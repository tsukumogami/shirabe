#!/usr/bin/env bash
# execute-template-structure_test.sh — the merge step's shape, read from the
# compiled template
# Part of the execute skill
#
# The guarantees of /execute's merge step are properties of execute.md's graph,
# so this reads the graph itself: `koto template compile` turns the template into
# JSON, and each assertion is a jq query over it. No field is parsed out of YAML
# by hand, so a comment or a reflowed line can't fool it.
#
# It asserts, on the shipped template:
#
#   merge_attempt has no default_action and carries the merge_intent gate,
#     `test "{{MERGE}}" = true`, overridable: false, whose failure edge
#     (exit_code 1) targets ready_awaiting_merge and whose other edges all
#     require it to pass
#   every merge_route and merge_confirm gate is a context-matches gate declared
#     overridable: false, and merge_confirm has no command gate
#   no transition targets the legacy `done`
#   merged's only incoming edge is from merge_confirm
#   no context_assignments block writes home_pr
#   escalate_dirty_merge_state still routes to done_blocked, and ci_monitor's
#     passing and failing_fixed edges target merge_readiness
#   no default_action command holds `${context.` (koto never substitutes it)
#   every edge into a terminal assigns `outcome` as a literal, no assignment
#     reads `${context.`, and a `step` or `reason` assignment is a literal
#   every terminal declares the result map, with step and reason read from
#     context
#   MERGE and PAUSE_BEFORE_FINALIZE are values [true, false], default false,
#     rebind: true; PLUGIN_ROOT carries the absolute-path pattern; PLAN_DOC and
#     PLAN_SLUG are not rebindable
#
# and, so the checks are known to bite, that each fails on a mutated copy: an
# assignment writing home_pr, an overridable merge_intent gate, an edge into
# `done`, a second edge into `merged`, and a `${context.` in a default action.
#
# Usage: execute-template-structure_test.sh
# Exit codes: 0 all pass (or koto absent: a loud SKIP), 1 a failure

set -uo pipefail

SCRIPT_DIR=$(CDPATH='' cd "$(dirname "$0")" && pwd)
SKILL_DIR=$(CDPATH='' cd "$SCRIPT_DIR/.." && pwd)
TEMPLATE="$SKILL_DIR/koto-templates/execute.md"

PASS_COUNT=0
FAIL_COUNT=0
pass() { echo "PASS: $*"; PASS_COUNT=$((PASS_COUNT + 1)); }
fail() { echo "FAIL: $*"; FAIL_COUNT=$((FAIL_COUNT + 1)); }

command -v jq >/dev/null 2>&1 || { echo "FAIL: jq is required" >&2; exit 1; }
if ! command -v koto >/dev/null 2>&1; then
    echo "SKIP: koto not on PATH -- the template was not compiled, so nothing was checked"
    exit 0
fi

WORK=$(mktemp -d "${TMPDIR:-/tmp}/execute-structure-test.XXXXXX")
trap 'rm -rf "$WORK"' EXIT
export HOME="$WORK/home"
mkdir -p "$HOME"

compile() { # compile <template> -> prints the compiled JSON path, or nothing
    koto template compile "$1" 2>/dev/null | tail -1
}

PLUGIN_ROOT_PATTERN='^/([^/.][^/]*|\.[^/.][^/]*|\.\.[^/]+|\.)?(/([^/.][^/]*|\.[^/.][^/]*|\.\.[^/]+|\.)?)*$'

# holds <compiled json> <jq filter that is true when the property holds>
holds() { jq -e "$2" "$1" >/dev/null 2>&1; }

