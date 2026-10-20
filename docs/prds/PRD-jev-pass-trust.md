---
schema: prd/v1
status: Done
problem: |
  shirabe can grade an agent's work with Jev through koto decider checks, but
  no Jev criterion says what its slice holds, why that is enough, or how big
  it gets on real runs, and none has earned trust from anything but the agent.
  The review-shadow trial kept its evidence in a local store nobody else can
  read, and koto's decider is off unless a user opts in. So every rule a Jev
  criterion could check stays preloaded for every user, and nothing says how a
  criterion would earn the right to change that or lose it again.
goals: |
  Every Jev criterion carries a measured, checked slice contract, and criteria
  whose slices don't fit are recorded as rejected. Pass trust is earned from
  fixtures and from the decider events koto already exports, granted and taken
  away only by reviewed registry changes. A trusted criterion's rule is
  withheld only for a user whose decider is active, and is loaded again
  whenever the check can't answer.
absorbed:
  - docs/briefs/BRIEF-jev-pass-trust.md
---

# PRD: Jev criteria and pass trust

## Status

Done

The completeness, clarity and testability reviewers passed it over three
rounds. The downstream DESIGN owns the approach.

Absorbed [BRIEF-jev-pass-trust](docs/briefs/BRIEF-jev-pass-trust.md); carried in Absorbed Brief.

## Absorbed Brief

The feature exists so a maintainer can tell which questions Jev can be trusted
with, and so a rule a trusted check enforces stops costing every run its text
without ever going unchecked. The brief framed three gaps: no Jev criterion
says what its slice holds or how big it gets on real runs, no criterion has
earned trust from anything but the agent, and nothing can stop loading a
checked rule safely or undo that. This document's Problem Statement states all
three in full, with the measured sizes.

The outcome it set: a maintainer reads the record for any criterion (sources,
slice script, completeness case, measured size, fixtures, live figures) and
sees a criterion that falls short rejected rather than shipped; once a
criterion earns pass trust, a user whose decider is active doesn't load its
rule, a user without one sees no change, an unanswered check hands the agent
the rule, and a confirmed false pass takes trust away through a reviewed
change. Goals and User Stories carry that outcome.

Its journeys were a maintainer whose proposed criterion measurement rejects, a
maintainer promoting a criterion with fixture and live evidence, users with and
without an active decider running `/work-on`, an unanswered check mid-run, and
a reviewer confirming a false pass. User Stories, R2, R9 to R15 carry them.

Its scope boundary put slice contracts, the criterion format, the 2.5 KB
ceiling, the fixture profile, the promotion and demotion bar, per-user
withholding and moving the review-shadow trial onto koto decider events in;
and batched scrutiny criteria, larger budgets, offline ablations, dashboards,
the script-check lifecycle, koto changes and actually withholding a rule out.
Requirements and Out of Scope carry it.

## Problem Statement

A koto decider check sends a slice of an agent's work to Jev with a closed
question. Since koto 0.20.0 a criterion Jev can't answer (an over-budget
slice, a failed extraction, a provider error, a spent cap) falls back to the
agent instead of passing. The machinery is in place. What's missing is any
rule for which questions belong on it and how much a Jev pass is worth. The
people affected are shirabe's maintainers, who decide which rules a check can
stand in for, and shirabe's users, whose runs load every rule's text whether a
check enforces it or not.

**Slices were never contracted or measured.** The only decider check inside a
workflow, `level_fits_facts` on `/work-on`'s `review_level_check`, asks whether
a level is too light "given these facts about a change and the review level
definitions", but its slice carries the facts and the level, not the
definitions. The review-shadow criteria (`rs-007` to `rs-017`) were built with
slicers that drop parts of a unit to fit the bound, so a slice could omit what
the question needs. A koto gate sends one slice per evaluation, so a criterion
that judges every unit of a run (every hunk, every acceptance criterion) has
to fit all of them at once. Measured that way on real runs on 2026-10-20
(UTC), with no call to Jev, most of them don't fit:

