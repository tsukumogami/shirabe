# /prd Scope: Complexity Routing Expansion

## Problem Statement

The /explore skill's routing table has 3 complexity levels
(Simple/Medium/Complex), but the pipeline supports 5. Trivial work has no
documented path, and Strategic work (VISION -> Roadmap -> per-feature) has
no entry despite F1 and F2 delivering the skills that make it viable. Agents
can't classify incoming work into the right pipeline path without these levels.

## Initial Scope

### In Scope
- Expand the Complexity-Based Routing table from 3 to 5 levels
- Add Trivial level: /work-on with no issue, Diamond 3 only
- Add Strategic level: VISION/Roadmap entry points, all three diamonds
- Define signals for each level (how agents classify incoming work)
- Update Artifact Type Routing Guide and Quick Decision Table for consistency

### Out of Scope
- Changes to the crystallize framework (separate feature, added to roadmap)
- Changes to /work-on, /implement, or other downstream skills
- New skills or commands
- Changes to the pipeline model itself

## Research Leads

1. **Current routing behavior gaps**: What happens when trivial or strategic
   work hits /explore today? Does it handle it poorly or by accident?

2. **Signal definition**: What distinguishes trivial from simple, and complex
   from strategic? The roadmap gives entry points but not classification signals.

3. **Routing table consistency**: Three routing sections exist in SKILL.md
   (Artifact Type Routing Guide, Quick Decision Table, Complexity-Based Routing).
   Which need updates?

## Coverage Notes

- User confirmed crystallize framework changes are out of scope for F4
- User identified a crystallize calibration problem (biases toward unknowns over
  undocumented knowns) -- to be captured as a new Feature 7 in the roadmap
