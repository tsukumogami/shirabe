# Security Review: DESIGN-gha-doc-validation (Phase 6)

Source: `docs/designs/DESIGN-gha-doc-validation.md`
Prior analysis: `wip/research/design_gha-doc-validation_phase5_security.md`
Review date: 2026-05-04

---

## Scope

This review evaluates the Security Considerations section of
DESIGN-gha-doc-validation.md against four questions:

1. Are there attack vectors not considered?
2. Are the mitigations sufficient for identified risks?
3. Is any "not applicable" justification actually applicable?
4. Is there residual risk that should be escalated rather than documented?

The design's Security Considerations section covers five topics: binary integrity vs.
authenticity, mutable tag references, `git ls-files HEAD` shellout argument handling,
reusable workflow permissions, and `custom-statuses` input bounds.

---

## 1. Attack Vectors Not Considered

### 1a. Annotation injection via doc content

The CLI reads Markdown doc files and emits annotation strings of the form
`::error file=<path>,line=<N>::[FC02] message`. The `message` component includes
values extracted from the doc's frontmatter — specifically, the `status` field value
(in FC02 errors), the `upstream` field value (in R6 errors), and section heading text
(in FC03 errors).

If a doc contains a `status` field with a value like `foo\n::error
file=/etc/passwd,line=1::injected`, and the message is written to stdout without
sanitizing newlines, a GHA runner could process the injected annotation command. Go
string formatting with `fmt.Fprintf` does not automatically strip newlines from
embedded strings.

**This vector is not addressed in the design's Security Considerations section.**

Severity: Low-to-medium. A malicious doc author in the caller's repo can inject
arbitrary GHA annotation commands into the workflow output. This could be used to
produce misleading CI results (fake error annotations on other files, fake notice
annotations suppressing real ones). It cannot escalate permissions or access secrets
given the read-only workflow context. However, it can corrupt CI output and mislead
code reviewers.

Mitigation required: Before including any frontmatter value in an annotation string,
strip or reject newlines and carriage returns. The annotation formatter in
`internal/annotation/annotation.go` is the right place — sanitize before formatting,
not at each call site.

### 1b. Path traversal via `file=<path>` annotation field

GHA annotations include `file=<path>` where `<path>` comes from the doc file's path
as supplied on the CLI's argument list. The workflow passes `<files>` derived from
`git diff --name-only`. These paths are repo-relative and should be safe. However, if
a downstream caller constructs the file list in an unusual way (e.g., absolute paths,
paths with `..` components), the annotation could reference files outside the expected
context. GHA annotations with out-of-repo paths are typically ignored by the UI, so
the practical impact is low. This is a minor gap worth documenting but not a
significant risk given the controlled input source.

### 1c. `go.sum` freshness and dependency confusion

The design notes that `go.sum` records expected content hashes. This is correct and
adequate at build time. However, the module cache action (`actions/cache`) stores the
Go module cache keyed on `go.sum`. A cache poisoning scenario — attacker pollutes the
cache before `go.sum` changes — would be caught at build time when Go verifies against
`go.sum`. This is not a new risk vector, but it confirms that the
`actions/cache`-keyed-on-`go.sum` approach is sound and doesn't need additional
controls.

### 1d. Third-party action SHA pinning absent

The workflow uses `actions/checkout@v4` and `actions/cache@v4`. These are mutable tag
references. The design's Security Considerations section addresses the mutable
`@v1` tag in the reusable workflow itself, but says nothing about the third-party
actions the workflow depends on. A compromised `actions/checkout@v4` tag (unlikely
given GitHub ownership, but nonzero) would affect the build step. SHA pinning for
these upstream actions is a common hardening practice recommended by OSSF Scorecard
and GitHub's own security hardening guide.

**This vector is not addressed in the design's Security Considerations section.**

Severity: Low. GitHub-owned actions have a much smaller compromise surface than
arbitrary third-party actions. However, the omission means the design doesn't
acknowledge the risk or make a documented decision to accept it.

