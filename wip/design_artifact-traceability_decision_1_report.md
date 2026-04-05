<!-- decision:start id="upstream-context-detection" status="assumed" -->
### Decision: Upstream Context Detection and Population

**Context**

Five artifact types form a traceability chain (VISION -> ROADMAP -> PRD -> DESIGN -> PLAN). The /design skill's Phase 0 PRD mode is the only workflow that populates the upstream field at creation time -- it reads the PRD path directly from `$ARGUMENTS` and writes it into the design doc frontmatter. The /prd format defines an optional upstream field pointing to a roadmap, but no creation phase populates it. The /roadmap format has no upstream field at all.

Each downstream skill has multiple entry points: standalone invocation, explore handoff, and plan issue dispatch. The upstream reference is available at some entry points (explore knows the VISION, plan issues know the roadmap) but isn't currently passed through to the creation workflow.

**Assumptions**
- The roadmap format will be extended with an optional `upstream` field (pointing to a VISION document) as part of the artifact-traceability design work.
- VISION documents follow a discoverable path convention (e.g., `docs/visions/VISION-*.md`).
- Handoff points can be modified to pass upstream paths explicitly without breaking existing workflows (the field is optional, so omission is safe).

**Chosen: Argument-Only with Handoff Enrichment**

Extend the /design model to all creation workflows: the upstream path is always passed explicitly, never detected via heuristics. Whoever creates the invocation context passes the upstream reference. The changes are:

1. **Handoff enrichment**: Each handoff point that knows the upstream adds it to the artifact or argument it passes downstream.
   - /explore Phase 5 (produce-roadmap): Add a `## Upstream` section to `wip/roadmap_<topic>_scope.md` containing the VISION document path when one was identified during exploration.
   - /plan planning issues (needs-prd): Include a machine-readable `Upstream: docs/roadmaps/ROADMAP-<name>.md` line in the issue body, alongside the existing `Roadmap:` context line.

2. **Creation workflow consumption**: Each skill's draft phase reads the upstream from available context and writes it to frontmatter.
   - /roadmap Phase 3: Read the `## Upstream` section from `wip/roadmap_<topic>_scope.md` (if present) or from `$ARGUMENTS`. Write `upstream:` to frontmatter.
   - /prd Phase 3: Read `Upstream:` from the plan issue body (if invoked from a plan issue) or from `$ARGUMENTS`. Write `upstream:` to frontmatter.

3. **Standalone fallback**: When invoked standalone without upstream context, the field is omitted. No search heuristics, no guessing.

4. **Format updates**: Add `upstream` as an optional field to roadmap-format.md frontmatter schema.

**Rationale**

This directly extends the pattern that already works in /design. The principle -- "whoever creates the context passes the reference" -- keeps each skill simple and avoids detection heuristics that could silently produce wrong results. Handoff points already have the upstream information; they just don't pass it through today. The changes are small, scoped to markdown files, and backward-compatible since upstream is optional everywhere.

**Alternatives Considered**

- **Entry-Point-Aware Detection in Phase 3**: Each skill's draft phase searches for upstream context by reading explore artifacts, scanning issue bodies, or searching `docs/` directories. Rejected because detection heuristics are fragile -- searching for "which roadmap mentions this topic" can match the wrong roadmap or miss renamed features. This adds complexity to the drafting phase for marginal benefit over explicit passing.

- **Phase 0 Detection with Context Propagation**: Add or extend Phase 0 in each skill to detect and store upstream context before scoping begins. Rejected because it introduces the same detection heuristics as Alternative 1 but earlier in the workflow. Front-loading detection doesn't make it more reliable -- it just moves the fragility. It also requires changes to more files (Phase 0, scope format, Phase 3) compared to the chosen approach.

**Consequences**

What becomes easier:
- Traceability queries ("what VISION led to this roadmap?") work by reading frontmatter -- no inference needed.
- Adding new entry points only requires ensuring they pass the upstream argument.
- Validation can check that upstream paths resolve to existing files.

What becomes harder:
- Standalone invocations without `--upstream` produce artifacts without traceability links. Users who care about traceability need to provide the path.
- Handoff points gain a small maintenance burden: when a new upstream artifact type is added, the handoff must be updated to pass it.
<!-- decision:end -->
