---
schema: prd/v1
status: Accepted
problem: |
  Two defects stop /execute's koto-driven single-pr path before it does any
  work. The worktree-discipline gate is written with shell interpolation syntax
  (`${PLAN_SLUG}`) that koto does not resolve and does not validate, so the gate
  tests a path with an empty slug and can never pass. The task-generation script
  uses bash 4 associative arrays in seven places and dies at the first one on
  macOS, whose system bash is 3.2. Both failures report a bare exit code or a
  syntax error with no route forward, so a developer who hits either has to read
  the template or the script to find out what happened.
goals: |
  Make /execute's single-pr path completable on a stock macOS host without
  hand-holding: the worktree-discipline gate resolves against the path the
  directive actually writes to, the task-generation script runs to completion
  under the bash macOS ships, and a precondition that genuinely fails names the
  input it is missing. Close both defect classes rather than the two instances
  that were hit, with a mechanical check that catches reintroduction.
source_issue: 270
motivating_context: |
  The first real /execute --auto run against a single-pr plan on macOS hit both
  defects. Both were worked around by hand and the run finished green, so
  neither is a correctness problem in the produced artifacts -- but neither
  workaround is discoverable, and together they make the documented path
  unusable on a default macOS host.
---

# PRD: execute-single-pr-blockers

## Status

Accepted

Requirements for the two defects blocking `/execute`'s single-pr path, from
issue #270. The framing that opened this chain was absorbed into this document
rather than kept as a standalone BRIEF — every section of it had a home here.
Mechanism choices are deferred to the downstream DESIGN and recorded under
Decisions and Trade-offs.

## Problem Statement

A developer who runs `/execute` against a single-pr plan is following a path
shirabe documents as complete. On a default macOS host it is not: two defects
halt the run at different steps, and neither reports enough for the developer
to route around it.

The first is an interpolation that never resolves.
`skills/execute/koto-templates/execute.md` gates its `worktree_discipline_check`
state on `test -f wip/work-on_${PLAN_SLUG}_impact.json`. koto resolves template
variables written as `{{KEY}}` and validates at compile time that every such
reference is declared in the template's `variables:` block. `${PLAN_SLUG}` is
neither: it is not a koto reference, so the compile-time check does not see it,
and koto passes the string through to `sh -c` verbatim. The shell then expands
an unset variable to the empty string, and the gate tests
`wip/work-on__impact.json` — a path nothing ever writes. `PLAN_SLUG` is derived
in the directive prose for the agent to use in its own shell, and that
derivation never reaches the environment koto evaluates the gate in. The state
cannot advance no matter what the agent does correctly.

The second is a portability break. `skills/plan/scripts/plan-to-tasks.sh`
declares associative arrays — a bash 4.0 construct — in seven places. macOS
ships bash 3.2.57 as `/bin/bash` for licensing reasons that will not change,
and the script's shebang is `#!/usr/bin/env bash`. On a macOS host with no
separately installed bash 5, the script fails at the first declaration and
exits before emitting a single task, so the step that consumes its output has
nothing to submit. The originally reported instance was one line; it was simply
the first of seven to execute.

What makes two small defects cost a whole run is that neither says what went
wrong. koto reports a failed command gate as `{"exit_code": 1, "error": ""}` —
the gate's own stdout and stderr are discarded before the result reaches the
caller — so the developer sees a number and no path. The script's failure is a
bash syntax error naming an invalid option, which describes the symptom and not
the requirement behind it. In both cases the developer has to open the source to
learn what the step wanted.

## Goals

- A developer on a default macOS host completes `/execute`'s single-pr path
  without installing a newer bash, hand-deriving the task list, or creating a
  shadow file to satisfy a gate.
- The worktree-discipline gate tests the same path the worktree-discipline
  directive writes to, for every plan slug.
- Both defect classes are closed, not just the instances that were hit: no koto
  template shirabe ships carries an interpolation koto will not resolve, and no
  script on the single-pr path depends on a bash newer than the platform floor.
- A precondition that genuinely fails tells the developer what input is missing
  and where it was expected, so an incomplete plan is distinguishable from a
  broken workflow.
- Reintroduction of either defect class is caught mechanically rather than by
  the next developer's run.

## User Stories

- As a shirabe developer on macOS with no Homebrew bash, I want `/execute`'s
  task generation to run under the bash my system ships, so that I can take a
  plan through the documented path without first changing my shell environment.
- As a developer whose run has reached the worktree-discipline step, I want the
  gate to observe the classification I wrote at the documented path, so that
  the run advances without my creating a second copy of the file somewhere else.
- As a developer whose plan is genuinely incomplete, I want the failing step to
  name the input it is missing, so that I can fix my plan instead of reading
  the koto template to work out what was being tested.
- As a shirabe maintainer reviewing a change to a koto template or a workflow
  script, I want an automated check to reject a reintroduced interpolation or
  bash-version defect, so that the next developer's run is not the detector.

## Requirements

### Functional

- **R1 — The worktree-discipline gate resolves the plan slug.** The
  `impact_classified` gate in `skills/execute/koto-templates/execute.md` SHALL
  evaluate against the same path the worktree-discipline directive instructs the
  agent to write, for any plan slug the single-pr path can produce. The gate
  SHALL pass when that file exists and SHALL fail when it does not.
- **R2 — No unresolvable interpolation in shipped koto templates.** No koto
  template shirabe ships SHALL contain a variable interpolation that koto does
  not resolve. Shell-style `${NAME}` interpolation is not resolved by koto and
  is not covered by its compile-time declared-reference check, so it SHALL NOT
  appear in any template field koto passes to a shell or to an agent, with the
  exception of koto's own `${evidence.<field>}` reference namespace, which koto
  resolves itself.
