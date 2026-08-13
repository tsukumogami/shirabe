//! Chain-aware passing-state lifecycle check.
//!
//! Walks the doc tree under a given root, discovers artifact chains by
//! inverting the `upstream:` frontmatter edge, infers each chain's
//! posture from the PLAN's `execution_mode` and `status` fields, and
//! verifies every chain member is at its passing state — the state
//! the current PR needs the doc to be at for the chain to ship.
//!
//! The entry point is [`run_lifecycle_check`]. The check codes use
//! the `Lnn` family, distinct from the `FCnn` content-format family
//! in `checks.rs`:
//!
//! - **L01**: a chain member's status differs from the passing state
//!   computed for the chain's posture. The umbrella code; covers
//!   present-Done multi-pr PLANs, present single-pr PLANs at merge,
//!   BRIEFs stuck at Accepted while their PLAN is Done, and every
//!   other state-vs-posture mismatch. The message names the posture
//!   so the author can read the rule directly — every posture that
//!   demands the state, since a doc can sit in more than one chain.
//! - **L02**: an orphan doc at non-terminal status that is neither
//!   rooted at an Active ROADMAP (its own `upstream:`) nor linked into a
//!   coherent multi-member tactical chain (a downstream child points at
//!   it, or its own `upstream:` resolves to another BRIEF/PRD/DESIGN/PLAN
//!   in the tree). A lone stuck doc is drift; a linked in-flight chain
//!   with no ROADMAP root is active work. The orphan-rule violation per
//!   `docs/decisions/DECISION-orphan-doc-passing-state-rule-2026-06-06.md`.
//! - **L03**: a cycle detected in the upstream graph. The message
//!   names every doc participating in the cycle.
//! - **L04**: a chain member references an `upstream:` parent that
//!   does not exist in the index.
//! - **L05**: defensive parsing fallback — the walker could not
//!   extract `upstream:` or `status:` from a chain-participating doc.
//! - **L06**: an outline-AC checkbox on a single-pr PLAN member is
//!   left unticked (outline-AC completeness).
//! - **L07**: a DESIGN's directory disagrees with its status — a
//!   `Current` design outside `docs/designs/current/`, or a
//!   non-`Current` design inside it.
//! - **L08**: two chains require the same document in states no
//!   single status satisfies. The message names each conflicting
//!   chain and the full set it requires, and it supersedes the L01
//!   findings those chains' requirements would have produced on that
//!   document — the document is told once that its consumers
//!   disagree, rather than handed instructions it cannot both follow.
//!   Findings of every other kind on it are unaffected.
//!
//! Posture detection follows
//! `docs/decisions/DECISION-multi-pr-posture-detection-2026-06-06.md`:
//! the PLAN's frontmatter `status:` field is the posture signal.
//! PLAN docs use a unified four-state lifecycle —
//! Draft -> Active -> Done -> DELETED — identical for single-pr and
//! multi-pr execution. The only branch is the Draft -> Active gate:
//! multi-pr requires human approval (GitHub issues + milestone are
//! created on the transition); single-pr auto-transitions when
//! `/shirabe:plan` finishes authoring, so a single-pr PLAN that
//! reaches a committed branch is already at `Active`. Consequently
//! the posture rules are: present at `Active` is in-flight (single-pr
//! mid-PR or multi-pr in-flight); present at `Done` is work-
//! completing-but-not-yet-deleted (L01 fires); present at `Draft` on
//! a committed PLAN is a violation (the author landed a single-pr
//! PLAN without its auto-transition firing, or a multi-pr PLAN whose
//! human approval gate never ran); absent is at-merge.

use std::collections::{BTreeMap, BTreeSet, HashMap, HashSet};
use std::fs;
use std::path::{Path, PathBuf};

use crate::doc::{Config, Doc, ValidationError};
use crate::frontmatter::parse_doc;
use crate::table::parse_outline_acs;
use crate::validate::ReviewPosture;

// ---------- public data types ----------

/// Target state for an artifact type — the final sunny-path state a
/// doc reaches in its lifecycle.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum TargetState {
    /// The doc reaches a named frontmatter status (BRIEF Done, PRD
    /// Done, DESIGN Current).
    Status(&'static str),
    /// The doc is deleted from the tree at chain completion (PLAN,
    /// ROADMAP).
    Deleted,
    /// Unknown format name — defensive fallback.
    Unknown,
}

/// Posture of a chain — derived from the PLAN's `execution_mode` and
/// frontmatter `status:` value.
///
/// Ordered so a set of postures has a stable presentation order; the
/// order is the declaration order below and carries no meaning beyond
/// determinism.
#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord)]
pub enum Posture {
    /// Multi-pr chain in flight: PLAN present at `Active`.
    MultiPrInFlight,
    /// Multi-pr chain whose author transitioned the PLAN to `Done`
    /// but has not yet deleted the file. The check FAILs in this
    /// posture (L01); the failure is the forcing function for the
    /// deletion commit.
    MultiPrWorkCompleting,
    /// Multi-pr chain at merge time: PLAN absent.
    MultiPrAtMerge,
    /// Single-pr chain mid-PR: PLAN present at `Active`. A single-pr
    /// PLAN's Draft -> Active gate auto-fires when `/shirabe:plan`
    /// finishes authoring, so the only on-disk state for a committed
    /// single-pr PLAN is `Active`. A committed single-pr PLAN at
    /// `Draft` is a violation (L01 fires).
    SinglePrMidPR,
    /// Single-pr chain at merge: PLAN absent.
    SinglePrAtMerge,
}

impl Posture {
    /// Human-readable name for inclusion in L01 error messages.
    pub fn name(self) -> &'static str {
        match self {
            Self::MultiPrInFlight => "multi-pr in-flight",
            Self::MultiPrWorkCompleting => "multi-pr work-completing",
            Self::MultiPrAtMerge => "multi-pr at-merge",
            Self::SinglePrMidPR => "single-pr mid-PR",
            Self::SinglePrAtMerge => "single-pr at-merge",
        }
    }
}

/// Role a doc plays in its chain — what artifact type it is.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ChainRole {
    Brief,
    Prd,
    Design,
    Plan,
    Roadmap,
}

impl ChainRole {
    fn from_format(name: &str) -> Option<Self> {
        match name {
            "Brief" => Some(Self::Brief),
            "PRD" => Some(Self::Prd),
            "Design" => Some(Self::Design),
            "Plan" => Some(Self::Plan),
            "Roadmap" => Some(Self::Roadmap),
            _ => None,
        }
    }

    fn as_str(self) -> &'static str {
        match self {
            Self::Brief => "BRIEF",
            Self::Prd => "PRD",
            Self::Design => "DESIGN",
            Self::Plan => "PLAN",
            Self::Roadmap => "ROADMAP",
        }
    }
}

/// Whether the chain is rooted at a PLAN or a ROADMAP.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum RootKind {
    Plan,
    Roadmap,
}

/// A doc participating in a chain, with the fields the check needs.
#[derive(Debug, Clone)]
pub struct ChainMember {
    pub path: PathBuf,
    pub role: ChainRole,
    pub status: String,
}

/// A discovered chain: the PLAN or ROADMAP it is rooted at, plus every
/// doc reachable from that root along the `upstream:` edge.
///
/// `members` reads BRIEF -> PRD -> DESIGN -> PLAN/ROADMAP for a chain
/// whose upstreams are single-valued (some leading members may be
/// absent if the upstream chain doesn't go all the way up). Once an
/// upstream fans out the walk branches and no single line-up survives,
/// so member order is presentational only: it is the reverse of walk
/// order, and nothing reads meaning out of a member's position. Root
/// identity in particular does not live there — `root` carries it. It
/// used to be recoverable as `members.last()`, which held only while
/// the walk was a single path.
#[derive(Debug, Clone)]
pub struct Chain {
    /// Canonical path of the PLAN or ROADMAP this chain is rooted at.
    /// Also present in `members`; this is the handle a consumer that
    /// has to name the chain uses.
    pub root: PathBuf,
    pub members: Vec<ChainMember>,
    pub root_kind: RootKind,
    pub posture: Posture,
}

/// Computed passing state for a chain member — the set of statuses
/// that satisfy one chain's demand on one document.
///
/// Each variant denotes a distinct set: `Status` a singleton,
/// `Deleted` the empty set (the document must not be there at all),
/// and the two compound variants their named pairs. No two variants
/// denote the same set, which is what lets the variant itself stand in
/// for "the required status set" as part of a finding's identity.
#[derive(Debug, Clone, PartialEq, Eq, PartialOrd, Ord)]
pub enum PassingState {
    /// The doc should be at this named status.
    Status(&'static str),
    /// The doc should be absent from the tree.
    Deleted,
    /// DESIGN-specific: passes at either `Planned` (in `docs/designs/`,
    /// the in-flight pre-promotion shape) or `Current` (in
    /// `docs/designs/current/`, the terminal post-promotion shape).
    /// Used for in-flight postures only.
    DesignPlannedOrCurrent,
    /// PRD-specific: passes at either `Accepted` (requirements locked,
    /// downstream not yet started) or `In Progress` (downstream
    /// workflow active). Used for multi-pr in-flight where the PRD
    /// can legitimately be at either state.
    PrdAcceptedOrInProgress,
}

impl PassingState {
    fn describe(&self) -> String {
        match self {
            Self::Status(s) => format!("status '{}'", s),
            Self::Deleted => "DELETED (absent from tree)".to_string(),
            Self::DesignPlannedOrCurrent => {
                "status 'Planned' or 'Current'".to_string()
            }
            Self::PrdAcceptedOrInProgress => {
                "status 'Accepted' or 'In Progress'".to_string()
            }
        }
    }

    /// The variant expanded into the concrete set of statuses it
    /// denotes.
    ///
    /// `matches` answers the question one status at a time, which is
    /// all the per-document check ever needed. Comparing two
    /// requirements to each other needs the sets themselves, and this
    /// is the one place they are written down.
    ///
    /// `Deleted` expands to the empty set — correctly, since no status
    /// satisfies "not there at all" — which is exactly why
    /// [`requirements_conflict`] cannot be a bare disjointness test.
    fn statuses(&self) -> BTreeSet<&'static str> {
        match self {
            Self::Status(s) => [*s].into_iter().collect(),
            Self::Deleted => BTreeSet::new(),
            Self::DesignPlannedOrCurrent => ["Planned", "Current"].into_iter().collect(),
            Self::PrdAcceptedOrInProgress => {
                ["Accepted", "In Progress"].into_iter().collect()
            }
        }
    }

    /// Whether the given status satisfies this passing state.
    fn matches(&self, status: &str) -> bool {
        match self {
            Self::Status(s) => status == *s,
            Self::Deleted => false,
            Self::DesignPlannedOrCurrent => status == "Planned" || status == "Current",
            Self::PrdAcceptedOrInProgress => {
                status == "Accepted" || status == "In Progress"
            }
        }
    }
}

// ---------- target-state lookup ----------

/// The terminal target state per artifact type.
///
/// See [`Posture`] for the chain-posture-dependent passing states;
/// this function returns the per-type *target* state, which is the
/// fixed end of the lifecycle independent of posture.
pub fn target_state_for(format_name: &str) -> TargetState {
    match format_name {
        "Brief" => TargetState::Status("Done"),
        "PRD" => TargetState::Status("Done"),
        "Design" => TargetState::Status("Current"),
        "Plan" => TargetState::Deleted,
        "Roadmap" => TargetState::Deleted,
        _ => TargetState::Unknown,
    }
}

// ---------- doc index ----------

/// Metadata extracted from a doc's frontmatter for the lifecycle
/// check. Built once per walk by [`build_doc_index`].
#[derive(Debug, Clone)]
struct IndexedDoc {
    path: PathBuf,
    format: String,        // "Brief", "PRD", "Design", "Plan", "Roadmap"
    status: String,        // frontmatter status field
    execution_mode: String, // for PLANs only; empty otherwise
    upstreams: Vec<PathBuf>, // resolved upstream paths (scalar or list)
}

/// Index of every doc under the tree, keyed by canonical path.
type DocIndex = BTreeMap<PathBuf, IndexedDoc>;

/// Inverse-upstream graph: parent path -> list of child paths.
type InverseGraph = BTreeMap<PathBuf, Vec<PathBuf>>;

/// Walk the doc directories under `root` and build the doc index.
///
/// Path-traversal containment: every discovered path is canonicalized
/// and verified to remain within `root`. Symlinks pointing outside
/// `root` are dropped with an L05 error.
fn build_doc_index(root: &Path) -> (DocIndex, Vec<ValidationError>) {
    let mut idx = DocIndex::new();
    let mut errors: Vec<ValidationError> = Vec::new();

    let canon_root = match fs::canonicalize(root) {
        Ok(p) => p,
        Err(_) => {
            // Root itself doesn't canonicalize — return empty index;
            // caller surfaces a usage error via CLI dispatch.
            return (idx, errors);
        }
    };

    let dirs: &[&str] = &[
        "docs/briefs",
        "docs/prds",
        "docs/designs",
        "docs/designs/current",
        "docs/plans",
        "docs/roadmaps",
    ];

    for sub in dirs {
        let dir = canon_root.join(sub);
        if !dir.exists() {
            continue;
        }
        let read = match fs::read_dir(&dir) {
            Ok(r) => r,
            Err(_) => continue,
        };
        for entry in read.flatten() {
            let path = entry.path();
            if !path.is_file() {
                continue;
            }
            let name = match path.file_name().and_then(|s| s.to_str()) {
                Some(n) => n,
                None => continue,
            };
            if !name.ends_with(".md") {
                continue;
            }
            // Skip non-artifact files at the top level of docs/designs/
            // — only BRIEF-/PRD-/DESIGN-/PLAN-/ROADMAP- prefixed.
            if !(name.starts_with("BRIEF-")
                || name.starts_with("PRD-")
                || name.starts_with("DESIGN-")
                || name.starts_with("PLAN-")
                || name.starts_with("ROADMAP-"))
            {
                continue;
            }

            // Path-traversal containment.
            let canon = match fs::canonicalize(&path) {
                Ok(p) => p,
                Err(_) => {
                    errors.push(error(
                        rel_path(&canon_root, &path),
                        "L05",
                        "could not canonicalize path (broken symlink?)",
                    ));
                    continue;
                }
            };
            if !canon.starts_with(&canon_root) {
                errors.push(error(
                    rel_path(&canon_root, &path),
                    "L05",
                    "path escapes lifecycle root after canonicalization",
                ));
                continue;
            }

            match index_doc(&canon_root, &canon, name) {
                Ok(indexed) => {
                    idx.insert(indexed.path.clone(), indexed);
                }
                Err(e) => errors.push(e),
            }
        }
    }

    (idx, errors)
}

/// Parse one doc's frontmatter and extract the lifecycle-relevant
/// fields.
fn index_doc(
    canon_root: &Path,
    canon_path: &Path,
    basename: &str,
) -> Result<IndexedDoc, ValidationError> {
    let rel = rel_path(canon_root, canon_path);
    let doc = parse_doc(canon_path).map_err(|e| {
        error(rel.clone(), "L05", &format!("frontmatter parse failed: {}", e))
    })?;

    let format = match crate::formats::detect_format(basename) {
        Some(spec) => spec.name,
        None => {
            return Err(error(
                rel.clone(),
                "L05",
                "format could not be detected from filename",
            ));
        }
    };

    let status = doc.status.clone();
    let execution_mode = doc
        .fields
        .get("execution_mode")
        .map(|f| f.value.clone())
        .unwrap_or_default();

    let upstreams = extract_upstreams(canon_root, canon_path, &doc);

    Ok(IndexedDoc {
        path: canon_path.to_path_buf(),
        format,
        status,
        execution_mode,
        upstreams,
    })
}

/// Pull the `upstream:` field from a parsed doc and resolve each entry
/// against the root.
///
/// Entries come from [`crate::upstream::upstream_entries`], the one
/// normalization path all three `upstream:` readers share: it handles the
/// scalar and sequence shapes, trims, and skips template placeholders. What
/// is left here is the resolution this function owns -- joining the
/// canonical root, canonicalizing, and suppressing a self-reference -- plus
/// dropping cross-repo entries, which name a file in another repository and
/// so have no local path to join. (The entry is marked rather than removed
/// by the shared helper precisely because the finalization walk needs to see
/// it in order to stop at it; the lifecycle index holds resolved local paths,
/// which a cross-repo reference has none of.)
fn extract_upstreams(canon_root: &Path, canon_path: &Path, doc: &Doc) -> Vec<PathBuf> {
    let mut out = Vec::new();

    for entry in crate::upstream::upstream_entries(doc) {
        if entry.cross_repo {
            continue;
        }
        // Resolve as relative-to-root.
        let resolved = canon_root.join(&entry.value);
        // Try to canonicalize; if it fails (file missing), keep the
        // joined path so L04 can report the missing reference.
        let final_path = fs::canonicalize(&resolved).unwrap_or(resolved);
        // Suppress self-reference: a doc whose upstream resolves to
        // itself is treated as having no upstream (defensive against
        // a self-edge cycle).
        if final_path == canon_path {
            continue;
        }
        out.push(final_path);
    }

    out
}

/// Build the inverse-upstream graph: for each parent path, list the
/// child paths that point at it via `upstream:`.
fn build_inverse_upstream(idx: &DocIndex) -> InverseGraph {
    let mut inv = InverseGraph::new();
    for (child_path, indexed) in idx {
        for parent in &indexed.upstreams {
            inv.entry(parent.clone())
                .or_insert_with(Vec::new)
                .push(child_path.clone());
        }
    }
    inv
}

// ---------- referrer map (the narrow API the finalization walk reads) ----------

/// One document that names another document as its `upstream:`.
///
/// The finalization walk consults these before retiring an ancestor: a
/// document that still names the ancestor, has not reached its own terminal
/// state, and is not itself being retired by that walk is a consumer whose
/// reference the retirement would strand.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Referrer {
    /// Canonical path of the referring document.
    pub path: PathBuf,
    /// Detected format name: `Brief`, `PRD`, `Design`, `Plan`, `Roadmap`.
    pub format: String,
    /// The referring document's frontmatter `status:`.
    pub status: String,
}

impl Referrer {
    /// Whether this document has reached its type's terminal state, and so
    /// has stopped consuming what it points at. A PLAN or ROADMAP retires by
    /// deletion ([`TargetState::Deleted`]), so one still present in the tree
    /// has not reached its terminal state whatever its status says.
    pub fn is_terminal(&self) -> bool {
        match target_state_for(&self.format) {
            TargetState::Status(terminal) => self.status == terminal,
            TargetState::Deleted | TargetState::Unknown => false,
        }
    }
}

/// Referrer map: a document's canonical path -> every document that names it
/// as an upstream, in canonical-path order.
pub type ReferrerMap = BTreeMap<PathBuf, Vec<Referrer>>;

/// Build the referrer map for the doc tree under `root`, keyed by the same
/// canonical paths the index is keyed by (see [`canonicalize_indexed_path`]).
///
/// This is the narrow graph-level API over the lifecycle index: one index
/// build, one inversion, and no second `upstream:` parse -- the entries come
/// from the same [`crate::upstream`] helper every other reader uses. The
/// returned errors are the index-construction errors, which a caller that
/// must know the map may be incomplete reads; the map itself is usable
/// either way.
pub fn build_referrer_map(root: &Path) -> (ReferrerMap, Vec<ValidationError>) {
    let (idx, errors) = build_doc_index(root);
    let mut map = ReferrerMap::new();
    for (upstream_path, children) in build_inverse_upstream(&idx) {
        let referrers: Vec<Referrer> = children
            .iter()
            .filter_map(|child| idx.get(child))
            .map(|doc| Referrer {
                path: doc.path.clone(),
                format: doc.format.clone(),
                status: doc.status.clone(),
            })
            .collect();
        if !referrers.is_empty() {
            map.insert(upstream_path, referrers);
        }
    }
    (map, errors)
}

