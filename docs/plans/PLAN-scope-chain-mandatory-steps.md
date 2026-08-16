---
schema: plan/v1
status: Active
execution_mode: single-pr
upstream: docs/designs/DESIGN-scope-chain-mandatory-steps.md
milestone: "Chain steps are mandatory"
issue_count: 18
---

# PLAN: Chain Steps Are Mandatory

## Status

Active

Single-pr plan decomposed from the accepted design. Eighteen issues across the
design's five implementation phases plus one prerequisite.

## Scope Summary

Make the corpus state one model for whether a tactical-chain step is optional:
state it in the shared parent-skill pattern, make `/explore` route to chain entry
points instead of chain interiors, give the router a handoff both parents
consume, and bring the eval suite into agreement with the skills it grades.

## Decomposition Strategy

Horizontal. The design describes three layers with a stated dependency direction
— the shared contract, then the parents that cite it, then the router — and
interfaces between them are stable and textual. One component is a prerequisite
for the rest: the pattern's model statement is what makes the parents'
declarations required.

Walking skeleton was considered and rejected. Its value is surfacing integration
failure early, and the integration here is textual consistency, which the
design's cross-decision validation already performed.

## Issue Outlines

### Issue 1: fix(scope): settle whether planned_chain drops a held-back child

**Goal**: Resolve `/scope`'s Phase 1 contradiction about `planned_chain`, so the
two pattern-level statements that depend on it can be written against a settled
reading.

**Acceptance Criteria**:
- [ ] `skills/scope/references/phases/phase-1-discovery.md` states one rule for
      what happens to a child held back by re-entry protection
- [ ] The rule matches `/charter`'s: the child stays in `planned_chain` and is
      recorded in `chain_skipped`, because the plan was to run it
- [ ] The passage calling the list "a constant" is reconciled with that rule
      rather than left to contradict it
- [ ] No passage in the file asserts a child is dropped from `planned_chain`

**Dependencies**: None

**Type**: docs
**Files**: `skills/scope/references/phases/phase-1-discovery.md`

### Issue 2: feat(pattern): state the mandatory-steps model and restate the declination clause

**Goal**: Give the shared pattern a statement of the model, a declination clause
that reads as an instance of it, a per-parent Adjust rule, and a correct roster.

**Acceptance Criteria**:
- [ ] `references/parent-skill-pattern.md` states at the head of its Gate
      Vocabulary that chain steps are mandatory and reduction is post-hoc
- [ ] The statement names the grounds on which a child may legitimately not run
- [ ] The statement is true of all three parents and does not require a parent to
      define a post-hoc reduction mechanism
- [ ] The ALWAYS declination clause names three properties: author-supplied so a
      non-interactive run invokes the child, formed against a document already on
      disk, and recorded
- [ ] The clause states the prompt may not ask whether the artifact is worth
      producing, and carries a one-sentence no-behavior-change note
- [ ] The clause carries no dated-retirement block
- [ ] The prompt literal-form contract states Adjust's reach into chain
      membership is per-parent
- [ ] `/execute` appears in the parent roster; the child roster's cardinality and
      the dispatch mechanism are each resolved rather than left stale

**Dependencies**: Blocked by <<ISSUE:1>>

**Type**: docs
**Files**: `references/parent-skill-pattern.md`

### Issue 3: feat(pattern): bound the chain_skipped reason vocabulary and unify the entry key

**Goal**: Replace free-text skip reasons with a closed vocabulary, restate the
triad contract, and make both parents write the same entry key.

**Acceptance Criteria**:
- [ ] `references/parent-skill-state-schema.md` defines a closed
      `chain_skipped[].reason` vocabulary of four members
- [ ] Every reason string either parent writes today maps to exactly one member
- [ ] No member ships without a writer in `skills/scope/` or `skills/charter/`
- [ ] An optional free-text sibling field is defined and stated never to be the
      ground, bound by the same content discipline as the existing free-text exit
      field
- [ ] The extension path cites the grow-by-PR-review precedent in
      `references/parent-skill-child-inspection.md` rather than describing a new
      discipline
- [ ] The triad contract states `planned_chain` constancy as a per-parent
      property and names the never-planned category as a first-class member
