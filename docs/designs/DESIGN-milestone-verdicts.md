---
schema: design/v1
status: Planned
problem: |
  On a milestone roadmap the coordinator's landing path and the completion
  cascade still set a milestone Done when work merges, goal fit never reads
  the milestone's Evidence, a milestone with no pull request can't reach a
  verdict, and nothing returns a Done milestone to In progress. The Done rule
  in the roadmap format reference is documented but no script enforces it.
decision: |
  A file-only script, milestone.sh, reads a milestone's Evidence and checks
  three new record entries (verdict, failure, goal fit). On a roadmap/v2
  roadmap the coordinator's `landed` tick writes a verdict-owed Work row
  instead of a Done pull request and routes to a new milestone_verdict state;
  roadmap-status.sh gains --verdict and --reopen modes that open the roadmap
  edit a checked entry calls for. A new `failure` event routes to a
  milestone_reopen state. Pick, close-out and the brief read the new rows,
  land-check adds the Evidence to goal fit's input, and the cascade skips
  milestone roadmaps.
rationale: |
  Every decision about Done, re-offering and closing stays in the record body,
  which only the coordinator's guarded scripts write, while entries carry the
  readable trail; that keeps a worker posting with the same GitHub login from
  closing its own milestone. Reusing roadmap-status.sh keeps one writer for
  roadmap edits and its one-pending-edit rule, the schema switch keeps
  feature roadmaps unchanged, and a bash reader of Evidence avoids a new CLI
  surface while the validator's milestone check already guarantees the
  format it reads.
upstream: docs/prds/PRD-milestone-verdicts.md
decision_provenance: inline-resolved
---

# DESIGN: milestone verdicts

## Status

Planned

## Context and Problem Statement

shirabe's roadmap format reference defines a milestone (a `roadmap/v2`
roadmap item with Outcome, Evidence, Left open and Dependencies) and a Done
rule for it: a milestone is Done only after the coordinator that dispatched
the work, or a person, checks the shipped work against its Evidence and
records a verdict (changes needed, verified with follow-ups, or verified).
The reference then says no tool enforces the rule. The requirements this
design answers are in `docs/prds/PRD-milestone-verdicts.md`; each is restated
below where a decision answers it.

The technical problem has five parts, each in code that exists today.

**The coordinator writes Done on landing.** `/coordinate` is a koto workflow
(`skills/coordinate/koto-templates/coordinate.md`). From `wait`, the
coordinator ticks `landed` when it judges a roadmap unit's last piece done;
that routes to `roadmap_status`, whose directive runs
`skills/coordinate/scripts/roadmap-status.sh --unit <tag> --outcome <text>`.
The script reads the roadmap at the default branch's head, rewrites the
unit's block to `**Status:** Done` with a `**Delivered:**` line, opens a pull
request it never merges, and writes a Side effects row (Action
`roadmap-status`) that `pick-facts.sh` reads as "landed" and `--confirm`
clears once the default branch reads Done. The `merge_confirm` and
`merged_facts` directives separately suggest dispatching a worker for a
"status-line pull request" when a feature's PLAN lives elsewhere. Nothing in
`skills/coordinate/scripts/` reads a roadmap's `schema:`, Outcome or
Evidence; `lib_roadmap_features` in `record-common.sh` reads tag, title,
Status and Dependencies only.

**Goal fit judges against the brief.** The `land` check state's
`land-check.sh` writes `coord/land.json`, which `goal_fit` reads together
with the brief it dispatched. `goal_fit` accepts `fit:
fits|fits_with_follow_ups|gap` and a rationale that stays in the local koto
log; nothing posts it to the record.

**A finished report with no pull request is bounced.** `classify_report`
routes a `done` report through `report-pr.sh`; with no pull request on the
holding and none named, it returns to `wait` and its directive tells the
coordinator to ask the worker to name one.

**Nothing reopens.** `roadmap-status.sh --unit` refuses a unit that already
reads Done, `--confirm` only accepts Done, and `wait` has no event for a
failure found after Done. The picker (`pick-facts.sh`) offers a unit that
reads not-done with no holding and no pending row, so a milestone the
default branch reads In progress again would be offered; but nothing gets
it there, and between `landed` and a verdict, once the worker's holding is
retired at teardown, the same rule would offer a merged milestone that is
still awaiting judgment. Close-out (`closeout-read.sh`) blocks on features
not Done, holdings, side effects, deferrals and decisions, and reads no Work
rows.

**The cascade writes or fails on a milestone roadmap.**
`skills/work-on/scripts/run-cascade.sh` finishes a PLAN's chain and then, in
`handle_roadmap`, looks for a `**Downstream:**` line naming the plan, sets
that feature Done, and deletes the roadmap once every Status is Done. A
milestone roadmap has no `**Downstream:**` line, so the lookup misses, the
step fails, the run reports `partial`, and `/execute` halts. Where someone
hand-added the line, the cascade sets Done in the worker's own pull request.

