# Architect Review: Strategic Pipeline Roadmap + F2/F6 PRDs

Reviewer: architect-reviewer
Date: 2026-04-04
Inputs: ROADMAP-strategic-pipeline.md, PRD-roadmap-skill.md, PRD-plan-skill-rework.md, DESIGN-roadmap-creation-skill.md

---

## 1. PRD Split Assessment

The split between F2 (roadmap creation) and F6 (plan rework) is structurally sound. Each PRD owns one skill's changes: F2 owns /roadmap, F6 owns /plan. The boundary is clean -- F2's out-of-scope section explicitly excludes "/plan skill's roadmap consumption behavior" and F6's out-of-scope excludes "/roadmap creation skill."

**One duplication that needs resolution.** Both PRDs define the same requirement:

- F2 R7: "When /plan consumes a roadmap, it enriches the roadmap directly..."
- F6 R1: "When /plan consumes a roadmap, it adds Implementation Issues table and Mermaid dependency graph directly into the roadmap document..."

These are the same behavior described from two perspectives. F2 R7 describes what the roadmap *receives*; F6 R1 describes what /plan *does*. Today they agree, but if either PRD is updated independently, they can drift. One of them should be authoritative and the other should cross-reference it. Since the behavior is a /plan action, F6 R1 should own the definition and F2 R7 should say "see PRD-plan-skill-rework.md R1" for the enrichment spec, keeping only the structural requirement that the roadmap format must support enrichment (i.e., it must have slots for Issues table and dependency graph). **Advisory** -- the duplication is contained to two files and doesn't affect implementation, but it will cause confusion during design review of F6.

Similarly, F2 R8 ("Roadmap planning is always multi-pr") and F6 R2 ("Roadmap mode is always multi-pr") are identical. Same recommendation: F6 should own it, F2 should reference it.

**Nothing substantive fell through the crack between the two PRDs.** The /explore handoff is fully in F2 (R9). The completion cascade is fully in F6 (R5). Progress consistency is in both but from different angles: F2 R6 defines the invariant, F6 R4 defines the mechanism. This split is appropriate -- the invariant belongs to the artifact owner, the enforcement mechanism belongs to the skill that triggers updates.

## 2. Sequencing Assessment

The roadmap's dependency graph says F6 depends on F2. This holds: /plan can't enrich roadmaps if the /roadmap skill (and its format spec) doesn't exist yet. The format spec defines the sections that /plan writes into.

**Sequencing gap: F5 (Transition Scripts) should also be a dependency of F6, not just F1+F2.** F6 R1 says /plan transitions the roadmap Draft -> Active. If F6 ships before F5, /plan will need to do an ad-hoc frontmatter update rather than calling the transition script. The design doc's "Downstream consumption" section already assumes a `transition-status.sh` exists. Either:
- Add F5 as a dependency of F6 (clean, but lengthens the critical path), or
- F6's design must specify that it calls `transition-status.sh` if it exists and falls back to direct frontmatter edit otherwise.

**Advisory** -- this won't cause structural damage because the transition script is a convenience wrapper around a sed operation, but it's a gap in the dependency graph that should be documented either way.

**F7 dependency is over-specified.** The roadmap says F7 depends on F1-6. Documentation can be written incrementally. F7 could start after F1-F4 (the pipeline model is complete at that point) and update when F5-F6 land. Not blocking -- just a scheduling note.

## 3. F2 Design vs F2 PRD Consistency

**Conflict: Phase 2 agent count.** The PRD doesn't specify agent roles (correct -- PRDs define what, not how). The design specifies "3 fixed agent roles" in Decision 1, but the Solution Architecture section says "4-role agent pool" for Phase 2 (line 222: `phase-2-discover.md -- 4-role agent pool`). The decision text explicitly rejected the 4-role option ("Over-engineered... 3 fixed roles is simpler"). The component listing contradicts the decision. **Blocking within the design doc** -- the component comment must say "3-role" to match Decision 1. This is an internal design inconsistency, not a PRD/design conflict.

**Conflict: Standalone data flow.** The design's standalone flow diagram (lines 289-305) shows "Phase 2: Discover (2-3 agents from 4-role pool)" -- again referencing the rejected 4-role pool with a selection heuristic. Decision 1 chose 3 fixed roles, always all three. The diagram should say "Phase 2: Discover (3 agents)". **Blocking within the design doc** -- same issue as above.

**Missing from design: R6 (Progress consistency invariant).** The PRD requires that "the roadmap must reflect" closed GitHub issues. The design has no mechanism for this -- it covers creation and lifecycle transitions but not progress synchronization. The design's "Downstream consumption" note says /plan handles enrichment, and the PRD's Known Limitations section says "How completion events propagate back to the roadmap is a /plan and /work-on concern." This is consistent -- the design correctly omits it because it's F6's responsibility. No issue here, but the design should state this explicitly as an out-of-scope item rather than leaving it implicit.

**No other PRD/design conflicts found.** The lifecycle states (Draft -> Active -> Done), the format spec adoption, the handoff pattern, the minimum 2 features requirement, and the no-directory-movement decision all align between PRD and design.

