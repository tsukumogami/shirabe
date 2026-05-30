# Security Review: shirabe-cli-rust-rewrite

## Dimension Analysis

### External Artifact Handling

**Applies:** Yes — the validator processes untrusted markdown files
(authored by PR contributors in calling repos) and emits strings that
GitHub Actions interprets as workflow commands (`::error file=…::…`,
`::notice file=…::…`).

**Risks:**

1. **GHA annotation injection.** A PR author could craft frontmatter
   field values containing `\n::error file=path::pwned` to inject
   spurious annotation lines into the workflow output, potentially
   masking real failures or surfacing fake errors against arbitrary
   paths. Severity: medium. The Go implementation closes this through
   `internal/annotation/annotation.go::sanitize`, which strips `\n` and
   `\r` before composing the annotation line.

2. **YAML parser exploitation.** A pathological YAML document could
   attempt to trigger billion-laughs (anchor expansion bomb), excessive
   memory allocation, or quadratic parser behavior. Severity: low —
   shirabe's checks only read top-level scalar keys; nested structures
   and anchor expansion are not introspected by any check. saphyr is
   pure Rust with no `unsafe` blocks in its public API.

3. **Path traversal via `upstream:` field.** The R6 check
   (`checkPlanUpstream`) calls `os.Stat` and `git ls-files` on the
   value of the `upstream:` field. A malicious PR could set
   `upstream: ../../../etc/passwd` to test what happens when the path
   exists but is not git-tracked, or test for the existence of
   arbitrary paths via the success/failure pattern of the check.
   Severity: low — the failure output discloses only whether the path
   exists and whether git tracks it; the file's contents are never
   read, transmitted, or quoted in error messages. Both pieces of
   information (existence, git-tracking) are already low-value because
   the CI runs against a fresh checkout of the PR branch where the
   attacker controls the filesystem contents.

**Mitigations (already in the design):**

- Decision 1 (saphyr) inherits the parser's correctness/safety
  posture; saphyr's pure-Rust implementation is verified.
- `Security Considerations` section in the design doc preserves the
  `sanitize` function in `shirabe-validate::annotation` byte-for-byte
  with the Go implementation. The parity fixture's corpus includes a
  synthetic case with `\n` in field values to exercise the path on
  every test run — this is explicit in the design's "Annotation
  injection" subsection.
- R6's error message contains only the field value, sanitized; no
  file contents are read or transmitted. The Rust port preserves this
  contract.

**Residual risk:** Annotation injection via the binary's own panic
output to stderr — if the Rust runtime panics, the panic message
(which could include attacker-controlled YAML content) would be
written to stderr without sanitization. Severity: low because (a)
GHA annotations are emitted from stdout, not stderr, and the host
runner does not parse stderr for annotation lines; (b) panic-on-
malicious-input would itself be a parser bug worth fixing; (c) the
parity fixture would catch any divergence in panic surfaces. No
design change recommended.

### Permission Scope

**Applies:** Yes — the validator opens files, invokes `git` as a
subprocess.

**Risks:**

1. **Read-only file access.** `parse_doc` calls `std::fs::read` on
   each path passed on the command line. No recursive walk, no
   symlink following beyond what the OS does for `open`. Severity:
   none — the caller workflow (in `validate-docs.yml`) constructs the
   file list via `git diff` on the PR's changed files, scoped to the
   caller's checkout. The validator cannot reach files outside the
   caller-provided list.

2. **`git ls-files` subprocess.** R6 invokes `git ls-files
   --error-unmatch -- <path>`. The Go implementation uses
   `exec.Command`, which spawns the process directly (no shell). The
   Rust port uses `std::process::Command`, which similarly does not
   invoke a shell. The `<path>` argument is passed as a separate
   `arg()` call and not string-interpolated; PR-authored `upstream:`
   values cannot trigger shell expansion. The `--` separator is
   preserved so paths starting with `-` are not treated as flags.
   Severity: none — both runtime APIs are inherently safe against
   shell injection when used correctly, and the design preserves the
   correct usage.

3. **No network access.** The validator does not make HTTP requests
   or DNS lookups. The Go binary has no `net/http` imports and the
   Rust port adds none.

**Residual risk:** none.

### Supply Chain or Dependency Trust

