---
schema: design/v1
status: Planned
problem: |
  A director that dispatched a lane can learn what the lane may do only by
  asking it or rereading the brief it wrote, and neither is the answer niwa
  resolves. Separately, any session running the coordinate skill can write
  another lane's active-worker cap through state-stored-set.sh --run cap,
  which checks no authority and doesn't ask whose record it's writing.
decision: |
  A new script, lane-read.sh, finds a lane's instance and session id from
  niwa's dispatch records (niwa list, then niwa lineage show) and asks niwa
  about it through authority-read.sh, the one reader the settled-steps
  scoping adds, reading fresh on every ask. Every new run records its opener
  as driver, and state-stored-set.sh --run cap sorts a write into own or
  cross-lane by the ownership rule the takeover already applies, leaves an
  own write as it is, and for a cross-lane write
  reads the moving session's authority through the same reader and refuses,
  naming the cap-change authority as one niwa grants. The skill spells no
  token for that authority, so until niwa grants one every cross-lane move is
  refused.
rationale: |
  Routing both reads through authority-read.sh keeps niwa authority check in
  one file and puts the lane answer under the same acceptance as every other
  authority read. Finding the lane through niwa's list and lineage, rather
  than the director's record or anything the lane wrote, is what keeps the
  lane out of the answer. Reusing the takeover's ownership rule means a
  coordinator's own cap writes keep working with no read, and a write that
  can't prove it's the writer's own is treated as cross-lane, the safe side.
  Spelling no token costs nothing today, since niwa grants no such authority,
  and keeps the skill from holding a definition niwa can't see.
upstream: docs/prds/PRD-director-reads-lane-authority.md
decision_provenance: inline-resolved
---

# DESIGN: Director Reads Lane Authority

## Status

Planned

## Context and Problem Statement

The coordinate skill's two roles are the manager, which runs one lane, and the
director, which dispatches managers. A director asked what one of its lanes
may do has two sources today: the lane's own claim, which costs a message, and
the brief the director wrote, which says what it meant to grant. niwa resolves
the real answer each time it's asked: a role grants what the workspace declares
for it now, kept inside the grant ceiling and what the dispatcher holds now.
Neither source the director has moves when the workspace changes.

