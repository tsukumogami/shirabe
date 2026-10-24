//! The push check's tests. The argv parse and the output framing are tested
//! on their own; every outcome PRD R4 states is tested end to end through
//! `evaluate`, in scratch repositories under the temp directory: a bare
//! `origin` and `fork`, and `work`, a clone with `main` pushed to both.

use std::cell::Cell;
use std::ffi::OsString;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::sync::atomic::{AtomicUsize, Ordering};

use super::super::tokenize::tokenize;
use super::super::{evaluate, Ctx, RegistrySource, RuleSet};
use super::*;

const TRAILER: &str = "feat: add x\n\nCo-Authored-By: Claude <noreply@anthropic.com>\n";
const CLEAN: &str = "feat: add y\n\nPlain body.\n";

// --- the parse and the framing ---------------------------------------------

fn words(cmd: &str) -> Vec<Word> {
    tokenize(cmd).expect("tokenizes").segments[0].words.clone()
}

#[test]
fn the_argv_names_the_remote_and_the_sources() {
    let ws = words("--force origin +topic HEAD:refs/heads/x :gone -o ci.skip --repo=fork");
    let a = parse(&ws).unwrap();
    assert_eq!(a.remote.map(|w| w.text.as_str()), Some("origin"));
    assert_eq!(a.repo.as_deref(), Some("fork"));
    assert_eq!(a.sources, vec!["topic", "HEAD"]);
    assert!(a.refspecs);

    let ws = words("origin --delete topic other");
    let a = parse(&ws).unwrap();
    assert!(a.delete && a.refspecs && a.sources.is_empty());

    let ws = words("--mirror");
    let a = parse(&ws).unwrap();
    assert!(a.branches && a.tags && a.remote.is_none() && !a.refspecs);

    let ws = words("--push-option x origin main");
    assert_eq!(parse(&ws).unwrap().sources, vec!["main"]);

    // `:` and `+:` push the matching branches, checked as every branch.
    for spec in [":", "+:"] {
        let ws = words(&format!("origin {spec}"));
        let a = parse(&ws).unwrap();
        assert!(a.branches && a.refspecs && a.sources.is_empty(), "{spec}");
    }
    let ws = words("origin --delete :");
    assert!(!parse(&ws).unwrap().branches);
}

#[test]
fn the_argv_refuses_what_it_cant_follow() {
    for (cmd, case) in [
        (
            "--some-new-option",
            Case::PushOption("--some-new-option".into()),
        ),
        ("--", Case::PushOption("--".into())),
        ("-fu origin", Case::PushOption("-fu".into())),
        ("--repo fork", Case::PushOption("--repo".into())),
        (
            "--recurse-submodules",
            Case::PushOption("--recurse-submodules".into()),
        ),
        ("origin +-x", Case::Source("-x".into())),
        ("origin -x:y", Case::PushOption("-x:y".into())),
        ("origin \"$B\"", Case::Source("$B".into())),
        ("--repo=\"$R\"", Case::PushOption("--repo=$R".into())),
        (
            "origin 'refs/heads/*:refs/heads/*'",
            Case::Source("refs/heads/*:refs/heads/*".into()),
        ),
        ("origin ma?n", Case::Source("ma?n".into())),
        ("origin m[a]in", Case::Source("m[a]in".into())),
        ("origin {main,topic}", Case::Source("{main,topic}".into())),
    ] {
        let ws = words(cmd);
        assert_eq!(parse(&ws).err(), Some(case), "{cmd}");
    }
}

#[test]
fn a_word_the_shell_would_glob_or_brace_expand_is_opaque_but_at_brace_is_not() {
    for (w, want) in [
        ("or*", true),
        ("{origin,fork}", true),
        ("{a..c}", true),
        ("main@{u}", false),
        ("HEAD@{1}", false),
        ("origin", false),
    ] {
        assert_eq!(opaque(&words(w)[0]), want, "{w}");
    }
}

#[test]
fn a_plain_remote_name_is_letters_digits_dot_underscore_and_dash() {
    for ok in ["origin", "my-fork", "a.b_c", "."] {
        assert!(plain_name(ok), "{ok}");
    }
    for bad in ["", "fo+o", "a/b", "a*", "https://x/y.git", "a b"] {
        assert!(!plain_name(bad), "{bad}");
    }
}

#[test]
fn the_git_version_is_read_as_major_and_minor() {
    assert_eq!(
        version("git version 2.39.5 (Apple Git-154)\n"),
        Some((2, 39))
    );
    assert_eq!(version("git version 2.44.0"), Some((2, 44)));
    assert_eq!(version("git version 2.45.1.windows.1"), Some((2, 45)));
    assert_eq!(version("nonsense"), None);
    assert!(Some((2, 43)) < Some(LAZY_FETCH_FLOOR));
}

