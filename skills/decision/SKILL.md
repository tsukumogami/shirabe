---
name: decision
description: >-
  Structured decision-making skill for contested choices. Use when facing a decision
  with 3+ viable alternatives, contradicting evidence, or irreversible consequences.
  Runs a multi-phase evaluation: research, alternative identification, validation
  bakeoff with adversarial agents, peer revision, cross-examination, and synthesis.
  Triggers on "decide between X and Y", "which approach should we use for Z",
  "I need to choose between A, B, and C", or when a lightweight decision escalates
  via status="escalated". Also invocable as a sub-operation by /design for parallel
  multi-decision orchestration.
argument-hint: '<decision question or topic>'
---

@.claude/shirabe-extensions/decision.md
@.claude/shirabe-extensions/decision.local.md

# Decision Skill

Make well-reasoned, auditable decisions through structured evaluation. The skill
produces decision reports that map directly to design doc Considered Options
sections and standalone Decision Records (ADRs).

**Writing style:** Read `skills/writing-style/SKILL.md` for guidance.

## Decision Tiers

This skill handles Tier 3 (standard) and Tier 4 (critical) decisions. For Tier 1-2,
use the lightweight decision protocol (`references/decision-protocol.md`).

| Tier | Path | Phases | When |
|------|------|--------|------|
| 3 (standard) | Fast | 0, 1, 2, 6 | 3+ options, needs research, but not adversarial |
| 4 (critical) | Full | 0, 1, 2, 3, 4, 5, 6 | Irreversible, high-stakes, contested |

## Agent Hierarchy

When invoked as a sub-operation by a parent skill (e.g., /design), the decision
skill runs as a **decider agent**. The decider spawns sub-agents:

```
Level 1: Parent skill (design, explore)
  └── Level 2: Decider agent (this skill, one per decision question)
        ├── Level 3: Research agent (Phase 1, disposable)
        ├── Level 3: Alternative agents (Phase 2, disposable)
        └── Level 3: Validator agents (Phases 3-5, persistent via SendMessage)
              ├── Phase 3: argue FOR their alternative (bakeoff)
              ├── Phase 4: receive peer findings, revise position
              └── Phase 5: cross-examine peers, reach final position
```

**Validator persistence is critical.** Validators are spawned in Phase 3 and
re-messaged via `SendMessage` in Phases 4-5. They retain their full conversation
history to revise and defend their positions. Research and alternative agents are
disposable (single task, then done).

## Sub-Operation Interface

When invoked by a parent skill, the decider receives a decision context:

```yaml
decision_context:
  question: "Which cache invalidation strategy?"
  prefix: "design_foo_decision_1"
  options:
    - name: "TTL-based"
      description: "..."
  constraints:
    - "Must support < 100ms latency"
  background: |
    The system currently uses...
  complexity: "standard"  # standard | critical
```

And produces:

```yaml
decision_result:
  status: "COMPLETE"
  chosen: "TTL-based"
  confidence: "high"
  rationale: "..."
  assumptions:
    - "Redis cluster remains available"
  rejected:
    - name: "Event-driven"
      reason: "Adds infrastructure dependency for marginal gain"
  report_file: "wip/design_foo_decision_1_report.md"
```

See `references/decision-report-format.md` for the canonical output format
with consumer rendering sections.

## Input Detection

From `$ARGUMENTS`:
1. **Empty** -- ask what needs to be decided (or infer from context in --auto)
2. **Decision question** -- use as the topic, proceed to Phase 0

Check for `--auto` flag. In --auto mode, the skill never blocks on user input.
Follow `references/decision-protocol.md` for assumption handling.

## Workflow Phases

```
Phase 0: CONTEXT --> Phase 1: RESEARCH --> Phase 2: ALTERNATIVES --> Phase 3: BAKEOFF --> Phase 4: REVISION --> Phase 5: EXAMINATION --> Phase 6: SYNTHESIS
                                                    (fast path skips 3-5) ──────────────────────────────────────────────────────────────┘
```