The skill already reads niwa's authority answer in three places, each for the
coordinator's own session: `posture-read.sh` at start, `state-stored-set.sh
--rules` for the standing-rule grant fields, and `need-check.sh` through the
stored copy. The settled-steps design
(`docs/designs/DESIGN-coordinator-authority-settled-steps.md`) replaces
those call sites with one reader, `authority-read.sh`, and adds a per-step read
for merges, closes and releases. No code reads another session's answer.

The lane cap is `--cap`, kept in the coordinator's record as the Run section's
`cap` key and written by `state-stored-set.sh --session S --run cap <n> --by
<who>`. `--session` names whose record is written. The script checks neither
whether the caller drives that record nor any authority, so a session can
write a sibling lane's cap. The `--rules` mode, by contrast, already refuses to
read authority for a record whose `record/meta` names a driver other than
`CLAUDE_CODE_SESSION_ID`.

### What a third session can read today

Measured on this host with niwa 0.40.0, from a session that was neither the
lane nor its dispatcher:

- `niwa list --json` gives each instance's `path`, `name`, `session_name` and
  `dispatch_id`. Its rows also carry an `authority` object, which is the
  dispatch's recorded copy (roles, grant ceiling, a stored grant list), not the
  grant resolved now. This design never reads it.
- `niwa lineage show <dispatch id> --json` gives a `niwa.lineage.chain/v1`
  document whose first entry names the dispatch's `instance` and the
  `session_id` the dispatch launched, with its parent dispatch and session.
- `niwa authority check -C <lane instance root> --session <lane session id>
  --point merge --json` exited 0 in about 0.14 seconds and printed a
  `niwa.authority.check/v1` document: `state` `bound`, `binding` `mapping`, the
  lane's `dispatch_id`, `parent` with the dispatching coordinator's
  `dispatch_id` and `instance`, `grant` (empty for that lane), `level`
  `autonomous` with `level_source` `built-in`, `grant_ceiling_source`
  `workspace`, and for the merge point a `decider` and an `author_exclusion`.
- No authority niwa's policy names is a cap-change authority. The grant
  vocabulary today is `merge-pr`, `close-issue` and `cut-release`.

The read named the point `merge`; niwa takes any point name of the right
form. The skill's settler read names the merge point `merge-pr`, which no
third-session read has used yet; the PLAN's last step measures it.

That read was of a lane whose grant was empty. A third session's read of a
lane whose role grants at least one authority, and of a grant changed between
two reads, hasn't been measured, so this design doesn't claim either works
today. The PLAN's last step measures both on this host, and the PLAN proposes
measuring them before the lane read is built.

Everything else this design touches is a dependency, listed under
Implementation Approach.

## Decision Drivers

- The lane's answer is one fresh `niwa authority check` read of the lane, and
  nothing the lane wrote or said, the brief, the dispatch's role or an earlier
  answer stands in for it (PRD R1, R2, R4).
- Can't tell is an answer, with niwa's state and reason or the read failure,
  and never a fallback (R5, R9).
- A record row narrows, never widens (R6).
- The skill holds no definition, token, level rule or grant table for the
  cap-change authority (R11).
- `niwa authority check` is run from one script under `skills/coordinate/`
  (R12), and that script is the reader the settled-steps scoping adds, not a
  second one.
- A coordinator's own cap writes behave as they do today, with no read, except
  for a writer that can't show the record is its own (R10).
- Bounded like the existing reads, three seconds by default (R13), and working
  on niwa 0.40.0 (R14).

## Considered Options

### Decision 1: How the director finds and reads the lane

Resolved inline. The lookup and the read were settled against what niwa 0.40.0 answers on this host.

#### Chosen: `lane-read.sh`, looking the lane up in niwa's list and lineage

`lane-read.sh --lane <topic>...` takes the lanes a question names, by the
dispatch topic the director's record already uses for each worker. It runs
`niwa list --json` once, from the workspace root (`dc_workspace_root`), the
way `dc_find_session` already does, and for each topic takes the rows whose
`session_name` `dc_session_matches` accepts: the topic's niwa slug, `-`, and
eight lowercase hex digits, never a prefix. `dc_find_session` stops at its
first match and has no deadline, so this feature extends it with a mode its
existing callers don't use, which counts every matching row (more than one is
`ambiguous-lane`) and runs the listing under `dc_with_deadline`. From the one
matching row it takes `path` and `dispatch_id`, and runs `niwa lineage show
<dispatch_id> --json` for the session id the dispatch launched. It then calls
`authority-read.sh --session <lane session id> --instance-root <lane path>
[--point <p>]...` and prints one result per lane.

The director finds its own row in the same listing: the row whose `path` is
its own instance root, the nearest directory at or above its working
directory holding `.niwa/instance.json`, resolved with `pwd -P`. That row's
`dispatch_id` is the director's own, so saying whether the lane's parent is
the director's dispatch costs no read of the director's session. With no
such row, the director has no dispatch of its own and `parent_is_mine` is
false.

#### Alternatives Considered

**Have the agent run `authority-read.sh` directly with ids it assembles.**
Rejected: the lookup, the parent comparison and the can't-tell cases would
live in prose the agent re-derives each time, and the call-count and timeout
acceptance tests would have nothing to run against.

**Take the lane's session id from the director's record.** Rejected: the
record holds what dispatch-worker.sh captured at launch, which is the
director's own note, not niwa's record of the dispatch (R2), and a successor
lane would keep the old id.

**Read `niwa lineage list --json` once for every lane.** Rejected for now: it
gives instance names but not paths, and turning a name into `-C` would assume
where niwa puts instances. `niwa list` gives the path itself.

### Decision 2: Where the cap-move check sits and how it decides

Resolved inline. The ownership rule is the one the takeover already applies.

#### Chosen: inside `state-stored-set.sh --run cap`, by the takeover's ownership rule, with a driver on every new run

**Every new run names its driver.** Ownership rests on `record/meta.driver`,
which today only a takeover or an import writes, so a run no one has taken
over has none. This design has the caller's session id recorded as the run's
driver at every start that opens a fresh run with a valid id: a new run, and
a carry or a carried rotation into a fresh session. The id is the one
`coordinate-open.sh` already checks (`CLAUDE_CODE_SESSION_ID` matching
`^[0-9a-f][0-9a-f-]{7,63}$`, a malformed id counting as none). It is recorded
where `record/meta` is born or arrives: the opener writes it after its own
carry and after a fresh start's legacy import, and the seed `state-open.sh`
makes at `record_open` (and its `--carry` for a discipline's next rotation)
writes it there, since a fresh start's record is seeded after the opener
returns. Ownership then rests on the driver for every run opened after this
change. A start with no valid id records no driver, as today.

The takeover reads "a driver recorded" today as "a takeover has touched this
run": a caller with no id is refused `taken-over` on a run with a driver or a
predecessor, and resumes any other (`coordinate-open.sh`'s caller-with-no-id
branch). With every new run holding a driver, that reading changes to the
run's `record/meta.takeover` being set or the run continuing a predecessor, so
a fresh run with a driver and no takeover still resumes for a caller with no
id as it does today. Because every new run now names its driver, a later
start of that run from a different Claude session id reads it as another
session's run and the takeover rule applies, where today a run with no driver
and no findable name resumes in whichever session starts it.

**The ownership test.** `--run cap` first decides whose record it is writing.
The takeover's `driven_by_another` reads the record itself and exits with
takeover output when a read fails (`failed=takeover_read`), and its coordinator
read calls `state-stored-set.sh --list`, which the cap check can't call from
inside itself. So the shared piece in `dispatch-common.sh` is a predicate over
values, not a moved function: given the record's driver, its coordinator row,
the caller's id and the caller's name, it answers own, another or unknown.

- With a driver recorded: own when it equals the caller's id, another when it
  doesn't.
- With no driver (a run from before this change): own when the coordinator row
  equals the caller's found name, another when the row and the name are both
  present and differ, unknown when either is missing.

The name is the one `dc_claude_name` gives for the caller's id, from a Claude
Code background job's state file under `${DC_CLAUDE_HOME:-$HOME/.claude}`; a
coordinator run in the foreground has none. The coordinator row has to equal
that name exactly; a row holding a dispatch topic or any other address doesn't
match. Beside the predicate, `dispatch-common.sh` gets the caller-id check and
the name derivation, so the opener and the cap check can't read the caller
differently.

Each caller decides what unknown means and keeps its own reads.
`coordinate-open.sh` reads the driver and the coordinator row as it does now,
keeps its `driver_unread` and `read_failed` exits, and reads unknown as "not
someone else's", the permissive reading the takeover has today.
`state-stored-set.sh` feeds the predicate from the record it has already
parsed: the driver from `$WD/parsed.json.meta`, as `rules_grant_read` reads it,
and the coordinator row from the Run section of `$WD/parsed.json`. It reads
unknown, and a meta or coordinator row that won't parse, as a write it can't
show is its own. A caller with no valid id never reaches the predicate: it is
refused `no-session` first.

**The first start needs no reorder.** A coordinator's first cap write happens
at reconcile, after `record_open` seeded the record with the driver, so it is
own by the driver whichever of the cap and the coordinator row is written
first. The reconcile text's order (the cap, then the coordinator's address)
and `state-handover.sh --check`'s gap order (`no-cap` before
`no-coordinator`) stay as they are: neither affects a write the driver already
proves.

**The refusal.** An own write goes ahead with no read, exactly as today. In
order, the check refuses:

- a caller with no valid session id with the case `no-session`, with no read:
  there is no session to read;
- a write the predicate answers unknown for, or whose meta or coordinator row
  won't parse, with the case `unproven-owner`, with no read: the writer can't
  show the record is its own, so the write is treated as cross-lane, and its
  own line says that rather than blaming a missing grant;
- a cross-lane write with no niwa found with the case `no-niwa`, before the
  read, so the reader isn't called;
- any other cross-lane write after calling `authority-read.sh` for the
  caller's own session and instance: the skill names no token for the
  cap-change authority, so no grant niwa returns today can hold it, and the
  case is `not-held` for a bound answer, niwa's state for any other, or the
  reader's `skipped`, `timeout`, `failed` or `refused`.

niwa is found by one `dispatch-common.sh` helper, on PATH, else an executable
`$NIWA_BIN`, the lookup the reader and `rules_grant_read` already make; the
reader, the cap check and `lane-read.sh` all use it, so `no-niwa` means the
same thing in each. Every refusal prints its fixed line, exits 13, and writes
nothing to the target record or any other, and every line names the
cap-change authority as one niwa grants. `state-stored-set.sh` uses 0, 1, 2, 10, 11, 12, 14, 64
and 65 today, so 13 is free and tells a cap-move refusal from a usage error
(64) or a schema refusal (65).

A refused move isn't dropped. The skill text routes it through the record's
existing decision path, in the order that path already takes:

1. **Raise.** Cap writes happen in `wait`, on a person's word. After a refused
   cap write whose `--session` named a record other than the session's own
   (`{{SESSION_NAME}}`), the session submits `event: raise`, the only route from
   `wait` to `decision_raise`. A refusal on its own record (`no-session` or
   `unproven-owner`) raises nothing: the session reports the refusal line and
   stays in `wait`. At `decision_raise` the session runs `state-decision.sh --open
   --source self` with a question that names the move (the target session and
   the cap value) and quotes the refusal line, and options such as the target
   lane setting its own cap on a person's word, or leaving it. `--open` writes
   only the question, the options and the source, so the refusal goes in the
   question: entry evidence is tied to an arrival event at
   `decision_evidence`, and a refusal isn't one.
2. **Take.** `decision_next` routes the new entry to `decision_take`, where
   `--take` hands it to the coordinator's verdict.
3. **Escalate.** At `decision_verdict` the session gives the verdict
   `escalate` with `state-decision.sh --escalate`, which is where the
   recommendation is written. Its other arguments are the ones the shared
   escalation validator already asks for: `--reason`, the refusal line as
   `--context`, the need behind the move as `--problem`, `--grounds
   outside-scope` (another lane's cap is outside the session's scope), and an
   `--option` with its explanation for each option. The escalation goes to
   whoever the session reports to.

The same move is the same target session and the same cap value. While an
entry for that move is open, a second refusal of it doesn't submit `event:
raise`: the session stays in `wait` and the open entry stays the one record
of the move. That is a new instruction the skill-text step adds to `wait`'s
text. The template's existing `decision_raise` rule about not opening a
second entry covers only a parked unit, so it isn't relied on here. The
engine stops only a second raise in the same visit to `decision_raise`, and
nothing in `state-decision.sh` refuses a repeated question across visits, so
the rule rests on the template text and is checked by a walkthrough, not by
an engine test.

No answer to the entry authorizes the write. The refusal stands until niwa
grants the authority; an answer can lead to the target lane setting its own
cap on a person's word, which the own-write path already allows. The entry's
routing is the decision path's, unchanged; this design adds none, and the
target lane's record stays untouched.

#### Alternatives Considered

**Refuse every write to a record the caller doesn't drive, with no read.**
Rejected: it gives the same result today but no place for niwa's answer to land
when the authority exists, and R7 and R9 ask for the read and its reason.

**A separate `cap-check.sh` the template calls before `--run cap`.** Rejected:
the write itself stays open to any caller that skips the template step, so the
check has to live where the write happens.

**Treat a record with no driver as cross-lane.** Rejected: a run from before
this change has no driver recorded, and every cap write of its own would be
refused even where its coordinator row shows the run is the writer's, breaking
R10.

**Leave fresh runs with no driver and order the first start instead.**
Rejected: the coordinator row would have to be written before the cap, and
the row only proves ownership for a coordinator that runs as a named
background job, so a foreground coordinator's first cap write would still be
refused and its run would never leave reconcile.

### Decision 3: How the lane answer is shaped and narrowed

Resolved inline. The narrowing follows the restrict-never-widen rule the standing-rule grant fields use.

#### Chosen: niwa's answer passed through, with the director's narrowing beside it

For a bound lane, `lane-read.sh` prints the accepted answer's `grant`, `level`,
`level_source`, `dispatch_id`, `parent` and `points` unchanged, plus
`parent_is_mine` (the answer's parent dispatch id equals the director's own)
and `narrowed_by`. For any other result it prints `cant_tell` with the reason
and no grant. Nothing in the director's record can add to `grant`;
`narrowed_by` only says which rows hold the lane back.

`narrowed_by` needs the director's record, so `lane-read.sh` takes an optional
`--session <director's koto session>`. With it, the lane's unit is the `unit`
of the Holdings row whose Worker is the lane's topic, read through
`dc_record_read`, and `narrowed_by` holds the pause `pause-read.sh` reports
under `covers` for that unit, given the record's Standing rows from
`state-stored-set.sh --list`. `pause-read.sh` is the one pause evaluator pick,
the dispatch check and the land check share, so a go-ahead that lets the unit
through (its `through`) leaves `narrowed_by` empty, exactly as pick would let
the unit through, and an unreadable condition holds as it does there. Both
scripts are called unchanged. With no Holdings row for the topic,
`narrowed_by` is `[]`. Without `--session`, `narrowed_by` is `[]`: that is
the read a session that is neither the lane nor its dispatcher makes, which
holds no record about the lane.

