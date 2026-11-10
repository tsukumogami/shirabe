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
  scoping adds, reading fresh on every ask. Every new run records the session
  that opened it in a record/meta field of its own, opened_by, which leaves
  the takeover's driver as it is, and state-stored-set.sh --run cap sorts a
  write into own or cross-lane by a strict form of the takeover's ownership
  rule that reads it, and leaves an own write as it is. A cross-lane write is
  never made by the mover: the script makes no read, writes nothing, prints
  one request line and exits 13, and the skill reads the owning lane through
  lane-read.sh, addresses the request through the delivery facts niwa's
  answer carries for that lane, and sends it; the owner decides it by its own
  rules. niwa defines no cap-change authority by design (tsukumogami/niwa
  docs/designs/DESIGN-authority-read-settlers.md, Decision 4), and the skill
  names none.
rationale: |
  Routing both reads through authority-read.sh keeps niwa authority check in
  one file and puts the lane answer under the same acceptance as every other
  authority read. Finding the lane through niwa's list and lineage, rather
  than the director's record or anything the lane wrote, is what keeps the
  lane out of the answer. Building on the takeover's ownership rule means a
  coordinator's own cap writes keep working with no read, a separate field
  keeps the takeover's contract unchanged, and a write that
  can't prove it's the writer's own is treated as cross-lane, the safe side.
  Turning a cross-lane move into a request follows niwa's own answer for the
  cap: there's no grant to check, the cap is the owning coordinator's
  setting, and the owner, not the mover, writes it. Keeping the address
  lookup in the skill text, through the lane read, leaves the cap check with
  no niwa read and the skill free of any authority of its own.
upstream: docs/prds/PRD-director-reads-lane-authority.md
decision_provenance: inline-resolved
---

# DESIGN: Director Reads Lane Authority

## Status

Planned

Amended: a move of another lane's worker cap is no longer refused by the name
of a cap-change authority niwa might grant later. niwa's design for authority
reads (tsukumogami/niwa `docs/designs/DESIGN-authority-read-settlers.md`,
Decision 4) defines no such authority, as a deliberate non-goal, and routes a
cross-lane cap change as a request to the coordinator that owns the cap.
Decision 2 now has the cap check print a request line for a cross-lane write,
with no read and nothing written, and the skill text reads the owning lane
through `lane-read.sh`, addresses the request through the delivery facts
niwa's answer carries, and sends it; the owner decides it by its own rules.
Decision 1, Decision 3, what `lane-read.sh` prints, the strict ownership test
and `record/meta.opened_by` stand, and so do the PLAN's Steps 1 and 3 and its
step and dependency order. One point is left open rather than decided: the
lane read's line carries the lane's `session` and `instance` but not its
`session_name` or `accepts_session_messages`, so the request is addressed by
session id and the `no-delivery` check waits on a change to Decision 3 that
this amendment doesn't make (Decision 2, "Open point").

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
- No authority niwa's policy names is a cap-change authority, and niwa
  defines none by design: its authority-read design (tsukumogami/niwa
  `docs/designs/DESIGN-authority-read-settlers.md`, Decision 4) makes that a
  deliberate non-goal. The grant vocabulary today is `merge-pr`,
  `close-issue` and `cut-release`.

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
- A change to another lane's cap is a request to the lane that owns it,
  routed through the delivery facts niwa gives for that lane, and never a
  write by the mover (R7, R8).
- The skill names no cap-change authority and holds no definition, token,
  level rule or grant table for one; niwa defines none, by design (R11).
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
`niwa list --json` once per question, from the workspace root
(`dc_workspace_root`), with the niwa binary the shared lookup found and under
`dc_with_deadline`, and matches every topic against that one listing: for
each topic it takes the rows whose `session_name` `dc_session_matches`
accepts, the topic's niwa slug, `-`, and eight lowercase hex digits, never a
prefix. `dc_find_session` can't be called once per lane for this: it runs
`niwa list` itself on every call, with `${NIWA:-niwa}` rather than the shared
lookup, has no deadline, and stops at its first match. So `dispatch-common.sh`
gains, beside it, a helper that takes a listing already fetched and a topic
and counts every matching row (more than one is `ambiguous-lane`);
`dc_find_session` and its callers stay as they are. From the one matching
row it takes `path` and `dispatch_id`, and runs `niwa lineage show
<dispatch_id> --json` for the session id the dispatch launched. It then calls
`authority-read.sh --session <lane session id> --instance-root <lane path>
[--point <p>]...` and prints one result per lane.

The director finds its own row in that same listing, with no second `niwa
list` call: the row whose `path` is
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

### Decision 2: Where the cap-move check sits and how a cross-lane move becomes a request

Resolved inline. The ownership rule is a strict form of the one the takeover
already applies, reading one new field the takeover never reads. What
happens to a cross-lane move follows niwa's design for authority reads
(tsukumogami/niwa `docs/designs/DESIGN-authority-read-settlers.md`, Decision
4), which defines no cap-change authority and routes a cross-lane cap change
as a request to the coordinator that owns the cap.

#### Chosen: inside `state-stored-set.sh --run cap`, by a strict ownership test, with the opener recorded on every new run and a cross-lane move turned into a request to the cap's owner

**The driver stays as it is.** `record/meta.driver` is written only by a
takeover, so a run no one has taken over has none, and the takeover reads a
recorded driver as "a takeover has touched this run": a caller with no id is
refused `taken-over` on a run with a driver or a predecessor, and resumes any
other. None of that changes. `driven_by_another`, the caller-with-no-id
branch, `takeover_check`'s outcomes and the takeover text in `SKILL.md` stay
exactly as they are, so a run opened under one Claude session id and later
started under another resumes, carries or is taken over just as it does
today.

