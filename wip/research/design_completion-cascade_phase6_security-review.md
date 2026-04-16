# Security Review: completion-cascade (Phase 6)

Reviewer: Claude (security panel)
Date: 2026-04-15
Source: Security Considerations section of the completion-cascade design doc

---

## Review Scope

This review evaluates the four mitigations stated in the design's Security
Considerations section against four questions:

1. Attack vectors not considered by the design
2. Sufficiency of stated mitigations
3. "Not applicable" justifications that are actually applicable
4. Residual risk requiring escalation

The prior phase-5 security research (design_completion-cascade_phase5_security.md)
identified the raw risks. This review assesses how well the design's stated
mitigations address them, and whether anything was missed.

---

## 1. Attack Vectors Not Considered

### 1a. `case` dispatch on unvalidated basename

The cascade script dispatches to per-skill `transition-status.sh` handlers via a
`case` statement on `basename "$next"`. The design validates that the resolved path
falls within `$REPO_ROOT`, but does not describe validating that the resolved
filename prefix is one of the known artifact types (DESIGN, PRD, ROADMAP, PLAN).

A document with `upstream: docs/designs/CUSTOM-weaponized.md` passes the path
boundary check (within repo) and routes to a `handle_design` branch. That is the
intended behavior. However, the `case` expression branches on the prefix of the
basename. If the dispatch uses a glob pattern like `DESIGN-*` and the file is named
`DESIGN-evil.md`, it reaches `handle_design`, which calls the design
`transition-status.sh` against the attacker-controlled path. Because
`transition-status.sh` accepts arbitrary paths (see the actual script: it only
checks `[[ ! -f "$doc_path" ]]`), the transition script will operate on whatever
file was supplied.

The path boundary guard catches out-of-tree traversal but does not constrain which
files within the tree can be targeted. A crafted `upstream` value pointing to any
`DESIGN-*.md` file anywhere in the repo — including unrelated designs — would be
acted upon. In a large monorepo, that expands the blast radius from one file to any
file matching the dispatch prefix.

Recommended addition: after the boundary check, verify the resolved path is one of
the known artifact paths that participate in the chain (i.e., the upstream fields
form an expected chain structure starting from the supplied PLAN doc), or at minimum
that the file is tracked in git before acting on it.

### 1b. Symlink traversal bypassing `realpath` boundary check

The design specifies using `realpath` to canonicalize the `upstream` path and
rejecting results outside `$REPO_ROOT`. `realpath` resolves symlinks, so a symlink
within the repo that points outside the repo boundary is caught by this check. That
is correct.

However: if the repository itself contains a symlink whose *target* is inside the
repo but points to a sensitive file (e.g., `docs/designs/DESIGN-secret.md ->
../../private/SECRET.md` where `private/` is inside the repo root), `realpath`
resolves it to a path that passes the boundary check. The script then operates on
the symlink target, not the symlink source. Whether this is exploitable depends on
what "inside the repo" means for this project — in a multi-repo workspace with
subrepo symlinks, this is a realistic path. The risk is low in a standard
single-repo layout, but the design should acknowledge it.

### 1c. `awk` write-to-temp then `mv` in the strip operation — race condition

The compression decision (Decision 2) specifies the `strip_implementation_issues`
function as:

```sh
awk '...' "$file" > "$file.tmp" && mv "$file.tmp" "$file"
```

This uses a predictable temp file name (`$file.tmp`). If another process creates
`$file.tmp` between the `awk` write and the `mv`, the `mv` overwrites whatever that
process wrote. This is a TOCTOU (time-of-check-to-time-of-use) issue. It does not
rise to a security vulnerability in normal single-user repository workflows, but it
can cause silent data corruption if two cascade runs overlap (e.g., a CI job and a
local run). The mitigation is to use `mktemp` rather than a predictable `.tmp`
suffix. The design should specify this.

### 1d. ROADMAP feature name lookup — `grep -F` does not prevent path injection in `awk`

