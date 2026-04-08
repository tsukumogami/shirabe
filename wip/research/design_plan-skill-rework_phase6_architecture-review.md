# Architecture Review: DESIGN-plan-skill-rework

## Scope

Review of `docs/designs/DESIGN-plan-skill-rework.md` for structural fit within
the shirabe skill architecture. Four questions: clarity for implementation,
missing components, phase sequencing, and simpler alternatives.

---

## 1. Is the architecture clear enough to implement?

**Mostly yes, with two gaps.**

The design correctly identifies the branching point (step 7.2), the input
signal (`input_type` from decomposition frontmatter), and the write target
(roadmap reserved sections via HTML comment markers). The data flow diagram
is concrete and maps directly to existing artifacts.

### Gap 1: Koto-adoption roadmap uses a non-standard Implementation Issues format

The design acknowledges this in the Negative Consequences section but
underestimates it as a "separate cleanup." ROADMAP-koto-adoption.md uses
a 4-column format (`Issue | Phase | Dependencies | Label`) while the design
specifies the 3-column roadmap-format.md template (`Feature | Issues | Status`).
An implementer running /plan on a future roadmap will produce the 3-column
format, creating format inconsistency across roadmaps in the same repo.

This isn't a design flaw -- it's a pre-existing deviation. But the design
should state explicitly whether it normalizes koto-adoption's format or
tolerates the divergence. As-is, an implementer won't know what to do if
they encounter the existing roadmap.

**Severity: Advisory.** Contained to one existing file. Doesn't affect new
roadmaps.

### Gap 2: Missing specification for the "locate reserved section" operation

The design says "locate the reserved sections by their HTML comment markers"
but doesn't specify the exact algorithm. The HTML comment markers are:

```
<!-- Populated by /plan during decomposition. Do not fill manually. -->
```

This comment appears in both the Implementation Issues and Dependency Graph
sections. The implementer needs to know: locate the comment, then replace
everything between it and the next `##` heading (or EOF). The existing
roadmap-format.md stubs have an empty table header after the comment for
Implementation Issues and an empty mermaid block for Dependency Graph. Does
the replacement include the stub, or insert after it?

The design shows the final output format (the populated table with milestone
heading) but doesn't specify what text gets replaced. This is solvable by
the implementer, but specifying the replacement boundaries would prevent
ambiguity.

**Severity: Advisory.** Implementer can derive it from the examples, but
explicit boundaries would be cleaner.

### Gap 3: ROADMAP-strategic-pipeline.md has no reserved sections

The strategic-pipeline roadmap (the one that contains Feature 5, which this
design addresses) doesn't have the Implementation Issues or Dependency Graph
reserved sections at all. It predates the roadmap-format.md spec that added
them. If /plan were run on this roadmap, the HTML comment markers wouldn't
exist to locate.

The design doesn't address this. Phase 7's enrichment path assumes the
markers are present. An implementer needs to know: should the enrichment
path add the sections if missing, or should it fail with a clear error
requiring the roadmap to be updated first?

**Severity: Advisory.** The design targets future roadmaps that follow
roadmap-format.md. Existing non-conforming roadmaps are a migration concern,
not a design flaw. But documenting the behavior on missing markers would
prevent implementation ambiguity.

---

## 2. Are there missing components or interfaces?

### No PLAN doc for roadmap input: impact on resume logic

The SKILL.md resume logic (line 220-228) checks for PLAN doc existence as the
first resume signal:

```
if GitHub issues exist for this design        -> Resume at Phase 7 (verify/complete)
```

For roadmap input, the GitHub issue search uses
`gh issue list --search "Design: <design-doc-path>"`. But for roadmaps, the
milestone description uses `"Roadmap: \`<roadmap-path>\`"`, not `"Design:"`.
The design's resume detection (check for populated Implementation Issues
table in the roadmap) is correct for the new path, but the existing resume
logic in SKILL.md also needs updating to handle the roadmap case. The design
mentions this in Phase 2 (implementation approach) but the SKILL.md resume
block would also need a roadmap-specific check added.

**Severity: Advisory.** The design's Phase 2 covers resume logic for Phase 7
specifically. The SKILL.md-level resume logic is a broader concern that may
need updating but isn't the design's responsibility to specify.

### Execution mode override rejected but not enforced

The PRD (R2) says roadmap mode is always multi-pr and single-pr should be
rejected with an error. The design doesn't specify where this rejection
happens. Phase 3's execution mode selection (step 3.6) presents a
recommendation to the user -- for roadmaps, it should force multi-pr without
presenting the choice, or reject user override. The design doesn't modify
Phase 3 at all, which is correct (only Phase 7 changes), but the enforcement
of "always multi-pr for roadmaps" needs to live somewhere.

Looking at Phase 3's step 3.6, roadmap input is already listed as a "moderate"
signal for multi-pr. But it's not a hard constraint -- the user could
override. The PRD says this should be an error.

**Severity: Advisory.** Phase 3's heuristic already pushes toward multi-pr
for roadmaps. Making it mandatory is a small change but is in scope for the
PRD and not addressed in the design. Could be handled during implementation
without design-level specification.

### No change to PLAN doc output listing

The SKILL.md's Output section (lines 312-328) lists what each mode produces.
The "Roadmap input" subsection currently says "planning issues with per-feature
needs-* labels instead of code-level issues. PLAN upstream field points to
the roadmap." After this design, roadmap input no longer produces a PLAN doc.
The SKILL.md needs updating but the design doesn't list it as a deliverable.

