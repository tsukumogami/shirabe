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

/// Each malformed step-plan fixture, the one new finding it must produce
/// (code, then text the line must carry: the step and the rule), and
/// nothing else at error level. An FC14 notice that Issue 1 already emitted
/// for a non-step heading is the only other line allowed.
const MALFORMED: &[(&str, &str, &[&str])] = &[
    (
        "PLAN-v2-issue-heading.md",
        "FC22",
        &["'### Issue 2:", "rule: step-heading"],
    ),
    (
        "PLAN-v2-gate-heading.md",
        "FC22",
        &["'### Gate: release'", "rule: step-heading"],
    ),
    (
        "PLAN-v2-issue-count.md",
        "FC22",
        &["'issue_count'", "rule: issue-count"],
    ),
    (
        "PLAN-v2-skeleton-outline.md",
        "FC22",
        &["step 1 is an outline", "rule: skeleton-detailed"],
    ),
    (
        "PLAN-v2-detailed-goal.md",
        "FC22",
        &["step 2 ", "rule: detailed-goal"],
    ),
    (
        "PLAN-v2-detailed-criteria.md",
        "FC22",
        &["step 2 ", "rule: detailed-criteria"],
    ),
    (
        "PLAN-v2-detailed-check.md",
        "FC22",
        &["step 2 ", "rule: detailed-check"],
    ),
    (
        "PLAN-v2-outline-two-lines.md",
        "FC22",
        &["step 3 ", "rule: outline-one-line"],
    ),
    (
        "PLAN-v2-detailed-prefix.md",
        "FC22",
        &["step 3 ", "outline step 2", "rule: detailed-prefix"],
    ),
    (
        "PLAN-v2-dependency-later.md",
        "FC22",
        &["step 1 depends on step 2", "rule: dependency-order"],
    ),
    (
        "PLAN-v2-dependency-format.md",
        "FC22",
        &["step 2 ", "'Issue 1'", "rule: dependency-format"],
    ),
    (
        "PLAN-v2-step-gap.md",
        "FC22",
        &["step 4 follows step 2", "rule: step-numbering"],
    ),
    (
        "PLAN-v2-step-duplicate.md",
        "FC22",
        &["step 3 is numbered twice", "rule: step-numbering"],
    ),
    (
        "PLAN-v2-step-number-above-999.md",
        "FC22",
        &["'### Step 1000:", "rule: step-number)"],
    ),
    (
        "PLAN-v2-step-number-leading-zero.md",
        "FC22",
        &["'### Step 03:", "rule: step-number)"],
    ),
    (
        "PLAN-v2-coordinated.md",
        "FC22",
        &["'coordinated'", "plan/v1", "rule: supported-mode"],
    ),
    (
        "PLAN-v2-tracking-issues.md",
        "FC22",
        &["'issues'", "plan/v1", "rule: supported-tracking"],
    ),
    (
        "PLAN-v2-tracking-issues-and-milestone.md",
        "FC22",
        &[
            "'issues-and-milestone'",
            "plan/v1",
            "rule: supported-tracking",
        ],
    ),
    (
        "PLAN-v2-hostile-heading.md",
        "FC22",
        &["rule: step-heading"],
    ),
    // A `Step <N>` naming no step is FC17's, worded as it words an
    // unresolved `Issue <N>` on plan/v1.
    (
        "PLAN-v2-dependency-missing.md",
        "FC17",
        &["step 'Step 2:", "'Step 9'"],
    ),
    ("PLAN-v2-missing-step-count.md", "FC01", &["\"step_count\""]),
];

fn error_lines(text: &str) -> Vec<&str> {
    text.lines().filter(|l| l.starts_with("::error ")).collect()
}

#[test]
fn each_malformed_step_plan_is_refused_naming_the_step_and_rule() {
    for (name, code, needles) in MALFORMED {
        let out = shirabe(&["validate", &fixture(name)]);
        let text = stdout(&out);
        assert_eq!(out.status.code(), Some(2), "{name}: {text}");
        let errors = error_lines(&text);
        assert_eq!(errors.len(), 1, "{name}: expected one error:\n{text}");
        assert!(
            errors[0].contains(&format!("::[{code}] ")),
            "{name}: {text}"
        );
        for needle in *needles {
            assert!(
                errors[0].contains(needle),
                "{name}: missing {needle:?}:\n{text}"
            );
        }
        for notice in text.lines().filter(|l| !l.starts_with("::error ")) {
            assert!(
                notice.contains("::[FC14] heading '### "),
                "{name}: unexpected line {notice:?}"
            );
        }
    }
}

