//! The `shirabe compaction` subcommand: the two hook commands that let a
//! session compact in place and still find its way back to the skill and the
//! koto run it was in.
//!
//! - `pre-compact` runs as a PreCompact hook. It prints an instruction for the
//!   summary: name the koto session, branch, pull request, note key and the
//!   skills to re-read, and keep owner words, ids and hashes verbatim. When
//!   the note is stale it adds one line saying so; when its freshness can't
//!   be read it adds one line saying that instead.
//! - `re-anchor` runs as a SessionStart hook matched on `compact`. It prints a
//!   SessionStart hook JSON whose `additionalContext` tells the compacted
//!   session to re-read each recorded `SKILL.md`, run `koto status` on its
//!   koto session, and read its compaction note, before doing anything else.
//!   It runs the same freshness read and opens with its verdict: the note is
//!   fresh, stale, or its freshness couldn't be checked. A stale note gets a
//!   step, right after reading it, to rewrite it before any other work; one
//!   whose freshness is unknown gets a step to rewrite it first if koto shows
//!   the run past it. The verdict reaches the session here even when the
//!   summary doesn't carry pre-compact's line, or pre-compact never ran.
//!
//! Both read the hook JSON on stdin for `session_id` and look up the ledger
//! entry `scripts/handoff-brief.sh note` wrote for that session:
//! `$XDG_STATE_HOME/shirabe/compaction/<session-id>` (or the same path under
//! `$HOME/.local/state`). The entry is plain `key: value` lines:
//!
//! ```text
//! koto_session: <name>
//! note_key: compaction/note.md
//! branch: <branch>
//! repo: <the repository's top-level directory>
//! pr: <pull request URL, or none>
//! skill: <name> [<arg> ...] <plugin root>/skills/<dir>/SKILL.md
//! ```
//!
//! with one `skill:` line per active skill, outermost first. The `repo:` line
//! is there when `note` ran in a work tree.
//!
//! An entry is used only when the directory is a real 0700 directory (not a
//! link), the entry is a regular 0600 file opened through that directory
//! without following a link, every field passes its grammar, the skills of
//! one plugin share one plugin root, and its koto session equals
//! `KOTO_SESSION` where that is set. With no usable entry for a valid session
//! id, the hooks ask koto for the run the session's anchor holds (`koto
//! session hierarchy anchor-<session id> --json`, a held-by link named by
//! that anchor). Exactly one such run, still in a work tree, gives a pointer
//! like an entry's: the koto session, the directory it runs in, the branch
//! read live there, and the note only when koto lists it. Otherwise
//! `pre-compact` says no note is recorded and names the branch `git` reads in
//! its working directory, and `re-anchor` prints a generic line.
//!
//! The stale flag. The note is stale when the koto session moved on after
//! the note's last write, or the branch has a commit newer than that write.
//! koto's CLI prints no session-wide latest seq, so "moved on" is read
//! through calls that log no read: `koto context history` of the note gives
//! its last write's seq, timestamp and state; `koto status` gives the current
//! state (a transition after the note changes it); the run's event log,
//! `koto-<session>.state.jsonl` in the directory `koto session dir` prints,
//! gives every event's seq and type, so any event after the note's write
//! that moved the work on (evidence, a decision, an override, a transition
//! back to the same state) is seen; and `koto context list` plus `koto
//! context history` of each other key gives the latest write seq of every
//! key. In the log, a read (`context_read`), an import (`session_imported`)
//! and a key copied in by a cloud sync (`context_added` by writer `sync`)
//! don't count: none of them is work. The log is opened without following a
//! link and must be a regular file; only its last mebibyte is read, and a
//! tail that holds nothing older than the event right after the note can't
//! say what came between, so it leaves the freshness unknown. The branch's
//! tip commit time comes from `git log -1 --format=%ct refs/heads/<branch>`,
//! run in the entry's repository when that is still a work tree, else in the
//! hook's working directory. Every call is bounded in time. A check that
//! can't be read leaves the freshness unknown unless another check already
//! found the note stale.
//!
//! Both commands are fail-open: they always exit 0 and never block a
//! compaction. A session id that fails its grammar, or a hook input that
//! isn't JSON, means no output at all. Neither command ever prints the note's
//! text, a skill's text or any text from the hook input; they print where to
//! read them. Neither makes a `gh` call, and every `git` call runs with
//! `core.fsmonitor`, `core.hooksPath` and `log.showSignature` turned off.

use std::fs;
use std::io::Read;
use std::os::unix::fs::PermissionsExt;
use std::path::{Path, PathBuf};
use std::process::{Command, ExitCode, Stdio};
use std::sync::LazyLock;
use std::time::{Duration, Instant};

use clap::{Args, Subcommand};
use regex::Regex;

/// The one key a compaction note lives under in the session's koto session.
pub const NOTE_KEY: &str = "compaction/note.md";

/// SessionStart `additionalContext` is capped at 10,000 characters; the
/// re-anchor stays under it.
const CONTEXT_CAP: usize = 10_000;

/// The most skill lines a ledger entry may carry.
const MAX_SKILLS: usize = 8;

/// The most bytes read from a ledger entry. A real entry is a few hundred.
const MAX_LEDGER_BYTES: u64 = 16 * 1024;

/// The longest one koto or git call may run before it is killed and its
/// answer counted as unreadable.
const CALL_TIMEOUT: Duration = Duration::from_secs(5);

/// The longest the whole freshness read may take. Past it every call left
/// is unreadable, so the freshness is unknown.
const FRESHNESS_BUDGET: Duration = Duration::from_secs(20);

/// The most keys whose history the freshness read asks koto for. A session
/// with more is read up to this many and its freshness is unknown unless
/// one of them already shows the note stale.
const MAX_KEYS_SCANNED: usize = 256;

/// The most bytes read from one tool's stdout.
const MAX_TOOL_OUTPUT: u64 = 4 * 1024 * 1024;

/// The most bytes read from the end of the run's event log. An event line is
/// a few hundred bytes, so this holds the last few thousand events.
const LOG_TAIL_BYTES: u64 = 1024 * 1024;

/// The longest session directory path the freshness read accepts.
const MAX_SESSION_DIR: usize = 4096;

/// The most bytes read from the start of a run's event log for its header
/// line. A real header is under a kilobyte.
const MAX_HEADER_BYTES: u64 = 64 * 1024;

/// The flags every `git` call carries, so a repository's fsmonitor, hooks or
/// signature program (`gpg.program`, run by `git log` when the repository
/// sets `log.showSignature`) never run from a hook.
const GIT_SAFE: [&str; 6] = [
    "-c",
    "core.fsmonitor=false",
    "-c",
    "core.hooksPath=/dev/null",
    "-c",
    "log.showSignature=false",
];

/// The environment every `git` call carries, so a partial clone missing an
/// object never runs the promisor remote's transport
/// (`remote.<name>.uploadpack`, `core.sshCommand` or a remote helper), which
/// the `-c` flags above don't stop. `GIT_NO_LAZY_FETCH` stops the fetch, but
/// only git 2.44 and the May 2024 maintenance releases honour it; an older
/// git ignores it. An empty `GIT_ALLOW_PROTOCOL` allows no transport at all,
/// whatever the repository's `protocol.*.allow` says, so the fetch fails
/// before it runs anything on any git. Both are set: the first keeps the
/// fetch from starting where git honours it, and the second covers a git
/// that doesn't.
const GIT_ENV: [(&str, &str); 2] = [("GIT_NO_LAZY_FETCH", "1"), ("GIT_ALLOW_PROTOCOL", "")];

#[derive(Args)]
pub struct CompactionArgs {
    #[command(subcommand)]
    pub command: CompactionCommands,
}

#[derive(Subcommand)]
pub enum CompactionCommands {
    /// PreCompact hook. Reads the hook JSON on stdin for `session_id` and
    /// prints the summary instruction built from the session's ledger entry,
    /// with a line when the note is stale or its freshness can't be read.
    /// With no usable entry it says no note is recorded and names the branch.
    /// Prints nothing for an invalid session id. Always exits 0.
    PreCompact,
    /// SessionStart hook, matched on `compact`. Reads the hook JSON on stdin
    /// for `session_id` and prints a SessionStart hook JSON whose
    /// `additionalContext` sends the session back to its skills, its koto
    /// session and its note, or a generic line with no usable entry. Prints
    /// nothing for an invalid session id. Always exits 0.
    ReAnchor,
}

/// Entrypoint for `shirabe compaction`. Always returns `ExitCode::SUCCESS`.
pub fn run(command: &CompactionCommands) -> ExitCode {
    let input = read_stdin();
    let out = match command {
        CompactionCommands::PreCompact => pre_compact_output(&input),
        CompactionCommands::ReAnchor => re_anchor_output(&input),
    };
    if let Some(s) = out {
        println!("{s}");
    }
    ExitCode::SUCCESS
}

// --- grammars ----------------------------------------------------------------

static SID_RE: LazyLock<Regex> = LazyLock::new(|| Regex::new(r"^[A-Za-z0-9-]{1,64}$").unwrap());
static KOTO_SESSION_RE: LazyLock<Regex> =
    LazyLock::new(|| Regex::new(r"^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$").unwrap());
static BRANCH_RE: LazyLock<Regex> =
    LazyLock::new(|| Regex::new(r"^[A-Za-z0-9._/-]{1,200}$").unwrap());
static PR_RE: LazyLock<Regex> = LazyLock::new(|| {
    Regex::new(r"^https://github\.com/[A-Za-z0-9][A-Za-z0-9._-]{0,99}/[A-Za-z0-9._-]{1,100}/pull/[0-9]{1,10}$")
        .unwrap()
});
static SKILL_NAME_RE: LazyLock<Regex> =
    LazyLock::new(|| Regex::new(r"^[a-z0-9][a-z0-9-]{0,63}(:[a-z0-9][a-z0-9-]{0,63})?$").unwrap());
static SKILL_ARG_RE: LazyLock<Regex> =
    LazyLock::new(|| Regex::new(r"^[A-Za-z0-9._/=:@+,-]{1,200}$").unwrap());
