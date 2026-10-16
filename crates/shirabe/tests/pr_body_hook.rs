//! CLI integration tests for `shirabe pr-body-hook`, the legacy pre-action
//! entry point: the decisions that depend on the process environment (the
//! off switches and the offload canary's opt-in file, PRD-pre-action-denies
//! R9 and R10), the output shape, and the exit code. The evaluator's own
//! decisions are unit-tested in `src/pre_action/`.

use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicUsize, Ordering};

use assert_cmd::Command;

/// A PreToolUse input for `command`.
fn hook(command: &str) -> String {
    serde_json::json!({
        "tool_name": "Bash",
        "cwd": "/",
        "tool_input": { "command": command },
    })
    .to_string()
}

const BAD_BODY: &str = "gh pr create --title 'feat: x' --body 'Adds x.'";
const PB4_ONLY: &str =
    "gh pr create --title 'feat: x' --body '## Summary\n\nAdds x.\n\n---\n\nContext.'";
const PB4_EDIT: &str = "gh pr edit 3 --body '## Summary\n\nAdds x.\n\n---\n\nContext.'";

/// A scratch directory per test.
fn scratch() -> PathBuf {
    static N: AtomicUsize = AtomicUsize::new(0);
    let d = std::env::temp_dir().join(format!(
        "shirabe-pr-body-hook-{}-{}",
        std::process::id(),
        N.fetch_add(1, Ordering::SeqCst)
    ));
    let _ = std::fs::remove_dir_all(&d);
    std::fs::create_dir_all(&d).unwrap();
    d
}

/// Run the hook on `command` with a clean environment plus `env`, in an
/// empty `HOME` unless `env` sets one. Returns stdout; asserts exit 0 and
/// an empty or one-line deny output.
fn run(command: &str, env: &[(&str, &str)]) -> String {
    let home = scratch();
    let mut cmd = Command::cargo_bin("shirabe").unwrap();
    cmd.env_clear()
        .env("PATH", std::env::var("PATH").unwrap_or_default())
        .env("HOME", &home);
    for (k, v) in env {
        cmd.env(k, v);
    }
    let out = cmd
        .arg("pr-body-hook")
        .write_stdin(hook(command))
        .output()
        .unwrap();
    assert!(out.status.success(), "always exits 0");
    let stdout = String::from_utf8(out.stdout).unwrap();
    if !stdout.is_empty() {
        assert_eq!(stdout.lines().count(), 1, "{stdout}");
        let v: serde_json::Value = serde_json::from_str(&stdout).unwrap();
        assert_eq!(v["hookSpecificOutput"]["hookEventName"], "PreToolUse");
        assert_eq!(v["hookSpecificOutput"]["permissionDecision"], "deny");
        assert!(stdout.starts_with(
            "{\"hookSpecificOutput\":{\"hookEventName\":\"PreToolUse\",\"permissionDecision\":\"deny\","
        ));
    }
    let _ = std::fs::remove_dir_all(&home);
    stdout
}

fn denied(stdout: &str) -> bool {
    !stdout.is_empty()
}

#[test]
fn a_bad_body_is_denied_in_the_registry_shape() {
    let out = run(BAD_BODY, &[]);
    let v: serde_json::Value = serde_json::from_str(&out).unwrap();
    let reason = v["hookSpecificOutput"]["permissionDecisionReason"]
        .as_str()
        .unwrap();
    assert!(reason.contains("\n\npr-body/one-separator: "), "{reason}");
    assert!(
        reason.contains("\n  full text: references/pr-body-conformance.md lines "),
        "{reason}"
    );
    assert_eq!(run("ls", &[]), "");
}

#[test]
fn the_off_switch_is_exactly_off() {
    assert!(!denied(&run(
        BAD_BODY,
        &[("SHIRABE_PRE_ACTION_HOOK", "off")]
    )));
    assert!(!denied(&run(
        "gh pr create --fill",
        &[("SHIRABE_PRE_ACTION_HOOK", "off")]
    )));
    for v in ["on", "OFF", "off ", "0", ""] {
        assert!(
            denied(&run(BAD_BODY, &[("SHIRABE_PRE_ACTION_HOOK", v)])),
            "{v:?} leaves the hook on"
        );
    }
}

#[test]
fn pr_body_hook_disable_keeps_its_meaning() {
    assert!(!denied(&run(BAD_BODY, &[("PR_BODY_HOOK_DISABLE", "1")])));
    assert!(!denied(&run(
        "gh pr create --fill",
        &[("PR_BODY_HOOK_DISABLE", "yes")]
    )));
    for v in ["", "0", "false"] {
        assert!(
            denied(&run(BAD_BODY, &[("PR_BODY_HOOK_DISABLE", v)])),
            "{v:?} leaves the rules on"
        );
    }
}

/// Write the opt-in file under `base` (`<base>/shirabe/offload-canary`).
fn opt_in(base: &Path, contents: &[u8]) {
    std::fs::create_dir_all(base.join("shirabe")).unwrap();
    std::fs::write(base.join("shirabe/offload-canary"), contents).unwrap();
}

#[test]
fn an_opted_in_host_lets_pb4_through_and_denies_the_rest() {
    let xdg = scratch();
    opt_in(&xdg, b"on\nmore\n");
    let env = [("XDG_CONFIG_HOME", xdg.to_str().unwrap())];
    assert!(!denied(&run(PB4_ONLY, &env)));
    assert!(!denied(&run(PB4_EDIT, &env)));
    assert!(denied(&run(BAD_BODY, &env)), "PB2 is still denied");
    let _ = std::fs::remove_dir_all(&xdg);
}

#[test]
fn without_xdg_config_home_the_file_under_home_is_read() {
    for xdg in [None, Some("")] {
        let home = scratch();
        opt_in(&home.join(".config"), b"on\n");
        let mut env = vec![("HOME", home.to_str().unwrap())];
        if let Some(x) = xdg {
            env.push(("XDG_CONFIG_HOME", x));
        }
        assert!(!denied(&run(PB4_ONLY, &env)), "{xdg:?}");
        let _ = std::fs::remove_dir_all(&home);
    }
}

#[test]
fn anything_but_a_regular_on_file_leaves_pb4_denied() {
    for contents in [&b"On\n"[..], b"on \n", b"on\r\n", b"off\n", b""] {
        let xdg = scratch();
        opt_in(&xdg, contents);
        let env = [("XDG_CONFIG_HOME", xdg.to_str().unwrap())];
        assert!(denied(&run(PB4_ONLY, &env)), "{contents:?}");
        let _ = std::fs::remove_dir_all(&xdg);
    }
    // A symlink to a file that reads `on`.
    let xdg = scratch();
    let real = xdg.join("real");
    std::fs::write(&real, "on\n").unwrap();
    std::fs::create_dir_all(xdg.join("shirabe")).unwrap();
    std::os::unix::fs::symlink(&real, xdg.join("shirabe/offload-canary")).unwrap();
    let env = [("XDG_CONFIG_HOME", xdg.to_str().unwrap())];
    assert!(denied(&run(PB4_ONLY, &env)), "a symlink");
    // An unreadable file (a directory in its place).
    let _ = std::fs::remove_file(xdg.join("shirabe/offload-canary"));
    std::fs::create_dir_all(xdg.join("shirabe/offload-canary")).unwrap();
    assert!(denied(&run(PB4_ONLY, &env)), "a directory");
    let _ = std::fs::remove_dir_all(&xdg);
}
