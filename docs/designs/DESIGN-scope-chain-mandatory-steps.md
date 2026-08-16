---
schema: design/v1
status: Planned
upstream: docs/prds/PRD-scope-chain-mandatory-steps.md
decision_provenance: inline-resolved
problem: |
  Four surfaces still describe the pre-#302 world in which a tactical-chain step
  could be skipped because someone judged its document not worth writing. The
  shared parent-skill pattern is the load-bearing one: it never states the
  model, it is the source of the chain-proposal contract both parents emit, and
  its ALWAYS gate carries the only clause authorizing a step to be dropped
  before its artifact exists.
decision: |
  State the model once in the shared pattern and restate the declination clause
  around three verifiable properties. Replace /explore's ten-type crystallize
  framework with two-stage scoring — terminal outcome first, then chain entry
  point — with candidacy preconditions for the two arms that cannot be reached
  by score. Give the router a parent-namespaced handoff artifact consumed
  through each parent's reserved Slot 7, fix the two ladder rows that currently
  misroute it, and make the Phase 1 bail reach clean-cancel.
rationale: |
  The two questions the router asks are not comparable quantities, so one
  scoreboard is a claim that they are. The handoff and its detection are one
  decision taken twice: a parent-namespaced path is the only shape swept by a
  rule that already exists and detected by a clause reading one path. And every
  fix lands in the document both parents inherit from, because a skill-local fix
  would leave the pattern contradicting the skill.
---

# DESIGN: Chain Steps Are Mandatory

## Status

Planned

Five decision questions were decomposed and evaluated. Under parent-chain
dispatch the decisions were resolved inline rather than delegated, recorded here
under Considered Options; `decision_provenance: inline-resolved` records that.

## Context and Problem Statement

Issue #280 argued that deciding a document is not worth producing before it
exists is the wrong-shaped judgment, and #302 replaced the type-level
absorbability test with a per-hop judgment read against two bodies that exist.
The corpus did not finish moving. The requirements this design implements are in
`docs/prds/PRD-scope-chain-mandatory-steps.md`.

The technical problem is not that four documents carry stale sentences. It is
that the stale statements sit at three levels of a contract hierarchy and
disagree with each other in ways that compound.

At the top, `references/parent-skill-pattern.md` states no model at all, so
there is nothing for a parent to conform to. It does fix the chain proposal's
option tokens and declare their default, which means the prompt both parents
emit is a pattern-level artifact — a skill-local change to it would leave the
pattern requiring an option the skill no longer offers. Its ALWAYS gate carries
a declination clause that is the corpus's only sanction for dropping a step
before its artifact exists, positioned as a concession rather than as an
instance of a rule, and its `chain_skipped[].reason` vocabulary is free text
that the two parents close in incompatible directions.

In the middle, `/scope` states the model and contradicts it beside itself, and
`/explore` routes authors into chain interiors at five different depths while
authoring four kinds of durable document on their behalf.

At the bottom, the eval suite grades the model that #302 removed, which makes it
the one surface that actively pulls an agent backward.

Two defects surfaced during requirements work that the change would inherit
rather than introduce. `/scope`'s resume-ladder Slot 6.3 globs
`wip/prd_<topic>_*` and matches the handoff `/explore` writes at
`wip/prd_<topic>_scope.md`, so the parent reads a router handoff as an
interrupted `/prd` run and invokes that child directly, skipping `/brief`, its
own Phase 1, and the chain proposal. `/charter`'s row 8 matches
`wip/vision_<topic>_scope.md` exactly, the same filename `/explore` writes, and
jumps into `/vision` so no state file is created and `/strategy` and `/roadmap`
are never scheduled.

A third defect surfaced during design. `/scope`'s Phase 3 already contemplates a
Phase 1 bail and resolves it wrongly: it sets `triggering_child:` to the first
child in `planned_chain:` that has not completed, then instructs Phase 3 to
force-materialize that child's intermediate — a file that cannot exist, because
no child has run. The observed behavior of a Phase 1 bail today is a run that
stops at Phase 3 with a hard-finalization violation, no exit recorded, and the
state file left on disk with `exit: UNSET`.

## Decision Drivers

**The fix site is the shared contract, not the skills.** Every skill-local
change considered here leaves `references/parent-skill-pattern.md` asserting
something the skill no longer does. The pattern is where the model is stated, so
it is where the model gets stated.

**No judgment may run before the artifact it is about exists.** This is the rule
`PRD-scope-artifact-persistence.md` R28 already fences, and this change enforces
it rather than proposing it. Every design option is tested against it, including
options that look like ergonomics.

**Preserve the affordances that do work.** Research reversed the initial reading
that the chain proposal is inert. Bail is the author's only stop before the
first child writes, and Adjust is the only in-prompt route to correcting a
framing-shift answer, which is the override that fires `/brief` against a
settled BRIEF. Both stay, and both are made to function.

