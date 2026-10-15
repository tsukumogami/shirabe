---
schema: prd/v1
status: Done
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
absorbed:
  - docs/briefs/BRIEF-offload-live-canary.md
---

# PRD: Live Offload Canary

## Status

Done

The completeness, clarity and testability reviewers all passed it, the first
two on a second round. The downstream DESIGN owns the approach.

Absorbed [BRIEF-offload-live-canary](docs/briefs/BRIEF-offload-live-canary.md); carried in Absorbed Brief.

## Absorbed Brief

The feature exists so the question of whether a gate-checked rule still has
to be preloaded can be answered from real work rather than from paid offline
runs, which stopped on 2026-10-14. The brief framed the gap as live data that
can't be split: koto already reports each broken rule to Datadog, but every
run sees the same instructions, koto exports no variable values, a passing
check names no rule, and the registry marks every gate rule as never to
withhold. This document's Problem Statement states all four in full.

The outcome it asked for is a maintainer reading, in Datadog alone, how often
one gate-checked rule is broken in runs that were told it and in runs that
weren't, while the agents doing the work notice nothing but the missing text
and the gate's failure. Its four journeys are the User Stories above: the
maintainer reading the split after a week, a withheld agent breaking the rule
and recovering from the gate's output, the maintainer turning the canary off
with one change, and a preloaded agent breaking the rule anyway and counting
toward the baseline. Its scope line is this document's Requirements and Out of
Scope: one rule, `/work-on` only, no exporter or anything else outside a
session, and no rule that guards pushing, merging or opening a pull request.

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

The volume is enough to measure with: a few dozen `/work-on` runs reach
`pr_creation` in a typical week.

## Goals

- One rule an existing `/work-on` output gate checks is withheld from about
  half of standalone `/work-on` runs and kept in the other half, chosen at
  random when each run starts.
- Each run's group can be read from events koto already exports, and a single
  Datadog query run from a session splits the rule's broken rate by group.
- A run that wasn't given the rule and breaks it gets the rule's text from the
  gate that caught it.
- One small, named change turns the canary off.
- Nothing new runs outside a session: no exporter, change to koto's event
  export, service or scheduled job, and no offline ablation.

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

Terms used below. **The rule** is `pr-body/no-heading-in-part1`. **The rule's
text** is the lines its registry entry anchors in
`references/pr-body-conformance.md` (`text.first` to `text.last`, the PB4
paragraph). **The marker states** are `offload_arm_withheld` and
`offload_arm_preloaded` in `/work-on`'s template. **A canary-off run** is a
run started with the canary turned off by the switch in R10.

### Functional

- **R1. The rule.** The canary withholds the rule and no other. Its gate,
  `pr_body_conformant` in `/work-on`'s `pr_creation` state, runs after
  `gh pr create` and reads the pull request GitHub has, so the gate stands
  after the creation it would otherwise guard. A violation is fixed with
  `gh pr edit`, and the PR-body CI check, required on `main`, keeps the
  pull request from merging while it fails. The DESIGN records why this rule was picked over the other
  gate rules.
- **R2. Eligibility.** The rule's registry entry has `guards: ["none"]`,
  `withhold: eligible`, a `backstop` naming the deterministic check that still
  blocks the merge, and a non-empty `notes` stating why. The registry check
  passes on the real registry and admits no other change: it fails when any
  other `level: gate` entry is marked `eligible` without a backstop, when any
  entry whose `guards` include `push`, `merge` or `pr-create` is marked
  `eligible`, and when an eligible gate entry has empty `notes`. On a host that
  opted in, the PR-body PreToolUse hook stops denying the rule (and only this
  rule), so its violations reach the gate that counts them (owner ruling,
  2026-10-14).
- **R3. Assignment.** A standalone `/work-on` run is assigned to the withheld
  or the preloaded group once its analysis plan is ready, on the edge out of
  `analysis`, before implementation begins and well before `pr_creation`. The
  template's initial state stays `entry`, because the first tick after
  `koto init` carries the entry evidence and a state that accepts none would
  drop it. Each group is drawn with probability one half from
  the operating system's random source (`/dev/urandom`), independently of
  every other run. The assignment is held in a koto variable and recorded in
  the session's own directory. Re-entering the assignment state in the same
  session (a rewind, a resume, a retry) reads the recorded assignment back and
  draws nothing new, so a rewound run re-enters the same marker state, never
  the other one.
- **R4. Who takes part.** A run takes part in neither group when it was
  started on `/execute`'s shared branch (`SHARED_BRANCH` non-empty), when it
  is a canary-off run, when its host hasn't opted in, when the registry
  doesn't mark the rule `eligible`, or when the assignment fails (R13). Its
  instructions are byte-for-byte those of a canary-off run. A host opts in
  with a file, `${XDG_CONFIG_HOME:-$HOME/.config}/shirabe/offload-canary`,
  whose first line is `on`; without it no run on that host takes part, since
  only hosts that send events to the backend you read results from can be
  measured.