Mitigation: Acknowledge in Security Considerations that `actions/checkout@v4` and
`actions/cache@v4` use mutable tag references. Document a decision to accept this
(consistent with workspace convention) or commit to SHA-pinning these in the initial
implementation.

### 1e. GHA `workflow_call` inputs not validated before CLI invocation

The `custom-statuses` item is discussed. However, the `docs-path` input (mentioned in
Decision 4 as an input to the reusable workflow) and any future string inputs are also
passed into the workflow environment. If `docs-path` is used to scope `git diff`
output or passed as a shell glob, a caller supplying a crafted `docs-path` value could
cause unintended file access patterns. The design doesn't specify how `docs-path` is
consumed, but the risk exists if it flows into a shell command rather than being
validated before use.

**Partially addressed:** `custom-statuses` is discussed; `docs-path` is not.

---

## 2. Sufficiency of Mitigations for Identified Risks

### Binary integrity vs. authenticity (addressed in design)

The design correctly characterizes the gap: SHA256 verification protects against
in-transit corruption but not a compromised release pipeline. The mitigation — build
from source for high-assurance environments, SLSA provenance as a v2 improvement — is
appropriate and honest. This is industry-standard for the current state.

**Verdict: Sufficient for v1. The v2 escalation path is clearly stated.**

### Mutable tag references (addressed in design)

The design recommends protecting the `v1` tag with branch protection rules requiring
PR review for any tag move. This is the right control. However, it's stated as
"shirabe should protect" — a recommendation rather than a requirement. The mitigation
should be a concrete action item tied to the release phase, not a suggestion.

**Verdict: Mitigation is correct but underspecified. "Should" needs to become a
tracked action before v1 ships. The branch protection setup belongs in Phase 5 or in
the implementation checklist — not left as a post-release concern.**

### `git ls-files HEAD` shellout (addressed in design)

The design correctly identifies the risk and the correct mitigation (discrete
`exec.Command` arguments). It defers confirmation to code review, which is appropriate.

However, the design doesn't mention that `checkPlanUpstream` runs in the caller's repo
working directory. The working directory must be the caller's repo root, not the
`.shirabe-src` checkout directory. If the working directory is wrong, `git ls-files`
could query the shirabe source tree rather than the caller's repo — producing incorrect
results (always passing or always failing upstream checks). This is a correctness gap
with indirect security implications: an attacker who knows the working directory is
wrong could commit an `upstream:` field that would fail in any correct environment but
passes due to the incorrect directory.

**Verdict: Core shellout mitigation is sufficient. Working-directory correctness for
the shellout is an unaddressed implementation requirement.**

### Reusable workflow permissions (addressed in design)

The design states the workflow does not receive `GITHUB_TOKEN`. This is worth
confirming in the workflow YAML. By default, reusable workflows do inherit the
caller's `GITHUB_TOKEN` context — the design should explicitly set
`permissions: contents: read` (or similar) in the workflow definition to enforce
minimum privilege rather than relying on the caller's default configuration.

**Verdict: The stated permission model is correct but needs to be enforced in the
workflow YAML, not just described. Relying on "default" permissions is insufficient —
defaults vary by organization policy and repo settings.**

### `custom-statuses` input bounds (addressed in design)

The design recommends a "reasonable size limit." This is vague. Without specifying the
limit (e.g., total flag value bytes, maximum entries per format, maximum status string
length), the implementation is likely to omit it. A concrete limit (e.g., 64KB total
YAML input, 50 status values per format) should be specified or the control won't
ship.

**Verdict: Mitigation is directionally correct but underspecified. Won't ship as
written.**

---

## 3. "Not Applicable" Justifications — Applicability Check

The design's Security Considerations section doesn't use "not applicable" language
explicitly, but the prior phase-5 analysis (from which the design section was derived)
made one implicit N/A judgment: **data exposure is not applicable** because the CLI is
a "pure local analysis tool."