**A guard nothing can check is a comment.** The prohibition on worth-producing
skip reasons is the point of bounding the reason vocabulary, and free text is
what makes it unenforceable.

**The state file is durably public from feature-branch push.** Anything written
into it can name a private artifact type from a public repo, which is why
`/charter` keeps `/comp` out of it entirely.

**Two parents must read as one procedure.** Where `/scope` and `/charter` differ
today they differ silently. Each divergence this change touches either
disappears or gets stated as a per-parent property with both parents declaring
which they have.

**A precondition is not a signal.** An arm whose destination cannot parse the
input must not be reachable by a one-point scoring margin.

## Considered Options

Five decisions were decomposed in Phase 1 and evaluated at equal depth. Each
section names what was chosen, the alternatives, and why the alternatives lost.

### Decision 1 — What replaces the ten-type crystallize framework

**Chosen: two-stage scoring, with candidacy preconditions.** Stage 1 scores what
the exploration *is* — a competitive landscape write-up, a feasibility answer, a
single decision, a rejection, or work. Stage 2 runs only when stage 1 returns
work, and scores which parent receives it. Two preconditions govern candidacy
rather than weight: a qualifying PLAN on disk makes `/execute` a candidate, and
repo visibility makes competitive analysis one.

*Flat scoring over a combined outcome set* was rejected because it preserves the
current framework's worst behavior. Comparing alternatives is what every
exploration does, so the decision-record signal fires on nearly all of them and
competes on raw counts with signals of a different kind. Widening the board does
not separate the two questions; it mixes more of them. Two-stage scoring is also
cheaper per run — five tables walked on a terminal outcome against ten today.

*Gate-then-score* was rejected as over-generalized, though its core insight was
adopted. It is right that `/execute` must not be reachable by score: the PRD
says the arm is reachable only when a PLAN exists, and "only when" is a
precondition. But reaching the four terminal outcomes by predicate trades a
judgment guard for brevity on exactly the four outcomes where a wrong answer
writes a permanent document. Rejection versus lead exhaustion has no mechanical
detector and already carries a dedicated anti-signal.

Making the visibility check a precondition rather than an anti-signal fixes a
live defect rather than relocating one. Public visibility is already an
anti-signal and the demotion rule is absolute, so competitive analysis can only
rank highest when every other type also has a firing anti-signal — but a demoted
type is still offered as a selectable alternative when the recommendation is
presented, and choosing it still reaches a produce handler that refuses. As a
precondition it never becomes a candidate and is never offered.

The chosen option's principal cost is that a stage-1 error is unrecoverable at
stage 2: an exploration wrongly scored as a rejection never reaches the entry
points at all, where a flat board would at least have ranked them. This is the
one place the flat alternative is genuinely stronger. It is mitigated by running
stage 2 anyway when stage 1's margin is within one point, so a near-tie between
"a chain" and a terminal outcome presents both, and the author sees the entry
point that the close call nearly cost them.

The seven tiebreakers become seven, redistributed. Two die because both
branches now reach the same destination. Four survive re-pointed. One is
promoted into stage 1. Four new ones are needed, of which `/charter`-versus-
`/scope` at the multi-feature boundary is the load-bearing addition. One
survivor carries a hazard worth naming: the design-versus-plan tiebreaker's
question — does an upstream artifact already exist? — still matters, but its
consequence inverts. A PLAN on disk unlocks `/execute`. A PRD or DESIGN on disk unlocks nothing,
because the chain runs whole and consolidation reduces afterward. Re-pointing
that rule naively is the most likely route back to entry-altitude selection.

`--strategic` keeps its Phase 0 and content-governance roles and loses its thumb
on the scale. It is not merely a flag — it is also read from CLAUDE.md as a repo
default, so a biasing `--strategic` would pre-answer the router for every
exploration in a strategic-default repo. That is the shape this change removes
elsewhere: a classification made at entry deciding what runs later. Two live
cases make it concrete: an exploration in a strategic-default repo that
converges on one bounded feature must be able to reach `/scope`, and an
exploration launched tactical that discovers a thesis is needed first must be
able to reach `/charter`.

Complexity survives as an advisory surface and dies as a router input. The
complexity table answers "which command should I run?" before any exploration
exists, and it survives re-pointed and smaller: Medium's reason for existing was
the design-then-plan path, which evaporates. As a crystallize input it adds
nothing the accumulated findings do not carry and would put a second
classification vocabulary inside the one routing surface.

### Decision 2 — Where the handoff lives and what it carries

**Chosen: one parent-namespaced file per parent** —
`wip/scope_<topic>_handoff.md` and `wip/charter_<topic>_handoff.md` — matching
the existing `wip/scope_<topic>_state.md` convention, with one skeleton and one
parent-specific block.

