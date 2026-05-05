package validate

import (
	"fmt"
	"strings"
)

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
