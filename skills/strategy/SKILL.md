---
name: strategy
description: >-
  Work out what you are betting on over the next few quarters and what would
  prove it wrong: the angle, the pieces that have to land for it to hold, who
  else has to move, and the signal that would say it was the wrong call. Use
  it when the direction matters more than the feature list — "what's our
  angle here?", "what are we actually betting on?", "what has to be true for
  this to work?", "how would we know if this was the wrong call?", "how do we
  avoid getting commoditized?", "why would this still matter in a year?" —
  and also when you are holding a settled feature spec and the real question
  is the bet behind it. Left unwritten, the bet lives in one person's head and
  nothing can falsify it. Do NOT use it to argue why the project should exist
  at all (`/vision`), to order the features that carry the bet (`/roadmap`),
  or to pick between options already named (`/decision`). When more than one
  of those is open at once, `/charter` runs them together.
argument-hint: '<project or org topic, optional VISION or PRD path, or STRATEGY path + lifecycle verb> [--upstream <path>]'
allowed-tools: Bash(bash ${CLAUDE_PLUGIN_ROOT}/scripts/skill-preflight.sh *), Bash(true)
---

!`bash ${CLAUDE_PLUGIN_ROOT}/scripts/skill-preflight.sh strategy 2>&1 || true`

@.claude/shirabe-extensions/strategy.md
@.claude/shirabe-extensions/strategy.local.md

# Strategy Documents

STRATEGY documents capture the medium-term bet a project commits to
when operationalizing a piece of an upstream VISION. They sit between
VISION (long-term aspiration, years) and ROADMAP (sequenced features)
at medium-term defensibility altitude. Each STRATEGY names a
falsifiable hypothesis, decomposes it into coherent building blocks,
maps coordination dependencies, and lists per-direction invalidation
conditions so the team can recognize when the bet has been wrong.

A STRATEGY links one level in each direction: its upstream is a VISION,
and its Downstream Artifacts are ROADMAPs. Keeping the links strict is
what makes the chain walkable -- a reader moving VISION -> STRATEGY ->
ROADMAP hits every altitude in order rather than landing two levels down
with the reasoning in between skipped. The ROADMAP is the boundary
between the strategic chain and the tactical one, and `/brief` is what
crosses it, so a STRATEGY never links a PRD, DESIGN, or PLAN directly.

A PRD can still ground the conversation — `/strategy
docs/prds/PRD-<name>.md` reads one to derive the bet, and an author
holding a feature PRD who wants the medium-term bet behind it has a
real strategy to write. But reading a document and recording it as the
strategy's parent are different acts. `upstream:` takes a VISION or
nothing; a strategy grounded in a PRD with no VISION above it omits the
field and names the PRD in Strategic Context prose.

**Writing style:** Read `skills/writing-style/SKILL.md` for guidance.

## Artifact Lifecycle

**Lifecycle:** Durable. Stays in `docs/strategies/` after completion.

STRATEGY is durable because the medium-term bet — the falsifiable claim a project pursues — stays in the audit trail. Future readers reviewing which strategic direction was taken need the STRATEGY to remain in place.

## Strategy Format

See `references/strategy-format.md` for the full format specification:
frontmatter schema, required and optional sections, visibility-gated
sections, section matrix, content boundaries, lifecycle states,
validation rules, and quality guidance. Load it during Phases 2, 3,
and 4.

## File Location

STRATEGY documents live at `docs/strategies/STRATEGY-<topic>.md`
(kebab-case). No directory movement until Sunset, which moves files
to `docs/strategies/sunset/`. Stable paths keep cross-references
durable and git blame readable.

## Repo Visibility

Before writing content, detect visibility from CLAUDE.md
(`## Repo Visibility: Public|Private`). If not found, infer from
repo path (`private/` -> Private, `public/` -> Public; default to
Private). Load the appropriate content governance skill:

- **Private repos:** Read `skills/private-content/SKILL.md`
- **Public repos:** Read `skills/public-content/SKILL.md`

Public STRATEGYs must not include a Competitive Considerations
section, and must not reference private artifacts. The R8 custom
check in `shirabe validate` enforces the section rule mechanically;
the upstream-reference rules are enforced by content governance.

---

## Creating a Strategy Document

When invoked as `/strategy`, this skill drives a six-phase workflow
that scopes the bet conversationally, drafts the foundational
sections, decomposes into building blocks, runs a three-reviewer
jury, and finalizes through explicit human approval.

The skill produces a STRATEGY document. Use `/strategy` when the work
needs medium-term defensibility framing (a falsifiable bet, named
invalidation conditions, building-block decomposition). Use
`/vision` if the conversation is long-term identity. Use `/roadmap`
when the bet is already settled and what's needed is feature
sequencing.

### Input Modes

From `$ARGUMENTS`:

1. **Empty** — ask the user what bet they want to articulate.
2. **Path to existing STRATEGY** with lifecycle verb (`accept`,
   `activate`, `sunset`) — execute the lifecycle transition via
   `shirabe transition <strategy-path> <status>`. Sunset requires a
   reason: `shirabe transition <strategy-path> Sunset --reason "<text>"`.
