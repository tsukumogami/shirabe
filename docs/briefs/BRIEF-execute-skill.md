---
schema: brief/v1
status: Done
problem: |
  The implementation flow does double duty: one workflow both runs a single issue
  and iterates a whole plan of many issues. So there is no implementation-altitude
  coordinator that owns plan-level execution, and a plan coordinated across
  repositories has nowhere durable to hold its across-issue picture.
outcome: |
  Plan-level execution becomes its own coordinator: an author hands a finished plan
  off in one move and it iterates the plan's issues to merged code — a single
  pull request, or coordinated across repositories — with progress against the
  whole, a single done-signal, and cross-branch resume. The single-issue executor
  narrows to exactly that one job, which the coordinator delegates to.
motivating_context: |
  The strategic chain (/charter) and tactical chain (/scope) already ship as
  single-agent parent skills in a shared pattern; the implementation altitude is
  the remaining gap. shirabe#196 added multi-repo coordinated execution — a single
  run across repositories with a merge-order coordination pull request — and the
  plan-iteration responsibility currently bundled into the single-issue executor
  (single-pull-request orchestration plus this coordinated mode) is the natural
  thing for the new coordinator to own. See tsukumogami/shirabe#196.
---

# BRIEF: execute-skill

## Status

Done

This brief frames the implementation-altitude coordinator and the responsibility
split that comes with it, and stops before requirements. The coordinator is a new
skill: `/work-on` persists as the single-issue executor the coordinator delegates
to, so there is nothing to rename. The downstream PRD owns the requirements; the
downstream design owns the technical calls, including whether the coordinator's plan
iteration uses koto or not.

## Problem Statement

shirabe gives authors two coherent parent-skill experiences. The strategic chain
walks an author from thesis to sequenced features as one held conversation; the
tactical chain walks a feature from framing to a finished plan the same way. In
both, the author talks to one coordinator that holds state across steps, delegates
each step to a child, and inspects only what it needs to before moving on.

The implementation altitude — taking a finished plan and turning it into merged
code — has no such coordinator, and the reason is a tangle of responsibilities. The
single workflow that executes work today does two jobs at once: it runs a single
issue to a merged pull request, and it iterates a whole plan of many issues to
completion. Bundling both into one place has two costs. There is no clean
plan-level coordinator an author can hand a finished plan to and watch it run; and
the single-issue path is weighed down by plan-orchestration concerns that do not
belong at the altitude of one issue.

The cost is sharpest on the plans where coordination matters most: a plan whose
issues land as several pull requests across repositories that must merge in a
defined order. Nothing durable holds the across-issue picture — what has merged,
what is blocked behind what, what comes next, whether the whole set is done — so an
author tracks it by hand and loses it entirely when a session ends.

## User Outcome

Plan-level execution becomes a coordinator of its own, completing the parent-skill
trio. An author who has finished a plan hands the whole plan off in a single move
and then experiences the implementation altitude the way they already experience
the other two chains: one conversation holds the state, each issue in the plan is
delegated and driven to merged code without the author dispatching it by hand, and
progress is reported against the whole plan rather than reconstructed from a wall of
pull requests.

A plan that resolves to a single pull request runs straight through. A plan
coordinated across repositories is walked in merge order on the author's behalf,
arriving at a single, unambiguous signal that the whole set is done. Stepping away
and coming back — even on a different branch, even in a new session — resumes
exactly where it left off, because the plan's own durable coordination state is the
source of truth.

Underneath, the single-issue executor narrows to exactly one job: take one issue to
a merged pull request, well. It stops carrying plan-orchestration weight; the
coordinator owns that, and calls down to the executor one issue at a time.

## User Journeys

The first two journeys are the two plan shapes the coordinator owns; the third is
the cross-cutting resume path that applies to either.

### Author runs a single-pull-request plan

A feature author has finished a plan whose issues all land in one pull request.
They hand the plan to the coordinator in one move. With no cross-pull-request merge
order to track, it iterates the plan's issues in order, delegating each to the
single-issue executor, drives the one pull request to merged, and reports the plan
complete. The author stays in one conversation and never dispatches an issue by hand.

### Author runs a coordinated multi-repo plan

An author has a plan whose issues land as several pull requests across repositories
that must merge in a defined order. They hand the whole plan to the coordinator. It
walks the merge order, delegating each issue to the single-issue executor, surfacing
progress against the whole as pull requests land, and signaling the plan done only
when the coordinated set has fully merged. The author tracks one conversation, not a
wall of pull requests across repositories.

### Author resumes an interrupted plan execution

An author started executing a coordinated plan, then closed the session partway
through — or picked the work back up on a different branch. They re-invoke the
coordinator against the same plan. Rather than starting over or asking where things
stood, it reads the plan's durable coordination state, recognizes which issues and
pull requests have merged, and picks up at the next unit of work.

## Scope Boundary

### In

- A single plan-level coordinator (working name `/execute`) that completes the
  parent-skill trio alongside the strategic and tactical chains, in the same
  single-agent shape.
- Owning plan-based execution end to end for two shapes: single-pull-request plans
  (many issues driven through one shared pull request — the orchestration that lives
  in the single-issue executor today), and coordinated multi-repo plans (a single run
  across repositories with a merge-order coordination pull request, per the
  coordination contract).
- Delegating each individual issue down to the single-issue executor.
- Narrowing the single-issue executor to single-issue work, by moving the
  plan-iteration responsibility it holds today out of it and into the coordinator.
- Inspecting each issue and pull request only through its status surface, reporting
  progress against the whole plan, with a single done-signal for a coordinated set.
- Resuming from the plan's own durable coordination state, including across branches
  and sessions.

### Out

- The mechanics of executing one issue. Those stay in the single-issue executor
  (koto-based today), which the coordinator calls down to rather than replaces.
- Multi-pull-request plans within a single repository. These remain implemented one
  issue at a time through the single-issue executor — each issue its own pull request
  — not driven by the coordinator. The coordinator owns single-pull-request plans and
  coordinated multi-repo plans only.
- Whether the coordinator's plan iteration uses koto or a different mechanism, and
  the exact state and resume machinery. Downstream design owns these, given the work
  may go either way.
- Building the shared coordination substrate the coordinator relies on for
  cross-session, cross-branch state. The coordinator consumes a durable coordination
  home when one exists; providing that substrate is separate amplifier work.
- The review-time redirect mechanism (changing course mid-execution in response to a
  human redirect). Separate downstream feature.

## Open Questions

- Whether the coordinator's plan iteration reuses the existing koto plan-orchestration
  machinery or a new, possibly non-koto, mechanism. The downstream design owns this,
  given the explicit latitude to go either way.
- The precise contract by which the coordinator hands a single issue to the
  single-issue executor, and how that composes with the coordinated mode's per-repo
  and per-pull-request grouping.
- Whether the single-issue executor remains directly invocable on its own for
  one-off issues, or is reached only through the coordinator. The PRD owns this
  boundary detail.

## References

- `docs/designs/current/DESIGN-shirabe-progression-authoring.md` — the parent-skill
  progression pattern this feature extends to the implementation altitude.
- `references/coordination-strategy.md` — the coordinated execution-mode contract a
  coordinated multi-repo plan is orchestrated against.
- The `/charter` (strategic) and `/scope` (tactical) skills — the precedent parent
  skills whose single-agent shape and metadata-only child inspection this feature
  mirrors.
- tsukumogami/shirabe#196 — the work that enabled multi-repo coordinated execution
  (a single run across repositories with a merge-order coordination pull request).
