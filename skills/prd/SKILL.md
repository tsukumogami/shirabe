---
name: prd
description: >-
  Settle what a feature must do and how anyone will know it is done — the
  behaviour, the numbered acceptance criteria, the cases that are deliberately
  out. Use it when the problem is already framed and the open question is the
  substance: "what should this actually do?", "what does done look like for
  this feature?", "list the acceptance criteria", "the stakeholders disagree
  about what we're building", "write up what we agreed in that meeting", or a
  settled BRIEF whose next step is requirements. Without it an agent invents
  the requirements as it codes and nothing written down can contradict it
  later. Do NOT use it when neither the requirements nor the technical
  approach are written down anywhere — that whole run is `/scope`, which
  calls this as one hop. Do NOT use it to work out the problem and the scope
  boundary in the first place (`/brief`), to choose the technical approach
  (`/design`), or to investigate an open question (`/explore`).
argument-hint: '<topic, feature name, or BRIEF path> [--upstream <path>] [--auto|--interactive] [--max-rounds=N]'
allowed-tools: Bash(${CLAUDE_PLUGIN_ROOT}/scripts/skill-preflight.sh *), Bash(true)
---

!`${CLAUDE_PLUGIN_ROOT}/scripts/skill-preflight.sh prd 2>&1 || true`

@.claude/shirabe-extensions/prd.md
@.claude/shirabe-extensions/prd.local.md

# Product Requirements Documents

PRDs capture WHAT to build and WHY -- the problem, goals, requirements, and
acceptance criteria. They complement design documents (which capture HOW) and
are the input for /design (which produces technical architecture).

**Writing style:** Read `skills/writing-style/SKILL.md` for guidance.

## Artifact Lifecycle

**Lifecycle:** Durable. Stays in `docs/prds/` after completion.

PRD is durable because the requirements captured at PRD-Accepted time are the audit trail of what was promised. Future readers checking whether a shipped feature met its requirements need the PRD to remain in place.

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
2. **Path to BRIEF document** (matches `docs/briefs/BRIEF-*.md`) -- brief
   input mode. The brief is treated as the upstream framing and its path is
   stored for Phase 0 (setup) and Phase 3 (draft). When the brief's status
   is `Draft`, Phase 0 transitions it to `Accepted` so the chain handoff
   matches /design (which bumps PRD `Accepted -> In Progress`) and /plan
   (which bumps DESIGN `Accepted -> Planned`). See "Execution" below.
3. **Anything else** -- use as the starting topic for Phase 1 scoping

Modes 1 and 3 may carry `--upstream <path>`, naming the BRIEF, STRATEGY or
VISION the PRD is written from; Phase 3 validates it before writing it to
frontmatter. In Mode 2 the positional BRIEF is the upstream, and a different
`--upstream` is ignored with a note to the author saying so.

### Session and Keys

