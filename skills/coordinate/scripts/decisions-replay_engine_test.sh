#!/usr/bin/env bash
# decisions-replay_engine_test.sh -- the decision flow's acceptance tests, in
# real koto.
#
# The skeleton template holds the decision states and the states whose edges
# they change (`wait`, `report_facts`), cut from STATES_FROM; every state they
# route to that isn't under test is a terminal stand-in, or a pass-through
# (take_report, pick_facts, classify_report) so one run can take several
# arrivals. coord-log.sh, phrasing-lib.sh and koto are real.
#
# STAND-INS. Until the coordinate-decisions plan's Issue 10, STATES_FROM is
# testdata/decisions/stand-in-states.yaml and the scripts in STAND_INS come
# from testdata/decisions/stand-ins/, which model the Decisions section by the
# DESIGN's rules. Issue 10 points STATES_FROM at coordinate.md, empties
# STAND_INS, deletes both, and the cases below run against the real scripts.
#
# Proves:
#   1. the niwa#330 replay: a settled entry whose source is the worker, the
#      dispatcher's mixed check result recorded as evidence on it, and the
#      worker's "please decide whether to ship" in a report. decision_verdict
#      is entered before any escalation, withdrawal or reply is rendered, no
#      escalation is rendered, and no table read during the run holds a
#      decision row without a recommendation and a reason. (The redirect is
#      rendered before the take by rule, asks no one anything, and is outside
#      the first check.)
#   2. the same replay against a template whose wait evidence edge goes
#      straight to escalate fails that check;
#   3. three levels (a person, a workspace coordinator W, a roadmap
#      coordinator R reporting to W): R's escalation opens a proposed entry at
#      W with R's entry as its source; the person's answer settles W's entry,
#      W's reply settles R's naming the final decider; a withdrawal from R
#      reopens W's entry, and when W settles it nothing goes back down.
#
# Needs koto, jq and git; SKIPs (exit 0) without koto, which
# run-tests.sh --engine turns into a failure.
# Usage: bash skills/coordinate/scripts/decisions-replay_engine_test.sh
set -uo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
for bin in koto jq git; do
    command -v "$bin" >/dev/null 2>&1 || { echo "SKIP: $bin not on PATH -- the engine cases did not run"; exit 0; }
done

STATES_FROM="$HERE/testdata/decisions/stand-in-states.yaml"
STAND_INS="coord-verdict.sh decision-next.sh decision-render.sh report-questions.sh record-decision.sh report-facts.sh model-lib.sh"

T=$(mktemp -d "${TMPDIR:-/tmp}/decisions-replay.XXXXXX")
T=$(cd -P "$T" && pwd -P)
if [ -n "${KEEP_T-}" ]; then echo "keeping $T"; else trap 'rm -rf "$T"' EXIT; fi
export HOME="$T/home" GIT_CEILING_DIRECTORIES="$T"
mkdir -p "$HOME"
W="$T/ws"
mkdir -p "$W"
cd "$W" || exit 1

PASS=0
FAIL=0
pass() { PASS=$((PASS + 1)); printf 'ok   %s\n' "$1"; }
fail() { FAIL=$((FAIL + 1)); printf 'FAIL %s\n     %s\n' "$1" "${2-}"; }
eq()   { if [ "$2" = "$3" ]; then pass "$1"; else fail "$1" "want [$2], got [$3]"; fi; }
finish() { echo; echo "decisions-replay: $PASS passed, $FAIL failed"; [ "$FAIL" -eq 0 ]; exit $?; }

# --- the plugin tree ---------------------------------------------------------------------

