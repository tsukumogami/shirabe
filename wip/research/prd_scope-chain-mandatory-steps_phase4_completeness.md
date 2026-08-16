# Phase 4 jury — completeness review

Artifact: `docs/prds/PRD-scope-chain-mandatory-steps.md` (33 requirements, 35
acceptance criteria).
Upstream: `docs/briefs/BRIEF-scope-chain-mandatory-steps.md`.
Research read in full: the three `phase2_*` files.

## Verdict

**FAIL**

The PRD is unusually strong on research uptake — it reverses a brief assumption
with reasoning, it carries both live misroutes the router would inherit, and
its Decisions section closes both deferred questions with real alternatives.
It fails on completeness for concrete, fixable reasons: two requirements
contradict their own acceptance criteria or another requirement, three
requirements have no covering criterion at all, and one research finding of the
same class the PRD exists to eliminate (a stale cross-skill reference left
pointing at a producer that no longer produces) is created by R17 and addressed
nowhere.

## Per-Criterion

### 1. Traceability to the brief's Scope Boundary

**Brief IN items, all covered.** Every one of the eight IN bullets has at least
one requirement: `/explore`'s routing surface (R10, R12, R15, R16), its durable
authoring (R11), its terminal recording set (R14), `/scope` Phase 1's proposal
and the stale prose beside it (R22, R24, R25, R26, R27), the two shared
reference docs (R1–R7), `skills/scope/evals/evals.json` (R28, R29), the
cross-suite `/explore` scenarios (R30), and `references/pipeline-model.md`
(R33). No IN item is orphaned.

**Four requirements have no home in the IN list.**

