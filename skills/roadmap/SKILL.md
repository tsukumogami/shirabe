---
name: roadmap
description: >-
  Structured workflow for creating Roadmap documents that sequence multiple
  features into a coordinated initiative. Use when planning multi-feature
  work that needs dependency tracking, sequencing rationale, and progress
  monitoring. Triggers on "create a roadmap for X", "plan the rollout of Y",
  "sequence these features", or any request to coordinate multiple features
  into an ordered plan. Do NOT use for single-feature requirements (/prd),
  strategic justification (/vision), technical architecture (/design), or
  open-ended exploration (/explore). Drives a multi-phase workflow:
  conversational scoping, parallel research agents, structured drafting,
  and jury review.
argument-hint: '<initiative topic>'
---

@.claude/shirabe-extensions/roadmap.md
@.claude/shirabe-extensions/roadmap.local.md

# Roadmap Documents

Roadmap documents sequence multiple features into a coordinated initiative.
They capture the theme (why these features belong together), the features
themselves, dependency relationships, sequencing rationale, and progress.
They sit downstream of VISIONs (which justify why a project exists) and
upstream of PRDs (which define individual features in detail).

**Writing style:** Read `skills/writing-style/SKILL.md` for guidance.

## Roadmap Format

See `references/roadmap-format.md` for the full format specification:
frontmatter schema, required and optional sections, lifecycle states,
validation rules, and quality guidance. Load it during Phases 3 and 4.

## File Location

Roadmap documents live at `docs/roadmaps/ROADMAP-<topic>.md` (kebab-case).
No directory movement at any lifecycle stage -- all roadmaps stay in
`docs/roadmaps/` regardless of status. Stable paths keep cross-references
durable and git blame readable.

---

## Creating a Roadmap Document

When invoked as `/roadmap`, this skill drives a structured creation workflow
that scopes the initiative conversationally, fans out research agents to
validate features and dependencies, drafts the ROADMAP with section-level
review, and validates through jury review.

Unlike an explore workflow (which is open-ended and can produce any artifact
type), /roadmap always produces a ROADMAP document. Use /roadmap when you
know you need to sequence multiple features. Use an explore workflow when
you don't know what artifact type you need yet.

### Input Modes

From `$ARGUMENTS`:

1. **Empty** -- ask the user what initiative or theme they want to create a
   roadmap for
2. **Path to existing ROADMAP** with lifecycle verb (`activate`, `done`) --
   execute the lifecycle transition via `scripts/transition-status.sh`
3. **Anything else** -- use as the starting topic for Phase 1 scoping

### Standalone Entry and Handoff Detection

/roadmap works both standalone and as a handoff target from /explore.

On startup, check for `wip/roadmap_<topic>_scope.md`. If it exists, an
/explore session already ran Phase 5 and wrote the handoff artifact with
synthesized findings (theme statement, candidate features, coverage notes).
Skip Phase 1 (scoping) and proceed directly to Phase 2 (discover) -- the
scope file provides the theme and candidate features as investigation
targets.

If no handoff artifact exists, start from Phase 1.

### Context Resolution

