# shirabe-extensions

Project-specific configuration for shirabe's own skills, run against the shirabe repo. Each
skill imports its file here (`@.claude/shirabe-extensions/<skill>.md`), so that file is pulled
into context on every run and stays minimal. This README holds the rationale a reader wants
but no skill needs loaded (it is **not** imported).

| File | Read by | Declares |
|------|---------|----------|
| `work-on.md` | `/work-on` | the verification map for the definition-of-done gate |
| `release.md` | `/shirabe:release` | the release checks and release assets, including the eval check |

## `work-on.md` — the verification map

`work-on.md` declares shirabe's verification map per the schema in
[`skills/work-on/references/verification-map.md`](../../skills/work-on/references/verification-map.md).
At the definition-of-done gate, `/work-on` matches an issue's changed files against the map,
runs each matched entry's command(s), and requires every run to pass before the issue can
finalize. A change matching no entry falls through to the default; a change with no match and
no usable default yields cannot-verify and **fails closed** (never reads as "verified").

### Entries

- **`skills/** -> scripts/check-skill.sh <skill>`** — run once per changed skill, where
  `<skill>` is the skill's directory name under `skills/`. For that skill it runs
  `shirabe validate` over its Markdown outside `evals/` and `koto-templates/`, compiles each
  `koto-templates/*.md` (skipping `*.mermaid.md`) with `koto template compile`, runs every
  `scripts/*_test.sh`, and checks the shape of `evals/evals.json` with
  `scripts/lib/check-evals-shape.py`: valid JSON, and every scenario with a `name`, a
  `prompt`, and a non-empty `expectations` or `assertions` list. A skill that declares
  `disable-model-invocation: true` may have no `evals.json`. It needs `shirabe`, `koto`,
  `python3` and `git`, and fails closed (exit 2) when one is missing. It never starts
  `claude`.

  It does not run the evals. A pull request that changes a skill writes or updates the
  scenarios in `evals/evals.json`; the scenarios run at release, through the eval check
  declared in [`release.md`](release.md), which compares each changed skill's pass rate with
  the previous release's. `scripts/run-evals.sh <skill>` is still there for an author who
  wants a local run.

- **Default** (no entry matches) — every one of `cargo test --workspace`,
  `skills/plan/scripts/plan-to-tasks_test.sh`, and `skills/work-on/scripts/run-cascade_test.sh`
  must pass.

## `release.md` — release checks and assets

`release.md` lists the commands `/shirabe:release` runs before it tags (`## Release checks`)
and after the draft release exists (`## Release assets`). shirabe's check is
`scripts/release-eval-check.sh`, which runs the evals of every skill changed since the last
tag and stops the release on a pass-rate drop until the maintainer confirms it. The file
itself says what the check needs on the release host.
