---
schema: design/v1
status: Accepted
upstream: docs/prds/PRD-coordinate-dispatch-path.md
problem: |
  The coordinate skill's dispatch and wait steps are prose. The coordinator
  composes each brief freehand, launches the worker by hand, and is told to
  record the holding first with nothing enforcing it; it reads each report and
  classifies it by eye; and it tears a worker's instance down on its own
  judgment of what the instance still holds. The loop is becoming a koto
  template whose dispatch and wait states call that prose until this feature
  fills them.
decision: |
  The dispatch state runs an agent-invoked script that renders the brief from
  a context key, opens a one-leg koto request when the worker's entry point
  accepts --koto-leg, writes the holding to the record ahead of launching,
  runs niwa dispatch, and marks the holding dispatched or failed. A
  non-overridable command gate reads the record for that holding. The wait
  state picks a target by script and splits into a request-leg path and a
  message path that both land the report in one context key, which a
  classification state reads through a shadow decider. A teardown state gates
  destruction on a content-based inventory of the worker's instance.
rationale: |
  niwa dispatch takes longer than koto's 30-second action cap and its success
  launches a session nobody can un-launch, so it can't be a default_action;
  an agent-run script with a gate that reads the record gives the same
  guarantee without that. Writing the holding before the launch is the only
  order in which a dying coordinator leaves something reconcile can see.
  Legs are fixed when a request is created and named per skill, so one
  request per worker is the only shape koto supports, and splitting the wait
  into two states is how one gate reads a leg chosen at run time.
---

# DESIGN: coordinate-dispatch-path

## Status

Accepted

## Context and Problem Statement

The requirements are in `docs/prds/PRD-coordinate-dispatch-path.md` (R1 to
R25), which frames the problem in full. This section states the technical
shape of it.

The `coordinate` skill is being turned into a koto template by the record
feature, whose brief names the loop's states: start, reconcile, pick,
dispatch, wait, verify, land or surface, record, and the rotation close-out.
Its dispatch and wait states call the prose in `skills/coordinate/SKILL.md`
(steps 3 and 4) and `references/brief-template.md` until this feature fills
them. The record feature also owns the record's container (an issue at
roadmap scope, a pull request per rotation) and the writer that renders it;
this feature adds holdings through that writer and reads them back through
its reader.

Four facts about the tools shape the design:

- **`niwa dispatch` is slow and final.** It clones the instance and waits for
  the session id before returning, which took 18 to 30 seconds on a
  development host. koto gives a `default_action` 30 seconds per run. Its
  success also launches a session, an externally visible event no later
  signal can undo. `--name` becomes a slug (dashes to underscores) plus a
  random token, so the session name peers message can't be predicted, and a
  reused name isn't refused.
- **koto request legs are fixed at creation and named per skill.** A request's
  legs are declared when it's created and can't be added later. `/scope`
  answers only a leg named `scope`, `/execute` only `execute`, and, once #401
  lands, `/deliver` only `deliver` and `/work-on` only `work-on`. A root
  session attaches to a leg by template file name and by the leg's declared
  inputs. Attach doesn't check the working directory, so a worker in another
  instance on the same host and home directory can attach.
- **A `request-leg` gate reads one leg,** named by `request` and `leg` fields
  that take literals or `{{VAR}}` substitutions. A capture delivers one value
  per state. Result shapes differ by skill: `/scope`, `/execute` and
  `/deliver` put `outcome`, `step`, `reason` and `pr` in the payload; `/work-on`
  terminals carry no result map, so its leg reports only koto's `status` and
  `final_state`.
- **koto session names are machine-wide.** `scope-<topic>` started from a
  second instance is refused as an origin mismatch while the first is live.

## Decision Drivers

- No window in which a launched worker is missing from the record (PRD R8).
- No gate this feature adds is satisfiable by a value the coordinator submits
  (R22); every gate that routes on a fact reads it from the record, a leg, or
  the instance itself.
- The template's other states belong to the record feature. This feature adds
  states and gates and fills the two it was handed, without restructuring.
- koto's authoring rules: a command whose success is the irreversible event
  stays out of `default_action`, a `default_action` finishes in 30 seconds and
  must be safe to re-run, and a decider's inputs are gated context keys or
  variables.
- Short bounded waits only; nothing the workflow needs runs without an end
  (R14).
- The skill carries no permission rule and no workaround for a filed defect.

## Considered Options

### Decision 1: Who runs the dispatch