| Criterion | Slice | Real runs | Over 2,560 bytes | State (R2) |
|---|---|---|---|---|
| `level_fits_facts` | review facts and level | 162 sessions, max 214 bytes | 0 | `untrusted` |
| `rs-007`, `rs-008` | PR body Part 1 and file list | 80 merged PRs, median 2,077 | 31 | `rejected` |
| `rs-009` | doc passage pairs | 24 merged PRs with pairs, median 7,721 | 17 | `rejected` |
| `rs-010`, `rs-016`, `rs-017` | comment-touching hunks | 463 `/work-on` runs, median 28,974 | 443 | `rejected` |
| `rs-011` | a brief's user journeys | 23 `/brief` runs, max 2,353 | 0 | `blocked` |
| `rs-012` | both summaries beside their sections | 23 `/brief` runs, median 3,393 | 23 | `rejected` |
| `rs-013` | a PRD's acceptance criteria | 21 `/prd` runs, median 6,405 | 19 | `rejected` |
| `rs-014` | a plan's issue criteria | no real-run record | n/a | `blocked` |
| `rs-015` | criteria with anchored hunks | 395 `/work-on` runs, median 13,813 | 379 | `rejected` |

The criteria with no gate are measured against the 2,560-byte ceiling;
`level_fits_facts` is measured against its gate's 2,048-byte budget, which it
also never exceeds.

The Jev accuracy spike (`docs/spikes/SPIKE-jev-accuracy.md`) validated inputs
only up to 2,507 bytes, so nothing larger can be trusted without re-running it.

**No criterion has earned trust.** The spike cleared criteria "for a decider
design, not for promotion: a Jev pass still has to earn trust from a non-agent
oracle". The review-shadow trial (tsukumogami/shirabe#563) graded criteria
beside review panels but wrote its records to a local store on the machine
that ran it, where nobody else can read them, and left most per-site runs
without a verdict. koto already records and exports `decider_checked` and
`decider_fallback` events for every host whose decider is opted in, which is
where evidence any reviewer can recompute would come from. koto's decider
defaults to off, so those events exist only where a user turned it on.

**Nothing can stop loading a checked rule safely.** A rule's text is loaded in
its state for every user. Withholding it is safe only when a check will
actually judge the result, which koto does only for a user whose decider is
opted in, in `auto` mode for a veto check. Nothing in shirabe tells a run
which case it is in, and nothing turns a confirmed false pass into a
demotion.

## Goals

- A maintainer can read, for every Jev criterion, its sources, the script that
  builds its slice, a written case that the slice is complete, its budget and
  its measured size on real runs, and CI refuses a criterion whose record is
  missing, inconsistent with the template, or over the validated budget.
- Pass trust is earned from seeded-bad and adversarial fixtures and then from
  live decider events, stated as figures a reviewer can recompute, and it is
  granted or removed only by a reviewed change to the rule registry.
- A trusted criterion's rule is withheld only for a user whose decider is
  active, and the rule is loaded again for the rest of a session in which the
  check could not answer, and for everyone once the criterion is demoted.
- The review-shadow trial's evidence comes from koto decider events, not from
  a local store.

## Terms

- **Session**: one koto session of a workflow, such as one `/work-on` run.
- **Jev criterion**: one closed question Jev answers, identified by its rule
  id. Each has exactly one registry entry, and each entry names exactly one
  criterion: the review-shadow criteria use their `rs-NNN` id as both, and a
  koto decider check's criterion gets a registry id of its own that the entry
  maps to its template, state, gate and criterion id.
- **Evaluation**: one koto evaluation of a decider check for one criterion,
  identified by session, visit sequence, check and criterion.
- **Slice**: the bytes the check's command prints, which koto sends to Jev
  whole or not at all.
- **Decider events**: the session-log and exported events koto writes for a
  decider check: `decider_checked` (Jev answered or didn't, with its outcome,
  mode, reason and input size), `decider_fallback` (the criterion fell back to
  the agent, with its reason and input size) and `decider_check_answered` (the
  agent recorded its own answer with `koto decider answer`).
