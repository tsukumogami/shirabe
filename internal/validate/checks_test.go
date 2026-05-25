package validate

import (
	"os"
	"runtime"
	"strings"
	"testing"
)

var designSpec = Formats["design/v1"]

// makeDoc is a helper that builds a minimal Doc for testing.
func makeDoc(schema, status string, fields map[string]FieldValue, sections []Section, body []string) Doc {
	if fields == nil {
		fields = make(map[string]FieldValue)
	}
	return Doc{
		Path:     "test.md",
		Schema:   schema,
		Status:   status,
		Fields:   fields,
		Sections: sections,
		Body:     body,
	}
}

// --- checkSchema ---

func TestCheckSchema(t *testing.T) {
	t.Run("matching schema returns nil", func(t *testing.T) {
		doc := makeDoc("design/v1", "Proposed", nil, nil, nil)
		got := checkSchema(doc, designSpec)
		if got != nil {
			t.Errorf("expected nil, got %+v", got)
		}
	})

	t.Run("mismatched schema returns SCHEMA notice", func(t *testing.T) {
		doc := makeDoc("design/v2", "Proposed", nil, nil, nil)
		got := checkSchema(doc, designSpec)
		if got == nil {
			t.Fatal("expected SCHEMA error, got nil")
		}
		if got.Code != "SCHEMA" {
			t.Errorf("code: got %q, want %q", got.Code, "SCHEMA")
		}
		if !strings.Contains(got.Message, "design/v2") {
			t.Errorf("message should contain schema value %q, got %q", "design/v2", got.Message)
		}
	})

	t.Run("empty schema returns SCHEMA notice", func(t *testing.T) {
		doc := makeDoc("", "Proposed", nil, nil, nil)
		got := checkSchema(doc, designSpec)
		if got == nil {
			t.Fatal("expected SCHEMA error, got nil")
		}
		if got.Code != "SCHEMA" {
			t.Errorf("code: got %q, want %q", got.Code, "SCHEMA")
		}
	})
}

// --- checkFC01 ---

func TestCheckFC01(t *testing.T) {
	t.Run("all required fields present passes", func(t *testing.T) {
		fields := map[string]FieldValue{
			"status":    {Value: "Proposed", Line: 2},
			"problem":   {Value: "something", Line: 3},
			"decision":  {Value: "do it", Line: 4},
			"rationale": {Value: "because", Line: 5},
		}
		doc := makeDoc("design/v1", "Proposed", fields, nil, nil)
		errs := checkFC01(doc, designSpec)
		if len(errs) != 0 {
			t.Errorf("expected no errors, got %v", errs)
		}
	})

	t.Run("one missing field returns FC01 error", func(t *testing.T) {
		fields := map[string]FieldValue{
			"status":   {Value: "Proposed", Line: 2},
			"problem":  {Value: "something", Line: 3},
			"decision": {Value: "do it", Line: 4},
			// "rationale" missing
		}
		doc := makeDoc("design/v1", "Proposed", fields, nil, nil)
		errs := checkFC01(doc, designSpec)
		if len(errs) != 1 {
			t.Fatalf("expected 1 error, got %d: %v", len(errs), errs)
		}
		if errs[0].Code != "FC01" {
			t.Errorf("code: got %q, want %q", errs[0].Code, "FC01")
		}
		if !strings.Contains(errs[0].Message, "rationale") {
			t.Errorf("message should mention missing field, got %q", errs[0].Message)
		}
		if errs[0].Line != 1 {
			t.Errorf("line: got %d, want 1", errs[0].Line)
		}
	})

	t.Run("all fields missing returns error per field", func(t *testing.T) {
		doc := makeDoc("design/v1", "", nil, nil, nil)
		errs := checkFC01(doc, designSpec)
		if len(errs) != len(designSpec.RequiredFields) {
			t.Errorf("expected %d errors, got %d", len(designSpec.RequiredFields), len(errs))
		}
	})
}

// --- checkFC02 ---