/// The canonicalization primitive the doc index keys on. A caller that looks
/// a path up in a [`ReferrerMap`] must canonicalize it the same way, or the
/// two disagree about which document a path names.
pub fn canonicalize_indexed_path(path: &Path) -> Option<PathBuf> {
    fs::canonicalize(path).ok()
}

// ---------- chain discovery + posture inference ----------

/// Discover all chains in the index. Each chain is rooted at a PLAN
/// or ROADMAP and walks the forward `upstream:` edge to gather BRIEF,
/// PRD, DESIGN members.
///
/// The walk follows *every* entry of a multi-valued `upstream:`, not
/// just the first. A document naming two upstreams is therefore a
/// member of both chains above it, which is the whole point: an
/// `upstream:` entry is a membership edge, and a walk that reads only
/// the first entry silently decides that the rest are not.
///
/// Cycles in the upstream graph produce an L03 error and the cyclic
/// chain is dropped from the result. Cycles are tracked per branch
/// rather than across the traversal, because the fan-out makes the two
/// different: a *diamond* — two upstream entries reconverging on a
/// common ancestor — revisits a node the traversal has already seen
/// without that node ever appearing twice on one root-to-node path. A
/// shared visited set cannot tell the two apart and would report the
/// diamond as a cycle, dropping a legal chain.
///
/// Reconvergence is not re-walked: the second branch to reach a node
/// stops there, since the node and everything above it are already
/// members. That cannot hide a cycle. Any cycle among a node's
/// ancestors is a property of the graph above it, so the branch that
/// expanded the node first walked into it and reported it.
fn discover_chains(idx: &DocIndex) -> (Vec<Chain>, Vec<ValidationError>) {
    let mut chains = Vec::new();
    let mut errors = Vec::new();

    for indexed in idx.values() {
        let root_kind = match indexed.format.as_str() {
            "Plan" => RootKind::Plan,
            "Roadmap" => RootKind::Roadmap,
            _ => continue,
        };

        let mut members: Vec<ChainMember> = Vec::new();
        // Nodes this chain's walk has already expanded, over the whole
        // traversal. Guards against re-walking a reconvergence point,
        // and against recording a diamond's shared ancestor twice.
        let mut expanded: HashSet<PathBuf> = HashSet::new();
        // Depth-first frontier. Each entry carries the node to expand
        // and the walk order that reached it — the root-to-parent path,
        // which is both the cycle-detection set for this branch and the
        // path an L03 message prints.
        let mut frontier: Vec<(PathBuf, Vec<PathBuf>)> =
            vec![(indexed.path.clone(), Vec::new())];

        while let Some((cur_path, branch)) = frontier.pop() {
            // Cycle check first, before the reconvergence check: a node
            // already on this branch is also already expanded, so
            // testing expansion first would swallow the cycle.
            if branch.contains(&cur_path) {
                // Cycle detected — emit L03 naming the cycle, in walk
                // order along the branch that closed it.
                let cycle_str = branch
                    .iter()
                    .chain(std::iter::once(&cur_path))
                    .map(|p| rel_path_lossy(p))
                    .collect::<Vec<_>>()
                    .join(" -> ");
                errors.push(error_path(
                    cur_path.clone(),
                    "L03",
                    &format!("upstream cycle detected: {}", cycle_str),
                ));
                members.clear();
                break;
            }

            // Reached again from a second branch: a diamond, not a
            // cycle. It is already a member and its own upstreams are
            // already walked, so this branch ends here.
            if !expanded.insert(cur_path.clone()) {
                continue;
            }

            let node = match idx.get(&cur_path) {
                Some(n) => n,
                None => {
                    // Upstream points at a missing parent — L04. Only
                    // this branch ends; sibling entries still resolve.
                    errors.push(error_path(
                        indexed.path.clone(),
                        "L04",
                        &format!(
                            "chain member missing: upstream references {} which does not exist",
                            rel_path_lossy(&cur_path)
                        ),
                    ));
                    continue;
                }
            };

            if let Some(role) = ChainRole::from_format(&node.format) {
                members.push(ChainMember {
                    path: node.path.clone(),
                    role,
                    status: node.status.clone(),
                });
            }

            // Walk to the parents. PLAN -> DESIGN -> PRD -> BRIEF in
            // the forward upstream direction.
            //
            // Stop the walk at a BRIEF: BRIEF is the chain's anchor.
            // If a BRIEF carries an `upstream:` field (e.g. pointing
            // at a parent DESIGN to record an amendment relationship),
            // that's a cross-chain reference, not a chain-membership
            // edge, and we do not follow it.
            //
            // Stop at a ROADMAP for the same reason at the other end.
            // A ROADMAP roots the tactical chain, and its own
            // `upstream:` points at the STRATEGY it operationalizes —
            // a member of the strategic chain, which this walk does
            // not model. `build_doc_index` never indexes
            // `docs/strategies/` or `docs/visions/`, so following that
            // edge reports a present file as a missing chain member
            // (L04). The strategic chain is out of scope here, not
            // absent.
            //
            // Both stops happen after the push above, so the stopping
            // node is itself a member.
            if matches!(node.format.as_str(), "Brief" | "Roadmap") {
                continue;
            }

            let mut child_branch = branch;
            child_branch.push(cur_path);
            // Pushed in reverse so the frontier pops them in written
            // order: the first `upstream:` entry is walked first, which
            // is the order a single-valued chain has always walked in.
            for parent in node.upstreams.iter().rev() {
                frontier.push((parent.clone(), child_branch.clone()));
            }
        }

        if members.is_empty() {
            continue;
        }

        // Reverse so a single-path chain reads BRIEF -> PRD -> DESIGN
        // -> PLAN. See `Chain::members` on what this ordering does and
        // does not mean once the walk branches.
        members.reverse();

        let posture = infer_posture_from(indexed);
        chains.push(Chain {
            root: indexed.path.clone(),
            members,
            root_kind,
            posture,
        });
    }

    (chains, errors)
}

/// Infer the posture from the root doc's frontmatter.
///
/// PLAN docs use a unified Draft -> Active -> Done -> DELETED
/// lifecycle. Only the Draft -> Active gate differs between modes
/// (human-approved for multi-pr, auto-fired for single-pr), so the
/// in-flight on-disk state is `Active` for both. A committed PLAN
/// at `Draft` is therefore a violation in either mode — the chain
/// posture maps it to its mode's in-flight bucket so the per-member
/// `(Plan, ...) = Status("Active")` rule fires L01 against the
/// member; the posture name in the error message tells the author
/// which gate did not run.
fn infer_posture_from(root: &IndexedDoc) -> Posture {
    if root.format == "Roadmap" {
        // ROADMAPs are multi-pr by definition. ROADMAP present at
        // Active is in-flight; Done is work-completing; absent never
        // appears here because we are iterating present docs.
        return match root.status.as_str() {
            "Done" => Posture::MultiPrWorkCompleting,
            _ => Posture::MultiPrInFlight,
        };
    }
    // PLAN root.
    if root.execution_mode == "multi-pr" {
        return match root.status.as_str() {
            "Done" => Posture::MultiPrWorkCompleting,
            // Active or Draft both bucket to in-flight; the
            // per-member rule for (Plan, MultiPrInFlight) is
            // Status("Active"), so a Draft PLAN fails L01 against
            // that expectation.
            _ => Posture::MultiPrInFlight,
        };
    }
    // single-pr or unspecified — treat as single-pr.
    match root.status.as_str() {
        // Unusual; PLAN should already be deleted at Done. The
        // at-merge passing-state row treats (Plan, ...) as Deleted,
        // so a present Done single-pr PLAN fails L01 (matching the
        // multi-pr work-completing forcing function).
        "Done" => Posture::SinglePrAtMerge,
        // Active is the on-disk mid-PR state; Draft buckets here too
        // so the (Plan, SinglePrMidPR) = Status("Active") rule fires
        // L01 against a Draft single-pr PLAN (the auto-transition
        // didn't run).
        _ => Posture::SinglePrMidPR,
    }
}

// ---------- passing-state computation ----------

/// The passing state for a chain member given the chain's posture.
///
/// Role and posture alone, which is to say: what one chain demands of
/// a document at the *root* of that chain's lineage. Position is not a
/// parameter here and cannot be — see [`required_state`], which holds
/// the one rule that depends on it.
///
/// The DESIGN is the only artifact type with a non-trivial passing-
/// state lifecycle outside the chain's primary state machine: it
/// lives at `Planned` in `docs/designs/` during in-flight phases and
/// at `Current` in `docs/designs/current/` once promoted at the
/// chain's terminal completion. We accept either at in-flight
/// postures and require `Current` at the at-merge postures.
fn compute_passing_state(role: ChainRole, posture: Posture) -> PassingState {
    use ChainRole::*;
    use Posture::*;
    match (role, posture) {
        // Multi-pr in-flight.
        (Brief, MultiPrInFlight) => PassingState::Status("Accepted"),
        (Prd, MultiPrInFlight) => PassingState::PrdAcceptedOrInProgress,
        (Design, MultiPrInFlight) => PassingState::DesignPlannedOrCurrent,
        (Plan, MultiPrInFlight) => PassingState::Status("Active"),
        (Roadmap, MultiPrInFlight) => PassingState::Status("Active"),

        // Multi-pr work-completing (intermediate failing state by design
        // for the PLAN; BRIEF/PRD/DESIGN move to their terminal states).
        (Brief, MultiPrWorkCompleting) => PassingState::Status("Done"),
        (Prd, MultiPrWorkCompleting) => PassingState::Status("Done"),
        (Design, MultiPrWorkCompleting) => PassingState::Status("Current"),
        (Plan, MultiPrWorkCompleting) => PassingState::Deleted,
        (Roadmap, MultiPrWorkCompleting) => PassingState::Deleted,

        // Multi-pr at-merge (PLAN/ROADMAP already absent; rarely reached
        // for a chain whose root is still present in the tree).
        (Brief, MultiPrAtMerge) => PassingState::Status("Done"),
        (Prd, MultiPrAtMerge) => PassingState::Status("Done"),
        (Design, MultiPrAtMerge) => PassingState::Status("Current"),
        (Plan, MultiPrAtMerge) => PassingState::Deleted,
        (Roadmap, MultiPrAtMerge) => PassingState::Deleted,

        // Single-pr mid-PR. The PLAN is at `Active`: a single-pr
        // PLAN's Draft -> Active gate auto-fires when /shirabe:plan
        // finishes authoring, so the only valid on-disk state for a
        // committed single-pr PLAN is `Active`. A Draft single-pr
        // PLAN fails L01 against this rule.
        (Brief, SinglePrMidPR) => PassingState::Status("Accepted"),
        // The PRD sits at `Accepted` until /shirabe:design starts, which
        // bumps it to `In Progress`; a single-pr chain carries the PRD,
        // DESIGN, and PLAN together, so mid-PR the PRD is legitimately at
        // either state (mirrors the multi-pr in-flight row).
        (Prd, SinglePrMidPR) => PassingState::PrdAcceptedOrInProgress,
        (Design, SinglePrMidPR) => PassingState::DesignPlannedOrCurrent,
        (Plan, SinglePrMidPR) => PassingState::Status("Active"),
        (Roadmap, SinglePrMidPR) => PassingState::Status("Active"),

        // Single-pr at-merge (PLAN absent).
        (Brief, SinglePrAtMerge) => PassingState::Status("Done"),
        (Prd, SinglePrAtMerge) => PassingState::Status("Done"),
        (Design, SinglePrAtMerge) => PassingState::Status("Current"),
        (Plan, SinglePrAtMerge) => PassingState::Deleted,
        // Unreachable, and left saying what it has always said. A
        // single-pr posture only ever comes from a PLAN root
        // (`infer_posture_from` maps a ROADMAP root to a multi-pr
        // posture and nothing else), so a ROADMAP holding this cell is
        // a member rather than a root — the case [`required_state`]
        // now answers before the table is consulted. `Active` is what
        // it answers, so the cell is not a contradiction left behind;
        // it is the same rule written twice, and flipping it to match
        // its row would make it one.
        (Roadmap, SinglePrAtMerge) => PassingState::Status("Active"),
    }
}

// ---------- obligation map ----------
//
// Every chain containing a document demands something of it. The map
// below collects those demands once, keyed by the document, so both
// entry points evaluate a document against all of them and neither can
// see a different answer from the other. The mode chooses which
// documents get reported on; it does not change what is said about
// one.

/// The chains behind one requirement: each (effective posture, chain
/// root) pair that demands it. The posture is what the message reads;
/// the root is the handle a diagnostic uses when it has to name which
/// chains are involved.
type Imposers = BTreeSet<(Posture, PathBuf)>;

/// Document path -> required status set -> the chains imposing it.
///
/// The two key levels are two thirds of a finding's identity — the
/// check code is the third, and L01 is the only code emitted from this
/// map. That is the point of keying rather than filtering afterwards:
/// two chains demanding the same state of the same document land on
/// one entry, so the duplicate is never built. It cannot be recovered
/// by textual comparison either, because the message names every
/// posture behind the entry and so differs from what either chain
/// alone would have written.
type ObligationMap = BTreeMap<PathBuf, BTreeMap<PassingState, Imposers>>;

/// The posture a chain is evaluated at, which is not always the
/// posture it carries.
///
/// Under `ReviewPosture::Ready` a single-pr chain mid-PR is held to
/// the at-merge row: the PR is up for review, so the PLAN should be
/// gone and BRIEF/PRD/DESIGN at their terminal states. Multi-pr
/// postures are unaffected. Applied once, at map-build time, so no
/// consumer downstream of the map ever handles a raw chain posture.
fn effective_posture(chain: Posture, review: ReviewPosture) -> Posture {
    if review == ReviewPosture::Ready && chain == Posture::SinglePrMidPR {
        Posture::SinglePrAtMerge
    } else {
        chain
    }
}

/// What one chain requires of one of its members.
///
/// The passing-state table is keyed by role and posture, and a posture
/// is a property of the chain's root. That is the right reading for a
/// document evaluated against its own lineage, and the wrong one for a
/// document a chain merely passes through on its way up: the table
/// cannot tell the two apart, so it answers as though every member's
/// own work were the work the posture describes.
///
/// For a ROADMAP the difference is the difference between a live
/// document and a deleted one. `discover_chains` records a node as a
/// member before the stop check, so a ROADMAP reached by walking up
/// from a PLAN is a full member of that PLAN's chain — and a multi-pr
/// PLAN at `Done` puts that chain at `MultiPrWorkCompleting`, whose
/// ROADMAP cell requires absence. Read straight off the table, one
/// feature finishing beneath a ROADMAP demands the ROADMAP be deleted
/// while the rest of its features are still running.
///
/// So: a ROADMAP that is not the root of the chain being evaluated is
/// required to be `Active`. Only a ROADMAP's own chain — the one
/// rooted at it, whose completion is its completion — can require its
/// absence, and that path still runs through the table unchanged.
///
/// `Active` rather than the weaker "present": the two differ on a
/// retired ROADMAP above a still-completing chain, which "present"
/// lets pass and which is a real finding.
fn required_state(member: &ChainMember, chain: &Chain, posture: Posture) -> PassingState {
    if member.role == ChainRole::Roadmap && member.path != chain.root {
        return PassingState::Status("Active");
    }
    compute_passing_state(member.role, posture)
}

/// Build the obligation map over every discovered chain.
fn build_obligations(chains: &[Chain], review: ReviewPosture) -> ObligationMap {
    let mut map = ObligationMap::new();
    for chain in chains {
        let posture = effective_posture(chain.posture, review);
        for member in &chain.members {
            map.entry(member.path.clone())
                .or_default()
                .entry(required_state(member, chain, posture))
                .or_default()
                .insert((posture, chain.root.clone()));
        }
    }
    map
}

/// The trailing clause of an L01 message, naming the postures that
/// demand the state.
///
/// One requirement can come from several chains at once, so the clause
/// has to stay true for all of them rather than pick one and imply the
/// others do not exist. A single posture reads exactly as it always
/// has; beyond one the names are listed and the noun pluralizes.
fn posture_clause(imposers: &Imposers) -> String {
    let postures: BTreeSet<Posture> = imposers.iter().map(|(p, _)| *p).collect();
    let names: Vec<&'static str> = postures.iter().map(|p| p.name()).collect();
    match names.split_last() {
        Some((last, [])) => format!("{} posture", last),
        Some((last, init)) => format!("{} and {} postures", init.join(", "), last),
        // Unreachable: an entry exists only because something inserted
        // an imposer into it.
        None => "an unknown posture".to_string(),
    }
}

// ---------- conflict detection ----------

/// One chain's demand on one document: which chain, at what posture,
/// and the set it requires.
///
/// The obligation map keys by required set and folds every chain
/// demanding it into a single entry, which is what makes an L01
/// unique. A conflict is about the chains rather than about the
/// requirement, and its message has to name them, so this reads the
/// map back apart into one requirement per chain.
#[derive(Clone, Copy)]
struct Requirement<'a> {
    state: &'a PassingState,
    posture: Posture,
    root: &'a Path,
}

/// Whether two chains' demands on one document cannot both be met.
///
/// Disjointness of the required status sets, not inequality. Two
/// chains wanting different-but-overlapping things — one accepting a
/// DESIGN at `Planned` or `Current`, another insisting on `Current` —
/// agree at the intersection, and that is the ordinary shape of a
/// shared document rather than a fault. Inequality as the test would
/// fire on every shared DESIGN, which is the case the intersection
/// protects.
///
/// `Deleted` is the value that needs the rule stated rather than
/// inferred. It denotes the empty set, and the empty set is disjoint
/// from everything including itself, so a bare disjointness test fires
/// on two chains that both correctly require the same PLAN deleted —
/// perfect agreement reported as conflict, on correct state. So:
/// absence against a status conflicts, and absence against absence
/// agrees.
fn requirements_conflict(a: &PassingState, b: &PassingState) -> bool {
    match (a, b) {
        (PassingState::Deleted, PassingState::Deleted) => false,
        (PassingState::Deleted, _) | (_, PassingState::Deleted) => true,
        _ => a.statuses().is_disjoint(&b.statuses()),
    }
}

/// The chain-level requirements on one document, in the map's order:
/// by required set, then by (posture, chain root) within a set. Both
/// levels are ordered collections, so the order is stable across runs
/// and the message reads the same twice.
fn requirements_of(required: &BTreeMap<PassingState, Imposers>) -> Vec<Requirement<'_>> {
    required
        .iter()
        .flat_map(|(state, imposers)| {
            imposers.iter().map(move |(posture, root)| Requirement {
                state,
                posture: *posture,
                root: root.as_path(),
            })
        })
        .collect()
}

/// Every requirement participating in at least one conflicting pair.
///
/// Pairwise over chains rather than over the map's entries. The two
/// give the same answer — whether a requirement conflicts depends only
/// on the set it names, so two chains behind one entry participate or
/// abstain together — but the entry-level scan would never compare two
/// requirements of absence to each other, since they share a key and
/// merge. Comparing chains keeps the absence-agrees rule on a path the
/// code actually walks.
fn conflicting_requirements<'a>(reqs: &[Requirement<'a>]) -> Vec<Requirement<'a>> {
    let mut participates = vec![false; reqs.len()];
    for i in 0..reqs.len() {
        for j in (i + 1)..reqs.len() {
            if requirements_conflict(reqs[i].state, reqs[j].state) {
                participates[i] = true;
                participates[j] = true;
            }
        }
    }
    reqs.iter()
        .zip(participates)
        .filter(|(_, p)| *p)
        .map(|(r, _)| *r)
        .collect()
}