*A single router-namespaced file* naming its intended parent is cleaner on
collisions and better when an author runs the other parent, but it pays for that
by widening two closed write-target sets so a parent may delete a third skill's
artifacts. That is a contract weakening bought for a convenience the chosen
option gets with one line of prose: a sibling-path notice.

*Keeping the existing per-child convention* and relying only on narrowing the
colliding rows was rejected on the requirement's own terms, and independently
because no narrowing exists that does not either read child file bodies or
depend on filesystem provenance.

One skeleton, two bindings, not two templates. Six sections carry material both
parents need in the same shape: provenance, the problem or theme statement, the
scope boundary, decisions already settled, coverage notes, and upstream
observations. Exactly one section differs because exactly one question differs —
the framing-shift answer for `/scope`, the thesis-shift answer for `/charter`.
`/scope` carries one additional block for shape signals that `/charter` has no
analogue for, because `/charter` runs no predicate walk.

The handoff carries predicate *inputs*, never verdicts. A verdict word in the
file invites a parent to copy it. So it carries the evidence the predicates are
computed from — the architectural alternatives the exploration left open, the
complexity signals it surfaced — and no material for the predicate that
cross-references the repo's directory structure, because that is a filesystem
fact the requirements bar.

### Decision 3 — How each parent detects the handoff

**Chosen: fill Slot 7 in both parents, placing `/charter`'s body as row 8.5
rather than renumbering the shared tail.** `/scope` fills the position already
reserved and documented as vacuous. `/charter` gains one row between its
`/vision` partial-run row and its topic-branch row, which is the slot-7
position, numbered fractionally so every existing citation of rows 9 and 10
stays true.

Both parents use the shared slot vocabulary. `/charter`'s SKILL.md maps slots 5
and 6 onto rows 5-6 and 7-8 and says slot 7 "is unfilled because `/charter` has
no feeder-doc case" — a sentence this change falsifies, and one that has to be
edited with the row rather than left behind.

*Renumbering `/charter`'s tail* was rejected because the tail is the shared
meta-ladder and renumbering disturbs `/scope` as well — a constraint `/charter`'s
own file already states as its reason for putting an earlier check inside an
existing row.

*Placing the handoff test inside `/charter`'s existing `/vision` partial-run
row* is the smallest-blast-radius option and the one the precedent most directly
supports: that row already matches the filename the router writes today, so a
disambiguation there resolves the collision and adds the detection in one edit,
with no new row and no template amendment. It was rejected because it makes the
two parents structurally different at the one surface the shared template exists
to keep the same. `/scope` would have a named slot-7 clause and `/charter` a
conditional buried inside a partial-run row, and it conflates two
unrelated conditions in one row, which is the defect the stated-skip rule was
written to fix elsewhere in the same parent. The blast-radius saving is real and
is the price paid.

*A pre-ladder check in both parents* was rejected, but not because it inverts
the ordering by construction — the option can be written with the re-entry
checks ahead of it. It loses because doing so makes it a second dispatch surface
that restates by hand what the ladder's first six rows already compute, and two
surfaces answering the same question is the shape this whole change exists to
remove.

The shared template gains one amendment: a parent may expand a body slot into
more than one numbered row, and the meta-ladder tail is identified by role and
by being last rather than by ordinal. `/charter` already ships ten rows against
the template's nine, so the amendment describes what is true as much as it
licenses the new row.

**Evaluation order.** A settled artifact wins. Slot 5 fires and Slot 7 is never
reached, because first-match-wins and the status-aware re-entry slot sits above
the feeder slot. The handoff has nothing to say about the artifact on disk,
being barred from carrying existence, status, or hashes, so it cannot be the
more current evidence. Two behaviors attach: the handoff is announced rather than
silently dropped, offered as context for the re-entry choice, and it is left on
disk so a later revise reaches Slot 7 on its own terms.

**What pre-loaded means.** Run Phase 0's setup obligations against the current
worktree, then enter Phase 1 with the handoff available to the discovery
prompts. The framing-shift question is still surfaced, as a confirmation rather
than a fresh ask, and the author's response is what gets recorded. The child-doc
globs are unchanged, because they are filesystem reads. The cold-start
projection is suppressed, because a handoff run is not a cold start. Two of the
three shape predicates accept the handoff's estimate with its stated reasons and
the third is recomputed against the tree; all three are re-evaluated against the
real PRD one child later regardless, which is what makes accepting an estimate
safe.

### Decision 4 — What Bail at Phase 1 does

**Chosen: narrow the wip-state test to the artifacts a child produced**, so a
Phase 1 bail reaches clean-cancel and the bail handler disposes of the state
file.

