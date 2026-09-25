#!/usr/bin/env bash
# execute-coordinated-structure_test.sh — the coordinated envelope's shape,
# read from the compiled template
# Part of the execute skill
#
# The coordinated envelope's guarantees are properties of its graph, so this
# reads the graph itself: `koto template compile` turns execute-coordinated.md
# into JSON and each assertion is a jq query over it.
#
# It asserts, on the shipped template:
#
#   the states are exactly coord_setup (initial), coord_loop, coord_verdict,
#     coord_merge_confirm, merged, ready_awaiting_merge,
#     paused_awaiting_merges, done_blocked, and done_error; no done_refused
#   coord_setup and coord_loop are agent-run (no default_action); coord_loop's
#     edges key only on the agent's loop_exit, never on a gate or merge state
#   coord_verdict takes no agent evidence and runs
#     record-coordination-verdict.sh as its default action
#   every edge into `merged` comes from coord_merge_confirm and no other state
#   coord_merge_confirm declares no command gate, and runs
#     record-merge-verdict.sh --confirm with --repo read from home_repo (never
#     the comma-joined repos) and --head-branch from coord_branch
#   every coord_merge_confirm and coord_verdict gate is a context-matches gate
#     declared overridable: false
#   no edge out of coord_verdict assigns reason, and only its absent-or-
#     unmatched edge assigns step, the literal execute:status-read
#   coord_merge_confirm's not-merged edge assigns the literal reason
#     merge-not-observed
#   every edge into a terminal assigns a literal outcome; step and reason are
#     assigned only as literals; no assignment reads ${context. or
#     ${gates.<g>.<path>} (there is no command gate whose output could hold a
#     script's)
#   every terminal declares the result map (outcome, step, reason, pr, repos,
#     resume, waiting), step and reason read from context
#   the variables: PLAN_DOC and PLAN_SLUG not rebindable (PLAN_SLUG pattern
#     ^[a-z0-9-]+$), MERGE and PAUSE_BEFORE_FINALIZE values [true, false]
#     default false rebind, PLUGIN_ROOT the same absolute-path pattern as
#     execute.md
#   no default_action command holds ${context.
#
# and, engine-free, over the source and the skill's tree:
#   the template carries the `# koto-floor: pinned` marker
#   `outcome=` followed by `refused` appears nowhere under skills/execute/
#   the only line that builds a `head=` field is in node-push.sh
#
# and that each structural check bites on a mutated copy: a second edge into
# merged, a command gate on coord_merge_confirm, an overridable coord_verdict
# gate, a reason assignment out of coord_verdict, and a done_refused state.
#
# Usage: execute-coordinated-structure_test.sh
# Exit codes: 0 all pass (or koto absent: the compiled checks SKIP loudly),
#             1 a failure

set -uo pipefail

SCRIPT_DIR=$(CDPATH='' cd "$(dirname "$0")" && pwd)
SKILL_DIR=$(CDPATH='' cd "$SCRIPT_DIR/.." && pwd)
TEMPLATE="$SKILL_DIR/koto-templates/execute-coordinated.md"
SINGLE="$SKILL_DIR/koto-templates/execute.md"

PASS_COUNT=0
FAIL_COUNT=0
pass() { echo "PASS: $*"; PASS_COUNT=$((PASS_COUNT + 1)); }
fail() { echo "FAIL: $*"; FAIL_COUNT=$((FAIL_COUNT + 1)); }

command -v jq >/dev/null 2>&1 || { echo "FAIL: jq is required" >&2; exit 1; }
[ -f "$TEMPLATE" ] || { echo "FAIL: $TEMPLATE not found" >&2; exit 1; }

# --- engine-free ------------------------------------------------------------------

if grep -q '^# koto-floor: pinned' "$TEMPLATE"; then
    pass "execute-coordinated.md carries the # koto-floor: pinned marker"
else
    fail "execute-coordinated.md lacks the # koto-floor: pinned marker"
