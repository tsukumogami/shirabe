---
schema: prd/v1
status: Draft
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
upstream: docs/briefs/BRIEF-scope-chain-mandatory-steps.md
motivating_context: |
  Research at requirements altitude found two live misrouting bugs the router
  would otherwise inherit, and reversed a working assumption: the chain
  proposal's option triad does real work in both parents and should be
  specified rather than removed.
---

# PRD: Chain Steps Are Mandatory

## Status

Draft

Requirements written from `docs/briefs/BRIEF-scope-chain-mandatory-steps.md`.
Both of the brief's Open Questions are closed under Decisions and Trade-offs,
along with three decisions that reverse or narrow what the brief assumed.

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
The restatement SHALL name three properties a conforming declination has —
author-supplied, so no predicate the parent evaluates can produce the skip and a
non-interactive run invokes the child; formed against a document already on
disk; and recorded, with the child remaining in `planned_chain` and the skip in
`chain_skipped`. It SHALL state that the prompt may not ask whether the child's
artifact is worth producing, and SHALL carry a one-sentence note that no
behavior changed.

**R3.** The pattern's prompt literal-form contract SHALL state what the chain
proposal's Adjust option is guaranteed to reach and what is per-parent. Adjust
SHALL re-enter the parent's discovery and re-emit the proposal; whether that
re-entry can change chain membership SHALL be declared a per-parent property,
with each parent stating which it has in its own chain-proposal section. The
contract SHALL state that no parent may use Adjust to reach a child whose
artifact the parent judged not worth producing.

**R4.** `chain_skipped[].reason` SHALL be bounded to a closed vocabulary defined
in `references/parent-skill-state-schema.md`, with an extension path matching
the corpus's existing grow-by-PR-review convention. The vocabulary SHALL admit
every ground the two parents record today and SHALL NOT be able to express a
worth judgment. Free text SHALL move to an optional sibling field that is never
the ground.

**R5.** The `planned_chain` / `chain_ran` / `chain_skipped` triad contract SHALL
state that whether `planned_chain` is the same on every run is a per-parent
property, with `/scope`'s constant and `/charter`'s varying by its Phase 1
gates, and that both shapes satisfy the same rule. It SHALL name the
never-planned category as a first-class member: a conditional feeder whose gate
never opened appears in neither list, and the state file names no reason for it.

**R6.** The `chain_skipped` entry key SHALL be the same in both parents.
`/scope` writes `name:` and `/charter` writes `child:`; the pattern specifies
neither. One SHALL be chosen and both parents plus their graded eval strings
brought to it.

**R7.** The pattern's parent roster SHALL name `/execute`. Every statement
enumerating "both v1 parents" or a fixed child count SHALL be corrected or, where
the statement is genuinely about the two authoring parents, SHALL say so
explicitly.

**R8.** `/charter`'s internal contradiction about `/comp` SHALL be resolved in
favor of the Phase 2 rule, which carries the visibility argument: `/comp` is
absent from `planned_chain` and has no `chain_skipped` entry. The state-schema
sites that list it as a member SHALL be corrected.

**R9.** `/charter`'s Phase 1 Adjust option SHALL NOT permit an author to opt a
child out without a recorded ground. Its current wording permits dropping a
child that would otherwise fire, with no `chain_skipped` entry described, which
R2's three-property rule makes non-conforming.

### `/explore` routes to entry points

**R10.** `/explore`'s crystallize step SHALL score chain entry points rather
than artifact types. The entry points are: file an issue, `/charter`, `/scope`,
and an existing PLAN. The scoring procedure, the demotion rule, the tiebreakers
that discriminate between entry points, and the insufficient-signal fallback
SHALL survive; the ten per-artifact-type signal tables SHALL be replaced by
per-entry-point ones.

**R11.** `/explore` SHALL NOT author a durable chain artifact. The DESIGN
skeleton its design handler writes SHALL be removed. Writing a `wip/` handoff
artifact is not authoring a durable artifact and SHALL survive.