Two constraints shape everything below. koto can't branch on a file's
contents, so a v1/v2 split has to come from a script's output or evidence.
And any session using the coordinator's GitHub login can post a comment on
the record issue, including the worker that did the work, so entries can't
be what gates Done; the record body, written only by the coordinator's
scripts behind `lib_write_guard`, has to carry every decision.

## Decision Drivers

- **No merge-driven Done on milestone roadmaps (PRD R1).** No landing tick,
  merge guidance or cascade step may set a milestone Done, write its
  Delivered line in place of a verdict, or propose a pull request that does.
  Feature roadmaps keep every one of those behaviours.
- **One verdict step for every milestone (R2).** Ticking `landed` for a
  milestone reaches a step that doesn't release the milestone until a
  checked verdict is recorded or the coordinator defers it; a milestone with
  no pull request reaches it the same way, and a finished no-pull-request
  report isn't bounced.
- **A checked, fixed-shape verdict entry (R3).** Labelled lines in a fixed
  order: Verdict with the tag, Checked by, Checked on, Source (roadmap path at
  a commit), Work checked, one held/not-held line per Evidence clause in the
  roadmap's order, Strategy fit, Follow-ups (`none`, `new: <title>`, `amend
  <tag>: <what>`), Changes needed. A check refuses a broken shape, a clause
  count that differs from the Evidence at Source, a verdict that breaks the
  rules table (verified: all held, fits, no follow-ups, no changes; verified
  with follow-ups: the same with at least one follow-up; changes needed: a
  clause not held or does not fit, and changes named), a future date, and a
  checker naming the holding worker's topic in any letter case.
- **Done only from the verdict, in one edit (R4, R5).** A checked verdict is
  followed by a roadmap pull request that adds a dated Progress line (tag,
  verdict, checker, entry URL) and the work to Delivered; for a verified
  verdict it sets Done and removes Needs; for verified with follow-ups it
  also adds each follow-up in the same change; for changes needed the Status
  stays. The writer never merges, refuses a milestone already Done, a Source
  whose Evidence for the milestone differs from the default branch's, a
  `new:` tag already used or an `amend` of an unknown tag, and a second edit
  while one is pending; a pending edit closed unmerged can be dropped and
  reopened from the same entry.
- **Nothing re-dispatched while a verdict is owed (R6).** The picker never
  offers a milestone between `landed` and its confirmed verdict edit, with or
  without its holding; after a confirmed changes-needed edit it is offered
  again and its next brief carries the Changes needed line and the not-held
  clauses.
- **Goal fit names clauses (R7).** Landing a pull request for a milestone
  shows goal fit the numbered Evidence from the default branch and posts an
  entry naming the pull request, the milestone and the clause numbers it
  advances or `advances none`; a check refuses a clause number the milestone
  lacks; `advances none` doesn't block landing on its own.
- **Reopening (R8, R9).** A failure entry (`Failure: <tag>`, Reported by,
  Seen on, Clause, What was seen), checked against a milestone that reads
  Done and an in-range clause, is followed by a roadmap pull request setting
  In progress with a Progress line. Once confirmed, the picker offers the
  milestone again with the failure in its next brief; dependents read
  blocked, and a dependent holding a worker is listed by the step that
  recorded the failure. `shirabe validate` accepts the Done-to-In-progress
  change.
- **Close-out waits (R10)** while a verdict is owed or a reopen edit is
  pending, naming the milestone.
- **Cascade (R11).** On a milestone roadmap the cascade leaves the roadmap
  byte-for-byte unchanged, never transitions or deletes it, records its
  roadmap step `skipped` with a reason naming the Done rule, and reports
  `completed` when nothing else failed; feature roadmaps unchanged.
- **Documents (R12)** stop saying the rule is unenforced or that the cascade
  or coordinator updates a milestone's status on merge.
- **Bash 3.2, offline suites, CI (R13, R14).** Every changed script runs on
  bash 3.2 and sits in `scripts/check-bash-floor.sh`'s list; every acceptance
  criterion is a script suite against a `mktemp` test roadmap and record with
  the GitHub and koto stand-ins, run in CI.
- **An entry alone changes nothing (R15).** Done, a cleared mark, a re-offer
  and a close-out depend on the record body and the default branch; an
  entry's author is read from its text, never from the comment's author.
- **Implementation drivers.** Keep the koto template change small (each new
  state costs a WANT-list entry, mermaid edges, a directive, a
  record-confirm case and rule-coverage rows); keep one writer of roadmap
  edits so the one-pending-edit rule still prevents conflicting generated
  sections; add no new `shirabe` CLI surface unless bash can't do it.

## Considered Options

The decisions below were resolved inline within this design under `/scope`
(standard tier, no `/decision` delegation).

### Decision 1: How the verdict enters the coordinate loop and holds the milestone

The template can't read the roadmap's schema, `landed` already means "the
coordinator judged this unit's work finished, with or without a merge" (its
guidance covers a spike or design whose acceptance call was made), and
something has to keep the picker away from a merged milestone awaiting
judgment after its holding is retired.

Key assumptions:
- The coordinator ticks `landed` for a no-pull-request milestone once its
  work is reported finished; no machine event marks that moment.
- One pending roadmap edit at a time stays acceptable for verdict edits.

#### Chosen: script-decided branch at `roadmap_status`, a new `milestone_verdict` state, and a `verdict-owed` Work row

`roadmap-status.sh --unit` reads the roadmap's `schema:` first, before any
of its existing refusals. On `roadmap/v2` it opens no pull request: it
writes a Work row of a new kind, `verdict-owed`
(Unit the tag, Who the holding's topic or `coordinator`, Next `verdict owed
since <date>`), prints `verdict-owed <tag>`, and exits 0. `roadmap_status`
gains the evidence value `status: verdict_owed`, which routes to a new agent
state, `milestone_verdict`. That state accepts `verdict: recorded|deferred`
and `unit`: `recorded` goes to `record`, whose `record-confirm.sh` rule for
this source requires a pending verdict-edit row naming the unit; `deferred`
goes back to `wait`, leaving the row. A later `landed` tick for the same unit
finds the row already there, prints `verdict-owed` again, and reaches the
state again. The Work row is what `pick-facts.sh` and `closeout-read.sh`
read, and `roadmap-status.sh --confirm` removes it when the verdict edit's
expected state is on the default branch. `dispatch_check`
(`deferral-check.sh`) also refuses a topic whose unit has a `verdict-owed`
row, so the guard doesn't rest on the pick directive's prose, and the pick
directive lists every verdict-owed milestone as a reminder, so a deferred
verdict comes back each time the run picks.

#### Alternatives Considered

**Widen `roadmap_status` to take the verdict directly.** No new state, but
one state would mean "Done pull request opened" on v1 and "verdict recorded"
on v2, with evidence fields that apply to only one of them; its directive
would carry both procedures. Rejected for legibility and because the
record-confirm rule would have to branch on schema too.

**A check state in front of `roadmap_status` that reads the schema.** It
would make the split a gate rather than a script output, at the cost of new
verdict codes in `coord-verdict.sh`, its table test and a cycle check. The
script already reads the roadmap at the default branch, so the check state
would read it twice. Rejected as more surface for the same guarantee.

**Keep the holding until the verdict instead of a new row.** The holding is
removed at teardown, which the coordinator runs when the worker is done, and
retirement order is a separate concern; tying the verdict to the holding
would block teardown on judgment or lose the guard. Rejected.

**A Side effects row as the mark.** Side effects are pull requests in flight
with a "how to confirm" check; a verdict owed has no pull request yet.
Rejected as a misuse of the section.

### Decision 2: How verdicts, failures and goal-fit judgments are recorded and checked

Three judgments need to be readable afterwards, and two of them need a
mechanical check before anything follows from them. Clause identity has to
survive sharpening of Evidence in place.

Key assumptions:
- The `roadmap/v2` validator check keeps every milestone's Evidence a `- `
  list under `**Evidence:**`, which a bash reader can number.
- Coordinators write entries by hand from the directive's template.

#### Chosen: three plain-text entry kinds checked by one file-only script

`record-append.sh` gains the kinds `milestone-verdict`, `milestone-failure`
and `goal-fit` (avoiding bare "verdict", which already names check-state
codes, `decision_verdict` and the board and teardown verdicts). A new script,
`skills/coordinate/scripts/milestone.sh`, reads files only (no network, git
or koto) and has six subcommands:

- `schema ROADMAP` prints the frontmatter `schema:` value;
- `evidence ROADMAP TAG` prints `{tag, title, status, schema, evidence:
  [clause, ...]}` as JSON, each clause's lines joined;
- `check-verdict ROADMAP TAG ENTRY [--worker TOPIC] [--today DATE]` checks
  the PRD's verdict shape and rules table against the milestone in ROADMAP
  (the Source commit's copy), printing the verdict, checker and follow-ups
  as JSON on success;
- `check-failure ROADMAP TAG ENTRY [--today DATE]` checks the failure shape,
  that TAG reads Done and that the clause number is in range;
- `progress-has ROADMAP TEXT` exits 0 when the `## Progress` section
  contains TEXT;
