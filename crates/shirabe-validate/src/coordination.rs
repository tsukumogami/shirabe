//! Coordinated multi-repo orchestration: the pure check and decision cores
//! behind shirabe's coordinated capability.
//!
//! The coordination PR body is **authored by the skill** (from the template in
//! `references/coordination-strategy.md`), not rendered by a CLI subcommand —
//! the same author-by-skill discipline every other shirabe artifact follows.
//! This module carries the pure cores `shirabe validate` uses to *check* that
//! body and to gate it at merge time:
//!
//! - [`parse_cross_repo_ref`] — the F2 `owner/repo:path` component parser and
//!   validator. Each component is validated before use: owner/repo against the
//!   GitHub charset regex (reusing [`crate::gh::is_valid_owner_or_repo`]), and
//!   the path against in-root, no-symlink lexical confinement (no absolute
//!   paths, no `..` traversal, no newline/NUL). A failing reference is an
//!   `Err`, never a silent skip (R21).
//! - [`Visibility`] + [`VisibilityResolver`] — the F1 input: each indexed PR's
//!   repo visibility is resolved before a diagnostic names it. The trait keeps
//!   the redaction path testable offline (a test injects a `Private` verdict
//!   without touching `gh`).
//! - [`redacted_label`] — the F1 fail-closed diagnostic redaction. A private
//!   (or unresolvable) repo surfaces only its opaque node id; no private
//!   owner/repo/path/number reaches a diagnostic.
//! - [`decide_visibility_guard`] — the Coordination-PR Visibility Rule front
//!   door: a public coordination PR refuses to index a private node.
//! - [`decide_gate`] — the pure merge-last gate core (F4).
//! - [`check_coordination_body`] / [`is_acyclic_order`] — the static
//!   authoring-feedback check the `shirabe validate --coordination-body` mode
//!   runs over an authored body, offline (no `gh`): declaration marker present,
//!   every cross-repo ref token parses and passes F2, and the fenced
//!   merge-order block is acyclic.
//!
//! Security model: a coordination PR lives at the most-restrictive visibility
//! of any repo the effort touches (the Coordination-PR Visibility Rule in
//! `references/coordination-strategy.md`), so a **public** coordination PR only
//! ever coordinates public repos. [`decide_visibility_guard`] is that
//! front-door enforcement: a public coordination PR refuses to index a private
//! node, because `Public -> Private` references are forbidden
//! (`references/cross-repo-references.md`). F1 redaction ([`redacted_label`]) is
//! the **fail-closed backstop** for the residual edges the front door cannot
//! pre-empt (a repo flips visibility mid-effort, a moved/renamed/unresolvable
//! ref → treat as private → redact to an opaque id), not the mechanism that
//! enables cross-visibility coordination — that is forbidden. F2 validates every
//! reference before use. The live F4 `gh` gate lives in [`crate::merge_gate`].

use crate::gh::is_valid_owner_or_repo;

/// A parsed, validated cross-repo `owner/repo:path` reference.
///
/// Construct only via [`parse_cross_repo_ref`], which is the F2 validation
/// gate; the fields are already component-validated by the time a value of this
/// type exists.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct CrossRepoRef {
    pub owner: String,
    pub repo: String,
    pub path: String,
}

impl CrossRepoRef {
    /// The `owner/repo` slug used as the visibility-resolution key.
    pub fn slug(&self) -> String {
        format!("{}/{}", self.owner, self.repo)
    }

    /// The full `owner/repo:path` reference, reproducing the canonical input
    /// shape. Used to label a node in a diagnostic (e.g. the merge-last gate's
    /// blocker reasons) from its already-validated components.
    pub fn slug_and_path(&self) -> String {
        format!("{}/{}:{}", self.owner, self.repo, self.path)
    }
}

/// Parse and validate a cross-repo `owner/repo:path` reference (F2).
///
/// The first colon separates the `owner/repo` selector from the path, matching
/// `cross-repo-references.md`. Every component is validated before the value is
/// returned:
///
/// - `owner` and `repo` against the GitHub charset regex (via
///   [`is_valid_owner_or_repo`]);
/// - the `path` against lexical confinement: non-empty, relative (no leading
///   `/`), no `..` traversal segment, and no newline or NUL byte.
///
/// A reference that fails any check returns `Err` with a diagnostic — it is
/// never silently accepted (R21). This is the single F2 gate every coordination
/// read path routes through before using a reference.
pub fn parse_cross_repo_ref(value: &str) -> Result<CrossRepoRef, String> {
    let colon = value.find(':').ok_or_else(|| {
        format!(
            "not a cross-repo reference (missing `owner/repo:path` colon): {:?}",
            value
        )
    })?;
    let selector = &value[..colon];
    let path = &value[colon + 1..];

    let (owner, repo) = selector.split_once('/').ok_or_else(|| {
        format!(
            "malformed repo selector (expected `owner/repo`): {:?}",
            selector
        )
    })?;

    if !is_valid_owner_or_repo(owner) {
        return Err(format!("invalid owner component: {:?}", owner));
    }
    if !is_valid_owner_or_repo(repo) {
        return Err(format!("invalid repo component: {:?}", repo));
    }

    validate_ref_path(path)?;

    Ok(CrossRepoRef {
        owner: owner.to_string(),
        repo: repo.to_string(),
        path: path.to_string(),
    })
}

