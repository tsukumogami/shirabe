package validate

import (
	"regexp"
	"strings"
)

// RowKind classifies an issues-table body row.
type RowKind int

const (
	// RowEntity is a primary entity row (an Issue row for the plan profile,
	// a Feature row for the roadmap profile).
	RowEntity RowKind = iota
	// RowDescription is an italic 1-3 sentence description row that follows
	// an entity row. First cell is `_..._`, remaining cells empty.
	RowDescription
	// RowChild is a child reference row used for tracks-design / tracks-plan
	// issues. First cell starts with `^_...`, remaining cells empty.
	RowChild
)

// Row is one body row of an issues table.
type Row struct {
	// Kind classifies the row.
	Kind RowKind
	// Key is the row's primary key token, used to resolve cross-references.
	//
	// For RowEntity in the plan profile, Key is the `#N` issue number
	// (e.g., `#42`). For RowEntity in the roadmap profile, Key is the
	// feature label text from the first cell (with any markdown link
	// syntax stripped). For RowDescription and RowChild, Key is empty.
	Key string
	// Deps is the parsed dependency targets from the Dependencies cell of
	// an entity row -- one entry per comma-separated link or the string
	// "None". For non-entity rows, Deps is nil.
	Deps []string
	// Line is the 1-indexed absolute line number of the row in the doc.
	Line int
	// Raw is the row's raw text including leading and trailing pipes.
	Raw string
}

// Table is the parsed issues table from a single Markdown doc.
type Table struct {
	// Columns is the header column names in order, with surrounding
	// whitespace trimmed and markdown stripped.
	Columns []string
	// Rows is every body row in order (entity, description, child).
	Rows []Row
	// HeaderLine is the 1-indexed absolute line number of the header row.
	HeaderLine int
}

// implementationIssuesHeading matches the Implementation Issues section
// heading. The validator finds the table inside this section's body.
const implementationIssuesHeading = "## Implementation Issues"

// strikethroughPattern strips `~~...~~` markers so a struck-through row
// classifies the same way as an open row.
var strikethroughPattern = regexp.MustCompile(`~~([^~]*)~~`)

// issueRefPattern extracts the `#N` token from a plan-profile entity
// cell. Matches `#` followed by one or more digits.
var issueRefPattern = regexp.MustCompile(`#(\d+)`)

// parseIssuesTable locates the GFM pipe table under the Implementation
// Issues section of doc and parses it into a Table.
//
// Returns (Table, true) if a table is found. Returns (Table{}, false)
// when the section is absent, the section has no table, or the table is
// malformed (no header / no separator row). The parser is total over
// arbitrary line input: it never panics on ragged rows, unterminated
// sections, or missing separators.
func parseIssuesTable(doc Doc) (Table, bool) {
	startIdx, endIdx, headerLine, ok := findIssuesTableSection(doc)
	if !ok {
		return Table{}, false
	}

	// Find the header row inside [startIdx, endIdx).
	hdrIdx := -1
	for i := startIdx; i < endIdx; i++ {
		line := doc.Body[i]
		trimmed := strings.TrimSpace(line)
		if trimmed == "" {
			continue
		}
		if isTableRow(trimmed) {
			hdrIdx = i
			break
		}
	}
	if hdrIdx < 0 {
		return Table{}, false
	}

	// The line immediately after the header must be a separator row
	// (`| --- | --- | ... |`). If absent, treat as no-table-found.
	sepIdx := hdrIdx + 1
	if sepIdx >= endIdx {
		return Table{}, false
	}
	if !isSeparatorRow(strings.TrimSpace(doc.Body[sepIdx])) {
		return Table{}, false
	}

	columns := splitRow(doc.Body[hdrIdx])
	if len(columns) == 0 {
		return Table{}, false
	}

	table := Table{
		Columns:    columns,
		HeaderLine: headerLine,
	}

	// Find the Dependencies column index by header. Missing/legacy
	// shapes that have no Dependencies column produce depCol == -1; FC05
	// reports the schema mismatch and FC06 simply finds no targets to
	// validate.
	depCol := -1
	for i, c := range columns {
		if c == "Dependencies" {
			depCol = i
			break
		}
	}

	// Iterate body rows until we hit a blank line or the section ends.
	for i := sepIdx + 1; i < endIdx; i++ {
		raw := doc.Body[i]
		trimmed := strings.TrimSpace(raw)
		if trimmed == "" {
			// A blank line ends the table body.
			break
		}
		if !isTableRow(trimmed) {
			// A non-pipe line ends the table body.
			break
		}
		cells := splitRow(raw)
		row := classifyRow(cells, depCol)
		// Absolute line = headerLine offset by (i - hdrIdx).
		row.Line = headerLine + (i - hdrIdx)
		row.Raw = doc.Body[i]
		table.Rows = append(table.Rows, row)
	}

	return table, true
}

