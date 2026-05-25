---
status: Done
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

Done. Accepted at commit `8c17099`; transitioned to In
Progress on 2026-05-24 when design authoring began at
`docs/designs/current/DESIGN-shirabe-progression-authoring.md`. The PRD is
the requirements input to that downstream design (co-authored
across `/charter`, `/scope`, and the `/work-on` migration) and to
`/charter`'s eventual implementation plan. Consumes the Accepted
brief at `docs/briefs/BRIEF-shirabe-charter-skill.md`. Transitioned to Done on 2026-05-25 after the charter skill implementation landed on session/db61668b (PR #96).

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
- The chain ends at exactly one of three named exit paths
  (full-run, re-evaluation, abandonment-forced). The re-evaluation
  exit produces a durable Decision Record file at
  `docs/decisions/DECISION-strategy-<topic>-<sub-shape>-<YYYY-MM-DD>.md`
  with two first-class sub-shapes that share the artifact shape:
  the re-evaluation sub-shape (existing STRATEGY holds; lightweight
  conclusion) and the rejection sub-shape (Draft STRATEGY authored
  and then explicitly rejected; conclusion captured as a durable
  record). Both express the same architectural intent — strategic
  discipline without a STRATEGY artifact — and land at a durable
  file in `docs/decisions/`.
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
Accepted/Active). State file records `exit: re-evaluation` with
`decision_record_sub_shape: re-evaluation`.

### US-3a: Strategy rejection via re-evaluation exit's rejection sub-shape

As a **skill author** whose `/charter` run authored a Draft STRATEGY
that I deliberately rejected at `/strategy`'s finalization gate, I
want `/charter` to capture the rejection as a durable Decision
Record (alongside the discard commit that `/strategy` itself wrote),
so that the strategic conversation lands at an artifact even when
the conclusion was "no STRATEGY warranted."

Chain shape: `/charter` invokes `/strategy` → `/strategy` runs to
its Phase 5 finalization → user picks Reject at the
final-confirmation gate → `/strategy` runs `git rm
docs/strategies/STRATEGY-<topic>.md`, cleans up `wip/strategy_<topic>_*.md`,
commits `docs(strategy): discard STRATEGY draft for <topic>` →
control returns to `/charter` → `/charter` immediately writes
`docs/decisions/DECISION-strategy-<topic>-rejection-<YYYY-MM-DD>.md`
referencing the discard commit SHA and the user's stated rationale
→ re-evaluation exit, rejection sub-shape.

This sub-shape is *not* abandonment (the author exercised explicit
judgment at a finalization gate; they did not bail mid-flight). It
shares the re-evaluation exit with the re-evaluation sub-shape
because both express the same architectural intent: a strategic
conversation that lands at a durable record rather than at a
STRATEGY artifact.

What I review at end: the new
`docs/decisions/DECISION-strategy-<topic>-rejection-<YYYY-MM-DD>.md`
referencing the discard commit. No STRATEGY exists on disk. State
file records `exit: re-evaluation` with `decision_record_sub_shape: rejection`
and `discard_commit_sha: <sha>`.

### US-3b: Mid-chain abandonment-forced materialization

As a **skill author** whose `/charter` run broke mid-flight (closed
the session, switched to a different task, or stale-session
detection fired on resume), I want `/charter` to force-materialize
the most-recently-running child's intermediate as a Draft artifact
with a Status marker noting the abandonment-forced origin, so that
the chain always leaves a review surface regardless of how it
ended.

Chain shape: `/charter` resume ladder detects partial state →
either (a) author explicitly says "wrap it up" or picks Bail at
R7.5's chain-proposal prompt, or (b) state file's `last_updated`
is ≥ 7 days old and author selects "Force-materialize" →
confirm/cancel prompt → force-materialize the most-recently-running
child's intermediate per R8's tie-break rule → abandonment-forced
exit.

The abandonment-forced exit fires when the author *bails* (closes
the session, lets the chain go stale, or explicitly says "wrap it
up"). It is distinct from the rejection sub-shape of the
re-evaluation exit (US-3a) — that sub-shape fires when the author
makes an explicit judgment at `/strategy`'s finalization gate.

What I review at end: the force-materialized Draft artifact with an
HTML-comment marker noting it was abandonment-forced. State file
records `exit: abandonment-forced` with `triggering_child:
<child-name>` and `partial_phase_reached: <phase>`.

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

**R1 [pattern-level].** A parent skill SHALL load as a Claude Code
slash command following the SKILL.md template shape used by
shipped shirabe skills (input modes section, execution-mode flag
parsing, topic-slug constraint, Workflow Phases diagram, Resume
Logic ladder, Phase Execution list, Reference Files table). The
template structure is pattern-level; the directory location is
charter-specific: `/charter` MUST live at `skills/charter/`.

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
- The author's Phase 1 discovery surfaces a thesis-shift signal.

The thesis-shift signal is an author-stated condition surfaced
through Phase 1 discovery. `/charter`'s discovery prompt MUST
include a question of the form "Is the long-term thesis shifting,
or is this an operational layer below it?" with at least the
following author-utterance categories treated as thesis-shift
signals: (a) the author explicitly says the long-term thesis is
changing or has changed; (b) the author names a new audience,
value proposition, or org fit that the existing VISION does not
cover; (c) the author indicates the existing VISION is no longer
the right framing. Signal detection is agent judgment; the
requirement is that the discovery prompt surfaces the question
explicitly and the agent treats any of these utterance categories
as a positive signal. The thesis-shift signal is
`/charter`-internal — `/vision` itself has no API to receive
"treat this as a revision." `/charter` Phase 1 elicits the signal
conversationally, then invokes `/vision <topic>`; `/vision`'s own
Resume Logic detects the existing-VISION case if one exists.

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
contains at least one non-empty entry that references another
Building Block by name. If only 1-2 Building Blocks, OR no
Coordination Dependencies section, OR a Coordination Dependencies
section with no qualifying entries, `/charter` SHALL skip
`/roadmap` and complete the chain at full-run with STRATEGY only.

`/charter` SHALL pass `/roadmap` two things together:
- `--upstream <strategy-path>` flag pointing at the just-produced
  STRATEGY (Phase 3 of `/roadmap` writes this to ROADMAP
  frontmatter). `/roadmap`'s phase code accepts the path verbatim
  with no basename enforcement; the contract is firm.
- A pre-populated `wip/roadmap_<topic>_scope.md` file matching the
  schema `/roadmap` Phase 1 expects (Theme Statement, Initial Scope,
  Candidate Features, Dependency Sketch, Sequencing Constraints,
  Downstream Artifact State, Coverage Notes). This handoff causes
  `/roadmap` to skip its Phase 1 (analogous to `/explore` Phase 5's
  handoff pattern).

**R7.5 [/charter-specific].** `/charter` Phase 1 SHALL conclude
with a **chain-proposal confirmation prompt** that names the
chain shape derived from discovery and the three exit options the
author can pick from. Numbered R-decimal (R7.5) mirrors the
R17a/R17b precedent of non-integer R-numbers in this PRD when
intermediate insertion is cleaner than renumbering.

The prompt MUST identify itself as the **chain proposal output**
(the canonical term referenced by AC8 and elsewhere) and MUST
contain the literal substrings "Proceed", "Adjust", and "Bail"
(case-insensitive) as the three options. The prompt MUST list,
in order, the children `/charter` plans to invoke (skipping
those determined by R4/R5/R7 not to fire). Example shape:

> Based on our conversation, here's the chain I propose: [skip
> `/vision` because <reason> | run `/vision`], run `/strategy`,
> [run `/roadmap` because <reason> | skip `/roadmap` because
> <reason>]. Proceed / Adjust chain / Bail?

