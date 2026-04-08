<!-- decision:start id="phase7-roadmap-branching" status="confirmed" -->
### Decision: Phase 7 Roadmap Branching and Write Target

**Context**

Phase 7 of the /plan skill creates implementation artifacts: GitHub issues (via batch script) and a PLAN document containing the Implementation Issues table and Dependency Graph. The roadmap format reserves two sections -- Implementation Issues and Dependency Graph -- that are explicitly designed to be populated by /plan. These reserved sections use HTML comment markers and empty table/mermaid stubs as placeholders. When /plan processes a roadmap, producing a separate PLAN doc duplicates information that belongs in the roadmap itself, leaving the reserved sections as dead stubs.

The decomposition artifact's frontmatter already carries `input_type` (set in Phase 1), and Phase 3 already branches on this field -- so the pattern of input_type-based branching is established in the skill.

**Assumptions**

- No external tooling besides parsePlanDoc() consumes PLAN doc artifacts for roadmap-sourced plans. If wrong: those tools would need updates to find implementation tracking in the roadmap instead of a PLAN doc.
- The HTML comment markers (`<!-- Populated by /plan during decomposition. Do not fill manually. -->`) are stable anchors for locate-and-replace. If wrong: a more structured delimiter (like the `<!-- decision:start -->` pattern) could be adopted.
- Downstream planning issues from roadmaps are processed individually via /plan (not /implement-doc), so no consumer expects a PLAN doc to exist for a roadmap. If wrong: /implement-doc would need a fallback to read from roadmaps.

**Chosen: Direct Roadmap Enrichment (no PLAN doc for roadmap input)**

When `input_type: roadmap`, Phase 7 writes implementation tracking directly into the roadmap's reserved sections instead of creating a `docs/plans/PLAN-<topic>.md` file.

The branching mechanism:
1. Phase 7 reads `input_type` from the decomposition artifact's frontmatter (already available).
2. At the top of the multi-pr path, an input_type check routes to either the existing PLAN-doc-writing path (design/prd/topic) or the new roadmap-enrichment path.
3. Step 7.1 (issue creation via batch script) is shared -- it's input_type-agnostic.
4. Step 7.2 diverges: for roadmaps, locate the reserved sections by their HTML comment markers and replace the empty stubs with populated content. The Implementation Issues table uses the roadmap's schema (`| Feature | Issues | Status |`), not the PLAN doc's schema (`| Issue | Dependencies | Complexity |`). The Dependency Graph replaces the empty `graph TD` with the full Mermaid diagram.
5. Steps 7.3-7.4 (verify, traceability) run their existing roadmap-specific paths.
6. Step 7.5 (status transition) skips for roadmaps (roadmap stays Active).
7. Resume logic adds a completion check: if the roadmap's Implementation Issues table has content rows (beyond the header), Phase 7 is complete.

**Rationale**

The reserved sections in the roadmap format exist specifically as /plan's write target. Their format contract -- HTML comment markers, empty stubs, the explicit instruction "Do not fill manually" -- was designed for exactly this use case. Not populating them (Alternative 2) would leave dead sections in every roadmap, forcing users to track down a separate PLAN doc for information that belongs in the roadmap. The hybrid approach (Alternative 3) creates two copies of the same data with no consumer for the redundant PLAN doc, and introduces a synchronization obligation.

Direct enrichment aligns with how Phase 3 already handles roadmaps: a clean branch on input_type, with roadmap-specific behavior that doesn't touch the design/prd paths. The cost is a small addition to resume logic (checking the roadmap file instead of a PLAN doc), which is proportional to the benefit.

**Alternatives Considered**

- **PLAN Doc Alongside Roadmap**: Create a PLAN doc as the canonical artifact, leaving roadmap reserved sections empty. Rejected because it violates the reserved section contract, creates a confusing user experience (where do I find my roadmap's issues?), and wastes the format design that anticipated /plan writing into those sections.
- **Hybrid (PLAN doc + roadmap enrichment)**: Produce both artifacts. Rejected because dual sources of truth require synchronization, no consumer needs the PLAN doc when tracking lives in the roadmap, and the added complexity is unjustified.

**Consequences**

Phase 7 gains a new branch in its multi-pr path, increasing the phase file's branching surface. The roadmap document becomes the single location for implementation tracking when roadmaps are planned, which simplifies the user's navigation. Resume logic needs a roadmap-aware completion check (populated table detection). The PLAN doc format and parsePlanDoc() remain untouched since roadmaps don't produce PLAN docs. Cleanup logic stays the same since wip/ artifacts are topic-scoped, not output-format-scoped.
<!-- decision:end -->
