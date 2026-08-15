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
pub(crate) fn split_row(raw: &str) -> Vec<String> {
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

/// Reports whether `text` can serve as an issues-table key without the
/// validator reading it as something else.
///
/// FC06 does not compare cell text. It compares [`extract_entity_key`]'s
/// output for a key cell against [`extract_deps`]'s output for a dependency
/// token, and those two apply *different* normalizations to the same string:
/// an `ISSUE_REF_PATTERN` match anywhere in a key cell replaces the whole key
/// with `#N`, a `[label](target)` form is unwrapped to `label`, and a
/// delivered row's key cell is strikethrough-wrapped before either runs while
/// the dependency token naming it is not. A renderer that emits author text as
/// a key therefore cannot decide safety from a character blacklist -- a label
/// containing `~~`, `#12`, or `](` passes any list a reader would write and
/// still produces an error-level finding.
///
/// So the question this answers is a fixpoint one: are both normalizations the
/// identity on this text, bare and strikethrough-wrapped? Commas and pipes are
/// rejected up front because they split the row and the dependency cell before
/// normalization ever runs, and control characters because they can rewrite
/// the rendered line.
///
/// This is a predicate for renderers, not a validation check: nothing new
/// fires during `shirabe validate`. It lives here so it uses the same
/// normalizers the checks do and cannot drift from them.
pub fn is_stable_table_key(text: &str) -> bool {
    let t = text.trim();
    if t.is_empty() {
        return false;
    }
    if t.contains(',') || t.contains('|') {
        return false;
    }
    if t.chars().any(char::is_control) {
        return false;
    }
    if extract_entity_key(t) != t {
        return false;
    }
    if extract_entity_key(&format!("~~{}~~", t)) != t {
        return false;
    }
    extract_deps(t) == vec![t.to_string()]
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
pub(crate) fn strip_strikethrough(s: &str) -> String {
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

// ---------------------------------------------------------------------------
// Issue Outlines parser -- the single reader of `## Issue Outlines`
// ---------------------------------------------------------------------------
//
// One walk serves every consumer of the section: FC14 and FC17 in
// `checks.rs`, L06 in `lifecycle.rs`, and the `plan outlines` CLI
// subcommand that `skills/plan/scripts/plan-to-tasks.sh` reads. Before
// this module was collapsed there were three implementations with
// different rules, and a PLAN could validate clean and then extract to a
// task graph with none of its declared edges -- see
// `docs/designs/DESIGN-issue-outlines-one-parser.md` for the eight
// divergences and the decisions that resolved them.
//
// Where the old readers disagreed, the rule kept is the one the task
// extractor used, because that reader decided what actually got built.

/// A `###` heading inside `## Issue Outlines` that is neither a canonical
/// `### Issue <N>: <title>` outline heading nor the `### Dependencies`
/// sub-heading.
///
/// Recorded rather than silently accepted or silently dropped: it is not a
/// block boundary (matching the extractor, whose behavior is the target
/// where the readers disagreed), so a consumer that wants to report the
/// shape needs it enumerated somewhere. FC14 reports each one at notice
/// level -- the heading mismatch already fails closed at extraction, so an
/// error here would stop a run that was about to stop anyway.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct NonconformingHeading {
    /// The heading text with the leading `### ` stripped, verbatim.
    pub text: String,
    /// 1-indexed absolute line number of the heading.
    pub line: usize,
}

/// A parsed outline block from a single-pr plan's `## Issue Outlines`
/// section.
///
/// Each block corresponds to one canonical `### Issue <N>: <title>`
/// heading. The parser is total over arbitrary input: a missing field
/// surfaces as `false`, `None`, or an empty `Vec` rather than a parse
/// failure, so consumers decide what to refuse. Refusing is deliberately
/// not the parser's job -- it has consumers with different severities for
/// the same defect.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct OutlineBlock {
    /// The outline's heading text with `### ` stripped, captured verbatim
    /// (e.g. `Issue 1: feat(validate): extend FormatSpec`). Findings name
    /// the outline by this key, and `OutlineAc::outline_key` matches it.
    pub key: String,
    /// The issue number parsed from the heading.
    ///
    /// Dependency resolution keys on this, NOT on the block's position in
    /// the section. The two agree for a document numbered 1..N in order and
    /// diverge for anything else, and the heading is what the author wrote.
    pub number: u32,
    /// The title parsed from the heading (everything after `Issue <N>: `).
    pub title: String,
    /// 1-indexed absolute line number of the outline's `###` heading.
    pub line: usize,
    /// Whether the block declared a `**Goal**:` line.
    pub goal_declared: bool,
    /// Whether the block declared an `**Acceptance Criteria**:` label.
    ///
    /// Separate from `acceptance_criteria` being non-empty: a block can
    /// declare the label and carry no canonical checkbox under it. FC14
    /// asks only about the label.
    pub acceptance_criteria_declared: bool,
    /// The canonical `- [ ]` / `- [x]` / `- [X]` checkboxes under the
    /// block's `**Acceptance Criteria**:` label. Consumed by L06.
    pub acceptance_criteria: Vec<OutlineAc>,
    /// Whether the block declared a `**Dependencies**:` line or a
    /// `### Dependencies` sub-heading. Distinguishes a missing declaration
    /// from a declared-but-empty one.
    pub dependencies_declared: bool,
    /// Whether the dependency declaration carries the literal `None`, with
    /// or without a trailing period. The contract's own example writes
    /// `**Dependencies**: None.`, so the period is canonical rather than
    /// sloppy.
    pub dependencies_none: bool,
    /// Sibling outline numbers this block waits on, in written order,
    /// de-duplicated. Every entry names a block that exists in this
    /// section.
    pub waits_on: Vec<u32>,
    /// Dependency text that named no sibling outline, verbatim, in written
    /// order. Covers both an `Issue N` reference to a number no outline
    /// declares and a token in a shape no reader recognizes (a bare
    /// number, a `#N` GitHub reference). The extractor used to drop the
    /// second kind silently, which is the defect this field exists to
    /// surface.
    pub unresolved_dependencies: Vec<String>,
    /// The `**Type**:` annotation, lowercased, when declared.
    pub issue_type: Option<String>,
    /// The backtick-quoted tokens on the block's `**Files**:` line, with
    /// the backticks stripped.
    pub files: Vec<String>,
}

/// The parsed `## Issue Outlines` section.
#[derive(Debug, Clone, PartialEq, Eq, Default)]
pub struct OutlineSection {
    /// One entry per canonical `### Issue <N>: <title>` heading, in
    /// document order.
    pub blocks: Vec<OutlineBlock>,
    /// `###` headings inside the section that opened no block.
    pub nonconforming_headings: Vec<NonconformingHeading>,
}

/// A single acceptance criterion parsed from an outline block.
///
/// Each `OutlineAc` corresponds to one canonical `- [ ]` / `- [x]` /
/// `- [X]` checkbox line inside a block's `**Acceptance Criteria**:`
/// bullet list. Non-canonical bullet shapes (a bare `- `, an indented
/// sub-bullet, an AC written as a bare sentence) are dropped per the
/// strict-tolerance contract in DESIGN-cascade-outline-ac-completeness
/// Decision 3, and dropping one does not end the bullet list.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct OutlineAc {
    /// The owning block's heading text, matching `OutlineBlock::key`.
    pub outline_key: String,
    /// The checkbox line with its `- [ ]` / `- [x]` / `- [X]` marker
    /// stripped. Trailing whitespace is preserved.
    pub ac_text: String,
    /// Whether the box is ticked.
    pub ticked: bool,
    /// 1-indexed absolute line number of the checkbox line.
    pub line: usize,
}

