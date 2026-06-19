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
    parse_cross_repo_ref, render_index_line, render_sync_body, seed_body,
    verify_cross_repo_upstream_terminal, ClientError, GhSubprocessClient, IndexedPr, IssueState,
    IssueStateClient, SeedInputs, Visibility, VisibilityResolver,
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

/// Entry point dispatched from `main.rs`.
pub fn run(args: &CoordinationArgs) -> ExitCode {
    match &args.command {
        CoordinationCommands::Create(c) => run_create(c),
        CoordinationCommands::Status(s) => run_status(s),
        CoordinationCommands::Sync(s) => run_sync(s),
        CoordinationCommands::Verify(v) => run_verify(v),
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

    let mut indexed: Vec<IndexedPr> = Vec::with_capacity(args.prs.len());
    for raw in &args.prs {
        // Split the `#number` suffix off the durable `owner/repo:path` reference.
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
    match verify_cross_repo_upstream_terminal(&args.reference, args.number, &client) {
        Ok(v) => {
            println!(
                "coordination verify: {}:{}#{} is terminal (verified read-only)",
                v.slug, v.path, v.number
            );
            ExitCode::SUCCESS
        }
        Err(e) => {
            eprintln!("coordination verify: {}", e);
            ExitCode::from(1)
        }
    }
}
