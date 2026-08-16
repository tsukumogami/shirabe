---
schema: design/v1
status: Current
complexity: Complex
upstream: docs/prds/PRD-scope-consolidation-over-skipping.md
decision_provenance: inline-resolved
problem: |
  `/scope` declines to produce BRIEF, PRD, or DESIGN on gates that run before
  the artifact exists, and invokes every child in its cold-start input mode so
  no child ever consumes the upstream the chain just produced. The reader-
  economy reason for reducing the artifact set is stated only inside `/brief`,
  behind a branch `/scope` cannot reach, with no receiver on the other side.
decision: |
  `/scope` always walks the whole tactical chain, `/brief` through `/plan`,
  with no altitude at which the chain starts other than `/brief`. Children
  are invoked through their existing upstream-path input modes so each
  consumes what the chain produced. After each artifact lands, a
  consolidation judgment compares it against the nearest surviving artifact
  above it and may absorb that upstream — but only at a hop where the
  downstream type's required sections have a home for every required section
  of the upstream type, which today is BRIEF into PRD alone. `/brief`'s
  fold-into-PRD branch is retired, and the validator's existing Plan-only
  upstream-resolution check is generalized to every format.
rationale: |
  A run that shrinks its own artifact set before writing anything is the
  defect, whatever the shrinking is called, so the chain runs whole and the
  consolidation judgment is the single mechanism that removes a document.
  Deriving absorbability from the schemas rather than enumerating it means no
  schema variant, no fourth gate shape, and a rule that stays correct if a
  format changes. Invoking children through input modes they already ship
  fixes reachability without touching R14's child-isolation boundary.
---

# DESIGN: scope-consolidation-over-skipping

## Status

Current

Technical design for replacing `/scope`'s produce-or-skip gates. Decisions
were resolved inline under parent-chain dispatch
(`references/fixes/sub-agent-dispatch.md` shape 3), so
`decision_provenance: inline-resolved`.

## Context and Problem Statement

`/scope` walks BRIEF to PRD to DESIGN to PLAN and can decline three of the
four. Every declination is decided before its artifact exists, so no
declination can rest on what the artifact would have said. Behind that sit
two mechanical facts the PRD names and this design has to fix.

The first is invocation shape.
`skills/scope/references/phases/phase-2-chain-orchestration.md` invokes each
child as `/<child-name> <topic-slug>`. A bare slug is every child's
cold-start mode. `/brief` reads it as a freeform topic and settles the
artifact decision with "the framing does not exist yet. Produce a standalone
brief" before the fold branch is reachable. `/prd` reads it as Input Mode 3,
which by its own eval "does NOT invoke shirabe transition because there is no
BRIEF path to transition" — so a PRD written moments after a BRIEF in the
same chain neither records it as `upstream:`, nor advances it, nor reads it.
`/design` and `/plan` are invoked the same way and consume their upstreams
the same amount, which is not at all. Every artifact in a `/scope` chain is
independently re-derived from the parent's conversation. That is the engine
producing the repetition the skip logic was meant to relieve.

The second is that nothing receives folded content. `/brief`'s Phase 0.5 is
explicit that folding is "NOT a license to skip articulation" and that the
four framing concerns "must still be captured durably, in the PRD itself."
It then recommends `/prd` and stops. `/prd` has no absorb step and no input
mode for folded framing. The path names what should move and moves nothing.

The rationale recorded at `/scope`'s own gate layer is unrelated to either.
`skills/scope/references/phases/phase-1-discovery.md` says the auto-skip
exists because "the parent MUST NOT silently overwrite an Accepted durable
artifact" — protection against clobbering, which is correct, necessary, and
not a statement about what a reader has to read. So the reader-facing reason
for reducing the artifact set is documented nowhere in the skill that
implements the reduction.

The architectural surface left to settle is what replaces the gates, how the
parent hands each child its upstream without touching the child's input
surface, where the consolidation judgment lives and when it fires, what
"absorb" can mean against required-section schemas the validator enforces,
how an absorb is verified and how link integrity survives it, and where the
reader-facing intent lives.

## Decision Drivers

- **D1 Judge written content, not future content.** Any decision that
  reduces the artifact set must read a body that exists. A decision that
  cannot read a body must be about something other than whether a document
  would have been worth writing.
- **D2 Reachability is the first-order failure.** The intended mechanism
  already exists once and is inert because `/scope` cannot reach it. A
  replacement that is not reachable from a `/scope` run is not a
  replacement. Every mechanism here lives in `/scope` itself or on a path
  `/scope` demonstrably takes.
- **D3 R14 child isolation holds.** The parent does not extend any child's
  `$ARGUMENTS` parser, add flags, or add environment-variable consumption.
  Anything the parent wants a child to consume must travel through an input
  mode the child already ships.
- **D4 No new substrate.** No fourth gate shape, no new artifact type, no
  per-type schema variant, no CLI subcommand that renders a body. New
  correctness checks belong in `shirabe validate`, per the CLI-surface rule
  in CLAUDE.md.
- **D5 Content that moves must be received and verified.** A recommendation
  that content be carried forward is what already failed. Absorption is only
  legitimate when something checks, section by section, that the content
  arrived.
