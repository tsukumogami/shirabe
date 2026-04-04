---
name: vision
description: >-
  Structured workflow for creating Vision documents that capture project thesis,
  strategic justification, and org fit. Use when defining WHY a project should
  exist before writing requirements. Triggers on "why should we build X",
  "define the vision for Y", "justify project Z", "I need a vision doc", or any
  request to articulate project thesis or strategic positioning. Do NOT use for
  feature requirements (/prd), technical architecture (/design), or open-ended
  exploration (/explore). Drives a multi-phase workflow: conversational scoping,
  parallel research agents, structured drafting, and jury review.
argument-hint: '<project or org topic>'
---

@.claude/shirabe-extensions/vision.md
@.claude/shirabe-extensions/vision.local.md

# Vision Documents

Vision documents capture WHY a project or organization should exist -- the core
thesis, audience, value proposition, org fit, and success criteria. They sit
upstream of PRDs (which capture WHAT to build) and are the strategic foundation
that justifies writing requirements in the first place.

**Writing style:** Read `skills/writing-style/SKILL.md` for guidance.

## Vision Format

### Frontmatter

Every vision document begins with YAML frontmatter:

```yaml
---
status: Draft
thesis: |
  1 paragraph: the core belief about why this project/org should exist.
scope: org | project
upstream: docs/visions/VISION-<parent>.md  # optional, project-level only
---
```

Required fields: `status`, `thesis`, `scope`. Optional: `upstream`.

- **status** -- lifecycle state (Draft, Accepted, Active, Sunset)
- **thesis** -- the core bet, matching the Thesis section body
- **scope** -- `org` (why does this org exist) or `project` (why does this
  project exist within the org)
- **upstream** -- path to parent VISION when a project-level doc derives from
  an org-level one. Project-level only; omit for org-level.

Frontmatter status must match the Status section in the body -- agent workflows
parse frontmatter to determine lifecycle state, so divergence causes silent
errors.

### Required Sections (in order)

