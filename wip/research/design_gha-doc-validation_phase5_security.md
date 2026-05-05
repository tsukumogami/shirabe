# Security Review: gha-doc-validation

## Dimension Analysis

### External Artifact Handling

**Applies:** Yes — scoped to the local distribution path only.

The GHA path does not download external artifacts at runtime. It checks out shirabe's
own source at `${{ github.action_ref }}` and compiles it. Content from the caller's
repo (Markdown + YAML frontmatter) is read as data, never executed or eval'd. The CLI
is a static reader: it parses files, runs check functions over an in-memory `Doc`
struct, and emits annotation strings.

The local distribution path (tsuku + `install.sh`) does download an external binary.
The `install.sh` script downloads the binary and `checksums.txt` from GitHub Releases,
performs SHA256 verification before installation, and installs to `~/.shirabe/bin/`.

**Risk and severity:** Low. The checksum verification closes the tampering window for
an in-transit substitution. The remaining trust question is whether the release artifact
itself is authentic — addressed under Supply Chain below. The curl-pipe-to-bash pattern
is not used here; the script verifies before installing, which is the right pattern.

**Residual exposure:** If GitHub Releases infrastructure is compromised, a tampered
binary and a tampered `checksums.txt` could be served together. SHA256 verification
over content from the same host does not protect against a compromised host — it only
protects against in-transit corruption or substitution by a third party.

**Mitigation:** Document this boundary in Security Considerations: `install.sh`
verifies integrity (SHA256) but not authenticity (code signing). Users in high-trust
environments who need authenticity guarantees should build from source. If GoReleaser
gains `goreleaser/goreleaser-action` provenance support (SLSA level 2+), enable it.

---

### Permission Scope

**Applies:** Yes — narrowly.

