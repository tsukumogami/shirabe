---
schema: brief/v1
status: Done
problem: |
  shirabe ships `/brief`, `/prd`, `/design`, and `/plan` at the tactical
  chain's altitude as direct-invocation child skills, but no parent
  skill walks an author through the chain as a sequence, enforces the
  three-exit contract across BRIEF/PRD/DESIGN/PLAN boundaries, or
  proves the parent-skill pattern v1 against the tactical chain's
  asymmetries (extra re-evaluation boundary, no Phase-5 Reject by
  default, multi-output-mode terminal child). Authors today sequence
  the chain by hand; the pattern stays unratified for the parent skills
  that follow.
outcome: |
  An author invokes `/scope`, the skill orients on whichever durable
  upstream artifacts already exist (BRIEF, PRD-Accepted, DESIGN at
  `current/`, PLAN at any of Draft/Active/Done), proposes a chain from
  the most-downstream settled point, and walks the children under
  their per-gate semantics. The conversation lands at one of three
  durable exits — full-run, re-evaluation Decision Record (at TWO
  boundaries now), or abandonment-forced — with cross-boundary resume
  and manual fallback as first-class steady-state surfaces.
---

# BRIEF: shirabe-scope-skill

## Status

Done

## Problem Statement

shirabe ships the tactical chain's four altitudes — BRIEF, PRD,
DESIGN, PLAN — as four loadable child skills that authors invoke
directly. `/brief` frames a feature before requirements; `/prd`
captures requirements; `/design` works the architecture; `/plan`
decomposes a design into atomic implementable issues, in either
single-pr or multi-pr output mode. The four exist; they validate
under their own format references; they are well-trodden. What's
missing is the parent layer: a skill that walks an author through
the tactical conversation as a *sequence*, deciding which children
to invoke against the upstream artifacts already on disk, carrying
scope between BRIEF and PRD and DESIGN and PLAN boundaries without
the author having to remember the order, and enforcing the same
three-exit contract `/charter` made first-class for the strategic
chain.

In the absence of a parent skill, authors today reach for the
tactical chain as four separate invocations. They re-derive the
sequencing decisions on every run: when does a BRIEF dog-foot in?
when is a DESIGN warranted given the PRD's complexity? when does
the PLAN's `single-pr` versus `multi-pr` choice fire? They carry
context manually with no resume contract if the session breaks
across child boundaries — and the tactical chain breaks across
boundaries more often than the strategic one, because requirements
and design churn faster than thesis. They have no enforcement that
the chain produces a durable terminal artifact rather than evidence
files in `wip/`. The work is done by discipline alone, and
discipline is exactly the wrong substrate for an invariant.

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
- **No Phase-5 Reject finalization on `/prd` or `/design` today.**
  `/charter`'s rejection sub-shape on the re-evaluation exit is
  gated on `/strategy`'s Phase 5 Reject verdict firing inside the
  chain. The tactical chain's children have no analogous reject
  finalization in their current contracts. Either the pattern's
  rejection sub-shape silently disappears in `/scope` (asymmetry
  inside the pattern contract that has nothing to do with the
  strategic/tactical distinction), or `/prd` and `/design` grow
  Phase-N Reject contracts as prerequisites — substantial upstream
  contract work, but the only way to preserve symmetry.
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
for the topic; the auto-skip is real and load-bearing, but the
pattern doc has no name for it. Either the pattern's gate vocabulary
grows a fourth entry (Mandatory-with-auto-skip), or `/prd`'s gate
unifies into EITHER-signal with a contrived "requirements-shift"
signal that doesn't actually match `/prd`'s resume semantics.

The remaining gap has five parts:

- **No parent skill entry point.** Future tactical-chain authors
  have no `/scope` to load. They re-discover the sequencing logic
  per run, including which upstream artifact triggers which entry
  point — `/scope <PRD-path>` versus `/scope <DESIGN-path>` versus
  `/scope <topic-slug>` versus cold.
