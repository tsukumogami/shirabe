---
schema: design/v1
status: Planned
problem: |
  The coordinate skill's reconcile step is prose, so nothing makes a
  restarted or rotated coordinator re-check its inherited record before it
  acts, and nothing shows whether it did. The loop is becoming a koto
  workflow with reconcile as one state. That state needs to do dozens of
  GitHub and host reads inside an engine that gives each action 30 seconds,
  re-read a missing worker no sooner than 30 seconds later, and hold the
  workflow until a report exists that the reconcile script wrote during this
  visit, where no value the agent supplies can stand in for it.
decision: |
  The reconcile state runs `reconcile-pass.sh` as its non-polling default
  action on every tick. Each run does one bounded pass of reads, saving
  progress to a visit-scoped work file in the session directory, and exits
  with `pending:...` until every read is done, including a listing re-read
  30 seconds after a miss. The final pass builds the report from its own
  work file, writes the report as JSON and as rendered text into context, and
  prints `reconciled sealed:<visit-seq>:<sha256>`, which the engine captures as
  RECONCILE_SEAL. A non-overridable command gate, the shared seal check the
  record feature owns,
  passes only when the stored report hashes to the sealed value and the
  sealed visit is the current one. The reads live in small scripts whose
  report rules are a pure function; the record reader, board check and
  deferral check are the record feature's, reused through one seam.
rationale: |
  A capture is the one value in koto 0.13.0 the agent can't write: it comes
  only from action stdout, the action runs on every tick that reaches the
  state, and a state with no accepts block refuses evidence. Binding the
  report's hash and the visit to that capture means a report the agent
  writes, or one left from an earlier visit, fails the gate. Splitting the
  reads across ticks keeps each run under the action limit without polling,
  which in 0.13.0 can't gate on its own run. Agent-run scripts, background
  collectors and a separate seal state were rejected because each either
  lets an agent-written value pass or restructures the template. The one
  hole left is `koto next --to`, which skips every gate; it is recorded as a
  known limitation with detection in the pick state's report read.
upstream: docs/prds/PRD-coordinate-reconcile.md
---

# DESIGN: coordinate-reconcile

## Status

Planned

## Context and Problem Statement

The `coordinate` skill drives a roadmap or a discipline rotation by
dispatching worker sessions and landing what they push. Its record on
GitHub holds four things GitHub can't recompute: holdings (each with a
dispatch topic, branch, pull request and verified head), deferrals, side
effects in flight and reversals. The PRD
(`docs/prds/PRD-coordinate-reconcile.md`) requires that at every start,
restart and rotation handoff, a script re-checks every one of those claims
against its live source and writes a report into the workflow's context,
and that the workflow can't reach pick until that report exists (R1 to R31).

The loop is being turned into a koto workflow template,
`skills/coordinate/koto-templates/coordinate.md`, by the coordination-record
feature. That template has a `reconcile` state between start and pick, and
until this design lands the state calls the prose procedure in
`skills/coordinate/references/loop.md`. This design fills that state. It
doesn't add states or move transitions.

Three properties of koto 0.13.0 shape the answer, read from its source:

- A `default_action` run is killed after 30 seconds, and that limit isn't
  configurable. With `polling`, the state's gates are evaluated inside the
  loop before the run's `default_action_executed` event is appended, and a
  gate that reads the polling action's own capture is refused, so a polling
  action can't gate on its own result.
- A non-polling action's `capture_stdout_as` value reaches the tick's
  variable overlay before that state's gates are evaluated, so a gate in the
  same state can read it. Captures come only from action stdout; the agent
  has no command that sets one.
- `koto context add` records the same event whoever calls it, so a context
  key alone proves nothing about who wrote it.

The reconcile reads themselves are those `loop.md` describes: pull request
state, the CI board, the branch on the remote, the workspace manager's
listing and the worker's instance, and, for a merge in flight, the default
branch's content compared with the verified head. With three holdings that
is several dozen network calls, more than one 30-second run can promise.

## Decision Drivers

- **No agent-supplied value may satisfy the gate** (PRD R22, R23). Evidence,
  context values, flags and overrides are all out.
- **"This visit"** (R22). A report from an earlier entry into reconcile
  must not satisfy the gate.
- **The 30-second action limit** and a 30-second minimum between two
  listing reads (R10) have to coexist.
- **Fill the state, don't restructure the template.** The record feature
  owns the template's shape.
- **Reuse, don't duplicate,** the record feature's reader, board check and
  deferral-disposal check (R1, R5, R15).
- **Reads only** (R27). Nothing on GitHub, the host or the record changes;
  that includes `git fetch` in a worker's clone.
- **Testable without the network** (the PRD's acceptance criteria run
  against stubs), including the 30-second timing.
- **Workers by dispatch topic only** (R29), and "not found on this read"
  rather than "gone" (R10).

## Considered Options

### Decision 1: How reconcile runs its reads and proves its report to the gate

