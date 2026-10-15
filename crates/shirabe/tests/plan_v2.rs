//! CLI integration tests for the `plan/v2` step plan, end to end through the
//! built binary: `shirabe validate` accepts the minimal step plan and refuses
//! a mismatched `step_count` or a missing `## Steps`, and `shirabe plan
//! outlines` lists its steps. The five-layer `plan/v1` fixture's validator
//! output is pinned so the `plan/v2` work cannot move a `plan/v1` result.
//!
//! Each run uses the workspace root as its working directory and passes the
//! fixture's workspace-relative path, so the `file=` annotation is stable.

use std::path::{Path, PathBuf};
use std::process::{Command, Output};

const FIXTURES: &str = "crates/shirabe-validate/tests/fixtures";

fn workspace_root() -> PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR"))
        .join("../..")
        .canonicalize()
        .expect("workspace root")
}

fn shirabe(args: &[&str]) -> Output {
    Command::new(env!("CARGO_BIN_EXE_shirabe"))
        .current_dir(workspace_root())
        // FC09's PR-context surface, cleared as the golden parity tests do.
        .env_remove("SHIRABE_PR_NUMBER")
        .env_remove("GITHUB_REF")
        .env_remove("GITHUB_REPOSITORY")
        .env_remove("GITHUB_TOKEN")
        .args(args)
        .output()
        .expect("run shirabe")
}

fn fixture(name: &str) -> String {
    format!("{FIXTURES}/{name}")
}

fn stdout(out: &Output) -> String {
    String::from_utf8_lossy(&out.stdout).into_owned()
}

/// Copy the minimal fixture into a temp dir as a `PLAN-` file with `edit`
/// applied, so a variant routes to the Plan spec like the original.
fn variant(tag: &str, edit: impl Fn(&str) -> String) -> PathBuf {
    let src = std::fs::read_to_string(workspace_root().join(fixture("PLAN-v2-minimal.md")))
        .expect("read minimal fixture");
    let dir = std::env::temp_dir().join(format!("shirabe-plan-v2-{}-{tag}", std::process::id()));
    std::fs::create_dir_all(&dir).expect("mkdir");
    let path = dir.join(format!("PLAN-{tag}.md"));
    std::fs::write(&path, edit(&src)).expect("write variant");
    path
}

#[test]
fn the_minimal_step_plan_validates_clean() {
    let out = shirabe(&["validate", &fixture("PLAN-v2-minimal.md")]);
    assert_eq!(out.status.code(), Some(0), "stdout: {}", stdout(&out));
    assert_eq!(stdout(&out), "");
}

#[test]
fn a_step_count_mismatch_is_refused_naming_the_field() {
    let out = shirabe(&[
        "validate",
        &fixture("PLAN-v2-minimal-step-count-mismatch.md"),
    ]);
    assert_eq!(out.status.code(), Some(2));
    let text = stdout(&out);
    assert!(text.contains("[FC22]"), "{text}");
    assert!(text.contains("'step_count: 4'"), "{text}");
    assert!(text.contains("rule: step-count"), "{text}");
}

#[test]
fn a_missing_steps_section_is_refused_naming_the_section() {
    let out = shirabe(&["validate", &fixture("PLAN-v2-minimal-no-steps.md")]);
    assert_eq!(out.status.code(), Some(2));
    assert_eq!(
        stdout(&out),
        format!(
            "::error file={},line=1::[FC04] missing required section '## Steps'\n",
            fixture("PLAN-v2-minimal-no-steps.md")
        )
    );
}

#[test]
fn the_step_plan_validates_clean_as_multi_pr() {
    let path = variant("multi", |s| {
        s.replace("execution_mode: single-pr", "execution_mode: multi-pr")
    });
    let out = shirabe(&["validate", path.to_str().unwrap()]);
    assert_eq!(out.status.code(), Some(0), "stdout: {}", stdout(&out));
}

