# Lead: Doc format schemas and status lifecycles

## Findings

Six document types in shirabe define persistent frontmatter schemas and lifecycle states. The decision skill produces only ephemeral wip reports, not a committed doc format. Two additional artifact types (spike reports, competitive analyses) appear in tsukumogami skills but have no shirabe skill definitions; they are out of scope here.

Sources consulted:

- `skills/design/SKILL.md` and `skills/design/references/lifecycle.md`
- `skills/prd/SKILL.md` and `skills/prd/references/prd-format.md`
- `skills/vision/SKILL.md` and `skills/vision/references/vision-format.md`
- `skills/roadmap/SKILL.md` and `skills/roadmap/references/roadmap-format.md`
- `skills/plan/SKILL.md` and `skills/plan/references/quality/plan-doc-structure.md`
- `skills/decision/SKILL.md` and `skills/decision/references/phases/phase-6-synthesis.md`
- Live doc examples: `docs/designs/current/`, `docs/prds/`, `docs/roadmaps/`, `docs/plans/`

---

### Design Doc

**File pattern:** `docs/designs/DESIGN-<topic>.md` (active), `docs/designs/current/DESIGN-<topic>.md` (current), `docs/designs/archive/DESIGN-<topic>.md` (superseded)

| Field | Type | Required |
|-------|------|----------|
| `status` | string | Yes |
| `problem` | literal block scalar | Yes |
| `decision` | literal block scalar | Yes |
| `rationale` | literal block scalar | Yes |
| `upstream` | path string | No |
| `spawned_from.issue` | integer | No (child designs only) |
| `spawned_from.repo` | string | No (child designs only) |
| `spawned_from.parent_design` | path string | No (child designs only) |

**Valid statuses:** Proposed, Accepted, Planned, Current, Superseded

**Status lifecycle:**

```
Proposed --> Accepted --> Planned --> Current
                                  --> Superseded
```

- Proposed: created by /design or /explore
- Accepted: human approval
- Planned: /plan creates issues
- Current: all issues closed, file moves to `docs/designs/current/`
- Superseded: replaced by newer design, file moves to `docs/designs/archive/`

**Status transition rules:**
- Frontmatter `status` must match the body Status section
- /plan requires status = Accepted to proceed
- File directory changes on Current and Superseded transitions (via `scripts/transition-status.sh`)

**Required sections (9):** Status, Context and Problem Statement, Decision Drivers, Considered Options (at least 1 alternative per decision), Decision Outcome, Solution Architecture, Implementation Approach, Security Considerations (never empty), Consequences

**Context-aware sections (visibility/scope gated):**
- Market Context: strategic + private only
- Required Tactical Designs: strategic (public or private)
- Upstream Design Reference: tactical only, when upstream exists
- Implementation Issues: added by /plan after issue creation

**Upstream chain:** optional `upstream` links to a PRD. Child designs use `spawned_from` to reference parent design and source issue.

---

### PRD

**File pattern:** `docs/prds/PRD-<name>.md` (no directory movement)

| Field | Type | Required |
|-------|------|----------|
| `status` | string | Yes |
| `problem` | literal block scalar | Yes |
| `goals` | literal block scalar | Yes |
| `upstream` | path string | No |
| `source_issue` | integer | No |

**Valid statuses:** Draft, Accepted, In Progress, Done

**Status lifecycle:**

```
Draft --> Accepted --> In Progress --> Done
```

- Draft: created by /prd, may have Open Questions
- Accepted: human approval, Open Questions must be empty or removed
- In Progress: downstream workflow (/design, /plan, /work-on) started
- Done: all acceptance criteria met

**Status transition rules:**
- Draft -> Accepted: Open Questions section must be empty or removed; human must explicitly approve
- Accepted -> In Progress: downstream workflow started (typically /design reads the PRD)
- In Progress -> Done: all acceptance criteria met
- No Superseded state; replaced PRDs are marked Done with a note
- /design and /plan require status = Accepted or In Progress

**Required sections (7):** Status, Problem Statement, Goals, User Stories, Requirements (numbered R1, R2, ...), Acceptance Criteria (checkbox format), Out of Scope

**Optional sections:** Open Questions (Draft only), Known Limitations, Decisions and Trade-offs, Downstream Artifacts

**Content boundary:** No technical architecture, implementation approach, code, API specs, or security analysis.

**Upstream chain:** optional `upstream` links to a ROADMAP.

---

### VISION

**File pattern:** `docs/visions/VISION-<topic>.md` (active states), `docs/visions/sunset/VISION-<topic>.md` (Sunset)

| Field | Type | Required |
|-------|------|----------|
| `status` | string | Yes |
| `thesis` | literal block scalar | Yes |
| `scope` | `org` or `project` | Yes |
| `upstream` | path string | No (project-level only) |