/// The conflict finding: one message naming every chain that
/// participates and the full set each requires.
///
/// A new code rather than a second flavour of L01. The `L0n` family
/// names kinds, and a lineage conflict is not a state-versus-posture
/// mismatch — the document may well be at a status some chain is happy
/// with. It is also unregistered in
/// [`crate::validate::posture_class`], which falls through to
/// always-enforced, so it carries the severity of the findings it
/// replaces in both postures.
fn conflict_finding(
    path: &Path,
    role: ChainRole,
    conflicting: &[Requirement<'_>],
) -> ValidationError {
    let roots: BTreeSet<&Path> = conflicting.iter().map(|r| r.root).collect();
    let clauses: Vec<String> = conflicting
        .iter()
        .map(|r| {
            format!(
                "the chain rooted at {} ({}) expected {}",
                rel_path_lossy(r.root),
                r.posture.name(),
                r.state.describe(),
            )
        })
        .collect();
    error_path(
        path.to_path_buf(),
        "L08",
        &format!(
            "{} is required in conflicting states by {} chains: {}. No single status satisfies all of them, so the per-chain status findings are withheld in favour of this one.",
            role.as_str(),
            roots.len(),
            clauses.join("; "),
        ),
    )
}

// ---------- emission ----------

/// Report on every document in `scope`, against the obligations the
/// whole corpus places on it.
///
/// The single place a per-document lifecycle finding is produced. A
/// document some chain demands something of is checked against every
/// demand; a document no chain reaches is subject to the orphan rule
/// instead, which is the same partition the two loops drew before
/// (chain membership always yields an obligation, since every member
/// has a role and the passing-state table is total).
///
/// `scope` is what the mode controls, and the only thing it controls.
fn emit_document_findings(
    scope: &BTreeSet<PathBuf>,
    obligations: &ObligationMap,
    idx: &DocIndex,
    inv: &InverseGraph,
) -> Vec<ValidationError> {
    let mut errors: Vec<ValidationError> = Vec::new();
    for path in scope {
        let doc = match idx.get(path) {
            Some(d) => d,
            None => continue,
        };
        let required = match obligations.get(path) {
            Some(r) => r,
            None => {
                if let Some(err) = check_orphan(doc, idx, inv) {
                    errors.push(err);
                }
                continue;
            }
        };
        let role = match ChainRole::from_format(&doc.format) {
            Some(r) => r,
            None => continue,
        };
        // Conflict first: when no status satisfies every chain, the
        // document is told so once instead of being handed the
        // instructions it cannot both follow. The requirements behind
        // the conflict are withheld; any requirement that intersects
        // everything else still speaks for itself below, and so do the
        // findings of every other kind on this document.
        //
        // Supersession is safe by construction rather than by care: if
        // no status satisfies every chain, this document's status
        // satisfies at most one of them, so at least one of the
        // withheld findings had fired. The replacement is one-for-N
        // with N at least one, never one-for-zero.
        let conflicting = conflicting_requirements(&requirements_of(required));
        let superseded: BTreeSet<&PassingState> =
            conflicting.iter().map(|r| r.state).collect();
        if !conflicting.is_empty() {
            errors.push(conflict_finding(path, role, &conflicting));
        }

        for (state, imposers) in required {
            if superseded.contains(state) {
                continue;
            }
            // The document was discovered by walking the index, so it
            // is present in the tree by definition and
            // `PassingState::Deleted` always fails — that is the
            // work-completing posture's forcing function for the
            // deletion commit. Other variants compare against the
            // document's current status.
            let mismatch = match state {
                PassingState::Deleted => true,
                _ => !state.matches(&doc.status),
            };
            if !mismatch {
                continue;
            }
            errors.push(error_path(
                path.clone(),
                "L01",
                &format!(
                    "{} at status '{}' (expected {} for {})",
                    role.as_str(),
                    doc.status,
                    state.describe(),
                    posture_clause(imposers),
                ),
            ));
        }
    }
    errors
}

/// The documents the chain-targeted mode reports on: the members of
/// every chain containing `target`.
///
/// A *shallow* closure. It deliberately does not go on to add the
/// members of chains containing those members: in a corpus where the
/// chains interlock, that transitive walk reaches everything and the
/// targeted mode stops being distinguishable from the whole-tree one,
/// which is the entire reason the mode exists.
///
/// A target no chain contains yields just the target, so the orphan
/// rule reaches it.
fn chain_targeted_scope(chains: &[Chain], target: &Path) -> BTreeSet<PathBuf> {
    let mut scope: BTreeSet<PathBuf> = BTreeSet::new();
    for chain in containing_chains(chains, target) {
        for member in &chain.members {
            scope.insert(member.path.clone());
        }
    }
    if scope.is_empty() {
        scope.insert(target.to_path_buf());
    }
    scope
}

/// The chains `target` is a member of. More than one once a document
/// names two upstreams, or two documents name it.
fn containing_chains<'a>(chains: &'a [Chain], target: &Path) -> Vec<&'a Chain> {
    chains
        .iter()
        .filter(|c| c.members.iter().any(|m| m.path == target))
        .collect()
}

// ---------- orphan-doc rule ----------
//
// See docs/decisions/DECISION-orphan-doc-passing-state-rule-2026-06-06.md
// for the rule's full Context, Options Considered, and Consequences.
//
// In short: an orphan doc (no inverse-upstream reference from any
// other doc) at its artifact's target state passes; an orphan at non-
// terminal status whose own upstream points at an Active ROADMAP
// passes (ROADMAP-rooted in-flight case); an orphan that is a member
// of a coherent multi-member tactical chain (linked to another
// BRIEF/PRD/DESIGN/PLAN by `upstream:`) passes (the pre-PLAN in-flight
// case — a standalone chain with no ROADMAP root, exactly what /scope
// produces); every other orphan fails with L02.

fn check_orphan(
    doc: &IndexedDoc,
    idx: &DocIndex,
    inv: &InverseGraph,
) -> Option<ValidationError> {
    // Plans and roadmaps are the chain roots — they are never
    // "orphan" in this sense; their own lifecycle posture is what
    // drives the chain check above.
    if doc.format == "Plan" || doc.format == "Roadmap" {
        return None;
    }

    let target = target_state_for(&doc.format);
    // Terminal-state orphan: pass.
    if let TargetState::Status(s) = target {
        if doc.status == s {
            return None;
        }
    }

    // Non-terminal orphan with own upstream pointing at an Active ROADMAP: pass.
    for parent_path in &doc.upstreams {
        if let Some(parent) = idx.get(parent_path) {
            if parent.format == "Roadmap" && parent.status == "Active" {
                return None;
            }
        }
    }

    // In-flight tactical chain: a non-terminal doc that is linked to at
    // least one other tactical-chain artifact — it has a downstream
    // child pointing at it via `upstream:`, or its own `upstream:`
    // resolves to a BRIEF/PRD/DESIGN/PLAN present in the tree — is a
    // member of a coherent, progressing chain, not a lone stuck doc.
    // The drift this rule targets is a single isolated artifact (the
    // reason the orphan-permissive option was rejected); a linked
    // multi-member chain with no ROADMAP root is active work. A public
    // repo whose roadmap is private can never satisfy the active-ROADMAP
    // exception above, so this linkage signal is the only one available
    // to it mid-flight. (See the chain-aware refinement recorded in
    // DECISION-orphan-doc-passing-state-rule-2026-06-06.md.)
    //
    // This linkage signal is deliberately single-hop and looser than
    // `discover_chains`' membership edge (which only roots at a PLAN/
    // ROADMAP and treats a BRIEF's upstream as a cross-chain reference):
    // here any inbound or outbound tactical edge is enough to mark the
    // doc as part of active work. Do not try to unify the two traversals.
    //
    // The downstream side is intentionally unfiltered — any doc pointing
    // at this one via `upstream:` means someone is building on it. The
    // upstream side is filtered to the tactical artifact types and
    // intentionally EXCLUDES "Roadmap": a ROADMAP upstream passes only
    // when Active, via the separate branch above. Admitting "Roadmap"
    // here would let a non-Active (aged-out) ROADMAP upstream suppress
    // drift, reintroducing exactly the hole the DECISION doc books as an
    // accepted, deferred trade-off. Do not add "Roadmap" to this match.
    let has_downstream_child = inv.get(&doc.path).is_some_and(|kids| !kids.is_empty());
    let has_tactical_upstream = doc.upstreams.iter().any(|p| {
        idx.get(p)
            .is_some_and(|parent| matches!(parent.format.as_str(), "Brief" | "PRD" | "Design" | "Plan"))
    });
    if has_downstream_child || has_tactical_upstream {
        return None;
    }

    // Every other orphan fails L02.
    let expected = match target {
        TargetState::Status(s) => format!("status '{}'", s),
        TargetState::Deleted => "DELETED".to_string(),
        TargetState::Unknown => "target state unknown".to_string(),
    };
    let rel = rel_path_lossy(&doc.path);
    Some(error(
        rel,
        "L02",
        &format!(
            "orphan {} at status '{}' (expected {}, an Active ROADMAP upstream, or a tactical upstream/downstream chain link)",
            doc.format.to_uppercase(),
            doc.status,
            expected
        ),
    ))
}

// ---------- document-location-vs-status rule ----------
//
// L07: a DESIGN's on-disk directory must agree with its status. The DESIGN
// is the one artifact type whose lifecycle moves it between directories:
// `Proposed`/`Accepted`/`Planned` live in `docs/designs/`, and `Current`
// (the terminal post-promotion state) lives in `docs/designs/current/`. A
// `Current` DESIGN still sitting in `docs/designs/` -- or a non-`Current`
// DESIGN already in `docs/designs/current/` -- is drift the chain check does
// not catch (it validates status against posture, not status against path).
// This is a corpus-wide, path-dependent check, so it runs through the
// lifecycle traversal rather than the per-file `validate_file` pass, and its
// code stays out of the per-file `--check` registry like the rest of the
// L-family.

fn check_location(doc: &IndexedDoc) -> Option<ValidationError> {
    if doc.format != "Design" {
        return None;
    }
    let in_current = doc.path.to_string_lossy().contains("/designs/current/");
    let rel = rel_path_lossy(&doc.path);
    if in_current && doc.status != "Current" {
        return Some(error(
            rel,
            "L07",
            &format!(
                "DESIGN at status '{}' is in docs/designs/current/ (that directory is for status 'Current' only)",
                doc.status
            ),
        ));
    }
    if !in_current && doc.status == "Current" {
        return Some(error(
            rel,
            "L07",
            "DESIGN at status 'Current' must live in docs/designs/current/, not docs/designs/",
        ));
    }
    None
}

// ---------- public entry point ----------

/// Run the chain-aware passing-state lifecycle check against `root`.
///
/// Returns an empty vec when every chain member is at its passing
/// state and every orphan doc honors the orphan-rule. Otherwise
/// returns one or more `ValidationError`s carrying `Lnn` codes.
///
/// The `posture` argument controls the DRAFT-vs-READY discipline for
/// single-pr chains. Under `ReviewPosture::Draft`, `Posture::SinglePrMidPR`
/// is a passing posture — BRIEF/PRD at Accepted, DESIGN at
/// Planned/Current, PLAN at Draft is healthy iteration. Under
/// `ReviewPosture::Ready`, `Posture::SinglePrMidPR` is re-targeted to the
/// `Posture::SinglePrAtMerge` passing-state row, so a present single-pr
/// PLAN fails and single-pr BRIEF/PRD at Accepted fail. Multi-pr
/// postures are unchanged by the posture. The re-target happens once,
/// as the obligation map is built (see [`effective_posture`]).
///
/// The scope is every indexed document. Corpus-integrity findings —
/// the index and chain errors, L03/L04/L05 — are whole-corpus here and
/// in the chain-targeted mode alike; they are properties of the corpus
/// rather than of a document under review.
///
/// `ReviewPosture::Ready` is the successor of the old `strict == true`:
/// the CI workflow asserts `Ready` when the PR is ready-for-review
/// (`github.event.pull_request.draft == false`) and `Draft` when the PR is
/// draft.
pub fn run_lifecycle_check(
    root: &Path,
    cfg: &Config,
    posture: ReviewPosture,
) -> Vec<ValidationError> {
    let (idx, mut errors) = build_doc_index(root);
    let inv = build_inverse_upstream(&idx);
    let (chains, chain_errors) = discover_chains(&idx);
    errors.extend(chain_errors);

    // Per-document findings — passing state where a chain reaches the
    // document, the orphan rule where none does.
    let obligations = build_obligations(&chains, posture);
    let scope: BTreeSet<PathBuf> = idx.keys().cloned().collect();
    errors.extend(emit_document_findings(&scope, &obligations, &idx, &inv));

    // L06: outline-AC completeness. Chain-keyed rather than
    // document-keyed — it needs the chain to locate its subject — so it
    // runs per chain rather than through the emitter.
    for chain in &chains {
        errors.extend(check_l06_outline_acs(chain, &idx, cfg));
    }

    // L07 location-vs-status rule, over every indexed doc (chain member or
    // not -- a Current design is terminal and orphan, but its directory must
    // still agree with its status).
    for doc in idx.values() {
        if let Some(err) = check_location(doc) {
            errors.push(err);
        }
    }

    sort_findings(&mut errors);
    errors
}

// ---------- L06: outline-AC completeness ----------

/// Check that every `- [ ]` / `- [x]` / `- [X]` outline-AC checkbox on
/// the chain's PLAN is ticked.
///
/// Fires only when the chain has a single-pr PLAN present in the tree:
/// multi-pr PLANs carry their issues in the `## Implementation Issues`
/// table without per-AC checkboxes, so the parser returns an empty
/// vector for them and L06 cannot trigger. Non-PLAN-rooted chains
/// (ROADMAP roots) likewise carry no outline ACs.
///
/// One L06 error per unticked AC. The message names the outline-key,
/// the verbatim AC text, and the 1-indexed line number so the author
/// can navigate to the offending box directly.
fn check_l06_outline_acs(
    chain: &Chain,
    idx: &DocIndex,
    cfg: &Config,
) -> Vec<ValidationError> {
    if cfg.allow_untracked_acs {
        return Vec::new();
    }
    let mut errors: Vec<ValidationError> = Vec::new();
    for member in &chain.members {
        if member.role != ChainRole::Plan {
            continue;
        }
        let indexed = match idx.get(&member.path) {
            Some(d) => d,
            None => continue,
        };
        if indexed.execution_mode != "single-pr" {
            continue;
        }
        // Re-parse the PLAN body. The doc index carries only the
        // frontmatter-derived metadata; L06 needs the body to find
        // the AC checkboxes. The cost is one file read per cascade
        // invocation, which is negligible against the cascade's
        // existing validator surface.
        let doc = match parse_doc(&member.path) {
            Ok(d) => d,
            Err(_) => {
                // A frontmatter parse failure is already surfaced as
                // L05 by `index_doc`; the L06 check has nothing to
                // contribute on a doc whose body cannot be reached.
                continue;
            }
        };
        for ac in parse_outline_acs(&doc) {
            if ac.ticked {
                continue;
            }
            errors.push(error_path(
                member.path.clone(),
                "L06",
                &format!(
                    "outline '{}' has unticked acceptance criterion: '{}' (line {})",
                    ac.outline_key, ac.ac_text, ac.line
                ),
            ));
        }
    }
    errors
}

// ---------- chain-targeted entry point ----------

/// Run the chain-aware passing-state lifecycle check against the
/// chains containing `doc_path`.
///
/// The whole-tree mode (`run_lifecycle_check`) reports on every
/// indexed document; this chain-targeted mode reports only on the
/// members of the chains `doc_path` belongs to. The cascade script in
/// `skills/work-on/scripts/run-cascade.sh` uses this mode to verify
/// its own chain's posture without surfacing unrelated drift as noise.
///
/// The narrowing is a scope, not a different check. Both modes state
/// the same thing about a document they both report on, because both
/// read the same obligation map, built over every chain in the corpus.
/// Corpus-integrity findings (L03/L04/L05) are whole-corpus here too.
///
/// The `doc_path` argument may name any chain member: PLAN, DESIGN,
/// PRD, BRIEF, or ROADMAP. The function canonicalizes the path,
/// derives the implied root by stripping the matching `docs/...`
/// suffix, builds the doc index against that root, and takes the
/// chains containing the canonicalized path.
///
/// Returns an empty vec on a clean pass. Returns one or more
/// `ValidationError`s otherwise. A non-doc-path input, a path with
/// an unrecognized artifact prefix, or a path that does not resolve
/// inside the indexed doc directories all produce a single L05
/// error naming the expected location set.
///
/// The `posture` argument has the same shape as `run_lifecycle_check`'s —
/// under `ReviewPosture::Ready` and a matched chain at
/// `Posture::SinglePrMidPR`, the chain re-targets to
/// `Posture::SinglePrAtMerge`. Multi-pr postures are unchanged by the
/// posture.
pub fn run_lifecycle_chain_check(
    doc_path: &Path,
    cfg: &Config,
    posture: ReviewPosture,
) -> Vec<ValidationError> {
    // Resolve the input path to an absolute canonical form. A
    // missing file or a path outside the filesystem produces a
    // single L05 error.
    let canon_doc = match fs::canonicalize(doc_path) {
        Ok(p) => p,
        Err(_) => {
            return vec![error(
                doc_path.display().to_string(),
                "L05",
                &format!(
                    "doc path not found or not resolvable: {} (expected a doc under docs/{{briefs,prds,designs,designs/current,plans,roadmaps}}/)",
                    doc_path.display()
                ),
            )];
        }
    };

    // The basename must carry one of the recognized artifact
    // prefixes so the lifecycle module can identify the artifact
    // type. A path inside docs/ that names a non-artifact file (e.g.
    // README.md) is rejected here.
    let basename = match canon_doc.file_name().and_then(|s| s.to_str()) {
        Some(n) => n,
        None => {
            return vec![error(
                doc_path.display().to_string(),
                "L05",
                "doc path has no filename component",
            )];
        }
    };
    if !(basename.starts_with("BRIEF-")
        || basename.starts_with("PRD-")
        || basename.starts_with("DESIGN-")
        || basename.starts_with("PLAN-")
        || basename.starts_with("ROADMAP-"))
    {
        return vec![error(
            doc_path.display().to_string(),
            "L05",
            &format!(
                "doc path '{}' has an unrecognized artifact prefix (expected BRIEF-/PRD-/DESIGN-/PLAN-/ROADMAP-)",
                basename
            ),
        )];
    }

    // Derive the implied root by stripping the matching docs/...
    // suffix from the canonicalized path. The lifecycle module's
    // indexed directories are
    // docs/{briefs,prds,designs,designs/current,plans,roadmaps}; the
    // input doc must sit directly inside one of them.
    let root = match derive_chain_root(&canon_doc) {
        Some(r) => r,
        None => {
            return vec![error(
                doc_path.display().to_string(),
                "L05",
                &format!(
                    "doc path '{}' is not inside docs/{{briefs,prds,designs,designs/current,plans,roadmaps}}/",
                    canon_doc.display()
                ),
            )];
        }
    };

    let (idx, mut errors) = build_doc_index(&root);

    // The doc must appear in the index we just built. If it does
    // not, the index-building step rejected it (e.g. frontmatter
    // parse failure) and the error is already in `errors`. Return
    // those errors as-is.
    if !idx.contains_key(&canon_doc) {
        if errors.is_empty() {
            errors.push(error(
                rel_path_lossy(&canon_doc),
                "L05",
                "doc not found in lifecycle index (frontmatter parse failure or non-standard placement)",
            ));
        }
        return errors;
    }

    let inv = build_inverse_upstream(&idx);
    let (chains, chain_errors) = discover_chains(&idx);
    errors.extend(chain_errors);

    // The obligation map is built over every chain in the corpus, not
    // only the ones in scope. That is what makes the two modes agree:
    // a document reported on here is held to the same requirements the
    // whole-tree mode would state, including ones arriving from chains
    // the target is not part of.
    let obligations = build_obligations(&chains, posture);
    let scope = chain_targeted_scope(&chains, &canon_doc);
    errors.extend(emit_document_findings(&scope, &obligations, &idx, &inv));

    // L06: outline-AC completeness, once per chain in scope.
    for chain in containing_chains(&chains, &canon_doc) {
        errors.extend(check_l06_outline_acs(chain, &idx, cfg));
    }

    sort_findings(&mut errors);
    errors
}

