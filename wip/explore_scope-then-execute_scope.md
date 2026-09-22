# Explore Scope: scope-then-execute

## Visibility

Public

## Execution Mode

auto (background session with a standing goal; the author asked not to pause)

## Core Question

Can one agent session take a feature from `/scope` all the way to merged code
when the PLAN it produces is `single-pr` or `coordinated`, given that the
execution mode is only decided inside `/scope` (at `/plan`'s decomposition
step)? And if the PLAN comes out `multi-pr`, what should that same session do
instead of stalling on merges it can't perform?

## Context

The skills split cleanly by altitude: `/charter` is strategic, `/scope` is
tactical and always ends in a PLAN, `/execute` drives a finished PLAN. The
PLAN's `execution_mode` is what decides whether one session can finish the
work. `single-pr` and `coordinated` plans can run to completion in one session;
a `multi-pr` plan blocks on each PR being merged, which fits better as one
session writing the scoping docs and then one session per PR. The author wants
to launch a single session with the goal "run `/scope`, then `/execute` the
PLAN, done only when everything is implemented and merged", but can't know at
launch time which mode `/scope` will pick. Sessions may not have merge rights.

## In Scope

- How `/scope` ends and what it hands off
- How `/plan` decides the execution mode, and whether that can be steered or
  known early
- How `/execute` consumes single-pr and coordinated PLANs, including who merges
- Composition between parent skills (can one chain into another)
- What a combined session should do when the PLAN lands `multi-pr`

## Out of Scope

- Redesigning the execution modes themselves
- `/charter` and the strategic chain beyond using it as a composition precedent
- niwa internals beyond whether `niwa dispatch` is a usable fan-out target

## Research Leads

1. **How does `/scope` finish today, and what does its exit hand to the next step?** (lead-scope-exit)
   Exit finalization, the state it writes (`plan_execution_mode:`), the message
   it ends with, and whether any route to `/execute` exists already.

2. **How does `/plan` choose the execution mode, and can a caller steer or learn it early?** (lead-mode-decision)
   Step 3.6 criteria (incremental value, hard constraint, stated preference),
   whether a flag or constraint can bias toward single-pr, and at what point in
   the chain the mode becomes knowable.

3. **What does `/execute` need to take a single-pr or coordinated PLAN to merged, and who merges?** (lead-execute-merge)
   Its inputs, its exit paths, whether it merges or stops at a green PR, and
   what "done" means for a session without merge rights.

4. **How do parent skills compose, and is there a precedent for one chaining into another?** (lead-parent-composition)
   `/charter` into `/scope`, koto templates, the parent-skill state schema,
   routing tables in `/explore` and `/work-on`; what a `/scope` -> `/execute`
   hop would have to respect.

5. **When a combined run lands a multi-pr PLAN, what should the session do?** (lead-multi-pr-fallback)
   How `/work-on` runs multi-pr plans, what a clean stop after scoping looks
   like, and whether per-PR sessions (e.g. `niwa dispatch`) are a reasonable
   handoff target.
