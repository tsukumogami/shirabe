#!/usr/bin/env bash
# deliver-engine_test.sh -- deliver.md on a real koto, walked through every
# route that matters, with the outcome asserted from `koto status` on the
# deliver-<topic> session.
#
# The children are stand-ins (testdata/engine-lib.sh): throwaway templates
# named scope.md and execute.md (the file names the legs accept), each a
# single state whose evidence becomes its terminal result, so a case can make
# a child promote any payload it needs. They attach to this run's legs with
# `koto init --koto-leg`, exactly as /scope and /execute do. The re-checks run for real
# (deliver-probe.sh, owned-pr.sh, publish-scoping-pr.sh --verify,
# merge-verdict.sh --confirm) against real git with a local bare origin and
# the gh stand-in in testdata/gh.
#
# Routes asserted:
#   - the three paths into `done` and the `pr` each reports: the /execute
#     leg's own pr on ready-awaiting-merge; the owned PR the probe found on
#     merged_check and on executed_check, replacing the leg's; no pr at all
#     when merged_check's lookup failed
#   - the --auto merged happy path: checked_pr left non-empty by scoped_check
#     before mode_route, and a `done` result whose pr equals the owned PR's
#     URL and checked_pr
#   - a merged claim GitHub contradicts is downgraded to ready-awaiting-merge,
#     and a leg pr naming some other merged PR is ignored
#   - explicit resolves with progress-shaped payloads on either leg end
#     deliver:child-absent without reaching scoped_check, execute_run,
#     merged_check, done or done_stopped, and without the forged pr
#   - `koto overrides record`, with and without --with-data, refused on both
#     leg gates and the intent gate
#   - a child that never attaches ends deliver:child-absent through the absent
#     state; a child bound in the meantime keeps the run waiting
#   - refusals on the leg: an invalid INTENT_FLAG (scope:refused), a live
#     intent=stop session (deliver:intent-mismatch), a throwaway template on
#     the execute leg (the leg lost: deliver:child-absent,
#     execute-leg-lost:template-mismatch, execute_state absent, as the
#     refused child opened no session); a promoted intent-mismatch refusal
#   - the start gate reads /scope's intent and PR from its leg: a result of
#     stop fails it while the body says continue; a body with no intent=
#     line, or one recording intent=stop, beside a result of continue
#     passes; a result naming another PR fails
#   - the handover: execute_run's directive appends nothing (`none`) on a
#     single-pr PLAN, with or without STORE, and `--coordination-pr <the
#     verified PR>`, plus `--store session` when STORE is set, on a
#     coordinated one
#   - a session isolated in one repository's worktree: run from a linked
#     worktree, a coordinated PLAN with a node in another repository ends
#     deliver:worktree-isolated naming both repositories, with /execute never
#     started; a single-repo PLAN there goes on to execute_run
#   - /scope stopping early (scope-ended-early naming which), its errors, an
#     unrecognised outcome (deliver:child-outcome), the multi-pr hand-off with
#     no /execute leg bound, the interactive confirmation (stop and proceed),
#     /execute's pauses and errors, an abandoned request
#   - a private repository runs to its PR, the scope step's real publish
#     pushing the branch
#   - the stale-run fence: a new run abandons the old request, and the old
#     run's child finishing later does not answer the new run's leg
#   - the review-level bound: execute_run's rendered directive tells the agent
#     to append --review-floor=standard and --review-ceiling=full on a run
#     started with them, and renders both empty, so nothing is appended, on a
#     run started without them
#
# In a checkout whose path koto's --var allowlist refuses (a `+` in a
# directory name), the cases run a copy of deliver.md with this checkout's
# path written in for {{PLUGIN_ROOT}}, as the other engine suites do.
#
# Usage: bash skills/deliver/scripts/deliver-engine_test.sh
# Exit codes: 0 all pass (SKIP when koto or jq is absent); 1 a failure.
set -uo pipefail
. "$(dirname "$0")/../../../scripts/lib/koto-test-guard.sh" || exit 1

HERE=$(cd "$(dirname "$0")" && pwd)
REPO_ROOT=$(cd "$HERE/../../.." && pwd)
TEMPLATE="$REPO_ROOT/skills/deliver/koto-templates/deliver.md"

