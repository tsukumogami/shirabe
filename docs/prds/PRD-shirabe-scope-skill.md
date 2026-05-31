---
status: Done
problem: |
  shirabe ships `/brief`, `/prd`, `/design`, and `/plan` at the
  tactical chain's altitude as four direct-invocation child skills,
  but has no parent skill that walks an author through the chain as
  a sequence, enforces the three-exit contract across BRIEF/PRD/
  DESIGN/PLAN boundaries, or proves the parent-skill pattern v1
  against the tactical chain's asymmetries (an extra re-evaluation
  boundary at the DESIGN level, no Phase-N Reject finalization on
  `/prd` or `/design`, a terminal child with two output modes).
  Authors today sequence the chain by hand; the pattern stays
  unratified for the parent skills that follow.
goals: |
  An author invokes `/scope`, the skill orients on the durable
  upstream artifacts already on disk (BRIEF, PRD-Accepted, DESIGN
  at `current/`, PLAN at any of Draft/Active/Done), proposes a
  chain from the most-downstream settled point, and walks the
  children under their per-gate semantics. The conversation lands
  at one of three durable exits — full-run at PLAN, re-evaluation
  Decision Record at PRD- or DESIGN-boundary, abandonment-forced
  materialization — with cross-boundary resume and manual fallback
  as first-class steady-state surfaces. `/scope` shipping ratifies
  the parent-skill pattern v1 against a chain with materially
  different shape than `/charter`'s.
upstream: docs/briefs/BRIEF-shirabe-scope-skill.md
---

# PRD: shirabe-scope-skill

## Status

Done

## Problem Statement

shirabe today ships `/brief`, `/prd`, `/design`, and `/plan` as
four loadable child skills at the tactical chain's altitude.
`/brief` frames a feature before requirements; `/prd` captures
requirements; `/design` works the architecture; `/plan` decomposes
a design into atomic implementable issues, in either single-pr or
multi-pr output mode. The four exist; each validates under its own
format reference; each is well-trodden. What's missing is the
parent layer: a skill that walks an author through the tactical
conversation as a *sequence*, deciding which children to invoke
against the upstream artifacts already on disk, carrying scope
between BRIEF and PRD and DESIGN and PLAN boundaries without the
author having to remember the order, and enforcing the same
three-exit contract `/charter` made first-class for the strategic
chain.

In the absence of a parent skill, authors today reach for the
tactical chain as four separate invocations. They re-derive the
sequencing decisions on every run: when does a BRIEF dog-food in?
when is a DESIGN warranted given the PRD's complexity? when does
the PLAN's `single-pr` versus `multi-pr` choice fire? They carry
context manually with no resume contract if the session breaks
across child boundaries — and the tactical chain breaks across
boundaries more often than the strategic one, because requirements
and design churn faster than thesis. They have no enforcement that
the chain produces a durable terminal artifact rather than evidence
files in `wip/`. The work is done by discipline alone, and
discipline is the wrong substrate for an invariant.

The deeper problem is that the parent-skill pattern v1 — the
contract `/charter` validated on the strategic chain — has
invariants that cannot be ratified for the parent skills that
follow until a second parent stands them against a chain with
genuinely different shape. The tactical chain's asymmetries
concentrate at three points where the strategic chain has no
analog:

- **Two settled-upstream boundaries instead of one.** The
  re-evaluation exit, which `/charter` exposes at exactly one point
  (an existing Accepted STRATEGY), multiplies in the tactical
  chain. A `/scope` run against a settled PRD asks the
  Re-evaluate/Revise/Bail question at the PRD boundary; against a
  settled DESIGN, at the DESIGN boundary. Two Decision Record
  sub-shapes need to exist, or the pattern's re-evaluation framing
  silently degrades to one of them.
- **No Phase-N Reject finalization on `/prd` or `/design` today.**
  `/charter`'s rejection sub-shape on the re-evaluation exit is
  gated on `/strategy`'s Phase 5 Reject verdict firing inside the
  chain. The tactical chain's children have no analogous reject
  finalization in their current contracts. Either the pattern's
  rejection sub-shape silently disappears in `/scope` (asymmetry
  inside the pattern contract that has nothing to do with the
  strategic/tactical distinction), or `/prd` and `/design` grow
  Phase-N Reject contracts as `/scope` prerequisites. This work takes
  the latter path to preserve symmetry.
- **A terminal child with two output modes.** `/plan`'s `single-pr`
  mode produces a self-contained PLAN doc; its `multi-pr` mode
  produces a PLAN doc plus a GitHub milestone with issues. The
  pattern's chain-tracking unit
  (`planned_chain`/`chain_ran`/`chain_skipped`) doesn't capture
  output-mode selection, and `/scope`'s state file needs to record
  the choice so re-entry against an Active PLAN reads the correct
  surface.

`/prd`'s invocation gate sits on top of those three asymmetries.
`/charter`'s three gate vocabularies — EITHER-signal, ALWAYS,
shape-dependent — don't fit `/prd` cleanly. The honest framing is
that `/prd` ALWAYS invokes unless an Accepted PRD already exists
for the topic; the auto-skip is real and load-bearing. The
pattern's gate vocabulary grows a fourth entry
(Mandatory-with-auto-skip) to name it explicitly.

Downstream, `/scope`'s shipping ratifies the parent-skill pattern
v1 for the parent skills that follow. The amplifier-layer parent
skill (the `/work-on` migration that follows) cannot inherit from a
pattern that has only one ground-truth example. `/scope` is the
second parent the pattern needs to ratify itself.

## Goals

- An author invokes `/scope` and is walked through the tactical
  chain — `/brief`, `/prd`, `/design`, `/plan` — without
  remembering the order, the gate semantics, or which child writes
  which artifact path.
- The chain ends at exactly one of three named exit paths
  (full-run at PLAN, re-evaluation Decision Record at PRD- or
  DESIGN-boundary, abandonment-forced materialization). The
  re-evaluation exit produces a durable Decision Record file at
  `docs/decisions/DECISION-{prd|design}-<topic>-<sub-shape>-<YYYY-MM-DD>.md`
  with two boundary positions (PRD or DESIGN) and two finalization
  sub-shapes (re-evaluation or rejection). Each combination shares
  the artifact body shape and inherits from the pattern's
  re-evaluation template with PRD- or DESIGN-specific load-bearing-
  claim walks.
- The chain is resumable mid-flight across four child boundaries.
  Resume detects partial child runs against any of the four
  `wip/{brief,prd,design,plan}_<topic>_*` artifact sets, plus
  status-aware re-entry against PLAN at three statuses (Draft,
  Active, Done) and DESIGN's directory-move lifecycle
  (`docs/designs/` vs `docs/designs/current/`).
- Manual fallback (author invokes a child directly outside
  `/scope`) is first-class steady-state capability across all four
  child boundaries. `/scope` warns about staleness but never acts
  unilaterally.
- The pattern-level edits the tactical chain's asymmetries
  motivate land cleanly inside the existing pattern surface: the
  fourth gate type (Mandatory-with-auto-skip) extends the existing
  gate vocabulary; the worktree-discipline reference lands at the
  top-level reference root; the L9 PRD pattern-level requirement
  tagging convention is reclassified to a required convention.
- The four `/scope` → child delegation contracts are documented at
  requirements altitude precise enough that the downstream design
  doc (`docs/designs/DESIGN-shirabe-scope-skill.md`) can lift
  pattern-level commitments into shared design and leave
  `/scope`-specific bindings in `/scope`'s scope.

## User Stories

The five user stories correspond to the five User Journeys in the
upstream brief. Each story names the trigger, the chain shape, the
exit, and what an author reviews after the run.

### US-1: Cold standalone invocation (full-run)

