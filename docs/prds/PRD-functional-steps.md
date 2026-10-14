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
  steps one line each until the plan's owner details them. Every tool that
  reads plans accepts both versions, /review-plan flags a layer-shaped plan,
  and step reports name the behaviour a step added.
upstream: docs/briefs/BRIEF-functional-steps.md
---

# PRD: functional steps

## Status

Draft

## Problem Statement

`/plan` decomposes an accepted design into work items, and the plans it
produces are mostly cut along the layers of the code. koto's template
evidence-routing plan is a typical example: five entries, in order "add
evidence routing types", "update compiler", "adapt CLI", "update tests",
"update plugin templates", with criteria such as "Add `Transition` struct
with `target: String`". Nothing in it could be run end to end until the
fourth entry landed.

That shape costs three roles. The person executing the plan gets no working
path until the last entries land, so an integration mistake surfaces after
the earlier layers have merged. The plan's owner carries detail for late
entries that was a guess when it was written, and nothing records who
rewrote it once it went stale. The reviewer, and whoever dispatched the work,
can confirm that files exist and tests pass but not that a behaviour works,
because nothing says which behaviour each entry adds; reports at checkpoints
mirror that and come back as lists of artifacts.

`/plan` already offers a walking-skeleton decomposition, but it is one option
among several, the format still requires every entry to be written in full,
and nothing checks the result. `/review-plan` does not flag a plan cut into
layers, and the format's unit is the issue, which says nothing about what an
entry leaves working.

## Goals

- An author can get a plan whose entries are steps: the first is a walking
  skeleton, each detailed step carries behavioural criteria and a check, and
  steps beyond the first two are one line until detailed.
- The plan names its entries steps, in a new plan version, and every plan of
  the current version keeps validating and running unchanged.
- `/review-plan` tells a reviewer when a plan is cut into layers and which
  criteria name files or functions.
- A worker's report on a step names the behaviour the step added and the
  check that shows it.
- The default plan version and the default checkpoint wording stay as they
  are, and the design records how to compare checkpoint wording on layered
  plans so that the comparison can run before either default changes.

## Definitions

- **Plan version.** The `schema:` value. The current version is `plan/v1`;
  the new one is `plan/v2`.
- **Step.** An entry of a `plan/v2` plan, headed `### Step <N>: <title>`
  under a `## Steps` section.
- **Detailed step.** A step whose body carries the fields R2 lists.
- **Outline step.** A step whose body is exactly one non-blank physical line
  (of any length) and nothing else.
- **Detail horizon.** The detailed steps whose work has not started. At
  authoring, the first two steps (or every step, when there are two or
  fewer).
- **Terminal.** The step's `/work-on` workflow reached a terminal state
  (done, or stopped with a recorded outcome).
- **File-shaped criterion.** An acceptance criterion whose subject is a file
  path or a code identifier (a backticked name, or a path containing `/` or a
  file extension) paired with a construction verb (add, create, implement,
  define, update, remove, rename) and no observable result (an output, exit
  code, message or state a person can see by running something).
- **Layer-shaped plan.** A plan with three or more entries in which every
  entry before the last has no criterion or check that a person can run to
  observe a behaviour, and the entries are named or grouped by component
  (types, model, schema, compiler, engine, core, CLI, command, tests, docs).

## User Stories

- As an author with an accepted design, I want `/plan` to give me a plan
  whose first step works end to end and whose later steps are one line each,
  so that I commit only to what I know.
- As a plan's owner, I want the format to say what a detailed step carries
  and exactly when I detail the next one, so that each step is written from
  what the previous one taught and the plan's history shows I did it.
- As a worker building a step, I want my step's detail to be complete before
  I start and my report format to be stated, so that I never build from a
  one-line outline.
- As a reviewer, I want `/review-plan` to tell me when a plan is cut into
  layers and which criteria name files, so that I can send it back before
  anyone builds it.
- As a maintainer with `plan/v1` plans in flight, I want every tool to read
  them as it does today, so that adopting steps costs me nothing.
- As the person who dispatched a step, I want the worker's report to name
  the behaviour added and the check that shows it, so that I can judge the
  step by running the check.
- As the person who decides when the defaults change, I want the qualifying
  plans, the exact wording on both sides and the comparison written down,
  so that I can run the comparison first.

## Requirements

### The new plan version

- **R1.** `plan/v2` is a new plan version accepted alongside `plan/v1`. Its
  frontmatter carries `schema: plan/v2`, `status`, `execution_mode`,
  `milestone` and `step_count` (not `issue_count`); its required sections
  are `Status`, `Scope Summary`, `Decomposition Strategy` and `Steps`, in
  that order; every `###` heading under `## Steps` is `### Step <N>:
  <title>`, numbered from 1 with no gap.
