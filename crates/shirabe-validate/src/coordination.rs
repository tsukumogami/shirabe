//! Coordinated multi-repo orchestration: the contract logic behind the
//! `shirabe coordination` subcommand.
//!
//! This module is the skeleton spine of the coordinated capability defined in
//! `references/coordination-strategy.md`. It carries the pieces that the
//! deeper verbs (sync, gate, finalize read pass) build on:
//!
//! - [`parse_cross_repo_ref`] — the F2 `owner/repo:path` component parser and
//!   validator. Each component is validated before use: owner/repo against the
//!   GitHub charset regex (reusing [`crate::gh::is_valid_owner_or_repo`]), and
//!   the path against in-root, no-symlink lexical confinement (no absolute
//!   paths, no `..` traversal, no newline/NUL). A failing reference is an
//!   `Err`, never a silent skip (R21).
//! - [`Visibility`] + [`VisibilityResolver`] — the F1 input: each indexed PR's
//!   repo visibility is resolved before render. The trait keeps the render path
//!   testable offline (a test injects a `Private` verdict without touching
//!   `gh`).
//! - [`render_index_line`] — the F1 fail-closed render. A private (or
//!   unresolvable) repo renders to an **opaque node id and merge state only**;
//!   no private owner/repo/path/branch/title/number ever reaches the rendered
//!   line.
//! - [`seed_body`] — the `create` verb's body skeleton (declaration, artifact
//!   chain, PR-index, fenced merge-order block).
//!
//! Security model: a coordination PR lives at the most-restrictive visibility
//! of any repo the effort touches (the Coordination-PR Visibility Rule in
//! `references/coordination-strategy.md`), so a **public** coordination PR only
//! ever coordinates public repos. [`decide_visibility_guard`] is that
//! front-door enforcement: a public coordination PR refuses to index a private
//! node, because `Public -> Private` references are forbidden
//! (`references/cross-repo-references.md`). F1 redaction ([`render_index_line`],
//! [`redacted_label`]) is the **fail-closed backstop** for the residual edges
//! the front door cannot pre-empt (a repo flips visibility mid-effort, a
//! moved/renamed/unresolvable ref → treat as private → redact to an opaque id),
//! not the mechanism that enables cross-visibility coordination — that is
//! forbidden. F2 validates every reference before use. The deeper F4 live-`gh`
//! gate lands in a later issue; this skeleton wires the read seam (`status`)
//! through the existing `gh.rs` client.

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

/// A repo's visibility, the F1 render input.
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

/// One indexed PR in the coordination PR-index, as known before render.
///
/// `node_id` is the opaque, non-sensitive identity (e.g. `pr-1`) used in the
/// merge-order DAG and in the redacted render. `reference`, `title`, and
/// `number` may be private and are emitted in the clear only after the repo
/// resolves to [`Visibility::Public`].
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct IndexedPr {
    /// Opaque node id, safe to render regardless of visibility.
    pub node_id: String,
    /// The validated cross-repo reference for the PR's repo + artifact.
    pub reference: CrossRepoRef,
    /// The PR number (potentially private — gated by F1).
    pub number: u64,
    /// The PR title (potentially private — gated by F1).
    pub title: String,
    /// Whether the PR has merged (merge state is non-sensitive; it is the one
    /// field F1 permits even for a private node).
    pub merged: bool,
}

/// Render one PR-index line for the **public** coordination PR body, applying
/// F1 redaction.
///
/// The resolver decides visibility from the PR's repo slug. For a public repo
/// the line carries the node id, the `owner/repo:path` reference, the PR
/// number, the (escaped) title, and merge state. For a private — or
/// unresolvable, fail-closed — repo the line carries **only the opaque node id
/// and merge state**: no owner, repo, path, branch, title, or number.
pub fn render_index_line(pr: &IndexedPr, resolver: &dyn VisibilityResolver) -> String {
    let merge_state = if pr.merged { "merged" } else { "open" };
    match resolver.visibility(&pr.reference.slug()) {
        Visibility::Public => format!(
            "- {} | {}#{} | {} | {}",
            pr.node_id,
            pr.reference.slug(),
            pr.number,
            escape_inline(&pr.title),
            merge_state,
        ),
        Visibility::Private => format!("- {} | (private) | {}", pr.node_id, merge_state),
    }
}

