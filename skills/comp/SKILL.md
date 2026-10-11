---
name: comp
description: >-
  Survey what already exists in the space and turn it into implications for
  what you build: who the alternatives are, on which dimensions they differ,
  where the real gaps sit, and what that means for your own choices. Use it
  when the answer would otherwise be a chat reply nobody can find again —
  "how does Cursor handle this?", "is there anything out there that already
  does X?", "should we build this or buy it?", "why would someone pick us over
  them?", "what's the state of the art here?", "has someone already solved
  this?". Build-versus-buy is this skill: the comparison is the work. The
  result is private-only, so in a public repo it cannot be finalized and you
  want a different artifact. Do NOT use it when the question is not yet about
  named alternatives at all (`/explore`), when you are choosing between
  options already on the table (`/decision`), or when the case being made is
  for your own project rather than against theirs (`/vision`).
argument-hint: <topic-slug> [--upstream <path>]
allowed-tools: Bash(${CLAUDE_PLUGIN_ROOT}/scripts/skill-preflight.sh *), Bash(true)
---

!`${CLAUDE_PLUGIN_ROOT}/scripts/skill-preflight.sh comp 2>&1 || true`

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

If visibility is anything other than `private`, the skill **warns** — it
emits `[/comp] WARNING <topic>: visibility=public` to stdout as a
machine-readable signal, tells the author that COMP content is
competitive and belongs in a private repo, names the alternatives (a
public BRIEF/PRD that references the competitive question without
containing the analysis), and lets the author decide whether to
continue. It does not terminate the invocation on its own.

Warning is not a loosened contract. What keeps a COMP out of a public
repo is the validator's R9 gate and the CI guardrail, and both still
reject a COMP under public visibility — an analysis drafted in a public
repo cannot be transitioned or merged there. The skill's check exists to
put that in front of the author at Phase 0, before the session is spent,
rather than to make the call for them.

`/comp` is directly invocable, which is why it carries its own check: an
author can reach it without any parent skill having evaluated
visibility first. A parent that routes toward `/comp` (today,
`/charter`) carries its own visibility gate for a different reason —
it should not steer an author toward a private-only artifact type in a
public repo at all. Two checks, two jobs; neither is redundant with the
other.

## Phases

The workflow runs six phases. Each phase file lives in
`references/phases/` and is loaded when the phase begins:

1. `phase-0-setup.md` — input-mode detection, the private-only visibility
   warning, topic-slug validation, and opening the `comp-<topic>` session.
2. `phase-1-scope.md` — conversational scoping: the competitive question,
   the market slice, and the boundary of what is surveyed.
3. `phase-2-discover.md` — per-competitor research and dimension
   identification.
4. `phase-3-draft.md` — draft the seven content sections.
5. `phase-4-validate.md` — three-reviewer parallel jury and all-PASS
   aggregation.
6. `phase-5-finalize.md` — human approval, the lifecycle transition, closing
   the session, PR creation, and the `[/comp] FINALIZED` stdout contract.

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

**Topic slug constraint.** The `<topic>` slug used in the session name and
the COMP filename must match `^[a-z0-9][a-z0-9-]*$` (kebab-case, lowercase
alphanumeric, hyphens only, no leading hyphen). Phase 0 rejects any topic with
other characters, including `.`, `/`, `_`, whitespace or a leading `-`, so a
topic can't be read as a flag or reach a path.

## Session and Keys

`/comp` keeps its working state as keys in its own koto session,
`comp-<topic>`, following
`${CLAUDE_PLUGIN_ROOT}/references/skill-session-convention.md`. It writes no
file to the `wip/` staging folder. Phase 0 opens the session once the
visibility decision and the topic check are done, so the visibility warning
still comes before anything is created:

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/skill-session.sh" open comp <topic>
```

`open` attaches to a live `comp-<topic>` (an interrupted run), replaces a
finished one (a fresh run), or creates it. Any non-zero exit stops the run
with the script's message: 127 or 69 means koto is missing or too old, 6 means
HEAD is detached, and the skill never falls back to files.

| Key | Written at | Holds |
|-----|-----------|-------|
| `work/scope.md` | Phase 1 | the competitive question, the slice and its boundary, the market-or-tool decision, upstream framing |
| `research/phase4_<role>.md` | Phase 4 | one juror's verdict (`<role>` is `competitive-framing`, `content-quality` or `structural-format`), ingested from a scratch directory |

Read a key with `koto context get comp-<topic> <key>` and test one with `koto
context exists comp-<topic> <key>` (exit 0 present, 1 absent).

**Writing a key.** Assemble the content in a scratch directory, put it, and
remove the directory:

```bash
dir=$("${CLAUDE_PLUGIN_ROOT}/scripts/skill-session.sh" scratch)
# write the content to "$dir/<name>", then:
"${CLAUDE_PLUGIN_ROOT}/scripts/skill-session.sh" put comp-<topic> work/<name> "$dir/<name>"
rm -rf "$dir"
```

The jurors never write keys: Phase 4 pins each verdict to a file in a scratch
directory and ingests the directory. The one rule that reads the keys to decide
something, whether the jury has already run, is the `jury-resume` subcommand of
`comp-state.sh`.

**Closing.** Phase 5 ends the session with `"${CLAUDE_PLUGIN_ROOT}/scripts/skill-session.sh"
close comp-<topic> done`, which keeps the keys readable. A run that stops
before Phase 5 closes nothing, so its keys stay for the next run.

## Stdout Signals

`/comp` runs the same way whoever invokes it: it reads no parent's state and
no parent keeps one for it. It prints two machine-readable lines on stdout. Phase 5
emits the `[/comp] FINALIZED` block so a caller can capture the outcome by
shell parsing; under non-private visibility it emits `[/comp] WARNING
<topic>: visibility=public` instead, which can be detected the same way.

## Output

A COMP document at `docs/competitive/COMP-<topic>.md`, jury-cleared and
human-ratified, plus a PR. On a public-repo invocation the skill emits
the `[/comp] WARNING` signal, states the consequence, and proceeds only
if the author says so; finalization in that case stops at the validator
rather than landing a COMP in a public repo.
