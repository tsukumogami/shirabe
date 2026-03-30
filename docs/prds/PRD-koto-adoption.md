---
status: Accepted
problem: |
  Seven shirabe skills encode workflow mechanics (resume, phase ordering, gates,
  decisions) as prose instructions. This duplicates 60-80% of each skill's content,
  causes structural failures (phase skipping, lost decisions), and provides no
  visibility into workflow state. Koto already solves this for /work-on but the
  other skills haven't adopted it.
goals: |
  Convert all shirabe skills to use koto for state persistence, phase gatekeeping,
  and deterministic verification. File koto feature requests for missing primitives.
  Phase the work so skills convert as koto features become available.
---

# PRD: Koto Adoption for Shirabe Skills

## Status

Accepted

## Problem Statement

Shirabe has 8 skills. Only /work-on uses koto for workflow orchestration. The
other 7 (explore, design, prd, plan, decision, release, review-plan) manage
their own state through wip/ files, enforce phase ordering through prose
instructions, and handle verification through agent-interpreted checks.

This causes three classes of problems:

**Structural failures.** Phase skipping (agent jumps to implementation without
completing analysis), design contradictions (cross-validation skipped on
resume), and lost decisions (recorded in wip/ files that get cleaned before
anyone reads them). Three documented incidents: shirabe #25, and two
design-phase failures during the reusable release system work.