static SKILL_PATH_RE: LazyLock<Regex> = LazyLock::new(|| {
    Regex::new(r"^/[A-Za-z0-9._/+@-]+/skills/[A-Za-z0-9._+@-]+/SKILL\.md$").unwrap()
});
/// koto's context key grammar: `/`-separated components, each starting with
/// a letter or digit.
static KOTO_KEY_RE: LazyLock<Regex> = LazyLock::new(|| {
    Regex::new(r"^[A-Za-z0-9][A-Za-z0-9._-]*(/[A-Za-z0-9][A-Za-z0-9._-]*)*$").unwrap()
});
static RFC3339_RE: LazyLock<Regex> = LazyLock::new(|| {
    Regex::new(
        r"^([0-9]{4})-([0-9]{2})-([0-9]{2})T([0-9]{2}):([0-9]{2}):([0-9]{2})(\.[0-9]{1,9})?(Z|[+-][0-9]{2}:[0-9]{2})$",
    )
    .unwrap()
});

fn valid_sid(sid: &str) -> bool {
    SID_RE.is_match(sid)
}

fn valid_branch(b: &str) -> bool {
    BRANCH_RE.is_match(b) && !b.contains("..") && !b.starts_with('-') && !b.starts_with('/')
}

/// A `SKILL.md` path: absolute, at most 512 bytes, no `..` component, and in
/// a plugin's layout, `<plugin root>/skills/<dir>/SKILL.md`.
fn valid_skill_path(p: &str) -> bool {
    p.len() <= 512 && SKILL_PATH_RE.is_match(p) && !p.split('/').any(|seg| seg == "..")
}

/// The plugin root of a valid `SKILL.md` path: everything before
/// `/skills/<dir>/SKILL.md`.
fn plugin_root(p: &str) -> Option<&str> {
    let rest = p.strip_suffix("/SKILL.md")?;
    let (rest, _dir) = rest.rsplit_once('/')?;
    let root = rest.strip_suffix("/skills")?;
    if root.is_empty() {
        None
    } else {
        Some(root)
    }
}

/// A character `has_bad_chars` in scripts/handoff-brief.sh refuses: a
/// control character (C0, DEL, C1), or a format character that hides or
/// reorders text (U+00AD, U+061C, U+200B-U+200F, U+2028-U+202E,
/// U+2060-U+2064, U+2066-U+2069, U+FEFF).
fn bad_char(c: char) -> bool {
    c.is_control()
        || matches!(
            c,
            '\u{ad}'
                | '\u{61c}'
                | '\u{200b}'..='\u{200f}'
                | '\u{2028}'..='\u{202e}'
                | '\u{2060}'..='\u{2064}'
                | '\u{2066}'..='\u{2069}'
                | '\u{feff}'
        )
}

/// A repository top-level: absolute, at most 512 bytes, and no control or
/// format character. `note` applies the same rule before it writes one.
fn valid_repo_path(p: &str) -> bool {
    p.starts_with('/') && p.len() <= 512 && !p.chars().any(bad_char)
}

fn valid_koto_key(k: &str) -> bool {
    k.len() <= 512 && KOTO_KEY_RE.is_match(k)
}

// --- the ledger entry ----------------------------------------------------------

/// One active skill: its name, the arguments it was invoked with, and the
/// path of its `SKILL.md`.
#[derive(Debug, Clone, PartialEq)]
pub struct Skill {
    pub name: String,
    pub args: Vec<String>,
    pub path: String,
}

/// A parsed, grammar-checked ledger entry, or the pointer the hooks derive
/// from koto when the session has none.
#[derive(Debug, Clone, PartialEq)]
pub struct Entry {
    pub koto_session: String,
    /// The note's key. A ledger entry always names one; a derived pointer
    /// names it only when koto lists the key for the run, and `None` means
    /// the run has no note to point at.
    pub note_key: Option<String>,
    pub branch: String,
    /// The repository top-level `note` ran in, when its line passed its
    /// grammar. A line that fails it is dropped here, not the entry: the
    /// branch is then read in the hook's working directory.
    pub repo: Option<String>,
    pub pr: Option<String>,
    pub skills: Vec<Skill>,
}

fn parse_skill(v: &str) -> Option<Skill> {
    let toks: Vec<&str> = v.split(' ').collect();
    if toks.len() < 2 || toks.iter().any(|t| t.is_empty()) {
        return None;
    }
    let name = toks[0];
    let path = toks[toks.len() - 1];
    let args = &toks[1..toks.len() - 1];
    if !SKILL_NAME_RE.is_match(name) || !valid_skill_path(path) {
        return None;
    }
    if !args.iter().all(|a| SKILL_ARG_RE.is_match(a)) {
        return None;
    }
    Some(Skill {
        name: name.to_string(),
        args: args.iter().map(|a| a.to_string()).collect(),
        path: path.to_string(),
    })
}

/// True when every skill of one plugin (the `<plugin>:` part of its name)
/// sits under one plugin root. A skill named without a plugin is checked for
/// its layout only.
fn one_root_per_plugin(skills: &[Skill]) -> bool {
    let mut seen: Vec<(&str, &str)> = Vec::new();
    for sk in skills {
        let root = match plugin_root(&sk.path) {
            Some(r) => r,
            None => return false,
        };
        let plugin = match sk.name.split_once(':') {
            Some((p, _)) => p,
            None => continue,
        };
        match seen.iter().find(|(p, _)| *p == plugin) {
            Some((_, r)) if *r != root => return false,
            Some(_) => {}
            None => seen.push((plugin, root)),
        }
    }
    true
}

/// Parse a ledger entry. Every field must pass its grammar, each of the four
/// single fields must appear exactly once, and the skills of one plugin must
/// share one plugin root; anything else is `None`. The `repo` line may appear
/// at most once; a value failing its grammar leaves `repo` empty and the
/// entry otherwise usable.
pub fn parse_entry(text: &str) -> Option<Entry> {
    let mut koto_session = None;
    let mut note_key = None;
    let mut branch = None;
    let mut repo_seen = false;
    let mut repo = None;
    let mut pr: Option<Option<String>> = None;
    let mut skills = Vec::new();
    for line in text.lines() {
        if line.is_empty() {
            continue;
        }
        let (k, v) = line.split_once(": ")?;
        match k {
            "koto_session" => {
                if koto_session.is_some() || !KOTO_SESSION_RE.is_match(v) {
                    return None;
                }
                koto_session = Some(v.to_string());
            }
            "note_key" => {
                if note_key.is_some() || v != NOTE_KEY {
                    return None;
                }
                note_key = Some(v.to_string());
            }
            "branch" => {
                if branch.is_some() || !valid_branch(v) {
                    return None;
                }
                branch = Some(v.to_string());
            }
            "repo" => {
                if repo_seen {
                    return None;
                }
                repo_seen = true;
                if valid_repo_path(v) {
                    repo = Some(v.to_string());
                }
            }
            "pr" => {
                if pr.is_some() {
                    return None;
                }
                if v == "none" {
                    pr = Some(None);
                } else if PR_RE.is_match(v) {
                    pr = Some(Some(v.to_string()));
                } else {
                    return None;
                }
            }
            "skill" => {
                if skills.len() >= MAX_SKILLS {
                    return None;
                }
                skills.push(parse_skill(v)?);
            }
            _ => return None,
        }
    }
    if !one_root_per_plugin(&skills) {
        return None;
    }
    Some(Entry {
        koto_session: koto_session?,
        note_key: Some(note_key?),
        branch: branch?,
        repo,
        pr: pr?,
        skills,
    })
}

/// The ledger directory: `$XDG_STATE_HOME/shirabe/compaction`, else
/// `$HOME/.local/state/shirabe/compaction`.
fn ledger_dir() -> Option<PathBuf> {
    let base = match std::env::var("XDG_STATE_HOME") {
        Ok(s) if !s.is_empty() => PathBuf::from(s),
        _ => {
            let home = std::env::var("HOME").ok().filter(|h| !h.is_empty())?;
            PathBuf::from(home).join(".local/state")
        }
    };
    Some(base.join("shirabe").join("compaction"))
}

/// Read the text of the entry `sid` in the ledger directory `dir`. The
/// directory is opened without following a link and must be a directory of
/// mode 0700; the entry is opened through that open directory, without
/// following a link and without waiting on a FIFO, and must be a regular file
/// of mode 0600. Anything else is `None`. The caller checks `sid` first, so
/// no name outside the directory is ever opened.
fn read_ledger_file(dir: &Path, sid: &str) -> Option<String> {
    use rustix::fs::{open, openat, Mode, OFlags};
    let dfd = open(
        dir,
        OFlags::RDONLY | OFlags::DIRECTORY | OFlags::NOFOLLOW | OFlags::CLOEXEC,
        Mode::empty(),
    )
    .ok()?;
    let dfile = fs::File::from(dfd);
    let dmeta = dfile.metadata().ok()?;
    if !dmeta.is_dir() || dmeta.permissions().mode() & 0o7777 != 0o700 {
        return None;
    }
    // O_NONBLOCK keeps the open from waiting on a FIFO at the entry path; the
    // regular-file check after the open then refuses it. Reads from a regular
    // file are unaffected.
    let fd = openat(
        &dfile,
        sid,
        OFlags::RDONLY | OFlags::NOFOLLOW | OFlags::NONBLOCK | OFlags::CLOEXEC,
        Mode::empty(),
    )
    .ok()?;
    let file = fs::File::from(fd);
    let meta = file.metadata().ok()?;
    if !meta.is_file() || meta.permissions().mode() & 0o7777 != 0o600 {
        return None;
    }
    let mut text = String::new();
    file.take(MAX_LEDGER_BYTES).read_to_string(&mut text).ok()?;
    Some(text)
}

/// Trust: where `KOTO_SESSION` is set, the entry must name that session.
fn trusted(entry: &Entry, koto_session_env: Option<&str>) -> bool {
    match koto_session_env {
        Some(ks) if !ks.is_empty() => ks == entry.koto_session,
        _ => true,
    }
}

/// The session's usable ledger entry, or `None`.
fn read_entry(sid: &str) -> Option<Entry> {
    if !valid_sid(sid) {
        return None;
    }
    let dir = ledger_dir()?;
    let entry = parse_entry(&read_ledger_file(&dir, sid)?)?;
    let ks = std::env::var("KOTO_SESSION").ok();
    if !trusted(&entry, ks.as_deref()) {
        return None;
    }
    Some(entry)
}

fn read_stdin() -> String {
    let mut s = String::new();
    let _ = std::io::stdin().take(1024 * 1024).read_to_string(&mut s);
    s
}

fn hook_sid(input: &str) -> Option<String> {
    let v: serde_json::Value = serde_json::from_str(input).ok()?;
    let sid = v.get("session_id")?.as_str()?;
    if valid_sid(sid) {
        Some(sid.to_string())
    } else {
        None
    }
}

