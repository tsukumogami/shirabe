//! `shirabe coordination` -- the coordinated multi-repo subcommand.
//!
//! Skeleton spine (Issue 1) of the coordinated capability. Two verbs:
//!
//! - `create` -- renders the seed coordination-PR body (declaration, artifact
//!   chain, PR-index, fenced merge-order block) from the supplied artifact
//!   chain and prints it. Full `gh pr create` wiring lands in a later issue;
//!   the skeleton renders the durable body shape the deeper verbs fill in.
//! - `status` -- reads one indexed PR's reference, validates the
//!   `owner/repo:path` with the F2 parser, resolves the repo's visibility via
//!   the `gh` client (fail-closed to private when unresolvable), reads the PR's
//!   merged/open state through the `gh.rs` issue client, and renders one
//!   PR-index line with F1 redaction applied.
//!
//! The contract these verbs bind to lives in
//! `references/coordination-strategy.md`. No prose is restated here.

use std::process::ExitCode;

use shirabe_validate::{
    decide_gate, decide_visibility_guard, parse_cross_repo_ref, redacted_label, render_index_line,
    render_sync_body, seed_body, verify_cross_repo_upstream_terminal, ClientError, CrossRepoRef,
    GateDecision, GatePrStatus, GateUpstreamStatus, GhSubprocessClient, GuardIndexNode, IndexedPr,
    IssueState, IssueStateClient, SeedInputs, Visibility, VisibilityGuardDecision,
    VisibilityResolver,
};

/// Clap-parsed args for `shirabe coordination`.
#[derive(clap::Args)]
pub struct CoordinationArgs {
    #[command(subcommand)]
    pub command: CoordinationCommands,
}

#[derive(clap::Subcommand)]
pub enum CoordinationCommands {
    /// Render the seed body for a docs-only coordination PR: declaration,
    /// artifact chain, an empty PR-index, and a fenced merge-order block.
    /// Prints the body to stdout (full `gh pr create` wiring lands later).
    Create(CreateArgs),
    /// Read one indexed PR via the `gh` client, validate its `owner/repo:path`
    /// (F2), and render its PR-index line redacting any private-repo
    /// identifier (F1, fail-closed).
    Status(StatusArgs),
    /// Read every indexed PR via the `gh` client (read-only, F5), recompute
    /// each one's live merge state (F4) and repo visibility (F1, fail-closed),
    /// and re-render the merge-time canonical coordination-PR body: the
    /// PR-index (private nodes redacted) plus a fenced acyclic merge-order
    /// block. Prints the body to stdout.
    Sync(SyncArgs),
    /// Read-only verify a cross-repo `owner/repo:path` upstream is at a
    /// terminal status (merged/closed). Performs no cross-repo write. Fails
    /// closed (R21): a malformed reference, an unresolvable read, or a
    /// non-terminal upstream halts with a diagnostic (exit 1).
    Verify(VerifyArgs),
    /// The merge-last gate (F4). Recompute "all indexed PRs merged + all
    /// upstreams terminal" from authoritative **live** `gh` queries at gate
    /// time, never from the editable PR body. Passes (exit 0) only when every
    /// indexed PR is merged AND every upstream is terminal; otherwise exits
    /// non-zero with one diagnostic per blocker. Fails closed (R21): any
    /// unresolvable PR or upstream is treated as not-merged / not-terminal.
    /// This verb drives the `lifecycle.yml` non-bypassable backstop.
    Gate(GateArgs),
}

#[derive(clap::Args)]
pub struct CreateArgs {
    /// Effort slug (e.g. `capstone-orchestration`).
    pub slug: String,

    /// An artifact-chain path to declare (repeatable; BRIEF/PRD/DESIGN/PLAN
    /// in order). Each is rendered verbatim into the seed body.
    #[arg(long = "artifact")]
    pub artifacts: Vec<String>,
}