3. **Path to a VISION document** (matches `docs/visions/VISION-*.md`)
   — treat as the upstream VISION for the new STRATEGY; derive the
   bet candidate from upstream content during Phase 1, and record the
   path as the draft's `upstream:`.
4. **Path to a PRD document** (matches `docs/prds/PRD-*.md`) — read as
   grounding for the bet during Phase 1. The PRD is not recorded as the
   STRATEGY's `upstream`, per the read-vs-record rule above; if no
   VISION sits above the strategy, the draft omits the field.
5. **Anything else** — use as the starting topic for Phase 1 scoping.

Any of the modes above may carry `--upstream <path>`, naming the
upstream VISION separately from the topic. `/strategy <topic-slug>
--upstream docs/visions/VISION-<name>.md` produces
`STRATEGY-<topic-slug>.md` recording that VISION as its upstream —
the slug comes from the positional argument and the upstream from
the flag, so the two need not share a name. Input Mode 3 is the
special case where they do: a bare VISION path supplies both at
once, which only works while the strategy's topic and the vision's
filename coincide.

The flag is parsed before the positional argument is classified,
and its value is never treated as a topic. A bare `--upstream` with
no value is rejected at Phase 0 naming the missing argument. The
value must name a VISION: the same basename rule Input Mode 3
enforces applies to the flag, because both feed the same recorded
`upstream:` field. A grounding PRD (Input Mode 4) is never passed
this way — it is read, not recorded, and the flag is the recording
route.

### Context Resolution

**Execution mode:** check `$ARGUMENTS` for `--auto` or `--interactive`
flags, then CLAUDE.md `## Execution Mode:` header (default:
`interactive`). In `--auto` mode, make decisions based on evidence
rather than blocking on user input. Create
`wip/strategy_<topic>_decisions.md` to track decisions.

**Topic slug constraint.** The `<topic>` slug used in wip/ paths and
the STRATEGY filename must match `[a-z0-9-]+` (kebab-case lowercase
alphanumeric, hyphens only). Phase 0 enforces this constraint by
rejecting any topic that contains other characters, including `.`,
`/`, `_`, or whitespace. Without the constraint, `../`-shaped topics
could redirect verdict writes outside `wip/research/`.

**Upstream:** check `$ARGUMENTS` for `--upstream <path>`. If
present, the path is validated at Phase 0 and stored as the
context file's `## Recorded Upstream`; Phase 2 writes it into the
STRATEGY's frontmatter. It points to the VISION this strategy
operationalizes — the strategy's immediate neighbour one level up
the strategic chain. `/charter` passes it on every chain where a
VISION is available; an author invoking `/strategy` standalone
passes it when a VISION exists that the topic slug does not name.
When no VISION exists, omit the flag rather than reaching past the
neighbour; the upstream field is then omitted from frontmatter.

**Path canonicalization.** Any user-supplied VISION or PRD path
(Input Modes 3 and 4) and any `--upstream` value must be
canonicalized at Phase 0 and rejected if the canonical path
resolves outside the repo working tree. Symlinks resolving to
arbitrary filesystem content would otherwise leak into a
public commit.

Detect visibility (Private/Public) from CLAUDE.md or repo path.
Infer from `private/` or `public/` in path if not explicit. Default
to Private if unknown — restricting is easier to undo than
oversharing.

Log: `Drafting strategy with [Private|Public] visibility...`

### Workflow Phases

```
Phase 0: SETUP --> Phase 1: DISCOVER --> Phase 2: DRAFT --> Phase 3: STRUCTURAL FILL --> Phase 4: VALIDATE --> Phase 5: FINALIZE
(branch +         (scope + upstream     (Context, Thesis,  (Building Blocks,             (3-reviewer        (approval +
 visibility)       grounding)            Falsifiability)    Coordination, Non-Goals,     jury)               transition)
                                                            Downstream Artifacts)
                                                                                          |
                                                                                          v (FAIL loops back to Phase 2 or 3)
```

| Phase | Purpose | Artifact |
|-------|---------|----------|
| 0. Setup | Branch, visibility/scope detection, slug + path validation | On topic branch |
| 1. Discover | Scoping conversation; ground bet in upstream VISION if any | `wip/strategy_<topic>_scope.md` |
| 2. Draft | Strategic Context, Defensibility Thesis, Bet-Specific Falsifiability | Partial STRATEGY draft |
| 3. Structural Fill | Building Blocks, Coordination Dependencies, Non-Goals, Downstream Artifacts | Complete STRATEGY draft |
| 4. Validate | Three parallel reviewers (bet quality, altitude, structural format) | Verdict files + aggregated decision |
| 5. Finalize | Explicit human approval, Draft -> Accepted transition, PR | Accepted STRATEGY |

Phase 4 jury runs three reviewers in parallel:

- **Bet quality** — falsifiability of the Defensibility Thesis; named
  invalidation conditions per Falsifiability direction.
- **Altitude** — operates at medium-term defensibility (carries
  upstream VISION content without re-justifying long-term thesis;
  defers sequenced feature decomposition to ROADMAP). Applies the
  Building Blocks granularity rubric defined in
  `references/strategy-format.md`.
