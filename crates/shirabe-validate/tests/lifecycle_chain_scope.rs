//! What `--lifecycle-chain <doc>` reports, and when an upstream is missing.
//!
//! L04 says a chain member's `upstream:` names a file that doesn't exist. A
//! PRD whose upstream is a STRATEGY, which in turn names a VISION, names files
//! that exist; the lifecycle walk doesn't model those artifacts, so it stops
//! there rather than reporting them missing.
//!
//! The chain-targeted run reports on the chain that holds the document it was
//! given. Drift in another chain in the same tree, of any kind, is the
//! whole-tree run's to report.

use std::fs;
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicUsize, Ordering};

use shirabe_validate::{
    run_lifecycle_chain_check, run_lifecycle_check, Config, ReviewPosture, ValidationError,
};

static COUNTER: AtomicUsize = AtomicUsize::new(0);

// The lifecycle walk reads frontmatter only, so the bodies are a heading.

/// A PRD at `In Progress`.
fn prd(upstream: &str) -> String {
    format!("---\nschema: prd/v1\nstatus: In Progress\nupstream: {upstream}\n---\n\n# PRD: t\n")
}

fn design(status: &str, upstream: &str) -> String {
    format!("---\nschema: design/v1\nstatus: {status}\nupstream: {upstream}\n---\n\n# DESIGN: t\n")
}

/// An issue-carrying multi-pr PLAN at `Active`: the in-flight posture, under
/// which a PRD at `In Progress` and a DESIGN at `Planned` pass.
fn plan(upstream: &str) -> String {
    format!(
        "---\nschema: plan/v1\nstatus: Active\nexecution_mode: multi-pr\nsplit_rationale: Hard Constraint. Fixture plan.\nupstream: {upstream}\n---\n\n# PLAN: t\n"
    )
}

/// A document whose frontmatter does not parse.
const UNPARSEABLE: &str =
    "---\nschema: design/v1\nstatus: Planned\nupstream: [unclosed list\n---\n\n# DESIGN: bad\n";

/// Write `(repo-relative path, full content)` pairs into a fresh temp
/// directory with the artifact directories present, and return its canonical
/// root.
fn tree(docs: &[(&str, String)]) -> PathBuf {
    let n = COUNTER.fetch_add(1, Ordering::SeqCst);
    let root = std::env::temp_dir().join(format!(
        "shirabe-lifecycle-chain-scope-{}-{}",
        std::process::id(),
        n
    ));
    let _ = fs::remove_dir_all(&root);
    for sub in [
        "docs/briefs",
        "docs/prds",
        "docs/designs",
        "docs/designs/current",
        "docs/plans",
        "docs/roadmaps",
    ] {
        fs::create_dir_all(root.join(sub)).unwrap();
    }
    for (rel, content) in docs {
        let path = root.join(rel);
        fs::create_dir_all(path.parent().unwrap()).unwrap();
        fs::write(&path, content).unwrap();
    }
    fs::canonicalize(&root).unwrap()
}

fn targeted(root: &Path, doc: &str) -> Vec<ValidationError> {
    run_lifecycle_chain_check(&root.join(doc), &Config::default(), ReviewPosture::Draft)
}

fn whole(root: &Path) -> Vec<ValidationError> {
    run_lifecycle_check(root, &Config::default(), ReviewPosture::Draft)
}

fn with_code<'a>(errors: &'a [ValidationError], code: &str) -> Vec<&'a ValidationError> {
    errors.iter().filter(|e| e.code == code).collect()
}

/// PLAN -> DESIGN -> PRD -> STRATEGY -> VISION, every file present.
fn chain_to_a_vision() -> PathBuf {
    tree(&[
        (
            "docs/visions/VISION-org.md",
            "---\nschema: vision/v1\nstatus: Accepted\n---\n\n# VISION: org\n".to_string(),
        ),
        (
            "docs/strategies/STRATEGY-foo.md",
            "---\nschema: strategy/v1\nstatus: Active\nupstream: docs/visions/VISION-org.md\n---\n\n# STRATEGY: foo\n"
                .to_string(),
        ),
        (
            "docs/prds/PRD-foo.md",
            prd("docs/strategies/STRATEGY-foo.md"),
        ),
        (
            "docs/designs/DESIGN-foo.md",
            design("Planned", "docs/prds/PRD-foo.md"),
        ),
        ("docs/plans/PLAN-foo.md", plan("docs/designs/DESIGN-foo.md")),
    ])
}

#[test]
fn a_chain_up_to_a_vision_with_every_file_present_reports_no_l04() {
    let root = chain_to_a_vision();
    for doc in [
        "docs/plans/PLAN-foo.md",
        "docs/designs/DESIGN-foo.md",
        "docs/prds/PRD-foo.md",
    ] {
        let errors = targeted(&root, doc);
        assert!(
            with_code(&errors, "L04").is_empty(),
            "--lifecycle-chain {doc}: a STRATEGY that exists is not a missing chain member, got {errors:?}"
        );
    }
    let errors = whole(&root);
    assert!(
        with_code(&errors, "L04").is_empty(),
        "whole tree: a STRATEGY that exists is not a missing chain member, got {errors:?}"
    );
}

