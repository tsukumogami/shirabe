---
schema: brief/v1
status: Draft
problem: |
  Plans from /plan are cut along component lines, written in full detail up
  front, and judged by criteria that name files. Nothing works end to end until
  the last entry lands, late detail goes stale, and whoever checks the work can
  only confirm that files exist.
outcome: |
  An author gets a plan of steps: a walking skeleton first, each step leaving
  the work running with a behavioural check, later steps one line until
  earlier ones land. Every reader of plans accepts the new version beside the
  old one, and /review-plan flags a plan cut into layers.
motivating_context: |
  A survey of recently executed shirabe and koto plans found most of them
  decomposed by layer (types, then engine, then CLI, then docs), with only a
  minority of acceptance criteria describing behaviour someone could observe.
  The sessions that dispatch delivery work increasingly judge a unit by the
  behaviour it adds, and a plan whose entries describe files gives them
  nothing to judge.
---

# BRIEF: functional steps

## Status

Draft

## Problem Statement

When an author runs `/plan` on an accepted design, the plan that comes back
usually follows the shape of the code: one entry for the data types, one
for the engine that uses them, one for the command line, one for the
documentation. Each entry is written in full before any of them is built, and
its acceptance criteria name the files and functions it touches. That shape is
easy to write and easy to execute, and it hides three costs.

The first is that nothing anyone can exercise exists until the last entry
lands. A plan of five layers produces four pull requests that each pass their
own tests and none of which a user could try. When the integration is wrong,
the plan finds out at the end, after the earlier layers have been reviewed and
merged against an assumption nobody exercised.

The second is that detail written for the fifth entry before the first one is
built is a guess. The first entry teaches something (a type was the wrong
shape, a call needs a flag), and the later entries either carry stale detail
or get rewritten by whoever happens to be executing them, with no record of
who decided what.

The third is that criteria naming files can be met by work that doesn't do
the job. The session that dispatched the work, the reviewer, and the person
reading a checkpoint report can each confirm that a file exists and a test
passes; none of them can confirm, from the plan, that a behaviour now works.
Checkpoint reports follow the plan's wording and come back as lists of
artifacts. `/review-plan` doesn't notice any of this: a plan cut into layers
passes it as readily as one cut into behaviours.

The plan format itself reinforces the habit. Its unit is the tracker's unit,
an issue, so nothing in the format asks what each entry leaves working.

## User Outcome

An author running `/plan` under a feature with a settled design gets back a
plan whose first step is a walking skeleton: the thinnest path through the
riskiest integration, working end to end. Every later step leaves the work
running and adds one behaviour someone can observe, with a check that proves
it. Only the next step or two are written in full; the rest are a line each,
and the session that owns the plan details each one after the step before it
lands, so the detail reflects what was learned rather than what was guessed.

The plan calls each entry a step, in a new plan version, and every plan
written before this change keeps validating and running exactly as it does
today: nobody has to migrate anything, and the tools that read plans take
either version.

A reviewer running `/review-plan` on a plan cut into layers gets a finding
that says so and names the criteria that describe files rather than
behaviour. A worker reporting at a checkpoint names the behaviour its step
added and the check that shows it, so the person reading the report can judge
the step without opening the code.

## User Journeys

### An author plans a feature in steps

An author has an accepted design for a koto feature and runs `/plan` on it.
The plan comes back with a first step that wires the new command through to a
real result on the simplest input, criteria that read as things a person can
run and observe, and steps three onward as single lines. The plan validator
accepts it on a clean checkout, and the author can see at a glance what will
work after each step.

### The plan's owner details the next step

The person or session that owns a step plan has just seen step one land, and
step two is still a single line. The plan format and `/plan`'s guidance tell
them what a detailed step must carry and when to write it: after the step
before it lands and before its own work starts. They rewrite step two in full
from what step one taught, adjust the remaining one-line steps, and commit the
edit, so the plan's history shows who detailed each step and when.

### A reviewer catches a layered plan

A reviewer runs `/review-plan` on a plan whose entries are "add the types",
"add the engine", "add the CLI", "add the docs". The review flags the plan as
layer-shaped, points out that no entry before the last leaves anything a user
could run, and lists the acceptance criteria that name files or functions
instead of behaviour, so the author knows which ones to rewrite.

### Existing plans keep running

A maintainer has plans in flight written in the current format and starts a
new feature whose plan comes back in the step format. `/execute` drives both, the validator passes
both, and koto's readers of plans parse both; nobody converts the old plan,
and nothing about running it changes.

### A checkpoint report names behaviour

A person who dispatched a step to a worker reads the worker's checkpoint
report to decide whether the step is done. The report says which behaviour the
step added and the command or check that shows it, so they can run the check
instead of reading through a list of changed files.

## Scope Boundary

### In

- A new plan version whose entries are named steps, with a walking-skeleton
  first step, behavioural acceptance criteria, and one-line later steps that
  the validator accepts.
- `/plan` guidance and templates that produce the new version.
- Acceptance of both plan versions by shirabe's plan validator, by `/execute`
  and the scripts it uses to read a plan, and by every koto reader of plans.
- `/review-plan` criteria that flag a plan cut into layers and name criteria
  describing files rather than behaviour.
- Guidance for checkpoint wording that names the behaviour a step added.
- A written description of how to compare checkpoint reports from layered
  plans with and without behavioural checkpoint wording (which plans, which
  wording), and a default plan version that stays as it is until that
  comparison reports.

### Out

- Building the step-by-step execution shape into `/deliver` and `/execute`
  themselves (who hands each step to its own agent, and when the owning
  session's detailing runs as a workflow state). The plan format and
  `/plan`'s guidance describe the rule; the delivery skills adopt it in
  separate work.
- Changing the roadmap format or renaming roadmap entries.
- Converting existing plans to the new version. Both versions stay valid.
- Running the checkpoint-wording comparison itself; that belongs to whoever
  dispatches delivery work, and this feature only makes it possible.
- Measured guidance on how large a step should be.
- Any change to niwa.

