//! CLI integration tests for `shirabe compaction pre-compact` and
//! `re-anchor`: the stale flag and its inputs, the ledger checks, and the
//! outputs for a session with no usable entry.
//!
//! Every run clears the environment and puts only stand-ins on `PATH`: a koto
//! stub that answers `context history`, `context list` and `status` from
//! files under `$KOTO_STUB` (it never touches a koto store), a `gh` stub that
//! logs each call, and a `git` wrapper that logs its arguments and runs the
//! real git on throwaway repositories.

use std::fs;
use std::os::unix::fs::PermissionsExt;
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicUsize, Ordering};
use std::time::Instant;

use assert_cmd::Command;

const SID: &str = "4f08fec0-0720-4fdd-ab29-5f0583eb2031";
const KS: &str = "probe-run-x7";
const PR: &str = "https://github.com/acme/widgets/pull/42";
const SKILL: &str = "/opt/plugins/shirabe/0.50.0/skills/deliver/SKILL.md";
const BRANCH: &str = "session/test1";
const OTHER_BRANCH: &str = "other/cwd-branch";
/// The note's last write, and commit times on either side of it.
const NOTE_AT: &str = "2026-06-01T12:00:00.250Z";
const BEFORE_NOTE: &str = "2026-06-01 11:00:00 +0000";
const AFTER_NOTE: &str = "2026-06-01 12:30:00 +0000";
const INPUT_MARKER: &str = "INPUT-MARKER-9z";

const KOTO_STUB: &str = r#"#!/bin/bash
printf '%s\n' "$*" >>"$KOTO_STUB/log"
[ -f "$KOTO_STUB/slow" ] && exec sleep 30
f=""
case "$1:${2-}" in
    context:history) f="$KOTO_STUB/history/${4//\//__}" ;;
    context:list) f="$KOTO_STUB/list" ;;
    status:*) f="$KOTO_STUB/status" ;;
esac
[ -n "$f" ] && [ -f "$f" ] || exit 2
printf '%s\n' "$(<"$f")"
"#;

const GH_STUB: &str = r#"#!/bin/bash
printf '%s\n' "$*" >>"$GH_LOG"
exit 0
"#;

fn good_entry() -> String {
    format!(
        "koto_session: {KS}\nnote_key: compaction/note.md\nbranch: {BRANCH}\npr: {PR}\nskill: shirabe:deliver handoff-brief {SKILL}\n"
    )
}

fn find_on_path(tool: &str) -> PathBuf {
    let path = std::env::var("PATH").unwrap_or_default();
    for d in path.split(':') {
        let p = Path::new(d).join(tool);
        if p.is_file() {
            return p;
        }
    }
    panic!("{tool} is not on PATH");
}

struct Fx {
    dir: PathBuf,
    git: PathBuf,
}

impl Drop for Fx {
    fn drop(&mut self) {
        let _ = fs::remove_dir_all(&self.dir);
    }
}

fn write_exec(p: &Path, body: &str) {
    fs::write(p, body).unwrap();
    fs::set_permissions(p, fs::Permissions::from_mode(0o755)).unwrap();
}

impl Fx {
    fn new() -> Fx {
        static N: AtomicUsize = AtomicUsize::new(0);
        let n = N.fetch_add(1, Ordering::SeqCst);
        let dir =
            std::env::temp_dir().join(format!("compaction-test-{}-{}", std::process::id(), n));
        let _ = fs::remove_dir_all(&dir);
        for d in [
            "state/shirabe/compaction",
            "stub/history",
            "kbin",
            "bin",
            "tools",
            "home",
            "repo",
            "other",
            "plain",
        ] {
            fs::create_dir_all(dir.join(d)).unwrap();
        }
        let dir = dir.canonicalize().unwrap();
        fs::set_permissions(
            dir.join("state/shirabe/compaction"),
            fs::Permissions::from_mode(0o700),
        )
        .unwrap();
        let git = find_on_path("git");
        write_exec(&dir.join("kbin/koto"), KOTO_STUB);
        write_exec(&dir.join("bin/gh"), GH_STUB);
        write_exec(
            &dir.join("bin/git"),
            &format!(
                "#!/bin/bash\nprintf '%s\\n' \"$*\" >>\"$GIT_LOG\"\nexec '{}' \"$@\"\n",
                git.display()
            ),
        );
        std::os::unix::fs::symlink(find_on_path("sleep"), dir.join("tools/sleep")).unwrap();
        let fx = Fx { dir, git };
        fx.init_repo("repo", BRANCH);
        fx.init_repo("other", OTHER_BRANCH);
        // The default koto answers: the note written once in state `work`,
        // one other key written before it, the run still in `work`.
        fx.history("compaction/note.md", &[(5, NOTE_AT, Some("work"))]);
        fx.history(
            "brief/brief.md",
            &[(3, "2026-06-01T11:59:00.000Z", Some("work"))],
        );
        fx.list(&["brief/brief.md", "compaction/note.md"]);
        fx.status("work");
        fx.entry(&good_entry());
        fx
    }

