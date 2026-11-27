#!/usr/bin/env bash
# probe-routes_test.sh -- does work-on.md route a run through the
# rule-distance probe the way docs/guides/probe.md says, driven through real
# `koto next` calls?
#
# The fixture holds the SHIPPED blocks and directives of offload_canary, its
# markers, probe_draw, the probe's markers, reproduce, implementation,
# pr_precheck, probe_near, pr_creation and ci_monitor, with the gates that
# read GitHub or other session keys stubbed to pass. reproduce's red_recorded
# gate and action are the shipped ones, reading the fix_kind.jsonl and
# red_first.json keys a case writes with mark_fix and record_red. A stub
# fix_determination routes to implementation, or to reproduce when mark_fix
# wrote `fix` into the session directory, in the tick that enters it; a stub
# changed_paths_record passes through to pr_precheck, and a stub analysis
# passes through to offload_canary, the loop a scope change takes.
# ci_pass_counting and every other target are stub terminals. The probe's own
# actions, gates and script are real. A gh stub answers the leak gate's pull
# request reads.
#
#   1. Static: the variable, the edges, the gate commands, the ack field, the
#      directive lines and directive_rules, the koto floor, and decider.mode
#      and the registry's stages unchanged from the base.
#   2. Routes: each arm's marker state; the opt-in off and PROBE off run as a
#      run without the probe (no probe files, no marker, no delivery, the
#      probe gates passing, every directive equal to the probe-free
#      template's); no extra agent turn; directive placement per arm; the
#      arrival response; near and far misses advance; far_redeliver holds
#      twice and advances; each created edge; the leak gate holding; the far
#      rule delivered once, at implementation for a change and at reproduce
#      for a fix, and never again on a retry, a hold or the move from
#      reproduce to implementation.
#   3. Records: a far_redeliver run's exported journal, a rewind and a
#      loop back into probe_draw, and a search of the journal for the drawn
#      value.
#   4. Evidence before gates: koto evaluates a state's gates on the log that
#      already holds the evidence submitted in the same call.
#
# The engine parts skip, loudly, when koto is absent (the bash 3.2 floor leg
# has no koto).
#
# Usage: probe-routes_test.sh
# Exit codes: 0 all pass (or the engine parts skipped), 1 any failed, 2 the
# harness could not run.

set -u
. "$(dirname "$0")/../../../scripts/lib/koto-test-guard.sh" || exit 1

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
SKILL_DIR=$(cd "$SCRIPT_DIR/.." && pwd)
TEMPLATE="$SKILL_DIR/koto-templates/work-on.md"
REAL_ROOT=$(cd "$SKILL_DIR/../.." && pwd)

PASS_COUNT=0
FAIL_COUNT=0
pass() { printf 'PASS: %s\n' "$*"; PASS_COUNT=$((PASS_COUNT + 1)); }
fail() { printf 'FAIL: %s\n' "$*"; FAIL_COUNT=$((FAIL_COUNT + 1)); }
check() { if [ "$2" = "$3" ]; then pass "$1"; else fail "$1: got [$2], want [$3]"; fi; }
finish() {
    echo
    echo "probe-routes_test: $PASS_COUNT passed, $FAIL_COUNT failed"
    [ "$FAIL_COUNT" -eq 0 ]
    exit $?
}

[ -f "$TEMPLATE" ] || { echo "template not found: $TEMPLATE" >&2; exit 2; }
command -v jq >/dev/null 2>&1 || { echo "jq is required to run this suite" >&2; exit 2; }

# extract_state <name>: the state's block from the template's frontmatter.
extract_state() {
    awk -v want="  $1:" '
        /^states:$/ { s = 1; next }
        s && $0 == want { on = 1; print; next }
        on && /^  [a-z_]+:$/ { exit }
        on && /^---$/ { exit }
        on && /^  # / { exit }
        on { print }' "$TEMPLATE"
}
# extract_var <name>: the variable's declaration.
extract_var() {
    awk -v want="  $1:" '
        /^variables:$/ { on = 1; next }
        on && /^states:$/ { exit }
        on && $0 == want { found = 1; print; next }
        found && /^  [A-Z][A-Z0-9_]*:$/ { exit }
        found { print }' "$TEMPLATE"
}
# section <name>: the state's directive body, after its heading.
section() {
    awk -v want="## $1" '$0 == want { on = 1; next } on && /^## / { exit } on { print }' "$TEMPLATE"
}
# targets_of <state>: every transition target, one per line.
targets_of() { extract_state "$1" | awk '/^      - target:/ { print $3 }'; }

# --- 1. static ------------------------------------------------------------------

COMPILED=$(mktemp "${TMPDIR:-/tmp}/probe-routes-compiled.XXXXXX") || exit 2
if command -v koto >/dev/null 2>&1 && koto template compile "$TEMPLATE" >"$COMPILED.path" 2>/dev/null; then
    cp "$(tail -n 1 "$COMPILED.path")" "$COMPILED" 2>/dev/null
fi
rm -f "$COMPILED.path"

check "PROBE: values on and off, default on, not rebindable" \
    "$(extract_var PROBE | grep -E '^    (default|values|rebind):' | tr -d ' ' | tr '\n' ';')" 'default:"on";values:["on","off"];'
check "offload_canary's edges all go to probe_draw" \
    "$( { targets_of offload_canary; targets_of offload_arm_withheld; targets_of offload_arm_preloaded; } \
        | grep -v '^offload_arm_' | sort -u | tr '\n' ' ')" "probe_draw "
check "probe_draw routes to the three markers or fix_determination" \
    "$(targets_of probe_draw | tr '\n' ' ')" "probe_arm_near probe_arm_far probe_arm_far_redeliver fix_determination "
for m in probe_arm_near probe_arm_far probe_arm_far_redeliver; do
    check "$m passes through to fix_determination" "$(extract_state $m | sed 1d | tr -d ' \n')" "transitions:-target:fix_determination"
