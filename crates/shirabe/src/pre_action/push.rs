//! The push check: which non-merge commits a guarded `git push` would send,
//! and which of them carry an AI-attribution line (PRD R4, R14, R15;
//! DESIGN-pre-action-denies Decision 3).
//!
//! It parses the words after `push` against R4's option list (anything else
//! fails closed), resolves the remote and the sources, and reads the
//! outgoing commits with two bounded plumbing calls, after a few small
//! ones (`rev-parse`, `config`, `symbolic-ref`, `for-each-ref`) that find
//! the repository, the sources and the remote:
//!
//! ```text
//! git rev-list --no-merges --max-count=1001 <ids...> --not --remotes=<remote>
//! git cat-file --batch          # stdin: those ids, one per line
//! ```
//!
//! with `--remotes` alone when the remote is a URL or path, or has no
//! remote-tracking refs. The ids on `rev-list`'s command line are the
//! hexadecimal ids git returned, never the words the agent typed.
//!
//! Every git child runs through a [`GitRunner`]. The real one,
//! [`SystemGit`], runs from a fixed environment with the configuration that
//! runs a repository's programs switched off, closes stdin (except
//! `cat-file`'s), and kills a child that outlives the check's budget. A
//! repository the agent just made is fully agent-shaped, `.git/config`
//! included, so nothing it holds may run a program during the check.
//! `safe.directory` is left alone: a repository git refuses to read is the
//! "work tree" case.

use std::ffi::OsString;
use std::io::{Read, Write};
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::time::{Duration, Instant};

use shirabe_validate::is_attribution_line;

use super::classify::PushSegment;
use super::reason::Case;
use super::tokenize::Word;

/// How long the push check's git calls may take together (PRD R7 case 8),
/// unless `SHIRABE_PRE_ACTION_GIT_TIMEOUT` (whole seconds, for tests) says
/// otherwise.
pub const GIT_BUDGET: Duration = Duration::from_secs(20);

/// More outgoing commits than this fail closed rather than get their
/// messages read. `rev-list` is asked for one more, so 1,001 ids says the
/// bound is passed without listing the rest.
pub const MAX_COMMITS: usize = 1000;

/// The most commit-object bytes `cat-file` may return.
const MAX_OBJECTS: usize = 16 * 1024 * 1024;

/// The most bytes any other git call may print.
const MAX_LISTING: usize = 16 * 1024 * 1024;

/// How many offending commits a deny names before `and <n> more`.
const MAX_LISTED: usize = 10;

/// How many characters of a subject a deny keeps.
const MAX_SUBJECT: usize = 72;

/// The oldest git whose `GIT_NO_LAZY_FETCH` keeps a partial clone from
/// fetching a missing object.
const LAZY_FETCH_FLOOR: (u32, u32) = (2, 44);

/// The arguments every git child starts with, after `-C <dir>`.
const PREFIX: &[&str] = &[
    "--no-pager",
    "-c",
    "core.fsmonitor=false",
    "-c",
    "core.hooksPath=/dev/null",
    "-c",
    "log.showSignature=false",
    "-c",
    "core.pager=cat",
];

/// The variables every git child gets, beside the ones kept from the
/// hook's environment.
const FIXED_ENV: &[(&str, &str)] = &[
    ("GIT_CONFIG_NOSYSTEM", "1"),
    ("GIT_NO_LAZY_FETCH", "1"),
    ("GIT_NO_REPLACE_OBJECTS", "1"),
    ("GIT_OPTIONAL_LOCKS", "0"),
    ("GIT_TERMINAL_PROMPT", "0"),
    ("GIT_PAGER", "cat"),
];

/// Push options that don't change which commits are checked (PRD R4).
const FLAGS: &[&str] = &[
    "--force",
    "-f",
    "--force-with-lease",
    "--force-if-includes",
    "--set-upstream",
    "-u",
    "--dry-run",
    "-n",
    "--no-verify",
    "--verify",
    "--atomic",
    "--porcelain",
    "--quiet",
    "-q",
    "--verbose",
    "-v",
    "--progress",
    "--no-progress",
    "--follow-tags",
    "--no-follow-tags",
    "--thin",
    "--no-thin",
    "--signed",
    "--no-signed",
];