**GHA reusable workflow (caller's repo):**
The workflow runs on `ubuntu-latest` with default GitHub Actions permissions. It
requires:
- Read access to the caller's repo (checkout for `git diff`, file access for validation)
- No write permissions to the caller's repo
- Read access to the shirabe repo (second `actions/checkout` for source)
- No network egress beyond GitHub infrastructure (checkout, cache)

The workflow does not request elevated permissions. Default GITHUB_TOKEN permissions
in the caller context are sufficient. The `GITHUB_TOKEN` is not passed to the shirabe
build step or the CLI invocation, so the binary runs without any GitHub credentials.

**`git ls-files HEAD` shellout:**
`checkPlanUpstream` runs `git ls-files HEAD` in the caller's repo working directory.
This is a read-only git command. It cannot modify the repo, make network calls, or
access secrets. The only input it receives is the `upstream` field value from a
frontmatter field — a string used to check whether a path is tracked. That string
goes through Go's `exec.Command` as an argument, not a shell string; shell injection
is not possible if the argument is passed as a separate element in the args slice (not
concatenated into a shell command string). The implementation must use `exec.Command("git", "ls-files", "HEAD")` and filter output in Go, not `exec.Command("sh", "-c", "git ls-files HEAD | grep "+upstream)`.

**Severity:** Low overall. The shellout risk is implementation-level, not architectural.

**Mitigation:** Confirm in code review that `checkPlanUpstream` uses `exec.Command`
with discrete arguments, not a shell interpolation of the `upstream` field value.

**`install.sh` local permissions:**
The install script writes to `~/.shirabe/bin/`. It does not use sudo, does not write
system-wide paths, and does not modify `PATH` permanently without explicit user
consent. Scope is appropriately minimal.

---

### Supply Chain or Dependency Trust

**Applies:** Yes — two trust chains.

**GHA trust chain:**
The reusable workflow is pinned to `${{ github.action_ref }}`, which resolves to the
tag or SHA the caller references in `uses: tsukumogami/shirabe/.github/workflows/validate-docs.yml@v1`.
If a caller pins to `@v1` (a mutable tag), a compromised tag push by a shirabe
maintainer or a stolen maintainer credential would affect all callers on the next run.
This is the standard reusable workflow trust model — callers who need stronger
guarantees should pin to a full commit SHA.

The third-party actions used in the workflow (`actions/checkout@v4`,
`actions/cache@v4`) are GitHub-owned. They are widely audited and subject to
GitHub's own security practices. Version pinning to `@v4` is a mutable reference;
SHA-pinning would be stronger but is not the current workspace convention.

**Go dependencies:**
The `shirabe` binary is built from source using `go.mod` and `go.sum`. `go.sum`
records expected content hashes for all direct and transitive modules. Go's module
proxy and checksum database (sum.golang.org) verify these hashes at build time. This
is a well-established supply chain control. The dependency surface is intentionally
small: `gopkg.in/yaml.v3` (frontmatter parsing) and `github.com/spf13/cobra` (CLI
framework) are the primary additions; both are widely used and actively maintained.

**Release binary trust chain:**
GoReleaser runs in GitHub Actions CI on a tag push. The release workflow uses
`goreleaser/goreleaser-action` to build and `gh release upload` to attach artifacts.
The release does not currently include code signing or SLSA provenance attestation.
Checksums are attached, verifying integrity but not authenticity.

**Severity:** Low-to-medium. The mutable `@v1` tag reference is a standard,
accepted risk for GHA reusable workflows. The release binary chain has a meaningful
authenticity gap — a compromised release workflow could replace artifacts and
regenerate checksums. This is a real but industry-typical risk for projects not yet
implementing signing.

**Mitigations:**
- Document that callers who need a stronger integrity guarantee can pin to a commit SHA
  in their `uses:` reference.
- Track SLSA provenance or sigstore signing as a v2 improvement once the GoReleaser
  pipeline is established.
- Ensure the release workflow uses OIDC-based GitHub tokens (not long-lived secrets)
  for the `gh release upload` step — this limits blast radius if the workflow is abused.

---

### Data Exposure

**Applies:** No — with one narrow note.

The CLI reads Markdown doc files from the caller's repo. It does not transmit any
file content over the network. It does not write to any external destination. It
does not log file contents, does not write temporary files, and does not access
secrets or environment variables beyond what is required for flag parsing
(`--visibility`, `--custom-statuses`).

The `github.repository_visibility` value is passed to the CLI as the `--visibility`
flag. This is a metadata value about the caller's repo (public or private), not
content. It is used only to determine whether to apply the VISION public-repo check.
It does not leave the runner.

The `--custom-statuses` flag accepts user-supplied YAML. It is parsed with
`gopkg.in/yaml.v3` into a `map[string][]string`. The parsed value is used to replace
valid-status enums in `FormatSpec`. It is not logged, not transmitted, and not written
to disk. Malformed YAML causes a parse error and exit — it does not trigger any
external call.

The `git ls-files HEAD` shellout emits a file list from the caller's repo. This
output is consumed in-process by the Go binary and is not transmitted or logged.

**No data exposure risk exists in the current design.** The tool is intentionally
architected as a pure local analysis tool: reads files, writes annotation strings to
stdout, exits.

**Narrow note on `--custom-statuses` input validation:**
The `custom-statuses` input is user-supplied YAML from the caller's workflow file.
YAML parsing with `yaml.v3` is memory-safe. However, a maliciously large input
(e.g., a list with millions of status values) could cause memory pressure. In practice
this comes from the caller's own workflow YAML, so the threat actor would have to
control the caller's repo. No cross-tenant exposure exists.

---

## Recommended Outcome

OPTION 2: Document considerations — draft the Security Considerations section text for the design doc.

Proposed Security Considerations section for insertion into DESIGN-gha-doc-validation.md:

---

## Security Considerations

**Binary integrity vs. authenticity for local install.** `install.sh` verifies the
downloaded binary against `checksums.txt` using SHA256 before installation. This
closes the window for in-transit substitution or corruption. It does not verify that
the release artifact itself is authentic — a compromised release pipeline could produce
a tampered binary and a matching `checksums.txt` simultaneously. This is the standard
trust model for projects without code signing. Users who require authenticity guarantees
should build from source (`go build ./cmd/shirabe`). Adding SLSA provenance attestation
or sigstore signing is tracked as a v2 improvement.

**Mutable tag references in GHA callers.** Callers who reference the reusable workflow
as `uses: tsukumogami/shirabe/...@v1` take a mutable tag dependency. This is the
standard reusable workflow trust model. Callers with stricter requirements can pin to a
full commit SHA. A compromised or mistakenly force-pushed `v1` tag would affect all
callers on their next run; shirabe should protect the `v1` tag with branch protection
rules that require PR review for any tag move.

**`git ls-files HEAD` shellout argument handling.** `checkPlanUpstream` shells out to
`git ls-files HEAD` to verify that the `upstream` field value is tracked in the caller's
repo. The implementation uses `exec.Command` with discrete arguments (not shell
interpolation), so a malformed `upstream` field value cannot inject shell commands.
This should be confirmed in code review.

**Reusable workflow permissions.** The workflow requires only read access to the caller
repo. It does not request write permissions, does not receive `GITHUB_TOKEN`, and does
not make network calls beyond GitHub infrastructure (checkout, module cache). The CLI
binary runs without any GitHub credentials.

**`custom-statuses` input bounds.** The `--custom-statuses` flag accepts
user-supplied YAML, parsed by `yaml.v3`. The threat actor with access to this input
also controls the caller's repo; no cross-tenant exposure exists. The implementation
should impose a reasonable size limit on the flag value to prevent accidental
resource exhaustion from a malformed input.

---

## Summary

The design is sound from a security standpoint. No high-severity risks were identified.
The GHA path builds from source (no external binary download at CI runtime), the CLI is
a pure local analysis tool with no network access or file writes, and the one shellout
(`git ls-files HEAD`) is scoped and must be implemented with discrete `exec.Command`
arguments to be safe. The local distribution path (install.sh) correctly verifies SHA256
before installing, though it does not verify authenticity — a gap that is industry-typical
and documented as a v2 improvement target. OPTION 2 is recommended: the design does not
need structural changes, but the Security Considerations section should be drafted to
surface the integrity/authenticity boundary, the mutable tag trust model, and the
shellout argument-handling requirement for code review.
