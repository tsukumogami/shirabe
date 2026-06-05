//! Issues-table parsing for the Implementation Issues section.
//!
//! Locates the GFM pipe table under a doc's `## Implementation Issues`
//! heading and parses it into a [`Table`] of classified [`Row`]s. The
//! parser is total over arbitrary line input: it never panics on ragged
//! rows, unterminated sections, or missing separators. FC05 and FC06 in
//! `checks.rs` consume the parsed table; this module is profile-agnostic.

use std::sync::LazyLock;

use regex::Regex;

use crate::doc::Doc;

/// Classifies an issues-table body row.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum RowKind {
    /// A primary entity row (an Issue row for the plan profile, a Feature
    /// row for the roadmap profile).
    Entity,
    /// An italic 1-3 sentence description row that follows an entity row.
    /// First cell is `_..._`, remaining cells empty.
    Description,
    /// A child reference row used for tracks-design / tracks-plan issues.
    /// First cell starts with `^_...`, remaining cells empty.
    Child,
}

/// Distinguishes the two issues-table shapes the validator recognises.
///
/// Detected from `Table.columns`: a 4-column shape whose last column is
/// `Status` indicates the roadmap profile; any other shape (including the
/// canonical 3-column plan shape) indicates the plan profile. FC07 uses
/// the profile to select the terminality rule: strikethrough-on-done for
/// the plan profile, Status-cell value (`Done`/`Closed`) for the roadmap
/// profile.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Profile {
    Plan,
    Roadmap,
}

/// One body row of an issues table.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Row {
    /// Classifies the row.
    pub kind: RowKind,
    /// The row's primary key token, used to resolve cross-references.
    ///
    /// For [`RowKind::Entity`] in the plan profile, `key` is the `#N`
    /// issue number (e.g., `#42`). For [`RowKind::Entity`] in the roadmap
    /// profile, `key` is the feature label text from the first cell (with
    /// any markdown link syntax stripped). For [`RowKind::Description`]
    /// and [`RowKind::Child`], `key` is empty.
    pub key: String,
    /// The parsed dependency targets from the Dependencies cell of an
    /// entity row -- one entry per comma-separated link or the string
    /// "None". For non-entity rows, `deps` is empty.
    pub deps: Vec<String>,
    /// The 1-indexed absolute line number of the row in the doc.
    pub line: usize,
    /// The row's raw text including leading and trailing pipes.
    pub raw: String,
    /// True when the row is in a terminal state.
    ///
    /// For plan-profile rows: true when the original (pre-strip) first
    /// cell is wrapped in `~~...~~` strikethrough. For roadmap-profile
    /// rows: true when the Status cell value is `Done` or `Closed`
    /// (case-insensitive, trimmed). Description and Child rows are never
    /// terminal.
    pub terminal: bool,
    /// The raw Status cell value for roadmap-profile entity rows;
    /// `None` for plan-profile rows and for non-entity rows. FC07 echoes
    /// the value verbatim in the four-field class-versus-Status notice.
    pub status: Option<String>,
}

/// The parsed issues table from a single Markdown doc.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Table {
    /// The header column names in order, with surrounding whitespace
    /// trimmed and markdown stripped.
    pub columns: Vec<String>,
    /// Every body row in order (entity, description, child).
    pub rows: Vec<Row>,
    /// The 1-indexed absolute line number of the header row.
    pub header_line: usize,
    /// The detected issues-table profile. See [`Profile`] for the
    /// detection rule.
    pub profile: Profile,
}

/// Matches the Implementation Issues section heading. The validator finds
/// the table inside this section's body.
const IMPLEMENTATION_ISSUES_HEADING: &str = "## Implementation Issues";

/// Strips `~~...~~` markers so a struck-through row classifies the same
/// way as an open row.
static STRIKETHROUGH_PATTERN: LazyLock<Regex> =
    LazyLock::new(|| Regex::new(r"~~([^~]*)~~").unwrap());

