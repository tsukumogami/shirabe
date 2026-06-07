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
    check_slug_prefix, detect_format, format_error, format_notice, is_notice, parse_doc,
    run_lifecycle_chain_check, run_lifecycle_check, run_transition, validate_file, walk_chain_mode,
    Config, Flags, Mode, ParseError, SlugPrefixCheck, ValidationError,
};

mod populate;

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
}

#[derive(clap::Args)]
struct RoadmapArgs {
    #[command(subcommand)]
    command: RoadmapCommands,
}

#[derive(Subcommand)]
enum RoadmapCommands {
    /// Populate a roadmap's reserved Implementation Issues and Dependency
    /// Graph sections, creating one GitHub issue per feature.
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
struct ValidateArgs {
    /// Files to validate.
    files: Vec<String>,

    /// Visibility context; only 'private' bypasses public-repo checks
    /// (unset is treated as public).
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

    /// Strict mode for `--lifecycle`. Disables the single-pr-mid-PR
    /// exemption so a present single-pr PLAN fails the check and
    /// single-pr BRIEF/PRD at Accepted fail. Multi-pr postures are
    /// unchanged. Default off — preserves the upstream non-strict
    /// behavior in local CLI invocations. The CI workflow templates
    /// this flag conditional on the PR's `draft` state so DRAFT PRs
    /// run non-strict and READY PRs run strict.
    #[arg(long, default_value_t = false)]
    strict: bool,

    /// Chain-targeted lifecycle mode. Takes a doc-in-a-chain (PLAN,
    /// DESIGN, PRD, BRIEF, or ROADMAP) and validates only the chain
    /// containing that doc. Mutually exclusive with `--lifecycle` and
    /// with positional file arguments. Works with `--strict`. The
    /// work-on cascade script uses this mode to verify its own chain's
    /// posture without surfacing unrelated drift as noise.
    #[arg(long, value_name = "DOC")]
    lifecycle_chain: Option<String>,
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

    if let Some(root) = args.lifecycle.as_deref() {
        return run_lifecycle(root, &args.visibility, args.strict);
    }

    if let Some(doc) = args.lifecycle_chain.as_deref() {
        return run_lifecycle_chain(doc, &args.visibility, args.strict);
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

    let cfg = Config {
        custom_statuses,
        visibility: args.visibility.clone(),
    };

    let mut worst = ValidateOutcome::Clean;
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
                println!(
                    "{}",
                    format_error(&ValidationError {
                        file: path.clone(),
                        line: 1,
                        code: "IO".to_string(),
                        message: format!("could not read file: {}", io_error_text(&err)),
                    })
                );
                worst = worst.merge(ValidateOutcome::ToolError);
                continue;
            }
        };

        let errs = validate_file(&doc, &spec, &cfg);
        for ve in &errs {
            if is_notice(ve) {
                println!("{}", format_notice(&ve.file, &ve.message));
            } else {
                println!("{}", format_error(ve));
                worst = worst.merge(ValidateOutcome::Violations);
            }
        }
    }

    worst.exit()
}

/// Runs the chain-aware passing-state lifecycle check against `root`.
/// Emits one annotation per failure to stdout and returns a non-zero
/// exit code if any failures were emitted.
///
/// When `strict` is true, the single-pr-mid-PR exemption is disabled:
/// a single-pr PLAN present in the tree fails (regardless of its
/// `status:` value) and single-pr BRIEF/PRD at Accepted fail.
/// Multi-pr postures are unchanged by the strict flag.
fn run_lifecycle(root: &str, visibility: &str, strict: bool) -> ExitCode {
    let cfg = Config {
        custom_statuses: HashMap::new(),
        visibility: visibility.to_string(),
    };
    let root_path = std::path::Path::new(root);
    if !root_path.exists() {
        eprintln!("--lifecycle root {} does not exist", root);
        return ValidateOutcome::ToolError.exit();
    }
    let errors = run_lifecycle_check(root_path, &cfg, strict);
    let mut worst = ValidateOutcome::Clean;
    for ve in &errors {
        if is_notice(ve) {
            println!("{}", format_notice(&ve.file, &ve.message));
        } else {
            println!("{}", format_error(ve));
            worst = worst.merge(ValidateOutcome::Violations);
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
/// `run_lifecycle_chain_check`. The strict flag has the same
/// behavior: when true, the single-pr-mid-PR exemption is disabled
/// for the matched chain; multi-pr postures are unchanged.
///
/// Used by the work-on cascade script in
/// `skills/work-on/scripts/run-cascade.sh` for the pre-cascade probe
/// and post-cascade verification points.
fn run_lifecycle_chain(doc_path: &str, visibility: &str, strict: bool) -> ExitCode {
    let cfg = Config {
        custom_statuses: HashMap::new(),
        visibility: visibility.to_string(),
    };
    let path = std::path::Path::new(doc_path);
    // The path may not exist — let the lifecycle module surface the
    // L05 error with its standard formatting. The whole-tree mode's
    // entry guard rejects on missing roots; the chain-targeted mode
    // leaves the rejection to the module so the error includes the
    // expected-location-set guidance.
    let errors = run_lifecycle_chain_check(path, &cfg, strict);
    let mut worst = ValidateOutcome::Clean;
    for ve in &errors {
        if is_notice(ve) {
            println!("{}", format_notice(&ve.file, &ve.message));
        } else {
            println!("{}", format_error(ve));
            worst = worst.merge(ValidateOutcome::Violations);
        }
    }
    worst.exit()
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
}
