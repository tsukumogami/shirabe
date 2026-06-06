# Decision 7: Sequencing and migration ordering

**Dispatch context:** Walked as serial-self under sub-agent dispatch; independence-loss caveat applies.

## Question

Given R32's pattern-level-first constraint and R31's backward-compatibility constraint, what is the implementation-issue ordering across the fix-class set? Which clusters land first because their shape is upstream to the others? How are the changes batched for /plan's downstream consumption?

## Constraints

- **R32** — pattern-level reference edits (R10, R13, R14, R16) land before per-skill consumers (R1-R9, R11-R12, R15, R17). Validator extensions (R18-R22) land alongside or after the prose changes that reference them.
- **R31** — direct invocation behavior unchanged at every batch boundary.
- **AC8.2** — sequencing respects R32 explicitly.

## Options Considered

### Option A — Three-batch ordering with pattern-level batch first

**Batch 1 (pattern-level upstream):**
- Decision 1's pattern-level edit (`references/parent-skill-pattern.md` Sub-Agent Dispatch Fallbacks section)
- Decision 2's pattern-level edit (`references/parent-skill-pattern.md` Child-Side Sentinel Consultation Row Convention subsection)
- Decision 3's format-reference materialization (`design-format.md`, `plan-format.md`) plus R11, R13, R14, R16 edits to brief-format / prd-format
- Decision 5's R25 wip-hygiene carve-out (`phase-6-final-review.md`)
- Decision 6's R28 CLAUDE.md `## Release Notes Convention:` convention addition
- Decision 6's R30 new shared reference (`references/cli-version-preflight.md`)

**Batch 2 (per-skill consumers of pattern-level):**
- Decision 1's per-skill section additions to all 8 child SKILLs
- Decision 2's per-skill Resume Logic row additions to all 7 child SKILLs
- Decision 3's per-skill citations (DESIGN's "Sections Added During Lifecycle" subsection; /plan's emission prose)
- Decision 5's R23 /plan Phase 3 sub-step 3.6 addition
- Decision 5's R24 /plan Phase 4 agent-prompt enrichment
- Decision 5's R26 eval-fixture authoring convention update
- Decision 6's R27 /scope Phase 0 slug-prefix sampling
- Decision 6's R29 /scope Phase 1 cold-start projected-PRD evaluation
- Decision 6's R30 per-skill CLI-preflight citations
- Decision 4's R21 /design Phase 6 structural-format reviewer addition (skill-prose edit, prose-only)
- Decision 4's R22 /plan Phase 7 emission self-check (skill-prose edit)

**Batch 3 (validator extensions, downstream of prose):**
- Decision 4's R18 `check_schema` SCHEMA-MISSING notice extension
- Decision 4's R20 new FC10 writing-style check
- Decision 4's R22 new FC11 plan-section-structure check (parallels Phase 7 self-check)
- Decision 4's R19 budget-vs-spec rubric is part of Batch 2's R21 structural-format reviewer (no separate validator change)

### Option B — Two-batch ordering (pattern-level vs everything-else)

Collapse Batches 2 and 3 into one batch. Validators and skill-prose ship together.

**Cons:** R32 explicitly says validator extensions land alongside OR AFTER prose changes that reference them. Option A's three-batch ordering makes the "after" branch concrete; Option B's two-batch ordering is "alongside" only. R32's permissive wording allows either, but Option A's three-batch ordering reduces risk — if a validator extension misfires under unexpected artifact shapes, Batch 3 can be reverted independently of the prose changes.

### Option C — Single-batch ordering (everything ships together)

**Cons:** Violates R32. Pattern-level edits and per-skill consumers must ship in distinct batches so per-skill consumers can cite the pattern-level statement (the pattern-level reference must exist at the moment the per-skill citation is added).

## Chosen: Option A — Three-batch ordering

**Rationale.** R32 sequencing is structural; Option A makes the dependencies explicit. Each batch is independently shippable (R31 backward compatibility holds at every batch boundary because the sentinel is the entry condition — Batch 1 adds the contract but no consumer fires it; Batch 2 adds consumers that fire when the sentinel is present; Batch 3 adds validator checks that detect the contract violations in committed artifacts).

**Cross-batch dependency graph:**

```
Batch 1 (pattern-level)
├── (no upstream dependencies)
└── Decision 1, 2, 3 pattern edits + Decision 5 R25 + Decision 6 R28, R30 references

Batch 2 (per-skill consumers)
├── depends on Batch 1 for pattern-level citations
└── Decision 1, 2, 3 per-skill edits + Decision 4 R21/R22 skill-prose + Decision 5 R23/R24/R26 + Decision 6 R27/R29/R30 citations

Batch 3 (validator extensions)
├── depends on Batch 2 for canonical structure references (FC11 reads plan-format.md; FC10 reads writing-style SKILL)
└── Decision 4 R18, R20, R22 validator code changes
```

**Implementation-issue grouping for /plan downstream consumption.** When `/plan` decomposes this DESIGN into issues, the three batches map to three groups of sibling issues. Each batch's issues can fan out internally; batches sequence top-down. The total issue count is approximately:

| Batch | Issue count estimate | Files touched (approx) |
|---|---|---|
| Batch 1 (pattern-level) | 6-8 issues | 5 files (parent-skill-pattern.md, design-format.md NEW, plan-format.md NEW, brief-format.md, prd-format.md, phase-6-final-review.md, CLAUDE.md, cli-version-preflight.md NEW) |
| Batch 2 (per-skill) | 12-16 issues | ~14 files (8 child SKILLs + 4 phase reference files for /scope, /plan, /design + writing-style reference clarifications) |
| Batch 3 (validator) | 3-4 issues | 3 files (checks.rs, validate.rs, formats.rs in crates/shirabe-validate) |

Total estimate: ~25-30 implementation issues across ~22 files.

## Assumptions

- The dependency-graph claim (Batch 2 needs Batch 1's pattern-level statement before per-skill citations are added) is structural — a per-skill citation that points at a non-existent pattern-level section is a broken link.
- Validators reading from canonical references (FC10 reads writing-style SKILL; FC11 reads plan-format.md) means Batch 3 needs Batch 1 + Batch 2 to be in place; the validator's check logic dereferences the canonical reference at validate-time, so a missing reference is a validator runtime error.
- The total issue/file count is an estimate for the PR description and downstream `/plan` scoping; actual count is determined by `/plan`.

## Status

complete
