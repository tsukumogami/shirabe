//! CLI integration tests exercising the built `shirabe` binary end to
//! end with `assert_cmd`. These lock the user-facing contract the Go
//! `cmd/shirabe/main.go` established: the `--version` line, the
//! `--custom-statuses` size cap message, and the no-args / unrecognized
//! -format exit behavior.

use assert_cmd::Command;
use predicates::prelude::PredicateBooleanExt;
use predicates::str::contains;

/// Resolve the binary under test. The `[[bin]]` target is named
///
fn shirabe() -> Command {
    Command::cargo_bin("shirabe").expect("binary `shirabe` builds")
}

#[test]
fn version_prints_shirabe_space_version_newline() {
    // The Go binary's version template is `"shirabe {{.Version}}\n"`. The
    // embedded version is whatever build.rs injected (SHIRABE_VERSION
    // override, else CARGO_PKG_VERSION), so assert against that exact value
    // rather than a hardcoded string -- the format is the contract.
    let expected = format!("shirabe {}\n", env!("CARGO_PKG_VERSION"));
    shirabe()
        .arg("--version")
        .assert()
        .success()
        .stdout(expected);
}

#[test]
fn lowercase_v_prints_version() {
    // cobra binds `-v` (lowercase) to version; clap's default is `-V`. We
    // bind both, so `-v` must print the same `shirabe <version>` line and
    // exit 0, matching the Go binary's `shirabe -v`.
    let expected = format!("shirabe {}\n", env!("CARGO_PKG_VERSION"));
    shirabe().arg("-v").assert().success().stdout(expected);
}

#[test]
fn uppercase_v_is_rejected() {
    // Strict cobra parity: Go binds `-v` to version and REJECTS `-V`
    // ("unknown shorthand flag"). We mirror that — `-V` is unbound, so it
    // must error (non-zero exit), NOT print the version. The exact error
    // text differs from cobra (different framework); the contract is that
    // `-V` is not a version alias.
    shirabe().arg("-V").assert().failure();
}

#[test]
fn bare_invocation_prints_help_to_stdout_and_exits_zero() {
    // cobra's bare `shirabe` (no subcommand) prints help to STDOUT and
    // exits 0. clap would default to a usage error on stderr with exit 2;
    // we override that. The help TEXT differs between frameworks, so assert
    // only the contract that matters: exit 0, output on stdout (non-empty),
    // and nothing on stderr.
    shirabe()
        .assert()
        .success()
        .stdout(contains("Workflow skills for AI coding agents"))
        .stderr("");
}

#[test]
fn custom_statuses_over_cap_is_rejected() {
    // A value larger than 64 KiB must be rejected with the Go-matching
    // message and a non-zero exit, before any file is read.
    let oversize = "x".repeat(64 * 1024 + 1);
    shirabe()
        .arg("validate")
        .arg("--custom-statuses")
        .arg(oversize)
        .arg("DESIGN-anything.md")
        .assert()
        .failure()
        .stderr(contains(
            "--custom-statuses value exceeds maximum allowed size (64 KiB)",
        ));
}

#[test]
fn custom_statuses_at_cap_is_accepted() {
    // Exactly 64 KiB is allowed (the guard is strictly greater-than). The
    // value is valid YAML (one mapping entry padded with a comment) so the
    // cap check passes and parsing succeeds; no files means exit 0.
    let mut value = String::from("design/v1: [Draft]\n");
    value.push_str(&"#".repeat(64 * 1024 - value.len()));
    assert_eq!(value.len(), 64 * 1024);
    shirabe()
        .arg("validate")
        .arg("--custom-statuses")
        .arg(value)
        .assert()
        .success()
        .stdout("");
}

#[test]
fn no_files_exits_zero_with_no_output() {
    // Mirrors the Go `len(args) == 0 { return nil }` path.
    shirabe()
        .arg("validate")
        .assert()
        .success()
        .stdout("")
        .stderr("");
}

#[test]
fn unrecognized_format_is_skipped() {
    // A path whose basename matches no format prefix is silently skipped;
    // with no other files the run exits 0 and emits nothing.
    shirabe()
        .arg("validate")
        .arg("README.md")
        .assert()
        .success()
        .stdout("")
        .stderr("");
}