**Applies:** Yes — the rewrite introduces new Rust dependencies
(`saphyr`, `clap`, and their transitive deps).

**Risks:**

1. **`saphyr` is at v0.0.6 (0.0.x version line).** The library is
   pre-1.0 by SemVer convention; the project's own README notes the
   API may change. Severity: low — the design names this explicitly
   in Decision 1 and commits to pinning to a specific patch version
   via `Cargo.toml`. The fallback to `saphyr-parser` event-level
   parsing is documented if the high-level API drifts.

2. **`clap` is widely adopted and v4 is stable.** No supply-chain
   concern; `clap-derive` (the proc-macro half) is a `cargo-deny`-
   green-listed dependency.

3. **Transitive deps from saphyr (`hashlink`).** `hashlink` is a
   small order-preserving HashMap implementation, widely used,
   actively maintained. No specific concern.

4. **Release pipeline changes.** The existing GoReleaser-based
   release workflow swaps to `cargo build --release`. The release
   signing/checksum step is unchanged. Severity: low — the binary
   that ships is built from the same source repo on the same CI
   runners as before; only the build tool changes.

**Mitigations:**

- Pin saphyr to a specific patch version in `Cargo.toml` (committed
  as part of SR1 phase 1).
- `Cargo.lock` is committed (standard practice for binary crates;
  ensures reproducible builds in CI).
- The existing `cargo-deny` or `cargo-audit` integration is added to
  the validate-docs CI (or established as part of SR1 phase 1)
  — this is a useful preventive measure though not blocking for
  SR1's contract.

**Residual risk:** A saphyr 0.0.x security advisory between SR1
landing and the next shirabe release would require a patch bump.
The reusable workflow consumers pin to a specific shirabe tag, so
they get the dependency pin transitively; the supply-chain trust
horizon is bounded by shirabe's release cadence.

### Data Exposure

**Applies:** Limited — the validator only emits the file path and a
sanitized message in each annotation. It does not read or transmit
the file's body content beyond what the checks themselves require
(which is the document's body lines for FC03's `## Status` body
match).

**Risks:**

1. **File contents in error messages.** The seven checks build error
   messages from: the file path, the schema version string, the
   status value, missing field/section names, and the body's status
   line text. The body status line text in particular *is* file
   content — if a malicious VISION doc set `## Status` followed by
   sensitive content as the next line, FC03's error would echo that
   sensitive content back into the annotation. Severity: low — only
   the *first non-blank line* after `## Status` is echoed (per
   `checkFC03` in the Go implementation), and the sanitizer strips
   `\n`/`\r`; if a PR author writes sensitive content as their `##
   Status` body, the secrecy was already breached at PR-author time.
   The validator is not the exposure surface.

2. **No external transmission.** The validator writes only to
   stdout/stderr in the local CI runner; no telemetry, no remote
   logging. No data leaves the runner.

**Residual risk:** none.

## Recommended Outcome

**OPTION 2 — Document considerations.**

The design already has a Security Considerations section drafted in
Phase 0 covering the load-bearing risks (annotation injection, git
subprocess, file system access, "what changes vs. the Go binary").
The Phase 5 review surfaced two refinements worth folding in:

1. **Make explicit the residual-risk position on panic-to-stderr**
   (low risk, no design change). Note the GHA annotation parser
   reads stdout only.
2. **Make explicit the supply-chain position on saphyr's 0.0.x
   version line** (pin patch version, document fallback). This is
   already in the design's body where Decision 1 discusses saphyr;
   the security section should cross-reference it.
3. **Note the FC03 echo of `## Status` body content** as a
   data-exposure consideration the validator inherits from the Go
   implementation. Severity is low (the exposure pre-exists the
   validator) but a future maintainer should know the constraint
   is intentional.

No design changes required. No loop back to Phase 3 or 4. Apply the
three refinements to the Security Considerations section and
proceed to Phase 6.

## Summary

The design's security posture is preservation: the Rust binary
processes the same inputs through the same checks and emits the same
outputs as the Go binary, including the load-bearing `sanitize`
function. The four review dimensions surface one medium-severity risk
(GHA annotation injection) already mitigated by the design, plus
three low-severity considerations worth documenting but not requiring
design change. Apply small refinements to Security Considerations,
then proceed to Phase 6.
