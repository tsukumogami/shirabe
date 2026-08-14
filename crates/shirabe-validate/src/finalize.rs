//! Completion-chain walk for `shirabe finalize-chain`.
//!
//! Walks a finished PLAN's `upstream` frontmatter chain, resolves each node's
//! format via [`crate::detect_format`], and builds a typed [`Report`]. The walk
//! has two modes ([`Mode`]):
//!
//! - [`Mode::Apply`] (the default for `finalize-chain <plan>`): each tactical
//!   node's terminal transition is applied in-process via
//!   [`crate::run_transition`] (Design->`Current`, PRD->`Done`, Brief->`Done`),
//!   and a DESIGN node has its stale `## Implementation Issues` section stripped
//!   first. The applied `old_status`/`new_status`/`new_path`/`moved` are recorded
//!   on each [`NodeEntry`].
//! - [`Mode::DryRun`] (the original read-only Issue 1 shape, exposed as
//!   `--dry-run`): no document is modified; the report records only what each
//!   node *would* do.
//!
//! The input PLAN is always reported for deletion and never transitioned
//! (finalize-chain never deletes); the caller owns the `git rm`. ROADMAP/VISION
//! end their branch; an unknown prefix is a per-node error. The typed-error/exit-code
//! surface and the `run-cascade.sh` refactor are later issues.
//!
//! ## The walk is multi-branch, and it asks before it retires
//!
//! A document may name several upstreams, so the walk is a worklist over every
//! entry rather than a loop over the first, and a shared ancestor reached
//! through two branches is visited once -- otherwise it would be transitioned
//! twice and the outcome would depend on traversal order. Branches are followed
//! in *written* order; nothing here sorts by path.
//!
//! Before any ancestor is transitioned the walk consults a referrer map built
//! once per invocation from the validator's own index
//! ([`crate::lifecycle::build_referrer_map`]). A document that this walk is not
//! itself retiring, that still names the ancestor as an upstream, and that has
//! not reached its own terminal state blocks the transition. The block is a
//! reported skip, not a failure: the walk continues, the exit code is
//! unaffected, and the node carries the blocking documents and their statuses.
//! This is the path that produced the dangling `upstream:` references already in
//! this repository.
//!
//! The carve-out is *documents this walk retires*, not *documents it visits*,
//! which earns one property for free: a blocked node is never transitioned, so
//! it stays non-terminal and remains a blocking referrer for its own ancestors.
//! The block propagates upward with no additional rule.
//!
//! ## The guard fails open, and says so
//!
//! The guard is only as good as the index behind it, and failing closed would
//! let one malformed document block every finalization in the repository. So an
//! index that comes up short does not stop the walk -- but every node the walk
//! then retires carries a note saying the check was incomplete. That covers the
//! partial failure as much as the total one: a single document dropped during
//! index construction yields a map missing whatever it referred to, which looks
//! from the inside exactly like a document nothing refers to. The note is the
//! only thing that tells those two apart, so it must reach the caller's rendered
//! output rather than sitting in the report for whoever thinks to read it --
//! `run-cascade.sh` puts it on the step's `detail` and logs it.
//!
//! ## Why the PLAN is a delete, not a transition
//!
//! The input PLAN's filename resolves through `detect_format` to the `Plan`
//! format. The PLAN's terminal lifecycle is `Active -> Done -> DELETED`: the
//! Active -> Done flip is an ephemeral in-process marker that bridges to the
//! deletion, and the caller (`run-cascade.sh`) owns both the flip and the
//! subsequent `git rm`. finalize-chain therefore reports the PLAN as a
//! delete node and applies no transition to it in-process — keeping the
//! ephemeral flip + delete co-located in the cascade script preserves the
//! atomic-commit shape the lifecycle check enforces. This is asserted in
//! [`walk_chain`] by checking the format is `Plan` (the only valid input
//! type), rather than hardcoded against the `"PLAN-"` filename prefix.

use std::collections::{HashMap, VecDeque};
use std::path::{Path, PathBuf};

use crate::coordination::parse_cross_repo_ref;
use crate::frontmatter::{self, ParseError};
use crate::gh::{ClientError, IssueState, IssueStateClient};
// The cross-repo discriminator lives in the shared `upstream` module now that
// all three `upstream:` readers normalize through one path; the walk reads the
// flag off the entry rather than calling it. The import keeps this module's own
// test for the discriminator pointed at the one implementation.
#[cfg(test)]
use crate::upstream::is_cross_repo_reference as is_cross_repo_ref;
use crate::upstream::UpstreamEntry;
use crate::{detect_format, run_transition, Flags, TransitionError};

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

/// Whether the chain walk applies each tactical transition or only reports what
/// it would do.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Mode {
    /// Apply each tactical node's terminal transition in-process (the default
    /// for `finalize-chain <plan>`). Mutates documents (and may `git mv` a
    /// DESIGN into `current/`).
    Apply,
    /// Walk read-only: resolve and report, but mutate nothing (`--dry-run`).
    DryRun,
}

/// A document whose reference blocks an ancestor's retirement: it still names
/// that ancestor as an upstream, this walk is not retiring it, and it has not
/// reached its own terminal state.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BlockingReferrer {
    /// The referring document's path, relative to the repo root when it lies
    /// inside it.
    pub path: String,
    /// The referring document's status when the referrer map was built.
    pub status: String,
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
    /// The target status the action transitions to, when applicable
    /// (`Current` for DESIGN, `Done` for PRD/BRIEF).
    pub target_status: Option<String>,
    /// The status the node held before the transition, populated only in
    /// [`Mode::Apply`] for a tactical node that was actually transitioned.
    pub old_status: Option<String>,
    /// The status the node holds after the transition (`Mode::Apply` only).
    pub new_status: Option<String>,
    /// The node's path after the transition (the post-move path for a DESIGN
    /// relocated into `current/`, equal to `path` otherwise). `Mode::Apply` only.
    pub new_path: Option<String>,
    /// Whether the node's file moved during the transition (`Mode::Apply` only).
    pub moved: Option<bool>,
    /// Whether the retirement guard blocked this node's transition. A blocked
    /// node is a reported skip: nothing was applied to it, the walk continued,
    /// and the exit code is unaffected.
    pub blocked: bool,
    /// The documents that blocked the transition, with their statuses. Empty
    /// unless `blocked`, and empty even then when the block came from a
    /// canonicalization failure rather than from a referrer.
    pub blocked_by: Vec<BlockingReferrer>,
    /// A rendered, human-readable note for this node -- the text field the
    /// automated caller surfaces. Set when the node was blocked; the
    /// `Stop`/`Error` actions carry their own note through
    /// [`NodeAction::note`].
    pub note: Option<String>,
}

impl NodeEntry {
    /// A node as discovery found it: classified, nothing decided or applied.
    fn new(
        path: String,
        format: Option<String>,
        action: NodeAction,
        target_status: Option<String>,
    ) -> Self {
        Self {
            path,
            format,
            action,
            target_status,
            old_status: None,
            new_status: None,
            new_path: None,
            moved: None,
            blocked: false,
            blocked_by: Vec::new(),
            note: None,
        }
    }
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
    /// and (when present) `target_status`, the applied `old_status` /
    /// `new_status` / `new_path` / `moved`, and a `note`.
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
            // `target_status`, the applied result fields, and `note` are all
            // optional; build the trailing keys so the final emitted key has no
            // trailing comma.
            let mut tail: Vec<String> = Vec::new();
            if let Some(status) = &node.target_status {
                tail.push(format!("      \"target_status\": {}", json_string(status)));
            }
            if let Some(old) = &node.old_status {
                tail.push(format!("      \"old_status\": {}", json_string(old)));
            }
            if let Some(new) = &node.new_status {
                tail.push(format!("      \"new_status\": {}", json_string(new)));
            }
            if let Some(new_path) = &node.new_path {
                tail.push(format!("      \"new_path\": {}", json_string(new_path)));
            }
            if let Some(moved) = node.moved {
                tail.push(format!("      \"moved\": {}", moved));
            }
            if node.blocked {
                tail.push("      \"blocked\": true".to_string());
            }
            if !node.blocked_by.is_empty() {
                let items: Vec<String> = node
                    .blocked_by
                    .iter()
                    .map(|b| {
                        format!(
                            "        {{\n          \"path\": {},\n          \"status\": {}\n        }}",
                            json_string(&b.path),
                            json_string(&b.status)
                        )
                    })
                    .collect();
                tail.push(format!(
                    "      \"blocked_by\": [\n{}\n      ]",
                    items.join(",\n")
                ));
            }
            // The node's own rendered note takes precedence; `Stop`/`Error`
            // carry theirs on the action.
            if let Some(note) = node.note.as_deref().or_else(|| node.action.note()) {
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

/// A chain-walk failure carrying a node-and-type-aware message and an exit
/// code, replacing the opaque error surface the bash cascade had (which
/// captured a bare `{` -- the engine's JSON error rendered to its first line --
/// with no awareness of why a transition was refused).
///
/// The `code` mirrors the single-document `transition` levels exactly:
/// - `0` is reserved for success (never carried by a `WalkError`).
/// - `1` tool error: a missing / unreadable / unparseable input, or a
///   path-validation failure (the value escapes the repo, is not a regular
///   file, or is a symlink).
/// - `2` lifecycle violation: an illegal or precondition-failing transition the
///   engine refused.
/// - `3` I/O error: a filesystem read/write or `git mv` failure during apply.
///
/// The subcommand renders this with [`WalkError::to_json`] in the same
/// `{ "success": false, "error": <message>, "code": <n> }` shape the
/// single-document `transition` uses, and exits with [`WalkError::code`].
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct WalkError {
    /// The 1/2/3 exit code, matching the transition levels.
    pub code: i32,
    /// The node-and-type-aware human-readable reason.
    pub message: String,
}

impl WalkError {
    fn new(code: i32, message: impl Into<String>) -> Self {
        Self {
            code,
            message: message.into(),
        }
    }

    /// The input plan path is missing, not a regular file, or escapes the repo:
    /// a tool error (exit 1).
    fn invalid_plan(message: impl Into<String>) -> Self {
        Self::new(1, message)
    }

    /// A path-validation failure on a chain node (outside the repo root, not a
    /// regular file, or a symlink): a tool error (exit 1).
    fn invalid_path(message: impl Into<String>) -> Self {
        Self::new(1, message)
    }

    /// Reading or parsing a node's frontmatter failed: a tool error (exit 1),
    /// matching the single-document transition's treatment of an unparseable
    /// input.
    fn parse(message: impl Into<String>) -> Self {
        Self::new(1, message)
    }

    /// A node's terminal transition was refused. Weaves the node path, its
    /// resolved artifact type, the attempted `from -> to` transition, and the
    /// engine's reason into one message, and carries the engine's own exit code
    /// (2 for a lifecycle violation, 1 for a tool error, 3 for I/O) so the
    /// chain's exit code is the first failing node's. This is the surface that
    /// replaces the bash cascade's bare `{`.
    fn transition(
        node_path: &str,
        node_type: Option<&str>,
        from: &str,
        to: &str,
        err: &TransitionError,
    ) -> Self {
        let type_label = node_type.unwrap_or("unknown type");
        Self::new(
            err.code,
            format!(
                "refused transition for {} ({}) {} -> {}: {}",
                node_path, type_label, from, to, err.message
            ),
        )
    }

    /// An I/O failure while preparing a node for transition (e.g. the DESIGN
    /// Implementation-Issues strip's read/write): an I/O error (exit 3).
    fn io(node_path: &str, node_type: Option<&str>, detail: &str) -> Self {
        let type_label = node_type.unwrap_or("unknown type");
        Self::new(
            3,
            format!(
                "I/O error preparing {} ({}): {}",
                node_path, type_label, detail
            ),
        )
    }

    /// The exit code to surface to the process, mirroring the transition levels.
    pub fn code(&self) -> i32 {
        self.code
    }

    /// Render the error JSON exactly as the single-document transition's
    /// `TransitionError::to_json` does: `{ "success": false, "error": <message>,
    /// "code": <code> }`, 2-space indented with a trailing newline.
    pub fn to_json(&self) -> String {
        format!(
            "{{\n  \"success\": false,\n  \"error\": {},\n  \"code\": {}\n}}\n",
            json_string(&self.message),
            self.code
        )
    }
}

impl std::fmt::Display for WalkError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "{} (code {})", self.message, self.code)
    }
}

