# Maintainer Review: Strategic Pipeline Artifacts

**Reviewer perspective:** Can the next developer understand and modify these artifacts with confidence?

**Files reviewed:**
- `docs/roadmaps/ROADMAP-strategic-pipeline.md`
- `docs/prds/PRD-roadmap-skill.md`
- `docs/prds/PRD-plan-skill-rework.md`
- `docs/designs/DESIGN-roadmap-creation-skill.md`

---

## Findings

### 1. Divergent agent pool count in design doc (DESIGN-roadmap-creation-skill.md)

**Blocking.**

The design doc contradicts itself on Phase 2 agent roles. Line 81 says "3 fixed agent roles (always all three)." The Alternatives Considered section (line 105) explains why a 4th role was rejected. But the standalone data flow diagram on line 295 says "2-3 agents from 4-role pool" -- the exact model that was rejected.

The next developer reading the data flow diagram will think there's a 4-role pool with a selection heuristic. The decision text says the opposite. Someone implementing this will build the wrong thing depending on which section they read first.

**Fix:** Update line 295 from `Phase 2: Discover (2-3 agents from 4-role pool)` to `Phase 2: Discover (3 fixed agent roles)`.

### 2. PRD-roadmap-skill.md R7 belongs in PRD-plan-skill-rework.md

**Blocking.**

PRD-roadmap-skill.md R7 says: "When /plan consumes a roadmap, it enriches the roadmap directly: adds Implementation Issues table and Mermaid dependency graph, creates GitHub milestone and per-feature issues with needs-* labels, transitions Draft -> Active. No separate PLAN doc produced."

This is a /plan behavior requirement. PRD-plan-skill-rework.md R1 says the same thing nearly word for word. The PRD-roadmap-skill.md Known Limitations section even acknowledges this: "the /plan changes needed to produce this output are tracked separately."

The next developer working on the roadmap skill will see R7 in their PRD and try to implement it. But R7 is out of scope for their skill -- it describes /plan's behavior. R8 (always multi-pr) has the same problem.

The Out of Scope section says "Changes to /plan skill's roadmap consumption behavior (separate PRD)" but R7 and R8 describe exactly that. Name-behavior mismatch: the requirements list promises things the Out of Scope section excludes.

**Fix:** Move R7 and R8 to a "Coordination Requirements" or "Cross-Skill Contracts" section that makes clear these describe what /roadmap output must support, not what /roadmap implements. Or remove them entirely and let PRD-plan-skill-rework.md own them, with a cross-reference.

### 3. Design doc references "4-role pool" in key assumptions but chose 3 fixed roles

**Advisory.**

Line 66 in the design doc lists "4-role pool is sufficient" as a key assumption for Decision 1. The decision then rejects the 4-role model and picks 3 fixed roles. This is a stale assumption that survived the decision process -- it describes what was considered, not what was chosen. A reader scanning assumptions before reading the full decision will form the wrong mental model.

**Fix:** Update the assumption to reflect the chosen approach, or remove it and let the decision body speak for itself.

### 4. No reading order guidance between the two PRDs

**Advisory.**

PRD-roadmap-skill.md and PRD-plan-skill-rework.md share overlapping requirements (R7/R8 in roadmap maps to R1/R2 in plan-rework). Both point upstream to the same roadmap. Neither points to the other as a prerequisite or companion document. The roadmap's Progress table lists them under separate features (2 and 6) with a dependency (6 depends on 2), but the PRDs themselves don't say this.

A new developer finding PRD-plan-skill-rework.md first will not know they need PRD-roadmap-skill.md context. The `upstream` frontmatter points to the roadmap, not to each other.

**Fix:** Add a "Related PRDs" section or frontmatter field to each PRD pointing to the other, with a one-line explanation of the dependency direction ("PRD-roadmap-skill.md must be implemented first; this PRD assumes the /roadmap skill exists").

### 5. Roadmap is self-contained without exploration research

**No issue.**

The roadmap explains its own pipeline model, cross-cutting decisions, and feature rationale without requiring the reader to find exploration notes. The three-diamond model, five complexity levels, and sequencing rationale are all inline. Good.

### 6. Design doc upstream is consistent with its PRD

**No issue.**

DESIGN-roadmap-creation-skill.md has `upstream: docs/prds/PRD-roadmap-skill.md`. The PRD exists and covers the same scope. The design doc was written after the PRD (it references PRD requirements). No confusion here.

### 7. Naming conventions are consistent

**No issue.**

File naming follows `TYPE-kebab-case.md` throughout. Feature numbers in the roadmap (1-7) are stable and referenced consistently. Requirement numbers (R1-R12 in roadmap PRD, R1-R7 in plan PRD) use independent numbering per document, which is the right call -- they don't collide.

### 8. Roadmap Progress table says Feature 2 is "Not Started" but has downstream artifacts

**Advisory.**

The Progress table shows Feature 2 as "Not Started" with downstream artifacts `PRD-roadmap-skill.md, DESIGN-roadmap-creation-skill.md`. Both exist. Feature 1 (VISION) shows "Done" with a design doc marked "(Current)." The status tracking convention is unclear: does "Not Started" mean no code has been written, or that the feature pipeline hasn't started? It clearly has started -- it has a PRD and a design doc.

The next developer checking what to work on will see "Not Started" and not realize significant design work is already done.

**Fix:** Either update the status to reflect actual progress (e.g., "In Design" or "Planned"), or add a note explaining that "Not Started" means "no implementation started" and downstream artifacts track pre-implementation progress.

---

## Summary

| Severity | Count |
|----------|-------|
| Blocking | 2 |
| Advisory | 3 |
| Clean | 3 |

The artifacts are well-structured and largely self-contained. The two blocking issues are both cases where the next developer will read a requirement or diagram and build the wrong thing: the stale data flow diagram in the design doc, and the cross-skill requirements masquerading as roadmap skill requirements in the PRD. Both are fixable with targeted edits.