PR="$T/plugin"
S="$PR/skills/coordinate/scripts"
mkdir -p "$S" "$PR/skills/coordinate/references" "$PR/skills/coordinate/koto-templates"
cp "$HERE/coord-log.sh" "$HERE/phrasing-lib.sh" "$S/"
cp "$HERE/coord-verdict.sh" "$S/coord-verdict-shipped.sh"
cp "$HERE/../references/decision-phrasings.tsv" "$PR/skills/coordinate/references/"
for f in $STAND_INS; do cp "$HERE/testdata/decisions/stand-ins/$f" "$S/$f"; done
chmod +x "$S"/*.sh
export DEC_ST="$T/dec"
mkdir -p "$DEC_ST"

# --- the skeleton template ---------------------------------------------------------------

UNDER="wait report_facts report_questions decision_next decision_carry decision_take decision_verdict
decision_open decision_raise decision_answer decision_evidence escalate escalate_send decision_withdraw
decision_withdraw_send decision_reply decision_reply_send decision_redirect decision_redirect_send"
PASSTHROUGH="take_report pick_facts classify_report"
TERMINAL="record_conflict rebrief surface decision_apply leg_pick quiet_check merged_facts teardown rotation_close done_stopped"

# block <state>: the state's YAML block, from its `  <state>:` line to the next state's.
block() {
    awk -v s="  $1:" '
        $0 == s { on = 1; print; next }
        on && /^  [a-z_]+:$/ { exit }
        on && /^---$/ { exit }
        on { print }
    ' "$STATES_FROM"
}
# skeleton <file> [sed program for the wait block]
skeleton() {
    {
        cat <<'EOF'
---
name: coordinate
version: "1.0"
description: the decision states, for decisions-replay_engine_test.sh
initial_state: entry
variables:
  PLUGIN_ROOT:
    description: plugin root
    required: true
  DISCIPLINE:
    description: discipline
    default: ""
  REPORTS_TO:
    description: the coordinator this run reports to; empty for a person
    default: ""
states:
  entry:
    accepts:
      go:
        type: enum
        values: [wait]
        required: true
    transitions:
      - target: wait
        when:
          go: wait
EOF
        for st in $UNDER; do
            if [ "$st" = wait ] && [ -n "${2-}" ]; then block wait | sed "$2"; else block "$st"; fi
            echo
        done
        for st in $PASSTHROUGH; do
            next=wait
            [ "$st" = take_report ] && next=report_facts
            printf '  %s:\n    accepts:\n      go:\n        type: enum\n        values: [go]\n        required: true\n    transitions:\n      - target: %s\n        when:\n          go: go\n\n' "$st" "$next"
        done
        for st in $TERMINAL; do printf '  %s:\n    terminal: true\n\n' "$st"; done
        echo '---'
        for st in entry $UNDER $PASSTHROUGH $TERMINAL; do printf '## %s\nStand-in.\n\n' "$st"; done
    } > "$1"
}
TPL="$PR/skills/coordinate/koto-templates/coordinate.md"
skeleton "$TPL"
koto template compile "$TPL" >"$T/compile.err" 2>&1 || { fail "the skeleton compiles" "$(cat "$T/compile.err")"; finish; }
pass "the skeleton compiles"
# The variant: wait's evidence edge goes straight to escalate.
VAR="$T/variant/coordinate.md"
mkdir -p "$T/variant"
skeleton "$VAR" '/^      - target: decision_evidence$/s/decision_evidence/escalate/'
awk '/^  wait:$/,/^  report_facts:$/' "$VAR" | grep -q 'target: decision_evidence' && fail "the variant rewires the evidence edge" "still routes to decision_evidence"
koto template compile "$VAR" >"$T/compile.err" 2>&1 || { fail "the variant compiles" "$(cat "$T/compile.err")"; finish; }
pass "the variant compiles, its evidence edge going to escalate"

# --- the driver --------------------------------------------------------------------------

# start <session> <template> [reports-to]: a fresh session at wait.
start() {
    koto init "$1" --template "$2" --var PLUGIN_ROOT="$PR" --var REPORTS_TO="${3-}" >/dev/null 2>"$T/init.err" ||
        { fail "session $1 starts" "$(cat "$T/init.err")"; return 1; }
    koto next "$1" --no-cleanup --with-data '{"go":"wait"}' >/dev/null 2>&1
}
tick() { local s=$1; shift; koto next "$s" --no-cleanup "$@" > "$T/next.json" 2>&1; }
at() { koto status "$1" 2>/dev/null | jq -r '.current_state // "gone"'; }
model() { jq -c "$2" "$DEC_ST/$1.json"; }
seed() { printf '%s\n' "$2" > "$DEC_ST/$1.json"; }
cur() { jq -r '.current' "$DEC_ST/$1.json"; }
rd() { local s=$1; shift; bash "$S/record-decision.sh" --session "$s" "$@"; }
# visits <session>: the states entered, in order, one per line.
visits() {
    jq -r 'select(.type == "transitioned" or .type == "directed_transition") | .payload.to' \
        "$(koto session dir "$1")/koto-$1.state.jsonl"
}

# The table a person would read, from the model: every entry escalated to a
# person is a decision row, which needs its recommendation and reason. The
# driver reads it after every step; one bad read marks the session.
table_check() {
    jq -e 'all(.entries[] | select(.state == "escalated" and .target == "a person"); .rec != "" and .reason != "")' \
        "$DEC_ST/$1.json" >/dev/null 2>&1 || : > "$DEC_ST/$1.bad-table"
}

# verdict_for <session> <n>: the verdict the scenario's coordinator makes, as
# `settle <outcome>` or `escalate <rec>|<reason>`. Each scenario defines it.
verdict_for() { echo "settle default"; }

# PEND_*: what an arrival carries into the agent state it lands on.
PEND_N="" PEND_SRC="" PEND_TEXT="" PEND_ROUND="" PEND_FINAL="" PEND_Q="" PEND_OPTS=""

# drive <session>: answer each agent state as the coordinator does, until the
# run is back at a hub or a terminal. Rendered messages are kept in the
# session's outbox, "$DEC_ST/<session>.sent", one JSON line each.
drive() {
    local s=$1 st i=0 n v
    while [ $i -lt 60 ]; do
        i=$((i + 1))
        table_check "$s"
        st=$(at "$s")
        case "$st" in
            wait|pick_facts|classify_report|gone) return 0 ;;
            record_conflict|rebrief|surface|decision_apply|leg_pick|quiet_check|merged_facts|teardown|rotation_close|done_stopped) return 0 ;;
            take_report) tick "$s" --with-data '{"go":"go"}' ;;
            decision_take) rd "$s" --take "$(cur "$s")"; tick "$s" --with-data '{"taken":"taken"}' ;;
            decision_verdict)
                n=$(cur "$s"); v=$(verdict_for "$s" "$n")
                case "$v" in
                    settle\ *) rd "$s" --settle "$n" "${v#settle }"; tick "$s" --with-data '{"verdict":"settle"}' ;;
                    escalate\ *) v=${v#escalate }; rd "$s" --escalate "$n" "${v%%|*}" "${v#*|}"; tick "$s" --with-data '{"verdict":"escalate"}' ;;
                esac ;;
            decision_open) rd "$s" --open-from-report; tick "$s" --with-data '{"opened":"opened"}' ;;
            decision_raise) rd "$s" --open "$PEND_Q" $PEND_OPTS; tick "$s" --with-data '{"raised":"raised"}' ;;
            decision_evidence) rd "$s" --evidence "$PEND_N" "$PEND_SRC" "$PEND_TEXT"; tick "$s" --with-data '{"recorded":"recorded"}' ;;
            decision_answer) rd "$s" --answer "$PEND_N" "$PEND_ROUND" "$PEND_TEXT" ${PEND_FINAL:+"$PEND_FINAL"}; tick "$s" --with-data '{"answered":"recorded"}' ;;
            escalate_send|decision_withdraw_send|decision_reply_send|decision_redirect_send)
                jq -c --rawfile t "$DEC_ST/$s.message" '. + {text: $t}' "$DEC_ST/$s.message.json" >> "$DEC_ST/$s.sent"
                rd "$s" --sent "$(jq -r .kind "$DEC_ST/$s.message.json")" "$(jq -r .n "$DEC_ST/$s.message.json")"
                tick "$s" --with-data '{"sent":"sent"}' ;;
            *) tick "$s" ;;
        esac
    done
    fail "drive $s reaches a hub" "still at $(at "$s") after $i steps"
}
# The arrivals, each named at wait the way the coordinator names them.
arrive_report() { # arrive_report <session> <holding or ""> <text>
    printf '%s' "$2" > "$DEC_ST/$1.holding"
    tick "$1" --with-data "$(jq -nc --arg r "$3" '{event: "report", unit: "w1", report: $r}')"
    drive "$1"
}
arrive_evidence() { # arrive_evidence <session> <n> <source> <text>
    PEND_N=$2 PEND_SRC=$3 PEND_TEXT=$4
    tick "$1" --with-data "$(jq -nc --arg n "$2" '{event: "evidence", decision: $n}')"
    drive "$1"
}
arrive_answer() { # arrive_answer <session> <n> <round> <outcome> [final decider]
    PEND_N=$2 PEND_ROUND=$3 PEND_TEXT=$4 PEND_FINAL=${5-}
    tick "$1" --with-data "$(jq -nc --arg n "$2" --arg r "$3" '{event: "answer", decision: $n, round: $r}')"
    drive "$1"
}
arrive_raise() { # arrive_raise <session> <question> <option>...
    local s=$1; PEND_Q=$2; shift 2; PEND_OPTS="$*"
    tick "$s" --with-data '{"event":"raise"}'
    drive "$s"
}
back_to_wait() { case "$(at "$1")" in pick_facts|classify_report) tick "$1" --with-data '{"go":"go"}' ;; esac; }

# replay_check <session>: the niwa#330 replay's pass condition.
replay_check() {
    local order first_verdict first_render
    order=$(visits "$1" | grep -n . )
    first_verdict=$(printf '%s\n' "$order" | grep ':decision_verdict$' | head -1 | cut -d: -f1)
    first_render=$(printf '%s\n' "$order" | grep -E ':(escalate|decision_withdraw|decision_reply)$' | head -1 | cut -d: -f1)
    [ -n "$first_verdict" ] || return 1
    [ -z "$first_render" ] || [ "$first_verdict" -lt "$first_render" ] || return 1
    ! printf '%s\n' "$order" | grep -q ':escalate$' || return 1
    [ ! -e "$DEC_ST/$1.bad-table" ]
}

# --- 1 and 2: the niwa#330 replay --------------------------------------------------------

SETTLED_D='{"next":2,"current":null,"entries":[{"id":1,"round":0,"question":"Which marketplace layout do we ship?",
  "options":["(c) per-project clones","(d) a shared clone"],"state":"settled","source":"worker w1","verdict":"settle",
  "rec":"","reason":"","target":"","owed":"","redirect":false,"evidence":[],
  "outcome":"(d) a shared clone: the flip condition is a per-project version moving","decided_by":"coordinator"}]}'
verdict_for() {
    case "$2" in
        1) echo "settle (d) a shared clone: the per-project installs held, so the flip condition didn't happen, and the record already accepts the shared clone moving" ;;
        *) echo "settle ship: the check the worker ran supports (d) and nothing in it is a reason to hold" ;;
    esac
}
replay() { # replay <session>
    seed "$1" "$SETTLED_D"
    arrive_evidence "$1" 1 dispatcher "check result, mixed: the shared marketplace clone moved, the installed per-project versions held"
    back_to_wait "$1"
    [ "$(at "$1")" = wait ] || return 0
    arrive_report "$1" "worker w1" "Ran the check the decision named.
Please decide whether to ship."
}

start replay-1 "$TPL" || finish
replay replay-1
if replay_check replay-1; then pass "replay: the verdict comes before any render, and nothing is escalated"; else
    fail "replay: the verdict comes before any render, and nothing is escalated" "$(visits replay-1 | tr '\n' ' ')"; fi
eq "replay: the evidence reopened entry 1 and it settled again on (d)" \
    'settled|(d)' "$(model replay-1 '.entries[0] | "\(.state)|\(.outcome[0:3])"' | tr -d '"')"
eq "replay: the old outcome is kept as evidence" true \
    "$(model replay-1 'any(.entries[0].evidence[]; .src == "previous outcome")')"
eq "replay: the worker's question is entry 2, opened as addressed and settled" 'settled|true' \
    "$(model replay-1 '.entries[1] | "\(.state)|\(.addressed)"' | tr -d '"')"
eq "replay: the messages rendered are the replies and one redirect, and none goes to a person" \
    'reply redirect reply' "$(jq -r .kind "$DEC_ST/replay-1.sent" | tr '\n' ' ' | sed 's/ $//')"
eq "replay: the run ends back at the report's classification" classify_report "$(at replay-1)"

start variant-1 "$VAR" || finish
replay variant-1
if replay_check variant-1; then fail "variant: the replay's check fails when evidence goes straight to escalate" "it passed: $(visits variant-1 | tr '\n' ' ')"; else
    pass "variant: the replay's check fails when evidence goes straight to escalate"; fi
eq "variant: the render finds nothing owed and the run stops at record_conflict" record_conflict "$(at variant-1)"

# --- 3: three levels ---------------------------------------------------------------------

# W reports to a person; R reports to W, whose dispatch topic is `ws`.
start lvl-w "$TPL" || finish
start lvl-r "$TPL" ws || finish
seed lvl-w '{"next":1,"entries":[],"current":null}'
seed lvl-r '{"next":1,"entries":[],"current":null}'
verdict_for() { echo "escalate wait for the release|the release is Friday and the merge can ride it"; }
last_sent() { tail -1 "$DEC_ST/$1.sent"; }

arrive_raise lvl-r "Merge the migration before the release?" "merge now" "wait for the release"
back_to_wait lvl-r
eq "levels: R escalates its entry to coordinator ws" 'escalated|coordinator ws' \
    "$(model lvl-r '.entries[0] | "\(.state)|\(.target)"' | tr -d '"')"
eq "levels: R's rendered escalation names decision 1 round 1" "Decision 1 round 1." \
    "$(last_sent lvl-r | jq -r .text | head -1)"

arrive_report lvl-w "coordinator roadmap-r" "$(last_sent lvl-r | jq -r .text)"
eq "levels: W opens R's escalation as its own entry, with R's entry as the source" \
    'coordinator roadmap-r #1 round 1' "$(model lvl-w '.entries[0].source' | tr -d '"')"
eq "levels: W escalates it to a person with a recommendation" 'escalated|a person|wait for the release' \
    "$(model lvl-w '.entries[0] | "\(.state)|\(.target)|\(.rec)"' | tr -d '"')"
back_to_wait lvl-w

arrive_answer lvl-w 1 1 "wait for the release"
eq "levels: the person's answer settles W's entry" 'settled|a person' \
    "$(model lvl-w '.entries[0] | "\(.state)|\(.decided_by)"' | tr -d '"')"
eq "levels: W renders a reply naming R's entry and round" \
    "Answer: decision 1 round 1: wait for the release. Decided by a person." "$(last_sent lvl-w | jq -r .text)"
back_to_wait lvl-w

arrive_answer lvl-r 1 1 "wait for the release" "a person"
eq "levels: R's entry settles naming the final decider" 'settled|coordinator ws (final: a person)' \
    "$(model lvl-r '.entries[0] | "\(.state)|\(.decided_by)"' | tr -d '"')"
back_to_wait lvl-r

# A withdrawal from below.
arrive_raise lvl-r "Pin the plugin before the release?" "pin" "don't pin"
back_to_wait lvl-r
arrive_report lvl-w "coordinator roadmap-r" "$(last_sent lvl-r | jq -r .text)"
back_to_wait lvl-w
eq "levels: W has R's second entry escalated to a person" 'escalated|coordinator roadmap-r #2 round 1' \
    "$(model lvl-w '.entries[1] | "\(.state)|\(.source)"' | tr -d '"')"
verdict_for() { echo "settle don't pin: the release moved, so the question is moot"; }
arrive_evidence lvl-r 2 dispatcher "the release moved a week"
back_to_wait lvl-r
eq "levels: evidence on R's sent escalation renders one withdrawal" 1 \
    "$(jq -r .kind "$DEC_ST/lvl-r.sent" | grep -c '^withdrawal$')"
R_SENT=$(wc -l < "$DEC_ST/lvl-r.sent")
W_BEFORE=$(wc -l < "$DEC_ST/lvl-w.sent")
arrive_report lvl-w "coordinator roadmap-r" "$(jq -rs '[.[] | select(.kind == "withdrawal")] | last | .text' "$DEC_ST/lvl-r.sent")"
eq "levels: the withdrawal reopens W's entry, which settles on a new verdict" "settled" \
    "$(model lvl-w '.entries[1].state' | tr -d '"')"
eq "levels: W withdraws its own escalation from the person" "withdrawal" \
    "$(sed -n "$((W_BEFORE + 1))p" "$DEC_ST/lvl-w.sent" | jq -r .kind)"
eq "levels: nothing goes back down to R after the withdrawal" "0" \
    "$(tail -n +"$((W_BEFORE + 1))" "$DEC_ST/lvl-w.sent" | jq -r 'select(.kind == "reply") | .kind' | wc -l | tr -d ' ')"
eq "levels: R sent nothing more" "$R_SENT" "$(wc -l < "$DEC_ST/lvl-r.sent")"
[ ! -e "$DEC_ST/lvl-w.bad-table" ] && pass "levels: every table W showed a person had a recommendation and a reason" ||
    fail "levels: every table W showed a person had a recommendation and a reason"

finish