/// The same, given with `=<value>`.
const VALUED: &[&str] = &[
    "--force-with-lease=",
    "--signed=",
    "--push-option=",
    "--recurse-submodules=",
];

/// What a git child gave back.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct GitOut {
    /// The exit code; `None` when a signal ended it.
    pub code: Option<i32>,
    pub stdout: Vec<u8>,
}

impl GitOut {
    fn ok(&self) -> bool {
        self.code == Some(0)
    }
}

/// Why a git child gave nothing back.
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum GitError {
    /// No `git` on the absolute `PATH` entries.
    NotFound,
    /// It couldn't be started.
    Spawn(String),
    /// It was still running at the deadline, and was killed.
    Timeout,
    /// It printed more than the call allows, and was killed.
    TooLarge,
}

/// Runs one git child. Tests inject a fake or a [`SystemGit`] with a stub
/// on its `PATH`.
pub trait GitRunner {
    /// Run `git -C <dir> <PREFIX> <args>`, feeding `stdin` when given (stdin
    /// is closed otherwise), keeping at most `limit` bytes of stdout, and
    /// killing the child at `deadline`.
    fn run(
        &self,
        dir: &Path,
        args: &[&str],
        stdin: Option<Vec<u8>>,
        limit: usize,
        deadline: Instant,
    ) -> Result<GitOut, GitError>;
}

/// The real runner: the first executable `git` on the absolute `PATH`
/// entries, run from a fixed environment.
pub struct SystemGit {
    /// The absolute `PATH` entries `git` is looked for in.
    dirs: Vec<PathBuf>,
    /// The `git` found there, looked for on the first call only, so an
    /// evaluation with no push stats nothing.
    git: std::sync::OnceLock<Option<PathBuf>>,
    env: Vec<(OsString, OsString)>,
}

impl SystemGit {
    /// From this process's environment.
    pub fn from_env() -> Self {
        Self::with_env(std::env::vars_os())
    }

    /// From `vars`: it keeps only `PATH` (its absolute entries, so a
    /// repository can't plant a `git`), `HOME`, `XDG_CONFIG_HOME` and
    /// `GIT_CONFIG_GLOBAL` (where the user's global git configuration, and a
    /// `safe.directory` in it, is found), `LANG` and `LC_*`, and adds
    /// [`FIXED_ENV`].
    pub fn with_env(vars: impl IntoIterator<Item = (OsString, OsString)>) -> Self {
        const KEPT: &[&str] = &["HOME", "XDG_CONFIG_HOME", "GIT_CONFIG_GLOBAL", "LANG"];
        let mut env = Vec::new();
        let mut dirs: Vec<PathBuf> = Vec::new();
        for (k, v) in vars {
            if k == "PATH" {
                dirs = std::env::split_paths(&v)
                    .filter(|p| p.is_absolute())
                    .collect();
            } else if KEPT.iter().any(|kept| k == *kept) || k.to_string_lossy().starts_with("LC_") {
                env.push((k, v));
            }
        }
        if let Ok(path) = std::env::join_paths(&dirs) {
            env.push(("PATH".into(), path));
        }
        for (k, v) in FIXED_ENV {
            env.push(((*k).into(), (*v).into()));
        }
        SystemGit {
            dirs,
            git: std::sync::OnceLock::new(),
            env,
        }
    }
}

fn executable(p: &Path) -> bool {
    use std::os::unix::fs::PermissionsExt;
    std::fs::metadata(p).is_ok_and(|m| m.is_file() && m.permissions().mode() & 0o111 != 0)
}

/// How often a running child is polled.
const POLL: Duration = Duration::from_millis(2);

