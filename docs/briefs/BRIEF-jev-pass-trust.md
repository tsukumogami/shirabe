---
schema: brief/v1
status: Accepted
problem: |
  shirabe can grade an agent's work with Jev through koto decider checks, but
  nothing says which questions Jev can be trusted with, what its slice must
  hold, or when a Jev pass is good enough to stop loading a rule's text. So
  every Jev-checked rule stays preloaded for everyone, with no way to earn trust.
outcome: |
  A maintainer can read, for any Jev criterion, what its slice holds and why
  that is enough, its size on real runs, its fixture results and live figures.
  A rule whose criterion earned pass trust stops being preloaded only for users
  whose decider runs it, and a confirmed false pass reverses that.
---

# BRIEF: Jev criteria and pass trust

## Status

Accepted

## Problem Statement

A koto decider check sends a slice of an agent's work to Jev with a closed
question, and since koto 0.20.0 a criterion Jev can't answer falls back to the
agent instead of passing. That machinery exists. What doesn't exist is any
rule for deciding which questions belong on it, or how much a Jev pass is
worth.

Three gaps follow from that.

1. **No criterion says what its slice holds or how big it gets.** The one
   decider check shirabe runs inside a workflow, `level_fits_facts` in
   `/work-on`'s `review_level_check`, asks whether a level is too light "given
   these facts about a change and the review level definitions", but its
   slice carries the facts and the level and not the definitions. Other
   candidates were never measured against the budget koto enforces. Measured
   on this host's real runs, every comment-touching hunk of a change exceeded
   2,560 bytes on 69 of 70 merged pull requests, and a PR body's first part
   with its file list exceeded it on 31 of 80. A slice over budget is never
   sent, so such a criterion would fall back to the agent on most runs and
   save nothing. The Jev accuracy spike
   (`docs/spikes/SPIKE-jev-accuracy.md`) validated inputs only up to 2,507
   bytes.
2. **No criterion has earned trust, and nothing says how one would.** The
   spike recommended criteria for a decider design, "not for promotion: a Jev
   pass still has to earn trust from a non-agent oracle". The review-shadow
   trial (tsukumogami/shirabe#563) graded criteria beside review panels, but
   it kept its records in a local store on one machine, and that store
   produced no usable evidence: most per-site runs came back without a
   verdict. Meanwhile koto already records and exports decider events
   (`decider_checked`, `decider_fallback`), which is where live figures for
   any host would come from.
3. **There is no way to stop loading a checked rule, and no way to undo
   that.** A rule's text is in its state's directive for every user, whether
   or not a decider will check the result, so a run pays for reading a rule
   that a check could have enforced. Withholding it is only safe for a
   user whose decider is actually active, and only while the criterion keeps
   its record. Nothing tells a run which case it is in, and nothing turns a
   confirmed false pass into a demotion.

## User Outcome

A shirabe maintainer deciding whether a rule can be checked by Jev instead of
read by the agent can answer the question from the record instead of from
memory or hope. They can tell whether the criterion's slice is built by a
script the agent can't steer, whether it carries everything the question
needs, and whether it fits the budget on real runs; whether it held against
seeded-bad and adversarial cases; and whether it answers on nearly every live
run. A criterion that falls short is visibly rejected rather than quietly
shipped.

Once a criterion earns pass trust, which none has yet, a shirabe user whose
decider is active runs `/work-on` without that rule's text, and the decider
checks the work instead. A user without an active decider sees exactly what they see today.
When a criterion can't be answered in a run, the agent answers it with the
rule in front of it. When a reviewer confirms a false pass, the criterion
loses its trust through a reviewed change and the rule is loaded again.

## User Journeys

### A maintainer proposes a criterion and measurement rejects it

A maintainer wants a Jev check that every code comment a change adds gives a
reason rather than restating the code. Before any template changes, they
write its slice contract: the diff as the source, the script that extracts
comment-touching hunks, the case that those hunks are enough to judge, and
the measured size over recent real changes. The measurement shows the slice
exceeds the budget on almost every change, so the contract records the
criterion as rejected at that granularity, and no gate is added that would
fall back to the agent on most runs.

### A maintainer promotes a criterion to pass trust

A criterion has run in shadow for weeks. The maintainer runs its fixture set,
including seeded-bad and adversarial cases, against Jev from their own
session, and reads its live answer rate and slice sizes from the decider
events koto exported. Both meet the stated bar, so they open a pull request
that marks the criterion trusted and its rule eligible to withhold, with the
figures in the body. A reviewer checks the figures and merges it. Nothing
changed until that merge.

### A user with an active decider runs /work-on

A user whose koto decider runs in auto mode starts `/work-on`. When the run
reaches the state whose rule is checked by a trusted criterion, the directive
points at a copy of the rule file without that rule, and the decider grades
the result. A second user with no decider configured runs the same skill and
reads the full rule, as before.

### A criterion goes unanswered in a run

The decider times out on a trusted criterion. koto holds the check and asks
the agent to answer it. Before answering, the agent is given the rule's full
text, and for the rest of that run the state loads the rule again.

### A reviewer confirms a false pass

A review panel upholds a finding that a trusted criterion passed. The reviewer
records the false pass against the criterion in a pull request that also
demotes it and makes its rule ineligible to withhold. Once that merges, every
user's runs load the rule again.

## Scope Boundary

**In scope:**

- A slice contract for every candidate Jev criterion shirabe has today: its
  sources, the script that builds its slice, the written completeness case,
  and its measured size on real runs, with criteria that fail measurement
  recorded as rejected.
- The criterion format: where a Jev criterion and its contract live in the
  rule registry, and the checks that hold them to the templates.
- A slice budget ceiling of about 2.5 KB, the size the spike validated, with
  any larger budget refused.
- The fixture profile a criterion is run against, including seeded-bad and
  adversarial cases, and a way to run it against Jev from a session.
- The promotion and demotion bar, stated as figures over koto's exported
  decider events and fixture results, applied only through a reviewed
  registry change.
- Withholding a trusted criterion's rule only for a user whose decider is
  active, and loading it again after an unanswered check or a demotion.
- Moving the review-shadow trial off its local store onto koto decider
  events.

**Out of scope:**

- Batching several review criteria into one Jev call for scrutiny panels,
  which is separate follow-up work that this feature's slice-contract rule
  will also govern.
- Raising the slice budget above about 2.5 KB, which needs the Jev spike
  re-run first.
- Offline ablations, long eval runs, or any measurement that runs outside a
  session.
- Dashboards or a measurement model over the exported events.
- The lifecycle of deterministic script checks (shadow, warn, block,
  retirement), which is its own feature and excludes model-graded criteria.
- Changes to koto. The feature uses koto 0.20's decider checks, fallback and
  exported events as they are.
- Actually withholding a rule. No criterion meets the bar when this ships;
  promotion is a later reviewed change.