fn skill_label(s: &Skill) -> String {
    if s.args.is_empty() {
        s.name.clone()
    } else {
        format!("{} {}", s.name, s.args.join(" "))
    }
}

// --- running koto and git --------------------------------------------------------

/// A deadline shared by every call of one freshness read.
struct Budget {
    deadline: Instant,
}

impl Budget {
    fn new(total: Duration) -> Budget {
        Budget {
            deadline: Instant::now() + total,
        }
    }

    /// Run `prog` (found on `PATH`) with `args`, stdin closed and stderr
    /// dropped, and return its stdout when it exits 0 within its time.
    /// Anything else (it can't start, fails, runs too long, prints too much
    /// or prints something that isn't UTF-8) is `None`.
    fn run(&self, prog: &str, args: &[&str]) -> Option<String> {
        let left = self.deadline.checked_duration_since(Instant::now())?;
        run_tool(prog, args, left.min(CALL_TIMEOUT))
    }
}

fn run_tool(prog: &str, args: &[&str], timeout: Duration) -> Option<String> {
    let mut cmd = Command::new(prog);
    if prog == "git" {
        cmd.envs(GIT_ENV);
    }
    let mut child = cmd
        .args(args)
        .stdin(Stdio::null())
        .stdout(Stdio::piped())
        .stderr(Stdio::null())
        .spawn()
        .ok()?;
    let out = child.stdout.take()?;
    // A reader thread, so a child that fills the pipe never stalls the wait.
    // Its result comes back over a channel and the thread is never joined: a
    // grandchild that inherited the pipe can hold it open after the child
    // exits, and the call still ends by its deadline.
    let (tx, rx) = std::sync::mpsc::channel();
    std::thread::spawn(move || {
        let mut buf = Vec::new();
        let ok = out.take(MAX_TOOL_OUTPUT + 1).read_to_end(&mut buf).is_ok();
        let _ = tx.send((ok, buf));
    });
    let deadline = Instant::now() + timeout;
    let status = loop {
        match child.try_wait() {
            Ok(Some(status)) => break status,
            Ok(None) if Instant::now() < deadline => {
                std::thread::sleep(Duration::from_millis(5));
            }
            _ => {
                let _ = child.kill();
                let _ = child.wait();
                return None;
            }
        }
    };
    // The child has exited; its stdout is read to the end only if that
    // happens before the deadline.
    let left = deadline.saturating_duration_since(Instant::now());
    let (ok, buf) = rx.recv_timeout(left).ok()?;
    if !ok || !status.success() || buf.len() as u64 > MAX_TOOL_OUTPUT {
        return None;
    }
    String::from_utf8(buf).ok()
}

/// The current branch `git` reads in the working directory, when it passes
/// the branch grammar.
fn cwd_branch(budget: &Budget) -> Option<String> {
    branch_in(None, budget)
}

/// The current branch `git` reads in `dir` (`git -C <dir>`), or in the
/// working directory when `dir` is `None`, when it passes the branch
/// grammar.
fn branch_in(dir: Option<&str>, budget: &Budget) -> Option<String> {
    let mut args: Vec<&str> = GIT_SAFE.to_vec();
    if let Some(d) = dir {
        args.extend(["-C", d]);
    }
    args.extend(["symbolic-ref", "--quiet", "--short", "HEAD"]);
    let out = budget.run("git", &args)?;
    let b = out.trim_end_matches('\n');
    if valid_branch(b) {
        Some(b.to_string())
    } else {
        None
    }
}

/// The entry's repository, when it is still one: not a link, a directory,
/// and inside a git work tree by git's own answer. `None` when the entry
/// records none or it fails a check; the branch is then read in the hook's
/// working directory.
fn entry_repo<'a>(e: &'a Entry, budget: &Budget) -> Option<&'a str> {
    work_tree(e.repo.as_deref()?, budget)
}

/// `repo`, when it is a directory that is not a link and is inside a git
/// work tree by git's own answer.
fn work_tree<'a>(repo: &'a str, budget: &Budget) -> Option<&'a str> {
    let meta = fs::symlink_metadata(repo).ok()?;
    if meta.file_type().is_symlink() || !meta.is_dir() {
        return None;
    }
    let mut args: Vec<&str> = GIT_SAFE.to_vec();
    args.extend(["-C", repo, "rev-parse", "--is-inside-work-tree"]);
    let out = budget.run("git", &args)?;
    if out.trim_end_matches('\n') == "true" {
        Some(repo)
    } else {
        None
    }
}

/// The commit time, in seconds since the epoch, of the tip of
/// `refs/heads/<branch>` in `repo`, or in the working directory's repository
/// when `repo` is `None`.
fn branch_commit_secs(branch: &str, repo: Option<&str>, budget: &Budget) -> Option<i64> {
    if !valid_branch(branch) {
        return None;
    }
    let refname = format!("refs/heads/{branch}");
    let mut args: Vec<&str> = GIT_SAFE.to_vec();
    if let Some(r) = repo {
        args.extend(["-C", r]);
    }
    args.extend([
        "log",
        "-1",
        "--no-show-signature",
        "--format=%ct",
        &refname,
        "--",
    ]);
    let out = budget.run("git", &args)?;
    out.trim().parse::<i64>().ok()
}

// --- the run the session's anchor holds ---------------------------------------------

/// The koto sessions a `koto session hierarchy <anchor> --json` answer shows
/// alive and held by `anchor`, in the order it lists them: members of kind
/// `koto_session`, with `alive` true and a `joined_by` element whose `via`
/// is `held-by link`, whose `holder` is the member itself and whose `named`
/// is the anchor. The hierarchy spans every session joined to the anchor
/// by any route, so each condition matters: another anchor, a session held
/// by another anchor, or a link this one didn't make is not this session's
/// run. Each name must pass koto's session grammar. `None` when the answer
/// isn't JSON with a `members` array.
pub fn parse_hierarchy(json: &str, anchor: &str) -> Option<Vec<String>> {
    let v: serde_json::Value = serde_json::from_str(json).ok()?;
    let mut runs: Vec<String> = Vec::new();
    for m in v.get("members")?.as_array()? {
        let field = |k: &str| m.get(k).and_then(|x| x.as_str());
        let Some(name) = field("name") else {
            continue;
        };
        if field("kind") != Some("koto_session")
            || m.get("alive").and_then(|a| a.as_bool()) != Some(true)
            || !KOTO_SESSION_RE.is_match(name)
        {
            continue;
        }
        let held = m
            .get("joined_by")
            .and_then(|j| j.as_array())
            .is_some_and(|links| {
                links.iter().any(|l| {
                    let link = |k: &str| l.get(k).and_then(|x| x.as_str());
                    link("via") == Some("held-by link")
                        && link("holder") == Some(name)
                        && link("named") == Some(anchor)
                })
            });
        if held && !runs.iter().any(|r| r == name) {
            runs.push(name.to_string());
        }
    }
    Some(runs)
}

/// The one koto run the session's anchor, `anchor-<session id>`, holds.
/// None, several, or an answer that can't be read is `None`: the hooks
/// never pick between runs, so a wrong one is never named.
fn anchored_run(sid: &str, budget: &Budget) -> Option<String> {
    let anchor = format!("anchor-{sid}");
    let out = budget.run("koto", &["session", "hierarchy", &anchor, "--json"])?;
    match parse_hierarchy(&out, &anchor)?.as_slice() {
        [one] => Some(one.clone()),
        _ => None,
    }
}

/// The `execution_dir` a run's event log header records.
fn header_execution_dir(head: &str) -> Option<String> {
    let v: serde_json::Value = serde_json::from_str(head).ok()?;
    v.get("execution_dir")?.as_str().map(str::to_string)
}

/// The `to` of the latest `execution_anchor_rebound` event in a log tail. A
/// tail that doesn't start the log drops its first, partial line.
fn rebound_to(tail: &LogTail) -> Option<String> {
    let text = String::from_utf8_lossy(&tail.bytes);
    let mut lines = text.split('\n');
    if !tail.whole {
        lines.next();
    }
    let mut to = None;
    for line in lines {
        let Ok(event) = serde_json::from_str::<serde_json::Value>(line) else {
            continue;
        };
        if event.get("type").and_then(|t| t.as_str()) != Some("execution_anchor_rebound") {
            continue;
        }
        if let Some(t) = event.pointer("/payload/to").and_then(|t| t.as_str()) {
            to = Some(t.to_string());
        }
    }
    to
}

/// The directory koto session `ks` runs in: the latest rebind in its event
/// log's tail when there is one, else the header's `execution_dir`. It must
/// pass the repository path grammar and still be a work tree.
fn run_dir(ks: &str, budget: &Budget) -> Option<String> {
    let path = run_log_path(ks, budget)?;
    let dir = read_log_tail(&path)
        .as_ref()
        .and_then(rebound_to)
        .or_else(|| {
            read_log_head(&path)
                .as_deref()
                .and_then(header_execution_dir)
        })?;
    if !valid_repo_path(&dir) {
        return None;
    }
    work_tree(&dir, budget).map(str::to_string)
}

/// The pointer for a session with no usable ledger entry, derived from koto
/// alone: the one run its anchor holds, the directory that run executes in,
/// the branch read live there, and the run's compaction note only when koto
/// lists the key. It reads koto and git and nothing else, so it is the same
/// whether the ledger has no entry or an entry it refused. `None`, and so
/// the generic text, when any of it can't be read, or `KOTO_SESSION` is set
/// to another session.
fn derived_entry(sid: &str, budget: &Budget) -> Option<Entry> {
    let ks = anchored_run(sid, budget)?;
    if let Ok(env) = std::env::var("KOTO_SESSION") {
        if !env.is_empty() && env != ks {
            return None;
        }
    }
    let dir = run_dir(&ks, budget)?;
    let branch = branch_in(Some(&dir), budget)?;
    let has_note = budget
        .run("koto", &["context", "list", &ks])
        .and_then(|j| parse_key_list(&j))
        .is_some_and(|keys| keys.iter().any(|k| k == NOTE_KEY));
    Some(Entry {
        koto_session: ks,
        note_key: has_note.then(|| NOTE_KEY.to_string()),
        branch,
        repo: Some(dir),
        pr: None,
        skills: Vec::new(),
    })
}

// --- the stale flag ----------------------------------------------------------------

