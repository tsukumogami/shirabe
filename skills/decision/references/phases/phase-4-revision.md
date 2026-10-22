# Phase 4: Informed Peer Revision

Each validator sees what the others found and revises their position.
Full path (Tier 4) only.

## Resume Check

If the bakeoff keys `<key_dir>/bakeoff_*` in `<session>` show revision markers
(`## Revised Position`), skip to Phase 5.

## Steps

### 4.1 Compile Peer Summaries

For each validator, compile a summary of ALL OTHER validators' positions
(from their Phase 3 bakeoff reports). Don't include a validator's own report
in its peer summary.

### 4.2 Send Peer Context to Each Validator

Validators revise their reports in place, so materialize each report into a
private directory first and keep the path `get` prints for each, `<report-N>`:

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/skill-session.sh" scratch          # prints <edit-dir>
"${CLAUDE_PLUGIN_ROOT}/scripts/skill-session.sh" get <session> <key_dir>/bakeoff_<N>.md <edit-dir>
                                                                  # prints <report-N>
```

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

  Update your report at <report-N> with a "## Revised Position"
  section. Do not write anywhere else.
  Return your revised summary (3-5 lines).
```

### 4.3 Collect Revised Positions

Read each validator's revised summary. Note changes from their Phase 3 position.
Write each revised report back to its key, then remove the directory:

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/skill-session.sh" put <session> <key_dir>/bakeoff_<N>.md <report-N>
rm -rf -- <edit-dir>
```

**Timeout fallback:** if a validator doesn't respond to SendMessage (agent was
garbage collected or timed out), use its Phase 3 position as its final word.

## Quality Checklist

- [ ] Each validator received all peer summaries
- [ ] Revised positions collected (or Phase 3 fallback used)

## Next Phase

Proceed to Phase 5: Cross-Examination (`phase-5-examination.md`)
