# Lead: Cross-pipeline traceability -- how artifacts reference each other

## Findings

### Current Reference Patterns by Artifact Type

Each artifact type has its own mechanism for pointing upstream and downstream. Here's what exists today.

**VISION (proposed, not yet implemented)**
- Upstream: `upstream` frontmatter field (org-level VISION path, or none for root)
- Downstream: "Downstream Artifacts" section with links to PRDs and Roadmaps
- Direction: Bidirectional by convention (upstream in frontmatter, downstream in body section)

**Roadmap**
- Upstream: No explicit upstream field in frontmatter. The Theme section provides narrative context but doesn't link to a parent artifact.
- Downstream: Features section references downstream artifacts (PRDs, design docs) when they exist. `/plan` decomposes features into issues with `needs-*` labels.
- Direction: Downstream only. No formal mechanism to trace a Roadmap back to a VISION.

**PRD**
- Upstream: `upstream` frontmatter field (path to parent artifact, e.g., `docs/roadmaps/ROADMAP-<name>.md`). Also `source_issue` for GitHub issue that triggered it.
- Downstream: "Downstream Artifacts" optional section with links to design docs, plans, issues, PRs.
- Direction: Bidirectional. `upstream` points up, "Downstream Artifacts" points down.

**Design Doc**
- Upstream: "Upstream Design Reference" section (tactical designs referencing strategic designs). `spawned_from` frontmatter field (child designs linking to parent issue and design doc). No general-purpose `upstream` frontmatter field pointing to PRD.
- Downstream: "Implementation Issues" section (table + Mermaid diagram). "Required Tactical Designs" section (strategic designs listing child designs needed).
- Direction: Partially bidirectional. `spawned_from` links child to parent. Strategic designs list required tactical designs. But there's no standard field linking a design doc back to its source PRD.

**Plan (PLAN-*.md)**
- Upstream: `upstream` frontmatter field (path to design doc, PRD, or roadmap).
- Downstream: Implementation Issues table with GitHub issue links and dependency graph.
- Direction: Bidirectional. `upstream` points to source artifact, issue table points to implementation.

**GitHub Issues**
- Upstream: Issue body references design doc or plan via prose links. `needs-*` labels indicate what upstream artifact is needed. `tracks-plan`/`tracks-design` labels indicate a child artifact exists.
- Downstream: PRs reference issues via `Ref #N` or `Fixes #N`.
- Direction: Loosely bidirectional via labels and PR references.

**Pull Requests**
- Upstream: `Ref #N` or `Fixes #N` in PR body links to issues. Design doc PRs use `Ref #N` (not Fixes) to avoid premature issue closure.
- Downstream: None (terminal artifact in the pipeline).
- Direction: Upstream only.

### Reference Mechanism Summary

| Artifact | Upstream Mechanism | Downstream Mechanism | Bidirectional? |
|----------|-------------------|---------------------|----------------|
| VISION (proposed) | `upstream` frontmatter | Downstream Artifacts section | Yes |
| Roadmap | None | Features list downstream refs | Downstream only |
| PRD | `upstream` frontmatter + `source_issue` | Downstream Artifacts section | Yes |
| Design Doc | `spawned_from` frontmatter, Upstream Design Reference section | Implementation Issues, Required Tactical Designs | Partial |
| Plan | `upstream` frontmatter | Implementation Issues table | Yes |
| GitHub Issue | Body links, labels | PR references | Loose |
| Pull Request | `Ref`/`Fixes` in body | None | Upstream only |

### Traceability Gaps

**Gap 1: Roadmap has no upstream field.** Roadmap frontmatter has `status`, `theme`, `scope` but no `upstream` field. If a VISION doc spawns a Roadmap, the Roadmap can't formally point back. This breaks the chain: VISION -> ? -> PRD (the PRD's `upstream` can point to a Roadmap, but the Roadmap can't point to the VISION).

**Gap 2: Design Doc has no standard upstream field to PRD.** The design doc skill defines `spawned_from` (for child designs from `needs-design` issues) and "Upstream Design Reference" (for tactical designs referencing strategic designs), but neither mechanism handles the common case of a design doc created from an Accepted PRD. There's no `upstream` frontmatter field equivalent to what PRD and Plan have. The lifecycle description mentions `/design <PRD-path>` reads an Accepted PRD, but the resulting design doc doesn't carry a formal back-link.