#[derive(clap::Args)]
pub struct StatusArgs {
    /// The indexed PR's cross-repo `owner/repo:path` reference. Validated by
    /// the F2 parser before any use; a malformed reference halts (exit 1).
    pub reference: String,

    /// The PR number to read state for.
    pub number: u64,

    /// The opaque node id rendered for this PR (safe regardless of
    /// visibility). Defaults to `pr-<number>`.
    #[arg(long = "node-id")]
    pub node_id: Option<String>,
}

#[derive(clap::Args)]
pub struct SyncArgs {
    /// Effort slug (e.g. `capstone-orchestration`), reproduced in the body
    /// header.
    pub slug: String,

    /// An indexed PR, given as `owner/repo:path#number` (repeatable). The
    /// `owner/repo:path` is the durable cross-repo reference (validated by the
    /// F2 parser); `#number` is the PR number whose live state is recomputed via
    /// `gh`. The supplied LIST is the durable index; per-PR merged/open status
    /// is never trusted from this argument — it is re-read live (F4).
    #[arg(long = "pr")]
    pub prs: Vec<String>,

    /// An artifact-chain path to declare in the body (repeatable; BRIEF/PRD/
    /// DESIGN/PLAN in order).
    #[arg(long = "artifact")]
    pub artifacts: Vec<String>,

    /// The coordination PR's **own** visibility context; only `private`
    /// declares a private coordination PR. Unset is treated as public
    /// (matching the workspace `--visibility` convention). Per the
    /// Coordination-PR Visibility Rule, a public coordination PR refuses to
    /// index a private repo (fail closed); set `--visibility private` for an
    /// effort that touches any private repo.
    #[arg(long = "visibility", default_value = "")]
    pub visibility: String,
}

#[derive(clap::Args)]
pub struct GateArgs {
    /// An indexed PR, given as `owner/repo:path#number` (repeatable). The
    /// supplied LIST is the durable index; per-PR merged status is **never**
    /// trusted from this argument or any PR body — it is recomputed live via
    /// `gh` (F4). The `owner/repo:path` is validated by the F2 parser before any
    /// read; a malformed reference halts (R21).
    #[arg(long = "pr")]
    pub prs: Vec<String>,

    /// An upstream to verify terminal, given as `owner/repo:path#number`
    /// (repeatable). Each is checked live via
    /// `verify_cross_repo_upstream_terminal`; a non-terminal or unresolvable
    /// upstream blocks the gate (fail closed, R21).
    #[arg(long = "upstream")]
    pub upstreams: Vec<String>,

    /// The coordination PR's **own** visibility context; only `private`
    /// declares a private coordination PR. Unset is treated as public. A public
    /// coordination PR with any private indexed node fails the
    /// Coordination-PR Visibility Rule front door and the gate refuses
    /// (fail closed) before recomputing merge state.
    #[arg(long = "visibility", default_value = "")]
    pub visibility: String,
}

#[derive(clap::Args)]
pub struct VerifyArgs {
    /// The cross-repo `owner/repo:path` upstream reference to verify.
    /// Validated by the F2 parser before any read; a malformed reference
    /// halts (exit 1).
    pub reference: String,

    /// The issue/PR number whose terminal status confirms the upstream.
    pub number: u64,
}

/// Bridges the `gh` client's [`fetch_repo_is_public`] into the F1
/// [`VisibilityResolver`] trait. Fail-closed: any non-public result, or any
/// resolution error, yields [`Visibility::Private`] so the render redacts.
///
/// [`fetch_repo_is_public`]: shirabe_validate::GhSubprocessClient::fetch_repo_is_public
struct GhVisibilityResolver<'a> {
    client: &'a GhSubprocessClient,
}

