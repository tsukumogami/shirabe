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
at which head. The requirements need every director start (a new run, a
resume, a takeover or a successor's first run) to report each lane pull
request merged since the previous start whose merged head had no call (R10),
and one read the skill names to list every call oldest first with its five
fields, and every merge or recommendation with its head's call, `after
merge`, or `unreviewed` (R11). And the director learns of its lanes' merges
only from what managers report: the named-roles design makes a manager name,
in its report after a land, every worker pull request that merged in its lane
since its last report.

The director's reading is not a second correctness review. It asks whether a
lane pull request does what its plan sources say the work is for without
contradicting any of them: the roadmap clauses and milestone Evidence of the
unit it closes or moves, the strategy, and each recorded owner decision whose
scope covers its unit or the files it changes. It doesn't re-review code,
launch correctness reviewers or repeat the worker's review round or the
manager's land step (R1). A full read is owed when the pull request marks its
unit done, reopened or dropped, is a milestone verdict pull request, changes
a roadmap or strategy document, or has a recorded owner decision among its
plan sources; anything else gets a one-line call, and the skill states that
line once (R3). A plan source the director can't read means no call, a report
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
- **An amendment to the named roles**, not yet written, under which a
  continuation keeps its role and a role changes mid-lineage only on an
  intervention from a session above it in its calling hierarchy, or from a
  person, recorded with who and when. This design relies on that rule and
  adds no such intervention.
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
order. The manager lifts its copy at its land step only when its verified
head equals the head the director's lift names. Every land check that would
merge or pass up the pull request now reads the hold from its own record.
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
reordered line and every combination the grammar rules out. The director's
land check, gated on the Run `role` row reading `director`, reads the run's
own alignment entries and reports the pull request unready, with the reason
`no-alignment-call`, when no standing call for the pinned head exists or the
standing one is `diverges`. That one check covers both a merge and a
recommendation, since the surface path that sends a pull request up runs
after it. The read is the session's own record, so the merge path still
reads nothing from outside.

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
strategy path the roadmap names, the changed files, the mechanical full-read
triggers it found, and candidate owner decisions: every Standing row and
settled decision whose On or text names the unit or a changed path. The
director keeps the candidates whose scope covers the pull request and names
each in Sources; a kept owner decision makes the read full. A source the
helper can't read makes it exit naming that source, and the director records
no call, names the source in its report and neither merges nor recommends
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
and the links in its message, which carry the manager's after-land list).
GitHub gives each one's state, merge time and merged head. A merge is
reviewed when a call for its merged head was stamped before the merge,
`after merge` when the first call for that head came later, and `unreviewed`
when none exists; a recommendation is a call whose Action is `recommend`.
With `--since`, the start uses it for R10. An earlier session of the lineage
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
message. Each lane waiting on it has its holding's Work row Next set to
`waits on decision <n>`. A matched waiting question gets the asking lane's
Work row pointed at it and nothing else: no evidence on the decision, since
evidence on an escalated entry owes the owner a withdrawal. A matched answer
is quoted back from the record. Every reply names the matched record. The
answer settles the decision, and every lane whose Work row names it is told.
Reports list each escalated decision with its age (now minus Asked) and the
lanes pointing at it; the existing re-ask rule schedules any repeat. The
relay check reads Standing rows whose Owner is the owner and whose Relayed
by is empty, and decisions the owner settled; a relay matching one is acted
on and the match named, and anything else is declined with both texts.

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
| `state-entry.sh` | changed | Adds `alignment` to the entry kinds and an `alignment_check` beside `goal_fit_check`. Not an outward kind. |
| `alignment-call.sh` | new | The director's one writer of a call: writes the entry through `state-entry.sh`; on `diverges` with no director hold standing on the pull request, adds the `align-` hold through `state-hold.sh` and prints the message to send the manager; on `fits` or `fits with follow-ups`, runs the guarded lift on any standing `align-` hold and prints the lift message. A call on a merged pull request is written (it is what `after merge` lists); only placing a hold on one is refused. |
| `alignment-call.sh --copy` | new mode | The manager's side: `--copy --add` records a director's hold as sent and `--copy --lift` lifts the manager's copy, each refused unless the message came from the dispatcher address the manager's record names; the lift is also refused unless the head it names equals the manager's verified head for the pull request and isn't the placed-on head in the hold's name. Both write a `hold` entry naming the event the message arrived in. |
| `state-hold.sh` | unchanged | Stays the only writer of the Holds section; both lifts call its `--lift`. |
| `land-check.sh` | changed | When the Run `role` row reads `director`: reports `unready <pr> <sha>` with reason `no-alignment-call` unless a standing non-`diverges` call exists for the pinned head. A role row that can't be read is `unready` too. Own record only. Nothing else in the merge path changes. |
| `alignment-sources.sh` | new | Read-only: unit, roadmap clauses and Evidence at a commit, strategy path, changed files, mechanical full-read triggers, candidate owner decisions. Exits naming any source it couldn't read. |
| `alignment-read.sh` | new | Read-only: calls, the lane pull request set, merges and recommendations with their call status, standing `align-` holds with their state (standing, closed while held, releasable), and lineage gaps. JSON out. |
| Coordinate template | changed | The director's start runs `alignment-read.sh --since` and reports its unreviewed list and holds; the manager's `wait` handling of a director's hold and lift message; the manager's land step lifts its copy only at the head the lift names. |
| `SKILL.md`, `references/state-keys.md` | changed | The director's alignment section (the triage line stated once, the call, the hold, owner questions, relays); the manager's hold duty in its reports; the entry grammar, the `align-` hold name and Lifted text. |

### Key Interfaces

**The alignment entry.** Written with `state-entry.sh --session S --kind
alignment --on owner/repo#n --text-file F`, at most 16 KiB, these seven lines
in this order with no blank line:

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
<path> at <40-hex> <section heading>`, `standing s<n>` or `decision <n>`. A
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
exits with its own code naming the hold, leaving it standing. The same check
runs in `alignment-read.sh`'s hold listing, so every start lifts what is
releasable and flags a hold whose live head has no call.

**The messages.** To the manager on a hold: the pull request, the hold row,
the reason (the call's Sources and Reason), the receiver and the release. On
a lift: the hold name and the head it was released on. The manager records
each as it arrives with `alignment-call.sh --copy --add` (the row as sent,
through `state-hold.sh`, and a `hold` entry carrying the reason, the release
and the event the message arrived in), and lifts its copy at its land step
with `alignment-call.sh --copy --lift`, which refuses unless its verified
head equals the head the lift names and isn't the placed-on head.

**`alignment-read.sh --session S [--since <stamp>]`.** Prints `{calls: [...],
merges: [...], recommendations: [...], holds: [...], gaps: [...]}`: each call
with `entry`, `stamp`, `pull_request`, `head`, `call`, `read`, `sources`,
`reason`, `evidence`, `follow_ups`, `action`, `standing`; each merge with
`pull_request`, `merged_head`, `merged_at` and `review` (`reviewed`, `after
merge` or `unreviewed`); each recommendation with its call; each `align-`
hold with its reason (from the call its name points to) and a state derived
from the row, GitHub and the entries: `lifted` when its Lifted cell is
filled; otherwise `merged while held` when the pull request merged (the
Reversals row is owed), `closed while held` when it closed unmerged,
`releasable` when the guarded lift's three conditions hold, and `standing`
otherwise, flagged `needs re-read` when the live head has no call; and each
standing hold with the latest manager report that named it, so a hold no
report has acknowledged shows as unconfirmed and is re-sent. This is the one read R11 names; the start report quotes its
`unreviewed` merges (R10).

### Data Flow

1. A manager reports a lane pull request (a `report` or `progress` event at
   the director's `wait`), or sends one it authored.
2. The director runs `alignment-sources.sh`; on an unreadable source it
   records nothing and reports which source.
3. It reads at the depth the triage line gives and runs `alignment-call.sh`.
4. `fits` or `fits with follow-ups`: on a manager-authored pull request, the
   director's land check finds the standing call for the pinned head; the
   land step merges (posture allows) or surfaces the pull request with the
   call and its own reading to its reviewer, and the grant holder above merges
   at the called head. On a worker pull request the manager lands, the call is
   recorded with `Action: none`. Any standing `align-` hold is released if the
   guard allows, and the lift message goes to the manager.
5. `diverges`: the hold goes into the director's record and the hold message
   to the manager, who records its copy; the manager's land check then reports
   held, and the manager reworks through its existing rework route and names
   the hold in every report until the lift.
6. A new head: the manager's verify runs as usual; its land check still says
   held; the pull request goes up as held; the director re-reads and calls.
7. Every director start: `alignment-read.sh --since <previous start>` reports
   each unreviewed merge with its pull request and head, each standing hold
   (closed ones as closed while held), releasable holds lifted, and any
   lineage gap.

**Where the provenance work changes this.** Three seams, each local. The
relay check's reader of recorded owner text (Standing rows with Owner the
owner and empty Relayed by, and settled decisions) becomes a reader of
Standing `rule` rows whose Source class is owner-said; the flow around it
stays. An alignment call's `standing s<n>` source would cite a row that then
carries a Source column, so a later reader can show the call's grounds with
their class; the entry's grammar doesn't change. And the `align-` hold's
Set by text is where a Source class for the hold would go if provenance
extends to holds.

**What provenance would need to cover a lift.** The standing-rule
provenance design and plan on main (shirabe#1451, shirabe#1459) give
Standing rows a Source that cites a koto decision, and their writer refuses
a citation it can't verify. They don't reach the Holds section or the
messages that place and lift a hold. To cover a lift, that work would need
three things: the director's lift recorded as a decision koto keeps, a
Source on the manager's copied hold that cites it, and `alignment-call.sh
--copy` checking that citation, so a lift is accepted because its decision
verifies rather than because of the address it came from. Until then the
sender address is the only check (see Security Considerations).

**Where the named roles meet this.** The Run `role` row gates the land
check's call requirement and the director's start steps; the director's
expectation list gains the alignment section; the manager's list gains the
hold duty (R8). Neither list gains anything about grants, and nothing here
sets, keeps or changes a role.

## Implementation Approach

### Phase 1: The entry kind and its check

`state-entry.sh` gains the `alignment` kind and `alignment_check`, with tests
for every refusal; `references/state-keys.md` documents the grammar.
Nothing reads the entries yet. Depends on nothing but the shipped record.

Deliverables:
- `skills/coordinate/scripts/state-entry.sh`, its test
- `skills/coordinate/references/state-keys.md` (Entries)

### Phase 2: The writer, the hold and the guarded lift

`alignment-call.sh` writes calls, places `align-` holds through
`state-hold.sh`, prints the messages, and runs the guarded lift.

Deliverables:
- `skills/coordinate/scripts/alignment-call.sh`, its test
- `skills/coordinate/references/state-keys.md` (Holds: the `align-` form)

### Phase 3: The reads

`alignment-sources.sh` and `alignment-read.sh`, read-only, with tests over a
planted roadmap, strategy, Standing rows and wait events. Which wait events
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
hold), the start's unreviewed list and hold listing, owner questions and
relays; and `land-check.sh` requiring a standing non-`diverges` call for the
pinned head when the Run `role` row reads `director`. The gate ships in the
same change as the text that tells a director to record calls, so no
director meets a gate its skill doesn't explain. Needs the named-roles role
row, so this phase can't land before the named-roles build that
shirabe#1483 plans; the compatibility digest is re-recorded.

Deliverables:
- `skills/coordinate/scripts/land-check.sh`, its test
- `skills/coordinate/SKILL.md`
- `skills/coordinate/koto-templates/coordinate.md`
- `skills/coordinate/references/loop.md`

## Security Considerations

The feature adds no network surface, credential or new permission. Its
inputs are the director's own record, its own session's wait events, the
roadmap and strategy on the default branch, and GitHub's pull request state,
all of which the coordinator already reads.

- **Forged or replayed direction.** A manager takes a hold or a lift only
  from its dispatcher's channel, never from a worker, a pull request body, a
  log or a relay, and `alignment-call.sh --copy` enforces it: it refuses a
  message whose sender isn't the dispatcher address the manager's record
  names, and records the event the message arrived in. Its lift is refused
  unless the named head equals the manager's verified head and isn't the
  placed-on head, so a replayed lift for an older head lifts nothing. A
  forged message from the dispatcher's own address naming the current
  verified head would still release the copy; that is the exposure the
  dispatcher-review design accepts for a reviewer's clearance, and the
  director's own record keeps the hold until its guarded lift.
- **Missing role.** A role row that can't be read makes the land check
  report `unready`, never skip the call requirement. A record with no role
  row at all is the named roles' no-role case, which that plan refuses at
  the start.
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
- **Residual risks a person accepts.** Two remain by design, each with a
  stated limit, for the owner to accept or close later:
  - A worker pull request merged in the delivery window between the call
    and the manager's copy. The window is bounded by the manager's next
    tick, since the copy is taken when the manager next reads its messages,
    and the record shows any merge that fell inside it afterwards.
  - A forged lift from the dispatcher's own address naming the current
    verified head. **A lift arriving from the dispatcher's address is
    trusted today**: the coordinate skill doesn't vet who sends a message
    under a session's address, so the address check is the whole check. Its
    limit is that it releases only the manager's copy, and only for the
    current verified head; the director's own record keeps the hold until
    its guarded lift, as the reviewer concept already accepts for a
    clearance. Closing it needs the provenance coverage described under
    Solution Architecture.
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
  is never posted to GitHub. The `align-` hold row passes the write core's
  existing checks (no private repository, no home path, no token-shaped
  string); the Set by text names roles and addresses only.
- **Fail closed.** An unreadable plan source records no call and blocks the
  merge or recommendation; an unreadable live head blocks the guarded lift;
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
- Worker pull requests the manager lands without waiting for a call are
  reported unreviewed at the next start; that is by requirement, and it will
  be the common case until directors read ready worker pull requests before
  their managers land them.
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