"Adjust" routes the author back to Phase 1 discovery for chain-shape
redirection (e.g., force `/vision` on, opt `/comp` out) before any
child fires. "Bail" routes per R8's bail-handling rule: routes to
abandonment-forced if any wip state exists, otherwise clean cancel.

**R8 [/charter-specific].** `/charter` SHALL terminate at exactly
one of three named exit paths. Every chain MUST land at a durable
file on disk; git history alone does not satisfy the
terminal-artifact contract.

- **Full-run.** A Draft STRATEGY landed (and optionally a Draft
  ROADMAP). The chain halts at the durable artifact(s).
- **Re-evaluation.** `/charter` wrote a durable Decision Record at
  `docs/decisions/DECISION-strategy-<topic>-<sub-shape>-<YYYY-MM-DD>.md`.
  The re-evaluation exit has two first-class sub-shapes that share
  the artifact shape:
  - **re-evaluation sub-shape.** The chain confirmed the existing
    STRATEGY's bet still holds. The Decision Record references
    the existing STRATEGY by path and records the evidence
    reviewed. No STRATEGY revision; no ROADMAP regeneration.
    Filename: `DECISION-strategy-<topic>-re-evaluation-<YYYY-MM-DD>.md`.
  - **rejection sub-shape.** The chain authored a Draft STRATEGY;
    the author explicitly rejected it at `/strategy`'s
    finalization gate (`/strategy` Phase 5 Reject branch).
    `/strategy` discarded the Draft via `git rm` and a
    `docs(strategy): discard STRATEGY draft` commit. `/charter`
    then wrote the Decision Record referencing the discard commit
    SHA, the user's stated rejection rationale, and the upstream
    VISION (if `/vision` ran). Filename:
    `DECISION-strategy-<topic>-rejection-<YYYY-MM-DD>.md`.
- **Abandonment-forced.** The most-recently-running child's
  intermediate was force-materialized as a Draft artifact with an
  HTML-comment marker noting abandonment-forced origin. Fires when
  the author bails (session closed and stale, "wrap it up" intent,
  R7.5's Bail option, or stale-session-detection threshold
  crossed). Does NOT fire on `/strategy` Phase 5 Reject — that is
  a deliberate finalization judgment, not a bail, and maps to the
  re-evaluation exit's rejection sub-shape.

  **Tie-break for "most-recently-running"**: the last entry in the
  state file's `chain_ran` field, or if `chain_ran` is empty, the
  first entry in `planned_chain` that has a non-empty wip/
  intermediate on disk. If neither resolves to a child (no
  `chain_ran` history, no wip/ intermediate), bail routes to
  clean-cancel rather than abandonment-forced — there is nothing
  to force-materialize.

**R9 [pattern-level].** `/charter` SHALL fail finalization if the
state file's `exit:` field is unset or not in
`{full-run, re-evaluation, abandonment-forced}`. When `exit:` is
`re-evaluation`, `decision_record_sub_shape:` MUST be set to one of
`{re-evaluation, rejection}`. Conditional fields (i.e., fields
whose presence is gated by a specific `exit:` or
`decision_record_sub_shape:` value, such as `referenced_strategy`,
`discard_commit_sha`, `rejection_rationale`, `triggering_child`,
`partial_phase_reached`) MUST be absent from the state file when
their triggering condition does not hold; they MUST NOT be set to
null, empty string, or placeholder value. The hard finalization
check is the contract enforcement mechanism: a `/charter` run that
completes without recording a valid exit is a violation and MUST
be surfaced (not silently absorbed).

**R10 [pattern-level].** `/charter` SHALL maintain a state file at
`wip/charter_<topic>_state.md`. The file is **pure YAML** despite
the `.md` extension (the extension matches shirabe's wip/
convention for committed intermediates; the body has no markdown).
The schema is:

```yaml
topic: <topic-slug>
chain_started: <ISO-8601 timestamp>
chain_completed: <ISO-8601 timestamp>  # set at finalization
last_updated: <ISO-8601 timestamp>     # set on every write
planned_chain: [vision?, comp?, strategy, roadmap?]  # which children in scope
chain_ran: [<sub-list of completed children>]
chain_skipped:                          # free-text reasons for humans; not parsed
  - child: <name>
    reason: <free text>
exit: full-run | re-evaluation | abandonment-forced
decision_record_sub_shape: re-evaluation | rejection   # set ONLY when exit=re-evaluation
exit_artifacts:
  - path: <artifact-path>
    status: <Draft | Accepted | Active>
child_snapshots:                       # per-child snapshot at last exit
  vision:   { path: <…>, status: <…>, content_hash: <git-blob-hash> }
  strategy: { path: <…>, status: <…>, content_hash: <git-blob-hash> }
  roadmap:  { path: <…>, status: <…>, content_hash: <git-blob-hash> }
referenced_strategy: <path>            # set on decision-record/re-evaluation
discard_commit_sha: <sha>              # set on decision-record/rejection
rejection_rationale: <text>            # set on decision-record/rejection
triggering_child: <child-name>         # set on abandonment-forced
partial_phase_reached: <phase-name>    # set on abandonment-forced
```

The `planned_chain` field disambiguates multi-child phase pointers
when a resume detects both a Draft VISION and a Draft STRATEGY. The
`child_snapshots` block enables sibling-edit detection (US-4):
each snapshot entry records the child doc's path, its
frontmatter `status:` value at last `/charter` exit, and the git
blob hash of the child doc at that time. On resume, `/charter`
compares both the live `status:` and the live blob hash against
the snapshot — drift fires when **either** has changed since the
snapshot was taken. Blob-hash comparison catches the common case
where a child doc stays at the same status (e.g., Draft → Draft)
but its body was edited by hand (e.g., a STRATEGY's Building Blocks
section rewritten between `/charter` runs).