for bin in koto jq git; do
    command -v "$bin" >/dev/null 2>&1 || { echo "SKIP: $bin not on PATH -- the engine-backed cases did not run"; exit 0; }
done
if ! koto init --help 2>/dev/null | grep -q -- '--koto-leg'; then
    echo "SKIP: this koto predates --koto-leg -- no case ran"
    exit 0
fi
# koto's recorded command environment hides this harness's stand-in variables
# from the commands koto runs; the knob keeps the old environment where the
# koto accepts it (scripts/lib/koto-legacy-env.sh; temporary, #483).
. "$REPO_ROOT/scripts/lib/koto-legacy-env.sh"
koto_legacy_env_enable

T=$(mktemp -d "${TMPDIR:-/tmp}/deliver-engine-test.XXXXXX") || exit 1
T=$(cd -P "$T" && pwd -P) || exit 1
trap 'case "$T" in */deliver-engine-test.*) rm -rf "$T" ;; esac' EXIT
export HOME="$T/home"
mkdir -p "$HOME"
export GIT_CEILING_DIRECTORIES="$T"
export MERGE_CONFIRM_WAIT_SECS=0

PASS=0
FAIL=0
pass() { PASS=$((PASS + 1)); printf 'ok   %s\n' "$1"; }
fail() { FAIL=$((FAIL + 1)); printf 'FAIL %s\n     %s\n' "$1" "${2-}"; }
eq()  { if [ "$2" = "$3" ]; then pass "$1"; else fail "$1" "want [$2], got [$3]"; fi; }

KOTO_ALLOW='^[a-zA-Z0-9._/:@ -]*$'
TPL="$TEMPLATE"
if [[ $REPO_ROOT =~ $KOTO_ALLOW ]]; then
    PLUGIN_ROOT_VAR="$REPO_ROOT"
else
    ln -s "$REPO_ROOT" "$T/plugin"
    if [[ $T/plugin =~ $KOTO_ALLOW ]]; then
        PLUGIN_ROOT_VAR="$T/plugin"
    else
        mkdir -p "$T/derived"
        TPL="$T/derived/deliver.md"
        sed "s#{{PLUGIN_ROOT}}#$REPO_ROOT#g" "$TEMPLATE" >"$TPL"
        PLUGIN_ROOT_VAR=/koto-probe
        echo "  note: this checkout's path is outside koto's --var allowlist, so these cases run a"
        echo "        copy of deliver.md with the path written in for {{PLUGIN_ROOT}}"
    fi
fi

BIN="$T/bin"
mkdir -p "$BIN"
cp "$HERE/testdata/gh" "$BIN/gh"
chmod +x "$BIN/gh"
export PATH="$BIN:$PATH"

# The stand-in children, the fixture and the helpers: testdata/engine-lib.sh.
# shellcheck source=testdata/engine-lib.sh
. "$HERE/testdata/engine-lib.sh"

# --- the three paths into done ----------------------------------------------------------

echo "== the --auto merged happy path =="
fixture happy single-pr
start auto && to_execute_run
eq "happy: at execute_run after scoped_check, mode_route and confirm" execute_run "$(state)"
eq "happy: scoped_check left checked_pr non-empty, the owned PR" "$URL" "$(ctx checked_pr)"
eq "happy: the verified PR equals the leg's pr" "$URL" "$(ctx pr)"
eq "happy: /scope's intent was copied from its leg" continue "$(ctx scope_intent)"
db_set '(.prs[] | select(.number == 42) | .state) = "MERGED"'
child execute "{\"outcome\":\"merged\",\"pr\":\"$OTHER_MERGED\",\"repos\":\"acme/widgets\"}"
tick
expect "happy" done outcome=merged "pr=$URL" repos=acme/widgets
eq "happy: the result's pr equals checked_pr" "$(ctx checked_pr)" "$(result pr)"
eq "happy: merged_check confirmed it" merged "$(ctx merged_verdict)"

echo "== the review-level bound in execute_run's directive =="
fixture bounded single-pr
START_EXTRA=(--var REVIEW_FLOOR=standard --var REVIEW_CEILING=full)
start auto && to_execute_run
START_EXTRA=()
eq "bounded: at execute_run" execute_run "$(state)"
DIRECTIVE=$(jq -r '.directive // ""' "$T/next.json" 2>/dev/null)
case "$DIRECTIVE" in
    *'`--review-floor=standard`, only when that value after `='*) pass "bounded: the directive appends --review-floor=standard" ;;
    *) fail "bounded: the directive appends --review-floor=standard" "$(printf '%s' "$DIRECTIVE" | grep -n review)" ;;
