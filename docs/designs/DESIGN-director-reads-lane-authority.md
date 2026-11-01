---
schema: design/v1
status: Proposed
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
  scoping adds, reading fresh on every ask. state-stored-set.sh --run cap
  sorts a write into own or cross-lane by the ownership rule the takeover
  already applies, leaves an own write as it is, and for a cross-lane write
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

Proposed

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
stored copy. The settled-steps scoping in tsukumogami/shirabe#1496 replaces
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
- `niwa authority check` runs from one place under `skills/coordinate/` (R12),
  and that place is the reader the settled-steps scoping adds, not a second
  one.
- A coordinator's own cap writes behave as they do today, with no read (R10).
- Bounded like the existing reads, three seconds by default (R13), and working
  on niwa 0.40.0 (R14).

## Considered Options

### Decision 1: How the director finds and reads the lane

Resolved inline. The lookup and the read were settled against what niwa 0.40.0 answers on this host.

#### Chosen: `lane-read.sh`, looking the lane up in niwa's list and lineage

`lane-read.sh --lane <topic>...` takes the lanes a question names, by the
dispatch topic the director's record already uses for each worker. For each it
finds the `niwa list --json` row whose `session_name` matches the topic as a
whole name (the matching `dc_session_matches` already does), takes the row's
`path` and `dispatch_id`, and runs `niwa lineage show <dispatch_id> --json` for
the session id the dispatch launched. It then calls `authority-read.sh
--session <lane session id> --instance-root <lane path> [--point <p>]...` and
prints one result per lane. The director's own dispatch id comes from its own
instance's row in the same `niwa list` output, so saying whether the lane's
parent is the director's dispatch costs no read of the director's session.

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

#### Chosen: inside `state-stored-set.sh --run cap`, by the takeover's ownership rule

`--run cap` first decides whose record it is writing, by the rule
`coordinate-open.sh` applies to a takeover: the record is the caller's own
when its `record/meta` names `CLAUDE_CODE_SESSION_ID` as its driver, or, with
no driver recorded, when its coordinator row names the caller's session name.
Every other case is cross-lane: another driver, no driver and another
coordinator, no caller session id at all (with or without a driver recorded),
or a meta or coordinator row that can't be read. The takeover lets a caller
with no session id resume an untouched run; the cap write doesn't take that
exception, because a caller that can't name itself can't show the record is
its own, and taking it would let any such caller write a sibling's cap.

A coordinator's own first-start cap write passes this test only if the
coordinator row is written before the cap. The implementation checks that
order in the template and moves the cap write after the coordinator row if it
isn't already there.

An own write goes ahead with no read, exactly as today. A cross-lane write
calls `authority-read.sh` for the caller's own session and instance, then
refuses: the skill names no token for the cap-change authority, so no grant
niwa returns today can hold it. The refusal prints which case applied
(`not-held` for a bound answer, niwa's state for any other, or the reader's
`skipped`, `timeout`, `failed` or `refused`), names the cap-change authority as
one niwa grants and the session doesn't hold, exits non-zero, and writes
nothing to the target record.

#### Alternatives Considered

**Refuse every write to a record the caller doesn't drive, with no read.**
Rejected: it gives the same result today but no place for niwa's answer to land
when the authority exists, and R7 and R9 ask for the read and its reason.

**A separate `cap-check.sh` the template calls before `--run cap`.** Rejected:
the write itself stays open to any caller that skips the template step, so the
check has to live where the write happens.

**Treat a record with no driver as cross-lane.** Rejected: a coordinator that
was never taken over has no driver recorded, and its own first-start cap write
would be refused, breaking R10.

### Decision 3: How the lane answer is shaped and narrowed

Resolved inline. The narrowing follows the restrict-never-widen rule the standing-rule grant fields use.

#### Chosen: niwa's answer passed through, with the director's narrowing beside it

For a bound lane, `lane-read.sh` prints the accepted answer's `grant`, `level`,
`level_source`, `dispatch_id`, `parent` and `points` unchanged, plus
`parent_is_mine` (the answer's parent dispatch id equals the director's own)
and `narrowed_by`, the ids of the director's live pause rows that cover the
lane's unit (`--on all` or the unit). For any other result it prints
`cant_tell` with the reason and no grant. Nothing in the director's record can
add to `grant`; `narrowed_by` only says which rows hold the lane back.

#### Alternatives Considered

**Merge the rows into one effective grant.** Rejected: a pause stops work, it
doesn't remove an authority, and folding it in would hide niwa's answer behind
the director's arithmetic.

## Decision Outcome

A director asked what a lane may do runs `lane-read.sh` with the lane's topic
and any points the question names. The script makes one `niwa list` call per
question, one `niwa lineage show` and one authority read per lane, and reads
again on every ask, so a grant the workspace changes shows on the next ask.
A cross-lane cap write is caught where the cap is written: own writes pass
untouched, cross-lane writes read the mover's authority and are refused by the
name of an authority niwa grants. The skill holds no token, rule or table for
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

