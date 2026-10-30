---
schema: design/v1
status: Proposed
problem: |
  The coordinate skill computes a unit's cost and milestone facts at the end
  of its life: the teardown pass runs `unit-cost.sh capture` on an archive,
  and units removed any other way were left to a detached removal sweep. A
  unit that dies or is reaped outside the pass loses its figures, the sweeps
  piled up into most of a busy host's load, and facts known at dispatch are
  re-derived after the rows that held them are gone. The owner's requirements
  for the replacement are fixed: telemetry sent inline as tools are used, the
  koto session as the only local storage, nothing running on the host to
  collect it, and nothing already done lost.
decision: |
  Four one-time facts under one scope, `unit_cost`, each sent by the script
  that learns it: `dispatched` from the coordinator's dispatch, `session_opened`
  from the shared koto open path, `landed` from the coordinator's merge and
  `retired` from the teardown pass. They carry join keys (the koto request,
  the koto session's name and opaque id, the worker's agent session and niwa dispatch ids, the
  milestone, the scope slug, the pull request), and a reader rebuilds the
  `unit-cost/1` figures by joining them with koto's workflow records, the
  agent runtime's token telemetry and a GitHub read. One helper,
  `scripts/emit-event.sh`, is the only file that may run the shared sender; it
  checks the off switch, a fixed date before which it never sends, and the
  sender's discovery rules, then calls it once under a 3-second bound. The
  capture, the removal sweep and the removals directory are deleted in a
  second step after the baseline week ends.
rationale: |
  Sending each fact at the moment a script that already runs learns it is
  what makes a reaped unit keep everything it sent, with no batch and no host
  job. Re-sending what the workflow scope and the runtime already carry would
  double-count, so the events hold only the coordinator's side of a unit and
  the keys that join the streams. A per-transition kind has no call site and
  a per-session summary is the end-of-run batch the owner ruled out. A date
  constant in the one file that can name the sender makes inertness a property
  of the code, and splitting the retirement on that date means every unit gets
  either an entry or events, never neither.
upstream: docs/prds/PRD-fleet-cost-capture.md
---

# DESIGN: Fleet cost emit

## Status

Proposed

This design supersedes `docs/designs/archive/DESIGN-fleet-cost-capture.md`.
It amends `docs/prds/PRD-fleet-cost-capture.md`: R1, R3 to R5, R12, R12a and
R14 to R16 are withdrawn with the removal capture, R10 and R11 are moot since
no entry is posted, and R2, R6, R7, R8 and R19 take their figures from the
sources below. The PRD's Status section lists each change.

## Context and Problem Statement

The coordinate skill produces a unit's cost and milestone facts at the end of
the unit's life. `skills/coordinate/scripts/teardown-pass.sh` archives a
finished worker and, between the archive and `niwa destroy`, runs
`unit-cost.sh capture`, which reads the archive (koto sessions, verdict
ledgers, transcripts, `teardown.json`), the unit's koto request, the
coordinator's Holdings row or leg key, and GitHub, and posts one `unit-cost/1`
entry into the coordinator's session. A unit niwa removed some other way was
to be picked up later: niwa's on-reap step ran `unit-removed.sh record`,
which wrote a removal record under
`${XDG_STATE_HOME:-$HOME/.local/state}/shirabe/removals` and started a
detached sweep that rebuilt an archive from whatever survived and ran the
same capture. That is `docs/designs/archive/DESIGN-fleet-cost-capture.md`,
shipped by #1120.

Three things are wrong with it.

- A session that dies, is reaped by hand, or is removed outside the pass
  loses its figures unless something reconstructs them afterwards from what
  survived on the host. A batch produced at the end of a run isn't
  reliable: the run has to reach its end, and the files the batch reads have
  to still be there.
- The reconstruction needs jobs on the host. The sweeps piled up until they
  were most of a busy host's load (#1409); #1411 stopped launching them, so
  today a unit removed outside the pass gets no entry at all.
- Facts known early (the dispatch, the milestone, the plan shape) are
  re-derived late, after the rows that held them are gone, which is why the
  capture carries fallbacks through the leg key and the removal record.

This design replaces the end-of-life capture with facts sent while the unit
runs, through a shared event sender that other work is building for every kind
of fleet telemetry (workflow events, cost, pull request data). It defines the
cost and milestone events, their fields and when each fires, and how a reader
gets back the per-unit figures `unit-cost/1` carries. It builds no sender,
channel or endpoint of its own.

### The sender this design calls

