# Phase 5: Produce

Hand off to the target command based on the crystallize decision.

## Goal

Write handoff artifacts matching the target command's expected format, then
either continue in the same session (for /prd and /design) or tell the user
what to run next (for /plan and no artifact). The exploration's research files
stay in wip/ for the target workflow to reference.

## Resume Check

If `wip/explore_<topic>_crystallize.md` exists, read it and proceed with the
handoff. The chosen type is in the `## Chosen Type` section.

If the handoff has already been partially completed (e.g., the design doc
skeleton exists but the summary file doesn't), pick up where it left off
rather than rewriting what's already there.

## Inputs

- **Crystallize decision**: `wip/explore_<topic>_crystallize.md`
- **Findings file**: `wip/explore_<topic>_findings.md` (for content to populate
  handoff artifacts)
- **Decisions file**: `wip/explore_<topic>_decisions.md` (if it exists; accumulated
  decisions from convergence rounds)
- **Scope file**: `wip/explore_<topic>_scope.md` (for the original context)

## Steps

### 5.1 Read the Crystallize Decision

Read `wip/explore_<topic>_crystallize.md` and extract the chosen type.

Route to the matching section below:

| Chosen Type | Go To |
|-------------|-------|
| PRD | Step 5.2 |
| Design Doc | Step 5.3 |
| Plan | Step 5.4 |
| No artifact | Step 5.5 |
| Roadmap | Step 5.7 |
| Spike Report | Step 5.8 |
| Decision Record | Step 5.9 |
| Competitive Analysis | Step 5.10 |
| Deferred type (Prototype) | Step 5.6 |

### 5.2 PRD Handoff

Write `wip/prd_<topic>_scope.md` matching /prd Phase 1's output format.
Synthesize content from the exploration findings -- don't just copy raw
research output.

```markdown
# /prd Scope: <topic>

## Problem Statement
<2-3 sentences synthesized from exploration. State the problem clearly,
grounded in what the exploration discovered.>

## Initial Scope
### In Scope
- <item from exploration findings>
- <item>

### Out of Scope
- <item>

## Research Leads
1. <lead>: <rationale from exploration>
2. <lead>: <rationale>

## Coverage Notes
<Gaps or uncertainties to resolve in /prd Phase 2. What did the exploration
NOT answer that a PRD process should address?>

## Decisions from Exploration
<If wip/explore_<topic>_decisions.md exists, include accumulated decisions
here. These are scope narrowing, option eliminations, and priority choices
already made during exploration that the PRD should treat as settled.
If the decisions file doesn't exist, omit this section.>
```

After writing, hand off to /prd:

1. Read the /prd skill: `../prd/SKILL.md`
2. Continue at Phase 2 (Discover). Phase 1 (Scope) is already done -- the
   handoff artifact fills that role.

Commit before handoff: `docs(explore): hand off <topic> to /prd`

### 5.3 Design Doc Handoff

Write two files. Synthesize content from the exploration findings.

**1. Design doc skeleton** at `docs/designs/DESIGN-<topic>.md`:

```markdown
---
status: Proposed
problem: |
  <1 paragraph from exploration findings. Be specific about what needs
  to be decided and why.>
---

# DESIGN: <Topic>

## Status

Proposed

## Context and Problem Statement

<From exploration findings. Cover what prompted the exploration, what was
discovered, and what architectural or technical decisions remain open.>

## Decision Drivers

<From exploration findings. List the factors that should influence the
technical decision. Pull from tensions, constraints, and user priorities
surfaced during exploration.>

## Decisions Already Made

<If wip/explore_<topic>_decisions.md exists, include the accumulated
decisions here. These are choices settled during exploration that the
design should treat as constraints, not reopen. If the decisions file
doesn't exist, omit this section.>
```

**2. Summary file** at `wip/design_<topic>_summary.md`:

```markdown
# Design Summary: <topic>

## Input Context (Phase 0)
**Source:** /explore handoff
**Problem:** <1-2 sentences>
**Constraints:** <key constraints from exploration>

## Current Status
**Phase:** 0 - Setup (Explore Handoff)
**Last Updated:** <date>
```

After writing both files, hand off to /design:

1. Read the /design skill: `../design/SKILL.md`
2. Continue at Phase 1 (Approach Discovery). Phase 0 (Setup) is done -- the
   handoff artifacts fill that role.

Commit before handoff: `docs(explore): hand off <topic> to /design`

### 5.4 Plan Handoff

Two paths depending on whether open decisions remain:

**No open decisions** (scope is clear, work is decomposable, no architectural
decisions need to be documented first): Tell the user to run `/plan <topic>` where
topic is a short description of what was explored. /plan will treat this as a direct
topic and produce a plan without requiring an upstream document.

**Open decisions remain** (technical approach or requirements still need to be
documented): Tell the user to complete the upstream artifact first, then run
`/plan <artifact-path>` once it's accepted. Suggest /prd if requirements need
capturing, /design if the technical approach is open.

Tell the user:

> Your exploration confirmed the scope and approach. Run `/plan <topic>` to break
> the work into issues directly.

or, if open decisions remain:

> Your exploration identified "plan" as the right next step, but [technical approach /
> requirements] still need to be documented first. [Create a design doc / PRD], then
> run `/plan <artifact-path>` once it's accepted.
>
> Your exploration research is saved in `wip/` if you need to reference it.

If the crystallize decision noted that an existing artifact covers this topic,
include its path in the suggestion.

### 5.5 No Artifact

Only appropriate when exploration produced no new decisions — it confirmed what was
already known, or validated that a simple, clearly-understood task can proceed.

**Before finalizing this path:** check `wip/explore_<topic>_decisions.md`. If it
exists and contains any entries, the exploration made decisions that need a permanent
home. Architectural choices, dependency selections, or structural decisions need a
design doc even if nothing remains undecided. `wip/` is cleaned before merge —
decisions recorded only there are permanently lost.

If the decisions file exists and has entries, return to Phase 4 and reconsider.
"No artifact" means nothing was decided that a future contributor needs to know,
not that everything is now settled.

If the decisions file doesn't exist or is empty, this path is appropriate.

If truly no decisions were made, summarize what was learned and suggest concrete
next steps.

Present to the user:

> Your exploration covered [brief summary of what was investigated]. Here's
> what we found:
>
> [3-5 bullet points: key findings, grounded in specifics]
>
> **Suggested next steps:**
> - Create a focused issue with `/issue` if there's a specific task to track
> - Start implementing directly with `/work-on` if the path is clear

No handoff artifacts to write. No commit needed beyond what prior phases
already committed.

### 5.6 Unsupported Type (Prototype Only)

The only remaining deferred type is **Prototype**. Prototypes produce working
code rather than documentation artifacts, so they don't fit the skill-based
production pattern.

Present the decision using AskUserQuestion following the pattern in
`references/decision-presentation.md`.

**Description field:** Explain that Prototype was selected as best fit, but
prototype production isn't available through /explore -- prototypes are code
artifacts that need hands-on development rather than document generation.

**Recommendation heuristic:** If the exploration focused on feasibility or
unknowns, recommend the spike report. If it focused on architecture or system
structure, recommend the design doc.

**Options (order by recommendation heuristic):**
1. "Create a spike report (Recommended)" or "Create a design doc (Recommended)" -- based on heuristic
2. The other document option, with justification for why it ranks lower
3. "Stop here -- research is saved in wip/"

If the user picks spike report, route to step 5.8 (Spike Report).
If the user picks design doc, route to step 5.3 (Design Doc).

### 5.7 Roadmap

Produce a roadmap directly. Read the roadmap skill for format reference:
`../roadmap/SKILL.md`

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

### 5.8 Spike Report

Produce a spike report directly. Read the spike-report skill for format
reference: `../spike-report/SKILL.md`

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

This is safe even if the label isn't present -- `gh issue edit --remove-label`
is a no-op for labels that don't exist on the issue.

Tell the user:

> Created `docs/spikes/SPIKE-<topic>.md` as a Draft spike report. The
> exploration findings have been incorporated where relevant.
>
> Complete the investigation within the timebox, then update Findings and
> Recommendation to transition to Complete.

### 5.9 Decision Record

Produce a decision record directly. Read the decision-record skill for format
reference: `../decision-record/SKILL.md`

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

This is safe even if the label isn't present -- `gh issue edit --remove-label`
is a no-op for labels that don't exist on the issue.

Tell the user:

> Created `docs/decisions/ADR-<topic>.md` as a Proposed decision record.
> Review the decision and rationale, then transition to Accepted when the
> team agrees.

### 5.10 Competitive Analysis

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

Route to the user's chosen alternative (step 5.3, 5.8, or end).

**If private repo:** Produce the analysis. Read the competitive-analysis skill
for format reference: `../competitive-analysis/SKILL.md`

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

## Cleanup Rule

Do NOT delete `wip/` research files after routing. Target skills may reference
them for context. Cleanup happens when the target workflow completes or when
the user runs `/cleanup`.

## Quality Checklist

Before completing:
- [ ] Crystallize decision read and chosen type identified
- [ ] Correct routing path followed for the chosen type
- [ ] Handoff artifacts written in the target command's expected format (if applicable)
- [ ] Content synthesized from exploration findings (not raw copy-paste)
- [ ] Target skill's SKILL.md read before continuing (for /prd and /design)
- [ ] Handoff committed before reading the target skill
- [ ] wip/ research files left in place (not deleted)
- [ ] Deferred type (Prototype only) handled with clear explanation and alternatives
- [ ] New artifact types (Roadmap, Spike, ADR, Competitive Analysis) produced directly
- [ ] Competitive analysis: repo visibility checked before producing
- [ ] Spike report / decision record: `needs-spike` or `needs-decision` label removed from source issue (if applicable)

## Artifact State

After this phase (varies by routing path):

**PRD handoff:**
- All explore artifacts in `wip/` (untouched)
- `wip/prd_<topic>_scope.md` (new)
- Session continues in /prd at Phase 2

**Design Doc handoff:**
- All explore artifacts in `wip/` (untouched)
- `docs/designs/DESIGN-<topic>.md` (new)
- `wip/design_<topic>_summary.md` (new)
- Session continues in /design at Phase 1

**Plan handoff:**
- All explore artifacts in `wip/` (untouched)
- No new artifacts; user runs `/plan <path>` separately

**No artifact:**
- All explore artifacts in `wip/` (untouched)
- No new artifacts

**Roadmap:**
- All explore artifacts in `wip/` (untouched)
- `docs/roadmaps/ROADMAP-<topic>.md` (new, Draft)

**Spike Report:**
- All explore artifacts in `wip/` (untouched)
- `docs/spikes/SPIKE-<topic>.md` (new, Draft)
- Source issue: `needs-spike` label removed (if from issue)

**Decision Record:**
- All explore artifacts in `wip/` (untouched)
- `docs/decisions/ADR-<topic>.md` (new, Proposed)
- Source issue: `needs-decision` label removed (if from issue)

**Competitive Analysis (private repos only):**
- All explore artifacts in `wip/` (untouched)
- `docs/competitive/COMP-<topic>.md` (new, Draft)

## Next Phase

None. Phase 5 is the final phase of /explore. If the session continues into
/prd or /design, the target skill's orchestrator takes over.
