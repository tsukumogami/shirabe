---
schema: prd/v1
status: Done
problem: |
  `/execute` drives every step of a plan through a `/work-on` child in its own
  context, so a session running a multi-step plan, often after a scoping
  conversation that used about half its window in the same session, ends near
  its context limit or compacts. The thin shape (one step agent per step, the
  owning session detailing each next step between them) happens only when a
  dispatcher writes it into the prompt, and the skills' team declarations,
  nesting rule and review-level rules all point away from it.
goals: |
  A `/deliver` or `/execute` run takes the lead shape on its own: each step's
  child goes to its own step agent, which may spawn that step's review seats,
  and the owning session details every step after the first between children
  and records it. The skills state the shape, carry no team declaration that
  nothing reads, and choose a step's review level from the step's own commits.
absorbed:
  - docs/briefs/BRIEF-lead-shape-delivery.md
---

## Status

Done

Absorbed [BRIEF-lead-shape-delivery](docs/briefs/BRIEF-lead-shape-delivery.md); carried in Absorbed Brief.

## Absorbed Brief

The brief framed why this feature exists. Runs that handed each step of a
plan to its own agent, with the session that owns the plan detailing the next
step between them, stayed thin, where runs that drove every step inline came
close to the context limit and compacted; but the shape reached a run only
when its dispatcher wrote it into the prompt, so the skills carried none of
it. That gap, and the three parts of the skills that point away from the
shape (team declarations nothing reads, a rule that a subagent never spawns
subagents, and review levels that end every shared-branch step at `full`),
are this document's Problem Statement.

The outcome it asked for is that whoever hands a plan to `/deliver` gets a
stepped run without writing any execution instructions, with each step run
and reviewed by its own agent, each later step detailed by the owning session
from what landed, and a step's review level following the step's own size;
and that a contributor can take every team or agent a skill describes as one
a run actually starts. Those are this document's Goals. Its journeys (a
coordinator dispatching a plain brief, a maintainer resuming a half-done plan
after long scoping, a reviewer reading a step's review record, and a
contributor asking why a small step ran the full review) are this document's
User Stories. Its scope boundary, in and out, is carried by the Requirements
and Out of Scope.

## Problem Statement

`/deliver` runs `/scope` and then `/execute` in one session, and `/execute`
ticks every plan-backed `/work-on` child itself, in that session's context.
Each child reads its step, plans, implements, runs its review panels and
records its result, and all of that stays in the session that owns the plan.
Measured inline runs of three to six steps peaked at 78 to 97 percent of a
one-million-token window, and two of them compacted, losing what earlier steps
decided. Even runs that delegated their steps spent about half the window in
scoping before step one.

Runs that handed each step's child to its own agent, with the owning session
detailing the next step between children, kept the owning session thin. But
the skills say none of it. `/execute`'s spawn directive says the session
"stays thin by delegating each issue to a fresh `work-on.md` child", which is
a koto child session, not a separate agent, and nothing stops two ready
children being driven at once. A session gets the thin shape only when its
dispatcher writes a paragraph of execution instructions into the prompt, and a
person running `/execute` by hand never gets it.

Three parts of the skills stand in the way of making the shape the default:

- Seven skills (`brief`, `prd`, `design`, `plan`, `vision`, `strategy`,
  `roadmap`) carry a `team.yaml` declaring peers a parent would build. No
  script, test, validator check or eval reads them, and the pattern reference
  still presents them as a dispatch contract.
- The pattern reference's `team_primitive` value,
  `single-team-per-leader-no-nested`, says no sub-agent spawns sub-agents. A
  step agent driving a `/work-on` child has to spawn that step's review seats.
- `review-level.sh facts` takes the larger of two diffs: from the child's
  `impl_base`, and from the merge-base with the default branch. On a shared
  branch the merge-base diff carries every earlier step's commits, so a late
  step's facts cross the 400-line and 12-file thresholds, or pick up an
  earlier step's template change, and the step floors at `full` whatever its
  own size. `record-changed-paths.sh` already keeps sibling commits out on a
  shared branch; the level rules don't, and no text says what a step should
  count.

