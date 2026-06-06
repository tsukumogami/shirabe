---
name: brief
description: >-
  Structured workflow for creating BRIEF documents — the framing step
  between a sequenced ROADMAP feature and a PRD's requirements. Use to
  capture a feature's problem, intended outcome, user journeys, and
  scope boundary as durable artifacts before requirements are written —
  including when an issue or conversation already states the problem,
  since the skill's job is to persist that framing (into the BRIEF, or
  a downstream PRD/design when a standalone brief is too heavy), not
  merely to supply framing that is missing. Triggers on "frame this
  feature", "write a brief for X", "what problem does Y solve before we
  write the PRD", "we need the framing step between the roadmap and the
  PRD", or "BRIEF-<name>". Do NOT use for feature sequencing
  (/roadmap), requirements articulation (/prd), technical architecture
  (/design), or open-ended exploration (/explore). Drives a six-phase
  workflow: conversational scoping, structured drafting, structural
  fill, a two-reviewer jury, and finalization.
argument-hint: '<feature topic, optional ROADMAP/PRD path, or BRIEF path + lifecycle verb>'
---

@.claude/shirabe-extensions/brief.md
@.claude/shirabe-extensions/brief.local.md

# Brief Documents

BRIEF documents frame a single named feature before its requirements
exist. They sit in the tactical chain between ROADMAP (which sequences
which features get built and in what order) and PRD (which captures
what one feature does and why). A ROADMAP entry is a line item; a PRD
is a requirements contract. The BRIEF is the framing step in between:
it states the problem the feature solves, the outcome a user should
experience, the concrete journeys that exercise it, and the boundary
of what it holds in and pushes out — in a form the downstream PRD can
pick up directly.

A BRIEF frames one feature, so it has no altitude band to police and
no falsifiable bet to invalidate. That is why the brief workflow is
the strategy workflow minus the altitude reviewer, the
visibility-gated section, and the Sunset lifecycle state.

**Writing style:** Read `skills/writing-style/SKILL.md` for guidance.

## Brief Format

See `references/brief-format.md` for the full format specification:
frontmatter schema, required and optional sections, section matrix,
content boundaries, lifecycle states, validation rules, and per-section
quality guidance. Load it during Phases 2, 3, and 4.

## File Location

BRIEF documents live at `docs/briefs/BRIEF-<topic>.md` (kebab-case).
No directory movement on any transition — a brief stays at the same
path through Draft, Accepted, and Done. Stable paths keep
cross-references durable and git blame readable.

## Repo Visibility

Before writing content, detect visibility from CLAUDE.md
(`## Repo Visibility: Public|Private`). If not found, infer from the
repo path (`private/` -> Private, `public/` -> Public; default to
Private). Load the appropriate content governance skill:

- **Private repos:** Read `skills/private-content/SKILL.md`
- **Public repos:** Read `skills/public-content/SKILL.md`

BRIEF has no visibility-gated section — there is no competitive framing
to fence off, so `shirabe validate` runs no custom check for the type.
The visibility value still matters: a public BRIEF must not reference
private paths, repos, filenames, or issue numbers, and its `upstream:`
field must not point at a private artifact. The Phase 4
structural-format reviewer flags these; content governance owns the
rules.

---

## Creating a Brief Document

When invoked as `/brief`, this skill drives a six-phase workflow that
scopes the feature conversationally, drafts the four content sections,
runs a two-reviewer jury, and finalizes through explicit human
approval.

The skill produces a BRIEF document. Use `/brief` to capture a
feature's framing — its problem, outcome, journeys, and scope — as a
durable artifact before requirements are written. Reach for it even
when an issue or a conversation already states the problem: that
source is ephemeral, and the skill's job is to persist the framing (in
the BRIEF, or downstream when a standalone brief is too heavy), not
just to supply framing that's missing. Use `/roadmap` if the
conversation is about which features ship and in what order. Use
`/prd` once the framing is settled and what's needed is the
requirements contract.

### Input Modes

From `$ARGUMENTS`:

1. **Empty** — ask the user which feature they want to frame.
2. **Path to existing BRIEF** with lifecycle verb (`accept`, `done`) —
   execute the lifecycle transition via `shirabe transition <brief-path>
   <status>`. No reason argument; no directory move.
3. **Path to a ROADMAP or PRD document** (matches
   `docs/roadmaps/ROADMAP-*.md` or `docs/prds/PRD-*.md`) — treat as the
   upstream for the new BRIEF; derive the feature's problem/outcome
   candidate from upstream content during Phase 1.
4. **Anything else** — use as the starting topic for Phase 1 scoping.

### Context Resolution

**Topic slug constraint.** The `<topic>` slug used in wip/ paths and
the BRIEF filename must match `^[a-z0-9-]+$` (kebab-case lowercase
alphanumeric, hyphens only). Phase 0 enforces this by rejecting any
topic that contains other characters, including `.`, `/`, `_`, or
whitespace. Without the constraint, a `../`-shaped topic could redirect
verdict writes outside `wip/research/`.

**Path canonicalization.** Any user-supplied ROADMAP or PRD upstream
path (Input Mode 3) must be canonicalized at Phase 0 and rejected if
the canonical path resolves outside the repo working tree. Symlinks
resolving to arbitrary filesystem content would otherwise leak into a
public commit.

**Visibility detection.** Detect Public/Private from CLAUDE.md or repo
path. Infer from `private/` or `public/` in the path if not explicit.
Default to Private if unknown — restricting is easier to undo than
oversharing.

BRIEF has no scope (`project`/`org`) dimension. A brief frames one
feature; there is nothing to scope across.

Log: `Drafting brief with [Private|Public] visibility...`

### Workflow Phases

```
Phase 0: SETUP --> Phase 1: DISCOVER --> Phase 2: DRAFT --> Phase 3: STRUCTURAL FILL --> Phase 4: VALIDATE --> Phase 5: FINALIZE
(branch +         (scope + upstream     (Problem Statement, (User Journeys,              (2-reviewer        (approval +
 visibility +     grounding;            User Outcome)       Scope Boundary,              jury)              transition)
 artifact         problem/outcome                           optional sections)
 decision)        pair)                                                                  |
                                                                                          v (FAIL loops back to Phase 2 or 3)
```

| Phase | Purpose | Artifact |
|-------|---------|----------|
| 0. Setup | Branch, visibility detection, slug + path validation, artifact decision | On topic branch |
| 1. Discover | Scoping conversation; ground the feature's problem and outcome | `wip/brief_<topic>_discover.md` |
| 2. Draft | Problem Statement, User Outcome | Partial BRIEF draft |
| 3. Structural Fill | User Journeys, Scope Boundary, optional sections | Complete BRIEF draft |
| 4. Validate | Two parallel reviewers (content quality, structural format) | Verdict files + aggregated decision |
| 5. Finalize | Explicit human approval, Draft -> Accepted transition, PR | Accepted BRIEF |

Phase 4 jury runs two reviewers in parallel:

- **Content quality** — the Problem Statement states a problem (not a
  smuggled solution); the User Outcome is outcome-shaped (not a feature
  list); each User Journey is concrete and the journeys are distinct;
  the Scope Boundary has real in/out exclusions; Open Questions (if
  present) defer to the downstream PRD.
- **Structural format** — all five required sections present and
  ordered; frontmatter fields and status value valid; the body
  `## Status` first word matches the frontmatter status;
  public-visibility clean; writing-style honored.

Both must PASS before Phase 5 begins. There is no altitude reviewer —
a brief frames one feature, so there is no altitude band to police.

### Resume Logic

```
BRIEF exists with status "Accepted" or "Done"           -> Offer to revise or start fresh
BRIEF exists with status "Draft"                         -> Offer to continue from Phase 2 or 3
wip/research/brief_<topic>_phase4_*.md files exist       -> Resume at Phase 4 (aggregate)
BRIEF has User Journeys section with real content        -> Resume at Phase 4
BRIEF has Problem Statement section                      -> Resume at Phase 3
wip/brief_<topic>_discover.md exists                     -> Resume at Phase 2
wip/brief_<topic>_context.md exists                      -> Resume at Phase 1
On main or unrelated branch                              -> Start at Phase 0
```

