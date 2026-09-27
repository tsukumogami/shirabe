---
schema: prd/v1
status: In Progress
problem: |
  /work-on's staleness_check gate runs a script shirabe doesn't ship, found by
  bare name with an argument form no script on a shirabe-only host accepts. It
  fails on every issue-backed run before assessing anything, so every run
  takes a hand override, and the gate neither catches overtaken issues nor
  keeps `override` meaning a deliberate choice.
goals: |
  On a host with shirabe and its declared dependencies, the gate reaches a
  verdict on its own: fresh issues advance to analysis, stale ones go to
  introspection, and a check that cannot run produces a named, recorded
  outcome that lets the run continue. No issue-backed run needs an override.
source_issue: 80
absorbed:
  - docs/briefs/BRIEF-staleness-check-portability.md
---

# PRD: staleness-check portability

## Status

In Progress

Absorbed [BRIEF-staleness-check-portability](docs/briefs/BRIEF-staleness-check-portability.md); carried in Absorbed Brief.

## Absorbed Brief

The brief framed one gap: `/work-on`'s staleness gate calls a script shirabe
doesn't ship, by a bare name and an argument form nothing on a shirabe-only
host accepts, so every issue-backed run overrides it by hand and the gate
checks nothing. It was written after two live runs showed the gap was worse
than portability: with the script absent the gate can never pass, and where a
separately installed plugin provides a same-named script, that script rejects
the gate's argument form. That problem is this document's Problem Statement.

The outcome it asked for is that an unattended run on a shirabe-only install
gets past the gate without an override, either because the check runs and
decides or because the run records, as its own named outcome, that the check
could not run and why; and that a maintainer can read inside shirabe what
"stale" means. Those are this document's Goals.

Four journeys grounded it and survive as the User Stories: an unattended run
on a fresh issue; the same run on an overtaken issue routing to
introspection; a host where the check can't run, recorded rather than
overridden; and a maintainer comparing the check with its predecessor. Its
scope boundary is carried as the Requirements and Out of Scope: the gate, its
argument form and resolution, the named degraded outcome, whatever shirabe
needs to run the check, and the statement of signals are in; the external
script, building the logic into koto, the introspection procedure, the other
gates, and plan-backed and free-form runs are out.

## Problem Statement

`/work-on` runs every issue-backed task through a `staleness_check` state
before analysis. The state exists to catch issues the codebase has overtaken:
filed long ago, with milestone siblings closed since, or naming files that
have changed. A stale issue goes to `introspection`, where the agent re-reads
it against current code before planning.

The gate behind that state runs `check-staleness.sh --issue <N>` by bare name
and pipes the result through `jq`. shirabe doesn't ship the script. On a
shirabe-only host the command isn't found, `jq` reads empty input, and the
pipeline exits non-zero; koto runs the gate without `pipefail`, so the failure
looks like any other gate failure. Where a separately installed plugin puts a
script of that name on the host, it takes the issue number positionally and
rejects `--issue`, so the gate fails there too.

The state then offers `fresh` (which only advances on a passing gate),
`stale_requires_introspection`, `override` (documented for a user who asked to
skip the check) and `blocked` (which ends the run). Unattended runs take
`override` every time. The staleness signal is lost, and agents learn that
overriding a gate is routine.

## Goals

- The staleness check runs on any host that has shirabe and the tools shirabe
  already declares (`gh`, `jq`, `git`), with nothing else installed.
- The gate's verdict, not the agent's choice of evidence, decides whether an
  issue is fresh or stale whenever the check can run.
- When the check can't run, the run continues and says so on the record, in
  a form no one can mistake for `override` or `blocked`.
- A maintainer can read, inside shirabe, exactly what "stale" means.

## User Stories

- As an agent running `/work-on <issue>` unattended on a shirabe-only host, I
  want the staleness gate to pass on a recently filed issue, so that I reach
  analysis with `fresh` instead of inventing an override justification.
- As the same agent on an issue the codebase has overtaken, I want the gate to
  fail with a result that tells me it found staleness, so that I route to
  introspection instead of implementing a stale plan.