impl GitRunner for SystemGit {
    fn run(
        &self,
        dir: &Path,
        args: &[&str],
        stdin: Option<Vec<u8>>,
        limit: usize,
        deadline: Instant,
    ) -> Result<GitOut, GitError> {
        let git = self
            .git
            .get_or_init(|| {
                self.dirs
                    .iter()
                    .map(|d| d.join("git"))
                    .find(|p| executable(p))
            })
            .as_ref()
            .ok_or(GitError::NotFound)?;
        let mut child = Command::new(git)
            .env_clear()
            .envs(self.env.iter().map(|(k, v)| (k, v)))
            .arg("-C")
            .arg(dir)
            .args(PREFIX)
            .args(args)
            .stdin(if stdin.is_some() {
                Stdio::piped()
            } else {
                Stdio::null()
            })
            .stdout(Stdio::piped())
            .stderr(Stdio::null())
            .spawn()
            .map_err(|e| GitError::Spawn(e.to_string()))?;
        // Both pipes are served from their own threads, so a child that
        // writes while it reads (`cat-file --batch`) never stalls on a full
        // pipe. Neither thread is joined after a kill: a grandchild holding
        // the pipe open can't hold the check past its deadline.
        if let (Some(bytes), Some(mut w)) = (stdin, child.stdin.take()) {
            std::thread::spawn(move || {
                let _ = w.write_all(&bytes);
            });
        }
        let (tx, rx) = std::sync::mpsc::channel();
        if let Some(out) = child.stdout.take() {
            std::thread::spawn(move || {
                let mut buf = Vec::new();
                let read = out.take(limit as u64 + 1).read_to_end(&mut buf);
                let _ = tx.send(read.map(|_| buf));
            });
        }
        // Poll rather than wait: `wait` can't be given a deadline, and a
        // child is done only when it has exited and its stdout has been read
        // to the end, which arrive in either order. Output past `limit` ends
        // it early, since a child blocked on a full pipe would never exit.
        let mut status = None;
        let mut stdout = None;
        loop {
            if stdout.is_none() {
                if let Ok(read) = rx.try_recv() {
                    match read {
                        Ok(buf) if buf.len() > limit => {
                            let _ = child.kill();
                            let _ = child.wait();
                            return Err(GitError::TooLarge);
                        }
                        Ok(buf) => stdout = Some(buf),
                        Err(e) => {
                            let _ = child.kill();
                            let _ = child.wait();
                            return Err(GitError::Spawn(e.to_string()));
                        }
                    }
                }
            }
            if status.is_none() {
                match child.try_wait() {
                    Ok(s) => status = s,
                    Err(e) => {
                        let _ = child.kill();
                        let _ = child.wait();
                        return Err(GitError::Spawn(e.to_string()));
                    }
                }
            }
            if let (Some(s), Some(_)) = (status, &stdout) {
                return Ok(GitOut {
                    code: s.code(),
                    stdout: stdout.unwrap_or_default(),
                });
            }
            if Instant::now() >= deadline {
                let _ = child.kill();
                let _ = child.wait();
                return Err(GitError::Timeout);
            }
            std::thread::sleep(POLL);
        }
    }
}

/// The push check's budget: `SHIRABE_PRE_ACTION_GIT_TIMEOUT` when it is a
/// whole number of seconds above zero, else [`GIT_BUDGET`].
pub fn git_budget() -> Duration {
    budget_from(
        std::env::var("SHIRABE_PRE_ACTION_GIT_TIMEOUT")
            .ok()
            .as_deref(),
    )
}

fn budget_from(value: Option<&str>) -> Duration {
    value
        .and_then(|v| v.parse::<u64>().ok())
        .filter(|s| *s > 0)
        .map(Duration::from_secs)
        .unwrap_or(GIT_BUDGET)
}

/// An outgoing commit that carries an AI-attribution line.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Offender {
    /// The full hexadecimal id.
    pub id: String,
    /// The subject as git reads it: the message's first paragraph, its lines
    /// joined by spaces.
    pub subject: String,
}

/// The deny's details for `offenders` (PRD R5): each as its 12-character
/// hash and `subject: ` with its subject, control characters (and the
/// format characters [`hidden`] names) removed and cut to 72 characters, at most 10, then `and <n> more`.
pub fn details(offenders: &[Offender]) -> Vec<String> {
    let mut out: Vec<String> = offenders
        .iter()
        .take(MAX_LISTED)
        .map(|o| {
            let subject: String = o
                .subject
                .chars()
                .filter(|c| !hidden(*c))
                .take(MAX_SUBJECT)
                .collect();
            let hash: String = o.id.chars().take(12).collect();
            format!("{hash} subject: {subject}")
        })
        .collect();
    if offenders.len() > MAX_LISTED {
        out.push(format!("and {} more", offenders.len() - MAX_LISTED));
    }
    out
}