- **Effective decider mode**: the lowest of three modes, ordered `off` below
  `shadow` below `auto`: the user's mode, which `koto config get decider.mode`
  prints after applying the `KOTO_DECIDER` variable over the user's koto
  configuration file (`.koto/config.toml` in their home directory);
  the project's mode, `decider.mode` in the working directory's
  `.koto/config.toml`; and the template's mode for the criterion. A veto check
  blocks only at `auto`.
- **Facts floor**: the lowest review level `review-level.sh` allows for a
  change's facts, computed from `review-level-rules.tsv` and printed in the
  slice as `floor`.

## User Stories

- As a shirabe maintainer proposing a Jev criterion, I write its slice
  contract and measure the slice on real runs before any template changes, so
  a criterion that would fall back to the agent on most runs is recorded as
  rejected instead of shipped.
- As a shirabe maintainer promoting a criterion, I run its fixture set against
  Jev from my own session, read its live figures from the exported decider
  events, and open a registry pull request carrying both, so a reviewer can
  check the evidence before trust is granted.
- As a reviewer of that pull request, I recompute the live figures from the
  stated queries, and CI refuses the change if the recorded figures fall short
  of the bar.
- As a user who opts my host's decider in to `auto`, my sessions produce the
  decider events that a criterion's live figures are built from.
- Once a criterion is trusted and its state wired, as a `/work-on` user whose
  effective decider mode is `auto`, I don't read that rule's text and the
  decider judges my result; as a user whose decider is off, in shadow or
  without a key, I read it exactly as before. In this feature the withhold
  script's tests exercise both cases; no state is wired yet.
- As a `/work-on` user whose decider couldn't answer a trusted criterion, I
  read the rule's full text before I answer the criterion myself, and it stays
  loaded for the rest of my session.
- As a reviewer who confirmed a false pass, I record it against the criterion
  in a registry pull request that also takes its trust away, and once it
  merges every session loads the rule again.

## Requirements

### Functional

**R1. Every Jev criterion has a registry entry with a slice contract.** Each
criterion graded by Jev, whether it runs as a koto decider check or is defined
in `scripts/review-shadow/criteria.json`, has an entry in
`references/rule-registry.json` with a contract holding:

- `sources`: a non-empty list, each naming what is read and what writes it
  (R3's vocabulary);
- `slice_script`: the repository path of the script that builds the slice;
- `budget`: bytes;
- `completeness`: the path and heading of the written completeness case, and
  a verdict, `sufficient` or `insufficient`, which the contract's author sets
  and the pull request's reviewers check;
- `measured`: runs, maximum bytes, 90th-percentile bytes (nearest rank),
  runs over budget, the date, the command that took it, and the population
  from the closed set `koto-sessions` (a run is one session),
  `merged-prs` (a run is one pull request) or `review-shadow-records` (a run
  is one record); or instead a `not_measured` reason from the closed set
  `no-real-run-record`;
- `fixtures`: the repository path of its fixture file, required from
  `untrusted` on;
- `state`: one of R2's states.

A koto decider check's entry also names the template, state, gate and
criterion id it checks, and records `declared`: the SHA-256 of the gate's
declaration and the date that declaration took effect. The declaration is
the command as written, label, `max_bytes`, and the criterion's question,
pass, fail and escape descriptions and threshold, serialized as JSON with
sorted keys, no whitespace and UTF-8; a shipped command prints it so a
reviewer and CI compute the same value.

**R2. Contract states.** Each state has one condition, and the registry check
holds every entry to the condition of the state it records:

| State | Condition |
|---|---|
| `rejected` | more than 5% of measured runs over the contract's budget, or a completeness verdict of `insufficient` |
| `blocked` | not rejected, and no koto template declares the criterion, because no koto state exists to run it in |
| `untrusted` | not rejected, declared by a koto template, and no promotion record |
| `trusted` | not rejected, declared by a koto template in `veto` mode, and a promotion record meeting R12 |

A criterion with no gate is measured against the 2,560-byte ceiling as its
budget. The Problem Statement's table gives each current criterion's state. A
template may declare only an `untrusted` or `trusted` criterion.

**R3. Slices come from scripts that read only what a script wrote.** A
contract's slice script is the command of the gate that runs the criterion.
Each source's writer is one of: `git` (committed objects), `gate-script` (a
koto context key written by a named gate command or `default_action`
script), `graded-artifact` (the artifact the criterion judges, read whole by
the script from where the workflow keeps it, such as the change's diff or the
body of the pull request under judgment) or `slice-script` (the script's own
earlier output). The agent never decides what goes into a slice: no source is
something the agent writes *about* the graded artifact (a summary, a list of
claims, a pointer to the parts to read), and no source is selected by the
agent. The registry check enforces the vocabulary and the named scripts;
whether a source is described truthfully is the pull request reviewers' call.