    fn p(&self, rel: &str) -> PathBuf {
        self.dir.join(rel)
    }

    fn git_cmd(&self, repo: &str) -> std::process::Command {
        let mut c = std::process::Command::new(&self.git);
        c.current_dir(self.p(repo))
            .env("HOME", self.p("home"))
            .env("GIT_CONFIG_NOSYSTEM", "1")
            .env("GIT_AUTHOR_NAME", "t")
            .env("GIT_AUTHOR_EMAIL", "t@example.com")
            .env("GIT_COMMITTER_NAME", "t")
            .env("GIT_COMMITTER_EMAIL", "t@example.com");
        c
    }

    fn git_ok(&self, repo: &str, args: &[&str]) {
        let st = self.git_cmd(repo).args(args).output().unwrap();
        assert!(st.status.success(), "git {args:?} failed: {st:?}");
    }

    fn init_repo(&self, repo: &str, branch: &str) {
        self.git_ok(repo, &["init", "-q", "-b", branch]);
        self.git_ok(repo, &["config", "commit.gpgsign", "false"]);
        self.commit(repo, BEFORE_NOTE);
    }

    fn commit(&self, repo: &str, date: &str) {
        let f = self.p(repo).join("f.txt");
        let mut body = fs::read_to_string(&f).unwrap_or_default();
        body.push_str(date);
        body.push('\n');
        fs::write(&f, body).unwrap();
        self.git_ok(repo, &["add", "f.txt"]);
        let st = self
            .git_cmd(repo)
            .args(["commit", "-q", "-m", "c"])
            .env("GIT_AUTHOR_DATE", date)
            .env("GIT_COMMITTER_DATE", date)
            .output()
            .unwrap();
        assert!(st.status.success(), "commit failed: {st:?}");
    }

    fn entry_path(&self) -> PathBuf {
        self.p("state/shirabe/compaction").join(SID)
    }

    fn entry(&self, text: &str) {
        let p = self.entry_path();
        let _ = fs::remove_file(&p);
        fs::write(&p, text).unwrap();
        fs::set_permissions(&p, fs::Permissions::from_mode(0o600)).unwrap();
    }

    fn history(&self, key: &str, writes: &[(u64, &str, Option<&str>)]) {
        let arr: Vec<serde_json::Value> = writes
            .iter()
            .map(|(seq, ts, state)| {
                serde_json::json!({"seq": seq, "timestamp": ts, "writer": "agent",
                    "hash": "00", "size": 1, "state": state})
            })
            .collect();
        fs::write(
            self.p("stub/history").join(key.replace('/', "__")),
            serde_json::to_string(&arr).unwrap(),
        )
        .unwrap();
    }

    fn list(&self, keys: &[&str]) {
        fs::write(self.p("stub/list"), serde_json::to_string(keys).unwrap()).unwrap();
    }

    fn status(&self, state: &str) {
        fs::write(
            self.p("stub/status"),
            serde_json::json!({"name": KS, "current_state": state, "is_terminal": false})
                .to_string(),
        )
        .unwrap();
    }

    fn input(&self) -> String {
        serde_json::json!({
            "session_id": SID,
            "hook_event_name": "PreCompact",
            "trigger": "auto",
            "custom_instructions": INPUT_MARKER,
            "transcript_path": format!("/tmp/{INPUT_MARKER}.jsonl"),
        })
        .to_string()
    }

