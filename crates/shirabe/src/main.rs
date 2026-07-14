//! The `shirabe` command-line binary.
//!
//! Thin CLI shell over the `shirabe-validate` library: it parses arguments
//! with clap (mirroring the Go cobra surface), reads the optional
//! `--custom-statuses` YAML map, then for each path detects the format,
//! parses the doc, runs the validator, and prints GitHub Actions workflow
//! commands. The control flow mirrors the Go `cmd/shirabe/main.go`
//! one-for-one so the stdout bytes and exit code stay identical.

use std::collections::HashMap;
use std::process::ExitCode;

use clap::{CommandFactory, Parser, Subcommand};
use saphyr::{LoadableYamlNode, Yaml};
use shirabe_validate::{
    check_coordination_body, check_pr_body, check_slug_prefix, detect_format, detect_pr_draft,
    explain_advisory, format_error, format_notice, is_known_check_code, is_notice, parse_doc,
    render_human_with_advisory, render_json_with_advisory, resolve_doc_visibility,
    run_lifecycle_chain_check, run_lifecycle_check, run_merge_gate, run_transition, validate_file,
    walk_chain_mode, AdvisoryReport, Config, Flags, GhSubprocessClient, GhVisibilityResolver,
    MergeGateOutcome, Mode, ParseError, PrPosture, ReviewPosture, SlugPrefixCheck, ValidationError,
};

mod populate;
mod pr_body_hook;
mod work_summary;

/// The maximum accepted size of the `--custom-statuses` value, matching the
/// Go binary's 64 KiB guard.
const MAX_CUSTOM_STATUSES_BYTES: usize = 64 * 1024;

/// Top-level CLI. `name = "shirabe"` keeps `--version` printing
/// `shirabe <version>`, matching the Go version template
/// `"shirabe {{.Version}}\n"` byte-for-byte.
///
//
// A bare `shirabe` (no subcommand) prints the long help to STDOUT and exits
// 0, matching cobra's bare-command behavior rather than clap's default
// usage-error-to-stderr / exit 2. This is handled in `main` by detecting
// the `None` subcommand (the subcommand is optional) and printing help
// explicitly — `arg_required_else_help` is intentionally left off because
// it exits with an error code. A plain `//` block (not `///`) keeps this
// rationale out of the generated `--help` text.
#[derive(Parser)]
#[command(
    name = "shirabe",
    about = "Workflow skills for AI coding agents",
    version = env!("SHIRABE_VERSION"),
    disable_version_flag = true
)]
struct Cli {
    /// Print version (`shirabe <version>`) and exit. Bound to `-v`
    /// (lowercase) only, matching cobra, which binds `-v` to version and
    /// rejects `-V`. clap's conventional `-V` is deliberately NOT bound, so
    /// `shirabe -V` errors out like the Go binary does.
    #[arg(short = 'v', long = "version", action = clap::ArgAction::Version)]
    version: (),

    #[command(subcommand)]
    command: Option<Commands>,
}

#[derive(Subcommand)]
enum Commands {
    /// Validate shirabe doc files.
    Validate(ValidateArgs),
    /// Roadmap-scoped subcommands.
    Roadmap(RoadmapArgs),
    /// Transition a shirabe doc to a new status.
    Transition(TransitionArgs),
    /// Walk a finished PLAN's upstream chain and apply each tactical node's
    /// terminal transition (Design->Current, PRD->Done, Brief->Done), stripping
    /// a DESIGN's Implementation Issues section first. Use `--dry-run` to report
    /// without mutating. The PLAN is reported for deletion, never removed.
    FinalizeChain(FinalizeChainArgs),
    /// Detect whether a candidate slug conforms to the workspace's
    /// existing slug-prefix convention. Samples `docs/{briefs,prds,designs,plans}/`
    /// filenames, extracts the most common first hyphen-delimited word
    /// after the artifact-type prefix, and reports the result.
    SlugPrefixDetect(SlugPrefixDetectArgs),
    /// Install a local git pre-commit hook that runs `shirabe validate` over
    /// the staged documents at commit time. Safe by default: an existing
    /// pre-commit hook is left untouched and reported unless `--force` is
    /// given.
    InstallHooks(InstallHooksArgs),
    /// Session "work in flight" summary component: capture PR identity from
    /// `gh pr create` output into a private per-session ledger, gate
    /// emissions, and render the standardized work-in-flight block. Backs
    /// both the ambient dot-niwa hooks (`capture`/`absence`/`compact`, which
    /// emit hook JSON) and the `/inflight` skill (`render`, which prints the
    /// plain block). Every subcommand exits 0 (fail-safe).
    WorkSummary(work_summary::WorkSummaryArgs),
    /// Client-side PreToolUse hook: gate a `gh pr create` / `gh pr edit`
    /// command against the mechanical PR-body rule
    /// (references/pr-body-conformance.md) before it runs. Reads a Claude Code
    /// hook JSON on stdin, reuses the `validate --pr-body` engine, and emits a
    /// PreToolUse `deny` decision naming the findings — or nothing (allow) when
    /// the body/title is clean or cannot be confidently extracted. Fail-safe:
    /// always exits 0. Registered via dot-niwa; the CI `pr-body.yml` gate is
    /// the authoritative backstop.
    PrBodyHook,
}

#[derive(clap::Args)]
struct RoadmapArgs {
    #[command(subcommand)]
    command: RoadmapCommands,
}

#[derive(Subcommand)]
enum RoadmapCommands {
    /// Populate a roadmap's reserved Implementation Issues and Dependency
    /// Graph sections, creating one GitHub issue per feature. Pass
    /// `--no-issues` for the issueless render mode (feature-keyed table and
    /// `F<n>` diagram from feature context, no GitHub calls).
    Populate(populate::PopulateArgs),
}

#[derive(clap::Args)]
struct TransitionArgs {
    /// Path to the doc to transition.
    file: String,

    /// Target status (canonical name; multi-word values like "In Progress"
    /// must be quoted).
    status: String,

    /// Doc path for a supersession (design Superseded, vision Sunset).
    #[arg(long)]
    superseded_by: Option<String>,

    /// Free-text reason for a sunset (strategy Sunset).
    #[arg(long)]
    reason: Option<String>,
}

#[derive(clap::Args)]
struct FinalizeChainArgs {
    /// Path to the completed PLAN doc whose upstream chain to walk.
    plan: String,

    /// Report the terminal action each node would take without mutating any
    /// document. The default (omitted) applies each tactical transition.
    #[arg(long)]
    dry_run: bool,
}

#[derive(clap::Args)]
struct SlugPrefixDetectArgs {
    /// The candidate slug to check (e.g. `pattern-v1-ergonomics`).
    slug: String,

    /// The docs directory root to sample (default: `docs`). The sampler
    /// reads `<docs-root>/{briefs,prds,designs,plans}/` for existing
    /// artifact filenames.
    #[arg(long, default_value = "docs")]
    docs_root: String,
}

#[derive(clap::Args)]
struct InstallHooksArgs {
    /// Overwrite an existing pre-commit hook instead of leaving it in place
    /// and reporting the collision.
    #[arg(long)]
    force: bool,
}

/// The output mode for `validate` results.
///
/// `annotation` is the default and its bytes are frozen for CI parity; it
/// is the GitHub Actions workflow-command format the reusable CI workflow
/// already consumes. `json` emits the versioned `shirabe-validate/v1`
/// envelope for programmatic consumers (the skills). `human` emits a
/// terminal-shaped summary.
#[derive(Clone, Copy, PartialEq, Eq, clap::ValueEnum)]
enum Format {
    Annotation,
    Json,
    Human,
}

/// The `--mode` value for `validate`: the review posture a lifecycle run
/// asserts. `draft` is the in-flight posture (the default); `ready` is the
/// review-ready posture (the successor of the deprecated `--strict`).
#[derive(Clone, Copy, PartialEq, Eq, clap::ValueEnum)]
enum PostureMode {
    Draft,
    Ready,
}

impl PostureMode {
    fn to_review_posture(self) -> ReviewPosture {
        match self {
            PostureMode::Draft => ReviewPosture::Draft,
            PostureMode::Ready => ReviewPosture::Ready,
        }
    }
}

#[derive(clap::Args)]
struct ValidateArgs {
    /// Files to validate.
    files: Vec<String>,

    /// Output mode: `annotation` (default; GitHub Actions workflow commands,
    /// byte-stable for CI), `json` (the versioned `shirabe-validate/v1`
    /// envelope), or `human` (terminal-shaped summary). The default is
    /// `annotation` so existing CI invocations are unchanged.
    #[arg(long, value_enum, default_value_t = Format::Annotation)]
    format: Format,

