//! The validation driver: runs every check for a doc in the order the Go
//! `internal/validate.ValidateFile` runs them, with the same schema-gate
//! early return and the same format-specific dispatch.
//!
//! [`Config`] is re-exported here (it lives in `doc.rs` so `checks.rs` and
//! this module share one declaration) to match the design's public surface
//! `validate::{Config, validate_file, is_notice}`.

use crate::checks::{
    check_fc01, check_fc02, check_fc03, check_fc04, check_fc05, check_fc06, check_fc07,
    check_plan_upstream, check_private_only, check_schema, check_strategy_public,
    check_vision_public,
};
use crate::doc::{Doc, ValidationError};
use crate::formats::FormatSpec;

pub use crate::doc::Config;

/// Reports whether a [`ValidationError`] should be emitted as a GHA
/// `::notice` annotation rather than a `::error`.
///
/// **Promotion seam.** FC07 ships notice-level for v1; remove the
/// `"FC07"` arm from this match to promote the check from notice to
/// error in a single-line diff. The match expression is the one place
/// that drives the notice-vs-error split; the corresponding test in this
/// module (`is_notice_only_schema_and_fc07`) tracks the membership.
///
/// All other codes (`FC01`-`FC06`, `R6`-`R9`) are errors that contribute
/// to a non-zero exit. `SCHEMA` is the long-standing notice; `FC07` is
/// the v1 addition pending the corpus-cleanup PR.
pub fn is_notice(err: &ValidationError) -> bool {
    matches!(err.code.as_str(), "SCHEMA" | "FC07")
}

