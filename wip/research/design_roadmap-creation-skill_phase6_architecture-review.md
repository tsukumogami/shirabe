# Architecture Review: Roadmap Creation Skill Design

**Reviewer:** architect-reviewer
**Design doc:** `docs/designs/DESIGN-roadmap-creation-skill.md`
**Pattern reference:** `docs/designs/current/DESIGN-vision-artifact-type.md`
**Date:** 2026-04-04

---

## 1. Is the architecture clear enough to implement?

**Yes, with one gap.** The design specifies all deliverables, their locations, phase
responsibilities, and handoff contracts. An implementer can work from it directly.

The gap: the design says "format spec adopted from private plugin" but doesn't
reproduce or reference the format spec inline. The /vision design embeds its full
section matrix, frontmatter schema, and content boundaries directly. The roadmap
design includes a template in the *explore handoff* section and another in the
existing `phase-5-produce-deferred.md` Roadmap section, but these are the handoff
artifact and the inline production template respectively -- neither is the format
spec for the skill's `references/roadmap-format.md`. An implementer would need to
reverse-engineer the format from these fragments plus the private plugin (which
isn't accessible from the public repo).

**Finding R1 (Advisory).** Add the roadmap format spec to the design doc (frontmatter
schema, required sections, validation rules, content boundaries) or explicitly
reference the private plugin path the implementer should adopt from. Without it,
Phase 1 implementation requires a separate discovery step. Not blocking because the
fragments in the design plus the existing deferred template provide ~80% of the spec.

## 2. Are there missing components or interfaces?

### 2a. Crystallize framework update -- missing from design

The /vision design includes a dedicated deliverable for updating the crystallize
framework (`skills/explore/references/quality/crystallize-framework.md`) with signal
tables, tiebreaker rules, and disambiguation rules. The roadmap design does not
mention this at all.

Currently, the routing table in `phase-5-produce.md` (line 47) sends Roadmap to
`phase-5-produce-deferred.md`. Changing the routing is covered by the design
(Phase 3). But the crystallize framework itself -- which decides *whether* to
recommend Roadmap as an artifact type in the first place -- is not addressed.

Roadmap is already a recognized type in the crystallize framework (it routes to
deferred today), so the signal/anti-signal table presumably exists. But if the
design intends any changes to crystallize scoring (e.g., removing Roadmap from
"deferred types" commentary, updating tiebreaker rules now that /roadmap has a
full skill), that should be explicit.

**Finding R2 (Advisory).** Confirm whether the crystallize framework needs updates
for Roadmap (signal table changes, removing from deferred types list, new tiebreaker
rules). If no changes needed, state that explicitly. The /vision design made this a
separate implementation phase; its absence here could be intentional or an oversight.

### 2b. No `roadmap-format.md` reference file listed

The component tree shows `references/roadmap-format.md` but the Phase 1
deliverables list does not include it:

```
Phase 1 Deliverables:
- skills/roadmap/SKILL.md
- skills/roadmap/references/roadmap-format.md          <-- in tree, not in list
- skills/roadmap/references/phases/phase-1-scope.md
- ...
```

Wait -- it IS in the deliverables list. Confirmed: present in both the component
tree and Phase 1 deliverables. No issue here; I misread initially.

### 2c. Eval structure unclear

The design lists `skills/roadmap/evals/evals.json` as a Phase 4 deliverable but
doesn't specify eval scenarios. The /vision design also deferred eval specifics,
so this matches the pattern. No issue.

## 3. Are the implementation phases correctly sequenced?

**Yes.** The sequencing matches the /vision pattern and respects dependencies:

- Phase 1 (skill + format + phases): no external dependencies
- Phase 2 (transition script): depends on Phase 1 for lifecycle states to validate
- Phase 3 (explore handoff): depends on Phase 1 for the skill to invoke
- Phase 4 (evals): depends on Phases 1-3 for the complete skill to test

One note: the /vision design bundled the transition script into Phase 1 alongside
the skill. The roadmap design separates it into Phase 2. Both orderings work -- the
transition script has no callers during initial creation (it's used post-creation for
lifecycle management). The separation is arguably cleaner for PR review.

**No blocking issue.**

## 4. Are there simpler alternatives we overlooked?

### 4a. Simpler lifecycle (no transition script at all)

The roadmap lifecycle is Draft -> Active -> Done. This is simpler than vision's
4-state lifecycle with directory movement. The design could skip the transition
script entirely and document the transitions as manual frontmatter edits, since:
- No directory movement (all states stay in `docs/roadmaps/`)
- Only 2 transitions with straightforward preconditions
- Roadmaps are infrequent documents

However, the cross-cutting decision from the strategic pipeline roadmap explicitly
requires script-driven transitions. And the pattern is established: design doc and
vision both have transition scripts. Adding a third is consistent, not over-engineered.

**No issue.** The script is justified by the cross-cutting decision.

### 4b. Merge Phase 2 into Phase 1

With only one deliverable (the transition script), Phase 2 is thin. It could merge
into Phase 1 without affecting the dependency chain. But this is a sequencing
preference, not an architectural concern.

**No issue.**

## 5. Pattern consistency with /vision design

| Dimension | /vision | /roadmap | Consistent? |
|-----------|---------|----------|-------------|
| SKILL.md with format + workflow | Yes | Yes | Yes |
| Separate format reference file | `references/vision-format.md` | `references/roadmap-format.md` | Yes |
| 4 phase files in `references/phases/` | Yes | Yes | Yes |
| Transition script in `scripts/` | Yes | Yes | Yes |
| Phase 5 handoff handler | `phase-5-produce-vision.md` | `phase-5-produce-roadmap.md` | Yes |
| Routing table update | Yes | Yes | Yes |
| Evals in dedicated phase | Yes | Yes | Yes |
| Crystallize framework update | Dedicated phase | Not mentioned | **Divergence** |
| Handoff artifact format | Problem Statement + Research Leads | Theme Statement + Candidate Features | Intentional, domain-appropriate |
| Standalone + handoff entry | Yes | Yes | Yes |

The only structural divergence is R2 above (crystallize framework). Everything else
follows the established pattern faithfully.

## 6. Structural findings unique to roadmap

### 6a. Deferred file cleanup is well-handled

The design explicitly states: remove the Roadmap section from
`phase-5-produce-deferred.md`, no fallback. After removal, deferred retains
Prototype, Spike Report, Competitive Analysis. This is clean -- no dual code path.

Verified against the current state of `phase-5-produce-deferred.md`: the Roadmap
section exists (lines 46-103) and would be removed. The table of contents and
Unsupported Type section would need updates (Prototype is already described as the
only remaining deferred type on line 9, which suggests someone already partially
updated the framing but left the Roadmap section in place). Minor implementation
detail, not a design issue.

### 6b. Handoff artifact divergence is justified

The roadmap handoff uses "Theme Statement + Candidate Features" instead of
/vision's "Problem Statement + Research Leads". The design explains why: roadmaps
coordinate multiple features, not solve a single problem. The section mapping is
clean (Theme Statement -> Phase 2 agents investigate features, not open questions).

**No issue.** Domain-appropriate divergence, not a parallel pattern.

---

## Summary

| ID | Finding | Severity |
|----|---------|----------|
| R1 | Format spec not included in design -- implementer must discover from fragments or private plugin | Advisory |
| R2 | Crystallize framework update not addressed (present in /vision design, absent here) | Advisory |

**Blocking count: 0**

The design follows the /vision pattern faithfully across all structural dimensions.
The two advisory findings are documentation gaps that won't cause structural
divergence -- they affect implementation clarity, not architectural fit. The phase
sequencing respects dependencies, the handoff contract matches the established
auto-continue pattern, and the deferred-file cleanup avoids dual code paths.