static OUTLINE_HEADING_RE: LazyLock<Regex> =
    LazyLock::new(|| Regex::new(r"^Issue\s+(\d+):\s*(.+)$").unwrap());

static ISSUE_REF_RE: LazyLock<Regex> = LazyLock::new(|| Regex::new(r"Issue\s+(\d+)").unwrap());

static PLACEHOLDER_RE: LazyLock<Regex> = LazyLock::new(|| Regex::new(r"<<ISSUE:(\d+)>>").unwrap());

static BACKTICKED_RE: LazyLock<Regex> = LazyLock::new(|| Regex::new(r"`([^`]*)`").unwrap());

static TYPE_RE: LazyLock<Regex> =
    LazyLock::new(|| Regex::new(r"\*\*Type\*\*:\s*([a-zA-Z]+)").unwrap());

/// Which multi-line field, if any, the walk is currently accumulating.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum Accumulating {
    Nothing,
    /// Inside an `**Acceptance Criteria**:` bullet list.
    AcceptanceCriteria,
    /// Inside a `### Dependencies` sub-section.
    Dependencies,
}

/// Per-block state during stage one, before dependencies are resolved.
struct PartialBlock {
    key: String,
    number: u32,
    title: String,
    line: usize,
    goal_declared: bool,
    acceptance_criteria_declared: bool,
    acceptance_criteria: Vec<OutlineAc>,
    dependencies_declared: bool,
    dependencies_raw: String,
    issue_type: Option<String>,
    files: Vec<String>,
}