- **Structural format** — all required sections present and ordered;
  frontmatter valid; visibility-gated section honored; Downstream
  Artifacts entries point at durable paths.

All three must PASS before Phase 5 begins.

### Resume Logic

```
parent_orchestration sentinel in wip/scope_<topic>_state.md or wip/charter_<topic>_state.md
                                                         -> see references/fixes/sub-agent-dispatch.md
STRATEGY exists with status "Accepted" or "Active"       -> Offer to revise or start fresh
STRATEGY exists with status "Draft"                      -> Offer to continue from Phase 2 or 3
wip/research/strategy_<topic>_phase4_*.md files exist    -> Resume at Phase 4 (aggregate)
STRATEGY has Building Blocks section                     -> Resume at Phase 4
STRATEGY has Defensibility Thesis section                -> Resume at Phase 3
wip/strategy_<topic>_scope.md exists                     -> Resume at Phase 2
On a branch related to the topic                         -> Resume at Phase 1
On main or unrelated branch                              -> Start at Phase 0
```

Phase 0 detection: if the parent-chain sentinel is present in
`wip/scope_<topic>_state.md` (tactical) or `wip/charter_<topic>_state.md`
(strategic), see `references/fixes/sub-agent-dispatch.md` for the
fallback shape that applies. Behavior under direct invocation is
unchanged when the sentinel is absent.

### Critical Requirements

- **Topic-slug constraint:** Phase 0 rejects topics not matching
  `[a-z0-9-]+`. Non-compliant topics never reach later phases.
- **Path canonicalization:** Phase 0 canonicalizes and bounds-checks
  any user-supplied upstream path, whether it arrived positionally
  or as the `--upstream` flag's value.
- **Slug independence:** the topic slug is never derived from the
  `--upstream` value. A flag-supplied upstream names the strategy's
  parent, not the strategy.
- **Conversational scoping:** Phase 1 is a dialogue, not a form to
  fill out. Org-scope STRATEGYs without an upstream VISION need this
  conversation to ground Strategic Context.
- **Jury parallelism:** Phase 4 spawns the three reviewer agents with
  `run_in_background: true`. Each reviewer's prompt is self-contained
  (no shared memory); the orchestrator aggregates verdicts.
- **Human approval gate:** Phase 5 requires explicit human approval
  via AskUserQuestion before Draft -> Accepted. Jury PASS alone does
  not transition status.
- **Visibility hygiene:** Public STRATEGYs must not surface
  Competitive Considerations content (R8 rejects mechanically). Phase
  2 warns authors when quoting from private-upstream content into a
  public-visibility STRATEGY (requires manual sanitization).

### Execution

Execute phases sequentially by reading the corresponding phase file:

0. **Setup**: branch + visibility/scope detection + slug + path validation
   - Instructions: `references/phases/phase-0-setup.md`

1. **Discover**: scoping conversation + upstream grounding
   - Instructions: `references/phases/phase-1-discover.md`

2. **Draft**: Strategic Context, Defensibility Thesis, Falsifiability
   - Instructions: `references/phases/phase-2-draft.md`

3. **Structural Fill**: Building Blocks, Coordination, Non-Goals, Downstream
   - Instructions: `references/phases/phase-3-structural-fill.md`

4. **Validate**: three-reviewer jury (parallel agents)
   - Instructions: `references/phases/phase-4-validate.md`

5. **Finalize**: approval + status transition + PR
   - Instructions: `references/phases/phase-5-finalize.md`

### Output

Final artifact: `docs/strategies/STRATEGY-<topic>.md`, created in
Draft status. After explicit user approval at Phase 5, transition to
Accepted via `shirabe transition <strategy-path> Accepted`.

After acceptance, suggest next steps:

| Situation | Suggestion |
|-----------|-----------|
| Building Blocks decomposed into discrete features | `/roadmap` to sequence them |
| Single building block has clear requirements | `/prd` to write requirements for it |
| Bet needs broader organizational alignment | Share STRATEGY for stakeholder review |
| Strategic question still open | `/explore` to investigate further |

---

## Team Shape

`/strategy`'s team shape is declared in [`team.yaml`](./team.yaml) as
the machine-readable contract surface. The child layer spawns three
reviewer peers at Phase 4 (`bet-quality-reviewer`, `altitude-reviewer`,
`structural-format-reviewer`) to validate the drafted STRATEGY.

See [Dispatch Contract](${CLAUDE_PLUGIN_ROOT}/references/parent-skill-pattern.md) for v1 parent-side consumption rules.

## Reference Files

| File | When to load |
|------|-------------|
| `references/strategy-format.md` | Phases 2, 3, 4 (drafting + validation) |
| `references/phases/phase-0-setup.md` | Phase 0 |
| `references/phases/phase-1-discover.md` | Phase 1 |
| `references/phases/phase-2-draft.md` | Phase 2 |
| `references/phases/phase-3-structural-fill.md` | Phase 3 |
| `references/phases/phase-4-validate.md` | Phase 4 |
| `references/phases/phase-5-finalize.md` | Phase 5 |