## Goals

- A person or coordinator who hands a plan to `/deliver` or `/execute` gets
  the lead shape without writing anything about execution: one step agent per
  step, steps one at a time, every step after the first detailed by the owning
  session after the previous child's terminal and before the next step agent
  starts.
- The owning session's growth per step is bounded: it ticks no child's loop,
  keeps at most ten lines per step from its step agent, and under `--auto`
  keeps none of the scoping conversation.
- A contributor reading the delivery skills finds the shape, the nesting rule
  and the review-level rule for a step stated there, and no file describing a
  team that nothing builds.
- A step's review level follows the step's own commits.

## User Stories

- As a coordinator dispatching a `/deliver` worker for a five-step plan, I
  want to leave execution shape out of the brief, so that the brief carries
  only the outcome and the decisions, and the run still delegates every step
  and records a refined outline for steps two to five.
- As a person running `/execute` by hand on a plan I wrote earlier, I want the
  same shape `/deliver` would give, so that I read one short report per step
  instead of every child's transcript.
- As a maintainer who scoped a large feature under `--auto` and re-invokes
  `/deliver` after the run stopped at step two, I want the run to carry steps
  three to six from the PLAN and the koto records, so that nothing of the
  earlier scoping conversation has to be in the session that finishes it.
- As a maintainer running a coordinated plan across two repositories, I want
  each work item to run in its own agent in its node's worktree, so that the
  coordinating session keeps only the run record and the coordination PR.
- As a reviewer reading one step's record in a finished pull request, I want
  to see the panels that step's own agent ran, at the level R10 gives for that
  step's own commits, so that I can trust each step was reviewed as itself.
- As a contributor who sees a two-file prompt change on step four go through
  the full review, I want the review-level rules to say which commits count
  toward a step's facts and why, so that I can tell whether the level was
  right without reading the scripts.

## Requirements

Terms used below. The **owning session** is the session holding
`execute-<topic>` (and, under `/deliver`, `deliver-<topic>`). A **step agent**
is a subagent the owning session starts to drive one `/work-on` child. A
**seat** is a reviewer subagent a `/work-on` panel spawns. A child is **on a
shared branch** when its `SHARED_BRANCH` variable is not empty. The **bound**
is the `REVIEW_FLOOR` and `REVIEW_CEILING` variables that `--review-floor` and
`--review-ceiling` set. The **leg** is the koto request leg a child reports
its terminal result on (`--koto-leg`). To **rewind** a child is `koto rewind
<child>`, which returns it to its previous state.

### Functional

**R1. Step agents.** On a `single-pr` PLAN, `/execute` hands each child's
whole `/work-on` loop to one step agent, started in the foreground in the same
checkout, which drives that child from where it stands to its terminal, panels
included, on the shared branch. The owning session never runs `koto next` on a
child. A step agent returns a report of at most ten newline-delimited lines,
and the owning session keeps no more than the first ten.

**R2. One step at a time.** The owning session hands off steps one at a time,
in the PLAN's order, including detailed steps that `waits_on` would let start
together. It starts the next step's agent only after `koto status` on the
previous child shows a terminal state, never on the strength of the agent's
report. When the previous child is at `done`, the next step proceeds as R3
says. When it is at any other terminal, the owning session goes on with the
next step koto hasn't skipped (`skip_dependents` skips that child's
dependents, as today), so the batch reaches its terminal and
`spawn_and_await` routes it to `escalate` as it does today. A child at
`validation_exit` because its step is still an outline is handled as R7 says,
not as a failure. When a step agent returns and `koto status` shows its child
not yet terminal, the owning session hands the child to one new step agent,
which resumes it from its current state; when that agent also returns with
the child not terminal, the owning session stops handing off and ends the
invocation with the forced-stop summary, leaving the run resumable.