**R11 [pattern-level].** `/charter` SHALL implement a resume ladder
that extends the multi-source pattern shared across shipped shirabe
ladders to span sibling child docs. The ladder MUST consult:
1. `wip/charter_<topic>_state.md` for the phase pointer, planned
   chain, and exit pointer (if any).
2. Each child doc named in `planned_chain` — for each, read the
   current frontmatter `status:` AND compute the current git blob
   hash, then compare both to the `child_snapshots` entry to
   detect out-of-chain edits.
3. Each child's own wip/ artifacts (`wip/strategy_<topic>_discover.md`,
   `wip/vision_<topic>_scope.md`, etc.) for partial-child-run
   detection.

If the state file exists but is malformed (e.g., missing required
fields for its recorded phase, invalid `exit:` value with no
`decision_record_sub_shape:`, unparseable YAML), `/charter` MUST
surface a clear error naming the malformation and offer Discard
as a recovery path. The ladder MUST NOT silently fall through to
Phase 0 — a malformed state file is a contract violation surface,
not a missing state.

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
state file malformed                                → Error + offer Discard
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

STRATEGY is the chain anchor for status-aware re-entry. ROADMAP
status checks do NOT appear in the ladder; if a Draft ROADMAP
exists from a prior chain run, the ladder's STRATEGY checks
control re-entry behavior, and ROADMAP drift surfaces through the
child-snapshots staleness path of US-4 (the staleness warning
prompt fires if `child_snapshots.roadmap` shows drift).

The ladder reads `wip/strategy_<topic>_discover.md` (not
`_scope.md`); `/strategy`'s SKILL.md documents the latter but its
phase files write the former. This is a known asymmetry `/charter`
accommodates; correcting `/strategy` is out of scope.

**R12 [pattern-level].** `/charter` SHALL detect repository
visibility by reading CLAUDE.md's `## Repo Visibility:` header
(pattern inherited from `/strategy` and `/explore`). If the header
is absent, `/charter` MUST default to Private and emit a warning
to the author. The warning text follows the shipped `/strategy`
phrasing: "Default to Private if unknown — restricting is easier
to undo than oversharing." Public repos with a missing header are
a known limitation — `/charter`'s default-Private behavior would
surface `/comp` in a repo that should not see it.

**R13 [pattern-level].** `/charter` SHALL treat invoking any child
skill directly outside `/charter` (manual fallback) as first-class
steady-state behavior. `/charter` MUST NOT prevent or warn against
direct child invocation. On the next `/charter` resume, the resume
ladder detects out-of-chain edits via `child_snapshots` comparison
and surfaces staleness with three concrete options (re-run the
downstream child, accept downstream as still-valid, proceed without
the downstream).

**R14 [pattern-level].** A parent skill SHALL wait for the invoked
child to complete its own finalization phase before deciding the
next step. The parent reads the child doc's frontmatter `status:`
value after the child returns. The parent MUST NOT inspect the
child's intermediate `wip/research/<child>_<topic>_phase<N>_*.md`
verdict files or any other child internals; the contract surface
is the child's durable artifact status, full stop.

### Non-Functional Requirements

**R15 [/charter-specific].** `/charter` SHALL produce artifacts that
pass `shirabe validate` on commit. Specifically:
- Draft STRATEGY MUST NOT contain Competitive Considerations
  sections when committed to a public repo (R8 of `shirabe
  validate` catches violations; this is `/strategy`'s constraint
  inherited).
- Decision Records (both sub-shapes) at
  `docs/decisions/DECISION-strategy-<topic>-<sub-shape>-<YYYY-MM-DD>.md`
  MUST follow the ADR-style body shape (Status, Context, Decision,
  Options Considered, Consequences) with frontmatter. Frontmatter
  field formats:
  - `status:` one of `{Draft, Accepted}` (an enum value, not free
    text);
  - `decision:` a single short sentence stating the decision
    conclusion (e.g., "bet still holds; no revision warranted" /
    "Draft STRATEGY rejected; no STRATEGY warranted");
  - `rationale:` a 1-3 sentence justification (~250 characters
    soft cap) referencing the body's Context or Options.
  The `DECISION-` prefix matches shirabe's `<TYPE>-<name>.md`
  pattern (BRIEF-, DESIGN-, PLAN-, PRD-, ROADMAP-, STRATEGY-,
  VISION-). Per-sub-shape body content requirements:
  - **Re-evaluation:** Context cites the new evidence reviewed
    (at least one named evidence item — URL, file path, or
    paraphrased finding). Decision states "bet still holds; no
    revision warranted." Options Considered names "revise the
    STRATEGY" and "force-abandon and rewrite" as rejected
    alternatives with evidence. Consequences describes what
    remains in effect (the existing STRATEGY stays
    Accepted/Active; no ROADMAP regeneration) and what triggers
    the next re-evaluation. References the existing STRATEGY by
    path.
  - **Rejection:** Context cites the chain's discovery and the
    Draft STRATEGY's framing. Decision states "Draft STRATEGY
    rejected; no STRATEGY warranted" with the author's stated
    rejection rationale. Options Considered names "accept the
    Draft" and "revise instead of reject" as rejected
    alternatives. Consequences describes the post-rejection
    state (no STRATEGY on disk; chain discarded; next steps for
    the strategic question — open it again later, reframe,
    drop). References the discard commit SHA.
- Abandonment-forced artifacts MUST be schema-compliant in the
  same shape as a full-run artifact. The abandonment-forced
  metadata MUST live in an HTML-comment marker
  (`<!-- charter-status-block: abandonment-forced; ... -->`)
  inside the artifact's existing Status section, NOT in a new
  required section that would invalidate the artifact-type schema.

**R16 [/charter-specific].** `/charter` SHALL respect a 7-day
stale-session threshold for distinguishing "broke for lunch" from
"abandoned for a week." The boundary fires at `≥` 7 days from
the state file's `last_updated` timestamp (consistent with AC17
and R11's resume-ladder ordering; US-3b's narrative uses the
same boundary). The threshold is fixed in v1; a future release
may make it configurable.

**R17a [pattern-level].** A parent skill SHALL ship CLAUDE.md
updates that surface its entry triggers and discovery surface.
Workspace and shirabe CLAUDE.md documentation MUST mention the
skill so that authors discover it through the same channels they
discover shipped child skills.