- `check-goal-fit ROADMAP TAG ENTRY` checks a goal-fit entry (`Goal fit:
  <owner/repo#n> -- <tag>`, `Fit: <fits|fits with follow-ups|gap>`,
  `Clauses: <n, n|advances none>`, `Rationale: <text>`) and that every clause
  number exists.

Clauses are identified by position in the Evidence list at the commit the
entry names. The verdict's `Source` pins that commit; the writer then
refuses when the default branch's Evidence for the milestone differs from
Source's (Decision 3), so a renumbering can't attach a judgment to the wrong
clause.

#### Alternatives Considered

**Structured JSON inside each entry**, as `cost` entries carry. Easier to
parse, harder for a person to write and read on the issue page; the
checker would still have to validate fields. The fixed labelled-line shape
is the one the PRD specifies and already reads as prose. Rejected.

**Clause identity by quoted text.** Survives reordering but breaks on any
sharpening of the wording, which the format explicitly allows while a
roadmap is Active, and makes entries long. Rejected in favour of position
plus the Source-drift refusal.

**Put the checks in the `shirabe` CLI.** The Rust parser already knows
milestones, but a new subcommand is new public surface, needs a release
before the coordinate scripts could rely on it, and the coordinate tests
stub `shirabe`. Rejected for this feature (see Decision 4).

