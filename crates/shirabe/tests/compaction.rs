//! CLI integration tests for `shirabe compaction pre-compact` and
//! `re-anchor`: the stale flag and its inputs, the ledger checks, and the
//! outputs for a session with no usable entry.
//!
//! Every run clears the environment and puts only stand-ins on `PATH`: a koto
//! stub that answers `context history`, `context list`, `status` and
//! `session dir` from files under `$KOTO_STUB` (it never touches a koto
//! store; the session directory it names holds a fixture event log), a `gh` stub that
//! logs each call, and a `git` wrapper that logs its arguments (and, in a
//! second log, its `GIT_NO_LAZY_FETCH` and `GIT_ALLOW_PROTOCOL`) and runs the
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
# A grandchild that keeps this call's stdout open after it exits.
if [ -f "$KOTO_STUB/linger" ]; then sleep 30 & fi
f=""
case "$1:${2-}" in
    context:history) f="$KOTO_STUB/history/${4//\//__}" ;;
    context:list) f="$KOTO_STUB/list" ;;
    status:*) f="$KOTO_STUB/status" ;;
    session:dir) f="$KOTO_STUB/session-dir" ;;
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

/// The good entry with a `repo:` line naming `repo`.
fn entry_with_repo(repo: &str) -> String {
    good_entry().replace(
        &format!("branch: {BRANCH}\n"),
        &format!("branch: {BRANCH}\nrepo: {repo}\n"),
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
            "sessions/probe-run-x7",
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
                "#!/bin/bash\nprintf '%s\\n' \"$*\" >>\"$GIT_LOG\"\n\
printf 'GIT_NO_LAZY_FETCH=%s GIT_ALLOW_PROTOCOL=%s\\n' \
\"${{GIT_NO_LAZY_FETCH-<unset>}}\" \"${{GIT_ALLOW_PROTOCOL-<unset>}}\" >>\"$GIT_LOG.env\"\n\
exec '{}' \"$@\"\n",
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
        // The run's event log agrees: the note's write, seq 5, is its last
        // event.
        fx.session_dir(&fx.p("sessions").join(KS).display().to_string());
        fx.events(&[
            ev(1, "workflow_initialized"),
            ev(2, "transitioned"),
            ev(3, "context_added"),
            ev(4, "evidence_submitted"),
            ev(5, "context_added"),
        ]);
        fx.entry(&good_entry());
        fx
    }

    /// What the koto stub prints for `koto session dir`.
    fn session_dir(&self, dir: &str) {
        fs::write(self.p("stub/session-dir"), dir).unwrap();
    }

    fn log_path(&self) -> PathBuf {
        self.p("sessions")
            .join(KS)
            .join(format!("koto-{KS}.state.jsonl"))
    }

    /// Write the run's event log: a header line, then one line per event.
    fn events(&self, lines: &[String]) {
        let mut body = format!(
            "{}\n",
            serde_json::json!({"schema_version": 1, "workflow": KS, "template_hash": "00",
                "created_at": "2026-06-01T10:00:00.000Z"})
        );
        for l in lines {
            body.push_str(l);
            body.push('\n');
        }
        fs::write(self.log_path(), body).unwrap();
    }

    /// Append events to the run's log.
    fn add_events(&self, lines: &[String]) {
        let mut body = fs::read_to_string(self.log_path()).unwrap();
        for l in lines {
            body.push_str(l);
            body.push('\n');
        }
        fs::write(self.log_path(), body).unwrap();
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
/// The re-anchor's line for a note nothing came after.
const FRESH: &str = "The compaction note is fresh";
/// The re-anchor step that puts the rewrite first.
const REWRITE: &str = "Rewrite the compaction note before any other work";

/// One event-log line, as koto writes it.
fn ev(seq: u64, ty: &str) -> String {
    ev_with(seq, ty, serde_json::json!({}))
}

fn ev_with(seq: u64, ty: &str, payload: serde_json::Value) -> String {
    serde_json::json!({"seq": seq, "timestamp": "2026-06-01T12:10:00.000Z", "type": ty,
        "payload": payload})
    .to_string()
}

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
fn an_event_after_the_note_in_the_same_state_makes_it_stale() {
    // Evidence, a decision, an override, or a transition that comes back to
    // the note's own state: no key written and no state changed, but the run
    // moved on after the note.
    for ty in [
        "evidence_submitted",
        "decision_recorded",
        "gate_override_recorded",
        "transitioned",
    ] {
        let fx = Fx::new();
        fx.add_events(&[ev(6, ty)]);
        let out = fx.pre_compact();
        assert_eq!(out.matches(STALE).count(), 1, "{ty}: {out}");
        assert!(
            out.contains("first step after the compaction"),
            "{ty}: {out}"
        );
        assert!(!out.contains(UNKNOWN), "{ty}: {out}");
        // Rewriting the note puts its write after the event.
        fx.history(
            "compaction/note.md",
            &[(5, NOTE_AT, Some("work")), (7, NOTE_AT, Some("work"))],
        );
        fx.add_events(&[ev(7, "context_added")]);
        let out = fx.pre_compact();
        assert!(!out.contains(STALE), "{ty}: {out}");
        assert!(!out.contains(UNKNOWN), "{ty}: {out}");
    }
}

#[test]
fn a_manual_compaction_is_judged_the_same() {
    let fx = Fx::new();
    fx.add_events(&[ev(6, "evidence_submitted")]);
    let input = serde_json::json!({
        "session_id": SID,
        "hook_event_name": "PreCompact",
        "trigger": "manual",
        "custom_instructions": INPUT_MARKER,
    })
    .to_string();
    let out = fx.run_with(
        "pre-compact",
        "repo",
        &["kbin", "bin", "tools"],
        &input,
        &[],
    );
    assert_eq!(out.matches(STALE).count(), 1, "{out}");
    assert!(!out.contains(INPUT_MARKER), "{out}");
}

#[test]
fn a_read_an_import_or_a_sync_after_the_note_does_not_make_it_stale() {
    let fx = Fx::new();
    fx.add_events(&[
        ev_with(
            6,
            "context_read",
            serde_json::json!({"key": "compaction/note.md", "reader": "cli", "state": "work",
                "present": true}),
        ),
        ev(7, "session_imported"),
        ev_with(
            8,
            "context_added",
            serde_json::json!({"key": "compaction/note.md", "hash": "00", "size": 1,
                "writer": "sync"}),
        ),
    ]);
    let out = fx.pre_compact();
    assert!(!out.contains(STALE), "{out}");
    assert!(!out.contains(UNKNOWN), "{out}");
}

#[test]
fn an_unreadable_event_log_leaves_freshness_unknown() {
    // No log in the session directory.
    let fx = Fx::new();
    fs::remove_file(fx.log_path()).unwrap();
    assert_unknown(&fx.pre_compact());

    // koto can't name the session directory.
    let fx = Fx::new();
    fs::remove_file(fx.p("stub/session-dir")).unwrap();
    assert_unknown(&fx.pre_compact());

    // A directory that isn't absolute, though it names the log from the
    // hook's working directory, or one that holds a control character.
    let fx = Fx::new();
    fx.entry(&entry_with_repo(&fx.p("repo").display().to_string()));
    let out = fx.run("pre-compact", ".");
    assert!(!out.contains(STALE) && !out.contains(UNKNOWN), "{out}");
    fx.session_dir(&format!("sessions/{KS}"));
    assert_unknown(&fx.run("pre-compact", "."));
    fx.session_dir(&format!("{}\u{7}", fx.p("sessions").join(KS).display()));
    assert_unknown(&fx.run("pre-compact", "."));

    // A log that is a link, or not a regular file.
    let fx = Fx::new();
    let real = fx.p("plain/log.jsonl");
    fs::rename(fx.log_path(), &real).unwrap();
    std::os::unix::fs::symlink(&real, fx.log_path()).unwrap();
    assert_unknown(&fx.pre_compact());
    fs::remove_file(fx.log_path()).unwrap();
    fs::create_dir(fx.log_path()).unwrap();
    assert_unknown(&fx.pre_compact());

    // A log with no event line in it.
    let fx = Fx::new();
    fx.events(&[]);
    assert_unknown(&fx.pre_compact());
    fs::write(fx.log_path(), "not json\n").unwrap();
    assert_unknown(&fx.pre_compact());
}

#[test]
fn a_stale_finding_wins_over_an_unreadable_log() {
    let fx = Fx::new();
    fs::remove_file(fx.log_path()).unwrap();
    fx.status("review");
    let out = fx.pre_compact();
    assert!(out.contains(STALE), "{out}");
    assert!(!out.contains(UNKNOWN), "{out}");
}

/// A read event padded out, so a few thousand of them pass the log tail the
/// hooks read.
fn padded_read(seq: u64) -> String {
    ev_with(
        seq,
        "context_read",
        serde_json::json!({"key": "compaction/note.md", "reader": "cli", "state": "work",
            "present": true, "pad": "p".repeat(400)}),
    )
}

#[test]
fn a_long_log_is_read_from_its_tail() {
    // Over a mebibyte of reads before the note's write and an event after it.
    let fx = Fx::new();
    let mut lines: Vec<String> = (1..=4000).map(padded_read).collect();
    lines.push(ev(4001, "context_added"));
    lines.push(ev(4002, "evidence_submitted"));
    fx.events(&lines);
    assert!(fs::metadata(fx.log_path()).unwrap().len() > 1024 * 1024);
    fx.history("compaction/note.md", &[(4001, NOTE_AT, Some("work"))]);
    let out = fx.pre_compact();
    assert_eq!(out.matches(STALE).count(), 1, "{out}");

    // With nothing after the note's write, the tail shows it current.
    let lines: Vec<String> = (1..=4000)
        .map(padded_read)
        .chain([ev(4001, "context_added")])
        .collect();
    fx.events(&lines);
    let out = fx.pre_compact();
    assert!(!out.contains(STALE), "{out}");
    assert!(!out.contains(UNKNOWN), "{out}");
}

#[test]
fn a_tail_of_reads_past_the_note_leaves_freshness_unknown() {
    // The note was written at seq 5, and the tail the hooks read holds only
    // reads from well after it: what came between can't be seen.
    let fx = Fx::new();
    let mut lines = vec![ev(5, "context_added")];
    lines.extend((6..=4000).map(padded_read));
    fx.events(&lines);
    assert_unknown(&fx.pre_compact());
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
            line.starts_with(
                "-c core.fsmonitor=false -c core.hooksPath=/dev/null -c log.showSignature=false "
            ),
            "unsafe git call: {line}"
        );
    }
}

