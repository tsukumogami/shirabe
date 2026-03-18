# Phase 5: Security Review

MANDATORY security review. The review always runs. The artifact output is conditional.

## Why This Phase is Mandatory

Every design carries security implications. This phase is NOT optional -- skip it and
the design doc will fail validation in Phase 6.

## Goal

A dedicated security researcher agent analyzes the design and recommends one
of three outcomes:
1. **Findings need design changes** -- loop back to Phase 3 or 4
2. **Considerations worth documenting** -- write Security Considerations section
3. **N/A with justification** -- brief self-contained explanation of why no
   security dimensions apply

The review is always thorough. What varies is the design doc output.

## Resume Check

If `wip/research/design_<topic>_phase5_security.md` exists, read it and apply its
recommended outcome. Skip to Phase 6.

## Steps

### 5.1 Launch Security Researcher

Launch a dedicated security agent using the Agent tool with `run_in_background: true`.

**Security researcher prompt:**

```
You are a security researcher reviewing a technical design.

## Design Document
[Full design doc content -- all sections written so far]

## Security Dimensions

Analyze each dimension that applies to this design. Common dimensions include:

1. **External artifact handling**: Does this design download, execute, or process
   external inputs? How are they validated?
2. **Permission scope**: What filesystem, network, or process permissions does
   this feature require? Any escalation risks?
3. **Supply chain or dependency trust**: Where do dependencies or artifacts come
   from? How is source authenticity verified?
4. **Data exposure**: What user or system data does this feature access or
   transmit?

If your project has defined additional domain-specific security dimensions (via
`@.claude/shirabe-extensions/design.md`), apply those as well.

For each dimension: if it applies, assess severity and suggest mitigations.
If it doesn't apply, explain concretely why not.

## Instructions

1. For each dimension, determine if it applies to this design
2. If applicable: identify specific risks, assess severity, suggest mitigations
3. If not applicable: explain concretely why not (e.g., "this design only produces
   markdown files and does not download or execute anything")

## Output

Write your full analysis to `wip/research/design_<topic>_phase5_security.md`.

Format:
# Security Review: <topic>

## Dimension Analysis
### External Artifact Handling
**Applies:** Yes/No
<If yes: risks, severity, mitigations>
<If no: concrete reason why not>

### Permission Scope
[same structure]

### Supply Chain or Dependency Trust
[same structure]

### Data Exposure
[same structure]

## Recommended Outcome
Choose one:

**OPTION 1 - Design changes needed:**
<What needs to change and why. Reference specific sections.>

**OPTION 2 - Document considerations:**
<What the implementer needs to know. Draft the Security Considerations section.>

**OPTION 3 - N/A with justification:**
<Self-contained explanation of why no dimensions apply. This text will appear
in the design doc as-is, so it must make sense without the wip/ report.>

## Summary
<2-3 sentences: verdict and reasoning>

Return the Summary and Recommended Outcome choice to this conversation.
```

### 5.2 Apply Outcome

Based on the security researcher's recommendation:

**Option 1 -- Design changes needed:**
- Present the security findings to the user
- Discuss which changes to make
- Return to Phase 3 (if the approach needs rethinking) or Phase 4 (if architecture
  needs adjustment)
- After fixes, re-run Phase 5

**Option 2 -- Document considerations:**
- Write the "Security Considerations" section in the design doc using the
  researcher's draft
- Include: applicable dimensions, risks, mitigations, residual risk

**Option 3 -- N/A with justification:**
- Write a brief "Security Considerations" section with the self-contained
  justification from the researcher
- The justification must make sense on its own -- wip/ gets cleaned before merge,
  so future readers won't have access to the full report

### 5.3 Update wip/ Summary

```markdown
## Security Review (Phase 5)
**Outcome:** <Option 1/2/3>
**Summary:** <1-2 sentences>

## Current Status
**Phase:** 5 - Security
**Last Updated:** <date>
```

Commit: `docs(design): complete security review for <topic>`

## Quality Checklist

Before proceeding:
- [ ] Security researcher agent was launched and completed
- [ ] Full report written to `wip/research/design_<topic>_phase5_security.md`
- [ ] All security dimensions addressed (applicable or justified N/A)
- [ ] Recommended outcome applied to design doc
- [ ] If N/A: justification is self-contained (no wip/ references)
- [ ] If findings: changes made and security re-reviewed

## Artifact State

After this phase, the design doc has:
- All previous sections
- Security Considerations section (content varies by outcome)

## Next Phase

Proceed to Phase 6: Final Review (`phase-6-final-review.md`)
