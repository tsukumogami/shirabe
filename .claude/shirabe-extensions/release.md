# release extension: shirabe

shirabe's declarations for `/shirabe:release`, imported by
`skills/release/SKILL.md`. Design: `docs/designs/current/DESIGN-evals-at-release.md`.

## Release checks

- `scripts/release-eval-check.sh --critical work-on,scope,execute --critical-runs 1 --model sonnet --tolerance 0.05`

## Release assets

- `scripts/release-eval-check.sh --finalize`

## After release

Run in order once the release is published. The version check stops the
list before `niwa apply` when the update didn't land the new binary (tsuku
hasn't seen the release yet, say), so a workspace is never re-applied with the
old one; `niwa apply` also moves the workspace's Claude plugins to the new
release.

- `tsuku update shirabe`: update the installed shirabe to the newest release.
  An `@v<version>` install would pin the recipe source's ref, leaving a second
  or pinned install that later updates skip.
- `test "$(shirabe --version)" = "shirabe v$RELEASE_VERSION"`: fail unless the
  binary on PATH reports the released version.
- `cd "${RELEASE_WORKSPACE_ROOT:?not in a niwa workspace}" && niwa apply`:
  re-apply every instance of the workspace this repository is in.

## The macOS floor run

Pull requests merge without waiting for their macOS legs, so a commit on
main may never have run every suite on the bash 3.2 floor. When a pull
request merges or closes, `cancel-closed-pr-macos-runs.yml` cancels its
macOS floor runs that are still queued or running, so a merged change's
own macOS result is often never reported. The `macos-floor.yml` run is the
only macOS check after merge.

Before dispatching the release workflow, run every floor suite on the
commit the release is cut from and wait for the result:

```bash
git fetch origin main
sha=$(git rev-parse origin/main)
gh workflow run macos-floor.yml -f ref="$sha"
# The run is named after its ref; repeat until this prints an id.
gh run list --workflow macos-floor.yml --event workflow_dispatch --json databaseId,displayTitle \
  --jq ".[] | select(.displayTitle == \"macOS floor on $sha\") | .databaseId"
gh run watch <databaseId> --exit-status
```

A red run stops the release; nothing enforces that but this step. The run
files an issue titled "CI: the macOS floor run is red", or comments on the
open one, naming the suites that failed; the release waits until a run on the
new main commit is green. The same workflow
runs on main every day, so its latest scheduled run says whether the floor was
already red before the release started. When no run named "macOS floor on
main" (the scheduled run, or a dispatch with `ref=main`) has finished green or
red for 36 hours, `macos-floor-watchdog.yml` files an issue titled "CI: the
macOS floor run is missing" and dispatches one; an open one means the floor's
state on main is unknown. A release run on a commit doesn't close it.

## About the eval check

The check runs the evals of every skill changed since the last release tag,
once each, with `EVAL_MODEL=sonnet`: the nested session that grades, and every
scenario that names no model of its own, run on Sonnet. Of a skill's
scenarios it runs the release subset: every tier-1 scenario and, of the
tier-2 ones, the one per behaviour that `evals.json` marks `"release": true`.
It runs the with-skill agent only, with no no-skill baseline: the release
decision reads with-skill rates, and the baseline, which measures what the
skill adds, stays with the scheduled runs. It compares each
skill's pass rate with the newest earlier release whose `eval-pass-rates.json`
asset measured that skill the same way: the same scenarios, on the same
scenario models and session model, over the same number of runs. A scenario
added to the release subset, or one that leaves it, starts a new reference
rather than reading as a drop. Measurements recorded before shirabe#879 carry
no scenario set, so the first release after it starts a new reference for
every skill it runs. It
reads the asset from the last tag and up to nine releases before it, so a
release that measured only some skills still leaves a baseline for the rest. A
skill that hasn't changed since the last tag doesn't run, the critical ones
(work-on, scope, execute) included.

A skill with no earlier measurement taken the same way (every skill, the first
time the check runs on Sonnet) gets a new reference: its rate is recorded and
printed as one, never compared with a rate measured on other models. From then
on a drop is a rate more than five points (0.05) below that reference, the
noise a single run showed on an unchanged skill. A drop exits 5 and asks for
confirmation; a harness or setup failure exits 1 and stops the release.

A single run is one sample. The repeat runs that measure how much a skill's
rate moves between runs are made off the release path, by
`scripts/scheduled-evals.py` on a schedule, within a weekly budget ($50 by
default). It repeats the release subset of each skill changed since its last
scheduled run, and rotates through the tier-2 scenarios outside the subset, up
to `--rotation-size` (3 by default) per skill per run, never-run first, then
the longest since run. Repeats and rotations share one queue, longest-waiting
first. A scenario is due again once the skill's tree changes, so on a skill
that changes faster than a pass the rotation lags the tree; the order keeps
any scenario from being skipped for good. Each run's cost goes in a ledger
the next run reads. Measurements and the
cost figures behind this check: `docs/spikes/SPIKE-release-eval-cost.md`.

The `--finalize` item stamps the record with the confirmed version and names
it for upload as the release asset `eval-pass-rates.json`. If that command or
its upload fails, the next release falls back to older records, and the skills
this release measured have no baseline newer than those: retry the upload
before the release is published.

The release host needs `claude` with the skill-creator plugin, `python3`,
`git`, `gh`, and bash 4 or later, since the eval harness doesn't run on
macOS's bash 3.2. The nested eval sessions can reach that host's stored
credentials; the check prints the host it runs on and says so before any eval
runs.
