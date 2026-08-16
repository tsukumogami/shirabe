# Crystallize Decision Framework

Reference for evaluating what an exploration reached and where its work goes next.
Loaded by Phase 4 (Crystallize) to score, rank, and recommend.

The step scores two things, in sequence. Stage 1 asks what the exploration *is*:
a competitive landscape write-up, a feasibility answer, a single decision, a
rejection, or a chain. Stage 2 asks, for a chain, which entry point receives it.
The two questions are not comparable quantities, so they do not share a
scoreboard.

## Documentation Purpose

Artifacts capture decisions already made, not only decisions yet to be made.

`wip/` is cleaned before every PR merges. Any decision recorded only in research
files or findings will be permanently lost when the branch closes. If exploration
produced architectural choices, dependency selections, structural decisions, or
design rationale that future contributors need to understand, those must be written
to a permanent document before the branch closes.

The question is not "do we still have something to decide?" — it's "did we decide
something a future contributor needs to know?"

## Candidacy Preconditions

Two arms are governed by a precondition rather than by weight. A precondition is
not a signal: it decides whether the arm is on the board at all. An arm whose
precondition fails is absent from the ranking, absent from the options presented
to the user, and must not be named in the recommendation, not even as a
near-miss.

**`/execute` is a candidate only when a qualifying PLAN exists.** A qualifying
PLAN is a file at `docs/plans/PLAN-*.md`, or any `.md` whose frontmatter carries
`schema: plan/v1`, whose `execution_mode` is `single-pr` or `coordinated`. A
`multi-pr` PLAN does not qualify: `/execute` refuses that mode and directs the
author to `/work-on` one issue at a time. Check the file before scoring stage 2.
No PLAN, or only a `multi-pr` one, and the `/execute` arm does not exist for this
run.

**Competitive analysis is a candidate only in a private repo.** Read the
`## Visibility` section of `wip/explore_<topic>_scope.md`, which Phase 0 wrote.
`Public` removes the category from stage 1 entirely. This is a precondition and
not an anti-signal because a demoted category is still offered as a selectable
alternative, and choosing it reaches a handler that refuses it. Removing it from
candidacy is what keeps it from being offered.

## Stage 1: What the Exploration Is

Five categories. Four are terminal outcomes that no chain owns; the fifth is a
chain. "A chain" is scored like the rest rather than treated as the residual, so
the demotion rule applies to it symmetrically. As a residual it could never be
demoted below a clean terminal outcome, which would privilege it on every run.

### Rejection Record

Produces a permanent rejection artifact at `docs/decisions/`. `/explore` authors
it; Phase 5 has the arm.

