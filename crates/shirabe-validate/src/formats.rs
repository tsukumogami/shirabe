//! Per-format structural contracts for shirabe doc types.

use std::collections::HashMap;

/// The identity of a shirabe artifact type.
///
/// Deliberately separate from [`FormatSpec::name`], whose casing is
/// inconsistent on purpose (`VISION` and `PRD` are upper-case, the rest are
/// not) because `validate_file`'s format dispatch matches those exact strings.
/// Naming a type by an enum rather than by that string keeps
/// [`FormatSpec::legal_upstream`] total: an entry cannot be a typo that
/// compiles, reads correctly to a human, and silently never matches.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum FormatId {
    Vision,
    Strategy,
    Roadmap,
    Brief,
    Prd,
    Design,
    Plan,
    Comp,
}

impl FormatId {
    /// The type's name as a finding message spells it. Upper-case throughout,
    /// independent of the dispatch strings in [`FormatSpec::name`].
    pub fn display(self) -> &'static str {
        match self {
            FormatId::Vision => "VISION",
            FormatId::Strategy => "STRATEGY",
            FormatId::Roadmap => "ROADMAP",
            FormatId::Brief => "BRIEF",
            FormatId::Prd => "PRD",
            FormatId::Design => "DESIGN",
            FormatId::Plan => "PLAN",
            FormatId::Comp => "COMP",
        }
    }
}

/// Whether a type's documents survive the completion of their own work.
///
/// `Working` documents are deleted by the finalization cascade when their work
/// completes; `Durable` documents stay in `docs/` as the audit trail. The
/// classes are the ones each skill's `## Artifact Lifecycle` section declares,
/// and this field is the authority the legality check reads.
///
/// [`crate::lifecycle::target_state_for`] is a second, partial spelling of the
/// same fact for five of the eight types. The two are not derived from each
/// other, because that map also encodes *which* status is terminal; a test in
/// this module asserts they agree on the five they share.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Lifetime {
    Durable,
    Working,
}

/// Structural contract for a single shirabe doc format.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct FormatSpec {
    pub name: String,
    /// The type's identity, used by the upstream-legality check and by any
    /// finding message that has to name a type.
    pub id: FormatId,
    /// Whether the type's documents survive the completion of their own work.
    pub lifetime: Lifetime,
    /// The types that may be named as this type's `upstream:`. An empty list
    /// states that the type is always the head of its own lineage.
    ///
    /// **Invariant:** no `Durable` format may list a `Working` format here. A
    /// durable document naming a working one holds a reference with a
    /// scheduled death date, and the invariant is what keeps that shape from
    /// being reintroduced by editing this table. It is enforced by
    /// `no_durable_format_declares_a_working_parent` below.
    pub legal_upstream: Vec<FormatId>,
    pub prefix: String,
    pub schema_version: String,
    pub required_fields: Vec<String>,
    pub valid_statuses: Vec<String>,
    /// The required section headings. **Element order is significant:** FC04
    /// checks presence, and FC15 checks that the present required sections
    /// appear in this order. Reordering entries changes the canonical order
    /// FC15 enforces (it would surface an FC15 notice on docs written to the
    /// old order), so treat the sequence as a contract, not a decorative list.
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
    /// profile populates this with `single-pr`, `multi-pr`, and `coordinated`
    /// lists so the Plan profile's required-sections check branches on
    /// execution mode without affecting any other profile.
    pub execution_mode_required_sections: Option<HashMap<String, Vec<String>>>,
}

impl FormatSpec {
    /// A spec carrying no structural expectations, for the prose family.
    ///
    /// The prose checks take a `&FormatSpec` for signature uniformity with
    /// the rest of the check surface but read nothing from it. Every field
    /// is empty so that a check reaching for a required field or section
    /// through this spec finds nothing to assert rather than asserting the
    /// wrong format's shape against an arbitrary file.
    pub fn prose_only() -> Self {
        FormatSpec {
            name: "Prose".to_string(),
            prefix: String::new(),
            schema_version: String::new(),
            required_fields: Vec::new(),
            valid_statuses: Vec::new(),
            required_sections: Vec::new(),
            issues_table_columns: Vec::new(),
            private: false,
            execution_mode_required_sections: None,
        }
    }
}

fn s(values: &[&str]) -> Vec<String> {
    values.iter().map(|v| (*v).to_string()).collect()
}

