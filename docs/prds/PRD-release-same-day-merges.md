---
schema: prd/v1
status: In Progress
upstream: docs/briefs/BRIEF-release-same-day-merges.md
source_issue: 321
problem: |
  `/release` computes what a release contains twice: once as a commit range,
  and once as a GitHub pull request search keyed on `$LAST_TAG_DATE`, a shell
  variable the skill never defines. Read as a date -- which is what the name
  invites -- GitHub resolves `merged:>YYYY-MM-DD` as "after the end of that
  day", so every PR merged on the same calendar day as the previous release tag
  drops out. It drops out of the release notes, and out of the Phase 2
  precondition that decides how a security-labeled fix is described.
goals: |
  One computation answers what a release contains, taken from the commits the
  release actually holds, and both consumers read it. A PR merged after the
  previous tag but before midnight appears in the notes and reaches the
  security decision. The skill defines every value it uses, so the next author
  who runs it does not have to reconstruct one whose precision decides whether
  the notes are complete.
motivating_context: |
  Found while cutting v0.18.0 from v0.17.0. The notes shipped complete only
  because the missing PR was noticed by a hand count and pulled in by number.
  The same expression sits on the security precondition one phase earlier,
  where a hand count would not have happened and nothing would have surfaced
  the omission at all.
---

# PRD: One PR set for a release, derived from its commits

## Status

In Progress

Requirements for issue #321, written from
[BRIEF-release-same-day-merges](../briefs/BRIEF-release-same-day-merges.md).
This PRD owns what the skill must do; the downstream DESIGN owns which
mechanism does it.

## Problem Statement

`skills/release/SKILL.md` decides what a release contains in two places, by two
mechanisms, and the second one is wrong.

Phase 3 step 1 gathers `git log --oneline $LAST_TAG..HEAD` -- the exact set of
commits between the previous tag and the release point. Phase 3 step 2 then
re-derives the same set by asking GitHub which pull requests merged since:

```
gh pr list --state merged --base main --search "merged:>$LAST_TAG_DATE"
```

`$LAST_TAG_DATE` is never assigned anywhere in the skill. Every author cutting
a release supplies it themselves, and the name invites a calendar date. GitHub
resolves `merged:>YYYY-MM-DD` as "strictly after the end of that day", so a
date-shaped value silently excludes every PR merged on the tag's own day.

Reproduced against the v0.17.0 to v0.18.0 range, with v0.17.0 tagged
`2026-08-15T19:43:30+00:00`:

| Search term | PRs returned |
|---|---|
| `merged:>2026-08-15` | 292, 311, 316, 318 |
| `merged:>2026-08-15T19:43:30Z` | 292, 297, 311, 316, 318 |

`#297` merged at `2026-08-15T23:52:38Z`, four hours after the tag. It is in the
release; the date-truncated search does not return it, and the notes render as
a complete list either way. The two lists the skill builds are never compared,
so the disagreement is invisible unless an author counts by hand.

The identical expression appears one phase earlier, at the Phase 2 precondition
that finds security-labeled pull requests:

```
gh pr list --state merged --search "label:security merged:>$LAST_TAG_DATE"
```

A PR this query misses never reaches the AskUserQuestion step that decides
whether the fix is described normally, redacted, or excluded. The release then
publishes a full description of a live-vulnerability fix, or omits it, by
accident. The failure is silent and permissive, in the phase whose whole
purpose is to stop a release that should not proceed.

Who is affected: whoever cuts the next shirabe release, and every consumer
reading its notes. Why now: the defect has already fired once, on the release
that shipped the largest breaking change in the project so far.

## Goals

- The set of pull requests a release credits is complete, including PRs merged
  on the previous tag's calendar day.
- The security precondition sees the same set the notes are built from, so no
  security-labeled change can slip past the describe/redact/exclude decision by
  a boundary condition.
- The skill defines every value it uses, so correctness does not depend on an
  author choosing the right precision for an undefined variable.
- Where a commit in the release cannot be attributed to a pull request, the
  author is told, rather than the gap being invisible.

## User Stories

**Cutting a release the same day as the previous one.** As a maintainer who
tagged this morning and is tagging again tonight, I want the second release's
notes to credit everything merged in between, so that the changelog matches
what shipped.

**A security fix merges after the tag.** As a maintainer, I want a
`security`-labeled PR merged after the previous tag to reach the
describe/redact/exclude decision, so that how a vulnerability fix is disclosed
is a choice I made rather than an accident of when it merged.

**Reading the skill.** As whoever runs `/release` next -- a person or an agent
-- I want every value the skill's commands use to be defined in the skill, so
that I do not have to guess a precision that decides whether the output is
correct.

**A commit with no pull request.** As a maintainer reviewing draft notes, I
want to see which commits in the release range carry no pull-request
reference, so that I can tell a direct push or a release chore commit apart
from a PR the gather lost.

