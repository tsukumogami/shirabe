---
status: Accepted
decision: |
  shirabe's koto minimum is 0.37.0, the FLOOR line of
  scripts/assert-koto-floor.sh. 0.37.0 is the release whose `koto overrides
  record` takes a decider (`--by person:<handle>`, `--surface`, `--link`) and
  records the decision with the override. /work-on's panel verdict directives
  have the run record a person's override of a panel gate naming that person,
  and skills/work-on/requires.tsv declares the three flags. This supersedes
  the minimum stated in DECISION-preflight-koto-minimum-2026-09-27.md; how the
  preflight reads and compares the minimum is unchanged.
rationale: |
  The alternative was to keep the old minimum and detect `--by` at runtime,
  which means two code paths for one command: one that names the person and
  one that can't. The minimum exists so a skill uses one path and a host
  without it is told at load. koto 0.37 is current on every host the workspace
  manages, and the preflight already prints the minimum and the installed
  version, so the hosts this refuses are told what to upgrade.
---

# DECISION: shirabe's koto minimum rises to 0.37.0

## Status

Accepted on 2026-11-23. Supersedes the minimum stated in
`DECISION-preflight-koto-minimum-2026-09-27.md`, which stays in force for how
the preflight reads and compares the minimum.

## Context

When a person decides that a `/work-on` panel verdict gate (`scrutiny_verdict`,
`review_verdict`, `qa_verdict` or `light_verdict`) should be passed, the
override used to be written by the person into the run's session from their
own shell, and koto recorded no decider. `docs/designs/DESIGN-acceptance-write-drift.md`
(Decision 4) has the run record the override itself, naming the person and the
surface they used, and has an unattended run record none and escalate. That
needs `koto overrides record --by`, which koto 0.37.0 introduced. Older
releases refuse the flag.

## Decision

`FLOOR` in `scripts/assert-koto-floor.sh` is 0.37.0. The four panel verdict
directives in `skills/work-on/koto-templates/work-on.md` name
`koto overrides record <session> --gate <gate> --rationale "<the person's words>" --by person:<handle> --surface <terminal|forge|relay>`,
with `--link <url>` for `relay`. `skills/work-on/requires.tsv` declares `--by`,
`--surface` and `--link` on `overrides record`, so the load-time surface probe
also catches a koto without them.

## Consequences

Hosts on koto 0.33 to 0.36 get the preflight's "prerequisite not met" block
until they upgrade. Every restatement of the minimum moved with it, which
`scripts/koto-minimum-consistency_test.sh` checks, and
`.github/workflows/offload-ablation.yml` records the 0.37.0 release binary's
sha256. koto records the handle without verifying it; a person override rests
on the agent's report of what the person said, and the rationale quotes it.

## References

- `docs/decisions/DECISION-preflight-koto-minimum-2026-09-27.md`
- `docs/designs/DESIGN-acceptance-write-drift.md`