**Every new run names the session that opened it.** A new field,
`record/meta.opened_by`, holds the Claude session id that admitted the run:
the id `coordinate-open.sh` already checks (`CLAUDE_CODE_SESSION_ID` matching
`^[0-9a-f][0-9a-f-]{7,63}$`, a malformed id counting as none). Only the cap
check reads it. It is written in the write that births `record/meta`, so no
crash between two writes can leave a fresh run without it:

- the seed's meta, which `core_write_session` builds when `state-open.sh`
  seeds the record at `record_open` or `--carry`s a discipline's next
  rotation (a fresh start's record is seeded after the opener returns);
- `core_carry`'s meta, when the opener carries a run into a new one;
- `core_import_meta`'s meta, when a fresh start's legacy import
  (`legacy-import/import.sh`) fills the record.

`state-open.sh`, the opener and the importer pass the caller's id into the
write core, which puts it in that meta. A seed's first `record/meta` write,
the pending one, already holds it, and a seed cut short and seeded again
writes it again. The seed with the test override (`--skip-session-checks`)
writes it the same way when a valid id is set, and none when it isn't.

After birth, the opener writes it through its existing meta write
(`meta_set`, through `core_write_meta`) in two places: on a resume it admits
as the caller's own or as unknown (the permissive reading the takeover
already has), and after an import it resumes on a koto older than 0.32.0,
whose copy keeps the source host's `record/meta`. A caller with no valid id
writes nothing. A failed write there doesn't fail the start: it prints
`warning=opener-unrecorded` after `session=`, the reason on stderr, and the
next start writes it, as a failed rules-digest write does. Every other
record write keeps the field as it is. The comments that say only the opener
writes record/meta's extra fields, and only between the fence and the end of
a takeover (`coordinate-open.sh`'s `meta_set`, `state-write-core.sh`'s
`core_write_meta`), are rewritten to name `opened_by` and its writers. The
rewrite drops the claim that no one else writes while the meta is written:
a resume's write can run while the earlier session is still writing. So the
resume write is skipped when `opened_by` already names the caller, and
otherwise re-reads the meta and rewrites only `opened_by`. The re-read alone
narrows the window but doesn't close it: two sessions writing the same record at once can
still lose one write. A lost `opened_by` ends in a refusal, never a widened
write. A resume write that lands over the other session's record write can
roll back the meta's other fields (`written`, `standing_used`, `pending`),
and a rolled-back `standing_used` could hand out a Standing id twice. The
build must close that: a resume that runs while another session is writing
the record never rolls back `record/meta` and never produces a duplicate
Standing id. That is a constraint on Step 1, with its own criterion there;
how it's met (a lock, a compare-and-write on `written`, or another way) is
the build's choice, made in Step 1's pull request. `SKILL.md` lists `warning=opener-unrecorded`
beside `warning=rules-unrecorded`, saying what it means and that the next
start writes the opener.

**The ownership test.** `--run cap` first decides whose record it is writing.
The takeover's `driven_by_another` reads the record itself and exits with
takeover output when a read fails (`failed=takeover_read`), and its coordinator
read calls `state-stored-set.sh --list`, which the cap check can't call from
inside itself. So the shared pieces in `dispatch-common.sh` are predicates
over values, not a moved function, each answering own, another or unknown.

The takeover's test, given the record's driver, its coordinator row, the
caller's id and the caller's name, is today's rule restated with its meaning
unchanged: with a driver recorded, own when it equals the caller's id and
another when it doesn't; with none, own when the coordinator row equals the
caller's found name, another when the row and the name are both present and
differ, unknown when either is missing. It never reads `opened_by`.

The cap's strict test takes `opened_by` as well:

- a driver equal to the caller's id is own;
- any other driver is another;
- no driver and `opened_by` equal to the caller's id is own;
- no driver and a coordinator row equal to the caller's found name is own;
- no driver and an `opened_by` that names another session is another;
- anything else is unknown.

The fifth branch is what lets a real sibling's record become a request. Only
a takeover writes the driver, so a lane's run that no takeover has touched
has none, and its `opened_by` names the lane. Without that branch a sibling's
record would read unknown and be refused `unproven-owner` with no read, and
the move would never reach the lane that owns the cap. A run from before this feature has no `opened_by`
and falls to the driver and coordinator-row branches, as before. A takeover's
new run keeps its predecessor's `opened_by`, but the takeover records a
driver, which the first two branches read first, so `opened_by` decides
nothing there and `finish_takeover` doesn't write it.

`opened_by` names the run's latest opener: the session that opened it, or the
last one to resume it (see below). "Own" for the cap means the latest opener,
or the coordinator its row names, not whichever session first opened it.

The name is the one `dc_claude_name` gives for the caller's id, from a Claude
Code background job's state file under `${DC_CLAUDE_HOME:-$HOME/.claude}`; a
coordinator run in the foreground has none. The coordinator row has to equal
that name exactly; a row holding a dispatch topic or any other address doesn't
match. Beside the predicates, `dispatch-common.sh` gets the caller-id check and
the name derivation. The cap check and every writer of `opened_by` (the
opener, `state-open.sh` and the importer) source them, so none reads the
caller differently.