**Chosen: an agent-run script, `dispatch-worker.sh`, gated on the record.**
The dispatch state's directive tells the coordinator to put the brief input in
context and run the script. The state's gate then reads the record.

*Alternative: a `default_action` that runs `niwa dispatch`.* It would take the
step out of the agent's hands entirely, which is what the PRD's "can't leave
the step" wants. It fails on two counts. `niwa dispatch` routinely runs close
to or past the 30-second cap, and a timed-out action has launched a worker the
tick then reports as failed. And a `default_action` re-runs on every tick that
enters the state without evidence, so each gate-blocked retry would launch
again unless the script made itself idempotent, at which point the engine is
running a command whose successful exit is the irreversible event, which
`references/default-action-conversion.md` rules out.

*Alternative: a background wait around the dispatch.* Starting `niwa dispatch`
in the background with a deadline and gating on its completion avoids the cap
but not the re-run hazard, and adds a process the workflow depends on.

### Decision 2: When the holding is written

**Chosen: write ahead, then launch, then confirm.** The script writes the
holding with dispatch status `dispatching` before it runs `niwa dispatch`, and
rewrites it as `dispatched` or `dispatch-failed` after.

*Alternative: write after the launch.* It records only real workers, but a
coordinator that dies between the launch and the write leaves the exact
invisible worker the feature exists to prevent.

*Alternative: write after, and have reconcile sweep `niwa list` for
unrecorded workers.* It moves the guarantee into reconcile, which is out of
scope, and a listing can't tell this coordinator's worker from another's.

The chosen order's failure is a `dispatching` row with no worker behind it.
The script's own re-run and reconcile both settle it by looking the topic up
in `niwa list --json`.

### Decision 3: How the dispatch gate knows the holding is there

**Chosen: a non-overridable command gate, `holding-recorded.sh`, that reads
the record through the record feature's reader** and exits 0 for a
`dispatched` holding, 1 for none, 3 for `dispatch-failed`, 2 when the record
can't be read.

*Alternative: a `context-exists` gate on a key the script writes.* The
coordinator can write the same key with `koto context add`, so the gate would
check a claim. The record is the thing the holding has to be on, so the gate
reads the record.

### Decision 4: How the wait state reads a leg chosen at run time

**Chosen: a selection script plus a two-state leg path.** `wait` runs
`wait-target.sh select`, which reads the holdings, checks each leg-bound one
with `koto request get`, prefers a resolved leg over an open one, writes the
choice to the context key `wait_target`, and captures its request id as
`WAIT_REQ`. `wait_leg` runs `wait-target.sh leg`, which captures the leg name
as `WAIT_LEG` from the same key, and carries the `request-leg` gate on
`{{WAIT_REQ}}` and `{{WAIT_LEG}}`. A `rescan` from `wait_leg` goes back
through `wait`, so a leg that resolves while another is being watched is
picked up on the next notification.

*Alternative: one request for the whole coordinator, one leg per worker.*
Legs are fixed at creation and named per skill, so a coordinator can't add a
worker's leg after the first dispatch and can't have two `deliver` legs.

*Alternative: four gates on `wait`, one per skill's leg name, all reading
`{{WAIT_REQ}}`.* Three of the four would report `missing` on every tick, and
the routing would have to pair each gate with the holding's entry point, which
the template can't see.

*Alternative: `koto request wait --resolved-count` in a background wait.* It
blocks on one request with a deadline, which is allowed, but it can't watch
several requests at once and it would move the result into a script's stdout
instead of a gate the engine evaluates.

### Decision 5: How the two return paths meet

**Chosen: both paths write one context key, `worker_report`,** and converge on
`take_report`. The leg path's transition writes it from the gate's output
(`status`, `final_state`, `outcome`, `step`, `reason`, and `payload.pr`),
which covers both the payload-carrying skills and `/work-on`'s map-less
terminals. On the message path the coordinator writes the message's text with
`koto context add`. A non-overridable `context-matches` gate requires the key
to be non-empty before `take_report` moves on.

*Alternative: separate classification states per path.* It would double the
decider declarations and split the shadow evidence for one question across
two declaration hashes.

This gate does check text the coordinator wrote, and that's deliberate: the
key holds the report itself, not a claim about the world. Whether the report
is true is the record feature's verify state's question, which reads GitHub.

### Decision 6: Where report classification lives

**Chosen: its own state, `classify_report`, with one declared field.**
`report_class` takes `done`, `blocked` or `needs_fix`, with a decider whose
input is the context key `worker_report` and whose answers are all `shadow`.
koto consults every declared field on a state at once and applies an answer
only when all qualify, so a state asking one question is the shape the decider
guide asks for.

