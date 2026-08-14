# Pipeline Model Reference

The shirabe workflow is organized as a three-diamond pipeline. Each diamond
is a diverge-converge pair. Work enters at a complexity-dependent point and
flows through the diamonds it needs.

## Three-diamond model

```
Diamond 1: EXPLORE / CRYSTALLIZE
  /explore (diverge) -> crystallize (converge) -> artifact type

Diamond 2: SPECIFY / SCOPE
  /prd, /design (diverge) -> /plan (converge) -> issues

Diamond 3: IMPLEMENT / SHIP
  /work-on (diverge) -> /release (converge) -> shipped
```

Diamond 1 discovers what to build and what artifact to produce. Diamond 2
specifies requirements, designs the approach, and decomposes into issues.
Diamond 3 implements and ships.

Not all work needs all three diamonds. Trivial and simple work enters at
Diamond 3. Medium work enters at Diamond 2. Complex and strategic work
starts at Diamond 1.

## Complexity levels

Five levels determine where work enters the pipeline and which skills are
involved.

| Level | Entry point | Diamonds | Typical path |
|-------|------------|----------|--------------|
| Trivial | /work-on (no issue) | 3 only | Direct fix, no artifact |
| Simple | /work-on with issue | 3 only | Issue -> implement -> ship |
| Medium | /design | 2-3 | Design -> plan -> implement |
| Complex | /explore | 1-2-3 | Explore -> crystallize -> specify -> implement |
| Strategic | /explore --strategic | 1-2-3 with branching | VISION -> STRATEGY -> Roadmap -> per-feature pipeline |

Detection runs top-down (Strategic first, Trivial last). The full detection
algorithm and tiebreaker rules live in `/explore SKILL.md` under "Detection
Algorithm." This reference describes the levels; /explore owns the
classification logic.

### Key discriminators between levels

| Boundary | Question |
|----------|----------|
| Strategic vs Complex | Multi-feature initiative or single capability? |
| Complex vs Medium | Can the user state what to build? |
| Medium vs Simple | Are there design decisions where reasonable people disagree? |
| Simple vs Trivial | Does a GitHub issue exist or is one warranted? |

## Named transitions

Five transitions connect diamonds and handle non-linear flow.

| Transition | From | To | When |
|------------|------|-----|------|
| **Advance** | Any diamond | Next diamond | Normal progression. Crystallize produces an artifact type; /plan produces issues; /release ships. |
| **Recycle** | Any diamond | Same diamond | The converge step sends work back to diverge. Crystallize can't pick a type; review finds gaps in the plan. |
| **Skip** | Diamond 1 or 2 | Later diamond | Complexity routing bypasses diamonds. Simple work skips Diamonds 1-2. Medium skips Diamond 1. |
| **Hold** | Any point | Paused | Work is paused. The artifact stays at its current status. No state transition occurs. |
| **Kill** | Any point | Abandoned | Work is abandoned. Artifacts may move to a Dropped or Superseded state (convention TBD, see F11). |

Advance is the default. Recycle happens when a diamond's converge step
determines the work isn't ready to move forward. Skip is driven by
complexity classification at entry. Hold and Kill are human decisions.

## Artifact lifecycle states

Each artifact type has its own lifecycle, but they follow a common pattern:
draft, accepted/active, in-progress, completed.

| Artifact | States | Terminal |
|----------|--------|----------|
| VISION | Draft -> Accepted -> Active -> Sunset | Sunset |
| Strategy | Draft -> Accepted -> Active -> Sunset | Sunset |
| Roadmap | Draft -> Active -> Done | Done |
| PRD | Draft -> Accepted -> In Progress -> Done | Done |
| Design Doc | Proposed -> Accepted -> Planned -> Current (or Superseded) | Current |
| Plan | Draft -> Active -> Done | Done |
| Spike Report | Draft -> Complete | Complete |
| Decision Record | Draft -> Accepted | Accepted |

### State meaning

- **Draft**: work in progress, not yet reviewed
- **Accepted/Active**: approved and ready for downstream consumption
- **Planned**: downstream /plan has created issues (design docs only)
- **Current**: implementation is complete, design is the active reference
- **Done/Complete**: all planned work finished
- **Superseded**: replaced by a newer artifact
- **Sunset**: VISION is no longer actively driving work but remains as context

### Validation rules

- Draft artifacts must not merge to main (CI enforces this)
- Each artifact type's transition script validates preconditions before
  allowing status changes
- Status must match in both YAML frontmatter and body Status section

## Traceability chain

Artifacts link to each other through `upstream` frontmatter fields, forming
a chain from strategic intent to implementation.

```
VISION
  └── Strategy (upstream: VISION)
        └── Roadmap (upstream: Strategy)
              └── Brief (no upstream -- see below)
                    └── PRD (upstream: Brief)
                          └── Design Doc (upstream: PRD)
                                └── Plan (upstream: Design Doc, and the
                                          Roadmap when there is one)
                                      └── GitHub Issues (upstream: Plan)
```

The diagram above is the full chain, not a mandatory one. Each artifact's
`upstream` field points to the nearest artifact actually produced above it
that it is *allowed* to name, and the field is omitted when there is none.

## What makes a link legal

Two properties, both declared per artifact type in the validator's format
table and both enforced by `shirabe validate`.

