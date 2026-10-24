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
ships in two parts: koto#444 (pin and unpin, prune keeping pinned sessions, the removal guard
at every removal point, reporting, unreadable pins, the start hook recording authority),
released in koto 0.24.0, and its cloud half, koto#460 (the bucket check before every delete,
keeping across hosts, import), merged but not yet released. `RECORD_PIN_FLOOR` is 0.24.0, so
step 6's same-host checks (pinning at `record_keep`, refusal and retry, `kept_by_pin` in a
prune, cleanup refusing a pinned session) run against a real koto on a scratch local store as
well as the stub. Under the cloud backend koto 0.24.0 refuses a pin, which the run records and
retries; its cross-host checks (a second host's prune or cleanup keeping the sessions, a
failed bucket check keeping them, a pin surviving import) wait on koto#460's release. The workspace option the design calls K2 is koto#455,
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

**Goal**: `scripts/run-record-lookup.sh` returns the run that carried a PR when the PR's record root has since been replaced, or when more than one run has recorded the PR. Two cases. A re-run of the same topic: `koto init --replace-terminal` moves the finished root aside as `<name>_r<N>` (koto's own naming, `N` from 1 to 10), and every koto child named `<name>.<rest>` moves with it as `<name>_r<N>.<rest>`, so the index entry's session name now holds the new run and the old run's step-session names, as recorded in `trail/step/*`, are stale. A later run that records the same PR (an adoption or a takeover) writes its own `run/<run_id>` entry into the PR's index session beside the first. Steps 1 and 2 left the lookup with no `session_id` check and no predecessor search, so this step adds them, reading every session's id from `koto session list` through `record-store.sh`'s read path and using the value patterns already in `scripts/lib/record-store.sh`.

**Acceptance Criteria**:

- [ ] In a stub run where run 1 records PR 7 under `execute-<topic>` and a re-run replaces that root (the stub moves the root and its `.`-children to `_r1` the way koto does), `run-record-lookup.sh <owner/repo> 7 --steps` exits 0 and names the record root `execute-<topic>_r1`, run 1's `run_id`, and each of run 1's step sessions under its `_r1` name. A lookup for run 2's PR names `execute-<topic>`.
- [ ] When the index entry's `session_id` matches neither the named session nor any of `<name>_r1` to `<name>_r10`, the lookup returns no root and exits 3, with a message on stderr saying the recorded root wasn't found under its name or any moved-aside name.
- [ ] When two runs have index entries for one PR and both roots list the PR in `trail/pr/*`, the lookup returns the entry with the latest `written_at` (ties broken by `run_id`), prints `unique: false`, and lists the other `run_id` in `others`. An entry whose root doesn't list the PR is never returned and doesn't appear in `others`. With one qualifying entry, `unique` is `true` and `others` is empty.
- [ ] A `session_id`, `written_at` or session name read back that fails its pattern in `record-store.sh` is reported in `missing` and never used to choose a root or build a name.
- [ ] The lookup's koto calls for one PR, as the stub's call log counts them, stay within 2 + P + S + 1, where P is the run's PR count and S its step count (one `session list` call covers the predecessor search), and none of them is a write.
- [ ] `run-record-lookup_test.sh` keeps its check that the `koto` on its `PATH` is the stub before the first case, and every new case runs with the workspace option absent and present.

**Check**: Run `bash scripts/run-record-lookup_test.sh` against the stub koto and see every case pass: the re-run case naming `execute-<topic>_r1` with step sessions renamed, the not-found case exiting 3, the two-run case printing `unique: false` with the other `run_id` in `others`, and the call-count case. Then run `bash scripts/check-bash-floor.sh --backend system run-record` and see it pass on bash 3.2.

**Dependencies**: Step 2

**Files**: `scripts/run-record-lookup.sh`, `scripts/run-record-lookup_test.sh`, `scripts/testdata/record-koto/koto`, `scripts/lib/record-store.sh` and `scripts/record-store_test.sh` if a pattern or read helper is added. No file under `skills/coordinate/`.

### Step 4: every PR of a coordinated run leads to its record root, which lists all of them