**R4. Measured on real runs, reproducibly.** The measured size comes from
running the contract's slice builder over real artifacts of the population it
names, with no call to Jev. The script that took each measurement ships, and
given the same inputs prints the figures the registry records. Figures are
counts and byte sizes only; they name no session, repository or path.

**R5. Budget ceiling.** No contract's budget, and no decider check's
`max_bytes`, exceeds 2,560 bytes, about the 2,507 bytes the Jev spike
validated. A contract's budget equals its gate's `max_bytes`. A larger budget
is refused until the spike is re-run, which this feature doesn't do.

**R6. Enough runs.** An `untrusted` or `trusted` contract's measurement covers
at least 100 runs of its population.

**R7. `level_fits_facts` carries what its question needs.** Its slice adds one
line stating the three levels in increasing order (`light`, `standard`,
`full`), next to the facts, the facts floor and the chosen level, and keeps
only typed values (counts as non-negative integers, class names from
`[a-z0-9_]`), so no free text reaches Jev. Its budget stays the 2,048 bytes
the gate declares today. Its completeness case
says why the question needs nothing else: the floor already applies the
rules file, and the order is all the level definitions add. Its registry id is
`work-on/review-level-fits-facts`.

**R8. Fixture profile.** Every `untrusted` or `trusted` criterion has a fixture
file of at least 10 good cases, at least 20 seeded-bad cases (a known-bad
input made from a good one by one targeted change) and at least 5 adversarial
cases (input written to steer the answer). Every case names its kind, its
expected answer (`pass` for a good case, `fail` for a seeded-bad or
adversarial one), its input as the slice script reads it and the slice the
script prints from that input. Every adversarial case names one technique from
the closed set `instruction`, `authority-claim`, `fake-answer`,
`hidden-comment`, `vocabulary-mimicry`, `role-line`, and a file uses at least
3 distinct techniques.

**R9. Fixture runner and fixture bar.** A shirabe script runs a criterion's
fixtures against Jev with the question, descriptions, label and threshold of
the criterion's declaration in its template, from a maintainer's session with
their own key. Each case's answer is `pass`, `fail` or `unclear` (the escape,
or no value at or above the threshold), mapped as koto maps it, or `error`
when Jev gave no readable answer after koto's one retry. The fixture bar is
met when no seeded-bad or adversarial case is answered `pass`, at least 80% of
good cases are answered `pass`, and no case is `error`. The runner prints the
counts by kind and answer and exits 0 when the bar is met; 1 when it isn't;
and 2, sending nothing, without a key, for a criterion no template declares,
or for a fixture file that fails R8, and 2 also when every case is `error`.

**R10. Live bar from exported decider events.** The figures are computed over
decider events of every mode from any host, within a window whose bounds are
recorded on the live record. It starts on the later of the contract's
`declared` date and the day after the latest recorded false pass's evaluation
date, ends on the date the figures were read, includes both, and is in UTC by
event timestamp.

- An evaluation is a distinct (session, visit, check, criterion) tuple, read
  from the exported attributes `koto.session.id`, `koto.visit.seq`,
  `koto.check` and `koto.rule.id`, with at least one `decider_checked` or
  `decider_fallback` event for the criterion. A fallback koto writes again on
  a re-evaluation falls in the same tuple and counts once.
