//! Per-format structural contracts for shirabe doc types.

/// Structural contract for a single shirabe doc format.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct FormatSpec {
    pub name: String,
    pub prefix: String,
    pub schema_version: String,
    pub required_fields: Vec<String>,
    pub valid_statuses: Vec<String>,
    pub required_sections: Vec<String>,
}

fn s(values: &[&str]) -> Vec<String> {
    values.iter().map(|v| (*v).to_string()).collect()
}

/// Return the canonical list of all known formats.
///
/// The order is stable but not semantically meaningful: `detect_format`
/// performs longest-prefix matching, not iteration-order matching.
pub fn formats() -> Vec<FormatSpec> {
    vec![
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
    fn detect_format_returns_seven_formats() {
        assert_eq!(formats().len(), 7);
    }
}
