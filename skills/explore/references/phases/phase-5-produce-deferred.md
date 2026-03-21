# Phase 5: Deferred Artifact Types

This file handles artifact types that were recognized during crystallize but fall
outside the core /prd, /design, /plan routing. Each section produces the artifact
directly rather than handing off to another skill.

## Table of Contents

- [Unsupported Type (Prototype)](#unsupported-type-prototype-only)
- [Roadmap](#roadmap)
- [Spike Report](#spike-report)
- [Decision Record](#decision-record)
- [Competitive Analysis](#competitive-analysis)

---

## Unsupported Type (Prototype Only)

The only remaining deferred type is **Prototype**. Prototypes produce working
code rather than documentation artifacts, so they don't fit the skill-based
production pattern.

Present the decision using AskUserQuestion following the pattern in
`${CLAUDE_PLUGIN_ROOT}/references/decision-presentation.md`.

**Description field:** Explain that Prototype was selected as best fit, but
prototype production isn't available through /explore -- prototypes are code
artifacts that need hands-on development rather than document generation.

**Recommendation heuristic:** If the exploration focused on feasibility or
unknowns, recommend the spike report. If it focused on architecture or system
structure, recommend the design doc.

**Options (order by recommendation heuristic):**
1. "Create a spike report (Recommended)" or "Create a design doc (Recommended)"
2. The other document option, with justification for why it ranks lower
3. "Stop here -- research is saved in wip/"

If the user picks spike report, follow the Spike Report section below.
If the user picks design doc, read `phase-5-produce-design.md` instead.

---

## Roadmap

Produce a roadmap directly.

Write `docs/roadmaps/ROADMAP-<topic>.md`:

```markdown
---
status: Draft
theme: |
  <1 paragraph synthesized from exploration findings. What initiative is
  being sequenced and why does coordination matter?>
scope: |
  <1 paragraph bounding the roadmap. Which features are included, which
  are deliberately excluded?>
---

# ROADMAP: <Topic>

## Status

Draft

## Theme

<Expanded from frontmatter. What capability area, why sequencing matters.>

## Features

<Ordered list of features identified during exploration. For each:>

### Feature N: <Name>

<1-2 sentence description. What this feature delivers.>

**Dependencies:** <which earlier features must complete first, or "None">
**Status:** Not Started
**Downstream:** <path to PRD/design doc if known, or "Needs PRD">

## Sequencing Rationale

<Why this order? What constraints drive the sequencing? Distinguish hard
technical dependencies from soft preferences.>

## Progress

| Feature | Status | Downstream Artifact |
|---------|--------|-------------------|
| Feature 1: <name> | Not Started | -- |
| Feature 2: <name> | Not Started | -- |
```

Commit: `docs(explore): produce roadmap for <topic>`

Tell the user:

> Created `docs/roadmaps/ROADMAP-<topic>.md` as a Draft roadmap. Review the
> feature list and sequencing, then transition to Active when ready.
>
> To start work on individual features, create PRDs for each one.

---

## Spike Report

Produce a spike report directly.

Write `docs/spikes/SPIKE-<topic>.md`:

```markdown
---
status: Draft
question: |
  <The specific feasibility question, synthesized from exploration.
  Should be answerable with go/no-go.>
timebox: "<estimated time based on exploration complexity>"
---

# SPIKE: <Topic>

## Status

Draft

## Question

<Expanded from frontmatter. The specific question this investigation
will answer.>

## Context

<From exploration findings. Why this question matters now, what decision
is blocked.>

## Approach

<Planned or completed investigation steps. What to try, what tools to
use, what to measure.>

## Findings

<Evidence from exploration if available. Otherwise: "Investigation not
yet started." If the exploration already gathered relevant data, include
it here.>

## Recommendation

<If findings exist: go/no-go with conditions. If not yet investigated:
"Pending investigation.">
```

Commit: `docs(explore): produce spike report for <topic>`

If the exploration started from an issue (issue number known from Phase 0),
remove the `needs-spike` label:

```bash
gh issue edit <N> --remove-label needs-spike
```

Tell the user:

> Created `docs/spikes/SPIKE-<topic>.md` as a Draft spike report. The
> exploration findings have been incorporated where relevant.
>
> Complete the investigation within the timebox, then update Findings and
> Recommendation to transition to Complete.

---

## Decision Record

Produce a decision record directly.

Write `docs/decisions/ADR-<topic>.md`:

```markdown
---
status: Proposed
decision: |
  <1 paragraph stating the proposed decision, synthesized from exploration.
  What specific choice is being made?>
rationale: |
  <1 paragraph explaining why this choice, based on exploration findings.
  What factors drove this recommendation?>
---

# ADR: <Topic>

## Status

Proposed

## Context

<From exploration findings. The situation prompting this decision, forces
at play, constraints.>

## Decision

<The specific choice being proposed. One clear statement.>

## Options Considered

<From exploration findings. Each option with brief description and
acceptance/rejection reason.>

### Option A: <Name>

<Description and trade-offs.>

### Option B: <Name>

<Description and trade-offs.>

## Consequences

<What changes as a result. Positive outcomes and accepted trade-offs.
What becomes easier, what becomes harder.>
```

Commit: `docs(explore): produce decision record for <topic>`

If the exploration started from an issue (issue number known from Phase 0),
remove the `needs-decision` label:

```bash
gh issue edit <N> --remove-label needs-decision
```

Tell the user:

> Created `docs/decisions/ADR-<topic>.md` as a Proposed decision record.
> Review the decision and rationale, then transition to Accepted when the
> team agrees.

---

## Competitive Analysis

**Before producing, check repo visibility.** Read the nearest `CLAUDE.md` file
and check for visibility indicators (`Repo Visibility: Private`, path contains
`private/`, or Private Repository Context heading).

**If public repo:** Refuse and explain:

> Your exploration points to **Competitive Analysis** as the best fit, but
> competitive analyses can only be created in private repositories.
>
> **Alternatives:**
> 1. Create a design doc with competitive findings in the Market Context section
>    (requires strategic scope in a private repo)
> 2. Create a spike report investigating a specific technical approach instead
> 3. Stop here -- your research is saved in `wip/`

Route to the user's chosen alternative.

**If private repo:** Produce the analysis.

Write `docs/competitive/COMP-<topic>.md`:

```markdown
---
status: Draft
market: |
  <1 paragraph identifying the market segment, synthesized from
  exploration findings.>
date: "<today's date, YYYY-MM-DD>"
---

# COMP: <Topic>

## Status

Draft

## Market Overview

<From exploration findings. The segment being analyzed, key dimensions
of competition.>

## Competitors

<From exploration findings. Individual analysis per competitor.>

### <Competitor Name>

**Strengths:** <specific>
**Weaknesses:** <specific>
**Approach:** <how they address the space>

## Comparative Matrix

| Dimension | <Our product> | <Competitor 1> | <Competitor 2> |
|-----------|---------------|----------------|----------------|
| <dim 1> | | | |
| <dim 2> | | | |

## Opportunities

<Gaps in the competitive landscape that represent opportunities.>

## Implications

<How findings should influence our decisions. Connect insights to
specific choices.>
```

Commit: `docs(explore): produce competitive analysis for <topic>`

Tell the user:

> Created `docs/competitive/COMP-<topic>.md` as a Draft competitive analysis.
> Complete the analysis and transition to Final when all sections have
> substantive content.