/// Order findings by file, then code, then message, and drop exact
/// repeats.
///
/// The dedup is not what keeps L01 unique — the obligation map's keys
/// do that, by construction — it is for the codes emitted outside the
/// map, where one document can be reached by two chains' worth of
/// chain-keyed checking.
fn sort_findings(errors: &mut Vec<ValidationError>) {
    errors.sort_by(|a, b| {
        a.file
            .cmp(&b.file)
            .then(a.code.cmp(&b.code))
            .then(a.message.cmp(&b.message))
    });
    errors.dedup();
}

/// Walk up from `doc_path` to find the implied lifecycle root — the
/// directory that contains a `docs/` subdirectory matching one of
/// the indexed locations. Returns `None` if the path does not sit
/// inside one of the recognized doc dirs.
fn derive_chain_root(doc_path: &Path) -> Option<PathBuf> {
    // The doc must live in one of these directories (relative to
    // the lifecycle root). We walk the path components from leaf to
    // root, accumulating segments until we identify the matching
    // suffix and return the prefix.
    //
    // Example: /repo/docs/plans/PLAN-foo.md
    //   parent = /repo/docs/plans
    //   parent matches "docs/plans" suffix -> root = /repo
    //
    // Example: /repo/docs/designs/current/DESIGN-foo.md
    //   parent = /repo/docs/designs/current
    //   parent matches "docs/designs/current" suffix -> root = /repo
    let parent = doc_path.parent()?;

    let suffixes: &[&str] = &[
        "docs/designs/current",
        "docs/briefs",
        "docs/prds",
        "docs/designs",
        "docs/plans",
        "docs/roadmaps",
    ];

    for suffix in suffixes {
        if let Some(root) = strip_suffix_path(parent, suffix) {
            return Some(root);
        }
    }
    None
}

/// Strip a multi-component path suffix from `path`. Returns the
/// prefix on success. Uses string-form comparison to handle the
/// multi-segment suffixes (e.g. "docs/designs/current").
fn strip_suffix_path(path: &Path, suffix: &str) -> Option<PathBuf> {
    let path_s = path.to_str()?;
    // Match either an exact suffix at the end or a "/<suffix>" tail.
    let needle = format!("/{}", suffix);
    if path_s.ends_with(&needle) {
        let prefix_len = path_s.len() - needle.len();
        return Some(PathBuf::from(&path_s[..prefix_len]));
    }
    if path_s == suffix {
        return Some(PathBuf::from(""));
    }
    None
}

// ---------- helpers ----------

fn error(file: String, code: &str, message: &str) -> ValidationError {
    ValidationError {
        file,
        line: 1,
        code: code.to_string(),
        message: format!("[{}] {}", code, message),
    }
}

fn error_path(path: PathBuf, code: &str, message: &str) -> ValidationError {
    error(rel_path_lossy(&path), code, message)
}

fn rel_path(root: &Path, path: &Path) -> String {
    match path.strip_prefix(root) {
        Ok(rel) => rel.display().to_string(),
        Err(_) => path.display().to_string(),
    }
}

fn rel_path_lossy(path: &Path) -> String {
    // Strip up to the docs/ segment so error files match the
    // repo-relative paths users expect.
    let s = path.display().to_string();
    if let Some(idx) = s.rfind("/docs/") {
        return s[idx + 1..].to_string();
    }
    s
}

// suppress an unused-variable warning for HashMap import; it's used
// by future expansions of the lifecycle module.
#[allow(dead_code)]
fn _hashmap_used<K, V>(_: HashMap<K, V>) {}

// ---------- tests ----------

#[cfg(test)]
mod tests {
    use super::*;
    use std::fs;
    use std::path::PathBuf;
    use std::sync::atomic::{AtomicUsize, Ordering};

    static COUNTER: AtomicUsize = AtomicUsize::new(0);

    /// Build a temp directory with the standard `docs/` subdirectories
    /// and write the given docs into it. Each tuple is
    /// `(repo-relative-path, frontmatter-yaml-without-fences, body)`.
    /// Returns the canonical root.
    fn build_tree(docs: &[(&str, &str, &str)]) -> PathBuf {
        let n = COUNTER.fetch_add(1, Ordering::SeqCst);
        let root = std::env::temp_dir().join(format!(
            "shirabe-lifecycle-{}-{}",
            std::process::id(),
            n
        ));
        let _ = fs::remove_dir_all(&root);
        for sub in &[
            "docs/briefs",
            "docs/prds",
            "docs/designs",
            "docs/designs/current",
            "docs/plans",
            "docs/roadmaps",
        ] {
            fs::create_dir_all(root.join(sub)).unwrap();
        }
        for (rel, frontmatter, body) in docs {
            let path = root.join(rel);
            if let Some(parent) = path.parent() {
                fs::create_dir_all(parent).unwrap();
            }
            let content = format!("---\n{}---\n\n{}\n", frontmatter, body);
            fs::write(&path, content).unwrap();
        }
        fs::canonicalize(&root).unwrap()
    }

    fn make_brief(status: &str, upstream: &str) -> String {
        let mut fm = format!(
            "schema: brief/v1\nstatus: {}\nproblem: |\n  problem.\noutcome: |\n  outcome.\n",
            status
        );
        if !upstream.is_empty() {
            fm.push_str(&format!("upstream: {}\n", upstream));
        }
        fm
    }

    fn make_prd(status: &str, upstream: &str) -> String {
        let mut fm = format!(
            "schema: prd/v1\nstatus: {}\nproblem: |\n  problem.\ngoals: |\n  goals.\n",
            status
        );
        if !upstream.is_empty() {
            fm.push_str(&format!("upstream: {}\n", upstream));
        }
        fm
    }

    fn make_design(status: &str, upstream: &str) -> String {
        let mut fm = format!(
            "schema: design/v1\nstatus: {}\nproblem: |\n  problem.\ndecision: |\n  decision.\nrationale: |\n  rationale.\n",
            status
        );
        if !upstream.is_empty() {
            fm.push_str(&format!("upstream: {}\n", upstream));
        }
        fm
    }

    fn make_plan(status: &str, execution_mode: &str, upstream: &str) -> String {
        let mut fm = format!(
            "schema: plan/v1\nstatus: {}\nexecution_mode: {}\nmilestone: \"m\"\nissue_count: 1\n",
            status, execution_mode
        );
        if !upstream.is_empty() {
            fm.push_str(&format!("upstream: {}\n", upstream));
        }
        fm
    }

    fn make_roadmap(status: &str) -> String {
        format!(
            "schema: roadmap/v1\nstatus: {}\ntheme: |\n  theme.\nscope: |\n  scope.\n",
            status
        )
    }

    fn body_for(kind: &str, status: &str) -> String {
        format!(
            "# {}: t\n\n## Status\n\n{}\n\n## Problem Statement\n\nProblem.\n\n## User Outcome\n\nOutcome.\n\n## User Journeys\n\n### Journey 1\n\nUser does thing.\n\n## Scope Boundary\n\nIN: x.\nOUT: y.\n",
            kind, status
        )
    }

    fn prd_body(status: &str) -> String {
        format!(
            "# PRD: t\n\n## Status\n\n{}\n\n## Problem Statement\n\nP.\n\n## Goals\n\nG.\n\n## User Stories\n\nAs a user.\n\n## Requirements\n\nR1.\n\n## Acceptance Criteria\n\n- [ ] AC.\n\n## Out of Scope\n\nOOS.\n",
            status
        )
    }

    fn design_body(status: &str) -> String {
        format!(
            "# DESIGN: t\n\n## Status\n\n{}\n\n## Context and Problem Statement\n\nP.\n\n## Decision Drivers\n\nD.\n\n## Considered Options\n\nO.\n\n## Decision Outcome\n\nD.\n\n## Solution Architecture\n\nS.\n\n## Implementation Approach\n\nI.\n\n## Security Considerations\n\nS.\n\n## Consequences\n\nC.\n",
            status
        )
    }

    fn plan_body(status: &str) -> String {
        format!(
            "# PLAN: t\n\n## Status\n\n{}\n\n## Scope Summary\n\nS.\n\n## Decomposition Strategy\n\nD.\n\n## Implementation Issues\n\n| Issue | Dependencies | Complexity |\n|-------|--------------|------------|\n\n## Dependency Graph\n\n```mermaid\ngraph TD\n  a[a]\n```\n\n## Implementation Sequence\n\nS.\n",
            status
        )
    }

    fn roadmap_body(status: &str) -> String {
        format!(
            "# ROADMAP: t\n\n## Status\n\n{}\n\n## Theme\n\nT.\n\n## Scope\n\nS.\n",
            status
        )
    }

    // ---- the 11 PRD-R10 scenarios + cycle + missing + malformed ----

    #[test]
    fn multi_pr_in_flight_passes() {
        let root = build_tree(&[
            (
                "docs/briefs/BRIEF-foo.md",
                &make_brief("Accepted", ""),
                &body_for("BRIEF", "Accepted"),
            ),
            (
                "docs/prds/PRD-foo.md",
                &make_prd("Accepted", "docs/briefs/BRIEF-foo.md"),
                &prd_body("Accepted"),
            ),
            (
                "docs/designs/current/DESIGN-foo.md",
                &make_design("Current", "docs/prds/PRD-foo.md"),
                &design_body("Current"),
            ),
            (
                "docs/plans/PLAN-foo.md",
                &make_plan("Active", "multi-pr", "docs/designs/current/DESIGN-foo.md"),
                &plan_body("Active"),
            ),
        ]);
        let errors = run_lifecycle_check(&root, &Config::default(), ReviewPosture::Draft);
        assert!(errors.is_empty(), "expected pass, got {:?}", errors);
    }

    #[test]
    fn multi_pr_work_completing_present_done_fails() {
        let root = build_tree(&[
            (
                "docs/briefs/BRIEF-foo.md",
                &make_brief("Done", ""),
                &body_for("BRIEF", "Done"),
            ),
            (
                "docs/prds/PRD-foo.md",
                &make_prd("Done", "docs/briefs/BRIEF-foo.md"),
                &prd_body("Done"),
            ),
            (
                "docs/designs/current/DESIGN-foo.md",
                &make_design("Current", "docs/prds/PRD-foo.md"),
                &design_body("Current"),
            ),
            (
                "docs/plans/PLAN-foo.md",
                &make_plan("Done", "multi-pr", "docs/designs/current/DESIGN-foo.md"),
                &plan_body("Done"),
            ),
        ]);
        let errors = run_lifecycle_check(&root, &Config::default(), ReviewPosture::Draft);
        // PLAN at Done in tree should fail L01 with the deletion forcing message.
        assert!(
            errors.iter().any(|e| e.code == "L01" && e.file.contains("PLAN-foo.md") && e.message.contains("DELETED")),
            "expected L01 on PLAN deletion forcing function, got {:?}",
            errors
        );
    }

    #[test]
    fn single_pr_mid_pr_passes() {
        // Single-pr mid-PR: PLAN at Active (the auto-transition fired
        // when /shirabe:plan finished authoring).
        let root = build_tree(&[
            (
                "docs/briefs/BRIEF-foo.md",
                &make_brief("Accepted", ""),
                &body_for("BRIEF", "Accepted"),
            ),
            (
                "docs/prds/PRD-foo.md",
                &make_prd("Accepted", "docs/briefs/BRIEF-foo.md"),
                &prd_body("Accepted"),
            ),
            (
                "docs/designs/current/DESIGN-foo.md",
                &make_design("Current", "docs/prds/PRD-foo.md"),
                &design_body("Current"),
            ),
            (
                "docs/plans/PLAN-foo.md",
                &make_plan("Active", "single-pr", "docs/designs/current/DESIGN-foo.md"),
                &plan_body("Active"),
            ),
        ]);
        let errors = run_lifecycle_check(&root, &Config::default(), ReviewPosture::Draft);
        assert!(errors.is_empty(), "expected pass, got {:?}", errors);
    }

    #[test]
    fn single_pr_committed_draft_plan_fails() {
        // A committed single-pr PLAN at Draft is a violation: the
        // auto-transition from Draft to Active didn't fire when
        // /shirabe:plan finished. L01 names the (Plan, single-pr
        // mid-PR) rule's expectation of `status: Active`.
        let root = build_tree(&[
            (
                "docs/briefs/BRIEF-foo.md",
                &make_brief("Accepted", ""),
                &body_for("BRIEF", "Accepted"),
            ),
            (
                "docs/prds/PRD-foo.md",
                &make_prd("Accepted", "docs/briefs/BRIEF-foo.md"),
                &prd_body("Accepted"),
            ),
            (
                "docs/designs/current/DESIGN-foo.md",
                &make_design("Current", "docs/prds/PRD-foo.md"),
                &design_body("Current"),
            ),
            (
                "docs/plans/PLAN-foo.md",
                &make_plan("Draft", "single-pr", "docs/designs/current/DESIGN-foo.md"),
                &plan_body("Draft"),
            ),
        ]);
        let errors = run_lifecycle_check(&root, &Config::default(), ReviewPosture::Draft);
        assert!(
            errors.iter().any(|e| e.code == "L01" && e.file.contains("PLAN-foo.md")),
            "expected L01 on Draft single-pr PLAN, got {:?}",
            errors
        );
    }

    #[test]
    fn single_pr_at_merge_passes() {
        // PLAN absent; BRIEF/PRD at Done; DESIGN at Current. The
        // chain root (PLAN) is gone, so there's no chain to walk —
        // the orphan rule applies and tolerates Done BRIEF, Done PRD,
        // Current DESIGN.
        let root = build_tree(&[
            (
                "docs/briefs/BRIEF-foo.md",
                &make_brief("Done", ""),
                &body_for("BRIEF", "Done"),
            ),
            (
                "docs/prds/PRD-foo.md",
                &make_prd("Done", "docs/briefs/BRIEF-foo.md"),
                &prd_body("Done"),
            ),
            (
                "docs/designs/current/DESIGN-foo.md",
                &make_design("Current", "docs/prds/PRD-foo.md"),
                &design_body("Current"),
            ),
        ]);
        let errors = run_lifecycle_check(&root, &Config::default(), ReviewPosture::Draft);
        assert!(errors.is_empty(), "expected pass, got {:?}", errors);
    }

    #[test]
    fn present_draft_multi_pr_plan_fails() {
        let root = build_tree(&[
            (
                "docs/briefs/BRIEF-foo.md",
                &make_brief("Accepted", ""),
                &body_for("BRIEF", "Accepted"),
            ),
            (
                "docs/prds/PRD-foo.md",
                &make_prd("Accepted", "docs/briefs/BRIEF-foo.md"),
                &prd_body("Accepted"),
            ),
            (
                "docs/designs/current/DESIGN-foo.md",
                &make_design("Current", "docs/prds/PRD-foo.md"),
                &design_body("Current"),
            ),
            (
                "docs/plans/PLAN-foo.md",
                &make_plan("Draft", "multi-pr", "docs/designs/current/DESIGN-foo.md"),
                &plan_body("Draft"),
            ),
        ]);
        let errors = run_lifecycle_check(&root, &Config::default(), ReviewPosture::Draft);
        assert!(
            errors.iter().any(|e| e.code == "L01" && e.file.contains("PLAN-foo.md")),
            "expected L01 on Draft multi-pr PLAN, got {:?}",
            errors
        );
    }

    #[test]
    fn single_pr_plan_present_at_merge_done_fails_forcing_deletion() {
        // A single-pr PLAN that authors flipped to Done but didn't delete.
        let root = build_tree(&[
            (
                "docs/briefs/BRIEF-foo.md",
                &make_brief("Done", ""),
                &body_for("BRIEF", "Done"),
            ),
            (
                "docs/prds/PRD-foo.md",
                &make_prd("Done", "docs/briefs/BRIEF-foo.md"),
                &prd_body("Done"),
            ),
            (
                "docs/designs/current/DESIGN-foo.md",
                &make_design("Current", "docs/prds/PRD-foo.md"),
                &design_body("Current"),
            ),
            (
                "docs/plans/PLAN-foo.md",
                &make_plan("Done", "single-pr", "docs/designs/current/DESIGN-foo.md"),
                &plan_body("Done"),
            ),
        ]);
        let errors = run_lifecycle_check(&root, &Config::default(), ReviewPosture::Draft);
        assert!(
            errors.iter().any(|e| e.code == "L01" && e.file.contains("PLAN-foo.md")),
            "expected L01 on present-Done single-pr PLAN, got {:?}",
            errors
        );
    }

    #[test]
    fn brief_stuck_at_accepted_while_multi_pr_plan_done_fails() {
        // The author transitioned PLAN to Done but forgot to bump BRIEF.
        let root = build_tree(&[
            (
                "docs/briefs/BRIEF-foo.md",
                &make_brief("Accepted", ""),
                &body_for("BRIEF", "Accepted"),
            ),
            (
                "docs/prds/PRD-foo.md",
                &make_prd("Done", "docs/briefs/BRIEF-foo.md"),
                &prd_body("Done"),
            ),
            (
                "docs/designs/current/DESIGN-foo.md",
                &make_design("Current", "docs/prds/PRD-foo.md"),
                &design_body("Current"),
            ),
            (
                "docs/plans/PLAN-foo.md",
                &make_plan("Done", "multi-pr", "docs/designs/current/DESIGN-foo.md"),
                &plan_body("Done"),
            ),
        ]);
        let errors = run_lifecycle_check(&root, &Config::default(), ReviewPosture::Draft);
        // BRIEF at Accepted expected Done (work-completing posture).
        assert!(
            errors.iter().any(|e| e.code == "L01" && e.file.contains("BRIEF-foo.md")),
            "expected L01 on BRIEF stuck at Accepted, got {:?}",
            errors
        );
    }

    #[test]
    fn orphan_brief_at_done_passes() {
        // BRIEF Done with no downstream — post-completion healthy case.
        let root = build_tree(&[(
            "docs/briefs/BRIEF-foo.md",
            &make_brief("Done", ""),
            &body_for("BRIEF", "Done"),
        )]);
        let errors = run_lifecycle_check(&root, &Config::default(), ReviewPosture::Draft);
        assert!(errors.is_empty(), "expected pass, got {:?}", errors);
    }

    #[test]
    fn orphan_brief_at_accepted_fails() {
        // BRIEF Accepted with no downstream and no Active-ROADMAP upstream.
        let root = build_tree(&[(
            "docs/briefs/BRIEF-foo.md",
            &make_brief("Accepted", ""),
            &body_for("BRIEF", "Accepted"),
        )]);
        let errors = run_lifecycle_check(&root, &Config::default(), ReviewPosture::Draft);
        assert!(
            errors.iter().any(|e| e.code == "L02" && e.file.contains("BRIEF-foo.md")),
            "expected L02 on orphan Accepted BRIEF, got {:?}",
            errors
        );
    }

    #[test]
    fn orphan_prd_with_active_roadmap_upstream_passes() {
        let root = build_tree(&[
            (
                "docs/roadmaps/ROADMAP-foo.md",
                &make_roadmap("Active"),
                &roadmap_body("Active"),
            ),
            (
                "docs/prds/PRD-foo.md",
                &make_prd("Accepted", "docs/roadmaps/ROADMAP-foo.md"),
                &prd_body("Accepted"),
            ),
        ]);
        let errors = run_lifecycle_check(&root, &Config::default(), ReviewPosture::Draft);
        // The PRD is a chain member (chain rooted at the ROADMAP), so
        // it goes through the chain check (Accepted is the in-flight
        // passing state for a multi-pr posture).
        assert!(
            errors.is_empty(),
            "expected pass (ROADMAP-rooted PRD), got {:?}",
            errors
        );
    }

