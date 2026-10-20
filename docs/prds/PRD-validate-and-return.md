---
schema: prd/v1
status: Done
problem: |
  An agent whose fix to a gate-checked rule doesn't land sees the same one-line
  registry summary on every failure. Only PB4 ever returns its full text, by a
  special case the live canary added, and a check the agent can't satisfy
  either holds /work-on in place indefinitely or ends it through a field made
  for something else, so nobody can count which rules end runs.
goals: |
  Every /work-on output gate escalates on koto's own per-rule count: the
  summary on a rule's first failed evaluation, its full registry text from the
  second, and from the third a named exit that ends the run blocked. The exit
  is countable per rule in exported koto events and never passes a gate, and
  the canary's PB4 path runs on the same ladder.
absorbed:
  - docs/briefs/BRIEF-validate-and-return.md
---

# PRD: Validate-and-Return on koto Gates

## Status

Done

The completeness, clarity and testability reviewers passed it, completeness on
a second round. The downstream DESIGN owns the approach.

Absorbed [BRIEF-validate-and-return](docs/briefs/BRIEF-validate-and-return.md); carried in Absorbed Brief.

## Absorbed Brief

The feature exists so a rule's text reaches an agent when the agent breaks it,
in proportion to how badly its fixes are going, and so a check nobody can pass
stops a run on the record instead of looping. The brief framed three gaps: a
gate's text never grows past the summary, the one rule that returns its full
text (PB4, for the live canary) does it by special case, and a check that
can't be satisfied ends the run unrecorded or not at all. This document's
Problem Statement states all three in full.

The outcome it set: an agent gets more help each time, decided by koto's count
rather than its own; taking the exit ends the run as blocked and never moves it
past the gate; a withheld rule needs no release code of its own; and a
maintainer can read, per rule and from exported events, how often it failed,
reached its full text and ended a run. Goals and User Stories carry that
outcome.

Its journeys were a canary run's agent fixing PB4 on the second try, an agent
taking the exit after repeated commit-subject failures, and a maintainer
reading which rules end runs, plus two boundary cases kept as they are: a rule
fixed on the first try sees one summary, and a gate script run from a shell
outside a session prints today's output. User Stories and R3, R8 and R11 carry
them.

Its scope boundary put the escalating text for every `/work-on` output gate,
the exit at the three holding gates, PB4's move onto the ladder and the
registry reference in; and registry changes, an exit that passes a gate, an
exit at the non-holding states, the check lifecycle, decider checks,
`/execute`'s and `/scope`'s gates and any koto change out. Requirements and
Out of Scope carry it.

## Problem Statement

shirabe's rule registry (`references/rule-registry.json`, read only through
`scripts/rule-registry.sh`) gives each rule a gate reports a stable id, a
one-line summary and an anchored range holding its full text. `/work-on`'s
output gates print each violation as a `::koto-finding::` line through
`scripts/lib/rule-findings.sh`, whose message starts with the rule's summary:
the PR-body gate at `pr_creation`, the commit gate at `finalization`,
`deferral_approval` and `pre_pr_evidence`, the documents gate at
`pr_precheck`, the verification verdict at `verification`, and the panels'
verdict gates. koto 0.15.0, shirabe's floor, records on every failed check
event a count per rule of how many times that check has failed on that rule in
that state, over the visit and over the session, and its run journal exports
each count as `koto.rule.session_count` on a `check_rule` record.

An agent sees the same summary on its first failure and its fifth. The full
text, which already sits at a known range, is offered for one rule only: PB4
(`pr-body/no-heading-in-part1`), which `check-pr-output.sh` releases on every
PB4 failure because the live offload canary leaves PB4 out of the conformance
text that a random half of `/work-on` runs on opted-in hosts read. That release
is hard-wired to one rule in one script, and because it fires on the first
failure the canary can't tell whether the summary would have been enough.

