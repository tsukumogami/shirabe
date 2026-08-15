---
status: Proposed
problem: |
  `/plan` records one `execution_mode` flag that answers three independent
  questions at once: whether a plan can land in a single PR, whether it should,
  and whether GitHub issues and a milestone get created. The forced case and the
  preferred case are fused in one branch at `phase-3-decomposition.md` step 3.6,
  and tracking is a hardcoded consequence in `phase-7-creation.md`. A repo cannot
  express that it prefers the fewest possible PRs, cannot express that it prefers
  small atomic increments, and cannot get multiple PRs without GitHub issues or
  issues without multiple PRs. The design must separate the three axes, bind the
  two preference-shaped ones to repo configuration on the existing
  `flag > CLAUDE.md-header > default` stack, and give a non-single-pr plan a
  durable record of why it is not single-pr.
---

# DESIGN: Multi-PR Plan Decoupling

## Status

Proposed

## Context and Problem Statement

Shirabe has separated intent from mechanics across most of its surface. The
plan-level execution mode has not kept up. `execution_mode`
(`single-pr | multi-pr | coordinated`) is chosen in a single 4-way branch at
`skills/plan/references/phases/phase-3-decomposition.md` step 3.6, which fuses a
hard-constraint check -- a fact about the work -- with an "each PR is
independently useful" judgment, which is a value call that varies by
organization. `skills/plan/references/phases/phase-7-creation.md` then treats
GitHub issue and milestone creation as an automatic consequence of the same flag:
multi-pr always files issues under exactly one milestone, single-pr never files
anything, and there is no way to ask for one without the other.

Three findings from the exploration reshape the problem.

**The mechanism already exists twice, scoped one altitude away.**
`## Roadmap Issues: optional|required` is the tracking preference, resolved
`flag > CLAUDE.md-header > default`, with issueless as the shipped default and an
explicit rule that automatic runs never file issues -- but it governs
`/roadmap populate` only, and `grep -rn "issueless\|no_issues" skills/plan/`
returns nothing. `## PR Grouping Policy: coarsest-legal` with
`## Reviewability Ceiling:` is the decomposition preference, complete with a
named split-trigger list and a configurable threshold -- but it governs per-repo
grouping inside a coordinated multi-repo effort, not the plan-level decision.
This work is largely generalization of proven mechanisms, not invention.

**The blast radius is narrower than it appears.** `skills/execute/SKILL.md`
declines multi-pr plans outright and redirects them to `/work-on`, so every
consumer of multi-pr GitHub state lives in one skill. Within it, milestones have
exactly one functional consumer: `/work-on M<N>`'s "select the next unblocked
issue." Nothing reads milestone state for progress, completion, or cascade.

**The trust the author wants is not deliverable by a preference alone.**
`skills/plan/SKILL.md` already requires that a forcing constraint "be named in
the PLAN doc," yet neither `skills/plan/references/plan-format.md` nor
`references/quality/plan-doc-structure.md` defines any field or section to hold
it, and `grep -n "trigger" crates/shirabe-validate/src/*.rs` returns zero hits.
`references/coordination-strategy.md` says "recorded trigger" and has no slot
either. Today `execution_mode: multi-pr` is a bare enum whose justification lives
only in `wip/` -- which the wip-hygiene rule deletes before merge -- and in PR-body
prose. So the recording obligation exists in prose at both altitudes and is
enforced at neither.

What remains open is the mechanism: where the preferences bind, what shape the
recording slot takes, how the validator expresses a conditional requirement it
currently cannot, and what replaces the GitHub-issue scaffolding that an
issueless multi-pr plan would lose.

## Decision Drivers

- **A multi-pr plan should be legible evidence, not an ambiguous flag.** A reader
  must be able to tell from the merged artifact whether the plan was forced,
  preferred, or produced by a repo default -- and today cannot tell any of them.
- **Reuse the existing preference channel.** Seven CLAUDE.md convention headers
  already carry scalar repo preferences, parsed by one generic tested walker
  (`resolve_claude_md_header` in `crates/shirabe-validate/src/visibility.rs`).
  `DESIGN-roadmap-issueless-preference.md` already rejected a `.shirabe.toml`
  layer as disproportionate. No third config channel.
- **Do not weaken the value guard.** Phase 3.5a asks whether a unit would deliver
  observable value if it landed alone. Any mechanism that lets a split bypass or
  carve out that question trades away the principle the whole workflow rests on.
- **Amend, do not re-derive.** `DESIGN-roadmap-plan-standardization.md` Decision 6
  owns the current rule and already de-conflated decomposition strategy from
  execution mode. This design extends it.
- **Distinguish itself from a prior rejection.** `DESIGN-capstone-orchestration.md`
  Decision G rejected an orthogonal `coordinated: true` flag over `multi-pr`
  because it "permits invalid combinations" and gives the validator two branches.
  A reviewer will ask why a tracking axis is safe when that one was not. The
  answer -- `coordinated` *is* a cardinality value while tracking is not -- has to
  be made explicitly, with the cross cells enumerated.
