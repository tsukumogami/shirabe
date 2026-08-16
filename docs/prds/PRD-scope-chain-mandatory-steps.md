---
schema: prd/v1
status: Done
absorbed:
  - docs/briefs/BRIEF-scope-chain-mandatory-steps.md
problem: |
  The corpus gives two answers to whether a tactical-chain step is optional.
  /execute states the post-#302 model and /scope states it and then contradicts
  itself; /explore, the shared parent-skill pattern both parents inherit, and
  /scope's eval suite still state the model #302 replaced. Four surfaces in all,
  and an author meets a stale one first. The shared pattern is the load-bearing
  one: it never states the model, and it is the source of the prompt contract
  and the only clause in the corpus that authorizes dropping a step before its
  artifact exists.
goals: |
  One model, stated once where both parents inherit it, and every surface that
  describes chain shape agreeing with it. An author is routed to a chain entry
  point rather than to a step inside a chain, the tactical chain keeps the two
  author affordances that do real work while shedding the prose that
  contradicts them, and the eval suite grades the model the skills implement.
motivating_context: |
  Research at requirements altitude found two live misrouting bugs the router
  would otherwise inherit, and reversed a working assumption: the chain
  proposal's option triad does real work in both parents and should be
  specified rather than removed.
---

# PRD: Chain Steps Are Mandatory

## Status

Done

Requirements written from the brief this document absorbed. Both of that
brief's Open Questions are closed under Decisions and Trade-offs, along with
three decisions that reverse or narrow what it assumed.

Absorbed [BRIEF-scope-chain-mandatory-steps](docs/briefs/BRIEF-scope-chain-mandatory-steps.md); carried in Absorbed Brief.

## Absorbed Brief

**The problem the feature solves.** Shirabe's tactical chain used to let a step
be skipped because someone judged its document not worth writing. #280 argued
that judgment is the wrong shape, because whether a document carried anything
can only be decided against a document that exists, and #302 replaced it. The
corpus did not finish moving: four surfaces still describe the earlier world,
and they are the surfaces an author touches first.

**The outcome an author should experience.** They never decide which chain step
to start at. They choose an entry point, the chain runs whole, and whatever did
not earn its keep is folded once it and its successor both exist. Every surface
describing chain shape says the same thing, and the affordances the chain offers
them do what they claim.

**The journeys that exercise it.** An author who does not know what they need
and is routed to a place to start rather than to a document to write. An author
entering the tactical chain, who reads what will run and can correct a framing
answer or stop before the first child writes. An author who believes the
upstream work is unnecessary and is told why the chain runs anyway. A maintainer
building a third parent, who finds the model stated in the document both
existing parents inherit from. An agent graded by the eval suite, pulled toward
the model the skills implement rather than away from it.

**Where the feature ends.** In: the four stale surfaces, the handoff subsystem
the router needs, and the eval scenarios that grade any of it. Out: adding a
consolidation judgment to the strategic chain, retiring `/charter`'s roadmap
declination, `/execute`'s behavior, the absorption checks in code, and
re-opening what #302 settled. The Requirements and Out of Scope sections below
carry both lists at full resolution.

**Framing provenance.** This work finishes propagating #302, whose own
documents — `BRIEF-`, `PRD-` and `DESIGN-scope-artifact-persistence.md` — state
the rule it enforces: no judgment runs before the artifact it is about exists,
including an author-chosen entry altitude. Its predecessor pair,
`PRD-` and `DESIGN-scope-consolidation-over-skipping.md`, each carry an
amendment recording what #302 falsified; that amendment shape is this corpus's
precedent for superseded durable prose.

## Problem Statement

Issue #280 argued that deciding a document is not worth producing before it
exists is the wrong-shaped judgment, and #302 replaced it: `/scope` now runs
BRIEF → PRD → DESIGN → PLAN on every invocation and reduces the artifact set
afterward, per hop, against two bodies that exist. The change did not propagate.
Four surfaces still describe the earlier model, and they are the surfaces an
author touches first.

`/explore` answers "I don't know what I need" by naming a chain step. Its
routing tables and ten-type crystallize framework send authors to `/prd`,
`/design`, `/plan`, `/vision`, and `/roadmap`, entering the tactical chain at
three depths and the strategic chain at two, with no vocabulary for BRIEF or
STRATEGY. `/scope`, `/charter`, and `/execute` are named nowhere in the skill;
a recursive search for `explore` across `skills/scope/` returns nothing in
either direction. Four of its produce handlers write committed documents,
including a DESIGN skeleton at `docs/designs/DESIGN-<topic>.md`.

`/scope` states the model and then contradicts it in the same file. Phase 1 says
`planned_chain:` is constant and no starting altitude is choosable, then gives a
redirect to invoke `/design` or `/plan` directly for "a shorter chain" — which a
later section of that same file calls an escape hatch from a constraint that no
longer exists. Its Phase 1 bail is documented as the author's only stop before
`/brief` writes, and cannot execute either of its branches: clean-cancel is
unreachable because Phase 0 always wrote the state file, and abandonment-forced
has no child intermediate to materialize and fails the hard-finalization check
on an empty artifact list.