- An evaluation is answered when any of its `decider_checked` events has
  `koto.decider.outcome` `pass` or `fail`. A tuple whose only events are
  fallbacks, or `decider_checked` with any other outcome, is unanswered, and
  an agent's own answer (`decider_check_answered`) never makes it answered.
- The bar is met with at least 30 evaluations across at least 5 sessions, at
  least 95% of them answered, no `decider_fallback` whose `koto.decider.reason`
  is `over_budget`, and no `koto.decider.input_bytes` on either event above
  the budget.

A guide states queries that compute these figures from the exported events,
and a shipped reference reader computes the same figures from koto session
logs, skipping any line it can't read and counting how many it skipped.

**R11. Confirmed false passes.** A confirmed false pass is an evaluation the
decider answered `pass` where one of these oracles showed the slice violated
the criterion:

- `review`: a review-panel finding at the same head (the commit the slice was
  built from) that names what the criterion asks about, which the run then
  fixed; the evidence links the pull request and the finding.
- `ci`: a failing check at the same head whose failure is what the criterion
  asks about; the evidence links the check run.
- `human`: a person's report of the violation; the evidence links the issue
  or comment. It is the only oracle for an evaluation whose session has no
  commit to name.

It is recorded on the criterion's entry with the evaluation's date, the date it
was recorded, its oracle and its evidence link, in a pull request whose
reviewers confirm it by merging it. A false pass can be recorded against an
`untrusted` criterion too; it then moves the start of any later live window.

**R12. Promotion is a reviewed registry change.** A criterion becomes
`trusted`, and its rule `withhold: eligible`, only in a pull request that
changes its entry and records: `trusted_since`, equal to the live window's end
date; the fixture run (date, the model Jev reported, the fixture file's git
blob hash, counts by kind and answer, which must add up to the fixture file's
cases); the live figures
(window, evaluations, sessions, answered share, over-budget fallbacks, largest
input); and the git blob hash of the slice script. CI refuses a `trusted`
entry missing any of these, with figures below R9's or R10's bar, whose live
window starts on or before the evaluation date of any recorded false pass,
whose recorded declaration, slice-script or fixture-file hash differs from the
repository's, whose rule isn't `withhold: eligible`, or whose template
declares it in a mode other than `veto`. CI also refuses an `untrusted` entry
that holds a promotion record. Nothing changes a contract state
automatically.

**R13. Demotion is a reviewed registry change.** A pull request that records a
confirmed false pass on a `trusted` criterion also returns it to `untrusted`,
removes its promotion record and sets its rule to `withhold: never`. False-pass
records are never removed, so a later promotion needs a live window that
starts after the latest one (R12). CI refuses a false-pass record missing a
field R11 lists.

**R14. Withhold only where the decider is active.** A shipped withhold script
takes a rule id, a session name and that session's directory, and prints one
path: the full rule file, or a withheld copy the script renders into the
session directory from the rule's file without the line range the registry
records for the rule, as the live canary renders its copy. It reads the
session log at `<session directory>/koto-<session name>.state.jsonl`. It
prints the withheld copy only when every condition holds:

1. the rule's entry is `trusted` and `withhold: eligible`;
2. `koto config get decider.mode` prints `auto`;
3. `koto config get decider.api_key` exits 0;
4. the working directory has no `.koto/config.toml`, or it has no `decider`
   table or `decider.` key;
5. the session log holds, for the entry's (check, criterion), no
   `decider_checked` event whose mode isn't `veto`, no `decider_fallback`
   event and no `decider_check_answered` event.

Otherwise, including when any input can't be read (koto missing or exiting
non-zero, a missing or malformed session log, a registry entry that can't be
read), it prints the full file's path.

**R15. An unanswered check delivers the rule.** A state that loads a rule
through the withhold script directs the agent, when koto lists the criterion
under the check's `awaiting`, to run `rule-registry.sh release <rule id>`
before answering. That existing command prints the rule's text between its
marker lines. By R14's condition 5 the full file is loaded on every later call
in that session. The registry check refuses a template that calls the
withhold script for a rule from a state whose directive lacks that
instruction, and refuses an `untrusted` or `trusted` entry whose text
`release` can't print.

