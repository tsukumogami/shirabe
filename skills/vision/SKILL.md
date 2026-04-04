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

See `references/vision-format.md` for the full format specification: frontmatter
schema, required and optional sections, visibility-gated sections, section
matrix, content boundaries, lifecycle states, validation rules, and quality
guidance. Load it during Phases 3 and 4.

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
follow decision-protocol conventions -- make decisions based on evidence rather
than blocking on user input. Create `wip/vision_<topic>_decisions.md` to track
decisions.

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
| `references/vision-format.md` | Phase 3 (drafting) and Phase 4 (validation) |
| `references/phases/phase-1-scope.md` | Phase 1 |
| `references/phases/phase-2-discover.md` | Phase 2 |
| `references/phases/phase-3-draft.md` | Phase 3 |
| `references/phases/phase-4-validate.md` | Phase 4 |
