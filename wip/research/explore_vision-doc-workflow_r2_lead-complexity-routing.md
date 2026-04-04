# Lead 12 + 13: Complexity Routing and Command Inventory

Research output for the vision-doc-workflow exploration, Round 2.

## Current Complexity Routing (from /explore)

The existing routing table in `/explore` SKILL.md defines three levels:

| Complexity | Signals | Recommended Path |
|------------|---------|------------------|
| Simple | Clear requirements, few files, one person | `/work-on` or `/prd` then implement |
| Medium | Known approach, some integration risk | `/design` then `/plan` |
| Complex | Multiple unknowns, shape unclear | `/explore` to discover first |

This table has gaps: it doesn't account for strategic-level work (new projects, multi-feature initiatives), doesn't address the top-of-funnel VISION stage, and doesn't route to private-plugin commands like `/implement`, `/roadmap`, or `/sprint`.

## Proposed Expanded Routing Table

Five complexity levels, adding Trivial below Simple and Strategic above Complex:

### Level 1: Trivial

**Signals:** Single file change, typo fix, config tweak, deleting obsolete content, no design decisions needed, under 30 minutes.

**Stages needed:** Implementation only.

**Stages skipped:** Everything upstream of implementation -- no exploration, no PRD, no design, no plan.

**Command path:**
```
/just-do-it <task> --> PR
```

No GitHub issue created. No wip/ artifacts. The only output is the PR itself.

### Level 2: Simple

**Signals:** Clear requirements already exist (in an issue or stated by user), affects few files, single person can complete, straightforward approach, one PR.

**Stages needed:** Issue resolution, implementation, PR.

**Stages skipped:** Exploration, PRD, design doc, plan doc.

**Command path:**
```
/work-on <issue> --> branch + implementation + PR
```

Or if requirements aren't captured yet:
```
/issue <topic> --> /work-on <N>
```

Triage may be needed if the issue has `needs-triage`. In that case:
```
/triage <N> --> /work-on <N>
```

### Level 3: Medium

**Signals:** Known problem with known general approach, but integration risk exists, multiple files affected, design decisions needed, 2-8 issues worth of work.

**Stages needed:** Design, planning, implementation.

**Stages skipped:** Exploration (approach is known), PRD (requirements are understood).

**Command path:**
```
/design <topic> --> /plan <design-doc> --> /implement <plan-doc>
   or
/design <topic> --> /plan <design-doc> --> /work-on <issue> (per issue)
```

The `/plan` step produces either a single-pr PLAN doc (consumed by `/implement`) or multi-pr GitHub issues (consumed by `/work-on` individually). `/review-plan` runs as a sub-phase of `/plan` before issue creation.

### Level 4: Complex

**Signals:** Multiple unknowns, shape unclear, feasibility questions, multiple possible approaches, cross-cutting concerns, 8+ issues likely.

**Stages needed:** Exploration to discover the right artifact type, then the full downstream pipeline.

**Stages skipped:** Nothing -- the exploration determines what's needed.

**Command path:**
```
/explore <topic> --> crystallize decision --> one of:
  - /prd <topic> --> /design <prd> --> /plan <design> --> /implement or /work-on
  - /design <topic> --> /plan <design> --> /implement or /work-on
  - /plan <topic> --> /implement or /work-on
  - No artifact (findings are sufficient)
  - Deferred: /roadmap, spike report, competitive analysis, prototype
```

The explore-converge loop may run multiple rounds before crystallizing.

### Level 5: Strategic (NEW -- VISION layer)

**Signals:** New project or major initiative, multi-feature scope, cross-repo impact, portfolio-level sequencing needed, timeline spans weeks or months, requires stakeholder alignment.

**Stages needed:** Vision/inception, roadmap, then per-feature pipelines at lower complexity levels.

**Stages skipped:** None at the portfolio level. Individual features within the roadmap may skip stages based on their own complexity.

**Proposed command path:**
```
VISION document (manual or /explore --strategic)
  --> /roadmap <vision-doc>
    --> /plan <roadmap> (produces planning issues, one per feature)
      --> per feature: assess complexity, route to Level 2-4 path
```

Key observations about this level:
- The VISION document is the new artifact type that doesn't exist yet as a skill
- `/roadmap` already exists as a document format skill but lacks a creation workflow
- `/plan` already handles roadmap inputs by producing planning issues (one per feature) rather than code issues
- Each feature in the roadmap re-enters the pipeline at its own complexity level
- `/explore --strategic` could serve as the creation workflow for VISION documents

## Full Command Inventory

### Shirabe Plugin (Public)

| Command | Pipeline Stage | Role |
|---------|---------------|------|
| `/explore` | Discovery | Determine what artifact type is needed; research unknowns |
| `/prd` | Requirements | Capture WHAT to build and WHY |
| `/design` | Architecture | Decide HOW to build it; trade-off analysis |
| `/decision` | Architecture (sub) | Structured evaluation for contested choices within /design |
| `/plan` | Decomposition | Break design/PRD/roadmap into implementable issues |
| `/review-plan` | Decomposition (sub) | Adversarial review of plan before issue creation |
| `/work-on` | Implementation | Implement a single issue end-to-end |
| `/release` | Delivery | Version selection, release notes, GitHub release |
| `/writing-style` | Cross-cutting | Prose quality enforcement |
| `/public-content` | Cross-cutting | Content governance for public repos |
| `/private-content` | Cross-cutting | Content governance for private repos |

### Private Plugin (tsukumogami)