The sender's interface is fixed by its own design; this one is written against
it exactly.

- **Discovery.** A tool runs the sender only from one fixed path,
  `$HOME/.local/libexec/fleet/event-sink`, and only when that file and every
  directory above it are owned by the user or by root, none is writable by
  group or others, and the file is not a symbolic link. Otherwise there is no
  telemetry. `FLEET_EVENT_SINK=off` in the environment turns sending off; no
  other value of that variable is read, so a cloned repository's settings
  can't point it at a script of their own. A scratch `HOME` has no sender, so
  test suites stay isolated without doing anything.
- **One event:** `timeout 3 "$HOME/.local/libexec/fleet/event-sink" event
  --scope SCOPE --kind KIND [--at RFC3339] [--carry N] key=value ...`.
  Several (1 to 200): `... send --scope SCOPE [--carry N] < records.ndjson`,
  one JSON object per line.
- **Result.** An exit code and one stdout JSON line: 0 posted, 1 usage error,
  2 consent off and nothing sent, 3 dropped after one bounded try (no retry,
  no spool), 4 posted with some records or fields invalid. Callers ignore it
  and never fail, retry or block on it, and wrap every call in `timeout 3`.
- **Allow-list.** The sender sends only a scope, kinds and fields listed for
  it; an unknown kind isn't sent and an unlisted field is dropped. The rows
  are added outside this repository from the names this design gives.
- **Field shapes.** Every field is scalar and is one of: `id`
  (`[A-Za-z0-9._:-]{1,128}`), `name` (`[A-Za-z0-9._:/@-]{1,128}`), `pr`
  (`github.com/<owner>/<repo>#<n>`), `bool`, or `int` (0 to 2^63-1). No
  floats, free text, arrays or nested objects.
- **Stamps.** The sender adds the event time, the host, the definitions
  version, pricing, the agent session id, niwa's dispatch id and workspace
  (from the environment niwa exports) and its own version to every record, so
  callers don't send those.
- **Consent.** Sending is gated on the host's existing consent, checked at
  each send, with no new prompt.
- **Not before 2026-11-09T02:00Z.** A baseline week is protected: no tool
  calls the sender before then.

Per-request tokens and cost already leave each session through the agent
runtime's own inline telemetry. Workflow events (koto's state entries) travel
through the same sender under their own scope. Pull request events (opened,
pushed) belong to a separate pull request scope whose helper and call sites are
other work. So cost and milestone events carry join keys, not recomputed
totals.

## Decision Drivers

These four are the owner's requirements for #1410, not options to weigh:

- **Inline and synchronous.** Telemetry is sent as the session's tools are
  used: never batched, never deferred to the end of a run.
- **The koto session is the only local storage.** No other journal, spool,
  archive or record of telemetry on the host.
- **Nothing runs on the host to collect, aggregate or forward.** No sweeps,
  timers, daemons or detached jobs.
- **Nothing already done is lost.** A session that dies or is reaped keeps
  every figure it already sent.

And from the sender and its owner:

- Events are increments or last-value-wins with a sequence number, never
  partials that a final total would double-count, and number in the tens per
  unit, not per tool call.
- Field names in shirabe are neutral: no `fleet.` prefix, no vendor, not an
  existing attribute name or one the agent runtime emits natively.
- `failing_heads` and `dispatch_to_green_min` keep coming from the GitHub
  read they come from today, not from the sender.
- Code may land before 2026-11-09T02:00Z but must stay inert until then.
- The design names no telemetry vendor, measured figure or private path.

## Considered Options

### Decision 1: Which events exist, where they fire, and how a unit's figures come back