Each caller decides what unknown means and keeps its own reads.
`coordinate-open.sh` reads the driver and the coordinator row as it does now,
keeps its `driver_unread` and `read_failed` exits, and reads unknown as "not
someone else's", the permissive reading the takeover has today.
`state-stored-set.sh` feeds the strict test from the record it has already
parsed: the driver and `opened_by` from `$WD/parsed.json.meta`, as
`rules_grant_read` reads the driver, and the coordinator row from the Run
section of `$WD/parsed.json`. It reads unknown, and a driver or `opened_by`
that isn't a string, as a write it can't show is its own. A record the schema
refuses never gets this far: a write mode refuses it with 10, as today. A
caller with no valid id never reaches the test: it is refused `no-session`
first. The check runs right after that parse and before `lib_write_guard`,
so a cross-lane move always becomes a request and never meets the guard's
exit 10, which refuses a target run that fails provenance or isn't its
scope's live run. An own write passes the check and then meets the guard
exactly as today. A cross-lane write to a target that isn't live still
prints the request line, which changes nothing it writes.

The two parse the driver differently, and that's named rather than shared:
the opener's `meta_field` reads a number as no driver and a boolean as its
text, while the cap check reads any driver that isn't a string as unreadable,
the strict side. Only a takeover writes the driver, always as a string, so
the two parses part only on a record edited by hand.

**The first start needs no reorder.** A coordinator's first cap write happens
at reconcile, after `record_open` seeded the record with `opened_by`, so it
is own by `opened_by` whichever of the cap and the coordinator row is written
first. The reconcile text's order (the cap, then the coordinator's address)
and `state-handover.sh --check`'s gap order (`no-cap` before
`no-coordinator`) stay as they are: neither affects a write `opened_by`
already proves.

**What the check does with a write.** An own write goes ahead with no read,
exactly as today. In order, the check stops:

- a caller with no valid session id with the case `no-session`, with no read:
  there is no session to read, so it can't show whose record it's writing;
- a write the strict test answers unknown for, or whose driver or
  `opened_by` isn't a string, with the case `unproven-owner`, with no read:
  the writer can't show the record is its own, so the write isn't made, and
  its own line names the cause that fired;
- every cross-lane write, with the case `requested`, with no read. The mover
  never writes another lane's record. The script writes nothing and prints
  one fixed line saying the cap is another lane's and the move goes as a
  request to that lane's owner, naming the target session and the cap value.

The first two cases are about the mover proving the record is its own, not
about any authority, and they stay as they were. Only their lines changed,
so neither names an authority.

The script makes no niwa call for a cap write of any kind, so it has no
`no-niwa` case: the call the check used to make to `authority-read.sh` for
the mover is gone, and a cap write costs no read in the script. Every line
exits 13 and writes nothing to the target record or any other.
`state-stored-set.sh` uses 0, 1, 2, 10, 11, 12, 14, 64 and 65 today, so 13
is free and tells a cap write that wasn't made here from a usage error (64),
a schema refusal (65) or the guard's refusal (10). Exit 13 means "not
written here": for `requested`, the move is a request the skill sends; for
`no-session` and `unproven-owner`, the writer couldn't show the record is
its own. It no longer means "refused for a missing authority".

**A cross-lane move is a request.** A change to another lane's cap is a
request routed through the authority facts niwa already grants, and the lane
that owns the cap decides it. The constraint is niwa's: its design for
authority reads (tsukumogami/niwa
`docs/designs/DESIGN-authority-read-settlers.md`, Decision 4) defines no
cap-change authority, as a deliberate non-goal, and routes a cross-lane cap
change as a request to the coordinator that owns the cap, through the
delivery facts its Decision 3 adds. That coordinator decides it by its own
rules. The skill names no cap-change authority and adds no grant of its own.