    #[test]
    fn orphan_design_at_current_passes() {
        let root = build_tree(&[(
            "docs/designs/current/DESIGN-foo.md",
            &make_design("Current", ""),
            &design_body("Current"),
        )]);
        let errors = run_lifecycle_check(&root, &Config::default(), ReviewPosture::Draft);
        assert!(errors.is_empty(), "expected pass, got {:?}", errors);
    }

    #[test]
    fn l07_current_design_outside_current_dir_fails() {
        // A DESIGN at status Current sitting in docs/designs/ (not current/).
        let root = build_tree(&[(
            "docs/designs/DESIGN-foo.md",
            &make_design("Current", ""),
            &design_body("Current"),
        )]);
        let errors = run_lifecycle_check(&root, &Config::default(), ReviewPosture::Draft);
        assert!(
            errors.iter().any(|e| e.code == "L07" && e.file.contains("DESIGN-foo.md")),
            "expected L07 on a Current design outside current/, got {:?}",
            errors
        );
    }

    #[test]
    fn l07_current_design_in_current_dir_passes() {
        let root = build_tree(&[(
            "docs/designs/current/DESIGN-foo.md",
            &make_design("Current", ""),
            &design_body("Current"),
        )]);
        let errors = run_lifecycle_check(&root, &Config::default(), ReviewPosture::Draft);
        assert!(
            !errors.iter().any(|e| e.code == "L07"),
            "expected no L07 on a Current design in current/, got {:?}",
            errors
        );
    }

    #[test]
    fn l07_non_current_design_in_current_dir_fails() {
        let root = build_tree(&[(
            "docs/designs/current/DESIGN-foo.md",
            &make_design("Accepted", ""),
            &design_body("Accepted"),
        )]);
        let errors = run_lifecycle_check(&root, &Config::default(), ReviewPosture::Draft);
        assert!(
            errors.iter().any(|e| e.code == "L07" && e.file.contains("DESIGN-foo.md")),
            "expected L07 on an Accepted design inside current/, got {:?}",
            errors
        );
    }

    #[test]
    fn in_flight_tactical_chain_without_roadmap_passes() {
        // A coherent BRIEF<-PRD<-DESIGN chain linked by `upstream:` with
        // no ROADMAP root and no PLAN yet — the exact mid-flight posture
        // /scope produces when paused after the design. Each member is a
        // non-terminal orphan (no chain is discovered without a PLAN/
        // ROADMAP root), but the chain linkage marks it as in-flight, not
        // drift. Regression for shirabe#188.
        let root = build_tree(&[
            (
                "docs/briefs/BRIEF-foo.md",
                &make_brief("Accepted", ""),
                &body_for("BRIEF", "Accepted"),
            ),
            (
                "docs/prds/PRD-foo.md",
                &make_prd("In Progress", "docs/briefs/BRIEF-foo.md"),
                &prd_body("In Progress"),
            ),
            (
                "docs/designs/DESIGN-foo.md",
                &make_design("Accepted", "docs/prds/PRD-foo.md"),
                &design_body("Accepted"),
            ),
        ]);
        let errors = run_lifecycle_check(&root, &Config::default(), ReviewPosture::Draft);
        assert!(
            !errors.iter().any(|e| e.code == "L02"),
            "expected no L02 on an in-flight roadmap-less chain, got {:?}",
            errors
        );
    }

    #[test]
    fn single_pr_chain_prd_at_in_progress_passes() {
        // A single-pr chain whose PRD is at `In Progress` (because
        // /shirabe:design bumped it) mid-PR. The PLAN roots the chain, so
        // members go through the L01 posture check; the PRD must be
        // accepted at either `Accepted` or `In Progress` mid-PR, the same
        // as the multi-pr in-flight row. Regression for the single-pr
        // /scope chain posture.
        let root = build_tree(&[
            (
                "docs/briefs/BRIEF-foo.md",
                &make_brief("Accepted", ""),
                &body_for("BRIEF", "Accepted"),
            ),
            (
                "docs/prds/PRD-foo.md",
                &make_prd("In Progress", "docs/briefs/BRIEF-foo.md"),
                &prd_body("In Progress"),
            ),
            (
                "docs/designs/DESIGN-foo.md",
                &make_design("Planned", "docs/prds/PRD-foo.md"),
                &design_body("Planned"),
            ),
            (
                "docs/plans/PLAN-foo.md",
                &make_plan("Active", "single-pr", "docs/designs/DESIGN-foo.md"),
                &plan_body("Active"),
            ),
        ]);
        let errors = run_lifecycle_check(&root, &Config::default(), ReviewPosture::Draft);
        assert!(
            !errors.iter().any(|e| e.code == "L01" && e.file.contains("PRD-foo.md")),
            "expected no L01 on a single-pr PRD at In Progress, got {:?}",
            errors
        );
    }

    #[test]
    fn two_unrelated_non_terminal_docs_both_fail() {
        // Two indexed docs where neither points at the other and neither
        // has an Active-ROADMAP upstream: both are isolated drift, not a
        // chain. The linkage pass requires a real `upstream:` edge between
        // members, so both still fail L02. Locks the drift-detection
        // boundary against the chain-linkage refinement.
        let root = build_tree(&[
            (
                "docs/briefs/BRIEF-foo.md",
                &make_brief("Accepted", ""),
                &body_for("BRIEF", "Accepted"),
            ),
            (
                "docs/designs/DESIGN-bar.md",
                &make_design("Accepted", ""),
                &design_body("Accepted"),
            ),
        ]);
        let errors = run_lifecycle_check(&root, &Config::default(), ReviewPosture::Draft);
        assert!(
            errors.iter().any(|e| e.code == "L02" && e.file.contains("BRIEF-foo.md")),
            "expected L02 on the unrelated BRIEF, got {:?}",
            errors
        );
        assert!(
            errors.iter().any(|e| e.code == "L02" && e.file.contains("DESIGN-bar.md")),
            "expected L02 on the unrelated DESIGN, got {:?}",
            errors
        );
    }

    #[test]
    fn lone_design_with_dangling_upstream_still_fails() {
        // A single non-terminal DESIGN whose `upstream:` points at a PRD
        // that does not exist in the tree, with nothing downstream. It is
        // not linked to any real tactical artifact, so it is drift — the
        // case the orphan rule must keep catching. Connectivity must
        // resolve to an indexed BRIEF/PRD/DESIGN/PLAN, not a dangling path.
        let root = build_tree(&[(
            "docs/designs/DESIGN-foo.md",
            &make_design("Accepted", "docs/prds/PRD-missing.md"),
            &design_body("Accepted"),
        )]);
        let errors = run_lifecycle_check(&root, &Config::default(), ReviewPosture::Draft);
        assert!(
            errors.iter().any(|e| e.code == "L02" && e.file.contains("DESIGN-foo.md")),
            "expected L02 on a lone DESIGN with a dangling upstream, got {:?}",
            errors
        );
    }

    // ---- the chain walk follows every upstream entry ----

    /// A block-sequence `upstream:` value, for the fan-out cases. The
    /// scalar helpers above interpolate a single path; these tests need
    /// the multi-entry shape the walk is supposed to follow whole.
    fn upstream_seq(paths: &[&str]) -> String {
        let mut out = String::from("\n");
        for p in paths {
            out.push_str(&format!("  - {}\n", p));
        }
        // The caller's own `upstream: {}\n` supplies the last newline.
        out.pop();
        out
    }

    /// Discover the chains of a built tree, for tests that assert on
    /// chain shape rather than on emitted findings.
    fn chains_of(root: &Path) -> (Vec<Chain>, Vec<ValidationError>) {
        let (idx, _) = build_doc_index(root);
        discover_chains(&idx)
    }

    fn member_names(chain: &Chain) -> Vec<String> {
        let mut names: Vec<String> = chain
            .members
            .iter()
            .map(|m| m.path.file_name().unwrap().to_string_lossy().into_owned())
            .collect();
        names.sort();
        names
    }

    #[test]
    fn every_upstream_entry_is_a_membership_edge() {
        // PLAN names two DESIGNs. Both, and everything above each of
        // them, are members. The old walk took the first entry and
        // discarded the second, so DESIGN-b and PRD-b were invisible.
        let root = build_tree(&[
            (
                "docs/briefs/BRIEF-a.md",
                &make_brief("Accepted", ""),
                &body_for("BRIEF", "Accepted"),
            ),
            (
                "docs/prds/PRD-a.md",
                &make_prd("Accepted", "docs/briefs/BRIEF-a.md"),
                &prd_body("Accepted"),
            ),
            (
                "docs/prds/PRD-b.md",
                &make_prd("Accepted", ""),
                &prd_body("Accepted"),
            ),
            (
                "docs/designs/DESIGN-a.md",
                &make_design("Planned", "docs/prds/PRD-a.md"),
                &design_body("Planned"),
            ),
            (
                "docs/designs/DESIGN-b.md",
                &make_design("Planned", "docs/prds/PRD-b.md"),
                &design_body("Planned"),
            ),
            (
                "docs/plans/PLAN-foo.md",
                &make_plan(
                    "Active",
                    "multi-pr",
                    &upstream_seq(&[
                        "docs/designs/DESIGN-a.md",
                        "docs/designs/DESIGN-b.md",
                    ]),
                ),
                &plan_body("Active"),
            ),
        ]);
        let (chains, errors) = chains_of(&root);
        assert_eq!(chains.len(), 1, "expected one chain, got {:?}", chains);
        assert!(
            errors.is_empty(),
            "a two-entry upstream is not an error, got {:?}",
            errors
        );
        // BRIEF-a is present because the walk records the node it stops
        // at; PRD-b and DESIGN-b because it followed the second entry.
        assert_eq!(
            member_names(&chains[0]),
            vec![
                "BRIEF-a.md",
                "DESIGN-a.md",
                "DESIGN-b.md",
                "PLAN-foo.md",
                "PRD-a.md",
                "PRD-b.md",
            ],
        );
        assert_eq!(chains[0].root, root.join("docs/plans/PLAN-foo.md"));
    }

    #[test]
    fn document_with_two_upstreams_is_a_member_of_both_chains() {
        // DESIGN-shared is named by two PLANs, each of which names a
        // second DESIGN too — and names it first in one case, second in
        // the other. A walk that reads only the first entry puts
        // DESIGN-shared in PLAN-1's chain and not PLAN-2's.
        let root = build_tree(&[
            (
                "docs/designs/DESIGN-shared.md",
                &make_design("Planned", ""),
                &design_body("Planned"),
            ),
            (
                "docs/designs/DESIGN-1.md",
                &make_design("Planned", ""),
                &design_body("Planned"),
            ),
            (
                "docs/designs/DESIGN-2.md",
                &make_design("Planned", ""),
                &design_body("Planned"),
            ),
            (
                "docs/plans/PLAN-1.md",
                &make_plan(
                    "Active",
                    "multi-pr",
                    &upstream_seq(&[
                        "docs/designs/DESIGN-shared.md",
                        "docs/designs/DESIGN-1.md",
                    ]),
                ),
                &plan_body("Active"),
            ),
            (
                "docs/plans/PLAN-2.md",
                &make_plan(
                    "Active",
                    "multi-pr",
                    &upstream_seq(&[
                        "docs/designs/DESIGN-2.md",
                        "docs/designs/DESIGN-shared.md",
                    ]),
                ),
                &plan_body("Active"),
            ),
        ]);
        let (chains, _) = chains_of(&root);
        let shared = root.join("docs/designs/DESIGN-shared.md");
        let holding: Vec<&PathBuf> = chains
            .iter()
            .filter(|c| c.members.iter().any(|m| m.path == shared))
            .map(|c| &c.root)
            .collect();
        assert_eq!(
            holding.len(),
            2,
            "DESIGN-shared belongs to both chains, got {:?}",
            holding
        );
    }

    #[test]
    fn diamond_is_not_a_cycle_and_does_not_drop_the_chain() {
        // Two upstream entries reconverge on PRD-shared. The node is
        // seen twice by the traversal but never twice on one branch, so
        // it is a diamond, not a cycle.
        let root = build_tree(&[
            (
                "docs/briefs/BRIEF-x.md",
                &make_brief("Accepted", ""),
                &body_for("BRIEF", "Accepted"),
            ),
            (
                "docs/prds/PRD-shared.md",
                &make_prd("Accepted", "docs/briefs/BRIEF-x.md"),
                &prd_body("Accepted"),
            ),
            (
                "docs/designs/DESIGN-a.md",
                &make_design("Planned", "docs/prds/PRD-shared.md"),
                &design_body("Planned"),
            ),
            (
                "docs/designs/DESIGN-b.md",
                &make_design("Planned", "docs/prds/PRD-shared.md"),
                &design_body("Planned"),
            ),
            (
                "docs/plans/PLAN-d.md",
                &make_plan(
                    "Active",
                    "multi-pr",
                    &upstream_seq(&[
                        "docs/designs/DESIGN-a.md",
                        "docs/designs/DESIGN-b.md",
                    ]),
                ),
                &plan_body("Active"),
            ),
        ]);
        let (chains, errors) = chains_of(&root);
        assert!(
            !errors.iter().any(|e| e.code == "L03"),
            "a diamond is not a cycle, got {:?}",
            errors
        );
        assert_eq!(
            chains.len(),
            1,
            "the chain must survive the reconvergence, got {:?}",
            chains
        );
        // The reconvergence point is recorded once, not once per branch,
        // and the walk continued past it to the BRIEF.
        assert_eq!(
            member_names(&chains[0]),
            vec![
                "BRIEF-x.md",
                "DESIGN-a.md",
                "DESIGN-b.md",
                "PLAN-d.md",
                "PRD-shared.md",
            ],
        );
    }

    #[test]
    fn cycle_below_a_fan_out_still_reports_walk_order_and_drops_the_chain() {
        // One branch of a fan-out closes a genuine cycle. Per-branch
        // tracking must still catch it: the L03 path reads in walk
        // order along the branch that closed it, and the chain goes.
        let root = build_tree(&[
            (
                "docs/prds/PRD-plain.md",
                &make_prd("Accepted", ""),
                &prd_body("Accepted"),
            ),
            (
                "docs/prds/PRD-a.md",
                &make_prd("Accepted", "docs/prds/PRD-b.md"),
                &prd_body("Accepted"),
            ),
            (
                "docs/prds/PRD-b.md",
                &make_prd("Accepted", "docs/prds/PRD-a.md"),
                &prd_body("Accepted"),
            ),
            (
                "docs/plans/PLAN-c.md",
                &make_plan(
                    "Active",
                    "multi-pr",
                    &upstream_seq(&["docs/prds/PRD-a.md", "docs/prds/PRD-plain.md"]),
                ),
                &plan_body("Active"),
            ),
        ]);
        let (chains, errors) = chains_of(&root);
        let l03: Vec<&ValidationError> = errors.iter().filter(|e| e.code == "L03").collect();
        assert_eq!(l03.len(), 1, "expected one L03, got {:?}", errors);
        assert!(
            l03[0].message.ends_with(
                "upstream cycle detected: docs/plans/PLAN-c.md -> docs/prds/PRD-a.md -> docs/prds/PRD-b.md -> docs/prds/PRD-a.md"
            ),
            "L03 must name the cycle in walk order, got {:?}",
            l03[0].message
        );
        assert!(
            chains.is_empty(),
            "a cyclic chain is dropped, got {:?}",
            chains
        );
    }

    #[test]
    fn chain_root_is_explicit_not_positional() {
        // A ROADMAP sits above a fanned-out PLAN. The walk stops at the
        // ROADMAP while recording it, so the PLAN's chain holds a node
        // that is itself a root — exactly the case member ordering can
        // no longer answer. `root` answers it.
        let root = build_tree(&[
            (
                "docs/roadmaps/ROADMAP-r.md",
                &make_roadmap("Active"),
                &roadmap_body("Active"),
            ),
            (
                "docs/prds/PRD-r.md",
                &make_prd("Accepted", "docs/roadmaps/ROADMAP-r.md"),
                &prd_body("Accepted"),
            ),
            (
                "docs/designs/DESIGN-r.md",
                &make_design("Planned", "docs/prds/PRD-r.md"),
                &design_body("Planned"),
            ),
            (
                "docs/designs/DESIGN-s.md",
                &make_design("Planned", ""),
                &design_body("Planned"),
            ),
            (
                "docs/plans/PLAN-r.md",
                &make_plan(
                    "Active",
                    "multi-pr",
                    &upstream_seq(&[
                        "docs/designs/DESIGN-r.md",
                        "docs/designs/DESIGN-s.md",
                    ]),
                ),
                &plan_body("Active"),
            ),
        ]);
        let (chains, _) = chains_of(&root);
        let plan_chain = chains
            .iter()
            .find(|c| c.root == root.join("docs/plans/PLAN-r.md"))
            .expect("the PLAN roots a chain");
        assert_eq!(plan_chain.root_kind, RootKind::Plan);
        assert!(
            plan_chain
                .members
                .iter()
                .any(|m| m.role == ChainRole::Roadmap),
            "the walk records the ROADMAP it stops at, got {:?}",
            member_names(plan_chain)
        );
    }

    // ---- the obligation map and the single emitter ----

