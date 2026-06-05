//! Status-transition engine for shirabe doc types.
//!
//! Consolidates the six per-skill `transition-status.sh` scripts behind one
//! declarative spec table interpreted by a single engine, per
//! `DESIGN-transition-script-consolidation.md`.
//!
//! ## Scope of this module (Issue 1)
//!
//! The [`TransitionSpec`] table is shaped for the full design — it carries the
//! status set, the transition [`Rule`], and stub fields for the later concerns
//! ([`Precondition`], [`Moves`], [`ExtraInput`], [`BodyTemplate`],
//! [`ResultFields`]) so the table is the one place each type's rules live.
//! Issue 1 only wires the engine to enforce **status membership** plus the
//! base frontmatter/body rewrite for the membership-only / no-move /
//! no-precondition path (prd, roadmap, brief base behavior). Graph evaluation,
//! preconditions, moves, extra inputs, and the idempotent short-circuit's
//! interaction with the extra-input gate land in Issues 2 and 3.
//!
//! ## Read vs. write
//!
//! The read path reuses the existing read-only frontmatter parser
//! ([`crate::frontmatter::parse_doc`]) and [`crate::detect_format`]. The write
//! path is a targeted line replacement (mirroring the scripts' `sed`/`awk`),
//! **not** a YAML re-serialization, so untouched bytes are preserved exactly.

use std::fmt;
use std::fs;
use std::io;
use std::path::Path;

use crate::detect_format;
use crate::frontmatter::{self, ParseError};

// ---------------------------------------------------------------------------
// Spec table
// ---------------------------------------------------------------------------

/// The transition rule for a type.
///
/// `MembershipOnly` types (prd, design) accept any valid status as a target
/// with no ordering constraint. `Graph` types (vision, strategy, roadmap,
/// brief) restrict transitions to an explicit edge list.
///
/// Issue 1 only enforces membership (the target-is-a-known-status check in
/// the engine covers both rules); `Graph` edge evaluation arrives in Issue 2.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Rule {
    /// Any valid status is a legal target.
    MembershipOnly,
    /// Only the listed `(from, to)` edges are legal transitions.
    Graph(Vec<(String, String)>),
}

/// Deterministic, document-local precondition gates.
///
/// Stub for Issue 2. The design limits preconditions to checks that need no
/// network or other documents (the existing Open-Questions-resolved and
/// >=2-features gates).
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Precondition {
    /// No precondition.
    None,
    /// Open Questions must be resolved (vision/strategy Draft -> Accepted).
    OpenQuestionsResolved,
    /// At least N `### Feature` headings (roadmap Draft -> Active, N = 2).
    MinFeatures(usize),
}

/// Directory moves keyed by the status that triggers them.
///
/// Stub for Issue 3. Each entry maps a status to the repo-relative target
/// directory the document is `git mv`'d into when it reaches that status.
#[derive(Debug, Clone, PartialEq, Eq, Default)]
pub struct Moves {
    /// `(status, target_directory)` pairs. Empty for types that never move
    /// (prd, roadmap, brief).
    pub entries: Vec<(String, String)>,
}

/// Per-type extra-input requirement.
///
/// Stub for Issue 3. The `missing_code` records the per-type exit code for a
/// missing required input: 1 for design's `--superseded-by` (treated as an
/// invalid-arguments error), 2 for strategy's `--reason`.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum ExtraInput {
    /// No extra input.
    None,
    /// `--superseded-by <path>`: required for design Superseded, optional for
    /// vision Sunset.
    SupersededBy {
        required: bool,
        target_status: String,
        missing_code: i32,
    },
    /// `--reason <text>`: required and sanitized for strategy Sunset.
    Reason {
        required: bool,
        sanitized: bool,
        target_status: String,
        missing_code: i32,
    },
}

