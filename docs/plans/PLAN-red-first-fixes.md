---
schema: plan/v1
status: Active
execution_mode: single-pr
split_mode_source: none
tracking_level: none
upstream: docs/designs/DESIGN-red-first-fixes.md
milestone: "red-first fixes and held-back test changes"
issue_count: 4
---

# PLAN: red-first fixes and held-back test changes

## Status

Active

This is a placeholder plan. The work it describes runs later as a step plan
regenerated from the design's four implementation steps; until then nothing
here is filed or started.

## Scope Summary

`/work-on` learns when a unit of work is a fix, records a failing check on
the base code before the correcting change and the same check passing after
it, holds a pass that came with an edited test until someone other than the
author accepts the edit under an interim rule that a higher authority can
overrule, and makes review tell an edited test from an added one.

## Decomposition Strategy

Walking skeleton. Issue 1 routes a fix red-first end to end, through the new
`fix_determination`, `reproduce` and `pass_counting` states. Issues 2 and 3
add the held-back pass (the ledger, the rule and the acceptance seat; then
the person path, overruling and the pull request record). Issue 4 makes review
tell edited from added. Each leaves `/work-on` working end to end, and all four
land in one pull request.

## Issue Outlines

### Issue 1: feat(work-on): start a fix from a red check run on the base code

**Goal**:

Let `/work-on` recognise a fix before implementation, record a failing check on the base code with the run's tests applied, and refuse to count a later pass unless the same check is green at the head, as the thinnest end-to-end path from `fix_determination` through `reproduce` to `pass_counting`.

**Acceptance Criteria**:

Fix recognition:

- [ ] A new `fix_determination` state sits between `review_level_choice` and `implementation`, and runs `fix-kind.sh resolve` as its default action.
- [ ] `fix-kind.sh resolve` binds `UNIT_KIND` to `fix` when the issue carries a label listed in `## Fix Labels:` in `CLAUDE.md` at the base (`bug` when the declaration is absent), or when a plan step supplies a `**Fixes**:` line as `FIX_REPORT`; otherwise it binds `change` and the run goes straight to `implementation` as today.
- [ ] Each determination is appended to the `fix_kind.jsonl` context key with its source (for example `label:bug`).
- [ ] `fix-kind.sh declare --reason` lets a run add the fix determination, and any move from `fix` back to `change` exits 1 with a `refused:` line naming the recorded source.
- [ ] A `kind_unchanged` gate (`fix-kind.sh agree`) holds when `UNIT_KIND` and the ledger disagree, so a hand rebind cannot skip the red.
- [ ] `FIX_REPORT` is declared in `work-on.md`, `skills/plan/scripts/plan-to-tasks.sh` forwards a step's `**Fixes**:` line into it, and `scripts/check-init-site-vars.sh` passes.
- [ ] `scripts/lib/claude-md-header.sh` reads one `## <Name>:` header from a `CLAUDE.md` at a given commit, ignores fenced code, and refuses duplicate headers.

The red:

- [ ] `UNIT_KIND=fix` routes to a new `reproduce` state, which leaves only through a `red_recorded` gate (`red-first.sh check-red`).
- [ ] `red-first.sh red` runs the check in a detached temporary worktree at `impl_base`, with the unit's committed test files (or those named by `--tests`) copied in, under a wall-clock bound, in its own process group that is killed whole at the bound.
- [ ] The command runs with an allowlisted environment: `GH_TOKEN`, `GITHUB_TOKEN` and `GIT_*` variables do not reach it. Symlinked test files are refused, and the worktree is removed by a trap.
- [ ] `red_first.json` is written only when the command exits non-zero, its output contains the marker, the marker is in the report passage, and the passage is verbatim in the report. Each failed condition exits 1 with a `refused:` line naming it, so a red that fails for a compile error is never recorded.
- [ ] A marker shorter than 8 characters or a passage shorter than 20 is refused.
- [ ] `red_first.json` holds the command, base, reproducing tests with blob ids, exit code, the last 40 lines of output capped at 4,096 bytes, passage, marker and time.
- [ ] Paths the command names that exist in the repository are recorded as the red's harness files.
- [ ] `red-first.sh observe --phase before|after` records an observation pair for a bug no check can reproduce, and `check-red` accepts a `before` observation.
- [ ] A run that returns to analysis and newly declares a fix comes back through `fix_determination` to `reproduce`.

The green and `pass_counting`:

- [ ] `red-first.sh green` re-runs the red's command at HEAD and records the exit code.
- [ ] A new `pass_counting` state is entered where `verification` exits 0, or where `verification_deferred` would go to `finalization`, and it has the `fix_green` gate (`red-first.sh check-green`).
- [ ] `check-green` passes for a non-fix, and for a fix passes only with a green at HEAD that exited 0.
- [ ] In this step `check-green` refuses an `after` observation with a `refused:` line saying observations wait for acceptance, so a unit recorded by observation stays held at `pass_counting`.
- [ ] `scripts/lib/test-classify.sh` diffs `impl_base` to HEAD, keeps paths in the `test` class of the rules copy stored at the base, and labels each `added`, `edited` or `unchanged`, judging a rename on both paths. For a fix it also labels `edited` any reproducing test or harness file whose blob id differs from the red's.

Walkthrough 1 (red then green on a reported bug), observable in a scratch repository:

- [ ] For a `bug`-labelled issue, `/work-on` reaches `fix_determination` and `fix-kind.sh` records `fix` with source `label:bug`.
- [ ] At `reproduce`, after a new reproducing test is committed, `red_first.json` shows a non-zero exit, a base equal to `impl_base`, the new test with its blob id, and an output tail containing the marker.
- [ ] After the code change and passing verification, `red-first.sh green` at `pass_counting` records exit 0 at the head, and the run proceeds to `finalization`.
- [ ] The red's test runs the reported case (`./greet.sh ''` in the walkthrough repository).
- [ ] A non-fix unit with no edited test passes through `fix_determination` and `pass_counting` with no new refusal.

Plumbing and regression:

- [ ] Each new script and library has a `_test.sh` beside it, listed in `scripts/bash-floor/work-on.list` and run from `.github/workflows/check-work-on-scripts.yml`, with new `scripts/lib/` files added to both of that workflow's `paths:` lists.
- [ ] `red-first-routes_test.sh` covers the new routes, and the existing route tests that assert the edges this step moves are updated.
- [ ] Each new script a template gate names, and each new library, has a `class engine` line in `skills/work-on/references/review-level-rules.tsv`.
- [ ] `work-on.mermaid.md` is regenerated, new finding rules have `references/rule-registry.json` entries and evals, `skills/work-on/references/red-first.md` is added, and `SKILL.md`, `phase-3-analysis.md`, `plan-format.md` and the plan step template mention the new behaviour.
- [ ] Every new script follows the bash 3.2 floor, uses guarded `mktemp`, builds JSON with `jq --arg` and never with string concatenation or `eval`.
- [ ] The full `/work-on` suite and the `/execute` template tests pass.

Downstream deliverables:

- [ ] Must deliver: `pass_counting` as a state with the `fix_green` gate and a place for a second gate, the `red_first.json` record, and `red-first.sh` `check-green` with the observation refusal that the next step relaxes (required by <<ISSUE:2>>).
- [ ] Must deliver: `scripts/lib/test-classify.sh`, sourceable by other scripts and emitting rows of class, path and blob id, with `test-classify_test.sh` (required by <<ISSUE:2>> and <<ISSUE:4>>).

**Dependencies**:

None

### Issue 2: feat(work-on): hold a pass from an edited test until a seat accepts it

**Goal**:

Hold a unit's passing check at `pass_counting` whenever the unit edited a test or relied on an observation, until a live acceptance from someone other than the author is on a session ledger that only `test-change.sh` writes and one rule library judges, and have a fresh acceptance seat give that acceptance in a repository that does not require a person.

**Acceptance Criteria**:

Ledger and writer
- [ ] `skills/work-on/scripts/test-change.sh` exists with the `init`, `classify`, `note`, `seat`, `accept`, `decline` and `status` commands, and is the only writer of the `test_change_ledger.jsonl` session key.
- [ ] `test-change.sh init` runs in `fix_determination`'s default action after `review_level_choice` has stored the rules copy, and writes a header line with the author (`agent:<session>`), `impl_base`, the repository, a run nonce, and whether the repository is person-required with its source.
- [ ] `init` refuses to run twice, and refuses an `impl_base` other than the merge-base of HEAD with the remote default branch (or the shared branch's tip when the step started). A ledger with no header holds the unit.
- [ ] Every ledger line carries `ts`, `event`, `identity`, `kind`, `authority`, `files`, `reason`, the rule outcome and rule id, `source` (`session`) and the judging rule (`interim`); lines are built with `jq --arg`.
- [ ] `accept`, `decline` and `seat` follow the design's input checks: session names match `^[A-Za-z0-9_-]{1,64}$`, identities match `^(agent|person):[A-Za-z0-9._:/-]{1,128}$`, path arguments are repository-relative with no `..` segment and no leading `-`, and control characters are stripped from reasons and paths. A `--repo` that differs from the header is refused before the rule is asked.
- [ ] A refused attempt appends a `refuse` line naming the rule and exits 1. Writers hold a per-session `mkdir` lock in a 0700, owner-checked per-user directory, exit 75 rather than write unlocked, and re-read the key to confirm their line landed.
- [ ] The script asserts the koto floor it relies on (retained sessions accept context writes and are addressed by name from any directory), and a test exercises both.

Rule library
- [ ] `scripts/lib/acceptance-rule.sh` exists with `acceptance_rule_decide` and `acceptance_rule_live`, and no other script compares authorities or names a rule id as a decision.
- [ ] The rules are checked in the order `author`, `authority-kind`, `person-required`, `unminted-seat`, `unknown-session`, `no-terminal`, `not-higher`, and an attempt that breaks several is refused by the first. Each rule has a test that triggers it alone.
- [ ] The author's own identity cannot accept; an agent can act only as `reviewer` or `coordinator`; an agent at `reviewer` must name an unused seat the run minted.
- [ ] `acceptance_rule_live` replays `decide` over each stored line, so a hand-written line the rule would refuse never counts; it ends an acceptance when a covered digest changes, and counts declines per sorted path set.
- [ ] A test replaces the rule bodies with a refuse-all stub and shows every caller still passes the same inputs and reads the same answers.

Counting state and seat
- [ ] `pass_counting` gains the `tests_counted` gate (`test-change.sh status`: exit 0 counted, 1 held with reasons, 2 undecided) beside `fix_green`.
- [ ] Walkthrough 2, step 1: for an unlabelled issue asking to change an expected value, the run is not a fix, edits one line of `tests/greet_test.sh` (one line removed, one added), and records why with `test-change.sh note`.
- [ ] Walkthrough 2, step 2: after verification passes, `test-change.sh status <session>` at `pass_counting` exits 1 with `held: unaccepted tests/greet_test.sh`.
- [ ] A test file that only gains lines is classified added and does not hold; a deleted or line-losing test file is edited and holds. Counting refuses (held, `uncommitted changes`) over uncommitted changes to tracked files.
- [ ] Walkthrough 2, step 3: in a repository that is not person-required, the directive has the run print the seat's brief with `test-change.sh seat`, commission one seat with the Agent tool on the same commissioning as the `light` panel's seat, and pass the brief unchanged. The brief holds the edited hunks, the run's recorded notes and the unit's acceptance criteria, framed as data.
- [ ] Walkthrough 2, step 3: the seat runs `accept` as `agent:<session>/accept-1`; `test-change.sh status` then exits 0, the run goes on to finalization, and the accepted file's digest (a blob id at the run's head) is recorded.
- [ ] A decline returns `pass_counting` to `implementation`, and the third decline of the same sorted path set ends the unit at `done_blocked`.
- [ ] An observation pair counts for a fix only once a live acceptance covers it, and `red-first.sh check-green` stops refusing an `after` observation that a live acceptance covers (it still refuses one that none covers).
- [ ] A person-required repository (`## Test Change Acceptance: person`) is left to <<ISSUE:3>>; here an agent acceptance in such a repository is refused with rule `person-required` once the declaration is read.

Plumbing
- [ ] `test-change_test.sh`, `test-change-routes_test.sh` and `acceptance-rule_test.sh` exist beside their scripts, are listed in `scripts/bash-floor/work-on.list`, and run in `.github/workflows/check-work-on-scripts.yml`; the new library is added to both of that workflow's `paths:` lists.
- [ ] `skills/work-on/references/review-level-rules.tsv` has an `engine` class line for `test-change.sh` and `acceptance-rule.sh`.
- [ ] `work-on.mermaid.md` is regenerated, route tests that assert moved edges are updated (including `retry-clearing_test.sh`), `phase-4-implementation.md` stops offering a free test edit, `red-first.md` and `SKILL.md` describe the hold, new finding rules have `references/rule-registry.json` entries and evals in `evals/evals.json`.
- [ ] New scripts follow the repository conventions: bash 3.2, guarded `mktemp`, and the `test -x ... || exit 2` gate form with `SHIRABE_GATE_*` variables.
- [ ] The whole `/work-on` suite and the `/execute` template tests pass, including the suites that read the states this step touches.
- [ ] E2E flow still works (do not break the skeleton)