/// Extracts the `#N` token from a plan-profile entity cell. Matches `#`
/// followed by one or more digits.
static ISSUE_REF_PATTERN: LazyLock<Regex> = LazyLock::new(|| Regex::new(r"#(\d+)").unwrap());

/// Locate the GFM pipe table under the Implementation Issues section of
/// `doc` and parse it into a [`Table`].
///
/// Returns `Some(table)` if a table is found. Returns `None` when the
/// section is absent, the section has no table, or the table is malformed
/// (no header / no separator row).
pub fn parse_issues_table(doc: &Doc) -> Option<Table> {
    let (start_idx, end_idx, header_line) = find_issues_table_section(doc)?;

    // Find the header row inside [start_idx, end_idx).
    let mut hdr_idx: Option<usize> = None;
    for i in start_idx..end_idx {
        let line = &doc.body[i];
        let trimmed = line.trim();
        if trimmed.is_empty() {
            continue;
        }
        if is_table_row(trimmed) {
            hdr_idx = Some(i);
            break;
        }
    }
    let hdr_idx = hdr_idx?;

    // The line immediately after the header must be a separator row
    // (`| --- | --- | ... |`). If absent, treat as no-table-found.
    let sep_idx = hdr_idx + 1;
    if sep_idx >= end_idx {
        return None;
    }
    if !is_separator_row(doc.body[sep_idx].trim()) {
        return None;
    }

    let columns = split_row(&doc.body[hdr_idx]);
    if columns.is_empty() {
        return None;
    }

    // Find the Dependencies column index by header. Missing/legacy shapes
    // that have no Dependencies column produce dep_col == None; FC05
    // reports the schema mismatch and FC06 simply finds no targets to
    // validate.
    let dep_col = columns.iter().position(|c| c == "Dependencies");

    // A roadmap-profile shape is the 4-column form ending in Status. Any
    // other shape (including the canonical 3-column plan form, legacy
    // shapes, and divergent roadmap shapes FC05 flags) classifies as Plan.
    let profile = detect_profile(&columns);
    let status_col = if matches!(profile, Profile::Roadmap) {
        columns.iter().position(|c| c == "Status")
    } else {
        None
    };

    let mut table = Table {
        columns,
        rows: Vec::new(),
        header_line,
        profile,
    };

    // Iterate body rows until we hit a blank line or the section ends.
    for i in (sep_idx + 1)..end_idx {
        let raw = &doc.body[i];
        let trimmed = raw.trim();
        if trimmed.is_empty() {
            // A blank line ends the table body.
            break;
        }
        if !is_table_row(trimmed) {
            // A non-pipe line ends the table body.
            break;
        }
        let cells = split_row(raw);
        let mut row = classify_row(&cells, dep_col, profile, status_col);
        // Absolute line = header_line offset by (i - hdr_idx).
        row.line = header_line + (i - hdr_idx);
        row.raw = doc.body[i].clone();
        table.rows.push(row);
    }

    Some(table)
}

/// Detect the issues-table profile from its column headers. A 4-column
/// table whose last column is `Status` is the roadmap profile; every
/// other shape (canonical 3-column plan, legacy 4-column plan, divergent
/// roadmap shapes) is the plan profile.
fn detect_profile(columns: &[String]) -> Profile {
    if columns.len() == 4 && columns.last().map(|s| s.as_str()) == Some("Status") {
        Profile::Roadmap
    } else {
        Profile::Plan
    }
}

/// Return the `[start, end)` body indices that bound the Implementation
/// Issues section, plus the absolute line of its heading. Returns `None`
/// if the section is absent.
fn find_issues_table_section(doc: &Doc) -> Option<(usize, usize, usize)> {
    // Section heading must appear in `doc.sections` (## level) under the
    // name "Implementation Issues".
    let heading_line = doc
        .sections
        .iter()
        .find(|sec| sec.name == "Implementation Issues")
        .map(|sec| sec.line)?;

    // Walk the body to find the heading line index and the next ## heading.
    let mut start_idx: Option<usize> = None;
    let mut end_idx = doc.body.len();
    for (i, line) in doc.body.iter().enumerate() {
        if start_idx.is_none() {
            if line.trim_end_matches([' ', '\t']) == IMPLEMENTATION_ISSUES_HEADING {
                start_idx = Some(i + 1);
            }
            continue;
        }
        // Past the heading -- watch for the next ## heading.
        if line.starts_with("## ") {
            end_idx = i;
            break;
        }
    }
    let start_idx = start_idx?;
    Some((start_idx, end_idx, heading_line))
}