- [ ] The pre-dispatch description no longer says a parent advances
      `planned_chain` per dispatch
- [ ] Both parents write the same entry key, and the graded eval strings match it

**Dependencies**: Blocked by <<ISSUE:1>>

**Type**: docs
**Files**: `references/parent-skill-state-schema.md`, `skills/scope/references/state-schema.md`, `skills/charter/references/phases/phase-state-management.md`

### Issue 4: fix(security): extend slug re-validation to the feeder-doc clause

**Goal**: Close the path-traversal surface the new detection clause would
otherwise open, at the one place the enumeration lives plus its two restatements.

**Acceptance Criteria**:
- [ ] `references/parent-skill-security.md`'s slug re-validation enumeration
      names the feeder-doc clause alongside the two slots it names today
- [ ] `skills/scope/references/phases/phase-resume.md` restates it for its new
      clause
- [ ] `skills/charter/references/phases/phase-resume.md` carries a first
      statement of the rule covering its new row

**Dependencies**: Blocked by <<ISSUE:2>>

**Type**: docs
**Files**: `references/parent-skill-security.md`

### Issue 5: docs(parents): declare which Adjust each parent has

**Goal**: Make the divergence the pattern now names visible in each parent's own
chain-proposal section.

**Acceptance Criteria**:
- [ ] `skills/scope/` states that its Adjust refines the topic and framing and
      cannot change chain membership
- [ ] `skills/charter/` states that its Adjust can force a previously-skipped
      child on
- [ ] Neither states that Adjust may reach a child whose artifact the parent
      judged not worth producing

**Dependencies**: Blocked by <<ISSUE:2>>

**Type**: docs
**Files**: `skills/scope/references/phases/phase-1-discovery.md`, `skills/charter/references/phases/phase-1-discovery.md`

### Issue 6: feat(parents): detect and consume an explore handoff

**Goal**: Fill the reserved feeder slot in both parents so a router handoff is
consumed into Phase 1 rather than ignored.

**Acceptance Criteria**:
- [ ] `/scope` fills Slot 7 with a clause matching
      `wip/scope_<topic>_handoff.md`
- [ ] `/charter` gains a row in the slot-7 position without renumbering the
      shared meta-ladder tail, matching `wip/charter_<topic>_handoff.md`
- [ ] `skills/charter/SKILL.md`'s sentence saying slot 7 is unfilled because
      `/charter` has no feeder-doc case is corrected
- [ ] Both clauses sit below re-entry protection, so a settled artifact wins and
      the handoff is announced rather than silently dropped
- [ ] Both clauses enter Phase 1 with the handoff pre-loaded and never route into
      a child
- [ ] A `consumed_handoff:` field is defined in each parent's state schema with
      its reader named
- [ ] The handoff's documented schema carries no artifact existence, frontmatter
      status, content hash, visibility, or upstream validation
- [ ] A malformed handoff is announced and the run proceeds as a cold start
- [ ] `references/parent-skill-resume-ladder-template.md` permits a parent to
      expand a body slot into more than one numbered row

**Dependencies**: Blocked by <<ISSUE:4>>

**Type**: docs
**Files**: `skills/scope/references/phases/phase-resume.md`, `skills/charter/references/phases/phase-resume.md`, `skills/charter/SKILL.md`, `references/parent-skill-resume-ladder-template.md`

### Issue 7: fix(parents): narrow the two ladder rows that swallow a handoff

**Goal**: Stop `/scope` reading a router handoff as an interrupted `/prd` run and
`/charter` reading one as an interrupted `/vision` run.

**Acceptance Criteria**:
- [ ] `/scope`'s partial-child-run glob no longer matches a handoff artifact
- [ ] `/charter`'s `/vision` partial-run row no longer matches a handoff artifact
- [ ] Both still match the interrupted-child run they were written for
- [ ] Placing a `/prd`-shaped scope artifact and running `/scope` no longer
      invokes `/prd` directly
- [ ] Placing a `/vision`-shaped scope artifact and running `/charter` no longer
      jumps into `/vision`

**Dependencies**: Blocked by <<ISSUE:6>>

**Type**: docs
**Files**: `skills/scope/references/phases/phase-resume.md`