Three of the gates hold the run on a violation and wait for a fix
(`pr_creation`, `finalization`, `pr_precheck`). When the fix can't be made,
the run loops, or the agent stops it through whatever field the state offers,
such as `pr_status: creation_failed_escalate`, whose recorded reason is a pull
request URL; `finalization` has no stopping edge at all, and `pr_precheck`'s
`blocked` fires only on the default branch. koto exports state names and rule
counts but no evidence values, so an exported event stream can count how often
a rule failed but not how often it ended a run.

## Goals

- An agent gets the ladder of R2 to R4: a rule's summary, then its full text,
  then an exit, on a schedule koto's counts decide.
- An agent facing a check it can't satisfy has one named way to stop, which is
  recorded and never moves the run past the gate.
- The canary's PB4 delivery needs no special case, and its readout can tell a
  summary that worked from a full text that was needed.
- A maintainer can count, per rule, failures by rung and runs that took the
  exit, from exported koto events alone.

## User Stories

- As an agent running `/work-on` whose PR body keeps failing a rule, I want
  the rule's full text once my first fix misses, so that I fix it from the
  rule rather than from a one-line paraphrase.
- As an agent that has failed the same rule three times on a holding gate, I
  want the gate to tell me there's a named exit and exactly how to take it, so
  that the run stops on the record instead of looping or misusing another
  field.
- As an agent in the canary's withheld group, I want PB4's summary the first
  time I break it and its full text if my fix misses, so that a rule I never
  read still reaches me.
- As an agent at verification or a review panel, which get no exit, I want the
  same escalating text, so that a repeated verification or panel finding comes
  with the rule behind it.
- As the canary's owner, I want each PB4 failure's count exported, so that I
  can split runs that fixed PB4 from the summary (no second failure) from runs
  that needed the full text.
- As a maintainer, I want to count per rule how often each rung was reached
  and how often a run took the exit, so that I can find checks or rules that
  nobody can satisfy.
- As the release owner, I want every rule that guards a push, a merge or pull
  request creation to keep blocking exactly as it does, so that the exit can't
  become a bypass.

## Requirements

### Functional

**R1. The ladder context.** A gate runs with the ladder when its command
supplies three values, written identically in every state that shares the
command: the path of the session's koto log (built from koto's `SESSION_DIR`
and `SESSION_NAME` variables), the gate's name as the template declares it,
and the template's exit table, which names each state with an exit and that
state's status field. The gate learns which state it runs in from the log: the
`to` of the latest `transitioned`, `directed_transition` or `rewound` event. A
gate whose command supplies none of the three runs without the ladder (R8).

**R2. The count.** For each rule a failing gate reports at `error`, the count
is 1 plus the highest `rule_counts[<rule>].session` on the `gate_evaluated`
events already in the log whose `state` and `gate` are this gate's, or 1 when
there is none. koto appends the current evaluation's event after the gate
exits, so the count is the value koto then records for this failure. A log
that is readable and holds no matching event gives count 1. The count measures
failed evaluations of the gate that reported the rule, as koto's does: a
`koto next` that re-evaluates a failing gate without a change raises it like a
failed fix. No value the agent submits, writes to context or passes outside
the template's command changes it.

**R3. Rung 1, the summary.** At count 1 a rule's finding is exactly what the
gate prints today: its message starts with the registry summary.

**R4. Rung 2, the full text.** For each distinct rule at count 2 or more, the
gate also runs `scripts/rule-registry.sh release <id>` once in that gate run,
which prints the rule's full text between its marker lines on standard error.
For a rule `release` refuses, that is `release`'s one-line refusal naming the
rule, followed by one line giving the rule's anchored reference (its
`rule_ref`, `<path>#L<first>-L<last>@<revision>`), so the agent still gets the
file and line range to read. The rules a
`/work-on` gate can report that `release` refuses today are
`pr-body/banned-word`, `pr-body/conformance`, `docs/private-only-type`,
`docs/visibility-vision-sections` and `docs/visibility-strategy-sections`.

**R5. Rung 3, the exit notice.** When at least one reported rule is at count 3
or more and the exit table names the current state, the gate prints one more
line on standard error, once per gate run, naming the rule with the highest
count (the first one the gate printed, when two share it), its count, the state's status field with the value
`check_unsatisfiable`, and the reason field `check_exit_reason`. A state the
exit table doesn't name gets no notice.

