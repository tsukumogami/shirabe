---
name: brief
description: >-
  Work out what problem a feature actually solves, who it is for, and where
  its edges are, and write that down where it survives. Use it when you are
  handed a feature and cannot say in one sentence what would be worse without
  it — "what are we actually solving here?", "the issue says add SSO but
  never says why anyone wants it", "we keep arguing about what's in and out of
  the export" — and use it even when an issue or a conversation already
  states the problem, because the issue is ephemeral and this framing is the
  record a future reader traces the feature back to. Skipping it means writing
  acceptance criteria for a feature whose problem nobody ever stated. Do NOT
  use it to write the requirements themselves (`/prd`), to settle a whole
  feature end to end from framing to issues (`/scope`, which runs this as its
  first hop), to order a set of features (`/roadmap`), or when the question is
  still open-ended (`/explore`).
argument-hint: '<feature topic, optional ROADMAP path, or BRIEF path + lifecycle verb> [--upstream <path>]'
allowed-tools: Bash(${CLAUDE_PLUGIN_ROOT}/scripts/skill-preflight.sh *), Bash(true)
---

!`${CLAUDE_PLUGIN_ROOT}/scripts/skill-preflight.sh brief 2>&1 || true`

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
frontmatter schema, required and optional sections,
content boundaries, lifecycle states, validation rules, and per-section
quality guidance. Load it during Phases 2, 3, and 4.

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
3. **Path to a ROADMAP document** (matches
   `docs/roadmaps/ROADMAP-*.md`) — read it to ground the new BRIEF;
   derive the feature's problem/outcome candidate from its content
   during Phase 1. The roadmap is read, not recorded (see
   `references/phases/phase-0-setup.md`).
4. **Anything else** — use as the starting topic for Phase 1 scoping.

Any of the modes above may carry `--upstream <path>`, naming the
grounding ROADMAP separately from the topic. `/brief <topic-slug>
--upstream docs/roadmaps/ROADMAP-<name>.md` produces
`BRIEF-<topic-slug>.md` grounded in that ROADMAP — the slug comes from
the positional argument and the grounding path from the flag, so the
two need not share a name. Input Mode 3 is the special case where they
do: a bare ROADMAP path supplies both at once, which only works while
the feature's topic and the roadmap's filename coincide. A roadmap
normally sequences several features, so they usually do not.

### Context Resolution

Log: `Drafting brief with [Private|Public] visibility...`

`/brief` takes no mode flag and runs interactively, except under a parent's
dispatch key, where it follows the parent's execution mode (see "Under `/scope`"
below).

### Session and Keys