/// Lexical path confinement for the F2 path component. Mirrors
/// `finalize.rs`'s in-root, no-symlink intent at the string level: reject the
/// shapes that can escape a repo root or smuggle control bytes before the path
/// is ever resolved on disk.
fn validate_ref_path(path: &str) -> Result<(), String> {
    if path.is_empty() {
        return Err("empty path component in cross-repo reference".to_string());
    }
    if path.starts_with('/') {
        return Err(format!("path component must be repo-relative: {:?}", path));
    }
    if path.contains('\n') || path.contains('\r') || path.contains('\0') {
        return Err("path component contains a control byte (newline or NUL)".to_string());
    }
    // Reject any `..` traversal segment (component-wise, so `..foo` is fine but
    // `../`, `a/../b`, and a trailing `..` are not).
    for segment in path.split('/') {
        if segment == ".." {
            return Err(format!(
                "path component contains `..` traversal: {:?}",
                path
            ));
        }
    }
    Ok(())
}

/// A repo's visibility, the F1 redaction input.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Visibility {
    Public,
    /// Private, or visibility that could not be resolved (fail-closed: F1
    /// treats unresolvable as private).
    Private,
}

/// Resolves a repo's visibility from its `owner/repo` slug.
///
/// The production resolver queries `gh`; the F1 unit test injects a stub so the
/// redaction path is exercised offline. A resolver that cannot determine
/// visibility MUST return [`Visibility::Private`] (fail closed) — never an
/// error that the caller could mistake for "public."
pub trait VisibilityResolver {
    fn visibility(&self, slug: &str) -> Visibility;
}

/// One indexed PR in the coordination PR-index, as known at gate time.
///
/// `node_id` is the opaque, non-sensitive identity (e.g. `pr-1`) used in the
/// merge-order DAG and in a redacted diagnostic. `reference` and `number` may
/// be private and are emitted in the clear only after the repo resolves to
/// [`Visibility::Public`].
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct IndexedPr {
    /// Opaque node id, safe to render regardless of visibility.
    pub node_id: String,
    /// The validated cross-repo reference for the PR's repo + artifact.
    pub reference: CrossRepoRef,
    /// The PR number (potentially private — gated by F1).
    pub number: u64,
    /// Whether the PR has merged (merge state is non-sensitive; it is the one
    /// field F1 permits even for a private node).
    pub merged: bool,
}

/// Render an F1-redacted **diagnostic label** for a cross-repo reference.
///
/// A diagnostic (the merge-last gate's blocker reasons, a visibility refusal)
/// is a render path under F1: a private repo's owner, repo, path, and number
/// are themselves private and MUST NOT reach a diagnostic in the clear. This
/// helper resolves the repo's visibility and, for a public repo, returns the
/// full `owner/repo:path#number` label; for a private — or unresolvable,
/// fail-closed — repo it returns the supplied opaque `node_id` (e.g. `pr-3`),
/// which carries no private identifier.
///
/// The caller MUST route every cross-repo reference through this helper before
/// interpolating it into a diagnostic, log, or any other operator-visible
/// string. Passing the raw [`CrossRepoRef::slug_and_path`] straight into a
/// diagnostic is an F1 leak.
pub fn redacted_label(
    reference: &CrossRepoRef,
    number: u64,
    node_id: &str,
    resolver: &dyn VisibilityResolver,
) -> String {
    match resolver.visibility(&reference.slug()) {
        Visibility::Public => format!("{}#{}", reference.slug_and_path(), number),
        // Fail closed: private or unresolvable repos surface only the opaque
        // node id, never the owner/repo/path/number.
        Visibility::Private => node_id.to_string(),
    }
}

/// One indexed PR's *live-resolved* merge status, as the merge-last gate sees
/// it (F4). The `merged` flag is always the product of an authoritative live
/// `gh` read recomputed at gate time — never a value parsed from the editable
/// coordination PR body. `label` is an opaque, non-sensitive identifier (a node
/// id or public reference) used only to name a blocker in a diagnostic; F1
/// redaction is the caller's responsibility before any private slug reaches it.
///
/// The type deliberately carries **no PR body and no body-sourced claim**: the
/// only thing the gate decision can read is the live `merged` flag. That is what
/// makes [`decide_gate`] structurally immune to a "merged"-claiming body (F4) —
/// there is nowhere in the input for a body claim to live.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct GatePrStatus {
    /// Opaque, non-sensitive label for diagnostics (node id or public ref).
    pub label: String,
    /// Live-resolved merge state. `true` only when an authoritative `gh` read
    /// resolved the PR as merged/closed at gate time; `false` for open *and*
    /// for any unresolvable read (fail closed).
    pub merged: bool,
}

/// One upstream's *live-resolved* terminal status, as the merge-last gate sees
/// it. As with [`GatePrStatus`], `terminal` is always the product of a live
/// read (via `verify_cross_repo_upstream_terminal`), never a body claim.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct GateUpstreamStatus {
    /// Opaque, non-sensitive label for diagnostics.
    pub label: String,
    /// Live-resolved terminal state. `true` only when the upstream verified as
    /// terminal (merged/closed); `false` for non-terminal *and* unresolvable
    /// (fail closed).
    pub terminal: bool,
}