impl std::error::Error for WalkError {}

impl From<ParseError> for WalkError {
    fn from(value: ParseError) -> Self {
        WalkError::parse(value.to_string())
    }
}

/// Walk a finished PLAN's `upstream` chain read-only and build a typed
/// [`Report`], applying nothing. Convenience wrapper for
/// `walk_chain_mode(plan_path, Mode::DryRun)`; preserves the Issue 1 surface.
pub fn walk_chain(plan_path: &str) -> Result<Report, WalkError> {
    walk_chain_mode(plan_path, Mode::DryRun)
}

/// Walk a finished PLAN's `upstream` chain and build a typed [`Report`].
///
/// The input PLAN is validated (within its repo work tree, a regular file) and
/// recorded as a [`NodeAction::DeletePlan`] entry -- its format carries no
/// `transition_spec`, so it has no terminal transition (asserted, not
/// prefix-matched). It is reported for deletion but never transitioned or
/// removed (finalize-chain never deletes; the caller owns the `git rm`). The
/// walk then follows each node's `upstream` frontmatter field, resolving the
/// format with [`detect_format`] and dispatching:
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
/// In [`Mode::Apply`] each tactical node's terminal transition is applied via
/// [`run_transition`] (a DESIGN has its `## Implementation Issues` section
/// stripped first), and the resulting `old_status`/`new_status`/`new_path`/
/// `moved` are recorded on the node. In [`Mode::DryRun`] nothing is modified and
/// only `target_status` is recorded.
///
/// The walk follows *every* `upstream` entry, in written order, visiting each
/// document once. Before a node is transitioned the retirement guard runs
/// against the pre-move path: a document outside the set this walk retires that
/// still names the node and has not reached its own terminal state blocks the
/// transition, which is reported on the node (`blocked`, `blocked_by`, `note`)
/// and skipped. The walk continues and the exit code is unaffected.
///
/// The whole chain is discovered and every decision taken before the first
/// document is touched: the guard's verdicts come from the corpus as it stood
/// when the walk started, so no node's fate depends on how far the walk had got
/// when it was reached.
pub fn walk_chain_mode(plan_path: &str, mode: Mode) -> Result<Report, WalkError> {
    let plan = Path::new(plan_path);
    // The input PLAN gets the same path validation every chain node does:
    // inside the repo root, a regular file, not a symlink. A failure is a tool
    // error (exit 1).
    let repo_root = repo_root_for(plan);
    validate_node_path(plan_path, &repo_root).map_err(WalkError::invalid_plan)?;

    // The input PLAN is a delete node: its format must be `Plan` (the only
    // valid input type for finalize-chain). The cascade script owns the
    // PLAN's Active -> Done -> DELETED sequence; finalize-chain neither
    // transitions nor deletes the PLAN. Assert against the format name
    // rather than hardcoding the "PLAN-" prefix.
    let plan_fmt = detect_format(basename(plan_path));
    debug_assert!(
        plan_fmt.as_ref().map(|f| f.name == "Plan").unwrap_or(true),
        "input PLAN's format must be `Plan` (delete, not transition); cascade owns Active -> Done"
    );

    // The referrer map is built once per walk, before anything is read or
    // written, so every verdict below is taken against the corpus as it stood
    // when the walk started. The index-construction errors are the fail-open
    // half of the guard: an unindexable corpus yields a thinner map rather than
    // a refusal, and every node the walk then retires says so.
    let (referrers, index_errors) = crate::lifecycle::build_referrer_map(&repo_root);
    let gap = referrer_map_gap(&repo_root, &index_errors);

    // ---- Discovery: every branch, in written order, each document once. ----
    let mut nodes: Vec<WalkNode> = vec![WalkNode {
        canonical: crate::lifecycle::canonicalize_indexed_path(plan),
        entry: NodeEntry::new(
            plan_path.to_string(),
            plan_fmt.map(|f| f.name),
            NodeAction::DeletePlan,
            None,
        ),
    }];
    let mut by_key: HashMap<String, usize> = HashMap::new();
    by_key.insert(nodes[0].key(), 0);
    let mut pending: VecDeque<usize> = VecDeque::from([0]);

    while let Some(i) = pending.pop_front() {
        if !expands(&nodes[i].entry.action) {
            continue;
        }
        // Read the node's own `upstream:` before anything has been applied, so
        // a DESIGN that is about to move is still read from where it is.
        let doc_path = nodes[i].entry.path.clone();
        for upstream in read_upstream_entries(&doc_path)? {
            let node = classify_node(upstream)?;
            let key = node.key();
            // A shared ancestor reached through two branches is one node, not
            // two: visiting it twice would transition it twice and make the
            // outcome depend on traversal order.
            if by_key.contains_key(&key) {
                continue;
            }
            let idx = nodes.len();
            let expandable = expands(&node.entry.action);
            nodes.push(node);
            by_key.insert(key, idx);
            if expandable {
                pending.push_back(idx);
            }
        }
    }

    // ---- The retirement guard: one verdict per node, before any mutation. ----
    let mut verdicts: Vec<Eval> = vec![Eval::Unresolved; nodes.len()];
    for i in 0..nodes.len() {
        decide(i, &nodes, &by_key, &referrers, &repo_root, &mut verdicts);
    }

    // ---- Apply. ----
    for i in 0..nodes.len() {
        let verdict = match &verdicts[i] {
            Eval::Done(v) => v.clone(),
            // `decide` resolves every node above; a still-unresolved node is
            // treated as not retired, which skips its transition.
            _ => Verdict::kept(),
        };
        if let Some(blocked) = verdict.block {
            nodes[i].entry.blocked = true;
            nodes[i].entry.blocked_by = blocked.blocked_by;
            nodes[i].entry.note = Some(blocked.note);
            continue;
        }
        // The fail-open note, on every node this walk retires on a transition.
        // It is recorded in both modes: a dry run that cannot see the whole
        // corpus is reporting a verdict it could not fully take, which is worth
        // exactly as much warning as applying one. The input PLAN carries no
        // note -- its deletion is unconditional and never consulted the map --
        // and a blocked node carries its block instead, since the hazard is
        // retiring something, not declining to.
        if verdict.retires && nodes[i].entry.target_status.is_some() {
            if let Some(gap) = &gap {
                nodes[i].entry.note = Some(gap.note_for(&nodes[i].entry.path));
            }
        }
        if mode != Mode::Apply || !verdict.retires {
            continue;
        }
        let path = nodes[i].entry.path.clone();
        let format = nodes[i].entry.format.clone();
        let target = match nodes[i].entry.target_status.clone() {
            Some(t) => t,
            // The input PLAN and the branch-ending nodes have no transition.
            None => continue,
        };
        // A DESIGN is stripped of its Implementation Issues section first, then
        // transitioned (and may move into `current/`).
        if matches!(nodes[i].entry.action, NodeAction::TransitionDesign) {
            strip_implementation_issues(&path)
                .map_err(|e| WalkError::io(&path, format.as_deref(), &e))?;
        }
        let outcome = run_transition(&path, &target, &Flags::default()).map_err(|e| {
            // The engine's TransitionError carries only its reason and code; we
            // know the node's resolved type and the attempted edge. Read the
            // node's current status best-effort for the `from` side so the
            // message names the full transition.
            let from = current_status_of(&path);
            WalkError::transition(
                &path,
                format.as_deref(),
                from.as_deref().unwrap_or("?"),
                &target,
                &e,
            )
        })?;
        let entry = &mut nodes[i].entry;
        entry.old_status = Some(outcome.old_status);
        entry.new_status = Some(outcome.new_status);
        entry.new_path = Some(outcome.new_path);
        entry.moved = Some(outcome.moved);
    }

    Ok(Report {
        nodes: nodes.into_iter().map(|n| n.entry).collect(),
    })
}

/// A discovered node: its report entry plus the canonical path the referrer
/// map is keyed by. `canonical` is `None` when the path does not canonicalize,
/// which blocks the node's transition -- the guard cannot ask what refers to a
/// document it cannot name.
struct WalkNode {
    entry: NodeEntry,
    canonical: Option<PathBuf>,
}

