//! YAML frontmatter parser with per-key line-number reconstruction.
//!
//! Uses `saphyr`'s `MarkedYamlOwned` API to read the document mapping
//! with per-node `Span` markers. The `parse_yaml_fields` function
//! produces a `HashMap<String, FieldValue { value, line }>` directly
//! analogous to the Go `internal/validate.parseYAMLFields`.
//!
//! ## Backstop: saphyr-parser SpannedEventReceiver
//!
//! saphyr is pre-1.0 (0.0.x version line) and the higher-level API
//! may shift between patch releases. If the pinned saphyr version's
//! `MarkedYamlOwned` / `Span` surface drifts more than cosmetically
//! from what `parse_yaml_fields` expects, the implementation should
//! drop to the lower-level `saphyr-parser` crate's `SpannedEventReceiver`
//! and walk events (`StreamStart`, `MappingStart`, `Scalar`) directly,
//! recovering per-key positions from event markers. This is roughly
//! +40 LOC of code but uses only stable parser-level primitives.
//!
//! If the backstop fires, `Cargo.toml` swaps `saphyr` for
//! `saphyr-parser`. The public surface of this module is unchanged.
//!
//! See DESIGN Decision 1 (§"YAML parser with per-key line numbers")
//! and §"YAML field-to-line reconstruction (the flagged technical risk)".

use std::collections::HashMap;
use std::fmt;
use std::fs;
use std::io;
use std::path::Path;

use saphyr::{LoadableYamlNode, MarkedYamlOwned, YamlDataOwned};

use crate::doc::{Doc, FieldValue, Section};

/// Errors produced by the frontmatter parser and its helpers.
///
/// The variants are hand-rolled (no `thiserror`) per DESIGN Decision 4
/// to keep the future crates.io boundary free of derive-macro leakage.
#[derive(Debug)]
pub enum ParseError {
    /// File I/O failed.
    Io(io::Error),
    /// YAML parsing failed inside the frontmatter block.
    Yaml(String),
    /// An opening `---` was found but no closing `---` matched.
    Unclosed(usize),
}

impl fmt::Display for ParseError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::Io(e) => write!(f, "io error: {}", e),
            Self::Yaml(msg) => write!(f, "yaml error: {}", msg),
            Self::Unclosed(line) => write!(
                f,
                "unclosed frontmatter: opening --- at line {} has no closing ---",
                line
            ),
        }
    }
}

impl std::error::Error for ParseError {
    fn source(&self) -> Option<&(dyn std::error::Error + 'static)> {
        match self {
            Self::Io(e) => Some(e),
            _ => None,
        }
    }
}

impl From<io::Error> for ParseError {
    fn from(value: io::Error) -> Self {
        Self::Io(value)
    }
}

/// Read a Markdown file, extract YAML frontmatter and `## ` headings,
/// and return a `Doc` with absolute 1-indexed line numbers.
pub fn parse_doc<P: AsRef<Path>>(path: P) -> Result<Doc, ParseError> {
    let path = path.as_ref();
    let data = fs::read(path).map_err(|e| {
        ParseError::Io(io::Error::new(
            e.kind(),
            format!("read {}: {}", path.display(), e),
        ))
    })?;
    parse_doc_bytes(&path.display().to_string(), &data)
}

/// Testable core of [`parse_doc`].
///
/// `path` is preserved verbatim into `Doc.path` for downstream error
/// messages; it is not opened or accessed in any way.
pub fn parse_doc_bytes(path: &str, data: &[u8]) -> Result<Doc, ParseError> {
    let split = split_frontmatter(data);
    let (fm_bytes, fm_start_line, body_start_line) = match split {
        Ok(parts) => parts,
        Err(SplitError::NoFrontmatter) => {
            // No frontmatter is not an error - just an empty field map.
            let mut doc = Doc {
                path: path.to_string(),
                schema: String::new(),
                status: String::new(),
                fields: HashMap::new(),
                sections: Vec::new(),
                body: Vec::new(),
            };
            let (sections, body) = scan_body(data, 1);
            doc.sections = sections;
            doc.body = body;
            return Ok(doc);
        }
        Err(SplitError::Unclosed(line)) => return Err(ParseError::Unclosed(line)),
    };

    let fields = parse_yaml_fields(&fm_bytes, fm_start_line)?;

    let schema = fields
        .get("schema")
        .map(|fv| fv.value.clone())
        .unwrap_or_default();
    let status = fields
        .get("status")
        .map(|fv| fv.value.clone())
        .unwrap_or_default();

    let body_data = body_after_line(data, body_start_line);
    let (sections, body) = scan_body(&body_data, body_start_line);

    Ok(Doc {
        path: path.to_string(),
        schema,
        status,
        fields,
        sections,
        body,
    })
}