**R3. The owning session details each next step.** Before handing off any step
after the first, and after the previous child reached its terminal (whichever
terminal it was), the owning session details that step: it rewrites the step's entry in the PLAN (its
`### Step N:` block on a `plan/v2` plan, its outline on a `plan/v1` plan, and
also the GitHub issue body when the step is an issue) so that the entry's
goal, criteria and check are consistent with the code the landed steps left.
It also rewrites a later step's one-line entry when that entry names a file,
command, interface or assumption a landed step changed. It commits the PLAN
edit on the shared branch, then runs `koto context add execute-<topic>
step_refine/<step>.md --from-file <file>` with the step's full entry text as
committed, where `<step>` is the part of the child's session name after
`.o-`, or the child's whole session name when it has no `.o-` (a `plan/v2`
child is `execute-<topic>.step-<N>`). It records the key even when the entry
didn't change. The first step is not detailed by the owning session; when it
is an outline, its child stops at `validation_exit` and R7's outline case
applies. No step agent edits any step's entry.

**R4. A fixed hand-off.** The text a step agent receives is one template in one
file, with named substitutions for the child session, the checkout, the
shared branch and the plugin root, and nothing else composed per run. It says
to drive the child under `/work-on`'s plan-backed child mode with
`--no-cleanup` on every tick, that the agent may spawn its step's review seats
and that those seats spawn nothing, that it must not edit any step's entry in
the PLAN, and that it must not read settings or credential files. It fixes the
report's first two lines as `child=<session> state=<terminal state>` and
`seats=spawned` or `seats=unavailable`. When a report carries
`seats=unavailable`, the owning session stops handing off and ends the
invocation with the forced-stop summary, leaving the run resumable.

**R5. The coordinated path.** On a `coordinated` PLAN, each work item the
`dispatch:<node>` action dispatches goes to its own step agent, one at a time
in the node's `ISSUES` order, in that node's worktree, with the R4 hand-off.
The owning session keeps every step that reads or writes the run record, the
coordination PR or a node branch's remote: `repo-visibility.sh`, `node-cut.sh`,
`node-push.sh` and the exit handling around them. It confirms each work item's
child with `koto status` before the next, and details every work item after
the run's first as R3 says, committing the PLAN edit on the coordination branch
in the coordination checkout, where `plan_abs` points.

**R6. Scoping in its own agent under `--auto`.** An `--auto` `/deliver` hands
the `/scope` Skill call, with exactly the arguments `scope_run` builds, to one
scope agent started in the foreground in the same checkout, which runs
`/scope` to its terminal and returns at most ten lines. The owning session
uses none of those lines: it ticks `deliver-<topic>`, which reads `/scope`'s
result from the leg, and reads the PLAN and the scoping documents from disk.
A scope agent that returns while the leg is still open takes the existing
`child_returned: yes` path to `deliver:child-absent`. An interactive
`/deliver` calls `/scope` in the owning session, because `/scope` asks the
author questions there.

**R7. Recovering after a compaction.** `/execute` states that after any
compaction the owning session runs `koto status` on every koto session of the
run (`execute-<topic>`, each child, and, under `/deliver`, `deliver-<topic>`)
before its next action, and goes on from the state each reports. Because step
agents run in the foreground, no step agent is running once the owning session
is acting again; a child that is not terminal is handed to a new step agent,
which resumes it from its current state. A child at `validation_exit` because
its step was an outline is detailed as R3 says, rewound, and handed to a step
agent.

**R8. The nesting rule.** `references/parent-skill-pattern.md`'s
`team_primitive` value says that an agent driving one unit of a run (a step
agent, or the scope agent) may spawn that unit's own reviewers, jurors and
research agents, and that those spawn nothing. These passages are rewritten to
match: the `team_primitive` consequences in the same file; the serial-self-jury
premise in `references/fixes/sub-agent-dispatch.md`; the matching passage in
`skills/design/references/phases/phase-6-final-review.md`; and the
team-lead rows in `references/worktree-discipline.md`. The serial-self-jury
fallback stays, for a harness that can't spawn at all.

