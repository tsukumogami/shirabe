# Security Review: DESIGN-release-process

## Scope

Review of `docs/designs/current/DESIGN-release-process.md` focusing on the
Security Considerations section and overall attack surface.

---

## 1. Attack Vectors Not Considered

### 1a. Race condition between release commit and finalize-release

The design has main briefly containing the real version before finalize-release
resets it to `0.0.0-dev`. If a PR merges to main between the release commit
push and the finalize-release job, one of two things happens:

- The finalize-release push fails because main has moved forward (non-fast-forward).
- The finalize-release force-pushes or rebases, potentially losing the intervening commit.

The design doesn't address this window. In practice it's narrow and shirabe
releases infrequently, but the failure mode should be documented. Koto's
finalize-release has the same exposure, so this isn't shirabe-specific, but
it's still an uncovered vector.

**Severity: Low.** Operational inconvenience, not a security breach. The
sentinel would remain at the release version until someone notices.

**Recommendation:** Add a note that finalize-release should pull before
committing, or use `--force-with-lease` so it fails cleanly rather than
silently. Alternatively, document the manual recovery procedure.

### 1b. Tag overwrite / deletion attack

If an attacker (or compromised PAT) deletes and recreates a tag pointing to a
different commit, users pulling that version get different code. The design
relies on annotated tags created by the /release skill, but doesn't mention
tag protection rules.

GitHub supports tag protection rules that prevent deletion/overwrite of tags
matching patterns (e.g., `v*`). The design doesn't mention enabling these.

**Severity: Medium.** Tag tampering could deliver wrong code to marketplace users.

**Recommendation:** Add tag protection rules for `v*` tags to the
implementation checklist. This is a one-time GitHub settings change.

### 1c. RELEASE_PAT compromise scope

The design correctly specifies fine-grained PAT scoped to shirabe only. However,
the finalize-release job uses this PAT to bypass branch protection and push
directly to main. If the PAT leaks (e.g., through a workflow log or a
dependency supply chain attack), an attacker can push arbitrary commits to main
without review.

The design mentions this is "intentional and consistent with koto" but doesn't
discuss PAT rotation, expiration, or monitoring.

**Severity: Medium.** Standard CI/CD risk, but the bypass of branch protection
means the blast radius is higher than a typical write token.

**Recommendation:** Document that the PAT should have an expiration date
(fine-grained PATs support this). Consider adding a branch ruleset that limits
bypass to the specific bot account, rather than anyone holding the PAT.

### 1d. Workflow trigger injection via crafted tag names

The design says "the version string comes from the tag name, which is validated
by GitHub's tag format constraints." This is partially true -- GitHub allows
tags with special characters. A tag like `v1.0.0$(whoami)` or
`v1.0.0; rm -rf /` is a valid git tag name. If the tag name flows into shell
commands without quoting (e.g., in `sed`, `jq`, or `gh release create`), this
becomes a command injection vector.

The koto release.yml uses `TAG="${GITHUB_REF_NAME}"` and then passes `$TAG`
into commands. This is safe when double-quoted, but the design should explicitly
require quoting conventions in the workflow implementation.

**Severity: Low-Medium.** Requires push access to create tags (already trusted),
but defense-in-depth matters.

**Recommendation:** The implementation should always double-quote `$TAG` in
shell contexts and validate the tag format (regex: `^v[0-9]+\.[0-9]+\.[0-9]+$`)
early in the workflow, failing fast on malformed tags.

### 1e. Supply chain: jq dependency

Both `check-sentinel.sh` and the release workflow depend on `jq`. On
GitHub-hosted runners, `jq` is pre-installed. But if the runner image changes
or a self-hosted runner is used, `jq` absence would cause silent failures
(depending on error handling) or wrong exit codes.

**Severity: Low.** Unlikely given GitHub-hosted runners, but worth a note.

**Recommendation:** The script should check for `jq` availability and fail
with a clear message if missing.

---