    /// The findings naming one document, in the order the entry point
    /// returned them.
    fn findings_on<'a>(
        errors: &'a [ValidationError],
        basename: &str,
    ) -> Vec<&'a ValidationError> {
        errors.iter().filter(|e| e.file.ends_with(basename)).collect()
    }

    /// Two chains, of different postures, converging on one PRD. Both
    /// demand the PRD be Done; the PRD is at Accepted, so both are
    /// unsatisfied.
    fn two_chains_over_one_prd() -> PathBuf {
        build_tree(&[
            (
                "docs/prds/PRD-shared.md",
                &make_prd("Accepted", ""),
                &prd_body("Accepted"),
            ),
            (
                "docs/designs/DESIGN-a.md",
                &make_design("Planned", "docs/prds/PRD-shared.md"),
                &design_body("Planned"),
            ),
            (
                "docs/designs/DESIGN-b.md",
                &make_design("Planned", "docs/prds/PRD-shared.md"),
                &design_body("Planned"),
            ),
            // multi-pr at Done -> multi-pr work-completing.
            (
                "docs/plans/PLAN-a.md",
                &make_plan("Done", "multi-pr", "docs/designs/DESIGN-a.md"),
                &plan_body("Done"),
            ),
            // single-pr at Done -> single-pr at-merge.
            (
                "docs/plans/PLAN-b.md",
                &make_plan("Done", "single-pr", "docs/designs/DESIGN-b.md"),
                &plan_body("Done"),
            ),
        ])
    }

    #[test]
    fn one_requirement_from_two_chains_is_one_finding() {
        // The reproduced defect: two chains of different postures each
        // demanding the PRD be Done. Same code, same path, same
        // required set — one finding, not two that differ only in
        // which posture the message names.
        let root = two_chains_over_one_prd();
        let errors = run_lifecycle_check(&root, &Config::default(), ReviewPosture::Draft);
        let on_prd = findings_on(&errors, "PRD-shared.md");
        assert_eq!(
            on_prd.len(),
            1,
            "two chains demanding the same state is one finding, got {:?}",
            on_prd
        );
        assert_eq!(
            on_prd[0].message,
            "[L01] PRD at status 'Accepted' (expected status 'Done' for multi-pr work-completing and single-pr at-merge postures)",
            "the message names every posture behind the requirement",
        );
    }

    #[test]
    fn differing_required_sets_on_one_document_are_separate_findings() {
        // Same document, same code, two different required sets: the
        // in-flight chain accepts Planned or Current, the completing
        // chain insists on Current. Both are unsatisfied at Proposed
        // and both are said, because the requirement — not the chain —
        // is what a finding is about.
        let root = build_tree(&[
            (
                "docs/designs/DESIGN-shared.md",
                &make_design("Proposed", ""),
                &design_body("Proposed"),
            ),
            (
                "docs/plans/PLAN-inflight.md",
                &make_plan("Active", "multi-pr", "docs/designs/DESIGN-shared.md"),
                &plan_body("Active"),
            ),
            (
                "docs/plans/PLAN-completing.md",
                &make_plan("Done", "multi-pr", "docs/designs/DESIGN-shared.md"),
                &plan_body("Done"),
            ),
        ]);
        let errors = run_lifecycle_check(&root, &Config::default(), ReviewPosture::Draft);
        let on_design = findings_on(&errors, "DESIGN-shared.md");
        assert_eq!(
            on_design.len(),
            2,
            "two different required sets are two findings, got {:?}",
            on_design
        );
        assert!(
            on_design
                .iter()
                .any(|e| e.message.contains("status 'Planned' or 'Current'")),
            "the in-flight requirement is stated, got {:?}",
            on_design
        );
        assert!(
            on_design
                .iter()
                .any(|e| e.message.contains("expected status 'Current'")),
            "the completing requirement is stated, got {:?}",
            on_design
        );
    }

    #[test]
    fn both_modes_agree_on_a_shared_document() {
        // The chain-targeted run points at DESIGN-a, which sits in
        // PLAN-a's chain and not PLAN-b's. The PRD below it is in
        // both. What the targeted mode says about that PRD has to be
        // what the whole-tree mode says — including the half of the
        // requirement that arrives from the chain the target is not
        // part of. The mode picks the documents, not the verdict.
        let root = two_chains_over_one_prd();
        let whole = run_lifecycle_check(&root, &Config::default(), ReviewPosture::Draft);
        let targeted = run_lifecycle_chain_check(
            &root.join("docs/designs/DESIGN-a.md"),
            &Config::default(),
            ReviewPosture::Draft,
        );
        assert_eq!(
            findings_on(&targeted, "PRD-shared.md"),
            findings_on(&whole, "PRD-shared.md"),
            "the two modes disagree about PRD-shared.md",
        );
        assert!(
            !findings_on(&targeted, "PRD-shared.md").is_empty(),
            "the fixture is meant to produce a finding to compare",
        );
    }

    #[test]
    fn chain_targeted_scope_is_shallow_not_transitive() {
        // PLAN-1 and PLAN-2 share DESIGN-shared; DESIGN-far hangs off
        // PLAN-2 alone and is at a status its chain rejects. Targeting
        // PLAN-1 reaches DESIGN-shared, because it is a member of
        // PLAN-1's chain. It must not go on to PLAN-2's other members:
        // one more hop through a shared document and the targeted mode
        // is reporting the whole corpus.
        let root = build_tree(&[
            (
                "docs/designs/DESIGN-shared.md",
                &make_design("Planned", ""),
                &design_body("Planned"),
            ),
            (
                "docs/designs/DESIGN-far.md",
                &make_design("Proposed", ""),
                &design_body("Proposed"),
            ),
            (
                "docs/plans/PLAN-1.md",
                &make_plan("Active", "single-pr", "docs/designs/DESIGN-shared.md"),
                &plan_body("Active"),
            ),
            (
                "docs/plans/PLAN-2.md",
                &make_plan(
                    "Active",
                    "multi-pr",
                    &upstream_seq(&[
                        "docs/designs/DESIGN-shared.md",
                        "docs/designs/DESIGN-far.md",
                    ]),
                ),
                &plan_body("Active"),
            ),
        ]);
        let whole = run_lifecycle_check(&root, &Config::default(), ReviewPosture::Draft);
        assert!(
            !findings_on(&whole, "DESIGN-far.md").is_empty(),
            "the fixture needs DESIGN-far to be reportable, got {:?}",
            whole
        );

        let targeted = run_lifecycle_chain_check(
            &root.join("docs/plans/PLAN-1.md"),
            &Config::default(),
            ReviewPosture::Draft,
        );
        assert!(
            findings_on(&targeted, "DESIGN-far.md").is_empty(),
            "DESIGN-far is two hops out and must stay out of scope, got {:?}",
            targeted
        );
        assert!(
            targeted.is_empty(),
            "PLAN-1's own chain is clean, got {:?}",
            targeted
        );
    }

    #[test]
    fn renaming_an_unreferenced_document_moves_only_its_own_finding() {
        // Nothing points at the PLAN, so its name is not part of any
        // other document's lineage. Renaming it must not add, remove,
        // or reword a finding anywhere else — only the path the
        // PLAN's own finding names changes.
        let members: Vec<(&str, String, String)> = vec![
            (
                "docs/prds/PRD-foo.md",
                make_prd("Accepted", ""),
                prd_body("Accepted"),
            ),
            (
                "docs/designs/DESIGN-foo.md",
                make_design("Proposed", "docs/prds/PRD-foo.md"),
                design_body("Proposed"),
            ),
        ];
        let with_plan = |plan_rel: &str| -> Vec<ValidationError> {
            let mut docs: Vec<(&str, &str, &str)> = members
                .iter()
                .map(|(p, f, b)| (*p, f.as_str(), b.as_str()))
                .collect();
            let fm = make_plan("Done", "multi-pr", "docs/designs/DESIGN-foo.md");
            let body = plan_body("Done");
            docs.push((plan_rel, &fm, &body));
            let root = build_tree(&docs);
            run_lifecycle_check(&root, &Config::default(), ReviewPosture::Draft)
        };

        let before = with_plan("docs/plans/PLAN-original.md");
        let after = with_plan("docs/plans/PLAN-renamed.md");

        let elsewhere = |errors: &[ValidationError]| -> Vec<String> {
            errors
                .iter()
                .filter(|e| !e.file.contains("PLAN-"))
                .map(|e| format!("{} {}", e.file, e.message))
                .collect()
        };
        assert_eq!(
            elsewhere(&before),
            elsewhere(&after),
            "renaming the PLAN changed a finding on another document",
        );
        assert_eq!(
            findings_on(&before, "PLAN-original.md").len(),
            1,
            "the PLAN reports once before the rename, got {:?}",
            before
        );
        assert_eq!(
            findings_on(&after, "PLAN-renamed.md")
                .iter()
                .map(|e| e.message.clone())
                .collect::<Vec<_>>(),
            findings_on(&before, "PLAN-original.md")
                .iter()
                .map(|e| e.message.clone())
                .collect::<Vec<_>>(),
            "only the path should have moved",
        );
    }

    #[test]
    fn corpus_integrity_findings_are_whole_corpus_in_both_modes() {
        // An unrelated chain's cycle (L03) is a property of the corpus,
        // not of the document under review, so the targeted mode
        // reports it even though none of its documents are in scope.
        let root = build_tree(&[
            (
                "docs/prds/PRD-cyc-a.md",
                &make_prd("Accepted", "docs/prds/PRD-cyc-b.md"),
                &prd_body("Accepted"),
            ),
            (
                "docs/prds/PRD-cyc-b.md",
                &make_prd("Accepted", "docs/prds/PRD-cyc-a.md"),
                &prd_body("Accepted"),
            ),
            (
                "docs/plans/PLAN-cyc.md",
                &make_plan("Active", "multi-pr", "docs/prds/PRD-cyc-a.md"),
                &plan_body("Active"),
            ),
            (
                "docs/designs/DESIGN-clean.md",
                &make_design("Planned", ""),
                &design_body("Planned"),
            ),
            (
                "docs/plans/PLAN-clean.md",
                &make_plan("Active", "single-pr", "docs/designs/DESIGN-clean.md"),
                &plan_body("Active"),
            ),
        ]);
        let whole = run_lifecycle_check(&root, &Config::default(), ReviewPosture::Draft);
        let targeted = run_lifecycle_chain_check(
            &root.join("docs/plans/PLAN-clean.md"),
            &Config::default(),
            ReviewPosture::Draft,
        );
        let l03s = |errors: &[ValidationError]| -> Vec<String> {
            errors
                .iter()
                .filter(|e| e.code == "L03")
                .map(|e| e.message.clone())
                .collect()
        };
        assert!(
            !l03s(&whole).is_empty(),
            "the fixture needs a cycle to report, got {:?}",
            whole
        );
        assert_eq!(
            l03s(&targeted),
            l03s(&whole),
            "the cycle is corpus integrity and belongs in both modes",
        );
    }

    // ---- root versus member ----

    /// A ROADMAP, a chain hanging beneath it, and a PLAN at the given
    /// execution mode and status. Everything but the ROADMAP sits at
    /// the status a completing chain wants, so the ROADMAP is the only
    /// document these tests have to reason about.
    fn roadmap_over_a_chain(
        roadmap_status: &str,
        execution_mode: &str,
        plan_status: &str,
    ) -> PathBuf {
        build_tree(&[
            (
                "docs/roadmaps/ROADMAP-r.md",
                &make_roadmap(roadmap_status),
                &roadmap_body(roadmap_status),
            ),
            (
                "docs/prds/PRD-f.md",
                &make_prd("Done", "docs/roadmaps/ROADMAP-r.md"),
                &prd_body("Done"),
            ),
            (
                "docs/designs/current/DESIGN-f.md",
                &make_design("Current", "docs/prds/PRD-f.md"),
                &design_body("Current"),
            ),
            (
                "docs/plans/PLAN-f.md",
                &make_plan(
                    plan_status,
                    execution_mode,
                    "docs/designs/current/DESIGN-f.md",
                ),
                &plan_body(plan_status),
            ),
        ])
    }

    #[test]
    fn a_live_member_roadmap_under_a_completing_chain_is_not_required_absent() {
        // The false positive this repair removes. The PLAN is a
        // multi-pr PLAN at Done, so its chain is work-completing and
        // the passing-state table's ROADMAP cell for that posture is
        // Deleted. The ROADMAP is a member of that chain — the walk
        // stops at it while recording it — but the work completing is
        // one feature's, not the ROADMAP's. It is live at Active and
        // nothing is owed.
        let root = roadmap_over_a_chain("Active", "multi-pr", "Done");
        let errors = run_lifecycle_check(&root, &Config::default(), ReviewPosture::Draft);
        assert!(
            findings_on(&errors, "ROADMAP-r.md").is_empty(),
            "a live ROADMAP above a completing feature owes nothing, got {:?}",
            findings_on(&errors, "ROADMAP-r.md")
        );
    }

    #[test]
    fn a_live_member_roadmap_under_a_completing_single_pr_chain_stays_active() {
        // The same position reached the other way: a single-pr PLAN at
        // Done puts its chain at the at-merge posture. This is the one
        // cell that already read Active before the repair, which is
        // what made it look anomalous; it is now the answer for the
        // position rather than for the row, and the verdict here has to
        // be the one it always gave.
        let root = roadmap_over_a_chain("Active", "single-pr", "Done");
        let errors = run_lifecycle_check(&root, &Config::default(), ReviewPosture::Draft);
        assert!(
            findings_on(&errors, "ROADMAP-r.md").is_empty(),
            "a live ROADMAP above a completing single-pr chain owes nothing, got {:?}",
            findings_on(&errors, "ROADMAP-r.md")
        );
    }

    #[test]
    fn a_retired_member_roadmap_is_asked_for_active_not_absence() {
        // Why the requirement is Active and not the weaker "present".
        // A ROADMAP at Done sitting above a chain that is still
        // finishing is a real finding: the chain beneath it is not done
        // with it. "Present" would let it pass.
        //
        // Its own chain asks for absence at the same time, since a
        // ROADMAP at Done roots a work-completing chain of its own.
        // Those two demands are disjoint and are what the conflict
        // finding is for; until that lands they are simply both said.
        let root = roadmap_over_a_chain("Done", "multi-pr", "Done");
        let errors = run_lifecycle_check(&root, &Config::default(), ReviewPosture::Draft);
        let on_roadmap = findings_on(&errors, "ROADMAP-r.md");
        assert!(
            on_roadmap
                .iter()
                .any(|e| e.message.contains("expected status 'Active'")),
            "the chain beneath a retired ROADMAP asks for it live, got {:?}",
            on_roadmap
        );
    }

    #[test]
    fn a_roadmap_rooted_chain_still_requires_its_own_absence() {
        // The half of the table the repair does not touch. A ROADMAP at
        // Done is the root of its own chain and that chain is
        // completing, so the deletion commit is still owed. Only a
        // ROADMAP's own chain can ask this of it.
        let root = build_tree(&[(
            "docs/roadmaps/ROADMAP-r.md",
            &make_roadmap("Done"),
            &roadmap_body("Done"),
        )]);
        let errors = run_lifecycle_check(&root, &Config::default(), ReviewPosture::Draft);
        let on_roadmap = findings_on(&errors, "ROADMAP-r.md");
        assert!(
            on_roadmap
                .iter()
                .any(|e| e.code == "L01" && e.message.contains("DELETED")),
            "a completed ROADMAP-rooted chain still owes the deletion, got {:?}",
            on_roadmap
        );
    }

    // ---------- L08: conflicting chains ----------

    /// One BRIEF beneath two chains that want different things of it:
    /// a single-pr chain mid-PR, which wants it at `Accepted`, and a
    /// multi-pr chain finishing its work, which wants it at `Done`.
    /// The two sets are disjoint under the draft posture and identical
    /// under ready, which is what makes this fixture serve both the
    /// conflict case and the effective-posture case.
    fn two_disjoint_chains_over_one_brief() -> PathBuf {
        build_tree(&[
            (
                "docs/briefs/BRIEF-shared.md",
                &make_brief("Accepted", ""),
                &body_for("BRIEF", "Accepted"),
            ),
            (
                "docs/plans/PLAN-a.md",
                &make_plan("Active", "single-pr", "docs/briefs/BRIEF-shared.md"),
                &plan_body("Active"),
            ),
            (
                "docs/plans/PLAN-b.md",
                &make_plan("Done", "multi-pr", "docs/briefs/BRIEF-shared.md"),
                &plan_body("Done"),
            ),
        ])
    }

    #[test]
    fn disjoint_chains_over_one_document_are_one_conflict_finding() {
        let root = two_disjoint_chains_over_one_brief();
        let errors = run_lifecycle_check(&root, &Config::default(), ReviewPosture::Draft);
        let on_brief = findings_on(&errors, "BRIEF-shared.md");
        assert_eq!(
            on_brief.len(),
            1,
            "a conflicted document is told once, got {:?}",
            on_brief
        );
        assert_eq!(on_brief[0].code, "L08", "got {:?}", on_brief);
        // Each chain by name, each requirement in full.
        for fragment in [
            "docs/plans/PLAN-a.md",
            "docs/plans/PLAN-b.md",
            "expected status 'Accepted'",
            "expected status 'Done'",
        ] {
            assert!(
                on_brief[0].message.contains(fragment),
                "the conflict message is missing {:?}: {}",
                fragment,
                on_brief[0].message
            );
        }
    }

    #[test]
    fn the_conflict_supersedes_the_status_findings_it_replaces() {
        // The same fixture read from the other side: the multi-pr
        // chain's demand for `Done` fired an L01 before this landed,
        // and the conflict finding is what replaces it. One-for-one
        // here, one-for-N in general, never one-for-zero — a document
        // no status satisfies satisfies at most one chain.
        let root = two_disjoint_chains_over_one_brief();
        let errors = run_lifecycle_check(&root, &Config::default(), ReviewPosture::Draft);
        assert!(
            !findings_on(&errors, "BRIEF-shared.md")
                .iter()
                .any(|e| e.code == "L01"),
            "the superseded status findings are withheld, got {:?}",
            findings_on(&errors, "BRIEF-shared.md")
        );
    }

    #[test]
    fn intersecting_required_sets_pass_at_the_intersection() {
        // The case the intersection rule protects, and the reason
        // conflict is disjointness rather than inequality: the
        // in-flight chain accepts `Planned` or `Current`, the
        // completing chain insists on `Current`, and a DESIGN at
        // `Current` satisfies both. Inequality as the test would fire
        // on every shared DESIGN, this one included.
        let root = build_tree(&[
            (
                "docs/designs/current/DESIGN-shared.md",
                &make_design("Current", ""),
                &design_body("Current"),
            ),
            (
                "docs/plans/PLAN-inflight.md",
                &make_plan(
                    "Active",
                    "multi-pr",
                    "docs/designs/current/DESIGN-shared.md",
                ),
                &plan_body("Active"),
            ),
            (
                "docs/plans/PLAN-completing.md",
                &make_plan("Done", "multi-pr", "docs/designs/current/DESIGN-shared.md"),
                &plan_body("Done"),
            ),
        ]);
        let errors = run_lifecycle_check(&root, &Config::default(), ReviewPosture::Draft);
        assert!(
            findings_on(&errors, "DESIGN-shared.md").is_empty(),
            "a document at the intersection owes nothing, got {:?}",
            findings_on(&errors, "DESIGN-shared.md")
        );
    }

    #[test]
    fn two_chains_requiring_the_same_document_absent_agree() {
        // PLAN-f is the root of its own completing chain, which wants
        // it deleted, and a member of PLAN-g's completing chain, which
        // wants the same. Absence expands to the empty set and the
        // empty set is disjoint from itself, so a bare disjointness
        // test would report perfect agreement as conflict. What is
        // owed here is the deletion commit, said once.
        let root = build_tree(&[
            (
                "docs/plans/PLAN-f.md",
                &make_plan("Done", "multi-pr", ""),
                &plan_body("Done"),
            ),
            (
                "docs/plans/PLAN-g.md",
                &make_plan("Done", "multi-pr", "docs/plans/PLAN-f.md"),
                &plan_body("Done"),
            ),
        ]);
        let errors = run_lifecycle_check(&root, &Config::default(), ReviewPosture::Draft);
        let on_f = findings_on(&errors, "PLAN-f.md");
        assert!(
            !on_f.iter().any(|e| e.code == "L08"),
            "two demands for absence agree, got {:?}",
            on_f
        );
        assert!(
            on_f.iter()
                .any(|e| e.code == "L01" && e.message.contains("DELETED")),
            "the deletion is still owed, got {:?}",
            on_f
        );
    }

    #[test]
    fn the_conflict_rule_states_the_absence_case_rather_than_inferring_it() {
        use PassingState::*;
        // Absence against absence agrees; absence against a status
        // conflicts.
        assert!(!requirements_conflict(&Deleted, &Deleted));
        assert!(requirements_conflict(&Deleted, &Status("Active")));
        assert!(requirements_conflict(&Status("Active"), &Deleted));
        // Statuses: disjoint sets conflict, overlapping ones do not.
        assert!(requirements_conflict(&Status("Accepted"), &Status("Done")));
        assert!(!requirements_conflict(&Status("Done"), &Status("Done")));
        assert!(!requirements_conflict(
            &DesignPlannedOrCurrent,
            &Status("Current")
        ));
        assert!(requirements_conflict(
            &DesignPlannedOrCurrent,
            &PrdAcceptedOrInProgress
        ));
        assert!(!requirements_conflict(
            &PrdAcceptedOrInProgress,
            &Status("In Progress")
        ));
    }

    /// A PLAN wanted absent by its own completing chain and alive by
    /// an in-flight chain below it, whose `upstream:` also names a
    /// document that is not there. The conflict and the dangling
    /// upstream are different kinds of fault about the same file.
    fn conflicted_plan_with_a_dangling_upstream() -> PathBuf {
        build_tree(&[
            (
                "docs/plans/PLAN-f.md",
                &make_plan("Done", "multi-pr", "docs/designs/DESIGN-missing.md"),
                &plan_body("Done"),
            ),
            (
                "docs/plans/PLAN-g.md",
                &make_plan("Active", "multi-pr", "docs/plans/PLAN-f.md"),
                &plan_body("Active"),
            ),
        ])
    }

    #[test]
    fn other_kinds_of_finding_survive_on_a_conflicted_document() {
        let root = conflicted_plan_with_a_dangling_upstream();
        let errors = run_lifecycle_check(&root, &Config::default(), ReviewPosture::Draft);
        let on_f = findings_on(&errors, "PLAN-f.md");
        assert!(
            on_f.iter().any(|e| e.code == "L08"),
            "the conflict is reported, got {:?}",
            on_f
        );
        assert!(
            on_f.iter().any(|e| e.code == "L04"),
            "the unresolvable upstream is still reported, got {:?}",
            on_f
        );
        assert!(
            !on_f.iter().any(|e| e.code == "L01"),
            "only the status findings are withheld, got {:?}",
            on_f
        );
    }

    #[test]
    fn the_conflict_carries_the_severity_of_what_it_replaced() {
        use crate::validate::{effective_severity, posture_class, PostureClass};
        // L08 is unregistered in the draft-tolerable set, which falls
        // through to always-enforced — the same class L01 carries, so
        // the replacement is an error wherever the pair was.
        assert_eq!(posture_class("L08"), PostureClass::AlwaysEnforced);
        for posture in [ReviewPosture::Draft, ReviewPosture::Ready] {
            assert_eq!(
                effective_severity("L08", posture),
                effective_severity("L01", posture),
                "L08 and L01 must resolve alike under {:?}",
                posture
            );
        }
        // And it is reported under both modes, not only the strict one.
        let root = conflicted_plan_with_a_dangling_upstream();
        for posture in [ReviewPosture::Draft, ReviewPosture::Ready] {
            let errors = run_lifecycle_check(&root, &Config::default(), posture);
            assert!(
                findings_on(&errors, "PLAN-f.md")
                    .iter()
                    .any(|e| e.code == "L08"),
                "the conflict is reported under {:?}, got {:?}",
                posture,
                findings_on(&errors, "PLAN-f.md")
            );
        }
    }

    #[test]
    fn required_sets_are_computed_from_effective_postures() {
        // The single-pr chain is mid-PR under draft, where it wants
        // the BRIEF at `Accepted` against the other chain's `Done` —
        // a conflict. Ready re-targets it to the at-merge row, where
        // both chains want `Done` and there is nothing to conflict
        // about. Computed from the raw chain postures, the conflict
        // would be reported in a mode that does not have it.
        let root = two_disjoint_chains_over_one_brief();
        let ready = run_lifecycle_check(&root, &Config::default(), ReviewPosture::Ready);
        let on_brief = findings_on(&ready, "BRIEF-shared.md");
        assert!(
            !on_brief.iter().any(|e| e.code == "L08"),
            "ready mode has no conflict here, got {:?}",
            on_brief
        );
        assert!(
            on_brief
                .iter()
                .any(|e| e.code == "L01" && e.message.contains("expected status 'Done'")),
            "both chains want the BRIEF at Done under ready, got {:?}",
            on_brief
        );
    }

    #[test]
    fn upstream_cycle_produces_l03() {
        // a -> b -> a self-cycle at the PRD altitude.
        let root = build_tree(&[
            (
                "docs/prds/PRD-a.md",
                &make_prd("Accepted", "docs/prds/PRD-b.md"),
                &prd_body("Accepted"),
            ),
            (
                "docs/prds/PRD-b.md",
                &make_prd("Accepted", "docs/prds/PRD-a.md"),
                &prd_body("Accepted"),
            ),
            (
                "docs/plans/PLAN-a.md",
                &make_plan("Active", "multi-pr", "docs/prds/PRD-a.md"),
                &plan_body("Active"),
            ),
        ]);
        let errors = run_lifecycle_check(&root, &Config::default(), ReviewPosture::Draft);
        assert!(
            errors.iter().any(|e| e.code == "L03"),
            "expected L03 cycle, got {:?}",
            errors
        );
    }

    #[test]
    fn roadmap_upstream_strategy_does_not_produce_l04() {
        // A ROADMAP's `upstream:` names the STRATEGY it operationalizes.
        // `docs/strategies/` is outside the doc index by design, so the
        // walk must stop at the ROADMAP rather than report a present
        // STRATEGY as a missing chain member.
        let root = build_tree(&[(
            "docs/roadmaps/ROADMAP-foo.md",
            "---\nschema: roadmap/v1\nstatus: Active\nupstream: docs/strategies/STRATEGY-foo.md\n---\n",
            "\n# Roadmap: foo\n\n## Features\n\n### Feature 1: A\n\n**Status:** Not Started\n",
        )]);
        let errors = run_lifecycle_check(&root, &Config::default(), ReviewPosture::Draft);
        assert!(
            !errors.iter().any(|e| e.code == "L04"),
            "STRATEGY upstream must not read as a missing chain member, got {:?}",
            errors
        );
    }

    #[test]
    fn missing_chain_member_produces_l04() {
        let root = build_tree(&[(
            "docs/plans/PLAN-foo.md",
            &make_plan("Active", "multi-pr", "docs/designs/DESIGN-missing.md"),
            &plan_body("Active"),
        )]);
        let errors = run_lifecycle_check(&root, &Config::default(), ReviewPosture::Draft);
        assert!(
            errors.iter().any(|e| e.code == "L04"),
            "expected L04 missing member, got {:?}",
            errors
        );
    }

    #[test]
    fn malformed_frontmatter_produces_l05_no_panic() {
        // A file with broken YAML in the frontmatter.
        let root = build_tree(&[]);
        let path = root.join("docs/briefs/BRIEF-bad.md");
        std::fs::write(
            &path,
            "---\nschema: brief/v1\nstatus: Draft\nproblem: |\n  unclosed\noutcome: |\n  outcome\nupstream: [unclosed list\n---\n\n# BRIEF: bad\n\n## Status\n\nDraft\n",
        )
        .unwrap();
        let errors = run_lifecycle_check(&root, &Config::default(), ReviewPosture::Draft);
        // The parse failure should be reported as L05, not a panic.
        assert!(
            errors.iter().any(|e| e.code == "L05"),
            "expected L05 on malformed frontmatter, got {:?}",
            errors
        );
    }

    #[test]
    fn target_state_lookup() {
        assert_eq!(target_state_for("Brief"), TargetState::Status("Done"));
        assert_eq!(target_state_for("PRD"), TargetState::Status("Done"));
        assert_eq!(target_state_for("Design"), TargetState::Status("Current"));
        assert_eq!(target_state_for("Plan"), TargetState::Deleted);
        assert_eq!(target_state_for("Roadmap"), TargetState::Deleted);
        assert_eq!(target_state_for("Unknown"), TargetState::Unknown);
    }

    #[test]
    fn design_at_planned_during_multi_pr_in_flight_passes() {
        // DESIGN at `Planned` in docs/designs/ during multi-pr in-flight.
        // This is the canonical mid-iteration shape — the DESIGN has
        // not yet been promoted to current/.
        let root = build_tree(&[
            (
                "docs/briefs/BRIEF-foo.md",
                &make_brief("Accepted", ""),
                &body_for("BRIEF", "Accepted"),
            ),
            (
                "docs/prds/PRD-foo.md",
                &make_prd("Accepted", "docs/briefs/BRIEF-foo.md"),
                &prd_body("Accepted"),
            ),
            (
                "docs/designs/DESIGN-foo.md",
                &make_design("Planned", "docs/prds/PRD-foo.md"),
                &design_body("Planned"),
            ),
            (
                "docs/plans/PLAN-foo.md",
                &make_plan("Active", "multi-pr", "docs/designs/DESIGN-foo.md"),
                &plan_body("Active"),
            ),
        ]);
        let errors = run_lifecycle_check(&root, &Config::default(), ReviewPosture::Draft);
        assert!(errors.is_empty(), "expected pass (DESIGN at Planned during in-flight), got {:?}", errors);
    }

    #[test]
    fn design_at_planned_during_multi_pr_work_completing_fails() {
        // DESIGN must be Current at multi-pr work-completing (promoted
        // before the chain's final commit set).
        let root = build_tree(&[
            (
                "docs/briefs/BRIEF-foo.md",
                &make_brief("Done", ""),
                &body_for("BRIEF", "Done"),
            ),
            (
                "docs/prds/PRD-foo.md",
                &make_prd("Done", "docs/briefs/BRIEF-foo.md"),
                &prd_body("Done"),
            ),
            (
                "docs/designs/DESIGN-foo.md",
                &make_design("Planned", "docs/prds/PRD-foo.md"),
                &design_body("Planned"),
            ),
            (
                "docs/plans/PLAN-foo.md",
                &make_plan("Done", "multi-pr", "docs/designs/DESIGN-foo.md"),
                &plan_body("Done"),
            ),
        ]);
        let errors = run_lifecycle_check(&root, &Config::default(), ReviewPosture::Draft);
        // DESIGN at Planned during work-completing should fail
        // (expected Current).
        assert!(
            errors.iter().any(|e| e.code == "L01" && e.file.contains("DESIGN-foo.md")),
            "expected L01 on DESIGN at Planned during work-completing, got {:?}",
            errors
        );
    }

    #[test]
    fn prd_at_in_progress_during_multi_pr_in_flight_passes() {
        // PRD lifecycle includes Draft -> Accepted -> In Progress ->
        // Done. During multi-pr in-flight the PRD can legitimately
        // be at Accepted (work not yet started) OR In Progress (work
        // in flight). Both should pass.
        let root = build_tree(&[
            (
                "docs/briefs/BRIEF-foo.md",
                &make_brief("Accepted", ""),
                &body_for("BRIEF", "Accepted"),
            ),
            (
                "docs/prds/PRD-foo.md",
                &format!(
                    "schema: prd/v1\nstatus: In Progress\nproblem: |\n  problem.\ngoals: |\n  goals.\nupstream: {}\n",
                    "docs/briefs/BRIEF-foo.md"
                ),
                &prd_body("In Progress"),
            ),
            (
                "docs/designs/DESIGN-foo.md",
                &make_design("Planned", "docs/prds/PRD-foo.md"),
                &design_body("Planned"),
            ),
            (
                "docs/plans/PLAN-foo.md",
                &make_plan("Active", "multi-pr", "docs/designs/DESIGN-foo.md"),
                &plan_body("Active"),
            ),
        ]);
        let errors = run_lifecycle_check(&root, &Config::default(), ReviewPosture::Draft);
        assert!(errors.is_empty(), "expected pass (PRD at In Progress in-flight), got {:?}", errors);
    }

    #[test]
    fn empty_tree_passes() {
        let root = build_tree(&[]);
        let errors = run_lifecycle_check(&root, &Config::default(), ReviewPosture::Draft);
        assert!(errors.is_empty(), "expected pass on empty tree, got {:?}", errors);
    }

    // ---- strict-mode tests for the DRAFT-vs-READY discipline ----
    //
    // These tests cover the six shapes named in
    // docs/prds/PRD-lifecycle-draft-ready-discipline.md (R12) plus the
    // strict-flag-threading verification. The shape parity with the
    // non-strict counterparts above is intentional — each strict test
    // reuses the same fixture as a sibling non-strict test and the
    // assertion is the toggled-by-flag bit.

    #[test]
    fn single_pr_mid_pr_passes_in_non_strict_mode() {
        // Same fixture as single_pr_mid_pr_passes; explicit
        // non-strict assertion documents that DRAFT-mode equivalent
        // CI runs preserve the upstream non-strict behavior.
        // single-pr-mid-PR uses Active (not Draft) under the unified
        // PLAN lifecycle.
        let root = build_tree(&[
            (
                "docs/briefs/BRIEF-foo.md",
                &make_brief("Accepted", ""),
                &body_for("BRIEF", "Accepted"),
            ),
            (
                "docs/prds/PRD-foo.md",
                &make_prd("Accepted", "docs/briefs/BRIEF-foo.md"),
                &prd_body("Accepted"),
            ),
            (
                "docs/designs/current/DESIGN-foo.md",
                &make_design("Current", "docs/prds/PRD-foo.md"),
                &design_body("Current"),
            ),
            (
                "docs/plans/PLAN-foo.md",
                &make_plan("Active", "single-pr", "docs/designs/current/DESIGN-foo.md"),
                &plan_body("Active"),
            ),
        ]);
        let errors = run_lifecycle_check(&root, &Config::default(), ReviewPosture::Draft);
        assert!(
            errors.is_empty(),
            "expected single-pr mid-PR pass in non-strict mode, got {:?}",
            errors
        );
    }

    #[test]
    fn single_pr_mid_pr_fails_in_strict_mode_on_present_plan() {
        // READY-mode equivalent: the same single-pr-mid-PR fixture
        // (PLAN at Active per the unified lifecycle) fails strict
        // mode because the PLAN is present in the tree.
        let root = build_tree(&[
            (
                "docs/briefs/BRIEF-foo.md",
                &make_brief("Accepted", ""),
                &body_for("BRIEF", "Accepted"),
            ),
            (
                "docs/prds/PRD-foo.md",
                &make_prd("Accepted", "docs/briefs/BRIEF-foo.md"),
                &prd_body("Accepted"),
            ),
            (
                "docs/designs/current/DESIGN-foo.md",
                &make_design("Current", "docs/prds/PRD-foo.md"),
                &design_body("Current"),
            ),
            (
                "docs/plans/PLAN-foo.md",
                &make_plan("Active", "single-pr", "docs/designs/current/DESIGN-foo.md"),
                &plan_body("Active"),
            ),
        ]);
        let errors = run_lifecycle_check(&root, &Config::default(), ReviewPosture::Ready);
        // Three L01 errors expected: PLAN must be DELETED, BRIEF must
        // be Done, PRD must be Done. The posture name in the message
        // is the re-targeted "single-pr at-merge" not "single-pr mid-PR".
        assert!(
            errors.iter().any(|e| e.code == "L01" && e.file.contains("PLAN-foo.md")),
            "expected L01 on present PLAN in strict mode, got {:?}",
            errors
        );
        assert!(
            errors
                .iter()
                .any(|e| e.code == "L01" && e.file.contains("BRIEF-foo.md")),
            "expected L01 on BRIEF Accepted in strict mode, got {:?}",
            errors
        );
        assert!(
            errors
                .iter()
                .any(|e| e.code == "L01" && e.file.contains("PRD-foo.md")),
            "expected L01 on PRD Accepted in strict mode, got {:?}",
            errors
        );
        // All L01 messages name the re-targeted at-merge posture, not
        // the chain's literal SinglePrMidPR posture.
        for err in errors.iter().filter(|e| e.code == "L01") {
            assert!(
                err.message.contains("single-pr at-merge"),
                "expected re-targeted posture name in error message, got {:?}",
                err
            );
        }
    }

    #[test]
    fn single_pr_at_merge_passes_in_strict_mode() {
        // The chain is at single-pr at-merge: PLAN absent, BRIEF/PRD
        // at Done, DESIGN at Current. Strict and non-strict both pass.
        let root = build_tree(&[
            (
                "docs/briefs/BRIEF-foo.md",
                &make_brief("Done", ""),
                &body_for("BRIEF", "Done"),
            ),
            (
                "docs/prds/PRD-foo.md",
                &make_prd("Done", "docs/briefs/BRIEF-foo.md"),
                &prd_body("Done"),
            ),
            (
                "docs/designs/current/DESIGN-foo.md",
                &make_design("Current", "docs/prds/PRD-foo.md"),
                &design_body("Current"),
            ),
        ]);
        let errors = run_lifecycle_check(&root, &Config::default(), ReviewPosture::Ready);
        assert!(
            errors.is_empty(),
            "expected single-pr at-merge pass in strict mode, got {:?}",
            errors
        );
    }

    #[test]
    fn multi_pr_in_flight_passes_in_strict_mode() {
        // Multi-pr in-flight is a legitimate passing state on a READY
        // PR (intermediate multi-pr PR shape). Strict and non-strict
        // both pass.
        let root = build_tree(&[
            (
                "docs/briefs/BRIEF-foo.md",
                &make_brief("Accepted", ""),
                &body_for("BRIEF", "Accepted"),
            ),
            (
                "docs/prds/PRD-foo.md",
                &make_prd("Accepted", "docs/briefs/BRIEF-foo.md"),
                &prd_body("Accepted"),
            ),
            (
                "docs/designs/current/DESIGN-foo.md",
                &make_design("Current", "docs/prds/PRD-foo.md"),
                &design_body("Current"),
            ),
            (
                "docs/plans/PLAN-foo.md",
                &make_plan("Active", "multi-pr", "docs/designs/current/DESIGN-foo.md"),
                &plan_body("Active"),
            ),
        ]);
        let errors = run_lifecycle_check(&root, &Config::default(), ReviewPosture::Ready);
        assert!(
            errors.is_empty(),
            "expected multi-pr in-flight pass in strict mode, got {:?}",
            errors
        );
    }

    #[test]
    fn multi_pr_work_completing_fails_in_both_modes() {
        // Multi-pr work-completing (PLAN at Done in the tree) is the
        // forcing-function failure that exists independent of strict
        // mode. Both modes fail.
        let root_nonstrict = build_tree(&[
            (
                "docs/briefs/BRIEF-foo.md",
                &make_brief("Done", ""),
                &body_for("BRIEF", "Done"),
            ),
            (
                "docs/prds/PRD-foo.md",
                &make_prd("Done", "docs/briefs/BRIEF-foo.md"),
                &prd_body("Done"),
            ),
            (
                "docs/designs/current/DESIGN-foo.md",
                &make_design("Current", "docs/prds/PRD-foo.md"),
                &design_body("Current"),
            ),
            (
                "docs/plans/PLAN-foo.md",
                &make_plan("Done", "multi-pr", "docs/designs/current/DESIGN-foo.md"),
                &plan_body("Done"),
            ),
        ]);
        let errors_nonstrict =
            run_lifecycle_check(&root_nonstrict, &Config::default(), ReviewPosture::Draft);
        assert!(
            errors_nonstrict
                .iter()
                .any(|e| e.code == "L01" && e.file.contains("PLAN-foo.md")),
            "expected L01 on multi-pr work-completing PLAN in non-strict mode, got {:?}",
            errors_nonstrict
        );
        let root_strict = build_tree(&[
            (
                "docs/briefs/BRIEF-foo.md",
                &make_brief("Done", ""),
                &body_for("BRIEF", "Done"),
            ),
            (
                "docs/prds/PRD-foo.md",
                &make_prd("Done", "docs/briefs/BRIEF-foo.md"),
                &prd_body("Done"),
            ),
            (
                "docs/designs/current/DESIGN-foo.md",
                &make_design("Current", "docs/prds/PRD-foo.md"),
                &design_body("Current"),
            ),
            (
                "docs/plans/PLAN-foo.md",
                &make_plan("Done", "multi-pr", "docs/designs/current/DESIGN-foo.md"),
                &plan_body("Done"),
            ),
        ]);
        let errors_strict =
            run_lifecycle_check(&root_strict, &Config::default(), ReviewPosture::Ready);
        assert!(
            errors_strict
                .iter()
                .any(|e| e.code == "L01" && e.file.contains("PLAN-foo.md")),
            "expected L01 on multi-pr work-completing PLAN in strict mode, got {:?}",
            errors_strict
        );
    }

    #[test]
    fn multi_pr_mid_transition_fails_in_strict_mode() {
        // Multi-pr mid-transition: PLAN at Done (work-completing) but
        // BRIEF/PRD still at Accepted. Both modes fail — the
        // work-completing forcing function fires on the PLAN, the
        // BRIEF/PRD-Done passing state fires on the framing docs.
        let root = build_tree(&[
            (
                "docs/briefs/BRIEF-foo.md",
                &make_brief("Accepted", ""),
                &body_for("BRIEF", "Accepted"),
            ),
            (
                "docs/prds/PRD-foo.md",
                &make_prd("Accepted", "docs/briefs/BRIEF-foo.md"),
                &prd_body("Accepted"),
            ),
            (
                "docs/designs/current/DESIGN-foo.md",
                &make_design("Current", "docs/prds/PRD-foo.md"),
                &design_body("Current"),
            ),
            (
                "docs/plans/PLAN-foo.md",
                &make_plan("Done", "multi-pr", "docs/designs/current/DESIGN-foo.md"),
                &plan_body("Done"),
            ),
        ]);
        let errors = run_lifecycle_check(&root, &Config::default(), ReviewPosture::Ready);
        assert!(
            errors
                .iter()
                .any(|e| e.code == "L01" && e.file.contains("BRIEF-foo.md")),
            "expected L01 on BRIEF stuck at Accepted in strict mode, got {:?}",
            errors
        );
        assert!(
            errors
                .iter()
                .any(|e| e.code == "L01" && e.file.contains("PRD-foo.md")),
            "expected L01 on PRD stuck at Accepted in strict mode, got {:?}",
            errors
        );
        assert!(
            errors
                .iter()
                .any(|e| e.code == "L01" && e.file.contains("PLAN-foo.md")),
            "expected L01 on PLAN Done in strict mode, got {:?}",
            errors
        );
    }

    #[test]
    fn strict_flag_threads_through_call_chain() {
        // Threading verification: two identical fixtures (PLAN at
        // Active per the unified lifecycle), one called with
        // strict=true, the other with strict=false. The result must
        // differ — confirming the flag actually reaches the posture
        // re-target inside the chain-iteration loop rather than being
        // silently dropped.
        let root_a = build_tree(&[
            (
                "docs/briefs/BRIEF-foo.md",
                &make_brief("Accepted", ""),
                &body_for("BRIEF", "Accepted"),
            ),
            (
                "docs/prds/PRD-foo.md",
                &make_prd("Accepted", "docs/briefs/BRIEF-foo.md"),
                &prd_body("Accepted"),
            ),
            (
                "docs/designs/current/DESIGN-foo.md",
                &make_design("Current", "docs/prds/PRD-foo.md"),
                &design_body("Current"),
            ),
            (
                "docs/plans/PLAN-foo.md",
                &make_plan("Active", "single-pr", "docs/designs/current/DESIGN-foo.md"),
                &plan_body("Active"),
            ),
        ]);
        let errors_nonstrict = run_lifecycle_check(&root_a, &Config::default(), ReviewPosture::Draft);
        let root_b = build_tree(&[
            (
                "docs/briefs/BRIEF-foo.md",
                &make_brief("Accepted", ""),
                &body_for("BRIEF", "Accepted"),
            ),
            (
                "docs/prds/PRD-foo.md",
                &make_prd("Accepted", "docs/briefs/BRIEF-foo.md"),
                &prd_body("Accepted"),
            ),
            (
                "docs/designs/current/DESIGN-foo.md",
                &make_design("Current", "docs/prds/PRD-foo.md"),
                &design_body("Current"),
            ),
            (
                "docs/plans/PLAN-foo.md",
                &make_plan("Active", "single-pr", "docs/designs/current/DESIGN-foo.md"),
                &plan_body("Active"),
            ),
        ]);
        let errors_strict = run_lifecycle_check(&root_b, &Config::default(), ReviewPosture::Ready);
        assert!(
            errors_nonstrict.is_empty(),
            "non-strict expected to pass, got {:?}",
            errors_nonstrict
        );
        assert!(
            !errors_strict.is_empty(),
            "strict expected to fail on present PLAN, got empty errors"
        );
    }

    // ---- chain-targeted mode (run_lifecycle_chain_check) ----

    #[test]
    fn chain_targeted_single_pr_mid_pr_strict_fails() {
        let root = build_tree(&[
            (
                "docs/briefs/BRIEF-foo.md",
                &make_brief("Accepted", ""),
                &body_for("BRIEF", "Accepted"),
            ),
            (
                "docs/prds/PRD-foo.md",
                &make_prd("Accepted", "docs/briefs/BRIEF-foo.md"),
                &prd_body("Accepted"),
            ),
            (
                "docs/designs/DESIGN-foo.md",
                &make_design("Planned", "docs/prds/PRD-foo.md"),
                &design_body("Planned"),
            ),
            (
                "docs/plans/PLAN-foo.md",
                &make_plan("Active", "single-pr", "docs/designs/DESIGN-foo.md"),
                &plan_body("Active"),
            ),
        ]);
        let plan_path = root.join("docs/plans/PLAN-foo.md");
        let errors = run_lifecycle_chain_check(&plan_path, &Config::default(), ReviewPosture::Ready);
        assert!(
            !errors.is_empty(),
            "strict mode expected to fail on present single-pr PLAN, got empty"
        );
        // The failures should name PLAN, BRIEF, or PRD members. No
        // L02 orphan errors should fire — every doc is a chain
        // member.
        let codes: Vec<&str> = errors.iter().map(|e| e.code.as_str()).collect();
        assert!(
            codes.iter().all(|c| *c == "L01"),
            "expected only L01 errors, got: {:?}",
            errors
        );
    }

    #[test]
    fn chain_targeted_single_pr_at_terminal_strict_passes() {
        // The PLAN is absent; the chain root is the DESIGN at
        // Current. The chain-walker discovers chains rooted at PLAN
        // or ROADMAP; without one, no chain exists and the docs are
        // orphans. The orphan rule passes for terminal-state orphans
        // (DESIGN at Current's target is Current; BRIEF at Done is
        // terminal; PRD at Done is terminal).
        let root = build_tree(&[
            (
                "docs/briefs/BRIEF-foo.md",
                &make_brief("Done", ""),
                &body_for("BRIEF", "Done"),
            ),
            (
                "docs/prds/PRD-foo.md",
                &make_prd("Done", "docs/briefs/BRIEF-foo.md"),
                &prd_body("Done"),
            ),
            (
                "docs/designs/current/DESIGN-foo.md",
                &make_design("Current", "docs/prds/PRD-foo.md"),
                &design_body("Current"),
            ),
        ]);
        let brief_path = root.join("docs/briefs/BRIEF-foo.md");
        let errors = run_lifecycle_chain_check(&brief_path, &Config::default(), ReviewPosture::Ready);
        assert!(
            errors.is_empty(),
            "single-pr at-terminal chain expected to pass; got: {:?}",
            errors
        );
    }

    #[test]
    fn chain_targeted_single_pr_mid_pr_nonstrict_passes() {
        let root = build_tree(&[
            (
                "docs/briefs/BRIEF-foo.md",
                &make_brief("Accepted", ""),
                &body_for("BRIEF", "Accepted"),
            ),
            (
                "docs/prds/PRD-foo.md",
                &make_prd("Accepted", "docs/briefs/BRIEF-foo.md"),
                &prd_body("Accepted"),
            ),
            (
                "docs/designs/DESIGN-foo.md",
                &make_design("Planned", "docs/prds/PRD-foo.md"),
                &design_body("Planned"),
            ),
            (
                "docs/plans/PLAN-foo.md",
                &make_plan("Active", "single-pr", "docs/designs/DESIGN-foo.md"),
                &plan_body("Active"),
            ),
        ]);
        let plan_path = root.join("docs/plans/PLAN-foo.md");
        let errors = run_lifecycle_chain_check(&plan_path, &Config::default(), ReviewPosture::Draft);
        assert!(
            errors.is_empty(),
            "single-pr mid-PR with strict=false should pass; got: {:?}",
            errors
        );
    }

    #[test]
    fn chain_targeted_multi_pr_in_flight_strict_passes() {
        let root = build_tree(&[
            (
                "docs/briefs/BRIEF-foo.md",
                &make_brief("Accepted", ""),
                &body_for("BRIEF", "Accepted"),
            ),
            (
                "docs/prds/PRD-foo.md",
                &make_prd("Accepted", "docs/briefs/BRIEF-foo.md"),
                &prd_body("Accepted"),
            ),
            (
                "docs/designs/current/DESIGN-foo.md",
                &make_design("Current", "docs/prds/PRD-foo.md"),
                &design_body("Current"),
            ),
            (
                "docs/plans/PLAN-foo.md",
                &make_plan("Active", "multi-pr", "docs/designs/current/DESIGN-foo.md"),
                &plan_body("Active"),
            ),
        ]);
        let plan_path = root.join("docs/plans/PLAN-foo.md");
        let errors = run_lifecycle_chain_check(&plan_path, &Config::default(), ReviewPosture::Ready);
        assert!(
            errors.is_empty(),
            "multi-pr in-flight with strict=true should pass; got: {:?}",
            errors
        );
    }

    #[test]
    fn chain_targeted_non_existent_path_rejects() {
        let path = std::path::Path::new("/tmp/does-not-exist-shirabe-test.md");
        let errors = run_lifecycle_chain_check(path, &Config::default(), ReviewPosture::Draft);
        assert_eq!(errors.len(), 1, "expected one error; got: {:?}", errors);
        assert_eq!(errors[0].code, "L05");
        assert!(
            errors[0].message.contains("not found"),
            "error should name missing path; got: {}",
            errors[0].message
        );
    }

    #[test]
    fn chain_targeted_unrecognized_prefix_rejects() {
        // A file inside docs/briefs but with a non-artifact name
        // (e.g. README.md). The file must exist for the
        // canonicalize step to succeed.
        let root = build_tree(&[(
            "docs/briefs/README.md",
            "schema: brief/v1\nstatus: Draft\n",
            "# README",
        )]);
        let readme_path = root.join("docs/briefs/README.md");
        let errors = run_lifecycle_chain_check(&readme_path, &Config::default(), ReviewPosture::Draft);
        assert_eq!(errors.len(), 1, "expected one error; got: {:?}", errors);
        assert_eq!(errors[0].code, "L05");
        assert!(
            errors[0].message.contains("unrecognized artifact prefix"),
            "error should name the prefix mismatch; got: {}",
            errors[0].message
        );
    }

    #[test]
    fn chain_targeted_path_outside_docs_rejects() {
        // The file must exist for canonicalize to succeed, but it
        // must live outside docs/. Use a temp directory with a
        // BRIEF-prefix name but no docs/ ancestor.
        let n = COUNTER.fetch_add(1, Ordering::SeqCst);
        let outside = std::env::temp_dir().join(format!(
            "shirabe-lifecycle-outside-{}-{}",
            std::process::id(),
            n
        ));
        let _ = fs::remove_dir_all(&outside);
        fs::create_dir_all(&outside).unwrap();
        let path = outside.join("BRIEF-foo.md");
        fs::write(&path, "---\nschema: brief/v1\nstatus: Accepted\n---\n\n# BRIEF\n").unwrap();
        let errors = run_lifecycle_chain_check(&path, &Config::default(), ReviewPosture::Draft);
        assert_eq!(errors.len(), 1, "expected one error; got: {:?}", errors);
        assert_eq!(errors[0].code, "L05");
        assert!(
            errors[0].message.contains("is not inside"),
            "error should name the docs/ requirement; got: {}",
            errors[0].message
        );
    }

    #[test]
    fn chain_targeted_orphan_at_terminal_passes() {
        // A BRIEF at Done with no downstream references and no
        // upstream is an orphan; the orphan rule passes because the
        // BRIEF is at its terminal state.
        let root = build_tree(&[(
            "docs/briefs/BRIEF-orphan.md",
            &make_brief("Done", ""),
            &body_for("BRIEF", "Done"),
        )]);
        let path = root.join("docs/briefs/BRIEF-orphan.md");
        let errors = run_lifecycle_chain_check(&path, &Config::default(), ReviewPosture::Draft);
        assert!(
            errors.is_empty(),
            "orphan at terminal should pass via orphan rule; got: {:?}",
            errors
        );
    }

    #[test]
    fn chain_targeted_orphan_at_non_terminal_fails() {
        // A BRIEF at Accepted (not terminal) with no chain
        // participation is an orphan; the orphan rule fails with
        // L02.
        let root = build_tree(&[(
            "docs/briefs/BRIEF-orphan.md",
            &make_brief("Accepted", ""),
            &body_for("BRIEF", "Accepted"),
        )]);
        let path = root.join("docs/briefs/BRIEF-orphan.md");
        let errors = run_lifecycle_chain_check(&path, &Config::default(), ReviewPosture::Draft);
        assert!(
            !errors.is_empty(),
            "orphan at non-terminal should fail; got empty errors"
        );
        assert!(
            errors.iter().any(|e| e.code == "L02"),
            "expected L02 error; got: {:?}",
            errors
        );
    }

    #[test]
    fn chain_targeted_from_design_node_walks_full_chain() {
        // Verify the chain-targeted mode can start from any node in
        // the chain, not just the PLAN. Pointing at the DESIGN
        // should walk the same chain as pointing at the PLAN.
        let root = build_tree(&[
            (
                "docs/briefs/BRIEF-foo.md",
                &make_brief("Accepted", ""),
                &body_for("BRIEF", "Accepted"),
            ),
            (
                "docs/prds/PRD-foo.md",
                &make_prd("Accepted", "docs/briefs/BRIEF-foo.md"),
                &prd_body("Accepted"),
            ),
            (
                "docs/designs/DESIGN-foo.md",
                &make_design("Planned", "docs/prds/PRD-foo.md"),
                &design_body("Planned"),
            ),
            (
                "docs/plans/PLAN-foo.md",
                &make_plan("Active", "single-pr", "docs/designs/DESIGN-foo.md"),
                &plan_body("Active"),
            ),
        ]);
        let design_path = root.join("docs/designs/DESIGN-foo.md");
        let errors = run_lifecycle_chain_check(&design_path, &Config::default(), ReviewPosture::Ready);
        assert!(
            !errors.is_empty(),
            "strict mode from DESIGN should still surface the chain's failure"
        );
        // The errors should reference chain members by their
        // relative paths; specifically, the PLAN must surface.
        let has_plan_error = errors.iter().any(|e| e.file.contains("PLAN-foo.md"));
        assert!(
            has_plan_error,
            "expected at least one error to reference PLAN-foo.md; got: {:?}",
            errors
        );
    }

    // ---- L06 outline-AC completeness ----

    fn single_pr_plan_body(acs: &str) -> String {
        format!(
            "# PLAN: t\n\n## Status\n\nDraft\n\n## Scope Summary\n\nS.\n\n## Decomposition Strategy\n\nD.\n\n## Issue Outlines\n\n### Issue 1: first\n\n**Goal**: do it.\n\n**Acceptance Criteria**:\n{}\n**Dependencies**: None\n\n## Implementation Sequence\n\nSeq.\n",
            acs,
        )
    }

    fn build_single_pr_chain(acs: &str) -> PathBuf {
        build_tree(&[
            ("docs/briefs/BRIEF-foo.md", &make_brief("Accepted", ""), &body_for("BRIEF", "Accepted")),
            ("docs/prds/PRD-foo.md", &make_prd("Accepted", "docs/briefs/BRIEF-foo.md"), &prd_body("Accepted")),
            ("docs/designs/DESIGN-foo.md", &make_design("Planned", "docs/prds/PRD-foo.md"), &design_body("Planned")),
            ("docs/plans/PLAN-foo.md", &make_plan("Draft", "single-pr", "docs/designs/DESIGN-foo.md"), &single_pr_plan_body(acs)),
        ])
    }

    #[test]
    fn l06_passes_when_all_acs_ticked() {
        let root = build_single_pr_chain("- [x] one\n- [X] two\n");
        let plan_path = root.join("docs/plans/PLAN-foo.md");
        let errors = run_lifecycle_chain_check(&plan_path, &Config::default(), ReviewPosture::Draft);
        let l06s: Vec<_> = errors.iter().filter(|e| e.code == "L06").collect();
        assert!(
            l06s.is_empty(),
            "expected no L06 errors when all AC boxes are ticked; got {:?}",
            l06s
        );
    }

    #[test]
    fn l06_fires_per_unticked_ac_with_message_naming_outline_and_text() {
        let root = build_single_pr_chain("- [ ] alpha\n- [x] beta\n- [ ] gamma\n");
        let plan_path = root.join("docs/plans/PLAN-foo.md");
        let errors = run_lifecycle_chain_check(&plan_path, &Config::default(), ReviewPosture::Draft);
        let l06s: Vec<_> = errors.iter().filter(|e| e.code == "L06").collect();
        assert_eq!(l06s.len(), 2, "expected 2 L06 errors; got {:?}", l06s);
        let combined: String = l06s.iter().map(|e| e.message.as_str()).collect::<Vec<_>>().join(" | ");
        assert!(combined.contains("Issue 1: first"), "message should name the outline: {}", combined);
        assert!(combined.contains("'alpha'"), "message should quote AC text alpha: {}", combined);
        assert!(combined.contains("'gamma'"), "message should quote AC text gamma: {}", combined);
        assert!(!combined.contains("'beta'"), "ticked AC should not appear: {}", combined);
    }

    #[test]
    fn l06_suppressed_when_allow_untracked_acs_set() {
        let root = build_single_pr_chain("- [ ] alpha\n- [ ] beta\n");
        let plan_path = root.join("docs/plans/PLAN-foo.md");
        let mut cfg = Config::default();
        cfg.allow_untracked_acs = true;
        let errors = run_lifecycle_chain_check(&plan_path, &cfg, ReviewPosture::Draft);
        let l06s: Vec<_> = errors.iter().filter(|e| e.code == "L06").collect();
        assert!(
            l06s.is_empty(),
            "expected no L06 errors when allow_untracked_acs is set; got {:?}",
            l06s
        );
        // L01-L05 must still be active under the flag; the single-pr-mid-PR
        // posture should still pass the chain shape since PLAN is at Draft.
        // We do not assert specific L01 outcomes; we only assert that the
        // suppression is L06-only and not a global silence.
    }

    #[test]
    fn l06_suppressed_under_strict_lifecycle_check_too() {
        // Whole-tree mode honors allow_untracked_acs identically to the
        // chain-targeted mode (the dispatch path is shared via
        // check_l06_outline_acs).
        let root = build_single_pr_chain("- [ ] open\n");
        let mut cfg = Config::default();
        cfg.allow_untracked_acs = true;
        let errors = run_lifecycle_check(&root, &cfg, ReviewPosture::Ready);
        let l06s: Vec<_> = errors.iter().filter(|e| e.code == "L06").collect();
        assert!(
            l06s.is_empty(),
            "whole-tree mode should honor allow_untracked_acs too; got {:?}",
            l06s
        );
    }

    #[test]
    fn l06_does_not_fire_on_multi_pr_plan() {
        // Build a multi-pr chain whose PLAN uses the existing multi-pr
        // plan_body (which has no `## Issue Outlines` section). L06
        // should not fire even though the multi-pr posture has unticked
        // boxes elsewhere in the doc.
        let root = build_tree(&[
            ("docs/briefs/BRIEF-foo.md", &make_brief("Accepted", ""), &body_for("BRIEF", "Accepted")),
            ("docs/prds/PRD-foo.md", &make_prd("Accepted", "docs/briefs/BRIEF-foo.md"), &prd_body("Accepted")),
            ("docs/designs/DESIGN-foo.md", &make_design("Planned", "docs/prds/PRD-foo.md"), &design_body("Planned")),
            ("docs/plans/PLAN-foo.md", &make_plan("Active", "multi-pr", "docs/designs/DESIGN-foo.md"), &plan_body("Active")),
        ]);
        let plan_path = root.join("docs/plans/PLAN-foo.md");
        let errors = run_lifecycle_chain_check(&plan_path, &Config::default(), ReviewPosture::Draft);
        let l06s: Vec<_> = errors.iter().filter(|e| e.code == "L06").collect();
        assert!(
            l06s.is_empty(),
            "expected no L06 errors on multi-pr PLAN; got {:?}",
            l06s
        );
    }
}