**Direction.** The target's type is one the naming type may point at. The
strategic chain (VISION -> Strategy -> Roadmap) is strict: a STRATEGY names a
VISION and a Roadmap names a STRATEGY, and nothing skips an altitude, because
skipping one would leave the reasoning at the skipped altitude unreachable
from the path a reader walks. The tactical chain is not strict, because its
steps are not all mandatory: a DESIGN written with no BRIEF above it names the
PRD, and a PLAN names whatever tactical artifact preceded it. What no artifact
does is point downward or sideways -- a BRIEF never names a PRD, which is
written from the brief's framing.

**Lifetime.** A link runs from the shorter-lived document to the longer-lived
one. Roadmaps and Plans are working artifacts: they are deleted when their work
completes. Every other type is durable. So a durable document never names a
working one -- the link would be correct on the day it is written and dangling
on the day the cascade runs. A working document may name anything, because it
does not outlive what it points at.

The two properties are enforced as `R10` (direction) and `R11` (lifetime). An
entry violating both reports the lifetime finding, which is the diagnosis that
survives being acted on.

## Where the chains meet

The Roadmap is where the strategic chain hands off to the tactical one, and the
lifetime rule decides which document records the crossing. A Roadmap is a
working artifact, so no durable tactical document may name it: **the crossing is
recorded on the PLAN alone.** The PLAN is deleted by the same cascade that
deletes the Roadmap, and it goes first, so that link cannot dangle.

A BRIEF therefore carries no `upstream:` at all. It reads the Roadmap that
sequences its feature -- the framing, the sequencing rationale, the neighbouring
features -- and absorbs that context into its own prose, which is what its
Problem Statement was always required to do. Its legal-parent set is empty,
which states as a checkable fact that a brief heads its own tactical lineage.

This is the same shape as the older rule for an upstream a document cannot
reach: a public document whose upstream is private omits the field, absorbs the
context, and stands as the head of its own lineage. One rule, two triggers --
an upstream that cannot be *reached* and an upstream that will not *last*. Only
the second can be checked by tooling, because a cross-repo value resolves to
nothing.

The chain enables:
- Finding all downstream work from a VISION
- Tracing an implementation issue back to its strategic justification
- Completion cascades (when issues close, propagate status upstream)

Plan-level execution (both single-pr and coordinated modes) and the completion
cascade are owned by `/execute`. `/work-on` is the single-issue engine plus an
execution_mode dispatcher: it runs multi-pr in place and hands single-pr and
coordinated plans to `/execute`. When a plan runs through `/execute PLAN-*.md`
and CI passes on the orchestrator's ready PR, `/execute` runs the completion
cascade as its final step before `done`. A single script (`run-cascade.sh --push`) walks the
`upstream` chain from the PLAN doc and applies the right transition at each
node: DESIGN moves to Current (with the Implementation Issues section
compressed out), PRD moves to Done, the ROADMAP feature entry is updated,
and the ROADMAP itself moves to Done once all its features complete. The
transitions are committed and pushed as `chore(cascade): post-implementation
artifact transitions` onto the open PR, so the PR merges with the upstream
artifacts already advanced — there is no post-merge trigger. Cascade
failures are best-effort: they don't block the PR, and the script emits a
JSON result recording which steps ran. See
`skills/execute/scripts/run-cascade.sh` for the implementation and
`docs/designs/current/DESIGN-completion-cascade.md` for the design.

For cross-repo traceability and the visibility-direction rules, see
[`cross-repo-references.md`](cross-repo-references.md). For the `wip/`
hygiene rule that prevents non-durable references in committed artifacts,
see [`wip-hygiene.md`](wip-hygiene.md).
For the upstream/downstream field convention, see
`DESIGN-artifact-traceability.md`.

## Skill routing table

Given a complexity level and a starting situation, this table shows which
skills apply and in what order.

| Situation | Skill sequence |
|-----------|---------------|
| Trivial fix (typo, config) | /work-on directly |
| Simple task with issue | /work-on -> /release |
| Full plan ready to ship | /execute PLAN-*.md (plan orchestrator) -> /release |
| Known approach, design decisions exist | /design -> /plan -> /work-on |
| Shape unclear, multiple unknowns | /explore -> (crystallize) -> /prd or /design -> /plan -> /work-on |
| New project, thesis needed | /explore --strategic -> /vision -> /strategy -> /roadmap -> per-feature pipeline |
| Whole strategic chain in one sitting | /charter -> VISION -> STRATEGY -> ROADMAP |
| Multi-feature initiative | /roadmap -> /plan (enriches roadmap) -> per-feature /prd, /design, /plan |
| Feasibility unknown | /explore -> (crystallize) -> spike report |
| Single contested choice | /explore -> (crystallize) -> /decision |

The crystallize step in /explore determines which artifact type to produce.
The detection algorithm in /explore determines which complexity level applies.
Both are documented in `/explore SKILL.md`.

### Roadmap branching

Strategic work follows a branching pattern. A Roadmap decomposes into
features. Each feature gets a planning issue with a `needs-*` label
(needs-prd, needs-design, needs-spike, needs-decision). The feature then
enters its own pipeline at the appropriate diamond based on what it needs.

```
Roadmap
  ├── Feature A (needs-prd) -> /prd -> /design -> /plan -> /work-on
  ├── Feature B (needs-design) -> /design -> /plan -> /work-on
  ├── Feature C (needs-spike) -> spike -> then reassess
  └── Feature D (needs-decision) -> /decision -> then reassess
```

Each feature's pipeline runs independently. The Roadmap tracks overall
progress; /plan enriches the Roadmap with an Implementation Issues table
and Dependency Graph.
