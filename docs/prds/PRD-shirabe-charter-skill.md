---
status: Draft
problem: |
  shirabe ships VISION, STRATEGY, and ROADMAP as loadable child skills
  that authors invoke directly, but has no parent skill that walks an
  author through the strategic chain as a sequence. Authors re-derive
  sequencing decisions per run, carry context between children
  manually, have no resume contract across child boundaries, and have
  no enforcement that the conversation produces a durable terminal
  artifact. Without `/charter`, the strategic chain's three-rule
  terminal-artifact contract is unenforceable, the
  discipline-vs-artifact decoupling collapses into ad-hoc artifact
  churn, and the parent-skill pattern has no validation point for the
  two follow-on parent skills (`/scope` and the `/work-on` migration)
  to inherit from.
goals: |
  An author reaches for `/charter` the way they reach for `/strategy`
  or `/vision` today: a loadable parent skill with a phased
  orchestration ladder, conditional invocation of the strategic-chain
  children (`/vision`, `/comp`, `/strategy`, `/roadmap`), a resume
  contract that picks up mid-chain across child boundaries, and three
  first-class exit paths (full-run, re-evaluation Decision Record,
  abandonment-forced materialization). The strategic chain becomes
  durable infrastructure rather than a manual sequencing discipline,
  and `/charter` ships as the validation point for the parent-skill
  pattern that `/scope` and the `/work-on` migration will inherit.
upstream: docs/briefs/BRIEF-shirabe-charter-skill.md
---

# PRD: shirabe-charter-skill

## Status

Draft.

## Problem Statement

shirabe today ships `/vision`, `/strategy`, and `/roadmap` as
loadable child skills at the strategic chain's altitude. Each child
runs as a standalone skill an author invokes by hand. The chain has
no parent: no skill walks an author through the conversation as a
*sequence*, deciding which children to invoke, carrying context
between them, or enforcing terminal-artifact guarantees.

In the absence of a parent skill, authors today reach for the chain
as three separate invocations, with a fourth (`/comp`, for
competitive analysis in private repos) parallel to the chain but
unshipped in shirabe core. This costs authors in three ways. They
re-derive the sequencing decisions on every run — when does a vision
update fire? when is a roadmap warranted? They carry context between
children manually, with no resume contract if the session breaks
between children. And they have no enforcement that the conversation
produces a durable terminal artifact: paused or abandoned chains
leave evidence files in `wip/` with no review surface.

The deeper problem is that the strategic chain has invariants that
cannot be enforced in the absence of `/charter`. Three exits — every
chain ends at a durable artifact for human review; re-evaluation of
a healthy upstream is a first-class lightweight exit; paused or
abandoned chains force-materialize the most-recent intermediate —
none survive a manual chain. The discipline-vs-artifact decoupling,
the principle that strategic work can be *disciplined* without being
forced to *produce*, depends on a parent skill that enforces the
three exits. Without it, every strategic conversation tempts the
author into a STRATEGY revision regardless of whether one is
warranted, and the discipline collapses into ad-hoc artifact
creation.

Downstream, `/charter`'s shipping validates the parent-skill pattern
for the two siblings that follow: `/scope` will inherit the same
parent/child shape, and the future `/work-on` migration will pivot
from its current substrate into the same pattern. `/charter` is not
just a new skill — it is the first instance of the parent-skill
infrastructure shirabe commits to.

## Goals

- An author invokes `/charter` and is walked through the strategic
  chain without remembering the order, the
  artifact-decision heuristics, or the visibility gating.
- The chain ends at exactly one of three named exit paths (full-run,
  re-evaluation, abandonment-forced). A fourth shape — explicit
  `/strategy` Reject — maps to abandonment-forced with the git
  history as the audit surface.
- The chain is resumable mid-flight across child boundaries. Author
  bails are routed to abandonment-forced; never to silent loss.
- Manual fallback (author invokes a child directly outside
  `/charter`) is first-class steady-state capability. `/charter`
  warns about staleness but never acts unilaterally.
- The four `/charter` → child delegation contracts are documented at
  requirements altitude precise enough that the downstream design
  doc (`docs/designs/DESIGN-shirabe-progression-authoring.md`) can
  lift pattern-level commitments into shared design and leave
  `/charter`-specific bindings in `/charter`'s scope.

## User Stories

The four user stories correspond to the four User Journeys in the
upstream brief. Each story names the trigger, the chain shape, the
exit, and what an author reviews after the run.

### US-1: Cold standalone invocation (full-run)

As a **skill author** with a strategic bet to pressure-test from
scratch, I want to invoke `/charter <topic-slug>` and be walked
through discovery, optional `/vision`, optional `/comp` (private
repos only), required `/strategy`, and optional `/roadmap` without
remembering the chain order or the artifact-decision rules, so that
I land at one or two Draft artifacts ready for human review.

Chain shape: `/charter` Phase 1 discovery → optional `/vision` (only
if thesis-shift signal surfaces in discovery) → optional `/comp`
(private repos with `/comp` shipped only) → `/strategy` (always) →
optional `/roadmap` (only if STRATEGY's Building Blocks count is 3+
with explicit Coordination Dependencies) → full-run exit.

What I review at end: the Draft STRATEGY at
`docs/strategies/STRATEGY-<topic>.md`, plus the Draft ROADMAP at
`docs/roadmaps/ROADMAP-<topic>.md` if `/roadmap` ran. State file at
`wip/charter_<topic>_state.md` records `exit: full-run`.

### US-2: Re-evaluation (the load-bearing story)