This judgment is broadly correct but has one edge case not examined: **the
`git ls-files HEAD` output.** The phase-5 analysis states this output "is consumed
in-process by the Go binary and is not transmitted or logged." This is correct for the
normal execution path. However, if the binary panics or encounters an unexpected error
after running the shellout but before consuming the output, Go's panic handler could
write the goroutine stack to stderr, which GHA captures. A stack trace could include
the `upstream` field value or partial `git ls-files` output. This is a minor edge case
in a read-only context, but it means the data-exposure "N/A" is not fully accurate
under error conditions.

**Verdict: The N/A is directionally correct but overstated. The design should
acknowledge that error output (stderr) could include file path values from the caller's
repo under abnormal exit conditions.**

---

## 4. Residual Risk Assessment — Escalate vs. Document

### Risks appropriate to document (not escalate)

- SHA256-only integrity without authenticity for `install.sh` binary. Standard
  industry practice, correctly described, v2 path identified.
- Mutable `@v1` tag for callers. Standard reusable workflow convention, documented.
- Mutable `actions/checkout@v4` and `actions/cache@v4` references. Low severity,
  GitHub-owned, should be acknowledged.
- `custom-statuses` resource exhaustion from malformed input. No cross-tenant
  exposure, same-repo threat actor.

### Risks that require concrete action before shipping (not just documentation)

**Annotation injection via newlines in frontmatter values.** A contributor to a
downstream repo can craft a `status:` field value containing newlines to inject
arbitrary GHA annotation commands. This corrupts CI output for that repo's maintainers.
The fix is straightforward (sanitize in the annotation formatter) and must happen
before v1 ships. This is not escalation-worthy — it's a standard output-sanitization
requirement — but it must be a tracked implementation requirement, not left to code
review chance.

**Explicit permission declaration in workflow YAML.** The workflow must declare
`permissions: contents: read` (and nothing else) explicitly, rather than relying on
caller defaults. This is a one-line fix with meaningful defense-in-depth value.

**Mutable tag branch protection.** The design says "shirabe should protect the `v1`
tag." This must be a concrete deliverable in Phase 5's checklist, not a post-release
suggestion.

**Working-directory correctness for `git ls-files`.** The shellout must run in the
caller's repo working directory. This must be confirmed as an explicit implementation
requirement.

### Risks to escalate

None. No single identified risk warrants escalation beyond the design document. The
highest-severity gap — annotation injection — is fixable at the implementation level
with a small code change and should not block the design from moving forward. The
trust-model gaps (mutable tags, unsigned binaries) are industry-standard and correctly
described as such.

---

## Summary of Findings

| Finding | Severity | Action |
|---------|----------|--------|
| Annotation injection via newlines in frontmatter values | Low-medium | Required implementation fix (sanitize in annotation formatter) |
| Third-party action mutable tag references not acknowledged | Low | Add to Security Considerations section |
| Explicit `permissions:` declaration missing from workflow | Low | Required implementation step |
| Mutable `v1` tag protection stated as "should" not "must" | Low | Harden to tracked action item in Phase 5 checklist |
| Working-directory correctness for `git ls-files` shellout | Low | Add as explicit implementation requirement |
| `custom-statuses` size limit underspecified | Low | Specify concrete limits (e.g., 64KB, 50 values/format) |
| Data-exposure "N/A" overstated for error/panic path | Minimal | Soften claim; acknowledge stderr under abnormal exit |
| Binary authenticity gap for `install.sh` | Low | Documented correctly; v2 path adequate |

### Security Considerations Section Assessment

The existing section is accurate and covers the most significant risks. Three gaps
should be addressed before implementation begins:

1. Add a note on annotation injection and the sanitization requirement.
2. Change "should" to a concrete action for `v1` tag branch protection.
3. Acknowledge third-party action mutable tag references.

The section does not require structural revision. It requires targeted additions and
one strengthened commitment.