**Valid statuses:** Draft, Accepted, Active, Sunset

**Status lifecycle:**

```
Draft --> Accepted --> Active --> Sunset
```

- Draft: under development, may have Open Questions
- Accepted: thesis endorsed, Open Questions resolved
- Active: downstream artifacts (PRDs, designs) reference this VISION
- Sunset: terminal; reason required (abandoned, pivoted, or invalidated)

**Status transition rules:**
- Draft -> Accepted: Open Questions empty or removed
- Accepted -> Active: at least one downstream artifact references this VISION
- Active -> Sunset: reason required; file moves to `docs/visions/sunset/`
- Forbidden: Draft -> Active, Draft -> Sunset (delete instead), Active -> Accepted/Draft, Sunset -> any
- One Active VISION per project at a time
- Thesis changes require creating a new VISION and sunsetting the old one

**Required sections (7):** Status, Thesis, Audience, Value Proposition, Org Fit, Success Criteria, Non-Goals

**Visibility-gated sections (private repos only):** Competitive Positioning, Resource Implications. These must NOT appear in public repos.

**Optional sections:** Open Questions (Draft only), Downstream Artifacts

**Section matrix by scope:** All 7 required sections apply for both org and project scope.

**Upstream chain:** project-level VISIONs may have `upstream` linking to an org-level VISION.

---

### Roadmap

**File pattern:** `docs/roadmaps/ROADMAP-<name>.md` (no directory movement)

| Field | Type | Required |
|-------|------|----------|
| `status` | string | Yes |
| `theme` | literal block scalar | Yes |
| `scope` | literal block scalar | Yes |
| `upstream` | path string | No |

**Valid statuses:** Draft, Active, Done

**Status lifecycle:**

```
Draft --> Active --> Done
```

- Draft: under development, feature list may change
- Active: feature list locked, execution in progress; human approval required
- Done: all features delivered or explicitly dropped; historical record

**Status transition rules:**
- Draft -> Active: feature list complete and sequencing justified; human must approve
- Active -> Done: every feature terminal (delivered or dropped with rationale)
- Forbidden: Done -> any, Active -> Draft
- Active roadmaps: Progress section and reserved sections (Implementation Issues, Dependency Graph) may be updated freely; Features and Sequencing Rationale are locked
- At least 2 features required

**Required sections (5 + 2 reserved):**
1. Status
2. Theme
3. Features (ordered, with per-feature structure: Needs annotation, Dependencies, Status)
4. Sequencing Rationale
5. Progress
6. Implementation Issues (reserved, populated by /plan)
7. Dependency Graph (reserved, populated by /plan)

**Per-feature format:** each feature lists `Needs` (optional `needs-*` annotation), `Dependencies`, and `Status`.

**Upstream chain:** optional `upstream` links to a VISION document.

---

### Plan

**File pattern:** `docs/plans/PLAN-<topic>.md` (active), `docs/plans/done/PLAN-<topic>.md` (Done)

| Field | Type | Required |
|-------|------|----------|
| `schema` | `plan/v1` | Yes |
| `status` | string | Yes |
| `execution_mode` | `single-pr` or `multi-pr` | Yes |
| `milestone` | string | Yes |
| `issue_count` | integer | Yes |
| `upstream` | path string | No |

**Valid statuses:** Draft, Active, Done

**Status lifecycle:**

```
Draft --> Active --> Done
```

- Draft: plan being written during /plan phases
- Active: implementation underway (multi-pr: GitHub issues created; single-pr: /work-on starts)
- Done: implementation complete; file moves to `docs/plans/done/`

**Coordinated lifecycle with design docs:**

