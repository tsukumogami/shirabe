//! CLI integration tests for L10, the lifecycle finding that stops a step
//! plan from completing while it still holds a one-line outline step.
//!
//! Each case under `crates/shirabe-validate/tests/fixtures/plan-v2/<case>/`
//! is a small repository root: a DESIGN and the `plan/v2` PLAN built from it.
//! `--lifecycle-chain` derives the root from the PLAN's `docs/plans/` path,
//! so each case is read on its own. The runs use the default draft posture,
//! where a present PLAN at `Active` is the expected mid-PR state and raises
//! no L01, so the findings below are the ones the step plan itself causes.

use std::fs;
use std::path::{Path, PathBuf};
use std::process::{Command, Output};

const CASES: &str = "crates/shirabe-validate/tests/fixtures/plan-v2";

fn workspace_root() -> PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR"))
        .join("../..")
        .canonicalize()
        .expect("workspace root")
}

fn shirabe(args: &[&str]) -> Output {
    Command::new(env!("CARGO_BIN_EXE_shirabe"))
        .current_dir(workspace_root())
        .env_remove("SHIRABE_PR_NUMBER")
        .env_remove("GITHUB_REF")
        .env_remove("GITHUB_REPOSITORY")
        .env_remove("GITHUB_TOKEN")
        .args(args)
        .output()
        .expect("run shirabe")
}

fn plan(case: &str) -> String {
    format!("{CASES}/{case}/docs/plans/PLAN-greeting.md")
}

fn stdout(out: &Output) -> String {
    String::from_utf8_lossy(&out.stdout).into_owned()
}

/// Lines carrying the given check code.
fn lines_with<'a>(text: &'a str, code: &str) -> Vec<&'a str> {
    let tag = format!("[{code}]");
    text.lines().filter(|l| l.contains(&tag)).collect()
}

fn lifecycle_chain(case: &str) -> (Option<i32>, String) {
    let out = shirabe(&["validate", "--lifecycle-chain", &plan(case)]);
    (out.status.code(), stdout(&out))
}

#[test]
fn every_case_plan_passes_fc22() {
    for case in [
        "lifecycle-outline-step",
        "lifecycle-two-outline-steps",
        "lifecycle-all-detailed",
        "lifecycle-unticked-detailed-step",
    ] {
        let out = shirabe(&["validate", "--check", "FC22", &plan(case)]);
        assert_eq!(out.status.code(), Some(0), "{case}: {}", stdout(&out));
        assert!(stdout(&out).is_empty(), "{case}: {}", stdout(&out));
    }
}

#[test]
fn one_outline_step_stops_completion_naming_it() {
    let (code, text) = lifecycle_chain("lifecycle-outline-step");
    assert_ne!(code, Some(0), "{text}");
    let l10 = lines_with(&text, "L10");
    assert_eq!(l10.len(), 1, "{text}");
    assert!(l10[0].contains("Step 3 is still an outline"), "{text}");
    assert!(l10[0].starts_with("::error "), "{text}");
}

#[test]
fn two_outline_steps_give_one_finding_each() {
    let (code, text) = lifecycle_chain("lifecycle-two-outline-steps");
    assert_ne!(code, Some(0), "{text}");
    let l10 = lines_with(&text, "L10");
    assert_eq!(l10.len(), 2, "{text}");
    assert!(l10[0].contains("Step 3 "), "{text}");
    assert!(l10[1].contains("Step 4 "), "{text}");
}

#[test]
fn a_fully_detailed_and_ticked_plan_raises_neither_l10_nor_l06() {
    let (code, text) = lifecycle_chain("lifecycle-all-detailed");
    assert_eq!(code, Some(0), "{text}");
    assert!(lines_with(&text, "L10").is_empty(), "{text}");
    assert!(lines_with(&text, "L06").is_empty(), "{text}");
}

#[test]
fn an_unticked_detailed_step_is_l06_not_l10() {
    let (_, text) = lifecycle_chain("lifecycle-unticked-detailed-step");
    assert!(lines_with(&text, "L10").is_empty(), "{text}");
    let l06 = lines_with(&text, "L06");
    assert_eq!(l06.len(), 1, "{text}");
    assert!(l06[0].contains("Step 3: "), "{text}");
}

#[test]
fn the_whole_tree_run_reports_no_l10() {
    let root = format!("{CASES}/lifecycle-outline-step");
    let out = shirabe(&["validate", "--lifecycle", &root]);
    assert!(
        lines_with(&stdout(&out), "L10").is_empty(),
        "{}",
        stdout(&out)
    );
    assert_eq!(out.status.code(), Some(0), "{}", stdout(&out));
}

/// Copy a case into a temp root outside the git tree with its PLAN edited.
fn edited_case(case: &str, tag: &str, edit: impl Fn(&str) -> String) -> PathBuf {
    let src = workspace_root().join(CASES).join(case);
    let dst = std::env::temp_dir().join(format!(
        "shirabe-plan-v2-lifecycle-{}-{tag}",
        std::process::id()
    ));
    let _ = fs::remove_dir_all(&dst);
    for sub in ["docs/designs", "docs/plans"] {
        fs::create_dir_all(dst.join(sub)).expect("mkdir");
        for entry in fs::read_dir(src.join(sub)).expect("read case") {
            let entry = entry.expect("entry");
            fs::copy(entry.path(), dst.join(sub).join(entry.file_name())).expect("copy");
        }
    }
    let plan = dst.join("docs/plans/PLAN-greeting.md");
    let text = fs::read_to_string(&plan).expect("read plan");
    fs::write(&plan, edit(&text)).expect("write plan");
    dst
}

fn l01_lines(root: &Path) -> Vec<String> {
    let plan = root.join("docs/plans/PLAN-greeting.md");
    let out = shirabe(&["validate", "--lifecycle-chain", plan.to_str().unwrap()]);
    lines_with(&stdout(&out), "L01")
        .into_iter()
        .map(str::to_string)
        .collect()
}

/// The same plan written as `plan/v1`: one issue outline per step, so the
/// two versions differ only in what L01 could possibly key on.
fn as_plan_v1(text: &str) -> String {
    text.replace("schema: plan/v2", "schema: plan/v1")
        .replace("step_count: 3", "issue_count: 3")
        .replace("## Steps", "## Issue Outlines")
        .replace("### Step ", "### Issue ")
        .replace(
            "**Dependencies**: Step ",
            "**Dependencies**: Blocked by Issue ",
        )
}

#[test]
fn a_draft_step_plan_fails_l01_as_a_draft_plan_v1_does() {
    let draft = |t: &str| t.replace("status: Active", "status: Draft");
    let v2 = l01_lines(&edited_case("lifecycle-all-detailed", "v2-draft", draft));
    let v1 = l01_lines(&edited_case("lifecycle-all-detailed", "v1-draft", |t| {
        as_plan_v1(&draft(t))
    }));
    assert_eq!(v2.len(), 1, "{v2:?}");
    assert!(v2[0].contains("PLAN at status 'Draft'"), "{v2:?}");
    assert_eq!(v2, v1, "plan/v2 and plan/v1 Draft PLANs fail L01 alike");
}

#[test]
fn an_active_step_plan_raises_no_l01_a_plan_v1_one_would_not() {
    let v2 = l01_lines(&edited_case("lifecycle-all-detailed", "v2-active", |t| {
        t.to_string()
    }));
    let v1 = l01_lines(&edited_case(
        "lifecycle-all-detailed",
        "v1-active",
        as_plan_v1,
    ));
    assert!(v2.is_empty(), "{v2:?}");
    assert_eq!(v2, v1);
}
