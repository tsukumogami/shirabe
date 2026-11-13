---
schema: plan/v1
status: Active
execution_mode: multi-pr
split_mode_source: default
split_rationale: |
  Incremental Value. Each issue lands a change a reader can use on its own:
  the reply table stops misreading refusals as absent, the contract test pins
  that table against real koto, the probe's deadline and hold bound the ladder
  gate and close #1737 and #1792, the template backstop states the gate's
  bound, the stated-local-topic path lets a fresh topic settle its
  never-opened names, and the opener flag hands that statement to operators
  with its docs.
tracking_level: none
upstream: docs/designs/DESIGN-scope-resume-ladder.md
milestone: "Scope resume ladder time bound"
issue_count: 6
---

# PLAN: Scope resume ladder time bound

## Status

Active

## Scope Summary

A resumed `/scope` session's `ladder` gate gets a time bound shirabe enforces: the resume probe runs a 20 s deadline over its koto calls, answers as soon as the lookups its row needs are settled, and otherwise holds the run with an exit 3 that prints one finding line per lookup that ran long or refused. koto's replies are read by exit code and `code` first, so no lookup that couldn't finish is ever read as absent, and an operator's `--local-topic=stated` statement plus the parent lookup's "not a parent here" answer let a fresh topic through.

## Decomposition Strategy

**Horizontal decomposition**, chosen with `--no-skeleton`. The design changes existing scripts and one template, and its Decision 6 fixes the build order: the reply table first, then the probe's clock with the gate's bound, then the operator's statement. The issues follow that order rather than a stub-first skeleton, because each later piece reads what the earlier one produces.

- **Issue 1 comes first** because the probe's classification and its finding text both read the reply table in `scripts/skill-session.sh`. Until the table can tell koto's exact not-found reply from a refusal, and until `has-work` has its refusal exit 7, the probe has nothing to hold on.
- **Issue 2 follows Issue 1** and pins that table against real koto v0.37.0, v0.37.1 and v0.37.2. It is a separate issue because it needs CI provisioning (several koto releases and a bucket) that the stub suites don't.
- **The design's Phase 2 splits into Issues 3 and 4**, and its Phase 3 into Issues 5 and 6, so each pull request changes one script or the template with its own tests. Issue 3 gives the probe its deadline, early answer, descendant kill and unrouted exit 3; Issue 4 gives both gates the `timeout: 30` backstop and the hold directive. Issue 5 adds the probe's path under a stated local topic; Issue 6 adds the opener flag that lets an operator make that statement, with the skill's usage text.

Decisions this plan makes, with the reasons:

- **`parent_state` is widened to the design's reading.** Every exit 3 `session_lookup_failed` is "not a parent here", read by code. koto builds that refusal only for a name with no copy on this host, so the code carries the fact the decision needs. The cost is that `adopt` fails open on two more shapes (this directory's prefix, or the bucket, couldn't be read). Issue 2's contract test guards that edge, and #1787's two stop tests flip to skip cases in Issue 1.
- **#1792 is covered and closed by Issue 3.** `has-work`'s refusal exit 7 (Issue 1) and the probe's unrouted exit 3 (Issue 3) hold the run at `resume_route` instead of ending it at `done_error`, which is what #1792 asks for.
- **Left out of the plan:** the koto asks (the design's Follow-on, which belong in koto's tracker) and #1755, which asks koto for a distinct answer from `status`.
- **The operator's spelling is `/scope <topic> --local-topic=stated`.** The probe keeps an internal `--local-topic <stated|unstated>` argument that only the gate passes. Issue 5's remedy text and Issue 6's accept and refuse criteria use exactly the equals form, and Issue 6 checks that the opener accepts the remedy text the probe prints, verbatim.
- **Docs coverage** for the user-visible surface rides with Issue 6, through the scope skill's argument hint and usage text.
- **Two handovers between issues** are stated on both sides. Issue 1 adds a `resume-probe_test.sh` case (a child's `koto status` exit 3 `session_lookup_failed` with a present `explore-t` handoff) that expects exit 2 until Issue 3 lands; Issue 3 changes that case to exit 3 with a `::koto-finding::` line and names it as the one exception to its "existing cases keep their exit codes" criterion. Issue 4 asserts the hold directive doesn't mention `--local-topic` yet; Issue 6 changes that assertion to require `--local-topic=stated`.

## Issue Outlines

### Issue 1: fix(skill-session): read koto's replies by exit code and code first

**Goal**: Make `session_state`, `has-work` and `parent_state` in `scripts/skill-session.sh` read koto's replies by exit code and `code` first, so only koto's exact not-found reply counts as absent, `has-work` gets a refusal exit 7 that carries koto's line, and `parent_state` answers "not a parent here" for exit 3 `session_lookup_failed` and for v0.37.0's exit-2 no-copy reply.

**Acceptance Criteria**:

*`session_state`: only the exact miss is absent*

- [ ] A `koto status` reply of exit 2, no `code`, and `error` exactly `workflow '<name>' not found` is absent. In `scripts/skill-session_test.sh`, the existing never-existed cases still pass: `status scope-never` prints `absent` with exit 0, and `has-work design nope` exits 1.
- [ ] An exit-2 reply whose `error` contains "not found" without being the exact form (for example `listing ws-a/<name>/ failed: HTTP 404 not found`) is not absent. A new `skill-session_test.sh` case shows `status <name>` exiting 4 with nothing on stdout, and `has-work` exiting 7.
- [ ] An exit-2 reply with the exact `error` text plus a `code` field is not absent. A new `skill-session_test.sh` case shows `status` exiting 4 and `has-work` exiting 7.
- [ ] An exit-3 reply with `code: "session_lookup_failed"` makes `status <name>` exit 4 and print nothing, and makes `has-work` exit 7.
- [ ] An exit 3 with any other `code` or with no `code`, an exit 0 whose stdout isn't a status object, and any other exit still give `has-work` exit 4. The existing `resume-probe_test.sh` case "a child koto cannot report (has-work exit 4)" still expects exit 2 from the probe.
- [ ] The kept-record cases still pass: exit 0 with `"removed": true` prints `absent`, and a terminal record with or without `"removed": false` prints `finished`.

*`has-work`: refusal exit 7 with koto's line*

- [ ] On exit 7, `has-work` prints koto's reply line on stdout unchanged. A `skill-session_test.sh` case compares stdout byte for byte with the stand-in koto's JSON line. stderr carries one line naming `<child>-<topic>`.
- [ ] During `has-work`, a `koto context exists <name> session/branch` answer of exit 2, or exit 3 with `session_lookup_failed`, also gives exit 7, with koto's reply line on stdout when koto gave one. Any other unexpected answer from that read, or from `koto context list`, still gives 4. Each case is a `skill-session_test.sh` run against a stub.
- [ ] Exits 0 and 1 print nothing on stdout, as today. The usage-error (64) and missing-koto (127) cases in `skill-session_test.sh` still pass.
- [ ] The script's header documents the new exit. `grep -nE '^#   7 ' scripts/skill-session.sh` prints a line naming `has-work`'s refusal, and the `has-work` paragraph in the header says exit 7 prints koto's line.

*`parent_state`: "not a parent here", read by code*

- [ ] Every exit 3 with `code: "session_lookup_failed"` is "not a parent here", whatever its text. In `skill-session_test.sh`, the stub kinds `session_lookup_failed-others`, `session_lookup_failed-own` and `session_lookup_failed-bucket` each give these results for a scope parent: `adopt design <t>` exits 0 and prints `adopted=none`, the only write is `context remove design-<t> chain/parent`, and `dispatch read design <t>` exits 0 and prints nothing.
- [ ] #1787's two stop cases for `session_lookup_failed-own` and `session_lookup_failed-bucket` (currently `pb3` and `pb4`, expecting exit 4) move to the no-match loop and expect the results above. This flip is intended.
- [ ] v0.37.0's exit-2 no-copy reply is still "not a parent here", matched on the `PARENT_NO_COPY_HERE` text as today. The `others-unlisted` and `elsewhere` cases (`pa1` to `pa3`) still print `adopted=none`.
- [ ] These replies still stop `adopt` and `dispatch read` with exit 4, a stderr line naming `scope-<t>`, and koto's reason: exit 2 `own-unreadable`, exit 2 `copy-mismatch`, and two new cases, exit 3 with a `code` other than `session_lookup_failed` (for example `workspace_unreadable`) and exit 3 with no `code`.
- [ ] "Not a parent here" is never absent. A `skill-session_test.sh` case runs `status scope-<t>` against each "not a parent here" reply (both exit-2 no-copy kinds and the three exit-3 kinds) and expects exit 4 with nothing on stdout. `sed -n '/^parent_state()/,/^}/p' scripts/skill-session.sh | grep -c 'SSTATE=absent'` prints `0`.
- [ ] A live parent on this branch whose `chain/dispatch` names the child still matches. The existing `adopt` and `dispatch read` match cases pass.

*The probe's tests under the exact match*

- [ ] The `resume-probe_test.sh` stand-in koto answers a missing name's `koto status` with koto's exact form, `{"command":"status","error":"workflow '<name>' not found"}` and exit 2, instead of `session not found`. The fresh-topic cases still reach row 10, and `grep -n "printf 'session not found" skills/scope/scripts/resume-probe_test.sh` prints nothing. The link stub in `skill-session_test.sh` that prints `workflow %s not found` quotes the name the same way.
- [ ] The `resume-probe_test.sh` stand-in gains a refusal mode, for example `STUB_REFUSED=<name>`. In that mode `koto status <name>` exits 3 and prints a `session_lookup_failed` JSON line with koto's real refusal text.
- [ ] A new `resume-probe_test.sh` case runs the probe with `STUB_KEYS="explore-t:handoff/scope.md"` and `STUB_REFUSED=design-t`. It expects exit 2 with `row=2 cannot-tell` on stdout, and stderr containing `has-work design t exited 7`. This expectation holds only until <<ISSUE:3>> lands. <<ISSUE:3>> changes this case to exit 3 with a `::koto-finding::` line for `design-t`, and names it as the one exception to its criterion that existing cases keep their exit codes.
- [ ] Every other existing `resume-probe_test.sh` case keeps its expected exit code.

*Suites*

- [ ] With koto and jq on PATH (so the engine-backed cases run instead of printing SKIP), `bash scripts/skill-session_test.sh`, `bash skills/scope/scripts/resume-probe_test.sh` and `bash skills/scope/scripts/scope-template_test.sh` each exit 0.
- [ ] `scripts/check-skill.sh --changed scope` exits 0.

*Downstream deliverables*

- [ ] Must deliver: `has-work` exit 7 exactly for the reply table's refusals, with koto's reply line unchanged on stdout and a stderr line naming the name. Exits 0, 1, 4, 64 and 127 keep their meanings (required by <<ISSUE:3>>).
- [ ] Must deliver: the `resume-probe_test.sh` stand-in's exact not-found answer and refusal mode, plus the `STUB_REFUSED=design-t` case expecting exit 2, which <<ISSUE:3>> changes to exit 3 with a finding line (required by <<ISSUE:3>>).
- [ ] Must deliver: every reply shape in the table reachable through the `status`, `has-work`, `dispatch read` and `adopt` subcommands, with the script header naming each shape and the answer it gives, so a test can run them against real koto (required by <<ISSUE:2>>).
- [ ] Must deliver: `parent_state` reading exit 3 `session_lookup_failed` by `code` alone, and exit 2 by the `PARENT_NO_COPY_HERE` text. That lets the contract test expect "not a parent here" on v0.37.1 and v0.37.2, and a non-absent 4 on v0.37.0, for a parent held only under another prefix whose sweep can't finish (required by <<ISSUE:2>>).

**Dependencies**: None

**Type**: code

**Complexity**: testable

### Issue 2: test(skill-session): run the reply table and parent_state against real koto

**Goal**: Add a contract test that runs `scripts/skill-session.sh`'s reply table and `parent_state` against real koto v0.37.0, v0.37.1 and v0.37.2, including a session written before the bucket's name index and held both on this host and only under another directory's prefix, and that expects each release's own answer when the sweep of other prefixes can't finish.

**Acceptance Criteria**:

*Provisioning and the run*

- [ ] A new suite, `scripts/skill-session-koto-contract_test.sh`, runs `scripts/skill-session.sh` (with `KOTO_BIN` set to each release's binary) and `koto` directly against v0.37.0, v0.37.1 and v0.37.2 in one run. For each release it prints one summary line, `release=<version> cases=<n> failed=<m>`.
- [ ] The suite sources `scripts/lib/koto-test-guard.sh` on the guard line that `scripts/check-koto-test-guard.sh` requires, before any line that names koto. It hands its cleanup to `ktg_on_exit` rather than setting its own EXIT trap. It sets its backend configuration after the guard has cleared `KOTO_SESSION_*` and `AWS_*`. `bash scripts/check-koto-test-guard.sh scripts/skill-session-koto-contract_test.sh` exits 0.
- [ ] A new workflow, `.github/workflows/check-skill-session-koto-contract.yml`, provisions the releases, the scratch bucket, the pre-index session and the forced sweep failure as the open point above settles. It runs the suite on pull requests that touch `scripts/skill-session.sh`, the suite, `scripts/lib/koto-test-guard.sh` or the workflow itself, and on push to `main` for the same paths.
- [ ] Before the suite runs, the workflow checks that each release's `koto version` prints exactly 0.37.0, 0.37.1 or 0.37.2 and that the scratch bucket answers a listing. Either check failing fails the job, so the suite can't skip to a green result.
- [ ] After the suite, the workflow fails unless the output holds exactly three summary lines, one each for 0.37.0, 0.37.1 and 0.37.2, each with `cases=` above 0 and `failed=0`. A green run of this workflow on the pull request is the evidence that the chosen provisioning works.
- [ ] Each koto or `skill-session.sh` call in the suite runs under a per-call wall-clock bound. A call that outlasts it fails its case, naming the release and the session, and doesn't hang the job.

*The reply table against real koto, on each release*

- [ ] **A never-opened name, sweep finishes.** On each release, with every prefix answering, `koto status <name>` exits 2 with no `code` and `error` exactly `workflow '<name>' not found`. `skill-session.sh status` prints `absent`, and `skill-session.sh has-work design <topic>` exits 1. This pins the exact match <<ISSUE:1>> introduces against real koto's text.
- [ ] **A never-opened name, sweep can't finish, on v0.37.1 and v0.37.2.** `koto status <name>` exits 3 with `code` `session_lookup_failed`. `skill-session.sh has-work design <topic>` exits 7 and prints koto's line on stdout. `skill-session.sh status` doesn't print `absent`.
- [ ] **A never-opened name, sweep can't finish, on v0.37.0.** `koto status <name>` exits 2 with an `error` that isn't the exact not-found reply. `skill-session.sh has-work design <topic>` exits 7, and `skill-session.sh status` doesn't print `absent`.
- [ ] **`koto context exists` on a session this host holds.** On each release, it exits 0 for a key the session has and 1 for one it lacks. On a never-opened name with the sweep failing, it exits 2, or 3 with `session_lookup_failed`, and never 1.
- [ ] **v0.37.2's new fields.** The suite asserts that a v0.37.2 `session_lookup_failed` refusal still exits 3 with that `code`, and that `adopt`'s answer for it is the same as on v0.37.1. Whether `reason` and `index` are present is recorded in the case's output. No assertion of `parent_state`'s answer depends on them.

*`parent_state` on a pre-index session held on this host*

- [ ] On each release, a pre-index `scope-<topic>` held on this host has a `chain/dispatch` for `design` and `session/branch` equal to the current branch, and the sweep of other prefixes is failing. In that state `skill-session.sh adopt design <topic>` exits 0 and prints `adopted=scope-<topic>`, and `skill-session.sh dispatch read design <topic>` prints `parent=scope-<topic>`.
- [ ] In the same state, `koto status scope-<topic>` on each release exits 0, and never exits 3 with `session_lookup_failed`. This is the check that koto builds that refusal only for a name with no copy on this host: it observes the reply for a name that does have a copy here.

*`parent_state` on a pre-index session held only under another prefix*

- [ ] **Sweep finishes.** On each release, `koto status scope-<topic>` answers the session's state, and `skill-session.sh dispatch read design <topic>` exits 0 without reporting the session absent. The suite also asserts that `skill-session.sh status scope-<topic>` prints `live` or `finished` and not `absent`.
- [ ] **Sweep can't finish, v0.37.1.** `koto status scope-<topic>` exits 3 with `code` `session_lookup_failed`. `skill-session.sh adopt design <topic>` exits 0 and prints `adopted=none` ("not a parent here"), and `skill-session.sh dispatch read design <topic>` exits 0 and prints nothing.
- [ ] **Sweep can't finish, v0.37.2.** The same observations as v0.37.1, asserted in their own case: exit 3 `session_lookup_failed`, `adopt` exits 0 with `adopted=none`, and `dispatch read` exits 0 with no output.
- [ ] **Sweep can't finish, v0.37.0.** `skill-session.sh adopt design <topic>` exits 4, prints nothing on stdout, and says on stderr `cannot read the parent sessions for <topic>` along with `scope-<topic>`. `skill-session.sh dispatch read design <topic>` exits 4 too. Before asserting, the case checks that koto's reply does not contain the `PARENT_NO_COPY_HERE` text from `scripts/skill-session.sh`, which tests Decision 3's assumption against real v0.37.0. If v0.37.0 does send that text here, the case fails with a message saying the assumption doesn't hold. The stand-in case `others-unlisted` in `scripts/skill-session_test.sh` scripts that very shape, an exit 2 carrying the no-copy text after another prefix's listing failed, so this criterion settles whether real v0.37.0 ever sends it.
- [ ] **Never absent.** In each of the three sweep-can't-finish cases, `skill-session.sh status scope-<topic>` doesn't print `absent`. No case on any release reports a session that exists under another prefix as absent.

*The two shapes the widened reading lets through (v0.37.1 and v0.37.2)*

- [ ] With this directory's prefix failing to list and the parent having no copy on this host, koto answers exit 3 `session_lookup_failed` on each of v0.37.1 and v0.37.2, and `skill-session.sh adopt design <topic>` exits 0 with `adopted=none`.
- [ ] With the whole bucket failing and the parent having no copy on this host, koto answers exit 3 `session_lookup_failed` on each of v0.37.1 and v0.37.2, and `skill-session.sh adopt design <topic>` exits 0 with `adopted=none`.
- [ ] With either of those faults applied to a parent that does have a copy on this host, koto answers from the host's copy on v0.37.1 and v0.37.2. It never exits 3 with `session_lookup_failed`, and `adopt` reads that parent as in the held-on-this-host case.
- [ ] In every case above, `skill-session.sh status` doesn't print `absent`.

*Reads write nothing*

- [ ] The fault layer or the server logs every write request (PUT, POST, DELETE) during each read-only phase of the suite: the `status`, `context exists`, `has-work`, `dispatch read` and refused `adopt` calls, including the calls killed at the per-call bound. The suite asserts that the count is 0 for each release. (`adopt` writes its own child's `chain/parent` key by design, and the suite excludes exactly that write by session and key.)

*Existing suites*

- [ ] `bash scripts/skill-session_test.sh` still passes, and `.github/workflows/check-skill-session.yml` stays green on the pull request.

**Dependencies**: Blocked by <<ISSUE:1>>

**Type**: code

**Complexity**: critical

### Issue 3: fix(scope): give the resume probe a deadline, an early answer and an unsettled hold

**Goal**: `resume-probe.sh` runs a 20 s deadline over every koto call it makes, answers as soon as the lookups its row needs are settled, kills the lookups still out by a descendant walk, and otherwise exits 3 (unsettled) with one reduced `::koto-finding::` line per outstanding or refused lookup, reading `has-work`'s refusal exit 7 as unsettled and a missing `--local-topic` as `unstated`.

**Acceptance Criteria**:

Deadline and early answer:

- [ ] `resume-probe_test.sh`'s koto stub gains a per-name delay (a lookup of a given name or key sleeps a given number of seconds before answering), koto's real refusal replies for v0.37.0 (exit 2 without the exact not-found reply) and v0.37.1 (exit 3, `code: session_lookup_failed`, with the "holds none under this directory's prefix ..., and koto can't tell whether another directory's prefix holds it" message the design quotes, and a second refusal message without that phrase), a `context get` answer for a key it holds, and a record of each stub process id so a case can check none survives.
- [ ] The probe reads a test-only deadline override, `SCOPE_PROBE_DEADLINE`, named in its header next to `SCOPE_PROBE_NOW`. It is honored only as a whole number from 1 to 20; any other value, including one at or above the gate's 30 s, reads as the 20 s default. `grep -n SCOPE_PROBE_DEADLINE skills/scope/koto-templates/scope.md` prints nothing, so no gate passes it, and koto runs gates in a cleared environment.
- [ ] Early answer on the resumed topic's own keys: with `scope-t`'s `work/state.md` present (fresh, `phase_pointer: 2`) and answering at once, and the five never-opened names delayed 30 s, `resume-probe.sh --topic t --intent none` with `SCOPE_PROBE_DEADLINE=5` exits 21 with `row=21 fresh-phase-2` in under 3 s, prints no `::koto-finding::` line, and leaves no stub process running.
- [ ] Early answer on the artifact tree: with neither `scope-t` key present, `docs/plans/PLAN-t.md` at `Active`, `--intent none`, and the five never-opened names delayed 30 s, the probe exits 41 in under 3 s with no finding line and no stub process left.
- [ ] Early answer on a prior run: with only `work/prior-run.md` present holding a failed `scope:push` step, `exit: full-run` and `--intent continue`, and the five never-opened names delayed 30 s, the probe exits 27 in under 3 s.
- [ ] A refusal on a lookup no remaining row needs is ignored: with `work/state.md` present (pointer 2) and every child's `koto status` answering the v0.37.1 refusal, the probe exits 21 with no finding line.
- [ ] Deadline on a fresh topic (#1737, the v0.37.0 shape): with no keys present and the five never-opened names delayed 30 s, `SCOPE_PROBE_DEADLINE=2` makes the probe exit 3 in under 5 s. Its stdout holds exactly five `::koto-finding::` lines, one per never-opened lookup (`lookup=explore-t handoff/scope.md`, `lookup=plan-t`, `lookup=design-t`, `lookup=prd-t`, `lookup=brief-t`), each with `outcome=deadline next=stop-and-act` and `koto=none before the deadline` as its last field, and then `row=3 unsettled`. No stub process is left running.
- [ ] The bound holds without an override: with every lookup delayed 40 s and `SCOPE_PROBE_DEADLINE=600`, the probe exits 3 in under 25 s, so the clamp holds and the default deadline plus the kill and print fits inside the gate's 30 s. This is the suite's one slow case.
- [ ] A `koto context get` read of `work/state.md` or `work/prior-run.md` runs under the same deadline: with the key present and its `context get` delayed past `SCOPE_PROBE_DEADLINE=2`, the probe exits 3 with a finding line for `scope-t work/state.md` (or `work/prior-run.md`) and `outcome=deadline`, not row 25.

Reply classification:

- [ ] The probe's `key_exists` reads `koto context exists` by the design's reply table: exit 0 present; exit 1 absent; 127 (koto missing) absent as today; exit 2, or exit 3 with `code: session_lookup_failed`, a refusal; anything else cannot-tell (exit 2). The existing cases "a state lookup koto cannot answer is cannot-tell, ahead of a present handoff" and "a handoff lookup koto cannot answer is cannot-tell" (the stub's bare exit 3 with no `code`) still exit 2.
- [ ] `child_partial` reads `has-work` exit 7 as unsettled, keeps exit 4 as cannot-tell, and keeps 0, 1 and 127 as today. The existing case "a child koto cannot report (has-work exit 4) is cannot-tell, ahead of a present handoff" still exits 2.
- [ ] A v0.37.1 refusal whose text says this directory's prefix answered empty and other prefixes went unchecked, on a lookup the ladder needs, gives a line with `outcome=refused next=stop-and-act` and `koto=session_lookup_failed ...`. The second refusal message, without that phrase, gives `outcome=refused next=tick-again`. A v0.37.0 exit-2 refusal of `koto status` that `has-work` reports as exit 7 gives `outcome=refused next=tick-again`.
- [ ] In ladder order, the first input the ladder needs that is cannot-tell gives exit 2, and the first it needs that is refused gives exit 3; the probe stops waiting at whichever comes first. A case pins each order: a refused `scope-t` key ahead of a cannot-tell child gives 3, and a cannot-tell `scope-t` key ahead of a refused child gives 2.
- [ ] No refusal and no deadline is ever read as absent: across every new case, a lookup whose reply is a refusal or that was killed at the deadline never yields a row that the lookup's absence would select (10, 11, 12's fall-through, or a Slot 6 miss).

The handover from <<ISSUE:1>> and #1792:

- [ ] The `resume-probe_test.sh` case <<ISSUE:1>> added, where one child's `koto status` answers exit 3 `session_lookup_failed` while `explore-t` holds `handoff/scope.md`, and which <<ISSUE:1>> left expecting exit 2 `row=2 cannot-tell` with stderr `has-work <child> t exited 7`, now expects exit 3. Its stdout holds a `::koto-finding::` line with `lookup=<child>-t outcome=refused` and `koto=session_lookup_failed` followed by the reduced message, then `row=3 unsettled`. Row 12 needs all four children settled, and exit 7 is unsettled, so the handoff can't fire.
- [ ] Every case `resume-probe_test.sh` holds before this change keeps its expected exit code, with one exception: the <<ISSUE:1>> case above, which moves from 2 to 3. `bash skills/scope/scripts/resume-probe_test.sh` passes.
- [ ] Closes #1792: a child lookup's transient `session_lookup_failed` refusal holds the run at `resume_route` instead of ending it at `done_error`. The probe exits 3 for it (the case above), and `bash skills/scope/scripts/scope-template_test.sh` passes with its "resume_route routes each probe code to its row's target" map still holding no key `"3"`, so koto finds no arm and holds. `done_error` stays reserved for exit 2, the cannot-tell answers a retry won't change.

Finding lines:

- [ ] Every finding line starts with `::koto-finding::`, carries `lookup=`, `outcome=` and `next=` built by the probe, and ends with `koto=` as its last field. A `stop-and-act` line names declaring the bucket's name index in a field before `koto=`. No finding line and no other probe output contains `--local-topic`; a test asserts that, and the assertion holds until <<ISSUE:5>> adds the `--local-topic=stated` remedy.
- [ ] The `koto=` text is reduced by allowlist. A stub reply whose message holds a second line, a URL with userinfo and a query (`https://user:secret@host.example/p/x?sig=abc`), the characters `$ ; = & \` " < >`, an embedded `::koto-finding:: lookup=forged`, and 1000 characters of padding produces one line that: keeps koto's `code`; keeps only the message's first line; cuts the URL to scheme, host and path (no `user:secret@`, no `?sig=abc`); holds no character outside letters, digits, space and `._:/'()-`; has a `koto=` value of at most 300 characters; and holds `::koto-finding::` only at the start of the line, so stdout has exactly one finding line for that lookup.

Arguments:

- [ ] `--local-topic stated` and `--local-topic unstated` are accepted once; with no `--local-topic` the probe behaves as with `unstated`. A repeated `--local-topic`, a missing value, or any other value (`--local-topic maybe`, `--local-topic=stated`) is a usage error, exit 64, before any koto call (the stub log stays empty). In this issue a fresh topic run with `--local-topic stated` gives the same exit and the same lines as one without it.

Processes and temp files:

- [ ] The kill walks descendants: for each job that is still running and has written no marker, the probe signals the job's children (`pkill -P <job>`) and then the job, using ids taken from its own job list. This reaches the koto that `has-work` starts through command substitution. After every early-answer, deadline and refusal case above, none of the recorded stub process ids is still running.
- [ ] The kill never matches by name: `grep -nE 'pkill +-f|killall|pgrep +-f' skills/scope/scripts/resume-probe.sh`, ignoring comment lines, prints nothing.
- [ ] The probe still writes nothing but its own `mktemp -d` directory: the snapshot check holds on every new case, and `tmp_gone` finds the directory removed after every new case, including deadline exits. The existing "a probe killed mid-lookup" case still passes.
- [ ] The probe runs on bash 3.2: with macOS's `/bin/bash` (3.2) first on `PATH`, `bash skills/scope/scripts/resume-probe_test.sh` passes, and `grep -nE 'wait -n|declare -A|local -A|mapfile|readarray' skills/scope/scripts/resume-probe.sh` prints nothing.
- [ ] Decision 1's first assumption is checked and the result written in the pull request: within a tick, after `record-scope-exit.sh --stage resume`'s `koto context` calls, the resumed topic's `scope-<topic>` copy on this host is current, so the probe's own-key `context exists` and `context get` reads make no bucket request at koto v0.37.0 and v0.37.1. The pull request cites the koto source path or a traced run that shows it. If the assumption doesn't hold, the pull request says so and a follow-up issue is filed before merge.

Documentation in the repo:

- [ ] The probe's header lists exit 3 (unsettled, no route, the run holds) beside exit 2, the deadline and its override, the finding-line format, and the `--local-topic` argument; `bash skills/scope/scripts/resume-probe.sh --topic t` prints a usage line that names `--local-topic <stated|unstated>`.
- [ ] `skills/scope/references/phases/phase-resume.md`, the ladder's normative spec, gains a row for the probe's unsettled answer: `grep -n '\[3\]' skills/scope/references/phases/phase-resume.md` shows a row saying the run holds at `resume_route` with the finding lines on the gate's blocking condition.

Downstream deliverables:

- [ ] Must deliver: the probe's exit 3 as an unrouted hold, with stdout of finding lines then `row=3 unsettled`, and a worst-case probe time under 25 s at the default deadline (the no-override slow case above), so the gate's `timeout: 30` is a backstop that the probe's own deadline beats (required by <<ISSUE:4>>).
- [ ] Must deliver: the internal `--local-topic <stated|unstated>` argument parsing with its usage error before any koto call; one function that builds a finding line from the probe's fields, with the remedy field before `koto=` that the `stop-and-act` advice fills; the reduction of koto's text; and a poll loop that can start further lookups mid-run inside the same deadline and kill them the same way (required by <<ISSUE:5>>).

**Dependencies**: Blocked by <<ISSUE:1>>

**Type**: code

**Complexity**: critical

### Issue 4: fix(scope): bound the ladder and pointer gates with a timed_out backstop

**Goal**: Give the `ladder` gate in `resume_route` and the `pointer` gate in `resume_stale` a stated 30 s bound with a `timed_out` arm to `done_error`, leave the probe's exit 3 unrouted so the run holds, and rewrite both states' directives so an agent knows what a hold means and what to do next.

**Acceptance Criteria**:

Gate bound and routing (observed through `koto template compile` in `skills/scope/scripts/scope-template_test.sh`):

- [ ] `bash skills/scope/scripts/scope-template_test.sh` exits 0, and its output includes passing cases showing that the compiled `resume_route.gates.ladder.timeout` and `resume_stale.gates.pointer.timeout` are both `30`.
- [ ] The same run passes a case showing that `resume_route` has exactly one arm whose `when` holds `gates.ladder.error: timed_out`. That arm targets `done_error`, assigns `outcome: error` and `step: "scope:resume-probe"`, and has a `failure_reason` that is fixed text with no `${...}` interpolation and says the probe's own deadline did not fire.
- [ ] The same run passes a case showing that `resume_stale` has exactly one arm whose `when` holds `gates.pointer.error: timed_out`. That arm targets `done_error` with the same `outcome`, `step` and fixed-text `failure_reason` shape.
- [ ] The same run passes a case showing that no transition in `resume_route` or `resume_stale` names exit code 3 on `ladder` or `pointer`, and that neither state has an unconditional transition, so exit 3 holds.
- [ ] The existing case "resume_route routes each probe code to its row's target" still passes. Its expected map adds the `timed_out` arm (exit code `-1` to `done_error`) and still has no key `3`. The existing "row 2 ends scope:resume-probe" case is unchanged and passes.
- [ ] The `ladder` and `pointer` gates keep `overridable: false`, and their commands keep the arguments they pass today (`--topic`, `--intent`, and `--ignore-stale` on `pointer`). The existing "resume_route has one gate, running resume-probe.sh, not overridable" case passes unchanged.

Hold directive (observed by `scope-template_test.sh` reading the `## resume_route` and `## resume_stale` sections of `scope.md`):

- [ ] The same run passes cases showing that each of the two sections says an exit 3 holds the run and tells the agent to read the `::koto-finding::` lines on the gate's blocking condition. Each section names `next=tick-again` (tick again once the bucket answers) and `next=stop-and-act` (tick at most once more, then stop and report, under `--auto` too). Each names declaring the bucket's name index as the way through when another tick won't help.
- [ ] The same run passes a case showing that each section treats the `koto=` field as quoted data and tells the agent never to paste `koto=` text into a pull request, issue or commit, but to describe the stop in its own words.
- [ ] The same run passes a case showing that each section says a gate stopped at its 30 s bound ends the run at `done_error` with `step=scope:resume-probe`. The current sentence, which reads any unrouted probe code as "the probe itself could not run", no longer describes exit 3 that way.
- [ ] The same run passes a case asserting that neither the `## resume_route` nor the `## resume_stale` section of `scope.md` contains the text `--local-topic`. This assertion holds until <<ISSUE:6>> lands, and <<ISSUE:6>> changes it to require `--local-topic=stated` in the hold directive.

Behaviour against real koto (observed by `bash skills/scope/scripts/scope-substrate_test.sh`, which already drives real koto against the shipped template in an isolated store with names outside any production prefix):

- [ ] A run uses a plugin root that copies this checkout's `skills/` but replaces `resume-probe.sh` with a stub that prints one `::koto-finding::` line and exits 3. Its first tick stops in `resume_route`, the response's blocking condition for `ladder` carries exit code 3 and the stub's finding line, and a second tick is still in `resume_route`.
- [ ] A run with a stub probe that sleeps well past 30 s ends at `done_error` with `step` `scope:resume-probe` and the fixed `failure_reason`, and the tick that runs the gate returns in under 45 s.
- [ ] A run reaches `resume_stale` with a stub that answers 24 without `--ignore-stale` and sleeps past 30 s with it. Submitting `stale_choice: resume` ends the run at `done_error` with `step` `scope:resume-probe`.
- [ ] `scripts/check-skill.sh --changed scope` exits 0.

Downstream:

- [ ] Must deliver: the `timeout: 30` gates and the `timed_out` arms on `ladder` and `pointer`, keyed so that adding the `--local-topic "{{LOCAL_TOPIC}}"` gate argument doesn't touch them; the hold directive sections in `resume_route` and `resume_stale` that <<ISSUE:6>> extends with the `--local-topic=stated` remedy; and the "does not contain `--local-topic`" assertion in `scope-template_test.sh` that <<ISSUE:6>> flips (required by <<ISSUE:6>>).

Out of scope: any change to `resume-probe.sh` (<<ISSUE:3>>, and <<ISSUE:5>> for the stated-local-topic path); the `LOCAL_TOPIC` variable, the gate argument and the `--local-topic=stated` remedy text (<<ISSUE:6>>).

**Dependencies**: Blocked by <<ISSUE:3>>

**Type**: code

**Complexity**: testable

### Issue 5: feat(scope): settle never-opened names under a stated local topic

**Goal**: Under `--local-topic stated`, `resume-probe.sh` settles the five never-opened names from one `koto session list` plus one `koto --workspace <this dir>` read per name it doesn't show, read by exit code and `code`, and every `stop-and-act` finding line names the remedy as exactly `--local-topic=stated` alongside the index declaration.

**Acceptance Criteria**:

The statement path:

- [ ] The `resume-probe_test.sh` stub koto gains a `koto session list` reply (the names it lists set by the test), a `koto --workspace <dir> status <name>` reply set per name (exit 2 with `code` `session_not_found`, exit 2 with `code` `workspace_not_found`, exit 0, exit 3 with `code` `workspace_unreadable`, and an unknown shape), and a way to make `session list` fail. It keeps logging every call to `STUB_LOG`, so each case below observes which koto calls ran.
- [ ] With `--local-topic unstated`, and with no `--local-topic` at all, `STUB_LOG` holds no `session list` line and no `--workspace` line, and every existing `resume-probe_test.sh` case keeps the exit code it has once <<ISSUE:3>> lands.
- [ ] Fresh topic on a large undeclared bucket, stated: every ordinary lookup of the five never-opened names refuses with exit 3 `session_lookup_failed` and the own-prefix-empty text, `session list` shows none of them, and each `--workspace` read answers exit 2 `session_not_found`. The probe exits 10 with `row=10 fresh-start`, and `STUB_LOG` shows exactly one `session list` line and one `--workspace <dir> status <name>` line for each of the five names.
- [ ] The same case with `--workspace` answering exit 2 `workspace_not_found` for every name also exits 10.
- [ ] The same refusals without the statement (`--local-topic unstated`) exit 3 with a `next=stop-and-act` finding line for the first unsettled lookup the row needs; the statement is what turns that exit 3 into row 10.
- [ ] A name `session list` shows gets no `--workspace` read: with `plan-t` listed and its ordinary `has-work` refusing (exit 7), the probe exits 3 with a finding line for `plan-t`, and `STUB_LOG` holds no `--workspace` line for `plan-t`.
- [ ] A `--workspace` read that answers exit 0 for a child sends it to its ordinary `has-work`: with `design-t` unlisted, `--workspace` exit 0 and `has-work` answering work under `work/`, the probe exits 61 with `row=61 design-partial`; with the same `--workspace` exit 0 and `has-work` refusing, it exits 3.
- [ ] A `--workspace` refusal is never absent: with `brief-t` unlisted and its `--workspace` read answering exit 3 `workspace_unreadable` while its ordinary lookup also refuses, the probe exits 3 with a `::koto-finding::` line whose `lookup=` names `brief-t` and whose `koto=` field carries `workspace_unreadable`. The same holds for the unknown-shape reply (exit 3, finding line, never row 10).
- [ ] The handoff under the statement: with `explore-t` unlisted, every child settled absent and `--workspace` answering exit 2 `session_not_found` for `explore-t`, the probe exits 10, not 12, even though `STUB_KEYS` would answer `explore-t:handoff/scope.md` present through the ordinary lookup if it were reached. With `explore-t` listed and its handoff key present, the probe exits 12 with `row=12 explore-handoff`.
- [ ] A failed `session list` draws no conclusion: with `session list` exiting nonzero (and, in a second case, sleeping past the deadline) and the ordinary lookups refusing, the probe runs no `--workspace` read (`STUB_LOG` shows none) and exits 3, never 10.
- [ ] An early answer still wins under the statement: with `scope-t:work/state.md` present and every never-opened lookup slow or refusing, the probe exits with its 20-29 row and doesn't wait on `session list` or any `--workspace` read. The test's deadline override keeps this case under a few seconds.
- [ ] Both statement reads stay read-only: no `STUB_LOG` line from a stated run is a koto write (`context add`, `next`, `init`, `rewind` or any other command outside `session list`, `status` and `context exists`), and a `--workspace` read killed at the deadline leaves the probe's own temp directory removed (the existing `tmp_gone` check).

The remedy text:

- [ ] A `stop-and-act` finding line names the remedy as exactly `--local-topic=stated`, alongside the index declaration that <<ISSUE:3>>'s lines carry. A `resume-probe_test.sh` case drives the own-prefix-empty refusal under `--local-topic unstated` and checks that the line contains the literal substring `--local-topic=stated` and the index declaration, and that the remedy sits in a field the probe builds ahead of `koto=`, so `koto=` stays the last field.
- [ ] A `next=tick-again` line doesn't mention `--local-topic`: a case drives a refusal without the own-prefix-empty text and checks that its finding line has no `--local-topic` substring.
- [ ] Under `--local-topic stated`, a `stop-and-act` line doesn't repeat the `--local-topic=stated` remedy, since the statement is already in force, and still names the index declaration. A case drives a failed `session list` with the own-prefix-empty refusal under `stated` and checks the line.
- [ ] A refusal whose koto text imitates a remedy can't add one: a stub reply whose message contains `--local-topic=stated` and `::koto-finding::` produces a finding line where that text appears only inside the reduced `koto=` field (with `::koto-finding::` neutralized, per <<ISSUE:3>>'s reduction), and a `tick-again` line's probe-built fields still carry no `--local-topic`.

The probe's argument:

- [ ] The probe keeps its internal argument as `--local-topic <stated|unstated>`, space-separated and accepted once. `--local-topic maybe`, `--local-topic` with no value, `--local-topic stated --local-topic stated`, and the equals form `--local-topic=stated` passed to the probe each exit 64 with a usage message, and `STUB_LOG` stays empty, so no koto call runs before the value is checked.

Downstream:

- [ ] Must deliver: the exact remedy text `--local-topic=stated` printed in every `stop-and-act` finding line under `unstated`, pinned by a `resume-probe_test.sh` case that observes it, so `scope-open.sh` can be tested to accept that printed text verbatim (required by <<ISSUE:6>>).
- [ ] Must deliver: the probe's internal `--local-topic <stated|unstated>` argument with `stated` settling the five never-opened names as above, so the `LOCAL_TOPIC` rebind variable the gates pass as `--local-topic "{{LOCAL_TOPIC}}"` takes effect end to end (required by <<ISSUE:6>>).
- [ ] `bash skills/scope/scripts/resume-probe_test.sh` and `scripts/check-skill.sh --changed scope` pass.

**Dependencies**: Blocked by <<ISSUE:3>>

**Type**: code

**Complexity**: critical

### Issue 6: feat(scope): add --local-topic to the scope opener

**Goal**: Let an operator at an interactive `/scope` invocation state `--local-topic=stated` through `scope-open.sh`, and nobody else: the opener checks the spelling and the value, refuses the flag under `--auto` and in a dispatched run, binds the `LOCAL_TOPIC` rebind variable that both resume gates pass to the probe, and the scope skill's usage text and argument hint say when to use it.

**Acceptance Criteria**:

Accepting the statement:

- [ ] `bash skills/scope/scripts/scope-open_test.sh` has a case that runs `scope-open.sh` with tokens `["<topic>","--local-topic=stated"]` and observes exit 0, `session=scope-<topic>` on stdout, and the vars file koto was handed (the suite's `vars.last` copy) carrying exactly one `["LOCAL_TOPIC","stated"]` pair; koto's record of the opened `scope-<topic>` workflow then shows `LOCAL_TOPIC` as `stated`.
- [ ] The same suite runs `["<topic>","--local-topic=unstated"]` and `["<topic>"]` (no flag) and observes exit 0 with `LOCAL_TOPIC` recorded as `unstated` in both.
- [ ] A `scope-open_test.sh` case takes the remedy token from what `resume-probe.sh` prints on a `next=stop-and-act` finding line, or from the one place `resume-probe.sh` defines that text, rather than retyping it, passes it to `scope-open.sh` unchanged, and observes exit 0 with `LOCAL_TOPIC` recorded as `stated`. Changing the remedy text on either side fails this case.
- [ ] One invocation only: a `scope-open_test.sh` case opens `<topic>` with `--local-topic=stated`, then invokes `scope-open.sh` again for the same topic with no flag, observes `opened=attached`, and observes `LOCAL_TOPIC` recorded as `unstated` after the second open.

Refusing the wrong spelling or value (each case in `scope-open_test.sh`):

- [ ] A bare `--local-topic`, a space-separated `--local-topic stated`, `--local-topic=yes`, `--local-topic=STATED`, an empty `--local-topic=`, and `--local-topic=stated` given twice are each refused: a non-zero exit (2 from koto or 64 from the opener), stdout carries `outcome=error` and `step=scope:refused` and never `outcome=refused`, stderr names `--local-topic` and shows the accepted form `--local-topic=stated`, the args file is gone, and `koto status scope-<topic>` fails afterwards.
- [ ] For the space-separated case, the refusal names `--local-topic`, not only the topic slug: an operator who typed `--local-topic stated` is told the spelling is wrong, not that `<topic> stated` is a bad slug.

Refusing the flag in an unattended run (each case in `scope-open_test.sh`):

- [ ] `--auto` together with `--local-topic=stated`, in either order, is refused with the same shape as above: non-zero exit, `outcome=error`, `step=scope:refused`, stderr naming `--local-topic` and saying it isn't accepted under `--auto`, no `scope-<topic>` workflow afterwards. `--auto` with `--local-topic=unstated` is refused the same way, so the flag never appears in an unattended run at all.
- [ ] `--interactive` together with `--local-topic=stated` is accepted, with exit 0 and `LOCAL_TOPIC` recorded as `stated`.
- [ ] A dispatched run is refused: `--koto-leg=<request-id>:scope` together with `--local-topic=stated` exits non-zero with no `scope-<topic>` workflow afterwards, and `koto request get <request-id>` shows the `scope` leg resolved with a refused result, so the caller waiting on the leg reads the refusal instead of waiting. The same suite has one more refusal case for each other dispatched-run signal the implementation reads (see the open point), and `scope-open.sh`'s header names every signal it reads and what it can't detect.

Template variable and gate argument:

- [ ] `bash skills/scope/scripts/scope-template_test.sh` passes with new cases that read the compiled template and observe: `LOCAL_TOPIC` declared with `values: [stated, unstated]`, default `unstated` and `rebind: true`; the `ladder` gate in `resume_route` and the `pointer` gate in `resume_stale` each carrying `--local-topic "{{LOCAL_TOPIC}}"` in their command; and the existing check that every gate command quotes each `{{VAR}}` it uses still passing over both commands.
- [ ] The existing `resume_route` cases in `scope-template_test.sh` (the gate is the one non-overridable `ladder` gate running `resume-probe.sh`, and each row code routes to its target) still pass unchanged, and exit 3 still has no route.

Directive, with the handover from <<ISSUE:4>>:

- [ ] `bash skills/scope/scripts/scope-template_test.sh` passes with <<ISSUE:4>>'s assertion changed from "the hold directive does not mention `--local-topic`" to "the `## resume_route` and `## resume_stale` sections each name `--local-topic=stated`", and no assertion that the directive omits `--local-topic` is left in the file.
- [ ] The same test asserts that both sections show the remedy as the operator's re-run, `/scope <topic> --local-topic=stated` (with the topic written out through `{{TOPIC}}` or as `<topic>`), state that the agent never adds the flag itself, and that under `--auto` the agent stops and reports the two remedies instead of re-running; and that neither section contains the space-separated form `--local-topic stated`.
- [ ] The directive says what the statement gives up, in a sentence the test can find: a same-named run or handoff held under another directory or on another host is not seen.

Usage text and argument hint (the plan's docs coverage for this user-visible surface):

- [ ] `skills/scope/SKILL.md`'s `argument-hint` gains `[--local-topic=stated]`, and a new section next to Execution-Mode Flags and Request Leg Flag tells an operator when to use it: only when they know the topic has no run on another host, checkout or worktree; what it gives up; that it covers this one invocation and is recorded; that `scope-open.sh` refuses it under `--auto` and in a dispatched run; and that declaring the bucket's name index is the alternative that clears the stop for every topic. Observed by the validation script's `grep` checks below and by `scripts/check-skill.sh --changed scope` passing its `shirabe validate` step over `SKILL.md`.
- [ ] Neither `SKILL.md` nor `scope-open.sh`'s usage and token-mapping comment shows the space-separated `--local-topic stated` or `--local-topic unstated` as something an operator types; the probe's internal argument appears only in the two gate commands and the probe's own files.
- [ ] `scope-open.sh`'s refusal wording is rendered the same way as the existing refusals: from `skills/scope/scripts/scope-open.wording.tsv` when koto refuses (for example an `invalid_var:LOCAL_TOPIC` row), or from the opener's own message when it refuses first. Observed by the stderr checks in the refusal cases above.

Eval scenario:

- [ ] `skills/scope/evals/evals.json` gains a scenario that runs `/scope <topic> --local-topic=stated --auto` and a bare `/scope <topic> --local-topic stated`, and expects each to be refused before any work with an error naming `--local-topic`, `outcome=error` and `step=scope:refused`, no `scope-<topic>` workflow afterwards, and no child skill invoked. Observed by `scripts/check-skill.sh --changed scope` printing `ok: eval shape (.../skills/scope/evals/evals.json)` and by the validation script's `jq` check that a scenario's prompt contains `--local-topic=stated --auto`. The scenario runs with the other changed-skill scenarios in the release precondition (`scripts/run-evals.sh scope` runs it locally).

Overall:

- [ ] `scripts/check-skill.sh --changed scope` exits 0, running the `scope-open_test.sh` and `scope-template_test.sh` suites the change touches.

**Dependencies**: Blocked by <<ISSUE:4>>, <<ISSUE:5>>

**Type**: code

**Complexity**: critical

## Dependency Graph

```mermaid
graph TD
    I1["1: read koto's replies by exit code and code first"]
    I2["2: run the reply table and parent_state against real koto"]
    I3["3: resume probe deadline, early answer and unsettled hold"]
    I4["4: bound the ladder and pointer gates"]
    I5["5: settle never-opened names under a stated local topic"]
    I6["6: add --local-topic to the scope opener"]

    I1 --> I2
    I1 --> I3
    I3 --> I4
    I3 --> I5
    I4 --> I6
    I5 --> I6

    classDef done fill:#c8e6c9
    classDef ready fill:#bbdefb
    classDef blocked fill:#fff9c4
    classDef needsDesign fill:#e1bee7
    classDef needsPrd fill:#b3e5fc
    classDef needsSpike fill:#ffcdd2
    classDef needsDecision fill:#d1c4e9
    classDef tracksDesign fill:#FFE0B2,stroke:#F57C00,color:#000
    classDef tracksPlan fill:#FFE0B2,stroke:#F57C00,color:#000

    class I1 ready
    class I2,I3,I4,I5,I6 blocked
```

**Legend**: Green = done, Blue = ready, Yellow = blocked, Purple = needsDesign, Light blue = needsPrd, Red = needsSpike, Lavender = needsDecision, Orange = tracksDesign / tracksPlan

## Implementation Sequence

**Critical path:** Issue 1, then Issue 3, then Issue 4, then Issue 6 (four issues). Issue 5 runs alongside Issue 4 and is the same length.

**Parallelization:**

- Issue 1 starts immediately; nothing blocks it.
- After Issue 1, Issues 2 and 3 can be worked in parallel. Nothing waits on Issue 2, so it can still be open while later issues land.
- After Issue 3, Issues 4 and 5 can be worked in parallel. They touch different files: Issue 4 the template and its tests, Issue 5 the probe and its tests.
- Issue 6 starts once Issues 4 and 5 have both landed, since it changes Issue 4's directive assertion and accepts the remedy text Issue 5 prints.

**Recommended order:** 1, 3, then 4 and 5 together, then 6, with 2 slotted in whenever its CI provisioning is ready. Each issue lands in its own pull request.