#[test]
fn an_upstream_that_is_not_a_file_in_the_repository_still_reports_l04() {
    let root = chain_to_a_vision();
    fs::write(
        root.join("docs/prds/PRD-gone.md"),
        prd("docs/strategies/STRATEGY-gone.md"),
    )
    .unwrap();
    fs::write(
        root.join("docs/plans/PLAN-gone.md"),
        plan("docs/prds/PRD-gone.md"),
    )
    .unwrap();
    // A file that exists, but beside the repository rather than in it.
    let name = format!("{}-outside.md", root.file_name().unwrap().to_string_lossy());
    fs::write(root.parent().unwrap().join(&name), "# outside\n").unwrap();
    fs::write(
        root.join("docs/plans/PLAN-escape.md"),
        plan(&format!("../{name}")),
    )
    .unwrap();

    for (doc, missing) in [
        (
            "docs/plans/PLAN-gone.md",
            "docs/strategies/STRATEGY-gone.md",
        ),
        ("docs/plans/PLAN-escape.md", name.as_str()),
    ] {
        let errors = targeted(&root, doc);
        assert!(
            with_code(&errors, "L04")
                .iter()
                .any(|e| e.message.contains(missing)),
            "--lifecycle-chain {doc}: expected L04 naming {missing}, got {errors:?}"
        );
    }
}

#[test]
fn the_targeted_run_reports_nothing_for_an_unrelated_chain() {
    let root = tree(&[
        // The chain under review, clean.
        (
            "docs/strategies/STRATEGY-one.md",
            "---\nschema: strategy/v1\nstatus: Active\n---\n\n# STRATEGY: one\n".to_string(),
        ),
        (
            "docs/prds/PRD-one.md",
            prd("docs/strategies/STRATEGY-one.md"),
        ),
        (
            "docs/designs/DESIGN-one.md",
            design("Planned", "docs/prds/PRD-one.md"),
        ),
        ("docs/plans/PLAN-one.md", plan("docs/designs/DESIGN-one.md")),
        // Other chains, each with its own drift: a missing member (L04),
        // a cycle (L03), a member that does not parse (L05) and a member at
        // the wrong status (L01).
        (
            "docs/plans/PLAN-gone.md",
            plan("docs/designs/DESIGN-gone.md"),
        ),
        ("docs/prds/PRD-cyc-a.md", prd("docs/prds/PRD-cyc-b.md")),
        ("docs/prds/PRD-cyc-b.md", prd("docs/prds/PRD-cyc-a.md")),
        ("docs/plans/PLAN-cyc.md", plan("docs/prds/PRD-cyc-a.md")),
        ("docs/designs/DESIGN-bad.md", UNPARSEABLE.to_string()),
        ("docs/plans/PLAN-bad.md", plan("docs/designs/DESIGN-bad.md")),
        ("docs/designs/DESIGN-drift.md", design("Proposed", "")),
        (
            "docs/plans/PLAN-drift.md",
            plan("docs/designs/DESIGN-drift.md"),
        ),
    ]);

    let all = whole(&root);
    for code in ["L01", "L03", "L04", "L05"] {
        assert!(
            !with_code(&all, code).is_empty(),
            "the fixture needs {code} drift in another chain, got {all:?}"
        );
    }

    let members = [
        "docs/plans/PLAN-one.md",
        "docs/designs/DESIGN-one.md",
        "docs/prds/PRD-one.md",
    ];
    let errors = targeted(&root, "docs/plans/PLAN-one.md");
    let foreign: Vec<&ValidationError> = errors
        .iter()
        .filter(|e| !members.contains(&e.file.as_str()))
        .collect();
    assert!(
        foreign.is_empty(),
        "--lifecycle-chain on PLAN-one reported documents outside its chain: {foreign:?}"
    );
    for code in ["L03", "L04", "L05"] {
        assert!(
            with_code(&errors, code).is_empty(),
            "--lifecycle-chain on PLAN-one: no {code} belongs to its chain, got {errors:?}"
        );
    }

    // The cycle is still reported to a run targeting a document on it.
    let cycle: Vec<&ValidationError> = with_code(&all, "L03");
    for doc in ["docs/plans/PLAN-cyc.md", "docs/prds/PRD-cyc-a.md"] {
        let errors = targeted(&root, doc);
        assert_eq!(with_code(&errors, "L03"), cycle, "--lifecycle-chain {doc}");
    }
}

#[test]
fn a_member_that_does_not_parse_is_reported_by_its_chain_and_nowhere_else() {
    let root = tree(&[
        ("docs/designs/DESIGN-bad.md", UNPARSEABLE.to_string()),
        ("docs/plans/PLAN-bad.md", plan("docs/designs/DESIGN-bad.md")),
        ("docs/designs/DESIGN-other.md", UNPARSEABLE.to_string()),
    ]);
    let l05_files = |errors: &[ValidationError]| -> Vec<String> {
        with_code(errors, "L05")
            .iter()
            .map(|e| e.file.clone())
            .collect()
    };

    // The file exists, so it is not a missing member; its parse failure is
    // the finding, and it belongs to the chain that reaches it.
    let errors = targeted(&root, "docs/plans/PLAN-bad.md");
    assert!(
        with_code(&errors, "L04").is_empty(),
        "a member that exists is not missing, got {errors:?}"
    );
    assert_eq!(
        l05_files(&errors),
        vec!["docs/designs/DESIGN-bad.md".to_string()],
        "got {errors:?}"
    );

    // Targeting the unparseable document itself reports it, and not the
    // other document that fails to parse.
    let errors = targeted(&root, "docs/designs/DESIGN-bad.md");
    assert_eq!(
        l05_files(&errors),
        vec!["docs/designs/DESIGN-bad.md".to_string()],
        "got {errors:?}"
    );
}