    /// Run a hook from `cwd` with `path` (directories under the fixture,
    /// joined) as the whole `PATH`.
    fn run_with(
        &self,
        sub: &str,
        cwd: &str,
        path: &[&str],
        input: &str,
        env: &[(&str, &str)],
    ) -> String {
        let path: Vec<String> = path
            .iter()
            .map(|d| self.p(d).display().to_string())
            .collect();
        let mut c = Command::cargo_bin("shirabe").unwrap();
        c.env_clear()
            .env("PATH", path.join(":"))
            .env("HOME", self.p("home"))
            .env("XDG_STATE_HOME", self.p("state"))
            .env("KOTO_STUB", self.p("stub"))
            .env("GH_LOG", self.p("gh.log"))
            .env("GIT_LOG", self.p("git.log"))
            .env("GIT_CONFIG_NOSYSTEM", "1")
            .current_dir(self.p(cwd))
            .args(["compaction", sub])
            .write_stdin(input.to_string());
        for (k, v) in env {
            c.env(k, v);
        }
        let out = c.output().unwrap();
        assert!(out.status.success(), "{sub} exited {:?}", out.status);
        String::from_utf8(out.stdout).unwrap()
    }

    fn run(&self, sub: &str, cwd: &str) -> String {
        self.run_with(sub, cwd, &["kbin", "bin", "tools"], &self.input(), &[])
    }

    fn pre_compact(&self) -> String {
        self.run("pre-compact", "repo")
    }
}

const STALE: &str = "The compaction note is stale";
const UNKNOWN: &str = "could not be checked";

fn context_of(re_anchor: &str) -> String {
    let v: serde_json::Value = serde_json::from_str(re_anchor).expect("re-anchor is JSON");
    assert_eq!(v["hookSpecificOutput"]["hookEventName"], "SessionStart");
    v["hookSpecificOutput"]["additionalContext"]
        .as_str()
        .unwrap()
        .to_string()
}

// --- the stale flag ---------------------------------------------------------------

#[test]
fn a_fresh_note_gets_no_stale_line() {
    let fx = Fx::new();
    let out = fx.pre_compact();
    for want in [KS, BRANCH, PR, "compaction/note.md", SKILL] {
        assert!(out.contains(want), "missing {want}: {out}");
    }
    assert!(!out.contains(STALE), "{out}");
    assert!(!out.contains(UNKNOWN), "{out}");
}

#[test]
fn a_key_written_after_the_note_makes_it_stale_and_a_rewrite_clears_it() {
    let fx = Fx::new();
    fx.history(
        "brief/brief.md",
        &[
            (3, "2026-06-01T11:59:00.000Z", Some("work")),
            (7, "2026-06-01T12:05:00.000Z", Some("work")),
        ],
    );
    let out = fx.pre_compact();
    assert!(out.contains(KS), "{out}");
    assert_eq!(out.matches(STALE).count(), 1, "{out}");
    assert!(out.contains("first step after the compaction"), "{out}");

    // Rewriting the note puts its last write after every other key's.
    fx.history(
        "compaction/note.md",
        &[
            (5, NOTE_AT, Some("work")),
            (8, "2026-06-01T12:06:00.000Z", Some("work")),
        ],
    );
    let out = fx.pre_compact();
    assert!(!out.contains(STALE), "{out}");
    assert!(!out.contains(UNKNOWN), "{out}");
}

#[test]
fn a_key_new_since_the_note_makes_it_stale() {
    let fx = Fx::new();
    fx.history(
        "scratch/x",
        &[(6, "2026-06-01T12:00:00.900Z", Some("work"))],
    );
    fx.list(&["brief/brief.md", "compaction/note.md", "scratch/x"]);
    assert!(fx.pre_compact().contains(STALE));
}

#[test]
fn a_commit_newer_than_the_note_makes_it_stale() {
    let fx = Fx::new();
    // A commit in the same second as the note, or before it, is not newer.
    fx.commit("repo", "2026-06-01 12:00:00 +0000");
    assert!(!fx.pre_compact().contains(STALE));
    fx.commit("repo", AFTER_NOTE);
    let out = fx.pre_compact();
    assert_eq!(out.matches(STALE).count(), 1, "{out}");
    // Rewriting the note after the commit clears it.
    fx.history(
        "compaction/note.md",
        &[(9, "2026-06-01T12:31:00.000Z", Some("work"))],
    );
    assert!(!fx.pre_compact().contains(STALE));
}