impl VisibilityResolver for GhVisibilityResolver<'_> {
    fn visibility(&self, slug: &str) -> Visibility {
        // `slug` is the validated `owner/repo` from a `CrossRepoRef`, so the
        // split is infallible; treat any unexpected shape as private.
        let Some((owner, repo)) = slug.split_once('/') else {
            return Visibility::Private;
        };
        match self.client.fetch_repo_is_public(owner, repo) {
            Ok(true) => Visibility::Public,
            // Non-public or any error: fail closed to private (F1).
            Ok(false) | Err(_) => Visibility::Private,
        }
    }
}

/// Map the `--visibility` flag string onto the coordination PR's own
/// [`Visibility`]. Only the literal `private` declares a private coordination
/// PR; everything else (including the empty default) is treated as public,
/// matching the workspace `--visibility` convention where unset means public.
///
/// Defaulting unset to **public** keeps the strict direction of the
/// Coordination-PR Visibility Rule: an effort that touches a private repo must
/// *opt in* with `--visibility private`, so forgetting the flag fails closed
/// into a refusal rather than silently coordinating a private repo from a
/// public PR.
fn coordination_pr_visibility(flag: &str) -> Visibility {
    if flag.eq_ignore_ascii_case("private") {
        Visibility::Private
    } else {
        Visibility::Public
    }
}

/// The Coordination-PR Visibility Rule front-door check, shared by the verbs
/// that index per-repo PRs (`sync`, `gate`). Resolves each indexed PR's repo
/// visibility live (fail-closed to private when unresolvable), builds an
/// F1-redacted label for each node, and routes the set through the pure
/// [`decide_visibility_guard`] decision.
///
/// On `Refuse` the diagnostic is already F1-safe (each label was produced by
/// [`redacted_label`], so a private node surfaces only its opaque node id) — the
/// refusal itself cannot leak a private identifier. Returns the decision so the
/// caller can halt fail-closed before any body render or gate recompute.
fn check_index_visibility(
    coordination_visibility: Visibility,
    refs: &[(CrossRepoRef, u64)],
    resolver: &dyn VisibilityResolver,
) -> VisibilityGuardDecision {
    let nodes: Vec<GuardIndexNode> = refs
        .iter()
        .map(|(reference, number)| {
            let node_id = format!("pr-{}", number);
            GuardIndexNode {
                // F1: the label is already redacted — a private node surfaces
                // only its opaque node id, never the raw owner/repo:path.
                label: redacted_label(reference, *number, &node_id, resolver),
                visibility: resolver.visibility(&reference.slug()),
            }
        })
        .collect();
    decide_visibility_guard(coordination_visibility, &nodes)
}

/// Entry point dispatched from `main.rs`.
pub fn run(args: &CoordinationArgs) -> ExitCode {
    match &args.command {
        CoordinationCommands::Create(c) => run_create(c),
        CoordinationCommands::Status(s) => run_status(s),
        CoordinationCommands::Sync(s) => run_sync(s),
        CoordinationCommands::Verify(v) => run_verify(v),
        CoordinationCommands::Gate(g) => run_gate(g),
    }
}

/// `create`: render and print the seed coordination-PR body.
fn run_create(args: &CreateArgs) -> ExitCode {
    let body = seed_body(&SeedInputs {
        slug: args.slug.clone(),
        artifact_chain: args.artifacts.clone(),
    });
    print!("{}", body);
    ExitCode::SUCCESS
}