*Alternative: declare the decider on `take_report`.* That state already has a
gate and would carry the report-received step and the classification in one
consultation.

### Decision 7: How teardown proves an instance holds nothing unique

**Chosen: a read-only inventory script, `teardown-inventory.sh`, run by the
teardown state's non-overridable gate,** which proves durability by content.
For each branch whose head is on no remote it diffs the head's tree, over
the paths the branch changed, against the squash merge commit of the pull
request that landed it, or against the default branch when none did.

*Alternative: ancestry (`git branch --no-merged`, `git log --not
--remotes`).* A squash merge makes every finished branch look unmerged, so
this reports finished work as unique and trains the coordinator to ignore the
report.

*Alternative: blob search (`git log --find-object`).* It proves a file's
content exists somewhere on the default branch's history, not that the
default branch holds it now, and it costs one history walk per file.

## Decision Outcome

The dispatch state stays one state whose work is one script and whose exit is
one gate that reads the record. The wait state becomes four states, `wait`,
`wait_leg`, `take_report` and `classify_report`, whose two entry paths meet
at a single report key, plus `rebrief` for a worker that needs a fix. Three
states are added at the end of a worker's life: `quiesce`, which stops the
worker's session, `teardown`, which gates on the inventory, and `destroy`,
which the gate opens. Every gate that routes on a fact is non-overridable and reads something
other than the coordinator's evidence: the record, a leg, or the instance.
The classification is recorded in shadow beside the coordinator's answer,
which routes.

The pieces reinforce each other. The write-ahead holding is what lets the
dispatch script be safe to re-run, because the row it finds tells it how far
an earlier run got. The return path recorded on that same row is what
`wait-target.sh` reads to decide whether a holding has a leg to watch, and
what stops a message from standing in for a leg the worker was bound to.

## Solution Architecture

### Components

All scripts live in `skills/coordinate/scripts/`, each with a `_test.sh`
sibling and fixtures under `skills/coordinate/scripts/testdata/`, on the model
of `skills/execute/scripts/`. They're reached from the template through the
declared `PLUGIN_ROOT` variable, never `${CLAUDE_PLUGIN_ROOT}`.

| Script | Run by | Does |
|---|---|---|
| `render-brief.sh` | `dispatch-worker.sh` | Validates the brief input and renders the brief; refuses and writes nothing on a missing field, an approval-worded checkpoint, a non-pointer pointer, or an argument the entry point doesn't allow |
| `dispatch-worker.sh` | the coordinator, in `dispatch` and `rebrief` | Idempotent dispatch under a per-topic lock: render, open the leg, write ahead, launch, confirm; `--rebrief` re-renders a held topic's brief and launches nothing |
| `holding-recorded.sh` | the `dispatch` gate | Reads the record's holding for the topic in `dispatch_topic`: 0 `dispatched`, 1 none, 3 `dispatch-failed`, 4 `dispatching`, 2 unreadable |
| `wait-target.sh` | the `wait` and `wait_leg` actions | Picks the holding to watch; always prints a token and writes `wait_target` |
| `report-source.sh` | the `take_report` gate | Refuses a message-path report for a topic whose holding is bound to a leg |
| `teardown-inventory.sh` | the `teardown` gate | Per-repository durability verdict for one instance |
| `dispatch-common.sh` | the scripts above | Workspace-root lookup, topic slugging, the entry-point table reader |

`skills/coordinate/references/entry-points.tsv` lists, per entry point, the
leg name and the template file the leg admits (or `-` when the skill doesn't
accept `--koto-leg`), the input keys to pin on the leg, and the flags the
entry point may be given. It holds legs for `scope` and `execute` today;
`deliver` and `work-on` gain theirs when #401 lands, as a data change.

### The brief input

The coordinator assembles one JSON object per dispatch and stores it with
`koto context add <session> brief_input.json --from-file <tmp>`, deleting the
temporary file after, per the repository's rule on koto-managed content.
Fields:

| Field | Required | Holds |
|---|---|---|
| `topic` | yes | the dispatch topic, `^[a-z0-9][a-z0-9-]*$`, equal to `dispatch_topic` |
| `repo` | yes | `owner/repo` |
| `entry_point` | yes | a skill named in `entry-points.tsv` |
| `entry_args` | yes | the entry point's positional argument and flags, each flag in that entry point's allowed set |
| `run_mode` | yes | the execution flags, `--auto` unless decided otherwise |
| `phase` | yes | `scoping-ahead` or `executing` |
| `authority` | yes | the authority sentence, in the human's voice |
| `goal` | yes | one or two sentences |
| `checkpoints` | yes, 1+ | the checkpoints, the last being where the worker stops |
| `decisions` | no | `{decision, by}` pairs |
| `read_first` | no | repository paths, `#n` / `owner/repo#n` references, or `https://` URLs |
| `acceptance` | yes, 1+ | acceptance criteria |
| `out_of_scope` | no | extra exclusions beyond the standing ones |
| `dispatcher_session` | yes | the coordinator's session name |
| `surfaces` | no | `{surface, coordinator}` pairs |
| `standing_rules` | no | the workspace's standing worker rules, copied verbatim |

The renderer writes the sections of `references/brief-template.md` in order,
adds the standing lines (the conventions pointer, the keep-alive note, closes
and issues reported rather than done, the work-in-flight block), and writes
the file to `<workspace-root>/.niwa/dispatch-briefs/<topic>.md`.

