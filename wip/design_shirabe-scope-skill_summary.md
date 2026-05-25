# Design Summary: shirabe-scope-skill

## Input Context (Phase 0)

**Source PRD:** docs/prds/PRD-shirabe-scope-skill.md (Accepted at commit 7129bdf; transitioned to In Progress at the start of this design run).

**Source BRIEF:** docs/briefs/BRIEF-shirabe-scope-skill.md (Accepted).

**Parent design (shared pattern):** docs/designs/current/DESIGN-shirabe-progression-authoring.md (Current; ships the parent-skill pattern v1 / Layer 1 invariants I-1 through I-7 / Layer 2 reference implementation under `wip-yaml-md` and `single-team-per-leader-no-nested`).

**Topic slug:** `shirabe-scope-skill`

**Visibility:** Public (shirabe).

**Scope:** Tactical.

**Problem (implementation framing):** Bind the parent-skill pattern v1 to the tactical chain (`/brief → /prd → /design → /plan`), absorbing three asymmetries the strategic chain does not have — two settled-upstream boundaries (Accepted PRD or Accepted DESIGN), Phase-N Reject finalization missing on `/prd` and `/design` today, and a terminal child with two output modes (`/plan single-pr` vs `/plan multi-pr`). Ship the `/scope` SKILL.md, the four `/scope` → child delegation contracts, the three exit paths with two boundary positions and two sub-shapes on the re-evaluation exit, the resume ladder across four child boundaries + three PLAN statuses + DESIGN's directory-move lifecycle, the pattern-doc edits (fourth gate type, `boundary:` and `plan_execution_mode:` state-schema fields, new top-level worktree-discipline reference), and the Phase-N Reject contract extensions to `/prd` and `/design`.

## PRD Requirement Tag Distribution

- **[pattern-level] (11 requirements; shared with `/charter`):** R1, R3, R9, R10, R11, R12, R13, R14, R17a, R18, R19.
- **[/scope-specific] (15 requirements):** R2, R4, R5, R6, R7, R7.5, R8, R15, R16, R16.5, R17b, R20, R21, R22, R23.

Solution Architecture components will mirror this distinction. Pattern-doc edits cover all eleven pattern-level requirements; `/scope` body slots cover all fifteen `/scope`-specific requirements.

## Design-Altitude Questions From PRD (Resolved Here)

The PRD's "Questions Deferred to Design" section names five design-altitude open questions:

1. Phase-N Reject contract implementation on `/prd` (Phase 4 placement) and `/design` (Phase 6 placement) — gate insertion phase, augment-vs-replace existing prompt logic, ordering against `/design`'s directory-move into `current/`.
2. R6 shape-predicate evaluation mechanism — checklist walk vs structured prompt vs sub-decision delegation.
3. PLAN-status-aware signaling from `/scope` to `/plan` (suppression of `/plan`'s own resume prompt on Draft re-entry).
4. The worktree-discipline reference's exact prose — rebase mechanics, "proceed anyway" recording semantics, chain-proposal integration.
5. Cross-boundary state-snapshot semantics — does `child_snapshots` advance on re-evaluation Decision Record write or stay frozen on the referenced artifact?

Phase 1 will decompose these (plus implicit decisions surfaced from the PRD body) into independent decision questions.

## Current Status

**Phase:** 0 — Setup (PRD)
**Last Updated:** 2026-05-25
