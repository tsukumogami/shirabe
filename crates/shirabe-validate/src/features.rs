//! Roadmap `## Features` section parser.
//!
//! Walks a roadmap [`Doc`]'s `## Features` section and produces a
//! [`Vec<Feature>`] suitable for downstream consumers (the binary crate's
//! `roadmap populate` subcommand, the validator's milestone check, future
//! tooling). The parser is total over arbitrary line input -- a missing field
//! falls back to a documented default rather than panicking, and a section
//! without features returns an empty vector.
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
//! A milestone roadmap (`schema: roadmap/v2`) adds `**Outcome:**`,
//! `**Evidence:**` (one `- ` clause per line below it), `**Left open:**` and
//! an optional `**Delivered:**`. A field's value runs from its marker to the
//! first blank line, the next column-0 `**Name:**` line or the next heading.
//!
//! The heading also accepts the strategy-derived prefix form
//! `### <PREFIX><N>: <label>` (e.g. `### ED1:`, `### SE2:`, `### AB10a:`),
//! where `<PREFIX>` is a short alphabetic tag immediately followed by the
//! feature number and, optionally, one lowercase letter. Both forms number
//! features positionally, so a `Feature M` dependency edge still resolves
//! against a prefixed roadmap; [`dependency_positions`] also resolves a
//! dependency named by its tag.
//!
//! Order matters only for the heading line; the bolded annotation lines and
//! the description are matched by their leading marker, not by position, so
//! an author writing them in a different order still parses. The label
//! captures everything after the heading's colon up to end-of-line and may
//! include an inline issue link (e.g. `... — [#42](url)`); the caller strips
//! the link for downstream uses where the bare label is wanted.

use std::sync::LazyLock;

use regex::Regex;

use crate::doc::Doc;

/// The schema value that marks a milestone roadmap.
pub const ROADMAP_V2_SCHEMA: &str = "roadmap/v2";

/// One parsed feature from a roadmap's `## Features` section.
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct Feature {
    /// 1-based index within the Features section (1, 2, 3, ...). The index
    /// is what [`dependency_positions`] returns and the dependency edges
    /// resolve to; `Feature 1` in a Dependencies cell means the feature
    /// tagged `Feature 1`, which is the one with `id == 1` unless headings
    /// are out of order.
    pub id: usize,
    /// The heading's tag: the text before its colon, `Feature 3` or `AB10a`.
    pub tag: String,
    /// The full label text from the heading, after the `### Feature N: ` (or
    /// `### <PREFIX><N>: `) prefix and colon.
    /// May contain trailing decoration (an em-dash plus an issue link),
    /// which the caller is expected to strip when a bare label is wanted.
    pub label: String,
    /// The raw `**Needs:**` line value (the text after the marker).
    /// Empty when the feature has no Needs line.
    pub needs: String,
    /// The raw `**Dependencies:**` line value.
    /// Empty when the feature has no Dependencies line.
    pub dependencies: String,
    /// True when a line that is neither blank, a field line nor a heading
    /// follows the `**Dependencies:**` line, so the list continues past the
    /// one line readers take it from.
    pub dependencies_continued: bool,
    /// The raw `**Status:**` line value.
    /// Empty when the feature has no Status line.
    pub status: String,
    /// The `**Outcome:**` value with its wrapped lines joined by single
    /// spaces; `None` when the item has no Outcome line.
    pub outcome: Option<String>,
    /// The `**Evidence:**` clauses, one string per `- ` line with its
    /// indented continuation lines joined; `None` when the item has no
    /// Evidence line, and empty when the line has no clause beneath it.
    pub evidence: Option<Vec<String>>,
    /// The `**Left open:**` value, joined like the Outcome; `None` when absent.
    pub left_open: Option<String>,
    /// The `**Delivered:**` value, joined like the Outcome; `None` when absent.
    pub delivered: Option<String>,
    /// Description prose collected from the item's other lines, up to the
    /// next `### ` heading or the end of the Features section. On a
    /// `roadmap/v2` document it excludes every field line's extent; on any
    /// other it is every line but the Needs, Dependencies and Status lines,
    /// as it always was. Blank lines are collapsed to single spaces so the
    /// description fits on one logical line (e.g. one table cell).
    pub description: String,
    /// 1-indexed absolute line number of the `### Feature N:` heading.
    pub heading_line: usize,
}