- **No codified delegation graph.** The four `/scope` → child
  interfaces (`/brief`, `/prd`, `/design`, `/plan`) each have
  different inputs, output shapes, lifecycles, and conditionality
  rules, but no document encodes them as a single contract.
- **No resume ladder across four child boundaries.** Resume within
  a single skill is precedent; resume across `/scope`'s four
  doc-emitting children, with three statuses on the terminal PLAN
  (`Draft`/`Active`/`Done`) and DESIGN's directory-move lifecycle
  (`docs/designs/` → `docs/designs/current/`), is new.
- **No terminal-artifact enforcement for the tactical chain.** The
  three exits — full-run at PLAN, re-evaluation Decision Record at
  either PRD- or DESIGN-boundary, abandonment-forced
  materialization — exist as architectural intent inherited from
  the pattern, but have no parent skill that implements them.
- **No pattern-validation evidence beyond `/charter`.** A contract
  validated on a single instance is a contract observed once.
  `/scope` is the second parent the pattern needs to ratify
  itself. The amplifier-layer parent skill (the `/work-on`
  migration that follows) cannot inherit from a pattern that has
  only one ground-truth example.

The problem is not that authors can't sequence the tactical chain
by hand. They do, every day. It's that without `/scope`, the
tactical chain's invariants are unenforceable, the parent-skill
pattern's contract surface stays untested against a chain it was
designed to hold, and the asymmetries the tactical chain exposes
go unresolved — silently degrading the pattern's symmetry as more
parent skills land.

## User Outcome

A skill author opens Claude Code in shirabe with a feature named on
the roadmap, surfaced from `/explore`'s crystallize phase, or
sitting in their head as a half-formed PRD intent. They invoke
`/scope`. The skill opens with discovery: it inspects the durable
artifacts already on disk for the topic — `docs/briefs/BRIEF-*.md`,
`docs/prds/PRD-*.md`, `docs/designs/current/DESIGN-*.md`,
`docs/plans/PLAN-*.md` — detects how far the tactical conversation
has already gone, and proposes a chain to run from the
most-downstream settled point. The author sees the chain plan, can
adjust it, and confirms. From there, `/scope` walks the children
under their per-gate semantics: `/brief` if no Accepted BRIEF
exists and the feature's framing isn't already settled in an
upstream PRD, `/prd` always unless an Accepted PRD already exists,
`/design` only when the just-produced PRD exposes architectural
decisions or surface complexity that warrant an explicit design,
`/plan` as the terminal child producing a PLAN doc and (in
`multi-pr` mode) a GitHub milestone with issues. The author never
has to remember the order, the gates, or which artifact triggers
which entry; the skill enforces the chain.

```mermaid
flowchart LR
    A([/scope topic-slug<br/>or upstream path]) --> P[Phase 1<br/>Discovery + Chain Proposal]
    P --> B{Accepted BRIEF<br/>at upstream?<br/>framing-shift signal?}
    B -->|fire| By[/brief]
    B -->|skip| Pr[/prd<br/>ALWAYS unless<br/>Accepted PRD exists]
    By --> Pr
    Pr --> D{Design surface?<br/>PRD complexity<br/>or new components?}
    D -->|fire| Dy[/design]
    D -->|skip| Pl[/plan<br/>single-pr or<br/>multi-pr]
    Dy --> Pl
    Pl --> Exit([Exit])
```

The conversation ends at one of three durable exits, mirroring
`/charter`'s contract across both the boundaries the tactical chain
exposes:

- **Full-run exit.** The chain reaches PLAN. In `single-pr` mode,
  the PLAN doc lands at `docs/plans/PLAN-<topic>.md` with status
  Draft and a complete Issue Outlines section; in `multi-pr` mode,
  the PLAN doc lands with status Active alongside a GitHub
  milestone and a set of issues. Intermediate PRD and DESIGN
  artifacts are settled (Accepted PRD; Accepted DESIGN moved to
  `docs/designs/current/`). The chain halts at the durable
  artifacts for human review.
