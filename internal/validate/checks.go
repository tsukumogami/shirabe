package validate

import (
	"fmt"
	"os"
	"os/exec"
	"strings"
)

// prohibitedPublicVisionSections lists section names that vision/v1 docs must not
// contain in public repos. See design DESIGN-gha-doc-validation.md (R7).
var prohibitedPublicVisionSections = []string{
	"Competitive Positioning",
	"Resource Implications",
}

// prohibitedPublicStrategySections lists section names that strategy/v1 docs must
// not contain in public repos. See DESIGN-shirabe-strategy-skill.md (R8).
var prohibitedPublicStrategySections = []string{
	"Competitive Considerations",
}

// checkSchema returns a SCHEMA ValidationError (to be emitted as ::notice) if
// doc.Schema is not spec.SchemaVersion. Returns nil if schema matches.
func checkSchema(doc Doc, spec FormatSpec) *ValidationError {
	if doc.Schema == spec.SchemaVersion {
		return nil
	}
	return &ValidationError{
		File:    doc.Path,
		Line:    1,
		Code:    "SCHEMA",
		Message: fmt.Sprintf("schema %q not in supported range, skipping", doc.Schema),
	}
}

// checkFC01 returns a ValidationError for each required field missing from doc.Fields.
// Line is 1 (field is absent, no specific line).
func checkFC01(doc Doc, spec FormatSpec) []ValidationError {
	var errs []ValidationError
	for _, field := range spec.RequiredFields {
		if _, ok := doc.Fields[field]; !ok {
			errs = append(errs, ValidationError{
				File:    doc.Path,
				Line:    1,
				Code:    "FC01",
				Message: fmt.Sprintf("[FC01] missing required field %q", field),
			})
		}
	}
	return errs
}

// checkFC02 validates doc.Status is in the accepted enum.
// Uses cfg.CustomStatuses[spec.SchemaVersion] if set (replacement, not extension).
// Line is doc.Fields["status"].Line if present, else 1.
func checkFC02(doc Doc, spec FormatSpec, cfg Config) []ValidationError {
	if doc.Status == "" {
		return nil
	}

	validStatuses := spec.ValidStatuses
	if custom, ok := cfg.CustomStatuses[spec.SchemaVersion]; ok {
		validStatuses = custom
	}

	for _, s := range validStatuses {
		if doc.Status == s {
			return nil
		}
	}

	line := 1
	if fv, ok := doc.Fields["status"]; ok {
		line = fv.Line
	}

	return []ValidationError{
		{
			File:    doc.Path,
			Line:    line,
			Code:    "FC02",
			Message: fmt.Sprintf("[FC02] status %q is not valid for %s docs. Valid values: %s", doc.Status, spec.Name, strings.Join(validStatuses, ", ")),
		},
	}
}

// checkFC03 finds ## Status section in doc.Body, reads the next non-blank line,
// and compares case-insensitively with doc.Status.
// Does NOT fire if ## Status section has no non-blank body text.
// Line is the Section.Line of the ## Status heading.
func checkFC03(doc Doc, spec FormatSpec) []ValidationError {
	// Find the ## Status section line number.
	statusLine := -1
	for _, sec := range doc.Sections {
		if sec.Name == "Status" {
			statusLine = sec.Line
			break
		}
	}
	if statusLine == -1 {
		return nil
	}

	// Scan doc.Body for "## Status" and find the next non-blank line.
	foundHeading := false
	bodyStatus := ""
	for _, line := range doc.Body {
		if !foundHeading {
			if strings.TrimRight(line, " \t") == "## Status" {
				foundHeading = true
			}
			continue
		}
		// We are past the ## Status heading.
		trimmed := strings.TrimSpace(line)
		if trimmed == "" {
			continue
		}
		// Stop if we hit another heading.
		if strings.HasPrefix(line, "#") {
			break
		}
		bodyStatus = trimmed
		break
	}

	// No non-blank body text after ## Status — skip.
	if bodyStatus == "" {
		return nil
	}

	if strings.EqualFold(doc.Status, bodyStatus) {
		return nil
	}

	return []ValidationError{
		{
			File:    doc.Path,
			Line:    statusLine,
			Code:    "FC03",
			Message: fmt.Sprintf("[FC03] frontmatter status %q does not match ## Status body %q", doc.Status, bodyStatus),
		},
	}
}

