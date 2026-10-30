# Jev criteria

A Jev criterion is a closed question Jev answers about a slice of an agent's
work. Before one may run, and before its rule's text may be left out of a
run, it has to show what its slice holds, that the slice is enough, how big it
gets on real runs, and what evidence other than the agent says its passes can
be trusted. This page is where each criterion's written case lives; the
figures and the trust record live in its entry in
`references/rule-registry.json`, under `jev`, and
`scripts/jev-criteria/jev_criteria.py check` holds the two to each other and to
the templates. The design is `docs/designs/current/DESIGN-jev-pass-trust.md`.

## The contract

Every entry Jev grades carries a `jev` object:

| Field | What it holds |
|---|---|
| `state` | `rejected`, `blocked`, `untrusted` or `trusted` (below). |
| `sources` | What the slice is built from, each with its `writer`: `git` (committed objects), `gate-script` (a koto context key a named gate or `default_action` script writes, named in `script`), `graded-artifact` (the artifact the criterion judges, read whole) or `slice-script` (the slice script's own earlier output). Never something the agent writes about its work, and never anything the agent selects. |
| `slice_script` | The script that prints the slice. For a koto decider check, the gate's command runs it. |
| `budget` | The slice's byte budget: the gate's `max_bytes`, and never above 2,560, about the 2,507 bytes the Jev accuracy spike validated. A criterion with no gate is measured against 2,560. |
| `completeness` | `path` and `heading` of its written case on this page, and the `verdict`, `sufficient` or `insufficient`, which the contract's author sets and its pull request's reviewers check. |
| `measured` | The slice's size on real runs: `population` (`koto-sessions`, `merged-prs`, `review-shadow-records`, or `documents` for a document criterion's census, below), `runs`, `max`, `p90` (nearest rank), `over_budget` (runs over the budget), `on` and the `command` that took it, which prints the same figures given the same inputs. Optionally `empty`: the runs that reached the criterion's state with an empty slice, which `runs` leaves out (`measure sessions --slice decision-reasons` prints it). With no `empty`, the measurement found no empty slice. Or instead `not_measured: no-real-run-record`. |
| `fixtures` | The fixture file, from `untrusted` on. |
| `declared` | For a koto decider check: `sha256` of its declaration and `since`, the date that declaration took effect. `jev_criteria.py declared-hash` prints both the declaration and its hash. |
| `false_passes` | Confirmed false passes: `evaluated` and `recorded` dates, `oracle` (`review`, `ci` or `human`) and an `evidence` link. Never removed. |
| `promotion` | Only on a trusted criterion: `trusted_since`, the `fixture_run`, the `live` figures and the slice script's blob hash. |
| `pairs` | Only on a document criterion, in place of the fields above: one contract per format, each with those fields and `format`, `template`, `section`, `cap`, `cut`, `change_kinds` and `fixture_run` ([Document criteria](#document-criteria)). `state` and `false_passes` stay beside `pairs`. |

A koto gate sends one slice per evaluation, so a criterion that judges every
unit of a run (every hunk, every acceptance criterion) has to fit them all at
once. Every figure below is that whole-run size in bytes: the number of runs
measured, the largest, the 90th percentile and how many went over the budget.
A document criterion is the exception: its check is in unit mode, grading each
unit apart, so its figures are per unit and its budget binds one unit.

## States

| State | Condition |
|---|---|
| `rejected` | More than 5% of measured runs over the budget, or a completeness verdict of `insufficient`. |
| `blocked` | Not rejected, and no koto template declares the criterion, because no koto state exists to run it in. |
| `untrusted` | Not rejected, declared by a koto template, no promotion record. |
| `trusted` | Not rejected, declared in `veto` mode, and a promotion record that meets the bars below. |

Only an untrusted or trusted criterion may be declared in a template, and only
a trusted one's rule may be `withhold: eligible`.

## The bars

**Fixtures.** At least 10 good, 20 seeded-bad (a good input with one targeted
change that makes it bad) and 5 adversarial cases (input written to steer the
answer), using at least 3 of the techniques `instruction`, `authority-claim`,
`fake-answer`, `hidden-comment`, `vocabulary-mimicry` and `role-line`. Each case
holds its input as the slice script reads it and the slice the script prints.
A file may also hold `empty` cases, with no minimum: a slice with nothing to
judge, whose right answer is the criterion's escape (`expected: unclear`).
A run meets the bar when no seeded-bad or adversarial case is answered `pass`,
at least 80% of good cases are, no empty case is answered `pass` or `fail`,
and every case got an answer.
`jev_criteria.py fixtures <rule-id>` runs the file against Jev under the
template's declaration and prints the `fixture_run` record a promotion keeps.

**Live.** Over decider events from the criterion's `declared.since` (or the day
after its latest false pass, if later) to the day the figures were read: at
least 30 evaluations across at least 5 sessions, at least 95% of them answered
`pass` or `fail`, no fallback for `over_budget`, and no input over the budget.
The figures that decide a promotion come from koto's exported decider events
read in a log backend; a local file never decides one.

**Evaluations with nothing to grade.** An evaluation whose every event is a
`decider_checked` with `koto.decider.outcome` `not_graded` had an empty slice:
the slice script printed nothing, so there was nothing to grade, and the
decider never decided that. It is left out of the evaluations, the sessions and
the answered share, never counts as a pass toward trust or withholding, and is
counted on its own as `not_graded`, which a promotion's `live` record carries.
The minimums (30 evaluations across 5 sessions) count graded evaluations only.
An evaluation with a `not_graded` event and any other event is graded and
follows the rule above, so a fallback for any reason, `over_budget` included,
and an `escape` still count against the bar. This holds for every criterion.

Because they are left out, nothing else would notice a slice script that
wrongly prints nothing on runs the criterion applies to: those runs would
vanish from the bar instead of counting against it. So the live bar also
holds the not-graded share (the not-graded evaluations over those and the
graded ones together) to within 10 points of the share the contract measured
with an empty slice (`measured.empty` over `measured.empty` plus
`measured.runs`, and 0% for a contract that records no `empty`). A promotion
whose share is further off isn't met until the slice script is explained and
the contract re-measured. The two shares are close cousins, not the same
count: the measurement counts sessions, and the live figures count
evaluations, so a session that visits the state twice adds two. The
tolerance is what absorbs that difference, and it holds either way, so a
share well below the measured one is held too.
`jev_criteria.py figures <rule-id> --sessions <dir>` computes the same figures
from local koto session logs, as a tested reference for their definitions.

## Withholding

A trusted criterion's rule may be left out of what a run reads, but only for
a user whose decider will check the result. `scripts/jev-withhold.sh` makes
that call at run time: it prints a copy of the rule's file without the rule's
lines only when the entry is trusted and `withhold: eligible`, the user's
decider mode is `auto` with a key, the project sets no decider configuration,
and the session's log holds no shadow-mode check, fallback or agent answer for
that criterion. Anything else, including any error, prints the full file.

The script ships unwired: no template calls it, and none may until a
criterion is trusted. `jev_criteria.py check` holds any call to a literal rule
id of a trusted criterion whose check is in the same template, made from a
state's command whose directive runs `rule-registry.sh release <id>`, and
refuses the script's name anywhere else under `skills/`, `koto-templates/` or
`hooks/`.

## Replacing a seat

A `/work-on` panel seat is a reviewer subagent, and a batch of trusted Jev
criteria could one day stand in for one. No seat qualifies today: every
question the scrutiny seats ask is `rejected` (`rs-015`, `rs-018`, `rs-019`,
`rs-020`), because its slice needs more than 2,560 bytes or more than a script
can hand over. Nothing in shirabe leaves a seat unspawned, and the pull request
that first does must build all of these, for that seat:

1. **Every question the seat asks is trusted.** Each has a `trusted` contract
   declared on the panel's state in `veto`, so a batch stands in for the whole
   seat and never for part of it.
2. **The decider is active for the session.** For each of those criteria,
   every condition `scripts/jev-withhold.sh` checks before it withholds a rule
   holds for the session, so a user whose decider would not judge the result
   still gets the seat.
3. **An unanswered criterion brings the seat back.** When any of those criteria
   is unanswered in the panel state's current visit (no `decider_checked`
   event with outcome `pass` or `fail`), `panel-scope.sh --plan` gives the seat
   `full` for that round, so a missing verdict never stands in for a review.