The shared parent-skill pattern never states the model at all. Searching it and
the state schema for `consolidat`, `absorb`, `fold`, `worth`, or `earn` returns
nothing. It is the source of the chain-proposal prompt contract both parents
emit and both eval suites grade, its `chain_skipped[].reason` vocabulary is free
text that the two parents close incompatibly, and its ALWAYS gate carries the
only clause in the corpus authorizing a child to be dropped before its artifact
exists. Its parent roster predates `/execute`.

The eval suite is the only executable statement of what `/scope` should do, and
three scenarios grade the retired model. One asserts a durable-artifact floor
against a skill section titled "There is no durable-artifact floor"; another
requires deriving absorbability from per-type required-section lists, which the
skill names as the defining violation, and records a field the skill calls
retired. This is an unmet requirement of #302's own PRD with two unchecked
acceptance criteria, behind documents at terminal status. Nothing caught it:
the eval workflow runs on a Monday cron and never on a pull request, and the
pull-request check only counts that eval files are non-empty.

Two further defects surfaced at requirements altitude, both of which the router
would inherit rather than introduce. `/scope`'s resume-ladder Slot 6.3 globs
`wip/prd_<topic>_*`, which matches the handoff `/explore` writes at
`wip/prd_<topic>_scope.md`; the parent reads it as an interrupted `/prd` run and
re-invokes that child directly, skipping `/brief`, its own Phase 1, and the
chain proposal. `/charter`'s ladder row 8 matches `wip/vision_<topic>_scope.md`
exactly — the same filename `/explore` writes — and jumps into `/vision`,
bypassing Phase 0 and Phase 1 so no state file is created and `/strategy` and
`/roadmap` are never scheduled.

## Goals

The corpus states one model in the document both parents inherit from, and every
surface that describes chain shape agrees with it.

An author who does not know what they need is routed to a chain entry point.
Choosing among artifact types stops being something a skill does on the author's
behalf before any artifact exists.

The tactical chain keeps the two author affordances that do real work — the
ability to correct a framing answer before the first child fires, and the
ability to stop before it does — and both are made to function as documented.

The executable statement of `/scope`'s behavior agrees with the prose, and the
scenarios that guard the model against regression survive intact.

## User Stories

Use-case descriptions, since the users here are authors and maintainers of a
workflow toolkit rather than end users of a product.

**An author who does not know what they need.** They run `/explore`, it
researches and converges, and it routes them to file an issue, to `/charter`, to
`/scope`, or to an existing PLAN. It does not tell them to write a PRD or a
design doc, and it does not write one for them.

**An author entering the tactical chain.** They run `/scope` and read what will
run, why each child fires, and what happens to the documents afterward. They can
correct a framing answer that was wrong, and they can stop before the first
child writes. Neither affordance claims to do something it cannot.

**An author who believes the upstream work is unnecessary.** They arrive with
the framing settled, expecting to skip ahead. `/scope` runs the whole chain and
says why, and tells them what invoking a child directly does and does not buy
them.

**A maintainer building a third parent skill.** They read the shared pattern and
find the model stated, along with what a skip may legitimately mean and how an
author declination differs from a gate the parent computes.

**An agent graded by the eval suite.** Every scenario it meets describes the
model the skills implement. Nothing rewards comparing two types' section lists,
and nothing asserts a floor the skill denies having.

## Requirements

### The shared pattern states the model

**R1.** `references/parent-skill-pattern.md` SHALL state, at the head of its
Gate Vocabulary section, that chain steps are mandatory and reduction is
post-hoc. The statement SHALL name the grounds on which a child may legitimately
not run, SHALL say that a judgment about whether one document holds anything its
successor does not is only answerable against two documents that exist, and
SHALL be true of `/scope`, `/charter`, and `/execute` as they exist. It SHALL
NOT require a parent to define a post-hoc reduction mechanism, because
`/charter` and `/execute` define none.

**R2.** The ALWAYS gate's declination clause SHALL be restated so that an author
declination reads as an instance of the model rather than an exception to it.
The restatement SHALL name three properties a conforming declination has:

- **Author-supplied.** No predicate the parent evaluates can produce the skip on
  its own, and a non-interactive run invokes the child. `/charter`'s roadmap
  prompt already behaves this way under `--auto`.
- **Formed against a document already on disk.** The prompt fires after the
  upstream artifact exists, so the author answers about something they can read.
- **Recorded.** The child remains in `planned_chain` and the skip lands in
  `chain_skipped` with a ground drawn from R4's vocabulary.

The clause SHALL state that the prompt may not ask whether the child's artifact
is worth producing, and SHALL carry a one-sentence note that no behavior
changed. It SHALL NOT carry a dated-retirement block, because nothing is
retired.

**R3.** The pattern's prompt literal-form contract SHALL state what the chain
proposal's Adjust option is guaranteed to reach and what is per-parent. Adjust
SHALL re-enter the parent's discovery and re-emit the proposal; whether that
re-entry can change chain membership SHALL be declared a per-parent property,
with each parent stating which it has in its own chain-proposal section. The
contract SHALL state that no parent may use Adjust to reach a child whose
artifact the parent judged not worth producing.