impl WalkNode {
    /// The identity two branches reconverging on one document must agree on:
    /// the canonical path, falling back to the written value for a node that
    /// has none (a cross-repo reference, or a path that failed to canonicalize).
    fn key(&self) -> String {
        match &self.canonical {
            Some(p) => p.to_string_lossy().into_owned(),
            None => self.entry.path.clone(),
        }
    }
}

/// Whether the walk follows a node's own `upstream:`. A branch-ending node
/// (ROADMAP handoff, VISION or cross-repo stop, unrecognized prefix) is not
/// expanded; every other node is, including a node the guard goes on to block,
/// so the block can propagate to its ancestors.
fn expands(action: &NodeAction) -> bool {
    matches!(
        action,
        NodeAction::DeletePlan
            | NodeAction::TransitionDesign
            | NodeAction::TransitionPrd
            | NodeAction::TransitionBrief
    )
}

/// Turn one `upstream:` entry into a walk node: validate its path, resolve its
/// format, and dispatch to the action its type takes.
fn classify_node(upstream: UpstreamEntry) -> Result<WalkNode, WalkError> {
    let path = upstream.value;

    // A cross-repo `owner/repo:path` reference is out of scope: this branch
    // ends here, and the walk never writes across a repo boundary.
    if upstream.cross_repo {
        return Ok(WalkNode {
            canonical: None,
            entry: NodeEntry::new(
                path.clone(),
                None,
                NodeAction::Stop(format!(
                    "cross-repo reference '{}' is out of scope; stopping chain walk",
                    path
                )),
                None,
            ),
        });
    }

    // Path validation before any read or transition: the untrusted `upstream`
    // value must resolve inside the repo root, be a regular file, and not be a
    // symlink (mirroring run-cascade.sh's `validate_upstream_path` intent). A
    // failure is a tool error (exit 1).
    let node_root = repo_root_for(Path::new(&path));
    validate_node_path(&path, &node_root).map_err(WalkError::invalid_path)?;

    let format_name = detect_format(basename(&path)).map(|f| f.name);
    let (action, target_status) = match format_name.as_deref() {
        Some("Design") => (NodeAction::TransitionDesign, Some("Current".to_string())),
        Some("PRD") => (NodeAction::TransitionPrd, Some("Done".to_string())),
        Some("Brief") => (NodeAction::TransitionBrief, Some("Done".to_string())),
        Some("Roadmap") => (NodeAction::RoadmapHandoff, None),
        Some("VISION") => (
            NodeAction::Stop(format!(
                "reached VISION node '{}'; handing off to the caller",
                path
            )),
            None,
        ),
        _ => (
            NodeAction::Error(format!(
                "upstream '{}' has an unrecognized filename prefix; stopping chain walk",
                path
            )),
            None,
        ),
    };

    Ok(WalkNode {
        canonical: crate::lifecycle::canonicalize_indexed_path(Path::new(&path)),
        entry: NodeEntry::new(path, format_name, action, target_status),
    })
}

/// Why a node was not retired.
#[derive(Debug, Clone)]
struct Block {
    blocked_by: Vec<BlockingReferrer>,
    note: String,
}

/// What the guard decided about one node.
#[derive(Debug, Clone)]
struct Verdict {
    /// Whether this walk retires the document. This is the carve-out the
    /// blocking rule reads: *retires*, not *visits*.
    retires: bool,
    /// Set when the node's transition was blocked.
    block: Option<Block>,
}

impl Verdict {
    /// Retired by this walk: the input PLAN, or a node whose transition the
    /// guard cleared.
    fn retired() -> Self {
        Self {
            retires: true,
            block: None,
        }
    }

    /// Not retired and not blocked: a branch-ending node the walk leaves alone.
    fn kept() -> Self {
        Self {
            retires: false,
            block: None,
        }
    }

    /// Blocked: not retired, and the report says by what.
    fn blocked(block: Block) -> Self {
        Self {
            retires: false,
            block: Some(block),
        }
    }
}

/// A node's guard state. `InProgress` guards against a cycle in the upstream
/// graph, which resolves as not-retired rather than recursing forever.
#[derive(Debug, Clone)]
enum Eval {
    Unresolved,
    InProgress,
    Done(Verdict),
}

/// Decide whether the walk retires node `i`, memoized in `verdicts`.
///
/// The rule: a document that this walk is not itself retiring, that still names
/// the node as an upstream, and that has not reached its own terminal state
/// blocks the transition. Retirement is decided recursively over the referrers,
/// which is what makes the block propagate: a blocked node is not retired, so it
/// keeps blocking its own ancestors.
fn decide(
    i: usize,
    nodes: &[WalkNode],
    by_key: &HashMap<String, usize>,
    referrers: &crate::lifecycle::ReferrerMap,
    repo_root: &Path,
    verdicts: &mut Vec<Eval>,
) -> Verdict {
    match &verdicts[i] {
        Eval::Done(v) => return v.clone(),
        // Reached through a cycle: treat as not retired, the conservative
        // reading (it then blocks, rather than silently clearing a transition).
        Eval::InProgress => return Verdict::kept(),
        Eval::Unresolved => {}
    }
    verdicts[i] = Eval::InProgress;

    let verdict = if matches!(nodes[i].entry.action, NodeAction::DeletePlan) {
        // The input PLAN counts as retired: finalize reports it for deletion and
        // the cascade performs the `git rm`. Were it not retired it would block
        // its own DESIGN and no chain could finalize.
        Verdict::retired()
    } else if nodes[i].entry.target_status.is_none() {
        // A branch-ending node is neither retired nor blocked.
        Verdict::kept()
    } else {
        match &nodes[i].canonical {
            // A canonicalization failure blocks: the walk and the map would
            // otherwise disagree about what names this document, and the guard
            // would silently miss its referrers.
            None => Verdict::blocked(Block {
                blocked_by: Vec::new(),
                note: format!(
                    "not retiring {}: its path could not be canonicalized, so the \
                     retirement guard cannot tell what still refers to it",
                    nodes[i].entry.path
                ),
            }),
            Some(canonical) => {
                let mut blockers: Vec<BlockingReferrer> = Vec::new();
                for referrer in referrers.get(canonical).map(Vec::as_slice).unwrap_or(&[]) {
                    let key = referrer.path.to_string_lossy().into_owned();
                    let retired_here = match by_key.get(&key) {
                        Some(&j) if j != i => {
                            decide(j, nodes, by_key, referrers, repo_root, verdicts).retires
                        }
                        // Not in this walk (or the node itself): nothing here
                        // retires it.
                        _ => false,
                    };
                    if retired_here || referrer.is_terminal() {
                        continue;
                    }
                    blockers.push(BlockingReferrer {
                        path: display_path(repo_root, &referrer.path),
                        status: referrer.status.clone(),
                    });
                }
                if blockers.is_empty() {
                    Verdict::retired()
                } else {
                    let rendered: Vec<String> = blockers
                        .iter()
                        .map(|b| format!("{} (status: {})", b.path, b.status))
                        .collect();
                    Verdict::blocked(Block {
                        note: format!(
                            "not retiring {}: still named as upstream by {}",
                            nodes[i].entry.path,
                            rendered.join(", ")
                        ),
                        blocked_by: blockers,
                    })
                }
            }
        }
    };

    verdicts[i] = Eval::Done(verdict.clone());
    verdict
}

/// The opening of the fail-open note. Both ways the map can come up short get
/// the same sentence, because they are the same hazard: the guard cleared a
/// retirement it could not fully check.
const GUARD_GAP_NOTE: &str = "retirement guard could not see the whole corpus";

/// How many unindexable documents the note names before it stops listing.
const GAP_NAMES_SHOWN: usize = 3;

/// A gap in the referrer map the guard's verdicts were taken against.
///
/// The guard is only as complete as the index behind it, and the index can come
/// up short in two ways. *Totally*: the corpus root does not resolve, nothing is
/// indexed, and the map is empty. *Partially*: individual documents fail to
/// parse or canonicalize during index construction and are dropped, so the map
/// is missing whatever they referred to. The partial case is the one that
/// actually happens -- one malformed document is a normal state for a repository
/// mid-edit -- and it is the silent one, since a thinner map looks exactly like
/// a document nothing refers to. Both produce this note.
struct ReferrerMapGap {
    /// What went short, rendered into the note after the shared opening.
    cause: String,
}

impl ReferrerMapGap {
    /// The note as it lands on one retired node.
    fn note_for(&self, path: &str) -> String {
        format!(
            "{}: {}; {} is retired without a complete check of what still refers to it",
            GUARD_GAP_NOTE, self.cause, path
        )
    }
}

/// Whether the referrer map the guard just consulted is known to be incomplete.
///
/// The total case is checked with the index's own canonicalization primitive
/// against the root, which is the one condition under which index construction
/// gives up before reading a single document. The partial case is the index's
/// own construction errors: each is a document that was dropped from the index
/// and whose upstreams are therefore missing from the map.
///
/// A directory the index skips because it cannot be read is neither -- it
/// produces no error and leaves the root resolvable -- so it stays outside what
/// this can report.
fn referrer_map_gap(
    repo_root: &Path,
    index_errors: &[crate::ValidationError],
) -> Option<ReferrerMapGap> {
    if crate::lifecycle::canonicalize_indexed_path(repo_root).is_none() {
        return Some(ReferrerMapGap {
            cause: format!(
                "the corpus root {} could not be resolved, so no document was indexed",
                repo_root.display()
            ),
        });
    }
    if index_errors.is_empty() {
        return None;
    }
    let mut named: Vec<&str> = index_errors.iter().map(|e| e.file.as_str()).collect();
    named.sort_unstable();
    named.dedup();
    let shown = named
        .iter()
        .take(GAP_NAMES_SHOWN)
        .copied()
        .collect::<Vec<&str>>()
        .join(", ");
    let listed = if named.len() > GAP_NAMES_SHOWN {
        format!("{}, and {} more", shown, named.len() - GAP_NAMES_SHOWN)
    } else {
        shown
    };
    Some(ReferrerMapGap {
        cause: format!(
            "{} document{} could not be indexed ({})",
            named.len(),
            if named.len() == 1 { "" } else { "s" },
            listed
        ),
    })
}