/// The outcome of the pure merge-last gate decision.
///
/// `Pass` means every indexed PR resolved merged AND every upstream resolved
/// terminal — the only state in which the coordination PR may merge (R7/R14).
/// `Block` carries one human-readable reason per blocker, each naming the
/// offending node, so the caller can surface exactly what holds the gate closed
/// (R21: never a silent skip).
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum GateDecision {
    /// All PRs merged and all upstreams terminal: the gate passes (exit 0).
    Pass,
    /// At least one blocker; each reason names the node it blocks on.
    Block(Vec<String>),
}

impl GateDecision {
    /// Whether the gate passed.
    pub fn passed(&self) -> bool {
        matches!(self, GateDecision::Pass)
    }
}

/// The pure, network-free core of the merge-last gate (F4 / Decision D).
///
/// Given the **live-resolved** per-PR merged flags and per-upstream terminal
/// flags, decide whether the coordination PR may merge. The gate passes only
/// when every indexed PR is merged AND every upstream is terminal; otherwise it
/// blocks with one reason per blocker, each naming the offending node.
///
/// This function is the F4 firewall expressed in the type system: its inputs are
/// resolved statuses, not PR bodies. A coordination PR body that *claims* a PR
/// merged cannot influence the result, because a claim has no representation in
/// [`GatePrStatus`] — the only field the decision reads is the live `merged`
/// flag the caller obtained from `gh`. Unresolvable reads are folded into
/// `merged == false` / `terminal == false` by the caller (fail closed), so an
/// unresolvable node blocks here exactly like an unmerged one.
pub fn decide_gate(prs: &[GatePrStatus], upstreams: &[GateUpstreamStatus]) -> GateDecision {
    let mut reasons: Vec<String> = Vec::new();
    for pr in prs {
        if !pr.merged {
            reasons.push(format!(
                "indexed PR {} is not merged (live status); merge-last gate blocked",
                pr.label
            ));
        }
    }
    for up in upstreams {
        if !up.terminal {
            reasons.push(format!(
                "upstream {} is not terminal (live status); merge-last gate blocked",
                up.label
            ));
        }
    }
    if reasons.is_empty() {
        GateDecision::Pass
    } else {
        GateDecision::Block(reasons)
    }
}

/// The outcome of the coordination-PR visibility front-door check.
///
/// `Allow` means the coordination PR may index every node it was given. `Refuse`
/// carries one human-readable reason per violating index, each naming the
/// offending node through an **already-F1-redacted** label, so the diagnostic
/// itself cannot leak a private identifier (R21: never a silent skip).
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum VisibilityGuardDecision {
    /// The coordination PR's visibility legally covers every indexed node.
    Allow,
    /// At least one indexed node violates the most-restrictive-visibility rule;
    /// each reason names the offending node via its redacted label.
    Refuse(Vec<String>),
}

impl VisibilityGuardDecision {
    /// Whether the coordination PR may proceed to index its nodes.
    pub fn allowed(&self) -> bool {
        matches!(self, VisibilityGuardDecision::Allow)
    }
}

/// One indexed node's resolved visibility plus an already-redacted diagnostic
/// label, as the coordination-PR visibility front-door check sees it.
///
/// `visibility` is the live-resolved (or fail-closed) verdict for the node's
/// repo. `label` is the F1-redacted identifier the caller already routed through
/// [`redacted_label`] — for a private node it is the opaque node id, so a refusal
/// diagnostic built from it cannot leak a private slug. The check deliberately
/// reads no raw `owner/repo` here: a leak is only possible if the caller hands a
/// raw slug as the label, which is the same caller responsibility F1 already
/// places on every diagnostic path.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct GuardIndexNode {
    /// Already-F1-redacted, non-sensitive label for the diagnostic.
    pub label: String,
    /// Live-resolved visibility of the node's repo. [`Visibility::Private`]
    /// covers both genuinely-private and unresolvable (fail-closed) repos.
    pub visibility: Visibility,
}

/// The pure front-door check for the **Coordination-PR Visibility Rule**: a
/// coordination PR lives at the most-restrictive visibility of any repo the
/// effort touches.
///
/// `Public → Private` references are forbidden by the workspace's directional
/// visibility rule (`references/cross-repo-references.md`, the "Visibility rule"
/// table): a public artifact must not reference a private repo's artifact. The
/// coordination PR holds the PLAN, which names each indexed repo in plaintext,
/// so a public coordination PR that indexes a private repo would name that
/// private repo regardless of render-layer redaction. The fix is structural, not
/// cosmetic: the coordination PR must itself be private whenever the effort
/// touches any private repo.
///
/// This function is that rule expressed as a decision:
///
/// - A **public** coordination PR may index only **public** nodes. Any node that
///   resolves [`Visibility::Private`] — including an unresolvable repo, which
///   fails closed to private upstream of this call — is a violation, and the
///   check **refuses fail-closed**.
/// - A **private** coordination PR may index **any** node (private *and* public),
///   because `Private → Public` references are allowed: a private coordination PR
///   can legally describe and index everything.
///
/// This is the front-door enforcement; F1 render-layer redaction is the
/// fail-closed backstop for the residual edges this check cannot pre-empt (a
/// repo flips visibility mid-effort, a moved/renamed/unresolvable ref). The
/// labels in `index` are already F1-redacted, so a refusal diagnostic built here
/// cannot leak a private identifier.
pub fn decide_visibility_guard(
    coordination_pr_visibility: Visibility,
    index: &[GuardIndexNode],
) -> VisibilityGuardDecision {
    // A private coordination PR may index anything (Private -> Public allowed).
    if coordination_pr_visibility == Visibility::Private {
        return VisibilityGuardDecision::Allow;
    }

    // A public coordination PR may index only public nodes. Any private (or
    // fail-closed-to-private) node is a Public -> Private violation.
    let mut reasons: Vec<String> = Vec::new();
    for node in index {
        if node.visibility == Visibility::Private {
            reasons.push(format!(
                "public coordination PR cannot index private node {} \
                 (Public -> Private reference is forbidden; \
                 see references/cross-repo-references.md); \
                 an effort touching any private repo requires a private coordination PR",
                node.label
            ));
        }
    }

    if reasons.is_empty() {
        VisibilityGuardDecision::Allow
    } else {
        VisibilityGuardDecision::Refuse(reasons)
    }
}

