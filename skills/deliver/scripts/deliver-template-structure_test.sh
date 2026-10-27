#!/usr/bin/env bash
# deliver-template-structure_test.sh -- deliver.md's guarantees, read from the
# template source and from the graph koto compiles.
#
# Engine-free, over the source:
#   - every context_assignments block assigns only literals, {{VAR}} values,
#     and ${gates.scope_leg.payload.*} / ${gates.exec_leg.payload.*} paths:
#     no ${context. (koto rejects it at compile time) and no
#     ${gates.<g>.<path>} over any other gate (a command gate carries only an
#     exit code). The grep reads every block, and is shown to bite on a
#     mutated copy of each kind.
#   - the refused outcome token never appears after `outcome=` under
#     skills/deliver/
#
# Over the compiled JSON:
#   - a state for each step of the run (request, scope, re-check, isolation
#     check, mode route, confirm, execute, merged re-check, report
#     terminals), and no others
#   - scoped_check's pass reaches isolation_check, the only way into
#     mode_route; isolation_check runs worktree-isolation.sh with this
#     session, routes on two non-overridable context-matches gates over
#     isolation_verdict, and ends an isolated verdict at done_error as
#     deliver:worktree-isolated
#   - TOPIC, PLUGIN_ROOT, COORDINATION, UPSTREAM and MAX_ROUNDS carry
#     scope.md's constraints exactly; MODE is auto|interactive, MERGE
#     true|false; REVIEW_FLOOR and REVIEW_CEILING are optional, default
#     empty, the level pattern ^(light|standard|full)?$, rebind like
#     MAX_ROUNDS
#   - scope_leg, scope_intent and exec_leg are request-leg gates on this run's
#     REQ, declared overridable: false, with /scope's and /execute's outcome
#     sets as `expect`; every context-matches gate in scoped_check,
#     executed_check and merged_check is overridable: false; so are the
#     mode_route and confirm gates
#   - the default actions are exactly open_request, scope_absent,
#     execute_absent, the three re-checks, isolation_check, mode_route's
#     handover read and execute_lost, and none pushes, merges, or opens a PR; no command koto
#     runs (a default action or a gate) reads ${context. or ${gates., which
#     koto never substitutes
#   - mode_route captures EXEC_HANDOVER from deliver-execute-leg.sh handover
#     with STORE, and execute_run's directive appends it unless it reads none;
#     STORE is optional, github|session, rebind
#   - every scope_run arm that copies the leg's pr copies its intent as
#     scope_intent; the explicit arm clears it
#   - execute_run's refused and missing arms, and only those, reach
#     execute_lost with step deliver:child-absent and reason
#     execute-leg-lost:<koto's code> or execute-leg-lost:request_not_found;
#     execute_lost runs deliver-execute-leg.sh lost and goes only to
#     done_error
#   - each of those bites on a mutated copy where the file uses it: a
#     refused leg or a missing request routed as before, an arm copying pr
#     without intent, a result map without execute_state, a command reading
#     ${context.
#   - on both leg gates: every arm that leaves toward progress requires a
#     promoted, valid result; the explicit arm reaches only done_error with
#     deliver:child-absent and assigns no leg value; the child_returned arm
#     requires an open, unbound leg and reaches only the absent state, which
#     goes only back to its run state
#   - outcome=merged is assigned only by merged_check and executed_check, on
#     an arm requiring both the verdict and a non-empty checked_pr; every
#     other merged_check arm ends ready-awaiting-merge
#   - the three terminals declare the same thirteen-key result map (the ten
#     report keys, execute_state, worktree_repo and other_repos), each read
#     as ${context.<key>};
#     done_error is a failure
#   - the child directives name --intent=continue and the legs; execute_run's
#     appends --review-floor={{REVIEW_FLOOR}} and
#     --review-ceiling={{REVIEW_CEILING}}, each only when not empty
#
# Usage: bash skills/deliver/scripts/deliver-template-structure_test.sh
# Exit codes: 0 all pass (the compiled checks SKIP loudly without koto);
#             1 a failure.
set -uo pipefail
. "$(dirname "$0")/../../../scripts/lib/koto-test-guard.sh" || exit 1