`unit-cost/1` is one JSON block per unit, computed from an archive. Once
nothing is computed at the end, each of its figures has to be rebuilt from
facts sent while the unit ran, and the only facts this design may add are the
ones no other stream already carries. Three streams exist or are being built
beside this one: the agent runtime's per-request token and cost telemetry
(which niwa already labels with the worker's dispatch id and lineage), koto's
workflow records (`session_started`, `state_entered`, `terminal` and the review
records, under the workflow scope), and the pull request scope's opened and
pushed events. What's missing is the coordinator's side of a unit: that it was
dispatched, for which topic, milestone and record, which koto sessions belong
to it, which pull request the coordinator merged for it, and how it left.

Reading the code settled where those facts are known. `dispatch-worker.sh`
creates the koto request and the leg key and runs `niwa dispatch`, so it knows
the topic, the Unit tag, the request id, the leg, the entry point, the repo and
the coordinator's session; it doesn't know niwa's dispatch id until it reads
niwa's listing. `scripts/koto-open.sh` is the open path shared by
`skill-session.sh open` and every skill's `*-open.sh`. Agents call `koto next`
directly, so no shirabe script runs at a transition. `land-merge.sh` merges a
unit's pull request. `teardown-pass.sh` runs the capture today.

Key assumptions:

- The workflow scope carries koto's `state_entered`, `terminal`, `cancelled`
  and review records, keyed by koto's opaque session id (the `session_id` in
  the session's header) and koto's run id, never by the session name. The
  pipeline's owner confirmed this. The code-round review records join that
  scope with work the pipeline owns; until they do, panel rounds are not
  recoverable and nothing else changes.
- The runtime's telemetry gives a subagent's requests its parent session's
  id, so a unit's worker row is one session id.
- A script can read a session's opaque id through koto's supported interface:
  `koto session list --execution-dir <dir>` prints each session under that
  directory with its `session_id`, and the row whose `id` is the session's
  name gives it. Nothing reads koto's files directly.

#### Chosen: four lifecycle facts under one scope, joined at read time

One scope, `unit_cost`, with four kinds. Each is a one-time fact sent from a
script that already runs at the moment the fact becomes known: `dispatched`
when the coordinator confirms a worker launched, `session_opened` each time a
shirabe skill opens a koto session, `landed` when the coordinator merges a
unit's pull request, and `retired` when the teardown pass removes the unit.
A unit sends one `dispatched`, one `retired`, one `landed` per merged pull
request and one `session_opened` per koto session, about 5 to 20 events.
Nothing is a running total, so nothing double-counts.

The fields are the join keys and the facts only the coordinator holds. Two
were added after reading the dispatch code: `dispatched` and `retired` are
sent by the coordinator, so the sender stamps them with the coordinator's own
session and dispatch ids, and a worker that dies before it opens any koto
session would otherwise have nothing linking it to its own token rows. They
carry the worker's agent session id and, when known, its niwa dispatch id.

Every event that names a koto session carries both its name and its opaque
session id. The workflow records are keyed by the id alone, so the id is what
joins a `session_opened` to a session's state entries; the name stays because
it is what the coordinator's own records and the koto request use.

Per-state time, session spans and sessions without `done` come from the
workflow records, joined on the koto session id. Panel rounds come from a koto
`code-round` review record, which `panel-scope.sh --record` starts writing for
each round it records, so they travel as workflow records too. Tokens come
from the runtime's telemetry. Green, merge and failing heads come from GitHub,
read by the reader with today's definitions.

#### Alternatives Considered

**A per-transition kind sent by shirabe.** One event at each koto transition,
carrying the time spent in the state just left, so state time would sit under
the cost scope. Rejected: shirabe has no call site, since agents call `koto
next` themselves. The only hook koto offers is a `default_action` on every
state of every template, which has a fixed 30-second timeout and stops the
tick when it fails, so a slow sender could hold a worker in place. It would
also send again what the workflow scope already carries, at one event per
transition.

**A per-session summary at `done`.** One event per koto session when it
reaches `done`, holding its state totals, rounds and token counts. It is the
smallest number of events and the closest to today's entry. Rejected: a
session that dies or is reaped before `done` sends nothing, which is the
failure this design exists to remove, and its totals would double-count
against the runtime's and the workflow scope's own increments.

**Keeping a slim end-of-life entry beside the events.** The teardown pass
keeps writing a reduced `unit-cost` entry, so today's readers keep working
unchanged. Rejected: a unit removed outside the pass still gets no entry, the
pass stays coupled to the archive's layout, and two sources would claim the
same figures.

**Cumulative counters, last value wins.** Re-send a unit's running totals with
a sequence number at each step, so the latest record is always the whole.
Rejected: it needs the same per-transition call site that doesn't exist, and
it duplicates the workflow scope's own facts.

**A `panel_round` kind under the cost scope.** `panel-scope.sh` sends a cost
event per round. Rejected: koto already defines a `code-round` record for
exactly this, kept in the koto session's own log and carried by the workflow
scope, so a cost kind would split review facts across two scopes.

### Decision 2: Retiring end-of-life capture and landing the sender call inert

The end-of-life machinery is spread across scripts, the skill's wake
guidance, an eval, a workspace's on-reap command and a directory on each
host. Since #1411, `unit-removed.sh record` and `start` do nothing but print
a line, and `sweep` runs only by hand. The sender must not be called before
2026-11-09T02:00Z. If the teardown capture went before then, units torn down
in between would get neither an entry nor events.

Key assumptions:

- The baseline week before the cutoff is measured with today's teardown
  capture still running, so the capture stays until sends are live.
- Removal records left on hosts are few and old. None has been written since
  #1411.

#### Chosen: a two-step retirement with one date-gated helper

One helper, `scripts/emit-event.sh`, is the only file in the repository that
names the sender's path or `FLEET_EVENT_SINK`. Call sites run it as a child
process and ignore everything it does. It stops, exiting 0, at the first of:
`FLEET_EVENT_SINK=off`; a clock reading before 2026-11-09T02:00Z, or one it
can't read; a sender that fails the discovery checks. Otherwise it runs the
sender once under a 3-second bound and exits 0. The date is a constant in the
helper; no variable, argument or setting moves it, so no repository or
workspace setting can start sending early. A static check fails the build if
any other file names the sender's path or variable.

Step one lands now, while sending is inert: the helper and its test, every
call site, and the removal of what already does nothing (the wake line, the
teardown pass's sweep start, the coordinator eval that expects it, and the
on-reap line in the reference). Step two lands after the cutoff, once a person
has seen one real unit's events arrive: the capture, `unit-removed.sh`, the
removals directory's code and the teardown pass's capture step are deleted,
and the GitHub read survives as a read-only tool for readers.

Removal records already on hosts are left alone. Until step two ships, a
person who wants those units' entries runs today's `unit-removed.sh sweep` by
hand; after it ships, the records are inert and the person deletes the
directory by hand. Nothing in shirabe reads, converts or deletes them on its
own.

#### Alternatives Considered

**Keep a by-hand sweep for good.** Keep `unit-removed.sh sweep` and `unit-cost.sh
capture` as a manual drain, so any host can still turn a removal record into
an entry. Rejected: it keeps the whole reconstruction stack (archive rebuild,
coordinator resolution, post lock, their suites) alive to serve a closed set of
old records, and a manual drain is one wake line away from becoming the
automatic sweep that overloaded hosts in #1409.

**An automatic one-time drain on upgrade.** Run the sweep once from the
teardown pass or `koto-open.sh`, or convert old records into events at the
cutoff. Rejected: it is a host job that collects and forwards, and a backfill
is a deferred batch. Most old records would end as "no coordinator" anyway.

**Delete removal records automatically on upgrade.** Rejected: code that
removes a user's files on the host, and it takes away the by-hand drain from
anyone who wanted it.

**A switch in the workspace configuration.** An environment variable a
workspace sets to turn sending on. Rejected: the sender reads no variable but
`FLEET_EVENT_SINK=off`, precisely so that repository or workspace settings
can't steer sending; a second switch would undo that, and turning it on would
need a person at 02:00Z.

**Release timing instead of a date gate.** Hold the call sites, or ship a
helper that always returns, until a release after the cutoff, then remove
everything in one change. Rejected: inertness would rest on merge and release
timing rather than on code. A slipped release, or the deletion landing first,
leaves units with neither an entry nor events, and the call sites go untested
until the day they go live.

**A sender call at each site.** Each call site runs the sender itself.
Rejected: the discovery checks and the date gate would be copied into five
scripts, and one missed copy breaks inertness.

## Decision Outcome

A unit's cost and milestone facts leave the host while the unit runs, each
from the script that learns it, through one helper that refuses to send
before the baseline week ends. The coordinator sends `dispatched` when a
worker starts and `landed` and `retired` as it merges and removes it. Every
shirabe skill session sends `session_opened` as it opens. koto's own records
carry the state times and review rounds, the agent runtime carries the tokens,
and GitHub keeps the head and run history the failing-head count reads. A
reader joins them on the koto request id and the worker's niwa dispatch id
and gets back the figures `unit-cost/1` carried, with the differences listed
under Solution Architecture. The end-of-life capture, the removal sweep and
the removals directory go in a second step once the events are live.

How each owner requirement is met:

| Requirement | How |
|---|---|
| Sent inline and synchronously as tools are used | Each event is sent by the script that runs at that moment (dispatch, open, merge, teardown), in the same process, before the script returns. Nothing is queued for later. |
| The koto session is the only local storage | The helper writes nothing. The one new local write is the `code-round` record, which lives in the koto session's own log. The removals directory stops being written in step one's release (it already isn't, since #1411) and its code goes in step two. |
| Nothing runs on the host to collect, aggregate or forward | No sweep, timer, daemon or detached job exists after step one: the wake line and the teardown pass's sweep start are deleted, and the helper runs the sender in the foreground and waits for it. |
| A session that dies or is reaped loses nothing already done | Every event is sent at the moment its fact exists, so a unit removed at any point keeps every event sent before it. Nothing is held back to be sent at the end. See Data Flow. |

## Solution Architecture

### Overview

```
coordinator session                     worker and nested sessions
-------------------                     ---------------------------
dispatch-worker.sh --dispatched-->      koto-open.sh --session_opened-->
land-merge.sh      --landed----->       (koto's own records: state_entered,
teardown-pass.sh   --retired---->        terminal, code-round)
        |                                       |
        +------ scripts/emit-event.sh ----------+
                 (off switch, date gate, discovery checks, timeout 3)
                         |
               $HOME/.local/libexec/fleet/event-sink
```

The reader joins four streams: this scope, the workflow scope, the runtime's
token telemetry and the pull request scope, and reads green, merge and
failing heads from GitHub.

### Components

**`scripts/emit-event.sh`** (new). Takes the sender's `event` form unchanged
(`event --scope S --kind K [--at T] key=value ...`). It checks, in order, and
exits 0 at the first that fails:

1. `FLEET_EVENT_SINK` is not exactly `off`. No other value is read.
2. `date -u +%s` prints an integer at or after 1794189600
   (2026-11-09T02:00:00Z). An unreadable clock counts as before.
3. `$HOME/.local/libexec/fleet/event-sink` is a regular file, not a symbolic
   link, and executable; it and every directory above it up to `/` are owned
   by the user's uid or by 0, and none is writable by group or others.
   Ownership and mode come from `ls -ldn`, which reads the same on macOS and
   Linux.
4. Each `key=value` value is matched to its field's shape (id, name, pr, int
   or bool, from a table in the helper that mirrors the field table below);
   a value that fails, or that starts with `--`, is dropped and the rest are
   sent.

Then it runs the sender with `timeout 3` (or the repository's watcher-based
deadline where `timeout` is missing), discards its output and status, and
exits 0. It never retries, spools or backgrounds anything. Callers run it as
`bash "$root/scripts/emit-event.sh" event ... </dev/null >/dev/null 2>&1 ||
:`, never by sourcing it, so a fault in it can't reach the caller's shell.

**Call sites** (changed), each adding one helper call:

- `skills/coordinate/scripts/dispatch-worker.sh`, in its confirm step, once
  niwa's launch is confirmed: `dispatched`. A re-leg that launches no worker
  sends nothing.
- `scripts/koto-open.sh`, after koto reports `opened=new`, `attached` or
  `replaced`: `session_opened`. work-on's plain `koto init` path, which
  doesn't go through `koto-open.sh`, sends the same event. Before sending,
  it reads the session's opaque id with `koto session list --execution-dir
  <the session's execution directory>`, taking the row whose `id` is the
  session's name; the coordinator's three call sites read their own
  session's id the same way. A failed read leaves `unit.koto_session_id`
  out and sends the rest.
- `skills/coordinate/scripts/land-merge.sh`, after the merge succeeds:
  `landed`.
- `skills/coordinate/scripts/teardown-pass.sh`, where step 4a runs the
  capture today, after the archive and before `niwa destroy`: `retired`.
- `skills/work-on/scripts/panel-scope.sh --record`: a koto `code-round`
  review record per round it records (`koto review record <session>
  code-round --round <n> --head <head>`). This is a workflow record, not a
  cost event; it is listed here because the panel-round figure depends on it.

**`skills/coordinate/scripts/pr-heads.sh`** (new in step two, from code
already in `unit-cost.sh`). Read-only: for one pull request it prints its
heads, green time, merge time and failing-head count by today's definitions
(per-head run reads, every attempt, the floor rule and its reasons). A reader
runs it by hand; nothing sends its output.

**`skills/coordinate/references/unit-cost.md`** (rewritten). Becomes the
event reference: the kinds and fields, the join below, the figures that
changed meaning, and a short section on reading `unit-cost/1` entries written
before step two.

### Key Interfaces

Scope `unit_cost`. Fields are written exactly as below; the sender renames
them on the way out. Shapes are the sender's: `id` is `[A-Za-z0-9._:-]{1,128}`,
`name` is `[A-Za-z0-9._:/@-]{1,128}`, `pr` is `github.com/<owner>/<repo>#<n>`.

| Field | Shape | Meaning |
|---|---|---|
| `unit.request` | id | the koto request the dispatch created; the unit's key |
| `unit.leg` | name | the request leg the worker binds |
| `unit.topic` | name | the dispatch topic |
| `unit.scope_slug` | name | the coordinator's scope slug |
| `unit.koto_session` | id | a koto session's name: the coordinator's on `dispatched`, `landed` and `retired`, the opened one on `session_opened` |
| `unit.koto_session_id` | id | the same session's opaque koto session id, the key the workflow records carry, read with `koto session list --execution-dir`; absent when that read fails |
| `unit.requested_at` | int | the koto request's creation time, in Unix seconds |
| `unit.parent_session` | id | the opened session's koto parent, when it has one |
| `unit.roadmap` | name | `ROADMAP-<name>` on a roadmap record; absent on a discipline record |
| `unit.milestone` | name | the Unit cut at its first `: `, each character outside the `name` alphabet written as `_` (`Feature 4` is `Feature_4`) and cut at 128 characters; absent when the Unit is an issue reference or has no tag shape |
| `unit.entry_point` | name | the skill the worker was dispatched to (`work-on`, `deliver`, ...) |
| `unit.repo` | name | the holding's repository, `owner/repo` |
| `unit.template` | name | the opened session's koto template name |
| `unit.mode` | name | on `dispatched`, the Holdings row's mode; on `session_opened`, work-on's entry mode (`plan_backed`, `issue_backed`, `free_form`) |
| `unit.pr` | pr | a pull request |
| `unit.outcome` | name | on `session_opened`, `new`, `attached` or `replaced`; on `retired`, the sealed verdict's outcome word |
| `unit.worker_session` | id | the worker's agent session id, as niwa reports it |
| `unit.worker_dispatch` | id | the worker's niwa dispatch id, when the sending script has read it |

| Kind | Sent by, when | Fields |
|---|---|---|
| `dispatched` | `dispatch-worker.sh` confirm step, in the coordinator, once niwa's launch is confirmed; the event time is the send time | request, requested_at, leg, topic, scope_slug, koto_session, koto_session_id, roadmap, milestone, entry_point, repo, mode, worker_session, worker_dispatch |
| `session_opened` | `koto-open.sh` and work-on's plain init, in the opening session | koto_session, koto_session_id, parent_session, template, request, leg, topic, mode, outcome |
| `landed` | `land-merge.sh` after a merge, in the coordinator | pr, topic, scope_slug, koto_session, koto_session_id, request |
| `retired` | `teardown-pass.sh` before `niwa destroy`, in the coordinator | topic, request, koto_session, koto_session_id, worker_session, worker_dispatch, pr, outcome |

Every field is optional on the wire: a value the sending script doesn't have,
or one that fails its shape, is left out, and the reader treats it as not
recoverable. The sender adds the event time, the host, the sending session's
agent session id, niwa dispatch id and workspace, so none of those is a field.

### Data Flow

A unit's life, and what a removal at each point keeps:

1. The coordinator dispatches: `dispatched` is sent. A unit removed after
   this keeps its dispatch time, topic, milestone, record and the link to its
   worker's session.
2. The worker opens its first koto session: `session_opened` is sent, and
   koto's records start flowing under the workflow scope. The runtime's token
   telemetry has been flowing since the worker's first request. A unit reaped
   now keeps all of that up to its last request and its last state entry.
3. Nested skills open their own sessions: each sends `session_opened`, stamped
   with the same niwa dispatch id. Each review round writes a `code-round`
   record as it is recorded.
4. The worker opens pull requests: the pull request scope sends them, stamped
   with the worker's ids.
5. The coordinator merges: `landed` is sent for each pull request.
6. The coordinator tears the unit down: `retired` is sent. A unit removed any
   other way (a hand removal, a reap) never sends `retired`, and a reader
   reads it as still running or as removed outside the pass; every figure
   above it stands.

At no point does a figure wait for a later step to be computed or sent. The
GitHub figures don't live on the host at all: they are read from GitHub when
someone reads the unit.

### Recovering the per-unit figures

The unit's key is `unit.request` from `dispatched`. The worker's niwa dispatch
id, W, comes from that event's `unit.worker_dispatch`, else `retired`'s, else
the dispatch id stamped on a `session_opened` that carries the same
`unit.request`, else the runtime rows of `unit.worker_session`. The unit's
koto sessions are the `unit.koto_session_id` values of the `session_opened`
events stamped with W, and their state entries and review records are the
workflow records with those ids; its tokens are the runtime rows that carry W.

| `unit-cost/1` field or figure | New source | Same as today? |
|---|---|---|
| `topic`, `record` | `dispatched`: topic, scope_slug, roadmap, repo | Yes |
| `milestone` | `dispatched`: milestone, roadmap | Mostly: fixed at dispatch, alphabet mapped |
| `unit` (the full tag) | not sent | No: free text has no field shape |
| `plan_shape` | `session_opened`: template (`execute` is `single-pr`, `execute-coordinated` is `coordinated`) and work-on's mode (`plan_backed` is `multi-pr`, else `issue`) | Mostly; see below |
| `dispatch` | `dispatched`'s `unit.requested_at`, else its event time (the confirmed launch) | Yes when the request time arrives; else a few seconds later than today's |
| `"niwa.dispatch.id"` | W | Yes |
| `pulls` via holding | `landed`: pr, then `pr-heads.sh` for merge commit and time | Yes |
| `pulls` via session, `opened` | the pull request scope's opened events stamped W, then GitHub for state | No; see below |
| `dispatch_to_green_min`, `failing_heads` | `dispatched`'s time and `pr-heads.sh` on the `landed` pull requests | Yes, the GitHub read as today |
| `dispatch_to_merge_min` | `dispatched`'s time and GitHub's merge time | Yes |
| `writing_code_min`, `review_min`, shares | workflow `state_entered` in work-on sessions under W, cut at the first `done` | Yes |
| `summed_session_span_min`, `minutes_per_unit`, `sessions[]` | workflow records per koto session under W | Yes |
| `sessions_without_done` | work-on sessions under W with no `done` entry | Yes once `retired` arrived; provisional before |
| `panel_rounds` | workflow `code-round` records per session | Yes, except a round that ran no seat |
| `tokens.worker` | runtime rows of `unit.worker_session` | Classes and sums yes; `messages` becomes a request count |
| `tokens.nested` | runtime rows under W from other sessions | Close; relocated copies no longer exist to dedupe |
| `key`, `captured_at`, `dispatch.jobs` | no archive: the unit is named by its request id, `retired`'s time stands in for capture | No |
| `complete`, `missing` | the reader, from which joins came back | Only `no source` remains |

Four figures can't be recovered the same way. Credit and `opened` move from
today's branch-and-link test over transcripts to "the open was sent from a
session stamped W", which is better evidence but a different rule, and until
the pull request scope ships only the holding's own pull requests (`landed`)
are known. A `/deliver` that dies after `/scope` resolves but before its first
execute or work-on session opens reads plan shape `none`, because its
`plan_execution_mode` is set by a koto context assignment no script sees. The
milestone is fixed at dispatch, so a Holdings row re-tagged later isn't
reflected. And a review round that ran no seat writes no `code-round` record,
where the verdict ledger counted it.

### Readers of `unit-cost/1`

No program reads `unit-cost/1`. Its readers are `unit-cost.sh`'s own duplicate
check, the `jq` recipes in `references/unit-cost.md`, and the suites'
fixtures. Entries already in coordinators' sessions stay where they are, and
the `cost` entry kind stays in `state-entry.sh` so they keep listing and
reading with today's recipe. No new `unit-cost/1` entry is written after step
two; the schema is frozen, with no `/2`. A reader joining history with events
treats the old entries as a separate source that ends at step two's release.

### Hosts holding removal records

A host may still hold records under
`${XDG_STATE_HOME:-$HOME/.local/state}/shirabe/removals` from before #1411.
Nothing in shirabe touches them, at upgrade or ever. Until step two ships, a
person who wants those units' entries runs `unit-removed.sh sweep` once by
hand with a token, which posts `unit-cost/1` entries into the dispatching
coordinator's session and sends nothing. Step two's release notes say the
records are inert and the directory (records, `removals.log`, lock files) can
be deleted by hand. The records hold no figure that was ever sent, so
leaving or deleting them loses nothing already done.

## Implementation Approach

### Step one: the helper and the call sites, inert

Lands any time; sends nothing before 2026-11-09T02:00Z.

- `scripts/emit-event.sh` and `scripts/emit-event_test.sh`. The test builds a
  scratch `HOME` under a mode-0700 parent that passes the checks, installs a
  fake sender that logs its arguments, and puts a stub `date` first on
  `PATH`. Cases: one second before the cutoff (no call), at and after it (one
  call, exact arguments), `FLEET_EVENT_SINK=off` (no call),
  `FLEET_EVENT_SINK` set to a path (ignored, call made), a symlinked sender or
  a group-writable parent (no call), no sender (no call), a hanging sender
  (returns in about 3 seconds with 0), sender exits 1 to 4 (helper exits 0),
  an unreadable clock (no call), a value outside its shape (field dropped).
- A static check that fails when any file but the helper and its test names
  `libexec/fleet/event-sink` or `FLEET_EVENT_SINK`.
- The call sites: `dispatch-worker.sh`, `koto-open.sh` and work-on's plain
  init, `land-merge.sh`, `teardown-pass.sh` (`retired` beside step 4a, which
  keeps running), each with a suite case asserting the helper's arguments
  through a stubbed helper.
- `panel-scope.sh --record` writes the `code-round` record.
- Removals of what already does nothing: the coordinator's wake line
  (`skills/coordinate/SKILL.md`), the teardown pass's sweep start on exit and
  its `TEARDOWN_SWEEP` setting, the coordinate eval
  `a-wake-starts-the-removal-sweep` (replaced by one asserting a wake runs and
  starts nothing for a removed unit's cost), the `requires.tsv` on-reap row,
  and the on-reap configuration in `references/unit-cost.md`. SKILL.md's
  on-reap sentence says instead that a unit's facts are sent as it runs.
- Workspaces drop shirabe's line from their `[session.on_reap]` command. That
  is a workspace configuration change outside this repository; the line
  already does nothing, and its `-x` guard keeps it harmless if it stays.

### Step two: retire the capture, after the cutoff

Merges after 2026-11-09T02:00Z, once a person has seen one real unit's events
arrive.

- `pr-heads.sh` extracted from `unit-cost.sh` with its tests.
- `unit-cost.sh` deleted with `unit-cost_test.sh`, `unit-cost-on_test.sh` and
  their fixtures.
- `unit-removed.sh` deleted with `unit-removed_test.sh`, its
  `check-skill.tsv` row and the sweep case in `newest-member_engine_test.sh`.
- `archive-common.sh`'s removal helpers deleted (`ac_removals_dir`,
  `ac_removal_for_path`, the reap-key pattern, the post lock); the collection
  helpers the teardown pass uses stay.
- `teardown-pass.sh` step 4a and `TEARDOWN_CAPTURE_SECS` deleted; `retired`
  stays. SKILL.md drops the two-minute capture from the pass's timing, and the
  archive README stops naming `unit-cost.json`.
- `references/unit-cost.md` rewritten as the event reference.

### Follow-up work

Not filed by this design; each is a candidate issue:

1. The helper, its test and the static check.
2. The four call sites and the `code-round` record, with their suite cases.
3. Step one's removals (wake line, sweep start, eval, requires row, reference
   text).
