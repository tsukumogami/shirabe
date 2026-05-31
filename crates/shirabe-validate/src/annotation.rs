//! GitHub Actions workflow-command annotation formatting.
//!
//! Renders [`ValidationError`]s as `::error` / `::notice` workflow-command
//! strings. Output is byte-identical to the Go `internal/annotation`
//! package so the GHA log annotations stay stable across the rewrite.
//!
//! The two formatters are intentionally asymmetric: [`format_error`] takes
//! a whole [`ValidationError`] (and conditionally emits a `line=` field),
//! while [`format_notice`] takes a bare `(file, msg)` pair. Notices come
//! from the SCHEMA path (line is always 1, so the position is dropped) and
//! from the IO-error path in the binary (which never builds a
//! `ValidationError`). Preserving the asymmetry preserves the output bytes.

use crate::doc::ValidationError;

/// Strips newlines and carriage returns from a string to prevent
/// annotation injection via crafted frontmatter field values.
fn sanitize(s: &str) -> String {
    // Removing both characters in a single pass is byte-identical to the
    // Go implementation's two sequential ReplaceAll calls: neither removal
    // can produce a newline or carriage return for the other to match.
    s.replace(['\n', '\r'], "")
}

/// Formats a [`ValidationError`] as a GHA `::error` annotation string. All
/// embedded field values are sanitized to prevent injection.
pub fn format_error(err: &ValidationError) -> String {
    let file = sanitize(&err.file);
    let msg = sanitize(&err.message);
    if err.line > 0 {
        format!("::error file={},line={}::{}", file, err.line, msg)
    } else {
        format!("::error file={}::{}", file, msg)
    }
}

/// Formats a file/message pair as a GHA `::notice` annotation string. All
/// embedded values are sanitized.
pub fn format_notice(file: &str, msg: &str) -> String {
    let file = sanitize(file);
    let msg = sanitize(msg);
    format!("::notice file={}::{}", file, msg)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn err(file: &str, line: usize, message: &str) -> ValidationError {
        ValidationError {
            file: file.to_string(),
            line,
            code: "FC01".to_string(),
            message: message.to_string(),
        }
    }

    #[test]
    fn format_error_with_line_includes_line_field() {
        let e = err(
            "docs/DESIGN-foo.md",
            12,
            "[FC01] missing required field \"status\"",
        );
        assert_eq!(
            format_error(&e),
            "::error file=docs/DESIGN-foo.md,line=12::[FC01] missing required field \"status\""
        );
    }

    #[test]
    fn format_error_zero_line_omits_line_field() {
        let e = err("docs/DESIGN-foo.md", 0, "boom");
        assert_eq!(format_error(&e), "::error file=docs/DESIGN-foo.md::boom");
    }

    #[test]
    fn format_error_sanitizes_newlines_and_carriage_returns() {
        let e = err("a\nb.md", 3, "line1\r\nline2");
        // Newlines and CRs are stripped from both file and message.
        assert_eq!(format_error(&e), "::error file=ab.md,line=3::line1line2");
    }

    #[test]
    fn format_notice_basic() {
        assert_eq!(
            format_notice("docs/DESIGN-foo.md", "schema \"design/v2\" not in supported range, skipping"),
            "::notice file=docs/DESIGN-foo.md::schema \"design/v2\" not in supported range, skipping"
        );
    }

    #[test]
    fn format_notice_sanitizes() {
        assert_eq!(
            format_notice("a\rb.md", "m\nsg"),
            "::notice file=ab.md::msg"
        );
    }
}