**R6. The thresholds.** The full text starts at count 2 and the exit notice at
count 3. Both are defined once, in `scripts/lib/rule-findings.sh`, and stated
in `references/rule-registry.md`.

**R7. The gate's result doesn't change.** The ladder never changes a gate's
exit status, its standard output, or the findings koto records. A `release` or
notice that fails to print leaves the result as it was.

**R8. Outside the template, nothing changes.** A gate script run without the
ladder context (from an agent's own shell, from a test, or from a template
that doesn't adopt, such as `/execute`'s) prints exactly what it prints today,
PB4's release on every PB4 failure included.

**R9. Fail toward more text.** When the ladder context is supplied but no
count can be read (the log is missing or unreadable, its first line isn't a
schema-version-1 koto header, or no state can be read from it), every reported
rule is treated as at count 2: its full text is released, and no exit notice
is printed.

**R10. The named exit.** `pr_creation`, `finalization` and `pr_precheck` each
accept the value `check_unsatisfiable` on their existing status field
(`pr_status`, `finalization_status`, `precheck_status`) and a new string field,
`check_exit_reason`. The submission routes on only while the state's registry
gate (`pr_body_conformant`, `commit_convention`, `branch_docs_visibility`)
exits 1. With that gate exiting 0, 2 or anything else, the submission matches
no edge and the state holds. The count-3 notice is when the gate offers the
exit; the template doesn't refuse it earlier, since taking it gains the agent
only a stopped run.

**R11. The exit is recorded.** The `check_unsatisfiable` edge goes to a marker
state, `check_exit`, which goes on to `done_blocked` and nowhere else. The edge
sets `failure_reason` to `check_exit at <state>: <gate> could not be satisfied:
<check_exit_reason>`. Entering `check_exit` writes a `state_entered` record
with `koto.state` = `check_exit` to koto's run journal, so runs that took the
exit are counted by that record, and its rule is read from the `check_rule`
records of the same session whose `koto.state` is the exit's state and whose
`koto.seq` is the highest below the marker's. When that evaluation failed on
several rules, the exit counts against each of them.

**R12. The exit never passes.** No path from `check_exit`, and no
`check_unsatisfiable` edge, reaches any state but `check_exit` and
`done_blocked`. Every gate rule whose registry `guards` include `pr-create`,
`push` or `merge` blocks exactly as before, and so does PB4.

**R13. Adoption.** These `/work-on` gates supply the ladder context:
`pr_body_conformant`; `commit_convention` in `finalization`,
`deferral_approval` and `pre_pr_evidence`; `branch_docs_visibility`;
`verification_verdict`; and `scrutiny_verdict`, `review_verdict`, `qa_verdict`
and `light_verdict`. A gate command shared by several states stays
byte-identical in each, as the template's consistency checks require.

**R14. PB4 on the ladder.** With the ladder context, `check-pr-output.sh`
releases PB4 only as R4 says: a withheld run that breaks PB4 gets its summary
at count 1 and its full text at count 2. The `pr_creation` directive and the
exit's wording stay identical across canary groups and never name PB4.

**R15. No registry change.** No entry in `references/rule-registry.json`
changes, and no rule becomes eligible to withhold.

**R16. Documentation.** `references/rule-registry.md` describes the ladder
context, the count, the three rungs and their thresholds, the unreleasable
rules, and the exit and how it's counted. The live canary's guide and design
say PB4's full text now arrives on the second failure.

### Non-functional

**R17. Cost.** The ladder reads the session log once per gate run, in one
pass, and only when the gate has a finding to print. Nothing is read on a
passing run.

**R18. Floors.** The ladder runs on shirabe's bash 3.2 floor and koto floor
(0.15.0), using only `jq` beyond what the gate scripts already need.

**R19. Directives.** The directives of `pr_creation`, `finalization` and
`pr_precheck` say that a failing gate's output escalates, that the exit is
offered from the third failed evaluation of a rule, how to take it
(`check_unsatisfiable` and `check_exit_reason`), and that taking it ends the
run at `done_blocked`.