done
PD=$(extract_state probe_draw)
grep -q 'probe.sh" draw "{{PROBE}}" "{{SHARED_BRANCH}}" "{{SESSION_DIR}}" "{{PLUGIN_ROOT}}"' <<<"$PD" \
    && ! grep -q 'capture_stdout_as' <<<"$PD" \
    && pass "probe_draw runs probe.sh draw and captures nothing" \
    || fail "probe_draw's action: $PD"
for pair in "implementation:PROBE_FAR_RULE" "reproduce:PROBE_FAR_RULE_FIX"; do
    st=${pair%%:*}; v=${pair#*:}
    B=$(extract_state "$st")
    grep -q 'probe.sh" far-text "{{SESSION_DIR}}" || true' <<<"$B" \
        && grep -q "^      capture_stdout_as: $v\$" <<<"$B" && grep -q '^      capture_allow_empty: true$' <<<"$B" \
        && pass "$st runs probe.sh far-text into $v with capture_allow_empty" \
        || fail "$st's action: $(grep -A4 'default_action' <<<"$B")"
done
RA=$(extract_state reproduce | awk '/^      command:/ { print; exit }')
case "$RA" in
    *'red-first.sh" has-red "{{SESSION_NAME}}" && exit 0; '*'probe.sh" far-text '*)
        pass "reproduce's action asks red-first.sh has-red before it takes the far rule" ;;
    *) fail "reproduce's action doesn't ask has-red first: $RA" ;;
esac
PN=$(extract_state probe_near)
grep -q 'probe.sh" near-text "{{SESSION_DIR}}"' <<<"$PN" && grep -q '^      capture_stdout_as: PROBE_NEAR_RULE$' <<<"$PN" \
    && grep -q '^      capture_allow_empty: true$' <<<"$PN" && [ "$(targets_of probe_near)" = pr_creation ] \
    && pass "probe_near runs near-text into PROBE_NEAR_RULE and passes through to pr_creation" \
    || fail "probe_near: $PN"
check "pr_precheck's two pull request edges target probe_near" \
    "$(targets_of pr_precheck | grep -c '^probe_near$')" 2
check "no pr_precheck edge targets pr_creation directly" "$(targets_of pr_precheck | grep -c '^pr_creation$')" 0
PC=$(extract_state pr_creation)
check "pr_creation accepts ack, a string with no description" \
    "$(printf '%s\n' "$PC" | awk '/^      ack:$/ { f = 1; next } f && /^      [a-z_]+:$/ { exit } f { print }' | tr -d ' \n')" "type:string"
for pair in "implementation:PROBE_FAR_RULE" "reproduce:PROBE_FAR_RULE_FIX" "pr_creation:PROBE_NEAR_RULE"; do
    st=${pair%%:*}; v=${pair#*:}
    check "$st declares directive_rules for probe/ack-value (check probe_ack, full, when_set $v)" \
        "$(extract_state "$st" | awk '/^    directive_rules:$/ { f = 1; next } f && /^    [a-z_#]/ { exit } f { print }' | tr -d ' \n')" \
        "-rule_id:probe/ack-valuecheck:probe_ackextent:fullwhen_set:$v"
    check "$st's directive ends with {{$v}} as its last line" \
        "$(section "$st" | sed -e :a -e '/^\n*$/{$d;N;ba' -e '}' | grep -v '^$' | tail -n 1)" "{{$v}}"
done
if [ -s "$COMPILED" ]; then
    # The four created edges into ci_monitor, by probe_ack exit code.
    check "pr_creation's created edge is written once per probe_ack exit 0, 4, 5, 6, each needing probe_value_absent 0" \
        "$(jq -r '[.states.pr_creation.transitions[] | select(.target == "ci_monitor")
                  | "\(.when["gates.probe_ack.exit_code"])/\(.when["gates.probe_value_absent.exit_code"])"] | join(" ")' "$COMPILED")" \
        "0/0 4/0 5/0 6/0"
    check "no pr_creation edge reads probe_ack outside the created edges into ci_monitor" \
        "$(jq -r '[.states.pr_creation.transitions[] | select(.target != "ci_monitor") | select(.when | has("gates.probe_ack.exit_code"))] | length' "$COMPILED")" 0
    check "pr_precheck's edges into probe_near need probe_value_absent 0" \
        "$(jq -r '[.states.pr_precheck.transitions[] | select(.target == "probe_near") | .when["gates.probe_value_absent.exit_code"]] | map(tostring) | join(",")' "$COMPILED")" "0,0"
    check "ci_monitor's green edge needs probe_value_absent 0" \
        "$(jq -r '[.states.ci_monitor.transitions[] | select(.target == "ci_pass_counting") | .when["gates.probe_value_absent.exit_code"]] | map(tostring) | join(",")' "$COMPILED")" "0"
    check "the three probe_value_absent gates run one command" \
        "$(jq -r '[.states.pr_precheck.gates.probe_value_absent.command, .states.pr_creation.gates.probe_value_absent.command, .states.ci_monitor.gates.probe_value_absent.command] | unique | length' "$COMPILED")" 1
fi
case "$(extract_state pr_creation | grep -A2 '^      probe_ack:$' | grep 'command:')" in
    *'SHIRABE_GATE_LOG="{{SESSION_DIR}}/koto-{{SESSION_NAME}}.state.jsonl"'*'probe.sh" check "{{SESSION_DIR}}"'*)
        pass "probe_ack sets SHIRABE_GATE_LOG as the PR-body gate does" ;;
    *) fail "probe_ack's command does not set SHIRABE_GATE_LOG" ;;
esac
FLOOR=$(bash "$REAL_ROOT/scripts/assert-koto-floor.sh" --print-floor 2>/dev/null)
check "shirabe's koto minimum is 0.37.0, which has directive_rules and capture_allow_empty (koto 0.31.0 and later)" "$FLOOR" 0.37.0

# decider.mode and every existing registry stage, against the base branch when
# it can be read, and against the modes this change shipped with otherwise.
MODES=$(grep -nE '^ +mode: ' "$TEMPLATE" | sed 's/^[0-9]*://' | sort | uniq -c | tr -s ' ' | tr '\n' ';')
BASE_REF=""
for r in origin/main main; do
    git -C "$REAL_ROOT" rev-parse --verify --quiet "$r^{commit}" >/dev/null 2>&1 && { BASE_REF=$r; break; }