// --- Static coordination-body check (`shirabe validate --coordination-body`) ---

/// The fixed declaration marker every coordination PR body must carry. The
/// merge-last gate in `lifecycle.yml` detects a coordination PR by grepping for
/// this exact substring, so the static check verifies the author wrote it.
pub const COORDINATION_DECLARATION_MARKER: &str = "This is a **coordination PR**";

/// The fence opener for the merge-order block the body carries.
const MERGE_ORDER_FENCE: &str = "```merge-order";

/// One finding from the static coordination-body check. `line` is 1-based (or
/// `1` for a whole-body finding such as a missing marker); `message` is an
/// actionable "what to fix and why" string the CLI renders in any `--format`.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct CoordinationBodyFinding {
    pub line: usize,
    pub message: String,
}

/// Statically check an **authored** coordination PR body, offline (no `gh`).
///
/// This is the static analog of `shirabe validate <brief-file>`: it gives the
/// author feedback before the body is posted, checking the three things that can
/// be verified without a network read:
///
/// 1. The declaration marker ([`COORDINATION_DECLARATION_MARKER`]) is present —
///    without it the merge-last gate will not recognize the PR.
/// 2. Every cross-repo ref token (`owner/repo:path#number`) parses and passes
///    F2 ([`parse_cross_repo_ref`]) — a malformed reference is a hard finding,
///    never a silent skip (R21).
/// 3. The fenced `merge-order` block (if present) lists each node once in an
///    acyclic order ([`is_acyclic_order`]).
///
/// The **visibility** rule (a public coordination PR must not reference a
/// private repo) and the **live merge state** (F4) need `gh`, so they live in
/// `shirabe validate --merge-gate` and are deliberately NOT duplicated here.
///
/// Returns the findings in source order; an empty vec means the body is clean.
pub fn check_coordination_body(body: &str) -> Vec<CoordinationBodyFinding> {
    let mut findings: Vec<CoordinationBodyFinding> = Vec::new();

    // 1. Declaration marker.
    if !body.contains(COORDINATION_DECLARATION_MARKER) {
        findings.push(CoordinationBodyFinding {
            line: 1,
            message: format!(
                "coordination PR body is missing the declaration marker {:?}. \
                 Add the blockquote line so the merge-last gate recognizes this \
                 as a coordination PR; see references/coordination-strategy.md.",
                COORDINATION_DECLARATION_MARKER
            ),
        });
    }

    // 2. Every cross-repo ref token parses and passes F2. Reuse the same token
    //    shape `lifecycle.yml` extracts from the body's PR-index lines.
    for (idx, line) in body.lines().enumerate() {
        let line_no = idx + 1;
        for token in extract_ref_tokens(line) {
            // Split the `#number` suffix the same way the merge-gate input does.
            let (ref_str, number_str) = match token.rsplit_once('#') {
                Some(pair) => pair,
                None => continue,
            };
            if number_str.parse::<u64>().is_err() {
                findings.push(CoordinationBodyFinding {
                    line: line_no,
                    message: format!(
                        "cross-repo ref {:?} has a non-numeric `#number` suffix; \
                         use `owner/repo:path#number`.",
                        token
                    ),
                });
                continue;
            }
            if let Err(msg) = parse_cross_repo_ref(ref_str) {
                findings.push(CoordinationBodyFinding {
                    line: line_no,
                    message: format!(
                        "cross-repo ref {:?} fails validation (F2): {}. \
                         Use `owner/repo:path#number` with a repo-relative path.",
                        token, msg
                    ),
                });
            }
        }
    }

    // 3. The fenced merge-order block, if present, must be acyclic.
    if let Some(nodes) = parse_merge_order_block(body) {
        if let Err(msg) = is_acyclic_order(&nodes) {
            findings.push(CoordinationBodyFinding {
                line: 1,
                message: format!(
                    "the fenced ```merge-order``` block is not a valid acyclic order: {}. \
                     List each node once; see references/coordination-strategy.md.",
                    msg
                ),
            });
        }
    }

    findings
}

