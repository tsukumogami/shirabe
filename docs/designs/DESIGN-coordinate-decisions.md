---
schema: design/v1
status: Proposed
problem: |
  `/coordinate` has no structure for decisions. A worker's question passes to the human as it
  stands, evidence after a decision goes back to the human as a bare "decide", the progress
  table's "Blocked on you" cell is free text a coordinator can fill with "decide whether to
  ship", and nothing about an open decision survives a restart. The template's only route
  for a blocked worker (`classify_report` to `surface` to `wait`) writes nothing and checks
  nothing.
decision: |
  Decisions become a fifth record section, `Decisions`, rendered only when it holds entries
  or an identifier high-water mark, so every existing record stays canonical. One write
  script, `record-decision.sh`, is the only thing that changes that section; it is bound to
  the workflow state it runs in and the entry the workflow routed, and refuses every
  transition the four-state machine doesn't allow and every verdict missing a part. A check
  state, `decision_next`, reads the record and the session log and routes to the one next
  thing owed: a write that didn't land, a message to render and send, a proposed entry to
  take up, or a verdict to make. Every message to the dispatcher or a worker is rendered by
  the workflow from the entry, in a check state, and marked sent only against that render.
  `dispatch_check` refuses to dispatch while anything is owed. Worker questions are caught
  where every report enters the coordinator, by a check that extracts them from the report's
  Questions part and question-shaped lines and opens an entry for each. The run's escalation
  target is fixed at open with `--reports-to`. The progress table takes decision rows from
  the record and refuses free-text needs that match a closed list of decision phrasings.
rationale: |
  The record is the one store a successor reads, has compare-and-swap writes and provenance
  checks, and already holds what GitHub can't recompute; a new section costs a codec change
  the omit-when-empty rule keeps backward compatible, where overloading Deferrals would block
  every dispatch behind a pending question. The coordinator's report intake is the one point
  every worker report crosses, by message or by leg, from any host; the worker skills have no
  step that sends a report, so a check there would never see the question. A single routing
  read over the record and the log gives restart take-over, one-at-a-time release, send-once
  and lost-write recovery from the same facts, and a guard at the dispatch point makes
  take-over hold on every path to a dispatch rather than on the paths someone remembered.
upstream: docs/prds/PRD-coordinate-decisions.md
---

# DESIGN: Decisions and escalation in the coordinate skill

## Status

Proposed

## Context and Problem Statement

The coordinate skill runs a coordinator as a koto workflow whose one rule is that the
workflow reads and the coordinator writes, and nothing the coordinator writes is read by a
check. Its record is a GitHub issue (roadmap scope) or a draft pull request (a discipline's
rotation) holding four tables, Holdings, Deferrals, Side effects in flight and Reversals,
rendered and parsed by one codec (`scripts/record-codec.jq`) so that a body is canonical only
when rendering its parse reproduces it byte for byte. Every change to it goes through a
write script that re-reads GitHub, compares the `Written:` line and refuses after any
directed transition.