/// Whether the compaction note is behind the work.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Freshness {
    /// Nothing happened in the koto session after the note's last write, and
    /// the branch has no newer commit.
    Fresh,
    /// The koto session moved on after the note's last write, or the branch
    /// has a newer commit.
    Stale,
    /// A check couldn't be read, and no other check found the note stale.
    Unknown,
}

/// One write of a key, as `koto context history` prints it.
#[derive(Debug, Clone, PartialEq)]
struct KeyWrite {
    seq: u64,
    secs: i64,
    state: Option<String>,
}

/// Seconds since the epoch for an RFC 3339 UTC-or-offset timestamp, as koto
/// writes them (`2026-01-01T00:00:02.123Z`). Fractions are dropped.
fn rfc3339_secs(s: &str) -> Option<i64> {
    let c = RFC3339_RE.captures(s)?;
    let n = |i: usize| c.get(i).unwrap().as_str().parse::<i64>().ok();
    let (y, mo, d, h, mi, se) = (n(1)?, n(2)?, n(3)?, n(4)?, n(5)?, n(6)?);
    if !(1..=12).contains(&mo) || !(1..=31).contains(&d) || h > 23 || mi > 59 || se > 60 {
        return None;
    }
    // Days from the civil date (Howard Hinnant's algorithm).
    let yy = if mo <= 2 { y - 1 } else { y };
    let era = (if yy >= 0 { yy } else { yy - 399 }) / 400;
    let yoe = yy - era * 400;
    let mp = (mo + 9) % 12;
    let doy = (153 * mp + 2) / 5 + d - 1;
    let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy;
    let days = era * 146_097 + doe - 719_468;
    let mut secs = days * 86_400 + h * 3_600 + mi * 60 + se;
    let tz = c.get(8).unwrap().as_str();
    if tz != "Z" {
        let sign = if tz.starts_with('-') { -1 } else { 1 };
        let oh = tz[1..3].parse::<i64>().ok()?;
        let om = tz[4..6].parse::<i64>().ok()?;
        secs -= sign * (oh * 3_600 + om * 60);
    }
    Some(secs)
}

/// Every write in a `koto context history` answer, oldest first. `None` when
/// the answer isn't a JSON array of writes each with a seq and a timestamp.
fn parse_history(json: &str) -> Option<Vec<KeyWrite>> {
    let v: serde_json::Value = serde_json::from_str(json).ok()?;
    let mut writes = Vec::new();
    for w in v.as_array()? {
        writes.push(KeyWrite {
            seq: w.get("seq")?.as_u64()?,
            secs: rfc3339_secs(w.get("timestamp")?.as_str()?)?,
            state: w.get("state").and_then(|s| s.as_str()).map(str::to_string),
        });
    }
    Some(writes)
}

/// The latest write in a history: the one with the highest seq.
fn latest(writes: &[KeyWrite]) -> Option<&KeyWrite> {
    writes.iter().max_by_key(|w| w.seq)
}

fn parse_current_state(json: &str) -> Option<String> {
    let v: serde_json::Value = serde_json::from_str(json).ok()?;
    v.get("current_state")?.as_str().map(str::to_string)
}

fn parse_key_list(json: &str) -> Option<Vec<String>> {
    let v: serde_json::Value = serde_json::from_str(json).ok()?;
    v.as_array()?
        .iter()
        .map(|k| k.as_str().map(str::to_string))
        .collect()
}

/// The end of a run's event log, as read: its bytes, and whether they are
/// the whole log.
struct LogTail {
    bytes: Vec<u8>,
    whole: bool,
}

/// The tail of the event log of koto session `ks`: the directory `koto
/// session dir` prints, which must be an absolute path with no control
/// character, and `koto-<ks>.state.jsonl` in it, opened without following a
/// link and without waiting on a FIFO, which must be a regular file. `ks`
/// passed its grammar when the entry was read, so the name has no `/`.
fn run_log_tail(ks: &str, budget: &Budget) -> Option<LogTail> {
    read_log_tail(&run_log_path(ks, budget)?)
}

/// Where koto session `ks` keeps its event log, with the checks
/// `run_log_tail` documents.
fn run_log_path(ks: &str, budget: &Budget) -> Option<PathBuf> {
    let out = budget.run("koto", &["session", "dir", ks])?;
    let dir = out.strip_suffix('\n').unwrap_or(&out);
    if !dir.starts_with('/') || dir.len() > MAX_SESSION_DIR || dir.chars().any(char::is_control) {
        return None;
    }
    Some(Path::new(dir).join(format!("koto-{ks}.state.jsonl")))
}

/// The event log at `path`, opened without following a link and without
/// waiting on a FIFO, when it is a regular file.
fn open_log(path: &Path) -> Option<(fs::File, u64)> {
    use rustix::fs::{open, Mode, OFlags};
    let fd = open(
        path,
        OFlags::RDONLY | OFlags::NOFOLLOW | OFlags::NONBLOCK | OFlags::CLOEXEC,
        Mode::empty(),
    )
    .ok()?;
    let file = fs::File::from(fd);
    let meta = file.metadata().ok()?;
    if !meta.is_file() {
        return None;
    }
    Some((file, meta.len()))
}

/// The first line of the event log at `path`: its header. Only the first
/// `MAX_HEADER_BYTES` are read, and a header longer than that is `None`.
fn read_log_head(path: &Path) -> Option<String> {
    let (file, _) = open_log(path)?;
    let mut bytes = Vec::new();
    file.take(MAX_HEADER_BYTES).read_to_end(&mut bytes).ok()?;
    let end = bytes.iter().position(|b| *b == b'\n')?;
    String::from_utf8(bytes[..end].to_vec()).ok()
}

fn read_log_tail(path: &Path) -> Option<LogTail> {
    use std::io::{Seek, SeekFrom};
    let (mut file, len) = open_log(path)?;
    let start = len.saturating_sub(LOG_TAIL_BYTES);
    file.seek(SeekFrom::Start(start)).ok()?;
    let mut bytes = Vec::new();
    file.take(LOG_TAIL_BYTES).read_to_end(&mut bytes).ok()?;
    Some(LogTail {
        bytes,
        whole: start == 0,
    })
}

/// Whether an event moved the work on. A read, an import and a key a cloud
/// sync copied in are not work; every other event is.
fn moves_work_on(event: &serde_json::Value, ty: &str) -> bool {
    match ty {
        "context_read" | "session_imported" => false,
        "context_added" => {
            event.pointer("/payload/writer").and_then(|w| w.as_str()) != Some("sync")
        }
        _ => true,
    }
}

/// What a log tail says about a note last written at `note_seq`:
/// `Some(true)` when an event after it moved the work on, `Some(false)` when
/// none did, and `None` when the tail can't tell: it holds no event, or it
/// starts past the event right after the note, so what came between isn't
/// in it. A tail that doesn't start the log starts mid-line, so its first
/// line is dropped. Lines that aren't an event (the log's header, a line
/// still being written) are passed over.
fn moved_on_after(tail: &LogTail, note_seq: u64) -> Option<bool> {
    let text = String::from_utf8_lossy(&tail.bytes);
    let mut lines = text.split('\n');
    if !tail.whole {
        lines.next();
    }
    let mut first_seq = None;
    for line in lines {
        let Ok(event) = serde_json::from_str::<serde_json::Value>(line) else {
            continue;
        };
        let (Some(seq), Some(ty)) = (
            event.get("seq").and_then(|s| s.as_u64()),
            event.get("type").and_then(|t| t.as_str()),
        ) else {
            continue;
        };
        first_seq.get_or_insert(seq);
        if seq > note_seq && moves_work_on(&event, ty) {
            return Some(true);
        }
    }
    let first_seq = first_seq?;
    if tail.whole || first_seq <= note_seq.saturating_add(1) {
        Some(false)
    } else {
        None
    }
}

/// Judge the entry's note against its koto session and its branch. An entry
/// with no note has nothing to judge, so its freshness is unknown; callers
/// don't ask for one.
fn note_freshness(e: &Entry, budget: &Budget) -> Freshness {
    let ks = e.koto_session.as_str();
    let Some(note_key) = e.note_key.as_deref() else {
        return Freshness::Unknown;
    };
    let note = match budget
        .run("koto", &["context", "history", ks, note_key])
        .and_then(|j| parse_history(&j))
    {
        Some(h) => match latest(&h) {
            Some(w) => w.clone(),
            None => return Freshness::Unknown,
        },
        None => return Freshness::Unknown,
    };
    let mut unknown = false;

    // A transition after the note leaves the run in another state.
    if let Some(at_note) = &note.state {
        match budget
            .run("koto", &["status", ks])
            .and_then(|j| parse_current_state(&j))
        {
            Some(now) if &now != at_note => return Freshness::Stale,
            Some(_) => {}
            None => unknown = true,
        }
    }

    // A commit on the branch newer than the note's write, in the entry's
    // repository when it still is one.
    let repo = entry_repo(e, budget);
    match branch_commit_secs(&e.branch, repo, budget) {
        Some(ct) if ct > note.secs => return Freshness::Stale,
        Some(_) => {}
        None => unknown = true,
    }

    // Any event after the note that moved the work on, whatever its kind.
    match run_log_tail(ks, budget).and_then(|t| moved_on_after(&t, note.seq)) {
        Some(true) => return Freshness::Stale,
        Some(false) => {}
        None => unknown = true,
    }

    // A key written after the note.
    match budget
        .run("koto", &["context", "list", ks])
        .and_then(|j| parse_key_list(&j))
    {
        Some(keys) => {
            if keys.len() > MAX_KEYS_SCANNED {
                unknown = true;
            }
            for k in keys.iter().take(MAX_KEYS_SCANNED) {
                if k == note_key {
                    continue;
                }
                if !valid_koto_key(k) {
                    unknown = true;
                    continue;
                }
                match budget
                    .run("koto", &["context", "history", ks, k])
                    .and_then(|j| parse_history(&j))
                {
                    Some(h) => {
                        if latest(&h).is_some_and(|w| w.seq > note.seq) {
                            return Freshness::Stale;
                        }
                    }
                    None => unknown = true,
                }
            }
        }
        None => unknown = true,
    }

    if unknown {
        Freshness::Unknown
    } else {
        Freshness::Fresh
    }
}

