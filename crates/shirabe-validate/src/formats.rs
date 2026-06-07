//! Per-format structural contracts for shirabe doc types.

use std::collections::HashMap;

/// Structural contract for a single shirabe doc format.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct FormatSpec {
    pub name: String,
    pub prefix: String,
    pub schema_version: String,
    pub required_fields: Vec<String>,
    pub valid_statuses: Vec<String>,
    pub required_sections: Vec<String>,
    /// Ordered list of required column headers for the doc's Implementation
    /// Issues table, per the canonical issues-table profile. Empty for
    /// formats without an issues table. FC05 checks the doc's table header
    /// against this list.
    pub issues_table_columns: Vec<String>,
    /// Marks a format whose docs may only be validated under private
    /// visibility. `check_private_only` (R9) rejects such docs when
    /// visibility is not exactly `"private"`, failing closed on the
    /// empty-visibility default.
    pub private: bool,
    /// Optional per-`execution_mode` required-sections override. When
    /// `Some(map)` and the doc's frontmatter carries an `execution_mode`
    /// value that maps in `map`, FC04 consults `map[execution_mode]`
    /// instead of `required_sections`. When `None` (the default for every
    /// format except Plan), FC04 uses `required_sections` as before. Plan
    /// profile populates this with `single-pr` and `multi-pr` lists so the
    /// Plan profile's required-sections check branches on execution mode
    /// without affecting any other profile.
    pub execution_mode_required_sections: Option<HashMap<String, Vec<String>>>,
}

fn s(values: &[&str]) -> Vec<String> {
    values.iter().map(|v| (*v).to_string()).collect()
}

/// Build the Plan profile's per-`execution_mode` required-sections map.
///
/// Returns a map with `"single-pr"` and `"multi-pr"` keys. FC04 consults
/// this map for Plan profile docs when their frontmatter carries an
/// `execution_mode` value; on a hit, the per-mode list replaces the flat
/// `required_sections` for that doc.
fn plan_execution_mode_sections() -> HashMap<String, Vec<String>> {
    let mut m = HashMap::new();
    m.insert(
        "single-pr".to_string(),
        s(&[
            "Status",
            "Scope Summary",
            "Decomposition Strategy",
            "Issue Outlines",
            "Implementation Sequence",
        ]),
    );
    m.insert(
        "multi-pr".to_string(),
        s(&[
            "Status",
            "Scope Summary",
            "Decomposition Strategy",
            "Implementation Issues",
            "Dependency Graph",
            "Implementation Sequence",
        ]),
    );
    m
}

