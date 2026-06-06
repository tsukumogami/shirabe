---
schema: brief/v1
status: Done
problem: |
  The parent-skill pattern v1 docs (`references/parent-skill-pattern.md`
  plus `/scope` and `/charter` SKILL.md) describe a parent invoking its
  children but never pin down which harness mechanism carries the
  dispatch. An orchestrator reading the current text reaches at least
  three plausible readings (inline Skill-tool, a single general-purpose
  subagent, or a TeamCreate-backed team) and none of them all match
  authorial intent across the chain.
outcome: |
  An orchestrator (human or agent) finishes the pattern docs with one
  unambiguous reading of how a parent skill hands work to a child:
  which harness primitive carries the dispatch, what state is
  established beforehand, what the parent observes mid-run, and what
  it reads back on return — symmetrically across `/scope` and
  `/charter` and all seven children in their respective chains.
---

# BRIEF: shirabe-child-dispatch-contract

## Status

Done

The downstream PRD owns the requirements articulation. The chosen
dispatch mechanism (Skill tool inline, single subagent, TeamCreate
with coordinator-and-peers, or another shape entirely) is deliberately
not decided here — that is downstream PRD/DESIGN territory.

## Problem Statement

The parent-skill pattern v1 documents — `/scope` SKILL.md, `/charter`
SKILL.md, and `references/parent-skill-pattern.md` — describe how a
parent skill walks an author through a chain of children: `/brief`,
`/prd`, `/design`, and `/plan` for the tactical chain under `/scope`;
`/vision`, `/strategy`, and `/roadmap` for the strategic chain under
`/charter`. What these documents do not pin down is the *mechanism* by
which a parent invokes a child. An orchestrator reading them today
cannot tell, from the text alone, which harness primitive carries the
dispatch.

The legibility gap is not a missing sentence — it is a three-way
internal tension across passages that all touch the same handoff:

- **The Team Shape section** of `/scope` SKILL.md states explicitly
  that `/scope` "runs as a single-agent skill in the v1 core layer —
  no team is spawned at the `/scope`-itself layer." Read on its own,
  this rules out team primitives entirely.
- **The Phase 2 Child Invocation step** says invocation goes via "the
  child's existing input mode: `/<child-name> <topic-slug>`." Read
  literally, this points at inline Skill-tool invocation, which is
  shaped like a single-agent call.
- **R19, the Team-Lead Operating Discipline** (semantic invariant I-7
  in `parent-skill-pattern.md`), describes a behavioral protocol —
  sleep-check-nudge, filesystem-evidence-first, terminal exits at
  PASS / FAIL / ESCALATE — that *only makes sense* when something is
  being dispatched and observed asynchronously. The discipline names
  no mechanism; it names a posture.

An orchestrator reading all three reaches at least three different
mechanism choices for child dispatch:

1. **Inline Skill-tool invocation.** The literal reading of "the
   child's existing input mode." The orchestrator hands control to
   the child the same way a user typing `/brief topic` would.
2. **A single general-purpose subagent.** A compromise reading. The
   orchestrator spawns one subagent, hands it the child invocation,
   and watches the artifact path. This is what the orchestrator in
   the run that surfaced this BRIEF reached for, and it is what the
   author later flagged as not matching intent.
3. **A `TeamCreate`-backed team with a coordinator and peer roles.**
   A team-aware reading of R19's I-7 discipline. The orchestrator
   reads the child's declared team shape, spawns a team with that
   shape, assigns a coordinator, and delegates the invocation to the
   coordinator who in turn uses the peers to satisfy the roles the
   child's phases require.

Each reading is internally coherent with at least one of the three
passages. None of them is coherent with all three at once. The
specific choice the orchestrator makes changes what happens during a
child run — whether peer roles are available, whether the team-lead
discipline has anything to observe, whether the parent's R20
file-existence check is reading evidence written by one agent or
many. The choice also changes what a child's `## Team Shape` section
is *for*: a contract the parent reads, or a self-documentation
artifact the child writes for its own internals.

The same ambiguity applies to `/charter` and its strategic chain. The
two parents share the same pattern and the same children-aren't-named
gap, so the legibility problem is pattern-level, not `/scope`-local.
A future third parent — `/work-on` is the obvious candidate — would
hit the same gap unless the contract is named at the pattern layer
rather than inside any one parent's SKILL.md.

The deeper problem is that the pattern's child-dispatch *contract* is
not articulated as a contract. The Team Shape section reads like a
declaration about `/scope`'s own coordination layer; the Phase 2
sentence reads like an interface note for a single phase; the R19
discipline reads like a behavioral spec that assumes the dispatch
mechanism is already known. A reader cannot reconstruct the contract
from these three passages because no passage frames itself as
specifying the dispatch contract. The contract is the thing the docs
are missing, even though each passage gestures at a piece of it.

The consequence shows up at run time. An orchestrator that picks a
mechanism without an explicit contract picks against the author's
intent more often than not, and the discrepancy is not visible until
the author reviews the run output and says "that's not what I meant
by R19." The legibility gap turns into a correctness gap one
orchestrator at a time.

## User Outcome