HERE=$(cd "$(dirname "$0")" && pwd)
SKILL_DIR=$(cd "$HERE/.." && pwd)
REPO_ROOT=$(cd "$SKILL_DIR/../.." && pwd)
TEMPLATE="$SKILL_DIR/koto-templates/deliver.md"
SCOPE="$REPO_ROOT/skills/scope/koto-templates/scope.md"

PASS=0
FAIL=0
pass() { PASS=$((PASS + 1)); echo "PASS: $*"; }
fail() { FAIL=$((FAIL + 1)); echo "FAIL: $*"; }

command -v jq >/dev/null 2>&1 || { echo "FAIL: jq is required" >&2; exit 1; }
[ -f "$TEMPLATE" ] || { echo "FAIL: $TEMPLATE not found" >&2; exit 1; }

WORK=$(mktemp -d "${TMPDIR:-/tmp}/deliver-structure-test.XXXXXX")
trap 'rm -rf "$WORK"' EXIT

# --- engine-free -------------------------------------------------------------------

# assignment_findings <file> -- every value line inside a context_assignments
# block that reads ${context. or a ${gates. path other than a leg payload.
assignment_findings() {
    awk '
        /^[[:space:]]*context_assignments:[[:space:]]*$/ {
            match($0, /^[[:space:]]*/); indent = RLENGTH; inblock = 1; next
        }
        inblock {
            if ($0 ~ /^[[:space:]]*$/) next
            match($0, /^[[:space:]]*/)
            if (RLENGTH <= indent) { inblock = 0 }
            else {
                line = $0
                if (line ~ /\$\{context\./) print NR ": " line
                rest = line
                while (match(rest, /\$\{gates\.[^}]*\}/)) {
                    ref = substr(rest, RSTART, RLENGTH)
                    if (ref !~ /^\$\{gates\.(scope_leg|exec_leg)\.payload\.[A-Za-z0-9_.-]+\}$/) print NR ": " line
                    rest = substr(rest, RSTART + RLENGTH)
                }
                next
            }
        }
    ' "$1"
}
BLOCKS=$(grep -c '^[[:space:]]*context_assignments:' "$TEMPLATE")
FOUND=$(assignment_findings "$TEMPLATE")
if [ "$BLOCKS" -gt 20 ] && [ -z "$FOUND" ]; then
    pass "every context_assignments block ($BLOCKS) assigns only literals, {{VAR}}s and leg payload paths"
else
    fail "context_assignments reading context or a non-leg gate: $FOUND"
fi
MUT="$WORK/mut.md"
perl -0pe 's/          outcome: handed-off-multi-pr/          outcome: "\${context.outcome}"/' "$TEMPLATE" >"$MUT"
if [ -n "$(assignment_findings "$MUT")" ]; then pass "the assignment grep bites on a \${context. assignment"; else fail "the assignment grep missed a \${context. assignment"; fi
perl -0pe 's/          outcome: handed-off-multi-pr/          outcome: "\${gates.plan_mode.exit_code}"/' "$TEMPLATE" >"$MUT"
if [ -n "$(assignment_findings "$MUT")" ]; then pass "the assignment grep bites on a command-gate path"; else fail "the assignment grep missed a command-gate path"; fi
perl -0pe 's/(scope_outcome: "\$\{gates\.scope_leg\.)payload\.outcome/${1}outcome/' "$TEMPLATE" >"$MUT"
if [ -n "$(assignment_findings "$MUT")" ]; then pass "the assignment grep bites on a leg path outside payload"; else fail "the assignment grep missed a leg path outside payload"; fi

BANNED="outcome=""refused"
if grep -rn -- "$BANNED" "$SKILL_DIR" >/dev/null 2>&1; then
    fail "the refused outcome token appears under skills/deliver/: $(grep -rn -- "$BANNED" "$SKILL_DIR")"
else
    pass "the refused outcome token appears nowhere under skills/deliver/"
fi

if ! command -v koto >/dev/null 2>&1; then
    echo "SKIP: koto not on PATH -- the template was not compiled, so its graph was not checked"
    echo "Results: $PASS passed, $FAIL failed"
    [ "$FAIL" -eq 0 ] || exit 1
    exit 0
fi

