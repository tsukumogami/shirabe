# Lightweight Decision Protocol

A 3-step micro-workflow for inline decisions during skill execution. Shared
across all workflow skills. For heavyweight decisions (Tier 3-4), use the
decision skill instead.

## When to invoke

The protocol triggers when ANY of these hold at a decision point:

- The decision affects downstream artifacts
- A reasonable person could have chosen differently
- The choice rests on a falsifiable assumption
- Reversing would require rework

**Tier 1 (trivial)** decisions skip the protocol entirely: only one reasonable
option, instantly reversible, no downstream impact. Just do it.

## The three steps

### Step 1: Frame

State the question in one sentence. Identify what's at stake.

### Step 2: Gather

Check available evidence from loaded context before deciding. This is NOT
research-agent-level investigation -- it's what you can determine from context
already loaded: codebase patterns, prior decisions in this workflow, constraint
files, existing artifacts.

The key discipline: **look before you leap.** Don't default to asking the user
(interactive) or guessing (non-interactive) when the answer is in the codebase.

During gather, evaluate whether the decision needs escalation. If you find
contradicting evidence or the decision is practically irreversible, check the
tier classification signals below. Tier 3+ decisions should escalate to the
decision skill rather than completing the micro-protocol.

### Step 3: Decide and record

Pick the best option. Write a decision block (see `decision-block-format.md`)
in the current artifact.

**Interactive mode:** present the recommendation via AskUserQuestion with the
evidence from Step 2. The user confirms or overrides. Record the user's choice.

**Non-interactive mode (--auto):** follow the recommendation. Write a decision
block with `status="assumed"` if the evidence was ambiguous, `status="confirmed"`
if clear. Continue without waiting.

## Tier classification

### For known decision points

Read `references/decision-points.md` to find the pre-assigned tier for each
known decision point. No runtime classification needed.

### For emergent decisions

Decisions discovered mid-execution (not in the manifest) use a three-signal
checklist in override order:

1. **Reversibility**: is the decision practically irreversible? -> Tier 4
2. **Heuristic confidence**: does a clear winner emerge from the evidence?
   - Yes -> Tier 2 (stay in micro-protocol)
   - No (contested, ambiguous) -> Tier 3
3. **Phase primacy**: is this the primary question this phase exists to answer?
   - Yes -> minimum Tier 3

**Default: Tier 2.** When signals are ambiguous, document the choice with the
micro-protocol. Over-documenting is better than under-escalating.

## Escalation to heavyweight

If Step 2 reveals the decision is Tier 3+:

1. Write a partial decision block with Question and Evidence gathered so far
2. Mark it `status="escalated"`
3. Invoke the decision skill (via agent spawn or inline, per the parent skill's
   static dispatch mode)
4. The decision skill reads the partial block as seed context
5. The decision skill's report replaces the partial block in the manifest

No information is lost. The decision skill's Phase 1 (research) abbreviates
what the lightweight protocol already gathered.

## Recording decisions

All decision blocks are inline in their source artifacts (the wip/ file where
the decision was made). The consolidated decisions file
(`wip/<workflow>_<topic>_decisions.md`) indexes all blocks.

After writing a decision block, append an entry to the consolidated file:

```markdown
| <id> | <artifact-path> | <tier> | <status> | <question-abbreviated> |
```

The consolidated file is the source of truth for review. Inline blocks are
write-time snapshots.

## Interaction with --auto mode

| Aspect | Interactive | Non-interactive (--auto) |
|--------|------------|--------------------------|
| Step 1 (frame) | Same | Same |
| Step 2 (gather) | Same | Same |
| Step 3 (decide) | Present via AskUserQuestion | Follow recommendation, document |
| Status | `confirmed` after user confirms | `confirmed` or `assumed` per threshold |
| Escalation | Same | Same (spawn agent if Tier 3+) |