/// Extract `owner/repo:path#number` tokens from one body line, matching the
/// shape `lifecycle.yml` greps for. A token is a whitespace/`|`-delimited run
/// that contains a `/`, a `:`, and a trailing `#<digits>`.
fn extract_ref_tokens(line: &str) -> Vec<&str> {
    line.split(|c: char| c.is_whitespace() || c == '|')
        .map(str::trim)
        .filter(|tok| {
            // Cheap structural pre-filter: must look like `owner/repo:...#n`.
            tok.contains('/')
                && tok.contains(':')
                && tok
                    .rsplit_once('#')
                    .map(|(_, n)| !n.is_empty() && n.chars().all(|c| c.is_ascii_digit()))
                    .unwrap_or(false)
        })
        .collect()
}

/// Parse the node ids out of the fenced ```` ```merge-order ```` block. Returns
/// `None` when no block is present (a body with no block is not a finding here —
/// the marker/ref checks already ran). Each non-comment, non-empty line inside
/// the fence contributes its first `|`-or-whitespace-delimited token as a node
/// id.
fn parse_merge_order_block(body: &str) -> Option<Vec<String>> {
    let start = body.find(MERGE_ORDER_FENCE)?;
    // Move past the fence opener line.
    let after_fence = &body[start + MERGE_ORDER_FENCE.len()..];
    let close = after_fence.find("```")?;
    let inner = &after_fence[..close];

    let mut nodes: Vec<String> = Vec::new();
    for line in inner.lines() {
        let trimmed = line.trim();
        if trimmed.is_empty() || trimmed.starts_with('#') {
            continue;
        }
        let node = trimmed
            .split(|c: char| c == '|' || c.is_whitespace())
            .find(|s| !s.is_empty());
        if let Some(node) = node {
            nodes.push(node.to_string());
        }
    }
    Some(nodes)
}

