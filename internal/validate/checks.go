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
