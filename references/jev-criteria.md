# Jev criteria

A Jev criterion is a closed question Jev answers about a slice of an agent's
work. Before one may run, and before its rule's text may be left out of a
run, it has to show what its slice holds, that the slice is enough, how big it
gets on real runs, and what evidence other than the agent says its passes can
be trusted. This page is where each criterion's written case lives; the
figures and the trust record live in its entry in
`references/rule-registry.json`, under `jev`, and
`scripts/jev-criteria/jev_criteria.py check` holds the two to each other and to
the templates. The design is `docs/designs/DESIGN-jev-pass-trust.md`.

## The contract

Every entry Jev grades carries a `jev` object:

| Field | What it holds |
|---|---|
| `state` | `rejected`, `blocked`, `untrusted` or `trusted` (below). |
| `sources` | What the slice is built from, each with its `writer`: `git` (committed objects), `gate-script` (a koto context key a named gate or `default_action` script writes, named in `script`), `graded-artifact` (the artifact the criterion judges, read whole) or `slice-script` (the slice script's own earlier output). Never something the agent writes about its work, and never anything the agent selects. |
| `slice_script` | The script that prints the slice. For a koto decider check, the gate's command runs it. |
| `budget` | The slice's byte budget: the gate's `max_bytes`, and never above 2,560, about the 2,507 bytes the Jev accuracy spike validated. A criterion with no gate is measured against 2,560. |
| `completeness` | `path` and `heading` of its written case on this page, and the `verdict`, `sufficient` or `insufficient`, which the contract's author sets and its pull request's reviewers check. |
| `measured` | The slice's size on real runs: `population` (`koto-sessions`, `merged-prs` or `review-shadow-records`), `runs`, `max`, `p90` (nearest rank), `over_budget` (runs over the budget), `on` and the `command` that took it, which prints the same figures given the same inputs. Or instead `not_measured: no-real-run-record`. |
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
A run meets the bar when no seeded-bad or adversarial case is answered `pass`,
at least 80% of good cases are, and every case got an answer.
`jev_criteria.py fixtures <rule-id>` runs the file against Jev under the
template's declaration and prints the `fixture_run` record a promotion keeps.

**Live.** Over decider events from the criterion's `declared.since` (or the day
after its latest false pass, if later) to the day the figures were read: at
least 30 evaluations across at least 5 sessions, at least 95% of them answered
`pass` or `fail`, no fallback for `over_budget`, and no input over the budget.
The figures come from koto's exported decider events read in a log backend,
never from a local file. `jev_criteria.py figures <rule-id> --sessions <dir>`
computes the same figures from local koto session logs; it is a tested
reference for their definitions, not the tool that decides a promotion.

## work-on/review-level-fits-facts

`/work-on`'s `review_level_check` asks Jev whether the chosen review level is
too light for the facts of the change.

**Sources.** `review_facts.json`, which the state's own `default_action`
(`review-level.sh facts`) writes from git, and `REVIEW_LEVEL`, the level the
agent chose, which is what the criterion judges.

**Slice.** `review-level.sh slice` prints one JSON line of typed facts (changed
lines and files as non-negative integers, at most 16 path-class names, whether
tests or the acceptance criteria changed, whether any path fell in no class,
and the facts floor), a line giving the order of the levels, and the chosen
level. No path, reason, criteria text or issue text reaches it.
`review-level.sh project` prints the same slice for a facts file, which is how
the fixture cases and the measurement build theirs.

**Completeness.** The question needs the facts, the floor the rules file
derives from them, the order of the levels and the level chosen, and nothing
else: the floor already applies every rule in `review-level-rules.tsv`, so the
definitions add only which level is lighter than which, and the slice states
that order. The verdict is `sufficient`.

**Figures.** 166 `/work-on` sessions' recorded facts, each projected at the
longest level name, largest 246, p90 229, none over the 2,048-byte budget
(the gate's `max_bytes`).

**State.** `untrusted`: it runs today, in veto mode for a user whose decider is
in `auto`, and no fixture run or live window has been recorded. Its rule's text
isn't preloaded in any directive, so nothing is withheld when it earns trust.

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