# The named checks. Each is a jq expression over the compiled template.
CHECKS=(
"merge_attempt has no default_action|.states.merge_attempt.default_action == null"
"merge_attempt carries the non-overridable merge_intent gate|.states.merge_attempt.gates.merge_intent == {type: \"command\", command: \"test \\\"{{MERGE}}\\\" = true\", overridable: false}"
"merge_intent's failure edge targets ready_awaiting_merge|[.states.merge_attempt.transitions[] | select(.when == {\"gates.merge_intent.exit_code\": 1})] | length == 1 and .[0].target == \"ready_awaiting_merge\""
"every other merge_attempt edge requires merge_intent to pass|[.states.merge_attempt.transitions[] | select(.when != {\"gates.merge_intent.exit_code\": 1}) | .when[\"gates.merge_intent.exit_code\"] == 0] | length > 0 and all"
"every merge_route gate is a non-overridable context-matches gate|[.states.merge_route.gates[] | (.type == \"context-matches\" and .overridable == false)] | length > 0 and all"
"every merge_confirm gate is a non-overridable context-matches gate|[.states.merge_confirm.gates[] | (.type == \"context-matches\" and .overridable == false)] | length > 0 and all"
"merge_confirm has no command gate|[.states.merge_confirm.gates[] | select(.type == \"command\")] | length == 0"
"merge_confirm's confirm read is a default action running record-merge-verdict.sh --confirm|(.states.merge_confirm.default_action.command // \"\") | test(\"record-merge-verdict\\\\.sh --confirm \")"
"merge_readiness's default action runs record-merge-verdict.sh with {{MERGE}}|(.states.merge_readiness.default_action.command // \"\") | (test(\"record-merge-verdict\\\\.sh \") and test(\"--merge \\\"\\\\{\\\\{MERGE\\\\}\\\\}\\\"\"))"
"no transition targets done|[.states[] | (.transitions // [])[] | select(.target == \"done\")] | length == 0"
"merged's only incoming edge is from merge_confirm|[.states | to_entries[] | .key as \$s | (.value.transitions // [])[] | select(.target == \"merged\") | \$s] | . == [\"merge_confirm\"]"
"no context_assignments block writes home_pr|[.states[] | (.transitions // [])[] | (.context_assignments // {}) | has(\"home_pr\")] | any | not"
"escalate_dirty_merge_state routes to done_blocked|[.states.escalate_dirty_merge_state.transitions[].target] == [\"done_blocked\"]"
"ci_monitor's dirty_merge_state edge still targets escalate_dirty_merge_state|[.states.ci_monitor.transitions[] | select(.when.ci_outcome == \"dirty_merge_state\") | .target] == [\"escalate_dirty_merge_state\"]"
"ci_monitor's passing and failing_fixed edges target merge_readiness|[.states.ci_monitor.transitions[] | select(.when.ci_outcome == \"passing\" or .when.ci_outcome == \"failing_fixed\") | .target] | length == 2 and all(. == \"merge_readiness\")"
"no default_action command holds \${context.|[.states[] | (.default_action.command // \"\") | contains(\"\${context.\")] | any | not"
"every edge into a terminal assigns a literal outcome|[.states as \$all | .states[] | (.transitions // [])[] | select(\$all[.target].terminal == true) | ((.context_assignments.outcome // \"\") | (length > 0 and (contains(\"\${\") | not) and (contains(\"{{\") | not)))] | length > 0 and all"
"no assignment reads \${context.|[.states[] | (.transitions // [])[] | (.context_assignments // {}) | .[] | contains(\"\${context.\")] | any | not"
"step and reason are assigned only as literals|[.states[] | (.transitions // [])[] | (.context_assignments // {}) | to_entries[] | select(.key == \"step\" or .key == \"reason\") | .value | (contains(\"\${\") or contains(\"{{\"))] | any | not"
"every terminal declares the full result map|[.states[] | select(.terminal == true) | (.result // {}) | keys == [\"outcome\",\"pr\",\"reason\",\"repos\",\"resume\",\"step\",\"waiting\"]] | length >= 5 and all"
"every terminal reads step and reason from context|[.states[] | select(.terminal == true) | .result.step == \"\${context.step}\" and .result.reason == \"\${context.reason}\"] | all"
"the legacy done terminal's outcome is ready-awaiting-merge|.states.done.result.outcome == \"ready-awaiting-merge\""
"MERGE is values [true, false], default false, rebind|.variables.MERGE | (.values == [\"true\",\"false\"] and .default == \"false\" and .rebind == true)"
"PAUSE_BEFORE_FINALIZE is values [true, false], rebind|.variables.PAUSE_BEFORE_FINALIZE | (.values == [\"true\",\"false\"] and .rebind == true)"
"PLAN_DOC and PLAN_SLUG are not rebindable|(.variables.PLAN_DOC.rebind // false) == false and (.variables.PLAN_SLUG.rebind // false) == false"
"PLAN_SLUG carries ^[a-z0-9-]+\$|.variables.PLAN_SLUG.pattern == \"^[a-z0-9-]+\$\""
)