// findIssuesTableSection returns the [start, end) body indices that
// bound the Implementation Issues section, and the absolute line of
// its heading. Returns false if the section is absent.
func findIssuesTableSection(doc Doc) (start, end, headingLine int, ok bool) {
	// Section heading must appear in Doc.Sections (## level) under the
	// name "Implementation Issues".
	headingSec := -1
	for _, sec := range doc.Sections {
		if sec.Name == "Implementation Issues" {
			headingLine = sec.Line
			headingSec = headingLine
			break
		}
	}
	if headingSec < 0 {
		return 0, 0, 0, false
	}

	// Walk Body to find the heading line index and the next ## heading.
	startIdx := -1
	endIdx := len(doc.Body)
	for i, line := range doc.Body {
		if startIdx < 0 {
			if strings.TrimRight(line, " \t") == implementationIssuesHeading {
				startIdx = i + 1
			}
			continue
		}
		// Past the heading -- watch for the next ## heading.
		if strings.HasPrefix(line, "## ") {
			endIdx = i
			break
		}
	}
	if startIdx < 0 {
		return 0, 0, 0, false
	}
	return startIdx, endIdx, headingLine, true
}

// isTableRow reports whether trimmed is a GFM pipe-table row -- starts
// with `|` and contains at least one cell separator.
func isTableRow(trimmed string) bool {
	if !strings.HasPrefix(trimmed, "|") {
		return false
	}
	// A valid table row has at least two `|` characters.
	return strings.Count(trimmed, "|") >= 2
}

// isSeparatorRow reports whether trimmed is a GFM separator row -- each
// cell contains only dashes, colons, and whitespace.
func isSeparatorRow(trimmed string) bool {
	if !isTableRow(trimmed) {
		return false
	}
	cells := splitRow(trimmed)
	if len(cells) == 0 {
		return false
	}
	for _, c := range cells {
		c = strings.TrimSpace(c)
		if c == "" {
			return false
		}
		for _, r := range c {
			if r != '-' && r != ':' {
				return false
			}
		}
	}
	return true
}

// splitRow splits a raw GFM pipe row into its cells. Surrounding pipes
// are removed and each cell is whitespace-trimmed. Empty trailing cells
// from `| a | | |` are preserved.
func splitRow(raw string) []string {
	trimmed := strings.TrimSpace(raw)
	if !strings.HasPrefix(trimmed, "|") {
		return nil
	}
	// Remove leading and trailing pipes.
	trimmed = strings.TrimPrefix(trimmed, "|")
	trimmed = strings.TrimSuffix(trimmed, "|")
	parts := strings.Split(trimmed, "|")
	cells := make([]string, len(parts))
	for i, p := range parts {
		cells[i] = strings.TrimSpace(p)
	}
	return cells
}

