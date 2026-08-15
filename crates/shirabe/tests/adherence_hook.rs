//! CLI integration tests for `shirabe adherence-hook` and for the plugin
//! registration that runs it.
//!
//! The in-module tests cover the witness logic. These cover the two properties
//! that only exist at process and configuration level: the subcommand always
//! exits 0 and emits no decision, and the shell guard in `hooks/hooks.json`
//! keeps a session running when the binary is absent or outdated. A
//! `PreToolUse` handler that exits non-zero blocks the tool call, so both are
//! the difference between a hook and a bricked session.

use std::fs;
use std::path::PathBuf;
use std::process::Command as StdCommand;
use std::sync::atomic::{AtomicUsize, Ordering};

use assert_cmd::Command;

struct Fx {
    dir: PathBuf,
}

impl Fx {
    fn new() -> Fx {
        static N: AtomicUsize = AtomicUsize::new(0);
        let n = N.fetch_add(1, Ordering::SeqCst);
        let dir = std::env::temp_dir().join(format!(
            "shirabe-adherence-cli-{}-{}",
            std::process::id(),
            n
        ));
        let _ = fs::remove_dir_all(&dir);
        fs::create_dir_all(dir.join("store")).unwrap();
        fs::create_dir_all(dir.join("repo/docs/plans")).unwrap();
        Fx { dir }
    }

    fn store(&self) -> PathBuf {
        self.dir.join("store")
    }

    fn repo(&self) -> PathBuf {
        self.dir.join("repo")
    }

    fn hook_json(&self, session: &str) -> String {
        serde_json::json!({
            "session_id": session,
            "hook_event_name": "PreToolUse",
            "tool_name": "Write",
            "tool_input": { "file_path": "/tmp/x.txt", "content": "hi" },
            "cwd": self.repo().to_string_lossy(),
            "permission_mode": "bypassPermissions",
        })
        .to_string()
    }
}

impl Drop for Fx {
    fn drop(&mut self) {
        let _ = fs::remove_dir_all(&self.dir);
    }
}

/// The plugin root: the repository root, two levels above this crate.
fn plugin_root() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("../..")
        .canonicalize()
        .unwrap()
}

fn hooks_config() -> serde_json::Value {
    let raw = fs::read_to_string(plugin_root().join("hooks/hooks.json")).unwrap();
    serde_json::from_str(&raw).unwrap()
}

/// The single `PreToolUse` handler entry declared by the plugin.
fn pre_tool_use_handler() -> serde_json::Value {
    let cfg = hooks_config();
    let matchers = cfg["hooks"]["PreToolUse"].as_array().unwrap();
    assert_eq!(matchers.len(), 1, "one PreToolUse matcher group");
    let hooks = matchers[0]["hooks"].as_array().unwrap();
    assert_eq!(hooks.len(), 1, "one handler in the group");
    hooks[0].clone()
}

#[test]
fn the_plugin_registers_a_command_handler_on_the_edit_tools() {
    let cfg = hooks_config();
    let group = &cfg["hooks"]["PreToolUse"][0];
    let matcher = group["matcher"].as_str().unwrap();
    for tool in ["Edit", "Write", "MultiEdit", "NotebookEdit"] {
        assert!(
            matcher.split('|').any(|m| m == tool),
            "matcher {matcher:?} must cover {tool}"
        );
    }
    // A prompt- or agent-type handler's deny ends the turn; a command
    // handler's deny returns as the tool error and the turn continues, which
    // is what the correction requirement needs. The type is load-bearing.
    assert_eq!(pre_tool_use_handler()["type"], "command");
    let cmd = pre_tool_use_handler()["command"]
        .as_str()
        .unwrap()
        .to_string();
    assert!(
        cmd.contains("command -v shirabe"),
        "the command must guard on the binary's presence: {cmd}"
    );
    assert!(
        !cmd.contains("exec "),
        "the command must not exec, so a non-zero exit can be swallowed: {cmd}"
    );
    assert!(
        cmd.contains("${CLAUDE_PLUGIN_ROOT}"),
        "the plugin root must be passed through: {cmd}"
    );
}

/// An absolute path to bash. The tests below override `PATH`, so the
/// interpreter cannot be resolved through it.
fn bash() -> PathBuf {
    ["/bin/bash", "/usr/bin/bash"]
        .iter()
        .map(PathBuf::from)
        .find(|p| p.exists())
        .expect("bash not found")
}

/// Run the registered hook command under bash with a controlled `PATH`,
/// returning its exit status.
fn run_registered_command(path: &str, plugin_root_value: &str) -> std::process::Output {
    let cmd = pre_tool_use_handler()["command"]
        .as_str()
        .unwrap()
        .to_string();
    StdCommand::new(bash())
        .arg("-c")
        .arg(&cmd)
        .env("PATH", path)
        .env("CLAUDE_PLUGIN_ROOT", plugin_root_value)
        .output()
        .unwrap()
}