### Issue 8: fix(scope): make the Phase 1 bail reach clean-cancel

**Goal**: Make the author's only pre-child stop execute, instead of reaching a
hard-finalization violation.

**Acceptance Criteria**:
- [ ] The bail routes to abandonment-forced only on a child intermediate or
      research scratch; nothing under the parent's own wip prefix counts
- [ ] The narrowed test is stated positively and matches `/charter`'s equivalent
      step
- [ ] A Phase 1 bail reaches clean-cancel and disposes of the state file
- [ ] The deletion removes the state file only, with the handoff artifact carved
      out explicitly in the shape the fold record's carve-out uses
- [ ] Clean-cancel is named in the closed write-target set
- [ ] The branch setting `triggering_child:` to the first incomplete child on a
      bail no child took part in is deleted from both places that carry it
- [ ] The three write-target restatement sites do not diverge
- [ ] An eval scenario exercises a Phase 1 bail reaching clean-cancel

**Dependencies**: Blocked by <<ISSUE:1>>

**Type**: docs
**Files**: `skills/scope/SKILL.md`, `skills/scope/references/phases/phase-3-exit-finalization.md`, `skills/scope/references/phases/phase-4-cleanup.md`

### Issue 9: fix(scope): sweep the prose that contradicts the model

**Goal**: Remove the passages in `/scope` that state the pre-#302 model beside
the one that states the current one.

**Acceptance Criteria**:
- [ ] No file under `skills/scope/` justifies the chain proposal on the ground
      that `/scope` cannot produce a smaller artifact set
- [ ] The direct-invocation redirect is narrowed: a child invoked directly buys a
      shorter conversation, not a smaller artifact set
- [ ] `skills/scope/references/phases/phase-1-discovery.md` contains no passage
      contradicting another passage in the same file
- [ ] `chain_revised:` is either absent everywhere or defined in the state schema
      with a stated reader
- [ ] The post-PRD gate's second confirmation either has an options block and a
      recorded answer, or is gone
- [ ] The state schema enumerates every `chain_skipped` reason the skill writes,
      and the count claim matches

**Dependencies**: Blocked by <<ISSUE:3>>, <<ISSUE:8>>

**Type**: docs
**Files**: `skills/scope/references/phases/phase-2-chain-orchestration.md`

### Issue 10: fix(charter): resolve the comp membership contradiction and bound Adjust

**Goal**: Make `/charter` name its private-only feeder one way, and stop its
Adjust from dropping a child before any artifact exists.

**Acceptance Criteria**:
- [ ] `/comp` appears in no `planned_chain` example and no `chain_skipped`
      example under `skills/charter/`
- [ ] The Phase 2 rule carrying the visibility argument is the surviving one
- [ ] `skills/charter/references/phases/phase-1-discovery.md` describes no Adjust
      behavior that drops a child
- [ ] Adjust retains re-framing the topic, correcting the thesis-shift answer,
      and forcing a previously-skipped child on

**Dependencies**: Blocked by <<ISSUE:3>>

**Type**: docs
**Files**: `skills/charter/references/phases/phase-2-chain-orchestration.md`

### Issue 11: feat(explore): restructure crystallize into two-stage scoring

**Goal**: Replace the ten-type framework with a stage that scores what the
exploration is, then a stage that scores which parent receives the work.

**Acceptance Criteria**:
- [ ] Stage 1 scores five categories: four terminal outcomes plus a chain, each
      with signal and anti-signal tables
- [ ] "A chain" is a scored category rather than the residual, so the demotion
      rule applies to it symmetrically
- [ ] Stage 2 scores four entry points and runs only when stage 1 returns a chain
- [ ] Stage 2 also runs when stage 1's margin is within one point
- [ ] Candidacy preconditions govern the execute arm and competitive analysis;
      neither is reachable by score alone
- [ ] The demotion rule, the insufficient-signal fallback, and the tiebreaker
      procedure survive
- [ ] No scoring category names a chain-internal child
- [ ] `--strategic` biases no signal or anti-signal
- [ ] The phase file reproduces every tiebreaker rather than a subset
- [ ] `grep -rEn 'Routes to (/|shirabe:)(brief|prd|design|plan|vision|strategy|roadmap)\b'`
      over the framework returns nothing