- **Re-evaluation exit, at either boundary.** When the chain runs
  against an already-Accepted PRD or an already-Accepted DESIGN
  and the conversation concludes the existing artifact still
  holds, `/scope` writes a Decision Record referencing the
  existing artifact by path:
  `DECISION-prd-<topic>-re-evaluation-<date>.md` at the PRD
  boundary, or `DECISION-design-<topic>-re-evaluation-<date>.md`
  at the DESIGN boundary. No re-authoring; no proceeding to the
  next child. The lightweight exit satisfies the terminal-artifact
  contract without forcing a redundant PRD or DESIGN revision.
- **Abandonment-forced exit.** When the author breaks the chain
  mid-flight — closes the session, switches tasks for a week, or
  tells `/scope` to wrap up as it stands — the chain forces the
  most-recently-running child to materialize its artifact even if
  that child's own decision rule would have left evidence-only
  files in `wip/`. The tactical chain leaves a review surface
  regardless of how it ended.

```mermaid
flowchart TD
    Run([/scope run reaches a chain boundary]) --> Q{Outcome shape?}
    Q -->|new or revised<br/>tactical content<br/>through to PLAN| FR[Full-run exit<br/><br/>PLAN-Draft single-pr<br/>or PLAN-Active multi-pr<br/>+ upstream PRD/DESIGN settled]
    Q -->|existing PRD still holds| RE1[Re-evaluation exit<br/>PRD-boundary<br/><br/>DECISION-prd-topic-<br/>re-evaluation-YYYY-MM-DD]
    Q -->|existing DESIGN still holds| RE2[Re-evaluation exit<br/>DESIGN-boundary<br/><br/>DECISION-design-topic-<br/>re-evaluation-YYYY-MM-DD]
    Q -->|author bails<br/>mid-chain| AF[Abandonment-forced exit<br/><br/>most-recently-running child<br/>force-materialized as Draft]
```

A `/scope` run that closes without one of these has violated the
terminal-artifact contract; the skill enforces all three
explicitly. The two re-evaluation boundaries are the novel
contribution against `/charter`'s single boundary, and they're
what prevent every `/scope` run against a settled chain from being
tempted into a redundant PRD or DESIGN revision when nothing
changed.

The author can resume `/scope` mid-chain if the session breaks.
The resume ladder detects partial child runs across four positions
(`wip/brief_<topic>_*`, `wip/prd_<topic>_*`,
`wip/design_<topic>_*`, `wip/plan_<topic>_*`) and offers
continue-from-here. Status-aware re-entry against a PLAN handles
three statuses (Draft, Active, Done) rather than `/charter`'s two,
since the PLAN lifecycle has no Accepted state. Manual fallback
remains first-class: a `/prd` or `/design` run done directly
outside `/scope` leaves the same durable artifact the in-chain
run would have, at the same path with the same frontmatter, and
`/scope`'s resume ladder reads that surface identically either
way. Authors and reviewers retain full control over the tactical
chain at any altitude; `/scope` provides discipline without
becoming a bottleneck.

Downstream, `/scope` shipping ratifies the parent-skill pattern
v1: the contract surface holds across two parents with genuinely
different chain shapes, the tactical chain's asymmetries all land
inside the pattern's existing extension points, and the amplifier-
layer parent skill that follows finally inherits from a pattern
with two ground-truth examples instead of one.

## User Journeys

Five journeys exercise `/scope` from distinct entry points. Each
names the user, the trigger, the path through the chain, and the
exit shape.

### Journey 1: Skill author, cold standalone invocation

A skill author opens Claude Code in shirabe with a feature named on
the roadmap and no durable upstream artifacts yet. They invoke
`/scope <topic-slug>` with the topic slug as the only argument. The
skill opens with discovery: it inspects `docs/briefs/`, `docs/prds/`,
`docs/designs/current/`, and `docs/plans/` for any matching durable
artifact, finds none, and proposes the full chain
`/brief → /prd → /design → /plan` with the author's confirmation. The
chain walks each child in order. `/brief` produces a BRIEF Draft and
transitions to Accepted after its own Phase 5 approval. `/prd`
produces a PRD Draft and transitions to Accepted. `/design` produces
a DESIGN Proposed and transitions to Accepted with the directory
move into `docs/designs/current/`. `/plan` produces a PLAN — Draft
in `single-pr` mode, Active in `multi-pr` mode — and the chain halts
at the durable terminal artifact for human review.