Decisions have no place in any of that. On main today a worker's report is classified
`blocked` and goes to `surface`, whose `blocker` answer returns to `wait` with nothing
recorded and nothing confirmed; `failure: escalate` does the same. The progress table's
"Blocked on you" rows come only from `--blocked <session>=<need>` text the coordinator types.
The escalation shape (options, recommendation, "until you answer") lives in
`references/loop.md` as prose. The two sibling features on their way in don't change this:
the dispatch path (shirabe#404) adds `take_report`, which admits a report by message or by
leg into the context key `worker_report`, and five more routes into `surface`, all leaving as
`blocker`; reconcile (shirabe#406) builds "Blocked on you" rows for closed pull requests and
unconfirmed merges and knows nothing about a question.

tsukumogami/niwa#330 walked through every gap. A worker recorded a `/decision` choosing
option (d), with a named assumption left untested and a stated condition that would flip
the choice to option (c). A person ran the check, which needed an authenticated session, and
got a mixed result: the shared marketplace clone moved, the installed per-project versions
held. The flip condition had not happened, and the record's consequences had already accepted
the clone moving. The worker handed the result to the human as "decide", and the coordinator
listed "decide whether to ship" with no recommendation. The right verdict, which the
coordinator had the authority and the criteria to make, was to keep (d), confirm the record,
and ship.

What this design has to make true, carried from the PRD:

- A decision entry per decision, holding its question, options, source, state, verdict,
  evidence, outcome and the messages it owes, in the store a successor reads (PRD R1),
  with a stable identifier never reused in the scope. A record written before this feature
  must still be adopted, and one with a malformed entry refused (R5).
- Four states, `proposed`, `coordinator-verdict`, `escalated`, `settled`, with five
  transitions and no others, each other transition refused with the stored entry unchanged
  (R2). A verdict carries its reasons: an outcome and reason to settle; to escalate, a
  recommendation from the options, its reason, a context and a problem statement, and at
  least one of three grounds (the decision changes the effort's scope; it reverses or extends
  a decision the dispatcher supplied; it is a choice whose options need a step the workspace
  reserves for a person), a field counting as empty after trimming (R3). Evidence in any
  state is appended and moves the entry to `coordinator-verdict`, never to `escalated` (R4).
- A successor takes every unsettled entry over before its first dispatch; an `escalated`
  entry whose message was sent isn't sent again, and one whose message never went out is
  sent once. A rotation's handoff carries unsettled entries, and a roadmap record can't close
  with one (R6).
- The escalation message is rendered by the workflow, one decision, context paragraph, then
  problem paragraph, then the question with the recommended option first and its reason;
  refused for an empty field, a recommendation outside the options, or a second rendering of
  the same verdict (R7). At most one entry is escalated at a time, the rest waiting with their
  verdicts recorded, oldest first; a withdrawn entry escalates again only with a new verdict
  (R8). Evidence on an escalated entry renders a withdrawal, and an answer that arrives after
  it is evidence (R9).
- The progress table shows a decision only from an escalated entry, with its question,
  recommendation and reason, refuses one without them, refuses free-text needs matching a
  closed phrasing list, and shows an entry with a coordinator, or waiting on this
  coordinator's verdict, as with that coordinator (R10). An answer naming the entry settles it
  with the outcome and who decided, and one that reverses a supplied decision is also a
  reversal (R11).
- The escalation target is fixed for the run, a person by default or a named coordinator
  (R12). An escalation from below is a `proposed` entry at the receiver with its source, and
  its settlement is rendered back down so the lower entry settles naming the final decider
  (R13). An entry whose source is a worker renders its outcome to the worker (R14).
- A worker's questions are the numbered items of a fixed Questions part plus every other line
  that ends in a question mark or matches the phrasing list (R15). Each becomes a `proposed`
  entry, or evidence on an entry it cites by identifier; nothing in a report reaches the
  dispatcher except through an entry's verdict (R16). A question addressed to a person is
  refused as addressed and re-routed, with a reply to the worker, by a check at a point every
  report passes (R17). Every brief carries a fixed sentence stating the channel (R18).
- Deciders never act (R19); the template is the source of truth and the skill file names only
  its states and checks (R20); tsukumogami/koto#261 is named, and implementation starts from
  a main holding the dispatch path and reconcile (R21). Every check has a passing and a
  failing test (R22), and a replay of niwa#330 records the verdict before any escalation and
  fails against a template that routes evidence straight to escalation (R23).

## Decision Drivers

1. **The record's own rules.** It stores only what GitHub can't recompute; every write is a
   compare-and-swap through a script; its body is canonical or it isn't adopted. A decision's
   verdict, its evidence and the messages it owes are all things only the coordinator knows.
2. **Checks read what the coordinator didn't write.** A check reads GitHub, the session log,
   or a capture the engine wrote. A context key the coordinator can set with
   `koto context add` is never trusted by a gate.
3. **Backward compatibility of live records.** Records are open issues today. Anything that
   makes their bodies non-canonical sends every running coordinator to `record_conflict`.
4. **A check the worker can't route around.** A worker report arrives by message or by leg,
   from this host or another. The check has to sit where all of those pass.
5. **Nesting without special cases.** A roadmap coordinator under a workspace coordinator is
   one coordinator reporting to another; the same code path serves a person and a
   coordinator.
6. **Restart is the normal case.** Every start is a new run that reconciles; whatever the
   decision flow needs after a crash must come from the record, GitHub and the log.
7. **Existing seams.** The dispatch path's `take_report` and `worker_report`, the seal and
   log readers in `coord-log.sh`, `lib_emit` detail keys, the verdict table in
   `coord-verdict.sh`, and the deferral guard in `dispatch_check` are the extension points.
8. **Untrusted text reaches a public record.** Worker reports are free text from sessions
   the coordinator doesn't control, and the record is often a public issue.

## Considered Options

### Decision 1: Where decision entries live

A successor must find every open decision on start, and GitHub can't tell it one exists: a
decision's question, verdict and evidence sit in no pull request or issue. The record is the
store a successor reads, but its shape is fixed: four sections, checked byte for byte by the
codec, with `record-find.sh`'s canonical check, the handoff format, the close-out reads and
the rule-coverage fixture all built on it. The question is what changing that shape costs and
what the alternatives cost instead.

#### Chosen: a fifth record section, `Decisions`, rendered only when it has something to hold

The codec gains a fifth section after Reversals. It opens with a line, `Next decision: <n>`,
the identifier the next new entry takes, followed by the table (or `None.`):

| Column | Holds |
|---|---|
| Decision | the identifier, a positive integer below `Next decision` |
| Round | how many times the entry has been escalated; messages and answers name it |
| Question | the question as the coordinator worded it, one line |
| Options | the options, one per line |
| State | `proposed`, `coordinator-verdict`, `escalated` or `settled` |
| Source | `worker <topic> [report <seq>.<i>]`, `coordinator <topic> #<n> round <r> [report <seq>]`, `dispatcher [raise <seq>]` for a decision the dispatcher handed over, or `self [raise <seq>]` |
| Verdict | blank, `settle` or `escalate`; an escalate verdict on a `coordinator-verdict` entry is a queued escalation |
| Recommendation | one of the options |
| Reason | the recommendation's reason |
| Context | what is being decided and why it matters now |
| Problem | what is unresolved and why the coordinator can't settle it |
| Grounds | one or more of `scope`, `supplied-decision`, `reserved-step` |
| Target | `a person` or `coordinator <topic>` |
| Owed | blank, `escalation`, `withdrawal` or `reply` |
| Sent | when the last owed message was marked sent |
| Evidence | append-only lines, `<time> <source> [<visit stamp>]: <text>` |
| Outcome | the outcome and its reason, once settled |
| Decided by | who settled it |
| Updated | the time of the last change |

The section is rendered only when it has an entry or `Next decision` is above 1, and the
parser accepts four sections or five, taking the fifth only when its title is `Decisions`.
A record written before this feature has no such section, parses to no entries and a next
identifier of 1, and renders back to the same bytes, so every live record stays canonical and
`record-find.sh` adopts it unchanged. A malformed entry (an unknown state, an identifier that
isn't an integer, repeats, or isn't below `Next decision`, a required column empty for its
state, a grounds value outside the three) is refused by the codec, which makes the record
non-canonical. Which columns an entry needs depends on its state (an escalated entry needs
recommendation, reason, context, problem, grounds and target; a settled one needs outcome and
decided by), so that is a row-level check, and the cell grammars are looked up by section as
well as column: the Decisions `reason` and `target` columns and the column named `state` don't
inherit or collide with the existing columns of those names or with the list of names the
codec refuses as GitHub-recomputable, which gains a section exemption.

The handoff renders the section with only the unsettled entries and the same
`Next decision`, so a new rotation's record continues the numbering; a predecessor copy
copies the section as it stands. Settled entries stay in a roadmap record until its close,
and leave a rotation's record at its end.

What this costs: the codec's section list, its parse and handoff split, section-aware cell
checks, the record template reference, `closeout-read.sh`, the predecessor copy, the
`dispatch_check` wording about four sections, and new rule-coverage rows. The omit-when-empty
rule is what keeps it from also costing a migration.

#### Alternatives Considered

**Decisions as rows in Deferrals, with a decision kind.** A deferral is "something the
coordinator chose not to act on now that someone must act on later", which a pending
decision resembles. Rejected because the Deferrals columns and their grammar (a Disposition
of `filed #n`, `closed: <reason>` or `carried <time>: <reason>`) would have to widen to hold a
recommendation, context, problem, grounds and evidence, which reopens the codec as much as a
new section does (driver 3 is no better served), and because `deferral-check.sh` refuses
every dispatch while a deferral raised before the run's start is undisposed, so a decision
escalated to a person and still unanswered after a restart would stop all dispatch. Carrying
it forward to get past the check would make "carried" mean two things.

**Decisions as rows in Side effects in flight.** That section is already "things in
progress whose outcome is still owed", which is also true of an escalated decision, and it
drops rows once confirmed. Rejected because its rows are confirmed by a GitHub read (the
merge landed, the issue closed), and a decision is settled by a verdict or an answer that no
read can observe; its columns (action, target, verified head, attempted, how to confirm)
describe a write, and every decision field would be a new column anyway.

**Decisions kept in the koto session's context, with only the settled outcome written to the
record as a Reversals row.** This avoids the codec change entirely. Rejected because each
start is a new session, so an open decision is lost on exactly the restart the PRD requires
it to survive (driver 6); a retained earlier session is local to one machine and one HOME,
where the record is on GitHub; and a context key is writable by the coordinator, so no check
could trust an entry's state or verdict from it (driver 2). Writing only the outcome also
loses the verdict's reasons, the part of a decision GitHub can least recompute.

**A fifth section always rendered, `None.` when empty, as the other four are.** This keeps
the record's uniform shape. Rejected because every record written before this feature would
stop being canonical the moment the new codec read it, sending every running coordinator to
`record_conflict` until a person rewrote its record (driver 3).

### Decision 2: Where the worker-side check lives

A worker's question addressed to the human has to be refused and re-routed to the
coordinator. The worker doesn't run `/coordinate`: it runs `/work-on`, `/execute`, `/deliver`
or `/scope`, and reports either by message, which the coordinator names as a `report` event
at the `wait` hub, or, when it was dispatched with a request leg, by the terminal result koto
promotes onto that leg. A check the worker's question never passes through isn't a check.

#### Chosen: at the coordinator's report intake, with the brief defining the shape

After the dispatch path's `take_report` admits a report and `report_facts` reads the
reporting holding, a new check state, `report_questions`, runs `report-questions.sh` over the
admitted report text (`worker_report`, which `take_report` itself gates and, on the leg path,
checks against the result koto holds). It extracts the report's questions deterministically:

- every numbered item under a line reading exactly `Questions:`, each optionally citing an
  entry as `(decision <n>)`;
- every other line that ends with a question mark;
- every other line that matches the decision-phrasing list (Decision 5), such as "please
  decide whether to ship", which ends with no question mark.

Lines inside fenced code blocks and quoted lines (`>`) are skipped, so a pasted log doesn't
become questions. At most ten questions of at most 400 characters are taken from one report;
a report over either cap gets the verdict `overflow`, which sends the worker a rebrief asking
it to resend with a Questions part, and opens nothing.

A question is marked `addressed` when it matches the list's person-addressing patterns ("the
human", "you decide", "your call", "up to you", and the rest the list names). A citation is
honored only for an entry whose Source is the reporting worker; a question citing any other
entry is treated as uncited. The script writes the extracted list as the detail key
`coord/questions.json` through `lib_emit`, and puts the list's SHA-256 digest in its verdict
token, `questions <digest>`, which `lib_emit` seals to the visit; it prints that, `none`,
`overflow` or `unreadable`. A reader takes the sealed capture with `coord-log.sh capture
--state report_questions` and refuses the detail key unless its digest matches, so the list
a later write reads is the one the check produced, not a copy the coordinator edited.

On `questions` the run goes to `decision_open`. There the coordinator words each question for
the public record and runs `record-decision.sh --open-from-report --text-file <file>`, a JSON
map from each extracted item's index to `{question, options}` in the coordinator's words. The
script reads the sealed list itself, never an argument, refuses unless every index is covered
exactly once, and writes one `proposed` entry per uncited question (source
`worker <topic> [report <seq>.<i>]`) and one evidence line per cited one, stamped
`[report <seq>.<i>]`, with `addressed` added to the stamp of each addressed question. The
coordinator's wording, not the worker's text, is what reaches the public record, and it
passes the same visibility checks as every other cell. The report itself isn't refused:
whatever else it says is classified as today. When any question was addressed, the worker is
owed one redirect for the report, rendered by the workflow, saying its questions go to the
coordinator, which answers them or escalates them with a recommendation; it is marked sent by
an evidence line `[redirect report <seq>]` on the first entry the report wrote to.

This check holds against the worker. On the message path the report text in `worker_report`
is what the coordinator relayed when it named the event, so a coordinator that leaves a
question out of its relay isn't caught; on the leg path `take_report` checks the text against
the result koto holds. The message-path relay is a residual of the same kind as
tsukumogami/koto#261's, named in Security Considerations.

The brief carries the contract that makes the Questions part parseable. The dispatch path's
`render-brief.sh` prints, in its fixed Reporting section, the sentence the PRD requires and
the `Questions:` shape, and its test checks the sentence is in every rendered brief.

A report from a coordinator this one dispatched is caught by the same check. Messages
`decision-render.sh` renders start with a fixed first line (`Decision <n> round <r> from
<topic>.`, `Withdrawn: decision <n> round <r> from <topic>.`, `Answer: decision <n> round <r>
...`). `report-questions.sh` honors such a line only when the reporting holding's entry point
is `/shirabe:coordinate` and the topic in the line is the holding's own worker topic. An
escalation becomes one question with source `coordinator <topic> #<n> round <r>
[report <seq>]`, and a second escalation with the same topic, entry and round (a re-send after
a crash) opens nothing; a withdrawal becomes evidence on the entry with that source, which
reopens it and, if it was escalated further up, withdraws it there too. An `Answer:` line in a
report means nothing at the receiver, since answers come from a coordinator's own dispatcher,
and is read as ordinary text.

#### Alternatives Considered

**In the brief only (the dispatch path's `render-brief.sh`).** The brief is the worker's only
context, so saying the rule there reaches every worker. Rejected as the check because it is a
sentence the worker may ignore; nothing refuses anything. It is kept as the contract the chosen
check parses against.

**In the worker skills' report step.** A check in `/work-on`, `/execute`, `/deliver` and
`/scope` would run in the worker's own session, before anything is sent. Rejected because none
of those templates has a step that sends a report: a report is a message the agent composes
between or after skill runs, outside any template state, so a gate there never sees it
(driver 4). The one structured thing a worker skill emits to a coordinator, its promoted leg
result, has fixed fields (status, final state, outcome, step, reason, pull request) and no
place for a question, and only a same-host worker dispatched with a leg has one. Adding a
question field to four skills' result maps would still miss message reports, workers on
another host, and a question asked mid-run before any terminal, and would change four skills
this feature has no other reason to touch.

**In `classify_report`, by refusing a `blocked` classification of a report that addresses the
human.** This is at the coordinator's intake too. Rejected because a classification is one
answer for the whole report, made by the coordinator with a decider only in shadow, so the
refusal would depend on the coordinator's own reading of the report, which driver 2 rules
out; and because a report that is both "done" and carries a question can have only one
classification. Extracting the questions as data, in a check state the coordinator doesn't
answer, makes the refusal deterministic and lets such a report be handled as both.

### Decision 3: How the template enforces transitions, verdicts, one at a time, and send-once

The PRD's rules are about sequencing: a verdict before any escalation, one escalation at a
time, a message sent once per verdict, a withdrawal when evidence reopens an escalation, a
reply when an entry with a source settles, a successor that takes all of it over, and no
question lost when a write fails. Each could be a separate rule in the state that needs it,
or one read could decide what is owed next.

#### Chosen: a bound write script, one routing check, split send states, and a dispatch guard

**The write script.** `record-decision.sh` is the only thing that changes the Decisions
section. It reads the live record from GitHub before every write, and every mode is bound to
the workflow state it runs in and to the entry the workflow chose. The current state is the
target of the log's latest transition, read with a new `coord-log.sh current`. Modes reached
from `decision_next` take the entry from its sealed capture; `--answer` and `--evidence` take
it, and an answer's round, from the `decision` and `round` fields of this visit's `wait`
evidence. The run's target comes from `coord-log.sh vars` (`REPORTS_TO`), never from an
argument.

| Mode | State | From | To | Refuses when |
|---|---|---|---|---|
| `--carry` | `decision_carry` | the previous rotation's handoff | its unsettled entries and `Next decision` copied into this record | before the run's first dispatch only; the entries already present |
| `--open` | `decision_raise` | none | `proposed`, source `self [raise <seq>]` or `dispatcher [raise <seq>]` | question or options empty |
| `--open-from-report` | `decision_open` | none | `proposed`, or evidence on a cited entry | an item uncovered or covered twice; the list's digest doesn't match its sealed capture; the report visit already written |
| `--take` | `decision_take` | `proposed` | `coordinator-verdict` | any other state |
| `--settle` | `decision_verdict` | `coordinator-verdict` | `settled`, `Owed: reply` when its source is a worker, a coordinator or the dispatcher | outcome or reason empty |
| `--escalate` | `decision_verdict` | `coordinator-verdict` | `escalated` with Round up by one and `Owed: escalation`; or the verdict queued when another entry is escalated | the shared escalation validator fails |
| `--answer` | `decision_answer` | `escalated`, answer naming its current round | `settled`, `Decided by` from the target, `Owed: reply` as for `--settle` | neither an option nor an outcome with its reason |
| `--answer` | `decision_answer` | `settled` by an identical answer (same round, outcome and decider) | nothing: a re-sent answer is already recorded | none |
| `--answer` | `decision_answer` | any other state, or an earlier round | evidence appended, as `--evidence` | as `--evidence` |
| `--evidence` | `decision_evidence` | any | `coordinator-verdict`, evidence appended | text or source empty |
| `--sent` | a `*_send` state | an entry owing the kind that state sends, or a report owing a redirect | `Owed` cleared and `Sent` stamped, or the redirect's evidence line | the render capture sealed at the latest entry into the matching render state doesn't name this entry, kind and round, or its digest doesn't match the rendered text |

Every write keys on the visit that caused it and stamps it, in one format both
`record-decision.sh` and `decision-next.sh` share: `[report <seq>.<i>]` on the Source or
Evidence line an open writes, `[wait <seq>]` on the line an answer or evidence writes, and
`[raise <seq>]` on the Source of an entry raised in `decision_raise`, where `<seq>` is the log
sequence of that state's entry. A second write for the same key is refused, so a retry after a
failed compare-and-swap never duplicates an entry or an evidence line. Any single item a write
takes (a question, an option, an evidence text, a context, a problem, a reason, an outcome) is
refused when it holds a carriage return or a line feed, since the codec's `<br>` also separates
Options and Evidence lines and an embedded break could forge an item.

Evidence (and an answer that becomes evidence) does more in the same write. It clears the
Verdict column, so a queued or earlier verdict can't be acted on without a new one. On a
settled entry it appends the previous outcome and who decided to Evidence, clears Outcome and
Decided by, and clears an owed reply, since there is no longer an outcome to report. On an
escalated entry whose message was sent it sets `Owed: withdrawal`; on one whose message was
never sent it clears `Owed`, since there is nothing to withdraw.

A write that frees the one escalated slot (settling the escalated entry, or evidence on it)
also releases the queued escalation with the lowest identifier in the same write: it runs the
shared validator over that entry's recorded verdict and escalates it (`Owed: escalation`), or,
if the verdict no longer passes, clears the verdict so the entry goes back for a new one.

The shared escalation validator is one jq definition in the codec, used by `--escalate`, by
the release above and by `decision-render.sh`: the recommendation is one of the options; the
reason, context and problem are non-empty after trimming; at least one ground; the target is
the run's. Because the write refuses what the renderer would refuse, a render can fail only if
the record changed underneath, which is a record fault.

`record-write.sh` refuses any body whose Decisions section differs from the live one's. Its
write core (parse, compare-and-swap, visibility, render, edit) moves into a `record-common.sh`
function that both scripts call, `record-decision.sh` after its own transition checks.

**The routing check.** `decision_next` runs `decision-next.sh`, which reads the record from
GitHub and the session log and prints one sealed verdict for the first thing owed, in this
order:

1. `carry`: before the run's first dispatch, an unsettled entry in the previous rotation's
   handoff, or its `Next decision`, is missing from this record (to `decision_carry`).
2. `unrecorded-open`, `unrecorded-answer`, `unrecorded-evidence`, `unrecorded-raise`: a write
   this run asked for didn't land, each word routing back to its own state. It is unrecorded
   when the latest entry into `report_questions` sealed `questions` and no Source or Evidence
   line carries its `[report <seq>.*]` stamp; when the latest `wait` answer or evidence has no
   line stamped `[wait <seq>]`; or when the latest entry into `decision_raise`, from any state
   that leads there, has no entry stamped `[raise <seq>]`.
3. `withdraw <n>`: an entry owes a withdrawal.
4. `reply <n>`: an entry owes a reply, or a report with an addressed question has no
   `[redirect report <seq>]` line yet.
5. `escalate <n>`: an entry owes its escalation (never sent, including after a crash between
   the verdict and the message).
6. `take <n>`: a `proposed` entry, lowest identifier first.
7. `verdict <n>`: a `coordinator-verdict` entry with no verdict recorded, lowest identifier
   first. The entry is written as the detail key `coord/decision.json` through `lib_emit`,
   which a `context-exists` gate on this arm requires, as `pick_input` does for `pick`.
8. `clear-report` or `clear`: nothing owed; `clear-report` when the latest `report_questions`
   capture's word is `questions` and there has been no entry into `classify_report` since, so
   the report that carried the questions is still to be classified.

`clear-report` goes to `classify_report` and `clear` to `pick_facts`. `reconcile` and
`roadmap_close`'s new `decisions` stage go to `decision_next`, and `pick_facts` gains a
`decisions` verdict, printed whenever anything above rules 1 to 7 is owed, which also goes
there. `pick_facts` is the one state every turn of the loop passes, so an owed reply or a
released escalation is routed at the next turn even when pick holds or asks up, and an
answer that went on to `decision_apply` comes back through it.

**Send states.** Every message has a render state and a send state, the pair the template
already uses for `land` and `land_merge`. The render state (`escalate`, `decision_withdraw`,
`decision_reply`) is a check: `decision-render.sh` reads the live entry, refuses unless the
entry owes the kind it is asked to render (so a second rendering of the same owing can't
happen), runs the shared validator, writes the text as a detail key and prints
`rendered <kind> <n> <round> <digest>`, which `lib_emit` seals, or `refused` (routed to
`record_conflict`, since only a record changed underneath can cause it). The send state
(`escalate_send`, `decision_withdraw_send`, `decision_reply_send`) shows the text; the
coordinator sends exactly that, runs `record-decision.sh --sent`, and submits `sent`, which
returns to `decision_next`. `--sent` refuses unless the sealed capture names this entry, kind
and round and its digest matches the text, so nothing is marked sent that wasn't rendered as
it stands, and a message is owed until it is marked. A crash after sending and before marking
sends it again on the next run: the guarantee is at least once. The receiver absorbs the
duplicate by its first line: an escalation with a topic, entry and round already opened opens
nothing, and a reply identical to the answer that settled an entry changes nothing.

The escalation reads:

```text
Decision <n> round <r> from <topic>.

<context paragraph>

<problem paragraph>

<question>
1. <recommended option> (recommended: <reason>)
2. <other option>

Answer naming decision <n> round <r> and an option, or give another outcome with its reason.
```

A withdrawal names the decision and round and says no answer is needed; a reply names the
decision, the outcome, its reason and who decided; a redirect tells the worker its questions
go to the coordinator. Free-text cells are rendered with `@` encoded so a public record or
message never notifies anyone.

**The dispatch guard.** `dispatch_check`'s `deferral-check.sh` gains a verdict,
`decision-owed`, routed to `decision_next`. Before the run's first dispatch it refuses while
anything in rules 1 to 7 is owed: a missing carry, an unrecorded write, an owed message, a
proposed entry, or an entry in `coordinator-verdict` with no verdict. After the first dispatch
it refuses only for an unrecorded write or an owed message, which `decision_next` clears in a
step, so an entry awaiting the coordinator's verdict never blocks dispatch for the rest of the
run (a coordinator that wants a worker to investigate before judging can still dispatch one).
Take-over then holds on every path to the first dispatch, including `reconcile` to
`posture_ask` to `record` to `pick_facts`, which doesn't pass `decision_next`, and the
`pick_facts` verdict keeps the loop from leaving owed work behind afterwards.

#### Alternatives Considered

**A confirm state after every write, and separate rules per concern.** Each write would go to
its own confirm check, as holdings go through `record`, and one-at-a-time, send-once and
take-over would each be a rule in the state that needs it (a guard in `escalate`, a marker
check in the renderer, a take-over pass in `reconcile`). This is how the template handles
holdings today and would be the smaller change to its shape. Rejected because the rules would
be spread across six states, each reading the record, a restart would need its own pass to
find what is owed (driver 6), and a failed write that creates an owing (an open, an answer)
would need its own confirmation rule; one routing read gives all of that from the same facts.

**The coordinator composes the escalation, and a check validates the text.** The directive
would ask for context, problem and question, and a check would parse the message for the
three parts. It keeps the coordinator's own voice in the message. Rejected because parsing
prose for "a context paragraph" is heuristic, and a check that passes a composed message can't
tell it matches the recorded verdict (driver 2). Rendering from the entry makes the verdict and
the message the same thing.

**A fifth state, `queued`, for an escalation waiting its turn.** It would make the
one-at-a-time rule visible in the State column, and `decision_next` could route on the state
alone. Rejected because a queued entry behaves as `coordinator-verdict` in every respect that
matters (evidence resets it, it isn't with anyone, it can be re-judged), so a separate state
would duplicate every rule that applies to `coordinator-verdict`; the recorded verdict already
marks it.

**A separate `decision_release` state** that releases the next queued escalation after the
slot frees. Rejected in favor of releasing inside the write that frees the slot: a state and a
routing rule fewer, and no window in which nothing is escalated and a queued verdict waits on
the coordinator's next tick.

### Decision 4: The escalation target and the way back down

The skill's glossary says "the human" means whoever dispatched the coordinator. The template
needs to know which it is, and an answer has to reach the entry that asked, one level down.

#### Chosen: a run setting, `--reports-to`, and answers that name the entry and round

`coordinate-open.sh` accepts `--reports-to <topic>`, the dispatch topic of the coordinator
this one reports to; without it the run reports to a person. It reaches the template as the
constrained variable `REPORTS_TO` (empty, or the topic grammar), checked at `koto init` like
every other setting, and read by the scripts from `coord-log.sh vars`. The target is fixed per
run.

Answers arrive only on the dispatcher's channel, as a message the coordinator names at `wait`
with `event: answer`, the `decision` and its `round`; a worker's report never produces one, since
`report_questions` turns a worker's text into questions and evidence only. `record-decision.sh
--answer` writes `Decided by` itself, from the target: `a person`, or `coordinator <topic>`,
followed by the final decider the reply names when the answer came back down from a nested
coordinator. An answer that reverses or extends a decision the dispatcher supplied goes on,
after `decision_answer`, through the existing `decision_apply` state with `change: reversal`,
whose record write and confirmation already handle Reversals, so there is one writer and one
check for reversals. `wait` keeps `event: decision` for a decision the dispatcher sends
unprompted, and adds `answer` for a reply naming an entry.

At the receiver, an escalation from a coordinator it dispatched is opened by
`report_questions` as a `proposed` entry with that coordinator and entry as its source. When it
settles, by the receiver's own verdict or by an answer from further up, it owes a reply, and
the rendered reply names the source entry and round, the outcome, its reason and who decided.
The lower coordinator names it at `wait` as an answer, and its entry settles with the final
decider named. An entry whose source is a worker owes the same reply, sent as a message the
way `rebrief` reaches the worker.

#### Alternatives Considered

**A target chosen per decision.** It would let a coordinator send a decision that needs a
person straight to one, skipping a coordinator above that has nothing to add. Rejected because
that is the niwa#330 route one level up: the coordinator above is exactly the one whose
verdict the design exists to insert, and "has nothing to add" is its call to make, not the
lower coordinator's (driver 5).

**Reading the dispatcher from the brief.** A coordinator dispatched by another coordinator has
a brief naming its dispatcher's session, and the dispatch path renders it. Rejected because
the brief is a file the run doesn't parse, a session name isn't the dispatch topic the record
and every check use, and a flag at open is checked by koto before any session exists.

### Decision 5: Telling a decision from any other blocker in the progress table

The niwa#330 row was free text in the `--blocked` flag. A row that asks for a decision has to
come from an escalated entry, but some needs are not decisions (a credential, a step the
workspace reserves, such as running a release) and still belong in "Blocked on you".

#### Chosen: decision rows from the record, and a closed phrasing list for free text

`pick-facts.sh` adds the record's unsettled entries to `coord/pick.json`, and
`progress-view.sh` renders them:

- an entry escalated to a person: a "Blocked on you" row, Unit the question, Status `decide`,
  and "recommended: <recommendation>, because <reason>" in the last column; refused when
  either is empty;
- an entry escalated to a coordinator: an "Ongoing" row reading "with `<topic>` for a
  decision", asking the reader nothing;
- an entry `proposed` or in `coordinator-verdict`, queued or not: an "Ongoing" row reading
  "with me for a verdict".

`--blocked <session>=<need>` stays for needs that aren't choices, and refuses any need that
matches the decision-phrasing list. The list is one file,
`skills/coordinate/references/decision-phrasings.tsv`, each row an extended regular
expression matched case-insensitively by `grep -E` (no back-references, so matching time is
linear in the text) and whether it marks a decision or a person-addressed question. It is read
by `progress-view.sh`, `report-questions.sh` and `need-check.sh`. Its fixtures,
`scripts/testdata/decision-phrasings/`, hold at least three refused and three accepted
phrasings, including an accepted need that resembles a decision ("waiting on the release
decision from the vendor").

The `surface` state's blocker path gets the same check. `surface` gains a `need` field and a
third answer, `decision`, which goes to `decision_raise`; `blocker` goes to a check state,
`surface_check`, whose `need-check.sh` reads the need from the logged evidence of the latest
`surface` visit (`coord-log.sh evidence`), refuses one matching the list (back to `surface`),
and otherwise seals it for sending (to `wait`).

#### Alternatives Considered

**A declared kind on every blocker row (`--blocked T=decision:...`).** It is explicit and has
no false positives. Rejected because the coordinator declares it, so a decision declared as a
plain need passes, which is the niwa#330 row exactly (driver 2); the phrasing check reads the
text instead.

**A decider classifying free text as a decision or a need.** A decider would catch phrasings
a closed list misses. Rejected as the check because its answer depends on a model and can't
be a deterministic refusal; deciders here stay in shadow (a `verdict` decider on
`decision_verdict` classifies authority, where judgment belongs, and is recorded, never
acted on).

## Decision Outcome

Decisions live in the record, in a fifth section rendered only when it has something to hold,
so every record on GitHub today stays canonical. One write script changes that section; it
runs only in the state each change belongs to, on the entry the workflow routed, and refuses
every transition outside the four-state machine and every verdict missing a part, and the
general record writer refuses to change the section at all. Evidence clears any recorded
verdict, so nothing reaches a person without a verdict made after it.

One routing check, `decision_next`, reads the record and the log after every decision write,
after reconcile and after every report that carried a question, and sends the coordinator to
the one next thing owed, in a fixed order: a write that didn't land, withdrawals, replies, the
escalation, taking up proposed entries, and verdicts. Every message is rendered from the
entry in a check state and marked sent only against that render. The write that frees the one
escalated slot releases the next queued escalation. `dispatch_check` refuses to dispatch while
anything is owed, so take-over holds on every path.

Worker questions are caught in the coordinator's report intake, which every report crosses;
each becomes an entry the coordinator words for the record, so a phrasing the list misses
still can't reach the dispatcher unjudged, and no worker text is pasted into a public record.
The run's escalation target is fixed at open; an escalation from below is a new entry at the
receiver, and its settlement comes back down by entry and round. The progress table takes
decision rows from the record and refuses free-text needs that read as decisions.

Against niwa#330: the approved option is a settled entry; the person's mixed result, relayed
by the dispatcher, is recorded as evidence, which clears the old verdict, keeps the old
outcome in Evidence, and moves the entry to `coordinator-verdict`; `decision_next` sends the
coordinator to `decision_verdict`, where it settles (keep option (d): the record's flip
condition didn't happen and its consequences accepted the clone moving); the worker's "please
decide whether to ship" arrives in a report, is extracted as an addressed question, opened as
a new entry with a redirect owed, taken up and settled with the same reasoning. The messages
rendered are the redirect and the replies to the worker. Nothing reaches a person.

## Solution Architecture

### Record

- `record-codec.jq`: the `decisions` section with its `Next decision` line, section-aware
  cell grammars and optional columns, per-state required columns, identifier uniqueness and
  bound, the shared escalation validator, `@` encoding in the free-text columns, the
  omit-when-empty render, a parse and handoff split that takes a fifth section only by its
  title, `decisions` in the allowed top-level keys, and the handoff filter to unsettled
  entries.
- `record-common.sh`: the write core shared by `record-write.sh` and `record-decision.sh`, and
  the named-repository scan extended to the Decisions text columns, with home-directory paths
  and token-shaped strings refused in them.
- `record-write.sh`: refuses a body whose Decisions section differs from the live one's.
- `closeout-read.sh`: a `decisions` stage before `ready` at roadmap scope; the handoff check
  expects the filtered section.
- `predecessor-handoff.sh`: copies the section as it stands.

### Scripts

| Script | Run by | Does |
|---|---|---|
| `record-decision.sh` | the coordinator, in the decision states | The only writer of the Decisions section; the mode table in Decision 3; exit 65 and nothing written on any other transition, a missing verdict part, or a mode run outside its state |
| `decision-next.sh` | `decision_next`'s action | Reads the record and the log, prints the sealed next-owed verdict, writes `coord/decision.json` for a verdict |
| `decision-render.sh` | the render states' actions | Renders an escalation, withdrawal, reply or redirect from the live entry through the shared validator, refuses when the entry doesn't owe that kind, seals the text's digest in its verdict |
| `report-questions.sh` | `report_questions`'s action | Extracts, caps and classifies a report's questions, honoring citations and first lines only from their own holding; seals the list's digest in its verdict |
| `need-check.sh` | `surface_check`'s action | Reads the need from the latest `surface` evidence, refuses one matching the phrasing list, seals the rest |
| `deferral-check.sh` (changed) | `dispatch_check`'s action | The `decision-owed` verdict |
| `progress-view.sh` (changed) | the coordinator | Decision rows from the record; `--blocked` refuses decision phrasings |
| `pick-facts.sh` (changed) | `pick_facts`'s action | Adds unsettled entries to `coord/pick.json` |
| `coordinate-open.sh` (changed) | the coordinator | `--reports-to <topic>` to `REPORTS_TO` |
| `render-brief.sh` (changed, dispatch path's) | `dispatch-worker.sh` | The fixed channel sentence and the `Questions:` shape in Reporting |

`coord-verdict.sh` gains a block of verdict codes (150 to 179) for the new words (`carry`,
`unrecorded-open`, `unrecorded-answer`, `unrecorded-evidence`, `unrecorded-raise`,
`withdraw`, `reply`, `escalate`, `take`, `verdict`, `clear`, `clear-report`, `questions`,
`overflow`, `unreadable`, `accepted`, `decision-owed`, `decisions`, `rendered`), pinned to
the template's arms by `coord-verdict-table_test.sh` as today; `coord-verdict.sh` routes on a
token's first word, so each route has its own word. `refused` reuses its existing code, which
the table allows because it is global. `coord-log.sh` gains `current`, the state the session
is in now.

### Template states

| State | Kind | Action and checks | Routes |
|---|---|---|---|
| `decision_next` | check | `decision-next.sh`; `decision_input` on the verdict arm | `decision_carry` on `carry`; `decision_open`, `decision_answer`, `decision_evidence`, `decision_raise` on the four `unrecorded-*` words; `decision_withdraw`, `decision_reply`, `escalate`, `decision_take`, `decision_verdict`; `classify_report` on `clear-report`; `pick_facts` on `clear` |
| `decision_carry` | agent | `record-decision.sh --carry` | `decision_next` on `carried` |
| `decision_take` | agent | `--take` | `decision_next` on `taken` |
| `decision_verdict` | agent, shadow decider on `verdict` | `verdict: settle` runs `--settle`, `verdict: escalate` runs `--escalate` | `decision_next` on either |
| `escalate`, `decision_withdraw`, `decision_reply` | check | `decision-render.sh --kind escalation`, `withdrawal`, `reply` or `redirect` | the matching `*_send` on `rendered`; `record_conflict` on `refused` |
| `escalate_send`, `decision_withdraw_send`, `decision_reply_send` | agent | send the rendered text, then `--sent` | `decision_next` on `sent` |
| `report_questions` | check | `report-questions.sh` | `decision_open` on `questions`; `classify_report` on `none`; `rebrief` on `overflow`; `surface` on `unreadable` |
| `decision_open` | agent | `--open-from-report` | `decision_next` |
| `decision_raise` | agent | `--open` | `decision_next` |
| `decision_answer` | agent | `--answer` | `decision_next`; `decision_apply` when the answer reverses or extends a supplied decision |
| `decision_evidence` | agent | `--evidence` | `decision_next` |
| `surface_check` | check | `need-check.sh` | `wait` on `accepted`; `surface` on `refused` |

Changed edges: `wait` gains the events `answer`, `evidence` and `raise` and the fields
`decision` and `round`; `reconcile` goes to `decision_next`; `pick_facts` gains `decisions` to
`decision_next`; `roadmap_close` gains its `decisions` stage to `decision_next`;
`report_facts` goes to `report_questions`; `failure: escalate` goes to `decision_raise`, since
escalating a failure asks the dispatcher to decide; `surface` gains `need` and the answer
`decision` (to `decision_raise`), and `blocker` goes to `surface_check`; `dispatch_check`
gains `decision-owed` to `decision_next`. `classify_report`'s `blocked` answer stays: a report
blocked on a step that isn't a choice still surfaces, now through `surface_check`.

`decision_verdict` declares a decider on `verdict` (`settle`, `escalate`), its input
`coord/decision.json`, every answer shadow, with fixtures in
`coordinate.decision_verdict.verdict.decider.jsonl`, at least one per answer, and rows in
`scripts/decider-declarations.tsv`.

### Data flow for one escalation

```
report_facts -> report_questions --(questions)--> decision_open -> decision_next
decision_next --(take n)--> decision_take -> decision_next
decision_next --(verdict n)--> decision_verdict --(escalate)--> decision_next
decision_next --(escalate n)--> escalate --(rendered)--> escalate_send --(sent)--> decision_next
wait --(answer n)--> decision_answer -> decision_next
decision_next --(reply n)--> decision_reply --> decision_reply_send -> decision_next
decision_next --(clear-report)--> classify_report | --(clear)--> pick_facts
```

## Implementation Approach

Implementation starts from a default branch that contains the dispatch path (shirabe#404)
and reconcile (shirabe#406), and uses the koto floor shirabe declares then (0.14.0 once
shirabe#457 has landed). Each step below is what the next one calls, so each can be tested
before the next exists:

1. **The phrasing list and its fixtures.** Three scripts read it, so it comes first.
2. **The Decisions section and the shared write core.** The codec change, the shared
   validator, `record-common.sh`'s write core, `record-write.sh`'s refusal, the close-out
   stage and the predecessor copy; golden-file tests, including a pre-feature record adopted
   unchanged and each malformed entry refused. Everything that writes an entry writes through
   this.
3. **The renderer.** `decision-render.sh` for the four kinds over fixture entries, with a
   test for each field the validator refuses, a wrong target and a changed record.
4. **The question extractor.** `report-questions.sh` over report fixtures: the Questions part,
   bare question lines, phrasing matches, fences and quotes, caps, citations from the holding
   and from another worker, and forged first lines.
5. **The write script.** `record-decision.sh`, every mode and refusal of the Decision 3 table,
   including `coord-log.sh current` and the state binding, the carry, the visit stamps and
   their idempotence, the line-break refusal, the evidence resets (including an owed reply)
   and release, against the test library's GitHub stand-in.
6. **Routing and the template.** `decision-next.sh` with every rule, including the four
   `unrecorded-*` words, an all-cited report, a stale report after `overflow`, and the carry;
   the `dispatch_check` guard before and after the first dispatch; the `pick_facts` and
   `roadmap_close` routes; `need-check.sh`; `REPORTS_TO` and `--reports-to`; the new states and
   edges, the verdict codes, the shadow decider and its fixtures; template compile and
   structure tests; take-over after a restart for each state.
7. **The brief and the progress table.** The channel sentence and Questions shape in
   `render-brief.sh`; `pick-facts.sh` and `progress-view.sh` with the decision rows and the
   free-text refusal.
8. **Skill text and replays.** SKILL.md's decision section by state names, and a check that
   every state and check name it uses exists in the template; `loop.md`'s escalation shape
   replaced by a pointer to the rendered form; `record-template.md`; rule-coverage rows; an
   eval; the three-level round trip and the niwa#330 replay as engine tests, the replay also
   run against a template variant whose evidence edge goes straight to `escalate`, where it
   must fail.

## Security Considerations

- **Untrusted report text.** A worker's report is free text from a session the coordinator
  doesn't control. `report-questions.sh` reads it as data with `jq` from the key `take_report`
  gated, never evaluates it, skips fenced and quoted lines, and caps questions at ten of 400
  characters, sending an over-cap report back to the worker rather than into the record. The
  phrasing patterns run under `grep -E` with no back-references, so a crafted line can't make
  matching slow.
- **Nothing a worker writes is pasted into the public record.** The coordinator words each
  question for the record, and the script refuses unless every extracted item is covered once;
  the free-text cells go through the named-repository scan, extended to them, and refuse
  home-directory paths and token-shaped strings. The codec encodes pipes, newlines and `@`, so
  a cell can't break the table or mention anyone; because `<br>` also separates Options and
  Evidence lines, `record-decision.sh` refuses a line break inside any single item, so one
  can't forge an option or an evidence line.
- **A worker can't answer, settle or reach other entries.** Answers are named by the
  coordinator at `wait` from its dispatcher's channel, and `Decided by` is written from the
  run's target, not from the message. A citation is honored only on the reporting worker's own
  entries, so a report can reopen only what that worker raised, and each reopening needs a new
  verdict before anything goes to anyone. A fixed first line claiming a coordinator source is
  honored only from a holding dispatched as a coordinator under that topic.
- **Stale and duplicate messages.** Every escalation, withdrawal and reply names its round,
  and an answer for an earlier round is evidence rather than a settlement. A message re-sent
  after a crash between sending and marking is absorbed by its receiver: an escalation already
  opened for that topic, entry and round opens nothing, and a reply identical to the answer
  that settled an entry changes nothing.
- **Checks read what the coordinator didn't write.** Every routing verdict comes from GitHub,
  the session log, or a capture the engine wrote. Content a later step reads (the question
  list, a rendered message, the next-owed entry) sits in a detail key the coordinator could
  overwrite, so its SHA-256 digest is in the sealed verdict token, and the reader refuses the
  key unless the digest matches. A seal's hash has no key (`coord-log.sh`), so it guards
  against a stale or mismatched value, not against a coordinator that forges one deliberately.
- **The coordinator's relay.** A message report reaches `worker_report` as the text the
  coordinator relayed when it named the event, so a coordinator that drops a question from its
  relay isn't caught. The question check holds against the worker; the leg path is checked
  against the result koto holds.
- **Residual risk, shared with the record under tsukumogami/koto#261.** Checks run in the
  coordinator's environment, so a coordinator that shadows `gh`, `jq` or `git`, or rewrites
  these scripts, can make any check read what it wants. A coordinator can still type a question
  to a person in its own chat outside the workflow's messages, and a report can try to steer a
  verdict by persuasion; the checks guarantee a verdict exists and is complete, not that it is
  right. Who may message a session is the harness's and the workspace's to decide.

## Consequences

### Positive

- A decision reaches a person only through a recorded verdict, in the shape the operator in
  the session behind the comment on shirabe#435 asked for, one at a time; the niwa#330
  sequence ends without a question to a person.
- Open decisions survive restarts and rotations, and no dispatch happens while one is owed a
  step.
- Nesting needs no special case: a coordinator's escalation is a report to the one above, and
  its answer comes back by entry and round.
- The progress table can't carry a bare "decide" row.

### Negative

- The record's Decisions table is nineteen columns wide, which reads poorly on GitHub.
- Every worker question becomes an entry, including trivial ones a coordinator would have
  answered in a line; each costs a take and a verdict write, plus the coordinator's wording.
- The decision loop adds sixteen states and a routing check to an already large template.
- A closed phrasing list misses phrasings. In a report that is harmless, since every question
  becomes an entry; in a free-text need a missed phrasing can reach the progress table.
- Messages are sent at least once, not exactly once.

### Mitigations

- Settled entries leave a rotation's record at its end and a roadmap's at its close; the width
  is the price of every field being a visible table cell, which the record's no-hidden-copy
  rule requires.
- A trivial question settles in two writes with no message to anyone but the worker.
- The new states follow the existing check-state and send-state patterns and the global
  verdict table, and each has a passing and a failing test.
- The phrasing list is one file with fixtures, so a missed phrasing found in use is a one-line
  addition with a test.
- The round in every message's first line makes a duplicate recognizable to whoever receives
  it.
