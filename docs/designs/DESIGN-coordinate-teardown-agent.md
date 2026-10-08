---
schema: design/v1
status: Proposed
upstream: docs/prds/PRD-coordinate-dispatch-path.md
problem: |
  The coordinate skill's teardown stops a retired worker's session, seals an
  inventory of its instance and destroys that one instance, and ends there.
  The worker's Claude session stays in the Agents view, nothing keeps its
  transcript or its job's files, and the job id is lost once the instance is
  gone. Before the destroy even starts, the posture reader hands it to a
  person because a hook mentions `niwa reap`, a command the skill never runs.
  And the inventory read is too slow for an instance of ten or eleven clones:
  the teardown's 24-second budget and the reconcile pass's 20-second one both
  run out, so a teardown routes to the human and a restart with a live worker
  never seals.
decision: |
  A new check state, `teardown_verdict`, runs after the inventory reads
  durable and seals one verdict naming the topic, the instance, the Claude
  job and session, the merged pull requests and the handoff comment, all read
  from the host and GitHub before anything is removed; it refuses when a pull
  request isn't merged, the handoff isn't on GitHub, or the job can't be
  named. The `destroy` state hands that verdict and its seal token to a local
  agent in the coordinator's own session, started from a charter the skill
  ships and kept for the session, and the agent runs one script,
  `teardown-pass.sh`, which re-reads every fact, refuses on any
  contradiction, copies the transcript, job files and attributable koto
  sessions into an archive with a checksum manifest, destroys the one
  instance, removes the one job and confirms both listings. The coordinator
  clears the record row last, and a new check state, `teardown_confirm`,
  re-reads the listings and the archive before `record`. The archive stays in
  the interim directory under the user's data home. The posture reader's
  teardown step is stood for only by the commands the skill runs. Both
  inventory reads walk clones in parallel and skip tips the remote already
  has.
rationale: |
  The legwork is a fixed sequence with no judgment in it, so it belongs in a
  script that can be tested end to end against stand-ins; the agent exists so
  the sequence's output stays out of the coordinator's context and so the
  authority to run it never leaves the coordinator's session. Sealing the
  verdict in a check state keeps the template's rule that no check reads what
  the coordinator writes: the coordinator supplies only the handoff link, and
  the check verifies it on GitHub. The inventory's time goes to per-tag git
  calls and to network reads made one clone after another, not to the
  content checks, so parallel clones and a set lookup cut it without
  loosening what it proves.
---

# DESIGN: coordinate-teardown-agent

## Status

Proposed

## Context and Problem Statement

The coordinate skill retires a worker through four states in
`skills/coordinate/koto-templates/coordinate.md`: `teardown`, where the
coordinator stops the worker's session by its id; `teardown_inventory`, whose
default action `teardown-inventory.sh --seal` lists what the worker's instance
holds that exists nowhere else and seals the verdict; `promote`, which moves
anything unique into an issue or pull request and inventories again; and
`destroy`, where the coordinator reads the sealed verdict, runs `niwa destroy
<instance>` and removes the holding row. This is the dispatch path's teardown
(`docs/designs/current/DESIGN-coordinate-dispatch-path.md`; R20 and R21 of
`docs/prds/PRD-coordinate-dispatch-path.md`).