func TestCheckFC02(t *testing.T) {
	emptyCfg := Config{}

	t.Run("valid status passes", func(t *testing.T) {
		fields := map[string]FieldValue{"status": {Value: "Proposed", Line: 2}}
		doc := makeDoc("design/v1", "Proposed", fields, nil, nil)
		errs := checkFC02(doc, designSpec, emptyCfg)
		if len(errs) != 0 {
			t.Errorf("expected no errors, got %v", errs)
		}
	})

	t.Run("invalid status returns FC02 with all valid values in message", func(t *testing.T) {
		fields := map[string]FieldValue{"status": {Value: "Invalid", Line: 3}}
		doc := makeDoc("design/v1", "Invalid", fields, nil, nil)
		errs := checkFC02(doc, designSpec, emptyCfg)
		if len(errs) != 1 {
			t.Fatalf("expected 1 error, got %d: %v", len(errs), errs)
		}
		if errs[0].Code != "FC02" {
			t.Errorf("code: got %q, want %q", errs[0].Code, "FC02")
		}
		if errs[0].Line != 3 {
			t.Errorf("line: got %d, want 3", errs[0].Line)
		}
		for _, valid := range designSpec.ValidStatuses {
			if !strings.Contains(errs[0].Message, valid) {
				t.Errorf("message should contain valid status %q, got %q", valid, errs[0].Message)
			}
		}
	})

	t.Run("missing status field is skipped (FC01 handles it)", func(t *testing.T) {
		doc := makeDoc("design/v1", "", nil, nil, nil)
		errs := checkFC02(doc, designSpec, emptyCfg)
		if len(errs) != 0 {
			t.Errorf("expected no errors when status empty, got %v", errs)
		}
	})

	t.Run("custom statuses replace canonical list", func(t *testing.T) {
		cfg := Config{
			CustomStatuses: map[string][]string{
				"design/v1": {"CustomDraft", "CustomDone"},
			},
		}
		// "Proposed" is in canonical but not in custom — should fail.
		fields := map[string]FieldValue{"status": {Value: "Proposed", Line: 2}}
		doc := makeDoc("design/v1", "Proposed", fields, nil, nil)
		errs := checkFC02(doc, designSpec, cfg)
		if len(errs) != 1 {
			t.Fatalf("expected 1 error with custom statuses, got %d: %v", len(errs), errs)
		}
		if !strings.Contains(errs[0].Message, "CustomDraft") {
			t.Errorf("message should list custom statuses, got %q", errs[0].Message)
		}
	})

	t.Run("custom status value passes when in custom list", func(t *testing.T) {
		cfg := Config{
			CustomStatuses: map[string][]string{
				"design/v1": {"CustomDraft", "CustomDone"},
			},
		}
		fields := map[string]FieldValue{"status": {Value: "CustomDraft", Line: 2}}
		doc := makeDoc("design/v1", "CustomDraft", fields, nil, nil)
		errs := checkFC02(doc, designSpec, cfg)
		if len(errs) != 0 {
			t.Errorf("expected no errors, got %v", errs)
		}
	})

	t.Run("line defaults to 1 when status field has no line info", func(t *testing.T) {
		// Status is set but not in Fields (unusual, but test the default).
		doc := makeDoc("design/v1", "Invalid", nil, nil, nil)
		errs := checkFC02(doc, designSpec, emptyCfg)
		if len(errs) != 1 {
			t.Fatalf("expected 1 error, got %d", len(errs))
		}
		if errs[0].Line != 1 {
			t.Errorf("line: got %d, want 1", errs[0].Line)
		}
	})
}

// --- checkFC03 ---