esac
case "$DIRECTIVE" in
    *'`--review-ceiling=full`, only when that value after `='*) pass "bounded: the directive appends --review-ceiling=full" ;;
    *) fail "bounded: the directive appends --review-ceiling=full" "$(printf '%s' "$DIRECTIVE" | grep -n review)" ;;
esac
fixture unbounded single-pr
start auto && to_execute_run
DIRECTIVE=$(jq -r '.directive // ""' "$T/next.json" 2>/dev/null)
case "$DIRECTIVE" in
    *'`--review-floor=`, only when that value after `=` is not'*'`--review-ceiling=`, only when that value after `=` is not'*)
        pass "unbounded: both flags render empty, so the directive appends neither" ;;
    *) fail "unbounded: both flags render empty" "$(printf '%s' "$DIRECTIVE" | grep -n review)" ;;
esac

echo "== the start gate reads /scope's intent from its leg, not the body =="
fixture leg-stop single-pr
start auto
child scope "{\"outcome\":\"scoped\",\"intent\":\"stop\",\"pr\":\"$URL\",\"plan_path\":\"docs/plans/PLAN-$TOPIC.md\",\"plan_execution_mode\":\"single-pr\"}"
tick
expect "/scope's result says stop while the body says continue" done_error outcome=error step=deliver:child-outcome
eq "leg-stop: scoped_check failed" fail "$(ctx scoped_verdict)"
if k request get "$REQ" | jq -e '.legs.execute.bound_child == null' >/dev/null; then pass "leg-stop: /execute never started"; else fail "leg-stop: /execute never started"; fi

fixture body-no-intent single-pr
db_set '(.prs[] | select(.number == 42) | .body) = "# PR\n\nno intent line here\n"'
start auto && to_execute_run
eq "a body with no intent= line, the leg's intent continue: execute_run" execute_run "$(state)"

fixture body-stop single-pr
db_set '(.prs[] | select(.number == 42) | .body) = "# PR\n\nintent=stop\n"'
start auto && to_execute_run
eq "a body recording intent=stop, the leg's intent continue: execute_run" execute_run "$(state)"

fixture leg-other-pr single-pr
start auto
child scope "{\"outcome\":\"scoped\",\"intent\":\"continue\",\"pr\":\"$FORGED\",\"plan_path\":\"docs/plans/PLAN-$TOPIC.md\",\"plan_execution_mode\":\"single-pr\"}"
tick
expect "/scope's result naming a PR other than the owned one" done_error outcome=error step=deliver:child-outcome

echo "== the handover to /execute =="
# handover_line -- the handover arguments in execute_run's directive.
handover_line() { jq -r '.directive // ""' "$T/next.json" 2>/dev/null | tr '\n' ' ' | sed -n 's/.*handover arguments: `\([^`]*\)`.*/\1/p'; }
fixture hand-single single-pr
start auto && to_execute_run
eq "a single-pr PLAN: the handover reads none" none "$(handover_line)"
fixture hand-coord coordinated
start auto && to_execute_run
eq "hand-coord: at execute_run" execute_run "$(state)"
eq "a coordinated PLAN: --coordination-pr is the PR scoped_check verified" "--coordination-pr https://github.com/acme/widgets/pull/42" "$(handover_line)"
fixture hand-store coordinated
START_EXTRA=(--var STORE=session)
start auto && to_execute_run
START_EXTRA=()
eq "a coordinated PLAN with --store session: both flags" "--coordination-pr https://github.com/acme/widgets/pull/42 --store session" "$(handover_line)"
fixture hand-store-single single-pr
START_EXTRA=(--var STORE=session)
start auto && to_execute_run
START_EXTRA=()
eq "a single-pr PLAN ignores --store: none" none "$(handover_line)"

