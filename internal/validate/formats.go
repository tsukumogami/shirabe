package validate

import "strings"

// FormatSpec describes the structural contract for a single shirabe doc format.
type FormatSpec struct {
	Name             string
	Prefix           string
	SchemaVersion    string
	RequiredFields   []string
	ValidStatuses    []string
	RequiredSections []string
}

// Formats maps schema version strings to their FormatSpec.
var Formats = map[string]FormatSpec{
	"design/v1": {
		Name:          "Design",
		Prefix:        "DESIGN-",
		SchemaVersion: "design/v1",
		RequiredFields: []string{"status", "problem", "decision", "rationale"},
		ValidStatuses:  []string{"Proposed", "Accepted", "Planned", "Current", "Superseded"},
		RequiredSections: []string{
			"Status",
			"Context and Problem Statement",
			"Decision Drivers",
			"Considered Options",
			"Decision Outcome",
			"Solution Architecture",
			"Implementation Approach",
			"Security Considerations",
			"Consequences",
		},
	},
	"prd/v1": {
		Name:          "PRD",
		Prefix:        "PRD-",
		SchemaVersion: "prd/v1",
		RequiredFields: []string{"status", "problem", "goals"},
		ValidStatuses:  []string{"Draft", "Accepted", "In Progress", "Done"},
		RequiredSections: []string{
			"Status",
			"Problem Statement",
			"Goals",
			"User Stories",
			"Requirements",
			"Acceptance Criteria",
			"Out of Scope",
		},
	},
	"vision/v1": {
		Name:          "VISION",
		Prefix:        "VISION-",
		SchemaVersion: "vision/v1",
		RequiredFields: []string{"status", "thesis", "scope"},
		ValidStatuses:  []string{"Draft", "Accepted", "Active", "Sunset"},
		RequiredSections: []string{
			"Status",
			"Thesis",
			"Audience",
			"Value Proposition",
			"Org Fit",
			"Success Criteria",
			"Non-Goals",
		},
	},
	"roadmap/v1": {
		Name:          "Roadmap",
		Prefix:        "ROADMAP-",
		SchemaVersion: "roadmap/v1",
		RequiredFields: []string{"status", "theme", "scope"},
		ValidStatuses:  []string{"Draft", "Active", "Done"},
		RequiredSections: []string{
			"Status",
			"Theme",
			"Features",
			"Sequencing Rationale",
			"Progress",
			"Implementation Issues",
			"Dependency Graph",
		},
	},
	"plan/v1": {
		Name:          "Plan",
		Prefix:        "PLAN-",
		SchemaVersion: "plan/v1",
		RequiredFields: []string{"status", "execution_mode", "milestone", "issue_count"},
		ValidStatuses:  []string{"Draft", "Active", "Done"},
		RequiredSections: []string{
			"Status",
			"Scope Summary",
			"Decomposition Strategy",
			"Implementation Issues",
			"Dependency Graph",
			"Implementation Sequence",
		},
	},
}

// DetectFormat returns the FormatSpec whose Prefix matches the start of basename.
// When multiple prefixes could match, the longest match wins.
// Returns (FormatSpec{}, false) if no format matches.
func DetectFormat(basename string) (FormatSpec, bool) {
	var best FormatSpec
	matched := false
	for _, spec := range Formats {
		if strings.HasPrefix(basename, spec.Prefix) {
			if !matched || len(spec.Prefix) > len(best.Prefix) {
				best = spec
				matched = true
			}
		}
	}
	return best, matched
}