/// What the push's words say, before git is asked anything.
#[derive(Debug, Default, PartialEq, Eq)]
struct Argv<'a> {
    /// The first positional word.
    remote: Option<&'a Word>,
    /// `--repo=<remote>`, used when there is no positional remote.
    repo: Option<String>,
    /// Each refspec's source; an empty one is a deletion and isn't listed,
    /// and `:` alone sets `branches`.
    sources: Vec<String>,
    /// The push named refspecs, deletions included.
    refspecs: bool,
    branches: bool,
    tags: bool,
    delete: bool,
}

/// A word the shell would change before git sees it: an expansion,
/// `$'...'`, a leading `~`, a glob character, or a brace list or sequence.
/// The tokenizer doesn't record which characters were quoted, so a glob or
/// brace character counts wherever it is; a refspec glob would fail to
/// resolve anyway. `@{u}` holds no `,` or `..` and the shell leaves it.
fn opaque(w: &Word) -> bool {
    let t = w.text.as_str();
    let brace = t
        .split_once('{')
        .is_some_and(|(_, rest)| rest.contains(',') || rest.contains(".."));
    w.expansion || w.ansi_c || w.tilde || t.contains(['*', '?', '[']) || brace
}

/// A character a deny must not pass on from a commit subject: a control
/// character, or a format character that reorders or hides text (bidi
/// controls, zero-width characters, the byte-order mark).
fn hidden(c: char) -> bool {
    c.is_control()
        || matches!(
            c,
            '\u{061c}'
                | '\u{200b}'..='\u{200f}'
                | '\u{202a}'..='\u{202e}'
                | '\u{2060}'..='\u{2069}'
                | '\u{feff}'
        )
}

/// Parse the words after `push` against R4's option list.
fn parse(words: &[Word]) -> Result<Argv<'_>, Case> {
    let mut a = Argv::default();
    let mut positional: Vec<&Word> = Vec::new();
    let mut i = 0;
    while i < words.len() {
        let w = &words[i];
        let t = w.text.as_str();
        i += 1;
        if !t.starts_with('-') {
            positional.push(w);
            continue;
        }
        if opaque(w) {
            return Err(Case::PushOption(t.to_string()));
        }
        match t {
            "--all" | "--branches" => a.branches = true,
            "--tags" => a.tags = true,
            "--mirror" => {
                a.branches = true;
                a.tags = true;
            }
            "--delete" | "-d" => a.delete = true,
            "--push-option" | "-o" => i += 1,
            _ if FLAGS.contains(&t) => {}
            _ if VALUED.iter().any(|p| t.starts_with(p)) => {}
            _ if t.starts_with("--repo=") => a.repo = Some(t["--repo=".len()..].to_string()),
            _ => return Err(Case::PushOption(t.to_string())),
        }
    }
    let mut positional = positional.into_iter();
    a.remote = positional.next();
    for w in positional {
        a.refspecs = true;
        if opaque(w) {
            return Err(Case::Source(w.text.clone()));
        }
        let spec = w.text.strip_prefix('+').unwrap_or(&w.text);
        if a.delete {
            continue;
        }
        // `:` and `+:` push the matching branches, not a deletion; every
        // local branch is checked, as for `--all`.
        if spec == ":" {
            a.branches = true;
            continue;
        }
        let src = spec.split_once(':').map_or(spec, |(s, _)| s);
        if src.is_empty() {
            continue;
        }
        if src.starts_with('-') {
            return Err(Case::Source(src.to_string()));
        }
        a.sources.push(src.to_string());
    }
    Ok(a)
}

/// A remote name that can go into `--remotes=` and a ref path as it is.
fn plain_name(name: &str) -> bool {
    !name.is_empty()
        && name
            .bytes()
            .all(|b| b.is_ascii_alphanumeric() || matches!(b, b'.' | b'_' | b'-'))
}

fn hex_id(s: &str) -> bool {
    (s.len() == 40 || s.len() == 64) && s.bytes().all(|b| b.is_ascii_hexdigit())
}

/// `git version` output as `(major, minor)`.
fn version(out: &str) -> Option<(u32, u32)> {
    let v = out.split_whitespace().nth(2)?;
    let mut parts = v.split('.');
    let num = |p: Option<&str>| -> Option<u32> {
        let p = p?;
        let digits: String = p.chars().take_while(char::is_ascii_digit).collect();
        digits.parse().ok()
    };
    Some((num(parts.next())?, num(parts.next())?))
}

