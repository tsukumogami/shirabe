# Phase 2 Research: User Research & Current State

## Lead A: User Stories and Personas

### Findings

**Repos and doc volumes observed**

| Repo | Designs | PRDs | Roadmaps | Plans | VISION | CI doc validation? |
|------|---------|------|----------|-------|--------|--------------------|
| koto | 30 current + 2 root-level | 7 | 2 | 9 (8 done + 1 active) | none found | None |
| niwa | 28 current | 9 | 0 | 0 | none found | None |
| tsuku | 100+ current + archive | 5 | 1 | 2 | none found | Yes (Design only, non-reusable) |
| shirabe | 4 current | 6 | 2 | 1 | (format defined, no live docs) | Plan only, non-reusable |

**koto** has no doc-validation workflow at all. Its `.github/workflows/` contains
`check-template-freshness.yml` (a reusable workflow it publishes), `validate-plugins.yml`,
`eval-plugins.yml`, and release workflows -- none checking Design, PRD, Roadmap, or Plan
structure. 65+ structured docs get zero CI enforcement.

**niwa** similarly has no doc-validation workflow. Its only CI workflow is `test.yml`, which
runs Go tests, vet, and recipe installation -- nothing touches `docs/`.

**tsuku** has `validate-design-docs.yml` and a companion script family
(`.github/scripts/validate-design-doc.sh`, `checks/frontmatter.sh`,
`checks/sections.sh`, `checks/status-directory.sh`). This covers Design format
only. It is not reusable: the workflow calls `.github/scripts/validate-design-doc.sh`
which in turn sources `checks/` scripts from the same repo, so it cannot be invoked
by another repo without copying the entire script tree.

**shirabe** has `check-plan-docs.yml` which calls
`skills/plan/scripts/validate-plan.sh`. Same non-reusable pattern: the workflow
references a local path. Also covers Plan format only.

**Frontmatter schemas observed across repos:**

Design: `status`, `problem`, `decision`, `rationale` (required). Optional:
`upstream`. Status values in tsuku: Proposed, Accepted, Planned, Current,
Superseded. Status values in koto: includes "Implemented" (seen in
`PRD-gate-transition-contract.md`).

PRD: `status`, `problem`, `goals` (required). Optional: `source_issue`. Status
values seen: Accepted, Delivered, Done, Implemented.

Roadmap: `status`, `theme`, `scope` (required). Status values seen: Active,
Complete, Done.

Plan: `schema: plan/v1`, `status`, `execution_mode`, `issue_count` (required).
Optional: `upstream`, `milestone`. Status values: Active, Done.

VISION (format defined in shirabe, no live docs in any public repo):
`status`, `thesis`, `scope` (required). Optional: `upstream`. Status values:
Draft, Accepted, Active, Sunset.

**Status enum divergence:** Repos use overlapping but inconsistent status values.
koto PRDs use "Implemented" while tsuku's validator only accepts Proposed, Accepted,
Planned, Current, Superseded. niwa PRDs use "Delivered". A cross-repo validator
must either accept a union of known values or each format must have its own
validated enum.

**Existing caller pattern (proven):** koto and niwa both call shirabe workflows
via `uses: tsukumogami/shirabe/.github/workflows/finalize-release.yml@v0.2.0` and
`uses: tsukumogami/shirabe/.github/workflows/release.yml@v0.2.0`. shirabe itself
calls koto via `uses: tsukumogami/koto/.github/workflows/check-template-freshness.yml@main`.
The three-ecosystem `uses:` pattern is established and working.

### Implications for Requirements

**User story 1: Repo maintainer onboarding**

A maintainer of koto or niwa (both have zero doc validation today) wants to add
doc format enforcement. They have 65+ existing Design, PRD, Roadmap, and Plan
docs written before any validator existed. The PRD must address grandfathering
or incremental rollout, because enabling strict validation against 65 docs at
once is likely to produce a wall of failures that blocks the PR enabling the check.
Recommendation: the PRD should require the validator to only run on files
changed in the PR (not all docs), so adoption doesn't require cleaning every
existing doc first.