/// Locate the `## Issue Outlines` section and parse it.
///
/// Returns an empty section when the heading is absent. Two stages: the
/// first collects blocks, fields, and non-conforming headings; the second
/// resolves dependency references, which cannot happen during the first
/// because a block may name a sibling that appears later.
pub fn parse_issue_outlines(doc: &Doc) -> OutlineSection {
    let (start, end) = match locate_section(doc) {
        Some(bounds) => bounds,
        None => return OutlineSection::default(),
    };

    let mut partials: Vec<PartialBlock> = Vec::new();
    let mut nonconforming: Vec<NonconformingHeading> = Vec::new();
    let mut accumulating = Accumulating::Nothing;

    for (offset, raw_line) in doc.body[start..end].iter().enumerate() {
        let absolute_line = start + offset + 1; // 1-indexed
        let trimmed = raw_line.trim();

        if let Some(rest) = trimmed.strip_prefix("### ") {
            accumulating = Accumulating::Nothing;
            if let Some(caps) = OUTLINE_HEADING_RE.captures(rest) {
                // A canonical outline heading. The only thing that opens a
                // block -- the extractor's rule, kept because it decides
                // what gets built.
                let number: u32 = match caps[1].parse() {
                    Ok(n) => n,
                    // A number too large for u32 is not an outline the
                    // extractor could reference either.
                    Err(_) => {
                        nonconforming.push(NonconformingHeading {
                            text: rest.to_string(),
                            line: absolute_line,
                        });
                        continue;
                    }
                };
                partials.push(PartialBlock {
                    key: rest.to_string(),
                    number,
                    title: caps[2].trim().to_string(),
                    line: absolute_line,
                    goal_declared: false,
                    acceptance_criteria_declared: false,
                    acceptance_criteria: Vec::new(),
                    dependencies_declared: false,
                    dependencies_raw: String::new(),
                    issue_type: None,
                    files: Vec::new(),
                });
            } else if is_dependencies_heading(rest) && !partials.is_empty() {
                // A dependencies sub-section of the block already open.
                accumulating = Accumulating::Dependencies;
                if let Some(block) = partials.last_mut() {
                    block.dependencies_declared = true;
                }
            } else {
                nonconforming.push(NonconformingHeading {
                    text: rest.to_string(),
                    line: absolute_line,
                });
            }
            continue;
        }

        // Lines before the first canonical heading belong to no block.
        let block = match partials.last_mut() {
            Some(b) => b,
            None => continue,
        };

        if strip_label(trimmed, "**Goal**:").is_some() {
            block.goal_declared = true;
            accumulating = Accumulating::Nothing;
            continue;
        }

        if strip_label(trimmed, "**Acceptance Criteria**:").is_some() {
            block.acceptance_criteria_declared = true;
            accumulating = Accumulating::AcceptanceCriteria;
            continue;
        }

        // Both colon placements parse identically (#156): the canonical
        // `**Dependencies**:` and the `**Dependencies:**` form that used to
        // be dropped silently.
        if let Some(rest) = strip_dependencies_label(trimmed) {
            block.dependencies_declared = true;
            let value = rest.trim().trim_end_matches('.');
            append_dependency_text(&mut block.dependencies_raw, value);
            accumulating = Accumulating::Nothing;
            continue;
        }

        if let Some(caps) = TYPE_RE.captures(trimmed) {
            block.issue_type = Some(caps[1].to_lowercase());
            accumulating = Accumulating::Nothing;
            continue;
        }

        if trimmed.contains("**Files**:") {
            block.files = BACKTICKED_RE
                .captures_iter(trimmed)
                .map(|c| c[1].to_string())
                .filter(|t| !t.is_empty())
                .collect();
            accumulating = Accumulating::Nothing;
            continue;
        }

        match accumulating {
            Accumulating::Dependencies => {
                if trimmed.is_empty() {
                    continue;
                }
                if trimmed == "---" {
                    accumulating = Accumulating::Nothing;
                    continue;
                }
                append_dependency_text(&mut block.dependencies_raw, trimmed);
            }
            Accumulating::AcceptanceCriteria => {
                // Strict tolerance: only the three canonical checkbox
                // shapes count, and a non-canonical bullet is dropped
                // WITHOUT ending the list, so a canonical sibling after it
                // still counts.
                if let Some((ticked, text)) = strip_ac_checkbox(trimmed) {
                    block.acceptance_criteria.push(OutlineAc {
                        outline_key: block.key.clone(),
                        ac_text: text.to_string(),
                        ticked,
                        line: absolute_line,
                    });
                }
            }
            Accumulating::Nothing => {}
        }
    }

    resolve(partials, nonconforming)
}

