---
schema: plan/v1
status: Active
execution_mode: single-pr
split_mode_source: none
tracking_level: none
upstream: docs/designs/DESIGN-validate-and-return.md
milestone: "Validate-and-return on koto gates"
issue_count: 4
---

# PLAN: validate-and-return

## Status

Active

Authored at Active: the tracking level is `none`, so nothing is filed and the
four outlines below are the work items.

## Scope Summary

Make every `/work-on` output gate escalate a failing rule's text on koto's own
per-rule count (summary, then full registry text, then a named exit notice),
add the `check_unsatisfiable` exit through a `check_exit` marker state at the
three holding gates, and move the canary's PB4 release onto the same ladder,
as DESIGN-validate-and-return describes.

## Decomposition Strategy

**Horizontal.** The design builds four layers with stable interfaces between
them: the findings library, the gate scripts that call it, the template that
supplies its context, and the documents. Each layer is inert until the next
one feeds it (the library does nothing without context, and the scripts
supply none on their own), so every step leaves the tree green and there is no
end-to-end thread a walking skeleton would add. The one runtime integration
risk, whether the gate's count matches koto's, is settled by the end-to-end
test in Issue 3, which drives a real koto session.

One pull request: the repository's default delivery preference is
consolidated, no hard constraint forces a split, and a partial landing would
ship either an unused library or a template calling a function that isn't
there yet.

## Issue Outlines

### Issue 1: feat(rule-findings): escalate a rule's text on koto's per-rule count

**Goal**: `scripts/lib/rule-findings.sh` records the rule ids a gate prints and gains `rf_deliver`, which reads koto's per-rule counts from the session log named by the ladder context and releases full text at count 2 and an exit notice at count 3, with no effect when no context is supplied.

**Acceptance Criteria**:
- [ ] `rf_emit` appends each printed rule id to `RF_REPORTED` once, in first-printed order, and `rf_finding` inherits it.
- [ ] `rf_ladder_active` is true when `SHIRABE_GATE_LOG` or `SHIRABE_GATE_NAME` is non-empty; with neither set, `rf_deliver` prints nothing and returns 0.
- [ ] The log reader takes the state from the `to` of the last `transitioned`, `directed_transition` or `rewound` event and the prior count from the highest `rule_counts[<id>].session` on `gate_evaluated` events with that state and `SHIRABE_GATE_NAME`; a readable log with no match gives count 1.
- [ ] At count 2 or more `rf_deliver` runs `rule-registry.sh release <id>` once per id; at count 3 or more, in a state `rf_exit_field` finds in `SHIRABE_GATE_EXITS`, it prints one `::shirabe-check-exit::` line naming the first-printed rule with the highest count, its count, the state, the evidence object and `done_blocked`.
- [ ] A missing or unreadable log, a first line that isn't a schema-version-1 header, or no transition gives count 2 for every id, one fixed diagnostic line on stderr, and no notice; `jq`'s own message isn't printed.
- [ ] `rf_deliver` runs at most once per process, writes only to stderr and always returns 0.
- [ ] `RF_FULL_TEXT_AT=2` and `RF_EXIT_AT=3` are defined once, and the library header documents the ladder.
- [ ] A fixture whose prior event has `rule_counts[<id>]` of `{"visit": 1, "session": 2}` (a later visit) gives count 3, not 2: the reader uses `session`.
- [ ] Probe tests in `scripts/rule-registry_test.sh` cover counts 1, 2 and 3, two rules, another gate, state or rule, the state read from the latest transition, a count claimed outside the log, each read failure, a state outside the exit table, a tie at count 3, and the no-context case.
- [ ] A test lists the rules each `/work-on` gate script can report that `release` refuses (`pr-body/banned-word`, `pr-body/conformance`, `docs/private-only-type`, `docs/visibility-vision-sections`, `docs/visibility-strategy-sections`) and fails when that set changes.
- [ ] The library tests pass under bash 3.2.

**Dependencies**: None

**Type**: code
**Files**: `scripts/lib/rule-findings.sh`, `scripts/rule-registry_test.sh`

### Issue 2: feat(work-on): deliver the ladder from the output gate scripts

**Goal**: `check-pr-output.sh`, `check-branch-output.sh`, `check-verification.sh` and `panel-scope.sh` call `rf_deliver` before each non-zero exit that follows printed findings, and `check-pr-output.sh` releases PB4 by its own code only when the ladder is off.

**Acceptance Criteria**:
- [ ] Each of the four scripts calls `rf_deliver` immediately before every non-zero exit that follows a printed finding (`--pr-body`'s exit 1; `check-branch-output.sh`'s exits 1; `check-verification.sh --verdict`'s `exit "$VERDICT"` when findings were printed; `panel-scope.sh --verdict`'s exit 1).
- [ ] `check-pr-output.sh` runs its PB4 `release` only when `rf_ladder_active` is false; its existing PB4 release tests still pass as the no-context case.
- [ ] With ladder context and a fixture log, `check-pr-output.sh --pr-body` on a PB4 violation prints PB4's summary finding and no release at count 1, and PB4's release block once at count 2.
- [ ] Each script's suite has a laddered failing case, and a check that its exit status and standard output are byte-identical with and without the context for a passing, a violating and an undecided run.
- [ ] `scripts/check-rule-registry.sh` and its tests still pass.