/// Reports whether `trimmed` is a GFM pipe-table row -- starts with `|`
/// and contains at least one cell separator.
fn is_table_row(trimmed: &str) -> bool {
    if !trimmed.starts_with('|') {
        return false;
    }
    // A valid table row has at least two `|` characters.
    trimmed.matches('|').count() >= 2
}

/// Reports whether `trimmed` is a GFM separator row -- each cell contains
/// only dashes, colons, and whitespace.
fn is_separator_row(trimmed: &str) -> bool {
    if !is_table_row(trimmed) {
        return false;
    }
    let cells = split_row(trimmed);
    if cells.is_empty() {
        return false;
    }
    for c in &cells {
        let c = c.trim();
        if c.is_empty() {
            return false;
        }
        if !c.chars().all(|r| r == '-' || r == ':') {
            return false;
        }
    }
    true
}

/// Split a raw GFM pipe row into its cells. Surrounding pipes are removed
/// and each cell is whitespace-trimmed. Empty trailing cells from
/// `| a | | |` are preserved.
fn split_row(raw: &str) -> Vec<String> {
    let trimmed = raw.trim();
    if !trimmed.starts_with('|') {
        return Vec::new();
    }
    // Remove leading and trailing pipes.
    let trimmed = trimmed.strip_prefix('|').unwrap_or(trimmed);
    let trimmed = trimmed.strip_suffix('|').unwrap_or(trimmed);
    trimmed.split('|').map(|p| p.trim().to_string()).collect()
}

/// Inspect the cells of a body row and produce a [`Row`] with its kind,
/// key, dependency targets, and terminality populated. `dep_col` is the
/// index of the Dependencies column (`None` if absent). `profile` selects
/// the terminality rule. `status_col` is the index of the Status column
/// for the roadmap profile (`None` otherwise).
fn classify_row(
    cells: &[String],
    dep_col: Option<usize>,
    profile: Profile,
    status_col: Option<usize>,
) -> Row {
    let blank = |kind| Row {
        kind,
        key: String::new(),
        deps: Vec::new(),
        line: 0,
        raw: String::new(),
        terminal: false,
        status: None,
    };

    if cells.is_empty() {
        return blank(RowKind::Entity);
    }
    let raw_first = &cells[0];
    let first = strip_strikethrough(raw_first);

    // Child reference row: first cell starts with `^_` and remaining cells
    // are empty (after strikethrough strip).
    if first.starts_with("^_") && rest_empty(&cells[1..]) {
        return blank(RowKind::Child);
    }

    // Description row: first cell is wrapped in italic markers `_..._`
    // (single underscores) and remaining cells are empty.
    if is_italic_cell(&first) && rest_empty(&cells[1..]) {
        return blank(RowKind::Description);
    }

    // Otherwise it's an entity row.
    let mut row = blank(RowKind::Entity);
    row.key = extract_entity_key(&first);
    if let Some(dc) = dep_col {
        if dc < cells.len() {
            row.deps = extract_deps(&strip_strikethrough(&cells[dc]));
        }
    }
    match profile {
        Profile::Plan => {
            // Plan-profile terminality: original first cell wrapped in
            // `~~...~~`. We inspect the raw cell rather than the stripped
            // form so a struck-through cell is observable here.
            row.terminal = is_strikethrough_wrapped(raw_first);
        }
        Profile::Roadmap => {
            if let Some(sc) = status_col {
                if sc < cells.len() {
                    let raw_status = strip_strikethrough(&cells[sc]);
                    let trimmed = raw_status.trim().to_string();
                    row.terminal = is_terminal_roadmap_status(&trimmed);
                    if !trimmed.is_empty() {
                        row.status = Some(trimmed);
                    }
                }
            }
        }
    }
    row
}