**Finding the workspace root.** A clone can carry a `.niwa/` directory of its
own, so the lookup never trusts the first marker it meets. It finds the
nearest ancestor holding `.niwa/instance.json` (the coordinator's instance)
and takes that directory's parent, which must hold `.niwa/workspace.toml`;
when no instance marker exists, the working directory itself must hold
`.niwa/workspace.toml`. Anything else is exit 2. The topic's pattern keeps the
brief's path inside the briefs directory.

### The dispatch script

`dispatch-worker.sh --session <koto-session> --plugin-root <dir>` reads
`dispatch_topic` and `brief_input.json` from the session's context, refuses
with exit 2 when their topics differ, takes an exclusive lock on
`<workspace-root>/.niwa/dispatch-briefs/<topic>.lock` held until it exits, and
runs:

1. **Look up the topic on the record** through the record feature's reader.
   `dispatched`: print `already-dispatched`, exit 0. `dispatch-failed`: exit 3,
   since a failed topic is re-dispatched under a new topic by the
   coordinator's choice. `dispatching`: an earlier run stopped partway; look
   for the topic's session in `niwa list --json`. Found: go to step 7 and
   confirm, reading the session name from the listing. Not found: go to step 6
   and launch, reusing the request recorded on the row.
2. **Refuse a topic a live session already uses** (exit 5), since koto session
   names are machine-wide. A topic's session is matched by its whole name,
   never by prefix: niwa's slug of the topic (each `-` becomes `_`), then `-`,
   then eight lowercase hexadecimal digits, as `^<slug>-[0-9a-f]{8}$`. So `api`
   (`^api-[0-9a-f]{8}$`) never matches `api-v2`'s session `api_v2-1a2b3c4d`.
   The format is niwa's today and is pinned by a test; a name outside it
   counts as no match, which fails toward launching and is caught by the
   record's `dispatching` row.
3. **Render the brief** with `render-brief.sh`. A refusal exits 1 with nothing
   written anywhere.
4. **Open the leg** when `entry-points.tsv` gives the entry point one:
   `koto request create --role <leg> --template <file> --inputs <json>
   --requested-by <dispatcher_session> --coordinator-of-record
   coordinate-<topic>`, pinning the listed inputs from the brief input. The
   return path is `<request-id>:<leg>`, and `--koto-leg=<request-id>:<leg>` is
   appended to the entry point's invocation in the prompt. Otherwise the
   return path is `message`.
5. **Write ahead**: add the holding through the record feature's writer with
   dispatch status `dispatching`, the topic, repository, entry point, run
   mode, phase, today's date, return path, and "none yet".
6. **Launch**: from the workspace root, `niwa dispatch "<prompt>" --name
   <topic> --detach` under a 300-second deadline, where the prompt is the
   authority, the repository, the entry point's invocation, the stop
   checkpoint, and the brief's path.
7. **Confirm**: on success, rewrite the holding as `dispatched` and print the
   session name niwa reported, which the coordinator uses to message the
   worker and never records. On a non-zero exit or the deadline, look for the
   topic's session in `niwa list --json` before concluding anything: found
   means the worker launched, so confirm it as `dispatched`; not found means
   it didn't, so rewrite the row `dispatch-failed`, abandon the request if one
   was opened (`koto request abandon-request`), and exit 4; a listing that
   can't be read leaves the row `dispatching` and exits 6, for the next run or
   reconcile to settle.

Exit codes: 0 dispatched or already dispatched, 1 brief refused, 2 usage,
mismatched topic, no workspace root or unreadable record, 3 topic already
failed, 4 launch failed, 5 topic in use by a live session, 6 launch outcome
unknown.

### The interface with the record feature

This feature fills two of the record feature's states and adds seven. It needs
the record feature to accept these seams, and its code lands only once that
feature's template carries them:

| Seam | What this feature needs |
|---|---|
| `pick -> dispatch` | the edge writes the context key `dispatch_topic` with `context_assignments`, fresh on every pass |
| `wait`'s exits | `wait` leaves to `wait_leg` and `take_report`, both added here |
| `classify_report`'s exits | `verify` on `done`, `dispatch` on `needs_fix`, and the record feature's surface step on `blocked` |
| unrecorded or refused legs | `wait_leg` leaves to the surface step directly |
| `land -> quiesce` | land's edge for a finished worker (merged, verified on the default branch, issues closed or handed on, final report in, the two questions asked) goes to `quiesce` instead of straight to `record`, and writes `teardown_topic` |
| `rebrief -> pick` | a unit whose worker is gone returns to `pick` with its holding |
| `destroy -> record` | `record` is where the holding row is dropped |
| holding row | add or replace one row whole, keyed by topic; read one row by topic |
| holding columns | *Phase* (`scoping-ahead` or `executing`), *Return path* (`<request-id>:<leg>` or `message`), and a dispatch status (`dispatching`, `dispatched`, `dispatch-failed`) the pull request column or a column of its own can carry |

The coordinator relayed the columns and the state list to the record feature
while this design was written; the names above are aligned when its
interface is published.

### Template states

States marked *filled* are the record feature's, whose directive and gates
this feature supplies. States marked *added* are new. Every gate listed is
declared `overridable: false`, and every evidence arm repeats its state's gate
fields so the arms are mutually exclusive, as koto's compiler requires.

| State | | Action | Gates | Leaves to |
|---|---|---|---|---|
| `dispatch` | filled | none (agent runs `dispatch-worker.sh`) | `holding_recorded`: command, `holding-recorded.sh` over `dispatch_topic` | `wait` on exit 0, clearing `worker_report` and `report_topic`; self-loop on exit 1 or 4 with evidence `retry` (re-run the script); `pick` on exit 3 with evidence `redispatch`; the surface step on any non-zero exit with evidence `escalate` |
| `wait` | filled | `wait-target.sh select`, capture `WAIT_REQ` (a request id, or `none`) | `leg_target`: `context-matches` on `wait_target` for a leg-bound pick | `wait_leg` when it matches; `take_report` on `matches: false` with evidence `report_from`, writing `report_topic` from it and `report_source: message` |
| `wait_leg` | added | `wait-target.sh leg`, capture `WAIT_LEG`; the script also writes `report_topic` from `wait_target` | `leg_result`: `request-leg` on `{{WAIT_REQ}}`/`{{WAIT_LEG}}` | `take_report` on a promoted resolved leg, writing `worker_report` from the gate's `status`, `final_state`, `outcome`, `step`, `reason` and `payload.pr`, and `report_source: leg`; the surface step on an explicit or refused result, an abandoned leg or a missing one; on an open leg, `wait` with evidence `rescan` (clearing `worker_report`), or `take_report` with evidence `report_from`, writing `report_topic` from it and `report_source: message` |
| `take_report` | added | none | `report_present`: `context-matches` on `worker_report` for a non-whitespace character; `report_source_ok`: command, `report-source.sh` over `report_topic` and `report_source` | `classify_report` when both pass; `wait` when `report_source_ok` refuses, clearing `worker_report` and `report_topic` |
| `classify_report` | added | none | none of its own; its decider input is gated by `report_present` | `verify` on `done`; `rebrief` on `needs_fix`; the surface step on `blocked` |
| `rebrief` | added | none (agent runs `dispatch-worker.sh --rebrief`) | none | `wait` on evidence `sent`, clearing `worker_report` and `report_topic`; `pick` on evidence `worker_gone` |
| `quiesce` | added | none | none | `teardown` on evidence `stopped` |
| `teardown` | added | none | `inventory_durable`: command, `teardown-inventory.sh` over `teardown_topic` | `destroy` on exit 0; self-loop on exit 1 with evidence `promoted`; the surface step on exit 2 with evidence `escalate` |
| `destroy` | added | none | none | `record` on evidence `destroyed` or `handed_over` |

**Why a message can't stand in for a leg.** `report_from` evidence on
`wait_leg` exists so a message from a message-path worker isn't stuck behind
another worker's open leg. Every route into `take_report` writes
`report_topic`, from the evidence on the message path and from `wait_target`
on the leg path, so `take_report`, `classify_report` and the record feature's
`verify` all know whose report they hold. `report-source.sh` reads that
topic's holding from the record: when its return path is a leg and the report
came by message, the gate refuses and the state goes back to `wait`, so the
leg is the only way that worker's result reaches `verify`. An unrecorded or refused leg goes to the surface step, never
to classification, so no route reaches `verify` for a leg-bound worker
without a promoted result.

**Why the keys are cleared.** `dispatch_topic` is written fresh on every
`pick -> dispatch` edge, so the dispatch gate never passes on the previous
topic's row. `worker_report` and `report_topic` are cleared on every edge
into `wait` (from `dispatch`, from a `rescan`, from `rebrief`, and from a
refused report), never on an edge into `take_report`, because on the message
path the coordinator writes the report before submitting `report_from`. So
`report_present` never passes on the previous round's text and never loses
this round's.

**The wait itself.** `wait-target.sh select` always prints a token and always
writes `wait_target`: a resolved leg if any holding has one, else the oldest
open leg, else `none`. With `none`, `leg_target` fails and the state stops for
evidence; that stop is the wait. The directive tells the coordinator to tick
the workflow on each message or harness notification: a message is submitted
as `report_from: <topic>` after its text is written to `worker_report`, and a
notification while `wait_leg` is on an open leg is submitted as `rescan`, so
a leg that resolved elsewhere is picked up. It never polls, and it checks a
quiet worker no more than once per 30 minutes, as the prose skill already
says.

The `classify_report` field:

```yaml
report_class:
  type: enum
  values: [done, blocked, needs_fix]
  required: true
  description: >-
    What did the worker report: finished work at its stop checkpoint, a block
    it can't clear, or work that needs a fix before it can be verified?
  decider:
    answers:
      done:      {description: "Reports its stop checkpoint reached, with a pull request or artifact named.", mode: shadow}
      blocked:   {description: "Reports it can't proceed without a decision, access or another unit's work.", mode: shadow}
      needs_fix: {description: "Reports failing checks, review findings or a defect in its own work it will fix.", mode: shadow}
    escape: {value: unclear, description: "The report is empty, truncated, or says none of these."}
    inputs:
      - {context: worker_report, label: report, max_bytes: 8192}
```

`report_present` is the `context-matches` gate the decider's `worker_report`
input needs, per koto's rule that a context input be checked by a context
gate in the template.

**Re-briefing after `needs_fix`.** `needs_fix` goes to `rebrief`, not back
through `dispatch`, because the worker already exists and holds the topic.
`dispatch-worker.sh --rebrief` reads `report_topic`, takes the repository,
entry point and flags from that topic's holding row rather than from the
report or the brief input, renders the new brief (the old one plus what was
learned) over the old file, and updates the row's date; it launches nothing.
The coordinator then sends the worker a message pointing at the brief and
submits `sent`. When the worker's session is gone, it submits `worker_gone`
and the unit goes back through `pick` under a new topic, as the prose skill's
failure branch says.

### The teardown inventory

Teardown starts at `quiesce`, whose directive has the coordinator stop the
worker's session by its id, through the harness's stop form that keeps the
session's job directory, and submit `stopped`. A gate runs when its state is
entered, so the stop has to happen in a state before the one that
inventories: nothing then writes to the instance between the inventory and the
destroy. `teardown`'s gate runs `teardown-inventory.sh --topic <teardown_topic>`, which finds the
worker's instance directory by the topic's whole session name in `niwa list
--json`, runs `git fetch --prune origin` once per repository so a remote
branch deleted without merging doesn't still look pushed, and for every git
repository and worktree under it:

1. `git status --porcelain`, including untracked files: any line is `unique`.
2. `git stash list`: any entry is `unique`.
3. Each local branch, and a detached HEAD in any worktree, whose head is on no
   remote branch. The paths it changed are `git diff --no-renames --name-only
   <merge-base>..<head>` against the default branch. The comparison target is
   the squash merge commit of the merged pull request whose head was that
   branch (`gh pr list --head <branch> --state merged --json mergeCommit`),
   fetched by sha; only when no merged pull request exists does it fall back
   to `origin/<default>`. Comparing against the merge commit keeps a later
   change to the same paths on the default branch from reading as unique
   work. An empty `git diff --no-renames <target> <head> -- <paths>` is
   `durable`, anything else `unique`, with the paths listed.
4. Anything it can't classify (a submodule, a bare repository, a nested
   `.git` it didn't enter, a repository it can't read) is an error, never
   `durable`.

