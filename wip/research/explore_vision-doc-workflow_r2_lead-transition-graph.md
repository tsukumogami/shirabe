# Artifact Type Transition Graph

Research output for the vision-doc-workflow exploration, Round 2.

## Artifact Type Inventory

All nodes in the directed graph:

| Node | Category | Owning Command | Permanent Location |
|------|----------|----------------|--------------------|
| **Idea** | Entry point (not an artifact) | None | N/A |
| **VISION** | Proposed new type | None yet | `docs/vision/VISION-*.md` (proposed) |
| **Roadmap** | Supported (deferred produce) | /explore Phase 5 | `docs/roadmaps/ROADMAP-*.md` |
| **PRD** | Supported | /prd | `docs/prds/PRD-*.md` |
| **Design Doc** | Supported | /design | `docs/designs/DESIGN-*.md` |
| **Plan** | Supported | /plan | `docs/plans/PLAN-*.md` |
| **Issue** | GitHub artifact | /plan (creates) | GitHub Issues |
| **PR** | GitHub artifact | /work-on (creates) | GitHub PRs |
| **Spike Report** | Supported (deferred produce) | /explore Phase 5 | `docs/spikes/SPIKE-*.md` |
| **Decision Record** | Supported | /decision (via /explore) | `wip/*_decision_report.md` |
| **Competitive Analysis** | Supported (private only) | /explore Phase 5 | `docs/competitive/COMP-*.md` |
| **Rejection Record** | Supported | /explore Phase 5 | `docs/decisions/REJECTED-*.md` |
| **No Artifact** | Terminal | /explore Phase 5 | N/A |
| **Prototype** | Unsupported (deferred) | None | N/A |

---

## ASCII Directed Graph

```
                                    +------------------+
                                    |      IDEA        |
                                    +--------+---------+
                                             |
                   +------------+------------+-------------+-----------+
                   |            |            |             |           |
                   v            v            v             v           v
              /explore       /prd       /design        /plan      /work-on
                   |            |            |             |           |
                   v            |            |             |           |
            +-----------+      |            |             |           |
            | SCOPE     |      |            |             |           |
            +-----+-----+      |            |             |           |
                  |             |            |             |           |
                  v             |            |             |           |
            +-----------+      |            |             |           |
            | DISCOVER  |<-+   |            |             |           |
            +-----+-----+  |   |            |             |           |
                  |         |   |            |             |           |
                  v         |   |            |             |           |
            +-----------+   |   |            |             |           |
            | CONVERGE  +---+   |            |             |           |
            +-----+-----+      |            |             |           |
                  | ready       |            |             |           |
                  v             |            |             |           |
            +-----------+      |            |             |           |
            |CRYSTALLIZE|      |            |             |           |
            +-----+-----+      |            |             |           |
                  |             |            |             |           |
     +----+----+--+--+----+----+---+---+    |             |           |
     |    |    |     |    |    |   |   |    |             |           |
     v    v    v     v    v    v   v   v    v             v           v
   PRD  DDoc Plan  Road Spike Dec Rej NoA  PRD        DDoc         Issue
    |    |    :     |    :    |   .   .     |            |           :
    |    |    :     |    :    |             |            |           :
    v    v    :     v    :    v             v            v           v
  /prd /des  :   (man.) :  /dec          /prd         /des        /work-on
  auto auto  :     |    :   auto         (man.)       (man.)      (man.)
    |    |   :     |    :    |             |            |           |
    v    v   v     v    v    v             v            v           v
   PRD DDoc Plan Roadmap Spike DecRec    PRD         DDoc          PR
   (a)  (b)  .    (c)   (d)   (e)       (f)          (g)
```

Legend: `auto` = /explore auto-invokes the downstream skill in the same session.
`man.` or `:` = user must manually invoke the next command. `.` = terminal.

---

## Complete Transition Table

### Entry Transitions (Idea to First Artifact)

| From | To | Trigger | Mode | Condition |
|------|----|---------|------|-----------|
| Idea | /explore | User runs `/explore <topic>` | Manual | Don't know what artifact type is needed |
| Idea | /prd | User runs `/prd <topic>` | Manual | Know requirements need capturing |
| Idea | /design | User runs `/design <topic>` | Manual | Know what to build, not how |
| Idea | /plan | User runs `/plan <topic>` | Manual | Direct topic, scope already clear |
| Idea | /work-on | User runs `/work-on <issue>` | Manual | Simple task, no artifact needed |

