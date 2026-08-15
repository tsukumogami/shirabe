//! `shirabe plan outlines` -- emit a PLAN's parsed `## Issue Outlines`
//! section as JSON.
//!
//! The out-of-process face of the single walk in `shirabe-validate`. Its
//! reason to exist is that `skills/plan/scripts/plan-to-tasks.sh` used to
//! carry its own bash re-implementation of that parse, and the two drifted:
//! a PLAN could validate clean and then extract to a task graph with none of
//! its declared edges. See
//! `docs/designs/DESIGN-issue-outlines-one-parser.md`.
//!
//! This subcommand reads and never writes. It creates no file, modifies
//! none, and follows no reference out of the document, which is what keeps
//! it on the reading side of the repo's CLI-surface rule: authoring an
//! artifact body belongs to a skill, and reporting what an existing document
//! says is deterministic parsing and feedback, which the same rule places in
//! the CLI next to `validate` and `slug-prefix-detect`.
//!
//! Parsing is not judgment. A document full of unresolvable dependencies
//! still exits 0 and reports them in the envelope, because the two consumers
//! refuse at different severities: validation errors on it (FC17), the
//! extractor refuses to emit a task set. Deciding here would make this a
//! third opinion rather than the one parser.

use std::process::ExitCode;

use shirabe_validate::{parse_doc, parse_issue_outlines, ParseError};

/// The envelope's schema identifier.
///
/// A consumer that does not recognize this value must refuse rather than
/// read fields positionally: an installed binary and a checked-out script
/// can skew, and the version is what makes that detectable instead of
/// silent.
pub const SCHEMA: &str = "shirabe-plan-outlines/v1";

#[derive(clap::Args)]
pub struct PlanArgs {
    #[command(subcommand)]
    pub command: PlanCommands,
}

#[derive(clap::Subcommand)]
pub enum PlanCommands {
    /// Parse a PLAN's `## Issue Outlines` section and write it to stdout as
    /// a `shirabe-plan-outlines/v1` JSON envelope. Read-only.
    Outlines(OutlinesArgs),
}

#[derive(clap::Args)]
pub struct OutlinesArgs {
    /// Path to the PLAN document to read.
    pub plan: String,
}

/// Exit codes, following the scheme `transition` and `finalize-chain`
/// already use: 0 parsed, 1 the input is not a readable PLAN, 3 I/O.
/// There is deliberately no 2 -- this command reports what a document says
/// and never renders a verdict on it.
const EXIT_TOOL_ERROR: u8 = 1;
const EXIT_IO: u8 = 3;

pub fn run(args: &OutlinesArgs) -> ExitCode {
    let doc = match parse_doc(&args.plan) {
        Ok(d) => d,
        Err(ParseError::Io(e)) => {
            eprintln!("[plan outlines] cannot read {}: {}", args.plan, e);
            return ExitCode::from(EXIT_IO);
        }
        Err(e) => {
            eprintln!("[plan outlines] cannot parse {}: {}", args.plan, e);
            return ExitCode::from(EXIT_TOOL_ERROR);
        }
    };

    let schema = doc.fields.get("schema").map(|f| f.value.trim().to_string());
    if schema.as_deref() != Some("plan/v1") {
        eprintln!(
            "[plan outlines] {} is not a PLAN document (expected 'schema: plan/v1', found {})",
            args.plan,
            schema
                .as_deref()
                .map(|s| format!("'{s}'"))
                .unwrap_or_else(|| "no schema field".to_string())
        );
        return ExitCode::from(EXIT_TOOL_ERROR);
    }

    let execution_mode = doc
        .fields
        .get("execution_mode")
        .map(|f| f.value.trim().to_string());

    print!("{}", render(&args.plan, execution_mode.as_deref(), &doc));
    ExitCode::SUCCESS
}

