#!/usr/bin/env bash
# scope-template_test.sh -- static properties of skills/scope/koto-templates/scope.md
# that koto's compiler does not check for us.
#
#   - no transition assignment reads ${gates.<g>.<path>} over a command gate:
#     a command gate exposes only exit_code and error, so such a value can
#     never carry what a script printed (script output reaches a result only
#     through a default action writing context);
#   - every gate and default-action command quotes each {{VAR}} it uses;
#   - `intake` is the initial state, and its routing gates refuse overrides;
#   - the argument variables carry the constraints scope-open.sh relies on;
#   - done_refused and done_error are failure terminals whose result maps carry
#     the keys a coordinator reads;
#   - the frontmatter description's state count matches the states declared.
#
# Usage: bash skills/scope/scripts/scope-template_test.sh
# Exit 0 when every case holds. The compiled-template cases need koto and jq and
# are skipped with a message without them; the text cases need only bash and awk.
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
TEMPLATE="$HERE/../koto-templates/scope.md"

PASS=0
FAIL=0
ok()  { PASS=$((PASS + 1)); printf 'ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); printf 'FAIL %s\n     %s\n' "$1" "${2-}"; }
eq()  { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "want [$2], got [$3]"; fi; }

FRONT=$(awk 'NR == 1 && $0 == "---" { inside = 1; next } inside && $0 == "---" { exit } inside { print }' "$TEMPLATE")

# --- command gates never feed an assignment ------------------------------------------

# Every gate name whose declaration carries `type: command`.
COMMAND_GATES=$(printf '%s\n' "$FRONT" | awk '
    /^      [A-Za-z_][A-Za-z0-9_]*:[[:space:]]*$/ { name = $1; sub(/:$/, "", name); next }
    /^        type:[[:space:]]*command[[:space:]]*$/ && name != "" { print name }
' | sort -u)
if [ -z "$COMMAND_GATES" ]; then
    bad "command gates are found" "the parser found none; the template's shape changed"
else
    ok "command gates are found ($(printf '%s\n' "$COMMAND_GATES" | wc -l | tr -d ' '))"
fi
OFFENDERS=""
for g in $COMMAND_GATES; do
    hits=$(printf '%s\n' "$FRONT" | grep -n "\${gates\.$g\." || true)
    [ -n "$hits" ] && OFFENDERS="$OFFENDERS $g"
done
if [ -z "$OFFENDERS" ]; then
    ok "no assignment reads \${gates.<g>.<path>} over a command gate"
else
    bad "no assignment reads \${gates.<g>.<path>} over a command gate" "offending gates:$OFFENDERS"
fi

# --- every {{VAR}} in a command is quoted -----------------------------------------------

unquoted_commands() {
    local line stripped
    printf '%s\n' "$FRONT" | grep -E '^[[:space:]]+command:' | while IFS= read -r line; do
        # The YAML single quotes around the value are not shell quoting; drop
        # them, then every double-quoted segment. A {{ left over is unquoted.
        stripped=$(printf '%s' "${line#*command:}" | sed -e "s/^ *'//" -e "s/' *\$//" -e 's/"[^"]*"//g')
        case "$stripped" in
            *'{{'*) printf '%s\n' "$line" ;;
        esac
    done
}
UNQUOTED=$(unquoted_commands)
if [ -z "$UNQUOTED" ]; then
    ok "every gate and action command quotes each {{VAR}} it uses"
else
    bad "every gate and action command quotes each {{VAR}} it uses" "$UNQUOTED"
fi

# --- the description's state count ------------------------------------------------------

STATES=$(printf '%s\n' "$FRONT" | awk '/^states:/ { s = 1; next } s && /^  [a-z_][a-z_0-9]*:[[:space:]]*$/ { n++ } END { print n + 0 }')
WORD=$(printf '%s\n' "$FRONT" | grep -oE '(Twenty|Thirty)(-[a-z]+)? states' | head -1 | sed 's/ states//')
num() {
    local tens=0 unit=0 w
    w=$(printf '%s' "$1" | tr 'A-Z' 'a-z')
    case "${w%%-*}" in twenty) tens=20 ;; thirty) tens=30 ;; esac
    case "$w" in
        *-one) unit=1 ;; *-two) unit=2 ;; *-three) unit=3 ;; *-four) unit=4 ;; *-five) unit=5 ;;
        *-six) unit=6 ;; *-seven) unit=7 ;; *-eight) unit=8 ;; *-nine) unit=9 ;;
    esac
    printf '%s' $((tens + unit))
}
eq "the description's state count matches the states declared" "$STATES" "$(num "$WORD")"