It prints one line per repository, `durable <path> (vs <target>)` or
`unique <path>: <why> (vs <target>)`, with every path relative to the
instance and the target named (`merge <sha>` or `default <branch>`), and exits
0 when all are durable, 1 when any is unique, 2 on an error. Its only writes
are the remote-tracking refs the fetch updates; it destroys nothing.

On exit 1 the coordinator promotes anything load-bearing into an issue
comment or a pull request and submits `promoted`, and the gate runs again.
On exit 0 the workflow moves to `destroy`, whose directive names `niwa
destroy <instance>` for that one instance, with `--force` only because of
niwa#322 and only because the gate just passed, never `niwa reap` or any form
that takes no target. Each finishing step goes as far as the workspace's
declared permissions allow and is handed to the human where they don't,
answered with `handed_over`.

### Data flow

```
pick --(dispatch_topic)--> dispatch --(dispatch-worker.sh: lock, write-ahead,
          niwa dispatch, confirm; holding_recorded reads the record)
          v
        wait --(wait-target.sh select)--> wait_leg --(request-leg, promoted)--+
          |   ^--------------(rescan)--------+                                 |
          +--(report_from + worker_report)-----------------------------------+-> take_report
                                                     (report_present, report_source_ok)
                                                                               v
                                                     classify_report (shadow decider)
                                                       done -> verify
                                                       needs_fix -> rebrief -> wait
                                                       blocked -> surface
        land --(teardown_topic)--> quiesce --(stopped)--> teardown --(inventory_durable)--> destroy --> record
```

