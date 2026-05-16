package annotation

import (
	"fmt"
	"strings"

	"github.com/tsukumogami/shirabe/internal/validate"
)

// sanitize strips newlines and carriage returns from a string to prevent
// annotation injection via crafted frontmatter field values.
func sanitize(s string) string {
	s = strings.ReplaceAll(s, "\n", "")
	s = strings.ReplaceAll(s, "\r", "")
	return s
}

// FormatError formats a ValidationError as a GHA ::error annotation string.
// All field values embedded in the annotation are sanitized to prevent injection.
func FormatError(err validate.ValidationError) string {
	file := sanitize(err.File)
	msg := sanitize(err.Message)
	if err.Line > 0 {
		return fmt.Sprintf("::error file=%s,line=%d::%s", file, err.Line, msg)
	}
	return fmt.Sprintf("::error file=%s::%s", file, msg)
}

// FormatNotice formats a file/message pair as a GHA ::notice annotation string.
// All embedded values are sanitized.
func FormatNotice(file, msg string) string {
	file = sanitize(file)
	msg = sanitize(msg)
	return fmt.Sprintf("::notice file=%s::%s", file, msg)
}
