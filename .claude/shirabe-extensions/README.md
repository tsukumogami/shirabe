# shirabe-extensions

Project-specific configuration for shirabe's own skills, run against the shirabe repo. Each
skill imports its file here (`@.claude/shirabe-extensions/<skill>.md`), so that file is pulled
into context on every run and stays minimal. This README holds the rationale a reader wants
but no skill needs loaded (it is **not** imported).

| File | Read by | Declares |
|------|---------|----------|
| `work-on.md` | `/work-on` | where the verification map lives (imported, minimal) |
| `verification-map.json` | `/work-on` | the verification map for the definition-of-done gate |
| `release.md` | `/shirabe:release` | the release checks and release assets, including the eval check |

## `verification-map.json` — the verification map

`verification-map.json` declares shirabe's verification map per the
`shirabe-verification-map/v1` schema in
[`skills/work-on/references/verification-map.md`](../../skills/work-on/references/verification-map.md);
`work-on.md` only points at it. The gate reads the copy at the merge-base with `main`, so a
branch that edits the map is verified by the map it started from. At the definition-of-done
gate, `/work-on` matches an issue's changed files against the map, runs each matched entry's
command(s), and requires every run to pass before the issue can finalize. A change matching no
entry falls through to the default; a change the map selects nothing for yields cannot-verify
and **fails closed** (never reads as "verified").

### Entries

- **`skills/**` -> `check-skill`** — `scripts/check-skill.sh` with `"each": "skills/*"`, so it
  runs once per changed skill with the skill's directory name under `skills/` as its argument. For that skill it runs
  `shirabe validate` over its Markdown outside `evals/` and `koto-templates/`, compiles each
  `koto-templates/*.md` (skipping `*.mermaid.md`) with `koto template compile`, runs every
  `scripts/*_test.sh`, and checks the shape of `evals/evals.json` with
  `scripts/lib/check-evals-shape.py`: valid JSON, and every scenario with a `name`, a
  `prompt`, and a non-empty `expectations` or `assertions` list. A skill that declares
  `disable-model-invocation: true` may have no `evals.json`. It needs `shirabe`, `koto`,
  `python3` and `git`, and fails closed (exit 2) when one is missing. It never starts
  `claude`.

  The gate runs it as `scripts/check-skill.sh --changed <skill>`, which runs only the suites
  the branch's changes touch, as described in the next section. Every other check runs in
  full.

  It does not run the evals. A pull request that changes a skill writes or updates the
  scenarios in `evals/evals.json`; the scenarios run at release, through the eval check
  declared in [`release.md`](release.md), which compares each changed skill's pass rate with
  the previous release's. `scripts/run-evals.sh <skill>` is still there for an author who
  wants a local run.

- **Default** (no entry matches) — every one of `cargo test --workspace` (with a 1200-second
  deadline), `skills/plan/scripts/plan-to-tasks_test.sh`, and
  `skills/work-on/scripts/run-cascade_test.sh` must pass.

### `--changed`: the suites a change touches

A skill opts in with a `check-skill.tsv` beside its `SKILL.md`; a skill without one runs
every suite under `--changed` too, short of a change only to `evals/` (below).
`skills/coordinate/check-skill.tsv` is the only one today. For an opted-in skill, `--changed` diffs the branch against its merge-base with the
default branch, the gate's own base, and classifies each changed path:

- a suite (`scripts/<name>_test.sh`) runs itself;
- a script under `scripts/` that is neither shared nor deleted runs its own
  `<stem>_test.sh` and the unit suites that name it or one of its direct callers, the
  skill's other scripts that name it. Engine suites (`*_engine_test.sh`) run only when no
  unit suite names any of them, so a script that only an engine suite tests still gets
  tested;
