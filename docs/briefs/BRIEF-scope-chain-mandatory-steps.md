---
schema: brief/v1
status: Accepted
problem: |
  The corpus gives two answers to whether a tactical-chain step is optional.
  /execute states the post-#302 model and /scope states it and then contradicts
  itself; /explore, the shared parent-skill pattern both parents inherit, and
  /scope's eval suite still state the model #302 replaced. Four surfaces in all,
  and an author meets a stale one first.
outcome: |
  An author never decides which chain step to start at. They choose an entry
  point, the chain runs whole, and what did not earn its keep is folded after
  the fact. Every surface describing chain shape says the same thing.
motivating_context: |
  Surfaced while reading the corpus after #302 shipped. /explore still picks a
  step inside /scope to start from, and /scope still opens by asking which
  steps will run. Investigation found the friction is real, sits in four places
  rather than two, and one of them is a shipped acceptance criterion that was
  never met.
---

# BRIEF: Chain Steps Are Mandatory

## Status

Accepted

Framed from the `/explore` run on this branch. The two questions this brief
deferred — what "a shorter chain" means to an author now, and whether the
abandonment exit must stay reachable from the author's own flow — are closed in
the downstream PRD's Decisions and Trade-offs section. The brief stops at the
boundary: which surfaces state the wrong model and what an author should
experience instead. Which prose replaces each one, and in what order, is PRD and
DESIGN work.

Edited in place after the PRD landed. The original framing said the chain
proposal's question mark was what had to go. Requirements-altitude research
found the opposite: the proposal's two remaining options each do work the
default cannot reach, and one of them does not function as documented. The
Problem Statement and User Outcome above carry the corrected reading; the
problem this brief frames is unchanged.

## Problem Statement

Shirabe's tactical chain used to let a step be skipped because someone judged
its document not worth writing. Issue #280 argued that judgment is the wrong
shape, because whether a document carried anything can only be decided against a
document that exists, and #302 replaced it. `/scope` now runs BRIEF → PRD →
DESIGN → PLAN on every invocation and reduces the set afterward, per hop,
against two bodies that exist.

The corpus did not finish moving. Four surfaces still describe the world before
#302, and they are not footnotes. They are the surfaces an author touches first.

`/explore` is the entry point for "I don't know what I need," and it answers
that question by naming a chain step. Its routing tables and its ten-type
crystallize framework send authors to `/prd`, `/design`, `/plan`, `/vision`, and
`/roadmap`, entering the tactical chain at three different depths and the
strategic chain at two. It has no vocabulary for BRIEF or STRATEGY at all, so
two of those five entries structurally skip an altitude; its roadmap handler
already carries a warning that its own handoff produces a ROADMAP whose missing
upstream is a direction violation nothing downstream catches. `/scope`,
`/charter`, and `/execute` are not named anywhere in the skill. And it does not
merely route: four of its produce handlers write committed documents, including
a DESIGN skeleton.

`/scope` states the current model in its own prose and then contradicts itself
beside it. Phase 1 says `planned_chain:` is constant and that no starting
altitude is choosable, and then gives a redirect to invoke `/design` or `/plan`
directly for "a shorter chain" — which a later section of that same file calls
an escape hatch from a constraint that no longer exists. The chain proposal that
ends Phase 1 justifies offering no shorter chain on the ground that `/scope`
cannot produce one, which consolidation falsified. And the proposal's own bail
option, documented as the author's only stop before the first child writes,
cannot execute either of its branches.

The shared parent-skill pattern, which both parents inherit from, never states
the model at all. It carries no mention of consolidation, absorption, or whether
a document earned its keep. It is the source of the chain-proposal prompt both
parents emit, and its ALWAYS gate carries a declination clause that is the only
place in the corpus authorizing a step to be dropped before its artifact exists.
Its `chain_skipped[].reason` vocabulary is open free text, which the two parents
close incompatibly: `/scope` forbids a worth-producing reason from ever
appearing, and `/charter` uses one as its canonical example.

