package validate

// Config holds optional overrides for the validation run.
type Config struct {
	CustomStatuses map[string][]string // format schema version → replacement enum
	Visibility     string              // "public" | "private" | ""
}

// IsNotice reports whether a ValidationError should be emitted as a GHA ::notice
// annotation rather than a ::error. Only SCHEMA-code results are notices; all
// other codes (FC01-FC04, R6, R7) are errors that contribute to a non-zero exit.
func IsNotice(err ValidationError) bool {
	return err.Code == "SCHEMA"
}

// ValidateFile runs all checks for a given doc against its format spec.
// Returns a SCHEMA notice (non-error) if the schema gate fires; otherwise returns FC01-FC04 errors.
// Callers must use IsNotice to distinguish notice-level results from error-level results.
func ValidateFile(doc Doc, spec FormatSpec, cfg Config) []ValidationError {
	// 1. Schema gate: if doc.Schema != spec.SchemaVersion, return SCHEMA notice.
	if schemaErr := checkSchema(doc, spec); schemaErr != nil {
		return []ValidationError{*schemaErr}
	}

	// 2. Run FC01, FC02, FC03, FC04 in order, collect all errors.
	var errs []ValidationError
	errs = append(errs, checkFC01(doc, spec)...)
	errs = append(errs, checkFC02(doc, spec, cfg)...)
	errs = append(errs, checkFC03(doc, spec)...)
	errs = append(errs, checkFC04(doc, spec)...)

	// 3. Format-specific checks dispatched by spec.Name.
	switch spec.Name {
	case "Plan":
		errs = append(errs, checkPlanUpstream(doc)...)
	case "VISION":
		errs = append(errs, checkVisionPublic(doc, cfg)...)
	}

	return errs
}