/// Reports whether `raw` is wrapped in a `~~...~~` strikethrough that
/// covers the entire trimmed cell. A cell with leading or trailing text
/// outside the strikethrough markers is not terminal.
fn is_strikethrough_wrapped(raw: &str) -> bool {
    let t = raw.trim();
    t.starts_with("~~") && t.ends_with("~~") && t.len() >= 4
}

/// Roadmap-profile terminality rule: `Done` and `Closed` are terminal
/// (case-insensitive, trimmed). Every other Status value (including
/// `In Progress`, `Not Started`, and `needs-*` annotations) is open. The
/// rule mirrors `references/issues-table.md` for the Status column.
fn is_terminal_roadmap_status(status: &str) -> bool {
    let t = status.trim();
    t.eq_ignore_ascii_case("Done") || t.eq_ignore_ascii_case("Closed")
}

/// Parse a Dependencies cell value into a list of targets. `None`
/// (case-insensitive) and the empty string both yield an empty vec.
/// Otherwise the cell is split on commas; each token is normalized to its
/// `#N` issue token if present, else to the feature-label text inside the
/// link. Cross-repo references (`owner/repo#N`) preserve the slash so FC06
/// can recognize them as non-local and skip them.
fn extract_deps(cell: &str) -> Vec<String> {
    let c = cell.trim();
    if c.is_empty() {
        return Vec::new();
    }
    if c.eq_ignore_ascii_case("none") {
        return Vec::new();
    }
    let mut out: Vec<String> = Vec::new();
    for p in c.split(',') {
        let p = p.trim();
        if p.is_empty() {
            continue;
        }
        // A `#N` token: only normalize to `#N` if no slash precedes it in
        // the token (cross-repo refs like `owner/repo#N` keep the slash so
        // FC06 treats them as non-local).
        if let Some(m) = ISSUE_REF_PATTERN.find(p) {
            let before = &p[..m.start()];
            // Strip leading markdown-link `[`.
            let before = before.trim_start_matches('[');
            if !before.contains('/') {
                out.push(p[m.start()..m.end()].to_string());
                continue;
            }
            // Preserve the cross-repo form for non-local detection.
            out.push(p.trim().to_string());
            continue;
        }
        // Otherwise use the link text or the raw cell content.
        out.push(normalize_feature_ref(p));
    }
    out
}

/// Return the entity row's primary key from the first cell.
///
/// For a plan-profile entity row, the cell looks like `[#N: <title>](<url>)`;
/// the key is `#N`. For a roadmap-profile entity row, the cell is a feature
/// label (free text, possibly with a markdown link to a per-feature anchor);
/// the key is the normalized label.
fn extract_entity_key(cell: &str) -> String {
    let c = strip_strikethrough(cell);
    if let Some(m) = ISSUE_REF_PATTERN.find(&c) {
        return m.as_str().to_string();
    }
    normalize_feature_ref(&c)
}

/// Strip markdown link syntax to produce a stable label suitable for
/// cross-reference lookup.
fn normalize_feature_ref(s: &str) -> String {
    let s = s.trim();
    // `[label](url)` -> `label`
    if let Some(rest) = s.strip_prefix('[') {
        if let Some(end) = rest.find("](") {
            return rest[..end].trim().to_string();
        }
    }
    s.to_string()
}

/// Remove `~~..~~` markers so a struck-through cell classifies the same as
/// an open cell.
fn strip_strikethrough(s: &str) -> String {
    STRIKETHROUGH_PATTERN.replace_all(s, "$1").into_owned()
}

/// Reports whether `s` is wrapped in single underscores. The description
/// row's first cell is `_...some text..._`.
fn is_italic_cell(s: &str) -> bool {
    let s = s.trim();
    if s.len() < 2 {
        return false;
    }
    if !s.starts_with('_') || !s.ends_with('_') {
        return false;
    }
    // Reject `__text__` (bold) -- description rows use single underscores.
    if s.starts_with("__") {
        return false;
    }
    true
}