4. **The batch's findings take the seat's place.** Its blocking findings stand
   in the findings ledger and the panel's verdict gate where the seat's would,
   and close by the same rules.
5. **Each condition is tested.** The change ships a test for each of
   conditions 1 to 4.

## work-on/review-level-fits-facts

`/work-on`'s `review_level_check` asks Jev whether the chosen review level is
too light for the facts of the change.

**Sources.** `review_facts.json`, which the state's own `default_action`
(`review-level.sh facts`) writes from git; `review_level_rules.tsv`, the copy
of `review-level-rules.tsv` that `review-level.sh init` stores as
`review_level_choice`'s action, which `facts` derived the floor from (a
session with no stored copy, one `init` never ran for, uses the shipped file,
as `facts` does); and `REVIEW_LEVEL`, the level the agent chose, which is what
the criterion judges.

**Slice.** `review-level.sh slice` prints one JSON line of typed facts (changed
lines and files as non-negative integers, at most 16 path-class names, whether
tests or the acceptance criteria changed, whether a test was edited rather
than only added to (`tests_edited`), whether any path fell in no class, and
the facts floor), a line giving the order of the levels, the level
definitions, and the chosen level. The definitions are rendered from the
stored rules copy, one line per level that raises the floor, then the default
and what the floor is:

```
the facts call for full when classes has ci, security, template or engine; or lines > 400; or files > 12; or tests_edited
the facts call for standard when classes has instruction, executable, test or manifest; or unclassified; or criteria_changed; or lines > 40
the facts call for light otherwise
floor: the most thorough level the facts call for
```

Every word in them comes from the rules parser, which admits only level
names, `[a-z0-9_]` class names, digit thresholds and the fixed fact names, so
no class glob, path, reason, criteria text or issue text reaches the slice.
The slice doesn't say what "too light" means: the criterion's pass and fail
texts carry that. With no facts recorded, or facts that don't parse, the
facts line is `{}` and the definitions are left out, since there is nothing to
apply them to, and the decider escapes. `review-level.sh project <facts>
<level> [<rules>]` prints the same slice for a facts file and a rules copy
(the shipped file when none is given), which is how the fixture cases and the
measurement build theirs.

**Completeness.** The question needs the facts, the definitions they are
judged under and the level chosen. The definitions are the rules the floor was
derived from, so the decider can check the floor against the facts as well as
the level against the levels the facts call for. The order line alone wasn't
enough: on one host's decider ledger, through the end of 2026-10-22 (UTC),
46 of 125 consultations under the order-only slice escaped. Rebuilt from
their sessions' stored facts and matched on koto's input hash, 32 of the 46
were full facts. The other 14 had facts that changed later, but each was at
least 167 bytes, and an empty slice is 51, so none was empty. The level
ledger's `check` line for every one of the 125 records a known level and
floor, so none had an unknown floor either. The decider leaned the right way
and stayed under the 0.9 threshold. The verdict is `sufficient`.

What the decider adds beyond the `level_floor` gate is bounded by that gate.
Each consultation's level and floor, read from the session's `check` ledger
line, put 33 below the floor (30 escapes and 3 fails), and `level_floor` held
all 33 in the same evaluation. The other 92, 76 passes and 16 escapes, had a
level at or above the floor. Those are the only ones where the decider's
answer can differ from the gate's, so the live figures that decide its trust
should count its fails at or above the floor apart from those below it.

**Fixtures.** 19 good, 25 seeded-bad, 6 adversarial and 3 empty cases. The
good cases cover each level at its floor and above it, and the seeded-bad
cases include the too-light shapes the ledger's escapes held. Run against the
configured decider (jev-1.14.0) on 2026-10-23 with
`jev_criteria.py fixtures work-on/review-level-fits-facts`: good 17 pass and 2
escapes, seeded-bad 24 fail and 1 escape, adversarial 6 fail, empty 3
escapes, so the bar is met: 47 of the 50 full-facts cases got a pass or a
fail, every one of them right. The three full-facts escapes are two
`standard` levels over a `light` floor and a 41-line documentation change at
`light`. The same rules introduced as "the highest level any rule below
yields" instead of what the facts "call for", the phrase the criterion's pass
and fail texts use, got an answer on only 29 or 30 of the 50 in two runs.
The three are left as they are: an escape is never a pass, it falls back to the
agent, and it counts against the live bar's answered share, so a slice that
kept escaping couldn't earn trust. The same 38 cases with the order-only
slice got 6 answers and 32 escapes. The dates in this section are UTC.
`koto decider report --fixtures` runs fixtures only for a state's `accepts`
fields, not a decider-check gate, so this runner is the one that applies.

