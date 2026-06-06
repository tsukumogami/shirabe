# Decision 4: Validator vs jury split for the five candidate checks

**Dispatch context:** Walked as serial-self under sub-agent dispatch; independence-loss caveat applies.

## Question

PRD's Cluster 4 defines five candidate checks: schema-field-present (R18 / `tsukumogami/shirabe#157`), section-length-budget (R19), writing-style banned-word grep (R20), structural-format reviewer addition (R21), single-pr Implementation Issues drift (R22 / `tsukumogami/shirabe#158`). For each, the question is: does it land in the validator at FC-vocabulary level, or as a Phase 6 reviewer, or somewhere else?

## Constraints

- **Validator-vs-skill-prose tradeoff** — validator extensions require Rust code changes and a release-train cut; skill-prose edits ship with the SKILL.md changes themselves.
- **Existing validator surface** — `check_schema` at `crates/shirabe-validate/src/checks.rs:39-51` emits SCHEMA notice on schema mismatch but exits 0 on missing-schema; FC01-FC09 vocabulary is the existing extension surface; FC08 (legend-vs-classdef) was added in PR #169 as a notice (verified git log line 7).
- **Existing Phase 6 reviewer set** — `skills/design/references/phases/phase-6-final-review.md:21-55` launches architecture-reviewer and security-reviewer; no structural-format reviewer exists.
- **R32 sequencing** — R20's writing-style mechanical check lands alongside the writing-style reference (the reference at `skills/writing-style/SKILL.md` already enumerates the banned vocabulary).
- **D2 / serial-self-jury contract** — Phase 6 jury runs serial-self under sub-agent dispatch; adding a third reviewer scales the serial walk but doesn't introduce a new dispatch shape.

## Options Considered per Check

### R18 — schema-field-present (tsukumogami/shirabe#157)

**Option A (validator, FC-coded notice):** Extend `check_schema` to emit a `SCHEMA-MISSING` notice (parallel to the existing SCHEMA notice at line 45-50) when `doc.schema.is_empty()`. Land alongside the existing schema notice path; preserves the notice (not error) discharge so exit code is non-zero only at the workspace-policy level if the workspace treats notices as errors. The check is structural (frontmatter parsing), the validator is the right surface.

**Option B (Phase 6 reviewer):** The structural-format reviewer (added per R21 below) checks schema-field-present as part of its rubric.

**Option C (both):** Validator emits the notice; Phase 6 reviewer ALSO checks (redundant but defense-in-depth).

