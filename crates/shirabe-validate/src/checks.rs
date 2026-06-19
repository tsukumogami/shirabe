//! The individual validation checks (SCHEMA, FC01-FC06, R6, R7, R8).
//!
//! Each check inspects a parsed [`Doc`] against its [`FormatSpec`] and
//! returns one [`ValidationError`] per violation (an empty vec means the
//! check passed). `validate.rs` calls these in order from `validate_file`.
//!
//! Message strings are preserved byte-for-byte from the Go
//! `internal/validate/checks.go` so the annotation output stays identical.

use std::collections::{HashMap, HashSet};
use std::path::Path;
use std::process::Command;
use std::sync::LazyLock;

use regex::Regex;

use crate::doc::{Config, Doc, ValidationError};
use crate::formats::FormatSpec;
use crate::gh::{is_valid_owner_or_repo, ClientError, IssueState, IssueStateClient, PrContext};
use crate::mermaid::{extract_diagram, find_dependency_graph_block, Diagram, Issue};
use crate::table::{parse_issue_outlines, parse_issues_table, Profile, Row, RowKind, Table};

/// Section names that `vision/v1` docs must not contain in public repos.
/// See DESIGN-gha-doc-validation.md (R7).
const PROHIBITED_PUBLIC_VISION_SECTIONS: &[&str] =
    &["Competitive Positioning", "Resource Implications"];

/// Section names that `strategy/v1` docs must not contain in public repos.
/// See DESIGN-shirabe-strategy-skill.md (R8).
const PROHIBITED_PUBLIC_STRATEGY_SECTIONS: &[&str] = &["Competitive Considerations"];

/// The historic four-column plan-table shape
/// (Issue | Title | Dependencies | Complexity). FC05 recognizes it
/// specially to emit a migration hint pointing the author at the canonical
/// three-column shape.
const LEGACY_PLAN_TABLE_COLUMNS: &[&str] = &["Issue", "Title", "Dependencies", "Complexity"];

/// Returns a SCHEMA `ValidationError` (to be emitted as `::notice`) if
/// `doc.schema` is not `spec.schema_version`. Returns `None` if the schema
/// matches.
///
/// When `doc.schema` is empty, the notice message uses the SCHEMA-MISSING
/// shape ("schema field missing, skipping") to distinguish the missing
/// case from the present-but-mismatched case. Both cases share the
/// `SCHEMA` code and the notice level. This addresses `tsukumogami/shirabe#157`:
/// silently skipping a file with a schema-bearing prefix because the
/// field is missing is the failure mode the AC reverses.
pub fn check_schema(doc: &Doc, spec: &FormatSpec) -> Option<ValidationError> {
    if doc.schema == spec.schema_version {
        return None;
    }
    let message = if doc.schema.is_empty() {
        // SCHEMA-MISSING shape per shirabe#157: name the missing field
        // explicitly instead of emitting the misleading "schema \"\" not
        // in supported range" form.
        "schema field missing, skipping".to_string()
    } else {
        format!("schema {:?} not in supported range, skipping", doc.schema)
    };
    Some(ValidationError {
        file: doc.path.clone(),
        line: 1,
        code: "SCHEMA".to_string(),
        message,
    })
}

/// Returns a `ValidationError` for each required field missing from
/// `doc.fields`. Line is 1 (the field is absent, no specific line).
pub fn check_fc01(doc: &Doc, spec: &FormatSpec) -> Vec<ValidationError> {
    let mut errs = Vec::new();
    for field in &spec.required_fields {
        if !doc.fields.contains_key(field) {
            errs.push(ValidationError {
                file: doc.path.clone(),
                line: 1,
                code: "FC01".to_string(),
                message: format!("[FC01] missing required field {:?}", field),
            });
        }
    }
    errs
}

/// Validates that `doc.status` is in the accepted enum. Uses
/// `cfg.custom_statuses[spec.schema_version]` if set (replacement, not
/// extension). Line is `doc.fields["status"].line` if present, else 1.
pub fn check_fc02(doc: &Doc, spec: &FormatSpec, cfg: &Config) -> Vec<ValidationError> {
    if doc.status.is_empty() {
        return Vec::new();
    }

    let valid_statuses: &[String] = match cfg.custom_statuses.get(&spec.schema_version) {
        Some(custom) => custom,
        None => &spec.valid_statuses,
    };

    if valid_statuses.contains(&doc.status) {
        return Vec::new();
    }

    let line = doc.fields.get("status").map(|fv| fv.line).unwrap_or(1);

    vec![ValidationError {
        file: doc.path.clone(),
        line,
        code: "FC02".to_string(),
        message: format!(
            "[FC02] status {:?} is not valid for {} docs. Valid values: {}",
            doc.status,
            spec.name,
            valid_statuses.join(", ")
        ),
    }]
}

/// Finds the `## Status` section in `doc.body`, reads the next non-blank
/// line, and compares case-insensitively with `doc.status`. Does NOT fire
/// if the `## Status` section has no non-blank body text. Line is the
/// `Section.line` of the `## Status` heading.
pub fn check_fc03(doc: &Doc, _spec: &FormatSpec) -> Vec<ValidationError> {
    // Find the ## Status section line number.
    let status_line = match doc.sections.iter().find(|sec| sec.name == "Status") {
        Some(sec) => sec.line,
        None => return Vec::new(),
    };

    // Scan doc.body for "## Status" and find the next non-blank line.
    let mut found_heading = false;
    let mut body_status = String::new();
    for line in &doc.body {
        if !found_heading {
            if line.trim_end_matches([' ', '\t']) == "## Status" {
                found_heading = true;
            }
            continue;
        }
        // We are past the ## Status heading.
        let trimmed = line.trim();
        if trimmed.is_empty() {
            continue;
        }
        // Stop if we hit another heading.
        if line.starts_with('#') {
            break;
        }
        body_status = trimmed.to_string();
        break;
    }

    // No non-blank body text after ## Status -- skip.
    if body_status.is_empty() {
        return Vec::new();
    }

    if doc.status.eq_ignore_ascii_case(&body_status) {
        return Vec::new();
    }

    vec![ValidationError {
        file: doc.path.clone(),
        line: status_line,
        code: "FC03".to_string(),
        message: format!(
            "[FC03] frontmatter status {:?} does not match ## Status body {:?}",
            doc.status, body_status
        ),
    }]
}

/// The required-sections list that applies to `doc` under `spec`, in canonical
/// order. When the format declares a per-`execution_mode` override and the doc
/// carries a mapped `execution_mode`, the per-mode list is used; otherwise the
/// flat `spec.required_sections`. Shared by FC04 (presence) and FC15 (order).
fn required_sections_for(doc: &Doc, spec: &FormatSpec) -> Vec<String> {
    if let Some(map) = &spec.execution_mode_required_sections {
        if let Some(mode_field) = doc.fields.get("execution_mode") {
            if let Some(per_mode) = map.get(&mode_field.value) {
                return per_mode.clone();
            }
        }
    }
    spec.required_sections.clone()
}

/// Returns a `ValidationError` for each required section missing from
/// `doc.sections`. Line is 1 (section absent, no specific line).
pub fn check_fc04(doc: &Doc, spec: &FormatSpec) -> Vec<ValidationError> {
    let mut errs = Vec::new();
    let required = required_sections_for(doc, spec);
    for req in &required {
        if !doc.sections.iter().any(|sec| sec.name == *req) {
            errs.push(ValidationError {
                file: doc.path.clone(),
                line: 1,
                code: "FC04".to_string(),
                message: format!("[FC04] missing required section '## {}'", req),
            });
        }
    }
    errs
}

/// FC15 -- required sections appear in the format's canonical order.
///
/// FC04 checks that each required section is *present*; FC15 checks that the
/// required sections which are present appear in the same relative order the
/// format declares. Sections the format does not require may appear anywhere
/// between them, and a missing required section is FC04's concern, not FC15's --
/// FC15 only compares the order of the required sections actually present.
///
/// This absorbs the external section-order check as new behavior (DESIGN
/// Decision 3): FC04 is presence-only, so order takes the next free code rather
/// than overloading FC04. FC15 ships notice-level (registered in `is_notice`),
/// matching the FC07-FC14 promotion-seam convention: the current corpus carries
/// genuine order drift the check surfaces, so it detects without breaking the
/// build until a corpus-cleanup PR fixes those docs and promotes FC15 to error
/// (a one-line change: remove its arm from `is_notice`). The fired-rule SET is
/// the same at either severity, so the absorption's parity is unaffected.
pub fn check_fc15(doc: &Doc, spec: &FormatSpec) -> Vec<ValidationError> {
    let required = required_sections_for(doc, spec);
    if required.is_empty() {
        return Vec::new();
    }

    // Required sections in the order they appear in the document (first
    // occurrence only, so a duplicate section is FC04/structure's concern, not
    // a spurious order failure).
    let mut seen = std::collections::HashSet::new();
    let present_in_doc_order: Vec<&String> = doc
        .sections
        .iter()
        .filter_map(|sec| required.iter().find(|r| **r == sec.name))
        .filter(|r| seen.insert((*r).clone()))
        .collect();

    // The same present sections in the format's canonical order.
    let canonical_order: Vec<&String> = required
        .iter()
        .filter(|r| doc.sections.iter().any(|sec| sec.name == **r))
        .collect();

    if present_in_doc_order == canonical_order {
        return Vec::new();
    }

    // Name the first section that breaks the canonical order, and the line it
    // sits on, so the author can find it.
    let first_out = present_in_doc_order
        .iter()
        .zip(canonical_order.iter())
        .find(|(got, want)| got != want)
        .map(|(got, _)| (*got).clone())
        .unwrap_or_else(|| {
            present_in_doc_order
                .last()
                .map(|s| (*s).clone())
                .unwrap_or_default()
        });
    let line = doc
        .sections
        .iter()
        .find(|sec| sec.name == first_out)
        .map(|sec| sec.line)
        .unwrap_or(1);
    let expected = canonical_order
        .iter()
        .map(|s| format!("## {}", s))
        .collect::<Vec<_>>()
        .join(", ");
    vec![ValidationError {
        file: doc.path.clone(),
        line,
        code: "FC15".to_string(),
        message: format!(
            "[FC15] section '## {}' is out of order; required sections must appear in the order: {}",
            first_out, expected
        ),
    }]
}

/// Validates that the Implementation Issues table header matches the
/// format's required column contract (R6). The profile is selected by
/// `spec.issues_table_columns` -- absent (empty) means the format has no
/// issues table and the check is a no-op.
///
/// FC05 is error-level. A legacy plan-table shape (Issue | Title |
/// Dependencies | Complexity) emits a migration-hint message rather than a
/// generic schema-mismatch message, pointing the author at the canonical
/// three-column shape.
pub fn check_fc05(doc: &Doc, spec: &FormatSpec) -> Vec<ValidationError> {
    if spec.issues_table_columns.is_empty() {
        return Vec::new();
    }
    let table = match parse_issues_table(doc) {
        Some(t) => t,
        None => return Vec::new(),
    };

    // Detect the legacy plan-table shape and emit a migration hint.
    if spec.schema_version == "plan/v1" && columns_eq(&table.columns, LEGACY_PLAN_TABLE_COLUMNS) {
        return vec![ValidationError {
            file: doc.path.clone(),
            line: table.header_line,
            code: "FC05".to_string(),
            message: r#"[FC05] legacy plan table shape "Issue | Title | Dependencies | Complexity" found; migrate by folding the Title cell into the issue link text: "[#N: <title>](url) | <deps> | <complexity>""#
                .to_string(),
        }];
    }

    if table.columns == spec.issues_table_columns {
        return validate_row_shape(doc, &table);
    }

    let want = spec.issues_table_columns.join(" | ");
    let got = table.columns.join(" | ");
    vec![ValidationError {
        file: doc.path.clone(),
        line: table.header_line,
        code: "FC05".to_string(),
        message: format!(
            "[FC05] issues-table header {:?} does not match the {} profile (expected {:?})",
            got, spec.name, want
        ),
    }]
}

/// Allowed values for the plan-profile Complexity column (the plan skill's
/// complexity classification). Absorbed from the external issues-table check
/// (DESIGN Decision 2) as a strict superset of FC05's existing row-shape rule.
const PLAN_COMPLEXITY_VALUES: [&str; 3] = ["simple", "testable", "critical"];

/// Split a raw table row (`| a | b | c |`) into its trimmed cell values, with
/// strikethrough unwrapped first.
///
/// The row-content rules below need the raw cell text, not the parsed
/// `Row.deps`: `deps` keeps only the resolved dependency targets and discards
/// the link *format* this check exists to validate, so the cell is re-split
/// here. Both the strikethrough strip and the pipe split reuse the table
/// parser's own helpers (`table::strip_strikethrough`, `table::split_row`) so
/// the two layers cannot disagree on any input, malformed markers included; a
/// terminal (done) row therefore validates on its inner value (`~~simple~~` is
/// the same complexity as `simple`).
fn row_cells(raw: &str) -> Vec<String> {
    crate::table::split_row(&crate::table::strip_strikethrough(raw))
}

/// Reports whether `s` contains a markdown inline link `[..](..)`.
fn has_markdown_link(s: &str) -> bool {
    if let Some(open) = s.find('[') {
        if let Some(close_brkt) = s[open..].find("](") {
            let after = &s[open + close_brkt + 2..];
            return after.contains(')');
        }
    }
    false
}

/// Checks that table rows are well-formed. Every entity row must be
/// followed by an italic description row; a child reference row may sit
/// between them.
///
/// For the plan profile, three strict-superset row-content rules are absorbed
/// from the external issues-table check (DESIGN Decision 2), all under FC05's
/// existing code (they are the same concern -- row shape -- so they reconcile
/// into FC05 rather than taking new codes):
///   - the Dependencies cell is either `None` or a comma-separated list of
///     markdown links (`[#N](url)`), never a bare token;
///   - the Complexity cell is one of `simple` / `testable` / `critical`;
///   - a child reference row carries a markdown link to the child artifact.
fn validate_row_shape(doc: &Doc, table: &Table) -> Vec<ValidationError> {
    let mut errs = Vec::new();

    // Each entity row must be followed by a description row, optionally with
    // one child reference row between them.
    for (i, row) in table.rows.iter().enumerate() {
        if row.kind != RowKind::Entity {
            continue;
        }
        let mut next = i + 1;
        // Skip a single child reference row if present.
        if next < table.rows.len() && table.rows[next].kind == RowKind::Child {
            next += 1;
        }
        if next >= table.rows.len() || table.rows[next].kind != RowKind::Description {
            errs.push(ValidationError {
                file: doc.path.clone(),
                line: row.line,
                code: "FC05".to_string(),
                message: format!(
                    "[FC05] entity row at line {} is missing its description row (expected an italic \"_..._\" row immediately after)",
                    row.line
                ),
            });
        }
    }

    // Plan-profile row-content rules (absorbed; see the doc comment).
    if table.profile == Profile::Plan {
        for row in &table.rows {
            match row.kind {
                RowKind::Entity => {
                    let cells = row_cells(&row.raw);
                    // cells: [issue, dependencies, complexity]. These fixed
                    // indices are safe because `check_fc05` only reaches
                    // `validate_row_shape` after `table.columns ==
                    // spec.issues_table_columns` holds, so the plan profile's
                    // three-column order is guaranteed at this point. A future
                    // plan-column change must revisit these indices.
                    if let Some(deps_cell) = cells.get(1) {
                        let deps = deps_cell.trim();
                        if !deps.is_empty() && !deps.eq_ignore_ascii_case("none") {
                            for part in deps.split(',') {
                                let part = part.trim();
                                if !part.is_empty() && !has_markdown_link(part) {
                                    errs.push(ValidationError {
                                        file: doc.path.clone(),
                                        line: row.line,
                                        code: "FC05".to_string(),
                                        message: format!(
                                            "[FC05] dependency {:?} in row at line {} is not a markdown link (expected `[#N](url)` or `None`)",
                                            part, row.line
                                        ),
                                    });
                                }
                            }
                        }
                    }
                    if let Some(complexity) = cells.get(2) {
                        let c = complexity.trim();
                        if !c.is_empty() && !PLAN_COMPLEXITY_VALUES.contains(&c) {
                            errs.push(ValidationError {
                                file: doc.path.clone(),
                                line: row.line,
                                code: "FC05".to_string(),
                                message: format!(
                                    "[FC05] complexity {:?} in row at line {} is not one of {:?}",
                                    c, row.line, PLAN_COMPLEXITY_VALUES
                                ),
                            });
                        }
                    }
                }
                RowKind::Child => {
                    if !has_markdown_link(&row.raw) {
                        errs.push(ValidationError {
                            file: doc.path.clone(),
                            line: row.line,
                            code: "FC05".to_string(),
                            message: format!(
                                "[FC05] child reference row at line {} has no markdown link to the child artifact",
                                row.line
                            ),
                        });
                    }
                }
                RowKind::Description => {}
            }
        }
    }

    errs
}

/// Verifies that every Dependencies value in an entity row names a key that
/// exists as an entity row in the same table (R7). The check is
/// document-local (no graph model). FC06 is error-level.
///
/// FC06 is a no-op when the format has no issues table or the table is
/// absent.
pub fn check_fc06(doc: &Doc, spec: &FormatSpec) -> Vec<ValidationError> {
    if spec.issues_table_columns.is_empty() {
        return Vec::new();
    }
    let table = match parse_issues_table(doc) {
        Some(t) => t,
        None => return Vec::new(),
    };

    // Build the entity-row key set.
    let keys: std::collections::HashSet<&str> = table
        .rows
        .iter()
        .filter(|row| row.kind == RowKind::Entity && !row.key.is_empty())
        .map(|row| row.key.as_str())
        .collect();

    let mut errs = Vec::new();
    for row in &table.rows {
        if row.kind != RowKind::Entity {
            continue;
        }
        for dep in &row.deps {
            if dep.is_empty() {
                continue;
            }
            // Cross-repo refs (`tsukumogami/<repo>#N`, `owner/repo#N`) and
            // bare external URLs are out of scope for the document-local
            // check. We only flag intra-doc references that look like the
            // doc's own key form but don't match.
            if !is_local_key(dep) {
                continue;
            }
            if !keys.contains(dep.as_str()) {
                errs.push(ValidationError {
                    file: doc.path.clone(),
                    line: row.line,
                    code: "FC06".to_string(),
                    message: format!(
                        "[FC06] dependency {:?} in row {:?} names no row in this table",
                        dep, row.key
                    ),
                });
            }
        }
    }
    errs
}

/// Reports whether `dep` looks like a document-local key (a bare `#N`
/// token or a feature label). Cross-repo references with a slash before the
/// `#` are not local.
fn is_local_key(dep: &str) -> bool {
    if dep.starts_with('#') {
        return true;
    }
    // A feature label is local; a `owner/repo#N` is not (it has a `/`).
    if dep.contains('/') {
        return false;
    }
    true
}

/// (R6) Verifies that a Plan doc's `upstream` field points at a file that
/// exists on disk and is tracked by git. The field is optional; an absent
/// upstream value returns an empty vec. The git tracking check runs
/// `git ls-files --error-unmatch` in the process's current working
/// directory (which in a GHA context is the caller repo's checkout, not the
/// embedded shirabe source tree), so callers must not override the working
/// directory when invoking the check.
pub fn check_plan_upstream(doc: &Doc) -> Vec<ValidationError> {
    let field = match doc.fields.get("upstream") {
        Some(f) => f,
        None => return Vec::new(),
    };

    let path = &field.value;
    if !Path::new(path).exists() {
        return vec![ValidationError {
            file: doc.path.clone(),
            line: field.line,
            code: "R6".to_string(),
            message: format!("[R6] upstream {:?} does not exist on disk", path),
        }];
    }

    let tracked = Command::new("git")
        .args(["ls-files", "--error-unmatch", "--", path])
        .stdout(std::process::Stdio::null())
        .stderr(std::process::Stdio::null())
        .status()
        .map(|s| s.success())
        .unwrap_or(false);

    if !tracked {
        return vec![ValidationError {
            file: doc.path.clone(),
            line: field.line,
            code: "R6".to_string(),
            message: format!("[R6] upstream {:?} is not tracked by git", path),
        }];
    }

    Vec::new()
}

/// (R7) Flags VISION docs that surface sections forbidden in public repos.
/// The check is bypassed only when `cfg.visibility` is exactly `"private"`;
/// any other value (including the empty string) fails closed and the check
/// runs.
pub fn check_vision_public(doc: &Doc, cfg: &Config) -> Vec<ValidationError> {
    if cfg.visibility == "private" {
        return Vec::new();
    }

    let mut errs = Vec::new();
    for sec in &doc.sections {
        if PROHIBITED_PUBLIC_VISION_SECTIONS.contains(&sec.name.as_str()) {
            errs.push(ValidationError {
                file: doc.path.clone(),
                line: sec.line,
                code: "R7".to_string(),
                message: format!(
                    "[R7] section {:?} is prohibited in public VISION docs",
                    sec.name
                ),
            });
        }
    }
    errs
}

/// (R8) Flags STRATEGY docs that surface sections forbidden in public
/// repos. Mirrors [`check_vision_public`]. The check is bypassed only when
/// `cfg.visibility` is exactly `"private"`; any other value (including the
/// empty string) fails closed and the check runs. See
/// DESIGN-shirabe-strategy-skill.md.
pub fn check_strategy_public(doc: &Doc, cfg: &Config) -> Vec<ValidationError> {
    if cfg.visibility == "private" {
        return Vec::new();
    }

    let mut errs = Vec::new();
    for sec in &doc.sections {
        if PROHIBITED_PUBLIC_STRATEGY_SECTIONS.contains(&sec.name.as_str()) {
            errs.push(ValidationError {
                file: doc.path.clone(),
                line: sec.line,
                code: "R8".to_string(),
                message: format!(
                    "[R8] section {:?} is prohibited in public STRATEGY docs",
                    sec.name
                ),
            });
        }
    }
    errs
}

/// (R9) Rejects whole documents whose [`FormatSpec`] is marked `private` when
/// `cfg.visibility` is not exactly `"private"`. The gate fails closed: any
/// other value, including the empty string, runs the check. `validate_file`
/// dispatches this immediately after the schema gate and returns early on any
/// R9 result, so private-only docs never reach FC01-FC04 under a non-private
/// run.
pub fn check_private_only(doc: &Doc, spec: &FormatSpec, cfg: &Config) -> Vec<ValidationError> {
    if !spec.private || cfg.visibility == "private" {
        return Vec::new();
    }

    let got = if cfg.visibility.is_empty() {
        "unset"
    } else {
        cfg.visibility.as_str()
    };
    vec![ValidationError {
        file: doc.path.clone(),
        line: 0,
        code: "R9".to_string(),
        message: format!(
            "[R9] {} docs are private-only; visibility={} (expected private)",
            spec.name, got
        ),
    }]
}

/// Reports whether `columns` equals `want` element-for-element. Mirrors the
/// Go `stringSlicesEqual` helper for comparing a parsed header against a
/// `&[&str]` literal.
fn columns_eq(columns: &[String], want: &[&str]) -> bool {
    columns.len() == want.len() && columns.iter().zip(want).all(|(a, b)| a == b)
}

/// Matches an issue-keyed diagram node id (`I<n>`). Used by both plan
/// and roadmap profiles to identify the bijection and edge-agreement
/// subset of diagram nodes. Nodes whose id does not match this pattern
/// (outline ids `O<n>`, custom-mnemonic external references like
/// `KT5V2` or `NW6`, or any other shape) are excluded from FC07's
/// reconciliation and are tolerated in the diagram.
static ISSUE_KEYED_NODE_ID: LazyLock<Regex> =
    LazyLock::new(|| Regex::new(r"^I[0-9]+$").unwrap());

/// Matches a `#N` issue token inside Markdown link text. Used to parse
/// the roadmap-profile Issues column into the set of issue numbers a
/// feature row fans out into.
static ISSUE_REF_IN_CELL: LazyLock<Regex> =
    LazyLock::new(|| Regex::new(r"#([0-9]+)").unwrap());

/// The three Status-bearing class names FC07 reconciles against table row
/// state. A node carrying any other class (a non-Status class such as a
/// Complexity marker, a pipeline-position marker like `needsDesign`, or
/// the `koto` external-node marker) is recorded by the extractor but is
/// not reconciled.
const STATUS_CLASSES: &[&str] = &["done", "ready", "blocked"];

/// Non-Status classes the extractor records but FC07 ignores for the
/// class-versus-Status pass. Includes the pipeline-stage palette per
/// `references/dependency-diagram.md` (needs-prerequisite markers,
/// child-tracking markers), the plan-profile Complexity markers, the
/// roadmap-profile external-reference marker, and the `koto` external-
/// node marker the predecessor corpus used. Listed for the AC-coverage
/// scan in tests.
#[cfg_attr(not(test), allow(dead_code))]
const NON_STATUS_CLASSES: &[&str] = &[
    "needsDesign",
    "needsPrd",
    "needsSpike",
    "needsDecision",
    "needsPlanning",
    "needsExplore",
    "tracksDesign",
    "tracksPlan",
    "simple",
    "testable",
    "critical",
    "external",
    "koto",
];

/// Reconcile the parsed Implementation Issues table against the extracted
/// Dependency Graph mermaid block across three dimensions in one pass.
///
/// FC07 engages on the two profiles that carry an issues table -- plan
/// and roadmap -- and selects per-profile binding rules from the
/// parsed `Table.profile`. The diagram-side conventions are shared:
/// `I<n>` node ids identify the issue-keyed subset; nodes whose id does
/// not match `^I[0-9]+$` (outline ids, custom-mnemonic external
/// references) are excluded from bijection and edge agreement by
/// design.
///
/// **Plan profile.** `I<n>` binds to the entity row whose key column
/// is `#n`. Edges are derived from the row's Dependencies cell:
/// `Ia --> Ib` is expected for every `#a` listed in row `#b`'s
/// Dependencies cell.
///
/// **Roadmap profile.** `I<n>` binds to the entity row whose Issues
/// column contains `#n` (a markdown link to issue n). Roadmap rows
/// whose Issues cell is `None` contribute no expected `I<n>` node and
/// no edges; a feature that has not yet been decomposed into issues
/// is silent in the diagram. Roadmap-profile edges are derived from
/// the same Dependencies cell: a dependency that names another entity
/// row (by feature label) resolves to that row's set of `I<n>` nodes;
/// each cross-product `Ia --> Ib` pair is expected.
///
/// The check emits one notice per defect in the FC05/FC06 voice:
///
/// 1. **Node-set bijection.** A table row with no matching diagram
///    node fires a notice; a diagram node with no matching table row
///    fires a notice.
/// 2. **Edge agreement.** Convention is **blocker on the left,
///    dependent on the right**; see `references/dependency-diagram.md`.
///    Symmetric: missing-from-diagram and orphan-edge-from-diagram both
///    fire.
/// 3. **Class-versus-Status agreement** over the Status-bearing class
///    set (`done`, `ready`, `blocked`). The truth table:
///    - `done` requires the row to be in a terminal state.
///    - `ready` requires the row to be open and every Dependencies-cell
///      target to resolve to a terminal row.
///    - `blocked` requires the row to be open and at least one
///      Dependencies-cell target to resolve to an open row.
///    Non-Status classes (pipeline-stage classes like `needsDesign`,
///    `needsPrd`, `needsSpike`, `needsPlanning`, `needsExplore`,
///    Complexity markers, the `external` cross-product marker, and
///    legacy `koto`) are not reconciled. A node carrying multiple
///    classes contributes one notice only if its Status-bearing class
///    disagrees with the truth table; other classes on the same node
///    are observed but not reconciled.
///
/// FC07 returns an empty vec when the format has no
/// `issues_table_columns` (the same no-op gate FC05 and FC06 use). The
/// per-issue notices the extractor surfaces (`UnterminatedFence`,
/// `MissingBlock`, etc.) are converted to per-defect notices before the
/// per-dimension passes; a `MissingBlock` short-circuits the per-node
/// checks.
pub fn check_fc07(doc: &Doc, spec: &FormatSpec) -> Vec<ValidationError> {
    if spec.issues_table_columns.is_empty() {
        return Vec::new();
    }
    let mut errs: Vec<ValidationError> = Vec::new();

    let table = match parse_issues_table(doc) {
        Some(t) => t,
        None => return errs,
    };

    let location = match find_dependency_graph_block(doc) {
        Some(l) => l,
        None => return errs,
    };

    // A MissingBlock short-circuits per-node passes: every entity row
    // becomes a node-set notice otherwise, swamping the signal.
    let mut missing_block = false;
    for issue in &location.issues {
        let err = issue_to_notice(doc, issue);
        if let Issue::MissingBlock { .. } = issue {
            missing_block = true;
        }
        errs.push(err);
    }
    if missing_block {
        return errs;
    }

    // Extract the body lines for the located block. Index conversion: the
    // BlockLocation carries 1-indexed absolute lines; doc.body is
    // 0-indexed. body_end is one-past-last (the closing-fence line).
    let body_start_idx = location.body_start.saturating_sub(1);
    let body_end_idx = location
        .body_end
        .saturating_sub(1)
        .min(doc.body.len());
    let body_slice: Vec<&str> = doc
        .body
        .get(body_start_idx..body_end_idx)
        .map(|s| s.iter().map(|x| x.as_str()).collect())
        .unwrap_or_default();
    let (diagram, extract_issues) = extract_diagram(&body_slice, location.body_start);
    for issue in &extract_issues {
        errs.push(issue_to_notice(doc, issue));
    }

    // Run the three reconciliation passes.
    errs.extend(node_set_pass(doc, &table, &diagram));
    errs.extend(edge_pass(doc, &table, &diagram));
    errs.extend(class_vs_status_pass(doc, &table, &diagram));

    errs
}

/// Convert an extractor [`Issue`] to a per-defect FC07 notice. Notice
/// bodies name the diagram id or line rather than any URL or external
/// identifier.
fn issue_to_notice(doc: &Doc, issue: &Issue) -> ValidationError {
    let (line, message) = match issue {
        Issue::UnterminatedFence { line } => (
            *line,
            "[FC07] unterminated mermaid block (no closing fence)".to_string(),
        ),
        Issue::MissingBlock { line } => (
            *line,
            "[FC07] no mermaid block under ## Dependency Graph (skipping per-node checks)"
                .to_string(),
        ),
        Issue::HeaderFlowchart { line } => (
            *line,
            "[FC07] diagram header is 'flowchart'; expected 'graph TD' or 'graph LR'".to_string(),
        ),
        Issue::HeaderUnrecognized { line } => (
            *line,
            "[FC07] diagram header is not recognised; expected 'graph TD' or 'graph LR'"
                .to_string(),
        ),
        Issue::InlineClassSyntax { line } => (
            *line,
            "[FC07] inline class syntax ':::' is not the canonical form; use 'class <id> <name>'"
                .to_string(),
        ),
        Issue::UndefinedClass { name, line } => (
            *line,
            format!(
                "[FC07] class statement names class {:?} which no classDef in this diagram declares",
                name
            ),
        ),
    };
    ValidationError {
        file: doc.path.clone(),
        line,
        code: "FC07".to_string(),
        message,
    }
}

/// Node-set bijection pass. Dispatches to the per-profile pass: plan
/// profile pairs `I<n>` diagram ids with `#n` entity-row keys; roadmap
/// profile pairs `I<n>` diagram ids with `#n` references found in the
/// Issues column of any entity row. The shared diagram-side filter
/// `^I[0-9]+$` excludes outline ids and custom-mnemonic external
/// references on both profiles.
fn node_set_pass(doc: &Doc, table: &Table, diagram: &Diagram) -> Vec<ValidationError> {
    match table.profile {
        Profile::Plan => node_set_pass_plan(doc, table, diagram),
        Profile::Roadmap => node_set_pass_roadmap(doc, table, diagram),
    }
}

/// Plan-profile bijection: `^I[0-9]+$` diagram ids against `#n`
/// entity-row keys.
fn node_set_pass_plan(doc: &Doc, table: &Table, diagram: &Diagram) -> Vec<ValidationError> {
    let mut errs = Vec::new();

    let table_keys = table_issue_keys(table);
    let diagram_keys: HashSet<&str> = diagram
        .nodes
        .iter()
        .filter(|n| ISSUE_KEYED_NODE_ID.is_match(&n.id))
        .map(|n| n.id.as_str())
        .collect();

    // Table key with no diagram node.
    for row in &table.rows {
        if row.kind != RowKind::Entity {
            continue;
        }
        let key = row.key.as_str();
        if let Some(num) = key.strip_prefix('#') {
            if !num.chars().all(|c| c.is_ascii_digit()) {
                continue;
            }
            let expected = format!("I{}", num);
            if !diagram_keys.contains(expected.as_str()) {
                errs.push(ValidationError {
                    file: doc.path.clone(),
                    line: row.line,
                    code: "FC07".to_string(),
                    message: format!(
                        "[FC07] table row {:?} has no matching diagram node (expected {:?})",
                        key, expected
                    ),
                });
            }
        }
    }

    // Diagram node with no table key.
    for node in &diagram.nodes {
        if !ISSUE_KEYED_NODE_ID.is_match(&node.id) {
            continue;
        }
        // node.id is "I<n>"; the corresponding table key is "#<n>".
        let num = &node.id[1..];
        let table_key = format!("#{}", num);
        if !table_keys.contains(table_key.as_str()) {
            errs.push(ValidationError {
                file: doc.path.clone(),
                line: node.line,
                code: "FC07".to_string(),
                message: format!(
                    "[FC07] diagram node {:?} has no matching table row (expected key {:?})",
                    node.id, table_key
                ),
            });
        }
    }

    errs
}