#[test]
fn plan_outlines_lists_three_steps_two_of_them_detailed() {
    let out = shirabe(&["plan", "outlines", &fixture("PLAN-v2-minimal.md")]);
    assert_eq!(out.status.code(), Some(0));
    let v: serde_json::Value = serde_json::from_slice(&out.stdout).expect("json envelope");
    assert_eq!(v["schema"], "shirabe-plan-outlines/v1");
    let steps = v["outlines"].as_array().expect("outlines");
    let numbers: Vec<u64> = steps
        .iter()
        .map(|s| s["number"].as_u64().unwrap())
        .collect();
    assert_eq!(numbers, vec![1, 2, 3]);
    for s in steps {
        assert_eq!(s["entry"], "step");
    }
    let detailed: Vec<bool> = steps
        .iter()
        .map(|s| s["detailed"].as_bool().unwrap())
        .collect();
    assert_eq!(detailed, vec![true, true, false]);
    let checks: Vec<bool> = steps
        .iter()
        .map(|s| s["check_declared"].as_bool().unwrap())
        .collect();
    assert_eq!(checks, vec![true, true, false]);
    assert_eq!(steps[1]["waits_on"], serde_json::json!([1]));
    assert_eq!(steps[0]["waits_on"], serde_json::json!([]));
}

#[test]
fn plan_outlines_still_reads_a_plan_v1_document() {
    let out = shirabe(&["plan", "outlines", &fixture("PLAN-v1-five-layer.md")]);
    assert_eq!(out.status.code(), Some(0));
    let v: serde_json::Value = serde_json::from_slice(&out.stdout).expect("json envelope");
    let issues = v["outlines"].as_array().expect("outlines");
    let numbers: Vec<u64> = issues
        .iter()
        .map(|s| s["number"].as_u64().unwrap())
        .collect();
    assert_eq!(numbers, vec![1, 2, 3, 4, 5]);
    let waits: Vec<serde_json::Value> = issues.iter().map(|s| s["waits_on"].clone()).collect();
    assert_eq!(
        waits,
        vec![
            serde_json::json!([]),
            serde_json::json!([1]),
            serde_json::json!([1, 2]),
            serde_json::json!([1, 2]),
            serde_json::json!([2]),
        ]
    );
    for s in issues {
        assert_eq!(s["entry"], "issue");
        assert_eq!(s["detailed"], true);
    }
}

/// The five-layer `plan/v1` regression anchor: its validator output,
/// recorded with the binary built before `plan/v2` existed, byte for byte.
#[test]
fn the_five_layer_plan_v1_output_is_unchanged() {
    let path = fixture("PLAN-v1-five-layer.md");
    let out = shirabe(&["validate", &path]);
    assert_eq!(out.status.code(), Some(2));
    let expected = [
        "::notice file={f}::[FC13] HTML comment on line 1 before the frontmatter '---' opener; the parser will silent-skip frontmatter -- see references/fixes/eval-fixture-frontmatter.md",
        "::error file={f},line=5::[R6] upstream \"docs/designs/current/DESIGN-template-evidence-routing.md\" does not exist on disk",
        "::notice file={f}::[FC08] Diagram declares `classDef needsDecision` outside the canonical Status palette but the Legend does not name it",
        "::notice file={f}::[FC08] Diagram declares `classDef needsDesign` outside the canonical Status palette but the Legend does not name it",
        "::notice file={f}::[FC08] Diagram declares `classDef needsPrd` outside the canonical Status palette but the Legend does not name it",
        "::notice file={f}::[FC08] Diagram declares `classDef needsSpike` outside the canonical Status palette but the Legend does not name it",
        "::notice file={f}::[FC08] Diagram declares `classDef tracksDesign` outside the canonical Status palette but the Legend does not name it",
        "::notice file={f}::[FC08] Diagram declares `classDef tracksPlan` outside the canonical Status palette but the Legend does not name it",
        "::notice file={f}::[FC12] field \"validate()\" declared with conflicting shapes (line 43 vs line 44); see references/fixes/plan-design-field-consistency.md",
        "::notice file={f}::[FC14] execution_mode is 'single-pr' but '## Dependency Graph' is populated -- switch the frontmatter to 'multi-pr' or remove the diagram body",
    ]
    .iter()
    .map(|l| format!("{}\n", l.replace("{f}", &path)))
    .collect::<String>();
    assert_eq!(stdout(&out), expected);
}