    /// Run only the named check(s) instead of the full applicable pass.
    /// Repeatable and comma-splittable (e.g. `--check FC01 --check R7` or
    /// `--check FC01,R7`). Codes are the per-file checks: `SCHEMA`,
    /// `FC01`-`FC13`, `FC-CONVENTIONS`, `R6`-`R9`. An unknown code is a tool
    /// error. A valid but format-inapplicable code is a clean no-op.
    #[arg(long, value_delimiter = ',')]
    check: Vec<String>,

    /// Visibility context; only 'private' bypasses public-repo checks
    /// (R7/R8/R9). When unset, visibility is auto-detected per file from the
    /// doc's owning repo the same way the shirabe skills detect it: read the
    /// repo's `CLAUDE.md`/`CLAUDE.local.md` `## Repo Visibility:` header, else
    /// infer from the path (`private`/`public` component), else default to
    /// 'private'. Passing the flag overrides detection for every file.
    #[arg(long, default_value = "")]
    visibility: String,

    /// YAML map of schema version to valid status list.
    #[arg(long, default_value = "")]
    custom_statuses: String,

    /// Chain-aware passing-state lifecycle mode. Walks the doc tree under
    /// the given root, identifies artifact chains via inverse `upstream:`
    /// traversal, and verifies every chain member is at its passing
    /// state for the chain's posture. Mutually exclusive with positional
    /// file arguments.
    #[arg(long, value_name = "ROOT")]
    lifecycle: Option<String>,

    /// Review posture for `--lifecycle` / `--lifecycle-chain`. `draft`
    /// (the default) is the in-flight posture: the single-pr-mid-PR
    /// exemption applies, so a present single-pr PLAN and single-pr
    /// BRIEF/PRD at Accepted pass. `ready` is the review-ready posture:
    /// the exemption is disabled, so a present single-pr PLAN fails and
    /// single-pr BRIEF/PRD at Accepted fail. Multi-pr postures are
    /// unchanged by the mode. The CI workflow asserts `ready` only when
    /// the PR is ready-for-review (`github.event.pull_request.draft ==
    /// false`); otherwise the default `draft` applies.
    #[arg(long, value_enum, default_value_t = PostureMode::Draft)]
    mode: PostureMode,

    /// Deprecated alias for `--mode=ready`. Hidden; retained for one
    /// migration window so unmigrated callers keep working. When set it
    /// resolves the posture to `ready` and prints a one-line deprecation
    /// notice to stderr. Precedence: `--strict` present wins (resolves to
    /// `ready`); otherwise the `--mode` value applies.
    #[arg(long, hide = true, default_value_t = false)]
    strict: bool,

    /// Chain-targeted lifecycle mode. Takes a doc-in-a-chain (PLAN,
    /// DESIGN, PRD, BRIEF, or ROADMAP) and validates only the chain
    /// containing that doc. Mutually exclusive with `--lifecycle` and
    /// with positional file arguments. Works with `--mode`. The
    /// work-on cascade script uses this mode to verify its own chain's
    /// posture without surfacing unrelated drift as noise.
    #[arg(long, value_name = "DOC")]
    lifecycle_chain: Option<String>,

    /// Suppress the L06 outline-AC completeness check. Default off.
    /// Applies to both `--lifecycle` and `--lifecycle-chain` modes.
    /// L01-L05 are unaffected — only L06 honors this flag. Use when an
    /// outline AC is satisfied by upstream work not in this PR and the
    /// author has signed off on the gap. The work-on cascade script
    /// forwards the env var `WORK_ON_ALLOW_UNTRACKED_ACS=1` by adding
    /// this flag to its validator invocations.
    #[arg(long, default_value_t = false)]
    allow_untracked_acs: bool,

    /// The coordination merge-last gate mode (F4 / Decision D). Recompute
    /// "all indexed PRs merged + all upstreams terminal" from authoritative
    /// **live** `gh` queries at gate time, never from the editable PR body.
    /// Posture-aware, mirroring the draft-tolerable lifecycle codes: under
    /// `--mode=ready` a blocked gate fails (the merge-last backstop); under
    /// `--mode=draft` (the default) a blocked gate is a notice (exit 0), since
    /// a coordination PR legitimately has unmerged indexed PRs mid-effort.
    /// Mutually exclusive with `--lifecycle` / `--lifecycle-chain` and with
    /// positional file arguments. Takes the indexed PR refs via `--pr` and
    /// upstreams via `--upstream`; honors `--visibility` (unset == public,
    /// only `private` opts a private effort in, fail-closed otherwise).
    #[arg(
        long,
        default_value_t = false,
        conflicts_with = "lifecycle",
        conflicts_with = "lifecycle_chain"
    )]
    merge_gate: bool,

    /// An indexed PR for `--merge-gate`, given as `owner/repo:path#number`
    /// (repeatable). The supplied LIST is the durable index; per-PR merged
    /// status is **never** trusted from this argument or any PR body — it is
    /// recomputed live via `gh` (F4). The `owner/repo:path` is validated by
    /// the F2 parser; a malformed reference is a hard input error.
    #[arg(long = "pr")]
    pr: Vec<String>,

    /// An upstream to verify terminal for `--merge-gate`, given as
    /// `owner/repo:path#number` (repeatable). Each is checked live; a
    /// non-terminal or unresolvable upstream blocks the gate (fail closed).
    #[arg(long = "upstream")]
    upstream: Vec<String>,

    /// The static coordination-body check mode. Reads an authored coordination
    /// PR body FILE and checks it **offline** (no `gh`): the declaration marker
    /// is present, every `owner/repo:path#number` cross-repo ref parses and
    /// passes F2, and the fenced merge-order block is acyclic. This is the
    /// static analog of `shirabe validate <brief-file>` — authoring feedback
    /// before the body is posted. The visibility rule and live merge state need
    /// `gh` and stay in `--merge-gate`; they are not duplicated here. Mutually
    /// exclusive with `--lifecycle` / `--lifecycle-chain` / `--merge-gate` and
    /// with positional file arguments.
    #[arg(
        long,
        value_name = "FILE",
        conflicts_with = "lifecycle",
        conflicts_with = "lifecycle_chain",
        conflicts_with = "merge_gate"
    )]
    coordination_body: Option<String>,

    /// The static PR-body check mode. Reads an authored pull-request body from
    /// FILE and checks the mechanical, objectively-decidable parts of the
    /// two-part squash-merge convention **offline** (no `gh`): exactly one
    /// top-level `---` separator with a non-empty Part 1, and no AI-attribution
    /// / co-author footer. Pair with `--pr-title` to also check the title is
    /// Conventional Commits. Subjective Part 2 section selection stays advisory
    /// and is not gated. This is the static analog of `--coordination-body` for
    /// a PR body — the single source both CI and the authoring skills consume
    /// (see references/pr-body-conformance.md). Mutually exclusive with
    /// `--lifecycle` / `--lifecycle-chain` / `--merge-gate` /
    /// `--coordination-body` and with positional file arguments. The
    /// `conflicts_with` for `coordination_body` is declared here explicitly:
    /// clap needs the edge on the new field, not only on the old one.
    #[arg(
        long,
        value_name = "FILE",
        conflicts_with = "lifecycle",
        conflicts_with = "lifecycle_chain",
        conflicts_with = "merge_gate",
        conflicts_with = "coordination_body"
    )]
    pr_body: Option<String>,

    /// The PR title to check under `--pr-body` (PB1, Conventional Commits).
    /// Only meaningful with `--pr-body`; supplying it without `--pr-body` is a
    /// hard input error. When omitted, `--pr-body` checks only the body-level
    /// rules so a caller can check a body-in-progress; the CI gate always
    /// supplies both.
    #[arg(long, value_name = "STRING", requires = "pr_body")]
    pr_title: Option<String>,
}

fn main() -> ExitCode {
    let cli = Cli::parse();
    match cli.command {
        Some(Commands::Validate(args)) => run_validate(&args),
        Some(Commands::Roadmap(args)) => match args.command {
            RoadmapCommands::Populate(p) => populate::run(&p),
        },
        Some(Commands::Transition(args)) => run_transition_cmd(&args),
        Some(Commands::FinalizeChain(args)) => run_finalize_chain_cmd(&args),
        Some(Commands::SlugPrefixDetect(args)) => run_slug_prefix_detect(&args),
        Some(Commands::InstallHooks(args)) => run_install_hooks_cmd(&args),
        Some(Commands::WorkSummary(args)) => work_summary::run(&args.command),
        Some(Commands::PrBodyHook) => pr_body_hook::run(),
        // Bare invocation: print the long help to stdout and exit 0,
        // matching cobra's behavior for a command with no `Run`. clap would
        // otherwise leave `command` as `None` and exit 0 silently.
        None => {
            let mut cmd = Cli::command();
            // Ignore a write failure (e.g. closed stdout) -- the exit code
            // is the contract, and cobra likewise doesn't fail on it.
            let _ = cmd.print_long_help();
            println!();
            ExitCode::SUCCESS
        }
    }
}

