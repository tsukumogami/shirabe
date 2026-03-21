# Decision Presentation

How agents present decisions to users during workflows.

## Philosophy

Agents aren't neutral facilitators. They investigate, gather evidence, and form a recommendation. The user then approves, redirects, or overrides.

This means: don't present options side by side and ask "which one?" Pick the best option based on what you found, say why, and let the user course-correct if they disagree. Users can always override. What they shouldn't have to do is re-derive the recommendation from scratch.

## Decision Variants

### Selection Decision (Multiple Options)

Use when the user needs to pick between two or more distinct options.

**Structure:**

1. **Recommended option first.** Mark it with "(Recommended)" in the option text.
2. **Alternatives follow.** Each gets a short justification for why it ranks lower than the recommendation.
3. **Description field** contains the evidence-based reasoning. Ground it in specific findings from investigation, not abstract trade-off lists. Cite what you found: file names, API responses, compatibility constraints, prior decisions in the codebase.

**Example option ordering:**
```
Option 1: "SQLite (Recommended)"
Option 2: "PostgreSQL - adds operational complexity we don't need at current scale"
Option 3: "None of these - describe an alternative"
```

When a "None of these" escape hatch is appropriate for the workflow, include it as the final option.

### Approval Decision (Binary)

Use when you've arrived at a single course of action and the user needs to approve or reject it.

**Structure:**

1. **Description field** states what you're proposing and why, grounded in evidence.
2. **Two options:** "Approve" and "Reject - provide alternative direction".

Don't use approval decisions as a shortcut when there are genuinely multiple viable paths. If you considered alternatives and ruled them out, briefly state what they were and why in the description.

## Equal Options

Sometimes investigation genuinely doesn't surface a clear winner. When this happens:

1. Say so explicitly in the description. Don't manufacture a false preference.
2. Still pick one as the recommended option.
3. Explain your tiebreaker. It can be arbitrary ("alphabetical," "simpler name") or pragmatic ("matches existing convention in `config.go`"). The point is transparency, not certainty.

Users handle "these are equal but I picked A because X" much better than "here are some options, you decide."

## What This Helper Doesn't Cover

This file defines the project convention for structuring decisions. It doesn't document the AskUserQuestion tool itself or its parameters. For tool usage, refer to the tool's own documentation.