/// Runs all checks for a given doc against its format spec. Returns a
/// SCHEMA notice (non-error) if the schema gate fires; otherwise returns
/// the FC01-FC06 / R6-R8 errors. Callers must use [`is_notice`] to
/// distinguish notice-level results from error-level results.
pub fn validate_file(doc: &Doc, spec: &FormatSpec, cfg: &Config) -> Vec<ValidationError> {
    // 1. Schema gate: if doc.schema != spec.schema_version, return SCHEMA notice.
    if let Some(schema_err) = check_schema(doc, spec) {
        return vec![schema_err];
    }

    // 1a. Visibility gate (R9): private-only formats short-circuit before FC
    // checks when visibility is not "private", so the failure is the single
    // authoritative reason rather than buried among structural errors.
    let r9 = check_private_only(doc, spec, cfg);
    if !r9.is_empty() {
        return r9;
    }

    // 2. Run FC01, FC02, FC03, FC04 in order, collect all errors.
    let mut errs = Vec::new();
    errs.extend(check_fc01(doc, spec));
    errs.extend(check_fc02(doc, spec, cfg));
    errs.extend(check_fc03(doc, spec));
    errs.extend(check_fc04(doc, spec));

    // 3. Format-specific checks dispatched by spec.name.
    // Casing is intentional per the formats-map entries -- existing names
    // mix conventions ("VISION" all-caps, "Roadmap" / "Strategy" / "Plan" /
    // "Design" / "PRD" otherwise). Do not normalize the case here without
    // updating formats().
    match spec.name.as_str() {
        "Plan" => {
            errs.extend(check_plan_upstream(doc));
            errs.extend(check_fc05(doc, spec));
            errs.extend(check_fc06(doc, spec));
            errs.extend(check_fc07(doc, spec));
        }
        "Roadmap" => {
            errs.extend(check_fc05(doc, spec));
            errs.extend(check_fc06(doc, spec));
            errs.extend(check_fc07(doc, spec));
        }
        "VISION" => {
            errs.extend(check_vision_public(doc, cfg));
        }
        "Strategy" => {
            errs.extend(check_strategy_public(doc, cfg));
        }
        _ => {}
    }

    errs
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

    // --- is_notice (ported from TestIsNotice) ---

    #[test]
    fn is_notice_only_schema() {
        // SCHEMA and FC07 are the notice-level codes for v1. FC07 ships
        // notice-level pending the corpus-cleanup PR; removing the FC07
        // arm from is_notice promotes the check to error.
        assert!(is_notice(&ValidationError {
            file: String::new(),
            line: 0,
            code: "SCHEMA".to_string(),
            message: String::new(),
        }));
        assert!(is_notice(&ValidationError {
            file: String::new(),
            line: 0,
            code: "FC07".to_string(),
            message: String::new(),
        }));
        for code in ["FC01", "FC02", "FC03", "FC04", "FC05", "FC06", "R6", "R7", "R8", "R9"] {
            assert!(
                !is_notice(&ValidationError {
                    file: String::new(),
                    line: 0,
                    code: code.to_string(),
                    message: String::new(),
                }),
                "{} should not be a notice",
                code
            );
        }
    }

    // --- validate_file (ported from TestBriefValidation ValidateFile cases) ---

    fn brief_fields(status: &str) -> HashMap<String, FieldValue> {
        let mut m = HashMap::new();
        m.insert("status".to_string(), fv(status, 2));
        m.insert("problem".to_string(), fv("a problem", 3));
        m.insert("outcome".to_string(), fv("an outcome", 4));
        m
    }

    fn brief_sections(omit: &str) -> Vec<Section> {
        let spec = spec_for("brief/v1");
        spec.required_sections
            .iter()
            .enumerate()
            .filter(|(_, name)| name.as_str() != omit)
            .map(|(i, name)| sec(name, i + 1))
            .collect()
    }

    fn brief_body(status: &str) -> Vec<String> {
        vec!["## Status".to_string(), String::new(), status.to_string()]
    }

    #[test]
    fn validate_file_well_formed_brief_passes() {
        let cfg = Config {
            custom_statuses: HashMap::new(),
            visibility: "public".to_string(),
        };
        let doc = make_doc(
            "brief/v1",
            "Draft",
            brief_fields("Draft"),
            brief_sections(""),
            brief_body("Draft"),
        );
        let errs = validate_file(&doc, &spec_for("brief/v1"), &cfg);
        assert_eq!(errs.len(), 0, "expected no errors, got {:?}", errs);
    }

    #[test]
    fn validate_file_no_brief_specific_check_runs() {
        // BRIEF has no visibility-gated section and no custom check, so a
        // section that would be prohibited for a strategy doc must not
        // trigger any error.
        let cfg = Config {
            custom_statuses: HashMap::new(),
            visibility: "public".to_string(),
        };
        let mut sections = brief_sections("");
        sections.push(sec("Competitive Considerations", 99));
        let doc = make_doc(
            "brief/v1",
            "Draft",
            brief_fields("Draft"),
            sections,
            brief_body("Draft"),
        );
        let errs = validate_file(&doc, &spec_for("brief/v1"), &cfg);
        assert_eq!(
            errs.len(),
            0,
            "expected no errors (no custom check for Brief), got {:?}",
            errs
        );
    }

    #[test]
    fn validate_file_schema_gate_returns_single_notice() {
        // A schema mismatch short-circuits: only the SCHEMA notice comes
        // back, not the FC01-FC04 errors that the missing fields would
        // otherwise produce.
        let cfg = Config::default();
        let doc = make_doc("design/v2", "Proposed", HashMap::new(), vec![], vec![]);
        let errs = validate_file(&doc, &spec_for("design/v1"), &cfg);
        assert_eq!(errs.len(), 1);
        assert_eq!(errs[0].code, "SCHEMA");
        assert!(is_notice(&errs[0]));
    }

    // --- validate_file R9 dispatch (comp/v1 private-only gate) ---

    fn comp_fields(status: &str) -> HashMap<String, FieldValue> {
        let mut m = HashMap::new();
        m.insert("status".to_string(), fv(status, 2));
        m.insert("problem".to_string(), fv("a problem", 3));
        m.insert("scope".to_string(), fv("a scope", 4));
        m
    }

    fn comp_sections(omit: &str) -> Vec<Section> {
        let spec = spec_for("comp/v1");
        spec.required_sections
            .iter()
            .enumerate()
            .filter(|(_, name)| name.as_str() != omit)
            .map(|(i, name)| sec(name, i + 1))
            .collect()
    }

    #[test]
    fn validate_file_comp_passes_under_private() {
        let cfg = Config {
            custom_statuses: HashMap::new(),
            visibility: "private".to_string(),
        };
        let doc = make_doc(
            "comp/v1",
            "Draft",
            comp_fields("Draft"),
            comp_sections(""),
            vec!["## Status".to_string(), String::new(), "Draft".to_string()],
        );
        let errs = validate_file(&doc, &spec_for("comp/v1"), &cfg);
        assert_eq!(errs.len(), 0, "expected no errors under private, got {:?}", errs);
    }

    #[test]
    fn validate_file_comp_public_yields_only_r9() {
        // Omit a required section to prove R9 short-circuits FC04.
        let cfg = Config {
            custom_statuses: HashMap::new(),
            visibility: "public".to_string(),
        };
        let doc = make_doc(
            "comp/v1",
            "Draft",
            comp_fields("Draft"),
            comp_sections("Implications"),
            vec!["## Status".to_string(), String::new(), "Draft".to_string()],
        );
        let errs = validate_file(&doc, &spec_for("comp/v1"), &cfg);
        assert_eq!(errs.len(), 1, "expected exactly one R9 error, got {:?}", errs);
        assert_eq!(errs[0].code, "R9", "R9 must fire before FC checks");
    }
}