/// Which remote-tracking refs mark a commit as already sent.
enum Sent {
    Remote(String),
    AnyRemote,
}

/// One push check's git calls, all in the segment's directory and under
/// one deadline.
struct Repo<'a> {
    git: &'a dyn GitRunner,
    dir: &'a Path,
    deadline: Instant,
    budget: Duration,
}

impl Repo<'_> {
    fn call(&self, args: &[&str], stdin: Option<Vec<u8>>, limit: usize) -> Result<GitOut, Case> {
        self.git
            .run(self.dir, args, stdin, limit, self.deadline)
            .map_err(|e| {
                let sub = args.first().copied().unwrap_or("");
                Case::Git(match e {
                    GitError::NotFound => {
                        "no `git` was found on the absolute entries of `PATH`".to_string()
                    }
                    GitError::Spawn(e) => format!("`git {sub}` couldn't run: {e}"),
                    GitError::Timeout => format!(
                        "`git {sub}` ran past the push check's {}-second budget",
                        self.budget.as_secs()
                    ),
                    GitError::TooLarge => format!(
                        "`git {sub}` printed more than the {} MiB the check reads",
                        limit / (1024 * 1024)
                    ),
                })
            })
    }

    /// A call whose non-zero exit is a git failure; its stdout as text.
    fn text(&self, args: &[&str]) -> Result<String, Case> {
        let out = self.call(args, None, MAX_LISTING)?;
        if !out.ok() {
            let sub = args.first().copied().unwrap_or("");
            return Err(Case::Git(match out.code {
                Some(c) => format!("`git {sub}` failed with exit status {c}"),
                None => format!("`git {sub}` was killed by a signal"),
            }));
        }
        Ok(String::from_utf8_lossy(&out.stdout).into_owned())
    }

    /// `git config --get <key>`: `None` when it isn't set (exit 1).
    fn config(&self, key: &str) -> Result<Option<String>, Case> {
        let out = self.call(&["config", "--get", key], None, MAX_LISTING)?;
        match out.code {
            Some(0) => Ok(Some(
                String::from_utf8_lossy(&out.stdout).trim_end().to_string(),
            )),
            Some(1) => Ok(None),
            _ => Err(Case::Git(format!(
                "`git config --get {key}` failed with exit status {}",
                out.code.map_or("none".into(), |c| c.to_string())
            ))),
        }
    }

    /// The current branch, or `None` on a detached HEAD.
    fn branch(&self) -> Result<Option<String>, Case> {
        let out = self.call(&["symbolic-ref", "--quiet", "HEAD"], None, MAX_LISTING)?;
        match out.code {
            Some(0) => Ok(String::from_utf8_lossy(&out.stdout)
                .trim_end()
                .strip_prefix("refs/heads/")
                .map(str::to_string)),
            Some(1) => Ok(None),
            _ => Err(Case::Git(
                "`git symbolic-ref HEAD` failed, so the current branch is unknown".into(),
            )),
        }
    }

    /// `src` as a commit id, or the unresolved-source case.
    fn resolve(&self, src: &str) -> Result<String, Case> {
        let rev = format!("{src}^{{commit}}");
        let out = self.call(
            &["rev-parse", "--verify", "--quiet", "--end-of-options", &rev],
            None,
            MAX_LISTING,
        )?;
        let id = String::from_utf8_lossy(&out.stdout).trim_end().to_string();
        if out.ok() && hex_id(&id) {
            Ok(id)
        } else {
            Err(Case::Source(src.to_string()))
        }
    }

    /// The commits the refs under `prefix` point at, an annotated tag
    /// counting as its commit. A tag of a tree or a blob sends no commit.
    fn ref_commits(&self, prefix: &str) -> Result<Vec<String>, Case> {
        let listing = self.text(&[
            "for-each-ref",
            "--format=%(objectname) %(objecttype) %(*objecttype)",
            prefix,
        ])?;
        let mut ids = Vec::new();
        for line in listing.lines() {
            let mut f = line.split(' ');
            let (id, kind, peeled) = (f.next(), f.next(), f.next().unwrap_or(""));
            let (Some(id), Some(kind)) = (id, kind) else {
                continue;
            };
            if !hex_id(id) {
                return Err(Case::Git(format!(
                    "`git for-each-ref {prefix}` printed an id that isn't one"
                )));
            }
            // `rev-list` peels a tag to the commit it names.
            if kind == "commit" || (kind == "tag" && matches!(peeled, "commit" | "tag")) {
                ids.push(id.to_string());
            }
        }
        Ok(ids)
    }

    /// Which tracking refs count as sent for the push's remote `name`.
    fn sent(&self, name: &str) -> Result<Sent, Case> {
        if plain_name(name) {
            let refs = self.text(&[
                "for-each-ref",
                "--count=1",
                "--format=%(refname)",
                &format!("refs/remotes/{name}/"),
            ])?;
            // A plain name with tracking refs is checked against them even
            // when no remote by that name is configured (stale refs): that
            // checks more commits than the any-remote fallback, never fewer.
            return Ok(if refs.trim().is_empty() {
                Sent::AnyRemote
            } else {
                Sent::Remote(name.to_string())
            });
        }
        // Outside the plain-name pattern: a URL or a path, unless a remote
        // by that name is configured, whose name would be a glob in
        // `--remotes=`. A control character can't be part of a config key,
        // so that lookup can't tell; it fails closed instead.
        if name.chars().any(char::is_control)
            || self.config(&format!("remote.{name}.url"))?.is_some()
        {
            return Err(Case::Remote(name.to_string()));
        }
        Ok(Sent::AnyRemote)
    }
}

