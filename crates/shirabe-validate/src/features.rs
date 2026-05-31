//! Roadmap `## Features` section parser.
//!
//! Walks a roadmap [`Doc`]'s `## Features` section and produces a
//! [`Vec<Feature>`] suitable for downstream consumers (the binary crate's
//! `roadmap populate` subcommand, future tooling). The parser is total over
//! arbitrary line input -- a missing field falls back to a documented
//! default rather than panicking, and a section without features returns
//! an empty vector.
//!
//! Per-feature format expected (matches
//! `skills/roadmap/references/roadmap-format.md`):
//!
//! ```text
//! ### Feature N: <label>
//! **Needs:** `needs-design` -- optional rationale
//! **Dependencies:** None | Feature M | <cross-repo>#N, ...
//! **Status:** Not started | In Progress | Done | ...
//!
//! <one or more lines of description prose>
//! ```
//!
//! Order matters only for the heading line; the three bolded annotation
//! lines and the description are matched by their leading marker, not by
//! position, so an author writing them in a different order still parses.
//! The label captures everything after `### Feature N: ` up to end-of-line
//! and may include an inline issue link (e.g. `... — [#42](url)`); the
//! caller strips the link for downstream uses where the bare label is
//! wanted.

use crate::doc::Doc;

/// One parsed feature from a roadmap's `## Features` section.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Feature {
    /// 1-based index within the Features section (1, 2, 3, ...). The index
    /// is the source-of-truth identifier the dependency edges resolve
    /// against; `Feature 1` in a Dependencies cell means the feature with
    /// `id == 1`.
    pub id: usize,
    /// The full label text from the heading after `### Feature N: `.
    /// May contain trailing decoration (an em-dash plus an issue link),
    /// which the caller is expected to strip when a bare label is wanted.
    pub label: String,
    /// The raw `**Needs:**` line value (the text after the marker).
    /// Empty when the feature has no Needs line.
    pub needs: String,
    /// The raw `**Dependencies:**` line value.
    /// Empty when the feature has no Dependencies line.
    pub dependencies: String,
    /// The raw `**Status:**` line value.
    /// Empty when the feature has no Status line.
    pub status: String,
    /// Description prose collected from lines after the bolded annotations,
    /// up to the next `### ` heading or the end of the Features section.
    /// Blank lines are collapsed to single spaces so the description fits
    /// on one logical line (e.g. one table cell).
    pub description: String,
    /// 1-indexed absolute line number of the `### Feature N:` heading.
    pub heading_line: usize,
}

/// Parse the `## Features` section of `doc` into an ordered list of
/// [`Feature`]s. Returns an empty vector when the section is missing or
/// contains no `### Feature N:` headings.
pub fn parse_features(doc: &Doc) -> Vec<Feature> {
    let Some((start_idx, end_idx, _heading_line)) = find_features_section(doc) else {
        return Vec::new();
    };

    let mut out: Vec<Feature> = Vec::new();
    let mut current: Option<Feature> = None;
    let mut next_id: usize = 1;

    for i in start_idx..end_idx {
        let raw = &doc.body[i];

        // A `### Feature N:` heading starts a new feature. Any line at the
        // `### ` level that does NOT match the feature pattern also closes
        // the current feature (it's a different sub-heading); we then drop
        // through without opening a new one. The Features section in a
        // canonical roadmap only carries Feature sub-headings, but the
        // parser tolerates drift without panicking.
        if let Some(label) = parse_feature_heading(raw) {
            if let Some(f) = current.take() {
                out.push(f);
            }
            current = Some(Feature {
                id: next_id,
                label,
                needs: String::new(),
                dependencies: String::new(),
                status: String::new(),
                description: String::new(),
                heading_line: absolute_line(doc, i),
            });
            next_id += 1;
            continue;
        }
        if raw.starts_with("### ") {
            if let Some(f) = current.take() {
                out.push(f);
            }
            continue;
        }

        let Some(f) = current.as_mut() else {
            // We're inside the Features section but before the first
            // `### Feature N:` heading; skip preamble prose.
            continue;
        };

        if let Some(rest) = strip_marker(raw, "**Needs:**") {
            f.needs = rest.to_string();
            continue;
        }
        if let Some(rest) = strip_marker(raw, "**Dependencies:**") {
            f.dependencies = rest.to_string();
            continue;
        }
        if let Some(rest) = strip_marker(raw, "**Status:**") {
            f.status = rest.to_string();
            continue;
        }

        // Accumulate description prose. Blank lines compress to a single
        // space so the description renders cleanly into a one-row Markdown
        // table cell.
        let trimmed = raw.trim();
        if trimmed.is_empty() {
            if !f.description.is_empty() && !f.description.ends_with(' ') {
                f.description.push(' ');
            }
            continue;
        }
        if !f.description.is_empty() && !f.description.ends_with(' ') {
            f.description.push(' ');
        }
        f.description.push_str(trimmed);
    }

    if let Some(f) = current.take() {
        out.push(f);
    }

    // Trim any trailing spaces left over from blank-line collapse.
    for f in &mut out {
        while f.description.ends_with(' ') {
            f.description.pop();
        }
    }

    out
}