/// The field a line inside an item belongs to, while its extent runs.
#[derive(Clone, Copy, PartialEq, Eq)]
enum Field {
    Needs,
    Dependencies,
    Status,
    Outcome,
    Evidence,
    LeftOpen,
    Delivered,
    Other,
}

/// Parse the `## Features` section of `doc` into an ordered list of
/// [`Feature`]s. Returns an empty vector when the section is missing or
/// contains no feature headings (neither `### Feature N:` nor the
/// strategy-derived `### <PREFIX><N>:` form).
pub fn parse_features(doc: &Doc) -> Vec<Feature> {
    let Some((start_idx, end_idx, _heading_line)) = find_features_section(doc) else {
        return Vec::new();
    };
    let milestone = doc.schema == ROADMAP_V2_SCHEMA;

    let mut out: Vec<Feature> = Vec::new();
    let mut current: Option<Feature> = None;
    let mut field: Option<Field> = None;
    let mut next_id: usize = 1;

    for i in start_idx..end_idx {
        let raw = &doc.body[i];

        // A `### Feature N:` heading starts a new feature. Any line at the
        // `### ` level that does NOT match the feature pattern also closes
        // the current feature (it's a different sub-heading); we then drop
        // through without opening a new one. The Features section in a
        // canonical roadmap only carries Feature sub-headings, but the
        // parser tolerates drift without panicking.
        if let Some((tag, label)) = parse_feature_heading(raw) {
            if let Some(f) = current.take() {
                out.push(f);
            }
            current = Some(Feature {
                id: next_id,
                tag,
                label,
                heading_line: absolute_line(doc, i),
                ..Feature::default()
            });
            field = None;
            next_id += 1;
            continue;
        }
        if raw.starts_with("### ") {
            if let Some(f) = current.take() {
                out.push(f);
            }
            field = None;
            continue;
        }

        let Some(f) = current.as_mut() else {
            // We're inside the Features section but before the first
            // `### Feature N:` heading; skip preamble prose.
            continue;
        };

        if let Some((name, rest)) = split_field_line(raw) {
            let kind = match name {
                "Needs" => Field::Needs,
                "Dependencies" => Field::Dependencies,
                "Status" => Field::Status,
                "Outcome" => Field::Outcome,
                "Evidence" => Field::Evidence,
                "Left open" => Field::LeftOpen,
                "Delivered" => Field::Delivered,
                _ => Field::Other,
            };
            match kind {
                Field::Needs => f.needs = rest.to_string(),
                Field::Dependencies => f.dependencies = rest.to_string(),
                Field::Status => f.status = rest.to_string(),
                Field::Outcome => f.outcome = Some(rest.to_string()),
                Field::Evidence => f.evidence = Some(Vec::new()),
                Field::LeftOpen => f.left_open = Some(rest.to_string()),
                Field::Delivered => f.delivered = Some(rest.to_string()),
                Field::Other => {}
            }
            field = Some(kind);
            // The Needs, Dependencies and Status lines never reach the
            // description; on a milestone roadmap no field line does.
            let in_description =
                !milestone && !matches!(kind, Field::Needs | Field::Dependencies | Field::Status);
            if in_description {
                push_description(f, raw);
            }
            continue;
        }

        if raw.trim().is_empty() {
            field = None;
            push_description(f, raw);
            continue;
        }

        // A non-blank line inside a field's extent continues that field.
        let mut in_extent = true;
        match field {
            Some(Field::Outcome) => append_joined(&mut f.outcome, raw),
            Some(Field::LeftOpen) => append_joined(&mut f.left_open, raw),
            Some(Field::Delivered) => append_joined(&mut f.delivered, raw),
            Some(Field::Evidence) => {
                let clauses = f.evidence.get_or_insert_with(Vec::new);
                if let Some(text) = raw.strip_prefix("- ") {
                    // A `- ` line with no text after it is not a clause.
                    if !text.trim().is_empty() {
                        clauses.push(text.trim().to_string());
                    }
                } else if raw.starts_with([' ', '\t']) && !clauses.is_empty() {
                    let last = clauses.last_mut().expect("non-empty");
                    last.push(' ');
                    last.push_str(raw.trim());
                } else {
                    // A column-0 line that isn't a clause ends the field.
                    field = None;
                    in_extent = false;
                }
            }
            Some(Field::Dependencies) => f.dependencies_continued = true,
            // A wrapped Needs, Status or unknown field line stays in that
            // field's extent: on v2 it is left out of the description, and
            // no field value keeps it.
            Some(_) => {}
            None => in_extent = false,
        }
        if !milestone || !in_extent {
            push_description(f, raw);
        }
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

/// The `###` lines in the Features section that aren't milestone headings
/// ([`is_milestone_heading`]), as `(absolute line, heading text)` pairs.
/// [`parse_features`] passes over such a line silently, so this is how a
/// milestone check finds a mistyped heading that would otherwise hide an
/// item.
pub fn non_milestone_headings(doc: &Doc) -> Vec<(usize, String)> {
    let Some((start_idx, end_idx, _)) = find_features_section(doc) else {
        return Vec::new();
    };
    (start_idx..end_idx)
        .filter(|&i| doc.body[i].starts_with("### ") && !is_milestone_heading(&doc.body[i]))
        .map(|i| (absolute_line(doc, i), doc.body[i].trim_end().to_string()))
        .collect()
}

/// Accumulate one line of description prose. Blank lines compress to a
/// single space so the description renders cleanly into a one-row Markdown
/// table cell.
fn push_description(f: &mut Feature, raw: &str) {
    let trimmed = raw.trim();
    if trimmed.is_empty() {
        if !f.description.is_empty() && !f.description.ends_with(' ') {
            f.description.push(' ');
        }
        return;
    }
    if !f.description.is_empty() && !f.description.ends_with(' ') {
        f.description.push(' ');
    }
    f.description.push_str(trimmed);
}

/// Append a wrapped line to a joined field value, one space between.
fn append_joined(value: &mut Option<String>, raw: &str) {
    let v = value.get_or_insert_with(String::new);
    if !v.is_empty() {
        v.push(' ');
    }
    v.push_str(raw.trim());
}

/// Split a column-0 field line `**<Name>:** rest` into its name and the
/// text after the marker (leading whitespace trimmed). The name is a capital
/// letter followed by letters and spaces, as in `Left open`. `None` for any
/// other line, a bold phrase in prose included.
fn split_field_line(line: &str) -> Option<(&str, &str)> {
    let rest = line.strip_prefix("**")?;
    let end = rest.find(":**")?;
    let name = &rest[..end];
    let mut chars = name.chars();
    let first = chars.next()?;
    if !first.is_ascii_uppercase() || !chars.all(|c| c.is_ascii_alphabetic() || c == ' ') {
        return None;
    }
    Some((name, rest[end + 3..].trim_start()))
}

/// Matches a `**Dependencies:**` reference to one or more features. The
/// keyword is `Feature` or `Features` (case-insensitive), followed by a
/// list of feature-index integers separated by commas, whitespace, or the
/// word `and`. Cross-repo refs such as `tsukumogami/koto#65` carry no
/// `Feature` keyword and so contribute no captures.
static FEATURE_DEP_RE: LazyLock<Regex> =
    LazyLock::new(|| Regex::new(r"(?i)\bfeatures?\s+(\d+(?:[\s,]+(?:and[\s,]+)?\d+)*)").unwrap());

/// Matches a run of ASCII digits, used to pull each integer out of a
/// [`FEATURE_DEP_RE`] number list.
static DIGITS_RE: LazyLock<Regex> = LazyLock::new(|| Regex::new(r"\d+").unwrap());

/// Matches the `F<N>` index alias the issueless tables use.
static F_INDEX_RE: LazyLock<Regex> = LazyLock::new(|| Regex::new(r"\bF(\d+)\b").unwrap());

/// Matches a whole `[A-Za-z0-9]+` token, the unit a heading tag is compared
/// against.
static TOKEN_RE: LazyLock<Regex> = LazyLock::new(|| Regex::new(r"[A-Za-z0-9]+").unwrap());

/// Resolve a Dependencies value to the 1-based positions of the features it
/// names, in first-seen order and without repeats.
///
/// Three spellings name a feature:
///
/// - `Feature N`, `Features N, M and K` (any case), and `F<N>`, the index
///   alias the issueless tables use: the feature whose tag is `Feature N`
///   when one exists, else the Nth feature (an `F<N>` that is itself some
///   feature's tag resolves as that tag instead);
/// - a whole `[A-Za-z0-9]+` token equal to a feature's tag (`AB1`, `AB10a`).
///
/// A number or tag that names no feature contributes nothing, and a
/// cross-repo reference (`owner/repo#7`) never matches, so callers get only
/// positions they can index.
///
/// `own` is the position of the item whose Dependencies `deps` is, when it
/// is one. An item never depends on itself, so a mention of its own tag or
/// number (`AB7 (the review surface AB10 renders)` under `AB10`) is dropped,
/// as the coordinator's roadmap reader drops it. (FC21, which allows only
/// tags on a `roadmap/v2` Dependencies line, reports a self-mention there as
/// naming no other milestone.)
pub fn dependency_positions(deps: &str, features: &[Feature], own: Option<usize>) -> Vec<usize> {
    // `Feature N` names the item tagged so when there is one, else the Nth.
    let numbered = |n: usize| -> Option<usize> {
        let tagged = format!("Feature {n}");
        features
            .iter()
            .find(|f| f.tag == tagged)
            .map(|f| f.id)
            .or_else(|| (1..=features.len()).contains(&n).then_some(n))
    };
    let mut hits: Vec<(usize, usize)> = Vec::new();
    for cap in FEATURE_DEP_RE.captures_iter(deps) {
        let list = cap.get(1).expect("group 1");
        for m in DIGITS_RE.find_iter(list.as_str()) {
            if let Some(id) = m.as_str().parse::<usize>().ok().and_then(numbered) {
                hits.push((list.start() + m.start(), id));
            }
        }
    }
    for cap in F_INDEX_RE.captures_iter(deps) {
        let whole = cap.get(0).expect("group 0");
        // A feature tagged `F2` is found by the token pass below.
        if features.iter().any(|f| f.tag == whole.as_str()) {
            continue;
        }
        let m = cap.get(1).expect("group 1");
        if let Some(id) = m.as_str().parse::<usize>().ok().and_then(numbered) {
            hits.push((m.start(), id));
        }
    }
    for m in TOKEN_RE.find_iter(deps) {
        if let Some(f) = features.iter().find(|f| f.tag == m.as_str()) {
            hits.push((m.start(), f.id));
        }
    }
    hits.sort_by_key(|&(at, _)| at);
    let mut out: Vec<usize> = Vec::new();
    for (_, id) in hits {
        if Some(id) != own && !out.contains(&id) {
            out.push(id);
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

/// Recognize a feature heading and return its label. Two forms are accepted:
///
/// - `### Feature <N>: <label>` -- the classic numbered form.
/// - `### <PREFIX><N>: <label>` -- the strategy-derived prefix form, where
///   `<PREFIX>` is a short alphabetic tag (e.g. `ED`, `SE`, `SR`, `NW`)
///   immediately followed by the feature number with no space between them.
///
/// In both forms the returned label is everything after the colon, trimmed.
fn parse_feature_heading(line: &str) -> Option<(String, String)> {
    let rest = line.strip_prefix("### ")?;

    // Classic form: the literal word `Feature`, a space, then `<N>: <label>`.
    if let Some(after) = rest.strip_prefix("Feature ") {
        let (tag_len, label) = parse_number_colon_label(after, false)?;
        return Some((format!("Feature {}", &after[..tag_len]), label));
    }

    // Prefix form: an alphabetic tag immediately followed by the number (and
    // optionally one lowercase letter, as in `AB10a`), then `: <label>`.
    // Require at least one leading ASCII-alphabetic character so a tag-less
    // `### 1: x` is not mistaken for a feature.
    let mut alpha_end = 0;
    for (idx, c) in rest.char_indices() {
        if c.is_ascii_alphabetic() {
            alpha_end = idx + c.len_utf8();
        } else {
            break;
        }
    }
    if alpha_end == 0 {
        return None;
    }
    let (tag_len, label) = parse_number_colon_label(&rest[alpha_end..], true)?;
    Some((rest[..alpha_end + tag_len].to_string(), label))
}

/// Given text positioned at `<N>: <label>` (or `<N><letter>: <label>` when
/// `suffix` allows one lowercase letter after the number), read the number,
/// require the `:` delimiter, and return the length of the number part and
/// the trimmed label. `None` if the number or colon is missing.
fn parse_number_colon_label(s: &str, suffix: bool) -> Option<(usize, String)> {
    let mut digit_end = 0;
    for (idx, c) in s.char_indices() {
        if c.is_ascii_digit() {
            digit_end = idx + c.len_utf8();
        } else {
            break;
        }
    }
    if digit_end == 0 {
        return None;
    }
    let mut tag_end = digit_end;
    if suffix && s[digit_end..].starts_with(|c: char| c.is_ascii_lowercase()) {
        tag_end += 1;
    }
    let after_colon = s[tag_end..].strip_prefix(':')?;
    Some((tag_end, after_colon.trim().to_string()))
}

/// True when `line` is a milestone heading as a `roadmap/v2` roadmap requires
/// it: a feature heading [`parse_features`] reads, with a space after the
/// colon and a title that isn't empty. [`parse_features`] itself also takes
/// `### AB2:Lister`; a milestone heading doesn't, because the coordinator's
/// roadmap reader requires the space and would not see that item at all.
pub fn is_milestone_heading(line: &str) -> bool {
    match parse_feature_heading(line) {
        Some((tag, label)) => !label.is_empty() && line.starts_with(&format!("### {tag}: ")),
        None => false,
    }
}

/// True when `line` is a feature heading recognized by [`parse_features`]:
/// either the classic `### Feature <N>:` form or the strategy-derived
/// `### <PREFIX><N>:` prefix form. `shirabe transition` uses this to count
/// features with the same prefix grammar the parser applies, so a roadmap
/// that activates is also one the parser can read.
pub fn is_feature_heading(line: &str) -> bool {
    parse_feature_heading(line).is_some()
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
            body_start_line: 1,
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
    fn parse_features_accepts_strategy_derived_prefix_headings() {
        // The strategy-derived roadmap variant names features with a short
        // alphabetic prefix + number (`### ED1:`, `### ED2:`) instead of the
        // classic `### Feature N:`. The parser must recognize them, number
        // them positionally, and capture the label after the colon.
        let body = vec![
            "## Features",
            "",
            "### ED1: Dispatch event bus",
            "**Needs:** `needs-design`",
            "**Dependencies:** None",
            "**Status:** Not started",
            "",
            "The event bus.",
            "",
            "### ED2: Worker pool",
            "**Needs:** None",
            "**Dependencies:** Feature 1",
            "**Status:** Not started",
            "",
            "Runs workers.",
            "",
            "## Sequencing Rationale",
        ];
        let doc = make_doc(body, vec![("Features", 1), ("Sequencing Rationale", 17)]);
        let features = parse_features(&doc);
        assert_eq!(features.len(), 2);
        assert_eq!(features[0].id, 1);
        assert_eq!(features[0].label, "Dispatch event bus");
        assert_eq!(features[0].status, "Not started");
        assert_eq!(features[0].description, "The event bus.");
        assert_eq!(features[1].id, 2);
        assert_eq!(features[1].label, "Worker pool");
    }

    #[test]
    fn is_feature_heading_recognizes_both_forms() {
        // Classic numbered form.
        assert!(is_feature_heading("### Feature 1: Foundation"));
        assert!(is_feature_heading("### Feature 12: Caching"));
        // Strategy-derived prefix form (short alpha tag + number, no space).
        assert!(is_feature_heading("### ED1: Dispatch"));
        assert!(is_feature_heading("### SE2: Skills"));
        assert!(is_feature_heading("### SR10: Consolidation"));
        assert!(is_feature_heading("### NW1: Networking"));
        assert!(is_feature_heading("### A1: Single-letter tag"));
        // Non-headings and near-misses.
        assert!(!is_feature_heading("### Feature A")); // no number/colon
        assert!(!is_feature_heading("### Milestone: Foo")); // no number
        assert!(!is_feature_heading("### 1: No tag")); // no alpha prefix
        assert!(!is_feature_heading("### ED1 Dispatch")); // no colon
        assert!(!is_feature_heading("### Sequencing Rationale"));
        assert!(!is_feature_heading("## Features")); // wrong heading level
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
        assert_eq!(features[0].label, "Safe; rm -rf /tmp/foo && echo HIJACKED");
    }

    fn milestone_body() -> Vec<&'static str> {
        vec![
            "## Features",
            "",
            "### AB1: Loader",
            "**Outcome:** A maintainer runs the loader",
            "and gets every plugin",
            "listed by name.",
            "",
            "**Evidence:**",
            "- The reviewer, from a clean checkout,",
            "  runs the loader and sees three plugins.",
            "- A second clause.",
            "- A third clause.",
            "",
            "**Left open:** the cache layout",
            "and the file names.",
            "",
            "**Dependencies:** None",
            "**Status:** In progress",
            "**Delivered:** acme/widgets#3",
            "",
            "Free prose here.",
            "",
            "## Sequencing Rationale",
        ]
    }

    fn with_schema(mut doc: Doc, schema: &str) -> Doc {
        doc.schema = schema.into();
        doc
    }

    #[test]
    fn parse_features_reads_milestone_fields_by_extent() {
        let doc = with_schema(
            make_doc(
                milestone_body(),
                vec![("Features", 1), ("Sequencing Rationale", 23)],
            ),
            ROADMAP_V2_SCHEMA,
        );
        let f = &parse_features(&doc)[0];
        assert_eq!(f.tag, "AB1");
        assert_eq!(
            f.outcome.as_deref(),
            Some("A maintainer runs the loader and gets every plugin listed by name.")
        );
        assert_eq!(
            f.evidence.as_deref(),
            Some(
                &[
                    "The reviewer, from a clean checkout, runs the loader and sees three plugins."
                        .to_string(),
                    "A second clause.".to_string(),
                    "A third clause.".to_string(),
                ][..]
            )
        );
        assert_eq!(
            f.left_open.as_deref(),
            Some("the cache layout and the file names.")
        );
        assert_eq!(f.delivered.as_deref(), Some("acme/widgets#3"));
        assert_eq!(f.dependencies, "None");
        assert!(!f.dependencies_continued);
        assert_eq!(f.status, "In progress");
        // On a milestone roadmap the description is the free prose alone.
        assert_eq!(f.description, "Free prose here.");
    }

    #[test]
    fn parse_features_keeps_the_v1_description_unchanged() {
        let doc = make_doc(
            milestone_body(),
            vec![("Features", 1), ("Sequencing Rationale", 23)],
        );
        let f = &parse_features(&doc)[0];
        assert_eq!(
            f.description,
            "**Outcome:** A maintainer runs the loader and gets every plugin listed by name. \
             **Evidence:** - The reviewer, from a clean checkout, runs the loader and sees three plugins. \
             - A second clause. - A third clause. **Left open:** the cache layout and the file names. \
             **Delivered:** acme/widgets#3 Free prose here."
        );
        // The fields are still read on v1; only the description keeps its old shape.
        assert_eq!(f.evidence.as_ref().map(Vec::len), Some(3));
    }

    #[test]
    fn evidence_clauses_end_with_the_field() {
        let body = vec![
            "## Features",
            "### AB1: Loader",
            "**Evidence:**",
            "- Only clause.",
            "",
            "- Not a clause: it follows a blank line.",
            "**Downstream:** PLAN-loader.md",
            "**Outcome:** Ends at the next field",
            "**Downstream:** PLAN-x.md",
            "not part of the Outcome.",
        ];
        let doc = with_schema(make_doc(body, vec![("Features", 1)]), ROADMAP_V2_SCHEMA);
        let f = &parse_features(&doc)[0];
        assert_eq!(
            f.evidence.as_deref(),
            Some(&["Only clause.".to_string()][..])
        );
        assert_eq!(f.outcome.as_deref(), Some("Ends at the next field"));
        assert_eq!(f.description, "- Not a clause: it follows a blank line.");
    }

    #[test]
    fn an_evidence_line_with_no_clause_reads_empty_and_absent_reads_none() {
        let body = vec![
            "## Features",
            "### AB1: One",
            "**Evidence:**",
            "",
            "### AB2: Two",
            "**Outcome:**",
        ];
        let doc = with_schema(make_doc(body, vec![("Features", 1)]), ROADMAP_V2_SCHEMA);
        let fs = parse_features(&doc);
        assert_eq!(fs[0].evidence, Some(Vec::new()));
        assert_eq!(fs[0].outcome, None);
        assert_eq!(fs[1].evidence, None);
        assert_eq!(fs[1].outcome.as_deref(), Some(""));
    }

    #[test]
    fn a_continued_dependencies_line_is_flagged() {
        let body = vec![
            "## Features",
            "### AB1: One",
            "**Dependencies:** None",
            "### AB2: Two",
            "**Dependencies:** AB1,",
            "AB3",
            "**Status:** Not started",
        ];
        let doc = with_schema(make_doc(body, vec![("Features", 1)]), ROADMAP_V2_SCHEMA);
        let fs = parse_features(&doc);
        assert!(!fs[0].dependencies_continued);
        assert!(fs[1].dependencies_continued);
        assert_eq!(fs[1].dependencies, "AB1,");
        assert_eq!(fs[1].description, "");
    }

    #[test]
    fn a_letter_suffixed_tag_is_an_item() {
        let body = vec![
            "## Features",
            "### AB10a: Rehearsal",
            "### Feature 3: Classic",
        ];
        let fs = parse_features(&make_doc(body, vec![("Features", 1)]));
        assert_eq!(fs.len(), 2);
        assert_eq!(
            (fs[0].tag.as_str(), fs[0].label.as_str()),
            ("AB10a", "Rehearsal")
        );
        assert_eq!(fs[1].tag, "Feature 3");
        assert!(is_feature_heading("### AB10a: Rehearsal"));
        assert!(!is_feature_heading("### AB10ab: Two letters"));
        assert!(!is_feature_heading(
            "### Feature 3a: No suffix on the classic form"
        ));
    }

    #[test]
    fn a_milestone_heading_needs_a_title() {
        assert!(is_milestone_heading("### AB2: Registry"));
        assert!(is_milestone_heading("### Feature 2: Registry"));
        assert!(!is_milestone_heading("### AB2:"));
        assert!(!is_milestone_heading("### AB2:   "));
        assert!(!is_milestone_heading("### AB2:Lister"));
        assert!(!is_milestone_heading("### Feature 2:Lister"));
        assert!(!is_milestone_heading("### Stage 1 -- Runtime"));
    }

    fn tagged(tags: &[&str]) -> Vec<Feature> {
        tags.iter()
            .enumerate()
            .map(|(i, t)| Feature {
                id: i + 1,
                tag: t.to_string(),
                ..Feature::default()
            })
            .collect()
    }

    #[test]
    fn dependency_positions_resolves_every_spelling() {
        let classic = tagged(&["Feature 1", "Feature 2", "Feature 3"]);
        assert_eq!(dependency_positions("Feature 2", &classic, None), vec![2]);
        assert_eq!(
            dependency_positions("Features 1, 2 and 3", &classic, None),
            vec![1, 2, 3]
        );
        assert_eq!(dependency_positions("F2", &classic, None), vec![2]);
        assert_eq!(
            dependency_positions("None", &classic, None),
            Vec::<usize>::new()
        );
        assert_eq!(
            dependency_positions("Feature 3, Feature 3, Feature 1", &classic, None),
            vec![3, 1]
        );

        let prefixed = tagged(&["AB1", "AB2", "AB10a"]);
        assert_eq!(dependency_positions("AB1", &prefixed, None), vec![1]);
        assert_eq!(
            dependency_positions("AB10a, AB1", &prefixed, None),
            vec![3, 1]
        );
        // `Feature N` on a prefixed roadmap is the Nth item.
        assert_eq!(dependency_positions("Feature 2", &prefixed, None), vec![2]);
        // Unknown tags, out-of-range numbers and cross-repo refs name nothing.
        assert_eq!(
            dependency_positions("ZZ9, Feature 9, owner/repo#7", &prefixed, None),
            Vec::<usize>::new()
        );
        // `AB1` inside `AB10a` is not a whole token.
        assert_eq!(dependency_positions("AB10a", &prefixed, None), vec![3]);
    }

    #[test]
    fn feature_n_prefers_the_item_tagged_feature_n() {
        // A roadmap whose second item is tagged `Feature 1` (headings out of
        // order): the tag wins over the position.
        let fs = tagged(&["Feature 2", "Feature 1"]);
        assert_eq!(dependency_positions("Feature 1", &fs, None), vec![2]);
        assert_eq!(dependency_positions("Feature 2", &fs, None), vec![1]);
        assert_eq!(dependency_positions("F2", &fs, None), vec![1]);
        assert_eq!(dependency_positions("F1", &fs, None), vec![2]);
    }

    #[test]
    fn an_item_never_depends_on_itself() {
        // A parenthetical naming the item itself, in every spelling.
        let prefixed = tagged(&["AB7", "AB8", "AB9", "AB10"]);
        let deps = "AB7 (the review surface AB10 renders); AB8 + AB9";
        assert_eq!(
            dependency_positions(deps, &prefixed, Some(4)),
            vec![1, 2, 3]
        );
        assert_eq!(
            dependency_positions(deps, &prefixed, None),
            vec![1, 4, 2, 3]
        );
        let classic = tagged(&["Feature 1", "Feature 2"]);
        assert_eq!(
            dependency_positions("Feature 1 (unlike Feature 2 or F2)", &classic, Some(2)),
            vec![1]
        );
    }

    #[test]
    fn a_tag_spelled_like_the_index_alias_resolves_as_the_tag() {
        let fs = tagged(&["F2", "F1"]);
        assert_eq!(dependency_positions("F2", &fs, None), vec![1]);
    }

    #[test]
    fn an_empty_evidence_bullet_is_not_a_clause() {
        let body = vec![
            "## Features",
            "### AB1: One",
            "**Evidence:**",
            "-   ",
            "- Real.",
        ];
        let doc = with_schema(make_doc(body, vec![("Features", 1)]), ROADMAP_V2_SCHEMA);
        let f = &parse_features(&doc)[0];
        assert_eq!(f.evidence.as_deref(), Some(&["Real.".to_string()][..]));
    }
}
