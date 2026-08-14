---
schema: plan/v1
status: Draft
execution_mode: single-pr
upstream: docs/designs/DESIGN-execute-single-pr-blockers.md
milestone: "Execute single-pr blockers"
issue_count: 4
---

# PLAN: execute-single-pr-blockers

## Status

Draft

Implementation decomposition for
`docs/designs/DESIGN-execute-single-pr-blockers.md`. Four issues on one branch
and one PR, sequenced so the CI change lands only after the script it exercises
is fixed.

## Scope Summary

Two defects block `/execute`'s koto-driven single-pr path on a default macOS
host, and one CI workaround is the reason the second one shipped. The DESIGN
settled four mechanisms: the worktree-discipline gate resolves its plan slug
through a declared koto template variable rather than shell expansion;
`plan-to-tasks.sh` drops its nine post-bash-3.2 constructs for a string-backed
key/value store and positional arguments; the gate's expected path is named in
the directive prose, which is the only failure surface koto passes through; and
the guard against reintroduction is the existing test suite running on the
platform floor plus one grep over shipped templates.

The implementation contract is narrow. No new components, no runtime
dependency, and no change to `plan-to-tasks.sh` output for any plan. The
multi-pr and coordinated paths are untouched.

## Decomposition Strategy

Vertical, one issue per DESIGN decision, with D1 and D3 folded together and D4
split in two.

D1 (gate resolution) and D3 (diagnostic naming) both edit the same
`worktree_discipline_check` state in the same template, and D3's naming uses the
`{{PLAN_SLUG}}` reference D1 introduces. Splitting them would mean two passes
over one state for no reviewable benefit, so they are one issue.

D4 splits because its two halves share nothing. Removing CI's bash 5 install is
a workflow edit that depends on the script fix; adding the interpolation grep is
a new script that depends on the template fix. Keeping them separate lets each
land against a tree that already passes it.

The sequencing constraint that matters is Issue 3 after Issue 2: removing the
bash 5 install before the script is portable turns the macOS job red. The
sequencing constraint that does not matter is Issue 4 after Issue 1 — the check
would pass either way once Issue 1 lands, and the edge exists so a reviewer
reads the guard against a tree the guard covers.

## Issue Outlines

### Issue 1: fix(execute): resolve the worktree-discipline gate's plan slug through koto

**Goal**: Make the `impact_classified` gate test the same path the
worktree-discipline directive writes to, and make a future mistake in that
reference a koto compile error rather than a silent empty expansion.

**Acceptance Criteria**:

- `skills/execute/koto-templates/execute.md` declares `PLAN_SLUG` in its
  `variables:` block, marked required, with a description naming what it is
  derived from.
- The `worktree_discipline_check` gate command reads
  `test -f wip/work-on_{{PLAN_SLUG}}_impact.json`. No `${PLAN_SLUG}` remains in
  any gate or default-action command in the file.
- `skills/execute/SKILL.md` Step 2's `koto init` invocation passes
  `--var PLAN_SLUG=<plan-slug>` alongside the `PLAN_DOC` and
  `PAUSE_BEFORE_FINALIZE` it already passes, and the surrounding prose says the
  slug is the same one already derived for the session name.
- The `worktree_discipline_check` directive prose names the literal path the
  gate tests, written as `wip/work-on_{{PLAN_SLUG}}_impact.json` so koto
  substitutes the real slug into the text a blocked-gate response carries.
- A koto template compile of the edited template succeeds, and a deliberate
  typo in the reference (`{{PLAN_SLUGG}}`) fails it with a message naming the
  state.

**Dependencies**: None

**Type**: fix

**Files**: `skills/execute/koto-templates/execute.md` `skills/execute/SKILL.md`

### Issue 2: fix(plan): run plan-to-tasks.sh under bash 3.2

**Goal**: Remove every post-bash-3.2 construct from `plan-to-tasks.sh` without
moving its output, so the script runs under the bash macOS ships.

**Acceptance Criteria**:

- A helper block provides `kv_set`, `kv_get`, `kv_has`, `set_add`, `set_has`,
  and `set_items` over newline-delimited `key<TAB>value` string stores, using
  `${!name}` indirect expansion and `printf -v`. No `eval` is introduced.
- `kv_set` and `set_add` reject a key containing a tab or a newline, failing
  through `die_schema` rather than corrupting the store.
- All eight associative arrays (`slug_counts`, `number_to_name`,
  `file_first_owner`, `issue_to_node`, `is_gate`, `edges_set`, `seen`, `indeg`)
  use the helpers. No `declare -A` or `local -A` remains in the file.
