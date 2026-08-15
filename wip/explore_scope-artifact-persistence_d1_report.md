<!-- decision:start id="contribution-section-depth" status="assumed" -->
### Decision: Depth expectation for contribution sections

**Context**

Under the contribution model, a document that absorbs an ancestor carries that
ancestor's contribution as one compact section ahead of its own content --
BRIEF/WHY, PRD/WHAT, DESIGN/HOW, PLAN/WHEN-as-sequence, illustratively. Every
fold is a distillation and lossy on purpose. That removes the signal the
current mechanism actually uses. Stage 3's carry check today asks "did upstream
section X arrive at survivor section Y," a question with a findable answer
because the content was meant to survive intact. Under distillation the section
is present and shorter by design, and length carries no signal at all. The
question is whether anything beyond presence can be asserted, and by whom.

The framing that motivates presence-only is: "presence is the whole of what
static validation can assert." That premise is true and the inference from it
does not hold. `crates/shirabe-validate/src/formats.rs` carries
`required_sections` checked by FC04 (presence, error) and FC15 (relative order,
notice), and that is the entire content surface -- no optional sections, no
conditional sections, no length rule. But no content criterion anywhere in this
repo is machine-checked. The BRIEF jury's "Problem Statement states a problem,
not a smuggled solution," `/prd`'s "could someone write a test plan from the
acceptance criteria alone," `/design`'s strawman check, STRATEGY's Strategic
Context contract -- all of them are prose an agent applies, none of them
machine-checked, and none of them concluded that presence was therefore the
whole spec. "The machine can only check presence" is a fact about the tooling,
equally true of every quality rule already shipped.

Two constraints bound the answer and neither bites the way it first appears.
The single-mechanism constraint is worded identically in three places
(`skills/scope/SKILL.md:433-452`, the #260 PRD at `:326-338`, the #260 DESIGN
at `:130-146`) as *only one thing may reduce the artifact set* -- not "only one
place may decide anything." A verification step inside the one mechanism does
not count, and Stage 3's existing carry check is proof by construction: it is a
verification step inside the judgment that gates the `git rm`, and it shipped
in the same design that killed the entry altitude. It already has a schema slot
(`state-schema.md:71-89`), an abort path (`carried: false` downgrades the
verdict to `keep` and deletes nothing), and it already sits strictly before the
`git rm`. An adequacy expectation is therefore an amendment to a mechanism that
exists, not a new one. The #260 principle about judgments running before their
artifact exists is likewise untouched: this judgment runs after both bodies are
written.

**Assumptions**

- **The contribution section is authored by the child at drafting time, not by
  the parent at fold time.** This extends the pattern `/prd` Phase 3.2 already
  runs, where the PRD draws four sections from its upstream BRIEF's body and is
  told explicitly that doing so is what makes the downstream consolidation
  judgment usable. If wrong -- if the parent authors the section during Stage 3
  -- the criterion's *wording* is unaffected but its *placement* changes: it can
  no longer ride the child's existing jury, nobody reviews the prose, and the
  self-grading weakness already recorded as a known limitation (#260 PRD:370-373,
  DESIGN:761) gets materially worse. In that case Alternative 3's fold-time
  reviewer becomes the right answer rather than redundant. This fork is
  genuinely open and may not be this decision's to settle; the recommendation
  below is written to be re-placeable without being re-worded.
- **"The question the type owns" is meant per-type (Why / What / How /
  sequence), not per-document.** If it is per-document -- answer the question
  *this specific ancestor* answered -- the criterion is harder to game and
  harder to state as static prose, since the question varies per run.
- **The absorb procedure's known bugs are fixed separately.** In particular the
  step-4 re-validate that checks only the survivor. The mechanical backstop
  below rides that revert path and inherits whatever state it is in.
- Issue #280's body was not readable from this worktree. Its framing is taken
  from the exploration artifacts; every constraint cited above is read from
  committed files.

**Chosen: Consumer-anchored standing-alone test**

A contribution section has a real adequacy expectation. "One section, essence
only" is the shape, not the whole specification. The expectation has three
parts and adds no new substrate.

