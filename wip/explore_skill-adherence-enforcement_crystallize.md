# Crystallize Decision: skill-adherence-enforcement

## Chosen Type

Design Doc

## Rationale

The exploration answered "what should we build" definitively and left "how do we
build it" open across several interlocking technical choices. That is the Design
Doc signal exactly.

What is settled: the failure is not discoverability (bare `/execute` resolves);
invocation is the wrong unit of measurement (incident 2 ran the skill's scripts
and produced a valid payload); the discriminating state exists only on the
machine (outcome gating certified both incidents); the machine is the party that
failed (client-side self-grading); and the resolution is to detect locally and
publish off-machine. A staged portfolio was chosen over any single mechanism, and
four candidate mechanisms were evaluated and rejected or reduced with recorded
reasons.

What remains open is architectural and interlocking, which is why this is not a
Decision Record:

- The exact predicate shape and its coupling to koto's internal event schema
  (`scheduler_ran`, `spawned_count`), plus the coordinated-plan carve-out that
  must read from the coordination PR instead.
- The off-machine publishing mechanism -- trailer versus run-report emit -- and
  the R9 amendment widening `/execute`'s closed write-target set.
- Where the ordering statement lives so it binds at every tick rather than only
  at entry, and how it is worded to narrow interpretation without claiming
  precedence.
- The `koto init` sequencing change, which the validator flagged as "a real
  state-machine change, not a reorder."
- How the detector composes with the existing niwa-injected hook set without
  double-registering, and whether it ships from skill frontmatter or the niwa
  path.

These are multiple interrelated technical decisions with real trade-offs, spanning
three repositories. That is a design doc, not an ADR.

## Signal Evidence

### Signals Present

- **What to build is clear, but how to build it is not**: the portfolio is
  chosen; the predicate shape, publishing mechanism, and sequencing are not.
- **Technical decisions need to be made between approaches**: trailer vs
  run-report emit; skill-frontmatter hooks vs niwa injection; which predicate
  strengthening (`currentState` advance vs `scheduler_ran` vs child dirs).
- **Architecture and integration questions remain**: the mechanism spans shirabe
  (skill, hooks, binary), koto (publishing, `koto init` sequencing), and
  potentially niwa (distribution), with an established division of labor to
  respect.
- **Exploration surfaced multiple viable implementation paths**: six alternatives
  evaluated adversarially, four surviving as components.
- **Architectural decisions were made during exploration that should be on
  record**: rejecting outcome gating as primary is falsification-backed and would
  otherwise be re-proposed, since it is shirabe's own shipped doctrine. Likewise
  the interpretation-narrowing constraint on the ordering statement -- getting
  that wrong ships something worse than the bug.
- **The core question is "how should we build this?"**: yes, now that the what is
  settled.

### Anti-Signals Checked

- *What to build is still unclear* -- **not present**. The decision report commits
  to a specific staged portfolio with named components.
- *No meaningful technical risk or trade-offs* -- **not present**. Predicate
  gaming, false positives on the coordinated path, deadlock without an escape
  hatch, and the write-target amendment are all live risks.
- *Problem is operational, not architectural* -- **not present**. It requires
  changes to skill structure, hook registration, koto state publishing, and a
  security-surface amendment.

## Alternatives Considered

- **Decision Record**: fits the shape of what was produced (a contested choice
  with alternatives and rationale) and the decision report is already written in
  ADR-compatible block format. Ranked lower on the framework's explicit
  anti-signal: "Multiple interrelated decisions need a design doc." There are at
  least five open technical decisions downstream of the one that was settled.
  The decision block should be *embedded* in the design doc's Considered Options
  rather than filed separately.

- **Plan**: ranked lower on the anti-signal "open architectural decisions need to
  be made first." The components are named but not specified to the level where
  atomic issues could be written -- the predicate shape alone is unresolved.
  A plan follows the design.

- **PRD**: ranked lower. Requirements did not emerge as the gap; the user stated
  the problem precisely and the exploration confirmed it. The open question is
  technical approach, which is the documented PRD-vs-Design tiebreaker (given,
  not identified -> Design Doc).

- **No artifact**: strongly ranked down by two anti-signals -- architectural
  decisions *were* made during exploration, and multiple people/repos are
  involved. `wip/` is deleted before merge, so the falsification datum about
  outcome gating and the interpretation-narrowing constraint would be lost
  precisely where they are most likely to be re-litigated.

- **Spike Report**: the feasibility questions that existed (is the predicate
  computable? do skill hooks persist?) were answered inside this exploration
  rather than remaining open. Not a feasibility artifact.

## Scope Note

The design spans shirabe, koto, and possibly niwa. Per the workspace's
coarsest-legal PR-grouping policy the implementation is one PR per repository,
but the design doc itself is single and lives in shirabe, which owns the skills
and the binary that implements the check.