## Acceptance Criteria

Ladder (a test drives a gate script with a fixture koto log):

- [ ] A log with a header and no `gate_evaluated` for this state and gate:
  the failing run prints the finding with its summary and no release block
  (R2, R3).
- [ ] A prior `gate_evaluated` for this state and gate with
  `rule_counts[R].session` 1: the failing run prints R's release block exactly
  once on standard error, and no exit notice (R4).
- [ ] Two rules, one at prior session count 1 and one at 3: each is released
  once (R4).
- [ ] Prior `rule_counts[R].session` 2 in a state the exit table names: the run
  prints R's release block and one notice line containing R's id, the count 3,
  the state's status field, `check_unsatisfiable` and `check_exit_reason` (R5).
- [ ] The same log in a state the exit table doesn't name: release block, no
  notice (R5).
- [ ] Two rules both at count 3: one notice line, naming the rule the gate
  printed first (R5).
- [ ] Counts recorded for R under another gate, another state, or for another
  rule leave R at count 1 (R2).
- [ ] With the same gate command, a count recorded under `finalization` leaves
  the count at `pre_pr_evidence` at 1, the state being read from the log's
  latest transition (R1, R2).
- [ ] A count claimed in a context key, an evidence field or an extra file
  changes nothing; only the log the command names is read (R2).
- [ ] Missing log, unreadable log, a first line that isn't a schema-version-1
  header, and a log with no transition: each failing run releases every
  reported rule and prints no notice (R9).
- [ ] At count 2 for each of the five unreleasable rules, the run prints
  `release`'s refusal line for it, then a line carrying its `rule_ref`; a test
  fails if that set changes for a `/work-on` gate (R4).
- [ ] For passing, violating and undecided runs, exit status and standard
  output are byte-identical with and without the ladder context (R7).
- [ ] Without the ladder context, `check-pr-output.sh --pr-body` on a PB4
  violation releases PB4 as it does today, and every adopting script prints
  what it prints today (R8).
- [ ] The ladder's tests pass under bash 3.2 in CI (R18).

Template (a test compiles and drives the shipped `/work-on` template):

- [ ] In each of `pr_creation`, `finalization` and `pr_precheck`, submitting
  `check_unsatisfiable` with a `check_exit_reason` while the registry gate
  exits 1 reaches `done_blocked` through `check_exit`, with `failure_reason`
  in the R11 format (R10, R11).
- [ ] The same submission while that gate exits 0 or 2 leaves the state where
  it was (R10).
- [ ] The run journal of a run that took the exit holds a `state_entered`
  record with `koto.state` = `check_exit`, preceded in the session by a
  `check_rule` for the failing rule at the exit's state (R11).
- [ ] In the compiled template, every `check_unsatisfiable` edge targets
  `check_exit`, and `check_exit`'s only target is `done_blocked` (R12).
- [ ] Every gate listed in R13 carries the ladder context, a test fails if one
  doesn't, and the three `commit_convention` copies stay byte-identical (R13).
- [ ] A PB4 violation at `pr_creation` with ladder context releases PB4's text
  at count 2 and not at count 1, and the canary's route tests pass unchanged
  in what they assert about directives (R14).
- [ ] Each of the three directives names `check_unsatisfiable`,
  `check_exit_reason` and `done_blocked`, and says the exit is offered from the
  third failure (R19).

Repository:

- [ ] `references/rule-registry.json` is unchanged by the pull request (R15).
- [ ] `references/rule-registry.md` has a section covering each item R16
  lists, and the canary guide and design no longer say PB4's text arrives on
  the first failure (R16).
- [ ] `scripts/check-skill.sh` passes for `work-on` (R13, R19).

## Out of Scope

- Changes to registry entries or to which rules may be withheld.
- An exit that lets a run past a failing gate, for any rule, PB4 included.
- An exit at `deferral_approval`, `pre_pr_evidence`, `verification` or the
  panels. `deferral_approval` is a person's approval with its own `rejected`
  stop; `pre_pr_evidence` ends the run on a violation; a failed verification
  goes back to implementation, which can stop; the panels have their own
  retry cap and `blocking_escalate`. All of them get the escalating text.
