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
//!   so the author can read the rule directly.
//! - **L02**: an orphan doc (no downstream `upstream:` reference) at
//!   non-terminal status whose own `upstream:` does not point at an
//!   Active ROADMAP. The orphan-rule violation per
//!   `docs/decisions/DECISION-orphan-doc-passing-state-rule-2026-06-06.md`.
//! - **L03**: a cycle detected in the upstream graph. The message
//!   names every doc participating in the cycle.
//! - **L04**: a chain member references an `upstream:` parent that
//!   does not exist in the index.
//! - **L05**: defensive parsing fallback — the walker could not
//!   extract `upstream:` or `status:` from a chain-participating doc.
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
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
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

/// A discovered chain, with members in BRIEF -> PRD -> DESIGN ->
/// PLAN/ROADMAP order (some leading members may be absent if the
/// upstream chain doesn't go all the way up).
#[derive(Debug, Clone)]
pub struct Chain {
    pub members: Vec<ChainMember>,
    pub root_kind: RootKind,
    pub posture: Posture,
}

/// Computed passing state for a chain member.
#[derive(Debug, Clone, PartialEq, Eq)]
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

/// Pull the `upstream:` field from a parsed doc.
///
/// Handles two shapes: scalar (`upstream: path`) and list-of-lines
/// (the `FieldValue` carries multi-line content when the YAML is a
/// list). Strips template placeholders containing `<` or `>`.
/// Resolves relative paths against the root.
fn extract_upstreams(canon_root: &Path, canon_path: &Path, doc: &Doc) -> Vec<PathBuf> {
    let mut out = Vec::new();
    let raw = match doc.fields.get("upstream") {
        Some(f) => f.value.clone(),
        None => return out,
    };

    // Split on newlines; each line may be a `- path` list item, a
    // bare `path` scalar, or a multi-doc string. Defensive parsing:
    // strip leading whitespace and `- ` prefixes, ignore template
    // placeholders, ignore empty lines.
    for line in raw.lines() {
        let trimmed = line.trim().trim_start_matches('-').trim();
        if trimmed.is_empty() {
            continue;
        }
        // Strip inline `# ...` comments.
        let bare = trimmed.split('#').next().unwrap_or("").trim();
        if bare.is_empty() {
            continue;
        }
        // Skip template placeholders.
        if bare.contains('<') || bare.contains('>') {
            continue;
        }
        // Resolve as relative-to-root.
        let resolved = canon_root.join(bare);
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

// ---------- chain discovery + posture inference ----------

/// Discover all chains in the index. Each chain is rooted at a PLAN
/// or ROADMAP and walks the forward `upstream:` edge to gather BRIEF,
/// PRD, DESIGN members.
///
/// Cycles in the upstream graph produce an L03 error and the cyclic
/// chain is dropped from the result.
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
        let mut visited: HashSet<PathBuf> = HashSet::new();
        let mut order: Vec<PathBuf> = Vec::new();
        let mut cur = Some(indexed.path.clone());

        while let Some(cur_path) = cur {
            if !visited.insert(cur_path.clone()) {
                // Cycle detected — emit L03 naming the cycle.
                order.push(cur_path.clone());
                let cycle_str = order
                    .iter()
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
            order.push(cur_path.clone());

            let node = match idx.get(&cur_path) {
                Some(n) => n,
                None => {
                    // Upstream points at a missing parent — L04.
                    errors.push(error_path(
                        indexed.path.clone(),
                        "L04",
                        &format!(
                            "chain member missing: upstream references {} which does not exist",
                            rel_path_lossy(&cur_path)
                        ),
                    ));
                    break;
                }
            };

            if let Some(role) = ChainRole::from_format(&node.format) {
                members.push(ChainMember {
                    path: node.path.clone(),
                    role,
                    status: node.status.clone(),
                });
            }

            // Walk to the parent. PLAN -> DESIGN -> PRD -> BRIEF in
            // the forward upstream direction. Take the first upstream
            // if multiple are present (the additional upstreams are
            // typically optional context, e.g. ROADMAP parents).
            //
            // Stop the walk at a BRIEF: BRIEF is the chain's anchor.
            // If a BRIEF carries an `upstream:` field (e.g. pointing
            // at a parent DESIGN to record an amendment relationship),
            // that's a cross-chain reference, not a chain-membership
            // edge, and we do not follow it.
            if matches!(node.format.as_str(), "Brief") {
                break;
            }
            cur = node.upstreams.first().cloned();
        }

        if members.is_empty() {
            continue;
        }

        // Reverse so chain reads BRIEF -> PRD -> DESIGN -> PLAN.
        members.reverse();

        let posture = infer_posture_from(indexed);
        chains.push(Chain {
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
        (Prd, SinglePrMidPR) => PassingState::Status("Accepted"),
        (Design, SinglePrMidPR) => PassingState::DesignPlannedOrCurrent,
        (Plan, SinglePrMidPR) => PassingState::Status("Active"),
        (Roadmap, SinglePrMidPR) => PassingState::Status("Active"),

        // Single-pr at-merge (PLAN absent; this branch is mostly for
        // ROADMAP shape).
        (Brief, SinglePrAtMerge) => PassingState::Status("Done"),
        (Prd, SinglePrAtMerge) => PassingState::Status("Done"),
        (Design, SinglePrAtMerge) => PassingState::Status("Current"),
        (Plan, SinglePrAtMerge) => PassingState::Deleted,
        (Roadmap, SinglePrAtMerge) => PassingState::Status("Active"),
    }
}

// ---------- orphan-doc rule ----------
//
// See docs/decisions/DECISION-orphan-doc-passing-state-rule-2026-06-06.md
// for the rule's full Context, Options Considered, and Consequences.
//
// In short: an orphan doc (no inverse-upstream reference from any
// other doc) at its artifact's target state passes; an orphan at non-
// terminal status whose own upstream points at an Active ROADMAP
// passes (ROADMAP-rooted in-flight case); every other orphan fails
// with L02.

fn check_orphan(
    doc: &IndexedDoc,
    idx: &DocIndex,
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
            "orphan {} at status '{}' (expected {} or an Active ROADMAP upstream)",
            doc.format.to_uppercase(),
            doc.status,
            expected
        ),
    ))
}

