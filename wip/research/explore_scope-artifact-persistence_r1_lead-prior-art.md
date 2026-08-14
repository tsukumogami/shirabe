# Lead: What did the consolidation change (#260) already settle, and was the permanent-PRD-and-DESIGN floor seen and accepted at the time?

Short answer up front: the floor was seen, argued explicitly as its own
numbered decision with four options, and accepted deliberately. The specific
move issue #280 now wants — rolling content forward at every hop so a small
run can leave nothing durable — was considered under that decision and
rejected by name. The rejection ground is that the PLAN is deleted at
implementation, so absorbing durable content into it destroys the record of
why the work happened. That ground does not depend on how authors reach
`/scope`, so "`/scope` is now the default front door" does not by itself
answer it.

## Findings

### 1. The PRD's Decisions and Trade-offs section — six decisions, not four

`docs/prds/PRD-scope-consolidation-over-skipping.md` (status: Done) closes
its deferred questions in six bolded paragraphs. The BRIEF's Downstream
Artifacts section says the section "closes the four questions this brief
deferred"; the shipped section carries six.

**(a) "Consolidation and consumption are both needed; they are not
alternatives."** Reason given: "Consumption alone leaves two documents saying
the same four things, which is the reader's actual complaint. Consolidation
alone would try to absorb a BRIEF into a PRD that was written without reading
it, so the carry check in R10 would fail most of the time. Consumption is what
makes absorption reliably available; absorption is what removes the second
document. R6 and R7 ship together."

**(b) "One mechanism reduces the set, and it runs after the fact."** This is
the entry-altitude removal. Verbatim:

> An earlier revision of this PRD gave `/scope` an entry altitude chosen once
> in Phase 1, on the reasoning that a question about the conversation an
> author is having is answerable when a question about an unwritten document
> is not. It was rejected: it is still a decision that shrinks the artifact
> set before any artifact exists, which is the exact shape this feature
> removes, and having two reduction mechanisms operating at different times
> made neither one legible.

And the cost is stated in the same paragraph: "two of the four artifact-set
outcomes are no longer reachable through `/scope`. Because no hop above
BRIEF-to-PRD is absorbable (R9), a `/scope` run ends with either all four
artifacts or the chain minus an absorbed BRIEF. A DESIGN-and-PLAN run, or a
PLAN alone, is reached by invoking `/design` or `/plan` directly."

**(c) "Absorbability is derived, not enumerated."** R9 states the rule in
terms of whether the downstream type's required sections have a home for the
upstream's. "Applied to the current schemas that yields exactly one absorbable
hop, BRIEF to PRD... Stating the rule rather than the answer means the set
changes correctly if a schema ever does."

**(d) "A run must leave something durable."** Verbatim: "R14 forbids reducing
to a PLAN alone from an entry above `plan`, because the PLAN is deleted at
implementation and the run would leave no record of why the work happened.
Entering at `plan` is still allowed: an author who says the work needs no
record beyond the code is making a claim they are entitled to make, and the
run says so out loud first."

**(e) "Re-entry protection stays, under its own name."** The complaint "was
never that this behavior is wrong; it was that its name and its recorded
reason made it look like a judgment about whether the artifact was worth
writing."

**(f) "Verification is split."** R10's carry check is semantic and belongs to
the skill; R12's upstream-resolution check is structural and belongs to
`shirabe validate`.

R14 itself is the floor as a requirement: "A `/scope` full-run SHALL leave at
least one durable artifact. This follows from R9 rather than needing its own
guard... A run that leaves no durable artifact is not reachable through
`/scope` at all."

### 2. The DESIGN — nine decisions; two of them are directly on point

`docs/designs/current/DESIGN-scope-consolidation-over-skipping.md`
(status: Current, complexity: Complex, decision_provenance: inline-resolved).

Decision Outcome, in summary: `planned_chain:` is `[brief, prd, design, plan]`
on every invocation minus re-entry-protected children; per-hop gates removed;
children invoked through their existing upstream-path input modes; a per-hop
consolidation judgment after the R20 file-existence check and validator
pass-through; `/brief`'s fold-into-PRD branch retired; `shirabe validate`'s
upstream-resolution check generalized from Plan docs to all formats.

