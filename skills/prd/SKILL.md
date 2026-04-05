---
name: prd
description: >-
  Structured workflow for creating Product Requirements Documents (PRDs).
  Use when writing new PRDs or defining WHAT to build and WHY before implementation.
  Triggers on "write requirements for X", "define scope for Y", "draft a spec",
  "what should we build for Z", "I need a PRD", or any request to capture requirements.
  Do NOT use for technical architecture decisions (/design) or open-ended exploration
  (/explore). Drives a multi-phase workflow: conversational scoping, parallel research
  agents, structured drafting, and a 3-agent jury review.
argument-hint: '<topic or feature name>'
---

@.claude/shirabe-extensions/prd.md
@.claude/shirabe-extensions/prd.local.md

# Product Requirements Documents

PRDs capture WHAT to build and WHY -- the problem, goals, requirements, and
acceptance criteria. They complement design documents (which capture HOW) and
are the input for /design (which produces technical architecture).

**Writing style:** Read `skills/writing-style/SKILL.md` for guidance.

## PRD Format

See `references/prd-format.md` for PRD structure, frontmatter, lifecycle states,
validation rules, and quality guidance. Load it during Phases 3 and 4.

## File Location

PRDs live at `docs/prds/PRD-<name>.md` (kebab-case). No directory movement
based on status -- stable paths keep cross-references durable and git blame readable.

## Repo Visibility

Before writing content, detect visibility from CLAUDE.md (`## Repo Visibility: Public|Private`). If not found, infer from repo path (`private/` -> Private, `public/` -> Public; default to Private). Load the appropriate content governance skill:
- **Private repos:** Read `skills/private-content/SKILL.md`
- **Public repos:** Read `skills/public-content/SKILL.md`

Public PRDs must not reference private artifacts.

---

## Creating a PRD

When invoked as `/prd`, this skill drives a structured creation workflow that
scopes the problem conversationally, fans out research agents, drafts the PRD
with thematic review, and validates through a jury review.

Unlike an explore workflow (which is open-ended and can produce any artifact type),
/prd always produces a PRD. Use /prd when you know you need requirements definition.
Use an explore workflow when you don't know what artifact type you need yet.

### Input Modes

From `$ARGUMENTS`:
1. **Empty** -- ask the user what feature or capability they want to specify
2. **Anything else** -- use as the starting topic for Phase 1 scoping

### Context Resolution

**Execution mode:** check `$ARGUMENTS` for `--auto` or `--interactive` flags,
then CLAUDE.md `## Execution Mode:` header (default: `interactive`). Also
parse `--max-rounds=N` (default: 2 for prd's discover loop). In --auto mode,
follow `references/decision-protocol.md` at all decision points. Create
`wip/prd_<topic>_decisions.md` to track decisions.

**Upstream:** check `$ARGUMENTS` for `--upstream <path>`. If present, the
path is stored and written to frontmatter during Phase 3 (draft). Typically
points to a Roadmap document when the PRD is part of a multi-feature
initiative. When not provided, the upstream field is omitted from frontmatter.

Detect visibility (Private/Public) from CLAUDE.md or repo path. Infer from
`private/` or `public/` in path if not explicit. Default to Private if unknown -- restricting is easier to undo than oversharing.

Log: `Specifying requirements with [Private|Public] visibility...`

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
| 0. Setup | Create feature branch | On `docs/<topic>` branch |
| 1. Scope | Conversational scoping with coverage tracking | Problem statement + research leads |
| 2. Discover | Parallel specialist agents investigate leads | Research findings in wip/ |
| 3. Draft | Produce PRD draft, surface open questions | Complete PRD draft |
| 4. Validate | 3-agent jury review | Validated PRD |

### Resume Logic

```
PRD exists with status "Accepted"                  -> Offer to revise or start fresh
PRD exists with status "Draft"                     -> Offer to continue from Phase 3
wip/research/prd_<topic>_phase2_*.md files exist   -> Resume at Phase 3
wip/prd_<topic>_scope.md exists                    -> Resume at Phase 2
On a branch related to the topic                   -> Resume at Phase 1
On main or unrelated branch                        -> Start at Phase 0
```

### Critical Requirements

- **Conversational First**: Phase 1 is a dialogue, not a form to fill out
- **Research Before Drafting**: Don't draft requirements you haven't investigated
- **User Review**: Never finalize a PRD the user hasn't reviewed and given feedback on
- **Jury Validation**: Phase 4 is not optional -- authors consistently miss ambiguity and testability gaps in their own writing, so all PRDs get reviewed by 3 agents

### Execution

Execute phases sequentially by reading the corresponding phase file:

0. **Setup**: Ensure work happens on a feature branch
   - If already on a branch that matches the topic, skip branch creation
   - If on `main` or an unrelated branch, create `docs/<topic>` (kebab-case) -- keeps drafts off main so abandoned PRDs don't need cleanup
   - If unsure whether the current branch is related, ask the user

1. **Scope**: Conversational scoping with coverage tracking
   - Instructions: `references/phases/phase-1-scope.md`

2. **Discover**: Parallel specialist agents investigate research leads
   - Instructions: `references/phases/phase-2-discover.md`

3. **Draft**: Produce PRD and walk through with user
   - Instructions: `references/phases/phase-3-draft.md`

4. **Validate**: Jury review and finalization
   - Instructions: `references/phases/phase-4-validate.md`

### Output

Final artifact: `docs/prds/PRD-<topic>.md`, transitioning from "Draft" to
"Accepted" on user approval. After acceptance, suggest next steps:

| Complexity | Suggestion |
|-----------|-----------|
| Simple or medium | plan skill |
| Complex (needs technical design first) | design skill |

---

## Reference Files

| File | When to load |
|------|-------------|
| `references/prd-format.md` | Phase 3 (drafting) and Phase 4 (validation) |
| `references/phases/phase-1-scope.md` | Phase 1 |
| `references/phases/phase-2-discover.md` | Phase 2 |
| `references/phases/phase-3-draft.md` | Phase 3 |
| `references/phases/phase-4-validate.md` | Phase 4 |