/// The body `## Status` rewrite template for a type.
///
/// Most types write the bare status word; prd rewrites the full status line
/// (so multi-word `In Progress` round-trips). The non-bare move templates land
/// in Issue 3.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum BodyTemplate {
    /// Write the bare target status word (roadmap, brief, vision/strategy/
    /// design pre-move).
    BareStatus,
    /// Rewrite the entire matched status line, not just the first word (prd).
    FullStatusLine,
    /// `Superseded by [name](path)` (design Superseded). Stub for Issue 3.
    SupersededBy,
    /// `Sunset: superseded by [name](path)` (vision Sunset). Stub for Issue 3.
    SunsetSupersededBy,
    /// `Sunset: <reason>` (strategy Sunset). Stub for Issue 3.
    SunsetReason,
}

/// The JSON result-field shape for a type.
///
/// The per-type result shapes stay divergent (the PRD chose preserve-over-
/// unify). prd and brief emit the four base fields; roadmap adds `new_path`
/// and `moved`; the move types add `superseded_by` / `reason` in Issue 3.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum ResultFields {
    /// `{success, doc_path, old_status, new_status}` (prd, brief).
    Base,
    /// Base plus `new_path` and `moved` (roadmap, design, vision, strategy).
    WithPath,
}

/// A declarative descriptor for one doc type's transition behavior.
///
/// The six specs live in one table ([`transition_spec`]); the engine
/// interprets them. This is the single place a transition rule changes.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct TransitionSpec {
    /// The format name from `FormatSpec.name` (e.g. "PRD", "Roadmap").
    pub format_name: String,
    /// The valid status set for the type, in canonical order.
    pub statuses: Vec<String>,
    /// The transition rule (membership-only or an ordered graph).
    pub rule: Rule,
    /// Deterministic, document-local precondition gate. Stub for Issue 2.
    pub precondition: Precondition,
    /// Directory moves keyed by triggering status. Stub for Issue 3.
    pub moves: Moves,
    /// Per-type extra-input requirement. Stub for Issue 3.
    pub extra_input: ExtraInput,
    /// The body `## Status` rewrite template.
    pub body_template: BodyTemplate,
    /// The JSON result-field shape.
    pub result_fields: ResultFields,
}

fn s(values: &[&str]) -> Vec<String> {
    values.iter().map(|v| (*v).to_string()).collect()
}

fn edges(pairs: &[(&str, &str)]) -> Vec<(String, String)> {
    pairs
        .iter()
        .map(|(a, b)| (a.to_string(), b.to_string()))
        .collect()
}

/// Return the [`TransitionSpec`] for a format name (`FormatSpec.name`), or
/// `None` if the format has no transition behavior.
///
/// The PLAN type is intentionally absent: it is not one of the six artifact
/// types the scripts cover, and its Done gate needs external GitHub state
/// (out of scope per the design's Boundary note).
pub fn transition_spec(format_name: &str) -> Option<TransitionSpec> {
    transition_table()
        .into_iter()
        .find(|spec| spec.format_name == format_name)
}

