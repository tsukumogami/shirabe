package validate

import "fmt"

// Config holds optional overrides for the validation run.
type Config struct {
	CustomStatuses map[string][]string // format schema version → replacement enum
	Visibility     string              // "public" | "private" | ""
}

// validateFile runs all checks for a given doc against its format spec.
// Returns a SCHEMA notice (non-error) if the schema gate fires; otherwise returns FC01-FC04 errors.
func validateFile(doc Doc, spec FormatSpec, cfg Config) []ValidationError {
	// 1. Schema gate: if doc.Schema != spec.SchemaVersion, return SCHEMA notice.
	if schemaErr := checkSchema(doc, spec); schemaErr != nil {
		return []ValidationError{
			{
				File:    doc.Path,
				Line:    1,
				Code:    "SCHEMA",
				Message: fmt.Sprintf("schema %q not in supported range, skipping", doc.Schema),
			},
		}
	}

	// 2. Run FC01, FC02, FC03, FC04 in order, collect all errors.
	var errs []ValidationError
	errs = append(errs, checkFC01(doc, spec)...)
	errs = append(errs, checkFC02(doc, spec, cfg)...)
	errs = append(errs, checkFC03(doc, spec)...)
	errs = append(errs, checkFC04(doc, spec)...)
	return errs
}