// ---------- public entry point ----------

/// Run the chain-aware passing-state lifecycle check against `root`.
///
/// Returns an empty vec when every chain member is at its passing
/// state and every orphan doc honors the orphan-rule. Otherwise
/// returns one or more `ValidationError`s carrying `Lnn` codes.
///
/// The `strict` flag controls the DRAFT-vs-READY discipline for
/// single-pr chains. When false (the default), `Posture::SinglePrMidPR`
/// is a passing posture — BRIEF/PRD at Accepted, DESIGN at
/// Planned/Current, PLAN at Draft is healthy iteration. When true,
/// `Posture::SinglePrMidPR` is re-targeted to the
/// `Posture::SinglePrAtMerge` passing-state row at check time, so a
/// present single-pr PLAN fails and single-pr BRIEF/PRD at Accepted
/// fail. Multi-pr postures are unchanged by the strict flag.
///
/// The CI workflow sets `strict=true` when the PR is ready-for-review
/// (`github.event.pull_request.draft == false`) and `strict=false`
/// when the PR is draft.
pub fn run_lifecycle_check(
    root: &Path,
    _cfg: &Config,
    strict: bool,
) -> Vec<ValidationError> {
    let (idx, mut errors) = build_doc_index(root);
    let _inv = build_inverse_upstream(&idx);
    let (chains, chain_errors) = discover_chains(&idx);
    errors.extend(chain_errors);

    // Track which docs participate in any chain so we can apply the
    // orphan rule only to non-chain-participating docs.
    let mut chain_participants: HashSet<PathBuf> = HashSet::new();
    for chain in &chains {
        for member in &chain.members {
            chain_participants.insert(member.path.clone());
        }
    }

    // Per-chain passing-state check.
    for chain in &chains {
        // Apply the strict-mode posture re-target. When strict is set
        // and the chain's posture is single-pr-mid-PR, the
        // passing-state computation uses the single-pr at-merge row
        // (PLAN deleted, BRIEF/PRD Done, DESIGN Current) instead of
        // the mid-PR exemption. Multi-pr postures are unchanged.
        let effective_posture = if strict && chain.posture == Posture::SinglePrMidPR {
            Posture::SinglePrAtMerge
        } else {
            chain.posture
        };
        for member in &chain.members {
            let passing = compute_passing_state(member.role, effective_posture);
            // The chain root is present in the tree by definition (we
            // discovered it by walking the index). If its passing
            // state is Deleted, that's the work-completing posture's
            // forcing function — fail L01.
            // The member was discovered by walking the index, so it is
            // present in the tree by definition. `PassingState::Deleted`
            // therefore always fails for a discovered member (the
            // forcing-function shape); other variants compare against
            // the member's current status via `matches`.
            let mismatch = match &passing {
                PassingState::Deleted => true,
                _ => !passing.matches(&member.status),
            };
            if mismatch {
                errors.push(error_path(
                    member.path.clone(),
                    "L01",
                    &format!(
                        "{} at status '{}' (expected {} for {} posture)",
                        member.role.as_str(),
                        member.status,
                        passing.describe(),
                        effective_posture.name()
                    ),
                ));
            }
        }
    }

    // Orphan rule for non-chain-participating docs.
    for (path, doc) in &idx {
        if chain_participants.contains(path) {
            continue;
        }
        if let Some(err) = check_orphan(doc, &idx) {
            errors.push(err);
        }
    }

    // Stable error ordering: by file, then by code, then by message.
    errors.sort_by(|a, b| {
        a.file
            .cmp(&b.file)
            .then(a.code.cmp(&b.code))
            .then(a.message.cmp(&b.message))
    });
    errors.dedup();
    errors
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
#[allow(dead_code)]
fn _btreeset_used(_: BTreeSet<()>) {}

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
        let errors = run_lifecycle_check(&root, &Config::default(), false);
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
        let errors = run_lifecycle_check(&root, &Config::default(), false);
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
        let errors = run_lifecycle_check(&root, &Config::default(), false);
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
        let errors = run_lifecycle_check(&root, &Config::default(), false);
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
        let errors = run_lifecycle_check(&root, &Config::default(), false);
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
        let errors = run_lifecycle_check(&root, &Config::default(), false);
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
        let errors = run_lifecycle_check(&root, &Config::default(), false);
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
        let errors = run_lifecycle_check(&root, &Config::default(), false);
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
        let errors = run_lifecycle_check(&root, &Config::default(), false);
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
        let errors = run_lifecycle_check(&root, &Config::default(), false);
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
        let errors = run_lifecycle_check(&root, &Config::default(), false);
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
        let errors = run_lifecycle_check(&root, &Config::default(), false);
        assert!(errors.is_empty(), "expected pass, got {:?}", errors);
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
        let errors = run_lifecycle_check(&root, &Config::default(), false);
        assert!(
            errors.iter().any(|e| e.code == "L03"),
            "expected L03 cycle, got {:?}",
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
        let errors = run_lifecycle_check(&root, &Config::default(), false);
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
        let errors = run_lifecycle_check(&root, &Config::default(), false);
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
        let errors = run_lifecycle_check(&root, &Config::default(), false);
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
        let errors = run_lifecycle_check(&root, &Config::default(), false);
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
        let errors = run_lifecycle_check(&root, &Config::default(), false);
        assert!(errors.is_empty(), "expected pass (PRD at In Progress in-flight), got {:?}", errors);
    }

    #[test]
    fn empty_tree_passes() {
        let root = build_tree(&[]);
        let errors = run_lifecycle_check(&root, &Config::default(), false);
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
        let errors = run_lifecycle_check(&root, &Config::default(), false);
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
        let errors = run_lifecycle_check(&root, &Config::default(), true);
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
        let errors = run_lifecycle_check(&root, &Config::default(), true);
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
        let errors = run_lifecycle_check(&root, &Config::default(), true);
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
            run_lifecycle_check(&root_nonstrict, &Config::default(), false);
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
            run_lifecycle_check(&root_strict, &Config::default(), true);
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
        let errors = run_lifecycle_check(&root, &Config::default(), true);
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
        let errors_nonstrict = run_lifecycle_check(&root_a, &Config::default(), false);
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
        let errors_strict = run_lifecycle_check(&root_b, &Config::default(), true);
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
}