/// The full six-entry transition spec table.
///
/// Status sets and the membership/graph rule are filled for all six types;
/// the precondition / moves / extra-input / move-template fields are shaped
/// per the design and populated by later issues.
pub fn transition_table() -> Vec<TransitionSpec> {
    vec![
        TransitionSpec {
            format_name: "VISION".to_string(),
            statuses: s(&["Draft", "Accepted", "Active", "Sunset"]),
            rule: Rule::Graph(edges(&[
                ("Draft", "Accepted"),
                ("Accepted", "Active"),
                ("Active", "Sunset"),
            ])),
            precondition: Precondition::OpenQuestionsResolved,
            moves: Moves {
                entries: vec![("Sunset".to_string(), "docs/visions/sunset".to_string())],
            },
            extra_input: ExtraInput::SupersededBy {
                required: false,
                target_status: "Sunset".to_string(),
                missing_code: 1,
            },
            body_template: BodyTemplate::BareStatus,
            result_fields: ResultFields::WithPath,
        },
        TransitionSpec {
            format_name: "Strategy".to_string(),
            statuses: s(&["Draft", "Accepted", "Active", "Sunset"]),
            // Strategy's graph includes Accepted -> Sunset, which vision lacks.
            rule: Rule::Graph(edges(&[
                ("Draft", "Accepted"),
                ("Accepted", "Active"),
                ("Accepted", "Sunset"),
                ("Active", "Sunset"),
            ])),
            precondition: Precondition::OpenQuestionsResolved,
            moves: Moves {
                entries: vec![("Sunset".to_string(), "docs/strategies/sunset".to_string())],
            },
            extra_input: ExtraInput::Reason {
                required: true,
                sanitized: true,
                target_status: "Sunset".to_string(),
                missing_code: 2,
            },
            body_template: BodyTemplate::BareStatus,
            result_fields: ResultFields::WithPath,
        },
        TransitionSpec {
            format_name: "Roadmap".to_string(),
            statuses: s(&["Draft", "Active", "Done"]),
            rule: Rule::Graph(edges(&[("Draft", "Active"), ("Active", "Done")])),
            precondition: Precondition::MinFeatures(2),
            moves: Moves::default(),
            extra_input: ExtraInput::None,
            body_template: BodyTemplate::BareStatus,
            result_fields: ResultFields::WithPath,
        },
        TransitionSpec {
            format_name: "Brief".to_string(),
            statuses: s(&["Draft", "Accepted", "Done"]),
            rule: Rule::Graph(edges(&[("Draft", "Accepted"), ("Accepted", "Done")])),
            precondition: Precondition::None,
            moves: Moves::default(),
            extra_input: ExtraInput::None,
            body_template: BodyTemplate::BareStatus,
            result_fields: ResultFields::Base,
        },
        TransitionSpec {
            format_name: "PRD".to_string(),
            statuses: s(&["Draft", "Accepted", "In Progress", "Done"]),
            rule: Rule::MembershipOnly,
            precondition: Precondition::None,
            moves: Moves::default(),
            extra_input: ExtraInput::None,
            // prd rewrites the full status line so multi-word values
            // ("In Progress") round-trip.
            body_template: BodyTemplate::FullStatusLine,
            result_fields: ResultFields::Base,
        },
        TransitionSpec {
            format_name: "Design".to_string(),
            statuses: s(&["Proposed", "Accepted", "Planned", "Current", "Superseded"]),
            rule: Rule::MembershipOnly,
            precondition: Precondition::None,
            moves: Moves {
                entries: vec![
                    ("Current".to_string(), "docs/designs/current".to_string()),
                    ("Superseded".to_string(), "docs/designs/archive".to_string()),
                ],
            },
            extra_input: ExtraInput::SupersededBy {
                required: true,
                target_status: "Superseded".to_string(),
                missing_code: 1,
            },
            body_template: BodyTemplate::BareStatus,
            result_fields: ResultFields::WithPath,
        },
    ]
}

// ---------------------------------------------------------------------------
// Engine
// ---------------------------------------------------------------------------

/// A successful transition outcome, ready for JSON rendering.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Outcome {
    /// The document path (unchanged in Issue 1; types never move yet).
    pub doc_path: String,
    /// The status the document held before the transition.
    pub old_status: String,
    /// The status the document holds after the transition.
    pub new_status: String,
    /// The path after a move; equals `doc_path` for non-moving types.
    pub new_path: String,
    /// Whether the file moved. Always `false` in Issue 1.
    pub moved: bool,
    /// The result-field shape, controlling which fields render to JSON.
    pub result_fields: ResultFields,
}

