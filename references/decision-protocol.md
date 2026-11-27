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

Pick the best option when the evidence settles it. The step ends in one of
three ways:

1. **Ask the person**, in a turn the person started in an attended session:
   present the recommendation via AskUserQuestion with the evidence from Step
   2. The user confirms or overrides. Record the user's choice.
2. **Decide and record** when the evidence is clear (or the person is not
   there to ask and the evidence still favours one option): write a decision
   block (see `decision-block-format.md`) in the current artifact with
   `status="confirmed"`.
3. **When the evidence does not settle it and nobody can be asked**, apply the
   cheap-or-costly test in `references/question-procedure.md` and either
   record a provisional decision (cheap: an `assumed` block, and the attempt
   recorded `provisional`) or raise the question (costly: the attempt recorded
   `undecided`, no block with a choice, and work that does not depend on the
   answer goes on). The test and its rules live in that reference only.

Each attempt is recorded with `shirabe question attempt`. A koto-driven skill
records the attempt in its own session; a skill without one records it in the
session its decisions are kept in.

## Tier classification

### For known decision points

Read `docs/specs/decision-points.md` to find the pre-assigned tier for each
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

All decision blocks are inline in their source artifacts (the session key
or document where the decision was made). The consolidated decisions key
(`work/decisions.md` in the skill's koto session) indexes all blocks.

After writing a decision block, append an entry to the consolidated key:

```markdown
| <id> | <artifact-path> | <tier> | <status> | <question-abbreviated> |
```

`<status>` is the block's status: `confirmed`, `assumed`, `escalated` or
`undecided`. An `undecided` row stays in the index until the answer arrives;
the block that records the answer then gets its own row.

The consolidated key is the source of truth for review. Inline blocks are
write-time snapshots.

A koto-driven skill (one whose run is a koto session, such as `/work-on`)
records each decision with `koto decisions record <WF>` instead of an inline
block and index row; the session's decision log is its source of truth.

## Interaction with --auto mode

| Aspect | Interactive | Non-interactive (--auto) |
|--------|------------|--------------------------|
| Step 1 (frame) | Same | Same |
| Step 2 (gather) | Same | Same |
| Step 3 (decide) | Present via AskUserQuestion | Decide when the evidence is clear; otherwise the cheap-or-costly test in `references/question-procedure.md` |
| Status | `confirmed` after user confirms | `confirmed` when clear; `assumed` for a provisional decision; `undecided` (no block with a choice, question raised) for a costly one |
| Escalation | Same | Same (spawn agent if Tier 3+) |

Whether a run is attended is read from the session (see
`references/question-procedure.md`), not from the `--auto` flag: `--auto`
says not to prompt, not that nobody is there.