export HOME="$WORK/home"
mkdir -p "$HOME"
compile() { koto template compile "$@" 2>/dev/null | tail -1; }
JSON=$(compile "$TEMPLATE")
if [ -z "$JSON" ] || [ ! -f "$JSON" ]; then
    fail "deliver.md does not compile"
    koto template compile "$TEMPLATE" 2>&1 | tail -3
    echo "Results: $PASS passed, $FAIL failed"
    exit 1
fi
pass "deliver.md compiles"
SCOPE_JSON=$(compile "$SCOPE")

holds() { jq -e "$2" "$1" >/dev/null 2>&1; }

for v in TOPIC PLUGIN_ROOT COORDINATION UPSTREAM MAX_ROUNDS; do
    ours=$(jq -c --arg v "$v" '.variables[$v] | {pattern, values, default, required, rebind}' "$JSON")
    theirs=$(jq -c --arg v "$v" '.variables[$v] | {pattern, values, default, required, rebind}' "$SCOPE_JSON")
    if [ -n "$theirs" ] && [ "$ours" = "$theirs" ]; then pass "$v carries scope.md's constraints"; else fail "$v: ours $ours, scope.md's $theirs"; fi
done

CHECKS=(
"the states are exactly the run's|.states | keys == [\"confirm\",\"done\",\"done_error\",\"done_stopped\",\"execute_absent\",\"execute_lost\",\"execute_run\",\"executed_check\",\"isolation_check\",\"merged_check\",\"mode_route\",\"open_request\",\"scope_absent\",\"scope_run\",\"scoped_check\"]"
"open_request is the initial state|.initial_state == \"open_request\""
"MODE is auto or interactive, default interactive|.variables.MODE | (.values == [\"auto\",\"interactive\"] and .default == \"interactive\")"
"MERGE is true or false, default false|.variables.MERGE | (.values == [\"true\",\"false\"] and .default == \"false\")"
"scope_leg is a non-overridable request-leg gate on REQ's scope leg|.states.scope_run.gates.scope_leg | (.type == \"request-leg\" and .overridable == false and .request == \"{{REQ}}\" and .leg == \"scope\")"
"scope_leg expects /scope's outcome set, refused included|.states.scope_run.gates.scope_leg.expect.outcome == [\"scoped\",\"handed-off-multi-pr\",\"executed\",\"re-evaluation\",\"abandonment\",\"cancelled\",\"refused\",\"error\"]"
"scope_intent reads the same leg, non-overridable|.states.scope_run.gates.scope_intent | (.type == \"request-leg\" and .overridable == false and .request == \"{{REQ}}\" and .leg == \"scope\" and .expect.reason == [\"intent-mismatch\",\"var-mismatch:INTENT_FLAG\"])"
"exec_leg is a non-overridable request-leg gate on REQ's execute leg|.states.execute_run.gates.exec_leg | (.type == \"request-leg\" and .overridable == false and .request == \"{{REQ}}\" and .leg == \"execute\" and .expect.outcome == [\"merged\",\"ready-awaiting-merge\",\"paused-for-review\",\"paused-awaiting-merges\",\"error\"])"
"every re-check gate is a non-overridable context-matches gate|[.states.scoped_check, .states.executed_check, .states.merged_check | .gates[] | (.type == \"context-matches\" and .overridable == false)] | length == 7 and all"
"the mode_route and confirm gates refuse overrides|[.states.mode_route, .states.confirm | .gates[] | .overridable == false] | length == 2 and all"
"the default actions are exactly the request-store, re-check, isolation, handover and lost-leg states|[.states | to_entries[] | select(.value.default_action != null) | .key] | sort == [\"execute_absent\",\"execute_lost\",\"executed_check\",\"isolation_check\",\"merged_check\",\"mode_route\",\"open_request\",\"scope_absent\",\"scoped_check\"]"
"no default action pushes, merges, or writes a PR|[.states[] | (.default_action.command // \"\") | test(\"git push|gh pr (merge|create|edit|ready|close)|gh api .*-X\")] | any | not"
"the re-checks run deliver-probe.sh in their own mode|(.states.scoped_check.default_action.command | test(\"deliver-probe\\\\.sh\\\" scoped \")) and (.states.executed_check.default_action.command | test(\"deliver-probe\\\\.sh\\\" executed \")) and (.states.merged_check.default_action.command | test(\"deliver-probe\\\\.sh\\\" merged \"))"
"open_request captures REQ from deliver-open-request.sh|.states.open_request.default_action | (.capture_stdout_as == \"REQ\" and (.command | test(\"deliver-open-request\\\\.sh\")))"
"the absent states run deliver-absent.sh on their own leg|(.states.scope_absent.default_action.command | test(\"deliver-absent\\\\.sh.* --leg scope\$\")) and (.states.execute_absent.default_action.command | test(\"deliver-absent\\\\.sh.* --leg execute\$\"))"
"each absent state goes only back to its run state|(.states.scope_absent.transitions | map(.target) == [\"scope_run\"]) and (.states.execute_absent.transitions | map(.target) == [\"execute_run\"])"
"every leg arm toward progress requires a promoted, valid result|[(.states.scope_run.transitions[] | select(.target == \"scoped_check\" or .target == \"executed_check\") | .when | (.[\"gates.scope_leg.source\"] == \"promoted\" and .[\"gates.scope_leg.valid\"] == true)), (.states.execute_run.transitions[] | select(.target == \"merged_check\" or .target == \"done\" or .target == \"done_stopped\") | .when | (.[\"gates.exec_leg.source\"] == \"promoted\" and .[\"gates.exec_leg.valid\"] == true))] | length == 7 and all"
"every scope_run arm into done_stopped requires a promoted, valid result|[.states.scope_run.transitions[] | select(.target == \"done_stopped\") | .when | (.[\"gates.scope_leg.source\"] == \"promoted\" and .[\"gates.scope_leg.valid\"] == true)] | length == 3 and all"
"the explicit arms reach only done_error with deliver:child-absent and copy no leg value|[.states.scope_run.transitions[], .states.execute_run.transitions[] | select((.when[\"gates.scope_leg.source\"] // .when[\"gates.exec_leg.source\"]) == \"explicit\") | (.target == \"done_error\" and .context_assignments.step == \"deliver:child-absent\" and .context_assignments.pr == \"\" and ([.context_assignments[] | contains(\"\${gates.\")] | any | not))] | length == 2 and all"
"the child_returned arms need an open, unbound leg and reach only the absent state|[.states.scope_run.transitions[], .states.execute_run.transitions[] | select(.when.child_returned != null) | ((.target == \"scope_absent\" and .when[\"gates.scope_leg.disposition\"] == \"open\" and .when[\"gates.scope_leg.bound\"] == false) or (.target == \"execute_absent\" and .when[\"gates.exec_leg.disposition\"] == \"open\" and .when[\"gates.exec_leg.bound\"] == false))] | length == 2 and all"
"every scope_run arm but the explicit one, and every execute_run arm but the explicit and missing ones, copies the leg's payload|[(.states.scope_run.transitions[] | select(.when[\"gates.scope_leg.source\"] != \"explicit\") | .context_assignments | [\"scope_outcome\",\"plan_path\",\"plan_execution_mode\",\"pr\",\"pr_state\",\"startable\",\"next\",\"scope_intent\"] as \$ks | [\$ks[] as \$k | .[\$k] == (\"\${gates.scope_leg.payload.\" + (if \$k == \"scope_outcome\" then \"outcome\" elif \$k == \"scope_intent\" then \"intent\" else \$k end) + \"}\")] | all), (.states.execute_run.transitions[] | select(.when[\"gates.exec_leg.source\"] != \"explicit\" and .when[\"gates.exec_leg.disposition\"] != \"missing\") | .context_assignments | [\"pr\",\"repos\",\"resume\",\"waiting\"] as \$ks | [\$ks[] as \$k | .[\$k] == (\"\${gates.exec_leg.payload.\" + \$k + \"}\")] | all)] | length == 24 and all"
"every scope_run arm that copies the leg's pr also copies its intent as scope_intent|[.states.scope_run.transitions[] | .context_assignments | select(.pr == \"\${gates.scope_leg.payload.pr}\") | .scope_intent == \"\${gates.scope_leg.payload.intent}\"] | length == 15 and all"
"scope_run's explicit arm clears scope_intent|[.states.scope_run.transitions[] | select(.when[\"gates.scope_leg.source\"] == \"explicit\") | .context_assignments.scope_intent] == [\"\"]"
"execute_run's refused and missing arms reach execute_lost with deliver:child-absent and an execute-leg-lost reason|[.states.execute_run.transitions[] | select(.when[\"gates.exec_leg.source\"] == \"refused\" or .when[\"gates.exec_leg.disposition\"] == \"missing\") | (.target == \"execute_lost\" and .context_assignments.outcome == \"error\" and .context_assignments.step == \"deliver:child-absent\" and (.context_assignments.reason | startswith(\"execute-leg-lost:\")))] | length == 2 and all"
"the refused arm names koto's code and the missing arm request_not_found|([.states.execute_run.transitions[] | select(.when[\"gates.exec_leg.source\"] == \"refused\") | .context_assignments.reason] == [\"execute-leg-lost:\${gates.exec_leg.payload.reason}\"]) and ([.states.execute_run.transitions[] | select(.when[\"gates.exec_leg.disposition\"] == \"missing\") | .context_assignments | [.reason, .pr]] == [[\"execute-leg-lost:request_not_found\", \"\"]])"
"only execute_run's refused and missing arms enter execute_lost|[.states | to_entries[] | .key as \$s | (.value.transitions // [])[] | select(.target == \"execute_lost\") | \$s] == [\"execute_run\",\"execute_run\"]"
"execute_lost runs deliver-execute-leg.sh lost and goes only to done_error|(.states.execute_lost.default_action.command | test(\"deliver-execute-leg\\\\.sh\\\" lost \")) and (.states.execute_lost.transitions | map(.target) == [\"done_error\"])"
"mode_route captures EXEC_HANDOVER from deliver-execute-leg.sh handover, passing STORE|.states.mode_route.default_action | (.capture_stdout_as == \"EXEC_HANDOVER\" and (.command | contains(\"deliver-execute-leg.sh\\\" handover \") and contains(\"--store \\\"{{STORE}}\\\"\")))"
"execute_run's directive appends the handover arguments, and nothing when they read none|.states.execute_run.directive | (contains(\"{{EXEC_HANDOVER}}\") and contains(\"When that value reads\\n\`none\`, append nothing\"))"
"STORE is optional, default empty, github or session, rebind|.variables.STORE | ((.required // false) == false and (.default // \"\") == \"\" and .pattern == \"^(github|session)?\$\" and .rebind == true)"
"no command koto runs reads \${context. or \${gates.|[.states[] | ((.default_action.command // \"\"), ((.gates // {})[] | (.command // \"\"))) | test(\"\\\\$\\\\{(context|gates)\\\\.\")] | any | not"
"a disposition of abandoned ends deliver:request-abandoned on both legs|[.states.scope_run.transitions[], .states.execute_run.transitions[] | select((.when[\"gates.scope_leg.disposition\"] // .when[\"gates.exec_leg.disposition\"]) == \"abandoned\") | (.target == \"done_error\" and .context_assignments.step == \"deliver:request-abandoned\")] | length == 2 and all"
"outcome merged is assigned only by merged_check and executed_check|[.states | to_entries[] | .key as \$s | (.value.transitions // [])[] | select(.context_assignments.outcome == \"merged\") | \$s] | sort == [\"executed_check\",\"merged_check\"]"
"merged_check's merged arm requires the verdict and a non-empty checked_pr|[.states.merged_check.transitions[] | select(.context_assignments.outcome == \"merged\") | .when == {\"gates.merged_confirmed.matches\": true, \"gates.merged_pr.matches\": true}] == [true]"
"every other merged_check arm ends ready-awaiting-merge in done|[.states.merged_check.transitions[] | select(.context_assignments.outcome != \"merged\") | (.target == \"done\" and .context_assignments.outcome == \"ready-awaiting-merge\")] | length == 2 and all"
"the merged_check verdict gate matches only merged|.states.merged_check.gates.merged_confirmed | (.key == \"merged_verdict\" and .pattern == \"^merged\$\")"
"scoped_check routes to isolation_check only on pass and a non-empty checked_pr|[.states.scoped_check.transitions[] | select(.target == \"isolation_check\") | .when] == [{\"gates.scoped_pass.matches\": true, \"gates.scoped_pr.matches\": true}]"
"only isolation_check enters mode_route|[.states | to_entries[] | .key as \$s | (.value.transitions // [])[] | select(.target == \"mode_route\") | \$s] == [\"isolation_check\"]"
"isolation_check runs worktree-isolation.sh on the PLAN, recording into this session|.states.isolation_check.default_action.command == \"\\\"{{PLUGIN_ROOT}}/skills/execute/scripts/worktree-isolation.sh\\\" --plan \\\"docs/plans/PLAN-{{TOPIC}}.md\\\" --session \\\"deliver-{{TOPIC}}\\\"\""
"isolation_check's gates are non-overridable context-matches gates on isolation_verdict|[.states.isolation_check.gates[] | (.type == \"context-matches\" and .overridable == false and .key == \"isolation_verdict\")] | length == 2 and all"
"isolation_check: pass to mode_route, isolated to done_error as deliver:worktree-isolated|[.states.isolation_check.transitions[] | [.target, (.context_assignments.step // \"\"), (.context_assignments.reason // \"\")]] == [[\"mode_route\",\"\",\"\"],[\"done_error\",\"deliver:worktree-isolated\",\"worktree-isolated\"]] and .states.isolation_check.gates.isolation_pass.pattern == \"^pass\$\" and .states.isolation_check.gates.isolation_isolated.pattern == \"^isolated\$\""
"mode_route: 0 and 10 to confirm, 20 to done_stopped as handed-off-multi-pr, 4 to an error|[.states.mode_route.transitions[] | [.when[\"gates.plan_mode.exit_code\"], .target, (.context_assignments.outcome // \"\")]] == [[0,\"confirm\",\"\"],[10,\"confirm\",\"\"],[20,\"done_stopped\",\"handed-off-multi-pr\"],[4,\"done_error\",\"error\"]]"
"confirm: auto goes on without evidence; stop ends scoped with next=/deliver <topic>|(.states.confirm.transitions[0] | .target == \"execute_run\" and .when == {\"gates.mode_auto.exit_code\": 0}) and ([.states.confirm.transitions[] | select(.target == \"done_stopped\") | .context_assignments] == [{\"outcome\":\"scoped\",\"next\":\"/deliver {{TOPIC}}\"}])"
"the three terminals declare the thirteen-key result map read from context|[.states[] | select(.terminal == true) | .result | (keys == ([\"outcome\",\"step\",\"reason\",\"pr\",\"pr_state\",\"repos\",\"resume\",\"waiting\",\"next\",\"startable\",\"execute_state\",\"worktree_repo\",\"other_repos\"] | sort) and (to_entries | all(.value == (\"\${context.\" + .key + \"}\"))))] | length == 3 and all"
"the three terminals' result maps are equal|[.states[] | select(.terminal == true) | .result] | (length == 3 and (unique | length) == 1)"
"done_error is a failure; done and done_stopped are not|.states.done_error.failure == true and ((.states.done.failure // false) == false) and ((.states.done_stopped.failure // false) == false)"
"scope_run's directive runs /scope --intent=continue on the scope leg|.states.scope_run.directive | (contains(\"--intent=continue\") and contains(\"--koto-leg={{REQ}}:scope\"))"
"execute_run's directive runs /execute on the PLAN and the execute leg|.states.execute_run.directive | (contains(\"docs/plans/PLAN-{{TOPIC}}.md\") and contains(\"--koto-leg={{REQ}}:execute\") and contains(\"{{MERGE}}\"))"
"execute_run's directive appends the review-level bound only when not empty|.states.execute_run.directive | (contains(\"\`--review-floor={{REVIEW_FLOOR}}\`, only when that value after \`=\` is not\") and contains(\"\`--review-ceiling={{REVIEW_CEILING}}\`, only when that value after \`=\` is not\"))"
"REVIEW_FLOOR and REVIEW_CEILING are optional, default empty, the level pattern, rebind|[.variables.REVIEW_FLOOR, .variables.REVIEW_CEILING] | all((.required // false) == false and (.default // \"\") == \"\" and .pattern == \"^(light|standard|full)?\$\" and .rebind == true)"
)

