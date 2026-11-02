---
schema: prd/v1
status: Accepted
problem: |
  A director that dispatched a lane learns what the lane may do only by asking
  it or by rereading the brief it wrote. Neither is the answer niwa resolves
  for that lane, and both go stale the first time the workspace changes a
  grant. Separately, any session running the coordinate skill can move another
  lane's active-worker cap, and the skill checks no authority before it does.
goals: |
  A director reads a lane's grants and level from niwa's authority read,
  without involving the lane, and sees the answer change when the workspace
  changes the grant. A session that niwa doesn't grant the cap-change
  authority, trying to move another lane's cap through the skill, is refused
  by that authority's name, and the skill defines no authority of its own.
absorbed:
  - docs/briefs/BRIEF-director-reads-lane-authority.md
---

# PRD: Director Reads Lane Authority

## Status

Accepted

Absorbed [BRIEF-director-reads-lane-authority](docs/briefs/BRIEF-director-reads-lane-authority.md); carried in Absorbed Brief.

## Absorbed Brief

The brief framed why this feature exists: what a session is expected to do
lives in the skill and its role, and what it is allowed to do is configured
per workspace and host and read from niwa. A director that judges a lane's
allowances from its own brief, or from what the lane says, turns an
allowance into an expectation, and the two drift apart the first time the
workspace narrows a role or lowers the grant ceiling. The same split rules
out the obvious fix for the lane cap: a rule in the skill about who may move
another lane's cap would be a second source of truth niwa can't see. That
framing is this document's Problem Statement.

The outcome it asked for is a director that answers from niwa's record of a
lane, without involving the lane, and sees the answer change when the
workspace changes the grant, and a cross-lane cap move refused by the name
of the authority niwa grants, with no authority defined in the skill. Those
are this document's Goals. Its five journeys (a director checking what a lane
may do, the workspace narrowing a grant, a lane trying to move a sibling's
cap, an authority that can't be read, and a maintainer looking for the cap
rule) survive as the User Stories, and its boundary survives as the
Requirements and Out of Scope. The skill passages it pointed to are the lane
cap and the start read of the session's own authority in the coordinate
skill's Bounds and Authority section.

## Problem Statement

Coordinators come in two roles. A manager runs one lane: it dispatches
workers, verifies what they push and lands it. A director sits over managers
and dispatches them. "Coordinator" means either.

A director that has dispatched a manager can say what that manager may do in
two ways today. It can ask the manager, which costs a message and returns a
claim the manager makes about itself. Or it can reread the brief it wrote,
which says what the director meant to grant, not what the session holds.
Neither is what niwa enforces. niwa resolves a dispatched session's grant
when asked: each role grants what the workspace declares for it at that
moment, kept inside the current grant ceiling and inside what the session's
dispatcher holds now. A workspace that narrows a role or lowers the ceiling
changes what every lane under it may do, and nothing the director remembers
or the lane reports moves with it.

What a session is expected to do is written in the skill and in the role it
plays. What it's allowed to do is configured per workspace and host, and niwa
is where that configuration is read. A director that reasons about a lane's
allowances from its own text turns an allowance into an expectation, and the
two drift apart the first time the workspace changes.

The second half is the lane's cap. The coordinate skill limits each lane's
active workers (`--cap`, five by default, kept in the coordinator's record as
the cap in force). Any session running the skill can write that number for a
lane, its own or a sibling's. Moving another lane's cap changes how much work
that lane carries, which is an authority question, and the skill asks no one.
A rule in the skill about who may move a cap would give the skill an
authority model of its own, a second source of truth that niwa can't see and
the workspace can't change. Allowances belong to the workspace.

## Goals

A director asked what a lane it dispatched may do answers from niwa's
authority read for that lane: its grants, its level and where the level came
from, read without involving the lane. When the workspace changes what the
lane's role grants, the director's next answer shows the change, because it
reads again rather than remembering.

