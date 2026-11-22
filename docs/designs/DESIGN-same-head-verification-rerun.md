---
schema: design/v1
status: Planned
problem: |
  `/work-on`'s verification step keeps one result per head and merge-base, and a
  later entry into verification at that head keeps the result it finds and starts
  nothing. That is right for a pass and for a suite still running, but wrong for a
  result that settles nothing about the change: a command that failed on a flake
  (exit 1) sends the run back to `implementation` with the same failure on every
  lap, and a check that timed out with no failed one holds at the timed-out hold
  (exit 5, with the hosted-of-record route open), where re-entering re-reads the
  same timed-out result. A user has no
  supported way to get a fresh suite at the same commit short of a throwaway
  commit, a merge of the default branch, a restart or a hand edit of the
  verification state.
decision: |
  A re-run at the same head becomes a value the agent submits with a reason:
  `verification_rerun` at `implementation` after a failed command (a failed
  command beside a timed-out one included), and `rerun` at the existing exit-5
  hold in `verification` (a timed-out check, none failed, the hosted-of-record
  route open), beside `hosted_of_record`, `fix` and `blocked`. The feature adds
  only that value and the `5 + rerun` and `75 + rerun` edges to the hold; a
  timeout with the route closed stays exit 4. Either value writes
  `verification_rerun_request`. On the next entry
  into `verification` the launcher runs `--archive --reason`, which appends the
  outgoing attempt to an append-only `verification_attempts` ledger, moves
  `result.json` and `run.json` into that attempt's folder, and starts a fresh suite
  in a fresh poll window. Logs are kept per attempt from the first run. The gate
  and the launcher share one eligibility check, in a sourced
  `verification-eligibility.sh`, and one count taken from the ledger, which caps
  re-runs at two per head and merge-base. A pass, a running suite and a dirty-tree
  result are never archived, and the PR body carries a re-run line for each
  archived attempt.
rationale: |
  An automatic re-run would run every genuine failure twice before anyone saw it
  and record a retry nobody decided, so the re-run is a choice the agent names
  with a reason. Exit 1 keeps its cheap lap through `implementation` rather than a
  hold in front of every failure, while a timeout already stands at a hold, so the
  re-run joins the values that hold accepts. A launcher verb with no new edges
  would offer nothing at that hold and inherit a spent poll window, and a shortcut
  edge from `implementation` straight
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

Planned

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
the commands after it never start. With the hosted-of-record route closed the
gate reads exit 4 and ends the run at `done_blocked`. With the route open it
holds at the timed-out hold (exit 5), whose values are the hosted route, `fix`
and `blocked`; re-entering at the same head, or walking a closed run back with
`koto rewind`, re-reads the same timed-out result.

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
reads the same failed result. A failed check beside a timed-out one is exit 1 too:
a failed check outranks a timeout. A check that timed out with none failed holds at
exit 5 when the hosted-of-record route is open, where the run can take the route, go
back to `fix` or stop, but nothing starts a fresh suite; with the route closed it
routes exit 4 to `done_blocked`, a failure terminal. Exit 2 holds too, for a
`supervisor-error` result, and its message says to move the file aside and tick.

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
  action in the same tick. This is traced in koto's source, not run: the append of
  a `transitioned` event writes its assignments to the context store straight
  away (`src/cli/mod.rs`), a failed store write is answered from the log
  (`src/engine/context_assign.rs`), and the advance loop then enters the target
  with its evidence cleared and runs its default action (`src/engine/advance.rs`).
  The starting state isn't in the loop's visited set, so a self-loop is allowed.
  If the reading is wrong, the launcher can't see the request on the lap, and the
  agent would run `--archive` itself before submitting the value; the
  `75 + rerun` edge already covers that order.
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
3. **The timed-out hold gains `rerun`.** Exit 5 already exists: a timed-out check,
   none failed, and the hosted-of-record route open. It has no gate-only edge, so
   the state holds until `hosted_of_record`, `fix` or `blocked` is submitted.
   This feature adds only `rerun` to those values, with two edges:
   `5 + rerun -> verification` (a self-loop, which needs a non-blank reason in
   `detail` through `route_reason_given` and never the route gate) and
   `75 + rerun -> verification`. Exit 75 is the gate's existing "no result for this
   head yet; the gate waits", so a `rerun` submitted after its result was already
   archived still matches an edge. Exit codes don't move: a failed check beside a
   timed-out one exits 1 and is re-run from `implementation`, and a timeout with the
   route closed stays exit 4, with no re-run.