- **D6 Cite the settled rules.** The `upstream:` convention (nearest
  artifact actually produced, omitted when none was), the three-shape gate
  vocabulary, and the decision-presentation convention were settled in PR
  #252. This design consumes them and does not restate or reopen them.
- **D7 Manual fallback stays symmetric.** A child invoked directly behaves
  exactly as it does today, and `/scope` writes no state for a run it did
  not orchestrate.

## Considered Options

Nine decisions were resolved inline. Each records the chosen option and the
rejected alternatives with their rejection rationale.

### Decision 1: What replaces the produce-or-skip gates

- **Option A (chosen): run all four children on every invocation, and fold
  pairwise as each artifact lands.** `/scope` walks `/brief` through `/plan`
  with no altitude selection anywhere. The consolidation judgment (Decision
  3) is the only thing that ends a run with fewer documents than the chain
  has altitudes.
- **Option B (rejected): an entry altitude chosen once in Phase 1.** This
  shipped in an earlier revision of this design and was withdrawn. It reaches
  all four artifact-set outcomes, and the question it asks the author is
  genuinely answerable — it is about the conversation they are having, not
  about an unwritten document. But it is still a decision that shrinks the
  artifact set before any artifact exists, which is the shape this design
  exists to remove, and it left two reduction mechanisms operating at
  different times so neither read as the rule.
- **Option C (rejected): keep per-hop gates but give them richer signals.**
  Whatever the signal, the gate still fires before its artifact exists. This
  is the shape the PRD's problem statement rejects, restated with more
  inputs.
- **Option D (rejected): run all four, then delete redundant artifacts once
  at the end.** Every downstream artifact has already cited a document that
  is about to disappear, so the re-pointing cascades across the whole set at
  once, and the author sees the reduction long after the conversation that
  justified it.

Chosen because it leaves exactly one mechanism that reduces the artifact set,
and that mechanism reads two bodies that exist. Nothing anywhere in a
`/scope` run decides that an unwritten document would not have been worth
writing.

The cost is real and is recorded in Consequences: because absorption is
available at one hop only (Decision 4), a `/scope` run ends with either all
four artifacts or the chain minus an absorbed BRIEF. The two shorter outcomes
— a DESIGN and a PLAN, or a PLAN alone — are reached by invoking `/design` or
`/plan` directly. That is not a workaround: entering the tactical chain at
the altitude that matches the conversation is what the pipeline model already
describes and what CLAUDE.md already tells authors to do. The difference is
that the choice now lives in what the author typed rather than in a judgment
`/scope` makes on their behalf.

### Decision 2: How `/scope` hands each child its upstream

- **Option A (chosen): invoke each child through the upstream-path input
  mode it already ships, whenever this chain produced that upstream.**
  `/brief` is invoked with the topic slug, being the head of the chain;
  every subsequent child is invoked with the path of the nearest artifact
  this chain produced above it — `/prd docs/briefs/BRIEF-<topic>.md`, `/design docs/prds/PRD-<topic>.md`,
  `/plan docs/designs/DESIGN-<topic>.md`.
- **Option B (rejected): add `--upstream <path>` to each child.** Adds a
  flag to four children's argument parsers. D3 forbids it.
- **Option C (rejected): have each child glob its canonical upstream path
  and self-discover.** Implicit, and it fires under direct invocation too,
  so a child run standalone would silently pick up an unrelated artifact.
  Breaks D7.
- **Option D (rejected): carry the upstream path in the
  `parent_orchestration:` sentinel.** The sentinel is a pattern-level
  convention children already read, so this is less illegal than B, but it
  still adds a new parse branch to each child for content that has a shipped
  input mode. Redundant given A.

Chosen because every child already accepts its upstream artifact's path as a
first-class input mode — `/prd` Input Mode 2 takes a BRIEF path and
transitions it Draft to Accepted, `/design`'s PRD mode reads the accepted PRD
and bumps it to In Progress, `/plan` accepts a DESIGN path. Nothing is
extended; the parent stops choosing the cold-start mode for children whose
upstream it just wrote. This single change is what makes `/prd` consume the
BRIEF (PRD R6) and what makes every downstream `upstream:` field record the
chain that was actually walked.

### Decision 3: Where the consolidation judgment lives and when it fires

- **Option A (chosen): in `/scope` Phase 2, per hop, immediately after the
  R20 file-existence check and validator pass-through for the child that
  just returned.** It compares the artifact just written against the nearest
  *surviving* durable artifact above it in this chain.
- **Option B (rejected): once at the end, across the whole artifact set.**
  By then every downstream artifact cites documents that may be about to
  disappear, so re-pointing becomes a set-wide operation rather than a local
  one, and the author sees the reduction long after the conversation that
  justified it.
- **Option C (rejected): inside each child skill.** This is exactly where
  `/brief`'s fold path lives and exactly why it is inert — a child cannot
  see the chain, and the parent's invocation shape decides whether the
  branch is reachable. Violates D2.
- **Option D (rejected): as a separate `/consolidate` skill invoked after
  the chain.** A third place for the same rule to drift, and it would need
  its own chain-state reconstruction.

Chosen because per-hop keeps the judgment local: only one link can need
re-pointing, and the author sees the verdict next to the artifacts it is
about. It also disposes of the cascade question the PRD raised. Absorption
means the upstream's content is *in* the survivor, not annotated as living
elsewhere, so when a later hop judges that survivor it is judging a body that
already includes everything absorbed into it. Nothing rides along separately
and there is no chain of pointers to follow.

