package validate

import (
	"strings"
	"testing"
)

// docFromMarkdown is a test helper that simulates parseDocBytes for
// table-test inputs. It splits frontmatter (if present) and scans the
// body for ## sections, matching the production scanner's behavior.
func docFromMarkdown(t *testing.T, md string) Doc {
	t.Helper()
	doc, err := parseDocBytes("test.md", []byte(md))
	if err != nil {
		t.Fatalf("parseDocBytes failed: %v", err)
	}
	return doc
}

// --- parseIssuesTable ---

func TestParseIssuesTable_CanonicalPlanProfile(t *testing.T) {
	doc := docFromMarkdown(t, `---
schema: plan/v1
status: Active
execution_mode: multi-pr
milestone: "foo"
issue_count: 2
---

# PLAN: foo

## Status

Active

## Implementation Issues

| Issue | Dependencies | Complexity |
|-------|--------------|------------|
| [#1: first](https://example.com/1) | None | simple |
| _First description._ | | |
| [#2: second](https://example.com/2) | [#1](https://example.com/1) | testable |
| _Second description._ | | |
`)

	table, ok := parseIssuesTable(doc)
	if !ok {
		t.Fatal("expected to find a table, got false")
	}
	wantCols := []string{"Issue", "Dependencies", "Complexity"}
	if !stringSlicesEqual(table.Columns, wantCols) {
		t.Errorf("columns: got %v, want %v", table.Columns, wantCols)
	}
	if len(table.Rows) != 4 {
		t.Fatalf("expected 4 rows (2 entity + 2 desc), got %d", len(table.Rows))
	}
	if table.Rows[0].Kind != RowEntity || table.Rows[0].Key != "#1" {
		t.Errorf("row[0]: got kind=%v key=%q, want entity #1", table.Rows[0].Kind, table.Rows[0].Key)
	}
	if table.Rows[1].Kind != RowDescription {
		t.Errorf("row[1]: got kind=%v, want description", table.Rows[1].Kind)
	}
	if table.Rows[2].Kind != RowEntity || table.Rows[2].Key != "#2" {
		t.Errorf("row[2]: got kind=%v key=%q, want entity #2", table.Rows[2].Kind, table.Rows[2].Key)
	}
	if len(table.Rows[2].Deps) != 1 || table.Rows[2].Deps[0] != "#1" {
		t.Errorf("row[2] deps: got %v, want [#1]", table.Rows[2].Deps)
	}
}

func TestParseIssuesTable_CanonicalRoadmapProfile(t *testing.T) {
	doc := docFromMarkdown(t, `---
schema: roadmap/v1
status: Active
theme: |
  theme
scope: |
  scope
---

# ROADMAP: foo

## Status

Active

## Implementation Issues

| Feature | Issues | Dependencies | Status |
|---------|--------|--------------|--------|
| Feature 1: alpha | [#10](https://example.com/10) | None | In Progress |
| _Alpha description._ | | | |
| Feature 2: beta | [#11](https://example.com/11) | Feature 1: alpha | Not Started |
| _Beta description._ | | | |
`)

	table, ok := parseIssuesTable(doc)
	if !ok {
		t.Fatal("expected to find a table, got false")
	}
	wantCols := []string{"Feature", "Issues", "Dependencies", "Status"}
	if !stringSlicesEqual(table.Columns, wantCols) {
		t.Errorf("columns: got %v, want %v", table.Columns, wantCols)
	}
	if len(table.Rows) != 4 {
		t.Fatalf("expected 4 rows (2 entity + 2 desc), got %d", len(table.Rows))
	}
	if table.Rows[0].Kind != RowEntity || table.Rows[0].Key != "Feature 1: alpha" {
		t.Errorf("row[0]: got kind=%v key=%q, want entity 'Feature 1: alpha'", table.Rows[0].Kind, table.Rows[0].Key)
	}
	if table.Rows[2].Key != "Feature 2: beta" {
		t.Errorf("row[2] key: got %q, want 'Feature 2: beta'", table.Rows[2].Key)
	}
	if len(table.Rows[2].Deps) != 1 || table.Rows[2].Deps[0] != "Feature 1: alpha" {
		t.Errorf("row[2] deps: got %v, want [Feature 1: alpha]", table.Rows[2].Deps)
	}
}