run_checks() { # run_checks <compiled json> -> prints the labels that fail
    local json="$1" entry label filter
    for entry in "${CHECKS[@]}"; do
        label="${entry%%|*}"
        filter="${entry#*|}"
        holds "$json" "$filter" || printf '%s\n' "$label"
    done
    # The PLUGIN_ROOT pattern is compared as a string, outside jq's escaping.
    if [ "$(jq -r '.variables.PLUGIN_ROOT.pattern // ""' "$json")" != "$PLUGIN_ROOT_PATTERN" ]; then
        printf '%s\n' "PLUGIN_ROOT carries the absolute-path pattern"
    fi
}

# --- the shipped template ------------------------------------------------------

SHIPPED=$(compile "$TEMPLATE")
if [ -z "$SHIPPED" ] || [ ! -f "$SHIPPED" ]; then
    fail "execute.md does not compile"
    koto template compile "$TEMPLATE" 2>&1 | tail -3
    echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed"
    exit 1
fi
FAILED=$(run_checks "$SHIPPED")
for entry in "${CHECKS[@]}" "PLUGIN_ROOT carries the absolute-path pattern|"; do
    label="${entry%%|*}"
    if printf '%s\n' "$FAILED" | grep -qxF "$label"; then
        fail "$label"
    else
        pass "$label"
    fi
done

# --- each check bites -----------------------------------------------------------
#
# A copy of the template, changed in one place, must fail the check that is
# about that place. The copy sits beside a link to /work-on so its relative
# child-template path still resolves.

MUT_DIR="$WORK/mut/skills/execute/koto-templates"
mkdir -p "$MUT_DIR"
ln -s "$SKILL_DIR/../work-on" "$WORK/mut/skills/work-on"

mutate() { # mutate <label> <expected failing check> <perl substitution>
    local label="$1" want="$2" sub="$3" json failed
    perl -0pe "$sub" "$TEMPLATE" > "$MUT_DIR/execute.md"
    if cmp -s "$TEMPLATE" "$MUT_DIR/execute.md"; then
        fail "mutation [$label] did not change the template; the substitution no longer matches"
        return
    fi
    # --allow-legacy-gates skips only koto's reachability check, which an
    # overridable merge_intent gate would fail on its own; the mutation is
    # about what this suite catches, not what the compiler does.
    json=$(koto template compile --allow-legacy-gates "$MUT_DIR/execute.md" 2>/dev/null | tail -1)
    if [ -z "$json" ] || [ ! -f "$json" ]; then
        fail "mutation [$label] does not compile, so it proves nothing"
        koto template compile "$MUT_DIR/execute.md" 2>&1 | tail -2
        return
    fi
    failed=$(run_checks "$json")
    if printf '%s\n' "$failed" | grep -qxF "$want"; then
        pass "the check fails on a copy with $label"
    else
        fail "a copy with $label passed [$want]"
    fi
}

mutate "an assignment writing home_pr from evidence" \
    "no context_assignments block writes home_pr" \
    's/(          merge_exec: refused\n        context_assignments:\n)/$1          home_pr: "\${evidence.merge_line}"\n/'
mutate "an overridable merge_intent gate" \
    "merge_attempt carries the non-overridable merge_intent gate" \
    's/(command: .test "\{\{MERGE\}\}" = true.\n        overridable: )false/${1}true/'
mutate "ci_monitor's passing edge back on done" \
    "no transition targets done" \
    's/(      - target: )merge_readiness(\n        when:\n          ci_outcome: passing)/${1}done$2/'
mutate "a second edge into merged" \
    "merged's only incoming edge is from merge_confirm" \
    's/(      - target: )ready_awaiting_merge(\n        when:\n          gates.merge_intent.exit_code: 0\n          merge_exec: refused)/${1}merged$2/'
mutate "a \${context. in a default action" \
    "no default_action command holds \${context." \
    's/--head-branch "\$\(koto context get execute-\{\{PLAN_SLUG\}\} settled_branch\)"(.\n      fallback: >-\n        koto could not record the merge verdict)/--head-branch "\${context.settled_branch}"$1/'

echo
echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed"
[ "$FAIL_COUNT" -eq 0 ] || exit 1
exit 0