- **R3 — Task generation runs on the platform bash floor.**
  `skills/plan/scripts/plan-to-tasks.sh` SHALL run to completion on a host whose
  only available bash is 3.2, for every plan the script accepts today. All seven
  associative-array uses are in scope, not only the first one to execute.
- **R4 — Identical output across bash versions.** For any given plan, the task
  list `plan-to-tasks.sh` emits under bash 3.2 SHALL be byte-identical to the
  list it emits under bash 5, including task ordering, generated names, and
  collision-suffixed names.
- **R5 — Diagnosable preconditions.** When either precondition genuinely fails,
  the developer-facing output SHALL name the missing input and the path where it
  was expected. For the gate, whose stdout and stderr koto discards, the naming
  SHALL be carried by the surface koto does surface to the agent on a blocked
  gate rather than by the gate command's own output.
- **R6 — Mechanical regression check.** A check runnable in CI SHALL fail on
  reintroduction of either defect class: an unresolvable interpolation in a
  shipped koto template, and a bash-4-or-newer construct in a script on the
  single-pr path.

### Non-functional

- **R7 — No behavior change where the path already worked.** On a host with
  bash 5 and on the multi-pr and coordinated execution paths, the observable
  behavior of `/execute` and `plan-to-tasks.sh` SHALL be unchanged.
- **R8 — No new runtime dependency.** Meeting R3 SHALL NOT require installing a
  newer bash, a different interpreter, or any tool not already required to run
  `/execute`.

## Acceptance Criteria

- [ ] With a plan whose slug is non-empty, the `impact_classified` gate passes
      when the impact classification exists at the path the worktree-discipline
      directive names, and fails when it does not.
- [ ] No shipped koto template contains a `${NAME}` interpolation outside koto's
      `${evidence.<field>}` namespace.
- [ ] `plan-to-tasks.sh` runs to completion under `/bin/bash` on macOS (bash
      3.2.57) against a representative multi-issue plan, emitting the full task
      list.
- [ ] For the same plan, the output of `plan-to-tasks.sh` under bash 3.2 and
      under bash 5 is byte-identical, including a plan that exercises slug
      collision handling.
- [ ] A run whose impact classification was never written surfaces output naming
      the expected file path, not a bare exit code.
- [ ] A run against a plan with no parseable issue outlines surfaces output
      naming what the script could not find.
- [ ] The regression check fails on a deliberately reintroduced `${NAME}`
      interpolation in a shipped koto template.
- [ ] The regression check fails on a deliberately reintroduced `declare -A` in
      a script on the single-pr path.
- [ ] `/execute --auto` completes the single-pr path end to end on a macOS host
      with no Homebrew bash, without manual workarounds.

## Out of Scope

- **Redesigning koto's template-variable model.** This PRD makes the existing
  gates resolve under the model koto ships. Changing how templates receive or
  substitute variables is separate work with a much wider blast radius, and it
  lives in the koto repository rather than this one.
- **Changing koto to surface gate stdout and stderr.** koto discards both on a
  failed command gate. That is a real diagnosability limit, and R5 is written to
  be satisfiable without changing it; a koto-side change is a separate request
  against a separate repository.
- **The multi-pr and coordinated execution paths.** Neither defect is reachable
  from them. Widening the change to paths this run did not exercise adds risk
  without evidence.
- **A repo-wide bash-version policy.** R3 makes one script run under the bash
  macOS ships and R6 guards the scripts on the single-pr path. Deciding what
  bash version the whole repository requires would need an audit of every script
  shirabe ships and is a separate decision.
- **The pre-existing data race in `tsukumogami/niwa`'s `internal/cli`**, observed
  during the same run. It is in another repository and predates this work.

## Decisions and Trade-offs

- **The interpolation sweep covers every shipped koto template, not just
  `/execute`'s.** This closes the BRIEF's open question. The sweep across all
  four templates shirabe ships found exactly one unresolvable interpolation —
  the reported gate — and every other `${...}` occurrence is in koto's
  `${evidence.<field>}` namespace, which koto resolves. Because the wider
  boundary costs one extra grep and no extra edits, there was no reason to draw
  it narrowly. The value is in R6's check, which now covers templates the fix
  did not have to touch.

- **The reported bash defect is treated as seven defects, not one.** The issue
  named line 395 because it executes first. Fixing only that line moves the
  failure to the next declaration and produces a second bug report from the same
  root cause. R3 scopes to all seven.

- **R4 (identical output across bash versions) is a requirement, not an
  assumption.** Replacing an associative array with a portable construction can
  change iteration order, and this script's output feeds task names and
  collision suffixes. Making byte-identical output an explicit requirement
  keeps a plan's task list stable regardless of which host generated it, and
  makes the property testable rather than hoped for.

- **R5 is scoped to what is reachable without changing koto.** koto renders a
  failed command gate as an exit code with an empty error string and drops the
  command's own output, so a diagnostic echoed by the gate command would go
  nowhere. The requirement therefore targets the surface koto does pass to the
  agent on a blocked gate. Accepting this constraint keeps the work inside this
  repository; the alternative was blocking on a koto change.

## Known Limitations

- Diagnosability at the gate is bounded by what koto surfaces. A developer
  watching a blocked gate will read the naming carried by the directive surface,
  not a message from the gate command itself. If koto later surfaces gate output,
  the gate command can carry its own diagnostic and the indirection can be
  removed.
- R6's bash check guards the scripts on the single-pr path. A bash 4 construct
  introduced in a script elsewhere in the repository is not caught, which is the
  cost of leaving the repo-wide policy out of scope.
