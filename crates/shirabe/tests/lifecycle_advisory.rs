//! End-to-end tests for the context-aware advisory explanation layer
//! (Issue 3 of the lifecycle-posture-mode plan), exercising the built
//! `shirabe` binary.
//!
//! The advisory layer explains a verdict in posture terms by reading the
//! typed `draft` boolean from `$GITHUB_EVENT_PATH` — for phrasing only. The
//! load-bearing invariant is **advisory-never-gates**: the exit code and the
//! existing `shirabe-validate/v1` JSON verdict fields (outcome, errors, and
//! each finding's code/severity/file/line) must NOT change with the event
//! payload content. Only the additive `advisory` object and the human
//! `Advisory:` prose may vary.
//!
//! These tests set `GITHUB_EVENT_PATH` per invocation (with a temp file) so
//! they remain offline and hermetic; the gate path makes no network call.

use std::fs;
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicUsize, Ordering};

use assert_cmd::Command;

static COUNTER: AtomicUsize = AtomicUsize::new(0);

fn shirabe() -> Command {
    Command::cargo_bin("shirabe").expect("binary `shirabe` builds")
}

/// Build a uniquely-named temp dir with the standard `docs/` subdirectories
/// and write the given docs into it.
fn build_tree(docs: &[(&str, String)]) -> PathBuf {
    let n = COUNTER.fetch_add(1, Ordering::SeqCst);
    let root =
        std::env::temp_dir().join(format!("shirabe-cli-advisory-{}-{}", std::process::id(), n));
    let _ = fs::remove_dir_all(&root);
    for sub in &["docs/briefs", "docs/prds", "docs/designs", "docs/plans"] {
        fs::create_dir_all(root.join(sub)).unwrap();
    }
    for (rel, content) in docs {
        let path = root.join(rel);
        if let Some(parent) = path.parent() {
            fs::create_dir_all(parent).unwrap();
        }
        fs::write(&path, content).unwrap();
    }
    fs::canonicalize(&root).unwrap()
}

/// Write `content` to a uniquely-named temp event file and return its path.
fn write_event(content: &str) -> PathBuf {
    let n = COUNTER.fetch_add(1, Ordering::SeqCst);
    let path = std::env::temp_dir().join(format!(
        "shirabe-cli-advisory-event-{}-{}.json",
        std::process::id(),
        n
    ));
    fs::write(&path, content).unwrap();
    path
}

fn doc(frontmatter: &str, body: &str) -> String {
    format!("---\n{}---\n\n{}\n", frontmatter, body)
}

/// An orphan BRIEF at Draft — the head of a fresh chain. The orphan rule
/// fires L02 (draft-tolerable): a notice under draft, an error under ready.
fn orphan_brief() -> String {
    let fm = "schema: brief/v1\nstatus: Draft\nproblem: |\n  problem.\noutcome: |\n  outcome.\n";
    let body = "# BRIEF: t\n\n## Status\n\nDraft\n\n## Problem Statement\n\nP.\n\n## User Outcome\n\nO.\n\n## User Journeys\n\n### Journey 1\n\nU does thing.\n\n## Scope Boundary\n\nIN: x.\nOUT: y.\n";
    doc(fm, body)
}

/// Run `validate --lifecycle <root> --mode <mode> --format <format>` with the
/// given optional `GITHUB_EVENT_PATH`. Returns (exit_code, stdout).
fn run(root: &Path, mode: &str, format: &str, event_path: Option<&Path>) -> (i32, String) {
    let mut cmd = shirabe();
    cmd.arg("validate")
        .arg("--lifecycle")
        .arg(root)
        .arg("--mode")
        .arg(mode)
        .arg("--format")
        .arg(format);
    // Neutralize any ambient PR context inherited from the test environment
    // so the only signal is the one each test sets explicitly.
    cmd.env_remove("GITHUB_EVENT_PATH");
    if let Some(p) = event_path {
        cmd.env("GITHUB_EVENT_PATH", p);
    }
    let out = cmd.output().expect("run shirabe");
    let code = out.status.code().expect("exit code");
    let stdout = String::from_utf8(out.stdout).expect("utf8 stdout");
    (code, stdout)
}

