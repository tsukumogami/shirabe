//! The evaluator's tests. The first group is `pr_body_hook.rs`'s unit tests
//! from before the evaluator existed, run on the legacy entry point's
//! settings, with their decisions kept except the five fail-open cases PRD
//! R11 names, which now deny.

use std::path::{Path, PathBuf};
use std::time::Instant;

use super::push::{GitError, GitOut};
use super::*;

/// The git runner of an evaluation that must never reach git.
struct NoGit;

impl GitRunner for NoGit {
    fn run(
        &self,
        _: &Path,
        args: &[&str],
        _: Option<Vec<u8>>,
        _: usize,
        _: Instant,
    ) -> Result<GitOut, GitError> {
        panic!("this evaluation runs no git, yet ran {args:?}")
    }
}

/// A git runner for directories that aren't repositories: every call exits
/// 128, as git does outside a work tree. The push check's own tests run
/// real repositories (`push_tests.rs`).
struct NotARepo;

impl GitRunner for NotARepo {
    fn run(
        &self,
        _: &Path,
        _: &[&str],
        _: Option<Vec<u8>>,
        _: usize,
        _: Instant,
    ) -> Result<GitOut, GitError> {
        Ok(GitOut {
            code: Some(128),
            stdout: Vec::new(),
        })
    }
}

/// A PreToolUse hook JSON with `command` as the Bash tool input.
fn hook(command: &str) -> String {
    serde_json::json!({
        "session_id": "s1",
        "tool_name": "Bash",
        "tool_input": { "command": command },
    })
    .to_string()
}

fn hook_in(command: &str, cwd: &Path) -> String {
    serde_json::json!({
        "tool_name": "Bash",
        "cwd": cwd.to_string_lossy(),
        "tool_input": { "command": command },
    })
    .to_string()
}

/// The legacy entry point's evaluation, not opted into the canary.
fn evaluate(input: &str) -> Option<String> {
    evaluate_with(input, || false)
}

fn evaluate_with(input: &str, canary: impl Fn() -> bool) -> Option<String> {
    super::evaluate(
        input,
        &Ctx {
            rules: RuleSet::PrBodyOnly,
            registry: RegistrySource::Embedded,
            canary_opted_in: &canary,
            legacy_wired: &|| panic!("the legacy set never asks"),
            git: &NoGit,
            git_budget: push::GIT_BUDGET,
        },
    )
}

fn evaluate_all(input: &str, registry: RegistrySource) -> Option<String> {
    evaluate_plugin(input, registry, || false)
}

/// The plugin's evaluation, with `wired` as the settings probe.
fn evaluate_plugin(
    input: &str,
    registry: RegistrySource,
    wired: impl Fn() -> bool,
) -> Option<String> {
    super::evaluate(
        input,
        &Ctx {
            rules: RuleSet::All,
            registry,
            canary_opted_in: &|| false,
            legacy_wired: &wired,
            git: &NotARepo,
            git_budget: push::GIT_BUDGET,
        },
    )
}

fn assert_fail_closed(reason: &str, word: &str) {
    assert!(reason.contains(word), "want {word:?} in: {reason}");
    assert!(reason.contains("ask the user"), "{reason}");
    assert!(!reason.contains("SHIRABE_PRE_ACTION_HOOK"), "{reason}");
}

// --- pr_body_hook.rs's tests at the base branch ---------------------------

#[test]
fn clean_create_is_allowed() {
    let cmd = "gh pr create --title 'feat: add mode' --body 'Adds the mode.

---

Fixes #1'";
    assert_eq!(evaluate(&hook(cmd)), None);
}

#[test]
fn banned_writing_style_words_are_allowed() {
    // PB5 runs only under `shirabe validate --pr-body --writing-style`;
    // the hook keeps deciding on PB1 to PB4 alone.
    let cmd = "gh pr create --title 'feat: a seamless mode' --body 'Leverage the mode.

---

A robust note. Fixes #1'";
    assert_eq!(evaluate(&hook(cmd)), None);
    assert_eq!(evaluate_all(&hook(cmd), RegistrySource::Embedded), None);
}

#[test]
fn non_conventional_title_is_denied() {
    let cmd = "gh pr create --title 'Add the mode' --body 'Body.

---

Fixes #1'";
    let reason = evaluate(&hook(cmd)).expect("should deny");
    assert!(reason.contains("not Conventional Commits"), "got: {reason}");
}

#[test]
fn missing_separator_is_denied() {
    let cmd = "gh pr create --title 'fix: thing' --body 'One part only, no separator.'";
    let reason = evaluate(&hook(cmd)).expect("should deny");
    assert!(reason.contains("no `---` separator"), "got: {reason}");
}

#[test]
fn attribution_footer_is_denied() {
    let cmd = "gh pr create -t 'fix: thing' -b 'Real change.

---

Context.

Co-Authored-By: Claude <noreply@anthropic.com>'";
    let reason = evaluate(&hook(cmd)).expect("should deny");
    assert!(reason.contains("AI-attribution"), "got: {reason}");
}

#[test]
fn flag_equals_value_form_is_parsed() {
    let cmd = "gh pr create --title=Add --body='b\n\n---\n\nx'";
    let reason = evaluate(&hook(cmd)).expect("should deny");
    assert!(reason.contains("not Conventional Commits"), "got: {reason}");
}

#[test]
fn edit_title_only_runs_pb1_only() {
    let bad = "gh pr edit 12 --title 'Not conventional'";
    let reason = evaluate(&hook(bad)).expect("should deny");
    assert!(reason.contains("not Conventional Commits"));
    assert!(!reason.contains("pr-body/one-separator"), "{reason}");
    let good = "gh pr edit 12 --title 'feat: good title'";
    assert_eq!(evaluate(&hook(good)), None, "clean title-only edit allowed");
}