- **R8** (`/charter`'s internal `/comp` contradiction) and **R9**
  (`/charter`'s Phase 1 Adjust) change `/charter`'s own skill files —
  `phase-state-management.md` and `phase-1-discovery.md`. The brief's IN list
  reaches `references/parent-skill-pattern.md` and
  `references/parent-skill-state-schema.md`, not `skills/charter/`. The
  research justifies R8 well (pattern-surface §6.2: the schema edit would
  otherwise land on a parent that contradicts itself) but the PRD never states
  that justification, so a reader checking scope against the brief sees an
  unexplained expansion into a repo area the brief's Out list treats as
  deliberately fenced.
- **R17–R21** (the handoff path, parent-side Slot 7 consumption, the handoff's
  content contract, the two misroute fixes, slug re-validation) are a new
  parent-level subsystem. The brief IN says only that "the wip handoff
  artifact that lets a downstream skill skip its own scoping phase survives" —
  which describes the *existing* child-level contract, not a new parent-level
  one. Moving consumption from children to parents follows necessarily from
  routing to parents, so this is defensible, but it is not stated as following
  from anything. R20 is the exception: its inclusion is explicitly argued in
  Decisions and Trade-offs, which is the model the other four should follow.

**One brief IN item is contradicted rather than covered.** The brief's third IN
bullet says the terminal recording set — rejection record, decision record,
spike report, competitive analysis — "stays, because no entry point can receive
them." R14 converts two of the four into routes (`/comp`, `/decision`). The PRD
argues the change well in Decisions and Trade-offs, and the research supports it
(router-contract §5.4: straight duplication of a path `/comp` already owns).
But the brief was edited in place after the PRD landed — its Status section says
so — and this reversal did not make it into that edit, so the two documents now
disagree on a scope boundary.

### 2. Requirement-to-criterion coverage

Full map below. Three requirements have no covering criterion, four are only
partially covered, and one criterion contradicts its own requirement.

**Uncovered:**

- **R5** — the `planned_chain`/`chain_ran`/`chain_skipped` triad contract:
  per-parent constancy stated, and the never-planned category named as a
  first-class member. No criterion mentions `planned_chain` constancy or the
  never-planned category. AC5 covers the reason vocabulary (R4) and AC6 covers
  the entry key (R6); R5's own substance is unverified. This matters because
  R5 is the requirement that lets `/charter` conform without recording
  `/comp` — the visibility argument the research called load-bearing.
- **R15** — removal of `/explore`'s Phase 0 artifact-type triage and
  reconciliation of the Stage 1 triage. No criterion. AC10's grep for
  chain-internal skill names does not catch it: Stage 2 emits `needs-prd` /
  `needs-design` / `needs-spike` / `needs-decision` labels, not skill
  invocations.
- **R19** — the handoff carries conversation, never filesystem state, and
  SHALL NOT pre-supply artifact existence, status, content hashes, visibility,
  or upstream validation. No criterion. AC16 verifies only that Slot 7 enters
  Phase 1. R19 is the requirement that stops the handoff from becoming a
  staleness vector, and nothing checks it.

**Partially covered:**

- **R10** — "the scoring procedure, the demotion rule, the tiebreakers ... and
  the insufficient-signal fallback SHALL survive." AC10 and AC11 check only
  which names appear. Nothing verifies the crystallize machinery survived the
  table replacement, which is the half of R10 most likely to be lost by an
  implementer rewriting ten signal tables.
- **R13** — AC11 requires `/explore` to name `/execute`, but nothing verifies
  the two substantive claims: that the file-an-issue arm's stated next step is
  `/work-on`, and that the `/execute` arm fires only when a PLAN already
  exists. Both are the point of the requirement.
- **R14** — AC14 covers the competitive arm only. Nothing verifies that a
  decision routes to `/decision`, or that the spike and rejection arms keep
  working.
- **R2** — AC3 checks the three properties. R2's final clauses (the prompt may
  not ask whether the artifact is worth producing; a one-sentence
  no-behavior-change note) are unverified.

**Contradiction between a requirement and its criterion:**

- **R31 vs AC31.** R31 says `chain-shape-is-constant` keeps the three
  expectations about the whole chain running, the unwritten-document judgment,
  and consolidation-after-both-exist, and that "its **fourth** expectation
  SHALL be updated to match R24's narrowed redirect." AC31 says the scenario
  "retains its **first, second, and fourth** expectations verbatim." Read
  against the file, AC31 is right and R31 is wrong. Scenario 17's expectations
  are, in order: (1) whole chain runs, (2) unwritten-document judgment,
  (3) "Plan points the author at invoking /design directly if they want to
  start above /brief", (4) redundant BRIEF removed by Phase 2 consolidation.
  The contested one — the one R24 narrows — is **the third**. As written, R31
  instructs an implementer to rewrite the consolidation expectation and leave
  the direct-invocation one alone, which is the opposite of the intent and
  would delete a guard the PRD elsewhere says must survive.

**Criteria verifying nothing stated as a requirement:**

- AC35 (`shirabe validate` reports zero errors across `docs/`) traces to no
  requirement. It is reasonable hygiene and I would keep it, but it should be
  named as such rather than sitting unattributed among 34 traceable criteria.

### 3. Research uptake

The PRD uses the research heavily and honestly: both misroutes (router-contract
§1.3/§1.4) become R20 with an argued reason for fixing them here; the
`/execute`-takes-only-a-PLAN finding (§4.4) becomes R13 and a Decision; the
`/comp` duplication (§5.4) becomes R14; the closed-enum reasoning including the
public-state-file leak argument (pattern-surface §4.4) is reproduced almost
intact; the CI finding (eval-inventory §CI) lands as a Known Limitation rather
than being quietly dropped. Bucket A, B, C and D of the eval inventory all have
requirements (R28, R29, R30, R31).

**Findings the PRD does not address, in descending order of consequence:**

1. **The child-level handoff detection clauses are orphaned by R17, and this is
   the exact defect class the PRD exists to remove.** Research §1.2 documents
   three live clauses: `/prd` (`phase-1-scope.md:14`), `/vision`
   (`SKILL.md:96-101`, ladder `:153`, phase table `:184`,
   `phase-1-scope.md:14-18`), `/roadmap` (`SKILL.md:138-145`, ladder `:234`,
   phase table `:269`, `phase-1-scope.md:26-30`). Each detects an
   `/explore`-written handoff. R17 moves `/explore`'s handoff to a
   parent-namespaced path and R10/R12 stop it routing to those children, so
   nothing `/explore` produces reaches any of them. Out of Scope then says the
   child skills "keep their structure," which makes the omission look
   deliberate. The result would be `skills/vision/SKILL.md:96` still telling a
   reader "an /explore session already ran Phase 5 and wrote the handoff
   artifact" about a handoff `/explore` no longer writes — a stale cross-skill
   reference of precisely the kind this PRD is cleaning up.
2. **AC30's stated reason is false for one of the two scenarios it protects.**
   R30 says the receiving-side scenarios survive "because `/charter` writes the
   same file." Verified against the tree: `/charter` pre-populates
   `wip/roadmap_<topic>_scope.md` only
   (`charter/.../phase-2-chain-orchestration.md:423-428`). Nothing in
   `/charter` writes `wip/vision_<topic>_scope.md`; its only writers are
   `/explore`'s Phase 5 handler (removed here) and `/vision`'s own Phase 1
   (`vision/.../phase-1-scope.md:79`). Both scenarios are fixture-driven so
   both would still mechanically pass, but the vision one would be named
   `explore-handoff-detection` while grading a path `/explore` never touches.
3. **A third filename/branch collision, of the same family as R20's two, is
   unaddressed.** Router-contract §6.4 item 2: `/explore` Phase 0 step 0.1
   creates and switches to a `docs/<topic>` branch, and both parents'
   meta-ladder rows key on "on branch related to topic" (`/scope` SKILL.md:337-338,
   `/charter` phase-resume.md:304-314). An `/explore` run that creates the
   branch and then routes to `/scope <topic>` lands the parent in the
   resume-at-Phase-1 row, skipping Phase 0, on what the author experiences as a
   first invocation. The research called this "a real design question, not a
   detail." It appears in no requirement, no Known Limitation, and no Out of
   Scope line.
4. **R7 treats as mechanical what the research established is not.**
   Pattern-surface §5.2 found four mechanical roster edits and one that needs a
   decision: line 381-384 asserts "the mechanism in v1 is the Skill tool," which
   becomes false the moment `/execute` joins the roster (its children are
   koto-materialized `/work-on` runs, `execute/SKILL.md:740-744`), and "all
   seven children" is already wrong today because it omits `/comp`. R7 says only
   that the roster SHALL name `/execute` and that fixed counts SHALL be
   corrected. The child-roster question (does a conditional feeder count? does
   `/work-on`?) and the dispatch-mechanism variance are both unresolved.
5. **R9 under-answers the conflict the research flagged as sharpest.**
   Pattern-surface §3.2 found that `/charter`'s Adjust can "opt out of a child
   that would otherwise fire" at Phase 1, *before any artifact exists* — which
   fails R2's own second property (formed against a document on disk). R9
   requires only that the opt-out carry "a recorded ground," which fixes the
   third property and leaves the timing problem untouched. As drafted, R2 and R9
   are in tension: R9 sanctions a declination R2 defines as non-conforming.
6. **R15's eval fallout is uncovered.** Removing Phase 0's Stage 2 triage
   breaks explore evals 15 and 16, which grade the triage's option labels and
   its primary-gap heuristic (`needs-prd` before `needs-design` before
   `needs-spike`). Research listed both as borderline Bucket C. R30 covers only
   scenarios asserting handoff to a chain-internal child, which these are not.
7. **Two Phase 0 preservation warnings are not carried.** Research §6.3: the
   Phase 1 hard stop at `:147-150` requires `## Visibility` written by Phase 0
   step 0.2a, so any Phase 0 surgery must preserve 0.2a or the run stops; and
   the Label Pre-Gate's provenance story changes when Stage 2 goes, so it needs
   restating. R15 authorizes the surgery without either constraint.
8. **`--upstream` passing is nowhere in the requirements.** Research §4.2/§4.3
   documents both parents' signatures (`/charter` takes a `VISION-` basename,
   `/scope` a `ROADMAP-` basename under `docs/roadmaps/`), and §3.2 recommends
   an identified VISION be passed via the flag rather than embedded. Separately,
   `/explore`'s current roadmap handler passes `--upstream <STRATEGY>` to
   `/roadmap` — a capability with no home once that arm routes to `/charter`,
   which does not accept a STRATEGY. No requirement covers either half.