**Goal**: A coordinated run's node PRs, follow-up PRs and coordination PR each resolve, through `scripts/run-record-lookup.sh`, to the run's record root `execute-<topic>`, and that root lists every one of them and every work item's step session. Steps 1 to 3 built this for a single-pr run only. On the coordinated path the run mints its `run_id` in `coord_setup` (`record-coord-setup.sh`), not at open, so `execute-open.sh` writes no `trail/self` there; this step writes it once `record-coord-setup.sh` has sealed or recovered the run's record. Each PR is recorded where the run already records it: `node-push.sh` after a node PR is opened or adopted (role `node`), `record-coord-setup.sh` for the coordination PR at setup (role `coordination`) and for a follow-up given `--follow-up` (role `follow-up`), each with `run-trail.sh pr` and then `run-trail.sh index` in the same step, before any later ownership lookup. The coordination PR lives in `home_repo` and a node PR in its own repository, so each index entry goes to its own owner's shared address. Before each `dispatch:<node>` work-item hand-off in `skills/execute/koto-templates/execute-coordinated.md`, the owning session records the PLAN snapshot (from `plan_abs`, the PLAN in the coordination checkout) and the step session `work-on-<slug>-<node>-<item>` with the node's worktree as its workspace, the same calls `execute.md`'s lead shape makes. A work item's child isn't a koto child of the root: it lives in the node's worktree and joins the root only by its dispatched-by link, so the root's `trail/step/*` is the only list of them. Two of step 3's advisories are folded in here because this step changes the lookup again: the `_r<N>` naming rule moves into `scripts/lib/record-store.sh`, and the lookup suite's header lists its cases.

**Acceptance Criteria**:

- [ ] In a coordinated run against the stub koto and the eval gh shim, with two node PRs in two repositories, one follow-up PR on the first node and the coordination PR in a third, `run-record-lookup.sh <owner/repo> <n>` for each of the four PRs exits 0 and names the same record root `execute-<topic>`, the same `run_id`, and a `prs` list holding exactly those four, each with its role and state.
- [ ] With `--steps`, the lookup lists one step per work item, each with its session `work-on-<slug>-<node>-<item>`, the node worktree's path as its workspace, and its PLAN snapshot taken from `plan_abs` before that item's hand-off.
- [ ] `trail/self` in a coordinated run's root holds the run's `run_id` and the coordination checkout as its workspace once `record-coord-setup.sh` has sealed a new record, and again after it recovers one.
- [ ] A follow-up removed with `--remove` stays in the root's `trail/pr/*` with state `closed` and its index entry is kept, so a lookup from that PR still reaches the run.
- [ ] The index entry for each PR is written in the same script call that records the PR in the run record (`node-push.sh`, `record-coord-setup.sh`), and a failed index write makes that call exit nonzero with a message naming the PR, never a silent success.
- [ ] `execute-coordinated-structure_test.sh` checks that the `dispatch:<node>` directive records the PLAN snapshot and the step session through `run-trail.sh` before each work-item hand-off.
- [ ] The `_r<N>` naming rule (`<name>_r1` to `<name>_r10`, and a `.`-child moving with its parent) is defined once, in `scripts/lib/record-store.sh`, and the lookup uses it from there. `run-record-lookup_test.sh`'s header lists every case it runs.
- [ ] Every suite this step adds or changes that runs the real koto (the coordinated engine suites included) unsets every `KOTO_SESSION_*` variable and `KOTO_SESSIONS_BASE`, gives koto a temp `HOME`, and asserts before its first koto command that `koto session dir` resolves under that directory, failing closed. Every stub suite asserts the `koto` on its `PATH` is the stub.

**Check**: Run `bash skills/execute/scripts/node-push_test.sh`, `bash skills/execute/scripts/record-coord-setup_test.sh`, `bash skills/execute/scripts/record-coord-follow-up_test.sh`, `bash skills/execute/scripts/execute-coordinated-structure_test.sh` and `bash scripts/run-record-lookup_test.sh`, and see every case pass, including the four-PR coordinated lookup and the removed follow-up. Then run `bash scripts/check-pipe-readers_test.sh` and `scripts/ablation/check-public-content.sh --diff origin/main --head HEAD` and see both clean.

**Dependencies**: Step 3