echo "== a session isolated in one repository's worktree =="
# iso_fixture <topic> <second repo> -- a coordinated PLAN with a node in
# acme/widgets (the fixture's repository) and one in <second repo>, run from a
# linked worktree of the fixture's checkout on the docs branch: the shape a
# session isolated in that repository's worktree runs in.
iso_fixture() {
    fixture "$1" coordinated
    cat >"$R/docs/plans/PLAN-$1.md" <<PLAN
---
schema: plan/v1
status: Active
execution_mode: coordinated
milestone: "$1"
issue_count: 2
---

# PLAN: $1

## Status

Active

## Implementation Issues

| Issue | Dependencies | Complexity |
|-------|--------------|------------|
| [#1: feat a](https://example.com/1) | None | testable |
| ^_Repo: acme/widgets \| Group: default_ | | |
| [#2: feat b](https://example.com/2) | None | testable |
| ^_Repo: $2 \| Group: default_ | | |
PLAN
    g add docs
    g commit -q -m "docs: $1 nodes"
    g push -q origin "HEAD:refs/heads/docs/$1"
    g checkout -q main
    git -C "$R" worktree add -q "$T/wt-$1" "docs/$1" 2>/dev/null
    R="$T/wt-$1"
}
iso_fixture iso-two acme/gadgets
start auto && to_execute_run
expect "a node outside the worktree's repository stops the run before /execute" done_error \
    outcome=error step=deliver:worktree-isolated reason=worktree-isolated \
    worktree_repo=acme/widgets other_repos=acme/gadgets
if k request get "$REQ" | jq -e '.legs.execute.bound_child == null' >/dev/null; then
    pass "iso-two: /execute never started, so no node was cut"
else
    fail "iso-two: /execute never started"
fi
REPORT=$(k status "deliver-$TOPIC" 2>/dev/null | bash "$HERE/deliver-report.sh")
case "$REPORT" in
    *"message=Stopped before any node was cut: this session is isolated in a worktree of acme/widgets, and the PLAN also has nodes in acme/gadgets."*)
        pass "iso-two: the report names both repositories and what to do" ;;
    *) fail "iso-two: the report's message" "$REPORT" ;;
esac
iso_fixture iso-one acme/widgets
start auto && to_execute_run
eq "a single-repo PLAN in that repository's worktree goes on to /execute" execute_run "$(state)"

echo "== ready-awaiting-merge carries the /execute leg's own pr =="
fixture ready single-pr
start auto && to_execute_run
child execute "{\"outcome\":\"ready-awaiting-merge\",\"pr\":\"$URL\",\"waiting\":\"$URL:human\",\"reason\":\"merge-not-requested\",\"repos\":\"acme/widgets\"}"
tick
expect "ready" done outcome=ready-awaiting-merge "pr=$URL" "waiting=$URL:human" reason=merge-not-requested
if [ -z "$(ctx merged_verdict)" ]; then pass "ready: merged_check did not run"; else fail "ready: merged_check did not run"; fi

echo "== the executed shortcut =="
fixture exec-merged executed
db_set '(.prs[] | select(.number == 42) | .state) = "MERGED"'
start auto
child scope "{\"outcome\":\"executed\",\"pr\":\"$FORGED\",\"pr_state\":\"open\"}"
tick
expect "executed merged" done outcome=merged "pr=$URL" pr_state=merged
eq "executed merged: the result's pr equals checked_pr" "$URL" "$(ctx checked_pr)"
if k request get "$REQ" | jq -e '.legs.execute.bound_child == null and .legs.execute.disposition == "open"' >/dev/null; then
    pass "executed merged: /execute never ran"
else
    fail "executed merged: /execute never ran"
fi

fixture exec-open executed
start auto
child scope "{\"outcome\":\"executed\",\"pr\":\"$FORGED\",\"pr_state\":\"merged\"}"
tick
expect "executed open" done outcome=ready-awaiting-merge "pr=$URL" pr_state=open

fixture exec-missing executed
db_set '.prs = []'
start auto
child scope "{\"outcome\":\"executed\",\"pr\":\"$FORGED\"}"
tick
expect "executed with no owned PR" done_error outcome=error step=deliver:child-outcome pr=

echo "== merged_check downgrades =="
fixture downgrade single-pr
start auto && to_execute_run
child execute "{\"outcome\":\"merged\",\"pr\":\"$OTHER_MERGED\"}"
tick
expect "a merged claim GitHub contradicts" done outcome=ready-awaiting-merge "pr=$URL"
eq "downgrade: the leg's pr naming another merged PR is ignored" "$URL" "$(ctx checked_pr)"