9. **Pattern doc line 429 is not reconciled.** Research §6.2: "advances
   `planned_chain`" reads as a per-dispatch mutation matching neither parent,
   and "needs to agree with" whatever constancy the schema settles on. R5
   settles the constancy and leaves 429 alone.
10. **R30 names the `/decision` suite, contradicting R14.** The only
    decision-suite scenario in Bucket C is id 5, which asserts `/explore` hands
    off to `/decision`. R14 keeps that route, and the PRD's own Decisions
    section says a Decision Record is not a chain artifact — so `/decision` is
    not a chain-internal child and its scenario should not be re-targeted. As
    written, R30 and AC29 instruct an implementer to break a correct scenario.

Two smaller items I checked and am **not** calling gaps, because the PRD
excludes them properly: the `team.yaml` glob marker with no instances
(pattern-surface §5.2 reason 3) is an honest omission from a PRD whose Out of
Scope fences `/execute`'s behavior; and the fifth enum identifier
`chain-terminated-before-invocation` with no writer is handled by R4's "SHALL
admit every ground the two parents record today," which drops it by
construction.

### 4. The brief's two Open Questions

**Q1 — what "a shorter chain" means to an author now: closed.** The Decision
gives a definition (fewer artifacts), distinguishes it from the thing direct
invocation actually buys (a shorter conversation), states which of the two the
corpus may keep offering, names the rejected alternative (retiring direct
invocation outright) with its cost (contradicts CLAUDE.md, strands four
standalone entry points), and carries the consequence through to the eval
surface. This is a model closure.