| Design Doc | PLAN Doc | Trigger |
|------------|----------|---------|
| Accepted | (doesn't exist) | /design or /explore approval |
| Planned | Draft | /plan creates PLAN artifact |
| Planned | Active | /plan finishes |
| Current | Done | /complete-milestone |

**Required sections (7):** Status, Scope Summary, Decomposition Strategy, Issue Outlines (single-pr mode), Implementation Issues (multi-pr mode), Dependency Graph, Implementation Sequence

**Execution mode differences:**
- single-pr: Issue Outlines populated; Implementation Issues empty; PLAN stays Draft until /work-on starts; no GitHub artifacts
- multi-pr: Implementation Issues table populated with linked issues; PLAN transitions to Active when issues are created

**Decomposition strategies:** Walking skeleton, Horizontal, Feature-by-feature (roadmap input only)

**Upstream chain:** optional `upstream` links to source design doc, PRD, or roadmap.

---

### Decision

The decision skill does NOT produce a committed document with YAML frontmatter. It produces ephemeral wip artifacts (`wip/<prefix>_report.md`) that are consumed by /design to populate Considered Options sections, or used standalone and then cleaned up. There is no persistent `docs/decisions/` directory or stable file format equivalent to the other artifact types.

The decision output format is a Markdown block with `<!-- decision:start id="..." status="confirmed|assumed" -->` delimiters. Status values are `confirmed` (clear evidence, no assumptions) or `assumed` (contested evidence, --auto mode, or assumptions made).

---

### Summary Table

| Format | Required Frontmatter | Optional Frontmatter | Valid Statuses | Upstream Chain | Required Sections |
|--------|---------------------|---------------------|----------------|----------------|-------------------|
| Design | status, problem, decision, rationale | upstream, spawned_from.* | Proposed, Accepted, Planned, Current, Superseded | PRD (optional) | 9 |
| PRD | status, problem, goals | upstream, source_issue | Draft, Accepted, In Progress, Done | Roadmap (optional) | 7 |
| VISION | status, thesis, scope | upstream | Draft, Accepted, Active, Sunset | VISION (optional, project -> org) | 7 |
| Roadmap | status, theme, scope | upstream | Draft, Active, Done | VISION (optional) | 5 + 2 reserved |
| Plan | schema, status, execution_mode, milestone, issue_count | upstream | Draft, Active, Done | Design/PRD/Roadmap (optional) | 7 |
| Decision | (none — wip artifact only) | n/a | confirmed, assumed (block-level) | n/a | n/a |

---

### Traceability Chain

The full upstream chain, when all links are present:

```
VISION (org) --> VISION (project) --> Roadmap --> PRD --> Design --> Plan --> Issues/PRs
```

The `upstream` field is optional in every format. It is set at creation time by the creation workflow (e.g., `/design` Phase 0 sets upstream from the source PRD), but several gaps exist: `/prd` has the upstream field in its schema but the creation workflow historically did not populate it (fixed in PRD-artifact-traceability); `/roadmap` recently gained the upstream field via the same work.

---

### Validation Rules by Format (what each format spec mandates)

**Design:**
- All 4 frontmatter fields present
- Frontmatter status = body Status section
- 9 required sections present
- Security Considerations non-empty
- Considered Options has at least 1 real alternative per decision (not strawmen)
- /plan requires status = Accepted

**PRD:**
- 3 required frontmatter fields present
- Frontmatter status = body Status section
- 7 required sections present and in order
- Requirements numbered (R1, R2, ...)
- Acceptance Criteria in checkbox format
- Open Questions empty or removed before Accepted transition
- /design and /plan require status = Accepted or In Progress

**VISION:**
- 3 required frontmatter fields present
- Frontmatter status = body Status section
- 7 required sections present
- Open Questions empty or removed before Accepted transition
- Active status requires at least one Downstream Artifact entry
- Sunset status requires reason in Status section
- Competitive Positioning and Resource Implications absent in public repos

**Roadmap:**
- 3 required frontmatter fields present
- Frontmatter status = body Status section
- 5 required sections + 2 reserved sections present
- At least 2 features listed
- Reserved sections (Implementation Issues, Dependency Graph) present even if empty
- Downstream workflows require status = Active

**Plan:**
- 5 required frontmatter fields present (schema must be `plan/v1`)
- 7 required sections present
- Mermaid dependency graph uses `graph` not `flowchart`, edges outside subgraphs, class definitions at end
- Issue table uses `[#N: title](url)` format in Issue column with clickable dependency links
- Every issue row followed immediately by a description row
- `tracksDesign`/`tracksPlan` nodes must have child reference rows; others must not

---

## Implications

Several categories of validation are machine-checkable from these specs:

1. **Frontmatter completeness**: every format has a fixed set of required fields. A YAML parser can check field presence and reject documents missing `status`, `problem`/`thesis`/`theme`/`scope`, `goals`, `schema`, `execution_mode`, `milestone`, or `issue_count` depending on format.

2. **Status value validity**: each format has a closed set of valid status strings. A simple enum check catches typos and invalid states.

3. **Frontmatter/body status sync**: every format spec requires the frontmatter `status` to match the Status section heading or body text. This is checkable with a regex on the body Status section.

4. **Section presence**: required sections are named and ordered. A heading-level check can verify all required sections exist and are in the correct order.

5. **Format-specific structural rules**:
   - PRD: numbered requirements (R1, R2, ...) detectable by regex; checkbox ACs detectable
   - Roadmap: at least 2 features; reserved sections present even if empty
   - Plan: `schema: plan/v1` field; Mermaid `graph` not `flowchart`; issue table link format; description rows after every issue row; child reference row invariant
   - VISION (public): absence of Competitive Positioning and Resource Implications section headings

6. **Upstream field format**: when `upstream` is present, the value should be a valid relative path (or cross-repo reference format). Existence checking would require access to the referenced repo, but format checking is feasible.

7. **File location conventions**: file placement in the correct directory based on status (e.g., Current designs in `docs/designs/current/`, Superseded in `docs/designs/archive/`, Done plans in `docs/plans/done/`).

8. **Lifecycle preconditions** (harder, requires cross-file context): validating that a Plan's upstream design is Accepted, or that an Active VISION has at least one Downstream Artifact entry. These require reading referenced files.

The Plan format has the most machine-checkable structural invariants (Mermaid syntax rules, table link format, description row requirement, child reference row invariant), making it the strongest candidate for strict CI validation.

---

## Surprises

1. **Decision has no persistent doc format.** Despite being listed as a format in the exploration context, the decision skill produces only wip artifacts. There is no `docs/decisions/` directory and no frontmatter schema. If a CI system needs to validate decision artifacts, it has nothing to check in the main branch — the outputs are consumed by design docs or cleaned up.

2. **Plan has a `schema` field (`plan/v1`) that no other format uses.** This is a versioned schema identifier, implying the plan format may evolve. None of the other four persistent formats have an explicit schema version. This is the most CI-friendly format because `schema: plan/v1` gives validators a reliable hook.

3. **Roadmap reserved sections must be present even when empty.** The format spec is explicit: Implementation Issues and Dependency Graph sections must appear in every roadmap file, even at creation time when they contain only placeholder comments. This is a structural invariant that CI could check — but it's unusual to require empty sections by design.

4. **No global enforcement of the frontmatter/body status sync rule**, despite every format spec calling it out as critical ("divergence causes silent errors"). This is the most commonly cited validation rule across all formats, yet it requires parsing both YAML frontmatter and Markdown body to check. It's a prime candidate for CI automation precisely because it's tedious to check manually and consequential when wrong.

5. **VISION's visibility-gated sections create a binary check**: in public repos, two section headings (Competitive Positioning, Resource Implications) must be absent. This is a clear negative-presence check that CI can enforce without requiring human judgment.

6. **The `upstream` field convention changed mid-lifecycle**: PRD-artifact-traceability was a whole project dedicated to closing gaps where skills had the upstream field in their schema but never populated it. The field is optional in all formats, so CI can't require its presence — but it can validate format when present.

---

## Open Questions

1. **Decision output format for CI purposes.** If the exploration context includes decision records as a CI-validation target, there's nothing to check — the skill's outputs are ephemeral. Are tsukumogami decision records (ADRs) a separate format that's out of scope for shirabe CI?

2. **Cross-repo upstream references.** The format specs mention `references/cross-repo-references.md` (referenced in design, prd, vision, roadmap formats) for cross-repo upstream links. This file was not present in the shirabe references directories during this investigation. Its absence means the cross-repo format convention is documented somewhere else (possibly in the workspace). CI validators that check upstream field format need this spec.

3. **Status section body format.** The specs say frontmatter status must match the body Status section, but don't define the exact body format. Some docs use bare status words ("Accepted"), others add context ("Active — issues created and tracked under..."). How precisely does CI need to match them? Exact string vs. prefix vs. contains?

4. **Section order enforcement.** Specs list required sections in order, but it's unclear whether out-of-order sections should fail validation or just warn. The plan format is most explicit about order; the others list sections without strict ordering language.

5. **Roadmap feature count rule.** The spec requires at least 2 features. CI could count `### Feature N:` headings, but feature format is not rigidly delimited — features use H3 headings in a flat list. Are there edge cases (sub-features, grouped features) that would confuse a heading-count approach?

6. **Plan Mermaid validation depth.** The plan format has extensive Mermaid syntax rules (no `flowchart`, edges outside subgraphs, class definitions at end, node label max 40 chars). Full validation would require parsing Mermaid AST. What is the intended depth of CI validation here — surface-level (check for `flowchart` keyword) or structural?

7. **VISION Accepted -> Active precondition.** Transitioning to Active requires "at least one downstream artifact references this VISION." This check requires reading other files in the repo. Can CI enforce this at merge time, or only at transition time?

---

## Summary

Shirabe defines five persistent committed document formats (Design, PRD, VISION, Roadmap, Plan), each with YAML frontmatter schemas of 3-5 required fields, closed-status enumerations, and named required sections; the decision skill produces only ephemeral wip reports with no committed format. The most consistently machine-checkable rules across all formats are: required frontmatter field presence, status value validity, frontmatter/body status synchronization, and required section presence — with Plan having the richest additional structural invariants (schema versioning, Mermaid syntax rules, issue table link format, description row requirement). The biggest open question is whether the cross-repo upstream reference convention has a defined format that validators can check, since the referenced specification file was not found in the shirabe skills directories.