/// Strip an inline GitHub issue link (and the preceding em-dash separator
/// or `--` if present) from a feature heading label.
///
/// Examples:
/// - `"Recipe validation"` -> `"Recipe validation"`
/// - `"Recipe validation -- [#49](url)"` -> `"Recipe validation"`
/// - `"Recipe validation — [#49](url)"` -> `"Recipe validation"`
/// - `"Recipe validation [#49](url)"` -> `"Recipe validation"`
pub fn strip_label_decoration(label: &str) -> String {
    let mut s = label.to_string();
    if let Some(idx) = s.find(" [#") {
        s.truncate(idx);
    }
    // After dropping any trailing link, peel back a separator-only tail
    // (em-dash, `--`) plus the spaces around it. Loop because the label
    // may have had `name — [#N](url)` -> `name —` after the first cut.
    loop {
        let trimmed = s.trim_end();
        let new_len = if let Some(stripped) = trimmed.strip_suffix('—') {
            stripped.trim_end().len()
        } else if let Some(stripped) = trimmed.strip_suffix("--") {
            stripped.trim_end().len()
        } else {
            break;
        };
        s.truncate(new_len);
    }
    s.trim().to_string()
}

/// Extract a single `needs-<token>` label from a `**Needs:**` line. Returns
/// `None` when no `needs-<token>` token appears (e.g. `**Needs:** None`).
pub fn extract_needs_label(needs_line: &str) -> Option<String> {
    let bytes = needs_line.as_bytes();
    let mut i = 0;
    while i + 6 < bytes.len() {
        if &bytes[i..i + 6] == b"needs-" {
            let start = i;
            let mut end = start + 6;
            while end < bytes.len() {
                let c = bytes[end];
                let is_lower = c.is_ascii_lowercase();
                let is_digit = c.is_ascii_digit();
                let is_dash = c == b'-';
                if is_lower || is_digit || is_dash {
                    end += 1;
                } else {
                    break;
                }
            }
            if end > start + 6 {
                return Some(needs_line[start..end].to_string());
            }
        }
        i += 1;
    }
    None
}

/// Return the `[start, end)` body indices that bound the Features section,
/// plus the absolute line of its `## Features` heading. `None` if the
/// section is absent.
fn find_features_section(doc: &Doc) -> Option<(usize, usize, usize)> {
    let heading_line = doc
        .sections
        .iter()
        .find(|sec| sec.name == "Features")
        .map(|sec| sec.line)?;

    let mut start_idx: Option<usize> = None;
    let mut end_idx = doc.body.len();
    for (i, line) in doc.body.iter().enumerate() {
        if start_idx.is_none() {
            if line.trim_end_matches([' ', '\t']) == "## Features" {
                start_idx = Some(i + 1);
            }
            continue;
        }
        if line.starts_with("## ") {
            end_idx = i;
            break;
        }
    }
    let start_idx = start_idx?;
    Some((start_idx, end_idx, heading_line))
}

