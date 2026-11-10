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
  changes the grant. A session trying to move another lane's cap through
  the skill never writes it: the move becomes a request to the lane that owns
  the cap, routed through the facts niwa already gives, and that lane decides
  it. The skill defines no authority of its own.
absorbed:
  - docs/briefs/BRIEF-director-reads-lane-authority.md
---

# PRD: Director Reads Lane Authority

## Status

Accepted

Amended: a move of another lane's worker cap is no longer refused by the name
of a cap-change authority niwa might grant later. niwa's design for authority
reads (tsukumogami/niwa `docs/designs/DESIGN-authority-read-settlers.md`,
Decision 4) defines no such authority, as a deliberate non-goal, and routes a
cross-lane cap change as a request to the coordinator that owns the cap,
through the delivery facts its Decision 3 adds. R7 to R11, R13 and the
criteria, limitations and trade-offs that rested on that authority now say a
cross-lane move is a request the owning lane decides by its own rules. The
lane read (R1 to R6), the ownership rule in R10 and R12's one reader stand.
The cap check makes no read; the skill addresses the request with one lane
read of the target lane. One point is open: the lane read carries the lane's
session id and instance but not its `session_name` or whether it takes
session messages, so a request is addressed by session id and the
no-delivery case waits on a change to the lane read's answer that this
amendment doesn't make.

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
workspace changes the grant, and a cross-lane cap move that doesn't go ahead
on the skill's own say, with no authority defined in the skill. The brief put
that as a refusal by the name of an authority niwa would grant; niwa has
since settled that it grants none, so this document carries the outcome as a
request to the cap's owner. Those are this document's Goals. Its five journeys (a director checking what a lane
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

A session that tries to move another lane's cap through the skill never
writes it. The skill changes nothing in that lane's record and turns the move
into a request to the lane that owns the cap, addressed through the facts
niwa gives for that lane, and the owning lane decides it by its own rules.
niwa defines no authority for moving another lane's cap, by design, and the
skill names none: it carries no definition, no rule for who may move a cap
and no level logic.

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
  cap through the skill, I want my move turned into a request to that sibling
  before anything changes, with the sibling's address read from niwa, so that
  the sibling, whose cap it is, decides, and its cap stays where it was until
  it does.
- As a director asking about a session niwa reports as not dispatched, whose
  record is unusable, or whose read fails or times out, I want to be told
  that what the session may do can't be told and why, so that I never fall
  back to the brief or the lane's own claim.
- As a maintainer reading the coordinate skill to find out who may move a
  cap, I want the skill to say a lane's cap is that lane's to set and another
  lane's move is a request to it, as niwa's design has it, so that the skill
  holds no rule of its own about who may move a cap.

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

**R7. A cross-lane cap move is a request to the cap's owner.** When a
session, through the skill, tries to change the cap in force of a lane whose
record isn't its own, the skill never writes that record. With no read, it
gives the session one fixed request line naming the target session and the
cap value asked for, saying the cap is another lane's and the move goes as a
request to that lane's owner. The session then reads the target lane from
niwa, the way R1 reads a lane, addresses the request through the delivery
facts niwa's answer carries for that lane (its session name when present,
else its session id, with its instance), and sends the line as a message to
that address, with the need behind the move, and reports that it did; it
raises no decision entry for a request that went out. The owning lane
decides the request by its own rules, and if it agrees, it sets its own cap
under R10. No reply authorizes the moving session to write the other lane's
record, and the session doesn't retry the write or reach the same cap another
way. While a request for the same move (the same target session and the same
cap value) is unanswered, a second one isn't sent.

A record is the moving session's own when its recorded driver is the moving
session, or, with no driver recorded, when the moving session is the run's
latest opener (the session that opened it or last resumed it) or is its
coordinator. Every other case counts as cross-lane, including a writer with
no session id, which is refused without a read under the reason
`no-session`. A record with no driver whose latest opener is another session
is cross-lane and becomes a request.

**R8. No cap-change authority exists, by niwa's design, so a cross-lane move
is a request.** niwa defines no authority over another lane's cap and says so
as a deliberate non-goal (tsukumogami/niwa
`docs/designs/DESIGN-authority-read-settlers.md`, Decision 4): the cap is the
owning coordinator's setting, which niwa neither stores nor gates. There's no
grant for the skill to check, so no cross-lane move goes ahead on the moving
session's authority. It goes, as a request, to the one session whose setting
it is, which is how niwa routes a cross-lane cap change too, through the
delivery facts its Decision 3 adds.

