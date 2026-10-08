---
schema: design/v1
status: Proposed
upstream: docs/prds/PRD-coordinate-skill.md
problem: |
  A person pauses a coordinator by sending a message to every live session
  by hand, and resumes it the same way. The coordinate skill stores a pause
  as a Standing row with its owner, who relayed it and when, but the loop
  doesn't act on one: pick still dispatches, land still merges, and the
  quiet check counts a paused worker's silence toward the failure branch. A
  scheduled resume is a timer in one session that dies with it. Separately,
  a coordinator that waits on workers asks for wakes it doesn't need: a
  watch that notifies on every expiry, re-armed seven times in one unit,
  delivered no event, and each wake re-reads the whole session.
decision: |
  A pause is a Standing row of kind `pause` with two new columns: On (`all`,
  or one unit as pick lists it) and Until (`lifted`, `time <UTC minute>`, or
  the merge policy's `merged` and `tag` conditions). One evaluator, shared by
  pick and land, reads which pauses are in force. `pick_facts` marks each
  paused unit; `dispatch_check` refuses a dispatch of one with a new verdict,
  `paused`, back to `wait`; `land` refuses a merge with the same word, to
  `surface`, where the holding's Phase is `held`; `land-merge.sh` re-reads
  before it merges; and a paused unit's request leg stays unread until the
  resume. Verification, record writes, message intake, decisions and
  teardown go on. A resume is the row ending: a
  person's word relayed through `record-state.sh --end`, or the stored
  condition read as met at the next pick, which a new `resume` wake event
  brings, with no session timer. A
  `go-ahead` on one unit lets that unit through while a wider pause stands.
  The progress table and the merge-order block say what is paused, since
  when and until what. The wait state carries the wake rule: a worker's
  message and the teardown agent's report are the wakes, one
  `koto request watch` with a two-hour bound covers every open leg, no
  30-minute expiring watch is armed, and
  each wake is counted per unit in a new Wakes column of the Work section.
rationale: |
  The Standing row is already the record's one place for an event only a
  person owns, written by one script with its owner and time, so extending
  it keeps a pause on the record a replacement reads and needs no new
  section or writer. Reading a pause at the two steps that start work and
  finish it, and again in the two scripts that act, is the shape the merge
  policy's holds already proved: a pause the loop reports is one it just
  read. A resume condition the loop evaluates on its own reads survives the
  session that set it, which a timer can't. The wake rule writes down a
  practice the performance rotation measured, and counting wakes in the
  record turns the next rotation's figure into a read rather than a
  recollection.
---

# DESIGN: coordinate-paused-state

## Status

Proposed

## Context and Problem Statement

This is Feature 9 of the coordinator roadmap: "A person pauses a coordinator, or
one lane of its work, and the loop holds dispatch and merge and says so until it
is resumed." The roadmap's block, its amendment of 2026-10-06 on wakes, and its
Coordination Dependencies section set the scope. Every claim below traces to the
roadmap, a merged pull request, a filed issue, or the process owner's
coordinator-session record (cited as the record, by date and subject, as the
merged record-container design cites it).

**Pauses are messages sent by hand.** The roadmap's block records three pauses
on 2026-09-29 and 2026-09-30, each sent by message to every live session and
each resumed the same way, once with one panel resumed while the rest of its
lane stayed paused. Since then the human paused all lanes twice more. On
2026-10-01 at 15:37 EDT: "We're nearing our usage limit for the week. I need you
to pause all lanes, and schedule a resume for 10/07 at 10am", amended at 15:40
to let each session reach a safe stop first. The process owner
relayed it to two coordinators and five workers; one worker had no socket and
got it only through its coordinator; the resume was a schedule in the process
owner's session, with the note that if the session were gone the human would
send it by hand (the record, 2026-10-01, the pause). The resume fired on
2026-10-07 at 09:58 and was relayed the same way (the record, 2026-10-07, the
resume). At 15:16 the same day the human paused again, "pause all lanes, and
continue after 7PM EDT", relayed in the same form, with another one-shot
schedule that "dies with this session" (the record, 2026-10-07, the second
pause).

**The record stores a pause, and the loop ignores it.** Feature 7 added the
Standing section: events only a person owns, each with its owner, who relayed
it and when, written only by `record-state.sh` (tsukumogami/shirabe#643). Its
design says: "What a pause does to the loop is Feature 9's paused state; this
design stores it with its who and when, and changes no routing for it"
(`docs/designs/current/DESIGN-coordinate-record-container.md`, Decision 3). A
Standing row's What is free text, so no script can tell what a pause covers or
when it ends.

**Holds already work this way for a merge.** Feature 8 made a hold a Holds row
with a condition `land-check.sh` evaluates live, `merged`, `tag` or `lifted`;
an unmet hold gives `held`, which routes to `surface`, and `land-merge.sh`
re-reads the holds before it merges
(`docs/designs/current/DESIGN-coordinate-merge-policy.md`, Decision 6). A pause
differs from a hold in what it covers (every dispatch and merge in its scope,
not one pull request) and in who owns it (always a person).

**A usage-limit stop looks like a pause nobody sent.** On 2026-10-07 at about
22:50 EDT the Feature 7 worker stopped at the account's usage limit: five eval
scenarios executed nothing, their nested sessions exiting 4 or 2, and a sixth
scored 6/7 against main's 7/7; when the human reported the reset at 23:01 the
worker was told to continue and re-run them (the record, 2026-10-07, the limit
stop). Earlier, on 2026-09-30, the limit stopped a fix worker and the process
owner's session together (the record, 2026-09-30, the usage limit).

**A waiting coordinator wakes for nothing.** The roadmap's amendment of
2026-10-06 records the performance rotation's coordinator counting its own
wakes during one unit, the work on tsukumogami/shirabe#591: twelve, of which seven were
expiries of a leg watch that caps at 30 minutes and notifies whether or not
anything happened, re-armed each time, delivering no event; two goal check-ins;
one quiet check; and two background reconcile waits that came back still
blocked (tsukumogami/shirabe#618). Each wake re-reads the cached session. The
human set a rule the coordinator adopted, and the amendment asks this design to
write it into the wait state and count wakes per unit in the record. The skill
already lists, as a known limitation, that it doesn't watch the wake koto
records when a leg resolves (koto 0.14.0, tsukumogami/koto#250).

## Decision Drivers

- **A pause is a person's event, and the record is where a replacement reads
  it.** It survives the session that set it and is written by the one writer
  of person-owned events.
- **The loop reports a pause because it just read it.** Feature 8's rule for
  holds, applied to pauses: no step says "paused" from memory.
- **A scheduled resume needs no session.** Its time lives in the record and
  the loop's own reads act on it.
- **The workflow reads, the coordinator writes.** No check reads what the
  coordinator wrote except the record on GitHub through its codec.
- **Session control is the workspace manager's.** The skill holds its own
  dispatch and merge and messages its own workers; it starts and stops no
  session.
- **The cheapest wake is the one not taken.** The human's directive of
  2026-10-01 ranks this lane's work by the cost it saves (the record,
  2026-10-01, the directive on cheaper running).
- **bash 3.2 and jq**, the skill's floor.

## Considered Options

### Decision 1: What a pause holds and how it is stored

A pause is a Standing row of kind `pause`. The Standing section gains two
columns between Kind and What:

```markdown
| Standing | Kind | On | Until | What | Owner | Relayed by | Set |
|---|---|---|---|---|---|---|---|
| s4 | pause | all | time 2026-10-07T14:00Z | all lanes, usage limit for the week | the human | the process owner | 2026-10-01T19:37Z |
| s5 | pause | Feature 9 | lifted | hold the design until the strategy entry merges | the human | | 2026-10-02T13:10Z |
| s6 | go-ahead | Feature 2 | | one panel on the open pull request | the human | the process owner | 2026-10-02T14:05Z |
```

**On** is the pause's scope: `all`, the whole coordinator, or one unit named as
pick lists units, a roadmap feature's heading tag (`Feature 2`, `ED1`) or an
issue (`#12`, `owner/repo#12`). The roadmap's block speaks of "one lane"; a run
of this skill drives one lane, its roadmap or discipline, so pausing the lane is
`all`. A lane that is itself a unit, a nested coordinator a parent dispatched,
is paused in the parent's record by its unit and in its own record as `all`.
`record-state.sh` refuses a unit pick can't read, with the forms it would take,
the same refusal `render-brief.sh` makes for a brief's unit.

**Until** is the resume condition, in the merge policy's vocabulary with one
word added:

| Until | In force while |
|---|---|
| `lifted` | the row stands; a person's resume ends it |
| `time <YYYY-MM-DDTHH:MMZ>` | the host clock, in UTC, is before that minute |
| `merged <owner/repo#n>` | that pull request isn't merged |
| `tag <owner/repo> <tag>` | that tag doesn't exist |

A condition that can't be read holds, as an unreadable hold does. A person
names a local time ("10am"); the coordinator writes it in UTC, and the entry
`record-state.sh` appends says both.

Approval and answer rows leave On and Until blank, and a go-ahead names its
unit in On with Until blank (Decision 2), so the codec allows a blank On and
Until for those kinds and requires both for a pause. The codec, not only the
writer, checks On's form and Until's grammar, since a hand-edited body is read
through it too, and both cells get the text checks every Standing text cell
gets on a public host. The Standing and Work sections shipped in no release
yet (no tag contains tsukumogami/shirabe#643), so their tables change form
with no compatibility read.

**What a pause holds:** every step that starts a worker on work or lands what
it pushed. Concretely, in its scope:

- **dispatch**: a new dispatch, a scoping-ahead dispatch, sending a scoped
  unit its execution, and a re-dispatch after a failure, all of which pass
  `dispatch_check`;
- **merge**: the land step, and the merge script it hands to;
- **a leg's result**: a leg-bound worker's result stays unread in koto until
  the resume, so nothing consumes it while its follow-on can't happen.

A re-brief is still sent, since it only puts the fix on record, and its message
says the fix starts at the resume; the pause line already told the worker to do
nothing until then. A replaced leg can't arise for a paused unit, because a
spent leg is found only by reading it.

**What goes on:** reading CI and verifying a head, since a read starts no work;
every record write; report intake, classification and decisions, including an
escalation to a person; teardown of a worker whose pull request has merged,
which only removes cost; and the progress report. Reading CI and verifying go on for a message-path
worker's report; a leg-bound worker's report is its leg, held as above. A pause
is the loop's
posture, not a stop: the coordinator still answers its workers and its
dispatcher.

**Where it is read.** One evaluator, `pause-lib.sh` (sourced, like
`board-lib.sh`), takes the record's parsed Standing rows and a unit, and says
which pauses are in force for it and why. It evaluates `merged` and `tag` with
the same reads `bl_holds_eval` makes, refactored into one condition reader
both call. These places use it:

1. `pick-facts.sh` puts the in-force pauses in `coord/pick.json`, with each
   row's state (`in-force`, `met`, `unreadable`), and marks every unit and
   holding the pause covers with the row's id (`paused: "s4"`). Pick's rule:
   a paused unit is never chosen; while `all` is in force, `hold`. Pick's
   marking is what the coordinator chooses by, and the dispatch check's refusal
   below is what stops a choice that ignores it; both are kept.
2. `deferral-check.sh`, the `dispatch_check` action, refuses a pick or
   re-dispatch whose unit a pause covers: `paused <id>`, routed to `wait`,
   with the row in `coord/dispatch_check.json`. It comes after
   `unknown-topic`, `unresolved-topic` and `record-changed`, which say the
   check can't name the unit or read the record, and before every other
   verdict, so a paused unit isn't sent to dispose of deferrals or settle
   decisions for a dispatch that can't happen. `record-changed` means the
   record is gone, closed or no longer canonical, never that a row changed,
   so the `--end` written just before a resume doesn't trip it.
3. `land-check.sh`, right after the head re-read and the merge state, before
   the panel evidence, the body checks and the holds, refuses a pull request
   whose unit a pause covers: `paused <pr> <sha>`, routed to `surface`, with
   the rows in `coord/land.json`. Reading it first means a paused pull request
   that is also unready isn't asked for a fix before its merge could happen
   anyway. The surface directive writes
   Phase `held`, the existing word for a ready pull request waiting on
   something other than the merge, and `record-confirm.sh` requires it, as it
   does after `held`.
4. `land-merge.sh` re-reads the pauses just before it merges, as it already
   re-reads the holds, so a pause written after the land check still stops
   the merge, which can't be undone. A dispatch isn't re-read the same way:
   `dispatch_check` runs one step before the launch, and a launch can be
   stopped afterwards by a message.
5. `wait-target.sh`, the `leg_pick` action, passes over a resolved leg whose
   holding a pause covers, leaving it untaken, and says so in its detail; a
   `leg` tick after the resume offers it.

`quiet-check.sh` treats a holding a pause covers as not silent: its worker was
told to stop at a safe point, so its silence is what the pause asked for, and a
sweep that skips it is not a silent check. The resume doesn't reset the
worker's last activity: the first sweep after a long pause finds it silent and
sends one status message, which is what a resumed coordinator needs to ask
anyway, and only a second silence after that message goes to the failure
branch.

A close-out (`roadmap_close`, `rotation_close`, `predecessor_close`) lands the
record, not a unit's work, so a pause doesn't hold it.

#### Alternatives considered

- **A Pauses section of its own.** A second place for a person's event, with a
  second writer. Rejected: Feature 7 made Standing that place.
- **Scope and condition encoded in What.** No codec change, but a grammar
  inside a free-text cell that every reader must parse and every writer can
  break. Rejected.
- **A pause as a hold on every pull request.** Holds name one pull request and
  are read only at land; a pause must also stop dispatch, and covers units
  that have no pull request yet. Rejected.
- **A separate gate on each step.** A second reader of the same facts beside
  each check's own verdict, which the merge policy declined for holds for the
  same reason. Rejected.

### Decision 2: Resume

A pause ends when its row ends. There are two ways:

- **A person's resume.** The coordinator writes it with `record-state.sh
  --end <id> --by "<the person>"`, the relay duty Feature 7 set: a resume said
  in a comment on the record, or relayed by another session, reaches the loop
  only through this call. `--end` already exists and appends the entry.
- **The stored condition met.** At every pick `pick-facts.sh` evaluates each
  pause; a `time` that has passed, a pull request merged, a tag that exists,
  reads `met`, and a met pause covers nothing. The pick directive then has the
  coordinator end the row, `--end <id> --by "its condition, <until>"`, and send
  the resume line. Nothing waits on that write: the loop is already released
  by the read.

Both need a pick to run. A paused loop with nothing in flight sits at `wait`,
and no existing spoke from `wait` returns to `pick_facts` without a record
change, so `wait` gains an event, `resume`, with an edge straight to
`pick_facts`. The coordinator ticks it after writing a person's resume, when
its wait for a pause's minute returns, and on any wake while a pause stands
whose condition it has reason to think met (the merge or tag a pause names
arriving as a notification).

**Whole or by lane.** Ending an `all` row resumes the whole coordinator; ending
a unit's row resumes that unit and nothing else. While `all` is in force, a
person who lets one unit through, the 2026-09-30 case of one panel resumed
inside a paused lane, is written as a `go-ahead` row on that unit: the
evaluator reads go-ahead rows first, and a unit with a standing go-ahead is
covered by no pause, `all` or its own.
Feature 7 defined a go-ahead as "a release or another step a person allowed
once", ended when used; the coordinator ends it after the step it allowed, the
land or the dispatch.

**A scheduled resume survives the session.** It is a `time` condition in the
record. No timer holds it: the first pick after its minute reads it met, in
this session or in a replacement started from the record alone, whose start
always runs a pick. In a running session, what brings that pick is a
`resume` tick. The coordinator runs one silent background wait until the
minute, which prints one line when the minute arrives and nothing before, and
ticks `resume` on it. That wait is session-local and dies with the session,
but it is never the store: a session that dies leaves the time in the record,
and its replacement's first pick reads it.

**Reports that arrive while paused** are never refused. A message is taken,
recorded and classified as usual, and what it leads to is held: a ready pull
request goes through verify to `land`, which reads the pause and surfaces it as
held with the pause named; a fix round is re-briefed with a message saying it
starts at the resume; a blocker goes to the person as a need, as it would
unpaused. A leg-bound worker's result stays in its leg, unread.

**What the resume re-enters.** Each held thing goes back through a route the
template already has, so the resume adds no new edge but `resume` itself:

- a leg-bound worker's result: the coordinator ticks `leg` after the resume,
  and `leg_pick` now offers the leg it passed over;
- a message-path worker whose pull request the pause held at `land`: the resume
  line asks it to send its ready report again, which comes back through
  `wait` to `take_report`, `classify_report`, `verify` and `land`, the way a
  report is brought back after a board that was still pending;
- a re-brief already sent: the resume line tells the worker to start it;
- a dispatch the pause held: the pick that `resume` brings chooses it.

The resume line goes to every live worker in the pause's scope, and each
holding's Work row is rewritten with what it resumes to.

#### Alternatives considered

- **A `--resume <scope>` flag.** A second way to end a row, by scope instead
  of id. `--end` already ends one row with its who and the entry, and the
  progress table names each pause's id. Rejected as surface with no new
  behavior.
- **An exception list on the `all` row.** One row whose cell grows a list of
  units let through. A go-ahead row already means exactly that, with its own
  owner and time. Rejected.
- **The loop ends a met pause by itself.** A check would write the record,
  which the template's rule forbids. Rejected: the read releases the loop, and
  the coordinator's write is the account.

### Decision 3: Delivery to sessions

Carrying a pause to the sessions a coordinator drives is the workspace
manager's, by the roadmap's Coordination Dependencies: it owns session control.
What the loop asks of it is one thing: deliver one notice to every live session
a given session dispatched, and to named instances, and say per session whether
it was delivered, not reachable, or gone, so a session with no socket is
reported rather than missed. niwa's dispatch lineage already records the parent
session of every worker it launches. Queuing the notice for a stopped session
until the daemon resumes it is the useful second half. Stopping or resuming
sessions on a pause stays out of this: it is the person's separate call, and
the roadmap puts session control out of this feature. The roadmap notes no
niwa issue was filed for it and asks this design to file one; the issue goes
to niwa with this design's ask, and the implementation's first pull request
cites its number.

What the loop does without it, which is what the record shows coordinators
doing by hand: after writing a pause, the coordinator messages each live worker
the pause line (push what you have at a safe point, report, then do nothing
until the resume: no panels, evals or messages), and writes each holding's Work
row with the next step `paused by <id>; idle until the resume`. A worker the
message doesn't reach is reported up as unreachable. On the resume it messages
each worker the resume line and writes the next step it is resuming to. The
Work rows are how a replacement knows who was told what. No worker is
dispatched into a pause's scope, so no brief needs to carry one.

#### Alternatives considered

- **The skill delivers through its own scripts.** The roadmap names this the
  workspace manager's and asks the design to consume it rather than rebuild it
  as skill scripts. Rejected.
- **Recording each worker told of the pause as a Run `told` row.** `told`
  means told the coordinator's address and is cleared when the address
  changes. Rejected: the Work row's next step already carries it per holding.

### Decision 4: Quiet waiting

The wait state's directive gets the human's rule from the roadmap's amendment,
with one narrowing:

- **The wakes are a worker's message and the teardown agent's report.** A
  checkpoint report, a ready report, a question, a blocker: each is a message,
  and each is ticked as its event.
- **One wait covers every open leg.** While any leg-bound worker's leg is
  open, the coordinator keeps one background `koto request watch --session
  <this session> --timeout-secs 7200 [--since <cursor>]`. It blocks until the
  session's wake file changes, which koto does when a leg the session waits
  on resolves, or until the bound passes, and prints `woke` (true or false)
  and a cursor. `woke: true` ticks `leg`, and `leg_pick` finds which leg; a
  wake means only "look again", so `leg_pick` finding none open returns to
  `wait`. `woke: false` is the bound, and ticks `quiet`. The coordinator
  passes the last cursor it printed as `--since` to the next watch, holding
  it in its own turn, not in the record or a file; a lost cursor costs at
  most one late read, since `leg_pick` reads every leg. A message-path worker
  needs no wait: its message is the wake.
- **A pause's resume minute.** While a `time` pause stands, one silent wait
  until its minute, which prints one line only when the minute arrives and
  ticks `resume` (Decision 2).
- **No 30-minute expiring watch.** No watch with a short cap that notifies on
  expiry, no polling loop, no goal check-in. A keep-alive is set only when the
  person asks for one. The leg watch's bound does notify on expiry, which the
  rule's wording would forbid; it is kept because a watch with no deadline is
  a hang koto refuses, and at two hours it wakes a session with open legs and
  nothing arriving at most once per two hours, where the measured 30-minute
  watch could wake it four times, and each such wake does the quiet check
  that is due by then anyway.
- **The quiet check** runs on the first wake after a worker has been silent
  for the skill's 30 minutes, as it does today; no timer is armed to make that
  wake happen. A two-hour silence with nothing else due is caught by the leg
  wait's bound, or by the next message from anyone.

The narrowing: the rule allows a wait per worker whose condition is a leg
resolved or a pull request ready. A message-path worker's ready pull request
arrives as its ready report, a wake already, so a wait on the same readiness
would wake the session a second time for one event. The design declines the
pull-request wait and keeps one leg wait for the whole session, since
`koto request watch` reports every leg this session waits on. The skill's known
limitation, that it doesn't watch the leg wake, is closed by the same line.

**Counting wakes.** A wake is a tick of `wait` the coordinator didn't start on
its own: events `report`, `progress`, `leg`, `quiet`, `merged` and `resume`.
Each is attributed from the log, never from a unit the coordinator would have
to guess: `report`, `progress` and `merged` by their evidence's unit; `leg` by
the topic `wait-target.sh` wrote for the leg it read; `quiet` against each
topic the sweep's QUIET capture named silent, or the run alone when it named
none; `resume` against the run. The Work section gains a Wakes column: on
every write of a holding's Work row, `record-state.sh` adds to the row's count
the wakes this run's log attributes to the holding's worker after the end of
the minute in the row's Updated cell, and when a holding's row leaves Work (the
holding torn down) it appends an entry with the unit's final count. The
rotation's handoff carries Work as it stands, so a unit still in flight at a
rotation's end has its figure there, and the next rotation reads the figures
and sums the entries rather than recalling them. With that cutoff the count is
a floor, never more than happened: wakes logged inside the minute after a
write, and wakes a crashed run logged after its last write, aren't counted,
since Updated is to the minute and a crashed run's log isn't read again.

#### A usage-limit stop

A usage-limit stop is not a pause. A pause is a person's, and exists only
as a Standing row. A limit stop is the host's: nobody writes it and nobody
resumes it; the account's reset does. So the loop never writes a pause for one.
It shows as a worker's runs executing nothing (nested sessions exiting without
running, as on 2026-10-07), as silence, or as the coordinator's own session
stopping. The coordinator writes one entry saying what it saw, with
`record-append.sh`, so the account explains the gap. The coordinator learns of
the reset from its own session running again, a person saying so, or a
worker's next message. On the reset it messages
each live worker to continue from its last checkpoint and re-run whatever
executed nothing. The brief template gains one line for workers: a run the
limit cut short (nested sessions that executed nothing) is not a result, is
re-run after the reset, and is never reported as a score. Silence across the stop is counted by the quiet check like any
other, so the first sweep after it sends each quiet worker its status message;
a second silence after that still goes to the failure branch, because by then
the worker had a message and the limit had reset.

#### Alternatives considered

- **A wake event of its own** (`idle`) for a wake that brought nothing. A
  bound that passed is a silence, which `quiet` already means. Rejected.
- **A record write per wake.** One body write and one comment per wake costs
  more than the wake it counts and notifies every watcher of the record.
  Rejected.
- **Counts only in an entry at teardown.** Simpler, but a unit still in flight
  when a rotation ends or a run crashes has no figure, and a successor would
  parse prose to sum them. Rejected as the only form; the final entry per unit
  is kept as the account.
- **A wait per message-path worker on its pull request's readiness.** Declined
  above.

### Decision 5: Reporting

`progress-view.sh` reads the pauses from the pick facts. When any is in force,
one line goes above the table, `Paused: s4, all, since 2026-10-01 19:37 UTC,
until 2026-10-07 14:00 UTC (the human, relayed by the process owner)`, one
clause per pause. A holding a pause covers reads `paused (s4)` in its Status
cell, and a queued unit's Next cell reads `held by pause s4`. The table keeps
its six columns and four kinds; the line is outside it, so the display rule
holds. A met pause the coordinator hasn't ended yet is listed as `met, to end`.

`merge-order-entry.sh`, the block under the merge-order table that a person
reads for each ready pull request, prints the pauses `land-check.sh` read with
their states, beside the holds. That block is the skill's ready report for a
pull request handed to a person.

The reconcile report is unchanged: a restarted coordinator reports what it
reconciled, then its first pick reads the pause and its first progress table
says so.

## Decision Outcome

A pause is a Standing row with a scope and a resume condition. The loop reads it
at pick and at land, and again in the two scripts that act, and refuses with
the pause named. Verification, intake, decisions and teardown go on. A resume is
the row ending, by a person's word or by its condition read as met at the next
pick, so a scheduled resume needs no session. The coordinator messages its own
workers until the workspace manager can deliver a pause to them. The wait state
asks only for the wakes that carry an event, and counts them per unit in the
record.

What the roadmap's block asks for that this declines:

- **Delivering the pause to sessions.** The workspace manager's, by the
  roadmap's own Coordination Dependencies; the design states the ask and what
  the coordinator does meanwhile.
- **A wait on a pull request becoming ready** for a worker that reports by
  message. Its report is the wake already (Decision 4).
- **Caps and the parked-worker count.** The roadmap's Feature 9 evidence paragraph calls
  a cap the loop's posture too, and names the ruling that parked workers count,
  which the cap can't express (tsukumogami/shirabe#501). A cap is already a Run
  row a person sets (Feature 7); counting parked workers is #501's, not a
  pause.
- **Stopping workers' sessions at a pause.** Session control, out of this
  feature.

## Solution Architecture

### The template

```
dispatch_check --paused--> wait
land           --paused--> surface        (Phase held, confirmed at record)
leg_pick       passes over a paused unit's leg, leaving it untaken
wait           --resume--> pick_facts
wait: the wake rule in its directive
```

One verdict word, `paused`, code 48, routed by `dispatch_check` and `land`. The
`pick` decider's input gains the pauses through `coord/pick.json`, so its
fixtures gain a paused case.

### Files

| File | Change | Pull request |
|---|---|---|
| `skills/coordinate/scripts/record-codec.jq`, `references/record-template.md` | Standing's On and Until, their checks | 1 |
| `skills/coordinate/scripts/record-state.sh` | `--standing pause` and `go-ahead` take `--on` and `--until`; the unit and condition checks | 1 |
| `skills/coordinate/scripts/pause-lib.sh` | new: which pauses cover a unit, and each one's state | 1 |
| `skills/coordinate/scripts/board-lib.sh` | the condition reader shared by holds and pauses | 1 |
| `skills/coordinate/scripts/pick-facts.sh`, `deferral-check.sh`, `land-check.sh`, `land-merge.sh`, `wait-target.sh`, `quiet-check.sh`, `record-confirm.sh` | read the pauses and act on them | 1 |
| `skills/coordinate/scripts/coord-verdict.sh`, `coord-verdict-table_test.sh` | `paused` | 1 |
| `skills/coordinate/scripts/progress-view.sh`, `merge-order-entry.sh` | report the pauses | 1 |
| `skills/coordinate/koto-templates/coordinate.md`, `coordinate.mermaid.md`, `coordinate.pick.choice.decider.jsonl`, `scripts/decider-declarations.tsv`, `references/loop.md`, `SKILL.md` | the arms, the `resume` event, the pause and resume directives | 1 |
| `skills/coordinate/scripts/record-codec.jq`, `record-state.sh`, `references/record-template.md` | Work's Wakes column and its count from the log; the final entry | 2 |
| `skills/coordinate/koto-templates/coordinate.md`, `SKILL.md` | the wake rule in `wait`; the leg watch; the limit stop; the known limitation closed | 2 |
| `skills/coordinate/references/brief-template.md` | a run the limit cut short is not a result | 2 |
| tests and evals | `pause-lib_test.sh`; codec, state, pick, dispatch check, land, merge, quiet, progress, handoff and structure cases; `pause_engine_test.sh`; eval scenarios for each changed state | 1 and 2 |

## Implementation Approach

Two pull requests after this design, the first landing before the second opens.
Each changes the template and runs the evals for every scenario reaching a
changed state.

1. **The paused state.** Decisions 1, 2, 3 and 5. The engine test,
   `pause_engine_test.sh`, drives a fixture loop through real koto with two
   holdings, one with a verified pull request: a pause on one unit makes
   `dispatch_check` refuse that unit's dispatch and `land` refuse its pull
   request with `paused` and the row's id, while the other unit dispatches;
   ending that row releases it and only it; a pause on `all` refuses both
   units; a `time` pause whose minute has passed releases both at the next
   pick a `resume` tick brings, with no timer; a leg-bound holding's resolved
   leg is passed over while paused and read by the first `leg` tick after the
   resume; the pull request held at `land` reaches `land` again from its
   re-sent report after the resume and is refused no longer; and a replacement
   session started on the record alone, with a pause standing, reaches pick
   and finds it in force. Unit tests cover the evaluator's conditions, the
   go-ahead, the codec's checks, and the rendering.
2. **Quiet waiting.** Decision 4. The Wakes column and its count, the final
   entry, the wait directive, the brief template's line. A test feeds a session
   log with wakes before, inside and after the minute of a Work write and
   checks the count, the floor at that minute, and the entry; an eval checks the wait directive arms no expiring timer.

## Security Considerations

A pause can only stop the loop's own steps; it widens nothing. Its cells go
through the codec like every Standing cell, so on a public host they get the
same checks for private names, paths and tokens. A pause is written only by the
coordinator from a person's word, the trust a `lifted` hold already rests on,
and its owner and relayer are on the record. A forged comment can't pause or
resume anything: the reader counts no comment without the entry marker, and
only `record-state.sh` writes the row. The `merged` and `tag` conditions read
GitHub with the same calls holds make.

## Consequences

### Positive

- A pause stops dispatch and merge in its scope and says so, from a read.
- A scheduled resume is acted on by any wake after its time, in any session
  started from the record.
- A replacement finds the pause standing and the next step each worker was
  told.
- A waiting coordinator takes a wake only when something arrived, and the next
  rotation reads its wake count from the record.

### Negative

- A `merged` or `tag` pause on a unit nothing else is happening on is read at
  the next wake of any kind, since its event may arrive as no notification
  the coordinator receives.
- Until the workspace manager delivers pauses, the coordinator still messages
  each worker, and a worker with no socket still needs someone else to reach
  it.
- A scheduled resume in a running session rests on a session-local wait; if
  that wait is lost and nothing else arrives, the resume waits for the next
  wake or restart.

### Mitigations

- The coordinator ticks `resume` whenever a notification names the pull
  request or tag a pause waits on, and the progress table lists every pause
  with its condition, so a person can see what it waits on.
- The Work rows record who was told; an unreachable worker is reported up.
- The one silent wait until the resume's minute brings the `resume` tick, and
  a person's message is always a wake.