/// Convert a `doc.body` index into the 1-indexed absolute line number. The
/// body in `Doc` already excludes the frontmatter; the section's recorded
/// `line` includes the absolute offset, so we anchor against the first
/// section that includes index 0.
///
/// In practice the binary crate only needs `Feature.heading_line` for
/// downstream error messages, so an off-by-frontmatter-size value would
/// still be useful even if not strictly correct; we anchor with the
/// Features-section heading line so the relative position is exact even if
/// the absolute baseline drifts.
fn absolute_line(doc: &Doc, body_idx: usize) -> usize {
    // Find the Features section's absolute heading line.
    let features_heading = doc
        .sections
        .iter()
        .find(|s| s.name == "Features")
        .map(|s| s.line)
        .unwrap_or(0);

    // Locate the body index of the `## Features` line; the difference
    // (body_idx - that index) is the offset within the section, which is
    // exact regardless of the frontmatter size.
    let mut features_body_idx: Option<usize> = None;
    for (i, line) in doc.body.iter().enumerate() {
        if line.trim_end_matches([' ', '\t']) == "## Features" {
            features_body_idx = Some(i);
            break;
        }
    }
    let features_body_idx = features_body_idx.unwrap_or(0);
    features_heading + body_idx.saturating_sub(features_body_idx)
}

/// Recognize `### Feature N: <label>` and return the label.
fn parse_feature_heading(line: &str) -> Option<String> {
    let rest = line.strip_prefix("### Feature ")?;
    // Read decimal digits, then ":", then optional whitespace, then label.
    let mut chars = rest.char_indices();
    let mut last_digit_end: Option<usize> = None;
    while let Some((idx, c)) = chars.next() {
        if c.is_ascii_digit() {
            last_digit_end = Some(idx + c.len_utf8());
        } else {
            break;
        }
    }
    let digit_end = last_digit_end?;
    if digit_end == 0 {
        return None;
    }
    let after_digits = &rest[digit_end..];
    let after_colon = after_digits.strip_prefix(':')?;
    Some(after_colon.trim().to_string())
}