**Decision 1 — what replaces the produce-or-skip gates.** Chosen: run all four
children every invocation, fold pairwise as each artifact lands. Rejected:

- Option B, an entry altitude chosen once in Phase 1: "This shipped in an
  earlier revision of this design and was withdrawn. It reaches all four
  artifact-set outcomes, and the question it asks the author is genuinely
  answerable — it is about the conversation they are having, not about an
  unwritten document. But it is still a decision that shrinks the artifact set
  before any artifact exists, which is the shape this design exists to remove,
  and it left two reduction mechanisms operating at different times so neither
  read as the rule."
- Option C, richer per-hop gate signals: "Whatever the signal, the gate still
  fires before its artifact exists."
- Option D, delete redundant artifacts once at the end: re-pointing cascades
  across the whole set at once, and the author sees the reduction long after
  the conversation that justified it.

**Decision 4 — what absorb can mean against fixed required-section schemas.**
Chosen Option A: "absorb is available only at a hop where a total mapping
exists from every required section of the upstream type into the required
sections of the downstream type... Where no total mapping exists, the
judgment's only available verdict is `keep`." Rejected alternatives, which are
exactly the two ways to loosen the test:

- Option B, grow the DESIGN schema with optional Requirements and Acceptance
  Criteria so a PRD can be absorbed: "A per-type schema variant, which PRD R19
  forbids, and it turns DESIGN into a PRD with extra sections rather than
  reducing anything."
- Option C, allow a lossy absorb that records what was dropped: "Trades a
  document a reader must read for content a reader cannot read. The complaint
  was repetition, not volume."
- Option D, hard-code "BRIEF folds into PRD": "Correct today by accident."

The mapping table is stated in the DESIGN: BRIEF→PRD yes; PRD→DESIGN no
("Context and Problem Statement only" is the sole home); DESIGN→PLAN no
("none").

**Decision 8 — the durable-artifact floor.** This is the decision #280 has to
answer. Chosen Option A: "the floor is structural, and no guard implements
it." Rejected:

- Option B, an explicit guard: "Dead code. The guard's condition cannot hold
  given Decision 4, and a check that can never fire teaches a later maintainer
  that the case is possible."
- Option C, allow a PLAN-alone `/scope` run behind a warning: "Requires an
  altitude selection to reach at all, which Decision 1 removed."
- **Option D, make DESIGN absorbable into PLAN so the shortest outcome stays
  reachable: "The PLAN is deleted once its work is implemented, so this trades
  a durable audit trail for a shorter run and loses the record of why the work
  happened."**

Closing prose on Decision 8: "The PRD asks for the PLAN-alone answer to be
stated deliberately rather than left to fall out of the model, so: a `/scope`
run never produces it. An author who genuinely wants no durable record beyond
the code invokes `/plan` directly, which is a claim they are entitled to make
and which is visible in what they typed."

**Decision 9 — generalization to `/charter`.** Stated in prose only, no
behavior change: the mapping test yields zero absorbable strategic hops, so
"porting the judgment would install a rule that can only ever return `keep`."

The DESIGN's Consequences/Negative records the same cost twice more: "Two of
the four artifact-set outcomes are unreachable through `/scope`... an author
who reaches for `/scope` expecting the whole ladder will not find it there,"
and "A DESIGN is now produced for every feature scoped at or above the design
altitude, including features with one live option."

### 3. Did the DESIGN conclude the type boundary is the real problem?

**No.** The BRIEF's Out of Scope says: "Renaming or re-scoping the artifact
types themselves. If the DESIGN concludes the type boundary is the real
problem, it says so and stops rather than acting on it." The DESIGN never
makes that conclusion. It rejects reshaping schemas (Decision 4 Option B) as
forbidden by PRD R19 and as not actually reducing anything, and it records the
one-absorbable-hop outcome as a cost rather than as a diagnosis.

The nearest thing to the diagnosis is in the **PRD's Known Limitations**, not
the DESIGN, and it is framed as a follow-up rather than a finding:

> Absorption runs in one direction, from an upstream artifact into the
> downstream one that replaced it. A thin DESIGN therefore has nowhere to go:
> its natural home would be the PRD above it, and folding backward is not a
> move this model has. If thin DESIGNs turn out to be common, that is the next
> question to open.

