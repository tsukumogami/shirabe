# Design Summary: shirabe-child-dispatch-contract

## Input Context (Phase 0)
**Source PRD:** docs/prds/PRD-shirabe-child-dispatch-contract.md
**Problem (implementation framing):** The parent-skill pattern v1 reference (`references/parent-skill-pattern.md`) and the two parent SKILL.md files (`skills/scope/SKILL.md`, `skills/charter/SKILL.md`) describe parent-to-child dispatch across three passages that name no mechanism. DESIGN must pick the harness primitive, the child-side declarator format, and the team-construction layer; then specify the per-file edits that reconcile the three passages and propagate the contract to all seven children.

## Current Status
**Phase:** 0 - Setup (PRD)
**Last Updated:** 2026-06-04

## Decisions to Settle (Phase 1 preview)

- D1 — Dispatch mechanism: TeamCreate-backed team per child / single sub-agent per child / inline Skill tool / shape-dependent
- D2 — Declarator format: prose subsection / structured YAML in frontmatter / structured markdown table / fenced YAML block in SKILL.md body
- D3 — Team-construction layer: one team for the whole chain / one team per child dispatch
- D4 — Per-parent override slot (D5(a) from PRD)
- D5 — Declarator format granularity (D5(b) from PRD)
- D6 — Forward-looking note placement (D5(c) from PRD)

## Migration Surface

Per the PRD, the DESIGN must name concrete edits to these files:
- `references/parent-skill-pattern.md`
- `references/parent-skill-state-schema.md`
- `skills/scope/SKILL.md`, `skills/charter/SKILL.md`
- `skills/brief/SKILL.md`, `skills/prd/SKILL.md`, `skills/design/SKILL.md`, `skills/plan/SKILL.md`
- `skills/vision/SKILL.md`, `skills/strategy/SKILL.md`, `skills/roadmap/SKILL.md`
- `skills/scope/references/phases/phase-2-chain-orchestration.md`
- `skills/charter/references/phases/phase-2-chain-orchestration.md`