As a **skill author** with a feature to specify from scratch, I
want to invoke `/scope <topic-slug>` and be walked through `/brief`,
`/prd`, optional `/design`, and `/plan` without remembering the
chain order or the artifact-decision rules, so that I land at a
Draft or Active PLAN (depending on `/plan`'s output mode) with the
intermediate BRIEF, PRD, and DESIGN settled at their accepted
statuses.

Chain shape: `/scope` Phase 1 discovery → `/brief` (EITHER-signal
gate; fires when no Accepted BRIEF exists OR framing-shift signal
surfaces) → `/prd` (Mandatory-with-auto-skip; fires unless an
Accepted PRD already exists) → `/design` (shape-dependent; fires
when the just-produced PRD exposes architectural-decision surface)
→ `/plan` (ALWAYS-when-reached; terminal) → full-run exit.

What I review at end: the terminal PLAN at
`docs/plans/PLAN-<topic>.md` — Draft in `single-pr` mode, Active in
`multi-pr` mode alongside a GitHub milestone with issues — plus
the intermediate Accepted BRIEF, Accepted PRD, and (if produced)
Accepted DESIGN at `docs/designs/current/DESIGN-<topic>.md`. State
file at `wip/scope_<topic>_state.md` records `exit: full-run`.

### US-2: Author with PRD already Accepted (auto-skip /brief)

As a **skill author** returning to a feature whose PRD has already
landed (either by direct `/prd` invocation or by an earlier `/scope`
run interrupted after `/prd`'s Accepted transition), I want
`/scope` to detect the Accepted PRD on Phase 1, auto-skip `/brief`
(its framing is settled downstream by the PRD), propose a chain
that starts at `/design`, and walk the remaining children, so that
the chain doesn't redundantly re-author upstream artifacts.

Chain shape: `/scope` Phase 1 discovery detects existing Accepted
PRD → chain proposal lists `/brief` in `chain_skipped`, `/prd` in
`chain_skipped` (auto-skip-on-existing-Accepted), `/design`
(shape-dependent gate evaluation) → `/plan` (ALWAYS-when-reached)
→ full-run exit.

What I review at end: the terminal PLAN plus the unchanged
upstream PRD (and DESIGN if `/design` ran). State file records
`exit: full-run` and `chain_skipped` lists both `/brief` and
`/prd` with reasons referencing the existing Accepted PRD as
evidence.

### US-3a: Re-evaluation at the PRD boundary

As a **skill author** returning to a topic with an Accepted PRD
whose framing the author wants to re-evaluate before proceeding to
`/design`, I want `/scope` to ask the Re-evaluate/Revise/Bail
question at the PRD boundary, walk the PRD's load-bearing claims if
I pick Re-evaluate, and produce a Decision Record at the PRD
boundary rather than force a redundant PRD revision, so that
tactical discipline is empirically demonstrated without artifact
churn.

Chain shape: `/scope` Phase 1 discovery detects Accepted PRD →
entry router asks "Re-evaluate / Revise / Bail" at the PRD
boundary → author picks Re-evaluate → walks the PRD's load-bearing
Requirements and Acceptance Criteria with per-claim evidence
prompts → if all claims hold, proceeds to Decision Record drafting
→ re-evaluation exit (PRD-boundary, re-evaluation sub-shape).

What I review at end: the new Decision Record at
`docs/decisions/DECISION-prd-<topic>-re-evaluation-<YYYY-MM-DD>.md`,
referencing the existing PRD by path. The existing
`docs/prds/PRD-<topic>.md` remains unchanged (still Accepted). State
file records `exit: re-evaluation`, `boundary: prd`, and
`decision_record_sub_shape: re-evaluation`.

### US-3b: Re-evaluation at the DESIGN boundary

As a **skill author** returning to a topic six weeks after an
earlier `/scope` run landed an Accepted DESIGN, with new evidence
to assess before proceeding to `/plan`, I want `/scope` to ask the
Re-evaluate/Revise/Bail question at the DESIGN boundary, walk the
DESIGN's load-bearing decisions if I pick Re-evaluate, and produce
a Decision Record at the DESIGN boundary, so that the architecture
question is answered durably without a redundant DESIGN revision.

Chain shape: `/scope` Phase 1 discovery detects Accepted DESIGN at
`docs/designs/current/DESIGN-<topic>.md` and no downstream PLAN →
entry router asks "Re-evaluate / Revise / Bail" at the DESIGN
boundary → author picks Re-evaluate → walks the DESIGN's Decision
Drivers, Considered Options, and chosen approach with per-claim
evidence prompts → re-evaluation exit (DESIGN-boundary,
re-evaluation sub-shape).

What I review at end: the new Decision Record at
`docs/decisions/DECISION-design-<topic>-re-evaluation-<YYYY-MM-DD>.md`,
referencing the existing DESIGN by path. The DESIGN remains the
live artifact. State file records `exit: re-evaluation`,
`boundary: design`, and `decision_record_sub_shape: re-evaluation`.

### US-4: PRD rejection via re-evaluation exit's rejection sub-shape

As a **skill author** whose `/scope` run authored a Draft PRD that
I deliberately rejected at `/prd`'s finalization gate, I want
`/scope` to capture the rejection as a durable Decision Record
(alongside the discard commit that `/prd` itself wrote), so that
the tactical conversation lands at an artifact even when the
conclusion was "no PRD warranted at this altitude."

Chain shape: `/scope` invokes `/prd` → `/prd` runs to its Phase 4
finalization (the new Phase-N Reject contract this PRD specifies
for `/prd`) → user picks Reject at the final-confirmation gate →
`/prd` runs `git rm docs/prds/PRD-<topic>.md`, cleans up
`wip/prd_<topic>_*.md`, commits `docs(prd): discard PRD draft for
<topic>` → control returns to `/scope` → `/scope` immediately
writes
`docs/decisions/DECISION-prd-<topic>-rejection-<YYYY-MM-DD>.md`
referencing the discard commit SHA and the user's stated rationale
→ re-evaluation exit (PRD-boundary, rejection sub-shape).

The same chain shape applies symmetrically at the DESIGN boundary
when `/design` Phase-N Reject fires inside the chain: `/scope`
writes
`docs/decisions/DECISION-design-<topic>-rejection-<YYYY-MM-DD>.md`
and the chain exits with `boundary: design`,
`decision_record_sub_shape: rejection`.

This sub-shape is *not* abandonment (the author exercised explicit
judgment at a finalization gate; they did not bail mid-flight). It
shares the re-evaluation exit with the re-evaluation sub-shape
because both express the same architectural intent: a tactical
conversation that lands at a durable record rather than at a
PRD or DESIGN artifact.

What I review at end: the new Decision Record referencing the
discard commit. No PRD (or DESIGN) exists on disk at the rejected
boundary. State file records `exit: re-evaluation`,
`boundary: {prd|design}`, `decision_record_sub_shape: rejection`,
`discard_commit_sha: <sha>`, and `rejection_rationale: <text>`.

### US-5: Mid-chain abandonment forcing materialization

As a **skill author** whose `/scope` run broke mid-flight (closed
the session, switched to a different task, or stale-session
detection fired on resume), I want `/scope` to force-materialize
the most-recently-running child's intermediate as a Draft artifact
with a Status marker noting the abandonment-forced origin, so that
the chain always leaves a review surface regardless of how it
ended.

Chain shape: `/scope` resume ladder detects partial state → either
(a) author explicitly says "wrap it up" or picks Bail at the
chain-proposal prompt, or (b) state file's `last_updated` is `≥`
7 days old and author selects "Force-materialize" → confirm/cancel
prompt → force-materialize the most-recently-running child's
intermediate per the tie-break rule → abandonment-forced exit.

What I review at end: the force-materialized Draft artifact (a
Draft BRIEF, PRD, DESIGN, or PLAN — whichever child was the
most-recently-running) with an HTML-comment marker noting it was
abandonment-forced. State file records `exit: abandonment-forced`
with `triggering_child: <child-name>` and `partial_phase_reached:
<phase>`.

### US-6: Reviewer redirect via manual fallback

As a **reviewer or author** who wants to tighten a Draft PRD (or
DESIGN) directly without re-running the full chain, I want to
invoke `/prd <topic>` (or `/design <PRD-path>`) outside `/scope`,
producing a revised Draft, and have `/scope` warn but not act when
I later resume it on the same topic, so that manual fallback is
first-class steady-state capability rather than a workaround.

Chain shape: author invokes `/prd` or `/design` directly outside
`/scope` → child runs standalone → produces revised Draft →
`/scope` is not invoked.

On later `/scope` resume against the same topic, the resume ladder
detects out-of-chain edits via `child_snapshots` comparison and
surfaces a staleness warning with three concrete options (re-run
the downstream child, accept downstream as still-valid, proceed
without the downstream). `/scope` warns but does not act
unilaterally.

What I review at end: depends on the author's choice. The critical
property is `/scope` did not interfere with the manual invocation,
and `/scope` did not silently re-run downstream work. The R13
manual-fallback non-interference rule applies across all four
child boundaries.

## Requirements

Requirements are tagged with `[/scope-specific]` (binding stays in
this PRD) or `[pattern-level]` (the downstream shared design doc
should lift the mechanism into pattern-level scope). Pattern-level
tags signal to the designer of
`docs/designs/DESIGN-shirabe-scope-skill.md` which commitments
apply to `/charter`, `/scope`, and the future `/work-on` migration
together.

Pattern-level R-numbers are reused verbatim from `/charter`'s PRD
to preserve cross-PRD comparability. Per the L9 fold (reclassified
from "untapped learning" to required convention in this PRD's
Decisions section), pattern-level requirements share R-numbers
across all parent-skill PRDs so reviewers can grep for
`[pattern-level]` and verify pattern-doc edits cover all of them.

### Functional Requirements

**R1 [pattern-level].** A parent skill SHALL load as a Claude Code
slash command following the SKILL.md template shape used by
shipped shirabe skills (input modes section, execution-mode flag
parsing, topic-slug constraint, Workflow Phases diagram, Resume
Logic ladder, Phase Execution list, Reference Files table). The
template structure is pattern-level; the directory location is
scope-specific: `/scope` MUST live at `skills/scope/`.

**R2 [/scope-specific].** `/scope` SHALL accept the following
input modes:
- **Empty `$ARGUMENTS`**: cold start; ask the author what feature
  they want to specify, then re-enter Freeform Topic mode with the
  derived slug.
- **Freeform topic string**: `/scope <topic-slug>` — derive the
  slug per the topic-slug constraint below; enter Phase 1
  discovery.

`/scope` MUST NOT accept paths to durable artifacts as input. The
chain produces multiple artifacts; an upstream-path input mode
does not compose. The two-slot $ARGUMENTS surface matches
`/charter`'s deliberate narrowness; the richer upstream-artifact
diversity in the tactical chain is handled by Phase 1 discovery
prose, not $ARGUMENTS dispatch.

**R3 [pattern-level].** `/scope` SHALL enforce the topic-slug
constraint `^[a-z0-9-]+$` on the derived slug. This constraint
matches `/charter`'s constraint so the same slug flows through the
chain. Slugs failing the constraint MUST be rejected at Phase 0;
`/scope` MUST NOT proceed silently.

**R4 [/scope-specific].** `/scope` SHALL invoke `/brief` when
either signal is present (Feeder-EITHER gate shape):
- No Accepted/Done BRIEF exists at `docs/briefs/BRIEF-<topic>.md`,
  OR
- The author's Phase 1 discovery surfaces a framing-shift signal.

The framing-shift signal is an author-stated condition surfaced
through Phase 1 discovery. `/scope`'s discovery prompt MUST
include a question of the form "Is the feature's framing shifting,
or is the existing BRIEF (if any) still the right framing?" with
at least the following author-utterance categories treated as
framing-shift signals: (a) the author explicitly says the
feature's problem or outcome has changed; (b) the author names a
new user, journey, or scope boundary the existing BRIEF does not
cover; (c) the author indicates the existing BRIEF is no longer
the right framing. Signal detection is agent judgment; the
requirement is that the discovery prompt surfaces the question
explicitly and the agent treats any of these utterance categories
as a positive signal.

When `/scope` is invoked dog-fooded from an Accepted BRIEF and no
framing-shift surfaces, `/scope` SHALL skip `/brief` and proceed
to `/prd` with the BRIEF recorded in `chain_skipped` (not in
`chain_ran`). The BRIEF is a chain member, not a feeder; its
skipped-vs-ran disposition is symmetric with the other three
children.

**R5 [/scope-specific].** `/scope` SHALL invoke `/prd` UNLESS an
Accepted PRD already exists at `docs/prds/PRD-<topic>.md`
(Mandatory-with-auto-skip gate shape). The auto-skip semantics
mirror `/brief`'s resume logic: when an Accepted PRD exists,
`/scope` records `/prd` in `chain_skipped` and proceeds to
`/design`'s gate evaluation; `/scope` MUST NOT silently overwrite
an Accepted PRD.

`/scope` SHALL pass `/prd` one of:
- a freeform topic string (no upstream), OR
- a BRIEF path (Input Mode 2 of `/prd`) if `/brief` ran in the
  chain or if an existing Accepted BRIEF was identified during
  discovery.

`/scope` MUST NOT pass a PRD path to `/prd` as input. PRD paths
are `/prd`'s lifecycle-verb mode, not the create-new mode.

**R6 [/scope-specific].** `/scope` SHALL invoke `/design` when the
just-produced PRD exhibits any of three shape predicates
(shape-dependent gate, agent-judgment predicates evaluated at
Phase 1 against the PRD body):
1. The PRD's Requirements section contains 2+ requirements that
   imply architectural alternatives (e.g., multiple components,
   choice points between approaches), OR
2. The PRD references components, interfaces, or data flows NOT
   yet defined in the repo (new API surface, new infrastructure),
   OR
3. The PRD's complexity assessment classifies Complex per
   `/design`'s own complexity table (Files to modify 4+, new test
   infrastructure, API surface changes, or cross-package work).

When NONE of the shape predicates hold (a PRD with 1 requirement
that adds a recipe, fixes a typo, updates docs), `/scope` SHALL
skip `/design` and proceed directly to `/plan` with the PRD as
upstream. `/plan` accepts `docs/prds/PRD-*.md` as Input Mode 2.

`/scope` SHALL pass `/design` either the just-produced PRD path
(when `/prd` ran in the chain) or the existing Accepted PRD path
(when `/prd` was auto-skipped). `/scope` MUST NOT pass a DESIGN
path to `/design` as input.

**R7 [/scope-specific].** `/scope` SHALL ALWAYS invoke `/plan` if
the chain reaches `/plan` (ALWAYS-when-reached gate shape). The
chain reaches `/plan` when the prior children completed without
hitting an exit (no re-evaluation, no abandonment-forced, no
rejection).

`/scope` SHALL pass `/plan` either the just-produced DESIGN path
(when `/design` ran) or the just-produced/existing PRD path (when
`/design` was skipped). `/scope` SHALL NOT pre-decide `/plan`'s
`execution_mode` (single-pr vs multi-pr); `/plan`'s own Phase
selects the mode per its existing rules. `/scope` SHALL record the
mode `/plan` selected in the state file's
`plan_execution_mode` field on `/plan`'s exit so re-entry against
an Active PLAN reads the correct surface.

`/scope`'s chain-tracking unit
(`planned_chain`/`chain_ran`/`chain_skipped`) does not capture
`execution_mode`; the field is recorded separately on the state
file at `/plan`'s finalization.

**R7.5 [/scope-specific].** `/scope` Phase 1 SHALL conclude with a
chain-proposal confirmation prompt that names the chain shape
derived from discovery and the three options the author can pick
from. The prompt MUST identify itself as the **chain proposal
output** (the canonical term referenced by acceptance criteria
below) and MUST contain the literal substrings "Proceed",
"Adjust", and "Bail" (case-insensitive) as the three options. The
prompt MUST list, in order, the children `/scope` plans to invoke
(skipping those determined by R4/R5/R6 not to fire). Example
shape:

> Based on our conversation, here's the chain I propose: [skip
> `/brief` because <reason> | run `/brief`], [skip `/prd` because
> <reason> | run `/prd`], [run `/design` because <reason> | skip
> `/design` because <reason>], run `/plan`. Proceed / Adjust chain
> / Bail?

