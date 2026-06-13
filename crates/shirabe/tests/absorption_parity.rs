//! Captured-corpus rule-set-diff parity harness for the check-absorption work
//! (DESIGN-shirabe-check-absorption, Decision 4).
//!
//! This is the cutover gate for each absorbed check: it proves the engine's
//! absorbed check fires the same rules as the external check it replaces, over
//! a frozen corpus, before the external copy is deleted. It is a third instance
//! of the shape `transition_parity.rs` and `parity.rs` already use -- a frozen
//! corpus, captured baselines, and one `#[test]` per case so a failure names
//! the exact diverging case.
//!
//! ## Why a fired-rule-SET diff (not byte, not pass/fail)
//!
//! The two sides use different code vocabularies and message formats by design,
//! so a byte comparison fails on benign formatting. Pass/fail-only comparison
//! would hide a same-verdict-different-rule edge (both reject a document, but
//! the engine fires fewer or differently-named rules). So each side is
//! normalized to the SET of rules it fired and the sets are diffed in the
//! engine's code vocabulary.
//!
//! ## The oracle and the baselines (capture-ahead, no live shell)
//!
//! The external check is the oracle. It is run ONCE, ahead of time, by a
//! developer in a controlled environment over the authors' own corpus, and the
//! SET of rules it fired for each case is committed under
//! `expected/<case_id>/external_rules` (one rule id per line; `#` comments and
//! blank lines ignored). `cargo test` and CI read those committed baselines and
//! spawn NO external shell -- the only process this harness launches is the
//! `shirabe` binary itself.
//!
//! ## What this test asserts, per case
//!
//! 1. Run `shirabe validate --format json --check <codes>` over the case's
//!    corpus document and collect the SET of `findings[].code` (the engine set).
//! 2. Read the committed external fired-rule set and translate it into the
//!    engine's code vocabulary via `mapping.tsv` (external_rule -> engine_code,
//!    same-verdict equivalences only).
//! 3. Apply the case's rows from `divergences.tsv`: an `engine_only` row adds an
//!    engine code the engine deliberately fires where the external check has no
//!    rule (union-by-default strictness); an `external_only` row tolerates an
//!    external rule the engine deliberately does not absorb.
//! 4. Assert the engine set equals the expected set. A failure names the case
//!    and the symmetric difference, so the diverging rule is obvious.
//!
//! The divergence manifest is the single source of truth for deliberate edges,
//! keyed to Decision 2's reconciliation verdicts, so the parity test asserts the
//! chosen behavior instead of failing blindly and the manifest cannot drift from
//! the design's verdict table.

use std::collections::BTreeSet;
use std::path::{Path, PathBuf};
use std::process::Command;

/// Absolute path to `tests/fixtures/absorption-golden`.
fn golden_dir() -> PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR")).join("tests/fixtures/absorption-golden")
}

/// Read non-comment, non-blank lines from a fixture file, tab-splitting each.
fn read_rows(path: &Path) -> Vec<Vec<String>> {
    let text = std::fs::read_to_string(path)
        .unwrap_or_else(|e| panic!("read fixture {}: {e}", path.display()));
    text.lines()
        .map(str::trim_end)
        .filter(|l| !l.trim().is_empty() && !l.trim_start().starts_with('#'))
        .map(|l| l.split('\t').map(|c| c.trim().to_string()).collect())
        .collect()
}

/// One parsed `cases.tsv` row.
struct Case {
    id: String,
    doc_relpath: String,
    check_codes: Vec<String>,
    /// `check` (per-file `--check`) or `lifecycle` (whole-tree `--lifecycle`).
    mode: String,
}

fn read_cases() -> Vec<Case> {
    read_rows(&golden_dir().join("cases.tsv"))
        .into_iter()
        .map(|cols| {
            assert!(
                cols.len() == 3 || cols.len() == 4,
                "cases.tsv row must have 3 or 4 tab-separated columns, got {cols:?}"
            );
            Case {
                id: cols[0].clone(),
                doc_relpath: cols[1].clone(),
                check_codes: cols[2].split(',').map(|s| s.trim().to_string()).collect(),
                mode: cols.get(3).cloned().unwrap_or_else(|| "check".to_string()),
            }
        })
        .collect()
}

fn case(id: &str) -> Case {
    read_cases()
        .into_iter()
        .find(|c| c.id == id)
        .unwrap_or_else(|| panic!("case {id} missing from cases.tsv"))
}

/// `external_rule -> engine_code` same-verdict equivalence map.
fn read_mapping() -> Vec<(String, String)> {
    read_rows(&golden_dir().join("mapping.tsv"))
        .into_iter()
        .map(|cols| {
            assert_eq!(
                cols.len(),
                2,
                "mapping.tsv row must have 2 tab-separated columns, got {cols:?}"
            );
            (cols[0].clone(), cols[1].clone())
        })
        .collect()
}