// checkFC04 returns a ValidationError for each required section missing from doc.Sections.
// Line is 1 (section absent, no specific line).
func checkFC04(doc Doc, spec FormatSpec) []ValidationError {
	present := make(map[string]bool, len(doc.Sections))
	for _, sec := range doc.Sections {
		present[sec.Name] = true
	}

	var errs []ValidationError
	for _, required := range spec.RequiredSections {
		if !present[required] {
			errs = append(errs, ValidationError{
				File:    doc.Path,
				Line:    1,
				Code:    "FC04",
				Message: fmt.Sprintf("[FC04] missing required section '## %s'", required),
			})
		}
	}
	return errs
}

// legacyPlanTableColumns is the historic four-column plan-table shape
// (Issue | Title | Dependencies | Complexity). FC05 recognizes it
// specially to emit a migration hint pointing the author at the
// canonical three-column shape.
var legacyPlanTableColumns = []string{"Issue", "Title", "Dependencies", "Complexity"}

// checkFC05 validates that the Implementation Issues table header
// matches the format's required column contract (R6). The profile is
// selected by spec.IssuesTableColumns -- absent (empty) means the
// format has no issues table and the check is a no-op.
//
// FC05 is error-level. A legacy plan-table shape (Issue | Title |
// Dependencies | Complexity) emits a migration-hint message rather
// than a generic schema-mismatch message, pointing the author at the
// canonical three-column shape.
func checkFC05(doc Doc, spec FormatSpec) []ValidationError {
	if len(spec.IssuesTableColumns) == 0 {
		return nil
	}
	table, ok := parseIssuesTable(doc)
	if !ok {
		return nil
	}

	// Detect the legacy plan-table shape and emit a migration hint.
	if spec.SchemaVersion == "plan/v1" && stringSlicesEqual(table.Columns, legacyPlanTableColumns) {
		return []ValidationError{
			{
				File:    doc.Path,
				Line:    table.HeaderLine,
				Code:    "FC05",
				Message: `[FC05] legacy plan table shape "Issue | Title | Dependencies | Complexity" found; migrate by folding the Title cell into the issue link text: "[#N: <title>](url) | <deps> | <complexity>"`,
			},
		}
	}

	if stringSlicesEqual(table.Columns, spec.IssuesTableColumns) {
		return validateRowShape(doc, table)
	}

	want := strings.Join(spec.IssuesTableColumns, " | ")
	got := strings.Join(table.Columns, " | ")
	return []ValidationError{
		{
			File:    doc.Path,
			Line:    table.HeaderLine,
			Code:    "FC05",
			Message: fmt.Sprintf(`[FC05] issues-table header %q does not match the %s profile (expected %q)`, got, spec.Name, want),
		},
	}
}

// validateRowShape checks that table rows are well-formed. Every entity
// row must be followed by an italic description row; a child reference
// row may sit between them.
func validateRowShape(doc Doc, table Table) []ValidationError {
	var errs []ValidationError

	// Each entity row must be followed by a description row, optionally
	// with one child reference row between them.
	for i, row := range table.Rows {
		if row.Kind != RowEntity {
			continue
		}
		next := i + 1
		// Skip a single child reference row if present.
		if next < len(table.Rows) && table.Rows[next].Kind == RowChild {
			next++
		}
		if next >= len(table.Rows) || table.Rows[next].Kind != RowDescription {
			errs = append(errs, ValidationError{
				File:    doc.Path,
				Line:    row.Line,
				Code:    "FC05",
				Message: fmt.Sprintf(`[FC05] entity row at line %d is missing its description row (expected an italic "_..._" row immediately after)`, row.Line),
			})
		}
	}

	return errs
}

// checkFC06 verifies that every Dependencies value in an entity row
// names a key that exists as an entity row in the same table (R7). The
// check is document-local (no graph model). FC06 is error-level.
//
// FC06 is a no-op when the format has no issues table or the table is
// absent.
func checkFC06(doc Doc, spec FormatSpec) []ValidationError {
	if len(spec.IssuesTableColumns) == 0 {
		return nil
	}
	table, ok := parseIssuesTable(doc)
	if !ok {
		return nil
	}

	// Build the entity-row key set.
	keys := make(map[string]bool, len(table.Rows))
	for _, row := range table.Rows {
		if row.Kind == RowEntity && row.Key != "" {
			keys[row.Key] = true
		}
	}

	var errs []ValidationError
	for _, row := range table.Rows {
		if row.Kind != RowEntity {
			continue
		}
		for _, dep := range row.Deps {
			if dep == "" {
				continue
			}
			// Cross-repo refs (`tsukumogami/<repo>#N`, `owner/repo#N`)
			// and bare external URLs are out of scope for the
			// document-local check. We only flag intra-doc references
			// that look like the doc's own key form but don't match.
			if !isLocalKey(dep) {
				continue
			}
			if !keys[dep] {
				errs = append(errs, ValidationError{
					File:    doc.Path,
					Line:    row.Line,
					Code:    "FC06",
					Message: fmt.Sprintf(`[FC06] dependency %q in row %q names no row in this table`, dep, row.Key),
				})
			}
		}
	}
	return errs
}

