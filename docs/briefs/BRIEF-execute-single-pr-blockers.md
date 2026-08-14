---
schema: brief/v1
status: Accepted
problem: |
  Two defects stop /execute's koto-driven single-pr path before it can do any
  work. The worktree-discipline gate tests a path built from a shell variable
  koto never sets, so it can never pass; and the task-generation script uses a
  bash 4 construct on a platform whose system bash is 3.2. Neither failure names
  its cause, so a developer who hits them has no route forward but to guess.
outcome: |
  A developer runs /execute against a single-pr plan on a stock macOS host and
  the documented path carries them through: the worktree-discipline gate clears
  once the impact classification is written where the directive says to write
  it, task generation emits the issue list, and a precondition that genuinely
  fails says what is missing instead of reporting a bare exit code.
motivating_context: |
  Surfaced by the first real /execute --auto run against a single-pr plan on
  macOS. Both defects were worked around by hand so the run finished, but
  neither workaround is discoverable, and both stop the documented path cold.
---

# BRIEF: execute-single-pr-blockers

## Status

Accepted

Framing for the two defects that block `/execute`'s single-pr path. The
downstream PRD owns the requirements; the DESIGN owns the choice of mechanism
for each fix.

## Problem Statement

`/execute`'s single-pr path is documented as a path a developer can follow.
Two defects mean they cannot: each one halts the run at a different step, and
neither is recoverable without already knowing the workaround.

The first is a variable that never expands. The koto template's
worktree-discipline state gates on a file whose path is built from a slug the
directive prose tells the agent to derive in its own shell. That derivation
never reaches the environment koto evaluates the gate in, so the gate tests a
path with an empty slug in the middle of it. The agent writes the classification
exactly where the directive says to, the gate looks somewhere else, and the
state never advances. What the developer sees is a gate failing with an exit
code and nothing else — no path, no expansion, no indication that the file they
just wrote was never the file being tested.

The second is a portability break. The script that turns a plan's issue outlines
into tasks declares an associative array, a construct bash gained in version
4.0. macOS ships bash 3.2 as its system bash and has for licensing reasons that
are not going to change. On any macOS host without a separately installed
bash 5, the script dies at that line before emitting a single task, and the step
that consumes its output has nothing to submit. This is not an exotic
configuration; it is the default one for a large share of the developers the
skill is written for.

Both defects share a shape worth naming. Each is a precondition that fails for
a reason the failure does not report — an unexpanded variable and an unsupported
shell are both invisible in the output the developer gets. A developer who
cannot see why a step failed cannot route around it, which is why two small
defects cost a whole run rather than two minutes each.

## User Outcome

A developer taking a single-pr plan through `/execute` on their own machine
reaches the end of the run without leaving the documented path. The
worktree-discipline step writes its impact classification and the gate clears
on that file. Task generation reads the plan's issue outlines and emits the
task list whatever bash the host provides. The developer never learns that a
slug had to be interpolated a particular way or that the script needed a shell
newer than the one their operating system ships, because neither fact ever
becomes their problem.

When a precondition does genuinely fail — no classification was written, the
plan has no parseable outlines — the developer reads a message that names what
is missing and where it was expected. The distinction that matters to them is
between "the workflow is broken" and "my input is incomplete", and the failure
output now lets them tell which one they are looking at.

## User Journeys

### A developer runs /execute on a stock macOS host

A shirabe developer on macOS, with no Homebrew bash installed, invokes
`/execute` against a single-pr plan. Task generation runs under the system
bash and emits the plan's issues as tasks. The developer does not inspect their
bash version, install a newer one, or hand-derive the task list from the plan's
outlines — the run proceeds to the point where the tasks are submitted.

### A developer watches the worktree-discipline gate clear

A developer whose run has reached the worktree-discipline step watches the
agent classify the upstream impact and write the classification to the path the
directive names. The gate evaluates against that same path, observes the file,
and the state advances. The developer does not create a second copy of the file
at a different path to unblock the gate.

### A developer reads why a precondition actually failed

A developer whose plan is genuinely incomplete — no issue outlines the script
can parse, or a worktree-discipline step that produced no classification — runs
`/execute` and hits the failing step. The output names the missing input and
where it was expected. The developer corrects the plan and re-runs, rather than
opening the koto template to work out what the gate was testing.

## Scope Boundary

**IN:**

- The `impact_classified` gate in `skills/execute/koto-templates/execute.md`
  resolving against the path the worktree-discipline directive writes to.
- A sweep of the same template and its sibling koto templates for other gate or
  command strings that interpolate a variable koto does not set, so the fix
  closes the defect class rather than the one instance that was hit.
- `skills/plan/scripts/plan-to-tasks.sh` running to completion under the bash a
  stock macOS host provides.
- Failure output that names the missing input for both preconditions, so a
  genuine input problem is distinguishable from a broken workflow.

**OUT:**

- A redesign of how koto templates receive variables. The fix makes the
  existing gates resolve correctly; changing the template variable model is a
  separate piece of work with a much larger blast radius.
- The multi-pr and coordinated `/execute` paths. Neither defect is reachable
  from them, and widening the change to paths this run did not exercise adds
  risk without evidence.
- Raising shirabe's supported-bash floor as a project-wide policy. This work
  makes one script run under the bash macOS ships; deciding what the whole repo
  requires is a separate decision that would need its own audit.
- The pre-existing data race in `tsukumogami/niwa`'s `internal/cli`, observed
  during the same run. It lives in another repository, predates this work, and
  is tracked there.

## References

- `skills/execute/koto-templates/execute.md` — the koto template carrying the
  `impact_classified` gate.
- `skills/plan/scripts/plan-to-tasks.sh` — the task-generation script.
- `docs/briefs/BRIEF-execute-friction.md` — the prior framing of `/execute`
  friction, from the skill's first end-to-end use.
