//! FC23 (BRIEF summary length), FC24 (DESIGN key order) and FC25 (DESIGN
//! provenance openers), run the way `shirabe validate` runs them: parsed from
//! document text by `parse_doc_bytes`, so line counts and positions come from
//! the source an author wrote.
//!
//! All three are notice-level. Every fixture here that breaks one of them is
//! otherwise clean, and the tests assert each of its findings is a notice in
//! both postures, which is what keeps `shirabe validate`'s exit status at 0.

use std::path::Path;

use shirabe_validate::{
    effective_severity, formats, is_known_check_code, parse_doc_bytes, render_json, validate_file,
    Config, ReviewPosture, Severity, ValidationError,
};

/// Every finding `validate_file` returns for `md`, parsed as if it lived at
/// `path`. The format is the one whose schema the document declares.
fn findings(path: &str, md: &str) -> Vec<ValidationError> {
    let doc = parse_doc_bytes(path, md.as_bytes()).expect("fixture parses");
    let spec = formats()
        .into_iter()
        .find(|f| f.accepts_schema(&doc.schema))
        .unwrap_or_else(|| panic!("no format accepts {:?}", doc.schema));
    validate_file(&doc, &spec, &Config::default())
}

fn with_code<'a>(errs: &'a [ValidationError], code: &str) -> Vec<&'a ValidationError> {
    errs.iter().filter(|e| e.code == code).collect()
}

/// Every finding is a notice under both postures: the run exits 0.
fn assert_exits_clean(errs: &[ValidationError]) {
    for e in errs {
        for posture in [ReviewPosture::Draft, ReviewPosture::Ready] {
            assert_eq!(
                effective_severity(&e.code, posture),
                Severity::Notice,
                "{} would fail the run under {posture:?}: {e:?}",
                e.code
            );
        }
    }
}

// --- BRIEF ---------------------------------------------------------------

const BRIEF_BODY: &str = "\n# BRIEF: widgets\n\n## Status\n\nDraft\n\n\
    ## Problem Statement\n\nWidgets are hard to find.\n\n\
    ## User Outcome\n\nA maintainer finds a widget by name.\n\n\
    ## User Journeys\n\nA maintainer searches and opens the widget.\n\n\
    ## Scope Boundary\n\nSearch only; no editing.\n";

const TWO_LINES: &str =
    "|\n  Widgets are hard to find today, and a maintainer\n  gives up before finding one.";

fn brief(problem: &str, outcome: &str) -> String {
    format!("---\nschema: brief/v1\nstatus: Draft\nproblem: {problem}\noutcome: {outcome}\n---\n{BRIEF_BODY}")
}

/// A `|` block of `n` non-blank lines.
fn block(n: usize) -> String {
    let mut s = String::from("|");
    for i in 0..n {
        s.push_str(&format!("\n  line {} of the summary", i + 1));
    }
    s
}

#[test]
fn fc23_passes_a_brief_with_two_and_four_line_summaries() {
    for n in [2, 4] {
        let errs = findings("docs/briefs/BRIEF-widgets.md", &brief(&block(n), &block(n)));
        assert!(with_code(&errs, "FC23").is_empty(), "{n} lines: {errs:?}");
        assert_exits_clean(&errs);
    }
}

#[test]
fn fc23_reports_one_and_five_line_summaries_at_the_key() {
    for key in ["problem", "outcome"] {
        for n in [1, 5] {
            let md = if key == "problem" {
                brief(&block(n), TWO_LINES)
            } else {
                brief(TWO_LINES, &block(n))
            };
            let errs = findings("docs/briefs/BRIEF-widgets.md", &md);
            let fc23 = with_code(&errs, "FC23");
            assert_eq!(fc23.len(), 1, "{key} at {n} lines: {errs:?}");
            // `problem:` is line 4; `outcome:` follows the problem's
            // two-line block, on line 7.
            let expected_line = if key == "problem" { 4 } else { 7 };
            assert_eq!(fc23[0].line, expected_line, "{key} at {n} lines");
            assert!(fc23[0].message.contains(&format!("'{key}'")));
            assert!(
                !fc23[0].message.contains("summary of"),
                "the message must not quote the value: {}",
                fc23[0].message
            );
            assert_exits_clean(&errs);
        }
    }
}

#[test]
fn fc23_skips_blank_lines_inside_the_block() {
    let four_with_blank = "|\n  one\n  two\n\n  three\n  four";
    let errs = findings(
        "docs/briefs/BRIEF-widgets.md",
        &brief(four_with_blank, four_with_blank),
    );
    assert!(with_code(&errs, "FC23").is_empty(), "{errs:?}");
}

