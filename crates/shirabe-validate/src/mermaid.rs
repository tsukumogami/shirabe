//! Line-oriented mermaid extractor for FC07 table-diagram reconciliation.
//!
//! Reads the `## Dependency Graph` fenced mermaid block of a parsed [`Doc`]
//! and produces a flat [`Diagram`] carrier with four parallel views: the
//! node set, the edge set, the class assignments, and the declared class
//! names. The extractor is stdlib-only over the corpus subset the spike
//! enumerated (`docs/spikes/SPIKE-mermaid-parser.md`) and total over
//! arbitrary line input -- malformed inputs surface as [`Issue`] values,
//! never panics.
//!
//! Out of scope: arrow variants other than `-->`, alternate node-bracket
//! forms, `classDef` style content, and multi-class statements. The
//! extractor reads only the canonical shape the corpus uses; FC07 does the
//! cross-surface reconciliation against the parsed table.

use std::collections::HashSet;
use std::sync::LazyLock;

use regex::Regex;

use crate::doc::Doc;

/// The extracted views from a single mermaid block.
///
/// Four parallel views. Each is independently consumed by FC07: the node
/// set drives the bijection check, the edge set drives the edge-agreement
/// check, the class assignments drive the class-versus-Status check, and
/// the `class_defs` set is consulted only to flag class statements naming
/// undefined classes.
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct Diagram {
    pub nodes: Vec<Node>,
    pub edges: Vec<Edge>,
    pub class_assignments: Vec<ClassAssignment>,
    pub class_defs: HashSet<String>,
}

/// A node declaration `<id>["<label>"]`.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Node {
    pub id: String,
    pub label: String,
    /// 1-indexed absolute line of the node declaration in the doc.
    pub line: usize,
}

/// A directed edge `src --> dst`.
///
/// Chained forms (`A --> B --> C`) are expanded into adjacent pairs at
/// extraction time; every Edge in the carrier is a single hop.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Edge {
    pub src: String,
    pub dst: String,
    /// 1-indexed absolute line of the edge declaration in the doc.
    pub line: usize,
}

/// A `class <id> <name>` assignment, possibly derived from a comma-list.
///
/// `inline` is true when the assignment was captured from the
/// `<id>:::<class>` inline form rather than a canonical `class` directive.
/// The inline form is flagged as a separate [`Issue`]; the equivalent
/// assignment is still recorded so FC07's class-versus-Status check sees
/// the relationship.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ClassAssignment {
    pub id: String,
    pub name: String,
    pub inline: bool,
    /// 1-indexed absolute line of the originating statement.
    pub line: usize,
}

/// Malformations the extractor surfaces as per-issue notices.
///
/// Each variant carries the 1-indexed absolute line where the
/// malformation was detected (for `MissingBlock`, the `## Dependency
/// Graph` heading line; for `UnterminatedFence`, the opening-fence line;
/// for the line-shape variants, the line that triggered the issue).
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Issue {
    /// Opening fence found but no matching closing fence before EOF.
    UnterminatedFence { line: usize },
    /// `## Dependency Graph` section has no fenced mermaid block.
    MissingBlock { line: usize },
    /// Header is `flowchart` instead of `graph TD`/`graph LR`. The
    /// reference forbids `flowchart`; the extractor still attempts the
    /// body.
    HeaderFlowchart { line: usize },
    /// Header is neither `graph` nor `flowchart`. The block is treated as
    /// empty.
    HeaderUnrecognized { line: usize },
    /// A node declaration or edge used the `:::class` inline form. The
    /// reference prescribes the `class <id> <name>` directive instead.
    InlineClassSyntax { line: usize },
    /// A `class <id> <name>` statement names a `<name>` that no
    /// `classDef` in the same diagram declares.
    UndefinedClass { name: String, line: usize },
}

/// The location of a mermaid block inside a parsed doc.
///
/// `body_start` and `body_end` are 1-indexed absolute line numbers of the
/// first body line (the line after the opening fence) and the
/// one-past-last body line (the closing-fence line, or `doc.body.len() +
/// 1` on an unterminated fence). `issues` carries the malformations
/// detected during block location and during extraction.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BlockLocation {
    pub body_start: usize,
    pub body_end: usize,
    pub issues: Vec<Issue>,
}

