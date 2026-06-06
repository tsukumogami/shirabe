# Decision 5: Cross-skill consistency rules

**Dispatch context:** Walked as serial-self under sub-agent dispatch; independence-loss caveat applies.

## Question

PRD's Cluster 5 (R23-R26) prescribes four cross-skill consistency rules: /plan field-consistency pre-flight (R23), /plan AC anchor-existence grep (R24), /design Phase 6 wip-hygiene carve-out extension (R25), eval-fixture HTML-comment marker placement convention (R26). Settle placement for each.

## Constraints

- **Composability** — rules at consistent altitudes.
- **R31** — direct invocation behavior unchanged.
- **/plan phase shape** — `skills/plan/SKILL.md:287-294` shows phases 1-7; Phase 3 (Decomposition) and Phase 7 (Creation) are the natural anchor points.

## Options Considered per Rule

### R23 — /plan field-consistency pre-flight

**Question:** where does the cross-issue field-consistency check fire?

**Option A — separate phase between Phase 3 (Decomposition) and Phase 4 (Generation):** A new Phase 3.5 "Cross-Issue Consistency" reads the decomposition manifest, scans for field-contract collisions across sibling issues, and flags before agent generation runs.

**Option B — folded into Phase 7 (Creation):** The consistency check runs at emission time against the generated issue bodies; conflicts are surfaced before the issues are filed.

**Option C — folded into Phase 3 (Decomposition):** Phase 3's existing decomposition step runs the consistency check as a sub-step.

**Chosen: C.** Phase 3 is where the issue outlines are first drafted; folding the check into Phase 3 catches the collision at the earliest point. Phase 7 (Option B) catches it after agent generation has already run against contradictory specs — wasted work. Option A's separate phase adds a phase count that the PRD doesn't require. Option C reuses Phase 3's existing scope and adds a sub-step "3.6 Cross-Issue Field Consistency Pre-Flight": for each schema field that two or more sibling issues touch, verify the field's contract definition is identical across the touching issues (e.g., both define the field as enum or both as free-text); when contracts diverge, flag the collision and require resolution before Phase 4.

### R24 — /plan AC anchor-existence grep

**Question:** where does the "annotation only" AC anchor-existence check fire?

**Option A — Phase 4 (Generation) agent prompt enrichment:** Each agent prompt that generates ACs for an "annotation only" issue includes a step that greps the target file for the asserted anchor.

**Option B — Phase 3 (Decomposition) pre-flight:** Same scope as R23; check anchor existence at decomposition time.

**Option C — Phase 7 (Creation) emission-time check:** Validate ACs against target files before issue creation.

**Chosen: A.** AC anchor-existence is per-issue (each issue's ACs are independently authored); the natural fire point is when the AC is being generated, in the agent prompt. Phase 4 is where agent prompts run; the prompt grows a step: "For each AC that claims 'annotation only' or 'schema fields unchanged', grep the target file at PLAN-authoring time. If the asserted anchor exists, the AC remains as written. If the anchor is absent, rewrite the AC defensively: 'annotation added; if anchor missing, this issue includes the minimal anchor definition.'" Option B is too early (decomposition doesn't yet have AC text); Option C is too late (issues are about to be filed).

### R25 — /design Phase 6 wip-hygiene carve-out extension

**Question:** what is the exact wording of the carve-out extension?

The existing rule (verified at `phase-6-final-review.md:104-106`): `No wip/... paths appear in the committed frontmatter or prose. The only acceptable matches are quoted statements OF the wip-hygiene rule itself; any path-shaped reference is a hard fail.`

The PRD wants the carve-out to extend to "documentation of a skill's runtime wip/ usage" — e.g., a DESIGN authoring `/strategy` or `/brief` that describes the skill's runtime `wip/` contract.

**Option A — extend the carve-out with explicit clause:** Change the wording to `The only acceptable matches are (a) quoted statements OF the wip-hygiene rule itself, or (b) documentation of a skill's runtime wip/ usage (i.e., a DESIGN, PRD, or BRIEF describing a skill's wip/-file contract for skill-implementation purposes). Any other path-shaped reference is a hard fail.`

**Option B — case-by-case judgment:** Leave the rule unchanged and rely on Phase 6 reviewer judgment.

**Chosen: A.** Option B is the failure mode (silent degradation under operator judgment). Option A is mechanical and grep-checkable. The "skill-implementation purposes" qualifier prevents the carve-out from being abused for non-skill-implementation DESIGNs that happen to mention wip/.

The wording lands in `skills/design/references/phases/phase-6-final-review.md` line 104-106 verbatim.

### R26 — eval-fixture HTML-comment marker placement

**Question:** where does the convention for HTML-comment line-1 marker placement live?

The conflict: eval-fixture authoring references prescribe an HTML-comment marker on line 1 of the fixture; the frontmatter parser at `crates/shirabe-validate/src/frontmatter.rs` requires `---` to be the first non-blank line. Both can't be true.

**Option A — eval-fixture references explicitly forbid line-1 markers; markers move to frontmatter field or after frontmatter:** Update eval-authoring references to state: `HTML-comment markers SHALL NOT appear on line 1 of a fixture. Place markers either (a) inside a frontmatter field value, or (b) after the closing --- of frontmatter as the first body line.`

**Option B — frontmatter parser tolerates a single HTML-comment before ---:** Change `frontmatter.rs` to skip leading HTML comments.

**Chosen: A.** Option B requires a Rust code change and changes the validator's input contract (breaking artifacts that placed `---` on line 1 today). Option A is a documentation change to eval-fixture authoring references; existing fixtures that violate the new convention are updated as a separate migration (out of scope for this PRD; the convention itself is in scope).

The convention lands in `skills/plan/references/templates/` (the closest existing eval-fixture authoring reference location) plus any eval-authoring SKILL prose that prescribes the marker.

## Summary

| Rule | Placement |
|---|---|
| R23 field-consistency | /plan Phase 3 sub-step 3.6 (Decomposition's Cross-Issue Consistency Pre-Flight) |
| R24 AC anchor-existence | /plan Phase 4 agent prompt step (per-AC grep at generation time) |
| R25 wip-hygiene carve-out | `phase-6-final-review.md:104-106` wording extension |
| R26 eval-fixture marker | Eval-authoring references; convention forbids line-1 markers |

## Assumptions

- `/plan` Phase 3 is "Decomposition"; verified at `skills/plan/SKILL.md:289`. Phase 4 is "Generation"; verified at line 292.
- The existing wip-hygiene rule wording is at `phase-6-final-review.md:104-106`; verified by reading the file.
- The frontmatter parser at `crates/shirabe-validate/src/frontmatter.rs` requires `---` to be the first non-blank line; verified by reading `parse_doc_bytes_full_doc_with_schema_and_status` at line 346.

## Status

complete
