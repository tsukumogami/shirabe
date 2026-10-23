---
schema: design/v1
status: Proposed
problem: |
  The coordinate skill writes a dispatched unit's `unit-cost/1` entry only in
  its teardown pass. A unit removed by hand or by a reap never gets one, an
  entry for a unit already removed carries a null dispatch id, the milestone is
  lost with the Holdings row, the session store posts the entry on the unit's
  own pull request, and failing heads are counted from at most 300 runs, so the
  fleet's cost per merged pull request by plan shape covers a minority of it.
decision: |
  Capture on niwa's removal: the workspace's on-reap command runs
  `unit-removed.sh record`, which writes a removal record keyed by the
  dispatch id and starts a detached sweep. The sweep finds the dispatching
  coordinator through the unit's koto request, builds a removed-mode archive
  with the collection code it now shares with the teardown pass, and runs
  `unit-cost.sh capture`. The capture dedupes by dispatch id under a host lock,
  takes the dispatch id and milestone from the removal record and the dispatch
  leg key when niwa and Holdings no longer have them, lists open pull requests
  in a new `opened` key, reads runs per head until green, and keeps entries
  off the unit's items unless `SHIRABE_PR_INTEGRATION=on`.
rationale: |
  niwa already runs one workspace command at every removal it makes, with the
  dispatch id, so hooking it reaches every removal path without a koto or niwa
  change; its short bound forces the record-then-detach split. Sharing the
  pass's collection code keeps the two captures' figures identical. The koto
  request and the leg key are the coordinator-side facts that outlive both the
  instance and the holding. A per-head runs read is the only one whose
  completeness can be decided head by head.
upstream: docs/prds/PRD-fleet-cost-capture.md
decision_provenance: inline-resolved
---

# DESIGN: Fleet cost capture

## Status

Proposed

Six decision questions were resolved inline under `/scope`. The reasoning that
survived the decision reports is carried in Considered Options below. This
design amends one choice of `docs/designs/current/DESIGN-coordinator-record-teardown.md`
(Decision 2): a cost entry is no longer posted on the pull request it concerns
by default.

## Context and Problem Statement

`skills/coordinate/scripts/teardown-pass.sh` archives a finished worker and,
between the archive and `niwa destroy`, runs `unit-cost.sh capture`, which
computes the unit's figures from the archive and posts one `cost` entry
through `record-append.sh`. Nothing else in the skill ever captures a unit.

Units leave the host in other ways. A coordinator whose pass refuses a unit
(a pull request that will never merge) archives and removes it by hand; a
person deletes finished sessions and `niwa reap` reclaims their instances; a
coordinator told to remove workers in the same pass as their merge does it
with `niwa destroy` directly. None of those reaches step 4a. Of what does
survive a removal, niwa's own documentation and source settle the parts this
design leans on: `niwa destroy` removes the instance directory, `claude rm`
removes `~/.claude/jobs/<id>/` but keeps the transcripts under
`~/.claude/projects/`, and niwa touches nothing under `~/.koto`, so the unit's
koto sessions and its koto request are still on the host.

