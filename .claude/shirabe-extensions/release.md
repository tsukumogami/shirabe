# release extension: shirabe

shirabe's declarations for `/shirabe:release`, imported by
`skills/release/SKILL.md`. Design: `docs/designs/current/DESIGN-evals-at-release.md`.

## Release checks

- `scripts/release-eval-check.sh --critical work-on,scope,execute --critical-runs 3`

## Release assets

- `scripts/release-eval-check.sh --finalize`

## About the eval check

The check runs the evals of every skill changed since the last release tag and
compares each one's pass rate with the previous release's
`eval-pass-rates.json` asset. A skill that hasn't changed since the last tag
doesn't run, the critical ones (work-on, scope, execute) included; when a
critical skill has changed, it runs three times. A drop exits 5 and asks for
confirmation; a harness or setup failure exits 1 and stops the release.

The `--finalize` item stamps the record with the confirmed version and names
it for upload as the release asset `eval-pass-rates.json`. If that command or
its upload fails, the next release has no baseline to compare against: retry
the upload before the release is published.

The release host needs `claude` with the skill-creator plugin, `python3`,
`git`, `gh`, and bash 4 or later, since the eval harness doesn't run on
macOS's bash 3.2. The nested eval sessions can reach that host's stored
credentials; the check prints the host it runs on and says so before any eval
runs.