#### Alternatives Considered

**Merge the rows into one effective grant.** Rejected: a pause stops work, it
doesn't remove an authority, and folding it in would hide niwa's answer behind
the director's arithmetic.

## Decision Outcome

A director asked what a lane may do runs `lane-read.sh` with the lane's topic,
its own session and any points the question names. The script makes one `niwa list` call per
question, one `niwa lineage show` and one authority read per lane, and reads
again on every ask, so a grant the workspace changes shows on the next ask.
A cross-lane cap write is caught where the cap is written: every new run names
its driver, own writes pass untouched, cross-lane writes read the mover's
authority and are refused by the name of an authority niwa grants. The skill holds no token, rule or table for
that authority; when niwa grants one, its name comes from niwa.

## Solution Architecture

### Overview

```
director --lane-read.sh--> niwa list --json        (path, dispatch_id)
                       --> niwa lineage show --json (lane session id)
                       --> authority-read.sh --> niwa authority check -C <lane> --session <lane>
cap write --state-stored-set.sh --run cap--> own?   --> write as today
                                         --> cross --> authority-read.sh (mover) --> refuse
```

### Components

**`skills/coordinate/scripts/authority-read.sh` (from the settled-steps design).**
Unchanged in shape, with one rule pinned: a `--session` given on the command
line is the session asked about and overrides `CLAUDE_CODE_SESSION_ID`, and
`--instance-root` likewise overrides the instance found from the working
directory, so a caller can ask about a session other than its own. The
settled-steps design takes the session from `CLAUDE_CODE_SESSION_ID`; if its
reader doesn't let `--session` override that, this feature's first step
changes the reader so it does. If this feature is built before that scoping's
reader lands, its first step adds the reader to that design's interface and
acceptance, and the settled-steps work picks it up rather than adding
another. The reader finds niwa through the shared lookup below.

