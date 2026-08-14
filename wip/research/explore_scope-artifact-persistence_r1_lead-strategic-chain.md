# Lead: Does the strategic chain under /charter have the same durable-artifact floor as /scope?

## Findings

**`/charter` does not run a consolidation judgment at all.** `skills/charter/SKILL.md` describes only orchestration (state, resume, upstream flag, security) — there is no absorb/keep judgment phase anywhere in its phase list (Phase 0 Setup, Phase 1 Discover, Phase 2 Chain, Phase N Finalize; `skills/charter/SKILL.md:151-181`). STRATEGY is explicitly called the durable terminal artifact and ROADMAP the working artifact that follows it unconditionally: "A full run also produces a ROADMAP, which `/roadmap` writes on every chain unless the author declines it (R7)" (`skills/charter/SKILL.md:26-34`). Every full `/charter` run therefore always leaves STRATEGY (and typically VISION) on disk — there is no code path that reduces this.

**The mapping test, applied to the strategic chain, would find nothing absorbable anyway.** Required sections per `crates/shirabe-validate/src/formats.rs:149-223`:

| Hop | Upstream required sections | Home in downstream | Absorbable |
|---|---|---|---|
| VISION to STRATEGY | Status, Thesis, Audience, Value Proposition, Org Fit, Success Criteria, Non-Goals | Status matches Status, Non-Goals matches Non-Goals; Thesis has a plausible but not exact home in Strategic Context/Defensibility Thesis; Audience, Value Proposition, Org Fit, Success Criteria have no home in STRATEGY's sections (Strategic Context, Defensibility Thesis, Building Blocks, Coordination Dependencies, Bet-Specific Falsifiability, Downstream Artifacts) | No |
| STRATEGY to ROADMAP | Status, Strategic Context, Defensibility Thesis, Building Blocks, Coordination Dependencies, Bet-Specific Falsifiability, Non-Goals, Downstream Artifacts | Status matches Status; Building Blocks arguably maps to Features, Coordination Dependencies arguably maps to Dependency Graph; Strategic Context, Defensibility Thesis, Bet-Specific Falsifiability, Non-Goals, Downstream Artifacts have no home in ROADMAP's sections (Theme, Features, Sequencing Rationale, Progress, Implementation Issues, Dependency Graph) | No |

This is the exact table `docs/designs/current/DESIGN-scope-consolidation-over-skipping.md` Decision 9 states in prose (not as a table there, but the same conclusion): "STRATEGY's required sections have no home for a VISION's Audience, Value Proposition, Org Fit, or Success Criteria; ROADMAP's have no home for a STRATEGY's Defensibility Thesis, Building Blocks, or Bet-Specific Falsifiability. Zero strategic hops are absorbable" (`DESIGN-scope-consolidation-over-skipping.md:362-370`).

**ROADMAP is a working artifact, confirmed.** `skills/roadmap/SKILL.md:60-68`: "**Lifecycle:** Working. Completion condition: all features on the ROADMAP are at status Done AND all referenced GitHub issues are closed... **Deleted by:** the work-on cascade's handle_roadmap_deletion step." This mirrors the workspace-wide contract stated in this repo's `CLAUDE.md:53-64` ("Artifact Lifecycle: per-skill" — "Working artifacts retire on completion... (PLAN, ROADMAP)").

**The shipped DESIGN puts `/charter` explicitly out of scope and answers the generalization question in prose, in Decision 9** (`DESIGN-scope-consolidation-over-skipping.md:353-372`):
- Option A, chosen: "state in prose that the consolidation model is a no-op on the strategic chain, and change nothing."
- Option B, rejected: implement the same model in `/charter` now — out of scope per the PRD, and "the consolidation half would add machinery that can never fire."
- Option C, rejected: say nothing — the PRD asks for the answer to be stated.
- Reasoning given: `/charter` already took the "run every child" half of this model — PR #252 made `/roadmap` an ALWAYS child with author declination, the same move Decision 1 makes for `/design` in the tactical chain. But the *consolidation* half (absorb-or-keep) does not generalize, "and the mapping test from Decision 4 says why," with zero strategic hops absorbable, so "porting the judgment would install a rule that can only ever return `keep`." Final line: "The model is intended to generalize; generalizing it today changes nothing, which is the reason not to."

The companion BRIEF (`docs/briefs/BRIEF-scope-consolidation-over-skipping.md:168-170`) lists in its Out of Scope section: "`/charter` and the strategic chain. Whether the model generalizes to VISION to STRATEGY to ROADMAP is a question the DESIGN answers in prose."

**No shared reference carries the consolidation mechanism.** I checked the two references both `/charter` and `/scope` bind to at the pattern level: `references/parent-skill-pattern.md` and `references/pipeline-model.md`. Neither mentions "absorb," "consolidat[e/ion]," or a mapping test — grepped both files for those terms, zero matches. The mapping-test logic and its mapping table live entirely inside `/scope`'s own phase files (`skills/scope/references/phases/phase-1-discovery.md`, `phase-2-chain-orchestration.md`, `phase-3-exit-finalization.md`, `skills/scope/references/state-schema.md`) and in the DESIGN doc, not in any pattern-level file `/charter` reads. `references/parent-skill-state-schema.md` uses the word "absorbed" once (`:221`) but in the ordinary-English sense ("not silently absorbed"), unrelated to the consolidation mechanism — a false-positive grep hit, not a shared surface.

## Implications

If a future change wanted `/charter` to gain the same consolidation judgment, it would need net-new machinery written specifically for `/charter` (a Phase 2-equivalent judgment step, its own reference doc) — there is no shared pattern-level home to edit once. That said, the DESIGN's own conclusion is that this machinery would be dead code today: the mapping test returns "no home" at both strategic hops, so the judgment could only ever emit `keep`, identical to `/charter`'s current unconditional-run behavior. Implementing it now would be Decision 9's rejected Option B.

## Surprises

The strategic chain already independently adopted half of the tactical chain's model (ALWAYS-child-with-declination for ROADMAP, mirroring `/design` in the tactical chain, per PR #252) before this DESIGN was written — so the two chains aren't fully divergent, they just diverge specifically on the absorb/keep half, and only because the schemas happen not to support it.

## Open Questions

None — the DESIGN gives an explicit, reasoned answer rather than leaving this open.

## Summary
`/charter` has no consolidation judgment at all — it's out of scope by explicit DESIGN decision (Decision 9), and every full run always leaves a durable STRATEGY (ROADMAP is a working artifact, per `skills/roadmap/SKILL.md`'s Artifact Lifecycle section, deleted on completion). Applying `/scope`'s mapping test to the strategic chain confirms zero absorbable hops (STRATEGY has no home for VISION's Audience/Value Proposition/Org Fit/Success Criteria; ROADMAP has no home for STRATEGY's Defensibility Thesis/Building Blocks/Bet-Specific Falsifiability), so the DESIGN concludes generalizing the mechanism today would be dead code that can only ever return "keep." No shared reference (`parent-skill-pattern.md`, `pipeline-model.md`) carries the mapping-test logic — it lives entirely in `/scope`'s own phase files, so a future change extending this to `/charter` would need new machinery, not a one-place edit.