**R9. No team declarations.** The seven `team.yaml` files are removed. Each
skill's `## Team Shape` section (the seven, plus `charter` and `scope`) says
in prose what that skill spawns and at which phase, with no pointer to a
declaration file. The pattern reference's Team-Shape Declarator section, its
Child Team-Shape Declaration element and the `skills/<name>/team.yaml`
glob-marker item are removed. The two current designs that present the
declaration as a live contract (`DESIGN-shirabe-child-dispatch-contract.md`,
for `team.yaml`, and `DESIGN-shirabe-progression-authoring.md`, for its
team-shape declarator component) each carry a dated note that the declaration
was retired and that `DESIGN-lead-shape-delivery.md` records why. A design
that only cites the old choice as precedent is left as it is.

**R10. A step's review level.** On a shared branch, `review-level.sh facts`
counts only the step's own commits: the diff from its `impl_base`, never the
merge-base with the default branch. On a shared branch with no `impl_base`,
`facts` exits 64 naming `impl_base`, with no merge-base fallback. Off a shared
branch the rule is unchanged, and the thresholds (more than 40 lines for
`standard`, more than 400 lines or 12 files for `full`) are unchanged.
`skills/work-on/references/review-levels.md` states how a step's level is
chosen under the lead shape: the step's own `/work-on` chooses it inside the
bound, and the step's own facts floor it. It states that a step whose own
commits touch the `ci`, `security`, `template` or `engine` class floors at
`full` because those paths change what every later run does, and that a step
whose own commits touch no path in those four classes and stay within 400
lines and 12 files floors no higher than `standard`.

**R11. The shape is stated where it runs.** `skills/deliver/SKILL.md`,
`skills/execute/SKILL.md` and `skills/work-on/SKILL.md` each contain the
phrase "lead shape". `/execute`'s SKILL.md and its `spawn_and_await`
directive state that the owning session details the next step "after the
previous step's child reaches its terminal and before the next step's agent
starts". `/work-on`'s SKILL.md states that a step agent drives a plan-backed
child and "may spawn its step's review seats".

### Non-functional

**R12. No new runtime.** The shape uses the agent tool the harness provides
and koto as installed today; the change is in this repository only.

**R13. Shell compatibility.** Any script added or changed runs under
`/bin/bash` 3.2.

**R14. Other runs are unaffected.** A `multi-pr` PLAN, a direct `/work-on` on
one issue, and the `/scope` and `/charter` chains run as they do today, apart
from the `## Team Shape` prose. A direct `/work-on` run's facts are computed
as before.

## Acceptance Criteria

A "text test" below is a shell test that checks each quoted phrase is present
as a fixed, case-sensitive substring (`grep -F`) of the named file or
section, and fails naming the phrase that is missing.

- [ ] A text test under `skills/execute/scripts/` asserts that
      `skills/execute/SKILL.md` and the `## spawn_and_await` section of
      `execute.md` each contain "step agent", "one at a time", "koto status",
      "never runs `koto next` on a child", and "after the previous step's
      child reaches its terminal and before the next step's agent starts".
- [ ] The same test asserts that the `spawn_and_await` section contains
      `step_refine/`, "after `.o-`", "whole session name", "even when the
      entry didn't change", the `skip_dependents` sentence of R2, and "No step
      agent edits".
- [ ] The step-agent hand-off template is
      `skills/execute/references/step-agent-handoff.md`, whose first line is
      `# Step agent hand-off`; `git grep -l '^# Step agent hand-off' --
      skills` lists only that file, and the template contains
      `--no-cleanup`, "may spawn its step's review seats",
      `child=<session> state=`, `seats=spawned`, `seats=unavailable`, and a
      ban on reading settings or credential files.