**`skills/coordinate/scripts/dispatch-common.sh`.** Gains the ownership
predicate, the caller-id check and the caller-name derivation (Decision 2),
the niwa lookup (PATH, else an executable `$NIWA_BIN`), and the counting,
bounded mode of `dc_find_session` (Decision 1). Each returns a status and
prints only its answer, as the file's other helpers do; the caller decides
what a failure means.

**`skills/coordinate/scripts/coordinate-open.sh` and `state-open.sh`.** Record
the caller's id as the driver at every fresh start with a valid id (Decision
2): the opener after its carry and a fresh start's legacy import, the seed at
`record_open` and its `--carry`. The opener's caller-with-no-id branch reads a
touched run as one whose `record/meta.takeover` is set or which continues a
predecessor. The opener calls the shared predicate with the values it reads
itself and keeps its own exits.

**`skills/coordinate/scripts/lane-read.sh` (new).** The lookup, the read and
the result per lane, as Decision 1 and Decision 3 describe. It makes no
`authority check` call itself; the reader does. Each niwa call it makes, the
listing and each lineage read, is bounded at `NIWA_LOOKUP_SECONDS` (three
seconds by default) through `dc_with_deadline`.

**`skills/coordinate/scripts/state-stored-set.sh --run cap`.** Gains the
ownership check and the cross-lane refusal, feeding the shared predicate
from the record it has already parsed. `--rules` stops calling niwa through
its own `rules_grant_read` and calls the reader instead. That move is the
settled-steps scoping's Phase 1; if that work hasn't landed, this feature's
first phase makes the move along with adding the reader, so R12's one-reader
search holds when this feature ships either way.