## Requirements

**R1.** The set of pull requests `/release` gathers for a release SHALL include
every pull request whose merge commit falls in the range between the previous
release tag and the release point, with no exclusion based on calendar-day
boundaries. In particular, a pull request merged after the previous tag's
timestamp but before the end of that tag's calendar day SHALL be included.

**R2.** The Phase 2 security-labeled-pull-request precondition SHALL evaluate
the same set of pull requests as R1. A pull request that R1 includes and that
carries the `security` label SHALL reach the AskUserQuestion step that decides
its treatment in the release notes.

**R3.** `skills/release/SKILL.md` SHALL NOT use any shell variable that the
skill does not define. Every variable appearing in a command the skill
prescribes SHALL have an assignment, in the skill, that a reader can find
before the use.

**R4.** Before the release notes are drafted, `/release` SHALL report every
commit in the release range that carries no pull-request reference. The report
is informational and SHALL NOT stop the release.

**R5.** The change SHALL NOT add a CLI subcommand that renders or creates
release notes. Artifact authoring belongs to skills and the CLI is the
validation surface, per `CLAUDE.md` section "CLI Surface".

**R6.** `skills/release/evals/evals.json` SHALL carry at least one scenario
that asserts R1 at the Phase 3 gather and at least one that asserts R2 at the
Phase 2 precondition, each asserting the same-day-merge behavior specifically
rather than the phase in general.

**R7.** The change SHALL be confined to `skills/release/` and its evals. The
release GitHub Actions workflows SHALL NOT be modified.

## Acceptance Criteria

- [ ] `grep -n 'LAST_TAG_DATE' skills/release/SKILL.md` returns no occurrence
      that is not preceded in the same file by an assignment of that variable.
- [ ] Executing the skill's Phase 3 gather procedure by hand against the
      v0.17.0 to v0.18.0 range yields a pull request set containing `#297`, and
      the transcript of the commands run is recorded in the pull request body.
- [ ] Executing the skill's Phase 2 security precondition by hand against the
      same range evaluates `#297` -- that is, `#297` is a member of the set
      whose labels the precondition inspects.
- [ ] The skill's prose names, at both call sites, where the pull request set
      comes from, and the two call sites name the same source.
- [ ] `skills/release/evals/evals.json` contains a scenario covering R1 and a
      scenario covering R2, and `scripts/run-evals.sh release` has been run
      with its results reported.
- [ ] `git diff --name-only` against the merge base lists no file under
      `.github/workflows/`.
- [ ] `shirabe validate` exits clean over every document this work changed, and
      `shirabe validate --lifecycle . --mode=ready` passes.

## Decisions and Trade-offs

**What the gather needs from each pull request.** The upstream BRIEF left open
whether the notes need pull request bodies or only numbers and titles. Decided:
numbers and titles. Phase 3 groups changes by conventional-commit type and
writes one sentence per change, and a squash-merge subject already carries the
type prefix, the description, and the `(#N)` suffix -- shirabe allows squash
merges only, with the commit title taken from the pull request title. Bodies
are read only for the security-labeled subset, which Phase 2 already does
explicitly and per pull request. The consequence for the DESIGN is that a
commit-range-derived set needs no re-hydration from GitHub for the notes, and
needs a per-pull-request label lookup for the security check.

**What happens when the two lists disagree.** The BRIEF asked whether a
reconciliation failure should stop the release or report and continue. Decided:
report and continue, and the shape of the report follows from the choice of
mechanism. If the pull request set is derived from the commit range there is no
second list to reconcile, and the residual gap is the opposite one -- commits
in the range that name no pull request, such as the release chore commits the
workflow itself writes. R4 names that report. It is informational because every
release legitimately contains such commits; stopping on them would fire on
every release.

**Both call sites, not one.** Repairing only the notes gather would leave the
security precondition truncating. The two carry the same expression, and the
precondition's failure mode is worse: an incomplete changelog is a document
defect a reader can notice, while a skipped security decision leaves no trace
at all. R2 is therefore stated as its own requirement rather than folded into
R1, so a partial fix fails a criterion rather than passing quietly.

## Out of Scope

- Re-cutting or amending the v0.18.0 release. It is published and its notes are
  correct; they were completed by hand, which is what surfaced this.
- `.github/workflows/release.yml`, `prepare-release.yml`, and
  `finalize-release.yml`. They do not compute a pull request set.
- Phase 2's other precondition checks -- clean tree, CI green, existing tag,
  existing draft, release blockers. Untouched.
- Any CLI subcommand for release notes, per R5.
- The unrelated open defects in this skill's neighborhood: multi-line
  `**Type**:` parsing, and the absence of a driver for an issueless multi-PR
  plan. Neither shares this defect's root.