/// `status`: validate the reference (F2), read PR state and repo visibility via
/// `gh`, and render the F1-redacted PR-index line.
fn run_status(args: &StatusArgs) -> ExitCode {
    // F2: parse + validate every component before use. A failing reference
    // halts with a diagnostic (R21), never a silent skip.
    let reference = match parse_cross_repo_ref(&args.reference) {
        Ok(r) => r,
        Err(msg) => {
            eprintln!("coordination status: invalid reference: {}", msg);
            return ExitCode::from(1);
        }
    };

    let client = GhSubprocessClient::new();

    // Read merge state through the existing issue/PR client. A PR that cannot
    // be resolved is rendered as not-merged (fail-closed; F4's full live gate
    // lands in a later issue).
    let merged = match client.fetch_issue_state(&reference.owner, &reference.repo, args.number) {
        Ok(IssueState::Closed) => true,
        Ok(IssueState::Open) => false,
        Err(ClientError::Auth) => {
            eprintln!(
                "coordination status: gh is not authenticated; cannot read PR state. \
                 Run `gh auth login`."
            );
            return ExitCode::from(1);
        }
        // Any other read failure: treat as not-merged for the render, but the
        // render still redacts identifiers per F1 below.
        Err(_) => false,
    };

    let node_id = args
        .node_id
        .clone()
        .unwrap_or_else(|| format!("pr-{}", args.number));

    let pr = IndexedPr {
        node_id,
        reference,
        number: args.number,
        // Title is not read in the skeleton status verb; the deeper `sync` verb
        // reads and escapes it. An empty title keeps the public render shape
        // without inventing data.
        title: String::new(),
        merged,
    };

    // F1: resolve visibility and redact private identifiers, fail-closed.
    let resolver = GhVisibilityResolver { client: &client };
    println!("{}", render_index_line(&pr, &resolver));
    ExitCode::SUCCESS
}

/// `sync`: read every indexed PR live via `gh` (read-only, F5), recompute each
/// node's merge state (F4) and visibility (F1, fail-closed), and re-render the
/// merge-time canonical coordination-PR body via the pure
/// [`render_sync_body`] fn.
///
/// The supplied `--pr` list is the durable index; per-PR merged/open status is
/// never trusted from the argument text — it is re-read live through the `gh`
/// client, which is what keeps F4's merge-last gate honest. A malformed
/// reference halts (R21); an unresolvable read renders the node not-merged but
/// still routed through F1 redaction.
fn run_sync(args: &SyncArgs) -> ExitCode {
    let client = GhSubprocessClient::new();
    let resolver = GhVisibilityResolver { client: &client };

    // Parse + validate every reference (F2) up front so the visibility
    // front-door check can run before any body render.
    let mut refs: Vec<(CrossRepoRef, u64)> = Vec::with_capacity(args.prs.len());
    for raw in &args.prs {
        let (ref_str, number) = match split_pr_arg(raw) {
            Ok(pair) => pair,
            Err(msg) => {
                eprintln!("coordination sync: invalid --pr {:?}: {}", raw, msg);
                return ExitCode::from(1);
            }
        };
        // F2: parse + validate every component before use. A failing reference
        // halts with a diagnostic (R21), never a silent skip.
        let reference = match parse_cross_repo_ref(ref_str) {
            Ok(r) => r,
            Err(msg) => {
                eprintln!("coordination sync: invalid reference: {}", msg);
                return ExitCode::from(1);
            }
        };
        refs.push((reference, number));
    }

    // Coordination-PR Visibility Rule front door: a public coordination PR must
    // not index a private repo (Public -> Private is forbidden;
    // references/cross-repo-references.md). Refuse fail-closed before rendering
    // any body. The diagnostic is already F1-redacted.
    let coordination_visibility = coordination_pr_visibility(&args.visibility);
    if let VisibilityGuardDecision::Refuse(reasons) =
        check_index_visibility(coordination_visibility, &refs, &resolver)
    {
        eprintln!("coordination sync: REFUSED (Coordination-PR Visibility Rule):");
        for reason in &reasons {
            eprintln!("  - {}", reason);
        }
        return ExitCode::from(1);
    }

    let mut indexed: Vec<IndexedPr> = Vec::with_capacity(refs.len());
    for (reference, number) in refs {
        // F4: recompute live merge state through the read-only issue client.
        // The body never supplies merged/open — only the list of refs.
        let merged = match client.fetch_issue_state(&reference.owner, &reference.repo, number) {
            Ok(IssueState::Closed) => true,
            Ok(IssueState::Open) => false,
            Err(ClientError::Auth) => {
                eprintln!(
                    "coordination sync: gh is not authenticated; cannot read PR state. \
                     Run `gh auth login`."
                );
                return ExitCode::from(1);
            }
            // Any other read failure: render not-merged; F1 redaction below
            // still applies to the node's identifiers.
            Err(_) => false,
        };

        // Title is read for the public render and escaped (F3) inside
        // render_index_line. An unresolvable body leaves the title empty rather
        // than inventing data.
        let title = client
            .fetch_pr_body(&reference.owner, &reference.repo, number)
            .unwrap_or_default();

        indexed.push(IndexedPr {
            node_id: format!("pr-{}", number),
            reference,
            number,
            title,
            merged,
        });
    }

    // Render the durable, merge-time canonical body via the pure fn. F1
    // redaction + F3 escaping live inside the render; the visibility resolver
    // fails closed to private on any unresolvable repo.
    let body = render_sync_body(&args.slug, &args.artifacts, &indexed, &resolver);
    print!("{}", body);
    ExitCode::SUCCESS
}

