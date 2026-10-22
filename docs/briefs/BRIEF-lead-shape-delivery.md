---
schema: brief/v1
status: Accepted
problem: |
  A delivery session that runs a multi-step plan drives every step's work in
  its own context, so a long plan runs it to the edge of its window. The shape
  that keeps it thin works only when the person dispatching the session writes
  it into the prompt, and the skills still describe teams nothing builds.
outcome: |
  Whoever hands a plan to /deliver gets a stepped run without writing any
  execution instructions: each step runs in its own agent, which reviews its
  own work, the owning session details each next step from what landed, and a
  step's review level follows the step's own size.
motivating_context: |
  Delivery runs that handed each step to its own agent, with the owning session
  detailing the next step between them, stayed thin where runs that drove every
  step inline came close to the context limit and compacted. Those runs got the
  shape from instructions in their prompt; nothing in the skills carries it.
---

## Status

Accepted

## Problem Statement

`/deliver` runs `/scope` and then `/execute` in one session, and `/execute`
drives every step of the plan through a `/work-on` child in that same session's
context. Each child reads the issue, plans, implements, runs two or three
review panels and watches CI, and all of it stays in the session that owns the
plan. A plan of four or more steps leaves that session holding most of its
window by the last step, and a run that goes past the window compacts, losing
the thread of what earlier steps decided.

Runs that handed each step to its own agent, with the owning session detailing
the next step between them, grew the owning session by a small fraction of what
an inline step adds. But a session gets that shape only when the person or
coordinator who dispatched it remembers to write a paragraph of execution
instructions into its prompt. A prompt that forgets the paragraph gets the
inline run and its risk of compaction, and a person running `/execute` by hand
has no paragraph to write and no way to get the shape at all.

Three things in the skills stand in the way of making that shape the default,
which is why they belong with it:

- Seven skills carry a `team.yaml` file declaring a team of peers to build per
  invocation. No code reads them; they describe a team runtime that doesn't
  exist, and a reader takes them for a contract.
- The pattern reference says a subagent never spawns subagents. A step agent
  that drives a `/work-on` child has to spawn that step's review seats, so the
  rule as written forbids the shape that works.
- Every step in recent multi-step runs finished its review at `full`, the
  heaviest level, including steps that chose `standard` and were small. The
  review-level rules never say what a step's level should be when it is one
  step of a larger change on a shared branch, so nothing tells a reader whether
  that result is right.

## User Outcome

A person or coordinator who hands a plan to `/deliver` gets the thin, stepped
run without writing a word about how to run it. Each step goes to its own step
agent, which drives the step to its end and spawns that step's reviewers; the
owning session keeps a short report per step, details the next step from what
the landed steps taught, and has room left for the last step and the pull
request. A run that starts long into its context, after a long scoping
conversation, still finishes its steps.

A contributor who reads the delivery skills finds the shape stated there: who
details the next step and when, how a step agent is started, that it may spawn
its review seats, and how its review level is chosen. Every team or agent a
skill describes is one a run actually starts, so the contributor can take the
description as the contract.

## User Journeys

### A coordinator dispatches a milestone with a plain brief

A coordinator dispatches a `/deliver` session for a feature whose plan comes
out at five steps. The brief names the outcome, the decisions already made and
the checkpoints, and says nothing about how to execute. The session scopes the
feature, then runs each step through its own step agent and details steps two
to five itself, each after the previous step's child finished. The coordinator
reads the run afterwards and finds every step delegated and every later step
detailed before it was driven.

### A maintainer resumes a half-done plan after a long scoping session

A maintainer scoped a large feature in one long conversation, which used about
half the session's window, and the session stopped after step two of six. They
re-invoke `/deliver` on the topic. The run picks up at step three, keeps the
scoping detail it no longer needs out of its context, and carries steps three
to six and the pull request without compacting.

### A reviewer reads a step's review record

A reviewer of the finished pull request opens one step's record and finds the
scrutiny and review panels that step's own agent ran, each seat's verdict
folded into the step, at the level the step's size called for. Nothing in the
skills told that agent it couldn't start those seats, so no step skipped its
panels or fell back to reviewing itself.

### A contributor reads how review depth is chosen

A contributor wonders why a two-file prompt change on step four of a plan went
through the full review. The review-level rules say how a step's level is
chosen when it is one step of a larger change: which commits count toward the
step's facts, and why. The step's ledger shows a level that follows those
rules, not one inflated by the steps before it.

## Scope Boundary

**In scope:**

- The lead shape built into the delivery skills (`/deliver`, `/execute`,
  `/work-on`), so a session runs it with no execution instructions in its
  prompt: one step agent per step, the owning session detailing each next step
  between children, a short report per step, and a check that each child
  reached its terminal before the next step starts.
- Keeping enough of the owning session's context for execution when scoping
  has already used a large part of it.
- Retiring the seven `team.yaml` files and the prose and pattern-reference
  text that points at them.
- Replacing the rule that a subagent never spawns subagents with the rule that
  a step agent may spawn its step's review seats.
- The review-level rules for a step of a larger change: how its level is
  chosen and which commits count toward its facts.

**Out of scope:**

- The plan format and `/plan`'s guidance on step sizing and outlines. The shape
  uses step plans as they are.
- Running steps in parallel. The shape runs one step at a time because each
  step's outline is detailed from what the step before it landed, which two
  steps running at once can't do.
- Any change to koto or to niwa. The shape is built from the agent tooling and
  the koto features the skills already use.
- `/coordinate`'s own dispatch and record scripts. A coordinator stops
  carrying an execution-shape item in its briefs, but how it dispatches a
  worker is unchanged.
- The parent-skill dispatch of `/scope` and `/charter` children, which run
  inline in their parent's context and are not steps of a plan.
- Changing the review panels themselves: their seats, rubrics and verdict
  shapes.