/// Internal error type for `split_frontmatter`. Translated to either
/// `ParseError::Unclosed` or the no-frontmatter branch in
/// `parse_doc_bytes`.
#[derive(Debug)]
enum SplitError {
    NoFrontmatter,
    Unclosed(usize),
}

/// Find the `---` delimiters and return the YAML bytes, the 1-indexed
/// line number of the line after the opening `---`, and the 1-indexed
/// line number of the first body line after the closing `---`.
fn split_frontmatter(data: &[u8]) -> Result<(Vec<u8>, usize, usize), SplitError> {
    let text = String::from_utf8_lossy(data);
    let mut fm_lines: Vec<&str> = Vec::new();
    let mut line_num: usize = 0;
    let mut open_line: Option<usize> = None;

    for line in split_lines(&text) {
        line_num += 1;

        if open_line.is_none() {
            if line == "---" {
                open_line = Some(line_num);
            } else if !line.trim().is_empty() {
                // Non-blank first line before --- means no frontmatter.
                return Err(SplitError::NoFrontmatter);
            }
            continue;
        }

        if line == "---" {
            let fm_start_line = open_line.unwrap() + 1;
            let body_start_line = line_num + 1;
            let mut buf = fm_lines.join("\n");
            buf.push('\n');
            return Ok((buf.into_bytes(), fm_start_line, body_start_line));
        }
        fm_lines.push(line);
    }

    match open_line {
        None => Err(SplitError::NoFrontmatter),
        Some(line) => Err(SplitError::Unclosed(line)),
    }
}

/// Decode a YAML mapping using `MarkedYamlOwned` for per-key line
/// numbers, then offset each key's line by `(fm_start_line - 1)` to
/// produce absolute file positions.
fn parse_yaml_fields(
    fm_bytes: &[u8],
    fm_start_line: usize,
) -> Result<HashMap<String, FieldValue>, ParseError> {
    let yaml_str = std::str::from_utf8(fm_bytes).map_err(|e| ParseError::Yaml(e.to_string()))?;

    let docs =
        MarkedYamlOwned::load_from_str(yaml_str).map_err(|e| ParseError::Yaml(e.to_string()))?;

    let mut fields: HashMap<String, FieldValue> = HashMap::new();

    let Some(root) = docs.into_iter().next() else {
        return Ok(fields);
    };

    // Anything other than a mapping at the document root yields an
    // empty map - matches the Go implementation's behavior for
    // non-mapping roots.
    let Some(mapping) = root.data.as_mapping() else {
        return Ok(fields);
    };

    // `Span.start.line()` is 1-indexed within the YAML input string.
    // `fm_start_line` is the 1-indexed absolute line of the YAML
    // input's first line in the source file.
    let offset = fm_start_line.saturating_sub(1);

    for (key_node, val_node) in mapping.iter() {
        let Some(key) = key_node.data.as_str() else {
            continue;
        };
        let absolute_line = key_node.span.start.line() + offset;
        let value = scalar_to_string(&val_node.data);
        fields.insert(
            key.to_string(),
            FieldValue {
                value: value
                    .trim_end_matches('\n')
                    .to_string(),
                line: absolute_line,
            },
        );
    }

    Ok(fields)
}