/// A referrer's path as the report shows it: relative to the repo root when it
/// lies inside it, so the note reads like the paths the author wrote.
fn display_path(repo_root: &Path, path: &Path) -> String {
    path.strip_prefix(repo_root)
        .unwrap_or(path)
        .to_string_lossy()
        .into_owned()
}

/// The outcome of the read-only cross-repo upstream verification pass.
///
/// This is the **verification-only** counterpart to the cross-repo WRITE wall in
/// [`walk_chain_mode`] (a cross-repo `upstream` is still a [`NodeAction::Stop`]
/// for the chain walk; finalize-chain never writes across a repo boundary). The
/// verification pass answers a narrower question: is the referenced cross-repo
/// upstream at its **terminal** status (its issue/PR resolved as merged/closed)?
///
/// A reference is verified only when the read resolves a terminal state.
/// Everything else — an unresolvable reference, a non-terminal (still-open)
/// upstream, or a malformed `owner/repo:path` — is an `Err` (fail closed, R21):
/// the pass never silently treats an unverifiable upstream as satisfied.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct CrossRepoVerification {
    /// The validated `owner/repo` slug the verification resolved against.
    pub slug: String,
    /// The cross-repo reference's repo-relative path component.
    pub path: String,
    /// The issue/PR number whose terminal status was confirmed.
    pub number: u64,
}

/// A read-only cross-repo upstream verification failure (fail closed, R21).
///
/// Carries a human-readable diagnostic naming the reference and why it could
/// not be confirmed terminal. The diagnostic never embeds a raw `gh` response
/// (F5): only the validated reference fields and a fixed reason phrase appear.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct VerifyError {
    /// Human-readable reason the upstream could not be confirmed terminal.
    pub message: String,
}

impl VerifyError {
    fn new(message: impl Into<String>) -> Self {
        Self {
            message: message.into(),
        }
    }
}

impl std::fmt::Display for VerifyError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "{}", self.message)
    }
}

impl std::error::Error for VerifyError {}

/// Decide a cross-repo upstream's verification outcome from an *already
/// resolved* read result. This is the pure core of the verification pass: it
/// holds the fail-closed (R21) terminal-status policy and is unit-testable
/// without any network.
///
/// - `Ok(IssueState::Closed)` is the only verified (terminal) outcome.
/// - `Ok(IssueState::Open)` is a non-terminal upstream: fail closed.
/// - `Err(_)` is an unresolvable reference: fail closed. The `gh` payload is
///   never embedded in the diagnostic (F5); only a fixed reason phrase derived
///   from the error variant appears.
///
/// **F1-UNSAFE diagnostic — do not surface verbatim.** The `VerifyError`
/// message built here interpolates the *raw* `slug` / `path` / `number`, so it
/// can leak a private cross-repo identifier in the clear. It is safe only
/// because the merge-gate caller discards this message and substitutes an
/// F1-redacted label. Any private/coordination-node caller MUST route the
/// reference through [`crate::coordination::redacted_label`] (the opaque node
/// id) and must NOT print this message as-is.
fn decide_terminal(
    slug: &str,
    path: &str,
    number: u64,
    read: Result<IssueState, ClientError>,
) -> Result<CrossRepoVerification, VerifyError> {
    match read {
        Ok(IssueState::Closed) => Ok(CrossRepoVerification {
            slug: slug.to_string(),
            path: path.to_string(),
            number,
        }),
        Ok(IssueState::Open) => Err(VerifyError::new(format!(
            "cross-repo upstream {}:{}#{} is not at a terminal status (still open); \
             halting per fail-closed verification",
            slug, path, number
        ))),
        Err(err) => {
            // Map the client error to a fixed reason phrase. The raw `gh`
            // response / Malformed payload is intentionally never interpolated
            // (F5: never log raw responses).
            let reason = match err {
                ClientError::Auth => "gh is not authenticated",
                ClientError::NotFound => "the referenced issue/PR was not found",
                ClientError::Forbidden => "access to the referenced repo was forbidden",
                ClientError::RateLimit => "gh reported a rate limit",
                ClientError::Network => "the gh read failed (network/spawn/timeout)",
                ClientError::Malformed(_) => "the gh response was malformed",
            };
            Err(VerifyError::new(format!(
                "cross-repo upstream {}:{}#{} could not be resolved ({}); \
                 halting per fail-closed verification",
                slug, path, number, reason
            )))
        }
    }
}

/// Read-only cross-repo upstream verification pass.
///
/// Given a cross-repo `owner/repo:path` upstream reference and the issue/PR
/// `number` that tracks it, verify the referenced upstream is at a **terminal**
/// status (resolved as merged/closed) using a read-only [`IssueStateClient`].
/// This performs **no cross-repo write** — it is the read-only verification gate
/// described in `references/coordination-strategy.md` (Decision C). The
/// finalize-chain WRITE wall is unchanged: a cross-repo `upstream` still stops
/// the chain walk ([`NodeAction::Stop`]); this is an additional read-only
/// capability the coordination/gate path calls.
///
/// The reference is parsed and validated by [`parse_cross_repo_ref`] (F2:
/// owner/repo charset, path lexically confined, no `..`/absolute/newline/NUL)
/// before any read. The read goes through the supplied client (F5: read-only
/// `gh api`, no token in process, 4 MiB cap, raw response never logged — the
/// client owns those invariants; this pass never embeds a raw response in its
/// diagnostic).
///
/// **Fail closed (R21):** a malformed reference, an unresolvable read, or a
/// non-terminal (still-open) upstream all return `Err(VerifyError)` with a clear
/// diagnostic. The pass never silently skips a reference and never treats an
/// unverifiable upstream as satisfied.
pub fn verify_cross_repo_upstream_terminal(
    reference: &str,
    number: u64,
    client: &dyn IssueStateClient,
) -> Result<CrossRepoVerification, VerifyError> {
    // F2: parse + validate every component before use. A failing reference
    // halts (R21) rather than being silently skipped.
    let parsed = parse_cross_repo_ref(reference)
        .map_err(|msg| VerifyError::new(format!("invalid cross-repo reference: {}", msg)))?;

    // Read-only status query through the client (F5 invariants owned by the
    // client). The decision policy is the pure, unit-testable core.
    let read = client.fetch_issue_state(&parsed.owner, &parsed.repo, number);
    decide_terminal(&parsed.slug(), &parsed.path, number, read)
}

/// Port of `run-cascade.sh`'s `strip_implementation_issues` (awk, lines
/// 182-200): idempotently remove the `## Implementation Issues` section from a
/// DESIGN doc, from that heading to (but not including) the next `## ` heading
/// or EOF. A no-op when the section is absent. Writes the result back in place,
/// preserving the file's trailing-newline state.
fn strip_implementation_issues(doc_path: &str) -> Result<(), String> {
    let original = std::fs::read_to_string(doc_path)
        .map_err(|e| format!("failed to read {}: {}", doc_path, e))?;

    // Fast path / idempotency guard: nothing to strip when the heading is
    // absent (matching the bash `grep -q` check). Avoids a needless rewrite.
    if !original.lines().any(|l| l == "## Implementation Issues") {
        return Ok(());
    }

    let has_trailing_newline = original.ends_with('\n');
    let mut out_lines: Vec<&str> = Vec::new();
    let mut skip = false;
    for line in original.split('\n') {
        // awk: `/^## Implementation Issues$/ { skip=1; next }`
        if line == "## Implementation Issues" {
            skip = true;
            continue;
        }
        // awk: `skip && /^## / { skip=0 }` -- the next `## ` heading ends the
        // skipped section and is itself kept.
        if skip && line.starts_with("## ") {
            skip = false;
        }
        if !skip {
            out_lines.push(line);
        }
    }

    let mut joined = out_lines.join("\n");
    if has_trailing_newline && !joined.ends_with('\n') {
        joined.push('\n');
    }
    std::fs::write(doc_path, joined).map_err(|e| format!("failed to write {}: {}", doc_path, e))?;
    Ok(())
}

