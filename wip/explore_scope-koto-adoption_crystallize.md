# Crystallize Decision: scope-koto-adoption

## Chosen Type

A chain, entering at `/scope`. Command: `/scope scope-koto-adoption`.

Confirmed by the author.

## Candidacy

- **`/execute`: not a candidate.** The only PLAN on disk is
  `docs/plans/PLAN-work-on-friction-fixes.md`, whose `execution_mode` is
  `multi-pr`. That mode does not qualify -- `/execute` refuses it -- and the
  document is off-topic besides. The arm takes no part in this run.
- **Competitive analysis: not a candidate.** `## Visibility` in the scope file
  reads `Public`, which removes the category from stage 1 entirely.

## Rationale

The exploration converged on one bounded feature: express `/scope` as a koto
phase-substrate workflow, carrying the framing rewrite inside the same effort
rather than beside it. What to build is settled. How to build it is not, and the
open questions are architectural rather than clerical -- whether `/scope` keeps
its 255-line `wip/` state schema alongside a koto session or folds one into the
other, where a machine-local koto session sits relative to git when `/scope` has
no PR mid-chain to anchor resume on, whether the 360-line artifact-status resume
ladder survives, and which passages belong in whatever the agent reads before
state 1 versus in a state's `<!-- details -->`.

The exploration also decided things that a future contributor needs and that
`wip/` cleanup would destroy: four falsified premises the reframe was stated
with, the four-category premise/verdict/bound/obituary cut that governs where
every passage lands, the gating strength statement amended twice against
verified source behaviour, and the author's two rulings on the skip route and
the audit surface. Those need a durable home, and the chain gives them one as it
goes.

## Stage 1 Evidence

### A Chain

**Signals present (5):**

- *Exploration converged on something someone will build.* A koto template for
  `/scope`, a rewrite of `SKILL.md`'s purpose-bearing sections, an appended
  amendment on `DESIGN-scope-consolidation-over-skipping.md`, and edits to three
  by-title references.
- *Requirements, architecture, or sequencing questions remain open.* Two state
  stores or one; koto session state relative to git; the resume ladder; the
  `<!-- details -->` versus pointer-to-file choice; whether a single-pr `/scope`
  run has a PR at all.
- *Decisions made during exploration need a durable home and downstream work.*
  Enumerated in the Rationale above. All of them currently live only in `wip/`.
- *A scope boundary emerged, not just an answer.* The phase substrate rather
  than materialization; the framing content inside the effort rather than
  superseded by it; `/charter` investigated and not committed; context economy
  withdrawn as a reason; Phase 3 ruled out as a place to intervene.
- *The core question is "what do we build, and how?"* The exploration opened on
  feasibility and closed on design.

**Anti-signals checked (0):**

- *Nothing was left to build* -- not present; the work is named and committed to.
- *The whole output is one choice between named options* -- not present; the
  shape choice is one input among several.
- *The output is a feasibility verdict nobody has committed to acting on* -- not
  present; the author confirmed the chain.
- *Findings center on external products* -- not present.
- *The conclusion is that the work should not happen* -- not present.

**Score: 5, no anti-signals.**

### Rejection Record

**Signals present (2):** re-proposal risk is genuinely high -- three premises
this exploration falsified (koto isolates children, the sourcing property is
reachable by changing the binding, koto reduces resident context) are exactly
the kind of claim that returns; and the investigation was multi-round and
adversarial.

**Anti-signals checked (0):** leads did not run out, the reasoning is not
already documented, and the matter is not low-stakes.

**Score: 2, no anti-signals.** Loses the tiebreak.

### Spike Report