4. **Eligibility.** One function, used by the gate's messages and by `--archive`'s
   refusals, decides. Eligible: a failed command, a per-command timeout, a
   whole-budget timeout that left no command unstarted and mixed fail+timeout, with
   fewer than two attempts archived for the head. Never eligible: any `runaway` or
   `not_started` command, a budget stop that left commands unstarted, `attended`,
   `dirty-tree` (stays exit 4), `no-map`, `bad-map` and `supervisor-error`. Over the
   cap, the gate's exits don't change: exit 1 still routes to `implementation`, and
   the hold at 5 offers only its other three values.

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
- **Launcher verb only, no new edges or code**: rejected because the timed-out
  hold would still offer no value that starts a fresh suite, and its evidence-free
  variant inherits the spent poll window.
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
reason submitted with the re-run value: `rationale` at `implementation`, `detail`
at `verification`) and moves `result.json`
and `run.json` into the attempt folder their logs already sit in, so no log path
ever moves. Before moving anything, `--archive` appends one JSON line for the
outgoing attempt to a context key `verification_attempts`: attempt number, the
folder number, head, merge-base, the exit it came through, result status, the
reason, an archive timestamp, and per command its id, exit status, timed-out
flag, duration and log path. It reads the key back and refuses unless the line
count rose by one and the last line is the new one. `verification_results.json`
keeps meaning the current attempt.

`--archive` counts ledger lines at the current head and merge-base and refuses a
third archive there, moving nothing and writing nothing; it cross-checks the count
against the archived results on disk and fails closed on a disagreement. On exits
1 and 5 the gate's message lists every ledger attempt beside the current result,
oldest first; a pass's message is unchanged. The directives name the key. When
the ledger is non-empty, the PR body's Verification section carries one line per
archived attempt saying which command failed or timed out, the reason given and
what the next attempt showed, and a `check-pr-output.sh` mode refuses a body that
omits one.

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

Decision 1 requires one eligibility function for the gate's re-run offers and for
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

### Decision 6: Where the re-run record is checked for a shared pull request

`check-pr-output.sh --rerun-record` refuses a PR body whose Verification section
lacks a re-run line for an archived attempt. A session that opens its own PR can
run it at `pr_creation`. In a plan run whose steps share one branch and one PR,
though, each step's child session submits `pr_status: shared` at `pr_creation` and
opens nothing: the owning session owns the PR and checks it at `pr_finalization`.
That edit replaces the whole PR body, keeping only the run marker, and its gates
check the rewritten body once. A child also has no variable naming the owned PR,
and in the node push path the PR is opened only after the children finish. The
verification deferral record already has this shape: `pr_creation` gates it on the
`created` edges only, and `pr_finalization`'s `deferral_recorded` gate collects
every child's `verification_deferral` and checks the owned PR. The requirement is
that no re-run is hidden in any PR, owned or shared.

#### Chosen: The owning session checks the shared PR at pr_finalization