**R17b [/charter-specific].** The CLAUDE.md trigger phrases for
`/charter` SHALL include: "start a strategic conversation about
X", "open a charter for Y", "I need to think through the bet on
Z", or direct `/charter <topic>` invocations. The phrase list is
charter-specific; the requirement to ship CLAUDE.md updates
(R17a) is pattern-level.

**R18 [pattern-level].** A parent skill SHALL ship skill evals at
`skills/<name>/evals/evals.json`. Per the shirabe authoring
convention, evals MUST be run via `scripts/run-evals.sh <name>`
before merging. For `/charter`, the eval scenarios MUST cover the
five user stories defined in this PRD (US-1, US-2, US-3a, US-3b,
US-4); the requirement to ship evals is pattern-level, the
scenarios chosen are charter-specific.

**R19 [pattern-level].** A parent skill's orchestration layer
(team-lead, whether the parent itself for single-agent parents or
the coordinator inside a team-emitting parent) SHALL implement the
**team-lead operating discipline**: a sleep-check-nudge loop that
runs for the duration of any dispatched work. The discipline is
substrate-agnostic — it survives the amplifier-layer migration
because filesystem evidence is a strictly stronger source of truth
than message delivery. The canonical 5-step loop:

1. **Dispatch.** Team-lead sends a structured directive to the
   teammate, records the dispatch in working memory (teammate,
   task, dispatch timestamp, expected artifacts, response window).
2. **Bounded sleep.** Team-lead sleeps for the task-class window
   (see priority ordering and timing below) before checking for
   evidence. Sleep is a scheduling primitive — team-lead MAY
   interleave its own work within the window; it MUST NOT exceed
   the window without checking.
3. **Filesystem evidence check (priority 1).** Team-lead inspects
   the filesystem for terminal artifacts, partial artifacts, new
   git commits, or growing `wip/` files. Filesystem evidence is
   durable, cheap, and unambiguous; it precedes inbox processing
   because message delivery is best-effort.
4. **Inbox processing (priority 2).** If no filesystem evidence
   advances the work, team-lead processes structured teammate
   messages (PASS / FAIL / PROGRESS / BLOCKED verdicts). Idle-status
   pings are infrastructure noise and SHALL NOT count as inbox
   messages.
5. **Nudge (priority 3).** If neither filesystem nor inbox advances
   the work, team-lead sends a nudge containing **directly-executable
   instructions**: what artifact to produce, where to write it, what
   structured verdict to reply with. Nudges SHALL NOT ask open-ended
   questions ("what's happening?", "are you stuck?").

The loop has exactly **three terminal exit conditions**:

- **PASS.** Terminal artifact present and valid at expected path,
  OR structured teammate message with `verdict: PASS` (with
  artifact-existence verification before proceeding).
- **FAIL.** Structured teammate message with `verdict: FAIL`, OR
  artifact present but failing validation. Team-lead routes to the
  parent's recovery flow.
- **ESCALATE.** Patience budget exhausted (default 5 stagnation
  cycles per teammate, where stagnation = no progress in either
  filesystem or inbox). Team-lead surfaces a concrete state dump
  to the user-proxy with a recommended intervention.

Indefinite passive wait is NOT a valid exit; this is the contract
the discipline enforces. The patience budget counts stagnation
cycles, not total cycles — a cycle that surfaces progress evidence
(even partial) resets the budget implicitly.

**Task-class timing parameters.** Default sleep windows and
patience budgets vary by task class:

| Task class | Default sleep | Patience budget |
|---|---|---|
| Review verdict (reviewer reads a doc, returns PASS/FAIL) | 30s | 5 cycles |
| Decomposition / generation (decomposer writes an issue body) | 60s | 10 cycles |
| Implementation pass (peer applies code changes, runs tests) | 120s | 10 cycles |
| External wait (CI run, network operation) | 60s | unlimited |

External waits poll status surfaces (CI rollup, exit codes) rather
than nudge; the work is external, team-lead has no leverage to
nudge it faster.

**`ci_outcome` semantics for CI-driven exits.** When team-lead
polls CI to completion, the recorded outcome distinguishes
`passing` (CI was always green) from `failing_fixed` (CI was
failing, then a fix commit flipped it green). The two are not
interchangeable; `failing_fixed` records that intervention
occurred.

R19 is encoded in the design as invariant **I-7 (Active
Orchestration)** plus reference-implementation content in
`references/parent-skill-pattern.md`. `/charter` v1 is single-agent
(no peer dispatch within `/charter` itself), so R19 binds vacuously
to `/charter`'s own orchestration; its child invocations
(`/vision`, `/strategy`, `/roadmap`) are dispatches in the
team-lead-discipline sense and inherit the loop. Future
team-emitting parents (`/scope`, `/work-on` migration) bind R19
concretely with their own task-class defaults.

## Acceptance Criteria

Each criterion is binary pass/fail. ACs trace to both the
requirement that motivates them and the user story they exercise
(where applicable). Verification entry points are noted per AC:
`[automated-unit]`, `[automated-eval]`, or `[manual-review]`.

### Skill loading and slug constraint

- [ ] **AC1** `/charter` loads as a slash command from
  `skills/charter/SKILL.md`. The SKILL.md frontmatter declares
  `name: charter`. `[automated-unit]` (R1)
- [ ] **AC1b** `skills/charter/SKILL.md` contains sections matching
  each of the 7 required structural elements named in R1: an Input
  Modes section, execution-mode flag-parsing, a topic-slug
  constraint statement, a Workflow Phases diagram, a Resume Logic
  ladder, a Phase Execution list, and a Reference Files table.
  Each MUST be present AND non-empty. `[automated-unit]` (R1)
- [ ] **AC2** Invoking `/charter` with no `$ARGUMENTS` produces a
  cold-start prompt asking for the topic. `[automated-eval]`
  (R2, US-1)
- [ ] **AC3** Invoking `/charter Hello World` (whitespace in slug)
  is rejected at Phase 0 with a clear error message; the chain
  does not proceed. `[automated-eval]` (R3)
- [ ] **AC3b** `/charter` rejects `$ARGUMENTS` containing uppercase
  letters (`/charter MyTopic`), underscores (`/charter my_topic`),
  dots (`/charter my.topic`), or other characters outside
  `[a-z0-9-]`. Each rejection MUST surface a clear error naming
  the violated pattern. `[automated-eval]` (R3)
- [ ] **AC4** Invoking `/charter docs/visions/VISION-foo.md` (path
  as `$ARGUMENTS`) is treated as a freeform topic after slug
  derivation; not interpreted as an upstream path.
  `[automated-eval]` (R2)

### Child invocation signals