### Decision 3: How the roadmap edit is written and confirmed

The verdict's edit and the reopen edit change the same generated sections
the existing Done edit changes, and the existing writer already handles
branch creation through the contents API, `shirabe roadmap populate`, the
pending row and its confirmation.

Key assumptions:
- A follow-up milestone's full text (Outcome, Evidence, Left open,
  Dependencies) is something the coordinator writes, not the verdict entry.

#### Chosen: extend `roadmap-status.sh` with `--verdict` and `--reopen`, schema-gated `--unit`, per-row confirmation

- `--unit TAG` keeps today's behaviour on any roadmap that isn't
  `roadmap/v2`; on v2 it writes the verdict-owed row (Decision 1).
- `--verdict TAG --entry-file F --entry-url URL [--follow-ups FILE]`
  requires TAG's `verdict-owed` row and takes the worker's topic from its
  Who cell; it fetches the roadmap at the entry's Source commit from the
  run's repository (refusing a commit the default branch doesn't contain)
  and runs `milestone.sh check-verdict --worker <topic>` against it, then
  refuses (exit 65, naming why) when TAG reads Done at the
  default branch, when the Evidence for TAG at the default branch differs
  from Source's, when any roadmap edit is pending (stricter than one per
  milestone, so that two pull requests never rewrite the generated sections
  at once), when a `new:` follow-up's
  heading tag is already used or has no section in FILE, or when an `amend`
  names a tag the roadmap lacks. It then rewrites the milestone block:
  appends the Work checked pull requests to `**Delivered:**` (none for
  `none`); for a verified verdict sets `**Status:** Done` and removes
  `**Needs:**`; for verified with follow-ups also inserts each FILE section
  (each `### <tag>: <title>` with non-empty Outcome, Evidence, Left open and
  Dependencies) after the last milestone and applies each `amend` section
  from FILE to its target; for changes needed leaves Status. It appends
  `- YYYY-MM-DD: <tag> -- <verdict>, checked by <checker> (<entry URL>,
  <first 8 of the entry's sha256>)` to `## Progress`, runs `shirabe roadmap
  populate`, and opens the pull request with the whole entry (clause lines,
  strategy fit, follow-ups and changes needed) in its body, so the person
  who merges it reviews the judgment, not just the status word. It writes a
  Side effects row whose Action names the kind: `milestone-done` for a
  verified verdict of either kind (How to confirm `the roadmap on <default>
  reads <TAG> Done`), `milestone-verdict` for changes needed (How to confirm
  `the roadmap on <default> carries <entry URL> in Progress`). The existing
  Action `roadmap-status` stays the feature-roadmap Done edit.
- `--reopen TAG --entry-file F --entry-url URL` runs `milestone.sh
  check-failure`, refuses while any roadmap edit is pending, sets
  `**Status:** In progress`, appends `- YYYY-MM-DD: <tag> -- reopened:
  clause <n> failed, reported by <reporter> (<entry URL>)` to Progress, and
  writes a row with Action `milestone-reopen`, confirming on `reads <TAG>
  In progress`; the pull request body carries the failure entry. It prints the tags
  of milestones that depend on TAG and hold a worker.
- `--confirm TAG` dispatches on the row's Action: `roadmap-status` and
  `milestone-done` check the Status reads Done, `milestone-reopen` that it
  reads In progress, and `milestone-verdict` that the default branch's
  `## Progress` contains the entry URL (`milestone.sh progress-has`).
  `--list` prints every pending row of the four Actions, with an `action`
  field, and `pick-facts.sh` keeps treating any of them as a pending edit. Confirming a verdict
  row removes TAG's `verdict-owed` row; confirming a changes-needed verdict
  or a reopen also writes a `rework` Work row for TAG whose Next carries the
  verdict's Changes needed line and its not-held clause numbers, or the
  failure's clause and what was seen (truncated to the body's cell budget).
- `--drop TAG --reason` keeps its meaning for every row kind; the entry is
  still on the record, so `--verdict` or `--reopen` can be run again from
  it.

#### Alternatives Considered

**A new writer script for milestones.** Cleaner separation, but two writers
of roadmap pull requests would need a shared pending-edit rule to avoid
conflicting generated sections, and would duplicate the contents-API commit
path. Rejected.

**A local agent makes the edit from a brief**, as some hand procedures do.
It moves the edit out of the coordinator's guarded write path, needs a
second check of the agent's diff, and can't be confirmed mechanically.
Rejected.

**Put follow-up milestone text in the verdict entry.** It would make entries
long and mix the judgment with authoring; the entry names the follow-ups,
and the edit carries their text. Rejected.

### Decision 4: How the coordinator scripts read Evidence and schema

#### Chosen: an awk reader in `milestone.sh`

