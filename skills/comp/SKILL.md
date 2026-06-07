---
name: comp
description: >-
  Structured workflow for creating COMP (competitive-analysis) documents
  — a private-only artifact that surveys the competitive landscape a
  feature or product sits in and turns that survey into implications for
  our own choices. Use when you need to compare competitors along
  explicit dimensions, find concrete gaps, and connect those findings to
  decisions, before or alongside writing requirements. Triggers on
  "competitive analysis for X", "how do competitors handle Y", "survey
  the market for Z", "what's the competitive landscape", or "COMP-<name>".
  Do NOT use for feature requirements (/prd), technical architecture
  (/design), feature framing (/brief), or open-ended exploration
  (/explore). COMP is private-only: in a public repo the skill refuses
  and emits a redirect to alternatives.
argument-hint: <topic-slug> [--upstream <path>]
---

# Competitive Analysis Workflow

This skill drives a six-phase workflow that scopes a competitive
question, researches competitors, drafts the survey and its
implications, runs a three-reviewer jury, and finalizes through explicit
human approval. It produces a COMP document.

Use `/comp` to capture a competitive survey — the market slice, the
competitors, a comparative matrix along named dimensions, the gaps it
reveals, and what those gaps imply for our choices — as a durable
artifact. Use `/prd` when the conversation is about what one feature
does and why. Use `/brief` to frame a single feature's problem and
scope. Use `/design` for technical architecture. Use `/explore` when you
don't yet know which artifact you need.

**Writing style:** Read `skills/writing-style/SKILL.md` for guidance.

## Artifact Lifecycle

**Lifecycle:** Durable. Stays in `docs/competitive/` after completion.

COMP is durable because the competitive analysis captured at survey time stays in the audit trail. Future readers tracing why a competitive decision was made need the COMP to remain in place.

COMP is private-only; the lifecycle contract does not loosen that constraint.

## Comp Format

See `references/comp-format.md` for the full format specification:
frontmatter schema, the seven required sections, optional sections,
section matrix, content boundaries, lifecycle states, validation rules,
and per-section quality guidance. Load it during Phases 2, 3, and 4.

## File Location

COMP documents live at `docs/competitive/COMP-<topic>.md` (kebab-case).
No directory movement on any transition — a COMP stays at the same path
through Draft, Accepted, and Done.

## Visibility: Private Only

COMP is a private-only artifact type. Before any other work, Phase 0
detects repo visibility from CLAUDE.md (`## Repo Visibility:
Public|Private`); if not found, it infers from the repo path (`private/`
-> Private, `public/` -> Public; default to Private).

If visibility is anything other than `private`, the skill refuses: it
emits `[/comp] REFUSED <topic>: visibility=public` to stdout and exits
before creating any file or doing any other work. A public-repo author
is redirected to alternatives (a public BRIEF/PRD that references the
competitive question without containing the analysis). This refusal is
the skill-side half of the same private-only contract the validator
enforces with R9.

## Phases

The workflow runs six phases. Each phase file lives in
`references/phases/` and is loaded when the phase begins:

1. `phase-0-setup.md` — input-mode detection, the private-only visibility
   refusal, topic-slug validation, optional parent-orchestration sentinel
   read, and `wip/` initialization.
2. `phase-1-scope.md` — conversational scoping: the competitive question,
   the market slice, and the boundary of what is surveyed.
3. `phase-2-discover.md` — per-competitor research and dimension
   identification.
4. `phase-3-draft.md` — draft the seven content sections.
5. `phase-4-validate.md` — three-reviewer parallel jury and all-PASS
   aggregation.
6. `phase-5-finalize.md` — human approval, the lifecycle transition, wip/
   cleanup, PR creation, and the `[/comp] FINALIZED` stdout contract.

## Input Modes

From `$ARGUMENTS`:

1. **Empty** — ask the user which competitive question they want to
   survey.
2. **Path to existing COMP** with a lifecycle verb (`accept`, `done`) —
   execute the transition via `shirabe transition <comp-path>
   Accepted|Done`. No directory move.
3. **`--upstream <path>`** — treat the named artifact as the upstream
   for the new COMP; derive the competitive question candidate from it
   during Phase 1.
4. **Anything else** — use as the starting topic slug for Phase 0/1.

**Topic slug constraint.** The `<topic>` slug used in `wip/` paths and
the COMP filename must match `^[a-z0-9-]+$` (kebab-case, lowercase
alphanumeric, hyphens only). Phase 0 rejects any topic with other
characters, including `.`, `/`, `_`, or whitespace, so that a `../`-shaped
topic cannot redirect verdict writes outside `wip/research/`.

## Parent Orchestration

`/comp` can run standalone or as a child of a parent skill (today,
`/charter`). When a parent invokes it, the parent writes a sentinel at
`wip/<parent>_<topic>_state.md`; Phase 0 reads it (optionally) for
upstream injection and resume context. Phase 5 always emits the
`[/comp] FINALIZED` block (or `[/comp] REFUSED` on a visibility refusal)
to stdout so the parent can capture the outcome by shell parsing. The
sentinel read is optional — `/comp` works the same standalone.

## Output

A COMP document at `docs/competitive/COMP-<topic>.md`, jury-cleared and
human-ratified, plus a PR. On a public-repo invocation, no file is
created and the skill emits the `[/comp] REFUSED` signal instead.
