---
complexity: simple
complexity_rationale: Single-file rewrite or split, scoped change to existing reference docs.
---

## Goal

Rewrite `skills/work-on/references/agent-instructions/phase-3-analysis.md`
so it reads naturally for both consumers — the main agent (simplified
plans, inline) and a freshly-spawned subagent (full plans, delegated)
— now that the parent PR introduced the inline path.

## Context

Commit `5502ce2` ("feat(work-on): make subagent delegation opt-out for
simplified plans") split phase 3 into two branches: full-plan delegates
to a subagent, simplified-plan writes the plan inline in the main
agent. Both consumers read the same reference file
(`agent-instructions/phase-3-analysis.md`), but its current framing
("You are executing Phase 3 (Analysis) of the `/work-on` workflow…
You will receive: …") implicitly addresses a fresh subagent.

When the main agent reads it for an inline simplified plan, the "you
will receive" framing reads as if it's about to consume context that's
actually already in its conversation. Mildly confusing today; will
become more so as more of phase 3 evolves.

Options to evaluate:
- (a) Split into two files:
  `phase-3-fullplan-agent.md` (subagent-targeted, current framing) +
  `phase-3-simplified-inline.md` (main-agent-targeted, drop the
  context-acquisition framing)
- (b) Rewrite the single file in agent-neutral voice, with a short
  "Inline path" / "Delegated path" header at the top that the reader
  uses to pick the right subsection

## Acceptance Criteria

- [ ] The chosen option is implemented (single rewrite or split)
- [ ] Main-agent inline consumption reads cleanly (no "you will
  receive" of content the main agent wrote itself)
- [ ] Subagent delegated consumption reads cleanly
- [ ] `phase-3-analysis.md` (the phase reference) links to whatever
  shape the chosen option produces
- [ ] Tests pass (run project's test command)
- [ ] CI green

## Dependencies

None

## Downstream Dependencies

None