**Gap 3: No standardized cross-repo reference format.** The `upstream` field uses relative file paths (e.g., `docs/roadmaps/ROADMAP-<name>.md`). This works within a single repo but breaks when the upstream artifact lives in a different repo. There's no convention for cross-repo references in frontmatter.

**Gap 4: Visibility rule prevents some references.** The design doc skill states: "a public tactical design cannot reference a private strategic design." This is correct for public-facing content, but it means the full traceability chain is invisible in public repos when the VISION lives in a private repo. There's no mechanism for a "redacted reference" -- something that says "this artifact has private upstream context" without exposing the private content.

**Gap 5: Downstream Artifacts sections are manually maintained.** PRDs and VISIONs have optional "Downstream Artifacts" sections, but nothing in the workflow automation populates them. When `/design` reads an Accepted PRD and produces a design doc, the PRD's Downstream Artifacts section isn't updated. The back-links exist in theory but not in practice.

**Gap 6: Issue-to-artifact traceability relies on conventions, not structure.** GitHub issues reference their source design doc or plan through prose in the body, not through structured metadata. There's no label or field that says "this issue was created from PLAN-X.md" in a machine-readable way.

### Cross-Repo Reference Problem

The workspace has this repo topology:
- `vision` (private): strategic planning, would contain org-level and project-level VISIONs
- `tsuku`, `koto`, `niwa`, `shirabe` (public): implementation repos

A typical chain might be:
1. `vision/docs/visions/VISION-koto.md` (private) -- why koto should exist
2. `koto/docs/roadmaps/ROADMAP-orchestration.md` (public) -- feature sequencing
3. `koto/docs/prds/PRD-resumable-workflows.md` (public) -- requirements for one feature
4. `koto/docs/designs/DESIGN-state-machine.md` (public) -- technical architecture
5. `koto/docs/plans/PLAN-state-machine.md` (public) -- issue decomposition
6. GitHub issues in koto repo -- implementation work
7. Pull requests in koto repo -- code changes

The visibility rule creates a hard boundary between steps 1 and 2. A public Roadmap cannot include a file path to a private VISION doc. Three approaches:

**Approach A: Opaque upstream reference.** The Roadmap's `upstream` field contains a token like `upstream: private:vision/VISION-koto` that signals "there is an upstream VISION doc in a private repo" without exposing the content or exact path. Agents in the private context can resolve the token; public readers see only that private context exists.

**Approach B: Visibility-stripped summary.** The VISION doc includes a "Public Summary" section that's safe to reference. The Roadmap's `upstream` field points to a public summary artifact that carries the non-sensitive portions of the VISION (thesis, audience, value proposition) without competitive analysis or internal strategy.

**Approach C: No cross-visibility references.** Accept that the chain breaks at the visibility boundary. Private VISIONs have their own Downstream Artifacts section pointing to public repos, but public artifacts never reference private ones. Traceability from public artifacts goes only as far back as the first public ancestor (the Roadmap or PRD).

### Proposed Traceability Model

**Principle: Every artifact should carry a machine-readable `upstream` field and a human-maintained `downstream` section.**

**1. Add `upstream` to Roadmap frontmatter:**
```yaml
---
status: Active
upstream: docs/visions/VISION-<name>.md  # optional
theme: |
  ...
scope: |
  ...
---
```

**2. Add `upstream` to Design Doc frontmatter:**
```yaml
---
status: Proposed
upstream: docs/prds/PRD-<name>.md  # optional, path to source PRD
spawned_from:  # existing, for child designs only
  issue: <number>
  repo: <owner/repo>
  parent_design: <path>
problem: |
  ...
---
```

The `upstream` field handles the PRD-to-design-doc link. `spawned_from` continues to handle the parent-child design relationship. Both can coexist on a child design that also traces back to a PRD.

**3. Standardize cross-repo reference format:**
```
upstream: <owner/repo>:<path>         # same visibility
upstream: private:<owner/repo>:<path> # cross-visibility (private upstream)
```

The `private:` prefix signals that the upstream artifact is in a private repo. Agents in the private context resolve it. Public readers and public documentation see only that private upstream context exists -- they don't follow the link.

**4. Automate Downstream Artifacts updates.** When a workflow creates a downstream artifact (e.g., `/design` produces a design doc from a PRD), the workflow should append a link to the source artifact's Downstream Artifacts section. This closes the loop: the upstream's frontmatter `upstream` field is set by the creator, and the downstream's body section is updated by the workflow.