The reads don't fit in one 30-second action, the re-read needs 30 seconds
of wall time, and the gate has to tell the script's report from anything
else in context.

#### Chosen: tick-driven passes sealed by a capture

A non-polling `default_action`, `reconcile-pass.sh`, runs on every tick that
reaches the state. Each run does one pass: it resumes a work file under the
session directory, launches the reads that remain (up to four in parallel)
until 20 seconds have passed, clips each read's deadline to the time left,
saves after every read with an atomic rename, and keeps the last few
seconds for the report and the context writes, so no run reaches koto's
30-second kill. When work remains it exits 0 printing
`pending:<visit-seq>:<n>:<sha256 of the work file>`. The state's gate then
fails, the tick returns blocked, and the directive tells the agent to tick
again. A missed listing read is retried on a later pass once 30 seconds
have passed since the first read, or within the same pass by sleeping when
the remaining wait fits before the cutoff.

The work file is anchored to the engine the same way the report is. At the
start of every pass, the script reads the stdout of this state's most
recent `default_action_executed` event from the session log (the engine
appends that event; nothing else writes it) and compares the hash in it with
the work file's current hash. A mismatch means something other than the
pass changed the file between ticks, and the pass discards it and starts the
visit's reads again. So the facts a report is built from are only ever the
ones earlier passes of this visit wrote and the engine logged. A pass that
was killed or failed logs no `pending:` hash, so the next pass restarts the
visit's reads rather than resuming them; the per-read saves are the pass's
own bookkeeping within one run.

The pass and the gate run in a scrubbed environment. koto spawns actions and
command gates with the environment of whoever ran `koto next`, and that is
the agent. So the first thing each script does is re-execute itself under
`env -i` with a fixed `PATH` of system directories plus the tool directories
of the account's own home (read from the password database, not from
`HOME`), and it refuses to run when `BASH_ENV`, `ENV`, `LD_PRELOAD`,
`GIT_CONFIG_*`, `GIT_DIR` or a `GH_HOST`, `GH_REPO` or `GH_TOKEN` override is
set. The command line in the template invokes the script through `env -u
BASH_ENV -u ENV` so no startup file runs before that check. There is no test
hook in the environment: tests drive an internal entry point with an
injected clock, which the template's command line never calls.

When every read is done, the pass builds the report from its own work file,
writes it to context, hashes the exact bytes it wrote, and prints
`sealed:<visit-seq>:<sha256>`. The engine captures that line as
`RECONCILE_SEAL`. The gate, the record feature's shared seal check, passes only when the
stored report hashes to the sealed value and `<visit-seq>` is the sequence
number of the latest event that entered the state. The gate is declared
`overridable: false`, the state declares no `accepts` block (so it refuses
evidence), and there is no override transition.

What that leaves the agent: writing the report key changes its hash; it
can't set a capture; it can't skip the action, which runs on every tick
without evidence; an earlier visit's seal is overwritten by this tick's
action before the gate reads it, and fails the entry check anyway; running
`reconcile-pass.sh` by hand does real reads but its output never becomes
the capture. See Consequences for `koto next --to`.

#### Alternatives

**The agent runs the script and a context gate checks the key.** No time
limit applies and a `sleep 30` covers the re-read. It fails the first
driver outright: the agent's own `koto context add` writes the same key and
the same event, and any nonce the gate demanded could be copied from the
session log.

**A polling action with incremental passes.** Polling spaces the passes and
the re-read naturally. In koto 0.13.0 it can't carry the seal. A gate that
references the polling action's own capture is refused before the command
runs on a first visit, and on a later visit it resolves to the previous
tick's value, never to this run's. A polling gate over any other input fares
no better, because the run's `default_action_executed` event is appended
only after the polling loop exits: nothing a gate can read inside the loop
is anchored to the engine.

**A non-polling action with a gate that parses the session log.** The gate
would find this visit's `default_action_executed` event and compare the
hash in its stdout with the stored report. It's as authentic as the chosen
option, since only the engine appends that event, but it couples the gate
to the log's file format when a capture carries the same fact through a
documented interface. The chosen option still reads the log for one fact,
the visit's entry sequence, which no documented interface exposes.

**A background collector with a fast assembling action.** A collector
started by the agent, or detached by the action, writes a snapshot that a
fast action turns into a report. Nothing the engine logs vouches for the
snapshot, since the collector's output never passes through an action's
stdout, so forged inputs would still produce a report that passes; and a
detached process escapes the engine's process-group kill and runs outside
the engine's model. The chosen option's work file differs on exactly the
first point: every pass that writes it prints its hash through the engine.

**A separate seal state after reconcile.** Capturing the digest in a
follow-on state is sound, but unnecessary once a same-state gate can read a
non-polling capture, and it adds a state to a template this feature doesn't
own.

**A command gate that runs the whole reconcile.** Gate timeouts are
unbounded, so a gate could do every read and sleep through the re-read. It
puts every read inside a judge that re-runs on every tick, holds a tick for
minutes, surfaces only an exit code, and defeats the action limit's intent.