/// The line the summary instruction gains for a stale note or one whose
/// freshness can't be read; none for a fresh note.
pub fn freshness_line(f: Freshness) -> Option<&'static str> {
    match f {
        Freshness::Fresh => None,
        Freshness::Stale => Some(
            "The compaction note is stale: the koto session or the branch moved on after it was last written. Rewriting the note is the first step after the compaction; say so in the summary.",
        ),
        Freshness::Unknown => Some(
            "Whether the compaction note is current could not be checked (koto or git could not be read). After the compaction, read the note and rewrite it first if it is behind the work; say so in the summary.",
        ),
    }
}

/// The verdict the re-anchor opens with, for every freshness: the session
/// after a compaction hears it whichever it is.
pub fn re_anchor_verdict(f: Freshness) -> &'static str {
    match f {
        Freshness::Fresh => {
            "The compaction note is fresh: nothing in the koto session or on the branch came after its last write."
        }
        Freshness::Stale => {
            "The compaction note is stale: the koto session or the branch moved on after it was last written, so it is behind the work."
        }
        Freshness::Unknown => {
            "Whether the compaction note is current could not be checked (koto or git could not be read), so it may be behind the work."
        }
    }
}

/// The re-anchor step after reading the note, for a note that is stale or
/// may be; none for a fresh one.
pub fn re_anchor_rewrite_step(f: Freshness) -> Option<&'static str> {
    match f {
        Freshness::Fresh => None,
        Freshness::Stale => Some(
            "Rewrite the compaction note before any other work, with `handoff-brief.sh note` (scripts/handoff-brief.sh in the shirabe plugin), from where koto says the run stands.",
        ),
        Freshness::Unknown => Some(
            "If koto shows the run past what the note says, rewrite the note before any other work, with `handoff-brief.sh note` (scripts/handoff-brief.sh in the shirabe plugin).",
        ),
    }
}

// --- the outputs ---------------------------------------------------------------------

/// The summary instruction PreCompact prints, from a valid entry.
pub fn summary_instruction(e: &Entry) -> String {
    summary_with(e, None)
}

/// The summary instruction PreCompact prints from the pointer derived from
/// koto: the entry's lines, behind one saying where the run was found, with
/// the run's worktree among them.
pub fn derived_summary(e: &Entry) -> String {
    summary_with(e, Some(e.repo.as_deref().unwrap_or_default()))
}

fn summary_with(e: &Entry, worktree: Option<&str>) -> String {
    let mut s = String::new();
    s.push_str("When you write the summary of this session, carry the way back to its work.\n");
    if worktree.is_some() {
        s.push_str("No compaction ledger entry is recorded for this session; koto's held-by link from the session's anchor names the run below.\n");
    }
    s.push_str("Name each of these in the summary, exactly as written here:\n");
    s.push_str(&format!("- koto session: {}\n", e.koto_session));
    if let Some(w) = worktree {
        s.push_str(&format!("- worktree: {w}\n"));
    }
    s.push_str(&format!("- branch: {}\n", e.branch));
    s.push_str(&format!(
        "- pull request: {}\n",
        e.pr.as_deref().unwrap_or("none recorded")
    ));
    match &e.note_key {
        Some(k) => s.push_str(&format!(
            "- compaction note: key {} in koto session {}\n",
            k, e.koto_session
        )),
        None => s.push_str(&format!(
            "- compaction note: none recorded in koto session {}\n",
            e.koto_session
        )),
    }
    if !e.skills.is_empty() {
        s.push_str("- skills to re-read by path after the compaction, outermost first:\n");
        for sk in &e.skills {
            s.push_str(&format!("  - {} ({})\n", sk.path, skill_label(sk)));
        }
    }
    s.push_str("Keep verbatim any words the owner typed, and any ids and hashes still in play.");
    s
}

/// The summary instruction PreCompact prints when the session has no usable
/// ledger entry: no note is recorded, and the branch `git` read in the
/// hook's working directory, or a line saying it couldn't be read.
pub fn no_note_summary(branch: Option<&str>) -> String {
    let mut s = String::new();
    s.push_str("When you write the summary of this session, carry the way back to its work.\n");
    s.push_str("No compaction note is recorded for this session, so there is no recorded koto session, pull request or skill to name.\n");
    match branch {
        Some(b) => s.push_str(&format!(
            "Name this in the summary, exactly as written here:\n- branch: {b}\n"
        )),
        None => s.push_str(
            "The branch could not be read from git in this session's working directory.\n",
        ),
    }
    s.push_str("If the session was running a skill and a koto session, name both as the session knows them.\n");
    s.push_str("Keep verbatim any words the owner typed, and any ids and hashes still in play.");
    s
}

/// The re-anchor text the SessionStart hook carries, from a valid entry and
/// its note's freshness.
pub fn re_anchor_text(e: &Entry, f: Freshness) -> String {
    let mut s = format!(
        "This session was just compacted. {} Before doing anything else, in this order:\n",
        re_anchor_verdict(f)
    );
    let mut n = 1;
    for sk in &e.skills {
        s.push_str(&format!(
            "{n}. Read {} again: it is the instructions of the skill you were running ({}).\n",
            sk.path,
            skill_label(sk)
        ));
        n += 1;
    }
    s.push_str(&format!(
        "{n}. Run `koto status {}` to see where that run stands.\n",
        e.koto_session
    ));
    re_anchor_tail(&mut s, e, Some(f), n + 1);
    s
}

/// The re-anchor text from the pointer derived from koto, with the note's
/// freshness when the run has a note (`None` when it has none). It names
/// the run, its worktree and the branch read there, and no skill: koto
/// records none, so the session works the skill out from the run.
pub fn derived_re_anchor_text(e: &Entry, f: Option<Freshness>) -> String {
    let mut s = format!(
        "This session was just compacted. No compaction ledger entry is recorded for it; koto's held-by link from the session's anchor names its run, koto session {}, in worktree {}. {} Before doing anything else, in this order:\n",
        e.koto_session,
        e.repo.as_deref().unwrap_or_default(),
        match f {
            Some(f) => re_anchor_verdict(f),
            None => "That run has no compaction note recorded.",
        }
    );
    s.push_str(&format!(
        "1. In that worktree, run `koto status {}` to see where the run stands.\n",
        e.koto_session
    ));
    s.push_str("2. Work out the skill that run belongs to from its directive and its session name's prefix (`deliver-` is shirabe:deliver, `scope-` is shirabe:scope, `coordinate-` is shirabe:coordinate), and read that skill's SKILL.md again.\n");
    re_anchor_tail(&mut s, e, f, 3);
    s
}

/// The steps from the note on, numbered from `n`, and the closing line.
fn re_anchor_tail(s: &mut String, e: &Entry, f: Option<Freshness>, mut n: usize) {
    if let Some(k) = &e.note_key {
        s.push_str(&format!(
            "{n}. Read your compaction note, key {}, with `handoff-brief.sh read --note --session {}` (scripts/handoff-brief.sh in the shirabe plugin), which prints it as data.\n",
            k, e.koto_session
        ));
        if let Some(step) = f.and_then(re_anchor_rewrite_step) {
            n += 1;
            s.push_str(&format!("{n}. {step}\n"));
        }
    }
    s.push_str(&format!(
        "Then carry on from where koto says the run stands, on branch {}",
        e.branch
    ));
    if let Some(pr) = &e.pr {
        s.push_str(&format!(" (pull request {pr})"));
    }
    s.push('.');
}

/// The three steps both fixed re-anchor texts give: they name nothing read
/// from anywhere.
macro_rules! generic_steps {
    () => {
        "1. Work out the skill you were running from your koto session's name prefix (`deliver-` is shirabe:deliver, `scope-` is shirabe:scope, `coordinate-` is shirabe:coordinate), and read that skill's SKILL.md again.\n\
2. In your worktree, run `koto status` on that koto session (`koto workflows` lists the sessions there) to see where the run stands.\n\
3. Read your compaction note with `handoff-brief.sh read --note --session <koto session>` (scripts/handoff-brief.sh in the shirabe plugin), which prints it as data.\n"
    };
}

/// The line the fixed re-anchor texts end on.
macro_rules! generic_carry_on {
    () => {
        "Then carry on from where koto says the run stands."
    };
}

/// The opening of the re-anchor for an entry too long to show.
macro_rules! over_cap_head {
    () => {
        "This session was just compacted. Its compaction ledger entry is recorded but too long to show here."
    };
}

/// The re-anchor text for a session with no usable ledger entry. Fixed text:
/// it names nothing read from anywhere.
pub const GENERIC_RE_ANCHOR: &str = concat!(
    "This session was just compacted, and no compaction note is recorded for it. Before doing anything else, in this order:\n",
    generic_steps!(),
    generic_carry_on!()
);

/// The re-anchor text for a usable entry whose block would reach the cap,
/// with no freshness verdict: the generic steps behind a line saying the
/// entry was too long. Fixed text; `over_cap_re_anchor` adds the verdict.
pub const OVER_CAP_RE_ANCHOR: &str = concat!(
    over_cap_head!(),
    " Before doing anything else, in this order:\n",
    generic_steps!(),
    generic_carry_on!()
);

/// The re-anchor text for a usable entry whose block would reach the cap:
/// the generic steps behind a line saying the entry was too long, with the
/// note's freshness verdict and, for a note that is stale or may be, the
/// rewrite step. It names nothing read from the entry.
pub fn over_cap_re_anchor(f: Freshness) -> String {
    let mut s = format!(
        "{} {} Before doing anything else, in this order:\n{}",
        over_cap_head!(),
        re_anchor_verdict(f),
        generic_steps!()
    );
    if let Some(step) = re_anchor_rewrite_step(f) {
        s.push_str(&format!("4. {step}\n"));
    }
    s.push_str(generic_carry_on!());
    s
}

/// `pre-compact`'s stdout for a hook input, or `None` for no output.
pub fn pre_compact_output(input: &str) -> Option<String> {
    let sid = hook_sid(input)?;
    let budget = Budget::new(FRESHNESS_BUDGET);
    match read_entry(&sid) {
        Some(e) => {
            let mut s = summary_instruction(&e);
            if let Some(line) = freshness_line(note_freshness(&e, &budget)) {
                s.push('\n');
                s.push_str(line);
            }
            Some(s)
        }
        None => match derived_entry(&sid, &budget) {
            Some(e) => {
                let mut s = derived_summary(&e);
                if e.note_key.is_some() {
                    if let Some(line) = freshness_line(note_freshness(&e, &budget)) {
                        s.push('\n');
                        s.push_str(line);
                    }
                }
                Some(s)
            }
            None => Some(no_note_summary(cwd_branch(&budget).as_deref())),
        },
    }
}