The narrowing is stated positively, and the positive form is load-bearing. The
live rule routes on a three-way disjunction (the state file, any child
intermediate, or any research scratch), and excluding only the state file leaves
the other two disjuncts to catch the handoff this change introduces at
`wip/scope_<topic>_handoff.md`. A router-fed run that bails at Phase 1 would then
reach abandonment-forced with a triggering child that never ran, which is the
defect being fixed, reachable only on the path this change creates. So: the bail
routes to abandonment-forced only on a child intermediate at
`wip/{brief,prd,design,plan}_<topic>_*` or research scratch at
`wip/research/{prd,design}_<topic>_*`. Nothing under the parent's own
`wip/scope_<topic>_*` prefix counts as evidence a child ran, because nothing
under that prefix is a child's output. `/charter`'s bail step already tests this
way, so the narrowing brings the two parents into agreement rather than moving
one of them.

The test and the deletion are inverses and are easy to transpose. The test
ignores the parent's whole prefix; the deletion touches one path inside it. A
clean-cancel removes `wip/scope_<topic>_state.md` and nothing else — the handoff
is carved out explicitly, in the shape the fold record's carve-out already uses,
because both the enumerated write-target set and the Phase 4 sweep are written as
the prefix `wip/scope_<topic>_*` and an implementer reading "disposes of the
parent's wip state" would sweep the prefix and destroy the handoff.

Every link in the defect was verified. The bail rule routes on a disjunction
whose first disjunct names the state file. Phase 0 writes that file
unconditionally before returning control, and its three early stops all
terminate before the write. No child has run, so no intermediate exists. The
hard-finalization check refuses the empty artifact list that results.

*Making abandonment-forced tolerate an empty artifact set* was rejected because
it spends the check that guards the other two exits to fix the one exit that
should not be taken here. Abandonment-forced exists to preserve a partial
artifact; at Phase 1 there is none to preserve.

*Moving the state-file write after the chain proposal* was rejected because
Phase 0's other obligations (slug validation, visibility detection, upstream
validation) all record into that file, and deferring the write means either
deferring them or holding them in memory across a phase boundary.

Three items travel with the fix. The Phase 3 branch that names the
about-to-be-invoked child as `triggering_child:` and instructs
force-materializing its nonexistent intermediate is deleted from both places
that carry it; it is the only text instructing a parent to materialize a file
that cannot exist. The clean-cancel eval scenario is added, its absence being
why the regression went unnoticed while the other parent grades its own
equivalent. And the disposal happens in the bail handler rather than Phase 4,
because Phase 4 does not run on a cancel, with clean-cancel named in the closed
write-target set so the deletion stays inside it.

The handoff artifact is not disposed of by a bail. It belongs to the router, not
to the parent, and leaving it is what makes a later invocation reach Slot 7
rather than starting cold.

### Decision 5 — The reason vocabulary and the entry key

**Chosen: a closed four-member vocabulary at the pattern layer**, with an
optional free-text sibling that is never the ground, and `child:` as the entry
key.

*An open list with a stated prohibition* was rejected because the prohibition is
the entire point. A grep can assert membership in a closed set; it cannot assert
the absence of a worth judgment from arbitrary prose.

*A structured reason with a typed qualifier* is the stronger of the two
alternatives and loses on a narrower point than ceremony. It is strictly better
on enforceability, since a typed qualifier is machine-checkable where an
optional free-text sibling is not, and it closes the public-surface argument completely
rather than mostly, because there would be no free-text field in the record at
all. It loses because the qualifier's type is heterogeneous across the four
grounds: a path for a supplied upstream, a prompt identity for a declination,
nothing at all for re-entry protection. Typing it honestly means a discriminated
union, which drags the conditional-field gating discipline down into a nested
list entry where the schema currently applies it only at the top level. That is
a real cost paid for a checkable qualifier nothing yet needs to check.

Four members ship, each with at least one current writer:
re-entry protection against a settled artifact at the canonical path; an
upstream supplied by the author; an author declination at a named confirmation
prompt; and a boundary rejection, whose qualifier is drawn from the existing
boundary enum so the closed set is two strings rather than an open one. A fifth
member proposed during requirements research is not shipped, because no writer
exists for it and none is latent.

The never-planned category survives the closed enum. A conditional feeder whose
gate never opened is a member of neither list, and the reason is unchanged by
bounding the vocabulary: the state file is durably public, and recording a
private-only artifact type there is a visibility violation whatever the reason
field says.

`child:` wins over `name:` on edit-site count and on reading consistently
against the sentinel's own `invoking_child:` field.

## Decision Outcome

The change lands in three layers, and the layering is the design.

**The pattern states the model.** A statement at the head of the Gate Vocabulary
says chain steps are mandatory and reduction is post-hoc, names the grounds on
which a child may legitimately not run, and is worded to be true of all three
parents — which forces it to say a parent *may* define a post-hoc reduction
mechanism rather than *shall*, because two of the three define none. The ALWAYS
declination clause is restated around three properties a conforming declination
has, each verifiable against the one live instance. The reason vocabulary is
closed. The prompt contract states that Adjust's reach into chain membership is
per-parent, and both parents declare which they have.