func TestCheckFC03(t *testing.T) {
	t.Run("matching status passes", func(t *testing.T) {
		body := []string{
			"## Status",
			"",
			"Proposed",
			"",
			"## Context and Problem Statement",
		}
		sections := []Section{{Name: "Status", Line: 1}, {Name: "Context and Problem Statement", Line: 5}}
		doc := makeDoc("design/v1", "Proposed", nil, sections, body)
		errs := checkFC03(doc, designSpec)
		if len(errs) != 0 {
			t.Errorf("expected no errors, got %v", errs)
		}
	})

	t.Run("case-insensitive comparison passes", func(t *testing.T) {
		body := []string{"## Status", "", "proposed"}
		sections := []Section{{Name: "Status", Line: 1}}
		doc := makeDoc("design/v1", "Proposed", nil, sections, body)
		errs := checkFC03(doc, designSpec)
		if len(errs) != 0 {
			t.Errorf("expected no errors for case-insensitive match, got %v", errs)
		}
	})

	t.Run("mismatch returns FC03 error", func(t *testing.T) {
		body := []string{"## Status", "", "Accepted"}
		sections := []Section{{Name: "Status", Line: 1}}
		doc := makeDoc("design/v1", "Proposed", nil, sections, body)
		errs := checkFC03(doc, designSpec)
		if len(errs) != 1 {
			t.Fatalf("expected 1 error, got %d: %v", len(errs), errs)
		}
		if errs[0].Code != "FC03" {
			t.Errorf("code: got %q, want %q", errs[0].Code, "FC03")
		}
		if !strings.Contains(errs[0].Message, "Proposed") || !strings.Contains(errs[0].Message, "Accepted") {
			t.Errorf("message should contain both statuses, got %q", errs[0].Message)
		}
	})

	t.Run("absent ## Status section skips check", func(t *testing.T) {
		body := []string{"## Context and Problem Statement", "", "some content"}
		sections := []Section{{Name: "Context and Problem Statement", Line: 1}}
		doc := makeDoc("design/v1", "Proposed", nil, sections, body)
		errs := checkFC03(doc, designSpec)
		if len(errs) != 0 {
			t.Errorf("expected no errors when ## Status absent, got %v", errs)
		}
	})

	t.Run("## Status section with no non-blank body skips check", func(t *testing.T) {
		body := []string{"## Status", "", "", "## Context and Problem Statement"}
		sections := []Section{{Name: "Status", Line: 1}, {Name: "Context and Problem Statement", Line: 4}}
		doc := makeDoc("design/v1", "Proposed", nil, sections, body)
		errs := checkFC03(doc, designSpec)
		if len(errs) != 0 {
			t.Errorf("expected no errors when ## Status body is blank, got %v", errs)
		}
	})

	t.Run("section line is used for FC03 error", func(t *testing.T) {
		body := []string{"# Title", "", "## Status", "", "Accepted"}
		sections := []Section{{Name: "Status", Line: 3}}
		doc := makeDoc("design/v1", "Proposed", nil, sections, body)
		errs := checkFC03(doc, designSpec)
		if len(errs) != 1 {
			t.Fatalf("expected 1 error, got %d", len(errs))
		}
		if errs[0].Line != 3 {
			t.Errorf("line: got %d, want 3", errs[0].Line)
		}
	})
}

// --- checkFC04 ---

func TestCheckFC04(t *testing.T) {
	t.Run("all required sections present passes", func(t *testing.T) {
		var sections []Section
		for _, name := range designSpec.RequiredSections {
			sections = append(sections, Section{Name: name, Line: 1})
		}
		doc := makeDoc("design/v1", "Proposed", nil, sections, nil)
		errs := checkFC04(doc, designSpec)
		if len(errs) != 0 {
			t.Errorf("expected no errors, got %v", errs)
		}
	})

	t.Run("one missing section returns FC04 error", func(t *testing.T) {
		var sections []Section
		for _, name := range designSpec.RequiredSections {
			if name != "Consequences" {
				sections = append(sections, Section{Name: name, Line: 1})
			}
		}
		doc := makeDoc("design/v1", "Proposed", nil, sections, nil)
		errs := checkFC04(doc, designSpec)
		if len(errs) != 1 {
			t.Fatalf("expected 1 error, got %d: %v", len(errs), errs)
		}
		if errs[0].Code != "FC04" {
			t.Errorf("code: got %q, want %q", errs[0].Code, "FC04")
		}
		if !strings.Contains(errs[0].Message, "Consequences") {
			t.Errorf("message should mention missing section, got %q", errs[0].Message)
		}
		if errs[0].Line != 1 {
			t.Errorf("line: got %d, want 1", errs[0].Line)
		}
	})

	t.Run("no sections returns error per required section", func(t *testing.T) {
		doc := makeDoc("design/v1", "Proposed", nil, nil, nil)
		errs := checkFC04(doc, designSpec)
		if len(errs) != len(designSpec.RequiredSections) {
			t.Errorf("expected %d errors, got %d", len(designSpec.RequiredSections), len(errs))
		}
	})
}

// --- checkPlanUpstream ---