**R9. A move whose request can't be addressed isn't written, and says why.**
When the session's read of the target lane finds no niwa, fails, times out
or answers anything but `bound` with an accepted shape (niwa's state for the
lane, or the reader's skip, timeout, failure or refusal), or niwa's facts say
the lane takes no session messages, nothing is written or sent and the
session names the reason. That move isn't dropped. The moving session raises it as a decision entry in its own
record, with the move and the line in the entry's question, and escalates
that entry under the skill's existing decision rules with a recommendation,
one option being the target lane setting its own cap on a person's word.
While that entry is open, a second stop of the same move raises nothing and
leaves that entry as the one record of the move. No answer to the entry
authorizes the cross-lane write.

**R10. A lane's own cap is unchanged.** A coordinator writing the cap of the
record it drives, at its first start or when a person's word sets it, behaves
as it does today, with no authority read added. A run records its latest
opener, the session that opened it or last resumed it, from its first start,
so a coordinator's own record shows as its own from the start. Recording that
changes nothing about how a later start resumes, carries or takes the run
over. The exceptions are a writer that can't show the record is its own: one
with no session id, or, on a record with no driver and no opener recorded,
one that isn't the coordinator its record names (a run from before this
feature, say, whose coordinator has no findable session name); and a session
whose run another session has resumed since, which is no longer the latest
opener and, unless its record's coordinator row names it, writes as another
lane under R7, except that, its record being its own, its line is reported
with no request sent and no decision entry raised. The first kind's cap write
isn't made (`no-session` for a missing id, `unproven-owner` for a record it
can't show is its own, with the cause), its own record included, with no
read, and a stopped write to its own record sends no request and raises no
decision entry.

**R11. The skill names no cap-change authority.** It holds no definition of
one, no rule for who may move another lane's cap, no level rule and no grant
table, and no text that reads as the skill allowing or refusing a cap move on
its own terms. It says a lane's cap is that lane's to set and another lane's
move is a request to it.

**R12. One reader.** The lane read, including the one the skill makes to
address a cap request, goes through the reader the settled-steps work adds, the same one the coordinator
is to use to read its own authority at start, for the standing-rule grant
fields, and for who settles each finishing step, so
`niwa authority check` is still run from one script in the skill.

### Non-functional

**R13. Bounded.** Each read is bounded the way the skill's existing authority
reads are (three seconds by default). One question costs at most one read
per lane asked about. The cap check makes no read for any cap write, and
addressing a cross-lane request costs at most one read, of the target lane
and never of the moving session.

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
  doesn't include that authority; and when the director's record can't be
  read for that narrowing, the answer still shows niwa's grant and says the
  narrowing couldn't be read, never that nothing narrows it.
- [ ] A reviewer has a lane try to move a sibling's cap through the skill
  and sees the write not made, with no read, and one request line naming the
  sibling's session and the cap value; the moving session reads the sibling
  with the lane read and sends that line to the address niwa's facts give
  for it, as a message with the need behind the move, and raises no decision
  entry; the sibling's cap in force and record entries are unchanged
  afterward; and no authority read of the moving session is made.
- [ ] A change to another lane's cap is a request routed through the
  authority facts niwa already grants: the request's address comes from
  niwa's facts for the target lane and from nothing the moving session or the
  target's record says, and no line the skill prints for the move names a
  cap-change authority.
- [ ] When the sibling agrees and sets its own cap through its own-write path,
  the write succeeds with no authority read; a reply from the sibling, of any
  kind, never leads the moving session to write the sibling's record; and a
  second attempt at the same move (same target session, same cap value)
  while the first request is unanswered sends no second request.
- [ ] The same cross-lane move, with the target lane's read made to fail,
  time out or answer `not-dispatched`, or with no niwa found, sends nothing,
  writes nothing, and the session reports the reason; the moving session's record then holds one decision entry whose
  question names the move and carries that line, escalated once with a
  recommendation; a second stop of the same move while that entry is open
  adds no second entry; an answer to the entry writes nothing to the
  sibling's record, and the sibling's cap is still unchanged.
- [ ] A coordinator with a session id setting its own cap at first start and
  on a person's word, on a run whose driver is that id, that it opened or
  last resumed under that id with no other session resuming it since, or
  whose coordinator row names its found session name, succeeds as before,
  and makes no authority read for it.
- [ ] A cap write against a record with no driver whose latest opener is
  another session, and whose coordinator row doesn't name the writer, is
  treated as cross-lane: it makes no read and becomes a request, never
  `unproven-owner`.
- [ ] A run opened under one session id and started again under another
  resumes, carries or is taken over exactly as it did before this feature.
- [ ] A cap write against a record whose driver is a different session from
  the writer is treated as cross-lane and becomes a request; a write whose writer can't
  be told (no session id for the writer, with or without a driver recorded)
  is refused with the reason `no-session`, a line saying the writer has no
  session id to show whose record it is, and no read; and a writer with an
  id that can't show a record with no driver and no opener recorded is its
  own is refused with the
  reason `unproven-owner`, a line naming which of the closed set of causes
  fired, and no read.
- [ ] A reviewer reads the skill after the change and finds no cap-change
  authority named: no definition, no rule for who may move another lane's
  cap, no level rule and no grant table, and text saying a lane's cap is
  that lane's to set and another lane's move is a request to it.