1. **Status** -- current lifecycle state and any transition context
2. **Thesis** -- the core bet, written as a hypothesis ("We believe [audience]
   needs [capability] because [insight]"), not a problem statement
3. **Audience** -- who benefits, describing their current situation
4. **Value Proposition** -- category of value delivered, not features
5. **Org Fit** -- how this relates to the broader portfolio
6. **Success Criteria** -- project-level outcomes (adoption, ecosystem, quality
   signals), not feature acceptance criteria
7. **Non-Goals** -- what this project deliberately is NOT, each with reasoning

### Optional Sections

- **Open Questions** -- Draft status only. Must be resolved (section removed or
  emptied) before transitioning to Accepted.
- **Downstream Artifacts** -- added when downstream work (PRDs, designs, plans)
  starts. Lists paths to artifacts that depend on this VISION.

### Visibility-Gated Sections (private repos only)

- **Competitive Positioning** -- market alternatives and differentiation
- **Resource Implications** -- investment required and opportunity cost

These sections must NOT appear in public repos. If present in a public repo
during validation, flag as an error.

### Section Matrix

| Section | Public | Private | Org | Project |
|---------|--------|---------|-----|---------|
| Status | Required | Required | Required | Required |
| Thesis | Required | Required | Required | Required |
| Audience | Required | Required | Required | Required |
| Value Proposition | Required | Required | Required | Required |
| Competitive Positioning | -- | Optional | Optional | Optional |
| Resource Implications | -- | Optional | Optional | Optional |
| Org Fit | Required | Required | Required | Required |
| Success Criteria | Required | Required | Required | Required |
| Non-Goals | Required | Required | Required | Required |
| Open Questions | Draft only | Draft only | Draft only | Draft only |
| Downstream Artifacts | When exists | When exists | When exists | When exists |

### Quality Guidance

Each required section has specific quality criteria. Reviewers and authors
should check these during drafting and validation.

- **Thesis**: Must be a hypothesis, not a problem statement. Format: "We believe
  [audience] needs [capability] because [insight]." If it reads like "The problem
  is..." it's wrong. The thesis is a bet -- it can be invalidated.
- **Audience**: Describe the audience's current situation, not just a label.
  "Backend engineers at mid-size companies managing 10+ microservices" is better
  than "developers." Include what they do today and what friction they face.
- **Value Proposition**: State the category of value, not a feature list. "Reduce
  the operational burden of managing developer tool installations" not "provides
  a CLI with install, update, and remove commands." Think one level above features.
- **Org Fit**: Explain why HERE and not elsewhere. What makes this org/team the
  right one to pursue this? What existing capabilities or positioning does it
  build on? A VISION without org fit is just an idea.
- **Success Criteria**: Project-level outcomes, not feature acceptance criteria.
  Adoption rates, ecosystem signals, quality indicators -- things that validate
  the thesis. "10 recipes contributed by external users within 6 months" not
  "install command exits with code 0."
- **Non-Goals**: About identity, not scope. Each non-goal should explain WHY
  this project won't do something, tying back to the thesis. "Not a system
  package manager -- we target developer tools specifically because system
  packages have different reliability and permission requirements" not just
  "not a system package manager."
- **Competitive Positioning** (private only): Name alternatives and explain
  differentiation. Reference but don't duplicate full competitive analysis
  artifacts.
- **Resource Implications** (private only): Investment and opportunity cost.
  What are we NOT doing by pursuing this?

### Content Boundaries

VISION does NOT contain:

- **Feature requirements or user stories** -- belongs in a PRD
- **Feature sequencing or timelines** -- belongs in a Roadmap
- **Technical architecture decisions** -- belongs in a Design Doc
- **Implementation tasks** -- belongs in a Plan
- **Full competitive analysis** -- separate artifact; VISION can reference
  positioning but not duplicate analysis

If a VISION draft starts accumulating feature lists, user stories, or technical
decisions, those belong in downstream artifacts. Extract them into Open Questions
or Downstream Artifacts pointers.

## Lifecycle

### States

| State | Meaning |
|-------|---------|
| Draft | Under development. May have Open Questions. |
| Accepted | Thesis endorsed. Open Questions resolved. Ready for downstream work. |
| Active | Downstream artifacts (PRDs, designs) reference this VISION. |
| Sunset | Terminated -- abandoned, pivoted, or invalidated. Terminal state. |

### Transitions

All transitions are executed by `scripts/transition-status.sh`. The script
validates preconditions, updates status in both frontmatter and body, and
moves files between directories when status changes.

| Transition | Preconditions | Directory Movement |
|-----------|---------------|-------------------|
| Draft -> Accepted | Open Questions section empty or removed | None (stays in `docs/visions/`) |
| Accepted -> Active | At least one downstream artifact references this VISION | None (stays in `docs/visions/`) |
| Active -> Sunset | Reason provided (abandoned, pivoted, or invalidated) | Moves to `docs/visions/sunset/` |

**Script interface:**

```
scripts/transition-status.sh <vision-doc-path> <target-status> [superseding-doc]
```

When a superseding doc is provided, the script records `superseded_by` in
frontmatter and notes the successor in the Status section body.

**Forbidden transitions:**

- Draft -> Active (must accept first)
- Draft -> Sunset (delete instead -- unendorsed drafts don't need a paper trail)
- Active -> Accepted or Draft (regression)
- Sunset -> any (terminal, irreversible)

### Validation Rules

- Frontmatter `status` must match the body Status section
- Draft: all 7 required sections present; Open Questions allowed
- Accepted: all 7 required sections present; Open Questions resolved (removed
  or empty)
- Active: same as Accepted, plus at least one Downstream Artifact entry
- Sunset: Status section includes reason (abandoned, pivoted, or invalidated)

### Edit Rules

Active VISIONs can be edited in place for everything except the Thesis. A
Thesis change signals a project pivot -- create a new VISION and Sunset the
old one via the script with the superseding doc argument.

One Active VISION per project at a time.

### Directory Mapping

| Status | Directory |
|--------|-----------|
| Draft, Accepted, Active | `docs/visions/` |
| Sunset | `docs/visions/sunset/` |

## File Location

Vision documents live at `docs/visions/VISION-<topic>.md` (kebab-case). No
directory movement until Sunset, which moves files to `docs/visions/sunset/`.
Stable paths keep cross-references durable and git blame readable.

## Repo Visibility

Before writing content, detect visibility from CLAUDE.md
(`## Repo Visibility: Public|Private`). If not found, infer from repo path
(`private/` -> Private, `public/` -> Public; default to Private). Load the
appropriate content governance skill:

- **Private repos:** Read `skills/private-content/SKILL.md`
- **Public repos:** Read `skills/public-content/SKILL.md`

Public VISIONs must not include Competitive Positioning or Resource Implications
sections, and must not reference private artifacts.

---

## Creating a Vision Document

When invoked as `/vision`, this skill drives a structured creation workflow that
scopes the thesis conversationally, fans out research agents, drafts the VISION
with section-level review, and validates through jury review.

Unlike an explore workflow (which is open-ended and can produce any artifact type),
/vision always produces a VISION document. Use /vision when you know you need
strategic justification. Use an explore workflow when you don't know what artifact
type you need yet.

### Input Modes

From `$ARGUMENTS`:

1. **Empty** -- ask the user what project or org they want to define a vision for
2. **Path to existing VISION** with lifecycle verb (`accept`, `activate`,
   `sunset`) -- execute the lifecycle transition via `scripts/transition-status.sh`
3. **Anything else** -- use as the starting topic for Phase 1 scoping

### Standalone Entry and Handoff Detection

/vision works both standalone and as a handoff target from /explore.

On startup, check for `wip/vision_<topic>_scope.md`. If it exists, an /explore
session already ran Phase 5 and wrote the handoff artifact with synthesized
findings. Skip Phase 1 (scoping) and proceed directly to Phase 2 (discover) --
the scope file provides the problem statement and research leads.

If no handoff artifact exists, start from Phase 1.

### Context Resolution

**Execution mode:** check `$ARGUMENTS` for `--auto` or `--interactive` flags,
then CLAUDE.md `## Execution Mode:` header (default: `interactive`). Also
parse `--max-rounds=N` (default: 2 for vision's discover loop). In --auto mode,
follow `references/decision-protocol.md` at all decision points. Create
`wip/vision_<topic>_decisions.md` to track decisions.

Detect visibility (Private/Public) from CLAUDE.md or repo path. Infer from
`private/` or `public/` in path if not explicit. Default to Private if
unknown -- restricting is easier to undo than oversharing.

Log: `Drafting vision with [Private|Public] visibility...`

### Workflow Phases

```
Phase 0: SETUP --> Phase 1: SCOPE --> Phase 2: DISCOVER --> Phase 3: DRAFT --> Phase 4: VALIDATE
(branch)          (conversational)   (agents fan out)     (iterative)        (jury review)
                       |                                       ^
                       |                                       |
                       +--- may loop back to DISCOVER or DRAFT-+
```

| Phase | Purpose | Artifact |
|-------|---------|----------|
| 0. Setup | Create feature branch, detect visibility | On topic branch |
| 1. Scope | Conversational scoping (or skip if handoff exists) | Problem statement + research leads |
| 2. Discover | Parallel research agents investigate leads | Research findings in wip/ |
| 3. Draft | Produce VISION draft | Complete VISION draft |
| 4. Validate | Jury review (thesis quality, boundaries) | Validated VISION |

Phase 2 agents investigate: audience validation, value proposition clarity,
org fit evidence, competitive landscape (private only), and success criteria
measurability.

Phase 4 jury focuses on VISION-specific quality: Is the thesis a hypothesis
(not a problem statement)? Do success criteria avoid feature-level metrics?
Does org fit explain why HERE and not elsewhere? Are non-goals about identity
(not scope)?

### Resume Logic

```
VISION exists with status "Accepted" or "Active"       -> Offer to revise or start fresh
VISION exists with status "Draft"                       -> Offer to continue from Phase 3
wip/research/vision_<topic>_phase2_*.md files exist     -> Resume at Phase 3
wip/vision_<topic>_scope.md exists                      -> Resume at Phase 2
On a branch related to the topic                        -> Resume at Phase 1
On main or unrelated branch                             -> Start at Phase 0
```

### Critical Requirements

- **Conversational First**: Phase 1 is a dialogue, not a form to fill out
- **Research Before Drafting**: Don't draft a thesis you haven't investigated
- **User Review**: Never finalize a VISION the user hasn't reviewed and given
  feedback on
- **Jury Validation**: Phase 4 is not optional -- thesis quality, content
  boundaries, and section guidance compliance all get checked

### Execution

Execute phases sequentially by reading the corresponding phase file:

0. **Setup**: Ensure work happens on a feature branch
   - If already on a branch that matches the topic, skip branch creation
   - If on `main` or an unrelated branch, create `docs/<topic>` (kebab-case)
   - If unsure whether the current branch is related, ask the user

1. **Scope**: Conversational scoping
   - Instructions: `references/phases/phase-1-scope.md`
   - Skipped when handoff artifact (`wip/vision_<topic>_scope.md`) exists

2. **Discover**: Parallel research agents investigate leads
   - Instructions: `references/phases/phase-2-discover.md`

3. **Draft**: Produce VISION draft and walk through with user
   - Instructions: `references/phases/phase-3-draft.md`

4. **Validate**: Jury review and finalization
   - Instructions: `references/phases/phase-4-validate.md`

### Output

Final artifact: `docs/visions/VISION-<topic>.md`, created in Draft status.
After user approval, transition to Accepted via `scripts/transition-status.sh`.

After acceptance, suggest next steps:

| Situation | Suggestion |
|-----------|-----------|
| Clear feature scope already | /prd to write requirements |
| Multiple directions possible | /explore to investigate further |
| Needs organizational alignment | Share VISION for stakeholder review |

---

## Reference Files

| File | When to load |
|------|-------------|
| `references/phases/phase-1-scope.md` | Phase 1 |
| `references/phases/phase-2-discover.md` | Phase 2 |
| `references/phases/phase-3-draft.md` | Phase 3 |
| `references/phases/phase-4-validate.md` | Phase 4 |