- As an agent on a host where the check can't run (no plugin root in the
  session, `gh` unauthenticated, GitHub unreachable), I want a named outcome
  for "not assessed" that lets me continue, so that the run neither stops at
  `done_blocked` nor records an `override` nobody asked for.
- As a reviewer reading a finished run, I want the "not assessed" outcome and
  its reason in the run's evidence, so that I know staleness was never
  checked.
- As a shirabe maintainer, I want the definition of "stale" (signals and
  thresholds) written down in shirabe, so that I can tune it and compare it
  with the check teams used before.

## Requirements

### Functional

- **R1. Resolvable without PATH setup.** The gate's command resolves whatever
  it runs from shirabe's own install (or from koto), never by bare name from
  `PATH`, and never from a separately installed plugin.
- **R2. One canonical argument form.** The gate and whatever it invokes agree
  on a single argument form, defined in shirabe. The argument form of any
  script outside shirabe is not relied on.
- **R3. Three distinguishable gate results.** The gate's result distinguishes
  three cases the agent can tell apart from the blocking condition koto
  reports: fresh (the gate passes), stale (the check ran and found at least
  one staleness signal), and unavailable (the check could not run or could
  not reach a verdict). Each result maps to evidence as follows:

  | Gate result | Evidence the directive prescribes | Route |
  |-------------|-----------------------------------|-------|
  | fresh | `fresh` | `analysis` |
  | stale | `stale_requires_introspection` | `introspection` |
  | unavailable | the degraded outcome (R6), with `detail` | `analysis` |
  | any | `override`, only on an explicit instruction to skip | `analysis` |
  | any | `blocked`, only when the run must stop | `done_blocked` |