As a **skill author** returning to a strategic topic weeks after the
original `/charter` run landed an Accepted STRATEGY, with new
evidence to assess, I want `/charter` to walk me through a
re-evaluation that concludes whether the bet still holds — and, when
it does, to produce a Decision Record rather than force a redundant
STRATEGY revision, so that strategic discipline is empirically
demonstrated without artifact churn.

Chain shape: `/charter` Phase 1 detects existing Accepted STRATEGY →
asks "Re-evaluate / Revise / Bail" as the entry router → walks
through each Bet-Specific Falsifiability claim from the existing
STRATEGY with per-claim evidence prompts → if all claims hold,
proceeds to Decision Record drafting → re-evaluation exit.

The entry prompt must offer "Re-evaluate" as a first-class option,
not "Do you want to revise?" The wording matters: a "Do you want to
revise?" default biases every chain toward STRATEGY revision and
destroys the discipline-vs-artifact decoupling the brief commits to.

What I review at end: the new Decision Record at
`docs/decisions/DECISION-strategy-<topic>-re-evaluation-<YYYY-MM-DD>.md`,
referencing the existing STRATEGY by path. The existing
`docs/strategies/STRATEGY-<topic>.md` remains unchanged (still
Accepted/Active). State file records `exit: re-evaluation`.

### US-3: Mid-chain abandonment-forced materialization

As a **skill author** whose `/charter` run broke mid-flight (closed
the session, switched to a different task, or stale-session
detection fired on resume), I want `/charter` to force-materialize
the most-recently-running child's intermediate as a Draft artifact
with a Status block noting the abandonment-forced origin, so that
the chain always leaves a review surface regardless of how it
ended.

Chain shape: `/charter` resume ladder detects partial state →
either (a) author explicitly says "wrap it up" or (b) state file's
`last_updated` is > 7 days old and author selects "Force-materialize"
→ confirm/cancel prompt → force-materialize the most-recently-running
child's intermediate → abandonment-forced exit.

The same path covers `/strategy` Phase 5's Reject branch. When the
author explicitly rejects a Draft STRATEGY at `/strategy`'s
finalization, `/strategy` deletes the STRATEGY and wip/ files. From
`/charter`'s point of view this is a successful Reject — recorded as
abandonment-forced with `partial_phase_reached: rejected` and a
reference to the discard commit SHA.

What I review at end: the force-materialized Draft artifact (Status
block marks it abandonment-forced); OR, on `/strategy` Reject, the
git history showing the discard commit. State file records
`exit: abandonment-forced`.

### US-4: Reviewer redirect via manual fallback

As a **reviewer or author** who wants to tighten a Draft STRATEGY
directly without re-running the full chain, I want to invoke
`/strategy <path-to-existing-STRATEGY>` outside `/charter`,
producing a revised Draft, and have `/charter` warn but not act when
I later resume it on the same topic, so that manual fallback is
first-class steady-state capability rather than a workaround.