#[test]
fn an_absent_binary_leaves_the_session_unblocked() {
    // No `shirabe` anywhere on PATH: the guard short-circuits and the tool
    // call proceeds.
    let out = run_registered_command("", &plugin_root().to_string_lossy());
    assert!(
        out.status.success(),
        "absent binary must exit 0, got {:?}",
        out.status
    );
    assert!(out.stdout.is_empty(), "no decision may be emitted");
}

#[test]
fn an_outdated_binary_leaves_the_session_unblocked() {
    // The shipped precedent: a binary that does not recognize the subcommand
    // and exits non-zero. The `|| exit 0` tail must swallow it.
    let fx = Fx::new();
    let bin_dir = fx.dir.join("bin");
    fs::create_dir_all(&bin_dir).unwrap();
    let stub = bin_dir.join("shirabe");
    fs::write(
        &stub,
        "#!/usr/bin/env bash\necho 'unrecognized subcommand' >&2\nexit 2\n",
    )
    .unwrap();
    use std::os::unix::fs::PermissionsExt;
    fs::set_permissions(&stub, fs::Permissions::from_mode(0o755)).unwrap();

    let out = run_registered_command(&bin_dir.to_string_lossy(), &plugin_root().to_string_lossy());
    assert!(
        out.status.success(),
        "a non-zero exit must be swallowed, got {:?}",
        out.status
    );
}

#[test]
fn the_subcommand_always_exits_zero_and_emits_no_decision() {
    let fx = Fx::new();
    for input in [
        fx.hook_json("cli-sess"),
        "not json at all".to_string(),
        String::new(),
        "{}".to_string(),
    ] {
        let assert = Command::cargo_bin("shirabe")
            .unwrap()
            .arg("adherence-hook")
            .arg("--contract")
            .arg(plugin_root())
            .env("SHIRABE_ADHERENCE_STORE_DIR", fx.store())
            .write_stdin(input.clone())
            .assert()
            .success();
        let out = assert.get_output();
        assert!(
            out.stdout.is_empty(),
            "input {input:?} produced stdout {:?}",
            String::from_utf8_lossy(&out.stdout)
        );
    }
}

#[test]
fn the_witness_lands_in_the_store_for_a_repo_that_hosts_plans() {
    let fx = Fx::new();
    Command::cargo_bin("shirabe")
        .unwrap()
        .arg("adherence-hook")
        .env("SHIRABE_ADHERENCE_STORE_DIR", fx.store())
        .write_stdin(fx.hook_json("cli-witness"))
        .assert()
        .success();
    let raw = fs::read_to_string(fx.store().join("cli-witness.json")).unwrap();
    let w: serde_json::Value = serde_json::from_str(&raw).unwrap();
    assert_eq!(w["session_id"], "cli-witness");
    assert_eq!(w["cwd"], fx.repo().to_string_lossy().to_string());
    assert_eq!(w["disabled"], false);
    assert!(w["contract_version"].as_u64().unwrap() >= 1);
    assert!(w["first_seen_unix"].as_u64().unwrap() > 0);
}

#[test]
fn a_repo_without_a_plans_directory_leaves_no_witness() {
    let fx = Fx::new();
    fs::remove_dir_all(fx.repo().join("docs/plans")).unwrap();
    Command::cargo_bin("shirabe")
        .unwrap()
        .arg("adherence-hook")
        .env("SHIRABE_ADHERENCE_STORE_DIR", fx.store())
        .write_stdin(fx.hook_json("cli-noplans"))
        .assert()
        .success();
    assert_eq!(fs::read_dir(fx.store()).unwrap().count(), 0);
}

#[test]
fn the_kill_switch_still_leaves_a_witness_marked_disabled() {
    // Suppressing the witness too would make a deliberately disabled run
    // indistinguishable from a run that predates the feature, and the first
    // of those is the one worth knowing about.
    let fx = Fx::new();
    Command::cargo_bin("shirabe")
        .unwrap()
        .arg("adherence-hook")
        .env("SHIRABE_ADHERENCE_STORE_DIR", fx.store())
        .env("SHIRABE_ADHERENCE_DISABLE", "1")
        .write_stdin(fx.hook_json("cli-disabled"))
        .assert()
        .success();
    let raw = fs::read_to_string(fx.store().join("cli-disabled.json")).unwrap();
    let w: serde_json::Value = serde_json::from_str(&raw).unwrap();
    assert_eq!(w["disabled"], true);
}