**The skill addresses and sends the request.** The address lookup and the
send live in the skill text, not the script. On a `requested` line for
another lane's record, the session reads the owning lane with `lane-read.sh
--lane <topic>`, with no `--session`, so no narrowing read is made: one
`niwa list`, one `niwa lineage show` and one authority read, all of the
target lane, and none of the moving session. The topic is the dispatch topic
the session knows that lane by, from the word that asked for the move or its
own records; a topic niwa lists no lane for is the lane read's `no-lane`.

From a bound line, the session addresses the request through the delivery
facts niwa's answer carries for that lane: following niwa's Decision 4, the
lane's `session_name` when present, else its `session_id`, with its
instance. What the lane read prints today (Decision 3 and Key Interfaces)
carries the lane's session id as `session` (taken from niwa's lineage, the
same value niwa's answer names as `session.session_id`) and its instance as
`instance` (the instance path, whose base name is niwa's
`session.instance`). So the address the skill builds today is `session` at
`instance`.

**Open point: the lane's name and whether it takes messages.** The lane
read's line doesn't carry the lane's own `session_name` or
`accepts_session_messages`. niwa's answer carries those two only inside
`parent`, for the seat above the session asked about, and the lane read
passes `parent` through as it is. So the skill can't prefer the lane's name
over its id, and it can't tell a lane that takes no session messages, the
`no-delivery` case, from one that does. Carrying either field is a change to
Decision 3 and to what `lane-read.sh` prints, which this amendment doesn't
make. Until that change is reviewed and made, the skill addresses by
session id and instance and doesn't check `no-delivery`; a request sent to a
lane that takes no session messages goes unanswered, and the session's
fallback for an unanswered request is the decision path below.

The session then sends the request as a message to that address, through
the message route it already uses, quoting the `requested` line and saying
the need behind the move, and reports that it sent it. It raises no decision
entry for a request that went out. The owning coordinator decides it by its
own rules; if it agrees, it sets its own cap through the own-write path,
which already passes the check. No reply authorizes the mover to write the
other lane's record, and the mover doesn't retry the write or reach the same
cap another way.

The same move is the same target session and the same cap value. While a
request for a move is unanswered, a second `requested` line for it isn't
sent again; the session reports that the first is still out. The session
keeps no record row for a request it sent, so that rule rests on the template
text and the session's own report of what it sent, and is checked by a
walkthrough, not by an engine test.

**When no request can go out.** The skill text checks the lane read's
result, and these cases send nothing and take the decision path: no niwa
(the lane read's `no-niwa`); niwa's state for the lane (`not-dispatched`
with its reason, `record-unusable`); the lane read's lookup reasons
(`no-lane`, `ambiguous-lane`, `bad-lookup`, a listing or lineage call that
timed out or failed); the reader's `skipped`, `timeout`, `failed` or
`refused`; and, once Decision 3 carries the field, `no-delivery`. A
`no-session` or `unproven-owner` line for another lane's record takes the
same path, since no request was formed.

A cross-lane cap write is made only from `wait`, on a person's word (the
session's own first cap is written at reconcile). After a cap write whose
`--session` named a record other than the session's own
(`{{SESSION_NAME}}`) ends in one of those cases, the move takes the record's
existing decision path, unchanged in its mechanics, in the order that path
already takes:

1. **Raise.** The session submits `event: raise`, the only route from `wait`
   to `decision_raise`. A stopped write on its own record raises nothing and
   sends nothing, whatever its case: `no-session`, `unproven-owner`, or
   `requested` for a session whose run another session has resumed since.
   The session reports the line and stays in `wait`. At `decision_raise` the
   session runs `state-decision.sh --open --source self` with a question that
   names the move (the target session and the cap value) and quotes the line
   and the reason no request went out, and options such as the target lane
   setting its own cap on a person's word, or leaving it. `--open` writes
   only the question, the options and the source, so the line goes in the
   question: entry evidence is tied to an arrival event at
   `decision_evidence`, and a stopped write isn't one.
2. **Take.** `decision_next` routes the new entry to `decision_take`, where
   `--take` hands it to the coordinator's verdict.
3. **Escalate.** At `decision_verdict` the session gives the verdict
   `escalate` with `state-decision.sh --escalate`, which is where the
   recommendation is written. Its other arguments are the ones the shared
   escalation validator already asks for: `--reason`, the line and the
   reason as `--context`, the need behind the move as `--problem`, `--grounds
   outside-scope` (another lane's cap is outside the session's scope), and an
   `--option` with its explanation for each option. The escalation goes to
   whoever the session reports to.

An entry is open while it's `proposed`, `coordinator-verdict` or
`escalated`, and no longer once it's `settled`, so the same move stopped
again after the answer raises again. While an entry for that move is open, a
second stop of it doesn't submit `event: raise`: the session stays in `wait`
and the open entry stays the one record of the move. That is a new
instruction the skill-text step adds to `wait`'s text. The template's
existing `decision_raise` rule about not opening a second entry covers only a
parked unit, so it isn't relied on here. The engine stops only a second raise
in the same visit to `decision_raise`, and nothing in `state-decision.sh`
refuses a repeated question across visits, so the rule rests on the template
text and is checked by a walkthrough, not by an engine test.

No answer to the entry authorizes the write: the mover never makes a
cross-lane write. An answer can lead to the target lane setting its own cap on
a person's word, which the own-write path already allows. The entry's routing
is the decision path's, unchanged; this design adds none, and the target
lane's record stays untouched.

#### Alternatives Considered

**Refuse by the name of a cap-change authority niwa might grant later.**
This design's earlier choice: read the mover's own authority and refuse,
naming the cap-change authority as one niwa grants, so every move was
refused until niwa granted one. Rejected: niwa's Decision 4 says no such
authority will exist, so the refusal would name something no workspace can
grant, and the raise, take and escalate route behind it would be a dead end
for every move.

**Refuse every cross-lane move, with no route.** niwa's Decision 4 calls a
caller that does this correct. Rejected: it drops the requirement that a
move reach the lane that owns the cap and leaves only an escalation, which
can't change that cap either.

**The skill defines its own cap-change grant.** A rule in the skill, or a
Standing row, saying which sessions may move which caps. Rejected: the skill
defines no authority of its own (R11), and a grant niwa can't see is the
second source of truth the PRD rules out.

**The mover writes the other lane's record once the owner says yes.**
Rejected: the write would still cross lanes, a reply would act as an
authority the record can't check, and the owner can set its own cap through
the own-write path.

**Look the address up inside `state-stored-set.sh`.** The script would take
the target lane's topic, run the lane read itself and print the address.
Rejected: it puts a niwa read and its failure cases into a gate script, and
makes the cap check depend on the lane read's step. The skill text already
lands after the lane read, and a request is the session's to send.

**Address the request from the target record's coordinator row.** Rejected:
the row is what the lane wrote about itself, may hold a dispatch topic rather
than an address, and isn't niwa's. Decision 4 routes the request through
niwa's delivery facts, which the lane read already reads.

**Record the opener as the run's driver.** Rejected: the takeover reads a
recorded driver as a run a takeover has touched, so every later start under
a new Claude session id would become a takeover, a carry of a live run on an
old template or with several live runs would be refused where it carries
today, and an import a koto older than 0.32.0 resumes would keep the source
host's driver. A field only the cap check reads changes none of that.

**A separate `cap-check.sh` the template calls before `--run cap`.** Rejected:
the write itself stays open to any caller that skips the template step, so the
check has to live where the write happens.

**Treat a record with no driver as cross-lane.** Rejected: a run from before
this change has no driver recorded, and every cap write of its own would be
stopped even where its coordinator row shows the run is the writer's,
breaking R10.

**Leave fresh runs with no opener recorded and order the first start instead.**
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

A narrowing that can't be read is never printed as `[]`, which would report a
lane no pause holds. When `dc_record_read` returns 2, `state-stored-set.sh
--list` fails or exits 65, or `pause-read.sh` exits 2 (a file it couldn't
read, or a condition read that ran out of time), the line prints
`narrowed_by: null` and `narrowing_unread` naming the read that failed, cut
like any other reason, and still prints niwa's grant: the lane's answer is
niwa's, and only the director's narrowing is unknown.

With `--session`, `pause-read.sh` reads each pause's condition live from
GitHub (`gh pr view <n> --repo R --json state` for a `merged` condition, `gh
api --method GET repos/R/git/ref/tags/T` for a `tag` condition), under
board-lib's own deadline. Those reads aren't niwa calls and aren't counted
with them.

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
the session that opened it, own writes pass untouched, and a cross-lane write
is never made by the mover. The script prints a request line, with no read,
and the session reads the owning lane with `lane-read.sh`, addresses the
request through the delivery facts niwa's answer carries, and sends it; that
lane decides it by its own rules. niwa defines no
cap-change authority, by design, and the skill names none.

## Solution Architecture

### Overview

```
director --lane-read.sh--> niwa list --json        (path, dispatch_id)
                       --> niwa lineage show --json (lane session id)
                       --> authority-read.sh --> niwa authority check -C <lane> --session <lane>
