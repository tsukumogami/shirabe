# Phase 5: Cross-Examination

Validators challenge each other directly and reach final positions.
Full path (Tier 4) only.

## Resume Check

If `wip/<prefix>_examination.md` exists, skip to Phase 6.

## Steps

### 5.1 Identify Key Disagreements

Read all revised positions (from Phase 4). Identify the strongest
disagreements between validators -- points where one validator's strength
directly contradicts another's claim.

### 5.2 Send Challenges to Each Validator

Use SendMessage to continue each validator with targeted challenges:

```
SendMessage to validator-<N>:
  Cross-examination for: <decision question>

  Validator <M> (advocating for <alternative-M>) challenges your position:
  "<specific challenge based on their revised findings>"

  Validator <P> (advocating for <alternative-P>) also notes:
  "<another specific challenge>"

  Respond to each challenge. You may:
  - Defend with evidence
  - Concede the point
  - Qualify your position ("true, but mitigated by...")

  Write your final position to indicate:
  - Points you defend
  - Points you concede
  - Your overall final recommendation

  Return your final position summary (3-5 lines).
```

### 5.3 Compile Cross-Examination Record

Write `wip/<prefix>_examination.md` with a summary of the exchange:

```markdown
# Cross-Examination: <question>

## Key Disagreements
- <disagreement 1>: Validator A says X, Validator B says Y

## Final Positions
### Validator 1 (<alternative>)
<final position summary>

### Validator 2 (<alternative>)
<final position summary>

## Points of Consensus
- <things all validators agree on>

## Unresolved Tensions
- <genuine trade-offs where no validator conceded>
```

**Timeout fallback:** if a validator doesn't respond, use its Phase 4 revised
position as its final word.

## Quality Checklist

- [ ] Key disagreements identified and challenged
- [ ] Final positions collected from all validators
- [ ] Cross-examination record written to wip/

## Next Phase

Proceed to Phase 6: Synthesis and Report (`phase-6-synthesis.md`)