#[test]
fn fc23_counts_a_value_on_the_keys_own_line_as_one() {
    for key in ["problem", "outcome"] {
        let md = if key == "problem" {
            brief("Widgets are hard to find.", TWO_LINES)
        } else {
            brief(TWO_LINES, "A maintainer finds a widget.")
        };
        let errs = findings("docs/briefs/BRIEF-widgets.md", &md);
        let fc23 = with_code(&errs, "FC23");
        assert_eq!(fc23.len(), 1, "{key}: {errs:?}");
        assert!(fc23[0].message.contains("spans 1 non-blank line;"));
        assert_exits_clean(&errs);
    }
}

#[test]
fn fc23_counts_a_folded_block_as_written() {
    // A `>` block parses to one line; the author wrote three.
    let folded =
        ">\n  Widgets are hard to find today,\n  and a maintainer gives up\n  before finding one.";
    let errs = findings("docs/briefs/BRIEF-widgets.md", &brief(folded, folded));
    assert!(with_code(&errs, "FC23").is_empty(), "{errs:?}");
    // Chomping indicators and a trailing comment are headers, not values.
    let chomped = ">- # summary\n  one\n  two";
    let errs = findings(
        "docs/briefs/BRIEF-widgets.md",
        &brief(chomped, "|+\n  one\n  two"),
    );
    assert!(with_code(&errs, "FC23").is_empty(), "{errs:?}");
}

#[test]
fn fc23_leaves_an_absent_key_to_fc01() {
    let md =
        format!("---\nschema: brief/v1\nstatus: Draft\noutcome: {TWO_LINES}\n---\n{BRIEF_BODY}");
    let errs = findings("docs/briefs/BRIEF-widgets.md", &md);
    assert!(with_code(&errs, "FC23").is_empty(), "{errs:?}");
    assert_eq!(with_code(&errs, "FC01").len(), 1, "{errs:?}");
}

// --- DESIGN --------------------------------------------------------------

/// A DESIGN body with every required section. `options` is the body of
/// `## Considered Options`.
fn design_body(options: &str) -> String {
    format!(
        "\n# DESIGN: widgets\n\n## Status\n\nProposed\n\n\
         ## Context and Problem Statement\n\nWidgets are hard to find.\n\n\
         ## Decision Drivers\n\nSearch must be fast.\n\n\
         ## Considered Options\n\n{options}\n\n\
         ## Decision Outcome\n\nAn index.\n\n\
         ## Solution Architecture\n\nOne index file.\n\n\
         ## Implementation Approach\n\nOne change.\n\n\
         ## Security Considerations\n\nNone apply: the index holds names only.\n\n\
         ## Consequences\n\nSearch gets faster.\n"
    )
}

const ONE_OPTION: &str = "### Decision 1: the index\n\nResolved inline.\n\nAn index file.";

fn design(frontmatter: &str, options: &str) -> String {
    format!("---\n{frontmatter}---\n{}", design_body(options))
}

const CANONICAL: &str =
    "schema: design/v1\nstatus: Proposed\nproblem: |\n  Widgets are hard to find.\n\
    decision: |\n  An index.\nrationale: |\n  Fast to read.\n";

#[test]
fn fc24_passes_the_listed_order() {
    let fm = format!(
        "{CANONICAL}upstream: acme/widgets:docs/prds/PRD-widgets.md\nspawned_from:\n  issue: 7\n  repo: acme/widgets\n  parent_design: docs/designs/DESIGN-parent.md\n\
         motivating_context: |\n  A request.\nuser_visible_surface: false\ndecision_provenance: inline-resolved\n"
    );
    let errs = findings("docs/designs/DESIGN-widgets.md", &design(&fm, ONE_OPTION));
    assert!(with_code(&errs, "FC24").is_empty(), "{errs:?}");
}

#[test]
fn fc24_ignores_an_unlisted_key() {
    let fm = "schema: design/v1\nstatus: Proposed\nsuperseded_by: docs/designs/DESIGN-next.md\nproblem: |\n  p\n\
              decision: |\n  d\nrationale: |\n  r\n";
    let errs = findings("docs/designs/DESIGN-widgets.md", &design(fm, ONE_OPTION));
    assert!(with_code(&errs, "FC24").is_empty(), "{errs:?}");
}

#[test]
fn fc24_reports_upstream_before_problem_once_at_the_upstream_line() {
    let fm =
        "schema: design/v1\nstatus: Proposed\nupstream: acme/widgets:docs/prds/PRD-widgets.md\n\
              problem: |\n  p\ndecision: |\n  d\nrationale: |\n  r\n";
    let errs = findings("docs/designs/DESIGN-widgets.md", &design(fm, ONE_OPTION));
    let fc24 = with_code(&errs, "FC24");
    assert_eq!(fc24.len(), 1, "{errs:?}");
    assert_eq!(fc24[0].line, 4, "the upstream: line");
    assert!(
        fc24[0].message.contains("'upstream'"),
        "{}",
        fc24[0].message
    );
    assert_exits_clean(&errs);
}

