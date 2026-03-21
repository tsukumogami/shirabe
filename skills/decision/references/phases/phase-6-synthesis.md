# Phase 6: Synthesis and Report

The decider reads all findings and produces the final decision report.

## Resume Check

If `wip/<prefix>_report.md` exists, the decision is complete. Skip this phase.

## Steps

### 6.1 Read All Inputs

**Fast path (Tier 3):**
- Context artifact (`wip/<prefix>_context.md`)
- Research findings (`wip/<prefix>_research.md`)
- Alternatives comparison (`wip/<prefix>_alternatives.md`)

**Full path (Tier 4):**
- All of the above, plus:
- Bakeoff reports (`wip/<prefix>_bakeoff_*.md`)
- Cross-examination record (`wip/<prefix>_examination.md`)

### 6.2 Synthesize Decision

Weigh the evidence and commit to a choice. For full path, the cross-examination
record provides the most refined view -- focus on:

- Points where all validators agreed (high confidence)
- Points where validators conceded (settled debates)
- Unresolved tensions (genuine trade-offs to document)

### 6.3 Write Decision Report

Write `wip/<prefix>_report.md` using the canonical format from
`references/decision-report-format.md`:

```markdown
<!-- decision:start id="<topic>" status="<confirmed|assumed>" -->
### Decision: <Topic>

**Context**
<from context artifact and research, 1-3 paragraphs>

**Assumptions**
- <from research assumptions + validator findings>

**Chosen: <Name>**
<full description, detailed enough to understand without reading alternatives>

**Rationale**
<why this option, tied to constraints and decision drivers>

**Alternatives Considered**
- **<Alt 1>**: <description>. Rejected because <reason from validators>.
- **<Alt 2>**: <description>. Rejected because <reason>.

**Consequences**
<what changes, what becomes easier, what becomes harder>
<!-- decision:end -->
```

### 6.4 Determine Status

Apply the status threshold from `references/decision-block-format.md`:

- If evidence clearly favored the choice and no assumptions were made: `confirmed`
- If assumptions exist, or evidence was contested, or the decision was made in
  --auto mode without user confirmation: `assumed`

### 6.5 Cleanup Intermediate Artifacts

Delete all intermediate files for this decision:
- `wip/<prefix>_context.md`
- `wip/<prefix>_research.md`
- `wip/<prefix>_alternatives.md`
- `wip/<prefix>_bakeoff_*.md`
- `wip/<prefix>_examination.md`

Only the report (`wip/<prefix>_report.md`) persists. This is essential for
multi-decision contexts where 5 decisions would otherwise produce 25+ files.

### 6.6 Return Result

If running as a sub-operation (agent), return the structured result:

```yaml
decision_result:
  status: "COMPLETE"
  chosen: "<name>"
  confidence: "<high|medium|low>"
  rationale: "<1-2 sentences>"
  assumptions:
    - "<assumption 1>"
  rejected:
    - name: "<alt>"
      reason: "<reason>"
  report_file: "wip/<prefix>_report.md"
```

If running standalone, commit the report and present a summary to the user.

## Quality Checklist

- [ ] All relevant inputs read (fast path or full path)
- [ ] Decision report written in canonical format
- [ ] Status correctly assigned (confirmed vs assumed)
- [ ] Intermediate artifacts cleaned up

## Next Phase

None. Phase 6 is the final phase. The report is the deliverable.
