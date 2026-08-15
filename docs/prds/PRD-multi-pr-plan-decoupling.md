---
status: Draft
problem: |
  A PLAN's execution_mode is read as the answer to three separate questions:
  whether the work can land in one pull request, whether it should, and whether
  GitHub issues and a milestone get created. One branch decides the first two
  together and a later step derives the third from their combined answer. A
  repository can state no preference on either of the last two, and a plan that
  is not single-PR records no reason a later reader can check.
goals: |
  Delivery shape and work tracking each follow a stated repository preference,
  resolved on the channel the repository already uses for durable preferences.
  Any plan that is not single-PR carries, in the merged artifact, which of the
  two things produced that shape -- a named forcing constraint or the
  repository's stated preference -- and a check confirms the record is there
  before the work merges.
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
`multi-pr`, or `coordinated`. Its value is produced by a single branch that
evaluates two unrelated things at once — whether a hard constraint forces the
work apart, and whether each resulting piece would deliver value on its own —
and a later step then treats the result as also answering a third question, by
filing GitHub issues and a milestone when the value is `multi-pr` and filing
nothing when it is `single-pr`.

Three things follow, and they are separate problems that happen to share a
cause.

A repository cannot say how it prefers work delivered. The maintainer who wants
the fewest possible pull requests and the team that wants the smallest reviewable
increments are both right for their situation, and neither can record that once
and have it honored. Worse, only one of them has sanctioned vocabulary: the
governing principle permits splitting for a hard constraint or for genuine
incremental value and for nothing else, so a team splitting because their
reviewers cannot absorb a large diff must describe that as incremental value.
The principle is silent on reviewability by construction, while the
cross-repository contract one altitude up lists exceeding a configured
reviewability ceiling as a legitimate reason to split. The repository already
contradicts itself on this point, in prose, in two files.

A repository cannot separate how code lands from how the work is tracked.
Nothing about landing a change across four pull requests requires GitHub issues,
and nothing about wanting issues requires four pull requests. The two are fused
because one flag drives both, so a team that would rather keep work items in the
plan document while still shipping in stages has no way to ask for that, and
neither does a team that wants issues for a change that fits in one PR.

And a plan that is not single-PR does not record why. The planning skill's own
surfaced rule already requires that a forcing constraint "be named in the PLAN
doc." No field or section exists to hold it, and no check looks for it. The
rationale is written into a working file that the wip-hygiene rule deletes before
the branch merges, and into pull-request prose that is not part of the
repository. The same gap exists one altitude up: the cross-repository grouping
rule says a repository splits "only on a recorded trigger" and nothing records
one. So the artifact a reader opens six months later cannot answer the question
they opened it for.

## Goals

- An author planning work does not re-argue delivery shape. The repository has
  already stated whether it prefers consolidated or atomic delivery, and the
  planning workflow honors that statement without the author restating it.
- A team whose reason for splitting is reviewability can say so in those terms.
  The governing principle stops contradicting the cross-repository contract.
- Work tracking is chosen independently of delivery shape. All four combinations
  of "one PR or several" and "issues or no issues" are reachable, and each is
  reached by stating a preference rather than by accepting a side effect.
- A merged plan answers why it has the shape it has. A reader can distinguish
  "something forced this" from "the repository prefers this" without reading
  closed pull requests, and the distinction is checkable rather than a matter of
  whether the author remembered to write it down.
- Nothing that works today stops working. A repository that states no preference
  gets exactly the behavior it gets now.

## User Stories

- As a sole maintainer, I want my repository to record once that I prefer the
  fewest possible pull requests, so that every plan I write defaults to one PR
  and I only discuss delivery shape when something forces the question.
- As a reviewer on a team that splits work for reviewability, I want to state
  that preference in my repository in my own terms, so that plans arrive as
  reviewable increments without anyone having to describe our review culture as
  incremental user value.
- As a team lead planning a staged change, I want to choose several pull requests
  without filing GitHub issues, so that the plan document stays the single place
  the work items live.
- As a team lead planning a change that fits one pull request, I want to file
  GitHub issues for it anyway, so that our issue tracker reflects work in flight
  regardless of how the code lands.
- As a reviewer auditing a merged plan, I want the document to name the reason it
  was not single-PR, so that I can tell a forced split from a preferred one
  without archaeology.
- As a maintainer trusting the workflow, I want a plan that omits its reason to
  be caught before it merges, so that the record's absence is a defect rather
  than something I have to notice.

## Requirements

### Functional

