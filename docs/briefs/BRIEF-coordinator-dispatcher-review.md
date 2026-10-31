---
schema: brief/v1
status: Draft
problem: |
  The coordinate skill sends reviews, merges, verdict edits and finishing steps to
  "a person" where the coordinator that dispatched the session is meant, and its
  posture passage reads as if a merge grant lets a coordinator merge unreviewed.
  A dispatched coordinator ends up asking the workspace owner for a review its dispatcher owes it.
outcome: |
  Whoever dispatches a coordinator gets its finished work, milestone verdict pull
  requests included, for review before it lands, whether or not it holds a merge
  grant. A coordinator with no dispatcher sends the same step to a person, and a
  director with no merge grant passes up its own reading of a lane's work.
---

# BRIEF: Coordinator Dispatcher Review

## Status

Draft

## Problem Statement

A coordinator can be started by a person or by another coordinator. The
coordinate skill names two roles for this: a manager runs one lane, and a
director runs managers. When a director dispatches a manager, the director is
the one who should read the manager's finished work before it lands. The skill
mostly doesn't say so. Across `SKILL.md`, its references and the template's
directives, a review, a merge, an edit to a milestone verdict or a finishing
step goes to "a person", with no qualifier, in dozens of places.

shirabe#1259 fixed part of this. It reworded six passages so that a merge,
close or release a bound coordinator can't take goes to the coordinator that
dispatched it, and to a person only for a root coordinator. It left other
passages as they were, and those are the ones that decide who reviews:

- The milestone-roadmap verdict rule says a verdict's edit pull requests "must
  not be auto-merged without a person's review." That rule exists for a good
  reason: anyone using the coordinator's login can post a comment shaped like a
  verdict, so an independent review of the roadmap pull request is the control on
  Done. But a manager reading it hears that a person must review its verdict, when
  its director is the independent reviewer it should go to. The Glossary's
  redirect for "the human" doesn't reach a sentence that says "a person".
- The posture passage ends with "Never ask the human for a step the workspace
  already permits." That is an allowance, written as if it were a rule. A
  coordinator holding a merge grant can read it as permission to merge its own
  finished work without anyone looking at it first.
- The worker brief tells a worker which landing steps its grant covers, but never
  tells a worker dispatched with a merge grant to report its finished work for
  review before it merges.
- Nothing tells a director without a merge grant to read a lane's work itself. It
  can relay the lane's report upward as if it were its own recommendation.

The result is that review lands in the wrong place. A newly dispatched lane asks
the workspace owner for a review its dispatcher owes it, a merge grant looks
like a way around review, and the forgery control on Done can't say who the
reviewer is once the coordinator is not at the root.

## User Outcome

A person or director who dispatches a coordinator gets that coordinator's
finished work back for review before it lands, a milestone verdict pull request
included. That holds whether or not the coordinator holds a merge grant: review
before merge is something the skill always expects, and the grant only decides
who merges once the review is done. A coordinator nobody dispatched, at the root,
sends the same step to a person, so the control on Done still has an
independent reviewer at every level.

A director that holds no merge grant reads a lane's work itself and passes up
its own recommendation to merge, so the person above it gets a director's
judgment and not a forwarded report. A lane that was just dispatched sends its
review requests to its dispatcher from its first report, and never asks the
workspace owner for one.

## User Journeys

### A manager's milestone verdict goes to its director

A manager dispatched by a director finishes a milestone, writes its verdict
entry and opens the roadmap pull request that sets the milestone Done. The skill
tells it the pull request needs review by the coordinator that dispatched it, so
it reports the pull request to the director, which reviews it before it merges.
The manager never merges it and never asks a person for it.

### A merge grant doesn't skip review

A manager holding a merge grant has finished lane work ready to land. Before it
merges, it sends the work to its director for review. The grant is used after
that review, to take the merge itself instead of handing it up.

### A director with no merge grant gives its own reading

A director dispatched by a person, with no merge grant, receives a lane's ready
pull request. It reads the work against the lane's brief and the milestone's
Evidence and sends the person its own reading with a recommendation to merge,
not the manager's report passed through.

### A granted worker reports before it merges

A worker dispatched with a merge grant finishes its pull request. Its brief tells
it to report the finished work to its coordinator for review before it merges
anything, so the grant never lets it land unreviewed work.

### A root coordinator sends review to a person

A coordinator started by a person, with no dispatcher above it, opens a
milestone verdict pull request. The rule that sends a bound coordinator's review
to its dispatcher sends this one to a person, because no dispatcher exists. The
same holds for a root director's own verdict pull requests: no class of pull
request is carved out of the rule.

## Scope Boundary

**In scope:**

- Every passage in the coordinate skill (`SKILL.md`, the files under
  `references/`, and the template's directives) that sends a review, a merge, a
  verdict edit or a finishing step to "a person": each is checked, and each one
  where the dispatching coordinator is meant is changed to name it.
- The milestone-roadmap verdict rule's wording, keeping its purpose as the
  control on Done and naming the dispatcher as the reviewer for a bound
  coordinator.
- The posture passage's "Never ask the human" sentence, so it no longer reads as
  letting a merge-capable coordinator skip review.
- The worker brief template's lines for a worker dispatched with a merge grant.
- What a director with no merge grant is told to do with a lane's ready work.
- One definition of who reviews a coordinator's work, which the reworded
  passages point to.
- The skill's tests, and the template's compatibility table if the template's
  structure or a gated script changes.

**Out of scope:**

- Naming the manager and director roles in the skill's start and in the
  record. This work uses the words in prose only.
- Where a standing rule came from, and how its provenance is recorded.
- Who settles a step under an authority model, beyond who reviews.
- Which grants a lane holds or how a grant is chosen.
- Teardown, which no grant covers and which still goes to a person.
- A new review mechanism. The work changes what the skill and the template's
  directives tell a coordinator to do; a reader might expect a new state, gate
  or evidence field that enforces the review, and building one is separate work.
- Other open work on the coordinate skill that this wording doesn't need.

## References

- shirabe#1259, which reworded the first set of these passages and is the
  pattern this work follows.
- shirabe#730, which added milestone verdicts and the review rule that makes
  independent review of the roadmap pull request the control on Done.
- `skills/coordinate/SKILL.md`, its Glossary, Verdicts, Decisions and "What a
  Coordinator Never Does" sections.
- `skills/coordinate/references/brief-template.md`.
