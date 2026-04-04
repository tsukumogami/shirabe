# Multi-Level Planning in Project Management Tools

**Research Lead**: How do other workflow systems handle multi-level planning?
**Role**: User Researcher
**Date**: 2026-04-04

## Summary

Most mature project management tools use **separate entity types** for portfolio/roadmap-level planning versus implementation-level planning, but connect them through hierarchy. The dominant pattern is a type hierarchy (e.g., Epic > Story > Task) where higher levels serve roadmap purposes and lower levels serve implementation purposes. A minority use a single unified type with views/filters to create the illusion of separation. Both approaches have trade-offs, but the industry has converged on distinct types with structural relationships.

---

## Tool Analysis

### 1. Linear

**Model**: Separate entity types connected by hierarchy.

- **Roadmap level**: Projects and Roadmaps. Projects group related issues toward a goal. The Roadmap view shows Projects plotted on a timeline.
- **Implementation level**: Issues (with sub-issues). Issues live within Projects and represent concrete work items.
- **Relationship**: Projects contain Issues. Roadmaps visualize Projects over time. Cycles (sprints) pull Issues from Projects for execution.

**What works well**:
- Clean separation of concerns. Product managers work with Projects and Roadmaps; engineers work with Issues and Cycles.
- Roadmap view is a first-class feature, not just a filtered list of tasks.
- Sub-issues allow implementation decomposition without polluting the roadmap.

**Friction points**:
- Projects are relatively rigid containers. Changing scope means moving issues between Projects.
- The roadmap is primarily visual/timeline-based, not a sequenced dependency graph.

---

### 2. Jira (Atlassian)

**Model**: Distinct issue types in an explicit hierarchy.

- **Roadmap level**: Initiatives and Epics. In Jira Premium/Advanced, Initiatives sit above Epics. The "Roadmap" (formerly Advanced Roadmaps / Portfolio) visualizes Epics and Initiatives on a timeline with dependency arrows.
- **Implementation level**: Stories, Tasks, Bugs, Sub-tasks. These are children of Epics and represent concrete implementation work.
- **Relationship**: Initiative > Epic > Story/Task > Sub-task. Each level has its own fields, workflows, and board visibility.

**What works well**:
- The explicit type hierarchy maps naturally to organizational layers (leadership sees Initiatives, PMs see Epics, engineers see Stories).
- Advanced Roadmaps can roll up estimates and progress from child issues.
- Custom issue types allow teams to add intermediate levels if needed.

**Friction points**:
- Configuration complexity. Teams spend significant time setting up issue type schemes, screen schemes, and workflow schemes for each level.
- Cross-project dependencies are awkward. Roadmap items often span multiple Jira projects, requiring Portfolio-level features.
- The hierarchy is rigid -- you can't easily change an issue's type or move it between levels without losing metadata.

---

### 3. GitHub Projects (v2)

**Model**: Single entity type (Issues) with flexible metadata and views.

- **Roadmap level**: GitHub Projects provides a "Roadmap" layout that plots issues on a timeline using date fields. There's no separate "roadmap item" type -- you use labels, milestones, or custom fields to mark issues as high-level features.
- **Implementation level**: Issues and sub-issues (task lists / sub-issues feature). The same issue type at every level.
- **Relationship**: Flat by default. Hierarchy comes from task lists (sub-issues), milestones, and custom fields. Views (Board, Table, Roadmap) filter and group the same pool of issues.

**What works well**:
- Minimal ceremony. One issue type means low overhead to create and manage items.
- Views provide the "roadmap vs. plan" distinction without requiring separate types. A PM can create a Roadmap view filtering on `type:feature`, while an engineer uses a Board view filtering on `sprint:current`.
- Integrates tightly with PRs and code, so implementation tracking is automatic.

**Friction points**:
- No real hierarchy enforcement. Sub-issues are relatively new and limited. You can't roll up progress from sub-issues to parent issues reliably.
- Roadmap view is date-based only, not dependency-based. No automatic sequencing.
- Scaling issues: once you have hundreds of items, the lack of type distinction makes filtering essential but fragile (depends on consistent labeling).

---

### 4. Notion

**Model**: Unified database with views (single type, multiple perspectives).

- **Roadmap level**: Teams create a "Roadmap" database view (typically a Timeline or Board grouped by quarter) from their main task database. No separate entity type -- just filtered/grouped views.
- **Implementation level**: The same database items, viewed as a Board or Table filtered to current sprint/iteration.
- **Relationship**: Relations between database entries create parent-child links. Rollup properties can aggregate status from children.

**What works well**:
- Maximum flexibility. Teams design exactly the structure they need.
- A single source of truth avoids sync issues between "roadmap tool" and "task tool."
- Relations and rollups provide hierarchy without rigid type constraints.

**Friction points**:
- Requires significant upfront design. Teams must build their own hierarchy, fields, and views.
- No built-in workflow enforcement. A "roadmap item" is just an item with a certain property value -- nothing prevents someone from breaking the convention.
- Performance degrades with large databases. The flexibility comes at a cost.
- Easy to create incoherent structures where the same item appears in conflicting states across views.