func TestParseIssuesTable_StrikethroughOnDoneClassifies(t *testing.T) {
	doc := docFromMarkdown(t, `---
schema: plan/v1
status: Active
execution_mode: multi-pr
milestone: "foo"
issue_count: 1
---

# PLAN: foo

## Status

Active

## Implementation Issues

| Issue | Dependencies | Complexity |
|-------|--------------|------------|
| ~~[#1: done item](https://example.com/1)~~ | ~~None~~ | ~~simple~~ |
| ~~_A struck-through description._~~ | | |
`)

	table, ok := parseIssuesTable(doc)
	if !ok {
		t.Fatal("expected to find a table")
	}
	if len(table.Rows) != 2 {
		t.Fatalf("expected 2 rows, got %d", len(table.Rows))
	}
	if table.Rows[0].Kind != RowEntity {
		t.Errorf("struck entity row should classify as RowEntity, got %v", table.Rows[0].Kind)
	}
	if table.Rows[0].Key != "#1" {
		t.Errorf("expected key '#1' (stripped from strikethrough), got %q", table.Rows[0].Key)
	}
	if table.Rows[1].Kind != RowDescription {
		t.Errorf("struck description row should classify as RowDescription, got %v", table.Rows[1].Kind)
	}
}

func TestParseIssuesTable_ChildReferenceRow(t *testing.T) {
	doc := docFromMarkdown(t, `---
schema: plan/v1
status: Active
execution_mode: multi-pr
milestone: "foo"
issue_count: 1
---

# PLAN: foo

## Status

Active

## Implementation Issues

| Issue | Dependencies | Complexity |
|-------|--------------|------------|
| [#1: tracks-design item](https://example.com/1) | None | simple |
| ^_Child: [DESIGN-foo.md](./DESIGN-foo.md)_ | | | |
| _Description._ | | |
`)

	table, ok := parseIssuesTable(doc)
	if !ok {
		t.Fatal("expected to find a table")
	}
	if len(table.Rows) != 3 {
		t.Fatalf("expected 3 rows, got %d", len(table.Rows))
	}
	if table.Rows[1].Kind != RowChild {
		t.Errorf("middle row should be RowChild, got %v", table.Rows[1].Kind)
	}
}

func TestParseIssuesTable_NoSectionReturnsFalse(t *testing.T) {
	doc := docFromMarkdown(t, `---
schema: plan/v1
status: Active
---

# PLAN: foo

## Status

Active

## Other Section

Some text.
`)

	if _, ok := parseIssuesTable(doc); ok {
		t.Error("expected (Table{}, false) when no Implementation Issues section")
	}
}

func TestParseIssuesTable_EmptySectionReturnsFalse(t *testing.T) {
	doc := docFromMarkdown(t, `---
schema: roadmap/v1
status: Draft
---

# ROADMAP: foo

## Status

Draft

## Implementation Issues

<!-- Populated by /plan during decomposition. Do not fill manually. -->

## Dependency Graph
`)

	if _, ok := parseIssuesTable(doc); ok {
		t.Error("expected (Table{}, false) when section is empty")
	}
}

func TestParseIssuesTable_NoSeparatorRowReturnsFalse(t *testing.T) {
	// A table with a header row but no separator (`| --- | --- |`) is
	// malformed and should be treated as no-table-found.
	doc := docFromMarkdown(t, `---
schema: plan/v1
status: Active
---

## Implementation Issues

| Issue | Dependencies | Complexity |
| [#1: only row](https://example.com/1) | None | simple |
`)

	if _, ok := parseIssuesTable(doc); ok {
		t.Error("expected false when separator row is missing")
	}
}

