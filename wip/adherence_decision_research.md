# Decision Research: skill-adherence mechanism

## Source

This decision inherits the research from round 1 of the parent exploration rather
than re-running it. Six lead files under `wip/research/`:

| Lead | Answers |
|------|---------|
| `lead-slash-command-resolution` | Bare `/execute` resolves; discoverability theory dead; silent-success failure mode |
| `lead-skill-firing-mechanics` | Competence filter; description ceiling; eval-suite blindness |
| `lead-mandatory-workflow-prior-art` | Shirabe's doctrine, the deferred dispatch gap, pattern-by-pattern assessment |
| `lead-niwa-distribution-surface` | Distribution solved; `[claude.skills]` sketch; overlay placement tension |
| `lead-dispatch-prompt-construction` | `dispatch.go:421`; brief-template gap; unused instance SessionStart channel |
| `lead-koto-observability` | The gate predicate is computable; `koto overrides` exists |

Synthesized in `wip/explore_skill-adherence-enforcement_findings.md`. Incident
record in `wip/explore_skill-adherence-enforcement_evidence.md`.

## Critical unknowns and their status

| Unknown | Status |
|---------|--------|
| Is the gate condition computable without agent cooperation? | **Resolved: yes.** One grep over `~/.koto/sessions/*/koto-*.state.jsonl` for a bound `PLAN_DOC`. Verified live against 32 sessions; returns nothing for incident 2's plan. |
| Is invocation a sufficient unit of measurement? | **Resolved: no.** Incident 2 ran the skill's scripts and produced a valid payload. Only the durable session discriminates. |
| Can niwa distribute an arbitrary gate as workspace policy? | **Resolved: yes, already does.** `shirabe pr-body-hook` is a shipped, niwa-injected PreToolUse allow/deny gate. |
| Can a mandate reach a dispatched worker? | **Resolved: yes.** `dispatch.go:421` prefix, no size budget, prefix-first ordering test-pinned. |
| Do hooks fire for subagents? Does SessionStart reach a `--bg` worker? | **Open.** Delegated; two attempts died on usage limits, a third is running. Bears on Alternative 1's coverage and on whether the gate needs a second surface. Does **not** change the ranking of the alternatives, because the gate predicate is evaluated in the main session's tool calls either way. |
| How does a hook learn *which* plan is in play? | **Open.** The grep answers "is there a session for plan X"; something upstream must supply X. Candidates: branch name, `wip/` state file, PR body, prompt text. This is an implementation gap inside Alternative 3, not a threat to it. |

## The disqualifying test carried into the bakeoff

In both incidents the agent could name the correct path when asked. **Any
mechanism whose only effect is to supply knowledge cannot fix a failure whose
cause is not missing knowledge.** Validators must apply this test explicitly
rather than scoring alternatives on plausibility.