/// Split a `--pr` argument of shape `owner/repo:path#number` into its
/// `owner/repo:path` reference and the parsed `number`. The `#number` suffix is
/// taken from the **last** `#`, so a path containing `#` is tolerated. Returns
/// `Err` with a diagnostic when the suffix is missing or not a `u64`.
fn split_pr_arg(raw: &str) -> Result<(&str, u64), String> {
    let hash = raw
        .rfind('#')
        .ok_or_else(|| "missing `#number` PR suffix".to_string())?;
    let (ref_str, num_str) = (&raw[..hash], &raw[hash + 1..]);
    let number = num_str
        .parse::<u64>()
        .map_err(|_| format!("PR number is not a non-negative integer: {:?}", num_str))?;
    Ok((ref_str, number))
}

/// `verify`: read-only verify a cross-repo upstream is at a terminal status.
///
/// Performs no cross-repo write — it is the read-only verification gate. The F2
/// parse and the read-only `gh` query live in
/// [`verify_cross_repo_upstream_terminal`]; this verb only surfaces the result
/// as stdout text + an exit code, failing closed (R21) on any non-terminal or
/// unresolvable outcome.
fn run_verify(args: &VerifyArgs) -> ExitCode {
    let client = GhSubprocessClient::new();
    let resolver = GhVisibilityResolver { client: &client };
    match verify_cross_repo_upstream_terminal(&args.reference, args.number, &client) {
        Ok(v) => {
            // F1: the result line is a render path. Re-validate the reference
            // (it already passed F2 inside the verifier) so it can be routed
            // through `redacted_label`, which fails closed to the opaque node id
            // for a private — or unresolvable — repo. The raw slug/path is never
            // printed in the clear for a private upstream.
            let node_id = format!("upstream-{}", v.number);
            let label = match parse_cross_repo_ref(&args.reference) {
                Ok(reference) => redacted_label(&reference, v.number, &node_id, &resolver),
                // The verifier already validated the ref; an unexpected parse
                // failure here falls back to the opaque node id (fail closed).
                Err(_) => node_id,
            };
            println!("coordination verify: {} is terminal (verified read-only)", label);
            ExitCode::SUCCESS
        }
        Err(e) => {
            eprintln!("coordination verify: {}", e);
            ExitCode::from(1)
        }
    }
}