Two neighbouring limitations matter for #280's evidence base: "One absorbable
hop is a thin surface for a rule stated in general terms," and "Evidence for
the constancy of BRIEF-to-PRD overlap comes from documents this same pipeline
produced against these same format references. The overlap may be a property
of the generator rather than of the feature space."

So: the type boundary was **not** considered-and-rejected as a diagnosis. It
was never raised as one. What *was* considered and rejected is (i) changing
schemas to widen absorbability, (ii) lossy absorb, and (iii) making DESIGN
absorbable into PLAN. #280's direction is closest to (iii) and partly to (ii).

### 4. PR #260 and commit 3f702b6

PR #260, "feat(scope): always walk the whole chain and consolidate after the
fact," merged, +2504/-319, **zero review comments** (`gh pr view 260
--comments` returns nothing beyond the body). Everything on the record is the
author's own body text and the commit message, which is the same prose.

The sentence #280 quotes appears in the fourth paragraph of both. Full
context:

> Reducing the artifact set moved to Phase 2, after the artifacts exist. A
> consolidation judgment reads the artifact that just landed and the nearest
> survivor above it, and can absorb the upstream only where the downstream
> type's required sections have a home for every one of the upstream's.
> **Applied to the current formats that is BRIEF into PRD alone, derived from
> the format contracts rather than enumerated by hand.** A per-section carry
> check records where each concern landed before anything is deleted; a
> section that did not arrive aborts the absorb and leaves both artifacts in
> place.

The next-but-one paragraph states the floor as an accepted consequence:

> Two consequences are stated rather than implied. A `/scope` run ends with
> either all four artifacts or the chain minus an absorbed BRIEF, since no hop
> above BRIEF-to-PRD is absorbable; an author who wants to start above
> `/brief` invokes `/design` or `/plan` directly, which is what CLAUDE.md
> already tells them to do and which keeps the choice visible in what they
> typed. And the durable-artifact floor follows from the chain shape rather
> than from a guard — a PLAN-alone run is unreachable through `/scope`, so
> nothing checks for it, and the prose says not to add a check that can never
> fire.

The PR body adds material the PRD and DESIGN do not carry:

- **Dogfooding result.** The chain that produced #260 ran `brief→prd`
  absorbable-but-**failed** the carry check: "the PRD's six one-line user
  stories do not carry the four narrative journeys, each of which walks
  through the judgment's behaviour. The absorb aborted and both artifacts
  stayed." So the one absorbable hop did not actually fire on its own
  reference run — that run left four artifacts, three of them durable.
- **An open gap the author declined to close.** "The consolidation judgment
  fires when the *downstream* artifact of a hop lands in this chain. Re-entry
  protection can prevent that: on a topic whose PRD is already settled,
  `/prd` is held back, so no PRD lands, so the brief-to-prd hop is never
  judged." The author's proposed fix (widen `/brief`'s re-entry protection to
  hold when a settled PRD exists) was written down and **not made**: "I have
  not made it, because it adds a condition under which a child does not run,
  and that is the shape this branch just spent its effort removing. It wants a
  deliberate decision rather than my inference."
- Eval results: `scope` 122/122, `brief` 67/67, `prd` 74/74; the two scenarios
  that replaced the withdrawn entry-altitude pair are
  `chain-shape-is-constant` and `durable-artifact-floor-is-structural`, both
  4/4 with the skill vs 1/4 baseline.

### 5. Where "Durable-Artifact Floor" lives in the shipped skill

Three hits repo-wide: the DESIGN (Decision 8), this exploration's own scope
file, and `skills/scope/references/phases/phase-1-discovery.md`, which carries
a section literally titled "## The Durable-Artifact Floor":

> A `/scope` run always leaves at least one durable artifact, and nothing here
> enforces that — it follows from the chain's shape... A run that leaves
> nothing behind — a PLAN alone, deleted once its work is implemented — is
> therefore not reachable through `/scope` at all. An author who genuinely
> wants no durable record beyond the code invokes `/plan <topic>` directly...
> **Do not add a guard for this. Its condition cannot hold, and a check that
> can never fire teaches the next maintainer that the case is possible.**

Nothing in `docs/decisions/` touches this — the six ADRs there are about
cascade triggers, lifecycle CLI shape, strict mode, multi-PR posture, orphan
docs, and issueless populate. The floor was recorded as a design decision, not
an ADR.

### 6. The entry-altitude removal rationale, stated three times

This is the argument any re-opening of chain shape has to survive. It is
recorded identically in the PRD trade-off (b), DESIGN Decision 1 Option B, the
commit message, and twice in the shipped skill prose:

`skills/scope/references/phases/phase-1-discovery.md`, "What Phase 1 Decides,
and What It Does Not":

> Phase 1 decides **nothing about the size of the artifact set.**... An
> earlier revision let Phase 1 choose an entry altitude for the chain; it was
> removed for exactly this reason, even though the question it asked the
> author (which conversation are you having?) was more answerable than the
> per-hop gates it replaced. It still shrank the artifact set before any
> artifact existed.

`skills/scope/SKILL.md`, "Why the Artifact Set Shrinks" (lines 414-455):

> Three documents that restate one problem at three altitudes cost a reader
> three reads for one idea... Sparing the reader that is worth doing, and it
> is the only reason `/scope` ever ends a run with fewer documents than the
> chain has altitudes. **It is not a way to save the chain work.** That
> distinction decides *when* the reduction can happen.

and:

> A briefly-shipped revision of this skill also let Phase 1 choose an entry
> altitude for the chain. It was withdrawn. The question it asked the author
> was more answerable than the per-hop gates it replaced — which conversation
> are you having, rather than what would an unwritten document have said — but
> it was still a decision that shrank the artifact set before any artifact
> existed, and having two reduction mechanisms fire at different times meant
> neither read as the rule.

Note the precise shape of the argument. It is **not** "authors cannot judge
their own altitude" — the author-facing question was conceded to be
answerable. It is two claims: (1) any mechanism that shrinks the set before
artifacts exist is the defect being removed, whatever it is called; and (2)
two reduction mechanisms firing at different times means neither reads as the
rule. Claim (2) is a single-mechanism constraint, and it is the one that bites
hardest on #280's fourth direction: adding roll-forward-at-every-hop *on top
of* the existing consolidation judgment would reinstate exactly the
two-mechanisms condition. Adding it *as* the consolidation judgment would not.

### 7. Other open issues that overlap

- **#273** "The tactical workflow cannot produce a second downstream document
  under one upstream" (enhancement, needs-triage). Same surface — `/scope`'s
  artifact set and canonical-path model — from the opposite direction: it
  wants *more* documents under one upstream, not fewer. Notes that
  `/design`'s split-at-8-9 branch "has never fired" and that inside `/scope`
  the refuse-at-10 branch surfaces as a missing artifact and bails.
- **#272** "Durable documents must not name ephemeral ones as upstream" (bug,
  needs-design). Directly implicates the absorb procedure: "`/scope`'s
  consolidation judgment makes it worse... step 2 of the absorb procedure sets
  the surviving PRD's `upstream:` to the absorbed BRIEF's own upstream —
  which, per the format above, is a ROADMAP." Any proposal that increases how
  often content rolls forward into ephemeral artifacts inherits this.
- **#277** "A durable DESIGN was deleted, stranding three upstream
  references" (bug). Live evidence of what deleting a durable artifact costs
  — three dangling `upstream:` references — which is the concrete form of
  Decision 8 Option D's objection.
- **#253** "upstream link legality is unenforceable" — proposes a
  `legal_upstream` field on `FormatSpec`; inventoried 71 upstream edges, 34
  DESIGN→PRD and 30 PRD→BRIEF legal, 7 illegal. Any chain-shape change has to
  land inside whatever this settles.
- **#140** "/plan should accept BRIEF as an input_type (currently falls into
  'Anything else' → topic with no upstream)." Relevant if a shorter chain is
  meant to hand a BRIEF straight to `/plan`.
- **#254** item 2 — `chain_skipped` entry keys differ between `/charter`
  (`{child, reason}`) and `/scope` (`{name, reason}`).
- **#257** "a STRATEGY can still be grounded in a tactical-chain PRD" —
  strategic-side analogue, explicitly untouched by #260.
- Adjacent and already landed: `PRD-chain-cardinality` (status Done) carries
  `motivating_context: "An exploration asked whether the /scope consolidation
  overhaul should be ported to /charter. Almost nothing remained to port, but
  the question surfaced that the two chains are not the same shape and that
  the tooling models neither of them correctly."` Its DESIGN is Current. It
  reworks lineage fan-out, chain posture, and the finalization walk that
  "retires shared parents while other consumers still depend on them" — so the
  substrate under any new chain-shape work is itself mid-change.