**R16. No change in what users load.** No template calls the withhold script
in this feature. Apart from R7's slice line and R18's removed callers, no
directive, slice or route changes.

**R17. Untrusted Jev criteria are never withhold-eligible.** Every Jev
criterion's rule is `withhold: never` unless its contract is `trusted`. This
applies to `rs-007` to `rs-017`, which are `eligible` today.

**R18. The review-shadow trial reads koto decider events.** The trial's local
store, under `$REVIEW_SHADOW_HOME` (by default `shirabe/review-shadow` in
the user's XDG state directory), is retired: no
skill or script writes or deletes it, and none reads it on its own, so
existing data on a user's disk stays where it is. The measurement script reads
records only from a directory its caller names, which is how the
`review-shadow-records` figures were taken. `review-shadow.py` loses its `grade`, `outcome`, `site`
and `report` subcommands and their tests. The callers in `/work-on`'s
`panel-scope.sh` and the `/brief`, `/prd` and `/review-plan` phase files are
removed. The trial's figures are R10's figures, read from decider events for
each criterion a koto template declares, which today is `level_fits_facts`;
`rs-007` to `rs-017` produce no events until a contract lets one run.
`criteria.json` keeps their definitions, which their contracts describe, and
`review-shadow.py scan` keeps running `rs-001` to `rs-006`.

### Non-functional

**R19. No koto change and no koto floor change.** The feature uses koto
0.20.0's decider checks, fallback and exported events as they are.

**R20. Jev and measurement stay in a maintainer's session.** The fixture
runner and the measurement scripts run only from a maintainer's session, and
the reference reader reads logs already on disk. CI runs their tests against
stubs and runs none of them against a live endpoint or a user's data.

**R21. Public repository.** Contracts, fixtures, figures and guides name no
private repository, path or record. Figures are aggregate counts and sizes
from R1's closed populations.

## Acceptance Criteria

Registry contracts:

- [ ] `references/rule-registry.json` has an entry with a contract for
  `work-on/review-level-fits-facts` and for each of `rs-007` to `rs-017`, in
  the state the Problem Statement's table gives it, and
  `scripts/check-rule-registry.sh` fails on a Jev entry missing any field R1
  lists for its state. (R1, R2, R7)
- [ ] The registry check fails a contract whose `slice_script`, completeness
  path or `fixtures` path doesn't exist, or whose completeness heading isn't a
  heading in that file. (R1)
- [ ] The registry check fails a contract with an empty `sources` list, a
  source whose writer isn't in R3's vocabulary, or a `gate-script` source
  whose named script doesn't exist. (R3)
- [ ] The registry check fails a contract with neither `measured` nor a
  `not_measured` reason from its closed set, or with a population outside its
  closed set. (R1, R4, R21)
- [ ] The registry check fails each state whose condition in R2 doesn't hold:
  a contract with more than 5% of measured runs over budget, or an
  `insufficient` completeness verdict, that isn't `rejected` (exactly 5%
  passes); a `blocked` contract a template declares; an `untrusted` contract
  no template declares; a decider check in a template with no registry entry;
  and a template declaring a `rejected` or `blocked` contract. (R2, R6)
- [ ] The registry check fails a contract budget or a `max_bytes` above 2,560,
  a budget that differs from its gate's `max_bytes`, and a gate whose command
  doesn't run the contract's `slice_script`. (R3, R5)
- [ ] The registry check fails an `untrusted` or `trusted` contract measured
  over fewer than 100 runs. (R6)
- [ ] `work-on/review-level-fits-facts`'s contract is `untrusted`, has budget
  2,048, names `skills/work-on/scripts/review-level.sh` as its slice script and
  records at least 100 measured sessions. (R2, R6, R7)

Measurement:

- [ ] The measurement scripts ship, and a test runs each over a fixture corpus
  with its network calls stubbed to fail, and gets the figures that corpus
  should give. (R4, R20)

Slice:

- [ ] `review-level.sh slice` prints the order line, and a test pins the
  slice's exact output for a known facts key, and checks it is under 2,048
  bytes for facts with every class the rules file defines, every boolean true
  and 19-digit line and file counts. (R7)