/// Render an F1-redacted **diagnostic label** for a cross-repo reference.
///
/// A diagnostic (the merge-last gate's blocker reasons, the `verify` result
/// line) is a render path under F1 exactly like the PR-index body: a private
/// repo's owner, repo, path, and number are themselves private and MUST NOT
/// reach a diagnostic in the clear. This helper resolves the repo's visibility
/// and, for a public repo, returns the full `owner/repo:path#number` label; for
/// a private — or unresolvable, fail-closed — repo it returns the supplied
/// opaque `node_id` (e.g. `pr-3`), which carries no private identifier.
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

/// Escape `gh`-sourced free text (PR titles, branch names) before it enters a
/// markdown table cell or list line (F3). Newlines and pipe characters would
/// break the row shape; backticks and angle brackets are neutralized so the
/// untrusted string cannot open markdown/HTML constructs.
///
/// The result is a non-load-bearing annotation: the authoritative merge-order
/// fields derive from validated state, never from this text.
pub fn escape_inline(s: &str) -> String {
    let mut out = String::with_capacity(s.len());
    for ch in s.chars() {
        match ch {
            '\n' | '\r' => out.push(' '),
            '|' => out.push('\\'),
            '`' => out.push('\''),
            '<' => out.push('('),
            '>' => out.push(')'),
            '\0' => {}
            other => out.push(other),
        }
    }
    out
}

/// The inputs the `create` verb renders the seed coordination-PR body from.
#[derive(Clone, Debug)]
pub struct SeedInputs {
    /// Effort slug (e.g. `capstone-orchestration`).
    pub slug: String,
    /// The artifact chain paths to declare (BRIEF/PRD/DESIGN/PLAN), in order.
    pub artifact_chain: Vec<String>,
}

/// Render the seed body for a freshly created coordination PR: the
/// declaration, the artifact chain, an (initially empty) PR-index, and a fenced
/// merge-order block. The body is rendered from the PLAN render; this skeleton
/// produces the structural shape the later `sync`/`gate` verbs fill in.
pub fn seed_body(inputs: &SeedInputs) -> String {
    let mut out = String::new();
    out.push_str(&format!(
        "# Coordination PR: {}\n\n",
        escape_inline(&inputs.slug)
    ));
    out.push_str(
        "> This is a **coordination PR** for a coordinated multi-repo effort. It is \
         docs-only and merges **last**, once every indexed per-repo PR has merged and \
         finalization is complete. See `references/coordination-strategy.md`.\n\n",
    );

    out.push_str("## Artifact Chain\n\n");
    if inputs.artifact_chain.is_empty() {
        out.push_str("_(none yet)_\n\n");
    } else {
        for artifact in &inputs.artifact_chain {
            out.push_str(&format!("- {}\n", escape_inline(artifact)));
        }
        out.push('\n');
    }

    out.push_str("## PR Index\n\n");
    out.push_str("_(no per-repo PRs indexed yet)_\n\n");

    out.push_str("## Merge Order\n\n");
    out.push_str("```merge-order\n");
    out.push_str("# Two-node merge-order DAG (PR nodes + non-PR gate nodes).\n");
    out.push_str("# Rendered from the PLAN; recomputed live by `shirabe coordination sync`.\n");
    out.push_str("```\n");

    out
}