**Dependencies**:

Blocked by <<ISSUE:1>>

### Issue 3: feat(work-on): require a person where declared, overrule acceptances, and record them on the pull request

**Goal**:

Refine the skeleton so that a repository declaring `## Test Change Acceptance: person` stops the run for a person at a terminal, a higher authority can overrule an acceptance before or after the run finished, the ledger can be read back and rendered into the pull request body, and a test edit made while fixing CI is held again before the run is done.

**Acceptance Criteria**:

Person-required repository (walkthrough 3):

- [ ] With `## Test Change Acceptance: person` on the default branch, a run that edits `tests/greet_test.sh` does not commission an acceptance seat at `pass_counting`. It stops with a message naming the edited file and the exact `accept` command a person runs.
- [ ] In that repository, an agent's `accept` as `agent:<session>/accept-1` at `reviewer` exits 1, and `record` shows a `refuse` line with rule `person-required`.
- [ ] A declaration value the script does not recognise is treated as `person`, and the record names the unrecognised value.
- [ ] `CLAUDE.local.md` in the working tree can tighten the declaration to `person` but cannot relax a `person` declared at the base or at the remote default branch tip.
- [ ] A person `accept` run in a real terminal prints the covered files, their digests, the edited hunks and a short code derived from them, reads the code back from `/dev/tty`, and on a correct code records the acceptance as `person:<name>` at `owner`. `record` then shows the unit counted.
- [ ] A wrong code, or stdin or stdout not on the terminal, is refused with rule `no-terminal` and recorded.
- [ ] Paths and hunks printed to the terminal have control characters escaped, so a crafted file name cannot rewrite what the person sees.
- [ ] A person line carries a keyed integrity tag from a per-user key file (mode 0600), and a hand-written person line whose tag does not check never counts.
- [ ] Resuming `/work-on` on the same unit after the person's acceptance continues from `pass_counting` to finalization.

Overruling and authority (walkthrough 2, steps 4 and 5):

- [ ] After the run finished, `overrule --as agent:<coordinator session> --authority coordinator --acceptance <id> --reason <text>` appends to the retained session's ledger, and `record` shows the unit held with reason `overruled`.
- [ ] The pull request section shows the overruling after `render --update` is run.
- [ ] A fresh seat's `accept` at `reviewer` after the overrule leaves the record held (`overruled`).
- [ ] An `accept` as `agent:<coordinator session>` at `coordinator` after the overrule makes the record show the unit counted.
- [ ] An overrule from an identity or authority that is not strictly higher than the acceptance's is refused with rule `not-higher` and recorded.
- [ ] Writers hold the per-user lock, exit 75 when they cannot get it, and re-read the key after writing to confirm the line landed.

Refusals recorded (walkthrough 4):

- [ ] On a run whose seat acceptance is live, each of these exits 1 and appends a `refuse` line naming the rule: `--as agent:<session>` (rule `author`); `--as agent:other` at `reviewer`, never minted (rule `unminted-seat`); `--as agent:other` at `owner` (rule `authority-kind`); `--as agent:no-such-session` at `coordinator` (rule `unknown-session`); `--as person:<name>` at `owner` from the agent's tool shell (rule `no-terminal`); and an overrule by a second minted seat at `reviewer` (rule `not-higher`).
- [ ] `record` lists all six refusals with identity, action, files, rule and time, and the unit is still counted.
- [ ] `render <session> --update` rewrites the run's pull request section, and the section's history shows the six refusals.
- [ ] Each attempt is judged by the first rule it breaks, in the documented order, and only `scripts/lib/acceptance-rule.sh` compares authorities or names a rule as a decision.

Pull request record and check:

- [ ] `record` prints the readout and `render` prints the pull request section between `<!-- shirabe-test-change:<session>:start -->` and the matching end marker, one section per session.
- [ ] `render` shows the red's and green's output only as the three lines either side of the marker, with home paths and common token shapes redacted. Free text has newlines collapsed and comment and marker strings neutralised, so a reason cannot close the section or forge another.
- [ ] When the report passage comes from a private repository's issue and the pull request is public, the section omits the passage, the marker and the output lines and says so.
- [ ] The section labels every identity as a recorded claim and names the judging rule (`interim`).
- [ ] `record` falls back to the pull request section, labelled reconstructed, after a prune. That read is display-only and never yields `counted`.
- [ ] `pr_precheck` re-runs `status` and fails when the pull request body lacks the section or the section does not match `render`. A commit made after counting is held again by digest.
- [ ] `check-pr-output.sh` and its test cover both the passing and the mismatched section.