#[test]
fn a_commit_on_another_branch_does_not_count() {
    let fx = Fx::new();
    fx.git_ok("repo", &["checkout", "-q", "-b", "side"]);
    fx.commit("repo", AFTER_NOTE);
    let out = fx.pre_compact();
    assert!(!out.contains(STALE), "{out}");
}

#[test]
fn a_transition_after_the_note_makes_it_stale() {
    let fx = Fx::new();
    fx.status("review");
    assert!(fx.pre_compact().contains(STALE));
}

#[test]
fn pre_compact_makes_no_gh_call_and_every_git_call_is_safe() {
    let fx = Fx::new();
    let _ = fx.pre_compact();
    fs::remove_file(fx.entry_path()).unwrap();
    let _ = fx.run("pre-compact", "other");
    assert!(
        fs::read_to_string(fx.p("gh.log"))
            .unwrap_or_default()
            .is_empty(),
        "gh was called"
    );
    let log = fs::read_to_string(fx.p("git.log")).unwrap();
    assert!(log.lines().count() >= 2, "{log}");
    for line in log.lines() {
        assert!(
            line.starts_with("-c core.fsmonitor=false -c core.hooksPath=/dev/null "),
            "unsafe git call: {line}"
        );
    }
}

#[test]
fn a_repository_fsmonitor_or_hook_never_runs() {
    let fx = Fx::new();
    let marker = fx.p("marker");
    let prog = fx.p("mark.sh");
    write_exec(
        &prog,
        &format!("#!/bin/bash\nprintf ran >>'{}'\n", marker.display()),
    );
    fs::create_dir_all(fx.p("hooks")).unwrap();
    for h in [
        "post-checkout",
        "pre-commit",
        "post-index-change",
        "reference-transaction",
        "fsmonitor-watchman",
    ] {
        std::os::unix::fs::symlink(&prog, fx.p("hooks").join(h)).unwrap();
    }
    for repo in ["repo", "other"] {
        fx.git_ok(
            repo,
            &["config", "core.fsmonitor", &prog.display().to_string()],
        );
        fx.git_ok(
            repo,
            &[
                "config",
                "core.hooksPath",
                &fx.p("hooks").display().to_string(),
            ],
        );
    }
    let _ = fx.pre_compact();
    fs::remove_file(fx.entry_path()).unwrap();
    let out = fx.run("pre-compact", "other");
    assert!(out.contains(OTHER_BRANCH), "{out}");
    assert!(!marker.exists(), "a repository program ran");
}

// --- freshness that can't be read ------------------------------------------------

fn assert_unknown(out: &str) {
    assert!(out.contains(KS), "the summary is missing: {out}");
    assert!(out.contains(UNKNOWN), "no unknown line: {out}");
    assert!(!out.contains(STALE), "{out}");
    assert!(!out.contains(INPUT_MARKER), "input text printed: {out}");
}

#[test]
fn koto_absent_leaves_freshness_unknown() {
    let fx = Fx::new();
    let out = fx.run_with("pre-compact", "repo", &["bin", "tools"], &fx.input(), &[]);
    assert_unknown(&out);
}

#[test]
fn git_absent_leaves_freshness_unknown_unless_koto_shows_it_stale() {
    let fx = Fx::new();
    let out = fx.run_with("pre-compact", "repo", &["kbin", "tools"], &fx.input(), &[]);
    assert_unknown(&out);
    fx.status("review");
    let out = fx.run_with("pre-compact", "repo", &["kbin", "tools"], &fx.input(), &[]);
    assert!(out.contains(STALE), "{out}");
}

#[test]
fn a_branch_git_cannot_find_leaves_freshness_unknown() {
    let fx = Fx::new();
    // The working directory's repository has no session/test1.
    let out = fx.run("pre-compact", "other");
    assert_unknown(&out);
    let out = fx.run("pre-compact", "plain");
    assert_unknown(&out);
}

