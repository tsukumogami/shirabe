---
schema: design/v1
status: Planned
problem: |
  A director is the reviewer of every manager it dispatched and is expected
  to read their finished pull requests for alignment, but the coordinate
  skill gives it nothing to act with. Its record keeps no trace of a
  judgment, a hold in its own record stops nothing in the manager's land
  step, a hold row can't name a head, a reason or a release, a merge that
  skipped the director leaves no mark, and owner questions and relays have
  no single route.
decision: |
  One new entry kind, `alignment`, records each call at one head in a fixed
  line grammar that state-entry.sh checks at write. A divergent pull request
  gets a `lifted`-until hold named after the head it was placed on, added to
  the director's record and copied by message into the manager's, so every
  land check that would merge it reads it from its own record; the director
  lifts only through a guarded lift that needs a new head and a later `fits`
  call. A read-only script lists the calls, merges and recommendations and
  feeds the start's unreviewed list, and owner questions and relay checks run
  on the record's existing Decisions entries, Work rows and Standing rows.
rationale: |
  Holds, entries, Decisions and Standing rows already carry most of what the
  requirements need, so the design adds one entry kind and leaves every
  section and grammar as it is. Copying the hold keeps every merge path on
  its own record, so no session's lands depend on reading another session's
  store, which can sit on another host; the cost is a delivery window that
  the record shows rather than prevents. Line grammar follows the milestone
  verdict entry, so other tools parse it the same way.
upstream: docs/prds/PRD-director-alignment-review.md
decision_provenance: inline-resolved
---

# DESIGN: Director Alignment Review

## Status

Planned

## Context and Problem Statement

A director is a coordinate session that runs over managers, one lane each,
and is the reviewer of every manager it dispatched. The named-roles work
gives it that role and a list of expectations, one of which is to read its
lanes' finished pull requests for alignment rather than correctness. Nothing
in the skill, the record or its scripts lets it act on that reading. This
design works out how it can, inside four constraints the coordinator record
already imposes.

**Each coordinator's record is its own.** A record is a set of `record/*`
keys in the coordinator's own koto session. The land check
(`land-check.sh`) reads holds, pauses and holdings from the record of the
session that runs it, and the merge step (`land-merge.sh`) refuses what that
read reports held. A director that holds a lane pull request only in its own
record stops nothing in the manager's land step, which is where most lane
pull requests merge. The requirement is that a director's hold sits where
every session that would merge or recommend the pull request reads it, the
manager's land check included, so none of them can merge it or pass it up as
ready while it stands (R7).

**Holds exist, but say too little.** A hold row today is `{hold, on, until,
set_by, set, lifted}`, where `until` is `merged owner/repo#n`, `tag
owner/repo <tag>` or `lifted`, and only `state-hold.sh` writes the section. A
`lifted` hold ends when someone stamps its Lifted cell with a minute and a
name. The row has no reason, no receiver and no notion of a head. The
requirements need a hold that names the reason (the plan source it diverges
from and how), the receiver (the lane's manager) and the release (a new head
the director reads again and calls `fits` or `fits with follow-ups`) (R7). It
lifts only when the pull request's head is not the head it was placed on and
the director has called that head `fits` or `fits with follow-ups`; the lift
names the head it lifted on; a push back to the held head isn't a new head; a
`diverges` re-read leaves it standing; a second `diverges` adds no second
hold; a person may lift any hold, recorded with who lifted it; and every
director start lists each standing hold, a closed one as closed while held
(R9).

**The record's history is append-only entries with a closed kind list.**
`state-entry.sh` accepts nineteen kinds and checks some of them further (a
`goal-fit` entry must name the pull request it is put on; a
`milestone-verdict` entry follows a fixed line grammar). The alignment call
is the director's judgment of one lane pull request at one head. It has to
exist for the exact head before the director merges or recommends that pull
request, a new head needs a new call, and when two calls exist for one head
the later stands and both stay listed (R5). It names the plan sources it was
judged against, or `none` (R2); it is one of `fits`, `fits with follow-ups`
or `diverges`, with each follow-up named (R4); on a milestone verdict pull
request it names each Evidence clause by number and whether it is met (R6).
It has five named fields, pull request, head, call value, plan sources and
reason, in a fixed grammar that a tool outside the skill reads field by
field, and the write check refuses one missing a field or carrying another
value (R16). The feature may add exactly one entry kind, may not change any
existing kind's grammar and may not add a record section; every call is a
new entry and no entry is rewritten (R15). The existing `goal-fit` entry
can't carry it: it has no head, judges fit against the lane's brief rather
than the plan sources, and is written only on milestone roadmaps.

**Owner direction is already kept, in two places.** Standing rows record
what a person decided (a pause, a go-ahead, an approval, an answer, an
assignment) with the person as Owner and whoever carried it as Relayed by.
Decisions entries record questions, with an `escalated` state for one asked
of the run's target, an `asked` time and an `owed` message. The requirements
add a single route for a lane's question: a manager asks its director, never
the owner; the director first looks for a question already waiting on the
same subject or an answer already recorded, joins or answers from it and
names the matched record, and otherwise asks once, recording the lanes
waiting and the time asked; the answer closes the question and reaches every
waiting lane (R12). A relayed "the owner said X" is checked against the
recorded text before the director acts on it, and a mismatch or a missing
text is declined with both texts shown (R13). A director never holds a turn
open for the owner's reply in a turn the owner didn't start, keeps every
independent lane moving, and lists each waiting question with its age and
waiting lanes in every report, re-asking only on the skill's existing rule
(R14).