- **R5. Withholding.** In the withheld group, none of these carry the rule's
  text or the string `pr-body/no-heading-in-part1`: the rendered
  `pr_creation` directive, `skills/work-on/references/phases/phase-6-pr.md`
  (which the directive points to for the pull-request format), and the
  conformance text the directive names for the run. Every other line of
  `references/pr-body-conformance.md`, PB1 to PB3 included, is in the
  withheld group's conformance text unchanged. The rule's text is left out by
  `{{VAR}}` substitution in the `pr_creation` directive, which is the only
  directive that refers to the group.
- **R6. The preloaded group.** In the preloaded group, every rendered
  directive is byte-for-byte what a canary-off run renders, and the
  conformance text the run reads is `references/pr-body-conformance.md`
  itself.
- **R7. The group in exported events.** A run that takes part enters one
  marker state and never the other, and koto's `state_entered` event for it carries the
  marker state's name in `koto.state`, an attribute koto's event export
  already forwards. A run that takes part in neither group enters neither. No other
  template uses either name.
- **R8. Readout.** A guide, `docs/guides/offload-live-canary.md`, names the
  attributes (`koto.session.id`, `koto.state`, `koto.rule.id`) and gives one
  Datadog query that, over a chosen time window, joins events on
  `koto.session.id` and returns one row per group with two counts: distinct
  sessions that entered a marker state and then `pr_creation`, and how many of
  those had at least one `check_rule` event with `koto.rule.id`
  `pr-body/no-heading-in-part1`. A group with runs and no broken run shows 0. A
  session is counted once however often it entered `pr_creation` or broke the
  rule. Sessions with no marker state (shared-branch, canary-off, failed
  assignment, and runs started before the canary) are excluded. The guide says
  why the denominator is runs and not passing checks.
- **R9. Delivery on failure.** In both groups, when `pr_body_conformant`
  fails with a finding for the rule, the gate's output, which koto returns to
  the agent, carries the finding and the rule's text between a
  `::shirabe-rule::` line and a `::shirabe-rule-end::` line, as
  `rule-registry.sh release` prints it. A failure on other PR-body rules alone
  carries no copy of the rule's text, and a passing gate carries none.
- **R10. Off switch.** A declared `/work-on` variable, `OFFLOAD_CANARY`, with
  the values `on` and `off`, turns the canary on or off. Its default in the
  template is the one change that turns it off for every run started after the
  change. A run already in progress keeps the group it drew. The guide names
  the file, the line and the value. koto refuses any other value at
  `koto init`.

### Non-functional

- **R11. Nothing outside a session.** The canary adds no exporter, no change
  to koto's event export, and no service, daemon, cron entry or scheduled
  workflow. Every new command runs inside a `/work-on` session as a koto
  action or gate.
- **R12. No ablations.** Building and testing the canary runs no offline
  ablation and no eval-harness run beyond what `scripts/check-skill.sh` runs.
- **R13. Failure is harmless.** If the assignment can't be made (its script
  missing, not executable, or failing), the run goes on to
  `review_level_choice` in neither group, with canary-off instructions, and doesn't stop.
- **R14. Cost.** The canary adds three states to the template (the assignment
  state and the two marker states), one koto action, and no state that asks
  for evidence.

## Acceptance Criteria

Registry:

- [ ] `references/rule-registry.json` gives `pr-body/no-heading-in-part1`
      `guards: ["none"]`, `withhold: eligible` and non-empty `notes`, and it is
      the only `level: gate` entry marked `eligible`.
- [ ] The registry check passes on the real registry, and its test suite has
      a failing case for each of: another gate entry marked `eligible`, an
      entry guarding `push`, `merge` or `pr-create` marked `eligible`, and an
      eligible gate entry with empty `notes`.

Assignment (script tests, each draw a separate process):

- [ ] Over 200 draws in fresh session directories with the canary on and no
      shared branch, each group is picked at least 70 and at most 130 times.
- [ ] With `OFFLOAD_CANARY` `off`, `SHARED_BRANCH` non-empty, no opt-in file,
      an opt-in file reading anything but `on`, or the rule marked
      `withhold: never`, a draw picks neither group and the run reads
      `references/pr-body-conformance.md`.
- [ ] A second draw in a session directory that already holds an assignment
      returns the same group, 20 times out of 20.
- [ ] With the assignment script missing, or exiting non-zero, the
      assignment state routes to `review_level_choice` and no marker state
      is entered.

Template and rendering (koto sessions driven in a test, `gh` stubbed):

- [ ] `koto template compile` passes for `work-on.md`. The diff adds exactly
      three states, none with an `accepts` block; `analysis`'s `plan_ready`
      edge enters the assignment state, and the initial state is still
      `entry`, whose first-tick evidence still routes on.
- [ ] `koto init` with `OFFLOAD_CANARY=maybe` is refused, and attaching to a
      live session with a different `OFFLOAD_CANARY` value is refused, so a
      run in progress keeps its group after the switch changes.
- [ ] A session rewound to the assignment state after drawing a group enters
      the same marker state again and no other.