func TestParseIssuesTable_RaggedRowsDoNotPanic(t *testing.T) {
	// Defensive: a row with fewer cells than the header must not panic.
	doc := docFromMarkdown(t, `---
schema: plan/v1
status: Active
---

## Implementation Issues

| Issue | Dependencies | Complexity |
|-------|--------------|------------|
| [#1: ragged](https://example.com/1) |
| _Description._ |
`)

	// Should not panic; if it parses, fine; if not, fine.
	defer func() {
		if r := recover(); r != nil {
			t.Fatalf("parseIssuesTable panicked on ragged rows: %v", r)
		}
	}()
	parseIssuesTable(doc)
}

func TestParseIssuesTable_DivergentRoadmapStrategicPipeline(t *testing.T) {
	// The ROADMAP-strategic-pipeline.md committed shape. parseIssuesTable
	// should return the table (parsing is profile-agnostic); FC05 then
	// flags it.
	doc := docFromMarkdown(t, `---
schema: roadmap/v1
status: Active
---

## Implementation Issues

| Feature | Status | Downstream Artifact |
|---------|--------|---------------------|
| Feature 1: VISION Artifact Type | Done | DESIGN-vision-artifact-type.md (Current) |
| Feature 2: Roadmap Creation Skill | Done | PRD-roadmap-skill.md (Done), DESIGN-roadmap-creation-skill.md (Current) |
`)

	table, ok := parseIssuesTable(doc)
	if !ok {
		t.Fatal("expected parseIssuesTable to find the divergent table")
	}
	wantCols := []string{"Feature", "Status", "Downstream Artifact"}
	if !stringSlicesEqual(table.Columns, wantCols) {
		t.Errorf("columns: got %v, want %v", table.Columns, wantCols)
	}
}

// --- checkFC05 ---

func TestCheckFC05_CanonicalPlanPasses(t *testing.T) {
	doc := docFromMarkdown(t, `---
schema: plan/v1
status: Active
execution_mode: multi-pr
milestone: "foo"
issue_count: 1
---

## Implementation Issues

| Issue | Dependencies | Complexity |
|-------|--------------|------------|
| [#1: alpha](https://example.com/1) | None | simple |
| _Alpha description._ | | |
`)

	errs := checkFC05(doc, Formats["plan/v1"])
	if len(errs) != 0 {
		t.Errorf("expected no FC05 errors on canonical plan, got %v", errs)
	}
}

func TestCheckFC05_CanonicalRoadmapPasses(t *testing.T) {
	doc := docFromMarkdown(t, `---
schema: roadmap/v1
status: Active
---

## Implementation Issues

| Feature | Issues | Dependencies | Status |
|---------|--------|--------------|--------|
| Feature 1: alpha | [#10](https://example.com/10) | None | In Progress |
| _Alpha description._ | | | |
`)

	errs := checkFC05(doc, Formats["roadmap/v1"])
	if len(errs) != 0 {
		t.Errorf("expected no FC05 errors on canonical roadmap, got %v", errs)
	}
}

func TestCheckFC05_LegacyPlanTitleColumnEmitsMigrationHint(t *testing.T) {
	doc := docFromMarkdown(t, `---
schema: plan/v1
status: Active
execution_mode: multi-pr
milestone: "foo"
issue_count: 1
---

## Implementation Issues

| Issue | Title | Dependencies | Complexity |
|-------|-------|--------------|------------|
| [#1](https://example.com/1) | first item | None | simple |
| _First description._ | | | |
`)

	errs := checkFC05(doc, Formats["plan/v1"])
	if len(errs) != 1 {
		t.Fatalf("expected 1 FC05 error, got %d: %v", len(errs), errs)
	}
	if errs[0].Code != "FC05" {
		t.Errorf("code: got %q, want FC05", errs[0].Code)
	}
	if !strings.Contains(errs[0].Message, "legacy plan table shape") {
		t.Errorf("message should mention legacy migration, got %q", errs[0].Message)
	}
	if !strings.Contains(errs[0].Message, "[#N: <title>](url)") {
		t.Errorf("message should show the canonical link form, got %q", errs[0].Message)
	}
}

