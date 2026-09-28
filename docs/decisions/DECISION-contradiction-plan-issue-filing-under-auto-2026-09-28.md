---
status: Accepted
decision: |
  The policy owner picked "Approval, repo opt-in", and added: "this is a koto workflow fix". Every path that files issues requires approval; an unattended run files only when the repository's CLAUDE.md declares a tracking level, and otherwise writes outlines without filing.
rationale: |
  /plan's own rule says filing issues needs human approval, yet its multi-pr
  path and its single-pr path with tracking file issues and a milestone with
  no approval step, and under --auto nobody is asked about tracking. An
  unattended run could create GitHub issues and a milestone nobody approved.
  Requiring approval everywhere makes the stated rule true; a repository that
  declares a tracking level has opted in to filing, and otherwise the run
  produces a PLAN with outlines, which the validator already accepts. Prose
  alone can't hold an unattended run to the rule, so the callers that run
  under a koto template gate it.
---

# DECISION: /plan files issues only with approval or a declared opt-in

## Status

Accepted on 2026-09-28. The policy owner answered this item of the
contradiction-settlement inventory (coordination PR shirabe#507).

## Context

This is the `plan-issue-filing-under-auto` item: /plan files issues and a
milestone under `--auto` without approval.

`skills/plan/SKILL.md` says an activation that files issues requires human
approval. But in `skills/plan/references/phases/phase-7-creation.md`, the
multi-pr path (steps 7.1 through 7.4) files issues and a milestone with no
approval step, and the approval step exists only on the coordinated path.
Phase 3 says tracking is asked separately, but nothing asks it under
`--auto`, and the default tracking level is issues-and-milestone. /scope
forwards `--auto` to /plan on intent runs, and /scope's SKILL.md says
`gh pr create` and `gh pr edit` are its only `gh` writes. An unattended run
can create GitHub issues and a milestone that nobody approved.

## Decision

The policy owner picked "Approval, repo opt-in", and added: "this is a koto workflow fix". Every path that files issues requires approval; an unattended run files only when the repository's CLAUDE.md declares a tracking level, and otherwise writes outlines without filing.

## Implementation notes

These notes are execution guidance for the items that apply this decision,
not the policy owner's words.

- "This is a koto workflow fix" is applied as a koto workflow gate rather
  than a prose rule alone.
- The gate uses only gate types koto 0.14.1 already has: `context-exists` or
  `context-matches` over a recorded approval, plus a command gate reading the
  repo's CLAUDE.md for the tracking level.
- /plan has no koto template, so the gate lives in the koto-templated caller
  that runs it, /scope's plan hop. No coordinated /execute state runs /plan
  today. /plan's prose restates the rule for direct runs.
- This is the DESIGN's option 1, approval on every filing path and filing
  under `--auto` only when CLAUDE.md declares a tracking level, which was the
  recommendation, with enforcement in the koto workflow added.
- /plan's prose changes land in the plan pull request of the
  contradiction-settlement PLAN; the gate and /scope's list of `gh` writes
  land in the scope pull request.

## Options Considered

- **Option 1: Approval on every filing path; under `--auto`, file only when
  CLAUDE.md declares a tracking level, else emit an issueless PLAN with
  outlines.** Makes the stated rule true and reuses the rule the coordinated
  path already follows.
- **Option 2: Never file under `--auto` or under a parent.** Simplest; a
  caller who wants issues runs /plan again interactively.
- **Option 3: Keep the behavior and rewrite the rule to allow it.** No
  behavior change; unattended filing becomes intended.

## Consequences

Until this record merges, the statements it governs stay as they are. After
it merges, no path files issues or a milestone without a recorded approval,
and an unattended run in a repository that declares no tracking level ends
with outlines in the PLAN and nothing filed. /scope's plan hop refuses to
pass its gate without both the approval and the opt-in.

## References

- shirabe#507 (the contradiction-settlement DESIGN, PLAN and inventory)
- `skills/plan/SKILL.md`
- `skills/plan/references/phases/phase-7-creation.md`
- `skills/scope/SKILL.md`
