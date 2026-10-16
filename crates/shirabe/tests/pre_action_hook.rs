//! CLI integration tests for `shirabe pre-action-hook`, the plugin's
//! pre-action entry point: the `--rules` handshake, the off switches (PRD
//! R9), the plugin-root registry, and the yield to a settings-wired `shirabe
//! pr-body-hook` (R12), which depends on `HOME`, `CLAUDE_PROJECT_DIR` and
//! `PATH`. Every run gets a scratch `HOME` and a clean environment, so no
//! real settings file is read. The evaluator's own decisions are unit-tested
//! in `src/pre_action/`.

use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicUsize, Ordering};

use assert_cmd::Command;

/// The rule ids the plugin's script passes, the binary's whole table.
const RULES: &str = "pr-body/conventional-title pr-body/one-separator pr-body/no-ai-trailer \
    pr-body/no-heading-in-part1 pr-body/conformance commit/no-ai-trailer";

/// niwa's wiring line.
const NIWA: &str =
    "command -v shirabe >/dev/null 2>&1 || exit 0; shirabe pr-body-hook 2>/dev/null || exit 0";

const BAD_BODY: &str = "gh pr create --title 'feat: x' --body 'Adds x.'";
const FILL: &str = "gh pr create --fill";
const WRAPPED_PUSH: &str = "sudo git push";

/// The repository, a plugin root with the registry and the files it names.
fn plugin_root() -> PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR")).join("../..")
}

/// A scratch host: `home`, `project`, a `bin` holding an executable
/// `shirabe` stub, and `home/.shirabe/bin` holding another.
struct Host {
    root: PathBuf,
}

impl Host {
    fn new() -> Self {
        static N: AtomicUsize = AtomicUsize::new(0);
        let root = std::env::temp_dir().join(format!(
            "shirabe-pre-action-hook-{}-{}",
            std::process::id(),
            N.fetch_add(1, Ordering::SeqCst)
        ));
        let _ = std::fs::remove_dir_all(&root);
        for d in [
            "home/.claude",
            "project/.claude",
            "bin",
            "home/.shirabe/bin",
        ] {
            std::fs::create_dir_all(root.join(d)).unwrap();
        }
        for bin in ["bin/shirabe", "home/.shirabe/bin/shirabe"] {
            let p = root.join(bin);
            std::fs::write(&p, "#!/bin/sh\nexit 0\n").unwrap();
            use std::os::unix::fs::PermissionsExt;
            std::fs::set_permissions(&p, std::fs::Permissions::from_mode(0o755)).unwrap();
        }
        Host { root }
    }

    fn dir(&self, rel: &str) -> String {
        self.root.join(rel).to_str().unwrap().to_string()
    }

    fn write(&self, rel: &str, contents: &str) {
        std::fs::write(self.root.join(rel), contents).unwrap();
    }

    /// The environment of a host whose `shirabe` is on `PATH`, with the
    /// project directory set.
    fn env(&self) -> Vec<(String, String)> {
        vec![
            ("HOME".into(), self.dir("home")),
            ("CLAUDE_PROJECT_DIR".into(), self.dir("project")),
            ("PATH".into(), format!("/nonexistent:{}", self.dir("bin"))),
        ]
    }
}

impl Drop for Host {
    fn drop(&mut self) {
        let _ = std::fs::remove_dir_all(&self.root);
    }
}

fn settings(matcher: &str, command: &str) -> String {
    serde_json::json!({ "hooks": { "PreToolUse": [{
        "matcher": matcher,
        "hooks": [{ "type": "command", "command": command, "timeout": 30 }]
    }]}})
    .to_string()
}

/// A PreToolUse input for `command`, run in `cwd`.
fn hook(command: &str, cwd: &str) -> String {
    serde_json::json!({
        "tool_name": "Bash",
        "cwd": cwd,
        "tool_input": { "command": command },
    })
    .to_string()
}

struct Out {
    code: i32,
    stdout: String,
}

