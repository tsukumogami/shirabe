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

// --- the push check through the binary --------------------------------------

const TRAILER: &str = "feat: add x\n\nCo-Authored-By: Claude <noreply@anthropic.com>\n";

/// A scratch `origin.git` and `work`, whose `main` holds one pushed commit
/// and one unpushed trailer commit.
fn trailer_repo(h: &Host) -> String {
    let git = |dir: &str, args: &[&str]| {
        let out = std::process::Command::new("git")
            .current_dir(h.dir(dir))
            .env_clear()
            .env("PATH", std::env::var_os("PATH").unwrap_or_default())
            .env("HOME", h.dir("home"))
            .env("GIT_CONFIG_NOSYSTEM", "1")
            .args(["-c", "user.name=t", "-c", "user.email=t@example.com"])
            .args(["-c", "commit.gpgSign=false"])
            .args(args)
            .output()
            .unwrap();
        assert!(out.status.success(), "git {args:?}");
    };
    git("", &["init", "-q", "--bare", "-b", "main", "origin.git"]);
    git("", &["init", "-q", "-b", "main", "work"]);
    git("work", &["remote", "add", "origin", &h.dir("origin.git")]);
    git(
        "work",
        &["commit", "-q", "--allow-empty", "-m", "chore: base"],
    );
    git("work", &["push", "-q", "origin", "main"]);
    git("work", &["commit", "-q", "--allow-empty", "-m", TRAILER]);
    h.dir("work")
}

/// The plugin's entry point on `command` run in `cwd`.
fn plugin_in(command: &str, cwd: &str, env: &[(String, String)]) -> String {
    let root = plugin_root();
    let out = run_in(
        &[
            "pre-action-hook",
            "--plugin-root",
            root.to_str().unwrap(),
            "--rules",
            RULES,
        ],
        &hook(command, cwd),
        env,
        Path::new("/"),
    );
    assert_eq!(out.code, 0, "{command}");
    reason(&out.stdout)
}

/// The first executable `git` on this process's `PATH`.
fn real_git() -> PathBuf {
    use std::os::unix::fs::PermissionsExt;
    std::env::split_paths(&std::env::var_os("PATH").unwrap_or_default())
        .map(|d| d.join("git"))
        .find(|p| {
            std::fs::metadata(p).is_ok_and(|m| m.is_file() && m.permissions().mode() & 0o111 != 0)
        })
        .expect("git on PATH")
}

/// A stub `git` in `h`'s `stub` directory running `body`; the directory.
fn stub_git(h: &Host, body: &str) -> String {
    use std::os::unix::fs::PermissionsExt;
    std::fs::create_dir_all(h.root.join("stub")).unwrap();
    let p = h.root.join("stub/git");
    std::fs::write(&p, format!("#!/bin/sh\n{body}\n")).unwrap();
    std::fs::set_permissions(&p, std::fs::Permissions::from_mode(0o755)).unwrap();
    h.dir("stub")
}

#[test]
fn a_trailer_push_is_denied_and_only_the_off_switch_turns_it_off() {
    let h = Host::new();
    let work = trailer_repo(&h);
    let r = plugin_in("git push", &work, &[]);
    assert!(
        r.starts_with("shirabe denied this `git push` before it ran.\n\ncommit/no-ai-trailer: "),
        "{r}"
    );
    assert!(r.contains(" subject: feat: add x\n"), "{r}");
    let off = with(&[("SHIRABE_PRE_ACTION_HOOK", "off")]);
    assert_eq!(plugin_in("git push", &work, &off), "");
    // PR_BODY_HOOK_DISABLE leaves the push on.
    let r = plugin_in("git push", &work, &with(&[("PR_BODY_HOOK_DISABLE", "1")]));
    assert!(r.contains("commit/no-ai-trailer: "), "{r}");
    // So does the legacy wiring, and the legacy entry point checks no push:
    // each rule is reported once between the two.
    h.write("home/.claude/settings.json", &settings("Bash", NIWA));
    let mut env = h.env();
    env.retain(|(k, _)| k != "PATH");
    env.push(("PATH".into(), format!("{}:/usr/bin:/bin", h.dir("bin"))));
    let cmd = "gh pr create --title 'Add x' --body 'Adds x.' && git push";
    let p = plugin_in(cmd, &work, &env);
    assert!(p.contains("commit/no-ai-trailer: "), "{p}");
    assert!(!p.contains("pr-body/"), "{p}");
    let out = run_in(&["pr-body-hook"], &hook(cmd, &work), &env, Path::new("/"));
    let l = reason(&out.stdout);
    assert!(l.contains("pr-body/one-separator: "), "{l}");
    assert!(!l.contains("commit/no-ai-trailer"), "{l}");
}