Chain shape: author invokes `/strategy` directly (Mode 3 with VISION
path or Mode 4 with the existing STRATEGY's topic) → `/strategy`
runs standalone → produces revised Draft → `/charter` is not
invoked.

On later `/charter` resume against the same topic, `/charter`'s
resume ladder detects out-of-chain edits (the STRATEGY's
last_updated is newer than `/charter`'s recorded snapshot). It
surfaces a staleness warning with three options: re-run `/roadmap`,
accept ROADMAP as still-valid, or proceed without ROADMAP.
`/charter` warns but does not act unilaterally.

What I review at end: depends on the author's choice. The
critical property is `/charter` did not interfere with the manual
invocation, and `/charter` did not silently re-run downstream work.

## Requirements

Requirements are tagged with `[/charter-specific]` (binding stays in
this PRD) or `[pattern-level]` (the downstream shared design doc
should lift the mechanism into pattern-level scope). Pattern-level
tags signal to the designer of
`docs/designs/DESIGN-shirabe-progression-authoring.md` which
commitments apply to `/scope` and the future `/work-on` migration
too.

### Functional Requirements

**R1 [/charter-specific].** `/charter` SHALL load as a Claude Code
slash command with the SKILL.md template shape used by `/strategy`
(input modes, execution-mode flag parsing, topic-slug constraint,
workflow phases diagram, resume logic ladder, phase execution list,
reference files table). The skill MUST live at `skills/charter/`.

**R2 [/charter-specific].** `/charter` SHALL accept the following
input modes:
- **Empty `$ARGUMENTS`**: cold start; ask the author what strategic
  conversation they want to have, then re-enter Freeform Topic mode
  with the derived slug.
- **Freeform topic string**: `/charter <topic-slug>` — derive the
  slug per the topic-slug-constraint below; enter Phase 1
  discovery.

`/charter` MUST NOT accept paths to durable artifacts as input
(unlike `/strategy`'s Input Modes 2-3). The chain produces multiple
artifacts; an upstream-path input mode does not compose.

**R3 [pattern-level].** `/charter` SHALL enforce the topic-slug
constraint `^[a-z0-9-]+$` on the derived slug. This constraint
matches `/strategy`'s constraint so the same slug flows through the
chain. Slugs failing the constraint MUST be rejected at Phase 0;
`/charter` MUST NOT proceed silently.

**R4 [/charter-specific].** `/charter` SHALL invoke `/vision` when
either signal is present:
- No Accepted/Active VISION exists at `docs/visions/VISION-<topic>.md`
  matching the chain's scope, OR
- The author's Phase 1 discovery surfaces a thesis-shift signal
  (author-stated; the brief calls this out as "if the long-term
  thesis is shifting").

The thesis-shift signal is `/charter`-internal — `/vision` itself
has no API to receive "treat this as a revision." `/charter` Phase 1
elicits the signal conversationally, then invokes `/vision <topic>`;
`/vision`'s own Resume Logic detects the existing-VISION case if
one exists.

**R5 [/charter-specific].** `/charter` SHALL invoke `/comp` when
both conditions hold:
- Repository visibility is Private (per CLAUDE.md `## Repo
  Visibility:` header), AND
- `skills/comp/SKILL.md` exists on disk.

When the `/comp` skill is not yet shipped, `/charter` SHALL silently
skip the `/comp` step. The author MUST NOT see a "skill not yet
shipped" message or any reference to competitive analysis. In public
repos, the same silence applies regardless of `/comp`'s shipping
status. This degenerate-silence shape ensures `/charter` v1 ships
without coupling to `/comp`; when `/comp` ships, the integration is
live with no `/charter` change.

**R6 [/charter-specific].** `/charter` SHALL always invoke
`/strategy` as the load-bearing child of the chain. The chain
completes either at `/strategy`'s exit (no `/roadmap` warranted) or
continues to `/roadmap`. `/charter` SHALL pass `/strategy` one of:
- a freeform topic string (no upstream), OR
- a VISION path (Input Mode 3 of `/strategy`) if `/vision` ran in
  the chain or if an existing VISION was identified during
  discovery, OR
- a PRD path (also accepted by `/strategy` Phase 1) if the chain
  operationalizes a feature PRD.

`/charter` MUST NOT pass a STRATEGY path to `/strategy`. STRATEGY
paths are `/strategy`'s lifecycle-verb mode (Input Mode 2), not the
create-new mode.

**R7 [/charter-specific].** `/charter` SHALL invoke `/roadmap` when
the just-produced STRATEGY's Building Blocks section contains 3 or
more blocks AND the STRATEGY's Coordination Dependencies section
names cross-block dependencies. If only 1-2 Building Blocks or no
explicit Coordination Dependencies, `/charter` SHALL skip `/roadmap`
and complete the chain at full-run with STRATEGY only.

`/charter` SHALL pass `/roadmap` two things together:
- `--upstream <strategy-path>` flag pointing at the just-produced
  STRATEGY (Phase 3 of `/roadmap` writes this to ROADMAP
  frontmatter), AND
- A pre-populated `wip/roadmap_<topic>_scope.md` file matching the
  schema `/roadmap` Phase 1 expects (Theme Statement, Initial Scope,
  Candidate Features, Dependency Sketch, Sequencing Constraints,
  Downstream Artifact State, Coverage Notes). This handoff causes
  `/roadmap` to skip its Phase 1 (analogous to `/explore` Phase 5's
  handoff pattern).

If `/roadmap`'s phase code rejects a STRATEGY path as upstream
(documented as "typically VISION"; pending verification), the
delegation contract MUST surface the gap explicitly — `/charter`
SHALL NOT silently substitute a VISION path or embed the STRATEGY
as a non-upstream reference.

**R8 [/charter-specific].** `/charter` SHALL terminate at exactly
one of three named exits:

- **Full-run.** A Draft STRATEGY landed (and optionally a Draft
  ROADMAP). The chain halts at the durable artifact(s).
- **Re-evaluation.** The chain confirmed the existing STRATEGY's
  bet still holds. `/charter` wrote a Decision Record at
  `docs/decisions/DECISION-strategy-<topic>-re-evaluation-<YYYY-MM-DD>.md`
  referencing the existing STRATEGY. No STRATEGY revision; no
  ROADMAP regeneration.
- **Abandonment-forced.** The most-recently-running child's
  intermediate was force-materialized as a Draft artifact with a
  Status block noting abandonment-forced origin. Subsumes
  `/strategy` Phase 5 Reject (treated as abandonment-forced with
  the discard commit SHA recorded in the state file).

**R9 [pattern-level].** `/charter` SHALL fail finalization if the
state file's `exit:` field is unset or not in
`{full-run, re-evaluation, abandonment-forced}`. The hard
finalization check is the contract enforcement mechanism: a
`/charter` run that completes without recording an exit is a
violation and MUST be surfaced (not silently absorbed).

**R10 [pattern-level].** `/charter` SHALL maintain a state file at
`wip/charter_<topic>_state.md` with the following fields (YAML
front-matter style):

```yaml
topic: <topic-slug>
chain_started: <ISO-8601 timestamp>
chain_completed: <ISO-8601 timestamp>  # set at finalization
last_updated: <ISO-8601 timestamp>     # set on every write
planned_chain: [vision?, comp?, strategy, roadmap?]  # which children in scope
chain_ran: [<sub-list of completed children>]
chain_skipped: [<sub-list of skipped children with reasons>]
exit: full-run | re-evaluation | abandonment-forced
exit_artifacts:
  - path: <artifact-path>
    status: <Draft | Accepted | Active>
child_snapshots:                       # per-child status snapshot at last exit
  vision: { path: <…>, status: <…>, last_seen: <ISO-8601> }
  strategy: { path: <…>, status: <…>, last_seen: <ISO-8601> }
  roadmap: { path: <…>, status: <…>, last_seen: <ISO-8601> }
referenced_strategy: <path>            # set on re-evaluation exit
triggering_child: <child-name>         # set on abandonment-forced
partial_phase_reached: <phase-name | "rejected">  # set on abandonment-forced
discard_commit_sha: <sha>              # set when /strategy Reject fired
```

The `planned_chain` field disambiguates multi-child phase pointers
when a resume detects both a Draft VISION and a Draft STRATEGY. The
`child_snapshots` block enables sibling-edit detection (US-4): a
resume compares `last_seen` against the child doc's current
last-updated marker and surfaces staleness when they differ.

**R11 [pattern-level].** `/charter` SHALL implement a resume ladder
that extends the multi-source pattern shared across shipped shirabe
ladders to span sibling child docs. The ladder MUST consult:
1. `wip/charter_<topic>_state.md` for the phase pointer, planned
   chain, and exit pointer (if any).
2. Each child doc named in `planned_chain` — for each, read the
   current frontmatter `status:` and compare to the
   `child_snapshots` entry to detect out-of-chain edits.
3. Each child's own wip/ artifacts (`wip/strategy_<topic>_discover.md`,
   `wip/vision_<topic>_scope.md`, etc.) for partial-child-run
   detection.

When the ladder detects a child doc in `Accepted` or `Active`
status that would trigger that child's own "offer to revise or
start fresh" prompt on re-entry, `/charter` MUST decide upfront
whether the re-entry path is a re-evaluation exit (write Decision
Record; do not invoke the child) or a fresh chain (signal the child
to suppress its status-aware re-entry). The signaling mechanism is
a design-team decision; the requirement is that `/charter`'s flow
MUST NOT be hijacked by a child's resume-time prompt.

Resume-ladder ordering, top to bottom (first match wins):

```
state file has exit field set                       → Offer revise/fresh based on exit type
state file exists, last_updated < 7d                → Resume at recorded phase
state file exists, last_updated ≥ 7d                → Offer Resume / Force-materialize / Discard
docs/strategies/STRATEGY-<topic>.md Accepted/Active → Offer Re-evaluate / Revise / Bail
docs/strategies/STRATEGY-<topic>.md Draft           → Offer continue / start fresh
wip/strategy_<topic>_discover.md exists             → Resume into /strategy
wip/vision_<topic>_scope.md exists                  → Resume into /vision
On branch related to topic                          → Resume at Phase 1
On main or unrelated branch                         → Start at Phase 0
```

The ladder reads `wip/strategy_<topic>_discover.md` (not
`_scope.md`); `/strategy`'s SKILL.md documents the latter but its
phase files write the former. This is a known asymmetry `/charter`
accommodates; correcting `/strategy` is out of scope.

**R12 [pattern-level].** `/charter` SHALL detect repository
visibility by reading CLAUDE.md's `## Repo Visibility:` header
(pattern inherited from `/strategy` and `/explore`). If the header
is absent, `/charter` MUST default to Private and emit a warning to
the author. Public repos with a missing header are a known
limitation — `/charter`'s default-Private behavior would surface
`/comp` in a repo that should not see it.

**R13 [pattern-level].** `/charter` SHALL treat invoking any child
skill directly outside `/charter` (manual fallback) as first-class
steady-state behavior. `/charter` MUST NOT prevent or warn against
direct child invocation. On the next `/charter` resume, the resume
ladder detects out-of-chain edits via `child_snapshots` comparison
and surfaces staleness with three concrete options (re-run the
downstream child, accept downstream as still-valid, proceed without
the downstream).

**R14 [/charter-specific].** `/charter` SHALL wait for the invoked
child to complete its own Phase 5 (or equivalent finalization)
before deciding the next child's invocation. `/charter` reads the
child doc's frontmatter `status:` value after the child returns;
`/charter` MUST NOT inspect the child's intermediate
`wip/research/<child>_<topic>_phase4_*.md` verdict files (those are
the child's internals).

### Non-Functional Requirements

**R15 [/charter-specific].** `/charter` SHALL produce artifacts that
pass `shirabe validate` on commit. Specifically:
- Draft STRATEGY MUST NOT contain Competitive Considerations
  sections when committed to a public repo (R8 of `shirabe
  validate` catches violations; this is `/strategy`'s constraint
  inherited).
- Decision Record at
  `docs/decisions/DECISION-strategy-<topic>-re-evaluation-<YYYY-MM-DD>.md`
  MUST follow the ADR-style body shape (Status, Context, Decision,
  Options Considered, Consequences) with frontmatter (`status`,
  `decision`, `rationale`). The `DECISION-` prefix matches
  shirabe's `<TYPE>-<name>.md` pattern (BRIEF-, DESIGN-, PLAN-,
  PRD-, ROADMAP-, STRATEGY-, VISION-).
- Abandonment-forced artifacts MUST be schema-compliant in the
  same shape as a full-run artifact. The abandonment-forced
  metadata MUST live in an HTML-comment marker
  (`<!-- charter-status-block: abandonment-forced; ... -->`)
  inside the artifact's existing Status section, NOT in a new
  required section that would invalidate the artifact-type schema.

**R16 [/charter-specific].** `/charter` SHALL respect the 7-day
stale-session threshold for distinguishing "broke for lunch" from
"abandoned for a week." The threshold is fixed in v1; a future
release may make it configurable.

**R17 [/charter-specific].** `/charter` SHALL update workspace and
shirabe CLAUDE.md documentation to surface `/charter`'s entry
triggers and discovery surface. The trigger phrases mirror the
patterns used by shipped skills: "start a strategic conversation
about X", "open a charter for Y", "I need to think through the bet
on Z", or direct `/charter <topic>` invocations.

**R18 [/charter-specific].** `/charter` SHALL ship with skill evals
at `skills/charter/evals/evals.json` covering the four user
stories. Per the shirabe authoring convention, evals MUST be run
via `scripts/run-evals.sh charter` before merging.

## Acceptance Criteria

Each criterion is binary pass/fail. AC numbering follows the
requirement that motivates each check.

### Skill loading and slug constraint

- [ ] **AC1** `/charter` loads as a slash command from
  `skills/charter/SKILL.md`. The SKILL.md frontmatter declares
  `name: charter`. (R1)
- [ ] **AC2** Invoking `/charter` with no `$ARGUMENTS` produces a
  cold-start prompt asking for the topic. (R2)
- [ ] **AC3** Invoking `/charter Hello World` (whitespace in slug)
  is rejected at Phase 0 with a clear error message; the chain does
  not proceed. (R3)
- [ ] **AC4** Invoking `/charter docs/visions/VISION-foo.md` (path
  as `$ARGUMENTS`) is treated as a freeform topic after slug
  derivation; not interpreted as an upstream path. (R2)

### Child invocation signals

- [ ] **AC5** When `docs/visions/VISION-<topic>.md` does not exist
  AND the author's Phase 1 discovery does not surface thesis-shift,
  the chain proposal does not include `/vision`. (R4)
- [ ] **AC6** When the author's Phase 1 discovery surfaces a
  thesis-shift signal, the chain proposal includes `/vision`. The
  invocation passes only the topic slug; no API-level "treat as
  revision" signal is required. (R4)
- [ ] **AC7** When invoked in a public repo, `/charter`'s Phase 1
  discovery and chain proposal do not mention `/comp` or
  competitive analysis, regardless of input text. (R5, R12)
- [ ] **AC8** When invoked in a private repo with
  `skills/comp/SKILL.md` absent, the chain proposal output is
  identical to a public-repo invocation. (R5)
- [ ] **AC9** When the just-produced STRATEGY has fewer than 3
  Building Blocks OR no Coordination Dependencies section,
  `/charter` skips `/roadmap` and exits at full-run with STRATEGY
  only. (R7)
- [ ] **AC10** When the just-produced STRATEGY has 3+ Building
  Blocks AND a Coordination Dependencies section, `/charter`
  invokes `/roadmap` with `--upstream <strategy-path>` AND a
  pre-populated `wip/roadmap_<topic>_scope.md`. (R7)

### Exit-path enforcement

- [ ] **AC11** After a chain that completes with a Draft STRATEGY
  (and optional Draft ROADMAP), `wip/charter_<topic>_state.md`
  contains `exit: full-run` and `exit_artifacts` lists the
  artifact path(s) and status(es). (R8, R10)
- [ ] **AC12** After a re-evaluation chain that confirms the bet
  holds, `docs/decisions/DECISION-strategy-<topic>-re-evaluation-<YYYY-MM-DD>.md`
  is written; the existing STRATEGY is unchanged; the state file
  contains `exit: re-evaluation` and `referenced_strategy:
  <strategy-path>`. (R8, R10)
- [ ] **AC13** After `/charter` force-materializes an intermediate,
  the resulting artifact contains an HTML-comment marker
  `<!-- charter-status-block: abandonment-forced; ... -->` inside
  its Status section; the state file contains
  `exit: abandonment-forced`,
  `triggering_child: <child-name>`,
  and `partial_phase_reached: <phase>`. (R8, R10, R15)
- [ ] **AC14** When `/strategy` Phase 5 Reject fires inside a
  `/charter` chain, the state file records
  `exit: abandonment-forced`,
  `partial_phase_reached: rejected`, and `discard_commit_sha:
  <sha>`. No charter-level Decision Record is written. (R8, R10)
- [ ] **AC15** A `/charter` run that completes without recording a
  valid `exit:` value fails finalization with a clear error. (R9)

### Resume ladder

- [ ] **AC16** When a partial state file exists and
  `last_updated` is less than 7 days old, `/charter` resumes at
  the recorded phase without prompting Force-materialize. (R10,
  R11)
- [ ] **AC17** When a partial state file exists and
  `last_updated` is ≥ 7 days old, `/charter` surfaces a
  three-option prompt: Resume / Force-materialize / Discard. The
  prompt fires on every invocation until the author chooses. (R11,
  R16)
- [ ] **AC18** When `docs/strategies/STRATEGY-<topic>.md` is
  Accepted/Active, the entry prompt is "Re-evaluate / Revise /
  Bail" — NOT "Continue / Start fresh." (R11; US-2 wording is
  load-bearing)
- [ ] **AC19** When `child_snapshots.strategy.last_seen` is older
  than the STRATEGY's current frontmatter timestamp, the
  resume ladder surfaces a staleness warning with three concrete
  options (re-run downstream, accept downstream as still-valid,
  proceed without downstream). (R11, R13)
- [ ] **AC20** When `/charter` invokes a child whose durable doc
  is already Accepted, `/charter`'s flow is not hijacked by the
  child's "offer to revise" prompt; `/charter` either pre-empts
  (writes Decision Record without invoking child) or signals the
  child to suppress (mechanism is design-team scope; AC verifies
  observable outcome). (R11)

### Visibility and manual fallback

- [ ] **AC21** When CLAUDE.md lacks a `## Repo Visibility:` header,
  `/charter` defaults to Private AND emits a warning naming the
  missing header. (R12)
- [ ] **AC22** An author invoking `/strategy` directly outside
  `/charter` produces no `/charter` interference; `/charter` does
  not surface a warning, does not block, does not modify state.
  (R13)
- [ ] **AC23** On the next `/charter` resume after a direct child
  invocation, the staleness detection in AC19 fires. (R13)

### Schema and validation

- [ ] **AC24** Draft STRATEGY written by `/charter`'s `/strategy`
  delegation passes `shirabe validate --visibility=<repo-visibility>`.
  (R15)
- [ ] **AC25** Re-evaluation Decision Record contains the required
  ADR-style sections (Status, Context, Decision, Options
  Considered, Consequences) and frontmatter (`status`,
  `decision`, `rationale`). (R15)
- [ ] **AC26** Force-materialized artifact passes the same
  schema validators as a full-run artifact (the abandonment-forced
  HTML-comment marker is inside the existing Status section, not
  in a new required section). (R15)

### Pattern-level commitments (for designer to lift)

- [ ] **AC27** Each requirement tagged `[pattern-level]` in this
  PRD is reflected in `docs/designs/DESIGN-shirabe-progression-authoring.md`'s
  pattern-level scope (visible to `/scope` and the `/work-on`
  migration). The check is post-design — it verifies the PRD's
  tagging was respected by the designer.

## Out of Scope

The following are deliberately excluded from `/charter` v1. Each
links to its successor effort where relevant.

- **The `/scope` tactical progression skill.** Separate feature
  with its own brief; shares the design doc but does not bind
  `/charter`'s scope.
- **The `/work-on` migration into the parent-skill pattern.**
  Separate feature; depends on workflow-substrate work that
  `/charter` does not require for its own ship.
- **The `/comp` skill body itself.** `/charter`'s contract for
  consuming `/comp` is in scope; authoring `/comp` SKILL.md is the
  responsibility of the `/comp` feature when it lands.
- **Revisions to the `/strategy` SKILL.md.** `/charter` consumes
  `/strategy` as it ships today. The known `_scope.md` /
  `_discover.md` documentation asymmetry in `/strategy`'s SKILL.md
  Resume Logic is accommodated by `/charter` (reads `_discover.md`);
  a fix to `/strategy`'s docs is a separate follow-up.
- **Revisions to the `/roadmap` SKILL.md or phases.** If
  `/roadmap`'s phase code rejects a STRATEGY path as `--upstream`,
  the gap is documented in this PRD as a delegation-contract
  caveat; the fix lands in a separate `/roadmap` change.
- **The discover/converge engine extraction location.** Whether
  the engine moves from `skills/explore/references/phases/` to a
  top-level `references/` directory is a design-team decision; the
  PRD declares the engine as referenced, not as moved.
- **The workflow-substrate work the `/work-on` migration depends
  on.** `/charter` ships against current shirabe patterns (`wip/`-based
  intermediates, plain-English phase prose) — the same pattern used
  by every shipped non-koto shirabe skill.
- **Automatic review-time redirect mechanism.** Manual fallback is
  first-class by design; an automatic-redirect substrate is
  workflow-substrate work and not a prerequisite for `/charter`.
- **Migration of existing strategic-progression artifacts.**
  `/charter` adds a parent layer without renaming or restructuring
  child artifacts. Existing STRATEGY, ROADMAP, VISION docs continue
  to validate under their existing schemas.
- **A new shirabe artifact type for re-evaluation Decision
  Records.** `/charter` v1 establishes `DECISION-*.md` in
  `docs/decisions/` by precedent (matching shirabe's existing
  `<TYPE>-<name>.md` prefix pattern). A separate feature can later
  formalize a decision-record artifact type with full validator
  rules if warranted.
- **`/charter` auto-handoff from `/explore`.** Brief named this as
  an open question; the PRD demotes it to out-of-scope-v1 (manual
  invocation is the v1 entry path).
- **Tone rubric, writing-style discipline, and other shirabe
  substrate work.** `/charter` follows the same conventions
  shirabe uses today.

## Open Questions

Questions deferred to `/design` or to a follow-on PRD. Each names
the area and where the resolution should land.

1. **`/roadmap`'s `--upstream` STRATEGY-path acceptance.** Pending
   verification from a targeted follow-up to peer research:
   does `/roadmap`'s Phase 3 (the phase that consumes `--upstream`)
   reject a STRATEGY path, accept it as-is, or handle it
   differently from a VISION path? If rejected, R7's delegation
   contract requires renegotiation — either `/charter` falls back
   to VISION upstream (losing the STRATEGY trace) or `/roadmap`
   gets a minor accommodation (out of scope per the brief).
   Resolution: design team.

2. **Engine extraction location for the discover/converge engine.**
   The engine currently lives in
   `skills/explore/references/phases/`. Whether `/charter` consumes
   it cross-skill (status quo) or whether the engine moves to a
   top-level `references/` directory (signaling shared
   infrastructure) is a design-team decision. The PRD specifies
   the engine is referenced, not where it lives.

3. **Dual-implementation contract.** `/charter` ships against
   `wip/`-based intermediates (the current shirabe pattern for all
   non-koto skills); the future `/work-on` migration will live in
   a different workflow substrate. The freeze line between the
   two implementations is the design-team's call. The resume
   contract IS storage-agnostic (named state fields + child-doc
   inspections), and the wip/-specific hygiene rules
   (cleanup-before-merge, no-orphan-references) are orthogonal —
   the contract bounds the substitution surface but does not pick
   the substrate.

4. **Shared design doc authoring timing.** Whether
   `docs/designs/DESIGN-shirabe-progression-authoring.md` is
   authored alongside this PRD or deferred until at least one
   other parent skill (`/scope` or `/work-on` migration) is in
   scope to validate pattern-level claims. The PRD's
   `[pattern-level]` tags are useful regardless; the question is
   whether the designer lifts them now or later.

5. **Cross-branch state-file behavior under `wip/`.** The state
   file under wip/ is branch-coupled — `/charter` resume requires
   the same feature branch as the original run. If `/charter`'s
   exit-tracking ever needs to cross branches (e.g., merge a
   child's PR, then resume `/charter` on main to invoke the next
   child), the wip/-based model breaks. No `/charter` v1
   requirement forces cross-branch resume; the limitation is
   flagged for the designer to consider when the workflow-substrate
   work is bounded.

6. **Competitive-framing signal detection in private repos.** When
   `/comp` ships, `/charter`'s recommended-default for offering
   `/comp` depends on detecting "competitive framing signals"
   (competitor name, externally-framed bet, market-share language)
   during Phase 1. The detection mechanism is agent judgment with
   the PRD specifying broad signal categories; the implementation
   detail (keyword list vs LLM judgment vs structured prompt) is a
   design-team decision when the `/comp` integration goes live.

7. **Team persistence across the parent-skill chain.** The
   TeamCreate single-team-per-leader constraint prevents
   downstream teams (`/prd`, `/design`, `/plan`) from holding
   upstream teams (`/brief`) alive for interactive query. The
   current contract is file-handoff. The likely resolution is the
   workflow-substrate work when it lands. The PRD records the
   constraint; the resolution is design-team territory.

## Known Limitations

- **`/comp` is not shipped.** `/charter` ships with the `/comp`
  invocation logic gated behind a skill-existence check; the
  contract becomes live with no `/charter` change when `/comp`
  ships. The intended user outcome ("In private repos, `/comp` is
  offered as an optional discovery feeder") is partially deferred
  until `/comp` lands.

- **No automatic engine extraction.** The discover/converge engine
  `/charter` consumes for Phase 1 discovery lives in
  `skills/explore/references/phases/` for the v1 ship. If the
  design team moves it to a top-level `references/` directory, the
  `/charter` SKILL.md reference path updates in a follow-on PR.

- **State file is branch-coupled.** The
  `wip/charter_<topic>_state.md` file lives on the feature branch
  of the original `/charter` run. Resume across branches is not
  supported in v1.

- **Stale-session threshold is fixed at 7 days.** Not configurable
  in v1. Author feedback after v1 ship determines whether to make
  it configurable in a follow-on.

- **`DECISION-` prefix is established by precedent, not by
  artifact-type validator.** `/charter` v1 writes
  `DECISION-strategy-<topic>-re-evaluation-<YYYY-MM-DD>.md` to
  `docs/decisions/` following shirabe's `<TYPE>-<name>.md` pattern
  but does not register a `decision` artifact type in `shirabe
  validate`. A separate feature can later formalize the artifact
  category if warranted.

- **`/strategy` Reject's audit surface is git history, not a
  charter-level file.** When `/strategy` Phase 5 Reject fires
  inside a chain, `/strategy` deletes the STRATEGY draft and its
  wip/ files. The `docs(strategy): discard STRATEGY draft for
  <topic>` commit is the durable audit trail. `/charter`'s state
  file records the discard commit SHA, but no
  `DECISION-strategy-<topic>-discarded.md` is written in v1.

- **CLAUDE.md missing visibility header defaults to Private.**
  Inherited from shipped `/strategy` behavior. A public repo
  without the `## Repo Visibility:` header would surface `/comp`
  prompts in `/charter` Phase 1 if `/comp` were shipped. The
  practical mitigation is the authoring guideline that every
  public repo's CLAUDE.md must declare visibility explicitly.

## Decisions and Trade-offs

Decisions made during scoping and research that shape requirements
above. Each entry names what was decided, what alternatives existed,
and the reasoning.

### Decision 1: Mixed audience for the PRD

**Decided.** The PRD is written for two readers: author-reader for
the user-facing surface (phases, prompts, exit messages, resume
behavior) and designer-reader for the four delegation contracts and
three exit paths. Requirements are tagged `[/charter-specific]` or
`[pattern-level]` so the designer can lift pattern-level
commitments into the shared design doc.

**Alternatives considered.** (a) Pure author-reader: would have
left the designer to re-discover contract precision in the design
phase. (b) Pure designer-reader: would have produced contract-level
requirements with no user-facing context, making the chain shape
hard to evaluate against the brief's User Journeys.

**Reasoning.** The downstream design doc is shared across
`/charter`, `/scope`, and the `/work-on` migration. The PRD's job
is to expose the contracts precise enough for a designer to
distinguish pattern-level from feature-specific while also
grounding requirements in user-observable behavior.

### Decision 2: `/comp` is documented-but-disabled, not deferred

**Decided.** `/charter` ships with `/comp` invocation logic gated
behind a skill-existence check. When `/comp` is not on disk,
`/charter` silently skips the `/comp` step (no "skill not yet
shipped" surface). Contract is documented as load-bearing in
requirements (R5). When `/comp` lands, the integration is live with
no `/charter` change.

**Alternatives considered.** (a) Ship without `/comp` integration
at all (PR follow-up when `/comp` ships) — simpler but adds a
second PR. (b) Block `/charter` shipping until `/comp` ships — gates
`/charter` on parallel work.

**Reasoning.** Author-facing outcome matches the brief's stated
intent: in private repos `/comp` is an optional discovery feeder
when shipped; otherwise the chain is silent about it. The
skill-existence flip is the only change needed when `/comp` lands.

### Decision 3: Hard finalization check on exit-tracking field

**Decided.** `/charter` runs a finalization check that fails if
`wip/charter_<topic>_state.md`'s `exit:` field is unset or invalid.
There is no "true bail" path; bail routes to abandonment-forced.

**Alternatives considered.** Best-effort enforcement with a warning
on bail. Would have made the discipline-vs-artifact decoupling
softer than the brief commits to: every chain leaves a review
surface, no exception.

**Reasoning.** The brief's "discipline-vs-artifact decoupling"
thesis fails empirically if the abandonment-forced exit is
skippable. The bail-routes-to-abandonment-forced rule is the
mechanism that makes the discipline survive when authors don't
follow through.

### Decision 4: Hybrid resume ladder (state-file pointer + child-doc snapshots)

**Decided.** `wip/charter_<topic>_state.md` holds the phase pointer,
the planned chain, the exit pointer, and per-child status
snapshots. Resume ladder consults this file AND the live child docs.
Snapshot enables sibling-edit detection (US-4); state file enables
multi-child phase pointer disambiguation.

**Alternatives considered.** (a) Pure single-source state file —
loses sibling-edit detection. (b) Pure multi-source against child
docs — loses the planned-chain disambiguation when multiple Draft
docs exist for the same topic.

**Reasoning.** `/explore` and `/strategy` both use multi-source
ladders today; `/charter`'s hybrid matches the precedent and adds
the cross-child boundary as the novel piece. The snapshot block in
the state file is what makes Journey 4's "warn but don't act"
behavior implementable.

### Decision 5: Reject is abandonment-forced, not a fourth exit

**Decided.** When `/strategy` Phase 5 Reject fires inside a
`/charter` chain (deleting the STRATEGY draft and wip/ files),
`/charter` records `exit: abandonment-forced` with
`partial_phase_reached: rejected` and `discard_commit_sha: <sha>`.
The discard commit message is the audit surface.

**Alternatives considered.** (a) Add a fourth exit class
"discarded" — preserves naming precision but breaks the brief's
three-exit count. (b) Force `/charter` to write a degenerate ADR
at `docs/decisions/DECISION-strategy-<topic>-discarded.md` —
preserves the every-chain-lands-at-a-file promise but doubles the
ADR write surface for arguably no marginal value.

**Reasoning.** The discard commit message already captures the
rationale (the author chose to reject). The brief's "every chain
leaves a review surface" spirit is met by `git log` for this
specific path. The three-exit count is preserved.

### Decision 6: `/charter` writes the re-evaluation Decision Record inline

**Decided.** `/charter` writes
`docs/decisions/DECISION-strategy-<topic>-re-evaluation-<YYYY-MM-DD>.md`
directly, using an ADR-style body (Status, Context, Decision,
Options Considered, Consequences) with frontmatter (`status`,
`decision`, `rationale`). No delegation to a separate
decision-writing skill.

**Alternatives considered.** (a) Delegate to `/decision` and
promote its `wip/<prefix>_report.md` to a durable ADR — `/decision`
itself doesn't durably produce ADRs; the indirection adds complexity
without reuse benefit for this use case. (b) Author a new sibling
skill `/decision-record` for shirabe core — out of scope per the
brief (no new sibling skills).

**Reasoning.** The re-evaluation use case (review evidence against
existing bet; either confirm or recommend re-strategizing) is
simpler than `/decision`'s general decision-question workflow. The
inline write produces exactly the artifact the brief calls for, in
a format that matches shirabe's `<TYPE>-<name>.md` precedent.

### Decision 7: HTML-comment marker for abandonment-forced status

**Decided.** When `/charter` force-materializes an intermediate,
the abandonment-forced metadata lives in an HTML-comment marker
(`<!-- charter-status-block: abandonment-forced; ... -->`) inside
the artifact's existing Status section. The artifact's schema is
unchanged.

**Alternatives considered.** Extend the STRATEGY format spec
(`references/strategy-format.md`) to add an abandonment-forced
Status block — would be a `/strategy`-revision excluded by the
brief.

**Reasoning.** The HTML-comment marker preserves the artifact-type
schema (existing validators continue to pass), is
machine-parseable, and is visible to human reviewers in source
view. It surfaces the abandonment-forced origin without forking
the schema.

### Decision 8: 7-day stale-session threshold, fixed in v1

**Decided.** The threshold for "stale enough to ask
Force-materialize" is fixed at 7 days in v1, with revisitation
deferred until authors signal it's wrong.

**Alternatives considered.** Configurable via CLAUDE.md
(`## Charter Stale Threshold:`). Adds configuration surface without
clear authoring need; harder to test deterministically.

**Reasoning.** Ship with a defensible default. The 7-day boundary
distinguishes "broke for lunch" from "abandoned for a week," which
matches the brief's framing of Journey 3.

### Decision 9: `wip/` is the current shirabe pattern, not against it

**Decided.** The PRD reframes the brief's wording: `/charter` lives
in the `wip/`-based intermediate pattern, which is what 6 of 7
shipped non-koto shirabe skills use today. The future workflow
substrate (which the `/work-on` migration will live in) is the
forward direction; `/charter` matches current shipping pattern.

**Alternatives considered.** Preserve the brief's framing of
`/charter` going "against current patterns." Inaccurate; would
mislead readers about what `/charter` actually does.

**Reasoning.** Truth-on-disk. The resume contract is
storage-agnostic regardless of framing; the framing should be
accurate.