/// Run `shirabe <args>` on `input` with only `env` in the environment (a
/// scratch `HOME` unless `env` sets one), in `cwd`.
fn run_in(args: &[&str], input: &str, env: &[(String, String)], cwd: &Path) -> Out {
    let home = Host::new();
    let mut cmd = Command::cargo_bin("shirabe").unwrap();
    cmd.env_clear()
        .env("PATH", "/usr/bin:/bin")
        .env("HOME", home.dir("home"))
        .current_dir(cwd);
    for (k, v) in env {
        cmd.env(k, v);
    }
    let out = cmd.args(args).write_stdin(input).output().unwrap();
    let stdout = String::from_utf8(out.stdout).unwrap();
    if !stdout.is_empty() {
        assert_eq!(stdout.lines().count(), 1, "{stdout}");
        assert!(stdout.starts_with(
            "{\"hookSpecificOutput\":{\"hookEventName\":\"PreToolUse\",\"permissionDecision\":\"deny\","
        ));
    }
    Out {
        code: out.status.code().unwrap_or(-1),
        stdout,
    }
}

/// The plugin's entry point on `command`; asserts exit 0 and returns the
/// deny reason, empty for no decision.
fn plugin(command: &str, env: &[(String, String)]) -> String {
    let root = plugin_root();
    let out = run_in(
        &[
            "pre-action-hook",
            "--plugin-root",
            root.to_str().unwrap(),
            "--rules",
            RULES,
        ],
        &hook(command, "/"),
        env,
        Path::new("/"),
    );
    assert_eq!(out.code, 0, "{command}");
    reason(&out.stdout)
}

fn legacy(command: &str, env: &[(String, String)]) -> String {
    let out = run_in(&["pr-body-hook"], &hook(command, "/"), env, Path::new("/"));
    assert_eq!(out.code, 0);
    reason(&out.stdout)
}

fn reason(stdout: &str) -> String {
    if stdout.is_empty() {
        return String::new();
    }
    let v: serde_json::Value = serde_json::from_str(stdout).unwrap();
    v["hookSpecificOutput"]["permissionDecisionReason"]
        .as_str()
        .unwrap()
        .to_string()
}

fn with(env: &[(&str, &str)]) -> Vec<(String, String)> {
    env.iter()
        .map(|(k, v)| (k.to_string(), v.to_string()))
        .collect()
}

#[test]
fn rules_naming_a_rule_the_binary_doesnt_check_exit_3() {
    let root = plugin_root();
    for rules in [
        format!("{RULES} commit/new-rule"),
        "pr-body/one-separator x".to_string(),
    ] {
        let out = run_in(
            &[
                "pre-action-hook",
                "--plugin-root",
                root.to_str().unwrap(),
                "--rules",
                &rules,
            ],
            &hook("ls", "/"),
            &[],
            Path::new("/"),
        );
        assert_eq!(out.code, 3, "{rules}");
        assert_eq!(out.stdout, "");
    }
}

#[test]
fn rules_equal_to_the_table_run_the_evaluator_on_the_plugin_registry() {
    let r = plugin(BAD_BODY, &[]);
    assert!(r.contains("\n\npr-body/one-separator: "), "{r}");
    let canon = std::fs::canonicalize(plugin_root()).unwrap();
    assert!(
        r.contains(&format!(
            "\n  full text: {}/references/pr-body-conformance.md lines ",
            canon.display()
        )),
        "{r}"
    );
    let r = plugin(WRAPPED_PUSH, &[]);
    assert!(r.contains("commit/no-ai-trailer"), "{r}");
    assert_eq!(plugin("ls", &[]), "");
}

#[test]
fn the_off_switch_is_exactly_off() {
    let off = with(&[("SHIRABE_PRE_ACTION_HOOK", "off")]);
    for cmd in [BAD_BODY, FILL, WRAPPED_PUSH, "gh pr create --title 'oops"] {
        assert_eq!(plugin(cmd, &off), "", "{cmd}");
    }
    for v in ["on", "OFF", "off ", "0", ""] {
        let env = with(&[("SHIRABE_PRE_ACTION_HOOK", v)]);
        assert_ne!(plugin(BAD_BODY, &env), "", "{v:?} leaves the hook on");
        assert_ne!(plugin(WRAPPED_PUSH, &env), "", "{v:?}");
    }
}

#[test]
fn pr_body_hook_disable_leaves_the_push_check_on() {
    for v in ["1", "yes"] {
        let env = with(&[("PR_BODY_HOOK_DISABLE", v)]);
        assert_eq!(plugin(BAD_BODY, &env), "", "{v}");
        assert_eq!(plugin(FILL, &env), "", "{v}");
        assert!(plugin(WRAPPED_PUSH, &env).contains("commit/no-ai-trailer"));
    }
    for v in ["", "0", "false"] {
        let env = with(&[("PR_BODY_HOOK_DISABLE", v)]);
        assert_ne!(plugin(BAD_BODY, &env), "", "{v:?} leaves the rules on");
    }
}