func TestCheckFC05_DivergentRoadmapFeatureStatusDownstreamArtifact(t *testing.T) {
	doc := docFromMarkdown(t, `---
schema: roadmap/v1
status: Active
---

## Implementation Issues

| Feature | Status | Downstream Artifact |
|---------|--------|---------------------|
| Feature 1: foo | Done | PRD-foo.md |
| _Description._ | | |
`)

	errs := checkFC05(doc, Formats["roadmap/v1"])
	if len(errs) == 0 {
		t.Fatal("expected FC05 to fail on divergent roadmap shape")
	}
	if errs[0].Code != "FC05" {
		t.Errorf("code: got %q, want FC05", errs[0].Code)
	}
	if !strings.Contains(errs[0].Message, "does not match the Roadmap profile") {
		t.Errorf("message should name the profile, got %q", errs[0].Message)
	}
}

func TestCheckFC05_DivergentRoadmapIssuePhaseDependenciesLabel(t *testing.T) {
	doc := docFromMarkdown(t, `---
schema: roadmap/v1
status: Active
---

## Implementation Issues

| Issue | Phase | Dependencies | Label |
|-------|-------|--------------|-------|
| [#49: foo](https://example.com/49) | 1 | None | needs-design |
| _Description._ | | | |
`)

	errs := checkFC05(doc, Formats["roadmap/v1"])
	if len(errs) == 0 {
		t.Fatal("expected FC05 to fail on Issue|Phase|Dependencies|Label roadmap shape")
	}
}

func TestCheckFC05_MissingDescriptionRowReported(t *testing.T) {
	doc := docFromMarkdown(t, `---
schema: plan/v1
status: Active
execution_mode: multi-pr
milestone: "foo"
issue_count: 2
---

## Implementation Issues

| Issue | Dependencies | Complexity |
|-------|--------------|------------|
| [#1: alpha](https://example.com/1) | None | simple |
| [#2: beta](https://example.com/2) | None | simple |
| _Beta description._ | | |
`)

	errs := checkFC05(doc, Formats["plan/v1"])
	if len(errs) == 0 {
		t.Fatal("expected FC05 to report missing description row for #1")
	}
	if !strings.Contains(errs[0].Message, "missing its description row") {
		t.Errorf("message should mention missing description row, got %q", errs[0].Message)
	}
}

func TestCheckFC05_NoIssuesTableSpecIsNoOp(t *testing.T) {
	// Formats without an issues table (Design, PRD, etc.) must not run FC05.
	doc := docFromMarkdown(t, `---
schema: design/v1
status: Accepted
---

## Implementation Issues

| Some | Random | Headers |
|------|--------|---------|
| a | b | c |
`)
	errs := checkFC05(doc, Formats["design/v1"])
	if len(errs) != 0 {
		t.Errorf("FC05 should be a no-op for design/v1, got %v", errs)
	}
}

// --- checkFC06 ---

func TestCheckFC06_AllReferencesResolve(t *testing.T) {
	doc := docFromMarkdown(t, `---
schema: plan/v1
status: Active
execution_mode: multi-pr
milestone: "foo"
issue_count: 2
---

## Implementation Issues

| Issue | Dependencies | Complexity |
|-------|--------------|------------|
| [#1: alpha](https://example.com/1) | None | simple |
| _Alpha._ | | |
| [#2: beta](https://example.com/2) | [#1](https://example.com/1) | testable |
| _Beta._ | | |
`)

	errs := checkFC06(doc, Formats["plan/v1"])
	if len(errs) != 0 {
		t.Errorf("expected no FC06 errors, got %v", errs)
	}
}