The design states that ROADMAP lookups and substitutions use `grep -F` (fixed-string)
and `awk`-based literal replacement. This prevents regex injection in the match
expression, which is the stated goal. However, if the feature name is used as the
first argument to an `awk` script via `-v varname="$feature_name"`, and `$feature_name`
contains a backslash sequence that `awk` interprets in string context (e.g., `\n`,
`\t`, `\\`), the substitution target is silently altered. This is not a code
execution vector, but it can cause the wrong line to go unmatched or the replacement
to contain unintended characters.

`awk -v` assignment does not protect against backslash interpretation in the variable
value. The safe alternative is to pass the value via environment variable and read it
with `ENVIRON["varname"]` in the awk body, or use `printf '%s\0'` piping. This is an
edge case (backslashes in feature names are rare), but the design claims literal
safety and this claim is incomplete.

---

## 2. Sufficiency of Stated Mitigations

### 2a. Path traversal via `upstream` field — PARTIAL

The stated mitigation (`validate_upstream_path` using `realpath`, rejecting paths
outside `$REPO_ROOT`) addresses out-of-tree traversal. It is necessary and correct
as far as it goes.

What it does not address:
- Symlink targets (noted above in 1b)
- Within-repo targeting of unrelated tracked files (noted above in 1a)
- Whether the path is a regular file (as opposed to a device, named pipe, or other
  special file) — `realpath` resolves all of these

The mitigation is necessary but not sufficient on its own. The design should add a
check that the resolved path is a regular file (`[[ -f "$next" ]]`) and that it
matches the expected prefix pattern for one of the cascade artifact types.

### 2b. GitHub URL injection in `check_issue_closed` — SUFFICIENT

The stated mitigation (parse URL to extract owner, repo, and issue number; validate
owner/repo against current repo slug; use `gh issue view <number> --repo
<owner/repo>`) closes the two named risks: command injection via shell metacharacters,
and cross-repo token probing.

One nuance: the design does not specify how it obtains the "current repository slug"
for comparison. If it reads this from `git remote get-url origin`, a repository with
a non-standard remote name or a multi-remote setup could supply an incorrect baseline.
This is a configuration edge case, not an attack vector, but the design should specify
that the origin remote is the authoritative source and document the assumption that
origin points to the canonical repository.

The mitigation is sufficient for the named threat. The implementation should use
`gh issue view` with `--json state` to avoid parsing free-form output.

### 2c. Auto-push blast radius — SUFFICIENT AS DESIGNED, but documentation gap

The `--push` flag separation is the correct mitigation. Without `--push`, the script
stages and prints a summary; the caller decides whether to push. This contains the
blast radius to the staging area, which is reversible (`git restore --staged`).

The design does not specify what the printed summary must include. To be meaningful,
the summary should list each file that would be committed (with its before/after
status) so the caller can verify the diff before pushing. If the summary is just
"cascade complete", it provides no useful check. The design should specify the summary
format.

### 2d. ROADMAP text substitution with special characters — PARTIAL

The design specifies `grep -F` (fixed-string) and `awk`-based literal replacement.
`grep -F` is the correct tool for fixed-string matching. Using `awk` for the
replacement (instead of `sed`) avoids the `/` and `&` metacharacter issues with
`sed` replacement strings.

However, the `awk -v` assignment issue with backslash sequences (noted in 1d)
means the design's claim of full literal safety is incomplete. The mitigation covers
the most common injection paths but misses the `awk` variable escaping edge case.

For a script that will be used primarily by trusted contributors on well-formed
ROADMAP docs, this is acceptable in practice. But the design should not claim
unconditional literal safety without acknowledging the `awk -v` limitation.

---

## 3. "Not Applicable" Justifications

The design's Security Considerations section does not use an explicit "not applicable"
label. The closest equivalent is the residual risk statement:

> "The threat model assumes documents in the repository are authored by trusted
> contributors. No external inputs are processed."

This deserves scrutiny.

### The trusted-contributor assumption

The stated threat model is accurate for direct attacks: an external attacker cannot
push a crafted document without repository write access. However, "trusted contributor"
does not mean "error-free contributor." The realistic threat in a developer tool is
misconfiguration, not malice: a contributor who copies a DESIGN doc from another
project without updating the `upstream` field, or who renames a file and updates
references manually with an error.