**Signals present (4):** the core question was feasibility-shaped ("can a
conversational parent be a koto workflow?"); technical uncertainty blocked a
decision; a bounded investigation produced concrete findings; and specific
technical risks were identified and tested empirically -- the gate bypasses, the
pass-through trap, and the exit veto were all verified by running koto rather
than by reading it.

**Anti-signals present (2):** the question was also "should we do this?", and
round 1 was broad across seven leads rather than focused on one technical risk.

**Score: 2, demoted.**

### Decision Record

**Signals present (3):** a decision with clear options was evaluated (phase
substrate versus materialized binding); future contributors need to understand
why; and specific alternatives were compared with trade-offs.

**Anti-signals present (1):** multiple interrelated decisions came with work
attached -- the skip route, the audit surface, the content placement, and the
template authoring are four decisions, not one.

**Score: 2, demoted.**

### Ranking

- A chain: 5
- Rejection Record: 2
- Spike Report: 2 (demoted, 2 anti-signals)
- Decision Record: 2 (demoted, 1 anti-signal)
- Competitive Analysis: not a candidate (Public)

## Stage 2 Evidence

Stage 2 ran because "a chain" was the top-ranked stage-1 category.

### `/scope`

**Signals present (9):**

- *A single coherent feature emerged.* One change to one skill, with its
  content rewrite inside it.
- *Requirements are unclear or contested.* Two were contested and settled this
  round; the rest are unwritten.
- *User stories or acceptance criteria are missing.* Entirely.
- *What to build is clear, but how to build it is not.* The defining condition
  here.
- *Technical decisions need to be made between approaches.* State store,
  resume anchoring, disclosure mechanism.
- *Architecture, integration, or system design questions remain.* The template's
  state layout and its reconciliation with the existing resume ladder.
- *Exploration surfaced multiple viable implementation paths.* Two shapes at the
  top level, several sub-paths within the chosen one.
- *Architectural or technical decisions were made during exploration that should
  be on record.* The load-bearing signal for this run.
- *The core question is "what should we build, and how?"*

**Anti-signals checked (0):** not multiple independent features whose order
affects delivery; one person cannot act on this without a written contract; no
qualifying PLAN covers the work; the exploration produced work rather than a
landscape or a verdict.

**Score: 9, no anti-signals.**

### File an Issue

**Signals present (0).** Not simple enough to act on directly; the exploration
did not merely confirm existing understanding, it falsified four premises; it
ran two rounds rather than one; and "just do it" is not the right next step.

**Anti-signals present (3):** others need documentation to build from;
architectural and structural decisions were made during exploration; scope was
debated across rounds.

**Score: -3, demoted.**

### `/charter`

**Signals present (0).** The project exists, no thesis validation was involved,
no strategic justification was produced, and no set of features needs ordering.

**Anti-signals present (4):** the project already exists and the question is
about its next feature; the work is one bounded feature however large; the users
and needs are identified and uncontested; there is no cross-feature sequencing
question.

**Score: -4, demoted.**

### Ranking

- `/scope`: 9
- File an issue: -3 (demoted)
- `/charter`: -4 (demoted)
- `/execute`: not a candidate (only PLAN is `multi-pr`)

## Tiebreakers Applied

- **A chain vs Rejection Record.** Applied because the two were the only
  categories without anti-signals, though the margin was 3 rather than 1. The
  rule reads: overall conclusion "proceed" gives a chain. The conclusion is
  proceed -- narrowly, and with three premises withdrawn, but proceed. A chain.
- No stage-2 tiebreaker was needed. The margin between `/scope` and the next
  entry point is twelve points.

## Alternatives Considered

- **Rejection Record.** The only real contender, and it ranked on a genuine
  signal: this exploration falsified three claims with high re-proposal risk,
  and recording them durably has independent value. It lost because the
  exploration concluded proceed, and a rejection record would leave the work it
  commits to without a home. The falsified premises are not lost -- they are
  carried into the chain's own artifacts, which is where the framework says
  decisions made during exploration belong.
- **File an issue.** Ranked lowest of the entry points on anti-signals rather
  than on size. The work might fit one person, but it made architectural
  decisions across two rounds that need a written contract, and it touches a
  shared pattern two skills bind to.
- **`/charter`.** Ranked lower because this is one bounded feature inside a
  project that exists, with no cross-feature sequencing question. The strategic
  chain has nothing to add.

## Deferred Type

**Prototype** was checked and does not fit. The exploration's uncertainty was
never "does this work?" in a way a proof-of-concept would settle -- and where it
was, the research agents already settled it by running koto directly: a 5-state
child-free template compiled and ran to terminal, the pass-through trap was
reproduced against two shipped templates, and the exit veto was confirmed with
`advanced: false` on a `full-run` claim against a failing gate.

## Author Rulings Carried Forward

Recorded here because Phase 5 hands them to `/scope` and `wip/` does not
survive.

- **The gating value counts.** A trace the agent did not author is different in
  kind from a post-hoc checker: no checker runs, nothing grades the agent, and a
  bypass is a deliberate command carrying a rationale rather than silence.
- **Hop states carry an ungated skip route; the binding goes on the exit.**
  `chain_skipped:` semantics and the re-entry protection built on them survive.
  A run that skipped every hop can still reach `finalize`; what it cannot do is
  claim `full-run` there.
- **The machine-local `/workflows` render is the audit surface.** Copying into a
  PR body was declined because it reintroduces the agent as the copier, making
  the copy forgeable where the original was not. A forgeable durable artifact is
  worse than an unforgeable local one. Accepted cost: the trace does not leave
  the machine.
- **#331 is re-scoped to the koto framing** rather than kept as the prose bug
  with a separate adoption issue. The prose work is inside the adoption rather
  than beside it, and the issue's diagnosis survives -- only its two proposed
  remedies were falsified.