**Severity: Advisory.** Documentation update, not a structural concern. But
easy to miss if not noted.

---

## 3. Are the implementation phases correctly sequenced?

**Yes, the sequencing is correct.**

- Phase 1 (roadmap branch in Phase 7) is the core change. It must come first
  because Phase 2 depends on having the write path to test resume against.
- Phase 2 (resume logic) correctly follows -- you can't test resume detection
  until the enrichment path exists.
- Phase 3 (evals) correctly comes last -- evals validate the completed behavior.

One minor sequencing consideration: the design scopes Phase 1 to modifying
only `phase-7-creation.md`. But the change also requires updating the SKILL.md
itself (Output section, possibly resume logic). These documentation updates
could be bundled into Phase 1 or split into a Phase 1.5. As specified, the
implementer might complete Phase 1 and leave the SKILL.md inconsistent until
someone notices.

---

## 4. Are there simpler alternatives we overlooked?

### Alternative considered and correctly rejected: the PLAN doc path

The design already evaluated and rejected producing PLAN docs alongside
roadmaps (dual source of truth) and producing only PLAN docs (dead stubs in
roadmaps). Both rejections are sound.

### Alternative not considered: Phase 7 writes PLAN doc, post-processing enriches roadmap

Instead of branching Phase 7's write target, a simpler pattern would be:
Phase 7 produces the PLAN doc as it does today, then a new step 7.2b reads
the PLAN doc's content and transplants the issues table and dependency graph
into the roadmap. This avoids modifying the main write path entirely -- the
PLAN doc is still the canonical output of Phase 7, and the roadmap enrichment
is additive.

This was implicitly rejected by the "hybrid" alternative but it's slightly
different: the PLAN doc would be deleted after transplanting, not kept
alongside. The benefit is zero changes to the existing Phase 7 write path.
The cost is an extra step and a transient artifact.

**Assessment:** The design's chosen approach (direct enrichment) is cleaner.
The transplant alternative adds complexity for no structural benefit. The
branching pattern is already established in Phase 3, so adding it to Phase 7
is architecturally consistent. Not recommending the alternative.

### Alternative worth considering: make the branch point earlier

The current design branches at step 7.2 within the multi-pr path. An
alternative is to branch at the top of Phase 7 (before step 7.1), creating
a third path alongside multi-pr and single-pr: "roadmap-enrichment." This
would make the control flow explicit in the table of contents instead of
nesting a conditional inside the multi-pr path.

The benefit: step 7.1 (issue creation) is already slightly different for
roadmaps (different milestone description). Making it a first-class path
would group all roadmap-specific behavior rather than scattering conditionals
through the multi-pr path.

**Assessment:** The design's approach (branch within multi-pr) is
acceptable because step 7.1 already handles roadmap input with a conditional,
and the existing pattern is "branch on input_type within a mode." Adding a
third top-level mode would be a larger structural change that affects the
table of contents, resume logic, and execution mode selection. The
incremental branching within multi-pr is the lower-risk choice.

---

## 5. Structural fit assessment

### Pattern consistency

The design follows the established input_type branching pattern from Phase 3.
Phase 3 has a full "Roadmap Decomposition" section with steps 3.R1-3.R4
that are separate from the standard decomposition path. Phase 7 could follow
the same pattern (a dedicated "Roadmap Enrichment" section with steps 7.R1-7.Rn)
rather than nesting the branch inside step 7.2. This would be more consistent
with how Phase 3 handles the same concern.

**Severity: Advisory.** Either approach works. The Phase 3 pattern (top-level
section) is slightly more discoverable but the design's in-step branching is
functional.

### No parallel patterns introduced

The design doesn't introduce any new patterns. It reuses:
- input_type branching (established in Phase 3)
- HTML comment markers as anchors (established in roadmap-format.md)
- Feature-to-issue mapping from manifest (established in Phase 4)
- Batch script for issue creation (unchanged)

### No state contract violations

No new fields are added to any schema. The roadmap's reserved sections are
an existing contract being fulfilled, not a new one. PLAN doc structure is
unchanged for design/prd input.

### No dependency inversions

The change is entirely within the plan skill's Phase 7 reference file. It
reads from the roadmap skill's format spec (lower-level reference) but
doesn't create a dependency from roadmap -> plan.

---

## Summary of findings

| # | Finding | Severity | Action |
|---|---------|----------|--------|
| 1 | koto-adoption roadmap uses non-standard 4-column format; design should state normalization policy | Advisory | Add a note about tolerating existing format divergence |
| 2 | "Locate reserved section" algorithm not specified (replacement boundaries) | Advisory | Specify what text gets replaced between marker and next heading |
| 3 | ROADMAP-strategic-pipeline.md lacks reserved sections entirely | Advisory | Document behavior when markers are missing (add or fail) |
| 4 | Roadmap input should force multi-pr (PRD R2) but enforcement point not specified | Advisory | Clarify whether Phase 3 or Phase 7 rejects single-pr for roadmaps |
| 5 | SKILL.md Output section and resume logic need updating (not listed as deliverable) | Advisory | Add SKILL.md to Phase 1 or Phase 2 deliverables |
| 6 | Phase 7 roadmap branch could follow Phase 3's top-level section pattern for consistency | Advisory | Consider 7.R1-7.Rn structure parallel to 3.R1-3.R4 |

No blocking findings. The design is structurally sound and fits the existing
architecture. All findings are advisory -- they improve clarity for the
implementer but don't represent structural violations that would compound.