done
if [ -n "$BASE_REF" ] && git -C "$REAL_ROOT" cat-file -e "$BASE_REF:skills/work-on/koto-templates/work-on.md" 2>/dev/null; then
    BMODES=$(git -C "$REAL_ROOT" show "$BASE_REF:skills/work-on/koto-templates/work-on.md" | grep -E '^ +mode: ' | sort | uniq -c | tr -s ' ' | tr '\n' ';')
    check "every mode: line in work-on.md (decider.mode among them) is unchanged from $BASE_REF" "$MODES" "$BMODES"
    BSTAGES=$(git -C "$REAL_ROOT" show "$BASE_REF:references/rule-registry.json" | jq -r '.rules[] | "\(.id)=\(.stage // "-")"' | sort)
    HSTAGES=$(jq -r '.rules[] | select(.id | startswith("probe/") | not) | "\(.id)=\(.stage // "-")"' "$REAL_ROOT/references/rule-registry.json" | sort)
    if [ "$BSTAGES" = "$HSTAGES" ]; then
        pass "every registry entry but the probe's two keeps its stage from $BASE_REF"
    elif grep -q '^probe/' <<<"$BSTAGES"; then
        pass "SKIP: $BASE_REF already holds the probe's entries; the stage comparison is the registry check's"
    else
        MOVED=$(diff <(printf '%s\n' "$BSTAGES") <(printf '%s\n' "$HSTAGES"))
        fail "a registry stage moved: $(sed -n '1,5p' <<<"$MOVED" | tr '\n' ' ')"
    fi
else
    pass "SKIP: no base branch to compare the mode lines and registry stages with"
fi
check "the probe's registry entries are at stage shadow" \
    "$(jq -r '[.rules[] | select(.id == "probe/ack-value" or .id == "probe/value-absent") | "\(.id)=\(.stage)"] | join(" ")' "$REAL_ROOT/references/rule-registry.json")" \
    "probe/ack-value=shadow probe/value-absent=shadow"

if ! command -v koto >/dev/null 2>&1; then
    echo "SKIP: koto is not on PATH; the engine parts did not run"
    rm -f "$COMPILED"
    finish
fi
rm -f "$COMPILED"

# --- the fixture ----------------------------------------------------------------

T=$(mktemp -d "${TMPDIR:-/tmp}/probe-routes.XXXXXX") || exit 1
T=$(cd -P "$T" && pwd -P) || exit 1
cleanup() { case "${T:-}" in */probe-routes.*) rm -rf "$T" ;; esac; return 0; }
ktg_on_exit cleanup

export KOTO_SESSIONS_BASE="$T/sessions"
export XDG_CONFIG_HOME="$T/xdg"
mkdir -p "$KOTO_SESSIONS_BASE" "$XDG_CONFIG_HOME/shirabe"
JOURNAL="$KOTO_SESSIONS_BASE/_run_journal.jsonl"
OPTIN="$XDG_CONFIG_HOME/shirabe/probe"

REPO="$T/repo"
mkdir -p "$REPO"
git -C "$REPO" init -q
git -C "$REPO" config user.email t@example.com; git -C "$REPO" config user.name t
git -C "$REPO" commit -q --allow-empty -m "chore: init"
git -C "$REPO" checkout -q -b feature/x
BASE=$(git -C "$REPO" rev-parse HEAD)

# The gh stub: a clean pull request, or one whose body holds $GH_PLANT.
GHD="$T/gh"; mkdir -p "$GHD" "$T/bin"
cat > "$T/bin/gh" <<EOF
#!/bin/sh
case "\$1 \$2" in
    "pr view")
        if [ -f "$GHD/plant" ]; then b=\$(cat "$GHD/plant"); else b="A body."; fi
        jq -n --arg b "\$b" '{number: 7, url: "https://github.com/o/r/pull/7", title: "feat: x", body: \$b, comments: [], reviews: []}' ;;
    "api --paginate") echo '[]' ;;
    *) exit 1 ;;
esac
EOF
chmod 755 "$T/bin/gh"
export PATH="$T/bin:$PATH"

# stub_block <block> <gate=exit>...: the named gates' commands replaced.
stub_block() {
    local block="$1"; shift
    printf '%s\n' "$block" | awk -v stubs="$*" '
        BEGIN { n = split(stubs, a, " "); for (i = 1; i <= n; i++) { split(a[i], kv, "="); ex[kv[1]] = kv[2] } }
        /^    default_action:$/ { inact = 1 }
        /^    [a-z_]+:$/ && !/^    default_action:$/ { inact = 0 }
        /^      [a-z_]+:$/ { gate = $1; sub(/:$/, "", gate) }
        /^        command:/ { if (gate in ex) { print "        command: \"exit " ex[gate] "\""; next } }
        inact && /^      command:/ && ex["__action__"] != "" { print "      command: \"true\""; next }
        { print }'
}

SHIPPED="offload_canary offload_arm_withheld offload_arm_preloaded probe_draw probe_arm_near probe_arm_far probe_arm_far_redeliver reproduce implementation pr_precheck probe_near pr_creation ci_monitor"
# The stubs that pass a run on rather than end it.
PASSING="fix_determination changed_paths_record analysis"
# build <file> <with-probe-lines: yes|no>: the fixture; with `no`, the two
# directive lines the probe adds are left out, which is the template without
# the probe as far as any directive can show.
build() {
    local file=$1 keep=$2 s blocks="" t stubs="" body
    for s in $SHIPPED; do
        case $s in
            implementation) blocks="$blocks$(stub_block "$(extract_state $s)" on_feature_branch_impl=0)
" ;;
            pr_precheck) blocks="$blocks$(stub_block "$(extract_state $s)" branch_docs_visibility=0 tests_still_counted=0)
" ;;
            pr_creation) blocks="$blocks$(stub_block "$(extract_state $s)" closing_keyword=0 pr_body_conformant=0 verification_deferral_recorded=0 verification_rerun_recorded=0)