func TestCheckPlanUpstream(t *testing.T) {
	t.Run("upstream field absent returns nil", func(t *testing.T) {
		doc := makeDoc("plan/v1", "Draft", nil, nil, nil)
		errs := checkPlanUpstream(doc)
		if len(errs) != 0 {
			t.Errorf("expected no errors when upstream absent, got %v", errs)
		}
	})

	t.Run("upstream file does not exist returns R6 error", func(t *testing.T) {
		fields := map[string]FieldValue{
			"upstream": {Value: "/tmp/nonexistent_shirabe_test_xyz_12345.md", Line: 5},
		}
		doc := makeDoc("plan/v1", "Draft", fields, nil, nil)
		errs := checkPlanUpstream(doc)
		if len(errs) != 1 {
			t.Fatalf("expected 1 error, got %d: %v", len(errs), errs)
		}
		if errs[0].Code != "R6" {
			t.Errorf("code: got %q, want %q", errs[0].Code, "R6")
		}
		if errs[0].Line != 5 {
			t.Errorf("line: got %d, want 5", errs[0].Line)
		}
		if !strings.Contains(errs[0].Message, "does not exist on disk") {
			t.Errorf("message should mention existence, got %q", errs[0].Message)
		}
	})

	t.Run("upstream file exists but is not tracked by git returns R6 error", func(t *testing.T) {
		// Create a temporary file that exists on disk but is not committed to git.
		f, err := os.CreateTemp("", "shirabe_untracked_*.md")
		if err != nil {
			t.Fatal(err)
		}
		defer os.Remove(f.Name())
		f.Close()

		fields := map[string]FieldValue{
			"upstream": {Value: f.Name(), Line: 3},
		}
		doc := makeDoc("plan/v1", "Draft", fields, nil, nil)
		errs := checkPlanUpstream(doc)
		if len(errs) != 1 {
			t.Fatalf("expected 1 error for untracked file, got %d: %v", len(errs), errs)
		}
		if errs[0].Code != "R6" {
			t.Errorf("code: got %q, want %q", errs[0].Code, "R6")
		}
		if !strings.Contains(errs[0].Message, "not tracked by git") {
			t.Errorf("message should mention git tracking, got %q", errs[0].Message)
		}
	})

	t.Run("upstream file exists and is tracked by git returns nil", func(t *testing.T) {
		// Use this test file itself — it exists on disk and is committed to git.
		// runtime.Caller(0) returns the absolute path of the current source file.
		_, thisFile, _, ok := runtime.Caller(0)
		if !ok {
			t.Fatal("runtime.Caller failed")
		}
		fields := map[string]FieldValue{
			"upstream": {Value: thisFile, Line: 4},
		}
		doc := makeDoc("plan/v1", "Draft", fields, nil, nil)
		errs := checkPlanUpstream(doc)
		if len(errs) != 0 {
			t.Errorf("expected no errors for tracked file, got %v", errs)
		}
	})
}

// --- checkVisionPublic ---

