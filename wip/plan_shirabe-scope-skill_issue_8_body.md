---
complexity: testable
complexity_rationale: Four surgical edits to a single pattern-reference markdown file extending Layer-2 vocabulary; contract surface is grep-checkable (literal field names and gating clauses) but no code execution, so verification is by static substring + sample-state-file shape check rather than runtime tests.
---

## Goal

Extend `references/parent-skill-state-schema.md` with two new conditional-field bullets (`boundary:` gated by `exit: re-evaluation`; `plan_execution_mode:` gated by `/plan` in `chain_ran`), a Chain-tracking paragraph clarifying that `plan_execution_mode:` is recorded separately from `chain_ran`/`chain_skipped`, and R9 hard-finalization-check additions covering multi-discriminator sub-shapes and chain-membership-gated I-5 fields per Component 2 of the design.

## Context

Design: `docs/designs/DESIGN-shirabe-scope-skill.md` — Solution Architecture / Component 2 (2.1 + 2.2 + 2.3 + 2.4)

`/scope` extends the pattern-skill state schema at Layer 2 to absorb two tactical-chain asymmetries the v1 pattern had no vocabulary for. The PRD-or-DESIGN re-evaluation boundary requires a `boundary:` discriminator on top of the existing `exit:` enum so `/scope`'s two settled-upstream boundaries (PRD-Accepted and DESIGN-Accepted) bind to distinct Decision Record sub-shapes without expanding the three-exit count. `/plan`'s `single-pr` vs `multi-pr` output modes are not chain-membership concerns — both modes count as `/plan` appearing in `chain_ran` — so the output-mode selection lives in a separate `plan_execution_mode:` field gated on `/plan`'s chain membership rather than on `exit:`. Both fields are conditional under invariant I-5 and parent-specific (only `/scope` has multi-boundary re-evaluation and a dual-output-mode terminal child in v1).