- **Strictness tracks blast radius.** New checks land on
  `PostureClass::DraftTolerable`: a notice while the PR is draft, an error at
  ready. No new enforcement subsystem.
- **Both postures are legitimate.** A sole contributor preferring the fewest
  possible PRs and a many-reviewer org preferring small atomic increments are
  both making defensible calls. Neither should have to fork the skill or launder
  its reasoning through a test that has no vocabulary for it.

## Decisions Already Made

These were settled during exploration and in the decision report at
`wip/explore_multi-pr-plan-decoupling_decision_1_report.md`. Treat them as
constraints; do not reopen them without new evidence.

**On the principle question.** Do not promote reviewability into P1. P1's escape
list is an exhaustive two-branch value test, and a size trigger added to it
collides with the 3.5a value-confirmation guard -- a collision the coordination
altitude never faced, because a per-repo PR is a natural value unit by
construction while a plan-level slice forced by size is not. Instead, make the
default posture repo-invertible so the default *unit* is rescaled and 3.5a asks
its unchanged question of it. P1's prose becomes "the shipped default of a
configurable posture" rather than a universal. The chosen option's abandonment
condition is recorded: if a rescaled default unit routinely fails 3.5a in
practice, the trigger model becomes the more truthful description and this should
be revisited.

**On sequencing.** The recording slot ships first, under whichever preference
lands. Every validator reached this independently, including the two whose own
alternatives it did not advance, because the trust claim is unenforceable without
it under every option.

**On the recording slot's shape.** A frontmatter field, not a section --
`skills/plan/SKILL.md` explicitly separates execution mode from Decomposition
Strategy, so putting the rationale in that section re-conflates what it just
separated, and `Design`'s `FormatSpec` already carries a `rationale` field as
precedent. Free text rather than an enum, because the plan-altitude trigger
taxonomy is not settled and an enum would pre-decide it and lock a
migration-costly schema. The answer to "did the author just type something" is a
structural check that the entry names which branch fired -- that check is not yet
specified and is open design work.

**On cardinality versus tracking.** Two independently triggered decisions on one
shared mechanism, in one document. They rest on different principles -- cardinality
on P1, the tracking coupling on P2's "a self-contained PLAN doc over GitHub
issues when the work is single-pr" -- and posture does not imply tracking: an
`atomic` repo may want small PRs without issue overhead, and a `consolidated` repo
may want issues for its rare multi-pr plans. But they share the header stack, the
frontmatter, the Phase 7 branch, and the advisory pattern, so the mechanism is
authored once.

**On naming.** `Execution Mode` is unavailable. That CLAUDE.md header already
means autonomy (`auto|interactive`) and collides with the unrelated
`execution_mode` frontmatter enum; reusing it would be a shipped bug, not a style
choice.

**On the milestone question.** Reframed from significance to mechanics. Shirabe
milestones carry no progress rollup, no completion trigger, and no cascade role --
their only functional consumer is `/work-on`'s issue selector, and a single
ROADMAP already spawns one roadmap-level milestone plus one per feature-PLAN. The
answerable question is whether a plan needs a GitHub-side grouping handle, not
whether it represents a project milestone.

**On eliminated options.** Issue count, dependency-graph depth, and complexity
labels are not "can" signals -- `/execute`'s single-pr path already drives many
dependent issues through one shared branch and PR, and complexity labels measure
per-issue review rigor. "Cross-repo implies multi-pr" is wrong: cross-repo routes
to `coordinated`. `team.yaml` is koto fan-out topology, not configuration.
`.claude/shirabe-extensions/` is built for file-glob tables, not scalar enums.

## Known Costs to Carry

Named here so the design prices them rather than discovering them:

- `FormatSpec`'s `required_fields` is unconditional. A conditional-required-field
  mechanism has to be built alongside `execution_mode_required_sections`.
- The Draft->Active approval gate is human-gated *because* multi-pr creates remote
  artifacts (`DECISION-multi-pr-posture-detection-2026-06-06.md`). Once tracking is
  independent, that predicate must be re-keyed onto "does this run create GitHub
  artifacts," amending that record.
- `skills/plan/scripts/plan-to-tasks.sh` parses `#N` GitHub references at task
  extraction for multi-pr rows. An issueless multi-pr PLAN has no `#N`, so
  `plan-to-tasks-contract.md` needs a third source-var scheme before such a plan
  is schedulable. This is the largest underpriced item.
- `/work-on M<N>` is the only "what's next" scheduler for multi-pr. An issueless
  multi-pr plan needs a substitute or an accepted loss of that entry point.
- The reviewability ceiling has no definition anywhere: `CLAUDE.md` defers to
  `references/coordination-strategy.md`, which names the trigger and never states
  a value. Define it or name it as deferred; do not assume it solved.
- `execution_mode: coordinated` has no wiring from step 3.6's documented
  procedure -- only prose describing when to reach for it. Resolve or scope out.

## Documentation Drift Found In Passing

Independent of this work, worth fixing: `plan-format.md` still describes
`execution_mode` as a two-value enum omitting `coordinated`, and
`DESIGN-gha-doc-validation.md` carries `status: Current` while describing a Go
implementation that is Rust in the tree.