The eval suite is the only executable statement of what `/scope` should do, and
it grades the retired model. Scenario `durable-artifact-floor-is-structural`
asserts a floor the skill now denies having; `consolidation-keep-at-unmapped-hop`
requires deriving absorbability from per-type required-section lists, which the
skill names as the defining violation. This is not newly discovered drift. It is
an unmet requirement of #302's own PRD, with two unchecked acceptance criteria,
sitting behind documents at terminal status. Nothing caught it because
the eval suite runs on a weekly schedule rather than on pull requests, and the
pull-request check only counts that eval files are non-empty.

The cost is not cosmetic. An author who reads `/explore` first is told to pick
an artifact type, which is the decision #302 removed. A maintainer who reads the
pattern document finds no statement of the model and a clause that sanctions its
opposite. An agent optimizing against the eval suite is pulled backward toward
the model the skill retired.

## User Outcome

An author never has to decide which chain step to start at, and never reads two
answers about whether they could have.

Reaching shirabe without knowing what they need, they get routed to a place to
start — file an issue, open the strategic chain, open the tactical chain, or
execute an existing plan — rather than to a step inside one of those chains.
The router asks which conversation they are having, not which document they
want. Nothing they are handed presumes an altitude they did not choose, and no
artifact is authored on their behalf by the skill that was supposed to route
them.

Entering the tactical chain, they are told what will run and why each child
fires, and what happens to the documents afterward: the chain runs whole, and
whatever did not earn its keep is folded once it and its successor both exist.
The affordances the proposal offers them do what they claim. They can correct a
framing answer that was wrong, and they can stop before the first child writes.
Neither is advertised as a way to shorten the chain, because neither is.

A maintainer reading the shared pattern to build a third parent finds the model
stated once, in the document both existing parents inherit from, along with what
a skip may legitimately mean. They do not have to reconstruct it from one
parent's local prose and infer that the other parent's canonical example is an
exception rather than the rule.

And the executable statement agrees with the prose. An agent graded by the eval
suite is pulled toward the model the skill actually implements, not away from it.

## User Journeys

### An author who does not know what they need

A contributor has a vague sense that something in the release pipeline is wrong
but cannot say whether it needs requirements, a design, or just a fix. They run
`/explore`. The skill researches, converges, and then routes them to one of four
places to start — not to "write a PRD" or "write a design doc." They enter the
chain at its head, the chain runs whole, and whichever documents turn out to
restate each other are folded afterward. At no point are they asked to predict,
before anything is written, which altitude their work deserves.

### An author entering the tactical chain

An author runs `/scope` on a feature. Before any child fires, they read what
will run: each child, whether re-entry protection is holding it back and why,
what shaped the design decision roster, and the notice about grounding on a
roadmap. Then the chain starts. They are not presented with an option to adjust
a list that cannot change, and not offered a bail whose two branches cannot
execute from where they stand.

### An author who believes the upstream work is unnecessary

An author arrives at `/scope` already convinced the framing and the requirements
are settled, wanting only to talk about architecture, and expecting to be let
past the first two children. `/scope` runs the whole chain anyway and says why:
judging an unwritten BRIEF not worth writing is a judgment about a document that
does not exist. If the BRIEF turns out to do no work the PRD does not, it is
absorbed after both exist. The author gets a coherent answer rather than a
redirect that one paragraph offers and another retires.

### A maintainer building a third parent skill

A maintainer opens `references/parent-skill-pattern.md` to bind a new parent to
the contract. They find the model stated: chain steps are mandatory, reduction
is post-hoc, and here is what a `chain_skipped` reason may legitimately say.
Where a parent may still offer an author a declination, they find it named as
such and distinguished from a gate the parent computes — so they can tell which
of the two they are looking at.

### An agent graded by the eval suite

An agent optimizing against `skills/scope/evals/evals.json` reaches the scenario
that judges a hop the chain kept. It is graded on whether the verdict came from
reading the two documents, which is what the skill does — not on whether it
compared the two types' section lists, which is what the skill names as the
defining violation. Every scenario it meets describes the model the skill
implements, so nothing in the suite pulls it back toward the one that was
retired.

## Scope Boundary

### In