run_checks() { # run_checks <json> -> the labels that fail
    local entry
    for entry in "${CHECKS[@]}"; do
        holds "$1" "${entry#*|}" || printf '%s\n' "${entry%%|*}"
    done
}
FAILED=$(run_checks "$JSON")
for entry in "${CHECKS[@]}"; do
    label="${entry%%|*}"
    if grep -qxF "$label" <<<"$FAILED"; then fail "$label"; else pass "$label"; fi
done

# --- each compiled check bites ----------------------------------------------------------

mutate() { # mutate <label> <check label> <perl substitution>
    local json failed
    perl -0pe "$3" "$TEMPLATE" >"$MUT"
    if cmp -s "$TEMPLATE" "$MUT"; then fail "mutation [$1] did not change the template"; return; fi
    json=$(compile --allow-legacy-gates "$MUT")
    if [ -z "$json" ] || [ ! -f "$json" ]; then
        fail "mutation [$1] does not compile, so it proves nothing"
        koto template compile --allow-legacy-gates "$MUT" 2>&1 | tail -2
        return
    fi
    failed=$(run_checks "$json")
    if grep -qxF "$2" <<<"$failed"; then pass "the check fails on a copy with $1"; else fail "a copy with $1 passed [$2]"; fi
}
mutate "an overridable scope_leg" \
    "scope_leg is a non-overridable request-leg gate on REQ's scope leg" \
    's/(        leg: scope\n        expect:\n          outcome: \[scoped[^\n]*\n        overridable: )false/${1}true/'
