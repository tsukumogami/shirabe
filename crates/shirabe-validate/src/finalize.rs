//! Read-only completion-chain walk for `shirabe finalize-chain`.
//!
//! Issue 1 of `DESIGN-finalize-chain.md`: walk a finished PLAN's `upstream`
//! frontmatter chain, resolve each node's format via [`crate::detect_format`],
//! and build a typed [`Report`] describing the terminal action each node would
//! take -- **without mutating any document**. Applying the transitions, the
//! `## Implementation Issues` strip, the typed-error/exit-code surface, and the
//! `run-cascade.sh` refactor are later issues.
//!
//! ## Why the PLAN is a delete, not a transition
//!
//! The input PLAN's filename resolves through `detect_format` to the `Plan`
//! format, and `transition_spec("Plan")` returns `None` -- the `Plan` format
//! carries no transition behavior. A format with no `transition_spec` has no
//! terminal transition to apply, so it routes to the delete/handoff path. This
//! is asserted in [`walk_chain`] rather than hardcoded against the `"PLAN-"`
//! filename prefix.

use std::path::{Path, PathBuf};

use crate::frontmatter::{self, ParseError};
use crate::{detect_format, transition_spec};

/// The terminal action a chain node would take. The variants are exactly the
/// six dispatch outcomes plus the two walk-stopping conditions; the string
/// rendering (used as the report's `action` field) is fixed by
/// [`NodeAction::as_str`].
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum NodeAction {
    /// The input PLAN: deleted by the caller, never transitioned (its format
    /// carries no `transition_spec`).
    DeletePlan,
    /// A DESIGN node: strip Implementation Issues, then transition to Current.
    TransitionDesign,
    /// A PRD node: transition to Done.
    TransitionPrd,
    /// A BRIEF node: transition to Done.
    TransitionBrief,
    /// A ROADMAP node: handed back to the caller's roadmap handler; ends walk.
    RoadmapHandoff,
    /// A VISION node (or a cross-repo reference): the walk stops here. Carries
    /// a human-readable note.
    Stop(String),
    /// An unrecognized node (no format matched); carries the reason. Ends walk.
    Error(String),
}

impl NodeAction {
    /// The fixed string rendered as the report's `action` field.
    pub fn as_str(&self) -> &str {
        match self {
            NodeAction::DeletePlan => "delete_plan",
            NodeAction::TransitionDesign => "transition_design",
            NodeAction::TransitionPrd => "transition_prd",
            NodeAction::TransitionBrief => "transition_brief",
            NodeAction::RoadmapHandoff => "roadmap_handoff",
            NodeAction::Stop(_) => "stop",
            NodeAction::Error(_) => "error",
        }
    }

    /// The note carried by `Stop`/`Error`, or `None` for the others.
    fn note(&self) -> Option<&str> {
        match self {
            NodeAction::Stop(msg) | NodeAction::Error(msg) => Some(msg),
            _ => None,
        }
    }
}

/// One node in the walked chain.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct NodeEntry {
    /// The node's path as it appeared in the chain (the input path for the
    /// PLAN, the `upstream` value for each subsequent node).
    pub path: String,
    /// The resolved format name (`FormatSpec.name`), or `None` when no format
    /// matched (an `Error` node).
    pub format: Option<String>,
    /// The terminal action this node would take.
    pub action: NodeAction,
    /// The target status the action would transition to, when applicable
    /// (`Current` for DESIGN, `Done` for PRD/BRIEF). Read-only in this issue:
    /// recorded but not applied.
    pub target_status: Option<String>,
}

/// The ordered result of a chain walk.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Report {
    /// Nodes in walk order, starting with the input PLAN.
    pub nodes: Vec<NodeEntry>,
}