/// The outcome of a `validate` run, mapped to the multi-level exit-code
/// contract shared with `transition` and `finalize-chain`: `0` clean,
/// `1` tool-error, `2` violations found, `3` I/O error.
///
/// Severity ordering (used for most-severe-wins across multiple documents)
/// is deliberately distinct from the exit integer: a tool-error outranks a
/// violation in severity yet maps to the lower exit code `1`, exactly as the
/// sibling commands do. This keeps one exit-code vocabulary across the CLI
/// while letting a multi-document run report its worst outcome.
#[derive(Clone, Copy, PartialEq, Eq)]
enum ValidateOutcome {
    Clean,
    Violations,
    ToolError,
    /// Exit code `3`. Reserved to complete the shared contract with
    /// `transition`/`finalize-chain`; `validate` only reads files and prints,
    /// so it does not currently emit an I/O failure, but the variant keeps the
    /// vocabulary identical across commands.
    #[allow(dead_code)]
    Io,
}

impl ValidateOutcome {
    /// Higher rank = more severe. Tool-error and I/O (the run could not
    /// complete) outrank a violation (the run completed but the rules said
    /// no), which outranks clean.
    fn severity_rank(self) -> u8 {
        match self {
            ValidateOutcome::Clean => 0,
            ValidateOutcome::Violations => 1,
            ValidateOutcome::ToolError => 2,
            ValidateOutcome::Io => 3,
        }
    }

    /// The exit integer, mirroring the `transition`/`finalize-chain` scheme.
    fn exit_code(self) -> u8 {
        match self {
            ValidateOutcome::Clean => 0,
            ValidateOutcome::ToolError => 1,
            ValidateOutcome::Violations => 2,
            ValidateOutcome::Io => 3,
        }
    }

    /// Keep whichever outcome is more severe.
    fn merge(self, other: ValidateOutcome) -> ValidateOutcome {
        if other.severity_rank() > self.severity_rank() {
            other
        } else {
            self
        }
    }

    fn exit(self) -> ExitCode {
        ExitCode::from(self.exit_code())
    }

    /// The outcome label used in the `json` and `human` summaries.
    fn label(self) -> &'static str {
        match self {
            ValidateOutcome::Clean => "clean",
            ValidateOutcome::Violations => "violations",
            ValidateOutcome::ToolError => "tool-error",
            ValidateOutcome::Io => "io",
        }
    }
}

/// Resolve the effective [`ReviewPosture`] from the `--strict` deprecated
/// flag and the `--mode` value. When `--strict` is set it wins (resolves to
/// `Ready`) and a one-line deprecation notice is printed to stderr;
/// otherwise the `--mode` value applies. Factored out so the precedence and
/// the deprecation notice are covered by a unit test.
fn resolve_posture(strict: bool, mode: PostureMode) -> ReviewPosture {
    if strict {
        eprintln!("warning: --strict is deprecated; use --mode=ready");
        return ReviewPosture::Ready;
    }
    mode.to_review_posture()
}

/// Runs the `validate` subcommand. Returns the multi-level exit code per
/// the `ValidateOutcome` contract: `0` clean, `1` tool-error (bad
/// invocation, unreadable or unparseable file), `2` violations found
/// (any error-level result), `3` I/O. Notice-level results never make a
/// run non-clean. Across multiple documents the most-severe outcome wins.
/// The annotation output bytes are unchanged from the prior behavior.
fn run_validate(args: &ValidateArgs) -> ExitCode {
    // The two lifecycle modes (whole-tree `--lifecycle <ROOT>` and
    // chain-targeted `--lifecycle-chain <DOC>`) and the per-file mode
    // (positional files) are mutually exclusive across the three
    // combinations.
    if args.lifecycle.is_some() && !args.files.is_empty() {
        eprintln!("--lifecycle is mutually exclusive with positional file arguments");
        return ValidateOutcome::ToolError.exit();
    }
    if args.lifecycle_chain.is_some() && !args.files.is_empty() {
        eprintln!("--lifecycle-chain is mutually exclusive with positional file arguments");
        return ValidateOutcome::ToolError.exit();
    }
    if args.lifecycle.is_some() && args.lifecycle_chain.is_some() {
        eprintln!("--lifecycle and --lifecycle-chain are mutually exclusive");
        return ValidateOutcome::ToolError.exit();
    }
    // The merge-gate mode is one validate mode: it cannot combine with the
    // lifecycle modes (clap already rejects those via `conflicts_with`) or with
    // positional file arguments.
    if args.merge_gate && !args.files.is_empty() {
        eprintln!("--merge-gate is mutually exclusive with positional file arguments");
        return ValidateOutcome::ToolError.exit();
    }
    // `--pr` / `--upstream` are only meaningful in merge-gate mode.
    if !args.merge_gate && (!args.pr.is_empty() || !args.upstream.is_empty()) {
        eprintln!("--pr and --upstream require --merge-gate");
        return ValidateOutcome::ToolError.exit();
    }
    // The static coordination-body check is its own mode: it cannot combine with
    // positional file arguments (clap already rejects the lifecycle/merge-gate
    // combinations via `conflicts_with`).
    if args.coordination_body.is_some() && !args.files.is_empty() {
        eprintln!("--coordination-body is mutually exclusive with positional file arguments");
        return ValidateOutcome::ToolError.exit();
    }
    // The static PR-body check is its own mode: it cannot combine with
    // positional file arguments (clap already rejects the lifecycle/merge-gate/
    // coordination-body combinations via `conflicts_with`).
    if args.pr_body.is_some() && !args.files.is_empty() {
        eprintln!("--pr-body is mutually exclusive with positional file arguments");
        return ValidateOutcome::ToolError.exit();
    }

    // Reject an unknown --check code up front: a typo like `FC1` must be a
    // tool error, not a silent clean pass. A valid but format-inapplicable
    // code is allowed here (it becomes a clean no-op once filtering runs).
    for code in &args.check {
        if !is_known_check_code(code) {
            eprintln!(
                "unknown --check code {:?}; valid codes: SCHEMA, FC01-FC13, FC-CONVENTIONS, R6-R9",
                code
            );
            return ValidateOutcome::ToolError.exit();
        }
    }

    // Resolve the effective review posture once. Precedence: the
    // deprecated `--strict` flag wins (resolves to Ready and emits a
    // one-line deprecation notice to stderr); otherwise the `--mode` value
    // applies (default Draft).
    let posture = resolve_posture(args.strict, args.mode);

    if let Some(file) = args.coordination_body.as_deref() {
        return run_coordination_body_mode(file, args.format);
    }

    if let Some(file) = args.pr_body.as_deref() {
        return run_pr_body_mode(file, args.pr_title.as_deref(), args.format);
    }

    if args.merge_gate {
        return run_merge_gate_mode(args, posture);
    }

    if let Some(root) = args.lifecycle.as_deref() {
        return run_lifecycle(
            root,
            &args.visibility,
            posture,
            args.allow_untracked_acs,
            args.format,
        );
    }

    if let Some(doc) = args.lifecycle_chain.as_deref() {
        return run_lifecycle_chain(
            doc,
            &args.visibility,
            posture,
            args.allow_untracked_acs,
            args.format,
        );
    }

    if args.files.is_empty() {
        return ValidateOutcome::Clean.exit();
    }

    let custom_statuses = match parse_custom_statuses(&args.custom_statuses) {
        Ok(map) => map,
        Err(msg) => {
            eprintln!("{}", msg);
            return ValidateOutcome::ToolError.exit();
        }
    };

    // An explicit `--visibility` overrides detection for every file; when the
    // flag is unset, visibility is resolved per file from the doc's owning repo
    // (CLAUDE.md `## Repo Visibility:` header, then path inference, then a
    // Private default). Per-file resolution is required because a single run can
    // span docs in repos of differing visibility.
    let explicit_visibility = if args.visibility.is_empty() {
        None
    } else {
        Some(args.visibility.clone())
    };

    // Collect every emitted finding across all files first, then render
    // once according to the chosen format. Annotation mode iterates the
    // findings in the same file-then-finding order the prior streaming code
    // used, so its output bytes are unchanged.
    let mut worst = ValidateOutcome::Clean;
    let mut findings: Vec<ValidationError> = Vec::new();
    for path in &args.files {
        let spec = match detect_format(basename(path)) {
            Some(s) => s,
            None => continue,
        };

        let doc = match parse_doc(path) {
            Ok(d) => d,
            Err(err) => {
                // An unreadable or unparseable input is a tool error: the
                // run could not complete for this file. Exit code 1, not a
                // violation.
                findings.push(ValidationError {
                    file: path.clone(),
                    line: 1,
                    code: "IO".to_string(),
                    message: format!("could not read file: {}", io_error_text(&err)),
                });
                worst = worst.merge(ValidateOutcome::ToolError);
                continue;
            }
        };

        let visibility = match &explicit_visibility {
            Some(v) => v.clone(),
            None => resolve_doc_visibility(std::path::Path::new(path)),
        };
        let cfg = Config {
            custom_statuses: custom_statuses.clone(),
            visibility,
            allow_untracked_acs: args.allow_untracked_acs,
        };

        for ve in validate_file(&doc, &spec, &cfg) {
            // When --check selects a subset, skip any finding whose code was
            // not requested: it is neither reported nor counted toward the
            // outcome (so selecting only a check that passes is a clean run,
            // even if an unselected check would have failed). The IO/parse
            // tool-error above is orthogonal and always surfaces.
            if !args.check.is_empty() && !args.check.iter().any(|c| c == &ve.code) {
                continue;
            }
            if !is_notice(&ve, posture) {
                worst = worst.merge(ValidateOutcome::Violations);
            }
            findings.push(ve);
        }
    }

    match args.format {
        Format::Annotation => {
            for ve in &findings {
                if is_notice(ve, posture) {
                    println!("{}", format_notice(&ve.file, &ve.message));
                } else {
                    println!("{}", format_error(ve));
                }
            }
        }
        Format::Json => {
            let advisory = compute_advisory(&findings, posture);
            print!(
                "{}",
                render_json_with_advisory(&findings, worst.label(), posture, Some(&advisory))
            )
        }
        Format::Human => {
            let advisory = compute_advisory(&findings, posture);
            print!(
                "{}",
                render_human_with_advisory(&findings, worst.label(), posture, Some(&advisory))
            )
        }
    }

    worst.exit()
}