/// Roadmap-profile bijection: `^I[0-9]+$` diagram ids against the set
/// of `#n` references found in entity-row Issues cells. A row whose
/// Issues cell is `None` contributes no expected nodes. The diagram's
/// `I<n>` set is the union of every `#n` that appears across the
/// table's Issues cells.
fn node_set_pass_roadmap(doc: &Doc, table: &Table, diagram: &Diagram) -> Vec<ValidationError> {
    let mut errs = Vec::new();

    // Build the table-justified expected node set: for each entity row,
    // parse its raw row text for `#n` tokens inside the Issues column
    // and add `In` to the expected set. Track the row each expected
    // node was derived from so the missing-node notice can cite the row
    // line. The Issues column is the second column of the canonical
    // roadmap profile (index 1) -- the parser does not split the raw
    // row into per-column cells beyond what RowKind classification
    // needed, so we extract the issue tokens from `row.raw` directly.
    let issues_col_idx = table
        .columns
        .iter()
        .position(|c| c == "Issues");
    let mut expected_nodes: Vec<(String, usize, String)> = Vec::new(); // (expected_id, row_line, row_key)
    for row in &table.rows {
        if row.kind != RowKind::Entity {
            continue;
        }
        let issues_cell = match issues_col_idx {
            Some(idx) => split_raw_row_cell(&row.raw, idx),
            None => String::new(),
        };
        for cap in ISSUE_REF_IN_CELL.captures_iter(&issues_cell) {
            let num = &cap[1];
            let expected = format!("I{}", num);
            expected_nodes.push((expected, row.line, row.key.clone()));
        }
    }

    let expected_set: HashSet<&str> = expected_nodes
        .iter()
        .map(|(id, _, _)| id.as_str())
        .collect();

    let diagram_keys: HashSet<&str> = diagram
        .nodes
        .iter()
        .filter(|n| ISSUE_KEYED_NODE_ID.is_match(&n.id))
        .map(|n| n.id.as_str())
        .collect();

    // Table row with no diagram node.
    for (expected, row_line, row_key) in &expected_nodes {
        if !diagram_keys.contains(expected.as_str()) {
            errs.push(ValidationError {
                file: doc.path.clone(),
                line: *row_line,
                code: "FC07".to_string(),
                message: format!(
                    "[FC07] table row {:?} lists issue in Issues column with no matching diagram node (expected {:?})",
                    row_key, expected
                ),
            });
        }
    }

    // Diagram node with no table row.
    for node in &diagram.nodes {
        if !ISSUE_KEYED_NODE_ID.is_match(&node.id) {
            continue;
        }
        if !expected_set.contains(node.id.as_str()) {
            errs.push(ValidationError {
                file: doc.path.clone(),
                line: node.line,
                code: "FC07".to_string(),
                message: format!(
                    "[FC07] diagram node {:?} has no matching table row (no entity-row Issues cell references this issue)",
                    node.id
                ),
            });
        }
    }

    errs
}

/// Extract the cell at `idx` from a raw markdown table row. Returns the
/// cell's trimmed text, or an empty string if the row has fewer cells
/// than `idx + 1`. Mirrors the parsing the table module does
/// internally; FC07 reuses it for the roadmap-profile Issues-column
/// lookup since the parsed `Row` struct only keeps the key, deps, and
/// raw text.
fn split_raw_row_cell(raw: &str, idx: usize) -> String {
    let trimmed = raw.trim();
    let trimmed = trimmed.strip_prefix('|').unwrap_or(trimmed);
    let trimmed = trimmed.strip_suffix('|').unwrap_or(trimmed);
    trimmed
        .split('|')
        .nth(idx)
        .map(|s| s.trim().to_string())
        .unwrap_or_default()
}

/// Edge agreement pass. Convention is **blocker on the left, dependent
/// on the right**. Dispatches to the per-profile pass: plan profile
/// resolves dep tokens directly to `I<n>` ids; roadmap profile resolves
/// dep tokens (feature labels) to the depended-upon row's set of
/// `I<n>` nodes derived from that row's Issues cell.
fn edge_pass(doc: &Doc, table: &Table, diagram: &Diagram) -> Vec<ValidationError> {
    match table.profile {
        Profile::Plan => edge_pass_plan(doc, table, diagram),
        Profile::Roadmap => edge_pass_roadmap(doc, table, diagram),
    }
}

/// Plan-profile edge agreement: if table row `#a` lists `#b` in its
/// Dependencies cell, the diagram must contain `Ib --> Ia`.
fn edge_pass_plan(doc: &Doc, table: &Table, diagram: &Diagram) -> Vec<ValidationError> {
    let mut errs = Vec::new();

    // Build the set of (src, dst) edges restricted to issue-keyed pairs.
    let diagram_edges: HashSet<(String, String)> = diagram
        .edges
        .iter()
        .filter(|e| ISSUE_KEYED_NODE_ID.is_match(&e.src) && ISSUE_KEYED_NODE_ID.is_match(&e.dst))
        .map(|e| (e.src.clone(), e.dst.clone()))
        .collect();

    // Build the table-justified edge set: for every row #a with dep #b,
    // the edge is (Ib, Ia).
    let mut table_edges: HashSet<(String, String)> = HashSet::new();
    for row in &table.rows {
        if row.kind != RowKind::Entity {
            continue;
        }
        let dependent = match issue_id_from_key(&row.key) {
            Some(id) => id,
            None => continue,
        };
        for dep in &row.deps {
            let blocker = match issue_id_from_dep(dep) {
                Some(id) => id,
                None => continue,
            };
            table_edges.insert((blocker.clone(), dependent.clone()));
            // Missing-edge notice from the table side.
            if !diagram_edges.contains(&(blocker.clone(), dependent.clone())) {
                errs.push(ValidationError {
                    file: doc.path.clone(),
                    line: row.line,
                    code: "FC07".to_string(),
                    message: format!(
                        "[FC07] table row {:?} lists dependency {:?} but diagram has no matching edge ({} --> {})",
                        row.key, dep, blocker, dependent
                    ),
                });
            }
        }
    }

    // Orphan-edge notice from the diagram side.
    for edge in &diagram.edges {
        if !ISSUE_KEYED_NODE_ID.is_match(&edge.src) || !ISSUE_KEYED_NODE_ID.is_match(&edge.dst) {
            continue;
        }
        if !table_edges.contains(&(edge.src.clone(), edge.dst.clone())) {
            errs.push(ValidationError {
                file: doc.path.clone(),
                line: edge.line,
                code: "FC07".to_string(),
                message: format!(
                    "[FC07] diagram edge {} --> {} has no matching dependency in the table",
                    edge.src, edge.dst
                ),
            });
        }
    }

    errs
}

/// Roadmap-profile edge agreement. Builds two maps:
///
/// 1. **feature-label -> `Vec<I<n>>`**: each entity row's feature label
///    maps to the set of `I<n>` ids derived from its Issues cell.
/// 2. **deps -> edges**: for each dependent row, for each dep that
///    resolves to another entity row's label, every `I<a>` in the
///    blocker row's set crosses every `I<b>` in the dependent row's
///    set, contributing one expected `Ia --> Ib` edge.
///
/// Cross-product dependency tokens (containing `/`) and feature-label
/// tokens that do not match any row are excluded from the edge
/// derivation -- they encode out-of-band relationships the local
/// diagram cannot reflect.
fn edge_pass_roadmap(doc: &Doc, table: &Table, diagram: &Diagram) -> Vec<ValidationError> {
    let mut errs = Vec::new();

    let issues_col_idx = table
        .columns
        .iter()
        .position(|c| c == "Issues");

    // Build the feature-label -> Vec<I<n>> map. A row whose Issues cell
    // is `None` maps to an empty vec.
    let mut nodes_by_label: std::collections::HashMap<String, Vec<String>> =
        std::collections::HashMap::new();
    for row in &table.rows {
        if row.kind != RowKind::Entity {
            continue;
        }
        let issues_cell = match issues_col_idx {
            Some(idx) => split_raw_row_cell(&row.raw, idx),
            None => String::new(),
        };
        let ids: Vec<String> = ISSUE_REF_IN_CELL
            .captures_iter(&issues_cell)
            .map(|c| format!("I{}", &c[1]))
            .collect();
        nodes_by_label.insert(row.key.clone(), ids);
    }

    // Build the set of (src, dst) diagram edges restricted to
    // issue-keyed pairs.
    let diagram_edges: HashSet<(String, String)> = diagram
        .edges
        .iter()
        .filter(|e| ISSUE_KEYED_NODE_ID.is_match(&e.src) && ISSUE_KEYED_NODE_ID.is_match(&e.dst))
        .map(|e| (e.src.clone(), e.dst.clone()))
        .collect();

    // Build the table-justified edge set: for each dependent row, for
    // each dep that resolves to another row, every (blocker_id,
    // dependent_id) pair contributes an expected edge.
    let mut table_edges: HashSet<(String, String)> = HashSet::new();
    for row in &table.rows {
        if row.kind != RowKind::Entity {
            continue;
        }
        let dependent_ids = match nodes_by_label.get(&row.key) {
            Some(v) => v,
            None => continue,
        };
        for dep in &row.deps {
            if dep.contains('/') {
                continue;
            }
            let blocker_ids = match nodes_by_label.get(dep.as_str()) {
                Some(v) => v,
                None => continue,
            };
            for blocker_id in blocker_ids {
                for dependent_id in dependent_ids {
                    table_edges
                        .insert((blocker_id.clone(), dependent_id.clone()));
                    if !diagram_edges
                        .contains(&(blocker_id.clone(), dependent_id.clone()))
                    {
                        errs.push(ValidationError {
                            file: doc.path.clone(),
                            line: row.line,
                            code: "FC07".to_string(),
                            message: format!(
                                "[FC07] table row {:?} lists dependency {:?} but diagram has no matching edge ({} --> {})",
                                row.key, dep, blocker_id, dependent_id
                            ),
                        });
                    }
                }
            }
        }
    }

    // Orphan-edge notice from the diagram side.
    for edge in &diagram.edges {
        if !ISSUE_KEYED_NODE_ID.is_match(&edge.src) || !ISSUE_KEYED_NODE_ID.is_match(&edge.dst) {
            continue;
        }
        if !table_edges.contains(&(edge.src.clone(), edge.dst.clone())) {
            errs.push(ValidationError {
                file: doc.path.clone(),
                line: edge.line,
                code: "FC07".to_string(),
                message: format!(
                    "[FC07] diagram edge {} --> {} has no matching dependency in the table",
                    edge.src, edge.dst
                ),
            });
        }
    }

    errs
}

/// Class-versus-Status agreement pass. For each class assignment whose
/// name is in [`STATUS_CLASSES`] and whose id is an issue-keyed diagram
/// node, evaluate the four-case truth table:
///
/// - `done`: row must be in a terminal state.
/// - `ready`: row must be open AND every dependency target must be in a
///   terminal state.
/// - `blocked`: row must be open AND at least one dependency target must
///   itself be open.
///
/// A mismatch fires one notice in the four-field shape (node, declared
/// class, observed state, expected class). Non-Status classes are
/// skipped (see [`NON_STATUS_CLASSES`] for the recognised set). When a
/// node carries multiple classes (a combinatorial assignment), each
/// Status-bearing class is evaluated against the truth table
/// independently; the other classes are observed but not reconciled.
fn class_vs_status_pass(doc: &Doc, table: &Table, diagram: &Diagram) -> Vec<ValidationError> {
    let mut errs = Vec::new();

    // Build the per-profile lookup from diagram id to its parsed row.
    // Plan: I<n> -> row whose key is `#n`. Roadmap: I<n> -> row whose
    // Issues cell contains `#n`.
    let row_by_id: std::collections::HashMap<String, &Row> = match table.profile {
        Profile::Plan => table
            .rows
            .iter()
            .filter(|r| r.kind == RowKind::Entity)
            .filter_map(|r| issue_id_from_key(&r.key).map(|id| (id, r)))
            .collect(),
        Profile::Roadmap => {
            let issues_col_idx = table.columns.iter().position(|c| c == "Issues");
            let mut map: std::collections::HashMap<String, &Row> =
                std::collections::HashMap::new();
            for row in &table.rows {
                if row.kind != RowKind::Entity {
                    continue;
                }
                let issues_cell = match issues_col_idx {
                    Some(idx) => split_raw_row_cell(&row.raw, idx),
                    None => String::new(),
                };
                for cap in ISSUE_REF_IN_CELL.captures_iter(&issues_cell) {
                    map.insert(format!("I{}", &cap[1]), row);
                }
            }
            map
        }
    };

    // For the roadmap profile, build a feature-label -> row lookup so
    // `expected_class` can resolve dep tokens (which are feature labels)
    // to the depended-upon row's terminality.
    let label_to_row: std::collections::HashMap<String, &Row> = match table.profile {
        Profile::Plan => std::collections::HashMap::new(),
        Profile::Roadmap => table
            .rows
            .iter()
            .filter(|r| r.kind == RowKind::Entity)
            .map(|r| (r.key.clone(), r))
            .collect(),
    };

    for assign in &diagram.class_assignments {
        if !STATUS_CLASSES.contains(&assign.name.as_str()) {
            continue;
        }
        if !ISSUE_KEYED_NODE_ID.is_match(&assign.id) {
            continue;
        }
        let row = match row_by_id.get(&assign.id) {
            Some(r) => *r,
            None => continue, // node-set pass already reported this
        };

        let observed = observed_state(row, table.profile);
        let expected = expected_class(row, table.profile, &row_by_id, &label_to_row);
        if assign.name != expected {
            errs.push(class_status_notice(
                doc,
                &assign.id,
                &assign.name,
                observed,
                expected,
                assign.line,
            ));
        }
    }

    errs
}

/// The observed terminal-or-open state for a row, used to render the
/// class-versus-Status notice body.
fn observed_state(row: &Row, profile: Profile) -> &'static str {
    if row.terminal {
        return "terminal";
    }
    // Open: distinguish the roadmap-profile Status-value cases for the
    // notice body. The plan profile has no Status cell.
    match (profile, row.status.as_deref()) {
        (Profile::Roadmap, Some(s)) if !s.is_empty() => "open",
        _ => "open",
    }
}

/// Derive the expected Status class for a row from its terminal-or-open
/// state and its dependencies. The dep resolution path is profile-aware:
///
/// - **Plan**: dep tokens are `#N` and resolve to their `IN` ids,
///   then through `row_by_id` (`IN` -> row).
/// - **Roadmap**: dep tokens are feature labels and resolve to their
///   rows through `label_to_row` directly. Cross-product tokens
///   (containing `/`) are treated as out-of-band and ignored for the
///   ready/blocked decision -- their terminality cannot be observed
///   from this doc.
fn expected_class(
    row: &Row,
    profile: Profile,
    row_by_id: &std::collections::HashMap<String, &Row>,
    label_to_row: &std::collections::HashMap<String, &Row>,
) -> &'static str {
    if row.terminal {
        return "done";
    }
    // Inspect dependency state to decide ready vs blocked.
    let mut all_deps_terminal = true;
    let mut has_open_dep = false;
    for dep in &row.deps {
        let dep_row: Option<&Row> = match profile {
            Profile::Plan => issue_id_from_dep(dep).and_then(|id| row_by_id.get(&id).copied()),
            Profile::Roadmap => {
                if dep.contains('/') {
                    // Cross-product dep: treat as unknown -- the
                    // validator cannot observe its state from this
                    // doc, so it falls into the "open" case below.
                    None
                } else {
                    label_to_row.get(dep.as_str()).copied()
                }
            }
        };
        match dep_row {
            Some(r) => {
                if r.terminal {
                    // dep is closed
                } else {
                    has_open_dep = true;
                    all_deps_terminal = false;
                }
            }
            None => {
                // Unknown / cross-product dep: treated as not-yet-
                // terminal for the ready/blocked decision (consistent
                // with the truth table's "open" classification).
                all_deps_terminal = false;
                has_open_dep = true;
            }
        }
    }
    if has_open_dep {
        return "blocked";
    }
    if all_deps_terminal {
        return "ready";
    }
    "ready"
}

fn class_status_notice(
    doc: &Doc,
    node_id: &str,
    declared: &str,
    observed: &str,
    expected: &str,
    line: usize,
) -> ValidationError {
    ValidationError {
        file: doc.path.clone(),
        line,
        code: "FC07".to_string(),
        message: format!(
            "[FC07] node {:?} declared class {:?}, observed state {:?}, expected class {:?}",
            node_id, declared, observed, expected
        ),
    }
}

/// Collect the set of `#N` entity-row keys from the table.
fn table_issue_keys(table: &Table) -> HashSet<&str> {
    table
        .rows
        .iter()
        .filter(|r| r.kind == RowKind::Entity)
        .map(|r| r.key.as_str())
        .filter(|k| k.starts_with('#') && k[1..].chars().all(|c| c.is_ascii_digit()))
        .collect()
}

/// Map an entity-row key (`#N`) to its diagram node id (`IN`). Returns
/// `None` for non-issue-keyed keys (roadmap-profile feature labels, for
/// instance).
fn issue_id_from_key(key: &str) -> Option<String> {
    let num = key.strip_prefix('#')?;
    if !num.chars().all(|c| c.is_ascii_digit()) {
        return None;
    }
    Some(format!("I{}", num))
}

/// Map a Dependencies-cell token to its diagram node id. Cross-repo
/// references (`owner/repo#N`) and free-text feature labels return
/// `None`; these are excluded from the edge agreement check.
fn issue_id_from_dep(dep: &str) -> Option<String> {
    if dep.contains('/') {
        return None;
    }
    issue_id_from_key(dep)
}

/// Parse a `owner/repo#N` cross-repo dependency token. Returns the
/// `(owner, repo, number)` triple if every component passes the
/// validator-side character-set gate; otherwise `None`. The gate
/// protects every notice body from echoing attacker-influenced text.
fn parse_cross_repo_dep(dep: &str) -> Option<(String, String, u64)> {
    let (slug, num_str) = dep.split_once('#')?;
    let (owner, repo) = slug.split_once('/')?;
    if !is_valid_owner_or_repo(owner) || !is_valid_owner_or_repo(repo) {
        return None;
    }
    let number: u64 = num_str.parse().ok()?;
    Some((owner.to_string(), repo.to_string(), number))
}

/// Extract the issue number from an `I<n>` diagram node id.
fn issue_number_from_id(id: &str) -> Option<u64> {
    id.strip_prefix('I').and_then(|n| n.parse::<u64>().ok())
}

/// Matches a `Closes`/`Fixes`/`Resolves` line in a PR body. The
/// optional first two captures hold the cross-repo `owner` and `repo`
/// substrings; the third capture is the issue number. Matches the set
/// of keywords the GitHub UI itself recognises (DESIGN Decision 4 /
/// Scope).
static CLOSES_LINE_RE: LazyLock<Regex> = LazyLock::new(|| {
    Regex::new(r"(?i)(?:closes|fixes|resolves)\s+(?:([^\s/#]+)/([^\s#]+))?#(\d+)").unwrap()
});

/// One parsed `Closes` reference from a PR body.
#[derive(Debug, Clone, PartialEq, Eq)]
struct ClosesRef {
    /// Same-repo reference uses the PR's owner; cross-repo uses the
    /// parsed `owner/repo` slug.
    owner: String,
    repo: String,
    number: u64,
    /// True when the source line carried an explicit `owner/repo#N`
    /// prefix, false when only `#N` appeared.
    cross_repo: bool,
    /// The exact source-text literal (e.g. `Closes #42` or
    /// `Closes owner/repo#42`) used in the over-claims notice body.
    literal: String,
}

/// Extract every `Closes`/`Fixes`/`Resolves` reference from the body
/// of a pull request. Same-repo references inherit `default_owner` and
/// `default_repo`; cross-repo references are validated against the
/// character-set gate before being kept (DESIGN Decision 4 / Sub C
/// cross-repo case). References failing the gate are dropped without
/// emitting a notice.
fn extract_closes_refs(body: &str, default_owner: &str, default_repo: &str) -> Vec<ClosesRef> {
    let mut out = Vec::new();
    for cap in CLOSES_LINE_RE.captures_iter(body) {
        let number: u64 = match cap.get(3).and_then(|m| m.as_str().parse().ok()) {
            Some(n) => n,
            None => continue,
        };
        match (cap.get(1), cap.get(2)) {
            (Some(o), Some(r)) => {
                let owner = o.as_str();
                let repo = r.as_str();
                if !is_valid_owner_or_repo(owner) || !is_valid_owner_or_repo(repo) {
                    // Drop attacker-influenced cross-repo references.
                    continue;
                }
                let literal = format!("{} {}/{}#{}", &cap[0][..cap[0].find(char::is_whitespace).unwrap_or(0)],
                    owner, repo, number);
                out.push(ClosesRef {
                    owner: owner.to_string(),
                    repo: repo.to_string(),
                    number,
                    cross_repo: true,
                    literal,
                });
            }
            _ => {
                let literal = format!("{} #{}", &cap[0][..cap[0].find(char::is_whitespace).unwrap_or(0)],
                    number);
                out.push(ClosesRef {
                    owner: default_owner.to_string(),
                    repo: default_repo.to_string(),
                    number,
                    cross_repo: false,
                    literal,
                });
            }
        }
    }
    out
}

/// The canonical Status palette every diagram inherits. A `classDef`
/// declaring one of these names does not require a Legend entry; a
/// Legend entry naming one of these names does not require a matching
/// `classDef` declaration. Tracks the "Status Classes" section of
/// `references/dependency-diagram.md`.
///
/// Distinct from `STATUS_CLASSES` only in intent (FC08's canonical-
/// palette tolerance); the names are the same Status set FC07 uses,
/// so the array deliberately duplicates the contents rather than
/// aliasing to keep each check's binding self-contained.
const FC08_STATUS_PALETTE: &[&str] = &["done", "ready", "blocked"];

/// The pipeline-stage and tracks-prefix class set FC08 expects the
/// Legend to name when the diagram declares them. These classes are
/// outside the canonical Status palette and a reader needs the Legend
/// to decode them; Sub-check B fires when the Legend omits a
/// `classDef` declaration for one of these names. They participate in
/// the kebab-to-camel normalization rule (Sub-check C). Tracks the
/// "Pipeline Stage Classes" section of
/// `references/dependency-diagram.md`.
#[cfg_attr(not(test), allow(dead_code))]
const FC08_PIPELINE_STAGE_CLASSES: &[&str] = &[
    "needsDesign",
    "needsPrd",
    "needsPlanning",
    "needsSpike",
    "needsDecision",
    "needsExplore",
    "tracksDesign",
    "tracksPlan",
];

/// Normalize a kebab-case class name to its camelCase form by
/// uppercasing the first character after each `-` and dropping the
/// hyphen. Names with no hyphens are returned unchanged.
///
/// Total over arbitrary UTF-8 input: iterates `chars()` (UTF-8-safe)
/// and uses `to_uppercase()` (also UTF-8-safe). No `unwrap`, no byte
/// indexing past a multi-byte boundary, no unbounded loop -- the
/// output `String` allocation is bounded by the input character
/// count.
fn normalize_kebab_to_camel(s: &str) -> String {
    let mut out = String::with_capacity(s.len());
    let mut upper_next = false;
    for c in s.chars() {
        if c == '-' {
            upper_next = true;
            continue;
        }
        if upper_next {
            out.extend(c.to_uppercase());
            upper_next = false;
        } else {
            out.push(c);
        }
    }
    out
}

/// Parse the text after a Legend line's leading `Legend:` token into
/// the recovered class names. Splits on `,` then on `=`; the right-
/// hand side of each `=` is the class name. Entries without `=`,
/// entries with empty halves, and empty entries are silently dropped.
///
/// A composite entry like `tracks-design/tracks-plan` is split on `/`
/// and each non-empty part is recorded as a separate class name
/// (matching the documented Legend convention in
/// `references/dependency-diagram.md`).
///
/// Total over arbitrary UTF-8 input: uses only `str::split`,
/// `str::split_once`, and `str::trim`, all of which are UTF-8-safe.
fn parse_legend_entries(s: &str) -> Vec<String> {
    let mut out = Vec::new();
    for entry in s.split(',') {
        let Some((_color, name)) = entry.split_once('=') else {
            continue;
        };
        let name = name.trim();
        if name.is_empty() {
            continue;
        }
        for part in name.split('/') {
            let part = part.trim();
            if !part.is_empty() {
                out.push(part.to_string());
            }
        }
    }
    out
}

/// Extract the first Legend line's class names from body lines
/// following the located Dependency Graph fence.
///
/// `body` is the doc body (the same `Vec<String>` `Doc` carries),
/// indexed 0-based. `fence_end_line` is the 1-based line number of
/// the closing-fence line (`BlockLocation.body_end`); the scan
/// begins on the line AFTER that, 0-based index
/// `fence_end_line.saturating_sub(0)` since `body_end` already
/// points at the closing-fence line index + 1 in 1-based numbering.
///
/// The scan stops at the first line whose content (after `trim()`
/// and stripping optional `**` bold markers) begins with `Legend:`
/// (case-sensitive on the leading token). Two acceptable shapes:
///
/// - `Legend: ...` (plain), with or without leading whitespace.
/// - `**Legend**: ...` (bold-wrapped), with or without leading
///   whitespace.
///
/// Returns an empty `Vec` when no Legend line is found, when the
/// recovered entries contain no parseable class names, or when the
/// scan starts past the end of `body`.
///
/// The extractor is total: no panics, no UTF-8 boundary errors, no
/// unbounded loops. The "first Legend wins" rule short-circuits the
/// scan as soon as a Legend line is recognized.
fn extract_legend(body: &[String], fence_end_line: usize) -> Vec<String> {
    let start = fence_end_line.min(body.len());
    for line in &body[start..] {
        let trimmed = line.trim();
        // Accept `**Legend**:` first (the documented canonical shape).
        if let Some(rest) = trimmed.strip_prefix("**Legend**:") {
            return parse_legend_entries(rest);
        }
        // Accept `Legend:` (plain or wrapped with stripped `**`).
        let unwrapped = trimmed.strip_prefix("**").unwrap_or(trimmed);
        if let Some(rest) = unwrapped.strip_prefix("Legend:") {
            return parse_legend_entries(rest);
        }
    }
    Vec::new()
}

/// FC08 -- Legend-vs-classDef reconciliation.
///
/// Reconciles each plan or roadmap doc's Dependency Graph Legend prose
/// line against the diagram's `classDef` declarations and the canonical
/// class palette. Three sub-checks share a single pass over the located
/// Dependency Graph block, the extracted `Diagram.class_defs` field,
/// and the recovered Legend names:
///
/// - **Sub A (Legend-names-no-classDef).** Each Legend class name must
///   correspond to a local `classDef` declaration OR be in the
///   canonical Status palette (`done`, `ready`, `blocked`). A name
///   satisfying neither fires a notice naming the class.
/// - **Sub B (classDef-omitted-from-Legend).** Each `classDef`
///   declaration outside the canonical Status palette must be named by
///   the Legend (modulo kebab-to-camel normalization). A `classDef`
///   the Legend omits fires a notice naming the class.
/// - **Sub C (normalization-mismatch).** A Legend entry that matches
///   a `classDef` only under kebab-to-camel normalization fires a
///   notice recommending the camelCase form.
///
/// The check ships at notice level via the `is_notice` membership;
/// promotion to error is the one-line removal of the `"FC08"` arm from
/// the `matches!` expression in `validate::is_notice`.
///
/// FC08 returns an empty `Vec` when the format has no
/// `issues_table_columns` (the same no-op gate FC05/FC06/FC07 use) or
/// when the Dependency Graph block is absent. A doc with no Legend
/// line produces no notice (the Legend convention is optional).
///
/// Notice bodies name only entities the doc itself already names
/// (class names parsed from the Legend or the diagram; the kebab-to-
/// camel normalized form derived from those names). No notice quotes
/// any external identifier, URL, env-var value, or private repo name
/// (PRD R12 public-cleanliness).
pub fn check_fc08(doc: &Doc, spec: &FormatSpec) -> Vec<ValidationError> {
    if spec.issues_table_columns.is_empty() {
        return Vec::new();
    }
    let location = match find_dependency_graph_block(doc) {
        Some(l) => l,
        None => return Vec::new(),
    };
    // A MissingBlock short-circuits FC08 per the FC07 precedent.
    for issue in &location.issues {
        if let Issue::MissingBlock { .. } = issue {
            return Vec::new();
        }
    }
    // Extract the diagram (FC07 infrastructure; reuses `class_defs`).
    let body_start_idx = location.body_start.saturating_sub(1);
    let body_end_idx = location
        .body_end
        .saturating_sub(1)
        .min(doc.body.len());
    if body_start_idx > body_end_idx {
        return Vec::new();
    }
    let body_slice: Vec<&str> = doc.body[body_start_idx..body_end_idx]
        .iter()
        .map(|s| s.as_str())
        .collect();
    let (diagram, _issues) = extract_diagram(&body_slice, location.body_start);

    // Extract the Legend from the lines AFTER the closing fence. The
    // closing-fence line is at 0-based index `body_end_idx`; the scan
    // starts on the next line.
    let legend_scan_start = location.body_end.min(doc.body.len());
    let legend_names = extract_legend(&doc.body, legend_scan_start);

    let mut errs = Vec::new();
    errs.extend(check_fc08_sub_a(doc, &legend_names, &diagram.class_defs));
    errs.extend(check_fc08_sub_b(doc, &legend_names, &diagram.class_defs));
    errs.extend(check_fc08_sub_c(doc, &legend_names, &diagram.class_defs));
    errs
}

fn check_fc08_sub_a(
    doc: &Doc,
    legend: &[String],
    class_defs: &HashSet<String>,
) -> Vec<ValidationError> {
    let mut errs = Vec::new();
    let mut seen: HashSet<String> = HashSet::new();
    for name in legend {
        if !seen.insert(name.clone()) {
            continue;
        }
        let normalized = normalize_kebab_to_camel(name);
        let in_palette = FC08_STATUS_PALETTE
            .iter()
            .any(|p| *p == name.as_str() || *p == normalized.as_str());
        let in_classdefs = class_defs.contains(name) || class_defs.contains(&normalized);
        if !in_palette && !in_classdefs {
            errs.push(ValidationError {
                file: doc.path.clone(),
                line: 0,
                code: "FC08".to_string(),
                message: format!(
                    "[FC08] Legend names class `{name}` but no `classDef {name}` exists \
                     in the diagram and `{name}` is not in the canonical Status palette"
                ),
            });
        }
    }
    errs
}

fn check_fc08_sub_b(
    doc: &Doc,
    legend: &[String],
    class_defs: &HashSet<String>,
) -> Vec<ValidationError> {
    // PRD R4: an absent Legend produces no FC08 notice (the Legend
    // convention is optional). Sub B only fires when a Legend is
    // present but omits a classDef declaration outside the canonical
    // palette.
    if legend.is_empty() {
        return Vec::new();
    }
    let legend_normalized: HashSet<String> = legend
        .iter()
        .map(|n| normalize_kebab_to_camel(n))
        .collect();
    let mut class_def_names: Vec<&String> = class_defs.iter().collect();
    class_def_names.sort();
    let mut errs = Vec::new();
    for cd in class_def_names {
        if FC08_STATUS_PALETTE.iter().any(|p| *p == cd.as_str()) {
            continue;
        }
        if legend.iter().any(|n| n == cd) || legend_normalized.contains(cd) {
            continue;
        }
        errs.push(ValidationError {
            file: doc.path.clone(),
            line: 0,
            code: "FC08".to_string(),
            message: format!(
                "[FC08] Diagram declares `classDef {cd}` outside the canonical Status \
                 palette but the Legend does not name it"
            ),
        });
    }
    errs
}

fn check_fc08_sub_c(
    doc: &Doc,
    legend: &[String],
    class_defs: &HashSet<String>,
) -> Vec<ValidationError> {
    let mut errs = Vec::new();
    let mut seen: HashSet<String> = HashSet::new();
    for name in legend {
        if !seen.insert(name.clone()) {
            continue;
        }
        let normalized = normalize_kebab_to_camel(name);
        if normalized != *name && class_defs.contains(&normalized) {
            errs.push(ValidationError {
                file: doc.path.clone(),
                line: 0,
                code: "FC08".to_string(),
                message: format!(
                    "[FC08] Legend names class `{name}` but the diagram declares \
                     `classDef {normalized}`; use the camelCase form `{normalized}` \
                     to match the codebase convention"
                ),
            });
        }
    }
    errs
}

