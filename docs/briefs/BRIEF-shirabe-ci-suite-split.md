---
schema: brief/v1
status: Accepted
problem: |
  A CI round on a shirabe pull request now takes 40-75 minutes, against
  2-3 minutes in September 2026. A few jobs run long suite lists one after
  another on one runner, and every fix-and-push round waits for the
  slowest of them.
outcome: |
  Someone pushing to a shirabe pull request gets every check back in a
  fraction of today's time, with the same tests run on the same koto
  releases and bash versions, so a round costs minutes again.
motivating_context: |
  Pull request runs on 2026-11-23 showed entry-floor at 41-53 minutes,
  test-coordinate-engine at 41, test-coordinate-scripts at 35, and on a
  ready pull request skill-gate's macOS leg at 72 and test-rule-registry's
  at 45. Suite runtimes grew 10-25x in two months while the jobs kept
  their one-runner, one-after-another shape.
---

# BRIEF: Shorter CI rounds for shirabe pull requests

## Status

Accepted

## Problem Statement

A shirabe pull request's CI round is as long as its slowest job, and the
slowest jobs have grown from a few minutes to most of an hour: a round took
2-3 minutes in September 2026 and takes 40-75 by late November. Each one
runs a long list of test suites sequentially on a single runner.

Measured on pull request runs from 2026-11-23:

- `entry-floor` (`check-koto-entry-floor.yml`) took 41-53 minutes. It
  installs the oldest koto release shirabe supports and runs five skills'
  koto-backed suites in a row. About 44 of those minutes are /coordinate's
  engine suites; /scope, /execute, /deliver and /work-on together take
  about 9.
- `test-coordinate-engine` took about 41 minutes and `test-coordinate-scripts
  (ubuntu-latest)` about 35 (`check-coordinate-scripts.yml`). Each runs
  every suite in `skills/coordinate/scripts/` through `run-tests.sh`, one at
  a time: 47 engine suites and 80 offline ones. No single suite takes more
  than about 6.5 minutes.
- On a ready (non-draft) pull request, `skill-gate (macos-latest)` took
  about 72 minutes and `skill-gate (ubuntu-latest)` about 42
  (`check-skill-gate.yml`), because `scripts/skill-gate.sh` runs
  `check-skill.sh` in full for each skill the change touches, so a
  /coordinate change runs coordinate's suites a third time, on macOS's
  bash 3.2 as well. `test-rule-registry (macos-latest)` took about 45.
- Behind those, `test-work-on-scripts` (15-20) and `test-execute-scripts`
  (14-19) run their suites one step at a time.

The path filters are not the main cause: entry-floor and the coordinate
workflow already trigger only on the skills and shared scripts they test.
The cost is that suites which could run side by side run in sequence, so
the round grows with the suite count. A contributor who pushes a one-line
fix waits close to an hour to learn whether it passed, and an agent driving
a pull request through several review rounds spends most of its wall clock
waiting.

The guarantees these jobs give have to survive whatever changes. Entry-floor
proves every koto-backed skill still works on the oldest koto release
shirabe supports, while every other workflow runs the newest 0.x. The macOS
legs prove the scripts run on bash 3.2 with BSD tools. A change to a shared
script has to keep running every suite that depends on it.

## User Outcome

A contributor or an agent pushing to a shirabe pull request gets every
check's result in a fraction of today's time. The round is bounded by the
slowest slice of a suite list rather than the whole list, and the same
tests run on the same koto releases, bash versions and operating systems as
before. A red check still names the suite that failed, and the checks the
repository's rulesets require keep reporting under their names, so merging
works as it does today.

## User Journeys

### A contributor changes one /coordinate script

A contributor edits a script under `skills/coordinate/scripts/` and pushes.
Today the push starts entry-floor and both coordinate jobs and the round
takes about 50 minutes. Afterwards the same suites run, on the floor koto
and on the newest koto, spread across parallel legs, and the round ends
when the slowest leg does.

### A contributor changes a shared script

A contributor edits `scripts/lib/` or `scripts/koto-open.sh`, which many
skills call. Every suite that depends on the script still runs, each
skill's suites on the floor koto included, and the extra legs run side by
side instead of adding to one job's length.

### A pull request is marked ready

An author marks a draft ready, which starts the macOS bash 3.2 legs of
skill-gate, rule-registry, execute and work-on. Those legs still run every
case they run today and no longer turn a 40-minute round into a 75-minute
one.

### A maintainer reads a failure

A shard fails. The maintainer sees which leg it was and which suite inside
it failed, and re-running that leg reruns exactly the suites it holds.

## Scope Boundary

**In:**

- Running each koto-backed skill's floor-koto suites in its own parallel
  leg, each leg still on exactly the oldest supported koto release.
- Spreading /coordinate's engine and offline suites across parallel legs,
  both in its own workflow and in the floor check.
- Spreading the other long sequential jobs (the skill gate and the
  rule-registry, /work-on and /execute suites) where their length sets the
  round.
- The test-runner support that splitting needs, such as running a chosen
  slice of a suite list.
- Narrower triggers for a leg where no suite it drops depends on the
  changed paths, with every narrowed suite named.

**Out:**

- Removing, skipping or weakening any test, and adding retries to hide a
  slow or flaky suite.
- Making individual suites faster by changing what they assert. Speeding
  up a slow suite is separate work.
- Any change to skill prose, the references skills load, koto templates,
  or /coordinate's behaviour.
- Taking the macOS bash 3.2 legs off pull requests, or changing which koto
  release the floor check installs.
- Renaming or dropping the checks the repository's rulesets require.