**`skills/coordinate/SKILL.md` and `koto-templates/coordinate.md`.** The Bounds
and Authority text says a director reads a lane's allowances with
`lane-read.sh`, never from the lane or the brief, and that moving another
lane's cap needs the cap-change authority, which niwa grants; it says nothing
about who should hold it.

### Key Interfaces

```
lane-read.sh --lane <topic> [--lane <topic>]... [--point <p>]... [--session <director's koto session>]
```

prints one JSON line per lane:

```json
{"lane": "<topic>", "instance": "<path>", "session": "<id>",
 "result": "answer", "grant": [], "level": "autonomous",
 "level_source": "built-in", "dispatch_id": "<id>",
 "parent": {"dispatch_id": "<id>", "instance": "<name>"},
 "parent_is_mine": true, "points": [], "narrowed_by": ["s3"]}
{"lane": "<topic>", "result": "cant_tell", "reason": "not-dispatched: <niwa's reason>"}
```

A can't-tell reason is one of niwa's state with its reason (`not-dispatched`,
`record-unusable`), `no-lane` (no `niwa list` row or no lineage session),
`ambiguous-lane` (more than one `niwa list` row matches the topic, as a
successor lane in a second instance can), `bad-lookup` (a path that isn't
absolute or holds no `.niwa/instance.json`, or a session id that isn't a
lowercase UUID), `no-niwa` (the shared lookup finds none, checked before the
listing), `timeout: niwa list`, `failed: niwa list`, `timeout: niwa lineage
show` or `failed: niwa lineage show` (that call ran past its bound or exited
non-zero), or the reader's `skipped`, `timeout`, `failed` or `refused`. The
lane read and the cap check both say `no-niwa` for a missing niwa: the lane
read needs niwa for its listing before the reader is ever called, so the
reader's `skipped` reaches it only for the reader's other skips. Any reason
text taken from niwa or the reader is cut to one line of at most 200
characters before it's printed.

