---
schema: design/v1
status: Current
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

Current

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
| Source | `worker <topic> [<stamp>]`, `coordinator <topic> #<n> round <r> [<stamp>]`, `dispatcher [<stamp>]` for a decision the dispatcher handed over, or `self [<stamp>]` |
| Verdict | blank, `settle`, `escalate` or `hold`; an escalate verdict on a `coordinator-verdict` entry is a queued escalation, and `hold` is a deferred verdict |
| Recommendation | one of the options |
| Reason | the recommendation's reason, or for a hold what the verdict waits on |
| Context | what is being decided and why it matters now |
| Problem | what is unresolved and why the coordinator can't settle it |
| Grounds | one or more of `scope`, `supplied-decision`, `reserved-step`, `outside-scope` |
| Target | `a person` or `coordinator <topic>` |
| Owed | blank, `escalation`, `withdrawal` or `reply` |
| Asked | when the escalation was marked sent |
| Evidence | append-only lines, `<time> <source> [<stamp>]: <text>` |
| Outcome | the outcome and its reason, once settled |
| Decided by | who settled it |
| Updated | the time of the last change |

**Stamps name the run.** Every stamp is `[<run> <kind> <seq>[.<i>]]`, where `<run>` is the
UTC stamp in the session's name (`coordinate-<scope>-<stamp>`, one per run) and `<seq>` the
log sequence of the visit that caused the write: `report` for an open or a cited question,
`wait` for an answer or evidence, `raise` for a raised entry, `hold` for a deferred verdict,
`redirect` for a sent redirect. The codec has a grammar for it. Sequence numbers restart
with every run while the record outlives them, so a stamp without its run would let a second
run's report at sequence 40 collide with the first run's; with it, a stamp is unique across
runs, and `decision-next.sh` matches only the current run's stamps when it asks whether this
run's write landed.

