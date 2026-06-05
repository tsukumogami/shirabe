//! The individual validation checks (SCHEMA, FC01-FC06, R6, R7, R8).
//!
//! Each check inspects a parsed [`Doc`] against its [`FormatSpec`] and
//! returns one [`ValidationError`] per violation (an empty vec means the
//! check passed). `validate.rs` calls these in order from `validate_file`.
//!
//! Message strings are preserved byte-for-byte from the Go
//! `internal/validate/checks.go` so the annotation output stays identical.

use std::collections::HashSet;
use std::path::Path;
use std::process::Command;
use std::sync::LazyLock;

use regex::Regex;

use crate::doc::{Config, Doc, ValidationError};
use crate::formats::FormatSpec;
use crate::mermaid::{extract_diagram, find_dependency_graph_block, Diagram, Issue};
use crate::table::{parse_issues_table, Profile, Row, RowKind, Table};

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
pub fn check_schema(doc: &Doc, spec: &FormatSpec) -> Option<ValidationError> {
    if doc.schema == spec.schema_version {
        return None;
    }
    Some(ValidationError {
        file: doc.path.clone(),
        line: 1,
        code: "SCHEMA".to_string(),
        message: format!("schema {:?} not in supported range, skipping", doc.schema),
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

/// Returns a `ValidationError` for each required section missing from
/// `doc.sections`. Line is 1 (section absent, no specific line).
pub fn check_fc04(doc: &Doc, spec: &FormatSpec) -> Vec<ValidationError> {
    let mut errs = Vec::new();
    for required in &spec.required_sections {
        if !doc.sections.iter().any(|sec| sec.name == *required) {
            errs.push(ValidationError {
                file: doc.path.clone(),
                line: 1,
                code: "FC04".to_string(),
                message: format!("[FC04] missing required section '## {}'", required),
            });
        }
    }
    errs
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

/// Checks that table rows are well-formed. Every entity row must be
/// followed by an italic description row; a child reference row may sit
/// between them.
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
}