# --- the compiled template --------------------------------------------------------------

if ! command -v koto >/dev/null 2>&1 || ! command -v jq >/dev/null 2>&1; then
    echo "SKIP: koto or jq not on PATH -- the compiled-template cases did not run"
    echo "passed: $PASS   failed: $FAIL"
    [ "$FAIL" -eq 0 ]
    exit
fi

OUT=$(koto template compile "$TEMPLATE" 2>/dev/null) || { bad "koto template compile passes" "$(koto template compile "$TEMPLATE" 2>&1 | tail -3)"; echo "passed: $PASS   failed: $FAIL"; exit 1; }
ok "koto template compile passes"
J=$(cat "$OUT")
q() { printf '%s' "$J" | jq -c "$1"; }

eq "intake is the initial state" '"intake"' "$(q '.initial_state')"
eq "intake's gates are context-matches over intake_verdict, not overridable" \
    '[["context-matches","intake_verdict",false],["context-matches","intake_verdict",false]]' \
    "$(q '[.states.intake.gates[] | [.type, .key, .overridable]]')"
eq "intake's action captures RUN_INTENT" '"RUN_INTENT"' "$(q '.states.intake.default_action.capture_stdout_as')"
eq "intake routes to branch_check, done_refused, done_error" '["branch_check","done_refused","done_error"]' \
    "$(q '[.states.intake.transitions[] | .target]')"

eq "TOPIC: pattern, required, not rebindable" '["^[a-z0-9][a-z0-9-]*$",true,null]' \
    "$(q '.variables.TOPIC | [.pattern, .required, .rebind]')"
eq "INTENT_FLAG: pattern, empty default, not rebindable" '["^(continue|stop)?$",null,null]' \
    "$(q '.variables.INTENT_FLAG | [.pattern, (.default | if . == "" then null else . end), .rebind]')"
eq "PLUGIN_ROOT_PLACEMENT: only outside, required, rebindable" '["^outside$",true,true]' \
    "$(q '.variables.PLUGIN_ROOT_PLACEMENT | [.pattern, .required, .rebind]')"
eq "PLUGIN_ROOT: required and rebindable" '[true,true]' "$(q '.variables.PLUGIN_ROOT | [.required, .rebind]')"
eq "COORDINATION: closed values, default none" '[["none","coordinated","no-coordinated"],"none",null]' \
    "$(q '.variables.COORDINATION | [.values, .default, .rebind]')"
eq "EXEC_MODE: closed values, default interactive, rebindable" '[["auto","interactive","default"],"interactive",true]' \
    "$(q '.variables.EXEC_MODE | [.values, .default, .rebind]')"
eq "MAX_ROUNDS: 1 to 50 or empty, rebindable" '["^([1-9]|[1-4][0-9]|50)?$",true]' \
    "$(q '.variables.MAX_ROUNDS | [.pattern, .rebind]')"
eq "UPSTREAM: patterned, not rebindable" 'true' "$(q '.variables.UPSTREAM | (.pattern != null) and (.rebind != true)')"
eq "no user-settable INTENT variable" 'null' "$(q '.variables.INTENT')"

for t in done_refused done_error; do
    eq "$t is a failure terminal" '[true,true]' "$(q ".states.$t | [.terminal, .failure]")"
    eq "$t's result carries the coordinator's keys" '["intent","outcome","reason","recorded","requested","step"]' \
        "$(q ".states.$t.result | keys")"
done
eq "hop_plan's landed edge requires plan_mode_consistent" 'true' \
    "$(q '[.states.hop_plan.transitions[] | select(.target == "fold") | .when["gates.plan_mode_consistent.exit_code"]] == [0]')"
eq "a plan-mode mismatch routes to bail" 'true' \
    "$(q '[.states.hop_plan.transitions[] | select(.target == "bail" and .when["gates.plan_mode_consistent.exit_code"] == 1)] | length == 1')"

echo
echo "passed: $PASS   failed: $FAIL"
[ "$FAIL" -eq 0 ]