#[test]
fn the_batch_output_is_split_by_length_and_the_message_by_the_blank_line() {
    let a = "a".repeat(40);
    let b = "b".repeat(40);
    // A message holding a fake header and blank lines can't shift the frame.
    let obj1 = "tree x\nauthor y\n\nsubject one\n\n0000 commit 3\nzz\n";
    let obj2 = "tree x\n\nCo-Authored-By: Claude <x>";
    let out = format!(
        "{a} commit {}\n{obj1}\n{b} commit {}\n{obj2}\n",
        obj1.len(),
        obj2.len()
    );
    let objs = split_batch(out.as_bytes(), &[&a, &b]).unwrap();
    assert_eq!(objs, vec![obj1.as_bytes(), obj2.as_bytes()]);
    assert_eq!(message(objs[0]), "subject one\n\n0000 commit 3\nzz\n");
    assert_eq!(subject(&message(objs[0])), "subject one");
    assert_eq!(
        subject("\n  first line\n second line \n\nbody"),
        "first line second line"
    );
    assert!(message(objs[1]).lines().any(is_attribution_line));

    for (bad, ids) in [
        (format!("{a} missing\n"), vec![a.as_str()]),
        (format!("{a} commit 99\nshort\n"), vec![a.as_str()]),
        (format!("{b} commit 1\nx\n"), vec![a.as_str()]),
        (format!("{a} tree 1\nx\n"), vec![a.as_str()]),
    ] {
        assert!(
            matches!(split_batch(bad.as_bytes(), &ids), Err(Case::Git(_))),
            "{bad}"
        );
    }
}

#[test]
fn offenders_are_listed_by_hash_and_a_cleaned_subject() {
    let long = format!("feat: \u{1b}[31mred\u{7}\t{}", "x".repeat(100));
    let mut offenders = vec![Offender {
        id: "0123456789abcdef".repeat(3)[..40].to_string(),
        subject: long,
    }];
    let d = details(&offenders);
    assert_eq!(d.len(), 1);
    assert!(
        d[0].starts_with("0123456789ab subject: feat: [31mred"),
        "{}",
        d[0]
    );
    assert!(!d[0].chars().any(char::is_control), "{:?}", d[0]);
    assert_eq!(d[0].chars().count(), "0123456789ab subject: ".len() + 72);

    let d = details(&[Offender {
        id: "a".repeat(40),
        subject: "x\u{202e}y\u{200b}z\u{2066}w\u{feff}".into(),
    }]);
    assert_eq!(d[0], "aaaaaaaaaaaa subject: xyzw");

    for i in 0..11 {
        offenders.push(Offender {
            id: format!("{i:040}"),
            subject: format!("c{i}"),
        });
    }
    let d = details(&offenders);
    assert_eq!(d.len(), 11);
    assert_eq!(d[10], "and 2 more");
}

#[test]
fn the_budget_variable_is_whole_seconds() {
    assert_eq!(budget_from(Some("1")), Duration::from_secs(1));
    for v in [None, Some("0"), Some("x"), Some("-1"), Some("")] {
        assert_eq!(budget_from(v), GIT_BUDGET, "{v:?}");
    }
    assert_eq!(GIT_BUDGET, Duration::from_secs(20));
}

// --- scratch repositories ----------------------------------------------------

struct Scratch {
    root: PathBuf,
}

impl Scratch {
    fn empty() -> Self {
        static N: AtomicUsize = AtomicUsize::new(0);
        let root = std::env::temp_dir().join(format!(
            "shirabe-push-{}-{}",
            std::process::id(),
            N.fetch_add(1, Ordering::SeqCst)
        ));
        let _ = std::fs::remove_dir_all(&root);
        std::fs::create_dir_all(root.join("home")).unwrap();
        Scratch { root }
    }

    /// `origin.git` and `fork.git` (bare), and `work`, with one commit on
    /// `main` pushed to both.
    fn repo() -> Self {
        let s = Self::empty();
        s.git("", &["init", "-q", "--bare", "-b", "main", "origin.git"]);
        s.git("", &["init", "-q", "--bare", "-b", "main", "fork.git"]);
        s.git("", &["init", "-q", "-b", "main", "work"]);
        s.git("work", &["remote", "add", "origin", &s.dir("origin.git")]);
        s.git("work", &["remote", "add", "fork", &s.dir("fork.git")]);
        s.commit("chore: base");
        s.git("work", &["push", "-q", "origin", "main"]);
        s.git("work", &["push", "-q", "fork", "main"]);
        s
    }

    fn path(&self, rel: &str) -> PathBuf {
        self.root.join(rel)
    }

    fn dir(&self, rel: &str) -> String {
        self.path(rel).to_str().unwrap().to_string()
    }

    fn setup_git(&self, rel: &str, args: &[&str]) -> Command {
        let mut c = Command::new("git");
        c.current_dir(self.path(rel))
            .env_clear()
            .env("PATH", std::env::var_os("PATH").unwrap_or_default())
            .env("HOME", self.path("home"))
            .env("GIT_CONFIG_NOSYSTEM", "1")
            .args(["-c", "user.name=t", "-c", "user.email=t@example.com"])
            .args(["-c", "commit.gpgSign=false", "-c", "tag.gpgSign=false"])
            .args(args);
        c
    }

    /// Run a setup git in `rel`; its stdout, trimmed.
    fn git(&self, rel: &str, args: &[&str]) -> String {
        self.git_with(rel, args, None)
    }

    fn git_with(&self, rel: &str, args: &[&str], stdin: Option<&[u8]>) -> String {
        let mut c = self.setup_git(rel, args);
        c.stdin(Stdio::piped())
            .stdout(Stdio::piped())
            .stderr(Stdio::piped());
        let mut child = c.spawn().unwrap();
        let mut input = child.stdin.take().unwrap();
        if let Some(bytes) = stdin {
            input.write_all(bytes).unwrap();
        }
        drop(input);
        let out = child.wait_with_output().unwrap();
        assert!(
            out.status.success(),
            "git {args:?}: {}",
            String::from_utf8_lossy(&out.stderr)
        );
        String::from_utf8_lossy(&out.stdout).trim().to_string()
    }