fi

# The token is built from two halves so this file doesn't carry it either.
BANNED="outcome=""refused"
REFUSED=$(grep -rn -- "$BANNED" "$SKILL_DIR" 2>/dev/null || true)
if [ -z "$REFUSED" ]; then
    pass "the refused outcome token appears nowhere under skills/execute/ (tests included)"
else
    fail "the refused outcome token appears: $REFUSED"
fi

# Lines that build a head= field: a `head=` followed by a shell expansion, in
# non-comment lines of the skill's scripts, templates, and SKILL.md. Reads (a
# regex group, a sed) and tests don't build one.
HEAD_WRITES=$(grep -rn 'head=\$' "$SKILL_DIR/scripts" "$SKILL_DIR/koto-templates" "$SKILL_DIR/SKILL.md" 2>/dev/null \
    | grep -v '_test\.sh:' | grep -v '/coord-test-helpers\.sh:' \
    | grep -v '^[^:]*:[0-9]*:[[:space:]]*#' \
    | grep -v "printf 'pr=%s\\\\nhead=%s" || true)
if [ -n "$HEAD_WRITES" ] && [ -z "$(printf '%s\n' "$HEAD_WRITES" | grep -v '/node-push\.sh:')" ]; then
    pass "the only line that builds a head= field is in node-push.sh"
else
    fail "head= is built outside node-push.sh (or nowhere): $HEAD_WRITES"
fi

if ! command -v koto >/dev/null 2>&1; then
    echo "SKIP: koto not on PATH -- the template was not compiled, so its graph was not checked"
    echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed"
    [ "$FAIL_COUNT" -eq 0 ] || exit 1
    exit 0
fi

WORK=$(mktemp -d "${TMPDIR:-/tmp}/coord-structure-test.XXXXXX")
trap 'rm -rf "$WORK"' EXIT
export HOME="$WORK/home"
mkdir -p "$HOME"

compile() { koto template compile "$@" 2>/dev/null | tail -1; }
holds() { jq -e "$2" "$1" >/dev/null 2>&1; }