Fixtures:

- [ ] `level_fits_facts` has a fixture file with at least 10 good, 20
  seeded-bad and 5 adversarial cases using at least 3 techniques, and CI fails
  a fixture file below any minimum, with a case missing its kind, expected
  answer, input or slice, or with an adversarial case whose technique isn't in
  R8's set. (R8)
- [ ] A test runs the slice script on every fixture case's input and fails
  when its output differs from the case's slice. (R8)
- [ ] Given a stub endpoint, the fixture runner sends one request per case
  with the question, descriptions, label and threshold read from the template,
  and exits 0 when the bar is met; it exits 1 for a run with one seeded-bad
  pass, one adversarial pass, 7 of 10 good passes, or one `error` case among
  answered ones, and 0 for 8 of 10 good passes with no other failure. (R9)
- [ ] The fixture runner exits 2 and sends nothing without a key, for a
  criterion no template declares, or for a fixture file below R8's minimums,
  and exits 2 when the stub endpoint fails every request. (R9)

Live bar, promotion and demotion:

- [ ] The reference reader computes R10's figures from a fixture session log,
  counting a fallback that koto wrote again on re-evaluation once, a tuple with
  a fallback and a later `pass` as answered, an agent-answered tuple as
  unanswered, events outside the window as absent and events on its first
  and last day as present, and skipping and counting a malformed line. Its bar
  verdict fails at 29 evaluations, at 4 sessions, at 94.9% answered, with one
  `over_budget` fallback, and with an input one byte over budget, and passes
  at 30, 5 and 95%. (R10)
- [ ] The guide has a section with the queries for R10's figures, a section
  for a promotion pull request and a section for a demotion pull request, and
  a doc test fails if any of the three headings is missing. (R10, R12, R13)
- [ ] The registry check fails a `trusted` entry missing `trusted_since`, the
  fixture record, the live record or the slice-script hash; whose fixture
  counts don't add up to its fixture file's cases; with recorded figures below
  R9's or R10's bar; whose live window starts on or before a recorded false
  pass's evaluation date; whose declaration, slice-script or fixture-file hash
  differs from the repository's; whose rule isn't `withhold: eligible`; or
  whose template mode isn't `veto`. It also fails an `untrusted` entry holding
  a promotion record. (R12, R13)
- [ ] The registry check fails a false-pass record missing its evaluation date,
  recorded date, oracle (from `review`, `ci`, `human`) or evidence link. (R11)
- [ ] Every Jev entry that isn't `trusted` is `withhold: never`, `rs-007` to
  `rs-017` included, and the registry check fails one that isn't. (R17)

Withholding:

- [ ] The withhold script prints the withheld copy's path when all five of
  R14's conditions hold, and the full file's path when any one fails; tests
  cover each condition failing alone, koto missing, koto exiting non-zero, a
  missing session log, a malformed session log and an unreadable registry
  entry. (R14)
- [ ] With a `decider_fallback` or `decider_check_answered` event for the
  entry's check and criterion in the session log, the withhold script prints
  the full file's path on every call, and an event for another criterion of
  the same check doesn't change its answer. (R14, R15)
- [ ] `rule-registry.sh release work-on/review-level-fits-facts` prints the
  rule's text between its marker lines, and the registry check fails an
  `untrusted` or `trusted` entry whose text `release` refuses. (R15)
- [ ] The registry check fails a template that calls the withhold script from
  a state whose directive doesn't name `rule-registry.sh` `release` with the
  rule's id. (R15)
- [ ] No template calls the withhold script, and no koto template's states,
  gates, directives or routes differ from the base branch's; only comments may
  change. (R16)

Review-shadow trial:

- [ ] `review-shadow.py` has no `grade`, `outcome`, `site` or `report`
  subcommand and no code that names `REVIEW_SHADOW_HOME` or the store path;
  `panel-scope.sh`, the `/brief` and `/prd` phase 4 files and the
  `/review-plan` phase 5 file no longer call it. (R18)