| Command | Pipeline Stage | Role |
|---------|---------------|------|
| `/implement` | Implementation | State-machine implementation of PLAN docs |
| `/implement-doc` | Implementation | Implement all issues from a design doc in one PR |
| `/sprint` | Implementation (setup) | Clone repo and set up workspace for an issue |
| `/just-do-it` | Implementation (shortcut) | Trivial tasks without GitHub issues |
| `/try-it` | Verification | Manual testing of recent changes |
| `/triage` | Pre-implementation | Assess needs-triage issues for readiness |
| `/groom` | Backlog management | Walk through issues one-by-one |
| `/complete-milestone` | Completion | Validate and close a milestone |
| `/roadmap` | Strategic planning | Roadmap document format and lifecycle |
| `/issue` | Issue creation | Create well-formed GitHub issues |
| `/approve` | Review gate | User approval after review phases |
| `/ci` | CI monitoring | Resume CI monitoring for open PRs |
| `/done` | Completion | Mark work complete, update tracking |
| `/merged` | Post-merge | Monitor push workflows after merge |
| `/fix-pr` | PR maintenance | Update PR to follow template |
| `/qa` | Verification | QA testing patterns |
| `/qa-explore` | Verification | Exploratory QA testing |
| `/prepare-release` | Pre-release | Create release checklist issue |
| `/release` (tsukumogami) | Delivery | Generate notes and execute release |
| `/cleanup` | Housekeeping | Clean wip/ artifacts |
| `/docstatus` | Document lifecycle | Transition design doc status |
| `/spike-report` | Research | Spike report format and lifecycle |
| `/competitive-analysis` | Research (private) | Competitive analysis documents |
| `/decision-record` | Architecture | ADR format and lifecycle |
| `/design-doc` | Architecture | Design doc format and validation |
| `/bug-report` | Issue creation | Bug report format |
| `/issue-drafting` | Issue creation | Issue structure and quality |
| `/issue-filing` | Issue creation | Dedup and creation mechanics |
| `/issue-staleness` | Backlog health | Detect stale issue specs |
| `/issue-introspection` | Backlog health | Gap analysis on issue specs |
| `/github-milestone` | Project management | Milestone conventions |
| `/upstream-context` | Context gathering | Find strategic context for issues |
| `/planning-context` | Context gathering | Determine design scope from repo |

### Commands Mapped to Pipeline Stages

```
STAGE 1: INCEPTION (Strategic)
  Existing:  /explore --strategic, /roadmap (format only)
  Missing:   VISION doc creation workflow, /roadmap creation workflow

STAGE 2: DISCOVERY
  Existing:  /explore (full workflow with discover-converge loop)
  Complete.

STAGE 3: REQUIREMENTS
  Existing:  /prd (full workflow)
  Complete.

STAGE 4: ARCHITECTURE
  Existing:  /design (full workflow), /decision (sub-operation)
  Complete.

STAGE 5: DECOMPOSITION
  Existing:  /plan (full workflow), /review-plan (adversarial review)
  Complete.

STAGE 6: IMPLEMENTATION
  Existing:  /work-on, /implement, /implement-doc, /sprint, /just-do-it
  Complete (multiple paths for different scenarios).

STAGE 7: VERIFICATION
  Existing:  /try-it, /qa, /qa-explore, CI monitoring via /ci
  Complete.

STAGE 8: DELIVERY
  Existing:  /release, /prepare-release, /done, /merged, /complete-milestone
  Complete.

STAGE 9: MAINTENANCE
  Existing:  /groom, /triage, /issue-staleness, /issue-introspection, /cleanup
  Complete.
```

## Gaps Identified

### Gap 1: No VISION document skill
There's no `/vision` or equivalent skill to create inception-level documents. The VISION artifact type doesn't exist in the crystallize framework. `/explore --strategic` partially covers this, but it routes to existing artifact types (PRD, design, plan), not to a VISION doc.

### Gap 2: No /roadmap creation workflow
`/roadmap` exists as a format/lifecycle reference skill, but it has no creation workflow. It tells you what a roadmap looks like but doesn't guide you through creating one. Compare with `/prd` and `/design`, which have full multi-phase creation workflows.

### Gap 3: No automatic complexity assessment
The routing table exists in `/explore`'s documentation, but there's no standalone complexity assessment step. When a user runs `/work-on` on something that's actually Level 4 Complex, nothing stops them. `/triage` partially fills this role (it assesses "needs investigation" vs "needs breakdown" vs "ready"), but it only runs on `needs-triage` issues, not as a general gate.

### Gap 4: Roadmap-to-feature decomposition is under-specified
`/plan` handles roadmap inputs by producing "planning issues" (one per feature), but the handoff from planning issue back to the appropriate complexity level isn't formalized. Someone has to manually assess each feature's complexity and invoke the right command.

## How Complexity Should Be Determined

The routing decision shouldn't rely solely on user self-assessment. Signals that can be detected:

| Signal Source | What It Reveals | How to Detect |
|---------------|----------------|---------------|
| Issue labels | Triage status, blocking state | `gh issue view` -- labels field |
| Issue body length | Scope indicator | Character/section count |
| Dependency count | Integration complexity | Parse Dependencies section |
| File count estimate | Change scope | Mentioned files or directories |
| Cross-repo references | Coordination needs | Links to other repos |
| Existing artifacts | Prior work done | Check for PRD/design/plan docs |
| Milestone membership | Part of larger initiative | Milestone field present |
| User's stated intent | Direct signal | "just fix this" vs "redesign the system" |

A practical approach: `/triage` already runs a 3-agent adversarial assessment. This pattern could be generalized into a lightweight complexity check that runs at the start of any workflow entry point, recommending escalation or shortcutting as appropriate.