### Decision 2: How the code is split, what it reuses, and how it's stubbed

#### Chosen: a pass driver over three focused scripts, with the report rules pure

- `reconcile-pass.sh` is the state's action. It resolves the visit, resumes
  or resets the work file, schedules the reads, and writes and seals the
  report.
- `reconcile-read.sh` reads the record through the record feature's reader
  (and, at discipline scope, the handoff file) and emits it as JSON, with
  exit codes for found, none, ambiguous, undeclared and unreadable.
- `reconcile-check.sh` has one subcommand per kind of re-check. Each prints
  one JSON fact and routes every external call through a deadline wrapper,
  so a failure becomes a not-verified fact rather than a script failure.
- `reconcile-report.sh` turns facts into the report JSON and its rendering.
  It does no I/O beyond stdin and stdout and carries the PRD's structure,
  phase, next-line, waiting and grading rules (R16 to R19), so those rules
  are tested without any stub.
- The gate is the record feature's shared check channel: its verdict gate
  `coord-verdict.sh` over its seal helper `coord-log.sh` (`seal`, `check`,
  `directed-since`), which every check state in the template, the pick
  side's read and the dispatch path's teardown gate use. Reconcile ships
  none of its own.
- `reconcile-deps.sh` names the record feature's reader, board check,
  deferral check and seal helper in one place, so aligning with that
  feature's final names is a one-line change. It also sources the input
  validators from `skills/execute/scripts/coord-common.sh` (repository,
  branch, sha, slug and pull request URL patterns, `RE_COORD_SLUG` for the
  topic) rather than copying them.

Tests follow the per-test keyed stub of
`skills/execute/scripts/merge-verdict_test.sh`: a `PATH` shim for `gh`,
`git`, `niwa` and `koto` that serves `<key>.out.N` on the Nth call and logs
every call. The log is how the read-only criterion is checked. Tests call
the scripts' internal entry points, past the environment scrub, with an
injected clock and a no-op sleep, so the 30-second re-read is tested
without waiting and without a clock hook the production command honors. The shared `gh` shim under `skills/execute/evals/` is not
reused: it serves no run-list, jobs or contents route.

#### Alternatives

**One script.** Fewer files, but the report rules could only be tested by
stubbing every read around them, and each of the seven next-line cases
would need a full fixture.

**A Rust subcommand in the validator crate.** JSON handling is easier in
Rust, but the record feature's reader and board check are shell, so the
logic would straddle two languages, and every change would wait on a
validator release.

**Re-implementing the reader and board check locally.** It removes the
dependency on the record feature's timing. It's ruled out by the brief this
feature was scoped from, and two readers of one record drift.

### Decision 3: The report's shape and where it lives

#### Chosen: JSON as the report, text as its rendering, in separate keys

One pass writes these context keys, all under `reconcile/`:

| Key | Content | Read by |
|-----|---------|---------|
| `reconcile/report.json` | The report, schema `coordinate-reconcile-report/v1`. This is the sealed key. | the gate (by hash), the pick state |
| `reconcile/report.md` | The report rendered as text, in R16's section order | the agent, through the directive |
| `reconcile/reasoning.md` | The predecessor's reasoning, verbatim (discipline scope only) | the agent; no gate names it |
| `reconcile/refusal` | `<case>: <reason>` when no report can be written (R3) | the agent, to escalate |
| `reconcile/progress` | why the last pass stopped short, in words | the agent, to know why it's ticking again |

The JSON holds a header (scope, record `Written:` time, reconcile time),
`changes[]`, `holdings[]` (topic, phase, state, next, board, per-read time
and grade), `waiting[]`, `nowhere_else[]`, `side_effects[]`,
`deferrals[]`, `reasoning` (present, absent or not recorded) and
`not_verified[]`. File paths in the report are relative to their clone, never absolute,
since an absolute path under a worker's instance names the instance. The
rendering is derived from the JSON by the same run, so the two never
disagree. The markdown's hash isn't sealed, because pick doesn't
read it.

#### Alternatives

**Text only.** The pick state would parse prose to count holdings by phase.

**JSON only.** The agent would read a raw document into its context at
every start, which is the cost R21 bounds.

**One key per holding.** No single write makes the report whole, so a
half-written report could satisfy a gate that checked for keys.

### Decision 4: Finding a worker by topic and inventorying it without writing

#### Chosen: match the listing on the topic's slug; compare blobs through GitHub

`niwa list --json` returns every instance with its name, path and, once the
session mapping exists, its session name. The workspace manager builds both
names from the dispatch topic's slug: the instance as
`<config>+<slug>-<8 hex>` and the session as `<slug>-<8 hex>`. Reconcile
slugs the record's worker column the same way and matches either name
against those shapes. One match is found; two are ambiguous and land in "not
verified"; none triggers the re-read. A command that can't run or can't be
parsed marks every holding's host reads "not verified".