    /// Commit `msg` on `work`'s current branch; its id.
    fn commit(&self, msg: &str) -> String {
        self.git("work", &["commit", "-q", "--allow-empty", "-m", msg]);
        self.git("work", &["rev-parse", "HEAD"])
    }

    fn config(&self, key: &str, value: &str) {
        self.git("work", &["config", key, value]);
    }

    /// Write `contents` to `rel` as an executable script; its path. A child
    /// shell writes the file, so this process never holds it open for
    /// writing: a parallel test that forked to spawn while it did would keep
    /// a copy of that handle until its child's exec, and running the script
    /// in that window fails with ETXTBSY (#1213). The mode is set by path,
    /// which opens nothing.
    fn script(&self, rel: &str, contents: &str) -> PathBuf {
        use std::os::unix::fs::PermissionsExt;
        let path = self.path(rel);
        let status = Command::new("/bin/sh")
            .args(["-c", "printf '%s' \"$2\" > \"$1\"", "sh"])
            .arg(&path)
            .arg(contents)
            .status()
            .unwrap();
        assert!(status.success(), "writing {}: {status}", path.display());
        std::fs::set_permissions(&path, std::fs::Permissions::from_mode(0o755)).unwrap();
        path
    }

    /// The real runner, with this scratch's `HOME`.
    fn system_git(&self) -> SystemGit {
        SystemGit::with_env([
            (
                OsString::from("PATH"),
                std::env::var_os("PATH").unwrap_or_default(),
            ),
            (OsString::from("HOME"), self.path("home").into_os_string()),
        ])
    }

    /// The plugin's evaluation of `cmd` run in `work`.
    fn eval(&self, cmd: &str) -> Option<String> {
        self.eval_in(cmd, "work")
    }

    fn eval_in(&self, cmd: &str, rel: &str) -> Option<String> {
        eval_with(
            cmd,
            &self.path(rel),
            &self.system_git(),
            RuleSet::All,
            false,
        )
    }
}

impl Drop for Scratch {
    fn drop(&mut self) {
        let _ = std::fs::remove_dir_all(&self.root);
    }
}

fn eval_with(
    cmd: &str,
    cwd: &Path,
    git: &dyn GitRunner,
    rules: RuleSet,
    wired: bool,
) -> Option<String> {
    let input = serde_json::json!({
        "tool_name": "Bash",
        "cwd": cwd.to_string_lossy(),
        "tool_input": { "command": cmd },
    })
    .to_string();
    evaluate(
        &input,
        &Ctx {
            rules,
            registry: RegistrySource::Embedded,
            canary_opted_in: &|| false,
            legacy_wired: &|| wired,
            git,
            git_budget: GIT_BUDGET,
        },
    )
}

#[track_caller]
fn assert_trailer_deny(r: Option<String>, id: &str) -> String {
    let r = r.expect("denies");
    assert!(
        r.starts_with("shirabe denied this `git push` before it ran.\n\n"),
        "{r}"
    );
    assert!(
        r.contains(&format!(
            "commit/no-ai-trailer: A commit carries an AI-attribution trailer: {} subject: ",
            &id[..12]
        )),
        "{r}"
    );
    assert!(
        r.contains("full text: references/pr-body-conformance.md lines "),
        "{r}"
    );
    r
}

#[track_caller]
fn assert_fail_closed(r: Option<String>, word: &str) -> String {
    let r = r.expect("denies");
    assert!(r.contains(word), "want {word:?} in: {r}");
    assert!(r.contains("`git push`"), "{r}");
    assert!(r.contains("commit/no-ai-trailer"), "{r}");
    assert!(r.contains("ask the user"), "{r}");
    assert!(!r.contains("SHIRABE_PRE_ACTION_HOOK"), "{r}");
    r
}

// --- what a push sends --------------------------------------------------------

#[test]
fn a_push_with_no_refspec_sends_the_current_branch() {
    let s = Scratch::repo();
    assert_eq!(s.eval("git push"), None, "nothing outgoing");
    s.commit(CLEAN);
    assert_eq!(s.eval("git push"), None, "a clean commit");
    let id = s.commit(TRAILER);
    let r = assert_trailer_deny(s.eval("git push"), &id);
    assert!(r.contains("subject: feat: add x\n"), "{r}");
    assert_trailer_deny(s.eval("git push origin"), &id);
    assert_trailer_deny(s.eval("/usr/bin/git push"), &id);
    assert_trailer_deny(s.eval("git status && git push"), &id);
    assert_trailer_deny(s.eval("if true; then git push; fi"), &id);
}

#[test]
fn a_refspec_sends_its_source() {
    let s = Scratch::repo();
    let id = s.commit(TRAILER);
    assert_trailer_deny(s.eval("git push origin HEAD:refs/heads/other"), &id);
    assert_trailer_deny(s.eval("git push --force origin +main"), &id);
    assert_trailer_deny(s.eval("git push origin main:main"), &id);
    // A deletion sends nothing.
    assert_eq!(s.eval("git push origin :topic"), None);
    assert_eq!(s.eval("git push origin --delete topic"), None);
    assert_eq!(s.eval("git push origin -d main"), None);
}

