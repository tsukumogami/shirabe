# Exploration Decisions: work-on-standalone-completeness

## Round 1

- **Items 1 and 2 of #361's "what /execute does that /work-on doesn't" list are
  eliminated from the problem statement**: `/work-on` never creates a draft PR
  (nothing to ready), and it already carries closing keywords and body
  conformance via `references/phases/phase-6-pr.md:35` and the shared
  `references/pr-body-conformance.md`. Verified directly, not via an agent.
  Rationale: the issue's term-count table counted only the koto templates and
  could not see the reference tree.

- **The problem is re-diagnosed as enforcement altitude rather than code
  location.** Rationale: most of the "missing" obligations exist as prose an
  agent may skip; in `/execute` the same obligations are koto states with
  evidence gates. That difference explains three workers skipping written-down
  steps, which a location-based diagnosis does not.

- **The per-issue-versus-per-plan cascade objection is set aside as already
  solved.** Rationale: `work-on.md:752-775` routes `pr_status: shared` straight
  to `done`, so `/execute`'s single-pr children never reach any post-CI state.
  Finishing logic added after `ci_monitor` is skipped for children with no new
  completion-tracking machinery.

- **The "folding is circular" objection is set aside.** Rationale:
  `execute.md:302-305` points koto's `materialize_children` at `work-on.md`
  directly. There is no slash-command recursion. The objection to folding has to
  be argued on other grounds (the documented prohibition on `/execute` taking an
  issue number, and reversing `DESIGN-execute-skill.md`).

- **A shared-library "shared component" variant is deprioritized.** Rationale:
  `DESIGN-execute-skill.md` already considered and rejected one for these two
  skills and this machinery, on legibility grounds; koto templates cannot compose,
  so it could only be a shared script or prose reference anyway.

- **A third direction is added to the two in #361**: raise enforcement altitude
  inside `/work-on` and add cascade states behind the existing `shared` fork.
  Rationale: it targets the re-diagnosed cause, avoids the rejected shared
  library, avoids re-deriving `children-complete`, and does not invert a
  documented prohibition.

- **`cannot_verify` is separated out as a distinct defect.** Rationale: MEASURED
  across this workspace -- only shirabe ships a verification map; both entry
  points run the same shared template state, so neither direction changes
  exposure to it.

- **`check-staleness.sh`'s absence and issue #87 are separated out as distinct
  pre-existing defects.** Rationale: neither is caused by the boundary; #87 is
  the same cascade gap filed four months earlier and still open.

- **#360 and #352 are proposed to split rather than travel together.** Rationale:
  #360 is cheap, boundary-independent, already solved by `/scope` in a
  transferable form, and is actively destroying context records now; #352 is a
  design-level change whose shape depends on which skill ends up owning
  `/work-on`'s three panels, so doing it before the boundary settles risks doing
  it twice.

## Round 2

- **Insight 4 is narrowed, not withdrawn.** The `pr_status: shared` fork
  discriminates `/execute`'s children only. multi-pr runs inside `/work-on` with
  each issue landing its own PR, so a last-issue discriminator is still required.
  Rationale: `skills/work-on/SKILL.md:137-141`, found by adversarial review of
  round 1. Direction C's "no last-issue machinery" claim is corrected in the
  routing options document rather than deleted.

- **The multi-pr discriminator is treated as a decided design with a lost
  implementation, not an open research question.** Rationale:
  `DECISION-cascade-trigger-mechanism-2026-06-06.md:176-178` already adopted
  execution_mode plus open-issue-count posture detection; the code moved into
  `/execute` during #199, which excludes multi-pr, with no amendment recording
  the removal.

- **The discriminator cost is assigned to all three directions, not to C
  alone.** Rationale: none of the three has a multi-pr cascade today, so all
  three build it. C was distinctive only in wrongly claiming to escape the cost.

- **The enforcement-altitude diagnosis is retained and a constraint added.**
  Rationale: koto's `init_child_core` seeds children from the compiled template
  and never loads `SKILL.md`, so a fix must live in `work-on.md` to reach both
  entry points -- but `work-on.md:1180` already cites the `Fixes #N` reference
  from its own prose, so the instruction reached both paths and was skipped
  anyway. The missing evidence gate is the defect; unreachability is a separate
  constraint on where any fix is written.

- **Three round-2 gaps are carried into scoping rather than explored further.**
  Rationale: issueless multi-pr's missing driver, the two `status: Current`
  designs where one superseded the other, and the discriminator's scope are all
  questions for whoever takes the work.

## Routing decision (author, 2026-09-13)

- **Direction chosen: add gated cascade states to `/work-on`.** The author
  selected this over folding `/work-on` into `/execute` and over relocating
  `/execute`'s finishing states into `/work-on`. This differs from the
  coordinator's leaning, which was relocation.

- **The deciding argument was the author's own, and it is not in the record
  anywhere.** The concern: `/execute` loops over many `/work-on` instances,
  potentially across teams of agents, and none of those agents should have
  finalization instructions in context when only the end of the `/execute` flow
  uses them. Rationale confirmed mechanically: `koto next` returns only the
  current state's `directive` and `details` (koto `src/cli/next.rs:50-64`), so
  context arrives one state at a time, and a `/work-on` child under `/execute`
  routes `pr_status: shared` straight to `done` and never reaches a post-CI
  state. It is never handed the prose rather than reading and ignoring it.

- **Corollary the author's argument produces: finalization must not live in
  `skills/work-on/SKILL.md`.** That file is loaded wholesale on direct
  invocation, so it is the one location where the context concern bites. Koto
  states are loaded on demand; `SKILL.md` is not.

- **The recorded rejection of a "shared library" does not bar a shared script.**
  `DESIGN-execute-skill.md:98-104` rejected "a neutral or plan-hosted template
  both skills reference" because it "muddies the single-issue legibility the
  narrowing is meant to buy" -- a legibility argument about templates, not a
  context-cost argument. A shared *script* is executed rather than read, costs no
  context, and was not what was rejected. Both skills calling one
  `run-cascade.sh` therefore duplicates the koto states without duplicating the
  cascade logic, which removes most of the cost originally charged against this
  direction.

- **multi-pr execution moves into `/execute`** (author, 2026-09-13, after the
  direction was chosen). Intent: `/execute` is how a PLAN gets run, one PR at a
  time; `/work-on` should not be what a person points at a PLAN's individual
  issues. Rationale and full cost in
  `wip/scope_work-on-standalone-completeness_handoff.md`. Consequence: the
  last-issue discriminator -- the hardest open question this exploration
  surfaced -- is replaced by a per-child "you are a child, do not cascade" flag
  the orchestrator sets on dispatch, which is race-free and cheap, because
  `/execute` already knows when its last child is done. It also gives the
  unowned issueless-multi-pr gap an owner. Cost: inverts multi-pr routing in at
  least six places across three skills, two of them trigger descriptions, plus
  the crystallize precondition.