This is the primary mode. It validates that `/scope` walks an author
through the full tactical conversation without forcing them to
remember the chain order, the gate semantics, or which child writes
which artifact path. It also exercises the inheritance promise from
`/charter`: the pattern's four references transfer verbatim and
`/scope`'s own SKILL.md fills the body slots with tactical-chain
specifics.

### Journey 2: Author with PRD already Accepted

A skill author returns to a feature whose PRD has already landed —
either because the author ran `/prd` directly before deciding to use
the parent skill, or because an earlier `/scope` run was interrupted
after `/prd`'s Accepted transition. They invoke `/scope` against the
topic slug. Discovery inspects the durable artifacts, finds an
Accepted PRD at `docs/prds/PRD-<topic>.md`, and proposes a chain
that starts at `/design`. The `/brief` gate auto-skips: the chain's
mandatory-with-auto-skip semantics see the Accepted PRD as evidence
that the framing has been settled downstream, and the chain proposal
records `/brief` in the skipped list rather than the run list. The
chain walks `/design` then `/plan`, lands the terminal artifact, and
halts.

This journey exercises the fourth pattern-level gate type
(Mandatory-with-auto-skip) that `/prd`'s invocation rule motivates.
It also validates the BRIEF-as-chain-member decision: the chain's
state file records `/brief` in `chain_skipped` rather than treating
it as a feeder-doc-detected slot, preserving the symmetry that lets
every child of the chain be a first-class member with a Phase-N
finalization verdict.

### Journey 3: Author returns for re-evaluation at the DESIGN boundary

A skill author returns to a topic six weeks after a `/scope` run
landed an Accepted DESIGN. New evidence has accumulated and the
author wants to know whether the architecture still holds before
proceeding to `/plan`. They invoke `/scope` against the topic.
Discovery surfaces the existing DESIGN at
`docs/designs/current/DESIGN-<topic>.md` and the absence of a
downstream PLAN. The chain proposal asks the
Re-evaluate / Revise / Bail question at the DESIGN boundary. The
author chooses Re-evaluate; the conversation walks the DESIGN's
load-bearing claims (Decision Drivers, Considered Options, the
chosen approach), confirms they still hold, and `/scope` writes
`DECISION-design-<topic>-re-evaluation-<date>.md` referencing the
existing DESIGN by path. The chain does not re-author the DESIGN
and does not proceed to `/plan`. The existing Accepted DESIGN
remains the live artifact.

This journey validates the second re-evaluation boundary that
`/charter` doesn't have. It also exercises the chain-level
discipline-vs-artifact decoupling at the tactical altitude: the
author asked a settled-architecture question, the chain answered it
durably with a Decision Record, and no redundant DESIGN revision
landed.

### Journey 4: Mid-chain abandonment forcing materialization

A skill author starts a `/scope` run on a hard feature. `/brief`
runs and lands an Accepted BRIEF; `/prd` enters its discover phase
and gathers context. Before the PRD draft is complete, the author
switches to a different task, closes the session, and doesn't
return for a week. When they re-open Claude Code and tell `/scope`
to wrap up the tactical conversation as it stands — or when the
resume ladder detects the partial state on its own and asks whether
to continue, bail, or wrap up — the chain does not abandon the work
as evidence-only files in `wip/prd_<topic>_*`. Instead, `/scope`
forces `/prd` (the most-recently-running child) to materialize its
artifact even if its own decision rule would have left the work as
evidence. The tactical conversation ends at a Draft PRD
(force-materialized from the partial state), with a Status block
noting it was abandonment-forced rather than full-run. The chain
leaves a review surface no matter how it ended.

