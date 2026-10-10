# Phase 6: Synthesis and Report

The decider reads all findings and produces the final decision report.

## Resume Check

If key `<report_key>` exists in `<session>`, the decision is complete. Skip this phase.

## Steps

### 6.1 Read All Inputs

**Fast path (Tier 3):**
- Context (key `<key_dir>/context.md`)
- Research findings (key `<key_dir>/research.md`)
- Alternatives comparison (key `<key_dir>/alternatives.md`)

**Full path (Tier 4):**
- All of the above, plus:
- Bakeoff reports (keys `<key_dir>/bakeoff_*.md`)
- Cross-examination record (key `<key_dir>/examination.md`)

### 6.2 Synthesize Decision

Weigh the evidence and commit to a choice. For full path, the cross-examination
record provides the most refined view -- focus on:

- Points where all validators agreed (high confidence)
- Points where validators conceded (settled debates)
- Unresolved tensions (genuine trade-offs to document)

### 6.3 Write Decision Report

Write key `<report_key>` in `<session>` (`koto context add <session>
<report_key>`, the content on stdin) using the canonical format from
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

### 6.5 Remove the Intermediate Keys

Remove every intermediate key for this decision (`koto context remove
<session> <key>` for each):
- `<key_dir>/context.md`
- `<key_dir>/research.md`
- `<key_dir>/alternatives.md`
- `<key_dir>/bakeoff_<k>.md`, each one `koto context list <session> --prefix
  <key_dir>/bakeoff_` lists
- `<key_dir>/examination.md`

Only the report (key `<report_key>`) persists, so a parent reading the session
finds one answer per decision and a restarted decision starts fresh. Nothing
is deleted from the staging folder: `/decision` writes nothing there.

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
  report_key: "<report_key>"
```

If running standalone, present a summary and the report to the user (it stays
readable as key `work/report.md` in `decision-<topic>`), then close the
session:

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/skill-session.sh" close decision-<topic> done
```

Under a parent skill, close nothing: the parent owns the session and closes
it at its own end.

## Quality Checklist

- [ ] All relevant inputs read (fast path or full path)
- [ ] Decision report written in canonical format
- [ ] Status correctly assigned (confirmed vs assumed)
- [ ] Intermediate keys removed; a standalone run closed `decision-<topic>`

## Next Phase

None. Phase 6 is the final phase. The report is the deliverable.
