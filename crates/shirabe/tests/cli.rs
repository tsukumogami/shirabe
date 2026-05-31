//! CLI integration tests exercising the built `shirabe-rs` binary end to
//! end with `assert_cmd`. These lock the user-facing contract the Go
//! `cmd/shirabe/main.go` established: the `--version` line, the
//! `--custom-statuses` size cap message, and the no-args / unrecognized
//! -format exit behavior.

use assert_cmd::Command;
use predicates::str::contains;

/// Resolve the binary under test. The `[[bin]]` target is named
/// `shirabe-rs` during the Go/Rust coexistence window.
fn shirabe() -> Command {
    Command::cargo_bin("shirabe-rs").expect("binary `shirabe-rs` builds")
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
fn uppercase_v_prints_version() {
    // `-V` (clap's conventional version short) also prints version. NOTE:
    // Go cobra rejects `-V` (it only binds `-v`); accepting `-V` here is a
    // deliberate, documented deviation -- the version output stream/exit is
    // the contract that matters, and keeping clap's `-V` avoids surprising
    // Rust-tooling users.
    let expected = format!("shirabe {}\n", env!("CARGO_PKG_VERSION"));
    shirabe().arg("-V").assert().success().stdout(expected);
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