This journey validates the third exit path at the tactical altitude.
It enforces the terminal-artifact contract in the case the contract
is weakest under: interrupted, half-finished, low-information
tactical work. Without abandonment-forced materialization, the
contract holds only for runs the author completes, which is exactly
the wrong shape.

### Journey 5: Reviewer redirects mid-chain via manual fallback

A reviewer, reading a Draft PRD produced by an earlier `/scope`
run whose Acceptance Criteria pre-suppose design decisions that
haven't been made yet, invokes `/prd` directly outside `/scope`
against the existing Draft PRD path with the tightened framing as
the input. `/prd`
runs as a standalone child the way it always has — phased
authoring, jury review, finalization — and produces a revised Draft
at the same path. `/scope` does not interfere with the manual
re-invocation. When the author later resumes `/scope` on the topic
and the resume ladder notices the PRD has been edited outside the
chain, the skill warns that any downstream DESIGN may be stale
relative to the revised PRD but does not act on the staleness. The
author decides whether to re-run `/design` or accept the existing
DESIGN as still-valid.

This journey validates that manual fallback is first-class
steady-state capability rather than a workaround. Authors and
reviewers retain full control over the tactical chain at any
altitude; `/scope` provides discipline without becoming a
bottleneck. The parent-skill pattern's R13 manual-fallback
non-interference rule stays compatible with the reviewer already
knowing the chain by hand and stepping outside it when the
situation warrants.

## Scope Boundary

This brief, and the downstream PRD it points at, cover the `/scope`
parent skill as a loadable plain-English SKILL.md, plus the pattern-
level edits the tactical chain's asymmetries motivate.

The scope holds the following inside:

- **The `/scope` SKILL.md** following the existing parent-skill
  template established by `/charter`: input modes, execution-mode
  flag parsing, topic-slug constraint, workflow phases diagram,
  resume logic ladder, phase execution list, reference files table.
- **The four delegation contracts at the `/scope` → child
  interfaces** (`/brief`, `/prd`, `/design`, `/plan`), including
  inputs, outputs, conditionality rules, and review-halt behavior.
  The gate vocabulary covers Feeder-EITHER signal for `/brief`,
  Mandatory-with-auto-skip for `/prd`, shape-dependent for
  `/design`, and ALWAYS-with-terminal-semantics for `/plan`.
- **The three exit paths** (full-run at PLAN, re-evaluation
  Decision Record at PRD-boundary or DESIGN-boundary,
  abandonment-forced materialization) as first-class skill
  behavior. The two re-evaluation boundaries get distinct Decision
  Record sub-shapes; both inherit from the pattern's re-evaluation
  template with PRD- and DESIGN-specific load-bearing-claim walks.
- **The resume ladder across four child boundaries**, including
  status-aware re-entry against a PLAN at three statuses
  (Draft, Active, Done), DESIGN's directory-move lifecycle
  (`docs/designs/` versus `docs/designs/current/`), and
  partial-child-run detection for each of the four children's
  `wip/` artifacts.
- **The pattern-level edits the tactical chain's asymmetries
  motivate.** Specifically: the fourth gate type
  (Mandatory-with-auto-skip) lands in
  `references/parent-skill-pattern.md` as a new gate vocabulary
  entry; a new top-level reference
  `references/parent-skill-worktree-discipline.md` lands as
  shared infrastructure both `/charter` and `/scope` cite; the
  L9 PRD pattern-level requirement tagging convention gets
  reclassified from "untapped learning" to required convention.
  The downstream PRD enumerates each pattern-level edit as a
  requirement.
- **Phase-N Reject finalization contracts on `/prd` and `/design`
  as `/scope` prerequisites.** Preserving the rejection sub-shape
  symmetry across both parents forces upstream contract work on
  the two children that currently lack Phase-5 Reject verdicts.
  The downstream PRD scopes the contract extensions; the design
  doc enumerates the implementation. Substantial work but the
  only path that keeps the pattern's exit-shape inventory uniform
  across parents.
