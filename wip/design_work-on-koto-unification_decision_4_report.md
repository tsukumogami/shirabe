<!-- decision:start id="review-panel-koto-integration" status="assumed" -->
### Decision: Review Panel Integration with Koto State Transitions

**Context**

The unified work-on workflow uses per-issue koto workflows for state management.
Review panels (3-agent scrutiny, 3-agent code review, QA validation) run between
implementation and PR creation. These panels are orchestrated in skill markdown --
koto gates can't express multi-agent coordination with feedback loops. The question
is how panel results connect to koto state transitions: through gates, evidence,
or both.

The existing work-on koto template combines gates with evidence in every non-trivial
state. States like `setup_issue_backed` use a `context-exists` gate to confirm an
artifact was produced, plus an evidence enum (`status: completed | override | blocked`)
for transition routing. This two-layer pattern separates structural guarantees (the
artifact exists) from control flow (what happened).

**Assumptions**

- Koto context files persist across session interrupts and are available on resume.
  If wrong, panel results would be lost, breaking both audit trails and auto-advance.
- New states can be inserted into the template between `implementation` and
  `finalization` without breaking existing workflows that don't traverse them.

**Chosen: Hybrid -- Context for Persistence, Evidence for Transitions**

Review panels write their aggregated results to koto context under conventional keys
(`scrutiny_results.json`, `review_results.json`, `qa_results.json`). New template
states (`scrutiny`, `review`, `qa_validation`) declare `context-exists` gates that
check for these keys. The skill layer runs panels within the state directive, writes
results to context, then calls `koto next` with an evidence enum encoding the outcome
(`review_outcome: passed | blocking_retry | blocking_escalate`).

The new states follow this shape:

```
scrutiny:
  gates:
    scrutiny_results:
      type: context-exists
      key: scrutiny_results.json
  accepts:
    scrutiny_outcome:
      type: enum
      values: [passed, blocking_retry, blocking_escalate]
  transitions:
    - target: review
      when: { scrutiny_outcome: passed }
    - target: implementation
      when: { scrutiny_outcome: blocking_retry }
    - target: done_blocked
      when: { scrutiny_outcome: blocking_escalate }
```

On first entry, the gate fails (no results yet). The directive tells the skill layer
to run the scrutiny panel, write results to context, then submit evidence. On resume
after interruption, the gate passes (results exist in context), and auto-advance
proceeds based on the previously recorded evidence.

The skill layer handles all panel complexity: spawning agents in parallel, collecting
structured results, evaluating blocking_count thresholds, assembling feedback for
rework loops, and re-spawning the implementing agent when blocking findings exist.
Koto's role is limited to state sequencing and resumability.

For feedback loops (blocking findings -> rework -> re-review), the skill layer
transitions back to `implementation` with `blocking_retry`, which re-enters the
implementation state. On completion, the agent transitions to `scrutiny` again,
where the gate will fail (stale results from the previous round). The skill layer
re-runs the panel with updated code, overwrites the context key, and submits fresh
evidence. This makes each review round produce a clean result set.

**Rationale**

The hybrid approach follows the established template convention where gates confirm
structural preconditions and evidence drives control flow. Every substantive state in
the current template already works this way. Using only gates (Alternative A) would
leave control flow underspecified -- the gate can confirm results exist but can't
route on blocking_count. Using only evidence (Alternative B) would sacrifice both
the audit trail (koto context persists; wip/ files are cleaned pre-merge) and
auto-advance resumability (the skill layer would need its own completion detection).
The hybrid costs one additional write per panel (context set), which is minimal
compared to the cost of running three agents.

**Alternatives Considered**

- **Context-Exists Gates as Checkpoints (A)**: Gates check result existence but can't
  evaluate content. The skill layer would still need evidence for routing, so the gate
  becomes redundant ceremony without the evidence layer. Rejected because it achieves
  persistence but not control flow.

- **Direct Evidence Submission (B)**: No gates, no context writes. Simpler, but panel
  results live only in wip/ files that are deleted before merge. Resume requires the
  skill layer to detect prior panel completion by checking wip/ -- fragile and
  duplicates what koto context already provides. Rejected because it loses the audit
  trail and clean resume semantics.

**Consequences**

New states (`scrutiny`, `review`, `qa_validation`) are added to the work-on koto
template between `implementation` and `finalization`. The state count grows from 17
to 20, but each new state follows the same gate-plus-evidence pattern as existing
states.

Panel results persist in koto context beyond wip/ cleanup, providing an audit trail
of review outcomes per issue. This also means the context store grows with each
reviewed issue in multi-issue plans -- bounded by the number of issues, not the
number of review rounds (results are overwritten on re-review).

The skill layer's panel orchestration code doesn't change structurally. It still
spawns agents, collects results, and decides the outcome. The only addition is a
`koto context set` call before `koto next` -- a single line of integration per panel
type.

Koto's override system applies to the new gates. If a user wants to skip scrutiny
(e.g., trivial documentation fix), they can override the `scrutiny_results` gate
with a rationale. This gives review skipping a formal mechanism with an audit trail,
replacing ad-hoc skip logic in the skill layer.
<!-- decision:end -->