/// Coerce a YAML scalar (string, integer, float, boolean) to its
/// string representation.
///
/// saphyr's `Scalar` enum distinguishes typed scalars, so `as_str`
/// returns `None` on an integer or boolean node. shirabe's corpus
/// includes typed-integer frontmatter (`issue_count: 8` in plan/v1),
/// so this function MUST coerce typed scalars back to their string
/// representation rather than fall through to an empty default.
///
/// Per DESIGN Decision 1 (§"Typed-scalar preservation"): falling back
/// to `unwrap_or_default()` on `as_str` would silently drop typed
/// scalar values; the parity fixture catches divergence on this path.
fn scalar_to_string(data: &YamlDataOwned<MarkedYamlOwned>) -> String {
    if let Some(s) = data.as_str() {
        return s.to_string();
    }
    if let Some(b) = data.as_bool() {
        return b.to_string();
    }
    if let Some(i) = data.as_integer() {
        return i.to_string();
    }
    if let Some(f) = data.as_floating_point() {
        return f.to_string();
    }
    String::new()
}

/// Return all bytes from the given 1-indexed start line onward.
fn body_after_line(data: &[u8], start_line: usize) -> Vec<u8> {
    if start_line <= 1 {
        return data.to_vec();
    }
    let text = String::from_utf8_lossy(data);
    let mut buf = String::new();
    for (i, line) in split_lines(&text).enumerate() {
        let line_num = i + 1;
        if line_num >= start_line {
            buf.push_str(line);
            buf.push('\n');
        }
    }
    buf.into_bytes()
}

/// Extract `## ` headings and raw body lines from body bytes,
/// offsetting line numbers by `body_start_line`.
fn scan_body(data: &[u8], body_start_line: usize) -> (Vec<Section>, Vec<String>) {
    let mut sections: Vec<Section> = Vec::new();
    let mut body_lines: Vec<String> = Vec::new();
    let text = String::from_utf8_lossy(data);
    let mut line_num = body_start_line.saturating_sub(1);
    for line in split_lines(&text) {
        line_num += 1;
        body_lines.push(line.to_string());
        if let Some(name) = line.strip_prefix("## ") {
            sections.push(Section {
                name: name.to_string(),
                line: line_num,
            });
        }
    }
    (sections, body_lines)
}

/// Iterator over the lines of `text`, matching Go `bufio.Scanner` semantics:
/// strip the trailing `\n` (and `\r\n`), do not yield a final empty line
/// when input ends with `\n`.
fn split_lines(text: &str) -> impl Iterator<Item = &str> {
    let trimmed = text.strip_suffix('\n').unwrap_or(text);
    if trimmed.is_empty() && text.is_empty() {
        // Empty input produces no lines.
        return SplitLines::Empty;
    }
    SplitLines::Lines(trimmed.split('\n'))
}

enum SplitLines<'a> {
    Empty,
    Lines(std::str::Split<'a, char>),
}

impl<'a> Iterator for SplitLines<'a> {
    type Item = &'a str;

