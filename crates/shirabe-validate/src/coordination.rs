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
//! Security model: this is the public-coordination-PR egress point. F1 redacts
//! private identifiers fail-closed; F2 validates every reference before use.
//! The deeper F4 live-`gh` gate lands in a later issue; this skeleton wires the
//! read seam (`status`) through the existing `gh.rs` client.

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
}
