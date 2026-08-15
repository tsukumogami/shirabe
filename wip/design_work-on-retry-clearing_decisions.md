# /design decision log: work-on-retry-clearing

Decision 1 is Tier 4 and runs through `/decision`'s full path; its report lands
at `wip/design_work-on-retry-clearing_decision_1_report.md`. Decision 2 is Tier 2
and is recorded here under the lightweight protocol in
`references/decision-protocol.md`.

<!-- decision:start id="test-home-and-ci" status="confirmed" -->
### Decision: where the round-trip test lives and how CI runs it

**Question:** Where does the test that drives real koto sessions live, and how
does CI run it?

**Tier:** 2. Reversibility is cheap (moving a shell script and a workflow),
a clear winner emerges from the repository's own conventions, and this is not
the question the design phase exists to answer. That is Tier 2 under the
three-signal checklist, which stays in the micro-protocol.

**Evidence, from the repository rather than from preference:**

- Shell suites live beside the skill they test:
  `skills/plan/scripts/plan-to-tasks_test.sh`,
  `skills/execute/scripts/{run-cascade,preflight,settled-branch-record}_test.sh`.
  `skills/work-on/` has no `scripts/` directory yet.
- Each suite has its own workflow: `check-plan-scripts.yml`,
  `check-execute-scripts.yml`, `check-templates.yml`,
  `check-template-consistency.yml`. There is no `check-work-on-scripts.yml`.
- `scripts/check-bash-floor.sh` carries a registry with four edit points --
  `SUITES`, `suite_scripts()`, `suite_workflow()`, `suite_needs_shirabe()` --
  and its own self-test asserts every registered script exists.
- `check-execute-scripts.yml` is the closest precedent and already solves the
  hard part: its Linux leg installs tsuku and then the project tool manifest to
  get a real koto, and its macOS leg runs the suite on the bash 3.2 floor
  through `scripts/check-bash-floor.sh --backend system execute`.
- `settled-branch-record_test.sh` exits 0 with a loud SKIP when koto is absent,
  which is what lets the same suite run on the floor leg that has no koto.

**Choice:** A new `skills/work-on/scripts/retry-clearing_test.sh`, a new
`.github/workflows/check-work-on-scripts.yml` modelled on
`check-execute-scripts.yml`, and a `work-on` suite registered in
`scripts/check-bash-floor.sh`. `suite_needs_shirabe()` returns false for it: the
harness drives koto only and never invokes `shirabe`, unlike the `plan` and
`execute` suites.

**Alternatives considered:**

- *Add the cases to `skills/execute/scripts/settled-branch-record_test.sh`.*
  Rejected on ownership: that harness tests `/execute`'s `orchestrator_setup`,
  and a `/work-on` regression failing a workflow named for `/execute` sends the
  next reader to the wrong skill. It would also couple the two skills' CI paths
  so that a change to either re-runs both.
- *A top-level `scripts/retry-clearing_test.sh`.* Rejected because top-level
  `scripts/` in this repository holds repository lint and cross-cutting tooling,
  not per-skill behaviour tests, and the bash-floor registry's own exemption
  list documents that split.

**Assumptions:**

- CI can install koto the same way `check-execute-scripts.yml` does. Same
  runner, same manifest.
- The macOS floor leg has no koto, so the harness needs the same koto-absent
  SKIP the precedent uses, and the floor leg checks portability of the shell
  rather than the assertions.

**Consequences:** One new script, one new workflow, and four small edits to the
bash-floor registry. `scripts/check-bash-floor_test.sh` iterates a hardcoded
list of suites and checks each appears in `--list`; adding `work-on` to that
list extends coverage rather than relaxing an assertion, and the suite passes
with or without it. This is recorded because "no existing test modified" is an
acceptance condition, and this is the one existing test file the work touches.

**Reversibility:** low cost.
<!-- decision:end -->
