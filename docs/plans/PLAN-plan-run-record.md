---
schema: plan/v2
status: Active
execution_mode: single-pr
split_mode_source: none
tracking_level: none
upstream: docs/designs/DESIGN-plan-run-record.md
milestone: "A plan's run outlives the plan as its record"
step_count: 8
---

# PLAN: A plan's run outlives the plan as its record

## Status

Active

## Scope Summary

A merged PR's repository and number lead, through one index session per PR in the koto
store, to the session that ran its plan and to every PR the plan produced. The run's
sessions hold a per-step trail (the PLAN as each step began, each step session, departures
and decisions with their actor) and are pinned through koto's session pin before each
qualifying terminal. PRs carry no workflow content unless the repository opted in, and the
lifecycle documents state one lifecycle and send a reader to the lookup. Everything lands in
one shirabe PR and touches no file under `skills/coordinate/`.

Three things this plan builds against but doesn't build. koto's session pin (koto#441)
ships in two parts, neither released yet: koto#444 (pin and unpin, prune keeping pinned
sessions, the removal guard at every removal point, reporting, unreadable pins, the start hook
recording authority) and the pin's cloud follow-up, a later koto PR (the bucket check before
every delete, keeping across hosts, import). `RECORD_PIN_FLOOR` and `RECORD_PIN_CLOUD_FLOOR`
stay unset and step 6 is proved against the stub koto, built from the pin's PRD as written.
Once koto#444 ships, step 6's same-host checks (pinning at `record_keep`, refusal and retry,
`kept_by_pin` in a same-host prune, cleanup refusing a pinned session) can also run against a
real koto; its cross-host checks (a second host's prune or cleanup keeping the sessions, a
failed bucket check keeping them, a pin surviving import) wait on the cloud follow-up. The workspace option the design calls K2 is koto#455,
read-only and built outside this plan: the index is written from a fixed directory, and
reads pass `--workspace` only once the installed koto accepts it, falling back to running
from the addressed directories, which works on the run's own host. The end-to-end
walkthrough from a fresh workspace on another host with no local copy, against a real koto and
a real bucket, covering the lookup and a removal there, rests on K2 and on the pin's cloud
follow-up, and is not a step here.

No step here, teardown included, posts a run record, pin result or cost entry to a public pull
request; with the opt-in off, all of it stays in the run's session.

## Decomposition Strategy

Walking skeleton. Step 1 runs one stub-backed single-pr run's home PR through
`adopt-or-create-pr.sh`, `scripts/run-trail.sh`, `scripts/lib/record-store.sh` and the stub
koto, then looks the PR up from a different directory with `scripts/run-record-lookup.sh`,
which confirms the PR in the root's own list. Each later step adds one behaviour a reader or
a test can see on top of that path: the per-step trail, the right run after a re-run or an
adoption, the coordinated record, the multi-pr plan root, pins, the PR content rules, and the
lifecycle statement. Each step carries the tests and documentation its behaviour needs.

## Steps

### Step 1: a single-pr run's home PR leads back to its record root from a fresh directory

**Goal**: Open the first end-to-end path through the run record: `adopt-or-create-pr.sh` writes the home PR and its index entry through `scripts/run-trail.sh` (`pr`, `index` and `self` verbs) and `scripts/lib/record-store.sh` into the stub koto (`scripts/testdata/record-koto/koto`), and `scripts/run-record-lookup.sh` reads it back. The input is one stub-backed single-pr run with one home PR, recorded in workspace A and looked up from a different directory B. `record-store.sh` writes the index from the fixed directory `/tmp/shirabe-run-record/<owner>` (created, entered in a subshell, no address option on any write) and reads through koto's read-only `--workspace` option only when the installed koto accepts it on a read verb (probed from koto's help once per process); otherwise it reads from the addressed directory, trying both canonical forms of the fixed directory (`/tmp/...` and `/private/tmp/...`). The stub models both a koto with the option (reads only; writes given it are refused) and one without.

**Acceptance Criteria**:

- [ ] After a single-pr run records its home PR in workspace A, `run-record-lookup.sh <owner/repo> <n>` run from directory B exits 0 and prints JSON naming the record root `execute-<topic>`, its workspace (A), the `run_id`, `complete: true` and a PR list holding exactly that one PR with its state.
- [ ] When the PR's index entry names a session whose own `trail/pr/*` list doesn't include the PR, the lookup doesn't return that session and exits 3.
- [ ] The lookup exits 3 for a PR with no index entry, 2 when the stub fails the store read, and 64 for `owner` without a repository, for a PR number of `0` and for a non-numeric one; each prints a message on stderr saying which case it hit.
- [ ] After a lookup from directory B, the stub's call log contains no write, no import and no migration marker from the lookup.
- [ ] No write the run makes through `record-store.sh` carries `--workspace`: the stub, in its option-present mode, refuses any write given it (as koto#455 specifies), and the skeleton case still passes in that mode. In option-absent mode the lookup from B still succeeds by reading from the addressed directories, and the stub's log shows no `--workspace` on any call; in option-present mode the log shows `--workspace` on the lookup's reads.
- [ ] With a stub `gh` that fails every call, the lookup returns the same JSON and exit code as with a working `gh`.
- [ ] `scripts/check-bash-floor.sh` passes for the new suites (`record-store_test.sh`, `run-trail_test.sh`, `run-record-lookup_test.sh`) on the bash 3.2 floor, and the `check-run-record` workflow runs them.

**Check**: Run `bash scripts/run-record-lookup_test.sh`. Its skeleton case records a single-pr run's home PR in workspace A through `adopt-or-create-pr.sh` against the stub koto, then runs the lookup from a different directory B. Look for exit 0 and JSON with the record root `execute-<topic>`, workspace A, the run_id and exactly one PR, followed by the suite's pass line. Then run `bash scripts/check-bash-floor.sh` and look for a pass on the new suites.

**Dependencies**: None

**Files**: `scripts/run-trail.sh`, `scripts/lib/record-store.sh`, `scripts/run-record-lookup.sh`, `scripts/testdata/record-koto/koto`, `scripts/record-store_test.sh`, `scripts/run-trail_test.sh`, `scripts/run-record-lookup_test.sh`, `skills/execute/scripts/adopt-or-create-pr.sh` and its test, `skills/execute/scripts/execute-open.sh` and its test, `.github/workflows/check-run-record.yml`, `scripts/bash-floor/run-record.list`. No file under `skills/coordinate/`.

### Step 2: the record holds the PLAN as each step began, each step session, departures and decisions with their actor

**Goal**: From a single-pr run's record root, `run-record-lookup.sh --steps` and `koto context get` show, for each step (step 1 included), the PLAN text and commit SHA as handed off and the step session's name. In the step sessions they show every departure against its step and every decision with its actor. This is built from `run-trail.sh`'s `plan`, `step`, `departure` and `decision` verbs, the hooks in the lead shape of `skills/execute/koto-templates/execute.md`, `/work-on`'s decision, deviation, deferral and scope-change sites, and the `trail/` carry in `skills/execute/scripts/execute-open.sh`. Step 1 left `run-record-lookup.sh`'s `steps` as an empty placeholder, wrote `trail/self` only on single-pr opens (`run-trail.sh index` also writes it when the root has none), and carries no `trail/` keys across a replace; this step fills `--steps` and adds the carry. It also folds the value patterns, which step 1 defined in both `run-trail.sh` and the lookup, into `scripts/lib/record-store.sh`, and makes the shared-address read fall through a "not found" on an unused canonical form.

**Acceptance Criteria**:

- [ ] `run-trail.sh departure` and `run-trail.sh decision` take their text only as one JSON document on stdin. Text passed as an argument, or a stdin document that isn't valid JSON or lacks the verb's required fields, exits 64 or 65 and writes no key.
- [ ] `run-trail.sh plan --plan <path>` with a path outside `docs/plans/PLAN-<topic>.md` (for example `../secrets.md` or `docs/plans/sub/PLAN-x.md`) exits 65 and writes nothing. A valid path stores the PLAN's committed text and a `{sha, entry, recorded_at}` record under the step.
- [ ] A departure or decision value holding a token shape (for example a `ghp_` string) or a private-key header exits 65 and writes nothing, including the copy `decision` would send through `koto decisions record`.
- [ ] In a three-step stub run where the PLAN is committed between steps 1 and 2, `run-record-lookup.sh --steps` shows three plan snapshots, step 1 included, and steps 1 and 2 carry different SHAs and texts. Each step also shows its step session's name, and a step that got a new step agent lists the earlier name as superseded.
- [ ] In the step sessions, the four departure kinds (`deviated`, `deferral`, `scope-change`, `entry-rewritten`) each appear against their own step with a non-empty why. A decision from an agent shows actor `agent:<name>`, and a human-approved deferral shows actor `person`.
- [ ] After a pause's replace, the replacement record root still holds the earlier `trail/` keys, because `execute-open.sh` carries `trail/` alongside the `run/` keys.
- [ ] `references/skill-session-convention.md` lists the `trail/` area with `scripts/run-trail.sh` as its writer, and the skill-session convention check passes.
- [ ] The value patterns (owner, repository, step id, session name, workspace) are defined once, in `scripts/lib/record-store.sh`, and both `run-trail.sh` and `run-record-lookup.sh` use them; a grep for each pattern's regex across `scripts/` finds it in that one file.
- [ ] With koto's workspace option present, a read of the shared address that gets "not found" from one canonical form of the fixed directory (`/tmp/...` or `/private/tmp/...`) goes on to the other, and the lookup still exits 0 for a PR indexed under the second form. Only a read that is unreadable (not "not found") under every form exits 2. The stub models a "not found" answer for an unused form.
- [ ] Every suite this step adds or changes that runs the real koto (`execute-open_test.sh` and any other) unsets every `KOTO_SESSION_*` variable and `KOTO_SESSIONS_BASE`, gives koto a temp `HOME` inside the suite, and before its first koto command asserts that `koto session dir` resolves under that temp directory, exiting non-zero before any case runs when it doesn't. Every suite that uses the stub koto (`record-store_test.sh`, `run-trail_test.sh`, `run-record-lookup_test.sh`) asserts before its first case that the `koto` on its `PATH` is the stub, failing closed otherwise.

**Check**: Run `bash scripts/run-trail_test.sh` and `bash scripts/run-record-lookup_test.sh`, both against the stub koto, and see every case pass. The trail cases to look for are the refusals above (exit 65, key list unchanged), the three-step run with two different SHAs, four departures each against its step, decisions with actors `agent:<name>` and `person`, and the trail still present after the replace. Then run `bash skills/execute/scripts/execute-template-structure_test.sh` and the `execute-open.sh` test and see them pass with the new hooks and carry in place.

**Dependencies**: Step 1

**Files**: `scripts/run-trail.sh`, `scripts/run-trail_test.sh`, `scripts/run-record-lookup.sh`, `scripts/run-record-lookup_test.sh`, `scripts/lib/record-store.sh`, `scripts/record-store_test.sh`, `scripts/testdata/record-koto/koto`, `skills/execute/koto-templates/execute.md`, `skills/execute/scripts/execute-open.sh` and its test, `skills/execute/scripts/execute-template-structure_test.sh`, `skills/work-on/koto-templates/work-on.md`, `skills/work-on/SKILL.md`, `skills/work-on/references/phases/phase-3-analysis.md`, `skills/work-on/references/phases/phase-4-implementation.md`, `skills/work-on/references/phases/phase-5-finalization.md`, `scripts/rule-dispute.sh` and its test, `references/skill-session-convention.md`. No file under `skills/coordinate/`.

### Step 3: a re-run or a later adopting run never makes the lookup return the wrong run

After a re-run moves the first root aside as `execute-<topic>_r1`, or a later run adopts the PR, the lookup returns the run whose entry names the PR, lists the others and reports `unique: false`.

### Step 4: every PR of a coordinated run leads to its record root, which lists all of them

Node, follow-up and coordination PRs of a coordinated run each resolve to its execute session, which lists all of them and its step sessions.

### Step 5: a multi-pr plan's item PRs lead to one plan-level record root

Each item PR of a multi-pr plan resolves to one plan-level root that lists every item's PR, including items that ran later.

### Step 6: a run that leaves its PRs ready or merged pins its evidence and reports any pin koto refuses

At each qualifying terminal the run pins its root, step sessions and index sessions through koto's session pin, reports and retries any pin left undone, and the retention reference says what is pinned and how to release it.

### Step 7: PRs carry no workflow content by default and an opted-in repository gets a session reference

Under omit no PR carries the run marker, run lines or a PR index and ownership holds through the index; under include Part 2 carries the session reference, read once per invocation, and the README states the opt-in and its checkout limit.

### Step 8: a stale lifecycle claim fails the rules check and every lifecycle document sends readers to the lookup

The plan, roadmap and pipeline references say a PLAN and a ROADMAP are deleted when their work finishes and name the lookup, and the rules check fails on the old stays-in-docs/plans and historical-record wording.

## Implementation Sequence

The steps run in order. Steps 3, 4 and 5 each need only what steps 1 and 2 built, so they
could run beside each other; step 6 needs the coordinated and multi-pr records in place, and
step 7 needs the index (steps 1 and 3) before it removes the marker the ownership lookup
reads today. The plan's owner details step 3 after step 2's work reaches its terminal, and
each later step the same way, from the PRD's acceptance criteria and the DESIGN's phase
deliverables, in a commit that touches only this plan.
