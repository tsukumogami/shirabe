package validate

import (
	"strings"
	"testing"
)

func TestParseDocBytes(t *testing.T) {
	tests := []struct {
		name        string
		input       string
		wantErr     bool
		wantSchema  string
		wantStatus  string
		wantFields  map[string]int    // field name → expected absolute line
		wantHeadings []string         // expected section names in order
		wantNoFM    bool              // expect no frontmatter (Fields empty)
	}{
		{
			name: "full doc with schema and status",
			input: `---
schema: design/v1
status: Proposed
---

# Title

## Status

Proposed
`,
			wantSchema: "design/v1",
			wantStatus: "Proposed",
			wantFields: map[string]int{"schema": 2, "status": 3},
			wantHeadings: []string{"Status"},
		},
		{
			name: "no frontmatter",
			input: `# Title

## Status

Proposed
`,
			wantNoFM:     true,
			wantHeadings: []string{"Status"},
		},
		{
			name:    "unclosed frontmatter",
			input:   "---\nschema: design/v1\n",
			wantErr: true,
		},
		{
			name:    "malformed yaml",
			input:   "---\nkey: [unclosed\n---\n",
			wantErr: true,
		},
		{
			name: "block scalar value",
			input: `---
status: Proposed
problem: |
  This is a
  block scalar.
---
`,
			wantStatus: "Proposed",
			wantFields: map[string]int{"status": 2, "problem": 3},
		},
		{
			name: "multiple headings with line numbers",
			input: `---
status: Active
---

## Context

body

## Decision

body
`,
			wantStatus:   "Active",
			wantHeadings: []string{"Context", "Decision"},
		},
		{
			name: "heading detection — only ## prefix",
			input: `---
status: Active
---

### Not a section
## Is a section
#### Also not
`,
			wantStatus:   "Active",
			wantHeadings: []string{"Is a section"},
		},
		{
			name: "empty frontmatter",
			input: `---
---

## Status
`,
			wantNoFM:     false,
			wantHeadings: []string{"Status"},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			doc, err := parseDocBytes("test.md", []byte(tt.input))
			if tt.wantErr {
				if err == nil {
					t.Fatal("expected error, got nil")
				}
				return
			}
			if err != nil {
				t.Fatalf("unexpected error: %v", err)
			}

			if tt.wantNoFM {
				if len(doc.Fields) != 0 {
					t.Errorf("expected no fields, got %v", doc.Fields)
				}
			}

			if tt.wantSchema != "" && doc.Schema != tt.wantSchema {
				t.Errorf("schema: got %q, want %q", doc.Schema, tt.wantSchema)
			}
			if tt.wantStatus != "" && doc.Status != tt.wantStatus {
				t.Errorf("status: got %q, want %q", doc.Status, tt.wantStatus)
			}

			for field, wantLine := range tt.wantFields {
				fv, ok := doc.Fields[field]
				if !ok {
					t.Errorf("field %q not found in doc.Fields", field)
					continue
				}
				if fv.Line != wantLine {
					t.Errorf("field %q: line %d, want %d", field, fv.Line, wantLine)
				}
			}

			if len(tt.wantHeadings) > 0 {
				if len(doc.Sections) != len(tt.wantHeadings) {
					var got []string
					for _, s := range doc.Sections {
						got = append(got, s.Name)
					}
					t.Errorf("sections: got %v, want %v", got, tt.wantHeadings)
				} else {
					for i, want := range tt.wantHeadings {
						if doc.Sections[i].Name != want {
							t.Errorf("section[%d]: got %q, want %q", i, doc.Sections[i].Name, want)
						}
					}
				}
			}
		})
	}
}

func TestSplitFrontmatter_LineNumbers(t *testing.T) {
	// Verify that fmStartLine correctly identifies the line after ---.
	input := "---\nschema: design/v1\nstatus: Proposed\n---\nbody\n"
	_, fmStart, bodyStart, err := splitFrontmatter([]byte(input))
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if fmStart != 2 {
		t.Errorf("fmStartLine: got %d, want 2", fmStart)
	}
	if bodyStart != 5 {
		t.Errorf("bodyStartLine: got %d, want 5", bodyStart)
	}
}

func TestParseDocBytes_BodyLines(t *testing.T) {
	input := "---\nstatus: Active\n---\n\nsome body\nmore body\n"
	doc, err := parseDocBytes("x.md", []byte(input))
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	combined := strings.Join(doc.Body, "\n")
	if !strings.Contains(combined, "some body") {
		t.Errorf("body missing 'some body': %q", combined)
	}
}
