# /brief Discovery: single-pr-plan-validation

## Problem Candidate

A shirabe coordinator authoring a single-pr plan today gets no structural feedback from `shirabe validate`. The Plan profile's required-sections list and every existing content check (FC04 required-sections, FC05/FC06/FC07/FC08/FC09 over the Implementation Issues table) is shaped around multi-pr plans — but a single-pr plan's authoritative content lives under `## Issue Outlines`, with `## Implementation Issues` and `## Dependency Graph` either absent or empty. The Plan profile does not branch on `execution_mode`, so a single-pr plan can declare `execution_mode: single-pr` in frontmatter, omit `## Issue Outlines` entirely, populate the wrong section with a multi-pr-shaped table, mismatch its `issue_count` against the actual outline count, and still pass every validator check. The discipline that produces well-formed single-pr plans is entirely on author convention, not on validation.

## Outcome Candidate

A coordinator authoring a single-pr plan gets the same level of structural feedback a multi-pr coordinator already gets: the validator catches a missing Issue Outlines section when single-pr requires it, an outline block missing its goal or acceptance-criteria block, an outline depending on a sibling that doesn't exist in the same section, an `issue_count` that doesn't match the number of outline blocks, and content that landed in the wrong section for the declared execution mode. The author finds out at `shirabe validate` time — in their IDE or in CI's Validate Docs job — not at review time, and certainly not at `/work-on` time when the cascade tries to consume a malformed outline.

## Grounding Anchor

conversation only (no path argument passed to /brief). Contextual upstream: shirabe issue #154 (FC10 single-pr plan validation; depends on closed #119) and the parent PLAN row at `docs/plans/PLAN-roadmap-plan-standardization.md` line 88. The FC09 precedent (`doc-vs-github-state-reconciliation`, PR #167 merged) is the sibling shape this brief mirrors — a single-check + light-refactor follow-up shipped as a notice with a one-line promotion path to error.

## Journey Sketch

- **Plan author finalizing a single-pr PLAN.** A coordinator runs `/plan` for a small bounded feature, picks single-pr mode at the value-confirmation guard, drafts Issue Outlines, and triggers `shirabe validate` either locally or via the CI Validate Docs job. FC10 fires on any structural defect (missing required section for single-pr; malformed outline block; unresolved outline-to-outline dependency; issue_count mismatch; wrong-section content). The author finds and fixes the defect before the PR is ready.
- **CI reviewer scanning a single-pr PLAN PR.** A reviewer or the author themselves looks at the CI rollup; any FC10 notice surfaces alongside FC07/FC08/FC09 notices in the same Validate Docs annotations. The notice carries the outline key, the missing field, or the unresolved dependency name verbatim, so the fix is mechanical.
- **Plan author re-running `/work-on` on the resulting single-pr PLAN.** The cascade reads Issue Outlines to drive its outline-by-outline implementation. FC10 having caught structural defects upstream means the cascade does not have to defend against malformed outlines at runtime; the validator caught them at authoring time.

## Open Questions for Drafting

- Sub-check E (mutual exclusion of populated sections) reads as a notice in the issue body but may want phrasing as "recommend the multi-pr execution mode or empty the section" — Phase 2 should pick the exact wording.
- The outline parser's location — `crates/shirabe-validate/src/table.rs` (extending) vs a new `outlines.rs` — is a Phase 2/design wiring detail, but worth flagging in the brief's Scope Boundary as "implementation detail, not in scope".
- FC10's notice → error promotion path is the same one-line move as FC07/FC08/FC09; should appear in Scope Boundary as a future increment, not in this brief's scope.