/// Put a commit object carrying a hand-written `gpgsig` header at
/// `refs/heads/<BRANCH>` of `repo`, so `git log --show-signature` would hand
/// it to `gpg.program`. Its commit time predates the note.
fn sign_tip(fx: &Fx, repo: &str) {
    let rev = |what: &str| {
        let out = fx.git_cmd(repo).args(["rev-parse", what]).output().unwrap();
        assert!(out.status.success(), "rev-parse {what}: {out:?}");
        String::from_utf8(out.stdout).unwrap().trim().to_string()
    };
    let tree = rev("HEAD^{tree}");
    let parent = rev("HEAD");
    let body = format!(
        "tree {tree}\nparent {parent}\n\
author t <t@example.com> 1780300000 +0000\n\
committer t <t@example.com> 1780300000 +0000\n\
gpgsig -----BEGIN PGP SIGNATURE-----\n \n iQEzBAABCAAdFiEEAAAAAAAAAAAAAAAAAAAAAAAAAAAFAmAAAAAACgkQAAAAAAAAAAAA\n =AAAA\n -----END PGP SIGNATURE-----\n\nsigned\n"
    );
    let mut child = fx
        .git_cmd(repo)
        .args(["hash-object", "-t", "commit", "-w", "--stdin"])
        .stdin(std::process::Stdio::piped())
        .stdout(std::process::Stdio::piped())
        .spawn()
        .unwrap();
    {
        use std::io::Write;
        let mut stdin = child.stdin.take().unwrap();
        stdin.write_all(body.as_bytes()).unwrap();
    }
    let out = child.wait_with_output().unwrap();
    assert!(out.status.success(), "hash-object: {out:?}");
    let sha = String::from_utf8(out.stdout).unwrap().trim().to_string();
    fx.git_ok(repo, &["update-ref", &format!("refs/heads/{BRANCH}"), &sha]);
}

