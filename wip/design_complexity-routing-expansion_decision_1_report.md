<!-- decision:start id="complexity-routing-table-design" status="assumed" -->
### Decision: Complexity Routing Table Design

**Context**

The /explore SKILL.md currently has a 3-level complexity routing table (Simple, Medium, Complex) that agents use to classify incoming work and recommend a workflow path. The strategic pipeline roadmap defines 5 levels (adding Trivial and Strategic) with distinct entry points and diamond usage patterns. Feature 4 of the roadmap requires expanding the table to 5 levels with observable signals, recommended paths, tiebreaker rules at all 4 boundaries, and a top-down detection algorithm.

The core design tension is between compactness (agents need to scan the table quickly during passive routing) and completeness (the PRD requires enough detail for accurate classification). The current 3-row table works because it's brief. Adding 2 rows plus tiebreaker rules plus a detection algorithm could bloat the section if not structured carefully.

**Assumptions**

- The detection algorithm is consumed by agents during classification, not by users directly. Agent-oriented detail is acceptable as long as it's scannable.
- Existing Simple/Medium/Complex signal descriptions are adequate and don't need expansion -- they've worked in practice and the PRD says their semantics must not change.
- The /explore SKILL.md is the single home for the routing table. Other skills reference complexity in their own narrower ways (per-issue sizing in /plan, output complexity in /design) and don't need the 5-level model.

**Chosen: Compact Table with Detection Checklist**

Expand the existing routing table from 3 to 5 rows, keeping the same | Complexity | Signals | Recommended Path | format with concise comma-separated signal phrases (matching current style). Add a "Detection Algorithm" subsection immediately below the table containing an ordered checklist that runs top-down from Strategic to Trivial. Tiebreaker rules are embedded as boundary guidance within the checklist steps rather than in a separate table.

The concrete content:

**Routing Table (5 rows):**

| Complexity | Signals | Recommended Path |
|------------|---------|------------------|
| Trivial | Self-evident change, no issue needed, single file, no design decisions | `/work-on` directly (no issue) |
| Simple | Clear requirements, few files, one person, no competing approaches | `/work-on` or `/prd` then implement |
| Medium | Known approach, some integration risk, design decisions between viable options | `/design` then `/plan` |
| Complex | Multiple unknowns, shape unclear, can't state requirements or approach | `/explore` to discover first |
| Strategic | Project inception, multi-feature sequencing, thesis validation needed | VISION or `/roadmap` then per-feature pipeline |

**Detection Algorithm (ordered checklist):**

```
1. Does the request reference project direction, multi-feature sequencing,
   or thesis validation?
   YES -> Strategic
   Boundary: if it's about one feature within an existing project -> Complex

2. Can the user clearly state what to build AND how to build it?
   NO (either is unknown) -> Complex
   Boundary: if they know what but not how -> Medium

3. Are there design decisions where reasonable people could disagree
   on the approach?
   YES -> Medium
   Boundary: if you can list the decision questions now -> Medium;
   if too many unknowns to even frame questions -> Complex

4. Does a GitHub issue exist (or should one exist) with defined scope?
   YES -> Simple
   Boundary: if no design decisions and clear acceptance criteria -> Simple;
   if "done" is self-evident without criteria -> Trivial

5. Is the change self-evident and fire-and-forget?
   YES -> Trivial

6. Default -> Simple (create an issue and proceed)
```

**Rationale**

This approach preserves the proven compact table style that agents already scan successfully. The Simple, Medium, and Complex rows use the same signal language as the current table (satisfying the constraint that existing semantics don't change), with minor additions to sharpen boundary distinctions. The detection checklist runs top-down from Strategic because higher-complexity levels are less likely to be misclassified downward -- an agent seeing "project inception" signals won't mistake it for Simple, but a Trivial request might be over-classified if checked first.

Embedding tiebreaker rules as boundary notes within each checklist step keeps classification logic in one place. An agent reads the checklist sequentially, hits the first YES, and gets immediate guidance for the adjacent boundary. This is more natural than jumping between a signal table and a separate tiebreaker table.

The four PRD-mandated discriminator questions are preserved:
- Trivial vs Simple: Does the work need an issue / acceptance criteria?
- Simple vs Medium: Are there design decisions where reasonable people could disagree?
- Medium vs Complex: Can you list the decision questions right now?
- Complex vs Strategic: Single feature vs project direction / multi-feature?

**Alternatives Considered**

- **Expanded Table + Separate Tiebreaker Section**: Uses longer signal descriptions (1-2 sentences per cell) and a dedicated | Boundary | Discriminator | table, with the detection algorithm as a third subsection. Rejected because it creates three independent sections to maintain in sync, and the longer signal cells slow down agent scanning. The thoroughness is admirable but over-engineers the format for a table that's consulted during quick classification passes.

- **Two-Tier Presentation**: Keeps the main table compact and moves all detail (full signal tables, tiebreakers, detection algorithm) to a reference section at the bottom of SKILL.md. Rejected because agents may skip the reference section during classification, reducing accuracy. The indirection also makes it harder to verify that signals and tiebreakers stay consistent with the table -- maintenance burden shifts from verbosity to cross-location sync.

**Consequences**

The routing section in /explore SKILL.md grows from a 3-row table (~6 lines) to a 5-row table plus a detection checklist (~25 lines total). This is a moderate increase that stays within the section's existing scope. Agents get explicit guidance for all 5 levels and all 4 boundaries in a single sequential read.

The detection checklist becomes the authoritative classification procedure. If future levels are added (unlikely given the pipeline model is structurally complete), the checklist is the primary artifact to update. The table is the summary; the checklist is the specification.

Other skills (/plan, /design, /prd) don't need changes. Their existing per-issue or output complexity assessments remain orthogonal to the 5-level pipeline routing model.
<!-- decision:end -->
