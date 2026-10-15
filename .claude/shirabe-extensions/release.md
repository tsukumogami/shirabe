# release extension: shirabe

shirabe's declarations for `/shirabe:release`, imported by
`skills/release/SKILL.md`. Design: `docs/designs/current/DESIGN-evals-at-release.md`.

## Release checks

- `scripts/release-eval-check.sh --critical work-on,scope,execute --critical-runs 1 --model sonnet --tolerance 0.05`

## Release assets

- `scripts/release-eval-check.sh --finalize`

## About the eval check

The check runs the evals of every skill changed since the last release tag,
once each, with `EVAL_MODEL=sonnet`: the nested session that grades, and every
scenario that names no model of its own, run on Sonnet. It compares each
skill's pass rate with the newest earlier release whose `eval-pass-rates.json`
asset measured that skill the same way: on the same scenario models and
session model, over the same number of runs. It
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
default): it runs only the skills changed since their last scheduled run and
keeps each run's cost in a ledger the next run reads. Measurements and the
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