"Adjust" routes the author back to Phase 1 discovery for
chain-shape redirection (e.g., force `/brief` on, opt `/design`
out) before any child fires. "Bail" routes per R8's bail-handling
rule: routes to abandonment-forced if any wip state exists,
otherwise clean cancel.

**R8 [/scope-specific].** `/scope` SHALL terminate at exactly one
of three named exit paths. Every chain MUST land at a durable file
on disk; git history alone does not satisfy the terminal-artifact
contract.

- **Full-run.** The chain reaches `/plan` and the PLAN lands at
  `docs/plans/PLAN-<topic>.md` — Draft in `single-pr` mode, Active
  in `multi-pr` mode alongside a GitHub milestone with issues.
  Intermediate BRIEF, PRD, and (if produced) DESIGN are settled at
  their accepted statuses. The chain halts at the durable terminal
  artifact for human review.
- **Re-evaluation.** `/scope` wrote a durable Decision Record at
  `docs/decisions/DECISION-{prd|design}-<topic>-<sub-shape>-<YYYY-MM-DD>.md`.
  The re-evaluation exit has two **boundary positions** and two
  first-class **sub-shapes** that share the artifact body shape:
  - **Boundary positions:** PRD (when the chain met a settled PRD
    or authored a Draft PRD that was rejected at `/prd`'s
    finalization gate) or DESIGN (when the chain met a settled
    DESIGN or authored a Draft DESIGN that was rejected at
    `/design`'s finalization gate). Each boundary writes the
    Decision Record at its corresponding path:
    `docs/decisions/DECISION-prd-<topic>-<sub-shape>-<YYYY-MM-DD>.md`
    for PRD-boundary;
    `docs/decisions/DECISION-design-<topic>-<sub-shape>-<YYYY-MM-DD>.md`
    for DESIGN-boundary.
  - **Sub-shapes:**
    - **re-evaluation sub-shape.** The chain confirmed the
      existing PRD or DESIGN still holds. The Decision Record
      references the existing artifact by path and records the
      evidence reviewed. No revision; no chain proceeding to the
      next child.
    - **rejection sub-shape.** The chain authored a Draft PRD or
      Draft DESIGN; the author explicitly rejected it at the
      child's finalization gate (`/prd` or `/design` Phase-N
      Reject branch — R20). The child discarded the Draft via
      `git rm` and a `docs({prd|design}): discard {PRD|DESIGN}
      draft` commit. `/scope` then wrote the Decision Record
      referencing the discard commit SHA, the user's stated
      rejection rationale, and the upstream artifact (BRIEF for
      PRD-rejection; PRD for DESIGN-rejection).
- **Abandonment-forced.** The most-recently-running child's
  intermediate was force-materialized as a Draft artifact with an
  HTML-comment marker noting abandonment-forced origin. Fires when
  the author bails (session closed and stale, "wrap it up" intent,
  R7.5's Bail option, or stale-session-detection threshold
  crossed). Does NOT fire on `/prd` or `/design` Phase-N Reject —
  that is a deliberate finalization judgment, not a bail, and maps
  to the re-evaluation exit's rejection sub-shape.

  **Tie-break for "most-recently-running"**: the last entry in the
  state file's `chain_ran` field, or if `chain_ran` is empty, the
  first entry in `planned_chain` that has a non-empty wip/
  intermediate on disk. If neither resolves to a child, bail
  routes to clean-cancel rather than abandonment-forced — there is
  nothing to force-materialize.

**R9 [pattern-level].** `/scope` SHALL fail finalization if the
state file's `exit:` field is unset or not in
`{full-run, re-evaluation, abandonment-forced}`. When `exit:` is
`re-evaluation`, BOTH `boundary:` MUST be set to one of
`{prd, design}` AND `decision_record_sub_shape:` MUST be set to
one of `{re-evaluation, rejection}`. Conditional fields (i.e.,
fields whose presence is gated by a specific `exit:`, `boundary:`,
or `decision_record_sub_shape:` value, such as
`referenced_artifact`, `discard_commit_sha`, `rejection_rationale`,
`triggering_child`, `partial_phase_reached`,
`plan_execution_mode`) MUST be absent from the state file when
their triggering condition does not hold; they MUST NOT be set to
null, empty string, or placeholder value. The hard finalization
check is the contract enforcement mechanism: a `/scope` run that
completes without recording a valid exit is a violation and MUST
be surfaced (not silently absorbed).

**R10 [pattern-level].** `/scope` SHALL maintain a state file at
`wip/scope_<topic>_state.md`. The file is **pure YAML** despite
the `.md` extension (the extension matches shirabe's `wip/`
convention for committed intermediates; the body has no markdown).
The schema is:

```yaml
topic: <topic-slug>
chain_started: <ISO-8601 timestamp>
chain_completed: <ISO-8601 timestamp>  # set at finalization
last_updated: <ISO-8601 timestamp>     # set on every write
planned_chain: [brief?, prd?, design?, plan]
chain_ran: [<sub-list of completed children>]
chain_skipped:                         # free-text reasons for humans; not parsed
  - child: <name>
    reason: <free text>
exit: full-run | re-evaluation | abandonment-forced
boundary: prd | design                 # set ONLY when exit=re-evaluation
decision_record_sub_shape: re-evaluation | rejection  # set ONLY when exit=re-evaluation
plan_execution_mode: single-pr | multi-pr  # set ONLY when /plan ran
exit_artifacts:
  - path: <artifact-path>
    status: <Draft | Accepted | Active | Done>
child_snapshots:                       # per-child snapshot at last exit
  brief:  { path: <…>, status: <…>, content_hash: <git-blob-hash> }
  prd:    { path: <…>, status: <…>, content_hash: <git-blob-hash> }
  design: { path: <…>, status: <…>, content_hash: <git-blob-hash> }
  plan:   { path: <…>, status: <…>, content_hash: <git-blob-hash> }
referenced_artifact: <path>            # set on re-evaluation-sub-shape
discard_commit_sha: <sha>              # set on rejection-sub-shape
rejection_rationale: <text>            # set on rejection-sub-shape
triggering_child: <child-name>         # set on abandonment-forced
partial_phase_reached: <phase-name>    # set on abandonment-forced
```

The `planned_chain` field disambiguates multi-child phase pointers
when a resume detects both a Draft PRD and a Draft DESIGN. The
`child_snapshots` block enables sibling-edit detection (US-6):
each snapshot entry records the child doc's path, its frontmatter
`status:` value at last `/scope` exit, and the git blob hash of
the child doc at that time. On resume, `/scope` compares both the
live `status:` and the live blob hash against the snapshot —
drift fires when **either** has changed since the snapshot was
taken.

The `boundary:` field is new in `/scope` (no analog in
`/charter`'s state schema because the strategic chain has one
re-evaluation boundary, not two). The `plan_execution_mode:`
field is new in `/scope` (no analog because `/strategy` has one
output mode, not two).

**R11 [pattern-level].** `/scope` SHALL implement a resume ladder
that extends the multi-source pattern shared across shipped
shirabe ladders to span sibling child docs at four positions plus
PLAN's three statuses (Draft, Active, Done) and DESIGN's
directory-move lifecycle (`docs/designs/` vs
`docs/designs/current/`). The ladder MUST consult:
1. `wip/scope_<topic>_state.md` for the phase pointer, planned
   chain, and exit pointer (if any).
2. Each child doc named in `planned_chain` — for each, read the
   current frontmatter `status:` AND compute the current git blob
   hash, then compare both to the `child_snapshots` entry to
   detect out-of-chain edits.
3. Each child's own wip/ artifacts (`wip/brief_<topic>_*.md`,
   `wip/prd_<topic>_*.md`, `wip/design_<topic>_*.md`,
   `wip/plan_<topic>_*.md`) for partial-child-run detection.

If the state file exists but is malformed (e.g., missing required
fields for its recorded phase, invalid `exit:` value with no
`boundary:` or `decision_record_sub_shape:`, unparseable YAML),
`/scope` MUST surface a clear error naming the malformation and
offer Discard as a recovery path. The ladder MUST NOT silently
fall through to Phase 0 — a malformed state file is a contract
violation surface, not a missing state.

Resume-ladder ordering, top to bottom (first match wins):

```
state file malformed                                    → Error + offer Discard
state file has exit field set                           → Offer revise/fresh based on exit type
state file exists, last_updated < 7d                    → Resume at recorded phase
state file exists, last_updated ≥ 7d                    → Offer Resume / Force-materialize / Discard
docs/plans/PLAN-<topic>.md status Active                → Refuse and redirect to /work-on
docs/plans/PLAN-<topic>.md status Done                  → Refuse and redirect to /release
docs/plans/PLAN-<topic>.md status Draft                 → Offer continue / start fresh
docs/designs/current/DESIGN-<topic>.md Accepted         → Offer Re-evaluate / Revise / Bail (DESIGN-boundary)
docs/designs/DESIGN-<topic>.md Proposed                 → Offer continue / start fresh
docs/prds/PRD-<topic>.md Accepted                       → Offer Re-evaluate / Revise / Bail (PRD-boundary)
docs/prds/PRD-<topic>.md Draft                          → Offer continue / start fresh
docs/briefs/BRIEF-<topic>.md Accepted/Done              → Auto-skip /brief in chain proposal
docs/briefs/BRIEF-<topic>.md Draft                      → Offer continue / start fresh
wip/plan_<topic>_*.md exists                            → Resume into /plan
wip/design_<topic>_*.md exists                          → Resume into /design
wip/prd_<topic>_*.md exists                             → Resume into /prd
wip/brief_<topic>_*.md exists                           → Resume into /brief
On branch related to topic                              → Resume at Phase 1
On main or unrelated branch                             → Start at Phase 0
```

PLAN is the chain anchor for status-aware re-entry at three
statuses. PLAN-Active and PLAN-Done are category errors for
`/scope` re-entry — `/work-on` owns Active, `/release` owns Done.
`/scope`'s resume ladder fires a "redirect to next skill" prompt
for those two cases rather than the Re-evaluate / Revise / Bail
triad.

When the ladder detects a child doc in `Accepted` or `Active`
status that would trigger that child's own "offer to revise or
start fresh" prompt on re-entry, `/scope` MUST decide upfront
whether the re-entry path is a re-evaluation exit (write Decision
Record; do not invoke the child) or a fresh chain (signal the
child to suppress its status-aware re-entry). The signaling
mechanism is a design-team decision; the requirement is that
`/scope`'s flow MUST NOT be hijacked by a child's resume-time
prompt.

**R12 [pattern-level].** `/scope` SHALL detect repository
visibility by reading CLAUDE.md's `## Repo Visibility:` header
(pattern inherited from `/charter`, `/strategy`, and `/explore`).
If the header is absent, `/scope` MUST default to Private and
emit a warning to the author. The warning text follows the
shipped `/charter` phrasing: "Default to Private if unknown —
restricting is easier to undo than oversharing." Public repos
with a missing header are a known limitation surfaced through
this default behavior.

