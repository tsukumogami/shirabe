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
#   - every terminal declares a result with `outcome`, and a walk of every edge
#     into every terminal finds `outcome` assigned from the closed set (and a
#     closed-set `step` on the error and refusal edges);
#   - resume_route runs resume-probe.sh as its one non-overridable gate and
#     sends each row code to the target Key Interfaces names;
#   - every edge into a cleanup state requires intent_declared to fail, beside
#     a parallel edge into the matching publish state, and each publish state
#     verifies with --verify --expect-intent and routes the failed step on a
#     non-overridable publish_step gate;
#   - executed_report takes no evidence and routes on non-overridable
#     context-matches gates; /scope ships no owned-pr script of its own;
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
WORD=$(printf '%s\n' "$FRONT" | grep -oE '(Twenty|Thirty|Forty)(-[a-z]+)? states' | head -1 | sed 's/ states//')
num() {
    local tens=0 unit=0 w
    w=$(printf '%s' "$1" | tr 'A-Z' 'a-z')
    case "${w%%-*}" in twenty) tens=20 ;; thirty) tens=30 ;; forty) tens=40 ;; esac
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
done
eq "done_refused's result carries the coordinator's keys" \
    '["intent","next","outcome","plan_execution_mode","plan_path","reason","recorded","requested","step"]' \
    "$(q '.states.done_refused.result | keys')"
eq "done_error's result carries the coordinator's keys" \
    '["exit","intent","outcome","reason","recorded","requested","step","wip_paths"]' \
    "$(q '.states.done_error.result | keys')"

# --- terminals and their results -----------------------------------------------------

TERMINALS='["done_abandonment","done_cancelled","done_error","done_executed","done_full_run","done_re_evaluation","done_refused","done_republished"]'
eq "the eight terminals" "$TERMINALS" "$(q '[.states | to_entries[] | select(.value.terminal == true) | .key] | sort')"
eq "every terminal declares a result with outcome" '[]' \
    "$(q '[.states | to_entries[] | select(.value.terminal == true) | select((.value.result.outcome // "") == "") | .key]')"
eq "every result key is drawn from the documented set" '[]' \
    "$(q '[.states[] | select(.terminal == true) | .result | keys[]] | unique
          - ["outcome","exit","intent","next","pr","pr_state","plan_path","plan_execution_mode","wip_paths","startable","boundary","via","reason","recorded","requested","step"]')"

# Walk every edge into every terminal. A terminal whose result reads
# ${context.outcome} needs every edge landing there to assign outcome, from the
# closed set, and the error edges to assign a step from the closed set.
EDGES=$(q '[.states | to_entries[] | .key as $from | (.value.transitions // [])[]
            | select(.target | startswith("done_"))
            | {from: $from, to: .target, outcome: (.context_assignments.outcome // ""), step: (.context_assignments.step // "")}]')
eq "every edge into a terminal assigns outcome" '[]' \
    "$(printf '%s' "$EDGES" | jq -c '[.[] | select(.outcome == "") | "\(.from)->\(.to)"]')"
eq "every assigned outcome is in the closed set" '[]' \
    "$(printf '%s' "$EDGES" | jq -c '[.[] | select(.outcome | IN("scoped","handed-off-multi-pr","executed","re-evaluation","abandonment","cancelled","refused","error") | not) | "\(.from)->\(.to)=\(.outcome)"]')"
eq "each terminal receives only its own outcome" '[]' \
    "$(printf '%s' "$EDGES" | jq -c '[.[] | select(
        (.to == "done_full_run" and (.outcome | IN("scoped","handed-off-multi-pr") | not))
        or (.to == "done_republished" and (.outcome | IN("scoped","handed-off-multi-pr") | not))
        or (.to == "done_executed" and .outcome != "executed")
        or (.to == "done_re_evaluation" and .outcome != "re-evaluation")
        or (.to == "done_abandonment" and .outcome != "abandonment")
        or (.to == "done_cancelled" and .outcome != "cancelled")
        or (.to == "done_refused" and .outcome != "refused")
        or (.to == "done_error" and .outcome != "error")) | "\(.from)->\(.to)"]')"
eq "every edge into done_error and done_refused assigns a step from the closed set" '[]' \
    "$(printf '%s' "$EDGES" | jq -c '[.[] | select(.to == "done_error" or .to == "done_refused")
        | select(.step | IN("scope:push","scope:pr-create","scope:intake","scope:resume-probe","scope:refused") | not) | "\(.from)->\(.to)"]')"
eq "done_executed reports the owned PR the script recorded" '["${context.executed_pr}","${context.executed_pr_state}"]' \
    "$(q '.states.done_executed.result | [.pr, .pr_state]')"

# --- resume_route ----------------------------------------------------------------------

eq "branch_check's success edges go to resume_route" '["resume_route","resume_route","bail"]' \
    "$(q '[.states.branch_check.transitions[] | .target]')"
eq "resume_route has one gate, running resume-probe.sh, not overridable" '[["ladder","command",true,false]]' \
    "$(q '[.states.resume_route.gates | to_entries[] | [.key, .value.type, (.value.command | test("scripts/resume-probe\\.sh")), .value.overridable]]')"
eq "resume_route routes each probe code to its row's target" \
    '{"10":"setup","11":"setup","12":"setup","2":"done_error","20":"discovery","21":"hop_select","22":"finalize","24":"resume_stale","25":"resume_malformed","26":"resume_exit_set","27":"publish_full_run","28":"publish_re_evaluation","29":"publish_abandonment","40":"republish","41":"done_refused","42":"done_refused","43":"resume_draft","44":"executed_report","45":"resume_boundary","46":"resume_draft","47":"resume_boundary","48":"resume_draft","49":"setup","50":"resume_draft","60":"setup","61":"setup","62":"setup","63":"setup"}' \
    "$(q '[.states.resume_route.transitions[] | {key: (.when["gates.ladder.exit_code"] | tostring), value: .target}] | from_entries' | jq -cS .)"