- `array_to_json` takes its elements as positional arguments instead of a
  nameref, and all three call sites pass `${waits_on[@]+"${waits_on[@]}"}` so
  an empty array is safe under `set -u`. No `local -n` or `declare -n` remains.
- `bash skills/plan/scripts/plan-to-tasks_test.sh` passes under `/bin/bash` on
  macOS (bash 3.2.57) and under bash 5.
- For a representative single-pr plan, a representative multi-pr plan, and a
  plan exercising slug-collision suffixing, the script's stdout under bash 3.2
  is byte-identical to its stdout under bash 5 and to the pre-change output.
- `plan-to-tasks_test.sh` gains a case covering slug-collision suffixing if it
  does not already have one, since that path is where insertion order could
  have leaked into output.

**Dependencies**: None

**Type**: fix

**Files**: `skills/plan/scripts/plan-to-tasks.sh` `skills/plan/scripts/plan-to-tasks_test.sh`

### Issue 3: chore(ci): stop installing bash 5 on the macOS plan-scripts runner

**Goal**: Make the macOS leg of `check-plan-scripts.yml` exercise the platform
bash, so a reintroduced post-3.2 construct fails CI at the point of use.

**Acceptance Criteria**:

- The `Install bash 5 (macOS)` step and its explanatory comment are removed from
  `.github/workflows/check-plan-scripts.yml`.
- On the macOS leg, the test steps invoke `/bin/bash` explicitly rather than
  `bash`, so a Homebrew bash on the runner's PATH cannot restore the old
  behavior. The Linux leg is unchanged.
- The workflow passes on both legs against the tree produced by Issue 2.
- No other workflow installs a newer bash to work around this script.

**Dependencies**: Issue 2

**Type**: chore

**Files**: `.github/workflows/check-plan-scripts.yml`

### Issue 4: feat(ci): reject shell-style interpolation in koto-executed template fields

**Goal**: Catch reintroduction of the interpolation defect class, which has no
runtime detector in CI because nothing executes a template's gate strings there.

**Acceptance Criteria**:

- `scripts/check-template-interpolation.sh` walks `skills/*/koto-templates/*.md`,
  reads gate `command:` values and `default_action` command values, and exits
  non-zero when one contains `$NAME` or `${NAME}`, naming the file, the state,
  and the offending field.
- The script does not match `{{KEY}}` references, and does not read
  `context_assignments`, so koto's own `${evidence.<field>}` namespace is not
  flagged.
- The script only reads files. It does not source, evaluate, or execute template
  content.
- `scripts/check-template-interpolation_test.sh` covers: a clean template
  passing, a template with `${NAME}` in a gate command failing, a template with
  `$NAME` in a default-action command failing, and a template using
  `${evidence.detail}` in `context_assignments` passing.
- `.github/workflows/check-templates.yml` runs the check on pull requests
  touching `skills/*/koto-templates/**`, and both scripts follow the shape of
  the repo's existing `scripts/check-sentinel.sh` and its test companion.
- The check passes against the tree produced by Issue 1 and fails against a tree
  with the original `${PLAN_SLUG}` gate restored.

**Dependencies**: Issue 1

**Type**: feat

**Files**: `scripts/check-template-interpolation.sh` `scripts/check-template-interpolation_test.sh` `.github/workflows/check-templates.yml`

## Implementation Sequence

Two independent chains that can run in either order or in parallel.

**Chain A — the gate.** Open with Issue 1. It is self-contained, touches two
files, and its verification is a koto template compile. Issue 4 follows and adds
the guard that keeps the fix from being undone.

**Chain B — the script.** Issue 2 is the bulk of the work and the only issue in
the plan with real risk, because it rewrites nine call sites in a script whose
output feeds task names and the merge-order graph. Do it against the existing
test suite, and verify output stability by diffing the script's stdout for the
same plans before and after. Issue 3 is a three-line workflow edit that must not
land before Issue 2, or the macOS job fails on the unfixed script.

If the two chains are worked in sequence rather than in parallel, take Chain B
first: it carries the risk, and finding a problem there early leaves room to
reshape the approach before the guard work in Issue 4 assumes a settled tree.

## References

- `docs/designs/DESIGN-execute-single-pr-blockers.md` — the upstream DESIGN,
  whose four decisions map to these four issues.
- `docs/prds/PRD-execute-single-pr-blockers.md` — the requirements the
  acceptance criteria trace to.
- `scripts/check-sentinel.sh` — the shape Issue 4's check script follows.