**R4.** `chain_skipped[].reason` SHALL be bounded to a closed vocabulary defined
in `references/parent-skill-state-schema.md`. The vocabulary SHALL admit every
ground either parent records today and SHALL NOT be able to express a worth
judgment; free text SHALL move to an optional sibling field that is never the
ground. Its extension path SHALL reuse the grow-by-PR-review discipline already
stated in `references/parent-skill-child-inspection.md` for the child-shape
table, rather than inventing a second one. A vocabulary member with no writer
SHALL NOT ship.

**R5.** The `planned_chain` / `chain_ran` / `chain_skipped` triad contract SHALL
state that whether `planned_chain` is the same on every run is a per-parent
property, with `/scope`'s constant and `/charter`'s varying by its Phase 1
gates, and that both shapes satisfy the same rule. It SHALL name the
never-planned category as a first-class member: a conditional feeder whose gate
never opened appears in neither list, and the state file names no reason for it,
because the state file is durably public and the feeder's artifact type may be
private-only. The pattern's Pre-Dispatch State description, which currently says
a parent "advances `planned_chain`" per dispatch, SHALL be reconciled with
whatever constancy the schema settles on.

**R6.** The `chain_skipped` entry key SHALL be the same in both parents.
`/scope` writes `name:` and `/charter` writes `child:`; the pattern specifies
neither. One SHALL be chosen and both parents plus their graded eval strings
brought to it.

**R7.** Within `references/parent-skill-pattern.md` and
`references/parent-skill-state-schema.md`, every statement enumerating the
parent set or a fixed child count SHALL be corrected. `/execute` SHALL appear in
the parent roster. Two of these are not one-line edits and SHALL be resolved
explicitly: the child roster's cardinality, which currently omits `/comp` and
does not say whether `/work-on` counts; and the dispatch mechanism, which the
pattern states as the Skill tool while `/execute` dispatches koto-materialized
`/work-on` runs — `/execute` SHALL be admitted as a named variance or the
mechanism statement SHALL be widened. Statements genuinely about the two
authoring parents SHALL say so rather than saying "both v1 parents".

**R8.** `/charter`'s internal contradiction about `/comp` SHALL be resolved in
favor of the Phase 2 rule, which carries the visibility argument: `/comp` is
absent from `planned_chain` and has no `chain_skipped` entry. The state-schema
sites that list it as a member SHALL be corrected. This is in scope because R5's
schema edit would otherwise land on a parent that contradicts itself about the
worked example the schema names.

**R9.** `/charter`'s Phase 1 Adjust option SHALL NOT permit an author to opt a
child out. Its current wording permits dropping a child that would otherwise
fire, before any artifact exists and with no recorded ground, which fails the
second and third of R2's properties. Adjust SHALL retain its other documented
powers — re-framing the topic, correcting the thesis-shift answer, and forcing a
previously-skipped child on — because forcing a child on adds work rather than
removing it. An author who wants a child dropped SHALL use that child's own
declination prompt, which is where the judgment is formed against a document
that exists.

### `/explore` routes to entry points

**R10.** `/explore`'s crystallize step SHALL score two things and score them in
sequence. First, whether the exploration reached a chain at all, or reached one
of the terminal outcomes no chain owns (R14). Second, for a chain outcome, which
entry point: file an issue, `/charter`, `/scope`, or `/execute`. The scoring
procedure, the demotion rule, the tiebreakers that discriminate between
outcomes, and the insufficient-signal fallback SHALL survive; the ten
per-artifact-type signal tables SHALL be replaced by per-outcome ones. No
scoring category SHALL name a chain-internal child.

**R11.** `/explore` SHALL NOT author a durable chain artifact. The DESIGN
skeleton its design handler writes SHALL be removed. Writing a `wip/` handoff
artifact is not authoring a durable artifact and SHALL survive.

**R12.** `/explore`'s routing tables, complexity table, and detection algorithm
SHALL name outcomes from R10 rather than chain-internal children. Where a row's
distinction only mattered while PRD and DESIGN were separately choosable, the
row SHALL be removed rather than re-pointed.

**R13.** Each arm SHALL name a destination that can receive what the arm hands
over. `/execute` accepts only a PLAN path, so that arm SHALL be reachable only
when a PLAN already exists. The file-an-issue arm's stated next step SHALL be
`/work-on`, which is the skill that accepts an issue number.

**R14.** The four artifact types no chain owns SHALL remain reachable, decided
per type. Competitive analysis SHALL route to `/comp`, which already owns the
same path and drives a jury and a lifecycle transition the inline handler does
not; the duplicate inline handler SHALL be deleted. A decision SHALL route to
`/decision`. A spike report and a rejection record have no owning skill, so
`/explore` SHALL keep authoring them; neither is a chain artifact.

**R15.** `/explore`'s Phase 0 artifact-type triage SHALL be removed. It commits
to one of four `needs-*` labels before Phase 1 runs, and the crystallize step
overrides it anyway. `references/label-reference.md` SHALL be updated in the
same change: the labels whose only producer was this triage SHALL be retired or
re-grounded on a surviving producer, and the two skill-lookup rows that already
dangle SHALL be corrected.