### Tool declaration

`skills/coordinate/requires.tsv` adds `niwa - - always`, and
`scripts/lib/tool-routes.tsv` adds `niwa tsuku any tsuku tsuku-info tsuku
install niwa@latest && . ~/.tsuku/env -`, the same route koto and shirabe
use; `tsuku info niwa` resolves. `koto` is declared at the floor the template
needs (request-leg gates, captures, and decider declarations: 0.13.0), which
the record feature's declaration may already carry.

## Implementation Approach

This feature's code lands after the record feature's template is on the
default branch and carries the seams listed under "The interface with the
record feature", since it fills that template's states.

1. **Brief rendering.** `dispatch-common.sh` and `render-brief.sh` with tests:
   complete input, each refusal, standing rules copied verbatim, the
   workspace-root lookup.
2. **Dispatch and holding.** `entry-points.tsv`, `dispatch-worker.sh` and
   `holding-recorded.sh` with tests against a stub `niwa`, a stub `koto
   request`, and a stub record writer and reader that log their calls to one
   file, covering the write-ahead order, idempotence, the failed launch and
   the crash-mid-dispatch recovery, the lock against a concurrent run, the
   exact session-name match, and a launch that times out after starting the
   worker. The `dispatch` state's directive and gate.
   The `requires.tsv` and `tool-routes.tsv` entries.
3. **The wait path.** `wait-target.sh` and `report-source.sh` with tests; the
   `wait`, `wait_leg`, `take_report`, `classify_report` and `rebrief` states,
   and the `--rebrief` mode; template compile and the
   repository's template checks.
4. **Teardown.** `teardown-inventory.sh` with tests over fixture repositories
   built in the test (a squash-merged branch whose paths the default branch
   later changed, an unpushed change, a stash, a worktree on a detached HEAD, a
   remote branch deleted without merging, a submodule); the `quiesce`,
   `teardown` and `destroy` states.
5. **Skill text and evals.** The thin SKILL.md's pointers to the new states,
   Known Limitations, and evals for a brief rendered with both channels, a
   dispatch refused to leave the state without a holding, and a report
   classified in shadow.

## Security Considerations

**Paths built from input.** The topic is the only input that reaches a path
(the brief file and its lock) or a koto name. It's checked against
`^[a-z0-9][a-z0-9-]*$` in `render-brief.sh` before any path is built, which
rules out traversal and leading dashes. The workspace root is found from the
coordinator's own instance marker and its parent, never from the first
`.niwa/` directory a walk meets, since a cloned repository can carry one.

**Arguments never reach a shell as text.** The brief input is JSON read with
`jq`; values are passed to `niwa`, `koto`, `gh` and `git` as separate
arguments, never interpolated into a `sh -c` string. The dispatch prompt is
one argument. `entry_args` is split into a positional argument and flags, and
each flag must be in the entry point's allowed set in `entry-points.tsv`, so a
brief can't hand a worker a flag its entry point doesn't document.

