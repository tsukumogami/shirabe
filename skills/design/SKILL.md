---
name: design
description: Create or review technical design documents. Use when deciding how to
  implement something — the skill fans out multiple approaches via advocate agents,
  presents trade-offs side by side, and produces a structured design doc with the
  chosen approach. Also use when reviewing, validating, or transitioning an existing
  design doc through its lifecycle (Proposed → Accepted → Planned → Current).
  Triggers on: "help me design X", "compare approaches for Y", "write a design doc
  for Z", review or approve a design doc, or status transitions on DESIGN-*.md files.
argument-hint: '<PRD path or topic>'
---

@.claude/shirabe-extensions/design.md
@.claude/shirabe-extensions/design.local.md

# Design Documents

Design documents capture HOW to build something -- the technical approach, trade-offs
considered, and architecture chosen. They complement PRDs (which capture WHAT and WHY)
and are the input for /plan (which breaks designs into issues).

**Writing style:** Read the `writing-style` skill for guidance.

## Structure

### Frontmatter

Every design doc begins with YAML frontmatter:

```yaml
---
status: Proposed
problem: |
  1 paragraph: what's broken or missing, who it affects, why now.
decision: |
  1 paragraph: chosen approach and key design elements.
rationale: |
  1 paragraph: why this approach, what trade-offs were weighed.
---
```

All four fields required. Use literal block scalars (`|`). Frontmatter status MUST
match the Status section in the body. The frontmatter provides a self-contained
summary so readers can understand the design without reading the full document, and
enables agent workflows to extract key info via simple regex.

**Suggested coverage** (guidance -- surface whatever is most relevant):
- **problem**: What's broken or missing? Who does it affect? Why act now?
- **decision**: What approach was chosen? Key design elements? How does it solve the problem?
- **rationale**: What trade-offs were weighed? Why were alternatives rejected?

**Optional fields:**
- `upstream: docs/prds/PRD-<name>.md` -- link to source PRD (set by /design Phase 0)
- `spawned_from` -- for child designs created from needs-design issues:
  ```yaml
  spawned_from:
    issue: <number>
    repo: <owner/repo>
    parent_design: <relative-path>
  ```

### Required Sections

Every design doc has these sections in order:

1. **Status** -- current lifecycle state
2. **Context and Problem Statement** -- the technical problem being solved
3. **Decision Drivers** -- constraints and priorities shaping the solution
4. **Considered Options** -- at least 1 alternative per decision
5. **Decision Outcome** -- what was chosen and why it works as a whole
6. **Solution Architecture** -- components, interfaces, data flow
7. **Implementation Approach** -- phased build plan
8. **Security Considerations** -- always include; see Security Considerations guidance below
9. **Consequences** -- positive, negative, mitigations

### Context-Aware Sections

Additional sections based on scope and visibility (detect from CLAUDE.md `## Repo Visibility:` and `## Planning Context:` fields):

| Section | Strategic + Private | Strategic + Public | Tactical |
|---------|--------------------|--------------------|----------|
| Market Context | Optional | No | No |
| Required Tactical Designs | Required | Required | No |
| Upstream Design Reference | No | No | If exists |

**Market Context** (after Context and Problem Statement): competitive landscape,
user demand, business opportunity. Only in strategic + private.

**Required Tactical Designs** (after Implementation Approach): table of tactical
designs needed in target repos. Each becomes a needs-design issue via /plan.

**Upstream Design Reference** (after Status): link to parent strategic design with
relevant sections noted.

Detect scope and visibility from CLAUDE.md:
- `## Repo Visibility: Private|Public`
- `## Planning Context: Strategic|Tactical` (or `## Default Scope:`)

## Lifecycle

```
Proposed --> Accepted --> Planned --> Current
                                      |
                              (or) Superseded
```

| Status | Directory | Transition |
|--------|-----------|------------|
| Proposed | `docs/designs/` | Created by /design or /explore |
| Accepted | `docs/designs/` | Human approval |
| Planned | `docs/designs/` | /plan creates issues |
| Current | `docs/designs/current/` | All issues closed |
| Superseded | `docs/designs/archive/` | Replaced by newer design |