    fn next(&mut self) -> Option<Self::Item> {
        match self {
            Self::Empty => None,
            Self::Lines(it) => it.next().map(|line| line.strip_suffix('\r').unwrap_or(line)),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    // ---- ParseDocBytes table cases (ported from frontmatter_test.go) ----

    #[test]
    fn parse_doc_bytes_full_doc_with_schema_and_status() {
        let input = "---\nschema: design/v1\nstatus: Proposed\n---\n\n# Title\n\n## Status\n\nProposed\n";
        let doc = parse_doc_bytes("test.md", input.as_bytes()).expect("parse ok");
        assert_eq!(doc.schema, "design/v1");
        assert_eq!(doc.status, "Proposed");
        assert_eq!(doc.fields.get("schema").map(|fv| fv.line), Some(2));
        assert_eq!(doc.fields.get("status").map(|fv| fv.line), Some(3));
        let names: Vec<&str> = doc.sections.iter().map(|s| s.name.as_str()).collect();
        assert_eq!(names, vec!["Status"]);
    }

    #[test]
    fn parse_doc_bytes_no_frontmatter() {
        let input = "# Title\n\n## Status\n\nProposed\n";
        let doc = parse_doc_bytes("test.md", input.as_bytes()).expect("parse ok");
        assert!(doc.fields.is_empty(), "expected no fields, got {:?}", doc.fields);
        let names: Vec<&str> = doc.sections.iter().map(|s| s.name.as_str()).collect();
        assert_eq!(names, vec!["Status"]);
    }

    #[test]
    fn parse_doc_bytes_unclosed_frontmatter() {
        let input = "---\nschema: design/v1\n";
        let err = parse_doc_bytes("test.md", input.as_bytes()).expect_err("expected error");
        assert!(
            matches!(err, ParseError::Unclosed(_)),
            "expected Unclosed, got {:?}",
            err
        );
    }

    #[test]
    fn parse_doc_bytes_malformed_yaml() {
        let input = "---\nkey: [unclosed\n---\n";
        let err = parse_doc_bytes("test.md", input.as_bytes()).expect_err("expected error");
        assert!(
            matches!(err, ParseError::Yaml(_)),
            "expected Yaml, got {:?}",
            err
        );
    }

    #[test]
    fn parse_doc_bytes_block_scalar_value() {
        let input = "---\nstatus: Proposed\nproblem: |\n  This is a\n  block scalar.\n---\n";
        let doc = parse_doc_bytes("test.md", input.as_bytes()).expect("parse ok");
        assert_eq!(doc.status, "Proposed");
        assert_eq!(doc.fields.get("status").map(|fv| fv.line), Some(2));
        assert_eq!(doc.fields.get("problem").map(|fv| fv.line), Some(3));
    }

    #[test]
    fn parse_doc_bytes_multiple_headings_with_line_numbers() {
        let input = "---\nstatus: Active\n---\n\n## Context\n\nbody\n\n## Decision\n\nbody\n";
        let doc = parse_doc_bytes("test.md", input.as_bytes()).expect("parse ok");
        assert_eq!(doc.status, "Active");
        let names: Vec<&str> = doc.sections.iter().map(|s| s.name.as_str()).collect();
        assert_eq!(names, vec!["Context", "Decision"]);
    }

    #[test]
    fn parse_doc_bytes_heading_detection_only_hash_hash_prefix() {
        let input = "---\nstatus: Active\n---\n\n### Not a section\n## Is a section\n#### Also not\n";
        let doc = parse_doc_bytes("test.md", input.as_bytes()).expect("parse ok");
        assert_eq!(doc.status, "Active");
        let names: Vec<&str> = doc.sections.iter().map(|s| s.name.as_str()).collect();
        assert_eq!(names, vec!["Is a section"]);
    }

    #[test]
    fn parse_doc_bytes_empty_frontmatter() {
        let input = "---\n---\n\n## Status\n";
        let doc = parse_doc_bytes("test.md", input.as_bytes()).expect("parse ok");
        // wantNoFM is false in the Go test; sections must still pick up "Status".
        let names: Vec<&str> = doc.sections.iter().map(|s| s.name.as_str()).collect();
        assert_eq!(names, vec!["Status"]);
    }

    // ---- Direct ports of TestSplitFrontmatter_LineNumbers and TestParseDocBytes_BodyLines ----

    #[test]
    fn split_frontmatter_line_numbers() {
        let input = "---\nschema: design/v1\nstatus: Proposed\n---\nbody\n";
        let (_, fm_start, body_start) =
            split_frontmatter(input.as_bytes()).expect("split ok");
        assert_eq!(fm_start, 2);
        assert_eq!(body_start, 5);
    }

    #[test]
    fn parse_doc_bytes_body_lines() {
        let input = "---\nstatus: Active\n---\n\nsome body\nmore body\n";
        let doc = parse_doc_bytes("x.md", input.as_bytes()).expect("parse ok");
        let combined = doc.body.join("\n");
        assert!(
            combined.contains("some body"),
            "body missing 'some body': {:?}",
            combined
        );
    }

    // ---- Typed-scalar invariant (DESIGN Decision 1, lines 834-848) ----

    #[test]
    fn parse_doc_bytes_typed_integer_field() {
        // plan/v1 frontmatter includes `issue_count: 42` as a typed integer.
        // saphyr's `as_str()` returns None on integers, so the value
        // extraction MUST coerce the typed scalar to its string form.
        let input = "---\nschema: plan/v1\nstatus: Active\nissue_count: 42\n---\n\n## Status\n";
        let doc = parse_doc_bytes("test.md", input.as_bytes()).expect("parse ok");
        let fv = doc
            .fields
            .get("issue_count")
            .expect("issue_count missing");
        assert_eq!(fv.value, "42", "typed integer must coerce to string");
        assert_eq!(fv.line, 4, "issue_count is on line 4");
    }
}