cap write --state-stored-set.sh --run cap--> own?   --> write as today
                                         --> cross --> request line, exit 13 (no read)
session   --lane-read.sh (target lane)--> address --message route--> the owning lane (it decides; it writes its own cap)
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

**`skills/coordinate/scripts/dispatch-common.sh`.** Gains the two ownership
predicates, the caller-id check and the caller-name derivation (Decision 2),
the niwa lookup (PATH, else an executable `$NIWA_BIN`), and the helper that
counts a topic's matching rows in a listing already fetched (Decision 1).
Each returns a status and prints only its answer, as the file's other helpers
do; the caller decides what a failure means.

**`skills/coordinate/scripts/state-write-core.sh`, `state-open.sh`,
`coordinate-open.sh` and `legacy-import/import.sh`.** Record the caller's id
as `record/meta.opened_by` in the write that births `record/meta` (Decision
2): the seed's meta in `core_write_session`, for `state-open.sh` at
`record_open` and its `--carry`; `core_carry`'s meta, for the opener's carry;
and `core_import_meta`'s, for the legacy importer. The opener also writes it
on a resume it admits as own or unknown and after an import it resumes on a
koto older than 0.32.0. The opener calls the takeover's predicate with the
values it reads itself and keeps its own exits; its takeover rules don't
change.

**`skills/coordinate/scripts/lane-read.sh` (new).** The lookup, the read and
the result per lane, as Decision 1 and Decision 3 describe. It makes no
`authority check` call itself; the reader does. Each niwa call it makes, the
listing and each lineage read, runs the binary the shared lookup found and is
bounded at `NIWA_LOOKUP_SECONDS` (three
seconds by default) through `dc_with_deadline`. The skill also runs it to
address a cap request (Decision 2); what it prints doesn't change for that.

**`skills/coordinate/scripts/state-stored-set.sh --run cap`.** Gains the
ownership check and the request line: a cross-lane write makes no read,
writes nothing and prints the `requested` line, feeding the strict test from
the record it has already parsed. It no longer calls `authority-read.sh`
for the mover, and makes no niwa call for a cap write. `--rules` stops calling niwa through
its own `rules_grant_read` and calls the reader instead. That move is the
settled-steps scoping's Phase 1; if that work hasn't landed, this feature's
first phase makes the move along with adding the reader, so R12's one-reader
search holds when this feature ships either way.

**`skills/coordinate/SKILL.md` and `koto-templates/coordinate.md`.** The Bounds
and Authority text says a director reads a lane's allowances with
`lane-read.sh`, never from the lane or the brief, and that a change to
another lane's cap is a request to the lane that owns it, which that lane
decides by its own rules. It names no cap-change authority and says nothing
about who may move a cap. The template's `wait` text, on a `requested` line
for another lane's record, reads that lane with `lane-read.sh`, addresses
the request from the line's `session` and `instance`, and sends it, and takes
a move it can't address through the decision path (Decision 2).

### Key Interfaces

```
lane-read.sh --lane <topic> [--lane <topic>]... [--point <p>]... [--session <director's koto session>]
```

`--session` here is the director's koto session, as it is for the record
scripts (`state-stored-set.sh`, `state-decision.sh`), not a Claude session
id as it is for `authority-read.sh`. `lane-read.sh` passes the reader the
lane's Claude session id, which it takes from niwa's lineage. It prints one
JSON line per lane:

```json
{"lane": "<topic>", "instance": "<path>", "session": "<id>",
 "result": "answer", "grant": [], "level": "autonomous",
 "level_source": "built-in", "dispatch_id": "<id>",
 "parent": {"dispatch_id": "<id>", "instance": "<name>"},
 "parent_is_mine": true, "points": [], "narrowed_by": ["s3"]}
{"lane": "<topic>", "result": "cant_tell", "reason": "not-dispatched: <niwa's reason>"}
```