A session that tries to move another lane's cap through the skill is checked
against niwa. If niwa doesn't grant it the cap-change authority, the skill
refuses, names that authority, and changes nothing. The skill carries no
definition of that authority, no rule for who gets it and no level logic: it
names the authority as something niwa grants and acts on niwa's answer.

## User Stories

- As a director with three managers running, I want to read whether one of
  them may merge before I hand it a unit that ends in a merge, from niwa and
  without messaging it, so that the answer is what the workspace allows rather
  than what the manager says about itself.
- As a director, I want the answer to say which dispatch launched the lane and
  which dispatch launched that one, so that I can see the lane is one I
  dispatched.
- As a director whose workspace owner has just removed an authority from the
  role a running manager was dispatched with, I want my next answer to drop
  that authority even though the manager's brief still names the role, so
  that I don't act on a grant the manager no longer holds.
- As a manager short of work, when I try to raise a sibling manager's worker
  cap through the skill without the cap-change authority, I want to be
  refused before anything changes, with the missing authority named, so that
  I know which grant is missing and the sibling's cap stays where it was.
- As a director asking about a session niwa reports as not dispatched, whose
  record is unusable, or whose read fails or times out, I want to be told
  that what the session may do can't be told and why, so that I never fall
  back to the brief or the lane's own claim.
- As a maintainer reading the coordinate skill to find out who may move a
  cap, I want the skill to send me to niwa, so that there is one place the
  rule lives and the workspace can change it.

## Requirements

### Functional

**R1. The director's answer is niwa's read of the lane.** What a director
reports a lane may do comes from one `niwa authority check -C <lane
instance> --session <lane session id> --json` read, with `--point <p>` added
for each decision point the question names. The lane's report, the brief the
director wrote, the role the dispatch named and any earlier answer are never
a source for it.

**R2. The lane is found without the lane.** The director learns the lane's
instance and session id from niwa's own records of the dispatch, never by
messaging the lane or reading anything the lane wrote.

**R3. What the answer says.** For a lane niwa reports bound, the director's
answer gives the lane's grant (its authorities, in niwa's order, which may be
none), its level and the level's source, the dispatch that launched it, and
that dispatch's parent. It says whether that parent is the director's own
dispatch. For each point asked, it gives who settles the point as niwa
answers it.

**R4. Every ask reads again.** Each question about a lane makes a new read at
the time it's asked. No answer is kept and reused for a later question, so a
change the workspace makes between two asks shows in the second answer.

**R5. Can't tell is an answer.** When the read doesn't print a document of
niwa's authority-check schema with state `bound`, the director says it can't
tell what the lane may do, and why: niwa's state and reason (`not-dispatched`
with its reason, `record-unusable`), a read that failed or ran past its bound,
no niwa, or an answer whose shape or values it doesn't accept. An accepted
answer exits 0, declares the schema `niwa.authority.check/v1`, and holds only
grant authorities, levels and settlers from niwa's own vocabularies, the same
acceptance the skill's existing authority reads apply. It assumes no grant
and falls back to nothing.