CI-fix test edits:

- [ ] `ci_pass_counting` exists, is entered only from `ci_monitor`'s passing edges, and has the `fix_green` and `tests_counted` gates.
- [ ] A test edit made while fixing a failing CI run holds the unit at `ci_pass_counting` until a live acceptance covers it. A decline returns the run to `ci_monitor`, and the third decline of the same path set ends at `done_blocked`.
- [ ] `ci-monitor-role_test.sh`, `cascade-chaining_test.sh` and `leg-result_test.sh` are updated for the moved edges and pass.

Plumbing and guidance:

- [ ] `work-on.md` is changed, `work-on.mermaid.md` is regenerated, and the route tests that assert the moved edges pass.
- [ ] `test-change_test.sh`, `test-change-routes_test.sh` and `acceptance-rule_test.sh` cover the person path, overrule, record, render and the refusals above. The workflow file and bash-floor list entries from earlier steps still cover them.
- [ ] `phase-5-finalization.md`, `phase-6-pr.md`, `red-first.md` and `references/fixes/claude-md-conventions.md` describe the person-required declaration, the terminal acceptance and the pull request section, and no longer offer a free test edit when fixing CI.
- [ ] Each new finding rule has a `references/rule-registry.json` entry and an eval in `skills/work-on/evals/evals.json`.
- [ ] The full `/work-on` suite and the `/execute` template tests pass.
- [ ] Nothing under `skills/coordinate/`, koto or niwa is changed.
- [ ] E2E flow still works (do not break the skeleton)

**Dependencies**:

Blocked by <<ISSUE:1>> (the skeleton this refines) and <<ISSUE:2>> (the ledger, rule library and acceptance seat this builds on).

### Issue 4: feat(work-on): make review tell an edited test from an added one

**Goal**:

Refine the skeleton so review tells an edited test from an added one: an edited test floors the review level at `full`, appears in its own packet section, and must be judged by every review seat.

**Acceptance Criteria**:

- [ ] `review-level.sh facts` emits a `tests_edited` boolean from the shared classifier, and it appears in `review_facts.json` and in the decider's slice.
- [ ] `review-level-rules.tsv` gains `rule full tests_edited` while `rule standard class:test` stays: a change that only adds tests still floors at `standard`, and a change with an edited test floors at `full`.
- [ ] `scripts/review-packet.sh code` prints a `## Test changes` section between "Changed paths" and "Diff", listing added tests by path and edited tests with their hunks; a change with no test files produces no such section content beyond what the packet does today.
- [ ] Each seat verdict accepts a `test_edits: [{path, judgment}]` field, where `judgment` is `corrects` or `weakens`.
- [ ] `panel-scope.sh --record` refuses a round (exit 65, rule `review/test-edit-judgment`) in which any seat lacks an entry for an edited path.
- [ ] `panel-scope.sh --record` records each `weakens` judgment as a blocking finding raised by that seat under rule `review/test-edit-weakens`.
- [ ] The four seat files (`phase-4a-scrutiny.md`, `phase-4b-review.md`, `phase-4c-qa.md`, `phase-4d-light.md`) each gain one question asking the seat to judge each edited test.
- [ ] The implementation and CI-fix guidance (`phase-6-pr.md` and related text) no longer offers a free test edit as a way to clear a failing test.
- [ ] `review-levels.md`, `review-panel-orchestration.md` and `SKILL.md` describe the new fact, floor, packet section and verdict field.
- [ ] New finding rules (`review/test-edit-judgment`, `review/test-edit-weakens`) have entries in `references/rule-registry.json` and `references/jev-criteria.md`, and an eval in `skills/work-on/evals/evals.json`.
- [ ] Tests cover the new behavior: `review-level_test.sh` (added-only floors at `standard`, edited floors at `full`), `review-packet_test.sh` (section content for added and edited tests), and `panel-scope_test.sh` (refusal on a missing judgment, blocking finding on `weakens`).
- [ ] The whole `/work-on` script suite and the `/execute` template tests pass.
- [ ] E2E flow still works (do not break the skeleton)

**Dependencies**:

Blocked by <<ISSUE:1>>

## Implementation Sequence

Critical path: Issue 1, then Issue 2, then Issue 3. Issue 4 depends only on
Issue 1's classifier and can run beside Issue 2. Recommended order: 1, 2, 4, 3.