#[test]
fn issue_count_without_step_count_is_refused_by_fc22_and_fc01() {
    let out = shirabe(&["validate", &fixture("PLAN-v2-issue-count-only.md")]);
    let text = stdout(&out);
    assert_eq!(out.status.code(), Some(2), "{text}");
    let errors = error_lines(&text);
    assert_eq!(errors.len(), 2, "{text}");
    assert!(
        errors[0].contains("[FC01] missing required field \"step_count\""),
        "{text}"
    );
    assert!(errors[1].contains("rule: issue-count"), "{text}");
}

#[test]
fn the_valid_step_plan_passes_and_tracking_none_passes_too() {
    let out = shirabe(&["validate", &fixture("PLAN-v2-valid.md")]);
    assert_eq!(out.status.code(), Some(0), "stdout: {}", stdout(&out));
    assert_eq!(stdout(&out), "");
    let path = variant("tracking-none", |s| {
        s.replace(
            "execution_mode: single-pr\n",
            "execution_mode: multi-pr\ntracking_level: none\n",
        )
    });
    let out = shirabe(&["validate", path.to_str().unwrap()]);
    assert_eq!(out.status.code(), Some(0), "stdout: {}", stdout(&out));
}

#[test]
fn sections_out_of_order_are_named_by_fc15() {
    let out = shirabe(&["validate", &fixture("PLAN-v2-sections-out-of-order.md")]);
    let text = stdout(&out);
    let lines: Vec<&str> = text.lines().collect();
    assert_eq!(lines.len(), 1, "{text}");
    assert!(
        lines[0].contains("[FC15] section '## Decomposition Strategy' is out of order"),
        "{text}"
    );
}

/// An ANSI escape and a heading past 80 characters come out of FC22 with the
/// control characters gone and the quote cut to 80 characters.
#[test]
fn a_quoted_heading_is_stripped_and_cut_to_80_characters() {
    let out = shirabe(&["validate", &fixture("PLAN-v2-hostile-heading.md")]);
    let text = stdout(&out);
    assert!(!text.contains('\u{1b}'), "{text:?}");
    let error = error_lines(&text)[0];
    let quoted = error
        .split("heading '### ")
        .nth(1)
        .and_then(|rest| rest.split('\'').next())
        .expect("quoted heading");
    assert_eq!(quoted.chars().count(), 80, "{quoted:?}");
}

#[test]
fn check_fc22_selects_fc22_alone() {
    let out = shirabe(&[
        "validate",
        "--check",
        "FC22",
        &fixture("PLAN-v2-issue-heading.md"),
    ]);
    let text = stdout(&out);
    assert_eq!(out.status.code(), Some(2), "{text}");
    let lines: Vec<&str> = text.lines().collect();
    assert_eq!(lines.len(), 1, "{text}");
    assert!(lines[0].contains("::[FC22] "), "{text}");
    // A fixture whose only finding is another code passes under the filter.
    let out = shirabe(&[
        "validate",
        "--check",
        "FC22",
        &fixture("PLAN-v2-missing-step-count.md"),
    ]);
    assert_eq!(out.status.code(), Some(0), "{}", stdout(&out));
    assert_eq!(stdout(&out), "");
}

/// The table and diagram checks never speak on a step plan, and FC14 never
/// compares a table with outlines there.
#[test]
fn table_checks_are_silent_on_every_step_plan_fixture() {
    let dir = workspace_root().join(FIXTURES);
    let mut seen = 0;
    for entry in std::fs::read_dir(&dir).expect("fixtures dir") {
        let name = entry
            .expect("entry")
            .file_name()
            .into_string()
            .expect("utf-8 name");
        if !(name.starts_with("PLAN-v2-") && name.ends_with(".md")) {
            continue;
        }
        seen += 1;
        let text = stdout(&shirabe(&["validate", &fixture(&name)]));
        for code in ["FC05", "FC06", "FC07", "FC08", "FC09", "FC11", "FC12"] {
            assert!(!text.contains(&format!("[{code}]")), "{name}: {text}");
        }
        for line in text.lines().filter(|l| l.contains("[FC14]")) {
            assert!(
                !line.contains("Implementation Issues") && !line.contains("Dependency Graph"),
                "{name}: {line}"
            );
        }
    }
    assert!(seen >= 20, "found only {seen} step-plan fixtures");
}