/// Flatten every block's acceptance criteria into one list, in document
/// order.
///
/// A projection over [`parse_issue_outlines`], not a second parse: L06 wants
/// the section's criteria as a flat sequence and has no use for the blocks
/// they came from beyond each one's key, which `OutlineAc` already carries.
pub fn parse_outline_acs(doc: &Doc) -> Vec<OutlineAc> {
    parse_issue_outlines(doc)
        .blocks
        .into_iter()
        .flat_map(|b| b.acceptance_criteria)
        .collect()
}

/// Resolve each block's dependency text into sibling numbers and leftovers.
fn resolve(
    partials: Vec<PartialBlock>,
    nonconforming: Vec<NonconformingHeading>,
) -> OutlineSection {
    let known: Vec<u32> = partials.iter().map(|b| b.number).collect();

    let blocks = partials
        .into_iter()
        .map(|p| {
            let (dependencies_none, waits_on, unresolved_dependencies) =
                resolve_dependencies(&p.dependencies_raw, &known);
            OutlineBlock {
                key: p.key,
                number: p.number,
                title: p.title,
                line: p.line,
                goal_declared: p.goal_declared,
                acceptance_criteria_declared: p.acceptance_criteria_declared,
                acceptance_criteria: p.acceptance_criteria,
                dependencies_declared: p.dependencies_declared,
                dependencies_none,
                waits_on,
                unresolved_dependencies,
                issue_type: p.issue_type,
                files: p.files,
            }
        })
        .collect();

    OutlineSection {
        blocks,
        nonconforming_headings: nonconforming,
    }
}

/// Split one block's dependency text into
/// `(is_none, resolved_numbers, unresolved_text)`.
fn resolve_dependencies(raw: &str, known: &[u32]) -> (bool, Vec<u32>, Vec<String>) {
    let value = raw.trim().trim_end_matches('.').trim();
    if value.is_empty() {
        return (false, Vec::new(), Vec::new());
    }
    // The trailing period is stripped BEFORE the `None` test, which is what
    // makes the contract's own `**Dependencies**: None.` example resolve as
    // an intentional absence instead of an unresolved token named `None`.
    if value.eq_ignore_ascii_case("None") {
        return (true, Vec::new(), Vec::new());
    }

    // `<<ISSUE:N>>` is an alternative spelling of `Issue N`, so normalize
    // it away and resolve one shape.
    let normalized = PLACEHOLDER_RE.replace_all(value, "Issue $1").to_string();

    let mut waits_on: Vec<u32> = Vec::new();
    let mut unresolved: Vec<String> = Vec::new();

    for caps in ISSUE_REF_RE.captures_iter(&normalized) {
        let n: u32 = match caps[1].parse() {
            Ok(n) => n,
            Err(_) => {
                unresolved.push(caps[0].to_string());
                continue;
            }
        };
        if known.contains(&n) {
            if !waits_on.contains(&n) {
                waits_on.push(n);
            }
        } else {
            let token = caps[0].to_string();
            if !unresolved.contains(&token) {
                unresolved.push(token);
            }
        }
    }

    // Whatever is left once the recognized references and the connecting
    // words are removed was meant to name a dependency and does not. The
    // extractor used to drop this residue without a word.
    let residue = ISSUE_REF_RE.replace_all(&normalized, "").to_string();
    for token in residue
        .replace("Blocked by", ",")
        .replace("blocked by", ",")
        .split(',')
    {
        let token = token.trim().trim_end_matches('.').trim();
        if token.is_empty() || token.eq_ignore_ascii_case("and") {
            continue;
        }
        let owned = token.to_string();
        if !unresolved.contains(&owned) {
            unresolved.push(owned);
        }
    }

    (false, waits_on, unresolved)
}