/// Matches a canonical node declaration: an id followed by `["..."]`.
/// Ids are alphanumeric-with-underscore starting with a letter or
/// underscore; labels are the quoted string between `["` and `"]`.
static NODE_DECL_PATTERN: LazyLock<Regex> = LazyLock::new(|| {
    Regex::new(r#"^([A-Za-z_][A-Za-z0-9_]*)\["([^"]*)"\]\s*$"#).unwrap()
});

/// Matches a canonical id (used to validate the endpoints of edges and
/// class statements).
static ID_PATTERN: LazyLock<Regex> =
    LazyLock::new(|| Regex::new(r"^[A-Za-z_][A-Za-z0-9_]*$").unwrap());

/// Matches an id with optional `:::class` inline suffix.
static ID_WITH_INLINE_CLASS: LazyLock<Regex> = LazyLock::new(|| {
    Regex::new(r"^([A-Za-z_][A-Za-z0-9_]*)(?::::([A-Za-z_][A-Za-z0-9_]*))?$").unwrap()
});

/// Locate the first fenced mermaid block under `## Dependency Graph` in
/// `doc`. Returns `None` when no `## Dependency Graph` section exists.
/// Returns a [`BlockLocation`] with an `Issue::MissingBlock` when the
/// section exists but has no fenced mermaid block. A block outside the
/// `## Dependency Graph` section is ignored; later blocks under the same
/// section after the first are also ignored.
pub fn find_dependency_graph_block(doc: &Doc) -> Option<BlockLocation> {
    let heading_line = doc
        .sections
        .iter()
        .find(|sec| sec.name == "Dependency Graph")
        .map(|sec| sec.line)?;

    // Walk doc.body from the heading line forward; stop at the next ##.
    let (start_idx, end_idx) = section_body_range(doc, "## Dependency Graph")?;

    // Find the opening ```mermaid fence inside the body range.
    let mut open_idx: Option<usize> = None;
    for i in start_idx..end_idx {
        let line = doc.body[i].trim();
        if line == "```mermaid" {
            open_idx = Some(i);
            break;
        }
    }
    let open_idx = match open_idx {
        Some(i) => i,
        None => {
            return Some(BlockLocation {
                body_start: heading_line,
                body_end: heading_line,
                issues: vec![Issue::MissingBlock { line: heading_line }],
            });
        }
    };

    // body_start is the line after the opening fence (1-indexed absolute).
    let body_start = open_idx + 2;
    // Find the matching closing fence inside the section range.
    let mut close_idx: Option<usize> = None;
    for i in (open_idx + 1)..end_idx {
        if doc.body[i].trim() == "```" {
            close_idx = Some(i);
            break;
        }
    }

    let (body_end, issues) = match close_idx {
        Some(c) => (c + 1, Vec::new()),
        None => (
            // On an unterminated fence, the body extends to the end of
            // the section range.
            end_idx + 1,
            vec![Issue::UnterminatedFence {
                line: open_idx + 1,
            }],
        ),
    };

    Some(BlockLocation {
        body_start,
        body_end,
        issues,
    })
}

/// Return the `[start_idx, end_idx)` indices into `doc.body` that bound
/// the body of `heading` (a `## ` heading). The section runs from the
/// line after the heading to the next `## ` heading or end of body.
fn section_body_range(doc: &Doc, heading: &str) -> Option<(usize, usize)> {
    let mut start_idx: Option<usize> = None;
    let mut end_idx = doc.body.len();
    for (i, line) in doc.body.iter().enumerate() {
        if start_idx.is_none() {
            if line.trim_end_matches([' ', '\t']) == heading {
                start_idx = Some(i + 1);
            }
            continue;
        }
        if line.starts_with("## ") {
            end_idx = i;
            break;
        }
    }
    start_idx.map(|s| (s, end_idx))
}

/// Extract the four-view [`Diagram`] from a slice of body lines (the
/// content between the opening and closing fences of a mermaid block).
///
/// The function is total over arbitrary line input: each line is matched
/// against a fixed set of canonical shapes; lines that match nothing are
/// silently skipped (the consequence -- a missing node or edge -- shows
/// up later in FC07's per-defect notice). Per-line operations use
/// `str::strip_prefix`, `str::find`, and pre-compiled regexes; running
/// time is linear in the number of lines.
///
/// Recognised shapes:
/// - `<id>["<label>"]` -- node declaration.
/// - `<src> --> <dst>` (with chained `A --> B --> C` expansion) -- edge.
/// - `class <id-list> <name>` -- class assignment.
/// - `classDef <name> <styles>` -- class definition (only the name is
///   captured).
/// - `%%` line -- mermaid comment (skipped).
/// - `subgraph` / `end` -- defensive tolerance (skipped).
/// - `graph TD`, `graph LR`, `flowchart` -- header lines (skipped here;
///   the caller flags `flowchart` via [`Issue::HeaderFlowchart`]).
/// - Inline `<id>:::<class>` on a node decl line -- the inline class is
///   recorded as a [`ClassAssignment`] with `inline = true` and an
///   [`Issue::InlineClassSyntax`] is emitted.
///
/// `start_line` is the 1-indexed absolute line of the first slice entry;
/// each emitted Node/Edge/ClassAssignment is line-tagged relative to
/// that base.
pub fn extract_diagram(lines: &[&str], start_line: usize) -> (Diagram, Vec<Issue>) {
    let mut diagram = Diagram::default();
    let mut issues: Vec<Issue> = Vec::new();
    let mut header_seen = false;

    for (idx, raw) in lines.iter().enumerate() {
        let abs_line = start_line + idx;
        let line = raw.trim();
        if line.is_empty() {
            continue;
        }
        if line.starts_with("%%") {
            continue;
        }
        if line.starts_with("subgraph") || line == "end" {
            continue;
        }
        if line.starts_with("graph ") {
            header_seen = true;
            continue;
        }
        if line.starts_with("flowchart") {
            issues.push(Issue::HeaderFlowchart { line: abs_line });
            header_seen = true;
            continue;
        }
        if !header_seen {
            // Anything before a recognised header is a header malformation.
            issues.push(Issue::HeaderUnrecognized { line: abs_line });
            header_seen = true;
            // Continue parsing the body defensively.
        }

        if let Some(rest) = line.strip_prefix("classDef ") {
            // Capture only the class name; ignore the style content.
            let name = rest.split_whitespace().next().unwrap_or("").to_string();
            if !name.is_empty() {
                diagram.class_defs.insert(name);
            }
            continue;
        }
        if let Some(rest) = line.strip_prefix("class ") {
            // `class <id-list> <name>` -- split on whitespace from the
            // right to isolate the class name.
            let trimmed = rest.trim();
            let last_ws = match trimmed.rfind(char::is_whitespace) {
                Some(p) => p,
                None => continue, // malformed (no name)
            };
            let id_list = trimmed[..last_ws].trim();
            let name = trimmed[last_ws + 1..].trim().to_string();
            if name.is_empty() {
                continue;
            }
            for piece in id_list.split(',') {
                let id = piece.trim().to_string();
                if id.is_empty() || !ID_PATTERN.is_match(&id) {
                    continue;
                }
                diagram.class_assignments.push(ClassAssignment {
                    id,
                    name: name.clone(),
                    inline: false,
                    line: abs_line,
                });
            }
            continue;
        }

        // Edge line: contains `-->`. Chained forms are split into adjacent
        // pairs. Endpoints may carry inline `:::class`; we strip the suffix
        // and surface an InlineClassSyntax issue for each piece that uses
        // it.
        if line.contains("-->") {
            let pieces: Vec<&str> = line.split("-->").map(|p| p.trim()).collect();
            if pieces.len() < 2 {
                continue;
            }
            let mut endpoint_ids: Vec<String> = Vec::with_capacity(pieces.len());
            let mut piece_ok = true;
            for p in &pieces {
                let (id_opt, inline_class) = parse_endpoint(p);
                match id_opt {
                    Some(id) => {
                        if let Some(cls) = inline_class {
                            issues.push(Issue::InlineClassSyntax { line: abs_line });
                            diagram.class_assignments.push(ClassAssignment {
                                id: id.clone(),
                                name: cls,
                                inline: true,
                                line: abs_line,
                            });
                        }
                        endpoint_ids.push(id);
                    }
                    None => {
                        piece_ok = false;
                        break;
                    }
                }
            }
            if !piece_ok || endpoint_ids.len() < 2 {
                continue;
            }
            for w in endpoint_ids.windows(2) {
                diagram.edges.push(Edge {
                    src: w[0].clone(),
                    dst: w[1].clone(),
                    line: abs_line,
                });
            }
            continue;
        }

        // Node declaration: `<id>["<label>"]` (with optional inline class
        // on the id form `<id>:::<class>["<label>"]`).
        if let Some(caps) = NODE_DECL_PATTERN.captures(line) {
            let id = caps.get(1).unwrap().as_str().to_string();
            let label = caps.get(2).unwrap().as_str().to_string();
            diagram.nodes.push(Node {
                id,
                label,
                line: abs_line,
            });
            continue;
        }
        // Try the inline `<id>:::<class>["<label>"]` form: split on `[`
        // and parse the prefix with the inline-class regex.
        if let Some(bracket) = line.find("[\"") {
            let prefix = &line[..bracket];
            if let Some(caps) = ID_WITH_INLINE_CLASS.captures(prefix) {
                let id = caps.get(1).unwrap().as_str().to_string();
                let cls = caps.get(2).map(|m| m.as_str().to_string());
                let rest = &line[bracket..];
                if let Some(label_end) = rest.find("\"]") {
                    let label = rest[2..label_end].to_string();
                    diagram.nodes.push(Node {
                        id: id.clone(),
                        label,
                        line: abs_line,
                    });
                    if let Some(class_name) = cls {
                        issues.push(Issue::InlineClassSyntax { line: abs_line });
                        diagram.class_assignments.push(ClassAssignment {
                            id,
                            name: class_name,
                            inline: true,
                            line: abs_line,
                        });
                    }
                    continue;
                }
            }
        }

        // Any other shape (ragged decl, alternate bracket form, unknown
        // arrow) is silently skipped. The consequence -- a missing node
        // or edge -- surfaces through FC07's per-defect notices.
    }

    // Surface any class statement that references a class no `classDef`
    // declared in the same diagram (R9 acceptance criterion).
    for assign in &diagram.class_assignments {
        if !diagram.class_defs.contains(&assign.name) {
            issues.push(Issue::UndefinedClass {
                name: assign.name.clone(),
                line: assign.line,
            });
        }
    }

    (diagram, issues)
}

/// Parse an edge endpoint: returns `(id, inline-class)`. The inline-class
/// component is `Some(name)` when the endpoint used the `id:::class`
/// form, `None` otherwise. Returns `(None, None)` if the endpoint does
/// not match a canonical id.
fn parse_endpoint(raw: &str) -> (Option<String>, Option<String>) {
    let trimmed = raw.trim();
    if let Some(caps) = ID_WITH_INLINE_CLASS.captures(trimmed) {
        let id = caps.get(1).map(|m| m.as_str().to_string());
        let cls = caps.get(2).map(|m| m.as_str().to_string());
        return (id, cls);
    }
    (None, None)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::frontmatter::parse_doc_bytes;

    fn doc_from_markdown(md: &str) -> Doc {
        parse_doc_bytes("test.md", md.as_bytes()).expect("parse_doc_bytes failed")
    }

    fn extract_block(lines: &[&str]) -> (Diagram, Vec<Issue>) {
        extract_diagram(lines, 1)
    }

    // --- extract_diagram: canonical shapes ---

    #[test]
    fn extract_diagram_node_decl_canonical_shape() {
        let (d, issues) =
            extract_block(&["graph TD", r##"I111["#111: shared references"]"##]);
        assert_eq!(d.nodes.len(), 1);
        assert_eq!(d.nodes[0].id, "I111");
        assert_eq!(d.nodes[0].label, "#111: shared references");
        assert!(issues.is_empty());
    }

    #[test]
    fn extract_diagram_node_decl_with_leading_whitespace() {
        let (d, _) = extract_block(&["graph TD", r#"    I1["alpha"]"#, r#"  I2["beta"]"#]);
        assert_eq!(d.nodes.len(), 2);
        assert_eq!(d.nodes[0].id, "I1");
        assert_eq!(d.nodes[1].id, "I2");
    }

    #[test]
    fn extract_diagram_single_edge() {
        let (d, _) = extract_block(&["graph TD", "I1 --> I2"]);
        assert_eq!(d.edges.len(), 1);
        assert_eq!(d.edges[0].src, "I1");
        assert_eq!(d.edges[0].dst, "I2");
    }

    #[test]
    fn extract_diagram_chained_edges_expanded_into_pairs() {
        let (d, _) = extract_block(&["graph TD", "O1 --> O2 --> O3 --> O4"]);
        assert_eq!(d.edges.len(), 3);
        assert_eq!((d.edges[0].src.as_str(), d.edges[0].dst.as_str()), ("O1", "O2"));
        assert_eq!((d.edges[1].src.as_str(), d.edges[1].dst.as_str()), ("O2", "O3"));
        assert_eq!((d.edges[2].src.as_str(), d.edges[2].dst.as_str()), ("O3", "O4"));
    }

    #[test]
    fn extract_diagram_class_single_key() {
        let (d, _) = extract_block(&["graph TD", "classDef ready fill:#bbdefb", "class I1 ready"]);
        assert_eq!(d.class_assignments.len(), 1);
        assert_eq!(d.class_assignments[0].id, "I1");
        assert_eq!(d.class_assignments[0].name, "ready");
        assert!(!d.class_assignments[0].inline);
    }

    #[test]
    fn extract_diagram_class_multi_key_no_spaces() {
        let (d, _) = extract_block(&[
            "graph TD",
            "classDef blocked fill:#fff9c4",
            "class I1,I2,I3 blocked",
        ]);
        assert_eq!(d.class_assignments.len(), 3);
        assert_eq!(d.class_assignments[0].id, "I1");
        assert_eq!(d.class_assignments[2].id, "I3");
    }

    #[test]
    fn extract_diagram_class_multi_key_with_internal_whitespace_tolerated() {
        let (d, _) = extract_block(&[
            "graph TD",
            "classDef blocked fill:#fff9c4",
            "class I1, I2,  I3 blocked",
        ]);
        assert_eq!(d.class_assignments.len(), 3);
        assert_eq!(d.class_assignments[0].id, "I1");
        assert_eq!(d.class_assignments[1].id, "I2");
        assert_eq!(d.class_assignments[2].id, "I3");
    }

    #[test]
    fn extract_diagram_classdef_name_captured_styles_ignored() {
        let (d, _) = extract_block(&[
            "graph TD",
            "classDef done fill:#c8e6c9",
            "classDef tracksDesign fill:#FFE0B2,stroke:#F57C00,color:#000",
        ]);
        assert!(d.class_defs.contains("done"));
        assert!(d.class_defs.contains("tracksDesign"));
        assert_eq!(d.class_defs.len(), 2);
    }

    // --- edge-case behavior (spike's enumeration) ---

    #[test]
    fn extract_diagram_empty_body_emits_no_views() {
        let (d, issues) = extract_block(&["graph TD"]);
        assert!(d.nodes.is_empty());
        assert!(d.edges.is_empty());
        assert!(d.class_assignments.is_empty());
        assert!(d.class_defs.is_empty());
        assert!(issues.is_empty());
    }

    #[test]
    fn extract_diagram_header_flowchart_emits_issue_and_continues() {
        let (d, issues) = extract_block(&["flowchart TD", r#"I1["alpha"]"#]);
        assert_eq!(d.nodes.len(), 1, "extractor still parses body after flowchart");
        assert!(
            issues
                .iter()
                .any(|i| matches!(i, Issue::HeaderFlowchart { .. }))
        );
    }

    #[test]
    fn extract_diagram_header_unrecognized_emits_issue() {
        let (_, issues) = extract_block(&["something else", r#"I1["alpha"]"#]);
        assert!(
            issues
                .iter()
                .any(|i| matches!(i, Issue::HeaderUnrecognized { .. }))
        );
    }

    #[test]
    fn extract_diagram_ragged_node_decl_skipped() {
        // Unterminated label -- the line does not match the canonical
        // shape and is silently skipped (the missing-node consequence
        // surfaces in FC07's per-defect notice, not here).
        let (d, _) = extract_block(&["graph TD", r#"I1["unterminated"#, r#"I2["ok"]"#]);
        assert_eq!(d.nodes.len(), 1);
        assert_eq!(d.nodes[0].id, "I2");
    }

    #[test]
    fn extract_diagram_inline_class_on_edge_records_assignment_and_issue() {
        let (d, issues) =
            extract_block(&["graph TD", "classDef ready fill:#bbdefb", "I1:::ready --> I2"]);
        assert_eq!(d.edges.len(), 1);
        assert_eq!(d.edges[0].src, "I1");
        assert_eq!(d.edges[0].dst, "I2");
        assert!(d.class_assignments.iter().any(|a| a.id == "I1"
            && a.name == "ready"
            && a.inline));
        assert!(
            issues
                .iter()
                .any(|i| matches!(i, Issue::InlineClassSyntax { .. }))
        );
    }

    #[test]
    fn extract_diagram_inline_class_on_node_decl_records_assignment_and_issue() {
        let (d, issues) =
            extract_block(&["graph TD", "classDef ready fill:#bbdefb", r#"I1:::ready["alpha"]"#]);
        assert_eq!(d.nodes.len(), 1);
        assert_eq!(d.nodes[0].id, "I1");
        assert!(d.class_assignments.iter().any(|a| a.inline && a.name == "ready"));
        assert!(
            issues
                .iter()
                .any(|i| matches!(i, Issue::InlineClassSyntax { .. }))
        );
    }

    #[test]
    fn extract_diagram_comment_line_skipped() {
        let (d, _) = extract_block(&["graph TD", "%% this is a comment", r#"I1["alpha"]"#]);
        assert_eq!(d.nodes.len(), 1);
    }

    #[test]
    fn extract_diagram_subgraph_and_end_skipped() {
        let (d, _) = extract_block(&[
            "graph TD",
            "subgraph stuff",
            r#"I1["alpha"]"#,
            "end",
            r#"I2["beta"]"#,
        ]);
        assert_eq!(d.nodes.len(), 2);
    }

    #[test]
    fn extract_diagram_class_naming_undefined_class_emits_issue() {
        let (_, issues) =
            extract_block(&["graph TD", r#"I1["alpha"]"#, "class I1 nosuchclass"]);
        assert!(
            issues.iter().any(|i| matches!(
                i,
                Issue::UndefinedClass { name, .. } if name == "nosuchclass"
            )),
            "expected UndefinedClass(nosuchclass), got {:?}",
            issues
        );
    }

    #[test]
    fn extract_diagram_class_with_defined_class_emits_no_undefined_issue() {
        let (_, issues) = extract_block(&[
            "graph TD",
            "classDef blocked fill:#fff9c4",
            r#"I1["alpha"]"#,
            "class I1 blocked",
        ]);
        assert!(issues
            .iter()
            .all(|i| !matches!(i, Issue::UndefinedClass { .. })));
    }

    // --- Bounded iteration / total-over-arbitrary-input ---

    #[test]
    fn extract_diagram_very_long_line_does_not_panic() {
        let big = "graph TD".to_string();
        let long = "x".repeat(10_000);
        let (_d, _i) = extract_block(&[&big, &long]);
    }

    #[test]
    fn extract_diagram_arbitrary_utf8_does_not_panic() {
        let _ = extract_block(&["graph TD", "日本語の説明", "🚀 --> 🌟", r#"I1["α β γ"]"#]);
    }

    #[test]
    fn extract_diagram_deeply_nested_punctuation_does_not_panic() {
        let _ = extract_block(&["graph TD", "[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[["]);
    }

    // --- find_dependency_graph_block ---

    #[test]
    fn find_dependency_graph_block_returns_first_block() {
        let doc = doc_from_markdown(
            "---\nschema: plan/v1\nstatus: Active\nexecution_mode: multi-pr\nmilestone: \"foo\"\nissue_count: 1\n---\n\n## Dependency Graph\n\n```mermaid\ngraph TD\n    I1[\"alpha\"]\n```\n",
        );
        let loc = find_dependency_graph_block(&doc).expect("found");
        assert!(loc.issues.is_empty());
        // body_start is the line after the ```mermaid fence
        assert!(loc.body_start > 0);
        assert!(loc.body_end > loc.body_start);
    }

    #[test]
    fn find_dependency_graph_block_missing_block_emits_issue() {
        let doc = doc_from_markdown(
            "---\nschema: plan/v1\nstatus: Active\nexecution_mode: multi-pr\nmilestone: \"foo\"\nissue_count: 1\n---\n\n## Dependency Graph\n\nNo block here.\n",
        );
        let loc = find_dependency_graph_block(&doc).expect("section located");
        assert!(loc
            .issues
            .iter()
            .any(|i| matches!(i, Issue::MissingBlock { .. })));
    }

    #[test]
    fn find_dependency_graph_block_unterminated_fence_emits_issue() {
        let doc = doc_from_markdown(
            "---\nschema: plan/v1\nstatus: Active\nexecution_mode: multi-pr\nmilestone: \"foo\"\nissue_count: 1\n---\n\n## Dependency Graph\n\n```mermaid\ngraph TD\n    I1[\"alpha\"]\n",
        );
        let loc = find_dependency_graph_block(&doc).expect("section located");
        assert!(loc
            .issues
            .iter()
            .any(|i| matches!(i, Issue::UnterminatedFence { .. })));
    }

    #[test]
    fn find_dependency_graph_block_only_under_dependency_graph_section() {
        // A mermaid block under a different section is ignored.
        let doc = doc_from_markdown(
            "---\nschema: plan/v1\nstatus: Active\nexecution_mode: multi-pr\nmilestone: \"foo\"\nissue_count: 1\n---\n\n## Something Else\n\n```mermaid\ngraph TD\n```\n\n## Dependency Graph\n\nNo block here.\n",
        );
        let loc = find_dependency_graph_block(&doc).expect("section located");
        assert!(
            loc.issues
                .iter()
                .any(|i| matches!(i, Issue::MissingBlock { .. })),
            "block outside ## Dependency Graph is ignored; section emits MissingBlock"
        );
    }

    #[test]
    fn find_dependency_graph_block_multiple_blocks_first_wins() {
        let doc = doc_from_markdown(
            "---\nschema: plan/v1\nstatus: Active\nexecution_mode: multi-pr\nmilestone: \"foo\"\nissue_count: 1\n---\n\n## Dependency Graph\n\n```mermaid\ngraph TD\n    I1[\"alpha\"]\n```\n\n```mermaid\ngraph TD\n    I2[\"beta\"]\n```\n",
        );
        let loc = find_dependency_graph_block(&doc).expect("found");
        // Extract the first block; the second is ignored.
        let body_lines: Vec<&str> = (loc.body_start..loc.body_end)
            .map(|abs| doc.body[abs - 1].as_str())
            .collect();
        let (d, _) = extract_diagram(&body_lines, loc.body_start);
        assert_eq!(d.nodes.len(), 1);
        assert_eq!(d.nodes[0].id, "I1");
    }

    #[test]
    fn find_dependency_graph_block_no_section_returns_none() {
        let doc = doc_from_markdown(
            "---\nschema: plan/v1\nstatus: Active\nexecution_mode: multi-pr\nmilestone: \"foo\"\nissue_count: 1\n---\n\n## Status\n\nActive\n",
        );
        assert!(find_dependency_graph_block(&doc).is_none());
    }
}