#[test]
fn fc24_reports_a_late_status_at_the_first_displaced_key() {
    let fm = "schema: design/v1\nproblem: |\n  p\ndecision: |\n  d\nrationale: |\n  r\nstatus: Proposed\n";
    let errs = findings("docs/designs/DESIGN-widgets.md", &design(fm, ONE_OPTION));
    let fc24 = with_code(&errs, "FC24");
    assert_eq!(fc24.len(), 1, "{errs:?}");
    assert_eq!(fc24[0].line, 3, "problem: sits where status: belongs");
}

fn provenance_design(options: &str) -> String {
    design(
        &format!("{CANONICAL}decision_provenance: inline-resolved\n"),
        options,
    )
}

#[test]
fn fc25_reports_only_the_entry_without_an_opener() {
    let options = "### Decision 1: the index\n\nResolved inline.\n\nText.\n\n\
                   ### Decision 2: the format\n\nThe format is JSON.";
    let md = provenance_design(options);
    let errs = findings("docs/designs/DESIGN-widgets.md", &md);
    let fc25 = with_code(&errs, "FC25");
    assert_eq!(fc25.len(), 1, "{errs:?}");
    let heading_line = md
        .lines()
        .position(|l| l == "### Decision 2: the format")
        .unwrap()
        + 1;
    assert_eq!(fc25[0].line, heading_line);
    assert!(fc25[0].message.contains("entry 2"), "{}", fc25[0].message);
    assert!(!fc25[0].message.contains("JSON"), "no document text quoted");
    assert_exits_clean(&errs);
}

#[test]
fn fc25_passes_both_openers_with_and_without_leading_spaces() {
    let options = "### Decision 1: the index\n\nResolved inline.\n\nText.\n\n\
                   ### Decision 2: the format\n\n   Delegated to /decision. See the record.";
    let errs = findings(
        "docs/designs/DESIGN-widgets.md",
        &provenance_design(options),
    );
    assert!(with_code(&errs, "FC25").is_empty(), "{errs:?}");
}

#[test]
fn fc25_is_case_sensitive() {
    let options = "### Decision 1: the index\n\nresolved inline.";
    let errs = findings(
        "docs/designs/DESIGN-widgets.md",
        &provenance_design(options),
    );
    assert_eq!(with_code(&errs, "FC25").len(), 1, "{errs:?}");
}

#[test]
fn fc25_reports_an_entry_with_no_body() {
    let options = "### Decision 1: the index\n\n### Decision 2: the format\n\nResolved inline.";
    let errs = findings(
        "docs/designs/DESIGN-widgets.md",
        &provenance_design(options),
    );
    let fc25 = with_code(&errs, "FC25");
    assert_eq!(fc25.len(), 1, "{errs:?}");
    assert!(fc25[0].message.contains("entry 1 has no body"));
    // The last entry with nothing before the next `##` fails the same way.
    let options = "### Decision 1: the index";
    let errs = findings(
        "docs/designs/DESIGN-widgets.md",
        &provenance_design(options),
    );
    assert_eq!(with_code(&errs, "FC25").len(), 1, "{errs:?}");
}

#[test]
fn fc25_skips_headings_in_code_blocks_and_after_the_section() {
    let options = "### Decision 1: the index\n\nResolved inline.\n\n\
                   ```markdown\n### Not an entry\n\nno opener\n```\n\n\
                   ~~~\n### Nor this\n~~~";
    let md = provenance_design(options).replace(
        "## Decision Outcome\n\nAn index.",
        "## Decision Outcome\n\nAn index.\n\n### Detail\n\nNo opener here.",
    );
    let errs = findings("docs/designs/DESIGN-widgets.md", &md);
    assert!(with_code(&errs, "FC25").is_empty(), "{errs:?}");
}

#[test]
fn fc25_does_not_run_without_decision_provenance() {
    let options = "### Decision 1: the index\n\nThe index.";
    let errs = findings(
        "docs/designs/DESIGN-widgets.md",
        &design(CANONICAL, options),
    );
    assert!(with_code(&errs, "FC25").is_empty(), "{errs:?}");
}

// --- Codes, levels and the envelope ---------------------------------------

#[test]
fn the_three_codes_are_selectable_notices() {
    for code in ["FC23", "FC24", "FC25"] {
        assert!(is_known_check_code(code), "--check {code} must be accepted");
        for posture in [ReviewPosture::Draft, ReviewPosture::Ready] {
            assert_eq!(effective_severity(code, posture), Severity::Notice);
        }
    }
}