### Decision 4: What absorb can mean against fixed required-section schemas

- **Option A (chosen): absorb is available only at a hop where a total
  mapping exists from every required section of the upstream type into the
  required sections of the downstream type.** The mapping is stated in
  `/scope`'s reference prose and derived from
  `crates/shirabe-validate/src/formats.rs`. Where no total mapping exists,
  the judgment's only available verdict is `keep`.
- **Option B (rejected): grow the DESIGN schema with optional Requirements
  and Acceptance Criteria sections so a PRD can be absorbed.** A per-type
  schema variant, which PRD R19 forbids, and it turns DESIGN into a PRD
  with extra sections rather than reducing anything.
- **Option C (rejected): allow a lossy absorb that records what was
  dropped.** Trades a document a reader must read for content a reader
  cannot read. The complaint was repetition, not volume.
- **Option D (rejected): hard-code "BRIEF folds into PRD" and say nothing
  about the others.** Correct today by accident. A reader cannot tell
  whether the other hops were considered, and the rule silently becomes
  wrong if a format gains a section.

Applied to the current formats, the mapping test yields exactly one
absorbable hop:

| Hop | Upstream required sections | Home in downstream | Absorbable |
|---|---|---|---|
| BRIEF to PRD | Problem Statement, User Outcome, User Journeys, Scope Boundary | Problem Statement, Goals, User Stories, Requirements (in-list) and Out of Scope (out-list) | Yes |
| PRD to DESIGN | Problem Statement, Goals, User Stories, Requirements, Acceptance Criteria, Out of Scope | Context and Problem Statement only | No |
| DESIGN to PLAN | Context and Problem Statement, Decision Drivers, Considered Options, Decision Outcome, Solution Architecture, Implementation Approach, Security Considerations, Consequences | none | No |

Chosen because stating the rule rather than the answer costs one paragraph
and buys correctness under schema change, and because the rule explains
itself: absorption is legitimate exactly when it does not have to discard
content or invent a place to put it.

### Decision 5: How an absorb is verified

- **Option A (chosen): an explicit per-section carry check, recorded as a
  table, run before the upstream is removed.** For each required section of
  the absorbed type, the check names where in the survivor that concern
  landed and marks it carried or not-carried. Any not-carried aborts the
  absorb; both artifacts stay and the finding is recorded.
- **Option B (rejected): a `shirabe validate` mode that checks the
  consolidated artifact.** "Carries the same concern" is semantic, not
  structural. The PRD's four counterpart sections are required already, so a
  structural check would pass unconditionally — worse than nothing, because
  it would look like verification.
- **Option C (rejected): trust the absorb verdict with no itemized check.**
  This is the shipped fold path: a recommendation with no receiver and
  nothing confirming the transfer. Violates D5.
- **Option D (rejected): an independent reviewer agent per absorb.** Buys
  independence the other options lack, at a per-run cost on the most common
  hop, for a check whose inputs are two documents in front of the same
  agent. Deferred; the recorded table is what makes a later reviewer
  possible.

Chosen because the itemized table is the smallest thing that makes the
transfer auditable by a human reading the PR, and because it fails in the
right direction: a section the survivor does not carry aborts the absorb
rather than losing content. Its non-independence is recorded in Consequences.

### Decision 6: Link integrity after an absorb

- **Option A (chosen): the survivor inherits the absorbed artifact's
  `upstream:` value, or omits the field when the absorbed artifact had none,
  and the validator's existing upstream-resolution check is generalized from
  Plan docs to every format.** `check_plan_upstream` becomes
  `check_upstream_resolves`, keeping code `R6`, and gains a guard that skips
  cross-repo `owner/repo:path` references.
- **Option B (rejected): rely on the finalize-chain walk to catch a broken
  link.** That walk runs at cascade time against a PLAN chain. A dangling
  `upstream:` would sit unnoticed from the absorb until implementation
  finishes.
- **Option C (rejected): keep the absorbed artifact on disk at a superseded
  status instead of deleting it.** BRIEF's valid statuses are Draft,
  Accepted, and Done — there is no superseded state to move it to — and
  leaving it on disk leaves the reader the second document they were meant
  to stop reading.
- **Option D (rejected): a new check code for consolidated docs
  specifically.** The rule is not about consolidation. An `upstream:` that
  does not resolve is wrong however it got that way.

Chosen because the mechanism already exists and is scoped too narrowly:
`check_plan_upstream` verifies existence on disk and git-tracking for Plan
docs only. Widening it turns a consolidation-specific risk into a general
correctness guarantee, follows the settled nearest-produced rule for the
re-point, and adds no new check code for reviewers to learn.

### Decision 7: What happens to `/brief`'s fold-into-PRD branch

- **Option A (chosen): retire it.** `/brief`'s Phase 0.5 artifact decision
  drops the fold path; the skill always produces a standalone brief and
  recommends `/prd <brief-path>` on completion. The reader-economy rationale
  moves to `/scope`, where the reduction now happens.
- **Option B (rejected): keep it for direct invocation only.** Leaves two
  mechanisms sharing one name, which is a named part of the problem, and
  leaves the direct-invocation path making the very
  decide-before-it-exists call this work removes.
