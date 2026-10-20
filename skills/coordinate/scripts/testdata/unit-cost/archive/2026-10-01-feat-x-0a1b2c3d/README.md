# Teardown of feat-x

Taken 2026-10-01T11:45Z by the coordinator's teardown pass, before anything was removed.

- Instance: inst-feat-x (/work/inst/feat-x)
- Claude Code job: 0a1b2c3d, session 0a1b2c3d-77aa
- Merged pull request: acme/widgets#21 5555555555555555555555555555555555555555
- Handoff: https://github.com/acme/widgets/pull/21#issuecomment-901

`claude-projects/` holds the Claude Code project directories of the instance, each copied whole without following a symbolic link:

- Project directory taken: -work-inst-feat-x
- Project directory taken: -work-inst-feat-x-widgets
- Project directory skipped (cwd outside the instance): -work-inst-feat-x-2

MANIFEST lists every copied file as `<sha256> <bytes> <path>`; each was checked against its source.
`teardown.json`, in the MANIFEST, records what the pass acted on: the topic, the instance, the job and session, whether the unit was removed outside the pass, and niwa's dispatch id.
`unit-cost.json`, when present, is the cost capture's derived summary and is not in the MANIFEST.