**R13 [pattern-level].** `/scope` SHALL treat invoking any child
skill directly outside `/scope` (manual fallback) as first-class
steady-state behavior across all four child boundaries. `/scope`
MUST NOT prevent or warn against direct child invocation. On the
next `/scope` resume, the resume ladder detects out-of-chain
edits via `child_snapshots` comparison and surfaces staleness
with three concrete options (re-run the downstream child, accept
downstream as still-valid, proceed without the downstream).

**R14 [pattern-level].** A parent skill SHALL wait for the
invoked child to complete its own finalization phase before
deciding the next step. The parent reads the child doc's
frontmatter `status:` value after the child returns. The parent
MUST NOT inspect the child's intermediate
`wip/research/<child>_<topic>_phase<N>_*.md` verdict files or any
other child internals; the contract surface is the child's
durable artifact status, full stop.

### Non-Functional Requirements

**R15 [/scope-specific].** `/scope` SHALL produce artifacts that
pass `shirabe validate` on commit. Specifically:
- Decision Records (both boundaries, both sub-shapes) at
  `docs/decisions/DECISION-{prd|design}-<topic>-<sub-shape>-<YYYY-MM-DD>.md`
  MUST follow the ADR-style body shape (Status, Context, Decision,
  Options Considered, Consequences) with frontmatter. Frontmatter
  field formats:
  - `status:` one of `{Draft, Accepted}` (an enum value, not free
    text);
  - `decision:` a single short sentence stating the decision
    conclusion (e.g., "PRD still holds; no revision warranted" /
    "Draft PRD rejected; no PRD warranted");
  - `rationale:` a 1-3 sentence justification (~250 characters
    soft cap) referencing the body's Context or Options.

  Per-boundary, per-sub-shape body content requirements:
  - **PRD-boundary, re-evaluation:** Context cites the new
    evidence reviewed (at least one named evidence item — URL,
    file path, or paraphrased finding). Decision states "PRD
    still holds; no revision warranted." Options Considered names
    "revise the PRD" and "force-abandon and rewrite" as rejected
    alternatives with evidence. Consequences describes what
    remains in effect (the existing PRD stays Accepted; no DESIGN
    regeneration) and what triggers the next re-evaluation.
    References the existing PRD by path.
  - **PRD-boundary, rejection:** Context cites the chain's
    discovery and the Draft PRD's framing. Decision states "Draft
    PRD rejected; no PRD warranted" with the author's stated
    rejection rationale. Options Considered names "accept the
    Draft" and "revise instead of reject" as rejected
    alternatives. Consequences describes the post-rejection state
    (no PRD on disk; chain discarded; next steps for the feature
    question). References the discard commit SHA.
  - **DESIGN-boundary, re-evaluation:** Context cites the new
    evidence reviewed. Decision states "DESIGN still holds; no
    revision warranted." Options Considered names "revise the
    DESIGN" and "force-abandon and rewrite" as rejected
    alternatives. Consequences describes what remains in effect
    (the existing DESIGN stays Accepted at
    `docs/designs/current/`; no PLAN regeneration) and what
    triggers the next re-evaluation. References the existing
    DESIGN by path.
  - **DESIGN-boundary, rejection:** Context cites the upstream
    PRD and the Draft DESIGN's framing. Decision states "Draft
    DESIGN rejected; no DESIGN warranted." Options Considered
    names "accept the Draft" and "revise instead of reject" as
    rejected alternatives. Consequences describes the
    post-rejection state. References the discard commit SHA.
- Abandonment-forced artifacts MUST be schema-compliant in the
  same shape as a full-run artifact. The abandonment-forced
  metadata MUST live in an HTML-comment marker
  (`<!-- scope-status-block: abandonment-forced; ... -->`) inside
  the artifact's existing Status section, NOT in a new required
  section that would invalidate the artifact-type schema.

**R16 [/scope-specific].** `/scope` SHALL respect a 7-day
stale-session threshold for distinguishing "broke for lunch" from
"abandoned for a week." The boundary fires at `≥` 7 days from the
state file's `last_updated` timestamp (consistent with the
resume-ladder ordering in R11). The threshold is fixed in v1; a
future release may make it configurable.