## 2. Sufficiency of Mitigations for Identified Risks

### 2a. RELEASE_PAT scope -- Adequate with caveats

The design correctly specifies fine-grained PAT with `contents: write` scoped
to shirabe only. This is the right approach. The caveat is that no expiration
or rotation policy is mentioned (see 1c above).

**Verdict: Sufficient for initial implementation.** Add expiration policy as a
follow-up.

### 2b. Script injection via jq -- Adequate

Using `jq` instead of `grep`/`sed` for JSON parsing is the right call. `jq`
handles malformed JSON safely (exits non-zero) without shell injection risk.

**Verdict: Sufficient.**

### 2c. Tag annotation extraction -- Adequate

Using `git tag -l --format='%(contents)'` with a fixed format string is safe.
The annotation content goes into a file (`/tmp/release-notes.md` in koto's
pattern) and is passed to `gh release create` via `--notes-file`, never
interpolated into shell.

**Verdict: Sufficient.**

### 2d. "No user-supplied data flows into shell commands" -- Partially accurate

The version string does flow from the tag name into `jq` filter arguments and
commit messages. In both cases the risk is low (`jq` treats the arg as a string
value, and `git commit -m` doesn't interpret shell metacharacters). But the
claim "no user-supplied data flows into shell commands without sanitization"
is slightly overstated -- the tag name is user-supplied and does flow into
commands, it's just that the contexts are safe.

**Verdict: Reword to be more precise.** Something like "The tag name flows into
shell commands only in safely-quoted contexts."

---

## 3. "Not Applicable" Justifications Review

The design doesn't have explicit "N/A" sections, but it implicitly scopes out
several concerns by not mentioning them:

### 3a. Artifact integrity / signing -- Implicitly scoped out

Shirabe has "no binaries to build," so there are no release artifacts beyond
the GitHub release itself. No checksums, signatures, or SBOMs are needed.

**Verdict: Correctly scoped out.** The marketplace reads source directly from
the tagged commit; there's no binary distribution channel.

### 3b. Secrets in release notes -- Implicitly scoped out

Release notes come from the tag annotation, written by the /release skill from
a checklist issue. No automated secret scanning is mentioned.

**Verdict: Acceptable risk.** The notes are human-reviewed (written during
/release) and the checklist issue is public. Low risk of accidental secret
inclusion.

### 3c. Permissions escalation via workflow_dispatch -- Correctly avoided

The design explicitly rejected workflow_dispatch in favor of tag-triggered
workflows. This avoids the class of attacks where a PR modifies a
workflow_dispatch workflow to run with elevated permissions.

**Verdict: Good design choice.**

---

## 4. Residual Risk Assessment

### Risks requiring escalation: None

No risks rise to the level of blocking the design. All identified gaps are
addressable with minor additions to the implementation.

### Risks requiring documentation

| Risk | Severity | Action |
|------|----------|--------|
| Race condition in finalize-release | Low | Document recovery procedure |
| Tag overwrite without protection rules | Medium | Add tag protection to implementation checklist |
| PAT with no expiration policy | Medium | Document rotation/expiration requirement |
| Tag name injection without format validation | Low-Medium | Add regex validation in workflow |

### Accepted residual risks

- The finalize-release job bypasses branch protection by design. This is
  inherent to the pattern and acceptable given fine-grained PAT scoping.
- A narrow window exists where main has a non-sentinel version. This is
  tolerable given low release frequency.

---

## Summary

The Security Considerations section covers the most important risks (PAT scope,
script injection, tag annotation safety) and makes sound choices (jq over grep,
fixed format strings, fine-grained PAT). Four gaps were identified:

1. **Tag protection rules** not mentioned -- medium severity, easy fix
2. **Race condition** in finalize-release -- low severity, needs documentation
3. **PAT lifecycle** (expiration/rotation) not addressed -- medium severity
4. **Tag name format validation** missing -- low-medium severity

None of these block the design. They should be added as implementation details
or follow-up items.