The PRD's can't-tell cases map onto these reasons. A session in another
instance than the one its lookup names is niwa's `not-dispatched` with
niwa's reason `other-instance`. A session started by hand has no dispatch, so
no `niwa list` row matches its topic and the answer is `no-lane`. A lane
niwa can't use the record of is `record-unusable` with niwa's reason.

The cross-lane cap refusal, on stderr with exit 13, takes one of three forms.
For a bound answer:

```
refused: moving another lane's cap needs the cap-change authority, which niwa grants and this session doesn't hold (not-held)
```

For a write the writer can't show is its own (`unproven-owner`), with no read:

```
refused: this session can't show <session>'s record is its own (no recorded driver and no session name found); a cap write it can't show is its own is treated as cross-lane, which needs the cap-change authority niwa grants (unproven-owner)
```

For any other result, where the read couldn't say, and for `no-session` and
`no-niwa`, where there was no session to read or no niwa to ask:

```
refused: moving another lane's cap needs the cap-change authority, which niwa grants, and this session's authority couldn't be read (<case>)
```

### Data Flow

Nothing is cached. `lane-read.sh` writes nothing; the director reports its
output and may write a row only through the existing record scripts. The cap
check writes nothing on refusal, so the target record's Run section and its
entries stay as they were.

### Where this meets the earlier work

The settled-steps design makes a coordinator take who settles each finishing
step from a fresh authority answer and adds `authority-read.sh` as the only
code that runs `niwa authority check`. This design adds two callers to that
reader and no other call site, so the one-file search both scopings ask for
still finds one file. The lane read reports a point's settler the way that
design reads it, and never acts on it: acting on a settler stays with the
lane's own finishing steps.

tsukumogami/shirabe#1473 gave Standing rows `under_session_grant` and
`session_allows`, read from the session's grant, with a row's words never
widening the grant. The lane answer applies the same rule to another lane: a
row can narrow what the director lets a lane do and never adds to niwa's
grant. The two meet in `authority-read.sh` and in the rule that a row restricts
and never widens. A cap write is a Run key, not a Standing row, so #1473's
fields don't change.