---

### 5. Shape Up (Basecamp)

**Model**: Fundamentally separate concepts with no hierarchy.

- **Roadmap level**: Shape Up explicitly rejects long-term roadmaps. Instead, it uses "Bets" -- shaped pitches that are committed to for a 6-week cycle. The betting table is the closest analog to a roadmap, but it only covers one cycle ahead.
- **Implementation level**: Within a cycle, teams break Bets into "Scopes" -- discovered clusters of related work. Scopes are not pre-planned; they emerge during implementation.
- **Relationship**: Bets contain Scopes, but Scopes are not pre-defined. There is no multi-level hierarchy. The philosophy is that long-term sequencing is waste.

**What works well**:
- Forces focus. No roadmap means no roadmap debt (stale promises, shifting timelines).
- Scopes are emergent, matching how implementation actually unfolds rather than how PMs imagine it will.
- Clear separation of shaping (deciding what) from building (deciding how).

**Friction points**:
- Doesn't work for organizations that need to communicate a multi-quarter plan to stakeholders (investors, enterprise customers, partner teams).
- No dependency tracking between Bets across cycles.
- The lack of a roadmap is a feature for some teams but a dealbreaker for others.

---

### 6. Shortcut (formerly Clubhouse)

**Model**: Separate types in a hierarchy, similar to Jira but simpler.

- **Roadmap level**: Epics serve as the portfolio/roadmap level. Epics can be placed on a timeline view. Milestones group multiple Epics into larger goals.
- **Implementation level**: Stories (with Tasks as subtasks within Stories). Stories live within Epics and are organized into Iterations (sprints).
- **Relationship**: Milestone > Epic > Story > Task. Each level has different fields and views.

**What works well**:
- Simpler than Jira's hierarchy while still providing meaningful levels.
- Milestones provide a lightweight "initiative" level without the configuration burden.
- Epics have their own workflow states, so roadmap items can be tracked independently of their child Stories.

**Friction points**:
- Only three levels (Milestone/Epic/Story). Teams that need more granularity hit walls.
- Cross-epic dependencies require workarounds (labels, external tracking).

---

## Cross-Tool Patterns

### The Dominant Pattern: Separate Types, Connected by Hierarchy

Five of six tools (all except Notion) use **distinct entity types** for different planning levels. The typical hierarchy is:

```
Portfolio/Roadmap level:  Initiative / Project / Epic / Bet
     |
Implementation level:    Story / Issue / Task / Scope
     |
Granular level:          Sub-task / Sub-issue / Checklist item
```

Even GitHub Projects, which uses a single Issue type, is adding sub-issues and hierarchy features -- moving toward this pattern.

### Key Finding: "Same Type, Different Views" Sounds Good but Scales Poorly

Notion and GitHub Projects both attempt the "one type, many views" approach. In practice:
- It works well for small teams (< 15 people, < 200 items).
- It degrades as the item count grows, because filtering/labeling discipline breaks down.
- It creates confusion about what "done" means at different levels (is a roadmap item done when its label is updated, or when all its children are complete?).

### Key Finding: Separate Types Enable Separate Workflows

Tools with distinct types (Jira, Linear, Shortcut) can give each level its own workflow states. A roadmap Epic might flow through: Proposed > Committed > In Progress > Complete. An implementation Story might flow through: To Do > In Progress > In Review > Done. These are genuinely different processes with different stakeholders, and unifying them into one workflow creates compromises.

### Key Finding: The Connection Mechanism Matters More Than the Separation

Whether types are unified or separate, what users actually care about is:
1. **Roll-up**: Can I see implementation progress reflected at the roadmap level?
2. **Drill-down**: Can I go from a roadmap item to its implementation tasks?
3. **Dependency tracking**: Can I express "Feature B depends on Feature A" at the roadmap level?

Tools that nail these connections (Linear, Jira Advanced Roadmaps) get high marks regardless of whether the underlying types are "separate" or "unified."

---

## Implications for Roadmap vs. Plan Artifact Types

Based on this research:

1. **Separate types with clear connection is the industry standard.** Most tools distinguish roadmap-level from implementation-level because they serve different audiences, have different lifecycles, and need different metadata.

2. **A unified type with "level" metadata is viable but requires discipline.** Notion proves it can work, but also demonstrates the failure mode: without enforcement, the abstraction leaks.

3. **The critical design question is the connection mechanism.** Whether Roadmap and Plan are separate types or a single type with a scope field, the system needs to support: (a) a Roadmap item linking to one or more Plan items, (b) progress rolling up from Plan to Roadmap, and (c) each level having its own sequencing logic.

4. **Separate types reduce cognitive load.** When a user sees "Roadmap," they know it means portfolio-level sequencing. When they see "Plan," they know it means implementation-level sequencing. A unified "Plan" type with a "level" field requires users to always check which level they're looking at.
