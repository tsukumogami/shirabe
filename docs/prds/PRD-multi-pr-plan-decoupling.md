---
status: Draft
problem: |
  A PLAN's execution_mode is read as the answer to three separate questions:
  whether the work can land in one pull request, whether it should, and what
  GitHub tracking gets created. One branch decides the first two together and a
  later step derives the third from their combined answer. A repository can
  state no preference on either of the last two, and a plan that is not
  single-PR records no reason a later reader can check.
goals: |
  Delivery shape and work tracking each follow a stated repository preference,
  resolved on the channel the repository already uses for durable preferences.
  A plan whose shape is not the one its repository's preference would produce
  carries, in the merged artifact, the reason for the shape it has, and a check
  confirms the record is there before the work merges.
upstream: docs/briefs/BRIEF-multi-pr-plan-decoupling.md
motivating_context: |
  Raised by shirabe's maintainer, who wants every plan that can be one PR to be
  one PR and wants multi-PR to be trustworthy evidence that no other option
  existed -- while recognizing that an org with many reviewers may legitimately
  prefer small atomic increments. Neither preference can be expressed today, and
  the trust the first depends on is unenforceable because nothing records why a
  plan was split.
---

# PRD: Multi-PR Plan Decoupling

## Status

Draft

## Problem Statement

Anyone planning work in a shirabe repository is affected, and the shape of the
problem is the same whether they are a sole maintainer or one of a dozen
reviewers.

A PLAN carries a field, `execution_mode`, holding one of `single-pr`,
`multi-pr`, or `coordinated`. Its value is produced by a single branch in
`skills/plan/references/phases/phase-3-decomposition.md` that evaluates two
unrelated things at once — whether a hard constraint forces the work apart, and
whether each resulting piece would deliver value on its own — and a later step in
`skills/plan/references/phases/phase-7-creation.md` then treats the result as
also answering a third question, by filing GitHub issues under a milestone when
the value is `multi-pr` and filing nothing when it is `single-pr`.

Three things follow, and they are separate problems that happen to share a
cause.

**A repository cannot say how it prefers work delivered.** The maintainer who
wants the fewest possible pull requests and the team that wants the smallest
reviewable increments are both right for their situation, and neither can record
that once and have it honored. Worse, only one of them has sanctioned
vocabulary. The rule that governs the choice — principle P1 in
`references/workflow-principles.md`, restated on the planning skill's own
surface — permits splitting for a hard constraint or for genuine incremental
value and for nothing else. A team splitting because their reviewers cannot
absorb a large diff must therefore describe that as incremental value. Yet
`references/coordination-strategy.md`, which governs the same
how-many-pull-requests question for work spanning several repositories, lists
exceeding a configured reviewability ceiling as a legitimate reason to split, and
the repository ships a `## Reviewability Ceiling:` setting to tune it. The two
documents contradict each other on whether reviewability may motivate a split.

**A repository cannot separate how code lands from how the work is tracked.**
Nothing about landing a change across four pull requests requires GitHub issues,
and nothing about wanting issues requires four pull requests. The two are fused
because one field drives both, so a team that would rather keep work items in the
plan document while still shipping in stages has no way to ask for that, and
neither does a team that wants issues for a change that fits in one pull request.
The milestone is fused in turn: a plan that files issues always gets one, even
when the work is several pull requests by mechanical necessity and represents no
landmark anyone would track.

**A plan that is not single-PR does not record why.** The planning skill's own
surfaced rule already requires that a forcing constraint "be named in the PLAN
doc." No field or section exists to hold it, and no check looks for it. The
rationale is written into a file under `wip/`, which shirabe deletes before the
branch merges, and into pull-request prose that is not part of the repository.
The same gap exists for multi-repository work: the grouping rule says a
repository splits "only on a recorded trigger" and nothing records one. So the
artifact a reader opens six months later cannot answer the question they opened
it for.

## Goals

- An author planning work does not re-argue delivery shape. The repository has
  already stated whether it prefers consolidated or atomic delivery, and the
  planning workflow honors that statement without the author restating it.
