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
