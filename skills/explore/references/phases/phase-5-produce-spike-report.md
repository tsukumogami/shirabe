# Phase 5: Spike Report

`/explore` authors this one. A spike report is not a chain artifact and no skill
owns `docs/spikes/`, so the arm keeps its author here rather than routing.

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

## Artifact State

After this step:
- All explore artifacts in `wip/` (untouched)
- `docs/spikes/SPIKE-<topic>.md` (new)
- No handoff to another skill — this is the final produce step