/// Runs the `validate --merge-gate` mode: the coordination merge-last gate
/// (F4 / Decision D), folded into `validate` as a posture-aware mode like every
/// other merge-gating check. The live `gh` resolution and the pure decision
/// cores live in `shirabe_validate::merge_gate`; this fn owns the CLI shell —
/// the output text and the posture-aware exit code.
///
/// **Posture-aware outcome (mirrors `effective_severity` for a draft-tolerable
/// code):**
///
/// - `ReviewPosture::Ready`: a blocked gate is an error (exit 2) — the
///   merge-last backstop. A coordination PR is only mergeable when every
///   indexed PR is merged and every upstream terminal.
/// - `ReviewPosture::Draft`: a blocked gate is a **notice** (exit 0), because a
///   coordination PR legitimately has unmerged indexed PRs mid-effort — exactly
///   how `L02`/`L06`/`L07` resolve under draft.
///
/// A visibility-rule refusal and a hard input error are **posture-independent**:
/// a draft does not soften a visibility leak or a malformed reference. Both exit
/// non-zero in every posture (a refusal exits 2, an input error exits 1).
///
/// Output respects `--format`: `json` emits the versioned envelope, `human`/
/// `annotation` emit a clear message. F1 redaction is applied inside the
/// resolution (every cross-repo identifier is routed through `redacted_label`
/// before it reaches a diagnostic), so the strings this fn prints are already
/// safe. The `gh` reads are read-only (F5).
fn run_merge_gate_mode(args: &ValidateArgs, posture: ReviewPosture) -> ExitCode {
    let client = GhSubprocessClient::new();
    let resolver = GhVisibilityResolver::new(&client);
    let outcome = run_merge_gate(
        &args.pr,
        &args.upstream,
        &args.visibility,
        posture,
        &client,
        &resolver,
    );

    match &outcome {
        MergeGateOutcome::Pass {
            pr_count,
            upstream_count,
        } => print_merge_gate_line(
            args.format,
            "pass",
            &format!(
                "merge-gate: PASS ({} PR(s) merged, {} upstream(s) terminal; recomputed live)",
                pr_count, upstream_count
            ),
        ),
        MergeGateOutcome::InputError(msg) => {
            // A malformed reference or auth failure is a hard input error
            // (exit 1), posture-independent.
            eprintln!("merge-gate: {}", msg);
        }
        MergeGateOutcome::Refused(reasons) => {
            // The Coordination-PR Visibility Rule refusal is fail-closed in
            // every posture (a draft does not soften a visibility leak). The
            // reasons are already F1-redacted.
            print_merge_gate_block(
                args.format,
                "refused",
                "merge-gate: REFUSED (Coordination-PR Visibility Rule)",
                reasons,
            );
        }
        MergeGateOutcome::Blocked(reasons) => match posture {
            ReviewPosture::Ready => print_merge_gate_block(
                args.format,
                "violations",
                "merge-gate: BLOCKED (merge-last gate, recomputed live)",
                reasons,
            ),
            ReviewPosture::Draft => print_merge_gate_block(
                args.format,
                "notice",
                "merge-gate: notice (draft posture) — gate not yet satisfied",
                reasons,
            ),
        },
    }

    merge_gate_outcome(&outcome, posture).exit()
}

/// Runs the `validate --coordination-body <FILE>` mode: the static
/// authoring-feedback check over an authored coordination PR body, offline (no
/// `gh`). It is the static analog of `shirabe validate <brief-file>` — it tells
/// the author what to fix and why before the body is posted.
///
/// The pure check logic lives in `shirabe_validate::check_coordination_body`
/// (declaration marker present, every cross-repo ref passes F2, the merge-order
/// block is acyclic); this fn owns the CLI shell — reading the file, rendering
/// findings per `--format`, and the exit code. The mode is posture-independent:
/// any finding is a violation (exit 2). An unreadable file is a tool error
/// (exit 1).
///
/// The **visibility** rule and **live merge state** (F4) need `gh`, so they
/// stay in `--merge-gate` and are deliberately not checked here.
fn run_coordination_body_mode(file: &str, format: Format) -> ExitCode {
    let body = match std::fs::read_to_string(file) {
        Ok(b) => b,
        Err(err) => {
            eprintln!("--coordination-body: could not read {}: {}", file, err);
            return ValidateOutcome::ToolError.exit();
        }
    };

    let findings = check_coordination_body(&body);
    let outcome = if findings.is_empty() {
        ValidateOutcome::Clean
    } else {
        ValidateOutcome::Violations
    };

    match format {
        Format::Json => {
            let items: Vec<String> = findings
                .iter()
                .map(|f| {
                    format!(
                        "{{\"line\":{},\"message\":{}}}",
                        f.line,
                        json_string(&f.message)
                    )
                })
                .collect();
            println!(
                "{{\"schema\":\"shirabe-coordination-body/v1\",\"outcome\":{},\"findings\":[{}]}}",
                json_string(outcome.label()),
                items.join(",")
            );
        }
        Format::Annotation => {
            // GitHub Actions error annotations, file-scoped.
            for f in &findings {
                println!("::error file={},line={}::{}", file, f.line, f.message);
            }
        }
        Format::Human => {
            if findings.is_empty() {
                println!("coordination-body: clean ({})", file);
            } else {
                eprintln!(
                    "coordination-body: {} finding(s) in {}",
                    findings.len(),
                    file
                );
                for f in &findings {
                    eprintln!("  - {}:{}: {}", file, f.line, f.message);
                }
            }
        }
    }

    outcome.exit()
}

/// Runs the static `--pr-body` check mode. Reads the PR body from `file`,
/// checks it (and the optional `title`) offline via
/// [`check_pr_body`](shirabe_validate::check_pr_body), and renders findings
/// through the same exit-code contract and formats as
/// `run_coordination_body_mode`. The `annotation` arm emits the **fileless**
/// `::error::` form because the body lives in a temp file with no path in the
/// checked-out tree — a file-anchored annotation would point at a nonexistent
/// source line.
fn run_pr_body_mode(file: &str, title: Option<&str>, format: Format) -> ExitCode {
    let body = match std::fs::read_to_string(file) {
        Ok(b) => b,
        Err(err) => {
            eprintln!("--pr-body: could not read {}: {}", file, err);
            return ValidateOutcome::ToolError.exit();
        }
    };

    let findings = check_pr_body(&body, title);
    let outcome = if findings.is_empty() {
        ValidateOutcome::Clean
    } else {
        ValidateOutcome::Violations
    };

    match format {
        Format::Json => {
            let items: Vec<String> = findings
                .iter()
                .map(|f| {
                    format!(
                        "{{\"line\":{},\"message\":{}}}",
                        f.line,
                        json_string(&f.message)
                    )
                })
                .collect();
            println!(
                "{{\"schema\":\"shirabe-pr-body/v1\",\"outcome\":{},\"findings\":[{}]}}",
                json_string(outcome.label()),
                items.join(",")
            );
        }
        Format::Annotation => {
            // GitHub Actions error annotations. Fileless: the body is a temp
            // file with no path in the checked-out tree, so a file-anchored
            // annotation would float against a nonexistent source line.
            for f in &findings {
                println!("::error::{}", f.message);
            }
        }
        Format::Human => {
            if findings.is_empty() {
                println!("pr-body: clean ({})", file);
            } else {
                eprintln!("pr-body: {} finding(s) in {}", findings.len(), file);
                for f in &findings {
                    eprintln!("  - {}:{}: {}", file, f.line, f.message);
                }
            }
        }
    }

    outcome.exit()
}