#[test]
fn an_unreadable_note_or_key_leaves_freshness_unknown() {
    let fx = Fx::new();
    fs::remove_file(fx.p("stub/history/compaction__note.md")).unwrap();
    assert_unknown(&fx.pre_compact());
    fx.history("compaction/note.md", &[]);
    assert_unknown(&fx.pre_compact());
    fs::write(fx.p("stub/history/compaction__note.md"), "not json").unwrap();
    assert_unknown(&fx.pre_compact());

    let fx = Fx::new();
    fs::remove_file(fx.p("stub/history/brief__brief.md")).unwrap();
    assert_unknown(&fx.pre_compact());

    let fx = Fx::new();
    fs::remove_file(fx.p("stub/list")).unwrap();
    assert_unknown(&fx.pre_compact());

    let fx = Fx::new();
    fs::remove_file(fx.p("stub/status")).unwrap();
    assert_unknown(&fx.pre_compact());

    let fx = Fx::new();
    fx.list(&["brief/brief.md", "compaction/note.md", "-not-a-key"]);
    assert_unknown(&fx.pre_compact());
}

#[test]
fn a_koto_that_hangs_is_cut_off() {
    let fx = Fx::new();
    fs::write(fx.p("stub/slow"), "").unwrap();
    let t = Instant::now();
    let out = fx.pre_compact();
    assert_unknown(&out);
    assert!(t.elapsed().as_secs() < 15, "took {:?}", t.elapsed());
}

// --- the ledger checks --------------------------------------------------------------

/// Both hooks, from a repository on another branch, print the no-entry
/// outputs and none of the entry's text.
fn assert_not_used(fx: &Fx, env: &[(&str, &str)], why: &str) {
    let path = ["kbin", "bin", "tools"];
    let pc = fx.run_with("pre-compact", "other", &path, &fx.input(), env);
    let ra = fx.run_with("re-anchor", "other", &path, &fx.input(), env);
    for text in [
        KS,
        PR,
        SKILL,
        BRANCH,
        "shirabe:deliver handoff-brief",
        INPUT_MARKER,
    ] {
        assert!(
            !pc.contains(text),
            "{why}: pre-compact printed {text}: {pc}"
        );
        assert!(!ra.contains(text), "{why}: re-anchor printed {text}: {ra}");
    }
    assert!(pc.contains("No compaction note is recorded"), "{why}: {pc}");
    assert!(
        pc.contains(&format!("- branch: {OTHER_BRANCH}")),
        "{why}: {pc}"
    );
    assert!(
        context_of(&ra).contains("handoff-brief.sh read --note"),
        "{why}: {ra}"
    );
}

#[test]
fn a_symlinked_entry_is_not_used() {
    let fx = Fx::new();
    let target = fx.p("target");
    fs::write(&target, good_entry()).unwrap();
    fs::set_permissions(&target, fs::Permissions::from_mode(0o600)).unwrap();
    fs::remove_file(fx.entry_path()).unwrap();
    std::os::unix::fs::symlink(&target, fx.entry_path()).unwrap();
    assert_not_used(&fx, &[], "symlinked entry");
}

#[test]
fn an_entry_that_is_not_a_regular_file_is_not_used() {
    let fx = Fx::new();
    fs::remove_file(fx.entry_path()).unwrap();
    fs::create_dir(fx.entry_path()).unwrap();
    assert_not_used(&fx, &[], "directory entry");
}

#[test]
fn an_entry_not_mode_0600_is_not_used() {
    let fx = Fx::new();
    for m in [0o644, 0o640, 0o700] {
        fs::set_permissions(fx.entry_path(), fs::Permissions::from_mode(m)).unwrap();
        assert_not_used(&fx, &[], &format!("entry mode {m:o}"));
    }
}

#[test]
fn a_directory_not_0700_or_symlinked_is_not_used() {
    let fx = Fx::new();
    let dir = fx.p("state/shirabe/compaction");
    fs::set_permissions(&dir, fs::Permissions::from_mode(0o755)).unwrap();
    assert_not_used(&fx, &[], "directory mode 0755");
    fs::set_permissions(&dir, fs::Permissions::from_mode(0o700)).unwrap();

    // The ledger directory is a link to a real 0700 directory holding a good
    // entry.
    let real = fx.p("real-compaction");
    fs::rename(&dir, &real).unwrap();
    std::os::unix::fs::symlink(&real, &dir).unwrap();
    assert_not_used(&fx, &[], "symlinked directory");
}

