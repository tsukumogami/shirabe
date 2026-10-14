---
schema: prd/v1
status: Draft
problem: |
  Every shirabe rule is preloaded into an agent's instructions, including
  rules a koto gate already checks after the agent acts, and nobody can say
  which of those still need preloading. The offline ablation that was to
  measure it has stopped. Real /work-on runs report each broken rule to
  Datadog, but every run sees the same instructions, koto exports no variable
  values, and the registry marks every gate-checked rule as never to withhold.
goals: |
  For one rule the /work-on pull-request gate already checks, about half of
  standalone /work-on runs go without its text and half keep it. The split of
  its broken rate between the two groups can be read in Datadog with one query
  run from a session. Nothing new runs outside a session, a withheld run still
  gets the rule's text when it breaks the rule, and one change turns it off.
upstream: docs/briefs/BRIEF-offload-live-canary.md
---

# PRD: Live Offload Canary

## Status

Draft

## Problem Statement

shirabe preloads its rules into the instructions every agent reads, and a
rule that a koto gate checks after the agent acts costs those tokens on every
run whether or not the agent needs the warning in advance. The question that
decides whether such rules can move out of the preloaded text is empirical:
when an agent isn't told the rule, how much more often is it broken, given
that the gate catches it either way?

The planned way to answer it, an offline ablation in shirabe's eval harness,
stopped on 2026-10-14. The owner asked for the work to be measured live, on
real runs, from what Datadog already receives, with nothing new running
outside a session. Four facts stand in the way today:

- Every run is given the same instructions, so a rule's broken count from
  koto's `check_rule` events has nothing to be split by.
- koto exports names, not values: the template on `session_started`, the
  state on `state_entered`, and the gate and rule id on `check_rule`. A koto
  variable's value never reaches Datadog.
- A passing check records no rule. `check_rule` is written only for a failing
  gate, and `check_evaluated`, which a pass writes, reaches Datadog without its
  gate name because its `koto.check` string collides with the `koto.check.*`
  fields. A rule's pass count can't be read per check.
- `references/rule-registry.json` marks all 21 gate-checked rules
  `withhold: never`, and its check forces that for any gate rule: a gate rule
  must guard an action, and any guard forces `never`. No rule an output gate
  checks is eligible to withhold.

The volume is enough to measure with. Over the seven days to 2026-10-14,
Datadog recorded 64 `/work-on` sessions, and 46 sessions entered
`pr_creation`.

## Goals

- One rule an existing `/work-on` output gate checks is withheld from about
  half of standalone `/work-on` runs and kept in the other half, chosen at
  random when each run starts.
- Each run's group can be read from events koto already exports, and a single
  Datadog query run from a session splits the rule's broken rate by group.
- A run that wasn't given the rule and breaks it gets the rule's text from the
  gate that caught it.
- One small, named change turns the canary off.
- Nothing new runs outside a session: no exporter, sender change, service or
  scheduled job, and no offline ablation.

## User Stories

- As the maintainer working on instruction offload, I want each run's group
  and the rule's broken occurrences to be readable in Datadog, so that after a
  week of ordinary work I can compare the rule's broken rate between runs that
  were told it and runs that weren't, without running anything outside a
  session.
- As an agent in a `/work-on` run that wasn't told the rule, I want the gate
  that catches a broken rule to give me the rule's text, so that I can fix the
  pull request in the same state instead of guessing.
- As an agent in a run that was told the rule, I want my instructions to be
  exactly those of a run with the canary off, so that the comparison group
  measures today's behavior.
- As the maintainer, I want to turn the canary off with one change named in
  the guide, so that a problem found in the withheld group stops at the next
  run.
- As a reviewer of the registry, I want the reason the withheld rule is
  eligible written next to the rule, so that the change to the registry's
  withhold safety can't spread to rules that guard pushing, merging or opening
  a pull request.

## Requirements

### Functional