#[test]
fn lifecycle_chain_and_lifecycle_are_mutually_exclusive() {
    // The two lifecycle modes target different scopes; passing both
    // surfaces a clear error and exits non-zero before any work runs.
    shirabe()
        .arg("validate")
        .arg("--lifecycle")
        .arg(".")
        .arg("--lifecycle-chain")
        .arg("docs/plans/PLAN-foo.md")
        .assert()
        .failure()
        .stderr(contains(
            "--lifecycle and --lifecycle-chain are mutually exclusive",
        ));
}

#[test]
fn lifecycle_chain_with_positional_files_is_rejected() {
    // The chain-targeted mode takes its doc-path via the flag value;
    // additional positional files would be ambiguous.
    shirabe()
        .arg("validate")
        .arg("--lifecycle-chain")
        .arg("docs/plans/PLAN-foo.md")
        .arg("docs/briefs/BRIEF-foo.md")
        .assert()
        .failure()
        .stderr(contains(
            "--lifecycle-chain is mutually exclusive with positional file arguments",
        ));
}

#[test]
fn lifecycle_chain_missing_path_emits_l05() {
    // A path that does not resolve to a file produces a single L05
    // error naming the expected location set.
    shirabe()
        .arg("validate")
        .arg("--lifecycle-chain")
        .arg("/tmp/shirabe-cli-nonexistent-doc.md")
        .assert()
        .failure()
        .stdout(contains("[L05]"))
        .stdout(contains("not found or not resolvable"));
}

#[test]
fn lifecycle_chain_format_json_emits_envelope_with_l_codes() {
    // `--lifecycle-chain --format json` must render the versioned
    // `shirabe-validate/v1` envelope (not the annotation lines), carrying
    // the L-family finding for a path that does not resolve. The exit code
    // stays 2 (violations) -- the format flag changes only the rendering,
    // not the outcome contract.
    shirabe()
        .arg("validate")
        .arg("--lifecycle-chain")
        .arg("/tmp/shirabe-cli-nonexistent-doc.md")
        .arg("--format")
        .arg("json")
        .assert()
        .failure()
        // A well-formed v1 envelope: the schema tag, a violations summary
        // with one error and no notices, and the L05 finding rendered as an
        // error-level entry (L-codes are never notices).
        .stdout(contains("\"schema_version\": \"shirabe-validate/v1\""))
        .stdout(contains("\"outcome\": \"violations\""))
        .stdout(contains("\"errors\": 1"))
        .stdout(contains("\"notices\": 0"))
        .stdout(contains("\"code\": \"L05\""))
        .stdout(contains("\"severity\": \"error\""))
        // The annotation workflow-command syntax must NOT leak into JSON mode.
        .stdout(contains("::error").not());
}

#[test]
fn lifecycle_chain_annotation_default_is_unchanged() {
    // Annotation mode is the default and its bytes are frozen for CI
    // parity. The refactor that added --format must leave the default
    // annotation output byte-identical: a single L05 workflow-command line
    // with no JSON/human framing.
    let expected = "::error file=/tmp/shirabe-cli-nonexistent-doc.md,line=1::[L05] doc path not found or not resolvable: /tmp/shirabe-cli-nonexistent-doc.md (expected a doc under docs/{briefs,prds,designs,designs/current,plans,roadmaps}/)\n";
    shirabe()
        .arg("validate")
        .arg("--lifecycle-chain")
        .arg("/tmp/shirabe-cli-nonexistent-doc.md")
        .assert()
        .failure()
        .stdout(expected);
}

#[test]
fn allow_untracked_acs_flag_is_accepted() {
    // The CLI must accept --allow-untracked-acs as a boolean flag without
    // it being mutually exclusive with any other flag. The flag exists on
    // the validate subcommand; passing it with an unresolvable
    // --lifecycle-chain doc still emits L05 (the lifecycle layer's
    // canonical missing-doc error). The contract here is that the flag
    // parses cleanly and does not suppress unrelated errors.
    shirabe()
        .arg("validate")
        .arg("--lifecycle-chain")
        .arg("/tmp/shirabe-cli-nonexistent-doc.md")
        .arg("--allow-untracked-acs")
        .assert()
        .failure()
        .stdout(contains("[L05]"));
}