**Rendering and adoption.** The section is rendered only when it has an entry or
`Next decision` is above 1, and the parser accepts four sections or five, taking the fifth
only when its title is `Decisions`. A record written before this feature has no such section,
parses to no entries and a next identifier of 1, and renders back to the same bytes, so every
live record stays canonical and `record-find.sh` adopts it unchanged. `Next decision` never
goes down, so a record changes shape once, at its first entry, and never toggles back. A
malformed entry (an unknown state, an identifier that isn't an integer, repeats, or isn't
below `Next decision`, a required column empty for its state, a ground outside the four, a
stamp that doesn't parse) is refused by the codec, which makes the record non-canonical.
Which columns an entry needs depends on its state (an escalated entry needs recommendation,
reason, context, problem, grounds and target; a settled one needs outcome and decided by; a
held one a reason), so that is a row-level check, and cell grammars are looked up by section
as well as column, so the Decisions `reason` and `target` columns don't take the grammars of
the Reversals and Side effects columns of the same names. The codec's list of names refused
as GitHub-recomputable is consulted only for columns outside a section's own list, so the
Decisions `state` column needs no exemption.

**Size.** `record-parse.sh` refuses a body over 65,536 bytes, and every write parses first.
Two rules keep the section inside that. A settled entry that owes nothing is compacted at the
next write to its identifier, round, question, options, state, source, outcome, decided by,
updated time and any `redirect`-stamped Evidence lines, its other cells blanked (`Next
decision` is what keeps its identifier from being reused). Options survive because evidence
can reopen a settled entry, which then needs them to be escalated again; the redirect lines
survive because a lost one would owe the redirect a second time. Evidence lines stamped by the
run that is writing are kept too, for as long as that run lasts: the unrecorded-write rules
read them to tell whether a write landed, and a later run compacts them away. And the
write core refuses a body over 60,000 bytes with its own exit code, which `decision-next.sh`
and the record states report as `record-full`, a stop for the human, rather than letting
GitHub refuse the edit. The core checks the live body against the same budget before it
parses, so a record already past the parser's 65,536-byte limit gets the same exit code and
the same advice rather than a parse refusal.

**Handoff and close.** The handoff renders the section with only the unsettled entries and
the same `Next decision`, so a new rotation's record continues the numbering; a predecessor
copy copies the section as it stands. Settled entries stay in a roadmap record, compacted,
until its close, and leave a rotation's record at its end.

What this costs: the codec's section list, its fixed parse count, `parse_sections`'
four-section range and `parse_handoff`'s split, section-aware cell checks and top-level keys,
the record template reference, `closeout-read.sh`, `predecessor-handoff.sh`'s key list, the
`dispatch_check` wording about four sections, and new rule-coverage rows. `record-find.sh`
needs no change: it calls the parser. The omit-when-empty rule is what keeps it from also
costing a migration.

#### Alternatives Considered

**Decisions as rows in Deferrals, with a decision kind.** A deferral is "something the
coordinator chose not to act on now that someone must act on later", which a pending
decision resembles. Rejected because the Deferrals columns and their grammar (a Disposition
of `filed #n`, `closed: <reason>` or `carried <time>: <reason>`) would have to widen to hold a
recommendation, context, problem, grounds and evidence, which reopens the codec as much as a
new section does (driver 3 is no better served); because `deferral-check.sh` refuses every
dispatch while a deferral raised before the run's start is undisposed, so a decision escalated
to a person and still unanswered after a restart would stop all dispatch, and a carried row
counts only when re-carried in each run; and because filed and closed rows drop out at the
first rewrite after a dispatch, so a settled decision kept as a closed deferral would vanish
and evidence could never reopen it.

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

After the dispatch path's `take_report` admits a report, `report_facts` reads the reporting
holding and prints `holding`, `unknown` or `refused`. All three of its arms go to a new check
state, `report_questions`, so no admitted report reaches `wait` without its questions being
extracted; `report_questions` then routes on to where `report_facts`' arm went before
(`classify_report` for a holding, `wait` otherwise) once its questions are recorded. It runs
`report-questions.sh` over the admitted report text (`worker_report`, which `take_report`
itself gates and, on the leg path, checks against the result koto holds). It extracts the
report's questions deterministically:

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
entry is treated as uncited. Without a holding (`unknown` or `refused`), every citation is
treated as uncited and no fixed first line is honored, and the entries' source is the topic
the event named. The script writes the extracted list as the detail key `coord/questions.json`
and seals it with `coord-log.sh seal --file --key`, the helper that already binds a key's
bytes to a visit, and prints `questions`, `none`, `overflow` or `unreadable`. A reader checks
it with `coord-log.sh check --key`, so the list a later write reads is the one the check
produced, not a copy the coordinator edited.

On `questions` the run goes to `decision_open`. There the coordinator words each question for
the public record and runs `record-decision.sh --open-from-report --text-file <file>`, a JSON
map from each extracted item's index to `{question, options}` in the coordinator's words. The
script reads the sealed list itself, never an argument, refuses unless every index is covered
exactly once, and writes one `proposed` entry per uncited question and one evidence line per
cited one, each stamped `[<run> report <seq>.<i>]`, with `addressed` noted on each addressed
question. The coordinator's wording, not the worker's text, is what reaches the public record,
and it passes the same visibility checks as every other cell. The report itself isn't refused:
whatever else it says is classified as today. When any question was addressed, the worker is
owed one redirect for the report, rendered by the workflow, saying its questions go to the
coordinator, which answers them or escalates them with a recommendation; it is marked sent by
an evidence line stamped `redirect` on the first entry the report wrote to.

**What this check holds against.** It holds against the worker. The report reaches it by leg
or by message, and the message is the normal path: a leg result has fixed fields, and its only
room for a question is its reason field, which is read on its own (a reason ending in `?` is a
question), so questions travel mostly by message, and a message report reaches `worker_report`
as the text the coordinator relayed when it named the event. From a coordinator holding, a
report that carries an escalation's digest or answer line, or a withdrawal's first line,
anywhere (indented or quoted too) must be that message exactly as rendered, or it is
unreadable: a relay that altered it is never read on as a worker's question. A coordinator that drops a
question from its relay isn't caught. So "every report crosses it" holds for every report
the coordinator admits, not for text it chooses not to relay; that residual is named in
Security Considerations beside tsukumogami/koto#261. So is a second path no check reads: a
worker's pull request body and comments, which the merge-order table links a person to.

The brief carries the contract that makes the Questions part parseable. The dispatch path's
`render-brief.sh` prints, in its fixed Reporting section, the sentence the PRD requires, the
`Questions:` shape, and an instruction to repeat in each report any question that has had no
answer. The last is what recovers a question extracted but not yet written when the
coordinator crashes: the successor's log is new, so nothing else would bring it back.

A report from a coordinator this one dispatched is caught by the same check. Messages
`decision-render.sh` renders start with a fixed first line (`Decision <n> round <r>.`,
`Withdrawn: decision <n> round <r>.`, `Answer: decision <n> round <r> ...`) and carry no
sender topic, since a run has no variable for its own; the receiver takes the source from the
holding `report_facts` found. `report-questions.sh` honors such a line only when that holding's
entry point is `/shirabe:coordinate`. An escalation becomes one question with source
`coordinator <topic> #<n> round <r> [<stamp>]`, and a second escalation with the same holding,
entry and round (a re-send after a crash) opens nothing; a withdrawal becomes evidence on the
entry with that source, which reopens it and, if it was escalated further up, withdraws it
there too. An `Answer:` line in a report means nothing at the receiver, since answers come from
a coordinator's own dispatcher, and is read as ordinary text.

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
out; because a report that is both "done" and carries a question can have only one
classification; and because `classify_report` is reached only from a report with a holding.
Extracting the questions as data, in a check state the coordinator doesn't answer, makes the
refusal deterministic and lets such a report be handled as both.

### Decision 3: How the template enforces transitions, verdicts, one at a time, and send-once

The PRD's rules are about sequencing: a verdict before any escalation, one escalation at a
time, a message sent once per verdict, a withdrawal when evidence reopens an escalation, a
reply when an entry with a source settles, a successor that takes all of it over, no question
lost when a write fails, and a verdict that can wait for a fact without stopping everything
else. Each could be a separate rule in the state that needs it, or one read could decide what
is owed next.

#### Chosen: a bound write script, one owed predicate, split send states, and a dispatch guard

**The write script.** `record-decision.sh` is the only thing that changes the Decisions
section. It reads the live record from GitHub before every write, and every mode is bound to
the workflow state it runs in and to the entry the workflow chose. The current state is the
target of the log's latest transition, read with a new `coord-log.sh current`. Modes reached
from `decision_next` take the entry from its sealed capture (`coord-log.sh capture --name
DECISION_NEXT --state decision_next`); `--answer` and `--evidence` take it, and an answer's
round, from the `decision` and `round` fields of this visit's `wait` evidence. The run's target
comes from `coord-log.sh vars` (`REPORTS_TO`), never from an argument. It also has the two
read modes `record-holding.sh` has for Holdings, `--list` and `--read <n>`, and every other
script that reads the section (`decision-next.sh`, `decision-render.sh`, `report-questions.sh`,
`pick-facts.sh`, `closeout-read.sh`) reads it through them.

| Mode | State | From | To | Refuses when |
|---|---|---|---|---|
| `--carry` | `decision_carry` | the previous rotation's handoff | its unsettled entries and `Next decision` copied into this record | after the run's first dispatch; the entries already present |
| `--open` | `decision_raise` | none | `proposed`, source `self [<stamp>]` or `dispatcher [<stamp>]` | question or options empty |
| `--open-from-report` | `decision_open` | none | `proposed`, or evidence on a cited entry | an item uncovered or covered twice; the sealed list fails `check --key`; this run's stamp for the report already written |
| `--take` | `decision_take` | `proposed` | `coordinator-verdict` | any other state |
| `--settle` | `decision_verdict` | `coordinator-verdict` | `settled`, `Owed: reply` when its source is a worker, a coordinator or the dispatcher, unless the latest evidence is that source's withdrawal | outcome or reason empty |
| `--escalate` | `decision_verdict` | `coordinator-verdict` | `escalated` with Round up by one and `Owed: escalation`; or the verdict queued when another entry is escalated | the shared escalation validator fails |
| `--hold` | `decision_verdict` | `coordinator-verdict` | `coordinator-verdict` with Verdict `hold`, Reason what it waits on, and a `hold` stamp in Evidence | reason empty |
| `--answer` | `decision_answer` | `escalated`, answer naming its current round | `settled`, `Decided by` from the target, `Owed: reply` as for `--settle` | neither an option nor an outcome with its reason |
| `--answer` | `decision_answer` | `settled` by an identical answer (same round, outcome and decider) | the same state, with an `answer ... again` line under this arrival's stamp | none |
| `--answer` | `decision_answer` | any other state, or an earlier round | evidence appended, as `--evidence` | as `--evidence` |
| `--evidence` | `decision_evidence` | any | `coordinator-verdict`, evidence appended | text or source empty |
| `--sent` | a `*_send` state | an entry owing the kind that state sends, or a report owing a redirect | `Owed` cleared (and `Asked` stamped for an escalation), or the redirect's evidence line | the message key fails `coord-log.sh check --key` against the latest entry into the matching render state, or the sealed render doesn't name this entry, kind and round |

Every write keys on the run-qualified stamp of the visit that caused it, and a second write for
the same stamp is refused, so a retry after a failed compare-and-swap never duplicates an entry
or an evidence line. Any single item a write takes (a question, an option, an evidence text, a
context, a problem, a reason, an outcome) is refused when it holds a carriage return or a line
feed, since the codec's `<br>` also separates Options and Evidence lines and an embedded break
could forge an item.

Evidence (and an answer that becomes evidence) does more in the same write. It clears the
Verdict column, a hold included, so a queued, held or earlier verdict can't be acted on without
a new one. On a settled entry it appends the previous outcome and who decided to Evidence,
clears Outcome and Decided by, and clears an owed reply, since there is no longer an outcome to
report. On an escalated entry whose message was sent it sets `Owed: withdrawal`; on one never
sent it clears `Owed`, since there is nothing to withdraw.

A write that frees the one escalated slot (settling the escalated entry, or evidence on it)
also releases the queued escalation with the lowest identifier in the same write: it runs the
shared validator over that entry's recorded verdict and escalates it (`Owed: escalation`), or,
if the verdict no longer passes, clears the verdict so the entry goes back for a new one.

A settle that follows a source's withdrawal owes no reply: the source already reopened its own
entry, and a reply would reach it as evidence and reopen it again.

The shared escalation validator is one jq definition in the codec, used by `--escalate`, by
the release above and by `decision-render.sh`: the recommendation is one of the options; the
reason, context and problem are non-empty after trimming; at least one ground; the target is
the run's. Because the write refuses what the renderer would refuse, a render can fail only if
the record changed underneath, which is a record fault.

**Where the write core lives.** `record-common.sh` is sourced by every check script and
promises it makes no GitHub write, and `record-write.sh` and `record-holding.sh` say writes
happen in one script. So the write core (parse, compare-and-swap, visibility, size budget,
render, edit) moves into a new file, `record-write-core.sh`, sourced only by the write scripts
(`record-write.sh`, `record-holding.sh`, `record-decision.sh`), and the headers say so.
`record-write.sh` refuses any body whose Decisions section differs from the live one's, and
`record-open.sh`, which creates a record from a body the coordinator supplies, refuses a body
that has a Decisions section at all, so `record-decision.sh` is the only writer of it.

**One owed predicate.** Whether something is owed is decided in one place,
`decision-next.sh`. Its default mode is the routing check below; `--owed <gate>` prints
whether anything that gate cares about is owed, and `deferral-check.sh` and `pick-facts.sh`
call it rather than evaluating the rules themselves. The rules, in routing order:

1. `carry`: before the run's first dispatch, an unsettled entry in the previous rotation's
   handoff, or its `Next decision`, is missing from this record (to `decision_carry`).
2. `unrecorded-open`, `unrecorded-answer`, `unrecorded-evidence`, `unrecorded-raise`: a write
   this run asked for didn't land, each word routing back to its own state. It is unrecorded
   when the latest entry into `report_questions` sealed a list and no Source or Evidence line
   carries this run's stamp for that report; when the latest `wait` answer or evidence has no
   line with this run's `wait` stamp for it; or when the latest entry into `decision_raise`,
   from any state that leads there, has no entry with this run's `raise` stamp for it.
3. `withdraw <n>`: an entry owes a withdrawal.
4. `reply <n>`: an entry owes a reply.
5. `redirect <n> <seq>`: a report with an addressed question has no `redirect` line yet on
   any entry; `<n>` is the first entry the report wrote to and `<seq>` the report's log
   sequence, which the renderer and `--sent` need to name the report.
6. `escalate <n>`: an entry owes its escalation (never sent, including after a crash between
   the verdict and the message).
7. `take <n>`: a `proposed` entry, lowest identifier first.
8. `verdict <n>`: a `coordinator-verdict` entry with no verdict recorded, lowest identifier
   first. Held entries are skipped. The entry is written as the detail key
   `coord/decision.json` through `lib_emit`, which a `context-exists` gate on this arm
   requires, as `pick_input` does for `pick`.
9. `clear-report` or `clear`: nothing owed; `clear-report` when the latest `report_questions`
   visit sealed a list and routed to `decision_open`, and neither `classify_report` nor `wait`
   has been entered since, so the report that carried the questions is still to be classified.

**What an owed rule blocks, in one place.**

| Rule | Blocks the first dispatch of a run | Blocks a later dispatch | Sends `pick_facts` to `decision_next` |
|---|---|---|---|
| 1 carry | yes | never reached | yes, before the first dispatch |
| 2 unrecorded write | yes | yes | yes |
| 3 to 6 an owed message | yes | yes | yes |
| 7 a proposed entry | yes | no | yes |
| 8 an unjudged entry, not held | yes | no | yes |
| a held entry | no | no | no |
| an escalated entry that owes nothing | no | no | no |

`dispatch_check`'s `deferral-check.sh` prints `decision-owed` (to `decision_next`) for the
rows marked in the first two columns, and `pick_facts` prints `decisions` (to
`decision_next`) for the rows marked in the third. Nothing blocks `wait`. A coordinator that
needs a fact before judging holds the verdict with what it waits on, and the loop goes on:
`pick` can dispatch the worker that will find it, `wait` receives the evidence, and the
evidence brings the entry back to rule 8. `clear` goes to `pick_facts` and `clear-report` to
`classify_report`, so a "done, and one question" report goes on to `verify` as soon as its
questions are recorded and taken up, with its question settled, escalated or held.

Take-over is these same rules at the first dispatch: rules 1, 7 and 8 block it, so a
successor meets every carried, proposed and unjudged entry before it dispatches anything, on
every path to `dispatch_check`, including `reconcile` straight to `pick_facts` when the merge
posture is readable, and `reconcile` to `posture_ask` to `record` to `pick_facts` when it isn't. `reconcile` needs no edge of its own to `decision_next`; `pick_facts`'
`decisions` verdict routes it. Every decision write returns to `decision_next`, so owed work
never waits on `pick_facts`: the routes back through `rebrief` and `quiet_check` to `wait`
don't pass `pick_facts`, and don't need to.

**Send states.** Every message has a render state and a send state, the pair the template
already uses for `land` and `land_merge`. The render state (`escalate`, `decision_withdraw`,
`decision_reply`, `decision_redirect`) is a check: `decision-render.sh` reads the live entry,
refuses unless the entry owes the kind it is asked to render (so a second rendering of the same
owing can't happen), runs the shared validator, writes the text to the detail key
`coord/decision_message.txt`, seals it with `coord-log.sh seal --file --key`, and prints
`message <kind> <n> <round> [report:<seq>] [qseal:<seq>:<hash>] keyseal:<seq>:<hash>`, or
`refused` (routed to
`record_conflict`, since only a record changed underneath can cause it). The key's seal rides
in the verdict because a reader can check a key only against a seal the engine wrote, and the
capture is engine-written; `report:<seq>` names the report a redirect answers. The renderer
takes `--state` besides `--kind`, since it seals to the state it runs in. For an escalation it
also writes the structured form, `coord/decision_question.json`: the question, the context and
problem paragraphs, and the options as `{label, explanation}` with the recommended one first,
sealed the same way, its seal carried in the verdict as `qseal:` so the question-tool route asks
exactly what was rendered. The send state (`escalate_send`, `decision_withdraw_send`,
`decision_reply_send`, `decision_redirect_send`) shows the text; the coordinator sends exactly
that, runs `record-decision.sh --sent`, and submits `sent`, which returns to `decision_next`.
`--sent` refuses unless the key checks against the render's seal and the render names this
entry, kind and round, so nothing is marked sent that wasn't rendered as it stands, and a
message is owed until it is marked.

**Asking a person.** `escalate_send` for a person target is the one place with two routes,
both rendered from the same structured form. The coordinator asks with the AskUserQuestion tool
only when the person is already in conversation with it in its own session: the turn it is in
was started by a message from that person, not by a worker's report, a notification or a
scheduled wake. It prints the context and problem paragraphs in chat, then asks the question
with the recommended option first and every option's explanation. Otherwise, or when the tool
is unavailable, refused or times out, it sends the same content as a message and keeps
coordinating. The reason is the loop: a question asked of a person who isn't there must not
stop it, and the tool holds the session until it is answered, where a message leaves `wait`
free to take reports, hold verdicts and dispatch. `--sent --route tool|message` records which
route was used as an Evidence line on the entry. The answer comes back the same way on both:
the chosen option goes to `decision_answer`, from `escalate_send` itself on the tool route (it
submits `answered` with the decision and round) and from `wait` as an `answer` event on the
message route. A coordinator target is always sent as a message.

What `--sent` can't see is the bytes that went out: a coordinator that sends an edited text and
then marks it passes. For a coordinator target there is a check on the other end: the message's
last line carries the SHA-256 digest of the text above it, and the receiver's
`report-questions.sh` refuses an escalation whose body doesn't hash to it. For a person there is
none, and Security Considerations says so.

A crash after sending and before marking sends it again on the next run: the guarantee is at
least once. The receiver absorbs the duplicate by its first line: an escalation already opened
for that holding, entry and round opens nothing, and a reply identical to the answer that
settled an entry changes nothing.

The escalation reads:

```text
Decision <n> round <r>.

<context paragraph>

<problem paragraph>

<question>
1. <recommended option> (recommended: <reason>)
   <its explanation>
2. <other option>
   <its explanation>

Answer naming decision <n> round <r> and an option, or give another outcome with its reason.
Digest: <sha256 of every byte above this line>
```

Every option carries an explanation once the entry is escalated. It is stored in the Options
line itself, `<option> -- <explanation>`, so the codec's grammar doesn't change; the
recommendation names the option part, and the shared validator refuses an option without an
explanation, so `--escalate` and the renderer refuse the same entries.

A withdrawal names the decision and round and says no answer is needed; a reply names the
decision, the outcome, its reason and who decided; a redirect tells the worker its questions
go to the coordinator. Free-text cells are rendered with `@` encoded so a public record or
message never notifies anyone.

**Forms the scripts share.** An Outcome cell is written `<outcome>; reason: <reason>`, and the
reply renders both. A Decided by for an answer that came back down from a nested coordinator is
`coordinator <topic> (final: <decider>)`. A question addressed to a person is marked by an
Evidence line whose text starts `addressed to a person`, stamped with the report that carried
it, and a sent redirect by a line stamped `[<run> redirect <seq>]`, where `<seq>` is that
report's sequence rather than the sending visit's, so the redirect names the report it answers.
Stamps are read by position (the one ending the Source and the one after each Evidence line's
source), never from a line's text, so a source or a final decider holding a bracket is refused:
it could forge the stamp that follows it. The stamp kinds are `raise` (an `--open`), `report`
(`--open-from-report`, `<seq>.<item>`), `wait` (`--evidence` and `--answer`, the arrival's
sequence, which is `escalate_send`'s own on the question-tool route), `hold`, `ask` (an
escalation to a person marked sent, with its route) and `redirect` (the report's sequence). An
answer that settles an entry still writes an Evidence line with its `wait` stamp, so the
unrecorded-answer rule sees it recorded, and an identical answer sent again (same round,
outcome and decider) adds a line of its own, `answer for round <r> again: <outcome>`, with its
own `wait` stamp: the stamp alone says the arrival was recorded, and an answer line under
another stamp never stands in for it. A verdict mode needs the entry's Verdict empty, so one
visit to `decision_verdict` records one verdict.

When a write refuses because the record changed after the route (exit 65), the coordinator
submits the state's evidence anyway and `decision_next` routes from the record as it now
stands; a message already sent may go out once more, which the at-least-once guarantee below
already allows.

#### Alternatives Considered

**A confirm state after every write, and separate rules per concern.** Each write would go to
its own confirm check, as holdings go through `record`, and one-at-a-time, send-once and
take-over would each be a rule in the state that needs it (a guard in `escalate`, a marker
check in the renderer, a take-over pass in `reconcile`). This is how the template handles
holdings today and would be the smaller change to its shape. Rejected because the rules would
be spread across six states, each reading the record, a restart would need its own pass to
find what is owed (driver 6), and a failed write that creates an owing (an open, an answer)
would need its own confirmation rule; one predicate gives all of that from the same facts.

**The coordinator composes the escalation, and a check validates the text.** The directive
would ask for context, problem and question, and a check would parse the message for the
three parts. It keeps the coordinator's own voice in the message. Rejected because parsing
prose for "a context paragraph" is heuristic, and a check that passes a composed message can't
tell it matches the recorded verdict (driver 2). Rendering from the entry makes the verdict and
the message the same thing.

**A fifth state, `queued` or `held`, for an entry waiting its turn or a fact.** It would make
the wait visible in the State column, and `decision_next` could route on the state alone.
Rejected because such an entry behaves as `coordinator-verdict` in every respect that matters
(evidence resets it, it isn't with anyone, it can be re-judged), so a separate state would
duplicate every rule that applies to `coordinator-verdict`; the Verdict column already marks it.

**Blocking the loop until every entry has a verdict.** It is the simplest reading of "a verdict
before anything else". Rejected because a coordinator that needs a fact before judging could
then neither dispatch the worker who would find it nor wait for the evidence, which pushes a
hurried settle or a premature escalation: niwa#330 by another route.

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

Answers arrive only on the dispatcher's channel: as a message the coordinator names at `wait`
with `event: answer`, the `decision` and its `round`, or, when the person was asked in
conversation, as the AskUserQuestion answer `escalate_send` submits as `answered`. A worker's
report never produces one, since
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
decider named. When the lower coordinator withdraws instead, the upper entry is reopened, and
whatever it settles to afterwards owes nothing back down. An entry whose source is a worker
owes the same reply, sent as a message the way `rebrief` reaches the worker.

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

### Decision 5: Telling a decision from any other blocker in what a person reads

The niwa#330 row was free text in the `--blocked` flag. A row that asks for a decision has to
come from an escalated entry, but some needs are not decisions (a credential, a step the
workspace reserves, such as running a release) and still belong in "Blocked on you". And the
table isn't the only surface: `progress-view.sh`'s `--next` text fills the same column on any
row, and every report carries a free-text "Waiting on the human" section.

#### Chosen: decision rows from the record, closed need kinds, and the phrasing list behind both

`pick-facts.sh` adds the record's unsettled entries to `coord/pick.json`, read through
`record-decision.sh --list`, and `progress-view.sh` renders them:

- an entry escalated to a person: a "Blocked on you" row, Unit the question, Status `decide`,
  and "recommended: <recommendation>, because <reason>" in the last column; refused when
  either is empty;
- an entry escalated to a coordinator: an "Ongoing" row reading "with `<topic>` for a
  decision", asking the reader nothing;
- an entry `proposed` or in `coordinator-verdict`, queued: an "Ongoing" row reading "with me
  for a verdict"; held: "with me for a verdict, waiting on <reason>".

`--blocked <session>=<kind> <argument>` takes one of a closed set of need kinds, and the
renderer words the cell: `credential <name>`, `reserved-step <merge|release|close|teardown>
<pull request or issue link>`, `access <owner/repo>`. There is no free sentence left to write a
decision in. `--next` text, on any row, is checked against the decision-phrasing list and
refused on a match. The list is one file, `skills/coordinate/references/decision-phrasings.tsv`,
each row an extended regular expression matched case-insensitively by `grep -E` (no
back-references, so matching time is linear in the text) and whether it marks a decision or a
person-addressed question. It is read by `progress-view.sh`, `report-questions.sh` and
`need-check.sh`. Its fixtures, `scripts/testdata/decision-phrasings/`, hold at least three
refused and three accepted phrasings, including an accepted text that resembles a decision
("waiting on the release decision from the vendor"). The list is a backstop: rewording evades
it, and the structural rule (a `decide` row only from an escalated entry, needs only from the
closed kinds) is the gate.

The reports' free-text "Waiting on the human" section is replaced by the progress table's
"Blocked on you" rows, which the skill text and `references/loop.md` already require at the end
of every report after the reconcile. The reconcile report's own table (`reconcile-report.sh`)
lists in "Blocked on you" only the escalated entries and the reserved finishing steps, rendered
from the record and the posture. As merged, it also puts a holding whose pull request was
closed there, reading "decide: re-dispatch or drop" with no recommendation: a bare decision
row. That choice is the coordinator's, since it holds the dispatch, so the row moves to
"Ongoing" reading "with me: re-dispatch or drop", and a coordinator that can't make the call
raises an entry for it (`decision_raise`), which reaches a person only through a verdict. An
unconfirmed merge stays in "Blocked on you" as the reserved step it is. The escalated entries
reach the report through the reconcile facts: `reconcile-read.sh` carries them (question,
recommendation, reason, target), including a handoff's that the record doesn't carry yet, and
`reconcile-pass.sh` passes them on.

The `surface` state's blocker path gets the same rules. `surface` gains a `need` field, which
takes a need kind, and a third answer, `decision`, which goes to `decision_raise`; `blocker`
goes to a check state, `surface_check`, whose `need-check.sh` reads the need from the logged
evidence of the latest `surface` visit (`coord-log.sh evidence`), refuses one that isn't a need
kind or whose argument matches the list (back to `surface`), and otherwise seals it for sending
(to `wait`).

#### Alternatives Considered

**Free text checked only against the phrasing list.** It keeps `--blocked` as it is. Rejected
as the gate because a closed regex list is evaded by rewording; it stays as the check on the
text that remains free (`--next`, a need's argument).

**A declared decision flag on free text (`--blocked T=decision:...`).** It is explicit and has
no false positives. Rejected because the coordinator declares it beside free text, so a
decision declared as a plain need passes, which is the niwa#330 row exactly (driver 2); closed
need kinds leave no sentence to put a decision in.

**A decider classifying free text as a decision or a need.** A decider would catch phrasings
a closed list misses. Rejected as the check because its answer depends on a model and can't
be a deterministic refusal; deciders here stay in shadow (a `verdict` decider on
`decision_verdict` classifies authority, where judgment belongs, and is recorded, never
acted on).

## Decision Outcome

Decisions live in the record, in a fifth section rendered only when it has something to hold,
so every record on GitHub today stays canonical, and every stamp names its run, so a restart or
a second run against the same record never mistakes one run's writes for another's. One write
script changes that section; it runs only in the state each change belongs to, on the entry the
workflow routed, and refuses every transition outside the four-state machine and every verdict
missing a part; the general record writer and the record opener refuse to change the section
at all. Evidence clears any recorded verdict, so nothing reaches a person without a verdict
made after it. A verdict can be held with what it waits on, so a coordinator can go and find a
fact without being pushed into a hurried settle or a premature escalation.

One predicate decides what is owed, and one routing check, `decision_next`, sends the
coordinator to the next thing owed, in a fixed order: a carry, a write that didn't land,
withdrawals, replies, redirects, the escalation, taking up proposed entries, and verdicts. One
table says which of those block the first dispatch, which block later ones, and which send
`pick_facts` back to it; nothing blocks `wait`, and a close with an unanswered escalation
reports it and waits. Every message is rendered from the entry in a check state and marked sent
only against that render. The write that frees the one escalated slot releases the next queued
escalation.

Worker questions are caught in the coordinator's report intake, which every admitted report
crosses, holding or not; each becomes an entry the coordinator words for the record, so a
phrasing the list misses still can't reach the dispatcher unjudged, and no worker text is
pasted into a public record. The run's escalation target is fixed at open; an escalation from
below is a new entry at the receiver, and its settlement comes back down by entry and round.
The progress table takes decision rows from the record, takes needs only in closed kinds, and
checks every remaining free text against the phrasing list.

Against niwa#330: the worker's `/decision` choice is a settled entry whose source is the worker;
the person's mixed result, relayed by the dispatcher, is recorded as evidence, which clears the
old verdict, keeps the old outcome in Evidence, and moves the entry to `coordinator-verdict`;
`decision_next` sends the coordinator to `decision_verdict`, where it settles (keep option (d):
the record's flip condition didn't happen and its consequences accepted the clone moving); the
worker's "please decide whether to ship" arrives in a report, is extracted as an addressed
question, opened as a new entry with a redirect owed, taken up and settled with the same
reasoning. The messages rendered are the redirect and the replies to the worker. Nothing
reaches a person.

## Solution Architecture

### Record

- `record-codec.jq`: the `decisions` section with its `Next decision` line, the stamp grammar,
  section-aware cell grammars and optional columns, per-state required columns, identifier
  uniqueness and bound, the shared escalation validator, compaction of settled entries that
  owe nothing, `@` encoding in the free-text columns, the omit-when-empty render, a parse and
  handoff split that takes a fifth section only by its title, `decisions` in the allowed
  top-level keys, and the handoff filter to unsettled entries.
- `record-write-core.sh` (new): the write core (parse, compare-and-swap, visibility, the
  60,000-byte budget with its own exit code, render, edit), sourced only by the write scripts.
- `record-common.sh`: keeps its no-write contract and gains the stamp helpers. As merged, the
  named-repository scan over the Decisions text columns is in the write core, and the codec
  refuses home-directory paths and token-shaped strings in them. The three refusals are
  narrowed so they don't catch ordinary prose.
  The scan over free text takes only the unambiguous forms of a repository reference, a
  `github.com/<owner>/<repo>` link and `<owner>/<repo>#<n>`; the bare `<owner>/<repo>` scan
  stays on the cells that hold nothing else (Holdings Repo, Side effects Target), so "and/or",
  "n/a" or "CI/CD" in a question are never read as a repository. A token shape must start at
  the start of the text or after a character that can't be part of a name, so a kebab-case
  name that contains `sk-` isn't refused. A home-relative path (`~/.config`) names no user and
  is accepted; a path under `/home/<user>/` or `/Users/<user>/` is refused.
- `record-write.sh`, `record-holding.sh`: call the write core; `record-write.sh` refuses a body
  whose Decisions section differs from the live one's. Exit 13 (`record-full`) is in both
  scripts' exit-code contracts, and `dispatch-common.sh` reports it as a full record rather
  than a generic write failure.
- `record-write-core.sh`: its header states what a caller must provide (a `usage` function, no
  `set -e`, no EXIT trap of its own before the call) and that `core_write` takes over `T` and
  the EXIT trap and exits on every refusal. A structure test keeps `DECISIONS_WRITER=1` out of
  every script but `record-decision.sh`.
- `record-open.sh`: refuses a body that has a Decisions section.
- `reconcile-salvage.jq`: the row-by-row reader reconcile falls back to on a non-canonical
  record takes the fifth section too, so a record or handoff with a Decisions section and one
  bad row is salvaged rather than read as unreadable.
- `closeout-read.sh`: a `decisions` stage before `ready` at roadmap scope, blocking on an entry
  that is unsettled or still owes a message, the same test compaction uses; the handoff check
  expects the filtered section.
- `predecessor-handoff.sh`: its key list gains `decisions`, and it copies the section as it
  stands.

### Scripts

| Script | Run by | Does |
|---|---|---|
| `record-decision.sh` | the coordinator, in the decision states | The only writer of the Decisions section; the mode table in Decision 3; `--list` and `--read` for every reader; exit 65 and nothing written on any other transition, a missing verdict part, or a mode run outside its state |
| `decision-next.sh` | `decision_next`'s action; `--owed` for `deferral-check.sh` and `pick-facts.sh` | The one owed predicate; prints the sealed next-owed verdict; writes `coord/decision.json` for a verdict |
| `decision-render.sh` | the render states' actions | Renders an escalation, withdrawal, reply or redirect from the live entry through the shared validator, refuses when the entry doesn't owe that kind, seals the text with `coord-log.sh seal --file --key` |
| `report-questions.sh` | `report_questions`'s action | Extracts, caps and classifies a report's questions, honoring citations and first lines only from their own holding and checking a coordinator escalation's digest; seals the list |
| `need-check.sh` | `surface_check`'s action | Reads the need from the latest `surface` evidence, refuses one outside the need kinds or matching the phrasing list, seals the rest |
| `phrasing-lib.sh` | sourced by `progress-view.sh`, `report-questions.sh` and `need-check.sh` | The phrasing list's one reader: `phrase_match <decision\|addressed> <text>` exits 0, 1, or 2 for "can't check" (never read as no match); rows of kind `both` count for each |
| `deferral-check.sh` (changed) | `dispatch_check`'s action | The `decision-owed` verdict, from `decision-next.sh --owed dispatch` |
| `pick-facts.sh` (changed) | `pick_facts`'s action | Adds unsettled entries to `coord/pick.json`; the `decisions` verdict from `decision-next.sh --owed pick` |
| `progress-view.sh` (changed) | the coordinator | Decision rows from the record; `--blocked` takes need kinds; `--next` refuses decision phrasings |
| `coordinate-open.sh` (changed) | the coordinator | `--reports-to <topic>` to `REPORTS_TO` |
| `coord-log.sh` (changed) | the scripts | `current`, the state the session is in now |
| `render-brief.sh` (changed, dispatch path's) | `dispatch-worker.sh` | The fixed channel sentence, the `Questions:` shape and the repeat-unanswered instruction in Reporting |

`coord-verdict.sh` gains codes for the new words, taken from the first free block on the
default branch the work starts from. On that branch the dispatch path added no verdict word,
reconcile added `reconciled` (140), and the record reader added `decisions` (136), so the first
free block is 150:

| State | Words and codes |
|---|---|
| `dispatch_check` | `decision-owed` 45 |
| `pick_facts` | `decisions` 136, the code `roadmap_close` already routes |
| `decision_next` | `carry` 150, `unrecorded-open` 151, `unrecorded-answer` 152, `unrecorded-evidence` 153, `unrecorded-raise` 154, `withdraw` 155, `reply` 156, `redirect` 157, `escalate` 158, `take` 159, `verdict` 160, `clear` 161, `clear-report` 162, `record-full` 163 |
| `report_questions` | `questions` 170, `overflow` 171, `unreadable` 172, `none` 11 |
| the render states | `message` 180, `refused` 62 |
| `surface_check` | `accepted` 190, `refused` 62 |

`coord-verdict.sh` routes on a token's first word, so each route has its own word; `refused`,
`none` and `decisions` reuse their existing codes, which the table allows because it is
global and each state has its own arms. `rendered` is already `predecessor_handoff`'s 110, and a second label for it in the
`case` would never run, so the render states print `message` instead, and
`coord-verdict-table_test.sh` gains a check that no word appears twice.

### Template states

| State | Kind | Action and checks | Routes |
|---|---|---|---|
| `decision_next` | check | `decision-next.sh`; `decision_input` on the verdict arm | `decision_carry` on `carry`; `decision_open`, `decision_answer`, `decision_evidence`, `decision_raise` on the four `unrecorded-*` words; `decision_withdraw`, `decision_reply`, `decision_redirect`, `escalate`, `decision_take`, `decision_verdict`; `classify_report` on `clear-report`; `pick_facts` on `clear`; `record_conflict` on `record-full` |
| `decision_carry` | agent | `record-decision.sh --carry` | `decision_next` on `carried` |
| `decision_take` | agent | `--take` | `decision_next` on `taken` |
| `decision_verdict` | agent, shadow decider on `verdict` | For a question that isn't obviously answerable, the directive has the coordinator run `/shirabe:decision` first, to reach one recommendation and the real alternatives; then `verdict: settle` runs `--settle`, `escalate` runs `--escalate`, `hold` runs `--hold` | `decision_next` on each |
| `escalate`, `decision_withdraw`, `decision_reply`, `decision_redirect` | check | `decision-render.sh --kind escalation`, `withdrawal`, `reply` or `redirect` | the matching `*_send` on `message`; `record_conflict` on `refused` |
| `escalate_send`, `decision_withdraw_send`, `decision_reply_send`, `decision_redirect_send` | agent | send the rendered text, then `--sent`; for a person target, `escalate_send` asks with AskUserQuestion when the person is in conversation (see "Asking a person") | `decision_next` on `sent`; `escalate_send` also `decision_answer` on `answered` |
| `report_questions` | check | `report-questions.sh` | `decision_open` on `questions`; on `none`, `classify_report` after a holding and `wait` otherwise; `rebrief` on `overflow`; `surface` on `unreadable` |
| `decision_open` | agent | `--open-from-report` | `decision_next` |
| `decision_raise` | agent | `--open` | `decision_next` |
| `decision_answer` | agent | `--answer` | `decision_next`; `decision_apply` when the answer reverses or extends a supplied decision |
| `decision_evidence` | agent | `--evidence` | `decision_next` |
| `surface_check` | check | `need-check.sh` | `wait` on `accepted`; `surface` on `refused` |

Changed edges: `wait` gains the events `answer`, `evidence` and `raise` and the fields
`decision` and `round`; `pick_facts` gains `decisions` to `decision_next`; `roadmap_close`
gains its `decisions` stage to `roadmap_blocked`, as its other four blockers go, whose `noted`
returns to `wait`, where an answer arrives; `report_facts`' three arms go to `report_questions`;
`failure: escalate` goes to `decision_raise`, since escalating a failure asks the dispatcher to
decide; `surface` gains `need` and the answer `decision` (to `decision_raise`), and `blocker`
goes to `surface_check`; `dispatch_check` gains `decision-owed` to `decision_next`.
`classify_report`'s `blocked` answer stays: a report blocked on a step that isn't a choice
still surfaces, now through `surface_check`. The template's description, which says every
spoke that changes the record returns through `record`, gains the decision writes, which
return through `decision_next` instead. The structure test gains a check that no cycle in the
template is made of check states only, which is what the close would have been without the
`roadmap_blocked` route. One pair of edges is such a cycle by design and is exempted by name:
`decision_next`'s `clear` to `pick_facts` and `pick_facts`' `decisions` back. It can't turn
twice without a write between, because `decision-next.sh --owed pick` fires on exactly the
rules whose absence is `clear`, read in one pass over the same record.

Each render state's gate has its own name (`escalate_verdict`, `decision_withdraw_verdict`,
`decision_reply_verdict`, `decision_redirect_verdict`), since a gate name is shared across
templates and one name must mean one command.

`decision_verdict` declares a decider on `verdict` (`settle`, `escalate`, `hold`), its input
`coord/decision.json`, every answer shadow, with fixtures in
`coordinate.decision_verdict.verdict.decider.jsonl`, at least one per answer, and rows in
`scripts/decider-declarations.tsv`.

### Data flow for one escalation

```
report_facts -> report_questions --(questions)--> decision_open -> decision_next
decision_next --(take n)--> decision_take -> decision_next
decision_next --(verdict n)--> decision_verdict --(escalate)--> decision_next
decision_next --(escalate n)--> escalate --(message)--> escalate_send --(sent)--> decision_next
wait --(answer n)--> decision_answer -> decision_next
decision_next --(reply n)--> decision_reply --> decision_reply_send -> decision_next
decision_next --(clear-report)--> classify_report | --(clear)--> pick_facts
```

## Implementation Approach

Implementation starts from a default branch that contains the dispatch path (shirabe#404)
and reconcile (shirabe#406), and uses the koto floor shirabe declares then (0.14.1). It lands
in two pull requests.

The seams this design names were re-read against that branch before the second pull request
started. They hold as described, with these differences, which the sections above now carry:
`reconcile` reaches `pick_facts` directly when the posture is readable; the reconcile report
puts a closed pull request in "Blocked on you" as a bare decision (Decision 5 moves it); the
koto floor is 0.14.1; and the first free verdict block is 150. `take_report` gates
`worker_report` and checks a leg report against the result koto holds; a message report fills
it with the relayed text and a leg report with a fixed line of the result's fields; both set
`report_topic`, which is the source when there is no holding. `report_facts` prints `holding`
(60), `unknown` (61) or `refused` (62). `render-brief.sh`'s Reporting section asks for
"numbered questions" with no fixed heading, so the `Questions:` shape is new. Its `decisions`
input key holds decisions already made and passed to a worker, a different thing from the
record's section of the same name. `coord-log.sh` has every reader the scripts need except
`current`.

The first carries the record change alone: the phrasing list, the Decisions section in the
codec, the write core, and the refusals in `record-write.sh` and `record-open.sh`. It writes no
entry. What it buys on its own is forward compatibility: the parser on main today refuses a
fifth section outright, so a coordinator still on an older plugin, restarted against a record
a newer one has written, stops at `record_conflict`. Releasing a reader of the five-section
record before any release writes one closes that window. It also touches the two most
safety-critical files, the codec and the write path, and is reviewable with the existing suite
unchanged.

The second carries everything else, in this order, each step what the next one calls:

1. **Seams.** Re-read the merged dispatch path and reconcile and confirm each seam this design
   names (`take_report`, `worker_report`, `report_facts`' arms, `render-brief.sh`'s Reporting
   section, reconcile's report, the verdict words both add), correcting the design where they
   differ.
2. **The acceptance harness.** The niwa#330 replay and the three-level round trip as engine
   tests written first, against stand-ins for the scripts, so every later step is measured
   against them; the replay also runs against a template variant whose evidence edge goes
   straight to `escalate`, where it must fail.
3. **The renderer.** `decision-render.sh` for the four kinds.
4. **The question extractor.** `report-questions.sh`, with a contract test that a report
   written to the brief's `Questions:` shape parses.
5. **The write script.** `record-decision.sh`, every mode and refusal.
6. **Routing and the template.** `decision-next.sh` and its `--owed` mode, the guard, the
   `pick_facts` and `roadmap_close` routes, `need-check.sh`, `REPORTS_TO`, the states and
   edges, the verdict codes and the decider.
7. **The brief and the progress table.**
8. **Skill text.** SKILL.md, the references, rule coverage and an eval.

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
  verdict before anything goes to anyone. A fixed first line is honored only from a holding
  dispatched as a coordinator, and the source is taken from that holding, not from the line.
- **Stale and duplicate messages.** Every escalation, withdrawal and reply names its round,
  and an answer for an earlier round is evidence rather than a settlement. A message re-sent
  after a crash between sending and marking is absorbed by its receiver: an escalation already
  opened for that holding, entry and round opens nothing, and a reply identical to the answer
  that settled an entry changes nothing. Stamps name their run, so no run's write is mistaken
  for another's.
- **Checks read what the coordinator didn't write, up to the send.** Every routing verdict
  comes from GitHub, the session log, or a capture the engine wrote. Content a later step reads
  (the question list, a rendered message, the next-owed entry) sits in a detail key sealed to
  its visit with `coord-log.sh seal --file --key`, and the reader refuses a key that doesn't
  check. A seal's hash has no key (`coord-log.sh`), so it guards against a stale or mismatched
  value, not against a coordinator that forges one deliberately. Nothing checks the bytes the
  coordinator actually sends to a person; a message to a coordinator carries its digest, which
  the receiver checks.
- **The coordinator's relay and other paths no check reads.** A message report reaches
  `worker_report` as the text the coordinator relayed, so a coordinator that drops a question
  from its relay isn't caught; the question check holds against the worker, and the leg path
  is checked against the result koto holds. A worker's pull request body and comments are a
  durable path to a person that no check reads. Questions extracted but not yet recorded when
  the coordinator crashes are recovered only by the worker repeating them, as its brief asks.
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
- Open decisions survive restarts, second runs and rotations, and no first dispatch happens
  while one is owed a step.
- A coordinator can hold a verdict while it finds a fact, without stopping the rest of its
  loop.
- Nesting needs no special case: a coordinator's escalation is a report to the one above, and
  its answer comes back by entry and round.
- The progress table can't carry a bare "decide" row.

### Negative

- The record's Decisions table is nineteen columns wide, which reads poorly on GitHub.
- Every worker question becomes an entry, including trivial ones a coordinator would have
  answered in a line; each costs a take and a verdict write, plus the coordinator's wording.
- The decision loop adds eighteen states and a routing check to an already large template.
- A closed phrasing list misses phrasings. In a report that is harmless, since every question
  becomes an entry; in `--next` text or a need's argument a missed phrasing can reach the
  table.
- Messages are sent at least once, not exactly once, and what goes to a person isn't checked
  byte for byte.
- Version skew: a coordinator on a plugin older than the first pull request stops at
  `record_conflict` on a record with a Decisions section. It fails closed, and releasing the
  reader first keeps the window short.

### Mitigations

- Settled entries that owe nothing are compacted, leave a rotation's record at its end and a
  roadmap's at its close, and the write core refuses a body near the size ceiling; the width is
  the price of every field being a visible table cell, which the record's no-hidden-copy rule
  requires.
- A trivial question settles in two writes with no message to anyone but the worker.
- The new states follow the existing check-state and send-state patterns and the global
  verdict table, and each has a passing and a failing test.
- The phrasing list is one file with fixtures, so a missed phrasing found in use is a one-line
  addition with a test; needs come only in closed kinds.
- The round in every message's first line makes a duplicate recognizable to whoever receives
  it.

### Known follow-ups

Review of the implementation left these open, each judged minor or failing closed, and each
tracked in shirabe#539:

- A relayed escalation prefixed with `- `, `| ` or a non-breaking space is still read as a
  worker's question with its digest unchecked (shirabe#539).
- A withdrawal's question line is only checked non-empty, so a relay that rewrites it is
  honored (shirabe#539).
- A zero-padded decision number in a withdrawal isn't recognized as one (shirabe#539).
- `--carry` matches handoff entries by number alone, so a clash is skipped silently and can
  leave two entries escalated (shirabe#539).
- Compaction is split between the codec and the writer, with dead code in the codec's part
  (shirabe#539).
- The 60,000-byte budget is hard-coded in the writer's live read, apart from the write core's
  (shirabe#539).
- A few exits misname their cause: a failed evidence read reports a refusal, and a record past
  the parser's limit exits 10 rather than `record-full` (shirabe#539).
- The compare-and-swap reads only the `Written:` line, so a hand edit that leaves it unchanged
  is overwritten by the next write (shirabe#539).