CHECKS=(
"the states are exactly the envelope's nine|.states | keys == [\"coord_loop\",\"coord_merge_confirm\",\"coord_setup\",\"coord_verdict\",\"done_blocked\",\"done_error\",\"merged\",\"paused_awaiting_merges\",\"ready_awaiting_merge\"]"
"coord_setup is the initial state|.initial_state == \"coord_setup\""
"no done_refused state is declared|.states | has(\"done_refused\") | not"
"merged, ready_awaiting_merge, and paused_awaiting_merges are non-failure terminals|[.states.merged, .states.ready_awaiting_merge, .states.paused_awaiting_merges] | all(. != null and .terminal == true and ((.failure // false) == false))"
"done_blocked and done_error are failure terminals|.states.done_blocked.terminal == true and .states.done_blocked.failure == true and .states.done_error.terminal == true and .states.done_error.failure == true"
"coord_setup is agent-run|.states.coord_setup.default_action == null"
"coord_loop is agent-run with no gates|.states.coord_loop.default_action == null and ((.states.coord_loop.gates // {}) | length == 0)"
"coord_loop's edges key only on loop_exit|[.states.coord_loop.transitions[] | .when | keys == [\"loop_exit\"]] | length == 3 and all"
"coord_verdict takes no agent evidence|(.states.coord_verdict.accepts // {}) | length == 0"
"coord_verdict's default action runs record-coordination-verdict.sh|(.states.coord_verdict.default_action.command // \"\") | test(\"record-coordination-verdict\\\\.sh \")"
"every edge into merged comes from coord_merge_confirm|[.states | to_entries[] | .key as \$s | (.value.transitions // [])[] | select(.target == \"merged\") | \$s] | . == [\"coord_merge_confirm\"]"
"coord_merge_confirm declares no command gate|[.states.coord_merge_confirm.gates[] | select(.type == \"command\")] | length == 0"
"every coord_merge_confirm gate is a non-overridable context-matches gate|[.states.coord_merge_confirm.gates[] | (.type == \"context-matches\" and .overridable == false)] | length > 0 and all"
"every coord_verdict gate is a non-overridable context-matches gate|[.states.coord_verdict.gates[] | (.type == \"context-matches\" and .overridable == false)] | length > 0 and all"
"coord_merge_confirm runs record-merge-verdict.sh --confirm on home_repo and coord_branch|(.states.coord_merge_confirm.default_action.command // \"\") | (test(\"record-merge-verdict\\\\.sh --confirm \") and test(\"--repo \\\"\\\\\$\\\\(koto context get execute-\\\\{\\\\{PLAN_SLUG\\\\}\\\\} home_repo\\\\)\\\"\") and test(\"--head-branch \\\"\\\\\$\\\\(koto context get execute-\\\\{\\\\{PLAN_SLUG\\\\}\\\\} coord_branch\\\\)\\\"\") and (test(\" repos\\\\)\") | not))"
"no edge out of coord_verdict assigns reason|[.states.coord_verdict.transitions[] | (.context_assignments // {}) | has(\"reason\")] | any | not"
"only coord_verdict's absent-or-unmatched edge assigns step, the literal execute:status-read|[.states.coord_verdict.transitions[] | select((.context_assignments // {}) | has(\"step\"))] | length == 1 and .[0].context_assignments.step == \"execute:status-read\" and ([.[0].when | to_entries[] | select(.key | startswith(\"gates.\")) | .value] | all(. == false))"
"coord_merge_confirm's not-merged edge assigns reason merge-not-observed|[.states.coord_merge_confirm.transitions[] | select(.target == \"ready_awaiting_merge\") | .context_assignments.reason] == [\"merge-not-observed\"]"
"every edge into a terminal assigns a literal outcome|[.states as \$all | .states[] | (.transitions // [])[] | select(\$all[.target].terminal == true) | ((.context_assignments.outcome // \"\") | (length > 0 and (contains(\"\${\") | not) and (contains(\"{{\") | not)))] | length > 0 and all"
"step and reason are assigned only as literals|[.states[] | (.transitions // [])[] | (.context_assignments // {}) | to_entries[] | select(.key == \"step\" or .key == \"reason\") | .value | (contains(\"\${\") or contains(\"{{\"))] | any | not"
"no assignment reads \${context. or \${gates.|[.states[] | (.transitions // [])[] | (.context_assignments // {}) | .[] | (contains(\"\${context.\") or contains(\"\${gates.\"))] | any | not"
"every terminal declares the full result map|[.states[] | select(.terminal == true) | (.result // {}) | keys == [\"outcome\",\"pr\",\"reason\",\"repos\",\"resume\",\"step\",\"waiting\"]] | length == 5 and all"
"every terminal reads step and reason from context|[.states[] | select(.terminal == true) | .result.step == \"\${context.step}\" and .result.reason == \"\${context.reason}\"] | all"
"no default_action command holds \${context.|[.states[] | (.default_action.command // \"\") | contains(\"\${context.\")] | any | not"
"MERGE is values [true, false], default false, rebind|.variables.MERGE | (.values == [\"true\",\"false\"] and .default == \"false\" and .rebind == true)"
"PAUSE_BEFORE_FINALIZE is values [true, false], default false, rebind|.variables.PAUSE_BEFORE_FINALIZE | (.values == [\"true\",\"false\"] and .default == \"false\" and .rebind == true)"
"PLAN_DOC and PLAN_SLUG are not rebindable|(.variables.PLAN_DOC.rebind // false) == false and (.variables.PLAN_SLUG.rebind // false) == false"
"PLAN_SLUG carries ^[a-z0-9-]+\$|.variables.PLAN_SLUG.pattern == \"^[a-z0-9-]+\$\""
"PLUGIN_ROOT is rebindable|.variables.PLUGIN_ROOT.rebind == true"
)