`/prd` keeps its working state as keys in its own koto session, `prd-<topic>`,
following `${CLAUDE_PLUGIN_ROOT}/references/skill-session-convention.md`. It
writes no file to the staging folder, chained or direct. Its first act, once
the topic is known (from the argument, or the `<topic>` in a path argument's
file name) and before Context Resolution or the resume rows below, opens the
session and records whether it runs under a parent:

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/skill-session.sh" open prd <topic>
"${CLAUDE_PLUGIN_ROOT}/scripts/skill-session.sh" adopt prd <topic>
```

`open` attaches to a live `prd-<topic>` (an interrupted run, whose keys the
resume rows read), replaces a finished one (a fresh run), or creates it. Any
non-zero exit from either command stops the run with the script's message:
127 or 69 means koto is missing or too old, and the skill never falls back to
files. `adopt` exiting 3 is the two-parents case below.

| Key | Written at | Holds |
|-----|-----------|-------|
| `work/decisions.md` | Context Resolution, under `--auto` | the autonomous-decision ledger |
| `work/scope.md` | Phase 1 | the scoping output |
| `research/phase2_<role>.md` | Phase 2 | the discovery agents' findings, ingested from a scratch directory |
| `research/phase4_<role>.md` | Phase 4 | the jury's verdicts, ingested from a scratch directory |

Keys are read and written with koto against `prd-<topic>`: `koto context
exists prd-<topic> <key>` tests one (exit 0 present, 1 absent), `koto context
get prd-<topic> <key>` prints it, `koto context add prd-<topic> <key>` stores
the content given on stdin (the whole content: to change part of it, get the
key, edit it, and add it back), `koto context list prd-<topic> --prefix
<prefix>` lists keys, and `koto context remove prd-<topic> <key>` removes one.
Research and reviewer agents never write keys: each phase that spawns them
pins every output to a file in a `skill-session.sh scratch` directory and
ingests it.

**Closing.** A direct run closes its session when it finishes:
`"${CLAUDE_PLUGIN_ROOT}/scripts/skill-session.sh" close prd-<topic> done`
at the end of Phase 4, or `close prd-<topic> abandoned` after a Reject's
discard commit. Under a parent `/prd` never closes its own session: the
parent closes it at its own exit (`skill-session.sh close-children`), and the
keys stay readable until then.

### Context Resolution

**Execution mode:** check `$ARGUMENTS` for `--auto` or `--interactive` flags,
then CLAUDE.md `## Execution Mode:` header (default: `interactive`). Under
`/scope`'s dispatch key the parent's execution mode wins, since `/scope` passes no
mode flag (see "Under `/scope`" below). Also
parse `--max-rounds=N` (default: 2 for prd's discover loop). In --auto mode,
follow `${CLAUDE_PLUGIN_ROOT}/references/decision-protocol.md` at all decision points, and
track decisions in key `work/decisions.md` in `prd-<topic>`.

When the positional argument is itself a BRIEF path (Input Mode 2), that
path is used as the upstream and `--upstream` is not required.

Log: `Specifying requirements with [Private|Public] visibility...`

### Resume Logic

```
dispatch read prd <topic> prints parent=<session>
                                                   -> run under that parent; see ${CLAUDE_PLUGIN_ROOT}/references/fixes/sub-agent-dispatch.md
PRD exists with status "Accepted"                  -> Offer to revise or start fresh
PRD exists with status "Draft"                     -> Offer to continue from Phase 3
keys research/phase2_* exist in prd-<topic>        -> Resume at Phase 3
key work/scope.md exists in prd-<topic>            -> Resume at Phase 2
On a branch related to the topic                   -> Resume at Phase 1
On main or unrelated branch                        -> Start at Phase 0
```

**Running under a parent.** The first row runs
`"${CLAUDE_PLUGIN_ROOT}/scripts/skill-session.sh" dispatch read prd <topic>`
with the topic this run works on (for a path argument, the `<topic>` in its file name). A printed `parent=<session>`
line means `/prd` runs under that parent (`scope-<topic>` or
`charter-<topic>`), with the parent's upfront decision in the `rationale=` and
`suppress_status_aware_prompt=` lines; what changes under a parent is in
`${CLAUDE_PLUGIN_ROOT}/references/fixes/sub-agent-dispatch.md`.
Four cases are no match. Three print nothing and exit 0, and the run is a
direct one with the rows below unchanged: no parent session, a finished parent
session, and a parent whose `chain/dispatch` key names another child. The
fourth, two parent sessions that both name `/prd`, exits 3: don't pick one
and don't run directly; stop and report both sessions, which the script names
on stderr, so the author can clear the stale key. Any other non-zero exit
stops the run with the script's message (`open` has already checked koto).
`adopt` has recorded the same match as `chain/parent` in `prd-<topic>`, or
removed a `chain/parent` an earlier chained run left.

**Under `/scope`.** When `/scope`'s dispatch key names
`prd` (the first row above), `/prd` still reaches its own Phase 4 verdict
and makes its own status transition, and skips everything that publishes or
routes, which `/scope` owns: no push, no pull request, no branch creation, no
cleanup commit, and no routing prompt. Control returns to `/scope`, which
decides the next hop. An interactive run asks the author for the verdict as
usual; an unattended run (`--auto`, which `/prd` takes from the parent's
execution mode) takes the recommended verdict and names it in its output.
Setup below and Phase 4 mark each step this changes. This is the
Parent-owned-publishing shape in
`${CLAUDE_PLUGIN_ROOT}/references/fixes/sub-agent-dispatch.md`, per
`docs/decisions/DECISION-contradiction-child-steps-under-scope-2026-09-28.md`.
Without a dispatch key naming this skill, nothing here applies.

### Critical Requirements

- **User Review**: Never finalize a PRD the user hasn't reviewed and given feedback on.
  The one exception is an unattended run under `/scope`, which takes the
  recommended verdict and names it (see "Under `/scope`" above).
- **Jury Validation**: Phase 4 is not optional -- authors consistently miss ambiguity and testability gaps in their own writing, so all PRDs get reviewed by 3 agents

### Execution

Execute phases sequentially by reading the corresponding phase file:

0. **Setup**: Ensure work happens on a feature branch and, in brief input
   mode, transition the upstream brief.
   - If already on a branch that matches the topic, skip branch creation
   - If on `main` or an unrelated branch, create `docs/<topic>` (kebab-case) -- keeps drafts off main so abandoned PRDs don't need cleanup
   - If unsure whether the current branch is related, ask the user
   - Under `/scope`'s dispatch key, skip all three: work on the branch `/scope`
     invoked this skill on, whatever its name, and neither create nor switch
     branches nor ask about it
   - **Upstream brief transition (brief input mode only):** if the input
     was a BRIEF path (Input Mode 2) and the brief's status is `Draft`,
     transition it `Draft -> Accepted` so the chain handoff is symmetric
     with /design (PRD `Accepted -> In Progress`) and /plan (DESIGN
     `Accepted -> Planned`). Skip when the brief is already `Accepted` or
     `Done`, and skip entirely when /prd was invoked without a brief input
     (empty or topic). Update both the brief frontmatter `status:` and the
     body `## Status` line atomically so the FC03 cross-check stays
     consistent. Use the transition subcommand:

     ```bash
     shirabe transition <brief-path> Accepted
     ```

     The subcommand is a no-op when the brief is already `Accepted`, exits
     with a clear error if asked to transition from `Done`, and updates both
     frontmatter and body in one operation. Commit:
     `docs(brief): mark <brief-name> accepted`

     Under `/scope`'s dispatch key this step still runs, since it is a status
     transition rather than publishing. `/brief` already accepted the brief in
     its own hop, so it is normally a no-op there.

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
"Accepted" on user approval. After acceptance, suggest next steps (not under
`/scope`, which decides the next hop itself):

| Complexity | Suggestion |
|-----------|-----------|
| Simple (few requirements, clear scope, could be a single PR) | File an issue, then `/work-on <issue>` |
| Medium (multiple requirements, needs issue breakdown) | `/plan` |
| Complex (needs technical design decisions) | `/design` |

---

## Team Shape

`/prd`'s team shape is declared in [`team.yaml`](./team.yaml) as the
machine-readable contract surface. The child layer spawns three
reviewer peers at Phase 4 (`completeness-reviewer`, `clarity-reviewer`,
`testability-reviewer`) to validate the drafted PRD.

See [Dispatch Contract](${CLAUDE_PLUGIN_ROOT}/references/parent-skill-pattern.md) for v1 parent-side consumption rules.