- **Option C (rejected): keep it and have `/prd` implement the receiving
  half.** Builds the receiver for a branch that now has a strictly better
  answer available — write the brief, then let the judgment read it.
- **Option D (rejected): retire it and have `/brief` route the author to a
  different altitude instead.** A child deciding it should have been a
  different child is the artifact-routing job `/explore` already owns.

Chosen because retiring the branch is what makes the reader-facing intent
single-sourced. A direct `/brief` invocation loses nothing real: it produced
no artifact on the fold path anyway, and the author who wants the reduction
gets it by running `/scope`, which can now actually deliver it.

### Decision 8: The durable-artifact floor

- **Option A (chosen): the floor is structural, and no guard implements
  it.** A `/scope` run always writes BRIEF, PRD, DESIGN and PLAN, and
  Decision 4 makes every hop above BRIEF-to-PRD unabsorbable, so the smallest
  set a run can end with is a PRD, a DESIGN and a PLAN. A run that leaves no
  durable artifact is unreachable through `/scope`, and nothing has to check
  for it.
- **Option B (rejected): an explicit guard that refuses to reduce below one
  durable artifact.** Dead code. The guard's condition cannot hold given
  Decision 4, and a check that can never fire teaches a later maintainer that
  the case is possible.
- **Option C (rejected): allow a PLAN-alone `/scope` run behind a warning.**
  Requires an altitude selection to reach at all, which Decision 1 removed.
- **Option D (rejected): make DESIGN absorbable into PLAN so the shortest
  outcome stays reachable.** The PLAN is deleted once its work is
  implemented, so this trades a durable audit trail for a shorter run and
  loses the record of why the work happened.

The PRD asks for the PLAN-alone answer to be stated deliberately rather than
left to fall out of the model, so: a `/scope` run never produces it. An
author who genuinely wants no durable record beyond the code invokes `/plan`
directly, which is a claim they are entitled to make and which is visible in
what they typed.

### Decision 9: Whether the model generalizes to `/charter`

- **Option A (chosen): state in prose that the consolidation model is a
  no-op on the strategic chain, and change nothing.**
- **Option B (rejected): implement the same model in `/charter` now.** Out
  of scope per the PRD, and the consolidation half would add machinery that
  can never fire.
- **Option C (rejected): say nothing.** The PRD asks for the answer.

`/charter` has already taken the run-every-child half of this: PR #252 made
`/roadmap` an ALWAYS child with an author declination rather than a threshold
the parent computed, which is the same move Decision 1 makes for `/design`.
The consolidation half does not generalize, and the mapping test from
Decision 4 says why. STRATEGY's required sections have no home for a VISION's Audience,
Value Proposition, Org Fit, or Success Criteria; ROADMAP's have no home for a
STRATEGY's Defensibility Thesis, Building Blocks, or Bet-Specific
Falsifiability. Zero strategic hops are absorbable, so porting the judgment
would install a rule that can only ever return `keep`. The model is intended
to generalize; generalizing it today changes nothing, which is the reason not
to.

## Decision Outcome

**`/scope` runs the whole chain.** `planned_chain:` is
`[brief, prd, design, plan]` on every invocation, minus only children held
back by re-entry protection. There is no altitude selection: no flag, no
prompt, no state field, and no computed recommendation decides where the
chain starts.

The per-hop produce-or-skip gates are removed. `/brief`'s R4 gate, `/prd`'s
R5 gate, and `/design`'s R6/R7 shape-dependent gate stop deciding whether
their child runs. The R6 predicates survive only as the input to `/design`'s
decision-roster shape, which is what "shape-dependent" always meant — the
gate governs *how* the child is invoked, not whether.

**Re-entry protection survives under its own name.** A child whose durable
artifact already exists at a settled status at the canonical path is still
skipped, recorded in `chain_skipped:` with reason
`settled-artifact-at-canonical-path-reentry-protection`, and the prose around
it states that this protects a settled document from being overwritten and is
not a judgment about whether the artifact was worth writing. The gate shape
stays Mandatory-with-auto-skip; the vocabulary keeps three shapes.

**Children are invoked through their upstream-path input modes.** Phase 2's
invocation rule changes from `/<child-name> <topic-slug>` to: `/brief` takes
the topic slug, because nothing in the chain sits above it; every later child
takes the path of the nearest artifact this chain produced above it. Nothing
is added to any child's input surface.

**A consolidation judgment runs per hop**, in Phase 2 after the R20
file-existence check and the validator pass-through. It reads the artifact
just written and the nearest surviving durable artifact above it, and reaches
`keep` or `absorb`. `absorb` is available only where the Decision 4 mapping
is total, which today is BRIEF into PRD. On `absorb`, the per-section carry
check runs; if every section is carried, the upstream is deleted, the
survivor inherits the upstream's own `upstream:` value (or omits the field),
and the verdict plus the carry table are recorded. If any section is not
carried, the absorb aborts and both artifacts stay.

**`/brief`'s fold-into-PRD branch is retired** and the reader-economy
rationale it carried moves into `/scope`'s Phase 1 and Phase 2 references and
its SKILL.md, stated in `/scope`'s own words at the layer that now performs
the reduction.