### Critical Requirements

- **Topic-slug constraint:** Phase 0 rejects topics not matching
  `^[a-z0-9-]+$`. Non-compliant topics never reach later phases.
- **Path canonicalization:** Phase 0 canonicalizes and bounds-checks
  any user-supplied upstream path.
- **Artifact decision:** Phase 0 decides, when the chain is entered
  partway up (a rich issue body already implies problem and outcome),
  whether to produce a durable brief or pass the existing evidence
  forward to the PRD. A brief written by reflex is not the goal.
- **Conversational scoping:** Phase 1 is a dialogue, not a form. The
  anchor is the feature's problem/outcome pair, not a bet.
- **Jury parallelism:** Phase 4 spawns the two reviewer agents with
  `run_in_background: true`. Each reviewer's prompt is self-contained
  (no shared memory); the orchestrator aggregates verdicts.
- **Human approval gate:** Phase 5 requires explicit human approval via
  AskUserQuestion before Draft -> Accepted. Jury PASS alone does not
  transition status.
- **Status convention:** the body `## Status` section opens with the
  bare status word alone on its own line (`Draft`, `Accepted`, or
  `Done`), a blank line, then any prose. `shirabe validate` (FC03)
  compares that first non-blank line to the frontmatter `status`; prose
  on the status line breaks the check.

### Execution

Execute phases sequentially by reading the corresponding phase file:

0. **Setup**: branch + visibility detection + slug + path validation + artifact decision
   - Instructions: `references/phases/phase-0-setup.md`

1. **Discover**: scoping conversation + upstream grounding
   - Instructions: `references/phases/phase-1-discover.md`

2. **Draft**: Problem Statement, User Outcome
   - Instructions: `references/phases/phase-2-draft.md`

3. **Structural Fill**: User Journeys, Scope Boundary, optional sections
   - Instructions: `references/phases/phase-3-structural-fill.md`

4. **Validate**: two-reviewer jury (parallel agents)
   - Instructions: `references/phases/phase-4-validate.md`

5. **Finalize**: approval + status transition + PR
   - Instructions: `references/phases/phase-5-finalize.md`

### Output

Final artifact: `docs/briefs/BRIEF-<topic>.md`, created in Draft
status. After explicit user approval at Phase 5, transition to Accepted
via `shirabe transition <brief-path> Accepted`.

After acceptance, suggest next steps:

| Situation | Suggestion |
|-----------|-----------|
| Framing is settled and requirements are the next conversation | `/prd` to capture requirements, with this BRIEF as upstream |
| The brief surfaced a technical question that needs deciding | `/design` to work the architecture |
| The framing changed which features should ship | `/roadmap` to re-sequence |
| A framing question is still open | `/explore` to investigate further |

---

## Team Shape

`/brief`'s team shape is declared in [`team.yaml`](./team.yaml) as the
machine-readable contract surface. The child layer spawns two reviewer
peers at Phase 4 (`content-quality-reviewer`,
`structural-format-reviewer`) to validate the drafted BRIEF.

See [Dispatch Contract](${CLAUDE_PLUGIN_ROOT}/references/parent-skill-pattern.md) for v1 parent-side consumption rules.

## Reference Files

| File | When to load |
|------|-------------|
| `references/brief-format.md` | Phases 2, 3, 4 (drafting + validation) |
| `references/phases/phase-0-setup.md` | Phase 0 |
| `references/phases/phase-1-discover.md` | Phase 1 |
| `references/phases/phase-2-draft.md` | Phase 2 |
| `references/phases/phase-3-structural-fill.md` | Phase 3 |
| `references/phases/phase-4-validate.md` | Phase 4 |
| `references/phases/phase-5-finalize.md` | Phase 5 |