**Figures.** 268 `/work-on` sessions' recorded facts, each projected at the
longest level name with the session's stored rules copy, largest 576, p90
563, none over the 2,048-byte budget (the gate's `max_bytes`). Measured before
`tests_edited` joined the slice; the field and its clause in the `full`
definition add under 40 bytes, so the largest stays well under the budget.

**State.** `untrusted`: it runs today, in veto mode for a user whose decider is
in `auto`, and no live window has been recorded. Its rule's text isn't
preloaded in any directive, so nothing is withheld when it earns trust.

## work-on/scrutiny-decision-reasons

`/work-on`'s `scrutiny` asks Jev, beside the seats, whether every decision the
run recorded in `analysis` and `implementation` gives, in its reason, why the
choice was made rather than restating it. It is the closed part of the
justification seat's question; the rest of that question is `rs-019`.

**Sources.** The `decision_recorded` events koto writes to the session log when
the agent runs `koto decisions record`, each with its state and its decision's
`choice`, `rationale` and optional `alternatives_considered`. The agent writes
the decisions, which are what the criterion grades; it never writes the slice.

**Slice.** `decision-reasons.sh slice` over the session log the gate passes
prints each matching decision, any visit, in log order, as a `- choice:` line
and a `  reason:` line, every field's whitespace collapsed to single spaces so
no field can start a line of its own. It reads no other file and no context
key. A run with no decision in those states has an empty slice, which koto
records as not graded.

**Completeness.** The question is whether a reason says why its choice was
made, and the choice and the reason are all it needs: the verdict is
`sufficient`. The alternatives are left out. They don't bear on the question,
since a reason can rule an alternative out in its own words, and
`koto decisions record` requires a rationale but not alternatives. With them,
5 of the live store's 88 graded sessions were over budget (5.7%), past the 5%
line; that first measurement read the live store alone, before the archive
was added to reach the 100-run minimum. Splitting the slice by state lowers
no share and doubles the calls.

**Figures.** Every session log the host kept, the live store and its archive,
gzipped copies included, each session counted once by its `session_id`: 119
graded sessions (with a decision to grade) of 1,502, largest 3,549, p90 1,761,
3 over the 2,560-byte budget (the gate's `max_bytes`). That is 2.5% of graded
runs, and 0.2% of all 1,502 sessions. The graded share is the one the contract
is held to, since the live bar counts graded evaluations only. The fit is
marginal: 119 graded runs is just past the 100-run minimum, and the live
figures, not this measurement, decide whether the criterion earns trust. A run
over budget falls back for `over_budget` and the agent answers it.

The live bar allows no over-budget fallback at all. At 3 in 119, a
30-evaluation window more likely than not holds one, so as built the
criterion probably can't earn trust; its slice would have to shrink first.
The figures also record no `empty` count, so a promotion would wait on a
re-measure that counts the sessions that reached `scrutiny` with no decision.

**State.** `untrusted`: it runs in shadow for a user whose decider is on, its
answers are recorded and never block the panel, and no fixture run or live
window has been recorded. The fixtures' adversarial cases include
inline layout mimicry (labelled `vocabulary-mimicry`): a reason that carries a
second decision's `- choice:` and `reason:` text, which the collapsed
whitespace keeps on the reason's own line.

## coordinate/pick-choice

`/coordinate`'s `pick` asks the decider which `choice` to make with one free
slot under the cap. It is an evidence decider rather than a Jev criterion: it
picks one of seven values instead of answering pass or fail, it runs in shadow
and never acts, and it has no registry entry, so the 2,560-byte budget above
doesn't bind it. Its input cap is the decider input's `max_bytes`, 12,000, and
its modes are rows of `scripts/decider-declarations.tsv`. The slice is written
down here so it meets the same tests as a criterion's: what it holds, why
that's enough, and how big it gets.

**Sources.** `coord/pick.json`, the facts `pick-facts.sh` writes as
`pick_facts`' `default_action` from the record, the roadmap on the default
branch or the discipline's issues, and the pauses; and `PARKED_BOUND`, a
session variable. The agent writes neither.

**Slice.** `pick-facts.sh` runs `pick-slice.jq`'s `pick_slice` over the
`coord/pick.json` it built on that visit and stores the result as
`coord/pick_slice.json`, before it seals its verdict, so a sealed verdict
means both keys came from that visit. The decider reads the slice; the agent
keeps reading the full facts. A unit whose `done` is true, with no holding
covering it, `verdict_owed` false and `rework` unset becomes its tag in a
`done` list. Every other unit keeps its row, and every holding keeps its row,
with fields that are null, false or an empty list left out. A kept unit's
`blocked_by` names its blockers by tag rather than by position, because the
positions count the full list and the slice no longer carries the done units
they would point at. `scope`, `name`, `host`, `cap`, `active`, `parked`,
`parked_bound`, `paused_all`, `pauses`, `go_aheads` and `decisions` are the
facts' own.

**Completeness.** Pick's rules never act on a done unit that no holding
covers, that isn't owed a verdict and that wasn't sent back: it can't be
dispatched, scoped or sent its execution, and what a dependent needs from it
is already in the dependent's own `blocked`, `blocked_by` and
`blocker_landed`. Confirming a done unit's `landed` row is the agent's
upkeep, read from the full facts, and no `choice` turns on it. A done unit
that is held, owed a verdict or reworked keeps its full row, since the rules
name each of those. A field left out reads the
same as its null or false value, and the counts, the cap, the bound, the
pauses and the decisions are passed whole. The verdict is `sufficient`.

**Figures.** The last `coord/pick.json` of each of 44 `/coordinate` sessions in
one host's koto store on 2026-10-22, read with `koto context get <session>
coord/pick.json` and sliced with `jq -c -L skills/coordinate/scripts 'include
"pick-slice"; pick_slice'`, sizes by `wc -c`. The full facts: largest 26,287,
p90 18,462, 8 over 12,000. The slice: largest 10,090, p90 3,637, none over.
The largest slice is mostly `pauses` (7.8 KB), which it keeps as they are.
`pick-facts_test.sh` holds a roadmap of 200 Done features and 3 open ones
under the cap.

**Fixtures.** `coordinate.pick.choice.decider.jsonl`. Each case's `pick_facts`
input is a slice, which `pick-facts_test.sh` checks by slicing it again, and
five carry a `done` list of 150 or more.

## coordinate/decision-verdict

`/coordinate`'s `decision_verdict` asks the decider whether to settle a
decision entry, escalate it to the run's target, or hold it for a fact. Like
pick's, it is an evidence decider: it runs in shadow, never acts, and has no
registry entry. Its input cap is the decider input's `max_bytes`, 12,000, and
its modes are rows of `scripts/decider-declarations.tsv`. Every answer goes
back to `decision_next`, so no answer changes a route.

**Sources.** `coord/decision.json`, which `decision-next.sh` writes as
`decision_next`'s `default_action` when its rule 8 finds an entry awaiting a
verdict. It is the record's Decisions section as `state-decision.sh --list`
reads it, filtered to that one entry. The agent writes the entry's question
and options when it opens it, and a worker's report or the agent's own raise
supplies its text; nothing selects what goes in.

**Slice.** The whole entry, one compact JSON line: all 19 of its fields,
`decision`, `round`, `question`, `options`, `state`, `source`, `verdict`,
`recommendation`, `reason`, `context`, `problem`, `grounds`, `target`,
`owed`, `asked`, `evidence`, `outcome`, `decided_by` and `updated`. While
the entry awaits a verdict the eleven fields a verdict writes are empty, so
what the decider reads is the question, the options, who raised it, the
evidence lines and the time.

**Completeness.** Whether an entry is the coordinator's to settle or has to
go up isn't in the entry. The directive's escalate grounds are scope, a
decision the dispatcher supplied, a step reserved for a person, and anything
outside the coordinator's scope, and none of those facts reaches the input:

- the run's scope: the roadmap on the default branch (which `pick-facts.sh`
  reads into `coord/pick.json`) or the discipline, and the Run section's
  `arguments`;
- what a person already decided or reserved: the record's Standing rows
  (`answer`, `approval`, `assignment`, `pause`), read by
  `state-stored-set.sh --list`;
- the steps reserved for a person and the four grounds themselves: the
  `decision_verdict` directive in `coordinate.md`, which only the agent reads;
- who the run reports to: `REPORTS_TO` and the Run section's `reports-to`;
- earlier verdicts on related entries: the rest of the Decisions section.

The `grounds` field is written only when an escalate verdict is recorded, so
it's always empty in the input. The completeness verdict is `insufficient`.

The ledger agrees. On one host's decider ledger, from 2026-10-21T03:12Z to
2026-10-23T01:25Z, there were 35 consultations in 8 `/coordinate`
sessions, each paired with the agent's own verdict, read with
`koto decider report --state decision_verdict --json` and the raw ledger
lines. None was covered: 25 were below the 0.9 threshold, 9 escaped and 1
timed out. The agent answered 24 settle and 11 escalate, and never hold. The
window ends at the last consultation the agent had answered when the ledger
was read; a later one, still unanswered then, is left out. The issue counted
32 consultations (25, 6 and 1; 23 settle and 9 escalate); the three added
since are all escapes, one settled and two escalated by the agent. Every
time in this section is UTC, the ledger's own clock; the host runs four hours
behind, so on its clock the window ended on the evening of 2026-10-22.

Each input was rebuilt from its session. A session's koto store keeps only
the latest `coord/decision.json`, so the rebuild works from two other things
it keeps. The session's log, `koto-<session>.state.jsonl` in its session
directory, gives the decision number (`decision-next.sh`'s `DECISION_NEXT`
capture), the `context_added` event of the `coord/decision.json` write
before the consultation, with its size, and the decider's `context_read` of
it, with the SHA-256 of the bytes it read. The record's Decisions section,
which the session stores as `record/decisions` (any later session on the
same record holds it too), gives the entry as it is now. That entry was
reset to its verdict-awaiting shape (`state` back to `coordinator-verdict`,
the eleven verdict fields empty) and searched over the fields that move
after a verdict: `round` as now or `0`, `evidence` as empty or any leading
run of its current lines, `options` as now or with each line's ` -- `
explanation cut (an escalation rewrites them), and `updated` as now or any
minute in the 72 hours before the consultation. A match is a rebuilt line
whose SHA-256 equals the logged one. Each match was then checked a second
time against the ledger's `input_sha256`, which koto computes over the
length-prefixed label and content, and all agreed. 27 of 35 rebuilt exactly. Six came from sessions whose record no
session still holds, and two from an entry whose evidence was later
rewritten. Those 8 have exact sizes but no text. 31 of the 35 inputs are
distinct: four were consulted twice unchanged. Three of those pairs got the
same answer both times; the fourth escaped once and leaned settle at 0.40
the next time.

- **Size.** Every input was a whole entry, none near the cap (the sizes are
  under Figures), so none was truncated or empty.
- **Evidence.** 25 of the 27 rebuilt inputs had an empty `evidence`, so the
  decider read only the question and the options. Of the two that had
  evidence, one held an earlier settled outcome of the same question and got
  the second-highest confidence of the window (settle, 0.86). The other held
  a worker asking the same question again; the decider leaned hold (0.63)
  and the agent settled.
- **Below threshold.** The decider leaned settle 18 times, hold 5 times and
  escalate twice. Its confidence ran from 0.31 to 0.88, with a median of
  0.51, 0.39 short of the threshold. It leaned the agent's way on 15 of the 25:
  13 of the 17 the agent settled, but only 2 of the 8 it escalated, and those
  2 were one input consulted twice, a question that asked in its own words
  whether "the owner" accepted a residual risk.
- **Escapes.** The escape's own probability had a median of 0.40, and the
  next-best answer was hold 5 times and settle 4 times. The escape's
  description, a missing, truncated or contradictory entry, matched none of
  the 9 inputs by size or shape.
- **Settle against escalate.** Nothing in the input tells the agent's settle
  cases from its escalate cases. Of the 27 rebuilt, the agent settled 18
  and escalated 9. The 18 it settled came from a worker 11 times, the
  agent's own raise 6 times and the dispatcher once; the 9 it escalated came
  from a worker 4 times, the agent's own raise 3 times and the dispatcher
  twice. Escalations had longer options
  (median 378 bytes against 202) and more of them (3 against 2), but a word
  like "owner", "scope" or "merge" turns up in both: "owner" in 4 of 9
  escalations and 3 of 18 settles. The agent's rationales name what decided
  it, and it's never in the entry: a scope the dispatcher set, an owner
  ruling that would be extended, a merge or a spending call that belongs to
  someone else, a rule of one review panel at a time.

So the low confidence isn't noise around a right answer. The decider can't
see whose decision it is, and with no evidence on most entries it leaned
hold, or put hold next after the escape, on 10 of the 34 consultations other
than the timeout, where the agent never held. No change to the input's size
or cap would fix this: the largest input was a third of the cap, and every
one arrived whole. Any input that could tell settle from escalate would need
facts the entry doesn't hold: the run's scope, the person's standing rulings
and decisions, and the steps reserved for a person. Whether the site gets
them or is dropped is a separate decision; this section only records what's
missing.

**Figures.** The 35 consultations above: smallest 504, median 856, p90
1,394, largest 3,953, none over 12,000. Sizes are each consultation's `context_added` size for
`coord/decision.json` in its session log, the last write before the
consultation.

**Fixtures.** `coordinate.decision_verdict.verdict.decider.jsonl`. The first
42 cases hold eight of the entry's fields and put the deciding fact in the
evidence. The eight cases after them are built from observed inputs, with
names made neutral and the decision numbers, report stamps and times
renumbered in the fixture file's own series, in the shape `decision-next.sh` writes, all 19 fields
on one line ending in a newline, as `jq -c` prints it:
`observed-settle-0` to `-2` (one with an earlier outcome as evidence),
`observed-escalate-0` to `-2` (the owner's residual risk, a recurring macOS
spend, a feature split out of a roadmap the dispatcher raised), and two whose
right answer is the escape: `empty-0`, an empty input, and `truncated-0`, an
entry cut at 200 bytes. No observed input was empty or truncated, so those
two are constructed. An observed case's expected answer is the verdict the
agent gave, which read the facts the input leaves out, so a decider that
misses one is showing the gap above rather than a fault of its own. The
fixtures haven't been run against the decider.

## Document criteria

Six rules a document jury flags over and over have Jev criteria that grade a
document one unit at a time: a Scope Boundary bullet, an Evidence clause, an
acceptance criterion, a user journey, a summary beside its section, two
passages that share a term or a number, and a falsifier beside its claim.
Each runs from a one-state template under `koto-templates/doc-criteria/`,
`<format>-<rule id>.md`, whose `grade` state holds one unit-mode decider check,
`doc_criteria`, with `units: jsonl`, `max_units` at the criterion's cap,
`max_bytes: 2560`, the format and section key as `unit_document` and
`unit_section`, and one criterion keyed by the jury rubric id it would stand
in for, in `mode: shadow`, with no `summary` or `rule_text`, since a shadow
criterion delivers nothing. The check's command runs
`scripts/doc-criteria/slice.py <rule id> <format> --doc <path> --commit <sha>`
through the template's `PLUGIN_ROOT`, `DOC` and `COMMIT` variables (the plugin
root rather than a slicer path, so the command names its slice script as
every other decider check's does),
which reads the document's blob at that commit from the repository the
document lives in, refuses a path that isn't under that repository's `docs/`
once symlinks are followed, and prints one JSON line per unit in the order the
units start in the document. koto grades the first `max_units` of them and
records the rest as past the cap (`unit_limit`), so a long document has the
same units graded on every run. The units past the cap are never graded, so a
contract's `over_cap` count says how much of its population that leaves out.

`references/doc-criteria.json` maps each format to its criteria (rule id,
section key, template and cap) and pins the sha256 of each template and of
the slice script; `jev_criteria.py check` fails when a pinned file differs,
and `jev_criteria.py pins` prints the pins as the files are now. A rule that
runs on two formats has one entry and two contracts, under `jev.pairs`, each
held to the contract above and to these rules:

- `template`, `section`, `cap` (at most 32) and `cut` match the map, the
  template's check and the slice script. A criterion that cuts never prints a
  unit over the budget; one that doesn't prints each unit whole, and koto
  records one over the budget as `over_budget`.
- `measured` is a census, population `documents`: every `<FORMAT>-*.md`
  under the public repositories' `docs/` directories, measured with
  `jev_criteria.py measure docs`. `runs` counts the documents with a unit,
  `empty` the ones with none, `over_budget` the documents holding a unit over
  the budget (the 5% line is drawn on these), `max` and `p90` the unit sizes,
  and `units`, `units_over_budget`, `units_per_doc_p90`, `units_per_doc_max`
  and `over_cap` (documents with more units than the cap) sit beside them. A
  census counts the whole population, so the 100-run minimum doesn't apply.
- `change_kinds` lists the finding kinds its seeded-bad fixtures may use, and
  its section below names each one. Every fixture case holds a small document
  as `input`, the `unit` key and the `slice` the slice script prints for that
  unit; each seeded-bad case names the good case it came from in `of`, its
  change kind in `change`, and has a slice of its own. A reviewer reads each
  seeded-bad case beside its good case and confirms in the review that the
  two differ by that one change.
- `fixture_run` records a run of the fixtures against the configured decider
  in shadow: the date, the decider model, the declaration's sha256, and the
  blob hashes of the fixture file and of the slice script. It is held to the
  fixture bar and also to every seeded-bad case answered `fail`, since an
  escape on a unit known to break the rule is a miss. The check fails when the
  counts miss either bar or any hash differs from the committed files; a run
  is re-made with `jev_criteria.py fixtures <rule id> --format <format>`.

No template anywhere may declare one of these six rule ids in `veto` or set
any decider value to `auto` (below, The shadow guard). Every one of them is
`untrusted`, and each leaves shadow the same way: a maintainer proposes it,
citing its live figures and its fixture run; the proposal is approved; and
only then does a template edit change its mode. Nothing in this page or the
registry changes a mode.

Every pre-jury moment sends each of these units to the decider endpoint a
user configured, through koto's capture redaction, private documents
included. A repository that must not send its documents sets the decider mode
to `off` in its project `.koto/config.toml`, which koto lets lower a user's
mode, and then nothing is sent.

### The shadow guard

`jev_criteria.py check` refuses, in every koto template of the tree (a `.md`
whose frontmatter declares `initial_state:` and `states:`, tests and
throwaway templates included) and in each template or directory passed with
`--koto-templates`:

- a decider-check criterion keyed by `rs-009`, `rs-011`, `rs-012`, `rs-013`,
  `rs-073` or `rs-074` in `mode: veto`;
- `mode: auto` on any decider answer of an accepts field, or on any criterion;
- a `KOTO_DECIDER=auto` anywhere in a template's text;
- the same in any template another one includes through
  `materialize_children.default_template`, followed from the including
  template's directory;
- a project `.koto/config.toml` anywhere in the tree, or in a directory from a
  passed path up to its repository root, that sets the decider mode to
  `auto`.

## brief-rs-073

Does a BRIEF's Scope Boundary bullet stay at the feature's altitude, naming no
function, data structure, field, flag, script, file path or command?

**Sources.** The BRIEF under review, its blob at the commit the step reads.

**Slice.** Each top-level list item under `## Scope Boundary`, whole, with the
`###` heading it sits under (`### In`, `### Out`) as its first line, or the
section's own heading when it sits under none. Section key `scope-boundary`.

**Completeness.** A bullet's altitude is decided by its own words and by
whether it is in or out of scope, which the heading carries; nothing else in
the document changes the answer. The verdict is `sufficient`. Change kinds:
`mechanism` (the bullet's subject becomes a function, a data structure or a
flag), `path` (a file path) and `command` (a command to run).

**Figures.** A 2,560-byte budget per unit and a cap of 32 units; units are not
cut. 85 public BRIEFs, 83 with a bullet: 934 units, largest 1,231, p90 363,
none over the budget; units per document p90 15, largest 19; none past the
cap.

**Fixtures.** `scripts/jev-criteria/fixtures/brief-rs-073.jsonl`: 13 good, 26
seeded-bad and 7 adversarial cases (all six techniques). Run against the
configured decider (jev-1.14.0) on 2026-10-30: good 13 pass, seeded-bad 26
fail, adversarial 6 fail and 1 escape.

**State.** `untrusted`, in shadow. It leaves shadow only through a
maintainer's proposal citing its live figures and its fixture run, the
proposal's approval, and then a template edit.

## roadmap-rs-073

Does a ROADMAP milestone's Evidence clause describe the check only by what a
person does and sees, naming no source file, script, function or line of the
implementation?

**Sources.** The ROADMAP under review, its blob at the commit the step reads.

**Slice.** Each Evidence clause, a `- ` line at column 0 with its indented
continuation, after a milestone's `**Evidence:**` and up to the first blank
line, field line or heading, with the milestone's `###` heading as its first
line. Milestones are read under `## Milestones`, or `## Features` on a
`roadmap/v2`. Section key `milestones`.

**Completeness.** Which milestone a clause evidences is in its heading, and
whether it names a mechanism is in its own words. The verdict is
`sufficient`. Change kinds: `file` (the clause names the implementing source
file), `script` (it rests on a named check script passing) and `function` (it
names an implementing function or line).

**Figures.** A 2,560-byte budget per unit and a cap of 32 units; units are not
cut. The public repositories hold no ROADMAP under `docs/`, so the census
measured none; the live figures are the first measurement this contract
gets, and its units aren't cut, so a proposal to promote it needs those
figures to show the budget holds.

**Fixtures.** `scripts/jev-criteria/fixtures/roadmap-rs-073.jsonl`: 12 good,
24 seeded-bad and 7 adversarial cases. Run on 2026-10-30 (jev-1.14.0): good 12
pass, seeded-bad 24 fail, adversarial 7 fail.

**State.** `untrusted`, in shadow. It leaves shadow only through a
maintainer's proposal citing its live figures and its fixture run, the
proposal's approval, and then a template edit.

## prd-rs-013

Can a PRD's acceptance criterion be answered yes or no by someone who didn't
write it, without any judgment call?

**Sources.** The PRD under review, its blob at the commit the step reads.

**Slice.** Each top-level list item under `## Acceptance Criteria`, whole,
group headings left out. Section key `acceptance-criteria`.

**Completeness.** A criterion's own text is all the question reads. The
verdict is `sufficient`. Change kinds: `subjective-word` (a measurable result
becomes a judgment word with no measure), `no-observable-result` (it becomes
an intent or a quality nobody can observe) and `unmeasured-quantity` (a number
becomes "most", "many" or "reasonable").

**Figures.** A 2,560-byte budget per unit and a cap of 32 units; units are not
cut. 186 public PRDs, 184 with a criterion: 5,074 units, largest 1,823, p90
352, none over the budget; units per document p90 51, largest 85; 57
documents have more units than the cap, and their later criteria are past it.

**Fixtures.** `scripts/jev-criteria/fixtures/prd-rs-013.jsonl`: 13 good, 26
seeded-bad and 7 adversarial cases. Run on 2026-10-30 (jev-1.14.0): good 12
pass and 1 escape, seeded-bad 26 fail, adversarial 7 fail.

**State.** `untrusted`, in shadow. It leaves shadow only through a
maintainer's proposal citing its live figures and its fixture run, the
proposal's approval, and then a template edit.

## brief-rs-011

Does a BRIEF's user journey have all three parts: a named role, an event or
need that happens before the role acts, and a result stated after the action?

**Sources.** The BRIEF under review, its blob at the commit the step reads.

**Slice.** Each `###` subsection under `## User Journeys`, whole, heading
included. Section key `user-journeys`.

**Completeness.** A journey's own text is all the question reads. The verdict
is `sufficient`. Change kinds: `no-role` (the role becomes "the user"),
`no-trigger` (the event or need that comes first is removed, or replaced by a
sentence that names none) and `no-outcome` (the result is removed, or
replaced by a sentence that names none).

The criterion's threshold is 0.7, not koto's 0.9. On a three-part question the
decider's confidence on clear cases sat between 0.7 and 0.9 in the fixture
runs, so at 0.9 a third of the seeded-bad cases escaped. A lower threshold
lets a wrong answer count sooner; in shadow nothing acts on one, and the
fixture run and the live figures are taken under this threshold.

**Figures.** A 2,560-byte budget per unit and a cap of 8 units; units are not
cut. 85 public BRIEFs, 83 with a journey: 341 units, largest 1,455, p90 842,
none over the budget; units per document p90 5, largest 6; none past the cap.
Measured as one slice per run, all of a brief's journeys at once, this
criterion was blocked for want of a koto state; graded one unit at a time from
its own template, it has one.

**Fixtures.** `scripts/jev-criteria/fixtures/brief-rs-011.jsonl`: 12 good, 24
seeded-bad and 7 adversarial cases. Run on 2026-10-30 (jev-1.14.0): good 12
pass, seeded-bad 24 fail, adversarial 5 fail and 2 escapes.

**State.** `untrusted`, in shadow. It leaves shadow only through a
maintainer's proposal citing its live figures and its fixture run, the
proposal's approval, and then a template edit.

## brief-rs-012

Does a BRIEF's frontmatter summary say the same thing as the leading part of
the section it summarizes, with no fact that conflicts?

**Sources.** The BRIEF under review, its blob at the commit the step reads.

**Slice.** The `problem` summary beside `## Problem Statement`, and the
`outcome` summary beside `## User Outcome`, each as one unit: the summary
(cut to 1,024 bytes, which no measured summary reaches), then the section's
leading paragraphs that fit the budget whole, then `[section continues]` when
any paragraph is left out. A first paragraph too big on its own is cut to fit.
A summary or a section that's missing gives no unit. Section key
`frontmatter`.

**Completeness.** The cut can't see a contradiction in the part of the
section it leaves out, so a pass means "agrees with the leading part", and
the marker tells the decider the section goes on. Uncut, 44 of the 170
measured units (26%) would be over the budget. The verdict is `sufficient` for that weaker
question. Change kinds: `different-subject` (the summary describes another
problem or outcome) and `contradicted-fact` (one fact in the summary is
changed so the section states the opposite).

**Figures.** A 2,560-byte budget per unit and a cap of 2 units; units are cut.
85 public BRIEFs: 170 units, largest 2,559, p90 2,434, none over the budget;
2 units in every document. Measured whole, as one slice per run, it was
rejected: every run was over the budget.

**Fixtures.** `scripts/jev-criteria/fixtures/brief-rs-012.jsonl`: 12 good, 24
seeded-bad and 6 adversarial cases. Run on 2026-10-30 (jev-1.14.0): good 11
pass and 1 escape, seeded-bad 24 fail, adversarial 5 fail and 1 escape.

**State.** `untrusted`, in shadow. It leaves shadow only through a
maintainer's proposal citing its live figures and its fixture run, the
proposal's approval, and then a template edit.

## prd-rs-009

Are two passages of a PRD that share a backticked term or a number consistent
with each other?

**Sources.** The PRD under review, its blob at the commit the step reads.

**Slice.** A passage is a list item with its continuation lines, a table row,
or a prose paragraph, outside fenced code and the frontmatter. A pair is two
passages sharing a key, a backticked term or a number (thousands separators
dropped), that occurs in two or three passages; a key in more passages forms
no pair. Each side is the sentence holding the key (an item or a row whole),
cut to 1,200 bytes, under its section heading cut to 72. Pairs come in order
of their first passage, then their second. Section key `document`.

**Completeness.** Clipping can drop a qualifying clause around the shared
term, so the question is whether the two statements, as written, disagree;
pairs the key rule never forms are never asked. The verdict is `sufficient`.
Change kinds: `number-conflict`, `name-conflict`, `status-conflict` and
`behaviour-conflict`, one passage changed so the two disagree on that.

The threshold is 0.85: the decider's confidence on clear conflicts sat between
0.85 and 0.9 often enough in the fixture runs that 0.9 left a few escaping.

**Figures.** A 2,560-byte budget per unit and a cap of 32 units; units are
cut. 186 public PRDs, 179 with a pair: 4,828 units, largest 2,426, p90 1,010,
none over the budget; units per document p90 55, largest 103; 61 documents
have more pairs than the cap. Measured whole, every pair of a run in one
slice, it was rejected: two runs in three were over the budget.

**Fixtures.** `scripts/jev-criteria/fixtures/prd-rs-009.jsonl`: 14 good, 25
seeded-bad and 7 adversarial cases. Run on 2026-10-30 (jev-1.14.0): good 14
pass, seeded-bad 25 fail, adversarial 5 fail and 2 escapes.

**State.** `untrusted`, in shadow. It leaves shadow only through a
maintainer's proposal citing its live figures and its fixture run, the
proposal's approval, and then a template edit.

## design-rs-009

Are two passages of a DESIGN that share a backticked term or a number
consistent with each other?

**Sources.** The DESIGN under review, its blob at the commit the step reads.

**Slice.** As `prd-rs-009`, over the DESIGN. Section key `document`.

**Completeness.** As `prd-rs-009`: the question is whether the two statements,
as written, disagree. The verdict is `sufficient`. Change kinds:
`number-conflict`, `name-conflict`, `status-conflict` and
`behaviour-conflict`. Its threshold is 0.85, for the same reason.

**Figures.** A 2,560-byte budget per unit and a cap of 32 units; units are
cut. 249 public DESIGNs, every one with a pair: 13,162 units, largest 2,542,
p90 943, none over the budget; units per document p90 100, largest 253; 176
documents have more pairs than the cap, so most DESIGNs are graded in part.

**Fixtures.** `scripts/jev-criteria/fixtures/design-rs-009.jsonl`: 15 good,
25 seeded-bad and 7 adversarial cases. Run on 2026-10-30 (jev-1.14.0): good 15
pass, seeded-bad 25 fail, adversarial 7 fail.

**State.** `untrusted`, in shadow. It leaves shadow only through a
maintainer's proposal citing its live figures and its fixture run, the
proposal's approval, and then a template edit.

## strategy-rs-074

Is a STRATEGY falsifier's condition about the same thing as the Defensibility
Thesis claim it names, so that observing it would show that claim wrong?

**Sources.** The STRATEGY under review, its blob at the commit the step reads.

**Slice.** Each top-level list item under `## Bet-Specific Falsifiability`,
its corrective included, cut to 1,500 bytes, beside the claim its first
`claim <n>` names: the Defensibility Thesis's numbered item `<n>`, or a
paragraph there that opens `Claim <n>`, cut to 1,000. A bullet naming no claim
number is sent with `[no claim named]`, and one naming a number the thesis has
no claim for says so; the decider escapes on both. Section key
`bet-specific-falsifiability`.

**Completeness.** The bullet and the claim it names are what the question
compares, and a missing claim number is itself a finding the escape covers.
Whether the condition can be observed and whether a corrective follows are
the bet-quality seat's other items; this criterion asks only whether the
falsifier tests its claim. The verdict is `sufficient`. Change kinds:
`unrelated-claim` (the bullet names a claim about another subject) and
`unrelated-condition` (its condition is replaced by one about another
subject).

**Figures.** A 2,560-byte budget per unit and a cap of 32 units; units are
cut. The public repositories hold no STRATEGY under `docs/`, so the census
measured none; the live figures are the first measurement this contract
gets.

**Fixtures.** `scripts/jev-criteria/fixtures/strategy-rs-074.jsonl`: 12 good,
24 seeded-bad and 6 adversarial cases. Run on 2026-10-30 (jev-1.14.0): good 10
pass and 2 escapes, seeded-bad 24 fail, adversarial 6 fail.

**State.** `untrusted`, in shadow. It leaves shadow only through a
maintainer's proposal citing its live figures and its fixture run, the
proposal's approval, and then a template edit.

## rs-007

Does Part 1 of the pull request body claim only changes the file list shows?

**Sources.** The pull request body (the graded artifact) and its file list
from git. **Slice.** `review-shadow.py`'s pull-request summary: Part 1 and the
file list, whole. **Completeness.** Part 1 and the full file list are what the
claim is judged against; the slicer's fallback to a directory summary or a cut
body would drop what the question needs, so only the whole slice counts.
**Figures.** 80 merged pull requests from shirabe and koto, largest 13,676,
p90 4,152, 32 over 2,560. **State.** `rejected`: over the budget on 40% of
runs.

## rs-008

Does Part 1 of the pull request body mention every significant change the file
list shows?

**Sources**, **slice**, **completeness** and **figures** as `rs-007`.
**State.** `rejected`, for the same measurement.

## rs-010

Does every code comment in the changed hunks still describe the code after the
change?

**Sources.** The diff, from git. **Slice.** `review-shadow.py`'s code hunks:
every hunk that adds, removes or borders a comment. **Completeness.** A comment
and the code beside it are what the question reads. **Figures.** 469 recorded
`/work-on` runs, largest 324,298, p90 89,574, 449 over 2,560. **State.**
`rejected`: over the budget on 96% of runs.

## rs-014

Does every criterion of an issue that checks an end state also check the
operation that produces it?

**Sources.** The PLAN under review. **Slice.** Every issue's title and
criteria. **Completeness.** One issue's criteria list is what the question
reads. **Figures.** None: `not_measured: no-real-run-record`. No real run
recorded its slices, and PLANs are deleted when their work lands. **State.**
`blocked`: `/plan` has no koto state to run a check in, and it stays out of
any template until its slices can be measured.

## rs-015

Do the changed hunks contain a change that would make an acceptance criterion
true?

**Sources.** The issue's criteria and the diff, from git. **Slice.** Every
criterion beside the hunks that mention one of its anchor terms.
**Completeness.** A criterion and the hunks that touch what it names are what
the question reads; a criterion with no anchored hunk can't be judged at all.
**Figures.** 398 recorded `/work-on` runs, largest 99,910, p90 29,328, 382
over 2,560. **State.** `rejected`: over the budget on 96% of runs.

## rs-016

Does every added code comment give a reason rather than restate the code?

**Sources**, **slice**, **completeness** and **figures** as `rs-010`.
**State.** `rejected`, for the same measurement.

## rs-017

Does every code comment in the changed hunks still describe the code after the
change?

**Sources**, **slice**, **completeness** and **figures** as `rs-010`.
**State.** `rejected`, for the same measurement.

## rs-018

Can every claim a change makes about meeting its acceptance criteria be
verified from the diff? The completeness seat's second question.

**Sources.** The agent's own claims that its work meets each criterion, and
the diff. **Slice.** None: nothing records the claims anywhere a script can
read, so no slicer exists; the row's slice kind, `ac-claims`, only names the
slice the question would need. **Completeness.** The claims are the agent's words
about its own work, which no slice may carry, since the agent would then
choose what the classifier sees. The verdict is `insufficient`. **Figures.**
None: `not_measured: no-real-run-record`. **State.** `rejected`.

## rs-019

Does every place where a change departs from its acceptance criteria or its
plan carry a reason that reflects a real trade-off? The justification seat's
question.

**Sources.** The criteria (`review_level_criteria.txt`, which
`review-level.sh` writes), the plan the run wrote (`plan.md`) and the diff.
**Slice.** The criteria, the plan and the hunks. **Completeness.** A
departure is visible only against the criteria and the plan, and whether its
reason is real needs the code it explains, so all three are what the question
reads. The verdict is `sufficient`. **Figures.** The criteria and the plan
alone, over 180 `/work-on` sessions: largest 40,003, p90 10,458, 154 over
2,560. These figures are a lower bound: the full slice also carries the diff.
**State.** `rejected`: over the budget on 86% of runs before the diff is
counted.

## rs-020

Does a change do what its design context describes, rather than only what its
criteria literally say? The intent seat's question.

**Sources.** The design context (`context.md`) and the diff. **Slice.** The
design context and the hunks. **Completeness.** The behaviour a design
describes and the code that implements it are what the question compares.
The verdict is `sufficient`. **Figures.** The design context alone, over 172
`/work-on` sessions that kept one: largest 37,777, p90 5,888, 91 over 2,560.
These figures are a lower bound: the full slice also carries the diff.
**State.** `rejected`: over the budget on 53% of runs before the diff is
counted.