eq "row 41 refuses as plan-active and row 42 as plan-done with next=/release" '[["plan-active",null],["plan-done","/release {{TOPIC}}"]]' \
    "$(q '[.states.resume_route.transitions[] | select(.target == "done_refused") | [.context_assignments.reason, .context_assignments.next]]')"
eq "row 2 ends scope:resume-probe" '"scope:resume-probe"' \
    "$(q '.states.resume_route.transitions[] | select(.when["gates.ladder.exit_code"] == 2) | .context_assignments.step')"

# --- publish ---------------------------------------------------------------------------

for s in exit_full_run full_run_blocked exit_re_evaluation exit_abandonment; do
    eq "$s carries intent_declared" '"test \"{{RUN_INTENT}}\" != none"' "$(q ".states.$s.gates.intent_declared.command")"
done
eq "every edge into a cleanup state requires intent_declared to fail" '[]' \
    "$(q '[.states | to_entries[] | .key as $from | (.value.transitions // [])[]
           | select(.target | startswith("cleanup_")) | select($from | startswith("publish_") | not)
           | select(.when["gates.intent_declared.exit_code"] != 1) | "\($from)->\(.target)"]')"
eq "each cleanup edge has a parallel publish edge on exit code 0" '[]' \
    "$(q '[.states | to_entries[] | .key as $from | .value.transitions as $t | ($t // [])[]
           | select(.target | startswith("cleanup_")) | select($from | startswith("publish_") | not)
           | . as $c | ($c.target | sub("^cleanup_"; "publish_")) as $p
           | select([$t[] | select(.target == $p and .when["gates.intent_declared.exit_code"] == 0
                     and ((.when | del(.["gates.intent_declared.exit_code"])) == ($c.when | del(.["gates.intent_declared.exit_code"]))))] | length != 1)
           | "\($from)->\($c.target)"]')"
for s in publish_full_run publish_re_evaluation publish_abandonment republish; do
    eq "$s verifies with --verify --expect-intent RUN_INTENT" 'true' \
        "$(q ".states.$s.gates.published.command | test(\"publish-scoping-pr\\\\.sh\\\" --topic \\\"{{TOPIC}}\\\" --verify --expect-intent \\\"{{RUN_INTENT}}\\\"\")")"
    eq "$s routes the failed step on publish_step, not overridable" '["context-matches","publish_step","^scope:push$",false]' \
        "$(q ".states.$s.gates.publish_push | [.type, .key, .pattern, .overridable]")"
    eq "$s: only the push arm assigns scope:push" 'true' \
        "$(q "[.states.$s.transitions[] | select(.target == \"done_error\") | [.when[\"gates.publish_push.matches\"], .context_assignments.step]]
              | all(if .[0] == true then .[1] == \"scope:push\" else .[1] == \"scope:pr-create\" end)")"
done
eq "republish has no default action" 'null' "$(q '.states.republish.default_action')"
eq "republish_record runs record-scope-exit.sh" 'true' \
    "$(q '.states.republish_record.default_action.command | test("scripts/record-scope-exit\\.sh")')"

# --- executed_report ----------------------------------------------------------------------

eq "executed_report's action is record-executed-report.sh" 'true' \
    "$(q '.states.executed_report.default_action.command | test("scripts/record-executed-report\\.sh")')"
eq "executed_report takes no evidence" 'null' "$(q '.states.executed_report.accepts')"
eq "executed_report routes only on non-overridable context-matches gates" '[["context-matches","executed_pr_state",false],["context-matches","executed_verdict",false]]' \
    "$(q '[.states.executed_report.gates[] | [.type, .key, .overridable]]')"

# --- owned-pr.sh is the shared one ----------------------------------------------------------

REPO_ROOT="$(cd "$HERE/../../.." && pwd)"
if [ -n "$(git -C "$REPO_ROOT" ls-files 'skills/scope/**/owned-pr*' 2>/dev/null)" ]; then
    bad "/scope ships no ownership script of its own" "$(git -C "$REPO_ROOT" ls-files 'skills/scope/**/owned-pr*')"
else
    ok "/scope ships no ownership script of its own"
fi
CALLS=$(grep -rn '/owned-pr\.sh' "$HERE" --include='*.sh' | grep -v '_test\.sh:' | grep -v ':[[:space:]]*#' | grep -v '/execute/scripts/owned-pr\.sh' || true)
if [ -z "$CALLS" ]; then
    ok "every owned-pr.sh call resolves to skills/execute/scripts/owned-pr.sh"
else
    bad "every owned-pr.sh call resolves to skills/execute/scripts/owned-pr.sh" "$CALLS"
fi
eq "hop_plan's landed edge requires plan_mode_consistent" 'true' \
    "$(q '[.states.hop_plan.transitions[] | select(.target == "fold") | .when["gates.plan_mode_consistent.exit_code"]] == [0]')"
eq "a plan-mode mismatch routes to bail" 'true' \
    "$(q '[.states.hop_plan.transitions[] | select(.target == "bail" and .when["gates.plan_mode_consistent.exit_code"] == 1)] | length == 1')"

echo
echo "passed: $PASS   failed: $FAIL"
[ "$FAIL" -eq 0 ]