/// Render the merge-time canonical coordination-PR body from a resolved set of
/// indexed PRs (Decision D). Pure: no network, no `gh` — the caller resolves
/// each [`IndexedPr`]'s live merge state and visibility before calling, then
/// this function renders the durable body that survives the PLAN's deletion (R8).
///
/// The body has two authoritative sections:
///
/// - **PR Index** — one [`render_index_line`] per node, applying F1 redaction
///   (private nodes collapse to opaque node id + merge state) and F3 escaping
///   (every `gh`-sourced title is run through [`escape_inline`] inside
///   `render_index_line`).
/// - **Merge Order** — a fenced ```` ```merge-order ```` block listing the nodes
///   in an acyclic order (see [`acyclic_node_order`]). The block carries only
///   opaque node ids and non-sensitive merge state, so it is safe to render
///   regardless of any node's visibility.
///
/// `slug` and `artifact_chain` reproduce the [`seed_body`] header so a synced
/// body is a drop-in replacement for the seed body.
pub fn render_sync_body(
    slug: &str,
    artifact_chain: &[String],
    prs: &[IndexedPr],
    resolver: &dyn VisibilityResolver,
) -> String {
    let mut out = String::new();
    out.push_str(&format!("# Coordination PR: {}\n\n", escape_inline(slug)));
    out.push_str(
        "> This is a **coordination PR** for a coordinated multi-repo effort. It is \
         docs-only and merges **last**, once every indexed per-repo PR has merged and \
         finalization is complete. See `references/coordination-strategy.md`.\n\n",
    );

    out.push_str("## Artifact Chain\n\n");
    if artifact_chain.is_empty() {
        out.push_str("_(none yet)_\n\n");
    } else {
        for artifact in artifact_chain {
            out.push_str(&format!("- {}\n", escape_inline(artifact)));
        }
        out.push('\n');
    }

    out.push_str("## PR Index\n\n");
    if prs.is_empty() {
        out.push_str("_(no per-repo PRs indexed yet)_\n\n");
    } else {
        for pr in prs {
            out.push_str(&render_index_line(pr, resolver));
            out.push('\n');
        }
        out.push('\n');
    }

    out.push_str("## Merge Order\n\n");
    out.push_str(&render_merge_order_block(prs));

    out
}

/// Render the fenced ```` ```merge-order ```` block for a resolved node set,
/// recomputed as an acyclic order over the indexed nodes.
///
/// The block carries only opaque node ids and merge state — no `owner/repo`,
/// path, title, or number — so it is always safe regardless of visibility, and
/// it reflects the **live** merge state of each node (F4): a node that has
/// merged renders `merged`, an open one renders `open`. The order is acyclic by
/// construction (see [`acyclic_node_order`]).
fn render_merge_order_block(prs: &[IndexedPr]) -> String {
    let mut out = String::new();
    out.push_str("```merge-order\n");
    out.push_str("# Two-node merge-order DAG (PR nodes + non-PR gate nodes).\n");
    out.push_str("# Rendered from the PLAN; recomputed live by `shirabe coordination sync`.\n");
    let order = acyclic_node_order(prs);
    for node_id in &order {
        // Look up the node's live merge state by opaque id.
        let state = prs
            .iter()
            .find(|p| &p.node_id == node_id)
            .map(|p| if p.merged { "merged" } else { "open" })
            .unwrap_or("open");
        out.push_str(&format!("{} | {}\n", escape_inline(node_id), state));
    }
    out.push_str("```\n");
    out
}

