---
schema: brief/v1
status: Draft
problem: |
  Nobody can say whether a gate-checked rule still has to sit in the text an
  agent preloads. The offline ablation that was meant to answer it has
  stopped, and real /work-on runs already report each broken rule to Datadog,
  but nothing tells a run that was given the rule from one that wasn't.
outcome: |
  A maintainer reads, in Datadog alone, how often one gate-checked rule is
  broken in runs that were told it and in runs that weren't. The agents doing
  the work see no difference except the missing text and the gate's failure.
---

# BRIEF: Live Offload Canary

## Status

Draft

## Problem Statement

shirabe preloads every rule into an agent's instructions, including rules a
koto gate already checks after the agent acts. Each preloaded rule costs
tokens on every run, and for a rule a gate already enforces, the open question
is whether the agent needs the text in advance at all, or whether the gate's
failure message is enough to fix the output when it's broken.

Until now, the way to find out was an offline ablation: shirabe's eval harness
withheld an instruction section and graded paid runs against the deployed
check. That stopped on 2026-10-14. The owner ruled out the cost of running
every eval several times over and asked for the work to be measured live
instead, on real runs, from what Datadog already receives, with nothing new
running outside a session. The harness stays in the repository, but nothing
runs it and it no longer decides whether a rule may be withheld.

The live data is there, but it can't answer the question yet:

- koto writes a `check_rule` event to its run journal for every registered
  rule a failing gate reports, with the rule id, the gate and the state, and
  those events reach Datadog. A rule's broken count is already readable.
- Every run is given the same instructions, so there is no comparison to read.
  A broken count with nothing to split it by says how often agents break a
  rule they were told, not whether telling them mattered.
- koto exports names only: template, state, gate and rule id. It never exports
  a variable's value, so a run's settings can't be read from Datadog even
  where a template has them.
- A passing check doesn't record which rules it covered. `check_rule` is
  written only on failure, and in Datadog the `check_evaluated` event that a
  pass produces arrives without its gate name, because its `koto.check` string
  collides with the `koto.check.*` fields. So a rule's pass count can't be
  read per check.
- The rule registry (`references/rule-registry.json`) has a `withhold` field
  meant for exactly this work. Every rule a gate checks is marked `never`.
  The registry's own check forces it, because a gate rule must guard an
  action and any guard forces `never`. No rule the canary could take is
  marked eligible today.

## User Outcome

The maintainer deciding whether rules can move out of the preloaded text gets
a live, per-rule answer. For one rule a `/work-on` gate already checks, about
half of real runs go without the rule's text and the other half keep it. A
Datadog query, run from inside a session, splits the rule's broken rate by
those two groups. The sample grows with ordinary work, about thirty runs per
group a week at current volume, with no paid eval runs and no exporter,
service or scheduled job added outside a session.

The agents doing the work notice nothing unusual. One that wasn't given the
rule and breaks it gets the rule's text from the gate that caught it, and
fixes the output in the same state. One that was given it sees exactly the
instructions it sees today.

## User Journeys

### A maintainer reads the split after a week

The maintainer working on instruction offload wants to know whether the
rule's text is earning its tokens. From a session, they run the guide's
Datadog query over the last seven days. It returns, for each of the two
groups, how many runs reached the gate's state and how many of those had the
rule reported broken at least once. They compare the two rates without
opening a session log or running anything else.

### An agent without the rule breaks it and recovers

A `/work-on` run drew the withheld group when its workflow started, so the
directive that tells it how to author the pull request leaves the rule's text
out. The agent opens the pull request with output the rule forbids. The gate
holds the state, and its failure output carries the rule's text. The agent
edits the pull request and submits again, and the gate passes. Datadog
records one broken occurrence of the rule against a run in the withheld group.

### A maintainer turns the canary off

A withheld-group failure turns up that the gate didn't catch, or the
measurement is finished. The maintainer makes the one change the guide names,
and from the next run on every run gets the rule's text and enters neither
group, so a later readout doesn't mistake new runs for canary runs.

### An agent that was told the rule breaks it anyway

A run drew the preloaded group, so its directive renders the same instructions
a run gets today, rule included. The agent breaks the rule regardless, the gate
holds the state exactly as it does now, and the agent fixes the output. In the
readout that run counts toward the preloaded group's broken rate, the baseline
the withheld rate is compared against.

## Scope Boundary

**In:**

- Withholding exactly one rule from `references/rule-registry.json`, a rule
  that a `/work-on` or `/execute` output gate already checks, and recording
  why it was picked.
- Making that rule eligible to withhold if the registry's withhold safety
  forbids it today. That means changing the classification or the check,
  stating why the change is safe, and never extending it to a rule that guards
  pushing, merging or opening a pull request.
- Assigning each `/work-on` run to the withheld or the preloaded group at
  random, about half each, when its workflow starts, through a koto variable.
- Leaving the rule's text out of the withheld group's directive by `{{VAR}}`
  substitution, with the preloaded group's instructions unchanged.
- Making each run's group readable from events koto already exports, and a
  guide giving the exact attributes and the Datadog query that splits the
  rule's broken rate by group.
- Making sure a withheld-group agent gets the rule's text, or enough of it to
  fix the output, from the gate's failure output.
- One small change that turns the canary off, named in the guide.

**Out:**

- Withholding a second rule, or a general mechanism for choosing which rules
  to withhold.
- The `/execute` side. `/execute`'s own pull-request finalization checks the
  same rule and keeps the text for every run, and its `/work-on` children on a
  shared branch open no pull request, so they enter neither group.
- Linter check states and an escalation ladder for repeated gate failures,
  which are separate work.
- Datadog dashboards, monitors and the measurement model that will read the
  split routinely. The guide's query is the readout until those ship.
- Any exporter, sender change, service or scheduled job outside a session.
  The gate-name collision on `check_evaluated` is fixed in the Datadog sender
  by the work that owns it, not here.
- Running offline ablations or the eval harness.
- Rules that guard pushing, merging or creating a pull request, which are
  never withheld.

## References

- `references/rule-registry.json` and `references/rule-registry.md`: the
  registry, its `withhold` and `guards` fields, and `release`.
- `docs/designs/current/DESIGN-rule-registry.md`: Decision 6, how guards were
  classified.
- `docs/designs/current/DESIGN-output-gates.md`: the output gates that report
  rule ids.
- `skills/work-on/koto-templates/work-on.md`: the `pr_creation` state and its
  `pr_body_conformant` gate.
- `references/pr-body-conformance.md`: the PR-body rules the gate checks.
