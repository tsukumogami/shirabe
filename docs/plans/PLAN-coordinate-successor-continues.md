---
schema: plan/v2
status: Active
execution_mode: multi-pr
split_mode_source: intent
split_rationale: |
  Hard Constraint. The work lands in two repositories, and shirabe's takeover
  can only be built on a koto release carrying the fence, so koto's steps must
  merge and ship before the shirabe steps that call them.
tracking_level: none
upstream: docs/designs/DESIGN-coordinate-successor-continues.md
milestone: "A coordinator's successor continues its run"
step_count: 11
---

# PLAN: A coordinator's successor continues its run

## Status

Active

## Scope Summary

The design replaces `/coordinate`'s carry-and-cancel handover with a takeover
built on koto's continues relation. A successor runs `koto init --continues
--supersede`, which fences the predecessor in its own log (first writer wins,
nothing written if it can't), creates the successor with its relation, carries
the run's record and leg keys from the fenced state, and rings the
predecessor's watch. `coordinate-open.sh` drives that and moves the coordinator
address; koto's request store forwards rings along the fence; a declared
`COMPAT` number decides template continuation; workers resolve the newest member
when they report, and a worker that can't be told is pending; `chain-start` and
the cost sweep follow the relation.

This plan covers all of it, in two repositories. Three steps are koto changes
(the fence on the local backend, ring forwarding, the fence on the cloud
backend); the rest are shirabe. Nothing is filed: the new koto work is proposed
in the planning report.

## Decomposition Strategy

Walking skeleton. Step 1 runs koto's fence end to end on the local backend: a
real predecessor session is fenced, the successor is created holding its keys,
and the predecessor's next tick and write are refused by name. Step 2 runs a
whole coordinator takeover through it: `coordinate-open.sh` on a live run, the
predecessor refused, the successor's first tick and reconcile working. Every
later step adds one behaviour on top: the compatibility rule, the told and
pending gate, relation-based lineage, the outcome contract's refusals, re-runs
and load case, leg wakes, watch handover, worker addressing and the cost sweep,
the cloud fence, and import.

Each step lands as its own pull request in the repository it names, because
the shirabe steps that call the fence need a koto release carrying it.

## Steps

### Step 1: a session opened with --supersede fences its predecessor and takes its keys

**Goal**: On koto's local backend, `koto init <succ> --continues <pred> --supersede` crosses the whole fence path on a real predecessor session: it fences the predecessor, creates the successor with its relation, copies the named key prefixes, and every later attempt to drive the predecessor is refused by name.

**Acceptance Criteria**:

- [ ] Over a predecessor `p` holding at least two keys under each of `record/`, `legs/`, `taken_legs` and `leg_children`, nested ones included (`record/entries/000001`, `legs/<req>/<leg>`), and a key `coord/x`, `koto init s --continues p --supersede --carry record/ --carry legs/ --carry taken_legs --carry leg_children` gives `s` exactly the same key set and values under those four prefixes as `p`, and no `coord/` key; `koto context exists s koto/superseded-carry-complete` exits 0.
- [ ] `koto next p` and `koto context add p record/b` each exit non-zero with error kind `session_superseded`, and the message names `s`; `p`'s log gains no event from either attempt.
- [ ] `koto context get p record/a` still prints the value: reads of a fenced session work.
- [ ] A second `koto init t --continues p --supersede` exits 2 printing `superseded_by=s`, and no session `t` exists afterwards.
- [ ] With `p`'s log lock held by the test past 10 seconds, `koto init u --continues p --supersede` exits 3 `fence_unavailable`, no session `u` exists, and `koto next p` is accepted once the lock is released.
- [ ] Re-running the first command exits 0 and changes nothing: `s`'s keys and `p`'s log are byte-identical before and after.

**Check**: In an end-to-end test that sets a scratch `HOME` and `KOTO_HOME`, unsets every `KOTO_SESSION_*` variable and `KOTO_SESSIONS_BASE`, and asserts the resolved store is under the scratch directory before running: open `p` from a two-state template, add the keys above, run the supersede command, then run `koto next p` and see it exit non-zero with `session_superseded` naming `s`, and compare `koto context list` of `s` and `p` under the four prefixes to see identical sets.

**Dependencies**: None

**Files**: `src/cli/init_entry.rs`, `src/session/links.rs`, `src/engine/persistence.rs`, `tests/session_supersede_test.rs`

### Step 2: a second coordinator session takes over a live run with one command and ticks it

**Goal**: `coordinate-open.sh`, run for a scope whose run another session is driving, continues that run through koto's fence instead of carrying and cancelling it: it prints `outcome=continued`, the predecessor is refused by name, and the successor's first tick and reconcile work with no rebind, record edit or carry. The step adds the liveness probe the takeover reports through and the template's directive for a `session_superseded` refusal.

**Acceptance Criteria**:

- [ ] On a fixture run A holding several record entries, two open legs (one taken), `taken_legs`, `leg_children`, one dispatched and one parked holding, `coordinate-open.sh` for the same scope from a different directory prints `outcome=continued`, `predecessor=A`, `session=<B>` and, since A's koto log has an event from the last 10 minutes, `predecessor_stopped=yes`; with A's last event older than 10 minutes and no Claude job for A on the host, the same run prints `predecessor_stopped=no`.
- [ ] No session of the scope is cancelled; `koto session hierarchy B` shows B continuing A; B's keys under `record/`, `legs/`, `taken_legs` and `leg_children` equal A's at the moment of the fence.
- [ ] A's next `koto next` and a `state-stored-set.sh` write against A both exit non-zero naming B, and the template's directive A's agent receives says to stop and not re-arm its watch.
- [ ] B's first `koto next` exits 0 with no `koto session rebind`; B's first reconcile reports both holdings with A's classification and takes neither leg A had taken.
- [ ] B's record shows the coordinator row naming B's Claude session, an empty told set, and exactly one takeover entry naming A and B; the next brief `dispatch-worker.sh` renders carries B as `reports_to`.
- [ ] Running the opener again from B's Claude session prints `outcome=resumed` and adds no record entry.

**Check**: Run `coordinate-open_engine_test.sh`'s new takeover case against a koto built with step 1, with a scratch `HOME` and `KOTO_HOME`, every `KOTO_SESSION_*` and `KOTO_SESSIONS_BASE` unset, the store asserted under scratch, and `CLAUDE_CODE_SESSION_ID` set by the test to a synthetic value per session: open run A on the fixture roadmap, seed it as above and tick it to `wait`, run the opener as session B, and see `outcome=continued`, then `koto next A` refused naming B and `koto next B` exit 0. For the `predecessor_stopped=no` case the test points the liveness probe's clock and Claude-job directory at fixtures (A's last event 11 minutes old, no job for A) rather than waiting.

**Dependencies**: Step 1

**Files**: `skills/coordinate/scripts/coordinate-open.sh`, `skills/coordinate/scripts/dispatch-common.sh`, `skills/coordinate/scripts/state-read.sh`, `skills/coordinate/scripts/coord-log.sh`, `skills/coordinate/koto-templates/coordinate.md`, `skills/coordinate/scripts/coordinate-open_engine_test.sh`

### Step 3: a handover across a text-only template change or another plugin path no longer refuses

**Goal**: The coordinate opener decides whether a live or imported run can be resumed by a compat number shipped beside the template, not by the compiled template's bytes or the plugin's absolute path, and CI keeps that number honest. A run opened from today's template keeps resuming exactly as it does now.

**Acceptance Criteria**:

- [ ] A live run whose compiled template is listed in the shipped compat table at the shipped compat number resumes (`resumed=1`) even when its compiled hash differs from the shipped template's, where today it is carried.
- [ ] A live run compiled from the coordinate template on main before this change resumes with no other change: its hash is in the table at compat 1.
- [ ] A live run opened from this change's template under one plugin root resumes when the opener runs from another plugin root on the same host, and afterwards `koto` reports its `PLUGIN_ROOT` as the new root.
- [ ] A live run whose hash is missing from the table, or listed at another compat number, is carried as today, and `coordinate-open.sh --import` of such a run prints `refused=template-incompatible`, naming the template and both sides' compat numbers and hashes.
- [ ] The compat check in CI, run from the base branch's copy of its script, fails a pull request that changes a state name, a transition, an evidence field, a variable or a gate command without raising the compat number; fails one that changes a script a gate invokes (or a library it sources) without raising the compat number or recording the new gate-script hash; fails one whose shipped template hash isn't in the table at the shipped compat number; and passes a change to directive or details text alone.

**Check**: In hosted CI, `check-template-compat_test.sh` runs the check over fixture template pairs (text only, state renamed, gate script changed with and without a bump, hash missing from the table) and prints one expected verdict per pair; `coordinate-open_engine_test.sh`'s new cases open a run, change the template's directive text and its plugin root, and see `resumed=1`, then see `refused=template-incompatible` for an unlisted hash. Engine cases run under test-coordinate-engine with a scratch `HOME`, `KOTO_SESSION_*` and `KOTO_SESSIONS_BASE` unset and the store asserted under scratch.

**Dependencies**: None

**Files**: `skills/coordinate/koto-templates/coordinate.compat.json`, `skills/coordinate/koto-templates/coordinate.md`, `skills/coordinate/scripts/coord-log.sh`, `skills/coordinate/scripts/state-read.sh`, `skills/coordinate/scripts/coordinate-open.sh`, `scripts/check-template-compat.sh`, `.github/workflows/check-coordinate-scripts.yml`

### Step 4: the handover gate passes with pending workers, and a delivered re-brief records told

**Goal**: A worker that can't be told the coordinator's address yet is recorded as pending and no longer holds the handover gate, and a re-brief that reached the worker records it as told with no hand step (tsukumogami/shirabe#1245).

**Acceptance Criteria**:

- [ ] `state-stored-set.sh --pending <worker> --by <who>` records the worker as pending for the current address; `state-handover.sh --check` then reports no `not-told <worker>` gap for it, and still reports `not-told` for a live worker recorded neither told nor pending.
- [ ] `--told <worker>` turns a pending worker into a told one; `--run coordinator` clears every told and pending row; a record holding one worker as both told and pending is refused by the schema.
- [ ] After the re-brief step reports the worker messaged, the worker is recorded told for the current address with no `--told` run by hand; when it reports the worker's session gone while its instance still exists, the worker is recorded pending; when the message was refused, nothing is recorded and the gate keeps its `not-told` gap.
- [ ] A record written before this change, with no pending rows, reads, checks and hands over exactly as before.

**Check**: In hosted CI, `state-stored-set_test.sh` and `state-handover_test.sh` run the pending, told and clear cases and print each gate result, and the template's routing test drives the re-brief step's three outcomes against real koto with a scratch `HOME`, `KOTO_SESSION_*` and `KOTO_SESSIONS_BASE` unset, and shows the told set after each.

**Dependencies**: None

**Files**: `skills/coordinate/scripts/state-stored-set.sh`, `skills/coordinate/scripts/state-schema.jq`, `skills/coordinate/scripts/state-handover.sh`, `skills/coordinate/koto-templates/coordinate.md`, `skills/coordinate/references/state-keys.md`

### Step 5: chain-start returns the lineage the continues relation and carried-run links give, whatever the names

shirabe: `coord-log.sh chain-start` walks `koto/links/continues/*` and then the recycled-coordinator `dispatched-by` link, and returns the same chain on a fixture whose names and relations disagree; needs only the koto release with the continues relation.

### Step 6: takeover refusals, rival takeovers, interrupted re-runs and a 65-entry run under load follow the outcome contract

shirabe: `ambiguous-scope`, `not-newest-member`, `taken-over`, `predecessor-unstoppable`, `template-incompatible` (unequal COMPAT, naming both versions) and `koto-too-old` refusals write nothing, two racing successors yield one `continued`, a kill after each listed step converges on re-run, and a 65-entry run at load 25 takes over with no koto action over 30 seconds.

### Step 7: a leg any earlier member opened wakes the newest member's watch within 10 seconds

koto: `ring_principals`, the per-tick wake pass and the stale-wake recovery follow `session_superseded` forward with id checks, a visited set and a hop cap, and ring the newest member as well as the principal.

### Step 8: on takeover the predecessor's watch exits, the successor's is armed, and leg_wake is reported

shirabe: the takeover rings the predecessor so its armed watch exits, the skill arms `koto request watch --session` from the printed `session=` before the first tick, and the result line reports `watcher=` and `leg_wake=supported|unsupported` by koto version.

### Step 9: a worker started again after takeovers reports to the newest member, and the cost sweep charges it

shirabe: the handover classifies workers with step 2's liveness probe into told, pending or not told, `resolve-coordinator.sh`, the brief Reporting section and `render-result.sh` send reports to the newest member and the first report turns pending into told, and `unit-removed.sh` resolves `requested_by` forward to the newest member on a fixture whose names and fences disagree.

### Step 10: the fence and carry work on the cloud backend across workspace prefixes

koto: `init --supersede` fences with a conditional push into the predecessor's prefix and carries into the successor's, exits 3 with nothing written when the bucket refuses, and validates names from events before use; needs koto's bucket walk for the relation.

### Step 11: coordinate-open.sh --import continues an imported run in a second workspace

shirabe: `coordinate-open.sh --import` imports and then takes over with the imported copy as predecessor, and every takeover criterion passes again in a second workspace with the cloud configuration (tsukumogami/shirabe#806); needs koto's import keeping its source.


## Implementation Sequence

The steps run in order where they depend on each other, and in parallel where
they don't. Each step is one pull request in the repository it names.

| Step | Repository | Depends on | Needs from koto before it can be built |
|---|---|---|---|
| 1 | tsukumogami/koto | none | the continues relation (tsukumogami/koto#481, on koto's main branch) |
| 2 | tsukumogami/shirabe | 1 | a koto release carrying step 1 and the relation |
| 3 | tsukumogami/shirabe | none | nothing |
| 4 | tsukumogami/shirabe | none | nothing |
| 5 | tsukumogami/shirabe | none | a koto release carrying the relation |
| 6 | tsukumogami/shirabe | 2, 3 | as step 2 |
| 7 | tsukumogami/koto | 1 | as step 1 |
| 8 | tsukumogami/shirabe | 2, 7 | a koto release carrying step 7 |
| 9 | tsukumogami/shirabe | 2, 4 | as step 2 |
| 10 | tsukumogami/koto | 1 | koto's bucket walk for the relation |
| 11 | tsukumogami/shirabe | 6, 10 | a koto release carrying step 10 and koto's import keeping its source |

Steps 3 and 4 need no koto change and can be built now: step 3 already lifts
today's provenance refusals (tsukumogami/shirabe#1144, tsukumogami/shirabe#806)
for the existing opener, and step 4 fixes the told gaps of
tsukumogami/shirabe#1245. Steps 1 and 7 build
on the relation already on koto's main branch, so they can be built before
koto releases it. Steps 2, 5, 6, 8 and 9 wait for a koto release; steps 10 and
11 wait for the rest of koto's relation work.

What each source outcome rests on:

| Outcome | Steps |
|---|---|
| One driver from a fresh instance on another shirabe version; the predecessor's `koto next` refuses naming the successor | 1, 2, 3, 6 |
| First tick with no rebind, edit or carry; coordinator row and next brief name the successor | 2 |
| A leg the predecessor dispatched wakes the successor's watch | 7, 8 |
| A 65-entry run taken over within koto's action limits at load 25, first reconcile finds every holding | 2, 6 |
| A changed template refuses by name | 3, 6 |
| The predecessor's watch ends and the successor's is armed | 8 |
| An idle worker is pending, the gate passes, it learns the address on its next start | 2, 4, 9 |
| `chain-start` and the cost sweep follow the relation where names disagree | 5, 9 |
| The same after `coordinate-open.sh --import` into a second workspace | 10, 11 |
