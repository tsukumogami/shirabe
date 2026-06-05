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
    detect_format, format_error, format_notice, is_notice, parse_doc, run_transition,
    validate_file, Config, Flags, ParseError, ValidationError,
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
}

fn main() -> ExitCode {
    let cli = Cli::parse();
    match cli.command {
        Some(Commands::Validate(args)) => run_validate(&args),
        Some(Commands::Roadmap(args)) => match args.command {
            RoadmapCommands::Populate(p) => populate::run(&p),
        },
        Some(Commands::Transition(args)) => run_transition_cmd(&args),
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

/// Runs the `validate` subcommand. Returns `ExitCode::FAILURE` (1) if any
/// error-level annotation was emitted or a flag was invalid, else
/// `ExitCode::SUCCESS` (0).
fn run_validate(args: &ValidateArgs) -> ExitCode {
    if args.files.is_empty() {
        return ExitCode::SUCCESS;
    }

    let custom_statuses = match parse_custom_statuses(&args.custom_statuses) {
        Ok(map) => map,
        Err(msg) => {
            eprintln!("{}", msg);
            return ExitCode::FAILURE;
        }
    };

    let cfg = Config {
        custom_statuses,
        visibility: args.visibility.clone(),
    };

    let mut has_errors = false;
    for path in &args.files {
        let spec = match detect_format(basename(path)) {
            Some(s) => s,
            None => continue,
        };

        let doc = match parse_doc(path) {
            Ok(d) => d,
            Err(err) => {
                println!(
                    "{}",
                    format_error(&ValidationError {
                        file: path.clone(),
                        line: 1,
                        code: "IO".to_string(),
                        message: format!("could not read file: {}", io_error_text(&err)),
                    })
                );
                has_errors = true;
                continue;
            }
        };

        let errs = validate_file(&doc, &spec, &cfg);
        for ve in &errs {
            if is_notice(ve) {
                println!("{}", format_notice(&ve.file, &ve.message));
            } else {
                println!("{}", format_error(ve));
                has_errors = true;
            }
        }
    }

    if has_errors {
        ExitCode::FAILURE
    } else {
        ExitCode::SUCCESS
    }
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
}