**Execution mode:** check `$ARGUMENTS` for `--auto` or `--interactive`
flags, then CLAUDE.md `## Execution Mode:` header (default: `interactive`).
Also parse `--max-rounds=N` (default: 2 for roadmap's discover loop). In
--auto mode, follow decision-protocol conventions -- make decisions based on
evidence rather than blocking on user input. Create
`wip/roadmap_<topic>_decisions.md` to track decisions.

**Upstream:** check `$ARGUMENTS` for `--upstream <path>`. If present, the
path is stored and written to frontmatter during Phase 3 (draft). Typically
points to a VISION document. Passed by /explore when it identified a VISION
during crystallization, or by the user in standalone invocation. When not
provided, the upstream field is omitted from frontmatter.

Log: `Drafting roadmap...`

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
| 0. Setup | Create feature branch, detect context | On topic branch |
| 1. Scope | Conversational scoping (or skip if handoff exists) | Theme + candidate features + coverage dimensions |
| 2. Discover | Parallel research agents investigate features | Research findings in wip/ |
| 3. Draft | Produce ROADMAP draft | Complete ROADMAP draft |
| 4. Validate | Jury review (theme coherence, sequencing, annotations) | Validated ROADMAP |

Phase 1 tracks 6 roadmap-specific coverage dimensions:

| Dimension | What to understand |
|-----------|-------------------|
| Theme clarity | What initiative, why coordinated sequencing? |
| Feature identification | What features, at least 2? Any gaps? |
| Dependency awareness | Which features depend on each other? |
| Sequencing constraints | Hard blockers vs soft preferences? |
| Downstream artifact state | What does each feature need next (needs-*)? |
| Scope boundaries | What's in this roadmap vs excluded? |

Phase 2 agents investigate: feature completeness (gaps, granularity),
dependency accuracy (hidden dependencies, stated dependency validation),
and sequencing justification (ordering rationale, parallelization
opportunities, needs-* annotation accuracy).

Phase 4 jury focuses on roadmap-specific quality: Do features belong
together under the theme? Are dependencies explicit, not implied? Is there
circular dependency? Do needs-* labels match feature descriptions? Does the
roadmap avoid downstream content (requirements, architecture, timelines)?
Are there at least 2 features?

### Resume Logic

```
ROADMAP exists with status "Active" or "Done"              -> Offer to revise or start fresh
ROADMAP exists with status "Draft"                         -> Offer to continue from Phase 3
wip/research/roadmap_<topic>_phase2_*.md files exist       -> Resume at Phase 3
wip/roadmap_<topic>_scope.md exists                        -> Resume at Phase 2
On a branch related to the topic                           -> Resume at Phase 1
On main or unrelated branch                                -> Start at Phase 0
```

### Critical Requirements

- **Conversational First**: Phase 1 is a dialogue, not a form to fill out
- **Research Before Drafting**: Don't draft sequencing you haven't validated
- **Minimum 2 Features**: Single-feature work doesn't need a roadmap -- use
  a PRD instead
- **User Review**: Never finalize a ROADMAP the user hasn't reviewed and
  given feedback on
- **Jury Validation**: Phase 4 is not optional -- theme coherence,
  sequencing validity, and annotation accuracy all get checked

### Execution

Execute phases sequentially by reading the corresponding phase file:

0. **Setup**: Ensure work happens on a feature branch
   - If already on a branch that matches the topic, skip branch creation
   - If on `main` or an unrelated branch, create `docs/<topic>` (kebab-case)
   - If unsure whether the current branch is related, ask the user

1. **Scope**: Conversational scoping
   - Instructions: `references/phases/phase-1-scope.md`
   - Skipped when handoff artifact (`wip/roadmap_<topic>_scope.md`) exists

2. **Discover**: Parallel research agents investigate features
   - Instructions: `references/phases/phase-2-discover.md`

3. **Draft**: Produce ROADMAP draft and walk through with user
   - Instructions: `references/phases/phase-3-draft.md`

4. **Validate**: Jury review and finalization
   - Instructions: `references/phases/phase-4-validate.md`

### Output

Final artifact: `docs/roadmaps/ROADMAP-<topic>.md`, created in Draft status.
After user approval, transition to Active via `scripts/transition-status.sh`.

A roadmap must be Active before merging to main. Draft roadmaps should not
appear on the default branch -- the transition to Active signals that the
feature list is locked and the sequencing is approved.

After activation, suggest next steps:

| Situation | Suggestion |
|-----------|-----------|
| Features need requirements | /prd for individual features |
| Features need technical design | /design for architecture decisions |
| Ready to break into issues | /plan to decompose into implementation work |

---

## Lifecycle Management

Roadmaps use a linear lifecycle: Draft -> Active -> Done.

| Transition | Verb | Precondition |
|------------|------|-------------|
| Draft -> Active | `activate` | Feature list complete, human approval |
| Active -> Done | `done` | All features terminal (delivered or dropped) |

**Forbidden transitions:** Done -> any (permanent record), Active -> Draft
(no regression), Draft -> Done (can't skip Active).

Done roadmaps retain all content: features, sequencing rationale, progress,
and any Implementation Issues table or Mermaid dependency graph added by
/plan. Nothing is stripped. Done roadmaps are historical artifacts.

Lifecycle verbs are invoked as:
```
/roadmap activate docs/roadmaps/ROADMAP-<topic>.md
/roadmap done docs/roadmaps/ROADMAP-<topic>.md
```

Both delegate to `scripts/transition-status.sh`.

---

## Reference Files

| File | When to load |
|------|-------------|
| `references/roadmap-format.md` | Phase 3 (drafting) and Phase 4 (validation) |
| `references/phases/phase-1-scope.md` | Phase 1 |
| `references/phases/phase-2-discover.md` | Phase 2 |
| `references/phases/phase-3-draft.md` | Phase 3 |
| `references/phases/phase-4-validate.md` | Phase 4 |