## Implementation Approach

### Phase 1: The shared ownership pieces, the driver at every fresh start, and the reader

Add the ownership predicate, the caller-id check, the caller-name derivation
and the niwa lookup to `dispatch-common.sh`, and have `coordinate-open.sh`
call the predicate with the values it reads, keeping its own exits. Record the
caller's id as the driver at every fresh start with a valid id, and change the
opener's caller-with-no-id branch to read a touched run by `.takeover` or a
predecessor. The takeover's engine tests pass, plus new cases: a fresh run
records its opener as driver, and a fresh run with a driver and no takeover
still resumes for a caller with no id. Use `authority-read.sh` from the
settled-steps work, changing it if `--session` doesn't override the
environment, or, if it hasn't landed, add it to that design's interface and
move `posture-read.sh` and `state-stored-set.sh --rules` onto it, so no
second call site survives.

### Phase 2: The cap-move check

Add the own-or-cross-lane split and the refusal to `state-stored-set.sh --run
cap`, with tests against a stand-in niwa for each case: own write with no
read, cross-lane bound with no such grant, read failure, timeout, no niwa
(`no-niwa`), `not-dispatched`, no valid caller session id (unset or
malformed) with and without a driver recorded (`no-session`), and a write the
writer can't show is its own, an unreadable meta included (`unproven-owner`),
the last two with no call on the stand-in's log and its own record included.
Every refusal exits 13. The existing tests that write a cap get a driver (the
run opened with an id through the opener) or an id plus a `DC_CLAUDE_HOME` job
fixture whose name equals the coordinator row, or expect the refusal.

### Phase 3: The lane read

Add `lane-read.sh` and its tests against a stand-in niwa: bound answer passed
through, a grant changed between two asks showing on the second, a point's
settler, each can't-tell case, a pause row in `narrowed_by` and a go-ahead
that lets the unit through, and two lanes making exactly one `niwa list`, two
`niwa lineage show` and two `niwa authority check` calls.

### Phase 4: The skill text

Update the Bounds and Authority text and the template, including the text that
takes a refused cross-lane move through raise, take and escalate as Decision 2
lays out, raises nothing for a refusal on the session's own record, and keeps
a second refusal of the same move in `wait` while its entry is open. Check
that a search of the executable lines of `skills/coordinate/scripts/*.sh`,
test files (`*_test.sh`) and comment lines excluded, finds an `authority
check` call only in `authority-read.sh`; prose in `SKILL.md`, the references
and comments doesn't count. That closes R12's criterion for the callers that
exist; the finishing-step read's half closes with the settled-steps work.
Walk a refused move through a scratch record to see one escalated entry.

### Phase 5: The whole-feature check

On this host, on niwa 0.40.0. The director is itself a dispatched session
(it has a dispatch id of its own in `niwa list`) and holds at least what the
lane's role grants, since niwa keeps a lane's grant inside its dispatcher's.
It dispatches the lane by hand with `niwa dispatch --role <role>
--parent-from <director instance>`, naming a role the workspace's
`[authority.roles]` grants at least one authority, because the skill's own
lane dispatch gives a lane coordinator no grant (the PLAN's Proposed
Follow-up). If that setup can't be made on this host when the step runs, the
step says so and the director-side criteria stay open. The lane is then read twice over: from the director, whose answer
shows `parent_is_mine` true, and from a session that is neither the lane nor
its dispatcher. Both read the lane from niwa's records alone, and both see a
grant changed between two asks, the change removing an authority from the
lane's role, since niwa keeps a lane's grant inside its dispatcher's and a
widening past that shows no change. A refused cross-lane move closes the run:
the director dispatches a second lane the same way, running
`/shirabe:coordinate` with its own record, and the first lane tries to move
that sibling's cap through the skill.
This is where the third-session read of a lane holding grants is measured. The record lands in "What a third session can read today" above,
as commands with host paths replaced and the result lines read, never full
niwa answers.

Phases 1 to 5 are the PLAN's Steps 1 to 5, each in its own pull request.

### Dependencies on the workspace authority work

None of these is assumed shipped.