Once the contract is explicit, an orchestrator (human or agent)
reading the parent-skill pattern v1 docs finishes those docs with one
unambiguous reading of how a parent skill hands work to a child. The
contract names four things every orchestrator should be able to read
off the docs without inference:

- **The dispatch mechanism.** Which harness primitive carries each
  child invocation — and the relationship of that mechanism to the
  child's `## Team Shape` declaration, the parent's single-agent
  shape, and the R19 discipline that governs the in-flight period.
- **The state established before dispatch.** What the parent writes
  (sentinel, state file, worktree-staleness gate output), what the
  child's input mode receives, and what state the child can rely on
  being present when it begins.
- **The observability surface during the run.** What the parent is
  allowed to inspect mid-run (filesystem under `wip/`, child status
  file, messages from a coordinator), and what its team-lead
  discipline does with that surface — including how the discipline's
  PASS/FAIL/ESCALATE terminal exits map onto the chosen mechanism's
  return signal.
- **The hand-back contract on completion.** What the parent reads
  when the child returns (the R20 file-existence check, the durable
  artifact's frontmatter `status:` value, the git blob hash, any
  reject-finalization Decision Record), and what it tears down before
  the next child begins.

The contract reads symmetrically across `/scope` and `/charter` —
both parents implement the same shape, so an orchestrator that
internalized the contract for one already knows the other. The
contract also reads symmetrically across the seven children: each
child's `## Team Shape` section plays the same role in the dispatch,
whether the child is `/brief` or `/strategy` or `/plan`. A future
third parent inherits the contract verbatim rather than re-deriving
it.

A skill author maintaining one of the children knows, from the
contract, what shape their child's `## Team Shape` section must take
to be readable by the parent — and which fields are load-bearing for
the dispatch versus which are internal child documentation. A
reviewer reading a proposed change to dispatch behavior can tell
whether the change is in-scope for the contract (and therefore needs
to land symmetrically) or a per-parent override (and therefore
contained). The contract's boundary is itself legible.

What the outcome explicitly does NOT promise: a particular mechanism
choice. The contract pins down the *contract*; the mechanism is the
PRD/DESIGN's call. The outcome is the same whether the chosen
mechanism is inline Skill-tool, single subagent, `TeamCreate` with
coordinator-and-peers, or another shape entirely — what matters is
that one unambiguous reading replaces today's three.

## User Journeys

Four journeys exercise the gap from distinct entry points. Each names
the user, the trigger that starts the journey, and the outcome shape
the contract should produce.

### Journey 1: Orchestrator agent running `/scope` for the first time

An orchestrator agent (Claude Code, a sub-agent dispatched by another
skill, or any agent reading the shirabe plugin) is asked to run
`/scope <topic>` on behalf of an author. The agent has not run
`/scope` before, so it reads `skills/scope/SKILL.md` end-to-end to
understand the workflow. It reaches the Team Shape section and learns
`/scope` itself is single-agent. It reaches Phase 2 and reads "the
child's existing input mode." It reaches the R19 cross-reference and
follows it to `references/parent-skill-pattern.md`'s Team-Lead
Operating Discipline. The three readings do not converge. The agent
picks one mechanism — today, a single general-purpose subagent is the
most common compromise — invokes `/brief` through it, and continues
through the chain. The author later reviews the run and flags that
the dispatch did not match intent. The contract's job: give this
orchestrator one reading instead of three, so the run matches intent
on the first pass without the author having to correct it.

### Journey 2: Orchestrator agent running `/charter` for the first time

A second orchestrator agent is asked to run `/charter <topic>`. It
reads `skills/charter/SKILL.md` and hits the same gap symmetrically:
a Team Shape section that disclaims peer primitives at the parent
layer, a Phase 2 child-invocation step that points at the child's
input mode, and the same R19 reference to `parent-skill-pattern.md`.
The agent reaches the same fork in the same place for a different
parent. The contract's job: ensure the orchestrator that internalized
the contract from `/scope` reads `/charter` and dispatches its
children — `/vision`, `/strategy`, `/roadmap` — identically. Two
parents must converge on one mechanism by reading the same contract,
not by independent best-effort interpretation.

### Journey 3: Skill author maintaining a child skill

A skill author maintaining one of the seven children — say `/design`
— is reviewing whether the child's `## Team Shape` section still
matches its actual coordination needs. They want to know: is this
section read by the parent at dispatch time, or only by the child for
its own internal use? If the parent reads it, what fields must be
present and well-formed for the dispatch to succeed? Today the author
cannot answer either question from the docs. They guess based on the
shapes other children's Team Shape sections use, and the guess goes
uncorrected until the next parent-skill review surfaces a mismatch.
The contract's job: tell the child-skill author exactly which Team
Shape fields the parent contract depends on, what their valid shapes
are, and what is internal to the child versus part of the dispatch
interface.

### Journey 4: Reviewer evaluating a proposed dispatch-behavior change

