<!-- decision:start id="stage-1-replacement" status="assumed" -->
### Decision: What replaces the type-level first stage of the consolidation judgment

**Context**

`/scope`'s consolidation judgment runs as three stages at each hop after a child
lands. Stage 1 looks the hop up in a hand-maintained mapping table and asks
whether the downstream *type's* required sections have a home for every required
section of the upstream *type*. Neither document is opened, so the verdict is the
same on every run: `absorb` available at BRIEF-to-PRD, `keep` everywhere else,
permanently. R1 abolishes that test. Under the contribution model a home can
always be written, so absorbability stops being a property of the types and Stage
1's question has no content left.

The exploration concluded Stage 1 "very nearly dissolves." The residue is what
this decision settles. Research found that the stage is described as one thing
and does three: the type test R1 kills; **hop validity**, because the table is the
only place in the whole procedure that looks at which hop this is; and
**recording a first-stage `keep`**, which Phase 3 lifts into the PR body so a
reviewer can tell an absorbed artifact from one that was never produced. A pure
dissolution deletes the first and silently drops the other two.

Three facts verified during the decision reshaped it. First, the mapping table's
claim to be "derived from the per-type required-section contracts in
`crates/shirabe-validate/src/formats.rs`, not enumerated by hand" is false:
`formats.rs` holds only per-format `required_sections: Vec<String>` lists, there
is no mapping structure anywhere in `crates/`, and every semantic edge in the
table (User Outcome to Goals, Scope Boundary to Requirements-plus-Out-of-Scope)
is authored prose. The table also silently drops `Status` from the BRIEF's five
required sections. The re-derivation instruction it carries has never been
runnable. Second, **non-adjacent hops are reachable today and undefined.**
Combining re-entry protection with the four children yields `brief->design`,
`prd->plan` and `brief->plan`; `brief->design` is produced by shipped eval id 8
(`us-2-prd-auto-skip`), and the table has no row for it — an absent row is neither
total nor not-total, so the procedure has no defined next action. Third, and
decisively, **R15's citation check cannot cover those hops.** Eval id 8 ships
`"files": ["docs/prds/PRD-test-topic.md"]` — one file, no BRIEF — and
`crates/shirabe-validate/src/checks.rs` requires `upstream:` to resolve to a file
that exists on disk and is git-tracked, so that PRD cannot cite a BRIEF this run
creates. Generalised: R15 protects citers of the deletion target, the deletion
target at a non-adjacent hop is always minutes old, and a document written before
the run cannot cite one created during it. The sets are disjoint by construction.
All 36 BRIEFs in `docs/briefs/` sit at a settled status (35 `Done`, 1
`Accepted`), and both are settled for `/brief`'s re-entry protection, so every
pre-existing BRIEF is held back and can never be a run-produced upstream — the
disjointness is total, not partial.

The decision ran the full adversarial path with five persistent validators
through bakeoff, peer revision and cross-examination. Two advocates withdrew
their alternatives outright, a third withdrew its distinguishing content, and the
strongest argument for dissolution was authored by the validator arguing against
it.

**Assumptions**

- **The judgment's upstream is the edge this run drew, which is stricter than R2
  as written.** R2 says the judgment "SHALL fire only at a hop where this run
  produced both documents" — a necessary condition, not a sufficient one. On the
  eval-8 trace this run produces both the BRIEF and the DESIGN, so R2's literal
  text *permits* `brief->design`. The rule adopted here adds a second necessary
  condition. Two validators independently confirmed it is an addition rather than
  an interpretation. The DESIGN should state it as a refinement of R2 and carry
  its justification rather than let a reader mistake it for R2's plain meaning.
- **The DESIGN must settle what step 3 hands the child, and settle it in the
  invocation table's favour.** Phase 2's child-invocation table hard-codes
  `/design | docs/prds/PRD-<topic>.md` while the prose two lines above says the
  argument is "the path of the nearest artifact this chain produced above it."
  These disagree on exactly the eval-8 trace. Everything in this decision about
  non-adjacent hops is downstream of that one sentence. Under the table reading
  they never compose; under the prose reading they compose and reach the content
  question with nothing having checked the pairing.
- **R30's enumeration needs amending from five decision points to four.** This is
  required under every surviving answer and therefore cannot discriminate between
  them.
- Assumed the PRD's eval references are by JSON `id`, not array index. `id: 17` is
  `chain-shape-is-constant`, exactly as the PRD names it, and ids 18/19/20 are the
  three scenarios mentioning the mapping. If wrong, the rewrite set shifts by one
  and the conclusions are unaffected.

