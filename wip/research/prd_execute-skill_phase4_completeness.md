# Completeness Review

**Verdict:** PASS

The PRD covers every goal, all eight parity capabilities, the coordination contract, and every BRIEF open question; the gaps found are minor under-specifications, not missing requirement areas.

## Gaps Found

1. **Batch-escalation operator summary is under-specified (parity capability #8, second half).** The inventory's capability #8 has two halves: (a) a self-documenting combined PR body and (b) an *actionable operator failure summary on batch escalation* (which children failed with reasons, which were skipped with their skip-chain, plus next-steps). R13 covers half (a) ("the resulting pull request body documents what the plan did") and R10 covers skip-dependents mechanics, but no requirement states that a blocked/failed run must surface a structured, actionable per-child failure+skip-chain summary at the forced-stop exit. R2 names the forced-stop exit but does not bind it to this operator-summary content. This is the one parity sub-capability that is implied rather than required.

2. **`WORK_ON_ALLOW_UNTRACKED_ACS` escape hatch not carried forward (backward-compat).** Both research files call this out as an existing env escape hatch (suppresses L06 only) that "must be preserved" for backward-compat parity (inventory backward-compat surface line 86; parity candidate #9). R3's backward-compat clause enumerates schema/execution_mode/upstream/milestone/issue-table/legacy-4-column but omits this env hatch. Since the cascade behavior moves into /execute, an existing PLAN relying on this hatch could regress silently. Minor but a concrete named backward-compat surface left uncovered.

3. **Per-issue drift re-check ("better") not decided.** Parity candidate #1 notes the drift gate runs *once* today and flags "better = per-issue re-check, not just once." The Known Limitations / R8 keep it as a single pre-advance gate (parity floor), which is acceptable, but the "or better" latitude the author's guardrail invites is neither claimed nor explicitly declined. Not a regression; an unclaimed improvement opportunity.

4. **Gate-node (non-PR) dispatch/await tooling unaddressed.** The coordination-contract research flags that the merge-order DAG includes non-PR gate nodes (e.g. a package publish) that are "verified live but have no authoring/dispatch tooling shown" and asks how /execute knows a gate node's condition and triggers/awaits it. R11/R14 speak of "per-unit pull requests" and the merge-gate; neither addresses how /execute handles a gate node that is not a PR. This is a real open item the coordination research surfaced; the PRD's Open Questions does not capture it.

## Suggested Additions

1. **Add an acceptance criterion (and a clause to R13 or R2) for the batch-failure operator summary:** "A blocked run surfaces, at the forced-stop exit, a per-child summary naming which issues failed (with reason) and which were skipped (with skip-chain) plus operator next-steps." This pins parity capability #8's second half so it cannot regress to an opaque stall.

2. **Name `WORK_ON_ALLOW_UNTRACKED_ACS` in R3's backward-compat enumeration** (or a Known Limitation) so the cascade-move preserves the existing L06 escape hatch. Low cost, closes a named parity surface.

3. **Record gate-node handling as an Open Question or a D-entry.** Either state that initial /execute scope handles only PR nodes (gate nodes deferred/refused, mirroring how cross-repo atomicity is refused at planning time) or defer the mechanism to design explicitly. Right now it falls through the cracks between R11 and R14.

4. **Resolve or down-convert the single remaining Open Question.** The PRD's own Open Question (whether /work-on grows a thin multi-pr milestone loop or multi-pr issues are author-dispatched one at a time) is left open with "Resolve before Accepted." That is correct for Draft status, but note the multi-pr exclusion AC (line 187) already assumes "no plan-level coordinator," which leans toward the no-loop answer; reconciling the AC wording with the Open Question would remove an internal tension.

## Summary

The PRD is complete at the requirement-area level: every goal has covering requirements, all eight parity capabilities map to R8-R13 (plan-level) and R6 (per-issue-delegated), the multi-pr exclusion / coordinated done-signal / narrowed-/work-on / backward-compat areas each have acceptance criteria, and all three BRIEF open questions are closed (new-skill-vs-rename in D1, koto-mechanism deferral in D3, /work-on direct-invocability in R6/R7 plus AC line 187). The gaps are under-specifications within otherwise-covered areas — the batch-failure operator summary (parity #8b), the `WORK_ON_ALLOW_UNTRACKED_ACS` escape hatch, and non-PR gate-node handling — none of which constitutes a missing requirement area or a silent value regression. Verdict is PASS with the four additions recommended before the PRD moves to Accepted.
