---
schema: design/v1
status: Proposed
problem: |
  `/work-on`'s verification step keeps one result per head and merge-base, and a
  later entry into verification at that head keeps the result it finds and starts
  nothing. That is right for a pass and for a suite still running, but wrong for a
  result that settles nothing about the change: a command that failed on a flake
  (exit 1) sends the run back to `implementation` with the same failure on every
  lap, and a suite that ran past its limits with no failed command (exit 4) ends at
  `done_blocked` and re-reads the same result after a rewind. A user has no
  supported way to get a fresh suite at the same commit short of a throwaway
  commit, a merge of the default branch, a restart or a hand edit of the
  verification state.
decision: |
  A re-run at the same head becomes a value the agent submits with a reason:
  `verification_rerun` at `implementation` after a failed command, and `rerun` at
  a new exit-5 hold in `verification` after an eligible timeout, beside `fix` and
  `blocked`. Either value writes `verification_rerun_request`. On the next entry
  into `verification` the launcher runs `--archive --reason`, which appends the
  outgoing attempt to an append-only `verification_attempts` ledger, moves
  `result.json` and `run.json` into that attempt's folder, and starts a fresh suite
  in a fresh poll window. Logs are kept per attempt from the first run. The gate
  and the launcher share one eligibility check, in a sourced
  `verification-eligibility.sh`, and one count taken from the ledger, which caps
  re-runs at two per head and merge-base. A pass, a running suite and a dirty-tree
  result are never archived, and the directive announces the ledger's attempts
  while the PR body carries a re-run line.
rationale: |
  An automatic re-run would run every genuine failure twice before anyone saw it
  and record a retry nobody decided, so the re-run is a choice the agent names
  with a reason. Exit 1 keeps its cheap lap through `implementation` rather than a
  hold in front of every failure, while a timeout gets a hold because its failure
  terminal reports to the parent in a way a later rewind can't take back. A
  launcher verb with no new edges would leave timeouts at that terminal and
  inherit a spent poll window, and a shortcut edge from `implementation` straight
  to `verification` would add a gate on a hot state to save a few ticks. For the
  record, a disk-only archive leaves the earlier attempt on one host with nothing
  making a reviewer see it, and per-attempt keys or koto's own trail leave a
  reader several full keys or no content at all. The ledger and per-attempt logs
  keep the one head-level `result.json` every existing reader opens and put the
  attempts where a reviewer reads them, and one shared eligibility check keeps the
  cap a reviewer sees equal to the cap that was enforced.
---

# DESIGN: Re-running a verification at the same head

## Status

Proposed

## Context and Problem Statement

`/work-on`'s verification step keeps one result per head and merge-base.
`run-verification.sh --start` keeps any result already on disk for the current
head and merge-base, except a dirty-tree one, and starts nothing; the
`verification_verdict` gate then reads that result through
`check-verification.sh`. Reusing the result is right for a pass, and for a
re-tick while a suite is still running. It goes wrong when the result says
nothing settled about the change.

