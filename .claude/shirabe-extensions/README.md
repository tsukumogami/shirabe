# shirabe-extensions

Project-specific `/work-on` configuration for the shirabe repo. The work-on skill imports
`work-on.md` here via `@.claude/shirabe-extensions/work-on.md`, so that file is pulled into
context on every `/work-on` run — keep it minimal. This README holds the rationale a reader
wants but the skill does not need loaded (it is **not** imported).

## `work-on.md` — the verification map

`work-on.md` declares shirabe's verification map per the schema in
[`skills/work-on/references/verification-map.md`](../../skills/work-on/references/verification-map.md).
At the definition-of-done gate, `/work-on` matches an issue's changed files against the map,
runs each matched entry's command(s), and requires every run to pass before the issue can
finalize. A change matching no entry falls through to the default; a change with no match and
no usable default yields cannot-verify and **fails closed** (never reads as "verified").

### Entries

- **`skills/** -> scripts/run-evals.sh <skill>`** — an issue that changes a skill must have
  that skill's evals **executed and passing**, not merely present. `<skill>` is the changed
  skill's directory name under `skills/`. This closes the `## Skill Evals` enforcement gap in
  `CLAUDE.md`: the existence check (`check-evals-exist.sh`) is not a substitute for running the
  evals.

- **Default** (no entry matches) — every one of `cargo test --workspace`,
  `skills/plan/scripts/plan-to-tasks_test.sh`, and `skills/work-on/scripts/run-cascade_test.sh`
  must pass.