## Implications

The settled ground #280 should not re-litigate: (1) reductions decided before
the artifacts exist are out, in any form, including an author-chosen entry
altitude; (2) re-entry protection is separate from worth-judgments and stays;
(3) children are invoked with their upstream's path and consume it; (4)
absorbability is derived from the format contracts rather than enumerated;
(5) any absorb needs a per-section receiver check and fails toward keeping
both artifacts; (6) the reader-facing rationale lives in `/scope`, not
`/brief`, and `/brief`'s fold path is gone for good.

The live ground: what "absorb" is allowed to mean. Decision 4's total-mapping
test and Decision 8's Option D are the two walls. Loosening the mapping test
was rejected on schema-variant grounds (R19) and on lossiness grounds — both
still stand independently of who the front door is. Absorbing into the PLAN
was rejected on a single ground: the PLAN is deleted. That ground is about the
PLAN's lifecycle, not about the entry point, so "`/scope` is the default front
door now" does not rebut it. A proposal that wants small runs to leave nothing
durable has to either (a) argue that for small work the code plus the PR *is*
the record and the loss is acceptable, which is precisely the claim Decision 8
says the author is entitled to make but must make explicitly, or (b) change
what happens at PLAN deletion so the rolled-forward content survives
somewhere.

The single-mechanism constraint is the sharper trap. Roll-forward at every hop
must *replace* the consolidation judgment, not sit beside it, or it reinstates
the two-mechanisms-neither-reads-as-the-rule failure that killed the entry
altitude.

