# Phase 5: Decision Record Handoff

When crystallize selects "Decision Record", write a decision brief and hand
off to the decision skill. This replaces the former inline ADR production.

## Decision Brief

Write the brief as key `work/decision-brief.md` in `explore-<topic>`: assemble
it in a scratch directory, put it, and remove the directory.

```bash
dir=$("${CLAUDE_PLUGIN_ROOT}/scripts/skill-session.sh" scratch)
# write the brief to "$dir/decision-brief.md", then:
"${CLAUDE_PLUGIN_ROOT}/scripts/skill-session.sh" put explore-<topic> work/decision-brief.md "$dir/decision-brief.md"
rm -rf "$dir"
```

The brief's content:

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
<The research keys the decision skill should read for detail, each as a
`koto context get explore-<topic> research/<name>` read.>

## Complexity Signal
<Simple (2 clear options, evidence strongly favors one) or
Complex (3+ options, trade-offs genuinely contested, stakeholders disagree)>
```

## Handoff

After putting the brief:

1. Read the decision skill: `skills/decision/SKILL.md`
2. Invoke the decision skill as a direct run on `<topic>`, with the brief as
   input context. It opens and closes its own session, `decision-<topic>`
   (see the skill's Session and Keys):
   - question: from the Decision Question section
   - options: from Known Options (if any)
   - constraints: from Constraints
   - background: from Context
   - complexity: from Complexity Signal ("simple" → standard, "complex" → critical)
3. The decision skill runs its phases and writes its report as key
   `work/report.md` in `decision-<topic>` (`koto context get decision-<topic>
   work/report.md` reads it)
4. The report serves as the Decision Record (ADR)
5. When the decision skill returns, close the session. It reads the research
   keys while it runs, so the close comes only after it returns:

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/skill-session.sh" close explore-<topic> done
```

## Escalation from Lightweight

If explore was running the lightweight protocol and escalated (status="escalated"),
the partial decision block's Question and Evidence become the brief's Decision
Question and Context sections. No information is lost.

## Artifact State

After this step:
- Key `work/decision-brief.md` in `explore-<topic>` (new)
- The decision skill's report at `work/report.md` in `decision-<topic>`
- Session `explore-<topic>` closed after the decision skill returned; its keys
  stay readable
