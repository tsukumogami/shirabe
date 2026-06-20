# /prd Scope: execute-skill

Upstream: docs/briefs/BRIEF-execute-skill.md (Accepted)

## Problem Statement

shirabe has no implementation-altitude parent skill that owns plan-level execution;
that responsibility is tangled into `/work-on`. The PRD specifies a new `/execute`
skill that owns two plan-execution modes — single-pr orchestration (the legacy
multi-issue orchestrator migrated out of `/work-on`) and coordinated multi-repo
execution (shirabe#196) — and delegates each single issue to a narrowed `/work-on`.
Critically, `/execute` must deliver parity-or-better with the value `/work-on`'s
current multi-issue execution already provides, and existing PLAN docs must keep
flowing end-to-end.

## Initial Scope

### In Scope
- Input contract: which PLAN shapes `/execute` accepts (single-pr, coordinated multi-repo).
- Plan-iteration behavior per mode (issue walk; coordinated merge-order DAG walk).
- Per-issue delegation contract to `/work-on` (single-issue executor).
- Narrowing `/work-on`: removing its plan-orchestration responsibility.
- **Parity-or-better with today's multi-issue execution value**: drift-prevention
  gates, inter-issue learning/carry-forward, per-issue baseline/plan/summary,
  review panels, CI-to-green choreography, finalization cascade. NO regression.
- Progress reporting + metadata-only status inspection.
- Done-signal semantics (coordinated = coordination-PR-merges-last).
- Cross-branch resume from durable coordination state.
- Parent-skill-pattern conformance (state schema, resume ladder, three exit paths,
  child inspection, security surfaces).
- Backward-compatibility: existing tsuku/koto/shirabe PLAN docs keep working.

### Out of Scope
- Single-issue execution mechanics (stay in `/work-on`).
- Multi-pr (single-repo, many PRs) orchestration — stays one-issue-at-a-time via `/work-on`.
- The koto-or-not decision for `/execute`'s plan iteration (downstream design).
- Building the coordination substrate; the review-time redirect mechanism.

## Research Leads
1. **Coordinated-mode contract surface** — what `references/coordination-strategy.md`
   (merged #196) exposes that `/execute` must consume: PR-index, merge-order DAG,
   gate/done-signal, per-repo grouping, status surface for metadata-only inspection.
2. **`/work-on`'s multi-issue execution VALUE inventory** — read `work-on-plan` koto
   template + work-on references; inventory the value-adding capabilities of today's
   multi-issue execution (drift-prevention gates, inter-issue learning, per-issue
   baseline/plan/summary, review panels, CI-to-green, cascade/finalization, gate
   auto-advance) so the PRD can require parity-or-better. Also the single-issue
   delegation surface and the backward-compat surface for existing PLANs.
3. **Parent-skill-pattern requirement shape** — how the pattern v1 references shape a
   parent skill's requirements (state schema, resume ladder, three exit paths, child
   inspection, security), using `/charter`/`/scope` as precedent.
4. **Existing PLAN docs + execution today** — what tsuku/koto/shirabe PLAN docs exist
   and how they execute now, to ground the backward-compatibility requirements.

## Coverage Notes
- Parity-or-better (lead 2) is a hard guardrail from the author: do not ship lower
  value than the existing multi-issue execution. Acceptance criteria must encode it.
- koto-or-not is deferred to design; the PRD states the capability requirements
  (drift gates, inter-issue learning, etc.) without mandating the mechanism.
