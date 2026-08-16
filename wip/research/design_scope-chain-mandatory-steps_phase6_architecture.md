# Phase 6 Architecture Review — DESIGN-scope-chain-mandatory-steps

Reviewer: architecture. Artifact: `docs/designs/DESIGN-scope-chain-mandatory-steps.md`.
Upstream: `docs/prds/PRD-scope-chain-mandatory-steps.md` (R1-R40).
Decision reports: `wip/design_scope-chain-mandatory-steps_decision_{1..5}_report.md`.
All line references re-derived against this worktree.

## Verdict

**FAIL**

The three-layer structure is right and the decision set is genuinely resolved at
depth — this is not a thin design. It fails on four counts that need edits before
implementation: one cross-decision interaction that reintroduces the exact defect
R28 exists to remove, on the router's own happy path; one contradiction inside
`/scope` that the design asserts as settled in the opposite direction; six
router-side requirements with no architectural home; and a layering claim
("each phase leaves the tree coherent") that is false for two of the four phase
boundaries the design itself defines.

## Strawman Check

### Decision 1 — crystallize replacement

**Verdict: FAIL (one rejection incomplete).**

The rejection of *gate-then-score* is honest. The design adopts C's core insight
as candidacy preconditions, states that C's failure is one of extent rather than
kind, and names the right defeater: rejection-versus-lead-exhaustion has no
mechanical detector and the four terminal outcomes are where a wrong answer
writes a permanent document. That matches the report and does not soften C.

The rejection of *flat scoring* is where the design sets up a loss. It gives two
reasons — contamination and per-run cost — and both are true. But the report
names two arguments FOR B that the design never engages:

1. **B has no stage-1 failure mode.** The report states it plainly: "if the two
   stages turn out to disagree in practice — stage 1 saying terminal where a
   chain was right — B has no such failure mode, because every outcome is always
   in contention. That is not a hypothetical; it is A's named con." A stage-1
   error is *unrecoverable* under A: if stage 1 returns a terminal, the four
   entry points are never scored and never offered. The design's Considered
   Options does not mention this, and — more seriously — neither does its
   Negative section, which lists four consequences and omits the one the decision
   report calls A's principal cost. The report's mitigation (when stage 1's margin
   between "a chain" and the top terminal is within 1, run stage 2 anyway and
   present both) is dropped with it.
2. **B inherits the demotion rule with zero adaptation.** The report calls this
   "B's genuine advantage and it is not small — the rule is the framework's main
   guard against a high-raw-score outcome with a disqualifying counter-indication,
   and B inherits it with no risk of getting the adaptation wrong." The design's
   only demotion-rule discussion argues the opposite direction (why "a chain" must
   be scored rather than residual, so demotion applies symmetrically), which is
   correct but is an argument about a problem A creates.

Neither argument overturns the choice. Both belong in the record, and the
mitigation belongs in the design.

### Decision 2 — handoff path and schema

**Verdict: PASS, with one cost not carried.**

Both rejections are argued on their merits. *Router-namespaced single file* is
credited with being cleaner on collisions and better on the mis-addressed case —
its two real advantages — and is rejected on a contract cost the report also
treats as decisive: widening two closed write-target sets so a parent may delete a
third skill's artifacts. The design recovers B's advantage with the sibling-path
notice and says so. *Per-child convention* is rejected on R19's own terms and,
independently, on the ground that no narrowing exists that does not read child
file bodies or depend on filesystem provenance. Both hold against the tree.

The cost not carried: the report names C's one genuine merit — it is the only
option under which `/prd`, `/vision`, and `/roadmap` keep a live producer for
their handoff-detection clauses — and states that under A the only surviving
producer is `/charter` → `/roadmap`, so "R24's edit is either a producer statement
that is true only for `/roadmap`, or it comes with a decision that `/scope` starts
pre-populating." The design's Layer 3 says the three child skills "are re-grounded
on the parent" without acknowledging that on the `/scope` path no such producer
exists. See Required Change 8.

### Decision 3 — detection placement

**Verdict: FAIL (missing option, and one rejection stronger than its argument).**

Two problems.

