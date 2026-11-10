---
schema: brief/v1
status: Draft
problem: |
  An author running /design in a repository that validates design documents
  on commit can't save the run's in-progress document: the hook refuses every
  stage before the frontmatter is final, and the run has no stated way through
  that doesn't bypass the hook or mark the design finished before it is.
outcome: |
  An author running /design under a validating hook commits each stage of the
  run with nothing bypassed, a run that stops partway resumes from where the
  work actually stands, and a design put up for review as ready while still
  unfinished is refused as it was before.
---

# BRIEF: Skeleton Commit

## Status

Draft

## Problem Statement

`/design` writes its document in stages and commits each one, starting with a
skeleton at Phase 0. The skeleton is incomplete on purpose. It has no
frontmatter `status`, because the skill's resume checks read `status: Proposed`
as a finished design, and it has only the sections the early phases have
reached.

Some repositories run the design-document validator as a pre-commit hook, and
in a workspace whose setup script installs that hook, every clone runs it. The
hook refuses the skeleton: the missing `status`, `problem`, `decision` and
`rationale` fields, a frontmatter status that doesn't match the body, and six
missing required sections, eleven errors in all. The same refusal meets every
commit the run makes until the frontmatter is written near the end, and the
skill's own document check refuses the same partial draft before its review.

Both rules have a reason. The hook is right to want a whole design on a branch,
and the skill is right not to mark an unfinished design `Proposed`. Because
they conflict and nothing says what a run does, an author is left to improvise,
and the two improvisations seen so far both cost something. One run filled the
frontmatter early so the hook would accept the commit; on resume, both of the
skill's resume checks read that early status as progress and would have skipped
the review jury. Another run kept the skeleton uncommitted rather than bypass
the hook, and stayed blocked with its work outside git. Bypassing the hook is
not a way through.

## User Outcome

An author running `/design` in a repository that validates design documents on
commit gets through the whole run without touching the hook: each stage the
skill commits is accepted, and nothing is skipped, faked or disabled to get
there. The partial document lives in git like any other stage, so the run can
be interrupted and picked up later, from another clone if need be.

A run that stops partway resumes at the point the work actually reached. No
field written early to satisfy a check is read as "this design is finished",
so a design never skips its review because of how it was saved.

The maintainer who installed the hook keeps what it was for. A design put up
for review as ready while it still lacks frontmatter or sections is refused,
as it would have been before. What changes is that the run's unfinished stages
are accepted on its branch; what a design must hold when it's published for
review doesn't change.

## User Journeys

### Starting a design under the hook

An author runs `/design` on a new topic in a clone where the pre-commit hook
validates design documents. Phase 0's commit, and each commit after it, goes
through on the first try. The author never sees a validator refusal for a stage
the skill meant to leave incomplete, and never has to choose between the hook
and the run. If the author's tools don't carry the change yet, the run says so
before any work starts, instead of failing at the first commit.

### Resuming a stopped run

An author returns to a design run that was interrupted between stages,
possibly in a different clone. The run reads where the work stands from what
was committed and recorded, picks up at the next unfinished step, and still
runs every review the design has not passed.

### Continuing a run caught by the conflict

An author has a run that already hit the refusal: either the skeleton sits
uncommitted in the worktree, or the frontmatter was filled early to get a
commit through. The author learns what to do with that run under the new rule,
and continues it without losing work or skipping the review.

### Reviewing a design that isn't finished

A maintainer whose repository runs the hook, and whose pull requests run the
design-document checks, sees a design pull request marked ready for review
while its document is still partial. The repository's checks refuse it, as
they would have before. Accepting the run's unfinished stages on its branch did not let
an unfinished design pass review.

## Scope Boundary

**In scope:**

- What `/design` commits while its document is partial, from the Phase 0
  skeleton through the commits before the frontmatter is final.
- Where the rule that lets those commits pass a validating hook lives, whether
  in the skill, the validator, the hook's scope, or elsewhere.
- What it costs an adopting repository to pick the change up, including what
  an author sees when their tools carry only part of it.
- How the skill's resume checks read a run's progress, so a status written to
  satisfy a check can't be read as a finished design.
- The skill's own document check, where it refuses the same partial draft the
  hook does.
- A stated way forward for runs already caught by the conflict.

**Out of scope:**

- Changes to the other document skills. They either commit only a finished
  document or, like `/brief`, already commit partial drafts under a status
  their format accepts, so the conflict as reported belongs to `/design`.
- Phase 5's empty summary commit (#1642), a neighbouring commit problem in the
  same skill with its own issue.
- Bypassing, disabling or editing the hook in an adopting repository, or
  dropping the hook from a workspace's setup. The hook's guarantee is part of
  the outcome, not a cost to trade away.
- Validation rules for finished designs. What a design must contain at review
  is unchanged.
- Closing every other path an unfinished design could take to the default
  branch, such as a direct push or a repository whose pull requests don't run
  the lifecycle check. The refusal this brief keeps is the one at review.

## Downstream Artifacts

- `docs/designs/DESIGN-skeleton-commit.md`, the design that picks this framing
  up and chooses how `/design` commits its partial document.

## References

- Issue #1646, which reports the refusal, the two runs it affected, and the
  resume checks that misread an early status.
- `skills/brief/references/phases/phase-2-draft.md`, a skill that commits a
  partial draft under a status its format accepts.