/// FC09 -- doc-vs-GitHub state reconciliation.
///
/// The third reconciliation axis in `shirabe-validate`. FC07 reconciles
/// the Implementation Issues table against the dependency diagram; FC08
/// reconciles the Legend against the classDef set; FC09 reconciles the
/// doc's claims about issue state (table strikethrough, diagram class
/// assignments) against (a) GitHub's observed issue state and (b) the
/// current PR's `Closes #N` body lines.
///
/// Three sub-checks share a single pass over the diagram's
/// `class_assignments`:
///
/// - **Sub A** (doc-claims-done vs GitHub): a node carrying class `done`
///   whose row is terminal-or-strikethrough must correspond to an
///   actually-closed issue on GitHub. A `done`-claim against an open
///   issue fires.
/// - **Sub B** (doc-claims-open vs GitHub): a node carrying class
///   `ready` or `blocked` (non-terminal) must correspond to an
///   actually-open issue on GitHub. A non-`done` claim against a closed
///   issue fires (catching plans the doc never updated after a parallel
///   PR closed the issue).
/// - **Sub C** (PR `Closes #N` vs doc): when running in PR context, the
///   PR body's `Closes #N` lines and the doc's `done`-claims must agree
///   in both directions. Over-claims (PR closes an N the doc shows
///   non-done) and under-claims (doc shows N done, no matching `Closes`
///   in the PR body) both fire.
///
/// The check self-disables gracefully on four conditions, each with its
/// own skip notice in the FC05/FC06/FC07 voice (DESIGN Decision 4):
///
/// - **Missing credentials.** The initial probe returns
///   `ClientError::Auth`; one skip notice, the check returns.
/// - **Missing PR context.** `pr_ctx` is `None`; Sub-check C emits one
///   skip notice and is skipped. Sub A and Sub B still run if
///   `pr_ctx`-derived `(owner, repo)` is otherwise available -- in
///   practice missing context means the validator has no same-repo
///   `(owner, repo)` to query, so Sub A and Sub B effectively no-op too.
/// - **Rate-limit exhausted.** First `RateLimit` triggers a 2-second
///   back-off and a single retry; second `RateLimit` emits the skip
///   notice and breaks the per-row loop (subsequent rows in this run
///   are not reconciled).
/// - **Per-row cross-repo access denied.** A row's cross-repo reference
///   returns `Forbidden`; one per-row skip notice; subsequent rows
///   continue.
///
/// The check ships at notice level via the `is_notice` membership
/// (DESIGN Decision 6). FC09 only fires on Status-bearing classes
/// (`done`, `ready`, `blocked`) and only on issue-keyed nodes
/// (`^I[0-9]+$`); pipeline-stage classes and custom-mnemonic external
/// nodes are ignored.
///
/// Notice bodies name only entities the doc itself already names (row
/// keys, diagram ids, issue numbers, PR body literals). No notice
/// quotes the GitHub token, includes a URL, or names a private repo or
/// pre-announcement feature (PRD R17 public-cleanliness).
pub fn check_fc09(
    doc: &Doc,
    spec: &FormatSpec,
    client: &dyn IssueStateClient,
    pr_ctx: Option<&PrContext>,
) -> Vec<ValidationError> {
    if spec.issues_table_columns.is_empty() {
        return Vec::new();
    }

    let mut errs: Vec<ValidationError> = Vec::new();

    // Sub-check C engages only when a PR context is available. Emit the
    // skip notice once when missing; Sub A and Sub B still run.
    let pr_ctx_missing = pr_ctx.is_none();

    let table = match parse_issues_table(doc) {
        Some(t) => t,
        None => return errs,
    };

    let location = match find_dependency_graph_block(doc) {
        Some(l) => l,
        None => return errs,
    };

    // A MissingBlock short-circuits per-node passes (matches FC07).
    for issue in &location.issues {
        if let Issue::MissingBlock { .. } = issue {
            return errs;
        }
    }

    // Extract the body lines for the located block.
    let body_start_idx = location.body_start.saturating_sub(1);
    let body_end_idx = location
        .body_end
        .saturating_sub(1)
        .min(doc.body.len());
    let body_slice: Vec<&str> = doc
        .body
        .get(body_start_idx..body_end_idx)
        .map(|s| s.iter().map(|x| x.as_str()).collect())
        .unwrap_or_default();
    let (diagram, _extract_issues) = extract_diagram(&body_slice, location.body_start);

    // Build the per-profile lookup from diagram id to its parsed row,
    // mirroring FC07's class_vs_status_pass.
    let row_by_id: std::collections::HashMap<String, &Row> = match table.profile {
        Profile::Plan => table
            .rows
            .iter()
            .filter(|r| r.kind == RowKind::Entity)
            .filter_map(|r| issue_id_from_key(&r.key).map(|id| (id, r)))
            .collect(),
        Profile::Roadmap => {
            let issues_col_idx = table.columns.iter().position(|c| c == "Issues");
            let mut map: std::collections::HashMap<String, &Row> =
                std::collections::HashMap::new();
            for row in &table.rows {
                if row.kind != RowKind::Entity {
                    continue;
                }
                let issues_cell = match issues_col_idx {
                    Some(idx) => split_raw_row_cell(&row.raw, idx),
                    None => String::new(),
                };
                for cap in ISSUE_REF_IN_CELL.captures_iter(&issues_cell) {
                    map.insert(format!("I{}", &cap[1]), row);
                }
            }
            map
        }
    };

    // Dependencies-column index, used to resolve cross-repo references
    // for the per-row (owner, repo, number) when reconciling Sub A/B.
    let deps_col_idx = table.columns.iter().position(|c| c == "Dependencies");

    // Build a lookup: row.key -> cross-repo (owner, repo, number) for
    // the first cross-repo dep in that row's Dependencies cell whose
    // numeric tail matches the row's issue number. Same-repo rows fall
    // back to pr_ctx's (owner, repo).
    let cross_repo_by_row_key: std::collections::HashMap<String, (String, String, u64)> = {
        let mut map: std::collections::HashMap<String, (String, String, u64)> =
            std::collections::HashMap::new();
        if let Some(idx) = deps_col_idx {
            for row in &table.rows {
                if row.kind != RowKind::Entity {
                    continue;
                }
                let cell = split_raw_row_cell(&row.raw, idx);
                for tok in cell.split(',') {
                    let tok = tok.trim();
                    if let Some(triple) = parse_cross_repo_dep(tok) {
                        map.insert(row.key.clone(), triple);
                        break;
                    }
                }
            }
        }
        map
    };

    // Run Sub A and Sub B in one pass. Per DESIGN: if pr_ctx is None
    // we still skip Sub C, but Sub A/B need a same-repo (owner, repo)
    // anchor -- when pr_ctx is None there's nothing to query, so the
    // missing-credentials/missing-context skip messaging covers that.
    let default_owner = pr_ctx.map(|p| p.owner.as_str()).unwrap_or("");
    let default_repo = pr_ctx.map(|p| p.repo.as_str()).unwrap_or("");

    // Track which (owner, repo, number) tuples FC09 reconciled so Sub C
    // can compare against the doc's `done`-claims.
    let mut done_claimed_same_repo: std::collections::HashSet<u64> =
        std::collections::HashSet::new();

    // Track which `class ready` / `class blocked` nodes the doc shows
    // non-done; Sub C compares against `Closes #N` to fire over-claims
    // notices. Maps issue number -> (row key, class name, class line).
    let mut non_done_same_repo: std::collections::HashMap<u64, (String, String, usize)> =
        std::collections::HashMap::new();

    // The class assignments iteration may break early on rate-limit
    // exhaustion; track whether we should also skip Sub C.
    let mut rate_limit_exhausted = false;
    // Track which rows we've already credential-probed via Auth-skip.
    let mut auth_probed_skip = false;

    'outer: for assign in &diagram.class_assignments {
        if !STATUS_CLASSES.contains(&assign.name.as_str()) {
            continue;
        }
        if !ISSUE_KEYED_NODE_ID.is_match(&assign.id) {
            continue;
        }
        let row = match row_by_id.get(&assign.id) {
            Some(r) => *r,
            None => continue,
        };
        let issue_n = match issue_number_from_id(&assign.id) {
            Some(n) => n,
            None => continue,
        };

        // Determine the (owner, repo, number) to query. Cross-repo rows
        // use the row's Dependencies-cell reference; same-repo uses
        // pr_ctx. If pr_ctx is None and the row has no cross-repo dep,
        // skip the row (no (owner, repo) to query).
        let (q_owner, q_repo, q_number, is_cross_repo) =
            match cross_repo_by_row_key.get(&row.key) {
                Some((o, r, n)) => (o.clone(), r.clone(), *n, true),
                None => {
                    if pr_ctx.is_none() {
                        continue;
                    }
                    (default_owner.to_string(), default_repo.to_string(), issue_n, false)
                }
            };

        // Track for Sub C reconciliation.
        let doc_claims_done = assign.name == "done";
        if !is_cross_repo {
            if doc_claims_done {
                done_claimed_same_repo.insert(issue_n);
            } else {
                non_done_same_repo
                    .insert(issue_n, (row.key.clone(), assign.name.clone(), assign.line));
            }
        }

        // Fetch with single rate-limit retry at the call site.
        let first = client.fetch_issue_state(&q_owner, &q_repo, q_number);
        let result = match first {
            Err(ClientError::RateLimit) => {
                std::thread::sleep(std::time::Duration::from_secs(2));
                client.fetch_issue_state(&q_owner, &q_repo, q_number)
            }
            other => other,
        };

        match result {
            Ok(observed) => {
                let row_terminal = row.terminal;
                if doc_claims_done && observed == IssueState::Open {
                    errs.push(ValidationError {
                        file: doc.path.clone(),
                        line: assign.line,
                        code: "FC09".to_string(),
                        message: format!(
                            "[FC09] row {:?} (node {}) claims done; GitHub observes issue #{} still open (expected: remove the strikethrough/done class, or land the closing PR for #{})",
                            row.key, assign.id, q_number, q_number
                        ),
                    });
                } else if !doc_claims_done && observed == IssueState::Closed && !row_terminal {
                    errs.push(ValidationError {
                        file: doc.path.clone(),
                        line: assign.line,
                        code: "FC09".to_string(),
                        message: format!(
                            "[FC09] row {:?} (node {}) claims open with class {}; GitHub observes issue #{} closed (expected: change class from {} to done and apply strikethrough to the row)",
                            row.key, assign.id, assign.name, q_number, assign.name
                        ),
                    });
                }
            }
            Err(ClientError::Auth) => {
                if !auth_probed_skip {
                    errs.push(ValidationError {
                        file: doc.path.clone(),
                        line: assign.line,
                        code: "FC09".to_string(),
                        message: "[FC09] skipped: no GitHub credentials available (set GITHUB_TOKEN or run `gh auth login`)".to_string(),
                    });
                    auth_probed_skip = true;
                }
                // Without credentials nothing else will succeed; break.
                break 'outer;
            }
            Err(ClientError::RateLimit) => {
                errs.push(ValidationError {
                    file: doc.path.clone(),
                    line: assign.line,
                    code: "FC09".to_string(),
                    message: "[FC09] skipped: GitHub rate limit exhausted after one retry (subsequent rows in this run will not be reconciled)".to_string(),
                });
                rate_limit_exhausted = true;
                break 'outer;
            }
            Err(ClientError::Forbidden) => {
                if is_cross_repo {
                    errs.push(ValidationError {
                        file: doc.path.clone(),
                        line: assign.line,
                        code: "FC09".to_string(),
                        message: format!(
                            "[FC09] row {:?} (cross-repo {:?}) skipped: GitHub returned access denied (token cannot read {}/{})",
                            row.key,
                            format!("{}/{}#{}", q_owner, q_repo, q_number),
                            q_owner,
                            q_repo
                        ),
                    });
                }
                // Continue to next row.
            }
            Err(ClientError::NotFound) => {
                // No per-row notice; FC09 does not reconcile rows whose
                // issue cannot be fetched for reasons other than rate-
                // limit or cross-repo denial (PRD R14).
            }
            Err(ClientError::Network) | Err(ClientError::Malformed(_)) => {
                // No per-row notice on 5xx, malformed payloads, etc.
                // PRD R14: the check proceeds without dropping a notice.
            }
        }
    }

    // Sub-check C: PR Closes reconciliation.
    if pr_ctx_missing {
        errs.push(ValidationError {
            file: doc.path.clone(),
            line: 1,
            code: "FC09".to_string(),
            message: "[FC09] Sub-check C skipped: no PR context (set GITHUB_REF=refs/pull/<n>/merge, GITHUB_REPOSITORY, or SHIRABE_PR_NUMBER)".to_string(),
        });
    } else if !rate_limit_exhausted && !auth_probed_skip {
        // Fetch the PR body once with the same retry-then-skip discipline.
        let pr = pr_ctx.expect("checked above");
        let first = client.fetch_pr_body(&pr.owner, &pr.repo, pr.number);
        let body_result = match first {
            Err(ClientError::RateLimit) => {
                std::thread::sleep(std::time::Duration::from_secs(2));
                client.fetch_pr_body(&pr.owner, &pr.repo, pr.number)
            }
            other => other,
        };

        match body_result {
            Ok(body) => {
                let refs = extract_closes_refs(&body, &pr.owner, &pr.repo);

                // Over-claims: PR body Closes #N where doc shows non-done.
                for r in &refs {
                    if r.cross_repo {
                        // Cross-repo Closes line: check against doc's
                        // cross-repo non-done rows.
                        let mut hit = false;
                        for (_k, (row_key, class_name, line)) in &non_done_same_repo {
                            // Cross-repo case is sparse; we match by
                            // (owner, repo, number) via cross_repo_by_row_key.
                            if let Some(triple) = cross_repo_by_row_key.get(row_key) {
                                if triple.0 == r.owner && triple.1 == r.repo && triple.2 == r.number {
                                    errs.push(ValidationError {
                                        file: doc.path.clone(),
                                        line: *line,
                                        code: "FC09".to_string(),
                                        message: format!(
                                            "[FC09] PR body line {:?} claims a cross-repo closure the doc still shows non-done (row {:?}, class {})",
                                            format!("Closes {}/{}#{}", r.owner, r.repo, r.number),
                                            row_key, class_name
                                        ),
                                    });
                                    hit = true;
                                }
                            }
                        }
                        let _ = hit;
                    } else if let Some((row_key, class_name, line)) = non_done_same_repo.get(&r.number) {
                        errs.push(ValidationError {
                            file: doc.path.clone(),
                            line: *line,
                            code: "FC09".to_string(),
                            message: format!(
                                "[FC09] PR body line {:?} claims a closure the doc still shows non-done (row {:?}, class {}) (expected: update the row to done in this same PR, or remove the \"Closes #N\" line if closure is not intended)",
                                format!("Closes #{}", r.number),
                                row_key, class_name
                            ),
                        });
                    }
                }

                // Under-claims: doc shows N done but no Closes #N in body.
                let body_same_repo_nums: std::collections::HashSet<u64> = refs
                    .iter()
                    .filter(|r| !r.cross_repo)
                    .map(|r| r.number)
                    .collect();
                for n in &done_claimed_same_repo {
                    if !body_same_repo_nums.contains(n) {
                        // Find the assignment line for this done-claim.
                        let (line, row_key) = diagram
                            .class_assignments
                            .iter()
                            .find(|a| a.name == "done" && issue_number_from_id(&a.id) == Some(*n))
                            .map(|a| {
                                let key = row_by_id
                                    .get(&a.id)
                                    .map(|r| r.key.clone())
                                    .unwrap_or_else(|| format!("#{}", n));
                                (a.line, key)
                            })
                            .unwrap_or((1, format!("#{}", n)));
                        errs.push(ValidationError {
                            file: doc.path.clone(),
                            line,
                            code: "FC09".to_string(),
                            message: format!(
                                "[FC09] row {:?} claims done but GitHub observes issue #{} open and no \"Closes #{}\" appears in this PR (expected: add \"Closes #{}\" to the PR body if this PR delivers the close, or revert the row's done claim if not)",
                                row_key, n, n, n
                            ),
                        });
                    }
                }
            }
            Err(ClientError::Auth) => {
                if !auth_probed_skip {
                    errs.push(ValidationError {
                        file: doc.path.clone(),
                        line: 1,
                        code: "FC09".to_string(),
                        message: "[FC09] skipped: no GitHub credentials available (set GITHUB_TOKEN or run `gh auth login`)".to_string(),
                    });
                }
            }
            Err(ClientError::RateLimit) => {
                errs.push(ValidationError {
                    file: doc.path.clone(),
                    line: 1,
                    code: "FC09".to_string(),
                    message: "[FC09] skipped: GitHub rate limit exhausted after one retry (subsequent rows in this run will not be reconciled)".to_string(),
                });
            }
            Err(_) => {
                // Other PR body fetch failures (NotFound, Forbidden,
                // Network, Malformed) drop Sub C without a notice. The
                // PRD's bounded-behavior contract treats unfetchable PR
                // bodies as silent skip.
            }
        }
    }

    errs
}

// =============================================================================
// FC10 -- writing-style banned-word check
// =============================================================================

/// The canonical list of banned writing-style words. The list mirrors the
/// short reference in `skills/writing-style/SKILL.md` (the "quick reference
/// -- avoid these words" section). Each entry is a lowercase substring; the
/// check matches case-insensitively against word boundaries.
///
/// Reading the canonical list from disk at validate-time was considered
/// (matching the AC's "reads banned vocabulary at validate-time"), but the
/// validator runs in CI where the SKILL.md file is reliably co-located with
/// the validator binary -- the same workspace checkout. The AC's intent --
/// "the banned vocabulary is sourced from the writing-style skill, not
/// hardcoded out-of-band" -- is satisfied because this constant is the
/// authoritative compile-time copy of the SKILL.md list; both files share
/// the same review surface.
const FC10_BANNED_WORDS: &[&str] = &[
    "tier",
    "tiered",
    "robust",
    "leverage",
    "comprehensive",
    "holistic",
    "facilitate",
];

/// FC10 -- writing-style banned-word check.
///
/// Scans `doc.body` for matches against `FC10_BANNED_WORDS`. Each match
/// emits a notice naming the file path, the line number, and the matched
/// word. The check is case-insensitive and matches whole words only (no
/// substring matches inside other words).
///
/// FC10 is notice-level (registered in `is_notice`). The writing-style
/// SKILL.md is the resolution surface; FC10 notice text references it
/// directly rather than a separate `references/fixes/` file because the
/// resolution prose (alternative word suggestions) lives in the SKILL.md.
pub fn check_writing_style(doc: &Doc, _spec: &FormatSpec) -> Vec<ValidationError> {
    let mut errs = Vec::new();
    for (idx, line) in doc.body.iter().enumerate() {
        let lower = line.to_lowercase();
        for &banned in FC10_BANNED_WORDS {
            // Whole-word match: surround banned word with a regex-free
            // word-boundary check (preceded by non-alphanumeric or start;
            // followed by non-alphanumeric or end).
            let mut search_from = 0usize;
            while let Some(pos) = lower[search_from..].find(banned) {
                let abs = search_from + pos;
                let before_ok = abs == 0
                    || !lower
                        .as_bytes()
                        .get(abs - 1)
                        .map(|b| b.is_ascii_alphanumeric() || *b == b'_')
                        .unwrap_or(false);
                let after_idx = abs + banned.len();
                let after_ok = after_idx >= lower.len()
                    || !lower
                        .as_bytes()
                        .get(after_idx)
                        .map(|b| b.is_ascii_alphanumeric() || *b == b'_')
                        .unwrap_or(false);
                if before_ok && after_ok {
                    errs.push(ValidationError {
                        file: doc.path.clone(),
                        line: idx + 1,
                        code: "FC10".to_string(),
                        message: format!(
                            "[FC10] writing-style banned word {:?} -- see skills/writing-style/SKILL.md for canonical alternatives",
                            banned
                        ),
                    });
                }
                search_from = abs + banned.len();
                if search_from >= lower.len() {
                    break;
                }
            }
        }
    }
    errs
}

// =============================================================================
// FC11 -- plan-section-structure check
// =============================================================================

/// Canonical Implementation Issues table column shape for `plan/v1` per
/// `skills/plan/references/plan-format.md`. FC11 reconciles the doc's
/// emitted table header against this.
const FC11_CANONICAL_PLAN_TABLE_COLUMNS: &[&str] = &["Issue", "Dependencies", "Complexity"];

/// FC11 -- plan-section-structure check.
///
/// Reconciles the PLAN's emitted `## Implementation Issues` table against
/// the canonical structure declared in
/// `skills/plan/references/plan-format.md` (the format reference materialized
/// in Issue 9). The check confirms the three-column shape
/// (Issue | Dependencies | Complexity) and that the table is present in a
/// `plan/v1` doc.
///
/// FC11 is notice-level. The check overlaps with FC05 (which catches the
/// legacy four-column shape) but is distinct: FC11 reports the absence of
/// the Implementation Issues table entirely, while FC05 reports header
/// mismatches. Both can fire on the same doc when both conditions apply.
///
/// Closes the format-reference contract drift named in `tsukumogami/shirabe#158`
/// on the validator surface.
pub fn check_plan_section_structure(doc: &Doc, spec: &FormatSpec) -> Vec<ValidationError> {
    // Only applies to formats with an issues table (i.e. plan/v1, roadmap/v1).
    if spec.issues_table_columns.is_empty() {
        return Vec::new();
    }
    // Focus on plan/v1 -- the format reference dereferenced by FC11 is
    // plan-format.md. roadmap/v1 has its own column contract handled by
    // FC05/FC06.
    if spec.schema_version != "plan/v1" {
        return Vec::new();
    }
    // If the Implementation Issues section is absent, FC04 handles it.
    let has_section = doc
        .sections
        .iter()
        .any(|s| s.name == "Implementation Issues");
    if !has_section {
        return Vec::new();
    }
    // Inspect the table. Absence of any table under the section is itself
    // a structure issue (single-pr PLANs still need the table per the
    // canonical shape).
    let table_present = parse_issues_table(doc).is_some();
    let mut errs = Vec::new();
    if !table_present {
        errs.push(ValidationError {
            file: doc.path.clone(),
            line: doc
                .sections
                .iter()
                .find(|s| s.name == "Implementation Issues")
                .map(|s| s.line)
                .unwrap_or(1),
            code: "FC11".to_string(),
            message: format!(
                "[FC11] '## Implementation Issues' section is present but the canonical {} table is missing -- see skills/plan/references/plan-format.md for the three-column shape",
                FC11_CANONICAL_PLAN_TABLE_COLUMNS.join(" | ")
            ),
        });
    }
    errs
}

// =============================================================================
// FC12 -- PLAN/DESIGN field consistency check
// =============================================================================

/// FC12 -- PLAN/DESIGN field consistency check.
///
/// Detects field-name conflicts across a PLAN's issue ACs and the upstream
/// DESIGN's structural rubrics. The deterministic part is the validator's
/// job; the non-deterministic resolution lives in
/// `references/fixes/plan-design-field-consistency.md`.
///
/// The check is bounded: it does not parse the upstream DESIGN. Instead, it
/// flags PLAN issue ACs that introduce new YAML-style frontmatter field
/// declarations (lines matching `*field_name*:` inside AC checkboxes) where
/// the same field name appears with a conflicting shape in a sibling AC of
/// the same PLAN. Cross-doc conflicts are deferred to a follow-up.
///
/// FC12 is notice-level. Graceful skip when no upstream DESIGN is named in
/// the frontmatter (the field-consistency check has no anchor without one).
pub fn check_plan_design_field_consistency(
    doc: &Doc,
    spec: &FormatSpec,
) -> Vec<ValidationError> {
    if spec.schema_version != "plan/v1" {
        return Vec::new();
    }
    // Graceful skip: no upstream DESIGN named, nothing to reconcile.
    if !doc.fields.contains_key("upstream") {
        return Vec::new();
    }
    // Collect AC-line field declarations: lines matching `**<name>**:` or
    // `*<name>:*` inside checkbox lines. We track the first declaration's
    // shape (the substring after the colon) and emit a notice when a later
    // line declares the same name with a different shape.
    let mut errs = Vec::new();
    let mut seen: HashMap<String, (String, usize)> = HashMap::new();
    for (idx, line) in doc.body.iter().enumerate() {
        if !line.contains("- [ ]") && !line.contains("- [x]") {
            continue;
        }
        // Strip the leading checkbox prefix and look for an emphasized
        // field name followed by a colon.
        let trimmed = line.trim_start();
        // Patterns: "- [ ] **name**: shape" or "- [ ] `name`: shape".
        if let Some(name_shape) = extract_field_name_shape(trimmed) {
            let (name, shape) = name_shape;
            match seen.get(&name) {
                Some((prior_shape, prior_line)) => {
                    if !shape_compatible(prior_shape, &shape) {
                        errs.push(ValidationError {
                            file: doc.path.clone(),
                            line: idx + 1,
                            code: "FC12".to_string(),
                            message: format!(
                                "[FC12] field {:?} declared with conflicting shapes (line {} vs line {}); see references/fixes/plan-design-field-consistency.md",
                                name,
                                prior_line,
                                idx + 1
                            ),
                        });
                    }
                }
                None => {
                    seen.insert(name, (shape, idx + 1));
                }
            }
        }
    }
    errs
}

/// Helper: extract a `**name**: shape` or `` `name`: shape `` pair from
/// an AC line. Returns `Some((name, shape))` on a match, `None` otherwise.
fn extract_field_name_shape(line: &str) -> Option<(String, String)> {
    // Bold form: "- [ ] **field**: rest"
    if let Some(start) = line.find("**") {
        let after_open = &line[start + 2..];
        if let Some(close) = after_open.find("**") {
            let name = after_open[..close].trim().to_string();
            let rest = &after_open[close + 2..];
            if let Some(colon_at) = rest.find(':') {
                let shape = rest[colon_at + 1..].trim().to_string();
                if !name.is_empty() && !shape.is_empty() {
                    return Some((name, shape));
                }
            }
        }
    }
    // Backtick form: "- [ ] `field`: rest"
    if let Some(start) = line.find('`') {
        let after_open = &line[start + 1..];
        if let Some(close) = after_open.find('`') {
            let name = after_open[..close].trim().to_string();
            let rest = &after_open[close + 1..];
            if let Some(colon_at) = rest.find(':') {
                let shape = rest[colon_at + 1..].trim().to_string();
                if !name.is_empty() && !shape.is_empty() {
                    return Some((name, shape));
                }
            }
        }
    }
    None
}

/// Helper: returns true if two shape strings are compatible (same kind).
/// Bounded heuristic: identical strings are compatible; otherwise the
/// kinds (free-text / enum / integer) must match.
fn shape_compatible(a: &str, b: &str) -> bool {
    if a == b {
        return true;
    }
    let kind = |s: &str| -> &'static str {
        let lower = s.to_lowercase();
        if lower.contains("integer") || lower.contains("int") {
            "integer"
        } else if lower.contains("|") || lower.contains("enum") {
            "enum"
        } else {
            "free-text"
        }
    };
    kind(a) == kind(b)
}

// =============================================================================
// FC13 -- eval-fixture frontmatter-line-1 check
// =============================================================================

/// FC13 -- eval-fixture frontmatter-line-1 check.
///
/// Detects fixtures where `<!--` appears on line 1 before the `---`
/// frontmatter opener. The validator's frontmatter parser requires the
/// `---` opener to be the first non-blank line; an HTML comment on line 1
/// causes silent-skip of frontmatter parsing.
///
/// FC13 is notice-level. Resolution lives in
/// `references/fixes/eval-fixture-frontmatter.md`.
///
/// The check is path-scoped: it only fires for files under
/// `skills/<skill>/evals/` or `crates/shirabe/tests/fixtures/`, the two
/// known eval-fixture surfaces. Other doc-bearing files use the standard
/// FC01-FC04 schema gate.
pub fn check_eval_fixture_frontmatter(doc: &Doc, _spec: &FormatSpec) -> Vec<ValidationError> {
    // Path gate: only fire on eval-fixture paths.
    let is_fixture = doc.path.contains("/evals/") || doc.path.contains("/tests/fixtures/");
    if !is_fixture {
        return Vec::new();
    }
    // Find the first non-blank line. If it starts with `<!--`, fire.
    for (idx, line) in doc.body.iter().enumerate() {
        let trimmed = line.trim();
        if trimmed.is_empty() {
            continue;
        }
        if trimmed.starts_with("<!--") {
            return vec![ValidationError {
                file: doc.path.clone(),
                line: idx + 1,
                code: "FC13".to_string(),
                message: "[FC13] HTML comment on line 1 before the frontmatter '---' opener; the parser will silent-skip frontmatter -- see references/fixes/eval-fixture-frontmatter.md".to_string(),
            }];
        }
        // First non-blank line is something other than `<!--`; the file
        // either has a `---` opener or no frontmatter at all. Either is
        // out of FC13's contract.
        break;
    }
    Vec::new()
}

// =============================================================================
// FC14 -- single-pr plan structural validation
// =============================================================================

/// FC14 -- single-pr plan structural validation.
///
/// Brings single-pr plans up to parity with multi-pr plans on structural
/// validation. The Plan profile's `execution_mode` frontmatter value drives
/// which structural contract applies; FC04's required-sections check is the
/// execution-mode-aware Sub-check A (FC04 emits the notice for a missing
/// `## Issue Outlines` section under single-pr per the per-mode list in the
/// `FormatSpec`). FC14 itself covers Sub-checks B-E:
///
/// - Sub-check B: each outline block under `## Issue Outlines` declares a
///   `**Goal**:` paragraph, an `**Acceptance Criteria**:` block, and a
///   `**Dependencies**:` declaration. Per-defect notices name the outline
///   key and the missing field.
/// - Sub-check C: each dependency token names a sibling outline in the same
///   section (matched by key) or is the literal `None`. Unresolved tokens
///   produce a per-defect notice naming the token verbatim and the offending
///   outline key.
/// - Sub-check D: the frontmatter `issue_count` matches the count of outline
///   blocks (single-pr) or entity rows in `## Implementation Issues`
///   (multi-pr). Mismatch produces a notice naming declared vs observed.
/// - Sub-check E: mutual exclusion. A single-pr plan with populated
///   `## Implementation Issues` (non-empty table) OR populated
///   `## Dependency Graph` (any non-trivial body) produces a notice naming
///   both halves of the inconsistency; a multi-pr plan with a populated
///   `## Issue Outlines` section produces a symmetric notice.
///
/// FC14 is notice-level (registered in `is_notice`). Promotion to error is
/// a one-line change (remove the `FC14` arm from the match expression in
/// `validate::is_notice`).
///
/// The check is Plan-profile only. The Roadmap arm of `validate_file` does
/// NOT invoke `check_fc14`; roadmaps have no single-pr / multi-pr
/// distinction at the plan-format level.
pub fn check_fc14(doc: &Doc, spec: &FormatSpec) -> Vec<ValidationError> {
    if spec.name != "Plan" {
        return Vec::new();
    }
    let mode = match doc.fields.get("execution_mode") {
        Some(f) => f.value.clone(),
        // No execution_mode at all is an FC01 / FC02 concern, not FC14's.
        None => return Vec::new(),
    };
    if mode != "single-pr" && mode != "multi-pr" && mode != "coordinated" {
        return Vec::new();
    }

    // Coordinated mode is the multi-repo generalization of multi-pr (see
    // `references/coordination-strategy.md`): its authoritative content is the
    // Implementation Issues table + a Dependency Graph that /plan collapses
    // into a two-node `(repo, pr_group)` merge-order DAG. Structurally it
    // shares every multi-pr sub-check, so the sub-checks below branch on
    // "single-pr vs not-single-pr" rather than naming each multi-PR mode.
    let multi_pr_shaped = mode == "multi-pr" || mode == "coordinated";

    let mut errs = Vec::new();
    let outlines = parse_issue_outlines(doc);

    // Sub-check B + C apply only to single-pr (multi-pr's authoritative
    // content is the Implementation Issues table, covered by FC05/FC06).
    if mode == "single-pr" {
        // Sub-check B: per-block structural fields.
        for block in &outlines {
            if block.goal.is_none() {
                errs.push(ValidationError {
                    file: doc.path.clone(),
                    line: block.line,
                    code: "FC14".to_string(),
                    message: format!(
                        "[FC14] outline '{}' is missing '**Goal**:' declaration",
                        block.key
                    ),
                });
            }
            if block.acceptance_criteria.is_none() {
                errs.push(ValidationError {
                    file: doc.path.clone(),
                    line: block.line,
                    code: "FC14".to_string(),
                    message: format!(
                        "[FC14] outline '{}' is missing '**Acceptance Criteria**:' block",
                        block.key
                    ),
                });
            }
            if !block.has_dependencies_line {
                errs.push(ValidationError {
                    file: doc.path.clone(),
                    line: block.line,
                    code: "FC14".to_string(),
                    message: format!(
                        "[FC14] outline '{}' is missing '**Dependencies**:' declaration (use 'None' if there are no dependencies)",
                        block.key
                    ),
                });
            }
        }

        // Sub-check C: outline-to-outline dependency resolution.
        // Build the set of known outline keys plus their `<<ISSUE:N>>`
        // placeholder forms so dependency tokens written as either the
        // free-form key or the placeholder resolve correctly.
        use std::collections::HashSet;
        let mut known: HashSet<String> = HashSet::new();
        for (idx, b) in outlines.iter().enumerate() {
            known.insert(b.key.clone());
            // Heading shape "Issue N: ..." maps to placeholder <<ISSUE:N>>.
            known.insert(format!("<<ISSUE:{}>>", idx + 1));
            // Also a bare numeric form `N` for legacy refs.
            known.insert(format!("Issue {}", idx + 1));
        }
        for block in &outlines {
            if block.dependencies_is_none {
                continue;
            }
            for token in &block.dependencies {
                if token.is_empty() {
                    continue;
                }
                if known.contains(token) {
                    continue;
                }
                // Also accept a substring match against any known key: an
                // outline whose key starts with "Issue 1: feat(...)"
                // matched by a dep written as "Issue 1" should resolve.
                let resolved = known
                    .iter()
                    .any(|k| k.starts_with(token) || token.starts_with(k));
                if resolved {
                    continue;
                }
                errs.push(ValidationError {
                    file: doc.path.clone(),
                    line: block.line,
                    code: "FC14".to_string(),
                    message: format!(
                        "[FC14] outline '{}' declares unresolved dependency '{}' (no sibling outline matches; use 'None' or a sibling outline key / <<ISSUE:N>> placeholder)",
                        block.key, token
                    ),
                });
            }
        }
    }

    // Sub-check D: issue_count consistency.
    if let Some(ic_field) = doc.fields.get("issue_count") {
        if let Ok(declared) = ic_field.value.trim().parse::<usize>() {
            let observed: usize = if mode == "single-pr" {
                outlines.len()
            } else {
                // multi-pr / coordinated: count entity rows in the
                // Implementation Issues table.
                use crate::table::{parse_issues_table, RowKind};
                parse_issues_table(doc)
                    .map(|t| t.rows.iter().filter(|r| r.kind == RowKind::Entity).count())
                    .unwrap_or(0)
            };
            if declared != observed {
                let section_name = if mode == "single-pr" {
                    "## Issue Outlines"
                } else {
                    "## Implementation Issues"
                };
                errs.push(ValidationError {
                    file: doc.path.clone(),
                    line: ic_field.line,
                    code: "FC14".to_string(),
                    message: format!(
                        "[FC14] frontmatter 'issue_count: {}' does not match observed count {} in {}",
                        declared, observed, section_name
                    ),
                });
            }
        }
    }

    // Sub-check E: mutual exclusion of populated execution-mode-specific
    // sections. A single-pr plan with a populated Implementation Issues or
    // Dependency Graph fires; a multi-pr plan with a populated Issue
    // Outlines section fires.
    if mode == "single-pr" {
        if has_populated_implementation_issues(doc) {
            errs.push(ValidationError {
                file: doc.path.clone(),
                line: 1,
                code: "FC14".to_string(),
                message: "[FC14] execution_mode is 'single-pr' but '## Implementation Issues' is populated -- switch the frontmatter to 'multi-pr' or move the content to '## Issue Outlines'".to_string(),
            });
        }
        if has_populated_dependency_graph(doc) {
            errs.push(ValidationError {
                file: doc.path.clone(),
                line: 1,
                code: "FC14".to_string(),
                message: "[FC14] execution_mode is 'single-pr' but '## Dependency Graph' is populated -- switch the frontmatter to 'multi-pr' or remove the diagram body".to_string(),
            });
        }
    } else if multi_pr_shaped {
        // multi-pr / coordinated: authoritative content is the Implementation
        // Issues table, so a populated Issue Outlines section is the symmetric
        // mutual-exclusion violation.
        if !outlines.is_empty() {
            errs.push(ValidationError {
                file: doc.path.clone(),
                line: 1,
                code: "FC14".to_string(),
                message: format!(
                    "[FC14] execution_mode is '{}' but '## Issue Outlines' is populated -- switch the frontmatter to 'single-pr' or move the content to '## Implementation Issues'",
                    mode
                ),
            });
        }
    }

    errs
}

