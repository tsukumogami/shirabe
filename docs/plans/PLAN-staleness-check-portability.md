---
schema: plan/v1
status: Active
execution_mode: single-pr
split_mode_source: none
tracking_level: none
upstream: docs/designs/DESIGN-staleness-check-portability.md
milestone: "Staleness check portability"
issue_count: 2
---

# PLAN: staleness-check portability

## Status

Active

Authored at Active: tracking level `none` files no GitHub issues, so
activation needs no approval. Both outlines land in one pull request.

## Scope Summary

Port the staleness check into shirabe and rewire `/work-on`'s
`staleness_check` gate to it, with a gate-conditioned `unavailable` outcome
for hosts where the check can't run, as the upstream DESIGN specifies.

## Decomposition Strategy

**Horizontal, two layers.** The script has a stable interface (the
`--issue <N>` argument and the 0/1/3/2 exit statuses) that the gate consumes
and nothing else does, so the script lands first with its own tests and the
template change builds on it. A walking skeleton buys nothing here: there is
one runtime seam, and the gate cases in the second outline exercise it.

The work doesn't split. Neither outline is useful alone (a script nothing
calls, or a gate pointing at a script that doesn't exist), no hard
constraint separates them, and the repository declares no `atomic`
preference, so it lands as one pull request.

## Issue Outlines

### Issue 1: feat(work-on): port the staleness check into shirabe

**Complexity**: testable

**Goal**: Add `skills/work-on/scripts/check-staleness.sh`, the signals
reference `skills/work-on/references/staleness-signals.md`, and
`skills/work-on/scripts/check-staleness_test.sh`, as the DESIGN's Solution
Architecture describes: `--issue <N>` only, exit 0 fresh, 1 stale, 3
unavailable, 2 usage, JSON report on stdout, bash 3.2 compatible, no
`set -e`, at most three `gh` calls.

**Acceptance Criteria**:
- [ ] A fresh issue (created today, no milestone, no file references) exits
  0 with `"verdict": "fresh"`.
- [ ] Each signal alone exits 1: age over 14 days; one milestone sibling
  closed after creation; position `middle` and position `last`; a referenced
  file with a commit after creation.
- [ ] `gh` failing on the issue call, and on either milestone call, exits 3;
  a `PATH` without `jq` exits 3; a `git log` failure on a referenced file
  exits 3.
- [ ] A bare positional number, a missing `--issue`, and a non-integer value
  exit 2 and print nothing on stdout.
- [ ] Every verdict's JSON carries `verdict`, `introspection_recommended`,
  each signal, `age_threshold_days`, and `reason`.
- [ ] A stub counter shows at most three `gh` calls per run.
- [ ] Referenced paths that are absolute or contain `..` are never passed to
  `git log`.
- [ ] A token-shaped string in `gh`'s stderr does not reach the report.
- [ ] `staleness-signals.md` lists each signal and threshold, the exit
  statuses, and the table of differences from the prior check.
- [ ] The suite passes under `scripts/check-bash-floor.sh --backend system
  work-on` locally where available, and is registered in that runner and in
  `.github/workflows/check-work-on-scripts.yml`.
- [ ] `scripts/check-skill-requires.sh` passes (the script calls only `gh`,
  `jq`, `git` and POSIX utilities).

**Dependencies**: None

### Issue 2: fix(work-on): run the staleness gate against shirabe's own check

**Complexity**: critical

**Goal**: Rewire `staleness_check` in
`skills/work-on/koto-templates/work-on.md` to the ported script through
`{{PLUGIN_ROOT}}`, add the `unavailable` evidence value with its two
gate-conditioned edges (exit 3 and -1), remove the trailing unconditional
edge, rewrite the state's directive, update the `PLUGIN_ROOT` description,
regenerate the mermaid companion, and extend the test suite with gate and
engine cases.

**Acceptance Criteria**:
- [ ] The gate command, extracted from the template and run with `sh -c` as
  koto would, exits 0 on a fresh issue, 1 on a stale one, and 3 when
  `PLUGIN_ROOT` is empty.
- [ ] With a `check-staleness.sh` that rejects `--issue` first on `PATH`, the
  extracted gate still exits 0 on a fresh issue.
- [ ] Driven through koto (skipped where koto is absent): `unavailable`
  advances to `analysis` on exit 3 and -1 and stays in `staleness_check` on 0,
  1 and 2; `fresh` advances on 0 and stays on 1 and 3;
  `stale_requires_introspection` reaches `introspection`; `override` reaches
  `analysis` and `blocked` reaches `done_blocked` on any exit code, 2
  included.
- [ ] The directive maps each exit status to its evidence value, names all
  five values with the case each is for, gives the re-run command in the
  `${CLAUDE_PLUGIN_ROOT}` form, and no longer claims the state auto-advances.
- [ ] `koto template compile` succeeds; `validate-template-mermaid.sh`,
  `check-template-interpolation.sh` and `check-template-directives.sh` pass on
  the edited template; the mermaid companion shows the new edges and no
  trailing unconditional edge out of `staleness_check`.
- [ ] The existing work-on script suites pass.
- [ ] No committed text names a private repository, path, or plugin.

**Dependencies**: Issue 1

## Implementation Sequence

Issue 1, then Issue 2, on one branch and one pull request. Issue 1's script
cases can be written and run before the template changes; Issue 2's gate and
engine cases are added to the same test file once the template edit lands.
There's no parallel work: the critical path is both outlines in order.