### Status Transition Script

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/transition-status.sh <path> <target> [superseding-doc]
```

Handles status update, file movement (`git mv`), and supersession links.

### Label Lifecycle

If your project uses GitHub labels to track design status (e.g., `needs-design`,
`tracks-plan`), the label transitions for this skill are:

- **Design accepted (Phase 6):** Remove whatever `needs-*` label the source issue
  carries. The tracking label is applied by the planning skill, not here.
- **Child design superseded:** Revert the parent issue to its pre-design label
  state and update the parent design doc accordingly.

Define your project's specific label names in CLAUDE.md under
`## Label Vocabulary`.

## Validation Rules

### During /design or /explore (drafting)
- Frontmatter has all 4 fields (status, problem, decision, rationale)
- Frontmatter status matches body Status section
- All 9 required sections present
- Status is "Proposed"

### During /plan phase-1 (before creating issues)
- Status MUST be "Accepted" -- if not, STOP and inform user
- All required sections present

### During /plan phase-6 (after creating issues)
- Status becomes "Planned" (update frontmatter and body)
- "Implementation Issues" section added

## Quality Guidance

### Problem Statement
- States the problem, not a solution
- Explains why this matters now
- Scopes what's in and out

### Considered Options

Organized by decision question. Each gets context, then chosen approach, then
alternatives with rejection rationale. Alternatives must be genuinely viable (no
strawmen). See `references/quality/considered-options-structure.md`
for detailed templates and examples.

### Security Considerations

