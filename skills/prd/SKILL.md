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
argument-hint: '<topic or feature name>'
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

### Context Resolution

**Execution mode:** check `$ARGUMENTS` for `--auto` or `--interactive` flags,
then CLAUDE.md `## Execution Mode:` header (default: `interactive`). Also
parse `--max-rounds=N` (default: 2 for prd's discover loop). In --auto mode,
follow `references/decision-protocol.md` at all decision points. Create
`wip/prd_<topic>_decisions.md` to track decisions.

When the positional argument is itself a BRIEF path (Input Mode 2), that
path is used as the upstream and `--upstream` is not required.

Log: `Specifying requirements with [Private|Public] visibility...`

### Resume Logic

```
parent_orchestration sentinel in wip/scope_<topic>_state.md or wip/charter_<topic>_state.md
                                                   -> see references/fixes/sub-agent-dispatch.md
PRD exists with status "Accepted"                  -> Offer to revise or start fresh
PRD exists with status "Draft"                     -> Offer to continue from Phase 3
wip/research/prd_<topic>_phase2_*.md files exist   -> Resume at Phase 3
wip/prd_<topic>_scope.md exists                    -> Resume at Phase 2
On a branch related to the topic                   -> Resume at Phase 1
On main or unrelated branch                        -> Start at Phase 0
```

### Critical Requirements

- **User Review**: Never finalize a PRD the user hasn't reviewed and given feedback on
- **Jury Validation**: Phase 4 is not optional -- authors consistently miss ambiguity and testability gaps in their own writing, so all PRDs get reviewed by 3 agents

### Execution

Execute phases sequentially by reading the corresponding phase file:

0. **Setup**: Ensure work happens on a feature branch and, in brief input
   mode, transition the upstream brief.
   - If already on a branch that matches the topic, skip branch creation
   - If on `main` or an unrelated branch, create `docs/<topic>` (kebab-case) -- keeps drafts off main so abandoned PRDs don't need cleanup
   - If unsure whether the current branch is related, ask the user
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