/// Map a [`MergeGateOutcome`] and review posture onto the shared
/// [`ValidateOutcome`] exit-code contract. This is the posture-aware decision
/// point, factored out so the draft-vs-ready matrix is unit-tested without
/// needing a live `gh`:
///
/// - `Pass` => `Clean` (exit 0) in every posture.
/// - `InputError` => `ToolError` (exit 1) in every posture (hard input error).
/// - `Refused` => `Violations` (exit 2) in every posture — the
///   Coordination-PR Visibility Rule is fail-closed; a draft does not soften a
///   visibility leak.
/// - `Blocked` => posture-aware, mirroring `effective_severity` for a
///   draft-tolerable code: `Ready` => `Violations` (exit 2, the merge-last
///   backstop); `Draft` => `Clean` (exit 0, a notice).
fn merge_gate_outcome(outcome: &MergeGateOutcome, posture: ReviewPosture) -> ValidateOutcome {
    match outcome {
        MergeGateOutcome::Pass { .. } => ValidateOutcome::Clean,
        MergeGateOutcome::InputError(_) => ValidateOutcome::ToolError,
        MergeGateOutcome::Refused(_) => ValidateOutcome::Violations,
        MergeGateOutcome::Blocked(_) => match posture {
            ReviewPosture::Ready => ValidateOutcome::Violations,
            ReviewPosture::Draft => ValidateOutcome::Clean,
        },
    }
}

/// Print a single merge-gate result line per `format`. For `json` it emits a
/// minimal versioned envelope; otherwise the human/annotation message.
fn print_merge_gate_line(format: Format, outcome: &str, message: &str) {
    match format {
        Format::Json => println!(
            "{{\"schema\":\"shirabe-merge-gate/v1\",\"outcome\":{},\"reasons\":[]}}",
            json_string(outcome)
        ),
        Format::Annotation | Format::Human => println!("{}", message),
    }
}

/// Print a merge-gate block result (refusal / block / notice) with its reasons
/// per `format`. For `json` the reasons are carried as a string array; for
/// human/annotation each reason is printed on its own line.
fn print_merge_gate_block(format: Format, outcome: &str, header: &str, reasons: &[String]) {
    match format {
        Format::Json => {
            let items: Vec<String> = reasons.iter().map(|r| json_string(r)).collect();
            println!(
                "{{\"schema\":\"shirabe-merge-gate/v1\",\"outcome\":{},\"reasons\":[{}]}}",
                json_string(outcome),
                items.join(",")
            );
        }
        Format::Annotation | Format::Human => {
            eprintln!("{}:", header);
            for reason in reasons {
                eprintln!("  - {}", reason);
            }
        }
    }
}