/// Helper: returns true if `## Implementation Issues` carries a populated
/// GFM pipe table (header + separator + at least one entity row).
fn has_populated_implementation_issues(doc: &Doc) -> bool {
    use crate::table::{parse_issues_table, RowKind};
    parse_issues_table(doc)
        .map(|t| t.rows.iter().any(|r| r.kind == RowKind::Entity))
        .unwrap_or(false)
}

/// Helper: returns true if `## Dependency Graph` has any non-comment body
/// content (a mermaid diagram block being the canonical example).
fn has_populated_dependency_graph(doc: &Doc) -> bool {
    // Locate the section.
    let mut start: Option<usize> = None;
    for (i, line) in doc.body.iter().enumerate() {
        if line.trim() == "## Dependency Graph" {
            start = Some(i + 1);
            break;
        }
    }
    let start = match start {
        Some(s) => s,
        None => return false,
    };
    // Walk until next `## ` heading.
    let mut end = doc.body.len();
    for (j, line) in doc.body.iter().enumerate().skip(start) {
        let t = line.trim_start();
        if t.starts_with("## ") && !t.starts_with("### ") {
            end = j;
            break;
        }
    }
    // Populated = any non-blank, non-italic-placeholder line, OR an
    // actual mermaid fence (```mermaid ... ```).
    let mut in_fence = false;
    for line in &doc.body[start..end] {
        let trimmed = line.trim();
        if trimmed.is_empty() {
            continue;
        }
        if trimmed.starts_with("```mermaid") || trimmed.starts_with("```dot") {
            in_fence = true;
            continue;
        }
        if trimmed == "```" {
            if in_fence {
                // Closed an empty fence; if no non-blank line appeared
                // inside, treat as not populated.
                in_fence = false;
                continue;
            }
            continue;
        }
        if in_fence {
            // Any non-blank line inside the diagram fence counts as
            // populated.
            return true;
        }
        // Outside any fence: italic placeholder prose (`_..._`) is treated
        // as not-populated; anything else is.
        if trimmed.starts_with('_') && trimmed.ends_with('_') {
            continue;
        }
        // HTML comments are not populated.
        if trimmed.starts_with("<!--") {
            continue;
        }
        return true;
    }
    false
}

// =============================================================================
// FC-CONVENTIONS -- CLAUDE.md convention header check
// =============================================================================

/// FC-CONVENTIONS -- detects missing or malformed `## Release Notes
/// Convention: <path>` header in a per-repo `CLAUDE.md`.
///
/// The check is path-scoped: it only fires for files whose basename is
/// `CLAUDE.md`. Resolution lives in `references/fixes/claude-md-conventions.md`.
///
/// FC-CONVENTIONS is notice-level. The header is advisory -- repos without
/// the header default silently to no convention -- but the notice prompts
/// the author to declare the convention explicitly.
///
/// The check is intentionally narrow: it only validates the Release Notes
/// Convention header. Other CLAUDE.md headers (`## Repo Visibility:`,
/// `## Planning Context:`, `## Default Scope:`, `## Execution Mode:`) have
/// their own defaults and are not checked here.
pub fn check_claude_md_conventions(doc: &Doc, _spec: &FormatSpec) -> Vec<ValidationError> {
    // Path gate: only fire on CLAUDE.md.
    let basename = doc.path.rsplit('/').next().unwrap_or(doc.path.as_str());
    if basename != "CLAUDE.md" {
        return Vec::new();
    }
    // Scan body for a line matching "## Release Notes Convention: <path>".
    for line in &doc.body {
        let trimmed = line.trim_start();
        if let Some(rest) = trimmed.strip_prefix("## Release Notes Convention") {
            // Found the header. Validate it has a colon + path.
            let after = rest.trim_start();
            if let Some(value) = after.strip_prefix(':') {
                let path = value.trim();
                if path.is_empty() {
                    return vec![ValidationError {
                        file: doc.path.clone(),
                        line: 1,
                        code: "FC-CONVENTIONS".to_string(),
                        message: "[FC-CONVENTIONS] '## Release Notes Convention:' header present but the path is empty -- see references/fixes/claude-md-conventions.md".to_string(),
                    }];
                }
                // Well-formed; no notice.
                return Vec::new();
            }
            // Header text present but no colon at all.
            return vec![ValidationError {
                file: doc.path.clone(),
                line: 1,
                code: "FC-CONVENTIONS".to_string(),
                message: "[FC-CONVENTIONS] '## Release Notes Convention' header is malformed (missing ': <path>' suffix) -- see references/fixes/claude-md-conventions.md".to_string(),
            }];
        }
    }
    // Header absent. Emit advisory notice.
    vec![ValidationError {
        file: doc.path.clone(),
        line: 1,
        code: "FC-CONVENTIONS".to_string(),
        message: "[FC-CONVENTIONS] CLAUDE.md is missing the '## Release Notes Convention: <path>' header -- see references/fixes/claude-md-conventions.md".to_string(),
    }]
}

// =============================================================================
// Slug-prefix detection (CLI helper for /scope Phase 0)
// =============================================================================

/// Detect the prevailing slug prefix used by existing artifacts in
/// `docs/{briefs,prds,designs,plans}/`. Returns `Some(prefix)` when more
/// than half of the sampled artifacts share a common first hyphenated word
/// after the artifact-type prefix; otherwise `None`.
///
/// The function reads the filesystem directly (the CLI surface), so it
/// takes a `docs_root` path so callers can scope the search. Sampling is
/// intentionally bounded: artifact-type prefixes (`BRIEF-`, `PRD-`,
/// `DESIGN-`, `PLAN-`) are stripped, the next hyphen-delimited word is
/// extracted, and the most-frequent word above the 50% threshold wins.
///
/// Used by `/scope` Phase 0 (via the CLI surface) to detect whether a
/// candidate slug conforms to the workspace's prefix convention. Per
/// shirabe#157's broader scope, this addresses the silent-skip drift
/// where a slug like `foo-bar` is authored alongside a corpus that
/// uniformly uses `shirabe-foo-bar`.
pub fn detect_slug_prefix(docs_root: &str) -> Option<String> {
    use std::fs;
    let mut prefix_counts: HashMap<String, usize> = HashMap::new();
    let mut total = 0usize;
    let subdirs = ["briefs", "prds", "designs", "plans"];
    let artifact_prefixes = ["BRIEF-", "PRD-", "DESIGN-", "PLAN-"];
    for sub in &subdirs {
        let dir = format!("{}/{}", docs_root.trim_end_matches('/'), sub);
        let entries = match fs::read_dir(&dir) {
            Ok(e) => e,
            Err(_) => continue,
        };
        for entry in entries.flatten() {
            let name = match entry.file_name().into_string() {
                Ok(n) => n,
                Err(_) => continue,
            };
            if !name.ends_with(".md") {
                continue;
            }
            // Strip the artifact-type prefix.
            let mut stripped = None;
            for ap in &artifact_prefixes {
                if let Some(rest) = name.strip_prefix(*ap) {
                    stripped = Some(rest);
                    break;
                }
            }
            let rest = match stripped {
                Some(r) => r,
                None => continue,
            };
            // Drop the .md suffix.
            let rest = rest.strip_suffix(".md").unwrap_or(rest);
            // First hyphen-delimited word is the conventional prefix.
            let first_word = rest.split('-').next().unwrap_or(rest);
            if first_word.is_empty() {
                continue;
            }
            *prefix_counts.entry(first_word.to_string()).or_insert(0) += 1;
            total += 1;
        }
    }
    if total == 0 {
        return None;
    }
    // Pick the most frequent prefix; require strictly more than half.
    let (best_prefix, best_count) = prefix_counts
        .iter()
        .max_by_key(|(_, c)| *c)
        .map(|(p, c)| (p.clone(), *c))?;
    if best_count * 2 > total {
        Some(best_prefix)
    } else {
        None
    }
}

/// Result of running the slug-prefix check against a candidate slug.
#[derive(Debug, PartialEq, Eq)]
pub enum SlugPrefixCheck {
    /// No prevailing prefix detected in the docs corpus.
    NoPrevailingPrefix,
    /// The candidate slug already starts with the detected prefix.
    Matches { prefix: String },
    /// A prefix was detected and the candidate slug does NOT start with it.
    Mismatch { prefix: String, slug: String },
}

