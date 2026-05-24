# Phase 1 Findings: BRIEF-shirabe-charter-skill (researcher-problem)

Read-only investigation of the problem space for the `/charter` brief.
All references use shirabe-repo paths; no private content is lifted.

## Worktree state vs origin/main (load-bearing)

The current shirabe session worktree (`shirabe-db61668b`, HEAD at
`429c8f0 chore(release): advance to 0.6.2-dev`) does NOT yet contain
the `/strategy` skill or its associated artifacts. Those landed on
`origin/main` at commit `8def921` ("feat(skills): add /strategy skill
and STRATEGY artifact type (#94)"). Until this branch syncs with main,
the following paths exist only via `git show origin/main:...`:

- `skills/strategy/SKILL.md` (and `references/`, `evals/`, `scripts/`)
- `docs/briefs/BRIEF-shirabe-strategy-skill.md` (the exemplar)
- `docs/prds/PRD-shirabe-strategy-skill.md`
- `docs/designs/current/DESIGN-shirabe-strategy-skill.md`

There is no `docs/briefs/` or `docs/strategies/` or `docs/visions/`
directory in the worktree HEAD. `docs/roadmaps/` exists and holds
`ROADMAP-strategic-pipeline.md` and `ROADMAP-koto-adoption.md`.

This matters for the brief because the team-shape calls the strategy
BRIEF "the exemplar"; that exemplar is committed but not present on
the active branch. Anyone authoring the charter brief locally needs
to read it via `git show origin/main:docs/briefs/BRIEF-shirabe-strategy-skill.md`
or rebase onto origin/main.

## Lead 1: `/strategy` SKILL.md actual shape (origin/main)

Source: `git show origin/main:skills/strategy/SKILL.md`.

**Phase count:** Six (0..5).

**Phase names:**
- Phase 0: Setup (branch + visibility/scope + slug + path validation)
- Phase 1: Discover (scoping conversation + upstream VISION grounding)
- Phase 2: Draft (Strategic Context, Defensibility Thesis, Falsifiability)
- Phase 3: Structural Fill (Building Blocks, Coordination, Non-Goals, Downstream Artifacts)
- Phase 4: Validate (three-reviewer parallel jury)
- Phase 5: Finalize (human approval + Draft -> Accepted transition)

**Reference-files structure** (eight entries in the closing table):

```
references/strategy-format.md             -> Phases 2, 3, 4
references/phases/phase-0-setup.md        -> Phase 0
references/phases/phase-1-discover.md     -> Phase 1
references/phases/phase-2-draft.md        -> Phase 2
references/phases/phase-3-structural-fill.md -> Phase 3
references/phases/phase-4-validate.md     -> Phase 4
references/phases/phase-5-finalize.md     -> Phase 5
scripts/transition-status.sh              -> lifecycle transitions
```

**Resume-logic shape:** Seven-line ladder, top-to-bottom, first match
wins. Checks artifact status first (Accepted/Active offers revise-or-start-fresh;
Draft offers continue from Phase 2 or 3), then verdict files,
then partial-section presence, then scope file, then branch name,
then defaults to Phase 0. Pattern: status-first, then artifact-presence
ladder, then branch detection.

**Input-modes pattern:** Four numbered modes from `$ARGUMENTS`:
1. Empty -> ask user
2. Path to existing STRATEGY + lifecycle verb (`accept`, `activate`,
   `sunset`) -> dispatch `scripts/transition-status.sh`
3. Path to a VISION document (matches `docs/visions/VISION-*.md`) ->
   treat as upstream
4. Anything else -> topic string for Phase 1

Adds execution-mode parsing (`--auto`, `--interactive`, `--max-rounds=N`)
as a Context Resolution sub-block, plus a topic-slug constraint
(`[a-z0-9-]+`) and upstream-path canonicalization (reject anything
resolving outside the working tree) in Phase 0.

**SE3 work-in-progress in this worktree:** None local. The skill,
its phase refs, the BRIEF/PRD/DESIGN/PLAN, the format reference, and
the validate-CLI extension all landed atomically on origin/main in
PR #94 and are absent from `session/db61668b`'s HEAD. There is no
local-only WIP that the charter brief would shadow.

## Lead 2: `/explore` SKILL.md shape and phase references

Source: `skills/explore/SKILL.md` (present in this worktree).

**Phase count:** Six (0..5) with orchestrator-managed loop after Phase 3.

**Phase names:** Setup, Scope, Discover, Converge, Crystallize, Produce.

**Phase reference files** (under `references/phases/`):

```
phase-0-setup.md
phase-1-scope.md
phase-2-discover.md
phase-3-converge.md
phase-4-crystallize.md
phase-5-produce.md                  (routing stub)
phase-5-produce-prd.md
phase-5-produce-design.md
phase-5-produce-plan.md
phase-5-produce-vision.md
phase-5-produce-roadmap.md
phase-5-produce-decision.md
phase-5-produce-rejection-record.md
phase-5-produce-deferred.md
phase-5-produce-no-artifact.md
```

Plus `references/quality/crystallize-framework.md` loaded in Phase 4.
The `label-reference.md` is a third top-level reference.

**Discover/converge engine extractability.** The `phase-2-discover.md`
and `phase-3-converge.md` files are written as self-contained
instructions parameterized by topic prefix; they read from a scope
file and write to topic-scoped wip/ paths. The orchestrator logic
that loops them (in `SKILL.md` body, lines 233-277, including the
AskUserQuestion prompt template and round-incrementing rules) is the
harder-to-extract piece — it is prose-encoded in the SKILL.md itself.
The five `phase-5-produce-<artifact>.md` files form a per-target
handoff family that any orchestrator skill could reuse by writing
`wip/<child>_<topic>_scope.md` and invoking the child slash command.

**No `skills/_shared/` convention exists in this worktree.** Searched
both `skills/_shared/` and any directory named `_shared` under `skills/`.
None present. Shared content currently lives at plugin root
(`${CLAUDE_PLUGIN_ROOT}/references/decision-presentation.md`,
`references/decision-protocol.md`) and inside individual skill
`references/` trees. Top-level `references/` (sibling to `skills/`)
does exist and holds `pipeline-model.md`, `cross-repo-references.md`,
etc. — that is the precedent location if `/charter` wants extracted
shared content.

## Lead 3: BRIEF and PRD precedents for `/strategy`

Sources: `git show origin/main:docs/briefs/BRIEF-shirabe-strategy-skill.md`
and `git show origin/main:docs/prds/PRD-shirabe-strategy-skill.md`.

**BRIEF (279 lines).** Frontmatter: `schema: brief/v1`, `status: Draft`,
`problem:` block scalar, `outcome:` block scalar. Body sections:

- Status
- Problem Statement
- User Outcome
- User Journeys (four journeys: standalone author, ROADMAP author
  tracing upstream, public-repo adopter, jury review and acceptance)
- Scope Boundary (explicit "inside" and "explicitly excludes" halves)
- Open Questions (three: acceptance trigger, sunset semantics,
  Building Blocks granularity rubric — all flagged "for the
  downstream PRD to resolve")
- Downstream Artifacts (names PRD-shirabe-strategy-skill.md and
  likely DESIGN-shirabe-strategy-skill.md)
- References (format-spec template precedents, jury precedent,
  skill structure template, validate CLI extension point)

**Problem Statement framing.** Four-part gap decomposition: no skill
entry point, no format reference, no validation discipline, no jury
rubric. Each part is one bullet with a one-sentence consequence.
The framing leads with "shirabe today recognizes five artifact types"
to ground the gap inside the existing taxonomy before naming what's
missing. The gap is described in three altitudes (entry point ->
format -> validation -> review) which mirrors the artifact lifecycle.

**User Outcome altitude.** Destination narrative, not requirements.
Opens with "A skill author opens Claude Code in a repo where a
strategic conversation needs to happen..." and walks through what
the user experiences: invoke, phased authoring, format reference,
jury, finalization, downstream traceability via `upstream:` frontmatter,
CI validation through the reusable workflow, marketplace propagation
to adopters. Stays at user-experience altitude; the PRD is flagged
as the place that owns requirements, jury rubric, format-spec
details, and validate-CLI checklist.

**Open Questions deferred to PRD.**
1. Acceptance trigger (jury PASS alone vs jury PASS + human ratification)
2. Sunset semantics (upstream pivot vs downstream completion vs
   explicit decision)
3. Building Blocks granularity rubric (block-count ranges vs
   block-to-downstream-artifact ratio vs scope-based)

Each question states the candidates and explicitly names "the PRD
picks one." None are open questions about the brief's own framing —
they are questions about format details the brief intentionally
doesn't resolve.

**PRD shape** (not deeply inspected — out of brief's scope but useful
context): exists at `docs/prds/PRD-shirabe-strategy-skill.md` on
origin/main. It is the downstream artifact the brief points at.

**Precedent the charter brief follows verbatim:** the four-part Gap
decomposition pattern in Problem Statement, the destination-narrative
voice in User Outcome, the explicit "for the downstream PRD" handling
of Open Questions, and the dual-half Scope Boundary
(inside / explicitly excludes).

## Lead 4: Parent-skill patterns (`/explore`, `/decision`)

Sources: `skills/explore/SKILL.md`, `skills/decision/SKILL.md`
(both present in this worktree).

**What makes them "parent" skills.**

`/explore` is parent in two senses: it routes (passive — recommends
which artifact-producing skill to invoke) and it orchestrates (active —
fans out research agents, then hands off to a per-artifact phase-5
file that invokes a downstream skill like `/prd`, `/design`, `/plan`,
`/vision`, `/roadmap`). The handoff pattern (`phase-5-produce-<X>.md`)
writes a `wip/<X>_<topic>_scope.md` file and either invokes the
slash command directly or returns a recommendation to the user. The
downstream skill detects the handoff file and skips its own scoping
phase. This is the cleanest precedent for `/charter`'s child
invocation (parent writes handoff scope; child consumes it).

`/decision` is parent in the agent-hierarchy sense: it spawns
research agents (disposable, Phase 1), alternative agents (disposable,
Phase 2), and validator agents (persistent across Phases 3-5 via
SendMessage). Documents a Level-1/Level-2/Level-3 hierarchy
explicitly in the SKILL.md body. Has a `decision_context` /
`decision_result` YAML interface for being invoked as a
sub-operation by a parent skill (e.g., /design). This is the
precedent for `/charter` being invoked AS a child (or for `/charter`
itself accepting structured input from `/explore`).

**Where they delegate.**

`/explore` delegates research within Phase 2 (one agent per lead,
all spawned in parallel via background tasks; converge in Phase 3
aggregates without spawning new agents). Phase 5 doesn't really
delegate — it invokes a slash command and exits the explore process.

`/decision` delegates per-phase: research agents (1) in Phase 1,
alternative agents (N options) in Phase 2, validator agents (N) in
Phase 3, persistent re-messaging of the same validators in Phases
4-5. The validator-persistence pattern (re-message via SendMessage
rather than re-spawn) is the most novel piece — it lets the
decision skill orchestrate multi-round adversarial debate without
context loss.

`/strategy` delegates only in Phase 4 — three reviewers spawned in
parallel via `run_in_background: true`, each prompt self-contained
(no shared memory), orchestrator aggregates verdicts. Simpler than
`/decision`'s persistent-validators pattern, more elaborate than
`/explore`'s research fan-out (which is round-based).

**How they handle resume across phases.**

All three use a resume-logic block: a top-to-bottom ladder, first
match wins, checking artifact presence in order from most-advanced
to least-advanced state.

- `/explore`: scope file -> research files (no findings) ->
  findings file (no crystallize marker) -> findings file (with
  marker) -> crystallize artifact exists. Six conditions.
- `/decision`: report exists -> examination exists -> bakeoff files
  exist -> alternatives -> research -> context. Six conditions.
- `/strategy`: status-first (Accepted/Active or Draft) THEN file
  ladder THEN branch detection. Seven conditions.

`/strategy`'s status-first pattern is the right precedent for
`/charter` because `/charter` produces a STRATEGY (durable terminal)
that has a non-trivial lifecycle; the resume question "should we
start fresh or continue this draft" is real. `/explore` doesn't have
that concern (findings files are always transient).

## Lead 5: Existing strategic-progression artifacts (filenames only)

Searched `docs/strategies/`, `docs/roadmaps/`, `docs/visions/` in
this worktree:

- `docs/visions/` — does not exist in this worktree HEAD.
- `docs/strategies/` — does not exist in this worktree HEAD.
- `docs/roadmaps/` — exists. Contains:
  - `ROADMAP-koto-adoption.md`
  - `ROADMAP-strategic-pipeline.md`

On origin/main, the same three directories: `docs/visions/` is
absent there too; `docs/strategies/` is absent (the STRATEGY artifact
type was added to validation in PR #94 but no STRATEGY document was
committed to shirabe itself on origin/main); `docs/roadmaps/` has
the same two files.

Adjacent strategic-flavored artifacts on origin/main:
- `docs/briefs/BRIEF-shirabe-strategy-skill.md` (Draft, the exemplar)
- `docs/prds/PRD-shirabe-strategy-skill.md` (status not inspected)
- `docs/designs/current/DESIGN-shirabe-strategy-skill.md` (Current)
- `docs/spikes/SPIKE-claude-code-goal-integration.md`

**What authors have to reach for today.** In the shirabe public
repo, the only strategic-altitude artifact authors can write
without `/charter` is a ROADMAP (sequenced features) — and the
existing ROADMAP-strategic-pipeline.md is itself the artifact
driving the strategic-pipeline completion that includes `/charter`.
There is no VISION, no STRATEGY, and no COMP authored in
shirabe today. The /vision skill ships at `skills/vision/SKILL.md`
and /roadmap ships at `skills/roadmap/SKILL.md` (both Feature 1 and
Feature 2 in ROADMAP-strategic-pipeline.md, both Done). But the
strategic-chain author has nothing public to point at as a
working example beyond the strategy-skill BRIEF/PRD/DESIGN trio.

This shapes the charter brief's Problem Statement: the gap isn't
that authors can't write strategic documents (they can — /vision
and /roadmap ship). The gap is the *parent orchestration* — there's
no single skill that takes a strategic conversation from "I have an
idea" through optional VISION update, optional COMP, required
STRATEGY, optional ROADMAP, with the right transitions between
them. Today the author has to know to invoke each skill in the
right order, and the artifact-decision logic ("do I need a COMP?
is the bet ripe enough for a STRATEGY?") lives in author memory.

## Summary for the brief coordinator

**Problem Statement framing the brief can adopt.** The four-part
gap pattern from BRIEF-shirabe-strategy-skill maps cleanly:

1. **No parent entry point.** Authors invoke /vision, /strategy,
   /roadmap individually in best-guess order.
2. **No artifact-decision orchestration.** The "should we run
   /comp?" or "is this STRATEGY ripe enough?" question lives in
   author memory; no skill makes it explicit.
3. **No chain-level resume.** If a strategic conversation is paused
   mid-progression (VISION drafted, STRATEGY in scope phase), there's
   no single resume entry point.
4. **No review-time redirect surface.** STRATEGY Block 5 commits to
   human redirect during progression; no skill implements the
   pickup-from-redirect behavior.

**User Outcome altitude the brief can hold.** A skill author opens
Claude Code in a repo where a strategic conversation needs to
happen. They invoke `/charter`. The skill scopes the strategic
question, decides which children to invoke (always /strategy; optionally
/vision, /comp, /roadmap based on signals), walks through each in
the right order with handoff scope files, and surfaces artifact-
decision and transition gates to the user at the right moments. The
output is a coordinated set of artifacts (STRATEGY always; VISION,
COMP, ROADMAP conditionally) with frontmatter `upstream:` chains
that link cleanly.

**Open Questions to defer to the downstream PRD.** Candidates that
emerged during research (each is a question about how /charter
behaves, not about whether it should exist):

- Should /charter be invocable as a child of /explore (auto-handoff
  from crystallize when artifact-type scores Strategic), or
  standalone-only at first?
- Where does the artifact-decision logic live: SKILL.md body prose,
  a `references/artifact-decision.md` shared file, or per-child
  evidence-check stubs in each phase reference?
- How does /charter handle the case where /strategy returns
  evidence-only (Block 4's abandonment-forces-materialization path)
  vs returns a Draft STRATEGY?
- Does /charter's resume ladder check each child's artifact status
  independently, or does it use a single `wip/charter_<topic>_state.md`
  file as the source of truth?

**Scope Boundary likely shape.**

Inside:
- /charter SKILL.md following the /strategy/explore template family
- Phase set covering optional /vision, optional /comp,
  required /strategy, optional /roadmap as child invocations
- Resume ladder that handles partial completion across children
- Handoff scope file format (per-child, written by /charter,
  consumed by child) — likely a generalization of
  `phase-5-produce-vision.md` / `phase-5-produce-roadmap.md` shape

Explicitly excludes:
- Modifications to /vision, /strategy, /roadmap themselves
  (children must work standalone today and through /charter)
- /comp skill itself (SE11 on the roadmap; /charter invokes it
  when available but doesn't author it)
- Review-time redirect MECHANISM (STRATEGY Block 5 commits the
  intent; the mechanism is downstream feature work)
- Auto-invocation from /explore (defer to a later integration once
  /charter standalone ships and stabilizes)

**Verification note for the coordinator's Problem Statement
drafting.** The charter brief is being authored while the worktree's
HEAD does NOT have /strategy locally. Any "follows the /strategy
pattern" prose in the brief should cite the SKILL.md by path
(`skills/strategy/SKILL.md`) rather than quoting lines that aren't
reachable from the current HEAD. The exemplar BRIEF lives at
`docs/briefs/BRIEF-shirabe-strategy-skill.md` on origin/main; the
brief coordinator can read it via `git show origin/main:...` or
ask for a rebase before drafting.