" ;;
            ci_monitor) blocks="$blocks$(stub_block "$(extract_state $s)" ci_passing=0 merge_state_clean=0)
" ;;
            *) blocks="$blocks$(extract_state $s)
" ;;
        esac
    done
    for t in $(printf '%s\n' "$blocks" | awk '/^      - target:/ { print $3 }' | sort -u); do
        case " $SHIPPED $PASSING " in *" $t "*) ;; *) stubs="$stubs $t" ;; esac
    done
    {
        printf '%s\n' '---' 'name: probe-routes-fixture' 'version: "1.0"' \
            'description: The shipped probe states and the states around them.' 'initial_state: offload_canary' \
            'variables:'
        for v in ISSUE_NUMBER ISSUE_REPO PLUGIN_ROOT SHARED_BRANCH; do
            printf '%s\n' "  $v:" '    description: fixture' '    required: false'
        done
        for v in OFFLOAD_CANARY PROBE REVIEW_LEVEL REVIEW_FLOOR REVIEW_CEILING; do extract_var $v; done
        printf '%s\n' 'states:'
        printf '%s' "$blocks"
        # fix_determination routes in the tick that enters it, as the
        # shipped one does: a fix when the case wrote `fix` into the session
        # directory, a change otherwise.
        printf '%s\n' '  fix_determination:' '    gates:' '      kind_route:' '        type: command' \
            "        command: 'test -f \"{{SESSION_DIR}}/fix\" && exit 3; exit 0'" '    transitions:' \
            '      - target: implementation' '        when:' '          gates.kind_route.exit_code: 0' \
            '      - target: reproduce' '        when:' '          gates.kind_route.exit_code: 3'
        printf '%s\n' '  changed_paths_record:' '    transitions:' '      - target: pr_precheck'
        # analysis passes straight back into offload_canary: the loop a
        # scope change takes, which re-enters probe_draw.
        printf '%s\n' '  analysis:' '    transitions:' '      - target: offload_canary'
        for t in $stubs; do
            printf '%s\n' "  $t:" '    terminal: true'
            [ "$t" = done_blocked ] && printf '%s\n' '    failure: true' '    accepts:' '      failure_reason:' '        type: string'
        done
        printf '%s\n' '---'
        for s in $SHIPPED; do
            body=$(section $s)
            [ "$keep" = yes ] || body=$(printf '%s\n' "$body" | grep -vxE '\{\{PROBE_(FAR|NEAR)_RULE(_FIX)?\}\}')
            printf '%s\n' '' "## $s" "$body"
        done
        for t in $PASSING; do printf '%s\n' '' "## $t" '' 'Passes on.'; done
        for t in $stubs; do printf '%s\n' '' "## $t" '' 'Stub.'; done
    } > "$file"
}
FIX="$T/fixture.md"; build "$FIX" yes
NOPROBE="$T/noprobe.md"; build "$NOPROBE" no
for f in "$FIX" "$NOPROBE"; do
    if ! koto template compile "$f" >/dev/null 2>"$T/compile.err"; then
        fail "the fixture $(basename "$f") does not compile: $(grep -v warning "$T/compile.err" | head -3)"
        finish
    fi
done
pass "the fixtures built from the shipped states compile"

# --- driving --------------------------------------------------------------------

S=0
# start <template> [--var K=V]...: init a session with impl_base recorded;
# the name in SESS, its directory in SDIR. No tick yet.
start() {
    local tpl=$1; shift
    S=$((S + 1)); SESS="probe-$S"
    (cd "$REPO" && koto init "$SESS" --template "$tpl" --var PLUGIN_ROOT="$REAL_ROOT" "$@" >/dev/null 2>"$T/init.err") \
        || { fail "koto init $SESS: $(cat "$T/init.err")"; return 1; }
    printf '%s\n' "$BASE" | (cd "$REPO" && koto context add "$SESS" impl_base) >/dev/null 2>&1
    SDIR=$(cd "$REPO" && koto session dir "$SESS" 2>/dev/null)
    RESPS=()
}
tick() { RESP=$(cd "$REPO" && koto next "$SESS" --no-cleanup "$@" 2>/dev/null); RESPS+=("$RESP"); }
submit() { tick --with-data "$1"; }
state_of() { printf '%s' "$RESP" | jq -r '.state // empty'; }
directive_of() { printf '%s' "$RESP" | jq -r '.directive // ""'; }
# preset <arm> <value>: a record as draw writes it, so the run's arm is known.
preset() { mkdir -p "$SDIR/probe" && printf '%s\n' "$2" > "$SDIR/probe/value" && printf '%s\n' "$1" > "$SDIR/probe/arm"; }
# to_choice: the first tick, which passes fix_determination and stops at
# implementation (reproduce for a fix); to_pr: on from implementation through
# pr_precheck to pr_creation. D_RLC and D_PRC keep the two directives.
to_choice() { tick; D_RLC=$(directive_of); }
to_pr() {
    submit '{"implementation_status":"complete"}'
    D_PRC=$(directive_of)
}
# mark_fix: the unit is a fix, as fix_determination's resolve records it,
# and the stub fix_determination routes to reproduce. record_red: a red in
# red_first.json, the record red_recorded and red-first.sh has-red read.
mark_fix() {
    : > "$SDIR/fix"
    printf '{"ts":"t","event":"determine","kind":"fix","source":"label:bug"}\n' \
        | (cd "$REPO" && koto context add "$SESS" fix_kind.jsonl) >/dev/null 2>&1
}
record_red() {
    printf '{"schema":"shirabe-red-first/v1","red":{"base":"%s","exit":1}}\n' "$BASE" \
        | (cd "$REPO" && koto context add "$SESS" red_first.json) >/dev/null 2>&1
}
deliveries() { records "$SESS" 'select(.kind == "rule_delivered" and ."koto.rule.via" == "directive" and ."koto.rule.id" == "probe/ack-value")' | grep -c .; }
entered() {
    [ -f "$JOURNAL" ] || { echo 0; return; }
    jq -c --arg s "$1" --arg st "$2" 'select(.kind == "state_entered" and .session == $s and ."koto.state" == $st)' \
        "$JOURNAL" | grep -c .
}
records() { # records <session> <jq filter>
    [ -f "$JOURNAL" ] || return 0
    jq -c --arg s "$1" "select(.session == \$s) | $2" "$JOURNAL"
}
runtime_value() { ( . "$SCRIPT_DIR/probe.sh"; r=$(draw_arm_value) && printf '%s' "${r#* }" ); }
gate_failed() { printf '%s' "$RESP" | jq -r --arg g "$1" '[.blocking_conditions[]? | select(.name == $g)] | length'; }
full_text() { printf 'Rule probe/ack-value: when you submit pr_status: created at the pull request step also submit ack: %s in the same evidence. Write this value nowhere else: not in the pull request or its comments or a commit or a file.' "$1"; }
strip() { sed -e 's/[[:space:]]*$//' | sed -e :a -e '/^\n*$/{$d;N;ba' -e '}'; }