**User story 2: Contributor with validation active**

A contributor to koto opens a PR that adds a new Design doc. CI catches a
missing `rationale` field before the reviewer sees it. The contributor sees an
error message pointing to the specific rule code (e.g., FM01) and a fix
command or link. The error must be actionable: the contributor needs to know
exactly which field is missing and what value to use.

**User story 3: shirabe maintainer propagating improvements**

The shirabe maintainer adds Plan validation for a new field (say, `decomposition_strategy`
becomes required). Because koto and niwa consume via `@v1` tag and the workflow is
centralized, the maintainer cuts a new `v2` tag. Downstream repos choose their upgrade
timing via their pin; no script copying required. This is the core value of the
reusable workflow model -- one change propagates, version-pinned for safety.

**Status enum question:** The actual values used across repos differ from the
canonical lists. The validator must handle cross-repo status value reality, not just
the values in shirabe's own docs. This is an open question: should the reusable
workflow validate against a common enum, or allow per-format enum customization?

### Open Questions

1. **Changed-files vs all-files:** Should the reusable workflow check only PR-changed
   docs (lower adoption friction, misses pre-existing violations) or all docs in the
   repo (catches regressions at any point, but hard to adopt against legacy corpus)?
   A per-repo input could parameterize this.

2. **Status enum normalization:** koto uses "Implemented", niwa uses "Delivered" --
   neither appears in tsuku's Design validator's accepted list. Are these values
   correct for those formats, or do they represent drift? The PRD needs to specify
   the canonical enum for each format.

3. **PRD-specific required fields:** tsuku's PRD format uses `goals` where koto's
   uses a different structure. Cross-repo consistency of required fields needs
   reconciliation before the validator is written.

4. **Plan validation in scope:** The plan validator in shirabe is the most mature
   (has upstream chain validation, schema versioning). For the reusable workflow,
   does Plan validation reuse the existing `validate-plan.sh` script or get
   rewritten as part of the centralized validator?

---

## Lead B: Downstream Setup PR Shape

### Findings

**The proven caller pattern**

koto and niwa call shirabe workflows identically. A representative caller in
koto (`finalize.yml`) looks like:

```yaml
uses: tsukumogami/shirabe/.github/workflows/finalize-release.yml@v0.2.0
with:
  tag: ${{ needs.extract-tag.outputs.tag }}
  expected-assets: 5
secrets:
  token: ${{ secrets.RELEASE_PAT }}
```

For doc validation there are no expected secrets (static validation, no external
APIs), so the caller is simpler -- just `uses:` and optional `with:` inputs.

**Concrete thin-caller content for koto**

File to create: `.github/workflows/validate-docs.yml`

```yaml
name: Validate doc formats

on:
  pull_request:
    paths:
      - 'docs/**/*.md'

jobs:
  validate:
    uses: tsukumogami/shirabe/.github/workflows/validate-docs.yml@v1
```

This is approximately 12 lines including the name, on/push block, jobs header,
and uses. No `with:` block needed at launch if no configuration is required for v1.

If path customization is desired (e.g., a repo that puts docs elsewhere), one
optional input would extend it by 2-3 lines:

```yaml
jobs:
  validate:
    uses: tsukumogami/shirabe/.github/workflows/validate-docs.yml@v1
    with:
      docs-path: 'documentation/**/*.md'
```

**What a setup PR description would say**

A setup PR to add doc validation to koto (or niwa) would include:
- Title: `ci: add shirabe doc format validation`
- Body: "Adds the reusable doc validation workflow from
  tsukumogami/shirabe. Checks Design, PRD, Roadmap, and Plan documents for
  frontmatter completeness, valid status values, status/body sync, and required
  sections. Runs on PRs that touch docs/. Existing docs are not affected unless
  they appear in the PR diff."
- No secrets to configure (static validation requires none)
- No other files to change (no scripts to copy)
- Single file created: `.github/workflows/validate-docs.yml`