*The criterion is two-sided.* Copied in shape from the STRATEGY skill's
Strategic Context contract, which is a contribution section in all but name and
already ships: "If the section reads like a re-write of the upstream, fold it
back; if a reader can't follow this document's argument without first reading
the upstream, expand" (`strategy-format.md:348-352`). The second clause is the
anti-thin half, and it is load-bearing precisely because it is phrased against
the *survivor's own content* rather than against an abstract sufficiency. A
one-line topic restatement fails it the moment the survivor's later sections
lean on something the contribution never established. The single-sided
formulation -- "a reader who never saw the original can answer the question the
type owns" -- does not have that property.

*It is anchored to named consumers rather than an abstract reader.* Two are
real and identified. DESIGNs and PLANs cite requirements as bare `R<n>` numbers
that resolve against the PRD (`design-format.md:166-169`,
`plan-format.md:208-218`), so a carried What that drops the numbering orphans
every citation below it. And `/execute` seeds CI lifecycle validation on the
surviving DESIGN as the chain's durable anchor (`execute/SKILL.md:529, 543-548`),
so a carried What in a DESIGN is what a later reader gets forever. The
criterion names these, and carries a good/bad discriminating example pair in
the manner of the BRIEF jury's problem-versus-missing-feature pair -- the shape
that demonstrably works cheaply in this corpus.

*It lives in the existing mechanism, stated in three places.* A content rule in
the format reference, a drafting instruction where the section is authored, and
a criterion the authoring artifact's own jury applies. Those are the same three
places STRATEGY states its version, and STRATEGY's jury reviewer is already
handed both documents (`strategy/phase-4-validate.md:196-197, 219-230`), so the
independence a fold-time reviewer would buy is already purchased one phase
earlier with a spawn already budgeted. Stage 3's carry check keeps its schema
slot, its abort semantics and its position before the `git rm`; its rows change
from "did upstream section X land at survivor section Y" to "did ancestor type
T's contribution arrive as one section meeting the criterion."

One mechanical backstop rides along: a citation-resolution rule in `shirabe
validate` that fails when an `R<n>` cited in a document does not resolve inside
that document or its surviving upstream. This is not a depth check and must not
be sold as one -- it catches exactly one inadequacy, a contribution that
dropped the requirement numbering. It is worth having because it is the only
depth expectation in this problem with a machine check available, and it plugs
into the absorb's existing step-4 revert-on-non-zero path with no new
machinery. D4 ("new correctness checks belong in `shirabe validate`") puts it
exactly there. It also closes a failure that is silent by construction today.

Explicitly not adopted: any word count, line minimum or length floor. The only
numeric length criterion in the corpus (R19 budget-vs-spec,
`design/phase-6-final-review.md:78-81`) flags *over*-length and only
heuristically, and `design-format.md:274-286` says outright that "a DESIGN that
opens by citing its PRD's requirement numbers loses nothing." Under a model
whose whole point is compression, a floor inverts the incentive the feature is
built on, and padding satisfies it at zero cost.

**Rationale**

The stakes as posed were: can a reviewer ever call a carried Why inadequate, or
does any non-empty Why pass? The shipped design that created the consolidation
judgment answers this directly. Its D5 principle reads: "A recommendation that
content be carried forward is what already failed. Absorption is only
legitimate when something checks, section by section, that the content arrived."
Presence-only is the closest of the five alternatives to the shape D5 rejects --
"the heading exists" is very nearly "nothing confirming the transfer." Adopting
it would hollow out the carry check while keeping its shape, which is a
regression against #260 rather than a neutral simplification of it. The carry
check would still run, still produce a table, still gate the `git rm`, and
still mean nothing.

The recommendation wins on three grounds beyond that. It is not invented: the
repo already ships this exact answer for the strategic chain, dogfooded, in a
contribution section with the same job, and the tactical chain can copy the
wording rather than derive it. It costs nothing new: no scored rubric, no new
gate shape, no extra spawn, no artifact type -- which is what D4's "no new
substrate" asks for. And it is honest about what compression means: the
two-sided phrasing is the only formulation among the alternatives that says
"too long" and "too thin" in the same breath, which is exactly the shape a
criterion needs when the goal is distillation rather than transfer.