**The router routes to entry points.** Crystallize scores terminal outcomes,
then entry points, with candidacy preconditions for the two arms that cannot be
reached by score. The skill stops authoring durable chain artifacts and hands off
through a parent-namespaced wip artifact that carries conversation and never
filesystem state.

**The parents consume it, and the two rows that would have swallowed it are
narrowed.** Slot 7 fills in both, below re-entry protection, entering Phase 1
rather than skipping it.

Under that, three local repairs whose only relationship to each other is that
they are the same defect at different addresses: the Phase 1 bail, the orphaned
`chain_revised:` field, and the eval scenarios that grade the retired model.

One prerequisite sits ahead of all of it. `/scope`'s Phase 1 file contradicts
itself about `planned_chain` within fifteen lines: a child held back by re-entry
protection is dropped from the list in one passage and the list is "a constant"
in the next, and `/charter` resolves the same question the other way. Two
pattern-level statements this design writes depend on the answer — the
declination property that a declined child remains in `planned_chain`, and the
per-parent constancy claim — so the contradiction is settled first, in `/scope`'s
own file, and the pattern statements are written against the settled reading.
The resolution follows `/charter`'s: a child that was planned and then held back
stays in `planned_chain` and is recorded in `chain_skipped`, because the plan was
to run it. That keeps "constant" true in the sense the file means and makes the
two parents agree.

The eval work is not a trailing chore. The suite is the only executable
statement of what `/scope` should do, and three of its scenarios currently grade
the model the skill retired — so an agent optimizing against it is pulled
backward. The scenarios are corrected in the same change that corrects the
prose, and the scenarios that guard the model against regression are preserved
to the byte.

## Solution Architecture

### Layer 1 — the shared contract

`references/parent-skill-pattern.md` gains a model statement at the head of the
Gate Vocabulary section, a restated ALWAYS declination clause carrying the
three-property test, an amended prompt literal-form rule stating what Adjust
guarantees and what is per-parent, and a corrected parent roster naming
`/execute`. Two roster items are not mechanical and are resolved explicitly: the
child roster's cardinality, which omits the conditional feeder and does not say
whether the implementation-altitude child counts; and the dispatch mechanism,
stated as the Skill tool while the third parent dispatches through koto.

`references/parent-skill-state-schema.md` gains the closed reason vocabulary in
its chain-tracking section — the place a reader checking a state file arrives —
with the extension path stated as a citation to the existing grow-by-PR-review
precedent rather than as a second discipline. The triad contract states
`planned_chain` constancy as a per-parent property and names the never-planned
category as a first-class member. Its pre-dispatch description, which says a
parent advances `planned_chain` per dispatch, is reconciled with that.

`references/parent-skill-resume-ladder-template.md` gains the body-slot
expansion amendment.

`references/parent-skill-security.md` gains the new clause in its slug
re-validation enumeration, which today names two slots. This is a pattern-level
edit rather than a parent-level one, and it belongs in this layer: leaving it to
the parent layer would have the pattern enumerating two slots while both parents
implement three. The rule is restated in three places and all three move
together — the pattern-level enumeration, `/scope`'s resume file which restates
it under Slot 6, and `/charter`'s resume file which does not restate it at all
and gains a first statement covering its new row.

### Layer 2 — the router

`skills/explore/references/quality/crystallize-framework.md` is restructured
into two scored stages. Stage 1 carries five categories — four terminal outcomes
plus "a chain" — each with signal and anti-signal tables, four of them derived
nearly verbatim from the current ten. "A chain" is a scored category rather than
the residual, so the demotion rule applies to it symmetrically; as a residual it
could never be demoted below a clean terminal, which would privilege it on every
run. Stage 2 carries four entry points, with candidacy preconditions evaluated
before scoring.

`phase-4-crystallize.md` runs the two stages and reproduces the tiebreakers
rather than a subset — the current file reproduces three of seven, so the four
strategic-altitude discriminations exist only in the framework file and a run
following the phase file never applies them.

`phase-5-produce.md` shrinks to the router's arms. The five child-specific
handoff handlers collapse to two parent handlers plus the terminal handlers. The
handler that writes a durable DESIGN skeleton is deleted. The competitive
analysis handler becomes a route to the skill that already owns that path and
drives a jury and a lifecycle transition. `SKILL.md`'s routing tables, the
complexity table, and the detection algorithm are re-pointed, and its reference
table — stale by three files today — is corrected.

`phase-0-setup.md` carries two triages and the design touches both. The
artifact-type triage — three agents arguing among four `needs-*` labels before
Phase 1 runs — is removed outright; it is the router's job and it commits before
any research exists. The investigation-versus-breakdown-versus-ready triage is
already router behavior living in Phase 0, since two of its three outcomes route
out of the skill entirely, and it is kept with its outputs feeding the
crystallize step rather than routing on their own. That leaves one routing
surface, which is the point. The step's visibility-persistence sub-step and the
Phase 1 gate that hard-stops without it are preserved explicitly, because the
surgery is adjacent to both, and the Label Pre-Gate's provenance is restated: it
branches on labels the removed triage used to write, and after the change those
labels arrive only from a human or from roadmap decomposition.