- A team whose reason for splitting is reviewability can say so in those terms.
  The governing principle stops contradicting the multi-repository grouping rule.
- Work tracking is chosen independently of delivery shape, at all three levels
  the current behavior bundles: no GitHub artifacts, issues alone, or issues
  under a milestone.
- A merged plan answers why it has the shape it has, whenever that shape is
  either not single-PR or not the one its repository's stated preference would
  have produced. A reader can distinguish "something forced this" from "the
  repository prefers this" without reading closed pull requests.
- Nothing that works today stops working. A repository that states no preference
  gets the same plans it gets now — the one addition being that a non-single-PR
  plan now says why, which is the point of the feature rather than an exception
  to it.

## Definitions

- **Delivery shape** — how many pull requests a plan's work arrives in, and
  therefore which `execution_mode` value the plan carries. Not *how the work is
  cut into issues*, which is the separate decomposition-strategy question.
- **Reviewable increment** — a unit of work a reviewer can hold in their head in
  one sitting. The term is deliberately unquantified here: the repository's
  existing reviewability ceiling resolves to no concrete value anywhere in the
  tree, and supplying one is out of scope (see Known Limitations).
- **Consolidated / atomic** — the two delivery preferences. *Consolidated* means
  prefer the fewest pull requests the work permits. *Atomic* means prefer the
  smallest reviewable increments the work permits.
- **Tracking level** — which GitHub artifacts a plan's work items get:
  `none`, `issues`, or `issues-and-milestone`.

## User Stories

- As a sole maintainer, I want my repository to record once that I prefer the
  fewest possible pull requests, so that every plan I write defaults to one PR
  and I only discuss delivery shape when something forces the question.
- As a reviewer on a team that splits work for reviewability, I want to state
  that preference in my repository in my own terms, so that plans arrive as
  reviewable increments without anyone having to describe our review culture as
  incremental user value.
- As a team lead planning a staged change, I want several pull requests without
  filing GitHub issues, so that the plan document stays the single place the work
  items live.
- As a team lead whose plan needs several pull requests for mechanical reasons, I
  want issues without a milestone, so that the tracker shows the work without
  implying a project landmark that does not exist.
- As a team lead planning a change that fits one pull request, I want to file
  GitHub issues for it anyway, so that our tracker reflects work in flight
  regardless of how the code lands.
- As a reviewer auditing a merged plan, I want the document to name the reason it
  has the shape it has whenever that shape is not the repository's default, so
  that I can tell a forced split from a preferred one, and a deliberate
  consolidation from an ordinary one, without archaeology.
- As a maintainer trusting the workflow, I want a plan that omits a required
  reason to be caught before it merges, so that the record's absence is a defect
  rather than something I have to notice.

## Requirements

### Functional — delivery-shape preference

- **R1.** The planning workflow SHALL resolve a delivery-shape preference for the
  repository in the precedence order *invocation flag*, then *CLAUDE.md
  convention header*, then *built-in default* — the order the repository already
  uses for `## Roadmap Issues:` and `## PR Grouping Policy:`.
- **R2.** The delivery-shape preference SHALL accept the value `consolidated`
  and the value `atomic` as defined above, and SHALL default to `consolidated`
  when the repository states nothing.
- **R3.** The delivery-shape preference's convention header SHALL NOT be named
  `Execution Mode`, which already denotes autonomy (`auto`/`interactive`) in
  `references/fixes/claude-md-conventions.md`.
- **R4.** Under `consolidated`, the workflow SHALL produce `execution_mode:
  single-pr` unless a hard constraint forces otherwise or the split delivers
  genuine incremental value — today's behavior. Under `atomic`, it SHALL produce
  a multi-PR shape whenever the decomposition permits one, without requiring the
  split to be justified as incremental value. R4 governs which justification the
  R13 record names; it does not govern whether a unit is well-formed, which is
  R6's separate question.
- **R5.** The governing workflow principle SHALL be amended so that a
  reviewability-motivated delivery preference is expressible without being
  described as incremental value, and so that it and
  `references/coordination-strategy.md` no longer disagree on whether
  reviewability may motivate a split.