For a matched instance, reconcile walks each git clone under its path. It
never runs `git status`: status refreshes the index, recurses into
submodules under their own config, and runs the clean and process filters
the clone's config names, and no set of flags turns all of that off. It reads
plumbing that runs no filter instead, every call as `git --no-optional-locks
-c core.fsmonitor= -c core.hooksPath=/dev/null -c protocol.allow=never` under
the read deadline:

- **Commits.** A clone's local remote-tracking refs are as old as its last
  fetch, and reconcile doesn't fetch. So it reads the live refs of the
  clone's own origin with one `git ls-remote`, run from `/` so no
  repository's config applies, when that origin is a github.com repository
  (an instance can hold several repositories, so the record row's repository
  isn't the right one for every clone; any other origin marks the clone
  unchecked). A tip (each local branch, each local tag, a detached HEAD)
  counts as pushed only when `git rev-list` finds no commit of it outside
  the live shas the clone has. A clone that hasn't fetched lately lacks some
  of them, so for a tip with commits outside the ones it has, GitHub's
  compare API is asked whether the default branch, or the remote branch of
  the same name, contains the tip (at most forty such reads a run; a read
  that can't answer leaves the tip unchecked). A commit on a branch that was
  pushed and later deleted on GitHub therefore counts as unique, which it
  is. A tip still not contained has its changed files compared by content
  with the default branch, against a merge base taken with the default tip
  or, in a stale clone, with a local commit GitHub says the default branch
  contains; files whose content landed don't count, which covers a
  squash-merged branch. A stash is always listed.
- **Files.** `git ls-files -s -v` gives each tracked path's index blob and
  its skip-worktree and assume-unchanged tags, `git ls-tree` gives HEAD's,
  and one `git hash-object --no-filters --stdin-paths` hashes every present
  tracked file and every untracked one (`git ls-files --others
  --exclude-standard`). A path is unique when its staged content (index
  against HEAD) or its working-tree content (file against index) differs
  from the default branch's blob for it, read from one recursive tree read
  per clone (the contents API per path only where GitHub truncates the
  tree). So a staged change whose file was put back, and an edit to a
  skip-worktree or assume-unchanged file, are found. Ignored files aren't
  listed.
- **Worktrees, submodules and nested repositories.** `git worktree list`
  names extra worktrees; one inside the instance has its own HEAD and files
  read (its refs, stash and worktree list are its repository's, read once),
  one outside it is listed, not read. A submodule (a gitlink in the index) and an
  untracked directory holding its own repository are walked as clones of
  their own, never through the superproject's git; `find` reaches clones
  anywhere in the instance, ignored directories included, to sixteen levels.
  A read that fails or runs late marks the clone unchecked, and a truncated
  inventory never reads as "nothing unique".

Caps, containment and path validation are in Security Considerations.

#### Alternatives

**Match on session id or instance path.** Those are host facts that don't
survive a restart or a move, and R29 forbids them.

**`git log origin/<default> --find-object` after a fetch.** It's the
check `loop.md` shows, but the fetch writes refs in the worker's clone, and
reconcile writes nothing on the host. Without the fetch, `origin/<default>`
is as old as the clone's last fetch.

**Ancestry (`git branch --contains`).** A squash merge breaks it: a commit
reachable only from a squashed-and-deleted branch is unique material even
though its content landed.

## Decision Outcome

The reconcile state becomes a sealed, tick-driven reader. On entry and on
every later tick without evidence, `reconcile-pass.sh` advances a
visit-scoped work file by one bounded pass. The agent's only move is to tick
again, and it reads `reconcile/progress` to know why. When the pass
completes, the report exists in context in two forms, its JSON is sealed by
a capture the agent can't write, and the non-overridable gate lets the
workflow into `pick_facts`, which reads `reconcile/report.json` through a
small reader that checks the seal again, so a report altered after the gate
passed, or one reached by skipping the gate, is refused there.

The re-checks and their sources of truth:

| Claim in the record | Re-check | Source of truth | Reported as |
|---------------------|----------|-----------------|-------------|
| A holding's pull request | state, draft flag, head sha, merge state | GitHub pull request, read live | changed with both values, or unchanged |
| A holding's board | every job has a runner name and a non-zero number of steps that ran; no required run missing | the CI board at the verified head (and at the live head if they differ), through the record feature's board check | holds, or fails naming the job or run |
| A holding's branch | ref present, tip equals the pull request head | `git ls-remote` on the repository | branch gone, tip differs, or matches |
| A holding with no pull request | a pull request on its branch, any state | GitHub pull request listing for the branch | appeared (one), ambiguous (several), none |
| A holding marked scoping ahead that has a pull request | whether any changed path lies outside `docs/` | the pull request's file list, paginated and capped | consistent, or flagged as contradicting its mark |
| A worker with no pull request | instance and session present, matched by topic slug; re-read after 30 s on a miss | the workspace manager's listing and the instance directory | found, or not found on this read |
| That worker's unique material | unpushed commits, uncommitted changes, file content not on the default branch | git in each clone of the instance; GitHub contents API for default-branch blobs | listed, nothing unique found, or couldn't be taken |
| A holding bound to a request leg | disposition and result (a result map where the entry point writes one; the engine's terminal status and final state otherwise; a refusal with its reason) | the workflow engine's request store on this host | shown beside the GitHub state, or not verified off-host |
| A merge in flight | every changed file's content on the default branch equals its content at the verified head; a file deleted at the verified head is confirmed only by a not-found on the default branch | GitHub contents API at the default branch and at the verified head, over the pull request's file list | confirmed, or not confirmed with the reason |
| A close in flight | target reads closed | GitHub issue or pull request state | confirmed, or not confirmed |
| A teardown in flight | target absent from two listing reads and from the disk | the workspace manager's listing and the instance directory | confirmed, or not confirmed |
| Any other side effect | none | none | not re-checked |
| A deferral | issue exists, closed with a reason, or carried forward with a reason | the record feature's disposal check, with GitHub for the issue | disposed, or undisposed |
| The predecessor's handoff (discipline scope) | tables re-checked as above; reasoning carried verbatim | `docs/disciplines/<name>.md` on the host repository's default branch | rows labelled with the handoff's date; reasoning present, absent or not recorded |

## Solution Architecture

### The state

The reconcile state in `skills/coordinate/koto-templates/coordinate.md`
becomes:

```yaml
reconcile:
  default_action:
    command: 'env -u BASH_ENV -u ENV "{{PLUGIN_ROOT}}/skills/coordinate/scripts/reconcile-pass.sh" --session "{{SESSION_NAME}}" --session-dir "{{SESSION_DIR}}"'
    capture_stdout_as: RECONCILE_SEAL
    fallback: >-
      The reconcile pass failed. Read its stderr above, fix the cause and
      tick again. Never write any reconcile/ context key yourself.
  gates:
    report_sealed:
      type: command
      command: 'env -u BASH_ENV -u ENV "{{PLUGIN_ROOT}}/skills/coordinate/scripts/coord-verdict.sh" --session "{{SESSION_NAME}}" --session-dir "{{SESSION_DIR}}" --state reconcile --key reconcile/report.json --capture "{{RECONCILE_SEAL}}"'
      timeout: 10
      overridable: false
  transitions:
    - target: pick_facts
      when:
        gates.report_sealed.exit_code: 0
```

No `accepts`, no `polling`, no override edge. The directive tells the agent
to tick again while the gate fails and `reconcile/progress` is set, to read
`reconcile/refusal` and escalate when it's set, and to read
`reconcile/report.md` once the state passes. The directive doesn't
reference `RECONCILE_SEAL`, because a tick that reaches the state without
running the action would stop on an unset capture. The state's name, its
predecessor and its successor are the record feature's; if that feature
names them differently, this block takes its names.

### The pass

```
reconcile-pass.sh            (every child's stdout goes to stderr)
  clear reconcile/refusal and reconcile/progress
  visit = seal helper: seq of the latest entry event into this state
  work file: <session-dir>/coordinate-reconcile/visit.json
    its seq differs from visit -> discard it, remove reconcile/* keys
    its hash differs from the hash in this state's last engine-logged
      pass output -> discard it, start the visit's reads again
  no record yet -> reconcile-read.sh
    none | ambiguous | undeclared | unreadable
      -> write reconcile/refusal, print blocked:<case>, exit 0
  queue = one read per claim (table above), minus those done
  launch reads, up to 4 at once, until 20 s have passed,
    each with its deadline clipped to the time left
    each result -> append fact to work file (atomic rename)
  listing missed and < 30 s since the first listing read
    -> sleep if the wait fits before the 20 s cutoff, else leave queued
  queue not empty -> write reconcile/progress,
    print pending:<visit>:<n>:<sha256 of work file>, exit 0
  facts -> reconcile-report.sh -> report.json + report.md (+ reasoning.md)
  write keys; print reconciled sealed:<visit>:<sha256 of report.json bytes>
```

The pass prints exactly one line, in one of three grammars built only from
characters a koto capture admits: `pending:<seq>:<n>:<64 hex>`,
`blocked:<case>` with `<case>` one of `none`, `ambiguous`, `undeclared`,
`unreadable`, and `reconciled sealed:<seq>:<64 hex>`, the last in the
shape the record feature's check channel defines for every check state
(`<verdict> ... sealed:<seq>:<sha256>`). A test feeds each shape through
koto's capture allowlist. The last seconds of the 30 are kept for building
the report and the context writes; the injected clock tests that the pass
never plans past its budget.

A pass that exits non-zero is an action failure: koto stops the tick with
the fallback and doesn't evaluate the gate, so a broken pass can't slip a
stale report through. `blocked:` and `pending:` exit 0 so the gate, not an
action failure, holds the state; both fail the seal check because neither
matches `sealed:<seq>:<hash>`.

### The gate

The shared verdict gate (`coord-verdict.sh` over `coord-log.sh check`, the
record feature's; their final flags are that feature's) exits 0 only when
all of these hold:

1. The capture has the form `reconciled sealed:<seq>:<64 hex>`.
2. `<seq>` is the seq of the latest event in the session log that entered
   the reconcile state (`transitioned`, `directed_transition` or `rewound`
   with this state as its target).
3. The sha256 of `koto context get <session> reconcile/report.json` equals
   the sealed hash.
4. The report parses and its schema is `coordinate-reconcile-report/v1`.

Any other outcome exits 1, and a read it can't complete exits 2. The koto
gate routes only on 0.

### The pick state's read

The record feature's `pick_facts` state, which runs before `pick`, reads the
report through
`reconcile-report-get.sh`, which this feature ships because it knows the
report's schema. Like every agent-run script in the template, it takes no
sealed token as an argument: it reads the reconcile state's capture from the
session log itself through `coord-log.sh`, checks the report against it with
`coord-log.sh check`, refuses the report when it fails, and names any
`directed_transition` in the run with `coord-log.sh directed-since`. A
directed transition anywhere in the run also blocks the record feature's
write scripts until a restart; the report names it either way.
When pick is reached by `--to` before any pass delivered the capture, koto
itself refuses to run a command that references it, so the workflow stops
on koto's unset-capture refusal instead; either way it stops. This is
detection for the `--to` case in Consequences, not prevention.

### Data flow of one start

1. start (the record feature's) opens or finds the record and transitions
   to reconcile.
2. Tick 1: the pass reads the record and does the first 20 seconds of
   reads; `pending:`.
3. Tick 2, whenever the agent sends it: the pass checks the work file's hash
   against tick 1's logged output and finishes the reads. A listing that
   missed at tick 1 is re-read only once 30 seconds have passed since the
   first read; if the agent ticked sooner, the pass sleeps when the wait fits
   or stays `pending:`. When nothing is left it writes and seals the report,
   the gate passes and the workflow enters pick.
4. pick reads `reconcile/report.json` through `reconcile-report-get.sh`; the
   agent reads `reconcile/report.md` and reports up.

### Rotation handoff

At discipline scope `reconcile-read.sh` also reads the predecessor's
handoff, `docs/disciplines/<name>.md` on the host repository's default
branch, through the record feature's `predecessor_handoff` read (the
read-only half of its rotation close-out; the agent-run close ladder,
`predecessor_close`, is not reconcile's). Its tables join the work queue labelled with the
handoff's heading date. Its reasoning section is copied verbatim into
`reconcile/reasoning.md`; when the section is missing, empty or says the
reasoning wasn't recorded, the report's `reasoning` field says so and no
key is written. No gate names `reconcile/reasoning.md`. A missing handoff
file is reported as a first rotation.

### The contract with the record feature

Two properties of the record feature's reader carry into reconcile
unchanged. The record is adopted only when its author and last editor have
write access to the host repository, so a record anyone else wrote is a
refusal, not a report. And a holding whose pull request lies outside the
scope's repositories, or whose head branch differs from the row's branch,
is refused by the reader's facts; reconcile reports such a row as refused
and doesn't re-check it.

Inbound, reconcile uses four things the record feature ships, named only
in `reconcile-deps.sh`: the record reader (with per-row unparseable results
that reconcile passes into `not_verified[]` with the raw row fenced, apart
from rows that fail reconcile's own validation), the board-property check,
the deferral-disposal check, and the seal helper (the visit's entry
sequence, the last engine-logged output of a state's action, and the
`sealed:<seq>:<hash>` check), shared with the pick state's read and the
dispatch path's teardown gate so there is one reader of the session log.
Three requirements bind that helper as they bind reconcile's own scripts:
it parses the log as typed JSON events with `jq` and never searches its
text; it runs in the scrubbed environment described under Decision 1; and
it exits 0 only on the four conditions under The gate.

Outbound, the record feature's template consumes three things from this
one: the reconcile state block above; the `reconcile/report.json` key with
schema `coordinate-reconcile-report/v1`; and `reconcile-report-get.sh` as
the pick state's way to read it. One requirement goes back the other way:
the template declares `PLUGIN_ROOT` without `rebind`, because a variable a
later `koto init --attach-live` can re-point would let whoever re-attached
choose which pass and gate scripts run.

### Where the follow-ons attach

Liveness would add a check to Decision 4's host read for each worker found,
reporting whether it is making progress. The double-held check would run
beside `reconcile-read.sh`, reading who else has written to the record's
container recently, and report without blocking. Externalised load belongs
to the land state's merges, not to reconcile.

### Files

| Path | Kind |
|------|------|
| `skills/coordinate/scripts/reconcile-pass.sh` | new, the state's action |
| `skills/coordinate/scripts/reconcile-read.sh` | new |
| `skills/coordinate/scripts/reconcile-check.sh` | new |
| `skills/coordinate/scripts/reconcile-report.sh` | new, pure |
| `skills/coordinate/scripts/reconcile-report-get.sh` | new, pick's reader |
| `skills/coordinate/scripts/reconcile-deps.sh` | new, the seam to the record feature |
| `skills/coordinate/scripts/*_test.sh` and `testdata/reconcile/` | new |
| `skills/coordinate/koto-templates/coordinate.md` | the reconcile state filled; the mermaid companion regenerated |
| `skills/coordinate/references/loop.md` | its reconcile section points at the state |
| `skills/coordinate/SKILL.md` | Known Limitations |
| `skills/coordinate/evals/evals.json` | two scenarios |
| `skills/coordinate/requires.tsv` | the tools the scripts call |

## Implementation Approach

1. **The report function first.** `reconcile-report.sh` with its schema and
   tests: sections, phase marks, the seven next-line cases, the waiting
   list, grades and the line bound. It needs no stubs and no record feature.
2. **The re-checks.** `reconcile-check.sh` subcommand by subcommand, each
   with keyed-stub tests: pull request, board (through the seam), branch,
   appeared, files (the scoping-ahead contradiction), host listing with the
   re-read, inventory (live remote refs, a deleted remote branch, a
   squash-merged branch), leg, merge, close, teardown, deferral (through
   the seam).
3. **The record read and handoff.** `reconcile-read.sh` over the record
   feature's reader, with the refusal cases and the handoff variant.
4. **The pass and the seal.** `reconcile-pass.sh`, its use of the shared
   seal helper, and `reconcile-report-get.sh`, tested with a stubbed session
   log and context store: the 20-second cutoff, restart after a kill, a work
   file edited between ticks, a refused environment, the stale-visit reset, and each output line
   through the capture allowlist.
5. **The state.** Fill the reconcile state in the template once the record
   feature's template is on the default branch; template checks, the engine
   test that drives the state through `pending:` to `sealed:`, and the
   agent-wrote-the-key and stale-visit cases.
6. **Docs and evals.** `loop.md`, SKILL.md's Known Limitations, the two
   evals, `requires.tsv`.

Steps 1 and 2 can land before the record feature does; steps 3 to 5 depend
on its reader, board check, deferral check and template.

## Security Considerations

**What reconcile trusts.** The record body is written by an agent and read
back as data. Reconcile never executes any part of it: the side-effect
table's "How to confirm" cell is never run (R14), every value taken from a
row (repository, branch, pull request number, topic, sha) is validated
against a fixed pattern before it reaches a command, and every command is
built as an argument vector, never through `eval` or `sh -c` on row text.
The patterns are the ones `skills/execute/scripts/coord-common.sh` already
uses for repositories, branches, shas and pull request URLs, plus a topic
slug pattern. A row that fails validation is reported as unparseable
(R2), in a fence.

**Paths that don't come from the record.** Two other sources feed commands:
file paths from a pull request's file list (for merge confirmation) and
paths found while walking a worker's clones (for the inventory). Both are
treated like row values. A path containing `..` as a component, a leading
`/`, a NUL or any control character is refused and reported under "not
verified". A path sent to the contents API is percent-encoded per segment
and passed as one argument to `gh api`, never spliced into a shell string.

**Containment inside a worker's instance.** The inventory resolves the
instance path from the listing and then only descends into it: it doesn't
follow symlinks, and it takes a clone only when its real path, its git
directory and its working tree (`core.worktree`) all lie under the instance's
real path; a clone whose `.git` is a symlink is marked unchecked. It skips any
worktree `git worktree list` reports outside the instance, listing it by name
without reading it. A symlink in a clone is never followed: a tracked one is
compared by its link text, an untracked one is listed, not read. The walk is
capped at 20 clones, 200 untracked files per clone and 200 listed items, and
past any cap the report says the inventory was truncated.

**Reads only.** The pass reads the request store with `koto request get`
and the context with `koto context get`, and writes only its own
`reconcile/` context keys and its work file in the session directory; it
reads no permission settings or hooks (R31). It calls `gh` with read
subcommands and `gh api` with GET only, and `git ls-remote` against a
github.com repository only: the record row's for a holding's branch, a
clone's github.com origin for an inventory. Inside a worker's instance it
runs only plumbing reads that run no filter (`config` reads, `rev-parse`,
`cat-file`, `symbolic-ref`, `rev-list`, `merge-base`, `diff --name-only`,
`for-each-ref`, `ls-files`, `ls-tree`, `worktree list`, and `hash-object
--no-filters` over `--stdin-paths` or `--stdin`, never with `-w`, so it
computes hashes without writing an object) and never `git status`. Every
in-clone git command runs as `git --no-optional-locks -c core.fsmonitor= -c
core.hooksPath=/dev/null -c protocol.allow=never`, so it neither refreshes
the worker's index nor runs anything the clone's config names; a file under
a clean filter (LFS, say) hashes unfiltered and reads as unique, which is the
safe direction. Nothing runs `fetch`, `pull`, `push`,
`checkout` or anything that writes refs, objects or the index. It calls
`niwa list` only. The tests assert this over every stub log against an
allowlist of these read verbs.

**The gate's authenticity.** The gate's inputs are a capture the agent
can't set, the session log the engine writes, and a context key whose hash
must match the capture. The agent can't satisfy it through evidence,
context, flags or overrides. It can bypass it with `koto next --to`, which
skips gate evaluation for any declared transition (koto#251); see
Consequences. The gate reads the session log as typed events: it parses
each line as JSON and matches on the event's `type`, `seq` and target
fields with `jq`, never by searching the text, so a context value or a
stream captured into some event's payload can't pose as an entry event.

Two things sit outside what any gate defends, and the design says so rather
than claiming otherwise. Files under the session directory can be edited by
the same user; that is tampering with the engine's storage. The scripts
themselves live under the plugin root, which the same user can also write;
an agent that edits `reconcile-pass.sh` to print a seal for a fabricated
report has changed the tool, not supplied a value to it. Both are the same
class as editing koto's binary. The pass reports the plugin root's placement
the way `/scope` does (inside or outside the repository being worked on),
and the eval for a restart checks that the scripts run from the installed
plugin root.

The environment of the process that runs `koto next` is the third input the
agent controls, and unlike the two above it needs no file edited. The
scrub under Decision 1 closes the variables that change what the scripts
run or where they read (`PATH`, `BASH_ENV`, `ENV`, `LD_PRELOAD`, git and
`gh` overrides). What stays with the account is its credential store: the
`gh` token the scripts use is the same user's, and a user who rewrites it
can point reads at another account. That is the same class as the files
above.

**Private content.** The report goes into context, not to GitHub, so it
never publishes anything. It names workers by topic only. The inventory
lists file paths from a worker's clones into the coordinator's context;
those paths are already on the host and visible to the same user.

**Resource use.** Reads are bounded per call and per pass, run at most four
at once, and are spread across ticks, so a large record costs more ticks,
not a burst of parallel calls on a shared host.

## Consequences

### Positive

- A coordinator can't act on its inherited record without a fresh,
  script-built report, and the report shows which reads failed.
- The hard cases have one implementation each: a merge confirmed file by
  file against the verified head, a board judged by its property, a
  listing miss re-read before anything is concluded.
- The report rules are a pure function, testable without stubs, and the
  reads are testable without the network.
- The seal pattern is reusable: the record feature's verified-head gate has
  the same problem and can capture its head and board the same way.

### Negative

- **`koto next --to pick` skips the gate.** koto 0.13.0 checks only that
  the target is a declared transition; `overridable: false` doesn't apply.
  No gate design in this engine version prevents it, for this state or any
  other.
- The agent ticks more than once in a start with several holdings, and
  each tick shows `pending:` until the pass finishes.
- The seal helper reads the session log's file format for the visit's entry
  sequence and a state's last action output, which koto doesn't document as
  an interface.
- The trust rests on `PLUGIN_ROOT` as set when the session was opened; the
  template declares it without `rebind` so a re-attach can't change it.
- A report can be minutes old by the time pick reads it, since passes read
  at different times.

### Mitigations

- `reconcile-report-get.sh` refuses a report whose hash doesn't match the
  seal and names an entry into pick by `directed_transition`, so a `--to`
  bypass is visible in pick's output. A koto change making `--to` honor
  non-overridable gates would close it; that is koto#251, not worked around
  here.
- The report carries a read time for every holding, and the verify step
  re-reads anything the coordinator is about to act on.
- If koto exposes a state's entry sequence through a documented command,
  the gate switches to it; the log read is one function in the gate script.

## Known Limitations

- **Pull request ownership by login and branch (shirabe#395).** The search
  for a pull request that appeared on a holding's branch can match another
  run's pull request under the same login and branch name. Today that can
  show a false "appeared"; topic-unique branch names keep it rare.
- **The merge-order block is empty (shirabe#396).** The report doesn't
  carry a worker's coordinated merge order; pick and land get it from the
  worker.
- **Scoping pull request bodies fail validation (shirabe#398).** A holding
  scoping ahead can show a failing body-check job on its scoping pull
  request, so its board reads "fails" for a reason unrelated to the work.
- **`--koto-leg` on /deliver and /work-on (shirabe#401).** Until those
  entry points accept a leg, their holdings carry no request id and are
  re-checked through GitHub and the host alone.
- **No wake when a leg resolves (koto#250).** Reconcile runs only when the
  coordinator's session ticks, so a worker's result is noticed at the next
  start or restart, not when it lands.
- **`koto next --to` past a failing non-overridable gate (koto#251).** The
  reconcile gate can be skipped by directing the workflow to pick. Until
  koto refuses that, the interim is detection: the pick state's read
  re-checks the seal and names an entry by `directed_transition`.