- [ ] A search of the executable lines of `skills/coordinate/scripts/*.sh`,
  test files (`*_test.sh`) and comment lines excluded, finds a line that runs
  niwa's `authority check` as a command only in the one reader, which the
  lane read (including the skill's read that addresses a cap request), the start read, the standing-rule read and,
  once it exists, the finishing-step read all call. A message string naming
  the command doesn't count, nor does prose in `SKILL.md`, the references and
  comments. This feature's skill-text step closes the criterion
  for the callers that exist; the finishing-step half closes with the
  settled-steps work.
- [ ] A lane read whose niwa never answers returns can't tell within the
  bound (three seconds by default) plus a second's slack.
- [ ] With no niwa found (none on the path and no executable `NIWA_BIN`), a
  lane read answers can't tell naming the missing niwa with `no-niwa`, and a
  cross-lane cap move's request goes unsent, the session naming that reason.
- [ ] One question about two lanes makes exactly two `niwa authority check`
  calls, counted on a
  stand-in niwa's call log, and none of them is about the director's own
  session unless the question is.
- [ ] On niwa 0.40.0, run from a session that is neither the lane nor its
  dispatcher, the lane read returns the lane's bound answer, with the lane's
  instance and session id found from `niwa list` and `niwa lineage show`
  alone.
- [ ] The lane read reads nothing the lane wrote and sends it nothing: in a
  test whose lane instance holds `.niwa/instance.json` beside a file the lane
  wrote, made unreadable, the answer is still exact and the read succeeds;
  and a stand-in niwa's call log holds only `list`, `lineage show` and
  `authority check` calls, with no messaging command called.

## Out of Scope

- Defining any authority, levels, grants or ceilings, or how niwa computes
  any of them. niwa owns those, and defines no cap-change authority by
  design; this feature reads niwa's answer.
- How the owning lane decides a cap request. It decides by its own rules,
  which this feature doesn't set.
- A session moving its own cap, except as R10 notes. The question here is
  one lane acting on another.
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

- **A cross-lane cap change waits on the owning lane.** The mover can't
  change a sibling's cap, only ask, and the cap changes only when the sibling
  agrees and writes it. A sibling that doesn't answer leaves its cap where it
  is, and a sibling the lane read gives no address for gets the move as an
  escalation rather than a request.
- **A request is addressed by session id, and a lane that takes no session
  messages isn't caught.** The lane read carries the lane's session id and
  instance but not its session name or whether it takes session messages.
  Carrying them is a change to the lane read's answer that this amendment
  leaves open; until then a request to a lane that takes no messages goes
  unanswered.
- **Whether a request is still unanswered rests on the session's own
  report.** The record keeps no row for a request that went out, so the rule
  against sending the same request twice is the skill's instruction, checked
  by a walkthrough, not something a script enforces.
- **A coordinator that can't name itself can't set its own cap.** With no
  session id it can't show that a record is its own, so its cap write is
  refused `no-session` (R10), and a run it opens records no opener and can't
  write its first cap. Scripts and tests that open a run have to give it an
  id.
- **A run from before this feature may not be able to change its cap.** Such
  a run records no driver and no opener. Unless its coordinator row names the
  writer's found session name (a coordinator in the foreground has none, and
  a row holding a dispatch topic or another address doesn't match), its cap
  write is refused `unproven-owner` until a start from a session with an id
  resumes it, which records that session as its opener, or a takeover
  records a driver; its cap stays as it is until then.
- **A session whose run another session has resumed since loses its own
  cap.** The record names its latest opener, so once a second session
  resumes the run, the first one's cap writes on it are cross-lane unless the
  coordinator row names the first one's session name. They aren't made, and
  since the record is its own, the line is reported with no request sent.
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
- **No authority is named.** niwa defines no cap-change authority, by
  design, so the requirements name none and assume no token, level or shape
  for one. Picking a name in the skill would put an authority definition
  there, which R11 forbids. An earlier version of this document named it as
  an authority niwa would grant; niwa's Decision 4 has since ruled that out.
- **Ask the owner; don't refuse, and don't decide for it.** A cross-lane cap
  move is a request to the lane that owns the cap. The request carries no
  authority: the owning lane decides it by its own rules and writes its own
  cap if it agrees, so neither the mover nor a person becomes the source of
  an allowance the workspace hasn't declared. Refusing every move with no
  route, which niwa's design calls correct, was set aside because it leaves
  the move nowhere to go but an escalation that can't change the cap either.
  R9's decision entry, for a move that can't be addressed, keeps the same
  line: an answer to the entry, from a person or anyone else, can't authorize
  the cross-lane write. What the entry carries upward is the need behind the
  move, and a person who wants the target's cap changed has the target lane
  set its own cap on their word, which R10 already allows.
- **Read fresh, never cache.** Caching an answer across asks would save a
  three-second read and would hide exactly the change R4 exists to show.
- **Own cap stays as it is.** Adding a read to a lane's own cap write would
  change a path that works and that the brief puts out of scope.