/// Read the `upstream` entries the walk follows from one node, in the order
/// the author wrote them. The list is empty when the field names none:
/// absent, empty, an unfilled `<placeholder>`, or a shape that is neither a
/// scalar nor a sequence.
///
/// Entries come from [`crate::upstream::upstream_entries`], the one
/// normalization path all three `upstream:` readers share. Every entry is
/// followed; written order is the branch order, and nothing here sorts by
/// path -- ordering by filename is the dependence the rest of this change
/// removes.
fn read_upstream_entries(doc_path: &str) -> Result<Vec<UpstreamEntry>, WalkError> {
    let doc = frontmatter::parse_doc(doc_path)?;
    Ok(crate::upstream::upstream_entries(&doc))
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

/// Validate a chain node's path before any read or transition, mirroring
/// run-cascade.sh's `validate_upstream_path` intent: the path must resolve
/// inside the repo `root`, be a regular file, and not be a symlink. Returns a
/// descriptive message on failure (the caller maps it to a tool error, exit 1).
///
/// Tracked-in-git is intentionally *not* re-checked here: `run_transition`
/// already operates only on on-disk files, the apply path stages its own moves,
/// and the unit tests use temp git repos where a just-written node may be staged
/// but not yet a tracked-at-HEAD file. The confinement + regular-file + no-
/// symlink checks are the security-relevant ones the design calls out.
fn validate_node_path(path: &str, root: &Path) -> Result<(), String> {
    reject_outside_root(path, root)?;
    let p = Path::new(path);
    // `symlink_metadata` does not follow the final symlink, so a symlinked node
    // is caught here rather than silently resolving to its target.
    match std::fs::symlink_metadata(p) {
        Ok(meta) => {
            let ft = meta.file_type();
            if ft.is_symlink() {
                return Err(format!("path is a symlink, not a regular file: {}", path));
            }
            if !ft.is_file() {
                return Err(format!("not a regular file: {}", path));
            }
            Ok(())
        }
        Err(e) => Err(format!("cannot stat path {}: {}", path, e)),
    }
}

/// Best-effort read of a node's current `status` for the refused-transition
/// message. Returns `None` when the doc cannot be parsed or carries no status;
/// the message then renders `?` for the `from` side.
fn current_status_of(doc_path: &str) -> Option<String> {
    let doc = frontmatter::parse_doc(doc_path).ok()?;
    doc.fields.get("status").map(|f| f.value.trim().to_string())
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
    use crate::transition_spec;
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
        // The PLAN format is the delete-target input type: finalize-chain
        // reports it but never applies its Active -> Done transition. The
        // cascade script owns the on-disk Active -> Done flip immediately
        // before the git rm, keeping the ephemeral marker co-located with
        // the deletion.
        let plan_fmt = detect_format("PLAN-x.md").expect("PLAN- resolves to a format");
        assert_eq!(plan_fmt.name, "Plan");
        // Plan now carries a transition_spec (Draft -> Active -> Done)
        // for direct use via `shirabe transition`. finalize-chain still
        // treats Plan as a delete node — it does not apply the
        // Active -> Done transition itself; the cascade does.
        assert!(
            transition_spec(&plan_fmt.name).is_some(),
            "Plan carries a transition_spec under the unified lifecycle"
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

    // ---- Apply mode (mutating; isolated to temp git repos) ----

    /// Create a fresh temp git repo and return its root. Apply-mode transitions
    /// `git mv` a DESIGN, so the docs must live in a real work tree that is
    /// entirely disposable -- never the real repo's `docs/`.
    fn fresh_git_repo() -> PathBuf {
        let n = COUNTER.fetch_add(1, Ordering::SeqCst);
        let root = std::env::temp_dir().join(format!(
            "shirabe-finalize-repo-{}-{}",
            std::process::id(),
            n
        ));
        fs::create_dir_all(&root).expect("mkdir repo");
        run_git(&root, &["init", "-q"]);
        run_git(&root, &["config", "user.email", "t@t"]);
        run_git(&root, &["config", "user.name", "t"]);
        root
    }

    fn run_git(root: &Path, args: &[&str]) {
        let status = std::process::Command::new("git")
            .arg("-C")
            .arg(root)
            .args(args)
            .status()
            .expect("run git");
        assert!(status.success(), "git {:?} failed", args);
    }

    /// Write a doc at `rel_path` inside the repo (creating parent dirs) with the
    /// given starting `status`, an optional absolute `upstream` link, `git add`
    /// it so `git mv` can track it, and return its absolute path. `extra_body` is
    /// appended after the Status section (used to inject an `## Implementation
    /// Issues` section).
    ///
    /// `status` matters because BRIEF transitions on a graph (Draft -> Accepted
    /// -> Done): a finalized chain's BRIEF is already `Accepted` when its
    /// downstream completes, so `Done` is a legal edge.
    fn write_repo_doc(
        root: &Path,
        rel_path: &str,
        status: &str,
        upstream: Option<&str>,
        extra_body: &str,
    ) -> String {
        let fm = match upstream {
            Some(u) => format!(
                "---\nschema: x/v1\nstatus: {0}\nupstream: {1}\n---\n\n## Status\n\n{0}\n{2}",
                status, u, extra_body
            ),
            None => format!(
                "---\nschema: x/v1\nstatus: {0}\n---\n\n## Status\n\n{0}\n{1}",
                status, extra_body
            ),
        };
        let path = root.join(rel_path);
        fs::create_dir_all(path.parent().unwrap()).expect("mkdir doc dir");
        fs::write(&path, fm).expect("write doc");
        run_git(root, &["add", rel_path]);
        path.to_string_lossy().into_owned()
    }

    #[test]
    fn apply_full_chain_transitions_and_moves_design() {
        let root = fresh_git_repo();
        // Build leaf-first so upstream values are absolute paths into the repo.
        // A finalized chain's BRIEF is already Accepted (Done is a legal edge);
        // PRD/DESIGN are membership-only, so any starting status transitions.
        let brief = write_repo_doc(&root, "docs/briefs/BRIEF-feat.md", "Accepted", None, "");
        let prd = write_repo_doc(&root, "docs/prds/PRD-feat.md", "Draft", Some(&brief), "");
        let design = write_repo_doc(
            &root,
            "docs/designs/DESIGN-feat.md",
            "Draft",
            Some(&prd),
            "",
        );
        let plan = write_repo_doc(&root, "docs/plans/PLAN-feat.md", "Draft", Some(&design), "");

        let report = walk_chain_mode(&plan, Mode::Apply).expect("apply ok");

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

        // DESIGN: Draft -> Current, moved into docs/designs/current/.
        let d = &report.nodes[1];
        assert_eq!(d.old_status.as_deref(), Some("Draft"));
        assert_eq!(d.new_status.as_deref(), Some("Current"));
        assert_eq!(d.moved, Some(true));
        assert_eq!(
            d.new_path.as_deref(),
            Some("docs/designs/current/DESIGN-feat.md")
        );
        // The file physically moved into current/ and the old path is gone.
        assert!(root.join("docs/designs/current/DESIGN-feat.md").is_file());
        assert!(!root.join("docs/designs/DESIGN-feat.md").exists());

        // PRD + BRIEF: Draft -> Done, no move.
        let p = &report.nodes[2];
        assert_eq!(p.old_status.as_deref(), Some("Draft"));
        assert_eq!(p.new_status.as_deref(), Some("Done"));
        assert_eq!(p.moved, Some(false));
        let b = &report.nodes[3];
        assert_eq!(b.old_status.as_deref(), Some("Accepted"));
        assert_eq!(b.new_status.as_deref(), Some("Done"));
        assert_eq!(b.moved, Some(false));

        // On-disk status assertions for the non-moving docs.
        assert!(fs::read_to_string(&prd).unwrap().contains("status: Done"));
        assert!(fs::read_to_string(&brief).unwrap().contains("status: Done"));
        // The moved design holds Current at its new location.
        let moved_design = fs::read_to_string(root.join("docs/designs/current/DESIGN-feat.md"))
            .expect("read moved design");
        assert!(moved_design.contains("status: Current"));

        // The PLAN is reported for deletion only -- never transitioned, never
        // removed.
        assert_eq!(report.nodes[0].action, NodeAction::DeletePlan);
        assert!(report.nodes[0].old_status.is_none());
        assert!(root.join("docs/plans/PLAN-feat.md").is_file());
    }

    #[test]
    fn apply_strips_implementation_issues_before_design_transition() {
        let root = fresh_git_repo();
        // DESIGN with an Implementation Issues section followed by another `##`.
        let extra = "\n## Implementation Issues\n\n- issue 1\n- issue 2\n\n## References\n\nfoo\n";
        let design = write_repo_doc(&root, "docs/designs/DESIGN-strip.md", "Draft", None, extra);
        let plan = write_repo_doc(
            &root,
            "docs/plans/PLAN-strip.md",
            "Draft",
            Some(&design),
            "",
        );

        let report = walk_chain_mode(&plan, Mode::Apply).expect("apply ok");
        assert_eq!(report.nodes[1].new_status.as_deref(), Some("Current"));

        let moved = fs::read_to_string(root.join("docs/designs/current/DESIGN-strip.md"))
            .expect("read moved design");
        // The Implementation Issues section is gone; the following `## References`
        // section is preserved.
        assert!(!moved.contains("## Implementation Issues"));
        assert!(!moved.contains("- issue 1"));
        assert!(moved.contains("## References"));
        assert!(moved.contains("foo"));
    }

    #[test]
    fn strip_implementation_issues_is_idempotent() {
        let root = fresh_git_repo();
        // No Implementation Issues section: strip is a no-op (bytes unchanged).
        let design = write_repo_doc(
            &root,
            "docs/designs/DESIGN-noimpl.md",
            "Draft",
            None,
            "body\n",
        );
        let before = fs::read_to_string(&design).unwrap();
        strip_implementation_issues(&design).expect("strip ok");
        assert_eq!(fs::read_to_string(&design).unwrap(), before);

        // With a section, the first strip removes it and a second strip is a
        // no-op.
        let extra = "\n## Implementation Issues\n\n- x\n\n## Next\n\ny\n";
        let design2 = write_repo_doc(&root, "docs/designs/DESIGN-impl.md", "Draft", None, extra);
        strip_implementation_issues(&design2).expect("strip ok");
        let after_first = fs::read_to_string(&design2).unwrap();
        assert!(!after_first.contains("## Implementation Issues"));
        strip_implementation_issues(&design2).expect("strip idempotent");
        assert_eq!(fs::read_to_string(&design2).unwrap(), after_first);
    }

    #[test]
    fn apply_reports_plan_delete_without_mutating_it() {
        let root = fresh_git_repo();
        let prd = write_repo_doc(&root, "docs/prds/PRD-keep.md", "Draft", None, "");
        let plan = write_repo_doc(&root, "docs/plans/PLAN-keep.md", "Draft", Some(&prd), "");
        let plan_before = fs::read_to_string(&plan).unwrap();

        let report = walk_chain_mode(&plan, Mode::Apply).expect("apply ok");

        // PLAN node: delete action, no applied transition fields, file intact.
        assert_eq!(report.nodes[0].action, NodeAction::DeletePlan);
        assert!(report.nodes[0].old_status.is_none());
        assert!(report.nodes[0].new_status.is_none());
        assert!(report.nodes[0].moved.is_none());
        assert_eq!(fs::read_to_string(&plan).unwrap(), plan_before);
        assert!(root.join("docs/plans/PLAN-keep.md").is_file());

        // The PRD was transitioned.
        assert_eq!(report.nodes[1].new_status.as_deref(), Some("Done"));
    }

    #[test]
    fn dry_run_mutates_nothing() {
        let root = fresh_git_repo();
        let prd = write_repo_doc(&root, "docs/prds/PRD-dry.md", "Draft", None, "");
        let design = write_repo_doc(&root, "docs/designs/DESIGN-dry.md", "Draft", Some(&prd), "");
        let plan = write_repo_doc(&root, "docs/plans/PLAN-dry.md", "Draft", Some(&design), "");
        let prd_before = fs::read_to_string(&prd).unwrap();
        let design_before = fs::read_to_string(&design).unwrap();

        let report = walk_chain_mode(&plan, Mode::DryRun).expect("dry-run ok");
        // No applied result fields, files untouched, design not moved.
        assert!(report.nodes[1].new_status.is_none());
        assert!(report.nodes[1].moved.is_none());
        assert_eq!(fs::read_to_string(&prd).unwrap(), prd_before);
        assert_eq!(fs::read_to_string(&design).unwrap(), design_before);
        assert!(root.join("docs/designs/DESIGN-dry.md").is_file());
        assert!(!root.join("docs/designs/current/DESIGN-dry.md").exists());
    }

    #[test]
    fn apply_json_includes_applied_fields() {
        let root = fresh_git_repo();
        let prd = write_repo_doc(&root, "docs/prds/PRD-json.md", "Draft", None, "");
        let plan = write_repo_doc(&root, "docs/plans/PLAN-json.md", "Draft", Some(&prd), "");
        let json = walk_chain_mode(&plan, Mode::Apply)
            .expect("apply ok")
            .to_json();
        assert!(json.contains("\"old_status\": \"Draft\""));
        assert!(json.contains("\"new_status\": \"Done\""));
        assert!(json.contains("\"new_path\""));
        assert!(json.contains("\"moved\": false"));
    }

    // ---- Issue 3: typed errors + exit-code contract ----

    /// Exit-code level 0: a clean apply returns `Ok`, so the subcommand exits 0.
    /// (The full apply chain is covered above; this asserts the success arm of
    /// the contract explicitly.)
    #[test]
    fn exit_code_0_clean_success() {
        let root = fresh_git_repo();
        let prd = write_repo_doc(&root, "docs/prds/PRD-ok.md", "Draft", None, "");
        let plan = write_repo_doc(&root, "docs/plans/PLAN-ok.md", "Draft", Some(&prd), "");
        let report = walk_chain_mode(&plan, Mode::Apply).expect("apply ok");
        assert_eq!(report.nodes[1].new_status.as_deref(), Some("Done"));
    }

    /// Exit-code level 2: a lifecycle violation. This is exactly the bare-`{`
    /// scenario from the design -- a graph-constrained BRIEF still at Draft,
    /// asked to go straight to Done (an illegal edge: it must be Accepted
    /// first). The engine refuses with code 2, and the chain surfaces a full
    /// node-and-type-aware message instead of a brace.
    #[test]
    fn exit_code_2_lifecycle_violation_brief_draft_to_done() {
        let root = fresh_git_repo();
        // BRIEF still at Draft: Draft -> Done is illegal (must be Accepted first).
        let brief = write_repo_doc(&root, "docs/briefs/BRIEF-bad.md", "Draft", None, "");
        let plan = write_repo_doc(&root, "docs/plans/PLAN-bad.md", "Draft", Some(&brief), "");

        let err = walk_chain_mode(&plan, Mode::Apply).expect_err("must refuse");
        assert_eq!(err.code(), 2, "lifecycle violation is exit 2");
        // The message names the node path, its type, the attempted transition,
        // and the engine's reason -- never a bare fragment.
        assert!(err.message.contains("BRIEF-bad.md"), "names the node path");
        assert!(err.message.contains("Brief"), "names the resolved type");
        assert!(
            err.message.contains("Draft -> Done"),
            "names the transition"
        );
        assert!(
            err.message.contains("must be Accepted first"),
            "carries the engine's reason: {}",
            err.message
        );
    }

    /// Exit-code level 1: a tool error from a path-validation failure. The PLAN
    /// names an `upstream` that does not exist on disk; validation fails before
    /// any read or transition.
    #[test]
    fn exit_code_1_tool_error_missing_upstream() {
        let root = fresh_git_repo();
        let missing = root
            .join("docs/prds/PRD-gone.md")
            .to_string_lossy()
            .into_owned();
        let plan = write_repo_doc(
            &root,
            "docs/plans/PLAN-miss.md",
            "Draft",
            Some(&missing),
            "",
        );

        let err = walk_chain_mode(&plan, Mode::Apply).expect_err("must fail");
        assert_eq!(err.code(), 1, "missing/unvalidatable upstream is exit 1");
        assert!(
            err.message.contains("PRD-gone.md"),
            "names the offending path: {}",
            err.message
        );
    }

    /// Exit-code level 1: a path-validation failure where the upstream is a
    /// symlink (rejected as not a regular file), mirroring
    /// `validate_upstream_path`'s symlink guard.
    #[test]
    fn exit_code_1_tool_error_symlink_upstream() {
        let root = fresh_git_repo();
        // A real PRD plus a symlink pointing at it; the chain links to the
        // symlink, which must be rejected.
        let real = write_repo_doc(&root, "docs/prds/PRD-real.md", "Draft", None, "");
        let link = root.join("docs/prds/PRD-link.md");
        std::os::unix::fs::symlink(&real, &link).expect("symlink");
        let link_str = link.to_string_lossy().into_owned();
        let plan = write_repo_doc(
            &root,
            "docs/plans/PLAN-link.md",
            "Draft",
            Some(&link_str),
            "",
        );

        let err = walk_chain_mode(&plan, Mode::Apply).expect_err("must fail");
        assert_eq!(err.code(), 1, "symlink upstream is a tool error (exit 1)");
        assert!(
            err.message.contains("symlink"),
            "explains the symlink rejection: {}",
            err.message
        );
    }

    /// Exit-code level 3: an I/O error path is reachable -- the structured error
    /// it produces carries code 3. We exercise the message shape directly since
    /// provoking a real mid-walk I/O fault is racy; the apply path maps strip
    /// and engine I/O faults through `WalkError::io` / the engine's code-3
    /// errors.
    #[test]
    fn exit_code_3_io_error_shape() {
        let err = WalkError::io(
            "docs/designs/DESIGN-x.md",
            Some("Design"),
            "permission denied",
        );
        assert_eq!(err.code(), 3);
        assert!(err.message.contains("DESIGN-x.md"));
        assert!(err.message.contains("Design"));
        assert!(err.message.contains("permission denied"));
    }

    /// A cross-repo `owner/repo:path` upstream stops the walk with a clear
    /// report entry rather than being resolved (resolution is out of scope).
    /// This is the apply-mode counterpart to the dry-run test above.
    #[test]
    fn cross_repo_upstream_stops_apply_mode() {
        let root = fresh_git_repo();
        let plan = write_repo_doc(
            &root,
            "docs/plans/PLAN-xrepo.md",
            "Draft",
            Some("owner/repo:docs/DESIGN-x.md"),
            "",
        );
        let report = walk_chain_mode(&plan, Mode::Apply).expect("walk ok (no error raised)");
        let actions: Vec<&str> = report.nodes.iter().map(|n| n.action.as_str()).collect();
        assert_eq!(actions, vec!["delete_plan", "stop"]);
        match &report.nodes[1].action {
            NodeAction::Stop(note) => {
                assert!(
                    note.contains("cross-repo"),
                    "note explains the stop: {}",
                    note
                );
                assert!(note.contains("out of scope"));
            }
            other => panic!("expected Stop, got {:?}", other),
        }
    }

    /// The structured-error JSON matches the single-document transition's
    /// `{ success:false, error, code }` shape, and `error` names the node, its
    /// type, and the engine's reason -- never a bare brace.
    #[test]
    fn structured_error_json_names_node_type_and_reason() {
        let root = fresh_git_repo();
        let brief = write_repo_doc(&root, "docs/briefs/BRIEF-json.md", "Draft", None, "");
        let plan = write_repo_doc(&root, "docs/plans/PLAN-bjson.md", "Draft", Some(&brief), "");

        let err = walk_chain_mode(&plan, Mode::Apply).expect_err("must refuse");
        let json = err.to_json();
        // Envelope shape, identical to TransitionError::to_json.
        assert!(json.starts_with("{\n  \"success\": false,\n  \"error\": "));
        assert!(json.contains("\"code\": 2"));
        assert!(json.ends_with("}\n"));
        // The error string is a full sentence, not a bare fragment.
        assert!(json.contains("BRIEF-json.md"));
        assert!(json.contains("Brief"));
        assert!(json.contains("Draft -> Done"));
        assert!(json.contains("must be Accepted first"));
        // It is emphatically not just a brace.
        assert_ne!(err.message.trim(), "{");
        assert!(err.message.len() > 1);
    }

    // ---- Issue 5: read-only cross-repo upstream verification pass ----

    use crate::gh::MockIssueStateClient;

    /// A cross-repo upstream whose tracking issue/PR is at a terminal
    /// (Closed/merged) status passes the read-only verification pass. The pass
    /// never writes across the repo boundary — it only confirms the terminal
    /// status through the read-only client.
    #[test]
    fn verify_cross_repo_terminal_passes() {
        let client = MockIssueStateClient::new().with_issue(
            "tsukumogami",
            "shirabe",
            196,
            Ok(IssueState::Closed),
        );
        let v = verify_cross_repo_upstream_terminal(
            "tsukumogami/shirabe:docs/designs/DESIGN-x.md",
            196,
            &client,
        )
        .expect("terminal upstream must verify");
        assert_eq!(v.slug, "tsukumogami/shirabe");
        assert_eq!(v.path, "docs/designs/DESIGN-x.md");
        assert_eq!(v.number, 196);
    }

    /// A non-terminal (still-open) upstream fails closed (R21): the pass halts
    /// with a diagnostic naming the reference rather than treating it as
    /// satisfied.
    #[test]
    fn verify_cross_repo_non_terminal_fails_closed() {
        let client = MockIssueStateClient::new().with_issue(
            "tsukumogami",
            "shirabe",
            196,
            Ok(IssueState::Open),
        );
        let err = verify_cross_repo_upstream_terminal(
            "tsukumogami/shirabe:docs/designs/DESIGN-x.md",
            196,
            &client,
        )
        .expect_err("non-terminal upstream must fail closed");
        assert!(
            err.message.contains("not at a terminal status"),
            "diagnostic names the non-terminal reason: {}",
            err.message
        );
        assert!(err.message.contains("tsukumogami/shirabe"));
    }

    /// An unresolvable reference (the read returns an error) fails closed
    /// (R21) — never silently skipped, never treated as terminal. The raw `gh`
    /// payload is not embedded in the diagnostic (F5).
    #[test]
    fn verify_cross_repo_unresolvable_fails_closed() {
        // The mock has no entry for this (owner, repo, number), so the read
        // returns NotFound.
        let client = MockIssueStateClient::new();
        let err = verify_cross_repo_upstream_terminal(
            "tsukumogami/shirabe:docs/designs/DESIGN-x.md",
            999,
            &client,
        )
        .expect_err("unresolvable upstream must fail closed");
        assert!(
            err.message.contains("could not be resolved"),
            "diagnostic explains the resolution failure: {}",
            err.message
        );
        assert!(err.message.contains("not found"));
    }

    /// A malformed `owner/repo:path` reference fails closed at the F2 parse
    /// gate, before any read is attempted (R21).
    #[test]
    fn verify_cross_repo_malformed_reference_fails_closed() {
        let client = MockIssueStateClient::new();
        // No colon: not a cross-repo reference at all.
        let err = verify_cross_repo_upstream_terminal("docs/designs/DESIGN-x.md", 1, &client)
            .expect_err("malformed reference must fail closed");
        assert!(
            err.message.contains("invalid cross-repo reference"),
            "diagnostic names the F2 rejection: {}",
            err.message
        );

        // Path traversal in the reference is also rejected by F2 before any read.
        let err2 =
            verify_cross_repo_upstream_terminal("tsukumogami/shirabe:../escape.md", 1, &client)
                .expect_err("traversal reference must fail closed");
        assert!(err2.message.contains("invalid cross-repo reference"));
    }

    // ---- Issue 9: the retirement guard + multi-branch traversal ----

    /// Write a doc whose `upstream:` is a block sequence, so a test can build a
    /// document with two branches. Written order is the sequence order.
    fn write_repo_doc_multi(
        root: &Path,
        rel_path: &str,
        status: &str,
        upstreams: &[&str],
        extra_body: &str,
    ) -> String {
        let mut fm = format!("---\nschema: x/v1\nstatus: {}\nupstream:\n", status);
        for u in upstreams {
            fm.push_str(&format!("  - {}\n", u));
        }
        fm.push_str(&format!("---\n\n## Status\n\n{}\n{}", status, extra_body));
        let path = root.join(rel_path);
        fs::create_dir_all(path.parent().unwrap()).expect("mkdir doc dir");
        fs::write(&path, fm).expect("write doc");
        run_git(root, &["add", rel_path]);
        path.to_string_lossy().into_owned()
    }

    fn node_for<'a>(report: &'a Report, needle: &str) -> &'a NodeEntry {
        let hits: Vec<&NodeEntry> = report
            .nodes
            .iter()
            .filter(|n| n.path.contains(needle))
            .collect();
        assert_eq!(
            hits.len(),
            1,
            "expected exactly one node for {}, got {:?}",
            needle,
            report.nodes.iter().map(|n| &n.path).collect::<Vec<_>>()
        );
        hits[0]
    }

    /// An ancestor another document still points at is not retired. The report
    /// names the blocking document and its status, the file is left untouched,
    /// and the walk still returns Ok — a block is a reported skip, not a
    /// failure.
    ///
    /// The block then propagates with no extra rule: the blocked PRD stays
    /// non-terminal, so it is itself a blocking referrer for the BRIEF above it.
    #[test]
    fn shared_ancestor_is_not_retired_and_the_block_propagates() {
        let root = fresh_git_repo();
        let brief = write_repo_doc(&root, "docs/briefs/BRIEF-shared.md", "Accepted", None, "");
        let prd = write_repo_doc(
            &root,
            "docs/prds/PRD-shared.md",
            "Draft",
            Some(&brief),
            "",
        );
        // The walked branch.
        let design = write_repo_doc(&root, "docs/designs/DESIGN-mine.md", "Draft", Some(&prd), "");
        // A second consumer of the same PRD, outside this walk and still live.
        write_repo_doc(&root, "docs/designs/DESIGN-other.md", "Draft", Some(&prd), "");
        let plan = write_repo_doc(
            &root,
            "docs/plans/PLAN-shared.md",
            "Draft",
            Some(&design),
            "",
        );

        let report = walk_chain_mode(&plan, Mode::Apply).expect("a block never fails the walk");

        // The walked DESIGN is retired as usual: its only referrer is the input
        // PLAN, which this walk retires.
        let d = node_for(&report, "DESIGN-mine.md");
        assert!(!d.blocked);
        assert_eq!(d.new_status.as_deref(), Some("Current"));

        // The shared PRD is not transitioned, and says who is still holding it.
        let p = node_for(&report, "PRD-shared.md");
        assert!(p.blocked, "the shared ancestor must be blocked");
        assert!(p.new_status.is_none(), "nothing was applied to it");
        assert_eq!(p.blocked_by.len(), 1, "{:?}", p.blocked_by);
        assert!(p.blocked_by[0].path.ends_with("DESIGN-other.md"));
        assert_eq!(p.blocked_by[0].status, "Draft");
        let note = p.note.as_deref().expect("a rendered note for humans");
        assert!(note.contains("DESIGN-other.md"), "note: {}", note);
        assert!(note.contains("Draft"), "note: {}", note);
        // On disk the PRD is untouched.
        assert!(fs::read_to_string(&prd).unwrap().contains("status: Draft"));

        // The walk continued past the block, and the BRIEF above it is blocked
        // in turn by the PRD that stayed non-terminal.
        let b = node_for(&report, "BRIEF-shared.md");
        assert!(b.blocked, "the block propagates upward");
        assert_eq!(b.blocked_by.len(), 1, "{:?}", b.blocked_by);
        assert!(b.blocked_by[0].path.ends_with("PRD-shared.md"));
        assert!(fs::read_to_string(&brief).unwrap().contains("status: Accepted"));
    }

    /// A referrer that has already reached its own terminal status does not
    /// block: a finished sibling cannot pin an ancestor open forever.
    #[test]
    fn terminal_referrer_does_not_block() {
        let root = fresh_git_repo();
        let prd = write_repo_doc(&root, "docs/prds/PRD-term.md", "Draft", None, "");
        let design = write_repo_doc(&root, "docs/designs/DESIGN-term.md", "Draft", Some(&prd), "");
        // A second consumer, already at its terminal status (a DESIGN retires at
        // `Current`, in `docs/designs/current/`).
        write_repo_doc(
            &root,
            "docs/designs/current/DESIGN-done.md",
            "Current",
            Some(&prd),
            "",
        );
        let plan = write_repo_doc(
            &root,
            "docs/plans/PLAN-term.md",
            "Draft",
            Some(&design),
            "",
        );

        let report = walk_chain_mode(&plan, Mode::Apply).expect("apply ok");
        let p = node_for(&report, "PRD-term.md");
        assert!(!p.blocked, "a terminal referrer must not block: {:?}", p);
        assert!(p.blocked_by.is_empty());
        assert_eq!(p.new_status.as_deref(), Some("Done"));
        assert!(fs::read_to_string(&prd).unwrap().contains("status: Done"));
    }

    /// A document with two upstreams has both branches walked, in written
    /// order rather than path order, and an ancestor reachable through both is
    /// visited once — so it is transitioned once and the outcome does not
    /// depend on traversal order.
    #[test]
    fn diamond_walks_both_branches_and_visits_the_shared_ancestor_once() {
        let root = fresh_git_repo();
        let prd = write_repo_doc(&root, "docs/prds/PRD-diamond.md", "Draft", None, "");
        // Written second alphabetically-first, so written order and path order
        // disagree: the report must follow what the author wrote.
        let zeta = write_repo_doc(&root, "docs/designs/DESIGN-zeta.md", "Draft", Some(&prd), "");
        let alpha = write_repo_doc(&root, "docs/designs/DESIGN-alpha.md", "Draft", Some(&prd), "");
        let plan = write_repo_doc_multi(
            &root,
            "docs/plans/PLAN-diamond.md",
            "Draft",
            &[&zeta, &alpha],
            "",
        );

        let report = walk_chain_mode(&plan, Mode::Apply).expect("apply ok");

        // Four nodes: the PLAN, both DESIGNs, and the shared PRD exactly once.
        assert_eq!(
            report.nodes.len(),
            4,
            "{:?}",
            report.nodes.iter().map(|n| &n.path).collect::<Vec<_>>()
        );
        assert!(report.nodes[1].path.ends_with("DESIGN-zeta.md"), "written order");
        assert!(report.nodes[2].path.ends_with("DESIGN-alpha.md"), "written order");
        let p = node_for(&report, "PRD-diamond.md");
        assert!(!p.blocked, "both referrers are retired by this walk");
        assert_eq!(p.new_status.as_deref(), Some("Done"));
        assert_eq!(p.old_status.as_deref(), Some("Draft"));
        // Both branches were applied.
        assert!(root.join("docs/designs/current/DESIGN-zeta.md").is_file());
        assert!(root.join("docs/designs/current/DESIGN-alpha.md").is_file());
        assert!(fs::read_to_string(&prd).unwrap().contains("status: Done"));
    }

    /// A branch that ends at a VISION does not end the other branch: the
    /// worklist is per-branch, not a single loop.
    #[test]
    fn one_branch_stopping_does_not_end_the_other() {
        let root = fresh_git_repo();
        let vision = write_repo_doc(&root, "docs/VISION-product.md", "Draft", None, "");
        let prd = write_repo_doc(&root, "docs/prds/PRD-two.md", "Draft", None, "");
        let plan = write_repo_doc_multi(
            &root,
            "docs/plans/PLAN-two.md",
            "Draft",
            &[&vision, &prd],
            "",
        );

        let report = walk_chain_mode(&plan, Mode::Apply).expect("apply ok");
        let actions: Vec<&str> = report.nodes.iter().map(|n| n.action.as_str()).collect();
        assert_eq!(actions, vec!["delete_plan", "stop", "transition_prd"]);
        assert_eq!(
            node_for(&report, "PRD-two.md").new_status.as_deref(),
            Some("Done")
        );
    }

    /// A dry run reports the block without touching anything: the guard's
    /// verdict is the same in both modes.
    #[test]
    fn dry_run_reports_the_block_and_the_json_carries_it() {
        let root = fresh_git_repo();
        let prd = write_repo_doc(&root, "docs/prds/PRD-dryblock.md", "Draft", None, "");
        let design = write_repo_doc(
            &root,
            "docs/designs/DESIGN-dryblock.md",
            "Draft",
            Some(&prd),
            "",
        );
        write_repo_doc(&root, "docs/designs/DESIGN-holder.md", "Draft", Some(&prd), "");
        let plan = write_repo_doc(
            &root,
            "docs/plans/PLAN-dryblock.md",
            "Draft",
            Some(&design),
            "",
        );
        let before = fs::read_to_string(&prd).unwrap();

        let report = walk_chain_mode(&plan, Mode::DryRun).expect("dry-run ok");
        assert!(node_for(&report, "PRD-dryblock.md").blocked);
        assert_eq!(fs::read_to_string(&prd).unwrap(), before);

        let json = report.to_json();
        assert!(json.contains("\"blocked\": true"), "{}", json);
        assert!(json.contains("\"blocked_by\": ["), "{}", json);
        assert!(json.contains("DESIGN-holder.md"), "{}", json);
        assert!(json.contains("\"status\": \"Draft\""), "{}", json);
        assert!(json.contains("\"note\": \"not retiring"), "{}", json);
    }

    /// A node whose path does not canonicalize blocks: the walk and the
    /// referrer map would otherwise disagree about which document a path names,
    /// and the guard would silently miss the referrers it could not look up.
    /// Exercised against the decision core, since a node that reaches the guard
    /// has already passed path validation.
    #[test]
    fn a_canonicalization_failure_blocks() {
        let nodes = vec![
            WalkNode {
                canonical: Some(PathBuf::from("/repo/docs/plans/PLAN-x.md")),
                entry: NodeEntry::new(
                    "docs/plans/PLAN-x.md".to_string(),
                    Some("Plan".to_string()),
                    NodeAction::DeletePlan,
                    None,
                ),
            },
            WalkNode {
                // The canonicalization failed.
                canonical: None,
                entry: NodeEntry::new(
                    "docs/prds/PRD-x.md".to_string(),
                    Some("PRD".to_string()),
                    NodeAction::TransitionPrd,
                    Some("Done".to_string()),
                ),
            },
        ];
        let by_key: HashMap<String, usize> = HashMap::new();
        let referrers = crate::lifecycle::ReferrerMap::new();
        let mut verdicts = vec![Eval::Unresolved; nodes.len()];

        let plan = decide(
            0,
            &nodes,
            &by_key,
            &referrers,
            Path::new("/repo"),
            &mut verdicts,
        );
        assert!(plan.retires, "the input PLAN counts as retired");

        let prd = decide(
            1,
            &nodes,
            &by_key,
            &referrers,
            Path::new("/repo"),
            &mut verdicts,
        );
        assert!(!prd.retires, "a canonicalization failure blocks");
        let block = prd.block.expect("the block is reported");
        assert!(block.blocked_by.is_empty(), "no referrer to name");
        assert!(
            block.note.contains("could not be canonicalized"),
            "note: {}",
            block.note
        );
    }

    // ---- Issue 10: the fail-open note ----

    /// Write a document the index cannot read: the frontmatter opens and never
    /// closes, which is a parse failure rather than a document without
    /// frontmatter. It is dropped from the index, so whatever it referred to is
    /// missing from the referrer map -- the partial failure, which is the one
    /// that actually happens.
    fn write_unindexable_doc(root: &Path, rel_path: &str) -> String {
        let path = root.join(rel_path);
        fs::create_dir_all(path.parent().unwrap()).expect("mkdir doc dir");
        fs::write(&path, "---\nschema: x/v1\nstatus: Draft\n\n## Status\n").expect("write doc");
        run_git(root, &["add", rel_path]);
        path.to_string_lossy().into_owned()
    }

    /// Build the standard BRIEF -> PRD -> DESIGN -> PLAN chain in a fresh repo,
    /// returning the repo root and the PLAN's path.
    fn chain_repo(slug: &str) -> (PathBuf, String) {
        let root = fresh_git_repo();
        let brief = write_repo_doc(
            &root,
            &format!("docs/briefs/BRIEF-{}.md", slug),
            "Accepted",
            None,
            "",
        );
        let prd = write_repo_doc(
            &root,
            &format!("docs/prds/PRD-{}.md", slug),
            "Draft",
            Some(&brief),
            "",
        );
        let design = write_repo_doc(
            &root,
            &format!("docs/designs/DESIGN-{}.md", slug),
            "Draft",
            Some(&prd),
            "",
        );
        let plan = write_repo_doc(
            &root,
            &format!("docs/plans/PLAN-{}.md", slug),
            "Draft",
            Some(&design),
            "",
        );
        (root, plan)
    }

    /// One document that fails to index leaves the map missing whatever it
    /// referred to, and the walk carries on retiring against it. Every node it
    /// retires says so, in both modes -- this is the reachable half of the
    /// fail-open compromise and the half that would otherwise be silent, since
    /// a thinner map is indistinguishable from a document nothing refers to.
    #[test]
    fn a_partial_index_failure_notes_every_retired_node() {
        let (root, plan) = chain_repo("partial");
        write_unindexable_doc(&root, "docs/prds/PRD-unreadable.md");

        let report = walk_chain_mode(&plan, Mode::Apply).expect("apply ok");

        for needle in ["DESIGN-partial.md", "PRD-partial.md", "BRIEF-partial.md"] {
            let node = node_for(&report, needle);
            let note = node.note.as_deref().unwrap_or_else(|| {
                panic!("{} must carry the fail-open note; got {:?}", needle, node)
            });
            assert!(note.starts_with(GUARD_GAP_NOTE), "{}: {}", needle, note);
            assert!(
                note.contains("PRD-unreadable.md"),
                "the note names what could not be indexed: {}",
                note
            );
            // Fail *open*: the transition still happened.
            assert!(!node.blocked, "{} must not be blocked", needle);
            assert!(node.new_status.is_some(), "{} was still retired", needle);
        }

        // The input PLAN's deletion never consulted the map, so it carries no
        // note about the map being short.
        assert_eq!(report.nodes[0].action.as_str(), "delete_plan");
        assert_eq!(report.nodes[0].note, None);

        // And it reaches the rendered report the caller parses.
        let json = report.to_json();
        assert!(
            json.contains(&format!("\"note\": \"{}", GUARD_GAP_NOTE)),
            "{}",
            json
        );
    }

    /// The same note in a dry run: a verdict the guard could not fully take is
    /// worth the same warning whether or not it is applied.
    #[test]
    fn a_dry_run_carries_the_fail_open_note_too() {
        let (root, plan) = chain_repo("partialdry");
        write_unindexable_doc(&root, "docs/briefs/BRIEF-unreadable.md");

        let report = walk_chain_mode(&plan, Mode::DryRun).expect("dry-run ok");
        let note = node_for(&report, "PRD-partialdry.md")
            .note
            .clone()
            .expect("the note is recorded in dry-run too");
        assert!(note.starts_with(GUARD_GAP_NOTE), "{}", note);
        assert!(note.contains("BRIEF-unreadable.md"), "{}", note);
    }

    /// A corpus that indexes cleanly says nothing: the note is a signal, not
    /// decoration, so it must not fire on the ordinary path.
    #[test]
    fn a_clean_corpus_carries_no_fail_open_note() {
        let (_root, plan) = chain_repo("clean");

        let report = walk_chain_mode(&plan, Mode::Apply).expect("apply ok");
        for node in &report.nodes {
            assert_eq!(
                node.note, None,
                "clean corpus, unexpected note on {:?}",
                node
            );
        }
        assert!(!report.to_json().contains(GUARD_GAP_NOTE));
    }

    /// The total failure -- no document indexed at all -- produces the same
    /// note as the partial one. It is checked against the gap helper directly
    /// because the walk cannot reach it: `repo_root_for` derives the root from
    /// an existing file that path validation has already stat'd, so the root
    /// always resolves by the time the map is built.
    #[test]
    fn a_total_index_failure_produces_the_same_note() {
        let missing = fresh_dir().join("no-such-corpus");
        let gap = referrer_map_gap(&missing, &[]).expect("an unresolvable root is a gap");
        let note = gap.note_for("docs/prds/PRD-x.md");
        assert!(note.starts_with(GUARD_GAP_NOTE), "{}", note);
        assert!(note.contains("no document was indexed"), "{}", note);
        assert!(note.contains("docs/prds/PRD-x.md"), "{}", note);

        // A resolvable root with no index errors is not a gap.
        let clean = fresh_dir();
        assert!(referrer_map_gap(&clean, &[]).is_none());
    }

    /// The note names the documents that were dropped, and stops naming them
    /// before it turns into a wall of paths.
    #[test]
    fn the_gap_note_names_what_was_dropped_and_stops_at_three() {
        let root = fresh_dir();
        let errs: Vec<crate::ValidationError> = ["d.md", "c.md", "b.md", "a.md"]
            .iter()
            .map(|f| crate::ValidationError {
                file: f.to_string(),
                line: 1,
                code: "L05".to_string(),
                message: "frontmatter parse failed".to_string(),
            })
            .collect();
        let note = referrer_map_gap(&root, &errs)
            .expect("index errors are a gap")
            .note_for("docs/prds/PRD-x.md");
        assert!(
            note.contains("4 documents could not be indexed"),
            "{}",
            note
        );
        assert!(note.contains("a.md, b.md, c.md, and 1 more"), "{}", note);

        let one = referrer_map_gap(&root, &errs[..1])
            .expect("one index error is a gap")
            .note_for("docs/prds/PRD-x.md");
        assert!(one.contains("1 document could not be indexed"), "{}", one);
    }

    /// The pure decision core encodes the fail-closed policy directly: only a
    /// resolved Closed state is terminal; Open and every client error are
    /// failures. Exercises the seam the network-free unit tests rely on.
    #[test]
    fn decide_terminal_policy_matrix() {
        // Closed -> verified.
        assert!(decide_terminal("o/r", "p", 1, Ok(IssueState::Closed)).is_ok());
        // Open -> fail closed.
        assert!(decide_terminal("o/r", "p", 1, Ok(IssueState::Open)).is_err());
        // Each client error -> fail closed, with a fixed reason phrase (no raw
        // payload interpolation).
        for err in [
            ClientError::Auth,
            ClientError::NotFound,
            ClientError::Forbidden,
            ClientError::RateLimit,
            ClientError::Network,
            ClientError::Malformed("secret raw response".to_string()),
        ] {
            let out = decide_terminal("o/r", "p", 1, Err(err));
            let e = out.expect_err("client error must fail closed");
            // F5: the raw Malformed payload must never appear in the diagnostic.
            assert!(
                !e.message.contains("secret raw response"),
                "raw gh payload leaked into diagnostic: {}",
                e.message
            );
        }
    }
}