The reader parses the frontmatter `schema:` line and, under `## Features`,
the block for one `### <tag>: <title>` heading: its `**Status:**` value and
the `- ` items under `**Evidence:**` up to the next `**Field:**` line or
heading, joining wrapped lines. `land-check.sh`, `roadmap-status.sh` and
`pick-facts.sh` call it rather than extending `lib_roadmap_features`, so the
picker's existing reader and its tests stay as they are.

#### Alternatives Considered

**A `shirabe roadmap milestones --json` subcommand** over the Rust parser.
One parser instead of two, but new CLI surface, a release dependency, and
the coordinate tests' `stand-in-shirabe` would have to emulate it. Rejected
for now; the duplication is recorded under Consequences.

**Extend `lib_roadmap_features`.** It feeds every pick; adding Evidence
there widens every reader for the benefit of three. Rejected.

### Decision 5: How the cascade recognizes and skips a milestone roadmap

#### Chosen: read the frontmatter in `handle_roadmap`

Before its `**Downstream:**` lookup, `handle_roadmap` reads the roadmap's
frontmatter; for `schema: roadmap/v2` it records the step
through `add_step` with action `update_roadmap_feature`, the roadmap as
target, status `skipped` and the detail `milestone roadmap: status follows
a recorded verdict (roadmap format, When a milestone is Done)`, writes nothing, and returns without calling
`handle_roadmap_deletion`. `skipped` is already a step status the cascade
defines for state it doesn't control, so `cascade_status` stays `completed`
when nothing else failed, and neither `/execute`'s gates nor `/work-on`'s
routing changes.

#### Alternatives Considered

**Carry the schema on finalize-chain's `roadmap_handoff` node.** Moves the
decision into Rust, but the cascade's tests run in a workflow that doesn't
trigger on `crates/**` and the node today carries only a path. Rejected.

**A new `cascade_status` value.** `/execute` matches three literal values
and would stall; `/work-on` would refuse it. Rejected.

**Detect milestones by `**Outcome:**`/`**Evidence:**` lines.** Some feature
roadmaps carry `**Outcome:**` lines that record merged pull requests.
Rejected; the validator gates milestone checks on the schema the same way.

## Decision Outcome

On a `roadmap/v2` roadmap the coordinator's `landed` tick no longer opens a
Done pull request. `roadmap-status.sh --unit` writes a `verdict-owed` Work
row and sends the run to `milestone_verdict`, where the coordinator reads the
milestone's numbered Evidence with `milestone.sh evidence`, writes a verdict
entry, checks it with `milestone.sh check-verdict`, posts it as a
`milestone-verdict` entry, and runs `roadmap-status.sh --verdict`, which opens
the one roadmap edit the verdict calls for. The milestone reads Done only
when that edit reaches the default branch, and `--confirm` then clears the
verdict-owed row. Until then the picker won't offer it and close-out won't
close the roadmap. A changes-needed verdict's confirmation leaves a `rework`
row the next brief carries. A failure found later goes through a new `wait`
event, `failure`, to `milestone_reopen`, which checks and posts a
`milestone-failure` entry and runs `roadmap-status.sh --reopen`; once the In
progress edit is confirmed the picker offers the milestone with the failure
in its brief. Goal fit gets the Evidence from `coord/land.json` and posts a
`goal-fit` entry naming clauses. The cascade skips milestone roadmaps.
Feature roadmaps go through every path exactly as before.

The decisions fit together around one boundary: entries are what a reader
follows, the record body and the default branch are what every decision
reads. A worker can post a perfectly shaped verdict entry, and nothing
follows from it, because no verdict-owed row is cleared, no roadmap edit is
opened and no pick changes until the coordinator's own scripts write the
body.

## Solution Architecture

### Overview

```
landed (v2) ──> roadmap_status ──verdict_owed──> milestone_verdict ──recorded──> record ──> pick
     │              │ roadmap-status.sh --unit        │ milestone.sh evidence / check-verdict
     │              └── writes Work row verdict-owed  │ record-append --kind milestone-verdict
     │                                                └ roadmap-status.sh --verdict (PR + Side effects row)
failure ─────────────────────────────> milestone_reopen ──opened──> record
                                          │ milestone.sh check-failure
                                          │ record-append --kind milestone-failure
                                          └ roadmap-status.sh --reopen
land ──> goal_fit (land.json carries milestone.evidence; goal-fit entry)
--confirm: verdict row confirmed -> drop verdict-owed; changes needed / reopen -> write rework row
pick-facts: verdict_owed and rework facts; closeout-read: verdict-owed blocks
run-cascade.sh handle_roadmap: roadmap/v2 -> step skipped, no write, no deletion
```

### Components

- **`skills/coordinate/scripts/milestone.sh`** (new): the file-only reader
  and the three entry checks (Decision 2, 4). Exit codes follow the
  coordinate scripts: 0 pass, 1 the check failed (reason on stderr naming the
  line), 2 a file couldn't be read or TAG isn't a milestone with Evidence, 64
  usage.
- **`roadmap-status.sh`** (changed): schema-gated `--unit`; new `--verdict`
  and `--reopen`; per-row `--confirm` that clears `verdict-owed` and writes
  `rework` (Decision 3).