**R6. A record row restricts, never widens.** A row in the director's own
record (a pause, a person's word about that lane) may narrow what the
director lets the lane do or tells it to do. No row adds an authority to
what niwa's answer grants, and the director never reports a lane may do more
than niwa's answer says.

**R7. A cross-lane cap move needs niwa's cap-change authority.** When a
session, through the skill, tries to change the cap in force of a lane whose
record it isn't driving, the skill reads the moving session's own authority
from niwa first. The move goes ahead only when that answer is `bound` and its
grant holds the cap-change authority. Otherwise the skill refuses, names the
cap-change authority as one niwa grants and the session doesn't hold, and
leaves the target lane's cap and record unchanged. A record is the moving
session's own when its recorded driver is the moving session, or, with no
driver recorded, when its coordinator is the moving session. Every other case
counts as cross-lane, including a writer with no session id, which is refused
without a read under the reason `no-session`.

A refused move isn't dropped. The moving session raises it as a decision
entry in its own record, with the refused move and the refusal line in the
entry's question, and escalates that entry under the skill's existing
decision rules with a recommendation. While that entry is open, a second
refusal of the same move (the same target session and the same cap value)
reuses it rather than raising another. The session doesn't retry the write or
reach the same cap another way, and no answer to the entry authorizes the
write: the cross-lane write stays refused until niwa grants the authority.

**R8. No cap-change authority exists yet, so every cross-lane move is
refused.** niwa grants no cap-change authority today. Until it does, every
cross-lane cap move through the skill is refused under R7 with the same
refusal: the cap-change authority, named as one niwa grants, isn't held.

**R9. A move whose check can't be read is refused.** A cross-lane cap move
whose authority read fails, times out, finds no niwa, or answers anything but
`bound` with an accepted shape is refused the same way, with the reason.

**R10. A lane's own cap is unchanged.** A coordinator writing the cap of the
record it drives, at its first start or when a person's word sets it, behaves
as it does today, with no authority read added.

**R11. The skill defines no authority.** The skill names the cap-change
authority only as something niwa grants. It holds no definition of it, no
rule for who gets it, no level rule and no grant table, and no text that
reads as the skill granting or withholding it on its own terms.

**R12. One reader.** The lane read and the cap-move check go through the same
reader the coordinator already uses to read its own authority at start, for
the standing-rule grant fields, and for who settles each finishing step, so
`niwa authority check` is still run from one place in the skill.

### Non-functional

**R13. Bounded.** Each read is bounded the way the skill's existing authority
reads are (three seconds by default). One question costs at most one read
per lane asked about, and a cross-lane cap move costs at most one read of the
moving session (none when the writer has no session id).

**R14. Works on today's niwa.** The lane read works on niwa 0.40.0 from a
session that is neither the lane nor its dispatcher, using only what that
version answers. Anything the feature needs beyond that is named as a
dependency, never assumed.

## Acceptance Criteria

- [ ] From a director and a lane it dispatched, a reviewer asks the director
  what the lane may do and sees the lane's grant, level and level source
  exactly as `niwa authority check -C <lane instance> --session <lane
  session> --json` prints them at that moment, with the lane's dispatch and
  its parent, and the parent shown as the director's own dispatch. The lane
  receives no message during the ask.
- [ ] The reviewer changes what the lane's role grants in the workspace
  configuration, asks again, and sees the new grant without restarting the
  director or the lane.
- [ ] Asked about a point (for example the merge point), the answer gives who
  settles it as niwa answers it.
- [ ] Asked about a session in another instance, a session started by hand,
  a lane niwa answers `record-unusable` for, or a lane whose read is made to
  fail, time out or print a document of another schema, the director answers that it can't tell, with niwa's state
  and reason or the read failure named, and reports no grant.
- [ ] With a pause on a lane in the director's record, the director's answer
  for that lane still shows niwa's grant and says the pause narrows it; with
  a row whose words name an authority niwa's answer doesn't hold, the answer
  doesn't include that authority.
- [ ] From a lane without the cap-change authority, a reviewer has it try to
  move a sibling's cap through the skill and sees a refusal that names the
  cap-change authority as one niwa grants and the session lacks; the
  sibling's cap in force and record entries are unchanged afterward.
- [ ] After that refusal, the moving session's record holds one decision entry
  whose question names the move and carries the refusal line, escalated once
  with a recommendation; a second refusal of the same move (same target
  session, same cap value) while that entry is open adds no second entry; an
  answer to the entry writes nothing to the sibling's record, and the
  sibling's cap is still unchanged.
- [ ] The same cross-lane move, with the moving session's read made to fail,
  time out or answer `not-dispatched`, is refused with the reason, and the
  sibling's cap is unchanged.
- [ ] A coordinator setting its own cap at first start and on a person's word
  succeeds as before, and makes no authority read for it.
- [ ] A cap write against a record whose driver is a different session from
  the writer is treated as cross-lane and refused; a write whose writer can't
  be told (no session id for the writer, with or without a driver recorded)
  is refused the same way, with the reason `no-session` and no read.
- [ ] A reviewer reads the skill after the change and finds the cap-change
  authority named only as something niwa grants: no definition, no rule for
  who holds it, no level rule and no grant table.
- [ ] A search for `niwa authority check` under `skills/coordinate/` finds it
  in one reader, which the lane read, the cap-move check, the start read, the
  standing-rule read and the finishing-step read all call.
- [ ] A lane read whose niwa never answers returns can't tell within the
  bound (three seconds by default) plus a second's slack.
- [ ] With no niwa on the path, a lane read answers can't tell naming the
  missing niwa, and a cross-lane cap move is refused naming it.
- [ ] One question about two lanes makes exactly two niwa calls, counted on a
  stand-in niwa's call log, and none of them is about the director's own
  session unless the question is.
- [ ] On niwa 0.40.0, run from a session that is neither the lane nor its
  dispatcher, the lane read returns the lane's bound answer, and the lane's
  instance and session id were found from niwa's dispatch records alone
  (no file the lane wrote was read and no message was sent).

## Out of Scope

- Defining the cap-change authority, levels, grants or ceilings, or how niwa
  computes any of them. The workspace authority work owns those; this
  feature reads niwa's answer.
- A session moving its own cap. The question here is one lane acting on
  another.
- Changing a grant from the skill. The workspace changes grants; the director
  only observes the change.
- A lane's answer read from outside the workspace or from another host.
- The gap where a session without a grant can launch a child that holds one,
  with a record that looks like an operator launched it
  (tsukumogami/niwa#422). That's niwa's fix.
- The finishing-step settler reads (merge, close, release), which have their
  own scoping.
- A fleet-wide limit on active workers across lanes, which is host practice
  and no concept in the skill.

## Known Limitations

- **Every cross-lane cap move is refused until niwa grants the authority.**
  That is the intended state, not a gap in this feature: no session can move
  a sibling's cap through the skill until the workspace authority work, whose
  design is in progress, gives the authority a name and a grant.
- **The parent the answer names is only as sound as niwa's dispatch record.**
  Until tsukumogami/niwa#422 is fixed, a child launched by a session without
  a grant can carry a record that looks operator-launched, so "the parent is
  my dispatch" rests on that fix.
- **The per-point settler is only as complete as the authority work behind
  it.** niwa answers who settles a point today, but tying that answer to the
  authority level is work that hasn't started; the director reports what
  niwa answers and claims nothing beyond it.
- **A third session's read of a lane that holds grants is unmeasured.** The
  read measured on this host was of a lane whose grant was empty. Whether a
  session that is neither the lane nor its dispatcher reads a lane holding
  grants, and sees a changed grant, is what the whole-feature check measures;
  nothing here claims it before then.

## Decisions and Trade-offs

- **The cap is the lane's active-worker limit.** "Move another lane's cap"
  means changing another lane's `--cap`, the cap in force in its record.
  The alternative reading, a limit across all lanes on a host, isn't a skill
  concept and is out of scope.
- **The authority is named in words, not spelled.** niwa has no cap-change
  authority yet, so the requirements name it as an authority niwa will grant
  and assume no token, no level and no shape for it. The alternative, picking
  a name now, would put an authority definition in the skill, which R11
  forbids.
- **Refuse, don't ask.** Until niwa grants the authority, a cross-lane cap
  move is refused and reported, rather than routed to a person for approval.
  Routing it would make a person the source of an allowance the workspace
  hasn't declared. R7's decision entry doesn't reopen that: the refusal
  stands, and an answer to the entry, from a person or anyone else, can't
  authorize the cross-lane write. What the entry carries upward is the need
  behind the move. A person who wants the target's cap changed has the
  target lane set its own cap on their word, which R10 already allows.
- **Read fresh, never cache.** Caching an answer across asks would save a
  three-second read and would hide exactly the change R4 exists to show.
- **Own cap stays as it is.** Adding a read to a lane's own cap write would
  change a path that works and that the brief puts out of scope.