/// `gate`: the merge-last gate (F4 / Decision D). Recompute each indexed PR's
/// merge state and each upstream's terminal state from authoritative **live**
/// `gh` queries, then route the resolved statuses through the pure
/// [`decide_gate`] core. The gate passes (exit 0) only when every indexed PR is
/// merged AND every upstream is terminal; otherwise it exits non-zero with one
/// diagnostic per blocker.
///
/// **F4 (critical):** merge status is never read from the editable PR body. The
/// `--pr` list is the durable *index* of refs; per-PR merged status is
/// recomputed live here. The body cannot supply a "merged" claim that this verb
/// would trust — the only status input the decision core accepts is the live
/// flag resolved below.
///
/// **Fail closed (R21):** any PR whose live state cannot be resolved is treated
/// as not-merged, and any upstream that cannot be confirmed terminal is treated
/// as non-terminal. A malformed reference halts immediately (it is a hard
/// input error, never a silent skip).
fn run_gate(args: &GateArgs) -> ExitCode {
    let client = GhSubprocessClient::new();
    let resolver = GhVisibilityResolver { client: &client };

    // Parse + validate every indexed PR reference (F2) up front so the
    // Coordination-PR Visibility Rule front door can run before any live read.
    let mut refs: Vec<(CrossRepoRef, u64)> = Vec::with_capacity(args.prs.len());
    for raw in &args.prs {
        let (ref_str, number) = match split_pr_arg(raw) {
            Ok(pair) => pair,
            Err(msg) => {
                eprintln!("coordination gate: invalid --pr {:?}: {}", raw, msg);
                return ExitCode::from(1);
            }
        };
        // F2: parse + validate every component before any read. A malformed
        // reference is a hard input error (R21), not a fail-closed block.
        let reference = match parse_cross_repo_ref(ref_str) {
            Ok(r) => r,
            Err(msg) => {
                eprintln!("coordination gate: invalid reference: {}", msg);
                return ExitCode::from(1);
            }
        };
        refs.push((reference, number));
    }

    // Coordination-PR Visibility Rule front door: a public coordination PR must
    // not index a private repo (Public -> Private is forbidden). Refuse
    // fail-closed before recomputing any merge state. The diagnostic is already
    // F1-redacted.
    let coordination_visibility = coordination_pr_visibility(&args.visibility);
    if let VisibilityGuardDecision::Refuse(reasons) =
        check_index_visibility(coordination_visibility, &refs, &resolver)
    {
        eprintln!("coordination gate: REFUSED (Coordination-PR Visibility Rule):");
        for reason in &reasons {
            eprintln!("  - {}", reason);
        }
        return ExitCode::from(1);
    }

    // Resolve each indexed PR's live merge state (F4). The blocker diagnostic is
    // a render path under F1: a private repo's owner/repo/path/number are
    // themselves private, so each label is routed through `redacted_label`,
    // which fails closed to the opaque node id for a private — or unresolvable —
    // repo. The gate diagnostic never names a private ref in the clear.
    let mut pr_statuses: Vec<GatePrStatus> = Vec::with_capacity(refs.len());
    for (reference, number) in refs {
        // F4: recompute live merge state through the read-only issue client.
        // `Closed` => merged; `Open` => not merged; ANY error => not merged
        // (fail closed). The PR body is never consulted.
        let merged = match client.fetch_issue_state(&reference.owner, &reference.repo, number) {
            Ok(IssueState::Closed) => true,
            Ok(IssueState::Open) => false,
            Err(ClientError::Auth) => {
                eprintln!(
                    "coordination gate: gh is not authenticated; cannot recompute live PR \
                     state. Run `gh auth login`."
                );
                return ExitCode::from(1);
            }
            // Any other read failure: fail closed to not-merged.
            Err(_) => false,
        };

        // Node id mirrors the sync render's opaque identity (`pr-<number>`); it
        // is the fail-closed label for a private/unresolvable repo.
        let node_id = format!("pr-{}", number);
        pr_statuses.push(GatePrStatus {
            label: redacted_label(&reference, number, &node_id, &resolver),
            merged,
        });
    }

    // Resolve each upstream's live terminal state via the read-only verifier.
    // A malformed reference is a hard input error (halt); a non-terminal or
    // unresolvable upstream is folded into `terminal == false` (fail closed).
    let mut upstream_statuses: Vec<GateUpstreamStatus> = Vec::with_capacity(args.upstreams.len());
    for raw in &args.upstreams {
        let (ref_str, number) = match split_pr_arg(raw) {
            Ok(pair) => pair,
            Err(msg) => {
                eprintln!("coordination gate: invalid --upstream {:?}: {}", raw, msg);
                return ExitCode::from(1);
            }
        };

        // Validate the reference up front so a malformed upstream halts (R21)
        // rather than being folded into a fail-closed block.
        let reference = match parse_cross_repo_ref(ref_str) {
            Ok(r) => r,
            Err(msg) => {
                eprintln!("coordination gate: invalid upstream reference: {}", msg);
                return ExitCode::from(1);
            }
        };

        // F1: the upstream blocker diagnostic redacts a private/unresolvable
        // ref to its opaque node id, same as the indexed-PR labels above.
        let node_id = format!("upstream-{}", number);
        let label = redacted_label(&reference, number, &node_id, &resolver);
        let terminal = verify_cross_repo_upstream_terminal(ref_str, number, &client).is_ok();
        upstream_statuses.push(GateUpstreamStatus { label, terminal });
    }

    // The decision is pure: it reads only the live-resolved flags above.
    match decide_gate(&pr_statuses, &upstream_statuses) {
        GateDecision::Pass => {
            println!(
                "coordination gate: PASS ({} PR(s) merged, {} upstream(s) terminal; \
                 recomputed live)",
                pr_statuses.len(),
                upstream_statuses.len()
            );
            ExitCode::SUCCESS
        }
        GateDecision::Block(reasons) => {
            eprintln!("coordination gate: BLOCKED (merge-last gate, recomputed live):");
            for reason in &reasons {
                eprintln!("  - {}", reason);
            }
            ExitCode::from(1)
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// Stub resolver returning a fixed verdict, mirroring the validate crate's
    /// F1 test idiom so the CLI gate path is exercised without `gh`.
    struct StubResolver(Visibility);
    impl VisibilityResolver for StubResolver {
        fn visibility(&self, _slug: &str) -> Visibility {
            self.0
        }
    }

    // F1: the gate's BLOCKED diagnostic is a render path. A blocked private PR
    // must surface only the redacted opaque node id in the reason, never the raw
    // owner/repo:path. This locks the contract that run_gate builds its
    // GatePrStatus labels via `redacted_label`, not raw `slug_and_path`.
    #[test]
    fn gate_blocked_reason_redacts_private_pr_label() {
        let reference =
            parse_cross_repo_ref("acme/secret-repo:docs/plans/PLAN-classified.md").unwrap();
        let resolver = StubResolver(Visibility::Private);
        let node_id = "pr-7";
        let label = redacted_label(&reference, 7, node_id, &resolver);

        // An unmerged (blocked) private PR feeds the decision core.
        let pr_statuses = vec![GatePrStatus {
            label: label.clone(),
            merged: false,
        }];
        let decision = decide_gate(&pr_statuses, &[]);

        match decision {
            GateDecision::Block(reasons) => {
                let joined = reasons.join("\n");
                assert!(
                    joined.contains(node_id),
                    "blocked reason must carry the opaque node id: {}",
                    joined
                );
                assert!(
                    !joined.contains("secret-repo"),
                    "private repo leaked in gate diagnostic: {}",
                    joined
                );
                assert!(
                    !joined.contains("PLAN-classified.md"),
                    "private path leaked in gate diagnostic: {}",
                    joined
                );
                assert!(
                    !joined.contains("acme"),
                    "private owner leaked in gate diagnostic: {}",
                    joined
                );
            }
            GateDecision::Pass => panic!("expected Block for an unmerged PR"),
        }
    }

    // The --visibility flag maps onto the coordination PR's own visibility:
    // only the literal `private` declares a private coordination PR; unset (and
    // anything else) is public, so forgetting the flag fails closed into the
    // strict public direction.
    #[test]
    fn coordination_pr_visibility_defaults_to_public() {
        assert_eq!(coordination_pr_visibility(""), Visibility::Public);
        assert_eq!(coordination_pr_visibility("public"), Visibility::Public);
        assert_eq!(coordination_pr_visibility("private"), Visibility::Private);
        // Case-insensitive on the private opt-in.
        assert_eq!(coordination_pr_visibility("PRIVATE"), Visibility::Private);
        // Any unrecognized value fails closed to public (strict direction).
        assert_eq!(coordination_pr_visibility("secret"), Visibility::Public);
    }

    // Front door: a public coordination PR indexing a private node is refused,
    // and the refusal reason carries only the F1-redacted opaque node id (never
    // the raw private slug). This locks that check_index_visibility builds its
    // labels via `redacted_label`.
    #[test]
    fn check_index_visibility_refuses_public_pr_indexing_private() {
        let private_ref =
            parse_cross_repo_ref("acme/secret-repo:docs/plans/PLAN-classified.md").unwrap();
        let resolver = StubResolver(Visibility::Private);
        let decision = check_index_visibility(Visibility::Public, &[(private_ref, 7)], &resolver);
        match decision {
            VisibilityGuardDecision::Refuse(reasons) => {
                let joined = reasons.join("\n");
                assert!(
                    joined.contains("pr-7"),
                    "refusal must carry the opaque node id: {}",
                    joined
                );
                assert!(
                    !joined.contains("secret-repo"),
                    "private repo leaked in refusal diagnostic: {}",
                    joined
                );
                assert!(
                    !joined.contains("acme"),
                    "private owner leaked in refusal diagnostic: {}",
                    joined
                );
                assert!(
                    !joined.contains("PLAN-classified.md"),
                    "private path leaked in refusal diagnostic: {}",
                    joined
                );
            }
            VisibilityGuardDecision::Allow => {
                panic!("public PR indexing a private node must be refused")
            }
        }
    }

    // Front door: a private coordination PR may index a private node (Private ->
    // Public is allowed, so a private coordination PR describes everything).
    #[test]
    fn check_index_visibility_allows_private_pr_indexing_private() {
        let private_ref =
            parse_cross_repo_ref("acme/secret-repo:docs/plans/PLAN-classified.md").unwrap();
        let resolver = StubResolver(Visibility::Private);
        let decision = check_index_visibility(Visibility::Private, &[(private_ref, 7)], &resolver);
        assert_eq!(decision, VisibilityGuardDecision::Allow);
    }

    // Front door: a public coordination PR indexing only public nodes is allowed.
    #[test]
    fn check_index_visibility_allows_public_pr_indexing_public() {
        let public_ref = parse_cross_repo_ref("tsukumogami/shirabe:docs/plans/PLAN-x.md").unwrap();
        let resolver = StubResolver(Visibility::Public);
        let decision = check_index_visibility(Visibility::Public, &[(public_ref, 196)], &resolver);
        assert_eq!(decision, VisibilityGuardDecision::Allow);
    }

    // F1 public counterpart: a public blocked PR keeps its full ref in the
    // diagnostic (public refs are themselves public).
    #[test]
    fn gate_blocked_reason_shows_public_pr_label() {
        let reference = parse_cross_repo_ref("tsukumogami/shirabe:docs/plans/PLAN-x.md").unwrap();
        let resolver = StubResolver(Visibility::Public);
        let label = redacted_label(&reference, 196, "pr-196", &resolver);
        let pr_statuses = vec![GatePrStatus {
            label,
            merged: false,
        }];
        match decide_gate(&pr_statuses, &[]) {
            GateDecision::Block(reasons) => {
                let joined = reasons.join("\n");
                assert!(
                    joined.contains("tsukumogami/shirabe:docs/plans/PLAN-x.md#196"),
                    "public ref should appear in the diagnostic: {}",
                    joined
                );
            }
            GateDecision::Pass => panic!("expected Block for an unmerged PR"),
        }
    }
}