**R16.** `/explore`'s Phase 0 investigation-versus-breakdown-versus-ready triage
SHALL be resolved to one of two shapes, and the PRD does not pick between them
because either satisfies the model: it is deleted and its question folded into
the crystallize step, or it is kept and its outputs feed the crystallize step
rather than routing on their own. What SHALL NOT survive is two routing surfaces
in one skill reaching different conclusions.

**R17.** Phase 0's two constraints that are not part of the triage SHALL survive
the surgery: step 0.2a, which writes the `## Visibility` value that Phase 1
hard-stops without, and the Label Pre-Gate, whose `needs-*` provenance changes
once the triage stops writing labels and SHALL be restated rather than left
implying a producer that no longer exists.

**R18.** Every shirabe skill destination named in `skills/explore/` SHALL
resolve to a directory under `skills/`. `/spike` and `/competitive-analysis`
resolve to nothing today. Workspace-plugin destinations outside shirabe are not
in scope for this requirement.

### The handoff, and the collisions it would inherit

**R19.** The `/explore` handoff artifact SHALL move to a parent-namespaced path
that collides with no existing resume-ladder match condition in either parent.
The current `wip/<child>_<topic>_scope.md` convention is kept by `/charter` for
its own pre-populated handoffs to `/roadmap`, so the router's artifact SHALL be
distinguishable from a parent's own. R22's narrowing of the colliding match
conditions is defense in depth, not the whole fix.

**R20.** Both parents SHALL detect an `/explore` handoff and consume it. In
`/scope` the clause SHALL fill the reserved, currently vacuous Slot 7. In
`/charter`, whose resume ladder uses row numbering rather than slot vocabulary
and whose row 7 is already occupied, the clause SHALL be placed without
renumbering the shared meta-ladder tail. In both, the action SHALL be to enter
the parent's Phase 1 with the handoff's content pre-loaded as discovery input,
never to skip Phase 1 and never to route into a child.

**R21.** The handoff SHALL carry conversation, never filesystem state. It may
pre-supply the framing-shift or thesis-shift answer with its evidence, the
problem statement and scope boundary, the accumulated decisions, and a shape
estimate the parent re-derives later. It SHALL NOT pre-supply artifact
existence, frontmatter status, content hashes, visibility, or upstream
validation, and each parent's clause SHALL state that those are re-read on every
run.

**R22.** The two existing misroutes SHALL be fixed. `/scope`'s Slot 6.3 glob and
`/charter`'s row 8 match condition SHALL be narrowed so neither can match a
handoff artifact.

**R23.** Slug re-validation SHALL cover the new clause. The rule that slugs
recovered from on-disk paths are re-validated before interpolation currently
enumerates Slot 5 and Slot 6 only.

**R24.** The child-level handoff detection clauses SHALL be re-grounded. `/prd`,
`/vision`, and `/roadmap` each detect a handoff artifact and skip their own
scoping phase, and several name `/explore` in prose as the producer. Once
`/explore` routes to parents, the surviving producer is the parent, and the
clauses SHALL name it. This is scoped work on those skills' handoff detection
only; their phase structure is otherwise out of scope.

**R25.** The router SHALL state what it passes with each arm. `/scope` accepts
`--upstream <ROADMAP>` and `/charter` accepts `--upstream <VISION>`, each with
basename enforcement. `/explore`'s current roadmap handler passes
`--upstream <STRATEGY>` to `/roadmap`; that value has no receiver once the arm
routes to `/charter`, and the requirement SHALL say what becomes of it.

**R26.** The interaction between `/explore`'s topic branch and both parents'
branch-matching ladder rows SHALL be resolved or excluded with a reason.
`/explore` Phase 0 creates a `docs/<topic>` branch, and both parents have a
meta-ladder row matching "on a branch related to the topic" that resumes at
Phase 1, skipping Phase 0 — on what the author experiences as a first
invocation. This is the same class of defect as R22's collisions and sits in the
router's path.

### `/scope`'s stale prose

**R27.** The chain proposal SHALL keep its three options. Bail is the author's
only surface for stopping before the first child writes, and Adjust is the only
in-prompt route to correcting a framing-shift answer, which is the override that
fires `/brief` against a settled BRIEF. The stale justification attached to the
proposal — that it offers no shorter chain "because `/scope` has no way to
produce one" — SHALL be corrected, since `/scope` does now produce a smaller
artifact set.

**R28.** Bail at Phase 1 SHALL execute, and SHALL reach clean-cancel. Both
branches are unreachable today: clean-cancel because Phase 0 always wrote the
state file before Phase 1 runs, and abandonment-forced because no child has
produced an intermediate to force-materialize and the hard-finalization check
refuses an empty artifact list. Clean-cancel is the correct outcome because
abandonment-forced exists to preserve a partial artifact, and at Phase 1 there
is none; the wip-state test that routes between them SHALL exclude the parent's
own state file, and the bail SHALL dispose of it.

**R29.** The direct-invocation redirect SHALL be narrowed rather than retired. A
child invoked directly remains supported. What SHALL be removed is the
justification that it is how an author reaches a smaller artifact set, since
consolidation now decides that after the fact. The two rules SHALL be stated as
distinct: `/explore` routes to parents, and an author may still invoke a child
directly for a shorter conversation.