#[test]
fn edit_body_only_runs_body_checks() {
    let cmd = "gh pr edit 12 --body 'No separator body.'";
    let reason = evaluate(&hook(cmd)).expect("should deny");
    assert!(reason.contains("no `---` separator"), "got: {reason}");
    assert!(!reason.contains("pr-body/conventional-title"), "{reason}");
}

#[test]
fn edit_without_title_or_body_is_allowed() {
    let cmd = "gh pr edit 12 --add-label needs-review";
    assert_eq!(evaluate(&hook(cmd)), None);
}

#[test]
fn non_gh_command_is_allowed() {
    assert_eq!(evaluate(&hook("echo gh pr create --title bad")), None);
    assert_eq!(evaluate(&hook("git commit -m 'not a pr'")), None);
}

/// Was `fill_and_web_are_allowed`.
#[test]
fn fill_and_web_are_denied() {
    let r = evaluate(&hook("gh pr create --fill")).expect("denies");
    assert_fail_closed(&r, "--fill");
    let r = evaluate(&hook("gh pr create --title 'feat: x' --web")).expect("denies");
    assert_fail_closed(&r, "--web");
}

/// Was `command_substitution_body_is_allowed`.
#[test]
fn command_substitution_body_is_denied() {
    let cmd = "gh pr create --title 'feat: x' --body \"$(cat body.txt)\"";
    let r = evaluate(&hook(cmd)).expect("denies");
    assert_fail_closed(&r, "expansion");
    assert!(
        r.contains("--body-file <path>"),
        "names the forms it reads: {r}"
    );
}

#[test]
fn body_file_is_read_and_checked() {
    let dir = std::env::temp_dir();
    let path = dir.join(format!("shirabe-hook-test-{}.md", std::process::id()));
    std::fs::write(&path, "One-part body, no separator.\n").unwrap();
    let cmd = format!(
        "gh pr create --title 'fix: thing' --body-file {}",
        path.display()
    );
    let reason = evaluate(&hook(&cmd)).expect("should deny");
    assert!(reason.contains("no `---` separator"), "got: {reason}");
    assert!(
        !reason.contains("One-part body"),
        "never quotes the file: {reason}"
    );
    let _ = std::fs::remove_file(&path);
}

#[test]
fn body_file_clean_is_allowed() {
    let dir = std::env::temp_dir();
    let path = dir.join(format!("shirabe-hook-ok-{}.md", std::process::id()));
    std::fs::write(&path, "Real change.\n\n---\n\nFixes #2\n").unwrap();
    let cmd = format!(
        "gh pr create --title 'fix: real' --body-file {}",
        path.display()
    );
    assert_eq!(evaluate(&hook(&cmd)), None);
    let _ = std::fs::remove_file(&path);
}

/// Was `unreadable_body_file_is_allowed`.
#[test]
fn unreadable_body_file_is_denied() {
    let cmd = "gh pr create --title 'fix: thing' --body-file /nonexistent/nope.md";
    let r = evaluate(&hook(cmd)).expect("denies");
    assert_fail_closed(&r, "/nonexistent/nope.md");
}

/// Was `body_file_dash_stdin_is_allowed`.
#[test]
fn body_file_dash_stdin_is_denied() {
    let cmd = "gh pr create --title 'fix: thing' --body-file -";
    let r = evaluate(&hook(cmd)).expect("denies");
    assert_fail_closed(&r, "stdin");
}

#[test]
fn malformed_stdin_is_allowed() {
    assert_eq!(evaluate("not json at all"), None);
    assert_eq!(evaluate("{}"), None);
    assert_eq!(evaluate(""), None);
}

#[test]
fn env_assignment_prefix_is_stripped() {
    let cmd = "GH_TOKEN=abc gh pr create --title 'bad title' --body 'b\n\n---\n\nx'";
    let reason = evaluate(&hook(cmd)).expect("should deny");
    assert!(reason.contains("not Conventional Commits"), "got: {reason}");
}

#[test]
fn compound_command_finds_the_gh_segment() {
    let cmd = "cd /tmp && gh pr create --title 'bad' --body 'b\n\n---\n\nx'";
    let reason = evaluate(&hook(cmd)).expect("should deny");
    assert!(reason.contains("not Conventional Commits"), "got: {reason}");
}

/// Was `unterminated_quote_segment_is_allowed`, which asserted only that it
/// didn't panic.
#[test]
fn unterminated_quote_segment_is_denied() {
    let cmd = "gh pr create --title 'unterminated --body 'b\n\n---\n\nx'";
    let r = evaluate(&hook(cmd)).expect("denies");
    assert_fail_closed(&r, "quote");
}

#[test]
fn deny_reason_is_json_safe() {
    let cmd = "gh pr create --title 'evil\" }] title\n\u{1b}[31m\\' --body 'Real.\n\n---\n\nx'";
    let reason = evaluate(&hook(cmd)).expect("denies the title");
    let value = serde_json::json!({
        "hookSpecificOutput": { "permissionDecisionReason": reason }
    });
    let s = serde_json::to_string(&value).unwrap();
    assert!(!s.contains('\u{1b}'), "the escape is JSON-escaped: {s}");
    let back: serde_json::Value = serde_json::from_str(&s).unwrap();
    assert_eq!(
        back["hookSpecificOutput"]["permissionDecisionReason"],
        reason
    );
}

// --- the offload canary's opt-in --------------------------------------

const HEADED: &str = "gh pr create --title 'feat: add mode' --body '## Summary

Adds the mode.

---