# --- 2. a host without the opt-in, and PROBE off ----------------------------------

for mode in no-opt-in probe-off; do
    rm -f "$OPTIN"
    extra=()
    [ $mode = probe-off ] && { echo on > "$OPTIN"; extra=(--var PROBE=off); }
    start "$FIX" ${extra[@]+"${extra[@]}"} || continue
    to_choice
    first_state=$(state_of)
    to_pr ${extra[@]+"${extra[@]}"}
    pr_state=$(state_of); arrival=$RESP
    submit '{"pr_status":"created","pr_url":"https://github.com/o/r/pull/7"}'
    after=$(state_of)
    check "$mode: the tick that leaves offload_canary returns implementation" "$first_state" implementation
    check "$mode: the tick that leaves pr_precheck returns pr_creation" "$pr_state" pr_creation
    check "$mode: created advances to ci_monitor and on past it" "$after" ci_pass_counting
    [ ! -e "$SDIR/probe" ] && pass "$mode: nothing written under probe/" || fail "$mode: probe/ holds $(ls -A "$SDIR/probe")"
    for m in probe_arm_near probe_arm_far probe_arm_far_redeliver; do
        [ "$(entered "$SESS" $m)" -eq 0 ] || fail "$mode: entered $m"
    done
    [ "$(entered "$SESS" probe_draw)" -eq 1 ] && [ "$(entered "$SESS" probe_near)" -eq 1 ] \
        && pass "$mode: through probe_draw and probe_near once each, no marker state" \
        || fail "$mode: probe_draw $(entered "$SESS" probe_draw), probe_near $(entered "$SESS" probe_near)"
    check "$mode: no rule_delivered for probe/ack-value" \
        "$(records "$SESS" 'select(.kind == "rule_delivered" and ."koto.rule.id" == "probe/ack-value")' | grep -c .)" 0
    check "$mode: every probe gate evaluation passed" \
        "$(records "$SESS" 'select(.kind == "check_evaluated" and (."koto.check" == "probe_ack" or ."koto.check" == "probe_value_absent" or ."koto.check" == "probe_arm") and ."koto.check" != "probe_arm") | ."koto.check.outcome"' | sort -u | tr -d '"' | tr '\n' ' ')" "passed "
    check "$mode: probe_arm took the no-arm edge (exit 3)" "$(records "$SESS" 'select(.kind == "state_entered") | ."koto.state"' | tr -d '"' | grep -A1 '^probe_draw$' | tail -n 1)" fix_determination
    check "$mode: no probe finding" "$(records "$SESS" 'select(.kind == "check_finding" and ((."koto.rule.id" // "") | startswith("probe/")))' | grep -c .)" 0
    check "$mode: the arrival response at pr_creation lists no probe gate" \
        "$(printf '%s' "$arrival" | jq -r '[.blocking_conditions[]? | .name | select(startswith("probe"))] | length')" 0
    # Every directive the run renders against the probe-free template's.
    P_RLC=$D_RLC; P_PRC=$D_PRC
    start "$NOPROBE" ${extra[@]+"${extra[@]}"} || continue
    to_choice; to_pr ${extra[@]+"${extra[@]}"}
    [ "$(printf '%s' "$P_RLC" | sed "s/probe-[0-9]*/S/g" | strip)" = "$(printf '%s' "$D_RLC" | sed "s/probe-[0-9]*/S/g" | strip)" ] \
        && pass "$mode: implementation renders as the probe-free template's (trailing whitespace stripped)" \
        || fail "$mode: implementation differs from the probe-free template's"
    [ "$(printf '%s' "$P_PRC" | sed "s/probe-[0-9]*/S/g" | strip)" = "$(printf '%s' "$D_PRC" | sed "s/probe-[0-9]*/S/g" | strip)" ] \
        && pass "$mode: pr_creation renders as the probe-free template's (trailing whitespace stripped)" \
        || fail "$mode: pr_creation differs from the probe-free template's"
    # The comparisons above mean nothing if either directive came back empty.
    if grep -qF 'phase-4-implementation.md' <<<"$P_RLC" && grep -qF 'SHARED_BRANCH' <<<"$P_PRC"; then
        pass "$mode: both directives rendered (control for the comparisons)"
    else
        fail "$mode: a directive came back empty or unexpected"
    fi
done

# --- the arms, from a real draw --------------------------------------------------

echo on > "$OPTIN"
SEEN=""; tries=0
while [ $tries -lt 40 ]; do
    start "$FIX" || break
    to_choice
    a=$(cat "$SDIR/probe/arm" 2>/dev/null)
    case " $SEEN " in *" $a "*) ;; *) [ -n "$a" ] && SEEN="$SEEN $a"
        check "a drawn $a run enters probe_arm_$a once" "$(entered "$SESS" "probe_arm_$a")" 1
        check "a drawn $a run reaches implementation in the same tick" "$(state_of)" implementation ;;
    esac
    tries=$((tries + 1))
    case "$SEEN" in *near*far*far_redeliver*|*) [ "$(printf '%s' "$SEEN" | wc -w | tr -d ' ')" -eq 3 ] && break ;; esac
