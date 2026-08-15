---
schema: brief/v1
status: Draft
problem: |
  A PLAN's execution_mode answers three questions with one value: whether the
  work can land in a single PR, whether it should, and whether GitHub issues and
  a milestone get created. A repo cannot state a preference on either of the
  last two, and a plan that ends up multi-PR records nothing about why.
outcome: |
  An author plans a change and its delivery shape follows what the repo has
  stated it prefers; the tracking mechanism follows a separate stated
  preference; and any plan that is not single-PR carries, in the merged
  artifact, the reason it is not.
motivating_context: |
  Surfaced while reviewing how shirabe's own plans get shaped. The maintainer
  wants every plan that can be one PR to be one PR, and wants a multi-PR plan to
  be trustworthy evidence that no other option existed -- while recognizing that
  an org with many reviewers may legitimately prefer small atomic increments.
  Neither preference can be expressed today.
---

# BRIEF: Multi-PR Plan Decoupling

## Status

Draft

Framed from the exploration recorded on this branch. The downstream PRD owns the
requirements; the decisions the exploration already settled are carried in the
DESIGN rather than reopened here.

## Problem Statement

A PLAN carries one field, `execution_mode`, whose value is read as the answer to
three separate questions.

The first is a fact about the work: can this change land in a single pull
request, or does something force it apart -- work spanning more than one
repository, or a step that must be published, deployed, or merged to the default
branch before a later step can consume it. The second is a preference about how a
team likes to review: even where one PR is possible, some teams would rather read
several small ones. The third is unrelated to either: does this plan get GitHub
issues and a milestone, or does it carry its work items inside the document.

Today one branch decides the first two together and a later step derives the
third from their combined answer. Three consequences follow.

A repo has no way to state which review shape it prefers. A maintainer working
alone who wants the fewest possible PRs and a team of reviewers who want the
smallest possible increments are both making defensible calls, and both must
re-argue the case on every plan, because there is nowhere durable to say it once.
Worse, the reviewing team has no honest vocabulary for their reason: the only
sanctioned justification for splitting is that each piece delivers incremental
value, so a reviewability preference has to be laundered as a value claim.

A repo has no way to separate how code lands from how work is tracked. Wanting
several pull requests and wanting GitHub issues are independent wishes, and there
is no way to have one without the other. A team that would rather track a
multi-PR effort inside the plan document cannot; a team that wants issues for a
change that fits one PR cannot either.

And a plan that is not single-PR does not say why. The skill's own prose already
requires that a forcing constraint be named in the document, but no field or
section exists to hold it and nothing checks that it is there. The justification
lives in a working file that is deleted before the branch merges, and in pull
request prose that is not part of the repository. So a reader six months later,
looking at a merged plan that shipped as four pull requests, cannot tell whether
something forced that shape or someone preferred it -- which is the question they
opened the document to answer.

## User Outcome

An author runs the planning workflow and does not have to re-argue how the work
should be delivered. Their repo has already said whether it prefers consolidated
or atomic delivery, and the workflow honors it. If the author wants something
different for this one change, they say so and the reason is recorded.

Separately and independently, their repo has already said how work gets tracked,
so a plan that spans several pull requests either files GitHub issues or does
not, according to what the repo asked for rather than according to how many pull
requests are involved.

When the work merges, the artifact left behind answers the question a later
reader will bring to it. A plan that shipped as several pull requests names which
of the two things happened -- something forced it, or the repo's stated
preference produced it -- and a reviewer can tell those apart without archaeology
through closed pull requests. A plan that shipped as one PR needs no such note,
because one PR is the shape nobody asks about.

## User Journeys

### The sole maintainer who wants the fewest possible PRs

A maintainer working alone on a public repository sets their repository's stated
preference to consolidated delivery once, in the place their repository already
keeps its other durable preferences. From then on, planning a change produces one
pull request whenever one pull request is possible.

When a change does need to be split -- a workflow file that has to reach the
default branch before anything can invoke it -- the plan says so, in the plan. The
maintainer trusts the split because the artifact names the constraint, not
because they remember approving it. Months later, reviewing why a particular
change arrived in three pieces, they read the reason off the document.