/// Append a fragment to a block's accumulating dependency text.
fn append_dependency_text(target: &mut String, fragment: &str) {
    if fragment.is_empty() {
        return;
    }
    if !target.is_empty() {
        target.push_str(", ");
    }
    target.push_str(fragment);
}

/// Locate `## Issue Outlines` and return its `[start, end)` body bounds.
///
/// The section ends at the next `## ` heading at the same level; `###`
/// headings stay inside.
fn locate_section(doc: &Doc) -> Option<(usize, usize)> {
    let start = doc
        .body
        .iter()
        .position(|line| line.trim() == "## Issue Outlines")?
        + 1;

    let end = doc.body[start..]
        .iter()
        .position(|line| {
            let t = line.trim_start();
            t.starts_with("## ") && !t.starts_with("### ")
        })
        .map(|offset| start + offset)
        .unwrap_or(doc.body.len());

    Some((start, end))
}

/// Reports whether a `###` heading's text is the `Dependencies`
/// sub-heading.
fn is_dependencies_heading(rest: &str) -> bool {
    let rest = rest.trim_end();
    rest == "Dependencies" || rest.starts_with("Dependencies ")
}

/// Strip a `**Label**:` prefix, returning the trimmed remainder on a match.
fn strip_label<'a>(line: &'a str, label: &str) -> Option<&'a str> {
    Some(line.strip_prefix(label)?.trim_start())
}

/// Strip either dependencies-label spelling: the canonical
/// `**Dependencies**:` or the `**Dependencies:**` form with the colon
/// inside the bold.
fn strip_dependencies_label(line: &str) -> Option<&str> {
    for label in ["**Dependencies**:", "**Dependencies:**"] {
        if let Some(rest) = line.strip_prefix(label) {
            return Some(rest.trim_start());
        }
    }
    None
}