#[test]
fn an_entry_with_a_field_failing_its_grammar_is_not_used() {
    let good = good_entry();
    let ctl = format!("branch: {BRANCH}\u{7}x");
    let two_roots = format!("{good}skill: shirabe:scope /tmp/elsewhere/skills/scope/SKILL.md\n");
    let cases: Vec<(&str, String)> = vec![
        (
            "koto session outside koto's grammar",
            good.replace(
                &format!("koto_session: {KS}"),
                "koto_session: ../probe-run-x7",
            ),
        ),
        (
            "note key other than compaction/note.md",
            good.replace("note_key: compaction/note.md", "note_key: brief/brief.md"),
        ),
        (
            "branch with a control character",
            good.replace(&format!("branch: {BRANCH}"), &ctl),
        ),
        (
            "skill path outside a plugin root",
            good.replace(SKILL, "/opt/plugins/shirabe/0.50.0/deliver/SKILL.md"),
        ),
        ("skills of one plugin under two roots", two_roots),
    ];
    for (why, text) in cases {
        let fx = Fx::new();
        fx.entry(&text);
        assert_not_used(&fx, &[], why);
    }
}

#[test]
fn an_entry_for_another_koto_session_is_not_used() {
    let fx = Fx::new();
    assert_not_used(
        &fx,
        &[("KOTO_SESSION", "someone-else")],
        "KOTO_SESSION mismatch",
    );
    // The matching name is used.
    let out = fx.run_with(
        "pre-compact",
        "repo",
        &["kbin", "bin", "tools"],
        &fx.input(),
        &[("KOTO_SESSION", KS)],
    );
    assert!(out.contains(KS), "{out}");
}

// --- no usable entry, and an invalid session id ----------------------------------------

#[test]
fn no_entry_names_the_branch_and_prints_the_generic_line() {
    let fx = Fx::new();
    fs::remove_file(fx.entry_path()).unwrap();
    let pc = fx.run("pre-compact", "other");
    assert!(pc.contains("No compaction note is recorded"), "{pc}");
    assert!(pc.contains(&format!("- branch: {OTHER_BRANCH}")), "{pc}");
    assert!(pc.chars().count() < 10_000);
    assert!(!pc.contains(INPUT_MARKER));
    let ra = fx.run("re-anchor", "other");
    assert!(ra.chars().count() < 10_000);
    assert!(!ra.contains(INPUT_MARKER));
    let ctx = context_of(&ra);
    for want in [
        "`deliver-`",
        "`scope-`",
        "`coordinate-`",
        "SKILL.md",
        "koto status",
        "worktree",
        "handoff-brief.sh read --note",
    ] {
        assert!(ctx.contains(want), "missing {want}: {ctx}");
    }
    // Outside a repository the branch can't be read, and it says so.
    let pc = fx.run("pre-compact", "plain");
    assert!(pc.contains("could not be read from git"), "{pc}");
    // No ledger directory at all is the same as no entry.
    fs::remove_dir_all(fx.p("state/shirabe")).unwrap();
    assert!(fx.run("pre-compact", "other").contains(OTHER_BRANCH));
    assert!(context_of(&fx.run("re-anchor", "other")).contains("read --note"));
}

#[test]
fn an_invalid_session_id_gets_no_output() {
    let fx = Fx::new();
    for sid in ["a/b", "..", "a\nb", "../../etc/passwd", ""] {
        let input = serde_json::json!({ "session_id": sid }).to_string();
        for sub in ["pre-compact", "re-anchor"] {
            let out = fx.run_with(sub, "repo", &["kbin", "bin", "tools"], &input, &[]);
            assert!(out.is_empty(), "{sub} {sid:?}: {out}");
        }
    }
    for input in ["not json", "{}", r#"{"session_id":7}"#] {
        for sub in ["pre-compact", "re-anchor"] {
            let out = fx.run_with(sub, "repo", &["kbin", "bin", "tools"], input, &[]);
            assert!(out.is_empty(), "{sub} {input:?}: {out}");
        }
    }
    // Nothing ran: no koto call, no git call.
    assert!(!fx.p("stub/log").exists());
    assert!(!fx.p("git.log").exists());
}

#[test]
fn re_anchor_with_a_good_entry_is_unchanged() {
    let fx = Fx::new();
    let ctx = context_of(&fx.run("re-anchor", "repo"));
    let a = ctx.find(SKILL).unwrap();
    let b = ctx.find(&format!("koto status {KS}")).unwrap();
    let c = ctx
        .find(&format!("koto context get {KS} compaction/note.md"))
        .unwrap();
    assert!(a < b && b < c);
    assert!(!ctx.contains(INPUT_MARKER));
}