/// `re-anchor`'s stdout for a hook input, or `None` for no output. With an
/// entry it judges the note's freshness, under the same time budget as
/// `pre-compact`, and carries the verdict. An entry whose block would reach
/// the cap gets the generic steps behind a line saying so, still with the
/// verdict. With no usable entry it looks for the run the session's anchor
/// holds, under the same budget, and names it; failing that, the generic
/// line.
pub fn re_anchor_output(input: &str) -> Option<String> {
    let sid = hook_sid(input)?;
    let budget = Budget::new(FRESHNESS_BUDGET);
    match read_entry(&sid) {
        Some(e) => {
            let f = note_freshness(&e, &budget);
            re_anchor_json(&e, f)
                .or_else(|| context_json(&over_cap_re_anchor(f)))
                .or_else(|| context_json(OVER_CAP_RE_ANCHOR))
        }
        None => match derived_entry(&sid, &budget) {
            Some(e) => {
                let f = e.note_key.is_some().then(|| note_freshness(&e, &budget));
                context_json(&derived_re_anchor_text(&e, f))
                    .or_else(|| context_json(GENERIC_RE_ANCHOR))
            }
            None => context_json(GENERIC_RE_ANCHOR),
        },
    }
}

/// The SessionStart hook JSON for an entry, withheld (`None`) rather than
/// truncated when its text would reach the 10,000-character cap.
fn re_anchor_json(e: &Entry, f: Freshness) -> Option<String> {
    context_json(&re_anchor_text(e, f))
}

/// A SessionStart hook JSON carrying `text` as `additionalContext`, or `None`
/// when the text would reach the cap.
fn context_json(text: &str) -> Option<String> {
    if text.chars().count() >= CONTEXT_CAP {
        return None;
    }
    let value = serde_json::json!({
        "hookSpecificOutput": {
            "hookEventName": "SessionStart",
            "additionalContext": text,
        }
    });
    serde_json::to_string(&value).ok()
}

#[cfg(test)]
mod tests {
    use super::*;

    const GOOD: &str = "koto_session: probe-run\n\
note_key: compaction/note.md\n\
branch: session/abc123\n\
pr: https://github.com/acme/widgets/pull/42\n\
skill: shirabe:deliver handoff-brief --no-merge /opt/plugins/shirabe/0.50.0/skills/deliver/SKILL.md\n\
skill: shirabe:scope handoff-brief /opt/plugins/shirabe/0.50.0/skills/scope/SKILL.md\n";

    #[test]
    fn parses_a_good_entry() {
        let e = parse_entry(GOOD).expect("parses");
        assert_eq!(e.koto_session, "probe-run");
        assert_eq!(
            e.pr.as_deref(),
            Some("https://github.com/acme/widgets/pull/42")
        );
        assert_eq!(e.skills.len(), 2);
        assert_eq!(e.skills[0].name, "shirabe:deliver");
        assert_eq!(e.skills[0].args, vec!["handoff-brief", "--no-merge"]);
        assert!(e.skills[1].path.ends_with("/scope/SKILL.md"));
    }

    #[test]
    fn pr_none_is_accepted() {
        let t = GOOD.replace("pr: https://github.com/acme/widgets/pull/42", "pr: none");
        assert_eq!(parse_entry(&t).unwrap().pr, None);
    }

    #[test]
    fn refuses_bad_fields() {
        for (from, to) in [
            ("koto_session: probe-run", "koto_session: ../x"),
            ("note_key: compaction/note.md", "note_key: brief/x.md"),
            ("branch: session/abc123", "branch: a..b"),
            (
                "pr: https://github.com/acme/widgets/pull/42",
                "pr: http://evil/pull/1",
            ),
            (
                "/opt/plugins/shirabe/0.50.0/skills/scope/SKILL.md",
                "/opt/../etc/SKILL.md",
            ),
            (
                "/opt/plugins/shirabe/0.50.0/skills/scope/SKILL.md",
                "relative/SKILL.md",
            ),
            ("shirabe:scope handoff-brief", "shirabe:scope $(id)"),
        ] {
            let t = GOOD.replace(from, to);
            assert!(parse_entry(&t).is_none(), "accepted {to}");
        }
    }

    #[test]
    fn refuses_duplicate_and_unknown_keys() {
        assert!(parse_entry(&format!("{GOOD}branch: other\n")).is_none());
        assert!(parse_entry(&format!("{GOOD}extra: x\n")).is_none());
        assert!(parse_entry("koto_session: a\n").is_none());
    }

    #[test]
    fn skill_path_length_is_capped_at_512() {
        let at = format!("/{}/skills/x/SKILL.md", "p".repeat(512 - 19));
        assert_eq!(at.len(), 512);
        assert!(valid_skill_path(&at));
        let over = format!("/{}/skills/x/SKILL.md", "p".repeat(512 - 18));
        assert!(!valid_skill_path(&over));
    }

    #[test]
    fn sid_grammar() {
        assert!(valid_sid("4f08fec0-0720-4fdd-ab29-5f0583eb2031"));
        for bad in ["", "a/b", "..", "a\nb", "a.b", &"x".repeat(65)] {
            assert!(!valid_sid(bad), "accepted {bad:?}");
        }
    }

    #[test]
    fn summary_names_everything_and_inlines_nothing() {
        let e = parse_entry(GOOD).unwrap();
        let s = summary_instruction(&e);
        for want in [
            "probe-run",
            "session/abc123",
            "https://github.com/acme/widgets/pull/42",
            "compaction/note.md",
            "/opt/plugins/shirabe/0.50.0/skills/deliver/SKILL.md",
            "verbatim",
        ] {
            assert!(s.contains(want), "missing {want}");
        }
    }

    #[test]
    fn re_anchor_orders_skills_then_status_then_note() {
        let e = parse_entry(GOOD).unwrap();
        for f in [Freshness::Fresh, Freshness::Stale, Freshness::Unknown] {
            let t = re_anchor_text(&e, f);
            let deliver = t.find("skills/deliver/SKILL.md").unwrap();
            let scope = t.find("skills/scope/SKILL.md").unwrap();
            let status = t.find("koto status probe-run").unwrap();
            let note = t
                .find("handoff-brief.sh read --note --session probe-run")
                .unwrap();
            assert!(deliver < scope && scope < status && status < note);
            assert!(t.chars().count() < CONTEXT_CAP);
        }
    }

    #[test]
    fn re_anchor_opens_with_the_verdict_and_puts_a_rewrite_after_the_note() {
        let e = parse_entry(GOOD).unwrap();
        for f in [Freshness::Fresh, Freshness::Stale, Freshness::Unknown] {
            let t = re_anchor_text(&e, f);
            let verdict = re_anchor_verdict(f);
            assert!(t.starts_with(&format!(
                "This session was just compacted. {verdict} Before"
            )));
            let note = t.find("handoff-brief.sh read --note").unwrap();
            let carry_on = t.find("Then carry on").unwrap();
            match re_anchor_rewrite_step(f) {
                Some(step) => {
                    // Numbered after the note's step: two skills, status,
                    // note, then the rewrite.
                    let at = t.find(&format!("5. {step}\n")).expect("rewrite step");
                    assert!(note < at && at < carry_on);
                }
                None => assert!(!t.contains("handoff-brief.sh note")),
            }
        }
    }

    #[test]
    fn the_re_anchor_verdicts() {
        let fresh = re_anchor_verdict(Freshness::Fresh);
        let stale = re_anchor_verdict(Freshness::Stale);
        let unknown = re_anchor_verdict(Freshness::Unknown);
        assert!(fresh.contains("is fresh") && !fresh.contains("stale"));
        assert!(stale.contains("is stale") && !stale.contains("fresh"));
        assert!(unknown.contains("could not be checked"));
        assert!(!unknown.contains("is fresh") && !unknown.contains("is stale"));
        for v in [fresh, stale, unknown] {
            assert!(!v.contains('\n'));
        }
        assert_eq!(re_anchor_rewrite_step(Freshness::Fresh), None);
        let stale_step = re_anchor_rewrite_step(Freshness::Stale).unwrap();
        assert!(stale_step.starts_with("Rewrite the compaction note before any other work"));
        let unknown_step = re_anchor_rewrite_step(Freshness::Unknown).unwrap();
        assert!(unknown_step.contains("before any other work"));
        for s in [stale_step, unknown_step] {
            assert!(s.contains("`handoff-brief.sh note`") && !s.contains('\n'));
        }
    }

    #[test]
    fn the_over_cap_re_anchor_carries_the_verdict() {
        for f in [Freshness::Fresh, Freshness::Stale, Freshness::Unknown] {
            let t = over_cap_re_anchor(f);
            assert!(t.contains("too long to show"));
            assert!(t.contains(re_anchor_verdict(f)));
            assert!(t.contains("handoff-brief.sh read --note --session"));
            assert!(!t.contains("no compaction note is recorded"));
            assert!(t.ends_with("Then carry on from where koto says the run stands."));
            assert_eq!(
                t.contains("4. "),
                re_anchor_rewrite_step(f).is_some(),
                "{t}"
            );
            assert!(t.chars().count() < CONTEXT_CAP);
        }
    }

    fn tail(lines: &[&str], whole: bool) -> LogTail {
        LogTail {
            bytes: lines.join("\n").into_bytes(),
            whole,
        }
    }