impl Outcome {
    /// Render the per-type JSON result exactly as the scripts' `json_success`
    /// helper does: a 2-space-indented object with a trailing newline, key
    /// order preserved.
    pub fn to_json(&self) -> String {
        let mut out = String::from("{\n");
        out.push_str("  \"success\": true,\n");
        out.push_str(&format!(
            "  \"doc_path\": {},\n",
            json_string(&self.doc_path)
        ));
        out.push_str(&format!(
            "  \"old_status\": {},\n",
            json_string(&self.old_status)
        ));
        match self.result_fields {
            ResultFields::Base => {
                out.push_str(&format!(
                    "  \"new_status\": {}\n",
                    json_string(&self.new_status)
                ));
            }
            ResultFields::WithPath => {
                out.push_str(&format!(
                    "  \"new_status\": {},\n",
                    json_string(&self.new_status)
                ));
                out.push_str(&format!(
                    "  \"new_path\": {},\n",
                    json_string(&self.new_path)
                ));
                out.push_str(&format!("  \"moved\": {}\n", self.moved));
            }
        }
        out.push_str("}\n");
        out
    }
}

/// A transition failure carrying the script-faithful exit code and message.
///
/// The `code` is the 1/2/3 exit code; `message` is the human-readable reason.
/// Rendered to stderr by [`TransitionError::to_json`] with a matching `code`
/// field, exactly as the scripts' `json_error` helper does.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct TransitionError {
    pub code: i32,
    pub message: String,
}

impl TransitionError {
    fn new(code: i32, message: impl Into<String>) -> Self {
        Self {
            code,
            message: message.into(),
        }
    }

    /// Render the error JSON exactly as the scripts' `json_error` helper:
    /// `{success: false, error: <message>, code: <code>}`, 2-space indented,
    /// trailing newline.
    pub fn to_json(&self) -> String {
        format!(
            "{{\n  \"success\": false,\n  \"error\": {},\n  \"code\": {}\n}}\n",
            json_string(&self.message),
            self.code
        )
    }
}

impl fmt::Display for TransitionError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "{} (code {})", self.message, self.code)
    }
}

impl std::error::Error for TransitionError {}

/// Per-type extra inputs supplied on the command line.
///
/// Stub for Issue 3 (the engine does not yet consult these). Wired now so the
/// engine signature is stable across issues.
#[derive(Debug, Clone, Default)]
pub struct Flags {
    /// `--superseded-by <path>`.
    pub superseded_by: Option<String>,
    /// `--reason <text>`.
    pub reason: Option<String>,
}

/// Run a transition on `file` to the canonical status `target_status`.
///
/// The step order matches the scripts so parity holds. Issue 1 implements the
/// membership-only / no-move / no-precondition path; graph evaluation,
/// preconditions, moves, and the extra-input gate land in later issues.
///
/// 1. `detect_format(basename)` -> type, or exit 1 ("cannot determine artifact
///    type").
/// 2. Parse the current status from frontmatter (preferred) or the body
///    `## Status` line; an unparseable status is exit 1.
/// 3. The target must be a known status for the type, else exit 2.
/// 4. Idempotent short-circuit: target == current -> success no-op.
/// 5. Apply edits: targeted `status:` frontmatter line replacement and the
///    body `## Status` rewrite per the type's template.
/// 6. Return the [`Outcome`] for JSON rendering.
pub fn run_transition(
    file: &str,
    target_status: &str,
    _flags: &Flags,
) -> Result<Outcome, TransitionError> {
    // Step 1: detect type.
    let spec = detect_format(basename(file))
        .and_then(|fmt| transition_spec(&fmt.name))
        .ok_or_else(|| {
            TransitionError::new(1, format!("cannot determine artifact type for: {}", file))
        })?;

    if !Path::new(file).is_file() {
        return Err(TransitionError::new(1, format!("doc not found: {}", file)));
    }

    // Step 2: parse current status.
    let doc = frontmatter::parse_doc(file).map_err(parse_error_to_transition)?;
    let current_status = current_status(&doc, &spec)
        .ok_or_else(|| TransitionError::new(1, "could not extract status from doc".to_string()))?;

    // Step 3: target must be a known status for the type.
    if !spec.statuses.iter().any(|s| s == target_status) {
        return Err(TransitionError::new(
            2,
            format!(
                "Invalid status: {}. Must be one of: {}",
                target_status,
                spec.statuses.join(" ")
            ),
        ));
    }

    // Step 4: idempotent short-circuit.
    //
    // Issue 1: no extra-input gate yet, so the no-op can short-circuit here
    // directly. Issue 3 introduces the extra-input gate that must run BEFORE
    // this short-circuit (per the design's step 4-before-5 ordering).
    if current_status == target_status {
        return Ok(success(&spec, file, &current_status, target_status));
    }

    // NOTE: graph-rule evaluation (Issue 2), preconditions (Issue 2), and
    // moves (Issue 3) slot in here, after the short-circuit, in the order the
    // design specifies. Issue 1's membership-only path reaches the edits
    // directly.

    // Step 5: apply edits (read the file, rewrite, write back).
    let original = fs::read_to_string(file)
        .map_err(|e| TransitionError::new(3, format!("Failed to read file: {}", io_text(&e))))?;
    let updated = rewrite(&original, &doc, &spec, &current_status, target_status);
    fs::write(file, updated)
        .map_err(|e| TransitionError::new(3, format!("Failed to write file: {}", io_text(&e))))?;

    // Step 6: assemble the result.
    Ok(success(&spec, file, &current_status, target_status))
}