### The team that reviews in small increments

A team with several reviewers sets their repository's stated preference to atomic
delivery. Planning a change now produces increments sized for review rather than
one large pull request, and the team does not have to describe their review
culture as incremental user value to get there. Their preference is stated in
their own terms and honored in those terms.

A change that would be awkward to split is still planned as one pull request when
the author says so for this change, and the plan records that this is a departure
from the repository's stated preference.

### The team that wants several PRs but not GitHub issues

A team is planning a change that genuinely has to arrive in stages. They do not
want a milestone and a set of GitHub issues for it: the work items are already
listed in the plan document, and duplicating them into the issue tracker creates
two places to keep in sync. They set the tracking preference accordingly, and the
work lands across several pull requests with the plan document as the only
record. The reverse also works: a team that wants issues filed for a change that
fits comfortably in one pull request gets them.

### The reviewer auditing a merged plan

Someone reviewing the history of a repository opens a plan that shipped as four
pull requests and wants to know whether that was necessary. The document tells
them: either it names the constraint that forced the split, or it says the split
followed the repository's stated preference. Both answers are useful and they are
different answers. Where the document is silent, the checks that ran before merge
would have said so, so silence is not something a reader has to interpret.

## Scope Boundary

### In

- The decision that produces a PLAN's execution mode, and the separation of the
  forced case from the preferred case within it.
- A repository-level preference for delivery shape, expressed through the same
  mechanism the repository already uses for its other durable preferences, with
  the same precedence order.
- A repository-level preference for how a multi-PR plan's work is tracked --
  GitHub issues, issues with a milestone, or neither -- independent of how many
  pull requests are involved.
- A durable record, inside the PLAN, of why a plan is not single-PR, and a check
  that it is present before the work merges.
- The consequences of separating tracking from delivery: the approval gate that
  currently fires because multi-PR creates remote artifacts, and the task
  extraction that currently keys work items on GitHub issue numbers.

### Out

- **Coordinated multi-repository efforts as a mode.** Cross-repository work
  already has its own execution mode with its own merge ordering, grouping
  policy, and gates. This feature does not redesign it, and does not fold it into
  the single-repository decision.
- **Roadmap-level issue filing.** A roadmap already has its own tracking
  preference and its own default. That mechanism is the model this feature
  follows; it is not a thing this feature changes.
- **Issue body format and acceptance criteria templates.** How an issue is
  written is untouched; only whether one is filed at all is in question.
- **The single-issue implementation path.** Working an individual issue is
  unaffected -- what changes is what produced the issue, and whether one exists.
- **Detecting forcing constraints automatically.** Whether a change genuinely
  cannot land in one pull request still rests on the author noticing and saying
  so. Making that detection mechanical is real work and it is separate work.
- **Defining a review-size threshold.** The repository's existing reviewability
  setting points at a value that is defined nowhere. Giving it a concrete
  meaning is named here as a known gap, not resolved as part of this feature.

## Open Questions

- Whether the record of why a plan is not single-PR should also be required of
  cross-repository efforts, which have the same unenforced obligation one
  altitude up. The downstream PRD decides whether that is in this feature's
  contract or a follow-on.
- Whether the two preferences share one setting or take two. They are
  independent wishes, which argues for two; they are set together in practice,
  which argues for one. The PRD records the choice and its reason.
- Whether a plan that fits one pull request may still be asked to record its
  shape. The framing above says no, on the ground that nobody asks about one pull
  request, but a reviewer wanting uniform records may disagree.

## References

- `references/workflow-principles.md` -- the principles the plan workflow derives
  from, including the one this feature amends.
- `references/coordination-strategy.md` -- the coarsest-legal grouping rule and
  its named split triggers, the closest existing model for the delivery
  preference.
- `references/fixes/claude-md-conventions.md` -- the repository preference
  channel both new preferences bind to.
- `docs/designs/current/DESIGN-populate-issueless-default.md` -- the shipped
  tracking preference this feature generalizes.
- `docs/designs/current/DESIGN-roadmap-plan-standardization.md` -- owns the
  current execution-mode rule; this feature amends its decision rather than
  replacing it.