- **Record codec** (`record-codec.jq`, `record-parse.sh`,
  `record-render.sh`, `record-state.sh`): Work kinds `verdict-owed` and
  `rework`, and Side effects Actions `milestone-done`, `milestone-verdict`
  and `milestone-reopen`, everywhere the Work and Side effects sections are
  parsed, validated and rendered. `record-append.sh`: entry kinds
  `milestone-verdict`, `milestone-failure`, `goal-fit`.
- **`pick-facts.sh`** (changed): per-unit `verdict_owed` (bool) and `rework`
  (text or null) from Work rows. The pick directive never dispatches a
  `verdict_owed` unit; an In progress unit with `rework` and no holding is
  offered as usual.
- **`render-brief.sh`** (changed): when the picked unit carries `rework`,
  the brief's acceptance gets a criterion quoting it; `dispatch` clears the
  `rework` row with `record-state.sh --done` after the dispatch succeeds.
- **`deferral-check.sh`** (changed): `dispatch_check` refuses a topic
  whose unit has a `verdict-owed` row, with a new verdict word and code in
  `coord-verdict.sh`.
- **`closeout-read.sh`** (changed): a new blocker, `verdict-owed <tag>`,
  for any `verdict-owed` Work row; a pending reopen edit already blocks as a
  side effect in flight.
- **`land-check.sh`** (changed): it maps the pull request to its holding's
  unit (the Holdings rows it already reads for holds give the tag), reads
  the roadmap at the default branch (a new read for this script), and when
  the roadmap is `roadmap/v2` adds `milestone: {tag, evidence: [...]}` from
  `milestone.sh evidence` to `coord/land.json`.
- **`shirabe validate`** (unchanged code, new test): FC21 checks a
  milestone's Status is one of the four values and compares nothing with an
  earlier version, so a Done-to-In-progress change already passes; a fixture
  test in `crates/shirabe-validate` pins that a reopened milestone roadmap
  with a reopen Progress line validates.
- **Template** (`coordinate.md`, `coordinate.mermaid.md`): `roadmap_status`
  accepts `verdict_owed`; new agent states `milestone_verdict` and
  `milestone_reopen`; `wait` gains the event `failure`; `goal_fit` accepts
  an optional `clauses` string; directives for `classify_report` (a
  milestone finished with nothing to merge: classify done and tick
  `landed`), `merge_confirm` and `merged_facts` (no status-line pull request
  on a milestone roadmap), `pick` (never dispatch `verdict_owed`) and
  `goal_fit` (read `milestone.evidence`, post the goal-fit entry checked by
  `milestone.sh check-goal-fit`). `record-confirm.sh` gains rules for the two
  new source states.
- **`skills/work-on/scripts/run-cascade.sh`** (changed): Decision 5.
- **Documents**: `skills/roadmap/references/roadmap-format.md` (Done rule
  enforced; post-Done failure returns a milestone to In progress through the
  coordinator; the one-feature-roadmap paragraph stops saying the cascade
  updates status for milestone roadmaps); `skills/coordinate/SKILL.md` and
  `skills/coordinate/references/record-template.md` (a Verdicts section:
  the verdict step, the three entries, reopening).

### Key Interfaces

Verdict entry (`--kind milestone-verdict`), one line each, then a blank line
before `Evidence:` and before `Strategy fit:`:

```
Verdict: <tag> -- <changes needed|verified with follow-ups|verified>
Checked by: <the coordinator's session name, or a person>
Checked on: <YYYY-MM-DD>
Source: <docs/roadmaps/ROADMAP-<name>.md> at <commit>
Work checked: <owner/repo#n, owner/repo#n | none>

Evidence:
1. <held|not held> -- <what showed it>
2. <held|not held> -- <what showed it>

Strategy fit: <fits|does not fit> -- <why>
Follow-ups: <none | new: <title>; amend <tag>: <what>>
Changes needed: <none | what must change>
```

Failure entry (`--kind milestone-failure`):

```
Failure: <tag>
Reported by: <a person, or the coordinator's session name>
Seen on: <YYYY-MM-DD>
Clause: <n>
What was seen: <text>
```

Goal-fit entry (`--kind goal-fit`):

```
Goal fit: <owner/repo#n> -- <tag>
Fit: <fits|fits with follow-ups|gap>
Clauses: <n, n | advances none>
Rationale: <text>
```

`roadmap-status.sh` new usage:

```
roadmap-status.sh --session S --verdict TAG --entry-file F --entry-url URL [--follow-ups FILE]
roadmap-status.sh --session S --reopen TAG --entry-file F --entry-url URL
```

Exit codes keep the script's existing meanings (65 a refusal, 2 a read
failed, 64 usage); `--unit` on v2 exits 0 and prints `verdict-owed <tag>`.

Template evidence: `roadmap_status` `status: opened|verdict_owed|failed`;
`milestone_verdict` `verdict: recorded|deferred`, `unit`;
`milestone_reopen` `status: opened|failed`, `unit`; `wait` `event: failure`
with `unit`; `goal_fit` optional `clauses`.