**Chosen: The citation preflight — R2's scoping moves out, R15's citation check
moves in**

Stage 1's type test is deleted along with the mapping table. The position
survives, renamed for what it now does, with content that is mechanical,
body-blind and type-blind. The judgment's three-stage shape is preserved:

**Outside the judgment — the firing condition (step 8).** The judgment fires only
when both endpoints of the edge step 3 drew were produced by this run. Concretely:
the upstream is the artifact path this run handed the child as its invocation
argument, and the judgment fires only if that artifact is one this run produced.
The predicate reads `chain_ran:` membership. When it does not hold there is no
hop, no `consolidation_judgments:` entry, and no verdict — a held-back artifact
was never a party to a judgment, and `chain_skipped:` already records why it was
held back. This is where R2's text already lives ("Skipped when this chain
produced no artifact above the current one"), now bound to a named field instead
of unbound prose.

Its justification is not caution about content loss but that the alternative
question is **ill-posed**. Stage 2 asks whether the upstream does work the
downstream does not, which presupposes the downstream could have incorporated it.
Where the downstream never read the upstream, absence is evidence of nothing and
`absorb` would be reached on a false inference. The predicate is "was this passed
as the invocation argument, and did this run produce it" — it reads no format
reference and no section list, so adjacency is a consequence rather than an input.
Non-adjacent hops never compose, rather than composing and being refused, which is
what keeps the rule clear of R1.

**Stage 1 — Citation preflight.** Its sole content is R15's citation search,
relocated to run before the content question. It searches the repository's
git-tracked files, excluding `wip/` and excluding the survivor of this fold, for
citations of the artifact that would be deleted. A path-exact hit downgrades the
verdict to `keep` through the existing abort path. A bare-name hit is carried
forward as a finding for the judging agent. It can return exactly two things,
"proceed to the content question" and `keep`, and it never opens either document.

Two independent arguments put the check here rather than at Stage 3. R15's soft
half — "a citation naming the artifact without its path SHALL be surfaced to the
judging agent as a finding and SHALL NOT by itself change the verdict" — is
unsatisfiable after the verdict, because R12 fixes the judging agent as the one
whose call the verdict is, and "by itself" is a contribution qualifier that
presupposes a verdict still forming. And a refusal reached before any mutation is
a clean abort with nothing to undo, which is the ordering Decision 6 reached
independently for the same reason. "Before deleting an artifact" is a lower bound
on placement, so running earlier satisfies R15 as written.

**Two structural clauses bound the position.** The stage carries a stated ceiling
— it is not capable of any outcome stronger than `keep`, in R15's own shipped
words — and an input restriction: **no check in the judgment may read either
type's required-section list, or compare the two types' section sets.** Chain
position and provenance are admissible inputs; a type's content contract is not.
The test for a violation: a condition that refuses one pair while permitting its
structural twin under identical repository state is a type rule. The input
restriction is written at the head of the *content* stage as well, because that is
the stage that can return `absorb` and no ceiling applies there.

**Fail-safe.** The preflight fails toward `keep` when its search cannot complete —
the git-tracked file set is unreadable, or the deletion target's repo-relative
path cannot be composed. That is what makes the PRD criterion "a hop whose first
stage cannot reach a verdict leaves both documents on disk" implementable: the
stage has exactly one mechanical operation, and its failure to complete is
observable rather than inferred.

**Rationale**

