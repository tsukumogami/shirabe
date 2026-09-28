---
schema: design/v1
status: Current
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
  state is a hub that routes to a request-leg path, whose leg a script picks,
  and a message path, and both land the report in one context key, which a
  classification state reads through a shadow decider. A sealed inventory
  state gates destruction on a content-based inventory of the worker's
  instance.
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

Current

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
  answers only a leg named `scope`, `/execute` only `execute`, `/deliver` only
  `deliver` and `/work-on` only `work-on` (the last two since #407, which fixed
  #401; `/work-on` answers its leg only for an issue or a task). A root
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
  states and gates and fills the ones it was handed (dispatch, wait,
  classify_report, rebrief and teardown), without restructuring.
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
`dispatched` holding, 1 for none, 3 for `dispatch-failed`, 4 for a
`dispatching` row an interrupted run left, 2 when the record can't be read.

*Alternative: a `context-exists` gate on a key the script writes.* The
coordinator can write the same key with `koto context add`, so the gate would
check a claim. The record is the thing the holding has to be on, so the gate
reads the record.

### Decision 4: How the wait state reads a leg chosen at run time

**Chosen: a selection script plus a two-state leg path.** `wait` is a hub
with no action; a `leg` event takes it to `leg_pick`, which runs
`wait-target.sh select`. The script reads the holdings, checks each leg-bound
one with `koto request get`, prefers a resolved leg over an open one, writes
the choice to the context key `wait_target`, and captures its request id as
`WAIT_REQ`. `wait_leg` runs `wait-target.sh leg`, which captures the leg name
as `WAIT_LEG` from the same key, and carries the `request-leg` gate on
`{{WAIT_REQ}}` and `{{WAIT_LEG}}`. A `rescan` from `wait_leg` goes back
through `leg_pick`, so a leg that resolves while another is being watched is
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
terminals. On the message path the coordinator submits the message on
`wait`'s `report` event, and that edge writes its text to the key. A
non-overridable `context-matches` gate requires the key to be non-empty
before `take_report` moves on.

*Alternative: separate classification states per path.* It would double the
decider declarations and split the shadow evidence for one question across
two declaration hashes.

This gate does check text the coordinator wrote, and that's deliberate: the
key holds the report itself, not a claim about the world. Whether the report
is true is the record feature's verify state's question, which reads GitHub.

### Decision 6: Where report classification lives

**Chosen: its own state, `classify_report`, with one declared field.**
`classification` takes `done`, `blocked` or `needs_fix`, with a decider whose
inputs are the record feature's `coord/report.json` and the context key
`worker_report`, and whose answers are all `shadow`.
koto consults every declared field on a state at once and applies an answer
only when all qualify, so a state asking one question is the shape the decider
guide asks for.

*Alternative: declare the decider on `take_report`.* That state already has a
gate and would carry the report-received step and the classification in one
consultation.

### Decision 7: How teardown proves an instance holds nothing unique

**Chosen: a read-only inventory script, `teardown-inventory.sh`, run by the
inventory state's action and read by its non-overridable gate,** which proves
durability by content.
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
one gate that reads the record. The wait path is `wait`, a hub that routes
on the event the coordinator names, plus `leg_pick`, `wait_leg`,
`take_report` and `classify_report`, whose two entry paths meet at a single
report key, and `rebrief` for a worker that needs a fix. Four states cover
the end of a worker's life: `teardown`, which stops the worker's session,
`teardown_inventory`, which gates on the sealed inventory, and `destroy`,
which that inventory opens, with `promote` between them when the instance
still holds something. The record feature's template already names the step
that stops a worker `teardown`, so that state keeps the name and the sealed
inventory is `teardown_inventory`. Every gate that routes on a fact is non-overridable and reads something
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

All scripts live in `skills/coordinate/scripts/`, each covered by a `_test.sh`
suite that builds its fixtures and stand-ins itself (a gate script shares the
suite of the script that writes what it reads: `holding-recorded.sh` in
`dispatch-worker_test.sh`, `report-source.sh` in `wait-target_test.sh`,
`teardown-verdict.sh` in `teardown-inventory_test.sh`), on the model of
`skills/execute/scripts/`. They're reached from the template through the
declared `PLUGIN_ROOT` variable, never `${CLAUDE_PLUGIN_ROOT}`.

| Script | Run by | Does |
|---|---|---|
| `render-brief.sh` | `dispatch-worker.sh` | Validates the brief input and renders the brief; refuses and writes nothing on a missing field, an approval-worded checkpoint, a non-pointer pointer, or an argument the entry point doesn't allow |
| `dispatch-worker.sh` | the coordinator, in `dispatch` and `rebrief` | Idempotent dispatch under a per-topic lock: render, open the leg, write ahead, launch, confirm; `--rebrief` re-renders a held topic's brief and launches nothing |
| `holding-recorded.sh` | the `dispatch` gate | Reads the record's holding for the topic in `dispatch_topic`: 0 `dispatched`, 1 none, 3 `dispatch-failed`, 4 `dispatching`, 2 the record unreadable or refusing the read |
| `wait-target.sh` | the `leg_pick` and `wait_leg` actions | Picks the holding to watch; always prints a token and writes `wait_target` |
| `report-source.sh` | the `take_report` gate | Refuses a message report for a topic with no holding or whose holding is bound to a leg (exit 1, back to the hub), and a leg report with no holding, from a leg other than the recorded one, or that isn't exactly the promoted result koto holds for the leg (exit 3, to the human) |
| `teardown-inventory.sh` | the `teardown_inventory` action (`--seal`) | Per-repository durability verdict for one instance, sealed through the record feature's seal helper |
| `teardown-verdict.sh` | the `teardown_inventory` gate, and `destroy`'s directive | Reads the sealed verdict only through the seal check; its read mode refuses after a directed transition |
| `dispatch-common.sh` | the scripts above | Workspace-root lookup, topic slugging and the exact session match, the entry-point table reader, the one invocation builder, and the wrappers around the record feature's `record-holding.sh` and `coord-log.sh` |

`skills/coordinate/references/entry-points.tsv` lists, per entry point, the
leg name and the template file the leg admits (or `-` when the skill doesn't
accept `--koto-leg`), the input keys to pin on the leg, and the flags the
entry point may be given. It holds legs for `scope`, `execute`, `deliver` and `work-on`;
the last two came as a data change once #407 fixed #401. Because `/work-on`
answers its leg only for an issue or a task, `dispatch-worker.sh` opens no leg
for a `/work-on` worker given a PLAN path, which reports by message.

### The brief input

The coordinator assembles one JSON object per dispatch and stores it with
`koto context add <session> brief_input.json --from-file <tmp>`, deleting the
temporary file after, per the repository's rule on koto-managed content.
Fields:

| Field | Required | Holds |
|---|---|---|
| `topic` | yes | the dispatch topic, `^[a-z0-9][a-z0-9-]*$`, equal to `dispatch_topic` |
| `repo` | yes | `owner/repo` |
| `unit` | yes | the unit of work, one line, as the holding's Unit cell names it |
| `entry_point` | yes | a skill named in `entry-points.tsv` |
| `entry_args` | yes | a JSON array of tokens: the positional argument first, then flags, each in that entry point's allowed set; none given twice, never `--auto` with `--interactive`, and a positional carrying no quote, backtick, dollar sign or backslash |
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

**Finding the workspace root.** niwa exposes no workspace root to a process
(niwa#326), and a clone can carry a `.niwa/` directory of its own, so the
lookup never trusts the first marker it meets. It finds the nearest ancestor
holding `.niwa/instance.json`. A niwa workspace root carries that file too, so
when the same directory also holds `.niwa/workspace.toml` it is the root;
otherwise it's the coordinator's instance and its parent must hold
`.niwa/workspace.toml`. When no instance marker exists, the working directory
itself must hold `.niwa/workspace.toml`. Anything else is exit 2. The topic's pattern keeps the
brief's path inside the briefs directory.

### The dispatch script

`dispatch-worker.sh --session <koto-session>` reads
`dispatch_topic` and `brief_input.json` from the session's context, refuses
with exit 2 when their topics differ, takes an exclusive lock on
`<workspace-root>/.niwa/dispatch-briefs/.<topic>.lock` held until it exits (a
directory created atomically, taken over when its owner's pid is gone, since
`flock` isn't on macOS), and runs:

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
3. **Check the brief input** with `render-brief.sh`. A refusal exits 1 with
   nothing written anywhere. The brief is written after step 4, so it shows the
   same invocation, `--koto-leg` included, as the prompt; `dc_invocation` builds
   that invocation once for the brief, the prompt and the holding's mode.
4. **Open the leg** when `entry-points.tsv` gives the entry point one: first
   abandon any open request under `coordinate-<topic>` (`koto request list
   --coordinator-of-record ... --state open`), which only a run that died
   before writing its holding can have left, then `koto request create
   --with-data '{"legs":[{name, role, template, inputs}]}' --requested-by
   <dispatcher_session> --coordinator-of-record coordinate-<topic>`, the leg
   named for the skill, admitting its templates and pinning the listed
   inputs. The
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
unknown, 7 another run holds the topic's lock, 8 the record refused the write
(no open record, or a directed transition in the run log).

niwa doesn't yet report the launched session machine-readably (niwa#325), so
the session name comes from the `session name:` line of its output, or from
`niwa list --json`'s `session_name`.

### The interface with the record feature

This feature fills five of the record feature's states and adds six. It needs
the record feature to accept these seams, and its code lands only once that
feature's template carries them:

| Seam | What this feature needs |
|---|---|
| `pick -> dispatch_check -> dispatch` | the pick edge writes the context key `dispatch_topic`, fresh on every pass, and the record feature's deferral gate `dispatch_check` passes it through to `dispatch` |
| `wait`'s exits | `wait`'s `report` event leaves to `take_report` and its `leg` event to `leg_pick`, both added here; its other events go to the record feature's states |
| `take_report -> report_facts -> classify_report` | an admitted report passes through the record feature's `report_facts`, which reads the reporting holding and writes the gated `coord/report.json`, before it's classified. `report-facts.sh` finds the reporting worker from the log: the hub's `unit` for a message report, and for a leg report the holding whose Return path is `leg <WAIT_REQ>:<WAIT_LEG>`, from leg_pick's and wait_leg's captures. That leg-path read is on the record feature's branch (#408) and isn't in the copy of it merged here |
| `classify_report`'s exits | `verify` on `done`, `rebrief` on `needs_fix`, and the record feature's surface step on `blocked` |
| unrecorded or refused legs | `wait_leg` leaves to the surface step directly |
| `wait -> teardown` | `wait`'s `retire` event goes to `teardown` and writes `teardown_topic` from its `unit`; `teardown`'s directive holds the finish check (merged, verified on the default branch, issues closed or handed on, final report in, the two questions asked). There's no edge from `land` |
| `rebrief -> pick_facts` | a unit whose worker is gone returns through `pick_facts` with its holding |
| `destroy -> record` | `record` is where the holding row is dropped |
| holding rows | `record-holding.sh --session <s>` with `--topic <t> --row-file <json>` (add or replace one row whole), `--read --topic <t>` (one row), or `--list` (every row, in record order); it derives the record itself from the session's log. Exit 0, 1 no row (`--read` only), 2 read failed, 10 refused (no open record, failed provenance, or a directed transition in the run), 11 write failed, 64 usage, 65 row refused |
| holding row keys | `unit`, `entry_point`, `mode`, `phase` (`scoping-ahead` or `executing`), `dispatch_status` (`dispatching`, `dispatched`, `dispatch-failed`), `return_path` (`<request-id>:<leg>` or `message`), `worker`, `repo`, `branch` (empty until known: written in the same write that records the pull request), `verified_head`, `dispatched`, `pull_request` |
| seals | `coord-log.sh seal --session <s> --state <state> --file <f> --key <k>` stores a verdict and prints `sealed:<seq>:<sha256>` (0 sealed, 2 no readable log or no entry into the state, 66 the context write failed); `check --session <s> --state <state> --sealed <t> --key <k>` prints the verified bytes (0 valid, 1 invalid, 2 read failure); `capture --session <s> --name <n>` reads a capture from the log (0 found, 1 absent, 2 read failure); `directed-since --session <s> --from <seq>` reports directed transitions (0 none, 1 some, 2 read failure); 64 usage throughout |
| `classify_report` | the record feature declares it, with the decider on `coord/report.json` and `worker_report`; this feature adds the routes and the gate on `worker_report` |
| `rebrief`, `teardown` | the record feature declares them; this feature fills them |

The record feature confirmed each interface above; this feature's scripts
reach it only through the wrappers in `dispatch-common.sh`, so a later change
is one edit there.

### Template states

States marked *filled* are the record feature's, whose directive and gates
this feature supplies. States marked *added* are new. Every gate listed is
declared `overridable: false`, and every evidence arm repeats its state's gate
fields so the arms are mutually exclusive, as koto's compiler requires.

| State | | Action | Gates | Leaves to |
|---|---|---|---|---|
| `dispatch` | filled | none (agent runs `dispatch-worker.sh`) | `holding_recorded`: command, `holding-recorded.sh`, which reads `dispatch_topic` itself | `record` on evidence `sent`, only when the gate exits 0; the record feature's `failure` on evidence `failed`, which the directive has the coordinator submit when the script exits 3 or 4 |
| `wait` | filled | none | none | a hub that stops for evidence: `event` (`report`, `leg`, `quiet`, `decision`, `deferral`, `merged`, `retire`, `end`), with `unit` and, for a report, `report`. `take_report` on `report`, writing `worker_report` from `report`, `report_topic` from `unit`, and `report_source: message`; `leg_pick` on `leg`; `teardown` on `retire`, writing `teardown_topic` from `unit`; the other events go to the record feature's states |
| `leg_pick` | added | `wait-target.sh select`, capture `WAIT_REQ` (a request id, or `none`) | `leg_target`: `context-matches` on `wait_target` for a leg-bound pick | `wait_leg` when it matches; `wait` when it doesn't, clearing `worker_report` and `report_topic` |
| `wait_leg` | added | `wait-target.sh leg`, capture `WAIT_LEG`; the script also writes `report_topic` from `wait_target` | `leg_result`: `request-leg` on `{{WAIT_REQ}}`/`{{WAIT_LEG}}` | `take_report` on a promoted resolved leg, writing `worker_report` from `${gates.leg_result.status}`, `final_state`, `payload.outcome`, `payload.step`, `payload.reason` and `payload.pr`, and `report_source: leg`; the surface step on an explicit or refused result, an abandoned leg or a missing one. Every one of those consuming edges sets `leg_consumed: "yes"`. On an open leg, `leg_pick` on evidence `watch: rescan`, or `wait` on `watch: back`, clearing `worker_report` and `report_topic` |
| `take_report` | added | none | `report_present`: `context-matches` on `worker_report` for `\S`; `report_source_ok`: command, `report-source.sh` over `report_topic` and `report_source` | the record feature's `report_facts`, then `classify_report`, when `report_source_ok` exits 0 and `report_present` matches; `wait` when `report_source_ok` exits 1; `wait` on evidence `withdrawn` when it exits 0 and there's no text, or when it exits 2 (the record can't be read, as for a report that names no worker); the surface step when it exits 3 (a refused leg report: no holding for the topic, a leg other than the one the record names, or text that isn't the promoted result koto holds for the leg; the leg is spent and would never come back to the hub). Every edge back to `wait` clears `worker_report` and `report_topic`; the edge to the surface step clears `worker_report` and keeps `report_topic`, so the human is told which worker's leg it was |
| `classify_report` | filled | none | none of its own; its decider inputs are gated by `report_facts`'s `report_input` and by `report_present` | `verify` on `done`; `rebrief` on `needs_fix`; the surface step on `blocked` |
| `rebrief` | filled | none (agent runs `dispatch-worker.sh --rebrief`) | none | `wait` on evidence `sent`, clearing `worker_report` and `report_topic`; `pick_facts` on evidence `worker_gone` |
| `teardown` | filled | none | none | `teardown_inventory` on evidence `stopped`; `record` on evidence `kept`, the worker staying, clearing `teardown_topic` |
| `teardown_inventory` | added | `teardown-inventory.sh --seal`, which reads `teardown_topic` itself; non-polling, capture `TEARDOWN_SEAL` | `inventory_durable`: command, `teardown-verdict.sh gate`, which checks the stored verdict against the seal it reads from the log, and that the verdict covers the current `teardown_topic` | `destroy` when the sealed verdict is durable (exit 0); `promote` when it's unique (exit 1); the surface step on an error verdict or a seal that doesn't hold (exit 2 or 3), clearing `teardown_topic`. No `accepts` block: the state moves on gates alone |
| `promote` | added | none | none | `teardown_inventory` on evidence `promoted` (re-entering runs the inventory again); the surface step on evidence `escalate`, clearing `teardown_topic` |
| `destroy` | added | none | none | `record` on evidence `destroyed` or `handed_over`; the surface step on evidence `refused`. All three clear `teardown_topic` |

**Why a message can't stand in for a leg.** Every route into `take_report`
writes `report_topic`, from `wait`'s `unit` on the message path and from
`wait_target` on the leg path, so `take_report`, `classify_report` and the
record feature's `verify` all know whose report they hold. `report-source.sh`
reads that topic's holding from the record. A message report is admitted only
when the holding's return path is `message`; for a leg-bound worker the gate
refuses and the state goes back to `wait`. A leg report is admitted only when
the holding's return path is the leg `wait_target` names, and only when
koto's own record of that leg (`koto request get`) shows it resolved with
`result_source` `promoted` and `worker_report` equals exactly the text built
from that result. The context keys say which leg; they can't say what the leg
holds, since anyone in the session can rewrite them with `koto context add`,
so rewriting them can't pass a report off as a leg result. An unrecorded or
refused leg goes to the surface step, never to classification, so no route
reaches `verify` for a leg-bound worker without a promoted result.

**Why the keys are cleared.** `dispatch_topic` is written fresh on every
`pick -> dispatch` edge, so the dispatch gate never passes on the previous
topic's row. Every edge into `take_report` writes `worker_report`,
`report_topic` and `report_source` fresh, and the dispatch path's edges back
into `wait` (from `take_report`, from `leg_pick`, from `wait_leg`'s `back`,
and from `rebrief`'s `sent`) clear `worker_report` and `report_topic`. So
`report_present` never passes on the previous round's text and never loses
this round's. `teardown_topic` is written only by `wait`'s `retire` edge and
cleared on every edge that leaves the teardown states (`teardown`'s `kept`,
`teardown_inventory` to the surface step, `promote`'s `escalate`, and every
`destroy` edge), so a later entry can't inventory or destroy a worker an
earlier retire named.

**A leg is read once.** A leg's result can't change after it resolves, and a
holding keeps naming its leg until the record drops the row, so the leg whose
result `wait_leg` takes is kept in the context key `taken_legs` and never
picked again; otherwise a report routed to `rebrief` or the surface step
would bring the same result back on the next pass. `wait-target.sh leg` marks
a leg taken when it's no longer open, but an evidence tick at `wait_leg`
doesn't run the action, so a leg that resolved between two ticks could be
consumed unmarked. Every consuming edge therefore sets `leg_consumed`, and the
next `wait-target.sh select` marks the previously picked leg taken from that
marker and clears it. A re-briefed worker reports by message: `--rebrief`
moves its holding to the message path and abandons the spent request.

**The wait itself.** `wait` has no action and no gate, so it stops for
evidence; that stop is the wait. The directive tells the coordinator to tick
the workflow on each message or harness notification and name the event: a
worker's message is submitted as `event: report` with its topic as `unit` and
the message itself as `report`, and a notification that a leg may have
resolved is submitted as `event: leg`. Whenever it can read the record,
`wait-target.sh select` in `leg_pick` prints a token and writes
`wait_target`: a leg with a result waiting if any untaken one has, else the
oldest open leg, else `none`. With `none`, `leg_target` fails and the
workflow goes back to `wait`. On an open leg, a later notification is
submitted as `watch: rescan`, so a leg that resolved elsewhere is picked up,
and a message that arrives meanwhile goes `watch: back` to `wait`, where it's
submitted as a report event. It never polls, and it checks a quiet worker no
more than once per 30 minutes, as the prose skill already says.

The `classify_report` field:

```yaml
classification:
  type: enum
  values: [done, blocked, needs_fix]
  required: true
  description: What does this worker's report mean?
  decider:
    answers:
      done: {description: "The worker says its unit is finished and its pull request is ready to verify."}
      blocked: {description: "The worker can't go on without a decision or a step that isn't its to take."}
      needs_fix: {description: "The work has a problem the worker can fix with what was learned."}
    escape: {value: unclear, description: "The report is missing, truncated, or ambiguous."}
    inputs:
      - {context: coord/report.json, label: report_facts, max_bytes: 12000}
      - {context: worker_report, label: worker_report, max_bytes: 8192}
```

No answer declares a `mode`, and koto records an answer with no declared mode
as `shadow`. `report_present` is the `context-matches` gate the decider's
`worker_report` input needs, per koto's rule that a context input be checked
by a context gate in the template; the record feature's `report_input` gate
checks `coord/report.json`.

**Re-briefing after `needs_fix`.** `needs_fix` goes to `rebrief`, not back
through `dispatch`, because the worker already exists and holds the topic.
`dispatch-worker.sh --rebrief` reads `report_topic`, takes the repository,
entry point and flags from that topic's holding row rather than from the
report or the brief input, renders the new brief (the old one plus what was
learned) over the old file, and updates the row's date; it launches nothing.
The coordinator then sends the worker a message pointing at the brief and
submits `sent`. When the worker's session is gone, it submits `worker_gone`
and the unit goes back through `pick_facts` and `pick` under a new topic, as the prose skill's
failure branch says.

### The teardown inventory

Teardown starts when the coordinator submits `event: retire` on `wait` with
the worker's topic as `unit`; that edge writes `teardown_topic` and enters
`teardown`. Its directive has the coordinator check the worker is finished,
ask it the two questions, stop the worker's session by its id, through the
harness's stop form that keeps the session's job directory, and submit
`stopped`, or `kept` when the worker stays, which goes to `record`. A gate
runs when its state is entered, so the stop has to happen in a state before
the one that inventories: nothing then writes to the instance between the
inventory and the destroy. `teardown_inventory`'s action runs
`teardown-inventory.sh --seal`, which reads `teardown_topic`, finds the
worker's instance directory by the topic's whole session name in `niwa list
--json`, and reads every clone under it without running anything the clone
could have configured. It never runs `git status` or `git fetch` in a clone:
status runs clean and process filters, so a worker's filter can make a change
vanish from it, and recurses into submodules with their own config; a fetch
runs the clone's URL rewrites, transports and credential helpers. It reads
plumbing (`ls-files`, `ls-tree`, `rev-list`, `cat-file`, `merge-base`,
`diff-tree`, `reflog`) with fsmonitor, hooks, the pager, signature
verification (which runs the clone's `gpg.program`) and every transport off,
hashes the
working tree's files itself with `hash-object --no-filters --stdin-paths`,
reads origin's live refs with `ls-remote` against the github.com URL under
the coordinator's own git config, and reads the trees it compares against
from GitHub, one read per commit. For every clone:

1. Staged, uncommitted, deleted and untracked changes, from the index, HEAD's
   tree and the working tree's own bytes, so a skip-worktree or
   assume-unchanged entry hides nothing: any is `unique`.
2. A stash: `unique`.
3. Each local branch, local tag and detached HEAD with a commit on none of
   origin's live refs, and each origin tracking ref whose branch is gone from
   origin and that this clone pushed (its reflog says so), since that ref can
   be the only thing holding a commit; any other tracking ref is someone
   else's branch as last fetched and isn't the worker's. That rule depends
   on the ref's log. A ref `git clone` created has no log file, which is
   normal and reads as not pushed; counting it would count every bystander
   branch deleted since the clone. (Measured on git 2.43: `git clone` writes
   origin's tracking refs to packed-refs with no log, even with ref logging
   on. That is why "an empty log means pushed", the obvious fix for a
   missing log, is wrong.) A gone-from-origin ref whose log exists
   but reads empty (expired or unreadable), or any such ref in a clone with
   ref logging turned off, is an error rather than a guess. What remains
   open reads as not pushed: a log file deleted by hand, a log that lost
   only its push entry to partial expiry, or ref logging turned off for the
   push and back on before the teardown. The empty-versus-missing
   distinction was measured on the files ref backend; the reftable backend
   (git 2.45 and later) hasn't been checked. A push to a remote other than origin, or by
   URL, leaves no origin tracking ref: a local branch still reads unique
   against origin, so the gap opens only when a worker pushed elsewhere and
   then deleted its local branch, which is outside what the inventory can
   prove. The paths it changed are the `diff-tree --no-renames`
   paths from its merge base with the default branch. The comparison target
   is the squash merge commit of the merged pull request whose head was that
   branch (`gh pr list --head <branch> --state merged --json mergeCommit`),
   and the default branch's head only when no merged pull request exists.
   Comparing against the merge commit keeps a later change to the same paths
   on the default branch from reading as unique work. Each path whose blob at
   the tip matches the target's tree is `durable`; any other is `unique`, with
   the paths listed.
4. Submodules, clones nested in the working tree (an ignored directory
   included) and linked worktrees inside the instance are inventoried as
   clones of their own. Anything it can't classify (a bare repository, a
   repository it can't read or whose git directory is outside the instance,
   a clone with no github.com origin, a lookup that fails or times out) is an
   error, never `durable`.

A content filter (LFS, a line-ending conversion) makes the working tree's
bytes differ from the index, so such a clone reads as unique: the safe
direction, at the cost of a promote step. The read follows the one the
reconcile feature's host checks use, and the two can share it once both land.

It prints one line per repository, `durable <path> (vs <target>)` or
`unique <path>: <why> (vs <target>)`, with every path relative to the
instance and the target named (`merge <sha>` or `default <branch>`), and exits
0 when all are durable, 1 when any is unique, 2 on an error. It writes nothing
in the instance and destroys nothing.

**The seal.** `koto next <session> --to <state>` moves a session without
evaluating gates, and `overridable: false` doesn't stop it, so a gate alone
can't guarantee `destroy` is reached only through a durable inventory. The
`teardown_inventory` state therefore uses the seal pattern the record and
reconcile features share, through one seal helper the record feature owns:
the state's `default_action` runs `teardown-inventory.sh --seal`, which
stores the verdict in context, keyed to the `teardown_inventory` state, and
prints the bare token `sealed:<visit-seq>:<sha256>` of it, captured
as `TEARDOWN_SEAL`; the gate checks that the stored verdict hashes to the
seal, that the sequence number is the state's latest entry event, and that
the verdict's topic is still `teardown_topic`. The action writes nothing in the
instance and is safe to re-run, which is what koto asks of an action. It must
finish within koto's 30 seconds, so each network read runs under its own
short deadline, and a read that misses it makes that repository an error,
never `durable`.

An inventory that can't start doesn't fail the action. When `teardown_topic`
is empty or isn't a topic, there's no workspace root, `niwa list` has no
instance for the topic, or the instance directory is gone, the script seals
an `error` verdict with `instance -` and exits 0, so the gate routes it to
the surface step. A failed `default_action` runs no gates, and the state
takes no evidence, so failing there would hold the run at the inventory for
good. A read that may succeed on the next tick (`niwa list` or
`teardown_topic` unreadable) still fails the action, so the tick retries it.

Detection covers the skip that the seal can't prevent. `destroy`'s directive
has the coordinator read the verdict through `teardown-verdict.sh read`
before naming any command, and the reader refuses when `destroy` was entered
by a directed transition (exit 4, koto#251) or when the latest
`teardown_inventory` visit's verdict isn't sealed, durable and for the
current topic. The coordinator then destroys nothing and submits `refused`,
which goes to the surface step.

When the verdict is unique the workflow moves to `promote`, where the
coordinator promotes anything load-bearing into an issue comment or a pull
request and submits `promoted`, which re-enters `teardown_inventory` and runs
the inventory again, or `escalate` when something can't be moved. When it's
durable the workflow moves to `destroy`, whose directive reads the verdict
through `teardown-verdict.sh read` and names `niwa destroy <instance>` for
the one instance the sealed verdict's `instance` line names, with `--force`
only because of niwa#322 and only because the gate just passed, never `niwa
reap` or any form that takes no target. The coordinator submits `destroyed`,
or `handed_over` when the workspace's declared permissions reserve the
destroy for a person; both go to `record`. On `handed_over` the record also
gets a Side effects row whose target is `instance of <topic>`, never the
instance path.

### Data flow

```
pick --(dispatch_topic)--> dispatch --(sent, holding_recorded exit 0)--> record
                             |   (dispatch-worker.sh: lock, write-ahead,
                             |    niwa dispatch, confirm)
                             +--(failed)--> failure

    +--(refused, or withdrawn)----------------------------------------------------+
    |  +--(event: report; writes worker_report, report_topic)-------------------+ |
    v  |                                                                        v |
    wait --(event: leg)--> leg_pick --(leg_target)--> wait_leg --(promoted)--> take_report
    ^  ^                    |   ^                      | | |                            |
    |  +---(no leg)---------+   +--(watch: rescan)-----+ | +--(not promoted)--> surface |
    +---------------(watch: back)------------------------+                              |
                                                    (report_present, report_source_ok)  |
                                            report_facts (the record feature's) <-------+
                                              v
                                            classify_report (shadow decider)
                                              done -> verify
                                              needs_fix -> rebrief --(sent)--> wait
                                                                 +--(worker_gone)--> pick_facts
                                              blocked -> surface

    wait               --(event: retire, writes teardown_topic)--> teardown
    teardown           --(stopped)--> teardown_inventory      --(kept)--> record
    teardown_inventory --(sealed, durable)--> destroy         --(unique)--> promote
                       --(error, or the seal fails)--> surface
    promote            --(promoted)--> teardown_inventory     --(escalate)--> surface
    destroy            --(destroyed, handed_over)--> record   --(refused)--> surface
```

### Tool declaration

`skills/coordinate/requires.tsv` adds `niwa - - always`, presence only
(niwa's help output isn't in the layout the load-time probe reads), and
`scripts/lib/tool-routes.tsv` adds `niwa tsuku any tsuku tsuku-info tsuku
install tsukumogami/niwa && . ~/.tsuku/env -`. The route names niwa by its
recipe source because the bare name is ambiguous in tsuku's registry: other
ecosystems publish a niwa too, and `tsuku install niwa@latest` stops to ask
which. `koto` is declared at the floor the template
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
   `wait`, `leg_pick`, `wait_leg`, `take_report`, `classify_report` and
   `rebrief` states,
   and the `--rebrief` mode; template compile and the
   repository's template checks.
4. **Teardown.** `teardown-inventory.sh` with tests over fixture repositories
   built in the test (a squash-merged branch whose paths the default branch
   later changed, an unpushed change, a stash, a worktree on a detached HEAD, a
   remote branch deleted without merging, a submodule), and its `--seal` mode
   against the record feature's seal helper; the `teardown`,
   `teardown_inventory`, `promote` and `destroy` states.
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
`worker_report` context key, drives no gate but the non-empty check (and,
for a leg report, the comparison against the result koto holds for the leg,
which the report can only fail), and is classified by the coordinator with the decider in shadow. It can't redirect a
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
return path from the record and, for a leg report, the leg's result from
koto, and `inventory_durable` reads the sealed inventory of the instance's
repositories. A coordinator could still write a holding row by hand; the gate
would pass, and reconcile's `niwa list` read is what catches a row with no
worker behind it. That residual is accepted: the gate's job is to stop an
omission, and a forged row is not an omission.

**Destruction is targeted, follows a stop, and reads before it writes.** The
worker's session is stopped in `teardown`, a state before
`teardown_inventory`, so nothing
writes to the instance between the verdict and the destroy. `stopped` is the
coordinator's evidence, not a fact the gate reads; the ordering is what the
state split guarantees. The inventory writes nothing in the
instance, treats anything it can't classify as an error, and
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
until the script re-runs or reconcile clears it. A `/work-on` worker given a PLAN
path, and any worker on another host, use the message path. koto 0.14.0 records a wake when a leg
resolves (koto#250), but the workflow doesn't watch for it yet, so a resolved
leg is read only when a message or notification makes the coordinator tick.

**Mitigations.** Reconcile, the next feature, checks every holding against
`niwa list`. The leg table grew by data when #407 fixed #401. The wait directive's
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
- **#401, fixed by #407.** `/deliver` and `/work-on` accept `--koto-leg`, and
  the leg table carries both; `/work-on` answers a leg only for an issue or a
  task, so a PLAN-path `/work-on` worker reports by message.
- **koto#250, leg wakes aren't watched.** koto 0.14.0 records a wake when a
  leg resolves, readable with `koto request watch`; the workflow doesn't watch
  for it yet, so the coordinator reads a resolved leg on its next tick, which a
  message, a notification, or the quiet-worker check triggers.
- **niwa#322, destroy refuses squash-merged branches.** `--force` is needed
  and is passed only after the inventory proves durability.
- **One topic per worker.** koto session names are machine-wide, so a second
  worker on a live topic is refused as an origin mismatch;
  `dispatch-worker.sh` refuses the topic first.
- **koto#251, a directed transition skips gates.** koto 0.13.0's `koto next
  --to` moves a session past any gate, non-overridable ones included. Until
  it's fixed, the shared seal helper is the interim detection: the
  `teardown_inventory` state seals its inventory and `destroy`'s reader
  refuses to destroy on a directed entry, which the coordinator answers with
  `refused`. The dispatch and wait gates have no seal, so a `--to` past
  `holding_recorded` leaves a missing holding for reconcile to find.
- **Session names aren't predictable (niwa#325).** niwa appends a random
  token to `--name` and doesn't report the launched handle machine-readably,
  so the coordinator reads the name from the dispatch output or `niwa list
  --json` and matches it by its whole shape.
- **No workspace root from niwa (niwa#326).** The scripts walk up to the root,
  guarded against a clone's own `.niwa/workspace.toml`.