R9 (the hard-finalization check spec, lines 157-184 of the existing reference) currently names three parts: `exit:` valid; sub-shape valid when applicable (singular); conditional fields absent when ungated. Component 2 extends Parts 2 and 3 with concrete language covering the new vocabulary. Part 2 gains "multi-discriminator" framing — when a parent has more than one sub-shape discriminator gating the same exit (e.g., `/scope`'s `boundary:` plus `decision_record_sub_shape:` together gating the four re-evaluation Decision Record combinations), ALL discriminators MUST be set when the gating `exit:` fires. Part 3 gains "chain-membership-gated" framing — conditional fields whose trigger is chain-position rather than `exit:` follow the same I-5 absent-when-ungated rule.

The edit surface is exclusively documentation. No SKILL.md, no Go code, no runtime behavior. The edits land at four named spots inside the existing reference file; the file's overall structure (Minimum Required Fields / Field Semantics / Pattern-Level Invariants / Extension Discipline / R9 Hard-Finalization Check Spec / Topic-Slug Regex sections) is preserved.

This issue ships inside PR-4 alongside the other PR-4 pattern-doc edits (<<ISSUE:7>>, <<ISSUE:9>>), the `/scope` SKILL.md body (<<ISSUE:10>>), and downstream artifacts. The dependency on <<ISSUE:7>> is semantic, not file-level: bullet 2.1's `plan_execution_mode:` documentation references the Mandatory-with-auto-skip gate's `chain_skipped` semantics for the field's gating-condition framing; that gate vocabulary lands in `parent-skill-pattern.md` via <<ISSUE:7>>.

## Acceptance Criteria

### Edit 2.1 — Two new conditional-field bullets in Field Semantics

- [ ] `references/parent-skill-state-schema.md` gains a new bullet documenting `boundary:` inside the Field Semantics section (placed after the existing `exit_artifacts` bullet block or in a clearly demarcated "Parent-specific conditional fields" sub-block)
- [ ] The `boundary:` bullet states the gating condition verbatim: gated by `exit: re-evaluation`
- [ ] The `boundary:` bullet states the valid value set verbatim: `prd | design`
- [ ] The `boundary:` bullet identifies the field's purpose: discriminates which upstream boundary the re-evaluation Decision Record attaches to
- [ ] The `boundary:` bullet documents the multi-boundary applicability: parents with multiple settled-upstream boundaries SHALL set the field; parents with one boundary MAY omit it (with `/scope` cited as multi-boundary and `/charter` cited as single-boundary)
- [ ] A second new bullet documents `plan_execution_mode:` in the same Field Semantics section
- [ ] The `plan_execution_mode:` bullet states the gating condition verbatim: gated by `/plan` appearing in `chain_ran`
- [ ] The `plan_execution_mode:` bullet states the valid value set verbatim: `single-pr | multi-pr`
- [ ] The `plan_execution_mode:` bullet identifies the field's purpose: records the output-mode selection of a terminal child with two output modes
- [ ] The `plan_execution_mode:` bullet identifies the field as parent-specific (only `/scope` has a terminal child with this property in v1)
- [ ] `grep -q 'boundary:' references/parent-skill-state-schema.md` returns 0
- [ ] `grep -q 'plan_execution_mode:' references/parent-skill-state-schema.md` returns 0
- [ ] `grep -q 'exit: re-evaluation' references/parent-skill-state-schema.md` returns 0 (the gating clause for `boundary:`)
- [ ] `grep -q "single-pr" references/parent-skill-state-schema.md` returns 0
- [ ] `grep -q "multi-pr" references/parent-skill-state-schema.md` returns 0

### Edit 2.2 — Chain-tracking paragraph addition

- [ ] The existing Chain-tracking sub-section (currently lines 105-120 of the reference, under Pattern-Level Invariants / Chain-tracking) gains a new paragraph
- [ ] The new paragraph states that output-mode selection is recorded SEPARATELY from `chain_ran` / `chain_skipped`
- [ ] The new paragraph states the rationale: the chain-tracking triad captures chain MEMBERSHIP, not output mode
- [ ] The new paragraph cites `plan_execution_mode:` as the canonical example (parent-specific field gated by terminal child appearing in `chain_ran`)
- [ ] The addition does NOT replace or reorder the existing three-bullet `planned_chain` / `chain_ran` / `chain_skipped` list

### Edit 2.3 — R9 Part 2 multi-discriminator addition

- [ ] R9 Part 2 (currently the "Sub-shape valid when applicable" bullet inside the R9 Hard-Finalization Check Spec section) gains a new paragraph or sub-bullet covering multi-discriminator parents
- [ ] The addition states that when a parent has more than one sub-shape discriminator gating the same `exit:` value, ALL discriminators MUST be set when the gating `exit:` fires
- [ ] The addition cites `/scope`'s `boundary:` + `decision_record_sub_shape:` combination as the canonical example (the two together gate the four re-evaluation Decision Record combinations: prd-re-evaluation / prd-rejection / design-re-evaluation / design-rejection)
- [ ] The addition states that UNSET or out-of-enum discriminator values fail R9 Part 2 (consistent with the existing R9 Part 2 framing for single-discriminator parents)
- [ ] The addition does NOT replace the existing R9 Part 2 single-discriminator language; the new content augments it

### Edit 2.4 — R9 Part 3 chain-membership-gated addition

- [ ] R9 Part 3 (currently the "Conditional fields absent when ungated" bullet inside the R9 Hard-Finalization Check Spec section) gains a new paragraph or sub-bullet covering chain-membership-gated fields
- [ ] The addition states that fields whose triggering condition is chain-membership (e.g., a child name appearing in `chain_ran`) follow the same I-5 absent-when-ungated rule as `exit:`-gated fields
- [ ] The addition cites `plan_execution_mode:` (gated by `/plan` in `chain_ran`) as the canonical example
- [ ] The addition states that null, empty-string, or placeholder values fail R9 Part 3 (consistent with the existing R9 Part 3 framing for `exit:`-gated fields)
- [ ] The addition does NOT replace the existing R9 Part 3 language; the new content augments it

### Cross-cutting integrity

- [ ] No edits land outside the four spots above — Field Semantics (2.1), Chain-tracking sub-section (2.2), R9 Part 2 (2.3), R9 Part 3 (2.4)
- [ ] The reference's existing section structure is preserved: Minimum Required Fields / Field Semantics / Pattern-Level Invariants (with Per-child snapshot dual-check, Conditional-field gating, Chain-tracking, Status-aware re-entry control sub-sections) / Extension Discipline / R9 Hard-Finalization Check Spec / Topic-Slug Regex
- [ ] The 5-field minimum (`topic`, `last_updated`, `phase_pointer`, `exit`, `exit_artifacts`) is NOT modified; the new fields are documented as parent-specific extensions per the existing Extension Discipline section
- [ ] The pattern-level Three Exit Paths count (full-run / re-evaluation / abandonment-forced) is NOT modified; `boundary:` discriminates within re-evaluation, not as a fourth exit path
- [ ] I-5 (Conditional-field gating invariant) wording is not modified; the new field bullets cite I-5 by reference
- [ ] No `wip/` paths appear in the edited reference (per wip-hygiene)
- [ ] `grep -c '^## ' references/parent-skill-state-schema.md` returns the same count before and after this issue (no new top-level sections added)
- [ ] `grep -q "redirect to /" references/parent-skill-state-schema.md` returns non-zero (Slot 5 refuse-and-redirect prose stays in the resume-ladder reference, not this one — sanity check that the edit didn't drift to the wrong file)
- [ ] CI green (shirabe-side pattern-doc validation, public-content checks)

## Dependencies

Blocked by <<ISSUE:7>>

<<ISSUE:7>> introduces the Mandatory-with-auto-skip gate and the formal `parent_orchestration:` state-file sentinel inside `references/parent-skill-pattern.md`. Bullet 2.1's `plan_execution_mode:` field documentation references the Mandatory-with-auto-skip gate's `chain_skipped` semantics when describing the gating condition; the gate vocabulary must exist in the pattern doc before this issue can cite it. (The file edits themselves do not collide — they touch different reference files — but the semantic citation is real.)

This issue does NOT depend on the new `references/parent-skill-worktree-discipline.md` (<<ISSUE:1>>); the worktree-divergences list is a state-schema-extension example documented in the worktree-discipline reference itself, not in this one.

## Downstream Dependencies

Blocks <<ISSUE:10>>

<<ISSUE:10>>'s `/scope` SKILL.md body cites the new state-schema vocabulary throughout — the state file schema body slot enumerates `boundary:`, `plan_execution_mode:`, and the R9 hard-finalization check spec by reference, and the resume ladder + Phase 3 exit-finalization sections depend on the I-5 conditional discipline this issue ratifies. The `/scope` body must not ship before this reference extension lands.