**`shirabe validate` generalizes its upstream-resolution check** from Plan
docs to every format, skipping cross-repo references, so a missed re-point
fails mechanically.

## Solution Architecture

### Component changes

```
skills/scope/SKILL.md
    # New "## Why the Artifact Set Shrinks" section — the reader-facing
    #   rationale, stated here rather than cited from /brief
    # New "## Consolidation Judgment" section — verdicts, absorbability
    #   rule, carry check, per-hop placement

skills/scope/references/phases/phase-1-discovery.md
    # R4/R5 gate sections rewritten: re-entry protection only, renamed
    #   reason string, explicit "this is not a worth-producing judgment"
    # R6 predicate walk retargeted: sizes /design's roster, no longer
    #   gates /design
    # New "What Phase 1 Decides, and What It Does Not" section
    # planned_chain population: the whole chain, every run

skills/scope/references/phases/phase-2-chain-orchestration.md
    # Child Invocation section: upstream-path input mode rule
    # Per-child loop grows step 8, the consolidation judgment
    # New "Consolidation Judgment" section: absorbability mapping table,
    #   carry check, absorb procedure, re-point rule, abort path

skills/scope/references/state-schema.md
    # + visibility:                Public | Private (read back by Phase 2)
    # + consolidation_judgments:   per-hop verdict list with carry tables

skills/brief/SKILL.md
skills/brief/references/phases/phase-0-setup.md
    # Phase 0.5 artifact decision: fold-into-PRD path removed; the skill
    #   always produces a standalone brief and recommends /prd <brief-path>

skills/prd/references/phases/phase-3-draft.md
    # Drafting guidelines: when an upstream BRIEF exists, draw Problem
    #   Statement, Goals, User Stories and Out of Scope from it and cite
    #   rather than re-narrate

skills/prd/references/prd-format.md
skills/design/references/design-format.md
    # Quality guidance: the standalone-readability rule is scoped to the
    #   problem statement; everything the upstream already says is cited

crates/shirabe-validate/src/checks.rs
    # check_plan_upstream -> check_upstream_resolves, cross-repo guard
crates/shirabe-validate/src/validate.rs
    # call site moves out of the Plan match arm into the common path

skills/{scope,brief,prd}/evals/evals.json
    # scenarios for whole-chain invocation, upstream-path invocation, the
    #   two consolidation verdicts, the aborted absorb, re-entry protection
```

### What Phase 1 still does

Phase 1 keeps its discovery work and loses its gate work. It surveys the
canonical paths for the topic, walks the R6 predicates, runs the cold-start
projection, and asks the framing-shift question — but none of those outputs
decides whether a child runs any more:

```
on-disk survey    -> re-entry protection (is a settled artifact already here?)
                  -> initial child_snapshots
R6 predicates     -> /design's decision-roster size, and nothing else
topic projection  -> framing for the discovery conversation
framing-shift     -> the override on /brief's re-entry protection
```

`planned_chain:` is `[brief, prd, design, plan]` on every run, minus only
children held back by re-entry protection. The chain proposal narrates that
list and the per-predicate verdicts behind `/design`'s roster size, and keeps
its `Proceed` / `Adjust` / `Bail` substrings — `Adjust` re-enters discovery
with the author's input rather than selecting a different starting point,
because there is no starting point to select.

### Per-child loop, revised

Phase 2's seven-step loop becomes eight:

```
for child in planned_chain:
  1. worktree-staleness check                     (unchanged)
  2. write parent_orchestration: sentinel         (unchanged)
  3. invoke child                                 (CHANGED: upstream-path mode)
  4. R20 structural file-existence check          (unchanged)
  5. clear parent_orchestration: sentinel         (unchanged)
  6. child-snapshot capture                       (unchanged)
  7. validator pass-through                       (unchanged)
  8. consolidation judgment vs nearest survivor   (NEW)
```

Step 3's argument selection:

```
if child == brief:                 arg = <topic-slug>
else:                              arg = path of nearest artifact this chain
                                         produced above `child`
```

The paths are the canonical ones R20 already tests, so step 3 and step 4
agree by construction. A child whose upstream was absorbed at an earlier hop
receives the survivor's path, which is what "nearest artifact this chain
produced" means once an absorb has happened.

### Consolidation judgment

Step 8 runs only when this chain produced a durable artifact above the one
that just landed. It resolves in three stages.

**Stage 1 — absorbability.** Look up the hop in the mapping table. If the
mapping is not total, the only available verdict is `keep`; record it with
the reason naming the unmapped sections and stop.

**Stage 2 — judgment.** Read both bodies. The question is whether the
upstream artifact does work the downstream artifact does not: does any
required section of the upstream carry content, detail, or framing the
downstream does not also carry? A `no` is `absorb`; a `yes` is `keep`, with
the finding naming what the upstream holds that the survivor does not.

**Stage 3 — carry check and absorb.** On `absorb`, walk the upstream's
required sections one at a time and record where each landed:

```yaml
consolidation_judgments:
  - hop: brief->prd
    absorbable: true
    carry_check:
      Problem Statement: {target: Problem Statement, carried: true}
      User Outcome:      {target: Goals, carried: true}
      User Journeys:     {target: User Stories, carried: true}
      Scope Boundary:    {target: Requirements + Out of Scope, carried: true}
    verdict: absorb
    absorbed: docs/briefs/BRIEF-<topic>.md
    into: docs/prds/PRD-<topic>.md
```