- **The shared design doc**, currently named
  `DESIGN-shirabe-explore-split.md` on the roadmap, renamed to
  `DESIGN-shirabe-scope-skill.md` for parallelism with the
  per-parent designs (`DESIGN-shirabe-charter-skill.md`,
  `DESIGN-shirabe-progression-authoring.md`). The relevant
  upstream roadmap entry gets updated to reflect that the
  discover/converge engine consumption is via cross-skill
  pointing into
  `skills/explore/references/phases/{phase-2-discover,phase-3-converge}.md`
  rather than engine extraction.
- **Workspace and shirabe CLAUDE.md updates** documenting
  `/scope`'s entry triggers and the tactical-chain entry section,
  mirroring `/charter`'s Strategic Chain Entry section.
- **Manual-redirect workflow as a first-class steady-state
  surface**, authored as explicitly as the parent-driven workflow.
  The R13 manual-fallback non-interference rule applies to all
  four child boundaries.
- **An eval suite at `skills/scope/evals/evals.json`** with
  scenarios covering each gate, each exit path, both resume
  re-entry surfaces, and the manual-fallback case.

The scope explicitly excludes:

- **The `/work-on` migration into the parent-skill pattern.**
  Separate feature; depends on amplifier-layer workflow-composition
  substrate that `/scope` does not require for its own ship.
  `/scope` ratifies the pattern for `/work-on`; the migration
  itself is downstream.
- **The review-time redirect mechanism.** Manual fallback is
  first-class by design; the automatic-redirect substrate is
  amplifier-layer work and is not a prerequisite for `/scope`.
- **Pattern-ergonomics tightening.** Several `/charter`-
  retrospective items defer to follow-up work explicitly (single-pr
  value-gated heuristic from L1, `ci_outcome` semantics from L6,
  reviewer coverage categories from L10, Track B amplifier-layer
  observations). The cascading decisions this BRIEF cites are the
  v1-cheap fold opportunities only.
- **Re-litigating pattern invariants I-1 through I-7 at the
  abstract level.** The pattern's seven semantic invariants stand
  as `/charter` ratified them; `/scope` adds gate vocabulary and
  one new reference but does not edit the invariants.
- **The amplifier-layer workflow substrate.** The migration into
  workflow-composition infrastructure is downstream; `/scope`
  ships against current shirabe patterns (wip/-based intermediates,
  plain-English phase prose).
- **The niwa workspace context surface.** `/scope` uses current
  CLAUDE.md visibility detection; substrate cleanup is unrelated.
- **Migration of existing tactical-progression artifacts.**
  `/scope` adds a parent layer without renaming or restructuring
  the children's artifacts. Existing BRIEF, PRD, DESIGN, PLAN docs
  continue to validate under their existing schemas.
- **Authoring `/brief`, `/prd`, `/design`, or `/plan` skill bodies.**
  `/scope` consumes the four children as they ship today. The only
  child-side work in scope is the Phase-N Reject contract
  extensions to `/prd` and `/design` (named above); any other
  child SKILL.md revisions are separate PRs.

## References

- Brief format precedent: `docs/briefs/BRIEF-shirabe-charter-skill.md`.
- Parent-skill template precedent: `skills/charter/SKILL.md`.
- Parent-skill pattern references the `/scope` body cites verbatim:
  `references/parent-skill-pattern.md`,
  `references/parent-skill-state-schema.md`,
  `references/parent-skill-resume-ladder-template.md`,
  `references/parent-skill-child-inspection.md`.
- Tactical-chain child precedents: `skills/brief/SKILL.md`,
  `skills/prd/SKILL.md`, `skills/design/SKILL.md`,
  `skills/plan/SKILL.md`.
- Discover/converge engine source consumed via cross-skill pointing:
  `skills/explore/references/phases/phase-2-discover.md` and
  `skills/explore/references/phases/phase-3-converge.md`.
- Shared design doc (planned, renamed from
  `DESIGN-shirabe-explore-split.md`):
  `docs/designs/DESIGN-shirabe-scope-skill.md`.
- Cross-repo visibility rules: `references/cross-repo-references.md`.
