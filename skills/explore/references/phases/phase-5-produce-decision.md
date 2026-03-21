# Phase 5: Decision Record Handoff

When crystallize selects "Decision Record", write a decision brief and hand
off to the decision skill. This replaces the former inline ADR production.

## Decision Brief

Write `wip/explore_<topic>_decision-brief.md`:

```markdown
# Decision Brief: <topic>

## Decision Question
<One sentence: what specific choice needs to be made?>

## Context
<From findings: why this decision matters, what's blocked, forces at play.>

## Known Options
<From findings/decisions: options identified during exploration.
Each with a brief description and evidence for/against from research.>

## Constraints
<From findings: non-negotiable requirements, compatibility needs, timebox.>

## Relevant Research
<Paths to wip/research/ files the decision skill should read for detail.>

## Complexity Signal
<Simple (2 clear options, evidence strongly favors one) or
Complex (3+ options, trade-offs genuinely contested, stakeholders disagree)>
```

## Handoff

After writing the brief:

1. Read the decision skill: `skills/decision/SKILL.md`
2. Invoke the decision skill with the brief as input context:
   - question: from the Decision Question section
   - prefix: `explore_<topic>_decision`
   - options: from Known Options (if any)
   - constraints: from Constraints
   - background: from Context
   - complexity: from Complexity Signal ("simple" → standard, "complex" → critical)
3. The decision skill runs its phases and produces `wip/explore_<topic>_decision_report.md`
4. The report serves as the Decision Record (ADR)

## Escalation from Lightweight

If explore was running the lightweight protocol and escalated (status="escalated"),
the partial decision block's Question and Evidence become the brief's Decision
Question and Context sections. No information is lost.

## Commit

Commit the brief before handoff: `docs(explore): hand off <topic> to /decision`

## Artifact State

After this step:
- All explore artifacts in `wip/` (untouched)
- `wip/explore_<topic>_decision-brief.md` (new)
- Session continues in the decision skill