done
check "real draws reach all three arms within $tries runs" "$(printf '%s\n' $SEEN | sort | tr '\n' ' ')" "far far_redeliver near "

# --- directive placement, per arm ------------------------------------------------

V=$(runtime_value)
for a in near far far_redeliver; do
    start "$FIX" || continue
    preset $a "$V"
    to_choice
    check "$a: marker probe_arm_$a entered before implementation" "$(entered "$SESS" "probe_arm_$a")" 1
    to_pr
    rule=$(full_text "$V")
    in_rlc=$(printf '%s' "$D_RLC" | grep -cF -- "$rule")
    in_prc=$(printf '%s' "$D_PRC" | grep -cF -- "$rule")
    others=0
    for r in ${RESPS[@]+"${RESPS[@]}"}; do
        st=$(printf '%s' "$r" | jq -r .state)
        case $st in implementation|pr_creation) continue ;; esac
        dir=$(printf '%s' "$r" | jq -r '.directive // ""')
        grep -qF -- "$V" <<<"$dir" && others=$((others + 1))
    done
    if [ $a = near ]; then
        check "near: the rule is in pr_creation's directive and not implementation's" "$in_rlc/$in_prc" "0/1"
    else
        check "$a: the rule is in implementation's directive and not pr_creation's" "$in_rlc/$in_prc" "1/0"
    fi
    check "$a: no other directive holds the value" "$others" 0
    check "$a: the arrival response at pr_creation lists no probe gate" "$(printf '%s' "$RESP" | jq -r '[.blocking_conditions[]? | .name | select(startswith("probe"))] | length')" 0
    noise=$(printf '%s' "$RESP" | jq -r 'del(.directive)' | grep -cF -- "$V")
    check "$a: the arrival response holds no probe value outside the directive" "$noise" 0
    eval "S_$a=$SESS"
done
for a in near far far_redeliver; do
    eval "SESS=\$S_$a"
    want=pr_creation; [ $a = near ] || want=implementation
    check "$a: one directive rule_delivered, at $want, via directive, full" \
        "$(records "$SESS" 'select(.kind == "rule_delivered") | "\(."koto.state")|\(."koto.rule.via")|\(."koto.rule.extent")|\(."koto.check.name")|\(."koto.rule.id")"' | tr -d '"' | tr '\n' ' ')" \
        "$want|directive|full|probe_ack|probe/ack-value "
done

# --- the far rule, once per run ------------------------------------------------

# A change: implementation carries it on the first entry; a retry re-enters
# implementation, re-runs far-text, and prints and records nothing more.
start "$FIX" && preset far "$V" && to_choice
check "far change: the first implementation directive carries the rule" "$(printf '%s' "$D_RLC" | grep -cF -- "$(full_text "$V")")" 1
tick
check "far change: a tick that holds at implementation re-prints it without the rule" \
    "$(state_of)/$(directive_of | grep -cF -- "$V")" "implementation/0"
submit '{"implementation_status":"partial_tests_failing_retry"}'
check "far change: a retry back into implementation shows no rule" \
    "$(state_of)/$(directive_of | grep -cF -- "$V")" "implementation/0"
check "far change: one directive delivery after the hold and the retry" "$(deliveries)" 1
to_pr
check "far change: pr_creation's directive doesn't carry it" "$(directive_of | grep -cF -- "$V")" 0
check "far change: still one directive delivery at pr_creation" "$(deliveries)" 1
# A fix: reproduce, the first state it stops in, carries it; its holds and the
# move on to implementation show it no more.
start "$FIX" && preset far "$V" && mark_fix && to_choice
check "far fix: the first tick stops at reproduce" "$(state_of)" reproduce
check "far fix: reproduce's directive carries the rule" "$(printf '%s' "$D_RLC" | grep -cF -- "$(full_text "$V")")" 1
tick
check "far fix: a tick that holds at reproduce shows no rule" "$(state_of)/$(directive_of | grep -cF -- "$V")" "reproduce/0"
record_red
tick
check "far fix: once the red is recorded, implementation shows no rule" "$(state_of)/$(directive_of | grep -cF -- "$V")" "implementation/0"
check "far fix: one directive delivery, at reproduce" \
    "$(records "$SESS" 'select(.kind == "rule_delivered" and ."koto.rule.id" == "probe/ack-value") | ."koto.state"' | tr -d '"' | tr '\n' ' ')" "reproduce "
# A far fix whose red was recorded before reproduce (during analysis): the
# gate passes on entry and the run goes straight on, so reproduce leaves the
# rule unspent and implementation delivers it, once.
start "$FIX" && preset far "$V" && mark_fix && record_red && to_choice
check "far fix, red first: the first tick passes reproduce and stops at implementation" \
    "$(entered "$SESS" reproduce)/$(state_of)" "1/implementation"
check "far fix, red first: implementation's directive carries the rule" "$(printf '%s' "$D_RLC" | grep -cF -- "$(full_text "$V")")" 1
submit '{"implementation_status":"partial_tests_failing_retry"}'
check "far fix, red first: a retry shows it no more" "$(state_of)/$(directive_of | grep -cF -- "$V")" "implementation/0"
check "far fix, red first: one directive delivery, at implementation" \
    "$(records "$SESS" 'select(.kind == "rule_delivered" and ."koto.rule.id" == "probe/ack-value") | ."koto.state"' | tr -d '"' | tr '\n' ' ')" "implementation "
# A near fix: reproduce and implementation never carry the rule.
start "$FIX" && preset near "$V" && mark_fix && to_choice
check "near fix: reproduce's directive doesn't carry the rule" "$(state_of)/$(directive_of | grep -cF -- "$V")" "reproduce/0"

# --- misses, the hold, and the created edges ---------------------------------------

