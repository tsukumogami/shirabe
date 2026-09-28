---
schema: brief/v1
status: Accepted
problem: |
  shirabe is about to change what its koto-templated workflows load, but it
  has no fixed "before" to judge those changes against: template versions
  aren't distinguishable, "preloaded rate" has no definition, and the only
  instruction-token count was taken elsewhere, at an older commit.
outcome: |
  A maintainer judging an instruction change can name the template versions
  the "before" ran, read and re-run the per-skill token count at that commit,
  and count rule violations with a written, clearly provisional definition.
motivating_context: |
  Planned work removes dead prose from the work-on, execute, scope and deliver
  instructions, loads references per state, and eventually withholds rules
  behind checks. Each of those changes what a run loads, so the baseline has
  to be taken before the first one lands.
---

# BRIEF: offload-baseline-pin

## Status

Accepted

Both jury reviewers passed the brief (the content review on its second round). The downstream PRD owns the requirements.

## Problem Statement

Four shirabe skills run as koto workflows: `/work-on`, `/execute`, `/scope`
and `/deliver`. Work is lined up that changes what those workflows put in
front of the agent: deleting prose that tells the agent nothing, moving
references so each loads only in the state that uses it, and later
withholding a rule until a check shows it was broken. Every one of those
changes is supposed to be judged by what it does to two numbers: how many
instruction tokens a run loads, and how often each rule gets broken. Neither
number has a fixed "before" that a later measurement can compare against.

Three gaps make that true today.

- **Template identity isn't recorded.** Each of the templates declares
  `version: "1.0"` and none has ever bumped it, so the declared version says
  nothing about which text a run actually executed. A number gathered from
  runs can't be tied to the template that produced it, and runs from before
  and after a change blur together.
- **"Preloaded rate" has no definition.** The offload work is meant to
  leave a withheld rule broken at half its preloaded rate or less, a target
  that means nothing until the rate is defined. Nothing says what counts as one violation, what the
  denominator is, how a rule is named, or which attributes a record carries.
  Two people measuring the same transcripts would get different numbers.
- **The token count can't be reproduced from the repository.** A census of
  every instruction line the four skills load was taken in September 2026, at
  commit e592501. It lives outside shirabe, its method is written down only
  there, and shirabe has moved on since. A maintainer can't re-run it on
  their branch, and can't compare their branch with anything current.

Git history keeps the old text, so nothing is lost in principle. What's
missing is the agreed starting point: the commit, the per-template identity,
the count and the definitions, written down once where the next change can
point at them.

## User Outcome

A shirabe maintainer who lands a change to what these workflows load can
show what it did. They can name the exact template versions the "before" ran,
read the per-skill instruction-token load at that commit, re-run the same
count on their own branch and get a number that compares, and count how often
a given rule was broken while it was still preloaded, using a definition
written down in the repository. They know which parts of that definition are
settled and which are provisional, so a later refinement changes the
definition in one place instead of quietly changing what the numbers mean.

## User Journeys

### Comparing token load after an instruction cleanup

A maintainer finishes a branch that deletes rationale prose from the
`/work-on` directives. Before opening the PR they re-run the recorded token
count on the branch, set it beside the pinned baseline, and put the per-skill
difference in the PR description. A reviewer can check the claim by running
the same count.

### Tying a run's numbers to a template version

A maintainer measuring how often a rule was broken before the offload work
rebuilds the rate from retained run records, and wants only runs of the
templates as they stood before any instruction change. They look up each
template's identity in the pin, select the runs whose recorded template
matches it, and treat anything else as a different version, even though the
declared version string is the same.

### Refining a provisional definition

A maintainer settling the measurement definitions that other measurement
work shares finds that it counts a violation differently from the way
this baseline does. They open the preloaded-rate definition, see it
marked provisional, change it, and record why, without having to work out which earlier numbers depended on the old
wording, because the baseline says which definition it used.

### Re-keying rules when a rule registry lands

When each rule gets a stable id of its own, the maintainer doing that work
maps every rule the baseline names, today identified by file and line or file
and heading, onto its new id. The mapping is mechanical because the baseline
names rules by source location and says it expects to be re-keyed.

## Scope Boundary

**IN:**

- A committed, machine-readable pin of the koto workflow templates the four
  skills ship at one shirabe commit on main, with enough per-template identity
  to tell versions apart when the declared version string doesn't change.
- A written definition of preloaded rate per rule, with its counting rules and
  the attribute names a record carries, each marked provisional.
- The per-skill instruction-token baseline measured at the pinned commit with
  the census method, written down so it can be re-run, with the September 2026
  figures at e592501 kept beside it as the reference.
- Only as much tooling as it takes to re-run that token count.

**OUT:**

- Any change to what a run loads: no instruction edits, deletions,
  contradiction fixes or per-state loading. Those are the changes this
  baseline exists to measure, so doing any of them here would contaminate it.
- Measuring violation rates. This work defines them; the rates can be rebuilt
  later from retained run records.
- A rule-id scheme. Rules are named by source location until a rule registry
  gives them ids.
- Measurement tooling beyond the token recount: no dashboards, no event
  export, no transcript-parsing pipeline.
- Skills that don't run as koto workflows. They load instructions too, but
  the baseline covers the four templated skills and what they load.
- Settling the definitions for good. They're proposals for review and stay
  provisional until a separate measurement-definitions effort settles them.

## Downstream Artifacts

- `docs/prds/PRD-offload-baseline-pin.md`: requirements for the pin, the
  definitions and the baseline.