`references/label-reference.md` moves with the triage. The two labels whose only
producer was the removed step are retired, the two skill-lookup rows that
already dangle are corrected, and the lifecycle sentence naming the producer is
re-grounded.

Two destinations in the routing tables name skills that do not exist. Both are
removed with the types they route: the framework's spike and competitive-analysis
rows are the only sites, and the spike arm keeps `/explore` as its author while
the competitive arm routes to the skill that owns the path.

Each arm's handover is stated where the arm is defined: the topic slug for both
parents, plus the roadmap or vision upstream flag where the exploration found
one, and a PLAN path for the execute arm. The strategy upstream the roadmap
handler passes today is retired rather than relocated — the strategic chain's
entry produces its own strategy, so handing one in would hand a parent an
artifact its own child writes, and an exploration that found one names it in the
handoff's prose instead.

The topic-branch interaction is resolved rather than deferred. `/explore` Phase 0
creates a `docs/<topic>` branch, and both parents' branch-matching rows resume at
Phase 1 on what an author experiences as a first invocation. Those rows sit below
Slot 7, so a handoff-fed run reaches the handoff clause first and the branch row
never fires; the residual case is an exploration that produced no handoff, where
resuming at Phase 1 on an existing topic branch is the behavior the row was
written for. The rows are left alone and the ordering is stated where a reader of
either ladder will find it.

### Layer 3 — the parents

Each parent gains a handoff-detection clause below re-entry protection, entering
its own Phase 1 with the handoff pre-loaded. `/scope`'s Slot 6.3 glob and
`/charter`'s row 8 condition are narrowed so neither matches a handoff while both
still match the interrupted-child run they were written for. The slug
re-validation rule extends to the new clause.

`/scope`'s bail handler narrows its wip-state test, the Phase 3 branch that
names a triggering child for a bail no child took part in is deleted, and the
stale prose beside the chain proposal is corrected: the justification that
`/scope` cannot produce a smaller artifact set, the direct-invocation redirect's
framing, the orphaned `chain_revised:` field, the unspecified second
confirmation on the post-PRD gate, and the reason-count claim.

`/charter`'s state schema stops listing the private-only feeder as a
`planned_chain` member, and its Phase 1 Adjust loses the ability to drop a child
while keeping its other powers — forcing a previously-skipped child on adds work
rather than removing it, so it survives.

The three child skills whose handoff detection names the router as producer are
re-grounded, and they do not all land the same way. After the path move the only
surviving producer of a child-level handoff is `/charter`, which pre-populates
the roadmap child's scope artifact itself — so the roadmap clause is re-grounded
on a producer that exists. `/vision`'s clause loses the router as a producer and
gains none, because `/charter` runs `/vision` directly rather than pre-populating
for it. `/prd`'s clause loses its only producer outright: `/scope` pre-populates
nothing. Those two clauses are retired rather than re-pointed, and their skills'
resume ladders lose the corresponding row. This is the largest downstream
consequence of the path move and is stated rather than folded into a sentence
about all three.

The parent's Slot 7 clause records what it consumed. A `consumed_handoff:` field
in each parent's state file names the path, written when the clause fires and
absent otherwise, so a resume can tell a run that consumed a handoff from one
that started cold. The field is specified in each parent's own state schema with
its reader named — the resume ladder — rather than left to be written by a phase
file and read by nobody, which is the shape of the orphan this same change
removes.

### Data flow

An exploration converges. Crystallize stage 1 asks what the exploration is; on a
terminal outcome the router records or routes and stops. On a chain outcome,
preconditions establish candidacy and stage 2 scores the entry points. The
router writes `wip/<parent>_<topic>_handoff.md` and names the command to run.
The author runs it. The parent's Phase 0 validates the slug, detects visibility,
and validates any upstream against the current worktree. The resume ladder is
consulted; a settled artifact wins if one exists, and the handoff is announced.
Otherwise Slot 7 fires, Phase 1 runs with the handoff pre-loaded, and the chain
proceeds as it always does.

## Implementation Approach

Five phases, ordered by dependency rather than by surface.

**Phase 0 — settle the `planned_chain` contradiction** in `/scope`'s Phase 1
file. It is two sentences, and both pattern-level statements in Phase 1 are
written against its outcome, so it goes first.

**Phase 1 — the shared contract.** The pattern, state-schema, ladder-template,
and security-reference edits. Everything downstream cites these, and doing them
first means the parent edits are conformance rather than invention. The two
parents' declarations of which Adjust they have land here too, because the
pattern's statement is what makes those declarations required.

