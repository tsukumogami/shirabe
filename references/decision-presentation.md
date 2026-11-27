# Decision Presentation

How agents present decisions to users during workflows.

## Philosophy

Agents aren't neutral facilitators. They investigate, gather evidence, and form a recommendation. The user then approves, redirects, or overrides.

This means: don't present options side by side and ask "which one?" Pick the best option based on what you found, say why, and let the user course-correct if they disagree. Users can always override. What they shouldn't have to do is re-derive the recommendation from scratch.

## Decision Variants

### Selection Decision (Multiple Options)

Use when the user needs to pick between two or more distinct options.

**Structure:**

1. **Recommended option first.** Mark it in the option's description, not its
   label: the description opens with "Recommended." and the label stays the
   bare name of the option. A question raised with `shirabe question raise`
   is rendered this way, because koto compares the labels the person saw with
   the stored ones when it records the answer.
2. **Alternatives follow.** Each gets a short justification for why it ranks lower than the recommendation.
3. **Description field** contains the evidence-based reasoning. Ground it in specific findings from investigation, not abstract trade-off lists. Cite what you found: file names, API responses, compatibility constraints, prior decisions in the codebase.

**Example option ordering:**
```
Option 1: label "SQLite", description "Recommended. One file beside the runner, no server to run."
Option 2: label "PostgreSQL", description "Adds operational complexity we don't need at current scale."
Option 3: label "None of these", description "Describe an alternative."
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

## Re-grounding

Before asking a question, orient the user with a one-line context header:

> **Workflow:** `/explore koto` · **Phase:** Round 1 convergence · **Decision:** explore further or crystallize

Format: `**Workflow:** <command> · **Phase:** <current phase> · **Decision:** <what's being decided>`

**Required** after any async work — agent dispatch, parallel research, tool operations that take more than a few seconds. The user may have stepped away.

**Optional** during rapid back-and-forth where the prior exchange is still visible and context hasn't shifted.

Practical test: if the user stepped away for 5 minutes, would they know where they are without scrolling up? If no, include the header.

A prompt rendered by `shirabe question render` needs no header printed
before it: its question text already opens with the context and the problem.

## Question Prompt Limits

`shirabe question raise` refuses content that would not fit the question
prompt unchanged, so `render` never alters a field koto compares:

- two to four options per question, the recommendation first;
- up to four questions per prompt (`render` splits a longer list into several
  prompts);
- a header of 12 characters (koto's `prompt_header`, `#` and 11 hex digits);
- a question text, the context, the problem and the question joined by blank
  lines, of at most 8,192 bytes;
- an option label of at most 64 bytes, with no control character;
- a description of at most 1,024 bytes. A longer reason is shortened at
  render with a fixed ` [shortened]` marker, except on a question or option
  carrying the standing mark, which `raise` refuses instead.

These are shirabe's bounds, not limits the question tool publishes. When the
tool's own limits are measured lower, the bounds here move with them.

What a session does with a question it cannot settle, from deciding first to
recording the owner's answer, is in `references/question-procedure.md`.

## What This Helper Doesn't Cover

This file defines the project convention for structuring decisions. It doesn't document the AskUserQuestion tool itself or its parameters. For tool usage, refer to the tool's own documentation.