- **R1.** The planning workflow SHALL resolve a delivery-shape preference for
  the repository on the `flag > CLAUDE.md-header > default` precedence order the
  repository already uses for its other durable preferences.
- **R2.** The delivery-shape preference SHALL support at minimum a value meaning
  "prefer the fewest pull requests" and a value meaning "prefer the smallest
  reviewable increments," and SHALL default to the former when the repository
  states nothing.
- **R3.** The delivery-shape preference SHALL NOT reuse the name `Execution
  Mode`, which already denotes autonomy (`auto`/`interactive`) and collides with
  the `execution_mode` PLAN frontmatter field.
- **R4.** The planning workflow SHALL resolve a work-tracking preference for the
  repository on the same precedence order, independently of the delivery-shape
  preference and independently of the resolved `execution_mode`.
- **R5.** The work-tracking preference SHALL distinguish, at minimum, filing
  GitHub issues from filing none, and SHALL make all four combinations of
  {one PR, several PRs} × {issues, no issues} reachable.
- **R6.** The work-tracking preference SHALL default to the behavior the
  repository exhibits today, so an unstated preference changes nothing.
- **R7.** The work-tracking preference SHALL NOT apply to `coordinated` plans,
  whose tracking is governed by the cross-repository coordination contract.
- **R8.** A PLAN whose `execution_mode` is not `single-pr` SHALL carry a
  frontmatter field recording why, naming which of the governing rule's branches
  produced the shape — a forcing constraint, an incremental-value judgment, or
  the repository's stated delivery preference — together with the specific
  justification.
- **R9.** A PLAN whose `execution_mode` is `single-pr` SHALL NOT be required to
  carry the field of R8.
- **R10.** The document validator SHALL report a PLAN that violates R8 as a
  draft-tolerable finding: a notice under draft posture and an error under ready
  posture.
- **R11.** The governing workflow principle SHALL be amended so that a
  reviewability-motivated delivery preference is expressible without being
  described as incremental value, and SHALL no longer contradict the
  cross-repository grouping rule on whether reviewability can motivate a split.
- **R12.** The value-confirmation guard that asks whether each unit would deliver
  observable value on its own SHALL continue to run unchanged against whatever
  unit the resolved preference makes the default. No delivery preference may
  create an exemption from it.
- **R13.** The approval gate that currently distinguishes automatic from
  human-approved plan activation SHALL be re-keyed onto whether the transition
  creates remote GitHub artifacts, rather than onto `execution_mode`.
- **R14.** Task extraction SHALL produce a schedulable dependency graph for a
  multi-PR plan that filed no GitHub issues, without depending on GitHub issue
  numbers as work-item keys.
- **R15.** Both preferences SHALL be documented in the repository's canonical
  convention-header reference alongside the existing headers.

### Non-functional

- **R16.** Neither preference SHALL introduce a new configuration channel. Both
  bind to the existing CLAUDE.md convention-header mechanism.
- **R17.** A repository that states neither preference SHALL observe behavior
  identical to today's, with no new prompts and no new required fields on plans
  that are single-PR.
- **R18.** The record required by R8 SHALL be free text naming its branch, not a
  closed enumeration of trigger names, because the plan-altitude trigger
  vocabulary is not settled and a schema change to widen it later is costly.
- **R19.** The R10 check SHALL be implemented on the validator's existing
  posture-class mechanism rather than as a new enforcement subsystem.

## Acceptance Criteria

- [ ] A repository declaring the delivery-shape preference as "fewest pull
      requests" and planning a change with no forcing constraint and no
      independent value in splitting produces `execution_mode: single-pr`.
- [ ] The same repository, planning a change whose steps cannot all land at once,
      produces a non-single-pr plan whose R8 field names the forcing constraint.
- [ ] A repository declaring the preference as "smallest reviewable increments"
      and planning the same no-constraint change produces a non-single-pr plan
      whose R8 field names the repository's stated preference as the reason, not
      a fabricated incremental-value claim.
- [ ] A repository declaring no delivery preference produces, for both changes
      above, exactly the `execution_mode` the current workflow produces.
- [ ] A repository declaring the tracking preference as "no issues" and producing
      a multi-PR plan results in no GitHub issues and no milestone, and the
      plan's work items remain readable from the document.
- [ ] A repository declaring the tracking preference as "issues" and producing a
      single-PR plan results in GitHub issues being filed.
- [ ] A `coordinated` plan is unaffected by the tracking preference in all of the
      above.
- [ ] `shirabe validate` on a non-single-pr PLAN missing the R8 field reports a
      finding; the finding is a notice under `--mode=draft` and an error under
      `--mode=ready`.