A bound answer whose narrowing couldn't be read carries `"narrowed_by": null,
"narrowing_unread": "<the read that failed>"` in place of the list
(Decision 3).

A can't-tell reason is one of niwa's state with its reason (`not-dispatched`,
`record-unusable`), `no-lane` (no `niwa list` row or no lineage session),
`ambiguous-lane` (more than one `niwa list` row matches the topic, as a
successor lane in a second instance can), `bad-lookup` (a path that isn't
absolute or holds no `.niwa/instance.json`, or a session id that isn't a
lowercase UUID), `no-niwa` (the shared lookup finds none, checked before the
listing), `timeout: niwa list`, `failed: niwa list`, `timeout: niwa lineage
show` or `failed: niwa lineage show` (that call ran past its bound or exited
non-zero), or the reader's `skipped`, `timeout`, `failed` or `refused`. The
lane's session id is held to a lowercase UUID, stricter than the caller-id
check, because it comes from niwa's record rather than this session's own
environment and is passed straight to `niwa authority check`; the lane
read's stand-in niwa gives UUIDs. The lane read says `no-niwa` for a missing niwa, and so does the skill's address read for a cap request, which is a lane read: the lane
read needs niwa for its listing before the reader is ever called, so the
reader's `skipped` reaches it only for the reader's other skips. Any reason
text taken from niwa or the reader is cut to one line of at most 200
characters before it's printed.

The PRD's can't-tell cases map onto these reasons. A session in another
instance than the one its lookup names is niwa's `not-dispatched` with
niwa's reason `other-instance`. A session started by hand has no dispatch, so
no `niwa list` row matches its topic and the answer is `no-lane`. A lane
niwa can't use the record of is `record-unusable` with niwa's reason.

The cap write's arguments don't change. When the cap isn't written here,
the script prints one of three fixed lines on stderr and exits 13, with no
read. For a cross-lane write (`requested`):

```
request: <session>'s cap is another lane's, so setting it to <n> goes as a request to that lane's owner; nothing was written (requested)
```

The line carries no address: the skill finds it afterward with the lane read
(Decision 2). The address the skill builds is `<session> at <instance>` from
the lane read's bound line, both already checked by the lane read (a
lowercase UUID, an absolute path holding `.niwa/instance.json`).

For a writer with no valid session id (`no-session`), on any record, its own
included, with no read:

```
refused: this session has no session id (CLAUDE_CODE_SESSION_ID), so it can't show whose record <session> is, and a cap write it can't show is its own isn't made (no-session)
```

For a write the writer can't show is its own (`unproven-owner`), with no read,
naming the cause that fired:

```
refused: this session can't show <session>'s record is its own (<cause>), and a cap write it can't show is its own isn't made (unproven-owner)
```

The cause is one of a closed set, in the order the strict test reaches them:

- `the record's driver or opener couldn't be read` (a driver or `opened_by`
  that isn't a string);
- `no recorded driver or opener, and no session name found for it`;
- `no recorded driver or opener, and no coordinator row`;
- `no recorded driver or opener, and the coordinator row names another
  session`.

An `opened_by` naming another session never reaches this list: the strict
test reads it as another, so the write becomes a request.

No line names a cap-change authority, and none carries a grant vocabulary
value.

### Data Flow

Nothing is cached. `lane-read.sh` writes nothing; the director reports its
output and may write a row only through the existing record scripts. The cap
check writes nothing whenever it doesn't write the cap (a request or a
refusal), so the target record's Run section and
its entries stay as they were. The request travels as a message the session
sends; the script itself sends nothing.

### Where this meets the earlier work

The settled-steps design makes a coordinator take who settles each finishing
step from a fresh authority answer and adds `authority-read.sh` as the only
code that runs `niwa authority check`. This design adds one caller to that
reader, `lane-read.sh`, which the skill also runs to address a cap request,
and no other call site, so the one-file search both scopings ask for still
finds one file. The lane read reports a point's settler the way that
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

### Phase 1: The shared ownership pieces, the opener on every new run, and the reader

Add the two ownership predicates, the caller-id check, the caller-name
derivation and the niwa lookup to `dispatch-common.sh`, and have
`coordinate-open.sh` call the takeover's predicate with the values it reads,
keeping its own exits. Record `opened_by` in the seed's, the carry's and the
legacy import's `record/meta`, passed into the write core, and have the opener
write it on a resume it admits as own or unknown and after an import it
resumes on an older koto. The takeover's contract doesn't change: its engine
tests pass unchanged, a run opened under one id and started under another
behaves exactly as today, and new cases show `opened_by` set at each place it
is written. Use `authority-read.sh` from the settled-steps work, changing it
if `--session` doesn't override the environment or it doesn't use the shared
niwa lookup, or, if it hasn't landed, add it to that design's interface and
move `posture-read.sh` and `state-stored-set.sh --rules` onto it, so no
second call site survives.

### Phase 2: The cap-move check

Add the own-or-cross-lane split and the request line to `state-stored-set.sh
--run cap`. Tests against a stand-in niwa cover each case, with no call on
the stand-in's log in any of them: own write; cross-lane write (`requested`,
whether the target is live or not); no valid caller session id (unset or
malformed) with and without a driver recorded (`no-session`); and a write
the writer can't show is its own, one case per cause (`unproven-owner`), its
own record included. Every line exits 13 and writes nothing. The existing tests that write a cap set or unset both
`CLAUDE_CODE_SESSION_ID` and `DC_CLAUDE_HOME` themselves, so none depends on
the environment it runs in, and either seed their run with the caller's id
(so `opened_by` is the caller) or give an id plus a `DC_CLAUDE_HOME` job
fixture whose name equals the coordinator row, or expect the exit-13 line.
`references/state-keys.md` gets exit 13, the request line and the case
words.

### Phase 3: The lane read

Add `lane-read.sh` and its tests against a stand-in niwa: bound answer passed
through, a grant changed between two asks showing on the second, a point's
settler, each can't-tell case, a pause row in `narrowed_by`, a go-ahead
that lets the unit through, a narrowing that can't be read, niwa found only
in `NIWA_BIN`, and two lanes making exactly one `niwa list`, two `niwa
lineage show` and two `niwa authority check` calls.

### Phase 4: The skill text

Update the Bounds and Authority text and the template, including the text
that, on a `requested` line for another lane's record, reads that lane with
`lane-read.sh`, addresses the request from the line's `session` and
`instance`, sends it as a message with the need behind the move and raises no
entry for it, doesn't send a second request
for the same move while the first is unanswered, takes a cross-lane move
whose lane read gave no address (no niwa, niwa's state for the lane, a
lookup reason, or the reader's `skipped`, `timeout`, `failed` or `refused`)
through raise, take and escalate as Decision 2 lays out, raises and sends nothing for a stopped write on the session's
own record, and keeps a second stop of the same move in `wait` while its
entry is open, and the reconcile text that has a session report a stopped
first cap's line and stay at reconcile. The text names no cap-change
authority, and a wording test checks that no line does. Check that a search of the executable lines of
`skills/coordinate/scripts/*.sh`, test files (`*_test.sh`) and comment lines
excluded, finds a line that runs niwa's `authority check` as a command only
in `authority-read.sh`; a message string naming the command doesn't count,
nor does prose in `SKILL.md`, the references and comments. That closes R12's criterion for the callers that
exist; the finishing-step read's half closes with the settled-steps work.
Walk a requested move through a scratch record to see one message and no
entry, and a move whose address couldn't be read to see one escalated
entry.

### Phase 5: The whole-feature check

On this host, on niwa 0.40.0. The director is itself a dispatched session
(it has a dispatch id of its own in `niwa list`) and holds at least what the
lane's role grants, since niwa keeps a lane's grant inside its dispatcher's.
It dispatches the lane by hand with `niwa dispatch --role <role>
--parent-from <director instance>`, naming a role the workspace's
`[authority.roles]` grants at least one authority, because the skill's own
lane dispatch gives a lane coordinator no grant (the PLAN's Proposed
Follow-up). If that setup can't be made on this host when the step runs, the
step says so, both lanes are dispatched the same way from a session with no
dispatch of its own (so `parent_is_mine` is false), the third-session read
and the cap request still run, and only the director-side criteria stay open.
The lane is then read twice over: from the director, whose answer
shows `parent_is_mine` true, and from a session that is neither the lane nor
its dispatcher, which asks with `--point merge-pr` so the `merge-pr` settler
is measured. Both read the lane from niwa's records alone, and both see a
grant changed between two asks, the change removing an authority from the
lane's role, since niwa keeps a lane's grant inside its dispatcher's and a
widening past that shows no change. A cross-lane cap request closes the run:
both lanes run `/shirabe:coordinate` with their own records, and the first
lane, from its `wait` as the skill directs, tries to move the second lane's
cap. The write isn't made; the first lane reads the second with
`lane-read.sh`, sends the request to the address the line's `session` and
`instance` give, the second lane receives it,
and the second lane's record is unchanged until it decides, by its own
rules, whether to set its own cap. The record names the niwa version the run used; if it isn't 0.40.0,
R14's claim about 0.40.0 stays unmeasured.
This is where the third-session read of a lane holding grants is measured. The record lands in "What a third session can read today" above,
as commands with host paths replaced and the result lines read, never full
niwa answers.

Phases 1 to 5 are the PLAN's Steps 1 to 5, each in its own pull request, in
the same order and with the same dependencies as before the amendment.
Phases 1 and 3 stand as they were.

### The template's compat number

Phases 1, 2 and 3 change scripts in the coordinate template's gate-script
closure (`dispatch-common.sh`, `state-write-core.sh`, `state-stored-set.sh`
and, when this feature moves it, `posture-read.sh`), so each records the new
`gate_scripts` digest in `skills/coordinate/koto-templates/coordinate.compat.json`
(`scripts/check-template-compat.sh --print` gives it) and the
`check-template-compat` job passes. Compat stays at 2. A run compiled before
this feature has no `opened_by` and is read by the existing branches, so it
keeps resuming, carrying and being taken over as it does now. Raising compat
would make every such run template-incompatible and force a carry, for a
change that adds one meta field and one way a cap write isn't made.

### Dependencies on the workspace authority work

None of these is assumed shipped.

- **niwa's delivery facts.** The cap request is addressed through the
  delivery facts niwa's authority-read design (tsukumogami/niwa
  `docs/designs/DESIGN-authority-read-settlers.md`) adds in its Decision 3,
  and follows its Decision 4: no cap-change authority, by design, and a
  cross-lane cap change sent as a request to the owning coordinator. Nothing
  here waits on a future authority. The lane read's line already carries the
  lane's `session` and `instance`, the same values niwa's `session` member
  names. It doesn't carry the lane's `session_name` or
  `accepts_session_messages`; carrying them is a change to Decision 3 left
  open (Decision 2, "Open point"). The reader's accepted grant vocabulary
  stays `merge-pr`, `close-issue` and `cut-release`, and the cap check
  compares no grant value.
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
and two `lineage show` calls on the stand-in's log. With `--session`, the
narrowing read adds `pause-read.sh`'s condition reads (Decision 3), one per
condition a pause row on the lane's unit names; they are bounded by
board-lib's deadline, not by `NIWA_LOOKUP_SECONDS`, and the lane read's
bound criterion covers only its niwa calls.

A cap write makes no niwa call in the script, own or cross-lane. Addressing
a cross-lane request costs the skill one lane read of the target lane: one
`niwa list`, one `niwa lineage show` and one `niwa authority check`, none of
them about the mover.

## Security Considerations

The lane read is read-only and asks niwa about sessions in the same workspace;
it reads no file the lane wrote and sends the lane nothing. With `--session`
it also reads, through `pause-read.sh`, the GitHub state of the conditions the
director's own pause rows name (a pull request's state, a tag's ref), the
same read-only calls pick already makes for those rows. The lane's
grant, level and dispatch ids are workspace-internal and go no further than the
director's own report.

The cap check closes a gap rather than opening one: today any session can
rewrite a sibling lane's cap. Its failure direction is that nothing is
written across lanes: the mover never writes another lane's record, under
any answer, and a meta it can't read, a missing caller id or unfound caller
name, and a lane read that can't give an address all keep the target cap as
it is. The request
carries no authority. It asks; the owning lane decides by its own rules and,
if it agrees, writes its own cap through its own-write path, so a forged or
repeated request can't change a cap the owner didn't choose to change. Each
line is fixed and carries only the case word and the `--session` and cap
value it was given, never text from niwa. The address the skill builds uses
only the lane read's checked `session` and `instance`. A wrong topic, or a
forged fact in niwa's files, can misdirect a request, not grant anything,
as niwa's design says of its delivery facts, and the request names the
target session, so a recipient that doesn't own it can see that. A
caller with no valid session id is refused `no-session`, so unsetting or
mangling the session variable can't turn a sibling's record into the
caller's own.

The lane read checks what it takes from niwa's lookup before using it: the
instance path must be absolute and hold `.niwa/instance.json`, the session id
must be a lowercase UUID, and a topic matching more than one instance is
answered can't tell rather than picked. It reads no other file in the lane's
instance and calls no messaging command. Neither does the cap check: the
session reads the lane and sends the request, as a message, after the
script exits.

A forged record can't widen anything. The lane answer comes from niwa, not the
director's record, and record rows only appear as `narrowed_by`. The cap
check's ownership test reads `record/meta`, which a session could edit to name
itself as driver or opener; doing so lets it write that cap as its own. That is the same
exposure the takeover rule has today, and this design doesn't widen it.

## Consequences

### Positive

- A director answers from niwa's current record of a lane and sees a changed
  grant on its next ask.
- No session writes a sibling lane's cap through the skill. A move it wants
  reaches the lane that owns the cap as a request, addressed from niwa's
  facts, and that lane decides it.
- `niwa authority check` still runs from one file, shared with the
  settled-steps work.

### Negative

- A resume's `opened_by` write adds a writer to `record/meta` that can run
  while the earlier session is still writing the record. Left alone, it
  could roll back that session's meta fields and hand out a Standing id
  twice, so Step 1 must show it never does; the mechanism is Step 1's to
  choose.
- A cross-lane cap change takes a round trip: the mover asks, and the cap
  changes only when the owning lane agrees and writes it. A lane that doesn't
  answer leaves the cap as it is, and a lane the lane read gives no address
  for sends the move through an escalation instead.
- Addressing a request costs the session a lane read of the target (one
  `niwa list`, one `niwa lineage show` and one authority read), and it has
  to know the target lane's dispatch topic.
- Until Decision 3 carries the lane's `session_name` and
  `accepts_session_messages`, a request is addressed by session id, and one
  sent to a lane that takes no session messages goes unanswered rather than
  being caught as `no-delivery`.
- A lane question costs two niwa calls per lane plus one list.
- The ownership test trusts `record/meta`'s driver and `opened_by`, which a
  session can edit.
- A run from before this change has no `opened_by`. Unless its coordinator
  row names the writer's found session name (a coordinator in the foreground
  has none), it can't change its cap until a start from a session with an id
  resumes it, which records that session as its opener, or a takeover records
  a driver; its cap stays as it is until then.
- A start with no valid session id records no opener, so a run opened that
  way can't write its first cap and stays at reconcile with its `no-cap` gap
  open. Scripts and tests that open a run must give it an id.
- A run resumed by a second session that the takeover reads as unknown
  records that session as its latest opener. The first session, if it's
  still running, can no longer prove the record is its own by its opener.
  Unless the coordinator row names its found session name, its cap writes
  on that run are treated as cross-lane and not made, and, being on its own
  record, the line is reported with no request sent and no entry raised.

### Mitigations

- The request names the target session and the cap value and goes to the
  address niwa's facts give for the lane that can change that cap; when the
  lane read gives no address, the session says why and the move is
  escalated.
- A request that's still unanswered isn't sent again, so a mover can't
  flood the owning lane.
- The calls are bounded and made only when a question is asked.
- A pre-change run's limit ends at its next start from a session with an id,
  or its next takeover, and every run opened after this change names its
  opener from the start.
- The takeover's contract is untouched: no restart, carry or import that
  resumes today becomes a takeover or a refusal.
- A stronger identity check than the record's driver belongs in niwa, which
  already binds each dispatched session to its instance; the cap check can
  move to that once niwa answers whose lane a record is.
