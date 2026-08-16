# Pipeline Model Reference

The shirabe workflow is organized as a three-diamond pipeline. Each diamond
is a diverge-converge pair. Work enters at one point, chosen before any of the
pipeline runs, and flows forward from there.

## Three-diamond model

```
Diamond 1: EXPLORE / CRYSTALLIZE
  /explore (diverge) -> crystallize (converge) -> a terminal outcome, or the
                                                  chain that receives the work

Diamond 2: SPECIFY / SCOPE
  /prd, /design (diverge) -> /plan (converge) -> issues

Diamond 3: IMPLEMENT / SHIP
  /work-on (diverge) -> /release (converge) -> shipped
```

Diamond 1 discovers what to build and where the work goes next. Diamond 2
specifies requirements, designs the approach, and decomposes into issues.
Diamond 3 implements and ships.

Diamonds 2 and 3 name their steps in a vocabulary that predates the parent
skills. `/prd`, `/design`, and `/plan` are hops inside `/scope`, and `/work-on`
runs under `/execute` when a PLAN drives it. None of those names is an entry
point an author picks. Reconciling the model's vocabulary with the current
skill set is separate work; what this file says about routing is reconciled
here.

Not all work passes through all three diamonds. Trivial and simple work goes
straight to Diamond 3 through `/work-on`, and a finished PLAN enters there
through `/execute`. Everything else enters at the top of a chain: `/explore`
when the shape is unclear, `/scope` or `/charter` when it isn't.

## Complexity levels

Four levels suggest which command an author runs first.

| Level | Entry point | Diamonds | Typical path |
|-------|------------|----------|--------------|
| Trivial | /work-on (no issue) | 3 only | Direct fix, no artifact |
| Simple | /work-on with issue | 3 only | Issue -> implement -> ship |
| Complex | /explore | 1, then whatever crystallize names | Explore -> crystallize -> the chain it names |
| Strategic | /charter | the strategic chain, then 2-3 per feature | VISION -> STRATEGY -> Roadmap -> per-feature pipeline |

The Medium level is gone. It recommended a design and then a plan, and that
recommendation only meant something while those two were separately choosable
entry points. A request that used to land on Medium reads as Complex now.

Detection runs top-down (Strategic first, Trivial last). The algorithm lives in
`skills/explore/SKILL.md` under "Detection Algorithm," and it is advisory: it
answers which command to run before any exploration exists, and nothing in it
feeds what happens afterward. Once an exploration has run, `/explore` scores the
findings instead -- two stages, four terminal outcomes and four chain entry
points, with the preconditions and tiebreakers in
`skills/explore/references/quality/crystallize-framework.md`. This file
describes the levels; `/explore` owns both surfaces.

### Key discriminators between levels

| Boundary | Question |
|----------|----------|
| Strategic vs Complex | Multi-feature initiative or single capability? |
| Complex vs Simple | Can the user state both what to build and how? |
| Simple vs Trivial | Does a GitHub issue exist or is one warranted? |

## Named transitions

Four transitions connect diamonds and handle non-linear flow.

| Transition | From | To | When |
|------------|------|-----|------|
| **Advance** | Any diamond | Next diamond | Normal progression. Crystallize names a terminal outcome or a chain entry point; /plan produces issues; /release ships. |
| **Recycle** | Any diamond | Same diamond | The converge step sends work back to diverge. Crystallize can't pick an outcome; review finds gaps in the plan. |
| **Hold** | Any point | Paused | Work is paused. The artifact stays at its current status. No state transition occurs. |
| **Kill** | Any point | Abandoned | Work is abandoned. Artifacts may move to a Dropped or Superseded state (convention TBD, see F11). |

Advance is the default. Recycle happens when a diamond's converge step
determines the work isn't ready to move forward. Hold and Kill are human
decisions.

There is no transition that bypasses a diamond's steps. Work enters the pipeline
at one point, and from there every step of the chain it entered runs. Whether a
document is worth producing is answered by reading it against the one before it,
which is possible only once both exist, so the reduction happens afterward and
not from a classification made at entry. `/scope`'s consolidation judgment is
that mechanism; see [`parent-skill-pattern.md`](parent-skill-pattern.md).

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
              └── Brief (upstream: the Roadmap's own parent --
                          Strategy, or Vision; never the Roadmap)
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

**Direction.** The target's type is one the naming type may point at, and the
rule is the same on both chains: an artifact names the nearest artifact actually
produced above it, and any strictly-higher altitude is legal because not every
altitude is written on every run. A DESIGN with no BRIEF above it names the PRD;
a ROADMAP written where no STRATEGY exists names the VISION. What no artifact
does is point downward or sideways -- a BRIEF never names a PRD, which is
written from the brief's framing.