**The cheapest option is absent from the design.** The report evaluated three
placements; the design names two. Report 3's Option B — put the handoff test
inside `/charter` row 8 and disambiguate there, mirroring the mid-roadmap check
row 6 already carries — is the one with the smallest blast radius ("Template
change: none, which is its main attraction"), and it repairs the row-8 collision
in the same edit. The report rejects it well (two different actions at two
different phases behind one row is the shape that made row 8 misroute in the first
place; and it falsifies `skills/charter/SKILL.md:222-224` while the feeder
behavior ships). Neither reason appears in the design. A reader of the design
cannot tell that the low-cost option was considered.

**The pre-ladder rejection overstates.** The design says a pre-ladder check "was
rejected because it makes the handoff win over re-entry protection. A settled
artifact on disk is the stronger claim, and a pre-ladder check inverts that
ordering *by construction*." That last clause is not true, and the report does not
claim it: report 3's Option C is written with the negatives included ("plus, to be
safe, no state file, no settled child artifact in any status the parent's Slot 5
enumerates, and no child partial-run artifact"). The report's actual objection is
D1 plus D3 — a pre-ladder check is a second dispatch surface, and its conjunction
of negatives is exactly what rows 1-6 already compute, restated by hand outside
the ladder where it drifts. That is a strong argument. The design substituted a
weaker one that sounds more damning.

### Decision 4 — Phase 1 bail

**Verdict: PASS.**

Both rejections are fair. *Tolerating an empty artifact set* is rejected on the
right ground — it spends the check that guards the other two exits to fix the one
exit that should not be taken here — and the design correctly names what
abandonment-forced is for. *Moving the state-file write* is rejected on a real
cost (Phase 0's other obligations record into that file). The design does not use
the report's decisive argument, which is that C is not an alternative at all: it
fixes the chain-proposal bail and leaves Phase 2's first worktree-discipline
escalation, the ladder's upstream re-validation bail, and Slot 5's settled-upstream
bail all broken, so C needs A anyway. Under-argued rather than strawmanned; worth
adding because it also tells the implementer that the narrowing fixes four stops,
not one.

### Decision 5 — reason vocabulary and entry key

**Verdict: FAIL (one rejection understates the alternative).**

*Open list with a stated prohibition* is rejected correctly and decisively — it
fails R4 on its face, and the design's one-sentence version ("a grep can assert
membership in a closed set; it cannot assert the absence of a worth judgment from
arbitrary prose") is the report's argument compressed without loss.

*A structured reason with a typed qualifier* is rejected as "the same closed enum
with more ceremony — the qualifier duplicates what the optional detail field
already carries, and it forces every writer to supply a second field even where
there is nothing to qualify." That is not why C fails, and it buries C's genuine
strength. The report is explicit: C is "strictly the best on paper. The ground is a
member and the qualifier is typed, so a check can assert both membership *and* the
qualifier's shape ... With no free-text field at all, the public-surface argument
closes **completely** rather than mostly." Since the public-surface argument is one
of the two pillars the design rests the whole decision on, an alternative that
closes it completely deserves its strength stated. C's real defeater is structural
and specific: the six grounds do not share a qualifier type, so C forces either a
per-ground discriminated union — which drags invariant I-5's conditional-field
gating into a nested list entry it was never written for — or an optional
qualifier, which is A. "More ceremony" is not that argument.

## Requirement Coverage

| Requirement | Architectural home | Verdict |
|---|---|---|
| R1 model statement | Layer 1, pattern Gate Vocabulary head | Covered |
| R2 declination three properties | Layer 1, restated ALWAYS clause | Covered but contradicted — see RC2 |
| R3 Adjust per-parent | Layer 1 prompt literal-form rule; both parents declare | Covered |
| R4 closed reason vocabulary | Layer 1, state-schema chain-tracking | Covered |
| R5 triad / constancy / never-planned | Layer 1, triad contract + Pre-Dispatch reconciliation | Covered but unresolved — see RC2 |
| R6 entry key | D5, `child:` | Covered |
| R7 parent roster, cardinality, dispatch mechanism | Layer 1, both non-mechanical items named | Covered |
| R8 `/comp` in `/charter` schema | Layer 3 | Covered |
| R9 `/charter` Adjust cannot drop | Layer 3 | Covered |
| R10 two-stage crystallize | Layer 2, framework restructure | Covered |
| R11 no durable authoring | Layer 2, DESIGN-skeleton handler deleted | Covered |
| R12 routing/complexity tables, detection algorithm | Layer 2 | Covered |
| R13 arms match destinations | D1 preconditions (`/execute`) | Partial — `/work-on` as the file-an-issue next step is never named |
| R14 four terminal outcomes | Layer 2, comp→`/comp`, terminal handlers survive | Covered |
| R15 Phase 0 artifact-type triage removed | Layer 2, "loses its artifact-type triage" | Partial — `references/label-reference.md` has no home |
| R16 investigation/breakdown/ready triage | **none** | **Missing** — see RC3 |
| R17 step 0.2a and Label Pre-Gate | Layer 2 preserves 0.2a explicitly | Partial — Label Pre-Gate provenance has no home |
| R18 destinations resolve under `skills/` | Layer 2 (comp only) | Partial — `/spike` has no home |
| R19 parent-namespaced handoff | D2 / Layer 2 | Covered |
| R20 both parents detect and consume | D3 / Layer 3 | Covered |
| R21 conversation not filesystem state | D2 | Covered |
| R22 two misroutes narrowed | Layer 3 | Covered |
| R23 slug re-validation | Security Considerations | Covered |
| R24 child clauses re-grounded | Layer 3, one sentence | Partial — see RC8 |
| R25 what each arm passes; STRATEGY upstream | **none** | **Missing** — see RC3 |
| R26 topic branch vs branch rows | **none** | **Missing** — see RC3 |
| R27 three options kept, justification corrected | Drivers + Layer 3 | Covered |
| R28 bail reaches clean-cancel | D4 / Layer 3 | Covered but broken by D2 — see RC1 |
| R29 direct-invocation redirect narrowed | Layer 3 | Covered |
| R30 `chain_revised:` | Layer 3, "the orphaned `chain_revised:` field" | Covered (disposition unstated) |
| R31 post-PRD second confirmation | Layer 3 | Covered (disposition unstated) |
| R32 reason-count claim | Layer 3 | Covered |
| R33 absorbability scenarios rewritten | Phase 4, group 1 | Covered |
| R34 chain-proposal pins converge per-token | Phase 4, group 2 (generic) | Partial — the byte-for-byte-to-per-token convergence is never named |
| R35 re-target handoff scenarios | Phase 4, group 2 | Covered |
| R36 receiving-side scenarios | Phase 4, group 3 | Covered |
| R37 guard scenarios survive | Phase 4, group 3 | Partial — R37 requires `chain-shape-is-constant`'s **third** expectation to be *updated*, not verified byte-identical; group 3 is defined as "verified rather than edited" |
| R38 `/explore` triage scenarios | Phase 4, group 2 (implied) | Partial — depends on R16, which has no home |
| R39 assertion arrays introduced | **none** | Missing (minor) |
| R40 `references/pipeline-model.md` | Phase 4 | Covered |

**Scope creep:** none material. The two commitments beyond the requirement set —
the sibling-path notice and the shared ladder-template's body-slot-expansion
amendment — are each argued as consequences of a chosen option rather than added
capability, and each is one clause. The design is disciplined here.

## Verified Claims

| Claim | Holds? | Evidence |
|---|---|---|
| `/scope`'s Slot 7 is reserved and vacuous | Yes | `skills/scope/references/phases/phase-resume.md:80` "Slot 7 — Feeder-Doc-Detected (vacuous in v1)"; `skills/scope/SKILL.md:358`, `:415` |
| `/charter`'s row 7 is occupied | Yes | `skills/charter/references/phases/phase-resume.md:52` row 7 = `wip/strategy_<topic>_discover.md` → resume into `/strategy` |
| `/charter` has no slot vocabulary | **No** | `skills/charter/SKILL.md:215-224` maps slots 5, 6, 7 onto rows explicitly and states "slot 7 (feeder-doc-detected) is unfilled because `/charter` has no feeder-doc case" — a sentence this change falsifies and the design never schedules for edit |
| `/charter`'s resume file states renumbering would disturb `/scope` | Yes | `skills/charter/references/phases/phase-resume.md:264-269`: "rows 9-10 are pattern-level meta-ladder rows that renumbering would disturb for `/scope` as well as `/charter`" |
| `phase-4-crystallize.md` reproduces three of seven tiebreakers | Yes | `phase-4-crystallize.md:97,100,102` carries PRD-vs-Design-Doc, PRD-vs-No-artifact, Design-Doc-vs-Plan; `crystallize-framework.md:186-211` carries those plus the four VISION discriminations |
| `/scope` Phase 3 sets `triggering_child:` to the first incomplete child on a Phase 1 bail and force-materializes its intermediate | Yes | `phase-3-exit-finalization.md:172-176`; duplicated at `SKILL.md:590-592` |
| `skills/explore/SKILL.md`'s reference table is stale by three files | Yes | Table at `:327-339` omits `phase-5-produce-rejection-record.md`, `phase-5-produce-roadmap.md`, `phase-5-produce-vision.md` — exactly three |
| The competitive-analysis handler refuses in a public repo at produce time | Yes | `phase-5-produce-deferred.md:113-126` |
| ...after crystallize may have scored it highest | **Qualified** | "Repo is public" is already an anti-signal (`crystallize-framework.md:138`) and the demotion rule (`:174-178`) demotes any type with a firing anti-signal below every type with none, so comp can only rank *highest* when every other type also has a firing anti-signal. The defect is real by a different route: alternatives are presented as selectable AskUserQuestion options (`phase-4-crystallize.md:129-131`, `:145-147`), so a demoted comp is still offered and still refused. The design should state the reachable form, not the strongest-sounding one |
| The bail rule's disjunction names the state file | Yes, and more | `SKILL.md:443-448` names "the state file, any child intermediate, **or any research scratch**" — three disjuncts, not one. Excluding only the state file leaves two |
| `/scope`'s `planned_chain` is constant | **No** | `phase-1-discovery.md:400-405` "the whole tactical chain, in order, **minus any child held back by re-entry protection**. Held-back children appear in `chain_skipped:` ... not in `planned_chain:`"; `:415-416` "That list is a constant." Both sentences, same section, ten lines apart |
| `/charter` keeps a declined child in `planned_chain` | Yes | `phase-2-chain-orchestration.md:386` — the declined `/roadmap` stays in `planned_chain` "the plan was to run it; the author declined" |
| `/explore` Phase 0 carries one triage | **No** | Two: step 0.4 Investigation vs. Actionable (`phase-0-setup.md:79`) and step 0.5 Triage Stage 2: Investigation Type (`:160`). R15 removes 0.5; R16 governs 0.4 |
| `/spike` resolves to nothing | Yes | `crystallize-framework.md:112` "Routes to /spike"; no `skills/spike/` exists |

## Required Changes

1. **The Phase 1 bail narrowing is insufficient once the handoff exists, and the
   two decisions collide on the router's own happy path.** D4 chooses to "narrow
   the wip-state test to exclude the parent's own state file." D2 puts a new file
   at `wip/scope_<topic>_handoff.md`, and D3 states the bail leaves it on disk
   ("The handoff artifact is not disposed of by a bail"). The bail rule at
   `SKILL.md:443-448` routes on "any wip state ... (the state file, any child
   intermediate, or any research scratch)". Exclude only the state file and the
   handoff still satisfies the disjunction, so an author who explores, is routed
   to `/scope`, and bails at the chain proposal lands in abandonment-forced with
   nothing to materialize — the exact R9 violation R28 exists to remove, now
   reachable on the path this change creates. Report 2 flagged this explicitly
   ("R28's exclusion must widen ... but it must be written down or the option
   regresses R28") and the design did not carry it. Restate D4 as report 4's
   three-step resolution — `chain_ran`, then the first `planned_chain` entry with
   a non-empty child intermediate, then clean-cancel — so the parent's whole
   `wip/<parent>_<topic>_*` prefix and `wip/research/` are never consulted. Say so
   in Decision 4, in the Layer 3 paragraph, and in the Mitigations claim.

2. **Resolve `/scope`'s `planned_chain` contradiction before the pattern-level
   statements are written.** `phase-1-discovery.md:400-405` says a child held back
   by re-entry protection is dropped from `planned_chain` and appears only in
   `chain_skipped`; `:415-416` says "That list is a constant." Three of this
   design's commitments depend on which is true: R2's third declination property
   ("The child remains in `planned_chain` and the skip lands in `chain_skipped`"),
   R5's per-parent constancy with "`/scope`'s constant", and the never-planned
   category's boundary. `/charter` resolves it the other way
   (`phase-2-chain-orchestration.md:386` keeps the declined child in the list), so
   writing R2's property as stated puts the shared pattern in conflict with
   `/scope` on landing. Report 5 raised this as an open sub-question and asked for
   it to be settled "before either is written." The design presents it as settled
   in the direction the tree contradicts. Pick one, and note that the PRD's own AC
   — `phase-1-discovery.md` contains "no passage contradicting another passage in
   the same file" — already reaches this passage.

3. **Six router-side requirements have no architectural home.** Give each a home
   or an explicit exclusion with a reason:
   - **R16** — Phase 0's step 0.4 investigation-versus-actionable triage. The
     design removes only the artifact-type triage (step 0.5). R16 requires 0.4 be
     deleted-and-folded or kept-and-fed-into-crystallize, and R38's two `/explore`
     scenarios depend on which.
   - **R25** — what each arm passes, and the fate of `--upstream <STRATEGY>`.
     Report 2 answers it (retired as a flag, demoted to prose under
     `## Upstream Observations`, mirroring what the roadmap handler already does
     for the VISION case); the design carries none of it, and the AC requires a
     stated destination or a stated retirement.
   - **R26** — `/explore`'s `docs/<topic>` branch against both parents'
     branch-matching rows. Report 3 answers it in two parts (Slot 7 sits above the
     branch row, plus restating the branch row's action to run Phase 0's
     idempotent obligations); the design mentions neither, and the AC requires a
     resolution or a named Known Limitation.
   - **R15's second half** — `references/label-reference.md` must be updated in the
     same change, retiring or re-grounding the labels whose only producer was the
     removed triage and fixing the two dangling skill-lookup rows.
   - **R17's second half** — the Label Pre-Gate's `needs-*` provenance changes once
     the triage stops writing labels and must be restated.
   - **R18** — `/spike`. The design fixes `/competitive-analysis` by routing to
     `/comp`, but the spike table survives "nearly verbatim" and carries
     `crystallize-framework.md:112`'s "Routes to /spike", which resolves to
     nothing. R14 keeps `/explore` as the spike author, so the string is the fix.

4. **The layering claim is false at two of the four phase boundaries.** The design
   asserts "each phase leaves the tree coherent" and rests the size mitigation on
   it. Two counterexamples, both inside the design's own ordering:
   - **After Phase 1 alone.** Phase 1 lands the closed reason vocabulary and the
     `child:` key in `references/parent-skill-state-schema.md`. Both parents write
     outside them until Phase 2: `/scope`'s templates write "PRD-boundary
     rejection" and "DESIGN-boundary rejection" and its Phase 1 writes `- name:
     prd`; `/charter`'s `phase-state-management.md:143-146` still says the reason
     is "free-text ... NOT parsed by tooling". The shared contract asserting
     something both skills contradict is the precise failure mode the design's own
     first Decision Driver names.
   - **Phase 3 after Phase 2.** Phase 3 introduces the handoff file, which
     re-breaks the bail fix Phase 2 landed unless Required Change 1 is applied.
   Either bind Phases 1 and 2 as one landing, or replace the coherence claim with
   the accurate one: the phases are dependency-ordered, and the intermediate
   states are internally inconsistent in stated ways. The narrower claim the
   design makes — "a detection clause with no producer is inert rather than
   broken" — is true and survives; it is the general claim that does not.

5. **Record Decision 1's own failure mode and its mitigation.** The design's
   Considered Options and its Negative section both omit that a stage-1 error is
   unrecoverable at stage 2 — if stage 1 wrongly returns a terminal, the four
   entry points are never scored and never offered. This is the report's named
   principal cost of the chosen option and the one place flat scoring is
   genuinely stronger. Carry the report's mitigation with it: when stage 1's
   margin between "a chain" and the top terminal is within 1 — the threshold the
   framework already uses — run stage 2 anyway and present both results.

6. **Repair Decision 3's option set and its pre-ladder rejection.** Add report 3's
   Option B (the handoff test inside `/charter` row 8) with the two reasons it
   loses: two different actions at two different phases behind one row, which is
   the shape that made row 8 misroute; and it falsifies
   `skills/charter/SKILL.md:222-224` while the feeder behavior ships. Replace "a
   pre-ladder check inverts that ordering by construction" — a pre-ladder check
   can carry the negatives — with the argument that actually defeats it: it is a
   second dispatch surface, and its conjunction of negatives restates by hand what
   rows 1-6 already compute, which is the same shape already wrong in row 8.

7. **State Decision 5's alternative at its real strength.** The typed-qualifier
   option is strictly better than the chosen one on enforceability and closes the
   public-surface argument completely rather than mostly. Its defeater is that the
   six grounds do not share a qualifier type, so it forces a per-ground
   discriminated union that drags invariant I-5's conditional-field gating into a
   nested list entry, or an optional qualifier — which is the chosen option. Say
   that instead of "more ceremony".

8. **Say what R24's re-grounding is honest about.** Once `/explore` stops writing
   `wip/{prd,vision,roadmap}_<topic>_scope.md`, the only surviving producer is
   `/charter` → `/roadmap`. `/scope` pre-populates nothing, so `/prd`'s detection
   clause is left with no producer on the `/scope` path. Either state that plainly
   in the clause, or decide that `/scope` starts pre-populating. Report 2 called
   this "the largest downstream consequence of the recommendation"; the design's
   one sentence — "the three child skills ... are re-grounded on the parent" —
   reads as if all three have one.

9. **Decide `consumed_handoff:`.** Report 3's proposed ladder rows for both
   parents write `consumed_handoff: <path>` into the state file, and report 3
   warns that leaving it unspecified makes it "the next `chain_revised:` — written
   by a phase file, absent from the schema, read by nothing." The design removes
   `chain_revised:` for exactly that under R30 and does not mention
   `consumed_handoff:` anywhere. Either give it a schema home in both parents and
   the pattern with its conditional-field gating, or state that no such field is
   written and that double-consumption is prevented by ladder ordering alone.

## Optional Improvements

- **State the competitive-analysis defect in its reachable form.** The current
  wording ("a public repo can score competitive analysis highest") is true only
  when every other type also carries a firing anti-signal, because the demotion
  rule is absolute. The defect that actually bites on ordinary runs is that a
  demoted competitive analysis is still presented as a selectable alternative in
  step 4.7's AskUserQuestion and still refused at produce time. Same conclusion,
  argument that survives a reader checking it.

- **Say that the bail narrowing fixes four stops, not one.** Report 4 identifies
  Phase 2's first worktree-discipline escalation, the ladder's upstream
  re-validation bail, and Slot 5's settled-upstream bail as sharing the Phase 1
  bail's exact state. This is also the decisive argument against the
  defer-the-write alternative — it cannot reach three of the four — and it is a
  stronger rejection than the one the design gives.

- **Schedule the two sentences that go false.** `skills/charter/SKILL.md:222-224`
  ("slot 7 ... is unfilled because `/charter` has no feeder-doc case") and
  `skills/scope/SKILL.md:358` / `:415` ("Slot 7 is vacuous in v1", "Slot 7
  (vacuous)"). The design already treats one such item as design-worthy — the
  `/explore` reference table stale by three files — so the standard is set.
  Report 5's sites 13 and 16 are the same class on the `/charter` side: two
  security arguments whose stated premise is "`chain_skipped[].reason` is free
  text", which the enum falsifies in the same PR.

- **Split R37's third group.** The design defines Phase 4's third group as
  "scenarios that must survive byte-identical, which are verified rather than
  edited." R37 requires `chain-shape-is-constant`'s first, second, and fourth
  expectations verbatim and its **third** updated to R29's narrowed redirect. As
  written the scenario would land in a group whose defining property is that it is
  not edited.

- **Name `/work-on` (R13) and the per-token eval convergence (R34).** Both are
  one-line commitments the PRD makes explicitly and the design leaves to the
  implementer to rediscover from the requirement text.

- **Two smaller undecideds the design closes by omission.** Report 1 leaves open
  whether "file an issue" is one arm or two (the Trivial row says "no issue
  needed"; the No Artifact handler offers `/issue` or direct `/work-on`), and what
  becomes of the Prototype deferred type and the "multiple deferred types match"
  disambiguation rule. The design's clean "five stage-1 categories, four stage-2
  entry points" framing has no slot for either, which reads as settled. One
  sentence each.

- **The Data flow paragraph over-generalizes the handoff.** "The router writes
  `wip/<parent>_<topic>_handoff.md` and names the command to run" is true of the
  `/scope` and `/charter` arms only; the `/execute` and file-an-issue arms write no
  handoff (report 2 Q5 confirms `/execute` needs nothing). Worth one clause so a
  later reader does not go looking for a third handoff file.