/// Produce an acyclic order over the indexed nodes' opaque ids.
///
/// The [`IndexedPr`] set carries no inter-node edges (the edge data lives in the
/// PLAN, which Decision D collapses into this flat node list at render time), so
/// the order is the nodes' first-appearance order — acyclic by construction
/// because it introduces no back-edge. Duplicate node ids are de-duplicated,
/// keeping the first occurrence, so the rendered order lists every node exactly
/// once.
fn acyclic_node_order(prs: &[IndexedPr]) -> Vec<String> {
    let mut order: Vec<String> = Vec::with_capacity(prs.len());
    for pr in prs {
        if !order.iter().any(|n| n == &pr.node_id) {
            order.push(pr.node_id.clone());
        }
    }
    order
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

#[cfg(test)]
mod tests {
    use super::*;

    /// Stub resolver that returns a fixed verdict, used to exercise the F1
    /// render path offline (no `gh`).
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

    // --- F1: private-repo node redaction in the public render ---

    #[test]
    fn f1_private_node_renders_opaque_id_only() {
        // A node whose repo, path, title, and number are all private-sensitive.
        let pr = IndexedPr {
            node_id: "pr-1".to_string(),
            reference: parse_cross_repo_ref(
                "tsukumogami/secret-repo:docs/designs/DESIGN-classified.md",
            )
            .unwrap(),
            number: 4242,
            title: "Secret internal feature name".to_string(),
            merged: false,
        };
        let resolver = StubResolver(Visibility::Private);
        let line = render_index_line(&pr, &resolver);

        // Only the opaque node id and merge state appear.
        assert!(
            line.contains("pr-1"),
            "opaque node id must be present: {}",
            line
        );
        assert!(line.contains("open"), "merge state may appear: {}", line);

        // No private identifier leaks: owner, repo, path, title, or number.
        assert!(
            !line.contains("secret-repo"),
            "private repo leaked: {}",
            line
        );
        assert!(
            !line.contains("tsukumogami"),
            "private owner leaked: {}",
            line
        );
        assert!(
            !line.contains("DESIGN-classified.md"),
            "private path leaked: {}",
            line
        );
        assert!(
            !line.contains("Secret internal feature name"),
            "private title leaked: {}",
            line
        );
        assert!(!line.contains("4242"), "private number leaked: {}", line);
    }

    #[test]
    fn f1_public_node_renders_full_index_line() {
        let pr = IndexedPr {
            node_id: "pr-2".to_string(),
            reference: parse_cross_repo_ref("tsukumogami/shirabe:docs/plans/PLAN-x.md").unwrap(),
            number: 196,
            title: "Add coordination subcommand".to_string(),
            merged: true,
        };
        let resolver = StubResolver(Visibility::Public);
        let line = render_index_line(&pr, &resolver);
        assert!(line.contains("pr-2"));
        assert!(line.contains("tsukumogami/shirabe"));
        assert!(line.contains("196"));
        assert!(line.contains("Add coordination subcommand"));
        assert!(line.contains("merged"));
    }

    // --- F1: diagnostic-label redaction (gate blocker reasons, verify result) ---

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
        assert!(!label.contains("acme"), "ref leaked on fail-closed: {}", label);
    }

    #[test]
    fn escape_inline_neutralizes_table_breakers() {
        let escaped = escape_inline("a|b\nc`d<e>f");
        assert!(!escaped.contains('|'));
        assert!(!escaped.contains('\n'));
        assert!(!escaped.contains('`'));
        assert!(!escaped.contains('<'));
        assert!(!escaped.contains('>'));
    }

    #[test]
    fn seed_body_has_all_skeleton_sections() {
        let body = seed_body(&SeedInputs {
            slug: "capstone-orchestration".to_string(),
            artifact_chain: vec!["docs/plans/PLAN-capstone-orchestration.md".to_string()],
        });
        assert!(body.contains("coordination PR"));
        assert!(body.contains("## Artifact Chain"));
        assert!(body.contains("docs/plans/PLAN-capstone-orchestration.md"));
        assert!(body.contains("## PR Index"));
        assert!(body.contains("## Merge Order"));
        assert!(body.contains("```merge-order"));
    }

    // --- render_sync_body: the merge-time canonical body (Decision D) ---

    /// Resolver that decides visibility per-slug from an allow-list of public
    /// slugs, mirroring the production `gh`-backed resolver's verdict shape but
    /// offline. Any slug not on the list is private (fail-closed).
    struct SlugResolver(Vec<String>);
    impl VisibilityResolver for SlugResolver {
        fn visibility(&self, slug: &str) -> Visibility {
            if self.0.iter().any(|s| s == slug) {
                Visibility::Public
            } else {
                Visibility::Private
            }
        }
    }

    /// A public node and a private node mixed in one index. F1: the private
    /// node's owner/repo/path/title/number must not leak; only its opaque node
    /// id and merge state appear. The public node renders in full.
    #[test]
    fn sync_body_redacts_private_node_keeps_public(/* F1 */) {
        let public_pr = IndexedPr {
            node_id: "pr-shirabe-api".to_string(),
            reference: parse_cross_repo_ref("tsukumogami/shirabe:docs/plans/PLAN-x.md").unwrap(),
            number: 196,
            title: "Public coordination subcommand".to_string(),
            merged: true,
        };
        let private_pr = IndexedPr {
            node_id: "pr-secret-core".to_string(),
            reference: parse_cross_repo_ref(
                "tsukumogami/secret-repo:docs/designs/DESIGN-classified.md",
            )
            .unwrap(),
            number: 4242,
            title: "Secret internal feature name".to_string(),
            merged: false,
        };
        let resolver = SlugResolver(vec!["tsukumogami/shirabe".to_string()]);
        let body = render_sync_body(
            "capstone-orchestration",
            &["docs/plans/PLAN-capstone-orchestration.md".to_string()],
            &[public_pr, private_pr],
            &resolver,
        );

        // Public node renders in full.
        assert!(body.contains("pr-shirabe-api"));
        assert!(body.contains("tsukumogami/shirabe"));
        assert!(body.contains("196"));
        assert!(body.contains("Public coordination subcommand"));

        // Private node: only opaque id + merge state survive.
        assert!(body.contains("pr-secret-core"));
        assert!(
            !body.contains("secret-repo"),
            "private repo leaked: {}",
            body
        );
        assert!(
            !body.contains("DESIGN-classified.md"),
            "private path leaked: {}",
            body
        );
        assert!(
            !body.contains("Secret internal feature name"),
            "private title leaked: {}",
            body
        );
        assert!(!body.contains("4242"), "private number leaked: {}", body);
    }

    /// F3: a public node whose title carries every table/markdown breaker is
    /// escaped before it reaches the rendered index line.
    #[test]
    fn sync_body_escapes_gh_sourced_title(/* F3 */) {
        let pr = IndexedPr {
            node_id: "pr-shirabe-api".to_string(),
            reference: parse_cross_repo_ref("tsukumogami/shirabe:docs/plans/PLAN-x.md").unwrap(),
            number: 7,
            title: "evil|title\nwith`back<ticks>".to_string(),
            merged: false,
        };
        let resolver = SlugResolver(vec!["tsukumogami/shirabe".to_string()]);
        let body = render_sync_body("slug", &[], &[pr], &resolver);

        // Scope the breaker assertions to the rendered index line, not the
        // static boilerplate (which legitimately contains backticks/fences).
        let line = body
            .lines()
            .find(|l| l.starts_with("- pr-shirabe-api"))
            .expect("public index line present");

        // The raw, unescaped title must not appear; the breakers are neutralized.
        assert!(
            !line.contains("evil|title"),
            "unescaped pipe survived: {}",
            line
        );
        // The title's own backtick/angle brackets are escaped away. The only `|`
        // left on the line are the cell separators render_index_line emits.
        assert!(!line.contains('`'), "backtick survived: {}", line);
        assert!(!line.contains('<'), "angle bracket survived: {}", line);
        assert!(!line.contains('>'), "angle bracket survived: {}", line);
        // The non-breaker text survives in escaped form.
        assert!(line.contains("title"));
    }

    /// The fenced merge-order block lists every node exactly once in an acyclic
    /// order. With no inter-node edges, that is first-appearance order; the
    /// block carries only opaque ids + merge state (safe regardless of
    /// visibility).
    #[test]
    fn sync_body_merge_order_is_acyclic_and_complete() {
        let prs = vec![
            IndexedPr {
                node_id: "pr-a".to_string(),
                reference: parse_cross_repo_ref("tsukumogami/shirabe:docs/a.md").unwrap(),
                number: 1,
                title: "a".to_string(),
                merged: false,
            },
            IndexedPr {
                node_id: "pr-b".to_string(),
                reference: parse_cross_repo_ref("tsukumogami/secret:docs/b.md").unwrap(),
                number: 2,
                title: "b".to_string(),
                merged: true,
            },
            IndexedPr {
                node_id: "pr-c".to_string(),
                reference: parse_cross_repo_ref("tsukumogami/koto:docs/c.md").unwrap(),
                number: 3,
                title: "c".to_string(),
                merged: false,
            },
        ];
        let resolver = SlugResolver(vec!["tsukumogami/shirabe".to_string()]);
        let body = render_sync_body("slug", &[], &prs, &resolver);

        // Extract the fenced merge-order block.
        let block_start = body.find("```merge-order").expect("block present");
        let after = &body[block_start..];
        let block_end = after[3..].find("```").expect("block closes") + 3;
        let block = &after[..block_end];

        // Every node id appears exactly once in the order block.
        for node in ["pr-a", "pr-b", "pr-c"] {
            assert_eq!(
                block.matches(node).count(),
                1,
                "node {} should appear once in {}",
                node,
                block
            );
        }

        // First-appearance (acyclic) order: pr-a precedes pr-b precedes pr-c.
        let pos_a = block.find("pr-a").unwrap();
        let pos_b = block.find("pr-b").unwrap();
        let pos_c = block.find("pr-c").unwrap();
        assert!(
            pos_a < pos_b && pos_b < pos_c,
            "order not acyclic: {}",
            block
        );
    }

    /// F4: the merge-order block reflects **live** merge state. Re-rendering the
    /// same node set after a node flips open -> merged changes the body text.
    #[test]
    fn sync_body_reflects_live_merge_state_change(/* F4 */) {
        let make = |merged: bool| IndexedPr {
            node_id: "pr-shirabe-api".to_string(),
            reference: parse_cross_repo_ref("tsukumogami/shirabe:docs/plans/PLAN-x.md").unwrap(),
            number: 196,
            title: "title".to_string(),
            merged,
        };
        let resolver = SlugResolver(vec!["tsukumogami/shirabe".to_string()]);

        let open_body = render_sync_body("slug", &[], &[make(false)], &resolver);
        let merged_body = render_sync_body("slug", &[], &[make(true)], &resolver);

        // The two renders differ: the live state propagates into the body.
        assert_ne!(open_body, merged_body);

        // The merge-order block specifically flips open -> merged.
        let order_state = |body: &str| -> bool {
            let start = body.find("```merge-order").unwrap();
            let block = &body[start..];
            // The node line carries `pr-shirabe-api | <state>`.
            block.contains("pr-shirabe-api | merged")
        };
        assert!(!order_state(&open_body), "open body wrongly shows merged");
        assert!(order_state(&merged_body), "merged body should show merged");
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
    /// the only readable field is the live `merged` flag. This test demonstrates
    /// that a body claiming "all merged" is irrelevant: with the live flag still
    /// `false`, the gate blocks.
    #[test]
    fn gate_ignores_body_claim_uses_live_status_only(/* F4 */) {
        // Simulate a coordination PR body asserting the PR has merged. The body
        // text is not an input to `decide_gate` at all — we keep it here only to
        // make the F4 intent legible. The function signature physically cannot
        // accept it.
        let _editable_body_claiming_merged =
            "## PR Index\n- pr-evil | tsukumogami/shirabe#1 | title | merged\n";

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
}