## 4. Circular Dependency Analysis

The concern: F2 defines the roadmap format. F6 makes /plan enrich roadmaps. /plan needs to know the format to write into it. But F2 R7 says "the roadmap IS the plan" -- so the format must accommodate plan-level content (Issues table, dependency graph).

**This is not a circular dependency.** It's a producer-consumer relationship with a shared schema:

1. F2 defines the roadmap format spec, including slots for Issues table and dependency graph (empty at creation time).
2. F6 teaches /plan to populate those slots.
3. The format spec is the contract between them.

The dependency is strictly one-directional: F6 depends on F2's format spec. F2 doesn't depend on F6 -- it just needs to leave room for the sections that /plan will later populate. The design confirms this: roadmaps are created with features, sequencing, and progress sections. /plan adds Issues table and dependency graph. The sections don't overlap.

**However, the format spec in F2's design doesn't explicitly define the Issues table and dependency graph slots.** The design's handoff template (lines 141-164) and the deferred production template (phase-5-produce-deferred.md lines 47-93) show the creation-time format, which has Features, Sequencing Rationale, and Progress -- but no placeholder for Implementation Issues or Mermaid dependency graph. The existing strategic pipeline roadmap (ROADMAP-strategic-pipeline.md) also lacks these sections.

This means F6 will need to *insert* new sections into an existing document, rather than *populate* existing empty sections. That's doable but more fragile than populating placeholders. **Advisory** -- the F2 format spec should define where Issues table and dependency graph go (even if empty at creation time) so F6 can populate rather than insert. This is a design-level decision, not a PRD issue.

## 5. Requirements That Fell Through

**5a. Completion cascade trigger mechanism.** Both PRDs acknowledge this gap in their Known Limitations. F2 says "How completion events propagate back to the roadmap is a /plan and /work-on concern." F6 says "detecting this reliably requires either polling or event-driven automation, which is outside current skill capabilities." Neither PRD owns solving this. The invariants are defined (F2 R6, F6 R4, F6 R5), but the enforcement mechanism is explicitly deferred.

This is acceptable as long as someone tracks it. The gap should have a feature number in the roadmap or a note that it's deferred beyond F6. Currently it's buried in Known Limitations of two separate PRDs. **Advisory** -- add a note to the roadmap's F6 description or create a placeholder Feature 8 so the gap is visible at the portfolio level.

**5b. /plan's detection of input_type: roadmap.** The plan skill already handles `input_type: roadmap` (SKILL.md line 75-82, line 125). It currently creates a PLAN doc for roadmaps. F6 changes this to enrich-in-place. But neither PRD specifies what happens to *existing* PLAN docs that were created from roadmaps before F6 ships. If someone plans a roadmap today (producing a PLAN doc), then F6 ships, the old PLAN doc becomes orphaned. **Advisory** -- probably not worth a requirement since no roadmaps have been planned yet (the only roadmap is the strategic pipeline one, which hasn't gone through /plan). But worth noting in F6's design.

**5c. CI enforcement of "Active before merge" (F2 R4).** The PRD says "The transition script or CI validates this." The design doesn't specify which. The cross-cutting decision says "CI should validate it." Neither PRD owns the CI check. If it's a transition script precondition, it only fires when someone runs the script -- it doesn't prevent a `git push` of a Draft roadmap. If it's CI, it needs a workflow file. This falls between F2 (roadmap-specific gate) and F5 (standardized transitions). **Advisory** -- the F2 design should specify the mechanism. A CI check is more reliable than relying on humans to run the transition script before pushing.

---

## Summary

| # | Finding | Severity | Location |
|---|---------|----------|----------|
| 1 | F2 R7 / F6 R1 duplicate the enrichment spec; one should be authoritative | Advisory | PRD-roadmap-skill.md R7, PRD-plan-skill-rework.md R1 |
| 2 | F5 (Transition Scripts) missing as dependency of F6 | Advisory | ROADMAP-strategic-pipeline.md sequencing |
| 3 | Design says "4-role agent pool" in two places after Decision 1 rejected it | Blocking | DESIGN-roadmap-creation-skill.md lines 222, 296 |
| 4 | F2 format spec has no placeholder slots for Issues table / dependency graph that F6 will populate | Advisory | DESIGN-roadmap-creation-skill.md |
| 5 | Completion cascade trigger mechanism deferred in both PRDs with no tracking at roadmap level | Advisory | PRD-roadmap-skill.md, PRD-plan-skill-rework.md Known Limitations |
| 6 | CI enforcement of "Active before merge" unspecified in design | Advisory | DESIGN-roadmap-creation-skill.md |

**blocking_count: 1** (internal design inconsistency on agent pool size -- Finding 3)

The PRD split is clean and the sequencing holds. The circular dependency concern is unfounded -- the relationship is a normal producer-consumer pattern through a shared format spec. The one blocking issue is contained to the F2 design document and is a straightforward fix (update two comments to match the decision that was already made).