fixture lookup-fails single-pr
start auto && to_execute_run
db_set '.fail = {"pr list": 1}'
child execute "{\"outcome\":\"merged\",\"pr\":\"$OTHER_MERGED\"}"
tick
expect "a failed lookup" done outcome=ready-awaiting-merge pr=
eq "lookup fails: no checked_pr" "" "$(ctx checked_pr)"

echo "== explicit resolves with progress-shaped payloads =="
fixture forged-scope single-pr
start auto
k request resolve "$REQ" scope --with-data "{\"status\":\"success\",\"summary\":\"x\",\"payload\":{\"outcome\":\"scoped\",\"pr\":\"$FORGED\"}}" >/dev/null
tick
expect "a hand-resolved scope leg claiming scoped" done_error outcome=error step=deliver:child-absent pr=
if [ -z "$(ctx scoped_verdict)" ] && ! grep -q . "$GH_DB.calls"; then pass "forged scope: scoped_check never ran"; else fail "forged scope: scoped_check never ran" "$(cat "$GH_DB.calls")"; fi

for payload in "{\"outcome\":\"ready-awaiting-merge\",\"pr\":\"$FORGED\"}" '{"outcome":"merged"}'; do
    fixture "forged-exec-$(jq -r .outcome <<<"$payload")" single-pr
    start auto && to_execute_run
    k request resolve "$REQ" execute --with-data "{\"status\":\"success\",\"summary\":\"x\",\"payload\":$payload}" >/dev/null
    tick
    expect "a hand-resolved execute leg claiming $(jq -r .outcome <<<"$payload")" done_error outcome=error step=deliver:child-absent pr=
    if [ -z "$(ctx merged_verdict)" ]; then pass "forged execute: merged_check never ran"; else fail "forged execute: merged_check never ran"; fi
done

echo "== overrides =="
fixture overrides single-pr
start auto
for gate in scope_leg scope_intent; do
    k overrides record "deliver-$TOPIC" --gate "$gate" --rationale test >"$T/ov.out" 2>&1
    rc=$?
    if [ "$rc" -eq 2 ] && grep -q gate_not_overridable "$T/ov.out"; then pass "override refused on $gate"; else fail "override refused on $gate" "rc=$rc $(cat "$T/ov.out")"; fi
    k overrides record "deliver-$TOPIC" --gate "$gate" --rationale test \
        --with-data '{"found":true,"disposition":"resolved","source":"promoted","valid":true,"payload":{"outcome":"scoped"}}' >"$T/ov.out" 2>&1
    rc=$?
    if [ "$rc" -eq 2 ] && grep -q gate_not_overridable "$T/ov.out"; then pass "override --with-data refused on $gate"; else fail "override --with-data refused on $gate" "rc=$rc $(cat "$T/ov.out")"; fi
done
tick
eq "overrides: the run still waits at scope_run" scope_run "$(state)"
to_execute_run
for gate in exec_leg; do
    k overrides record "deliver-$TOPIC" --gate "$gate" --rationale test >"$T/ov.out" 2>&1
    rc=$?
    if [ "$rc" -eq 2 ] && grep -q gate_not_overridable "$T/ov.out"; then pass "override refused on $gate"; else fail "override refused on $gate" "rc=$rc $(cat "$T/ov.out")"; fi
    k overrides record "deliver-$TOPIC" --gate "$gate" --rationale test \
        --with-data '{"found":true,"disposition":"resolved","source":"promoted","valid":true,"payload":{"outcome":"merged"}}' >"$T/ov.out" 2>&1
    rc=$?
    if [ "$rc" -eq 2 ] && grep -q gate_not_overridable "$T/ov.out"; then pass "override --with-data refused on $gate"; else fail "override --with-data refused on $gate" "rc=$rc $(cat "$T/ov.out")"; fi
done

echo "== a child that never attaches =="
fixture absent single-pr
start auto
tick --with-data '{"child_returned":"yes"}'
expect "child_returned on an open, unbound scope leg" done_error outcome=error step=deliver:child-absent
eq "absent: the leg holds the fixed record" '{"outcome":"error","step":"deliver:child-absent"}' "$(k request get "$REQ" | jq -c '.legs.scope.result.payload')"

fixture absent-exec single-pr
start auto && to_execute_run
tick --with-data '{"child_returned":"yes"}'
expect "child_returned on an open, unbound execute leg" done_error outcome=error step=deliver:child-absent