`pick.json` per unit adds `verdict_owed` and `rework`; `land.json` adds an
optional `milestone`.

Cascade step record on v2: `{"action": "update_roadmap_feature", "target":
"<roadmap path>", "found_in": null, "status": "skipped", "detail":
"milestone roadmap: status follows a recorded verdict (roadmap format, When
a milestone is Done)"}`.

### Data Flow

1. A worker's last pull request merges, or it reports a no-PR milestone
   finished. The coordinator ticks `landed` with the unit.
2. `roadmap_status`: `roadmap-status.sh --unit` reads the default branch's
   roadmap; v2 writes `verdict-owed` and the run goes to `milestone_verdict`.
3. The coordinator checks each clause, writes the entry to a file outside
   any repository, runs `milestone.sh check-verdict` against the Source
   commit's copy with `--worker <topic>`, posts it with `record-append.sh
   --kind milestone-verdict` (which prints the entry URL), and runs
   `roadmap-status.sh --verdict` with that URL. Submits `recorded`.
4. `record` confirms the pending verdict-edit row; `pick_facts` reads
   `verdict_owed: true` for the unit until the edit merges and `--confirm`
   clears it, writing `rework` after a changes-needed verdict.
5. Later, a person reports a failure. The coordinator ticks `failure`,
   writes and checks the failure entry, posts it, and runs `--reopen`, which
   prints held dependents. Once merged and confirmed, `rework` carries the
   failure and the picker offers the milestone; `render-brief.sh` quotes the
   rework text into the next brief and `dispatch` clears the row.

## Implementation Approach

Each phase leaves the coordinator working on both roadmap schemas, adds its
scripts and suites to `scripts/check-bash-floor.sh` and to the CI workflow
that runs its skill's tests, and extends one acceptance suite,
`skills/coordinate/scripts/milestone-verdicts_test.sh`, which drives the
scripts against a test milestone roadmap (one PR-bearing milestone, one
host-state milestone) and an empty record in a `mktemp` directory with the
GitHub and koto stand-ins.

### Phase 1: A verified verdict closes a milestone, and nothing else does

`milestone.sh` (`schema`, `evidence`, `check-verdict`, `progress-has`), the
`milestone-verdict` entry kind, the `verdict-owed` Work kind and the new
Side effects Actions through the record codec, schema-gated `--unit`,
`--verdict` for verified and changes-needed verdicts without follow-ups,
the per-Action `--confirm`, the `roadmap_status` evidence value and the
`milestone_verdict` state with its record-confirm rule, `verdict_owed` in
`pick-facts.sh` and the `dispatch_check` refusal, the `classify_report`
route for a finished no-pull-request milestone, and the `merge_confirm` and
`merged_facts` wording. The acceptance suite records a verdict for both test
milestones from an empty record.

### Phase 2: Judgment that waits is held and carried

The `closeout-read.sh` blocker, deferral and the pick reminder, the `rework`
row written at `--confirm` and carried into the brief by `render-brief.sh`
and cleared at dispatch, follow-ups (`--follow-ups`, `new:` and `amend`),
and the writer's edge-case refusals (Done, Source drift, pending edit, drop
and re-open, entry binding).

### Phase 3: The cascade leaves milestone roadmaps alone

`run-cascade.sh` Decision 5 with scenarios for a v2 roadmap (unchanged file,
`completed`, step skipped, no deletion) and the v1 regression.

### Phase 4: Goal fit names the Evidence it advances

`land-check.sh` milestone evidence, `milestone.sh check-goal-fit`, the
`goal-fit` entry kind, and the `goal_fit` directive and `clauses` field.

### Phase 5: A failure reopens a Done milestone

`milestone.sh check-failure`, the `milestone-failure` kind, `--reopen`, the
`failure` event and `milestone_reopen` state, the dependents listing,
re-offer with the failure in the brief, and the validator fixture test.

### Phase 6: The documents say what the tools do

`roadmap-format.md`, the coordinate skill's documentation and record
template, and a final pass of the acceptance suite over every criterion.

## Security Considerations

The feature adds no network surface and no dependency. It does add writes
under the coordinator's token: roadmap pull requests for verdicts and
reopens, through the contents API path `roadmap-status.sh` already uses.
Every GitHub write goes through `record-append.sh`, `record-state.sh` and
`roadmap-status.sh`, which keep the record's session write guard
(`lib_write_guard`).

**Precondition: the roadmap pull request is reviewed.** Done is only as
strong as the review of the pull request that sets it. The writer puts the
whole verdict entry in that pull request's body for this reason, and the
coordinate documentation states that a milestone roadmap's edits must not
be auto-merged without a person's review; a repository that auto-merges
them gives up the control this design rests on.

**Trust model.** Any session using the coordinator's GitHub login,
including the worker that did the work, can post a comment shaped like a
verdict, and any write collaborator can edit one. The design makes such a
comment inert rather than forbidden: Done follows only from a roadmap pull
request that `roadmap-status.sh --verdict` opens under the write guard and
that a person or the repository's merge rules merge, and the verdict-owed
and rework rows and close-out read only the record body and the default
branch. What this doesn't stop is a process that holds the coordinator's
session writing the body or the API directly, or the coordinator being
persuaded by text it reads. The `--worker` refusal catches an honest mistake
(the checker naming the holding worker's topic), not a determined forger.
Review of the roadmap pull request is the real control on Done.

**Binding the entry to the edit.** `--verdict` and `--reopen` re-read the
comment at `--entry-url`, require it to be a comment on this run's record
issue carrying the matching entry kind, and require its text to equal the
entry file. The Progress line carries a short hash of the entry text, so a
later edit of the comment is visible. The Source commit must be a full
40-character hash, its path must pass the roadmap path check, and the copy
is read from the run's own repository.

**Input grammar.** Entry text never reaches a shell: `milestone.sh` reads it
with `awk` and `jq`, and the writer passes values through `jq --arg`, a file
or `ENVIRON`, never interpolated and never through `awk -v`, which
interprets backslashes. Fields that reach a committed file have closed
shapes: the checker and reporter (a login, a session name or a plain name,
at most 60 characters), Work checked (`owner/repo#n` items), follow-up
titles (one line, at most 120 bytes, no markdown or HTML metacharacters, no
`@`), and the entry URL. Each is refused when it holds a control character
or a path into a work-in-progress directory. Entry text passes through the
record's existing redaction (`lib_redact`) before it is posted. The rework
text is capped and quoted into the brief as data under a fixed heading. The
Evidence reader refuses a milestone block it can't classify (a code fence, a
tab, an unexpected structure), and its suite runs it against fixtures the
validator also accepts, comparing its clause count with the validator's on
each.