impl Report {
    /// Render the report as a JSON envelope in the same 2-space-indent,
    /// trailing-newline style as [`crate::Outcome::to_json`]: a top-level
    /// `nodes` array of node objects, each with `path`, `format`, `action`,
    /// and (when present) `target_status` / `note`.
    pub fn to_json(&self) -> String {
        let mut out = String::from("{\n");
        out.push_str("  \"nodes\": [");
        if self.nodes.is_empty() {
            out.push_str("]\n}\n");
            return out;
        }
        out.push('\n');
        for (i, node) in self.nodes.iter().enumerate() {
            out.push_str("    {\n");
            out.push_str(&format!("      \"path\": {},\n", json_string(&node.path)));
            match &node.format {
                Some(name) => {
                    out.push_str(&format!("      \"format\": {},\n", json_string(name)));
                }
                None => out.push_str("      \"format\": null,\n"),
            }
            // `target_status` and `note` are optional; build the trailing keys
            // so the final emitted key has no trailing comma.
            let mut tail: Vec<String> = Vec::new();
            if let Some(status) = &node.target_status {
                tail.push(format!("      \"target_status\": {}", json_string(status)));
            }
            if let Some(note) = node.action.note() {
                tail.push(format!("      \"note\": {}", json_string(note)));
            }
            // `action` is always present; it gets a trailing comma only when a
            // tail key follows.
            if tail.is_empty() {
                out.push_str(&format!(
                    "      \"action\": {}\n",
                    json_string(node.action.as_str())
                ));
            } else {
                out.push_str(&format!(
                    "      \"action\": {},\n",
                    json_string(node.action.as_str())
                ));
                out.push_str(&tail.join(",\n"));
                out.push('\n');
            }
            if i + 1 < self.nodes.len() {
                out.push_str("    },\n");
            } else {
                out.push_str("    }\n");
            }
        }
        out.push_str("  ]\n}\n");
        out
    }
}

/// Errors the read-only walk can fail with before any node is recorded (the
/// per-node `Error`/`Stop` cases are recorded *in* the report, not raised).
#[derive(Debug)]
pub enum WalkError {
    /// The input plan path is missing, not a regular file, or escapes the repo.
    InvalidPlan(String),
    /// Reading or parsing a node's frontmatter failed.
    Parse(String),
}

impl std::fmt::Display for WalkError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            WalkError::InvalidPlan(msg) => write!(f, "invalid plan: {}", msg),
            WalkError::Parse(msg) => write!(f, "parse error: {}", msg),
        }
    }
}

impl std::error::Error for WalkError {}

impl From<ParseError> for WalkError {
    fn from(value: ParseError) -> Self {
        WalkError::Parse(value.to_string())
    }
}