**R30.** `chain_revised:` SHALL be either specified or removed. It is written by
a phase file, absent from `/scope`'s own state schema, read by nothing, and
named for the produce-or-skip behavior the same file retires.

**R31.** The post-`/prd` re-evaluation gate's second confirmation prompt SHALL
be specified or removed. It currently has no options block, no branch list, and
no state record of the answer.

**R32.** The claim that Phase 2 writes "one further reason" into `chain_skipped`
SHALL be corrected. Two distinct reason strings are written, by the two
rejection templates, and neither is enumerated in the state schema.

### The evals

**R33.** The three `/scope` scenarios grading the retired absorbability model
SHALL be rewritten so that no scenario asserts a durable-artifact floor, names
the retired `absorbable:` field, or derives an absorb verdict from either type's
required-section list. Describing where absorbed content landed is the carry
check and is not what this forbids. The rewritten set SHALL cover at least the
same ground: a `keep` reached by reading two bodies, an `absorb` reached through
the citation preflight and the carry check, a carry-check failure aborting an
absorb, and the absence of a durable-artifact floor.

**R34.** The `/scope` scenarios pinning the chain-proposal options block SHALL
be updated to match whatever the block becomes, and the byte-for-byte pin SHALL
be decoupled from the claim it exists to make. `/scope` pins the literal
byte-for-byte while `/charter` asserts the same triad per-token and explicitly
tolerates a re-labelled option; both SHALL converge on the per-token form.

**R35.** Every scenario asserting that `/explore` hands off to a chain-internal
child SHALL be re-targeted at the parent that owns that chain, across the
`/explore`, `/roadmap`, and `/vision` suites. The `/decision` suite's
crystallize scenario SHALL NOT be re-targeted: R14 keeps that arm routing to
`/decision`, which is not a chain-internal child.

**R36.** The receiving-side scenarios SHALL survive with one narrow amendment.
`/roadmap`'s and `/vision`'s `explore-handoff-detection` scenarios assert that a
child detects a handoff and skips its own scoping phase, which stays true. Where
such a scenario attributes the handoff to `/explore` in prose, the attribution
SHALL be re-grounded on the surviving producer per R24. `/charter` pre-populates
the roadmap handoff itself, so that scenario's producer is unchanged.

**R37.** The scenarios that guard the model SHALL survive. `/scope`'s
`chain-shape-is-constant` SHALL keep its first, second, and fourth expectations
verbatim — the whole chain runs, skipping a child would be a judgment about an
unwritten document, and a redundant artifact is removed by consolidation after
both exist. Its **third** expectation, which points the author at invoking
`/design` directly, SHALL be updated to match R29's narrowed redirect rather
than deleted. `/charter`'s four roadmap-declination scenarios SHALL survive
byte-identical.

**R38.** The `/explore` scenarios grading the Phase 0 triage SHALL be reconciled
with R15 and R16. Two of them grade the triage's option labels and its
`needs-prd` / `needs-design` / `needs-spike` primary-gap heuristic, which R15
removes; R35 does not reach them because they assert labels rather than a
handoff.

**R39.** Where a scenario carries no assertion array today, re-targeting it
SHALL introduce one rather than leaving the claim in prose only. Several
`/explore` scenarios carry `expected_output` alone.

### The corpus-wide routing statement

**R40.** `references/pipeline-model.md` SHALL agree with the router. It names
`/explore` as the authority for the classification algorithm while itself
describing routes into chain interiors and a Skip transition that bypasses chain
steps on a classification made at entry.

## Acceptance Criteria

### The shared pattern

- [ ] `references/parent-skill-pattern.md` contains a statement that chain steps
      are mandatory and reduction is post-hoc, positioned at the head of the
      Gate Vocabulary section, and it names the grounds on which a child may
      legitimately not run.
- [ ] The statement is true of all three parents: it does not require a parent
      to define a post-hoc reduction mechanism.
- [ ] The ALWAYS declination clause names exactly three properties, and each is
      verifiable against `/charter`'s roadmap prompt as it exists today.
- [ ] An eval scenario exercises `/charter --auto` and asserts `/roadmap` is
      invoked with no `chain_skipped` declination entry, which is the behavioral
      test of R2's author-supplied property.
- [ ] The declination clause carries no dated-retirement block.
- [ ] `references/parent-skill-pattern.md` states that Adjust's reach into chain
      membership is a per-parent property, and both `skills/scope/` and
      `skills/charter/` state which they have.
- [ ] `references/parent-skill-state-schema.md` defines a closed
      `chain_skipped[].reason` vocabulary, and every reason string either parent
      writes today maps to exactly one member.
- [ ] No vocabulary member is without a writer in `skills/scope/` or
      `skills/charter/`.
- [ ] The schema cites `references/parent-skill-child-inspection.md` for the
      extension discipline rather than describing a new one.
- [ ] The triad contract names the never-planned category and states that a
      conditional feeder whose gate never opened appears in neither
      `planned_chain` nor `chain_skipped`, with `/comp` as the worked example.
- [ ] `grep -rn 'chain_skipped' skills/scope/ skills/charter/` shows one entry
      key, not two, and the graded eval strings use it.