// classifyRow inspects the cells of a body row and produces a Row with
// its kind, key, and dependency targets populated. depCol is the index
// of the Dependencies column in the table header (-1 if absent).
func classifyRow(cells []string, depCol int) Row {
	if len(cells) == 0 {
		return Row{Kind: RowEntity}
	}
	first := stripStrikethrough(cells[0])

	// Child reference row: first cell starts with `^_` and remaining
	// cells are empty (after strikethrough strip).
	if strings.HasPrefix(first, "^_") {
		if restEmpty(cells[1:]) {
			return Row{Kind: RowChild}
		}
	}

	// Description row: first cell is wrapped in italic markers `_..._`
	// (single underscores) and remaining cells are empty.
	if isItalicCell(first) && restEmpty(cells[1:]) {
		return Row{Kind: RowDescription}
	}

	// Otherwise it's an entity row.
	row := Row{Kind: RowEntity}
	row.Key = extractEntityKey(first)
	if depCol >= 0 && depCol < len(cells) {
		row.Deps = extractDeps(stripStrikethrough(cells[depCol]))
	}
	return row
}

// extractDeps parses a Dependencies cell value into a list of targets.
// `None` (case-insensitive) and the empty string both yield nil.
// Otherwise the cell is split on commas; each token is normalized to its
// `#N` issue token if present, else to the feature-label text inside the
// link. Cross-repo references (`owner/repo#N`) preserve the slash so
// FC06 can recognize them as non-local and skip them.
func extractDeps(cell string) []string {
	c := strings.TrimSpace(cell)
	if c == "" {
		return nil
	}
	if strings.EqualFold(c, "none") {
		return nil
	}
	parts := strings.Split(c, ",")
	out := make([]string, 0, len(parts))
	for _, p := range parts {
		p = strings.TrimSpace(p)
		if p == "" {
			continue
		}
		// A `#N` token: only normalize to `#N` if no slash precedes it
		// in the token (cross-repo refs like `owner/repo#N` keep the
		// slash so FC06 treats them as non-local).
		if loc := issueRefPattern.FindStringIndex(p); loc != nil {
			before := p[:loc[0]]
			// Strip leading markdown-link `[`.
			before = strings.TrimLeft(before, "[")
			if !strings.Contains(before, "/") {
				out = append(out, p[loc[0]:loc[1]])
				continue
			}
			// Preserve the cross-repo form for non-local detection.
			out = append(out, strings.TrimSpace(p))
			continue
		}
		// Otherwise use the link text or the raw cell content.
		out = append(out, normalizeFeatureRef(p))
	}
	return out
}

// extractEntityKey returns the entity row's primary key from the first
// cell.
//
// For a plan-profile entity row, the cell looks like
// `[#N: <title>](<url>)`; the key is `#N`. For a roadmap-profile entity
// row, the cell is a feature label (free text, possibly with a markdown
// link to a per-feature anchor); the key is the normalized label.
func extractEntityKey(cell string) string {
	c := stripStrikethrough(cell)
	if m := issueRefPattern.FindString(c); m != "" {
		return m
	}
	return normalizeFeatureRef(c)
}

// normalizeFeatureRef strips markdown link syntax to produce a stable
// label suitable for cross-reference lookup.
func normalizeFeatureRef(s string) string {
	s = strings.TrimSpace(s)
	// `[label](url)` -> `label`
	if strings.HasPrefix(s, "[") {
		if end := strings.Index(s, "]("); end > 0 {
			s = s[1:end]
		}
	}
	return strings.TrimSpace(s)
}

// stripStrikethrough removes `~~..~~` markers so a struck-through cell
// classifies the same as an open cell.
func stripStrikethrough(s string) string {
	return strikethroughPattern.ReplaceAllString(s, "$1")
}

// isItalicCell reports whether s is wrapped in single underscores. The
// description row's first cell is `_...some text..._`.
func isItalicCell(s string) bool {
	s = strings.TrimSpace(s)
	if len(s) < 2 {
		return false
	}
	if !strings.HasPrefix(s, "_") || !strings.HasSuffix(s, "_") {
		return false
	}
	// Reject `__text__` (bold) -- description rows use single underscores.
	if strings.HasPrefix(s, "__") {
		return false
	}
	return true
}

// restEmpty reports whether every cell in tail is empty after
// strikethrough is stripped.
func restEmpty(tail []string) bool {
	for _, c := range tail {
		if strings.TrimSpace(stripStrikethrough(c)) != "" {
			return false
		}
	}
	return true
}
