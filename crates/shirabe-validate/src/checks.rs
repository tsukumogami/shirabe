//! The individual validation checks (SCHEMA, FC01-FC06, R6, R7, R8).
//!
//! Each check inspects a parsed [`Doc`] against its [`FormatSpec`] and
//! returns one [`ValidationError`] per violation (an empty vec means the
//! check passed). `validate.rs` calls these in order from `validate_file`.
//!
//! Message strings are preserved byte-for-byte from the Go
//! `internal/validate/checks.go` so the annotation output stays identical.

use std::path::Path;
use std::process::Command;

use crate::doc::{Config, Doc, ValidationError};
use crate::formats::FormatSpec;
use crate::table::{parse_issues_table, RowKind, Table};

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
}