/// Render the envelope. Split from [`run`] so the shape is testable without
/// a process boundary.
fn render(path: &str, execution_mode: Option<&str>, doc: &shirabe_validate::Doc) -> String {
    let section = parse_issue_outlines(doc);

    let outlines: Vec<String> = section
        .blocks
        .iter()
        .map(|b| {
            format!(
                concat!(
                    "    {{\n",
                    "      \"number\": {number},\n",
                    "      \"title\": {title},\n",
                    "      \"key\": {key},\n",
                    "      \"line\": {line},\n",
                    "      \"goal_declared\": {goal},\n",
                    "      \"acceptance_criteria_declared\": {acd},\n",
                    "      \"dependencies_declared\": {dd},\n",
                    "      \"dependencies_none\": {dn},\n",
                    "      \"waits_on\": [{waits}],\n",
                    "      \"unresolved_dependencies\": [{unresolved}],\n",
                    "      \"type\": {issue_type},\n",
                    "      \"files\": [{files}]\n",
                    "    }}"
                ),
                number = b.number,
                title = json_string(&b.title),
                key = json_string(&b.key),
                line = b.line,
                goal = b.goal_declared,
                acd = b.acceptance_criteria_declared,
                dd = b.dependencies_declared,
                dn = b.dependencies_none,
                waits = b
                    .waits_on
                    .iter()
                    .map(|n| n.to_string())
                    .collect::<Vec<_>>()
                    .join(", "),
                unresolved = b
                    .unresolved_dependencies
                    .iter()
                    .map(|t| json_string(t))
                    .collect::<Vec<_>>()
                    .join(", "),
                issue_type = b
                    .issue_type
                    .as_deref()
                    .map(json_string)
                    .unwrap_or_else(|| "null".to_string()),
                files = b
                    .files
                    .iter()
                    .map(|f| json_string(f))
                    .collect::<Vec<_>>()
                    .join(", "),
            )
        })
        .collect();

    let headings: Vec<String> = section
        .nonconforming_headings
        .iter()
        .map(|h| {
            format!(
                "    {{ \"text\": {}, \"line\": {} }}",
                json_string(&h.text),
                h.line
            )
        })
        .collect();

    format!(
        "{{\n  \"schema\": {schema},\n  \"path\": {path},\n  \"execution_mode\": {mode},\n  \"outlines\": [{outlines}],\n  \"nonconforming_headings\": [{headings}]\n}}\n",
        schema = json_string(SCHEMA),
        path = json_string(path),
        mode = execution_mode
            .map(json_string)
            .unwrap_or_else(|| "null".to_string()),
        outlines = wrap_list(&outlines),
        headings = wrap_list(&headings),
    )
}

/// Render a list body: empty stays `[]`, non-empty gets newlines so the
/// envelope is readable when a human dumps it.
fn wrap_list(items: &[String]) -> String {
    if items.is_empty() {
        String::new()
    } else {
        format!("\n{}\n  ", items.join(",\n"))
    }
}

/// Serialize a string as a JSON string literal.
///
/// Hand-rolled because the crate has no JSON dependency and the other
/// emitters here do the same. Document-derived text reaches this — an
/// outline title is whatever the author typed — so the escaping covers the
/// full set RFC 8259 requires, including the control characters below
/// 0x20 that a naive quote-and-backslash pass would emit raw and produce
/// invalid JSON from.
fn json_string(s: &str) -> String {
    let mut out = String::with_capacity(s.len() + 2);
    out.push('"');
    for c in s.chars() {
        match c {
            '"' => out.push_str("\\\""),
            '\\' => out.push_str("\\\\"),
            '\n' => out.push_str("\\n"),
            '\r' => out.push_str("\\r"),
            '\t' => out.push_str("\\t"),
            '\u{08}' => out.push_str("\\b"),
            '\u{0c}' => out.push_str("\\f"),
            c if (c as u32) < 0x20 => out.push_str(&format!("\\u{:04x}", c as u32)),
            c => out.push(c),
        }
    }
    out.push('"');
    out
}

#[cfg(test)]
mod tests {
    use super::*;
    use shirabe_validate::parse_doc_bytes;