4. Step two's retirement and `pr-heads.sh`, gated on the cutoff and on one
   unit's events seen.
5. The reference rewrite.
6. A reader recipe for the join, once the backend's query surface is settled.

The allow-list rows for the scope, kinds and fields are added outside this
repository from the Key Interfaces tables.

## Consequences

### Positive

- A unit removed at any point keeps every fact already sent; no figure depends
  on the unit reaching teardown.
- No host job exists: the sweep, its locks and its log go, and the teardown
  pass's cost step drops from a 120-second capture to one 3-second send.
- The milestone, dispatch and plan shape are sent when they are known, so the
  leg-key and removal-record fallbacks go.
- Tokens come from the runtime's own per-request telemetry, so the transcript
  deduplication rules and the relocated-copy problem go with the archive read.

### Negative

- Reading a unit becomes a join across four streams and a GitHub read,
  where today it is one JSON block in the coordinator's session.
- Credit and `opened` depend on the pull request scope, which is other work;
  until it ships, a unit's pull requests are only the ones the coordinator
  landed.
- A few figures change meaning: plan shape for a `/deliver` that dies early,
  a milestone re-tagged after dispatch, rounds that ran no seat, and the
  archive-only fields.
- Panel rounds and state times depend on the workflow scope carrying koto's
  records.
- Two changes instead of one, and the date gate stays in the helper as dead
  code after the cutoff until a cleanup removes it.
- Every send can add up to 3 seconds to the script that makes it.

### Mitigations

- `references/unit-cost.md` documents the join, each figure's new source and
  every changed meaning, so a reader doesn't rediscover them.
- Old entries stay readable and are clearly frozen, so the series has a known
  seam at step two's release.
- If the workflow scope leaves out review records, only panel rounds are
  affected, and they are added there rather than under this scope.
- The send bound is fixed and a unit sends tens of events, so the added time
  per unit is small and never blocks a step on the sender's answer.