#[test]
fn a_push_with_no_refspec_fails_closed_when_its_configuration_may_send_more() {
    let s = Scratch::repo();
    s.commit(CLEAN);
    s.config("push.default", "matching");
    for cmd in ["git push", "git push origin"] {
        let r = assert_fail_closed(s.eval(cmd), "`push.default`");
        assert!(r.contains("may send more than the current branch"), "{r}");
    }
    // A refspec says what is sent, so the setting doesn't matter.
    assert_eq!(s.eval("git push origin main"), None);
    s.config("push.default", "simple");
    assert_eq!(s.eval("git push"), None);

    s.config("remote.origin.push", "refs/heads/*:refs/heads/*");
    assert_fail_closed(s.eval("git push"), "`remote.origin.push`");
    assert_fail_closed(s.eval("git push origin"), "`remote.origin.push`");
    assert_eq!(s.eval("git push fork"), None);
    assert_eq!(s.eval("git push origin main"), None);
}

#[test]
fn an_empty_refspec_pushes_the_matching_branches() {
    let s = Scratch::repo();
    s.git("work", &["checkout", "-q", "-b", "topic"]);
    let id = s.commit(TRAILER);
    s.git("work", &["checkout", "-q", "main"]);
    assert_trailer_deny(s.eval("git push origin :"), &id);
    assert_trailer_deny(s.eval("git push origin +:"), &id);
    let s = Scratch::repo();
    s.commit(CLEAN);
    assert_eq!(s.eval("git push origin :"), None);
}

/// Example-table rows: a redirection on a push is no refspec.
#[test]
fn a_redirected_push_is_checked_like_any_other() {
    let s = Scratch::repo();
    s.git("work", &["checkout", "-q", "-b", "topic"]);
    s.commit(CLEAN);
    let cmds = [
        "git push origin topic 2>&1",
        "git push origin topic > log",
        "git push -u origin topic 2>&1",
        "git push origin HEAD >/dev/null",
        "git push>/dev/null",
        "cd . 2>/dev/null && git push origin topic",
    ];
    for cmd in cmds {
        assert_eq!(s.eval(cmd), None, "clean: {cmd}");
    }
    let id = s.commit(TRAILER);
    for cmd in cmds {
        assert_trailer_deny(s.eval(cmd), &id);
    }
    assert!(!s.path("work/log").exists(), "the check writes nothing");
}

#[test]
fn the_example_tables_trailer_pushes_are_denied() {
    let s = Scratch::repo();
    s.git("work", &["checkout", "-q", "-b", "topic"]);
    let id = s.commit(TRAILER);
    std::fs::create_dir_all(s.path("work/sub")).unwrap();
    for cmd in [
        "git push --force origin +topic",
        "git -c k=v push",
        "cd sub && git push",
        "git -C sub push",
    ] {
        assert_trailer_deny(s.eval(cmd), &id);
    }
    assert_eq!(s.eval("git push origin --delete topic"), None);
    assert_eq!(s.eval("git push origin :topic"), None);
}

#[test]
fn all_tags_and_mirror_send_every_branch_or_tag() {
    let s = Scratch::repo();
    s.git("work", &["checkout", "-q", "-b", "topic"]);
    let id = s.commit(TRAILER);
    s.git("work", &["checkout", "-q", "main"]);
    // Only on a branch that isn't pushed.
    assert_eq!(s.eval("git push origin main"), None);
    assert_eq!(s.eval("git push"), None);
    assert_trailer_deny(s.eval("git push --all"), &id);
    assert_trailer_deny(s.eval("git push --branches origin"), &id);
    assert_trailer_deny(s.eval("git push --mirror"), &id);
    assert_eq!(s.eval("git push --tags"), None, "no tags yet");

    // An annotated tag on a commit no branch holds counts as that commit.
    let s = Scratch::repo();
    s.git("work", &["checkout", "-q", "-b", "tmp"]);
    let id = s.commit(TRAILER);
    s.git("work", &["tag", "-a", "-m", "v1", "v1"]);
    s.git("work", &["checkout", "-q", "main"]);
    s.git("work", &["branch", "-q", "-D", "tmp"]);
    assert_eq!(s.eval("git push --all"), None);
    assert_trailer_deny(s.eval("git push --tags"), &id);
    assert_trailer_deny(s.eval("git push origin --tags"), &id);
    assert_trailer_deny(s.eval("git push --mirror"), &id);
    assert_trailer_deny(s.eval("git push origin v1"), &id);
}

#[test]
fn a_merge_commit_carrying_the_trailer_is_not_checked() {
    let s = Scratch::repo();
    s.git("work", &["checkout", "-q", "-b", "topic"]);
    s.commit(CLEAN);
    s.git("work", &["checkout", "-q", "main"]);
    s.git("work", &["merge", "-q", "--no-ff", "-m", TRAILER, "topic"]);
    assert_eq!(s.eval("git push"), None);
}

#[test]
fn repo_names_the_remote_when_no_positional_word_does() {
    let s = Scratch::repo();
    let id = s.commit(TRAILER);
    assert_trailer_deny(s.eval("git push --repo=fork"), &id);
    s.git("work", &["push", "-q", "fork", "main"]);
    assert_eq!(s.eval("git push --repo=fork"), None);
    assert_trailer_deny(s.eval("git push --repo=origin"), &id);
    // The positional word wins over `--repo`.
    assert_eq!(s.eval("git push --repo=origin fork main"), None);
}

// --- where it pushes: one test per resolution step ---------------------------

/// A repository whose trailer commit on `main` is already on `fork`, so a
/// push to `fork` sends nothing and one to `origin` sends it.
fn on_fork_only() -> (Scratch, String) {
    let s = Scratch::repo();
    let id = s.commit(TRAILER);
    s.git("work", &["push", "-q", "fork", "main"]);
    (s, id)
}