/// Per-case deliberate divergence rows: `(case_id, token, direction, reason)`.
fn read_divergences() -> Vec<(String, String, String, String)> {
    read_rows(&golden_dir().join("divergences.tsv"))
        .into_iter()
        .map(|cols| {
            assert!(
                cols.len() >= 3,
                "divergences.tsv row needs at least case_id, token, direction, got {cols:?}"
            );
            let reason = cols.get(3).cloned().unwrap_or_default();
            (cols[0].clone(), cols[1].clone(), cols[2].clone(), reason)
        })
        .collect()
}

/// The committed external fired-rule set for a case.
fn external_rule_set(case_id: &str) -> BTreeSet<String> {
    read_rows(
        &golden_dir()
            .join("expected")
            .join(case_id)
            .join("external_rules"),
    )
    .into_iter()
    .map(|cols| cols[0].clone())
    .collect()
}

/// Run the engine over a corpus document and collect the SET of fired codes.
///
/// FC09's env-var surface is cleared so the engine set is deterministic
/// regardless of whether the test runs locally or in GitHub Actions (mirroring
/// `parity.rs`). The github-status absorption (a later issue) extends FC09's
/// injected-state path, so without this its fired set would depend on ambient
/// CI env and the parity diff would flake. Keeping it here preserves the
/// append-only contract: a new check is added by appending a `cases.tsv` row,
/// a corpus doc, and a baseline — never by editing this function.
///
/// Note the envelope of that contract: this harness runs `validate` directly
/// against the in-tree corpus doc with no temp git repo (correct for a
/// read-only check over the parsed document). A future check that needs git or
/// repo context is OUTSIDE the append-only envelope and must extend the harness
/// deliberately, as `transition_parity.rs` does with its per-case temp repo.
fn engine_rule_set(doc: &Path, check_codes: &[String]) -> BTreeSet<String> {
    let bin = env!("CARGO_BIN_EXE_shirabe");
    let mut cmd = Command::new(bin);
    cmd.env_remove("SHIRABE_PR_NUMBER")
        .env_remove("GITHUB_REF")
        .env_remove("GITHUB_REPOSITORY")
        .env_remove("GITHUB_TOKEN")
        .arg("validate")
        .arg("--format")
        .arg("json");
    for code in check_codes {
        cmd.arg("--check").arg(code);
    }
    cmd.arg(doc);
    let out = cmd.output().expect("run shirabe validate");
    let stdout = String::from_utf8(out.stdout).expect("validate stdout is UTF-8");
    parse_codes(&stdout)
}

/// Run the engine in whole-tree lifecycle mode over a corpus root and collect
/// the SET of fired codes. Status-directory parity is captured this way: the
/// engine absorbs status-vs-directory as the lifecycle check L07, and L-codes
/// are not per-file `--check` selectable (they are whole-tree checks), so the
/// `--check` path above cannot exercise them. This runs the same offline,
/// network-free validate the per-file path does, just over the case's tree.
fn engine_lifecycle_set(corpus_root: &Path) -> BTreeSet<String> {
    let bin = env!("CARGO_BIN_EXE_shirabe");
    let out = Command::new(bin)
        .arg("validate")
        .arg("--format")
        .arg("json")
        .arg("--lifecycle")
        .arg(corpus_root)
        .output()
        .expect("run shirabe validate --lifecycle");
    let stdout = String::from_utf8(out.stdout).expect("validate stdout is UTF-8");
    parse_codes(&stdout)
}

/// Extract the set of `"code": "..."` values from the validate JSON envelope
/// without pulling a JSON dependency into the test crate (the sibling parity
/// harnesses likewise avoid serde, comparing captured text directly).
///
/// Invariant this scan relies on: on *stdout*, the only `"code"` key is
/// `findings[].code`. The error envelope's `"code"` field goes to stderr (which
/// this harness never reads), and document-derived values interpolated into a
/// message render with escaped quotes (`\"code\"`), so they never contribute the
/// bare `"code"` token. If a future `--format json` schema adds another stdout
/// `"code"` key, this scan would over-collect and must be revisited.
fn parse_codes(json: &str) -> BTreeSet<String> {
    let mut set = BTreeSet::new();
    for chunk in json.split("\"code\"").skip(1) {
        // chunk starts after the key; find the first quoted string after the colon.
        if let Some(colon) = chunk.find(':') {
            let rest = &chunk[colon + 1..];
            if let Some(start) = rest.find('"') {
                if let Some(end) = rest[start + 1..].find('"') {
                    set.insert(rest[start + 1..start + 1 + end].to_string());
                }
            }
        }
    }
    set
}

