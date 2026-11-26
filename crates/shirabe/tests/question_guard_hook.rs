//! CLI integration tests for `shirabe hook question-guard`, the plugin's
//! PreToolUse hook on the question tool (PRD-decision-escalation-ladder R27).
//! Each run gets a scratch `HOME` holding the harness directory and a clean
//! environment; the inputs are the fixtures under
//! `hooks/testdata/question-guard/`, with their `PATH-1` record marker
//! pointed at the fixture's record placed under that directory. The end-to-end
//! run through `hooks/hooks.json` is `hooks/question-guard_test.sh`.

use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicUsize, Ordering};

use assert_cmd::Command;

const DENY_PREFIX: &str =
    r#"{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","#;

fn fixtures() -> PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR")).join("../../hooks/testdata/question-guard")
}

/// A scratch host with `home/.claude/projects/p` for session records and an
/// `outside` directory beyond the harness's reach.
struct Host {
    root: PathBuf,
}

impl Host {
    fn new() -> Self {
        static N: AtomicUsize = AtomicUsize::new(0);
        let root = std::env::temp_dir().join(format!(
            "shirabe-question-guard-{}-{}",
            std::process::id(),
            N.fetch_add(1, Ordering::SeqCst)
        ));
        let _ = std::fs::remove_dir_all(&root);
        for d in ["home/.claude/projects/p", "outside", "config"] {
            std::fs::create_dir_all(root.join(d)).unwrap();
        }
        Host { root }
    }

    fn path(&self, rel: &str) -> PathBuf {
        self.root.join(rel)
    }

    /// The fixture's input, its record copied to `record_rel`.
    fn input_at(&self, case: &str, record_rel: &str) -> String {
        let rec = self.path(record_rel);
        std::fs::copy(fixtures().join(format!("{case}.record.jsonl")), &rec).unwrap();
        self.input_pointing(case, &rec)
    }

    fn input(&self, case: &str) -> String {
        self.input_at(case, &format!("home/.claude/projects/p/{case}.jsonl"))
    }

    fn input_pointing(&self, case: &str, rec: &Path) -> String {
        let raw = std::fs::read_to_string(fixtures().join(format!("{case}.json"))).unwrap();
        let out = raw.replace(
            r#""transcript_path":"PATH-1""#,
            &format!(r#""transcript_path":"{}""#, rec.display()),
        );
        assert_ne!(raw, out, "{case}: no PATH-1 marker");
        out
    }

    fn run(&self, input: &str, env: &[(&str, &str)]) -> String {
        let mut cmd = Command::cargo_bin("shirabe").unwrap();
        cmd.env_clear()
            .env("HOME", self.path("home"))
            .args(["hook", "question-guard"])
            .write_stdin(input.to_string());
        for (k, v) in env {
            cmd.env(k, v);
        }
        let out = cmd.assert().success().get_output().stdout.clone();
        String::from_utf8(out).unwrap()
    }
}

impl Drop for Host {
    fn drop(&mut self) {
        let _ = std::fs::remove_dir_all(&self.root);
    }
}

const ATT: (&str, &str) = ("CLAUDE_CODE_SESSION_ATTENDED", "1");
const UNATT: (&str, &str) = ("CLAUDE_CODE_SESSION_ATTENDED", "0");

fn assert_deny(out: &str, what: &str) {
    assert!(
        out.starts_with(DENY_PREFIX) && out.ends_with("\"}}\n") && out.lines().count() == 1,
        "{what}: expected one deny line, got [{out}]"
    );
}

#[test]
fn starts_no_person_typed_are_denied_when_attended() {
    let h = Host::new();
    for case in [
        "background-notification",
        "peer-message",
        "hook-continuation",
        "scheduled-wakeup",
        "subagent",
    ] {
        assert_deny(&h.run(&h.input(case), &[ATT]), case);
    }
}

#[test]
fn typed_starts_are_allowed_when_attended() {
    let h = Host::new();
    for case in [
        "typed-prompt",
        "typed-skill-command",
        "typed-skill-command-agent",
    ] {
        assert_eq!(h.run(&h.input(case), &[ATT]), "", "{case}");
    }
}

#[test]
fn dispatch_brief_follows_the_run_mode() {
    let h = Host::new();
    let input = h.input("dispatch-brief");
    assert_deny(&h.run(&input, &[UNATT]), "dispatch-brief unattended");
    // The record labels a dispatch brief as typed, so attended it is allowed.
    assert_eq!(h.run(&input, &[ATT]), "");
    assert_eq!(h.run(&input, &[]), "");
}

#[test]
fn deny_carries_no_text_from_the_input() {
    let h = Host::new();
    let out = h.run(&h.input("peer-message"), &[ATT]);
    assert_deny(&out, "peer-message");
    assert!(!out.contains("PEER-"), "{out}");
    let reason = out.split("\"permissionDecisionReason\":\"").nth(1).unwrap();
    assert!(reason.starts_with("A question prompt was denied because no person typed"));
}

#[test]
fn record_outside_the_harness_directory_is_not_read() {
    let h = Host::new();
    let input = h.input_at("background-notification", "outside/r.jsonl");
    // Not read, so unknown: the run mode decides.
    assert_eq!(h.run(&input, &[ATT]), "");
    assert_deny(&h.run(&input, &[UNATT]), "outside, unattended");

    // A link inside the harness directory that leaves it is not followed.
    let link = h.path("home/.claude/projects/p/link.jsonl");
    std::os::unix::fs::symlink(h.path("outside/r.jsonl"), &link).unwrap();
    let input = h.input_pointing("background-notification", &link);
    assert_eq!(h.run(&input, &[ATT]), "");
}

#[test]
fn claude_config_dir_names_the_harness_directory() {
    let h = Host::new();
    let input = h.input_at("background-notification", "config/r.jsonl");
    let config = h.path("config");
    let config = config.to_str().unwrap();
    assert_deny(
        &h.run(&input, &[ATT, ("CLAUDE_CONFIG_DIR", config)]),
        "record under CLAUDE_CONFIG_DIR",
    );
    // A relative CLAUDE_CONFIG_DIR is ignored in favour of HOME/.claude.
    assert_eq!(h.run(&input, &[ATT, ("CLAUDE_CONFIG_DIR", "config")]), "");
}

#[test]
fn other_tools_and_malformed_input_get_no_decision() {
    let h = Host::new();
    let input = h.input("background-notification");
    for tool in ["Bash", "Read", "Agent", "MadeUpTool"] {
        let other = input.replace(
            r#""tool_name":"AskUserQuestion""#,
            &format!(r#""tool_name":"{tool}""#),
        );
        assert_eq!(h.run(&other, &[UNATT]), "", "{tool}");
    }
    for bad in ["", "not json", "[]", r#"{"tool_name":7}"#] {
        assert_eq!(h.run(bad, &[UNATT]), "", "[{bad}]");
    }
}

#[test]
fn off_switch_is_exactly_off() {
    let h = Host::new();
    let input = h.input("background-notification");
    assert_eq!(
        h.run(&input, &[ATT, ("SHIRABE_PRE_ACTION_HOOK", "off")]),
        ""
    );
    for v in ["OFF", "0", ""] {
        assert_deny(
            &h.run(&input, &[ATT, ("SHIRABE_PRE_ACTION_HOOK", v)]),
            &format!("SHIRABE_PRE_ACTION_HOOK=[{v}]"),
        );
    }
}
