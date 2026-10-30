---
schema: design/v1
---

# DESIGN: Fleet cost emit

## Status

Proposed

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
same capture. That is `docs/designs/current/DESIGN-fleet-cost-capture.md`,
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