**R12.** `/explore`'s routing tables, complexity table, and detection algorithm
SHALL name entry points rather than chain-internal children. Where a table row's
distinction only mattered while PRD and DESIGN were separately choosable, the
row SHALL be removed rather than re-pointed.

**R13.** The fourth arm SHALL be named for what it can actually receive.
`/execute` accepts only a PLAN path; it does not accept an issue number. The
arm SHALL route to `/execute` only when a PLAN already exists, and the
file-an-issue arm's stated next step SHALL be `/work-on`, which is the skill
that accepts an issue number.

**R14.** The four artifact types no chain owns SHALL remain reachable.
Competitive analysis SHALL route to `/comp`, which already owns the same path
and produces a more complete document, and the duplicate inline handler SHALL be
deleted. A decision SHALL route to `/decision`. A spike report and a rejection
record have no owning skill, so `/explore` SHALL keep authoring them; neither is
a chain artifact.

**R15.** `/explore`'s Phase 0 artifact-type triage SHALL be removed. It commits
to one of four `needs-*` labels before Phase 1 runs, and Phase 4 overrides it
anyway. Phase 0's investigation-versus-breakdown-versus-ready triage SHALL be
reconciled with the router rather than left as a second routing surface.

**R16.** Every destination `/explore` names SHALL resolve to a skill that exists
in this repository, or SHALL be removed. `/spike` and `/competitive-analysis`
resolve to nothing today.

### The handoff, and the two collisions it would inherit

**R17.** The `/explore` handoff artifact SHALL live at a path that collides with
no existing resume-ladder match condition in either parent. The current
`wip/<child>_<topic>_scope.md` convention collides with `/scope`'s Slot 6.3 glob
and `/charter`'s row 8 exact match.

**R18.** Both parents SHALL detect an `/explore` handoff and consume it. The
clause SHALL live in each parent's reserved Slot 7, which both name and leave
empty today. Its action SHALL be to enter the parent's Phase 1 with the
handoff's content pre-loaded as discovery input, never to skip Phase 1 and never
to route into a child.

**R19.** The handoff SHALL carry conversation, never filesystem state. It may
pre-supply the framing-shift or thesis-shift answer with its evidence, the
problem statement and scope boundary, the accumulated decisions, and a shape
estimate the parent re-derives later. It SHALL NOT pre-supply artifact
existence, frontmatter status, content hashes, visibility, or upstream
validation, all of which the parent re-reads on every run.

**R20.** The two existing misroutes SHALL be fixed as part of this change.
`/scope`'s Slot 6.3 glob and `/charter`'s row 8 match condition SHALL be
narrowed so neither can match a handoff artifact.

**R21.** Slug re-validation SHALL cover Slot 7. The rule that slugs recovered
from on-disk paths are re-validated before interpolation currently enumerates
Slot 5 and Slot 6 only.

### `/scope`'s stale prose

**R22.** The chain proposal SHALL keep its three options. Bail is the author's
only surface for stopping before the first child writes, and Adjust is the only
in-prompt route to correcting a framing-shift answer, which is the override that
fires `/brief` against a settled BRIEF. The stale justification attached to the
proposal — that it offers no shorter chain "because `/scope` has no way to
produce one" — SHALL be corrected, since `/scope` does now produce a smaller
artifact set.

**R23.** Bail at Phase 1 SHALL execute. Both branches are currently unreachable:
clean-cancel because Phase 0 always wrote the state file before Phase 1 runs,
and abandonment-forced because no child has produced an intermediate to
force-materialize and the hard-finalization check refuses an empty artifact
list.

**R24.** The direct-invocation redirect SHALL be narrowed rather than retired. A
child invoked directly remains supported. What SHALL be removed is the
justification that it is how an author reaches a smaller artifact set, since
consolidation now decides that after the fact. The two rules SHALL be stated as
distinct: `/explore` routes to parents, and an author may still invoke a child
directly for their own reasons.