- `/execute`'s and `/scope`'s gates. They print through the same library and
  can adopt later by supplying the same context; until then they behave as
  today.
- The check lifecycle (shadow, warn, block, retire) and a dispute path for a
  check that fails wrongly.
- Decider checks, whose unanswered criteria already fall back to the agent.
- A koto change, including the session-feed contract's reserved `escalation`
  field.
- Offline ablations or long eval runs. The ladder's effect is read live from
  exported events.

## Known Limitations

- Five rules a `/work-on` gate reports can't reach rung 2's full text, because
  `release` refuses their text: two PR-body rules whose ranges exceed 60 lines,
  and three documents rules whose text is in a guide no skill loads. Their
  findings keep the summary and the `rule_ref`. Moving or splitting that text
  is a registry anchor change this feature doesn't make.
- The count is koto's, so a `koto next` that re-evaluates a failing gate
  without a fix moves the ladder on. An agent that re-queries twice sees the
  full text sooner, which costs nothing.
- After a rewind out of `done_blocked`, the session count keeps climbing, so a
  rule that already failed three times offers the exit on its next failure.
- `/execute`'s `pr_finalization` runs the same PR-body and commit scripts
  without ladder context, so it keeps today's output, including PB4's release
  on every failure, until it adopts.
- The exit table is written in the gate commands, so adding an exit to a state
  means editing that table in every adopting command; a template test checks
  the table against the states that have a `check_unsatisfiable` edge.

## Decisions and Trade-offs

**Full text at count 2, exit at count 3.** The brief left the counts to the
requirements. Count 2 is the first evidence that the summary didn't work, so
holding the full text back longer only costs a fix loop; releasing it at count
1 is what PB4 does now and is exactly what keeps the canary from learning
whether the summary sufficed. The exit opens one failure after the full text,
so an agent is offered it only after it has had the rule's whole text. The
`/work-on` panels already cap blocking retries at two or three with
`panel-retry-budget.sh`, so a third failure as the point to stop trying is
consistent with the run's other limits.

**Session counts, not visit counts.** A visit count returns to 1 when the run
leaves the state and comes back (a rewind out of `done_blocked`, or
`verification` sending the run back to implementation), so a run would see
the summary again for a rule it already failed twice. The session count keeps
climbing across visits, which is the escalation the feature is for.

**The gate reads koto's log rather than koto changing.** koto's per-rule
counts are on its published session-feed contract, koto appends and syncs
every event before it runs the next command, and shirabe's `panel-scope.sh`
already reads the same log. A koto change that hands a command its prior
counts would be cleaner, but no gap forces it, and the feature would wait on a
koto release.

**The state comes from the log, the exit table from the command.** The three
`commit_convention` copies must stay byte-identical, so nothing per-state can
sit in a gate command. The log already says which state the session is in,
and one table naming every exit state is the same text everywhere.

**The exit stops the run; it doesn't route around the gate.** An exit that
continued past PB4 (whose merge the PR-body CI check still blocks) would help
the one unguarded rule and complicate the template, because a gate's exit
status can't say which of its rules failed, and each gate with an exit also
reports rules that guard pull request creation or a push. A uniform stop is
the only shape that keeps R12.

**The exit is offered at count 3, not enforced there.** koto routes on a
command gate's exit status and nothing else, so refusing the exit below count
3 would need a new exit status from the gate scripts, which `/execute`'s gates
share. An early exit only stops the run, so there's nothing to enforce against:
the stop is recorded with the rule's count on the gate's last failure, and a
reader can see an exit taken at count 1.

**A marker state rather than evidence for the record.** koto's run journal
exports state names and rule counts but no evidence values, so a status value
alone would leave the exit uncountable. The marker state follows the canary's
`offload_arm_withheld` precedent.

**Fail toward more text.** When the counts can't be read, over-delivering a
rule's text costs a few lines; under-delivering is the problem this feature
exists to fix. Opening the exit needs a real count, so an unreadable log never
offers it.