**Phase 2 — the parents.** Handoff detection and the `consumed_handoff:` field,
the two narrowed rows, the parent-side half of the slug re-validation restatement,
the bail fix with its narrowed test and its three travelling items, and `/scope`'s
stale prose. `/charter`'s feeder-membership, slot-vocabulary sentence, and Adjust
corrections.

**Phase 3 — the router.** The crystallize restructure, the produce-handler
collapse, the durable-authoring removal, both triage changes, the label
reference, and the routing tables. This is the largest phase and the only one
that changes behavior an author sees on a first invocation.

**Phase 4 — the executable statement.** The eval work, in three groups: the
scenarios grading the retired absorbability model, which are broken today
independent of this change; the scenarios pinning surfaces this change moves;
and the scenarios that must survive byte-identical, which are verified rather
than edited. `references/pipeline-model.md` lands here too, because it restates
the router's model and cannot be corrected before the router is.

**What the phase boundaries do and do not guarantee.** The claim worth making is
narrow: a detection clause with no producer is inert rather than broken, so Phase
2 can land before Phase 3 and the parents simply never see a handoff. The
stronger claim — that every boundary leaves the corpus internally consistent —
is false at two of them, and pretending otherwise would be the kind of
unexamined assertion this change exists to remove.

After Phase 1 alone the shared contract declares a closed reason vocabulary and
one entry key while both parents still write outside them, which is a
conformance gap of exactly the shape the first decision driver names. After
Phase 2 the bail fix is correct only against the artifacts that exist at that
point; Phase 3 introduces the handoff, and if the bail's test were narrowed to
the state file alone rather than to the parent's whole prefix, Phase 3 would
re-break what Phase 2 fixed. Both are managed by ordering rather than dissolved
by it: Phase 2 follows Phase 1 closely enough that the gap is not observable to
an author, and the bail's test is written in its final positive form in Phase 2
rather than being tightened later.

The ordering has one hard constraint beyond that: Phase 4's third group is a
verification step, and running it before Phases 2 and 3 would verify nothing.

## Security Considerations

The pattern-level security surfaces this change touches are the closed
write-target set, slug re-validation on resume, the visibility boundary, and the
no-untrusted-input-interpolation rule.

**A new wip path enters two closed write-target sets.** The handoff artifact is
written by the router and deleted by each parent's wip sweep. Both parents'
write-target sets are enumerated and both gain one path, composed from the
validated topic slug and a fixed prefix. This is the argument that decided the
path shape: a router-namespaced single file would have required each parent's
set to admit a path in another skill's namespace, which widens the set from
"paths this skill composes" to "paths another skill composes", and a closed set
whose membership depends on a second skill's conventions is not closed in the
sense the rule means.

**Slug re-validation extends to the new clause.** Slugs recovered from on-disk
paths during a ladder match are re-validated against the slug regex before
interpolation into any emitted command or write path, and the rule currently
enumerates two slots. A handoff artifact is discovered by a filesystem match
exactly as those are, so the same path-traversal surface opens if the new clause
is omitted from the enumeration. This is the single most important security item
in the change, and it lands in `references/parent-skill-security.md` — the one
place the enumeration lives — plus the two parent files that restate it.

**The handoff is untrusted input, and is read rather than executed.** It is a
wip file that any process on the machine can write. Nothing in it is
interpolated into a shell command: the parent reads its prose into a discovery
conversation, and the one value that reaches a command — the topic slug — comes
from the parent's own validated argument, never from the file. The predicate
estimates it carries are advisory and re-derived against the real PRD one child
later. The upstream path, which does reach a committed frontmatter field,
travels as a flag argument through the parent's existing inbound validation
rather than inside the handoff, which is why the design keeps it out of the file.

**One handoff field reaches a gate, and the control on it is the confirmation.**
The framing-shift answer is not covered by the paragraph above: it is neither a
shell argument nor a path nor a frontmatter value, and it is the only carried
value that is not re-derived later. A positive answer is the override that fires
`/brief` against an Accepted BRIEF at the canonical path — the one thing in the
handoff that can defeat re-entry protection. The control is that the
pre-supplied answer is never accepted as recorded state. The question is
surfaced as a confirmation, mandatorily rather than as a formality, and the
author's response is what gets recorded; under a non-interactive run the
pre-supplied answer is taken and announced rather than applied silently. The
residual risk is low and the reason is worth stating: `/brief`'s own resume
ladder offers revise-or-start-fresh against an Accepted BRIEF, and its
finalization requires explicit approval for the Draft-to-Accepted transition, so
the worst case of a malicious handoff is a nudged prompt rather than a clobbered
artifact.

**A malformed handoff degrades to a cold start.** If the file is truncated,
unparseable, or missing the sections the clause expects, the parent announces
that it found a handoff it could not consume and proceeds as though none
existed. It does not attempt partial consumption, because a half-read handoff
would pre-supply some discovery inputs and not others with no way for the author
to tell which.