Fixes #1'";

#[test]
fn heading_in_part1_is_denied_without_the_opt_in() {
    let reason = evaluate_with(&hook(HEADED), || false).expect("should deny");
    assert!(reason.contains("markdown section heading"), "got: {reason}");
    assert!(
        reason.contains("pr-body/no-heading-in-part1"),
        "got: {reason}"
    );
}

#[test]
fn heading_in_part1_is_allowed_on_an_opted_in_host() {
    assert_eq!(evaluate_with(&hook(HEADED), || true), None);
    let edit = "gh pr edit 3 --body '## Summary\n\nAdds.\n\n---\n\nx'";
    assert_eq!(evaluate_with(&hook(edit), || true), None);
    assert!(evaluate_with(&hook(edit), || false).is_some());
}

#[test]
fn the_opt_in_keeps_pb1_to_pb3() {
    let cmd = "gh pr create --title 'Add the mode' --body '## Summary

Adds the mode.'";
    let reason = evaluate_with(&hook(cmd), || true).expect("should still deny");
    assert!(reason.contains("not Conventional Commits"), "got: {reason}");
    assert!(reason.contains("no `---` separator"), "got: {reason}");
    assert!(
        !reason.contains("markdown section heading"),
        "got: {reason}"
    );
}

#[test]
fn the_canary_is_asked_only_about_a_pb4_finding() {
    let asked = std::cell::Cell::new(false);
    let cmd = "gh pr create --title 'Add' --body 'x\n\n---\n\ny'";
    assert!(evaluate_with(&hook(cmd), || {
        asked.set(true);
        true
    })
    .is_some());
    assert!(!asked.get());
}

#[test]
fn opted_in_at_reads_only_a_regular_file_whose_first_line_is_on() {
    let dir = std::env::temp_dir().join(format!("pr-body-hook-optin-{}", std::process::id()));
    std::fs::create_dir_all(&dir).unwrap();
    let f = dir.join("offload-canary");
    assert!(!opted_in_at(&f), "a missing file is not an opt-in");
    std::fs::write(&f, "on\n").unwrap();
    assert!(opted_in_at(&f), "a file reading on is an opt-in");
    std::fs::write(&f, "on\nmore\n").unwrap();
    assert!(opted_in_at(&f), "later lines don't matter");
    for no in ["off\n", "", "On\n", "on \n", "on\r\n"] {
        std::fs::write(&f, no).unwrap();
        assert!(!opted_in_at(&f), "{no:?} is not an opt-in");
    }
    std::fs::write(&f, b"on\n\xff\xfe").unwrap();
    assert!(
        opted_in_at(&f),
        "invalid UTF-8 after the first line doesn't matter"
    );
    std::fs::write(&f, "on\n").unwrap();
    let link = dir.join("link");
    let _ = std::fs::remove_file(&link);
    std::os::unix::fs::symlink(&f, &link).unwrap();
    assert!(!opted_in_at(&link), "a symlink is not an opt-in");
    let _ = std::fs::remove_dir_all(&dir);
}

// --- the deny's shape (PRD R5, R11) -------------------------------------

const BAD: &str = "Adds x.";
const GOOD: &str = "Adds x.\n\n---\n\nContext.";

fn create(title: &str, body: &str) -> String {
    format!("gh pr create --title '{title}' --body '{body}'")
}

#[test]
fn one_broken_rule_is_one_block_with_the_relative_path() {
    let r = evaluate(&hook(&create("feat: x", BAD))).expect("denies");
    let reg = Registry::embedded().unwrap();
    let e = reg.entry("pr-body/one-separator").unwrap();
    let range = reg.range(e).unwrap();
    let want = format!(
        "shirabe denied this `gh pr create` before it ran.\n\n\
         pr-body/one-separator: {}: ",
        e.summary
    );
    assert!(r.starts_with(&want), "{r}");
    let tail = format!(
        "\n  full text: references/pr-body-conformance.md lines {}-{}",
        range.first, range.last
    );
    assert!(r.ends_with(&tail), "{r}");
    assert_eq!(r.matches("full text:").count(), 1);
}

#[test]
fn two_broken_rules_are_two_blocks_in_registry_order() {
    let r = evaluate(&hook(&format!("git add . && {}", create("Add x", BAD)))).expect("denies");
    let title = r.find("pr-body/conventional-title:").expect("PB1 block");
    let sep = r.find("pr-body/one-separator:").expect("PB2 block");
    assert!(title < sep, "{r}");
    assert_eq!(r.matches("full text:").count(), 2);
}

#[test]
fn several_findings_under_one_rule_join_with_semicolons() {
    // Two PB3 lines: two findings, one block.
    let body =
        "Change.\n\n---\n\nCo-Authored-By: Claude <a@anthropic.com>\nGenerated with Claude Code";
    let r = evaluate(&hook(&create("feat: x", body))).expect("denies");
    assert_eq!(r.matches("pr-body/no-ai-trailer:").count(), 1, "{r}");
    assert!(r.contains("line 5: the PR body carries"), "{r}");
    assert!(r.contains("; body line 6: the PR body carries"), "{r}");
}

#[test]
fn the_plugin_root_names_the_absolute_path_and_reads_its_summary() {
    let root = fixture_root("summary", |reg| {
        reg.replace(
            "The pull request body needs exactly one --- separator and a non-empty Part 1",
            "A CHANGED SUMMARY",
        )
    });
    let r = evaluate_all(
        &hook(&create("feat: x", BAD)),
        RegistrySource::PluginRoot(root.clone()),
    )
    .expect("denies");
    assert!(
        r.contains("pr-body/one-separator: A CHANGED SUMMARY: "),
        "{r}"
    );
    let canon = std::fs::canonicalize(&root).unwrap();
    assert!(
        r.contains(&format!(
            "full text: {}/references/pr-body-conformance.md lines ",
            canon.display()
        )),
        "{r}"
    );
    let _ = std::fs::remove_dir_all(&root);
}

