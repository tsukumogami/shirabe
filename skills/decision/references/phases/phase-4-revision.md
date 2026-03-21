# Phase 4: Informed Peer Revision

Each validator sees what the others found and revises their position.
Full path (Tier 4) only.

## Resume Check

If validator bakeoff files show revision markers (`## Revised Position`),
skip to Phase 5.

## Steps

### 4.1 Compile Peer Summaries

For each validator, compile a summary of ALL OTHER validators' positions
(from their Phase 3 bakeoff reports). Don't include a validator's own report
in its peer summary.

### 4.2 Send Peer Context to Each Validator

Use SendMessage to continue each validator agent with the peer context:

```
SendMessage to validator-<N>:
  Here are the positions from the other validators evaluating competing
  alternatives for: <decision question>

  <Validator A summary>
  <Validator B summary>
  ...

  Review their findings. You may:
  - Defend your position with new evidence
  - Add caveats based on what peers found
  - Acknowledge strengths in competing alternatives
  - Revise your overall assessment

  Update your report at wip/<prefix>_bakeoff_<N>.md with a
  "## Revised Position" section.
  Return your revised summary (3-5 lines).
```

### 4.3 Collect Revised Positions

Read each validator's revised summary. Note changes from their Phase 3 position.

**Timeout fallback:** if a validator doesn't respond to SendMessage (agent was
garbage collected or timed out), use its Phase 3 position as its final word.

## Quality Checklist

- [ ] Each validator received all peer summaries
- [ ] Revised positions collected (or Phase 3 fallback used)

## Next Phase

Proceed to Phase 5: Cross-Examination (`phase-5-examination.md`)
