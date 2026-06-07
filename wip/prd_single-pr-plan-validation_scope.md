# /prd Scope: single-pr-plan-validation

## Problem Statement

`shirabe validate` enforces no structural shape on single-pr plans: the Plan profile's required-sections list and every content check (FC04 required-sections, FC05/FC06/FC07/FC08/FC09 over the Implementation Issues table) is shaped around multi-pr, so single-pr plans pass vacuously while well-formed single-pr plans get zero structural enforcement. This blocks the milestone-6 goal of treating single-pr and multi-pr as first-class peer lifecycles -- the lifecycle gate landed (#173, #176), the value-confirmation guard landed (#142), but structural validation is still asymmetric.

## Initial Scope

### In Scope

- A new check `checkFC10` in the validator's Plan arm, alongside FC05-FC09.
- Five behavioural sub-checks (mode-aware required sections, outline structural check, outline dep resolution, issue_count consistency, mutual-exclusion of populated sections).
- `FormatSpec` refactor making the Plan profile's required-sections shape `execution_mode`-aware.
- Outline parser helper extracting outline blocks (key, goal, acceptance-criteria, dependencies) totally over arbitrary input.
- Notice severity for the entire check via `is_notice` membership; one-line path to error.
- Table-driven tests covering each sub-check per execution mode plus the panic-resistance case.

### Out of Scope

- Promotion of FC10 to error severity.
- Roadmap arm changes (roadmaps have no single-pr / multi-pr distinction at the format level).
- Corpus migration to fix existing malformed single-pr plans.
- Single-pr PLAN format-spec authoring (the spec already lives at `skills/plan/references/quality/plan-doc-structure.md`).
- `/plan` skill changes.
- CI workflow changes.

## Research Leads

1. **FormatSpec extension shape.** How to encode `execution_mode`-aware required-sections in the current `FormatSpec` without breaking the Roadmap profile or non-Plan profiles. Inspect `crates/shirabe-validate/src/formats.rs` to see how the Plan profile is currently constructed, what fields exist, and where `check_required_sections` consults them. The PRD must name the specific contract surface FC10 extends.

2. **Outline parser shape.** Whether the new outline parser extends `table.rs` or lives in a sibling `outlines.rs`. Inspect existing `parseIssuesTable` to see if the abstractions reuse cleanly. The PRD does not pick the file location, but it must specify the function signature, the OutlineBlock fields, and the total-over-arbitrary-input contract precisely.

3. **Sibling-check pattern (FC07-FC09).** How FC07/FC08/FC09 are wired into `is_notice`, how they emit reconciliation messages, how their tests are organized. The PRD's acceptance criteria must specify FC10 follows the same pattern so the validator's check family stays consistent and the one-line promotion path stays uniform.

## Coverage Notes

- **Who is affected:** shirabe coordinators authoring single-pr plans; reviewers scanning their PRs in CI; the `/work-on` cascade consuming Issue Outlines downstream.
- **Current situation:** validator treats single-pr / multi-pr identically; single-pr plans pass vacuously.
- **What's missing:** no `execution_mode`-aware dispatch, no Issue Outlines structural enforcement, no outline-to-outline dep check, no `issue_count` parity check for single-pr, no mutual-exclusion check.
- **Why now:** FC09 (#167) and the lifecycle gates (#173, #176) merged in the last 48h; single-pr plans are now first-class lifecycle citizens; FC10 closes the last open structural gap in milestone #6.
- **Scope boundaries:** matches BRIEF in/out lists verbatim.
- **Success criteria:** FC10 notices fire on each of the 7 defect cases the BRIEF Journey 1 enumerates; well-formed single-pr plans get no FC10 notices; existing multi-pr plans see no behavioural change.

The upstream BRIEF is already Accepted at `docs/briefs/BRIEF-single-pr-plan-validation.md`; the scope's authoritative framing flows from there. This scope file is the bridge between the BRIEF's user-facing framing and the PRD's requirements articulation.