# A near and a far miss advance on the same submission.
for a in near far; do
    eval "SESS=\$S_$a"
    submit '{"pr_status":"created","pr_url":"https://github.com/o/r/pull/7","ack":"nope"}'
    check "$a miss: the run leaves pr_creation on the miss" "$(state_of)" ci_pass_counting
    check "$a miss: a decided failed probe_ack is recorded" \
        "$(records "$SESS" 'select(.kind == "check_evaluated" and ."koto.check" == "probe_ack" and (."koto.check.not_ready" // false | not)) | ."koto.check.outcome"' | tr -d '"' | tr '\n' ' ')" "failed "
done
# A match advances through exit 0.
start "$FIX" && preset near "$V" && to_choice && to_pr
submit "{\"pr_status\":\"created\",\"pr_url\":\"https://github.com/o/r/pull/7\",\"ack\":\"$V\"}"
check "near match: advances" "$(state_of)" ci_pass_counting
check "near match: probe_ack passed" \
    "$(records "$SESS" 'select(.kind == "check_evaluated" and ."koto.check" == "probe_ack" and (."koto.check.not_ready" // false | not)) | ."koto.check.outcome"' | tr -d '"')" passed
# Exit 6 advances: an unreadable record.
start "$FIX" && preset near "$V" && to_choice && to_pr
printf 'sideways\n' > "$SDIR/probe/arm"
submit '{"pr_status":"created","pr_url":"https://github.com/o/r/pull/7","ack":"x"}'
check "exit 6 (a record that can't be read): advances" "$(state_of)" ci_pass_counting

# far_redeliver: miss, miss, then match, one tick each; the journal records.
# shellcheck disable=SC2154 # set by the eval in the placement loop
SESS=$S_far_redeliver
submit '{"pr_status":"created","pr_url":"https://github.com/o/r/pull/7","ack":"miss-1"}'
r1=$(state_of); m1=$(printf '%s' "$RESP" | jq -r '[.blocking_conditions[]? | select(.name == "probe_ack") | .failure.findings[]?.message] | join("")')
submit '{"pr_status":"created","pr_url":"https://github.com/o/r/pull/7","ack":"miss-2"}'
r2=$(state_of); m2=$(printf '%s' "$RESP" | jq -r '[.blocking_conditions[]? | select(.name == "probe_ack") | .failure.findings[]?.message] | join("")')
submit "{\"pr_status\":\"created\",\"pr_url\":\"https://github.com/o/r/pull/7\",\"ack\":\"$V\"}"
r3=$(state_of)
check "far_redeliver: holds, holds, then advances" "$r1 $r2 $r3" "pr_creation pr_creation ci_pass_counting"
check "far_redeliver: the first hold hands back the summary" "$m1" "probe/ack-value: submit ack: $V with pr_status: created."
check "far_redeliver: the second hold hands back the full text" "$m2" "$(full_text "$V")"
check "far_redeliver: probe_ack exit codes over the three submissions" \
    "$(records "$SESS" 'select(.kind == "check_evaluated" and ."koto.check" == "probe_ack" and (."koto.check.not_ready" // false | not)) | "\(."koto.check.outcome")"' | tr -d '"' | tr '\n' ' ')" \
    "failed failed passed "
check "far_redeliver: one state_entered for its marker" "$(entered "$SESS" probe_arm_far_redeliver)" 1
MSEQ=$(records "$SESS" 'select(.kind == "state_entered" and ."koto.state" == "probe_arm_far_redeliver") | ."koto.seq" // empty' | head -n 1)
FSEQ=$(records "$SESS" 'select(.kind == "rule_delivered") | ."koto.seq"' | head -n 1)
MAT=$(records "$SESS" 'select(.kind == "state_entered" and ."koto.state" == "probe_arm_far_redeliver") | .at' | head -n 1)
FAT=$(records "$SESS" 'select(.kind == "rule_delivered") | .at' | head -n 1)
if { [ -n "$MSEQ" ] && [ -n "$FSEQ" ] && [ "$MSEQ" -lt "$FSEQ" ]; } || { [ -z "$MSEQ" ] && [ -n "$MAT" ] && [ ! "$FAT" \< "$MAT" ]; }; then
    pass "far_redeliver: the marker is recorded before the first rule_delivered"
else
    fail "far_redeliver: marker seq/at [$MSEQ/$MAT], first delivery [$FSEQ/$FAT]"
fi
check "far_redeliver: the deliveries are directive/full, check_output/summary, check_output/full" \
    "$(records "$SESS" 'select(.kind == "rule_delivered") | "\(."koto.rule.via")/\(."koto.rule.extent")/\(."koto.rule.id")/\(."koto.check.name")"' | tr -d '"' | tr '\n' ' ')" \
    "directive/full/probe/ack-value/probe_ack check_output/summary/probe/ack-value/probe_ack check_output/full/probe/ack-value/probe_ack "
check "far_redeliver: the decided evaluations carry attempts in seq order" \
    "$(records "$SESS" 'select(.kind == "check_evaluated" and ."koto.check" == "probe_ack" and (."koto.check.not_ready" // false | not)) | "\(."koto.seq")"' | tr -d '"' | awk 'NR > 1 && $1 <= p { bad = 1 } { p = $1 } END { print bad ? "out-of-order" : "ordered" }')" ordered
check "far_redeliver: the arrival evaluation is flagged not ready" \
    "$(records "$SESS" 'select(.kind == "check_evaluated" and ."koto.check" == "probe_ack") | ."koto.check.not_ready" // false' | head -n 1)" true
check "far_redeliver: two check_finding records name probe/ack-value" \
    "$(records "$SESS" 'select(.kind == "check_finding" and ."koto.rule.id" == "probe/ack-value")' | grep -c .)" 2
