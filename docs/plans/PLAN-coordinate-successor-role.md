---
schema: plan/v2
status: Active
execution_mode: multi-pr
split_mode_source: intent
split_rationale: |
  Incremental Value. Each step leaves coordinators able to do something they
  couldn't before. Step 1 lets a roadmap manager hand over past an owed
  verdict, a pause, a parked decision or an empty scope (tsukumogami/shirabe#1862);
  step 2 lets a discipline coordinator hand over in its own role
  (tsukumogami/shirabe#1861); later steps each add one guarantee a running
  coordinator sees on its own: the handover after a rotation's window, one
  pending successor at a time, a stranded successor settled at reconcile, a
  brief that names its role once, and one route for every successor.
tracking_level: none
upstream: docs/designs/DESIGN-coordinate-successor-role.md
milestone: "Coordinator successor dispatch with its role"
step_count: 7
---

# PLAN: Coordinator successor dispatch with its role

## Status

Active

## Scope Summary

The design gives `skills/coordinate/scripts/dispatch-worker.sh` a fourth mode,
`--successor`, that a coordinator runs from the `wait` hub, or from
`rotation_end` at discipline scope, to start its own successor. The mode never
touches pick, so an owed verdict, a pause, a parked decision or an empty scope
can't stop it, while the worker path keeps every one of those refusals. It
builds the invocation from the run's own facts (`coord-log.sh run-facts` and
`vars`): `/shirabe:coordinate <ROADMAP> --role <role>` at roadmap scope and
`/shirabe:coordinate --discipline <name> --host <owner/repo> --role <role>` at
discipline scope, with the role read from the record's Run `role` row. A
script-only `successor` render field in `render-brief.sh` admits the
discipline shape, and `--role` moves after the scope group. A pending
successor is one Run row, `successor`, written `dispatching` before the launch
and `dispatched` or `dispatch-failed` after, refused a second time with exit
12, settled by reconcile, and cleared by the successor's own takeover or
rotation carry. A new exit 13 holds the handover while a decision arrival is
unrecorded.

The plan covers all of it, and all of it lands in tsukumogami/shirabe: no koto,
niwa or template structure change is needed, and the template stays at compat
2. Every acceptance criterion traces to a requirement in
`docs/prds/PRD-coordinate-successor-role.md`, named in parentheses. Nothing is
filed: the steps are the work items.

## Decomposition Strategy

Walking skeleton. Step 1 runs the whole handover at roadmap scope for a
manager on one real input, a run whose only open unit owes a verdict: the
coordinator's `successor_input.json`, the mode, the `successor` Run row, the
rendered brief, a stubbed niwa launch, and the successor's opener taking the
run over, clearing the row and reporting "Role: manager.". Step 2 opens the
discipline invocation and all four role and scope pairs. Every later step adds
one guarantee on top, named by what a coordinator sees.

The order is chosen so each step can land alone. Every way a successor can
start clears the row (the takeover in step 1, the rotation carry in step 3)
before step 4 starts refusing a second successor on it, so a carried row can't
block a rotation's own handover. Tests and docs go with the step whose
behaviour they cover; the coordinate skill's Roles section and the brief
template's `role` paragraph land with steps 1 and 2.

## Steps

### Step 1: a roadmap manager whose only open unit owes a verdict hands over to a successor that takes its run over as manager

**Goal**: A coordinator at the `wait` hub of a roadmap run hands over through `dispatch-worker.sh --session <run> --successor`, crossing the whole handover on one real input: a manager run whose only open unit is a milestone with its verdict owed. The mode reads no pick facts, builds `/shirabe:coordinate <ROADMAP> --role manager` from the run's own `ROADMAP` variable and Run `role` row, records the pending successor as a Run `successor` row around a stubbed niwa launch, and the successor's opener, started from the brief's tokens with `--dispatched-by`, takes the run over, clears that row and reports itself as a manager.

**Acceptance Criteria**:

- [ ] On a manager run at `wait` whose only open unit is a milestone pick marks `verdict_owed`, with a `successor_input.json` that names no `role`, `entry_args` or `repo`, `dispatch-worker.sh --session <run> --successor` exits 0 and prints `session=<name>`; the rendered brief's Goal line and the stub niwa's recorded prompt both read ``Run `/shirabe:coordinate <ROADMAP> --role manager` in <owner/repo>.``, where `<ROADMAP>` is the value `coord-log.sh vars --session <run>` prints for `ROADMAP` and `<owner/repo>` is the run's host from `coord-log.sh run-facts` (R1, R3).
- [ ] The same `--successor` dispatch, each on its own manager run with a role row, exits 0 with `session=<name>` in three more states: pick lists no open unit; the only open unit is held by a pause; and the only open unit is parked on a decision. In each case `state-read.sh --session <run> --run` afterwards shows one `successor` row reading `dispatched <topic> <YYYY-MM-DD>` and the stub niwa was called once (R2).
- [ ] A worker dispatch (no `--successor`) still exits 10 for each of those units: stderr names the owed verdict for the verdict-owed milestone, the pause for the paused unit and the decision for the parked one. After each refusal the Run section reads exactly as before (no `successor` row), the Holdings section has no new row, the run has no new `legs/` key, `.niwa/dispatch-briefs` under the workspace root holds no new brief and the stub niwa's call log is empty (R2, R10).
- [ ] At the moment the stub niwa is called, `state-read.sh --session <run> --run` shows exactly one `successor` row reading `dispatching <topic> <YYYY-MM-DD>` with Set by the predecessor run; after the launch the same row reads `dispatched <topic> <YYYY-MM-DD>`, and the record's entries include one naming the topic, the brief's path and the role `manager` (R9).
- [ ] With no Run `role` row on the record, the `--successor` dispatch exits 1 and its stderr names `state-stored-set.sh --session <run> --run role`. Afterwards the Run section reads exactly as before (no `successor` row), the Holdings section has no new row, the run has no new `legs/` key, `.niwa/dispatch-briefs` holds no new brief and the stub niwa's call log is empty (R6).
- [ ] `state-stored-set.sh --session <run> --run successor "dispatched <topic> <date>" --by <run>` still exits 64 and leaves the Run section unchanged, while `state-read.sh --session <run> --run` reads a record holding a `successor` row without error (R9).
- [ ] `coordinate-open.sh --dispatched-by <predecessor run> <args-file>`, the args file holding the brief's invocation tokens, prints `outcome=continued` and `predecessor=<predecessor run>`; afterwards the successor's Run section holds its own `coordinator` row, a `role` row reading `manager` and no `successor` row (R5, R9).
- [ ] A takeover of the same predecessor, its row reading `dispatched`, that doesn't name it keeps the row: `coordinate-open.sh <args-file>` run from another Claude session with no `--dispatched-by`, and `coordinate-open.sh --dispatched-by <another run> <args-file>` naming a different run the fixture opened, each against its own fresh predecessor fixture, each print `outcome=continued` and `predecessor=<predecessor run>`, and afterwards the new run's Run section still holds the `successor` row with its value and Set by unchanged (R9).
- [ ] `coord-log.sh chain-start --session <successor>` prints the same timestamp as `coord-log.sh chain-start --session <predecessor>`, and `reconcile-report-get.sh --session <successor> --md` prints a record line ending `Role: manager.` (R5, R8).
- [ ] In the rendered successor brief, the invocation line is the only line holding `manager` or `director` as a whole word: its keep-alive section reads "niwa schedules your keep-alive at dispatch. Don't schedule one.", and `render-brief_test.sh` passes with every worker brief under `testdata/brief-golden` byte-identical to before (R7, R10).
- [ ] SKILL.md's Roles section shows the roadmap-scope command `dispatch-worker.sh --session <run> --successor` and says a successor dispatch needs no unit; the `wait` directive carries a one-line pointer to it and `directive-ceiling_engine_test.sh` passes with `wait` rendered at or under 10802 bytes; the `dispatch` details' sentence about `own` for a successor names the mode; and `references/state-keys.md` describes the Run `successor` key with its value grammar and statuses (R12).
- [ ] `scripts/check-template-compat.sh` exits 0 with `coordinate.compat.json` still at compat 2 and its `gate_scripts` digest re-recorded, and `coord-log.sh compat --session <run>` prints `2` for the predecessor, so a run compiled at compat 2 is taken over rather than refused `template-incompatible`. Beside that, the existing gate and reconcile suites, whose records hold no `successor` row, pass with no edit to their files: `coordinate_1_engine_test.sh` through `coordinate_4_engine_test.sh`, `coordinate-takeover_engine_test.sh`, `reconcile-pass_test.sh`, `reconcile-pass_engine_test.sh`, `reconcile-settle_test.sh` and `reconcile-report_test.sh` (R5, R9).

**Check**: Run `bash skills/coordinate/scripts/successor-handover_engine_test.sh` (also selected by `run-tests.sh --engine`). The suite sources `scripts/lib/koto-test-guard.sh`, so HOME is a scratch directory, KOTO_HOME, every `KOTO_SESSION_*` variable and `KOTO_SESSIONS_BASE` are unset, and it asserts `koto session dir` resolves under the scratch directory before any case runs; it sets `NIWA` to a stub that records its arguments and the Run section it finds at call time, answers `niwa dispatch --help` and `niwa list --json`, and prints a `session name:` line; and it sets a synthetic `CLAUDE_CODE_SESSION_ID` per session. Its first case opens a manager run on a fixture milestone roadmap, writes the role row with `state-stored-set.sh --run role manager`, marks the only open milestone's verdict owed with `roadmap-status.sh --unit`, ticks the run to `wait`, adds `successor_input.json` to its context and runs the mode. Look for: the mode's exit 0 and `session=<name>`; the stub's record of the Run section showing `dispatching <topic> <date>` and the record afterwards showing `dispatched <topic> <date>`; the brief line ``Run `/shirabe:coordinate docs/roadmaps/ROADMAP-<name>.md --role manager` in <owner/repo>.``; the opener, run as the successor with that line's tokens in its args file and `--dispatched-by <predecessor>`, printing `outcome=continued` and `predecessor=<predecessor>`; the successor's Run section with `role` `manager` and no `successor` row; the two `chain-start` timestamps equal; and the record line ending `Role: manager.`. Its other cases show the exit 0s for no open unit, a pause and a parked decision; the worker dispatch's three exit 10s and the no-role-row exit 1, each followed by a check that the Run section, Holdings, `legs/`, the brief directory and the stub's call log are unchanged; and the two takeovers that keep the row, one from a third Claude session with no `--dispatched-by` and one naming another run. Before the change, run the new suite against the base commit's scripts and see every one of its cases fail: the base `dispatch-worker.sh` has no `--successor` mode and the base opener has no row to clear. Then run `bash skills/coordinate/scripts/run-tests.sh --engine` and `bash scripts/check-template-compat.sh` and see the existing gate, takeover and reconcile suites named above pass and the compat check exit 0.

**Dependencies**: None

**Files**: `skills/coordinate/scripts/dispatch-worker.sh`, `skills/coordinate/scripts/dispatch-common.sh`, `skills/coordinate/scripts/render-brief.sh`, `skills/coordinate/scripts/state-schema.jq`, `skills/coordinate/scripts/state-stored-set.sh`, `skills/coordinate/scripts/coordinate-open.sh`, `skills/coordinate/scripts/successor-handover_engine_test.sh`, `skills/coordinate/scripts/dispatch-worker_test.sh`, `skills/coordinate/scripts/state-stored-set_test.sh`, `skills/coordinate/scripts/render-brief_test.sh`, `skills/coordinate/SKILL.md`, `skills/coordinate/references/state-keys.md`, `skills/coordinate/koto-templates/coordinate.md`, `skills/coordinate/koto-templates/coordinate.compat.json`

### Step 2: a discipline coordinator's successor brief and prompt carry --discipline, --host and the record's role, and it takes over the rotation

**Goal**: A coordinator running a discipline (`--discipline <name> --host <owner/repo>`) dispatches its successor with `dispatch-worker.sh --session <run> --successor`, just as a roadmap manager can after step 1: the mode reads the scope, name and host from `coord-log.sh run-facts` rather than from anything the coordinator typed, the brief's Goal line and the dispatch prompt carry `/shirabe:coordinate --discipline <name> --host <owner/repo> --role <role>`, and the successor started from them takes the rotation over. All four role and scope pairs now work end to end, and the opener's role check holds at both scopes.

**Acceptance Criteria**:

- [ ] `render-brief.sh --stdout` over a `coordinate` input with `successor: true`, `role: director`, `repo: acme/widgets` and `entry_args: ["--discipline", "ci-health", "--host", "acme/widgets"]` exits 0, and its Goal reads ``Run `/shirabe:coordinate --discipline ci-health --host acme/widgets --role director` in acme/widgets.``; `dc_invocation` over the same input prints `/shirabe:coordinate --discipline ci-health --host acme/widgets --role director`, and over a roadmap successor's input still prints `/shirabe:coordinate docs/roadmaps/ROADMAP-plugin-system.md --role director`. (R4)
- [ ] With `successor: true`, every other first-flag shape exits 1 and prints no brief: a name that fails the template's `DISCIPLINE` pattern (`CI_Health`), a host that isn't `owner/repo` (`acme`), the pair reordered (`--host` first), a missing `--host`, and a fifth token. (R4)
- [ ] `successor: true` exits 1 naming the field on a `work-on` input, beside `held_rerender`, and beside `role_change_by`, and a `coordinate` input with `successor: true` and no `role` exits 1 naming `role`. (R7, R10)
- [ ] A lane still can't take the discipline shape: the same four tokens without `successor` exit 1 with `entry_args: the first token must be the positional argument, one line, not a flag`; `--discipline ci-health` after a roadmap positional exits 1 with `entry_args: coordinate doesn't allow --discipline`; a worker-path dispatch whose `brief_input.json` sets `successor: true` itself is refused with that same first-token message, because the field is dropped before rendering; and every worker golden under `testdata/brief-golden/` still matches byte for byte. (R10)
- [ ] On a discipline run opened as `--discipline ci-health --host acme/widgets` whose record holds `role=director`, `dispatch-worker.sh --session <run> --successor` exits 0 and prints `session=<name>`, though the successor input gave no `entry_args` or `repo`; the brief's Goal reads ``Run `/shirabe:coordinate --discipline ci-health --host acme/widgets --role director` in acme/widgets.``, the prompt the niwa stand-in logged carries `/shirabe:coordinate --discipline ci-health --host acme/widgets --role director`, and the Run `successor` row reads `dispatched <topic> <YYYY-MM-DD>`. (R1, R3, R4)
- [ ] On that discipline run the successor dispatch also exits 0 with `session=<name>` and a `dispatched <topic> <YYYY-MM-DD>` row when pick lists no open issue, when the only open issue is held by a pause, and when it's parked on a decision; a worker dispatch (no `--successor`) naming that paused issue still exits 10, and afterwards the Run section has no `successor` row, no new `legs/` key exists, `.niwa/dispatch-briefs/` holds no new brief and the stand-in's log has no `niwa dispatch` line. (R2, R10)
- [ ] The two remaining pairs render and report their own role: a discipline run recorded `manager` gives `/shirabe:coordinate --discipline ci-health --host acme/widgets --role manager`, and a roadmap run recorded `director` gives `/shirabe:coordinate <the run's ROADMAP> --role director`. In each of the three new briefs, `grep -inwE 'managers?|directors?'` matches one line, the invocation line, and each pair's successor, started from its brief's tokens with `--dispatched-by`, prints a `Record:` line from `reconcile-report-get.sh --md` ending `Role: <that pair's role>.` (R1, R7, R8)
- [ ] With the niwa stand-in failing the first launch, so that dispatch exits 4 and the successor row reads `dispatch-failed`, then `state-stored-set.sh --run role director --by <name> --intervention person` run on a record that held `manager`, a second successor dispatch under a new topic exits 0 and renders `--role director` where the first rendered `--role manager`, at discipline scope and at roadmap scope. (R3)
- [ ] A discipline run with no Run `role` row makes the successor dispatch exit 1 with stderr naming `state-stored-set.sh --run role`, and afterwards the Run section has no `successor` row, no new `legs/` key exists, `.niwa/dispatch-briefs/` holds no brief and the stand-in's log has no `niwa dispatch` line. (R6)
- [ ] A discipline run whose facts can't be read (`coord-log.sh run-facts` exits 1 because the run found no record, or 2 because its log can't be read) makes the successor dispatch exit 1, and afterwards the Run section has no `successor` row, no new `legs/` key exists, `.niwa/dispatch-briefs/` holds no brief and the stand-in's log has no `niwa dispatch` line. (R4)
- [ ] A successor input whose `entry_args` or `repo` differs from the derived value token for token (`["--discipline", "release", "--host", "acme/widgets"]`, `["--discipline", "ci-health", "--host", "acme/other"]`, or `repo: acme/other`) exits 1 with a message naming both the input's value and the run's, with no `successor` row, brief or `niwa dispatch` line afterwards; an input giving exactly the derived values exits 0. (R3)
- [ ] When `coord-log.sh run-facts` reports a name or host that starts with `-` or fails its variable's pattern (a stand-in in `dispatch-worker_test.sh`'s copied skill prints `-x` for the name, then `acme` for the host), the successor dispatch exits 1 naming the token, with no `successor` row, brief or `niwa dispatch` line afterwards. (R4)
- [ ] A discipline successor started inside its rotation's window, before the predecessor's reasoning is written, with the brief's invocation tokens in `args.json` and `--dispatched-by <predecessor>`, takes the rotation over: the opener prints `outcome=continued` and `predecessor=<predecessor>` rather than opening a next rotation, `coord-log.sh chain-start` on the successor prints the predecessor's chain start, the successor's Run section holds `role` `director` and no `successor` row, and its `Record:` line names `acme/widgets` and ends `Role: director.` (R5, R8)
- [ ] At discipline scope and at roadmap scope, an opener started with the successor brief's tokens but `--role manager` against a record holding `director` prints `outcome=refused` and `reason=role-mismatch` and exits 2 with the record unchanged; the same start with `--role-change-by <the record's reports-to address> --role-change-source dispatcher` is accepted and prints `role_changed_from=director`. (R8)
- [ ] SKILL.md's Roles section shows `/shirabe:coordinate --discipline <name> --host <owner/repo> --role <role>` and says a discipline coordinator runs the `--successor` dispatch at `rotation_end` before it submits `reasoning: written`; the `rotation_end` directive in `coordinate.md` gives the same order; and `references/brief-template.md`'s `role` paragraph shows the same discipline invocation line beside the roadmap one. (R12)
- [ ] On records with no `successor` row, the existing gate suites (`coordinate_1_engine_test.sh` through `coordinate_4_engine_test.sh`, `dispatch-path_engine_test.sh`) and reconcile suites (`reconcile-check_test.sh`, `reconcile-pass_test.sh`, `reconcile-pass_engine_test.sh`, `reconcile-settle_test.sh`, `reconcile-report_test.sh`) pass with no case changed, `directive-ceiling_engine_test.sh` passes, and `scripts/check-template-compat.sh --template skills/coordinate/koto-templates/coordinate.md` exits 0 with `compat` still 2, so a run compiled at compat 2 is taken over rather than refused `template-incompatible`. (R5, R10)

**Check**: Run `bash skills/coordinate/scripts/render-brief_test.sh` and see its new discipline-shape cases pass: the Goal line ``Run `/shirabe:coordinate --discipline ci-health --host acme/widgets --role director` in acme/widgets.`` and the matching `dc_invocation` output, each refused shape and misplaced `successor` exiting 1, the lane refusal `entry_args: the first token must be the positional argument, one line, not a flag`, and the goldens unchanged. Run `bash skills/coordinate/scripts/dispatch-worker_test.sh` and see the derived-token and bad-facts refusals exit 1, each followed by an assertion that the Run section has no `successor` row, no new `legs/` key, no brief under `.niwa/dispatch-briefs/` and no `niwa dispatch` line in the stand-in's log. Then run `bash skills/coordinate/scripts/successor-handover_engine_test.sh`, extended with the discipline cases. Its setup sources `scripts/lib/koto-test-guard.sh` as step 1's cases do (a scratch `HOME`; `KOTO_HOME`, every `KOTO_SESSION_*` variable and `KOTO_SESSIONS_BASE` unset; the resolved store asserted under the scratch directory before anything runs) and stubs niwa with a stand-in that logs its arguments. Open a discipline run `--discipline ci-health --host acme/widgets`, set its role row to `director`, and run the mode; look for the Goal line above in the brief and `/shirabe:coordinate --discipline ci-health --host acme/widgets --role director` in the logged prompt. Start the opener with those tokens and `--dispatched-by` and look for `outcome=continued`, equal `chain-start` output for both runs, and a `Record:` line ending `Role: director.`. The manager-at-discipline and director-at-roadmap pairs run as their own cases, each asserting the one-line role grep on its brief and its successor's `Record:` line ending `Role: <that pair's role>.`; the per-state cases with the worker exit 10, the no-role and unreadable-facts refusals with their empty-record assertions, the role-row change between a failed and a second dispatch, and the `role-mismatch` refusal and accepted change at both scopes run as cases in the same file. Every new successor case fails on the base commit, where `--successor` isn't a mode and the discipline shape is refused; the worker exit 10 and lane cases are regression guards that pass on both. Then confirm the docs: `sed -n '/^## Roles$/,/^## The Record$/p' skills/coordinate/SKILL.md | grep -F -- '--discipline <name> --host <owner/repo> --role <role>'` and `sed -n '/is the role of a coordinator the brief starts/,/^$/p' skills/coordinate/references/brief-template.md | grep -F -- '--discipline <name> --host <owner/repo> --role <role>'` each print a line. Finish with `bash skills/coordinate/scripts/run-tests.sh --engine`, which runs the gate and reconcile suites above unchanged, and `bash scripts/check-template-compat.sh --template skills/coordinate/koto-templates/coordinate.md`, both exiting 0.

**Dependencies**: Step 1

**Files**: `skills/coordinate/scripts/render-brief.sh`, `skills/coordinate/scripts/render-brief_test.sh`, `skills/coordinate/scripts/dispatch-common.sh`, `skills/coordinate/scripts/dispatch-worker.sh`, `skills/coordinate/scripts/dispatch-worker_test.sh`, `skills/coordinate/scripts/successor-handover_engine_test.sh`, `skills/coordinate/references/entry-points.tsv`, `skills/coordinate/references/brief-template.md`, `skills/coordinate/SKILL.md`, `skills/coordinate/koto-templates/coordinate.md`, `skills/coordinate/koto-templates/coordinate.compat.json`

### Step 3: a discipline successor started after its rotation's end date opens the next rotation in its predecessor's role and clears the pending row

shirabe: `state-open.sh --carry` clears the `successor` row when the new run's `koto/links/dispatched-by/` names the run that wrote it and keeps it otherwise, and the engine suite shows the next rotation's record holding the predecessor's role and its first record line naming it (R5, R8).

### Step 4: a second successor is refused while one is pending, and a re-run with the same topic confirms or re-launches it under the same row

shirabe: `dispatch-worker.sh --successor` settles the row first, exits 12 naming the pending topic and status while the row reads `dispatching` or `dispatched`, confirms or re-launches a same-topic re-run without a second row, lets a `dispatch-failed` or `stranded` row free the slot for a new topic (exit 3 on reusing that topic, exit 5 on a live session), and treats a confirm refused by a takeover fence as success, printing `taken_over=` (R9).

### Step 5: reconcile settles a pending successor row and the report names it with the command to run again

shirabe: the reconcile pass runs `reconcile-settle.sh --successor` when the record holds a pending row, turning a listed `dispatching` row `dispatched` and an unlisted `dispatched` row `stranded` only after a listing that was read, without changing the pass exit or the gate verdict, and `reconcile-report.sh` prints one line naming the row, its status and topic, and for an unlisted `dispatching` row the command to run again (R9).

### Step 6: a successor brief names its role only on its invocation line, and a handover waits while a decision arrival is unrecorded

shirabe: the mode exits 1 naming the field when coordinator text (`authority`, `goal`, `checkpoints`, `acceptance`, `decisions`, `read_first`, `out_of_scope`, `standing_rules`, `surfaces`) holds `manager` or `director` as a whole word in any case, so a rendered successor brief at each scope has one line naming a role, and exits 13 naming the recording write while `decision-next.sh` names an `unrecorded-*` rule (R7).

### Step 7: an own-scope coordinate brief on the worker path is refused naming --successor, and every other worker brief renders its role as before

shirabe: `input_role` tests own-scope from `coord-log.sh run-facts` at both scopes and the worker path exits 1 naming `--successor` for the run's own roadmap or discipline and host, while a brief naming another roadmap still renders `--role manager`, a worker brief carries no `--role`, `--rebrief` and `--releg` never read the role row, a held lane's re-brief renders no `--role` without `role_change`, and `role_change` on a successor dispatch exits 1 (R3, R10).

## Implementation Sequence

The steps run in order where they depend on each other, and in parallel where
they don't. Each step is one pull request, and every one lands in
tsukumogami/shirabe.

| Step | Repository | Depends on |
|---|---|---|
| 1 | tsukumogami/shirabe | none |
| 2 | tsukumogami/shirabe | 1 |
| 3 | tsukumogami/shirabe | 2 |
| 4 | tsukumogami/shirabe | 3 |
| 5 | tsukumogami/shirabe | 4 |
| 6 | tsukumogami/shirabe | 2 |
| 7 | tsukumogami/shirabe | 2 |

Step 1 opens the path and step 2 widens it to discipline scope, so both come
first. After step 2, steps 3, 6 and 7 can be built side by side; step 4 waits
for step 3, because it starts refusing a second successor on the row and the
carry has to clear that row first, and step 5 waits for step 4, whose
settle-first rule it reuses at reconcile. Steps 2, 4, 6 and 7 all touch
`dispatch-worker.sh`, and most steps re-record `gate_scripts` in
`coordinate.compat.json`, so branches built side by side will need a rebase
there. The outline steps' dependencies are this order's; the plan's owner
confirms them when it details each step.

What each PRD requirement rests on:

| Requirement | Steps |
|---|---|
| R1 successor dispatch at both scopes, all four pairs | 1, 2 |
| R2 no unit gate on a successor; worker refusals kept | 1, 2 |
| R3 successor recognized by the run's own scope, name and host | 1, 2, 7 |
| R4 discipline brief takes the opener's shape from run facts | 2 |
| R5 same run: takeover inside the window, carry after it | 1, 2, 3 |
| R6 no role row, no successor | 1, 2 |
| R7 role as data, one role line | 1, 2, 6 |
| R8 role checked at start, named in the first report | 1, 2, 3 |
| R9 one successor at a time, settled on restart | 1, 4, 5 |
| R10 worker paths unchanged | 1, 2, 7 |
| R11 a case per requirement failing on the base commit | every step |
| R12 Roles section and brief template show both lines | 1, 2 |