/// Check one push: the outgoing non-merge commits carrying an
/// AI-attribution line, in `rev-list` order, or the case that makes it
/// uncheckable. The git calls share `budget`. The classifier hands over at
/// most one push per command (a later push is a same-command case, since
/// the first changes the tracking refs it reads), so this is the call's
/// whole git budget.
pub fn check(
    seg: &PushSegment,
    git: &dyn GitRunner,
    budget: Duration,
) -> Result<Vec<Offender>, Case> {
    let argv = parse(&seg.words)?;
    let repo = Repo {
        git,
        dir: &seg.dir,
        deadline: Instant::now() + budget,
        budget,
    };

    let top = repo.call(&["rev-parse", "--show-toplevel"], None, MAX_LISTING)?;
    if !top.ok() {
        return Err(Case::WorkTree(seg.dir.clone()));
    }
    if repo.config("extensions.partialClone")?.is_some() {
        let v = repo.text(&["version"])?;
        if version(&v).is_none_or(|v| v < LAZY_FETCH_FLOOR) {
            return Err(Case::Git(format!(
                "the repository is a partial clone and `{}` is older than 2.44, which can't be kept from fetching missing objects",
                v.trim()
            )));
        }
    }

    // The current branch, asked only when the push needs it.
    let mut branch: Option<Option<String>> = None;
    let mut current = || -> Result<Option<String>, Case> {
        if branch.is_none() {
            branch = Some(repo.branch()?);
        }
        Ok(branch.clone().flatten())
    };

    let mut ids: Vec<String> = Vec::new();
    if argv.branches {
        ids.extend(repo.ref_commits("refs/heads/")?);
    }
    if argv.tags {
        ids.extend(repo.ref_commits("refs/tags/")?);
    }
    for src in &argv.sources {
        ids.push(repo.resolve(src)?);
    }
    if !argv.refspecs && !argv.branches && !argv.tags && !argv.delete {
        let Some(b) = current()? else {
            return Err(Case::DetachedHead);
        };
        ids.push(repo.resolve(&format!("refs/heads/{b}"))?);
    }
    ids.sort();
    ids.dedup();
    if ids.is_empty() {
        return Ok(Vec::new());
    }

    // Where it pushes, in git's order and PRD R4's: the positional word,
    // `--repo=`, then the branch's `pushRemote`, `remote.pushDefault`, the
    // branch's `remote`, and `origin`. An expanded `--repo=` word was refused
    // with the options in `parse`; the positional word is refused here, and
    // only when the push sends something.
    let remote = match (argv.remote, &argv.repo) {
        (Some(w), _) if opaque(w) => return Err(Case::Remote(w.text.clone())),
        (Some(w), _) => w.text.clone(),
        (None, Some(r)) => r.clone(),
        (None, None) => {
            let b = current()?;
            let mut found = None;
            if let Some(b) = &b {
                found = repo.config(&format!("branch.{b}.pushRemote"))?;
            }
            if found.is_none() {
                found = repo.config("remote.pushDefault")?;
            }
            if found.is_none() {
                if let Some(b) = &b {
                    found = repo.config(&format!("branch.{b}.remote"))?;
                }
            }
            found.unwrap_or_else(|| "origin".to_string())
        }
    };
    let not = match repo.sent(&remote)? {
        Sent::Remote(r) => format!("--remotes={r}"),
        Sent::AnyRemote => "--remotes".to_string(),
    };

    let max = format!("--max-count={}", MAX_COMMITS + 1);
    let mut args: Vec<&str> = vec!["rev-list", "--no-merges", &max];
    args.extend(ids.iter().map(String::as_str));
    args.push("--not");
    args.push(&not);
    // No paths: an id that is also a file name in the work tree isn't
    // ambiguous.
    args.push("--");
    let listing = repo.text(&args)?;
    let commits: Vec<&str> = listing.lines().collect();
    if let Some(bad) = commits.iter().find(|c| !hex_id(c)) {
        return Err(Case::Git(format!(
            "`git rev-list` printed `{}`, which isn't a commit id",
            bad.chars()
                .filter(|c| !c.is_control())
                .take(80)
                .collect::<String>()
        )));
    }
    if commits.len() > MAX_COMMITS {
        return Err(Case::TooManyCommits);
    }
    if commits.is_empty() {
        return Ok(Vec::new());
    }

    let mut input = commits.join("\n").into_bytes();
    input.push(b'\n');
    let out = repo.call(&["cat-file", "--batch"], Some(input), MAX_OBJECTS)?;
    if !out.ok() {
        return Err(Case::Git("`git cat-file --batch` failed".into()));
    }
    let objects = split_batch(&out.stdout, &commits)?;
    Ok(objects
        .into_iter()
        .zip(&commits)
        .filter_map(|(body, id)| {
            let message = message(body);
            message.lines().any(is_attribution_line).then(|| Offender {
                id: (*id).to_string(),
                subject: subject(&message),
            })
        })
        .collect())
}

