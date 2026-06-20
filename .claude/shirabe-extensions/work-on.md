# work-on extension: shirabe

Project-specific `/work-on` guidance for the shirabe repo. `/work-on` imports this file via
`@.claude/shirabe-extensions/work-on.md` and reads the verification map below at its
definition-of-done gate.

This file declares shirabe's verification map per the schema in
`skills/work-on/references/verification-map.md`. The gate matches an issue's changed files
against the map, runs each matched entry's command(s), and requires every run to pass before
the issue can finalize. A change matching no entry falls through to the default; a change with
no match and no usable default yields cannot-verify and fails closed.

## Verification map

- `skills/**` -> `scripts/run-evals.sh <skill>`

  An issue that changes a skill must have that skill's evals **executed and passing**, not
  merely present. `<skill>` is the changed skill's name (the directory under `skills/`). This
  closes the `## Skill Evals` enforcement gap in CLAUDE.md: the existence check
  (`check-evals-exist.sh`) is not a substitute for running the evals.

### Default verification command

When no map entry matches the changed files, run all of:

- `cargo test --workspace`
- `skills/plan/scripts/plan-to-tasks_test.sh`
- `skills/work-on/scripts/run-cascade_test.sh`

Every one must pass for the default to pass.