- a path under any skill's `evals/` runs the suites that can read it: those that name
  `evals`, directly or through a helper under the skill's `scripts/` that names it or
  names such a helper (two levels), and those that walk the tree (`find`, `ls -R`,
  `cp -r`, `grep -r` or `--recursive`, `git grep`, `git ls-files`, `rg`). The eval harness
  is what reads `evals/`, so a change to it alone runs few suites or none. This holds for
  a skill without `check-skill.tsv` too, when every changed path is under an `evals/`.
  Not "no suite", as one might expect: some suites run the eval shims under
  `evals/fixtures/` or read `evals.json`. Unlike the rules for scripts, a miss here
  can't fall back to every suite, so a suite that reaches `evals/` another way (a third
  helper in a chain, a path built at run time) isn't run locally; CI still runs it;
- everything else runs every suite: a shared script, anything under a subdirectory of
  `scripts/` (testdata and the test libraries), a koto template, the skill's Markdown and
  data files, `check-skill.tsv` itself, a deleted file, and any other path outside the
  skill, `scripts/check-skill.sh` included. So do a change with no merge-base and a
  branch with no changes. Markdown and data files run everything because suites read them
  by glob as well as by name (`references/`, `SKILL.md`, `requires.tsv`), which name
  matching can't see.

Callers are followed one level only. A suite that reaches a changed script only through
two scripts in a row, or an engine suite that drives the script while a unit suite names
it, isn't run locally. That's the one place a selection can miss a suite that would fail.
Followed further, callers reach 45 of coordinate's 77 suites from almost any script, so
the gate would gain nothing, and CI runs every suite before merge.

A script is shared when two or more of the skill's files source it, which the script works
out on each run, or when `check-skill.tsv` names it on a `shared` row. The rows hold what
sourcing can't show. For coordinate, that's the template's own scripts (`coord-verdict.sh`,
`coord-log.sh`, `coordinate-open.sh` and its wording table), which every engine suite drives,
and the record's schema (`state-schema.jq`).

`check-skill.tsv`'s `cost` rows give each suite's measured CPU seconds. With or without
`--changed`, suites launch costliest first, so a long suite doesn't start last and set the
tail. Results still print in the glob's order. `scripts/check-skill.sh --changed --list
<skill>` prints what a branch would run, and why, without running it.

CI never uses `--changed`. Each skill's workflow runs every suite on every pull request
that touches it, so whatever the selection misses, CI still catches before merge.

Keeping `check-skill.tsv` current:

- Add a `shared` row when a script becomes one that many others reach without sourcing it:
  a script the template or another skill's code drives directly, or a jq module. A script
  two files source is shared without a row.
- Add a `cost` row for a new suite, and re-measure the rows when a suite's cost changes
  much. A suite with no row launches last, which costs time but never correctness;
  `scripts/check-cost-rows.sh` fails when a skill's rows and suites differ. The
  `check-cost-rows.yml` workflow runs it on every pull request that adds or removes a
  skill suite or edits a `check-skill.tsv`, and `scripts/check-skill_test.sh` runs it
  for coordinate on the macOS floor.
- A skill opts in by adding the file. Until it has one, its suites have never been
  classified, so `--changed` runs them all.
- A suite that drives a script only through a variable, never by name, can't be found by
  name. Name the script in the suite, a comment is enough, or make the script shared.

### Coordinate engine suites on the floor koto

The entry-floor job runs coordinate's engine suites against the oldest koto shirabe
supports, which has no `koto init --continues` or `--supersede`, and `run-tests.sh --engine`
fails a suite that prints a SKIP line. A suite with a case that needs those flags sources
`skills/coordinate/scripts/testdata/takeover-flags.sh` after its `koto-test-guard.sh` line
and declares the case in one line, `if needs_takeover "<case>"; then ... fi`. On the floor
koto the case is left out with a line naming it; on a newer koto it runs. The helper's header
has the rest; the takeover, outcome, takeover-load, chain and newest-member suites use it.

## `release.md` — release checks and assets

`release.md` lists the commands `/shirabe:release` runs before it tags (`## Release checks`)
and after the draft release exists (`## Release assets`). shirabe's check is
`scripts/release-eval-check.sh`, which runs the evals of every skill changed since the last
tag and stops the release on a pass-rate drop until the maintainer confirms it. The file
itself says what the check needs on the release host.