- [ ] **AC5** When `docs/visions/VISION-<topic>.md` does not exist
  AND the author's Phase 1 discovery does not surface thesis-shift,
  the chain proposal does not include `/vision`. The observable:
  the chain proposal output (R7.5) does NOT contain the literal
  substring "/vision". `[automated-eval]` (R4, US-1)
- [ ] **AC6** When the author's Phase 1 discovery surfaces a
  thesis-shift signal (per R4's three utterance categories), the
  chain proposal includes `/vision`. The observable: the chain
  proposal output (R7.5) contains the literal substring
  "/vision". The invocation passes only the topic slug; no
  API-level "treat as revision" signal is required.
  `[automated-eval]` (R4)
- [ ] **AC7** When invoked in a public repo, `/charter`'s Phase 1
  discovery and chain proposal output do NOT contain any of the
  literal substrings: "/comp", "competitive analysis",
  "competitive framing". This holds regardless of input text
  (including a topic slug that mentions a competitor's name).
  `[automated-eval]` (R5, R12)
- [ ] **AC8** When invoked in a private repo with
  `skills/comp/SKILL.md` absent, the chain proposal output (the
  R7.5 prompt's content) is byte-identical to a public-repo
  invocation for the same topic. `[automated-eval]` (R5)
- [ ] **AC9** When the just-produced STRATEGY has fewer than 3
  Building Blocks OR no Coordination Dependencies section OR a
  Coordination Dependencies section with no qualifying entry
  (per R7), `/charter` skips `/roadmap` and exits at full-run
  with STRATEGY only. `[automated-eval]` (R7, US-1)
- [ ] **AC10** When the just-produced STRATEGY has 3+ Building
  Blocks AND a Coordination Dependencies section with at least
  one non-empty entry referencing another Building Block by name,
  `/charter` invokes `/roadmap` with `--upstream <strategy-path>`
  AND a pre-populated `wip/roadmap_<topic>_scope.md`.
  `[automated-eval]` (R7, US-1)
- [ ] **AC10b** When `/charter` Phase 1 identifies an existing PRD
  as the chain's framing, `/strategy` is invoked with the PRD
  path as upstream (per R6's three valid input shapes — freeform
  topic, VISION path, PRD path). The state-file's `chain_started`
  context records the PRD path as the chain framing.
  `[automated-eval]` (R6)
- [ ] **AC10c** `/charter` never passes a STRATEGY path to
  `/strategy`. Observable: across all `/charter` runs, the
  arguments passed to `/strategy` in `chain_ran` records contain
  no path matching `docs/strategies/STRATEGY-*.md`.
  `[manual-review]` of code paths (R6).

### Chain-proposal confirmation prompt

- [ ] **AC10d** `/charter` Phase 1 produces a chain-proposal
  confirmation prompt (the "chain proposal output") at the end of
  discovery, containing the literal substrings "Proceed",
  "Adjust", and "Bail" (case-insensitive). The prompt lists the
  children that will be invoked in chain order.
  `[automated-eval]` (R7.5, US-1)
- [ ] **AC10e** Selecting "Adjust" at the chain-proposal prompt
  routes the chain back to Phase 1 discovery for redirection
  before any child fires. `[automated-eval]` (R7.5)
- [ ] **AC10f** Selecting "Bail" at the chain-proposal prompt
  routes per R8's bail-handling: abandonment-forced if any wip
  state for this topic exists, clean-cancel otherwise.
  `[automated-eval]` (R7.5, R8)

### Exit-path enforcement

- [ ] **AC11a** After a chain that completes with STRATEGY only
  (no ROADMAP), `wip/charter_<topic>_state.md` contains
  `exit: full-run` and `exit_artifacts` lists exactly one entry
  pointing to `docs/strategies/STRATEGY-<topic>.md`.
  `[automated-eval]` (R8, R10, US-1)
- [ ] **AC11b** After a chain that completes with STRATEGY AND
  ROADMAP, `wip/charter_<topic>_state.md` contains
  `exit: full-run` and `exit_artifacts` lists two entries: the
  STRATEGY path and the ROADMAP path, each with the correct
  status. `[automated-eval]` (R8, R10, US-1)
- [ ] **AC12** After a re-evaluation chain that confirms the bet
  holds,
  `docs/decisions/DECISION-strategy-<topic>-re-evaluation-<YYYY-MM-DD>.md`
  is written; the existing STRATEGY is unchanged; the state file
  contains `exit: re-evaluation`,
  `decision_record_sub_shape: re-evaluation`, and
  `referenced_strategy: <strategy-path>`. The Decision Record's
  Context section cites at least one named evidence item (URL,
  file path, or paraphrased finding); the Decision Record's
  Options Considered section names "revise the STRATEGY" AND
  "force-abandon and rewrite" as rejected alternatives.
  `[automated-eval]` (R8, R10, R15, US-2)
- [ ] **AC12b** US-2 entry-router **Revise** branch: when the
  author picks "Revise" at the entry router for an existing
  Accepted STRATEGY, `/charter` invokes `/strategy` with the
  existing STRATEGY path (`/strategy` enters its
  resume-from-Accepted offer-to-revise flow), produces a revised
  Draft STRATEGY, and the chain exits at full-run with the
  revised artifact recorded in `exit_artifacts`.
  `[automated-eval]` (R8, US-2)
- [ ] **AC12c** US-2 entry-router **Bail** branch (and chain-proposal
  Bail per AC10f): when the author picks "Bail" at the entry
  router or at the chain-proposal prompt and prior wip state
  exists for the topic, the chain routes to abandonment-forced;
  when no wip state exists, clean-cancel fires (no state file
  written, no terminal artifact, no contract violation).
  `[automated-eval]` (R8, US-2)
- [ ] **AC13** When `/strategy` Phase 5 Reject fires inside a
  `/charter` chain, `/charter` writes
  `docs/decisions/DECISION-strategy-<topic>-rejection-<YYYY-MM-DD>.md`
  immediately after `/strategy`'s discard commit lands; the state
  file contains `exit: re-evaluation`,
  `decision_record_sub_shape: rejection`,
  `discard_commit_sha: <sha>`, and `rejection_rationale: <text>`.
  The rejection Decision Record's Context section references the
  discard commit SHA; the Options Considered section names
  "accept the Draft" AND "revise instead of reject" as rejected
  alternatives. `[automated-eval]` (R8, R10, R15, US-3a)
- [ ] **AC14** After `/charter` force-materializes an intermediate
  (author bail per AC12c, or stale-session detection per AC17),
  the resulting artifact contains an HTML-comment marker
  `<!-- charter-status-block: abandonment-forced; ... -->` inside
  its Status section; the state file contains
  `exit: abandonment-forced`, `triggering_child: <child-name>`
  (resolved via R8's tie-break), and `partial_phase_reached:
  <phase>`. `decision_record_sub_shape` is absent (per R9).
  `[automated-eval]` (R8, R10, R15, US-3b)
- [ ] **AC14b** When the author bails inside an invoked child
  (`/vision`, `/comp`, or `/roadmap` — not just `/strategy`),
  `/charter`'s resume ladder on the next entry routes to
  abandonment-forced per US-3b semantics; the artifact
  force-materialized is the child that was running at the time
  of bail. `[automated-eval]` (R8, US-3b)
- [ ] **AC15** A `/charter` run that completes without recording
  a valid `exit:` value (or with `exit: re-evaluation` but no
  `decision_record_sub_shape:`, or with conditional fields set
  when their triggering condition does not hold per R9) fails
  finalization with a clear error.
  `[automated-eval]` (R9)

### Resume ladder

- [ ] **AC16** When a partial state file exists and
  `last_updated` is less than 7 days old, `/charter` resumes at
  the recorded phase without prompting Force-materialize.
  `[automated-eval]` (R10, R11)
- [ ] **AC17** When a partial state file exists and
  `last_updated` is `≥` 7 days old, `/charter` surfaces a
  three-option prompt: Resume / Force-materialize / Discard. The
  prompt fires on every invocation until the author chooses.
  Selecting "Force-materialize" triggers the abandonment-forced
  exit per AC14 (writes the marker, sets state-file fields).
  `[automated-eval]` (R11, R16, US-3b)
- [ ] **AC18** When `docs/strategies/STRATEGY-<topic>.md` is
  Accepted/Active, the entry prompt MUST contain the literal
  substrings "Re-evaluate", "Revise", and "Bail"
  (case-insensitive) as the three options offered, AND MUST NOT
  contain the literal substring "Continue / Start fresh".
  `[automated-eval]` (R11, US-2 wording is load-bearing)
- [ ] **AC18b** US-3a/AC13 verification: when `/strategy` Phase 5
  fires Reject outside a `/charter` chain (the author invokes
  `/strategy` directly and rejects), `/charter` does NOT
  retroactively write a rejection Decision Record on a later
  `/charter` resume — the rejection sub-shape is
  `/charter`-orchestrated only; manual-fallback rejection leaves
  only the discard commit as the durable trace (by design).
  `[automated-eval]` (R13, US-3a)
- [ ] **AC19** When `child_snapshots.strategy.status` OR
  `child_snapshots.strategy.content_hash` differ from the live
  STRATEGY's current `status:` or current git blob hash, the
  resume ladder surfaces a staleness warning with three concrete
  options (re-run downstream, accept downstream as still-valid,
  proceed without downstream). Drift fires when EITHER differs;
  the content-hash check covers the case where status stays
  Draft but body was rewritten. `[automated-eval]` (R10, R11,
  R13, US-4)
- [ ] **AC20** When `/charter` invokes a child whose durable doc
  is already Accepted, the next prompt the author sees is one of
  `/charter`'s prompt vocabulary (e.g., "Re-evaluate / Revise /
  Bail") — NOT `/strategy`'s "Continue / Start fresh" vocabulary
  or any other child's status-aware re-entry prompt. The
  mechanism by which suppression happens is a design-team choice;
  the observable is the prompt-vocabulary substring match.
  `[automated-eval]` (R11)
- [ ] **AC20b** R14 child-internals isolation: during and after a
  `/charter` chain, `/charter`'s decision logic depends only on
  (a) child doc frontmatter, (b) the topic slug, and (c) its own
  state file — never on a child's internal
  `wip/research/<child>_<topic>_phase<N>_*.md` files or any other
  child internals. Verified by code-path review against the
  SKILL.md prose. `[manual-review]` (R14)
- [ ] **AC20c** Malformed state file on resume: when
  `wip/charter_<topic>_state.md` is unparseable, missing required
  fields for its recorded phase, or has an invalid `exit:` /
  `decision_record_sub_shape:` combination, `/charter` surfaces a
  clear error and offers Discard as a recovery path; it does NOT
  silently fall through to Phase 0. `[automated-eval]` (R11)

### Visibility and manual fallback

- [ ] **AC21** When CLAUDE.md lacks a `## Repo Visibility:` header,
  `/charter` defaults to Private AND emits a warning containing
  the literal phrasing "Default to Private if unknown" and naming
  the missing `## Repo Visibility:` header. `[automated-eval]`
  (R12)
- [ ] **AC22** An author invoking `/strategy` directly outside
  `/charter` produces no `/charter` interference; `/charter` does
  not surface a warning, does not block, does not modify state
  files. `[manual-review]` (R13, US-4)
- [ ] **AC23** On the next `/charter` resume after a direct child
  invocation that edited the child doc, the staleness detection
  in AC19 fires. `[automated-eval]` (R13, US-4)

### Schema and validation

- [ ] **AC24** Draft STRATEGY written by `/charter`'s `/strategy`
  delegation passes `shirabe validate
  --visibility=<repo-visibility>`. `[automated-unit]` (R15)
- [ ] **AC25** Both Decision-Record sub-shapes (re-evaluation and
  rejection) contain the required ADR-style sections (Status,
  Context, Decision, Options Considered, Consequences) and
  frontmatter (`status`, `decision`, `rationale` — `status` ∈
  {Draft, Accepted}, `decision` and `rationale` are non-empty
  strings). Per-sub-shape body content is verified by AC12 and
  AC13. `[automated-unit]` (R15)
- [ ] **AC26** Force-materialized artifact passes the same
  schema validators as a full-run artifact (the abandonment-forced
  HTML-comment marker is inside the existing Status section, not
  in a new required section). `[automated-unit]` (R15)

### CLAUDE.md surfacing and evals

- [ ] **AC26b** Workspace CLAUDE.md and shirabe CLAUDE.md (the
  files in this PRD's source tree) mention `/charter` and include
  the trigger phrases listed in R17b. `[automated-unit]` (R17a,
  R17b)
- [ ] **AC26c** `skills/charter/evals/evals.json` contains at
  least one eval scenario tagged for each user story: US-1, US-2,
  US-3a, US-3b, and US-4. All scenarios pass under
  `scripts/run-evals.sh charter`. `[automated-eval]` (R18)

### `_discover.md` resume detection

- [ ] **AC26d** When `wip/strategy_<topic>_discover.md` exists
  (the file actually written by `/strategy` Phase 1) but
  `wip/strategy_<topic>_scope.md` does not, `/charter`'s resume
  ladder detects the partial `/strategy` run and resumes into
  `/strategy`. The ladder MUST NOT incorrectly look for
  `_scope.md`. `[automated-eval]` (R11)

### Team-lead operating discipline (R19)

- [ ] **AC27** The team-lead operating discipline (sleep-check-nudge
  loop) fires immediately after any dispatch — that is, after
  `/charter` invokes a child skill (`/vision`, `/strategy`,
  `/roadmap`) or any future team-emitting parent's coordinator
  dispatches a teammate. Team-lead MUST NOT transition to indefinite
  passive wait on the inbox. The observable in
  `references/parent-skill-pattern.md`: a Team-Lead Operating
  Discipline section names the loop as the default behavior after
  dispatch. `[automated-unit]` (R19)
- [ ] **AC28** The discipline loop's evidence-check ordering puts
  **filesystem before inbox**: each cycle inspects expected
  artifact paths, git log, and `wip/` file growth as priority 1
  before processing teammate messages as priority 2. The
  observable: `references/parent-skill-pattern.md` documents the
  three-priority ordering with filesystem first; eval scenarios
  verify the ordering via assertion strings on the priority list.
  `[automated-eval]` (R19)
- [ ] **AC29** Nudges sent by team-lead contain
  **directly-executable instructions** — what artifact to produce
  or what action to take, where to write it on the filesystem, and
  what structured verdict to reply with. Nudges MUST NOT consist
  of open-ended questions ("what's happening?", "are you stuck?").
  The observable: the nudge template documented in
  `references/parent-skill-pattern.md` names directly-executable
  content; AC violation surfaces if the template uses open-ended
  question phrasing. `[automated-unit]` (R19)
- [ ] **AC30** The patience budget exhausts at exactly **5
  stagnation cycles** per teammate for the default review-verdict
  task class (not before, not after). A cycle counts as
  "stagnation" only when neither filesystem evidence nor inbox
  message advances the work; cycles that surface progress evidence
  (partial artifact, new commit, `wip/` growth, PROGRESS verdict)
  reset the budget implicitly. The observable:
  `references/parent-skill-pattern.md` names the 5-cycle default
  and the stagnation-counting rule; eval scenarios verify the
  budget boundary. `[automated-eval]` (R19)
- [ ] **AC31** `ci_outcome` recording for CI-driven exits
  distinguishes `passing` (CI always green) from `failing_fixed`
  (CI was failing, then a fix commit flipped it green). The two
  values MUST NOT be conflated. The observable: when team-lead
  polls CI to completion after a fix commit lands, the recorded
  `ci_outcome` is `failing_fixed`, not `passing`. `[manual-review]`
  of code paths (R19).

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
- **Revisions to the `/roadmap` SKILL.md or phases.** `/roadmap`'s
  Phase 3 code accepts a STRATEGY path as `--upstream` verbatim
  (no basename check); only the format-spec prose at
  `roadmap-format.md` names VISION as the "natural" upstream.
  Updating that prose to acknowledge STRATEGY upstream as
  first-class is a minor follow-up fix to `/roadmap`'s docs and
  out of scope for `/charter` v1.
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
- **Cross-topic resume in the same session.** The state file is
  topic-keyed by filename
  (`wip/charter_<topic>_state.md`), so concurrent or sequential
  invocations against different topics in the same session do
  not interfere. v1 does NOT support resume against a different
  topic mid-chain; the resume ladder is per-topic. Stating this
  explicitly to forecloses a class of bug reports.

## Questions Deferred to Design

The PRD made its decisions; the questions below are legitimate
design-altitude inputs for the downstream design phase. Each
names the area and where the resolution should land.

1. **Engine extraction location for the discover/converge engine.**
   The engine currently lives in
   `skills/explore/references/phases/`. Whether `/charter` consumes
   it cross-skill (status quo) or whether the engine moves to a
   top-level `references/` directory (signaling shared
   infrastructure) is a design-team decision. The PRD specifies
   the engine is referenced, not where it lives.

2. **Dual-implementation contract.** `/charter` ships against
   `wip/`-based intermediates (the current shirabe pattern for all
   non-koto skills); the future `/work-on` migration will live in
   a different workflow substrate. The freeze line between the
   two implementations is the design-team's call. The resume
   contract IS storage-agnostic (named state fields + child-doc
   inspections), and the wip/-specific hygiene rules
   (cleanup-before-merge, no-orphan-references) are orthogonal —
   the contract bounds the substitution surface but does not pick
   the substrate.

3. **Shared design doc authoring timing.** Whether
   `docs/designs/DESIGN-shirabe-progression-authoring.md` is
   authored alongside this PRD or deferred until at least one
   other parent skill (`/scope` or `/work-on` migration) is in
   scope to validate pattern-level claims. The PRD's
   `[pattern-level]` tags are useful regardless; the question is
   whether the designer lifts them now or later.

4. **Cross-branch state-file behavior under `wip/`.** The state
   file under wip/ is branch-coupled — `/charter` resume requires
   the same feature branch as the original run. If `/charter`'s
   exit-tracking ever needs to cross branches (e.g., merge a
   child's PR, then resume `/charter` on main to invoke the next
   child), the wip/-based model breaks. No `/charter` v1
   requirement forces cross-branch resume; the limitation is
   flagged for the designer to consider when the workflow-substrate
   work is bounded.

5. **Competitive-framing signal detection in private repos.** When
   `/comp` ships, `/charter`'s recommended-default for offering
   `/comp` depends on detecting "competitive framing signals"
   (competitor name, externally-framed bet, market-share language)
   during Phase 1. The detection mechanism is agent judgment with
   the PRD specifying broad signal categories; the implementation
   detail (keyword list vs LLM judgment vs structured prompt) is a
   design-team decision when the `/comp` integration goes live.

6. **Team persistence across the parent-skill chain.** The
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
  `DECISION-strategy-<topic>-<sub-shape>-<YYYY-MM-DD>.md` to
  `docs/decisions/` following shirabe's `<TYPE>-<name>.md` pattern
  but does not register a `decision` artifact type in `shirabe
  validate`. A separate feature can later formalize the artifact
  category with full validator rules if warranted. The
  divergence from the workspace's private-overlay `ADR-*`
  convention is intentional — shirabe is public and codifies
  `DECISION-` as its own decision-record convention.

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

### Decision 5: Rejection is the rejection sub-shape of the re-evaluation exit

**Decided.** The re-evaluation exit produces a Decision Record
file and has two first-class sub-shapes: the re-evaluation
sub-shape (existing STRATEGY holds; lightweight conclusion) and
the rejection sub-shape (Draft STRATEGY authored and explicitly
rejected at `/strategy`'s finalization gate). When `/strategy`
Phase 5 Reject fires inside a `/charter` chain, `/charter` writes
`docs/decisions/DECISION-strategy-<topic>-rejection-<YYYY-MM-DD>.md`
immediately after `/strategy`'s discard commit lands. The state
file records `exit: re-evaluation`,
`decision_record_sub_shape: rejection`,
`discard_commit_sha: <sha>`, and `rejection_rationale: <text>`.
The brief's three-exit list (full-run, re-evaluation,
abandonment-forced) stands literally.

**Alternatives considered.**

(a) **Treat Reject as abandonment-forced (rejected, considered
in depth).** The earliest framing in this PRD's drafting was that
Reject "subsumes" into the abandonment-forced exit, with
`partial_phase_reached: rejected` and `discard_commit_sha:
<sha>` recorded in the state file. This framing was rejected on
review because it was incoherent on two grounds: first, the
user's explicit judgment at `/strategy`'s Phase 5 finalization
gate is structurally different from a bail (the user actively
confirmed "delete this STRATEGY" rather than walking away);
second, abandonment-forced requires a most-recently-running
child's intermediate to force-materialize, but on `/strategy`
Reject the STRATEGY draft AND all `wip/strategy_<topic>_*.md`
files are deleted by `/strategy` itself — there is no
intermediate left to materialize. The subsumption framing
contradicted AC13's "writes a Decision Record" with AC14's "no
charter-level Decision Record is written" depending on which
path one read first.

(b) **Add a fourth exit category "discarded".** Preserves naming
precision (each exit means exactly one thing) but breaks the
brief's three-exit count literally. The brief commits to three
exits as the contract; a fourth category would require brief
revision.

(c) **Treat Reject as a no-op exit with git history as the
audit trail.** This was attractive for simplicity — the `git rm
docs/strategies/STRATEGY-<topic>.md` commit message already
captures the rationale, and `git log` is queryable. It was
rejected because it violates the brief's "every chain lands at
a durable file" commitment literally. `git log` entries are not
shirabe `<TYPE>-` artifacts; downstream readers consume `docs/`
not `git log -p`. The discipline-vs-artifact decoupling thesis
requires the rejection conclusion to be a first-class artifact,
not an audit trail.

**Reasoning.** Re-evaluation and rejection express the same
architectural intent: a strategic conversation concluding without
a STRATEGY artifact. The re-evaluation sub-shape says "existing
strategy holds"; the rejection sub-shape says "considered
strategy and no artifact warranted." Both produce a DECISION-
record at the same altitude. Naming them as sub-shapes under the
re-evaluation exit keeps the brief's three-exit list verbatim
while honoring the durable-file commitment. The distinction from
abandonment-forced is sharp: the rejection sub-shape fires on
explicit finalization judgment; abandonment-forced fires on bail.

The underlying principle behind the three-exit contract is the
**discipline-vs-artifact decoupling thesis**: strategic
conversation can be *disciplined* without being forced to
*produce*. The re-evaluation exit (with its two sub-shapes) is the
operational proof that a disciplined conversation can conclude at
a durable Decision Record rather than at a STRATEGY artifact;
abandonment-forced is the proof that even a chain that bails ends
at a review surface. Naming this thesis explicitly makes clear
why the three-exit shape has the structure it does — each exit
exists to demonstrate a specific decoupling property — and gives
downstream parent skills (`/scope`, `/work-on`) a principled
framing when they confront their own exit-shape decisions.

### Decision 6: `/charter` writes both re-evaluation sub-shapes inline

**Decided.** `/charter` writes both re-evaluation and rejection
Decision Records inline at
`docs/decisions/DECISION-strategy-<topic>-<sub-shape>-<YYYY-MM-DD>.md`,
using a shared ADR-style body shape (Status, Context, Decision,
Options Considered, Consequences) with frontmatter (`status`,
`decision`, `rationale`). The two sub-shapes share the body
template; their Context, Decision, and Options-Considered content
differ per sub-shape per R15. No delegation to a separate
decision-writing skill.

**Alternatives considered.** (a) Delegate to `/decision` and
promote its `wip/<prefix>_report.md` to a durable file — `/decision`
itself doesn't durably produce decision records; the indirection
adds complexity without reuse benefit. (b) Author a new sibling
skill `/decision-record` for shirabe core — out of scope per the
brief (no new sibling skills authorized).

**Reasoning.** Both re-evaluation-exit sub-shapes share the same
altitude and the same artifact shape. A single inline-write code
path covers both. The format matches shirabe's `<TYPE>-<name>.md`
precedent and integrates cleanly with the existing
`docs/decisions/` convention.

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

## Downstream Artifacts

`/charter`'s PRD is the upstream input for the following work.
Each downstream artifact owns its own acceptance criteria; the
linkages below are commitments this PRD makes to the downstream
artifact's framing.

- **`docs/designs/DESIGN-shirabe-progression-authoring.md`** — the
  shared design doc co-authored across the parent-skill pattern's
  three features (`/charter`, `/scope`, the `/work-on` migration).
  The design should lift every requirement tagged `[pattern-level]`
  in this PRD into its pattern-level scope so `/scope` and
  `/work-on` inherit the mechanism. The PRD's requirement-tagging
  is the baton; verifying the design respects it is the
  design doc's own acceptance check, not this PRD's. The
  pattern-level requirements at PRD acceptance time are: R1, R3,
  R9, R10, R11, R12, R13, R14, R17a, R18, R19 (11 requirements).
  R19 (team-lead operating discipline) is encoded in the design
  as invariant I-7 and a new Component 6 (Team-Lead Operating
  Discipline) on the pattern-skill reference.

- **`skills/charter/SKILL.md`** — the loadable skill itself. AC1
  through AC1b verify the structural template.

- **`skills/charter/evals/evals.json`** — eval scenarios covering
  US-1 through US-4 (per R18 and AC26c).

- **Workspace and shirabe CLAUDE.md updates** — surface `/charter`
  entry triggers (per R17a, R17b, and AC26b).

- **Follow-up minor fix to `skills/strategy/SKILL.md`** —
  optional: update the Resume Logic ladder to reference
  `wip/strategy_<topic>_discover.md` (the file actually written)
  instead of `_scope.md` (referenced but never written). Out of
  scope for `/charter` v1; flagged here so a future PR closes the
  asymmetry that `/charter` accommodates.

- **Follow-up minor fix to `skills/roadmap/references/roadmap-format.md`**
  — optional: update the format-spec prose to acknowledge that
  `upstream:` accepts STRATEGY paths as first-class (the code
  already does; only the prose says "typically VISION"). Out of
  scope for `/charter` v1.