- [ ] `/execute` appears in the pattern's parent roster, and the dispatch
      mechanism statement either covers koto-materialized dispatch or names
      `/execute` as a variance.
- [ ] `/comp` appears in no `planned_chain` example and no `chain_skipped`
      example under `skills/charter/`.
- [ ] `skills/charter/references/phases/phase-1-discovery.md` describes no
      Adjust behavior that drops a child.

### `/explore`

- [ ] `grep -rEn 'Routes to (/|shirabe:)(brief|prd|design|plan|vision|strategy|roadmap)\b' skills/explore/references/quality/crystallize-framework.md`
      returns nothing.
- [ ] The handler table in `skills/explore/references/phases/phase-5-produce.md`
      names no chain-internal child in its handoff column.
- [ ] The destination columns of the routing table and the complexity table in
      `skills/explore/SKILL.md` name no chain-internal child.
- [ ] `skills/explore/` names `/scope`, `/charter`, and `/execute`.
- [ ] `skills/explore/` writes no file under `docs/designs/`.
- [ ] `skills/explore/` names neither `/spike` nor `/competitive-analysis`.
- [ ] The competitive-analysis arm routes to `/comp` and writes no
      `docs/competitive/` file itself.
- [ ] `skills/explore/references/phases/phase-0-setup.md` assigns no `needs-*`
      label and contains no artifact-type triage.
- [ ] `references/label-reference.md` names no label whose only producer was the
      removed triage, and its skill-lookup rows all resolve.
- [ ] `skills/explore/` contains exactly one routing surface: no step outside
      the crystallize phase reaches a terminal route on its own.
- [ ] Step 0.2a still writes `## Visibility`, and Phase 1's hard stop still
      finds it.
- [ ] `skills/explore/` routes a filed issue to `/work-on`, and names
      `/execute` only in a branch conditioned on an existing PLAN path.

### The handoff

- [ ] The handoff artifact's path matches no Slot 5 or Slot 6 condition in
      `/scope` and no row-7 or row-8 condition in `/charter`, and is
      distinguishable from `/charter`'s own pre-populated handoff paths.
- [ ] `/scope`'s Slot 7 and `/charter`'s handoff clause each enter their
      parent's Phase 1 rather than routing into a child, and each is exercised
      by a new eval scenario.
- [ ] The handoff artifact's documented schema contains no field for artifact
      existence, frontmatter status, content hash, visibility, or upstream
      validation, and each parent's clause states that these are re-read.
- [ ] Placing `wip/prd_<topic>_scope.md` and running `/scope <topic>` no longer
      re-invokes `/prd` directly.
- [ ] Placing `wip/vision_<topic>_scope.md` and running `/charter <topic>` no
      longer jumps into `/vision`.
- [ ] The slug re-validation rule enumerates the new clause alongside Slot 5 and
      Slot 6.
- [ ] The handoff-detection clauses in `skills/prd/`, `skills/vision/`, and
      `skills/roadmap/` name the surviving producer, and none of them names
      `/explore` as the producer.
- [ ] Each arm's documented handover states what it passes, and the STRATEGY
      case has a stated destination or a stated retirement.
- [ ] The topic-branch interaction has either a stated resolution in
      `skills/explore/` and both parents, or a Known Limitation naming it.

### `/scope`'s prose

- [ ] `/scope`'s chain proposal still contains the three option tokens.
- [ ] No file under `skills/scope/` justifies the proposal on the ground that
      `/scope` cannot produce a smaller artifact set.
- [ ] Bail at Phase 1 reaches clean-cancel, the wip-state test excludes the
      parent's own state file, and an eval scenario exercises it.
- [ ] `skills/scope/references/phases/phase-1-discovery.md` contains no passage
      offering direct child invocation as the way to a smaller artifact set, and
      no passage contradicting another passage in the same file.
- [ ] `grep -rn 'chain_revised' skills/` returns nothing, or returns the field
      plus a state-schema entry naming its reader.
- [ ] The post-`/prd` gate's confirmation either has an options block and a
      recorded answer, or is gone.
- [ ] `skills/scope/references/state-schema.md` enumerates every
      `chain_skipped` reason the skill writes, and the count claim matches.

### The evals

- [ ] No `/scope` eval scenario asserts a durable-artifact floor, names
      `absorbable:`, or derives an absorb verdict from either type's
      required-section list.
- [ ] `skills/scope/evals/evals.json` contains at least four scenarios covering
      the consolidation judgment and the durable-artifact floor: the three
      currently named `consolidation-*` plus the rewritten floor scenario.
- [ ] No `/scope` or `/charter` scenario requires a contiguous
      `Proceed / Adjust / Bail` string; both assert the three tokens
      individually.
- [ ] No scenario in the `/explore`, `/roadmap`, or `/vision` suites asserts
      that `/explore` hands off to a chain-internal child.
- [ ] The `/decision` suite's crystallize scenario is byte-identical to its
      pre-change form.
- [ ] The two `explore-handoff-detection` scenarios are byte-identical to their
      pre-change form apart from re-grounding the producer attribution.
- [ ] `/scope`'s `chain-shape-is-constant` retains its first, second, and fourth
      expectations verbatim, and its third names the narrowed redirect.