func TestCheckFC06_DanglingCrossReferenceFires(t *testing.T) {
	doc := docFromMarkdown(t, `---
schema: plan/v1
status: Active
execution_mode: multi-pr
milestone: "foo"
issue_count: 2
---

## Implementation Issues

| Issue | Dependencies | Complexity |
|-------|--------------|------------|
| [#1: alpha](https://example.com/1) | None | simple |
| _Alpha._ | | |
| [#2: beta](https://example.com/2) | [#99](https://example.com/99) | testable |
| _Beta._ | | |
`)

	errs := checkFC06(doc, Formats["plan/v1"])
	if len(errs) != 1 {
		t.Fatalf("expected 1 FC06 error, got %d: %v", len(errs), errs)
	}
	if errs[0].Code != "FC06" {
		t.Errorf("code: got %q, want FC06", errs[0].Code)
	}
	if !strings.Contains(errs[0].Message, `"#99"`) {
		t.Errorf("message should name the dangling key '#99', got %q", errs[0].Message)
	}
	if !strings.Contains(errs[0].Message, `"#2"`) {
		t.Errorf("message should name the source row '#2', got %q", errs[0].Message)
	}
}

func TestCheckFC06_CrossRepoReferenceSkipped(t *testing.T) {
	// `tsukumogami/repo#N` is a cross-repo reference -- out of scope for
	// the document-local check.
	doc := docFromMarkdown(t, `---
schema: plan/v1
status: Active
execution_mode: multi-pr
milestone: "foo"
issue_count: 1
---

## Implementation Issues

| Issue | Dependencies | Complexity |
|-------|--------------|------------|
| [#1: alpha](https://example.com/1) | someorg/somerepo#5 | simple |
| _Alpha._ | | |
`)

	errs := checkFC06(doc, Formats["plan/v1"])
	if len(errs) != 0 {
		t.Errorf("FC06 should skip cross-repo refs, got %v", errs)
	}
}

func TestCheckFC06_RoadmapFeatureKeyResolves(t *testing.T) {
	doc := docFromMarkdown(t, `---
schema: roadmap/v1
status: Active
---

## Implementation Issues

| Feature | Issues | Dependencies | Status |
|---------|--------|--------------|--------|
| Feature 1: alpha | [#10](https://example.com/10) | None | Done |
| _Alpha._ | | | |
| Feature 2: beta | [#11](https://example.com/11) | Feature 1: alpha | In Progress |
| _Beta._ | | | |
`)

	errs := checkFC06(doc, Formats["roadmap/v1"])
	if len(errs) != 0 {
		t.Errorf("expected no FC06 errors for resolving feature ref, got %v", errs)
	}
}

func TestCheckFC06_NoIssuesTableSpecIsNoOp(t *testing.T) {
	doc := docFromMarkdown(t, `---
schema: design/v1
status: Accepted
---

## Implementation Issues

| Some | Random | Headers |
|------|--------|---------|
| a | b | c |
`)
	errs := checkFC06(doc, Formats["design/v1"])
	if len(errs) != 0 {
		t.Errorf("FC06 should be a no-op for design/v1, got %v", errs)
	}
}

// --- Defensive parsing ---

func TestParseIssuesTable_NoSectionInEmptyDoc(t *testing.T) {
	doc := docFromMarkdown(t, ``)
	defer func() {
		if r := recover(); r != nil {
			t.Fatalf("panicked on empty doc: %v", r)
		}
	}()
	if _, ok := parseIssuesTable(doc); ok {
		t.Error("expected false on empty doc")
	}
}

func TestParseIssuesTable_UnterminatedSectionDoesNotPanic(t *testing.T) {
	// Section heading with no body, no closing section.
	doc := docFromMarkdown(t, `## Implementation Issues
`)
	defer func() {
		if r := recover(); r != nil {
			t.Fatalf("panicked on unterminated section: %v", r)
		}
	}()
	parseIssuesTable(doc)
}