**Dependencies**: Blocked by <<ISSUE:2>>

**Type**: docs
**Files**: `skills/explore/references/quality/crystallize-framework.md`, `skills/explore/references/phases/phase-4-crystallize.md`

### Issue 12: feat(explore): rebuild the produce handlers as router arms

**Goal**: Collapse five child-specific handoff handlers into two parent handlers,
stop authoring durable chain artifacts, and route the arms that have owners.

**Acceptance Criteria**:
- [ ] The handler table names no chain-internal child in its handoff column
- [ ] `skills/explore/` writes no file under `docs/designs/`
- [ ] Two parent handlers write `wip/scope_<topic>_handoff.md` and
      `wip/charter_<topic>_handoff.md` from one skeleton with one
      parent-specific block
- [ ] The handoff carries predicate inputs and never predicate verdicts, and no
      material for the predicate that reads the repo's directory structure
- [ ] The competitive-analysis arm routes to `/comp` and writes no
      `docs/competitive/` file itself
- [ ] The decision arm routes to `/decision`
- [ ] The spike and rejection arms keep `/explore` as their author
- [ ] The execute arm is named only in a branch conditioned on an existing PLAN
      path, and a filed issue's next step is `/work-on`
- [ ] Each arm states what it passes; the strategy upstream is retired with its
      reason stated

**Dependencies**: Blocked by <<ISSUE:11>>

**Type**: docs
**Files**: `skills/explore/references/phases/phase-5-produce.md`

### Issue 13: feat(explore): re-point the routing tables and remove the artifact-type triage

**Goal**: Make the skill's own tables name outcomes rather than children, and
leave exactly one routing surface.

**Acceptance Criteria**:
- [ ] The destination columns of the routing table and the complexity table name
      no chain-internal child
- [ ] Rows whose distinction only mattered while PRD and DESIGN were separately
      choosable are removed rather than re-pointed
- [ ] `skills/explore/` names `/scope`, `/charter`, and `/execute`
- [ ] `skills/explore/` names neither `/spike` nor `/competitive-analysis`
- [ ] `phase-0-setup.md` assigns no `needs-*` label and contains no
      artifact-type triage
- [ ] The investigation-versus-breakdown-versus-ready triage feeds the
      crystallize step rather than routing on its own
- [ ] Step 0.2a still writes `## Visibility` and Phase 1's hard stop still finds
      it
- [ ] The Label Pre-Gate's provenance is restated
- [ ] `references/label-reference.md` names no label whose only producer was the
      removed triage, and its skill-lookup rows all resolve
- [ ] The reference-files table is corrected

**Dependencies**: Blocked by <<ISSUE:12>>

**Type**: docs
**Files**: `skills/explore/SKILL.md`, `skills/explore/references/phases/phase-0-setup.md`, `skills/explore/references/label-reference.md`

### Issue 14: fix(children): re-ground the child-level handoff detection clauses

**Goal**: Stop three child skills naming a producer that no longer produces, and
retire the two clauses that lose their producer outright.

**Acceptance Criteria**:
- [ ] `/roadmap`'s clause names `/charter` as the producer that pre-populates it
- [ ] `/vision`'s and `/prd`'s clauses are retired, with the corresponding
      resume-ladder rows removed
- [ ] No clause in `skills/prd/`, `skills/vision/`, or `skills/roadmap/` names
      `/explore` as a handoff producer
- [ ] The topic-branch ordering is stated where a reader of either parent's
      ladder will find it

**Dependencies**: Blocked by <<ISSUE:12>>

**Type**: docs
**Files**: `skills/prd/references/phases/phase-1-scope.md`, `skills/vision/SKILL.md`, `skills/roadmap/SKILL.md`

### Issue 15: test(scope): rewrite the scenarios grading the retired absorbability model

**Goal**: Stop the executable statement of `/scope`'s behavior from grading the
model #302 removed.

**Acceptance Criteria**:
- [ ] No `/scope` scenario asserts a durable-artifact floor
- [ ] No `/scope` scenario names the retired `absorbable:` field
- [ ] No `/scope` scenario derives an absorb verdict from either type's
      required-section list
- [ ] Describing where absorbed content landed is preserved, since that is the
      carry check rather than an absorbability derivation