run_checks() { # run_checks <compiled json> -> prints the labels that fail
    local json="$1" entry label filter
    for entry in "${CHECKS[@]}"; do
        label="${entry%%|*}"
        filter="${entry#*|}"
        holds "$json" "$filter" || printf '%s\n' "$label"
    done
    if [ "$(jq -r '.variables.PLUGIN_ROOT.pattern // ""' "$json")" != "$SINGLE_PLUGIN_PATTERN" ]; then
        printf '%s\n' "PLUGIN_ROOT carries execute.md's absolute-path pattern"
    fi
}

SINGLE_JSON=$(compile "$SINGLE")
SINGLE_PLUGIN_PATTERN=$(jq -r '.variables.PLUGIN_ROOT.pattern // ""' "$SINGLE_JSON" 2>/dev/null)
SHIPPED=$(compile "$TEMPLATE")
if [ -z "$SHIPPED" ] || [ ! -f "$SHIPPED" ]; then
    fail "execute-coordinated.md does not compile"
    koto template compile "$TEMPLATE" 2>&1 | tail -3
    echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed"
    exit 1
fi
pass "execute-coordinated.md compiles"
FAILED=$(run_checks "$SHIPPED")
for entry in "${CHECKS[@]}" "PLUGIN_ROOT carries execute.md's absolute-path pattern|"; do
    label="${entry%%|*}"
    if printf '%s\n' "$FAILED" | grep -qxF "$label"; then fail "$label"; else pass "$label"; fi
done

# --- each check bites -------------------------------------------------------------

MUT="$WORK/mut.md"
mutate() { # mutate <label> <expected failing check> <perl substitution>
    local label="$1" want="$2" sub="$3" json failed
    perl -0pe "$sub" "$TEMPLATE" > "$MUT"
    if cmp -s "$TEMPLATE" "$MUT"; then
        fail "mutation [$label] did not change the template; the substitution no longer matches"
        return
    fi
    json=$(compile --allow-legacy-gates "$MUT")
    if [ -z "$json" ] || [ ! -f "$json" ]; then
        fail "mutation [$label] does not compile, so it proves nothing"
        koto template compile --allow-legacy-gates "$MUT" 2>&1 | tail -2
        return
    fi
    failed=$(run_checks "$json")
    if printf '%s\n' "$failed" | grep -qxF "$want"; then
        pass "the check fails on a copy with $label"
    else
        fail "a copy with $label passed [$want]"
    fi
}

mutate "a second edge into merged (from coord_verdict)" \
    "every edge into merged comes from coord_merge_confirm" \
    's/(      - target: )coord_merge_confirm(\n        when:\n          gates.verdict_merged.matches: true)/${1}merged$2/'
mutate "a command gate on coord_merge_confirm" \
    "coord_merge_confirm declares no command gate" \
    's/(    gates:\n      confirmed_merged:\n)/$1        type: context-matches\n        key: confirm_verdict\n        pattern: x\n        overridable: false\n      confirm_exit:\n        type: command\n        command: "true"\n        overridable: false\n      confirmed_merged_2:\n/'
mutate "an overridable coord_verdict gate" \
    "every coord_verdict gate is a non-overridable context-matches gate" \
    's/(pattern: .\^ready\$.\n        overridable: )false/${1}true/'
mutate "a reason assigned out of coord_verdict" \
    "no edge out of coord_verdict assigns reason" \
    's/(        context_assignments:\n          outcome: paused-awaiting-merges\n)/$1          reason: predecessor-unmerged\n/'
mutate "a done_refused state" \
    "no done_refused state is declared" \
    's/(\n  done_error:\n)/\n  done_refused:\n    terminal: true\n    failure: true\n$1/; s/\z/\n## done_refused\n\nRefused.\n/'

echo
echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed"
[ "$FAIL_COUNT" -eq 0 ] || exit 1
exit 0
