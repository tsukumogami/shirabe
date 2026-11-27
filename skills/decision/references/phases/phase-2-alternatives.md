# Phase 2: Alternative Presentation

Identify all viable alternatives and present them for comparison.

## Resume Check

If key `<key_dir>/alternatives.md` exists in `<session>`, skip to Phase 3 (full
path) or Phase 6 (fast path).

## Steps

### 2.1 Generate Alternatives

If the context artifact has pre-identified options, use them as a starting point.
Spawn alternative agents to expand the list if the domain warrants research:

- Rapidly evolving or unfamiliar domain: spawn agents to research alternatives
- Established domain with well-known options: proceed from existing knowledge

Each alternative needs: name, description, and enough context for validators
(Phase 3) to evaluate it. Don't evaluate viability here -- that's the validators' job.

Cap at 5 alternatives. If more are identified, cluster related ones.

### 2.2 Document Each Alternative

Write one section per alternative in key `<key_dir>/alternatives.md`
(`koto context add <session> <key_dir>/alternatives.md`, the content on
stdin). Alternative agents return what they found to this conversation; they
write no file and no key.

```markdown
# Alternatives: <question>

## Alternative 1: <Name>
<description, context, key characteristics>
Source: <research | existing knowledge>

## Alternative 2: <Name>
<description, context, key characteristics>
Source: <research | existing knowledge>
```

### 2.3 Present Comparison

Build a side-by-side comparison and form a recommendation based on the evidence.

**Interactive mode:** present via AskUserQuestion with the recommendation and
evidence. User can approve, override, or request more alternatives.

**Non-interactive mode (--auto):** when the comparison has a clear winner,
take it. For fast path (Tier 3), write the decision block and proceed to
Phase 6. For full path (Tier 4), proceed to Phase 3 with all alternatives.

When it has none (no option is a clear winner, or a fact the choice rests on
could not be found), the decision does not settle here. For fast path, go to
Phase 6 with no chosen alternative: it ends the decision provisionally or
`UNDECIDED` by the cheap-or-costly test in `references/question-procedure.md`,
which this phase does not restate. For full path, go on to Phase 3; the
bakeoff may still settle it, and Phase 6 applies the same test if it does
not. Whether the run is unattended is read from the session, not from
`--auto`.

### 2.4 Fast Path Exit

If complexity is "standard" (Tier 3): skip Phases 3-5. The comparison from
Step 2.3 is sufficient. Proceed directly to Phase 6 (Synthesis) with the
chosen alternative and the alternatives document, or, when 2.3 found no clear
winner, with no chosen alternative and the recommendation.

## Quality Checklist

- [ ] All viable alternatives identified (2-5)
- [ ] Each alternative described with enough context for evaluation
- [ ] Alternatives stored as key `<key_dir>/alternatives.md`

## Next Phase

- **Fast path (standard):** Phase 6: Synthesis (`phase-6-synthesis.md`)
- **Full path (critical):** Phase 3: Bakeoff (`phase-3-bakeoff.md`)