/// A plugin root with the repository's references, the registry edited by
/// `edit`.
fn fixture_root(name: &str, edit: impl Fn(String) -> String) -> PathBuf {
    let repo = Path::new(env!("CARGO_MANIFEST_DIR")).join("../..");
    let dir = std::env::temp_dir().join(format!("shirabe-eval-{name}-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&dir);
    std::fs::create_dir_all(dir.join("references")).unwrap();
    let reg = std::fs::read_to_string(repo.join("references/rule-registry.json")).unwrap();
    std::fs::write(dir.join("references/rule-registry.json"), edit(reg)).unwrap();
    std::fs::copy(
        repo.join("references/pr-body-conformance.md"),
        dir.join("references/pr-body-conformance.md"),
    )
    .unwrap();
    dir
}

#[test]
fn a_damaged_registry_fails_closed_on_a_checked_command_only() {
    let cases: Vec<(&str, Box<dyn Fn(String) -> String>, &str)> = vec![
        (
            "unreadable",
            Box::new(|_| "not json".to_string()),
            "registry",
        ),
        (
            "missing",
            Box::new(|r| r.replace("\"pr-body/one-separator\"", "\"pr-body/renamed\"")),
            "`pr-body/one-separator`",
        ),
        (
            "anchor",
            Box::new(|r| r.replace("\"or fence the example.\"", "\"no such anchor text\"")),
            "`pr-body/one-separator`",
        ),
    ];
    for (name, edit, word) in cases {
        let root = fixture_root(name, edit);
        let src = || RegistrySource::PluginRoot(root.clone());
        // A clean create is denied too: the registry must answer for every
        // rule the action is guarded by.
        let r = evaluate_all(&hook(&create("feat: x", GOOD)), src()).expect(name);
        assert_fail_closed(&r, word);
        let r = evaluate_all(&hook(&create("feat: x", BAD)), src()).expect(name);
        assert_fail_closed(&r, word);
        // Nothing guarded: no decision, whatever the registry says.
        for cmd in [
            "ls",
            "git status",
            "gh pr view 3",
            "gh pr edit 3 --add-label x",
        ] {
            assert_eq!(evaluate_all(&hook(cmd), src()), None, "{name}: {cmd}");
        }
        let _ = std::fs::remove_dir_all(&root);
    }
}

/// A registry entry's `stage` decides how a gate script prints its findings,
/// not whether the hook denies: a body breaking PB2 is denied under
/// `pr-body/one-separator` at every stage.
#[test]
fn pb2_is_denied_at_every_stage() {
    for stage in ["block", "warn", "shadow", "retired"] {
        let root = fixture_root(&format!("stage-{stage}"), |reg| {
            let mut v: serde_json::Value = serde_json::from_str(&reg).unwrap();
            for e in v["rules"].as_array_mut().unwrap() {
                if e["id"] == "pr-body/one-separator" {
                    e["stage"] = serde_json::Value::from(stage);
                }
            }
            serde_json::to_string_pretty(&v).unwrap()
        });
        let r = evaluate_all(
            &hook(&create("feat: x", BAD)),
            RegistrySource::PluginRoot(root.clone()),
        )
        .unwrap_or_else(|| panic!("{stage}: PB2 was not denied"));
        assert!(r.contains("pr-body/one-separator: "), "{stage}: {r}");
        assert!(!r.contains("could not check"), "{stage}: {r}");
        let _ = std::fs::remove_dir_all(&root);
    }
}

// --- the example table's PR rows, end to end -------------------------------

#[test]
fn example_rows_for_pull_request_commands() {
    let d = std::env::temp_dir().join(format!("shirabe-eval-rows-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&d);
    std::fs::create_dir_all(&d).unwrap();
    std::fs::write(d.join("b.md"), "x\n\n---\n\ny\n").unwrap();
    let made = std::process::Command::new("mkfifo")
        .arg(d.join("fifo"))
        .status()
        .unwrap();
    assert!(made.success());
    let run = |cmd: &str| evaluate(&hook_in(cmd, &d));

    for cmd in [
        "ls",
        "git status",
        "git commit -m x",
        "gh pr view 3",
        "echo \"gh pr create\"",
        "gh issue create --title pr --body edit",
        "git log --grep push",
        "gh pr edit 12 --add-label x",
        "gh pr merge 1 --squash --body \"Adds a new edit path.\"",
        "env -u GH_TOKEN gh pr merge 1 --squash --body \"Adds a new edit path.\"",
        "env -u GH_TOKEN gh issue create --title \"hook refuses gh pr create\" --body x",
    ] {
        assert_eq!(run(cmd), None, "{cmd}");
    }
    assert_eq!(run(&create("feat: x", GOOD)), None);

    let deny = |cmd: &str| run(cmd).unwrap_or_else(|| panic!("{cmd} should deny"));
    assert_fail_closed(&deny("echo `gh pr create`"), "wrapped");
    assert_fail_closed(
        &deny("env -u GH_TOKEN gh pr create --title \"feat: x\" --body \"Adds x.\""),
        "wrapped",
    );
    assert_fail_closed(
        &deny("printf 'x' > b.md && gh pr create --title \"feat: x\" -F b.md"),
        "same command",
    );
    assert_fail_closed(
        &deny("gh pr create --title \"feat: x\" -F fifo"),
        "regular file",
    );
    assert_fail_closed(&deny("gh pr create --title \"feat: x\""), "no body");
    assert_fail_closed(&deny(&format!("gh pr create --body '{GOOD}'")), "title");
    assert_fail_closed(
        &deny("gh pr create --title \"feat: x\" --body \"$BODY\""),
        "body",
    );
    assert_fail_closed(&deny("gh pr create --fill"), "--fill");

    let rule = |cmd: &str, ids: &[&str]| {
        let r = deny(cmd);
        let found: Vec<&str> = PR_RULES
            .iter()
            .copied()
            .filter(|id| r.contains(&format!("{id}: ")))
            .collect();
        let mut want = ids.to_vec();
        want.sort();
        let mut got = found.clone();
        got.sort();
        assert_eq!(got, want, "{cmd}: {r}");
        assert!(!r.contains("could not check"), "{cmd}: {r}");
    };
    rule(&create("feat: x", BAD), &["pr-body/one-separator"]);
    rule(
        &format!("GH_TOKEN=t gh -R o/r pr create --title \"feat: x\" --body '{BAD}'"),
        &["pr-body/one-separator"],
    );
    rule(
        &format!("git add . && gh pr create --title \"Add x\" --body '{BAD}'"),
        &["pr-body/conventional-title", "pr-body/one-separator"],
    );
    rule(
        "gh pr create --title \"feat: x\" --body \"$(cat <<'EOF'\nIt's bad, no separator.\nEOF\n)\"",
        &["pr-body/one-separator"],
    );
    rule(
        &format!("gh pr -R o/r create --title \"feat: x\" --body '{BAD}'"),
        &["pr-body/one-separator"],
    );
    rule(
        "gh pr edit 12 --title \"bad title\"",
        &["pr-body/conventional-title"],
    );
    rule(
        &format!("gh pr edit 12 --body '{BAD}'"),
        &["pr-body/one-separator"],
    );
    let _ = std::fs::remove_dir_all(&d);
}

#[test]
fn a_head_in_another_case_is_judged_as_the_lowercase_one() {
    // On a case-insensitive filesystem `ENV` runs env and `GH` runs gh
    // (#1074's repro is the first row).
    for (upper, lower) in [
        (
            "ENV gh pr create -t \"feat: x\" -b \"Adds x.\"",
            "env gh pr create -t \"feat: x\" -b \"Adds x.\"",
        ),
        (
            "ENV -u GH_TOKEN gh pr create -t \"feat: x\" -b \"Adds x.\"",
            "env -u GH_TOKEN gh pr create -t \"feat: x\" -b \"Adds x.\"",
        ),
        ("Sudo gh pr edit 12 --body x", "sudo gh pr edit 12 --body x"),
        (
            "BASH -c 'gh pr create --title x'",
            "bash -c 'gh pr create --title x'",
        ),
        (
            format!("GH pr create --title 'feat: x' --body '{BAD}'").as_str(),
            create("feat: x", BAD).as_str(),
        ),
        (
            "GH pr edit 12 --title \"bad title\"",
            "gh pr edit 12 --title \"bad title\"",
        ),
    ] {
        let want = evaluate(&hook(lower)).unwrap_or_else(|| panic!("{lower} should deny"));
        assert_eq!(evaluate(&hook(upper)), Some(want), "{upper}");
    }
    assert_fail_closed(
        &evaluate(&hook("ENV gh pr create -t \"feat: x\" -b \"Adds x.\"")).unwrap(),
        "wrapped",
    );
    for cmd in [
        "ENV -u GH_TOKEN gh pr merge 1 --squash --body \"Adds a new edit path.\"",
        format!("GH pr create --title 'feat: x' --body '{GOOD}'").as_str(),
    ] {
        assert_eq!(evaluate(&hook(cmd)), None, "{cmd}");
    }
}

#[test]
fn here_document_bodies_are_checked() {
    for q in ["'EOF'", "\"EOF\"", "EOF"] {
        let good = format!(
            "gh pr create --title 'feat: x' --body \"$(cat <<{q}\nAdds x.\n\n---\n\nContext.\nEOF\n)\""
        );
        assert_eq!(evaluate(&hook(&good)), None, "{q}");
        let bad = good.replace("\n\n---\n\n", "\n");
        assert!(
            evaluate(&hook(&bad))
                .unwrap()
                .contains("pr-body/one-separator"),
            "{q}"
        );
    }
    let expands =
        "gh pr create --title 'feat: x' --body \"$(cat <<EOF\n$HOME\n\n---\n\nx\nEOF\n)\"";
    assert_fail_closed(&evaluate(&hook(expands)).expect("denies"), "body");
}

#[test]
fn body_file_forms_relative_to_cd() {
    let d = std::env::temp_dir().join(format!("shirabe-eval-cd-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&d);
    std::fs::create_dir_all(d.join("sub")).unwrap();
    std::fs::write(d.join("sub/bad.md"), "one part\n").unwrap();
    for cmd in [
        "gh pr create --title 'feat: x' -F sub/bad.md",
        "cd sub && gh pr create --title 'feat: x' --body-file=bad.md",
    ] {
        let r = evaluate(&hook_in(cmd, &d)).expect("denies");
        assert!(r.contains("pr-body/one-separator"), "{cmd}: {r}");
    }
    let _ = std::fs::remove_dir_all(&d);
}

// --- segment-less cases and the rule sets ----------------------------------

#[test]
fn malformed_input_naming_a_guarded_action_is_denied() {
    let r = evaluate("{\"tool_input\": {\"command\": \"gh pr create --title x").expect("denies");
    assert_fail_closed(&r, "hook input");
    // The legacy entry point leaves a push to the plugin's hook.
    assert_eq!(evaluate("not json: git push"), None);
    let r = evaluate_all("not json: git push", RegistrySource::Embedded).expect("denies");
    assert_fail_closed(&r, "hook input");
    assert!(r.contains("`git push`"), "{r}");
}

#[test]
fn an_oversize_input_is_denied_only_when_it_names_a_guarded_action() {
    let pad = "x".repeat(MAX_INPUT);
    let r = evaluate(&hook(&format!("gh pr create --body '{pad}'"))).expect("denies");
    assert_fail_closed(&r, "4 MiB");
    assert_eq!(evaluate(&hook(&format!("echo '{pad}'"))), None);
}

#[test]
fn an_unterminated_quote_without_a_guarded_action_gives_no_decision() {
    assert_eq!(evaluate(&hook("echo 'oops")), None);
    assert_eq!(evaluate(&hook("git push 'oops")), None, "legacy: PR only");
    let r = evaluate_all(&hook("git push 'oops"), RegistrySource::Embedded).expect("denies");
    assert_fail_closed(&r, "quote");
}

#[test]
fn push_cases_belong_to_the_full_rule_set() {
    for (cmd, word) in [
        ("sudo git push", "wrapped"),
        ("git commit -m x && git push", "same command"),
        ("git --git-dir=x push", "--git-dir=x"),
        ("GIT_DIR=x git push", "GIT_DIR="),
        ("cd \"$DIR\" && git push", "directory"),
    ] {
        assert_eq!(
            evaluate(&hook_in(cmd, Path::new("/r"))),
            None,
            "legacy: {cmd}"
        );
        let r = evaluate_all(&hook_in(cmd, Path::new("/r")), RegistrySource::Embedded)
            .unwrap_or_else(|| panic!("{cmd} should deny"));
        assert_fail_closed(&r, word);
        assert!(r.contains("commit/no-ai-trailer"), "{r}");
    }
    // A push the classifier hands over reaches the push check, which finds
    // no repository at `/r`.
    let r = evaluate_all(
        &hook_in("git push", Path::new("/r")),
        RegistrySource::Embedded,
    )
    .expect("denies");
    assert_fail_closed(&r, "work tree");
}

// --- the deadline runner ---------------------------------------------------

#[test]
fn a_panic_or_a_hang_fails_closed_on_a_guarded_command_only() {
    let guarded = hook("gh pr create --title t --body b");
    let plain = hook("ls");
    let boom = |_: &str| -> Option<String> { panic!("boom") };
    let r = decide(guarded.clone(), RuleSet::PrBodyOnly, DEADLINE, boom).expect("denies");
    assert_fail_closed(&r, "crash");
    assert_eq!(
        decide(plain.clone(), RuleSet::PrBodyOnly, DEADLINE, boom),
        None
    );
    let slow = |_: &str| -> Option<String> {
        std::thread::sleep(Duration::from_secs(5));
        None
    };
    let start = std::time::Instant::now();
    let r = decide(
        guarded,
        RuleSet::PrBodyOnly,
        Duration::from_millis(100),
        slow,
    )
    .expect("denies");
    assert!(start.elapsed() < Duration::from_secs(2));
    assert_fail_closed(&r, "25 seconds");
    assert_eq!(
        decide(plain, RuleSet::PrBodyOnly, Duration::from_millis(100), slow),
        None
    );
}

#[test]
fn an_earlier_command_substitution_is_the_same_command() {
    let d = std::env::temp_dir().join(format!("shirabe-nested-{}", std::process::id()));
    std::fs::create_dir_all(&d).unwrap();
    std::fs::write(d.join("b.md"), "Adds x.\n\n---\n\nctx\n").unwrap();
    for (cmd, action) in [
        (
            "echo $(git commit -qm \"x\" -m \"Co-Authored-By: Claude <noreply@anthropic.com>\") && git push",
            "`git push`",
        ),
        (
            "echo $(printf 'Adds x.' > b.md) && gh pr create -t \"feat: x\" -F b.md",
            "`gh pr create`",
        ),
    ] {
        let r = evaluate_all(&hook_in(cmd, &d), RegistrySource::Embedded)
            .unwrap_or_else(|| panic!("{cmd} should deny"));
        assert_fail_closed(&r, "same command");
        assert!(r.contains(action), "{r}");
    }
    let _ = std::fs::remove_dir_all(&d);
}

#[test]
fn attached_short_values_are_checked() {
    for (cmd, id, not) in [
        (
            "gh pr edit 12 -b'Adds x.'",
            "pr-body/one-separator",
            "pr-body/conventional-title",
        ),
        (
            "gh pr edit 12 -t'Add x'",
            "pr-body/conventional-title",
            "pr-body/one-separator",
        ),
        (
            "gh pr edit 12 -t=Add",
            "pr-body/conventional-title",
            "pr-body/one-separator",
        ),
        (
            "gh pr create -t'feat: x' -b'Adds x.'",
            "pr-body/one-separator",
            "pr-body/conventional-title",
        ),
        (
            "gh pr create -t='Add x' -b='Adds x.\n\n---\n\nctx'",
            "pr-body/conventional-title",
            "pr-body/one-separator",
        ),
    ] {
        for r in [
            evaluate(&hook(cmd)),
            evaluate_all(&hook(cmd), RegistrySource::Embedded),
        ] {
            let r = r.unwrap_or_else(|| panic!("{cmd} should deny"));
            assert!(r.contains(&format!("{id}:")), "{cmd}: {r}");
            assert!(!r.contains(&format!("{not}:")), "{cmd}: {r}");
        }
    }
    assert_eq!(
        evaluate(&hook("gh pr create -t'feat: x' -b'Adds x.\n\n---\n\nctx'")),
        None
    );
}

#[test]
fn gh_pr_new_is_checked_like_create() {
    let r = evaluate(&hook(
        &create("feat: x", BAD).replace("pr create", "pr new"),
    ))
    .expect("denies");
    assert!(r.contains("pr-body/one-separator:"), "{r}");
    assert!(r.contains("`gh pr create`"), "{r}");
    let r = evaluate(&hook("gh pr new --fill")).expect("denies");
    assert_fail_closed(&r, "--fill");
    let r = evaluate(&hook("gh pr new --body x")).expect("denies");
    assert_fail_closed(&r, "title");
    assert_eq!(
        evaluate(&hook(
            &create("feat: x", GOOD).replace("pr create", "pr new")
        )),
        None
    );
    // The segment-less cases name it too.
    assert!(evaluate(&hook("gh pr new --title 'oops")).is_some());
    assert!(evaluate("not json: gh pr new").is_some());
}

#[test]
fn substitutions_nested_too_deep_fail_closed_on_a_guarded_command_only() {
    let deep = |head: &str| format!("{head} {}x{}", "$(".repeat(3000), ")".repeat(3000));
    for (head, rules) in [
        ("git push origin", RuleSet::All),
        ("gh pr create --title", RuleSet::PrBodyOnly),
    ] {
        let input = hook_in(&deep(head), Path::new("/r"));
        let r = super::evaluate(
            &input,
            &Ctx {
                rules,
                registry: RegistrySource::Embedded,
                canary_opted_in: &|| false,
                legacy_wired: &|| false,
                git: &NotARepo,
                git_budget: push::GIT_BUDGET,
            },
        )
        .unwrap_or_else(|| panic!("{head} should deny"));
        assert_fail_closed(&r, "nested");
    }
    assert_eq!(evaluate(&hook(&deep("echo"))), None);
    assert_eq!(
        evaluate_all(&hook(&deep("echo")), RegistrySource::Embedded),
        None
    );
    // Unclosed, it is the same case.
    let r = evaluate(&hook(&format!("gh pr edit 3 -b {}", "$(".repeat(4000)))).expect("denies");
    assert_fail_closed(&r, "nested");
}

#[test]
fn the_fallback_reads_the_command_not_the_rest_of_the_input() {
    let boom = |_: &str| -> Option<String> { panic!("boom") };
    let slow = |_: &str| -> Option<String> {
        std::thread::sleep(Duration::from_secs(5));
        None
    };
    let short = Duration::from_millis(100);
    let described = serde_json::json!({
        "tool_name": "Bash",
        "tool_input": { "command": "ls", "description": "list files, git push later, then gh pr create" },
    })
    .to_string();
    for eval in [boom, slow] {
        for rules in [RuleSet::All, RuleSet::PrBodyOnly, RuleSet::PushOnly] {
            assert_eq!(decide(described.clone(), rules, short, eval), None);
        }
        // A guarded command still fails closed.
        let guarded = serde_json::json!({
            "tool_name": "Bash",
            "tool_input": { "command": "g\"i\"t push", "description": "ls" },
        })
        .to_string();
        assert!(decide(guarded, RuleSet::All, short, eval).is_some());
        // A backslash-newline in the command joins its lines.
        for (command, named) in [("gi\\\nt push", true), ("cd x\\\ngit push", false)] {
            let input = serde_json::json!({
                "tool_name": "Bash",
                "tool_input": { "command": command },
            })
            .to_string();
            assert_eq!(
                decide(input, RuleSet::All, short, eval).is_some(),
                named,
                "{command}"
            );
        }
        // Input that doesn't parse is read raw.
        assert!(decide("not json: git push".into(), RuleSet::All, short, eval).is_some());
    }
}

#[test]
fn the_deadline_runner_keeps_the_plugins_rule_sets() {
    let boom = |_: &str| -> Option<String> { panic!("boom") };
    let slow = |_: &str| -> Option<String> {
        std::thread::sleep(Duration::from_secs(5));
        None
    };
    let short = Duration::from_millis(100);
    let push = hook("git push");
    let pr = hook("gh pr create --title t --body b");
    for eval in [boom, slow] {
        let r = decide(push.clone(), RuleSet::All, short, eval).expect("denies");
        assert!(r.contains("`git push`"), "{r}");
        assert!(r.contains("commit/no-ai-trailer"), "{r}");
        let r = decide(pr.clone(), RuleSet::All, short, eval).expect("denies");
        assert!(r.contains("pr-body/one-separator"), "{r}");
        // Under PR_BODY_HOOK_DISABLE the pull request isn't the plugin's.
        assert_eq!(decide(pr.clone(), RuleSet::PushOnly, short, eval), None);
        assert!(decide(push.clone(), RuleSet::PushOnly, short, eval).is_some());
        assert_eq!(decide(hook("ls"), RuleSet::All, short, eval), None);
    }
}

// --- the plugin's yield to the legacy entry point (PRD R12) ----------------

/// Every input of the yield tests, a broken rule or a fail-closed case each.
const YIELD_CASES: &[&str] = &[
    "gh pr create --title 'feat: x' --body 'Adds x.'",
    "gh pr create --fill",
    "gh pr edit 3 --body \"$(date)\"",
    "sudo gh pr create --title 'feat: x' --body 'Adds x.'",
];

#[test]
fn wired_the_plugin_gives_no_decision_on_a_pull_request() {
    for cmd in YIELD_CASES {
        let input = hook_in(cmd, Path::new("/r"));
        assert!(
            evaluate_plugin(&input, RegistrySource::Embedded, || false).is_some(),
            "unwired: {cmd}"
        );
        assert_eq!(
            evaluate_plugin(&input, RegistrySource::Embedded, || true),
            None,
            "wired: {cmd}"
        );
    }
    // Segment-less cases naming only a pull request.
    for input in [
        "not json: gh pr create".to_string(),
        hook("gh pr create --title 'oops"),
    ] {
        assert!(evaluate_plugin(&input, RegistrySource::Embedded, || false).is_some());
        assert_eq!(
            evaluate_plugin(&input, RegistrySource::Embedded, || true),
            None,
            "{input}"
        );
    }
}

#[test]
fn wired_the_plugin_still_reports_the_push_cases() {
    for (cmd, word) in [
        ("sudo git push", "wrapped"),
        ("git commit -m x && git push", "same command"),
        ("git --git-dir=x push", "--git-dir=x"),
        ("gh pr create --fill && sudo git push", "wrapped"),
    ] {
        let r = evaluate_plugin(
            &hook_in(cmd, Path::new("/r")),
            RegistrySource::Embedded,
            || true,
        )
        .unwrap_or_else(|| panic!("{cmd} should deny"));
        assert_fail_closed(&r, word);
        assert!(r.contains("commit/no-ai-trailer"), "{r}");
        assert!(!r.contains("pr-body/"), "{cmd}: {r}");
        assert!(!r.contains("`gh pr"), "{cmd}: {r}");
    }
    // A segment-less case naming both keeps only the push.
    for input in [
        "not json: gh pr create && git push".to_string(),
        hook("gh pr create --title x && git push 'oops"),
    ] {
        let r = evaluate_plugin(&input, RegistrySource::Embedded, || true).expect("denies");
        assert!(r.contains("`git push`"), "{r}");
        assert!(!r.contains("pr-body/"), "{r}");
    }
}

#[test]
fn the_two_entry_points_report_a_broken_rule_once_between_them() {
    let inputs = [
        hook(&create("feat: x", BAD)),
        hook_in(
            &format!("{} && sudo git push", create("Add x", BAD)),
            Path::new("/r"),
        ),
        "not json: gh pr create && git push".to_string(),
    ];
    for input in &inputs {
        let legacy = evaluate(input).unwrap_or_default();
        let plugin = evaluate_plugin(input, RegistrySource::Embedded, || true).unwrap_or_default();
        // A rule is named in a broken-rule block or a fail-closed
        // paragraph's `guarded by:` line, by one entry point only.
        for id in RULES {
            assert!(
                !(legacy.contains(id) && plugin.contains(id)),
                "{id} in both:\n{legacy}\n---\n{plugin}"
            );
        }
        assert!(!legacy.is_empty(), "{input}");
    }
    let both = evaluate(&inputs[1]).unwrap()
        + &evaluate_plugin(&inputs[1], RegistrySource::Embedded, || true).unwrap();
    for id in ["pr-body/conventional-title", "pr-body/one-separator"] {
        assert_eq!(both.matches(&format!("{id}:")).count(), 1, "{both}");
    }
    assert!(both.contains("commit/no-ai-trailer"), "{both}");
}

#[test]
fn the_settings_are_read_only_for_a_pull_request_under_the_full_set() {
    let asked = std::cell::Cell::new(0);
    let probe = || {
        asked.set(asked.get() + 1);
        true
    };
    for cmd in [
        "ls",
        "echo gh pr create",
        "git push",
        "sudo git push",
        "git commit -m x && git push",
    ] {
        let _ = evaluate_plugin(
            &hook_in(cmd, Path::new("/r")),
            RegistrySource::Embedded,
            probe,
        );
        assert_eq!(asked.get(), 0, "{cmd}");
    }
    let _ = evaluate_plugin(
        &hook(&create("feat: x", BAD)),
        RegistrySource::Embedded,
        probe,
    );
    assert_eq!(asked.get(), 1, "asked once per call");
    // The push-only set (PR_BODY_HOOK_DISABLE) has nothing to yield.
    let r = super::evaluate(
        &hook(&create("feat: x", BAD)),
        &Ctx {
            rules: RuleSet::PushOnly,
            registry: RegistrySource::Embedded,
            canary_opted_in: &|| false,
            legacy_wired: &probe,
            git: &NoGit,
            git_budget: push::GIT_BUDGET,
        },
    );
    assert_eq!(r, None);
    assert_eq!(asked.get(), 1);
}

#[test]
fn the_rule_table_is_the_pr_rules_then_the_push_rules() {
    let joined: Vec<&str> = PR_RULES.iter().chain(PUSH_RULES).copied().collect();
    assert_eq!(RULES, joined.as_slice());
    let reg = Registry::embedded().unwrap();
    for id in RULES {
        reg.range(reg.entry(id).unwrap()).unwrap();
    }
}

/// The plugin script passes its `RULE_IDS` line as `--rules`, and
/// scripts/check-rule-registry.sh holds that line to the registry's `deny`
/// fields; this holds it to the table, so the three can't drift apart.
#[test]
fn the_rule_table_is_the_hook_scripts_rule_ids_line() {
    let path = Path::new(env!("CARGO_MANIFEST_DIR")).join("../../hooks/pre-action-deny.sh");
    let script = std::fs::read_to_string(&path).expect("hooks/pre-action-deny.sh");
    let lines: Vec<&str> = script
        .lines()
        .filter_map(|l| l.strip_prefix("RULE_IDS=\""))
        .collect();
    assert_eq!(lines.len(), 1, "one RULE_IDS line in {}", path.display());
    let ids = lines[0].strip_suffix('"').expect("a closing quote");
    assert_eq!(ids.split(' ').collect::<Vec<_>>(), RULES);
}