// isLocalKey reports whether dep looks like a document-local key (a
// bare `#N` token or a feature label). Cross-repo references with a
// slash before the `#` are not local.
func isLocalKey(dep string) bool {
	if strings.HasPrefix(dep, "#") {
		return true
	}
	// A feature label is local; a `owner/repo#N` is not (it has a `/`).
	if strings.Contains(dep, "/") {
		return false
	}
	return true
}

// stringSlicesEqual reports whether two slices have the same length
// and the same elements in order.
func stringSlicesEqual(a, b []string) bool {
	if len(a) != len(b) {
		return false
	}
	for i := range a {
		if a[i] != b[i] {
			return false
		}
	}
	return true
}

// checkPlanUpstream (R6) verifies that a Plan doc's upstream field points at a
// file that exists on disk and is tracked by git. The field is optional; an
// absent upstream value returns nil. The git tracking check runs `git ls-files
// --error-unmatch` in the process's current working directory (which in a GHA
// context is the caller repo's checkout, not the embedded shirabe source tree),
// so callers must not override the working directory when invoking the check.
func checkPlanUpstream(doc Doc) []ValidationError {
	field, ok := doc.Fields["upstream"]
	if !ok {
		return nil
	}

	path := field.Value
	if _, err := os.Stat(path); err != nil {
		return []ValidationError{
			{
				File:    doc.Path,
				Line:    field.Line,
				Code:    "R6",
				Message: fmt.Sprintf("[R6] upstream %q does not exist on disk", path),
			},
		}
	}

	cmd := exec.Command("git", "ls-files", "--error-unmatch", "--", path)
	if err := cmd.Run(); err != nil {
		return []ValidationError{
			{
				File:    doc.Path,
				Line:    field.Line,
				Code:    "R6",
				Message: fmt.Sprintf("[R6] upstream %q is not tracked by git", path),
			},
		}
	}

	return nil
}

// checkVisionPublic (R7) flags VISION docs that surface sections forbidden in
// public repos. The check is bypassed only when cfg.Visibility is exactly
// "private"; any other value (including the empty string) fails closed and the
// check runs.
func checkVisionPublic(doc Doc, cfg Config) []ValidationError {
	if cfg.Visibility == "private" {
		return nil
	}

	prohibited := make(map[string]bool, len(prohibitedPublicVisionSections))
	for _, name := range prohibitedPublicVisionSections {
		prohibited[name] = true
	}

	var errs []ValidationError
	for _, sec := range doc.Sections {
		if prohibited[sec.Name] {
			errs = append(errs, ValidationError{
				File:    doc.Path,
				Line:    sec.Line,
				Code:    "R7",
				Message: fmt.Sprintf("[R7] section %q is prohibited in public VISION docs", sec.Name),
			})
		}
	}
	return errs
}

// checkStrategyPublic (R8) flags STRATEGY docs that surface sections forbidden
// in public repos. Mirrors checkVisionPublic. The check is bypassed only when
// cfg.Visibility is exactly "private"; any other value (including the empty
// string) fails closed and the check runs. See DESIGN-shirabe-strategy-skill.md.
func checkStrategyPublic(doc Doc, cfg Config) []ValidationError {
	if cfg.Visibility == "private" {
		return nil
	}

	prohibited := make(map[string]bool, len(prohibitedPublicStrategySections))
	for _, name := range prohibitedPublicStrategySections {
		prohibited[name] = true
	}

	var errs []ValidationError
	for _, sec := range doc.Sections {
		if prohibited[sec.Name] {
			errs = append(errs, ValidationError{
				File:    doc.Path,
				Line:    sec.Line,
				Code:    "R8",
				Message: fmt.Sprintf("[R8] section %q is prohibited in public STRATEGY docs", sec.Name),
			})
		}
	}
	return errs
}
