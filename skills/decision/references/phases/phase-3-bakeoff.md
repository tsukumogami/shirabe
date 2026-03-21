# Phase 3: Validation Bakeoff

Spawn one validator agent per alternative. Each argues FOR their assigned option.
Full path (Tier 4) only -- skipped for fast path.

## Resume Check

If `wip/<prefix>_bakeoff_*.md` files exist, skip to Phase 4.

## Steps

### 3.1 Spawn Validator Agents

For each alternative, spawn a persistent validator agent via the Agent tool
with `run_in_background: true`. Launch ALL validators in a single message.

Each validator receives:

```
Agent tool:
  prompt: |
    You are a validator arguing FOR "<alternative-name>" as the solution to:
    <decision question>

    Alternative description: <from alternatives artifact>
    Constraints: <from context artifact>
    Research findings: <from research artifact>

    Your job is to make the strongest case FOR this alternative. Be honest
    about weaknesses but advocate for it. Cover:

    1. Strengths: what makes this the right choice
    2. Weaknesses: acknowledged limitations (honest assessment)
    3. Risks: what could go wrong
    4. Implementation implications: what it means for the codebase
    5. Recommendation: your overall assessment

    Write your validation report to wip/<prefix>_bakeoff_<N>.md
    Return a 5-line summary of your position.
```

### 3.2 Collect Results

Wait for all validators to complete. Read each summary. If a validator fails
or times out, note the failure -- Phase 4 and 5 will work with available
validators.

**Store validator agent IDs.** They will be re-messaged in Phases 4 and 5
via SendMessage. The agent IDs are needed for continuation.

## Quality Checklist

- [ ] One validator spawned per alternative
- [ ] All validators completed (or failures noted)
- [ ] Validator agent IDs stored for Phase 4-5 continuation

## Next Phase

Proceed to Phase 4: Peer Revision (`phase-4-revision.md`)