fixture bound single-pr
start auto
k init "scope-$TOPIC" --template "$T/tpl/scope.md" --var TOPIC="$TOPIC" --var INTENT_FLAG=continue --koto-leg "$REQ:scope" >/dev/null 2>&1
tick --with-data '{"child_returned":"yes"}'
eq "child_returned on a bound leg: the run keeps waiting" scope_run "$(state)"

echo "== refusals on the leg =="
fixture refuse-var single-pr
start auto
k init "scope-$TOPIC" --template "$T/tpl/scope.md" --var TOPIC="$TOPIC" --var INTENT_FLAG=bogus --koto-leg "$REQ:scope" >/dev/null 2>&1
tick
expect "an invalid INTENT_FLAG refused at init" done_error outcome=error step=scope:refused reason=invalid-var:INTENT_FLAG
if k status "scope-$TOPIC" >/dev/null 2>&1; then fail "the refused child opened no session"; else pass "the refused child opened no session"; fi

fixture refuse-intent single-pr
k init "scope-$TOPIC" --template "$T/tpl/scope.md" --var TOPIC="$TOPIC" --var INTENT_FLAG=stop >/dev/null 2>&1
start auto
k init "scope-$TOPIC" --template "$T/tpl/scope.md" --var TOPIC="$TOPIC" --var INTENT_FLAG=continue --attach-live --koto-leg "$REQ:scope" >/dev/null 2>&1
tick
expect "a live intent=stop run" done_error outcome=error step=deliver:intent-mismatch reason=var-mismatch:INTENT_FLAG

fixture promoted-intent single-pr
start auto
child scope '{"outcome":"refused","reason":"intent-mismatch","step":"scope:refused"}'
tick
expect "a promoted intent-mismatch refusal" done_error outcome=error step=deliver:intent-mismatch reason=intent-mismatch

fixture promoted-refused single-pr
start auto
child scope '{"outcome":"refused","reason":"plan-active","step":"scope:refused"}'
tick
expect "any other promoted refusal" done_error outcome=error step=scope:refused reason=plan-active

fixture forged-tpl single-pr
start auto && to_execute_run
k init "execute-$TOPIC" --template "$T/forged/forged.md" --var PLAN_SLUG="$TOPIC" --koto-leg "$REQ:execute" >/dev/null 2>&1
tick
expect "a throwaway template declaring merged is refused at attach: the execute leg is lost" done_error outcome=error \
    step=deliver:child-absent reason=execute-leg-lost:template-mismatch execute_state=absent
if k status "execute-$TOPIC" >/dev/null 2>&1; then fail "forged-tpl: the refused child opened no session"; else pass "forged-tpl: the refused child opened no session"; fi
REPORT=$(k status "deliver-$TOPIC" 2>/dev/null | bash "$HERE/deliver-report.sh")
eq "forged-tpl: the report names the lost leg and the execute state" "outcome=error
step=deliver:child-absent
reason=execute-leg-lost:template-mismatch
execute_state=absent" "$REPORT"

echo "== /scope's other outcomes =="
for which in re-evaluation abandonment cancelled; do
    fixture "early-$which" single-pr
    start auto
    child scope "{\"outcome\":\"$which\"}"
    tick
    expect "/scope ended at $which" done_stopped outcome=scope-ended-early "reason=$which"
done

fixture scope-error single-pr
start auto
child scope '{"outcome":"error","step":"scope:push"}'
tick
expect "/scope's error keeps its step" done_error outcome=error step=scope:push

fixture scope-odd single-pr
start auto
child scope '{"outcome":"shipped"}'
tick
expect "an outcome /deliver doesn't recognise" done_error outcome=error step=deliver:child-outcome

fixture multi multi-pr
start auto
child scope "{\"outcome\":\"handed-off-multi-pr\",\"intent\":\"continue\",\"pr\":\"$URL\",\"startable\":\"#101 First\\n#102 Second\",\"next\":\"/work-on #101\"}"
tick
expect "a multi-pr PLAN" done_stopped outcome=handed-off-multi-pr "pr=$URL" "next=/work-on #101"
eq "multi-pr: the startable list is relayed" "#101 First
#102 Second" "$(result startable)"
if k request get "$REQ" | jq -e '.legs.execute.bound_child == null' >/dev/null; then pass "multi-pr: /execute never started"; else fail "multi-pr: /execute never started"; fi