- [ ] A session in the withheld group records a `state_entered` for
      `offload_arm_withheld` once and none for `offload_arm_preloaded`; a
      preloaded session the reverse; a shared-branch session and a canary-off
      session neither. No other template under `skills/` defines either name.
- [ ] In a withheld session at `pr_creation`, the rendered directive,
      `phase-6-pr.md` and the conformance text the directive names contain
      neither the rule's first anchor line nor `pr-body/no-heading-in-part1`,
      and the conformance text equals `references/pr-body-conformance.md` with
      exactly the rule's anchored lines removed.
- [ ] In a preloaded session, a shared-branch session and a session whose
      assignment failed, the rendered `pr_creation` directive is
      byte-identical to the one a canary-off session renders.
- [ ] `{{` references to the assignment variable appear in no directive but
      `pr_creation`'s.

Gate output (`check-pr-output.sh` tests, `gh` stubbed):

- [ ] A body with a heading in Part 1 makes the gate exit 1 with the
      `pr-body/no-heading-in-part1` finding and the rule's text between
      `::shirabe-rule::` and `::shirabe-rule-end::`.
- [ ] A body that breaks only PB2 makes the gate exit 1 without the rule's
      text, and a conformant body exits 0 without it. A body that breaks PB4
      and PB3 carries both findings and the rule's text once.

Readout and guide:

- [ ] The guide names the file, line and value of the off switch, and a test
      fails if the template's `OFFLOAD_CANARY` default line differs from the
      guide's.
- [ ] The guide's query, run in Datadog over the week before the pull request
      with the marker state names replaced by a state every `/work-on` run
      enters, returns one row with a run count above 0, which shows the joins
      and the zero-broken case work on real events.

Boundaries:

- [ ] The diff adds no file under `.github/workflows/` with a `schedule:`
      trigger, changes no file outside `skills/work-on/`, `references/`,
      `scripts/`, `docs/` and `.github/workflows/`, and runs no eval workflow.
- [ ] `scripts/check-skill.sh work-on` passes, and every required CI check on
      the pull request is green.

## Out of Scope

- **A second rule.** Only PB4 is withheld. A mechanism for choosing further
  rules is later work.
- **The `/execute` side.** `/execute`'s `pr_finalization` checks the same
  rule and keeps the text in every run. Its shared-branch children open no
  pull request and take part in neither group.
- **Dashboards, monitors and the measurement model.** Dashboards are out of
  scope. The guide's query is the readout.
- **The `check_evaluated` gate-name collision.** A known export issue fixed
  outside this change. The canary doesn't depend on it.
- **Linter check states and an escalation ladder** for repeated gate
  failures.
- **Offline ablations and the eval harness.**
- **Rules that guard pushing, merging or creating a pull request.** They
  stay `never`.

## Known Limitations

- **Contamination from outside the template.** `phase-6-pr.md` tells the
  agent to apply its project's own PR-creation skill for Part 2, and an agent
  may already know the convention. Either can carry the rule into a withheld
  run, which narrows the measured difference toward zero. Neither is in this
  repository's control.
- **A small, low baseline.** The weekly sample per group is small and PB4
  rarely breaks, so a difference shows up only as a count over several
  weeks.
- **Runs, not checks.** The rate is broken runs over runs that reached the
  state. A run that breaks the rule twice counts once.
- **The rule's choice waits on one ruling.** Making PB4 eligible narrows the
  registry's withhold safety, which is the owner's call. Until it's made, the
  registry change isn't committed. If the ruling is no, no gate rule can be
  withheld under the registry as it stands, and the canary stops at its
  design.

## Decisions and Trade-offs

- **PB4 over the other gate rules.** PB1 shares its text with
  `commit/conventional-subject`, so withholding it withholds a commit rule
  too. PB2 (one separator) defines the two-part body every other check
  depends on. PB3 (no AI attribution) is public the moment the pull request
  opens and can't be taken back. The commit, branch, docs, panel and
  verification rules stand before a push or the pull request's creation. PB4
  is narrow, checked after creation, fixed by an edit and blocked at merge by
  CI.
- **Group visibility through state names.** koto exports no variable values,
  and the brief rules out an exporter. A marker state per group shows the
  group in `state_entered`, an event koto already exports. The maintainers
  decided this.
- **Runs as the denominator.** A passing check carries no rule id, and in
  Datadog it carries no gate name either, so pass counts per rule aren't
  available. Runs that entered `pr_creation` are, and the gate is evaluated
  once per entry. The maintainers decided this.
- **Delivery in both groups.** Releasing the rule's text on failure in both
  groups keeps the two identical except for the preloaded text, which is the
  one difference the canary measures.
- **The switch is fixed per run.** `OFFLOAD_CANARY` isn't rebindable, so
  turning the canary off never moves a run that already drew a group, and a
  run's group can't change partway through.
- **Opt-in per host.** shirabe is public, and a canary on for everyone would
  withhold the rule from runs whose events never reach the backend you read
  results from. Only a host with the opt-in file takes part, and turning the
  file on for a host is a separate step after the canary merges. The
  maintainers decided this.