The path validation mitigations are primarily protective against mistakes, not
attacks. Framing them only as an attack surface may cause future implementers to
consider relaxing them when "all contributors are trusted." The design should
reframe the mitigations as correctness guards first (protecting against accidental
misconfiguration) and security guards second (protecting against unlikely but
possible repository-level attacks, e.g., a compromised contributor account or a
PR from a fork with a crafted document that a maintainer merges without inspection).

### External input via PR review workflow

The design states "no external inputs are processed." This is true at runtime: the
script reads only files present in the working tree. However, the script is designed
to be called from within a CI/agent workflow triggered by a merge event. If that
workflow runs on a fork-sourced PR, the documents in the merged branch were authored
by an external contributor. GitHub's own CI safety model (no secrets on fork PRs)
mitigates the token exposure risk, but the path validation and URL validation
mitigations are relevant for any workflow that processes cascade on fork-originated
content.

This does not require design changes, but the "no external inputs" residual-risk
statement should be narrowed to "no externally sourced runtime inputs beyond the
repository working tree" to be accurate.

---

## 4. Residual Risk Assessment

### Risks that do not require escalation

- **Within-repo untargeted file access**: An `upstream` value pointing to an
  unrelated tracked file within the repo could cause the cascade to modify it. This
  is bounded by the repo boundary check, is unlikely in practice, and the fix (verify
  the file is in the expected chain) is straightforward. Document as a known gap for
  implementation.

- **`awk -v` backslash interpretation**: Affects ROADMAP substitution only. Requires
  a backslash in a feature name, which is unusual. Low probability, low impact
  (incorrect substitution, not data exfiltration). Note for implementation, not
  escalation.

- **Predictable `.tmp` file in compression**: Cosmetic race condition in single-user
  workflow. Use `mktemp` in implementation to close it cheaply.

- **Summary content not specified**: Risk that the `--push` gate provides theater
  rather than a real check. Fixable by specifying the summary format in the design.

### Risk that warrants a design note

- **Symlink traversal within repo**: If the repository contains symlinks (common in
  monorepo setups where one repo symlinks into another), the `realpath` boundary
  check may approve paths that are logically outside the intended document set.
  This is not high-severity, but the design should explicitly state whether symlinks
  are rejected or permitted and document the assumption about the repo layout.

### No escalation required

None of the identified risks are high-severity under the project's stated threat
model. The most significant gap — within-repo untargeted file access — is bounded,
reversible (git tracks the pre-cascade state), and easy to address at the
implementation stage. The design's core mitigations are structurally correct.

---

## Summary Table

| Item | Assessment | Action |
|------|------------|--------|
| Path traversal via `upstream` | Mitigation necessary but not sufficient — within-repo untargeted access not covered | Add: verify resolved path is tracked git file of expected artifact type |
| GitHub URL injection | Mitigation sufficient; minor implementation note on remote slug sourcing | Note for implementation |
| Auto-push blast radius | Mitigation sufficient; summary format unspecified | Specify summary format in design |
| ROADMAP text substitution | Mitigation mostly correct; `awk -v` backslash escaping gap | Note for implementation |
| `case` dispatch on basename | Not addressed in design; unrelated tracked files can be targeted within repo | Add: restrict dispatch to files in the upstream chain only |
| Symlink traversal within repo | Not addressed; low severity in standard single-repo layout | Add: document assumption or add symlink rejection |
| Temp file naming in strip | Not addressed; low severity TOCTOU | Use `mktemp` in implementation |
| Trusted-contributor framing | Residual-risk statement too narrow; excludes fork PR and misconfiguration scenarios | Reframe mitigations as correctness guards |

---

## Verdict

The design's security analysis identifies the right risk categories and the stated
mitigations are structurally sound. Two gaps need closing before implementation:
the `case` dispatch does not restrict to files in the expected upstream chain (any
within-repo DESIGN-*.md can be targeted), and the `--push` summary content is
unspecified (making the gate nominal rather than functional). The remaining items
are implementation notes.

No risks require escalation outside the design review process.
