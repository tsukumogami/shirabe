# Consolidated Decisions File Format

Each workflow invocation creates one `wip/<workflow>_<topic>_decisions.md` file
that indexes all decisions and tracks assumptions. This is the source of truth
for the review surface (terminal summary, PR body).

Inline decision blocks in wip/ artifacts are write-time snapshots. On
assumption invalidation, only the consolidated file is updated.

## File Structure

```markdown
# Decisions: <workflow> <topic>

## Index

| ID | Artifact | Tier | Status | Priority | Question |
|----|----------|------|--------|----------|----------|
| decomp-strategy | wip/plan_foo_decomposition.md | 2 | confirmed | -- | Walking skeleton vs horizontal |
| exec-mode | wip/plan_foo_decomposition.md | 2 | assumed | low | Single-pr vs multi-pr |
| cache-approach | wip/design_foo_decision_2_report.md | 3 | assumed | high | Cache invalidation strategy |

## Assumptions

### A1: exec-mode (low priority)

**Decision:** Execution mode: single-pr
**Evidence:** 5 issues, all in one repo, no merge gates. Signal tally: 3 single-pr vs 1 multi-pr.
**If wrong:** Re-run /plan with --multi-pr to convert issue outlines to GitHub issues.

### A2: cache-approach (high priority)

**Decision:** Cache invalidation: TTL-based
**Evidence:** Heuristic was close (60/40 TTL vs event-driven). TTL chosen for operational simplicity.
**If wrong:** Re-invoke decision skill for this question with the correction as a constraint. Check cascade: exec-mode assumes low complexity which may change.
```

## Index Table Columns

| Column | Required | Description |
|--------|----------|-------------|
| ID | Yes | The `id` from the decision block's delimiter |
| Artifact | Yes | Path to the wip/ file containing the inline block |
| Tier | Yes | 1-4 (from manifest pre-classification or checklist) |
| Status | Yes | confirmed, assumed, or escalated |
| Priority | For assumed | high or low; `--` for confirmed decisions |
| Question | Yes | Abbreviated form of the decision question |

## Assumption Detail Entries

Each `status="assumed"` decision gets a detailed entry below the index.
Entries are numbered sequentially (A1, A2, ...) for easy reference in
the terminal summary and during invalidation.

### Required fields per entry

| Field | Purpose |
|-------|---------|
| Decision | What was chosen (one line) |
| Evidence | What informed the choice and why it's uncertain |
| If wrong | Concrete restart path: which phase, what constraint to add, what cascade to check |

### Priority assignment

| Priority | When | Surfaces in |
|----------|------|-------------|
| high | Approval gates, contested judgment calls (heuristic close or contradicting evidence) | Terminal summary + PR body |
| low | Clear heuristic wins categorized as assumed only because they're judgment calls | Decisions file only |

## Lifecycle

1. **Created** when the first decision block is written during workflow execution
2. **Appended** after each subsequent decision block
3. **Read** by the terminal summary printer at workflow end
4. **Read** by the PR body section generator
5. **Updated** if an assumption is invalidated (entry removed or replaced)
6. **Deleted** during wip/ cleanup before merge

## Relationship to Other Files

| File | Purpose | Relationship |
|------|---------|-------------|
| Inline decision blocks | Per-artifact records | Snapshots; this file is authoritative |
| `coordination.json` | Agent orchestration state (design skill only) | Machine state; this file is human-readable |
| Terminal summary | End-of-workflow display | Read-only view of high-priority entries |
| PR body section | Reviewer-facing assumptions | Read-only view of high-priority entries |
