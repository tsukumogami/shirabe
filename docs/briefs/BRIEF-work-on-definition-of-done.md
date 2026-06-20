---
schema: brief/v1
status: Draft
problem: |
  `/work-on` can report work as "done" when it is only partially done. Verification
  artifacts get authored but never executed (evals written, not run; a test added, not
  run), and caveats or deferrals get introduced unilaterally as footnotes in the
  deliverable. The workflow has no enforced definition of done — the completion judgment
  lives in the agent's head, not in the workflow — so incomplete work passes as complete
  and the human is left to catch the gap.
outcome: |
  `/work-on` treats completion as verified-by-execution. For whatever a change touched, it
  runs the project's declared verification (defaulting to the repo's tests) and requires it
  to pass before calling the work done; any deferral becomes a surfaced, human-approved
  decision rather than an agent-authored footnote. The author can trust that "done" means
  done, without auditing for hidden caveats.
motivating_context: |
  This brief exists because the gap was hit directly: during a `/work-on` run, skill evals
  were authored but not executed, the work was reported complete, and hedge language was
  introduced into shipped docs — leaving the human to discover the shortfall. The recurring
  risk is that "looks done" substitutes for "is done." The fix belongs in the workflow, not
  in per-run vigilance.
---

# BRIEF: work-on Definition of Done

## Status

Draft

## Problem Statement

`/work-on` drives work from an issue or plan to a pull request. At the end of that drive it
decides the work is finished and moves on — but nothing in the workflow defines or checks
what "finished" means. The completion criterion is the agent's judgment, applied case by
case, and that judgment is fallible in a specific, repeating way: it accepts *evidence that
work was attempted* in place of *evidence that work was verified*.

Two failure modes recur, and both shipped recently:

- **Verification authored but not executed.** A skill's evals were written and committed,
  the existence check passed, and the work was reported done — but the evals were never run,
  so there was no evidence the behavior was correct. "The verification exists" was treated
  as "the verification passed."
- **Unilateral caveats and deferrals.** Hedge language ("experimental", "not yet run",
  "current limitations") and deferred items were introduced into the deliverable by the
  agent on its own initiative, turning an incomplete result into one that *reads* complete
  with a footnote. The deferral was never a decision the human made; it was one the human
  had to catch.

The cost lands on the person who asked for the work. They are told it is done, they
reasonably assume it is done, and they instead inherit the job of auditing for what was
quietly skipped. Trust in "done" erodes, and the workflow's whole value — handing off work
and getting back a finished result — is undermined. The gap is the absence of an enforced
definition of done in the workflow itself; it is not a gap in any one project's conventions.

## User Outcome

The author hands work to `/work-on` and trusts the result. Completion stops being the
agent's private judgment and becomes a workflow gate with two properties:

- **Verified-by-execution, not addressed.** Before `/work-on` calls work done, the
  verification appropriate to what the change touched has actually *run and passed* — not
  merely been authored or confirmed to exist. The workflow learns what to run from the
  project rather than hard-coding any one stack's commands, and falls back to the repo's
  standard tests when the project declares nothing.
- **No silent deferral.** The agent cannot, on its own, downgrade "done" to "done with
  caveats." Any deferral or unmet criterion is surfaced to the human as an explicit
  decision; absent that approval, the work is reported as blocked, not done. Caveats in the
  deliverable exist only when the human chose them.

What changes for the author is that they no longer audit for hidden shortfalls — the
workflow refuses to call work done until it is, and any exception is one they consciously
approved. What changes for the next person reading the result is that "done" is reliable:
the deliverable does not carry quiet footnotes substituting for finished work.

## User Journeys

### An author hands off work that has a project-specific verification

An author runs `/work-on` on a change in a repo that declares its own verification (for
shirabe, that a skill change must have its evals executed and passing; for another project,
that touched packages must pass their tests). `/work-on` detects what the change touched,
runs the declared verification, and only reports done once it passes. If the verification
was authored but not run, the workflow runs it — it does not accept existence as a
substitute.

### An author hands off work in a repo with no declared verification

An author runs `/work-on` in a project that declares nothing specific. The workflow falls
back to the repo's standard test command, runs it, and requires it to pass before
completion. The definition of done still binds; the project simply did not need to
customize what "verified" means.

### A criterion genuinely cannot be met this session

Partway through, `/work-on` finds an acceptance criterion it cannot satisfy now (a flaky
external dependency, a deliberately phased rollout). Instead of shipping the result with a
quiet caveat, the workflow surfaces the unmet criterion to the human and asks for an
explicit decision: approve the deferral (and record it as the human's choice) or treat the
work as blocked. The agent never resolves this on its own.

### A reviewer or future reader trusts the result

Someone opens the finished PR. They do not find hedge language standing in for unfinished
work, and they do not need to re-verify what the workflow claimed. Either every criterion
was verified by execution, or a deferral is present and visibly carries the human's
approval. "Done" reads as done.

## Scope Boundary

### In

- Making `/work-on`'s completion a workflow-enforced definition of done rather than the
  agent's discretionary judgment, applied at the point `/work-on` decides work is finished.
- The verified-by-execution principle: the verification appropriate to what a change touched
  must have run and passed, and "the verification exists" never counts as "it passed."
- A project-declared verification surface: `/work-on` learns what to run for which kinds of
  changes from the project it is operating on, with a sensible default (the repo's standard
  tests) when nothing is declared. The generic workflow holds the principle; the project
  holds the specifics.
- The no-silent-deferral rule: any deferral or unmet criterion is a surfaced, human-approved
  decision, and unapproved caveat language in the deliverable is disallowed.
- The shirabe-specific instance of the project-declared surface: shirabe declares that a
  skill change requires its evals to be executed and passing (closing the exact gap that
  motivated this brief), expressed through shirabe's own `/work-on` configuration rather than
  baked into the generic skill.

### Out

- The exact mechanism by which `/work-on` (a koto-driven workflow) encodes the gate — a new
  state, a modified finalization contract, or a blocking decision gate — and how the
  project declares its verification map (an extension file, a CLAUDE.md header, or other
  config). Those are downstream DESIGN decisions.
- Re-defining what verification each non-shirabe project should run. The capability lets a
  project declare its map; it does not prescribe other projects' verification commands.
- Changes to the underlying test/eval runners themselves. The capability runs a project's
  existing verification; it does not build new verification tooling.
- The other shirabe skills' completion behavior beyond `/work-on`. This frames `/work-on`'s
  definition of done; generalizing the principle to other skills is a separate question.
- A hard ban on the word "experimental" or on any caveat. The boundary is unilateral,
  unapproved hedging — a deliberately phased rollout the human approves is legitimate.

## References

- `skills/work-on/SKILL.md` — the workflow whose completion this brief constrains, including
  its finalization state and its `.claude/shirabe-extensions/work-on.md` project-extension hook.
- `CLAUDE.md` (`## Skill Evals`) — the existing shirabe rule that evals must be run, not just
  exist, which `/work-on` currently does not enforce; the shirabe instance of this brief makes
  the workflow enforce it.