#[test]
fn the_remote_is_first_the_branchs_push_remote() {
    let (s, id) = on_fork_only();
    s.config("branch.main.pushRemote", "fork");
    s.config("remote.pushDefault", "origin");
    s.config("branch.main.remote", "origin");
    assert_eq!(s.eval("git push"), None);
    s.config("branch.main.pushRemote", "origin");
    s.config("remote.pushDefault", "fork");
    s.config("branch.main.remote", "fork");
    assert_trailer_deny(s.eval("git push"), &id);
}

#[test]
fn the_remote_is_then_the_push_default() {
    let (s, id) = on_fork_only();
    s.config("remote.pushDefault", "fork");
    s.config("branch.main.remote", "origin");
    assert_eq!(s.eval("git push"), None);
    s.config("remote.pushDefault", "origin");
    s.config("branch.main.remote", "fork");
    assert_trailer_deny(s.eval("git push"), &id);
}

#[test]
fn the_remote_is_then_the_branchs_remote() {
    let (s, id) = on_fork_only();
    s.config("branch.main.remote", "fork");
    assert_eq!(s.eval("git push"), None);
    s.config("branch.main.remote", "origin");
    assert_trailer_deny(s.eval("git push"), &id);
}

#[test]
fn the_remote_is_last_origin() {
    let (s, id) = on_fork_only();
    assert_trailer_deny(s.eval("git push"), &id);
    // With the commit on `origin` instead, the default sends nothing.
    let s = Scratch::repo();
    s.commit(TRAILER);
    s.git("work", &["push", "-q", "origin", "main"]);
    assert_eq!(s.eval("git push"), None);
}

#[test]
fn a_url_remote_checks_the_commits_on_no_remotes_tracking_refs() {
    let (s, first) = on_fork_only();
    let url = s.dir("origin.git");
    // The trailer commit is on `fork`'s tracking refs, so it isn't checked
    // even though the URL is `origin`'s.
    assert_eq!(s.eval(&format!("git push {url} main")), None);
    let second = s.commit(TRAILER);
    let r = assert_trailer_deny(s.eval(&format!("git push {url} main")), &second);
    assert!(!r.contains(&first[..12]), "{r}");
    assert_trailer_deny(s.eval(&format!("git push file://{url} main")), &second);
}

#[test]
fn a_remote_with_no_tracking_refs_checks_the_commits_on_no_remotes_tracking_refs() {
    let (s, first) = on_fork_only();
    s.git("", &["init", "-q", "--bare", "-b", "main", "empty.git"]);
    s.git("work", &["remote", "add", "empty", &s.dir("empty.git")]);
    assert_eq!(s.eval("git push empty main"), None);
    let second = s.commit(TRAILER);
    let r = assert_trailer_deny(s.eval("git push empty main"), &second);
    assert!(!r.contains(&first[..12]), "{r}");
}

// --- the options R4 lists ------------------------------------------------------

#[test]
fn each_listed_option_keeps_the_check() {
    let clean = Scratch::repo();
    clean.commit(CLEAN);
    let s = Scratch::repo();
    let id = s.commit(TRAILER);
    for opt in [
        "--force",
        "-f",
        "--force-with-lease",
        "--force-with-lease=main",
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
        "--signed=if-asked",
        "--no-signed",
        "--push-option x",
        "--push-option=x",
        "-o x",
        "--recurse-submodules=no",
    ] {
        let cmd = format!("git push {opt} origin main");
        assert_trailer_deny(s.eval(&cmd), &id);
        assert_eq!(clean.eval(&cmd), None, "{cmd}");
    }
}

// --- fail-closed pushes --------------------------------------------------------

#[test]
fn a_detached_head_with_no_refspec_fails_closed() {
    let s = Scratch::repo();
    s.commit(CLEAN);
    s.git("work", &["checkout", "-q", "--detach"]);
    assert_fail_closed(s.eval("git push"), "HEAD");
    assert_fail_closed(s.eval("git push origin"), "HEAD");
    // A refspec names what to push.
    assert_eq!(s.eval("git push origin HEAD:refs/heads/x"), None);
}

#[test]
fn a_source_that_doesnt_resolve_or_starts_with_a_dash_fails_closed() {
    let s = Scratch::repo();
    assert_fail_closed(s.eval("git push origin nosuch"), "`nosuch`");
    assert_fail_closed(s.eval("git push origin +-x"), "`-x`");
    assert_fail_closed(
        s.eval("git push origin \"$(git rev-parse --abbrev-ref HEAD)\""),
        "doesn't resolve",
    );
    // A substitution in the push's own words runs before it too.
    assert_fail_closed(
        s.eval("git push origin \"$(git branch --show-current)\""),
        "same command",
    );
}

/// A runner that counts its calls and answers none.
struct Counting(Cell<usize>);

impl GitRunner for Counting {
    fn run(
        &self,
        _: &Path,
        _: &[&str],
        _: Option<Vec<u8>>,
        _: usize,
        _: Instant,
    ) -> Result<GitOut, GitError> {
        self.0.set(self.0.get() + 1);
        Err(GitError::NotFound)
    }
}

#[test]
fn an_unknown_option_fails_closed_before_any_git_runs() {
    let git = Counting(Cell::new(0));
    for opt in [
        "--some-new-option",
        "--exec=x",
        "--receive-pack=x",
        "--no-recurse-submodules",
    ] {
        let r = eval_with(
            &format!("git push {opt}"),
            Path::new("/r"),
            &git,
            RuleSet::All,
            false,
        );
        assert_fail_closed(r, &format!("`{opt}`"));
    }
    assert_eq!(git.0.get(), 0);
}

