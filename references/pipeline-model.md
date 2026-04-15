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
| Strategic | /explore --strategic | 1-2-3 with branching | VISION or Roadmap -> per-feature pipeline |

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
  └── Roadmap (upstream: VISION)
        └── PRD (upstream: Roadmap, per feature)
              └── Design Doc (upstream: PRD)
                    └── Plan (upstream: Design Doc)
                          └── GitHub Issues (upstream: Plan)
```

Each artifact's `upstream` field points to its parent. The chain enables:
- Finding all downstream work from a VISION
- Tracing an implementation issue back to its strategic justification
- Completion cascades (when issues close, propagate status upstream)

For cross-repo traceability, see `references/cross-repo-references.md`.
For the upstream/downstream field convention, see
`DESIGN-artifact-traceability.md`.

## Skill routing table

Given a complexity level and a starting situation, this table shows which
skills apply and in what order.

| Situation | Skill sequence |
|-----------|---------------|
| Trivial fix (typo, config) | /work-on directly |
| Simple task with issue | /work-on -> /release |
| Known approach, design decisions exist | /design -> /plan -> /work-on |
| Shape unclear, multiple unknowns | /explore -> (crystallize) -> /prd or /design -> /plan -> /work-on |
| New project, thesis needed | /explore --strategic -> /vision -> /roadmap -> per-feature pipeline |
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
