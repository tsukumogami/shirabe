# release extension: shirabe

shirabe's declarations for `/shirabe:release`, imported by
`skills/release/SKILL.md`. Designs: `docs/designs/DESIGN-skill-regression-detection.md` for the eval check, and `docs/designs/current/DESIGN-evals-at-release.md` for the release-checks hook.

## Release checks

- `scripts/release-eval-check.sh`

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

The check runs every skill's `grader: script` cases once, through
`scripts/lib/script-cases.py --all`. Every skill that keeps an
`evals/evals.json` runs, not only the skills changed since the last release
tag: the cases cost seconds, and a change to a shared file or to a hand-off target can break
a skill whose own files didn't change. No model-graded case runs. Those
scenarios stay in each skill's `evals.json`, where they describe its
behaviour, and nothing runs them. The runner's output passes through, and the
check then prints the two lines the release notes carry, along with the names
of any skills a person confirmed:

```text
script cases: <P> of <N> passed
model-graded cases: not run
```

Each failing case is labelled against the skill's newest script-measured
record, read from the `eval-pass-rates.json` asset of the last tag's release
and up to nine releases before it. It's `regressed` when the case passed there
or the skill's pass rate fell below that record's, `still failing` when the
case failed there too, and `failing, no baseline` when the case is new or no
earlier release measured the skill this way. The baseline picks the label and
never the exit. Any failing case exits 5, whatever its label, with the output
ending in a `confirm: RELEASE_CONFIRMED_DROPS=<a,b>` line that names every
skill with one, and the check keeps exiting 5 until `RELEASE_CONFIRMED_DROPS`
names them all. The re-run after a person confirms compares the saved results
again and runs no case. When koto is missing, the runner can't run or a
download fails, the check exits 1 with a message ending `run the check again`.

The `--finalize` item stamps the record with the confirmed version and names
it for upload as the release asset `eval-pass-rates.json`. If that command or
its upload fails, the next release falls back to older records, and the skills
this release measured have no baseline newer than those: retry the upload
before the release is published.

The release host needs `koto`, which the hand-off cases attach sessions with,
`python3`, `git` and `gh`. The check runs under macOS's `/bin/bash` 3.2 and
calls no model. It prints the host it runs on before any case runs.