**Duplication.** 60-80% of each SKILL.md's line count is workflow mechanics:
resume logic ("if wip/X exists, skip to phase N"), phase ordering ("read
phase-3.md before proceeding"), gate checks ("verify CI is green"). Every
skill reimplements these patterns in prose.

**No visibility.** Workflow state lives in wip/ file existence. There's no way
to see which phase a workflow is in, what decisions were made, or why a phase
was skipped — short of reading the files and inferring state.

The /work-on skill demonstrates the solution: koto templates define phases,
gates, and evidence schemas declaratively. The engine enforces ordering,
persists state, captures decisions, and supports resume. But the other 7
skills haven't adopted it.

## Goals

- **G1**: Every shirabe skill uses koto for phase sequencing, state persistence,
  and resume. Prose instructions cover domain logic only, not workflow mechanics.
- **G2**: Deterministic checks (CI status, file existence, frontmatter validation)
  run as koto gates, not as agent-interpreted prose.
- **G3**: Decisions made during workflows are captured in koto's decision log,
  visible via `koto decisions list`.
- **G4**: Koto feature gaps are filed as issues in the koto repo with concrete
  use cases from shirabe.

## User Stories

### US1: Reliable resume

As a user resuming a mid-flight /design workflow, I want koto to detect
exactly where I left off and resume from that phase, so that I don't re-run
completed work or skip required phases.

### US2: Decision visibility

As a user reviewing a completed /explore workflow, I want to see all
decisions made during convergence rounds via `koto decisions list`, so that
I understand why the exploration crystallized the way it did.

### US3: Deterministic CI gating

As a user running /release, I want the workflow to wait for CI to pass as a
koto gate rather than relying on the agent to poll correctly, so that the
release can't proceed with failing CI.

### US4: Phase enforcement

As a user running /design, I want koto to prevent Phase 3 (cross-validation)
from running before Phase 2 (decision execution) completes, so that
decisions aren't cross-validated against incomplete data.

### US5: Reduced skill complexity

As a skill author, I want skills to focus on what to achieve and koto
workflows to handle how to get there, so that I can reason about domain
logic and workflow mechanics independently.

## Requirements

### Functional Requirements

**R1: Koto workflows for all skills.** Each skill gets a koto workflow
template that defines how phases sequence, what gates enforce between
them, and what evidence is required to advance. Skills define what to
achieve in each phase; workflows define how to get there. Templates
live alongside the skill at `skills/<name>/koto-templates/<name>.md`.

**R2: Phase gate enforcement.** Phase transitions are enforced by koto
gates (context-exists, command, evidence-based). An agent cannot advance
past a gate without satisfying it or explicitly overriding (which koto logs).

**R3: Decision capture in koto.** Decisions made during workflows are
recorded via `koto decisions record` rather than written to wip/ files.
This provides a queryable audit trail that survives wip/ cleanup.

**R4: Deterministic verification gates.** Checks that are currently prose
("verify CI is green", "check frontmatter status is Accepted") become koto
command gates or content-match gates that run deterministically.

**R5: Resume from any phase.** Interrupted workflows resume at the exact
phase where they stopped, with all prior evidence and decisions preserved.
No "check which files exist to figure out where we are" logic in the skill.

**R6: Koto feature requests filed.** Missing koto primitives are filed as
issues in the koto repo with use cases from shirabe. Shirabe conversions
that depend on these features are explicitly blocked until the features ship.

**R7: Phased adoption.** Skills convert in phases based on koto feature
availability and conversion complexity. Each phase delivers working
conversions, not partial work.

### Non-Functional Requirements

**R8: Separation of concerns.** After conversion, SKILL.md focuses on what
to achieve (domain goals, output expectations, quality criteria). The koto
workflow template handles how to get there (phase sequencing, gates,
evidence schemas, transitions). Workflow mechanics (resume, ordering,
gate checks) move out of SKILL.md entirely.

**R9: No behavioral regression.** Converted skills produce the same outputs
(artifacts, issues, documents) as before. The user experience doesn't change;
only the enforcement mechanism does.

**R10: Graceful degradation.** If koto is not installed, skills fall back to
their current prose-based behavior. Koto adoption is additive, not a hard
dependency for skill execution.

## Acceptance Criteria

- [ ] Every shirabe skill has a koto template
- [ ] Phase ordering is enforced by koto gates, not prose
- [ ] Decisions are captured via koto and visible via `koto decisions list`
- [ ] CI and status checks run as koto command gates
- [ ] Interrupted workflows resume correctly from the interrupted phase
- [ ] Koto feature request issues are filed in tsukumogami/koto
- [ ] Skills work (with degraded enforcement) when koto is not installed
- [ ] SKILL.md files focus on what to achieve; workflow mechanics live in koto templates

## Out of Scope

- Designing or implementing koto features (tracked via koto issues)
- Converting /work-on (already uses koto)
- Changing koto's core architecture or state model
- Automated testing of koto templates (deferred to koto's own test infra)

## Open Questions

- ~~**Q1**: Template vs SKILL.md authority?~~ **Resolved**: The koto template
  is the authoritative phase definition. SKILL.md references it for structure
  and adds domain-specific instructions per phase only.
- **Q2**: How should fan-out agents be represented in the koto template? The
  current approach (agents outside koto, glob gate for collection) works but
  means koto doesn't track individual agent status.

## Known Limitations

- **Koto prerequisites.** Several conversions are blocked by koto features
  that don't exist yet (#65 variables, #66 mid-state decisions, #87 evidence
  promotion, plus 4 new feature requests). The phasing accounts for this but
  means full adoption can't happen immediately.
- **Fan-out outside koto.** Parallel agent execution stays in the skill layer
  (Claude Code Task agents). Koto tracks the collection point (glob gate) but
  not individual agents. This is pragmatic but means koto's state view is
  incomplete during fan-out phases.
- **Release skill is last.** The /release skill (15+ external commands, zero
  wip/ files) is the poorest koto fit and converts last. It may need
  architectural changes to work well with koto.

## Decisions and Trade-offs

**D1: Phased adoption over big-bang.** Skills convert in 3 phases based on
koto feature availability. Phase 1 uses current koto. Phase 2 needs #65/#87.
Phase 3 needs new features. Each phase delivers working conversions.

**D2: Fan-out stays outside koto.** 6 of 7 skills fan out parallel agents.
Rather than waiting for koto to support native parallelism (#41), skills
continue using Claude Code Task agents with a glob-aware koto gate for
collection. This is pragmatic — koto tracks the checkpoint, not the
individual agents.

**D3: Graceful degradation over hard dependency.** Skills check for koto
availability and fall back to prose-based behavior if it's missing. This
avoids making koto installation a prerequisite for using shirabe.

**D4: Release converts last.** The /release skill's heavy reliance on
external commands (gh, git) and lack of wip/ state makes it the poorest
koto fit. It converts in Phase 3 after polling gates and content-match gates
exist.

## Phased Adoption Plan

### Phase 1: Current Koto (no new features needed)

| Skill | Mode | Complexity | Value |
|-------|------|-----------|-------|
| review-plan | fast-path only | Low | Resume, verdict enforcement |
| decision | without persistent validators | Medium | Tier routing, resume across 7 phases |

### Phase 2: After koto #65 (variables) + #87 (evidence promotion)

| Skill | Mode | Complexity | Value |
|-------|------|-----------|-------|
| prd | full (fan-out outside koto) | Medium | Resume across 5 phases, jury enforcement |
| plan | full | Medium | 7-phase enforcement, mode selection gate |
| explore | basic (fixed round count) | Medium | Resume, crystallize enforcement |
| design | linear flow (no parallel decisions) | Medium | 6-phase enforcement, security gate mandatory |

### Phase 3: After new koto features (polling, loop counter, glob gate, content-match)

| Skill | Mode | Complexity | Value |
|-------|------|-----------|-------|
| explore | full loops | Low (upgrade) | Bounded discover-converge iteration |
| design | parallel decisions | Low (upgrade) | Concurrent decision agents tracked |
| release | full | High | CI polling gate, external command verification |
| review-plan | adversarial mode | High | Parallel review categories |
| decision | full validators | High | Cross-state agent persistence |

## Koto Feature Requests (to file)

| Feature | Koto Issue | Shirabe Skills | Phase |
|---------|-----------|----------------|-------|
| Template variables (`--var`) | #65 (open) | all | Phase 2 blocker |
| Mid-state decision capture | #66 (open) | explore, design, prd | Phase 2 |
| Evidence-to-variable promotion | #87 (open) | work-on, release | Phase 2 blocker |
| Polling gate | tsukumogami/koto#104 | release, work-on | Phase 3 blocker |
| Bounded iteration / loop counter | tsukumogami/koto#105 | explore, prd | Phase 3 blocker |
| Glob-aware context-exists gate | tsukumogami/koto#106 | explore, design, plan, prd | Phase 3 blocker |
| Content-match gate | tsukumogami/koto#107 | design, plan | Phase 3 |
| Override-with-rationale | tsukumogami/koto#108 | all (any gate bypass) | Phase 2 |