mutate "an overridable merged_check gate" \
    "every re-check gate is a non-overridable context-matches gate" \
    's/(key: merged_verdict\n        pattern: .\^merged\$.\n        overridable: )false/${1}true/'
mutate "an explicit arm that copies the forged pr" \
    "the explicit arms reach only done_error with deliver:child-absent and copy no leg value" \
    's/(step: "deliver:child-absent"\n[^\n]*\n          pr: )""/${1}"\${gates.exec_leg.payload.pr}"/'
mutate "a merged arm on the leg's word alone" \
    "outcome merged is assigned only by merged_check and executed_check" \
    's/(          gates\.exec_leg\.payload\.outcome: merged\n        context_assignments:\n)/${1}          outcome: merged\n/'
mutate "a merged_check arm upgrading without checked_pr" \
    "merged_check's merged arm requires the verdict and a non-empty checked_pr" \
    's/(          gates\.merged_confirmed\.matches: true\n          gates\.merged_pr\.matches: false\n        context_assignments:\n          outcome: )ready-awaiting-merge/${1}merged/'
mutate "a refused execute leg ending execute:refused again" \
    "execute_run's refused and missing arms reach execute_lost with deliver:child-absent and an execute-leg-lost reason" \
    's/(      - target: )execute_lost(\n        when:\n          gates\.exec_leg\.disposition: resolved\n          gates\.exec_leg\.source: refused\n)/${1}done_error$2/'