func TestCheckVisionPublic(t *testing.T) {
	t.Run("private visibility returns nil even with prohibited sections", func(t *testing.T) {
		cfg := Config{Visibility: "private"}
		sections := []Section{
			{Name: "Competitive Positioning", Line: 10},
			{Name: "Resource Implications", Line: 20},
		}
		doc := makeDoc("vision/v1", "Draft", nil, sections, nil)
		errs := checkVisionPublic(doc, cfg)
		if len(errs) != 0 {
			t.Errorf("expected no errors for private visibility, got %v", errs)
		}
	})

	t.Run("public visibility with prohibited section returns R7 error", func(t *testing.T) {
		cfg := Config{Visibility: "public"}
		sections := []Section{
			{Name: "Thesis", Line: 5},
			{Name: "Competitive Positioning", Line: 12},
		}
		doc := makeDoc("vision/v1", "Draft", nil, sections, nil)
		errs := checkVisionPublic(doc, cfg)
		if len(errs) != 1 {
			t.Fatalf("expected 1 error, got %d: %v", len(errs), errs)
		}
		if errs[0].Code != "R7" {
			t.Errorf("code: got %q, want %q", errs[0].Code, "R7")
		}
		if errs[0].Line != 12 {
			t.Errorf("line: got %d, want 12", errs[0].Line)
		}
		if !strings.Contains(errs[0].Message, "Competitive Positioning") {
			t.Errorf("message should mention section name, got %q", errs[0].Message)
		}
	})

	t.Run("empty visibility fails closed — prohibited section returns R7 error", func(t *testing.T) {
		cfg := Config{Visibility: ""}
		sections := []Section{
			{Name: "Resource Implications", Line: 8},
		}
		doc := makeDoc("vision/v1", "Draft", nil, sections, nil)
		errs := checkVisionPublic(doc, cfg)
		if len(errs) != 1 {
			t.Fatalf("expected 1 error for empty visibility, got %d: %v", len(errs), errs)
		}
		if errs[0].Code != "R7" {
			t.Errorf("code: got %q, want %q", errs[0].Code, "R7")
		}
	})

	t.Run("public visibility without prohibited sections returns nil", func(t *testing.T) {
		cfg := Config{Visibility: "public"}
		sections := []Section{
			{Name: "Thesis", Line: 5},
			{Name: "Audience", Line: 10},
			{Name: "Value Proposition", Line: 15},
		}
		doc := makeDoc("vision/v1", "Draft", nil, sections, nil)
		errs := checkVisionPublic(doc, cfg)
		if len(errs) != 0 {
			t.Errorf("expected no errors, got %v", errs)
		}
	})

	t.Run("both prohibited sections present returns two R7 errors", func(t *testing.T) {
		cfg := Config{Visibility: "public"}
		sections := []Section{
			{Name: "Competitive Positioning", Line: 10},
			{Name: "Resource Implications", Line: 20},
		}
		doc := makeDoc("vision/v1", "Draft", nil, sections, nil)
		errs := checkVisionPublic(doc, cfg)
		if len(errs) != 2 {
			t.Fatalf("expected 2 errors, got %d: %v", len(errs), errs)
		}
		for _, e := range errs {
			if e.Code != "R7" {
				t.Errorf("code: got %q, want %q", e.Code, "R7")
			}
		}
	})
}

// --- checkStrategyPublic ---

func TestCheckStrategyPublic(t *testing.T) {
	t.Run("private visibility returns nil even with prohibited section", func(t *testing.T) {
		cfg := Config{Visibility: "private"}
		sections := []Section{
			{Name: "Competitive Considerations", Line: 10},
		}
		doc := makeDoc("strategy/v1", "Draft", nil, sections, nil)
		errs := checkStrategyPublic(doc, cfg)
		if len(errs) != 0 {
			t.Errorf("expected no errors for private visibility, got %v", errs)
		}
	})

	t.Run("public visibility with prohibited section returns R8 error", func(t *testing.T) {
		cfg := Config{Visibility: "public"}
		sections := []Section{
			{Name: "Defensibility Thesis", Line: 5},
			{Name: "Competitive Considerations", Line: 15},
		}
		doc := makeDoc("strategy/v1", "Draft", nil, sections, nil)
		errs := checkStrategyPublic(doc, cfg)
		if len(errs) != 1 {
			t.Fatalf("expected 1 error, got %d: %v", len(errs), errs)
		}
		if errs[0].Code != "R8" {
			t.Errorf("code: got %q, want %q", errs[0].Code, "R8")
		}
		if errs[0].Line != 15 {
			t.Errorf("line: got %d, want 15", errs[0].Line)
		}
		if !strings.Contains(errs[0].Message, "Competitive Considerations") {
			t.Errorf("message should mention section name, got %q", errs[0].Message)
		}
	})

	t.Run("empty visibility fails closed — prohibited section returns R8 error", func(t *testing.T) {
		cfg := Config{Visibility: ""}
		sections := []Section{
			{Name: "Competitive Considerations", Line: 8},
		}
		doc := makeDoc("strategy/v1", "Draft", nil, sections, nil)
		errs := checkStrategyPublic(doc, cfg)
		if len(errs) != 1 {
			t.Fatalf("expected 1 error for empty visibility, got %d: %v", len(errs), errs)
		}
		if errs[0].Code != "R8" {
			t.Errorf("code: got %q, want %q", errs[0].Code, "R8")
		}
	})

	t.Run("public visibility without prohibited section returns nil", func(t *testing.T) {
		cfg := Config{Visibility: "public"}
		sections := []Section{
			{Name: "Defensibility Thesis", Line: 5},
			{Name: "Building Blocks", Line: 10},
			{Name: "Non-Goals", Line: 20},
		}
		doc := makeDoc("strategy/v1", "Draft", nil, sections, nil)
		errs := checkStrategyPublic(doc, cfg)
		if len(errs) != 0 {
			t.Errorf("expected no errors, got %v", errs)
		}
	})
}