/// Extract the verdict-bearing slice of the JSON: everything from the opening
/// brace up to (but excluding) the additive `"advisory"` key, plus the
/// closing structure. This is the portion that must be byte-identical
/// regardless of advisory context. We compare it by stripping the advisory
/// block, which always appears after `findings`.
fn verdict_slice(json: &str) -> String {
    match json.find("  \"advisory\": {") {
        // Everything before the advisory block is the verdict envelope. The
        // trailing comma after `findings` is the only delta the advisory
        // introduces, so normalize it away for the comparison.
        Some(idx) => json[..idx].replace("]\n  \"advisory\"", "]\n").to_string(),
        None => json.to_string(),
    }
}

// ---- in-flight pass: advisory names each tolerated finding by code ----

#[test]
fn in_flight_pass_advisory_names_tolerated_findings() {
    let root = build_tree(&[("docs/briefs/BRIEF-foo.md", orphan_brief())]);
    let event = write_event(r#"{"pull_request":{"draft":true}}"#);

    let (code, json) = run(&root, "draft", "json", Some(&event));
    assert_eq!(
        code, 0,
        "in-flight L02 must pass under draft; json: {}",
        json
    );
    // The verdict envelope is intact (clean, the L02 finding present as a notice).
    assert!(json.contains("\"outcome\": \"clean\""), "json: {}", json);
    assert!(json.contains("\"code\": \"L02\""), "json: {}", json);
    // The advisory names L02 by code with a remedy.
    assert!(
        json.contains("\"advisory\": {"),
        "advisory block present: {}",
        json
    );
    assert!(
        json.contains("\"code\": \"L02\"") && json.contains("\"remedy\":"),
        "advisory note for L02 with remedy: {}",
        json
    );

    let (hcode, human) = run(&root, "draft", "human", Some(&event));
    assert_eq!(hcode, 0);
    assert!(
        human.contains("Advisory:"),
        "human advisory block: {}",
        human
    );
    assert!(human.contains("L02"), "human names L02: {}", human);

    let _ = fs::remove_file(&event);
}

// ---- ready failure on a draft-tolerable finding names the escape hatch ----

#[test]
fn ready_failure_advisory_states_draft_would_pass() {
    let root = build_tree(&[("docs/briefs/BRIEF-foo.md", orphan_brief())]);
    let event = write_event(r#"{"pull_request":{"draft":false}}"#);

    let (code, json) = run(&root, "ready", "json", Some(&event));
    assert_eq!(code, 2, "L02 must fail under ready; json: {}", json);
    assert!(
        json.contains("\"outcome\": \"violations\""),
        "json: {}",
        json
    );
    // The advisory names the draft escape hatch and the concrete flag.
    assert!(json.contains("\"advisory\": {"), "json: {}", json);
    assert!(
        json.contains("--mode=draft"),
        "advisory must name the draft escape hatch: {}",
        json
    );
    assert!(json.contains("\"code\": \"L02\""), "json: {}", json);

    let _ = fs::remove_file(&event);
}

// ---- LOAD-BEARING anti-gating: differing event content, identical verdict ----

#[test]
fn anti_gating_event_content_cannot_move_verdict() {
    let root = build_tree(&[("docs/briefs/BRIEF-foo.md", orphan_brief())]);

    // Three different GITHUB_EVENT_PATH situations under the SAME docs + mode:
    //  - draft PR
    //  - ready PR
    //  - absent (no event path)
    let event_draft = write_event(r#"{"pull_request":{"draft":true}}"#);
    let event_ready = write_event(r#"{"pull_request":{"draft":false}}"#);

    for mode in ["draft", "ready"] {
        let (c_draft, j_draft) = run(&root, mode, "json", Some(&event_draft));
        let (c_ready, j_ready) = run(&root, mode, "json", Some(&event_ready));
        let (c_absent, j_absent) = run(&root, mode, "json", None);

        // Exit code is identical regardless of event payload content.
        assert_eq!(
            c_draft, c_ready,
            "exit code must not vary with draft/ready event under mode {}",
            mode
        );
        assert_eq!(
            c_draft, c_absent,
            "exit code must not vary with absent event under mode {}",
            mode
        );

        // The verdict slice of the JSON (everything except the additive
        // advisory block) is byte-identical across all three event contexts.
        let v_draft = verdict_slice(&j_draft);
        let v_ready = verdict_slice(&j_ready);
        let v_absent = verdict_slice(&j_absent);
        assert_eq!(
            v_draft, v_ready,
            "verdict envelope must be byte-identical for draft vs ready event under mode {}",
            mode
        );
        assert_eq!(
            v_draft, v_absent,
            "verdict envelope must be byte-identical for present vs absent event under mode {}",
            mode
        );

        // Sanity: the verdict slice carries the real verdict fields.
        assert!(v_draft.contains("\"outcome\":"));
        assert!(v_draft.contains("\"code\": \"L02\""));
        assert!(v_draft.contains("\"severity\":"));

        // Sanity: the advisory block is present (the additive surface that
        // the PR context is allowed to vary). Under draft mode (an in-flight
        // pass) the phrasing distinguishes draft-PR vs ready-PR contexts, so
        // assert the prose actually differs there — proving the advisory does
        // read the event while the verdict above stays fixed.
        assert!(j_draft.contains("\"advisory\": {"));
        if mode == "draft" {
            assert_ne!(
                j_draft, j_ready,
                "advisory prose should differ across PR contexts under draft mode"
            );
        }
    }

    let _ = fs::remove_file(&event_draft);
    let _ = fs::remove_file(&event_ready);
}

// ---- absent / malformed payload degrades, no crash, verdict unchanged ----

#[test]
fn malformed_payload_degrades_to_posture_only() {
    let root = build_tree(&[("docs/briefs/BRIEF-foo.md", orphan_brief())]);
    let bad = write_event("{ this is not valid json at all");
    let missing = std::env::temp_dir().join("shirabe-advisory-nonexistent-event.json");
    let _ = fs::remove_file(&missing);

    // Baseline: a present-but-draft event.
    let good = write_event(r#"{"pull_request":{"draft":true}}"#);
    let (c_good, j_good) = run(&root, "draft", "json", Some(&good));

    // Malformed and absent payloads must not crash and must yield the same
    // verdict envelope as the good run.
    let (c_bad, j_bad) = run(&root, "draft", "json", Some(&bad));
    let (c_miss, j_miss) = run(&root, "draft", "json", Some(&missing));

    assert_eq!(c_good, 0);
    assert_eq!(c_bad, 0, "malformed payload must not change exit code");
    assert_eq!(c_miss, 0, "absent payload must not change exit code");

    assert_eq!(
        verdict_slice(&j_good),
        verdict_slice(&j_bad),
        "malformed payload must not change the verdict envelope"
    );
    assert_eq!(
        verdict_slice(&j_good),
        verdict_slice(&j_miss),
        "absent payload must not change the verdict envelope"
    );
    // Degrades to posture-only phrasing: still a valid advisory block.
    assert!(j_bad.contains("\"advisory\": {"), "json: {}", j_bad);

    let _ = fs::remove_file(&bad);
    let _ = fs::remove_file(&good);
}

// ---- sanitization: crafted payload cannot emit control/escape chars ----

#[test]
fn crafted_payload_cannot_emit_control_or_escape_chars() {
    let root = build_tree(&[("docs/briefs/BRIEF-foo.md", orphan_brief())]);

    // An event payload carrying ANSI escape and control bytes embedded in
    // (and around) the pull_request object. The advisory layer lifts ONLY
    // the typed `draft` boolean from this, never any of these bytes — and
    // every advisory string is sanitized regardless. The crafted bytes must
    // not reach the rendered output.
    let crafted = "{\"action\":\"\u{1b}[31mEVIL\u{1b}[0m\",\"pull_request\":{\"title\":\"\u{0007}\u{1b}[2J\",\"draft\":true}}";
    let event = write_event(crafted);

    // Human format is the verbatim-emit channel; assert no ESC / control
    // bytes survive into it.
    let (_hcode, human) = run(&root, "draft", "human", Some(&event));
    assert!(
        !human.contains('\u{1b}'),
        "no ESC byte may reach the human render: {:?}",
        human
    );
    assert!(
        !human.contains('\u{0007}'),
        "no BEL byte may reach the human render: {:?}",
        human
    );
    // The draft bit was still read (the advisory engaged) — phrasing is present.
    assert!(human.contains("Advisory:"), "advisory present: {}", human);

    // JSON format must likewise carry no raw ESC byte.
    let (_jcode, json) = run(&root, "draft", "json", Some(&event));
    assert!(
        !json.contains('\u{1b}'),
        "no ESC byte may reach the JSON render: {:?}",
        json
    );

    let _ = fs::remove_file(&event);
}
