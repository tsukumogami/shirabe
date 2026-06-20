---
schema: brief/v1
status: Done
problem: |
  As the single-issue executor, `/work-on` decides one issue is done by the agent's own
  judgment, and that judgment accepts "verification authored" in place of "verification
  passed" (a test or eval added but never run) and lets the agent introduce caveats or
  deferrals on its own. So an issue can be reported done while one of its acceptance
  criteria is unverified or quietly deferred, and the human inherits the job of auditing
  for what was skipped. There is no enforced definition of done at the single-issue level.
outcome: |
  Completing one issue means every one of that issue's acceptance criteria is
  verified-by-execution: the verification appropriate to what the issue touched has actually
  run and passed (the project declares what to run; the default is the repo's tests), and
  "the verification exists" never counts as "it passed". Any deferral becomes a surfaced,
  human-approved decision rather than an agent-authored footnote, so the author can trust
  that a finished issue is finished.
motivating_context: |
  `/work-on` is narrowing to a single-issue executor (plan-level iteration moves to a
  separate implementation-altitude coordinator). At that single-issue altitude the recurring
  failure is "looks done" standing in for "is done" — hit directly when verification was
  authored but never executed and the result shipped with unilateral hedge language. The
  definition of done belongs in the workflow at the level `/work-on` now owns: one issue,
  finished.
---

# BRIEF: work-on Definition of Done

## Status

Done

This brief frames the completion discipline for `/work-on` as a single-issue executor. It
assumes the scope reduction that narrows `/work-on` to exactly one issue (plan-level
iteration handled by a separate implementation-altitude coordinator) and does not re-frame
that split; it layers an enforced definition of done onto the single-issue job.

## Problem Statement

`/work-on` takes one issue from start to a pull request. With plan-level iteration moving
out to its own coordinator, finishing that single issue cleanly is `/work-on`'s whole job —
and the moment it decides the issue is done is governed by nothing but the agent's judgment.
That judgment fails in a specific, repeating way: it accepts *evidence that work was
attempted* in place of *evidence that work was verified*.

Two failure modes recur at the single-issue level:

- **Verification authored but not executed.** The issue's change adds or changes a thing
  that has a verification — a test, an eval — and that verification is written and committed,
  but never run. An existence check passes; nothing confirms the behavior is correct. "The
  verification exists" is treated as "the verification passed."
- **Unilateral caveats and deferrals.** The agent, on its own initiative, downgrades a
  not-quite-finished issue into one that *reads* finished with a footnote — hedge language
  ("experimental", "not yet run", "known limitations") or a quietly deferred acceptance
  criterion. The deferral was never a decision the human made; it is one the human has to
  catch.

The cost lands on whoever asked for the issue. They are told it is done, they reasonably
assume it is done, and they instead inherit the audit for what was quietly skipped. Trust in
a finished issue erodes, and the value of handing off a unit of work — getting back a result
you can build on without re-checking — is lost. The gap is the absence of an enforced
definition of done at the single-issue level; it is not a gap in any one project's tooling.

## User Outcome

The author hands one issue to `/work-on` and trusts the result. Completion stops being the
agent's private judgment and becomes a workflow gate with two properties, both scoped to the
single issue:

- **Verified-by-execution, not addressed.** Before `/work-on` reports the issue done, every
  one of that issue's acceptance criteria is backed by verification that actually *ran and
  passed* — not merely authored or confirmed to exist. The workflow learns what to run for
  what the issue touched from the project rather than hard-coding any one stack's commands,
  and falls back to the repo's standard tests when the project declares nothing.
- **No silent deferral.** The agent cannot, on its own, downgrade the issue to "done with
  caveats." Any unmet criterion or deferral is surfaced to the human as an explicit
  decision; absent that approval, the issue is reported blocked, not done. Caveats in the
  result exist only when the human chose them.

What changes for the author is that they no longer audit a finished issue for hidden
shortfalls — the workflow refuses to call the issue done until it is, and any exception is
one they consciously approved. What changes for the next reader of the issue's PR is that
"done" is reliable: it carries no quiet footnotes standing in for unfinished work.

## User Journeys

### An author hands off an issue with a project-specific verification

An author runs `/work-on` on one issue in a repo that declares its own verification (for
shirabe: an issue that changes a skill must have that skill's evals executed and passing;
for another project: touched packages must pass their tests). `/work-on` detects what the
issue's change touched, runs the declared verification, and only reports the issue done once
it passes. If the verification was authored but not run, the workflow runs it — existence is
not a substitute.

### An author hands off an issue in a repo with no declared verification

An author runs `/work-on` on one issue in a project that declares nothing specific. The
workflow falls back to the repo's standard test command, runs it, and requires it to pass
before the issue is done. The definition of done still binds; the project simply did not
need to customize what "verified" means.

### An acceptance criterion of the issue cannot be met this session

Partway through one issue, `/work-on` finds an acceptance criterion it cannot satisfy now (a
flaky external dependency, a deliberately phased step). Instead of reporting the issue done
with a quiet caveat, the workflow surfaces the unmet criterion to the human and asks for an
explicit decision: approve the deferral (recorded as the human's choice) or treat the issue
as blocked. The agent never resolves this on its own.

### A reviewer trusts the single-issue PR

Someone opens the PR for one finished issue. They do not find hedge language standing in for
unfinished work, and they do not need to re-verify the issue's acceptance criteria. Either
every criterion was verified by execution, or a deferral is present and visibly carries the
human's approval. "Done" reads as done.

## Scope Boundary

### In

- Making `/work-on`'s single-issue completion a workflow-enforced definition of done rather
  than the agent's discretionary judgment, applied at the point `/work-on` decides one issue
  is finished.
- The verified-by-execution principle at the per-issue level: each of the issue's acceptance
  criteria is backed by verification that ran and passed, and "the verification exists" never
  counts as "it passed."
- A project-declared verification surface: `/work-on` learns what to run for what the issue
  touched from the project, with a sensible default (the repo's standard tests) when nothing
  is declared. The generic workflow holds the principle; the project holds the specifics.
- The no-silent-deferral rule: any unmet criterion or deferral is a surfaced, human-approved
  decision, and unapproved caveat language in the result is disallowed.
- The shirabe-specific instance of the project-declared surface: shirabe declares that an
  issue changing a skill requires that skill's evals to be executed and passing (closing the
  exact gap that motivated this brief), expressed through shirabe's own `/work-on`
  configuration rather than baked into the generic skill.

### Out

- Plan-level, milestone, and coordinated multi-PR execution and *their* completion. Those
  belong to the separate implementation-altitude coordinator; this brief is single-issue
  only and does not define done for a set of issues.
- The scope reduction itself — narrowing `/work-on` to a single issue and moving plan
  iteration out — which is a separate effort this brief assumes rather than performs.
- The exact mechanism by which `/work-on` (koto-driven) encodes the gate — a new state, a
  modified finalization contract, or a blocking decision gate — and how the project declares
  its verification map (an extension file, a CLAUDE.md header, or other config). Those are
  downstream DESIGN decisions.
- Re-defining what verification each non-shirabe project should run. The capability lets a
  project declare its map; it does not prescribe other projects' commands.
- Changes to the underlying test/eval runners themselves. The capability runs a project's
  existing verification; it does not build new verification tooling.
- A blanket ban on the word "experimental" or on any caveat. The boundary is unilateral,
  unapproved hedging — a deliberately phased step the human approves is legitimate.

## References

- `skills/work-on/SKILL.md` — the workflow whose single-issue completion this brief
  constrains, including its finalization state and its `.claude/shirabe-extensions/work-on.md`
  project-extension hook.
- `CLAUDE.md` (`## Skill Evals`) — the existing shirabe rule that evals must be run, not just
  exist, which `/work-on` does not currently enforce; the shirabe instance of this brief makes
  the workflow enforce it for an issue that changes a skill.
