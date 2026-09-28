---
schema: brief/v1
status: Accepted
problem: |
  Maintainers plan to stop preloading some instruction sections and deliver
  them only when a check fails, but nothing in shirabe can say, before a
  section is withheld for real, whether runs without it break its rule more
  often or how many tokens withholding it saves.
outcome: |
  A maintainer about to withhold a section first runs the same scenario with
  and without it, reads a violation rate graded by the check that would
  deliver it and a token saving comparable to the committed baseline, and
  knows which of their decisions that data can settle offline.
motivating_context: |
  The instruction-token baseline and the provisional preloaded-rate
  definitions are pinned in docs/measurement/offload-baseline/. The next
  features want to withhold sections against that baseline, and each one
  needs a way to measure the withholding before it ships.
---

# BRIEF: Offline Ablation for Withheld Instruction Sections

## Status

Accepted

Written by `/scope` as the first hop of the offload-offline-ablation chain.

## Problem Statement

shirabe's koto-templated skills load every instruction up front: `SKILL.md`,
the state directives, and the references those name. The baseline in
`docs/measurement/offload-baseline/` counts that load at about 37,000
weighted tokens for one `/work-on` run and defines, provisionally, how often
a rule is broken while it sits in the agent's context. The plan built on that
baseline is to withhold some sections and deliver each one only when the
check that guards it fails.

Before anyone withholds a section, they need to know two things: does an
agent that never saw the section break its rule more often, and how much does
leaving it out save. Nothing in the repository answers either today.

- The eval harness runs a skill exactly as it ships. There is no way to run
  it with one section missing without editing the shipped files, and editing
  them changes what every real run loads.
- Grading is an LLM judge reading each scenario's expectations. That isn't
  the check a withheld section would rely on in production, so a pass under
  the judge says nothing about whether the deployed check would have caught
  the slip.
- Token counts aren't captured per run. The only figure is whatever the
  grading session writes into `timing.json`, which can't be set beside the
  baseline's per-profile counts.
- The without-skill arm already runs for every scenario and is thrown away
  ungraded, so the cheapest lower bound anyone could have is discarded.
- Nothing watches the rules nobody is measuring. A run that loses a section
  might also slip on rules next to it, and no run samples them.

Without a measurement, the first withholding would be decided by argument,
and the first evidence would come from real runs that already paid for any
mistake.

## User Outcome

A shirabe maintainer who wants to withhold an instruction section can find
out what that would do before any user's run is affected. They no longer
argue from the section's size or from intuition about whether agents need
it: they see how agents behave without it, judged the way production would
judge them, on the same footing as the pinned baseline.

What they read at the end is a violation rate per arm at both observation
points the baseline defines, a token saving they can set beside the pinned
figures, and a plain statement of what that many runs can and can't
distinguish. When the answer is "this run count can't tell", they know that
before they withhold anything, rather than taking "no difference seen" as
"safe".

## User Journeys

### A maintainer measures a section before withholding it

A maintainer preparing a feature that withholds a 4 KB reference section from
`/work-on` runs the ablation on that section with 20 runs per arm. The harness
builds a variant of the skill in scratch space without the section, runs the
three arms, grades each with the section's check, and writes a result record.
The maintainer sees the withheld arm's violation count at the first
production and after the section's text was delivered once, the token saving
per run, and whether the difference clears the uplift that section's size
would need to pay for itself.

### A reviewer re-derives a committed result

A reviewer looking at a pull request that cites an ablation result runs the
committed regeneration command. It reads the committed run records and prints
the same rates, token figures and detectable-uplift statement the pull request
quotes, without re-running any model session.

### An analyst excludes fixture runs from a real-run rate

An analyst computing the preloaded rate from the koto sessions real users
ran filters the population by template hash, as the baseline says. Ablation
runs use the same template text, so the hash alone would let them in. The
session's template source directory marks them as ablation fixtures, and the
analyst's filter drops them before any rate is computed.

### A process owner checks what a withholding costs elsewhere

Before approving a feature that withholds one section, the process owner
opens its ablation result looking not at the targeted rule but at the audit
of other script-checkable rules sampled in the same runs. When the withheld
arm breaks one of those neighbouring rules noticeably more often than the
full arm, the result says so, and the process owner can send the feature back
even though its own rule looked unaffected.

## Scope Boundary

**In scope:**

- Running an eval scenario with one named instruction section withheld,
  identified by its source location at the pinned commit, without touching
  the shipped skill files.
- Grading withheld, full and without-skill runs with the check that would be
  deployed for the section.
- Per-run instruction and total token capture comparable to the baseline pin.
- Recording both observation points the baseline defines.
- Sampled audits of other script-checkable rules in the same runs.
- A stated detection limit for a given run count, and which decisions it
  can settle offline.
- Marking ablation sessions so real-run measurements can exclude them.
- One end-to-end demonstration on a small section that already has a script
  check, with a committed command that regenerates its numbers.

**Out of scope:**

- Withholding any section from a normal run. Nothing a user's run loads
  changes.
- The full ablation study across every candidate section. Each later feature
  that withholds a section runs its own ablation with this harness.
- A rule registry, new gates, or linter check states. The ablation uses
  checks that already exist or are written for the demonstration section.
- A live canary on real runs, which is a later feature.
- Sections that guard irreversible actions (creating a pull request, pushing,
  merging, destroying a record) as demonstration candidates.
- Settling the provisional preloaded-rate definitions. The ablation uses them
  as pinned.