**Q2 — whether the abandonment exit must stay reachable from the author's flow:
closed, but thinly.** The Decision states the answer (yes, at the chain
proposal), names the mechanism (R22 keeps the option, R23 makes it work), and
gives one alternative (rely on the resume ladder's own prompt) with its cost
(the author must let `/brief` write first). What it does not do is say what the
exit *does*: R23 identifies both branches as unreachable — clean-cancel because
Phase 0 already wrote the state file, abandonment-forced because there is no
intermediate to materialize and hard finalization refuses an empty artifact
list — and then requires only that Bail "execute." Which branch survives, and
what abandonment-forced means with nothing to force, is left open. That is
arguably DESIGN work and I am not requiring it be settled here, but AC21
("reaches a defined terminal state") is doing a lot of unspecified work.

### 5. Out of Scope

Eight of the nine exclusions are doing real work: each names a boundary a
downstream implementer could plausibly cross, and each gives a reason rather
than a restatement. The `formats.rs` line is the best of them — an implementer
told the corpus states the wrong model would reasonably go looking at the code
that enforces it, and the line stops them. The `/execute` line usefully bounds
R7. The `/explore` research-loop line carries the shared-engine reason from the
research (`/charter` loads those phase files as its own Phase 1 backbone), which
is the non-obvious part.

The ninth — "The child skills' internal phase workflows. `/brief`, `/prd`,
`/design`, and `/plan` keep their structure" — is the one that misfires. Read
together with R17, it fences off exactly the edits needed to stop `/prd`'s
Phase 1 detection clause pointing at an `/explore` handoff that will no longer
exist, and it does not name `/vision` or `/roadmap`, whose clauses have the same
problem. As written it converts finding 1 above from an omission into a stated
exclusion of the fix.

## Requirement-to-Criterion Map

| Req | Covering AC | Verdict |
|---|---|---|
| R1 | AC1, AC2 | covered |
| R2 | AC3 | partial — worth-prohibition and no-behavior-change note unverified |
| R3 | AC4 | covered |
| R4 | AC5 | covered |
| R5 | — | **uncovered** |
| R6 | AC6 | covered |
| R7 | AC7 | partial — roster name only; dispatch-mechanism and child-roster unverified |
| R8 | AC8 | covered |
| R9 | AC9 | covered (but see R2 conflict) |
| R10 | AC10, AC11 | partial — surviving scoring machinery unverified |
| R11 | AC12 | covered |
| R12 | AC10 | covered |
| R13 | AC11 | partial — `/work-on` arm and PLAN-gated `/execute` arm unverified |
| R14 | AC14 | partial — decision, spike, rejection arms unverified |
| R15 | — | **uncovered** |
| R16 | AC13 | covered |
| R17 | AC15 | covered |
| R18 | AC16 | covered |
| R19 | — | **uncovered** |
| R20 | AC17, AC18 | covered |
| R21 | AC19 | covered |
| R22 | AC20 | covered |
| R23 | AC21 | covered |
| R24 | AC22 | covered |
| R25 | AC23 | covered |
| R26 | AC24 | covered |
| R27 | AC25 | covered |
| R28 | AC26, AC27 | covered |
| R29 | AC28 | covered |
| R30 | AC29, AC30 | covered — but AC30's premise is false for the vision suite, and R30's `/decision` inclusion contradicts R14 |
| R31 | AC31, AC32 | **contradictory** — R31 says update the fourth expectation, AC31 says keep it; the file says the contested one is the third |
| R32 | AC33 | covered |
| R33 | AC34 | covered |
| — | AC35 | criterion with no requirement |

## Required Changes

1. **Fix R31's expectation ordinal.** Scenario 17's contested expectation is the
   **third** ("Plan points the author at invoking /design directly if they want
   to start above /brief"), not the fourth. Change R31 to say the third
   expectation is updated to match R24's narrowed redirect, and that the first,
   second, and fourth survive verbatim — which is what AC31 already says. As
   drafted, R31 directs an implementer to rewrite the consolidation-after-both-
   exist guard.

2. **Remove the `/decision` suite from R30 and AC29, or state why it belongs.**
   The only decision-suite Bucket C scenario (id 5) asserts `/explore` hands off
   to `/decision`, which R14 preserves and the Decisions section confirms is not
   a chain artifact. As written, R30 requires re-targeting a scenario that
   should stay.

3. **Add a requirement covering the child-level handoff detection clauses.**
   R17 moves the handoff path and R10/R12 stop `/explore` routing to children,
   which orphans the detection clauses in `/prd` (`phase-1-scope.md:14`),
   `/vision` (`SKILL.md:96-101`, `:153`, `:184`, `phase-1-scope.md:14-18`) and
   `/roadmap` (`SKILL.md:138-145`, `:234`, `:269`, `phase-1-scope.md:26-30`),
   several of which name `/explore` in prose. State what happens to them —
   re-grounded on the surviving producer, or removed — and amend the Out of
   Scope line "the child skills' internal phase workflows" so it does not fence
   off this fix.

4. **Correct AC30's premise or narrow the criterion.** `/charter` pre-populates
   `wip/roadmap_<topic>_scope.md` only; nothing in `/charter` writes
   `wip/vision_<topic>_scope.md`. R30's justification ("because `/charter`
   writes the same file") holds for the roadmap suite's
   `explore-handoff-detection` and not the vision suite's. Say which producer
   grounds each, or require the vision scenario be re-grounded.

5. **Add acceptance criteria for R5, R15, and R19.** Suggested shapes:
   for R5, that `references/parent-skill-state-schema.md` states
   `planned_chain` constancy as a per-parent property and names the
   never-planned category, with `/comp` as the worked case; for R15, that
   `skills/explore/references/phases/phase-0-*.md` contains no artifact-type
   triage and emits no `needs-*` label as a routing decision; for R19, that the
   handoff template contains no artifact path, frontmatter status, content hash,
   or visibility value.

6. **Resolve the R2/R9 conflict.** R2's second property requires a conforming
   declination be formed against a document already on disk. `/charter`'s
   Phase 1 Adjust opt-out fires before any artifact exists
   (`charter/.../phase-1-discovery.md:387-388`). R9 requires only a recorded
   ground, which leaves the timing violation in place. Either narrow R9 to
   require conformance to all three of R2's properties, or state the Adjust
   opt-out as a named fourth removal ground with its own reasoning — the
   research called this the sharpest unresolved conflict it found and it is
   currently resolved in two incompatible directions in the same PRD.

7. **Address the `docs/<topic>` branch collision, or exclude it explicitly.**
   `/explore` Phase 0 creates a `docs/<topic>` branch; both parents' meta-ladder
   rows match "on branch related to topic" and resume at Phase 1, skipping
   Phase 0, on what the author experiences as a first invocation. This is the
   same class of defect as R20's two collisions and sits directly in the
   router's path. Give it a requirement or a Known Limitation with a reason.

8. **Expand R7 to carry the two non-mechanical parts of the roster fix.**
   Adding `/execute` to a roster whose surrounding text says "the mechanism in
   v1 is the Skill tool" makes the pattern doc assert something false, since
   `/execute` dispatches koto-materialized `/work-on` runs; and "all seven
   children" already omits `/comp`. Require the child roster be defined
   (whether a conditional feeder and `/work-on` count) and the dispatch
   mechanism either extended or `/execute` admitted as a named variance.

9. **Cover R15's eval fallout.** Explore evals 15 and 16 grade the Phase 0
   triage's option labels and its `needs-prd`/`needs-design`/`needs-spike`
   primary-gap heuristic. R15 removes the surface they grade and R30 does not
   reach them, since they assert triage labels rather than a handoff to a
   chain-internal child.

10. **Carry the two Phase 0 preservation constraints into R15.** Phase 1's hard
    stop requires `## Visibility` written by Phase 0 step 0.2a, so 0.2a must
    survive the surgery; and the Label Pre-Gate's `needs-*` provenance changes
    when Stage 2 goes and needs restating.

11. **State the router's `--upstream` behavior.** `/scope` accepts
    `--upstream <ROADMAP>` and `/charter` accepts `--upstream <VISION>` with
    basename enforcement. Additionally, `/explore`'s current roadmap handler
    passes `--upstream <STRATEGY>` to `/roadmap`; that capability has no home
    once the arm routes to `/charter`, which does not accept a STRATEGY. Say
    what the router passes and what becomes of the STRATEGY case.

12. **Reconcile the brief with R14, or say in the PRD that it supersedes the
    brief's third IN bullet.** The brief says the terminal recording set "stays,
    because no entry point can receive them"; R14 converts the competitive and
    decision arms into routes. The brief was already edited in place after the
    PRD landed, so the disagreement is live in two documents at once.

13. **Give R8 and R17–R21 a stated traceability line.** Both reach outside the
    brief's IN list — R8 into `/charter`'s own files, R17–R21 into a new
    parent-level handoff subsystem. R20 shows the right form: a sentence in
    Decisions and Trade-offs saying why the work belongs here. R8's reason is
    already in the research (the schema edit would land on a self-contradicting
    parent) and just needs stating.

## Optional Improvements

- **Reconcile `references/parent-skill-pattern.md:429** ("advances
  `planned_chain`") with R5's constancy statement. Small, concrete, and the
  research flagged it as needing to agree with whatever the schema settles.
- **Attribute AC35.** The `shirabe validate` criterion is good hygiene but
  traces to no requirement; naming it as a global gate rather than leaving it
  in the list would keep the map clean.
- **Add coverage for R10's surviving machinery.** A criterion asserting the
  crystallize scoring procedure, demotion rule, tiebreakers, and
  insufficient-signal fallback are still present after the table replacement
  would protect the half of R10 most at risk.
- **Say what Bail's surviving branch does.** R23 requires it to execute and
  AC21 requires "a defined terminal state." Naming which of clean-cancel and
  abandonment-forced survives would make AC21 checkable without pre-empting
  DESIGN.
- **Note the `REJECTED-*` naming drift.** Research §5.1 found `/explore` is the
  sole author of a filename convention matching nothing else in
  `docs/decisions/`, where every file is `DECISION-<topic>-<date>.md`. R14 keeps
  `/explore` as the rejection record's author without touching the convention.
- **Decide the dated-vs-undated retirement-note convention once.** The pattern
  doc's convention is dated, `/scope`'s two in-file versions are not
  (`phase-1-discovery.md:136-140`, `:266-288`). The PRD decides correctly that
  no dated block is needed here; the convention question itself is left open.
- **Consider folding the additive `stage: carry` coverage into R28.** Research
  offered it for scope eval 21 as non-breaking; the file will be open anyway.