The type test dies unanimously; the question was only what occupies its position,
and the round answered it by elimination. Every candidate subject for a surviving
stage was eliminated by a validator other than its advocate. R2 in the stage was
eliminated by a dilemma no one rebutted: drawn from the run-produced set the
ownership check can never fire, which is the shape `phase-1-discovery.md`'s own
maxim forbids ("a check that can never fire teaches the next maintainer that the
case is possible"); drawn from disk it writes a verdict into the PR body about a
document the run never owned. R3/R5 preconditions were eliminated as duplication —
R5's heading has a `[mech]` owner because R8 puts it in the validator, R3 is
backstopped by R14's carry check with shipped fail-toward-keep wording, and the
PRD already assigns both conformance criteria to `[insp]` and `[mech]` owners.
Their last defender conceded them without reservation in cross-examination. A
type-shaped refusal of non-adjacent hops was eliminated by its own author, after a
peer showed the discriminating conjunct is entailed rather than independent: a
non-adjacent hop arises only from a middle child absent from `planned_chain:`,
Phase 1 writes exactly one skip reason, and that reason *requires* a settled
artifact at the canonical path — so the gap is occupied by construction whenever
the check runs, making it extensionally identical to an adjacency rule.

What survives elimination is the citation check, and it is a better occupant than
anything the advocates proposed for the position. It is required anyway, it is
mechanical rather than a judgment, it reads no document body and no section list,
it carries its own fail-toward-keep ceiling in shipped requirement text, and
placing it here is the only placement under which R15's soft half means anything.

Dissolution was the serious rival and lost on one point. It does not remove the
attractor that filled this position once already with a hand-authored type table
carrying a sincere and false provenance claim — it relocates that attractor to the
head of the content question, which is the stage that *can* return `absorb` and
where no ceiling applies. A type-shaped shortcut is worse there, not better. The
dissolution advocate's counter — that a type check is idiomatic inside a
pre-filter and jarring at the top of a stage contracted to read both bodies — is a
claim about what a later maintainer will find natural, and it is outweighed by the
mechanical protection a stated ceiling provides. The input restriction is adopted
at both positions precisely because that argument has force.

The two answers are otherwise the same procedure, and the round converged there
rather than splitting. The remaining difference is whether the first position
carries a stage label. It is kept because the PRD's acceptance criterion speaks of
"a hop whose first stage cannot reach a verdict" and needs a referent, because
eval id 20 keeps its shape as a verdict reached before the bodies are read, and
because a labelled position with a written ceiling is a smaller target than an
unlabelled ordering convention.

**Alternatives Considered**

- **Full dissolution.** Stage 1 deleted outright; the judgment becomes the content
  question plus the carry check. Rejected because it relocates the type-shaped
  attractor to the head of the content stage, where no ceiling applies and the
  stage can return `absorb`; and because it drops the recorded first-stage `keep`
  that Phase 3's PR-body record and eval id 20 both consume. Its advocate held at
  0.85 and contributed the round's most useful finding on the Floor.
- **Eligibility precondition** (run ownership plus R3/R5 in the stage). Withdrawn
  by its own advocate, which conceded R2 to the firing-condition split, dropped
  its positional-nearest premise, and dropped R5 and then R3. Its closing words:
  "almost nothing of mine survives that the split lacks."
- **Mechanical pre-filter** (defined by output algebra). Withdrawn as a distinct
  alternative by its own advocate, which called it "an ordering claim wearing a
  stage's clothes." Its two clauses — the ceiling and the input restriction — are
  adopted above; the input restriction was re-stated mid-round after its original
  wording was shown to bar composing the hop identifier at all.
- **Split the firing condition from the precondition.** Adopted in substance;
  this is the structure of the chosen answer. Rejected only in its surviving
  content: its interposed-artifact check was withdrawn under the entailment
  argument, and its R3/R5 preflight was conceded away, leaving the split itself.
- **Hop resolution and normalization.** Rejected because composing the `hop:`
  identifier is a record-writing step rather than a decision point, and because
  the edge rule settles the hop at step 3 before the judgment starts. Its
  advocate revised from a stage to "a named resolution step" and then endorsed the
  citation check as "a better first-stage occupant than anything I proposed." Its
  R3/R5 objection is the one position held unqualified across all three phases and
  it carried.

**Consequences**

**What `consolidation_judgments[].absorbable` becomes.** It is retired, not
re-annotated. Under R1 it would be `true` at every hop it could ever be written,
and its shipped annotation — "is the required-section mapping total?" — is the
deleted model sitting in the machine-readable contract that R25 names. Not one of
the five validators kept the name. It is replaced by `stage: preflight | judgment
| carry`, naming the stage at which the entry's verdict was settled: `carry` on a
completed absorb, and on a `keep` the stage that produced it. This is strictly
more informative than the boolean it replaces — it answers the question the PR-body
reviewer actually has — and it is free, because the procedure has never executed
and there are no entries on disk to migrate. `hop:` and `verdict:` should also
join the enum re-validation list in Phase 2, which today covers four fields and
omits `verdict:` despite the schema declaring it an enum.

**What the Durable-Artifact Floor section becomes.** Its premise is falsified —
the condition it says "cannot hold" now holds — so the section is replaced rather
than edited, and it moves from `phase-1-discovery.md` to Phase 2 beside the
judgment. Its `/plan` redirect goes with the premise: an author wanting no durable
record no longer has to leave `/scope`, so the escape hatch describes a state of
affairs that no longer exists. The no-guard *instruction* survives with a
corrected reason, sited in Phase 2 because that is where the unguarded temptation
lives — the Phase 1 form (an entry-altitude shortcut) is already forbidden by R28
and already graded by eval id 17, while "never absorb the last one" is actionable
only where the absorb happens and nothing catches it. Verbatim:

> **There is no durable-artifact floor.** A run can absorb its way down to a
> single surviving artifact, or to none once the PLAN is implemented, and that is
> a reachable outcome rather than a defect. Do not add a guard that forces `keep`
> on the ground that the survivor would be the last artifact. R27 will not catch
> such a guard — a mechanism whose only possible effect is to force `keep` does
> not count as a second reduction mechanism — so this prohibition has to be
> written down rather than derived. It is wrong for two reasons. It would decide a
> fold from the artifact *set* rather than from the two documents at the hop,
> which is what R1 moved the verdict away from. And it would fire at exactly the
> DESIGN-to-PLAN hop R11 requires to be absorbable, closing by a second route the
> floor R1 opened. A chain that folds everything away is handled downstream by
> `/execute`'s finalization guard reading the seeded `exit_artifacts:` contract,
> not prevented here.

That R27 does not forbid a floor guard is the round's sharpest single finding, and
it is why deleting the section outright was rejected: the guard now looks
*reasonable* to anyone not told why it is forbidden, so the instruction is needed
more than it was, not less. The prohibition should also become a graded
expectation on rewritten eval id 18 — "Plan does NOT add a check that forces
`keep` on the ground that the survivor would be the last artifact" — so it is a
tripwire rather than ungraded phase-file prose.

**`chain_ran:` is specified, consumed, and written nowhere.** Verified directly:
`state-schema.md` defines it, Phase 3 reads it in four places (R9 Part 3's
chain-membership gate, the PR-body record copying "every artifact in
`chain_ran:`", the R8 tie-break's per-child start timestamps, and the
`plan_execution_mode:` presence check), and no instruction in any `/scope` phase
file appends to it. The firing condition reads that field, so **this work must
create its write site** — in Phase 2's existing loop step 6, alongside the child
snapshot, with entries carrying a started-at timestamp so that
`phase-3-exit-finalization.md`'s existing claim about reading timestamps out of
`chain_ran:` becomes true rather than staying contradicted by `state-schema.md`'s
declaration of a bare name list. This is a PLAN item and it is a prerequisite, not
an adjacent cleanup: without it the hard-finalization check gates on a field
nobody populates. Adding it also resolves the `child_snapshots:` ambiguity for
free — Phase 1 and Phase 2 write that block in byte-identical shape with no
discriminating field, and `chain_ran:` membership is the discriminator, so no new
snapshot field is needed and the fix there is prose.

**R30's enumeration collapses to four.** With R3/R5 out of the stage, "the
replaced first stage" and "the citation check" name one mechanism at one address.
The corrected enumeration is: *the citation preflight, the carry check,
post-absorb re-validation, and record production.* The acceptance criterion
retargets from "the replaced first stage" to the preflight, and remains
implementable as stated. This amendment is needed under dissolution too, which
drops the item rather than merging it, so it is not a cost this answer carries
alone. Note for the amendment: R30's five items have never mapped to five stages —
the carry check and post-absorb re-validation both live inside today's `### Stage
3 — Carry check and absorb`, whose step 4 runs the validator and reverts. The list
constrains fail-safe direction item by item and says nothing about placement.

**R15's coverage bound belongs in the DESIGN.** R15 protects deletion targets that
pre-existed the run and structurally cannot protect deletion targets the run
created. Coverage is zero by construction wherever the upstream is run-produced,
which under R2 is every hop the judgment can fire at. Coverage is high in the
narrower case where a settled document in the gap cites a target that pre-existed.
R30's fail-safe inventory currently reads as though the citation check covers
every deletion, and it does not. The firing condition is what closes the exposure;
the citation check is a guard against stranding external citers, not a hop-validity
check, and the DESIGN should not let the two roles blur.

**What gets easier.** Every hop's verdict is decided by the two documents in front
of it, and the mapping table with its false provenance claim leaves the tree. Evals
18, 19 and 20 are rewritten without a type-level mapping check, and 20 keeps its
shape — a verdict reached before the bodies are read — with its trigger changed
from an unmapped mapping to a path-exact citation. Eval 17 is untouched, which is
what the R28 tripwire needs.

**What gets harder.** The judgment now depends on a state field this work has to
create, which makes an unpopulated `chain_ran:` a live failure mode where before it
was latent. The firing condition is stricter than R2's literal text and the
divergence has to be stated rather than absorbed silently. And the position at the
head of the judgment still exists, which is a place a later maintainer can put a
cheap type comparison; the ceiling and the input restriction are what stand in the
way, and both are prose in a phase file rather than anything a machine checks.
<!-- decision:end -->