Two more facts shape the design. The record has no trace of a review: the
dispatcher-review design keeps a coordinator's own reading as prose in its
report, never as an entry, so nothing can list which merges were judged and
at which head. The requirements make the call's unit the manager's finished
unit at its final head (a unit marked done, reopened or dropped, a milestone
verdict pull request, or a roadmap or strategy change), and need every
director start (a new run, a resume, a takeover or a successor's first run)
to report each finished unit's final head and each manager-authored pull
request merged since the previous start with no call for its merged head;
a worker pull request that a manager holding the merge grant lands short of
finishing its unit is reviewed work, not a debt (R10). They need one read the
skill names to list every call oldest first with its five fields, and every
merge or recommendation with its head's call, `after merge`, `unreviewed` or
`manager-reviewed` (R11). The check that stops a merge or recommendation of a
head with no call has to record each refusal, and the next start prints how
many there were (R5). And the director learns of its lanes' merges
only from what managers report: the named-roles design makes a manager name,
in its report after a land, every worker pull request that merged in its lane
since its last report.

The director's reading is not a second correctness review. It asks whether a
lane pull request does what its plan sources say the work is for without
contradicting any of them: the roadmap clauses and milestone Evidence of the
unit it closes or moves, the strategy, each recorded owner decision whose
scope covers its unit or the files it changes, and the open holdings and pull
requests of the director's other lanes. It doesn't re-review code, launch
correctness reviewers or repeat the worker's review round or the manager's
land step (R1). A full read is owed when the pull request marks its unit
done, reopened or dropped, is a milestone verdict pull request, changes a
roadmap or strategy document, changes a document, path or roadmap another
lane has open work on (the call names that lane), or has a recorded owner
decision among its plan sources; anything else gets a one-line call, and the
skill states that line once (R3). A plan source the director can't read means no call, a report
naming that source, and no merge or recommendation until a call exists (R2).

### What this design builds on, and what it doesn't have yet

- **The reviewer concept** (shirabe#1449, merged): the reviewer of a
  coordinator's work is whoever dispatched it; finished work goes to the
  reviewer before it lands, merge grant or not; a coordinator that may not
  merge sends a ready pull request up with its own reading, and the grant
  holder in its calling hierarchy merges at the head that reading checked.
  This design keeps all of it and adds the call to what the own reading
  carries.
- **The named roles** (scoped in `docs/prds/PRD-coordinator-named-roles.md`
  and `docs/designs/DESIGN-coordinator-named-roles.md`; its plan is
  shirabe#1483, not merged): the Run row `role`, the record line, and the
  director's and manager's expectation lists. **This feature depends on that
  plan landing.** Until it does, no session knows it is a director, and
  nothing here applies. Today no record carries a role: the Run section has
  no `role` row, and the land check reads the merge path without one. The
  row arrives with the named-roles build that shirabe#1483 plans, which
  isn't merged. This design assumes nothing about the row beyond what that
  plan says: a Run-section `role` row, written once by its writer, read as
  `director` or `manager`. Where this design reads the row, it reads only
  that value.
- **The named roles' rule that a role holds across a succession**: R5 of
  `docs/prds/PRD-coordinator-named-roles.md`, "The role doesn't change across
  a succession." This design reads a session's role at the land check's gate
  and at every director start, and relies on R5 in this form: "A
  continuation keeps its role. A different role is refused unless the change
  is an intervention from above: the dispatching session higher in the
  calling hierarchy, or a person. The record keeps who intervened and when.
  The opener refuses any other change." The text on main states the first
  half; the intervention clause is the amendment the named-roles plan
  (shirabe#1483) carries. So a successor director keeps the gate and the
  start steps, and a manager can't become a director by continuing a
  lineage. This design adds no intervention of its own.
- **Standing-rule provenance** (designed and planned on main in
  `docs/designs/DESIGN-coordinator-standing-rule-provenance.md` and
  `docs/plans/PLAN-coordinator-standing-rule-provenance.md`, shirabe#1451
  and shirabe#1459; partly built): a `rule` kind of Standing row and a
  Source column that cites a koto decision, from which a reader works out
  whether a rule is what the owner said, what a dispatcher said, or a relay.
  It covers Standing rows, not holds. This design does not wait for it, and
  names under Solution Architecture where it would change what is built
  here, including what it would need to cover a lift.

## Decision Drivers

- **Reuse before adding.** The call is the one new entry kind. Holds use the
  existing Holds section and its one writer, owner questions use Decisions
  entries and Work rows, and the relay check reads Standing rows and settled
  decisions. No record section, no new grammar on an existing entry kind
  (R15, R19).
- **The merge path stays on the session's own record.** The land check and
  the merge step read only their own record today, and an unreadable input
  there means `held`. A director and its manager may run on different hosts
  or stores, and the record reader can't read another host's session or
  follow a takeover, so making one session's lands read another's record
  would let a split or an outage stall every land.
- **A hold reaches the session that would merge it** before that session
  can land or pass up the pull request (R7), and shows in every report of the
  manager it waits on (R8).
- **Machine-readable calls.** Five fixed fields in a grammar a JSON or line
  parser reads without free-text matching, refused at write when malformed
  (R16).
- **Checkable triage.** Whether a pull request needed a full read must be
  checkable afterwards from its unit, its changed files and the call's own
  plan sources (R3).
- **No authority from review.** Nothing here grants or withholds merge,
  close or release authority or defines a grant or level; who merges stays
  with the workspace's authority configuration, read as the reviewer concept
  reads it (R17).
- **Roles untouched.** A hold, a call, a declined relay and a lane's question
  change no role (R18).
- **No blocking on the owner.** A director never holds a turn open for the
  owner's reply in a turn the owner didn't start, and lanes that don't depend
  on a question keep moving (R14).
- **A later provenance rework stays local.** Where provenance will change
  where owner text is read, or give entries a source, the change should
  touch one reader rather than every call and hold already written.
- **Skill text over machinery where the judgment is the director's.**
  Matching two questions, or a relay with a recorded text, stays a judgment
  that names its match (R12, R13); the design doesn't automate it.

## Considered Options

### Decision 1: How a hold reaches every land check, and where its heads live

Delegated to /decision.

A `diverges` call has to stop every session that would merge or recommend the
lane pull request. The manager lands its workers' pull requests through its
own land step, which reads only the manager's record; the director lands or
sends up the pull requests a manager authors, through its own. The release
needs two facts about heads: the one the hold was placed on, and the one the
director re-read and called `fits`.

Key assumptions:

- A director and its manager can run on different hosts or stores, and the
  record reader can't read another host's session or follow a takeover.
- A manager records a hold its director sends as soon as it takes the
  message at its wait hub, before any land step, as the template already
  says for a hold someone asks for.
- Branch protection, not this feature, stops a person merging in GitHub's
  web interface; a person's merge while a hold stands is an override the
  record shows.

#### Chosen: Copy the hold by message, heads in the hold name and the Lifted cell

The director adds a `lifted`-until hold to its own record and, in the same
turn, messages the manager the row with the reason, the receiver and the
release; the manager adds the identical row to its own record with
`state-hold.sh`, taking a hold or a lift only through its dispatcher's
channel. The hold's name is `align-<repo name>-<number>-<40-hex placed-on
head>` (with `-<k>` if the same head is held again after a lift), which is
also how the `diverges` call it was placed on is found, so the placed-on head
lives in the row and the reason lives in that call. A director's lift stamps
the Lifted cell `<minute> by director at <address>, <fits|fits with
follow-ups> at <40-hex head>`, so the lifted-on head lives in the row too. The director only lifts through a
guarded lift run in the same writer run as the `fits` call, call first: it
reads the live head from GitHub and lifts only when the live head isn't the
placed-on head, the latest call for the live head is `fits` or `fits with
follow-ups`, and that call comes after the hold's `diverges` call in entry
order. A hold that became releasable without a lift (the live-head read
failed after the call was written, or the call came before the push) is
lifted by the same guard at the next director start, through
`alignment-call.sh --lift-releasable`, which writes no new call (R9). The
manager takes both messages when they arrive at its `wait` hub, as a new
`director-hold` wait event, and records the copy or its lift on that event's
edge, never later at its land step: the lift is refused unless the head it
names equals the `verified_head` of the manager's holding for that pull
request, or, when no holding links it (a pull request the manager authored), the
pull request's live head from GitHub, read fail closed (R7, R8, R9). A person's lift
on an unchanged head doesn't use this check: each side records it with
`state-hold.sh --lift`, as the template's `surface` text already says for a
person's word (R9). The manager's `director_hold` state then leaves by one of three
edges: `rework` to `rebrief` after a hold on a pull request with a holding,
`reverify` to `verify` after a lift on one, and `wait` otherwise. The event's
`unit` evidence names the holding's Worker topic, and `wait`'s edge writes it to
`report_topic` as a report's does, so a hold reaches the worker and a lift reaches
`land` with no fresh worker report (R8, R9). Every land check that would merge or pass up the pull
request now reads the hold from its own record.

The `reverify` edge needs three things the report path otherwise supplies. Before
taking it, the manager rewrites a row at Phase `held` to the Phase its entry point
and mode give (`scoping` or `executing`), so a lifted holding stops reading as held.
`board-record.sh` takes its pull request from `report_facts`' REPORT capture, which
this edge never refreshes and which may name another worker's pull request, so when
the latest entry into `verify` came from `director_hold` it reads the pull request
from the holding `report_topic` names. And `lib_unit`, which `state-confirm.sh
--verified` reads the unit through, counts a `director-hold` event with a non-empty
`unit` as an arrival. `land-check.sh` needs nothing here: it reads the VERIFIED
capture that `verify_board` writes on this visit.

The sender check reads the manager's Run `reports-to` row, `director at <address>`.
Nothing else rewrites that row after a successor takes over, so a successor's first
message to a lane names the row's current address and its own, and `--copy
--reports-to` rewrites the row through `state-stored-set.sh --run reports-to`, with
`--by` the sender, at that `director-hold` event. Its `--from` is the new address the
message names, not the row's. A message naming any other current address changes nothing,
and neither does one sent to a row holding no address, which stays the handover
gate's gap to fill (R7, R9).
The hold path leaves the Holds grammar, `bl_holds_eval`, `land-merge.sh`
and the merged-while-held Reversals rule untouched, and needs nothing new
in `land-check.sh`, whose hold read already covers it; that script's one
change is Decision 2's call requirement.

#### Alternatives Considered

- **Live cross-record read.** The hold lives only in the director's record
  and the manager's land check also reads its reviewer's holds. Rejected: it
  keeps the hold in the director's record alone; the reader can't reach
  another host's store or follow a takeover, so on split hosts every worker
  pull request would read as held with nobody able to lift it; and it loses
  the merged-while-held Reversals row the manager's record enforces for its
  workers' pull requests.
- **A label on the pull request.** Rejected: a missing label can't permit a
  merge, so it only narrows the delivery window, at the cost of a merge-path
  change, a new GitHub write path and repository permissions, and against the
  rule that record state isn't kept on GitHub.
- **A new `until` form evaluated against call entries.** Rejected: its one
  gain, the call and the lift in one write, is matched by the single-run
  writer; it changes the Holds grammar and evaluator, puts entries on the
  merge path, and makes every older reader refuse the whole record.
- **The director writes into the manager's record.** Rejected: it breaks the
  one-writer-per-record rule, which takeover fences and the cloud backend
  enforce.

### Decision 2: The alignment call's grammar, its check, and where a call is required

Resolved inline.

The call needs five fields a tool reads without free-text matching, refused
at write when malformed, plus what R4 and R6 add (follow-ups, Evidence
clauses). It also has to be the thing that lets the owner's list show which
heads were recommended, since the record keeps a recommendation nowhere else.

Key assumptions:

- The named-roles Run `role` row exists and says `director`.
- An entry's text may hold several lines, as milestone verdict entries do.

#### Chosen: An `alignment` entry kind with a fixed line grammar, checked in state-entry.sh

The entry is written with `state-entry.sh --kind alignment --on
<owner/repo#n>`, stays in the session (it isn't an outward kind), and holds
seven lines in a fixed order, modelled on the milestone verdict entry (the
grammar is under Key Interfaces). An `alignment_check` beside
`goal_fit_check` refuses, with exit 65 and nothing written, a missing or
reordered line and every combination the grammar rules out (R16).

Today `--on` is accepted only for an outward kind (any other kind exits 64),
and an entry with `--on` skips the host-visibility scan and is posted as a
comment when the repository opts in. So `state-entry.sh` gains a third `--on`
mode, for `alignment` only, so that each call names its pull request and is
checked at write (R16): it checks that the entry's first line names the
`--on` pull request, runs the existing `on_admitted` check that the pull
request is in the host or a holding's repository, keeps the host-visibility
scan an entry kept in the session gets, and never posts to GitHub. `--on
none` is refused for it. Every other kind that stays in the session still
exits 64 on `--on`, as `state-entry-on_test.sh` pins today.

The director's land check reads the run's own alignment entries and reports
`uncalled <pr> <sha>` when no standing call for the pinned head exists or the
standing one is `diverges` (R5). It is its own token, with its own exit code
(86) in `coord-verdict.sh`'s table, and the check runs after the hold read
and before the posture, so a held pull request still reads `held` and a
`diverges` call with its hold is never counted as a head with no call. That
one check covers a merge and a recommendation on a pull request the director
verified, since the surface path that sends one up runs after it. The read is
the session's own record, so the merge path still reads nothing from outside.

Three recommendations never reach that check: a worker pull request a manager
sends up ready, for which `land-check.sh` exits 2 with no verify capture of the
director's own; a milestone verdict pull request, which goes from
`milestone_verdict` to `record` and then to the reviewer; and a roadmap or strategy
edit the template sends to the reviewer directly. Their directives run
`alignment-call.sh --require --on <owner/repo#n>` first. It exits 0 only when a
standing `fits` or `fits with follow-ups` call exists for the pull request's live
head and no unlifted `align-` hold on the pull request stands, and non-zero naming
the head or the hold otherwise or when that head can't be read, so a `fits` call at
a held head doesn't pass it (R7, R9). On non-zero for a missing call the directive
does `align_call`'s work where it stands: it writes the refusal line once per pull
request and head, runs `alignment-sources.sh` and `alignment-call.sh`, and runs
`--require` again. It doesn't go to `align_call`, whose only way forward is `land`.
On non-zero for a hold it writes no refusal line, since a held head is never counted
as a head with no call. It runs `alignment-call.sh --lift-releasable`, which lifts a
hold whose guarded lift failed on a `fits` call for a new head and leaves any other
standing, and runs `--require` again. A pull request still refused leaves by an
existing edge, naming what stopped it, so these paths add no edge.

A director checks a worker pull request a manager sends up ready at
`classify_report`, before it submits `classification: done` or `blocked` for that
report. Passing, `blocked` goes to `surface`, which submits `surfaced: blocker` with
`need: reserved-step merge <link>`; `need-check.sh` accepts it, `surface_check` goes
on to `wait`, and the report up names the called head. A passing `done` that
`verify_board` sends to `surface` on `unlinked` goes up the same way. Still refused
on a `diverges` call or a standing hold, the director submits `classification:
needs_fix`, whose edge goes to `rebrief`: the message tells the manager what stopped
the pull request and that a new head releases it, and `rebrief` goes back to `wait`
or on to `pick_facts`. Still refused with no call, because a plan source or the live
head can't be read, the manager can't fix it, for the reason `uncalled` avoids
`rebrief` below. The director submits `classification: blocked`, and what `surface`
submits depends on what failed. When a repository can't be read (the pull request's
own, named in `--on`, when the live head can't be read, or the one
`alignment-sources.sh` names with `repository`), `surface` submits `surfaced: blocker`
with `need: access <owner/repo>` for that repository. `need-check.sh` accepts it,
`surface_check` goes on to `wait`, and the report up names the source (R2) and
recommends nothing. When the repository reads and the file doesn't (the helper names
it with `file`: a roadmap missing at the commit it read, a milestone with no
Evidence, an `upstream:` that names no file), no repository is unreadable, and an
access need would ask for access the director already holds and pass `need-check.sh`
all the same; no need kind names a missing file. `surface` then submits `surfaced:
decision`, and at `decision_raise` the director opens an entry naming the pull
request and the path, with two options: restore the file at that path, or point the
document that names it at a readable one. Either fix is to a roadmap or strategy
document, which is neither the director's to change nor the manager's, so the
director gives the entry an `escalate` verdict. `decision_next` goes through
`decision_verdict`, `escalate` and `escalate_send`, and once the escalation is sent
nothing is owed, so it goes on to `pick_facts` by `clear`. The escalation names the
source (R2), and nothing is recommended. Neither route enters `rebrief`, `verify` or
`land`, and either way the pull request comes back to `classify_report` with the
manager's next report of it, where `--require` runs again. `done` doesn't fit this branch: it goes
through `verify_board`, whose `unlinked` exit reaches `surface` with no call and no
need that names it. A record the director can't read isn't this branch: it's a read
failure, fixed and ticked again at whatever state it stops, as every record read is.
The check can't sit at
`surface`, where a refused pull request has no way out: `need-check.sh` takes only
credential, reserved-step and access needs and a refused need comes back to
`surface`; `surfaced: merge_table` goes to a `record` step that waits for a Verified
head this path never wrote; and `surfaced: decision` raises a choice the call has
already made. That last reason holds only for a pull request that has a call. With no
call, nothing has chosen how a missing file gets restored, which is why the no-call
case above can raise it as a decision.

`milestone_verdict` checks the pull request once it's open and before `verdict:
recorded`. Still refused, it leaves with `verdict: deferred`, which goes to `wait`.
A `landed` tick brings the run back through `roadmap_status`, whose script prints
`verdict-owed` again, and that visit checks the same pull request and writes no
second entry, since `roadmap-status.sh --verdict` refuses a new entry while the
first one's row is pending. Passing on that visit, the director writes the called
head into that Side effects row's Verified head with `state-write.sh` before
`verdict: recorded`: the record step waits for a record write later than the latest
`wait`, and the call and the refusal line are entries, which don't write the record.
`roadmap_status` checks the edit before it's handed to
whoever merges. Still refused, it submits `status: opened` with the edit not handed;
the record step confirms the Side effects row the script already wrote and goes on
to `pick_facts`. The template has no state of its own for a strategy edit, so a
strategy pull request is checked at `classify_report` or `land`, as any lane pull
request is. These three are held by a directive's check, not by a gate, and the
engine walk covers each (R5, R6).

The gate applies only when the Run `role` row reads `director`. A record with
no `role` row gets no gate, and the session runs as it does today; a `role`
row that can't be read is `unready <pr> <sha>` with the reason
`role-unreadable`. Reading the role on the land path is an exception to the
named-roles rule that no gate branches on the role
(`docs/designs/DESIGN-coordinator-named-roles.md`, Security Considerations):
the call gate is a duty check, not an allowance. It narrows nothing a role is
allowed to do, since the posture read, the grant and the merge step don't
change, and it asks a director only for the record of a judgment its
expectation list already owes. `land-check.sh` joins that design's reader
allow-list test by the one function that reads the row, and the director's
start reads its role from the record line its first report prints, which
that test already lists.

The gate exists so the director never merges or recommends a head with no
call (R5), and it records what it stops. `uncalled` routes to a new director
agent state, `align_call`, never to `rebrief`, since the manager can't fix a
call only the director records. There the director writes one entry of the
existing free-text `entry` kind whose first line is `Refused:
no-alignment-call <owner/repo#n> at <40-hex head>`, once per pull request and
head: when the record already holds that line for the head, a later visit
that refuses again writes nothing, so the count is of heads stopped, not of
visits. It then runs `alignment-sources.sh` and `alignment-call.sh` and goes
back to `land`, which reads the new call; when a source can't be read it
records no call (R2), names the source in its report and goes back to `wait`.
`alignment-read.sh` counts those entries since the previous start and the
start report prints the count. `land-check.sh` itself stays read-only, and
reusing the `entry` kind adds no kind and changes no grammar (R15).

#### Alternatives Considered

- **JSON in the entry's text.** Parseable, but every other checked kind uses
  lines, and people read entries in the account. Rejected.
- **Widening the goal-fit entry.** Changes an existing grammar (R15) and
  carries no head. Rejected.
- **A second entry kind for a recommendation.** Exceeds the one kind R15
  allows; the call's `Action` line carries it instead. Rejected.
- **Posting the call on the pull request.** Nothing in the requirements asks
  for it, and it would publish a judgment under the repository's content
  opt-in. Left for later.
- **Requiring the call only in skill text.** Leaves R5 unchecked at the one
  point where it matters, the merge. Rejected.

### Decision 3: How the director finds a pull request's plan sources and its depth of reading

Resolved inline.

The call must name its plan sources and the triage line must be checkable
afterwards. Part of finding them is mechanical (the unit, the roadmap, the
changed files); part is judgment (whether a recorded owner decision's scope
covers the pull request).

Key assumptions:

- A lane pull request's unit is knowable from the lane's brief or the pull
  request, as the requirements define it.
- A roadmap names its strategy in its frontmatter `upstream:`; when it
  doesn't, the strategy source is `none` and the call says so.

#### Chosen: A read-only helper for the mechanical half, the judgment in skill text

`alignment-sources.sh` prints, as JSON, the pull request's unit, that unit's
roadmap clauses and milestone Evidence read from the roadmap on the default
branch at a named commit (with the roadmap reader pick already uses), the
strategy path the roadmap names, the changed files, the other lanes' open
work, the mechanical full-read triggers it found, and candidate owner
decisions: every Standing row and settled decision whose On or text names the
unit or a changed path. The other lanes' open work is, for each holding in
the director's Holdings rows other than the pull request's own lane, the
open pull requests its manager's latest report names in its `open=` lines
(with their changed files from GitHub; Decision 4 gives the lines, and no
free text is read for them) and the documents, paths and roadmap units its
Holdings and Work rows name. When the pull request changes a file one of those open
pull requests also changes, or a document, path or roadmap one of those rows
names, the helper reports an `other-lane` trigger naming the lane, the read
is full, and the call names the lane and its open work in Sources (R1, R3). The
director keeps the candidates whose scope covers the pull request and names
each in Sources; a kept owner decision makes the read full. A source the
helper can't read makes it exit naming that source as `<owner/repo> <path>`,
followed by `repository` when the repository itself can't be read or `file`
when it reads and the file, or the part of it the helper needs, doesn't. The
director records no call, names the source in its report and neither merges nor recommends
(R2). The triage line is stated once, in the director's section of the skill,
and the helper's reasons cite it.

#### Alternatives Considered

- **Skill text only.** Leaves the triage uncheckable and repeats the roadmap
  parse in prose. Rejected.
- **Mechanical owner-decision matching by unit string.** Misses decisions
  scoped by files or worded differently, and hides the judgment the
  requirements want shown. Rejected.
- **Asking the manager for the plan sources.** The director would be judging
  the manager's reading of itself. Rejected.

### Decision 4: Finding unreviewed merges and listing the calls

Resolved inline. Re-resolved once in cross-validation: its first answer read
each manager's record, which Decision 1 showed can't be read across hosts or
after a takeover.

The calls are in the director's own record. The hard part is the set of lane
pull requests that merged: a confirmed merge empties a Holdings row's
pull-request cell and the row goes at teardown, the director's own Holdings
rows cover only the managers' authored work, and manager reports are
messages.

Key assumptions:

- Manager reports that name pull requests arrive at the director's `wait`
  hub as `report` or `progress` events, whose evidence keeps the message
  whole and the pull request it names.
- A successor can read its lineage's earlier session logs on its own host;
  when it can't, the gap case below covers it.

#### Chosen: One read over the director's own entries, its own wait events and GitHub

`alignment-read.sh` lists the calls from the director's `alignment` entries,
oldest first, each parsed into its fields, with the latest call per pull
request and head marked standing. The lane pull request set is every pull
request the calls name, the pull requests linked in the director's own
Holdings rows, and every pull request a manager named in a `report` or
`progress` event the director's runs submitted (the event's pull request,
and the links in its message, which carry the manager's after-land list,
plus the pull requests its `unit=` and `open=` lines name). A link only adds a
pull request to the set: whether a unit is finished, and which pull requests
are open, is read from those lines alone. GitHub gives each one's state,
merge time and merged head.

A manager's report says which units it finished, and which lane pull requests
are open, in fixed lines its result block carries, so no reader matches free
text (R10, and R1 and R3 for the other lanes' open work):
`unit=<topic> <done|reopened|dropped> <owner/repo#n>` for each unit it
finished since its last report, `<topic>` the Worker topic of its holding for
that unit, `open=<owner/repo#n>` for each open lane pull request, and
`worker=<owner/repo#n>` for each pull request the report names or lands that a
worker wrote, not the manager.
`render-result.sh` prints them inside the block it already prints
(`=== RESULT ===` to `=== END RESULT ===`), from new repeatable `--unit`,
`--open` and `--worker` arguments, beside the `pr=` and `review_round=` lines, and the
manager runs it for every report it sends its director, not only its final
one. The block is the place because it is the one part of a report the
template already passes on whole as the event's `report` evidence and a
script already parses line by line.

A pull request is manager-authored when no `worker=` line names it and either
it was the `pull_request` of a `report` or `progress` event whose `unit` is a
holding's topic (a manager reports its workers' pull requests the same way, so the
field alone can't tell them apart), or one of the director's Holdings rows has a
`verified_head` equal to GitHub's merged head. The `worker=` test covers both
because a director can verify an open worker pull request that its manager then
lands at that head, which leaves that head on the row. A manager that leaves out a
`worker=` line lists its worker's merge as `unreviewed`, a visible false debt
rather than a hidden one (R10). The Holdings link alone
can't say it: `merge_confirm` and `merged_facts` clear a row's Pull request
cell at the merge, keeping its `verified_head`, and the row goes at teardown.

A merge owes a call when it is a finished unit's final head (a `unit=` line
names its unit done, reopened or dropped at that pull request, it is a
milestone verdict pull request, or GitHub shows it changes a roadmap or
strategy document, the test `alignment-sources.sh` uses for its triggers) or
when it is manager-authored. Such a merge is reviewed when a call for its
merged head was stamped before the merge, `after merge` when the first call
for that head came later, and `unreviewed` when none exists. A worker pull
request its manager reported landing short of a finished unit, with no call
before it merged, is `manager-reviewed`: the manager's land step reviewed it,
and it isn't a debt (R10). A recommendation is a call whose Action is
`recommend`.

With `--since <stamp>`, the read keeps `calls`, `merges`, `recommendations`
and `refusals` to what is stamped or merged after the stamp, while each
merge's review is still judged against every call of the run; `holds` stay
whole (R10, R12). The start passes the stamp of the previous director start.
Nothing the record writes today marks every start: the `run` entry
`state-stored-set.sh --rule-files` writes is written only when a Run row
changed, and a `takeover` entry only at a takeover. So each director start,
once its report has gone, writes an `entry` whose first line is `Director
start: <YYYY-MM-DDTHH:MM:SSZ>`, the time its read ran, and the next start
reads `--since` from the latest such entry; on the run's first start there is
none, and the window runs from each lane's dispatch (R10). A carry copies the
entries, so a successor reads its predecessor's. An earlier session of the lineage
that can't be read is printed as a gap: the start names it and asks each
manager for its lane's merges since the window start, and their replies are
reported at the next start.

#### Alternatives Considered

- **Reading each manager's record.** Fails across hosts and stores and after
  a manager's takeover. Rejected in cross-validation.
- **GitHub search by repository and time alone.** Can't tell a lane's pull
  request from other work in a shared repository. Rejected.
- **An entry per pull request the director hears of.** A second entry kind
  (R15). Rejected.

### Decision 5: Owner questions and the relay check on the existing record

Resolved inline.

The requirements want one question per subject reaching the owner, with
waiting lanes and age, and relays checked against recorded owner text, all
on what the record has.

Key assumptions:

- The director has a Work row for each manager's holding; the handover check
  already requires one for every live holding.

#### Chosen: Decisions entries for questions, Work rows for waiting lanes, Standing rows and settled decisions for owner text

A question the director can't answer from the record becomes a decision
opened and escalated to the owner with `state-decision.sh`, sent as a
message. `state-decision.sh` keeps one escalated entry at a time and queues
any other escalation behind it (state `coordinator-verdict`, Verdict
`escalate`, Asked empty) until the slot frees. So a waiting question is an
escalated or a queued entry. An escalated entry's age runs from Asked; a
queued entry's from its Updated, which `--escalate` stamps when it queues the
verdict and which any later write to the entry replaces only by taking it out
of the queue. Each lane waiting on it has its holding's Work row Next set to
`waits on decision <n>`. A matched waiting question, escalated or queued,
gets the asking lane's Work row pointed at it and nothing else: no evidence
on the decision, since evidence on an escalated entry owes the owner a
withdrawal. The second lane's question still reaches `decision_open` inside
its manager's report, and the template has every extracted question covered
there, so it opens its own entry; the director settles that entry at once
with `state-decision.sh --settle --outcome "joins decision <n>"`, whose owed
reply tells the lane the matched record (R12). A matched answer is quoted
back from the record. Every reply names the matched record. The answer
settles the decision, and every lane whose Work row names it is told.
Reports list each waiting decision, escalated or queued, with its age and the
lanes pointing at it; the existing re-ask rule schedules any repeat. The
relay check reads Standing rows whose Owner is the owner and whose Relayed
by is empty, and decisions the owner settled; a relay matching one is acted
on and the match named, and anything else is declined with both texts. That
rule needs a person's word told to the director directly to be recorded with
Relayed by empty, as `state-stored-set.sh --standing` and the template's
`wait` directive already say; `references/state-keys.md` still tells a
coordinator to record itself as the relayer, and that line is corrected with
this feature (R13).

The owner funnel rides the same record (R12). The manager's expectation list
says it sends its questions, reports and pull requests to its director and
never to the owner, and its Run `reports-to` row names the director, so
nothing from a lane reaches the owner except through the director. Each
director report to the owner carries the calls whose stamp is after its
previous report to the owner, `alignment-read.sh --since <that stamp>`'s
`calls`, `diverges` calls first, grouped by subject: a pull request's calls,
its hold and any lane question on that pull request go in one message,
however many lanes or calls touched it. Nothing in the record marks an owner
report today, so each report, once sent, writes an `entry` whose first line
is `Owner report: <YYYY-MM-DDTHH:MM:SSZ>`, the time of the read it carried,
and the next report reads `--since` from the latest one; with none, it
carries every call of the run (R12). A call the owner
reverses becomes a Standing `answer` row with the owner as Owner, Relayed by
empty, and What naming the reversed call's entry number, pull request and
head (R13). The director then records a new call on that head with
`standing s<n>` in Sources and the owner's value, tells the lane the row id
so it can cite it, and, where the owner reversed a `diverges`, records the
owner's lift on the `align-` hold as a person's lift and relays it to the
manager's copy. The relay check reads exactly those rows, so a lane's later
relay citing `s<n>` matches.

#### Alternatives Considered

- **Waiting lanes as evidence on the decision.** Owes the owner a withdrawal
  and a re-send, a second message on one subject. Rejected.
- **A question queue or section.** A new section (R15), and routing beyond
  the record, which the requirements rule out. Rejected.
- **Exact-text matching.** Two wordings of one question defeat it. Rejected.

## Decision Outcome

The five decisions fit together around one rule: every session acts on its
own record, and what crosses between sessions crosses by message. The
director's calls are entries in its record, and its land check refuses to
merge or send up a manager's pull request without a standing call for the
pinned head. A `diverges` call places a hold in the director's record and,
by message, in the manager's, so the manager's land check stops its workers'
pull requests without reading anything new; the hold's name carries the head
it was placed on and points at the call that gives its reason, and its
Lifted cell carries the head it was released on. The guarded lift checks
both release conditions against GitHub and the director's own entries before
it stamps that cell. The list read joins the director's entries, its own
wait events and GitHub, so R10 and R11 come from one script whose sources
the director owns. Owner questions and relays use rows and entries the
record already has, and the triage helper keeps the mechanical part of
finding plan sources out of prose while leaving the matching of owner
decisions to the director, visibly.

What the design admits in exchange: a worker pull request merged after the
call but before the manager has recorded its copy is shown afterwards (a
Reversals row in the director's record, the merge listed), not prevented;
one hold is two rows, so a person's lift has to be relayed to the other
record; and the reason and release sit in entries, not in the row.

## Solution Architecture

### Overview

The director runs the coordinate skill with the Run `role` row reading
`director`. When a manager reports a lane pull request ready or landed, or
sends one it authored, the director runs `alignment-sources.sh` on it, reads
what it must, and records a call with `alignment-call.sh`. A `fits` or `fits
with follow-ups` call on a manager-authored pull request lets the director's
land step merge it (when its posture allows) or send it up with its own
reading; a `diverges` call places and sends the hold; a call on a held pull
request's new head may release it. At every start, `alignment-read.sh
--since` reports unreviewed merges and the standing holds. Owner questions
and relays follow the skill text in the director's section.

### Components

| Component | Kind | What it does |
|-----------|------|--------------|
| `state-entry.sh` | changed | Adds `alignment` to `ENTRY_KINDS` and an `alignment_check` beside `goal_fit_check`. Not an outward kind. A third `--on` mode, for `alignment` only (R16): the first line must name the `--on` pull request, `on_admitted` runs, the host-visibility scan stays, `--on none` is refused, and nothing is posted. Every other kind that stays in the session still exits 64 on `--on`. |
| `alignment-call.sh` | new | The director's one writer of a call: writes the entry through `state-entry.sh`; on `diverges` with no director hold standing on the pull request, adds the `align-` hold through `state-hold.sh` and prints the message to send the manager; on `fits` or `fits with follow-ups`, runs the guarded lift on any standing `align-` hold and prints the lift message. A call on a merged pull request is written (it is what `after merge` lists); only placing a hold on one is refused. |
| `alignment-call.sh --lift-releasable --on <owner/repo#n>` | new mode | Runs the same guarded lift on each releasable `align-` hold on the pull request, writes no call, and prints the lift message for each hold it lifts (R9). The director's start runs it for each hold `alignment-read.sh` reports `releasable`. |
| `alignment-call.sh --copy` | new mode | The manager's side, run on the edge of a `director-hold` wait event: `--copy --add` records a director's hold as sent and `--copy --lift` lifts the manager's copy, each taking `--message-file F --event <n> --from <sender>` and refused unless `--from` is the address in the manager's Run `reports-to` row; the lift is also refused unless the head it names equals the `verified_head` of the manager's holding for the pull request, or the live head when no holding links it, and isn't the placed-on head in the hold's name (R7, R8, R9). `--copy --reports-to` rewrites that row for a successor, refused unless the message names the row's current address and `--from` as the new one (R7, R9). Each writes a `hold` entry naming event `<n>`. |
| `board-record.sh` | changed | When the latest entry into `verify` came from `director_hold`, reads the pull request from the holding `report_topic` names instead of `report_facts`' capture (R8, R9). |
| `state-common.sh` | changed | `lib_unit` counts a `director-hold` event with a non-empty `unit` as an arrival (R8, R9). |
| `alignment-call.sh --require --on <owner/repo#n>` | new mode | Read-only. Exits 0 only when a standing `fits` or `fits with follow-ups` call exists for the live head and no unlifted `align-` hold on the pull request stands; run by the directives of the recommendations that skip `land` (R5, R6). |
| `state-hold.sh` | unchanged | Stays the only writer of the Holds section; every lift calls its `--lift`. |
| `land-check.sh` | changed | When the Run `role` row reads `director`, after the hold read and before the posture: reports `uncalled <pr> <sha>` unless a standing non-`diverges` call exists for the pinned head (R5). No `role` row: no gate. A `role` row that can't be read: `unready <pr> <sha>`, reason `role-unreadable`. Reads the row in one function, which joins the named-roles reader allow-list test. Own record only. Nothing else in the merge path changes. |
| `coord-verdict.sh` | changed | `uncalled` exits 86, with its template arm (R5). |
| `render-result.sh` | changed | Repeatable `--unit '<topic> <done\|reopened\|dropped> <owner/repo#n>'`, `--open <owner/repo#n>` and `--worker <owner/repo#n>`, printed as `unit=`, `open=` and `worker=` lines inside the result block (R10, R1). |
| `alignment-sources.sh` | new | Read-only: unit, roadmap clauses and Evidence at a commit, strategy path, changed files, the other lanes' open work (from managers' `open=` lines), mechanical full-read triggers (an `other-lane` trigger among them), candidate owner decisions. Exits naming any source it couldn't read as `<owner/repo> <path>` and `repository` or `file`. |
| `alignment-read.sh` | new | Read-only: calls, the lane pull request set, merges and recommendations with their call status (`manager-reviewed` among them), standing `align-` holds with their state (standing, closed while held, releasable), the gate's refusal count, and lineage gaps. JSON out. It reports a releasable hold; it lifts nothing. |
| Coordinate template | changed | The `uncalled` arm from `land` to a new director agent state, `align_call`, which writes the refusal entry once per pull request and head, runs `alignment-sources.sh` and `alignment-call.sh`, and goes back to `land` (or to `wait` when a source can't be read) (R5, R2). A new `wait` event, `director-hold`, with evidence fields `message`, `from` and `unit`, whose edge goes to a new manager agent state, `director_hold`, that runs `alignment-call.sh --copy --add`, `--copy --lift` or `--copy --reports-to` and leaves by its `rework`, `reverify` or `wait` edge (R7, R8, R9). The director's start runs `alignment-read.sh --since`, `--lift-releasable` on each releasable hold, reports its unreviewed list, holds and refusal count, and writes its `Director start:` entry (R10, R9, R5). |
| `SKILL.md`, `references/state-keys.md` | changed | The director's alignment section (the triage line stated once, the call, the hold, the owner funnel, owner questions, relays, recording an owner's reversal, the `Owner report:` entry); the manager's hold duty in its reports, its `unit=` and `open=` lines, and its rule that nothing goes to the owner but through the director; the entry grammar, the refusal, `Director start:` and `Owner report:` lines, the `align-` hold name and Lifted text; the corrected line on who a person's word names as relayer. |

### Key Interfaces

**The alignment entry.** Written with `state-entry.sh --session S --kind
alignment --on owner/repo#n --text-file F`, the third `--on` mode Decision 2
gives (checked against the first line, admitted by `on_admitted`, scanned for
the host's visibility, never posted), at most 16 KiB, these seven lines in
this order with no blank line:

```
Alignment: <owner/repo#n> at <40-hex head> -- <fits|fits with follow-ups|diverges>
Read: <full|one-line>
Sources: <none | <source>; <source>; ...>
Reason: <one line>
Evidence: <none | <n> <met|not met>; ...>
Follow-ups: <none | new: <title>; ...>
Action: <merge|recommend|hold|none>
```

A source is one of `roadmap <path> at <40-hex> <unit> clause <n>`, `strategy
<path> at <40-hex> <section heading>`, `standing s<n>`, `decision <n>` or
`lane <holding> <owner/repo#n | path>` (another lane's open pull request or
the document or path its rows name). A
reader splits each line once on `: ` and a list on `; `. The five fields R16
names are the first line's pull request, head and call value, the Sources
line and the Reason line; Read, Evidence, Follow-ups and Action carry R3, R6,
R4 and the owner's list. `alignment_check` refuses: a missing, extra or
reordered line; a first line whose pull request isn't `--on`; a head that
isn't 40 hex; a value outside each line's set; `fits with follow-ups` with
Follow-ups `none`, or another call with a follow-up; `diverges` with Sources
`none`; `Read: one-line` with a call other than `fits`; `Action: hold` with a
call other than `diverges`, or `diverges` with another Action.

**The `align-` hold.** A row in the existing grammar, in the director's
record and the manager's:

```json
{"hold": "align-<repo name>-<n>-<40-hex placed-on head>[-<k>]",
 "on": "<owner/repo#n>", "until": "lifted",
 "set_by": "director at <address>, receiver manager at <address>",
 "set": "<YYYY-MM-DDTHH:MMZ>",
 "lifted": "<empty | <YYYY-MM-DDTHH:MMZ> by director at <address>, <fits|fits with follow-ups> at <40-hex head> | <YYYY-MM-DDTHH:MMZ> by <person>[, relayed by <role>]>"}
```

The release is the same for every `align-` hold and stated once in the skill:
a new head the director re-reads and calls `fits` or `fits with follow-ups`.

**The guarded lift.** Inside `alignment-call.sh`, after a `fits` or `fits
with follow-ups` call is written: for each unlifted `align-` hold on the
pull request, read the live head from GitHub, and lift only when it isn't the
placed-on head in the name, the latest call for the live head is the one just
written or a later non-`diverges` one, and that call's entry number is above
the `diverges` call the hold is keyed to. A failure after the call is written
exits with its own code naming the hold, leaving it standing.
`alignment-read.sh`'s hold listing evaluates the same three conditions and
reports a hold that meets them as `releasable`, and one whose live head has
no call as `needs re-read`; it lifts nothing.
`alignment-call.sh --lift-releasable --on <owner/repo#n>` runs the guard on
each releasable `align-` hold on the pull request, writes no call, and prints
one lift message per hold it lifts; the director's start runs it for each
hold the read reports releasable (R9).

**The land check's tokens.** `land-check.sh` keeps its tokens (`permit`,
`deny`, `confirm`, `unready`, `dirty`, `held`, `moved`, `paused`) and gains
`uncalled <pr> <sha>`, exit 86 in `coord-verdict.sh`, printed only when the
Run `role` row reads `director`, after the hold read, when no standing
non-`diverges` call exists for the pinned head (R5). A `role` row that can't be read is `unready` with
reason `role-unreadable`; a record with no `role` row gets no gate.

**The messages.** To the manager on a hold: the pull request, the hold row,
the reason (the call's Sources and Reason), the receiver and the release. On
a lift: the hold name, the head it was released on and the entry number of
the `fits` call it rests on. Each arrives at the manager's `wait` hub as a
`director-hold` event, whose evidence carries `message` (the whole text, as
it arrived), `from` (the sender as the arriving message names it, which
the agent supplies) and `unit` (the holding's Worker topic, empty when no
holding links the pull request), and whose edge goes to the `director_hold` state. There
the manager runs `alignment-call.sh --copy --add` or `--copy --lift` with
`--message-file` holding the message, `--event` the event's log sequence and
`--from` the evidence's sender (R7, R9). `--copy --add` adds the row as sent,
through `state-hold.sh`, and writes a `hold` entry carrying the reason, the
release and event `<n>`. `--copy --lift` lifts the copy at once, refused
unless the head the lift names equals the `verified_head` of the manager's
holding for that pull request, or the live head when no holding links it, and
isn't the placed-on head, and its `hold`
entry carries the hold name, the `fits` call's entry number and event
`<n>`. Neither waits for the manager's land step.

**The manager's report lines.** Inside the result block `render-result.sh`
prints, one line per item, before `=== END RESULT ===`:

```
unit=<topic> <done|reopened|dropped> <owner/repo#n>
open=<owner/repo#n>
worker=<owner/repo#n>
```

`unit=` names each unit the manager finished since its last report, by the
Worker topic of its holding, with the pull request that finished it; `open=`
names each open lane pull request; `worker=` names each pull request the report
names or lands that a worker wrote. The manager prints the block in every
report it sends its director. `alignment-read.sh` and `alignment-sources.sh`
read these lines from the `report` evidence of the director's `report` and
`progress` events and nothing else in the message (R10, R1, R3).

**The start and owner-report entries.** Two lines of the existing `entry`
kind, each the entry's first line: `Director start: <YYYY-MM-DDTHH:MM:SSZ>`,
written by each director start after its report, and `Owner report:
<YYYY-MM-DDTHH:MM:SSZ>`, written after each director report to the owner,
each naming the time of the `alignment-read.sh` run it reported. The next
start and the next owner report pass the latest one's time as `--since`
(R10, R12).

**`alignment-sources.sh --session S --on <owner/repo#n> [--unit <roadmap
unit>]`.** Prints `{unit, clauses, evidence, commit, strategy, changed_files,
other_lanes, triggers, candidates}`. `unit` is `--unit` when given, otherwise the
roadmap unit the Holdings row of the pull request's lane names; with neither it is
`none`, and `clauses` and `evidence` are empty until the director names the unit
from its own reading and runs it again (R2, R3).

**`alignment-read.sh --session S [--since <stamp>]`.** Prints `{calls: [...],
merges: [...], recommendations: [...], holds: [...], open: [...], refusals: <n>,
gaps: [...]}`: each call with `entry`, `stamp`, `pull_request`, `head`, `call`,
`read`, `sources`, `reason`, `evidence`, `follow_ups`, `action`, `standing`;
each open lane pull request with `pull_request`, its live `head` and `call`, the
standing call's value for that head or `none` (R5, R11), whole under `--since`;
each merge with `pull_request`, `merged_head`, `merged_at`, `call` (the latest
call's value for the merged head, or `none`) and `review`
(`reviewed`, `after merge`, `unreviewed` or `manager-reviewed`); each
recommendation with its call; `refusals`, the count of the gate's refusal
entries; each `align-`
hold with its reason (from the call its name points to) and a state derived
from the row, GitHub and the entries: `lifted` when its Lifted cell is
filled; otherwise `merged while held` when the pull request merged (the
Reversals row is owed), `closed while held` when it closed unmerged,
`releasable` when the guarded lift's three conditions hold, and `standing`
otherwise, flagged `needs re-read` when the live head has no call; and each
standing hold with the latest manager report that named it, so a hold no
report has acknowledged shows as unconfirmed and is re-sent. With `--since
<stamp>`, `calls`, `merges`, `recommendations` and `refusals` hold only what
is stamped or merged after the stamp, each merge's `review` still judged
against every call of the run, and `holds` stay whole; without it, every
item of the run. This is the one read R11 names; the start report quotes its
`unreviewed` merges (R10).

### Data Flow

1. A manager reports a lane pull request (a `report` or `progress` event at
   the director's `wait`, its result block carrying its `unit=` and `open=`
   lines), or sends one it authored.
2. The director runs `alignment-sources.sh`; on an unreadable source it
   records nothing and reports which source.
3. It reads at the depth the triage line gives and runs `alignment-call.sh`.
4. `fits` or `fits with follow-ups`: on a manager-authored pull request, the
   director's land check finds the standing call for the pinned head (with
   none, it reports `uncalled`, and `align_call` writes the refusal entry,
   records the call and goes back to `land`); the
   land step merges (posture allows) or surfaces the pull request with the
   call and its own reading to its reviewer, and the grant holder above merges
   at the called head. A worker pull request a manager sends up ready doesn't
   enter the director's `land`: at `classify_report`, `alignment-call.sh --require`
   checks its call, the directive records one on a refusal, and `surface` sends it
   to the reviewer as `need: reserved-step merge <link>`. One still refused on a
   `diverges` call or a standing hold goes back to the manager through `needs_fix`
   and `rebrief`. One with no call goes up as `need: access <owner/repo>` when a
   repository can't be read, or as an escalated decision entry naming the path
   when a file in a readable repository can't, and neither recommends anything.
   On a worker pull request the manager lands, the call is
   recorded with `Action: none`. Any standing `align-` hold is released if the
   guard allows, and the lift message goes to the manager.
5. `diverges`: the hold goes into the director's record and the hold message
   to the manager, which takes it at `wait` as a `director-hold` event and
   records its copy in `director_hold`; the manager's land check then reports
   held, and the manager reworks through its existing rework route and names
   the hold in every report until the lift.
6. A new head: the manager's verify runs as usual; its land check still says
   held; the pull request goes up as held; the director re-reads and calls.
   The lift message reaches the manager's `wait` as a `director-hold` event,
   and `director_hold` lifts the copy at once when the lift's head equals the
   holding's `verified_head`.
7. Every director start: `alignment-read.sh --since <the latest Director
   start: entry>` reports each unreviewed merge with its pull request and
   head, each standing hold (closed ones as closed while held), each
   releasable hold, which the start lifts with `alignment-call.sh
   --lift-releasable` and whose lift message it sends, the count of refusals
   the gate recorded, and any lineage gap; the start then writes its own
   `Director start:` entry.
8. Every director report to the owner: the calls `alignment-read.sh --since
   <the latest Owner report: entry>` lists, `diverges` first, one message per
   subject, then its own `Owner report:` entry; a call the owner reverses is
   recorded as a Standing `answer` row and cited by the director's next call
   on that head.

**Where the provenance work changes this.** Three seams, each local. The
relay check's reader of recorded owner text (Standing rows with Owner the
owner and empty Relayed by, and settled decisions) becomes a reader of
Standing `rule` rows whose Source class is owner-said; the flow around it
stays. An alignment call's `standing s<n>` source would cite a row that then
carries a Source column, so a later reader can show the call's grounds with
their class; the entry's grammar doesn't change. And the `align-` hold's
Set by text is where a Source class for the hold would go if provenance
extends to holds.

**What this feature hands koto's decision record.** The standing-rule
provenance design and plan on main (shirabe#1451, shirabe#1459) give
Standing rows a Source that cites a koto decision, and their writer refuses
a citation it can't verify. They don't reach the Holds section or the
messages that place and lift a hold. This design puts no requirement on
that work or on koto's decision record; it states what it already records,
as inputs either can take (R19):

- **Who decided.** A call is an entry in the director's own session; a
  hold's Set by names the director and its address and the receiving
  manager; a director's lift names the director and its address in the
  Lifted cell, and a person's lift names the person and who relayed it; an
  owner's reversal is a Standing row whose Owner is the owner.
- **What was decided, and on what.** The call's pull request, head, value
  and entry number; the hold's name, which carries the placed-on head and
  points at its `diverges` call; the lift's head and the entry number of the
  `fits` call it rests on; the reversal's reversed entry number.
- **Authority.** None is recorded here. Recording a call or a hold grants
  nothing (R17), and the authority a deciding session held is the
  workspace's authority configuration's to give and koto's anchor to read.

If that work later records the director's lift as a decision koto keeps,
the manager's copy could cite it and `alignment-call.sh --copy` could check
the citation instead of the sender address. Until something like that
exists, the sender address is the only check (see Security Considerations).

**Where the named roles meet this.** The Run `role` row gates the land
check's call requirement and the director's start steps. The land check's
read of it is the one exception this feature makes to the named-roles rule
that no gate branches on the role: the call gate is a duty check, not an
allowance, and narrows nothing a role is allowed (Decision 2). `land-check.sh`
joins the named-roles reader allow-list test by the function that reads the
row, and the start takes its role from the record line, already on that
list. The director's
expectation list gains the alignment section; the manager's list gains the
hold duty (R8) and the rule that nothing goes to the owner but through the
director (R12). Neither list gains anything about grants, and nothing here
sets, keeps or changes a role: the gate and the start steps follow the role
as the named roles' R5, quoted above, keeps it.

## Implementation Approach

### Phase 1: The entry kind and its check

`state-entry.sh` gains the `alignment` kind, `alignment_check` and the third
`--on` mode for it, with tests for every refusal; `references/state-keys.md`
documents the grammar. Nothing reads the entries yet. Depends on nothing but
the shipped record.

Deliverables:
- `skills/coordinate/scripts/state-entry.sh`, its test
- `skills/coordinate/references/state-keys.md` (Entries)

### Phase 2: The writer, the hold and the guarded lift

`alignment-call.sh` writes calls, places `align-` holds through
`state-hold.sh`, prints the messages, runs the guarded lift, and has the
`--lift-releasable`, `--require` and `--copy` modes (`--add`, `--lift` and
`--reports-to`), the last taking the message, event number and sender as
arguments until the template's `director-hold` event lands in Phase 4.

Deliverables:
- `skills/coordinate/scripts/alignment-call.sh`, its test
- `skills/coordinate/references/state-keys.md` (Holds: the `align-` form)

### Phase 3: The reads

`alignment-sources.sh` and `alignment-read.sh`, read-only, with tests over a
planted roadmap, strategy, Standing rows and wait events whose reports carry
`unit=` and `open=` lines; neither reads a report's free text. `alignment-read.sh`
gives each open lane pull request's live head and call under its `open` key. Which wait events
carry a manager's pull request links is confirmed before Phase 2 starts, as
a short check of the template's `wait` evidence, since the read's lane set
rests on it.

Deliverables:
- `skills/coordinate/scripts/alignment-sources.sh`, its test
- `skills/coordinate/scripts/alignment-read.sh`, its test

### Phase 4: Skill text, template and the land check gate, together

The director's alignment section (the triage line stated once), the
manager's hold duty and its handling of a director's hold and lift messages
(including relaying a person's lift and the re-send of an unacknowledged
hold), the start's unreviewed list, hold listing and refusal count, the
owner funnel, owner questions and relays; the manager's `unit=` and `open=`
lines through `render-result.sh`; the `director-hold` wait event and the
`director_hold` and `align_call` states, with `director_hold`'s `rework` and
`reverify` edges and the two reads `reverify` needs; `alignment-call.sh --require`
in the directives of the three paths that skip `land`; the `Director start:` and `Owner
report:` entries; and `land-check.sh` reporting `uncalled` for a pinned head
with no standing non-`diverges` call when the Run `role` row reads
`director`, with `align_call` recording each refusal. The gate ships in the
same change as the text that tells a director to record calls, so no
director meets a gate its skill doesn't explain. Needs the named-roles role
row, so this phase can't land before the named-roles build that
shirabe#1483 plans; the compatibility digest is re-recorded.

Deliverables:
- `skills/coordinate/scripts/land-check.sh`, its test
- `skills/coordinate/scripts/coord-verdict.sh`, its table test
- `skills/coordinate/scripts/render-result.sh`, its test
- `skills/coordinate/scripts/board-record.sh`, its test
- `skills/coordinate/scripts/state-common.sh`, with `state-confirm_test.sh` covering `lib_unit`'s change
- `skills/coordinate/scripts/coordinate-template-structure_engine_test.sh`
  (the named-roles reader allow-list test)
- `skills/coordinate/SKILL.md`
- `skills/coordinate/koto-templates/coordinate.md`
- `skills/coordinate/references/loop.md`, `references/state-keys.md`

## Security Considerations

The feature adds no network surface, credential or new permission. Its
inputs are the director's own record, its own session's wait events, the
roadmap and strategy on the default branch, and GitHub's pull request state,
all of which the coordinator already reads.

- **Forged or replayed direction.** A manager takes a hold or a lift only
  from its dispatcher's channel, never from a worker, a pull request body, a
  log or a relay, and `alignment-call.sh --copy` checks it: it refuses a
  message whose `from` isn't the dispatcher address the manager's record
  names, and records the `director-hold` event the message arrived in. The
  `from` field is supplied by the agent, which copies the sender as the
  arriving message names it; the `wait` evidence has no sender of its own. So the check
  catches a wrong or stale sender (a message from a worker, or from a
  dispatcher the record no longer names), not a forgery: an agent that
  writes the dispatcher's address into `from` passes it. `--copy --reports-to`
  is the one mode that takes a `from` the row doesn't name, since a successor's
  address isn't there yet: it checks only that the message names the row's
  current address, so a message that knows that address can repoint the row, and
  holds and lifts from the new address then pass. The rewrite writes a `hold`
  entry naming the event and the old and new addresses, so it shows in the
  manager's own account, and the director's own record keeps its holds. Its lift is refused
  unless the named head equals the `verified_head` of the manager's holding, or
  the live head when no holding links it, and isn't the placed-on head, so a
  replayed lift for an older head lifts nothing. A forged message naming the dispatcher's address and the current
  verified head would still release the copy; that is the exposure the
  dispatcher-review design accepts for a reviewer's clearance, and the
  director's own record keeps the hold until its guarded lift.
- **Missing role.** A `role` row that can't be read makes the land check
  report `unready`, never skip the call requirement. A record with no `role`
  row gets no gate and runs as it does today, as a record from before the
  named roles does; no session in such a run is a director, so no call is
  owed.
- **Strict inputs.** The new scripts check every field against a fixed
  pattern before writing (the hold name, 40-hex heads, `owner/repo#n`,
  each source form, a one-line Reason), pass values as data and never
  evaluate them.
- **A pull request can't argue its own fit.** Its body, a report or a relay
  is never a plan source: a `fits` call names roadmap clauses, strategy
  passages and recorded owner decisions read from the default branch and the
  record, and the Reason cites them. Text that claims a fit is data, so an
  injected "this fits" changes no source a call can name.
- **Bounded lane set.** `alignment-read.sh` and `alignment-sources.sh` read
  only pull requests in repositories the director's scope or Holdings rows
  name; a link to any other repository in a report is listed as out of scope
  and not read.
- **A lift names its call.** The lift message names the hold and the entry
  number of the `fits` call it rests on, and the manager's `hold` entry
  records both, so a lift without a matching call is visible in the
  manager's own account.
- **Residual risks a person accepts.** Three remain by design, each with a
  stated limit, for the owner to accept or close later:
  - A forged `--copy --reports-to` message naming the row's current address,
    which repoints the manager's row, as above. Its limit is that the rewrite
    is on the manager's record with both addresses, and that it releases
    nothing in the director's own record.
  - A worker pull request merged in the delivery window between the call
    and the manager's copy. The window is bounded by the manager's next
    tick, since the copy is taken when the manager next reads its messages,
    and the record shows any merge that fell inside it afterwards.
  - A forged lift from the dispatcher's own address naming the current
    verified head. **A lift whose `from` names the dispatcher's address is
    trusted today**: the coordinate skill doesn't vet who sends a message
    under a session's address, and `from` is what the agent says the sender
    was, so the address check is the whole check. Its
    limit is that it releases only the manager's copy, and only for the
    current verified head; the director's own record keeps the hold until
    its guarded lift, as the reviewer concept already accepts for a
    clearance. Closing it takes a verifiable lift decision, one of the
    inputs described under Solution Architecture.
- **Delivery is confirmed, not assumed.** The director's own record holds
  the pull request from the call onward; the hold counts as delivered to
  the manager only once a manager report names it, and is re-sent until
  then.
- **Text from pull requests and reports is data.** The call's Reason and the
  hold message quote plan sources and the director's own words; nothing from
  a pull request body, a report or a relay is executed or followed as an
  instruction. A relay is checked against recorded text precisely because it
  is untrusted.
- **Public content.** The alignment entry isn't an outward kind, so a call
  is never posted to GitHub: its `--on` mode admits the pull request and
  checks the first line against it but has no post path, and it keeps the
  host-visibility scan, so on a public host a call can't name a private
  repository. The `align-` hold row passes the write core's
  existing checks (no private repository, no home path, no token-shaped
  string); the Set by text names roles and addresses only.
- **Fail closed.** An unreadable plan source records no call and blocks the
  merge or recommendation; an unreadable live head blocks the guarded lift,
  a copy lift with no holding and an `alignment-call.sh --require` check;
  a lost lift message leaves the manager's copy standing. Each delays a land
  rather than letting one through.
- **No authority change.** A call or a hold grants or withholds no merge,
  close or release authority; the posture read and the grant are unchanged.

## Consequences

### Positive

- Every merge or recommendation of a manager's pull request by the director
  has a call for its exact head, checked at the merge.
- A divergent pull request stops in the manager's land step with no change to
  the merge path, and a successor on either side inherits the hold with the
  record.
- The owner can list every call and every merge's review status in one read,
  and a merge past the director shows up at the next start.
- Owner questions and relays use what the record already keeps, so a
  successor sees waiting questions, their age and their lanes.
- One entry kind, no section, no grammar change: the rework when provenance
  lands touches one reader.

### Negative

- A worker pull request can merge between the director's call and the
  manager's copy of the hold; the record shows it afterwards.
- One hold is two rows; a person's lift on one must be relayed to the other.
- The reason and release live in the call entry and the manager's `hold`
  entry, not in the row, so reading a hold's reason takes a second read.
- A finished unit whose final worker pull request the manager lands before
  the director calls it is reported unreviewed at the next start; that is by
  requirement. Worker pull requests a granted manager lands short of a
  finished unit are listed as `manager-reviewed`, so the director's view of
  them is the manager's land step, not its own reading.
- A refusal is counted once per pull request and head, so the count says how
  many heads the gate stopped, not how long each stayed stopped.
- The unreviewed list depends on managers' reports naming their merges; a
  manager that omits one hides it until a lineage gap or a later report
  brings it in.

### Mitigations

- R8's per-report hold line is the manager's receipt: a report that omits a
  standing director hold gets the hold re-sent, and one that names a hold the
  director shows lifted gets the lift re-sent. A merge in the window gets a
  Reversals row in the director's record when the manager's report names it.
- The skill says a person's lift is relayed to the other record, and the
  start listing flags a hold lifted in one record and standing in the other
  when the manager's report names it.
- `alignment-read.sh` prints each hold with its call's reason, so the second
  read is the script's, not the director's.
- The named-roles expectation already makes managers name every merge in
  their lane; the director checks a report against the merges GitHub shows
  for the pull requests it already knows.