| Signals | Anti-Signals |
|---------|-------------|
| Exploration reached an active rejection conclusion (not lead exhaustion — there's positive rejection evidence) | Leads ran out without a conclusion (no positive rejection evidence) |
| Adversarial lead returned high or medium confidence evidence of absent or rejected demand on multiple demand-validation questions | Rejection reasoning is already documented publicly (reference existing docs) |
| Specific citable blockers or failure modes were identified with citations | Low-stakes decision unlikely to resurface (close with comment) |
| Re-proposal risk is high (common request, non-obvious rejection reasoning) | |
| Investigation was multi-round or adversarial | |

### Spike Report

Produces a feasibility assessment with findings and recommendation. `/explore`
authors it; Phase 5 has the arm.

| Signals | Anti-Signals |
|---------|-------------|
| The core question is "can we do this?" (feasibility) | The question is "should we do this?" or "what should we build?" |
| Technical uncertainty blocks a decision | The approach is known; only sequencing remains |
| A time-boxed investigation produced concrete findings | Exploration was broad, not focused on a specific technical risk |
| Specific technical risks were identified and tested | |

### Decision Record

Produces a permanent record of a single architectural or process decision.
Routes to `/decision`.

| Signals | Anti-Signals |
|---------|-------------|
| A single decision with clear options was evaluated | Multiple interrelated decisions came with work attached |
| The core question is "which option and why?" | The decision is low-stakes and unlikely to be questioned later |
| Future contributors will need to understand why this choice was made | No meaningful trade-offs between options |
| Exploration compared specific alternatives with trade-offs | |

### Competitive Analysis

Produces a structured analysis of the competitive landscape. Routes to `/comp`,
which drives the jury and the lifecycle transition. Candidate in private repos
only; see Candidacy Preconditions.

| Signals | Anti-Signals |
|---------|-------------|
| The core question is "what exists in this space?" | Competitive landscape is already well-understood |
| Market or ecosystem understanding drove the exploration | Exploration focused on internal technical decisions, not the external landscape |
| Multiple alternatives were evaluated with trade-offs | |
| Findings center on external tools, products, or approaches | |

### A Chain

The exploration produced work. Stage 2 decides where that work enters.

| Signals | Anti-Signals |
|---------|-------------|
| Exploration converged on something someone will build | Nothing was left to build: the exploration answered a question and closed it |
| Requirements, architecture, or sequencing questions remain open | The whole output is one choice between named options |
| Decisions made during exploration need a durable home and downstream work | The output is a feasibility verdict nobody has committed to acting on |
| Multiple stakeholders need alignment on what to build | Findings center on external products rather than on something to build |
| A scope boundary emerged, not just an answer | The conclusion is that the work should not happen |
| The core question is "what do we build, and how?" | |

## Stage 2: Where the Chain Starts

Four entry points. Stage 2 runs when stage 1 returns a chain, and also when
stage 1's margin is within one point, so a near-tie presents both. `/execute` is
on this board only when its precondition holds.

### File an Issue

No document produced here. The work is filed and picked up directly; the stated
next step is `/work-on`, which accepts an issue number.

| Signals | Anti-Signals |
|---------|-------------|
| Simple enough to act on directly | Others need documentation to build from |
| One person can implement without coordination | Multiple people will work on this |
| Exploration confirmed existing understanding without making new decisions | Any architectural, dependency, or structural decisions were made during exploration |
| Short exploration (1 round) with high user confidence | Scope was debated across rounds |
| The right next step is "just do it" | |

### `/charter`

The strategic chain. Routes to `/charter`, which runs its own children and
produces a durable strategy plus a sequenced roadmap.

| Signals | Anti-Signals |
|---------|-------------|
| Project doesn't exist yet (no repo, no codebase) | The project already exists and the question is about its next feature |
| Exploration centered on "should we build this?" | The work is one bounded feature, however large |
| Org fit or strategic alignment was the core question | Specific users and needs are already identified and uncontested |
| Thesis validation was the exploration's primary output | No sequencing question: the items have no order that affects delivery |
| Multiple fundamentally different project directions viable | |
| Target audience not yet well-defined | |
| Exploration produced strategic justification arguments | |
| Multiple features or initiatives need ordering | |
| Dependencies between work items affect delivery order | |
| The core question is "what order do we build in across features?" | |

### `/scope`

The tactical chain. Routes to `/scope`, which runs its own children and produces
a PLAN as its terminal artifact.

| Signals | Anti-Signals |
|---------|-------------|
| A single coherent feature emerged from exploration | Multiple independent features whose order affects delivery |
| Requirements are unclear or contested | One person can act on this without a written contract |
| Multiple stakeholders need alignment on what to build | A qualifying PLAN already covers this work |
| User stories or acceptance criteria are missing | The exploration produced no work: a landscape, a feasibility answer, or one decision |
| What to build is clear, but how to build it is not | |
| Technical decisions need to be made between approaches | |
| Architecture, integration, or system design questions remain | |
| Exploration surfaced multiple viable implementation paths | |
| Architectural or technical decisions were made during exploration that should be on record | |
| The core question is "what should we build, and how?" | |

### `/execute`

Implementation altitude. Routes to `/execute` with the PLAN path. Candidate only
when a qualifying PLAN exists; see Candidacy Preconditions.

| Signals | Anti-Signals |
|---------|-------------|
| The qualifying PLAN covers this topic and exploration confirmed it still holds | Technical approach is still debated |
| Exploration confirmed scope and approach and the remaining work is execution | Open architectural or requirements decisions need to be made first |
| The core question is "should we start building this now?" | Exploration changed the scope the PLAN assumes |
| The PLAN's issues are the work, all of them | Only one issue out of the PLAN is in play |

## Deferred Types

The following type is recognized by the framework but not produced by /explore.
If it fits best, inform the user and suggest the closest available alternative.

| Type | Core Question | Closest Available Alternative |
|------|---------------|-------------------------------|
| Prototype | Does this work? (proof-of-concept) | File an issue and start building through `/work-on` |

When a deferred type fits best, explain:
1. Why the deferred type matches the findings
2. That /explore doesn't produce it yet
3. Which available alternative comes closest and why
4. Offer to produce a rough outline the user can develop manually

## Evaluation Procedure

Run these steps against the accumulated findings from all discover-converge rounds.

### Step 1: Establish Candidacy

Before any scoring, evaluate both preconditions from the Candidacy Preconditions
section. Record which arms are on the board and which are not. An arm that failed
its precondition takes no further part in this run.

### Step 2: Score Stage 1

For each candidate stage-1 category (Rejection Record, Spike Report, Decision
Record, Competitive Analysis, A Chain):
- Count the number of signals present in the findings
- Count the number of anti-signals present in the findings
- Score = signals present minus anti-signals present

Also check the deferred type. If it scores highest, handle it per the Deferred
Types section before continuing.

### Step 3: Rank and Demote

Rank stage-1 categories by score, highest first.

**Demotion rule:** Any category with one or more anti-signals present is demoted
below all categories without anti-signals, regardless of its raw score. A category
scoring 3 with 1 anti-signal ranks below a category scoring 1 with 0 anti-signals.
This applies to "a chain" the same as to the four terminal outcomes.

### Step 4: Apply Stage-1 Tiebreakers

When the top two categories are tied or within 1 point after demotion:

**A chain vs Rejection Record:** Overall conclusion "proceed" -> a chain. "Don't
proceed" -> Rejection Record.

**A chain vs Spike Report:** Did the exploration answer "can we?" and stop, or did
the answer commit someone to building? Answered and stopped -> Spike Report.
Committed -> a chain.

**A chain vs Decision Record:** Is the exploration's entire output one choice
between named options? Yes -> Decision Record. If the choice is one input among
several that a build still needs -> a chain, which records the choice as it goes.

### Step 5: Decide Whether Stage 2 Runs

Run stage 2 if either holds:
- "A chain" is the top-ranked stage-1 category
- "A chain" is within 1 point of the top-ranked category after demotion

The second condition is deliberate. A stage-1 error is unrecoverable at stage 2:
an exploration wrongly scored as a terminal outcome never reaches the entry points
at all. Running stage 2 on a near-tie presents both, so the author sees the entry
point the close call nearly cost them.

If neither holds, the recommendation is the terminal outcome. Stop here.

### Step 6: Score Stage 2

For each candidate entry point (File an Issue, `/charter`, `/scope`, and
`/execute` when its precondition holds), count signals and anti-signals and
score the same way. Rank, then apply the same demotion rule.

### Step 7: Apply Stage-2 Tiebreakers

When the top two entry points are tied or within 1 point after demotion:

**`/scope` vs File an issue:** Can one person act on this without a written
contract? Yes -> file an issue. No -> `/scope`. A short exploration (1 round)
with a confident author leans toward filing; scope debated across rounds, or
several stakeholders, leans toward `/scope`.

**`/charter` vs File an issue:** Does anyone else need the strategic argument?
Yes -> `/charter`. No -> file an issue.

**`/charter` vs `/scope`, the existence question:** Does the project exist yet?
No -> `/charter`. Yes -> `/scope`.

**`/charter` vs `/scope`, the multi-feature boundary:** Does the work span more
than one feature whose order affects delivery? Yes -> `/charter`, whose terminal
artifact is a sequenced roadmap. One bounded feature, however large -> `/scope`.
The size of the feature is not the test; the number of separately-sequenced
features is.

**`/scope` vs `/execute`:** The question is whether an upstream artifact already
exists, and the answer's consequence is narrow. A qualifying PLAN unlocks
`/execute`, and that is a precondition rather than a tiebreaker input. Everything
else on disk unlocks nothing: **a PRD or a DESIGN covering this topic is not a
reason to enter the chain below `/scope`.** The chain runs whole and reduces per
hop afterward, against artifacts that exist. Reading an existing upstream document
as permission to skip ahead is the most likely route back to entry-altitude
selection, which this framework does not do.

**`/execute` vs File an issue:** Is the whole PLAN the work, or one issue out of
it? The whole PLAN -> `/execute`. One issue -> file the issue, next step
`/work-on`.

### Step 8: Insufficient-Signal Fallback

If no stage-1 category scores above 0 after demotion, the findings are too vague
to recommend anything. Instead of forcing a choice:

1. Tell the user the findings don't clearly point anywhere
2. Identify which signals are missing and what questions would surface them
3. Recommend another discover-converge round with specific leads targeting the gaps
4. Return to Phase 2 (Discover) with the new leads

This prevents premature commitment when exploration hasn't gone deep enough.

If stage 1 returned a chain but no entry point scores above 0 at stage 2, don't
loop back. The exploration established that work exists; only its altitude is
unsettled. Present the candidate entry points with what each would cost and let
the author choose.

## Recommendation Format

Present the Crystallize output to the user with three parts.

### 1. Recommendation

For a terminal outcome, state the category and list which signals matched. For a
chain, state the entry point and the exact command to run. Be specific: reference
actual findings from the exploration, not generic descriptions.

Example:
> **Recommended: `/scope`**
> Your exploration converged on one feature, the version resolver, and surfaced
> three competing approaches for it. Requirements are partly contested (the CLI
> flags are settled, the provider fallback order is not) and the architectural
> question is open. Run `/scope version-resolver`.

### 2. Alternatives

List the other candidates that partially fit. For each, note which signals matched
and which anti-signals or missing signals caused it to rank lower. Never list an
arm that failed its precondition.

Example:
> **Alternative: file an issue** -- Ranked lower because three implementation
> approaches need comparison before committing. Direct implementation risks
> choosing the wrong one.
>
> **Alternative: `/charter`** -- Ranked lower because the work is one feature, not
> a set of features that need ordering.

### 3. Deferred Types (if applicable)

If the deferred type scored well, note it separately with the suggested workaround
from the Deferred Types section.

## Disambiguation Rules

These rules handle common ambiguous patterns that raw scoring doesn't resolve
cleanly.

**Exploration surfaced both requirement gaps AND technical questions.** Both are
inside one chain, so there's nothing to choose between. Recommend `/scope`; the
chain writes the requirements before the architecture, in that order, and reduces
per hop where a step turns out not to be needed.

**Exploration was deep but the user wants to act fast.** Urgency doesn't override
the need to capture decisions. If exploration made architectural or dependency
choices, those need a durable home regardless of how quickly the user wants to
start coding. What can be compressed is each artifact's size, and that
compression happens inside the chain, per hop, against a document that exists.
The right response is "run the chain and keep each document lean," not "skip
ahead."

**Exploration surfaced both strategic justification AND feature requirements.**
`/charter` comes first. Strategic justification must be accepted before
requirements are worth writing, and the strategic chain's roadmap is what feeds
the tactical one.

**The work is understood well enough to break into issues, but no PLAN exists.**
`/execute` is not a candidate, so this is not the boundary it looks like. Route
to `/scope`, whose terminal artifact is the PLAN the author is describing. The
chain's own per-hop reduction is what keeps a well-understood feature from paying
for four full documents.

**Multiple feasibility-shaped outcomes match.** If findings point to a spike
report AND a prototype, suggest filing an issue and starting to build. The
fastest path to answering "can we?" is usually trying.

**Findings contradict across rounds.** If early rounds pointed one way but later
rounds shifted direction, weight the later rounds more heavily. The user narrowed
focus during Converge phases, and later findings reflect that refined
understanding.