**The never-planned rule is what prevents the visibility leak; the closed
vocabulary does something narrower.** A `chain_skipped` entry keys on the child
name, so recording a private-only child names it whatever the reason field
holds. The mechanism that actually prevents the leak is the pattern-level rule
that a child whose gate never opened produces no entry at all and its skip is
stated conversationally, and this design preserves that rule rather than
replacing it with the enum. What the closed vocabulary genuinely buys is that a
*recorded* skip's ground can no longer carry arbitrary prose, and that it becomes
re-validatable on resume like the other state-file enums.

**The optional detail field is free text in a durably public record, and is
bound accordingly.** Shipping an enum alongside a free-text sibling would
otherwise reintroduce, in the same entry, what the enum was chosen to remove.
The sibling carries the same content discipline the existing free-text exit
field already carries in the other parent — no secrets, no
customer-identifiable context, no unpublished competitive positioning, and no
private artifact named from a public repository — and it is advisory only: any
check reads the ground, never the sibling.

**Clean-cancel deletes one file inside the closed set, and must not sweep the
prefix.** The bail handler disposes of `wip/scope_<topic>_state.md`, a path
composed from the validated slug and already enumerated, and leaves
`wip/scope_<topic>_handoff.md` in place so a later invocation reaches the
handoff clause rather than starting cold. The carve-out is stated in the shape
the fold record's already uses, because the enumerated set and the Phase 4 sweep
are both written as a prefix and a reader would otherwise sweep it. The other
parent's set is a closed list of concrete paths rather than a prefix, so it
gains the handoff path and a count change rather than a carve-out. Three
restatement sites move together — the authoritative enumeration in `/scope`'s
SKILL.md and its restatements in the exit-finalization and cleanup phase files,
which that file warns must not diverge.

**The handoff does not survive an abandonment-forced exit, and that is
correct.** Phase 4 removes the parent's wip prefix on every exit, with a
carve-out preserving child wip for resumability on abandonment. The handoff is
not child wip and is swept. An abandonment-forced resume matches the
status-aware re-entry slot against the force-materialized Draft and never
reaches the handoff clause, so nothing is lost — but the interaction is stated
rather than left for a reader to derive.

**No new external surface.** No network calls, no new binaries, no credentials,
no new file formats read from outside the repository. Every path this change
writes is composed from a validated slug or is a fixed constant.

## Consequences

### Positive

The corpus states one model in the document both parents inherit from, so a
third parent has something to conform to rather than two examples to
triangulate.

Two live misroutes are fixed. Both are reachable today by an author who runs
`/explore` and then a parent, and both silently skip a parent's entire discovery
phase.

A third defect found during design is fixed: a Phase 1 bail currently reaches a
hard-finalization violation rather than any of the three exits.

The router gets cheaper per run — five scored tables on a terminal outcome
against ten today — and stops offering an outcome it will refuse at produce
time.

The eval suite stops pulling agents backward, and the guard scenarios that
protect the model are preserved to the byte rather than rewritten.

### Negative

This is a large change across three layers, and Phase 3 is the largest single
piece. The router restructure touches a framework document, a phase file, nine
produce handlers, and the skill's own tables.

The handoff contract is specified but exercised only by its consumers. No run in
this change produces a handoff that a parent then consumes end to end, so the
first real use is the test.

Two parents keep a stated divergence rather than converging: Adjust reaches
chain membership in one and not the other. That is a real difference in what the
parents can do, and the change makes it visible rather than removing it.

The router's two-stage scoring makes a stage-1 error unrecoverable at stage 2.
An exploration wrongly read as a rejection never reaches the entry points, where
a single flat board would at least have ranked them alongside. This is the cost
of separating the two questions and it is paid on every run.

Two child skills lose their handoff-detection clause outright rather than having
it re-pointed, because after the path move nothing produces what they detect.
That is a capability removal, not a rename.

The eval suite still will not run on pull requests. This change makes the
scenarios agree with the skills; it does not change when they execute, so the
same drift can recur.

### Mitigations

The layering mitigates size to the extent the Implementation Approach claims and
no further: a detection clause with no producer is inert, so Phase 2 lands before
Phase 3 safely. The two boundaries where the corpus is briefly inconsistent are
named there and managed by ordering rather than by the claim.

The stage-1 error cost is mitigated by running stage 2 anyway on a margin within
one point, so a near-tie presents both the terminal outcome and the entry point
rather than silently resolving to the first.

The handoff's untested-ness is bounded by what it is allowed to carry. It cannot
supply artifact existence, status, hashes, or visibility, so a malformed or
stale handoff degrades to a discovery conversation with a wrong prior rather
than to a parent acting on false filesystem beliefs.

The stated divergence is mitigated by requiring both parents to declare which
Adjust they have, in their own chain-proposal sections, so an author moving
between them reads the difference rather than discovering it.

The recurrence risk is named in the PRD's Known Limitations rather than mitigated
here. A pull-request-time structural check is the obvious follow-on and is
deliberately out of scope.