- [ ] The text test asserts that `execute.md` says a report with
      `seats=unavailable` stops the hand-offs with the forced-stop summary,
      that a child left non-terminal by a returned step agent gets one new
      step agent and then the forced-stop summary, and that the owning
      session keeps no more than the first ten lines of a report; and that
      the hand-off template contains "at most ten lines".
- [ ] The text test asserts that `execute-coordinated.md`'s `dispatch:<node>`
      action names the hand-off template, "one at a time", the node's
      worktree, `koto status`, `step_refine/` and `plan_abs`, and that
      `node-push.sh` is still run by the owning session.
- [ ] A text test under `skills/deliver/scripts/` asserts that
      `deliver.md`'s `scope_run` directive tells an `auto` run to hand the
      `/scope` call to one scope agent and an `interactive` run to call it
      directly, and keeps the `child_returned: yes` path.
- [ ] The text test asserts that `skills/execute/SKILL.md` carries R7's rule:
      `koto status` on every session of the run after a compaction, a
      non-terminal child handed to a new step agent, and an outline child at
      `validation_exit` detailed, rewound with `koto rewind` and handed off.
- [ ] `git ls-files 'skills/*/team.yaml'` prints nothing; `git grep -n
      'team.yaml' -- skills references` prints nothing; and `git grep -l
      'team.yaml' -- docs/designs/current` lists only
      `DESIGN-shirabe-child-dispatch-contract.md`,
      `DESIGN-skill-preflight-checks.md` (a precedent citation) and
      `DESIGN-lead-shape-delivery.md`; the two designs R9 names each contain
      a dated retirement note naming `DESIGN-lead-shape-delivery.md`.
- [ ] `git grep -n '## Team Shape' -- skills` still lists the nine skills,
      and none of those sections contains `team.yaml`.
- [ ] `git grep -n -e 'Team-Shape Declarator' -e 'Child Team-Shape
      Declaration' -e 'single-team-per-leader-no-nested' -- references skills`
      prints nothing, and `references/parent-skill-pattern.md` contains "may
      spawn" and "spawn nothing".
- [ ] `references/fixes/sub-agent-dispatch.md` and
      `skills/design/references/phases/phase-6-final-review.md` still
      describe the serial-self-jury fallback, and each states it applies when
      the harness can't spawn subagents, not because a subagent may not
      spawn; and `git grep -n 'team-lead-spawned' --
      references/worktree-discipline.md` prints nothing.
- [ ] `review-level_test.sh` has a case where, on a shared branch, an earlier
      sibling committed a `koto-templates/` file and 500 lines, and the step's
      own `impl_base` diff is a 20-line `SKILL.md` change: `facts` records
      `base_source: impl_base` and floor `standard`.
- [ ] `review-level_test.sh` has a case off a shared branch with the same
      commits and an `impl_base` recorded after them: `facts` records
      `base_source: merge_base` and floor `full`, as today.
- [ ] `review-level_test.sh` has a case on a shared branch with no
      `impl_base`: `facts` exits 64 and names `impl_base`.
- [ ] `review-level_test.sh`'s existing base-choice cases pass unchanged.
- [ ] `skills/work-on/references/review-levels.md` has a section on a step's
      level under the lead shape that names `impl_base` as the only base on a
      shared branch and lists `ci`, `security`, `template` and `engine` as the
      classes that floor a step at `full`.
- [ ] `skills/deliver/SKILL.md`, `skills/execute/SKILL.md` and
      `skills/work-on/SKILL.md` each contain "lead shape", and
      `skills/work-on/SKILL.md` contains "may spawn its step's review seats".
- [ ] `skills/execute/evals/evals.json` has a scenario for a three-step plan
      whose expectations name a step agent per step and a `step_refine/` key
      for steps two and three, and `skills/deliver/evals/evals.json` has an
      `--auto` scenario whose expectations name a scope agent.