- **R6.** The value-confirmation guard that asks whether each unit would deliver
  observable value on its own SHALL continue to run, unchanged, against whatever
  unit the resolved preference makes the default. It is a per-unit quality gate
  that runs regardless of which branch R4 selected and regardless of what the R13
  record names. No delivery preference may create an exemption from it.

### Functional — tracking preference

- **R7.** The planning workflow SHALL resolve a tracking level for the repository
  in the same precedence order as R1. Where a level is stated — by flag or by
  header — that level SHALL apply regardless of the delivery-shape preference and
  regardless of the resolved `execution_mode`. Where no level is stated, R9's
  default applies, and it alone reads `execution_mode`.
- **R8.** The tracking level SHALL accept `none`, `issues`, and
  `issues-and-milestone`, and all six combinations of {`single-pr`, `multi-pr`} ×
  {`none`, `issues`, `issues-and-milestone`} SHALL be reachable.
- **R9.** When the repository states no tracking level, the resolved level SHALL
  be `issues-and-milestone` for `multi-pr` plans and `none` for `single-pr`
  plans — a fixed rule stated as a value, which happens to equal today's
  behavior.
- **R10.** The tracking preference SHALL NOT apply to `coordinated` plans, whose
  tracking is governed by `references/coordination-strategy.md`.
- **R11.** The approval gate that distinguishes automatic from human-approved
  plan activation SHALL be keyed on whether the activation will create GitHub
  issues, rather than on `execution_mode`.
- **R12.** Task extraction SHALL produce a schedulable dependency graph for a
  plan whose resolved tracking level is `none`, without depending on GitHub issue
  numbers as work-item keys.

### Functional — the shape record

- **R13.** A PLAN SHALL carry a frontmatter field recording why it has the
  delivery shape it has, whenever either condition holds: its `execution_mode` is
  not `single-pr`, or its `execution_mode` is not what the resolved delivery
  preference would have produced.
- **R14.** The field of R13 SHALL name which of the governing rule's branches
  produced the shape — a hard constraint, an incremental-value judgment, or the
  repository's stated delivery preference — together with the specific
  justification. R5's amendment SHALL state that the rule has these three
  branches, so the third is part of the rule rather than standing beside it.
- **R15.** A PLAN whose `execution_mode` is `single-pr` and matches what the
  resolved delivery preference would have produced SHALL NOT be required to carry
  the field of R13.
- **R16.** Validation of a PLAN that violates R13 SHALL report a finding, and
  that finding SHALL be non-blocking while the pull request is a draft and
  blocking once it is ready for review.
### Functional — documentation

- **R17.** Both preferences SHALL be documented in
  `references/fixes/claude-md-conventions.md` alongside the existing headers,
  each with its accepted values, its default, and its precedence order.

### Non-functional

- **R18.** Neither preference SHALL introduce a new configuration channel. Both
  bind to the existing CLAUDE.md convention-header mechanism.
- **R19.** A repository that states neither preference SHALL observe today's
  behavior in what the workflow *produces*: the same `execution_mode` for the
  same input, the same GitHub artifacts, and no new prompts. The R13 record is
  the one exception, and it is deliberate — a plan that is not `single-pr` owes
  a reason whether or not the repository has stated a preference, because the
  reason is what makes the shape auditable and that is the feature's point. The
  exception costs no retrofit: PLANs are deleted by the completion cascade, so
  there is no committed corpus of plans to migrate.
- **R20.** The field of R13 SHALL hold free text naming its branch, not a closed
  enumeration of trigger names, because the plan-altitude trigger vocabulary is
  not settled and widening a closed enumeration later costs a schema migration.

## Acceptance Criteria

### Delivery-shape preference

- [ ] A repository declaring `atomic` and planning a change with no forcing
      constraint, whose decomposition permits a split, produces a non-single-pr
      plan. The same change in a repository declaring `consolidated` produces
      `execution_mode: single-pr`. The two runs differ only in the header.
