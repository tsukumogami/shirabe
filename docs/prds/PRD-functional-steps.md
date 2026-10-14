---
schema: prd/v1
status: Draft
problem: |
  Plans from /plan are cut along component lines, fully detailed up front,
  and judged by criteria that name files. Nothing a user can exercise exists
  until the last entry lands, detail written for late entries goes stale, and
  the reviewer or dispatcher can only confirm that files exist. /review-plan
  passes a layered plan as readily as one cut by behaviour.
goals: |
  /plan can write a plan of steps, in a new plan version: a walking skeleton
  first, behavioural criteria with a check for every detailed step, and later
  steps one line each until the session that owns the plan details them.
  Every tool that reads plans accepts both versions, /review-plan flags a
  layer-shaped plan, and checkpoint reports name the behaviour a step added.
upstream: docs/briefs/BRIEF-functional-steps.md
---

# PRD: functional steps

## Status

Draft

## Problem Statement

`/plan` decomposes an accepted design into work items, and in practice it
cuts them along the layers of the code: the data types, then the engine, then
the command line, then the documentation. Every entry is written in full
before the first one is built, and acceptance criteria tend to name files and
functions ("add `parse_step` to `plan.rs`") rather than behaviour someone can
observe.

Three people pay for that shape. The person executing the plan gets no
working end-to-end path until the last entry lands, so an integration mistake
surfaces only after the earlier layers have merged. The session that owns the
plan carries detail for late entries that was a guess when it was written and
is stale by the time it is used, and nothing records who rewrote it. The
reviewer, and whoever dispatched the work, can check that files exist and
tests pass, but not that a behaviour now works, because nothing in the plan
says which behaviour each entry adds. Checkpoint reports mirror the plan's
wording and come back as lists of artifacts.

`/plan` already offers a walking-skeleton decomposition, but it is one option
among several, the format still requires every entry to be detailed, and
nothing checks the result. `/review-plan` does not flag a plan cut into
layers, and the plan format's unit is the issue, which says nothing about what
each entry leaves working.

## Goals

- An author can get a plan whose entries are steps: the first step is a
  walking skeleton that works end to end, each step leaves the work running
  with criteria that describe behaviour and a check that proves it, and steps
  beyond the next one or two stay a single line.
- The plan names its entries steps, in a new plan version, and every existing
  plan keeps validating and running unchanged.
- A reviewer learns from `/review-plan` when a plan is cut into layers and
  which criteria describe files instead of behaviour.
- A checkpoint report from a worker names the behaviour its step added and
  the check that shows it.
- The default plan version does not change until a comparison of checkpoint
  wording on layered plans has reported, and the people running that
  comparison have what they need written down.

## User Stories

- As an author with an accepted design, I want `/plan` to give me a plan
  whose first step works end to end and whose later steps are one line each,
  so that I commit only to what I know and can see what will work after each
  step.
- As the session that owns a step plan, I want the plan format to say what a
  detailed step carries and when the next one-line step is detailed, so that
  I detail each step from what the previous one taught and the plan's history
  shows that I did.
- As a reviewer, I want `/review-plan` to tell me when a plan is cut into
  layers and which criteria name files, so that I know what to send back
  before anyone builds it.
- As a maintainer with plans in flight in the current format, I want
  `/execute`, the validator and koto to keep reading them as they do today,
  so that adopting step plans costs me nothing.
- As the person who dispatched a step, I want the worker's checkpoint report
  to name the behaviour the step added and the check that shows it, so that I
  can judge the step by running the check.
- As the person who decides when the default changes, I want to know which
  plans and which wording a checkpoint-wording comparison needs, so that I can
  run it before the default changes.

## Requirements

### The new plan version

- **R1.** A new plan version exists alongside the current one. A plan of the
  new version names its entries steps: its entry headings, its count field
  and its section names say "step", not "issue".
