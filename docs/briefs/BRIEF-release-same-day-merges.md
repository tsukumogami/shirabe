---
schema: brief/v1
status: Accepted
problem: |
  `/release` builds the set of pull requests a release contains twice, through
  two mechanisms with different boundary semantics, and the second one is keyed
  on a variable the skill never defines. Read as a date, it drops every PR
  merged on the same calendar day as the previous tag -- from the notes, and
  from the security check that decides whether a fix may be described.
outcome: |
  An author cutting a release gets a pull request set that holds everything the
  release contains, and the security check runs against that same set. A PR
  merged four hours after the previous tag appears in both. Whether the two
  computations become one or the second is made exact is the downstream
  decision; either way the author stops depending on an undefined value.
motivating_context: |
  Found while cutting v0.18.0. The notes shipped complete only because the
  missing PR was noticed by hand and pulled in by number. The same truncation
  sits on the security-labeled-PR check one phase earlier, where nothing would
  have surfaced it at all.
---

# BRIEF: A release credits only some of the pull requests it contains

## Status

Accepted

Framing for issue #321. The downstream PRD owns the requirements; this brief
stops at the problem, the outcome, the journeys that exercise it, and where the
boundary sits. It deliberately does not pick between the two candidate
resolutions the Scope Boundary names -- that is the design's call, and the
outcome and journeys here are written so either one reaches them.

Two framing details were carried as Open Questions through the Draft and are
recorded here because Accepted status forbids that section. Both resolve in the
downstream PRD's Decisions and Trade-offs. Whether the notes gather needs pull
request bodies or only numbers and titles: only numbers and titles, since a
squash subject already carries the type prefix, the description, and the
number, and bodies are read only for the security-labeled subset. What the
skill does when the release's commits and its credited pull requests do not
line up: report and continue, never stop, because a release legitimately
contains commits no pull request accounts for and a blocking check would fire
every time.

## Problem Statement

`/release` decides what a release contains twice.

Phase 3 step 1 gathers `git log --oneline $LAST_TAG..HEAD`. That range is
exact: it is the set of commits between the previous tag and the release point,
with no boundary semantics to get wrong. Phase 3 step 2 then re-derives the
same set a second way, by asking GitHub which pull requests merged after the
previous release:

```
gh pr list --state merged --base main --search "merged:>$LAST_TAG_DATE"
```

`$LAST_TAG_DATE` is used and never defined. Nothing anywhere in
`skills/release/SKILL.md` assigns it, so each author cutting a release derives
it themselves, and the variable's name invites a date. GitHub's search treats
`merged:>YYYY-MM-DD` as "after the end of that day", so a date-shaped value
silently excludes every PR merged on the same calendar day as the tag.

Cutting v0.18.0 from v0.17.0, which was tagged `2026-08-15T19:43:30+00:00`:

| Search term | PRs returned |
|---|---|
| `merged:>2026-08-15` | 292, 311, 316, 318 |
| `merged:>2026-08-15T19:43:30Z` | 292, 297, 311, 316, 318 |

`#297` merged at `2026-08-15T23:52:38Z`, four hours after the tag and squarely
inside the release. The date-truncated form loses it, and the notes render as a
complete list either way. Nothing in the skill compares the two lists it built,
so the disagreement surfaces only if an author counts them by hand -- which is
how this was found.

The same expression appears one phase earlier, and that call site is worse:

```
gh pr list --state merged --search "label:security merged:>$LAST_TAG_DATE"
```

This is the Phase 2 precondition that finds security-labeled PRs in the release
and, for each one, puts a decision to the author: describe the fix normally,
redact it, or exclude it. A PR the query does not return never reaches that
decision. A fix for a live vulnerability can be published with a standard
description and nobody is prompted. It fails silently and permissively, in the
one place the skill is otherwise most careful -- the phase whose whole job is
to stop before something ships that should not.

The two defects are the same defect at two call sites, and they have the same
root: a release's contents are computed twice, so the truncating computation is
the one two consumers happen to read.

## User Outcome

An author cutting a release gets a pull request set that holds everything the
release contains, and the security check asks its question of that same set, so
a security-labeled PR merged an hour after the previous tag reaches the
describe/redact/exclude decision instead of falling through it.

