//! `shirabe coordination` -- the coordinated multi-repo subcommand.
//!
//! Spine of the coordinated capability. Three verbs:
//!
//! - `create` -- renders the seed coordination-PR body (declaration, artifact
//!   chain, PR-index, fenced merge-order block) from the supplied artifact
//!   chain and prints it.
//! - `status` -- reads one indexed PR's reference, validates the
//!   `owner/repo:path` with the F2 parser, resolves the repo's visibility via
//!   the `gh` client (fail-closed to private when unresolvable), reads the PR's
//!   merged/open state through the `gh.rs` issue client, and renders one
//!   PR-index line with F1 redaction applied.
//! - `sync` -- re-reads every indexed PR live (read-only, F5), recomputes each
//!   node's merge state (F4) and visibility (F1, fail-closed), and re-renders
//!   the merge-time canonical coordination-PR body.
//!
//! The merge-last gate and the upstream-terminal verification that used to live
//! here as the `gate`/`verify` verbs are now the posture-aware
//! `shirabe validate --merge-gate` mode -- a validate mode like every other
//! merge-gating check. Its live-resolution glue lives in
//! `shirabe_validate::merge_gate`.
//!
//! The contract these verbs bind to lives in
//! `references/coordination-strategy.md`. No prose is restated here.

use std::process::ExitCode;

use shirabe_validate::{
    check_index_visibility, coordination_pr_visibility, parse_cross_repo_ref, render_index_line,
    render_sync_body, seed_body, split_pr_arg, ClientError, CrossRepoRef, GhSubprocessClient,
    GhVisibilityResolver, IndexedPr, IssueState, IssueStateClient, SeedInputs,
    VisibilityGuardDecision,
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
    ///
    /// The merge-last gate and the upstream-terminal verification that used to
    /// live here as the `gate`/`verify` verbs are now the posture-aware
    /// `shirabe validate --merge-gate` mode — a validate mode like every other
    /// merge-gating check. See `references/coordination-strategy.md`.
    Sync(SyncArgs),
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

/// Entry point dispatched from `main.rs`.
pub fn run(args: &CoordinationArgs) -> ExitCode {
    match &args.command {
        CoordinationCommands::Create(c) => run_create(c),
        CoordinationCommands::Status(s) => run_status(s),
        CoordinationCommands::Sync(s) => run_sync(s),
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
    let resolver = GhVisibilityResolver::new(&client);
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
    let resolver = GhVisibilityResolver::new(&client);

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

// The gate/verify logic and its F1/visibility tests moved with the merge-last
// gate into `shirabe_validate::merge_gate` (the live-resolution glue and its
// `MergeGateOutcome` tests) and `shirabe_validate::coordination` (the pure
// `decide_gate`/`decide_visibility_guard`/`redacted_label` cores). The
// `--merge-gate` validate mode is covered end-to-end by the binary integration
// tests in `tests/coordination_merge_gate.rs`. The `create`/`status`/`sync`
// verbs that remain here lean on the pure render cores' own tests.
