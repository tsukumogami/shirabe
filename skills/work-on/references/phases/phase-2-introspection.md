# Introspection

Re-read the issue against the current codebase to check whether the original
approach is still valid.

## Steps

Check for:
- Requirements partially or fully addressed by other changes
- Assumptions in the issue that no longer hold
- New constraints or dependencies introduced since filing
- Whether the issue has been superseded

Write findings to `wip/issue_{{ISSUE_NUMBER}}_introspection.md`.

## Evidence

- `introspection_outcome: approach_unchanged` — original approach still valid
- `introspection_outcome: approach_updated` — adjustments needed (describe in rationale)
- `introspection_outcome: issue_superseded` — issue no longer relevant