- **R1. The rule.** The canary withholds exactly one rule:
  `pr-body/no-heading-in-part1` (PB4, no markdown heading in Part 1 of a pull
  request body). Its gate, `pr_body_conformant` in `/work-on`'s `pr_creation`
  state, runs after `gh pr create` and reads the pull request GitHub has, so
  the gate stands after the creation it would otherwise guard. A violation is
  fixed with `gh pr edit`, and CI's `shirabe validate --pr-body` blocks the
  merge independently. The DESIGN records why this rule was picked over the
  other gate rules.
- **R2. Eligibility.** The rule's registry entry is marked
  `withhold: eligible`, with `notes` stating why, and the registry check
  admits it. The change admits no other entry: every other gate rule, and every
  rule whose guards include `push`, `merge` or `pr-create`, stays
  `withhold: never`, and the registry check fails if any of them is marked
  eligible.
- **R3. Assignment.** When a standalone `/work-on` run starts, before its first
  state that asks for evidence, it is assigned to the withheld or the
  preloaded group at random, each with probability one half, independently of
  every other run. The assignment is held in a koto variable for the rest of
  the run and doesn't change on a resume, a rewind or a retry.
- **R4. Who takes part.** A `/work-on` run that `/execute` started on its
  shared branch (`SHARED_BRANCH` set) opens no pull request of its own and
  takes part in neither group. So does every run while the canary is off.
  Such a run's instructions are those of a run with the canary off.
- **R5. Withholding.** In the withheld group, no instruction the run loads
  before the `pr_body_conformant` gate first fails carries the rule's text or
  its rule id. That covers the `pr_creation` directive, the reference it
  points to for the pull-request format, and the conformance text it points
  to. The rule's text is left out by `{{VAR}}` substitution in the directive.
  The other PR-body rules (PB1, PB2, PB3) stay in the withheld group's text,
  unchanged.
- **R6. The preloaded group.** In the preloaded group, every instruction the
  run loads is byte-for-byte what a run with the canary off loads.
- **R7. The arm in exported events.** Each run that takes part enters exactly
  one state whose name identifies its group, and koto's `state_entered` event
  for it reaches Datadog with that name in `koto.state`. A run that takes part
  in neither group enters neither state.
- **R8. Readout.** A guide under `docs/guides/` names the exact event
  attributes and gives one Datadog query. Run from a session, the query
  returns, per group, the number of runs that entered `pr_creation` and how
  many of those had at least one `check_rule` event with `koto.rule.id`
  `pr-body/no-heading-in-part1`. The guide says why the denominator is runs,
  not passing checks.
- **R9. Delivery on failure.** When `pr_body_conformant` fails on this rule,
  its output, which koto returns to the agent, carries the rule's text from
  `references/pr-body-conformance.md` as well as the finding. That happens in
  both groups.
- **R10. Off switch.** One change, a single variable default in
  `/work-on`'s template, turns the canary off for every later run. The guide
  names the line and the value.

### Non-functional

- **R11. Nothing outside a session.** The canary adds no exporter, no change
  to the Datadog sender, and no service, daemon or scheduled job. Every new
  command runs inside a `/work-on` session as a koto action or gate.
- **R12. No ablations.** Building and testing the canary runs no offline
  ablation and no eval-harness run beyond what `scripts/check-skill.sh` runs.
- **R13. Failure is harmless.** If the assignment can't be made (a script
  missing or failing), the run continues in neither group, with the canary-off
  instructions, rather than stopping.
- **R14. Cost.** Assignment adds at most two states and one koto action to a
  run, and no state that waits for evidence.

## Acceptance Criteria

- [ ] `references/rule-registry.json` marks `pr-body/no-heading-in-part1`
      `withhold: eligible` with a non-empty `notes` reason, and it is the only
      `level: gate` entry marked eligible.