**R16.5 [/scope-specific].** `/scope` SHALL default
`--max-rounds=N` to 5 (vs `/charter`'s default of 3). Reason:
tactical chains have more re-evaluation opportunities (two
boundaries instead of one) and requirements/design churn faster
than strategic thesis; a higher default accommodates the larger
natural surface without forcing user override. Authors may
override via the `--max-rounds=N` flag.

**R17a [pattern-level].** A parent skill SHALL ship CLAUDE.md
updates that surface its entry triggers and discovery surface.
Workspace and shirabe CLAUDE.md documentation MUST mention the
skill so that authors discover it through the same channels they
discover shipped child skills.

**R17b [/scope-specific].** The CLAUDE.md trigger phrases for
`/scope` SHALL include: "specify a feature called X", "scope
feature Y", "walk me through specifying Z", or direct
`/scope <topic>` invocations. shirabe's CLAUDE.md MUST gain a
"Tactical Chain Entry: /scope" section paralleling the existing
"Strategic Chain Entry: /charter" section.

**R18 [pattern-level].** A parent skill SHALL ship skill evals at
`skills/<name>/evals/evals.json`. Per the shirabe authoring
convention, evals MUST be run via `scripts/run-evals.sh <name>`
before merging. For `/scope`, the eval scenarios MUST cover the
six user stories defined in this PRD (US-1, US-2, US-3a, US-3b,
US-4, US-5, US-6); the requirement to ship evals is pattern-level,
the scenarios chosen are scope-specific.

**R19 [pattern-level].** A parent skill's orchestration layer
(team-lead, whether the parent itself for single-agent parents or
the coordinator inside a team-emitting parent) SHALL implement
the **team-lead operating discipline**: a sleep-check-nudge loop
that runs for the duration of any dispatched work. The discipline
is substrate-agnostic — it survives the amplifier-layer migration
because filesystem evidence is a strictly stronger source of
truth than message delivery. The canonical 5-step loop:

1. **Dispatch.** Team-lead sends a structured directive to the
   teammate, records the dispatch in working memory (teammate,
   task, dispatch timestamp, expected artifacts, response window).
2. **Bounded sleep.** Team-lead sleeps for the task-class window
   (see priority ordering and timing below) before checking for
   evidence.
3. **Filesystem evidence check (priority 1).** Team-lead inspects
   the filesystem for terminal artifacts, partial artifacts, new
   git commits, or growing `wip/` files.
4. **Inbox processing (priority 2).** If no filesystem evidence
   advances the work, team-lead processes structured teammate
   messages (PASS / FAIL / PROGRESS / BLOCKED verdicts).
5. **Nudge (priority 3).** If neither filesystem nor inbox
   advances the work, team-lead sends a nudge containing
   **directly-executable instructions**: what artifact to
   produce, where to write it, what structured verdict to reply
   with.

The loop has exactly **three terminal exit conditions**: PASS
(artifact present and valid), FAIL (artifact present but failing
validation or structured FAIL verdict), ESCALATE (patience budget
exhausted; default 5 stagnation cycles per teammate).

Task-class timing parameters and `ci_outcome` semantics
(`passing` vs `failing_fixed`) inherit verbatim from R19's
canonical encoding in `/charter`'s PRD — `/scope` adopts the
same defaults.

R19 is encoded in the design as invariant **I-7 (Active
Orchestration)** plus reference-implementation content in
`references/parent-skill-pattern.md`. `/scope` v1 is single-agent
(no peer dispatch within `/scope` itself), so R19 binds vacuously
to `/scope`'s own orchestration; its child invocations
(`/brief`, `/prd`, `/design`, `/plan`) are dispatches in the
team-lead-discipline sense and inherit the loop.

### Fold-driven Requirements (new in `/scope` v1)

The four fold-driven requirements below close gaps the
`/charter` retrospective identified as Track A inside-pattern items. Each
captures a discipline `/scope` v1 ships by authoring (small per-
PR cost; load-bearing for the pattern's reviewer-checkability
contract).

**R20 [/scope-specific].** `/scope` SHALL perform a structural
file-existence check before consulting any child's
finalization-phase reviewer verdicts (paired fold of observations
#3 and #9). For each child invocation, after the child returns,
`/scope` MUST verify the durable artifact exists at the expected
path (`docs/briefs/BRIEF-<topic>.md`,
`docs/prds/PRD-<topic>.md`,
`docs/designs/current/DESIGN-<topic>.md`, or
`docs/plans/PLAN-<topic>.md`) BEFORE accepting the child's
reported PASS verdict. A reviewer-PASS verdict with no artifact
present MUST be treated as STALE (not PASS); `/scope` MUST treat
the state as "child finalization did not complete" and route via
the bail-handling rule rather than proceeding to the next child.

The check encodes the pattern doc's existing filesystem-evidence-
as-priority-1 ordering at the chain-orchestration altitude: when
`/scope` dispatches a child, the artifact's existence is priority
1 evidence; the reviewer's reported verdict is priority 2; the
two diverging is a contract violation surface, not a benign
condition.

**R21 [/scope-specific].** `/scope` SHALL keep its worktree in sync
with upstream across the chain and SHALL escalate based on whether
upstream changes invalidate the chain's intent, NOT on whether the
rebase was clean (fold of observation #11). Before invoking
`/brief`, `/prd`, `/design`, or `/plan`, `/scope` MUST:

1. **Attempt rebase.** Execute the equivalent of `git fetch && git
   rebase origin/<tracking-branch>`. Both clean rebases and
   conflicted rebases proceed to step 2 (mechanical conflict
   resolution is sub-agent work using artifact context; conflicts
   that cannot be resolved from artifact context escalate via the
   same impact-classification step below, not as a separate path).

2. **Analyze contextual impact.** Read the upstream commits that
   landed in step 1 and cross-reference them against the chain's
   authored artifacts (BRIEF, PRD, DESIGN, PLAN as they exist at
   this point in the chain) AND against the inputs the next child
   invocation will consume. Classify the impact:
   - **None**: upstream changes touch no path, symbol, or contract
     the chain depends on.
   - **Informational**: upstream changes touch something the chain
     references, but the change is non-substantive (typo, comment,
     formatting).
   - **Intent-changing**: upstream changes alter a contract,
     interface, or fact the chain has committed to (e.g., a child
     skill's input format changed; a referenced file was renamed
     or removed; a doc the BRIEF cites was rewritten).

3. **Escalate based on impact.**
   - **None or Informational**: record the rebase in
     `worktree_rebases:` and proceed to child invocation. The team
     lead and author are not prompted.
   - **Intent-changing**: route to the team lead with full
     evidence (which artifact, which referenced contract,
     specifically what changed). The team lead decides whether the
     original session intent still holds; if it does, the team
     lead may resolve in-place (e.g., update a citation in the
     chain's authored artifact, then proceed). If the intent has
     genuinely changed, the team lead MUST escalate to the author
     with the three-option prompt: re-author affected artifacts
     against the new contract / proceed against the original intent
     (recording the divergence) / bail per R8.

The author is bothered ONLY when the session's original intent has
changed. Mechanical conflicts, cosmetic upstream changes, and
contract changes the team lead can resolve from artifact context
never reach the author.

The check trigger fires "before each Phase 2 child invocation"
(not on every `/scope` invocation, not after each child completes)
to bound the operational overhead. Tactical chains span longer
than strategic chains (4 children vs 3, each typically minutes to
hours), so worktree-staleness probability doubles relative to
`/charter`'s typical run; the check is load-bearing for tactical
chains specifically.

The discipline is captured at the pattern level in a new top-level
reference `references/parent-skill-worktree-discipline.md` (per
Decision 4 below), so future parents (`/work-on` migration,
future tactical parents) inherit the same trigger condition.

**R22 [/scope-specific].** `/scope` SHALL respect `/plan`'s
`<<ISSUE:N>>` placeholder convention in two ways (fold of L11):
1. The motivating `docs/plans/PLAN-shirabe-scope-skill.md`
   produced as part of `/scope`'s ship MUST use the `<<ISSUE:N>>`
   placeholder syntax verbatim with explanatory prose mirroring
   `/plan` SKILL.md's "Placeholder Conventions" section, so the
   PLAN doc dog-foods the convention.
2. When `/scope` re-enters mid-chain against an Active PLAN doc
   with unresolved `<<ISSUE:N>>` placeholders, `/scope`'s
   chain-orchestration logic MUST NOT interpret outline-number
   references as stale. The placeholders are a known
   intermediate state in single-pr mode; treating them as
   staleness surfaces a false-positive contract violation.

**R23 [/scope-specific].** `/scope` SHALL invoke `/prd` and
`/design` only after each has shipped a Phase-N Reject
finalization contract (named here as the upstream prerequisite,
implemented in the downstream design doc). The Phase-N Reject
contract on each child MUST:
- Add a final-confirmation gate at the child's Phase 4 (for
  `/prd`) and Phase 6 (for `/design`) that offers
  Accept/Reject/Continue-revising as options.
- On Reject, run `git rm <durable-artifact-path>`, clean up the
  child's `wip/` artifacts for the topic, and commit
  `docs({prd|design}): discard {PRD|DESIGN} draft for <topic>`.
- Return control to the caller (`/scope` when invoked in-chain,
  the shell otherwise) with a Reject verdict observable from the
  commit SHA.

When invoked outside `/scope`, the Phase-N Reject contract on
`/prd` or `/design` MUST function identically (the contract is
the child's own, not `/scope`'s). On in-chain rejection,
`/scope` writes the rejection-sub-shape Decision Record per R8;
on out-of-chain rejection, the discard commit is the durable
record and `/scope` does NOT retroactively write a Decision
Record on a later resume (the rejection sub-shape is
chain-orchestrated only; manual-fallback rejection leaves only
the discard commit, by design).

## Acceptance Criteria

Each criterion is binary pass/fail. ACs trace to both the
requirement that motivates them and the user story they exercise
(where applicable). Verification entry points are noted per AC:
`[automated-unit]`, `[automated-eval]`, or `[manual-review]`.

### Skill loading and slug constraint

- [ ] **AC1** `/scope` loads as a slash command from
  `skills/scope/SKILL.md`. The SKILL.md frontmatter declares
  `name: scope`. `[automated-unit]` (R1)
- [ ] **AC1b** `skills/scope/SKILL.md` contains sections matching
  each of the 7 required structural elements named in R1: an
  Input Modes section, execution-mode flag-parsing, a topic-slug
  constraint statement, a Workflow Phases diagram, a Resume Logic
  ladder, a Phase Execution list, and a Reference Files table.
  Each MUST be present AND non-empty. `[automated-unit]` (R1)
- [ ] **AC2** Invoking `/scope` with no `$ARGUMENTS` produces a
  cold-start prompt asking for the feature topic.
  `[automated-eval]` (R2, US-1)
- [ ] **AC3** Invoking `/scope Hello World` (whitespace in slug)
  is rejected at Phase 0 with a clear error message; the chain
  does not proceed. `[automated-eval]` (R3)
- [ ] **AC3b** `/scope` rejects `$ARGUMENTS` containing uppercase
  letters (`/scope MyTopic`), underscores (`/scope my_topic`),
  dots (`/scope my.topic`), or other characters outside
  `[a-z0-9-]`. Each rejection MUST surface a clear error naming
  the violated pattern. `[automated-eval]` (R3)
- [ ] **AC4** Invoking `/scope docs/prds/PRD-foo.md` (path as
  `$ARGUMENTS`) is treated as a freeform topic after slug
  derivation; not interpreted as an upstream path.
  `[automated-eval]` (R2)

### Child invocation gates

- [ ] **AC5** When `docs/briefs/BRIEF-<topic>.md` does not exist
  AND the author's Phase 1 discovery does not surface
  framing-shift, the chain proposal includes `/brief`. The
  observable: the chain proposal output (R7.5) contains the
  literal substring "/brief" in the planned chain.
  `[automated-eval]` (R4, US-1)
- [ ] **AC5b** When an Accepted or Done BRIEF exists at
  `docs/briefs/BRIEF-<topic>.md` AND no framing-shift surfaces
  during discovery, the chain proposal records `/brief` in
  `chain_skipped` (not in the planned chain) AND the chain
  proposal output (R7.5) names `/brief` as skipped with the
  reason "Accepted BRIEF already exists." `[automated-eval]`
  (R4, US-2)
- [ ] **AC5c** When the author's Phase 1 discovery surfaces a
  framing-shift signal (per R4's three utterance categories), the
  chain proposal includes `/brief` regardless of any existing
  BRIEF. `[automated-eval]` (R4)
- [ ] **AC6** When an Accepted PRD exists at
  `docs/prds/PRD-<topic>.md`, the chain proposal records `/prd`
  in `chain_skipped` with reason "Accepted PRD already exists"
  AND proceeds to `/design`'s gate evaluation against the
  existing PRD. `[automated-eval]` (R5, US-2)
- [ ] **AC6b** When no Accepted PRD exists at
  `docs/prds/PRD-<topic>.md`, the chain proposal includes
  `/prd`. The observable: the chain proposal output (R7.5)
  contains the literal substring "/prd" in the planned chain.
  `[automated-eval]` (R5, US-1)
- [ ] **AC7** When the just-produced or existing PRD exhibits at
  least one of R6's three shape predicates (2+ architectural
  requirements, references new components, OR Complex
  classification), the chain proposal includes `/design`. The
  observable: the chain proposal output (R7.5) contains
  "/design" in the planned chain. `[automated-eval]` (R6, US-1)
- [ ] **AC7b** When the PRD exhibits NONE of R6's three shape
  predicates, the chain proposal records `/design` in
  `chain_skipped` with a reason citing which predicates failed
  AND `/scope` proceeds to `/plan` with the PRD as upstream.
  `[automated-eval]` (R6)
- [ ] **AC8** When the chain reaches `/plan` (no prior re-evaluation,
  no rejection, no abandonment-forced), `/scope` invokes `/plan`
  unconditionally with the upstream artifact appropriate to the
  chain (DESIGN path if `/design` ran, PRD path otherwise) and
  records `/plan` in `chain_ran` on successful completion.
  `[automated-eval]` (R7, US-1)
- [ ] **AC8b** `/scope` does NOT pre-decide `/plan`'s
  `execution_mode`; the state file's `plan_execution_mode` field
  is set on `/plan`'s exit to whichever mode `/plan` selected
  (single-pr or multi-pr) per `/plan`'s existing rules.
  `[automated-eval]` (R7)

### Chain-proposal confirmation prompt

- [ ] **AC9** `/scope` Phase 1 produces a chain-proposal
  confirmation prompt at the end of discovery, containing the
  literal substrings "Proceed", "Adjust", and "Bail"
  (case-insensitive). The prompt lists the children that will be
  invoked in chain order. `[automated-eval]` (R7.5, US-1)
- [ ] **AC9b** Selecting "Adjust" at the chain-proposal prompt
  routes the chain back to Phase 1 discovery for redirection
  before any child fires. `[automated-eval]` (R7.5)
- [ ] **AC9c** Selecting "Bail" at the chain-proposal prompt
  routes per R8's bail-handling: abandonment-forced if any wip
  state for this topic exists, clean-cancel otherwise.
  `[automated-eval]` (R7.5, R8)

### Exit-path enforcement

- [ ] **AC10a** After a chain that completes through `/plan`
  with all four children running (`/brief`, `/prd`, `/design`,
  `/plan`), `wip/scope_<topic>_state.md` contains
  `exit: full-run` and `exit_artifacts` lists at least one entry
  for the terminal PLAN path with status Draft (single-pr) or
  Active (multi-pr). The `plan_execution_mode` field is set
  consistently with the PLAN's status. `[automated-eval]` (R8,
  R10, US-1)
- [ ] **AC10b** After a chain that completes with `/design`
  skipped and only `/brief`/`/prd`/`/plan` running,
  `wip/scope_<topic>_state.md` contains `exit: full-run` and
  `chain_skipped` lists `/design` with a reason citing failed
  shape predicates. `[automated-eval]` (R6, R8, R10)
- [ ] **AC11a** After a re-evaluation chain at the PRD boundary
  that confirms the PRD still holds,
  `docs/decisions/DECISION-prd-<topic>-re-evaluation-<YYYY-MM-DD>.md`
  is written; the existing PRD is unchanged; the state file
  contains `exit: re-evaluation`, `boundary: prd`,
  `decision_record_sub_shape: re-evaluation`, and
  `referenced_artifact: docs/prds/PRD-<topic>.md`. The Decision
  Record's Context section cites at least one named evidence
  item; the Options Considered section names "revise the PRD"
  AND "force-abandon and rewrite" as rejected alternatives.
  `[automated-eval]` (R8, R10, R15, US-3a)
- [ ] **AC11b** After a re-evaluation chain at the DESIGN
  boundary that confirms the DESIGN still holds,
  `docs/decisions/DECISION-design-<topic>-re-evaluation-<YYYY-MM-DD>.md`
  is written; the existing DESIGN at
  `docs/designs/current/` is unchanged; the state file contains
  `exit: re-evaluation`, `boundary: design`,
  `decision_record_sub_shape: re-evaluation`, and
  `referenced_artifact: docs/designs/current/DESIGN-<topic>.md`.
  `[automated-eval]` (R8, R10, R15, US-3b)
- [ ] **AC12a** When `/prd` Phase-N Reject fires inside a
  `/scope` chain (per R23's contract), `/scope` writes
  `docs/decisions/DECISION-prd-<topic>-rejection-<YYYY-MM-DD>.md`
  immediately after `/prd`'s discard commit lands; the state
  file contains `exit: re-evaluation`, `boundary: prd`,
  `decision_record_sub_shape: rejection`,
  `discard_commit_sha: <sha>`, and `rejection_rationale: <text>`.
  `[automated-eval]` (R8, R10, R15, R23, US-4)
- [ ] **AC12b** When `/design` Phase-N Reject fires inside a
  `/scope` chain (per R23's contract), `/scope` writes
  `docs/decisions/DECISION-design-<topic>-rejection-<YYYY-MM-DD>.md`
  immediately after `/design`'s discard commit lands; the state
  file contains `exit: re-evaluation`, `boundary: design`,
  `decision_record_sub_shape: rejection`,
  `discard_commit_sha: <sha>`, and `rejection_rationale: <text>`.
  `[automated-eval]` (R8, R10, R15, R23, US-4)
- [ ] **AC12c** When `/prd` or `/design` Phase-N Reject fires
  OUTSIDE a `/scope` chain (the author invokes the child
  directly and rejects), `/scope` does NOT retroactively write a
  rejection Decision Record on a later `/scope` resume — the
  rejection sub-shape is chain-orchestrated only; manual-fallback
  rejection leaves only the discard commit as the durable trace
  (by design). `[automated-eval]` (R13, R23, US-4, US-6)
- [ ] **AC13** After `/scope` force-materializes an intermediate
  (author bail, or stale-session detection per AC17), the
  resulting artifact contains an HTML-comment marker
  `<!-- scope-status-block: abandonment-forced; ... -->` inside
  its Status section; the state file contains
  `exit: abandonment-forced`, `triggering_child: <child-name>`,
  and `partial_phase_reached: <phase>`. `boundary` and
  `decision_record_sub_shape` are absent (per R9).
  `[automated-eval]` (R8, R10, R15, US-5)
- [ ] **AC13b** When the author bails inside an invoked child
  (`/brief`, `/prd`, `/design`, or `/plan`), `/scope`'s resume
  ladder on the next entry routes to abandonment-forced per
  US-5 semantics; the artifact force-materialized is the child
  that was running at the time of bail. `[automated-eval]` (R8,
  US-5)
- [ ] **AC13c** When the author bails before any child completes
  (`chain_ran` empty in the state file), `/scope`'s bail-handling
  resolves the tie-break per R8: if a
  `wip/{brief|prd|design|plan}_<topic>_*` intermediate exists,
  force-materialize the first entry in `planned_chain` matching
  a non-empty wip/ intermediate; if no wip/ intermediate exists
  for any planned child, bail routes to clean-cancel (no
  abandonment-forced exit, no Decision Record, no state-file
  `exit:` set to `abandonment-forced`). `[automated-eval]` (R8)
- [ ] **AC14** A `/scope` run that completes without recording
  a valid `exit:` value (or with `exit: re-evaluation` but no
  `boundary:` and `decision_record_sub_shape:`, or with
  conditional fields set when their triggering condition does
  not hold per R9) fails finalization with a clear error.
  `[automated-eval]` (R9)

### Resume ladder

- [ ] **AC15** When a partial state file exists and
  `last_updated` is less than 7 days old, `/scope` resumes at
  the recorded phase without prompting Force-materialize.
  `[automated-eval]` (R10, R11)
- [ ] **AC16** When a partial state file exists and
  `last_updated` is `≥` 7 days old, `/scope` surfaces a
  three-option prompt: Resume / Force-materialize / Discard.
  Selecting "Force-materialize" triggers the abandonment-forced
  exit per AC13. `[automated-eval]` (R11, R16, US-5)
- [ ] **AC16b** `/scope` defaults `--max-rounds=N` to 5 when the
  flag is not supplied. The flag accepts integer values 1+ via
  `--max-rounds=<N>`; values outside that range surface a clear
  error at Phase 0. `[automated-eval]` (R16.5)
- [ ] **AC17a** When `docs/prds/PRD-<topic>.md` is Accepted, the
  entry prompt MUST contain the literal substring
  "Re-evaluate / Revise / Bail" (case-insensitive) as the
  three-option triad offered AND MUST identify the boundary as
  the PRD-boundary, AND MUST NOT contain the literal substring
  "Continue / Start fresh". `[automated-eval]` (R11, US-3a)
- [ ] **AC17b** When `docs/designs/current/DESIGN-<topic>.md` is
  Accepted, the entry prompt MUST contain the literal substring
  "Re-evaluate / Revise / Bail" (case-insensitive) as the
  three-option triad offered AND MUST identify the boundary as
  the DESIGN-boundary. When both an Accepted PRD AND an Accepted
  DESIGN exist for the topic, the resume ladder's ordering puts
  DESIGN above PRD (the DESIGN-boundary fires first).
  `[automated-eval]` (R11, US-3b)
- [ ] **AC17c** When `docs/plans/PLAN-<topic>.md` is Active,
  `/scope` refuses re-entry as a chain-authoring skill and
  surfaces a redirect to `/work-on` (with a message naming
  `/work-on` as the active-plan owner). Similarly, when the
  PLAN is Done, `/scope` redirects to `/release`. Neither case
  fires the Re-evaluate / Revise / Bail triad.
  `[automated-eval]` (R11)
- [ ] **AC18a** When `child_snapshots.prd.status` OR
  `child_snapshots.prd.content_hash` differ from the live PRD's
  current `status:` or current git blob hash, the resume ladder
  surfaces a staleness warning with three concrete options
  (re-run downstream, accept downstream as still-valid, proceed
  without downstream). Drift fires when EITHER differs.
  `[automated-eval]` (R10, R11, R13, US-6)
- [ ] **AC18b** The same drift detection (EITHER of `status` or
  `content_hash` differs from snapshot) fires for
  `child_snapshots.brief`, `child_snapshots.design`, and
  `child_snapshots.plan`; drift on any of the four children
  surfaces the three-option prompt. `[automated-eval]` (R10,
  R11, R13, US-6)
- [ ] **AC18c** R14 child-internals isolation: during and after a
  `/scope` chain, `/scope`'s decision logic depends only on (a)
  child doc frontmatter, (b) the topic slug, and (c) its own
  state file — never on a child's internal
  `wip/research/<child>_<topic>_phase<N>_*.md` files or any other
  child internals. Verified by code-path review against the
  SKILL.md prose. `[manual-review]` (R14)
- [ ] **AC18d** Malformed state file on resume: when
  `wip/scope_<topic>_state.md` is unparseable, missing required
  fields for its recorded phase, or has an invalid `exit:` /
  `boundary:` / `decision_record_sub_shape:` combination,
  `/scope` surfaces a clear error and offers Discard as a
  recovery path; it does NOT silently fall through to Phase 0.
  `[automated-eval]` (R11)

### Visibility and manual fallback

- [ ] **AC19** When CLAUDE.md lacks a `## Repo Visibility:`
  header, `/scope` defaults to Private AND emits a warning
  containing the literal phrasing "Default to Private if
  unknown" and naming the missing `## Repo Visibility:` header.
  `[automated-eval]` (R12)
- [ ] **AC20** An author invoking `/prd`, `/design`, `/brief`,
  or `/plan` directly outside `/scope` produces no `/scope`
  interference; `/scope` does not surface a warning, does not
  block, does not modify state files. Verified for all four
  child boundaries. `[manual-review]` (R13, US-6)

### Schema and validation

- [ ] **AC21** Draft and Accepted artifacts written by
  `/scope`'s child delegations (BRIEF, PRD, DESIGN, PLAN) pass
  `shirabe validate --visibility=<repo-visibility>`.
  `[automated-unit]` (R15)
- [ ] **AC22** All four Decision-Record combinations
  (PRD-boundary re-evaluation, PRD-boundary rejection,
  DESIGN-boundary re-evaluation, DESIGN-boundary rejection)
  contain the required ADR-style sections (Status, Context,
  Decision, Options Considered, Consequences) and frontmatter
  (`status`, `decision`, `rationale` — `status` ∈ {Draft,
  Accepted}, `decision` and `rationale` are non-empty strings).
  Per-combination body content is verified by AC11a, AC11b,
  AC12a, AC12b. `[automated-unit]` (R15)
- [ ] **AC23** Force-materialized artifact passes the same
  schema validators as a full-run artifact (the
  abandonment-forced HTML-comment marker is inside the existing
  Status section, not in a new required section).
  `[automated-unit]` (R15)

### CLAUDE.md surfacing and evals

- [ ] **AC24a** Workspace CLAUDE.md and shirabe CLAUDE.md (the
  files in this PRD's source tree) mention `/scope` and include
  the trigger phrases listed in R17b. shirabe CLAUDE.md MUST
  contain a "Tactical Chain Entry: /scope" section paralleling
  "Strategic Chain Entry: /charter". `[automated-unit]` (R17a,
  R17b)
- [ ] **AC24b** `skills/scope/evals/evals.json` contains at
  least one eval scenario tagged for each user story: US-1,
  US-2, US-3a, US-3b, US-4, US-5, and US-6. All scenarios pass
  under `scripts/run-evals.sh scope`. `[automated-eval]` (R18)

### Resume detection across four child boundaries

- [ ] **AC25** When `wip/brief_<topic>_*.md` exists, `/scope`'s
  resume ladder detects the partial `/brief` run and resumes
  into `/brief`. The same holds symmetrically for
  `wip/prd_<topic>_*.md`, `wip/design_<topic>_*.md`, and
  `wip/plan_<topic>_*.md`. `[automated-eval]` (R11)

### Team-lead operating discipline (R19)

- [ ] **AC26a** The team-lead operating discipline
  (sleep-check-nudge loop) fires immediately after any
  dispatch — that is, after `/scope` invokes a child skill
  (`/brief`, `/prd`, `/design`, `/plan`). Team-lead MUST NOT
  transition to indefinite passive wait on the inbox.
  `[automated-unit]` (R19)
- [ ] **AC26b** The discipline loop's evidence-check ordering
  puts **filesystem before inbox**: each cycle inspects expected
  artifact paths, git log, and `wip/` file growth as priority 1
  before processing teammate messages as priority 2.
  `[automated-eval]` (R19)
- [ ] **AC26c** Nudges sent by team-lead contain
  **directly-executable instructions** — what artifact to
  produce, where to write it, and what structured verdict to
  reply with. Nudges MUST NOT consist of open-ended questions.
  `[automated-unit]` (R19)
- [ ] **AC26d** The patience budget exhausts at 5 stagnation
  cycles per teammate for the default review-verdict task class
  (per R19's canonical defaults). `[automated-eval]` (R19)

### Fold-driven discipline (R20-R23)

- [ ] **AC27a** When `/scope` invokes a child and the child
  returns a PASS verdict, `/scope` verifies the durable artifact
  exists at the expected path BEFORE proceeding. When the
  artifact is absent despite the PASS verdict, `/scope` treats
  the verdict as STALE and routes via R8's bail-handling rule
  using the most-recently-running tie-break (the child whose
  verdict is STALE); if no wip/ intermediate exists for that
  child, the route resolves to clean-cancel.
  `[automated-eval]` (R20, R8)
- [ ] **AC27b** Eval scenarios include at least one scenario
  per child where the child returns PASS but the artifact is
  absent; the scenario verifies `/scope` treats it as STALE and
  routes to bail-handling rather than the happy path.
  `[automated-eval]` (R20)
- [ ] **AC28** Before each Phase 2 child invocation, `/scope`
  attempts a rebase, then analyzes the contextual impact of any
  upstream commits that landed. The observable: an eval scenario
  with upstream changes that touch a chain-referenced contract
  verifies `/scope` halts and routes to the team lead with
  evidence; a second scenario with upstream changes orthogonal to
  the chain verifies `/scope` proceeds silently without prompting
  either the team lead or the author; a third scenario with a
  rebase conflict in a chain-orthogonal file verifies the conflict
  is resolved from artifact context (or by the parent's
  conflict-resolution sub-agent) without escalation. `[automated-eval]`
  (R21)
- [ ] **AC28b** `references/parent-skill-worktree-discipline.md`
  exists at the top-level reference root and documents the
  trigger condition (before each Phase 2 child invocation), the
  rebase-then-analyze flow, the three-level impact classification
  (none / informational / intent-changing), the escalation
  contract (none/informational → proceed silently; intent-changing
  → team lead, then author only if intent genuinely changed), and
  the three-option author-facing prompt (re-author affected
  artifacts / proceed against original intent / bail) that surfaces
  only on team-lead escalation. The reference is cited from
  `/scope`'s Phase 2 chain-orchestration reference file.
  `[automated-unit]` (R21)
- [ ] **AC29a** The motivating
  `docs/plans/PLAN-shirabe-scope-skill.md` produced as part of
  /scope's ship uses `<<ISSUE:N>>` placeholder syntax verbatim
  with explanatory prose mirroring `/plan` SKILL.md's
  "Placeholder Conventions" section. `[automated-unit]` (R22)
- [ ] **AC29b** When `/scope` re-enters mid-chain against an
  Active PLAN with unresolved `<<ISSUE:N>>` placeholders,
  `/scope`'s chain-orchestration logic does NOT flag the
  placeholders as staleness; the eval scenario verifies a clean
  resume across the unresolved-placeholder boundary.
  `[automated-eval]` (R22)
- [ ] **AC30a** `/prd`'s shipped Phase-N Reject contract
  (named in R23) adds a final-confirmation gate to `/prd`'s
  Phase 4 offering Accept/Reject/Continue-revising; on Reject,
  `/prd` runs `git rm docs/prds/PRD-<topic>.md`, cleans up
  `wip/prd_<topic>_*.md`, and commits
  `docs(prd): discard PRD draft for <topic>`.
  `[automated-eval]` (R23)
- [ ] **AC30b** `/design`'s shipped Phase-N Reject contract
  (named in R23) adds a final-confirmation gate to `/design`'s
  Phase 6 offering Accept/Reject/Continue-revising; on Reject,
  `/design` runs `git rm docs/designs/DESIGN-<topic>.md`,
  cleans up `wip/design_<topic>_*.md`, and commits
  `docs(design): discard DESIGN draft for <topic>`.
  `[automated-eval]` (R23)
- [ ] **AC30c** When invoked outside `/scope`, both `/prd` and
  `/design` Phase-N Reject contracts function identically (the
  contract is the child's own, not `/scope`'s). The discard
  commit is the durable trace; no Decision Record is written
  retroactively on a later `/scope` resume. `[automated-eval]`
  (R23, US-6)

## Out of Scope

The following are deliberately excluded from `/scope` v1. Each
links to its successor effort where relevant.

- **The `/work-on` migration into the parent-skill pattern
  (future work).** Separate feature; depends on amplifier-layer
  workflow-composition substrate that `/scope` does not require
  for its own ship. `/scope` ratifies the pattern for `/work-on`;
  the migration itself is downstream.
- **The review-time redirect mechanism (future work).** Manual fallback
  is first-class by design; the automatic-redirect substrate is
  amplifier-layer work and is not a prerequisite for `/scope`.
- **Pattern-ergonomics tightening (future work).** Several the /charter precedent-
  retrospective items defer to follow-up work explicitly (single-pr
  value-gated heuristic from L1, `ci_outcome` semantics from L6,
  reviewer coverage categories from L10, Track B amplifier-layer
  observations). The cascading folds this PRD enumerates (R20-
  R22) are the v1-cheap inside-pattern Track A items only.
- **Re-litigating pattern invariants I-1 through I-7 at the
  abstract level.** The pattern's seven semantic invariants
  stand as `/charter` ratified them; `/scope` adds gate
  vocabulary (Mandatory-with-auto-skip) and one new reference
  but does not edit the invariants.
- **The amplifier-layer workflow substrate.** The migration into
  workflow-composition infrastructure is downstream; `/scope`
  ships against current shirabe patterns (`wip/`-based
  intermediates, plain-English phase prose).
- **The niwa workspace context surface.** `/scope` uses current
  CLAUDE.md visibility detection; substrate cleanup is unrelated.
- **Migration of existing tactical-progression artifacts.**
  `/scope` adds a parent layer without renaming or restructuring
  the children's artifacts. Existing BRIEF, PRD, DESIGN, PLAN
  docs continue to validate under their existing schemas.
- **Authoring `/brief`, `/prd`, `/design`, or `/plan` skill
  bodies.** `/scope` consumes the four children as they ship
  today. The only child-side work in scope is the Phase-N Reject
  contract extensions to `/prd` and `/design` (R23); any other
  child SKILL.md revisions are separate PRs.
- **A feeder slot in the tactical chain v1.** The tactical chain
  has no feeder skill analogous to `/charter`'s `/comp`. Pattern-
  level future-proofing keeps the feeder slot named in the
  pattern doc; `/scope` ships without a populated feeder
  position. If a future feeder lands (e.g.,
  `/spike-feasibility`), the three-condition gate template at
  the pattern level accommodates it without re-deriving the
  contract.
- **A new shirabe artifact type for re-evaluation Decision
  Records.** `/scope` v1 establishes
  `DECISION-{prd|design}-*.md` in `docs/decisions/` by
  precedent (matching shirabe's existing `<TYPE>-<name>.md`
  prefix pattern and inheriting from `/charter`'s
  `DECISION-strategy-*.md` precedent). A separate feature can
  later formalize a decision-record artifact type with full
  validator rules if warranted.
- **Cross-topic resume in the same session.** The state file is
  topic-keyed by filename (`wip/scope_<topic>_state.md`), so
  concurrent or sequential invocations against different topics
  in the same session do not interfere. v1 does NOT support
  resume against a different topic mid-chain; the resume ladder
  is per-topic.
- **Cross-branch state-file behavior.** The state file under
  `wip/` is branch-coupled — `/scope` resume requires the same
  feature branch as the original run. If exit-tracking ever
  needs to cross branches (e.g., merge `/plan`'s milestone PR,
  then resume `/scope` on main), the `wip/`-based model breaks.
  No `/scope` v1 requirement forces cross-branch resume; the
  limitation is flagged for the designer to consider when the
  workflow-substrate work is bounded.
- **Stale-session threshold configurability.** Fixed at 7 days
  in v1 per R16, inherited from `/charter`. A future release
  may make it configurable.

## Questions Deferred to Design

This section serves the role `prd-format.md` reserves for the
optional "Open Questions" section, but the questions below are
deliberately design-altitude inputs (not Draft-blocking unknowns).
The PRD made its decisions; the questions below are legitimate
design-altitude inputs for the downstream design phase. Each
names the area and where the resolution should land.

1. **The Phase-N Reject contract implementation on `/prd` and
   `/design`.** R23 specifies the contract surface (Accept/
   Reject/Continue-revising final-confirmation gate; `git rm`
   on Reject; commit message format). The implementation detail
   — which Phase the gate inserts into for each child, whether
   it replaces or augments the existing final-prompt logic,
   whether `/design`'s gate fires before or after the
   directory-move into `docs/designs/current/` — is design-team
   territory. The contract is firm; the placement and ordering
   are not.

2. **The shape-predicate evaluation mechanism for R6.** R6
   names three agent-judgment predicates (architectural
   alternatives, new components/interfaces, Complex
   classification). The implementation mechanism — checklist
   walk during Phase 1, structured prompt to the agent,
   delegation to a sub-decision skill — is design-team
   territory. R6 specifies the predicates; the evaluation
   mechanism is not.

3. **PLAN-status-aware re-entry signaling to `/plan`.** R11's
   resume ladder defers to `/plan`'s own resume logic when
   the chain re-enters with a Draft PLAN; for Active/Done PLAN
   it refuses and redirects. The signaling mechanism by which
   `/scope` suppresses `/plan`'s own "Resume / Start fresh"
   prompt on Draft re-entry — analogous to AC20 in `/charter`'s
   PRD — is design-team territory.

4. **The worktree-staleness reference's exact prose.** R21
   specifies the trigger condition and the three-option prompt;
   `references/parent-skill-worktree-discipline.md`'s detailed
   prose (rebase mechanics, "proceed anyway" recording semantics,
   integration with the chain-proposal prompt) is design-team
   territory.

5. **Cross-boundary state-snapshot semantics.** R10 specifies the
   `child_snapshots` block; the `boundary:` field interacts with
   it in nuanced ways (e.g., when a re-evaluation Decision Record
   is written, does `child_snapshots` advance to record the
   Decision Record or stay frozen on the referenced artifact?).
   Design-team territory.

## Known Limitations

- **`/prd` and `/design` need Phase-N Reject contract extensions
  shipped before `/scope` v1.** R23 makes this explicit. The
  contract extensions are substantial work for two child skills.
  `/scope`'s ship is gated on them.

- **The shape-predicate evaluation in R6 depends on agent
  judgment.** Unlike `/charter`'s R7 Building-Blocks-count
  predicate (concrete and file-level), `/scope`'s R6 predicates
  are agent-judgment. False negatives (skipping `/design` when
  it should have fired) cost re-work; false positives (running
  `/design` when not warranted) cost time.

- **State file is branch-coupled.** The
  `wip/scope_<topic>_state.md` file lives on the feature branch
  of the original `/scope` run. Resume across branches is not
  supported in v1. This bites harder in tactical chains than in
  strategic ones because `/plan`'s `multi-pr` mode creates a
  milestone with downstream issues that will be implemented on
  different feature branches.

- **No runtime success metric defined for `/scope`.** Pattern-
  conformance is verifiable (does `/scope` cite the right
  references, produce the right exit artifacts?). Behavioral
  success (do authors use `/scope` for tactical features rather
  than manual chaining? does the chain reach PLAN-Active faster
  than manual sequencing?) is not defined.

- **Stale-session threshold is fixed at 7 days.** Inherited
  from `/charter`. Not configurable in v1.

- **CLAUDE.md missing visibility header defaults to Private.**
  Inherited from shipped `/charter` behavior. The practical
  mitigation is the authoring guideline that every public repo's
  CLAUDE.md must declare visibility explicitly.

- **No `/comp`-equivalent feeder in tactical chain v1.** The
  tactical chain has no competitive-framing-at-feature-level
  analog. `/scope` ships without a populated feeder position.

- **Worktree-staleness check imposes per-invocation overhead.**
  R21 adds a `git fetch` before each Phase 2 child invocation
  (four times per full-run chain). On slow networks the check
  adds noticeable latency. The trigger is bounded
  ("before each Phase 2 child invocation," not "every operation"),
  but the overhead is real.

## Decisions and Trade-offs

Decisions made during scoping and research that shape requirements
above. Each entry names what was decided, what alternatives
existed, and the reasoning.

### Decision 1: Extend pattern contract surface to preserve full symmetry with `/charter`

**Decided.** /scope's scope includes pattern-doc edits and upstream
contract extensions to `/prd` and `/design`. The pattern's gate
vocabulary grows from three (EITHER-signal, ALWAYS,
shape-dependent) to four by adding Mandatory-with-auto-skip; the
re-evaluation exit's rejection sub-shape is preserved in `/scope`
by adding Phase-N Reject contracts to `/prd` and `/design` as
/scope prerequisites; a new top-level reference
`references/parent-skill-worktree-discipline.md` lands as shared
infrastructure both `/charter` and `/scope` cite.

**Alternatives considered.**

(a) **Stay narrow.** Unify `/prd`'s gate as EITHER-signal with a
"requirements-shift" signal; drop the rejection sub-shape in
`/scope`; place the worktree runbook at
`skills/scope/references/`. Smaller surface, but the rejection
sub-shape would silently disappear inside the pattern contract
(asymmetry that has nothing to do with the strategic/tactical
distinction); the `/prd` gate framing would force a contrived
signal that doesn't match `/prd`'s actual resume semantics; the
worktree runbook would create a known re-home in follow-up work.

**Reasoning.** Full contract symmetry across both parent skills
is load-bearing for the parent-skill pattern v1; asymmetries
left unaddressed in `/scope` v1 would compound across the `/work-on`
migration, the review-time redirect, and follow-up pattern
ergonomics. The "stay narrow" velocity gain is one-time; the
contract symmetry pays off across every downstream parent.

### Decision 2: BRIEF is treated as a chain member, not a feeder

**Decided.** `/brief` is a chain member with EITHER-signal gate;
its skipped-vs-ran disposition is recorded symmetrically with
`/prd`, `/design`, and `/plan` in `chain_ran` and
`chain_skipped`. "Brief-only" runs (the chain runs `/brief` and
then exits via abandonment-forced before `/prd`) are expressed
as `exit: abandonment-forced` with `triggering_child: /brief`,
not as a new exit shape.

**Alternatives considered.** Treat `/brief` as a feeder analogous
to `/comp` in `/charter`'s chain. Would require a new exit
sub-shape or shape for "brief-only" — and would create asymmetry
where the other three children are first-class chain members
with Phase-N finalization verdicts but `/brief` is not.

**Reasoning.** Rejection sub-shape symmetry requires that every
chain child has a Phase-N Reject finalization verdict. If
`/brief` were a feeder, the chain-proposal logic would treat it
asymmetrically. Chain-member status also lets "brief-only" be
expressed cleanly as abandonment-forced rather than introducing a
new exit shape, keeping the brief's three-exit count literal.

### Decision 3: Re-evaluation exit gains a boundary dimension AND keeps two sub-shapes

**Decided.** The re-evaluation exit gets two boundary positions
(PRD or DESIGN) and two sub-shapes (re-evaluation or rejection).
The four combinations share the artifact body shape and inherit
from the pattern's re-evaluation template. The state file gains a
new `boundary:` field that disambiguates PRD-boundary from
DESIGN-boundary; the existing `decision_record_sub_shape:` field
distinguishes re-evaluation from rejection.

**Alternatives considered.**

(a) **Collapse to a single PRD-boundary.** Treat the DESIGN-
boundary case as a special instance of the PRD-boundary case,
keeping `/charter`'s one-boundary state-schema shape. Would lose
the architectural signal — when a `/scope` run concludes "the
DESIGN holds" it's a different conclusion than "the PRD holds,"
and the Decision Record's Context section addresses different
load-bearing claims.

(b) **Add two new exit shapes** instead of multiplying the
re-evaluation exit. Would break the brief's three-exit count
literally and require a brief revision.

**Reasoning.** The tactical chain has two settled-upstream
boundaries where the strategic chain has one. Honoring both
keeps the pattern's three-exit count verbatim while giving the
state file enough discrimination to write the correct Decision
Record. The four-combination matrix (2 boundaries × 2
sub-shapes) shares the same artifact body shape, so the
authoring overhead is minimal; only the Context, Decision, and
Options-Considered prose differ per combination.

### Decision 4: Worktree-discipline reference lands at top-level, not parent-specific

**Decided.** `references/parent-skill-worktree-discipline.md`
lands at the top-level reference root (sibling to
`parent-skill-pattern.md`,
`parent-skill-state-schema.md`,
`parent-skill-resume-ladder-template.md`,
`parent-skill-child-inspection.md`). `/scope`'s SKILL.md cites
it; `/charter`'s SKILL.md gets a follow-up reference-table
addition in a small back-edit PR.

**Alternatives considered.** Place at
`skills/scope/references/operational-runbook.md`. Ships faster
but creates known re-home work in follow-up work. The exploration's
learning-fold-opportunities Lead recommended the parent-specific
location for velocity reasons; the exploration's decisions doc
overrode this to the top-level location.

**Reasoning.** Worktree staleness affects every long-running
parent skill, not just `/scope`. Top-level placement lets future
parents (`/work-on` migration, future tactical parents) inherit
the same trigger condition without re-deriving it. Deferring to
follow-up work leaves a known-good fold sitting outside the pattern's
contract surface; now is the right time to land it because the
tactical chain bites this gap harder than the strategic chain
(4-child runs span longer than 3-child runs).

### Decision 5: L9 PRD pattern-level requirement tagging is a required convention

**Decided.** Every requirement in this PRD MUST be tagged either
`[pattern-level]` or `[/scope-specific]` in its title. Pattern-
level requirements reuse `/charter`'s exact R-numbers (R1, R3,
R9, R10, R11, R12, R13, R14, R17a, R18, R19); `/scope`-specific
new requirements start at R20 to avoid clashing with `/charter`'s
own `/charter`-specific R-numbers.

**Alternatives considered.** Tag only some requirements, or skip
tagging entirely. Both alternatives break the mechanical
review-checkability the convention provides: a reviewer cannot
grep for `[pattern-level]` and verify the pattern-doc edits
cover all of them.

**Reasoning.** The L9 fold is the only mechanical way for
reviewers to verify that pattern-doc edits cover all pattern-
level requirements. Without it, pattern-doc edits become opaque
to grep-based review. The /charter retrospective framed L9 as
"untapped learning"; this PRD reclassifies it as "established
convention `/scope` MUST follow" because the pattern itself
requires it.

### Decision 6: `/prd` gate is Mandatory-with-auto-skip, not EITHER-signal

**Decided.** `/prd`'s invocation gate is a new pattern-level
gate shape — Mandatory-with-auto-skip — added to
`references/parent-skill-pattern.md`'s existing gate vocabulary.
The semantics: `/prd` ALWAYS invokes unless an Accepted PRD
already exists for the topic, in which case `/prd` is auto-
skipped and recorded in `chain_skipped`.

**Alternatives considered.** Unify `/prd`'s gate with EITHER-
signal where signal 1 is "no Accepted PRD exists" and signal 2
is "requirements-shift detected during Phase 1." Would keep the
pattern's gate vocabulary at three entries instead of four. But
the EITHER-signal framing forces a contrived "requirements-
shift" signal that doesn't match `/prd`'s actual resume
semantics — `/prd` is mandatory in the new-topic case and
auto-skippable in the existing-Accepted case; there is no
discovered-during-Phase-1 signal that would tip the gate.

**Reasoning.** The honest framing is the more accurate framing.
Mandatory-with-auto-skip captures `/prd`'s actual semantics; the
EITHER-signal unification would mislead future parent-skill
authors who consult the pattern doc. Adding a fourth gate type
is the smaller change relative to forcing a misnamed third gate
type.

### Decision 7: Two folds added as new requirements; two folds embedded as authoring discipline

**Decided.** Observations #3 + #9 are paired into a single new
`/scope`-specific requirement R20 (structural file-existence +
reviewer-PASS-with-artifact-presence check at child-invocation
review). Observation #11 lands as R21 (worktree-staleness check
trigger condition). L11 (`<<ISSUE:N>>` placeholder discipline)
lands as R22. L9 (PRD pattern-level requirement tagging) is
captured as Decision 5 above — not a new R-numbered requirement
because it's an authoring convention this PRD itself follows,
not a `/scope` runtime behavior.

**Alternatives considered.** Add each as a separate R-numbered
requirement. Would inflate the requirement count past 25 without
adding contract surface — observations #3 and #9 are two faces of
the same fold, and L9 is an authoring discipline, not a runtime
behavior.

**Reasoning.** R-numbered requirements capture `/scope` runtime
behavior; authoring disciplines belong in Decisions and Trade-
offs. Pairing #3 and #9 keeps the requirement count at ~21-23 as
predicted; folding L9 into Decision 5 keeps L9 reviewable
without inflating R-numbers.

### Decision 8: `--max-rounds=N` default is 5 (vs `/charter`'s 3)

**Decided.** `/scope` defaults `--max-rounds=N` to 5, up from
`/charter`'s default of 3.

**Alternatives considered.** Keep the same default as `/charter`
for consistency. Would under-budget tactical chains, since they
have two re-evaluation boundaries (not one) and requirements/
design churn faster than strategic thesis.

**Reasoning.** Tactical chains have more re-evaluation
opportunities than strategic chains, both by boundary count
(2 vs 1) and by domain volatility (requirements churn vs thesis
churn). A higher default accommodates the natural surface
without forcing user override. Authors who want `/charter`-style
discipline can override via the `--max-rounds=N` flag.

### Decision 9: `/scope` against PLAN-Active or PLAN-Done refuses and redirects

**Decided.** When `/scope` resumes against a topic whose PLAN is
Active, `/scope` refuses re-entry as a chain-authoring skill and
redirects to `/work-on`. When the PLAN is Done, `/scope`
redirects to `/release`. Neither case fires the Re-evaluate /
Revise / Bail triad.

**Alternatives considered.** Treat PLAN-Active and PLAN-Done
symmetrically with PLAN-Draft (offer continue / start fresh) or
with the PRD/DESIGN-boundary triad (Re-evaluate / Revise / Bail).
Would conflict with the established skill ownership boundaries:
`/work-on` owns Active PLANs (implementation in progress);
`/release` owns Done PLANs (post-implementation finalization).

**Reasoning.** Re-entering chain authoring against an actively-
implementing or completed feature is a category error. `/scope`
respects skill ownership boundaries; the refuse-and-redirect
behavior surfaces the boundary explicitly rather than letting
`/scope` overwrite work owned by another skill.

### Decision 10: `/scope`'s validator pass-through validates each intermediate

**Decided.** `/scope` validates each intermediate artifact as the
chain crosses boundaries: PRD passes `shirabe validate` before
`/scope` invokes `/design`; DESIGN before `/scope` invokes
`/plan`; PLAN before `/scope` declares full-run.

**Alternatives considered.** Validate only the terminal PLAN at
full-run exit (matching `/charter`'s AC24 single-artifact
validation). Would leave intermediate artifacts unverified at
chain-completion-time.

**Reasoning.** Strict pass-through matches the inheritance
pattern's discipline. The chain-level validation gate is
`/scope`'s, not the children's — and a simpler PLAN-only
validation would leave a class of intermediate-artifact bugs
silent until much later.

## Downstream Artifacts

`/scope`'s PRD is the upstream input for the following work.
Each downstream artifact owns its own acceptance criteria; the
linkages below are commitments this PRD makes to the downstream
artifact's framing.

- **`docs/designs/DESIGN-shirabe-scope-skill.md`** — the design
  doc for `/scope` (renamed from `DESIGN-shirabe-explore-split.md`
  per Decision 1 in the upstream BRIEF and roadmap update). The
  design should lift every requirement tagged `[pattern-level]`
  in this PRD into its pattern-level scope so `/work-on` (future work)
  and future parents inherit the mechanism. The PRD's
  requirement-tagging is the baton; verifying the design respects
  it is the design doc's own acceptance check, not this PRD's.
  The pattern-level requirements at PRD acceptance time are: R1,
  R3, R9, R10, R11, R12, R13, R14, R17a, R18, R19 (11
  requirements — identical to `/charter`'s pattern-level set).

- **`skills/scope/SKILL.md`** — the loadable skill itself. AC1
  through AC1b verify the structural template.

- **`skills/scope/evals/evals.json`** — eval scenarios covering
  US-1 through US-6 (per R18 and AC24b).

- **Pattern-doc edit:
  `references/parent-skill-pattern.md`** — adds the fourth gate
  type (Mandatory-with-auto-skip) to the existing gate
  vocabulary, with `/prd`'s gate as the canonical example.

- **New top-level reference:
  `references/parent-skill-worktree-discipline.md`** — captures
  the worktree-staleness trigger condition (per R21 and
  AC28b) as shared infrastructure both `/charter` and `/scope`
  cite.

- **`/prd` Phase-N Reject contract extension** — adds the
  final-confirmation gate to `/prd`'s Phase 4 (per R23 and
  AC30a).

- **`/design` Phase-N Reject contract extension** — adds the
  final-confirmation gate to `/design`'s Phase 6 (per R23 and
  AC30b).

- **Workspace and shirabe CLAUDE.md updates** — surface `/scope`
  entry triggers (per R17a, R17b, and AC24a). shirabe CLAUDE.md
  gains a "Tactical Chain Entry: /scope" section paralleling
  the existing "Strategic Chain Entry: /charter" section.

- **Roadmap update** — the relevant upstream roadmap entry gets updated to
  reflect that the discover/converge engine consumption is via
  cross-skill pointing into
  `skills/explore/references/phases/{phase-2-discover,phase-3-converge}.md`
  rather than engine extraction. The design doc rename is
  reflected here.

- **Follow-up reference-table addition to
  `skills/charter/SKILL.md`** — adds a citation to
  `references/parent-skill-worktree-discipline.md` so `/charter`
  inherits the worktree-staleness discipline. Small back-edit
  PR.