Any `carried: false` aborts: the verdict is downgraded to `keep`, the
finding names the section that did not arrive, and both artifacts stay. This
is the receiver D5 requires — the check that the shipped fold path never had.

On a completed absorb:

1. Read the absorbed artifact's own `upstream:` value.
2. Set the survivor's `upstream:` to that value, or remove the field when
   the absorbed artifact had none.
3. `git rm` the absorbed artifact.
4. Re-run `shirabe validate` on the survivor; a non-zero exit reverts the
   absorb and routes to R8 bail-handling.

Step 4 is what makes the generalized `R6` check load-bearing: a survivor
whose `upstream:` no longer resolves fails validation and the absorb does not
land.

### Citation rule

The standalone-readability rules in the format references
(`skills/brief/references/brief-format.md`, "Stands alone. A reviewer landing
on the brief cold should grasp what's broken... without having to open the
upstream roadmap"; `skills/design/references/design-format.md`, "Stands
alone. A reader landing on the DESIGN cold should grasp what's broken without
reading the upstream PRD") are already scoped to the problem-statement
section, not to the whole document. That scoping is what lets
standalone-readability and non-duplication coexist, and it is the reason
`DESIGN-table-diagram-reconciliation` can open by citing the PRD's
requirement numbers and lose nothing while `DESIGN-pr-template-gate`
re-narrates its upstream in full — both passed the same review machinery
because no rule distinguished them.

The rule is stated once, in the two format references' quality guidance:
restate the problem in full, cite everything else the upstream already says.
`/prd`'s drafting phase and `/design`'s drafting phase both point at it. No
new required section and no validator check — this is authoring guidance, and
a structural check cannot tell a citation from a restatement.

### Manual-fallback boundary

Step 8 lives in `/scope` Phase 2 and nowhere else, so a child invoked
directly runs no consolidation judgment and writes no `/scope` state. The
symmetry is structural rather than conditional: there is no
consolidation code path inside a child to suppress, which is the same reason
Decision 3 rejected putting the judgment in one.

### Durable record

`consolidation_judgments:` lives in the `wip/` state file during the run.
Phase 3 exit-finalization writes the same information into the PR body's
artifact list, so it survives Phase 4's `wip/` cleanup: every artifact
produced, every artifact absorbed, into what, and the finding. A reviewer
reading only the PR can distinguish "not produced" from "absorbed."

### Validator change

```rust
// checks.rs
pub fn check_upstream_resolves(doc: &Doc) -> Vec<ValidationError> {
    let field = match doc.fields.get("upstream") { Some(f) => f, None => return Vec::new() };
    let path = &field.value;

    // Cross-repo references (`owner/repo:path`) are resolved by the
    // cross-repo reference rules, not on this filesystem.
    if is_cross_repo_reference(path) { return Vec::new(); }

    // ... existing exists-on-disk and git-ls-files body, code "R6" ...
}
```

`validate.rs` moves the call out of the `Some("Plan")` match arm into the
common per-doc path, next to `check_fc03` and `check_fc04`. The check code
and its two messages are unchanged, so no reviewer has a new code to learn
and `is_known_check_code` needs no new entry.

### Data flow

```
/scope <topic>
  Phase 1  survey + predicates -> re-entry protection, /design roster size
           author confirms the proposal (or --auto takes it)
           planned_chain = [brief, prd, design, plan]
  Phase 2  for each child:
             invoke with slug (entry) or nearest produced upstream path
             R20 + validator pass-through
             consolidation judgment vs nearest survivor
               keep   -> record verdict + finding
               absorb -> carry check
                           all carried -> re-point, git rm, re-validate
                           any missing -> abort to keep, record
  Phase 3  exit: full-run; exit_artifacts = surviving durable set + PLAN
           PR body records produced / absorbed / findings
  Phase 4  wip cleanup
```

## Implementation Approach

Six batches, single PR. The skill-prose batches are independent of each
other; the validator batch is independent of all of them.

**Batch 1 — `/scope` Phase 1.** Rewrite the R4 and R5 gate sections as
re-entry protection with the renamed reason string and the explicit
not-a-worth-producing-judgment statement. Retarget the R6 predicate walk to
size `/design`'s decision roster and nothing else. Add the "What Phase 1
Decides, and What It Does Not" section. Update `planned_chain:` population to
the whole chain on every run.

**Batch 2 — `/scope` Phase 2.** Change the Child Invocation section to the
upstream-path rule. Add step 8 to the per-child loop and the Consolidation
Judgment section with the mapping table, the three stages, the carry-check
schema, and the absorb procedure.

**Batch 3 — `/scope` SKILL.md and state schema.** Add the Why the Artifact
Set Shrinks and Consolidation Judgment sections, update the Chain-Proposal
Output section, and add `visibility:` and `consolidation_judgments:` to
`skills/scope/references/state-schema.md`.

**Batch 4 — children.** Remove `/brief`'s fold-into-PRD branch from
`skills/brief/references/phases/phase-0-setup.md` and the corresponding
SKILL.md summary; add the upstream-BRIEF drafting rule to
`skills/prd/references/phases/phase-3-draft.md`.

**Batch 5 — validator.** Rename `check_plan_upstream` to
`check_upstream_resolves`, add the cross-repo guard, move the call site, and
add unit tests: resolving upstream on a non-Plan doc is clean, dangling
upstream on a non-Plan doc errors with code `R6`, cross-repo reference is
skipped, absent field is clean.

**Batch 6 — evals.** Update `skills/scope/evals/evals.json`,
`skills/brief/evals/evals.json`, and `skills/prd/evals/evals.json` for the
changed behaviors, and run those three suites only.

Sequencing within the PR is free; batch 5 is the only one with compiled
tests, and `cargo test --workspace` gates it.

## Security Considerations

The change adds one filesystem mutation and one path-interpolation site to
`/scope`, and widens the reach of an existing validator check.

**Deletion authority.** The absorb procedure runs `git rm` against an
artifact path. The path is not author-supplied: it is the canonical path
`docs/briefs/BRIEF-<topic>.md` composed from the topic slug, which Phase 0
validates against `^[a-z0-9-]+$` as provided and which the resume ladder
re-validates before any interpolation
(`references/parent-skill-security.md`, Slug Re-Validation on Resume). The
closed write-target set in `/scope`'s Security Considerations gains
`docs/briefs/` as a delete target; the set stays closed and enumerable.

**No new control-flow field.** The chain shape is a constant, so nothing
new joins the state-file enum re-validation list in Phase 2 — `boundary:`,
`decision_record_sub_shape:`, `triggering_child:` and `plan_execution_mode:`
are unchanged. A state file whose `planned_chain:` has been tampered with
cannot redirect an invocation to an unexpected child, because the child names
are fixed and each one's argument path is composed from the validated topic
slug rather than from state.

**Upstream values are untrusted input.** The generalized `R6` check reads
`upstream:` from document frontmatter, which is author-supplied, and passes
it to `git ls-files --error-unmatch -- <path>`. The argument is positional
after `--`, so no shell metacharacter interpretation occurs, and the existing
`Command` invocation does not spawn a shell. This is unchanged behavior on a
wider set of documents, not a new surface. The check reports; it never
follows or opens the path.

**Widening the check cannot leak.** The generalized check runs on every
format, including private-only COMP docs, but it reports only the path
already written in the document under validation and never reads the
upstream's contents. A public run cannot surface private content it did not
already hold.

**Visibility boundary is unchanged.** The absorb procedure moves content
between two documents in the same repository at the same visibility. It
never crosses a repository or a visibility boundary, and the cross-repo guard
in the validator check exists precisely so the check does not attempt to
resolve a foreign-repo path on this filesystem.

**Failure direction.** Every new failure mode fails toward keeping
artifacts: an unmapped hop keeps, a failed carry check keeps, a
post-absorb validation failure reverts the absorb. No path deletes an
artifact on an error.

## Consequences

### Positive

- A `/scope` run stops re-deriving. Every child receives the artifact above
  it and cites it, which removes the restatement that made the artifact set
  read as repetitive in the first place.
- Every `upstream:` in a `/scope` chain records the chain that was actually
  walked, which the settled nearest-produced rule already describes and
  which `/scope` was silently failing to produce.
- The reduction decision is made against written bodies, by a step that can
  see them, and is auditable afterwards from the PR alone.
- One mechanism carries one name. The fold-into-PRD branch is gone, and the
  reader-economy rationale lives where the reduction happens.
- A dangling `upstream:` is now an error on any document type, not just a
  Plan.
- Re-entry protection is legible as what it is, so the next person changing
  these gates does not have to infer intent from a neighbouring skill.

### Negative

- The carry check is performed by the same agent that wrote both documents.
  It reads real bodies rather than guessing at unwritten ones, which is the
  improvement being bought, but it is not an independent review.
- Two of the four artifact-set outcomes are unreachable through `/scope`. A
  DESIGN-and-PLAN run, or a PLAN alone, requires invoking `/design` or
  `/plan` directly. That is the documented way to enter the tactical chain at
  a chosen altitude, but an author who reaches for `/scope` expecting the
  whole ladder will not find it there.
- Absorption has exactly one reachable hop. A rule stated in general terms
  with a single instance invites the reasonable question of why it was not
  written as "BRIEF folds into PRD."
- A DESIGN is now produced for every feature scoped at or above the design
  altitude, including features with one live option. The citation rule keeps
  those documents short, but they are documents that today would not exist.
- Retiring `/brief`'s fold path removes a behavior direct-invocation users
  may have relied on, and the replacement only exists inside `/scope`.

### Mitigations

- **Non-independent carry check:** the recorded table is the artifact a
  human reviewer or a later independent reviewer reads. Decision 5 Option D
  stays available without rework.
- **Entry-altitude timing:** `Adjust` re-enters discovery, so an author who
  discovers mid-conversation that the altitude was wrong changes it without
  restarting.
- **One absorbable hop:** the mapping table is stated in the reference
  prose, so the next schema change re-derives the answer instead of
  silently invalidating a hard-coded rule.
- **More DESIGNs:** PRD R15's citation rule bounds their size, and a DESIGN
  that records one live option and why no alternative was live is a better
  audit trail than the silence it replaces.
- **Retired fold path:** `/brief` now ends by recommending
  `/prd <brief-path>`, so a direct-invocation author lands one command away
  from the chain that can perform the reduction.

## References

- PRD: `docs/prds/PRD-scope-consolidation-over-skipping.md` (23 acceptance
  criteria, 21 requirements).
- BRIEF: `docs/briefs/BRIEF-scope-consolidation-over-skipping.md` (framing).
- `references/parent-skill-pattern.md` — Gate Vocabulary, the three shapes,
  the EITHER-signal retirement, invariant I-7.
- `references/parent-skill-security.md` — slug re-validation, closed
  write-target set, state-file enum re-validation.
- `references/pipeline-model.md` — the settled `upstream:` rule and the
  non-strict tactical chain.
- `references/fixes/sub-agent-dispatch.md` — the five fallback shapes; shape
  3 governs this design's inline decision resolution.
- `skills/scope/references/phases/phase-1-discovery.md`,
  `skills/scope/references/phases/phase-2-chain-orchestration.md` — the
  gates and the invocation shape being changed.
- `skills/brief/references/phases/phase-0-setup.md` — the fold path being
  retired.
- `skills/prd/references/phases/phase-3-draft.md` — the drafting guidance
  gaining the upstream-BRIEF rule.
- `crates/shirabe-validate/src/formats.rs` — the per-type required-section
  contracts the absorbability mapping is derived from.
- `crates/shirabe-validate/src/checks.rs` — `check_plan_upstream`, the check
  being generalized.


## Amendment — 2026-08-15

Superseded in part by `DESIGN-scope-artifact-persistence.md`, which makes
the consolidation judgment decide absorbability from the two documents at
a hop rather than from their types. The original text above is left
unedited; this section records what no longer holds and why.

**Decision 8 (the durable-artifact floor) — the conclusion is falsified,
and the option it rejected is the one now adopted.**

Option A concluded that "the smallest set a run can end with is a PRD, a
DESIGN and a PLAN" and that "a run that leaves no durable artifact is
unreachable through `/scope`." Both followed from Decision 4 making every
hop above BRIEF-to-PRD unabsorbable. That premise is gone: absorbability
is now a question about the two documents, so every hop is decidable and
a chain can fold to nothing.

Option D — "make DESIGN absorbable into PLAN so the shortest outcome
stays reachable" — was rejected here on the ground that the PLAN is
deleted, so the move "trades a durable audit trail for a shorter run and
loses the record of why the work happened." That objection was answered
rather than overruled. The record of *why* belongs in the code, kept
current as the code changes, which is now a standing instruction in
`/work-on` and independent of what any chain decided. And the record of
*what happened* is `docs/folds.md`, which survives on the default branch
whether or not any chain artifact does.

Option B — an explicit guard refusing to reduce below one durable
artifact — was rejected as dead code whose "condition cannot hold." The
condition now holds, and the guard is still forbidden, for a different
reason: it would decide a fold from the artifact *set* rather than from
the two documents at the hop. That prohibition now lives beside the
judgment in `phase-2-chain-orchestration.md`, because the single-mechanism
rule does not catch a keep-only guard and so cannot be relied on to
forbid it.

**Decision 9 (`/charter` is out of scope) — the conclusion stands, the
reasoning does not.**

The reasoning was that "zero strategic hops are absorbable, so porting
the judgment would install a rule that can only ever return `keep`."
That rests on the same type-level mapping test, and under the current
rule no chain can be declared unabsorbable in advance.

The conclusion survives on grounds that do not depend on it: there is no
consolidation judgment in `/charter` to change, and the judgment's logic
lives entirely inside `/scope`'s own phase files, so extending it to the
strategic chain would be new machinery rather than a follow-on edit.

## Amendment — 2026-08-16

`DESIGN-fold-record-removal.md` removes `docs/folds.md`. The original text above is left unedited; this section records what no longer holds.

**Option D stays adopted. The second half of the answer that rescued it is
withdrawn, and this section states what replaces it.** The objection was that
absorbing a DESIGN into a PLAN "trades a durable audit trail for a shorter run and
loses the record of why the work happened," and the 2026-08-15 amendment above
answered it in two halves.

The half recording *why* is unchanged and is the stronger of the two. It lives in
the code, as a standing `/work-on` instruction that holds regardless of what
documents the work leaves behind — which is written for exactly this case.

The half recording *what happened* pointed at `docs/folds.md`. Three things now
carry it, in descending coverage. The survivor's `absorbed:` declaration and
`## Status` absorption line carry it for every hop that leaves a survivor, under
error-level enforcement, and they accumulate so the last survivor names every
ancestor folded into it. The ROADMAP feature's downstream cell carries it for a
chain that folded to nothing — conditionally, since a chain that came through no
roadmap feature has no cell, and temporarily, since the same cascade deletes the
roadmap once its features land. And for a chain that folds to a PLAN the cascade
deletes, with no roadmap feature behind it, **nothing carries it**: that chain and
a chain that never ran are indistinguishable on the default branch.

That last case is stated rather than solved. It is the accepted cost of the
removal, and it does not reopen this decision: the objection was about the audit
trail Option D trades away, and the trade is now smaller than the record made it
look — the *why* survives in the code, and the *what* survives wherever a
document does. No durable-artifact floor follows from it, and the prohibition
against a guard that forces `keep` to manufacture one is unaffected.