**R25.** `chain_revised:` SHALL be either specified or removed. It is written by
a phase file, absent from `/scope`'s own state schema, read by nothing, and
named for the produce-or-skip behavior the same file retires.

**R26.** The post-`/prd` re-evaluation gate's second confirmation prompt SHALL
be specified or removed. It currently has no options block, no branch list, and
no state record of the answer.

**R27.** The claim that Phase 2 writes "one further reason" into `chain_skipped`
SHALL be corrected. Two distinct reason strings are written, by the two
rejection templates, and neither is enumerated in the state schema.

### The evals

**R28.** The three `/scope` scenarios grading the retired absorbability model
SHALL be rewritten so no scenario asserts a durable-artifact floor, records the
retired `absorbable:` field, or derives absorbability from either type's
required-section list. The consolidation family's scenario count SHALL NOT
decrease.

**R29.** The `/scope` scenarios pinning the chain-proposal options block SHALL
be updated to match whatever the block becomes, and the byte-for-byte pin SHALL
be decoupled from the claim it exists to make. `/scope` pins the literal
byte-for-byte while `/charter` asserts the same triad per-token and explicitly
tolerates a re-labelled option; the two SHALL converge on the per-token form.

**R30.** Every scenario asserting that `/explore` hands off to a chain-internal
child SHALL be re-targeted at the parent that owns that chain. This spans the
`/explore`, `/roadmap`, `/vision`, and `/decision` suites. Scenarios asserting
the receiving side — that a child detects an existing handoff artifact and skips
its own scoping phase — SHALL survive, because `/charter` writes the same file.

**R31.** The scenarios that guard the model SHALL survive. `/scope`'s
`chain-shape-is-constant` SHALL keep the three expectations that assert the whole
chain runs, that skipping a child would be a judgment about an unwritten
document, and that a redundant artifact is removed by consolidation after both
exist; its fourth expectation SHALL be updated to match R24's narrowed redirect
rather than deleted. `/charter`'s four roadmap-declination scenarios SHALL
survive unchanged.

**R32.** Where a scenario carries no assertion array today, re-targeting it SHALL
introduce one rather than leaving the claim in prose only. Several `/explore`
scenarios carry `expected_output` alone.

### The corpus-wide routing statement

**R33.** `references/pipeline-model.md` SHALL agree with the router. It names
`/explore` as the authority for the classification algorithm while itself
describing routes into chain interiors and a Skip transition that bypasses
chain steps on a classification made at entry.

## Acceptance Criteria

- [ ] `references/parent-skill-pattern.md` contains a statement that chain steps
      are mandatory and reduction is post-hoc, and a reader can find it without
      opening a skill directory.
- [ ] Searching `references/parent-skill-pattern.md` and
      `references/parent-skill-state-schema.md` for the model's vocabulary
      returns the new statement rather than nothing.
- [ ] The ALWAYS declination clause names three properties, and each is
      verifiable against `/charter`'s roadmap prompt as it exists.
- [ ] The pattern states that Adjust's reach into chain membership is
      per-parent, and both `/scope` and `/charter` state which they have.
- [ ] `chain_skipped[].reason` has a closed vocabulary, every reason string
      either parent writes today maps to a member, and no member can express a
      worth judgment.
- [ ] Both parents write the same `chain_skipped` entry key, and the graded eval
      strings match it.
- [ ] `/execute` appears in the pattern's parent roster.
- [ ] `/charter` names `/comp` in exactly one way across its state schema and
      its Phase 2 orchestration.
- [ ] `/charter`'s Phase 1 Adjust cannot drop a child without a recorded ground.
- [ ] `/explore` names no chain-internal child as a routing destination.
      `grep -E '/(brief|prd|design|plan|vision|strategy|roadmap)\b' skills/explore/`
      returns only references that are not routing destinations.
- [ ] `/explore` names `/scope`, `/charter`, and `/execute`.
- [ ] `/explore` writes no file under `docs/designs/`.
- [ ] Every skill destination named in `skills/explore/` resolves to a directory
      under `skills/`.