A reviewer is evaluating a PR that proposes changing how `/scope`
spawns its children — perhaps tightening the worktree-staleness gate,
adding a new sentinel field, or changing the R20 file-existence check
to also verify the git blob hash. The reviewer needs to know whether
the change is in-scope for the pattern contract (in which case
`/charter` must change symmetrically and the pattern reference must
be updated) or a per-parent override (in which case `/charter` stays
untouched and only `/scope` changes). Today, the reviewer reads the
three passages, sees no contract boundary drawn, and has to make a
judgment call. The contract's job: draw the boundary explicitly so
the reviewer can read the change against it, not against intuition.

## Scope Boundary

This brief, and the downstream PRD it points at, cover making the
parent-skill child-dispatch contract legible. The scope is a
docs-and-references reconciliation across the pattern's v1 surface,
not a substrate change to how parents work.

The scope holds the following inside:

- **An explicit child-dispatch contract section** at the pattern
  layer — most naturally a new section inside
  `references/parent-skill-pattern.md`, but the PRD owns the exact
  shape. The section names the dispatch mechanism, the pre-dispatch
  state, the in-flight observability surface, and the hand-back
  contract — the four outcome elements above — as one unified
  contract rather than three scattered passages.
- **Reconciliation of the three currently-in-tension passages** so
  they read together as a single coherent statement. The Team Shape
  section (or whatever it becomes), the Phase 2 child-invocation
  step, and the R19 / I-7 Team-Lead Operating Discipline must agree
  with each other and with the new contract section. Where today's
  wording overstates or understates, the reconciliation adjusts.
- **Symmetric application across `/scope` and `/charter`.** Both
  parents reference the contract identically. Any per-parent
  override exists in a clearly-named override slot, not in
  contradiction with the contract.
- **The dispatch interface a child's `## Team Shape` section exposes
  to its parent.** Whichever fields the contract reads off the
  child must be named, with their valid shapes, so a child-skill
  author can write a Team Shape section that the parent contract
  understands. The child's internal-only documentation in the same
  section is preserved; the contract just draws the line.
- **A statement of the mechanism choice** — the PRD/DESIGN names
  which harness primitive carries the dispatch (Skill tool inline,
  single subagent, `TeamCreate`-backed team, or another shape).
  This brief takes no position; the downstream artifacts make the
  call. The choice is in-scope for the chain this brief feeds.
- **Updates to all seven child SKILL.md files** to confirm their
  `## Team Shape` sections expose the fields the contract requires.
  Children that already do require no edit; children that don't get
  a section update. Either way, the children become parent-readable.

The scope explicitly excludes:

- **Changing the harness team primitive's substrate.** Whatever
  `TeamCreate`, `SendMessage`, and the team-lead discipline do at
  the harness layer is taken as a given. The contract names which
  of those primitives the dispatch uses; it does not redesign them.
- **The amplifier-layer team-shape declarator.** The pattern's v1
  Team-Shape Declarator section already notes that team-emitting
  parents will declare structured metadata when the amplifier-layer
  substrate ships. This brief does not pull that forward — v1
  prose declarators stay v1.
- **The `/work-on` migration into the parent-skill pattern.**
  `/work-on` is a separate parent that depends on
  workflow-composition substrate that does not exist yet. The
  contract this brief frames *will* apply to `/work-on` when it
  migrates, but the migration itself is downstream feature work.
- **Pattern-invariant renumbering.** The pattern's seven semantic
  invariants (I-1 through I-7) stand as they ratified. The contract
  this brief frames operationalizes I-7 (Active Orchestration) but
  does not change the invariant's wording or add new invariants.
- **Re-litigating which mechanism is "right" against the others at
  the abstract level.** The PRD picks one mechanism with stated
  trade-offs. The brief does not stake out the comparison; the
  decision rationale lives in the design doc.
- **Authoring net-new child skills.** The seven children that exist
  today are the children the contract applies to. New children
  added later inherit the contract; their authoring is not in scope.
- **Migration of existing chain runs in flight.** A `/scope` or
  `/charter` run that pre-dates the contract continues to work as
  it does today. The contract is forward-looking; existing in-flight
  state is not retroactively re-shaped.
- **Editing the workspace or shirabe CLAUDE.md files** to surface
  the contract at the user-facing layer. The contract is internal
  to the pattern's documentation; user-facing CLAUDE.md text is a
  separate concern the PRD may revisit if needed but this BRIEF
  does not commit to.

## References

- Pattern source the contract reconciles:
  `references/parent-skill-pattern.md` (Team-Shape Declarator,
  Team-Lead Operating Discipline / I-7).
- Tactical-chain parent that surfaced the gap:
  `skills/scope/SKILL.md` (Team Shape section, Phase 2 child
  invocation step).
- Strategic-chain parent the contract applies to symmetrically:
  `skills/charter/SKILL.md`.
- Brief-format precedent followed:
  `docs/briefs/BRIEF-shirabe-scope-skill.md` for body structure;
  `references/brief-format.md` for the section matrix.
- The upstream conversation: a triage issue in the shirabe repo
  titled "clarify that /scope spawns a TeamCreate-backed team per
  child dispatch" surfaced the legibility gap. Its "Suggested fix"
  sketches one possible mechanism choice (TeamCreate-per-child);
  this BRIEF deliberately does not adopt it as the answer, leaving
  the choice to the downstream PRD.
