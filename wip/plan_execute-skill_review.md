# PLAN Review

**Verdict:** PASS

The 7-issue walking-skeleton decomposition covers the DESIGN's full Implementation Approach and every parity capability, with a genuine thin end-to-end Issue 1 and sound dependency edges; the gaps below are minor sequencing/AC tightenings, not blocking omissions.

## Gaps / Issues

1. **Drift gate (R8) has no dedicated AC.** The design's single-pr data-flow step 3 names the base-branch drift gate explicitly (intent-changing halt+escalate vs. non-intent-changing absorb), and PRD AC lines cover both the halt and non-halt branches. The PLAN folds drift-gate behavior into the lifted `work-on-plan.md` template (Issue 1) and never restates it as an AC anywhere. Because it rides in verbatim on the lifted template this is parity-by-construction and acceptable, but no issue's AC asserts the drift gate still fires after the lift. Recommend adding a drift-gate assertion to Issue 7's eval set (the PRD has two ACs for it) so the parity claim is actually tested, not just inherited.

2. **Carry-forward (R9) likewise inherited, not asserted.** Same pattern: single-pr carry-forward comes verbatim with the lifted template (Issue 1), and the PRD has an explicit AC ("observable across two issues"). Issue 7's eval list does not include a carry-forward observation eval. Minor — recommend adding one.

3. **Coordinated carry-forward payload is unscoped.** The DESIGN flags (Consequences) that coordinated cross-unit carry-forward rides the coordination PR's durable state and "its exact payload is specified at plan time." Issue 4 (coordinated loop) does not mention defining that payload. This is a real design-deferred-to-plan item that the PLAN silently drops. Low severity since coordinated carry-forward is the thinnest path, but it should be an AC on Issue 4 or 5.

4. **Dependency-sequencing + skip-dependents (R10) only appears in Issue 7's table-parse-adjacent evals, not as a thickening AC.** Again inherited via the template in Issue 1; the single-pr data flow names "a failed issue skips its dependents." PRD has a dedicated AC. Issue 7 should carry a skip-dependents eval; currently its four evals are single-pr happy path, multi-pr dispatch, legacy table, and path resolution — none exercise skip-dependents.

5. **PLAN format reference doc-debt (PRD Known Limitation) is unassigned.** PRD notes the human-facing PLAN format reference documents single-pr/multi-pr but not coordinated, and "the design or plan should pick up" aligning it. No issue covers this. It is explicitly adjacent doc-debt, so omission is defensible, but it is a named follow-through with no home.

6. **The "Dependency Graph" section in the PLAN is an empty header** (line 173 has no body/diagram). The edges are recoverable from the per-issue Dependencies lines and the Implementation Sequence, so this is cosmetic, but the section should either be filled with the Mermaid graph or removed.

## Sequencing Assessment

Sound. Issue 1 is a genuine thin end-to-end slice: it forces the load-bearing risk (cross-skill `${CLAUDE_PLUGIN_ROOT}/skills/work-on/koto-templates/work-on.md` resolution + the delegation contract) to work before anything thickens, and it drives a real single-pr PLAN to a merged PR. That is the correct walking-skeleton shape. Issues 2-5 are independent thickening layers all blocked only by Issue 1, matching the design's six-step Implementation Approach (extract, narrow+dispatch, single-pr path, coordinated path, state/resume). Issue 6 correctly adds the second edge on Issue 5 (conformance binds the state schema/resume ladder/exit names that Issue 5 implements). Issue 7 is correctly gated on all five thickening issues (2-6) as the backward-compat integration gate. No circular edges. One note: the design's step-1 "extract orchestrator" actually lands inside Issue 1 (the lifted template) and Issue 3 (cascade script) split across two issues — that split is fine and arguably cleaner, but means Issue 3's "extract cascade" is logically part of the same extraction as Issue 1; both depend only on Issue 1, so no ordering hazard.

Atomicity is good: each issue is one session's worth, scoped to a small file set, and none is oversized. Issue 6 (conformance + six security surfaces) is the densest but is binding/checklist work against an already-built skill, so it holds.

## Summary

The decomposition is a correct single-pr walking skeleton with sound, acyclic dependency edges and atomic issues, and Issue 7 is properly gated on all thickening layers. The substantive weakness is that four parity capabilities (drift gate, carry-forward, skip-dependents, and coordinated carry-forward payload) are inherited via the lifted template without any AC or eval asserting they survived the lift — the PRD names dedicated acceptance criteria for each, so Issue 7's eval set should be widened to cover them. These are tightenings to an otherwise complete and well-sequenced plan, not blocking gaps; verdict is PASS.