**Reopening, and report text reaching a worker.** A failure entry moves a
Done milestone to In progress and makes its dependents read blocked, which
costs a dispatch. The reporter is named, not authenticated; the control is
that the reopen is a pull request a person merges, with the failure entry in
its body. The failure's "What was seen" text is the first external text
meant to reach a dispatched worker's brief, so it has a closed shape (one
paragraph, at most 600 bytes, no URLs or markdown links, no control
characters), and the brief quotes it under a fixed heading that labels it
an unverified report to check against the Evidence, never instructions. The
changes-needed text a `rework` row carries is the coordinator's own and
gets the same shape and label.

**Closed grammars and caps.** A TAG is refused unless it matches the
heading-tag shape the picker already reads (letters, digits, spaces and
hyphens, at most 40 characters). Entry files are capped at 16 KiB and a
`--follow-ups` file at 32 KiB; follow-up sections and `amend` text pass the
same redaction and control-character checks as entries, and an `amend` may
change a milestone's Outcome, Evidence or Left open only together with a
Progress line the writer adds naming the amendment. Working files are made
with `mktemp` under the user's temporary directory. Redaction happens before
an entry is posted and the entry file is written from the redacted text, so
the byte-for-byte binding compares like with like.

**Public content.** A public roadmap carries the Progress line, the
Delivered line and any follow-up milestone, and a public repository's record
issue carries the clause judgments and failure text. Coordinators treat both
as public: no tokens, host paths or private systems. The Progress line holds
only the tag, the verdict word, the date, the checker, the entry URL and the
hash; clause text and changes stay on the record issue. The writer refuses
Work checked references to repositories other than the run's host and the
repositories its holdings name.

**Test-only override.** `--skip-session-checks` with the override flags
bypasses the guard in every coordinate script; the new modes accept it only
with `--scope --name --repo --ref`, as the existing modes do, and the
guard's refusal tests cover them.

## Consequences

### Positive

- Done on a milestone roadmap means a named checker's verdict, and the
  verdict, the goal-fit judgments and any later failure are on the record
  issue for anyone to read.
- Milestones with no pull request close through the same step, so host
  state and walkthrough Evidence stop needing hand edits.
- `/execute` no longer halts on `partial` when a PLAN finishes under a
  milestone roadmap.
- Feature roadmaps and their coordinators see no change.

### Negative

- Two Evidence readers exist: the Rust parser in `shirabe validate` and the
  awk reader in `milestone.sh`. A format change has to touch both.
- One pending roadmap edit at a time serializes verdict edits on a busy
  roadmap; a verdict can be recorded and its edit opened later, but the
  milestone stays verdict-owed meanwhile.
- Refusing a checker that names the holding worker stops an honest mistake,
  not a forger who holds the coordinator's session.
- Nothing retires a fully verified milestone roadmap: the cascade stops
  deleting it, and its end is left to the roadmap's own lifecycle.
- Two new states and one event grow an already large template and its
  structure tests.

### Mitigations

- `milestone.sh`'s suite runs against roadmaps the validator accepts, and the
  validator's FC21 check pins the field shapes the awk reader depends on; a
  later `shirabe roadmap milestones` subcommand can replace the reader
  without changing any entry or row.
- The verdict-owed row keeps the milestone off the picker however long the
  edit waits, and close-out names it.
- The record already documents that entries are posted under the
  coordinator's login; the body remains the single source of decisions.