| Phase | Purpose | Agents | Artifact |
|-------|---------|--------|----------|
| 0 | Context and framing | None | `wip/<prefix>_context.md` |
| 1 | Research critical unknowns | 1 research agent (disposable) | `wip/<prefix>_research.md` |
| 2 | Identify and present alternatives | N alternative agents (disposable) | `wip/<prefix>_alternatives.md` |
| 3 | Validation bakeoff | N validator agents (persistent) | `wip/<prefix>_bakeoff_<N>.md` |
| 4 | Informed peer revision | Same validators (SendMessage) | Updated bakeoff files |
| 5 | Cross-examination | Same validators (SendMessage) | `wip/<prefix>_examination.md` |
| 6 | Synthesis and report | None (decider synthesizes) | `wip/<prefix>_report.md` |

**Fast path (Tier 3):** skip Phases 3-5. No validators spawned. The decider
goes from alternatives presentation directly to synthesis.

## Resume Logic

```
if wip/<prefix>_report.md exists           -> Decision complete
if wip/<prefix>_examination.md exists      -> Resume at Phase 6
if wip/<prefix>_bakeoff_*.md exist         -> Resume at Phase 4
if wip/<prefix>_alternatives.md exists     -> Resume at Phase 3 (or Phase 6 for fast path)
if wip/<prefix>_research.md exists         -> Resume at Phase 2
if wip/<prefix>_context.md exists          -> Resume at Phase 1
else                                       -> Start at Phase 0
```

## Phase Execution

Execute phases sequentially by reading the corresponding phase file:

0. **Context and Framing**: `references/phases/phase-0-context.md`
1. **Research**: `references/phases/phase-1-research.md`
2. **Alternative Presentation**: `references/phases/phase-2-alternatives.md`
3. **Validation Bakeoff**: `references/phases/phase-3-bakeoff.md`
4. **Peer Revision**: `references/phases/phase-4-revision.md`
5. **Cross-Examination**: `references/phases/phase-5-examination.md`
6. **Synthesis and Report**: `references/phases/phase-6-synthesis.md`

## Cleanup

After Phase 6 writes the report, delete intermediate artifacts:
- `wip/<prefix>_context.md`
- `wip/<prefix>_research.md`
- `wip/<prefix>_alternatives.md`
- `wip/<prefix>_bakeoff_*.md`
- `wip/<prefix>_examination.md`

Only the final `wip/<prefix>_report.md` persists. This keeps wip/ manageable
when the parent skill runs multiple decisions.

## Validator Agent Contract

Validators are persistent agents. The contract between phases:

**Phase 3 (spawn):**
- Input: alternative description, decision question, constraints, background
- Output: validation report (strengths, weaknesses, risks, recommendation)

**Phase 4 (SendMessage):**
- Input: summaries from all OTHER validators
- Output: revised report (may change recommendation, add caveats)

**Phase 5 (SendMessage):**
- Input: specific challenges from competing validators
- Output: final position (defend, concede, or qualify)

If a validator times out or errors during Phase 4-5, the decider uses the
validator's last known position rather than re-spawning.

---

## Reference Files

| File | When to load |
|------|-------------|
| `references/phases/phase-0-context.md` | Phase 0 |
| `references/phases/phase-1-research.md` | Phase 1 |
| `references/phases/phase-2-alternatives.md` | Phase 2 |
| `references/phases/phase-3-bakeoff.md` | Phase 3 (full path only) |
| `references/phases/phase-4-revision.md` | Phase 4 (full path only) |
| `references/phases/phase-5-examination.md` | Phase 5 (full path only) |
| `references/phases/phase-6-synthesis.md` | Phase 6 |
| `references/decision-report-format.md` | Phase 6 (output format) |
| `references/decision-block-format.md` | Phase 6 (block delimiters) |
