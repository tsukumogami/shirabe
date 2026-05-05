package validate

import (
	"bufio"
	"bytes"
	"fmt"
	"os"
	"strings"

	"gopkg.in/yaml.v3"
)

// ParseDoc reads a Markdown file, extracts YAML frontmatter and ## headings,
// and returns a Doc with accurate absolute line numbers for each element.
func ParseDoc(path string) (Doc, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return Doc{}, fmt.Errorf("read %s: %w", path, err)
	}
	return parseDocBytes(path, data)
}

// parseDocBytes is the testable core of ParseDoc.
func parseDocBytes(path string, data []byte) (Doc, error) {
	fmBytes, fmStartLine, bodyStartLine, err := splitFrontmatter(data)
	if err != nil {
		// No frontmatter is not an error — just an empty field map.
		if err == errNoFrontmatter {
			doc := Doc{Path: path, Fields: make(map[string]FieldValue)}
			doc.Sections, doc.Body = scanBody(data, 1)
			return doc, nil
		}
		return Doc{}, fmt.Errorf("parse %s: %w", path, err)
	}

	fields, err := parseYAMLFields(fmBytes, fmStartLine)
	if err != nil {
		return Doc{}, fmt.Errorf("parse frontmatter in %s: %w", path, err)
	}

	doc := Doc{Path: path, Fields: fields}
	if fv, ok := fields["schema"]; ok {
		doc.Schema = fv.Value
	}
	if fv, ok := fields["status"]; ok {
		doc.Status = fv.Value
	}

	bodyData := bodyAfterLine(data, bodyStartLine)
	doc.Sections, doc.Body = scanBody(bodyData, bodyStartLine)
	return doc, nil
}

var errNoFrontmatter = fmt.Errorf("no frontmatter")

// splitFrontmatter finds the --- delimiters and returns the YAML bytes,
// the 1-indexed line number of the line after the opening ---, and the
// 1-indexed line number of the first body line after the closing ---.
func splitFrontmatter(data []byte) (fmBytes []byte, fmStartLine, bodyStartLine int, err error) {
	scanner := bufio.NewScanner(bytes.NewReader(data))
	lineNum := 0
	openLine := -1

	var fmLines []string

	for scanner.Scan() {
		lineNum++
		line := scanner.Text()

		if openLine == -1 {
			if line == "---" {
				openLine = lineNum
			} else {
				// Non-blank first line before ---: no frontmatter
				if strings.TrimSpace(line) != "" {
					return nil, 0, 0, errNoFrontmatter
				}
			}
			continue
		}

		if line == "---" {
			// Closing delimiter found
			fmStartLine = openLine + 1
			bodyStartLine = lineNum + 1
			return []byte(strings.Join(fmLines, "\n") + "\n"), fmStartLine, bodyStartLine, nil
		}
		fmLines = append(fmLines, line)
	}

	if openLine == -1 {
		return nil, 0, 0, errNoFrontmatter
	}
	return nil, 0, 0, fmt.Errorf("unclosed frontmatter: opening --- at line %d has no closing ---", openLine)
}

// parseYAMLFields decodes a YAML mapping using yaml.Node to get per-key line numbers,
// then offsets each key's line by (fmStartLine - 1) to produce absolute file positions.
func parseYAMLFields(fmBytes []byte, fmStartLine int) (map[string]FieldValue, error) {
	var node yaml.Node
	if err := yaml.Unmarshal(fmBytes, &node); err != nil {
		return nil, err
	}

	fields := make(map[string]FieldValue)
	if node.Kind == 0 || len(node.Content) == 0 {
		return fields, nil
	}

	// yaml.Unmarshal wraps a document node; the mapping is node.Content[0].
	mapping := node.Content[0]
	if mapping.Kind != yaml.MappingNode {
		return fields, nil
	}

	// yaml.Node line numbers are 1-indexed within the YAML string.
	// fmStartLine is the 1-indexed absolute line of the first YAML line.
	// absolute = yaml_line + (fmStartLine - 1)
	offset := fmStartLine - 1

	for i := 0; i+1 < len(mapping.Content); i += 2 {
		keyNode := mapping.Content[i]
		valNode := mapping.Content[i+1]

		key := keyNode.Value
		absoluteLine := keyNode.Line + offset

		// For block scalars and multi-line values, use the scalar string value.
		value := valNode.Value
		fields[key] = FieldValue{Value: strings.TrimRight(value, "\n"), Line: absoluteLine}
	}
	return fields, nil
}

// bodyAfterLine returns all bytes from the given 1-indexed start line onward.
func bodyAfterLine(data []byte, startLine int) []byte {
	if startLine <= 1 {
		return data
	}
	scanner := bufio.NewScanner(bytes.NewReader(data))
	lineNum := 0
	var buf bytes.Buffer
	for scanner.Scan() {
		lineNum++
		if lineNum >= startLine {
			buf.WriteString(scanner.Text())
			buf.WriteByte('\n')
		}
	}
	return buf.Bytes()
}

// scanBody extracts ## headings and raw body lines from body bytes,
// offsetting line numbers by bodyStartLine.
func scanBody(data []byte, bodyStartLine int) ([]Section, []string) {
	var sections []Section
	var bodyLines []string
	scanner := bufio.NewScanner(bytes.NewReader(data))
	lineNum := bodyStartLine - 1
	for scanner.Scan() {
		lineNum++
		line := scanner.Text()
		bodyLines = append(bodyLines, line)
		if strings.HasPrefix(line, "## ") {
			sections = append(sections, Section{
				Name: strings.TrimPrefix(line, "## "),
				Line: lineNum,
			})
		}
	}
	return sections, bodyLines
}
