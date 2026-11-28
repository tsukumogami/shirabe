# Introspection

Re-read the issue against the current codebase to check whether the original
approach is still valid.

## Steps

Check for:
- Requirements partially or fully addressed by other changes
- Assumptions in the issue that no longer hold
- New constraints or dependencies introduced since filing
- Whether the issue has been superseded

Store the findings in koto context under `introspection.md`, by stdin pipe or a
`mktemp` file deleted after ingestion (see `../koto-context-conventions.md`).

## Evidence

- `approach_unchanged` — original approach still valid
- `approach_updated` — adjustments needed
- `issue_superseded` — issue no longer relevant

`issue_superseded` doesn't end the run on its own: it goes to `decide_first`,
which lets the run stop at `done_blocked` only once an attempt to decide is
recorded for the arrival, or raise a question and wait on its answer. The
directive there names the commands to run.