`pr_finalization` gains a re-run record gate beside `deferral_recorded`. Its
collector, modelled on `shared-deferral-record.sh`, finds the run's children the
same ways (the children listing, or `--child` with `--child-dir`), reads each
child's `verification_attempts` as JSON Lines, and runs `check-pr-output.sh
--rerun-record` against the owned PR after the finalization edit, so it checks the
body a reviewer reads. In the node push path the ledger lines reach the run record
at push time, the way deferrals do, and the check runs where that path checks
deferrals. The gate is overridable only by a person, like the other output gates,
and it doesn't pass under `omit`: re-run lines are required whatever the
workflow-content setting. The finalization directive tells the owning session to
write each child's re-run lines into the body.

Each child's `pr_creation` runs its re-run record gate on the `created` edges only,
where the child opens its own PR. The `shared` edge stays ungated, as it is for
every other output gate. So the owned and shared cases each get one check, on the
body that lands. This was assumed under `--auto`. It assumes a child's session and
its `verification_attempts` key stay readable through `pr_finalization`, since
every tick carries `--no-cleanup`; if not, the ledger needs a run-record copy, as
deferrals already have for the node push path.

#### Alternatives Considered

- **A sharing child checks the owning PR's body at pr_creation**: rejected because
  the owning session's finalization edit replaces the body afterwards and nothing
  checks it again, the PR may not exist yet in the node push path, and the child
  has no variable naming the owned PR. A re-run could still be hidden.
- **Both checks, the child's as an early signal**: rejected because it meets the
  requirement only through the owning session's check, while the child's half adds
  PR-naming plumbing and a hold on a body that is about to be replaced.
- **Leave the shared case unchecked and say so**: rejected because it hides re-runs
  in shared PRs by design.

## Decision Outcome

The six decisions fit together as one route and one record. Decision 1 names the
route: a failed command still goes to `implementation`, where the agent can answer
`verification_rerun` with a reason (a failed command beside a timed-out one
included), and a timeout with no failure holds at the existing exit 5, which now
accepts `rerun` beside `hosted_of_record`, `fix` and `blocked`. Either
rerun value writes
`verification_rerun_request`, and on the next entry into `verification` the
launcher runs `--archive --reason`. Decision 2 keeps the record: `--archive`
appends the outgoing attempt to the `verification_attempts` ledger before it moves
`result.json` and `run.json` into that attempt's folder, then a fresh suite starts
in a fresh poll window. Because the launcher now reads and writes koto keys, its
old "never calls koto" contract ends, and decision 1's route is built on that. The
gate and `--archive` share one eligibility function (decision 5) and one count,
taken from the ledger, so the two-per-head cap a reviewer sees in the announcement
and the PR body is the one that was enforced. A moved merge-base writes no ledger
line (decision 3), exit 2 keeps its route (decision 4), and a pass, a running suite
and a dirty-tree result are never archived. The PR body carries a re-run line per
archived attempt: a session that opens its own PR checks it at `pr_creation`, and a
PR that a plan's steps share is checked by the owning session at `pr_finalization`
(decision 6).

High-priority assumption: this design adds no guard on `implementation_status:
complete`. Over the cap the gate routes exit 1 to `implementation` as today and
the launcher refuses a further `verification_rerun`, so the ways out are a new
head (a real fix) or `implementation_status: blocked`, which already goes to
`done_blocked`. The gate's over-cap message names both. An agent that keeps
submitting `complete` at an unchanged head still laps through the same failed
result, as it does today; the design assumes the message is enough to stop that.
If a guard turns out to be needed, it is an addition to decision 1's edges, not a
change to decision 2's record.

## Solution Architecture

### Overview

A re-run at the same head becomes a value the agent submits, with a reason, at one
of the two places koto lets it stand after a non-settling result: `implementation`
after a failed command, and the existing timed-out hold at `verification` (exit 5).
The value writes a request key. On the next entry into `verification` the launcher
reads the key, archives the live result into an attempt folder and the attempts
ledger, and starts a fresh suite in a fresh poll window. A pass, a running suite
and a dirty-tree result are never archived, so their reuse at an unchanged head is
unchanged. Two re-runs per head and merge-base are allowed; after that the run
routes as it does today, and the hold at 5 offers only its other three values.

### Components

All paths are under `skills/work-on/`.

- **`scripts/verification-eligibility.sh` (new).** Sourced by both scripts below.
  It takes two paths, a result file and a ledger file, and prints `eligible`,
  `over-cap` or `ineligible <cause>`; each caller fetches the ledger from koto into
  a file first. A key that `koto context exists` reports missing is an empty
  ledger; any other failed read is not, and the caller refuses rather than count
  it as empty. Eligible: status `done` or
  `timed-out` whose commands that didn't pass are only failed or timed-out ones (a
  failed command beside a timed-out one included), with no command left unstarted
  by a budget stop and fewer than two ledger lines at this head and merge-base.
  Ineligible: any `runaway` or `not_started` command, a budget stop that left
  commands unstarted, `attended`, `dirty-tree`, `no-map`, `bad-map` and
  `supervisor-error`. The ledger's line count at the head and merge-base is the
  one counter: it sets the cap and the "attempt k" every message shows.
- **`scripts/run-verification.sh`.**
  - The supervisor writes each command's log into `<head>/attempts/<n>/`, where n is
    the next free folder number at that head. The number names storage only; each
    ledger line records the folder its attempt used. Log names keep today's form,
    the command's index followed by its id with every character outside
    `[A-Za-z0-9._-]` replaced, so a branch-supplied id can't leave the folder.
    Attempt folders are created `0700` and their logs `0600`. `result.json` and
    `run.json` stay at `<head>/`.
  - `--archive --reason <text>` (new verb) refuses an empty reason, a running suite
    (the existing `lock_live` guard) and any result the eligibility check doesn't
    pass. Otherwise, holding the supervisor's lock for the whole sequence, it
    appends the outgoing attempt to the `verification_attempts` ledger, reads the
    key back, checks the line count rose by one, and moves `result.json` and
    `run.json` into the attempt folder their logs already sit in. Those two
    fixed-name files are all it moves; no path it moves or removes is built from a
    command id. It validates the session name and head against `[A-Za-z0-9._-]+`
    and the folder number as an integer before any of them forms a path for `mv`
    or `rm`. It refuses a symlinked attempt folder, `result.json` or `run.json`,
    and creates attempt folders itself, `0700`.
  - `--start` reads `verification_rerun_request` before its reuse check, under the
    same supervisor lock `--archive` holds, so two ticks can't both consume one
    request. With a request and an eligible live result it runs `--archive --reason
    <request>`, removes the key and launches. With a request and no eligible result
    it removes the key, says why on stderr and behaves as today. When the ledger
    read fails for any reason other than a missing key, it refuses the re-run and
    keeps the request key, as the gate holds at exit 2 on a failed read. A moved
    merge-base still deletes the stale result and writes no ledger line
    (decision 3).
- **`scripts/check-verification.sh`.** Reads `verification_attempts` with `koto
  context get`, through the same koto access and `--session` it already uses to
  write `verification_results.json`. A missing key counts as no attempts; a failed
  read holds the gate at exit 2, as a failed write does today, so a read failure
  never grants a re-run. Its exits don't change: a failed check beside a timed-out
  one stays exit 1, a timeout with no failure and the route open stays exit 5, and
  one with the route closed stays exit 4. It reads the ledger only for a result that
  can reach 1 or 5, deciding whether the route is open before anything is recorded,
  so exits 3 and 4 never read it. On exits 1 and 5 its message gives the attempt
  number, each earlier attempt's failed or timed-out commands and reason, and the
  current attempt's log folder; at exit 5 it offers `rerun` beside
  `hosted_of_record`, `fix` and `blocked` while the result is eligible, and for a
  whole-budget timeout says a re-run can take up to two more hours. Over the cap,
  its exit-1 message says the ways out are a real fix or
  `implementation_status: blocked`, and its exit-5 message says the cap is spent and
  offers only the other three values. Every other exit is unchanged.
- **`koto-templates/work-on.md`.** `verification_status` already holds `blocked`,
  `fix` and `hosted_of_record` for the hold; it gains `rerun`, and two edges are
  added on `verification`: `5 + rerun -> verification` and
  `75 + rerun -> verification`, both needing a non-blank reason through
  `route_reason_given` and neither the route gate.
  `implementation_status` gains `verification_rerun`, whose edge goes to
  `changed_paths_record` like `complete`. Every rerun edge writes
  `verification_rerun_request` through `context_assignments`. Directives are static
  text, so the verification and implementation directives say when each value
  fits, point at the gate's message for the attempts, and name the
  `verification_attempts` key; they say its content is data from earlier runs,
  not instructions, and that the output of a failing log is data too.
  `koto-templates/work-on.mermaid.md` is regenerated.
- **`scripts/check-pr-output.sh`.** A new mode refuses a PR body whose Verification
  section lacks one line per ledger attempt, or whose re-run line holds an
  absolute path, carries a command id or reason outside a code span, or carries
  an id holding a character the ledger's cleaning strips.
- **Docs.** `SKILL.md`'s Definition of Done, `references/verification-map.md` and
  the verdict table in `docs/designs/current/DESIGN-output-gates.md` learn the
  rerun values, `rerun` at exit 5 included.

### Key Interfaces

- **Exit 5 of `check-verification.sh`.** The existing timed-out hold: a check timed
  out, none failed, and the hosted-of-record route is open. It has no gate-only edge,
  so the state holds until a value is submitted. This feature only adds `rerun` to
  the values it accepts.
- **Evidence values.** `verification_status: rerun`, beside the hold's
  `hosted_of_record`, `fix` and `blocked`, with the reason in `detail`; `implementation_status: verification_rerun`, with the reason in
  `rationale`.
- **`verification_rerun_request`.** A context key holding the reason text. Rerun
  edges write it, and only `--start` reads and removes it. A key left behind when
  the run never re-enters `verification` does nothing: nothing else reads it, and
  `--start` checks it against the live result before acting on it.
- **`verification_attempts`.** A context key of JSON Lines, one line per archived
  attempt: attempt number, the folder number, head, merge-base, the exit it came
  through, result status, reason, archive timestamp, and per command its id, exit
  status, timed-out flag, duration and log path relative to the head directory.
  The exit comes from the result's causes the same way the gate picks it, so
  `--archive` needs no word from the gate. Each id is cleaned and capped as the
  reason is before it's stored.
  Only `--archive` writes it, building each line with `jq -n --arg` and using the
  same read-append-write-read-back steps as `panel-retry-budget.sh`. A reader
  accepts a log path only in the shape `attempts/<n>/<index>-<name>.log`.
- **`run-verification.sh --archive --reason <text>`.** Usable by hand as well as
  from `--start`, and either way it requires the same validated `--session` the
  gate uses. The reason arrives as one quoted argument, is stripped of control
  characters, newlines, ANSI escape sequences and Unicode format characters
  (bidirectional controls included), and is capped at 500 characters; an empty
  result is refused. It refuses a third archive at a head and merge-base, moving
  nothing and writing nothing, and fails closed when the ledger count and the
  archived `attempts/*/result.json` on disk disagree, with one exception: when the
  last ledger line records folder n at the live result's head and merge-base and
  `attempts/<n>/` holds no `result.json`, the archive was interrupted between the
  append and the move, and `--archive` finishes the move instead of refusing. That
  recovery still runs under the lock, still refuses a running suite through
  `lock_live`, still requires the live result to pass the eligibility check, and
  moves nothing unless the live result's head and merge-base match the ledger
  line's. The cross-check counts only archived results whose head and merge-base
  match the current pair, so archived attempts from an earlier merge-base at the
  same head don't trip it. When prune has removed a head's attempt folders and
  its ledger lines survive, the check fails closed, and the ways out are the ones
  the over-cap route names: a new head or `implementation_status: blocked`.
- **`verification_results.json`.** Unchanged: it still means the current attempt.

### Data Flow

A flaky failure:

1. The suite fails. The gate exits 1, and koto routes to `implementation` as today.
   The gate's message gives the attempt number and the log folder.
2. The agent reads the failing log, judges the failure to be outside the change, and
   submits `implementation_status: verification_rerun` with a reason. The edge writes
   `verification_rerun_request`.
3. The run passes through `changed_paths_record` and the carried panels. At an
   unchanged head no reviewer runs again.
4. Entry into `verification` opens a fresh poll window. `--start` finds the request
   and an eligible result, appends ledger line 1, moves `result.json` and `run.json`
   into `attempts/1/`, removes the key and launches attempt 2, whose logs go to
   `attempts/2/`.
5. The gate reads attempt 2. On a pass it exits 0 with its message unchanged, and
   the PR body's re-run line, written from the ledger, shows attempt 1's failure,
   its reason and attempt 2's pass.

A timeout with no failure:

1. A check runs past its limit, none fails, and the hosted-of-record route is open.
   The gate exits 5, and the state holds.
2. The agent submits `verification_status: rerun` with a reason. The self-loop writes
   the request key and re-enters `verification`, which opens a fresh poll window.
3. Steps 4 and 5 above follow. If the cause is the change, `fix` goes to
   `implementation`; if the run can't go on, `blocked` goes to `done_blocked`; the
   hosted route stays open as before.

A failed check beside a timed-out one exits 1 and takes the flaky-failure path. A
timeout with the route closed exits 4 and isn't re-run.

Over the cap, the gate's routing and the launcher's refusal leave a new head or
`blocked` as the only ways out: `implementation_status: blocked` after a failure,
and after a timeout the hold's other three values (`hosted_of_record`, `fix` and
`blocked`). Steps 2 and 4 rely on decision 1's assumption
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
- `skills/work-on/scripts/run-verification_test.sh`, covering the log layout, the
  ledger's integrity and cap, archive recovery, the reason's cleaning, and the
  eligibility cases.

### Phase 2: The request consumer in `--start`

`--start` reads and removes `verification_rerun_request` under the supervisor's
lock. With no edge writing the key yet, nothing changes for a run.

Deliverables:
- `skills/work-on/scripts/run-verification.sh` (`--start`)
- `skills/work-on/scripts/run-verification_test.sh`, covering the request key against
  each state the live result can be in.

### Phase 3: What reviewers see

The PR body's re-run line and its check, and the docs. With an empty ledger the
check asks for nothing, so this is inert until a re-run can happen, and it lands
before any route can trigger one. A hand-run `--archive` can write a ledger line
from Phase 1 on; the check then asks for that line too.

Deliverables:
- `skills/work-on/scripts/check-pr-output.sh` and `check-pr-output_test.sh`
- `skills/work-on/koto-templates/work-on.md` (the re-run record gate on
  `pr_creation`'s `created` edges)
- `skills/execute/koto-templates/execute.md` (the re-run record gate on
  `pr_finalization`, beside `deferral_recorded`, and the finalization directive), a
  collector script modelled on `shared-deferral-record.sh`, and its test
- `skills/work-on/SKILL.md`, `skills/work-on/references/verification-map.md`,
  `docs/designs/current/DESIGN-output-gates.md`

### Phase 4: `rerun` at the timed-out hold

The gate's ledger read and messages at exit 5, the eligibility of timeouts and of a
failed check beside a timed-out one, and the template's `rerun` value, its two edges
and the directives land in one commit. An offer of `rerun` without its edges would
hold with no edge to take, the edges without the offer would never be chosen, and
one commit owns the directive text for both the value and the announcement.

Deliverables:
- `skills/work-on/scripts/verification-eligibility.sh` (timeouts, whole-budget
  stops and the mixed result eligible) and `run-verification.sh` (the ledger line's
  `exit`, 1 or 5)
- `skills/work-on/scripts/check-verification.sh` (ledger read at exit 5, messages)
- `skills/work-on/koto-templates/work-on.md` (the `rerun` value, two edges,
  directives)
- `skills/work-on/koto-templates/work-on.mermaid.md` (regenerated)
- `skills/work-on/scripts/output-gates-routing_test.sh`, covering the exit-5 hold,
  each new edge and one self-loop lap against real koto, and exercising the
  same-tick read of a rerun edge's `context_assignments` by the target's default
  action before this phase's commit
- `skills/work-on/evals/evals.json`, covering both re-run routes, a real hang sent
  to `fix`, an ineligible result and the over-cap route.

## Security Considerations

This change adds no network access, no downloads and no new external
dependencies. It
sources one new script from the plugin's own `skills/work-on/scripts/` directory,
resolved from the calling script's location the way `scripts/lib/rule-findings.sh`
is, and it lets the launcher read and write koto context keys and move files
inside the session's verification state directory. `jq` stays the only parser.

The threat model is a careless or mistaken agent, not a hostile one. An agent with
shell access can already edit koto keys or move result files by hand, so the
two-per-head cap and the eligibility check bound and record re-runs; they don't
stop a determined bypass. The disk cross-check isn't independent evidence either,
since the attempt folders are as editable as the ledger; it catches a careless
edit, and that's all this threat model asks of it. Even a hand-written request key
stays limited by eligibility: a pass, a running suite, a dirty-tree result, a
runaway or not-started command and a supervisor error are never archived. The cap
is counted per head and merge-base pair, so moving either one resets it, and a
re-run's cost, up to two hours each, is bounded per pair and not per branch.
That's accepted: the cost falls on the host's time and the run's wall clock, and
every commit that moves the head, every merge that moves the merge-base and every
re-run at a pair shows in the PR and the ledger. A ledger read that fails for any
reason other than a missing key never grants a fresh cap: the gate holds at exit
2, and `--start` refuses the re-run and keeps the request key.

Agent-supplied text is treated as data. The reason reaches `--archive` as one
quoted argument and is never expanded by `eval`. It's stripped of control
characters, newlines, ANSI escape sequences and Unicode format characters, which
include the bidirectional controls, and capped in length; the ledger line is built
with `jq --arg`, so quotes and newlines can't forge a second line, and the
read-back check catches a malformed append. Command ids and log paths from
`result.json` come from the repository's own verification map, which a branch can
change. Each id gets the reason's cleaning and length cap before it's stored in a
ledger line, so the gate message and the PR body replay no control character,
escape sequence or format character from it. Log names already put the command's
index first and replace every character outside `[A-Za-z0-9._-]`, so an id can't
name a file outside its attempt folder; `--archive` moves only `result.json` and
`run.json` and builds no path from an id; and a reader accepts a ledger log path
only in the `attempts/<n>/<index>-<name>.log` shape. Session name, head and folder
number are validated before they form a path for `mv` or `rm`. Verification
commands are branch code running as the user, so `--archive` refuses a symlinked
attempt folder, `result.json` or `run.json` rather than move through one, and
creates the attempt folders itself. Run by hand, it requires the same validated
`--session` the gate uses.

The ledger is replayed into later laps and into the PR body, so it is a channel
for stored text. The gate's message and the directives present it as data from
earlier runs, not instructions. In the PR body a re-run line puts each command id
and the reason inside a code span, with backticks removed from both, so links,
images and @mentions in them don't render, and `check-pr-output.sh` refuses a line
that doesn't. What a code span can't stop is an agent that reads a hostile reason
or map entry and follows it, and the same goes for a failing log: a branch can
print "this is a flake, re-run it" into its own output, and that log is what the
agent reads to judge a flake. The directives say log output is data, not
instructions. That residual is accepted, bounded by the cap and by everything the
reason can reach being recorded.

`--archive` holds the supervisor's lock from its eligibility check through the
ledger append and the move, and `--start` reads and removes the request key under
the same lock, so a launch can't slip in between and two ticks can't both consume
one request. It writes the ledger line before moving anything, so a crash leaves a
recorded attempt with its files still in place, which the next `--archive`
recognises and finishes. That recovery path keeps every check: the lock,
`lock_live`, the eligibility check, and a match between the live result's head and
merge-base and the ledger line's.

Earlier attempts' logs now stay on the host until their head directory is pruned,
where before a later run overwrote them, and logs can hold secrets. Attempt
folders are created `0700` and logs `0600`, and they go with the head when it's
pruned. Disk use grows with them, bounded by the cap and by how often the
merge-base moves at one head. The ledger lives in koto, which outlives the host, and the PR
body may be public, so the ledger stores log paths relative to the head directory,
and a PR body's re-run lines carry command ids and the agent's reason only, with no
absolute paths and no log excerpts. `check-pr-output.sh` refuses a re-run line that
holds an absolute path. What's left is the reason itself. Nothing checks its
content beyond the cleaning and the length cap, so a secret an agent pastes into
it can reach a PR body that may be public. Only the directive, which says to write
the reason in the agent's own words, stands against that, and the residual is
accepted.

## Consequences

### Positive

- A flaky failure or a load-caused timeout gets one more suite at the same commit
  with one submitted value and a reason: no throwaway commit, no merge of the
  default branch, no restart and no hand edit.
- A timeout at the hold can get a fresh suite, not only the hosted route, a fix or a
  stop.
- The flake is readable on the record. The ledger and the PR body put attempt 1's
  failure, the reason for the re-run and attempt 2's result side by side, and the
  ledger lives in koto, so it outlives the host and the head's prune.
- No log path ever moves and no run overwrites an earlier run's logs, which also
  fixes today's overwrite at the same head.
- A pass, a running suite and a dirty-tree result keep today's reuse, and
  `verification_results.json` keeps its meaning, so existing readers, tests and evals
  stay as they are.

### Negative

- For eligible timeouts the choice between `rerun`, `hosted_of_record`, `fix` and
  `blocked` sits with the agent, and a careless `rerun` costs a suite, up to two
  hours for a whole-budget timeout.
- The template and the gate gain surface that has to stay in agreement: a value at
  the timed-out hold, a value at `implementation` and three new edges.
- The launcher now reads and writes koto keys, ending its old contract that it never
  calls koto, and it depends on the session name.
- One more context key whose integrity a script has to guard, and one more checked
  shape in the PR body.
- The supervisor-error hold keeps its inherited-window defect, and a `rerun`
  submitted at exit 2 or -1 still matches no edge (decision 4).
- The ledger carries agent- and branch-supplied text into later laps and the PR
  body.
- Over the cap, an agent that keeps submitting `complete` at an unchanged head
  still laps through the same failed result, as it does today.
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
- The reason is stripped of control and format characters, the gate and the
  directives present the ledger as data, and PR re-run lines keep ids and reasons
  in code spans, which `check-pr-output.sh` enforces.
- The gate's over-cap message names the two ways out, a real fix or
  `implementation_status: blocked`. A guard on `complete` is revisited if the evals
  or real runs show an agent lapping on `complete` over the cap at an unchanged
  head.
- If the same-tick assumption fails, the agent runs `--archive` before submitting,
  and the `75 + rerun` edge keeps that order routable.