- `/explore`'s routing surface: the artifact-type routing guide, the quick
  decision table, the complexity-based routing table, the detection algorithm,
  the ten-type crystallize framework and its tiebreakers, and the phase-5
  produce handlers — replaced by a router over chain entry points.
- `/explore`'s durable-document authoring. The skill stops writing committed
  artifacts on an author's behalf; the wip handoff artifact that lets a
  downstream skill skip its own scoping phase survives.
- `/explore`'s terminal recording set for the artifact types no chain owns —
  rejection record, decision record, spike report, competitive analysis — which
  stays, because no entry point can receive them.
- `/scope` Phase 1's chain-proposal prompt, and the stale prose beside it: the
  direct-invocation redirect, the justification attached to it, the orphan
  `chain_revised:` field, the undefined second confirmation on the post-PRD
  gate, and the miscounted `chain_skipped:` reason vocabulary.
- `references/parent-skill-pattern.md` and
  `references/parent-skill-state-schema.md`: a statement of the post-#302 model,
  the chain-proposal prompt's contract, the ALWAYS declination clause restated
  so it reads as a preserved instance of the model rather than an exception, and
  a bounded `chain_skipped[].reason` vocabulary.
- `skills/scope/evals/evals.json`: the scenarios grading the retired
  absorbability model, and the assertions pinning the prompt being changed.
- The eval scenarios in `/explore`, `/roadmap`, `/vision`, and `/decision` that
  assert `/explore` routes to a chain-internal child.
- `references/pipeline-model.md`, which restates `/explore`'s routing model
  while naming `/explore` as its authority.

### Out

- **Adding a consolidation judgment to `/charter`.** The strategic chain has
  none, so #302 reached only the tactical chain. Whether it should gain one is a
  real question and a separate one: STRATEGY is the durable audit trail and
  ROADMAP is a working artifact retired by the plan cascade, which is a
  different disposal model from absorb-into-survivor.
- **Retiring `/charter`'s roadmap declination.** It is kept. It forms its
  judgment against a draft STRATEGY that exists, keeps proceeding as the default
  under both readings, and is covered by four eval scenarios written to keep the
  parent's reading advisory. The model is restated around it rather than against
  it.
- **`/execute`.** It has no chain proposal, no confirmation prompt, and nothing
  an author can drop; it omits the chain-tracking triad outright, which the state
  schema sanctions. It already states the model correctly.
- **`crates/shirabe-validate/src/formats.rs` and the absorption checks.** The
  code already encodes the current model. The prose and the evals are what
  lagged.
- **The child skills' internal phase workflows.** `/brief`, `/prd`, `/design`,
  and `/plan` keep their own structure; only how a parent or a router reaches
  them changes.
- **`/explore`'s research loop.** Setup, scoping, discovery, and convergence are
  the skill's actual value and are untouched by the routing change.
- **Re-opening what #302 settled.** The absorbability judgment, the citation
  preflight, the carry check, and the fold record stay as shipped.

## Downstream Artifacts

- `docs/prds/PRD-scope-chain-mandatory-steps.md` — the requirements written from
  this framing, and the closure surface for both questions this brief deferred.

## References

- `docs/briefs/BRIEF-scope-artifact-persistence.md` — the framing for #302, the
  change this brief finishes propagating.
- `docs/prds/PRD-scope-artifact-persistence.md` — states the rule this work
  enforces: no judgment runs before the artifact it is about exists, including
  an author-chosen entry altitude.
- `docs/designs/current/DESIGN-scope-artifact-persistence.md` — the design for
  the document-level absorbability judgment.
- `docs/prds/PRD-scope-consolidation-over-skipping.md` and
  `docs/designs/current/DESIGN-scope-consolidation-over-skipping.md` — the
  predecessor pair, each carrying an amendment recording what #302 falsified.
  Their amendment shape is the precedent for superseded durable prose.
- `references/parent-skill-pattern.md` — the shared contract both parents bind
  to, and the surface that carries neither a statement of the model nor a bound
  reason vocabulary.
- `skills/scope/references/phases/phase-2-chain-orchestration.md` — the
  consolidation judgment as shipped.