#[test]
fn a_git_past_the_shortened_budget_is_denied_naming_git_in_time() {
    let h = Host::new();
    let work = trailer_repo(&h);
    let stub = stub_git(&h, "exec sleep 5");
    let env = with(&[
        ("SHIRABE_PRE_ACTION_GIT_TIMEOUT", "1"),
        ("PATH", &format!("{stub}:/usr/bin:/bin")),
    ]);
    let start = std::time::Instant::now();
    let r = plugin_in("git push", &work, &env);
    assert!(
        start.elapsed() < std::time::Duration::from_secs(3),
        "{:?}",
        start.elapsed()
    );
    assert!(
        r.contains("(git: `git rev-parse` ran past the push check's 1-second budget)"),
        "{r}"
    );
    assert!(r.contains("ask the user"), "{r}");
}

#[test]
fn every_git_child_runs_plumbing_only_from_the_fixed_environment() {
    let h = Host::new();
    let work = trailer_repo(&h);
    let calls = h.root.join("calls");
    let envs = h.root.join("envs");
    let stub = stub_git(
        &h,
        &format!(
            "for a in \"$@\"; do printf '%s\\n' \"$a\" >> '{c}'; done\n\
             printf '%s\\n' '--end--' >> '{c}'\n\
             env >> '{e}'\n\
             printf '%s\\n' '--end--' >> '{e}'\n\
             exec '{g}' \"$@\"",
            c = calls.display(),
            e = envs.display(),
            g = real_git().display()
        ),
    );
    let env = with(&[
        ("PATH", &format!("relative/bin:{stub}:/usr/bin:/bin")),
        ("HOME", &h.dir("home")),
        ("LANG", "C"),
        ("LC_ALL", "C"),
        ("GIT_DIR", "/nonexistent"),
        ("GIT_CONFIG_PARAMETERS", "'core.fsmonitor'='/x'"),
        ("LEAK", "1"),
    ]);
    let r = plugin_in("git push", &work, &env);
    assert!(r.contains("commit/no-ai-trailer: "), "{r}");

    let calls = std::fs::read_to_string(&calls).unwrap();
    let mut subs = Vec::new();
    for call in calls.split("--end--\n").filter(|c| !c.is_empty()) {
        let args: Vec<&str> = call.lines().collect();
        assert_eq!(
            &args[..11],
            &[
                "-C",
                work.as_str(),
                "--no-pager",
                "-c",
                "core.fsmonitor=false",
                "-c",
                "core.hooksPath=/dev/null",
                "-c",
                "log.showSignature=false",
                "-c",
                "core.pager=cat"
            ],
            "{call}"
        );
        subs.push(args[11].to_string());
    }
    // Local plumbing only: no `fetch`, `ls-remote` or `remote`.
    for sub in &subs {
        assert!(
            [
                "rev-parse",
                "config",
                "symbolic-ref",
                "for-each-ref",
                "rev-list",
                "cat-file"
            ]
            .contains(&sub.as_str()),
            "{subs:?}"
        );
    }
    assert!(subs.iter().any(|s| s == "cat-file"), "{subs:?}");

    let envs = std::fs::read_to_string(&envs).unwrap();
    for e in envs.split("--end--\n").filter(|c| !c.is_empty()) {
        let mut vars: Vec<&str> = e
            .lines()
            .filter(|l| l.contains('='))
            // Set by the stub's own shell.
            .filter(|l| {
                !["PWD=", "OLDPWD=", "SHLVL=", "_="]
                    .iter()
                    .any(|p| l.starts_with(p))
            })
            .collect();
        vars.sort();
        let home = format!("HOME={}", h.dir("home"));
        let path = format!("PATH={stub}:/usr/bin:/bin");
        let mut want = vec![
            "GIT_CONFIG_NOSYSTEM=1",
            "GIT_NO_LAZY_FETCH=1",
            "GIT_NO_REPLACE_OBJECTS=1",
            "GIT_OPTIONAL_LOCKS=0",
            "GIT_PAGER=cat",
            "GIT_TERMINAL_PROMPT=0",
            home.as_str(),
            "LANG=C",
            "LC_ALL=C",
            path.as_str(),
        ];
        want.sort();
        assert_eq!(vars, want, "{e}");
    }
}

#[test]
fn a_push_check_in_an_empty_home_and_tmpdir_writes_nothing() {
    let h = Host::new();
    let work = trailer_repo(&h);
    for d in ["empty-home", "empty-tmp"] {
        std::fs::create_dir_all(h.root.join(d)).unwrap();
    }
    let env = with(&[
        ("HOME", &h.dir("empty-home")),
        ("TMPDIR", &h.dir("empty-tmp")),
    ]);
    let r = plugin_in("git push", &work, &env);
    assert!(r.contains("commit/no-ai-trailer: "), "{r}");
    for d in ["empty-home", "empty-tmp"] {
        let n = std::fs::read_dir(h.root.join(d)).unwrap().count();
        assert_eq!(n, 0, "{d}");
    }
}