The accepted trade-off is that omission remains the residual gaming vector. An
agent that writes one fluent paragraph and silently drops the one contested
thing the ancestor settled is not caught by any of this, because the folding
agent cannot see the absence it created. That is the sincerity-drift failure
already on record as a known limitation of the carry check. The two-sided
clause narrows it -- an omission the survivor's later sections depend on
surfaces as a reader who cannot follow the argument -- but does not close it.
Closing it fully needs Alternative 3, and the case for paying that price rests
entirely on the authorship fork above.

**Alternatives Considered**

- **Presence only.** "One section, essence only" is the whole spec; any
  non-empty contribution passes. Rejected because it contradicts the shipped D5
  principle head-on -- it turns the carry check into a heading count while
  keeping its table, its schema slot and its abort path, so the mechanism keeps
  its shape and loses its content. The premise that motivates it ("presence is
  all static validation can assert") is true of every quality rule already
  shipped in this repo, none of which drew that conclusion.

- **Stated adequacy rubric, machine-unenforced.** Named dimensions the folding
  agent grades against, recorded per dimension. Rejected because the repo has no
  scored rubric anywhere and its functional tests and discriminating-example
  criteria demonstrably work; a dimension set is new substrate that buys nothing
  the two-sided test does not, and it is gamed by the same omission vector while
  reading more rigorous than it is.

- **Independent fold-time reviewer agent.** A subagent spawned by Stage 3, handed
  the original and the contribution, gating the `git rm`. Rejected as a standing
  requirement -- not as a bad idea -- because the independence it buys already
  exists one phase earlier: wherever the child authors the contribution, the
  child's own jury reads the upstream and the draft together, which is precisely
  the comparison this reviewer would perform, with a spawn already budgeted. It
  would also be the repo's first agent-gated deletion (existing `git rm` paths
  are gated by an explicit human verdict), a genuinely new supervisory shape.
  This alternative becomes the right answer if the authorship assumption above
  is wrong.

- **Self-contained test as worded.** "A reader who never saw the original can
  answer the question the type owns." Rejected in its single-sided form because
  it is satisfiable by a one-line restatement of the topic: the question is
  stated at type altitude, so any statement at that altitude formally answers
  it. Adopted in substance -- the recommendation is this test, made two-sided
  and anchored to named consumers, which is what makes it bite.

**Consequences**

A reviewer -- human or agent -- can call a carried contribution inadequate and
abort the fold, through the abort path that already exists. `carried: false`
keeps its meaning: verdict downgraded to `keep`, finding recorded, nothing
deleted. The failure stays auditable rather than silent.

The design must state the criterion in three places rather than one, and must
supply the discriminating example pair. That is writing work, not machinery.
The wording can be lifted from `strategy-format.md:348-356` and
`design-format.md:274-286` rather than derived, which also keeps the tactical
and strategic chains saying the same thing about the same shape.

One new validator rule is created (citation resolution), which is the first
machine check on a content relationship in this repo and closes a failure that
is silent today: nothing currently validates an `R<n>` citation anywhere, so
absorbing a PRD orphans every downstream reference undetectably. It will also
fire on documents already on disk that carry dangling references, which needs a
rollout call the design should make deliberately.

What stays open and is made visible rather than resolved: the authorship fork
(child at drafting time versus parent at fold time), which determines whether
the criterion rides an existing jury or needs Alternative 3's reviewer; and
whether the expectation should be uniform across hops, given that a fold into
the PLAN puts the distillate in a document that is `git rm`'d at implementation
on a branch the org squash-merges -- so on that path the content exists nowhere
reachable from main. Relatedly, the #260 PRD's stated recovery path ("the
commit history is the recovery path", `:304-306`) holds only while the feature
branch lives; after squash-merge an absorbed original never existed on main.
That is a real correction to an assumption the prior artifacts carry, and it
raises the price of every inadequate contribution rather than changing which
alternative wins.
<!-- decision:end -->