- [ ] Passing the delivery-shape flag on the invocation overrides a conflicting
      CLAUDE.md header, and the header overrides the built-in default. All three
      levels are exercised in one test, each producing a different observable
      `execution_mode` for the same input.
- [ ] A repository declaring nothing produces, for the change above, the same
      `execution_mode` the pre-change workflow produces for it.
- [ ] `references/fixes/claude-md-conventions.md` carries an entry for each of
      the two new headers, and each entry states the header's accepted values,
      its default, and its precedence order. The delivery-shape header's name is
      not `Execution Mode`, and it and the autonomy header appear as separate
      rows.
- [ ] Planning a change under `atomic` runs the value-confirmation guard against
      each resulting unit, and a unit that fails it is reported as a
      mis-decomposition rather than accepted because the preference is `atomic`.

### Tracking preference

- [ ] Each of the six {`single-pr`, `multi-pr`} × {`none`, `issues`,
      `issues-and-milestone`} combinations is produced by stating the
      corresponding preferences, and each is confirmed by inspecting what was
      created: no GitHub artifacts, issues with no milestone assigned, or issues
      with a milestone assigned.
- [ ] A repository stating a delivery preference but no tracking preference
      produces `issues-and-milestone` for a `multi-pr` plan and no GitHub
      artifacts for a `single-pr` plan.
- [ ] Passing the tracking-level flag on the invocation overrides a conflicting
      CLAUDE.md tracking header, and the header overrides the R9 default. All
      three levels are exercised in one test, each producing a different
      observable set of GitHub artifacts for the same input.
- [ ] A `coordinated` plan produces the tracking its coordination contract
      specifies, unchanged, under every value of the tracking preference.
- [ ] Activating a plan whose resolved tracking level is `issues` or
      `issues-and-milestone` requires the human-approval path; activating one
      whose level is `none` takes the automatic path. The observable is which of
      the two paths the run takes, for both a `single-pr` and a `multi-pr` plan
      at each level.
- [ ] Task extraction on a `multi-pr` plan whose tracking level is `none`
      produces a task graph in which every dependency edge resolves to a declared
      work item, with no unresolved keys.

### The shape record

- [ ] `shirabe validate` on a non-`single-pr` PLAN missing the R13 field reports
      a finding; the finding does not fail the run under draft posture and does
      fail it under ready posture.
- [ ] `shirabe validate` on a `multi-pr` PLAN authored in a repository that
      states neither preference, split by a forcing constraint, reports the same
      finding when the R13 field is absent as it does in a repository that states
      one. The record is owed regardless of whether a preference was stated.
- [ ] `shirabe validate` on a `single-pr` PLAN in a `consolidated` repository,
      with no R13 field, reports no finding for its absence.
- [ ] `shirabe validate` on a `single-pr` PLAN in an `atomic` repository, with no
      R13 field, reports a finding — the plan departed from the stated
      preference and owes a reason.
- [ ] All three branches are distinguishable by reading the R13 field. A plan
      split by a forcing constraint names the hard-constraint branch. A plan
      split under `atomic` with no constraint names the stated-preference
      branch. A plan split under `consolidated` with no forcing constraint,
      whose decomposition reveals genuine per-unit value, names the
      incremental-value branch.

### Principle reconciliation

- [ ] `references/workflow-principles.md` and
      `references/coordination-strategy.md` agree, in prose, on whether
      reviewability may motivate a split, and the principle names three branches
      rather than two.

## Out of Scope

- **Redesigning coordinated multi-repository mode.** Its merge ordering,
  grouping policy, gates, and coordination PR are untouched. Only its exemption
  from the tracking preference (R10) is stated here.
- **Roadmap-level issue filing.** The roadmap's own tracking preference is the
  model this work follows, not a thing this work changes.
- **Issue body format and acceptance-criteria templates.** Whether an issue is
  filed is in scope; how it is written is not.
- **The single-issue implementation path.** What produced an issue changes; how
  one is worked does not.