Two cases show it. A command fails because of a flake rather than the change
(#1230, #1852): run alone a minute later, the same command passes. The gate
reads exit 1 and routes the run back to `implementation`. Nothing in the code
needs fixing, so the head doesn't change, and the next entry into
verification finds the same failing result, runs nothing, and routes back
again. In the second case a suite runs past its limits with no command failing
(#1855): one command is stopped at its timeout, the total budget runs out, and
the commands after it never start. The gate reads exit 4 and ends the run at
`done_blocked`; walking it back with `koto rewind` at the same head re-reads
the same timed-out result.

In both cases a user of `/work-on` has no supported way to get a fresh suite at
the same commit. What's left costs more than a re-run: a commit that changes
nothing just to move the head; a merge of the default branch, which in #1230
made the next review rounds full size; starting the whole run over under a new
name; or moving the result file aside by hand, which the gate names only for a
`supervisor-error` result. That case already has a held, named route to a
fresh run (#1506). A flaky failure and a timeout with no failure have none.

## Decision Drivers

- A user whose verification failed or timed out for a reason outside the
  change gets a fresh suite at the same head through a route the run itself
  names, not a throwaway commit, a restart or a hand edit.
- The earlier attempt stays in the record next to the new one, so a flaky
  command shows up as flaky and isn't quietly retried until green.
- A pass, and a suite still running, are still reused at an unchanged head:
  finished work isn't redone, and what reviewers see doesn't change just to get
  a re-run.
- Out of scope: the fixed 7200-second budget, per-command timeouts under load
  (#1178, #1499, #817), a lapsed poll window (#1820), the supervisor-error
  route itself (#1506), and review-round sizing after a merge (#1229).

## Considered Options

### Decision 1: The route to a fresh suite at the same head

`run-verification.sh --start` keeps any result on disk for the current head and
merge-base, except a dirty-tree one, and the `verification_verdict` gate reads it
through `check-verification.sh`. koto takes the gate-only edges for exits 0, 1, 3
and 4 in the same tick it reads them, so on those exits the agent never stands in
`verification` and nothing can be offered there. A flaky failure routes exit 1 to
`implementation`; nothing needs fixing, the head doesn't move, and the next entry
reads the same failed result. A suite that runs past its limits with no failed
command routes exit 4 to `done_blocked`, a failure terminal, which reports the run
as failed to its parent in the same tick; a `koto rewind` re-reads the same result.
Only `supervisor-error` has a held route today: exit 2 holds, and its message says
to move the file aside and tick.

Two koto facts shaped the answer. A gate's poll window opens at its first
evaluation after the latest entry into the state, and only a transition
(self-transitions included), a directed transition or a rewind counts as an entry
(koto `src/engine/poll.rs`, `src/engine/persistence.rs`). A plain tick after the
result is moved aside inherits the first suite's window; since the window and the
whole-run budget are both 7200 seconds, a re-run after a whole-budget timeout
would read timed out on its first tick. And evidence submitted in a state stays in
that state's evidence until the next entry, while a state's default action is
skipped on any tick that carries evidence, so a value that matches no edge turns
the launcher off for the rest of the epoch.

Key assumptions:

- An edge's `context_assignments` are readable by the target state's default
  action in the same tick (traced in koto's `context_assign.rs` and `advance.rs`,
  not run). If wrong, the launcher can't see the request on the lap, and the agent
  would run `--archive` itself before submitting the value; the `75 + rerun` edge
  already covers that order.
- At an unchanged head the review panels carry with no new reviewer, so the lap
  from `implementation` back to `verification` costs ticks, not reviews.
- Decision 2's ledger lets the gate and the launcher count archived attempts per
  head and merge-base the same way.
- Agents won't pick `rerun` by reflex on real failures. The cap bounds this, and
  the evals check it.

#### Chosen: A named rerun value that the launcher carries out

The agent asks for the re-run by submitting a value, and the launcher does the
work on the next entry into `verification`.

1. **One request key, one consumer.** Each rerun edge writes
   `verification_rerun_request` from its evidence through `context_assignments`.
   On every entry into `verification`, before its reuse check,
   `run-verification.sh --start` reads the key. If the live result at this head and
   merge-base passes the shared eligibility check, it runs `--archive --reason
   <request>`, which writes the ledger line before moving the files, then removes
   the key and launches a fresh supervisor. Otherwise it removes the key, says why
   on stderr and behaves as today. It never archives a pass or a running suite.
2. **Exit 1 keeps koto's own edge to `implementation`.** The flake judgement
   happens there, where the agent reads the failing log. `implementation_status`
   gains `verification_rerun`, with the reason in `rationale`. Its edge takes the
   same route as `complete` through the carried panels and writes the request key.
   Re-entering `verification` opens a fresh poll window. Nothing skips review, and
   if a commit moved the head the launcher drops the key and the new head is
   verified as usual.
3. **Eligible timeouts hold at `verification`.** `check-verification.sh` exits a
   new code, 5, for a settled result whose block-stage causes are only timed-out
   commands, or timed-out and failed commands together, while the cap isn't spent.
   Exit 5 has no gate-only edge, so the state holds, as it does for exit 2.
   `verification_status` gains `rerun` and `fix`, with edges `5 + rerun ->
   verification` (a self-loop), `5 + fix -> implementation`, `5 + blocked ->
   done_blocked`, and `75 + rerun -> verification`, so a `rerun` that finds no live
   result still matches an edge.
4. **Eligibility.** One function, used by the gate's choice of exit 5 and by
   `--archive`'s refusals, decides. Eligible: a failed command, a per-command
   timeout, a whole-budget timeout and mixed fail+timeout, with fewer than two
   attempts archived for the head. Never eligible: any `runaway` or `not_started`
   command, `attended`, `dirty-tree` (stays exit 4), `no-map`, `bad-map` and
   `supervisor-error`. Over the cap, an eligible result routes as today.

This meets the first driver by naming the route in the two places koto lets an
agent stand: `implementation` for a failure and a hold for a timeout, which keeps a
non-verdict out of the failure terminal. Keeping koto's exit-1 edge means the
agent can only turn a failure into another suite koto runs, never into a pass.
Every re-run is an `evidence_submitted` event with its reason, an archived attempt
folder and a ledger line, and the cap of two per head stops endless retries. A pass
and a running suite keep their reuse unchanged. The self-loop and the request key
give the re-run its own poll window, which the archive-then-tick shape doesn't get.

#### Alternatives Considered

- **Automatic re-run**: the gate returns 5 for an eligible result and a gate-only
  self-loop re-runs once per head with a generated reason. Rejected because it runs
  every genuine failure twice before anyone sees it, can spend two more hours
  nobody asked for, and records a retry nobody decided.
- **Held verdict for every eligible failure, exit 1 included**: rejected for exit
  1 because it hands koto's exit-1 routing to the agent and puts a fork in front of
  every failure, when the lap through `implementation` costs little at an
  unchanged head. Its timeout half is adopted.
- **Launcher verb only, no new edges or code**: rejected because an eligible
  timeout still lands at the failure terminal and reports a failure to the parent
  that a later rewind can't take back, and its evidence-free variant inherits the
  spent poll window.
- **Split by verdict with an implementation shortcut** (an edge from
  `implementation` straight to `verification`): rejected because at an unchanged
  head the panels carry anyway, so the shortcut saves a few ticks at the cost of a
  new gate on a hot state and an edge that skips review if its guard is ever wrong.

### Decision 2: Keeping the earlier attempt on the record, and bounding re-runs

Today a head directory under
`$XDG_STATE_HOME/shirabe/verification/<session>/<head>/` holds one `result.json`
and one log per command at fixed names, opened with `>`, so a second run at the
same head overwrites the first run's logs. The merge-base is a field, not a path,
and prune keeps the ten most recently touched head directories.
`check-verification.sh` writes the settled result to the context key
`verification_results.json`, and `koto context add` replaces the whole key; koto's
`context history` keeps hashes and sizes, not content. Each gate finding for a
failed, timed-out, runaway or not-started command carries the log's absolute path
into koto's append-only event log, and the PR body's Verification section is free
prose. So a moved log breaks every path already written into the event log, and an
overwritten key leaves no readable trace of the attempt before it.

Key assumptions:

- koto's event log keeps each gate evaluation's findings and each edge's evidence
  `rationale`.
- A re-run re-runs the whole selected suite.
- The on-disk state directory isn't durable evidence for a reviewer: it is
  host-local and pruned with its head.
- The PR body's Verification section can take one checked line per re-run while
  skills still write the body and a script only checks it.
- The attempt folder number can be the next free number at the head, since the cap
  is counted from the ledger by head and merge-base.

#### Chosen: Logs per attempt from the first run, plus an append-only attempts ledger

The supervisor writes each run's per-command logs into `<head>/attempts/<n>/`
from the moment the run starts. The live `result.json` and `run.json` stay at
`<head>/`, so `--locate`, `--start`'s reuse rule and `check-verification.sh` open
the same path they open today. `--archive` requires a non-empty `--reason` (the
same text as the evidence `rationale` on the re-run edge) and moves `result.json`
and `run.json` into the attempt folder their logs already sit in, so no log path
ever moves. Before moving anything, `--archive` appends one JSON line for the
outgoing attempt to a context key `verification_attempts`: attempt number, head,
merge-base, the exit it came through, result status, the reason, an archive
timestamp, and per command its id, exit status, timed-out flag, duration and log
path. It reads the key back and refuses unless the line count rose by one and the
last line is the new one. `verification_results.json` keeps meaning the current
attempt.

`--archive` counts ledger lines at the current head and merge-base and refuses a
third archive there, moving nothing and writing nothing; it cross-checks the count
against the archived results on disk and fails closed on a disagreement. The
verification directive announces every ledger attempt beside the current result,
oldest first. When the ledger is non-empty, the PR body's Verification section
carries one line per archived attempt saying which command failed or timed out,
the reason given and what the next attempt showed, and a `check-pr-output.sh` mode
refuses a body that omits one.

This is the only option that keeps the earlier attempt where a reviewer reaches
it, counts the cap from that same record, and shows the re-run to a reviewer
without the agent choosing to mention it. The ledger sits in koto, so it outlives
the host and the prune; the cap reads the ledger, so the count a reviewer sees is
the count that was enforced. Writing logs into the attempt folder from the start
fixes dangling log paths at their source and stops today's overwrite of an earlier
run's logs.

#### Alternatives Considered

- **Disk-only archive**: rejected because the earlier attempt lives only on one
  host until prune removes its head, earlier findings point at moved logs, and
  nothing makes a reviewer see the re-run.
- **Per-attempt context keys with archive-and-rewrite**: rejected because log
  paths in earlier findings still dangle, a reader has to list and read several
  full keys, and the directive is still the only path to a reviewer.
- **Rely on koto's own trail**: rejected because `context history` holds no
  content, findings record only failing causes so a later pass has nothing to sit
  beside, and edge visit counts aren't keyed by head and merge-base.
- **Attempt folders as the gate's only source**: rejected because it changes the
  file every reader opens and the shape of the key every consumer reads, a much
  larger change than keeping the head-level `result.json`.

### Decision 3: A stale result after the merge-base moves

Today `--start` deletes a `result.json` whose merge-base no longer matches and
starts a fresh run. Under decision 2 the earlier run's logs no longer sit at fixed
names in the head folder, so they stay behind in their own attempt folder whatever
happens to the result. The question is whether that path should also archive the
stale result into the ledger.

#### Chosen: Keep deleting the stale result, with no ledger line

`--start` keeps today's behaviour for a moved merge-base: it removes the live
`result.json` and `run.json` and launches. The earlier run's logs stay in
`attempts/<n>/`, and the next run takes the next free number. The ledger records
only re-runs someone asked for at one head and merge-base, which is the pair the cap
counts, so a run at an older merge-base never affects the count. This was assumed
under `--auto`, since the evidence pointed one way.

#### Alternatives Considered

- **Archive the stale result with a generated reason**: rejected because it writes
  a ledger line nobody decided, and the PR body check would then require a re-run
  line for a run that was never re-run at the same pair.

### Decision 4: The supervisor-error route

A `supervisor-error` result holds at exit 2, and its message says to move the file
aside and tick. That re-run inherits the first suite's poll window, the same defect
decision 1 found in the archive-then-tick shape.

#### Chosen: Leave exit 2's route as it is

This design changes no exit-2 edge and names no `rerun` value at exit 2 or -1. The
gate's exit-2 message stays as it is today, so nothing invites a value that would
match no edge there. The natural follow-up, a `2 + rerun -> verification` edge onto
the same request key, belongs with the supervisor-error route, which the drivers
put out of scope. This was assumed under `--auto`.

#### Alternatives Considered

- **Add `2 + rerun -> verification` now**: rejected because it reopens the
  supervisor-error route (#1506) inside a change about failed and timed-out
  results, and widens the review surface for a case the issues don't raise.

### Decision 5: Where the shared eligibility check lives

Decision 1 requires one eligibility function for the gate's choice of exit 5 and for
`--archive`'s refusals. The gate is `check-verification.sh` and `--archive` lives in
`run-verification.sh`.

#### Chosen: A sourced file both scripts load

A new `skills/work-on/scripts/verification-eligibility.sh` defines the function and
the cap, and both scripts source it, the way `check-verification.sh` already sources
`scripts/lib/rule-findings.sh`. It reads a result file and the ledger and prints
`eligible`, `over-cap` or `ineligible <cause>`. This was assumed under `--auto`.

#### Alternatives Considered

- **The gate calls the launcher in a query mode**: rejected because it puts a
  process boundary and a second argument parser between the two callers of one
  rule, and couples the gate to the launcher's CLI.

## Decision Outcome

The two decisions fit together as one route and one record. A failed command
still goes to `implementation`, where the agent can answer `verification_rerun`
with a reason; an eligible timeout holds at the new exit 5, where the agent picks
`rerun`, `fix` or `blocked`. Either rerun value writes `verification_rerun_request`,
and on the next entry into `verification` the launcher runs `--archive --reason`,
which appends the outgoing attempt to the `verification_attempts` ledger before it
moves `result.json` and `run.json` into that attempt's folder, then starts a fresh
suite in a fresh poll window. Because the launcher now reads and writes koto keys,
its old "never calls koto" contract ends; that was the conflict cross-validation
found, and decision 1 was re-evaluated with decision 2's choice as a constraint.
The gate and `--archive` share one eligibility function and one count, taken from
the ledger, so the two-per-head cap a reviewer sees in the announcement and the PR
body is the one that was enforced. A pass, a running suite and a dirty-tree result
are never archived.

High-priority assumption, left open after the one cross-validation round: decision
2 says that at the failed exit, over the cap, "the guard on `complete` still
refuses at the unchanged head". The restarted decision 1 adds no such guard. Over
the cap it routes exit 1 to `implementation` as today, and the launcher refuses a
further `verification_rerun`. This design assumes the way out over the cap is a
new head (a real fix) or a blocked outcome, enforced by the launcher's refusal and
the gate's routing rather than by a guard on `complete`. If a guard turns out to
be needed, it is an addition to decision 1's edges, not a change to decision 2's
record.

## Solution Architecture

### Overview

A re-run at the same head becomes a value the agent submits, with a reason, at one
of the two places koto lets it stand after a non-settling result: `implementation`
after a failed command, and a new hold at `verification` after an eligible timeout.
The value writes a request key. On the next entry into `verification` the launcher
reads the key, archives the live result into an attempt folder and the attempts
ledger, and starts a fresh suite in a fresh poll window. A pass, a running suite
and a dirty-tree result are never archived, so their reuse at an unchanged head is
unchanged. Two re-runs per head and merge-base are allowed; after that the run
routes as it does today.

### Components

All paths are under `skills/work-on/`.

- **`scripts/verification-eligibility.sh` (new).** Sourced by both scripts below.
  Given a result file and the ledger, it prints `eligible`, `over-cap` or
  `ineligible <cause>`. Eligible: status `done` or `timed-out` whose block-stage
  causes are only failed or timed-out commands, with fewer than two ledger lines at
  this head and merge-base. Ineligible: any `runaway` or `not_started` command,
  `attended`, `dirty-tree`, `no-map`, `bad-map` and `supervisor-error`.
- **`scripts/run-verification.sh`.**
  - The supervisor writes each command's log into `<head>/attempts/<n>/`, where n is
    the next free number at that head. `result.json` and `run.json` stay at
    `<head>/`.
  - `--archive --reason <text>` (new verb) refuses an empty reason, a running suite
    (the existing `lock_live` guard) and any result the eligibility check doesn't
    pass. Otherwise, holding the supervisor's lock for the whole sequence, it
    appends the outgoing attempt to the `verification_attempts` ledger, reads the
    key back, checks the line count rose by one, and moves `result.json` and
    `run.json` into the attempt folder their logs already sit in. It validates the
    session name and head against `[A-Za-z0-9._-]+` and the attempt number as an
    integer before any of them forms a path for `mv` or `rm`.
  - `--start` reads `verification_rerun_request` before its reuse check. With a
    request and an eligible live result it runs `--archive --reason <request>`,
    removes the key and launches. With a request and no eligible result it removes
    the key, says why on stderr and behaves as today. A moved merge-base still
    deletes the stale result and writes no ledger line (decision 3).
- **`scripts/check-verification.sh`.** Gains exit 5 for an eligible settled result
  that is a timeout or a timeout with failures; a result that only failed keeps exit
  1. Its message names `rerun`, `fix` and `blocked`, the attempt number and the
  archived logs, and for a whole-budget timeout says a re-run can take up to two
  more hours. Every other exit is unchanged.
- **`koto-templates/work-on.md`.** `verification_status` becomes
  `[blocked, rerun, fix]` and four edges are added on `verification`:
  `5 + rerun -> verification`, `5 + fix -> implementation`,
  `5 + blocked -> done_blocked` and `75 + rerun -> verification`.
  `implementation_status` gains `verification_rerun`, whose edge goes to
  `changed_paths_record` like `complete`. Every rerun edge writes
  `verification_rerun_request` through `context_assignments`. The verification and
  implementation directives say when each value fits and announce the ledger's
  attempts beside the current result. `koto-templates/work-on.mermaid.md` is
  regenerated.
- **`scripts/check-pr-output.sh`.** A new mode refuses a PR body whose Verification
  section lacks one line per ledger attempt.
- **Docs.** `SKILL.md`'s Definition of Done, `references/verification-map.md` and
  the verdict table in `docs/designs/current/DESIGN-output-gates.md` learn exit 5
  and the rerun values.

### Key Interfaces

- **Exit 5 of `check-verification.sh`.** A settled, eligible result that is a
  timeout, or a timeout with failures, under the cap. It has no gate-only edge, so
  the state holds and the agent must answer.
- **Evidence values.** `verification_status: rerun | fix | blocked`, with the reason
  in `detail`; `implementation_status: verification_rerun`, with the reason in
  `rationale`.
- **`verification_rerun_request`.** A context key holding the reason text. Rerun
  edges write it, and only `--start` reads and removes it.
- **`verification_attempts`.** A context key of JSON Lines, one line per archived
  attempt: attempt number, head, merge-base, the exit it came through, result
  status, reason, archive timestamp, and per command its id, exit status, timed-out
  flag, duration and log path relative to the head directory. Only `--archive`
  writes it, building each line with `jq -n --arg` and using the same
  read-append-write-read-back steps as `panel-retry-budget.sh`.
- **`run-verification.sh --archive --reason <text>`.** Usable by hand as well as
  from `--start`. The reason arrives as one quoted argument, is stripped of control
  characters and newlines, and is capped at 500 characters; an empty result is
  refused. It refuses a third archive at a head and merge-base, moving nothing and
  writing nothing, and fails closed when the ledger count and the archived
  `attempts/*/result.json` on disk disagree, with one exception: when the last
  ledger line names attempt n at the live result's head and merge-base and
  `attempts/<n>/` holds no `result.json`, the archive was interrupted between the
  append and the move, and `--archive` finishes the move instead of refusing.
- **`verification_results.json`.** Unchanged: it still means the current attempt.

### Data Flow

A flaky failure:

1. The suite fails. The gate exits 1, and koto routes to `implementation` as today.
2. The agent reads the failing log, judges the failure to be outside the change, and
   submits `implementation_status: verification_rerun` with a reason. The edge writes
   `verification_rerun_request`.
3. The run passes through `changed_paths_record` and the carried panels. At an
   unchanged head no reviewer runs again.
4. Entry into `verification` opens a fresh poll window. `--start` finds the request
   and an eligible result, appends ledger line 1, moves `result.json` and `run.json`
   into `attempts/1/`, removes the key and launches attempt 2, whose logs go to
   `attempts/2/`.
5. The gate reads attempt 2. On a pass the directive and the PR body show
   attempt 1's failure, its reason and attempt 2's pass.

A timeout with no failure:

1. The suite runs past its budget. The gate exits 5, and the state holds.
2. The agent submits `verification_status: rerun` with a reason. The self-loop writes
   the request key and re-enters `verification`, which opens a fresh poll window.
3. Steps 4 and 5 above follow. If the cause is the change, `fix` goes to
   `implementation`; if the run can't go on, `blocked` goes to `done_blocked`.

Over the cap, the gate's routing and the launcher's refusal leave a new head or a
blocked outcome as the only ways out. Steps 2 and 4 rely on decision 1's assumption
that a rerun edge's `context_assignments` are readable by the target state's default
action in the same tick. If that turns out to be wrong, the agent runs `--archive`
itself before submitting the value, and the `75 + rerun` edge already covers that
order.

## Implementation Approach

The pieces land in an order where each step is inert until the next one routes to it.

### Phase 1: Attempt folders, the ledger and `--archive`

The supervisor's log directory moves to `<head>/attempts/<n>/`, and `--archive`
arrives with its reason, ledger append, read-back, cap and disk cross-check, on top
of the eligibility file. Nothing routes to `--archive` yet, so the only visible change
is where logs live.

Deliverables:
- `skills/work-on/scripts/verification-eligibility.sh`, sourced by a path built
  from the calling script's own location, reading its inputs only through `jq`
  and printing `ineligible` on a parse error
- `skills/work-on/scripts/run-verification.sh` (log layout, `--archive` with the
  lock scope, the jq-built ledger line, the reason's cleaning and length cap, and
  the path validation)
- `skills/work-on/scripts/run-verification_test.sh`: a second run doesn't overwrite
  the first's logs, a third archive is refused with nothing moved, a ledger line the
  script didn't write fails closed, an interrupted archive is finished, a reason
  holding quotes, a newline and shell metacharacters lands as one ledger line, and
  each eligibility case.

### Phase 2: The request consumer in `--start`

`--start` reads and removes `verification_rerun_request`. With no edge writing the
key yet, nothing changes for a run.

Deliverables:
- `skills/work-on/scripts/run-verification.sh` (`--start`)
- `skills/work-on/scripts/run-verification_test.sh`: the request-key matrix (eligible,
  ineligible, no result, moved head, moved merge-base).

### Phase 3: Exit 5 and the new edges

The gate's exit 5 and the template's edges land in one commit. Exit 5 without its
edges would hold with no value that matches an edge, and the edges without exit 5
would never fire.

Deliverables:
- `skills/work-on/scripts/check-verification.sh` (exit 5, message)
- `skills/work-on/koto-templates/work-on.md` (enums, five edges, directives)
- `skills/work-on/koto-templates/work-on.mermaid.md` (regenerated)
- `skills/work-on/scripts/output-gates-routing_test.sh`: the exit-5 hold and each new
  edge, plus one self-loop lap against real koto.

### Phase 4: What reviewers see

The directive's announcement of ledger attempts, the PR body's re-run line and its
check, and the docs and evals.

Deliverables:
- `skills/work-on/scripts/check-pr-output.sh` and `check-pr-output_test.sh`,
  including a refusal of a re-run line that carries an absolute path
- `skills/work-on/SKILL.md`, `skills/work-on/references/verification-map.md`,
  `docs/designs/current/DESIGN-output-gates.md`
- `skills/work-on/evals/evals.json`: a flake re-run from `implementation`, a timeout
  re-run from the hold, a real hang sent to `fix`, a refused runaway, and an
  over-cap failure that routes as today.

## Security Considerations

This change adds no network access, no downloads and no new dependencies. It
sources one new script from the plugin's own `skills/work-on/scripts/` directory,
resolved from the calling script's location the way `scripts/lib/rule-findings.sh`
is, and it lets the launcher read and write koto context keys and move files
inside the session's verification state directory. `jq` stays the only parser.

The threat model is a careless or mistaken agent, not a hostile one. An agent with
shell access can already edit koto keys or move result files by hand, so the
two-per-head cap and the eligibility check bound and record re-runs; they don't
stop a determined bypass. Even a hand-written request key stays limited by
eligibility: a pass, a running suite, a dirty-tree result, a runaway or not-started
command and a supervisor error are never archived. Moving the head resets the cap,
so a re-run's cost, up to two hours each, is bounded per head and not per branch.
That's accepted.

Agent-supplied text is treated as data. The reason reaches `--archive` as one
quoted argument and is never expanded by `eval`. It's stripped of control
characters and newlines and capped in length, and the ledger line is built with
`jq --arg`, so quotes and newlines can't forge a second line; the read-back check
catches a malformed append. Command ids and log paths from `result.json` come from
the repository's own verification map, which a branch can change, so they're
encoded through `jq` the same way and shown in the directive and the PR body as
quoted data. Session name, head and attempt number are validated before they form a
path for `mv` or `rm`.

`--archive` holds the supervisor's lock from its eligibility check through the
ledger append and the move, so a `--start` can't launch in between. It writes the
ledger line before moving anything, so a crash leaves a recorded attempt with its
files still in place, which the next `--archive` recognises and finishes.

Earlier attempts' logs now stay on the host until their head directory is pruned,
where before a later run overwrote them, and logs can hold secrets. The
`attempts/` folders keep the mode of the existing head directories and go with the
head when it's pruned. The ledger lives in koto, which outlives the host, and the PR
body may be public, so the ledger stores log paths relative to the head directory,
and a PR body's re-run lines carry command ids and the agent's reason only, with no
absolute paths and no log excerpts. `check-pr-output.sh` refuses a re-run line that
holds an absolute path. What's left is the reason itself: an agent that pastes log
output into it can still publish what the log held, and the directive says to
write the reason in the agent's own words.

## Consequences

### Positive

- A flaky failure or a load-caused timeout gets one more suite at the same commit
  with one submitted value and a reason: no throwaway commit, no merge of the
  default branch, no restart and no hand edit.
- A timeout no longer ends the run at a failure terminal or reports a failure to a
  parent; it holds and asks.
- The flake is readable on the record. The ledger and the PR body put attempt 1's
  failure, the reason for the re-run and attempt 2's result side by side, and the
  ledger lives in koto, so it outlives the host and the head's prune.
- No log path ever moves and no run overwrites an earlier run's logs, which also
  fixes today's overwrite at the same head.
- A pass, a running suite and a dirty-tree result keep today's reuse, and
  `verification_results.json` keeps its meaning, so existing readers, tests and evals
  stay as they are.

### Negative

- For eligible timeouts the choice between `rerun`, `fix` and `blocked` sits with the
  agent, and a careless `rerun` costs a suite, up to two hours for a whole-budget
  timeout.
- The template and the gate gain surface that has to stay in agreement: a new exit,
  three new values and five new edges.
- The launcher now reads and writes koto keys, ending its old contract that it never
  calls koto, and it depends on the session name.
- One more context key whose integrity a script has to guard, and one more checked
  shape in the PR body.
- The supervisor-error hold keeps its inherited-window defect, and a `rerun`
  submitted at exit 2 or -1 still matches no edge (decision 4).
- The same-tick reading of `context_assignments` is traced in koto's source, not
  run.

### Mitigations

- The cap of two archived attempts per head and merge-base bounds a careless
  `rerun`, the gate's message warns about the two-hour cost, and the evals check that
  a real hang goes to `fix`.
- One eligibility file serves both the gate and `--archive`, so they can't disagree
  about what may be re-run, and the routing tests cover every new edge.
- The ledger follows `panel-retry-budget.sh`'s read-back discipline and cross-checks
  the disk, failing closed on a disagreement.
- The exit-2 message doesn't name `rerun`, so nothing invites the unmatched value;
  the follow-up edge has an obvious home on the same request key.
- If the same-tick assumption fails, the agent runs `--archive` before submitting,
  and the `75 + rerun` edge keeps that order routable.