#[test]
fn unguarded_commands_start_no_git() {
    let git = Counting(Cell::new(0));
    for cmd in [
        "ls",
        "git status",
        "git commit -m x",
        "git log --grep push",
        "echo \"git push\"",
        "gh pr view 3",
    ] {
        assert_eq!(
            eval_with(cmd, Path::new("/r"), &git, RuleSet::All, false),
            None,
            "{cmd}"
        );
    }
    assert_eq!(git.0.get(), 0);
}

#[test]
fn more_than_a_thousand_commits_fail_closed_and_a_thousand_decide() {
    let s = Scratch::repo();
    let mut stream = String::new();
    for i in 1..=1001 {
        let msg = if i == 1 {
            TRAILER.to_string()
        } else {
            format!("chore: c{i}\n")
        };
        stream.push_str(&format!(
            "commit refs/heads/big\ncommitter t <t@example.com> {i} +0000\ndata {}\n{msg}\n",
            msg.len()
        ));
    }
    s.git_with("work", &["fast-import", "--quiet"], Some(stream.as_bytes()));
    assert_fail_closed(s.eval("git push origin big"), "1000 commits");
    // `big~1` reaches 1,000 commits, the oldest carrying the trailer.
    let root = s.git("work", &["rev-list", "--max-parents=0", "big"]);
    assert_trailer_deny(s.eval("git push origin big~1:refs/heads/x"), &root);
}

#[test]
fn a_remote_name_outside_the_plain_pattern_fails_closed() {
    let s = Scratch::repo();
    s.commit(CLEAN);
    s.config("remote.fo+o.url", &s.dir("fork.git"));
    assert_fail_closed(s.eval("git push fo+o main"), "`fo+o`");
    s.config("branch.main.pushRemote", "fo+o");
    assert_fail_closed(s.eval("git push"), "`fo+o`");
    assert_fail_closed(s.eval("git push \"$R\" main"), "`$R`");
}

#[test]
fn a_directory_outside_a_work_tree_fails_closed() {
    let s = Scratch::repo();
    assert_fail_closed(s.eval_in("git push", ""), "work tree");
    assert_fail_closed(s.eval_in("git push", "origin.git"), "work tree");
    assert_fail_closed(s.eval_in("git push", "no-such-dir"), "work tree");
}

/// A runner that answers from a script: each call's subcommand and first
/// argument, and the exit code and stdout to give back.
struct Scripted(Vec<(&'static str, i32, &'static str)>, Cell<Vec<String>>);

impl GitRunner for Scripted {
    fn run(
        &self,
        _: &Path,
        args: &[&str],
        _: Option<Vec<u8>>,
        _: usize,
        _: Instant,
    ) -> Result<GitOut, GitError> {
        let key = args[..args.len().min(3)].join(" ");
        let mut seen = self.1.take();
        seen.push(key.clone());
        self.1.set(seen);
        let (_, code, out) = self
            .0
            .iter()
            .find(|(k, _, _)| key.starts_with(k))
            .unwrap_or(&("", 1, ""));
        Ok(GitOut {
            code: Some(*code),
            stdout: out.as_bytes().to_vec(),
        })
    }
}

#[test]
fn a_partial_clone_is_refused_below_git_2_44_and_checked_from_it() {
    let partial = |v: &'static str| {
        Scripted(
            vec![
                ("rev-parse --show-toplevel", 0, "/w\n"),
                ("config --get extensions.partialClone", 0, "origin\n"),
                ("version", 0, v),
                ("symbolic-ref", 1, ""),
            ],
            Cell::new(Vec::new()),
        )
    };
    let seg = |cmd: &str| PushSegment {
        words: words(cmd),
        dir: PathBuf::from("/w"),
        index: 0,
    };
    for v in [
        "git version 2.39.5 (Apple Git-154)\n",
        "git version 2.43.7\n",
        "nonsense\n",
    ] {
        let git = partial(v);
        match check(&seg("x"), &git, GIT_BUDGET) {
            Err(Case::Git(why)) => assert!(why.contains("partial clone"), "{why}"),
            other => panic!("{v}: {other:?}"),
        }
        assert!(
            !git.1.take().iter().any(|c| c.starts_with("symbolic-ref")),
            "{v}"
        );
    }
    // From 2.44 the check goes on (here to the detached HEAD it scripted).
    let git = partial("git version 2.44.0\n");
    assert_eq!(check(&seg("x"), &git, GIT_BUDGET), Err(Case::DetachedHead));
    // A full clone never asks for the version.
    let git = Scripted(
        vec![
            ("rev-parse --show-toplevel", 0, "/w\n"),
            ("symbolic-ref", 1, ""),
        ],
        Cell::new(Vec::new()),
    );
    assert_eq!(check(&seg("x"), &git, GIT_BUDGET), Err(Case::DetachedHead));
    assert!(!git.1.take().iter().any(|c| c == "version"));
}