## Surprises

- The one absorbable hop **did not fire** on the change's own dogfood run. The
  carry check failed on User Journeys, so #260 shipped leaving all four
  artifacts. In practice the absorb path has, on the record, never
  successfully removed a document.
- PR #260 has zero review comments. There is no second voice anywhere on this
  decision — everything is the author's own prose, restated in four places.
- The author already identified and deliberately declined a nearby fix (widen
  `/brief` re-entry protection when a settled PRD exists), for the same
  self-imposed reason: it adds a condition under which a child does not run.
  #280 is arguably the deliberate decision he said that fix was waiting for.
- The floor's origin question is asymmetric with how #280 frames it. #280 says
  the floor exists "because the consolidation judgment can only absorb where
  the mapping is total." That is true, but the floor was *also* independently
  desired: Decision 8 Option D was rejected on audit-trail grounds even though
  it would have made the mapping test pass.

## Open Questions

- Does the PRD-level requirement R19 ("no new artifact type and no per-type
  schema variant") still bind, given #280 may want exactly a schema change?
  It is a Done PRD, so re-opening it means a new PRD, not an edit.
- What is the actual evidence base for "the framing overlap is constant"? The
  PRD itself flags that the corpus was generated by this same pipeline.
- Is the intended target really "leave nothing durable," or "leave one durable
  artifact of the right altitude"? Decision 8 permits the former only via a
  direct `/plan` invocation. The two targets have very different blast radius.
- #272 and #277 change what deleting or re-pointing an artifact costs. Should
  any roll-forward proposal wait on them?

## Summary

The permanent-PRD-and-DESIGN floor was fully seen and deliberately accepted:
DESIGN Decision 8 argues it with four options, PRD R14 requires it, and
`phase-1-discovery.md` tells maintainers not to add a guard for it — and
Decision 8 Option D rejects absorbing a DESIGN into the PLAN on the ground
that the PLAN is deleted, so it "trades a durable audit trail for a shorter
run and loses the record of why the work happened," which is the exact move
#280 proposes. The DESIGN did *not* conclude the type boundary is the real
problem; the closest thing is a PRD Known Limitation saying a thin DESIGN has
nowhere to go because folding backward is not a move this model has, and "if
thin DESIGNs turn out to be common, that is the next question to open." The
entry-altitude removal rationale, recorded verbatim in five places, concedes
the author-facing question was answerable and rests instead on two claims —
nothing may shrink the set before artifacts exist, and only one reduction
mechanism may exist — of which the second is the real constraint on any
roll-forward-at-every-hop proposal.