- **The cap-change authority.** niwa grants none today, and the workspace
  authority work's design, in progress, is where it gets a name and a grant.
  Until then every cross-lane cap move is refused. When it exists, the check
  needs its name from niwa, and `authority-read.sh` has to accept it in its
  grant vocabulary; until the reader knows the value, an answer carrying it is
  refused and the move still holds. How niwa tells the skill which grant value
  is the cap-change authority is part of this dependency. In the meantime the
  reader's accepted grant vocabulary stays `merge-pr`, `close-issue` and
  `cut-release`, and the bound branch of the cap check compares no grant
  value: the allow path stays unwritten until niwa answers that, which is why
  the check today can only refuse.
- **The soundness of the parent.** tsukumogami/niwa#422: a session without a
  grant can launch a child whose record looks operator-launched, so
  `parent_is_mine` is only as sound as that fix.
- **The per-point settler.** niwa answers a point's settler today, but tying it
  to the authority level is work that hasn't started; the lane read reports
  what niwa answers and claims nothing past it.
- **The settled-steps reader.** The settled-steps design is Planned and its
  PLAN builds `authority-read.sh` first; it isn't built yet.

### Call counts

The acceptance criterion that two lanes make exactly two niwa calls counts
`niwa authority check` calls, the reads R13 bounds. The lookup adds one
`niwa list` per question and one `niwa lineage show` per lane, and the lane
read's tests count those too: one question about two lanes makes one `list`
and two `lineage show` calls on the stand-in's log.

## Security Considerations

The lane read is read-only and asks niwa about sessions in the same workspace;
it reads no file the lane wrote and sends the lane nothing. The lane's
grant, level and dispatch ids are workspace-internal and go no further than the
director's own report.

The cap check closes a gap rather than opening one: today any session can
rewrite a sibling lane's cap. Its failure direction is refusal: a meta it can't
read, a missing caller id or unfound caller name, a failed or slow read, and an
answer the reader refuses all keep the target cap as it is. The refusal's text
is fixed and carries only the case word and the `--session` it was given,
never text from niwa's answer. A caller with no valid session id is refused
`no-session`, so unsetting or mangling the session variable can't turn a
sibling's record into the caller's own.

The lane read checks what it takes from niwa's lookup before using it: the
instance path must be absolute and hold `.niwa/instance.json`, the session id
must be a lowercase UUID, and a topic matching more than one instance is
answered can't tell rather than picked. It reads no other file in the lane's
instance and calls no messaging command.

A forged record can't widen anything. The lane answer comes from niwa, not the
director's record, and record rows only appear as `narrowed_by`. The cap
check's ownership test reads `record/meta`, which a session could edit to name
itself as driver; doing so lets it write that cap as its own. That is the same
exposure the takeover rule has today, and this design doesn't widen it.

## Consequences

### Positive

- A director answers from niwa's current record of a lane and sees a changed
  grant on its next ask.
- No session can move a sibling lane's cap through the skill without an
  authority niwa grants.
- `niwa authority check` still runs from one file, shared with the
  settled-steps work.

### Negative

- Every cross-lane cap move is refused until niwa grants the cap-change
  authority, including moves a person would have approved.
- A lane question costs two niwa calls per lane plus one list.
- The ownership test trusts `record/meta`'s driver, which a session can edit.
- A run from before this change, with no driver and no findable name for its
  coordinator (a coordinator in the foreground, say), can't change its cap
  until a takeover records a driver; its cap stays as it is.
- A start with no valid session id records no driver, so a run opened that way
  can't write its first cap and stays at reconcile with its `no-cap` gap open.
  Scripts and tests that open a run must give it an id.
- A later start of a new run from a different Claude session id is read as
  another session's run and goes through the takeover rule, where today a run
  with no driver and no findable name resumes wherever it's started.

### Mitigations

- The refusal names the missing authority, so the person sees what the
  workspace would have to grant.
- The calls are bounded and made only when a question is asked.
- A pre-change run's limit ends at its next takeover, and every run opened
  after this change names its driver from the start.
- A stronger identity check than the record's driver belongs in niwa, which
  already binds each dispatched session to its instance; the cap check can
  move to that once niwa answers whose lane a record is.
