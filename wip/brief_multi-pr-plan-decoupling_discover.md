# Brief Discover: multi-pr-plan-decoupling

## Dispatch Context

Invoked under `/scope`'s `parent_orchestration:` sentinel. The parent owns the
approval prompt; this run finalizes the artifact and hands control back.

## Grounding Path

None. No `--upstream` supplied and no ROADMAP sequences this feature, so
`upstream:` is omitted rather than guessed.

## Feature Framing

The scoping conversation for this feature already happened: it is the `/explore`
run recorded in `wip/explore_multi-pr-plan-decoupling_findings.md`, its
`_decisions.md` companion, and the decision report at
`wip/explore_multi-pr-plan-decoupling_decision_1_report.md`. Phase 1 grounds on
those rather than re-running a dialogue whose answers are already on disk.

## Problem/Outcome Pair

**Problem candidate.** A PLAN's `execution_mode` answers three questions with one
value -- whether the work can land in a single PR, whether it should, and whether
GitHub issues and a milestone get created. A repo cannot state a preference on
either of the last two, and a plan that ends up multi-PR records nothing about
why, so a later reader cannot tell a forced split from a preferred one.

**Outcome candidate.** An author plans a change and the delivery shape follows
what their repo has stated it prefers; the tracking mechanism follows a separate
stated preference; and any plan that is not single-PR carries, in the merged
artifact, the reason it is not.

## Signals Feeding the Framing

- The fusion is localized: one branch in `phase-3-decomposition.md` step 3.6 and
  one hardcoded consequence in `phase-7-creation.md`.
- Both preference mechanisms already ship one altitude away
  (`## Roadmap Issues:` for tracking, `## PR Grouping Policy:` with
  `## Reviewability Ceiling:` for decomposition).
- `skills/plan/SKILL.md` already requires a forcing constraint be named in the
  PLAN doc; no schema slot exists to hold it, and the validator has no check.
- Milestones carry no progress, completion, or cascade role -- only `/work-on`'s
  issue selector reads them.

## Deferred to the Downstream PRD

Header names, the structural check on a free-text rationale, the
conditional-required-field mechanism, the issueless task-extraction scheme, the
`/work-on M<N>` substitute, and whether the reviewability ceiling gets a concrete
value.