mutate "a missing request ending deliver:request-abandoned again" \
    "execute_run's refused and missing arms reach execute_lost with deliver:child-absent and an execute-leg-lost reason" \
    's/(          gates\.exec_leg\.disposition: missing\n        context_assignments:\n          outcome: error\n          step: )"deliver:child-absent"/${1}"deliver:request-abandoned"/'
mutate "a scope_run arm that copies pr but not intent" \
    "every scope_run arm that copies the leg's pr also copies its intent as scope_intent" \
    's/(          gates\.scope_leg\.payload\.outcome: scoped\n(?:[^\n]*\n)*?          pr: "\$\{gates\.scope_leg\.payload\.pr\}"\n)          scope_intent: [^\n]*\n/$1/'
mutate "a terminal whose result map lacks execute_state" \
    "the three terminals' result maps are equal" \
    's/(      startable: "\$\{context\.startable\}"\n)      execute_state: "\$\{context\.execute_state\}"\n/$1/'
mutate "a default action reading \${context." \
    "no command koto runs reads \${context. or \${gates." \
    's/(deliver-execute-leg\.sh" lost --topic "\{\{TOPIC\}\}")/${1} --x "\${context.pr}"/'
mutate "a default action that pushes" \
    "no default action pushes, merges, or writes a PR" \
    's/(scripts\/deliver-open-request\.sh" --topic "\{\{TOPIC\}\}")/${1} \&\& git push/'

echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