- [ ] The CI workflows "Check execute scripts", "Check work-on scripts",
      "Check deliver scripts", "Check plan scripts", "Check skill gate",
      "Check skill evals exist" and "Check bash floor" all pass on the pull
      request's head.
- [ ] `git diff --name-only` against the default branch lists no file under
      `skills/scope/koto-templates/`, `skills/charter/koto-templates/` or
      `skills/coordinate/`.

## Out of Scope

- The plan format and `/plan`'s guidance on step sizing and outlines. The
  shape uses step plans and issue plans as they are.
- Running steps in parallel. Each step's entry is detailed from what the step
  before it landed, which two steps running at once can't do.
- Any change to koto or niwa (R12).
- `/coordinate`'s dispatch and record scripts. A coordinator stops carrying an
  execution-shape item in its briefs, but how it dispatches a worker is
  unchanged, and nothing under `skills/coordinate/` changes.
- How `/scope` and `/charter` dispatch their own children, which run inline in
  the parent's context and aren't steps of a plan.
- The review panels' seats, rubrics and verdict shapes.
- A structural refining state in `/execute` that a template gate enforces. The
  detailing is the owning session's act, stated in the directive; a gate is
  later work if runs show the directive isn't followed.
- Running the shape on a real milestone and reading its record. The text tests
  and eval scenarios check what the skills say; whether a run follows it is
  read from a run's koto records after the change ships.

## Known Limitations

- The detailing is prose the owning session follows, not a koto gate. A
  session that skips it still produces a run; the `step_refine/` keys and the
  PLAN commits are what show whether it happened.
- Steps no longer run in parallel, so a plan with independent steps takes
  longer than an inline run that drove two at once.
- An interactive `/deliver` still runs `/scope` in the owning session, so a
  long interactive scoping conversation still costs the owning session its
  share of the window; R7's recovery rule is what carries it through a
  compaction.
- A step agent's own context is fresh, so it reads its step, the design and
  earlier steps' summaries itself; the run as a whole doesn't spend less, it
  spends it where it doesn't accumulate.
- On a shared branch, a child whose `impl_base` was recorded after some of its
  own commits floors lower than it should. `impl_base` is recorded at
  `analysis`, before implementation, so this needs a commit made before
  analysis; the pull request's own review before it is ready is the backstop.

## Decisions and Trade-offs

- **The coordinated path is in scope.** It dispatches `/work-on` children the
  same way, and leaving it inline would keep the problem for every
  multi-repository plan. Its run record and coordination PR stay with the
  owning session, so only the child loop moves.
- **Scoping goes to its own agent only under `--auto`.** Alternatives were to
  always delegate `/scope` (a subagent can't put questions to the author, so
  interactive scoping would break), or to rotate to a fresh session after
  scoping (that needs a dispatcher or niwa change, which is out of scope).
  Delegating under `--auto` saves the window exactly where nobody is there to
  restart a session by hand.
- **A failed step doesn't stop the batch.** The alternative was to stop all
  hand-offs at the first failed child. That would leave the remaining children
  unstarted and non-terminal, so the batch gate would never route; carrying on
  with the steps koto hasn't skipped keeps today's routing to `escalate`.
- **The refine key follows the existing reading convention.** A `plan/v1`
  child's session ends in `.o-<slug>` and a `plan/v2` child's in `.step-<N>`,
  so the key is the part after `.o-`, or the whole session name when there is
  none, which is what a reader of the execute session already matches. A key
  is recorded even for an unchanged step, so the record shows the step was
  looked at.
- **A step counts only its own commits.** The alternative was to keep the
  larger-diff rule and state why every step is `full`. That would keep levels
  that don't follow steps, and `record-changed-paths.sh` already treats sibling
  commits on a shared branch as not this run's.
- **The checks are text tests and eval scenarios.** The skills' behaviour is
  agent behaviour driven by directives, so the pull request checks the
  directives say exactly what the requirements need, and adds eval scenarios
  the release runs; a scripted end-to-end run of agents is not something CI
  can do.