**5. Structured issue metadata.** When `/plan` creates issues, include a structured header in the issue body:
```markdown
<!-- source: docs/plans/PLAN-<topic>.md -->
<!-- design: docs/designs/DESIGN-<topic>.md -->
```

HTML comments are invisible to readers but machine-parseable for traceability queries.

### Full Traceability Chain

```
VISION-koto.md
  upstream: (none, or org-level VISION)
  downstream: [ROADMAP-orchestration.md, PRD-basic-workflow.md]

ROADMAP-orchestration.md
  upstream: private:niwaw/vision:docs/visions/VISION-koto.md
  downstream: [PRD-resumable-workflows.md, PRD-parallel-execution.md]

PRD-resumable-workflows.md
  upstream: docs/roadmaps/ROADMAP-orchestration.md
  source_issue: 42
  downstream: [DESIGN-state-machine.md]

DESIGN-state-machine.md
  upstream: docs/prds/PRD-resumable-workflows.md
  downstream: [PLAN-state-machine.md]

PLAN-state-machine.md
  upstream: docs/designs/DESIGN-state-machine.md
  downstream: [#101, #102, #103]

Issue #101
  <!-- source: docs/plans/PLAN-state-machine.md -->
  downstream: PR #150

PR #150
  Fixes #101
```

At every level, you can traverse up via `upstream` and down via Downstream Artifacts / Implementation Issues. The chain is complete from VISION to PR.

### Verification: Can you trace from a PR back to a VISION?

Starting from PR #150:
1. PR body says `Fixes #101` -> Issue #101
2. Issue body has `<!-- source: docs/plans/PLAN-state-machine.md -->` -> Plan
3. Plan frontmatter has `upstream: docs/designs/DESIGN-state-machine.md` -> Design
4. Design frontmatter has `upstream: docs/prds/PRD-resumable-workflows.md` -> PRD
5. PRD frontmatter has `upstream: docs/roadmaps/ROADMAP-orchestration.md` -> Roadmap
6. Roadmap frontmatter has `upstream: private:niwaw/vision:docs/visions/VISION-koto.md` -> VISION (private)

Full chain traversable in 6 hops. Each hop uses a machine-readable field (frontmatter `upstream`, HTML comment, or PR body reference).

## Implications

1. **Two gaps need closing before VISION ships: Roadmap `upstream` and Design Doc `upstream`.** Without these, the traceability chain has holes that VISION can't bridge. These are small schema additions to existing artifact types.

2. **Cross-repo references need a convention, not a tool.** The `owner/repo:path` format is parseable and unambiguous. The `private:` prefix handles the visibility boundary without exposing private content. No new tooling required -- just a documented convention and agent awareness.

3. **Downstream Artifacts automation is the highest-impact improvement.** Currently, downstream links are manually maintained and often missing. If workflows like `/design`, `/plan`, and `/work-on` automatically update the source artifact's Downstream Artifacts section, traceability becomes reliable without human discipline.

4. **The visibility boundary is a feature, not a bug.** Public artifacts should not expose private strategy. The `private:` prefix gives agents enough to follow the chain when they have access, while keeping public-facing content clean.

5. **Structured issue metadata (`<!-- source: ... -->`) is low-cost, high-value.** HTML comments in issue bodies are invisible to human readers but make issue-to-artifact traceability machine-readable. This replaces the current convention of prose links that vary in format.

## Surprises

1. **Design docs lack an `upstream` field for PRDs.** Given that PRDs and Plans both have `upstream` frontmatter, the design doc's omission is inconsistent. The `spawned_from` field handles child designs, but the primary PRD-to-design-doc link has no structured representation.

2. **Roadmaps are the weakest link in traceability.** They reference downstream artifacts in feature descriptions but have no upstream field and no Downstream Artifacts section. As the bridge between VISION and PRD, they need both.

3. **The existing `upstream` field is already cross-artifact but not cross-repo.** The PRD `upstream` field can point to a Roadmap, and the Plan `upstream` field can point to a Design Doc or PRD. The format is path-based and works within a repo. Extending it to cross-repo references is a natural evolution, not a redesign.

## Summary

Current traceability is one-directional at most levels: artifacts point upstream via frontmatter but downstream links are manually maintained and often missing. Two structural gaps (Roadmap and Design Doc lack `upstream` fields) break the chain. Cross-repo references need a `owner/repo:path` convention with a `private:` prefix for visibility boundaries. The highest-impact fix is automating Downstream Artifacts updates when workflows create new artifacts.
