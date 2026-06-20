# work-on extension: shirabe

shirabe's `/work-on` verification map (read by the definition-of-done gate). Schema:
`skills/work-on/references/verification-map.md`. Rationale: `README.md` in this directory.
This file is `@`-imported by the work-on skill, so it stays minimal.

## Verification map

- `skills/**` -> `scripts/run-evals.sh <skill>`

### Default verification command (when no map entry matches; all must pass)

- `cargo test --workspace`
- `skills/plan/scripts/plan-to-tasks_test.sh`
- `skills/work-on/scripts/run-cascade_test.sh`