#[test]
fn the_runner_kills_a_child_that_prints_too_much_or_runs_too_long() {
    let s = Scratch::empty();
    std::fs::create_dir_all(s.path("stub")).unwrap();
    // The stub's PATH holds only its own directory, so it names every
    // program by absolute path.
    let stub_git = |body: &str| {
        s.script("stub/git", &format!("#!/bin/sh\n{body}\n"));
        SystemGit::with_env([(OsString::from("PATH"), s.path("stub").into_os_string())])
    };

    // Each elapsed-time bound is half of what a runner that got it wrong
    // would wait for (the far deadline, or the child's own run), not a guess
    // at how fast the host is: spawning, killing and reaping on a loaded
    // runner has taken over two seconds (#1058).
    let git = stub_git("exec /usr/bin/yes");
    let start = Instant::now();
    let far_secs = 20;
    let far = start + Duration::from_secs(far_secs);
    assert_eq!(
        git.run(&s.root, &["x"], None, 1024 * 1024, far),
        Err(GitError::TooLarge)
    );
    assert!(start.elapsed() < Duration::from_secs(far_secs / 2));

    let child_secs = 20;
    let git = stub_git(&format!("exec /bin/sleep {child_secs}"));
    let start = Instant::now();
    let soon = start + Duration::from_millis(300);
    assert_eq!(
        git.run(&s.root, &["x"], None, 1024, soon),
        Err(GitError::Timeout)
    );
    assert!(start.elapsed() < Duration::from_secs(child_secs / 2));

    // A grandchild that keeps stdout open can't hold the runner past the
    // deadline either.
    let git = stub_git(&format!("/bin/sleep {child_secs} &\nexit 0"));
    let start = Instant::now();
    let soon = start + Duration::from_millis(300);
    assert_eq!(
        git.run(&s.root, &["x"], None, 1024, soon),
        Err(GitError::Timeout)
    );
    assert!(start.elapsed() < Duration::from_secs(child_secs / 2));
}

#[test]
fn a_partial_clone_fails_closed_under_a_git_older_than_2_44() {
    let s = Scratch::repo();
    let id = s.commit(TRAILER);
    s.config("extensions.partialClone", "origin");
    let v = version(&s.git("", &["version"])).expect("a git version");
    if v < LAZY_FETCH_FLOOR {
        let r = assert_fail_closed(s.eval("git push"), "git");
        assert!(r.contains("partial clone"), "{r}");
    } else {
        assert_trailer_deny(s.eval("git push"), &id);
    }
}

#[test]
fn a_missing_git_fails_closed_naming_git() {
    let s = Scratch::repo();
    let git = SystemGit::with_env([(OsString::from("PATH"), OsString::from("/nonexistent"))]);
    let r = eval_with("git push", &s.path("work"), &git, RuleSet::All, false);
    let r = assert_fail_closed(r, "git");
    assert!(r.contains("no `git` was found"), "{r}");
}

// --- what the deny lists ---------------------------------------------------------

#[test]
fn twelve_offending_commits_list_ten_then_and_two_more() {
    let s = Scratch::repo();
    for i in 0..12 {
        s.commit(&format!(
            "feat: c{i}\n\nCo-Authored-By: Claude <noreply@anthropic.com>"
        ));
    }
    let r = s.eval("git push").expect("denies");
    assert_eq!(r.matches(" subject: feat: c").count(), 10, "{r}");
    assert!(r.contains("; and 2 more\n"), "{r}");
    assert_eq!(r.matches("commit/no-ai-trailer:").count(), 1, "{r}");
}

#[test]
fn a_generated_with_line_is_an_attribution_line_too() {
    let s = Scratch::repo();
    let id = s.commit("fix: y\n\nGenerated with Claude Code");
    assert_trailer_deny(s.eval("git push"), &id);
}

#[test]
fn a_subject_with_quotes_backslashes_and_escapes_is_cleaned() {
    let s = Scratch::repo();
    let subject = format!("feat: \"q\" \\b \u{1b}[31mred {}", "z".repeat(90));
    s.commit(&format!(
        "{subject}\n\nCo-Authored-By: Claude <x@anthropic.com>"
    ));
    let r = s.eval("git push").expect("denies");
    assert!(r.contains("subject: feat: \"q\" \\b [31mred zzz"), "{r}");
    assert!(!r.contains('\u{1b}'), "{r}");
    let line = r.lines().find(|l| l.contains(" subject: ")).unwrap();
    let kept = line.split(" subject: ").nth(1).unwrap();
    assert_eq!(kept.chars().count(), 72, "{kept}");
}

#[test]
fn a_command_breaking_pr_and_push_rules_gets_one_header_and_registry_order() {
    let s = Scratch::repo();
    s.commit(TRAILER);
    let cmd = "gh pr create --title 'Add x' --body 'Adds x.' && git push";
    let r = eval_with(cmd, &s.path("work"), &s.system_git(), RuleSet::All, false).expect("denies");
    assert!(
        r.starts_with(
            "shirabe denied this command's `gh pr create` and `git push` before they ran.\n\n"
        ),
        "{r}"
    );
    let at = |id: &str| {
        r.find(&format!("{id}: "))
            .unwrap_or_else(|| panic!("{id}: {r}"))
    };
    // The registry lists the commit rule before the PR-body rules.
    assert!(
        at("commit/no-ai-trailer") < at("pr-body/conventional-title"),
        "{r}"
    );
    assert!(
        at("pr-body/conventional-title") < at("pr-body/one-separator"),
        "{r}"
    );

    // Wired, the plugin keeps the push and the legacy entry point the PR;
    // each rule is reported once between them.
    let plugin = eval_with(cmd, &s.path("work"), &s.system_git(), RuleSet::All, true).unwrap();
    assert!(plugin.contains("commit/no-ai-trailer: "), "{plugin}");
    assert!(!plugin.contains("pr-body/"), "{plugin}");
    let legacy = eval_with(
        cmd,
        &s.path("work"),
        &s.system_git(),
        RuleSet::PrBodyOnly,
        false,
    )
    .unwrap();
    assert!(legacy.contains("pr-body/one-separator: "), "{legacy}");
    assert!(!legacy.contains("commit/no-ai-trailer"), "{legacy}");
    // Under PR_BODY_HOOK_DISABLE the push is still checked.
    let push_only = eval_with(
        cmd,
        &s.path("work"),
        &s.system_git(),
        RuleSet::PushOnly,
        false,
    )
    .unwrap();
    assert!(push_only.contains("commit/no-ai-trailer: "), "{push_only}");
    assert!(!push_only.contains("pr-body/"), "{push_only}");
}