### /explore Internal Loop

| From | To | Trigger | Mode | Condition |
|------|----|---------|------|-----------|
| Scope | Discover (R1) | Leads identified | Auto | Always |
| Discover (RN) | Converge | Research agents return | Auto | Always |
| Converge | Discover (RN+1) | User says "explore further" | Manual (interactive) / Auto (--auto) | Gaps remain |
| Converge | Crystallize | User says "ready to decide" | Manual (interactive) / Auto (--auto) | Sufficient coverage |
| Crystallize | Produce | Type scored and confirmed | Auto | Always |
| Crystallize | Discover (RN+1) | Insufficient-signal fallback | Auto | No type scores above 0 |

### /explore Phase 5 Produce Transitions

| From (Crystallize Output) | To (Artifact) | Handoff Mode | What Happens |
|---------------------------|---------------|--------------|--------------|
| Crystallize -> PRD | PRD (Draft) | **Auto-continue**: writes `wip/prd_<topic>_scope.md`, invokes /prd | /prd resumes at Phase 2 (Discover), skipping Phase 1 (Scope) |
| Crystallize -> Design Doc | Design Doc (Proposed) | **Auto-continue**: writes skeleton + summary, invokes /design | /design resumes at Phase 1 (Decompose), skipping Phase 0 (Setup) |
| Crystallize -> Decision Record | Decision Brief | **Auto-continue**: writes brief, invokes /decision | /decision runs its phases |
| Crystallize -> Plan | (no artifact) | **Manual stop**: tells user to run `/plan` | User runs `/plan <topic>` or `/plan <upstream-path>` separately |
| Crystallize -> Roadmap | Roadmap (Draft) | **Inline produce**: writes `docs/roadmaps/ROADMAP-*.md` | Terminal for /explore; user creates PRDs per feature |
| Crystallize -> Spike Report | Spike Report (Draft) | **Inline produce**: writes `docs/spikes/SPIKE-*.md` | Terminal for /explore; user completes investigation |
| Crystallize -> Competitive Analysis | Comp Analysis (Draft) | **Inline produce**: writes `docs/competitive/COMP-*.md` | Terminal for /explore; private repos only |
| Crystallize -> Rejection Record | Rejection Record | **Inline produce**: writes `docs/decisions/REJECTED-*.md` | Terminal; optionally routes to /decision for formal ADR |
| Crystallize -> No Artifact | (nothing) | **Terminal**: summarizes findings | Suggests `/issue` or `/work-on` as next steps |
| Crystallize -> Prototype | (fallback) | **Manual stop**: offers spike report or design doc | Prototype production not supported |

### Artifact-to-Artifact Downstream Transitions

| From | To | Trigger | Mode | Condition |
|------|----|---------|------|-----------|
| **VISION** | Roadmap | User creates roadmap referencing vision | Manual | Vision covers multiple features (proposed) |
| **VISION** | PRD | User runs `/prd` referencing vision | Manual | Vision covers single feature (proposed) |
| **Roadmap** | PRD (per feature) | User creates PRD for each feature | Manual | Feature needs requirements |
| **Roadmap** | Plan (planning issues) | User runs `/plan <roadmap-path>` | Manual | Produces one planning issue per feature with needs-* labels |
| **PRD** (Accepted) | Design Doc | User runs `/design <PRD-path>` | Manual | PRD mode: /design imports requirements, transitions PRD to "In Progress" |
| **PRD** (Accepted) | Plan | User runs `/plan <PRD-path>` | Manual | Simple enough to plan directly without design |
| **PRD** (Accepted) | /work-on | User runs `/work-on <issue>` | Manual | Simple PRD, one implementation issue |
| **Design Doc** (Accepted) | Plan | User runs `/plan <design-path>` | Manual | Standard decomposition path |
| **Plan** (Active) | Issues | /plan Phase 7 creates GitHub issues | Auto | Multi-pr mode |
| **Plan** (Active) | /implement | User runs `/implement <plan-path>` | Manual | Drives issue-by-issue implementation |
| **Issue** | PR | /work-on creates branch, implements, opens PR | Auto | Standard implementation |
| **Spike Report** (Complete) | PRD or Design Doc | User acts on go/no-go | Manual | If go: proceed to next artifact; if no-go: stop |
| **Decision Record** | Design Doc or PRD | Decision informs upstream | Manual | Decision unblocks stalled design/requirements work |
| **Rejection Record** | Decision Record | High re-proposal risk | Manual (optional) | /explore Phase 5 offers this route |