/// Translate the external set into engine codes and apply the case's recorded
/// divergences, producing the SET the engine is expected to fire.
fn expected_engine_set(case_id: &str, external: &BTreeSet<String>) -> BTreeSet<String> {
    let mapping = read_mapping();
    let divergences = read_divergences();

    let mut expected = BTreeSet::new();
    for rule in external {
        // `external_only` divergence: the engine deliberately does not absorb
        // this external rule, so it contributes no engine code.
        let is_external_only = divergences
            .iter()
            .any(|(c, tok, dir, _)| c == case_id && tok == rule && dir == "external_only");
        if is_external_only {
            continue;
        }
        match mapping.iter().find(|(ext, _)| ext == rule) {
            Some((_, code)) => {
                expected.insert(code.clone());
            }
            None => panic!(
                "external rule {rule:?} for case {case_id} is neither in mapping.tsv \
                 nor recorded as an external_only divergence; the absorption is unaccounted for"
            ),
        }
    }
    // `engine_only` divergence: the engine deliberately fires this code where
    // the external check has no matching rule (union-by-default strictness).
    for (c, tok, dir, _) in &divergences {
        if c == case_id && dir == "engine_only" {
            expected.insert(tok.clone());
        }
    }
    expected
}

/// The single per-case assertion: live engine set vs translated external set.
fn assert_parity(case_id: &str) {
    let c = case(case_id);
    let corpus_root = golden_dir().join("corpus").join(case_id);
    let doc = corpus_root.join(&c.doc_relpath);
    assert!(
        doc.is_file(),
        "corpus document for {case_id} not found at {}",
        doc.display()
    );

    let engine = match c.mode.as_str() {
        "check" => engine_rule_set(&doc, &c.check_codes),
        "lifecycle" => engine_lifecycle_set(&corpus_root),
        other => panic!("case {case_id}: unknown mode {other:?} (expected check|lifecycle)"),
    };
    let external = external_rule_set(case_id);
    let expected = expected_engine_set(case_id, &external);

    assert_eq!(
        engine, expected,
        "fired-rule-set divergence for {case_id}\n\
         --- engine fired ---\n{engine:?}\n\
         --- expected (external translated + recorded divergences) ---\n{expected:?}\n\
         --- raw external set ---\n{external:?}\n\
         If this is a deliberate edge, record it in divergences.tsv; otherwise the \
         absorbed check diverges from the source it replaces."
    );
}

macro_rules! parity_tests {
    ($($name:ident => $case_id:literal,)*) => {
        $(
            #[test]
            fn $name() {
                assert_parity($case_id);
            }
        )*
    };
}

parity_tests! {
    // frontmatter.sh (design frontmatter) at parity with engine FC01/FC02/FC03,
    // captured from the real script over design documents. A clean design fires
    // nothing on either side; a missing required field fires FM01/FC01, an
    // invalid status value FM02/FC02, and a frontmatter-vs-body status mismatch
    // FM03/FC03.
    frontmatter_clean           => "frontmatter-clean",
    frontmatter_missing_field   => "frontmatter-missing-field",
    frontmatter_invalid_status  => "frontmatter-invalid-status",
    frontmatter_status_mismatch => "frontmatter-status-mismatch",

    // sections.sh (design sections) at parity with engine FC04 (presence) and
    // FC15 (order). A clean design fires nothing; a missing section fires
    // SC01/FC04; an out-of-order section fires SC02/FC15. An empty Security
    // Considerations section fires SC03, which the engine deliberately does not
    // absorb (recorded as an external_only divergence).
    sections_clean              => "sections-clean",
    sections_missing            => "sections-missing",
    sections_order              => "sections-order",
    sections_security_empty     => "sections-security-empty",

    // status-directory.sh (design status-vs-directory) at parity with engine
    // L07, run in lifecycle mode: a Current design outside docs/designs/current/
    // fires SD01/L07.
    status_directory_misplaced  => "status-directory-misplaced",

    // Issues-table row-content (engine FC05) hand-authored cases retained from
    // the engine-side absorption; these retire with the legacy
    // implementation-issues.sh check (Outline 4), not captured here.
    issues_table_complexity_bad => "issues-table-complexity-bad",
    issues_table_dep_format_bad => "issues-table-dep-format-bad",

    // github-status (engine FC09). FC09 already implements the full
    // doc-vs-GitHub reconciliation; offline (no injected PR context, which the
    // harness clears) it surfaces a deterministic skip notice where the
    // external check silently no-ops, recorded as an engine_only divergence.
    // The live reconciliation needs network and is covered by FC09's own unit
    // tests, not this offline harness.
    github_status_no_context   => "github-status-no-context",
}