/// Build the success [`Outcome`] for a type. Issue 1 types never move, so
/// `new_path` equals the input path and `moved` is `false`.
fn success(spec: &TransitionSpec, file: &str, old: &str, new: &str) -> Outcome {
    Outcome {
        doc_path: file.to_string(),
        old_status: old.to_string(),
        new_status: new.to_string(),
        new_path: file.to_string(),
        moved: false,
        result_fields: spec.result_fields.clone(),
    }
}

/// Extract the current status the way the scripts do: prefer the frontmatter
/// `status:` value, falling back to the body `## Status` line. For
/// [`BodyTemplate::FullStatusLine`] types (prd) the body status is the full
/// matched line; otherwise it is the first word.
fn current_status(doc: &crate::Doc, spec: &TransitionSpec) -> Option<String> {
    let fm = doc
        .fields
        .get("status")
        .map(|fv| fv.value.trim().to_string());
    if let Some(value) = fm {
        if !value.is_empty() {
            return Some(value);
        }
    }
    body_status(doc, spec)
}

/// Find the body status line per the scripts: scan from the `## Status`
/// heading across the next 3 lines for the first line that starts with one of
/// the type's valid statuses. Returns the full line (`FullStatusLine`) or the
/// first word (`BareStatus`-family), matching the per-type `get_body_status`.
fn body_status(doc: &crate::Doc, spec: &TransitionSpec) -> Option<String> {
    let line = body_status_line(doc, spec)?;
    match spec.body_template {
        BodyTemplate::FullStatusLine => Some(line),
        _ => line.split_whitespace().next().map(str::to_string),
    }
}

/// Return the raw body status line (trimmed of leading whitespace) the scripts
/// match via `grep -A 3 '^## Status' | grep -E '^(<status>)'`.
fn body_status_line(doc: &crate::Doc, spec: &TransitionSpec) -> Option<String> {
    let heading = doc.body.iter().position(|l| l == "## Status")?;
    // `grep -A 3` yields the matched line plus the 3 following lines.
    let window_end = (heading + 4).min(doc.body.len());
    for line in &doc.body[heading..window_end] {
        let trimmed = line.trim_start();
        if spec
            .statuses
            .iter()
            .any(|status| trimmed.starts_with(status.as_str()))
        {
            return Some(trimmed.to_string());
        }
    }
    None
}

