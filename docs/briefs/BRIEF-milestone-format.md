---
schema: brief/v1
status: Accepted
problem: |
  A roadmap item says what gets built, not what someone can do once it
  ships or how anyone other than its author would check that. So a merged
  pull request ends up standing in for "done", and the tools that read
  roadmaps misread the ones people actually wrote.
outcome: |
  An author writing or revising a roadmap gets items that state an outcome
  and a check someone else can judge; the validator says which item lacks
  one; and a coordinator picking work reads dependencies and status
  correctly from any roadmap, whatever tag style it uses.
---

# BRIEF: milestone-format

## Status

Accepted

## Problem Statement

A roadmap item today is a heading, a Needs line, a Dependencies line and a
Status line, followed by whatever prose the author wrote. Nothing in the
format asks for the outcome the item exists to deliver, or for a check that
someone other than the session that built it could run against the shipped
result. In practice item bodies describe mechanism: the CLI verb, the file
layout, the component to add. When the work merges, the only evidence on
hand is the merge, so the merge becomes the definition of done. That's how
items get marked Done with their outcome unmet, and how items keep reading
"Not started" for weeks after their outcome shipped by another route,
because nobody could tell from the item what would count.

The same gap shows up in the tools. `shirabe validate` checks a roadmap's
structure but has nothing to say about an item that names no outcome, since
there's no field for one. The coordinator's picker, which decides which item
to hand out next, reads only a narrow spelling of dependencies and status:
`Feature N` references, and a Status that is exactly `Done`. Roadmaps in
real use name their items with prefixed tags (`AB1`, `CD3`), wrap a
dependency list across several lines of prose, and write statuses like
`Done -- shipped in #12` or `Shipped (#34)`. On those roadmaps the picker
treats finished items as unfinished and unfinished dependencies as absent,
so it offers work whose prerequisites haven't landed and holds back work
whose prerequisites have. The coordinator's own status writer makes it
worse: it records the merged pull requests on an `**Outcome:**` line, which
would overwrite the very field an outcome-shaped item needs.

Finally, an Active roadmap's feature list is locked: any change means a new
roadmap. That rule exists to stop scope drifting under a running
initiative, but it also blocks the change that should be easy, tightening
the check on an item as the work teaches what the check should be. Authors
either live with a vague check or start over.

## User Outcome

An author who runs `/roadmap` gets items written as milestones without
asking for them: each one says who can do what once it lands (its
Outcome), how someone other than the author will check that (its
Evidence), which decisions are left to the session that does the work
(Left open), and which other milestones it needs (Dependencies). The rule
for when a milestone counts as done is written where authors and reviewers
read the format, so nobody has to infer it from a merge.

When the author validates the roadmap, an item missing its outcome or its
check fails validation by name, the same way a missing section does today,
so a roadmap can't quietly ship items that have nothing to judge them
against.

A coordinator driving any existing roadmap, new or old, picks work the way
a person reading that roadmap would: finished items read finished whatever
annotation follows the status, dependencies named by prefixed tags or
wrapped across lines are honoured, and the coordinator never overwrites an
item's outcome when it records what merged.

And an author running an initiative can sharpen one milestone's check, or
what it leaves open, in place on an Active roadmap, and the result still
validates, without starting a new roadmap or loosening the lock on what the
roadmap commits to deliver.

## User Journeys

### An author drafts a new roadmap

A maintainer sequencing a new initiative runs `/roadmap` on the topic in a
fresh repository. The draft the workflow hands back has every item written
as a milestone with an outcome, its evidence, what's left open and its
dependencies, and the roadmap validates. The maintainer didn't have to know
the format existed to get it.

### An author validates a roadmap with a gap

A maintainer edits a milestone roadmap and deletes an item's evidence while
reworking it, then runs `shirabe validate` on the file. The command exits
non-zero and names that milestone and the missing field, so the gap is
caught before review rather than at the verdict.

### A coordinator picks from a roadmap written in another style

A coordinator session drives a roadmap whose items are tagged `AB1`,
`AB2` and so on, whose dependency lines run over several lines and mention
items from other roadmaps, and whose finished items read
`Done -- shipped in #12`. At each pick it offers only items whose
same-roadmap dependencies are finished, and a person comparing its blocked
list against their own reading of the roadmap finds the two agree.

### An author sharpens a check mid-flight

Partway through an initiative, a maintainer realises one milestone's
evidence clause can't be judged as written. They run `/roadmap` on the
Active roadmap, are offered a way to sharpen that milestone's evidence in
place, make the change, and the roadmap still validates and stays Active.

## Scope Boundary

### In scope

- The milestone format in shirabe's roadmap format reference: the four
  fields, how each is spelled, the status values, and the rule for when a
  milestone is Done.
- `/roadmap` drafting milestones by default, and its reviewers judging
  them as milestones.
- `shirabe validate` failing a milestone roadmap whose item lacks an
  outcome or evidence, naming the item.
- The roadmap readers agreeing with the format: the populate subcommand's
  parser and rendering, and the coordinator's picker, including prefixed
  tags, wrapped dependency lines and annotated statuses in roadmaps already
  written.
- Keeping the coordinator's status writer from overwriting a milestone's
  outcome field.
- Sharpening a milestone's evidence and what it leaves open in place on an
  Active roadmap, offered by `/roadmap`.

### Out of scope

- Recording verdicts and changing the completion cascade so that no tool
  marks a milestone Done on a merge. The format states the rule; making
  every tool obey it is separate, later work.
- Rewriting existing roadmaps into the milestone format. Readers learn to
  read them as they are; migrating each one is its own work, done roadmap
  by roadmap.
- Plans built from milestones (functional steps, skeleton-first ordering)
  and how `/plan` and `/review-plan` treat them.
- Resolving dependencies that point into another roadmap. The picker can
  only see the roadmap it drives; a cross-roadmap dependency stays prose.
- Any change to koto or niwa.
