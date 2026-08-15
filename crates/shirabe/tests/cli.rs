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
fn unrecognized_format_gets_prose_checks_not_structural_ones() {
    // A path whose basename matches no artifact prefix used to be silently
    // skipped: `shirabe validate README.md` printed nothing and exited 0,
    // and this test asserted that as the contract. It was the defect, not
    // the design — the instruction files that shape every agent run were
    // the ones nothing checked.
    //
    // The file now gets the prose family. It does not get the structural
    // checks: a README has no frontmatter, no schema, and no required
    // sections, so FC01/FC04/FC15 firing on it would be a worse regression
    // than the gap. That invariant is a signature property now, since the
    // prose entry point takes no FormatSpec.
    let dir = std::env::temp_dir().join("shirabe-cli-unrecognized-format");
    let _ = std::fs::remove_dir_all(&dir);
    std::fs::create_dir_all(&dir).unwrap();
    let readme = dir.join("README.md");
    std::fs::write(&readme, "A robust and comprehensive introduction.\n").unwrap();

    let out = shirabe()
        .arg("validate")
        .arg(readme.to_str().unwrap())
        .assert()
        .success()
        .get_output()
        .stdout
        .clone();
    let text = String::from_utf8_lossy(&out);

    assert!(
        text.contains("FC10"),
        "the prose family must reach a non-artifact file; got: {text}"
    );

    for structural in ["FC01", "FC02", "FC03", "FC04", "FC15", "SCHEMA"] {
        assert!(
            !text.contains(structural),
            "structural check {structural} must not fire on a non-artifact file; got: {text}"
        );
    }
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

/// A minimal STRATEGY doc that carries the R8-gated `Competitive
/// Considerations` section. The `--check R8` runs filter every other finding,
/// so only R8's presence/absence is observed.
const STRATEGY_WITH_COMPETITIVE: &str = "---\nschema: strategy/v1\nbet: A bet.\nscope: A scope.\nstatus: Active\n---\n\n# STRATEGY: visibility autodetect\n\n## Competitive Considerations\n\nPrivate-only section.\n";

/// Create an isolated repo directory under the temp dir with the given
/// CLAUDE.md body and a STRATEGY doc, returning the doc path. The directory
/// name is derived from `tag` (cleaned first) so parallel test runs stay
/// isolated without a randomness source.
fn make_repo_with_doc(tag: &str, claude_md: &str) -> std::path::PathBuf {
    let repo = std::env::temp_dir().join(format!("shirabe-cli-visibility-{tag}"));
    let _ = std::fs::remove_dir_all(&repo);
    std::fs::create_dir_all(&repo).unwrap();
    std::fs::write(repo.join("CLAUDE.md"), claude_md).unwrap();
    let doc = repo.join("STRATEGY-visibility.md");
    std::fs::write(&doc, STRATEGY_WITH_COMPETITIVE).unwrap();
    doc
}

#[test]
fn visibility_autodetected_private_repo_strategy_passes_r8_without_flag() {
    // The R8 false-positive fix: with no `--visibility` flag, a STRATEGY that
    // lives in a repo whose CLAUDE.md declares `## Repo Visibility: Private`
    // must NOT trip R8 for its Competitive Considerations section. Visibility
    // is auto-detected from the owning repo's CLAUDE.md header.
    let doc = make_repo_with_doc("private-passes", "# repo\n\n## Repo Visibility: Private\n");
    shirabe()
        .arg("validate")
        .arg("--check")
        .arg("R8")
        .arg(&doc)
        .assert()
        .success()
        .stdout("");
}

#[test]
fn visibility_autodetected_public_repo_strategy_still_fails_r8() {
    // The fix must not neuter R8 for genuinely public repos: with no
    // `--visibility` flag, a STRATEGY in a repo whose CLAUDE.md declares
    // `## Repo Visibility: Public` must still trip R8 on its Competitive
    // Considerations section.
    let doc = make_repo_with_doc("public-fails", "# repo\n\n## Repo Visibility: Public\n");
    shirabe()
        .arg("validate")
        .arg("--check")
        .arg("R8")
        .arg(&doc)
        .assert()
        .failure()
        .stdout(contains("[R8]"))
        .stdout(contains("Competitive Considerations"));
}

#[test]
fn visibility_explicit_flag_overrides_autodetection() {
    // An explicit `--visibility public` overrides the Private header, so R8
    // fires even though the owning repo's CLAUDE.md says Private. This locks
    // the precedence: flag beats detection.
    let doc = make_repo_with_doc("flag-override", "## Repo Visibility: Private\n");
    shirabe()
        .arg("validate")
        .arg("--visibility")
        .arg("public")
        .arg("--check")
        .arg("R8")
        .arg(&doc)
        .assert()
        .failure()
        .stdout(contains("[R8]"));
}

/// A minimal BRIEF whose `upstream:` names a DESIGN -- a direction violation
/// (a brief heads its own lineage) with no lifetime component, so `--check
/// R10` observes R10 alone.
const BRIEF_NAMING_A_DESIGN: &str = "---\nschema: brief/v1\nstatus: Draft\nproblem: A problem.\noutcome: An outcome.\nupstream: docs/designs/DESIGN-x.md\n---\n\n# BRIEF: legality\n\n## Status\n\nDraft\n\n## Problem Statement\n\nA problem.\n\n## User Outcome\n\nAn outcome.\n\n## User Journeys\n\n### One\n\nA journey.\n\n## Scope Boundary\n\nIN: a thing. OUT: another.\n";

/// The same BRIEF naming a ROADMAP -- a working target, so the lifetime
/// finding fires and the direction finding is suppressed.
const BRIEF_NAMING_A_ROADMAP: &str = "---\nschema: brief/v1\nstatus: Draft\nproblem: A problem.\noutcome: An outcome.\nupstream: docs/roadmaps/ROADMAP-x.md\n---\n\n# BRIEF: legality\n\n## Status\n\nDraft\n\n## Problem Statement\n\nA problem.\n\n## User Outcome\n\nAn outcome.\n\n## User Journeys\n\n### One\n\nA journey.\n\n## Scope Boundary\n\nIN: a thing. OUT: another.\n";

fn make_brief(tag: &str, body: &str) -> std::path::PathBuf {
    let repo = std::env::temp_dir().join(format!("shirabe-cli-legality-{tag}"));
    let _ = std::fs::remove_dir_all(&repo);
    std::fs::create_dir_all(&repo).unwrap();
    let doc = repo.join("BRIEF-legality.md");
    std::fs::write(&doc, body).unwrap();
    doc
}

#[test]
fn check_r10_selects_the_direction_finding() {
    let doc = make_brief("r10", BRIEF_NAMING_A_DESIGN);
    shirabe()
        .arg("validate")
        .arg("--check")
        .arg("R10")
        .arg(&doc)
        .assert()
        .failure()
        .stdout(contains("[R10]"))
        .stdout(contains("BRIEF may not name DESIGN"));
}

#[test]
fn check_r11_selects_the_lifetime_finding() {
    let doc = make_brief("r11", BRIEF_NAMING_A_ROADMAP);
    shirabe()
        .arg("validate")
        .arg("--check")
        .arg("R11")
        .arg(&doc)
        .assert()
        .failure()
        .stdout(contains("[R11]"))
        .stdout(contains("scheduled to dangle"));
}

/// The precedence rule at the CLI: a brief naming a roadmap violates both
/// properties, and `--check R10` observes nothing because the lifetime finding
/// is the only one emitted.
#[test]
fn check_r10_is_silent_when_the_lifetime_finding_suppressed_it() {
    let doc = make_brief("precedence", BRIEF_NAMING_A_ROADMAP);
    shirabe()
        .arg("validate")
        .arg("--check")
        .arg("R10")
        .arg(&doc)
        .assert()
        .success()
        .stdout("");
}

/// The valid-codes diagnostic names the new codes, so an author who mistypes
/// one is told the range they fall in.
#[test]
fn unknown_check_code_message_names_the_legality_range() {
    let doc = make_brief("unknown-code", BRIEF_NAMING_A_DESIGN);
    shirabe()
        .arg("validate")
        .arg("--check")
        .arg("R12")
        .arg(&doc)
        .assert()
        .failure()
        .stderr(contains("R6-R11"));
}

/// The stdout marker of a `--format json` run: the versioned envelope tag. A
/// programmatic consumer tests for this BEFORE it reads the exit code, so the
/// tests below assert its presence or absence alongside the code rather than
/// the code alone. See `docs/guides/multi-consumer-cli-contract.md`.
const ENVELOPE_TAG: &str = "\"schema_version\": \"shirabe-validate/v1\"";

/// A usage error is a CLI-surface failure, not a verdict on a document, so it
/// takes the tool-error code `1` -- never `2`, which means "the run completed
/// and found violations". clap's default is exit `2` for every parse error;
/// `main` overrides it via `try_parse`. Without the override an unrecognized
/// flag and a genuinely failing document are indistinguishable to a consumer
/// reading the exit code, and the author is sent to fix content that is not
/// broken.
#[test]
fn unrecognized_flag_exits_one_with_no_envelope() {
    shirabe()
        .arg("validate")
        .arg("--not-a-real-flag")
        .arg("--format")
        .arg("json")
        .assert()
        .code(1)
        // The diagnostic goes to stderr and stdout carries no envelope: the
        // validator never ran, so there is no verdict to report.
        .stdout(contains(ENVELOPE_TAG).not())
        .stderr(contains("unexpected argument"));
}

/// The same contract for the other clap-intercepted usage error.
#[test]
fn unrecognized_subcommand_exits_one_with_no_envelope() {
    shirabe()
        .arg("frobnicate")
        .assert()
        .code(1)
        .stdout(contains(ENVELOPE_TAG).not())
        .stderr(contains("unrecognized subcommand"));
}

/// `--help` keeps clap's stdout / exit-0 routing: it is not a failure, and the
/// remap must not sweep it up.
#[test]
fn help_exits_zero_on_stdout() {
    shirabe()
        .arg("--help")
        .assert()
        .code(0)
        .stdout(contains("Workflow skills for AI coding agents"))
        .stderr("");
}

/// The other half of the discriminator: a document that genuinely fails a
/// check exits `2` AND emits an envelope, so a consumer that found the
/// envelope can trust `2` to mean violations.
#[test]
fn violating_document_exits_two_with_an_envelope() {
    let doc = make_brief("json-violations", BRIEF_NAMING_A_DESIGN);
    shirabe()
        .arg("validate")
        .arg("--check")
        .arg("R10")
        .arg("--format")
        .arg("json")
        .arg(&doc)
        .assert()
        .code(2)
        .stdout(contains(ENVELOPE_TAG))
        .stdout(contains("\"outcome\": \"violations\""))
        .stdout(contains("\"code\": \"R10\""));
}

/// A clean run exits `0` and still emits the envelope -- envelope presence
/// tracks "the validator reached a verdict", not "the verdict was bad".
#[test]
fn clean_document_exits_zero_with_an_envelope() {
    let doc = make_repo_with_doc("json-clean", "# repo\n\n## Repo Visibility: Private\n");
    shirabe()
        .arg("validate")
        .arg("--check")
        .arg("R8")
        .arg("--format")
        .arg("json")
        .arg(&doc)
        .assert()
        .code(0)
        .stdout(contains(ENVELOPE_TAG))
        .stdout(contains("\"outcome\": \"clean\""));
}