`/brief` keeps its working state as keys in its own koto session,
`brief-<topic>`, following
`${CLAUDE_PLUGIN_ROOT}/references/skill-session-convention.md`. It writes no
file to the staging folder, chained or direct. As soon as the topic is known
(from the argument, or from Phase 0's slug step on a cold start), and before
the resume rows below are read, it opens the session and records whether it
runs under a parent:

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/skill-session.sh" open brief <topic>
"${CLAUDE_PLUGIN_ROOT}/scripts/skill-session.sh" adopt brief <topic>
```

`open` attaches to a live `brief-<topic>` (an interrupted run, whose keys the
resume rows read), replaces a finished one (a fresh run), or creates it. Any
non-zero exit from either command stops the run with the script's message:
127 or 69 means koto is missing or too old, and the skill never falls back to
files. `adopt` exiting 3 is the two-parents case below.

| Key | Written at | Holds |
|-----|-----------|-------|
| `work/context.md` | Phase 0 | entry mode, grounding path, visibility, artifact decision, phase |
| `work/discover.md` | Phase 1 | the scoping conversation's output |
| `research/phase4_content-quality.md`, `research/phase4_structural-format.md` | Phase 4 | the jury's verdicts, ingested from a scratch directory |

Keys are read and written with koto against `brief-<topic>`: `koto context
exists brief-<topic> <key>` tests one (exit 0 present, 1 absent), `koto
context get brief-<topic> <key>` prints it, `koto context add brief-<topic>
<key>` stores the content given on stdin (the whole content: to change one
line, get the key, edit it, and add it back), `koto context list
brief-<topic> --prefix <prefix>` lists keys, and `koto context remove
brief-<topic> <key>` removes one. Reviewer agents never write keys: Phase 4
pins each verdict to a file in a `skill-session.sh scratch` directory and
ingests it.

**Closing.** A direct run closes its session when it finishes:
`"${CLAUDE_PLUGIN_ROOT}/scripts/skill-session.sh" close brief-<topic> done`
after Phase 5's last step, or `close brief-<topic> abandoned` after a Reject's
discard commit. Under a parent `/brief` never closes its own session: the
parent closes it at its own exit (`skill-session.sh close-children`), and the
keys stay readable until then.

### Resume Logic

```
dispatch read brief <topic> prints parent=<session>
                                                         -> run under that parent; see ${CLAUDE_PLUGIN_ROOT}/references/fixes/sub-agent-dispatch.md
BRIEF exists with status "Accepted" or "Done"            -> Offer to revise or start fresh
BRIEF exists with status "Draft"                         -> Offer to continue from Phase 2 or 3
keys research/phase4_* exist in brief-<topic>            -> Resume at Phase 4 (aggregate)
BRIEF has User Journeys section with real content        -> Resume at Phase 4
BRIEF has Problem Statement section                      -> Resume at Phase 3
key work/discover.md exists in brief-<topic>             -> Resume at Phase 2
key work/context.md exists in brief-<topic>              -> Resume at Phase 1
None of the above                                        -> Start at Phase 0
```

**Running under a parent.** The first row runs
`"${CLAUDE_PLUGIN_ROOT}/scripts/skill-session.sh" dispatch read brief <topic>`
with the topic this run works on. A printed `parent=<session>`
line means `/brief` runs under that parent (`scope-<topic>` or
`charter-<topic>`), with the parent's upfront decision in the `rationale=` and
`suppress_status_aware_prompt=` lines; what changes under a parent is in
`${CLAUDE_PLUGIN_ROOT}/references/fixes/sub-agent-dispatch.md`.
Four cases are no match. Three print nothing and exit 0, and the run is a
direct one with the rows below unchanged: no parent session, a finished parent
session, and a parent whose `chain/dispatch` key names another child. The
fourth, two parent sessions that both name `/brief`, exits 3: don't pick one
and don't run directly; stop and report both sessions, which the script names
on stderr, so the author can clear the stale key. Any other non-zero exit
stops the run with the script's message (`open` has already checked koto).
`adopt` has recorded the same match as `chain/parent` in `brief-<topic>`, or
removed a `chain/parent` an earlier chained run left.

**Under `/scope`.** When `/scope`'s dispatch key names
`brief` (the first row above), `/brief` still reaches its own Phase 5 verdict
and makes its own status transition, and skips everything that publishes or
routes, which `/scope` owns: no push, no pull request, no branch creation, no
cleanup commit, and no routing prompt. Control returns to `/scope`, which
decides the next hop. An interactive run asks the author for the verdict as
usual; an unattended run (`--auto`, which `/brief` takes from the parent's
execution mode) takes the recommended verdict and names it in its output.
Phase 5 marks each step this changes. This is the Parent-owned-publishing
shape in `${CLAUDE_PLUGIN_ROOT}/references/fixes/sub-agent-dispatch.md`, per
`docs/decisions/DECISION-contradiction-child-steps-under-scope-2026-09-28.md`.
Without a dispatch key naming this skill, nothing here applies.

### Critical Requirements

- **Human approval gate:** Phase 5 requires explicit human approval via
  AskUserQuestion before Draft -> Accepted. Jury PASS alone does not
  transition status. The one exception is an unattended run under
  `/scope`, which takes the recommended verdict and names it (see "Under
  `/scope`" above).

### Execution

Execute phases sequentially by reading the corresponding phase file:

0. **Setup**: visibility detection + slug + path validation (works on the
   current branch; creates none)
   - Instructions: `references/phases/phase-0-setup.md`

1. **Discover**: scoping conversation + upstream grounding
   - Instructions: `references/phases/phase-1-discover.md`

2. **Draft**: Problem Statement, User Outcome
   - Instructions: `references/phases/phase-2-draft.md`

3. **Structural Fill**: User Journeys, Scope Boundary, optional sections
   - Instructions: `references/phases/phase-3-structural-fill.md`

4. **Validate**: two-reviewer jury (parallel agents)
   - Instructions: `references/phases/phase-4-validate.md`

5. **Finalize**: approval + status transition + PR (no PR under `/scope`)
   - Instructions: `references/phases/phase-5-finalize.md`

### Output

Final artifact: `docs/briefs/BRIEF-<topic>.md`, created in Draft
status. After explicit user approval at Phase 5, transition to Accepted
via `shirabe transition <brief-path> Accepted`.

---

## Team Shape

`/brief`'s team shape is declared in [`team.yaml`](./team.yaml) as the
machine-readable contract surface. The child layer spawns two reviewer
peers at Phase 4 (`content-quality-reviewer`,
`structural-format-reviewer`) to validate the drafted BRIEF.

See [Dispatch Contract](${CLAUDE_PLUGIN_ROOT}/references/parent-skill-pattern.md) for v1 parent-side consumption rules.