- [ ] `review-shadow.py scan` still runs `rs-001` to `rs-006`, and its tests
  pass. (R18)

Floor, CI and visibility:

- [ ] `scripts/assert-koto-floor.sh` still reads 0.20.0. (R19)
- [ ] No workflow under `.github/workflows/` runs the fixture runner, a
  measurement script or the reference reader other than through their stubbed
  test suites. (R20)
- [ ] `shirabe validate --visibility=public` passes on every document this
  feature adds or changes, and the review panel finds no private repository,
  path or record named in the contracts, fixtures or guide. (R21)

## Out of Scope

- Batching several review criteria into one Jev call for scrutiny panels,
  which is separate follow-up work held to the same slice-contract rule.
- Any budget above 2,560 bytes, and re-running the Jev spike.
- Offline ablations, long eval runs, or anything that runs outside a session.
- Dashboards or a measurement model over the exported events.
- The lifecycle of deterministic script checks, which is its own feature and
  excludes model-graded criteria.
- Changes to koto, including a fixture runner for decider-check criteria in
  `koto decider report`.
- Promoting any criterion, and wiring a withheld rule into a template. No
  criterion meets the bar when this ships, and the one in-run criterion,
  `level_fits_facts`, checks a rule whose text isn't preloaded in any
  directive (the facts floor is enforced by a script and defined in a
  reference the directive only points to). Wiring belongs in the promotion
  pull request of the first criterion whose rule is preloaded.
- Giving `/brief`, `/prd`, `/plan` or `/review-plan` a koto workflow so their
  blocked criteria could run.

## Known Limitations

- Live figures can't accumulate until a host opts its decider in, so the live
  bar can't be met until someone does.
- Whether a user's decider is active is read from koto's configuration before
  the check runs, because koto has no command that prints the effective mode.
  The read is conservative: any project decider setting, or anything
  unreadable, loads the rule.
- `rs-014` has no real-run record: the review-plan site wrote none, and PLANs
  are deleted when their work lands. It is `blocked` regardless, since `/plan`
  has no koto state.
- A false pass is only as visible as the oracles that catch it. A criterion
  can look clean because nothing downstream looked.

## Decisions and Trade-offs

**A whole session's units as one slice.** koto sends one slice per gate
evaluation, so a criterion that judges every unit of a session has to fit
them all in one slice. The review-shadow slicers packed one unit per request
and dropped parts that didn't fit; neither works inside a koto gate. Measuring
at that granularity is what rejects most current candidates, and per-unit
checking is left to the batching work that follows this feature.

**Contracts live in the rule registry.** A separate contracts file would put a
second definition of each criterion beside the registry, which is already the
one place a shirabe rule is defined. The registry gains a decider check kind
and a contract object, and its checker enforces them.

**shirabe runs fixtures itself.** `koto decider report --fixtures` judges only
accepts-field deciders, not decider-check criteria. Adding that to koto is out
of scope, so shirabe ships a small runner that asks Jev the way koto does and
keeps its results in the promotion pull request.

**The bar's numbers.** The fixture minimums follow the spike's profile (12
good, 22 bad, 6 adversarial per criterion) rounded down to 10, 20 and 5, and
the technique set is the spike's six. The live bar's 30 evaluations match
koto's own promotion minimum of 30 paired observations; 95% answered leaves
room for an occasional provider error; 5 sessions keep one long session from
standing in for many. The 100-session measurement floor is what the one
in-run criterion already exceeds and keeps a measurement from resting on a
handful of runs. A false pass is dated by its evaluation, not by when it was
recorded, so a miss found late still counts against the trust in force when
it happened.

**Retire the trial's store rather than port it.** The store produced no
usable evidence, its document sites read files the skills no longer write, and
koto's events already carry what a criterion's figures need. Porting the
grade and site writers to emit koto events would keep a second grading path
beside koto's.

**Build the withholding check without wiring it.** The one in-run criterion
checks a rule that isn't preloaded, so wiring it would withhold nothing.
Shipping the check with tests, and refusing any template that calls it without
the fallback instruction, keeps the first real withholding to a reviewed
promotion.