#[test]
fn a_repository_signature_program_fsmonitor_or_hook_never_runs() {
    let fx = Fx::new();
    let marker = fx.p("marker");
    let prog = fx.p("mark.sh");
    write_exec(
        &prog,
        &format!(
            "#!/bin/bash\nprintf 'ran %s\\n' \"$*\" >>'{}'\n",
            marker.display()
        ),
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
    let prog_s = prog.display().to_string();
    let hooks_s = fx.p("hooks").display().to_string();
    for repo in ["repo", "other"] {
        for (k, v) in [
            ("core.fsmonitor", prog_s.as_str()),
            ("core.hooksPath", hooks_s.as_str()),
            ("log.showSignature", "true"),
            ("gpg.program", prog_s.as_str()),
        ] {
            fx.git_ok(repo, &["config", k, v]);
        }
    }
    sign_tip(&fx, "repo");
    // The fixture can fire: the same `git log` without the hook's flags runs
    // the signature program.
    let refname = format!("refs/heads/{BRANCH}");
    let probe = fx
        .git_cmd("repo")
        .args(["log", "-1", "--format=%ct", &refname, "--"])
        .output()
        .unwrap();
    assert!(probe.status.success(), "{probe:?}");
    assert!(marker.exists(), "the fixture's signature program never ran");
    fs::remove_file(&marker).unwrap();

    // With the entry, from the repository, then through the entry's repo line.
    let out = fx.pre_compact();
    assert!(
        !marker.exists(),
        "a repository program ran: {:?}",
        fs::read_to_string(&marker)
    );
    assert!(out.contains(KS) && !out.contains(UNKNOWN), "{out}");
    fx.entry(&entry_with_repo(&fx.p("repo").display().to_string()));
    let out = fx.run("pre-compact", "plain");
    assert!(
        !marker.exists(),
        "a repository program ran: {:?}",
        fs::read_to_string(&marker)
    );
    assert!(out.contains(KS) && !out.contains(UNKNOWN), "{out}");
    // With no entry, from the other repository.
    fs::remove_file(fx.entry_path()).unwrap();
    let out = fx.run("pre-compact", "other");
    assert!(out.contains(OTHER_BRANCH), "{out}");
    assert!(!marker.exists(), "a repository program ran");
}

/// Build `pc`: a partial clone whose promisor remote's upload-pack is
/// `mark.sh`, and whose branch tip is a commit missing from the object store,
/// so reading the tip makes git fetch it. Returns the marker `mark.sh`
/// writes.
fn partial_clone(fx: &Fx) -> PathBuf {
    let marker = fx.p("marker");
    let prog = fx.p("mark.sh");
    write_exec(
        &prog,
        &format!(
            "#!/bin/bash\nprintf 'ran %s\\n' \"$*\" >>'{}'\nexit 1\n",
            marker.display()
        ),
    );
    fs::create_dir_all(fx.p("pc")).unwrap();
    fx.init_repo("pc", BRANCH);
    fx.commit("pc", AFTER_NOTE);
    let out = fx
        .git_cmd("pc")
        .args(["rev-parse", "HEAD"])
        .output()
        .unwrap();
    assert!(out.status.success(), "{out:?}");
    let tip = String::from_utf8(out.stdout).unwrap().trim().to_string();
    let url = fx.p("repo").display().to_string();
    let prog_s = prog.display().to_string();
    for (k, v) in [
        ("core.repositoryformatversion", "1"),
        ("extensions.partialClone", "origin"),
        ("remote.origin.url", url.as_str()),
        ("remote.origin.promisor", "true"),
        ("remote.origin.uploadpack", prog_s.as_str()),
    ] {
        fx.git_ok("pc", &["config", k, v]);
    }
    fs::remove_file(fx.p("pc/.git/objects").join(&tip[..2]).join(&tip[2..])).unwrap();
    marker
}

#[test]
fn a_promisor_remote_program_never_runs_through_a_lazy_fetch() {
    let fx = Fx::new();
    let marker = partial_clone(&fx);

    // The fixture can fire: the same `git log` without GIT_NO_LAZY_FETCH runs
    // the promisor remote's program.
    let refname = format!("refs/heads/{BRANCH}");
    let _ = fx
        .git_cmd("pc")
        .env_remove("GIT_NO_LAZY_FETCH")
        .args(["log", "-1", "--format=%ct", &refname, "--"])
        .output()
        .unwrap();
    assert!(
        marker.exists(),
        "the fixture's upload-pack program never ran"
    );
    fs::remove_file(&marker).unwrap();

    // Through the entry's repo line, from outside the repository, then from
    // the repository with no repo line.
    fx.entry(&entry_with_repo(&fx.p("pc").display().to_string()));
    let out = fx.run("pre-compact", "plain");
    assert!(
        !marker.exists(),
        "a repository program ran: {:?}",
        fs::read_to_string(&marker)
    );
    assert!(out.contains(KS) && out.contains(UNKNOWN), "{out}");
    // The unknown line would also come from a refused repo line falling back
    // to `plain`, so the record shows the hook did read the tip in `pc`.
    let log = fs::read_to_string(fx.p("git.log")).unwrap_or_default();
    assert!(
        log.contains(&format!(
            "-C {} log -1 --no-show-signature",
            fx.p("pc").display()
        )),
        "the repo line's git log never ran: {log}"
    );
    fx.entry(&good_entry());
    let out = fx.run("pre-compact", "pc");
    assert!(
        !marker.exists(),
        "a repository program ran: {:?}",
        fs::read_to_string(&marker)
    );
    assert!(out.contains(KS) && out.contains(UNKNOWN), "{out}");
}

/// An empty `GIT_ALLOW_PROTOCOL` keeps the promisor remote's transport from
/// running on its own, with no `GIT_NO_LAZY_FETCH`, as on a git that ignores
/// that variable: over the file transport (`remote.origin.uploadpack`), ssh
/// (`core.sshCommand`) and a remote helper the repository allows
/// (`ext::` with `protocol.ext.allow=always`). Each probe is the hook's own
/// `git log` call.
#[test]
fn an_empty_git_allow_protocol_alone_keeps_the_promisor_transport_from_running() {
    let fx = Fx::new();
    let marker = partial_clone(&fx);
    let prog_s = fx.p("mark.sh").display().to_string();
    let ext_url = format!("ext::{prog_s} %S x");
    let refname = format!("refs/heads/{BRANCH}");
    let args = [
        "-c",
        "core.fsmonitor=false",
        "-c",
        "core.hooksPath=/dev/null",
        "-c",
        "log.showSignature=false",
        "log",
        "-1",
        "--no-show-signature",
        "--format=%ct",
        refname.as_str(),
        "--",
    ];
    let variants: Vec<(&str, Vec<(&str, &str)>)> = vec![
        ("upload-pack over file", vec![]),
        (
            "core.sshCommand over ssh",
            vec![
                ("remote.origin.url", "ssh://example.invalid/x"),
                ("core.sshCommand", prog_s.as_str()),
            ],
        ),
        (
            "remote helper over ext",
            vec![
                ("remote.origin.url", ext_url.as_str()),
                ("protocol.ext.allow", "always"),
            ],
        ),
    ];
    for (what, config) in variants {
        for (k, v) in config {
            fx.git_ok("pc", &["config", k, v]);
        }
        // The fixture can fire: with neither variable, the call runs the
        // transport's program.
        let _ = fx
            .git_cmd("pc")
            .env_remove("GIT_NO_LAZY_FETCH")
            .env_remove("GIT_ALLOW_PROTOCOL")
            .args(args)
            .output()
            .unwrap();
        assert!(marker.exists(), "{what}: the fixture's program never ran");
        fs::remove_file(&marker).unwrap();
        let out = fx
            .git_cmd("pc")
            .env_remove("GIT_NO_LAZY_FETCH")
            .env("GIT_ALLOW_PROTOCOL", "")
            .args(args)
            .output()
            .unwrap();
        assert!(!out.status.success(), "{what}: the tip was read: {out:?}");
        assert!(
            !marker.exists(),
            "{what}: the transport ran: {:?}",
            fs::read_to_string(&marker)
        );
    }
}

/// Every hook `git` call runs with `GIT_NO_LAZY_FETCH=1` and an empty
/// `GIT_ALLOW_PROTOCOL`, whatever the hook inherited.
#[test]
fn every_git_call_carries_no_lazy_fetch_and_no_allowed_protocol() {
    let fx = Fx::new();
    let inherited = [
        ("GIT_NO_LAZY_FETCH", "0"),
        ("GIT_ALLOW_PROTOCOL", "file:ssh:ext"),
    ];
    let path = ["kbin", "bin", "tools"];
    let _ = fx.run_with("pre-compact", "repo", &path, &fx.input(), &inherited);
    fx.entry(&entry_with_repo(&fx.p("repo").display().to_string()));
    let _ = fx.run_with("pre-compact", "plain", &path, &fx.input(), &inherited);
    fs::remove_file(fx.entry_path()).unwrap();
    let _ = fx.run_with("pre-compact", "other", &path, &fx.input(), &inherited);
    let calls = fs::read_to_string(fx.p("git.log")).unwrap();
    let envs = fs::read_to_string(fx.p("git.log.env")).unwrap();
    assert!(calls.lines().count() >= 4, "{calls}");
    assert_eq!(envs.lines().count(), calls.lines().count(), "{envs}");
    for line in envs.lines() {
        assert_eq!(line, "GIT_NO_LAZY_FETCH=1 GIT_ALLOW_PROTOCOL=", "{envs}");
    }
}

// --- the entry's repository -----------------------------------------------------------

#[test]
fn a_commit_is_seen_through_the_entry_repo_from_outside_the_repository() {
    let fx = Fx::new();
    fx.entry(&entry_with_repo(&fx.p("repo").display().to_string()));
    // From a directory that is no repository: fresh, then stale on a commit.
    let out = fx.run("pre-compact", "plain");
    assert!(out.contains(KS), "{out}");
    assert!(!out.contains(STALE) && !out.contains(UNKNOWN), "{out}");
    fx.commit("repo", AFTER_NOTE);
    let out = fx.run("pre-compact", "plain");
    assert_eq!(out.matches(STALE).count(), 1, "{out}");
    // From a repository with no such branch, the entry's repository still
    // answers.
    let out = fx.run("pre-compact", "other");
    assert_eq!(out.matches(STALE).count(), 1, "{out}");
    let log = fs::read_to_string(fx.p("git.log")).unwrap();
    assert!(
        log.contains(&format!("-C {} log -1", fx.p("repo").display())),
        "{log}"
    );
}

/// A refused repo line falls back to the hook's working directory: the
/// branch isn't in `other`, so the freshness is unknown there, and the
/// commit is seen from `repo`. Had the repo line been used, `other` would
/// have shown the note stale.
fn assert_repo_refused(fx: &Fx, why: &str) {
    let out = fx.run("pre-compact", "other");
    assert!(out.contains(KS), "{why}: the entry was not used: {out}");
    assert!(
        out.contains(UNKNOWN) && !out.contains(STALE),
        "{why}: {out}"
    );
    let out = fx.run("pre-compact", "repo");
    assert_eq!(out.matches(STALE).count(), 1, "{why}: {out}");
}

#[test]
fn a_repo_line_outside_a_work_tree_is_refused_and_falls_back() {
    let fx = Fx::new();
    fx.commit("repo", AFTER_NOTE);
    // The repository's .git directory: git reads the branch there, but it
    // isn't inside a work tree.
    fx.entry(&entry_with_repo(&fx.p("repo/.git").display().to_string()));
    assert_repo_refused(&fx, "a git directory");
    fx.entry(&entry_with_repo(&fx.p("plain").display().to_string()));
    assert_repo_refused(&fx, "no repository");
    fx.entry(&entry_with_repo(&fx.p("repo/f.txt").display().to_string()));
    assert_repo_refused(&fx, "a file");
    fx.entry(&entry_with_repo(&fx.p("gone").display().to_string()));
    assert_repo_refused(&fx, "a missing path");
}

#[test]
fn a_repo_line_that_is_a_symlink_is_refused_and_falls_back() {
    let fx = Fx::new();
    fx.commit("repo", AFTER_NOTE);
    std::os::unix::fs::symlink(fx.p("repo"), fx.p("repo-link")).unwrap();
    fx.entry(&entry_with_repo(&fx.p("repo-link").display().to_string()));
    assert_repo_refused(&fx, "a symlink");
}

#[test]
fn a_repo_line_failing_its_grammar_is_refused_and_falls_back() {
    let fx = Fx::new();
    fx.commit("repo", AFTER_NOTE);
    // Each refused path is a real work tree whose branch has a commit newer
    // than the note, so only the grammar keeps it from making the note stale
    // from `other`: a directory whose name holds U+200B, and `other/repo`,
    // where the relative `repo` lands from the hook's working directory.
    for dir in ["zw\u{200b}", "other/repo"] {
        fs::create_dir_all(fx.p(dir)).unwrap();
        fx.init_repo(dir, BRANCH);
        fx.commit(dir, AFTER_NOTE);
    }
    // Spelled absolute, `other/repo` passes the grammar and is used.
    fx.entry(&entry_with_repo(&fx.p("other/repo").display().to_string()));
    let out = fx.run("pre-compact", "other");
    assert_eq!(out.matches(STALE).count(), 1, "the fixture: {out}");

    fx.entry(&entry_with_repo(&fx.p("zw\u{200b}").display().to_string()));
    assert_repo_refused(&fx, "a format character");
    fx.entry(&entry_with_repo("repo"));
    assert_repo_refused(&fx, "a relative path");
}

#[test]
fn an_entry_with_no_repo_line_reads_the_branch_in_the_working_directory() {
    let fx = Fx::new();
    fx.commit("repo", AFTER_NOTE);
    assert_eq!(fx.pre_compact().matches(STALE).count(), 1);
    let out = fx.run("pre-compact", "plain");
    assert!(out.contains(UNKNOWN) && !out.contains(STALE), "{out}");
    let log = fs::read_to_string(fx.p("git.log")).unwrap();
    assert!(!log.contains(" -C "), "{log}");
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
fn a_grandchild_holding_a_tools_stdout_does_not_hold_the_hook() {
    let fx = Fx::new();
    fs::write(fx.p("stub/linger"), "").unwrap();
    let t = Instant::now();
    let out = fx.pre_compact();
    assert_unknown(&out);
    // Inside the 20-second budget for the whole read, though each lingering
    // call's grandchild holds the pipe for 30.
    assert!(t.elapsed().as_secs() < 20, "took {:?}", t.elapsed());
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
        .find(&format!("handoff-brief.sh read --note --session {KS}"))
        .unwrap();
    assert!(a < b && b < c);
    assert!(!ctx.contains(INPUT_MARKER));
}

#[test]
fn an_entry_whose_re_anchor_would_reach_the_cap_gets_the_generic_steps() {
    let fx = Fx::new();
    // Eight skills each with six 200-character arguments: within the 16 KiB
    // the hooks read, but a re-anchor block over 10,000 characters.
    let arg = "q".repeat(200);
    let args = [arg.as_str(); 6].join(" ");
    let mut text =
        format!("koto_session: {KS}\nnote_key: compaction/note.md\nbranch: {BRANCH}\npr: {PR}\n");
    for _ in 0..8 {
        text.push_str(&format!("skill: shirabe:deliver {args} {SKILL}\n"));
    }
    assert!(text.len() < 16 * 1024 && text.len() > 10_000);
    fx.entry(&text);
    // The entry is usable: pre-compact names it.
    assert!(fx.pre_compact().contains(KS));
    let ra = fx.run("re-anchor", "repo");
    assert!(ra.chars().count() < 10_000);
    let ctx = context_of(&ra);
    assert!(ctx.contains("too long to show"), "{ctx}");
    assert!(!ctx.contains("no compaction note is recorded"), "{ctx}");
    for want in [
        "`deliver-`",
        "SKILL.md",
        "koto status",
        "handoff-brief.sh read --note --session",
    ] {
        assert!(ctx.contains(want), "missing {want}: {ctx}");
    }
    for text in [KS, SKILL, arg.as_str(), INPUT_MARKER] {
        assert!(!ctx.contains(text), "printed {text}: {ctx}");
    }
    // With the entry gone, the no-entry wording is unchanged.
    fs::remove_file(fx.entry_path()).unwrap();
    let ctx = context_of(&fx.run("re-anchor", "repo"));
    assert!(ctx.contains("no compaction note is recorded"), "{ctx}");
    assert!(!ctx.contains("too long to show"), "{ctx}");
}

// --- the re-anchor's freshness verdict -------------------------------------------------

fn re_anchor(fx: &Fx) -> String {
    let ra = fx.run("re-anchor", "repo");
    assert!(ra.chars().count() < 10_000);
    assert!(!ra.contains(INPUT_MARKER), "input text printed: {ra}");
    context_of(&ra)
}

/// The stale verdict, then the rewrite as the step after reading the note
/// and before carrying on.
fn assert_re_anchor_stale(ctx: &str) {
    assert_eq!(ctx.matches(STALE).count(), 1, "{ctx}");
    assert!(!ctx.contains(FRESH), "{ctx}");
    assert!(!ctx.contains(UNKNOWN), "{ctx}");
    let verdict = ctx.find(STALE).unwrap();
    let read = ctx.find("handoff-brief.sh read --note").unwrap();
    let rewrite = ctx.find(REWRITE).expect("no rewrite step");
    let carry_on = ctx.find("Then carry on").unwrap();
    assert!(
        verdict < read && read < rewrite && rewrite < carry_on,
        "{ctx}"
    );
    assert!(ctx.contains("`handoff-brief.sh note`"), "{ctx}");
}

#[test]
fn re_anchor_says_a_stale_note_is_stale_and_to_rewrite_it_first() {
    // An event in the note's own state after its write.
    let fx = Fx::new();
    fx.add_events(&[ev(6, "evidence_submitted")]);
    assert_re_anchor_stale(&re_anchor(&fx));

    // A transition to another state.
    let fx = Fx::new();
    fx.status("review");
    assert_re_anchor_stale(&re_anchor(&fx));

    // A newer commit on the branch.
    let fx = Fx::new();
    fx.commit("repo", AFTER_NOTE);
    assert_re_anchor_stale(&re_anchor(&fx));

    // A key written after the note.
    let fx = Fx::new();
    fx.history(
        "brief/brief.md",
        &[(7, "2026-06-01T12:05:00.000Z", Some("work"))],
    );
    assert_re_anchor_stale(&re_anchor(&fx));
}

#[test]
fn re_anchor_names_a_fresh_note_fresh() {
    let fx = Fx::new();
    let ctx = re_anchor(&fx);
    assert_eq!(ctx.matches(FRESH).count(), 1, "{ctx}");
    assert!(!ctx.contains(STALE), "{ctx}");
    assert!(!ctx.contains(UNKNOWN), "{ctx}");
    assert!(!ctx.contains(REWRITE), "{ctx}");
    // The steps keep their order behind the verdict.
    let f = ctx.find(FRESH).unwrap();
    let a = ctx.find(SKILL).unwrap();
    let b = ctx.find(&format!("koto status {KS}")).unwrap();
    let c = ctx
        .find(&format!("handoff-brief.sh read --note --session {KS}"))
        .unwrap();
    assert!(f < a && a < b && b < c, "{ctx}");
}

/// Freshness unknown: said so, never called fresh or stale.
fn assert_re_anchor_unknown(ctx: &str) {
    assert_eq!(ctx.matches(UNKNOWN).count(), 1, "{ctx}");
    assert!(!ctx.contains(FRESH), "{ctx}");
    assert!(!ctx.contains(STALE), "{ctx}");
    assert!(ctx.contains(&format!("koto status {KS}")), "{ctx}");
}

#[test]
fn re_anchor_never_calls_an_unreadable_note_fresh() {
    let fx = Fx::new();
    let out = fx.run_with("re-anchor", "repo", &["bin", "tools"], &fx.input(), &[]);
    assert_re_anchor_unknown(&context_of(&out));

    let fx = Fx::new();
    fs::remove_file(fx.log_path()).unwrap();
    assert_re_anchor_unknown(&re_anchor(&fx));

    let fx = Fx::new();
    fs::remove_file(fx.p("stub/history/compaction__note.md")).unwrap();
    assert_re_anchor_unknown(&re_anchor(&fx));

    let fx = Fx::new();
    let out = fx.run_with("re-anchor", "repo", &["kbin", "tools"], &fx.input(), &[]);
    assert_re_anchor_unknown(&context_of(&out));

    let fx = Fx::new();
    let mut lines = vec![ev(5, "context_added")];
    lines.extend((6..=4000).map(padded_read));
    fx.events(&lines);
    assert_re_anchor_unknown(&re_anchor(&fx));
}

#[test]
fn re_anchor_over_the_cap_still_carries_the_verdict() {
    let fx = Fx::new();
    let arg = "q".repeat(200);
    let args = [arg.as_str(); 6].join(" ");
    let mut text =
        format!("koto_session: {KS}\nnote_key: compaction/note.md\nbranch: {BRANCH}\npr: {PR}\n");
    for _ in 0..8 {
        text.push_str(&format!("skill: shirabe:deliver {args} {SKILL}\n"));
    }
    fx.entry(&text);
    let ctx = re_anchor(&fx);
    assert!(ctx.contains("too long to show"), "{ctx}");
    assert!(ctx.contains(FRESH), "{ctx}");
    fx.add_events(&[ev(6, "evidence_submitted")]);
    let ctx = re_anchor(&fx);
    assert!(ctx.contains("too long to show"), "{ctx}");
    assert_re_anchor_stale(&ctx);
    for text in [KS, SKILL, arg.as_str()] {
        assert!(!ctx.contains(text), "printed {text}: {ctx}");
    }
    fs::remove_file(fx.log_path()).unwrap();
    let ctx = re_anchor(&fx);
    assert_eq!(ctx.matches(UNKNOWN).count(), 1, "{ctx}");
    assert!(!ctx.contains(FRESH) && !ctx.contains(STALE), "{ctx}");
}

#[test]
fn re_anchor_makes_no_gh_call_and_every_git_call_is_safe() {
    let fx = Fx::new();
    fx.add_events(&[ev(6, "evidence_submitted")]);
    let _ = fx.run("re-anchor", "repo");
    assert!(
        fs::read_to_string(fx.p("gh.log"))
            .unwrap_or_default()
            .is_empty(),
        "gh was called"
    );
    let log = fs::read_to_string(fx.p("git.log")).expect("re-anchor read the branch");
    for line in log.lines() {
        assert!(
            line.starts_with(
                "-c core.fsmonitor=false -c core.hooksPath=/dev/null -c log.showSignature=false "
            ),
            "{line}"
        );
    }
    let env = fs::read_to_string(fx.p("git.log.env")).unwrap();
    for line in env.lines() {
        assert_eq!(line, "GIT_NO_LAZY_FETCH=1 GIT_ALLOW_PROTOCOL=", "{line}");
    }
}

#[test]
fn a_koto_that_hangs_does_not_hold_the_re_anchor() {
    let fx = Fx::new();
    fs::write(fx.p("stub/slow"), "").unwrap();
    let t = Instant::now();
    assert_re_anchor_unknown(&re_anchor(&fx));
    assert!(t.elapsed().as_secs() < 15, "took {:?}", t.elapsed());
}