**Chosen: A.** R18 is structural and applies to every artifact type uniformly; the validator is the right surface. Option B would require the structural-format reviewer to re-parse frontmatter, duplicating logic that already lives in `frontmatter.rs`. Option C is over-engineered. The notice is non-zero exit (matching FC08's notice-discharge per PR #169 precedent).

### R19 — section-length-budget overshoot

**Option A (validator soft-warning lane):** Validator parses budgets from prose (`"approximately N lines"`) and emits a notice when actual exceeds by >X% (threshold a config field).

**Option B (Phase 6 reviewer):** A new "budget-vs-spec reviewer" rubric in Phase 6 reads the DESIGN's own prose for budget claims and counts the section lines; emits a verdict line.

**Option C (skill-prose only, no automation):** Document the discipline in `design-format.md`; no mechanical check.

**Chosen: B.** The budget-vs-spec check requires natural-language parsing of budget claims (the prose says "approximately 110 lines" or "~110 lines" or "around 110 lines" — parsing variants in the validator is brittle). The Phase 6 reviewer has the artifact context to make the judgment naturally. A new reviewer rubric extends the structural-format reviewer (R21 below) — they become one reviewer with two rubrics (`structural-format` covers section presence/order, `budget-vs-spec` covers section-length budget). Threshold: budget exceeded by >50% triggers a verdict flag (caught the BRIEF's 110/183 = 66% overshoot case).

### R20 — writing-style banned-word grep

**Option A (validator FC code):** Add `check_writing_style` to the validator; emit FC10 notices for each banned-word match.

**Option B (Phase 4/6 reviewer):** Extend the existing reviewer set (or add a new "writing-style reviewer") to grep the banned vocabulary.

**Option C (pre-commit hook):** A git pre-commit hook runs the grep before commit; failure blocks the commit.

**Option D (skill-prose only, in the writing-style SKILL):** The writing-style SKILL.md already enumerates the list; SHOULD-author-runs-it discipline.

**Chosen: A.** The grep is purely mechanical (no judgment); the validator is the right surface. The writing-style banned list at `skills/writing-style/SKILL.md` is already enumerated; the validator reads from the same canonical list. R20 emits as a notice (writing-style violations are advisory, not structural errors) — the workspace policy decides whether notices block the workflow. R32's sequencing requirement is satisfied: the writing-style reference is the source of truth; the validator's FC10 vocabulary lands alongside the reference (the validator change ships in the same PR set as the writing-style reference reaffirmation; the validator reads the canonical list at validate-time so future updates to the reference propagate without a validator code change). Pre-commit hooks (Option C) would block authors mid-flow; jury reviewer (Option B) catches less reliably than mechanical grep.

### R21 — structural-format reviewer for /design Phase 6

**Option A (extend Phase 6 reviewer set to three reviewers):** Add structural-format-reviewer as the third reviewer in `phase-6-final-review.md` step 6.1. The reviewer's rubric: artifact-shape conformance against `design-format.md` (newly materialized per Decision 3), section presence/order, frontmatter field order, budget-vs-spec check (per R19's Option B).

**Option B (extend the existing architecture-reviewer's rubric):** Add structural-format checks to the existing architecture-reviewer.

**Chosen: A.** AC4.4 explicitly says "Phase 6's jury invocation spawns a structural-format reviewer in addition to the existing reviewers." The AC's "in addition to" wording requires a new reviewer, not a rubric extension. The third reviewer composes with the serial-self-jury contract — the Phase 6 jury becomes 3 reviewers under direct invocation (3 parallel Agent-tool spawns) or 3 sequential rubric walks under sub-agent dispatch (3 self-evaluations, one per lens).

### R22 — single-pr Implementation Issues drift (tsukumogami/shirabe#158)

**Option A (validator):** Validator's existing FC checks gain an FC11 check that reconciles the emitted `## Implementation Issues` section structure against the canonical structure documented in `plan-format.md` (Decision 3 R17).

**Option B (Phase 7 self-check):** /plan Phase 7's emission step checks its own output against the canonical structure; mismatch is a phase-internal error.

**Option C (both):** Phase 7 self-check at emission time; validator catches drift on already-committed artifacts.

**Chosen: C.** Phase 7 self-check (Option B) is the upstream guard — catches drift at the moment of emission, before commit. Validator (Option A) is the downstream guard — catches artifacts that were committed by an older /plan version. Both are needed: the emission-time check prevents new drift; the validator check catches existing drift in already-committed PLANs. Phase 7 self-check is a SKILL.md edit; validator check is a Rust code change.

## Summary of validator-vs-jury split

| Check | Surface | Rationale |
|---|---|---|
| R18 schema-field-present | Validator (`check_schema` extension, notice level) | Structural, applies to every artifact type |
| R19 section-length-budget | Phase 6 reviewer (structural-format reviewer's budget-vs-spec rubric) | Requires prose parsing the validator does not have |
| R20 writing-style banned-word | Validator (new FC10 check, notice level) | Purely mechanical grep |
| R21 structural-format reviewer | Phase 6 reviewer set (new third reviewer) | AC explicitly requires "in addition to" |
| R22 Implementation Issues drift | Both: Phase 7 self-check + validator FC11 | Defense-in-depth across emission and commit-time |

The validator gets two new check vocabulary entries (SCHEMA-MISSING extension to existing check_schema; FC10 writing-style; FC11 plan-section-structure — though SCHEMA-MISSING is an extension to FC01 / `check_schema` rather than a new FC code). The Phase 6 reviewer set grows from two reviewers to three (architecture, security, structural-format). /plan Phase 7 gains an emission-time self-check.

## Assumptions

- The validator's notice mechanism (per FC08 PR #169 precedent) is the established way to add non-error advisory checks. Verified by reading checks.rs lines 39-51 (existing SCHEMA notice) and the FC08 / FC09 notice precedent in git log.
- The Phase 6 reviewer set is the right place for a structural-format reviewer because it already has the parallel-jury shape (R1's fallback applies uniformly to all reviewers in the set, including the new one).
- The writing-style SKILL.md at `skills/writing-style/SKILL.md` is the canonical source for the banned vocabulary; the validator reads from it at validate-time. Verified by reading lines 10-17 which enumerate "tier/tiered, robust, comprehensive, holistic" et al.

## Status

complete