    #[test]
    fn a_log_tail_sees_an_event_that_moved_the_work_on() {
        let header = r#"{"schema_version":1,"workflow":"k"}"#;
        let note = r#"{"seq":5,"timestamp":"t","type":"context_added","payload":{"key":"compaction/note.md"}}"#;
        let evidence = r#"{"seq":6,"timestamp":"t","type":"evidence_submitted","payload":{}}"#;
        let read = r#"{"seq":6,"timestamp":"t","type":"context_read","payload":{}}"#;
        let import = r#"{"seq":7,"timestamp":"t","type":"session_imported","payload":{}}"#;
        let sync =
            r#"{"seq":8,"timestamp":"t","type":"context_added","payload":{"writer":"sync"}}"#;
        let agent =
            r#"{"seq":8,"timestamp":"t","type":"context_added","payload":{"writer":"agent"}}"#;
        assert_eq!(moved_on_after(&tail(&[header, note], true), 5), Some(false));
        assert_eq!(
            moved_on_after(&tail(&[header, note, evidence], true), 5),
            Some(true)
        );
        assert_eq!(
            moved_on_after(&tail(&[header, note, read, import, sync], true), 5),
            Some(false)
        );
        assert_eq!(
            moved_on_after(&tail(&[header, note, read, agent], true), 5),
            Some(true)
        );
        // An event at the note's own seq or before it never counts.
        assert_eq!(
            moved_on_after(&tail(&[header, evidence], true), 6),
            Some(false)
        );
        // A trailing newline, a line still being written, and the header are
        // passed over.
        assert_eq!(
            moved_on_after(&tail(&[header, note, "", r#"{"seq":9,"#], true), 5),
            Some(false)
        );
        // No event at all can't tell.
        assert_eq!(moved_on_after(&tail(&[header], true), 5), None);
        assert_eq!(moved_on_after(&tail(&["", "not json"], true), 5), None);
    }

    #[test]
    fn a_partial_log_tail_drops_its_first_line_and_must_reach_the_note() {
        let cut = r#"type":"evidence_submitted","seq":99}"#;
        let note = r#"{"seq":5,"timestamp":"t","type":"context_added","payload":{}}"#;
        let next_read = r#"{"seq":6,"timestamp":"t","type":"context_read","payload":{}}"#;
        let late_read = r#"{"seq":40,"timestamp":"t","type":"context_read","payload":{}}"#;
        let late_work = r#"{"seq":41,"timestamp":"t","type":"decision_recorded","payload":{}}"#;
        // The cut first line is dropped, even when it would parse.
        let whole_line = r#"{"seq":99,"timestamp":"t","type":"evidence_submitted","payload":{}}"#;
        assert_eq!(
            moved_on_after(&tail(&[whole_line, note], false), 5),
            Some(false)
        );
        assert_eq!(
            moved_on_after(&tail(&[cut, note, next_read], false), 5),
            Some(false)
        );
        // A tail starting right after the note still sees everything after it.
        assert_eq!(
            moved_on_after(&tail(&[cut, next_read], false), 5),
            Some(false)
        );
        // A tail of reads that starts well past the note can't tell.
        assert_eq!(moved_on_after(&tail(&[cut, late_read], false), 5), None);
        // But work anywhere in it after the note is enough.
        assert_eq!(
            moved_on_after(&tail(&[cut, late_read, late_work], false), 5),
            Some(true)
        );
    }

    fn entry_with(skills: usize, arg_len: usize, args: usize) -> Entry {
        let path = format!("/{}/skills/n/SKILL.md", "p".repeat(470));
        let argv = vec!["a".repeat(arg_len); args].join(" ");
        let mut t =
            String::from("koto_session: k\nnote_key: compaction/note.md\nbranch: b\npr: none\n");
        for _ in 0..skills {
            t.push_str(&format!("skill: n {argv} {path}\n"));
        }
        parse_entry(&t).unwrap()
    }

    #[test]
    fn re_anchor_json_is_hook_shaped() {
        let e = parse_entry(GOOD).unwrap();
        let j: serde_json::Value =
            serde_json::from_str(&re_anchor_json(&e, Freshness::Fresh).unwrap()).unwrap();
        assert_eq!(j["hookSpecificOutput"]["hookEventName"], "SessionStart");
        assert!(j["hookSpecificOutput"]["additionalContext"]
            .as_str()
            .unwrap()
            .contains("koto status probe-run"));
    }

    #[test]
    fn re_anchor_is_withheld_at_the_cap_not_truncated() {
        // Eight skills with long paths and short arguments fit.
        for f in [Freshness::Fresh, Freshness::Stale, Freshness::Unknown] {
            let fits = entry_with(MAX_SKILLS, 20, 3);
            assert!(re_anchor_json(&fits, f).is_some());
            // Eight skills each carrying 4,000 characters of arguments don't.
            let over = entry_with(MAX_SKILLS, 200, 20);
            assert!(re_anchor_text(&over, f).chars().count() >= CONTEXT_CAP);
            assert!(re_anchor_json(&over, f).is_none());
        }
    }

    #[test]
    fn more_than_max_skills_is_refused() {
        let mut t =
            String::from("koto_session: k\nnote_key: compaction/note.md\nbranch: b\npr: none\n");
        for _ in 0..=MAX_SKILLS {
            t.push_str("skill: n /a/skills/n/SKILL.md\n");
        }
        assert!(parse_entry(&t).is_none());
    }

    #[test]
    fn bad_hook_input_gives_no_sid() {
        assert!(hook_sid("not json").is_none());
        assert!(hook_sid(r#"{"session_id":"../../etc"}"#).is_none());
        assert!(hook_sid(r#"{"session_id":"a\nb"}"#).is_none());
        assert_eq!(
            hook_sid(r#"{"session_id":"abc-1"}"#).as_deref(),
            Some("abc-1")
        );
    }

    #[test]
    fn max_skills_exactly_is_accepted() {
        let mut t =
            String::from("koto_session: k\nnote_key: compaction/note.md\nbranch: b\npr: none\n");
        for _ in 0..MAX_SKILLS {
            t.push_str("skill: n /a/skills/n/SKILL.md\n");
        }
        assert_eq!(parse_entry(&t).unwrap().skills.len(), MAX_SKILLS);
    }

    #[test]
    fn a_skill_path_outside_a_plugin_root_is_refused() {
        // Not in a plugin's layout: no skills/<dir>/ above SKILL.md.
        for bad in [
            "/opt/plugins/shirabe/0.50.0/deliver/SKILL.md",
            "/skills/deliver/SKILL.md",
            "/opt/plugins/shirabe/0.50.0/skills/SKILL.md",
        ] {
            let t = GOOD.replace("/opt/plugins/shirabe/0.50.0/skills/deliver/SKILL.md", bad);
            assert!(parse_entry(&t).is_none(), "accepted {bad}");
        }
        // Two skills of one plugin under two roots.
        let t = GOOD.replace(
            "/opt/plugins/shirabe/0.50.0/skills/scope/SKILL.md",
            "/tmp/elsewhere/skills/scope/SKILL.md",
        );
        assert!(parse_entry(&t).is_none());
    }

    #[test]
    fn skills_of_different_plugins_may_have_different_roots() {
        let t = GOOD.replace(
            "skill: shirabe:scope handoff-brief /opt/plugins/shirabe/0.50.0/skills/scope/SKILL.md",
            "skill: other:tool /opt/plugins/other/1.0.0/skills/tool/SKILL.md\nskill: bare /home/u/.claude/skills/bare/SKILL.md",
        );
        let e = parse_entry(&t).expect("parses");
        assert_eq!(e.skills.len(), 3);
        assert_eq!(
            plugin_root(&e.skills[1].path),
            Some("/opt/plugins/other/1.0.0")
        );
    }

    #[test]
    fn a_branch_with_a_control_character_is_refused() {
        for bad in ["session/a\u{7}b", "session/a\tb", "session/a\u{1b}[0m"] {
            let t = GOOD.replace("branch: session/abc123", &format!("branch: {bad}"));
            assert!(parse_entry(&t).is_none(), "accepted {bad:?}");
        }
    }

    #[test]
    fn koto_session_must_match_where_set() {
        let e = parse_entry(GOOD).unwrap();
        assert!(trusted(&e, None));
        assert!(trusted(&e, Some("")));
        assert!(trusted(&e, Some("probe-run")));
        assert!(!trusted(&e, Some("someone-else")));
    }

    #[test]
    fn rfc3339_to_epoch_seconds() {
        assert_eq!(rfc3339_secs("1970-01-01T00:00:00Z"), Some(0));
        assert_eq!(rfc3339_secs("2026-01-01T00:00:02Z"), Some(1_767_225_602));
        assert_eq!(
            rfc3339_secs("2026-01-01T00:00:02.999Z"),
            Some(1_767_225_602)
        );
        assert_eq!(rfc3339_secs("2024-02-29T12:00:00Z"), Some(1_709_208_000));
        assert_eq!(
            rfc3339_secs("2026-01-01T02:00:02+02:00"),
            Some(1_767_225_602)
        );
        assert_eq!(
            rfc3339_secs("2025-12-31T23:00:02-01:00"),
            Some(1_767_225_602)
        );
        for bad in [
            "",
            "2026-01-01",
            "2026-13-01T00:00:00Z",
            "2026-01-01T24:00:00Z",
            "2026-01-01 00:00:00Z",
            "2026-01-01T00:00:00",
        ] {
            assert_eq!(rfc3339_secs(bad), None, "parsed {bad:?}");
        }
    }

    #[test]
    fn history_parses_and_the_latest_is_the_highest_seq() {
        let h = parse_history(
            r#"[{"seq":3,"timestamp":"2026-01-01T00:00:02.000Z","writer":"agent","hash":"h","size":1,"state":"work"},
                {"seq":9,"timestamp":"2026-01-01T00:01:00.000Z","writer":"agent","hash":"h","size":1,"state":null}]"#,
        )
        .unwrap();
        let w = latest(&h).unwrap();
        assert_eq!(w.seq, 9);
        assert_eq!(w.secs, 1_767_225_660);
        assert_eq!(w.state, None);
        assert_eq!(h[0].state.as_deref(), Some("work"));
        assert!(latest(&parse_history("[]").unwrap()).is_none());
        for bad in [
            "",
            "{}",
            r#"[{"seq":"x","timestamp":"2026-01-01T00:00:02Z"}]"#,
            r#"[{"seq":1}]"#,
            r#"[{"seq":1,"timestamp":"yesterday"}]"#,
        ] {
            assert!(parse_history(bad).is_none(), "parsed {bad:?}");
        }
    }

    #[test]
    fn status_and_list_parse() {
        assert_eq!(
            parse_current_state(r#"{"current_state":"work","is_terminal":false}"#).as_deref(),
            Some("work")
        );
        assert!(parse_current_state(r#"{"current_state":null}"#).is_none());
        assert!(parse_current_state("not json").is_none());
        assert_eq!(
            parse_key_list(r#"["a","b/c"]"#).unwrap(),
            vec!["a".to_string(), "b/c".to_string()]
        );
        assert!(parse_key_list(r#"["a",1]"#).is_none());
    }

    #[test]
    fn the_hierarchy_keeps_only_live_runs_the_anchor_holds() {
        let a = "anchor-s1";
        let held = |h: &str, n: &str| serde_json::json!([{"holder": h, "named": n, "target": n, "via": "held-by link"}]);
        let m = |kind: &str, name: &str, alive: bool, links: serde_json::Value| serde_json::json!({"kind": kind, "name": name, "alive": alive, "joined_by": links});
        let json = serde_json::json!({"session": a, "members": [
            m("anchor", a, true, serde_json::json!([])),
            m("koto_session", "run-a", true, held("run-a", a)),
            m("koto_session", "run-a", true, held("run-a", a)),
            m("koto_session", "dead", false, held("dead", a)),
            m("koto_session", "elsewhere", true, held("elsewhere", "anchor-s2")),
            m("koto_session", "via-other", true, held("someone", a)),
            m("anchor_close", "close", true, held("close", a)),
            m("koto_session", "-bad", true, held("-bad", a)),
            m("koto_session", "parent", true,
              serde_json::json!([{"holder": "parent", "named": a, "via": "parent link"}])),
            serde_json::json!({"kind": "koto_session", "name": "no-links", "alive": true}),
            m("koto_session", "run-b", true, serde_json::json!([
                {"via": "parent link", "holder": "x", "named": "y"},
                {"via": "held-by link", "holder": "run-b", "named": a}])),
        ]})
        .to_string();
        assert_eq!(parse_hierarchy(&json, a).unwrap(), vec!["run-a", "run-b"]);
        assert_eq!(
            parse_hierarchy(&json, "anchor-s2").unwrap(),
            vec!["elsewhere"]
        );
        assert_eq!(
            parse_hierarchy(r#"{"members": []}"#, a).unwrap(),
            Vec::<String>::new()
        );
        for bad in [
            "",
            "not json",
            "[]",
            r#"{"members": 7}"#,
            r#"{"session": "x"}"#,
        ] {
            assert!(parse_hierarchy(bad, a).is_none(), "{bad}");
        }
    }

    #[test]
    fn the_execution_dir_is_the_latest_rebind_else_the_header() {
        assert_eq!(
            header_execution_dir(r#"{"schema_version":1,"execution_dir":"/w/a"}"#).as_deref(),
            Some("/w/a")
        );
        assert!(header_execution_dir(r#"{"schema_version":1}"#).is_none());
        assert!(header_execution_dir(r#"{"execution_dir":7}"#).is_none());
        assert!(header_execution_dir("not json").is_none());
        let rb = |seq: u64, to: &str| {
            format!(
                r#"{{"seq":{seq},"type":"execution_anchor_rebound","payload":{{"from":"/x","to":"{to}"}}}}"#
            )
        };
        let t = tail(
            &[
                r#"{"schema_version":1,"execution_dir":"/w/a"}"#,
                &rb(2, "/w/b"),
                r#"{"seq":3,"type":"transitioned"}"#,
                &rb(4, "/w/c"),
            ],
            true,
        );
        assert_eq!(rebound_to(&t).as_deref(), Some("/w/c"));
        assert!(rebound_to(&tail(&[r#"{"seq":3,"type":"transitioned"}"#], true)).is_none());
        // A partial tail drops its first line, rebind or not.
        assert!(rebound_to(&tail(&[&rb(2, "/w/b"), r#"{"seq":3,"type":"x"}"#], false)).is_none());
    }

    #[test]
    fn koto_key_grammar() {
        for good in ["compaction/note.md", "brief/files/abc", "a", "a.b-c_d/e"] {
            assert!(valid_koto_key(good), "refused {good}");
        }
        for bad in [
            "", "-x", "/a", "a/", "a//b", "a/./b", "a/../b", "a b", "a\nb",
        ] {
            assert!(!valid_koto_key(bad), "accepted {bad:?}");
        }
    }

    #[test]
    fn the_freshness_lines() {
        assert_eq!(freshness_line(Freshness::Fresh), None);
        let stale = freshness_line(Freshness::Stale).unwrap();
        assert!(stale.contains("stale") && stale.contains("first step after the compaction"));
        assert!(!stale.contains('\n'));
        let unknown = freshness_line(Freshness::Unknown).unwrap();
        assert!(unknown.contains("could not be checked") && !unknown.contains("is stale"));
        assert!(!unknown.contains('\n'));
    }

    #[test]
    fn no_note_summary_names_the_branch_or_says_it_is_unread() {
        let s = no_note_summary(Some("work/x"));
        assert!(s.contains("No compaction note is recorded"));
        assert!(s.contains("- branch: work/x\n"));
        assert!(s.chars().count() < CONTEXT_CAP);
        let s = no_note_summary(None);
        assert!(s.contains("could not be read from git"));
        assert!(s.chars().count() < CONTEXT_CAP);
    }

    #[test]
    fn the_generic_re_anchor_line() {
        for want in [
            "`deliver-`",
            "`scope-`",
            "`coordinate-`",
            "SKILL.md",
            "koto status",
            "worktree",
            "handoff-brief.sh read --note",
        ] {
            assert!(GENERIC_RE_ANCHOR.contains(want), "missing {want}");
        }
        let j: serde_json::Value =
            serde_json::from_str(&context_json(GENERIC_RE_ANCHOR).unwrap()).unwrap();
        assert_eq!(j["hookSpecificOutput"]["hookEventName"], "SessionStart");
        assert!(GENERIC_RE_ANCHOR.chars().count() < CONTEXT_CAP);
    }

    #[test]
    fn a_repo_line_is_kept_when_it_passes_its_grammar() {
        let t = GOOD.replace(
            "branch: session/abc123\n",
            "branch: session/abc123\nrepo: /home/u/work/widgets\n",
        );
        let e = parse_entry(&t).expect("parses");
        assert_eq!(e.repo.as_deref(), Some("/home/u/work/widgets"));
        assert_eq!(parse_entry(GOOD).unwrap().repo, None);
    }

    #[test]
    fn a_repo_line_failing_its_grammar_is_dropped_not_the_entry() {
        let long = format!("/{}", "r".repeat(512));
        for bad in [
            "relative/path",
            "/a\u{7}b",
            "/a\tb",
            "/a\u{200b}b",
            "/a\u{202e}b",
            "/a\u{feff}b",
            "/a\u{85}b",
            long.as_str(),
        ] {
            let t = GOOD.replace(
                "branch: session/abc123\n",
                &format!("branch: session/abc123\nrepo: {bad}\n"),
            );
            let e = parse_entry(&t).unwrap_or_else(|| panic!("entry refused for {bad:?}"));
            assert_eq!(e.repo, None, "kept {bad:?}");
        }
        let at = format!("/{}", "r".repeat(511));
        assert!(valid_repo_path(&at));
        // Two repo lines are a malformed entry, like any repeated field.
        let t = format!("{GOOD}repo: /a\nrepo: /b\n");
        assert!(parse_entry(&t).is_none());
    }

    #[test]
    fn the_over_cap_re_anchor_line_does_not_say_no_note_is_recorded() {
        assert!(!OVER_CAP_RE_ANCHOR.contains("no compaction note is recorded"));
        assert!(OVER_CAP_RE_ANCHOR.contains("too long to show"));
        assert!(OVER_CAP_RE_ANCHOR.contains("handoff-brief.sh read --note --session"));
        assert!(GENERIC_RE_ANCHOR.contains("no compaction note is recorded"));
        assert!(OVER_CAP_RE_ANCHOR.chars().count() < CONTEXT_CAP);
    }

    // --- the ledger file's checks ---------------------------------------------

    struct Dir(PathBuf);
    impl Drop for Dir {
        fn drop(&mut self) {
            let _ = fs::remove_dir_all(&self.0);
        }
    }

    fn ledger_fixture(tag: &str) -> (Dir, PathBuf) {
        let root =
            std::env::temp_dir().join(format!("shirabe-ledger-{}-{}", std::process::id(), tag));
        let _ = fs::remove_dir_all(&root);
        let dir = root.join("compaction");
        fs::create_dir_all(&dir).unwrap();
        fs::set_permissions(&dir, fs::Permissions::from_mode(0o700)).unwrap();
        let entry = dir.join("sid-1");
        fs::write(&entry, GOOD).unwrap();
        fs::set_permissions(&entry, fs::Permissions::from_mode(0o600)).unwrap();
        (Dir(root), dir)
    }

    #[test]
    fn ledger_file_good() {
        let (_g, dir) = ledger_fixture("good");
        assert_eq!(read_ledger_file(&dir, "sid-1").as_deref(), Some(GOOD));
        assert!(read_ledger_file(&dir, "sid-2").is_none());
    }

    #[test]
    fn ledger_file_wrong_modes() {
        let (_g, dir) = ledger_fixture("modes");
        for m in [0o644, 0o640, 0o400, 0o700, 0o4600] {
            fs::set_permissions(dir.join("sid-1"), fs::Permissions::from_mode(m)).unwrap();
            assert!(
                read_ledger_file(&dir, "sid-1").is_none(),
                "entry {m:o} used"
            );
        }
        fs::set_permissions(dir.join("sid-1"), fs::Permissions::from_mode(0o600)).unwrap();
        for m in [0o755, 0o750, 0o711] {
            fs::set_permissions(&dir, fs::Permissions::from_mode(m)).unwrap();
            assert!(read_ledger_file(&dir, "sid-1").is_none(), "dir {m:o} used");
        }
        fs::set_permissions(&dir, fs::Permissions::from_mode(0o700)).unwrap();
        assert!(read_ledger_file(&dir, "sid-1").is_some());
    }

    #[test]
    fn ledger_file_links_and_non_files() {
        let (g, dir) = ledger_fixture("links");
        // A symlinked entry pointing at a good 0600 file.
        let target = g.0.join("target");
        fs::write(&target, GOOD).unwrap();
        fs::set_permissions(&target, fs::Permissions::from_mode(0o600)).unwrap();
        std::os::unix::fs::symlink(&target, dir.join("sid-link")).unwrap();
        assert!(read_ledger_file(&dir, "sid-link").is_none());
        // A directory at the entry path.
        fs::create_dir(dir.join("sid-dir")).unwrap();
        fs::set_permissions(dir.join("sid-dir"), fs::Permissions::from_mode(0o600)).unwrap();
        assert!(read_ledger_file(&dir, "sid-dir").is_none());
        fs::set_permissions(dir.join("sid-dir"), fs::Permissions::from_mode(0o700)).unwrap();
        // A symlinked directory pointing at a good 0700 directory.
        let linked = g.0.join("linked");
        std::os::unix::fs::symlink(&dir, &linked).unwrap();
        assert!(read_ledger_file(&linked, "sid-1").is_none());
        assert!(read_ledger_file(&dir, "sid-1").is_some());
    }
}
