---
schema: prd/v1
status: Accepted
problem: |
  The finalization cascade's post-verification step seeds its lifecycle check
  on the PLAN the cascade deleted moments earlier, so the check returns L05 and
  every successful single-pr run reports cascade_status: partial. The step has
  never distinguished a cascade that finalized from one that did not, which is
  the only job it has, and no test exercises the branch it lives in.
goals: |
  The post-verification tells the truth in all three shapes a finished chain can
  take: an anchor survives, nothing survives because the chain folded, or the
  chain did not finalize. The third still fails, including the blocked-node case
  that currently reports itself as ok. CI executes the branch, so the next
  regression is caught in the pull request that causes it.
upstream: docs/briefs/BRIEF-cascade-post-verify-seed.md
motivating_context: |
  Filed three times independently over ten weeks (shirabe#186, shirabe#307,
  shirabe#328) without triage. The suite has eighteen scenarios and passes
  --push in none of them, so a deterministic defect stayed invisible to a green
  CI the whole time.
---

# PRD: Cascade post-verify seed

## Status

Accepted

Three jury rounds. Between them the reviewers constructed six wrong
implementations that satisfied the criteria as then written, and each round's
fix closed the family rather than the instance only after the next round showed
the instance patch was not enough. The findings that survived into the document
are the anchor precedence, the prohibition on disqualifying filters, AC6's and
AC8a's pinned fixtures, and R7a.

Two defects in `run-cascade.sh` were found by review rather than by the original
report and are recorded here because no `--push` scenario can be written without
them: `git commit` writes to stdout ahead of the report (R7a), and `delete_plan`
never enters the record (Known Limitations). Accepted under `/scope`'s
non-interactive mode on the round-three verdicts, with the two round-three
findings applied.

## Problem Statement

`skills/execute/scripts/run-cascade.sh` finalizes a completed chain and then
verifies its own work. The verification re-runs the chain-targeted lifecycle
check in ready posture, expecting a clean pass to confirm the chain reached its
terminal state.

That check is seeded on `$PLAN_DOC`, at `run-cascade.sh:296-300`, for both the
pre-cascade and post-cascade invocations. The pre-cascade seed is correct: the
PLAN is still on disk. The post-cascade one runs in the block at
`run-cascade.sh:906-914`, after line 873 has already `git rm -f`'d that exact
file and line 885 has committed the removal. The validator cannot canonicalize
the path, returns a single `L05` finding (`doc path not found or not
resolvable`) with exit 2, and the script — which branches on the exit code
alone, by its own comment at lines 280-282 — records the step as failed, sets
`ANY_FAILED=true`, and downgrades the run to `cascade_status: partial`.

The result is deterministic. Every `--push` cascade that deletes its PLAN
reports `partial` and attributes a bug to itself that it did not commit. A
verdict that is constant carries no information, so the step has never once done
the job it exists for.

What makes this more than a wrong path is what the step is supposed to catch.
`shirabe finalize-chain` has a retirement guard: when another document still
names a node as upstream, the node is blocked rather than transitioned. The
report marks it `blocked` with a `blocked_by` and omits `new_path`, but the
script reads neither field. It falls back to the un-moved path, stages it, and
records the step as `"ok"` with the block reason demoted to a `detail` string.
A cascade that silently failed to retire its DESIGN is therefore reported as a
clean run, and the post-verification is the only thing positioned to notice.
Seeded on the surviving DESIGN, it does notice — exit 2, with `[L01] DESIGN at
status 'Planned' (expected status 'Current' ...)`. Seeded on the deleted PLAN,
it notices nothing, because it fails identically whatever the chain did.

This is why the shortest available fix is the wrong one. Skipping the
verification when the PLAN is absent would silence the false failure, and the
PLAN is absent on every successful run — so it would silence the step
completely, and the blocked-node case would ship as `completed`.

The chain does not always leave an anchor. `/scope`'s consolidation judgment can
absorb a document into the one below it at any hop, and a PLAN whose only
upstream is a ROADMAP that the cascade then deletes leaves no chain document
standing at all. That is a complete chain with nothing to seed on, and it has to
read as success. A chain that never finalized also has no clean anchor, and has
to read as failure. Telling those apart is the substance of the work.

Nobody caught any of this because the branch is unreachable from the test suite.
`run-cascade_test.sh` has eighteen scenarios and passes `--push` in none of
them; the flag's only appearance in the file is a comment at line 500 noting its
absence. The post-verification is gated on `PUSH == true` with a non-empty
`STAGED_FILES`, so CI has never executed a single line of it.

## Goals

The verification step becomes trustworthy in both directions. A finalized chain
reports success, a chain that did not finalize reports failure, and the report
distinguishes them for whatever reads it.

The blocked-node case stops passing silently. The guard that exists to catch a
cascade that did not do what it claimed actually catches one.

A chain that legitimately folded every artifact away is treated as complete
rather than as a missing seed, and says which of the two it was.

CI executes the post-verification branch, so a change that reintroduces any of
the above fails in its own pull request rather than months later in a hand-run.

## User Stories

**As an author running `/execute` on a single-pr chain**, I want the run report
to say `completed` when my chain finalized cleanly, so that a `partial` verdict
means something and is worth reading.

**As an author whose chain did not finalize**, I want the run to fail and name
the step that did not land, so that I am told about my chain rather than about
the verification's own seed.

**As an author whose `/scope` run folded every artifact away**, I want the run to
report success and say plainly that no chain document survived to check against,
so that I am not asked to account for an anchor that was never supposed to exist.

**As a maintainer changing `run-cascade.sh`**, I want the test suite to execute
the post-verification branch, so that breaking it fails CI on my pull request.

## Requirements

### Terms

A **chain document** is any artifact the cascade's chain walk touches: a BRIEF,
PRD, DESIGN, PLAN or ROADMAP. The **record** is `STAGED_FILES`, the array the
cascade appends to as it stages each transition — at `run-cascade.sh:497`,
`:577`, `:795`, `:802` and `:808`. (`CASCADE_DESIGN_PATH` at `:796` holds the
same value line 795 already appended, so it adds nothing to the set.) A
**candidate** is any path in the record. A candidate **survives** when it exists
on disk at the moment the verification runs, which is after the finalization
commit at `:885`. An **anchor** is the surviving candidate the post-cascade
verification seeds its lifecycle check on.

### Functional

**R1.** The post-cascade verification SHALL NOT seed on `$PLAN_DOC`. The
pre-cascade probe SHALL continue to seed on `$PLAN_DOC` unchanged: its
expected-failure semantics depend on the PLAN being present, and a clean
pre-probe still short-circuits the run to `cascade_status: skipped` with no
transitions performed (`run-cascade.sh:697-702`).

**R2.** The post-cascade verification SHALL select its anchor from the surviving
candidates in the record. A candidate qualifies if and only if it survives —
the existence test and nothing else. **No filename-prefix filter, document-type
filter, or "is this really a chain document" test may disqualify a surviving
candidate.** Type discrimination is permitted only to *order* survivors under
the precedence below: every survivor stays eligible, and whatever the order
leaves standing is the anchor. Every path in the record is a chain document by
construction, and an implementation that discards a surviving ROADMAP rather
than ranking it last reports no anchor for a chain whose ROADMAP is standing on
disk and validates clean.

Two classes make the existence test necessary rather than optional: candidates
the cascade recorded and then deleted (the ROADMAP at `:577`), which do not
qualify, and candidates it recorded without moving because the node was blocked
(`:795`), which **do** qualify and are how R5 is satisfied. The test SHALL be
evaluated where the verification runs, not cached from before the `git rm` at
`:873` or the commit at `:885`.

Selection order among survivors SHALL be: the surviving DESIGN, else the
surviving PRD, else the surviving BRIEF, else the surviving ROADMAP. The rungs
are document types, not path or status tests — a blocked DESIGN sits at
`docs/designs/DESIGN-<slug>.md` rather than its terminal path and is still the
first rung, which is how R5 is satisfied.

The order does not change the verdict among tactical members: chain-targeted
validation reports every member of the chain, so a BRIEF, PRD or DESIGN anchor
yields the same findings, measured on both a clean chain and a blocked one.

A ROADMAP anchor is different, and ranking it too high is the more damaging
error rather than the lesser one. It sits above the chain and carries sibling
features whose own in-flight PLANs surface as `L01` against it — measured: on a
cleanly finalized `PLAN → PRD → BRIEF → ROADMAP` chain whose ROADMAP has an
in-flight sibling, the PRD and BRIEF anchors return clean while the ROADMAP
anchor returns `L01` and would produce the very false `partial` this PRD removes.
The ROADMAP is therefore the last resort, used only when no tactical member
survives, and AC8a is the criterion that holds the line.

**R3.** When at least one candidate survives, the verification SHALL run the
chain-targeted check in ready posture against the selected anchor and SHALL
require a clean pass. A non-clean result SHALL record the `lifecycle_post_verify`
step as `failed` and set `ANY_FAILED=true`, so the run reports `partial`. The
failed step's `detail` SHALL carry the validator's findings summary, so the
finding codes remain readable in the report.

**R4.** When no candidate survives, the verification SHALL treat the chain as
complete. The `lifecycle_post_verify` step SHALL be recorded with status
`skipped` and a detail containing the literal phrase `no recorded chain document
survived to verify against`. The word "recorded" is load-bearing: the claim is
scoped to the record, and a chain document can exist on disk without entering it
— an `error`-action node leaves its document unstaged, and the deleted PLAN was
never appended at all. It SHALL NOT set `ANY_FAILED=true`, SHALL NOT report `L05`,
and SHALL NOT record `ok` — a run that verified nothing must not be reported as
one that verified something.

**R5.** The verification SHALL fail a run whose DESIGN was blocked by
`finalize-chain`'s retirement guard and left un-transitioned on disk. It SHALL
do so without reading `blocked` or `blocked_by` from the report: the blocked
DESIGN survives at its un-moved path, qualifies as a candidate under R2, and
ready-posture chain validation fails it with `L01`.

**R6.** The change SHALL NOT rescue a run that already failed. The five sites
that set `ANY_FAILED=true` before the verification runs — `run-cascade.sh:579`,
`:827`, `:832`, `:850`, `:876` — SHALL remain in force, and the verification
SHALL NOT clear `ANY_FAILED` on any path. A run that reached any of those sites
SHALL still report `partial` even when the post-verification itself passes.

**R7.** The verification's step entry SHALL record the anchor it used in its
`target` field on every branch, or an explicit null when no candidate survived.
It currently hardcodes `$PLAN_DOC` at `:909` (the failed arm) and `:912` (the ok
arm), which after this change would name a document the verification did not
check. Emitting a null requires `add_step` to build `target` with `--argjson`,
the treatment `found_in` already gets at `:334-337` and `:350`; `--arg` at
`:348-349` always yields a JSON string.

**R7a.** In a `--push` run, the JSON report SHALL be the only thing the script
writes to stdout. `git commit` at `:885` currently writes its summary there
ahead of `emit_result`, so the captured output is not parseable JSON and every
`--push` assertion resolves to a parse error. The fix is `git commit -q` in
`run-cascade.sh`; it is carved out of R8 explicitly. This is a fourth defect in
the same function — the script's usage block already promises "Output: JSON to
stdout", and under `--push` it has never kept that promise — and it is in scope
here only because no `--push` scenario can assert anything without it.

**R8.** The change SHALL NOT alter which documents the cascade transitions, the
order it transitions them in, the contents of the finalization commit, or the
run-level `cascade_status` vocabulary (`completed` / `partial` / `skipped`). The
per-step `status` vocabulary gains no new value — R4 reuses `skipped`, already
in use at `:404`, `:414`, `:564` and `:698` — and is otherwise unchanged.
Suppressing `git commit`'s stdout summary per R7a is not an alteration of the
commit's contents and is permitted.

**R9.** The change SHALL NOT alter the `L06` / `WORK_ON_ALLOW_UNTRACKED_ACS`
suppression path, and SHALL NOT alter the `--lifecycle-chain` CLI surface. No
tolerate-missing-seed mode exists in the validator and none SHALL be added; the
fix is caller-side.

**R10.** The three open reports of this defect SHALL be triaged. **shirabe#186
is canonical** — it is the oldest and the only one carrying the `bug` label, so
it is the one already in the repo's triage queries. shirabe#307 carries the
fullest diagnosis but states in its Impact section that `cascade_status` still
comes back `completed`, which is wrong; making it canonical would enshrine that
claim as the record. The pull request SHALL reference shirabe#186 so merging
closes it, and shirabe#307 and shirabe#328 SHALL be closed as duplicates
pointing at it. The two adjacent defects under Known Limitations SHALL be filed
as their own issues rather than folded into this change.

### Non-functional

**R11.** Both `run-cascade.sh` and `run-cascade_test.sh` SHALL remain executable
under bash 3.2. The macOS CI leg runs both on that floor via
`scripts/check-bash-floor.sh --backend system execute`. Negative array
subscripts (`${arr[-1]}`), associative arrays, `mapfile`, namerefs, `${var,,}`,
and `[[ -v ]]` are unavailable; `"${arr[@]}"` on an empty array under `set -u`
requires the existing `${arr[@]:+...}` guard.

**R12.** The verification SHALL reach no network. It is a local validator call
against the working tree, and it SHALL stay one — no remote lookup, no `gh`, no
issue-state query. Separately, and because the two are easy to conflate: no new
test scenario may set an `https://` origin or invoke `gh` either, per R14's last
clause. That clause constrains the harness; this requirement constrains the
production path.

**R13.** `run-cascade_test.sh` SHALL gain `--push` scenarios covering the six
fixture shapes AC1, AC3, AC4, AC5, AC6 and AC7 name, plus a seventh scenario for
AC8 that reuses AC1's shape under the pass-through logging stub. None rides on an
existing scenario: every current scenario is a dry run. AC8 needs a scenario of
its own rather than an assertion bolted onto AC1's, because the stub changes what
the run observes. AC2 is a cross-cutting assertion over all of them, and AC9
rides on the existing `scenario_pre_probe_already_terminal`. Every new scenario
SHALL establish an
upstream-tracking branch with `git push -u origin HEAD` after `commit_all`:
`setup_test_repo` creates a file-based bare origin but sets no tracking branch,
so the cascade's bare `git push` at `:886` dies under `set -euo pipefail` and
the script emits no JSON at all. A scenario needing the script's exit code SHALL
invoke `bash "$CASCADE_SCRIPT"` directly, as `scenario_idempotency` does —
`run_cascade` discards stderr and swallows the code via `|| true`.

**R14.** Fixture shapes are constrained as follows.

A scenario asserting a clean verification SHALL use one PLAN per chain:
chain-targeted ready-posture validation reports every member, so a sibling PLAN
legitimately in flight surfaces as an `L01` against the anchor.

The no-anchor scenario (AC3) SHALL use a PLAN whose only upstream is a ROADMAP
built with `write_roadmap_done_single` and **no embedded issue URLs**, so the
issue grep yields nothing, `check_issue_closed` is never called, `all_closed`
stays true, `handle_roadmap_deletion` deletes the ROADMAP, and the record is left
holding one path that no longer exists. Do not copy
`scenario_deletion_all_done_all_closed`, which embeds URLs and installs a `gh`
stub the last clause of this requirement forbids.

The non-DESIGN-anchor scenario (AC4) SHALL use BRIEF at `Accepted` with no
upstream, then PRD at `Accepted`, then PLAN — no ROADMAP and no DESIGN.

The surviving-ROADMAP scenario (AC7) SHALL use the
`scenario_plan_roadmap_no_design` shape with `write_roadmap`, so Feature 2 stays
`Planned`, the deletion branch never fires, and the ROADMAP is rewritten and
staged at `:497` rather than removed.

The blocked-DESIGN scenario (AC5) SHALL use two single-pr PLANs naming one
shared DESIGN, with the cascade run on the first. The second PLAN at `Draft`
still names the DESIGN as upstream, so `finalize-chain`'s retirement guard
returns `blocked: true` with no `new_path` and the DESIGN stays at `Planned` in
`docs/designs/`. This is the one scenario that needs two PLANs; the
one-PLAN-per-chain clause above binds only clean-verification scenarios.

The pre-probe-argv scenario (AC8) SHALL reuse AC1's chain shape under the
pass-through logging stub, so the run reaches the verification and both validate
calls are observable.

The earlier-failure scenario (AC6) SHALL use PLAN, then DESIGN, then an upstream
that exists on disk but carries an unrecognized filename prefix — a
`docs/notes/NOTE-<name>.md`. `finalize-chain` exits 0, the DESIGN transitions and
stages so the commit and the verification both fire, and the second node returns
`action: "error"`, which sets `ANY_FAILED=true` at `:827`. The error node MUST
sit above a node that staged successfully; a fixture whose failure empties the
record leaves the verification unreached and the criterion vacuous.

No new scenario SHALL set an `https://` origin or invoke `gh`. The bash 3.2
floor image ships only jq, git and python3, so a stray `gh` call fails the macOS
leg specifically. Note that `GH_STUB_DIR` is a never-unset global: once any
deletion scenario sets it, later scenarios inherit a `PATH` prefix pointing at a
deleted directory, so "gh is never invoked" must be a property of the fixture
rather than of the environment.

## Acceptance Criteria

- [ ] **AC1.** A `--push` cascade over a single-pr chain with a surviving DESIGN
  reports `cascade_status: completed`, with `lifecycle_post_verify` at status
  `ok` and its `target` equal to the DESIGN's post-move path
  (`docs/designs/current/DESIGN-<slug>.md`). Fixture: `write_roadmap` (Feature 2
  stays `Planned`, so the deletion branch never fires and `gh` is never reached)
  plus DESIGN plus PLAN.
- [ ] **AC2.** No step in any new `--push` scenario carries the detail substring
  `not found or not resolvable`, and none reports `L05`.
- [ ] **AC3.** A `--push` cascade whose chain left no surviving document reports
  `cascade_status: completed`, with `lifecycle_post_verify` at status `skipped`,
  a detail containing `no recorded chain document survived to verify against`,
  and `target` equal to `null`. Fixture per R14.
- [ ] **AC4.** A `--push` cascade over a chain with no DESIGN but a surviving PRD
  and BRIEF at `Done` reports `lifecycle_post_verify` at status `ok`, not at
  `skipped`, with `target` equal to `docs/prds/PRD-<slug>.md` per R2's ordering.
  Fixture per R14. This is the criterion a DESIGN-only anchor implementation
  fails.
- [ ] **AC5.** A `--push` cascade whose DESIGN was blocked by the retirement
  guard reports `cascade_status: partial` with `lifecycle_post_verify` at
  `failed`, and its detail contains `DESIGN at status 'Planned' (expected status
  'Current'` and does **not** contain `not found or not resolvable`. The
  scenario also asserts on the filesystem that `docs/designs/DESIGN-<slug>.md`
  is still at `status: Planned` and `docs/designs/current/` does not exist. The
  detail matcher is pinned to the DESIGN-specific finding because this fixture
  also produces an `L01` for the legitimately in-flight sibling PLAN, so
  matching on `[L01]` alone would pass an implementation that noticed only the
  sibling. The step's `target` equals the un-moved
  `docs/designs/DESIGN-<slug>.md`, not the deleted PLAN.
- [ ] **AC6.** A `--push` cascade in which an earlier step fails and the
  post-verification passes still reports `cascade_status: partial`, with
  `lifecycle_post_verify` at `ok`. Fixture per R14 — an `error`-action node
  sitting above a DESIGN that transitioned cleanly. This is the criterion an
  implementation that clears `ANY_FAILED` on a passing verification fails, and
  it is worthless if its fixture cannot reach the verification, so the fixture
  is pinned rather than suggested.
- [ ] **AC7.** A `--push` cascade over a PLAN whose only upstream is a surviving
  ROADMAP reports `lifecycle_post_verify` at `ok` with `target` equal to
  `docs/roadmaps/ROADMAP-<slug>.md`, not `skipped`. Fixture per R14. This is the
  criterion an anchor filter that drops `ROADMAP-` fails.
- [ ] **AC8.** In a `--push` run that reaches the verification, the argv of the
  **first** `validate --lifecycle-chain` call contains the PLAN path and the argv
  of the **second** does not, containing the anchor instead. This pins R1's
  pre-cascade half. Neither existing stub variant can host it: the argv-logging
  variant at `run-cascade_test.sh:950-965` pins the validate exit to 0, which
  short-circuits the run after a single call, and `setup_shirabe_stub`'s
  `validate-exits.txt` sequencing fakes both probes. A pass-through logging
  variant is required — log `$*`, then `exec` the real binary unconditionally.
- [ ] **AC8a.** A `--push` cascade over a chain with a ROADMAP, no DESIGN, a
  surviving PRD and BRIEF, and a legitimately in-flight sibling PLAN under a
  second ROADMAP feature reports `cascade_status: completed` with
  `lifecycle_post_verify` at `ok` and `target` equal to `docs/prds/PRD-<slug>.md`.
  This is the criterion any misordering that ranks the ROADMAP above a tactical
  member fails: seeded on that ROADMAP the check returns `L01` for the sibling
  PLAN and the run reports the exact false `partial` this PRD exists to remove.
  Fixture: AC4's chain plus `write_roadmap`'s Feature-2 PLAN.
- [ ] **AC9.** The pre-cascade probe's behaviour is unchanged: a chain already at
  its ready-posture terminal still yields `cascade_status: skipped` with no
  transitions performed.
- [ ] **AC10.** Every new scenario is registered in the runner block.
  Registration is manual and a function without a call line is silently a no-op.
- [ ] **AC11.** *(Process criterion — verified by a reviewer, not by CI.)* Each
  new assertion of post-verify behaviour was shown to fail against the unfixed
  script. The pull request body states the exact one-line mutant used (restoring
  `--lifecycle-chain "$PLAN_DOC"` at the post call site), names the scenarios
  that fail under it, and pastes their `FAIL:` lines, so a reviewer can apply the
  mutant and re-run in one step. AC9 is excluded: it asserts unchanged behaviour
  and is unaffected by the mutant by design. AC8 is **not** excluded — its first
  half (the pre-cascade call carries the PLAN) is unchanged by the mutant, but
  its second half (the post-cascade call does not) is one of the strongest
  detectors in the set, since restoring the PLAN seed is exactly what the mutant
  does.
- [ ] **AC12.** The whole suite passes, and passes on the bash 3.2 floor via
  `scripts/check-bash-floor.sh execute` (which resolves to the docker backend
  locally; R11 cites the `--backend system` form because that is the macOS CI
  leg verbatim). Suite-wide passage is what carries R8 and R9: the existing
  eighteen scenarios pin the transitions and the `cascade_status` vocabulary, and
  `scenario_allow_untracked_acs_env_forwarded` and
  `scenario_allow_untracked_acs_default_off` are the `L06` path's regression
  guard.
- [ ] **AC13.** *(Process criterion.)* The pull request references shirabe#186 so
  merging closes it; shirabe#307 and shirabe#328 are closed as duplicates
  pointing at it; and the two defects under Known Limitations are filed as their
  own issues.

## Out of Scope

Everything the upstream BRIEF's Scope Boundary excludes, unchanged — see
`docs/briefs/BRIEF-cascade-post-verify-seed.md`. Two exclusions are this PRD's
own:

- **Teaching the script to read `blocked` / `blocked_by` from the finalize-chain
  report.** R5 requires the blocked-node case to be caught, and an anchored
  verification catches it without the script learning a new field. Reading the
  guard fields is a cleaner fix to a different defect and belongs in its own
  change.
- **The two adjacent defects under Known Limitations.** Both are real, both are
  outside this PRD's problem, and R10 routes them to their own issues rather
  than folding them in.

## Known Limitations

**`delete_plan` never registers in `STAGED_FILES`.** `run-cascade.sh:873-879`
performs the `git rm` without appending to the array, so a chain whose only
action is the PLAN deletion leaves the record empty. Both the commit at line 883
and the verification at line 906 are gated on that array being non-empty, so
such a run stages the deletion and never commits it, even under `--push`.
Reproduced. This bounds R14: a no-anchor scenario cannot be built on a
no-upstream PLAN, because that shape exercises neither the commit nor the
verification.

**`git commit` and `git push` are unguarded.** At `run-cascade.sh:885-886`,
under `set -euo pipefail` with no trap installed, a push failure aborts the
script before `emit_result` and the run produces no JSON on stdout at all.
Reproduced at rc 128. This is why R13 requires a scenario to establish tracking
rather than relying on the cascade to survive a failed push.

**An anchored verification inherits the chain's own false-positive surface.**
Ready-posture chain-targeted validation reports every member of the chain, so a
sibling PLAN that is legitimately in flight appears as an `L01` against the
anchor. This is not new — the old seed sat in the same chain — but it is why R14
constrains fixture shape, why AC5 pins its matcher, and why R2 prefers tactical
members over a ROADMAP, whose sibling features widen the surface further.

## Decisions and Trade-offs

**Where the anchor is read from.** The BRIEF deferred this. Decided: from the
cascade's own record, filtered by an on-disk existence test — not recomputed
from the chain's canonical paths. Recomputation was rejected because it would
have to reconstruct the slug-to-path mapping the cascade already holds, and
would not know which candidates the cascade deleted. The existence filter is
required on the chosen option for a separate reason: the record can contain a
path that was just `git rm`'d (`:577`) and a path staged but never moved because
the node was blocked (`:795`), and only an on-disk test separates a genuine
survivor from the first while keeping the second.

**What separates "folded away" from "never finalized".** The BRIEF's stance was
that the cascade holds evidence the after-the-fact check does not. Decided, and
the answer is structural rather than a variable to read: **a run that reaches
the verification with no surviving candidate has either folded or already
failed.** Every non-finalizing path either sets `ANY_FAILED` before the
verification (the five sites in R6) or leaves the record empty so the
verification never executes at all. The "already failed" limb is not slack: a
`git rm` failure at `:876` on a PLAN-and-ROADMAP chain leaves the record holding
only the deleted ROADMAP, so the verification runs and finds no survivor on a
chain that folded but did not finalize. R6 forbids clearing `ANY_FAILED`, so
that run still reports `partial`, which is why the no-anchor path can treat its
own case as complete without rescuing anything. An earlier draft named `FINALIZE_RC` as the discriminator; that was wrong.
All five record-append sites sit inside the node loop that is skipped when
`FINALIZE_RC != 0` (the `else` at `:847`), and the verification is gated on the
record being non-empty, so `FINALIZE_RC` is provably `0` wherever it would be
read. Following it literally produces an always-true branch. The structural
statement is strictly stronger, and R6 exists to protect the invariant it rests
on rather than leaving it assumed.

**Why not branch on the `L05` finding code instead.** The validator's seed gates
short-circuit and return exactly one `L05` finding, so `L05` can never mix with
`L01` in one envelope, and a consumer could tell "seed missing" from "chain not
finalized" by reading `findings[].code` while still seeding on the PLAN.
Rejected: it would make the verification pass on a missing seed, and the PLAN is
missing on every successful run, so an `L05`-tolerant check seeded on the PLAN
verifies nothing at all — the blocked-node hole in R5, reopened. The
finding-code distinction is real and worth knowing; it is not a fix.

**Which issue is canonical.** Settled in R10 rather than left to the
implementer. shirabe#186 over shirabe#307 despite #307's fuller writeup, because
#307's Impact section claims `cascade_status` still comes back `completed` and
it does not — `ANY_FAILED=true` routes to `partial` at `:936-941`.

**Assertion matchers and fixtures are pinned in the criteria, not left to the
design.** AC3's status token, AC5's detail substring, AC11's mutant and every
new scenario's fixture shape are named. The alternative — describing the intent
and letting the implementer choose — is what made an earlier draft's AC3
unwritable, let a `contains("[L01]")` matcher pass an implementation that
noticed only a sibling PLAN, and pointed AC6 at a fixture that cannot reach the
verification at all.

**Criteria are written to the requirement, not to the counterexample.** Two
review rounds each produced a wrong implementation, and patching the criteria to
kill those two instances left a third alive: an anchor filter keeping
`BRIEF-`/`PRD-`/`DESIGN-` and dropping `ROADMAP-` satisfied every criterion while
reporting no anchor for a chain whose ROADMAP was on disk and validated clean.
R2's prohibition on type filters closes the family; AC7 covers the instance.

## References

- `skills/execute/SKILL.md` — the seed-doc rule under the Finalization-Not-Done
  Guard, which states the behaviour the script contradicts.
- `skills/execute/scripts/run-cascade.sh` — `lifecycle_probe()` at 289-321, the
  `git rm` at 873, the verification block at 906-914.
- `skills/execute/scripts/run-cascade_test.sh` — the suite, `setup_test_repo` at
  245-257, the argv-logging stub at 950-965.
- `.github/workflows/check-execute-scripts.yml` — the CI job, including the
  bash 3.2 floor leg.
- `crates/shirabe-validate/src/lifecycle.rs` — seed-path gates at 1706-1816,
  posture re-targeting at 930-936.
- `crates/shirabe-validate/src/finalize.rs` — the report shape at 159-193 and
  the retirement guard at 836-870.
