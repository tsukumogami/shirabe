---
name: design
description: >-
  Choose how something gets built and write the reasoning down: decompose it
  into the questions that actually have to be answered, weigh the options for
  each, and land a technical approach on a page. Reach for it when the
  requirements are already settled — an accepted PRD exists, or the feature
  is specified and the open question is pure architecture: "how should this
  talk to the existing cache?", "what's the migration path off the old
  schema?", "we have the PRD, now what?", "refactor the auth layer", "why is
  this slow and what do we do about it?". An agent that starts editing files
  instead has picked an approach without anyone seeing what it was picked
  over. Do NOT use it when the requirements are NOT settled and the feature
  still has to be worked out — that is `/scope`, which runs this as one hop
  and decides per feature whether a separate design survives. Do NOT use it
  for one named either-or choice (`/decision`), for requirements (`/prd`), or
  for a question with no options on the table yet (`/explore`).
argument-hint: '<PRD path or topic>'
allowed-tools: Bash(${CLAUDE_PLUGIN_ROOT}/scripts/skill-preflight.sh *), Bash(true)
---

!`${CLAUDE_PLUGIN_ROOT}/scripts/skill-preflight.sh design 2>&1 || true`

@.claude/shirabe-extensions/design.md
@.claude/shirabe-extensions/design.local.md

# Design Documents

Design documents capture HOW to build something -- the technical approach, trade-offs
considered, and architecture chosen. They complement PRDs (which capture WHAT and WHY)
and are the input for /plan (which breaks designs into issues).

**Writing style:** Read `skills/writing-style/SKILL.md` for guidance.

## Artifact Lifecycle

**Lifecycle:** Durable. Stays in `docs/designs/` after completion.

## Structure

### Frontmatter

Every design doc begins with YAML frontmatter:

```yaml
---
status: Proposed
problem: |
  1 paragraph: what's broken or missing, who it affects, why now.
decision: |
  1 paragraph: chosen approach and key design elements.
rationale: |
  1 paragraph: why this approach, what trade-offs were weighed.
---
```

All four fields required. Use literal block scalars (`|`). Frontmatter status must
match the Status section in the body -- agent workflows parse frontmatter to
determine lifecycle state, so divergence causes silent errors. The frontmatter
provides a self-contained summary so readers can understand the design without
reading the full document.

**Optional fields:**
- `upstream: docs/prds/PRD-<name>.md` -- link to source PRD (set by /design Phase 0).
  For cross-repo upstream references and the visibility-direction rules,
  see `${CLAUDE_PLUGIN_ROOT}/references/cross-repo-references.md`. The
  Phase 0 setup script validates this value (see step 0.4a in
  `references/phases/phase-0-setup-prd.md`).
- `spawned_from` -- for child designs created from needs-design issues:
  ```yaml
  spawned_from:
    issue: <number>
    repo: <owner/repo>
    parent_design: <relative-path>
  ```

### Required Sections

Every design doc has these sections in order:

1. **Status** -- current lifecycle state
2. **Context and Problem Statement** -- the technical problem being solved
3. **Decision Drivers** -- constraints and priorities shaping the solution
4. **Considered Options** -- at least 1 alternative per decision, so future readers understand it wasn't automatic
5. **Decision Outcome** -- what was chosen and why it works as a whole
6. **Solution Architecture** -- components, interfaces, data flow
7. **Implementation Approach** -- phased build plan
8. **Security Considerations** -- always include; see Security Considerations guidance below
9. **Consequences** -- positive, negative, mitigations

### Context-Aware Sections

Additional sections based on scope and visibility (detect from CLAUDE.md `## Repo Visibility:` and `## Planning Context:` fields):

| Section | Strategic + Private | Strategic + Public | Tactical |
|---------|--------------------|--------------------|----------|
| Market Context | Optional | No | No |
| Required Tactical Designs | Required | Required | No |
| Upstream Design Reference | No | No | If exists |

**Market Context** (after Context and Problem Statement): competitive landscape,
user demand, business opportunity. Only in strategic + private.

**Required Tactical Designs** (after Implementation Approach): table of tactical
designs needed in target repos. Each becomes a needs-design issue via /plan.

**Upstream Design Reference** (after Status): link to parent strategic design with
relevant sections noted.

Detect scope and visibility from CLAUDE.md (`## Repo Visibility:` and
`## Planning Context:` or `## Default Scope:`). If not found, infer
visibility from repo path (`private/` -> Private, `public/` -> Public;
default to Private). After detecting visibility, read the appropriate
content governance skill: `skills/private-content/SKILL.md` or
`skills/public-content/SKILL.md`. Public designs must not reference
private artifacts.

## Lifecycle and Validation

See `references/lifecycle.md` for lifecycle states, transition script, label
lifecycle, validation rules, and quality guidance.

## File Location

`references/lifecycle.md` maps each status to its directory. A superseded
design moves to `docs/designs/archive/DESIGN-<topic>.md`.

---

## Creating a Design Document

