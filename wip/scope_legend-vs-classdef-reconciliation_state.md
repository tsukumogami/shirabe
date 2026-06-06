---
topic: legend-vs-classdef-reconciliation
chain_started: 2026-06-06T16:48:16Z
last_updated: 2026-06-06T16:48:16Z
phase_pointer: phase-1
exit: UNSET
exit_artifacts: []
planned_chain: []
visibility: Public
execution_mode: auto
plan_execution_mode: single-pr
---

# /scope state — legend-vs-classdef-reconciliation

## Phase 0 — Setup (complete)

- Slug `legend-vs-classdef-reconciliation` matches `^[a-z0-9-]+$`.
- Visibility detected from CLAUDE.md: Public.
- No stale `parent_orchestration:` block (fresh chain).
- Pre-committed: `plan_execution_mode: single-pr` (ephemeral PLAN).
- Pre-committed: post-/scope action is `/work-on` against the PLAN doc.

## Phase 1 — Discovery (in progress)

Topic: FC08 — Legend-vs-classDef reconciliation as a notice.
Upstream context:
- Parent PLAN row at `docs/plans/PLAN-roadmap-plan-standardization.md` line 84-85 (#152).
- FC07 precedent: `docs/{briefs,prds,designs/current}/*-table-diagram-reconciliation.md`.
- FC09 precedent: `docs/{briefs,prds,designs/current}/*-doc-vs-github-state-reconciliation.md`.

R6 shape predicates for /design decision-roster:
- architectural-alternatives count: ~1-2 (Legend extractor pattern, normalization rule).
- new-component references: 0 — reuses `Diagram.class_defs` from FC07.
- Complex classification: NO — Simple shape; tight infra reuse.

Verdict: /design with small decision-roster (1-2 decisions). All four children in chain.

Chain proposal (auto-accepted; no user confirmation prompt under --auto):
- /brief — Mandatory.
- /prd — Mandatory.
- /design — Mandatory (with small decision-roster, mirroring FC07/FC09 sub-design shape).
- /plan — Mandatory (single-pr; ephemeral PLAN to be deleted in work-completing commit).
