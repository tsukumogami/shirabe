# Phase 2: Present Approaches (CONVERGE)

Side-by-side comparison of all investigated approaches. Recommend based on evidence, user approves or overrides.

## Goal

Recommend the strongest approach based on advocate evidence, then let the user approve or override:
- Present all approaches with equal framing
- Highlight trade-offs, not just pros/cons
- Recommend the approach that best fits the decision drivers, grounded in advocate findings
- The user approves, overrides, or requests alternatives
- Write Considered Options and Decision Outcome into the design doc

See `references/decision-presentation.md` for the selection decision pattern.

## Resume Check

If the design doc already has a "Considered Options" section, skip to Phase 3.

## Steps

### 2.1 Build Comparison

Read all advocate reports from `wip/research/design_<topic>_phase1_advocate-*.md`.

Present approaches side-by-side. Don't summarize so aggressively that differences
are lost. The user needs to see the real trade-offs.

Format:

```
## Approach Comparison

### <Approach 1>
**What:** <2-3 sentences>
**Strengths:** <bulleted>
**Weaknesses:** <bulleted>
**Deal-breakers:** <if any>
**Complexity:** <small/medium/large>

### <Approach 2>
[same structure]

### Quick Comparison

| Factor | Approach 1 | Approach 2 | Approach 3 |
|--------|-----------|-----------|-----------|
| Complexity | ... | ... | ... |
| Risk | ... | ... | ... |
| <Key Driver 1> | ... | ... | ... |
| <Key Driver 2> | ... | ... | ... |
```

### 2.2 Recommend and Confirm

Based on the comparison and decision drivers, recommend the strongest approach.
Present via AskUserQuestion using the selection decision variant from
`references/decision-presentation.md`:

- Recommended option first, marked with "(Recommended)"
- Alternatives follow, each with a brief justification for why it ranks lower (grounded in advocate evidence)
- "None of these" as the final option (triggers loop-back)

### 2.3 Handle Loop-Back

If the user selects "None of these" or says a valid approach wasn't considered:

1. Ask what's missing or what assumptions were wrong
2. Delete the Phase 1 advocate reports that need replacement (if re-investigating
   an existing approach with different framing, delete its report)
3. Return to Phase 1, step 1.4 with the new/corrected approaches only
4. After new advocates complete, return here to Phase 2 with the full set

### 2.4 Write Considered Options

Write the "Considered Options" section in the design doc. For each approach:

```markdown
## Considered Options

### Decision <N>: <Decision topic>

**Context:** <What decision is being made>

**Chosen: <Selected approach>.**

<Why this approach was selected. Draw from the advocate's strengths and the
comparison with alternatives.>

*Alternative rejected: <Other approach>.* <Genuine explanation of why it was
rejected. Draw from the advocate's weaknesses. This must NOT be a strawman --
the advocate investigated this with equal depth.>
```

Group related decisions if the design involves multiple independent choices.

### 2.5 Write Decision Outcome

Write the "Decision Outcome" section:

```markdown
## Decision Outcome

<Summary of what will be built, based on the selected approach(es).>

Key properties:
- <Property 1>
- <Property 2>
```

### 2.6 Update wip/ Summary

```markdown
## Selected Approach (Phase 2)
<Which approach was chosen and why -- 2-3 sentences>

## Current Status
**Phase:** 2 - Present Approaches
**Last Updated:** <date>
```

Commit: `docs(design): select approach for <topic>`

## Quality Checklist

Before proceeding:
- [ ] All approaches presented with equal framing (no strawmen)
- [ ] Agent recommended based on evidence, user approved or overrode
- [ ] Rejected alternatives have genuine depth in Considered Options

## Artifact State

After this phase, the design doc has:
- All previous sections (Context, Decision Drivers)
- Considered Options section (new)
- Decision Outcome section (new)

## Next Phase

Proceed to Phase 3: Deep Investigation (`phase-3-deep-investigation.md`)