echo "== the interactive confirmation =="
fixture confirm-stop single-pr
start interactive && to_execute_run
eq "interactive: stops at confirm" confirm "$(state)"
tick --with-data '{"decision":"stop"}'
expect "a declined confirmation" done_stopped outcome=scoped "next=/deliver confirm-stop" "pr=$URL"

fixture confirm-go single-pr
start interactive && to_execute_run
tick --with-data '{"decision":"proceed"}'
eq "a confirmed run goes on to execute_run" execute_run "$(state)"

fixture auto-stray single-pr
start auto && to_execute_run
eq "--auto asks nothing" execute_run "$(state)"

echo "== /execute's other outcomes =="
for which in paused-for-review paused-awaiting-merges; do
    fixture "pause-$which" single-pr
    start auto && to_execute_run
    child execute "{\"outcome\":\"$which\",\"pr\":\"$URL\",\"waiting\":\"$URL:human\",\"resume\":\"/execute docs/plans/PLAN-$TOPIC.md --merge\"}"
    tick
    expect "/execute paused ($which)" done_stopped "outcome=$which" "pr=$URL" "resume=/execute docs/plans/PLAN-$TOPIC.md --merge"
done

fixture exec-error single-pr
start auto && to_execute_run
child execute '{"outcome":"error","step":"execute:ci"}'
tick
expect "/execute's error keeps its step" done_error outcome=error step=execute:ci

fixture exec-odd single-pr
start auto && to_execute_run
child execute '{"outcome":"refused"}'
tick
expect "a promoted outcome outside /execute's set" done_error outcome=error step=deliver:child-outcome

echo "== the request and the repository =="
fixture abandoned single-pr
start auto
k request abandon-request "$REQ" --rationale test >/dev/null
tick
expect "an abandoned request" done_error outcome=error step=deliver:request-abandoned

# A private repository runs the whole chain. The scope step publishes for real
# through publish-scoping-pr.sh.
publish() { # publish -- /scope's publish step, run as /scope runs it
    (cd "$R" && bash "$REPO_ROOT/skills/scope/scripts/publish-scoping-pr.sh" \
        --topic "$TOPIC" --exit full-run --intent continue) >"$T/publish.out" 2>"$T/publish.err"
}
fixture private private
start auto
publish
eq "private: the publish step pushes (exit 0)" 0 "$?"
eq "private: origin holds the pushed head" "$(g rev-parse HEAD)" "$(g ls-remote origin "refs/heads/docs/$TOPIC" | cut -f1)"
to_execute_run
eq "private: at execute_run" execute_run "$(state)"
db_set '(.prs[] | select(.number == 42) | .state) = "MERGED"'
child execute "{\"outcome\":\"merged\",\"pr\":\"$URL\",\"repos\":\"acme/widgets\"}"
tick
expect "a private repository reaches its PR" done outcome=merged "pr=$URL"

echo "== the stale-run fence =="
fixture fence single-pr
start auto
OLD_REQ="$REQ"
k init "scope-$TOPIC" --template "$T/tpl/scope.md" --var TOPIC="$TOPIC" --var INTENT_FLAG=continue --koto-leg "$OLD_REQ:scope" >/dev/null 2>&1
# A new /deliver run on the same topic: a fresh session and a fresh request.
k session cleanup "deliver-$TOPIC" >/dev/null 2>&1
start auto
if [ "$REQ" != "$OLD_REQ" ]; then pass "fence: a new request"; else fail "fence: a new request"; fi
eq "fence: the old request is closed" '"closed"' "$(k request get "$OLD_REQ" | jq -c '.request_state')"
# The old run's child finishes late: its result is not the new run's.
k next "scope-$TOPIC" --no-cleanup --with-data "{\"finish\":\"go\",\"outcome\":\"scoped\",\"pr\":\"$FORGED\"}" >/dev/null 2>&1
tick
eq "fence: the new run is still waiting on its own leg" scope_run "$(state)"
eq "fence: the new request's scope leg is still open" '"open"' "$(k request get "$REQ" | jq -c '.legs.scope.disposition')"
eq "fence: the old leg took no result" 'null' "$(k request get "$OLD_REQ" | jq -c '.legs.scope.result')"

echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