Reaching past an altitude that *does* exist is a different matter, and this
check does not adjudicate it. Legality is decided from two basenames, so the
check cannot tell a roadmap that skipped an existing strategy from one written
where no strategy exists; rejecting the second in order to catch the first would
fail the legitimate case. Preferring the nearest altitude is therefore authoring
guidance -- `/roadmap` states it in its own contract, and `/charter` runs
`/strategy` ahead of it, so a roadmap written inside the strategic chain is
handed a STRATEGY -- rather than a rule the validator enforces. An earlier
version of this file called the strategic chain strict and the tactical chain
loose; both halves were wrong. `/scope` walks all four tactical altitudes on
every run, and the strategic chain is the one where an altitude is routinely
absent.

**Lifetime.** A link runs from the shorter-lived document to the longer-lived
one. Roadmaps and Plans are working artifacts: they are deleted when their work
completes. Every other type is durable. So a durable document never names a
working one -- the link would be correct on the day it is written and dangling
on the day the cascade runs.

A working document may name another working one, and the guarantee there rests
on cascade ordering rather than on the lifetime classes alone. The classes say
nothing about which of two working documents dies first. The pair the table
actually admits is a PLAN naming a ROADMAP, and it is safe because a roadmap is
deleted only once all its features are Done, which means every plan beneath it
has already finalized. That ordering is the invariant; a change to deletion
order would break this link with nothing else pointing at why.

The two properties are enforced as `R10` (direction) and `R11` (lifetime). An
entry violating both reports the lifetime finding, which is the diagnosis that
survives being acted on.

## Where the chains meet

The Roadmap is where the strategic chain hands off to the tactical one, and the
lifetime rule decides which document records the crossing. A Roadmap is a
working artifact, so no durable tactical document may name it: **the crossing is
recorded on the PLAN alone.** The PLAN is deleted by the same cascade that
deletes the Roadmap, and it goes first, so that link cannot dangle.

A BRIEF therefore never names the Roadmap it was framed against. It names the
Roadmap's own nearest durable ancestor instead, found by walking up exactly one
hop: the Strategy the roadmap sequences, or the Vision when it traces straight
to one. Both are durable, so one hop always terminates -- a Roadmap's parents
are the only two strategic types and neither is working. The lineage survives
the roadmap's deletion, which is the point: a reader following a brief's
upstream reaches the strategy that chose this feature, and it is still there.

The brief still reads the roadmap -- the framing, the sequencing rationale, the
neighbouring features -- and absorbs that context into its own prose. It covers
a slice of the roadmap's scope, so absorbing that slice is owed whatever the
`upstream:` field ends up holding, and the Problem Statement's standing
obligation to make sense cold is what carries it.

The field is omitted when the walk finds nothing to record: a roadmap that names
no upstream of its own, or an ancestor that is private where the brief is
public. That second case is the older rule for an upstream a document cannot
reach -- omit the field, absorb the context, stand as the head of the chain.
The two rules meet here: an upstream that will not *last* is resolved past, and
an upstream that cannot be *reached* is omitted. Only the first can be checked
by tooling, because a cross-repo value resolves to nothing.

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
| Whole tactical chain in one sitting | /scope -> BRIEF -> PRD -> DESIGN -> PLAN |
| Whole strategic chain in one sitting | /charter -> VISION -> STRATEGY -> ROADMAP |
| One feature to specify, however large | /scope -> /execute -> /release |
| Project needs a thesis, or features need ordering | /charter -> per-feature /scope |
| Shape unclear, multiple unknowns | /explore -> (crystallize) -> the entry point it names |
| Feasibility unknown | /explore -> (crystallize) -> spike report |
| Single contested choice | /explore -> (crystallize) -> /decision |

Every sequence starts at something an author runs. The rows that used to name a
chain hop as a destination -- design-then-plan for a known approach, a PRD or a
design after crystallize, the strategic children after `--strategic` -- named
steps that `/scope` and `/charter` now sequence themselves, so they collapse
into the parent rows above.

The crystallize step in `/explore` decides whether an exploration is a terminal
outcome or a chain, and for a chain, which entry point receives it; it is
documented in `skills/explore/references/quality/crystallize-framework.md`. The
detection algorithm in `skills/explore/SKILL.md` suggests a complexity level
before an exploration exists.

### Roadmap branching

Strategic work follows a branching pattern. A Roadmap decomposes into
features. Each feature gets a planning issue, and `/plan` labels it with what
the feature is missing: `needs-prd` or `needs-design`. The label is an entry
signal, not a route. A feature carrying either one enters the tactical chain at
`/scope`, which writes the framing, the requirements, the design, and the plan
in that order and folds a hop away only once the document it would fold is on
disk. A feature with no `Needs` annotation is ready for direct implementation.

```
Roadmap
  ├── Feature A (needs-prd) -> /scope -> /execute
  ├── Feature B (needs-design) -> /scope -> /execute
  └── Feature C (no Needs annotation) -> file an issue -> /work-on
```

The feasibility and single-choice labels this tree used to branch on are retired
from the label vocabulary, because the triage that assigned them is gone. Both
questions reach `/explore` instead, which authors the spike report and routes a
single choice to `/decision`. See
`skills/explore/references/label-reference.md` for the surviving vocabulary.

Each feature's pipeline runs independently. The Roadmap tracks overall
progress; /plan enriches the Roadmap with an Implementation Issues table
and Dependency Graph.