/// Rewrite the frontmatter `status:` line and the body `## Status` line in the
/// raw file text. Targeted line edits (mirroring the scripts' `sed`), not a
/// YAML re-serialization, so untouched bytes are preserved.
fn rewrite(
    original: &str,
    doc: &crate::Doc,
    spec: &TransitionSpec,
    _current_status: &str,
    target_status: &str,
) -> String {
    let has_trailing_newline = original.ends_with('\n');
    let has_frontmatter = doc.fields.contains_key("status");
    let body_old = body_status_line(doc, spec);

    let mut out_lines: Vec<String> = Vec::new();
    let mut in_frontmatter = false;
    let mut seen_open = false;
    let mut frontmatter_done = false;
    let mut rewrote_body = false;

    for line in original.split('\n') {
        // Frontmatter delimiter tracking: the first `---` opens, the next
        // closes. Only rewrite the `status:` line inside the frontmatter.
        if line == "---" && !frontmatter_done {
            if !seen_open {
                seen_open = true;
                in_frontmatter = true;
            } else {
                in_frontmatter = false;
                frontmatter_done = true;
            }
            out_lines.push(line.to_string());
            continue;
        }

        if has_frontmatter && in_frontmatter && line.starts_with("status:") {
            // `s/^status:.*$/status: <target>/`
            out_lines.push(format!("status: {}", target_status));
            continue;
        }

        // Body `## Status` rewrite: replace the exact matched old line with
        // the new line (full line for prd, bare word otherwise).
        if !rewrote_body {
            if let Some(old) = &body_old {
                if line.trim_start() == old.as_str() && line.trim_start() == line {
                    out_lines.push(target_status.to_string());
                    rewrote_body = true;
                    continue;
                }
            }
        }

        out_lines.push(line.to_string());
    }

    let mut joined = out_lines.join("\n");
    // `original.split('\n')` on a trailing-newline file produces a final
    // empty element, which the join already reproduces; only re-add a newline
    // when the original had one and the join dropped it. The split/join pair
    // is byte-exact for the trailing-newline case, so guard the no-newline
    // case explicitly.
    if has_trailing_newline && !joined.ends_with('\n') {
        joined.push('\n');
    }
    joined
}

/// Map a [`ParseError`] from the read-only parser to the engine's exit-code
/// contract. Any parse failure on the read path is an unparseable-status
/// (exit 1) error, matching the scripts' `Could not extract status` path.
fn parse_error_to_transition(err: ParseError) -> TransitionError {
    TransitionError::new(1, format!("could not parse doc: {}", err))
}

/// Returns the final path component of `path`, matching `basename` semantics
/// for POSIX-style repo-relative paths.
fn basename(path: &str) -> &str {
    let trimmed = path.trim_end_matches('/');
    if trimmed.is_empty() {
        return "/";
    }
    match trimmed.rfind('/') {
        Some(idx) => &trimmed[idx + 1..],
        None => trimmed,
    }
}

/// Trim the `io::Error` wrapper text for an error message.
fn io_text(err: &io::Error) -> String {
    err.to_string()
}