**`skills/coordinate/scripts/authority-read.sh` (from tsukumogami/shirabe#1496).**
Unchanged in shape. This design relies on its `--session` and
`--instance-root` flags naming the session and instance asked about, so a
caller can ask about a session other than its own. If this feature is built
before that scoping's reader lands, its first step adds the reader to that
design's interface and acceptance, and the settled-steps work picks it up
rather than adding another.

**`skills/coordinate/scripts/lane-read.sh` (new).** The lookup, the read and
the result per lane, as Decision 1 and Decision 3 describe. It runs no
`niwa authority check` itself. Each niwa call is bounded at
`NIWA_LOOKUP_SECONDS` (three seconds by default) through `dc_with_deadline`.

**`skills/coordinate/scripts/state-stored-set.sh --run cap`.** Gains the
ownership test and the cross-lane refusal. The ownership test is the one
`coordinate-open.sh` uses, moved into `dispatch-common.sh` so both call it
instead of keeping two copies. `--rules` stops calling niwa through its own
`rules_grant_read` and calls the reader instead. That move is the settled-steps
scoping's Phase 1; if that work hasn't landed, this feature's first phase makes
the move along with adding the reader, so R12's one-reader search holds when
this feature ships either way.

**`skills/coordinate/SKILL.md` and `koto-templates/coordinate.md`.** The Bounds
and Authority text says a director reads a lane's allowances with
`lane-read.sh`, never from the lane or the brief, and that moving another
lane's cap needs the cap-change authority, which niwa grants; it says nothing
about who should hold it.

### Key Interfaces

```
lane-read.sh --lane <topic> [--lane <topic>]... [--point <p>]...
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
lowercase UUID), or the reader's `skipped`, `timeout`, `failed` or `refused`.
`skipped` covers a missing niwa. Any reason text taken from niwa or the
reader is cut to one line of at most 200 characters before it's printed.

The cross-lane cap refusal, on stderr with a non-zero exit, takes one of two
forms. For a bound answer:

```
refused: moving another lane's cap needs the cap-change authority, which niwa grants and this session doesn't hold (not-held)
```

For any other result, where the read couldn't say:

```
refused: moving another lane's cap needs the cap-change authority, which niwa grants, and this session's authority couldn't be read (<case>)
```

### Data Flow

Nothing is cached. `lane-read.sh` writes nothing; the director reports its
output and may write a row only through the existing record scripts. The cap
check writes nothing on refusal, so the target record's Run section and its
entries stay as they were.

### Where this meets the earlier work

tsukumogami/shirabe#1496 makes a coordinator take who settles each finishing
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

### Phase 1: The shared ownership test and the reader

Move the takeover's ownership test into `dispatch-common.sh` and have
`coordinate-open.sh` call it, with its existing tests passing unchanged. Use
`authority-read.sh` from the settled-steps work, or, if it hasn't landed, add
it to that design's interface and move `posture-read.sh` and
`state-stored-set.sh --rules` onto it, so no second call site survives.

### Phase 2: The cap-move check

Add the own-or-cross-lane split and the refusal to `state-stored-set.sh --run
cap`, with tests against a stand-in niwa for each case: own write with no
read, cross-lane bound with no such grant, read failure, timeout, no niwa,
`not-dispatched`, and a driver recorded with no caller session id.

### Phase 3: The lane read

Add `lane-read.sh` and its tests against a stand-in niwa: bound answer passed
through, a grant changed between two asks showing on the second, a point's
settler, each can't-tell case, a pause row in `narrowed_by`, and two lanes
making exactly two `niwa authority check` calls.

### Phase 4: The skill text

Update the Bounds and Authority text and the template, and check that a search
for `niwa authority check` under `skills/coordinate/` finds only the reader.

### Dependencies on the workspace authority work

None of these is assumed shipped.

- **The cap-change authority.** niwa grants none today, and the workspace
  authority work's design, in progress, is where it gets a name and a grant.
  Until then every cross-lane cap move is refused. When it exists, the check
  needs its name from niwa, and `authority-read.sh` has to accept it in its
  grant vocabulary; until the reader knows the value, an answer carrying it is
  refused and the move still holds. How niwa tells the skill which grant value
  is the cap-change authority is part of this dependency, and the skill adds no
  literal for it in the meantime: the allow path stays unwritten until niwa
  answers that, which is why the check today can only refuse.
- **The soundness of the parent.** tsukumogami/niwa#422: a session without a
  grant can launch a child whose record looks operator-launched, so
  `parent_is_mine` is only as sound as that fix.
- **The per-point settler.** niwa answers a point's settler today, but tying it
  to the authority level is work that hasn't started; the lane read reports
  what niwa answers and claims nothing past it.
- **The settled-steps reader** (tsukumogami/shirabe#1496), not yet merged.

### Call counts

The acceptance criterion that two lanes make exactly two niwa calls counts
`niwa authority check` calls, the reads R13 bounds. The lookup adds one
`niwa list` per question and one `niwa lineage show` per lane, and the tests
count those separately.

## Security Considerations

The lane read is read-only and asks niwa about sessions in the same workspace;
it reads no file the lane wrote and sends the lane nothing. The lane's
grant, level and dispatch ids are workspace-internal and go no further than the
director's own report.

The cap check closes a gap rather than opening one: today any session can
rewrite a sibling lane's cap. Its failure direction is refusal: a meta it can't
read, a missing caller id with a driver recorded, a failed or slow read, and an
answer the reader refuses all keep the target cap as it is. The refusal's text
is fixed and carries only the case word, never text from niwa's answer. A
caller with no session id is cross-lane, so unsetting the session variable
can't turn a sibling's record into the caller's own.

The lane read checks what it takes from niwa's lookup before using it: the
instance path must be absolute and hold `.niwa/instance.json`, the session id
must be a lowercase UUID, and a topic matching more than one instance is
answered can't tell rather than picked.

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
- A lane question costs three niwa calls per lane plus one list.
- The ownership test trusts `record/meta`'s driver, which a session can edit.

### Mitigations

- The refusal names the missing authority, so the person sees what the
  workspace would have to grant.
- The calls are bounded and made only when a question is asked.
- A stronger identity check than the record's driver belongs in niwa, which
  already binds each dispatched session to its instance; the cap check can
  move to that once niwa answers whose lane a record is.