- **R4. Fresh advances on the gate's word.** When the check finds no
  staleness signal the gate passes, and `fresh` routes to `analysis`. `fresh`
  routes nowhere when the gate did not pass. (The state requires evidence even
  on a passing gate; today's directive says it auto-advances, which it
  doesn't, and the directive is corrected.)
- **R5. Stale routes to introspection.** When the check finds staleness, the
  directive tells the agent to submit `stale_requires_introspection`, which
  routes to `introspection` as it does today.
- **R6. A named degraded outcome.** The state accepts a distinct evidence
  value for the unavailable case, separate from `override` and `blocked`. It
  routes to `analysis` and is accepted only when the gate's result is the
  unavailable one, so it can't stand in for a stale verdict. Its `detail`
  carries the reason.
- **R7. The directive offers it.** The `staleness_check` directive names the
  degraded outcome, says when it applies (and when it doesn't), and keeps
  `override` for an explicit instruction to skip the check and `blocked` for
  a run that must stop.
- **R8. Signals stated in shirabe.** The check's signals and thresholds are
  stated in one place in shirabe: at least issue age against a threshold,
  milestone siblings closed since the issue was filed, the issue's position in
  its milestone, and files the issue body names that were modified since it
  was filed. Where a signal or threshold differs from the check teams used
  before, the statement says so.
- **R9. The check reports its reasons.** When the check runs, it can emit the
  signals it measured and the reason for its verdict in machine-readable form,
  so an agent can quote them in `detail` or in introspection.

### Non-functional

- **R10. Dependencies.** The check uses only what shirabe already declares for
  `/work-on`: `gh`, `jq`, `git`, and a POSIX shell environment compatible with
  the bash 3.2 floor shirabe's scripts target.
- **R11. No private references.** Nothing committed names a private
  repository, private path, or private plugin.
- **R12. Tested.** Automated tests cover: a fresh issue passes the gate; a
  stale issue fails it with the stale result; a host where the check can't run
  produces the unavailable result and the degraded outcome advances to
  `analysis`; the template compiles and its mermaid companion matches.
- **R13. Bounded cost.** A single run of the check makes a bounded number of
  GitHub API calls (a small constant, independent of repository size) and
  completes well inside koto's gate timeout on a normal connection.

## Acceptance Criteria

Terms: the "plugin root" is the `PLUGIN_ROOT` variable the work-on template
already declares; "stale result" and "unavailable result" are the gate exit
statuses the DESIGN assigns to those two cases.

- [ ] AC1 (R1, R4). With only shirabe, `gh`, `jq` and `git` installed and
  `PLUGIN_ROOT` set, the gate on an issue created today with no milestone and
  no file references passes, and `fresh` routes the run to `analysis`.
- [ ] AC2 (R1). The gate still passes on a fresh issue when an executable
  named `check-staleness.sh` that rejects `--issue` sits first on `PATH`.
- [ ] AC3 (R5). The gate on an issue older than the age threshold fails with
  the stale result, and `stale_requires_introspection` routes to
  `introspection`.
- [ ] AC4 (R3, R8). Each of the four signals, on its own with the other three
  quiet, produces the stale result: age over threshold; one milestone sibling
  closed after the issue was created; a middle or last milestone position; a
  file named in the issue body with a commit since the issue was created.
- [ ] AC5 (R3, R6). With `PLUGIN_ROOT` set to the empty string, the gate fails
  with the unavailable result, and the degraded outcome with a `detail` routes
  to `analysis`.
- [ ] AC6 (R3, R6). With `gh` failing (not authenticated, or the API call
  erroring), the gate fails with the unavailable result, not the stale one.
- [ ] AC7 (R6). Submitting the degraded outcome when the gate reported the
  stale result leaves the workflow in `staleness_check`.
- [ ] AC8 (R4). Submitting `fresh` when the gate reported the stale or
  unavailable result leaves the workflow in `staleness_check`.
- [ ] AC9 (R7). `override` still routes to `analysis` and `blocked` to
  `done_blocked` whatever the gate result, and the directive names all five
  evidence values with the case each is for.
- [ ] AC10 (R2, R9). The check accepts `--issue <N>` as its only issue
  argument form, rejects a bare positional number with a usage exit status
  distinct from the stale and unavailable results, and on every verdict prints
  a JSON object carrying the verdict, each measured signal, and a reason.
- [ ] AC11 (R8). One document in shirabe lists each signal with its threshold,
  and a line per difference from the prior check's behaviour as described in
  issue #80's thread and the Problem Statement above; where there is no
  difference it says so.
- [ ] AC12 (R10). The check's test suite passes under the bash 3.2 floor
  runner, and the script calls no command outside `gh`, `jq`, `git` and POSIX
  utilities.
- [ ] AC13 (R13). One run of the check makes at most three `gh` calls,
  counted by a stub in the test suite.
- [ ] AC14 (R12). `koto template compile` succeeds on the edited template, the
  mermaid companion matches its export, and the existing work-on script
  suites pass.
- [ ] AC15 (R11). A reviewer's read of the diff finds no `private/` path
  component, no private repository name, and no plugin named other than
  shirabe and koto.

## Out of Scope

- Editing or depending on the script a separately installed plugin provides.
- Building staleness logic into koto. A proposal to the koto project is
  allowed; implementation there is not part of this work.
- Changes to the `introspection` state's procedure.
- Other gates in the work-on template.
- Plan-backed and free-form `/work-on` runs, which skip `staleness_check`.
- Retuning the staleness signals themselves beyond what portability requires.

## Decisions and Trade-offs

- **The PRD states the gate contract, not the mechanism.** Whether the check
  is ported into shirabe, made conditional, moved to koto, or dropped is the
  DESIGN's call. A port or a conditional gate can meet every requirement. A
  dropped gate meets none of R3 to R9 and would have to argue that the signal
  isn't worth keeping; moving the logic to koto leaves shirabe needing an
  interim answer, which the DESIGN must state.
- **Unavailable continues the run.** Routing it to `blocked` was the
  alternative. It was rejected because the brief's outcome is that an
  unattended run never stops at this gate for a missing tool, and because a
  staleness check is advisory: skipping it costs a possible re-read, not
  correctness.
- **Parity is documented rather than required.** Keeping every signal and
  threshold identical to the prior check would make comparison trivial but
  would freeze its known noise (for example, any issue in a milestone with
  one closed sibling reads as stale). The PRD requires the signals be stated
  and differences named, and leaves the tuning question out of scope.
