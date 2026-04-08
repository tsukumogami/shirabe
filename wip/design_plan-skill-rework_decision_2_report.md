<!-- decision:start id="roadmap-table-format" status="assumed" -->
### Decision: Enriched roadmap table format

**Context**
When /plan enriches a roadmap, it populates the Implementation Issues section that /roadmap left as an empty placeholder. Two documented formats exist: the roadmap reserved template (`Feature | Issues | Status` from roadmap-format.md) and the PLAN doc format (`Issue | Dependencies | Complexity` with description rows from plan-doc-structure.md). The only existing enriched roadmap (ROADMAP-koto-adoption.md) uses neither format exactly, instead using `Issue | Phase | Dependencies | Label`.

The enriched roadmap table is purely for human consumption. No downstream parser reads it -- parsePlanDoc only processes PLAN artifacts, and /implement never touches roadmaps. The table's audience is someone navigating the roadmap to understand which issues track which features and what type of work each feature needs next.

Roadmap decomposition uses feature-by-feature planning, which creates a 1:1 mapping between features and planning issues. All planning issues carry `simple` complexity. Dependencies between features are already visualized in the Mermaid graph below the table.

**Assumptions**
- The 1:1 feature-to-issue mapping holds for all roadmap enrichments. If a future roadmap produces multiple issues per feature, this format would need rows grouped by feature or a feature column added back.
- The needs-* label is the most useful per-issue metadata for roadmap readers. If readers need different metadata (e.g., assignee, target date), the columns would need revision.

**Chosen: Roadmap reserved format with needs-label in Status**
Use the roadmap-format.md template as-is: `Feature | Issues | Status`. The Feature column carries the feature name (matching the Features section headings), Issues carries the GitHub issue link, and Status carries the needs-* label or completion state. This keeps the documented contract intact while encoding the label information readers need.

When a feature has no needs-* label (ready for direct implementation), Status shows the issue's GitHub state (e.g., "Open", "Done"). When a feature has a needs-* label, Status shows `needs-design`, `needs-prd`, `needs-spike`, or `needs-decision`.

Example:
```markdown
| Feature | Issues | Status |
|---------|--------|--------|
| review-plan fast-path | [#49](url) | needs-design |
| decision (degraded) | [#50](url) | needs-design |
| file koto requests | ~~[#51](url)~~ | Done |
```

**Rationale**
The reserved format already exists in roadmap-format.md and the template is what /roadmap stamps into every roadmap file. Using it avoids introducing a third format that diverges from both documented specs. The Feature column, while often similar to the issue title, provides explicit traceability to the Features section headings -- the reader can scan the Feature column and match to the Feature subsections above.

The PLAN doc format's Dependencies and Complexity columns carry no useful information in roadmap context: dependencies are in the Mermaid graph, and complexity is uniformly "simple" for planning issues. Adding those columns would be noise. A custom "roadmap-native" format (dropping Feature, adding Label) would work but breaks the documented contract in roadmap-format.md for marginal gain -- the Status column can carry the label information without adding a dedicated column.

**Alternatives Considered**
- **PLAN doc format (Issue | Dependencies | Complexity)**: Consistent with PLAN docs elsewhere, but two of three columns carry no differentiating information for roadmap planning issues. Dependencies duplicate the Mermaid graph; complexity is always "simple". Rejected for low information density.
- **Roadmap-native format (Issue | Label | Status)**: Every column carries useful, varying data. But it diverges from the documented roadmap-format.md contract and drops the Feature column that provides explicit traceability to the Features section. Rejected because the reserved format achieves the same goals without breaking the documented spec.
- **Extended reserved format (Feature | Issues | Label | Status)**: Adds a dedicated Label column to the reserved template. Four columns is wider than needed -- the Status column can serve double duty since the needs-* label IS the most relevant status information.

**Consequences**
The roadmap-format.md template works as-is with no changes. Phase 7 populates the reserved section using the documented columns. The Status column carries either a needs-* label or a completion state, which is a slight overloading but matches how readers naturally think about "status." If needs change and multi-issue features emerge, the Feature/Issues separation is already there to handle grouping. The existing ROADMAP-koto-adoption.md would need updating to match (it uses a non-standard format), but that's a separate cleanup.
<!-- decision:end -->