/// `cat-file --batch` output, split into each commit's raw object by the
/// length in its header, in the order `ids` were asked for. No byte in a
/// message can break this framing.
fn split_batch<'b>(out: &'b [u8], ids: &[&str]) -> Result<Vec<&'b [u8]>, Case> {
    let bad = |why: &str| Case::Git(format!("`git cat-file --batch` {why}"));
    let mut objects = Vec::with_capacity(ids.len());
    let mut rest = out;
    for id in ids {
        let nl = rest
            .iter()
            .position(|b| *b == b'\n')
            .ok_or_else(|| bad("ended early"))?;
        let header = std::str::from_utf8(&rest[..nl]).map_err(|_| bad("printed a bad header"))?;
        let mut f = header.split(' ');
        let (oid, kind, size) = (f.next(), f.next(), f.next());
        if oid != Some(*id) || kind != Some("commit") {
            return Err(bad("didn't return the commit asked for"));
        }
        let size: usize = size
            .and_then(|s| s.parse().ok())
            .ok_or_else(|| bad("printed a bad size"))?;
        let start = nl + 1;
        let end = start
            .checked_add(size)
            .filter(|e| *e < rest.len() && rest[*e] == b'\n')
            .ok_or_else(|| bad("ended early"))?;
        objects.push(&rest[start..end]);
        rest = &rest[end + 1..];
    }
    Ok(objects)
}

/// A raw commit object's message: everything after the first blank line,
/// which ends the headers.
fn message(object: &[u8]) -> String {
    let at = object
        .windows(2)
        .position(|w| w == b"\n\n")
        .map_or(object.len(), |i| i + 2);
    String::from_utf8_lossy(&object[at..]).into_owned()
}

/// The subject: the message's first paragraph, its lines joined by spaces.
fn subject(message: &str) -> String {
    message
        .lines()
        .skip_while(|l| l.trim().is_empty())
        .take_while(|l| !l.trim().is_empty())
        .map(str::trim)
        .collect::<Vec<_>>()
        .join(" ")
}

#[cfg(test)]
#[path = "push_tests.rs"]
mod tests;