/// A document of every other format, written with a one-line `problem:`,
/// `upstream:` before `problem:` and a `decision_provenance` key over an
/// opener-less Considered Options entry, never gets FC23, FC24 or FC25.
#[test]
fn other_formats_never_produce_the_three_codes() {
    let fm_tail = "upstream: acme/widgets:docs/x.md\nproblem: One line.\noutcome: One line.\n\
                   decision_provenance: inline-resolved\n";
    let body = "\n## Status\n\nDraft\n\n## Considered Options\n\n### One\n\nNo opener.\n";
    for (path, schema, status) in [
        ("docs/prds/PRD-w.md", "prd/v1", "Draft"),
        ("docs/plans/PLAN-w.md", "plan/v1", "Draft"),
        ("docs/plans/PLAN-w2.md", "plan/v2", "Draft"),
        ("docs/roadmaps/ROADMAP-w.md", "roadmap/v1", "Draft"),
        ("docs/strategies/STRATEGY-w.md", "strategy/v1", "Draft"),
        ("docs/visions/VISION-w.md", "vision/v1", "Draft"),
    ] {
        let md = format!("---\nschema: {schema}\nstatus: {status}\n{fm_tail}---\n{body}");
        let errs = findings(path, &md);
        for code in ["FC23", "FC24", "FC25"] {
            assert!(
                with_code(&errs, code).is_empty(),
                "{schema} produced {code}: {errs:?}"
            );
        }
    }
}

#[test]
fn each_finding_reaches_the_json_envelope_with_file_line_and_code() {
    let mut errs = findings(
        "docs/briefs/BRIEF-widgets.md",
        &brief("One line.", TWO_LINES),
    );
    errs.extend(findings(
        "docs/designs/DESIGN-widgets.md",
        &provenance_design("### Decision 1: the index\n\nNo opener."),
    ));
    let fm =
        "schema: design/v1\nupstream: acme/widgets:docs/prds/PRD-widgets.md\nstatus: Proposed\n\
              problem: |\n  p\ndecision: |\n  d\nrationale: |\n  r\n";
    errs.extend(findings(
        "docs/designs/DESIGN-order.md",
        &design(fm, ONE_OPTION),
    ));
    let ours: Vec<ValidationError> = errs
        .into_iter()
        .filter(|e| ["FC23", "FC24", "FC25"].contains(&e.code.as_str()))
        .collect();
    assert_eq!(ours.len(), 3, "{ours:?}");
    let json = render_json(&ours, "clean", ReviewPosture::Ready);
    for e in &ours {
        assert!(
            json.contains(&format!("\"code\": \"{}\"", e.code)),
            "{json}"
        );
        assert!(
            json.contains(&format!("\"file\": \"{}\"", e.file)),
            "{json}"
        );
        assert!(json.contains(&format!("\"line\": {}", e.line)), "{json}");
        assert!(e.line > 0);
    }
    assert!(json.contains("\"severity\": \"notice\""), "{json}");
}

// --- The design skill's templates -----------------------------------------

/// The repository root, two levels above this crate.
fn repo_root() -> &'static Path {
    Path::new(env!("CARGO_MANIFEST_DIR"))
        .parent()
        .and_then(Path::parent)
        .expect("crate sits two levels below the repository root")
}

/// The frontmatter lines of the first fenced block in `file` that opens with
/// `---`, with each line's trailing `# ...` instruction comment removed.
fn template_frontmatter(file: &str) -> Vec<String> {
    let text = std::fs::read_to_string(repo_root().join(file))
        .unwrap_or_else(|e| panic!("read {file}: {e}"));
    let mut lines = text.lines();
    while let Some(line) = lines.next() {
        if line.starts_with("```") {
            let mut block = lines.clone();
            if block.next() == Some("---") {
                return block
                    .take_while(|l| *l != "---")
                    .map(|l| match l.find("   #") {
                        Some(i) => l[..i].trim_end().to_string(),
                        None => l.to_string(),
                    })
                    .collect();
            }
        }
    }
    panic!("{file} has no fenced frontmatter block");
}

/// A DESIGN written from the step 6.5 template (every optional key kept)
/// passes FC24, and so does each phase-0 skeleton as written: each writes
/// `schema: design/v1` first and its keys in FC24's order.
#[test]
fn a_design_written_from_the_skill_templates_passes_fc24() {
    for template in [
        "skills/design/references/phases/phase-6-final-review.md",
        "skills/design/references/phases/phase-0-setup-prd.md",
        "skills/design/references/phases/phase-0-setup-freeform.md",
    ] {
        let fm = template_frontmatter(template);
        assert_eq!(
            fm.first().map(String::as_str),
            Some("schema: design/v1"),
            "{template}"
        );
        let md = design(&(fm.join("\n") + "\n"), ONE_OPTION);
        let errs = findings("docs/designs/DESIGN-widgets.md", &md);
        assert!(with_code(&errs, "FC24").is_empty(), "{template}: {errs:?}");
        assert!(with_code(&errs, "FC25").is_empty(), "{template}: {errs:?}");
    }
}