/// Build the Plan profile's per-`execution_mode` required-sections map.
///
/// Returns a map with `"single-pr"`, `"multi-pr"`, and `"coordinated"` keys.
/// FC04 consults this map for Plan profile docs when their frontmatter carries
/// an `execution_mode` value; on a hit, the per-mode list replaces the flat
/// `required_sections` for that doc.
///
/// `coordinated` is the multi-repo generalization of `multi-pr` (see
/// `references/coordination-strategy.md`). Its section shape is modeled on
/// `multi-pr`: an Implementation Issues table plus a Dependency Graph that the
/// /plan contraction collapses into a two-node `(repo, pr_group)` merge-order
/// DAG. It carries the same required sections as `multi-pr`.
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
    let multi_pr_sections = s(&[
        "Status",
        "Scope Summary",
        "Decomposition Strategy",
        "Implementation Issues",
        "Dependency Graph",
        "Implementation Sequence",
    ]);
    m.insert("multi-pr".to_string(), multi_pr_sections.clone());
    // Coordinated mode shares multi-pr's section shape: it is always multi-PR
    // and adds the coordination PR + two-node merge-order DAG on top.
    m.insert("coordinated".to_string(), multi_pr_sections);
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
            id: FormatId::Comp,
            lifetime: Lifetime::Durable,
            legal_upstream: vec![],
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
            id: FormatId::Design,
            lifetime: Lifetime::Durable,
            legal_upstream: vec![FormatId::Prd, FormatId::Brief],
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
            id: FormatId::Prd,
            lifetime: Lifetime::Durable,
            legal_upstream: vec![FormatId::Brief],
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
            id: FormatId::Vision,
            lifetime: Lifetime::Durable,
            legal_upstream: vec![FormatId::Vision],
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
            id: FormatId::Roadmap,
            lifetime: Lifetime::Working,
            // A STRATEGY when one was written, a VISION when none was. This
            // check reads two basenames and nothing else, so it cannot tell a
            // roadmap that skipped an existing strategy from one written where
            // no strategy exists -- and rejecting the second to catch the first
            // would fail the legitimate case. Preferring the nearest altitude
            // is authoring guidance, stated in `/roadmap`'s own contract; what
            // is enforced here is direction.
            legal_upstream: vec![FormatId::Strategy, FormatId::Vision],
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
            id: FormatId::Plan,
            lifetime: Lifetime::Working,
            legal_upstream: vec![FormatId::Design, FormatId::Prd, FormatId::Brief, FormatId::Roadmap],
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
            id: FormatId::Strategy,
            lifetime: Lifetime::Durable,
            legal_upstream: vec![FormatId::Vision],
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
            id: FormatId::Brief,
            lifetime: Lifetime::Durable,
            legal_upstream: vec![],
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

    #[test]
    fn plan_execution_mode_sections_includes_coordinated() {
        let map = plan_execution_mode_sections();
        // The third coordinated mode is recognized alongside single-pr/multi-pr.
        assert!(map.contains_key("single-pr"));
        assert!(map.contains_key("multi-pr"));
        assert!(
            map.contains_key("coordinated"),
            "coordinated must be a recognized execution_mode section profile"
        );
        // Coordinated shares multi-pr's required-section shape (it is the
        // multi-repo generalization of multi-pr).
        assert_eq!(
            map.get("coordinated"),
            map.get("multi-pr"),
            "coordinated section shape must mirror multi-pr"
        );
    }

    /// The invariant behind the whole upstream-legality rule: a durable
    /// document may not name a working one, so no durable format may declare a
    /// working format among its legal parents. Enforcing it here rather than
    /// only against documents means a maintainer who adds such a type finds out
    /// from this test rather than from a dangling link months later.
    #[test]
    fn no_durable_format_declares_a_working_parent() {
        let by_id: HashMap<FormatId, Lifetime> =
            formats().into_iter().map(|f| (f.id, f.lifetime)).collect();
        for spec in formats() {
            if spec.lifetime != Lifetime::Durable {
                continue;
            }
            for parent in &spec.legal_upstream {
                let parent_lifetime = by_id
                    .get(parent)
                    .copied()
                    .unwrap_or_else(|| panic!("{} names an unknown parent", spec.id.display()));
                assert_ne!(
                    parent_lifetime,
                    Lifetime::Working,
                    "{} is Durable and declares {} (Working) as a legal upstream; \
                     a durable document must not name one whose deletion is scheduled",
                    spec.id.display(),
                    parent.display()
                );
            }
        }
    }

    /// The declared table, asserted verbatim. A single changed entry in any row
    /// fails here rather than silently widening or narrowing what the legality
    /// check accepts.
    #[test]
    fn declared_lifetimes_and_parent_sets_match_the_contract() {
        let expected: Vec<(FormatId, Lifetime, Vec<FormatId>)> = vec![
            (FormatId::Vision, Lifetime::Durable, vec![FormatId::Vision]),
            (FormatId::Strategy, Lifetime::Durable, vec![FormatId::Vision]),
            (
                FormatId::Roadmap,
                Lifetime::Working,
                vec![FormatId::Strategy, FormatId::Vision],
            ),
            (FormatId::Brief, Lifetime::Durable, vec![]),
            (FormatId::Prd, Lifetime::Durable, vec![FormatId::Brief]),
            (
                FormatId::Design,
                Lifetime::Durable,
                vec![FormatId::Prd, FormatId::Brief],
            ),
            (
                FormatId::Plan,
                Lifetime::Working,
                vec![
                    FormatId::Design,
                    FormatId::Prd,
                    FormatId::Brief,
                    FormatId::Roadmap,
                ],
            ),
            (FormatId::Comp, Lifetime::Durable, vec![]),
        ];

        let specs = formats();
        assert_eq!(
            specs.len(),
            expected.len(),
            "every format must appear in the contract table"
        );

        for (id, lifetime, parents) in expected {
            let spec = specs
                .iter()
                .find(|f| f.id == id)
                .unwrap_or_else(|| panic!("no format declares id {}", id.display()));
            assert_eq!(
                spec.lifetime,
                lifetime,
                "{} lifetime",
                id.display()
            );
            assert_eq!(
                spec.legal_upstream,
                parents,
                "{} legal_upstream (order is significant)",
                id.display()
            );
        }
    }

    /// `lifetime` and `lifecycle::target_state_for` are two spellings of the
    /// same fact for the five types the latter covers. They are deliberately
    /// not derived from each other -- that map also encodes *which* status is
    /// terminal -- so this test is what keeps them from drifting. `lifetime` is
    /// the authority for legality; the map is the authority for finalization.
    #[test]
    fn lifetime_agrees_with_the_finalization_terminal_map() {
        use crate::lifecycle::{target_state_for, TargetState};
        for spec in formats() {
            match target_state_for(&spec.name) {
                TargetState::Deleted => assert_eq!(
                    spec.lifetime,
                    Lifetime::Working,
                    "{} is deleted at finalization, so it is Working",
                    spec.id.display()
                ),
                TargetState::Status(_) => assert_eq!(
                    spec.lifetime,
                    Lifetime::Durable,
                    "{} transitions to a terminal status rather than being deleted, \
                     so it is Durable",
                    spec.id.display()
                ),
                // VISION, STRATEGY and COMP are outside the finalization walk;
                // the map has nothing to say about them.
                TargetState::Unknown => {}
            }
        }
    }

    /// Every spec's `id` is the id of the format it sits on, and every id is
    /// used once. This is the mistake `FormatId` exists to make impossible: a
    /// newly added `FormatSpec` literal with a copy-pasted `id:` would mistype
    /// every finding message and every parent lookup for that format, and
    /// nothing else in the file would notice. Tying the id to the prefix
    /// catches it, because the prefix is what `detect_format` routes on.
    #[test]
    fn each_spec_id_matches_its_prefix_and_is_unique() {
        let mut seen: HashMap<FormatId, String> = HashMap::new();
        for spec in formats() {
            assert_eq!(
                spec.prefix,
                format!("{}-", spec.id.display()),
                "{}'s id and prefix disagree",
                spec.name
            );
            if let Some(other) = seen.insert(spec.id, spec.name.clone()) {
                panic!("{} and {} both declare id {}", other, spec.name, spec.id.display());
            }
        }
        assert_eq!(seen.len(), formats().len(), "every format declares its own id");
    }

    #[test]
    fn plan_profile_carries_coordinated_section_override() {
        let plan = detect_format("PLAN-x.md").expect("PLAN- matches the Plan profile");
        let map = plan
            .execution_mode_required_sections
            .expect("Plan profile must carry per-execution_mode sections");
        assert!(map.contains_key("coordinated"));
    }
}