The author does not have to know how GitHub's search resolves a bare date, and
does not have to reconstruct a variable the skill never defined. Neither does
the next author, because the skill no longer asks anyone to supply a value
whose precision decides whether the release notes are complete.

The brief deliberately stops short of saying *how*. Both candidate resolutions
reach this outcome: deriving the set from the commit range collapses the two
computations into one, and defining the missing variable as a full-precision
timestamp leaves two but makes the second exact. Choosing between them is the
downstream design's call, and this outcome is written so it does not prejudge
it.

## User Journeys

### Two releases land on the same day

A maintainer tags a release in the morning, merges more work through the
afternoon, and cuts the next release that evening -- or the next morning, with
the afternoon's merges still on the tag's calendar day. Today the second
release's notes silently omit everything merged after the first tag but before
midnight. After this work the notes carry them.

The journey's outcome shape is a complete changelog, reached without the author
noticing anything was at risk.

### A security fix merges after the tag

A contributor's fix carries the `security` label and merges the same evening
the previous release was tagged. Today Phase 2's query returns nothing, the
precondition passes, and the release proceeds without ever asking how the fix
should be described. The notes then describe it in full, or omit it, by
accident rather than by decision. After this work the PR is in the set Phase 2
reads, so the author is asked.

This journey is why both call sites are in scope and why the second one is the
more urgent of the two. A missing entry in a changelog is an incomplete
document. A missing entry here is a decision that never got made.

### A maintainer reads the skill to find out where a value comes from

Someone editing `skills/release/SKILL.md` -- or an agent executing it -- reaches
`$LAST_TAG_DATE` and looks for its definition. There isn't one. Today they
supply something plausible and the plausible thing is wrong. After this work
every value the skill's commands use is defined in the skill, above its use.

The journey exercises the skill as prose read by whoever runs it next, which is
the surface a skill actually has.

### The commit list and the credited PRs do not line up

An author sees five commits and four credited PRs and has no reason to think
that is a mismatch rather than an ordinary difference -- a direct push, a
release chore commit, a revert. Today nothing accounts for the gap, so a lost
PR and a legitimate unattributed commit look identical.

The journey's outcome shape is that whatever the release contains but no pull
request accounts for is named where the author will see it, so a gap that is
ordinary reads as ordinary and a gap that is not stands out. Which mechanism
produces that accounting depends on the resolution the design picks, and this
journey is written against the outcome rather than against either mechanism.

## Scope Boundary

**In:**

- Making the set of pull requests `/release` gathers include every PR merged
  after the previous release tag, including those merged on the tag's own
  calendar day.
- Both call sites of the truncating expression: the Phase 2 security-labeled-PR
  precondition and the Phase 3 release-notes gather. A fix that repairs one and
  leaves the other truncating does not close the problem.
- Deciding between the two candidate resolutions the issue records -- derive
  the PR set from the commit range the skill already gathers, or define the
  missing variable as a full-precision timestamp -- and recording the reasoning
  where the next reader can find it.
- Whether the skill should reconcile the two lists it builds, and what it does
  when they disagree.
- The skill's evals, which are part of the skill: a behavior the skill now
  guarantees is a behavior an eval asserts.

**Out:**

- Re-cutting or amending the v0.18.0 release. It is published and its notes are
  correct; they were completed by hand, which is what surfaced this.
- The release GitHub Actions workflows (`release.yml`, `prepare-release.yml`,
  `finalize-release.yml`). The defect is in the skill's prose, and the workflows
  do not compute a PR set.
- Any CLI subcommand that renders or creates release notes. `CLAUDE.md`
  section "CLI Surface" reserves artifact authoring for skills and the CLI for
  validation; a renderer here would be the anti-pattern that section names.
- Phase 2's other precondition checks. The clean-tree, CI-green, existing-tag,
  existing-draft, and blocker checks are untouched.
- The other open defects in this skill's neighborhood -- multi-line `**Type**:`
  parsing, and the absence of a driver for an issueless multi-PR plan. They are
  separate issues and neither shares this one's root.

## References

- `skills/release/SKILL.md` -- the skill carrying both call sites.
- `docs/designs/current/DESIGN-reusable-release-system.md` -- the release
  system this skill drives.