The performance rotation's first teardown on 2026-10-06 showed where it stops
short (tsukumogami/shirabe#617). After the review-level-up-front worker was
stopped and its instance destroyed, the finished job stayed in `claude agents
--json --all` as `state: done`, so the person's Agents view kept a row for a
session whose instance was gone. Removing it took a separate `claude rm`,
which deleted the job directory, and with it `state.json`, `timeline.jsonl`
and the job's `tmp/` scratch, which held the worker's handoff drafts. Nothing
in the skill said to keep any of that first, or the transcript, or the 87 koto
sessions the worker left (72 of them throwaway fixtures). And once the
instance is gone `niwa list` no longer shows it, so the job id has to be
captured before the destroy.

The same teardown stalled before the destroy (tsukumogami/shirabe#616).
`posture-read.sh` stands for the teardown step by four command forms, `niwa
destroy`, `niwa reap`, `niwa instance remove` and `niwa remove`, and marks the
step `confirm` when a PreToolUse hook's text mentions any of them. The
workspace's gate hook denies `niwa reap`, the untargeted sweep, and no other
niwa command; the skill never runs reap. The read came out `teardown:
confirm, why: a PreToolUse hook mentions niwa reap`, the coordinator handed a
durable destroy to the person, and the person had to ask why.

And the inventory is too slow (tsukumogami/shirabe#618). `reconcile-pass.sh`
gives each worker's inventory read 20 seconds and kills it at the budget; on
an instance of ten clones the read took 24.3 seconds by hand, so a restart
over a live worker re-launched it on every tick for eighteen minutes and
never sealed. The teardown read hit the same wall: `public/tsuku: not fully
inventoried; the scan ran out of its 24s budget at tag v0.15.2`, and three
later runs by hand with a raised budget took 21.5, 21.7 and 24.1 seconds (the
issue's comments). Measured again for this design against an idle instance
of ten freshly cloned repositories on the same host: the teardown inventory
takes 12.7 seconds and the reconcile inventory 22.6. The reconcile read
spends about 37 ms on each local tag, one `rev-list` under its deadline
wrapper (2.6 seconds for one clone's 69 tags alone), and both reads make each
clone's two network reads, the remote's refs (about 0.3 s) and the default
branch's recursive tree (0.5 to 0.7 s), one clone after another. The content
checks are the smaller part: the largest clone, 15,494 tracked files,
inventories on its own in 2.5 seconds.

The coordinator roadmap's Feature 10 records the pattern this design
implements: a persistent local agent inside the coordinator's session, not a
separate session, so teardown authority never crosses a session boundary and
no one else can tell the janitor to clean something up. The coordinator keeps
the judgment, decides a worker is retired and hands the agent one sealed
verdict; the agent does the legwork, one named target per pass. An improvised
janitor session in earlier dogfooding was told to run a workspace-wide
cleanup and destroyed another lane's instance. The feature leaves two
questions open, which this design settles: how `destroy` hands one verdict to
the agent, and the archive's permanent home. It also settles the three
defects above.

### What `claude rm` removes

Re-measured for this design on Claude Code 2.1.293 (the roadmap's
measurement is from 2.1.292), with a throwaway background session started for
the purpose: `claude stop <id>` keeps the job directory; `claude rm <id>`
then deletes `~/.claude/jobs/<id>/`, `tmp/` included, and the job's entry in
`claude agents --json --all`, and leaves the transcript
`~/.claude/projects/<slug>/<session>.jsonl` and the `session-env` entry. The
behaviour is undocumented, so the pass copies everything it keeps before the
removal rather than relying on what the removal spares.

## Decision Drivers

- **One named target per pass.** Nothing runs that takes no target, and
  nothing acts on anything the verdict doesn't name.
- **The workflow reads, the coordinator writes.** No check reads what the
  coordinator wrote except through a GitHub or host read that verifies it.
- **Refuse rather than repair.** A removed session can't fix its own pull
  request, so the pass refuses whenever a fact it re-reads disagrees with the
  verdict.
- **Testable end to end.** The sequence must run in an engine test against a
  stand-in instance and job, asserting each removal happened once.
- **Inside `skills/coordinate/`.** The skill ships everything it needs; the
  one shared script it changes is its own posture reader.
- **Cheaper running.** The coordinator's context should hold the verdict and
  the result, not the sequence's output.

## Considered Options

### Decision 1: The verdict's form and how it's handed over

**Chosen: a sealed verdict from a new check state, handed over with its seal
token.** `teardown_verdict` sits between `teardown_inventory`'s durable exit
and `destroy`. Its default action, `teardown-handoff.sh --seal`, reads:

- the sealed inventory, through `teardown-verdict.sh`'s seal check, which must
  read durable and cover `teardown_topic`;
- the instance's name and path from `niwa list --json`, matched by the
  inventory's path;
- the job from `claude agents --json --all`: exactly one entry whose `cwd` is
  the instance path, cross-checked against niwa's `session_name` where niwa
  records one, giving the job id and its `sessionId`; its state must not be
  `working`, since the session was stopped before the inventory;
- the merged pull requests: the holding's Repo and Branch from the record,
  and every pull request GitHub lists as merged from that branch, each with
  its merge commit; none is a refusal;
- the handoff: the comment link the coordinator submitted with `teardown:
  stopped` (a new optional field, `handoff`), read back from GitHub; it must
  be an issue or pull request comment in the holding's repository with a
  non-empty body.

The verdict is plain lines, one fact per line (`topic <t>`, `instance <name>
<path>`, `job <id> <session>`, `transcript <path>`, `pr <owner/repo>#<n>
<merge sha>` per pull request, `handoff <url>`, `inventory <seal token>`),
sealed through `coord-log.sh` under the key `teardown_handoff` like every
other check's detail. The state routes `handoff-ready` to `destroy` and
`handoff-refused` to `surface`, with the reason in the detail.

The coordinator hands the agent the verdict's text and its seal token. The
agent's script never takes the target from the message: it reads the verdict
through the seal from the coordinator's koto session and refuses unless the
token it was given is the current one, so a stale or edited hand-off can't
point a pass at another instance.

**Rejected: the coordinator writes the verdict.** That's the one thing the
template forbids, and the job id and pull request list are facts a script can
read. **Rejected: folding these reads into `teardown-inventory.sh`.** The
inventory runs inside koto's 30-second action budget and already owns one
seal; the verdict needs reads the inventory doesn't, and a refusal here means
something different from unique material.

### Decision 2: The agent's definition and invocation

**Chosen: a charter the skill ships, given to a subagent the coordinator
starts once and keeps.** `skills/coordinate/references/teardown-agent.md` is
the agent's standing instruction: what it may run (only `teardown-pass.sh
run` with the session and token it was handed, and read-only listings), what
it never runs (`niwa reap`, `niwa destroy` without a name, `claude rm` or
`claude stop` typed by hand, any command without a target), that it takes
direction only from this coordinator, one pass at a time, and that it reports
the script's result lines verbatim and stops on any refusal. The `destroy`
directive tells the coordinator to start the agent with the harness's
subagent tool on the session's first teardown, passing the charter and the
first verdict, and to send each later verdict to the same agent. The agent
lives and dies with the coordinator's session, and the cap doesn't count it
(the cap already excludes local agents).

The legwork itself is `teardown-pass.sh`, so the sequence is code with tests
rather than prose an agent follows. Because each pass carries its full
verdict and the script re-reads everything, a restarted coordinator that has
lost its agent starts another; persistence saves a start-up and isn't load
bearing.

**Rejected: an agent definition in the plugin's `agents/` directory.** It
lives outside `skills/coordinate/`, any session that loads the plugin could
invoke it, and it can't carry the pass's verdict anyway, so the directive
would still render the hand-off. **Rejected: the coordinator runs the script
itself.** It works, and the directive allows it for a harness with no
subagent tool, but the point of the agent is that the legwork's output stays
out of the coordinator's context.

### Decision 3: The pass

`teardown-pass.sh run --session <s> --token <sealed:...>`, in order:

1. **Read the verdict** through the seal; refuse when the token isn't the
   current one, or when the session log shows a directed transition since the
   seal (koto#251).
2. **Re-read every fact.** Each pull request still merged at its merge
   commit; the handoff comment still there; the job still listed with the
   same `cwd` and session and not working; niwa still listing the instance by
   that name and path. Any difference refuses.
3. **Re-inventory**, unsealed, with `teardown-inventory.sh --topic
   --instance`; anything but durable refuses. The sealed inventory is minutes
   old by now, the destroy is irreversible, and after Decision 6 the read
   costs a few seconds.
4. **Preserve.** Into the archive directory (Decision 4), named `<UTC
   date>-<topic>-<job id>`: the transcript jsonl and its sibling subagent
   directory if any; the job's `state.json`, `timeline.jsonl` and `tmp/`; and
   every koto session directory whose state file's header has an
   `execution_dir` at or under the instance path or the job's `tmp/`. A
   `MANIFEST.sha256` lists every copied file, each copy is checked against
   its source's hash, and a `README.md` names the unit, the pull requests,
   the handoff and the date. A copy that doesn't verify refuses, with nothing
   removed.
5. **Destroy** with `niwa destroy --force <name>`, run at the workspace root,
   the name taken from the verdict and checked non-empty and well formed
   before the command is built (niwa#342). `--force` stands on step 3's
   durable read (niwa#322).
6. **Remove** with `claude rm <job id>`.
7. **Confirm** that `niwa list --json` no longer shows the instance and
   `claude agents --json --all` no longer shows the job, and write the result
   into the archive.

Exit 0 is `done`; 1 is `refused`, before anything was removed; 2 is
`incomplete`, after the destroy, naming the step that failed, which goes to
the person. The script never stops a session: the stop is the `teardown`
state's, before the inventory, as it is today.

Back in the loop, the coordinator removes the holding row (the last write),
then submits `destroyed: destroyed`, which now goes to `teardown_confirm`.
That check re-reads the verdict through its seal, both listings, and the
archive against its manifest, and routes `teardown-confirmed` to `record`
(whose check confirms the row is gone, as now) and `teardown-incomplete` to
`surface`. A refusal is `destroyed: refused`, as now; `handed_over` is
unchanged for a posture that reserves the step.

### Decision 4: The archive's home

**Chosen: the interim directory stays, for now.** The pass writes to
`$TEARDOWN_ARCHIVE_DIR`, defaulting to
`${XDG_DATA_HOME:-~/.local/share}/teardown-archive/`. It isn't `/tmp` and
isn't the job's tmp directory, which `claude rm` deletes.

The workspace's observability archive is the natural permanent home, and it
can't serve today: it copies every source on its own cadence with no
per-session mode, its job copies are rebuilt from an allow-list that drops
most of `state.json`, and it doesn't run on every host. The condition that
moves the default is that archive offering a per-session write that keeps
`state.json` whole, running on the coordinator's host; then
`TEARDOWN_ARCHIVE_DIR` points there and the pass is unchanged. Retention and
pruning of the interim directory are out of scope; the skill deletes nothing
in it.

### Decision 5: The posture reader (tsukumogami/shirabe#616)

The teardown step is stood for by the commands the skill runs to perform it:
`niwa destroy`, `claude rm`, and `teardown-pass.sh`, the script that runs
both (a hook matching a typed command never sees a command a script runs
inside itself, so the script's name stands for them, as `land-merge.sh` does
for the merge). `niwa reap`, `niwa instance remove` and `niwa remove` leave
the list: the skill never runs them, and a hook that denies them gates
nothing the skill does. A hook whose text names `niwa destroy` still makes
the step `confirm`, and a deny rule on it still makes it `deny`.

The issue's related note, that the same reader keys `merge: confirm` on any
hook mentioning the merge command, is a different step and stays out of this
design.

### Decision 6: The inventory's speed (tsukumogami/shirabe#618)

Both inventory reads, `teardown-inventory.sh` and `reconcile-check.sh
inventory`, change in two ways that leave what they prove untouched:

- **Tips the remote already has are settled by lookup.** A local branch or
  tag whose object id is one of the remote's live ids has no commit outside
  the remote, so the per-tip `rev-list` is skipped for it. Only tips that
  differ (an unpushed branch, a moved tag, a detached HEAD) pay for the walk.
- **Clones run in parallel.** Each clone's read runs as its own background
  job with its own scratch files, at most eight at a time, and the per-clone
  results are merged in queue order, so the output is the same as a serial
  read's. Clones found during the walk (submodules, nested clones,
  worktrees) join the next wave. A linked worktree sharing a git directory
  with another clone is read after the first of them, as now, so its refs
  aren't listed twice.

The budgets stay (24 seconds for the teardown read, 20 for reconcile's), and
a read the budget doesn't finish is still an error or not verified, never
durable. The target is the ten-clone instance reading inside half of each
budget on this host, idle and under a worker's test load; the implementation
pull request carries the measurement.

**Rejected: a larger budget.** The teardown read runs inside koto's
30-second action limit, so it can't grow much, and the reconcile pass's
24-second tick bounds every read in it. **Rejected: a cheaper reconcile-only
read.** It would answer a weaker question than the teardown's, with a second
implementation to keep honest, and the shared faster read answers the same
question in time. **Rejected: an inventory the worker keeps current.** It's a
claim by the party whose work is being checked.

## Decision Outcome

`teardown_verdict` seals one verdict from host and GitHub reads and refuses
an unmerged pull request, a missing handoff or a job it can't name. The
`destroy` state hands the verdict and its token to a local agent the
coordinator starts from the skill's charter and keeps for the session; the
agent runs `teardown-pass.sh`, which re-reads, re-inventories, archives with a
verified manifest, destroys one instance, removes one job and confirms both
listings. The coordinator clears the row last, and `teardown_confirm` checks
the result before `record`. The archive stays in the user's data home until
the observability archive can take per-session writes. The posture reader
judges teardown by the commands the skill runs. Both inventories walk clones
in parallel and skip tips the remote has.

What the roadmap's Feature 10 asks for that this declines:

- **The agent stops the session and seals the inventory.** The stop and the
  sealed inventory stay where they are, in `teardown` and
  `teardown_inventory`: the stop must come before the inventory so nothing
  writes to the instance between them, and the verdict names the sealed
  inventory, so both have to exist before the verdict does. The pass refuses
  a job that's running again and re-inventories before the destroy, which
  covers what moving them would have.
- **The agent promotes unique material.** `promote` is a judgment about where
  material belongs, and it's already a coordinator state; the pass refuses
  anything not durable instead.
- **The agent clears the record row.** The record is written by the
  coordinator through the skill's record scripts, whose checks read the
  coordinator's session log; the row is still cleared last, after the pass
  has confirmed both listings, and `record` confirms it.
- **Koto sessions whose execution directory "is" the instance path.** Read
  as "at or under": a worker starts its workflows in the repositories inside
  its instance, so an exact match would miss nearly all of them.

## Solution Architecture

### The template

```
teardown --stopped(+handoff)--> teardown_inventory --durable--> teardown_verdict
teardown_verdict --handoff-ready--> destroy --destroyed--> teardown_confirm
teardown_verdict --handoff-refused--> surface
teardown_confirm --teardown-confirmed--> record
teardown_confirm --teardown-incomplete--> surface
destroy --refused--> surface        destroy --handed_over--> record
```

`teardown_topic` is cleared on every edge that leaves the teardown states, as
now; `teardown_verdict` and `teardown_confirm` are teardown states.
`record-confirm.sh` treats an entry into `record` from `teardown_confirm` as
it treats one from `destroy`, reading the `destroy` evidence before it.

### New verdict words

| Word | State | Code | Route |
|---|---|---|---|
| `handoff-ready` | `teardown_verdict` | 200 | `destroy` |
| `handoff-refused` | `teardown_verdict` | 201 | `surface` |
| `teardown-confirmed` | `teardown_confirm` | 202 | `record` |
| `teardown-incomplete` | `teardown_confirm` | 203 | `surface` |

### Files

| File | Change |
|---|---|
| `skills/coordinate/scripts/teardown-handoff.sh` | new: the verdict, sealed |
| `skills/coordinate/scripts/teardown-pass.sh` | new: `run` (the pass) and `confirm` (`teardown_confirm`'s check) |
| `skills/coordinate/references/teardown-agent.md` | new: the agent's charter |
| `skills/coordinate/scripts/teardown-inventory.sh`, `reconcile-check.sh` | parallel clones, tips settled by lookup |
| `skills/coordinate/scripts/posture-read.sh` | the teardown step's commands |
| `skills/coordinate/scripts/coord-verdict.sh` and its table test | the four words |
| `skills/coordinate/scripts/record-confirm.sh` | `teardown_confirm` as a source |
| `skills/coordinate/koto-templates/coordinate.md`, `coordinate.mermaid.md` | the two states, the `handoff` field, the directives |
| `skills/coordinate/SKILL.md` | the Teardown entry and what a coordinator never does |
| `skills/coordinate/requires.tsv` | `claude` and `niwa` for the pass |
| tests | unit tests for the new scripts and the posture change; a new engine suite, `teardown-pass_engine_test.sh` |

## Implementation Approach

Two pull requests after this design, each landing before the next opens.

1. **The inventory and the posture reader.** Decisions 5 and 6, with no
   template change: the faster reads with their existing tests plus cases for
   output order and settled tips, the posture change with its cases, and the
   measurement on a ten-clone instance, idle and under load. Closes
   tsukumogami/shirabe#616 and tsukumogami/shirabe#618.
2. **The verdict, the agent and the pass.** Decisions 1 to 4: the two
   scripts, the charter, the template states and directives, and the engine
   suite, which runs a full teardown against a stand-in instance and job
   (stand-in `niwa` and `claude`, a temporary Claude and koto home, the real
   koto) and asserts the archived files and their manifest, exactly one
   destroy and one rm, both listings confirmed and the row cleared, and the
   refusal, with nothing removed, when the pull request isn't merged. Evals
   run for every scenario reaching a changed state. Closes
   tsukumogami/shirabe#617.

## Security Considerations

The pass destroys and deletes, so every target comes from the sealed verdict,
never from the message that started the pass or from an argument the agent
could vary: the token only selects which seal to check, and a token that
isn't the current one refuses. The instance name is validated before the
destroy command is built, so it can't be empty and the command can't widen
into a workspace-wide destroy. The pass refuses on any contradiction rather
than resolving it. The archive holds transcripts, which can hold anything the
worker saw, so it lives under the user's own data directory with the user's
permissions, and the pass never prints a file's content, only paths and
hashes. The charter tells the agent to take direction from its coordinator
only, and the agent can't widen what it runs, because the script reads its
target from the seal.

## Consequences

### Positive

- A retired worker leaves nothing behind in the Agents view, and its
  transcript, job files and koto sessions survive in one place with a
  manifest.
- The job id is captured before the destroy and kept in the archive.
- The destroy no longer goes to a person because of a hook about reap.
- A restart with a live worker seals, and a teardown of a large instance
  stops routing to the human on a budget overrun.
- The coordinator's context holds a verdict and a result line per teardown.

### Negative

- Two more states, and a coordinator-supplied field on `teardown`.
- The pass relies on undocumented behaviour of `claude rm` and on the shape
  of `claude agents --json --all`.
- The archive grows until someone prunes it.
- The koto sessions are copied, not removed, so `~/.koto/sessions` keeps
  growing (koto#308).

### Mitigations

- The handoff field is verified on GitHub, so a wrong link refuses rather
  than passing.
- The pass copies before it removes and confirms both listings after, so a
  change in `claude rm` shows up as an incomplete pass, not lost files, and
  the design records the version it was measured on.
- The archive's location is one variable, ready for the observability
  archive.
- Removing koto sessions waits for koto to list and remove them by execution
  directory.
