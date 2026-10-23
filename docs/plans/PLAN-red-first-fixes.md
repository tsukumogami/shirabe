---
schema: plan/v2
status: Active
execution_mode: single-pr
split_mode_source: none
tracking_level: none
upstream: docs/designs/DESIGN-red-first-fixes.md
milestone: "red-first fixes and held-back test changes"
step_count: 4
---

# PLAN: red-first fixes and held-back test changes

## Status

Active

## Scope Summary

`/work-on` learns when a unit of work is a fix, records a failing check on
the base code before the correcting change and the same check passing after
it, holds a pass that came with an edited test until someone other than the
author accepts the edit under an interim rule that a higher authority can
overrule, and makes review tell an edited test from an added one.

## Decomposition Strategy

Walking skeleton. Step 1 runs a fix end to end on a scratch repository: the
run determines it is a fix at `fix_determination`, records a red on the base
code at `reproduce`, implements, and is counted at `pass_counting` only with a
green at its head. Steps 2 and 3 hold a pass that came with an edited test
(accepted by a seat the run mints; then a person where the repository
requires one, overruling and the pull request record). Step 4 makes review
tell an edited test from an added one. Steps 3 and 4 are detailed after the
step before them reaches its terminal.

## Steps

### Step 1: a fix run records a red on the base code before its correcting change and is counted only with a green at its head

**Goal**: A `/work-on` run on a scratch repository whose issue carries the `bug` label crosses `fix_determination`, `reproduce` and `pass_counting`: it records the fix with its source, a red from the check run on the base code with the run's test applied, and a green at its head before it can finish.

**Acceptance Criteria**:

- [ ] A run on an issue labelled `bug` (or whichever label the repository's `## Fix Labels:` declaration lists) records the unit as a fix with source `label:bug`; a plan step that carries a `**Fixes**:` line records it with that source, and the run's own `declare --reason` records it with a declared source.
- [ ] A unit with no fix label, no `**Fixes**:` line and no declaration is recorded as a change, goes from `fix_determination` straight to `implementation`, and meets no red or green requirement at `pass_counting`.
- [ ] Once a unit is recorded as a fix, an attempt to move it back to a change exits 1 with a `refused:` line naming the recorded source, and a hand rebind of the kind variable away from the ledger holds the run at `fix_determination`.
- [ ] A red is recorded only when the check exits non-zero and its output contains the marker; a zero exit, or output without the marker, exits 1 with a `refused:` line naming the failed condition and writes no red.
- [ ] A marker shorter than 8 characters, a passage shorter than 20 characters, or a passage that is not verbatim in the report (the issue body, task text or supplied report) exits 1 with a `refused:` line, and nothing is recorded.
- [ ] The red runs on the base code with the run's committed test files applied: when the correcting change is already committed on the branch, the red still fails and is recorded, and the record shows the base commit, the reproducing test with its blob id, the non-zero exit and an output tail containing the marker.
- [ ] From `reproduce`, `implementation` cannot be reached without a recorded red or a recorded before-observation; the `red_recorded` gate holds the run there with a message saying which is missing.
- [ ] At `pass_counting`, a fix with no green at its head (the same command exiting 0) is held and does not reach `finalization`; once the green is recorded the run moves on.
- [ ] A fix recorded by an observation pair stays held at `pass_counting` with a `refused:` line saying observations wait for acceptance, even after the after-observation is recorded.
- [ ] A plan step whose body has a `**Fixes**:` line reaches the run as its fix report, so the red's passage is checked against that text and not against an issue body.

**Check**: In a scratch repository (a `greet.sh` that prints `Hello, <name>!`, a `tests/run.sh` runner, and a `bug`-labelled issue saying `./greet.sh ''` should print `error: name required`), run `bash skills/work-on/scripts/red-first-routes_test.sh`. It drives a real koto session through `fix_determination`, `reproduce` and `pass_counting` and must exit 0, showing the fix recorded with source `label:bug`, a red whose base equals the implementation base and whose output tail holds the marker, a hold at `pass_counting` until the green at the head is recorded, and the same route taken by a non-fix unit with none of those records. Then run `bash skills/work-on/scripts/red-first_test.sh` and `bash skills/work-on/scripts/fix-kind_test.sh`; both must exit 0, including their cases for a missing marker, a too-short marker, a too-short passage, a passage not in the report, and a withdrawn fix.

**Dependencies**: None

**Files**: `scripts/lib/claude-md-header.sh`, `scripts/lib/claude-md-header_test.sh`, `scripts/lib/test-classify.sh`, `scripts/lib/test-classify_test.sh`, `skills/work-on/scripts/fix-kind.sh`, `skills/work-on/scripts/fix-kind_test.sh`, `skills/work-on/scripts/red-first.sh`, `skills/work-on/scripts/red-first_test.sh`, `skills/work-on/scripts/red-first-routes_test.sh`, `skills/work-on/references/red-first.md`, `skills/work-on/koto-templates/work-on.md`, `skills/work-on/koto-templates/work-on.mermaid.md`, `skills/work-on/SKILL.md`, `skills/work-on/references/phases/phase-3-analysis.md`, `skills/work-on/references/review-level-rules.tsv`, `skills/work-on/scripts/offload-canary-routes_test.sh`, `skills/work-on/scripts/review-level-routes_test.sh`, `skills/work-on/scripts/verification-deferral_test.sh`, `skills/work-on/scripts/output-gates-routing_test.sh`, `skills/work-on/evals/evals.json`, `skills/plan/scripts/plan-to-tasks.sh`, `skills/plan/scripts/plan-to-tasks_test.sh`, `skills/plan/references/plan-format.md`, `skills/plan/references/templates/step.md`, `references/fixes/claude-md-conventions.md`, `references/rule-registry.json`, `scripts/bash-floor/work-on.list`, `.github/workflows/check-work-on-scripts.yml`

### Step 2: a pass that came with an edited test is held until a minted acceptance seat accepts it

**Goal**: At `pass_counting`, a unit whose diff removes a line from a test (or carries an observation) is held until `test-change.sh` records a live acceptance by a seat the run minted, under the interim rule in `scripts/lib/acceptance-rule.sh`. A run that only adds tests, or whose edit a seat accepts, reaches its pull request without waiting for a person.

**Acceptance Criteria**:

- [ ] A test file that only gained lines (or is new) is labelled `added` by `test-change.sh classify`, and a unit with only added tests passes `test-change.sh status` with exit 0 and no acceptance recorded.
- [ ] A test file with a removed line, a deleted test file, or a renamed test file with a changed line is labelled `edited`, and `test-change.sh status` exits 1 printing `held: unaccepted <path>` for it.
- [ ] After `test-change.sh seat` prints `agent:<session>/accept-1`, `test-change.sh accept` run as that identity at `reviewer` exits 0, `status` exits 0, and the ledger line records the identity, kind `agent`, authority `reviewer`, the covered file's blob digest, the reason, a time and the judging rule `interim`.
- [ ] `accept` run as the run's own identity (`agent:<session>`) exits 1 and appends a `refuse` line with rule `author`; run as `agent:other` at `reviewer`, a name never minted, it exits 1 with rule `unminted-seat`; run as an agent at `owner` it exits 1 with rule `authority-kind`; run as `agent:no-such-session` at `coordinator` it exits 1 with rule `unknown-session`. Each refuse line records who asked, the action, the files, the rule id and a time, and the unit stays held.
- [ ] After a commit changes an accepted file, `status` exits 1 and prints a held reason `changed since acceptance` for that path, and a second `accept` covering the new digest makes it exit 0 again.
- [ ] `decline` returns the run from `pass_counting` to `implementation`, and the third `decline` against the same sorted path set sends the run to `done_blocked` instead.
- [ ] An `after` observation recorded with `red-first.sh observe` is held as unaccepted until a seat accepts its digest; once a live acceptance covers it, `red-first.sh check-green` exits 0 where it refused before.
- [ ] A ledger with no header line, or an `init` run a second time, leaves `status` exiting 1 (held) and `init` exiting 1 respectively, rather than counting the unit.
- [ ] Replacing the bodies of `acceptance_rule_decide` and `acceptance_rule_live` in `scripts/lib/acceptance-rule.sh` with a refuse-all body makes every `accept` exit 1 and every unit with an edit stay held, with no other file changed.
- [ ] In a repository that is not person-required, an autonomous run with an edited test reaches `finalization` after the seat's acceptance, with no stop that asks a person.
- [ ] A review-level change made after `fix_determination` (a raise at `review_level_check`) leaves the run's recorded fix determination in force: `fix-kind.sh agree` still exits 0 and `pass_counting` still requires the green for a fix.

**Check**: Run `bash skills/work-on/scripts/test-change-routes_test.sh`. It drives a koto session whose diff edits a test and should print only passing cases: `tests_counted` holds with `unaccepted`, a minted seat's accept makes `status` exit 0, the author's and an unminted reviewer's accepts exit 1 with rules `author` and `unminted-seat`, and a later edit to the accepted file holds the unit again with `changed since acceptance`. Then run `bash scripts/lib/acceptance-rule_test.sh` and `bash skills/work-on/scripts/test-change_test.sh` and see both exit 0.

**Dependencies**: Step 1

**Files**: `scripts/lib/acceptance-rule.sh`, `scripts/lib/acceptance-rule_test.sh`, `skills/work-on/scripts/test-change.sh`, `skills/work-on/scripts/test-change_test.sh`, `skills/work-on/scripts/test-change-routes_test.sh`, `skills/work-on/koto-templates/work-on.md`, `skills/work-on/koto-templates/work-on.mermaid.md`, `skills/work-on/SKILL.md`, `skills/work-on/scripts/red-first.sh`, `skills/work-on/scripts/red-first_test.sh`, `skills/work-on/scripts/retry-clearing_test.sh`, `skills/work-on/references/red-first.md`, `skills/work-on/references/phases/phase-4-implementation.md`, `skills/work-on/references/review-level-rules.tsv`, `skills/work-on/scripts/review-level.sh`, `skills/work-on/scripts/review-level_test.sh`, `skills/work-on/evals/evals.json`, `references/rule-registry.json`, `scripts/bash-floor/work-on.list`, `.github/workflows/check-work-on-scripts.yml`

### Step 3: a person-required repository waits for a person, a higher authority can overrule, and the pull request carries the record

**Goal**: A repository whose `CLAUDE.md` declares `## Test Change Acceptance: person` holds the run at `pass_counting` until a person accepts at a terminal; a higher authority overrules an acceptance before or after the run finished; a test edit made while fixing CI is held at `ci_pass_counting`; and the pull request body carries the rendered record, checked at `pr_precheck`.

**Acceptance Criteria**:

- [ ] With `## Test Change Acceptance: person` in `CLAUDE.md` at the base or at the remote default branch's tip, the ledger header records `person_required: true` and its source; a `CLAUDE.local.md` saying `agent` leaves it `true`, and an unknown value reads as `person` and is named in the record.
- [ ] In such a repository, a held run doesn't commission a seat: it stops at `pass_counting` with a message naming each held file and the exact `test-change.sh accept` command a person runs.
- [ ] An agent's accept there exits 1 with rule `person-required`, and a `person:` accept run without a terminal (stdin, stdout and `/dev/tty` not one terminal) exits 1 with rule `no-terminal`; both are recorded as `refuse` lines.
- [ ] A `person:` accept run in a terminal (in tests, under a pseudo-terminal) prints the edited hunks and a code, and exits 0 only when that code is typed back; the record then shows the unit counted with `person:<name>` at `owner`, and a person line whose integrity tag doesn't check never counts.
- [ ] An overrule by an authority strictly higher than the acceptance's (`agent:<existing session>` at `coordinator` over a `reviewer` acceptance) makes `status` exit 1 with reason `overruled`; an overrule at the same authority exits 1 with rule `not-higher`; an agent at `coordinator` naming no existing koto session exits 1 with rule `unknown-session`, and the live fold re-checks that session rather than trusting the stored line.
- [ ] After an overrule, a new acceptance below the overruling's authority leaves the unit held, and one at or above it counts it again.
- [ ] An overrule against a run that already reached `done` is recorded in its retained session and rewrites that run's section of the pull request body.
- [ ] `test-change.sh record` prints the fix source, the red and green (or observations), each test file as added or edited, and every acceptance, decline, refusal and overruling with the unit's state; it works while held and after the run finished.
- [ ] `test-change.sh render` writes a section between `<!-- shirabe-test-change:<session>:start -->` and its end marker showing the output only as the lines around the marker, with home paths and token shapes redacted, free text flattened, and comment markers neutralised; a passage from a private repository's issue under a public pull request is omitted with the marker and output lines.
- [ ] `pr_precheck` re-runs `status` and holds when it no longer exits 0, and `check-pr-output.sh` refuses a body whose section is missing or differs from `render`.
- [ ] A commit that edits a test while fixing CI on the open pull request reaches `ci_pass_counting` when CI passes and is held there until accepted, then goes on to `cascade_entry` or `done`.

**Check**: Run `bash skills/work-on/scripts/test-change-routes_test.sh` and see it pass its person-required, overrule and `ci_pass_counting` cases: the agent's accept refused with `person-required`, a pseudo-terminal person accept counting the unit at `owner`, a `coordinator` overrule holding it as `overruled`, a same-authority overrule refused `not-higher`, and a CI-fix test edit held at `ci_pass_counting`. Then run `bash skills/work-on/scripts/test-change_test.sh`, `bash scripts/lib/acceptance-rule_test.sh` and `bash skills/work-on/scripts/check-pr-output_test.sh` and see each exit 0.

**Dependencies**: Step 2

**Files**: `skills/work-on/koto-templates/work-on.md`, `skills/work-on/koto-templates/work-on.mermaid.md`, `skills/work-on/SKILL.md`, `skills/work-on/scripts/test-change.sh`, `skills/work-on/scripts/test-change_test.sh`, `skills/work-on/scripts/test-change-routes_test.sh`, `skills/work-on/scripts/check-pr-output.sh`, `skills/work-on/scripts/check-pr-output_test.sh`, `skills/work-on/scripts/ci-monitor-role_test.sh`, `skills/work-on/scripts/cascade-chaining_test.sh`, `skills/work-on/scripts/leg-result_test.sh`, `skills/work-on/references/red-first.md`, `skills/work-on/references/phases/phase-5-finalization.md`, `skills/work-on/references/phases/phase-6-pr.md`, `skills/work-on/evals/evals.json`, `scripts/lib/acceptance-rule.sh`, `scripts/lib/acceptance-rule_test.sh`, `scripts/lib/claude-md-header.sh`, `references/fixes/claude-md-conventions.md`, `references/rule-registry.json`

### Step 4: review floors an edited test at full and every seat judges it

A change with an edited test floors at full, its packet lists edited and added tests apart with the edited hunks, every seat's verdict says corrects or weakens for each edited test, and the guidance stops offering a free test edit.

## Implementation Sequence

The steps run in order on one branch. Step 4 needs only step 1's classifier,
but runs after step 3 so each step's review sees the earlier ones in place.