- **R2.** A step is either detailed or an outline. A detailed step carries a
  goal, acceptance criteria and a check (a command, test or walkthrough
  whose observable result shows the step's behaviour works), plus its
  dependencies. An outline step is its heading and one line saying what
  behaviour it will add.
- **R3.** The first step is the walking skeleton: it is always detailed, and
  its goal is a path through the riskiest integration that works end to end
  on the simplest input.
- **R4.** Every detailed step leaves the work running: its criteria describe
  behaviour someone can observe, not files or functions, and its check can be
  run after the step lands without any later step.
- **R5.** At authoring time, only the first one or two steps are detailed;
  every later step is an outline. The plan format states this horizon and the
  rule for moving it: the session that owns the plan details the next step
  after the previous step's work reaches its end and before the next step's
  work starts, updates the remaining outlines if they changed, and commits
  that edit to the plan. A worker building a step does not edit any step's
  outline.
- **R6.** A file list may appear on a detailed step as an optional hint for
  conflict detection. It is never an acceptance criterion and never required.
- **R7.** The new version supports the execution modes the current one does
  wherever its readers can drive them, and the plan format says, for each
  execution mode and tracking level, how the detail horizon fits; where a
  combination is not supported, the validator refuses it with a message
  naming the supported alternative.

### Writing the new version

- **R8.** `/plan` can write the new version, and its guidance produces the
  shape R2 to R5 describe: a skeleton first step, behavioural criteria, a
  check per detailed step, and outlines after the horizon.
- **R9.** How an author selects the version is explicit (an invocation flag,
  a repository convention header, or both). Until the default changes, a
  `/plan` run that selects nothing writes the current version exactly as it
  does today.
- **R10.** Changing the default to the new version is a single, separate
  edit, so it can land after the checkpoint-wording comparison reports
  without touching anything else this feature delivers.

### Reading both versions

- **R11.** `shirabe validate` accepts a valid plan of either version and
  checks the new version's rules: entries named steps, the first step
  detailed, every detailed step carrying criteria and a check, every outline
  step a single line, and the step count matching the steps present.
  Violations name the step and the rule.
- **R12.** `/execute`, and every script it uses to read a plan, drives a plan
  of either version, and treats an outline step as not yet startable until
  it is detailed.
- **R13.** Every koto reader of plans accepts a plan of either version.
- **R14.** Every other shirabe reader of plans (the lifecycle checks, task
  extraction, and any skill or script that parses plan content) accepts
  either version or states that it reads only one and refuses the other with
  a clear message.
- **R15.** No plan of the current version changes behaviour: every existing
  test of plan reading still passes unchanged.

### Review and reporting

- **R16.** `/review-plan` flags a plan as layer-shaped when its entries are
  cut by component (types, engine, CLI, docs) such that no entry before the
  last leaves anything a user could exercise, and names each acceptance
  criterion that describes files or functions rather than behaviour. It
  reviews plans of either version.
- **R17.** Guidance for a step's checkpoint report says the report names the
  behaviour the step added and the check that shows it. The guidance is
  where a worker executing a step plan reads it.
- **R18.** A written description says how to compare checkpoint reports from
  layered plans under the current checkpoint wording and under behavioural
  wording: which plans qualify, the exact wording on each side, and what to
  compare. The default checkpoint wording and the default plan version stay
  as they are until that comparison reports.

### Non-functional

- **R19.** Scripts run on bash 3.2 and need no new tool.
- **R20.** Nothing in the new version's format or guidance names a private
  repository or document.

## Acceptance Criteria

- [ ] Running `/plan` with the new version selected against a design whose
  earlier plan was cut into five layers produces a plan whose first step
  works end to end, whose criteria describe behaviour, and whose steps three
  onward are one line each, and `shirabe validate` on a clean checkout
  accepts it.
- [ ] The new version's entry headings, count field and section names use
  "step"; a plan that uses "issue" headings under the new version fails
  validation with a message naming the rule.
- [ ] A new-version plan whose first step is an outline, or whose detailed
  step lacks criteria or a check, or whose outline step spans more than one
  line, fails validation naming the step.
- [ ] `/plan` with nothing selected writes a current-version plan identical
  in shape to today's.
- [ ] `shirabe validate`, `/execute`'s plan-reading scripts and every koto
  reader of plans accept a fixture plan of each version; the existing tests
  for current-version plans pass unchanged.
- [ ] `/execute` on a new-version plan starts the first step and does not
  start an outline step until it is detailed.
- [ ] `/review-plan` on the five-layer plan flags it as layer-shaped and
  lists the criteria that name files or functions; on the step plan above it
  raises no layer-shape finding.
- [ ] The step-plan guidance tells a worker to report the behaviour its step
  added and the check that shows it.
- [ ] A written description of the checkpoint-wording comparison names the
  qualifying plans, the wording on each side and what to compare, and the
  default plan version and default checkpoint wording are unchanged.
- [ ] Every new or changed script passes its suite under bash 3.2.

## Out of Scope

- Building the step-by-step execution shape into `/deliver` and `/execute`:
  who hands each step to its own agent, and making the owning session's
  detailing a workflow state. The format and `/plan`'s guidance describe the
  rule; the delivery skills adopt it separately.
- The roadmap format and renaming roadmap entries.
- Converting existing plans to the new version.
- Running the checkpoint-wording comparison.
- Changing the default plan version or the default checkpoint wording (R10
  and R18 make that a later, separate change).
- Measured guidance on how large a step should be.
- Any change to niwa.

## Decisions and Trade-offs

- **A new version, not a change to the current one.** Renaming entries in
  place would break every plan in flight and every reader at once. A second
  version accepted alongside the first lets readers adopt it one at a time
  and leaves existing plans untouched. Alternative rejected: extending the
  current version with optional step fields, which would leave "issue" as the
  name of the unit and let a plan mix both shapes.
- **The file list survives as an optional hint.** It already serves conflict
  detection between parallel work items; dropping it would cost that, and
  keeping it out of the criteria keeps criteria behavioural. (Resolves the
  brief's question on file lists.)
- **The detail horizon fits issue-per-step repositories by the plan format's
  own rule (R7), settled in the design.** The design chooses between filing
  an issue only when a step is detailed and limiting the new version to
  outline-shaped plans; either way the validator says which. (Resolves the
  brief's question on issue-per-step repositories by assigning it.)
- **The default waits.** The new version ships selectable, and the default
  flip is a one-line follow-up (R9, R10), because the question of whether
  artifact-shaped reports come from layered plans or from checkpoint wording
  has to be answered before the default changes. (Resolves the brief's
  question on when the default changes.)