/// Minimal JSON string encoder for the merge-gate envelope: quote and escape
/// the control characters JSON requires. The strings here are already
/// F1-redacted, so this only needs to produce valid JSON, not redact.
fn json_string(s: &str) -> String {
    let mut out = String::with_capacity(s.len() + 2);
    out.push('"');
    for ch in s.chars() {
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

/// Build the context-aware advisory for a render. The advisory is read-only
/// with respect to the verdict (the advisory-never-gates invariant): the PR
/// context it reads (`detect_pr_draft`, a typed `draft` bit from
/// `GITHUB_EVENT_PATH`) feeds *phrasing only* and never the exit code or any
/// existing JSON verdict field. The read is hermetic (a local file, no
/// network) and degrades to no-PR phrasing when the signal is absent.
///
/// Annotation mode does not render an advisory (its bytes are frozen for CI
/// parity), so this is only called for the JSON and human formats.
fn compute_advisory(findings: &[ValidationError], posture: ReviewPosture) -> AdvisoryReport {
    let pr = PrPosture::from_draft_bit(detect_pr_draft());
    explain_advisory(findings, posture, pr)
}

/// Runs the chain-aware passing-state lifecycle check against `root`.
/// Emits one annotation per failure to stdout and returns a non-zero
/// exit code if any failures were emitted.
///
/// Under `ReviewPosture::Ready`, the single-pr-mid-PR exemption is
/// disabled: a single-pr PLAN present in the tree fails (regardless of its
/// `status:` value) and single-pr BRIEF/PRD at Accepted fail. Multi-pr
/// postures are unchanged by the posture.
///
/// The findings are collected into a `Vec` and rendered once by
/// [`render_lifecycle`] per the chosen [`Format`], mirroring `run_validate`.
fn run_lifecycle(
    root: &str,
    visibility: &str,
    posture: ReviewPosture,
    allow_untracked_acs: bool,
    format: Format,
) -> ExitCode {
    let cfg = Config {
        custom_statuses: HashMap::new(),
        visibility: visibility.to_string(),
        allow_untracked_acs,
    };
    let root_path = std::path::Path::new(root);
    if !root_path.exists() {
        eprintln!("--lifecycle root {} does not exist", root);
        return ValidateOutcome::ToolError.exit();
    }
    let findings = run_lifecycle_check(root_path, &cfg, posture);
    render_lifecycle(&findings, format, posture)
}

/// Render a lifecycle mode's collected findings once by `format` and return
/// the run's exit code. Shared by [`run_lifecycle`] and
/// [`run_lifecycle_chain`]; factored out so the two modes render identically.
///
/// The `worst` outcome is accumulated the same way the streaming code did:
/// a notice (per [`is_notice`], resolved under `posture`) never bumps the
/// run to `Violations`, so a run carrying only notices stays clean (exit
/// 0). In `Annotation` mode the per-finding `format_error`/`format_notice`
/// loop runs in the original finding order, so its output bytes are
/// unchanged.
fn render_lifecycle(
    findings: &[ValidationError],
    format: Format,
    posture: ReviewPosture,
) -> ExitCode {
    let mut worst = ValidateOutcome::Clean;
    for ve in findings {
        if !is_notice(ve, posture) {
            worst = worst.merge(ValidateOutcome::Violations);
        }
    }

    match format {
        Format::Annotation => {
            for ve in findings {
                if is_notice(ve, posture) {
                    println!("{}", format_notice(&ve.file, &ve.message));
                } else {
                    println!("{}", format_error(ve));
                }
            }
        }
        Format::Json => {
            let advisory = compute_advisory(findings, posture);
            print!(
                "{}",
                render_json_with_advisory(findings, worst.label(), posture, Some(&advisory))
            )
        }
        Format::Human => {
            let advisory = compute_advisory(findings, posture);
            print!(
                "{}",
                render_human_with_advisory(findings, worst.label(), posture, Some(&advisory))
            )
        }
    }

    worst.exit()
}

/// Runs the `slug-prefix-detect` subcommand. Samples the docs corpus
/// for existing artifact filenames and reports whether the candidate
/// slug conforms to the prevailing prefix convention. Used by /scope
/// Phase 0 to surface a slug-shape recommendation before authoring.
///
/// Output is a single line on stdout describing the result; exit code
/// is 0 in every non-error case (mismatch is informational, not a
/// failure). The advisory shape mirrors FC07/FC08/FC09 notice-level
/// behavior: the validator names the drift but does not block.
fn run_slug_prefix_detect(args: &SlugPrefixDetectArgs) -> ExitCode {
    match check_slug_prefix(&args.docs_root, &args.slug) {
        SlugPrefixCheck::NoPrevailingPrefix => {
            println!(
                "no-prevailing-prefix: sampled docs corpus under {:?} did not produce a >50% prefix majority",
                args.docs_root
            );
        }
        SlugPrefixCheck::Matches { prefix } => {
            println!(
                "matches: candidate slug {:?} starts with the detected prefix {:?}",
                args.slug, prefix
            );
        }
        SlugPrefixCheck::Mismatch { prefix, slug } => {
            println!(
                "mismatch: candidate slug {:?} does not start with the detected prefix {:?}; consider {}-{}",
                slug, prefix, prefix, slug
            );
        }
    }
    ExitCode::SUCCESS
}

/// Runs the chain-targeted lifecycle check against the chain
/// containing `doc_path`. Emits one annotation per failure to stdout
/// and returns a non-zero exit code if any failures were emitted.
///
/// Mirrors `run_lifecycle`'s shape but invokes
/// `run_lifecycle_chain_check`. The posture has the same behavior: under
/// `ReviewPosture::Ready` the single-pr-mid-PR exemption is disabled for
/// the matched chain; multi-pr postures are unchanged.
///
/// Used by the work-on cascade script in
/// `skills/work-on/scripts/run-cascade.sh` for the pre-cascade probe
/// and post-cascade verification points.
///
/// The findings are collected into a `Vec` and rendered once by
/// [`render_lifecycle`] per the chosen [`Format`], mirroring `run_validate`.
fn run_lifecycle_chain(
    doc_path: &str,
    visibility: &str,
    posture: ReviewPosture,
    allow_untracked_acs: bool,
    format: Format,
) -> ExitCode {
    let cfg = Config {
        custom_statuses: HashMap::new(),
        visibility: visibility.to_string(),
        allow_untracked_acs,
    };
    let path = std::path::Path::new(doc_path);
    // The path may not exist — let the lifecycle module surface the
    // L05 error with its standard formatting. The whole-tree mode's
    // entry guard rejects on missing roots; the chain-targeted mode
    // leaves the rejection to the module so the error includes the
    // expected-location-set guidance.
    let findings = run_lifecycle_chain_check(path, &cfg, posture);
    render_lifecycle(&findings, format, posture)
}

/// Runs the `transition` subcommand. On success, prints the per-type JSON
/// result to stdout and exits 0. On failure, prints the error JSON (with a
/// matching `code` field) to stderr and exits with the engine's 1/2/3 code.
fn run_transition_cmd(args: &TransitionArgs) -> ExitCode {
    let flags = Flags {
        superseded_by: args.superseded_by.clone(),
        reason: args.reason.clone(),
    };
    match run_transition(&args.file, &args.status, &flags) {
        Ok(outcome) => {
            print!("{}", outcome.to_json());
            ExitCode::SUCCESS
        }
        Err(err) => {
            eprint!("{}", err.to_json());
            ExitCode::from(err.code as u8)
        }
    }
}

/// Runs the `finalize-chain` subcommand. By default it applies each tactical
/// node's terminal transition in-process (stripping a DESIGN's Implementation
/// Issues section first); `--dry-run` walks read-only. On success, prints the
/// JSON chain report to stdout and exits 0. On a walk or transition failure,
/// prints the node-and-type-aware error JSON
/// (`{ "success": false, "error": <message>, "code": <n> }`) to stderr and
/// exits with the chain's aggregated exit code, mirroring `run_transition_cmd`:
/// 2 lifecycle violation, 1 tool error, 3 I/O error. The exit code is the first
/// failing node's, since the walk stops there.
fn run_finalize_chain_cmd(args: &FinalizeChainArgs) -> ExitCode {
    let mode = if args.dry_run {
        Mode::DryRun
    } else {
        Mode::Apply
    };
    match walk_chain_mode(&args.plan, mode) {
        Ok(report) => {
            print!("{}", report.to_json());
            ExitCode::SUCCESS
        }
        Err(err) => {
            eprint!("{}", err.to_json());
            ExitCode::from(err.code() as u8)
        }
    }
}

/// The static pre-commit hook script written by `install-hooks`.
///
/// It is fully tool-authored: no repo-derived or user-derived string is
/// interpolated into it. Staged paths are collected NUL-delimited (`git
/// diff --cached -z`) and read with `read -r -d ''` so filenames containing
/// spaces, newlines, glob metacharacters, or leading dashes cannot split
/// arguments or smuggle options; paths are passed to `validate` after a
/// `--` end-of-options separator. The hook is fail-closed: `exec` hands the
/// validator's exit code straight back to git, so any non-zero result
/// blocks the commit. `bash` is used (not strict POSIX `sh`) because
/// `read -r -d ''` is the clean primitive for the NUL-safe handling the
/// security model requires.
const PRE_COMMIT_HOOK: &str = r#"#!/usr/bin/env bash
# shirabe pre-commit hook -- generated by `shirabe install-hooks`.
# Runs `shirabe validate` over the staged shirabe documents at commit time.
# Fail-closed: any non-zero validate exit blocks the commit.
set -euo pipefail

if ! command -v shirabe >/dev/null 2>&1; then
  echo "shirabe pre-commit: 'shirabe' not found on PATH; skipping doc validation." >&2
  exit 0
fi

# Collect staged files NUL-delimited so a filename with spaces, newlines,
# glob characters, or a leading dash cannot split arguments or smuggle
# options. Narrow to Markdown; shirabe's own format detection skips any
# non-artifact .md file.
docs=()
while IFS= read -r -d '' file; do
  case "$file" in
    *.md) docs+=("$file") ;;
  esac
done < <(git diff --cached -z --name-only --diff-filter=ACMR)

if [ ${#docs[@]} -eq 0 ]; then
  exit 0
fi

# Pass paths after `--` so a file named like a flag is treated as a path.
exec shirabe validate --format human -- "${docs[@]}"
"#;

/// The kind of pre-commit hook already present at the target path.
#[derive(Debug, PartialEq, Eq)]
enum ExistingHook {
    /// A hook this command previously installed (carries the shirabe marker).
    Ours,
    /// A hook managed by the pre-commit framework (pre-commit.com).
    Framework,
    /// Any other pre-existing hook.
    Other,
}

/// Classify the content of an existing `pre-commit` hook so the installer
/// can report it accurately and avoid clobbering a framework-managed hook.
fn classify_existing_hook(content: &str) -> ExistingHook {
    if content.contains("shirabe install-hooks") {
        ExistingHook::Ours
    } else if content.contains("pre-commit.com") || content.contains("generated by pre-commit") {
        ExistingHook::Framework
    } else {
        ExistingHook::Other
    }
}

/// The result of attempting to install the hook into a hooks directory.
#[derive(Debug, PartialEq, Eq)]
enum InstallOutcome {
    /// The hook was written (fresh install or `--force` overwrite).
    Installed,
    /// An existing hook was left byte-unchanged; the variant says what it was.
    Preserved(ExistingHook),
}

/// Install the pre-commit hook into `hooks_dir`. When a `pre-commit` hook is
/// already present and `force` is false, it is left byte-unchanged and the
/// classified kind is returned; otherwise the static hook is written at mode
/// `0755`. This is the filesystem core, factored out of
/// `run_install_hooks_cmd` so it can be tested against a temp directory
/// without depending on the process working directory or a real git repo.
fn install_hook_at(hooks_dir: &std::path::Path, force: bool) -> std::io::Result<InstallOutcome> {
    let hook_path = hooks_dir.join("pre-commit");

    if hook_path.exists() && !force {
        let existing = std::fs::read_to_string(&hook_path).unwrap_or_default();
        return Ok(InstallOutcome::Preserved(classify_existing_hook(&existing)));
    }

    std::fs::create_dir_all(hooks_dir)?;
    std::fs::write(&hook_path, PRE_COMMIT_HOOK)?;
    use std::os::unix::fs::PermissionsExt;
    std::fs::set_permissions(&hook_path, std::fs::Permissions::from_mode(0o755))?;
    Ok(InstallOutcome::Installed)
}

/// Runs the `install-hooks` subcommand. Resolves the repo's hooks directory
/// (via `git rev-parse --git-path hooks`, which is correct for worktrees and
/// submodules where `.git` is a file), then writes the static pre-commit
/// hook via [`install_hook_at`]. An existing hook is left byte-unchanged and
/// reported unless `--force` is given. Exit `0` on success or a reported
/// no-op; `1` on a tool error (not a git repo, write failure).
fn run_install_hooks_cmd(args: &InstallHooksArgs) -> ExitCode {
    use std::process::Command;

    let hooks_dir = match Command::new("git")
        .args(["rev-parse", "--git-path", "hooks"])
        .output()
    {
        Ok(out) if out.status.success() => String::from_utf8_lossy(&out.stdout).trim().to_string(),
        _ => {
            eprintln!(
                "install-hooks: not a git repository (could not resolve the hooks directory)"
            );
            return ExitCode::from(1);
        }
    };
    let hooks_dir = std::path::Path::new(&hooks_dir);
    let hook_path = hooks_dir.join("pre-commit");

    match install_hook_at(hooks_dir, args.force) {
        Ok(InstallOutcome::Preserved(kind)) => {
            match kind {
                ExistingHook::Ours => println!(
                    "install-hooks: a shirabe pre-commit hook is already installed at {} (unchanged). Pass --force to refresh it.",
                    hook_path.display()
                ),
                ExistingHook::Framework => println!(
                    "install-hooks: a pre-commit-framework hook is present at {} (unchanged). Add shirabe to your .pre-commit-config.yaml instead of installing a raw hook, or pass --force to replace it.",
                    hook_path.display()
                ),
                ExistingHook::Other => println!(
                    "install-hooks: an existing pre-commit hook is present at {} (unchanged). Pass --force to overwrite it.",
                    hook_path.display()
                ),
            }
            ExitCode::SUCCESS
        }
        Ok(InstallOutcome::Installed) => {
            let resolved = Command::new("sh")
                .args(["-c", "command -v shirabe"])
                .output()
                .ok()
                .filter(|o| o.status.success())
                .map(|o| String::from_utf8_lossy(&o.stdout).trim().to_string())
                .filter(|s| !s.is_empty());
            println!(
                "install-hooks: installed pre-commit hook at {}",
                hook_path.display()
            );
            match resolved {
                Some(path) => println!(
                    "install-hooks: the hook runs `shirabe` resolved on PATH (currently {}).",
                    path
                ),
                None => println!(
                    "install-hooks: note -- `shirabe` is not currently on PATH; the hook resolves it on PATH at commit time, so install shirabe for the checks to run."
                ),
            }
            ExitCode::SUCCESS
        }
        Err(err) => {
            eprintln!(
                "install-hooks: could not write the hook under {}: {}",
                hooks_dir.display(),
                err
            );
            ExitCode::from(1)
        }
    }
}

/// Parses the `--custom-statuses` flag value into a schema-version ->
/// status-list map. An empty value yields an empty map (no override).
///
/// Mirrors the Go path: a >64 KiB value and any YAML that does not decode
/// to a `map[string][]string` are rejected with the same message prefixes
/// the Go binary uses (`--custom-statuses value exceeds maximum allowed
/// size (64 KiB)` and `--custom-statuses contains invalid YAML: ...`).
fn parse_custom_statuses(value: &str) -> Result<HashMap<String, Vec<String>>, String> {
    if value.is_empty() {
        return Ok(HashMap::new());
    }
    if value.len() > MAX_CUSTOM_STATUSES_BYTES {
        return Err("--custom-statuses value exceeds maximum allowed size (64 KiB)".to_string());
    }

    let docs = Yaml::load_from_str(value)
        .map_err(|e| format!("--custom-statuses contains invalid YAML: {}", e))?;

    let mut out: HashMap<String, Vec<String>> = HashMap::new();

    // No documents (empty/comment-only input) or a null root decodes to an
    // empty map, matching yaml.Unmarshal of empty input into a nil map.
    let Some(root) = docs.into_iter().next() else {
        return Ok(out);
    };
    if root.is_null() {
        return Ok(out);
    }

    let Some(mapping) = root.as_mapping() else {
        return Err(invalid_yaml(
            "expected a map of schema version to status list",
        ));
    };

    for (key_node, val_node) in mapping.iter() {
        let Some(key) = key_node.as_str() else {
            return Err(invalid_yaml("map keys must be strings"));
        };
        let Some(items) = val_node.as_vec() else {
            return Err(invalid_yaml("each value must be a list of statuses"));
        };
        let mut statuses = Vec::with_capacity(items.len());
        for item in items {
            let Some(s) = item.as_str() else {
                return Err(invalid_yaml("status list entries must be strings"));
            };
            statuses.push(s.to_string());
        }
        out.insert(key.to_string(), statuses);
    }

    Ok(out)
}

/// Builds an `invalid YAML` error message with the shared Go-matching
/// prefix.
fn invalid_yaml(detail: &str) -> String {
    format!("--custom-statuses contains invalid YAML: {}", detail)
}

/// Renders a [`ParseError`] for the `could not read file:` annotation,
/// trimming `ParseError`'s `io error: ` Display prefix so the message
/// shape tracks Go's `could not read file: read <path>: ...` rather than
/// surfacing the Rust-internal wrapper label. The residual OS-string
/// difference (Rust's `std::io::Error` text vs Go's `os.PathError` text)
/// is an accepted out-of-contract divergence -- no parity-corpus file
/// triggers the IO-read-failure path. See DESIGN's divergence note.
fn io_error_text(err: &ParseError) -> String {
    let rendered = err.to_string();
    rendered
        .strip_prefix("io error: ")
        .map(str::to_string)
        .unwrap_or(rendered)
}

/// Returns the final path component of `path`, matching Go's
/// `filepath.Base` for the inputs the validator sees (POSIX-style paths in
/// CI). Trailing slashes are trimmed before taking the last component.
fn basename(path: &str) -> &str {
    let trimmed = path.trim_end_matches('/');
    if trimmed.is_empty() {
        // `filepath.Base("/")` is "/"; an all-slash path keeps a slash.
        return "/";
    }
    match trimmed.rfind('/') {
        Some(idx) => &trimmed[idx + 1..],
        None => trimmed,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parse_custom_statuses_empty_is_empty_map() {
        assert!(parse_custom_statuses("").unwrap().is_empty());
    }

    #[test]
    fn parse_custom_statuses_valid_block_map() {
        let map = parse_custom_statuses("design/v1:\n  - Draft\n  - Done\n").unwrap();
        assert_eq!(
            map.get("design/v1"),
            Some(&vec!["Draft".to_string(), "Done".to_string()])
        );
    }

    #[test]
    fn parse_custom_statuses_inline_flow_map() {
        let map = parse_custom_statuses("{design/v1: [A, B]}").unwrap();
        assert_eq!(
            map.get("design/v1"),
            Some(&vec!["A".to_string(), "B".to_string()])
        );
    }

    #[test]
    fn parse_custom_statuses_oversize_rejected() {
        let big = "x".repeat(MAX_CUSTOM_STATUSES_BYTES + 1);
        let err = parse_custom_statuses(&big).unwrap_err();
        assert!(err.contains("exceeds maximum allowed size (64 KiB)"));
    }

    #[test]
    fn parse_custom_statuses_invalid_yaml_rejected() {
        let err = parse_custom_statuses("key: [unclosed").unwrap_err();
        assert!(err.contains("--custom-statuses contains invalid YAML"));
    }

    #[test]
    fn parse_custom_statuses_non_map_rejected() {
        let err = parse_custom_statuses("just a scalar").unwrap_err();
        assert!(err.contains("--custom-statuses contains invalid YAML"));
    }

    #[test]
    fn basename_simple() {
        assert_eq!(basename("docs/designs/DESIGN-foo.md"), "DESIGN-foo.md");
        assert_eq!(basename("DESIGN-foo.md"), "DESIGN-foo.md");
        assert_eq!(basename("/abs/PLAN-bar.md"), "PLAN-bar.md");
    }

    #[test]
    fn basename_trailing_slash() {
        assert_eq!(basename("docs/"), "docs");
        assert_eq!(basename("/"), "/");
    }

    #[test]
    fn validate_outcome_exit_codes_mirror_sibling_scheme() {
        // 0 clean, 1 tool-error, 2 violations, 3 I/O -- the same scheme
        // transition and finalize-chain use.
        assert_eq!(ValidateOutcome::Clean.exit_code(), 0);
        assert_eq!(ValidateOutcome::ToolError.exit_code(), 1);
        assert_eq!(ValidateOutcome::Violations.exit_code(), 2);
        assert_eq!(ValidateOutcome::Io.exit_code(), 3);
    }

    #[test]
    fn validate_outcome_clean_is_zero_everything_else_nonzero() {
        // Existing zero/non-zero CI gates keep working.
        assert_eq!(ValidateOutcome::Clean.exit_code(), 0);
        for o in [
            ValidateOutcome::ToolError,
            ValidateOutcome::Violations,
            ValidateOutcome::Io,
        ] {
            assert_ne!(o.exit_code(), 0);
        }
    }

    #[test]
    fn validate_outcome_tool_error_outranks_violations() {
        // Severity ordering is distinct from the exit integer: tool-error
        // (exit 1) is more severe than a violation (exit 2).
        assert!(
            ValidateOutcome::ToolError.severity_rank()
                > ValidateOutcome::Violations.severity_rank()
        );
        assert!(
            ValidateOutcome::Violations.severity_rank() > ValidateOutcome::Clean.severity_rank()
        );
        assert!(ValidateOutcome::Io.severity_rank() > ValidateOutcome::ToolError.severity_rank());
    }

    #[test]
    fn validate_outcome_merge_keeps_most_severe() {
        // A clean run that then finds a violation -> violations (exit 2).
        let r = ValidateOutcome::Clean.merge(ValidateOutcome::Violations);
        assert_eq!(r.exit_code(), 2);

        // {clean, violations} accumulated, then a tool error (unreadable
        // file): tool-error wins -> exit 1, even though it appears last and
        // its integer is lower.
        let r = ValidateOutcome::Clean
            .merge(ValidateOutcome::Violations)
            .merge(ValidateOutcome::ToolError);
        assert_eq!(r.exit_code(), 1);

        // Order-independent: a tool error first, then a violation, still 1.
        let r = ValidateOutcome::ToolError.merge(ValidateOutcome::Violations);
        assert_eq!(r.exit_code(), 1);

        // All-clean stays clean.
        let r = ValidateOutcome::Clean.merge(ValidateOutcome::Clean);
        assert_eq!(r.exit_code(), 0);
    }

    #[test]
    fn validate_format_defaults_to_annotation() {
        // An invocation with no --format must default to annotation so
        // existing CI invocations are byte-unchanged.
        let cli = Cli::parse_from(["shirabe", "validate", "x.md"]);
        match cli.command {
            Some(Commands::Validate(args)) => {
                assert!(matches!(args.format, Format::Annotation));
            }
            _ => panic!("expected the validate subcommand"),
        }
    }

    #[test]
    fn validate_mode_defaults_to_draft() {
        // No --mode and no --strict: the default posture is Draft.
        let cli = Cli::parse_from(["shirabe", "validate", "--lifecycle", "."]);
        match cli.command {
            Some(Commands::Validate(args)) => {
                assert!(matches!(args.mode, PostureMode::Draft));
                assert!(!args.strict);
                assert_eq!(
                    resolve_posture(args.strict, args.mode),
                    ReviewPosture::Draft
                );
            }
            _ => panic!("expected the validate subcommand"),
        }
    }

    #[test]
    fn validate_strict_and_mode_ready_resolve_identically() {
        // The deprecated --strict and --mode=ready must resolve to the same
        // ReviewPosture (Ready), so they yield identical verdicts/output.
        let strict_cli = Cli::parse_from(["shirabe", "validate", "--lifecycle", ".", "--strict"]);
        let ready_cli =
            Cli::parse_from(["shirabe", "validate", "--lifecycle", ".", "--mode", "ready"]);

        let strict_posture = match strict_cli.command {
            Some(Commands::Validate(args)) => resolve_posture(args.strict, args.mode),
            _ => panic!("expected the validate subcommand"),
        };
        let ready_posture = match ready_cli.command {
            Some(Commands::Validate(args)) => resolve_posture(args.strict, args.mode),
            _ => panic!("expected the validate subcommand"),
        };
        assert_eq!(strict_posture, ReviewPosture::Ready);
        assert_eq!(ready_posture, ReviewPosture::Ready);
        assert_eq!(strict_posture, ready_posture);
    }

    #[test]
    fn resolve_posture_strict_wins_over_mode() {
        // Precedence: --strict present resolves to Ready even if --mode says
        // draft; otherwise the --mode value applies.
        assert_eq!(
            resolve_posture(true, PostureMode::Draft),
            ReviewPosture::Ready
        );
        assert_eq!(
            resolve_posture(false, PostureMode::Ready),
            ReviewPosture::Ready
        );
        assert_eq!(
            resolve_posture(false, PostureMode::Draft),
            ReviewPosture::Draft
        );
    }

    #[test]
    fn validate_check_is_repeatable_and_comma_split() {
        let cli = Cli::parse_from([
            "shirabe",
            "validate",
            "--check",
            "FC01,FC03",
            "--check",
            "R7",
            "x.md",
        ]);
        match cli.command {
            Some(Commands::Validate(args)) => {
                assert_eq!(args.check, vec!["FC01", "FC03", "R7"]);
            }
            _ => panic!("expected the validate subcommand"),
        }
    }

    #[test]
    fn merge_gate_posture_matrix() {
        // Pass: clean (exit 0) in both postures.
        let pass = MergeGateOutcome::Pass {
            pr_count: 2,
            upstream_count: 1,
        };
        assert_eq!(
            merge_gate_outcome(&pass, ReviewPosture::Ready).exit_code(),
            0
        );
        assert_eq!(
            merge_gate_outcome(&pass, ReviewPosture::Draft).exit_code(),
            0
        );

        // Blocked: posture-aware. Ready => violations (exit 2, backstop);
        // Draft => clean (exit 0, notice) — symmetric with L02/L06/L07.
        let blocked = MergeGateOutcome::Blocked(vec!["pr-1 is not merged".to_string()]);
        assert_eq!(
            merge_gate_outcome(&blocked, ReviewPosture::Ready).exit_code(),
            2
        );
        assert_eq!(
            merge_gate_outcome(&blocked, ReviewPosture::Draft).exit_code(),
            0
        );

        // Refused: fail-closed in EVERY posture (a draft does not soften a
        // visibility leak). Exit 2 under both.
        let refused = MergeGateOutcome::Refused(vec!["public PR cannot index pr-2".to_string()]);
        assert_eq!(
            merge_gate_outcome(&refused, ReviewPosture::Ready).exit_code(),
            2
        );
        assert_eq!(
            merge_gate_outcome(&refused, ReviewPosture::Draft).exit_code(),
            2
        );

        // InputError: hard input error (exit 1) in every posture.
        let input = MergeGateOutcome::InputError("invalid reference".to_string());
        assert_eq!(
            merge_gate_outcome(&input, ReviewPosture::Ready).exit_code(),
            1
        );
        assert_eq!(
            merge_gate_outcome(&input, ReviewPosture::Draft).exit_code(),
            1
        );
    }

    #[test]
    fn merge_gate_flag_parses_pr_and_upstream() {
        let cli = Cli::parse_from([
            "shirabe",
            "validate",
            "--merge-gate",
            "--mode=ready",
            "--pr",
            "o/r:docs/a.md#1",
            "--pr",
            "o/r:docs/b.md#2",
            "--upstream",
            "o/r:docs/d.md#3",
        ]);
        match cli.command {
            Some(Commands::Validate(args)) => {
                assert!(args.merge_gate);
                assert_eq!(args.pr, vec!["o/r:docs/a.md#1", "o/r:docs/b.md#2"]);
                assert_eq!(args.upstream, vec!["o/r:docs/d.md#3"]);
                assert!(matches!(args.mode, PostureMode::Ready));
            }
            _ => panic!("expected the validate subcommand"),
        }
    }

    #[test]
    fn merge_gate_conflicts_with_lifecycle() {
        // clap rejects --merge-gate alongside --lifecycle (conflicts_with).
        let res = Cli::try_parse_from(["shirabe", "validate", "--merge-gate", "--lifecycle", "."]);
        assert!(res.is_err(), "--merge-gate + --lifecycle must be rejected");
    }

    #[test]
    fn json_string_escapes_control_chars() {
        assert_eq!(json_string("a\"b"), "\"a\\\"b\"");
        assert_eq!(json_string("a\nb"), "\"a\\nb\"");
        assert_eq!(json_string("plain"), "\"plain\"");
    }

    #[test]
    fn classify_existing_hook_distinguishes_kinds() {
        assert_eq!(classify_existing_hook(PRE_COMMIT_HOOK), ExistingHook::Ours);
        assert_eq!(
            classify_existing_hook("#!/bin/sh\n# File generated by pre-commit.com\n"),
            ExistingHook::Framework
        );
        assert_eq!(
            classify_existing_hook("#!/bin/sh\nmake lint\n"),
            ExistingHook::Other
        );
    }

    #[test]
    fn pre_commit_hook_has_security_critical_pieces() {
        // NUL-delimited staged-file collection (no arg-splitting on bad names).
        assert!(PRE_COMMIT_HOOK.contains("git diff --cached -z --name-only --diff-filter=ACMR"));
        assert!(PRE_COMMIT_HOOK.contains("read -r -d ''"));
        // Paths passed after the end-of-options separator.
        assert!(PRE_COMMIT_HOOK.contains("-- \"${docs[@]}\""));
        // Fail-closed: exec hands validate's exit code back to git.
        assert!(PRE_COMMIT_HOOK.contains("exec shirabe validate --format human"));
        // Carries the marker used to recognize our own hook on re-install.
        assert!(PRE_COMMIT_HOOK.contains("shirabe install-hooks"));
    }

    #[test]
    fn install_hook_at_writes_preserves_and_forces() {
        use std::os::unix::fs::PermissionsExt;

        // A unique temp hooks dir (no git, no CWD dependency).
        let base = std::env::temp_dir().join(format!(
            "shirabe-hooktest-{}-{}",
            std::process::id(),
            line!()
        ));
        let hooks = base.join("hooks");
        let _ = std::fs::remove_dir_all(&base);

        // Fresh install: writes the hook at mode 0755.
        assert_eq!(
            install_hook_at(&hooks, false).unwrap(),
            InstallOutcome::Installed
        );
        let hook = hooks.join("pre-commit");
        assert!(hook.exists());
        let mode = std::fs::metadata(&hook).unwrap().permissions().mode();
        assert_eq!(mode & 0o777, 0o755);
        assert_eq!(std::fs::read_to_string(&hook).unwrap(), PRE_COMMIT_HOOK);

        // A foreign hook is preserved byte-unchanged without --force.
        std::fs::write(&hook, "#!/bin/sh\nmake lint\n").unwrap();
        assert_eq!(
            install_hook_at(&hooks, false).unwrap(),
            InstallOutcome::Preserved(ExistingHook::Other)
        );
        assert_eq!(
            std::fs::read_to_string(&hook).unwrap(),
            "#!/bin/sh\nmake lint\n"
        );

        // --force overwrites with our hook.
        assert_eq!(
            install_hook_at(&hooks, true).unwrap(),
            InstallOutcome::Installed
        );
        assert_eq!(std::fs::read_to_string(&hook).unwrap(), PRE_COMMIT_HOOK);

        let _ = std::fs::remove_dir_all(&base);
    }
}