    fn plan(body: &str) -> shirabe_validate::Doc {
        let md = format!(
            "---\nschema: plan/v1\nstatus: Active\nexecution_mode: single-pr\nmilestone: \"x\"\nissue_count: 1\n---\n\n# PLAN: x\n\n## Status\n\nActive\n\n{body}\n"
        );
        parse_doc_bytes("docs/plans/PLAN-x.md", md.as_bytes()).expect("fixture parses")
    }

    #[test]
    fn envelope_names_its_schema_and_path() {
        let doc = plan("## Issue Outlines\n\n### Issue 1: a\n\n**Dependencies**: None\n");
        let out = render("docs/plans/PLAN-x.md", Some("single-pr"), &doc);
        assert!(out.contains("\"schema\": \"shirabe-plan-outlines/v1\""));
        assert!(out.contains("\"path\": \"docs/plans/PLAN-x.md\""));
        assert!(out.contains("\"execution_mode\": \"single-pr\""));
    }

    #[test]
    fn envelope_carries_numbers_titles_and_resolved_edges() {
        let doc = plan(
            "## Issue Outlines\n\n### Issue 1: a\n\n**Dependencies**: None\n\n### Issue 2: b\n\n**Dependencies**: Blocked by <<ISSUE:1>>\n",
        );
        let out = render("docs/plans/PLAN-x.md", Some("single-pr"), &doc);
        assert!(out.contains("\"number\": 2"));
        assert!(out.contains("\"title\": \"b\""));
        assert!(out.contains("\"waits_on\": [1]"));
    }

    #[test]
    fn envelope_reports_unresolved_dependencies_without_refusing() {
        // Refusing is the consumer's call; this command reports.
        let doc = plan(
            "## Issue Outlines\n\n### Issue 1: a\n\n**Dependencies**: None\n\n### Issue 2: b\n\n**Dependencies**: 3\n",
        );
        let out = render("docs/plans/PLAN-x.md", Some("single-pr"), &doc);
        assert!(out.contains("\"unresolved_dependencies\": [\"3\"]"));
    }

    #[test]
    fn envelope_reports_nonconforming_headings() {
        let doc = plan("## Issue Outlines\n\n### 4. not an outline\n");
        let out = render("docs/plans/PLAN-x.md", Some("single-pr"), &doc);
        assert!(out.contains("\"outlines\": []"));
        assert!(out.contains("\"text\": \"4. not an outline\""));
    }

    #[test]
    fn envelope_is_empty_but_well_formed_when_the_section_is_absent() {
        let doc = plan("## Implementation Sequence\n\nnone\n");
        let out = render("docs/plans/PLAN-x.md", Some("multi-pr"), &doc);
        assert!(out.contains("\"outlines\": []"));
        assert!(out.contains("\"nonconforming_headings\": []"));
    }

    #[test]
    fn envelope_carries_type_and_files() {
        let doc = plan(
            "## Issue Outlines\n\n### Issue 1: a\n\n**Dependencies**: None\n\n**Type**: docs\n**Files**: `a/b.rs`\n",
        );
        let out = render("docs/plans/PLAN-x.md", Some("single-pr"), &doc);
        assert!(out.contains("\"type\": \"docs\""));
        assert!(out.contains("\"files\": [\"a/b.rs\"]"));
    }

    #[test]
    fn a_title_carrying_json_metacharacters_stays_valid_json() {
        // Titles are author text and reach the envelope verbatim.
        let doc = plan(
            "## Issue Outlines\n\n### Issue 1: feat: add \"quoted\" \\ thing\n\n**Dependencies**: None\n",
        );
        let out = render("docs/plans/PLAN-x.md", Some("single-pr"), &doc);
        assert!(out.contains(r#""title": "feat: add \"quoted\" \\ thing""#));
    }

    #[test]
    fn json_string_escapes_control_characters() {
        assert_eq!(json_string("a\u{01}b"), "\"a\\u0001b\"");
        assert_eq!(json_string("tab\there"), "\"tab\\there\"");
    }
}
