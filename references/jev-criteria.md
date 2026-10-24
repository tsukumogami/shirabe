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
| `measured` | The slice's size on real runs: `population` (`koto-sessions`, `merged-prs` or `review-shadow-records`), `runs`, `max`, `p90` (nearest rank), `over_budget` (runs over the budget), `on` and the `command` that took it, which prints the same figures given the same inputs. Optionally `empty`: the runs that reached the criterion's state with an empty slice, which `runs` leaves out (`measure sessions --slice decision-reasons` prints it). With no `empty`, the measurement found no empty slice. Or instead `not_measured: no-real-run-record`. |
| `fixtures` | The fixture file, from `untrusted` on. |
| `declared` | For a koto decider check: `sha256` of its declaration and `since`, the date that declaration took effect. `jev_criteria.py declared-hash` prints both the declaration and its hash. |
| `false_passes` | Confirmed false passes: `evaluated` and `recorded` dates, `oracle` (`review`, `ci` or `human`) and an `evidence` link. Never removed. |
| `promotion` | Only on a trusted criterion: `trusted_since`, the `fixture_run`, the `live` figures and the slice script's blob hash. |

A koto gate sends one slice per evaluation, so a criterion that judges every
unit of a run (every hunk, every acceptance criterion) has to fit them all at
once. Every figure below is that whole-run size in bytes: the number of runs
measured, the largest, the 90th percentile and how many went over the budget.

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
verdict. It is the record's Decisions section as `record-decision.sh --list`
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
  `record-state.sh --list`;
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

## rs-009

Are two passages of the same document consistent with each other?

**Sources.** The changed documents at the merge commit, from git. **Slice.**
`review-shadow.py`'s doc pairs: each added passage beside each passage sharing
a number or a backticked term, every pair of the run at once. **Completeness.**
Each pair carries both passages whole, which is all the question reads.
**Figures.** 24 of shirabe's last 40 merged pull requests had pairs, largest
54,359, p90 22,939, 16 over 2,560. **State.** `rejected`: over the budget on
67% of runs.

## rs-010

Does every code comment in the changed hunks still describe the code after the
change?

**Sources.** The diff, from git. **Slice.** `review-shadow.py`'s code hunks:
every hunk that adds, removes or borders a comment. **Completeness.** A comment
and the code beside it are what the question reads. **Figures.** 469 recorded
`/work-on` runs, largest 324,298, p90 89,574, 449 over 2,560. **State.**
`rejected`: over the budget on 96% of runs.

## rs-011

Does a user journey name a specific user, what brings them to the feature, and
what they get?

**Sources.** The BRIEF under review. **Slice.** Every journey of the brief,
whole. **Completeness.** Each journey's own text is all the question reads.
**Figures.** 23 recorded `/brief` runs, largest 2,353, p90 1,999, none over
2,560. **State.** `blocked`: its slices fit, but `/brief` has no koto state to
run a check in.

## rs-012

Does a frontmatter summary agree with the section it summarizes?

**Sources.** The BRIEF under review. **Slice.** Both summaries (problem and
outcome) beside the sections they summarize. **Completeness.** A summary and
its whole section are what the question compares. **Figures.** 23 recorded
`/brief` runs, largest 3,877, p90 3,709, all 23 over 2,560. **State.**
`rejected`.

## rs-013

Can an acceptance criterion be answered yes or no by someone who didn't write
it?

**Sources.** The PRD under review. **Slice.** Every acceptance criterion of the
PRD. **Completeness.** A criterion's own text is all the question reads.
**Figures.** 21 recorded `/prd` runs, largest 11,332, p90 8,169, 19 over
2,560. **State.** `rejected`: over the budget on 90% of runs.

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