- [ ] `shirabe validate` on a `single-pr` PLAN with no R8 field reports no
      finding for its absence.
- [ ] A multi-PR plan that filed no GitHub issues yields a task graph whose
      dependency edges resolve, with no unresolved work-item keys.
- [ ] Activating a plan that will create GitHub issues requires human approval;
      activating one that will not does so automatically, regardless of how many
      pull requests either involves.
- [ ] The workflow-principles document and the cross-repository coordination
      contract agree, in prose, on whether reviewability can motivate a split.
- [ ] Both new headers appear in the canonical convention-header reference with
      their accepted values, their default, and their precedence order.

## Out of Scope

- **Redesigning coordinated multi-repository mode.** Its merge ordering,
  grouping policy, gates, and coordination PR are untouched. Only its exemption
  from the tracking preference (R7) is stated here.
- **Roadmap-level issue filing.** The roadmap's own tracking preference is the
  model this work follows, not a thing this work changes.
- **Issue body format and acceptance-criteria templates.** Whether an issue is
  filed is in scope; how it is written is not.
- **The single-issue implementation path.** What produced an issue changes; how
  one is worked does not.
- **Automatic detection of forcing constraints.** Whether a change genuinely
  cannot land in one PR still rests on the author noticing. Making that
  mechanical — for example by generalizing the cross-repository gate-node concept
  to single-repository plans — is real, separate work.
- **Defining a concrete reviewability threshold.** The existing reviewability
  ceiling header points at a definition that does not exist anywhere in the tree.
  This work does not supply one; it is recorded as a known limitation.
- **Extending the R8 record to coordinated efforts.** The cross-repository
  contract has the same unenforced "recorded trigger" obligation, and closing it
  writes to a different artifact — the coordination PR body — with its own
  validator surface. Named as a follow-on.

## Decisions and Trade-offs

Each entry below closes an Open Question the upstream BRIEF deferred to this
document.

**Two preferences, not one.** The BRIEF asked whether delivery shape and work
tracking share one setting or take two. Two. They are independent wishes, and
the argument is decided by the cross cells rather than by taste: a team wanting
atomic delivery without issue overhead and a team wanting issues for a change
that fits one PR are both real, and one setting cannot express either. They also
rest on different principles — delivery shape on the usable-value principle,
tracking on the lowest-ceremony principle — so folding them into one setting
would tie two rules together at exactly the layer this work is separating. The
cost is one more header for a reader to know about; that is cheaper than a
setting that cannot say what a team means.

**A single-PR plan records nothing.** The BRIEF asked whether a plan that fits
one pull request should record its shape too, for uniformity. It should not.
One pull request is the shape nobody asks about, so the record would have no
reader, and requiring it would put a new mandatory field on the common case in
service of symmetry. The alternative — uniform records everywhere — was rejected
because R17's promise that an unstated preference changes nothing is worth more
than a consistent schema. R9 states the exemption explicitly so a later reviewer
sees it was decided rather than overlooked.

**The coordinated altitude is a follow-on, not part of this contract.** The
BRIEF asked whether the R8 record should also bind cross-repository efforts,
which carry the same unenforced obligation. Not here. The write target is
different — a coordination PR body rather than PLAN frontmatter — and so is the
validating surface, so folding it in would double the change's blast radius for
a case this work does not otherwise touch. It is named in Out of Scope so the
gap stays visible rather than being closed by silence.

**Free text rather than an enumeration.** R18 chooses free text for the R8
record over a closed set of trigger names. An enumeration would make the check
stronger than "is the field non-empty," which is the honest weakness of free
text. It was rejected because the plan-altitude trigger vocabulary is not
settled: the cross-repository rule's four triggers do not transfer — two of them
fire on almost any well-decomposed plan and one refers to a graph that does not
exist at this altitude — so an enumeration written now would encode a guess and
cost a schema migration to correct. R8 recovers most of the strength by
requiring the entry to name which branch produced the shape, which is checkable
without fixing the vocabulary.

## Known Limitations

- The reviewability ceiling that an atomic-preferring repository would most
  naturally tune resolves to a value defined nowhere in the tree. Until it has a
  definition, the delivery preference is expressed as a posture rather than a
  threshold, and a repository cannot say *how* small it wants increments.
- The R8 record makes a split's reason legible; it does not make the underlying
  judgment more reliable. Whether a forcing constraint exists still rests on the
  author noticing it, so the record's honesty is only as good as its author's.
- The R10 check confirms a reason is present, not that it is true. A plan
  asserting a constraint that does not exist validates clean.