- **R2.** A detailed step carries `**Goal**:`, `**Acceptance Criteria**:`
  with at least one checkbox item, `**Check**:` (a non-empty command, test
  or walkthrough whose result shows the step's behaviour), and
  `**Dependencies**:` (`None`, or `Step <N>` references separated by
  commas). An outline step is its heading and one line naming the behaviour
  it will add.
- **R3.** Step 1 is the walking skeleton and is always detailed. Its goal
  names the integration it crosses and the input it runs on, and its check
  runs it end to end.
- **R4.** Detailed steps form a prefix: no detailed step follows an outline
  step. A step depends only on earlier steps.
- **R5.** The plan format states the horizon and the rule that moves it: the
  plan's owner details step N+1 after step N's work reaches its terminal and
  before step N+1's work starts, rewrites any outline whose behaviour
  changed, and commits that edit to the plan file on its own (one commit per
  detailing, touching only the plan). A worker never edits any step's
  heading, outline or detail. This rule is guidance, checked by review and by
  the plan's history, not by the validator.
- **R6.** A detailed step may carry `**Files**:` as a hint for conflict
  detection. It is never required and never counts as a criterion.
- **R7.** `plan/v2` supports `execution_mode: single-pr` and `multi-pr` at
  `tracking_level: none` (or the field absent). The validator refuses
  `plan/v2` with `execution_mode: coordinated` or with `tracking_level:
  issues` or `issues-and-milestone`, with a message naming `plan/v1` as the
  version for those cases.

### Writing the new version

- **R8.** `/plan` writes `plan/v2` when it is selected, and its guidance
  produces the shape in R1 to R5: a skeleton first step, the second step
  detailed, criteria that are not file-shaped, a check per detailed step,
  and outline steps from step 3 on.
- **R9.** The version is selected by `--plan-version=v1|v2` on `/plan`, else
  by a `## Plan Version: v1|v2` header in the repository's CLAUDE.md, else by
  the default. The flag wins over the header. Any other value is refused
  before anything is written, naming the accepted values.
- **R10.** The default is defined in exactly one place, a named setting in
  one script, and is `v1`. Changing it to `v2` is a one-line edit to that
  setting and needs no other change for the suites to pass.

### Reading both versions

- **R11.** `shirabe validate` accepts a valid plan of either version and
  checks R1, R2, R3, R4 and R7 for `plan/v2`. Each violation names the step
  number (where there is one) and the rule broken.
- **R12.** `/execute` drives a `plan/v2` plan in either supported mode. A
  step's `/work-on` workflow that finds its step is still an outline when it
  starts stops before implementing anything, with a message naming the step
  and saying the plan's owner must detail it first; once the plan is
  detailed and committed, rerunning that step builds from the detailed text.
- **R13.** koto's handling of plans accepts both versions. koto passes plan
  paths through decider and template variables without parsing plan content;
  the design records each place it does so, and any that parses content
  accepts both versions.
- **R14.** Every shirabe reader of plan content accepts `plan/v2`. The
  design names each reader (the validator, `shirabe plan outlines`, task
  extraction, the lifecycle checks, the `/scope`, `/execute` and `/work-on`
  scripts that read plan bodies or the schema), and each one either reads
  both versions or refuses `plan/v2` with a message naming the reader and
  the unsupported version, never silently returning nothing.
- **R15.** No `plan/v1` plan changes behaviour: every existing test of plan
  reading passes unchanged, and `shirabe validate` gives identical output on
  the existing plan fixtures.

### Review and reporting

- **R16.** `/review-plan` reviews plans of either version and, applying the
  definitions above, reports a layer-shaped plan as a finding naming the
  entries and the components they are cut by, and lists each file-shaped
  criterion by entry and text. A plan with no such criteria and a walking
  skeleton first gets neither finding. At authoring it also flags a
  `plan/v2` plan with more than two detailed steps.
- **R17.** The plan format's `plan/v2` section and `/work-on`'s instructions
  for a plan-step task say that a step's report names "the behaviour this
  step added" and the check that shows it, with the check's result.
- **R18.** The design document has a section describing the
  checkpoint-wording comparison: which plans qualify, the exact checkpoint
  wording on each side, what is compared in the reports, and the record it
  produces. The default plan version (R10) and the default checkpoint
  wording in shirabe's brief template are unchanged by this feature.

### Non-functional

- **R19.** New and changed shell scripts run under bash 3.2 and pass the
  repository's bash-floor check; no new runtime dependency is added beyond
  the tools the repository's scripts already use.
- **R20.** No file this feature adds or changes names a private repository,
  a private issue, or a private document.

## Acceptance Criteria

- [ ] A committed fixture copies koto's five-layer evidence-routing plan as
  `plan/v1`, with its source named in the fixture's header comment.
- [ ] Running `/plan --plan-version=v2` on koto's evidence-routing design
  yields a plan that `shirabe validate` accepts on a clean checkout, whose
  step 1 is detailed with a check that runs end to end, whose step 2 is
  detailed, whose steps from 3 on are outline steps, and in which
  `/review-plan` finds no file-shaped criterion.
- [ ] A `plan/v2` fixture with all R1 and R2 fields validates clean, with and
  without `**Files**:` on its detailed steps.
- [ ] `shirabe validate` reports an error naming the step and rule for each
  of these `plan/v2` fixtures: a `### Issue 1:` heading; `step_count` not
  matching the steps; step 1 an outline; a detailed step missing
  `**Check**:`; a detailed step with no checkbox criterion; an outline step
  of two lines; a detailed step after an outline step; a step depending on a
  later or missing step; `execution_mode: coordinated`; `tracking_level:
  issues`.
- [ ] `shirabe validate` output on every existing `plan/v1` fixture is
  unchanged, and every existing suite that reads plans passes unchanged.
- [ ] `/plan` with no flag and no header writes `schema: plan/v1`; with
  `## Plan Version: v2` it writes `plan/v2`; with the header set to `v2` and
  `--plan-version=v1` it writes `plan/v1`; `--plan-version=v3` is refused
  before any file is written.
- [ ] The default version is one named setting; a test that sets it to `v2`
  shows the selection resolving to `v2` with nothing else changed.
- [ ] Task extraction and `shirabe plan outlines` produce one task per step
  for a `plan/v2` fixture in each supported mode, each named for its step and
  carrying whether it is detailed; each other reader the design names has a
  test feeding it a `plan/v2` fixture, and none returns empty output
  silently.
- [ ] A `/work-on` plan-step task whose step is an outline stops before
  implementation with a message naming the step and the rule.
- [ ] The design lists every place koto handles a plan path or plan content,
  and each is shown to accept a `plan/v2` path.
- [ ] `/review-plan` on the five-layer fixture reports it as layer-shaped,
  names its components, and lists its file-shaped criteria (for example
  "Add `Transition` struct with `target: String`"); on a `plan/v2` fixture
  with behavioural criteria it reports neither finding; on a `plan/v2`
  fixture with three detailed steps at authoring it flags the horizon.
- [ ] `git grep -n "the behaviour this step added"` finds the phrase in the
  plan format reference and in `/work-on`'s plan-step instructions.
- [ ] The design has a section naming the qualifying plans, both checkpoint
  wordings verbatim, what is compared, and the record produced; the brief
  template's checkpoint wording is unchanged in this feature's diff.
- [ ] New and changed scripts pass their suites under `/bin/bash` 3.2 and
  the bash-floor check.
- [ ] A search of the feature's diff for private repository names, private
  issue references and private document paths returns nothing.

## Out of Scope

- Building the step-by-step execution shape into `/deliver` and `/execute`:
  handing each step to its own agent, and making the owner's detailing a
  workflow state. The format and `/plan`'s guidance state the rule.
- Enforcing R5 mechanically (detecting a worker that edited an outline).
- `plan/v2` for coordinated plans and for plans that file an issue per step.
- The roadmap format and renaming roadmap entries.
- Converting existing plans to `plan/v2`.
- Running the checkpoint-wording comparison, and changing either default.
- Measured guidance on how large a step should be.
- Any change to niwa.

## Decisions and Trade-offs

- **A new version, not a change to the current one.** Renaming entries in
  place would break every plan in flight and every reader at once. A second
  version lets readers adopt it one at a time and leaves existing plans
  untouched. Rejected: optional step fields on `plan/v1`, which would keep
  "issue" as the unit and let a plan mix both shapes.
- **The file list stays as an optional hint (R6).** It already serves
  conflict detection; keeping it out of the criteria keeps criteria
  behavioural. This settles the brief's question about file lists.
- **`plan/v2` is outline-only (R7).** A plan that files an issue per entry
  writes every issue body at filing time, which defeats the detail horizon.
  Repositories that need an issue per entry keep `plan/v1` until filing on
  detailing exists. Coordinated plans also stay on `plan/v1`, since their
  per-entry repository and group fields add a second shape to settle. This
  settles the brief's question about issue-per-step repositories.
- **The horizon is guidance plus review, not a validator rule.** The
  validator cannot tell which steps have landed, so it checks the prefix
  rule (R4) and `/review-plan` checks the horizon at authoring (R16).
- **The defaults wait (R10, R18).** Whether artifact-shaped reports come
  from layered plans or from checkpoint wording has to be known before the
  default changes, so the new version ships selectable and the flip is a
  one-line follow-up. This settles the brief's question about timing.
- **koto needs no parser.** koto handles plan paths as opaque variables, so
  accepting both versions there means confirming that and recording it
  (R13), not adding code.