### Skip Paths (Shortcuts)

| From | To | Skips | Condition |
|------|----|-------|-----------|
| Idea | /work-on | All artifacts | Simple, clear task; one person; no coordination needed |
| Idea | /prd -> /work-on | Design, Plan | Simple PRD, direct implementation |
| Idea | /design -> /plan -> /work-on | PRD | Technical problem where "what" is obvious |
| /explore -> Plan | PRD, Design Doc | Explore confirmed scope, no open decisions remain |
| PRD -> /plan | Design Doc | Work is decomposable without architectural decisions |
| PRD -> /work-on | Design Doc, Plan | Single implementation issue, trivial scope |

### Loop Edges

| Loop | Condition | Max |
|------|-----------|-----|
| /explore: Discover <-> Converge | User wants more research | `--max-rounds=N` (default 3 in --auto) |
| /explore: Crystallize -> Discover | Insufficient-signal fallback (no type scores > 0) | Same round limit |
| /explore: No Artifact -> Crystallize | Decisions file has entries, reconsider | One reconsideration |
| /design: Phase 2 decision agents | Each decision question runs /decision | Bounded by question count |
| Roadmap -> PRD -> Design -> Plan -> Issue -> PR (repeated per feature) | Each roadmap feature follows its own pipeline | Bounded by feature count |

### Branching Edges

| From | Fan-out | Condition |
|------|---------|-----------|
| Roadmap | N x PRDs | Each feature in the roadmap can spawn an independent PRD |
| Roadmap via /plan | N x Planning Issues | Each with needs-prd, needs-design, needs-spike, or needs-decision labels |
| Plan | N x Issues | Decomposition creates multiple sequenced issues |
| /explore Discover phase | N x Research Agents | Parallel investigation of leads |

---

## Missing Transitions (Gaps the Pipeline Needs)

### 1. VISION -> Roadmap / PRD (not yet implemented)

No VISION artifact type exists. The proposed type would sit above Roadmap and PRD as the strategic entry point. Without it, the pipeline has no place to capture project thesis, org fit, or strategic justification before committing to a roadmap or PRD.

**Needed edges:**
- VISION -> Roadmap (multi-feature initiative)
- VISION -> PRD (single-feature initiative)
- /explore -> VISION (when crystallize determines the idea is too early for requirements)

### 2. Spike Report -> downstream artifact

Spike reports have no automatic handoff. After a spike completes with "go," the user must manually decide whether to write a PRD, design doc, or just start implementing. No wip/ handoff artifact is produced.

**Needed edge:** Spike Report (Complete, go) -> /prd or /design with handoff context.

### 3. Competitive Analysis -> downstream artifact

Same gap as spike reports. The analysis is terminal with no structured next step.

**Needed edge:** Competitive Analysis (Final) -> PRD or Design Doc (importing implications).

### 4. Roadmap feature -> /explore (per feature)

When a roadmap feature is complex or poorly understood, there's no documented path back into /explore for that specific feature. The user would need to manually run `/explore <feature-topic>`.

**Needed edge:** Roadmap Feature (needs-exploration) -> /explore <feature>.

### 5. Rejection Record -> reopened exploration

If preconditions for revisiting are met later, there's no structured way to resume. The user starts fresh with no reference to the prior rejection.

**Needed edge:** Rejection Record -> /explore (with rejection record as context input).

### 6. Decision Record -> commit to downstream artifact

The decision skill produces a report in wip/, but there's no structured handoff to the artifact that was blocked on the decision. The user must manually integrate the decision.

**Needed edge:** Decision Record (resolved) -> resume blocked /design or /prd phase.

---

## Lifecycle States per Artifact Type

For completeness, each artifact type's internal lifecycle (not cross-artifact transitions):

| Type | States | Terminal States |
|------|--------|-----------------|
| VISION (proposed) | Draft -> Active -> Done | Done |
| Roadmap | Draft -> Active -> Done | Done |
| PRD | Draft -> Accepted -> In Progress -> Done | Done |
| Design Doc | Proposed -> Accepted -> Superseded/Archived | Superseded, Archived |
| Plan | Draft -> Active -> Done | Done |
| Spike Report | Draft -> Complete | Complete |
| Decision Record | (produced by /decision phases) | Report written |
| Competitive Analysis | Draft -> Final | Final |
| Rejection Record | (no lifecycle, written once) | Written |