**Dependencies**: Blocked by <<ISSUE:1>>

**Type**: code
**Files**: `skills/work-on/scripts/check-pr-output.sh`, `skills/work-on/scripts/check-branch-output.sh`, `skills/work-on/scripts/check-verification.sh`, `skills/work-on/scripts/panel-scope.sh`

### Issue 3: feat(work-on): pass the ladder context and add the named check exit

**Goal**: `/work-on`'s template supplies the ladder context on its ten output gates, and `pr_creation`, `finalization` and `pr_precheck` accept `check_unsatisfiable` with `check_exit_reason`, routed through a `check_exit` marker state to `done_blocked`.

**Acceptance Criteria**:
- [ ] `pr_body_conformant`, the three `commit_convention` copies, `branch_docs_visibility`, `verification_verdict`, `scrutiny_verdict`, `review_verdict`, `qa_verdict` and `light_verdict` carry `SHIRABE_GATE_LOG="{{SESSION_DIR}}/koto-{{SESSION_NAME}}.state.jsonl"`, their own `SHIRABE_GATE_NAME` and the same `SHIRABE_GATE_EXITS` string, after their `test -x` guard; the three `commit_convention` copies stay byte-identical.
- [ ] The three states add `check_unsatisfiable` to `pr_status`, `finalization_status` and `precheck_status`, accept `check_exit_reason`, and route it to `check_exit` only with the state's registry gate at exit 1, setting `failure_reason` to `check_exit at <state>: <gate> could not be satisfied: <reason>`.
- [ ] `check_exit` has one unconditional transition, to `done_blocked`, and a `## check_exit` directive section.
- [ ] The three directives say a failing gate's output escalates, that the exit is offered from the third failed evaluation of a rule, how to take it (`check_unsatisfiable`, `check_exit_reason`), that it ends the run at `done_blocked`, and, at `pr_creation`, to mark the pull request draft with `gh pr ready --undo` first; `pr_creation`'s directive names no PB4 text and stays identical across canary groups.
- [ ] `work-on.mermaid.md` is regenerated with `koto template export` and `scripts/validate-template-mermaid.sh` passes.
- [ ] `output-gates-routing_test.sh` covers the exit at each state with the gate at 1 (reaches `done_blocked` through `check_exit`, `failure_reason` in the stated format, including an empty reason), 0 and 2 (holds), the `check_exit` target set, the prefix on every listed gate, and the exit table matching the states that have a `check_unsatisfiable` edge.
- [ ] One test drives the shipped template through a real koto session to a PB4 failure twice and the exit once, checking that the gate's count matches the `rule_counts` koto recorded and that the run journal holds a `state_entered` record for `check_exit`.
- [ ] The `pr-shared` eval fixture's `pr_status` values include `check_unsatisfiable`.
- [ ] `finalization-shape_test.sh`, `offload-canary-routes_test.sh` and `scripts/check-skill.sh skills/work-on` pass.

**Dependencies**: Blocked by <<ISSUE:2>>

**Type**: code
**Files**: `skills/work-on/koto-templates/work-on.md`, `skills/work-on/koto-templates/work-on.mermaid.md`, `skills/work-on/scripts/output-gates-routing_test.sh`

### Issue 4: docs(rule-registry): document the ladder and move the canary's PB4 text

**Goal**: `references/rule-registry.md` documents the ladder and the exit, and the canary's guide and design say PB4's full text arrives on the second failure in a laddered run.

**Acceptance Criteria**:
- [ ] `references/rule-registry.md` has an "Escalating a rule's text" section covering the ladder context, the count, the three rungs and their thresholds, the unreleasable rules, and the exit and how it's counted from exported records.
- [ ] Its "Delivering a rule when it applies" paragraph on the PR-body gate says PB4 is released by the ladder in a laddered run and on every failure outside one.
- [ ] `docs/guides/offload-live-canary.md` and `docs/designs/current/DESIGN-offload-live-canary.md` no longer say PB4's text arrives on the first failure in a laddered run, and the guide says how to split PB4 runs by `koto.rule.session_count`.
- [ ] `references/rule-registry.json` is unchanged.
- [ ] `shirabe validate` passes on every changed document at public visibility.

**Dependencies**: Blocked by <<ISSUE:3>>

**Type**: docs
**Files**: `references/rule-registry.md`, `docs/guides/offload-live-canary.md`, `docs/designs/current/DESIGN-offload-live-canary.md`

## Implementation Sequence

**Critical path**: Issue 1 -> Issue 2 -> Issue 3 -> Issue 4 (length 4). The
chain is strictly sequential: each layer consumes the one before it, and the
documents describe the shipped behaviour, so they come last. Nothing runs in
parallel; the four land as commits in one pull request.