- [ ] `/charter`'s four roadmap-declination scenarios are byte-identical to
      their pre-change form.
- [ ] The two `/explore` triage scenarios either grade a surviving surface or
      are removed with the surface they graded.
- [ ] Every re-targeted scenario carries an assertion array.

### Corpus-wide

- [ ] `references/pipeline-model.md` describes no route from `/explore` into a
      chain interior and no classification-driven Skip of chain steps.
- [ ] `shirabe validate --format json` over the documents this change adds or
      edits reports zero errors. The corpus-wide run is not the criterion: five
      pre-existing `R6` / `R10` / `R11` upstream-legality errors sit in unrelated
      briefs, so a corpus-wide gate would fail for reasons this change neither
      caused nor fixes. The error count over the whole corpus SHALL NOT increase.

## Decisions and Trade-offs

**The chain proposal keeps its three options.** The brief's outcome section said
what goes is the question mark, on the reading that the prompt is inert.
Research at this altitude showed both remaining options do work Proceed cannot
reach. Bail is the documented route into bail-handling before any child fires,
and removing it deletes the author's only chance to stop before `/brief` writes.
Adjust is the only in-prompt way to correct a framing-shift answer, and that
answer is the override that fires `/brief` against a settled BRIEF. What was
actually wrong is narrower: the pattern implies a uniform Adjust semantics it
never states, and `/scope`'s Adjust cannot change chain membership while
`/charter`'s can. R3 states the divergence rather than removing the option.
Considered and rejected: removing the options block entirely, which costs a real
capability and a graded contract; and a two-option confirmation, which forks the
eval surface per parent, the opposite of what the pattern exists to prevent.

**Bail is fixed rather than left as documentation.** Keeping the option while
knowing neither branch executes would be worse than removing it. R28 requires it
to work, and names clean-cancel as the outcome.

**"A shorter chain" means fewer artifacts, and absorption already handles it —
so the redirect is narrowed, not retired.** This closes the brief's first Open
Question. Absorption reduces the artifact set but not the conversation, so an
author who invokes `/design` directly is still doing something absorption cannot
do for them: having a shorter conversation. That is a legitimate reason to
invoke a child, and CLAUDE.md tells authors they may. What is not legitimate is
the corpus offering it as the way to reach a smaller artifact set, which is the
claim consolidation falsified. R29 splits the two. The consequence for the eval
suite is that `chain-shape-is-constant`'s contested expectation is rewritten to
the narrowed justification rather than deleted, preserving the guard against
reintroducing entry-altitude selection. Considered and rejected: retiring direct
invocation outright, which would contradict CLAUDE.md and strand four skills
that ship as standalone entry points.

**The abandonment exit stays reachable from the author's flow, at the chain
proposal.** This closes the brief's second Open Question, and R27 plus R28
together are the answer: the option stays and is made to work. The alternative —
relying on the resume ladder's own prompt as the only route — would mean an
author who wants out before the first child writes has to let it write first.

**The fourth arm is `/work-on`, not `/execute`, for work that starts as an
issue.** `/execute` has exactly two input modes and neither accepts an issue
number. Routing a filed issue to `/execute` would name a skill that cannot
receive it. `/execute` remains an arm, reachable when a PLAN already exists.

**Spike reports and rejection records keep `/explore` as their author.** Neither
is a chain artifact — no upstream field, no chain-driven lifecycle, nothing
downstream consumes them — so authoring them does not violate the constraint as
stated. Considered and rejected: building a `/spike` skill, which is a new
capability rather than a routing change, and deleting the arms, which would
strand the adversarial demand-validation research the `/explore` suite grades
and remove the only way to record a "don't build this" conclusion.

**The competitive-analysis arm becomes a route.** `/comp` already owns
`docs/competitive/COMP-<topic>.md` and drives a six-phase workflow with a jury
and a lifecycle transition. The inline handler writes a Draft at the same path
with none of that. This is duplication, and the more complete producer already
exists.

**The `chain_skipped` reason vocabulary is a closed enum with a
grow-by-PR-review extension path.** An open list with a stated prohibition
cannot be checked — a grep can assert membership in a set but not the absence of
a worth judgment from arbitrary prose. A hard-closed enum fails when a fourth
parent lands with a legitimate new ground. The corpus already uses
grow-by-PR-review for exactly this situation elsewhere, so the discipline is
reused rather than invented. There is a second reason independent of
enforceability: the field is durably public from feature-branch push time, and
free text is how a private artifact type could be named from a public repo's
state file.

**The two misroutes are fixed here rather than filed separately.** They are live
bugs today, but they are also directly in the path of R20: a handoff artifact
cannot be introduced safely while two ladder rows silently claim it. Fixing them
separately would mean landing the router on top of a known trap.

**Why the work reaches outside the brief's scope boundary in three places.** The
brief bounded the surfaces that state the wrong model; three requirement groups
reach past that, each for a stated reason. R8 edits `/charter`'s own state
schema, because R5's pattern-level edit names `/comp` as its worked example and
would otherwise land on a parent that contradicts itself about that example.
R19 through R26 build a parent-level handoff subsystem the brief did not
anticipate, because the brief assumed `/explore` could hand off through the
existing convention and research found that convention already misrouting in
both parents. R24 reaches into three child skills, because their handoff
detection names a producer this change removes, and leaving them would create
exactly the dangling cross-skill reference the PRD exists to eliminate.

