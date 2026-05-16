package validate

// Doc is the intermediate representation of a parsed shirabe doc file.
type Doc struct {
	Path     string
	Schema   string
	Status   string
	Fields   map[string]FieldValue // frontmatter fields with absolute line numbers
	Sections []Section             // ## headings with absolute line numbers
	Body     []string              // raw body lines (for FC03, checkVisionPublic)
}

// FieldValue holds a frontmatter field's string value and its 1-indexed line number.
type FieldValue struct {
	Value string
	Line  int
}

// Section holds a ## heading name and its 1-indexed line number.
type Section struct {
	Name string
	Line int
}

// ValidationError describes a single validation failure, mapped 1:1 to a GHA annotation.
type ValidationError struct {
	File    string
	Line    int
	Code    string // "FC01", "FC02", "FC03", "FC04", "R6", "R7", "SCHEMA"
	Message string
}