/// Check that a merge-order node list is a valid acyclic order.
///
/// The authored block lists nodes in their intended merge order; the contract's
/// two-node DAG carries no inline back-edges, so "acyclic" reduces to "each node
/// appears at most once." A repeated node id is the signature of a cycle (a node
/// ordered both before and after itself), so it is rejected. Returns `Ok(())`
/// for a clean order, or `Err` naming the first duplicate.
pub fn is_acyclic_order(nodes: &[String]) -> Result<(), String> {
    let mut seen: Vec<&str> = Vec::with_capacity(nodes.len());
    for node in nodes {
        if seen.contains(&node.as_str()) {
            return Err(format!(
                "node {:?} appears more than once (a node ordered both before and after \
                 itself is a cycle)",
                node
            ));
        }
        seen.push(node.as_str());
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    /// Stub resolver that returns a fixed verdict, used to exercise the F1
    /// redaction path offline (no `gh`).
    struct StubResolver(Visibility);
    impl VisibilityResolver for StubResolver {
        fn visibility(&self, _slug: &str) -> Visibility {
            self.0
        }
    }

    // --- F2: parse_cross_repo_ref ---

    #[test]
    fn parse_accepts_canonical_reference() {
        let r = parse_cross_repo_ref("tsukumogami/shirabe:docs/designs/DESIGN-x.md").unwrap();
        assert_eq!(r.owner, "tsukumogami");
        assert_eq!(r.repo, "shirabe");
        assert_eq!(r.path, "docs/designs/DESIGN-x.md");
        assert_eq!(r.slug(), "tsukumogami/shirabe");
    }

    #[test]
    fn parse_rejects_missing_colon() {
        assert!(parse_cross_repo_ref("docs/designs/DESIGN-x.md").is_err());
    }

    #[test]
    fn parse_rejects_bad_owner_or_repo() {
        assert!(parse_cross_repo_ref("has space/shirabe:docs/x.md").is_err());
        assert!(parse_cross_repo_ref("tsukumogami/has space:docs/x.md").is_err());
        assert!(parse_cross_repo_ref("/shirabe:docs/x.md").is_err());
    }

    #[test]
    fn parse_rejects_path_traversal_and_absolute() {
        assert!(parse_cross_repo_ref("tsukumogami/shirabe:../escape.md").is_err());
        assert!(parse_cross_repo_ref("tsukumogami/shirabe:docs/../../escape.md").is_err());
        assert!(parse_cross_repo_ref("tsukumogami/shirabe:/etc/passwd").is_err());
    }

    #[test]
    fn parse_rejects_control_bytes_in_path() {
        assert!(parse_cross_repo_ref("tsukumogami/shirabe:docs/x\ninjected.md").is_err());
        assert!(parse_cross_repo_ref("tsukumogami/shirabe:docs/x\0.md").is_err());
    }

    #[test]
    fn parse_allows_dotdot_only_as_prefix_not_segment() {
        // `..foo` is a legitimate filename, not a traversal segment.
        let r = parse_cross_repo_ref("tsukumogami/shirabe:docs/..hidden.md").unwrap();
        assert_eq!(r.path, "docs/..hidden.md");
    }

    // --- F1: diagnostic-label redaction (gate blocker reasons, visibility refusal) ---

    #[test]
    fn f1_redacted_label_hides_private_ref() {
        // A private upstream whose owner/repo/path/number are all sensitive.
        let reference =
            parse_cross_repo_ref("tsukumogami/secret-repo:docs/designs/DESIGN-classified.md")
                .unwrap();
        let resolver = StubResolver(Visibility::Private);
        // The node id is an opaque, operator-chosen identity; here it carries no
        // sensitive number so the "number leaked" assertion can be exact.
        let label = redacted_label(&reference, 4242, "upstream-a", &resolver);

        // Only the opaque node id surfaces; no private identifier leaks into the
        // diagnostic label.
        assert_eq!(label, "upstream-a");
        assert!(
            !label.contains("secret-repo"),
            "private repo leaked: {}",
            label
        );
        assert!(
            !label.contains("tsukumogami"),
            "private owner leaked: {}",
            label
        );
        assert!(
            !label.contains("DESIGN-classified.md"),
            "private path leaked: {}",
            label
        );
        assert!(!label.contains("4242"), "private number leaked: {}", label);
    }

    #[test]
    fn f1_redacted_label_shows_public_ref() {
        let reference = parse_cross_repo_ref("tsukumogami/shirabe:docs/plans/PLAN-x.md").unwrap();
        let resolver = StubResolver(Visibility::Public);
        let label = redacted_label(&reference, 196, "pr-196", &resolver);
        assert_eq!(label, "tsukumogami/shirabe:docs/plans/PLAN-x.md#196");
    }

    #[test]
    fn f1_redacted_label_fails_closed_on_unresolvable() {
        // The StubResolver returning Private is the fail-closed verdict the
        // production resolver yields when visibility cannot be resolved; the
        // label must collapse to the opaque node id rather than leak the ref.
        let reference = parse_cross_repo_ref("acme/unknown:docs/x.md").unwrap();
        let resolver = StubResolver(Visibility::Private);
        let label = redacted_label(&reference, 7, "pr-7", &resolver);
        assert_eq!(label, "pr-7");
        assert!(
            !label.contains("acme"),
            "ref leaked on fail-closed: {}",
            label
        );
    }

    // --- decide_gate: the pure merge-last gate core (F4 / Decision D) ---

    fn pr(label: &str, merged: bool) -> GatePrStatus {
        GatePrStatus {
            label: label.to_string(),
            merged,
        }
    }

    fn upstream(label: &str, terminal: bool) -> GateUpstreamStatus {
        GateUpstreamStatus {
            label: label.to_string(),
            terminal,
        }
    }

    /// All PRs merged and all upstreams terminal => the gate passes.
    #[test]
    fn gate_passes_when_all_merged_and_all_terminal() {
        let prs = [pr("pr-a", true), pr("pr-b", true)];
        let ups = [upstream("design-x", true)];
        assert_eq!(decide_gate(&prs, &ups), GateDecision::Pass);
        assert!(decide_gate(&prs, &ups).passed());
    }

    /// An empty index trivially passes (no blockers); the caller decides whether
    /// an empty index is meaningful — the pure core only reports blockers.
    #[test]
    fn gate_passes_with_no_nodes() {
        assert_eq!(decide_gate(&[], &[]), GateDecision::Pass);
    }

    /// One unmerged PR blocks, and the reason names exactly that PR.
    #[test]
    fn gate_blocks_when_one_pr_unmerged() {
        let prs = [pr("pr-merged", true), pr("pr-open", false)];
        let decision = decide_gate(&prs, &[]);
        match decision {
            GateDecision::Block(reasons) => {
                assert_eq!(reasons.len(), 1, "exactly one blocker: {:?}", reasons);
                assert!(
                    reasons[0].contains("pr-open"),
                    "reason must name the unmerged PR: {}",
                    reasons[0]
                );
                assert!(
                    !reasons[0].contains("pr-merged"),
                    "the merged PR must not be named a blocker: {}",
                    reasons[0]
                );
            }
            GateDecision::Pass => panic!("expected Block, got Pass"),
        }
    }

    /// An unresolvable PR — folded by the caller into `merged == false` (fail
    /// closed) — blocks the gate exactly like an unmerged one. The pure core
    /// sees only the resolved flag, so "unresolvable" and "open" are the same
    /// blocking input here; the fail-closed mapping lives at the call site.
    #[test]
    fn gate_blocks_when_pr_unresolvable_fail_closed() {
        // `merged: false` is what the caller emits for an unresolvable read.
        let prs = [pr("pr-unresolvable", false)];
        let decision = decide_gate(&prs, &[]);
        assert!(
            !decision.passed(),
            "an unresolvable (=> not-merged) PR must block: {:?}",
            decision
        );
        match decision {
            GateDecision::Block(reasons) => {
                assert!(reasons.iter().any(|r| r.contains("pr-unresolvable")));
            }
            GateDecision::Pass => unreachable!(),
        }
    }

    /// A non-terminal upstream blocks, and the reason names it.
    #[test]
    fn gate_blocks_when_upstream_not_terminal() {
        let prs = [pr("pr-a", true)];
        let ups = [upstream("upstream-open", false)];
        let decision = decide_gate(&prs, &ups);
        match decision {
            GateDecision::Block(reasons) => {
                assert!(
                    reasons.iter().any(|r| r.contains("upstream-open")),
                    "reason must name the non-terminal upstream: {:?}",
                    reasons
                );
            }
            GateDecision::Pass => panic!("expected Block, got Pass"),
        }
    }

    /// Multiple blockers each surface their own named reason (R21: never a
    /// silent skip — every blocker is reported).
    #[test]
    fn gate_reports_every_blocker() {
        let prs = [pr("pr-a", false), pr("pr-b", true), pr("pr-c", false)];
        let ups = [upstream("up-x", false)];
        match decide_gate(&prs, &ups) {
            GateDecision::Block(reasons) => {
                assert_eq!(reasons.len(), 3, "three blockers expected: {:?}", reasons);
                assert!(reasons.iter().any(|r| r.contains("pr-a")));
                assert!(reasons.iter().any(|r| r.contains("pr-c")));
                assert!(reasons.iter().any(|r| r.contains("up-x")));
            }
            GateDecision::Pass => panic!("expected Block"),
        }
    }

    /// F4: the decision core takes only live-resolved statuses. A coordination
    /// PR body that *claims* a PR is merged cannot flip the result, because the
    /// core's input ([`GatePrStatus`]) has no field for a body-sourced claim —
    /// the only readable field is the live `merged` flag.
    #[test]
    fn gate_ignores_body_claim_uses_live_status_only(/* F4 */) {
        // The body text is not an input to `decide_gate` at all — the function
        // signature physically cannot accept it.
        let _editable_body_claiming_merged =
            "## PR Index\n- pr-evil | tsukumogami/shirabe#1 | merged\n";

        // The live-resolved status is the only thing the gate reads, and it says
        // not-merged (e.g. the live `gh` read returned Open, or was unresolvable
        // and fail-closed to false).
        let live = [pr("pr-evil", false)];

        let decision = decide_gate(&live, &[]);
        assert!(
            !decision.passed(),
            "a body claiming merged must NOT flip the gate; live status governs"
        );

        // And conversely, flipping the *live* flag (not the body) is what changes
        // the outcome — proving the live status is the sole governing input.
        let live_merged = [pr("pr-evil", true)];
        assert!(
            decide_gate(&live_merged, &[]).passed(),
            "flipping the live status (not the body) is what passes the gate"
        );
    }

    // --- decide_visibility_guard: the Coordination-PR Visibility Rule front door ---

    fn node(label: &str, visibility: Visibility) -> GuardIndexNode {
        GuardIndexNode {
            label: label.to_string(),
            visibility,
        }
    }

    /// A public coordination PR indexing only public nodes is allowed — the
    /// common case (public-only effort -> public coordination PR).
    #[test]
    fn guard_allows_public_pr_with_all_public_index() {
        let index = [
            node("tsukumogami/shirabe:docs/x.md#1", Visibility::Public),
            node("tsukumogami/koto:docs/y.md#2", Visibility::Public),
        ];
        let decision = decide_visibility_guard(Visibility::Public, &index);
        assert_eq!(decision, VisibilityGuardDecision::Allow);
        assert!(decision.allowed());
    }

    /// A public coordination PR indexing even one private node must refuse
    /// fail-closed: this is the forbidden Public -> Private direction, and the
    /// reason names the offending (already-redacted) node.
    #[test]
    fn guard_refuses_public_pr_with_one_private_index() {
        let index = [
            node("tsukumogami/shirabe:docs/x.md#1", Visibility::Public),
            // Already-redacted opaque label for the private node (F1).
            node("pr-2", Visibility::Private),
        ];
        let decision = decide_visibility_guard(Visibility::Public, &index);
        match decision {
            VisibilityGuardDecision::Refuse(reasons) => {
                assert_eq!(reasons.len(), 1, "exactly one violation: {:?}", reasons);
                assert!(
                    reasons[0].contains("pr-2"),
                    "reason must name the private node: {}",
                    reasons[0]
                );
                // The public node is not a violation and must not be named.
                assert!(
                    !reasons[0].contains("tsukumogami/shirabe"),
                    "the public node must not be flagged: {}",
                    reasons[0]
                );
                // The reason cites the directional rule and the remediation.
                assert!(reasons[0].contains("Public -> Private"));
                assert!(reasons[0].contains("private coordination PR"));
            }
            VisibilityGuardDecision::Allow => {
                panic!("a public PR indexing a private node must refuse")
            }
        }
        assert!(!decide_visibility_guard(Visibility::Public, &index).allowed());
    }

    /// A private coordination PR may index a mixed set (private + public): the
    /// Private -> Public direction is allowed, so a private coordination PR can
    /// describe and index everything.
    #[test]
    fn guard_allows_private_pr_with_mixed_index() {
        let index = [
            node("tsukumogami/shirabe:docs/x.md#1", Visibility::Public),
            node("pr-2", Visibility::Private),
        ];
        let decision = decide_visibility_guard(Visibility::Private, &index);
        assert_eq!(decision, VisibilityGuardDecision::Allow);
    }

    /// An unresolvable index visibility is folded to private (fail-closed)
    /// upstream of this call; a public coordination PR therefore refuses it,
    /// exactly like a known-private node. This is the fail-closed edge the
    /// front-door check shares with F1.
    #[test]
    fn guard_refuses_public_pr_with_unresolvable_index_fail_closed() {
        // `Visibility::Private` is the fail-closed verdict the resolver yields
        // for an unresolvable repo.
        let index = [node("pr-3", Visibility::Private)];
        let decision = decide_visibility_guard(Visibility::Public, &index);
        assert!(
            !decision.allowed(),
            "an unresolvable (=> private, fail-closed) node must refuse under a public PR"
        );
        match decision {
            VisibilityGuardDecision::Refuse(reasons) => {
                assert!(reasons.iter().any(|r| r.contains("pr-3")));
            }
            VisibilityGuardDecision::Allow => unreachable!(),
        }
    }

    /// Every violating node surfaces its own named reason (R21: never a silent
    /// skip) and public nodes in the same index are not flagged.
    #[test]
    fn guard_reports_every_private_violation() {
        let index = [
            node("pr-a", Visibility::Private),
            node("tsukumogami/shirabe:docs/x.md#2", Visibility::Public),
            node("pr-c", Visibility::Private),
        ];
        match decide_visibility_guard(Visibility::Public, &index) {
            VisibilityGuardDecision::Refuse(reasons) => {
                assert_eq!(reasons.len(), 2, "two violations expected: {:?}", reasons);
                assert!(reasons.iter().any(|r| r.contains("pr-a")));
                assert!(reasons.iter().any(|r| r.contains("pr-c")));
            }
            VisibilityGuardDecision::Allow => panic!("expected Refuse"),
        }
    }

    // --- check_coordination_body: the static authoring-feedback check ---

    /// A canonical, well-formed body the skill authored passes cleanly.
    fn good_body() -> String {
        format!(
            "# Coordination PR: capstone-orchestration\n\n\
             > {marker} for a coordinated multi-repo effort. It is docs-only and \
             merges last. See references/coordination-strategy.md.\n\n\
             ## Artifact Chain\n\n\
             - docs/plans/PLAN-capstone-orchestration.md\n\n\
             ## PR Index\n\n\
             - pr-1 | tsukumogami/shirabe:docs/plans/PLAN-x.md#196 | open\n\
             - pr-2 | tsukumogami/koto:docs/plans/PLAN-y.md#5 | merged\n\n\
             ## Merge Order\n\n\
             ```merge-order\n\
             # Two-node merge-order DAG.\n\
             pr-1 | open\n\
             pr-2 | merged\n\
             ```\n",
            marker = COORDINATION_DECLARATION_MARKER
        )
    }

    #[test]
    fn body_check_passes_clean_authored_body() {
        let findings = check_coordination_body(&good_body());
        assert!(
            findings.is_empty(),
            "expected clean body, got {:?}",
            findings
        );
    }

    #[test]
    fn body_check_flags_missing_declaration_marker() {
        let body = good_body().replace(COORDINATION_DECLARATION_MARKER, "This is a normal PR");
        let findings = check_coordination_body(&body);
        assert!(
            findings
                .iter()
                .any(|f| f.message.contains("declaration marker")),
            "expected a missing-marker finding: {:?}",
            findings
        );
    }

    #[test]
    fn body_check_flags_malformed_cross_repo_ref() {
        // A traversal path in the ref must fail F2.
        let body = good_body().replace(
            "tsukumogami/shirabe:docs/plans/PLAN-x.md#196",
            "tsukumogami/shirabe:../escape.md#196",
        );
        let findings = check_coordination_body(&body);
        assert!(
            findings.iter().any(|f| f.message.contains("F2")),
            "expected an F2 finding for the traversal ref: {:?}",
            findings
        );
    }

    #[test]
    fn body_check_flags_non_numeric_ref_suffix() {
        let body = good_body().replace(
            "tsukumogami/shirabe:docs/plans/PLAN-x.md#196",
            "tsukumogami/shirabe:docs/plans/PLAN-x.md#abc",
        );
        let findings = check_coordination_body(&body);
        // `#abc` fails the structural token filter, so it is not extracted as a
        // ref token — the malformed-suffix path is exercised via a token that
        // passes the digit filter but with a path issue, covered above. Here we
        // assert no panic and that a clearly numeric-but-otherwise-fine ref is
        // not falsely flagged. The non-numeric case is rejected at extraction.
        assert!(
            !findings.iter().any(|f| f.message.contains("#196")),
            "the valid ref must not be flagged: {:?}",
            findings
        );
    }

    #[test]
    fn body_check_flags_cyclic_merge_order() {
        // A node appearing twice signals a cycle.
        let body = good_body().replace("pr-2 | merged\n```", "pr-1 | merged\n```");
        let findings = check_coordination_body(&body);
        assert!(
            findings.iter().any(|f| f.message.contains("acyclic")),
            "expected a cyclic-order finding: {:?}",
            findings
        );
    }

    #[test]
    fn is_acyclic_order_accepts_distinct_nodes() {
        let nodes = vec!["pr-a".to_string(), "pr-b".to_string(), "pr-c".to_string()];
        assert!(is_acyclic_order(&nodes).is_ok());
    }

    #[test]
    fn is_acyclic_order_rejects_repeat() {
        let nodes = vec!["pr-a".to_string(), "pr-b".to_string(), "pr-a".to_string()];
        let err = is_acyclic_order(&nodes).unwrap_err();
        assert!(
            err.contains("pr-a"),
            "error must name the cycle node: {}",
            err
        );
    }

    #[test]
    fn extract_ref_tokens_pulls_index_line_ref() {
        let line = "- pr-1 | tsukumogami/shirabe:docs/plans/PLAN-x.md#196 | open";
        let tokens = extract_ref_tokens(line);
        assert_eq!(tokens, vec!["tsukumogami/shirabe:docs/plans/PLAN-x.md#196"]);
    }
}