niwa (since #408 in that repository) runs a workspace-declared
`[session.on_reap]` command once for each session it removes: at `niwa
destroy`, at `niwa reap`, and in the reaps `niwa dispatch`, `niwa create` and
`niwa watch` run first. It runs the command under `/bin/sh -c` from the
workspace root, in its own process group, with only `PATH`, `HOME`,
`NIWA_REAP_KEY` (the dispatch id for a dispatched session), `NIWA_SESSION_ID`,
`NIWA_INSTANCE_PATH` and the names the table's `env` lists. Each run has a
10-second default timeout inside a 30-second budget for the whole step; niwa
kills the group only on timeout, keeps a session's mapping until a run
succeeds, and repeats a failed run at later reaps up to ten times.

Four faults sit inside the capture itself:

- `"niwa.dispatch.id"` comes from `niwa list` at teardown
  (`teardown-handoff.sh`), so the pass's removed mode writes it null.
- The milestone is cut from the Holdings row whose Worker is the topic
  (`record-holding.sh --read`); once the unit is retired there is none.
- On the session store the entry goes `--on` the holding's pull request, else
  the Unit's issue (`unit-cost.sh`, the destination block), which puts it on a
  review thread the repository's maintainers own.
- Failing heads come from one `gh run list --branch <b> --limit 300`; a long
  branch's older heads get no runs, read as `none`, and the short count is
  reported `measured` (#1093).

The PRD's terms (unit, coordinator-dispatched, scope slug, live run, removal,
removal record, record, credit's conditions, head, floor) are used here as it
defines them.

## Decision Drivers

- Every removal path the PRD names (R1) must lead to an entry with no step run
  by hand, and none of them may need a koto or niwa change.
- An entry after a removal must compute the same figures as the pass (R2), from
  the same collection rules.
- niwa's on-reap bound (10 seconds a run, 30 a step) is far below a capture's
  120, and the command must never change niwa's outcome (R15).
- One entry per unit (R5), in both orders and when two captures overlap.
- The dispatch id and milestone must come from facts that outlive the instance
  and the holding (R4, R6).
- Placement: nothing on the unit's items by default (R10, R13), one workspace
  switch to restore it (R11).
- The capture's untrusted-input discipline holds for every new input (R17), and
  the schema stays `unit-cost/1` (R18).
- The coordinator's record scripts and dispatch path are being reworked by
  another effort; this design should touch them as little as it can and name
  every file it does.

## Considered Options

### Decision 1: What triggers and runs the capture after a removal

Resolved inline.

**Chosen: the on-reap command records the removal and starts a detached sweep.**
The workspace's on-reap command runs `unit-removed.sh record`. It validates the
three `NIWA_*` values, writes a removal record named by the dispatch id, starts
`unit-removed.sh sweep` in a new session with its streams closed, and exits 0,
all within a second. The sweep, holding one host lock, captures every kept
record. A record the sweep can't capture yet stays, and the next removal's
sweep tries it again, so retries ride removals, which a host that dispatches
makes often.

*A sweep in the coordinator's loop* (its reconcile, or its quiet check). It
would need no workspace configuration, and it was rejected because it catches
only the units of a coordinator that is running, at the moment its loop
happens to pass, and because once niwa forgets the instance there is no
dispatch id left for it to read.

*Capture inside the on-reap run.* Simplest, and rejected because a capture
takes up to 120 seconds against niwa's 10-second run timeout and 30-second step
budget: niwa would kill it, count a failure, and keep retrying it at every reap.

*Capture by the worker at its own terminal.* Rejected because the merge, and
often green, come after the worker ends, and a worker has no business writing
its coordinator's record.

### Decision 2: How a capture after a removal assembles its archive

Resolved inline.

**Chosen: one collection library shared with the pass.** The pass's
instance-scoped collection moves, unchanged, into
`skills/coordinate/scripts/archive-common.sh`: the project-directory rule (the
directory named for the instance path, and a `-`-suffixed sibling only when its
`.jsonl` lines all carry a `cwd` inside the instance), the koto-session scan by
`execution_dir`, the hashed copy and the MANIFEST, MANIFEST.sha256 and README
writers. `teardown-pass.sh` sources it; the sweep sources it too and writes a
removed-mode archive (`removed: true`, the job id taken from the session id as
the pass's removed mode takes it) that `unit-cost.sh capture` reads as it reads
the pass's.

*A second copier in the sweep.* Less churn in `teardown-pass.sh`, and rejected
because the sibling-instance and symbolic-link rules would exist twice and
drift, and the PRD's same-figures requirement rests on them.

*Let the capture read the live sources.* No copy at all, and rejected because
the capture reads an archive layout and skips links by design, and a live read
races Claude Code's and koto's own pruning and leaves nothing to re-derive the
figures from later.

### Decision 3: How the dispatching coordinator is found

Resolved inline.

**Chosen: the unit's koto request.** Each archived session's
`request-leg.toml` names a request; `KOTO_REQUESTS/<id>/request.jsonl`'s header
carries `requested_by` and `coordinator_of_record`. The earliest request (by
`created_at`) whose `requested_by` matches `^coordinate-[a-z0-9-]+-[0-9]{8}T[0-9]{6}Z$`
is the dispatch, the same request the capture's Dispatch figure already reads.
Its `coordinator_of_record` minus `coordinate-` is the topic, and the slug is
`requested_by` with its `-<stamp>` cut. The entry goes to `requested_by` when
`coord-log.sh live-session --scope-slug <slug> --all` lists it, else to the one
run that call lists; none or several keeps the record.

*Scan every live coordinator's Holdings for the topic.* Rejected because it
misses the units already off Holdings, which are the case this feature exists
for.

*Match niwa's instance name to a topic.* Rejected because niwa composes and may
change that name, so the rule would be niwa's to break.

### Decision 4: Where the milestone survives the holding

Resolved inline.

**Chosen: the leg key written at dispatch.** `dispatch-worker.sh` already writes
`legs/<request>/<leg>` in the coordinator's session before any holding names the
leg (`dc_leg_put`), and nothing removes it with the holding. The dispatch adds
the brief's `unit` to that object. The capture reads the Holdings row first, as
today; when no row names the topic, it reads the leg key named by the unit's
request id from the `requested_by` session and takes its `unit` through the same
pattern and cut the row's Unit gets.

*Read the Unit from the brief in the worker's transcript.* Rejected: free text,
not a record, and the brief's shape belongs to the renderer.

*A separate dispatch ledger key.* Rejected as a second dispatch-time write for
the same fact the leg key can carry.

### Decision 5: How failing heads are read over every head

Resolved inline.

**Chosen: runs per head, paged, oldest head first, stopping after green.** For
each head of the pull request, the capture reads `repos/<repo>/actions/runs?head_sha=<sha>&per_page=100&page=<k>`
until a page holds fewer than 100 runs, then each run's earlier attempts as
today. It stops after the first green head. A head whose pages it couldn't
finish makes failing heads `bound`, with `missing` naming `failing_heads` and the
read's reason; green from a partly read head is not taken.

*Page the branch's runs.* Fewer calls on a short branch, and rejected because
the runs API pages newest first, so a cut leaves the oldest heads with no runs,
which read as `none` and hide exactly the failures #1093 is about.

*`gh run list --commit <sha> --limit N`.* Rejected because it gives no page
signal: a head with exactly N runs can't be told complete.

### Decision 6: The switch that puts entries back on the unit's items

Resolved inline.

**Chosen: `SHIRABE_PR_INTEGRATION`, read where the capture chooses `--on`.** The
value `on`, exactly, restores today's session-store placement; anything else
keeps the entry in the coordinator's session (`--on none`). A workspace sets it
in its configuration's environment, and lists it in its on-reap step's `env` so
a removal capture sees it. The wider tool-content switch (#1114) can read the
same name.

*A CLAUDE.md header.* Rejected: that is the repository's configuration, and the
ruling puts the switch in the workspace's.

*A Run row on the coordinator's record.* Rejected: per run, so every restart
would need it set again.

## Decision Outcome

A removal now leads to a capture as reliably as the pass does: niwa calls the
on-reap step at every removal it makes, the step records the removal in under a
second, and a detached sweep does the slow part with the pass's own collection
code and the pass's own capture. The capture gains three fallbacks for facts the
removal took away (the dispatch id from the removal record, the milestone from
the leg key, the coordinator from the koto request), one dedupe rule that holds
across both paths (same key or same dispatch id, under one lock), one new key
(`opened`) for pull requests not yet merged, a per-head runs read whose
completeness it can state, and a placement default that keeps entries off the
unit's items. The pass itself changes only by sourcing the extracted library.

## Solution Architecture

### Files

| File | Change |
|---|---|
| `skills/coordinate/scripts/unit-removed.sh` | new: `record` (the on-reap step) and `sweep` |
| `skills/coordinate/scripts/unit-removed_test.sh` | new suite |
| `skills/coordinate/scripts/archive-common.sh` | new: collection code moved out of `teardown-pass.sh` |
| `skills/coordinate/scripts/teardown-pass.sh` | sources `archive-common.sh`; no behaviour change |
| `skills/coordinate/scripts/unit-cost.sh` | dedupe by dispatch id under the lock, the removal-record and leg-key fallbacks, `opened`, the per-head runs read, placement, credited pulls standing in for an empty verdict |
| `skills/coordinate/scripts/unit-cost_test.sh`, `unit-cost-on_test.sh` | new and changed cases |
| `skills/coordinate/scripts/testdata/gh` | the stub serves `actions/runs?head_sha=` pages |
| `skills/coordinate/scripts/dispatch-worker.sh` | `unit` in the leg key |
| `skills/coordinate/scripts/dispatch-worker_test.sh` | the leg key's `unit` |
| `skills/coordinate/references/unit-cost.md` | `## Capture after a removal`, `opened`, failing-head floors, placement, last lines, workspace configuration |
| `skills/coordinate/SKILL.md` | the Teardown bullet names capture after a removal |
| `skills/coordinate/check-skill.tsv`, `skills/coordinate/requires.tsv` | the new suite's row; `perl` if the detach uses it |

No `record-*.sh` script changes; the capture still writes through
`record-append.sh` and reads through `record-holding.sh --read` and
`coord-log.sh`.

### The removal record and its directory

`R=${XDG_STATE_HOME:-$HOME/.local/state}/shirabe/removals/`, made `0700`.

```json
{"schema":"unit-removal/1","dispatch_id":"<id>","session_id":"<uuid>",
 "instance_path":"/abs/path","removed_at":"<UTC>","attempts":0,"last":null}
```

`record` writes `<id>.json` through a temporary name and `mv`; a record that
already exists keeps its `removed_at`. It refuses (one line, exit 0, no record)
when `NIWA_REAP_KEY` is unset or fails `^[A-Za-z0-9._:-]{1,128}$`, equals
`NIWA_SESSION_ID`, the session id fails the capture's session-id pattern, the
instance path isn't absolute or holds `..`, or `R` can't be written. It then
starts the sweep detached: `perl -MPOSIX -e 'POSIX::setsid(); exec @ARGV'
"$0" sweep </dev/null >/dev/null 2>&1 &`, falling back to `nohup` when perl is
absent; either way it exits 0 without waiting. A new session puts the sweep out
of niwa's process group and out of the shell that ran niwa.

### The sweep

```
unit-removed.sh sweep
  take R/.lock (mkdir); on failure: if R/.lock/at is older than
    150 s x max(1, R/.lock/n), take it over; else exit 0
  loop:
    list R/*.json not yet handled this sweep; write n into the lock
    none left -> release the lock, exit 0
    for each record:
      shape check fails          -> delete, log `invalid input`
      removed_at > 7 days ago    -> delete, log `expired`
      sessions = archive-common's koto scan for instance_path
      request  = earliest request-leg request with a coordinator requested_by
      no request                 -> keep, log `no coordinator`
      target   = requested_by if live, else the slug's one live run
      none / several             -> keep, log `no coordinator` / `several coordinators`
      archive  = <archive root>/<UTC date>-<topic>-<session id's first 8 hex>
                 (the pass's removed-mode name), collected by archive-common,
                 with teardown.json {topic, instance: {name: null, path},
                 job: {id: <8 hex>, session}, removed: true,
                 niwa: {dispatch_id, reason: null}}
      run unit-cost.sh capture --session <target> --archive <archive>
          --topic <topic> --prs-file <empty> under a 120 s deadline
      map its last line (below) -> delete the record or keep it, log the outcome
```

The sweep sets the capture's environment as the on-reap step received it, so
`SHIRABE_PR_INTEGRATION` reaches the capture when the workspace lists it. A
record it keeps gets `attempts` and `last` updated. `removals.log` takes one
line per record handled: `<UTC time> <dispatch id> <outcome>`.

| Capture's last line (R14) | Log outcome | Record |
|---|---|---|
| `posted the cost entry`, `kept the cost entry in the session`, `posted the cost entry on <item>` | `captured` | deleted |
| `the record already holds this unit's cost entry` | `already recorded` | deleted |
| `the post failed (record-append exit <n>)`, `the post did not finish in time` | `post failed` | kept |
| `the entry could not be computed`, or no last line | `read failed` | kept |
| stopped at the 120-second deadline | `timed out` | kept |

### Changes inside `unit-cost.sh capture`

- **Empty verdict.** With a `--prs-file` that names no pull request (a capture
  after a removal), green, merge and failing heads read the merged pull requests
  credit found (`via: session`) in place of the holding's.
- **Dispatch id.** When `teardown.json` holds no dispatch id, the capture reads
  `R/*.json` for the one whose `instance_path` is the archive's and takes its
  `dispatch_id`. When `teardown.json` holds one and a removal record names a
  different one, `teardown.json`'s stands and one line names both.
- **Milestone.** No Holdings row for the topic: read
  `legs/<request>/<leg>` (`dc_leg_get`) from the request's `requested_by`
  session, for the request Dispatch already found, and take `.unit` through the
  Unit pattern and the `: ` cut.
- **Dedupe and the lock.** The entry list and the post run under `R/.post-lock`
  (`mkdir`, taken over after 60 seconds, the list's and post's bounds summed),
  and the check matches a listed `cost` entry with the same `key`, or the same
  non-null `"niwa.dispatch.id"`.
- **`opened`.** Credit's `pr view` already returns `state`. A candidate meeting
  conditions 1, 2 and 4, created at or after dispatch, with `state == "OPEN"`
  (drafts are `OPEN`) goes to `opened` as `{repo, number, via: "session"}`; the
  holding's own pull request, when the row names one that reads open, goes in
  as `via: "holding"`. Ordered by number, at most 100, the same public-host
  rule, `missing` naming `opened` for `entry size` or a failed read.
- **Failing heads.** `uc_runs` replaces `run list --branch --limit 300` with the
  per-head pages of Decision 5. `uc_gh_ok` admits `api --method GET
  repos/<o>/<r>/actions/runs?head_sha=<sha>&per_page=100&page=<n>` with the sha
  and page matched first. A head not read whole sets the pull request's
  `runs_whole: false`; `prf()` then reports failing heads `bound`, and the
  figure's reason is the read's (`time limit`, `read failed`, `invalid input`).
- **Placement.** On the session store `ON=none` unless
  `SHIRABE_PR_INTEGRATION` is exactly `on`, in which case today's rule runs. A
  GitHub-record run is unchanged.

### `dispatch-worker.sh`

The leg key object gains `unit: <the brief input's unit>` (it is in the same
input JSON `render-brief.sh` checked), only when it matches the capture's Unit
pattern `^[A-Za-z0-9][A-Za-z0-9 _.#/-]{0,63}$`; otherwise the key is written
without it. `dc_leg_put`'s shape check is unchanged, since it checks only
`request`, `leg` and `state`.

### Workspace configuration

What a workspace adds, documented in the reference's `## Capture after a
removal`:

```toml
[session.on_reap]
command = '''
d=""; for c in "$HOME"/.claude/plugins/cache/shirabe/shirabe/*/skills/coordinate/scripts/unit-removed.sh; do [ -x "$c" ] && d=$c; done
[ -n "$d" ] && "$d" record
exit 0
'''
env = ["SHIRABE_PR_INTEGRATION"]
```

The loop takes the last match in the shell's sorted glob order; the reference
says to pin the path instead where more than one shirabe version is installed.
Combined with another tool's step, shirabe's goes first and ends without
`exit`, since it returns at once: `<shirabe step>; <the other step>`.

## Implementation Approach

One pull request, built in this order so each step leaves the suites green:

1. Extract `archive-common.sh` from `teardown-pass.sh`, behaviour-neutral;
   `teardown-pass_test.sh` and `teardown-pass_engine_test.sh` unchanged.
2. Failing heads per head (#1093), with the stub's paged runs and the new
   cases.
3. Placement and `SHIRABE_PR_INTEGRATION`; `unit-cost-on_test.sh` cases.
4. `opened`, the empty-verdict rule, dedupe by dispatch id and the post lock.
5. `unit` in the leg key; the capture's leg-key and removal-record fallbacks.
6. `unit-removed.sh` and its suite.
7. The reference, SKILL.md's line, `check-skill.tsv` and `requires.tsv`.

## Security Considerations

The removal record is written from `NIWA_*` values niwa sets, and every one is
matched to its pattern before use: the dispatch id to niwa's own reap-key shape,
the session id to the capture's, the instance path to an absolute path with no
`..`. A value that fails is never written. The sweep reads the record back
through the same checks (a hand-edited record is deleted, `invalid input`), and
only the matched values reach a path or an argument; the instance path is only
ever compared against headers and used under `archive-common.sh`'s existing
`cd -P` and physical-path checks.

The sweep reads the same untrusted inputs the pass's capture reads (transcripts,
koto sessions, the koto request) under the same rules, plus the leg key, a JSON
object the coordinator wrote, whose `unit` is matched to the Unit pattern. The
detached sweep runs as the user, writes only under `R` and the archive root
(`0700`, `umask 077`, as the pass), and posts only through `record-append.sh`,
which keeps its own visibility scan: an entry naming a private repository isn't
posted on a public host's item.

The on-reap command runs with the trust of a hook the workspace installs. The
documented command runs a script found under the user's own Claude Code plugin
cache; a workspace that doesn't trust the glob pins the path.

With the switch off, nothing is written to a pull request or an issue the unit
touched, which removes today's exposure of coordinator bookkeeping on those
items.

## Consequences

### Positive

- Every removal niwa makes leads to one entry, with its dispatch id, for the
  coordinator that dispatched the unit.
- The pass and a removal capture compute figures from one collection code.
- Failing heads are whole or say they are a floor (#1093).
- Entries stay off the unit's items unless a workspace asks.

### Negative

- Capture after a removal depends on the workspace declaring the on-reap step,
  and the documented command finds the script by a glob.
- A detached background process now runs after removals, and a host that
  never removes again never retries a kept record.
- The capture's dedupe now lists the record under a host lock, so two captures
  on one host serialize their list-and-post (at most about 40 seconds each).
- Per-head reads cost one call per head up to green, more than one `run list`
  on a short branch.

### Mitigations

- The reference documents the on-reap step, its combination with another, and
  pinning the path; without it the pass behaves exactly as today.
- Every removal's sweep retries every kept record, and records expire after 7
  days with a log line, so nothing accumulates silently.
- The lock's takeover age is its holders' own bounds, so a crashed capture
  blocks the next for at most a minute.
- The per-head read stops at green and stays inside the capture's existing
  90-second read budget; a read it can't finish is a stated floor, never a
  silent short count.