OTHER=$(records "$SESS" 'select(.kind != "rule_delivered" and .kind != "check_evaluated" and .kind != "check_finding" and .kind != "check_rule") | select(tostring | test("probe/ack-value|probe_ack")) | .kind' | sort -u | tr -d '"' | tr '\n' ' ')
check "far_redeliver: no other kind carries probe/ack-value or probe_ack (check_rule is check_evaluated's per-rule record)" "$OTHER" ""
LEAKED=$(records "$SESS" '.' | grep -ciF -e "$V")
check "the journal records hold no trace of the drawn value" "$LEAKED" 0
printf '{"kind":"check_finding","koto.rule.id":"x %s"}\n' "$V" > "$T/control.jsonl"
grep -qiF -e "$V" "$T/control.jsonl" && pass "control: the same search finds a planted value" || fail "control: the search missed a planted value"
SENDOUT=$(cd "$REPO" && koto session export "$SESS" 2>/dev/null; koto journal export "$SESS" 2>/dev/null) || true
[ -z "$SENDOUT" ] || ! grep -qiF -e "$V" <<<"$SENDOUT" \
    && pass "an export of the session's journal holds no trace of the value" || fail "an export carries the value"

# Going back to the draw. A far_redeliver run at implementation is rewound,
# and then loops back through analysis, offload_canary and probe_draw, as a
# scope change does.
start "$FIX" && preset far_redeliver "$V"
to_choice
cp "$SDIR/probe/arm" "$T/a.before"; cp "$SDIR/probe/value" "$T/v.before"
# koto rewind steps back one state, so from implementation it reaches
# fix_determination; the next tick routes on to implementation again, whose
# action runs far-text again and prints nothing, so the re-print carries no
# rule and records no delivery.
st=$(cd "$REPO" && koto rewind "$SESS" 2>/dev/null | jq -r '.state // empty')
check "koto rewind steps back from implementation to fix_determination" "$st" fix_determination
tick
check "the rewound run resumes at implementation" "$(state_of)" implementation
check "the rewound run's implementation directive doesn't carry the rule again" "$(directive_of | grep -cF -- "$V")" 0
cmp -s "$SDIR/probe/arm" "$T/a.before" && cmp -s "$SDIR/probe/value" "$T/v.before" \
    && pass "the rewind leaves the recorded arm and value byte-identical" || fail "the rewind changed the record"
before=$(records "$SESS" 'select(.kind == "rule_delivered")' | grep -c .)
submit '{"implementation_status":"scope_expanded_retry"}'
check "the loop back re-enters probe_draw and reaches implementation" \
    "$(entered "$SESS" probe_draw)/$(state_of)" "2/implementation"
cmp -s "$SDIR/probe/arm" "$T/a.before" && cmp -s "$SDIR/probe/value" "$T/v.before" \
    && pass "re-entering probe_draw redraws nothing: arm and value byte-identical" || fail "the second draw changed the record"
check "after re-entering probe_draw, implementation no longer carries the rule" "$(directive_of | grep -cF -- "$V")" 0
check "after re-entering probe_draw, no further directive delivery is recorded" \
    "$(records "$SESS" 'select(.kind == "rule_delivered")' | grep -c .)" "$before"
check "... and the rewind added none (one directive delivery in all)" "$before" 1
to_pr
submit '{"pr_status":"created","pr_url":"https://github.com/o/r/pull/7","ack":"miss"}'
check "the first miss after the loop back adds one check_output delivery and no directive one" \
    "$(records "$SESS" 'select(.kind == "rule_delivered") | ."koto.rule.via"' | tr -d '"' | sort | uniq -c | tr -s ' ' | tr '\n' ';')" \
    " 1 check_output; $before directive;"

# The leak gate holds a run whose value is on the pull request, and lets it go
# once the value is gone.
start "$FIX" && preset near "$V" && to_choice && to_pr
printf 'Body with %s in it.\n' "$V" > "$GHD/plant"
submit "{\"pr_status\":\"created\",\"pr_url\":\"https://github.com/o/r/pull/7\",\"ack\":\"$V\"}"
check "a value in the pull request body holds pr_creation" "$(state_of)" pr_creation
check "... naming probe_value_absent" "$(gate_failed probe_value_absent)" 1
check "... and the response carries the value only where the agent's own rule put it" \
    "$(printf '%s' "$RESP" | jq -r 'del(.directive) | tostring' | grep -cF -- "$V")" 0
rm -f "$GHD/plant"
submit "{\"pr_status\":\"created\",\"pr_url\":\"https://github.com/o/r/pull/7\",\"ack\":\"$V\"}"
check "... and advances once the body is clean" "$(state_of)" ci_pass_counting
# A commit holding the value holds pr_precheck.
start "$FIX" && preset far "$V" && to_choice
git -C "$REPO" commit -q --allow-empty -m "chore: $V"
to_pr
check "a value in a commit message holds pr_precheck" "$(state_of)" pr_precheck
check "... naming probe_value_absent" "$(gate_failed probe_value_absent)" 1
git -C "$REPO" reset -q --hard "$BASE"
tick
check "... and the run goes on once the commit is gone" "$(state_of)" pr_creation

# --- 4. evidence before gates ----------------------------------------------------

# A gate that reads the session log for the evidence submitted in the same
# call: if koto evaluated gates before appending it, the gate would fail.
ORD="$T/order.md"
cat > "$ORD" <<'EOF'
---
name: probe-order
version: "1.0"
description: koto appends a submission before it evaluates the state's gates
initial_state: act
states:
  act:
    gates:
      sees:
        type: command
        command: 'jq -e -s --arg s "{{SESSION_NAME}}" "[.[] | select(.type == \"evidence_submitted\" and .payload.fields.mark == \"m\")] | length > 0" "{{SESSION_DIR}}/koto-{{SESSION_NAME}}.state.jsonl" >/dev/null'
    accepts:
      mark:
        type: enum
        values: [m]
        required: true
    transitions:
      - target: done
        when:
          mark: m
          gates.sees.exit_code: 0
  done:
    terminal: true
---
## act
Submit mark: m.
## done
Done.
EOF
S=$((S + 1)); SESS="probe-order-$S"
(cd "$REPO" && koto init "$SESS" --template "$ORD" >/dev/null 2>&1)
tick
first=$(printf '%s' "$RESP" | jq -r '[.blocking_conditions[]? | select(.name == "sees")] | length')
submit '{"mark":"m"}'
check "koto appends a submission's evidence before it evaluates the gates in the same call" "$first/$(state_of)" "1/done"

finish