The Security Considerations section must not be empty. For each dimension that
applies to the design, document risks and mitigations. For dimensions that don't
apply, write a brief explicit justification ("Not applicable because this design
only produces markdown files and executes no external code").

Consumer projects should define domain-specific security dimensions in their
extension file (`@.claude/shirabe-extensions/design.md`).

### Common Pitfalls
- Too broad ("Improve the system") -- narrow to a specific capability
- Strawman options -- alternatives that exist only to justify the preferred choice
- Empty or bare "N/A" security section -- always justify non-applicability
- No consequences -- every decision has trade-offs

## File Location

Active: `docs/designs/DESIGN-<topic>.md` (kebab-case).
Current: `docs/designs/current/DESIGN-<topic>.md`.
Archived: `docs/designs/archive/DESIGN-<topic>.md`.

### Sections Added During Lifecycle

**Implementation Issues** -- added by /plan. Contains issues table and Mermaid
dependency diagram. See your project's diagram convention, or follow the format: an issues table with a Mermaid dependency diagram showing issue relationships.

## Repo Visibility

Before writing content, determine visibility from CLAUDE.md (`## Repo Visibility: Public|Private`):
- **Private repos:** Read `skills/private-content/SKILL.md`
- **Public repos:** Read `skills/public-content/SKILL.md`

Public designs must not reference private artifacts.

---

## Creating a Design Document

When invoked as `/design`, this skill drives a structured creation workflow that
investigates multiple approaches with equal depth before committing to one.

The core pattern is expansion-contraction: Phase 1 fans out advocate agents (one per
approach, arguing FOR it). Phase 2 presents all approaches side-by-side and the user
selects. Phases 3-6 deepen, formalize, review, and finalize the chosen approach.

### Input Modes

From `$ARGUMENTS`:
1. **Empty** -- ask the user what they want to design
2. **Path to accepted PRD** (matches `docs/prds/PRD-*.md` with status "Accepted") -- PRD mode
3. **Anything else** -- freeform topic

### Context Resolution

Detect visibility (Private/Public) from CLAUDE.md or repo path. Detect scope
(Strategic/Tactical) from `--strategic`/`--tactical` flags or CLAUDE.md default.

When the source issue is from a different repo, use `gh` commands to read content.
Visibility rule: public repos must not reference private issues.

### Workflow Phases

```
Phase 0: SETUP --> Phase 1: EXPAND --> Phase 2: CONVERGE --> Phase 3: INVESTIGATE --> Phase 4: ARCHITECT --> Phase 5: SECURITY --> Phase 6: FINALIZE
                        ^                    |
                        +--- loop back if ---+
                        approaches missing
```

| Phase | Purpose | Artifact |
|-------|---------|----------|
| 0 | Branch setup, PRD extraction or freeform scoping | Design doc skeleton, wip/ summary |
| 1 | Fan out advocate agents, one per approach (cap 5) | wip/ research per advocate |
| 2 | Side-by-side comparison, agent recommends, user approves | Considered Options, Decision Outcome |
| 3 | Research agents examine chosen approach in depth | wip/ research per area |
| 4 | Synthesize findings into architecture sections | Solution Architecture, Consequences |
| 5 | Mandatory security review (3 outcomes) | Security Considerations |
| 6 | Review, strawman check, frontmatter, commit, PR | Complete design doc |

### Resume Logic

```
Design doc status "Accepted"                    → Offer to revise or start fresh
Design doc status "Proposed"                    → Offer to continue
wip/research/design_<topic>_phase5_security.md  → Resume at Phase 6
Design doc has Solution Architecture            → Resume at Phase 5
wip/research/design_<topic>_phase3_*.md exist   → Resume at Phase 4
Design doc has Considered Options               → Resume at Phase 3
wip/research/design_<topic>_phase1_*.md exist   → Resume at Phase 2
wip/design_<topic>_summary.md exists            → Resume at Phase 1
On topic branch, no artifacts                   → Resume at Phase 0
```

### Critical Requirements

- **No premature commitment**: no approach chosen until the user approves the agent's recommendation in Phase 2
- **Equal-depth investigation**: every advocate gets the same context and effort
- **Security is mandatory**: Phase 5 always runs; output may be N/A but the review is not optional
- **Strawman check**: Phase 6 validates rejected alternatives have genuine depth
- **Topic-scoped artifacts**: all wip/ files include `<topic>` in their path

### Output

Final artifact: `docs/designs/DESIGN-<topic>.md` with status "Proposed".

After completion, present the design summary and offer next steps.

Run a complexity assessment based on the design's implementation scope:

| Criterion | Simple | Complex |
|-----------|--------|---------|
| Files to modify | 1-3 | 4+ |
| New tests | Updates only | New test infrastructure |
| API changes | None | Surface changes |
| Cross-package | No | Yes |

Present an AskUserQuestion with the assessment and options:
- If Simple: "Plan (Recommended)" / "Approve only"
- If Complex: "Plan (Recommended)" / "Approve only"

**"Plan":** suggest running `/plan <design-doc-path>` to create implementation issues.
The PR should NOT be merged yet — `/plan` will add an "Implementation Issues" section.

**"Approve only":** stop here; the user handles implementation manually.

### Execution

Execute phases sequentially by reading the corresponding phase file:

0. **Setup + Context**
   - PRD mode: `references/phases/phase-0-setup-prd.md`
   - Freeform: `references/phases/phase-0-setup-freeform.md`
1. **Approach Discovery**: `references/phases/phase-1-approach-discovery.md`
2. **Present Approaches**: `references/phases/phase-2-present-approaches.md`
3. **Deep Investigation**: `references/phases/phase-3-deep-investigation.md`
4. **Architecture**: `references/phases/phase-4-architecture.md`
5. **Security**: `references/phases/phase-5-security.md`
6. **Final Review**: `references/phases/phase-6-final-review.md`

---

## Reference Files

| File | When to load |
|------|-------------|
| `references/phases/phase-0-setup-prd.md` | Phase 0, PRD input mode |
| `references/phases/phase-0-setup-freeform.md` | Phase 0, freeform input mode |
| `references/phases/phase-1-approach-discovery.md` | Phase 1 |
| `references/phases/phase-2-present-approaches.md` | Phase 2 |
| `references/phases/phase-3-deep-investigation.md` | Phase 3 |
| `references/phases/phase-4-architecture.md` | Phase 4 |
| `references/phases/phase-5-security.md` | Phase 5 |
| `references/phases/phase-6-final-review.md` | Phase 6 |
| `references/quality/considered-options-structure.md` | When writing Considered Options |
| `${CLAUDE_PLUGIN_ROOT}/scripts/transition-status.sh` | Status transitions with file movement |