/// Walk a finished PLAN's `upstream` chain read-only and build a typed
/// [`Report`].
///
/// The input PLAN is validated (within its repo work tree, a regular file) and
/// recorded as a [`NodeAction::DeletePlan`] entry -- its format carries no
/// `transition_spec`, so it has no terminal transition (asserted, not
/// prefix-matched). The walk then follows each node's `upstream` frontmatter
/// field, resolving the format with [`detect_format`] and dispatching:
///
/// - `Design` -> [`NodeAction::TransitionDesign`] (target `Current`)
/// - `PRD` -> [`NodeAction::TransitionPrd`] (target `Done`)
/// - `Brief` -> [`NodeAction::TransitionBrief`] (target `Done`)
/// - `Roadmap` -> [`NodeAction::RoadmapHandoff`], then stop
/// - `VISION` -> [`NodeAction::Stop`], then stop
/// - unrecognized prefix -> [`NodeAction::Error`], then stop
/// - a cross-repo `owner/repo:path` upstream -> [`NodeAction::Stop`] with a
///   note (resolution is out of scope), then stop
///
/// No document is modified. The `target_status` per type is determined but not
/// applied.
pub fn walk_chain(plan_path: &str) -> Result<Report, WalkError> {
    let plan = Path::new(plan_path);
    if !plan.is_file() {
        return Err(WalkError::InvalidPlan(format!(
            "not a regular file: {}",
            plan_path
        )));
    }
    let repo_root = repo_root_for(plan);
    reject_outside_root(plan_path, &repo_root).map_err(WalkError::InvalidPlan)?;

    // The input PLAN is a delete node: its format must carry no transition
    // spec. Assert that, rather than hardcoding the "PLAN-" prefix.
    let plan_fmt = detect_format(basename(plan_path));
    debug_assert!(
        plan_fmt
            .as_ref()
            .map(|f| transition_spec(&f.name).is_none())
            .unwrap_or(true),
        "input PLAN's format must carry no transition_spec (delete, not transition)"
    );

    let mut nodes = vec![NodeEntry {
        path: plan_path.to_string(),
        format: plan_fmt.map(|f| f.name),
        action: NodeAction::DeletePlan,
        target_status: None,
    }];

    // Follow the chain from the PLAN's upstream.
    let mut current_doc_path = plan_path.to_string();
    loop {
        let upstream = match read_upstream(&current_doc_path)? {
            Some(value) if !value.trim().is_empty() => value.trim().to_string(),
            _ => break, // No upstream: chain complete.
        };

        // A cross-repo `owner/repo:path` reference is out of scope: stop.
        if is_cross_repo_ref(&upstream) {
            nodes.push(NodeEntry {
                path: upstream.clone(),
                format: None,
                action: NodeAction::Stop(format!(
                    "cross-repo reference '{}' is out of scope; stopping chain walk",
                    upstream
                )),
                target_status: None,
            });
            break;
        }

        let fmt = detect_format(basename(&upstream));
        let format_name = fmt.as_ref().map(|f| f.name.clone());

        let (action, target_status, stop) = match format_name.as_deref() {
            Some("Design") => (
                NodeAction::TransitionDesign,
                Some("Current".to_string()),
                false,
            ),
            Some("PRD") => (NodeAction::TransitionPrd, Some("Done".to_string()), false),
            Some("Brief") => (NodeAction::TransitionBrief, Some("Done".to_string()), false),
            Some("Roadmap") => (NodeAction::RoadmapHandoff, None, true),
            Some("VISION") => (
                NodeAction::Stop(format!(
                    "reached VISION node '{}'; handing off to the caller",
                    upstream
                )),
                None,
                true,
            ),
            _ => (
                NodeAction::Error(format!(
                    "upstream '{}' has an unrecognized filename prefix; stopping chain walk",
                    upstream
                )),
                None,
                true,
            ),
        };

        nodes.push(NodeEntry {
            path: upstream.clone(),
            format: format_name,
            action,
            target_status,
        });

        if stop {
            break;
        }

        current_doc_path = upstream;
    }

    Ok(Report { nodes })
}

/// Read a node's `upstream` frontmatter field, or `None` when absent.
fn read_upstream(doc_path: &str) -> Result<Option<String>, WalkError> {
    let doc = frontmatter::parse_doc(doc_path)?;
    Ok(doc.fields.get("upstream").map(|f| f.value.clone()))
}

/// Whether an upstream value is a cross-repo `owner/repo:path` reference. The
/// `owner/repo:` prefix carries a `:` before the first `/`-rooted path
/// segment; a plain repo-relative path (`docs/designs/DESIGN-x.md`) has no `:`.
fn is_cross_repo_ref(value: &str) -> bool {
    match value.find(':') {
        // A `:` that precedes the first path separator marks a repo selector.
        Some(colon) => {
            let before = &value[..colon];
            before.contains('/') && !before.contains(' ')
        }
        None => false,
    }
}

/// The final path component, matching the binary's `basename`.
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

/// The repo work-tree root containing `path`, or its parent directory when not
/// in a repo. Mirrors `transition.rs`'s anchor-on-the-doc's-directory approach.
fn repo_root_for(path: &Path) -> PathBuf {
    let dir = path.parent().unwrap_or(path);
    let output = std::process::Command::new("git")
        .arg("-C")
        .arg(dir)
        .arg("rev-parse")
        .arg("--show-toplevel")
        .output();
    if let Ok(out) = output {
        if out.status.success() {
            let root = String::from_utf8_lossy(&out.stdout).trim().to_string();
            if !root.is_empty() {
                return PathBuf::from(root);
            }
        }
    }
    dir.to_path_buf()
}

/// Reject `path` if it resolves outside `root`. Mirrors the transition module's
/// confinement guard so the chain walk cannot read outside the repo work tree.
fn reject_outside_root(path: &str, root: &Path) -> Result<(), String> {
    let p = Path::new(path);
    let abs = if p.is_absolute() {
        p.to_path_buf()
    } else {
        let cwd = std::env::current_dir().unwrap_or_else(|_| PathBuf::from("."));
        cwd.join(p)
    };
    let normalized = lexical_normalize(&abs);
    let root_norm = lexical_normalize(root);
    if normalized.starts_with(&root_norm) {
        Ok(())
    } else {
        Err(format!(
            "path resolves outside the repository work tree: {}",
            path
        ))
    }
}