- [ ] The suite covers a keep reached by reading two bodies, an absorb reached
      through the citation preflight and carry check, a carry-check failure
      aborting an absorb, and the absence of a floor
- [ ] `skills/scope/evals/evals.json` contains at least four scenarios covering
      the consolidation judgment and the durable-artifact floor

**Dependencies**: Blocked by <<ISSUE:9>>

**Type**: task
**Files**: `skills/scope/evals/evals.json`

### Issue 16: test(suites): re-target routing scenarios and converge the prompt pins

**Goal**: Make every scenario that asserts a routing destination name a parent,
and make the two parents assert the chain-proposal triad the same way.

**Acceptance Criteria**:
- [ ] No scenario in the `/explore`, `/roadmap`, or `/vision` suites asserts that
      `/explore` hands off to a chain-internal child
- [ ] The `/decision` suite's crystallize scenario is byte-identical to its
      pre-change form
- [ ] No `/scope` or `/charter` scenario requires a contiguous
      `Proceed / Adjust / Bail` string; both assert the three tokens individually
- [ ] Every re-targeted scenario carries an assertion array rather than leaving
      the claim in prose
- [ ] A scenario exercises each parent's handoff clause entering Phase 1

**Dependencies**: Blocked by <<ISSUE:13>>, <<ISSUE:15>>

**Type**: task
**Files**: `skills/explore/evals/evals.json`, `skills/roadmap/evals/evals.json`, `skills/vision/evals/evals.json`, `skills/charter/evals/evals.json`

### Issue 17: test(suites): verify the guard scenarios and reconcile the triage fallout

**Goal**: Confirm the scenarios that protect the model survived the change, and
resolve the two that grade a removed surface.

**Acceptance Criteria**:
- [ ] `/scope`'s chain-shape-is-constant retains its first, second, and fourth
      expectations verbatim
- [ ] Its third expectation names the narrowed redirect rather than being deleted
- [ ] `/charter`'s four roadmap-declination scenarios are byte-identical to their
      pre-change form
- [ ] The two `explore-handoff-detection` scenarios are byte-identical apart from
      re-grounding the producer attribution
- [ ] The two `/explore` triage scenarios either grade a surviving surface or are
      removed with the surface they graded

**Dependencies**: Blocked by <<ISSUE:16>>

**Type**: task
**Files**: `skills/scope/evals/evals.json`

### Issue 18: docs(pipeline): reconcile the corpus-wide routing model

**Goal**: Stop the pipeline model describing routes into chain interiors while
naming `/explore` as the authority for the algorithm.

**Acceptance Criteria**:
- [ ] `references/pipeline-model.md` describes no route from `/explore` into a
      chain interior
- [ ] It describes no classification-driven skip of chain steps
- [ ] Its pointer to `/explore` as the authority resolves to the router
- [ ] The error count over the whole docs corpus does not increase

**Dependencies**: Blocked by <<ISSUE:13>>

**Type**: docs
**Files**: `references/pipeline-model.md`

## Dependency Graph

## Implementation Sequence

**Critical path**: 1 → 2 → 11 → 12 → 13 → 16 → 17. Seven issues deep. The
crystallize restructure and the produce-handler rebuild are the two largest
pieces and both sit on it.

**Parallelizable once issue 1 lands**: issues 2, 3, and 8 have no dependency on
each other. Issue 8 is the bail fix and touches files nothing else in that wave
writes.

**Parallelizable once issue 2 lands**: issues 4, 5, and 11. The router branch
(11 → 12 → 13) runs independently of the parent branch (4 → 6 → 7) for its whole
length, and the two only rejoin at the eval work.

**Serialized by file ownership**: issues 6 and 7 both write both parents' resume
files, and issue 7 depends on 6 for that reason as much as for its logic. Issues
15, 16, and 17 all write eval suites and are chained deliberately, because 17 is
a verification step and running it before 15 and 16 would verify nothing.

**The two brief inconsistencies** the design names sit between issues 3 and 9,
and between issues 8 and 12. Both are managed by ordering rather than dissolved
by it: the bail's test is written in its final positive form in issue 8 rather
than being tightened after the handoff lands in issue 12.