When invoked as `/design`, this skill drives a structured creation workflow that
investigates multiple approaches with equal depth before committing to one.

The core pattern is decompose-decide-validate: Phase 1 breaks the design into
independent decision questions. Phase 2 delegates each question to the decision skill
for structured evaluation; under a parent skill, a standard-tier question is
resolved inline instead and a critical one still goes to `/decision`. Phase 3 cross-validates assumptions across decisions to
catch conflicts. Phases 4-6 synthesize architecture, run security review, and finalize.

### Input Modes

From `$ARGUMENTS`:
1. **Empty** -- ask the user what they want to design
2. **Path to accepted PRD** (matches `docs/prds/PRD-*.md` with status "Accepted") -- PRD mode
3. **Anything else** -- freeform topic

### Session and Keys

`/design` keeps its working state as keys in its own koto session,
`design-<topic>`, following
`${CLAUDE_PLUGIN_ROOT}/references/skill-session-convention.md`. It writes no
file to the staging folder, chained or direct. Its first act, once the topic
is known (from the argument, or the `<topic>` in a PRD path's file name) and
before Context Resolution or the resume rows below, opens the session and
records whether it runs under a parent:

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/skill-session.sh" open design <topic>
"${CLAUDE_PLUGIN_ROOT}/scripts/skill-session.sh" adopt design <topic>
```

`open` attaches to a live `design-<topic>` (an interrupted run, whose keys the
resume rows read), replaces a finished one (a fresh run), or creates it. Any
non-zero exit from either command stops the run with the script's message:
127 or 69 means koto is missing or too old, and the skill never falls back to
files. `adopt` exiting 3 is the two-parents case below.

| Key | Written at | Holds |
|-----|-----------|-------|
| `work/decisions.md` | Context Resolution, under `--auto` | the autonomous-decision ledger |
| `work/summary.md` | Phase 0, updated through Phase 5 | the design summary and current phase |
| `work/coordination.json` | Phase 1, updated in Phase 2 | the decision coordination manifest |
| `work/decision_<N>_report.md` | Phase 2 | each decision's report, from `/decision` or resolved inline |
| `work/decision-<N>/<file>` | Phase 2, by `/decision` | a decider's intermediates (`context.md`, `research.md`, `alternatives.md`, `bakeoff_<k>.md`, `examination.md`) |
| `research/phase5_security.md` | Phase 5 | the security researcher's report, ingested |
| `research/phase6_<role>-review.md` | Phase 6 | the final-review jury's reports, ingested |

Keys are read and written with koto against `design-<topic>`: `koto context
exists design-<topic> <key>` tests one (exit 0 present, 1 absent), `koto
context get design-<topic> <key>` prints it, `koto context add design-<topic>
<key>` stores the content given on stdin (the whole content: to change part
of it, get the key, edit it, and add it back), `koto context list
design-<topic> --prefix <prefix>` lists keys, and `koto context remove
design-<topic> <key>` removes one. Research and reviewer agents never write
keys: each phase that spawns them pins every output to a file in a
`skill-session.sh scratch` directory and ingests it. A decider agent in Phase
2 runs the `/decision` skill inside this session, writing the keys its
`decision_context` names.

**Closing.** A direct run closes its session when it finishes:
`"${CLAUDE_PLUGIN_ROOT}/scripts/skill-session.sh" close design-<topic> done`
at Phase 6's end, or `close design-<topic> abandoned` after a Reject's discard
commit. Under a parent `/design` never closes its own session: the parent
closes it at its own exit (`skill-session.sh close-children`), and the keys
stay readable until then.

### Context Resolution

**Execution mode:** check `$ARGUMENTS` for `--auto` or `--interactive` flags,
then CLAUDE.md `## Execution Mode:` header (default: `interactive`). Also
parse `--max-rounds=N` (default: 1 for design's corrective loop). In --auto
mode, follow `${CLAUDE_PLUGIN_ROOT}/references/decision-protocol.md` at all decision points, and
track decisions in key `work/decisions.md` in `design-<topic>`.

Detect visibility and scope as described in Context-Aware Sections above.
For cross-repo source issues, use `gh` commands to read content.

### Resume Logic

```
dispatch read design <topic> prints parent=<session>
                                                          → run under that parent; see ${CLAUDE_PLUGIN_ROOT}/references/fixes/sub-agent-dispatch.md
Design doc status "Accepted"                              → Offer to revise or start fresh
Design doc status "Proposed"                              → Offer to continue
key research/phase5_security.md in design-<topic>         → Resume at Phase 6
Design doc has Solution Architecture                      → Resume at Phase 5
Design doc has Considered Options                         → Resume at Phase 4
key work/coordination.json (all complete)                 → Resume at Phase 3
key work/coordination.json (some pending)                 → Resume at Phase 2
key work/summary.md exists, no work/coordination.json     → Resume at Phase 1
On topic branch, no artifacts                             → Resume at Phase 0
```

**Running under a parent.** The first row runs
`"${CLAUDE_PLUGIN_ROOT}/scripts/skill-session.sh" dispatch read design <topic>`
with the topic this run works on (for a path argument, the `<topic>` in its file name). A printed `parent=<session>`
line means `/design` runs under that parent (`scope-<topic>` or
`charter-<topic>`), with the parent's upfront decision in the `rationale=` and
`suppress_status_aware_prompt=` lines; what changes under a parent is in
`${CLAUDE_PLUGIN_ROOT}/references/fixes/sub-agent-dispatch.md`.
Four cases are no match. Three print nothing and exit 0, and the run is a
direct one with the rows below unchanged: no parent session, a finished parent
session, and a parent whose `chain/dispatch` key names another child. The
fourth, two parent sessions that both name `/design`, exits 3: don't pick one
and don't run directly; stop and report both sessions, which the script names
on stderr, so the author can clear the stale key. Any other non-zero exit
stops the run with the script's message (`open` has already checked koto).
`adopt` has recorded the same match as `chain/parent` in `design-<topic>`, or
removed a `chain/parent` an earlier chained run left.

### Critical Requirements

- **Decision decomposition before execution**: identify all decision questions in Phase 1 before spawning any decision agents in Phase 2
- **Equal-depth investigation**: every decision question gets the same framework treatment at its assigned tier
- **Cross-validation is mandatory**: Phase 3 always runs after Phase 2, even with one decision
- **Topic-scoped state**: every working, research and decision file is a key in `design-<topic>`, never a file in the staging folder

### Output

Final artifact: `docs/designs/DESIGN-<topic>.md` with status "Proposed".

After completion, present the design summary and offer next steps.

Run a complexity assessment based on the design's implementation scope:

| Criterion | Simple | Complex |
|-----------|--------|---------|
| Files to modify | 1-3 | 4+ |
| New tests | Updates only | New test infrastructure |
| API changes | None | Surface changes |
| Cross-package | No | Yes |

Present an AskUserQuestion with the assessment and options, following the pattern
in `${CLAUDE_PLUGIN_ROOT}/references/decision-presentation.md`:
- If Simple: "Plan (Recommended)" / "Approve only"
- If Complex: "Plan (Recommended)" / "Approve only"

**Description field:** Ground the recommendation in the complexity assessment --
name the criteria that landed the design where it did (which files it touches,
whether it changes an API surface, whether it crosses packages), not the Simple
or Complex label alone.

**"Plan":** suggest running `/plan <design-doc-path>` to create implementation issues.

**"Approve only":** stop here; the user handles implementation manually.

**Under `/scope`.** When `/scope`'s dispatch key names `design` (the
Resume Logic's first row), `/design` still reaches its own Phase 6 verdict
(6.7) and makes its own status transition (6.8), and skips everything that
publishes or routes, which `/scope` owns: no push, no pull request, no
branch creation, no cleanup commit, and no routing prompt -- the complexity
assessment and its Plan or Approve question above are not asked. Control
returns to `/scope`, which decides the next hop. An interactive run asks the
author for the verdict as usual; an unattended run (`--auto`, which
`/design` takes from the parent's execution mode) takes the recommended
verdict and names it in its output. This is the Parent-owned-publishing
shape in `${CLAUDE_PLUGIN_ROOT}/references/fixes/sub-agent-dispatch.md`, per
`docs/decisions/DECISION-contradiction-child-steps-under-scope-2026-09-28.md`.

### Execution

Execute phases sequentially by reading the corresponding phase file:

0. **Setup + Context**
   - PRD mode: `references/phases/phase-0-setup-prd.md`
   - Freeform: `references/phases/phase-0-setup-freeform.md`
1. **Decision Decomposition**: `references/phases/phase-1-decomposition.md`
2. **Decision Execution**: `references/phases/phase-2-execution.md`
3. **Cross-Validation**: `references/phases/phase-3-cross-validation.md`
4. **Investigation**: `references/phases/phase-4-architecture.md` (slimmed, implementation focus only)
5. **Security**: `references/phases/phase-5-security.md`
6. **Final Review**: `references/phases/phase-6-final-review.md`

---

## Team Shape

`/design`'s team shape is declared in [`team.yaml`](./team.yaml) as the
machine-readable contract surface. The child layer spawns four peer
roles across three phases: `decision-researcher` (worker,
upper_bound 9, phase-2-execution) walks the decision protocol per
pending architectural question; `security-researcher` (reviewer,
phase-5-security) investigates security implications;
`architecture-reviewer` and `security-reviewer` (reviewers,
phase-6-final-review) jury the final DESIGN.

See [Dispatch Contract](${CLAUDE_PLUGIN_ROOT}/references/parent-skill-pattern.md) for v1 parent-side consumption rules.

## Reference Files

| File | When to load |
|------|-------------|
| `references/lifecycle.md` | Phase 6 (status transitions, label lifecycle, validation) |
| `references/quality/considered-options-structure.md` | When writing Considered Options |
| `shirabe transition <design-path> <status>` (Superseded takes `--superseded-by <path>`) | Status transitions with file movement |