/// Lexically resolve `.`/`..` without touching the filesystem.
fn lexical_normalize(abs: &Path) -> PathBuf {
    use std::path::Component;
    let mut out: Vec<std::ffi::OsString> = Vec::new();
    for comp in abs.components() {
        match comp {
            Component::ParentDir => {
                out.pop();
            }
            Component::CurDir => {}
            Component::RootDir => out.push(std::ffi::OsString::from("/")),
            Component::Normal(c) => out.push(c.to_os_string()),
            Component::Prefix(p) => out.push(p.as_os_str().to_os_string()),
        }
    }
    let mut result = PathBuf::new();
    for c in out {
        result.push(c);
    }
    result
}

/// Escape a string as a JSON string literal (2-space-indent envelope style,
/// matching `Outcome::to_json`'s helper).
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

    /// Create a fresh temp directory and return it. Each test gets its own so
    /// the relative `upstream` paths resolve against a known root.
    fn fresh_dir() -> PathBuf {
        let n = COUNTER.fetch_add(1, Ordering::SeqCst);
        let dir =
            std::env::temp_dir().join(format!("shirabe-finalize-{}-{}", std::process::id(), n));
        fs::create_dir_all(&dir).expect("mkdir temp");
        dir
    }

    /// Write a doc with the given basename and frontmatter `upstream` link
    /// (omitted when `upstream` is `None`) inside `dir`, returning its absolute
    /// path string.
    fn write_doc(dir: &Path, name: &str, upstream: Option<&str>) -> String {
        let body = match upstream {
            Some(u) => format!(
                "---\nschema: x/v1\nstatus: Draft\nupstream: {}\n---\n\n## Status\n\nDraft\n",
                u
            ),
            None => "---\nschema: x/v1\nstatus: Draft\n---\n\n## Status\n\nDraft\n".to_string(),
        };
        let path = dir.join(name);
        fs::write(&path, body).expect("write doc");
        path.to_string_lossy().into_owned()
    }

    #[test]
    fn full_chain_plan_design_prd_brief() {
        let dir = fresh_dir();
        // Build the chain leaf-first so upstream values are absolute paths
        // (resolved as-is, no repo-relative ambiguity in the test temp dir).
        let brief = write_doc(&dir, "BRIEF-feature.md", None);
        let prd = write_doc(&dir, "PRD-feature.md", Some(&brief));
        let design = write_doc(&dir, "DESIGN-feature.md", Some(&prd));
        let plan = write_doc(&dir, "PLAN-feature.md", Some(&design));

        let report = walk_chain(&plan).expect("walk ok");
        let actions: Vec<&str> = report.nodes.iter().map(|n| n.action.as_str()).collect();
        assert_eq!(
            actions,
            vec![
                "delete_plan",
                "transition_design",
                "transition_prd",
                "transition_brief"
            ]
        );
        // Target statuses per type.
        assert_eq!(report.nodes[0].target_status, None);
        assert_eq!(report.nodes[1].target_status, Some("Current".to_string()));
        assert_eq!(report.nodes[2].target_status, Some("Done".to_string()));
        assert_eq!(report.nodes[3].target_status, Some("Done".to_string()));
        // Resolved format names.
        assert_eq!(report.nodes[1].format.as_deref(), Some("Design"));
        assert_eq!(report.nodes[2].format.as_deref(), Some("PRD"));
        assert_eq!(report.nodes[3].format.as_deref(), Some("Brief"));
    }

    #[test]
    fn plan_with_no_upstream_is_delete_only() {
        let dir = fresh_dir();
        let plan = write_doc(&dir, "PLAN-solo.md", None);
        let report = walk_chain(&plan).expect("walk ok");
        assert_eq!(report.nodes.len(), 1);
        assert_eq!(report.nodes[0].action, NodeAction::DeletePlan);
        assert_eq!(report.nodes[0].format.as_deref(), Some("Plan"));
    }

    #[test]
    fn roadmap_node_is_handoff_and_stops() {
        let dir = fresh_dir();
        let roadmap = write_doc(&dir, "ROADMAP-theme.md", None);
        let plan = write_doc(&dir, "PLAN-theme.md", Some(&roadmap));
        let report = walk_chain(&plan).expect("walk ok");
        let actions: Vec<&str> = report.nodes.iter().map(|n| n.action.as_str()).collect();
        assert_eq!(actions, vec!["delete_plan", "roadmap_handoff"]);
        assert_eq!(report.nodes[1].format.as_deref(), Some("Roadmap"));
    }

    #[test]
    fn vision_node_stops() {
        let dir = fresh_dir();
        let vision = write_doc(&dir, "VISION-product.md", None);
        let plan = write_doc(&dir, "PLAN-product.md", Some(&vision));
        let report = walk_chain(&plan).expect("walk ok");
        let actions: Vec<&str> = report.nodes.iter().map(|n| n.action.as_str()).collect();
        assert_eq!(actions, vec!["delete_plan", "stop"]);
        assert_eq!(report.nodes[1].format.as_deref(), Some("VISION"));
        assert!(matches!(report.nodes[1].action, NodeAction::Stop(_)));
    }

    #[test]
    fn unrecognized_prefix_is_error_entry() {
        let dir = fresh_dir();
        let unknown = write_doc(&dir, "NOTES-misc.md", None);
        let plan = write_doc(&dir, "PLAN-misc.md", Some(&unknown));
        let report = walk_chain(&plan).expect("walk ok");
        let actions: Vec<&str> = report.nodes.iter().map(|n| n.action.as_str()).collect();
        assert_eq!(actions, vec!["delete_plan", "error"]);
        assert_eq!(report.nodes[1].format, None);
        assert!(matches!(report.nodes[1].action, NodeAction::Error(_)));
    }

    #[test]
    fn plan_is_classified_delete_not_transition() {
        // The PLAN format must carry no transition_spec; that is exactly why it
        // is delete-not-transition.
        let plan_fmt = detect_format("PLAN-x.md").expect("PLAN- resolves to a format");
        assert_eq!(plan_fmt.name, "Plan");
        assert!(
            transition_spec(&plan_fmt.name).is_none(),
            "Plan must carry no transition_spec"
        );

        let dir = fresh_dir();
        let plan = write_doc(&dir, "PLAN-x.md", None);
        let report = walk_chain(&plan).expect("walk ok");
        assert_eq!(report.nodes[0].action, NodeAction::DeletePlan);
    }

    #[test]
    fn cross_repo_upstream_stops_with_note() {
        let dir = fresh_dir();
        let plan = write_doc(&dir, "PLAN-xrepo.md", Some("owner/repo:docs/DESIGN-x.md"));
        let report = walk_chain(&plan).expect("walk ok");
        let actions: Vec<&str> = report.nodes.iter().map(|n| n.action.as_str()).collect();
        assert_eq!(actions, vec!["delete_plan", "stop"]);
        match &report.nodes[1].action {
            NodeAction::Stop(note) => assert!(note.contains("cross-repo")),
            other => panic!("expected Stop, got {:?}", other),
        }
    }

    #[test]
    fn to_json_envelope_shape() {
        let dir = fresh_dir();
        let prd = write_doc(&dir, "PRD-j.md", None);
        let plan = write_doc(&dir, "PLAN-j.md", Some(&prd));
        let json = walk_chain(&plan).expect("walk ok").to_json();
        assert!(json.starts_with("{\n  \"nodes\": [\n"));
        assert!(json.ends_with("  ]\n}\n"));
        assert!(json.contains("\"action\": \"delete_plan\""));
        assert!(json.contains("\"action\": \"transition_prd\""));
        assert!(json.contains("\"target_status\": \"Done\""));
        assert!(json.contains("\"format\": \"PRD\""));
    }

    #[test]
    fn cross_repo_ref_detection() {
        assert!(is_cross_repo_ref("owner/repo:docs/DESIGN-x.md"));
        assert!(!is_cross_repo_ref("docs/designs/DESIGN-x.md"));
        assert!(!is_cross_repo_ref("DESIGN-x.md"));
    }
}