/// If `line` begins with the bold marker (e.g. `**Needs:**`), return the
/// text after it with leading whitespace trimmed.
fn strip_marker<'a>(line: &'a str, marker: &str) -> Option<&'a str> {
    line.strip_prefix(marker).map(str::trim_start)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::doc::Section;

    fn make_doc(body: Vec<&str>, sections: Vec<(&str, usize)>) -> Doc {
        Doc {
            path: "test.md".into(),
            schema: "roadmap/v1".into(),
            status: "Draft".into(),
            fields: Default::default(),
            sections: sections
                .into_iter()
                .map(|(name, line)| Section {
                    name: name.into(),
                    line,
                })
                .collect(),
            body: body.into_iter().map(str::to_string).collect(),
        }
    }

    #[test]
    fn parse_features_empty_when_section_missing() {
        let doc = make_doc(vec!["# title", "## Theme", "Some text"], vec![]);
        assert_eq!(parse_features(&doc), Vec::new());
    }

    #[test]
    fn parse_features_extracts_three_features() {
        let body = vec![
            "## Features",
            "",
            "### Feature 1: Foundation",
            "**Needs:** `needs-design` -- pending",
            "**Dependencies:** None",
            "**Status:** Not started",
            "",
            "The foundation layer.",
            "",
            "### Feature 2: Caching",
            "**Needs:** `needs-spike`",
            "**Dependencies:** Feature 1",
            "**Status:** Not started",
            "",
            "Adds a cache.",
            "",
            "### Feature 3: Bridge",
            "**Needs:** None",
            "**Dependencies:** tsukumogami/koto#65, Feature 1",
            "**Status:** Done",
            "",
            "Cross-repo bridge.",
            "",
            "## Sequencing Rationale",
        ];
        let doc = make_doc(body, vec![("Features", 1), ("Sequencing Rationale", 23)]);
        let features = parse_features(&doc);
        assert_eq!(features.len(), 3);
        assert_eq!(features[0].id, 1);
        assert_eq!(features[0].label, "Foundation");
        assert_eq!(features[0].needs, "`needs-design` -- pending");
        assert_eq!(features[0].dependencies, "None");
        assert_eq!(features[0].status, "Not started");
        assert_eq!(features[0].description, "The foundation layer.");

        assert_eq!(features[1].id, 2);
        assert_eq!(features[1].label, "Caching");
        assert_eq!(features[1].dependencies, "Feature 1");

        assert_eq!(features[2].id, 3);
        assert_eq!(features[2].label, "Bridge");
        assert_eq!(features[2].dependencies, "tsukumogami/koto#65, Feature 1");
        assert_eq!(features[2].status, "Done");
    }

    #[test]
    fn parse_features_label_with_inline_link_kept_verbatim() {
        let body = vec![
            "## Features",
            "### Feature 1: Foo — [#42](https://example.com/issues/42)",
            "**Needs:** None",
            "**Dependencies:** None",
            "**Status:** Not started",
            "",
            "Body.",
        ];
        let doc = make_doc(body, vec![("Features", 1)]);
        let features = parse_features(&doc);
        assert_eq!(features.len(), 1);
        assert_eq!(
            features[0].label,
            "Foo — [#42](https://example.com/issues/42)"
        );
        assert_eq!(strip_label_decoration(&features[0].label), "Foo");
    }

    #[test]
    fn parse_features_ragged_input_does_not_panic() {
        // No features, malformed sub-headings, no markers -- parser must
        // simply return an empty Vec.
        let body = vec![
            "## Features",
            "### NotAFeature",
            "random prose",
            "**Bad:** value",
            "## Other",
        ];
        let doc = make_doc(body, vec![("Features", 1), ("Other", 5)]);
        let features = parse_features(&doc);
        assert!(features.is_empty());
    }

    #[test]
    fn extract_needs_label_finds_first_token() {
        assert_eq!(
            extract_needs_label("`needs-design` -- rationale"),
            Some("needs-design".to_string())
        );
        assert_eq!(
            extract_needs_label("Looks like needs-spike fits"),
            Some("needs-spike".to_string())
        );
        assert_eq!(extract_needs_label("None"), None);
        assert_eq!(extract_needs_label(""), None);
        assert_eq!(extract_needs_label("needs-"), None);
    }

    #[test]
    fn strip_label_decoration_handles_variants() {
        assert_eq!(strip_label_decoration("Foo"), "Foo");
        assert_eq!(strip_label_decoration("Foo -- [#1](url)"), "Foo");
        assert_eq!(strip_label_decoration("Foo — [#1](url)"), "Foo");
        assert_eq!(strip_label_decoration("Foo [#1](url)"), "Foo");
    }

    #[test]
    fn parse_features_metacharacters_in_label_round_trip() {
        // The parser MUST NOT interpret shell metacharacters in labels --
        // they round-trip verbatim into the Feature.label.
        let body = vec![
            "## Features",
            "### Feature 1: Safe; rm -rf /tmp/foo && echo HIJACKED",
            "**Needs:** None",
            "**Dependencies:** None",
            "**Status:** Not started",
        ];
        let doc = make_doc(body, vec![("Features", 1)]);
        let features = parse_features(&doc);
        assert_eq!(features.len(), 1);
        assert_eq!(
            features[0].label,
            "Safe; rm -rf /tmp/foo && echo HIJACKED"
        );
    }
}