/// Return the canonical list of all known formats.
///
/// The order is stable but not semantically meaningful: `detect_format`
/// performs longest-prefix matching, not iteration-order matching.
pub fn formats() -> Vec<FormatSpec> {
    vec![
        FormatSpec {
            name: "Comp".to_string(),
            prefix: "COMP-".to_string(),
            schema_version: "comp/v1".to_string(),
            required_fields: s(&["status", "problem", "scope"]),
            valid_statuses: s(&["Draft", "Accepted", "Done"]),
            required_sections: s(&[
                "Status",
                "Market Overview",
                "Competitors",
                "Comparative Matrix",
                "Opportunities",
                "Implications",
                "References",
            ]),
            issues_table_columns: vec![],
            private: true,
            execution_mode_required_sections: None,
        },
        FormatSpec {
            name: "Design".to_string(),
            prefix: "DESIGN-".to_string(),
            schema_version: "design/v1".to_string(),
            required_fields: s(&["status", "problem", "decision", "rationale"]),
            valid_statuses: s(&["Proposed", "Accepted", "Planned", "Current", "Superseded"]),
            required_sections: s(&[
                "Status",
                "Context and Problem Statement",
                "Decision Drivers",
                "Considered Options",
                "Decision Outcome",
                "Solution Architecture",
                "Implementation Approach",
                "Security Considerations",
                "Consequences",
            ]),
            issues_table_columns: vec![],
            private: false,
            execution_mode_required_sections: None,
        },
        FormatSpec {
            name: "PRD".to_string(),
            prefix: "PRD-".to_string(),
            schema_version: "prd/v1".to_string(),
            required_fields: s(&["status", "problem", "goals"]),
            valid_statuses: s(&["Draft", "Accepted", "In Progress", "Done"]),
            required_sections: s(&[
                "Status",
                "Problem Statement",
                "Goals",
                "User Stories",
                "Requirements",
                "Acceptance Criteria",
                "Out of Scope",
            ]),
            issues_table_columns: vec![],
            private: false,
            execution_mode_required_sections: None,
        },
        FormatSpec {
            name: "VISION".to_string(),
            prefix: "VISION-".to_string(),
            schema_version: "vision/v1".to_string(),
            required_fields: s(&["status", "thesis", "scope"]),
            valid_statuses: s(&["Draft", "Accepted", "Active", "Sunset"]),
            required_sections: s(&[
                "Status",
                "Thesis",
                "Audience",
                "Value Proposition",
                "Org Fit",
                "Success Criteria",
                "Non-Goals",
            ]),
            issues_table_columns: vec![],
            private: false,
            execution_mode_required_sections: None,
        },
        FormatSpec {
            name: "Roadmap".to_string(),
            prefix: "ROADMAP-".to_string(),
            schema_version: "roadmap/v1".to_string(),
            required_fields: s(&["status", "theme", "scope"]),
            valid_statuses: s(&["Draft", "Active", "Done"]),
            required_sections: s(&[
                "Status",
                "Theme",
                "Features",
                "Sequencing Rationale",
                "Progress",
                "Implementation Issues",
                "Dependency Graph",
            ]),
            issues_table_columns: s(&["Feature", "Issues", "Dependencies", "Status"]),
            private: false,
            execution_mode_required_sections: None,
        },
        FormatSpec {
            name: "Plan".to_string(),
            prefix: "PLAN-".to_string(),
            schema_version: "plan/v1".to_string(),
            required_fields: s(&["status", "execution_mode", "milestone", "issue_count"]),
            valid_statuses: s(&["Draft", "Active", "Done"]),
            required_sections: s(&[
                "Status",
                "Scope Summary",
                "Decomposition Strategy",
                "Implementation Issues",
                "Dependency Graph",
                "Implementation Sequence",
            ]),
            issues_table_columns: s(&["Issue", "Dependencies", "Complexity"]),
            private: false,
            execution_mode_required_sections: Some(plan_execution_mode_sections()),
        },
        FormatSpec {
            name: "Strategy".to_string(),
            prefix: "STRATEGY-".to_string(),
            schema_version: "strategy/v1".to_string(),
            required_fields: s(&["status", "bet", "scope"]),
            valid_statuses: s(&["Draft", "Accepted", "Active", "Sunset"]),
            required_sections: s(&[
                "Status",
                "Strategic Context",
                "Defensibility Thesis",
                "Building Blocks",
                "Coordination Dependencies",
                "Bet-Specific Falsifiability",
                "Non-Goals",
                "Downstream Artifacts",
            ]),
            issues_table_columns: vec![],
            private: false,
            execution_mode_required_sections: None,
        },
        FormatSpec {
            name: "Brief".to_string(),
            prefix: "BRIEF-".to_string(),
            schema_version: "brief/v1".to_string(),
            required_fields: s(&["status", "problem", "outcome"]),
            valid_statuses: s(&["Draft", "Accepted", "Done"]),
            required_sections: s(&[
                "Status",
                "Problem Statement",
                "User Outcome",
                "User Journeys",
                "Scope Boundary",
            ]),
            issues_table_columns: vec![],
            private: false,
            execution_mode_required_sections: None,
        },
    ]
}

/// Return the `FormatSpec` whose `prefix` matches the start of `basename`.
///
/// When multiple prefixes could match, the longest match wins. Returns
/// `None` if no format matches.
pub fn detect_format(basename: &str) -> Option<FormatSpec> {
    let mut best: Option<FormatSpec> = None;
    for spec in formats() {
        if basename.starts_with(&spec.prefix) {
            match &best {
                None => best = Some(spec),
                Some(current) if spec.prefix.len() > current.prefix.len() => best = Some(spec),
                _ => {}
            }
        }
    }
    best
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn detect_format_matches_known_prefixes() {
        assert_eq!(
            detect_format("DESIGN-foo.md").map(|f| f.schema_version),
            Some("design/v1".to_string())
        );
        assert_eq!(
            detect_format("PRD-bar.md").map(|f| f.schema_version),
            Some("prd/v1".to_string())
        );
        assert_eq!(
            detect_format("PLAN-baz.md").map(|f| f.schema_version),
            Some("plan/v1".to_string())
        );
    }

    #[test]
    fn detect_format_returns_none_for_unknown() {
        assert!(detect_format("README.md").is_none());
        assert!(detect_format("notes.md").is_none());
    }

    #[test]
    fn detect_format_matches_comp_prefix() {
        let spec = detect_format("COMP-acme.md").expect("COMP- should match a format");
        assert_eq!(spec.schema_version, "comp/v1");
        assert_eq!(spec.name, "Comp");
        assert!(spec.private, "comp/v1 must be private");
    }

    #[test]
    fn detect_format_returns_eight_formats() {
        assert_eq!(formats().len(), 8);
    }
}