/// Strip a canonical acceptance-criteria checkbox marker, returning
/// `(ticked, text)`.
fn strip_ac_checkbox(line: &str) -> Option<(bool, &str)> {
    for (marker, ticked) in [("- [ ] ", false), ("- [x] ", true), ("- [X] ", true)] {
        if let Some(rest) = line.strip_prefix(marker) {
            return Some((ticked, rest));
        }
    }
    None
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
    fn is_stable_table_key_accepts_ordinary_labels() {
        assert!(is_stable_table_key("Foundation layer"));
        assert!(is_stable_table_key("A1 — Establish the baseline"));
        // Parentheses and backticks are only meaningful to the normalizers in
        // combination, so an ordinary label carrying them is still stable.
        assert!(is_stable_table_key("Retire the shim (finally)"));
        assert!(is_stable_table_key(
            "Safe; rm -rf /tmp/foo && echo HIJACKED"
        ));
    }

    #[test]
    fn is_stable_table_key_rejects_delimiters_and_empties() {
        assert!(!is_stable_table_key(""));
        assert!(!is_stable_table_key("   "));
        // A comma splits the dependency cell into tokens that name no row.
        assert!(!is_stable_table_key("Establish, then act"));
        // A pipe splits the markdown row itself.
        assert!(!is_stable_table_key("Read a | b"));
        // A control character can rewrite the rendered line.
        assert!(!is_stable_table_key("Retire\u{1b}[31m the shim"));
        assert!(!is_stable_table_key("Retire\rthe shim"));
    }

    #[test]
    fn is_stable_table_key_rejects_text_the_normalizers_rewrite() {
        // An issue reference anywhere in a key cell replaces the whole key,
        // so two features mentioning #123 would collapse to one key.
        assert!(!is_stable_table_key("Retire #123 shim"));
        // A markdown link is unwrapped to its text, so two labels differing
        // only in target become one key.
        assert!(!is_stable_table_key("[Cache](#anchor)"));
        // A `~~` run in the label collapses asymmetrically: the key cell is
        // strikethrough-wrapped for a delivered feature and the dependency
        // token naming it is not.
        assert!(!is_stable_table_key("a~~b"));
        assert!(!is_stable_table_key("~~struck~~"));
    }

    #[test]
    fn is_stable_table_key_agrees_with_the_normalizers_it_wraps() {
        // The guarantee the predicate exists to make: for accepted text, the
        // key a row renders and the token a dependency cell renders normalize
        // to the same value -- which is what FC06 compares.
        for label in ["Foundation layer", "A1 — Establish the baseline", "Metrics"] {
            assert!(is_stable_table_key(label));
            assert_eq!(extract_entity_key(label), extract_deps(label)[0]);
            assert_eq!(
                extract_entity_key(&format!("~~{}~~", label)),
                extract_deps(label)[0]
            );
        }
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

    // --- parse_issue_outlines: the single walk ---

    #[test]
    fn outlines_absent_section_is_empty() {
        let doc = doc_from_markdown("---\nschema: plan/v1\nstatus: Draft\nexecution_mode: single-pr\nmilestone: \"x\"\nissue_count: 0\n---\n\n## Status\n\nDraft\n");
        let section = parse_issue_outlines(&doc);
        assert!(section.blocks.is_empty());
        assert!(section.nonconforming_headings.is_empty());
    }

    #[test]
    fn outlines_heading_supplies_number_and_title() {
        let doc = single_pr_plan(
            "## Issue Outlines\n\n### Issue 7: feat(cli): add the thing\n\n**Goal**: g.\n\n**Dependencies**: None\n",
        );
        let section = parse_issue_outlines(&doc);
        assert_eq!(section.blocks.len(), 1);
        assert_eq!(section.blocks[0].number, 7);
        assert_eq!(section.blocks[0].title, "feat(cli): add the thing");
        assert_eq!(section.blocks[0].key, "Issue 7: feat(cli): add the thing");
    }

    #[test]
    fn outlines_noncanonical_heading_opens_no_block_and_is_recorded() {
        let doc = single_pr_plan(
            "## Issue Outlines\n\n### 4. do the thing\n\n**Goal**: g.\n\n**Dependencies**: None\n",
        );
        let section = parse_issue_outlines(&doc);
        assert!(
            section.blocks.is_empty(),
            "a non-canonical heading must not open a block: {:?}",
            section.blocks
        );
        assert_eq!(section.nonconforming_headings.len(), 1);
        assert_eq!(section.nonconforming_headings[0].text, "4. do the thing");
    }

    #[test]
    fn outlines_none_with_trailing_period_is_an_intentional_absence() {
        // The contract's own example writes `**Dependencies**: None.`, so the
        // period must not turn it into an unresolved token.
        let doc = single_pr_plan(
            "## Issue Outlines\n\n### Issue 1: a\n\n**Goal**: g.\n\n**Dependencies**: None.\n",
        );
        let section = parse_issue_outlines(&doc);
        assert!(section.blocks[0].dependencies_none);
        assert!(section.blocks[0].unresolved_dependencies.is_empty());
        assert!(section.blocks[0].waits_on.is_empty());
    }

    #[test]
    fn outlines_placeholder_and_prose_reference_resolve_identically() {
        let placeholder = single_pr_plan(
            "## Issue Outlines\n\n### Issue 1: a\n\n**Dependencies**: None\n\n### Issue 2: b\n\n**Dependencies**: Blocked by <<ISSUE:1>>\n",
        );
        let prose = single_pr_plan(
            "## Issue Outlines\n\n### Issue 1: a\n\n**Dependencies**: None\n\n### Issue 2: b\n\n**Dependencies**: Blocked by Issue 1.\n",
        );
        let a = parse_issue_outlines(&placeholder);
        let b = parse_issue_outlines(&prose);
        assert_eq!(a.blocks[1].waits_on, vec![1]);
        assert_eq!(b.blocks[1].waits_on, vec![1]);
        assert!(a.blocks[1].unresolved_dependencies.is_empty());
        assert!(b.blocks[1].unresolved_dependencies.is_empty());
    }

    #[test]
    fn outlines_colon_inside_the_bold_parses_identically() {
        let doc = single_pr_plan(
            "## Issue Outlines\n\n### Issue 1: a\n\n**Dependencies**: None\n\n### Issue 2: b\n\n**Dependencies:** Blocked by Issue 1.\n",
        );
        let section = parse_issue_outlines(&doc);
        assert!(section.blocks[1].dependencies_declared);
        assert_eq!(section.blocks[1].waits_on, vec![1]);
    }

    #[test]
    fn outlines_bare_numeric_dependency_is_unresolved_not_dropped() {
        // The #275 fail-open case: the extractor used to emit a task with no
        // edge and say nothing.
        let doc = single_pr_plan(
            "## Issue Outlines\n\n### Issue 1: a\n\n**Dependencies**: None\n\n### Issue 2: b\n\n**Dependencies**: 1\n",
        );
        let section = parse_issue_outlines(&doc);
        assert!(section.blocks[1].waits_on.is_empty());
        assert_eq!(
            section.blocks[1].unresolved_dependencies,
            vec!["1".to_string()]
        );
    }

    #[test]
    fn outlines_github_style_reference_is_unresolved_in_single_pr() {
        // `#N` is the multi-pr table's form; reading it as an outline
        // reference would invent an edge from a GitHub issue number.
        let doc = single_pr_plan(
            "## Issue Outlines\n\n### Issue 1: a\n\n**Dependencies**: None\n\n### Issue 2: b\n\n**Dependencies**: Blocked by #1.\n",
        );
        let section = parse_issue_outlines(&doc);
        assert!(section.blocks[1].waits_on.is_empty());
        assert_eq!(
            section.blocks[1].unresolved_dependencies,
            vec!["#1".to_string()]
        );
    }

    #[test]
    fn outlines_reference_to_a_missing_sibling_is_unresolved() {
        let doc = single_pr_plan(
            "## Issue Outlines\n\n### Issue 1: a\n\n**Dependencies**: Blocked by Issue 42\n",
        );
        let section = parse_issue_outlines(&doc);
        assert_eq!(
            section.blocks[0].unresolved_dependencies,
            vec!["Issue 42".to_string()]
        );
    }

    #[test]
    fn outlines_resolution_keys_on_heading_numbers_not_position() {
        // Numbered 2 and 5: a positional reader resolves against 1 and 2 and
        // gets both edges wrong.
        let doc = single_pr_plan(
            "## Issue Outlines\n\n### Issue 2: a\n\n**Dependencies**: None\n\n### Issue 5: b\n\n**Dependencies**: Blocked by Issue 2.\n",
        );
        let section = parse_issue_outlines(&doc);
        assert_eq!(section.blocks[1].waits_on, vec![2]);
        assert!(section.blocks[1].unresolved_dependencies.is_empty());
    }

    #[test]
    fn outlines_dependencies_subheading_carries_edges_and_opens_no_block() {
        let doc = single_pr_plan(
            "## Issue Outlines\n\n### Issue 1: a\n\n**Goal**: g.\n\n**Dependencies**: None.\n\n---\n\n### Issue 2: b\n\n**Goal**: g.\n\n### Dependencies\n\nIssue 1\n",
        );
        let section = parse_issue_outlines(&doc);
        assert_eq!(
            section.blocks.len(),
            2,
            "the sub-heading must not open a third block"
        );
        assert!(
            section.nonconforming_headings.is_empty(),
            "`### Dependencies` is a known sub-heading, not a stray one"
        );
        assert!(section.blocks[1].dependencies_declared);
        assert_eq!(section.blocks[1].waits_on, vec![1]);
    }

    #[test]
    fn outlines_type_and_files_are_read() {
        let doc = single_pr_plan(
            "## Issue Outlines\n\n### Issue 1: a\n\n**Dependencies**: None\n\n**Type**: Docs\n**Files**: `a/b.rs`, `c/d.md`\n",
        );
        let section = parse_issue_outlines(&doc);
        assert_eq!(section.blocks[0].issue_type.as_deref(), Some("docs"));
        assert_eq!(
            section.blocks[0].files,
            vec!["a/b.rs".to_string(), "c/d.md".to_string()]
        );
    }

    #[test]
    fn outlines_declared_flags_are_independent_of_content() {
        let doc = single_pr_plan(
            "## Issue Outlines\n\n### Issue 1: a\n\n**Acceptance Criteria**:\n\n### Issue 2: b\n\n**Goal**: g.\n",
        );
        let section = parse_issue_outlines(&doc);
        assert!(section.blocks[0].acceptance_criteria_declared);
        assert!(section.blocks[0].acceptance_criteria.is_empty());
        assert!(!section.blocks[0].goal_declared);
        assert!(section.blocks[1].goal_declared);
        assert!(!section.blocks[1].acceptance_criteria_declared);
        assert!(!section.blocks[1].dependencies_declared);
    }

    #[test]
    fn outline_acs_projection_matches_the_blocks_it_flattens() {
        let doc = single_pr_plan(
            "## Issue Outlines\n\n### Issue 1: a\n\n**Acceptance Criteria**:\n- [ ] one\n- [x] two\n\n### Issue 2: b\n\n**Acceptance Criteria**:\n- [ ] three\n",
        );
        let section = parse_issue_outlines(&doc);
        let flattened: Vec<_> = section
            .blocks
            .iter()
            .flat_map(|b| b.acceptance_criteria.clone())
            .collect();
        assert_eq!(parse_outline_acs(&doc), flattened);
        assert_eq!(flattened.len(), 3);
    }

    // --- parse_outline_acs ---

    fn single_pr_plan(body: &str) -> Doc {
        let md = format!(
            "---\nschema: plan/v1\nstatus: Draft\nexecution_mode: single-pr\nupstream: docs/designs/DESIGN-x.md\nmilestone: \"x\"\nissue_count: 1\n---\n\n# PLAN: x\n\n## Status\n\nDraft\n\n## Scope Summary\n\nfoo.\n\n## Decomposition Strategy\n\nbar.\n\n{}\n\n## Implementation Sequence\n\nbaz.\n",
            body
        );
        doc_from_markdown(&md)
    }

    #[test]
    fn parse_outline_acs_returns_empty_when_section_absent() {
        let doc = doc_from_markdown(
            "---\nschema: plan/v1\nstatus: Draft\nexecution_mode: single-pr\n---\n\n# PLAN: x\n\n## Status\n\nDraft\n\n## Scope Summary\n\nfoo.\n",
        );
        assert!(parse_outline_acs(&doc).is_empty());
    }

    #[test]
    fn parse_outline_acs_collects_canonical_unticked_and_ticked() {
        let doc = single_pr_plan(
            "## Issue Outlines\n\n### Issue 1: first\n\n**Goal**: do x.\n\n**Acceptance Criteria**:\n- [ ] open box\n- [x] lowercase ticked\n- [X] uppercase ticked\n\n**Dependencies**: None\n",
        );
        let acs = parse_outline_acs(&doc);
        assert_eq!(acs.len(), 3);
        assert_eq!(acs[0].outline_key, "Issue 1: first");
        assert_eq!(acs[0].ac_text, "open box");
        assert!(!acs[0].ticked);
        assert!(acs[1].ticked);
        assert!(acs[2].ticked);
    }

    #[test]
    fn parse_outline_acs_ignores_noncanonical_shapes() {
        let doc = single_pr_plan(
            "## Issue Outlines\n\n### Issue 1: first\n\n**Acceptance Criteria**:\n- bare bullet, no bracket\n-[] no space before bracket\n- [  ] wide brackets\n- [ ] canonical\n\n**Dependencies**: None\n",
        );
        let acs = parse_outline_acs(&doc);
        // Only the canonical `- [ ] canonical` line counts; the three
        // non-canonical shapes above it are silently dropped per the
        // strict-tolerance contract.
        assert_eq!(acs.len(), 1);
        assert_eq!(acs[0].ac_text, "canonical");
        assert!(!acs[0].ticked);
    }

    #[test]
    fn parse_outline_acs_correlates_acs_with_outline_keys() {
        let doc = single_pr_plan(
            "## Issue Outlines\n\n### Issue 1: first\n\n**Acceptance Criteria**:\n- [ ] one\n- [x] two\n\n**Dependencies**: None\n\n### Issue 2: second\n\n**Acceptance Criteria**:\n- [ ] three\n\n**Dependencies**: None\n",
        );
        let acs = parse_outline_acs(&doc);
        assert_eq!(acs.len(), 3);
        assert_eq!(acs[0].outline_key, "Issue 1: first");
        assert_eq!(acs[1].outline_key, "Issue 1: first");
        assert_eq!(acs[2].outline_key, "Issue 2: second");
        assert_eq!(acs[2].ac_text, "three");
    }

    #[test]
    fn parse_outline_acs_dependencies_block_does_not_consume_ac_bullets() {
        let doc = single_pr_plan(
            "## Issue Outlines\n\n### Issue 1: first\n\n**Acceptance Criteria**:\n- [ ] before deps\n\n**Dependencies**: None\n\n- [ ] this is outside any AC block\n",
        );
        let acs = parse_outline_acs(&doc);
        // Only the first checkbox (inside the AC block) counts; the
        // post-Dependencies bullet is outside the AC scope and dropped.
        assert_eq!(acs.len(), 1);
        assert_eq!(acs[0].ac_text, "before deps");
    }

    #[test]
    fn parse_outline_acs_line_numbers_are_one_indexed_absolute() {
        let doc = single_pr_plan(
            "## Issue Outlines\n\n### Issue 1: first\n\n**Acceptance Criteria**:\n- [ ] target\n",
        );
        let acs = parse_outline_acs(&doc);
        assert_eq!(acs.len(), 1);
        assert!(acs[0].line > 0, "line numbers are 1-indexed");
    }
}