// --- the repository can't run a program -------------------------------------------

#[test]
fn a_repository_configured_to_run_programs_runs_none() {
    let s = Scratch::repo();
    let marker = s.path("marker");
    let mark = s.script(
        "mark.sh",
        &format!(
            "#!/bin/sh\necho \"$0 $*\" >> '{}'\ncat >/dev/null 2>&1\nexit 0\n",
            marker.display()
        ),
    );
    std::fs::create_dir_all(s.path("hooks")).unwrap();
    for hook in [
        "reference-transaction",
        "post-index-change",
        "pre-push",
        "post-checkout",
        "pre-commit",
    ] {
        std::os::unix::fs::symlink(&mark, s.path("hooks").join(hook)).unwrap();
    }

    // A commit object with a signature header and the trailer, which a
    // signature check would hand to `gpg.program`.
    let tree = s.git("work", &["rev-parse", "HEAD^{tree}"]);
    let parent = s.git("work", &["rev-parse", "HEAD"]);
    let object = format!(
        "tree {tree}\nparent {parent}\nauthor t <t@example.com> 1 +0000\ncommitter t <t@example.com> 1 +0000\n\
         gpgsig -----BEGIN PGP SIGNATURE-----\n \n iQEz\n -----END PGP SIGNATURE-----\n\n{TRAILER}"
    );
    let id = s.git_with(
        "work",
        &["hash-object", "-t", "commit", "-w", "--stdin"],
        Some(object.as_bytes()),
    );
    s.git("work", &["update-ref", "refs/heads/main", &id]);
    // A replace object that would hide the trailer if it were honoured.
    let clean = s.git_with(
        "work",
        &["hash-object", "-t", "commit", "-w", "--stdin"],
        Some(format!("tree {tree}\nparent {parent}\nauthor t <t@example.com> 1 +0000\ncommitter t <t@example.com> 1 +0000\n\nclean\n").as_bytes()),
    );
    s.git("work", &["replace", &id, &clean]);

    let m = mark.to_str().unwrap();
    for (k, v) in [
        ("core.fsmonitor", m),
        ("core.hooksPath", s.path("hooks").to_str().unwrap()),
        ("log.showSignature", "true"),
        ("gpg.program", m),
        ("gpg.ssh.program", m),
        ("core.pager", m),
        ("pager.rev-list", m),
        ("pager.cat-file", m),
        ("diff.external", m),
        ("core.sshCommand", m),
    ] {
        s.config(k, v);
    }
    // The configuration is live: plain git, without the check's settings,
    // runs the repository's programs.
    let _ = s.setup_git("work", &["status"]).output();
    let _ = s
        .setup_git("work", &["log", "--show-signature", "-1"])
        .output();
    assert!(marker.exists(), "the markers would fire against plain git");
    std::fs::remove_file(&marker).unwrap();
    assert_trailer_deny(s.eval("git push"), &id);
    assert_trailer_deny(s.eval("git push --tags --all"), &id);
    assert!(
        !marker.exists(),
        "{}",
        std::fs::read_to_string(&marker).unwrap_or_default()
    );
}

#[test]
fn the_runner_keeps_only_path_home_the_global_config_lang_and_lc_and_adds_the_fixed_variables() {
    let g = SystemGit::with_env(
        [
            ("PATH", "relative/bin:/usr/bin:.:/bin"),
            ("HOME", "/h"),
            ("XDG_CONFIG_HOME", "/h/.cfg"),
            ("GIT_CONFIG_GLOBAL", "/x"),
            ("LANG", "C"),
            ("LC_ALL", "C"),
            ("GIT_DIR", "/elsewhere"),
            ("GIT_CONFIG", "/y"),
            ("GIT_CONFIG_SYSTEM", "/z"),
            ("LEAK", "1"),
        ]
        .map(|(k, v)| (OsString::from(k), OsString::from(v))),
    );
    let keys: Vec<String> = g
        .env
        .iter()
        .map(|(k, v)| format!("{}={}", k.to_string_lossy(), v.to_string_lossy()))
        .collect();
    assert_eq!(
        keys,
        vec![
            "HOME=/h",
            "XDG_CONFIG_HOME=/h/.cfg",
            "GIT_CONFIG_GLOBAL=/x",
            "LANG=C",
            "LC_ALL=C",
            "PATH=/usr/bin:/bin",
            "GIT_CONFIG_NOSYSTEM=1",
            "GIT_NO_LAZY_FETCH=1",
            "GIT_NO_REPLACE_OBJECTS=1",
            "GIT_OPTIONAL_LOCKS=0",
            "GIT_TERMINAL_PROMPT=0",
            "GIT_PAGER=cat",
        ]
    );
}