/// JSON-encode a string with the minimal escaping `jq` applies to scalars:
/// `"`, `\`, and the control characters that must be escaped in JSON.
fn json_string(value: &str) -> String {
    let mut out = String::with_capacity(value.len() + 2);
    out.push('"');
    for ch in value.chars() {
        match ch {
            '"' => out.push_str("\\\""),
            '\\' => out.push_str("\\\\"),
            '\n' => out.push_str("\\n"),
            '\r' => out.push_str("\\r"),
            '\t' => out.push_str("\\t"),
            c if (c as u32) < 0x20 => out.push_str(&format!("\\u{:04x}", c as u32)),
            c => out.push(c),
        }
    }
    out.push('"');
    out
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::fs;
    use std::sync::atomic::{AtomicU64, Ordering};

    static COUNTER: AtomicU64 = AtomicU64::new(0);

    /// Write `content` to a uniquely-named temp file with the given basename
    /// prefix (so `detect_format` resolves the type) and return its path.
    fn write_doc(basename: &str, content: &str) -> String {
        let n = COUNTER.fetch_add(1, Ordering::SeqCst);
        let dir =
            std::env::temp_dir().join(format!("shirabe-transition-{}-{}", std::process::id(), n));
        fs::create_dir_all(&dir).expect("mkdir temp");
        let path = dir.join(basename);
        fs::write(&path, content).expect("write doc");
        path.to_string_lossy().into_owned()
    }

    // ---- prd ----

    #[test]
    fn prd_legal_change_rewrites_and_emits_base_result() {
        let doc = "---\nschema: prd/v1\nstatus: Draft\nproblem: x\ngoals: y\n---\n\n# Title\n\n## Status\n\nDraft\n";
        let path = write_doc("PRD-foo.md", doc);
        let outcome = run_transition(&path, "In Progress", &Flags::default()).expect("ok");

        assert_eq!(outcome.old_status, "Draft");
        assert_eq!(outcome.new_status, "In Progress");
        assert_eq!(outcome.result_fields, ResultFields::Base);

        let updated = fs::read_to_string(&path).unwrap();
        assert!(updated.contains("status: In Progress"));
        // Body line rewritten to the full multi-word status.
        assert!(updated.contains("\n## Status\n\nIn Progress\n"));

        let json = outcome.to_json();
        assert!(json.contains("\"success\": true"));
        assert!(json.contains("\"old_status\": \"Draft\""));
        assert!(json.contains("\"new_status\": \"In Progress\""));
        assert!(!json.contains("new_path"));
    }

    #[test]
    fn prd_in_progress_round_trips_out() {
        let doc = "---\nstatus: In Progress\n---\n\n## Status\n\nIn Progress\n";
        let path = write_doc("PRD-bar.md", doc);
        let outcome = run_transition(&path, "Done", &Flags::default()).expect("ok");
        assert_eq!(outcome.old_status, "In Progress");
        let updated = fs::read_to_string(&path).unwrap();
        assert!(updated.contains("status: Done"));
        assert!(updated.contains("\n## Status\n\nDone\n"));
    }

    #[test]
    fn prd_unknown_status_exits_2() {
        let doc = "---\nstatus: Draft\n---\n\n## Status\n\nDraft\n";
        let path = write_doc("PRD-baz.md", doc);
        let err = run_transition(&path, "Bogus", &Flags::default()).expect_err("err");
        assert_eq!(err.code, 2);
    }

    // ---- roadmap ----

    #[test]
    fn roadmap_legal_change_emits_with_path_result() {
        let doc = "---\nstatus: Draft\n---\n\n## Status\n\nDraft\n\n### Feature A\n### Feature B\n";
        let path = write_doc("ROADMAP-foo.md", doc);
        let outcome = run_transition(&path, "Active", &Flags::default()).expect("ok");

        assert_eq!(outcome.old_status, "Draft");
        assert_eq!(outcome.new_status, "Active");
        assert_eq!(outcome.result_fields, ResultFields::WithPath);
        // Roadmaps never move: new_path == input, moved == false.
        assert_eq!(outcome.new_path, path);
        assert!(!outcome.moved);

        let updated = fs::read_to_string(&path).unwrap();
        assert!(updated.contains("status: Active"));
        assert!(updated.contains("\n## Status\n\nActive\n"));

        let json = outcome.to_json();
        assert!(json.contains("\"new_path\""));
        assert!(json.contains("\"moved\": false"));
    }

    #[test]
    fn roadmap_unknown_status_exits_2() {
        let doc = "---\nstatus: Draft\n---\n\n## Status\n\nDraft\n";
        let path = write_doc("ROADMAP-bar.md", doc);
        let err = run_transition(&path, "Shipped", &Flags::default()).expect_err("err");
        assert_eq!(err.code, 2);
    }

    // ---- brief ----

    #[test]
    fn brief_legal_change_rewrites_and_emits_base_result() {
        let doc = "---\nstatus: Draft\n---\n\n## Status\n\nDraft\n";
        let path = write_doc("BRIEF-foo.md", doc);
        let outcome = run_transition(&path, "Accepted", &Flags::default()).expect("ok");

        assert_eq!(outcome.old_status, "Draft");
        assert_eq!(outcome.new_status, "Accepted");
        assert_eq!(outcome.result_fields, ResultFields::Base);

        let updated = fs::read_to_string(&path).unwrap();
        assert!(updated.contains("status: Accepted"));
        assert!(updated.contains("\n## Status\n\nAccepted\n"));
    }

    #[test]
    fn brief_unknown_status_exits_2() {
        let doc = "---\nstatus: Draft\n---\n\n## Status\n\nDraft\n";
        let path = write_doc("BRIEF-bar.md", doc);
        let err = run_transition(&path, "Archived", &Flags::default()).expect_err("err");
        assert_eq!(err.code, 2);
    }

    // ---- type detection / idempotency ----

    #[test]
    fn unrecognized_filename_exits_1() {
        let doc = "---\nstatus: Draft\n---\n\n## Status\n\nDraft\n";
        let path = write_doc("README.md", doc);
        let err = run_transition(&path, "Done", &Flags::default()).expect_err("err");
        assert_eq!(err.code, 1);
    }

    #[test]
    fn idempotent_noop_at_current_status() {
        let doc = "---\nstatus: Draft\n---\n\n## Status\n\nDraft\n";
        let path = write_doc("BRIEF-noop.md", doc);
        let before = fs::read_to_string(&path).unwrap();
        let outcome = run_transition(&path, "Draft", &Flags::default()).expect("ok");
        assert_eq!(outcome.old_status, "Draft");
        assert_eq!(outcome.new_status, "Draft");
        // No edits on a no-op.
        let after = fs::read_to_string(&path).unwrap();
        assert_eq!(before, after);
    }

    #[test]
    fn body_status_falls_back_when_no_frontmatter_status() {
        // No frontmatter status field; status comes from the body.
        let doc = "# Title\n\n## Status\n\nDraft\n\nbody\n";
        let path = write_doc("BRIEF-bodyonly.md", doc);
        let outcome = run_transition(&path, "Accepted", &Flags::default()).expect("ok");
        assert_eq!(outcome.old_status, "Draft");
        let updated = fs::read_to_string(&path).unwrap();
        assert!(updated.contains("\n## Status\n\nAccepted\n"));
    }

    // ---- JSON rendering parity ----

    #[test]
    fn base_json_matches_jq_shape() {
        let outcome = Outcome {
            doc_path: "docs/prds/PRD-foo.md".to_string(),
            old_status: "Draft".to_string(),
            new_status: "Done".to_string(),
            new_path: "docs/prds/PRD-foo.md".to_string(),
            moved: false,
            result_fields: ResultFields::Base,
        };
        let expected = "{\n  \"success\": true,\n  \"doc_path\": \"docs/prds/PRD-foo.md\",\n  \"old_status\": \"Draft\",\n  \"new_status\": \"Done\"\n}\n";
        assert_eq!(outcome.to_json(), expected);
    }

    #[test]
    fn with_path_json_matches_jq_shape() {
        let outcome = Outcome {
            doc_path: "x".to_string(),
            old_status: "Draft".to_string(),
            new_status: "Active".to_string(),
            new_path: "x".to_string(),
            moved: false,
            result_fields: ResultFields::WithPath,
        };
        let expected = "{\n  \"success\": true,\n  \"doc_path\": \"x\",\n  \"old_status\": \"Draft\",\n  \"new_status\": \"Active\",\n  \"new_path\": \"x\",\n  \"moved\": false\n}\n";
        assert_eq!(outcome.to_json(), expected);
    }

    #[test]
    fn error_json_matches_jq_shape() {
        let err = TransitionError::new(2, "Invalid status: Foo");
        let expected =
            "{\n  \"success\": false,\n  \"error\": \"Invalid status: Foo\",\n  \"code\": 2\n}\n";
        assert_eq!(err.to_json(), expected);
    }

    #[test]
    fn table_has_six_types() {
        assert_eq!(transition_table().len(), 6);
        assert!(transition_spec("PRD").is_some());
        assert!(transition_spec("Plan").is_none());
    }
}