**Files**: `skills/execute/scripts/node-push.sh`, `skills/execute/scripts/record-coord-setup.sh` and their tests (`node-push_test.sh`, `record-coord-setup_test.sh`, `record-coord-follow-up_test.sh`), `skills/execute/koto-templates/execute-coordinated.md`, `skills/execute/scripts/execute-coordinated-structure_test.sh`, `skills/execute/references/step-agent-handoff.md`, `scripts/run-trail.sh`, `scripts/run-record-lookup.sh`, `scripts/lib/record-store.sh` and their tests, `scripts/testdata/record-koto/koto`. No file under `skills/coordinate/`.

### Step 5: a multi-pr plan's item PRs lead to one plan-level record root

**Goal**: Each item PR of a `multi-pr` plan, which runs through `/work-on` one item at a time with no `/execute` session, resolves through `scripts/run-record-lookup.sh` to one plan-level record root that lists every item's PR, items run later included. The root is the session `plan.<owner>.<repo>.<topic>.<sha12>` at the shared address (`<sha12>` is the first 12 hex digits of the commit that added the PLAN to the default branch, so a later plan reusing the topic gets a new root). It's opened from `koto-templates/skill-session.md` with the same attach-or-create call every item makes, never ticked, and it gets its own `trail/self` naming the shared address, because `run-trail.sh index` refuses (65) a root with no `trail/self` (step 4's rule). At the item's start in `/work-on` (`skills/work-on/koto-templates/work-on.md` and `references/phases/phase-6-pr.md`), a top-level multi-pr item run records, through `run-trail.sh`, the PLAN snapshot into the plan root (`plan --plan` takes the absolute path to `docs/plans/PLAN-<topic>.md` in the checkout that holds it, as step 4 added), the item through a new `item` verb (`trail/item/<step>`: `{session, workspace, pr}`, the item's own `/work-on` session in its own workspace, as `step --child-workspace` already records one), and, once its PR exists, the PR (`pr`, role `item`) and the PR's index entry (`index --mode multi-pr`) in the same step. The lookup's multi-pr branch confirms the PR through the root's `trail/item/*`. A plan-backed child of `/execute` does none of this; its parent records it. Step 4 also showed that the suites write their shared index directory under the real `/tmp/shirabe-run-record`, so concurrent suites collided there, and step 4 only stopped deleting it; this step gives `record-store.sh` a test-only override for that root, and every suite points it at a temp directory.

**Acceptance Criteria**:

- [ ] In a stub multi-pr run of a three-item PLAN in one repository, where item 1's PR is opened, then item 2's, then item 3's in a later invocation from a different workspace on the same host, `run-record-lookup.sh <owner/repo> <n>` for each of the three PRs exits 0, names the same root `plan.<owner>.<repo>.<topic>.<sha12>` at the shared address, and lists exactly the three PRs with role `item`. With `--steps` it lists the three items, each with its own `/work-on` session and workspace and the PLAN snapshot taken at that item's start.
- [ ] A second plan that reuses the topic after the first PLAN was deleted from the default branch gets a root with a different `<sha12>`, and a lookup of either plan's PRs never lists the other plan's PRs.
- [ ] The plan root's `trail/self` names the shared address and the root, and is written by the first item that opens the root; a later item's attach leaves it as it was.
- [ ] A PR whose index entry names the plan root but which no `trail/item/*` entry in that root holds is not returned, and the lookup exits 3, as step 1's rule has it for `trail/pr/*`.
- [ ] A `/work-on` run that is a plan-backed child of `/execute` writes no `item`, plan-root or index entry (its parent records it), shown by a stub case and by the work-on template's structure check.
- [ ] `scripts/lib/record-store.sh` reads the shared root from a test-only variable when it is set, documented as test-only in its header, and defaults to `/tmp/shirabe-run-record`. Every suite that writes through `record-store.sh` sets that variable to a temp directory, and none writes under `/tmp/shirabe-run-record`, which a check in `record-store_test.sh` asserts by listing the real directory before and after.
- [ ] Every stub suite asserts the `koto` on its `PATH` is the stub; every suite that runs the real koto clears `KOTO_SESSION_*` and `KOTO_SESSIONS_BASE`, uses a temp `HOME` and asserts `koto session dir` resolves under it before its first koto command.

**Check**: Run `bash scripts/run-trail_test.sh`, `bash scripts/run-record-lookup_test.sh` and `bash scripts/record-store_test.sh` against the stub and see every case pass, including the three-item lookup from a later workspace, the reused topic and the no-write check on the real shared directory. Run the work-on template structure suite and see the item hooks checked. Then run `bash scripts/check-pipe-readers_test.sh` and `scripts/ablation/check-public-content.sh --diff origin/main --head HEAD` and see both clean.

**Dependencies**: Step 4

**Files**: `scripts/run-trail.sh`, `scripts/run-record-lookup.sh`, `scripts/lib/record-store.sh` and their tests, `scripts/testdata/record-koto/koto`, `skills/execute/scripts/coord-test-helpers.sh` and `skills/execute/scripts/adopt-or-create-pr_test.sh` (the shared-root override), `skills/work-on/koto-templates/work-on.md`, `skills/work-on/references/phases/phase-6-pr.md`, the work-on template structure test. No file under `skills/coordinate/`.

### Step 6: a run that leaves its PRs ready or merged pins its evidence and reports any pin koto refuses

**Goal**: Before every terminal that leaves a plan's PRs ready or merged, the run pins the sessions that hold its evidence through koto's session pin, and any pin koto refuses is recorded and retried. A new script, `scripts/run-record-pin.sh --root <session> [--retry]`, makes one `koto session pin --reason <reason> <name>` call per session: the record root, every step session in the root's `trail/step/*` (never one listed as superseded), every index session holding this run's `run/<run_id>` entry, and, for a multi-pr item, the plan root (a repeat pin is idempotent), the item's own `/work-on` session and its index session. It decides what belongs to this run from local facts, not from names read back from the bucket alone: a single-pr step session is pinned only when it is the root's own koto child (`koto workflows --children`), a coordinated work-item session only when its dispatched-by link names the root (`koto session hierarchy`), and an index or plan root only when it holds this run's entry; every address comes from the run's own `trail/self` and `trail/step/*` records, and a write to the shared address runs from its directory through `record-store.sh`'s write path (no address option on any write). A session whose recorded workspace isn't on this host is recorded as unpinned with reason `other-workspace`, never skipped silently. The reason is `record of plan <topic>: <owner>/<repo>#<n>`, no control characters, at most 500 characters with the topic cut to fit; it holds no plan prose. The pin floor `RECORD_PIN_FLOOR` is koto 0.24.0, the release carrying koto#444, checked by version, because 0.24.0 hides `session pin` from its help; for the same reason neither skill's `requires.tsv` declares it. Under the cloud backend koto 0.24.0 refuses a pin until its cloud half (koto#460) is released, so every refusal (exit 2) or unconfirmed pin (exit 3) is written to the root's `trail/unpinned` key with koto's code, the terminal's `result:` says `record: unpinned` with the names, and the next invocation's opener (`execute-open.sh`, `work-on-open.sh`) reruns `run-record-pin.sh --retry`, which puts each name through the same provenance check before pinning it and removes `trail/unpinned` once every name is pinned. The pin runs in a new default-action state, `record_keep`, that never blocks the terminal: in `skills/execute/koto-templates/execute.md` and `execute-coordinated.md` before `merged` and `ready_awaiting_merge` (not `paused_awaiting_merges`, where not every PR is ready), and in `skills/work-on/koto-templates/work-on.md` before `done` only for a top-level multi-pr item whose PR is ready or merged (a plan-backed child skips it; its parent pins it). Steps 1 to 5 recorded each PR as `open` and never advanced it; this step records the PR's state where the run observes it change, through `run-trail.sh pr`: `ready` in `plan_completion` and when a coordinated node or the coordination PR is readied, and `merged` in `merge_confirm` and where the coordinated loop observes a merge. shirabe never calls `koto session unpin`. `references/koto-session-retention.md` gains a section saying which sessions shirabe pins, when, with what reason, that the pin keeps only that session, and how a pin comes off: by hand from a shell with no `KOTO_ANCHOR`, or from an agent session whose start was handed koto's `release-pin` authority. `scripts/check-run-record-rules.sh`, run by `.github/workflows/check-run-record.yml`, fails on any `koto session unpin` call in shirabe's skills and scripts, on any retention window shirabe defines itself, and on any cleanup or prune instruction in a skill whose paragraph doesn't say the pinned sessions are kept; it doesn't police `skills/coordinate/`, which another change edits. No step posts a pin result, run record or cost entry to a pull request.

**Acceptance Criteria**:

- [ ] Against the stub koto, a single-pr run reaching `ready_awaiting_merge` pins exactly the record root, each non-superseded step session and each of its index sessions, one pin call each, with the reason `record of plan <topic>: <owner>/<repo>#<n>`, and the stub's call log holds no `unpin` call. A coordinated run pins its root, every work-item session whose dispatched-by link names the root, and every PR's index session. A multi-pr item pins the plan root, its own session and its index session.
- [ ] A name in `trail/step/*` that is neither a koto child of the root nor dispatched by it, or an index session holding no entry for this run, is not pinned and is reported as skipped.
- [ ] When koto refuses a pin with exit 2 (as koto 0.24.0 does under the cloud backend) or answers exit 3, the run still reaches its terminal; `trail/unpinned` names each such session with koto's code, and the terminal's result says `record: unpinned`. The next invocation's opener retries them, pins those koto now accepts, and removes `trail/unpinned` once none is left.
- [ ] Below `RECORD_PIN_FLOOR` (a stub koto reporting 0.23.0) no pin call is made and the result says `record: unpinned`.
- [ ] Against a real koto 0.24.0 in a scratch `HOME` on the local backend, with a retention of zero set in that scratch store's config, a finished single-pr fixture run's root, step and index sessions are pinned at `record_keep`; `koto session prune --apply --all` in that scratch store keeps each of them with `kept_by_pin: true` and the reason, and removes a finished sibling session from the same fixture that holds no pin; `koto session cleanup` of the pinned root exits 2 and removes nothing. The suite clears `KOTO_SESSION_*` and `KOTO_SESSIONS_BASE`, uses the temp `HOME`, and asserts `koto session dir` resolves under it before its first koto command, failing closed. Nothing runs against the real store.
- [ ] A single-pr run's home PR is recorded `ready` in `trail/pr/*` after `plan_completion` and `merged` after `merge_confirm`; a coordinated node PR and the coordination PR are recorded `ready` and `merged` where the loop readies them and observes their merge.
- [ ] `check-run-record-rules.sh` fails on a planted `koto session unpin` call, a planted shirabe-defined retention window and a planted prune instruction that doesn't say pinned sessions are kept, and passes on the repository as it stands; it runs in `check-run-record.yml`.
- [ ] `references/koto-session-retention.md` names the sessions pinned, when, the reason format, that a pin keeps only its session, and both release routes, and says shirabe never unpins.
- [ ] Every suite that writes through `record-store.sh` sets `SHIRABE_RUN_RECORD_TEST_ROOT` to a temp directory; every stub suite asserts the `koto` on its `PATH` is the stub.

**Check**: Run `bash scripts/run-record-pin_test.sh` (stub cases and the real-koto scratch-store case), `bash scripts/check-run-record-rules_test.sh`, `bash skills/execute/scripts/terminal-retention_test.sh`, `bash skills/execute/scripts/execute-template-structure_test.sh`, `bash skills/execute/scripts/execute-coordinated-structure_test.sh` and the `execute-open.sh` and `work-on-open.sh` suites, and see every case pass, including the real-koto prune keeping the pinned sessions with `kept_by_pin: true` and removing the unpinned sibling. Then run `bash scripts/check-pipe-readers_test.sh`, `scripts/ablation/check-public-content.sh --diff origin/main --head HEAD` and `bash scripts/lib/preflight-probe_test.sh`, and see them clean (the preflight's timing case aside).

**Dependencies**: Step 5

**Files**: `scripts/run-record-pin.sh`, `scripts/run-record-pin_test.sh`, `scripts/check-run-record-rules.sh`, `scripts/check-run-record-rules_test.sh`, `scripts/run-trail.sh`, `scripts/lib/record-store.sh`, `scripts/testdata/record-koto/koto`, `scripts/bash-floor/run-record.list`, `.github/workflows/check-run-record.yml`, `skills/execute/koto-templates/execute.md`, `skills/execute/koto-templates/execute-coordinated.md`, `skills/work-on/koto-templates/work-on.md`, `skills/execute/scripts/execute-open.sh`, `skills/work-on/scripts/work-on-open.sh`, the coordinated scripts that ready a PR or observe its merge, their tests, `skills/execute/scripts/terminal-retention_test.sh`, `references/koto-session-retention.md`. No `requires.tsv` change. No file under `skills/coordinate/`.

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