// --- brief/v1 ---

var briefSpec = Formats["brief/v1"]

func TestDetectFormatBrief(t *testing.T) {
	spec, ok := DetectFormat("BRIEF-shirabe-foo.md")
	if !ok {
		t.Fatal("expected BRIEF- prefix to match a format")
	}
	if spec.Name != "Brief" {
		t.Errorf("name: got %q, want %q", spec.Name, "Brief")
	}
	if spec.SchemaVersion != "brief/v1" {
		t.Errorf("schema: got %q, want %q", spec.SchemaVersion, "brief/v1")
	}
}

func TestBriefValidation(t *testing.T) {
	cfg := Config{Visibility: "public"}

	briefFields := func(status string) map[string]FieldValue {
		return map[string]FieldValue{
			"status":  {Value: status, Line: 2},
			"problem": {Value: "a problem", Line: 3},
			"outcome": {Value: "an outcome", Line: 4},
		}
	}
	briefSections := func(omit string) []Section {
		var s []Section
		for i, name := range briefSpec.RequiredSections {
			if name == omit {
				continue
			}
			s = append(s, Section{Name: name, Line: i + 1})
		}
		return s
	}
	briefBody := func(status string) []string {
		return []string{"## Status", "", status}
	}

	t.Run("well-formed brief passes through ValidateFile", func(t *testing.T) {
		doc := makeDoc("brief/v1", "Draft", briefFields("Draft"), briefSections(""), briefBody("Draft"))
		errs := ValidateFile(doc, briefSpec, cfg)
		if len(errs) != 0 {
			t.Errorf("expected no errors for well-formed brief, got %v", errs)
		}
	})

	t.Run("missing required section returns FC04 naming it", func(t *testing.T) {
		doc := makeDoc("brief/v1", "Draft", briefFields("Draft"), briefSections("User Journeys"), briefBody("Draft"))
		errs := checkFC04(doc, briefSpec)
		if len(errs) != 1 {
			t.Fatalf("expected 1 FC04 error, got %d: %v", len(errs), errs)
		}
		if errs[0].Code != "FC04" {
			t.Errorf("code: got %q, want %q", errs[0].Code, "FC04")
		}
		if !strings.Contains(errs[0].Message, "User Journeys") {
			t.Errorf("message should name the missing section, got %q", errs[0].Message)
		}
	})

	t.Run("invalid status returns FC02 listing valid statuses", func(t *testing.T) {
		doc := makeDoc("brief/v1", "Published", briefFields("Published"), briefSections(""), briefBody("Published"))
		errs := checkFC02(doc, briefSpec, cfg)
		if len(errs) != 1 {
			t.Fatalf("expected 1 FC02 error, got %d: %v", len(errs), errs)
		}
		if errs[0].Code != "FC02" {
			t.Errorf("code: got %q, want %q", errs[0].Code, "FC02")
		}
		for _, valid := range []string{"Draft", "Accepted", "Done"} {
			if !strings.Contains(errs[0].Message, valid) {
				t.Errorf("message should list valid status %q, got %q", valid, errs[0].Message)
			}
		}
	})

	t.Run("no Brief-specific check runs in ValidateFile", func(t *testing.T) {
		// BRIEF has no visibility-gated section and no custom check, so a section
		// that would be prohibited for a strategy doc must not trigger any error.
		sections := append(briefSections(""), Section{Name: "Competitive Considerations", Line: 99})
		doc := makeDoc("brief/v1", "Draft", briefFields("Draft"), sections, briefBody("Draft"))
		errs := ValidateFile(doc, briefSpec, cfg)
		if len(errs) != 0 {
			t.Errorf("expected no errors (no custom check for Brief), got %v", errs)
		}
	})
}

// --- IsNotice ---

func TestIsNotice(t *testing.T) {
	if !IsNotice(ValidationError{Code: "SCHEMA"}) {
		t.Error("SCHEMA should be a notice")
	}
	for _, code := range []string{"FC01", "FC02", "FC03", "FC04", "R6", "R7", "R8"} {
		if IsNotice(ValidationError{Code: code}) {
			t.Errorf("%s should not be a notice", code)
		}
	}
}