**The STRATEGY upstream case is retired rather than relocated.** `/explore`'s
roadmap handler passes `--upstream <STRATEGY>` to `/roadmap` today, and
`/charter` accepts only a VISION. There is no receiver for a STRATEGY at the
strategic chain's entry, and there should not be: a chain that enters at
`/charter` produces its own STRATEGY, so handing one in would be handing a
parent an artifact one of its own children writes. An exploration that found an
existing STRATEGY names it in the handoff's prose, which is what the current
handler already does for the VISION case it cannot pass. Considered and
rejected: teaching `/charter` to accept a STRATEGY upstream, which would let a
chain skip `/strategy` — the exact shape this PRD removes elsewhere.

**The brief was corrected rather than superseded.** Three of its statements
predated the reversals recorded above: its tactical-chain journey said the
author is no longer presented with an option on an unchangeable list, its scope
boundary said all four terminal recording types stay with `/explore`, and its
exclusion of the research loop covered Setup, which R15 edits. The brief is
durable and a reader following the audit trail would have found it contradicting
its own downstream. It was edited in place under the format's allowance for a
material framing shift, with the change noted in its Status prose. Considered
and rejected: leaving the brief and recording the supersession only here, which
would put the stale reading in the document a reader reaches first.

**The declination clause gets no dated-retirement block.** The corpus's
retirement convention exists to translate a dead name in documents already on
disk. Nothing here is retired — the gate stays ALWAYS, `/charter`'s declination
is kept, and the same children fire on the same runs. A retirement note would
advertise a vocabulary change that did not happen. A one-sentence
no-behavior-change assurance carries what a reader actually needs.

## Known Limitations

**`/decision` produces nothing durable, and this change does not fix it.** The
decision arm routes to `/decision`, which writes only `wip/<prefix>_report.md`
and never touches `docs/decisions/`, while `/explore`'s handler calls that
report the Decision Record. Since `wip/` is swept before a PR merges, the arm
currently yields no durable artifact. That is a `/decision` defect rather than a
routing one, and fixing it means giving `/decision` a finalize step. The arm is
routed correctly here and the gap is left named.

**The eval suite still will not run on pull requests.** This change makes the
scenarios agree with the skills; it does not change when they execute. The same
drift can recur, and the next reader to notice will be whoever reads the Monday
run. A pull-request-time structural check is the obvious follow-on and is out of
scope here.

**`references/pipeline-model.md`'s three-diamond model predates both parents.**
Its second diamond names `/prd`, `/design`, and `/plan` with no `/brief` and no
`/scope`; its third names `/work-on` and `/release` with no `/execute`. R40
requires the routing statements to agree with the router, which is narrower than
reconciling the model's vocabulary with the current skill set. The wider
reconciliation is left for a later change.

**The handoff contract is specified but only exercised by the parents.** No
`/explore` run in this change produces a handoff that a parent then consumes end
to end in anger, so the first real use will be the test.

## Out of Scope

- **Adding a consolidation judgment to `/charter`.** The strategic chain has
  none, so #302 reached only the tactical chain. STRATEGY is the durable audit
  trail and ROADMAP is a working artifact retired by the plan cascade, which is
  a different disposal model from absorb-into-survivor. Deciding whether the
  strategic chain should reduce at all is separate work.
- **Retiring `/charter`'s roadmap declination.** It is kept, and R2 restates the
  model around it. It already does what #280 asked: the judgment is formed
  against a document that exists, the parent's reading never decides, and the
  author's answer is recorded.
- **`/execute`'s behavior.** It has no chain proposal, no confirmation prompt,
  and nothing an author can drop, and it omits the chain-tracking triad in a way
  the state schema sanctions. Only the pattern's roster changes.
- **`crates/shirabe-validate/src/formats.rs` and the absorption checks.** The
  code already encodes the current model.
- **Giving `/decision` a durable finalize step.** Named under Known Limitations.
- **A pull-request-time eval or skill-prose check.** Named under Known
  Limitations.
- **The child skills' internal phase workflows.** `/brief`, `/prd`, `/design`,
  and `/plan` keep their structure.
- **`/explore`'s research loop.** Phases 1 through 3 are the skill's value and
  are orthogonal to routing. They are also shared: `/charter` loads the
  discover and converge phase files as its own Phase 1 backbone, so they are not
  `/explore`'s to move or rename.
- **Re-opening what #302 settled.** The absorbability judgment, the citation
  preflight, the carry check, and the fold record stay as shipped.

## Amendment — 2026-08-16

`PRD-fold-record-removal.md` removes `docs/folds.md`. The original text above is left unedited; this section records what no longer holds.

**The Out-of-Scope entry naming the fold record as staying "as shipped" no longer
holds.** The absorbability judgment, the citation preflight, and the carry check
do stay as shipped; the fold record does not. Nothing else in this document's
scope is affected — the record was named there as a thing this work would not
touch, not as a thing it depended on.