**Worker reports are untrusted text.** A report can say anything, including
text written to steer whoever reads it. It reaches the workflow only as the
`worker_report` context key, drives no gate but the non-empty check, and is
classified by the coordinator with the decider in shadow. It can't redirect a
re-dispatch: the repository, entry point and flags of a `needs_fix`
re-dispatch come from the holding row, not from the report. Because it's
externally authored text, it's a weak candidate for ever promoting the decider
to `auto`, and the design says so for whoever considers promotion.

**What the decider sends out.** koto's deciders are off unless a user opts in;
for a user who has, `worker_report` goes to the decider's provider, up to its
8 KB budget. The directive tells the coordinator to write the worker's report,
not logs it quotes, into the key. No redaction step is added: a report is
already a message sent between sessions, and a scrubber tuned for secrets
would give a false assurance the rest of the loop doesn't rely on. The risk is
accepted for opted-in users and stated here.

**Gates read facts, not claims.** `holding_recorded` reads the record on
GitHub, `leg_result` reads a leg whose result only the bound session's
terminal tick can promote, `report_source_ok` reads the reporting topic's
return path from the record, and `inventory_durable` reads the instance's
repositories. A coordinator could still write a holding row by hand; the gate
would pass, and reconcile's `niwa list` read is what catches a row with no
worker behind it. That residual is accepted: the gate's job is to stop an
omission, and a forged row is not an omission.

**Destruction is targeted, quiesced and read-before-write.** The worker's
session is stopped in `quiesce`, a state before the inventory's, so nothing
writes to the instance between the verdict and the destroy. `stopped` is the
coordinator's evidence, not a fact the gate reads; the ordering is what the
state split guarantees. The inventory is read-only apart
from remote-tracking refs, treats anything it can't classify as an error, and
never reports it durable. The destroy names one instance found by the topic's
whole session name, never a sweep, and `--force` is tied to a passing
inventory. Stopping a session uses the harness's stop form by id, never a form
that deletes its job directory.

**Public record.** The holding carries a topic, repository, entry point,
flags, phase, date and a koto request id, and never a session id, instance
path or job id. Inventory lines are relative to the instance, so promoting one
into an issue comment names no host path. A roadmap record in a public
repository names no private repository, path or issue.

## Consequences

**Positive.** A dispatched worker is on the record before anything else can
happen, and a restart finds it. Every brief carries the same sections and both
channels. The coordinator's workflow advances the same way on a leg and on a
message, and each report's classification is recorded with a suggestion
beside it. Teardown can't destroy unique work silently, and squash-merged work
no longer reads as unique.

**Negative.** The dispatch state depends on the coordinator running the
script; a coordinator that launches a worker by hand and writes the row by
hand passes the gate. The wait path adds three states to the record feature's
template. A `dispatching` row whose launch never happened sits on the record
until the script re-runs or reconcile clears it. Until #401 lands, most
workers use the message path. Until koto#250 lands, a resolved leg is read
only when a message or notification makes the coordinator tick.

**Mitigations.** Reconcile, the next feature, checks every holding against
`niwa list`. The leg table grows by data when #401 lands. The wait directive's
quiet-worker check bounds how long a resolved leg can go unread.

### Known limitations

- **#395, PR ownership by login and branch name.** Every worker shares the
  coordinator's login, so two workers whose branches collide can adopt each
  other's pull request. Topics feed branch names; one topic per worker keeps
  them apart.
- **#396, the merge-order block.** A worker running a coordinated PLAN leaves
  it empty; the coordinator can't read merge order from it later.
- **#398, scoping pull request bodies.** Not conformant two-part bodies, so a
  report that points at one gives the coordinator less structure.
- **#401, `--koto-leg` on `/deliver` and `/work-on`.** Until it lands, only
  `/scope` and `/execute` workers use the leg path.
- **koto#250, no wake on a resolved leg.** The coordinator reads a resolved
  leg on its next tick, which a message, a notification, or the quiet-worker
  check triggers.
- **niwa#322, destroy refuses squash-merged branches.** `--force` is needed
  and is passed only after the inventory proves durability.
- **One topic per worker.** koto session names are machine-wide, so a second
  worker on a live topic is refused as an origin mismatch;
  `dispatch-worker.sh` refuses the topic first.
- **Session names aren't predictable.** niwa appends a random token to
  `--name`, so the coordinator reads the name from the dispatch output or
  `niwa list --json` and never derives it.