#[test]
fn niwas_wiring_in_each_settings_file_yields_the_pull_request() {
    for rel in [
        "home/.claude/settings.json",
        "project/.claude/settings.json",
        "project/.claude/settings.local.json",
    ] {
        let h = Host::new();
        let env = h.env();
        assert_ne!(plugin(BAD_BODY, &env), "", "unwired");
        assert_ne!(plugin(FILL, &env), "", "unwired");
        h.write(rel, &settings("Bash", NIWA));
        assert_eq!(plugin(BAD_BODY, &env), "", "{rel}");
        assert_eq!(plugin(FILL, &env), "", "{rel}");
        let r = plugin(WRAPPED_PUSH, &env);
        assert!(r.contains("commit/no-ai-trailer"), "{rel}: {r}");
    }
}

#[test]
fn the_not_wired_cases_still_deny_the_bad_body() {
    let cases: Vec<(&str, Box<dyn Fn(&Host)>)> = vec![
        (
            "unparsable",
            Box::new(|h| h.write("home/.claude/settings.json", "{ not json")),
        ),
        (
            "echo",
            Box::new(|h| {
                h.write(
                    "home/.claude/settings.json",
                    &settings("Bash", "echo shirabe pr-body-hook"),
                )
            }),
        ),
        (
            "matcher Edit",
            Box::new(|h| h.write("home/.claude/settings.json", &settings("Edit", NIWA))),
        ),
        (
            "disableAllHooks",
            Box::new(|h| {
                let mut v: serde_json::Value =
                    serde_json::from_str(&settings("Bash", NIWA)).unwrap();
                v["disableAllHooks"] = true.into();
                h.write("home/.claude/settings.json", &v.to_string())
            }),
        ),
    ];
    for (name, setup) in cases {
        let h = Host::new();
        setup(&h);
        assert!(
            plugin(BAD_BODY, &h.env()).contains("pr-body/one-separator"),
            "{name}"
        );
    }
}

#[test]
fn wiring_under_cwd_without_a_project_dir_is_not_read() {
    let h = Host::new();
    h.write("project/.claude/settings.json", &settings("Bash", NIWA));
    let env: Vec<(String, String)> = h
        .env()
        .into_iter()
        .filter(|(k, _)| k != "CLAUDE_PROJECT_DIR")
        .collect();
    let root = plugin_root();
    let project = h.root.join("project");
    let out = run_in(
        &[
            "pre-action-hook",
            "--plugin-root",
            root.to_str().unwrap(),
            "--rules",
            RULES,
        ],
        &hook(BAD_BODY, project.to_str().unwrap()),
        &env,
        &project,
    );
    assert_eq!(out.code, 0);
    assert!(reason(&out.stdout).contains("pr-body/one-separator"));
}

#[test]
fn wiring_with_shirabe_only_at_dot_shirabe_bin_is_not_wiring() {
    let h = Host::new();
    h.write("home/.claude/settings.json", &settings("Bash", NIWA));
    let mut env = h.env();
    assert_eq!(plugin(BAD_BODY, &env), "", "on PATH: wired");
    env.retain(|(k, _)| k != "PATH");
    env.push(("PATH".into(), "/nonexistent".into()));
    assert!(plugin(BAD_BODY, &env).contains("pr-body/one-separator"));
}

#[test]
fn the_two_entry_points_report_each_broken_rule_once() {
    let h = Host::new();
    h.write("home/.claude/settings.json", &settings("", NIWA));
    let env = h.env();
    let cmd = "gh pr create --title 'Add x' --body 'Adds x.' && sudo git push";
    let l = legacy(cmd, &env);
    let p = plugin(cmd, &env);
    let both = format!("{l}\n{p}");
    for id in ["pr-body/conventional-title:", "pr-body/one-separator:"] {
        assert_eq!(both.matches(id).count(), 1, "{both}");
    }
    assert!(
        l.contains("pr-body/one-separator:"),
        "the legacy reports it"
    );
    assert!(
        p.contains("commit/no-ai-trailer"),
        "the plugin keeps the push"
    );
    assert!(!p.contains("pr-body/"), "{p}");
}