**Comparison with non-reusable pattern**

tsuku's non-reusable setup requires: `validate-design-docs.yml` + at least 6 scripts
under `.github/scripts/checks/` + doc files under `.github/scripts/docs/`. That's
10+ files to copy and keep in sync. The `uses:` pattern reduces this to 1 file,
1-12 lines, zero maintenance.

**Trigger pattern decision**

The `check-plan-docs.yml` in shirabe triggers on `paths: 'docs/plans/PLAN-*.md'`.
This is more surgical than triggering on all `docs/**/*.md`, but it means the
caller needs a separate path filter per format. A single workflow triggering on
`docs/**/*.md` (or `docs/**`) and having the validator detect format by filename
prefix (DESIGN-, PRD-, PLAN-, ROADMAP-, VISION-) is simpler for the caller and
consistent with how tsuku's `validate-design-docs.yml` works (it finds files by
`DESIGN-*.md` pattern internally).

**Version pinning**

koto and niwa pin to `@v0.2.0` for the release workflow. The doc validation
workflow should be pinned the same way. At launch: `@v1`. The PRD's acceptance
criterion should include: a tagged release of shirabe includes the workflow, and
a downstream caller can pin to that tag.

**niwa-specific note:** niwa has no doc subdirectory for Plans (only designs and
prds). A setup PR for niwa would omit Plan validation or accept that the workflow
finds no Plan files and produces no Plan-related output, which is fine if the
validator handles "no files found" gracefully.

### Implications for Requirements

- The caller workflow is so thin (12 lines) that setup documentation can fit in a
  single code block. This argues for a clear code example in the PRD's acceptance
  criteria.
- "No configuration required at launch" is achievable and supported by the
  observed pattern -- shirabe's `check-templates.yml` calls koto's
  `check-template-freshness.yml` with just one `with:` input and no secrets.
  Doc validation needs zero inputs if path detection is internal.
- The path filter on the calling side (`paths: 'docs/**/*.md'`) avoids running
  validation on every PR regardless of whether docs changed. This is important
  for high-velocity repos like tsuku that have many non-doc PRs.
- Plan validation reuse: the existing `validate-plan.sh` could be called from
  within the reusable workflow, but it lives in `skills/plan/scripts/` -- a path
  that is accessible when shirabe's workflow runs on the caller's repo only if
  the workflow checks out shirabe explicitly. The workflow will need to check out
  shirabe (or have validation logic embedded) to access the script.

### Open Questions

1. **Does the reusable workflow need to check out shirabe to access validation
   scripts?** If the logic is embedded as shell in the workflow YAML steps rather
   than delegated to scripts in shirabe's repo, this is a non-issue. If scripts
   are referenced by path, the workflow needs a second checkout step for shirabe.
   This affects complexity and auditability.

2. **How should "no matching docs" be handled?** A repo with no PRD docs should
   not fail when PRD validation finds nothing. The koto `check-template-freshness.yml`
   emits a `::warning::` for no matching files and exits 0. The doc validator
   should behave the same.

3. **Should the workflow emit per-file annotation errors** (using `::error
   file=...::`)? tsuku's validator does this via shell script. The GHA annotation
   format surfaces errors in the PR diff view, which is more useful than a wall of
   text. This should be a requirement for the static validation tier.

---

## Summary

Three downstream repos (koto, niwa, and tsuku) all use shirabe's doc formats at
scale -- koto and niwa have zero CI doc validation despite 65+ structured docs,
while tsuku has a non-reusable Design-only validator that would require copying
10+ scripts to adopt elsewhere. The existing `uses:` caller pattern between these
repos is proven and operational (koto and niwa both call shirabe's release
workflows today), so a thin 12-line caller workflow is the natural setup shape for
any downstream adopter. The main implementation risk is status enum divergence
across repos -- koto uses "Implemented" and niwa uses "Delivered" as status values
that don't appear in tsuku's current validator, which the PRD must address as part
of specifying the canonical enum per format.