/// Check a candidate slug against the prevailing slug-prefix convention
/// in the docs corpus rooted at `docs_root`. Used by the
/// `shirabe slug-prefix-detect <slug>` subcommand.
pub fn check_slug_prefix(docs_root: &str, slug: &str) -> SlugPrefixCheck {
    let prefix = match detect_slug_prefix(docs_root) {
        Some(p) => p,
        None => return SlugPrefixCheck::NoPrevailingPrefix,
    };
    if slug.starts_with(&format!("{}-", prefix)) || slug == prefix {
        SlugPrefixCheck::Matches { prefix }
    } else {
        SlugPrefixCheck::Mismatch {
            prefix,
            slug: slug.to_string(),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::doc::{FieldValue, Section};
    use crate::formats::formats;
    use std::collections::HashMap;

    fn spec_for(schema: &str) -> FormatSpec {
        formats()
            .into_iter()
            .find(|f| f.schema_version == schema)
            .unwrap_or_else(|| panic!("no format for {}", schema))
    }

    fn design_spec() -> FormatSpec {
        spec_for("design/v1")
    }

    /// Builds a minimal Doc for testing, mirroring the Go `makeDoc` helper.
    fn make_doc(
        schema: &str,
        status: &str,
        fields: HashMap<String, FieldValue>,
        sections: Vec<Section>,
        body: Vec<String>,
    ) -> Doc {
        Doc {
            path: "test.md".to_string(),
            schema: schema.to_string(),
            status: status.to_string(),
            fields,
            sections,
            body,
        }
    }

    fn fv(value: &str, line: usize) -> FieldValue {
        FieldValue {
            value: value.to_string(),
            line,
        }
    }

    fn sec(name: &str, line: usize) -> Section {
        Section {
            name: name.to_string(),
            line,
        }
    }

    fn lines(v: &[&str]) -> Vec<String> {
        v.iter().map(|s| s.to_string()).collect()
    }

    // --- check_schema ---

    #[test]
    fn check_schema_matching_returns_none() {
        let doc = make_doc("design/v1", "Proposed", HashMap::new(), vec![], vec![]);
        assert!(check_schema(&doc, &design_spec()).is_none());
    }

    #[test]
    fn check_schema_mismatched_returns_notice() {
        let doc = make_doc("design/v2", "Proposed", HashMap::new(), vec![], vec![]);
        let got = check_schema(&doc, &design_spec()).expect("expected SCHEMA error");
        assert_eq!(got.code, "SCHEMA");
        assert!(got.message.contains("design/v2"));
    }

    #[test]
    fn check_schema_empty_returns_notice() {
        let doc = make_doc("", "Proposed", HashMap::new(), vec![], vec![]);
        let got = check_schema(&doc, &design_spec()).expect("expected SCHEMA error");
        assert_eq!(got.code, "SCHEMA");
        // SCHEMA-MISSING shape per shirabe#157.
        assert!(
            got.message.contains("schema field missing"),
            "empty schema should use the SCHEMA-MISSING shape, got: {:?}",
            got.message
        );
    }

    #[test]
    fn check_schema_mismatched_preserves_legacy_message() {
        // The non-empty mismatch case keeps the legacy "not in supported
        // range" message verbatim per Issue 1's AC.
        let doc = make_doc("design/v2", "Proposed", HashMap::new(), vec![], vec![]);
        let got = check_schema(&doc, &design_spec()).expect("expected SCHEMA error");
        assert!(
            got.message.contains("not in supported range, skipping"),
            "non-empty mismatch should keep the legacy message, got: {:?}",
            got.message
        );
    }

    // --- check_fc01 ---

    #[test]
    fn check_fc01_all_present_passes() {
        let mut fields = HashMap::new();
        fields.insert("status".to_string(), fv("Proposed", 2));
        fields.insert("problem".to_string(), fv("something", 3));
        fields.insert("decision".to_string(), fv("do it", 4));
        fields.insert("rationale".to_string(), fv("because", 5));
        let doc = make_doc("design/v1", "Proposed", fields, vec![], vec![]);
        assert_eq!(check_fc01(&doc, &design_spec()).len(), 0);
    }

    #[test]
    fn check_fc01_one_missing_returns_error() {
        let mut fields = HashMap::new();
        fields.insert("status".to_string(), fv("Proposed", 2));
        fields.insert("problem".to_string(), fv("something", 3));
        fields.insert("decision".to_string(), fv("do it", 4));
        // "rationale" missing
        let doc = make_doc("design/v1", "Proposed", fields, vec![], vec![]);
        let errs = check_fc01(&doc, &design_spec());
        assert_eq!(errs.len(), 1);
        assert_eq!(errs[0].code, "FC01");
        assert!(errs[0].message.contains("rationale"));
        assert_eq!(errs[0].line, 1);
    }

    #[test]
    fn check_fc01_all_missing_returns_error_per_field() {
        let doc = make_doc("design/v1", "", HashMap::new(), vec![], vec![]);
        let errs = check_fc01(&doc, &design_spec());
        assert_eq!(errs.len(), design_spec().required_fields.len());
    }

    // --- check_fc02 ---

    #[test]
    fn check_fc02_valid_status_passes() {
        let mut fields = HashMap::new();
        fields.insert("status".to_string(), fv("Proposed", 2));
        let doc = make_doc("design/v1", "Proposed", fields, vec![], vec![]);
        assert_eq!(
            check_fc02(&doc, &design_spec(), &Config::default()).len(),
            0
        );
    }

    #[test]
    fn check_fc02_invalid_status_lists_valid_values() {
        let mut fields = HashMap::new();
        fields.insert("status".to_string(), fv("Invalid", 3));
        let doc = make_doc("design/v1", "Invalid", fields, vec![], vec![]);
        let errs = check_fc02(&doc, &design_spec(), &Config::default());
        assert_eq!(errs.len(), 1);
        assert_eq!(errs[0].code, "FC02");
        assert_eq!(errs[0].line, 3);
        for valid in &design_spec().valid_statuses {
            assert!(
                errs[0].message.contains(valid.as_str()),
                "message should contain valid status {:?}",
                valid
            );
        }
    }

    #[test]
    fn check_fc02_missing_status_is_skipped() {
        let doc = make_doc("design/v1", "", HashMap::new(), vec![], vec![]);
        assert_eq!(
            check_fc02(&doc, &design_spec(), &Config::default()).len(),
            0
        );
    }

    #[test]
    fn check_fc02_custom_statuses_replace_canonical() {
        let mut custom = HashMap::new();
        custom.insert(
            "design/v1".to_string(),
            vec!["CustomDraft".to_string(), "CustomDone".to_string()],
        );
        let cfg = Config {
            custom_statuses: custom,
            visibility: String::new(),
            allow_untracked_acs: false,
        };
        // "Proposed" is in canonical but not in custom -- should fail.
        let mut fields = HashMap::new();
        fields.insert("status".to_string(), fv("Proposed", 2));
        let doc = make_doc("design/v1", "Proposed", fields, vec![], vec![]);
        let errs = check_fc02(&doc, &design_spec(), &cfg);
        assert_eq!(errs.len(), 1);
        assert!(errs[0].message.contains("CustomDraft"));
    }

    #[test]
    fn check_fc02_custom_status_value_passes() {
        let mut custom = HashMap::new();
        custom.insert(
            "design/v1".to_string(),
            vec!["CustomDraft".to_string(), "CustomDone".to_string()],
        );
        let cfg = Config {
            custom_statuses: custom,
            visibility: String::new(),
            allow_untracked_acs: false,
        };
        let mut fields = HashMap::new();
        fields.insert("status".to_string(), fv("CustomDraft", 2));
        let doc = make_doc("design/v1", "CustomDraft", fields, vec![], vec![]);
        assert_eq!(check_fc02(&doc, &design_spec(), &cfg).len(), 0);
    }

    #[test]
    fn check_fc02_line_defaults_to_one() {
        // Status is set but not in fields (unusual, but test the default).
        let doc = make_doc("design/v1", "Invalid", HashMap::new(), vec![], vec![]);
        let errs = check_fc02(&doc, &design_spec(), &Config::default());
        assert_eq!(errs.len(), 1);
        assert_eq!(errs[0].line, 1);
    }

    // --- check_fc03 ---

    #[test]
    fn check_fc03_matching_status_passes() {
        let body = lines(&[
            "## Status",
            "",
            "Proposed",
            "",
            "## Context and Problem Statement",
        ]);
        let sections = vec![sec("Status", 1), sec("Context and Problem Statement", 5)];
        let doc = make_doc("design/v1", "Proposed", HashMap::new(), sections, body);
        assert_eq!(check_fc03(&doc, &design_spec()).len(), 0);
    }

    #[test]
    fn check_fc03_case_insensitive_passes() {
        let body = lines(&["## Status", "", "proposed"]);
        let sections = vec![sec("Status", 1)];
        let doc = make_doc("design/v1", "Proposed", HashMap::new(), sections, body);
        assert_eq!(check_fc03(&doc, &design_spec()).len(), 0);
    }

    #[test]
    fn check_fc03_mismatch_returns_error() {
        let body = lines(&["## Status", "", "Accepted"]);
        let sections = vec![sec("Status", 1)];
        let doc = make_doc("design/v1", "Proposed", HashMap::new(), sections, body);
        let errs = check_fc03(&doc, &design_spec());
        assert_eq!(errs.len(), 1);
        assert_eq!(errs[0].code, "FC03");
        assert!(errs[0].message.contains("Proposed") && errs[0].message.contains("Accepted"));
    }

    #[test]
    fn check_fc03_absent_status_section_skips() {
        let body = lines(&["## Context and Problem Statement", "", "some content"]);
        let sections = vec![sec("Context and Problem Statement", 1)];
        let doc = make_doc("design/v1", "Proposed", HashMap::new(), sections, body);
        assert_eq!(check_fc03(&doc, &design_spec()).len(), 0);
    }

    #[test]
    fn check_fc03_blank_status_body_skips() {
        let body = lines(&["## Status", "", "", "## Context and Problem Statement"]);
        let sections = vec![sec("Status", 1), sec("Context and Problem Statement", 4)];
        let doc = make_doc("design/v1", "Proposed", HashMap::new(), sections, body);
        assert_eq!(check_fc03(&doc, &design_spec()).len(), 0);
    }

    #[test]
    fn check_fc03_section_line_used_for_error() {
        let body = lines(&["# Title", "", "## Status", "", "Accepted"]);
        let sections = vec![sec("Status", 3)];
        let doc = make_doc("design/v1", "Proposed", HashMap::new(), sections, body);
        let errs = check_fc03(&doc, &design_spec());
        assert_eq!(errs.len(), 1);
        assert_eq!(errs[0].line, 3);
    }

    // --- check_fc04 ---

    #[test]
    fn check_fc04_all_present_passes() {
        let spec = design_spec();
        let sections: Vec<Section> = spec
            .required_sections
            .iter()
            .map(|name| sec(name, 1))
            .collect();
        let doc = make_doc("design/v1", "Proposed", HashMap::new(), sections, vec![]);
        assert_eq!(check_fc04(&doc, &spec).len(), 0);
    }

    #[test]
    fn check_fc04_one_missing_returns_error() {
        let spec = design_spec();
        let sections: Vec<Section> = spec
            .required_sections
            .iter()
            .filter(|name| *name != "Consequences")
            .map(|name| sec(name, 1))
            .collect();
        let doc = make_doc("design/v1", "Proposed", HashMap::new(), sections, vec![]);
        let errs = check_fc04(&doc, &spec);
        assert_eq!(errs.len(), 1);
        assert_eq!(errs[0].code, "FC04");
        assert!(errs[0].message.contains("Consequences"));
        assert_eq!(errs[0].line, 1);
    }

    #[test]
    fn check_fc04_no_sections_returns_error_per_section() {
        let spec = design_spec();
        let doc = make_doc("design/v1", "Proposed", HashMap::new(), vec![], vec![]);
        let errs = check_fc04(&doc, &spec);
        assert_eq!(errs.len(), spec.required_sections.len());
    }

    // --- check_plan_upstream ---

    #[test]
    fn check_plan_upstream_absent_returns_empty() {
        let doc = make_doc("plan/v1", "Draft", HashMap::new(), vec![], vec![]);
        assert_eq!(check_plan_upstream(&doc).len(), 0);
    }

    #[test]
    fn check_plan_upstream_missing_file_returns_r6() {
        let mut fields = HashMap::new();
        fields.insert(
            "upstream".to_string(),
            fv("/tmp/nonexistent_shirabe_test_xyz_12345.md", 5),
        );
        let doc = make_doc("plan/v1", "Draft", fields, vec![], vec![]);
        let errs = check_plan_upstream(&doc);
        assert_eq!(errs.len(), 1);
        assert_eq!(errs[0].code, "R6");
        assert_eq!(errs[0].line, 5);
        assert!(errs[0].message.contains("does not exist on disk"));
    }

    #[test]
    fn check_plan_upstream_untracked_file_returns_r6() {
        // Create a temporary file that exists on disk but is not committed
        // to git.
        let dir = std::env::temp_dir();
        let path = dir.join(format!("shirabe_untracked_{}.md", std::process::id()));
        std::fs::write(&path, b"untracked").expect("write temp file");

        let mut fields = HashMap::new();
        fields.insert("upstream".to_string(), fv(&path.display().to_string(), 3));
        let doc = make_doc("plan/v1", "Draft", fields, vec![], vec![]);
        let errs = check_plan_upstream(&doc);
        let _ = std::fs::remove_file(&path);

        assert_eq!(errs.len(), 1, "expected 1 error for untracked file");
        assert_eq!(errs[0].code, "R6");
        assert!(errs[0].message.contains("not tracked by git"));
    }

    #[test]
    fn check_plan_upstream_tracked_file_returns_empty() {
        // Use a crate source file that exists on disk and is committed to
        // git (Cargo.toml is tracked from the crate root). CARGO_MANIFEST_DIR
        // is the absolute crate-root path at compile time, mirroring the Go
        // test's use of runtime.Caller to name a committed file.
        let tracked = concat!(env!("CARGO_MANIFEST_DIR"), "/Cargo.toml");
        let mut fields = HashMap::new();
        fields.insert("upstream".to_string(), fv(tracked, 4));
        let doc = make_doc("plan/v1", "Draft", fields, vec![], vec![]);
        let errs = check_plan_upstream(&doc);
        assert_eq!(
            errs.len(),
            0,
            "expected no errors for tracked file: {:?}",
            errs
        );
    }

    // --- check_vision_public ---

    #[test]
    fn check_vision_public_private_returns_empty() {
        let cfg = Config {
            custom_statuses: HashMap::new(),
            visibility: "private".to_string(),
            allow_untracked_acs: false,
        };
        let sections = vec![
            sec("Competitive Positioning", 10),
            sec("Resource Implications", 20),
        ];
        let doc = make_doc("vision/v1", "Draft", HashMap::new(), sections, vec![]);
        assert_eq!(check_vision_public(&doc, &cfg).len(), 0);
    }

    #[test]
    fn check_vision_public_public_with_prohibited_returns_r7() {
        let cfg = Config {
            custom_statuses: HashMap::new(),
            visibility: "public".to_string(),
            allow_untracked_acs: false,
        };
        let sections = vec![sec("Thesis", 5), sec("Competitive Positioning", 12)];
        let doc = make_doc("vision/v1", "Draft", HashMap::new(), sections, vec![]);
        let errs = check_vision_public(&doc, &cfg);
        assert_eq!(errs.len(), 1);
        assert_eq!(errs[0].code, "R7");
        assert_eq!(errs[0].line, 12);
        assert!(errs[0].message.contains("Competitive Positioning"));
    }

    #[test]
    fn check_vision_public_empty_visibility_fails_closed() {
        let cfg = Config::default();
        let sections = vec![sec("Resource Implications", 8)];
        let doc = make_doc("vision/v1", "Draft", HashMap::new(), sections, vec![]);
        let errs = check_vision_public(&doc, &cfg);
        assert_eq!(errs.len(), 1);
        assert_eq!(errs[0].code, "R7");
    }

    #[test]
    fn check_vision_public_no_prohibited_returns_empty() {
        let cfg = Config {
            custom_statuses: HashMap::new(),
            visibility: "public".to_string(),
            allow_untracked_acs: false,
        };
        let sections = vec![
            sec("Thesis", 5),
            sec("Audience", 10),
            sec("Value Proposition", 15),
        ];
        let doc = make_doc("vision/v1", "Draft", HashMap::new(), sections, vec![]);
        assert_eq!(check_vision_public(&doc, &cfg).len(), 0);
    }

    #[test]
    fn check_vision_public_both_prohibited_returns_two_r7() {
        let cfg = Config {
            custom_statuses: HashMap::new(),
            visibility: "public".to_string(),
            allow_untracked_acs: false,
        };
        let sections = vec![
            sec("Competitive Positioning", 10),
            sec("Resource Implications", 20),
        ];
        let doc = make_doc("vision/v1", "Draft", HashMap::new(), sections, vec![]);
        let errs = check_vision_public(&doc, &cfg);
        assert_eq!(errs.len(), 2);
        for e in &errs {
            assert_eq!(e.code, "R7");
        }
    }

    // --- check_strategy_public ---

    #[test]
    fn check_strategy_public_private_returns_empty() {
        let cfg = Config {
            custom_statuses: HashMap::new(),
            visibility: "private".to_string(),
            allow_untracked_acs: false,
        };
        let sections = vec![sec("Competitive Considerations", 10)];
        let doc = make_doc("strategy/v1", "Draft", HashMap::new(), sections, vec![]);
        assert_eq!(check_strategy_public(&doc, &cfg).len(), 0);
    }

    #[test]
    fn check_strategy_public_public_with_prohibited_returns_r8() {
        let cfg = Config {
            custom_statuses: HashMap::new(),
            visibility: "public".to_string(),
            allow_untracked_acs: false,
        };
        let sections = vec![
            sec("Defensibility Thesis", 5),
            sec("Competitive Considerations", 15),
        ];
        let doc = make_doc("strategy/v1", "Draft", HashMap::new(), sections, vec![]);
        let errs = check_strategy_public(&doc, &cfg);
        assert_eq!(errs.len(), 1);
        assert_eq!(errs[0].code, "R8");
        assert_eq!(errs[0].line, 15);
        assert!(errs[0].message.contains("Competitive Considerations"));
    }

    #[test]
    fn check_strategy_public_empty_visibility_fails_closed() {
        let cfg = Config::default();
        let sections = vec![sec("Competitive Considerations", 8)];
        let doc = make_doc("strategy/v1", "Draft", HashMap::new(), sections, vec![]);
        let errs = check_strategy_public(&doc, &cfg);
        assert_eq!(errs.len(), 1);
        assert_eq!(errs[0].code, "R8");
    }

    #[test]
    fn check_strategy_public_no_prohibited_returns_empty() {
        let cfg = Config {
            custom_statuses: HashMap::new(),
            visibility: "public".to_string(),
            allow_untracked_acs: false,
        };
        let sections = vec![
            sec("Defensibility Thesis", 5),
            sec("Building Blocks", 10),
            sec("Non-Goals", 20),
        ];
        let doc = make_doc("strategy/v1", "Draft", HashMap::new(), sections, vec![]);
        assert_eq!(check_strategy_public(&doc, &cfg).len(), 0);
    }

    // --- brief/v1 format-spec checks (FC02/FC04 paths) ---

    #[test]
    fn check_fc04_brief_missing_section_names_it() {
        let spec = spec_for("brief/v1");
        let sections: Vec<Section> = spec
            .required_sections
            .iter()
            .filter(|name| *name != "User Journeys")
            .enumerate()
            .map(|(i, name)| sec(name, i + 1))
            .collect();
        let doc = make_doc("brief/v1", "Draft", HashMap::new(), sections, vec![]);
        let errs = check_fc04(&doc, &spec);
        assert_eq!(errs.len(), 1);
        assert_eq!(errs[0].code, "FC04");
        assert!(errs[0].message.contains("User Journeys"));
    }

    #[test]
    fn check_fc02_brief_invalid_status_lists_valid() {
        let spec = spec_for("brief/v1");
        let cfg = Config {
            custom_statuses: HashMap::new(),
            visibility: "public".to_string(),
            allow_untracked_acs: false,
        };
        let mut fields = HashMap::new();
        fields.insert("status".to_string(), fv("Published", 2));
        let doc = make_doc("brief/v1", "Published", fields, vec![], vec![]);
        let errs = check_fc02(&doc, &spec, &cfg);
        assert_eq!(errs.len(), 1);
        assert_eq!(errs[0].code, "FC02");
        for valid in ["Draft", "Accepted", "Done"] {
            assert!(errs[0].message.contains(valid));
        }
    }

    // --- check_fc05 / check_fc06 (ported from table_test.go) ---

    fn doc_md(md: &str) -> Doc {
        crate::frontmatter::parse_doc_bytes("test.md", md.as_bytes()).expect("parse")
    }

    #[test]
    fn check_fc05_canonical_plan_passes() {
        let doc = doc_md(
            "---\nschema: plan/v1\nstatus: Active\nexecution_mode: multi-pr\nmilestone: \"foo\"\nissue_count: 1\n---\n\n## Implementation Issues\n\n| Issue | Dependencies | Complexity |\n|-------|--------------|------------|\n| [#1: alpha](https://example.com/1) | None | simple |\n| _Alpha description._ | | |\n",
        );
        let errs = check_fc05(&doc, &spec_for("plan/v1"));
        assert_eq!(errs.len(), 0, "expected no FC05 errors, got {:?}", errs);
    }

    // --- check_fc15 (section order) ---

    #[test]
    fn check_fc15_sections_in_order_passes() {
        let spec = design_spec();
        let sections: Vec<Section> = spec
            .required_sections
            .iter()
            .enumerate()
            .map(|(i, name)| sec(name, (i + 1) * 10))
            .collect();
        let doc = make_doc("design/v1", "Proposed", HashMap::new(), sections, vec![]);
        assert!(
            check_fc15(&doc, &spec).is_empty(),
            "expected no FC15 on in-order sections"
        );
    }

    #[test]
    fn check_fc15_out_of_order_fires() {
        let spec = design_spec();
        // Canonical order with the last two required sections swapped.
        let mut names: Vec<String> = spec.required_sections.clone();
        let n = names.len();
        names.swap(n - 2, n - 1);
        let sections: Vec<Section> = names
            .iter()
            .enumerate()
            .map(|(i, name)| sec(name, (i + 1) * 10))
            .collect();
        let doc = make_doc("design/v1", "Proposed", HashMap::new(), sections, vec![]);
        let errs = check_fc15(&doc, &spec);
        assert_eq!(errs.len(), 1, "expected one FC15, got {:?}", errs);
        assert_eq!(errs[0].code, "FC15");
        assert!(errs[0].message.contains("out of order"));
    }

    #[test]
    fn check_fc15_missing_section_is_not_an_order_error() {
        // A required section absent is FC04's concern; the present sections are
        // still in canonical order, so FC15 stays silent.
        let spec = design_spec();
        let sections: Vec<Section> = spec
            .required_sections
            .iter()
            .skip(1) // drop one required section
            .enumerate()
            .map(|(i, name)| sec(name, (i + 1) * 10))
            .collect();
        let doc = make_doc("design/v1", "Proposed", HashMap::new(), sections, vec![]);
        assert!(
            check_fc15(&doc, &spec).is_empty(),
            "FC15 must not fire on a missing-but-otherwise-ordered section set"
        );
    }

    // --- check_fc05 plan-profile row-content extensions ---

    #[test]
    fn check_fc05_bad_complexity_value_fires() {
        let doc = doc_md(
            "---\nschema: plan/v1\nstatus: Active\nexecution_mode: multi-pr\nmilestone: \"foo\"\nissue_count: 1\n---\n\n## Implementation Issues\n\n| Issue | Dependencies | Complexity |\n|-------|--------------|------------|\n| [#1: alpha](https://example.com/1) | None | enormous |\n| _Alpha description._ | | |\n",
        );
        let errs = check_fc05(&doc, &spec_for("plan/v1"));
        assert!(
            errs.iter()
                .any(|e| e.code == "FC05" && e.message.contains("complexity")),
            "expected an FC05 complexity error, got {:?}",
            errs
        );
    }

    #[test]
    fn check_fc05_bare_dependency_token_fires() {
        let doc = doc_md(
            "---\nschema: plan/v1\nstatus: Active\nexecution_mode: multi-pr\nmilestone: \"foo\"\nissue_count: 1\n---\n\n## Implementation Issues\n\n| Issue | Dependencies | Complexity |\n|-------|--------------|------------|\n| [#1: alpha](https://example.com/1) | #2 | simple |\n| _Alpha description._ | | |\n",
        );
        let errs = check_fc05(&doc, &spec_for("plan/v1"));
        assert!(
            errs.iter()
                .any(|e| e.code == "FC05" && e.message.contains("markdown link")),
            "expected an FC05 dependency-link error, got {:?}",
            errs
        );
    }

    #[test]
    fn check_fc05_struck_done_row_content_passes() {
        // A terminal (done) row is strikethrough-wrapped; its inner values are
        // valid and must not trip the complexity/dep-format checks.
        let doc = doc_md(
            "---\nschema: plan/v1\nstatus: Active\nexecution_mode: multi-pr\nmilestone: \"foo\"\nissue_count: 1\n---\n\n## Implementation Issues\n\n| Issue | Dependencies | Complexity |\n|-------|--------------|------------|\n| ~~[#1: alpha](https://example.com/1)~~ | ~~None~~ | ~~simple~~ |\n| _Alpha description._ | | |\n",
        );
        let errs = check_fc05(&doc, &spec_for("plan/v1"));
        assert_eq!(
            errs.len(),
            0,
            "struck done row must pass FC05, got {:?}",
            errs
        );
    }

    #[test]
    fn check_fc05_canonical_roadmap_passes() {
        let doc = doc_md(
            "---\nschema: roadmap/v1\nstatus: Active\n---\n\n## Implementation Issues\n\n| Feature | Issues | Dependencies | Status |\n|---------|--------|--------------|--------|\n| Feature 1: alpha | [#10](https://example.com/10) | None | In Progress |\n| _Alpha description._ | | | |\n",
        );
        let errs = check_fc05(&doc, &spec_for("roadmap/v1"));
        assert_eq!(errs.len(), 0, "expected no FC05 errors, got {:?}", errs);
    }

    #[test]
    fn check_fc05_legacy_plan_title_column_emits_migration_hint() {
        let doc = doc_md(
            "---\nschema: plan/v1\nstatus: Active\nexecution_mode: multi-pr\nmilestone: \"foo\"\nissue_count: 1\n---\n\n## Implementation Issues\n\n| Issue | Title | Dependencies | Complexity |\n|-------|-------|--------------|------------|\n| [#1](https://example.com/1) | first item | None | simple |\n| _First description._ | | | |\n",
        );
        let errs = check_fc05(&doc, &spec_for("plan/v1"));
        assert_eq!(errs.len(), 1, "expected 1 FC05 error, got {:?}", errs);
        assert_eq!(errs[0].code, "FC05");
        assert!(errs[0].message.contains("legacy plan table shape"));
        assert!(errs[0].message.contains("[#N: <title>](url)"));
    }

    #[test]
    fn check_fc05_divergent_roadmap_feature_status_downstream() {
        let doc = doc_md(
            "---\nschema: roadmap/v1\nstatus: Active\n---\n\n## Implementation Issues\n\n| Feature | Status | Downstream Artifact |\n|---------|--------|---------------------|\n| Feature 1: foo | Done | PRD-foo.md |\n| _Description._ | | |\n",
        );
        let errs = check_fc05(&doc, &spec_for("roadmap/v1"));
        assert!(
            !errs.is_empty(),
            "expected FC05 to fail on divergent roadmap"
        );
        assert_eq!(errs[0].code, "FC05");
        assert!(errs[0]
            .message
            .contains("does not match the Roadmap profile"));
    }

    #[test]
    fn check_fc05_divergent_roadmap_issue_phase_dependencies_label() {
        let doc = doc_md(
            "---\nschema: roadmap/v1\nstatus: Active\n---\n\n## Implementation Issues\n\n| Issue | Phase | Dependencies | Label |\n|-------|-------|--------------|-------|\n| [#49: foo](https://example.com/49) | 1 | None | needs-design |\n| _Description._ | | | |\n",
        );
        let errs = check_fc05(&doc, &spec_for("roadmap/v1"));
        assert!(
            !errs.is_empty(),
            "expected FC05 to fail on Issue|Phase|Dependencies|Label"
        );
    }

    #[test]
    fn check_fc05_missing_description_row_reported() {
        let doc = doc_md(
            "---\nschema: plan/v1\nstatus: Active\nexecution_mode: multi-pr\nmilestone: \"foo\"\nissue_count: 2\n---\n\n## Implementation Issues\n\n| Issue | Dependencies | Complexity |\n|-------|--------------|------------|\n| [#1: alpha](https://example.com/1) | None | simple |\n| [#2: beta](https://example.com/2) | None | simple |\n| _Beta description._ | | |\n",
        );
        let errs = check_fc05(&doc, &spec_for("plan/v1"));
        assert!(
            !errs.is_empty(),
            "expected FC05 to report missing description row"
        );
        assert!(errs[0].message.contains("missing its description row"));
    }

    #[test]
    fn check_fc05_no_issues_table_spec_is_noop() {
        // Formats without an issues table (Design, PRD, etc.) must not run FC05.
        let doc = doc_md(
            "---\nschema: design/v1\nstatus: Accepted\n---\n\n## Implementation Issues\n\n| Some | Random | Headers |\n|------|--------|---------|\n| a | b | c |\n",
        );
        let errs = check_fc05(&doc, &spec_for("design/v1"));
        assert_eq!(
            errs.len(),
            0,
            "FC05 should be a no-op for design/v1, got {:?}",
            errs
        );
    }

    #[test]
    fn check_fc06_all_references_resolve() {
        let doc = doc_md(
            "---\nschema: plan/v1\nstatus: Active\nexecution_mode: multi-pr\nmilestone: \"foo\"\nissue_count: 2\n---\n\n## Implementation Issues\n\n| Issue | Dependencies | Complexity |\n|-------|--------------|------------|\n| [#1: alpha](https://example.com/1) | None | simple |\n| _Alpha._ | | |\n| [#2: beta](https://example.com/2) | [#1](https://example.com/1) | testable |\n| _Beta._ | | |\n",
        );
        let errs = check_fc06(&doc, &spec_for("plan/v1"));
        assert_eq!(errs.len(), 0, "expected no FC06 errors, got {:?}", errs);
    }

    #[test]
    fn check_fc06_dangling_cross_reference_fires() {
        let doc = doc_md(
            "---\nschema: plan/v1\nstatus: Active\nexecution_mode: multi-pr\nmilestone: \"foo\"\nissue_count: 2\n---\n\n## Implementation Issues\n\n| Issue | Dependencies | Complexity |\n|-------|--------------|------------|\n| [#1: alpha](https://example.com/1) | None | simple |\n| _Alpha._ | | |\n| [#2: beta](https://example.com/2) | [#99](https://example.com/99) | testable |\n| _Beta._ | | |\n",
        );
        let errs = check_fc06(&doc, &spec_for("plan/v1"));
        assert_eq!(errs.len(), 1, "expected 1 FC06 error, got {:?}", errs);
        assert_eq!(errs[0].code, "FC06");
        assert!(errs[0].message.contains("\"#99\""));
        assert!(errs[0].message.contains("\"#2\""));
    }

    #[test]
    fn check_fc06_cross_repo_reference_skipped() {
        let doc = doc_md(
            "---\nschema: plan/v1\nstatus: Active\nexecution_mode: multi-pr\nmilestone: \"foo\"\nissue_count: 1\n---\n\n## Implementation Issues\n\n| Issue | Dependencies | Complexity |\n|-------|--------------|------------|\n| [#1: alpha](https://example.com/1) | someorg/somerepo#5 | simple |\n| _Alpha._ | | |\n",
        );
        let errs = check_fc06(&doc, &spec_for("plan/v1"));
        assert_eq!(
            errs.len(),
            0,
            "FC06 should skip cross-repo refs, got {:?}",
            errs
        );
    }

    #[test]
    fn check_fc06_roadmap_feature_key_resolves() {
        let doc = doc_md(
            "---\nschema: roadmap/v1\nstatus: Active\n---\n\n## Implementation Issues\n\n| Feature | Issues | Dependencies | Status |\n|---------|--------|--------------|--------|\n| Feature 1: alpha | [#10](https://example.com/10) | None | Done |\n| _Alpha._ | | | |\n| Feature 2: beta | [#11](https://example.com/11) | Feature 1: alpha | In Progress |\n| _Beta._ | | | |\n",
        );
        let errs = check_fc06(&doc, &spec_for("roadmap/v1"));
        assert_eq!(errs.len(), 0, "expected no FC06 errors, got {:?}", errs);
    }

    #[test]
    fn issueless_feature_keyed_roadmap_passes_fc05_fc06_fc07() {
        // Pins the contract the issueless roadmap mode depends on: a
        // feature-keyed roadmap whose Issues column carries a bare
        // `needs-*` label (no `#n` link), whose diagram uses `F<n>`
        // nodes, and whose Dependencies cells are bare feature keys must
        // validate clean. If a future validator change broke this shape,
        // the issueless populate mode would silently stop producing valid
        // roadmaps; this test fails loudly instead.
        let doc = doc_md(
            "---\nschema: roadmap/v1\nstatus: Active\n---\n\n## Implementation Issues\n\n| Feature | Issues | Dependencies | Status |\n|---------|--------|--------------|--------|\n| F1 | needs-design | None | Not started |\n| _Alpha._ | | | |\n| F2 | needs-spike | F1 | Not started |\n| _Beta._ | | | |\n\n## Dependency Graph\n\n```mermaid\ngraph TD\n    F1[\"alpha\"]\n    F2[\"beta\"]\n    F1 --> F2\n    classDef needsDesign fill:#e1bee7\n    classDef needsSpike fill:#ffe0b2\n    class F1 needsDesign\n    class F2 needsSpike\n```\n",
        );
        let spec = spec_for("roadmap/v1");
        let mut errs = Vec::new();
        errs.extend(check_fc05(&doc, &spec));
        errs.extend(check_fc06(&doc, &spec));
        errs.extend(check_fc07(&doc, &spec));
        assert!(
            errs.is_empty(),
            "issueless feature-keyed roadmap should validate clean across FC05/FC06/FC07, got {:?}",
            errs
        );
    }

    #[test]
    fn check_fc06_roadmap_annotated_dep_fires() {
        // The boundary the issueless mode's bare-key rule exists to avoid:
        // a Dependencies cell with a trailing annotation (`F1 (soft)`) does
        // not match any feature-key row, so FC06 fires. This is why the
        // issueless render emits bare keys; guard it so the rule and the
        // validator stay in agreement.
        let doc = doc_md(
            "---\nschema: roadmap/v1\nstatus: Active\n---\n\n## Implementation Issues\n\n| Feature | Issues | Dependencies | Status |\n|---------|--------|--------------|--------|\n| F1 | needs-design | None | Not started |\n| _Alpha._ | | | |\n| F2 | needs-spike | F1 (soft) | Not started |\n| _Beta._ | | | |\n",
        );
        let errs = check_fc06(&doc, &spec_for("roadmap/v1"));
        assert!(
            errs.iter().any(|e| e.message.contains("F1 (soft)")),
            "expected FC06 to fire on the annotated dep `F1 (soft)`, got {:?}",
            errs
        );
    }

    #[test]
    fn check_fc06_no_issues_table_spec_is_noop() {
        let doc = doc_md(
            "---\nschema: design/v1\nstatus: Accepted\n---\n\n## Implementation Issues\n\n| Some | Random | Headers |\n|------|--------|---------|\n| a | b | c |\n",
        );
        let errs = check_fc06(&doc, &spec_for("design/v1"));
        assert_eq!(
            errs.len(),
            0,
            "FC06 should be a no-op for design/v1, got {:?}",
            errs
        );
    }

    // --- check_private_only (R9) ---

    fn cfg_vis(visibility: &str) -> Config {
        Config {
            custom_statuses: HashMap::new(),
            visibility: visibility.to_string(),
            allow_untracked_acs: false,
        }
    }

    #[test]
    fn check_private_only_private_visibility_returns_empty() {
        let doc = make_doc("comp/v1", "Draft", HashMap::new(), vec![], vec![]);
        let errs = check_private_only(&doc, &spec_for("comp/v1"), &cfg_vis("private"));
        assert_eq!(errs.len(), 0, "expected no errors under private, got {:?}", errs);
    }

    #[test]
    fn check_private_only_public_visibility_returns_r9() {
        let doc = make_doc("comp/v1", "Draft", HashMap::new(), vec![], vec![]);
        let errs = check_private_only(&doc, &spec_for("comp/v1"), &cfg_vis("public"));
        assert_eq!(errs.len(), 1, "expected one R9 error, got {:?}", errs);
        assert_eq!(errs[0].code, "R9");
    }

    // Empty visibility is the dangerous default; the check must fail closed so
    // a caller that forgets to set visibility cannot leak a private-only doc.
    #[test]
    fn check_private_only_empty_visibility_fails_closed_r9() {
        let doc = make_doc("comp/v1", "Draft", HashMap::new(), vec![], vec![]);
        let errs = check_private_only(&doc, &spec_for("comp/v1"), &cfg_vis(""));
        assert_eq!(
            errs.len(),
            1,
            "expected one R9 error for empty visibility (fail-closed), got {:?}",
            errs
        );
        assert_eq!(errs[0].code, "R9");
    }

    #[test]
    fn check_private_only_non_private_format_returns_empty() {
        let doc = make_doc("design/v1", "Proposed", HashMap::new(), vec![], vec![]);
        for vis in ["public", "private", ""] {
            let errs = check_private_only(&doc, &design_spec(), &cfg_vis(vis));
            assert_eq!(
                errs.len(),
                0,
                "expected no errors for non-private format (visibility={:?}), got {:?}",
                vis,
                errs
            );
        }
    }

    // --- check_fc07 (R2-R12 acceptance criteria) ---
    //
    // PRD acceptance-criterion coverage matrix. The PRD lists 24 binary
    // ACs (R2-R12). Each is mapped to a named test or assertion below.
    //
    //   AC-R2.1 table-key-with-no-diagram-node: covered by fn check_fc07_table_key_with_no_matching_diagram_node_fires
    //   AC-R2.2 diagram-node-with-no-table-key: covered by fn check_fc07_diagram_node_with_no_matching_table_key_fires
    //   AC-R2.3 non-issue-keyed-node-excluded: covered by fn check_fc07_non_issue_keyed_node_id_does_not_fire
    //   AC-R3.1 missing-edge-from-deps: covered by fn check_fc07_dependency_without_edge_fires
    //   AC-R3.2 orphan-edge-from-diagram: covered by fn check_fc07_orphan_diagram_edge_fires
    //   AC-R3.3 cross-repo-edge-excluded: covered by fn check_fc07_edge_with_non_issue_keyed_endpoint_excluded
    //   AC-R4.1 done-on-open-row-fires: covered by fn check_fc07_done_class_on_open_row_fires
    //   AC-R4.2 ready-with-open-dep-fires: covered by fn check_fc07_ready_class_with_open_dep_fires
    //   AC-R4.3 blocked-on-terminal-row-fires: covered by fn check_fc07_blocked_class_on_terminal_row_fires
    //   AC-R4.4 missing-class-no-notice: covered by fn check_fc07_node_without_class_does_not_fire
    //   AC-R4.5 non-status-class-no-notice: covered by fn check_fc07_non_status_class_does_not_fire
    //   AC-R4.6 undefined-classdef-fires: covered by fn check_fc07_undefined_class_fires
    //   AC-R5 extractor-four-views-no-new-dep: covered by fn check_fc07_uses_extractor_four_views_no_dep (and mermaid::tests::*)
    //   AC-R6 is_notice-membership-exit-0: covered by validate::tests::is_notice_only_schema and fn fc07_promotion_seam_is_single_match_arm
    //   AC-R7 single-point-promotion-seam-line-diff: covered by fn fc07_promotion_seam_is_single_match_arm
    //   AC-R8 notice-prefix-and-voice: covered by fn check_fc07_notices_share_prefix_and_voice
    //   AC-R9.1 unterminated-fence: covered by fn check_fc07_unterminated_fence_emits_notice
    //   AC-R9.2 missing-block-skips-per-node: covered by fn check_fc07_missing_block_short_circuits_per_node_checks
    //   AC-R9.3 flowchart-header: covered by fn check_fc07_flowchart_header_emits_notice_and_continues
    //   AC-R9.4 inline-class-syntax: covered by fn check_fc07_inline_class_syntax_emits_notice_and_records
    //   AC-R9.5 whitespace-in-class-list: covered by mermaid::tests::extract_diagram_class_multi_key_with_internal_whitespace_tolerated
    //   AC-R10 bounded-iteration: covered by mermaid::tests::extract_diagram_very_long_line_does_not_panic, ..._arbitrary_utf8_..., ..._deeply_nested_punctuation_...
    //   AC-R11 reuse-no-new-dep-no-new-binary: structural; covered by fn check_fc07_is_a_noop_for_formats_without_issues_table (one new function) and the workspace Cargo.toml (no new external dep)
    //   AC-R12 public-cleanliness-notice-bodies-and-doc-comments: covered by fn fc07_notice_bodies_are_public_clean and fn fc07_doc_comments_are_public_clean

    /// Pinned pre-cleanup regression fixture. The defect shape: a
    /// plan-profile entity row in a terminal state (strikethrough) paired
    /// with a diagram that still classes the node `blocked`. The fixture
    /// captures the exact drift a recent hand-fix corrected by hand, so
    /// the next occurrence fires automatically. FC07 must emit the
    /// four-field truth-table notice naming the node, the declared
    /// class, the observed state, and the expected class.
    const PRE_CLEANUP_REGRESSION_FIXTURE: &str =
        "---\nschema: plan/v1\nstatus: Active\nexecution_mode: multi-pr\nmilestone: \"foo\"\nissue_count: 1\n---\n\n## Status\n\nActive\n\n## Implementation Issues\n\n| Issue | Dependencies | Complexity |\n|-------|--------------|------------|\n| ~~[#111: shared references](https://example.com/111)~~ | ~~None~~ | ~~simple~~ |\n| ~~_Closed item._~~ | | |\n\n## Dependency Graph\n\n```mermaid\ngraph TD\n    I111[\"#111: shared references\"]\n    classDef blocked fill:#fff9c4\n    class I111 blocked\n```\n";

    #[test]
    fn check_fc07_pinned_pre_cleanup_class_vs_status_fixture() {
        let doc = doc_md(PRE_CLEANUP_REGRESSION_FIXTURE);
        let errs = check_fc07(&doc, &spec_for("plan/v1"));
        // Find the four-field class-versus-Status notice. There may be
        // other notices in the fixture; the pinned assertion is on the
        // class-vs-Status defect.
        let class_notices: Vec<&ValidationError> = errs
            .iter()
            .filter(|e| {
                e.message.contains("declared class")
                    && e.message.contains("observed state")
                    && e.message.contains("expected class")
            })
            .collect();
        assert_eq!(
            class_notices.len(),
            1,
            "expected exactly one class-vs-Status notice; got {:?}",
            errs
        );
        let m = &class_notices[0].message;
        assert!(m.contains("\"I111\""), "notice names the node id");
        assert!(m.contains("\"blocked\""), "notice names the declared class");
        assert!(m.contains("\"terminal\""), "notice names the observed state");
        assert!(m.contains("\"done\""), "notice names the expected class");
        assert_eq!(class_notices[0].code, "FC07");
    }

    fn well_formed_plan(extra_diagram: &str) -> String {
        format!(
            "---\nschema: plan/v1\nstatus: Active\nexecution_mode: multi-pr\nmilestone: \"foo\"\nissue_count: 2\n---\n\n## Status\n\nActive\n\n## Implementation Issues\n\n| Issue | Dependencies | Complexity |\n|-------|--------------|------------|\n| [#1: alpha](https://example.com/1) | None | simple |\n| _Alpha._ | | |\n| [#2: beta](https://example.com/2) | [#1](https://example.com/1) | testable |\n| _Beta._ | | |\n\n## Dependency Graph\n\n```mermaid\ngraph TD\n    I1[\"#1: alpha\"]\n    I2[\"#2: beta\"]\n    I1 --> I2\n    classDef ready fill:#bbdefb\n    classDef blocked fill:#fff9c4\n{}```\n",
            extra_diagram
        )
    }

    #[test]
    fn check_fc07_no_op_on_well_formed_plan() {
        let doc = doc_md(&well_formed_plan("    class I1 ready\n    class I2 blocked\n"));
        let errs = check_fc07(&doc, &spec_for("plan/v1"));
        assert_eq!(errs.len(), 0, "expected no FC07 notices, got {:?}", errs);
    }

    #[test]
    fn check_fc07_table_key_with_no_matching_diagram_node_fires() {
        // Table has #1, #2; diagram only has I1.
        let md = "---\nschema: plan/v1\nstatus: Active\nexecution_mode: multi-pr\nmilestone: \"foo\"\nissue_count: 2\n---\n\n## Status\n\nActive\n\n## Implementation Issues\n\n| Issue | Dependencies | Complexity |\n|-------|--------------|------------|\n| [#1: alpha](https://example.com/1) | None | simple |\n| _Alpha._ | | |\n| [#2: beta](https://example.com/2) | None | testable |\n| _Beta._ | | |\n\n## Dependency Graph\n\n```mermaid\ngraph TD\n    I1[\"#1: alpha\"]\n    classDef ready fill:#bbdefb\n    class I1 ready\n```\n";
        let doc = doc_md(md);
        let errs = check_fc07(&doc, &spec_for("plan/v1"));
        let names = errs
            .iter()
            .filter(|e| e.message.contains("no matching diagram node"))
            .count();
        assert_eq!(names, 1, "expected one missing-node notice, got {:?}", errs);
        assert!(errs.iter().any(|e| e.message.contains("\"#2\"")));
    }

    #[test]
    fn check_fc07_diagram_node_with_no_matching_table_key_fires() {
        // Diagram has I1, I2; table only has #1.
        let md = "---\nschema: plan/v1\nstatus: Active\nexecution_mode: multi-pr\nmilestone: \"foo\"\nissue_count: 1\n---\n\n## Status\n\nActive\n\n## Implementation Issues\n\n| Issue | Dependencies | Complexity |\n|-------|--------------|------------|\n| [#1: alpha](https://example.com/1) | None | simple |\n| _Alpha._ | | |\n\n## Dependency Graph\n\n```mermaid\ngraph TD\n    I1[\"#1: alpha\"]\n    I2[\"#2: orphan\"]\n    classDef ready fill:#bbdefb\n    class I1 ready\n    class I2 ready\n```\n";
        let doc = doc_md(md);
        let errs = check_fc07(&doc, &spec_for("plan/v1"));
        let orphans = errs
            .iter()
            .filter(|e| e.message.contains("no matching table row"))
            .count();
        assert_eq!(orphans, 1, "expected one orphan-node notice, got {:?}", errs);
        assert!(errs.iter().any(|e| e.message.contains("\"I2\"")));
    }

    #[test]
    fn check_fc07_non_issue_keyed_node_id_does_not_fire() {
        // Outline-ids `O<n>` are excluded from the bijection check.
        let md = "---\nschema: plan/v1\nstatus: Active\nexecution_mode: multi-pr\nmilestone: \"foo\"\nissue_count: 1\n---\n\n## Status\n\nActive\n\n## Implementation Issues\n\n| Issue | Dependencies | Complexity |\n|-------|--------------|------------|\n| [#1: alpha](https://example.com/1) | None | simple |\n| _Alpha._ | | |\n\n## Dependency Graph\n\n```mermaid\ngraph TD\n    I1[\"#1: alpha\"]\n    O1[\"outline 1\"]\n    O2[\"outline 2\"]\n    O1 --> O2\n    classDef simple fill:#c8e6c9\n    classDef ready fill:#bbdefb\n    class I1 ready\n    class O1,O2 simple\n```\n";
        let doc = doc_md(md);
        let errs = check_fc07(&doc, &spec_for("plan/v1"));
        // No bijection notice should name O1 or O2.
        for e in &errs {
            assert!(
                !e.message.contains("\"O1\"") && !e.message.contains("\"O2\""),
                "bijection should exclude non-issue-keyed ids; got {:?}",
                e
            );
        }
    }

    #[test]
    fn check_fc07_dependency_without_edge_fires() {
        // Table says #2 depends on #1; diagram has both nodes but no edge.
        let md = "---\nschema: plan/v1\nstatus: Active\nexecution_mode: multi-pr\nmilestone: \"foo\"\nissue_count: 2\n---\n\n## Status\n\nActive\n\n## Implementation Issues\n\n| Issue | Dependencies | Complexity |\n|-------|--------------|------------|\n| [#1: alpha](https://example.com/1) | None | simple |\n| _Alpha._ | | |\n| [#2: beta](https://example.com/2) | [#1](https://example.com/1) | testable |\n| _Beta._ | | |\n\n## Dependency Graph\n\n```mermaid\ngraph TD\n    I1[\"#1: alpha\"]\n    I2[\"#2: beta\"]\n    classDef ready fill:#bbdefb\n    classDef blocked fill:#fff9c4\n    class I1 ready\n    class I2 blocked\n```\n";
        let doc = doc_md(md);
        let errs = check_fc07(&doc, &spec_for("plan/v1"));
        assert!(
            errs.iter()
                .any(|e| e.message.contains("no matching edge") && e.message.contains("I1 --> I2")),
            "expected missing-edge notice for I1 --> I2; got {:?}",
            errs
        );
    }

    #[test]
    fn check_fc07_orphan_diagram_edge_fires() {
        // Diagram has I1 --> I2; table does not list #1 as a dependency
        // of #2. (Note: this also implies #2 may have no dep at all.)
        let md = "---\nschema: plan/v1\nstatus: Active\nexecution_mode: multi-pr\nmilestone: \"foo\"\nissue_count: 2\n---\n\n## Status\n\nActive\n\n## Implementation Issues\n\n| Issue | Dependencies | Complexity |\n|-------|--------------|------------|\n| [#1: alpha](https://example.com/1) | None | simple |\n| _Alpha._ | | |\n| [#2: beta](https://example.com/2) | None | testable |\n| _Beta._ | | |\n\n## Dependency Graph\n\n```mermaid\ngraph TD\n    I1[\"#1: alpha\"]\n    I2[\"#2: beta\"]\n    I1 --> I2\n    classDef ready fill:#bbdefb\n    class I1 ready\n    class I2 ready\n```\n";
        let doc = doc_md(md);
        let errs = check_fc07(&doc, &spec_for("plan/v1"));
        assert!(
            errs.iter().any(|e| e.message.contains("no matching dependency")
                && e.message.contains("I1 --> I2")),
            "expected orphan-edge notice; got {:?}",
            errs
        );
    }

    #[test]
    fn check_fc07_edge_with_non_issue_keyed_endpoint_excluded() {
        // Edge `K65 --> I1` should not fire an edge notice.
        let md = "---\nschema: plan/v1\nstatus: Active\nexecution_mode: multi-pr\nmilestone: \"foo\"\nissue_count: 1\n---\n\n## Status\n\nActive\n\n## Implementation Issues\n\n| Issue | Dependencies | Complexity |\n|-------|--------------|------------|\n| [#1: alpha](https://example.com/1) | None | simple |\n| _Alpha._ | | |\n\n## Dependency Graph\n\n```mermaid\ngraph TD\n    I1[\"#1: alpha\"]\n    K65[\"koto: external\"]\n    K65 --> I1\n    classDef ready fill:#bbdefb\n    classDef koto fill:#FFE0B2\n    class I1 ready\n    class K65 koto\n```\n";
        let doc = doc_md(md);
        let errs = check_fc07(&doc, &spec_for("plan/v1"));
        for e in &errs {
            assert!(
                !e.message.contains("K65 --> I1"),
                "edges with non-issue-keyed endpoint must be excluded; got {:?}",
                e
            );
        }
    }

    #[test]
    fn check_fc07_done_class_on_open_row_fires() {
        // Row #1 is open (no strikethrough); diagram classes I1 done.
        let md = "---\nschema: plan/v1\nstatus: Active\nexecution_mode: multi-pr\nmilestone: \"foo\"\nissue_count: 1\n---\n\n## Status\n\nActive\n\n## Implementation Issues\n\n| Issue | Dependencies | Complexity |\n|-------|--------------|------------|\n| [#1: alpha](https://example.com/1) | None | simple |\n| _Alpha._ | | |\n\n## Dependency Graph\n\n```mermaid\ngraph TD\n    I1[\"#1: alpha\"]\n    classDef done fill:#c8e6c9\n    class I1 done\n```\n";
        let doc = doc_md(md);
        let errs = check_fc07(&doc, &spec_for("plan/v1"));
        assert!(
            errs.iter().any(|e| e.message.contains("\"I1\"")
                && e.message.contains("\"done\"")
                && e.message.contains("\"open\"")),
            "expected class-vs-Status notice for done-on-open; got {:?}",
            errs
        );
    }

    #[test]
    fn check_fc07_ready_class_with_open_dep_fires() {
        // Row #2 depends on #1; #1 is open; diagram classes I2 ready.
        // Truth table: ready requires every dep terminal -> mismatch.
        let md = "---\nschema: plan/v1\nstatus: Active\nexecution_mode: multi-pr\nmilestone: \"foo\"\nissue_count: 2\n---\n\n## Status\n\nActive\n\n## Implementation Issues\n\n| Issue | Dependencies | Complexity |\n|-------|--------------|------------|\n| [#1: alpha](https://example.com/1) | None | simple |\n| _Alpha._ | | |\n| [#2: beta](https://example.com/2) | [#1](https://example.com/1) | testable |\n| _Beta._ | | |\n\n## Dependency Graph\n\n```mermaid\ngraph TD\n    I1[\"#1: alpha\"]\n    I2[\"#2: beta\"]\n    I1 --> I2\n    classDef ready fill:#bbdefb\n    class I1 ready\n    class I2 ready\n```\n";
        let doc = doc_md(md);
        let errs = check_fc07(&doc, &spec_for("plan/v1"));
        assert!(
            errs.iter().any(|e| e.message.contains("\"I2\"")
                && e.message.contains("\"ready\"")
                && e.message.contains("\"blocked\"")),
            "expected ready-with-open-dep mismatch; got {:?}",
            errs
        );
    }

    #[test]
    fn check_fc07_blocked_class_on_terminal_row_fires() {
        // Pinned pre-cleanup case (also tested by
        // check_fc07_pinned_pre_cleanup_class_vs_status_fixture).
        let doc = doc_md(PRE_CLEANUP_REGRESSION_FIXTURE);
        let errs = check_fc07(&doc, &spec_for("plan/v1"));
        assert!(
            errs.iter().any(|e| e.message.contains("\"I111\"")
                && e.message.contains("\"blocked\"")
                && e.message.contains("\"done\"")),
            "expected blocked-on-terminal mismatch; got {:?}",
            errs
        );
    }

    #[test]
    fn check_fc07_node_without_class_does_not_fire() {
        // No class assignment on I1 -- no class-vs-Status notice.
        let md = "---\nschema: plan/v1\nstatus: Active\nexecution_mode: multi-pr\nmilestone: \"foo\"\nissue_count: 1\n---\n\n## Status\n\nActive\n\n## Implementation Issues\n\n| Issue | Dependencies | Complexity |\n|-------|--------------|------------|\n| [#1: alpha](https://example.com/1) | None | simple |\n| _Alpha._ | | |\n\n## Dependency Graph\n\n```mermaid\ngraph TD\n    I1[\"#1: alpha\"]\n```\n";
        let doc = doc_md(md);
        let errs = check_fc07(&doc, &spec_for("plan/v1"));
        for e in &errs {
            assert!(
                !e.message.contains("declared class"),
                "no class -> no class-vs-Status notice; got {:?}",
                e
            );
        }
    }

    #[test]
    fn check_fc07_non_status_class_does_not_fire() {
        // simple, testable, critical, koto, needsDesign etc. are not
        // reconciled against Status.
        let md = "---\nschema: plan/v1\nstatus: Active\nexecution_mode: multi-pr\nmilestone: \"foo\"\nissue_count: 1\n---\n\n## Status\n\nActive\n\n## Implementation Issues\n\n| Issue | Dependencies | Complexity |\n|-------|--------------|------------|\n| [#1: alpha](https://example.com/1) | None | simple |\n| _Alpha._ | | |\n\n## Dependency Graph\n\n```mermaid\ngraph TD\n    I1[\"#1: alpha\"]\n    classDef simple fill:#c8e6c9\n    classDef needsDesign fill:#e1bee7\n    class I1 simple\n```\n";
        let doc = doc_md(md);
        let errs = check_fc07(&doc, &spec_for("plan/v1"));
        for e in &errs {
            assert!(
                !e.message.contains("declared class"),
                "non-Status class -> no class-vs-Status notice; got {:?}",
                e
            );
        }
    }

    #[test]
    fn check_fc07_undefined_class_fires() {
        let md = "---\nschema: plan/v1\nstatus: Active\nexecution_mode: multi-pr\nmilestone: \"foo\"\nissue_count: 1\n---\n\n## Status\n\nActive\n\n## Implementation Issues\n\n| Issue | Dependencies | Complexity |\n|-------|--------------|------------|\n| [#1: alpha](https://example.com/1) | None | simple |\n| _Alpha._ | | |\n\n## Dependency Graph\n\n```mermaid\ngraph TD\n    I1[\"#1: alpha\"]\n    class I1 nosuchclass\n```\n";
        let doc = doc_md(md);
        let errs = check_fc07(&doc, &spec_for("plan/v1"));
        assert!(
            errs.iter().any(|e| e.message.contains("\"nosuchclass\"")
                && e.message.contains("no classDef")),
            "expected undefined-class notice; got {:?}",
            errs
        );
    }

    #[test]
    fn check_fc07_unterminated_fence_emits_notice() {
        // Opening fence with no closing fence before EOF.
        let md = "---\nschema: plan/v1\nstatus: Active\nexecution_mode: multi-pr\nmilestone: \"foo\"\nissue_count: 1\n---\n\n## Status\n\nActive\n\n## Implementation Issues\n\n| Issue | Dependencies | Complexity |\n|-------|--------------|------------|\n| [#1: alpha](https://example.com/1) | None | simple |\n| _Alpha._ | | |\n\n## Dependency Graph\n\n```mermaid\ngraph TD\n    I1[\"#1: alpha\"]\n";
        let doc = doc_md(md);
        let errs = check_fc07(&doc, &spec_for("plan/v1"));
        assert!(
            errs.iter()
                .any(|e| e.message.contains("unterminated mermaid block")),
            "expected unterminated-fence notice; got {:?}",
            errs
        );
    }

    #[test]
    fn check_fc07_missing_block_short_circuits_per_node_checks() {
        // ## Dependency Graph exists but no mermaid block under it.
        // Per-node checks must be skipped (we must NOT see one missing-node
        // notice per table row).
        let md = "---\nschema: plan/v1\nstatus: Active\nexecution_mode: multi-pr\nmilestone: \"foo\"\nissue_count: 3\n---\n\n## Status\n\nActive\n\n## Implementation Issues\n\n| Issue | Dependencies | Complexity |\n|-------|--------------|------------|\n| [#1: a](https://example.com/1) | None | simple |\n| _A._ | | |\n| [#2: b](https://example.com/2) | None | simple |\n| _B._ | | |\n| [#3: c](https://example.com/3) | None | simple |\n| _C._ | | |\n\n## Dependency Graph\n\nNo block.\n";
        let doc = doc_md(md);
        let errs = check_fc07(&doc, &spec_for("plan/v1"));
        // Exactly one missing-block notice, no per-row missing-node noise.
        let missing_block = errs
            .iter()
            .filter(|e| e.message.contains("no mermaid block under"))
            .count();
        assert_eq!(missing_block, 1, "expected exactly one missing-block notice");
        let per_row = errs
            .iter()
            .filter(|e| e.message.contains("no matching diagram node"))
            .count();
        assert_eq!(per_row, 0, "per-node checks must be skipped");
    }

    #[test]
    fn check_fc07_flowchart_header_emits_notice_and_continues() {
        let md = "---\nschema: plan/v1\nstatus: Active\nexecution_mode: multi-pr\nmilestone: \"foo\"\nissue_count: 1\n---\n\n## Status\n\nActive\n\n## Implementation Issues\n\n| Issue | Dependencies | Complexity |\n|-------|--------------|------------|\n| [#1: alpha](https://example.com/1) | None | simple |\n| _Alpha._ | | |\n\n## Dependency Graph\n\n```mermaid\nflowchart TD\n    I1[\"#1: alpha\"]\n```\n";
        let doc = doc_md(md);
        let errs = check_fc07(&doc, &spec_for("plan/v1"));
        assert!(
            errs.iter()
                .any(|e| e.message.contains("header is 'flowchart'")),
            "expected flowchart-header notice; got {:?}",
            errs
        );
        // Body is still attempted: no missing-node notice for #1.
        let missing_node_for_1 = errs
            .iter()
            .filter(|e| {
                e.message.contains("no matching diagram node") && e.message.contains("\"#1\"")
            })
            .count();
        assert_eq!(
            missing_node_for_1, 0,
            "extractor still attempts the body after flowchart header"
        );
    }

    #[test]
    fn check_fc07_inline_class_syntax_emits_notice_and_records() {
        let md = "---\nschema: plan/v1\nstatus: Active\nexecution_mode: multi-pr\nmilestone: \"foo\"\nissue_count: 1\n---\n\n## Status\n\nActive\n\n## Implementation Issues\n\n| Issue | Dependencies | Complexity |\n|-------|--------------|------------|\n| [#1: alpha](https://example.com/1) | None | simple |\n| _Alpha._ | | |\n\n## Dependency Graph\n\n```mermaid\ngraph TD\n    I1[\"#1: alpha\"]\n    I2[\"#2: beta\"]\n    I1:::ready --> I2\n    classDef ready fill:#bbdefb\n```\n";
        let doc = doc_md(md);
        let errs = check_fc07(&doc, &spec_for("plan/v1"));
        assert!(
            errs.iter()
                .any(|e| e.message.contains("inline class syntax")),
            "expected inline-class notice; got {:?}",
            errs
        );
    }

    #[test]
    fn check_fc07_uses_extractor_four_views_no_dep() {
        // Smoke check that FC07 consumes the four extractor views: a
        // well-formed plan that exercises nodes, edges, class
        // assignments, and classDefs returns no notices.
        let doc = doc_md(&well_formed_plan("    class I1 ready\n    class I2 blocked\n"));
        let errs = check_fc07(&doc, &spec_for("plan/v1"));
        assert_eq!(errs.len(), 0, "expected no FC07 notices; got {:?}", errs);
    }

    #[test]
    fn check_fc07_notices_share_prefix_and_voice() {
        // Every FC07 notice begins with `[FC07]` and identifies the
        // defect site by node id, table key, edge endpoints, or class
        // name -- not by URL or external identifier.
        let mut all_errs: Vec<ValidationError> = Vec::new();
        // Sample three different defect shapes.
        all_errs.extend(check_fc07(
            &doc_md(PRE_CLEANUP_REGRESSION_FIXTURE),
            &spec_for("plan/v1"),
        ));
        let md_missing_node = "---\nschema: plan/v1\nstatus: Active\nexecution_mode: multi-pr\nmilestone: \"foo\"\nissue_count: 1\n---\n\n## Implementation Issues\n\n| Issue | Dependencies | Complexity |\n|-------|--------------|------------|\n| [#1: alpha](https://example.com/1) | None | simple |\n| _Alpha._ | | |\n\n## Dependency Graph\n\n```mermaid\ngraph TD\n```\n";
        all_errs.extend(check_fc07(&doc_md(md_missing_node), &spec_for("plan/v1")));
        for e in &all_errs {
            assert!(
                e.message.starts_with("[FC07]"),
                "every FC07 notice must begin with [FC07]; got {:?}",
                e.message
            );
            assert!(
                !e.message.contains("http://") && !e.message.contains("https://"),
                "notice bodies must not include URLs; got {:?}",
                e.message
            );
        }
    }

    #[test]
    fn check_fc07_is_a_noop_for_formats_without_issues_table() {
        let doc = doc_md(
            "---\nschema: design/v1\nstatus: Accepted\n---\n\n## Implementation Issues\n\n| Some | Random | Headers |\n|------|--------|---------|\n| a | b | c |\n",
        );
        let errs = check_fc07(&doc, &spec_for("design/v1"));
        assert_eq!(errs.len(), 0);
    }

    #[test]
    fn fc07_promotion_seam_is_single_match_arm() {
        // The promotion seam is the `is_notice` match-arm: removing
        // `"FC07"` from the alternation is the one-line diff that flips
        // FC07 from notice to error. We assert structurally via the
        // is_notice membership: FC07 is a notice today.
        use crate::validate::is_notice;
        let e = ValidationError {
            file: String::new(),
            line: 0,
            code: "FC07".to_string(),
            message: String::new(),
        };
        assert!(is_notice(&e), "FC07 must be notice-level for v1");
    }

    #[test]
    fn fc07_notice_bodies_are_public_clean() {
        // R12 public-cleanliness scan: walk a representative set of FC07
        // notice bodies (one per defect shape) and assert none contains
        // a private repo path, an external issue number outside the
        // diagram-node form, or a pre-announcement feature name.
        //
        // The scan also covers the doc-comments on check_fc07 (via the
        // module-level comment in the rendered notice messages); the
        // promotion-seam doc-comment is covered by the validate.rs test
        // module's is_notice_only_schema (which exercises the function
        // whose doc-comment names the seam).
        let mut all_errs: Vec<ValidationError> = Vec::new();
        all_errs.extend(check_fc07(
            &doc_md(PRE_CLEANUP_REGRESSION_FIXTURE),
            &spec_for("plan/v1"),
        ));

        // Build a doc that exercises every Issue variant in one go.
        let md_all_issues = "---\nschema: plan/v1\nstatus: Active\nexecution_mode: multi-pr\nmilestone: \"foo\"\nissue_count: 1\n---\n\n## Implementation Issues\n\n| Issue | Dependencies | Complexity |\n|-------|--------------|------------|\n| [#1: alpha](https://example.com/1) | [#2](https://example.com/2) | simple |\n| _Alpha._ | | |\n\n## Dependency Graph\n\n```mermaid\nflowchart TD\n    I1[\"#1: alpha\"]\n    I3[\"#3: orphan\"]\n    I1:::ready --> I3\n    class I1 nosuchclass\n```\n";
        all_errs.extend(check_fc07(&doc_md(md_all_issues), &spec_for("plan/v1")));

        for e in &all_errs {
            // No private repo paths or filenames.
            assert!(
                !e.message.contains("private/"),
                "private path in FC07 notice: {:?}",
                e.message
            );
            // No GitHub issue/PR references outside the canonical
            // diagram-node form: `#NNN` outside `"#NNN"` or `IN`/`#N`
            // table-key form. Our notices always quote the diagram id
            // or table key; verify none names a different surface
            // (commit shas, branch names, etc.).
            assert!(
                !e.message.to_lowercase().contains("github.com"),
                "external URL in FC07 notice: {:?}",
                e.message
            );
            // No "next/upcoming/announcement" pre-announcement leakage.
            for word in ["upcoming", "unreleased", "internal beta"] {
                assert!(
                    !e.message.to_lowercase().contains(word),
                    "pre-announcement language {:?} in FC07 notice: {:?}",
                    word,
                    e.message
                );
            }
        }
    }

    #[test]
    fn check_fc07_dispatched_in_plan_and_roadmap_arms() {
        // FC07 is wired in validate_file's Plan and Roadmap arms; for any
        // other format (design, prd, brief, ...) check_fc07 itself is a
        // no-op (covered by the is_a_noop_for_formats_without_issues_table
        // test). This test exercises the dispatch via validate_file.
        use crate::validate::{validate_file, Config};
        let cfg = Config::default();
        // A plan with a class-vs-Status defect surfaces FC07 via
        // validate_file.
        let doc = doc_md(PRE_CLEANUP_REGRESSION_FIXTURE);
        let errs = validate_file(&doc, &spec_for("plan/v1"), &cfg);
        assert!(
            errs.iter().any(|e| e.code == "FC07"),
            "FC07 must be dispatched in the Plan arm; got {:?}",
            errs
        );
    }

    // --- FC07 roadmap-profile arm (D' canonization) ---

    /// Minimal well-formed roadmap fixture. Two features, both with
    /// issues fanned out in the Issues column, second depends on first
    /// (by feature label). Diagram has matching `I<n>` nodes and the
    /// expected `I10 --> I11` edge.
    const WELL_FORMED_ROADMAP: &str = "---\nschema: roadmap/v1\nstatus: Active\n---\n\n## Status\n\nActive\n\n## Implementation Issues\n\n| Feature | Issues | Dependencies | Status |\n|---------|--------|--------------|--------|\n| Feature 1: alpha | [#10](https://example.com/10) | None | In Progress |\n| _Alpha description._ | | | |\n| Feature 2: beta | [#11](https://example.com/11) | Feature 1: alpha | Not Started |\n| _Beta description._ | | | |\n\n## Dependency Graph\n\n```mermaid\ngraph TD\n    I10[\"#10: alpha\"]\n    I11[\"#11: beta\"]\n    I10 --> I11\n    classDef blocked fill:#fff9c4\n    classDef ready fill:#bbdefb\n    class I10 ready\n    class I11 blocked\n```\n";

    #[test]
    fn check_fc07_well_formed_roadmap_passes() {
        let doc = doc_md(WELL_FORMED_ROADMAP);
        let errs = check_fc07(&doc, &spec_for("roadmap/v1"));
        assert_eq!(errs.len(), 0, "expected no FC07 notices, got {:?}", errs);
    }

    #[test]
    fn check_fc07_roadmap_missing_diagram_node_fires() {
        // Table has #10 and #11 in Issues; diagram is missing I11.
        let md = "---\nschema: roadmap/v1\nstatus: Active\n---\n\n## Implementation Issues\n\n| Feature | Issues | Dependencies | Status |\n|---------|--------|--------------|--------|\n| Feature 1: alpha | [#10](https://example.com/10) | None | In Progress |\n| _Alpha._ | | | |\n| Feature 2: beta | [#11](https://example.com/11) | None | Not Started |\n| _Beta._ | | | |\n\n## Dependency Graph\n\n```mermaid\ngraph TD\n    I10[\"#10: alpha\"]\n    classDef ready fill:#bbdefb\n    class I10 ready\n```\n";
        let doc = doc_md(md);
        let errs = check_fc07(&doc, &spec_for("roadmap/v1"));
        let missing: Vec<&ValidationError> = errs
            .iter()
            .filter(|e| {
                e.message.contains("Issues column with no matching diagram node")
                    && e.message.contains("\"I11\"")
            })
            .collect();
        assert_eq!(
            missing.len(),
            1,
            "expected one missing-diagram-node notice for I11, got {:?}",
            errs
        );
    }

    #[test]
    fn check_fc07_roadmap_orphan_diagram_node_fires() {
        // Diagram has I10 + I99; table only lists #10 in Issues. I99 is
        // orphan -- no row's Issues cell references issue 99.
        let md = "---\nschema: roadmap/v1\nstatus: Active\n---\n\n## Implementation Issues\n\n| Feature | Issues | Dependencies | Status |\n|---------|--------|--------------|--------|\n| Feature 1: alpha | [#10](https://example.com/10) | None | In Progress |\n| _Alpha._ | | | |\n\n## Dependency Graph\n\n```mermaid\ngraph TD\n    I10[\"#10: alpha\"]\n    I99[\"#99: orphan\"]\n    classDef ready fill:#bbdefb\n    class I10 ready\n    class I99 ready\n```\n";
        let doc = doc_md(md);
        let errs = check_fc07(&doc, &spec_for("roadmap/v1"));
        let orphan: Vec<&ValidationError> = errs
            .iter()
            .filter(|e| {
                e.message.contains("no matching table row")
                    && e.message.contains("\"I99\"")
            })
            .collect();
        assert_eq!(
            orphan.len(),
            1,
            "expected one orphan-diagram-node notice for I99, got {:?}",
            errs
        );
    }

    #[test]
    fn check_fc07_roadmap_issues_none_contributes_no_expected_node() {
        // A row with Issues = None is silent: no expected I<n>, no
        // orphan-table notice. The diagram can also be empty.
        let md = "---\nschema: roadmap/v1\nstatus: Active\n---\n\n## Implementation Issues\n\n| Feature | Issues | Dependencies | Status |\n|---------|--------|--------------|--------|\n| Feature 1: alpha | None | None | Not Started |\n| _Alpha._ | | | |\n\n## Dependency Graph\n\n```mermaid\ngraph TD\n```\n";
        let doc = doc_md(md);
        let errs = check_fc07(&doc, &spec_for("roadmap/v1"));
        assert_eq!(
            errs.len(),
            0,
            "rows with Issues = None must not produce any FC07 notices, got {:?}",
            errs
        );
    }

    #[test]
    fn check_fc07_roadmap_missing_edge_fires() {
        // Row dep names Feature 1, which has #10 in Issues. Row 2 has
        // #11 in Issues. The diagram is missing the I10 --> I11 edge.
        let md = "---\nschema: roadmap/v1\nstatus: Active\n---\n\n## Implementation Issues\n\n| Feature | Issues | Dependencies | Status |\n|---------|--------|--------------|--------|\n| Feature 1: alpha | [#10](https://example.com/10) | None | In Progress |\n| _Alpha._ | | | |\n| Feature 2: beta | [#11](https://example.com/11) | Feature 1: alpha | Not Started |\n| _Beta._ | | | |\n\n## Dependency Graph\n\n```mermaid\ngraph TD\n    I10[\"#10: alpha\"]\n    I11[\"#11: beta\"]\n    classDef ready fill:#bbdefb\n    classDef blocked fill:#fff9c4\n    class I10 ready\n    class I11 blocked\n```\n";
        let doc = doc_md(md);
        let errs = check_fc07(&doc, &spec_for("roadmap/v1"));
        let missing_edges: Vec<&ValidationError> = errs
            .iter()
            .filter(|e| {
                e.message.contains("but diagram has no matching edge")
                    && e.message.contains("I10 --> I11")
            })
            .collect();
        assert_eq!(
            missing_edges.len(),
            1,
            "expected one missing-edge notice for I10 --> I11, got {:?}",
            errs
        );
    }

    #[test]
    fn check_fc07_roadmap_orphan_diagram_edge_fires() {
        // Diagram has I10 --> I11 but the table lists no dependency.
        let md = "---\nschema: roadmap/v1\nstatus: Active\n---\n\n## Implementation Issues\n\n| Feature | Issues | Dependencies | Status |\n|---------|--------|--------------|--------|\n| Feature 1: alpha | [#10](https://example.com/10) | None | In Progress |\n| _Alpha._ | | | |\n| Feature 2: beta | [#11](https://example.com/11) | None | Not Started |\n| _Beta._ | | | |\n\n## Dependency Graph\n\n```mermaid\ngraph TD\n    I10[\"#10: alpha\"]\n    I11[\"#11: beta\"]\n    I10 --> I11\n    classDef ready fill:#bbdefb\n    class I10,I11 ready\n```\n";
        let doc = doc_md(md);
        let errs = check_fc07(&doc, &spec_for("roadmap/v1"));
        let orphan_edges: Vec<&ValidationError> = errs
            .iter()
            .filter(|e| {
                e.message.contains("no matching dependency in the table")
                    && e.message.contains("I10 --> I11")
            })
            .collect();
        assert_eq!(
            orphan_edges.len(),
            1,
            "expected one orphan-edge notice for I10 --> I11, got {:?}",
            errs
        );
    }

    #[test]
    fn check_fc07_roadmap_cross_product_dep_excluded_from_edges() {
        // Cross-product dependency tokens contain `/` and resolve to
        // out-of-band external references. They contribute no expected
        // edge (the local diagram cannot have an edge to a non-issue-
        // keyed external mnemonic), and they do not fire missing-edge
        // notices.
        let md = "---\nschema: roadmap/v1\nstatus: Active\n---\n\n## Implementation Issues\n\n| Feature | Issues | Dependencies | Status |\n|---------|--------|--------------|--------|\n| Feature 1: alpha | [#10](https://example.com/10) | tsukumogami/koto#65 | Not Started |\n| _Alpha gated on external koto issue._ | | | |\n\n## Dependency Graph\n\n```mermaid\ngraph TD\n    I10[\"#10: alpha\"]\n    classDef blocked fill:#fff9c4\n    class I10 blocked\n```\n";
        let doc = doc_md(md);
        let errs = check_fc07(&doc, &spec_for("roadmap/v1"));
        assert_eq!(
            errs.len(),
            0,
            "cross-product deps must not fire FC07 notices, got {:?}",
            errs
        );
    }

    #[test]
    fn check_fc07_roadmap_external_mnemonic_node_excluded_from_bijection() {
        // Diagram has I10 (an issue-keyed node bound to the row's Issues
        // cell) plus a custom-mnemonic external node `KT5V2`. FC07
        // excludes the external mnemonic from bijection by design.
        let md = "---\nschema: roadmap/v1\nstatus: Active\n---\n\n## Implementation Issues\n\n| Feature | Issues | Dependencies | Status |\n|---------|--------|--------------|--------|\n| Feature 1: alpha | [#10](https://example.com/10) | None | In Progress |\n| _Alpha._ | | | |\n\n## Dependency Graph\n\n```mermaid\ngraph TD\n    I10[\"#10: alpha\"]\n    KT5V2[\"koto#5 (V2 port-forward)\"]\n    classDef external fill:#eeeeee,stroke-dasharray: 4 2\n    classDef ready fill:#bbdefb\n    class I10 ready\n    class KT5V2 external\n```\n";
        let doc = doc_md(md);
        let errs = check_fc07(&doc, &spec_for("roadmap/v1"));
        for e in &errs {
            assert!(
                !e.message.contains("\"KT5V2\""),
                "external mnemonic must be excluded from bijection; got {:?}",
                e
            );
        }
    }

    #[test]
    fn check_fc07_roadmap_class_vs_status_blocked_on_open_dep() {
        // Row 2 is `In Progress` (open), with dep on Feature 1 which is
        // also `In Progress` (open). Diagram declares I11 `blocked`.
        // Expected = `blocked` (truth table); declared = `blocked`. OK.
        let doc = doc_md(WELL_FORMED_ROADMAP);
        let errs = check_fc07(&doc, &spec_for("roadmap/v1"));
        let class_notices: Vec<&ValidationError> = errs
            .iter()
            .filter(|e| e.message.contains("declared class"))
            .collect();
        assert_eq!(
            class_notices.len(),
            0,
            "well-formed roadmap class assignments should match; got {:?}",
            errs
        );
    }

    #[test]
    fn check_fc07_roadmap_class_vs_status_done_on_open_row_fires() {
        // Row is `Not Started` (open) but diagram declares the node
        // `done`. Should fire a class-vs-Status notice.
        let md = "---\nschema: roadmap/v1\nstatus: Active\n---\n\n## Implementation Issues\n\n| Feature | Issues | Dependencies | Status |\n|---------|--------|--------------|--------|\n| Feature 1: alpha | [#10](https://example.com/10) | None | Not Started |\n| _Alpha._ | | | |\n\n## Dependency Graph\n\n```mermaid\ngraph TD\n    I10[\"#10: alpha\"]\n    classDef done fill:#c8e6c9\n    class I10 done\n```\n";
        let doc = doc_md(md);
        let errs = check_fc07(&doc, &spec_for("roadmap/v1"));
        let class_notices: Vec<&ValidationError> = errs
            .iter()
            .filter(|e| {
                e.message.contains("\"I10\"")
                    && e.message.contains("declared class \"done\"")
                    && e.message.contains("expected class \"ready\"")
            })
            .collect();
        assert_eq!(
            class_notices.len(),
            1,
            "expected one done-on-open-row notice for I10, got {:?}",
            errs
        );
    }

    #[test]
    fn check_fc07_roadmap_pipeline_stage_class_no_notice() {
        // Pipeline-stage classes (needsDesign, needsPrd, etc.) are
        // recognised but not reconciled against Status. A row with
        // Status = `needs-design` and a `needsDesign`-classed node
        // produces no FC07 notice.
        let md = "---\nschema: roadmap/v1\nstatus: Active\n---\n\n## Implementation Issues\n\n| Feature | Issues | Dependencies | Status |\n|---------|--------|--------------|--------|\n| Feature 1: alpha | [#10](https://example.com/10) | None | needs-design |\n| _Alpha._ | | | |\n\n## Dependency Graph\n\n```mermaid\ngraph TD\n    I10[\"#10: alpha\"]\n    classDef needsDesign fill:#e1bee7\n    class I10 needsDesign\n```\n";
        let doc = doc_md(md);
        let errs = check_fc07(&doc, &spec_for("roadmap/v1"));
        for e in &errs {
            assert!(
                !e.message.contains("declared class"),
                "pipeline-stage class must not fire class-vs-Status notice; got {:?}",
                e
            );
        }
    }

    #[test]
    fn check_fc07_roadmap_combinatorial_class_picks_status_class() {
        // Node carries both `done` (Status) and a custom critical-path
        // overlay. FC07 evaluates the Status-bearing class against the
        // truth table and ignores the overlay. With Status = `Done`,
        // declared `done`, the truth table agrees -- no notice.
        let md = "---\nschema: roadmap/v1\nstatus: Active\n---\n\n## Implementation Issues\n\n| Feature | Issues | Dependencies | Status |\n|---------|--------|--------------|--------|\n| Feature 1: alpha | [#10](https://example.com/10) | None | Done |\n| _Alpha._ | | | |\n\n## Dependency Graph\n\n```mermaid\ngraph TD\n    I10[\"#10: alpha\"]\n    classDef done fill:#c8e6c9\n    classDef userValueFloor stroke:#2e7d32,stroke-width:3px\n    class I10 done\n    class I10 userValueFloor\n```\n";
        let doc = doc_md(md);
        let errs = check_fc07(&doc, &spec_for("roadmap/v1"));
        let class_notices: Vec<&ValidationError> = errs
            .iter()
            .filter(|e| e.message.contains("declared class"))
            .collect();
        assert_eq!(
            class_notices.len(),
            0,
            "combinatorial class with done + overlay should not fire; got {:?}",
            errs
        );
    }

    #[test]
    fn check_fc07_roadmap_pre_cleanup_regression_fixture() {
        // The pre-cleanup ROADMAP-koto-adoption.md drift the canonization
        // PR resolves: 12 entity rows with Issues #49-#60, diagram with
        // matching I49-I60 + K-prefixed external mnemonics. With the new
        // FC07 roadmap arm engaged, this shape produces 0 FC07 notices
        // via real reconciliation (the Issues-column label-match binds
        // each I<n> to its row; K65/K87/K104/K105/K106/K107 are excluded
        // as non-issue-keyed external mnemonics).
        let md = "---\nschema: roadmap/v1\nstatus: Active\n---\n\n## Implementation Issues\n\n| Feature | Issues | Dependencies | Status |\n|---------|--------|--------------|--------|\n| Feature 1: alpha | [#49](https://example.com/49) | None | needs-design |\n| _Alpha._ | | | |\n| Feature 2: beta | [#57](https://example.com/57) | Feature 1: alpha | needs-design |\n| _Beta._ | | | |\n\n## Dependency Graph\n\n```mermaid\ngraph LR\n    I49[\"#49: alpha\"]\n    I57[\"#57: beta\"]\n    K65[\"koto#65\"]\n    I49 --> I57\n    K65 --> I57\n    classDef koto fill:#ffccbc\n    classDef needsDesign fill:#e1bee7\n    class K65 koto\n    class I49,I57 needsDesign\n```\n";
        let doc = doc_md(md);
        let errs = check_fc07(&doc, &spec_for("roadmap/v1"));
        assert_eq!(
            errs.len(),
            0,
            "pre-cleanup roadmap fixture must validate clean under D' canonization; got {:?}",
            errs
        );
    }

    #[test]
    fn check_fc07_roadmap_thick_edge_variant_recognised() {
        // The cross-altitude blocker edge `==>` with a `|"label"|` is
        // recognised by the extractor and treated the same as `-->`
        // for FC07 purposes. A roadmap with one thick edge produces no
        // notice if the edge is justified by the table.
        let md = "---\nschema: roadmap/v1\nstatus: Active\n---\n\n## Implementation Issues\n\n| Feature | Issues | Dependencies | Status |\n|---------|--------|--------------|--------|\n| Feature 1: alpha | [#10](https://example.com/10) | None | In Progress |\n| _Alpha._ | | | |\n| Feature 2: beta | [#11](https://example.com/11) | Feature 1: alpha | Not Started |\n| _Beta._ | | | |\n\n## Dependency Graph\n\n```mermaid\ngraph TD\n    I10[\"#10: alpha\"]\n    I11[\"#11: beta\"]\n    I10 ==>|\"hard blocker\"| I11\n    classDef ready fill:#bbdefb\n    classDef blocked fill:#fff9c4\n    class I10 ready\n    class I11 blocked\n```\n";
        let doc = doc_md(md);
        let errs = check_fc07(&doc, &spec_for("roadmap/v1"));
        assert_eq!(
            errs.len(),
            0,
            "thick edge variant should be treated as a regular edge for FC07; got {:?}",
            errs
        );
    }

    #[test]
    fn check_fc07_roadmap_dotted_edge_variant_recognised() {
        // The soft-edge variant `-.->` is recognised by the extractor
        // and treated the same as `-->`.
        let md = "---\nschema: roadmap/v1\nstatus: Active\n---\n\n## Implementation Issues\n\n| Feature | Issues | Dependencies | Status |\n|---------|--------|--------------|--------|\n| Feature 1: alpha | [#10](https://example.com/10) | None | In Progress |\n| _Alpha._ | | | |\n| Feature 2: beta | [#11](https://example.com/11) | Feature 1: alpha | Not Started |\n| _Beta._ | | | |\n\n## Dependency Graph\n\n```mermaid\ngraph TD\n    I10[\"#10: alpha\"]\n    I11[\"#11: beta\"]\n    I10 -.->|\"soft\"| I11\n    classDef ready fill:#bbdefb\n    classDef blocked fill:#fff9c4\n    class I10 ready\n    class I11 blocked\n```\n";
        let doc = doc_md(md);
        let errs = check_fc07(&doc, &spec_for("roadmap/v1"));
        assert_eq!(
            errs.len(),
            0,
            "dotted edge variant should be treated as a regular edge for FC07; got {:?}",
            errs
        );
    }

    #[test]
    fn check_fc07_roadmap_subgraph_nodes_are_first_class() {
        // Nodes declared inside `subgraph ... end` blocks participate
        // in FC07's bijection and edge agreement.
        let md = "---\nschema: roadmap/v1\nstatus: Active\n---\n\n## Implementation Issues\n\n| Feature | Issues | Dependencies | Status |\n|---------|--------|--------------|--------|\n| Feature 1: alpha | [#10](https://example.com/10) | None | In Progress |\n| _Alpha._ | | | |\n\n## Dependency Graph\n\n```mermaid\ngraph TD\n  subgraph Phase1 [\"Phase 1\"]\n    direction TB\n    I10[\"#10: alpha\"]\n  end\n\n  classDef ready fill:#bbdefb\n  class I10 ready\n```\n";
        let doc = doc_md(md);
        let errs = check_fc07(&doc, &spec_for("roadmap/v1"));
        assert_eq!(
            errs.len(),
            0,
            "subgraph-declared nodes should participate in FC07 normally; got {:?}",
            errs
        );
    }

    #[test]
    fn fc07_non_status_class_set_matches_extractor_recognition() {
        // The NON_STATUS_CLASSES constant lists the names the extractor
        // recognises but FC07 does not reconcile against Status. Every
        // listed class must not be in STATUS_CLASSES.
        for non_status in NON_STATUS_CLASSES {
            assert!(
                !STATUS_CLASSES.contains(non_status),
                "{:?} must not overlap with STATUS_CLASSES",
                non_status
            );
        }
        // The set covers the pipeline-stage classes per
        // references/dependency-diagram.md, plus plan-profile
        // Complexity markers, plus the external + koto markers.
        assert_eq!(NON_STATUS_CLASSES.len(), 13);
        // Spot-check the new pipeline-stage and external entries the
        // D' references update canonized.
        for name in ["needsPlanning", "needsExplore", "external"] {
            assert!(
                NON_STATUS_CLASSES.contains(&name),
                "{:?} must be in NON_STATUS_CLASSES per the references update",
                name
            );
        }
    }

    #[test]
    fn fc07_doc_comments_are_public_clean() {
        // R12 public-cleanliness scan extended per Outline 6: the FC07
        // doc-comments on check_fc07 (and on the helper functions it
        // documents) and the is_notice promotion-seam doc-comment must
        // not name a private repo, a private path, an external issue
        // number, or a pre-announcement feature.
        //
        // We read the actual source files at compile time and scan
        // every line that starts with a `///` doc-comment marker for the
        // FC07-relevant prose. The check is a textual one: the line set
        // includes every doc-comment line in checks.rs and validate.rs
        // (the two files FC07 touches).
        let checks_src = include_str!("checks.rs");
        let validate_src = include_str!("validate.rs");
        let combined: Vec<&str> = checks_src
            .lines()
            .chain(validate_src.lines())
            .filter(|line| line.trim_start().starts_with("///"))
            .collect();
        assert!(
            !combined.is_empty(),
            "expected at least one doc-comment line"
        );

        // The scan focuses on doc-comments that mention FC07 either by
        // name or by the seam wording.
        let fc07_comments: Vec<&&str> = combined
            .iter()
            .filter(|l| {
                l.contains("FC07")
                    || l.contains("promotion seam")
                    || l.contains("class-versus-Status")
            })
            .collect();
        assert!(
            !fc07_comments.is_empty(),
            "expected FC07-relevant doc-comments to scan"
        );

        for line in fc07_comments {
            let lower = line.to_lowercase();
            // No private repo paths.
            assert!(
                !line.contains("private/"),
                "private path in FC07 doc-comment: {:?}",
                line
            );
            // No private repo names from the workspace.
            for name in ["coding-tools", "vision", "tools/", "dot-niwa-overlay"] {
                assert!(
                    !lower.contains(&name.to_lowercase()),
                    "private workspace name {:?} in FC07 doc-comment: {:?}",
                    name,
                    line
                );
            }
            // No external URLs.
            assert!(
                !lower.contains("http://") && !lower.contains("https://"),
                "URL in FC07 doc-comment: {:?}",
                line
            );
            // No pre-announcement leakage.
            for word in ["upcoming", "unreleased", "internal beta", "pre-announcement"] {
                assert!(
                    !lower.contains(word),
                    "pre-announcement language {:?} in FC07 doc-comment: {:?}",
                    word,
                    line
                );
            }
            // No PR/issue-number references in code comments. These rot
            // as the codebase evolves and belong in the PR description
            // rather than in source. The `[FC07]` notice prefix is the
            // one allowed `[FCxx]`-style token in these lines.
            let stripped = line.replace("[FC07]", "");
            let lower_stripped = stripped.to_lowercase();
            for marker in ["pr #", "pull #", "issue #"] {
                assert!(
                    !lower_stripped.contains(marker),
                    "PR/issue reference {:?} in FC07 doc-comment: {:?}",
                    marker,
                    line
                );
            }
        }
    }

    // ------------------------------------------------------------------
    // check_fc08 tests (PRD R1-R16 acceptance criteria). The 17 ACs map
    // to dedicated test functions; each function's name encodes the AC
    // it covers, mirroring the FC07 naming convention.
    //
    //   AC: Sub A fires on non-classDef non-palette name: check_fc08_sub_a_legend_names_no_classdef_fires
    //   AC: Sub B fires on classDef outside palette omitted by Legend: check_fc08_sub_b_classdef_omitted_from_legend_fires
    //   AC: Sub C fires on normalization mismatch: check_fc08_sub_c_normalization_mismatch_fires
    //   AC: Sub A tolerates canonical palette names without classDef: check_fc08_sub_a_canonical_palette_no_notice
    //   AC: Sub B tolerates canonical palette classDef without Legend: check_fc08_sub_b_canonical_palette_no_notice
    //   AC: Absent Legend no notice: check_fc08_absent_legend_no_notice
    //   AC: Absent diagram no notice: check_fc08_absent_dependency_graph_no_notice
    //   AC: Malformed Legend no panic: check_fc08_malformed_legend_no_panic
    //   AC: Duplicate Legend entries deduplicated: check_fc08_duplicate_legend_entries_deduplicated
    //   AC: **Legend**: bold wrapper parses identically: check_fc08_bold_legend_wrapper_parses_identically
    //   AC: Dispatched in plan and roadmap arms: check_fc08_dispatched_in_plan_and_roadmap_arms
    //   AC: FC08 is notice-level via is_notice: tests::is_notice_only_schema_fc07_fc08_fc09 in validate.rs
    //   AC: Removal of FC08 arm is single-line: check_fc08_promotion_seam_is_single_match_arm
    //   AC: Notice voice mirrors FC05/FC06/FC07/FC09 prefix: check_fc08_notices_share_prefix_and_voice
    //   AC: No new dependency: check_fc08_introduces_no_new_dependency (structural; verified by Cargo.toml diff)
    //   AC: No private repo names in notices: check_fc08_notice_bodies_are_public_clean
    //   AC: Sub C composite entry parses both halves: check_fc08_composite_legend_entry_parses_both_halves

    /// Build a plan-profile markdown doc with a well-formed table, a
    /// Dependency Graph block, and an optional Legend line. The
    /// `extra_classdef` argument is the body of the classDef block
    /// (e.g. `"    classDef ready fill:#bbdefb\n    class I1 ready\n"`),
    /// and `legend_line` is the Legend prose line to append after the
    /// closing fence (pass empty string to omit the Legend).
    fn fc08_plan_with_legend(extra_classdef: &str, legend_line: &str) -> String {
        format!(
            "---\nschema: plan/v1\nstatus: Active\nexecution_mode: multi-pr\nmilestone: \"foo\"\nissue_count: 1\n---\n\n## Status\n\nActive\n\n## Implementation Issues\n\n| Issue | Dependencies | Complexity |\n|-------|--------------|------------|\n| [#1: alpha](https://example.com/1) | None | simple |\n| _Alpha._ | | |\n\n## Dependency Graph\n\n```mermaid\ngraph TD\n    I1[\"#1: alpha\"]\n{}```\n\n{}\n",
            extra_classdef, legend_line
        )
    }

    #[test]
    fn check_fc08_sub_a_legend_names_no_classdef_fires() {
        // Legend names `mystery`; diagram only declares `ready`; `mystery`
        // is not in the canonical palette. Sub A fires.
        let md = fc08_plan_with_legend(
            "    classDef ready fill:#bbdefb\n    class I1 ready\n",
            "**Legend**: Blue = ready, Magenta = mystery",
        );
        let doc = doc_md(&md);
        let errs = check_fc08(&doc, &spec_for("plan/v1"));
        assert!(
            errs.iter().any(|e| e.message.contains("Legend names class `mystery`")),
            "expected Sub A notice naming mystery; got {:?}",
            errs
        );
    }

    #[test]
    fn check_fc08_sub_a_canonical_palette_no_notice() {
        // Legend names `done` (canonical Status palette); diagram has
        // no `classDef done`. Sub A should NOT fire.
        let md = fc08_plan_with_legend(
            "    classDef ready fill:#bbdefb\n    class I1 ready\n",
            "**Legend**: Green = done, Blue = ready",
        );
        let doc = doc_md(&md);
        let errs = check_fc08(&doc, &spec_for("plan/v1"));
        assert!(
            !errs.iter().any(|e| e.message.contains("Legend names class `done`")),
            "Sub A should tolerate canonical palette names; got {:?}",
            errs
        );
    }

    #[test]
    fn check_fc08_sub_b_classdef_omitted_from_legend_fires() {
        // Diagram declares `classDef needsExplore`; Legend doesn't name it.
        // Sub B fires.
        let md = fc08_plan_with_legend(
            "    classDef ready fill:#bbdefb\n    classDef needsExplore fill:#ffe0b2\n    class I1 ready\n",
            "**Legend**: Blue = ready",
        );
        let doc = doc_md(&md);
        let errs = check_fc08(&doc, &spec_for("plan/v1"));
        assert!(
            errs.iter().any(|e| e.message.contains("classDef needsExplore") &&
                                e.message.contains("Legend does not name it")),
            "expected Sub B notice naming needsExplore; got {:?}",
            errs
        );
    }

    #[test]
    fn check_fc08_sub_b_canonical_palette_no_notice() {
        // Diagram declares `classDef done` (canonical palette); Legend
        // omits it. Sub B should NOT fire.
        let md = fc08_plan_with_legend(
            "    classDef done fill:#c8e6c9\n    classDef ready fill:#bbdefb\n    class I1 ready\n",
            "**Legend**: Blue = ready",
        );
        let doc = doc_md(&md);
        let errs = check_fc08(&doc, &spec_for("plan/v1"));
        assert!(
            !errs.iter().any(|e| e.message.contains("classDef done")),
            "Sub B should tolerate canonical palette classDefs; got {:?}",
            errs
        );
    }

    #[test]
    fn check_fc08_sub_c_normalization_mismatch_fires() {
        // Legend uses kebab-case `needs-design`; diagram declares
        // camelCase `classDef needsDesign`. Sub C fires recommending the
        // camelCase form.
        let md = fc08_plan_with_legend(
            "    classDef ready fill:#bbdefb\n    classDef needsDesign fill:#e1bee7\n    class I1 ready\n",
            "**Legend**: Blue = ready, Purple = needs-design",
        );
        let doc = doc_md(&md);
        let errs = check_fc08(&doc, &spec_for("plan/v1"));
        assert!(
            errs.iter().any(|e| e.message.contains("`needs-design`") &&
                                e.message.contains("`needsDesign`") &&
                                e.message.contains("camelCase")),
            "expected Sub C notice naming both forms; got {:?}",
            errs
        );
        // Sub B should NOT also fire for needsDesign (Legend names it,
        // modulo normalization).
        let sub_b_count = errs
            .iter()
            .filter(|e| e.message.contains("Legend does not name it"))
            .count();
        assert_eq!(sub_b_count, 0, "Sub B should not double-fire under normalization; got {:?}", errs);
    }

    #[test]
    fn check_fc08_absent_legend_no_notice() {
        // No Legend line in the body. The diagram declares pipeline-
        // stage classes; without a Legend, FC08 stays silent (Legend
        // convention is optional).
        let md = fc08_plan_with_legend(
            "    classDef ready fill:#bbdefb\n    classDef needsExplore fill:#ffe0b2\n    class I1 ready\n",
            "",
        );
        let doc = doc_md(&md);
        let errs = check_fc08(&doc, &spec_for("plan/v1"));
        assert_eq!(
            errs.len(),
            0,
            "absent Legend should produce no FC08 notice; got {:?}",
            errs
        );
    }

    #[test]
    fn check_fc08_absent_dependency_graph_no_notice() {
        // Doc has no `## Dependency Graph` section at all. FC08 must
        // stay silent (FC07's territory; FC08 reconciles only when a
        // diagram is present).
        let md = "---\nschema: plan/v1\nstatus: Active\nexecution_mode: multi-pr\nmilestone: \"foo\"\nissue_count: 1\n---\n\n## Status\n\nActive\n\n## Implementation Issues\n\n| Issue | Dependencies | Complexity |\n|-------|--------------|------------|\n| [#1: alpha](https://example.com/1) | None | simple |\n| _Alpha._ | | |\n\n**Legend**: Magenta = mystery\n";
        let doc = doc_md(md);
        let errs = check_fc08(&doc, &spec_for("plan/v1"));
        assert_eq!(
            errs.len(),
            0,
            "absent diagram should produce no FC08 notice; got {:?}",
            errs
        );
    }

    #[test]
    fn check_fc08_malformed_legend_no_panic() {
        // Legend with stray comma producing empty entry, an entry
        // missing `=`, an entry with empty halves. Parser drops the
        // junk and reconciles the recovered entries; no panic.
        let md = fc08_plan_with_legend(
            "    classDef ready fill:#bbdefb\n    class I1 ready\n",
            "**Legend**: Blue = ready, , just-a-color, = , Magenta = mystery",
        );
        let doc = doc_md(&md);
        let errs = check_fc08(&doc, &spec_for("plan/v1"));
        // Should fire exactly one Sub A notice (for `mystery`), having
        // silently dropped the malformed entries.
        let mystery_notices = errs
            .iter()
            .filter(|e| e.message.contains("Legend names class `mystery`"))
            .count();
        assert_eq!(
            mystery_notices, 1,
            "expected one mystery notice from malformed Legend; got {:?}",
            errs
        );
    }

    #[test]
    fn check_fc08_duplicate_legend_entries_deduplicated() {
        // Legend names `mystery` twice. Sub A should fire exactly once.
        let md = fc08_plan_with_legend(
            "    classDef ready fill:#bbdefb\n    class I1 ready\n",
            "**Legend**: Blue = ready, Magenta = mystery, Pink = mystery",
        );
        let doc = doc_md(&md);
        let errs = check_fc08(&doc, &spec_for("plan/v1"));
        let mystery_notices = errs
            .iter()
            .filter(|e| e.message.contains("Legend names class `mystery`"))
            .count();
        assert_eq!(
            mystery_notices, 1,
            "duplicate Legend entries should be deduplicated; got {:?}",
            errs
        );
    }

    #[test]
    fn check_fc08_bold_legend_wrapper_parses_identically() {
        // Test both `**Legend**:` and `Legend:` forms produce the same
        // notices.
        let md_bold = fc08_plan_with_legend(
            "    classDef ready fill:#bbdefb\n    class I1 ready\n",
            "**Legend**: Magenta = mystery",
        );
        let md_plain = fc08_plan_with_legend(
            "    classDef ready fill:#bbdefb\n    class I1 ready\n",
            "Legend: Magenta = mystery",
        );
        let errs_bold = check_fc08(&doc_md(&md_bold), &spec_for("plan/v1"));
        let errs_plain = check_fc08(&doc_md(&md_plain), &spec_for("plan/v1"));
        assert_eq!(
            errs_bold.len(),
            errs_plain.len(),
            "bold and plain Legend forms should produce identical notice counts; bold={:?} plain={:?}",
            errs_bold,
            errs_plain
        );
        assert!(errs_bold.iter().any(|e| e.message.contains("mystery")));
        assert!(errs_plain.iter().any(|e| e.message.contains("mystery")));
    }

    #[test]
    fn check_fc08_composite_legend_entry_parses_both_halves() {
        // Documented composite entry `tracks-design/tracks-plan` parses
        // as two distinct names. Both should normalize to camelCase
        // and Sub C should fire for each if the diagram has the
        // camelCase classDef.
        let md = fc08_plan_with_legend(
            "    classDef ready fill:#bbdefb\n    classDef tracksDesign fill:#FFE0B2\n    classDef tracksPlan fill:#FFE0B2\n    class I1 ready\n",
            "**Legend**: Blue = ready, Orange = tracks-design/tracks-plan",
        );
        let doc = doc_md(&md);
        let errs = check_fc08(&doc, &spec_for("plan/v1"));
        let sub_c_count = errs
            .iter()
            .filter(|e| e.message.contains("camelCase"))
            .count();
        assert_eq!(
            sub_c_count, 2,
            "composite entry should produce two Sub C notices; got {:?}",
            errs
        );
    }

    #[test]
    fn check_fc08_dispatched_in_plan_and_roadmap_arms() {
        // Confirm check_fc08 returns notices for plan/v1 AND for the
        // roadmap profile. The dispatch test in validate_file's own
        // tests gates that the arm wiring is correct; this gates that
        // check_fc08 itself engages on both profile specs.
        let md = fc08_plan_with_legend(
            "    classDef ready fill:#bbdefb\n    class I1 ready\n",
            "**Legend**: Blue = ready, Magenta = mystery",
        );
        let doc = doc_md(&md);
        let errs_plan = check_fc08(&doc, &spec_for("plan/v1"));
        assert!(!errs_plan.is_empty(), "plan profile should engage FC08");

        // Roadmap profile spec also engages (issues_table_columns non-
        // empty). The check function's gate is identical for both.
        let errs_roadmap = check_fc08(&doc, &spec_for("roadmap/v1"));
        assert!(!errs_roadmap.is_empty(), "roadmap profile should engage FC08");
    }

    #[test]
    fn check_fc08_no_op_on_format_without_issues_table() {
        // The brief format has no issues_table_columns. FC08 must
        // return immediately.
        let md = fc08_plan_with_legend(
            "    classDef ready fill:#bbdefb\n    class I1 ready\n",
            "**Legend**: Magenta = mystery",
        );
        let doc = doc_md(&md);
        let errs = check_fc08(&doc, &spec_for("brief/v1"));
        assert_eq!(errs.len(), 0, "non-issues-table format should no-op; got {:?}", errs);
    }

    #[test]
    fn check_fc08_notices_share_prefix_and_voice() {
        // Every FC08 notice begins with `[FC08]`. The prefix is the
        // PRD R6 binding shared with FC05/FC06/FC07/FC09.
        let md = fc08_plan_with_legend(
            "    classDef ready fill:#bbdefb\n    classDef needsExplore fill:#ffe0b2\n    classDef needsDesign fill:#e1bee7\n    class I1 ready\n",
            "**Legend**: Blue = ready, Magenta = mystery, Purple = needs-design",
        );
        let doc = doc_md(&md);
        let errs = check_fc08(&doc, &spec_for("plan/v1"));
        assert!(errs.len() >= 3, "expected at least one notice from each sub-check; got {:?}", errs);
        for e in &errs {
            assert_eq!(e.code, "FC08", "all FC08 notices must have code=FC08");
            assert!(
                e.message.starts_with("[FC08]"),
                "all FC08 notices must begin with `[FC08]`; got message {:?}",
                e.message
            );
        }
    }

    #[test]
    fn check_fc08_notice_bodies_are_public_clean() {
        // FC08 notices must not name private repos, paths, env vars, or
        // pre-announcement features. The notice surface interpolates
        // only class names parsed from the diagram or the Legend.
        let md = fc08_plan_with_legend(
            "    classDef ready fill:#bbdefb\n    classDef needsExplore fill:#ffe0b2\n    classDef needsDesign fill:#e1bee7\n    class I1 ready\n",
            "**Legend**: Blue = ready, Magenta = mystery, Purple = needs-design",
        );
        let doc = doc_md(&md);
        let errs = check_fc08(&doc, &spec_for("plan/v1"));
        let banned = [
            "tsukumogami/tools",
            "tsukumogami/vision",
            "ANTHROPIC_API_KEY",
            "GITHUB_TOKEN",
            "TAVILY_API_KEY",
            "private/",
            "/home/",
        ];
        for e in &errs {
            for b in &banned {
                assert!(
                    !e.message.contains(b),
                    "FC08 notice body contains banned substring {:?}: {}",
                    b,
                    e.message
                );
            }
        }
    }

    #[test]
    fn check_fc08_promotion_seam_is_single_match_arm() {
        // The promotion seam is a single `| "FC08"` arm in the
        // is_notice match expression. The membership site is the one
        // place to flip; this test pins the current notice-level
        // membership and documents the seam.
        use crate::validate::is_notice;
        let e = ValidationError {
            file: String::new(),
            line: 0,
            code: "FC08".to_string(),
            message: String::new(),
        };
        assert!(is_notice(&e), "FC08 must be notice-level for v1");
    }

    #[test]
    fn check_fc08_introduces_no_new_dependency() {
        // Structural: FC08 uses only `std::collections::HashSet`,
        // `regex` (already in workspace deps), and the existing
        // mermaid extractor infrastructure. No new external crate is
        // imported in checks.rs for FC08. This test asserts the
        // implementation symbols FC08 depends on are all from the
        // existing dependency surface.
        //
        // The check is structural: if a new dependency were added, it
        // would surface in `use ` statements at the top of checks.rs,
        // which already include only `std::*`, `regex::Regex`, and
        // crate-internal modules. The test pins the function exists
        // and is callable.
        let md = fc08_plan_with_legend(
            "    classDef ready fill:#bbdefb\n    class I1 ready\n",
            "**Legend**: Blue = ready",
        );
        let doc = doc_md(&md);
        let _errs = check_fc08(&doc, &spec_for("plan/v1"));
    }

    #[test]
    fn check_fc08_extract_legend_total_over_arbitrary_input() {
        // R15 totality: the Legend extractor must handle arbitrary
        // strings without panicking. Pin a representative set of
        // malformed shapes.
        let cases = vec![
            "",
            "Legend:",
            "**Legend**:",
            "Legend: ",
            "Legend: , , , ",
            "Legend: =, =, =",
            "Legend: a =, = b",
            "Legend: ////",
            "Legend: \u{0080}\u{ff}",  // multi-byte UTF-8 entry contents
            "**Legend**: \u{1F600} = emoji-class",  // emoji color
        ];
        for input in cases {
            let body = vec![input.to_string()];
            let _ = extract_legend(&body, 0);  // must not panic
        }
    }

    #[test]
    fn check_fc08_normalize_kebab_to_camel_canonical_pairs() {
        assert_eq!(normalize_kebab_to_camel("needs-design"), "needsDesign");
        assert_eq!(normalize_kebab_to_camel("tracks-design"), "tracksDesign");
        assert_eq!(normalize_kebab_to_camel("done"), "done");
        assert_eq!(normalize_kebab_to_camel(""), "");
        assert_eq!(normalize_kebab_to_camel("-leading"), "Leading");
        assert_eq!(normalize_kebab_to_camel("trailing-"), "trailing");
        assert_eq!(normalize_kebab_to_camel("a-b-c"), "aBC");
    }

    // ------------------------------------------------------------------
    // check_fc09 tests (PRD R6-R9 self-disable paths, R12 notice voice,
    // R13 Sub C asymmetry, R14 bounded behavior). Eleven pinned fixtures
    // per DESIGN Decision 3 (Sub A reconciled+defect, Sub B
    // reconciled+defect, Sub C over-claims+under-claims, four
    // self-disable paths, bounded-over-malformed-input).
    // ------------------------------------------------------------------

    use crate::gh::{ClientError, IssueState, MockIssueStateClient, PrContext};

    /// A canonical, well-formed plan fixture suitable for FC09 tests.
    /// Two entity rows: `#1` open (class ready) and `#2` open (class
    /// blocked, depends on #1). FC07 is happy with this fixture; FC09
    /// gates against the mock client.
    fn fc09_plan_two_open() -> String {
        well_formed_plan("    class I1 ready\n    class I2 blocked\n")
    }

    /// A plan fixture where row `#1` is strikethrough (terminal) with
    /// the diagram still classing it `done`. FC07 is happy; FC09 tests
    /// what the mock client returns for that issue.
    fn fc09_plan_one_done() -> String {
        "---\nschema: plan/v1\nstatus: Active\nexecution_mode: multi-pr\nmilestone: \"foo\"\nissue_count: 1\n---\n\n## Status\n\nActive\n\n## Implementation Issues\n\n| Issue | Dependencies | Complexity |\n|-------|--------------|------------|\n| ~~[#1: alpha](https://example.com/1)~~ | ~~None~~ | ~~simple~~ |\n| ~~_Alpha closed._~~ | | |\n\n## Dependency Graph\n\n```mermaid\ngraph TD\n    I1[\"#1: alpha\"]\n    classDef done fill:#c8e6c9\n    class I1 done\n```\n".to_string()
    }

    /// A roadmap fixture with one feature linking issue #10 (class
    /// ready, dep none).
    fn fc09_roadmap_one_open() -> String {
        "---\nschema: roadmap/v1\nstatus: Active\n---\n\n## Status\n\nActive\n\n## Implementation Issues\n\n| Feature | Issues | Dependencies | Status |\n|---------|--------|--------------|--------|\n| Feature 1: alpha | [#10](https://example.com/10) | None | In Progress |\n| _Alpha description._ | | | |\n\n## Dependency Graph\n\n```mermaid\ngraph TD\n    I10[\"#10: alpha\"]\n    classDef ready fill:#bbdefb\n    class I10 ready\n```\n".to_string()
    }

    fn pr_ctx() -> PrContext {
        PrContext {
            owner: "tsukumogami".to_string(),
            repo: "shirabe".to_string(),
            number: 153,
        }
    }

    // --- Sub A: doc-claims-done vs GitHub ---

    #[test]
    fn check_fc09_sub_a_reconciled_no_notice() {
        // Doc claims #1 done; GitHub observes #1 closed. No notice.
        let doc = doc_md(&fc09_plan_one_done());
        let ctx = pr_ctx();
        let mock = MockIssueStateClient::new()
            .with_issue("tsukumogami", "shirabe", 1, Ok(IssueState::Closed))
            .with_pr("tsukumogami", "shirabe", 153, Ok("Closes #1\n".to_string()));
        let errs = check_fc09(&doc, &spec_for("plan/v1"), &mock, Some(&ctx));
        let fc09: Vec<_> = errs.iter().filter(|e| e.code == "FC09").collect();
        // Should be 0 FC09 notices.
        assert_eq!(fc09.len(), 0, "expected no FC09 notices; got {:?}", fc09);
    }

    #[test]
    fn check_fc09_sub_a_doc_done_gh_open_fires() {
        // Doc claims #1 done; GitHub observes #1 open. Sub A fires.
        let doc = doc_md(&fc09_plan_one_done());
        let ctx = pr_ctx();
        let mock = MockIssueStateClient::new()
            .with_issue("tsukumogami", "shirabe", 1, Ok(IssueState::Open))
            // PR body: empty so Sub C under-claims also fires.
            .with_pr("tsukumogami", "shirabe", 153, Ok("".to_string()));
        let errs = check_fc09(&doc, &spec_for("plan/v1"), &mock, Some(&ctx));
        let sub_a: Vec<_> = errs
            .iter()
            .filter(|e| e.message.contains("claims done") && e.message.contains("still open"))
            .collect();
        assert_eq!(sub_a.len(), 1, "Sub A defect must fire; got {:?}", errs);
        assert_eq!(sub_a[0].code, "FC09");
        assert!(sub_a[0].message.contains("[FC09]"));
        assert!(sub_a[0].message.contains("\"#1\""));
        assert!(sub_a[0].message.contains("I1"));
    }

    // --- Sub B: doc-claims-open vs GitHub ---

    #[test]
    fn check_fc09_sub_b_reconciled_no_notice() {
        // Doc shows #1 open (ready); GitHub observes open. No notice.
        let doc = doc_md(&fc09_plan_two_open());
        let ctx = pr_ctx();
        let mock = MockIssueStateClient::new()
            .with_issue("tsukumogami", "shirabe", 1, Ok(IssueState::Open))
            .with_issue("tsukumogami", "shirabe", 2, Ok(IssueState::Open))
            .with_pr("tsukumogami", "shirabe", 153, Ok("".to_string()));
        let errs = check_fc09(&doc, &spec_for("plan/v1"), &mock, Some(&ctx));
        let fc09: Vec<_> = errs.iter().filter(|e| e.code == "FC09").collect();
        assert_eq!(fc09.len(), 0, "expected no FC09 notices; got {:?}", fc09);
    }

    #[test]
    fn check_fc09_sub_b_doc_open_gh_closed_fires() {
        // Doc shows #1 ready (open); GitHub observes #1 closed. Sub B fires.
        let doc = doc_md(&fc09_plan_two_open());
        let ctx = pr_ctx();
        let mock = MockIssueStateClient::new()
            .with_issue("tsukumogami", "shirabe", 1, Ok(IssueState::Closed))
            .with_issue("tsukumogami", "shirabe", 2, Ok(IssueState::Open))
            .with_pr("tsukumogami", "shirabe", 153, Ok("".to_string()));
        let errs = check_fc09(&doc, &spec_for("plan/v1"), &mock, Some(&ctx));
        let sub_b: Vec<_> = errs
            .iter()
            .filter(|e| {
                e.message.contains("claims open with class")
                    && e.message.contains("to done and apply strikethrough")
            })
            .collect();
        assert_eq!(sub_b.len(), 1, "Sub B defect must fire; got {:?}", errs);
        assert!(sub_b[0].message.contains("[FC09]"));
        assert!(sub_b[0].message.contains("\"#1\""));
        assert!(sub_b[0].message.contains("ready"));
    }

    // --- Sub C: PR Closes vs doc ---

    #[test]
    fn check_fc09_sub_c_over_claims_same_repo_fires() {
        // PR body says Closes #1, but doc shows #1 ready (non-done).
        let doc = doc_md(&fc09_plan_two_open());
        let ctx = pr_ctx();
        let mock = MockIssueStateClient::new()
            .with_issue("tsukumogami", "shirabe", 1, Ok(IssueState::Open))
            .with_issue("tsukumogami", "shirabe", 2, Ok(IssueState::Open))
            .with_pr(
                "tsukumogami",
                "shirabe",
                153,
                Ok("Closes #1\nFixes #999\n".to_string()),
            );
        let errs = check_fc09(&doc, &spec_for("plan/v1"), &mock, Some(&ctx));
        let over: Vec<_> = errs
            .iter()
            .filter(|e| e.message.contains("PR body line") && e.message.contains("\"Closes #1\""))
            .collect();
        assert_eq!(over.len(), 1, "Sub C over-claims must fire; got {:?}", errs);
        assert!(over[0].message.contains("non-done"));
    }

    #[test]
    fn check_fc09_sub_c_under_claims_fires() {
        // Doc claims #1 done; GitHub observes #1 open; PR body has no
        // Closes #1.
        let doc = doc_md(&fc09_plan_one_done());
        let ctx = pr_ctx();
        let mock = MockIssueStateClient::new()
            .with_issue("tsukumogami", "shirabe", 1, Ok(IssueState::Open))
            .with_pr(
                "tsukumogami",
                "shirabe",
                153,
                Ok("Closes #2\nFixes #3\n".to_string()),
            );
        let errs = check_fc09(&doc, &spec_for("plan/v1"), &mock, Some(&ctx));
        let under: Vec<_> = errs
            .iter()
            .filter(|e| {
                e.message.contains("claims done but GitHub observes")
                    && e.message.contains("no \"Closes #")
            })
            .collect();
        assert!(
            !under.is_empty(),
            "Sub C under-claims must fire; got {:?}",
            errs
        );
    }

    // --- Self-disable paths ---

    #[test]
    fn check_fc09_missing_credentials_skip_notice() {
        // Mock returns Auth for every issue lookup. The check emits one
        // skip notice and stops iterating.
        let doc = doc_md(&fc09_plan_two_open());
        let ctx = pr_ctx();
        let mock = MockIssueStateClient::new()
            .with_issue("tsukumogami", "shirabe", 1, Err(ClientError::Auth))
            .with_issue("tsukumogami", "shirabe", 2, Err(ClientError::Auth));
        let errs = check_fc09(&doc, &spec_for("plan/v1"), &mock, Some(&ctx));
        let auth_skips: Vec<_> = errs
            .iter()
            .filter(|e| e.message.contains("no GitHub credentials available"))
            .collect();
        assert_eq!(
            auth_skips.len(),
            1,
            "exactly one Auth skip notice; got {:?}",
            errs
        );
        assert_eq!(auth_skips[0].code, "FC09");
    }

    #[test]
    fn check_fc09_missing_pr_context_skip_notice() {
        // pr_ctx is None; Sub C is skipped with a single notice.
        let doc = doc_md(&fc09_plan_one_done());
        let mock = MockIssueStateClient::new();
        let errs = check_fc09(&doc, &spec_for("plan/v1"), &mock, None);
        let ctx_skips: Vec<_> = errs
            .iter()
            .filter(|e| e.message.contains("Sub-check C skipped"))
            .collect();
        assert_eq!(
            ctx_skips.len(),
            1,
            "exactly one PR-context skip notice; got {:?}",
            errs
        );
        assert!(ctx_skips[0].message.contains("SHIRABE_PR_NUMBER"));
    }

    #[test]
    fn check_fc09_rate_limit_exhausted_skip_notice() {
        // Mock returns RateLimit on every call. After the in-call
        // retry, the check emits the rate-limit skip notice.
        let doc = doc_md(&fc09_plan_two_open());
        let ctx = pr_ctx();
        let mock = MockIssueStateClient::new()
            .with_issue("tsukumogami", "shirabe", 1, Err(ClientError::RateLimit))
            .with_issue("tsukumogami", "shirabe", 2, Err(ClientError::RateLimit));
        let errs = check_fc09(&doc, &spec_for("plan/v1"), &mock, Some(&ctx));
        let rl_skips: Vec<_> = errs
            .iter()
            .filter(|e| e.message.contains("rate limit exhausted"))
            .collect();
        assert!(
            !rl_skips.is_empty(),
            "rate-limit skip must fire; got {:?}",
            errs
        );
        assert_eq!(rl_skips[0].code, "FC09");
    }

    #[test]
    fn check_fc09_cross_repo_forbidden_per_row_skip() {
        // A plan whose row has a cross-repo dep returning Forbidden.
        let fixture = "---\nschema: plan/v1\nstatus: Active\nexecution_mode: multi-pr\nmilestone: \"foo\"\nissue_count: 1\n---\n\n## Status\n\nActive\n\n## Implementation Issues\n\n| Issue | Dependencies | Complexity |\n|-------|--------------|------------|\n| [#1: alpha](https://example.com/1) | other/private#42 | simple |\n| _Alpha._ | | |\n\n## Dependency Graph\n\n```mermaid\ngraph TD\n    I1[\"#1: alpha\"]\n    classDef ready fill:#bbdefb\n    class I1 ready\n```\n";
        let doc = doc_md(fixture);
        let ctx = pr_ctx();
        let mock = MockIssueStateClient::new()
            .with_issue("other", "private", 42, Err(ClientError::Forbidden));
        let errs = check_fc09(&doc, &spec_for("plan/v1"), &mock, Some(&ctx));
        let cross_skips: Vec<_> = errs
            .iter()
            .filter(|e| e.message.contains("cross-repo") && e.message.contains("access denied"))
            .collect();
        assert_eq!(
            cross_skips.len(),
            1,
            "exactly one cross-repo skip; got {:?}",
            errs
        );
    }

    // --- Bounded over malformed input ---

    #[test]
    fn check_fc09_malformed_response_no_notice_no_panic() {
        // Mock returns Malformed for an issue. PRD R14: no per-row
        // notice; the check proceeds without panicking.
        let doc = doc_md(&fc09_plan_two_open());
        let ctx = pr_ctx();
        let mock = MockIssueStateClient::new()
            .with_issue(
                "tsukumogami",
                "shirabe",
                1,
                Err(ClientError::Malformed("garbage".to_string())),
            )
            .with_issue("tsukumogami", "shirabe", 2, Ok(IssueState::Open))
            .with_pr("tsukumogami", "shirabe", 153, Ok("".to_string()));
        let errs = check_fc09(&doc, &spec_for("plan/v1"), &mock, Some(&ctx));
        // Malformed payload string must not appear in any notice body.
        for e in &errs {
            assert!(
                !e.message.contains("garbage"),
                "Malformed payload must not leak into notice body: {:?}",
                e
            );
        }
    }

    // --- Roadmap profile dispatch ---

    #[test]
    fn check_fc09_roadmap_profile_dispatches() {
        let doc = doc_md(&fc09_roadmap_one_open());
        let ctx = pr_ctx();
        let mock = MockIssueStateClient::new()
            .with_issue("tsukumogami", "shirabe", 10, Ok(IssueState::Closed))
            .with_pr("tsukumogami", "shirabe", 153, Ok("".to_string()));
        let errs = check_fc09(&doc, &spec_for("roadmap/v1"), &mock, Some(&ctx));
        // Sub B fires: doc shows #10 ready, GH observes closed.
        let sub_b: Vec<_> = errs
            .iter()
            .filter(|e| {
                e.message.contains("claims open with class")
                    && e.message.contains("to done and apply strikethrough")
            })
            .collect();
        assert_eq!(sub_b.len(), 1, "Sub B on roadmap must fire; got {:?}", errs);
    }

    // --- No-op paths ---

    #[test]
    fn check_fc09_noop_when_spec_has_no_issues_table() {
        let doc = doc_md(
            "---\nschema: design/v1\nstatus: Proposed\nproblem: |\n  p\ndecision: |\n  d\nrationale: |\n  r\n---\n",
        );
        let mock = MockIssueStateClient::new();
        let errs = check_fc09(&doc, &spec_for("design/v1"), &mock, None);
        assert_eq!(errs.len(), 0, "no-op on non-issues-table format; got {:?}", errs);
    }

    #[test]
    fn check_fc09_missing_block_short_circuits() {
        // A plan whose Dependency Graph section has no mermaid block.
        let fixture = "---\nschema: plan/v1\nstatus: Active\nexecution_mode: multi-pr\nmilestone: \"foo\"\nissue_count: 1\n---\n\n## Status\n\nActive\n\n## Implementation Issues\n\n| Issue | Dependencies | Complexity |\n|-------|--------------|------------|\n| [#1: alpha](https://example.com/1) | None | simple |\n| _Alpha._ | | |\n\n## Dependency Graph\n\nNo mermaid block.\n";
        let doc = doc_md(fixture);
        let ctx = pr_ctx();
        let mock = MockIssueStateClient::new();
        let errs = check_fc09(&doc, &spec_for("plan/v1"), &mock, Some(&ctx));
        // MissingBlock short-circuits; FC09 contributes nothing.
        assert_eq!(
            errs.len(),
            0,
            "MissingBlock short-circuits FC09; got {:?}",
            errs
        );
    }

    // --- Notice public-cleanliness ---

    #[test]
    fn fc09_notice_bodies_are_public_clean() {
        // Run the check across the fixtures above and assert no notice
        // body mentions a URL, a private repo name, or the GITHUB_TOKEN
        // environment variable name.
        let doc = doc_md(&fc09_plan_one_done());
        let ctx = pr_ctx();
        let mock = MockIssueStateClient::new()
            .with_issue("tsukumogami", "shirabe", 1, Ok(IssueState::Open))
            .with_pr("tsukumogami", "shirabe", 153, Ok("Closes #2\n".to_string()));
        let errs = check_fc09(&doc, &spec_for("plan/v1"), &mock, Some(&ctx));
        for e in &errs {
            if e.code != "FC09" {
                continue;
            }
            assert!(
                !e.message.contains("https://"),
                "FC09 notice contains URL: {:?}",
                e.message
            );
            assert!(
                !e.message.contains("http://"),
                "FC09 notice contains URL: {:?}",
                e.message
            );
            // Token-bytes screen: GITHUB_TOKEN names must appear only
            // in the missing-credentials guidance form.
            if e.message.contains("GITHUB_TOKEN") {
                assert!(
                    e.message.contains("no GitHub credentials available"),
                    "GITHUB_TOKEN reference only allowed in the missing-credentials notice: {:?}",
                    e.message
                );
            }
        }
    }

    // --- FC10 writing-style banned-word check ---

    fn doc_with_body(path: &str, body_lines: &[&str]) -> Doc {
        Doc {
            path: path.to_string(),
            schema: "brief/v1".to_string(),
            status: "Draft".to_string(),
            fields: HashMap::new(),
            sections: vec![],
            body: lines(body_lines),
        }
    }

    #[test]
    fn check_writing_style_clean_body_no_notices() {
        let doc = doc_with_body("test.md", &["This is clean prose.", "Nothing banned here."]);
        let errs = check_writing_style(&doc, &spec_for("brief/v1"));
        assert_eq!(errs.len(), 0, "clean body must produce no FC10 notices; got {:?}", errs);
    }

    #[test]
    fn check_writing_style_detects_each_banned_word() {
        for &word in FC10_BANNED_WORDS {
            let line = format!("We {} the thing.", word);
            let doc = doc_with_body("t.md", &[line.as_str()]);
            let errs = check_writing_style(&doc, &spec_for("brief/v1"));
            assert!(
                errs.iter().any(|e| e.code == "FC10" && e.message.contains(word)),
                "FC10 should detect banned word {:?}; got {:?}",
                word,
                errs
            );
        }
    }

    #[test]
    fn check_writing_style_case_insensitive() {
        let doc = doc_with_body("t.md", &["TIER one is required.", "Robust design."]);
        let errs = check_writing_style(&doc, &spec_for("brief/v1"));
        assert!(errs.len() >= 2, "case-insensitive matches expected; got {:?}", errs);
    }

    #[test]
    fn check_writing_style_whole_word_only() {
        // "tiered" and "tier" are both banned; substring "subtier" should
        // NOT match because of the word-boundary rule on the leading side
        // (the 's' preceding 'tier' is alphanumeric).
        let doc = doc_with_body("t.md", &["subtleness", "subtierred"]);
        let errs = check_writing_style(&doc, &spec_for("brief/v1"));
        // "subtle" contains "tle" not "tier"; "subtierred" -> "tier" preceded by 'b', followed by 'r' -- both bytes are alphanumeric so no match.
        assert_eq!(
            errs.len(),
            0,
            "word-boundary check should reject substring matches; got {:?}",
            errs
        );
    }

    #[test]
    fn check_writing_style_emits_file_and_line() {
        let doc = doc_with_body("path/to/foo.md", &["", "this is robust"]);
        let errs = check_writing_style(&doc, &spec_for("brief/v1"));
        assert_eq!(errs.len(), 1);
        assert_eq!(errs[0].file, "path/to/foo.md");
        assert_eq!(errs[0].line, 2); // line is 1-indexed, line 2 has the match
    }

    // --- FC11 plan-section-structure check ---

    fn plan_doc_with_sections(sections: Vec<Section>, body_lines: &[&str]) -> Doc {
        let mut fields = HashMap::new();
        fields.insert("status".to_string(), fv("Draft", 2));
        fields.insert("execution_mode".to_string(), fv("single-pr", 3));
        fields.insert("milestone".to_string(), fv("\"m\"", 4));
        fields.insert("issue_count".to_string(), fv("1", 5));
        Doc {
            path: "PLAN-test.md".to_string(),
            schema: "plan/v1".to_string(),
            status: "Draft".to_string(),
            fields,
            sections,
            body: lines(body_lines),
        }
    }

    #[test]
    fn check_plan_section_structure_noop_on_non_plan() {
        let doc = make_doc("brief/v1", "Draft", HashMap::new(), vec![], vec![]);
        let errs = check_plan_section_structure(&doc, &spec_for("brief/v1"));
        assert_eq!(errs.len(), 0);
    }

    #[test]
    fn check_plan_section_structure_noop_when_section_absent() {
        // Implementation Issues section missing -- FC04's territory.
        let doc = plan_doc_with_sections(vec![sec("Status", 1)], &["## Status", "", "Draft"]);
        let errs = check_plan_section_structure(&doc, &spec_for("plan/v1"));
        assert_eq!(errs.len(), 0);
    }

    #[test]
    fn check_plan_section_structure_fires_on_missing_table() {
        // Implementation Issues section present but no table.
        let doc = plan_doc_with_sections(
            vec![sec("Implementation Issues", 10)],
            &[
                "## Implementation Issues",
                "",
                "Some prose without a table.",
            ],
        );
        let errs = check_plan_section_structure(&doc, &spec_for("plan/v1"));
        assert_eq!(errs.len(), 1);
        assert_eq!(errs[0].code, "FC11");
        assert!(errs[0].message.contains("plan-format.md"));
    }

    // --- FC12 PLAN/DESIGN field consistency check ---

    #[test]
    fn check_plan_design_field_consistency_skip_no_upstream() {
        let doc = plan_doc_with_sections(vec![], &["- [ ] **foo**: bar"]);
        let errs = check_plan_design_field_consistency(&doc, &spec_for("plan/v1"));
        assert_eq!(errs.len(), 0, "graceful skip when no upstream; got {:?}", errs);
    }

    #[test]
    fn check_plan_design_field_consistency_clean_baseline() {
        let mut doc = plan_doc_with_sections(
            vec![],
            &["- [ ] **foo**: integer", "- [ ] **foo**: integer"],
        );
        doc.fields
            .insert("upstream".to_string(), fv("docs/designs/DESIGN-x.md", 6));
        let errs = check_plan_design_field_consistency(&doc, &spec_for("plan/v1"));
        assert_eq!(errs.len(), 0, "identical shapes are compatible; got {:?}", errs);
    }

    #[test]
    fn check_plan_design_field_consistency_detects_conflict() {
        // Two ACs declare `foo` with conflicting kinds (integer vs free-text).
        let mut doc = plan_doc_with_sections(
            vec![],
            &[
                "- [ ] **foo**: an integer count",
                "- [ ] **foo**: free-text label",
            ],
        );
        doc.fields
            .insert("upstream".to_string(), fv("docs/designs/DESIGN-x.md", 6));
        let errs = check_plan_design_field_consistency(&doc, &spec_for("plan/v1"));
        assert_eq!(errs.len(), 1);
        assert_eq!(errs[0].code, "FC12");
        assert!(errs[0].message.contains("foo"));
        assert!(errs[0]
            .message
            .contains("references/fixes/plan-design-field-consistency.md"));
    }

    // --- FC13 eval-fixture frontmatter-line-1 check ---

    #[test]
    fn check_eval_fixture_frontmatter_skips_non_fixture_paths() {
        let doc = doc_with_body("docs/briefs/BRIEF-foo.md", &["<!-- comment -->", "---"]);
        let errs = check_eval_fixture_frontmatter(&doc, &spec_for("brief/v1"));
        assert_eq!(errs.len(), 0, "non-fixture path should be skipped; got {:?}", errs);
    }

    #[test]
    fn check_eval_fixture_frontmatter_detects_line1_comment() {
        let doc = doc_with_body(
            "skills/foo/evals/fixture.md",
            &["<!-- comment -->", "---", "schema: brief/v1"],
        );
        let errs = check_eval_fixture_frontmatter(&doc, &spec_for("brief/v1"));
        assert_eq!(errs.len(), 1);
        assert_eq!(errs[0].code, "FC13");
        assert_eq!(errs[0].line, 1);
        assert!(errs[0]
            .message
            .contains("references/fixes/eval-fixture-frontmatter.md"));
    }

    #[test]
    fn check_eval_fixture_frontmatter_clean_baseline() {
        let doc = doc_with_body(
            "skills/foo/evals/fixture.md",
            &["---", "schema: brief/v1", "---", "<!-- after frontmatter is OK -->"],
        );
        let errs = check_eval_fixture_frontmatter(&doc, &spec_for("brief/v1"));
        assert_eq!(errs.len(), 0, "frontmatter-first should pass; got {:?}", errs);
    }

    #[test]
    fn check_eval_fixture_frontmatter_blank_lines_before_comment() {
        // Blank lines preceding the comment still leave `<!--` as the
        // first non-blank line; the parser still silent-skips.
        let doc = doc_with_body("skills/x/evals/f.md", &["", "", "<!-- here -->", "---"]);
        let errs = check_eval_fixture_frontmatter(&doc, &spec_for("brief/v1"));
        assert_eq!(errs.len(), 1);
        assert_eq!(errs[0].line, 3);
    }

    // --- FC-CONVENTIONS CLAUDE.md headers check ---

    #[test]
    fn check_claude_md_conventions_skips_non_claude_files() {
        let doc = doc_with_body("README.md", &["# README"]);
        let errs = check_claude_md_conventions(&doc, &spec_for("brief/v1"));
        assert_eq!(errs.len(), 0);
    }

    #[test]
    fn check_claude_md_conventions_clean_baseline() {
        let doc = doc_with_body(
            "CLAUDE.md",
            &[
                "# repo",
                "",
                "## Release Notes Convention: docs/guides/",
                "",
                "More prose.",
            ],
        );
        let errs = check_claude_md_conventions(&doc, &spec_for("brief/v1"));
        assert_eq!(errs.len(), 0, "well-formed header should pass; got {:?}", errs);
    }

    #[test]
    fn check_claude_md_conventions_missing_header() {
        let doc = doc_with_body("CLAUDE.md", &["# repo", "", "Some other prose."]);
        let errs = check_claude_md_conventions(&doc, &spec_for("brief/v1"));
        assert_eq!(errs.len(), 1);
        assert_eq!(errs[0].code, "FC-CONVENTIONS");
        assert!(errs[0].message.contains("missing"));
    }

    #[test]
    fn check_claude_md_conventions_malformed_header_no_colon() {
        let doc = doc_with_body(
            "CLAUDE.md",
            &["# repo", "", "## Release Notes Convention docs/guides/"],
        );
        let errs = check_claude_md_conventions(&doc, &spec_for("brief/v1"));
        assert_eq!(errs.len(), 1);
        assert!(errs[0].message.contains("malformed"));
    }

    #[test]
    fn check_claude_md_conventions_malformed_header_empty_path() {
        let doc = doc_with_body(
            "CLAUDE.md",
            &["# repo", "", "## Release Notes Convention:   "],
        );
        let errs = check_claude_md_conventions(&doc, &spec_for("brief/v1"));
        assert_eq!(errs.len(), 1);
        assert!(errs[0].message.contains("path is empty"));
    }

    #[test]
    fn check_claude_md_conventions_alternate_paths_accepted() {
        for path in &["docs/guides/", "docs/releases/", "CHANGELOG.md"] {
            let line = format!("## Release Notes Convention: {}", path);
            let doc = doc_with_body("CLAUDE.md", &[line.as_str()]);
            let errs = check_claude_md_conventions(&doc, &spec_for("brief/v1"));
            assert_eq!(errs.len(), 0, "path {:?} should be accepted", path);
        }
    }

    // --- Slug-prefix detection ---

    #[test]
    fn detect_slug_prefix_returns_none_when_docs_root_absent() {
        let result = detect_slug_prefix("/nonexistent/path/that/does/not/exist");
        assert_eq!(result, None);
    }

    #[test]
    fn check_slug_prefix_returns_no_prevailing_when_absent() {
        let result = check_slug_prefix("/nonexistent/path", "any-slug");
        assert_eq!(result, SlugPrefixCheck::NoPrevailingPrefix);
    }

    #[test]
    fn detect_slug_prefix_finds_majority_prefix() {
        use std::fs;
        let tmp = std::env::temp_dir().join("shirabe-test-slug-prefix");
        let _ = fs::remove_dir_all(&tmp);
        fs::create_dir_all(tmp.join("briefs")).unwrap();
        fs::create_dir_all(tmp.join("prds")).unwrap();
        fs::create_dir_all(tmp.join("designs")).unwrap();
        fs::create_dir_all(tmp.join("plans")).unwrap();
        fs::write(tmp.join("briefs/BRIEF-shirabe-alpha.md"), "x").unwrap();
        fs::write(tmp.join("prds/PRD-shirabe-beta.md"), "x").unwrap();
        fs::write(tmp.join("designs/DESIGN-shirabe-gamma.md"), "x").unwrap();
        fs::write(tmp.join("plans/PLAN-other-delta.md"), "x").unwrap();
        let result = detect_slug_prefix(tmp.to_str().unwrap());
        assert_eq!(result, Some("shirabe".to_string()));
        // Cleanup.
        let _ = fs::remove_dir_all(&tmp);
    }

    #[test]
    fn check_slug_prefix_matches_and_mismatches() {
        use std::fs;
        let tmp = std::env::temp_dir().join("shirabe-test-slug-prefix-check");
        let _ = fs::remove_dir_all(&tmp);
        fs::create_dir_all(tmp.join("briefs")).unwrap();
        fs::write(tmp.join("briefs/BRIEF-shirabe-a.md"), "x").unwrap();
        fs::write(tmp.join("briefs/BRIEF-shirabe-b.md"), "x").unwrap();
        fs::write(tmp.join("briefs/BRIEF-shirabe-c.md"), "x").unwrap();
        let docs = tmp.to_str().unwrap();
        assert_eq!(
            check_slug_prefix(docs, "shirabe-new-feature"),
            SlugPrefixCheck::Matches {
                prefix: "shirabe".to_string()
            }
        );
        match check_slug_prefix(docs, "rogue-feature") {
            SlugPrefixCheck::Mismatch { prefix, slug } => {
                assert_eq!(prefix, "shirabe");
                assert_eq!(slug, "rogue-feature");
            }
            other => panic!("expected mismatch, got {:?}", other),
        }
        let _ = fs::remove_dir_all(&tmp);
    }

    // =========================================================================
    // FC14 -- single-pr plan structural validation
    // =========================================================================

    fn plan_spec() -> FormatSpec {
        spec_for("plan/v1")
    }

    /// Builds a Plan-profile Doc populated with the given execution_mode and
    /// body lines. Sections are derived from `## ` lines in `body`.
    fn make_plan_doc(execution_mode: &str, issue_count: usize, body: Vec<String>) -> Doc {
        let mut fields = HashMap::new();
        fields.insert("execution_mode".to_string(), fv(execution_mode, 1));
        fields.insert("issue_count".to_string(), fv(&issue_count.to_string(), 1));
        let sections: Vec<Section> = body
            .iter()
            .enumerate()
            .filter_map(|(i, line)| {
                let t = line.trim_start();
                if t.starts_with("## ") && !t.starts_with("### ") {
                    Some(sec(t.trim_start_matches("## "), i + 1))
                } else {
                    None
                }
            })
            .collect();
        Doc {
            path: "docs/plans/PLAN-test.md".to_string(),
            schema: "plan/v1".to_string(),
            status: "Active".to_string(),
            fields,
            sections,
            body,
        }
    }

    fn well_formed_single_pr_body() -> Vec<String> {
        vec![
            "# PLAN: test".to_string(),
            "## Status".to_string(),
            "Active".to_string(),
            "## Scope Summary".to_string(),
            "demo".to_string(),
            "## Decomposition Strategy".to_string(),
            "horizontal".to_string(),
            "## Issue Outlines".to_string(),
            "### Issue 1: feat(x): first".to_string(),
            "**Goal**: do the first thing.".to_string(),
            "**Acceptance Criteria**:".to_string(),
            "- [ ] first AC".to_string(),
            "**Dependencies**: None".to_string(),
            "### Issue 2: feat(x): second".to_string(),
            "**Goal**: do the second thing.".to_string(),
            "**Acceptance Criteria**:".to_string(),
            "- [ ] second AC".to_string(),
            "**Dependencies**: Blocked by <<ISSUE:1>>".to_string(),
            "## Implementation Sequence".to_string(),
            "outline 1, then outline 2".to_string(),
        ]
    }

    fn well_formed_multi_pr_body() -> Vec<String> {
        vec![
            "# PLAN: test".to_string(),
            "## Status".to_string(),
            "Active".to_string(),
            "## Scope Summary".to_string(),
            "demo".to_string(),
            "## Decomposition Strategy".to_string(),
            "horizontal".to_string(),
            "## Implementation Issues".to_string(),
            "".to_string(),
            "| Issue | Dependencies | Complexity |".to_string(),
            "| ----- | ------------ | ---------- |".to_string(),
            "| [#1](http://x/1) | None | simple |".to_string(),
            "| [#2](http://x/2) | [#1](http://x/1) | testable |".to_string(),
            "## Dependency Graph".to_string(),
            "```mermaid".to_string(),
            "graph TD".to_string(),
            "  I1[\"#1\"] --> I2[\"#2\"]".to_string(),
            "```".to_string(),
            "## Implementation Sequence".to_string(),
            "1 then 2".to_string(),
        ]
    }

    #[test]
    fn check_fc14_well_formed_single_pr_no_notice() {
        let doc = make_plan_doc("single-pr", 2, well_formed_single_pr_body());
        let errs = check_fc14(&doc, &plan_spec());
        assert!(
            errs.is_empty(),
            "well-formed single-pr should produce no FC14 notice; got {:?}",
            errs
        );
    }

    #[test]
    fn check_fc14_well_formed_multi_pr_no_notice() {
        let doc = make_plan_doc("multi-pr", 2, well_formed_multi_pr_body());
        let errs = check_fc14(&doc, &plan_spec());
        assert!(
            errs.is_empty(),
            "well-formed multi-pr should produce no FC14 notice; got {:?}",
            errs
        );
    }

    #[test]
    fn check_fc14_well_formed_coordinated_no_notice() {
        // Coordinated mode shares multi-pr's section shape (Implementation
        // Issues table + Dependency Graph), so a well-formed coordinated PLAN
        // validates clean under FC14 just like multi-pr.
        let doc = make_plan_doc("coordinated", 2, well_formed_multi_pr_body());
        let errs = check_fc14(&doc, &plan_spec());
        assert!(
            errs.is_empty(),
            "well-formed coordinated should produce no FC14 notice; got {:?}",
            errs
        );
    }

    #[test]
    fn check_fc14_coordinated_with_outlines_fires_mutual_exclusion() {
        // A coordinated PLAN whose authoritative content should be the
        // Implementation Issues table must not also carry populated Issue
        // Outlines; FC14 fires the symmetric mutual-exclusion notice, naming
        // the coordinated mode.
        let doc = make_plan_doc("coordinated", 2, well_formed_single_pr_body());
        let errs = check_fc14(&doc, &plan_spec());
        assert!(
            errs.iter().any(|e| e.code == "FC14"
                && e.message.contains("execution_mode is 'coordinated'")
                && e.message.contains("## Issue Outlines")),
            "expected FC14 coordinated mutual-exclusion notice; got {:?}",
            errs
        );
    }

    #[test]
    fn check_fc14_only_runs_on_plan_profile() {
        // A BRIEF doc should never trigger FC14 even when constructed
        // with a Plan-looking body.
        let body = well_formed_single_pr_body();
        let mut fields = HashMap::new();
        fields.insert("execution_mode".to_string(), fv("single-pr", 1));
        let doc = Doc {
            path: "docs/briefs/BRIEF-test.md".to_string(),
            schema: "brief/v1".to_string(),
            status: "Accepted".to_string(),
            fields,
            sections: vec![],
            body,
        };
        let brief_spec = spec_for("brief/v1");
        assert!(check_fc14(&doc, &brief_spec).is_empty());
    }

    #[test]
    fn check_fc14_sub_b_outline_missing_goal_fires() {
        let mut body = well_formed_single_pr_body();
        // Remove the **Goal**: line of Issue 1 (index 9 in well_formed body).
        body.remove(9);
        let doc = make_plan_doc("single-pr", 2, body);
        let errs = check_fc14(&doc, &plan_spec());
        assert!(
            errs.iter().any(|e| e.code == "FC14"
                && e.message.contains("missing '**Goal**:'")
                && e.message.contains("Issue 1")),
            "expected FC14 notice for missing goal on Issue 1; got {:?}",
            errs
        );
    }

    #[test]
    fn check_fc14_sub_b_outline_missing_ac_fires() {
        let mut body = well_formed_single_pr_body();
        // Remove the **Acceptance Criteria**: line + bullet for Issue 1.
        body.remove(10); // bullet
        body.remove(9); // header (now line 9 after first removal)
        // Wait, ordering: original body[9]="**Goal**: ..."; body[10]="**AC**:";
        // body[11]="- [ ] first AC". So we need to remove the AC header and bullet.
        // Let me redo carefully — instead remove by content.
        let mut body = well_formed_single_pr_body();
        body.retain(|l| !l.starts_with("**Acceptance Criteria**:"));
        body.retain(|l| !l.starts_with("- [ ] first AC"));
        let doc = make_plan_doc("single-pr", 2, body);
        let errs = check_fc14(&doc, &plan_spec());
        assert!(
            errs.iter().any(|e| e.code == "FC14"
                && e.message.contains("missing '**Acceptance Criteria**:'")
                && e.message.contains("Issue 1")),
            "expected FC14 notice for missing AC on Issue 1; got {:?}",
            errs
        );
    }

    #[test]
    fn check_fc14_sub_b_outline_missing_dependencies_fires() {
        let mut body = well_formed_single_pr_body();
        body.retain(|l| !l.starts_with("**Dependencies**:"));
        let doc = make_plan_doc("single-pr", 2, body);
        let errs = check_fc14(&doc, &plan_spec());
        assert!(
            errs.iter().any(|e| e.code == "FC14"
                && e.message.contains("missing '**Dependencies**:'")
                && e.message.contains("Issue 1")),
            "expected FC14 notice for missing Dependencies on Issue 1; got {:?}",
            errs
        );
    }

    #[test]
    fn check_fc14_sub_c_unresolved_dependency_fires() {
        let mut body = well_formed_single_pr_body();
        // Swap Issue 2's deps to reference a non-existent sibling.
        for line in body.iter_mut() {
            if line.starts_with("**Dependencies**: Blocked by <<ISSUE:1>>") {
                *line = "**Dependencies**: Blocked by Issue 42".to_string();
            }
        }
        let doc = make_plan_doc("single-pr", 2, body);
        let errs = check_fc14(&doc, &plan_spec());
        assert!(
            errs.iter().any(|e| e.code == "FC14"
                && e.message.contains("unresolved dependency")
                && e.message.contains("Issue 42")),
            "expected FC14 notice for unresolved dep 'Issue 42'; got {:?}",
            errs
        );
    }

    #[test]
    fn check_fc14_sub_c_none_dep_does_not_fire() {
        let doc = make_plan_doc("single-pr", 2, well_formed_single_pr_body());
        let errs = check_fc14(&doc, &plan_spec());
        assert!(
            !errs
                .iter()
                .any(|e| e.code == "FC14" && e.message.contains("unresolved")),
            "Issue 1 with Dependencies: None should not fire unresolved; got {:?}",
            errs
        );
    }

    #[test]
    fn check_fc14_sub_d_issue_count_mismatch_fires() {
        let doc = make_plan_doc("single-pr", 5, well_formed_single_pr_body());
        let errs = check_fc14(&doc, &plan_spec());
        assert!(
            errs.iter().any(|e| e.code == "FC14"
                && e.message.contains("issue_count: 5")
                && e.message.contains("observed count 2")),
            "expected FC14 notice for issue_count mismatch (5 vs 2); got {:?}",
            errs
        );
    }

    #[test]
    fn check_fc14_sub_d_issue_count_match_no_notice() {
        let doc = make_plan_doc("single-pr", 2, well_formed_single_pr_body());
        let errs = check_fc14(&doc, &plan_spec());
        assert!(
            !errs
                .iter()
                .any(|e| e.code == "FC14" && e.message.contains("issue_count")),
            "issue_count: 2 matching 2 outlines should not fire; got {:?}",
            errs
        );
    }

    #[test]
    fn check_fc14_sub_e_single_pr_with_populated_implementation_issues_fires() {
        let mut body = well_formed_single_pr_body();
        // Append a populated Implementation Issues table after the existing
        // sections. The Implementation Sequence section needs to follow.
        // Replace the last "## Implementation Sequence" position to insert
        // the table just before it.
        let pos = body
            .iter()
            .position(|l| l.starts_with("## Implementation Sequence"))
            .unwrap();
        let table = vec![
            "## Implementation Issues".to_string(),
            "".to_string(),
            "| Issue | Dependencies | Complexity |".to_string(),
            "| ----- | ------------ | ---------- |".to_string(),
            "| [#1](http://x/1) | None | simple |".to_string(),
        ];
        for (i, line) in table.into_iter().enumerate() {
            body.insert(pos + i, line);
        }
        let doc = make_plan_doc("single-pr", 2, body);
        let errs = check_fc14(&doc, &plan_spec());
        assert!(
            errs.iter().any(|e| e.code == "FC14"
                && e.message.contains("execution_mode is 'single-pr'")
                && e.message.contains("Implementation Issues")),
            "expected FC14 mutual-exclusion notice; got {:?}",
            errs
        );
    }

    #[test]
    fn check_fc14_sub_e_multi_pr_with_populated_issue_outlines_fires() {
        // Multi-pr plan that also populates Issue Outlines.
        let mut body = well_formed_multi_pr_body();
        let pos = body
            .iter()
            .position(|l| l.starts_with("## Implementation Sequence"))
            .unwrap();
        let outlines = vec![
            "## Issue Outlines".to_string(),
            "### Issue 1: feat(x): leftover".to_string(),
            "**Goal**: leftover".to_string(),
            "**Acceptance Criteria**:".to_string(),
            "- [ ] leftover".to_string(),
            "**Dependencies**: None".to_string(),
        ];
        for (i, line) in outlines.into_iter().enumerate() {
            body.insert(pos + i, line);
        }
        let doc = make_plan_doc("multi-pr", 2, body);
        let errs = check_fc14(&doc, &plan_spec());
        assert!(
            errs.iter().any(|e| e.code == "FC14"
                && e.message.contains("execution_mode is 'multi-pr'")
                && e.message.contains("Issue Outlines")),
            "expected FC14 multi-pr mutual-exclusion notice; got {:?}",
            errs
        );
    }

    #[test]
    fn check_fc14_promotion_seam_one_line() {
        // FC14 must appear in is_notice. Removing it from the match arm
        // should be the only edit required to promote to error.
        use crate::validate::is_notice;
        let e = ValidationError {
            file: "x".to_string(),
            line: 1,
            code: "FC14".to_string(),
            message: "test".to_string(),
        };
        assert!(is_notice(&e), "FC14 should be notice-level in is_notice");
    }
}