- [ ] The registry check fails when any other `level: gate` entry, or any
      entry whose `guards` include `push`, `merge` or `pr-create`, is marked
      `eligible`. A test case shows each failure.
- [ ] Over 200 draws, the assignment script picks each group at least 70
      times, and it picks neither group when `OFFLOAD_CANARY` is off or
      `SHARED_BRANCH` is set.
- [ ] A test drives a `/work-on` session in the withheld group to
      `pr_creation`, and the rendered directive and every file it names for
      the pull-request format contain neither the PB4 text from
      `references/pr-body-conformance.md` nor `pr-body/no-heading-in-part1`.
- [ ] The same test in the preloaded group renders a `pr_creation` directive
      byte-identical to the one rendered with the canary off.
- [ ] A session in the withheld group records a `state_entered` for the
      withheld marker state and none for the preloaded one, and the reverse
      for the preloaded group. A shared-branch session records neither.
- [ ] Given a pull request body with a heading in Part 1, the
      `pr_body_conformant` gate's output contains the
      `pr-body/no-heading-in-part1` finding and the PB4 text between
      `::shirabe-rule::` and `::shirabe-rule-end::`.
- [ ] Changing the one default the guide names to its off value makes a new
      session take part in neither group.
- [ ] The guide's query runs in Datadog from a session and returns one row per
      group with the runs and broken-runs columns.
- [ ] The diff adds no workflow file under `.github/workflows/` with a
      `schedule:` trigger, and changes no file outside this repository.
- [ ] CI is green on the pull request.

## Out of Scope

- **A second rule.** Only PB4 is withheld. A mechanism for choosing further
  rules is later work.
- **The `/execute` side.** `/execute`'s `pr_finalization` checks the same
  rule and keeps the text in every run. Its shared-branch children open no
  pull request and take part in neither group.
- **Dashboards, monitors and the measurement model.** They belong to the
  Datadog optimization work. The guide's query is the readout until they ship.
- **The `check_evaluated` gate-name collision.** It's fixed in the Datadog
  sender by the work that owns it, not here. The canary doesn't depend on it.
- **Linter check states and an escalation ladder** for repeated gate
  failures.
- **Offline ablations and the eval harness.**
- **Rules that guard pushing, merging or creating a pull request.** They
  stay `never`.

## Known Limitations

- **Contamination from outside the template.** The `pr_creation` reference
  tells the agent to apply its project's own PR-creation skill for Part 2,
  and an agent may already know the convention. Either can carry the rule into
  a withheld run, which narrows the measured difference toward zero. Neither
  is in this repository's control.
- **A small, low baseline.** About 20 to 30 runs reach `pr_creation` per group
  a week, and PB4 broke in none of the runs Datadog recorded in that week, so
  a difference shows up only as a count over several weeks.
- **Runs, not checks.** The rate is broken runs over runs that reached the
  state. A run that breaks the rule twice counts once.

## Decisions and Trade-offs

- **PB4 over the other gate rules.** PB1 shares its text with
  `commit/conventional-subject`, so withholding it withholds a commit rule
  too. PB2 (one separator) defines the two-part body every other check
  depends on. PB3 (no AI attribution) is public the moment the pull request
  opens and can't be taken back. The commit, branch, docs, panel and
  verification rules stand before a push or the pull request's creation. PB4
  is narrow, checked after creation, fixed by an edit and blocked at merge by
  CI. This choice depends on the coordinator's ruling on the registry's
  withhold safety.
- **Group visibility through state names.** koto exports no variable values,
  and the brief rules out an exporter. A marker state per group shows the
  group in `state_entered`, an event koto already exports.
- **Runs as the denominator.** A passing check carries no rule id, and in
  Datadog it carries no gate name either, so pass counts per rule aren't
  available. Runs that entered `pr_creation` are.
- **Delivery in both groups.** Releasing the rule's text on failure in both
  groups keeps the two identical except for the preloaded text, which is the
  one difference the canary measures.
