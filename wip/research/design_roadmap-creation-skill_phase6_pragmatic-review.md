# Pragmatic Review: Roadmap Creation Skill Design

**blocking_count: 1**
**advisory_count: 3**

---

## Blocking

### 1. Phase 2 role selection heuristic is speculative generality

Lines 89-92: The 3 heuristics ("New capability", "Extension of existing",
"Refactoring/migration") select 3 of 4 roles each time, meaning exactly 1
role is dropped per run. A 4-role pool where you always use 3 is a 4-role
pool with extra decision logic. Either use all 4 (simpler, no heuristic
needed) or cut to 3 fixed roles. The selection heuristic adds branching
with no demonstrated payoff -- every combination includes "completeness"
and every combination includes at least 2 of the other 3.

**Fix:** Drop to 3 fixed roles (completeness + dependency + sequencing).
Fold "downstream artifact assessor" into the sequencing analyst -- checking
needs-* annotations is a 2-line addendum, not a full investigation role.
Remove the selection heuristic entirely.

---

## Advisory

### 2. Transition script for a 3-state linear lifecycle

The vision skill's transition script handles 4 states with directory
movement (Sunset moves files to `docs/visions/sunset/`). The design
explicitly says roadmaps have "no directory movement" and a simpler
lifecycle (Draft -> Active -> Done). A bash script for `sed` on a
frontmatter field with 2 valid transitions is ceremony. The SKILL.md
instructions can just tell the agent to update the frontmatter directly.

PRD has no transition script and manages fine. Consider skipping
`transition-status.sh` and adding it later only if transition errors
actually occur. **Advisory** because the script is small and follows
pattern.

### 3. Handoff artifact template divergences section is scope creep

Lines 169-179 explain why the template differs from PRD/VISION templates
("Theme Statement replaces Problem Statement", etc.). This is rationale
for a decision nobody asked about -- the divergences are self-evident from
the template itself. Adds ~10 lines of design doc that will never be
referenced. Minor, but symptomatic of over-justification.

**Fix:** Cut the "Divergences from PRD/VISION templates" paragraph.

### 4. "Downstream artifact assessor" role overlaps with jury role 3

Phase 2's "downstream artifact assessor" investigates needs-* annotation
accuracy. Phase 4's "annotation and boundary reviewer" validates needs-*
labels match descriptions. These check the same thing at different stages.
The jury role is sufficient -- Phase 2 agents should investigate features
and dependencies, not annotations that haven't been written yet.

**Fix:** If keeping 4 Phase 2 roles (see finding 1), drop this one first.

---

## Not Flagged

- 4-phase pattern reuse: proven across 3 skills, justified.
- Auto-continue handoff replacing inline production: consistent with
  cross-cutting decision, removes a code path.
- 6 scope dimensions in Phase 1: these are prompts, not code. Low cost.
- 3 jury roles: reasonable for the validation concerns listed.
- Minimum 2-feature constraint: correctly scoped.