/// Reports whether every cell in `tail` is empty after strikethrough is
/// stripped.
fn rest_empty(tail: &[String]) -> bool {
    tail.iter()
        .all(|c| strip_strikethrough(c).trim().is_empty())
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::frontmatter::parse_doc_bytes;

    /// Test helper that mirrors the Go `docFromMarkdown`: parse the
    /// markdown into a `Doc` via the production parser.
    fn doc_from_markdown(md: &str) -> Doc {
        parse_doc_bytes("test.md", md.as_bytes()).expect("parse_doc_bytes failed")
    }

    // --- parse_issues_table ---

    #[test]
    fn parse_issues_table_canonical_plan_profile() {
        let doc = doc_from_markdown(
            "---\nschema: plan/v1\nstatus: Active\nexecution_mode: multi-pr\nmilestone: \"foo\"\nissue_count: 2\n---\n\n# PLAN: foo\n\n## Status\n\nActive\n\n## Implementation Issues\n\n| Issue | Dependencies | Complexity |\n|-------|--------------|------------|\n| [#1: first](https://example.com/1) | None | simple |\n| _First description._ | | |\n| [#2: second](https://example.com/2) | [#1](https://example.com/1) | testable |\n| _Second description._ | | |\n",
        );

        let table = parse_issues_table(&doc).expect("expected to find a table, got None");
        assert_eq!(table.columns, vec!["Issue", "Dependencies", "Complexity"]);
        assert_eq!(table.rows.len(), 4, "expected 4 rows (2 entity + 2 desc)");
        assert_eq!(table.rows[0].kind, RowKind::Entity);
        assert_eq!(table.rows[0].key, "#1");
        assert_eq!(table.rows[1].kind, RowKind::Description);
        assert_eq!(table.rows[2].kind, RowKind::Entity);
        assert_eq!(table.rows[2].key, "#2");
        assert_eq!(table.rows[2].deps, vec!["#1"]);
    }

    #[test]
    fn parse_issues_table_canonical_roadmap_profile() {
        let doc = doc_from_markdown(
            "---\nschema: roadmap/v1\nstatus: Active\ntheme: |\n  theme\nscope: |\n  scope\n---\n\n# ROADMAP: foo\n\n## Status\n\nActive\n\n## Implementation Issues\n\n| Feature | Issues | Dependencies | Status |\n|---------|--------|--------------|--------|\n| Feature 1: alpha | [#10](https://example.com/10) | None | In Progress |\n| _Alpha description._ | | | |\n| Feature 2: beta | [#11](https://example.com/11) | Feature 1: alpha | Not Started |\n| _Beta description._ | | | |\n",
        );

        let table = parse_issues_table(&doc).expect("expected to find a table, got None");
        assert_eq!(
            table.columns,
            vec!["Feature", "Issues", "Dependencies", "Status"]
        );
        assert_eq!(table.rows.len(), 4);
        assert_eq!(table.rows[0].kind, RowKind::Entity);
        assert_eq!(table.rows[0].key, "Feature 1: alpha");
        assert_eq!(table.rows[2].key, "Feature 2: beta");
        assert_eq!(table.rows[2].deps, vec!["Feature 1: alpha"]);
    }

    #[test]
    fn parse_issues_table_strikethrough_on_done_classifies() {
        let doc = doc_from_markdown(
            "---\nschema: plan/v1\nstatus: Active\nexecution_mode: multi-pr\nmilestone: \"foo\"\nissue_count: 1\n---\n\n# PLAN: foo\n\n## Status\n\nActive\n\n## Implementation Issues\n\n| Issue | Dependencies | Complexity |\n|-------|--------------|------------|\n| ~~[#1: done item](https://example.com/1)~~ | ~~None~~ | ~~simple~~ |\n| ~~_A struck-through description._~~ | | |\n",
        );

        let table = parse_issues_table(&doc).expect("expected to find a table");
        assert_eq!(table.rows.len(), 2);
        assert_eq!(
            table.rows[0].kind,
            RowKind::Entity,
            "struck entity row should classify as Entity"
        );
        assert_eq!(
            table.rows[0].key, "#1",
            "expected key '#1' (stripped from strikethrough)"
        );
        assert_eq!(
            table.rows[1].kind,
            RowKind::Description,
            "struck description row should classify as Description"
        );
    }

    #[test]
    fn parse_issues_table_child_reference_row() {
        let doc = doc_from_markdown(
            "---\nschema: plan/v1\nstatus: Active\nexecution_mode: multi-pr\nmilestone: \"foo\"\nissue_count: 1\n---\n\n# PLAN: foo\n\n## Status\n\nActive\n\n## Implementation Issues\n\n| Issue | Dependencies | Complexity |\n|-------|--------------|------------|\n| [#1: tracks-design item](https://example.com/1) | None | simple |\n| ^_Child: [DESIGN-foo.md](./DESIGN-foo.md)_ | | | |\n| _Description._ | | |\n",
        );

        let table = parse_issues_table(&doc).expect("expected to find a table");
        assert_eq!(table.rows.len(), 3);
        assert_eq!(
            table.rows[1].kind,
            RowKind::Child,
            "middle row should be Child"
        );
    }

    #[test]
    fn parse_issues_table_no_section_returns_none() {
        let doc = doc_from_markdown(
            "---\nschema: plan/v1\nstatus: Active\n---\n\n# PLAN: foo\n\n## Status\n\nActive\n\n## Other Section\n\nSome text.\n",
        );

        assert!(
            parse_issues_table(&doc).is_none(),
            "expected None when no Implementation Issues section"
        );
    }

    #[test]
    fn parse_issues_table_empty_section_returns_none() {
        let doc = doc_from_markdown(
            "---\nschema: roadmap/v1\nstatus: Draft\n---\n\n# ROADMAP: foo\n\n## Status\n\nDraft\n\n## Implementation Issues\n\n<!-- Populated by /plan during decomposition. Do not fill manually. -->\n\n## Dependency Graph\n",
        );

        assert!(
            parse_issues_table(&doc).is_none(),
            "expected None when section is empty"
        );
    }

    #[test]
    fn parse_issues_table_no_separator_row_returns_none() {
        // A table with a header row but no separator (`| --- | --- |`) is
        // malformed and should be treated as no-table-found.
        let doc = doc_from_markdown(
            "---\nschema: plan/v1\nstatus: Active\n---\n\n## Implementation Issues\n\n| Issue | Dependencies | Complexity |\n| [#1: only row](https://example.com/1) | None | simple |\n",
        );

        assert!(
            parse_issues_table(&doc).is_none(),
            "expected None when separator row is missing"
        );
    }

    #[test]
    fn parse_issues_table_ragged_rows_do_not_panic() {
        // Defensive: a row with fewer cells than the header must not panic.
        let doc = doc_from_markdown(
            "---\nschema: plan/v1\nstatus: Active\n---\n\n## Implementation Issues\n\n| Issue | Dependencies | Complexity |\n|-------|--------------|------------|\n| [#1: ragged](https://example.com/1) |\n| _Description._ |\n",
        );

        // Should not panic; if it parses, fine; if not, fine.
        let _ = parse_issues_table(&doc);
    }

    #[test]
    fn parse_issues_table_divergent_roadmap_strategic_pipeline() {
        // The ROADMAP-strategic-pipeline.md committed shape.
        // parse_issues_table should return the table (parsing is
        // profile-agnostic); FC05 then flags it.
        let doc = doc_from_markdown(
            "---\nschema: roadmap/v1\nstatus: Active\n---\n\n## Implementation Issues\n\n| Feature | Status | Downstream Artifact |\n|---------|--------|---------------------|\n| Feature 1: VISION Artifact Type | Done | DESIGN-vision-artifact-type.md (Current) |\n| Feature 2: Roadmap Creation Skill | Done | PRD-roadmap-skill.md (Done), DESIGN-roadmap-creation-skill.md (Current) |\n",
        );

        let table = parse_issues_table(&doc).expect("expected to find the divergent table");
        assert_eq!(
            table.columns,
            vec!["Feature", "Status", "Downstream Artifact"]
        );
    }

    // --- Defensive parsing ---

    #[test]
    fn parse_issues_table_no_section_in_empty_doc() {
        let doc = doc_from_markdown("");
        assert!(
            parse_issues_table(&doc).is_none(),
            "expected None on empty doc"
        );
    }

    #[test]
    fn parse_issues_table_unterminated_section_does_not_panic() {
        // Section heading with no body, no closing section.
        let doc = doc_from_markdown("## Implementation Issues\n");
        let _ = parse_issues_table(&doc);
    }

    // --- Terminality, Status, Profile (FC07 prerequisites) ---

    #[test]
    fn profile_detected_as_plan_for_canonical_three_column_shape() {
        let doc = doc_from_markdown(
            "---\nschema: plan/v1\nstatus: Active\nexecution_mode: multi-pr\nmilestone: \"foo\"\nissue_count: 1\n---\n\n## Implementation Issues\n\n| Issue | Dependencies | Complexity |\n|-------|--------------|------------|\n| [#1: alpha](https://example.com/1) | None | simple |\n| _Alpha._ | | |\n",
        );
        let table = parse_issues_table(&doc).expect("table parses");
        assert_eq!(table.profile, Profile::Plan);
    }

    #[test]
    fn profile_detected_as_roadmap_for_four_column_status_shape() {
        let doc = doc_from_markdown(
            "---\nschema: roadmap/v1\nstatus: Active\n---\n\n## Implementation Issues\n\n| Feature | Issues | Dependencies | Status |\n|---------|--------|--------------|--------|\n| Feature 1: alpha | [#10](https://example.com/10) | None | Done |\n| _Alpha._ | | | |\n",
        );
        let table = parse_issues_table(&doc).expect("table parses");
        assert_eq!(table.profile, Profile::Roadmap);
    }

    #[test]
    fn profile_falls_back_to_plan_for_divergent_roadmap_shape() {
        let doc = doc_from_markdown(
            "---\nschema: roadmap/v1\nstatus: Active\n---\n\n## Implementation Issues\n\n| Feature | Status | Downstream Artifact |\n|---------|--------|---------------------|\n| Feature 1: alpha | Done | DESIGN-foo.md |\n",
        );
        let table = parse_issues_table(&doc).expect("table parses");
        assert_eq!(
            table.profile,
            Profile::Plan,
            "3-column shape ending in non-Status falls back to Plan"
        );
    }

    #[test]
    fn plan_profile_strikethrough_sets_terminal() {
        let doc = doc_from_markdown(
            "---\nschema: plan/v1\nstatus: Active\nexecution_mode: multi-pr\nmilestone: \"foo\"\nissue_count: 1\n---\n\n## Implementation Issues\n\n| Issue | Dependencies | Complexity |\n|-------|--------------|------------|\n| ~~[#1: done item](https://example.com/1)~~ | ~~None~~ | ~~simple~~ |\n| ~~_Description._~~ | | |\n",
        );
        let table = parse_issues_table(&doc).expect("table parses");
        assert!(table.rows[0].terminal, "struck entity row is terminal");
        assert_eq!(table.rows[0].status, None);
    }

    #[test]
    fn plan_profile_no_strikethrough_means_open() {
        let doc = doc_from_markdown(
            "---\nschema: plan/v1\nstatus: Active\nexecution_mode: multi-pr\nmilestone: \"foo\"\nissue_count: 1\n---\n\n## Implementation Issues\n\n| Issue | Dependencies | Complexity |\n|-------|--------------|------------|\n| [#1: open item](https://example.com/1) | None | simple |\n| _Description._ | | |\n",
        );
        let table = parse_issues_table(&doc).expect("table parses");
        assert!(!table.rows[0].terminal, "non-struck entity row is open");
    }

    #[test]
    fn roadmap_profile_status_done_is_terminal() {
        let doc = doc_from_markdown(
            "---\nschema: roadmap/v1\nstatus: Active\n---\n\n## Implementation Issues\n\n| Feature | Issues | Dependencies | Status |\n|---------|--------|--------------|--------|\n| Feature 1: alpha | [#10](https://example.com/10) | None | Done |\n| _Alpha._ | | | |\n",
        );
        let table = parse_issues_table(&doc).expect("table parses");
        assert!(table.rows[0].terminal);
        assert_eq!(table.rows[0].status.as_deref(), Some("Done"));
    }

    #[test]
    fn roadmap_profile_status_closed_is_terminal() {
        let doc = doc_from_markdown(
            "---\nschema: roadmap/v1\nstatus: Active\n---\n\n## Implementation Issues\n\n| Feature | Issues | Dependencies | Status |\n|---------|--------|--------------|--------|\n| Feature 1: alpha | [#10](https://example.com/10) | None | Closed |\n| _Alpha._ | | | |\n",
        );
        let table = parse_issues_table(&doc).expect("table parses");
        assert!(table.rows[0].terminal);
        assert_eq!(table.rows[0].status.as_deref(), Some("Closed"));
    }

    #[test]
    fn roadmap_profile_status_in_progress_is_open() {
        let doc = doc_from_markdown(
            "---\nschema: roadmap/v1\nstatus: Active\n---\n\n## Implementation Issues\n\n| Feature | Issues | Dependencies | Status |\n|---------|--------|--------------|--------|\n| Feature 1: alpha | [#10](https://example.com/10) | None | In Progress |\n| _Alpha._ | | | |\n",
        );
        let table = parse_issues_table(&doc).expect("table parses");
        assert!(!table.rows[0].terminal);
        assert_eq!(table.rows[0].status.as_deref(), Some("In Progress"));
    }

    #[test]
    fn roadmap_profile_status_not_started_is_open() {
        let doc = doc_from_markdown(
            "---\nschema: roadmap/v1\nstatus: Active\n---\n\n## Implementation Issues\n\n| Feature | Issues | Dependencies | Status |\n|---------|--------|--------------|--------|\n| Feature 1: alpha | [#10](https://example.com/10) | None | Not Started |\n| _Alpha._ | | | |\n",
        );
        let table = parse_issues_table(&doc).expect("table parses");
        assert!(!table.rows[0].terminal);
        assert_eq!(table.rows[0].status.as_deref(), Some("Not Started"));
    }

    #[test]
    fn roadmap_profile_needs_annotation_counts_as_open() {
        let doc = doc_from_markdown(
            "---\nschema: roadmap/v1\nstatus: Active\n---\n\n## Implementation Issues\n\n| Feature | Issues | Dependencies | Status |\n|---------|--------|--------------|--------|\n| Feature 1: alpha | [#10](https://example.com/10) | None | needs-design |\n| _Alpha._ | | | |\n",
        );
        let table = parse_issues_table(&doc).expect("table parses");
        assert!(!table.rows[0].terminal);
        assert_eq!(table.rows[0].status.as_deref(), Some("needs-design"));
    }

    #[test]
    fn description_row_is_never_terminal() {
        let doc = doc_from_markdown(
            "---\nschema: plan/v1\nstatus: Active\nexecution_mode: multi-pr\nmilestone: \"foo\"\nissue_count: 1\n---\n\n## Implementation Issues\n\n| Issue | Dependencies | Complexity |\n|-------|--------------|------------|\n| ~~[#1: done](https://example.com/1)~~ | ~~None~~ | ~~simple~~ |\n| _Description._ | | |\n",
        );
        let table = parse_issues_table(&doc).expect("table parses");
        assert_eq!(table.rows[1].kind, RowKind::Description);
        assert!(!table.rows[1].terminal);
        assert_eq!(table.rows[1].status, None);
    }
}