- [ ] The competitive-analysis handler routes to `/comp` and writes no
      `docs/competitive/` file itself.
- [ ] The handoff artifact's path matches no Slot 5 or Slot 6 condition in
      `/scope` and no row-8 condition in `/charter`.
- [ ] `/scope` Slot 7 and `/charter`'s handoff clause each enter their parent's
      Phase 1 rather than routing into a child, and each is exercised by a new
      eval scenario.
- [ ] Placing `wip/prd_<topic>_scope.md` and running `/scope <topic>` no longer
      re-invokes `/prd` directly.
- [ ] Placing `wip/vision_<topic>_scope.md` and running `/charter <topic>` no
      longer jumps into `/vision`.
- [ ] The slug re-validation rule enumerates Slot 7.
- [ ] `/scope`'s chain proposal still contains the three option tokens, and its
      justification no longer claims `/scope` cannot produce a smaller artifact
      set.
- [ ] Bail at Phase 1 reaches a defined terminal state, and an eval scenario
      exercises it.
- [ ] `skills/scope/references/phases/phase-1-discovery.md` contains no passage
      offering direct child invocation as the way to a smaller artifact set, and
      no passage contradicting another passage in the same file.
- [ ] `chain_revised:` is either absent from every file or defined in
      `/scope`'s state schema with a stated reader.
- [ ] The post-`/prd` gate's confirmation either has an options block and a
      recorded answer, or is gone.
- [ ] `/scope`'s state schema enumerates every `chain_skipped` reason the skill
      writes.
- [ ] No `/scope` eval scenario asserts a durable-artifact floor, names
      `absorbable:`, or reasons from either type's required-section list.
- [ ] The consolidation scenario count in `skills/scope/evals/evals.json` is not
      lower than before this change.
- [ ] `/scope` and `/charter` assert the chain-proposal triad the same way.
- [ ] No scenario in the `/explore`, `/roadmap`, `/vision`, or `/decision`
      suites asserts that `/explore` hands off to a chain-internal child.
- [ ] The two `explore-handoff-detection` scenarios still pass unchanged.
- [ ] `/scope`'s `chain-shape-is-constant` retains its first, second, and fourth
      expectations verbatim.
- [ ] `/charter`'s four roadmap-declination scenarios are byte-identical to
      their pre-change form.
- [ ] Every re-targeted scenario carries an assertion array.
- [ ] `references/pipeline-model.md` describes no route from `/explore` into a
      chain interior and no classification-driven Skip of chain steps.
- [ ] `shirabe validate` reports zero errors across `docs/` after the change.

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
knowing neither branch executes would be worse than removing it. R23 requires it
to work.

**"A shorter chain" means fewer artifacts, and absorption already handles it —
so the redirect is narrowed, not retired.** This closes the brief's first Open
Question. Absorption reduces the artifact set but not the conversation, so an
author who invokes `/design` directly is still doing something absorption cannot
do for them: having a shorter conversation. That is a legitimate reason to
invoke a child, and CLAUDE.md tells authors they may. What is not legitimate is
the corpus offering it as the way to reach a smaller artifact set, which is the
claim consolidation falsified. R24 splits the two. The consequence for the eval
suite is that `chain-shape-is-constant`'s contested expectation is rewritten to
the narrowed justification rather than deleted, preserving the guard against
reintroducing entry-altitude selection. Considered and rejected: retiring direct
invocation outright, which would contradict CLAUDE.md and strand four skills
that ship as standalone entry points.

**The abandonment exit stays reachable from the author's flow, at the chain
proposal.** This closes the brief's second Open Question, and R22 plus R23
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
bugs today, but they are also directly in the path of R18: a handoff artifact
cannot be introduced safely while two ladder rows silently claim it. Fixing them
separately would mean landing the router on top of a known trap.

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
`/scope`; its third names `/work-on` and `/release` with no `/execute`. R33
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