- **Automatic detection of forcing constraints.** Whether a change genuinely
  cannot land in one pull request still rests on the author noticing. Making that
  mechanical — for example by generalizing the multi-repository gate-node concept
  to single-repository plans — is real, separate work.
- **Defining a concrete reviewability threshold.** The existing
  `## Reviewability Ceiling:` header points at a definition that does not exist
  anywhere in the tree. This work does not supply one.
- **Extending the R13 record to multi-repository efforts.** The coordination
  contract has the same unenforced "recorded trigger" obligation, and closing it
  writes to a different artifact — the coordination PR body — with its own
  validating surface. Named as a follow-on.

## Decisions and Trade-offs

Each of the first three entries closes an Open Question the upstream BRIEF
deferred to this document.

**Two preferences, not one.** The BRIEF asked whether delivery shape and work
tracking share one setting or take two. Two. The argument is decided by the cross
cells rather than by taste: a team wanting atomic delivery without issue overhead
and a team wanting issues for a change that fits one PR are both real, and one
setting cannot express either. They also rest on different principles — delivery
shape on the usable-value principle, tracking on the lowest-ceremony principle —
so folding them into one setting would tie two rules together at exactly the
layer this work is separating. The cost is one more header to know about, which
is cheaper than a setting that cannot say what a team means.

**The record is owed on departure, not on multiplicity.** The BRIEF asked
whether a plan that fits one pull request should record its shape too. The first
draft of this document said no, on the ground that one pull request is the shape
nobody asks about. That was right for a `consolidated` repository and wrong for
an `atomic` one, where single-PR *is* the departure — and the BRIEF's own second
journey describes exactly that case. R13 therefore keys on departure from the
resolved preference, with "not `single-pr`" as an additional trigger so a
multi-PR plan always carries a reason regardless of preference. R15 keeps the
common case free of a new required field, which is what the original decision was
protecting.

**The coordinated altitude is a follow-on.** The BRIEF asked whether the R13
record should also bind multi-repository efforts, which carry the same unenforced
obligation. Not here. The write target is different — a coordination PR body
rather than PLAN frontmatter — and so is the validating surface, so folding it in
would double the change's blast radius for a case this work does not otherwise
touch. Out of Scope names it so the gap stays visible.

**Three tracking levels, not two.** An earlier draft collapsed tracking to
issues-or-nothing, on the reading that a milestone is a thin wrapper around
issues. That was wrong for the case that motivates the feature: a plan split by
mechanical necessity may want its work visible in the tracker while representing
no landmark. Since a milestone's only functional consumer is the next-issue
selector, carrying the third level costs almost nothing and preserves a
distinction the requester asked for by name.

**Free text rather than an enumeration.** R20 chooses free text for the R13
record over a closed set of trigger names. An enumeration would make the check
stronger than "the field is present and names a branch," which is the honest
weakness of free text. It was rejected because the plan-altitude trigger
vocabulary is not settled: the multi-repository rule's four triggers do not
transfer — two fire on almost any well-decomposed plan and one refers to a graph
that does not exist at this altitude — so an enumeration written now would encode
a guess and cost a schema migration to correct. R14 recovers most of the strength
by requiring the entry to name its branch.

## Known Limitations

- The reviewability ceiling an `atomic` repository would most naturally tune
  resolves to a value defined nowhere in the tree. Until it has one, the delivery
  preference is a posture rather than a threshold, and a repository cannot say
  *how* small it wants increments.
- The document validator's format specifications declare required fields
  unconditionally. R13 requires a field only under a condition, so either that
  mechanism gains a conditional form or the check is expressed outside the
  required-field list. Which of the two is a DESIGN decision; that neither exists
  today is a cost this work carries.
- The R16 check confirms a reason is present and names a branch, not that the
  reason is true. A plan asserting a constraint that does not exist validates
  clean.
- R13's departure condition requires the validator to know the repository's
  resolved delivery preference, which is a CLAUDE.md read rather than a
  document-local fact. A repository that changes its preference after a plan is
  authored may see the finding appear or disappear without the plan changing.
