#!/usr/bin/env bash
# decisions-replay_engine_test.sh -- the decision flow's acceptance tests, in
# real koto, against records in the testdata/gh stand-in.
#
# The skeleton template holds the decision states and the states whose edges
# they change (wait, report_facts), cut from STATES_FROM, and a record_find
# state that seals `found <ref>` so the run has a record as a real run does.
# Every state they route to that isn't under test is a terminal, or a
# pass-through (take_report, pick_facts, classify_report) so one run can take
# several arrivals. Every script is the shipped one, copied from this
# directory, except those named in STAND_INS, which come from
# testdata/decisions/stand-ins/.
#
# What moves as the coordinate-decisions plan lands: each issue that ships a
# script removes it from STAND_INS (Issue 6 report-questions.sh, Issue 7
# record-decision.sh, Issue 8 decision-next.sh and coord-verdict.sh), and
# Issue 8, which puts the states in coordinate.md, points STATES_FROM there.
# Issue 10 deletes stand-in-states.yaml and the stand-ins directory. The
# driver, the arrivals, the fixtures and the assertions stay: they use
# record-decision.sh's interface, the sealed captures and context keys the
# real scripts write, and records rendered by the real codec.
#
# Some of that interface is chosen here, where the DESIGN leaves it open, for
# Issues 6 and 7 to adopt or change together with this harness:
# record-decision.sh's write-mode flags, the shape of coord/questions.json
# (report-questions.sh's header), an Outcome cell written
# `<outcome>; reason: <reason>`, a nested Decided by written
# `<target> (final: <decider>)`, and the addressed mark (the codec's
# d_addressed_mark). The stand-in record-decision.sh also answers --list and
# --read itself, in place of the shipped read modes, until Issue 7 replaces it.
#
# Proves:
#   1. the niwa#330 replay: a settled entry whose source is the worker, the
#      dispatcher's mixed check result recorded as evidence on it, and the
#      worker's "please decide whether to ship" in a report.
#      decision_verdict is entered before any escalation, withdrawal or reply
#      is rendered; no escalation is rendered; and no read of the section
#      during the run shows an entry escalated to a person without its
#      recommendation and reason. The redirect is outside the first check:
#      the DESIGN owes it per report, before the take (rule 5 before rule 7),
#      and it asks no one anything.
#   2. the same replay against a template whose wait evidence edge goes
#      straight to escalate fails that check;
#   3. three levels (a person, a workspace coordinator W, a roadmap
#      coordinator R reporting to W): R's escalation opens a proposed entry at
#      W with R's entry as its source; the person's answer settles W's entry,
#      and W's rendered reply, relayed down as R's answer, settles R's naming
#      the final decider; a withdrawal from R reopens W's escalated entry,
#      W withdraws it from the person, and when W settles it nothing goes back
#      down.
#
# Needs koto, jq and git; SKIPs (exit 0) without koto, which
# run-tests.sh --engine turns into a failure.
# Usage: bash skills/coordinate/scripts/decisions-replay_engine_test.sh
set -uo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
for bin in koto jq git; do
    command -v "$bin" >/dev/null 2>&1 || { echo "SKIP: $bin not on PATH -- the engine cases did not run"; exit 0; }
done
ORIG_PATH=$PATH

STATES_FROM="$HERE/testdata/decisions/stand-in-states.yaml"
STAND_INS="coord-verdict.sh decision-next.sh record-decision.sh"

# test-lib.sh gives the GitHub DB, the codec-rendered records and ok/bad/eq.
# It also puts testdata/ (the koto stand-in too) first on PATH; this suite
# needs the real koto, so only the gh stand-in goes in front.
. "$HERE/testdata/test-lib.sh"
T=$(cd -P "$T" && pwd -P)
# KEEP_T=1 keeps the scratch directory for a look after a failure.
if [ -n "${KEEP_T-}" ]; then trap - EXIT; echo "keeping $T"; fi
unset KOTO_STORE KOTO_COMPILED_HASH
mkdir -p "$T/bin"
printf '#!/usr/bin/env bash\nexec "%s/testdata/gh" "$@"\n' "$HERE" > "$T/bin/gh"
chmod +x "$T/bin/gh"
PATH="$T/bin:$ORIG_PATH"
export PATH HOME="$T/home" GIT_CEILING_DIRECTORIES="$T"
mkdir -p "$HOME" "$T/ws"
cd "$T/ws" || exit 1
db_init
finish() { done_tests decisions-replay; exit $?; }

# --- the plugin tree ---------------------------------------------------------------------

PR="$T/plugin"
S="$PR/skills/coordinate/scripts"
mkdir -p "$S" "$PR/skills/coordinate/koto-templates"
cp "$HERE"/*.sh "$HERE"/*.jq "$S/"
cp -R "$HERE/../references" "$PR/skills/coordinate/"
case " $STAND_INS " in *" coord-verdict.sh "*) mv "$S/coord-verdict.sh" "$S/coord-verdict-shipped.sh" ;; esac
for f in $STAND_INS; do cp "$HERE/testdata/decisions/stand-ins/$f" "$S/$f"; done
chmod +x "$S"/*.sh

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
  SCOPE:
    description: scope
    default: roadmap
  ROADMAP:
    description: the roadmap's path
    default: ""
  DISCIPLINE:
    description: discipline
    default: ""
  HOST_REPO:
    description: host
    default: acme/widgets
  REPORTS_TO:
    description: the coordinator this run reports to; empty for a person
    default: ""
  RECORD_REF:
    description: the record this run found
    required: true
states:
  entry:
    accepts:
      go:
        type: enum
        values: [wait]
        required: true
    transitions:
      - target: record_find
        when:
          go: wait
  record_find:
    default_action:
      command: '"{{PLUGIN_ROOT}}/skills/coordinate/scripts/coord-log.sh" seal --session "{{SESSION_NAME}}" --state record_find --token "found {{RECORD_REF}}"'
      capture_stdout_as: RECORD_FIND
      fallback: The seal failed.
    gates:
      record_find_verdict:
        type: command
        command: '"{{PLUGIN_ROOT}}/skills/coordinate/scripts/coord-verdict.sh" --session "{{SESSION_NAME}}" --state record_find --capture "{{RECORD_FIND}}"'
        overridable: false
    transitions:
      - target: wait
        when:
          gates.record_find_verdict.exit_code: 10  # found
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
        for st in entry record_find $UNDER $PASSTHROUGH $TERMINAL; do printf '## %s\nStand-in.\n\n' "$st"; done
    } > "$1"
}
TPL="$PR/skills/coordinate/koto-templates/coordinate.md"
skeleton "$TPL"
koto template compile "$TPL" >"$T/compile.err" 2>&1 || { bad "the skeleton compiles" "$(cat "$T/compile.err")"; finish; }
ok "the skeleton compiles"
# The variant: wait's evidence edge goes straight to escalate.
VAR="$T/variant/coordinate.md"
mkdir -p "$T/variant"
skeleton "$VAR" '/^      - target: decision_evidence$/s/decision_evidence/escalate/'
awk '/^  wait:$/,/^  report_facts:$/' "$VAR" | grep -q 'target: decision_evidence' &&
    bad "the variant rewires wait's evidence edge" "wait still routes evidence to decision_evidence"
koto template compile "$VAR" >"$T/compile.err" 2>&1 || { bad "the variant compiles" "$(cat "$T/compile.err")"; finish; }
ok "the variant compiles, wait's evidence edge going to escalate"

# --- the fixtures: records in the gh stand-in --------------------------------------------

# new_run <session> <template> <roadmap-name> <record-number> [reports-to]:
# an empty record for the roadmap and a session that has found it, at wait.
new_run() {
    db '.issues += [{repo: "acme/widgets", number: $k, title: "Coordinator record: ROADMAP-\($n)", body: $b,
        state: "open", author: "coord", editor: null}]' --argjson k "$4" --arg n "$3" \
        --arg b "$(render "$(record_json roadmap "$3")" issue)"
    koto init "$1" --template "$2" --var PLUGIN_ROOT="$PR" --var ROADMAP="docs/roadmaps/ROADMAP-$3.md" \
        --var RECORD_REF="$4" --var REPORTS_TO="${5-}" >/dev/null 2>"$T/init.err" ||
        { bad "session $1 starts" "$(cat "$T/init.err")"; return 1; }
    koto next "$1" --no-cleanup --with-data '{"go":"wait"}' > "$T/next.json" 2>&1
    [ "$(at "$1")" = wait ] || { bad "session $1 reaches wait" "$(cat "$T/next.json")"; return 1; }
}
# edit_record <record-number> <roadmap-name> <jq program over the parsed record> [jq args]
edit_record() {
    local k=$1 n=$2 p=$3; shift 3
    jq -r --argjson k "$k" '.issues[] | select(.number == $k) | .body' "$GH_DB" > "$T/body.md"
    bash "$S/record-parse.sh" --container issue --expect-scope "roadmap:$n" "$T/body.md" > "$T/parsed.json" || return 1
    jq -c "$@" "$p" "$T/parsed.json" > "$T/next.json" || return 1
    db '(.issues[] | select(.number == $k) | .body) = $b' --argjson k "$k" --arg b "$(render "$(cat "$T/next.json")" issue)"
}
seed_holding() { edit_record "$1" "$2" '.holdings += [$h]' --argjson h "$3"; }   # <ref> <name> <holding-json>
seed_decisions() { edit_record "$1" "$2" '.decisions = $d' --argjson d "$3"; }    # <ref> <name> <section-json>

# --- the driver --------------------------------------------------------------------------

tick() { local s=$1; shift; koto next "$s" --no-cleanup "$@" > "$T/next.json" 2>&1; }
at() { koto status "$1" | jq -r '.current_state // "gone"'; }
section() { bash "$S/record-decision.sh" --session "$1" --list; }
entry() { section "$1" | jq -c --arg n "$2" '.entries[] | select(.decision == $n)'; }
field() { entry "$1" "$2" | jq -r --arg f "$3" '.[$f] // ""'; }
routed() { bash "$S/coord-log.sh" capture --session "$1" --name DECISION_NEXT --state decision_next | cut -d' ' -f2; }
rd() { # rd <session> <mode args...>: record-decision.sh as the coordinator runs it
    local s=$1; shift
    bash "$S/record-decision.sh" --session "$s" "$@" >/dev/null 2>"$T/rd.err" || { RD_FAILED=1; bad "record-decision.sh $1 for $s" "$(cat "$T/rd.err")"; }
}
# visits <session>: the states entered, in order, one per line.
visits() {
    jq -r 'select(.type == "transitioned" or .type == "directed_transition") | .payload.to' \
        "$(koto session dir "$1")/koto-$1.state.jsonl"
}
# The decision a person would be asked to make: every entry escalated to a
# person needs its recommendation and reason. Read after every step; one bad
# read marks the session.
table_check() {
    section "$1" | jq -e 'all(.entries[] | select(.state == "escalated" and .target == "a person");
        (.recommendation | test("\\S")) and (.reason | test("\\S")))' >/dev/null 2>&1 || : > "$T/$1.bad-table"
}
# verdict_for <session> <n>: the scenario's coordinator's verdict, one of
#   settle|<outcome>|<reason>
#   escalate|<recommendation>|<reason>|<context>|<problem>|<grounds>
verdict_for() { echo "settle|default|default"; }

# What an arrival carries into the agent state it lands on.
PEND_SRC="" PEND_TEXT="" PEND_Q="" PEND_OUT="" PEND_REASON="" PEND_FINAL=""
PEND_OPTS=()
RD_FAILED=0

# drive <session>: answer each agent state as the coordinator does, until the
# run is back at a hub or a terminal. Every message sent goes to the session's
# outbox, "$T/<session>.sent", one JSON line {kind, n, text}.
drive() {
    local s=$1 st i=0 n v a b c d e cn rs o
    while [ $i -lt 60 ]; do
        i=$((i + 1))
        # A refused write stops the drive: ticking on would only repeat it.
        [ "$RD_FAILED" = 0 ] || { RD_FAILED=0; return 0; }
        table_check "$s"
        st=$(at "$s")
        case "$st" in
            wait|pick_facts|classify_report|gone) return 0 ;;
            record_conflict|rebrief|surface|decision_apply|leg_pick|quiet_check|merged_facts|teardown|rotation_close|done_stopped) return 0 ;;
            take_report) tick "$s" --with-data '{"go":"go"}' ;;
            decision_take) rd "$s" --take; tick "$s" --with-data '{"taken":"taken"}' ;;
            decision_verdict)
                n=$(routed "$s")
                IFS='|' read -r v a b c d e <<EOF
$(verdict_for "$s" "$n")
EOF
                case "$v" in
                    settle) rd "$s" --settle --outcome "$a" --reason "$b"; tick "$s" --with-data '{"verdict":"settle"}' ;;
                    escalate) rd "$s" --escalate --recommendation "$a" --reason "$b" --context "$c" --problem "$d" --grounds "$e"
                              tick "$s" --with-data '{"verdict":"escalate"}' ;;
                esac ;;
            decision_open)
                # The coordinator words each extracted question for the record.
                koto context get "$s" coord/questions.json |
                    jq '[.[] | select(.kind != "withdrawal") | {key: (.index | tostring), value: {question: .text, options: (.options // ["ship", "hold"])}}] | from_entries' \
                    > "$T/words.json"
                rd "$s" --open-from-report --text-file "$T/words.json"; tick "$s" --with-data '{"opened":"opened"}' ;;
            decision_raise)
                set --
                for o in "${PEND_OPTS[@]}"; do set -- "$@" --option "$o"; done
                rd "$s" --open --question "$PEND_Q" "$@"; tick "$s" --with-data '{"raised":"raised"}' ;;
            decision_evidence) rd "$s" --evidence --source "$PEND_SRC" --text "$PEND_TEXT"; tick "$s" --with-data '{"recorded":"recorded"}' ;;
            decision_answer)
                set -- --outcome "$PEND_OUT"
                [ -n "$PEND_REASON" ] && set -- "$@" --reason "$PEND_REASON"
                [ -n "$PEND_FINAL" ] && set -- "$@" --final "$PEND_FINAL"
                rd "$s" --answer "$@"; tick "$s" --with-data '{"answered":"recorded"}' ;;
            escalate_send|decision_withdraw_send|decision_reply_send|decision_redirect_send)
                case "$st" in
                    escalate_send) rs=escalate cn=ESCALATE_MESSAGE ;;
                    decision_withdraw_send) rs=decision_withdraw cn=WITHDRAW_MESSAGE ;;
                    decision_reply_send) rs=decision_reply cn=REPLY_MESSAGE ;;
                    *) rs=decision_redirect cn=REDIRECT_MESSAGE ;;
                esac
                koto context get "$s" coord/decision_message.txt > "$T/message.txt"
                bash "$S/coord-log.sh" capture --session "$s" --name "$cn" --state "$rs" |
                    jq -Rc --rawfile t "$T/message.txt" 'split(" ") | {kind: .[1], n: .[2], text: $t}' >> "$T/$s.sent"
                # Nobody is in conversation with a harness coordinator, so a person
                # is asked by message.
                if [ "$st" = escalate_send ] && [ -z "$(bash "$S/coord-log.sh" vars --session "$s" | jq -r ".REPORTS_TO // \"\"")" ]; then
                    rd "$s" --sent --route message
                else rd "$s" --sent; fi
                tick "$s" --with-data '{"sent":"sent"}' ;;
            *) tick "$s" ;;
        esac
    done
    bad "drive $s reaches a hub" "still at $(at "$s") after $i steps"
}
# The arrivals, each named at wait the way the coordinator names them.
arrive_report() { # arrive_report <session> <topic> <text>
    tick "$1" --with-data "$(jq -nc --arg u "$2" --arg r "$3" '{event: "report", unit: $u, report: $r}')"
    drive "$1"
}
arrive_evidence() { # arrive_evidence <session> <n> <source> <text>
    PEND_SRC=$3 PEND_TEXT=$4
    tick "$1" --with-data "$(jq -nc --arg n "$2" '{event: "evidence", decision: $n}')"
    drive "$1"
}
arrive_answer() { # arrive_answer <session> <n> <round> <outcome> [reason] [final decider]
    PEND_OUT=$4 PEND_REASON=${5-} PEND_FINAL=${6-}
    tick "$1" --with-data "$(jq -nc --arg n "$2" --arg r "$3" '{event: "answer", decision: $n, round: $r}')"
    drive "$1"
}
arrive_raise() { # arrive_raise <session> <question> <option>...
    local s=$1; PEND_Q=$2; shift 2; PEND_OPTS=("$@")
    tick "$s" --with-data '{"event":"raise"}'
    drive "$s"
}
back_to_wait() { case "$(at "$1")" in pick_facts|classify_report) tick "$1" --with-data '{"go":"go"}' ;; esac; }
last_sent() { tail -1 "$T/$1.sent" | jq -r "$2"; }

# replay_check <session>: the niwa#330 replay's pass condition.
replay_check() {
    local order first_verdict first_render
    order=$(visits "$1" | grep -n .)
    first_verdict=$(printf '%s\n' "$order" | grep ':decision_verdict$' | head -1 | cut -d: -f1)
    first_render=$(printf '%s\n' "$order" | grep -E ':(escalate|decision_withdraw|decision_reply)$' | head -1 | cut -d: -f1)
    [ -n "$first_verdict" ] || return 1
    [ -z "$first_render" ] || [ "$first_verdict" -lt "$first_render" ] || return 1
    ! printf '%s\n' "$order" | grep -q ':escalate$' || return 1
    [ ! -e "$T/$1.bad-table" ]
}

# --- 1 and 2: the niwa#330 replay --------------------------------------------------------

# Entry 1 as an earlier run left it: settled, owing nothing, and so compacted
# by the codec's compact_settled (verdict and evidence blank, options kept).
SETTLED_D='{"next":2,"entries":[{"decision":"1","round":"0","question":"Which marketplace layout do we ship?",
  "options":"(c) per-project clones -- each project pins its own marketplace version\n(d) a shared clone -- one clone serves every project",
  "state":"settled","source":"worker w1 [20260920T080000Z report 3.1]",
  "outcome":"(d) a shared clone; reason: the flip condition is a per-project version moving, which is untested",
  "decided_by":"this coordinator","updated":"2026-09-20T08:30Z"}]}'
verdict_for() {
    case "$2" in
        1) echo "settle|(d) a shared clone|the per-project installs held, so the flip condition didn't happen, and the record already accepts the shared clone moving" ;;
        *) echo "settle|ship|the check the worker ran supports (d), and nothing in it is a reason to hold" ;;
    esac
}
replay() { # replay <session> <template> <record-number>
    new_run "$1" "$2" "replay-$3" "$3" || return 1
    seed_holding "$3" "replay-$3" "$(holding w1 '{"entry_point":"/shirabe:work-on","pull_request":""}')"
    seed_decisions "$3" "replay-$3" "$SETTLED_D"
    arrive_evidence "$1" 1 dispatcher "check result, mixed: the shared marketplace clone moved, the installed per-project versions held"
    # Read now: entry 1 settles again, owing only the reply, and once that is
    # sent a later write may compact its evidence away.
    E1_AFTER_EVIDENCE=$(field "$1" 1 evidence)
    E1_STATE_AFTER=$(field "$1" 1 state)
    back_to_wait "$1"
    [ "$(at "$1")" = wait ] || return 0
    arrive_report "$1" w1 "Ran the check the decision named.
Please decide whether to ship."
}

replay coordinate-roadmap-replay-11-20260928T100001Z "$TPL" 11
R1=coordinate-roadmap-replay-11-20260928T100001Z
if replay_check "$R1"; then ok "replay: the verdict comes before any render, and nothing is escalated"; else
    bad "replay: the verdict comes before any render, and nothing is escalated" "$(visits "$R1" | tr '\n' ' ')"; fi
eq "replay: the evidence reopened entry 1, which settled again on (d)" 'settled|settled|(d) a shared clone' \
    "$E1_STATE_AFTER|$(field "$R1" 1 state)|$(field "$R1" 1 outcome | sed 's/; reason:.*//')"
case "$E1_AFTER_EVIDENCE" in
    *"previous outcome"*"check result, mixed"*) ok "replay: the old outcome and the mixed result are kept as evidence" ;;
    *) bad "replay: the old outcome and the mixed result are kept as evidence" "$E1_AFTER_EVIDENCE" ;;
esac
eq "replay: the worker's question is entry 2, opened with its source" "worker w1" "$(field "$R1" 2 source | sed 's/ \[.*//')"
case "$(field "$R1" 2 evidence)" in *"addressed to a person"*) ok "replay: entry 2 is noted as addressed to a person" ;;
    *) bad "replay: entry 2 is noted as addressed to a person" "$(field "$R1" 2 evidence)" ;; esac
eq "replay: entry 2 was taken up and settled" "settled" "$(field "$R1" 2 state)"
eq "replay: the messages sent are the reply, the redirect and the reply, none to a person" 'reply redirect reply' \
    "$(jq -r .kind "$T/$R1.sent" | tr '\n' ' ' | sed 's/ $//')"
eq "replay: the run ends at the report's classification" classify_report "$(at "$R1")"

V1=coordinate-roadmap-replay-12-20260928T100002Z
replay "$V1" "$VAR" 12
if replay_check "$V1"; then bad "variant: the replay's check fails when evidence goes straight to escalate" "it passed: $(visits "$V1" | tr '\n' ' ')"; else
    ok "variant: the replay's check fails when evidence goes straight to escalate"; fi
eq "variant: escalate is entered with no verdict before it" "wait escalate" "$(visits "$V1" | sed -n '3,4p' | tr '\n' ' ' | sed 's/ $//')"
eq "variant: the render finds nothing routed and the run stops at record_conflict" record_conflict "$(at "$V1")"

# --- 3: three levels ---------------------------------------------------------------------

# W reports to a person and holds R, a coordinator, under the topic rr. R reports to W,
# whose dispatch topic is ws.
LW=coordinate-roadmap-ws-20260928T100003Z
LR=coordinate-roadmap-rr-20260928T100004Z
new_run "$LW" "$TPL" ws 21 || finish
new_run "$LR" "$TPL" rr 22 ws || finish
seed_holding 21 ws "$(holding rr '{"entry_point":"/shirabe:coordinate","pull_request":""}')"
CTX_M="The migration rewrites the lockfile format, and the release on Friday is the next time users upgrade."
PROB_M="Shipping it now splits users across two formats for a week; waiting holds two other features behind it."
CTX_P="The plugin floats to its latest version, and the release pins what users get for a quarter."
PROB_P="Pinning now freezes a version with a known bug; not pinning lets a breaking release through."
verdict_for() {
    case "$1:$2:$(field "$1" "$2" question)" in
        *:Merge*) echo "escalate|wait for the release|the release is Friday and the migration rides it|$CTX_M|$PROB_M|scope" ;;
        "$LR":*:Pin*) if field "$LR" "$2" evidence | grep -q "release moved"; then
                          echo "settle|don't pin|the release moved, so the question is moot"
                      else echo "escalate|don't pin|the bug fix lands next week|$CTX_P|$PROB_P|scope"; fi ;;
        "$LW":*:Pin*) if field "$LW" "$2" evidence | grep -q "withdrawn:"; then
                          echo "settle|don't pin|the question was withdrawn below"
                      else echo "escalate|don't pin|the bug fix lands next week|$CTX_P|$PROB_P|scope"; fi ;;
    esac
}

arrive_raise "$LR" "Merge the migration before the release?" "merge now -- the format lands this week" "wait for the release -- one upgrade carries both changes"
back_to_wait "$LR"
eq "levels: R escalates its entry to coordinator ws" 'escalated|coordinator ws' "$(field "$LR" 1 state)|$(field "$LR" 1 target)"
eq "levels: R's escalation is rendered, naming decision 1 round 1" "escalation|Decision 1 round 1." \
    "$(last_sent "$LR" .kind)|$(last_sent "$LR" .text | head -1)"

arrive_report "$LW" rr "$(last_sent "$LR" .text)"
eq "levels: W opens R's escalation as its own entry, with R's entry as its source" \
    'coordinator rr #1 round 1' "$(field "$LW" 1 source | sed 's/ \[.*//')"
eq "levels: W took it up as a proposed entry" 1 "$(visits "$LW" | grep -c '^decision_take$')"
eq "levels: W carries R's options with their explanations, the recommendation first" "wait for the release -- one upgrade carries both changes|merge now -- the format lands this week" "$(entry "$LW" 1 | jq -r '.options | split("\n") | join("|")')"
eq "levels: W escalates it to a person with a recommendation" 'escalated|a person|wait for the release' \
    "$(field "$LW" 1 state)|$(field "$LW" 1 target)|$(field "$LW" 1 recommendation)"
back_to_wait "$LW"

arrive_answer "$LW" 1 1 "wait for the release"
eq "levels: the person's answer settles W's entry" 'settled|a person' "$(field "$LW" 1 state)|$(field "$LW" 1 decided_by)"
eq "levels: W's reply names R's entry and round" "reply|Answer: decision 1 round 1." "$(last_sent "$LW" .kind)|$(last_sent "$LW" .text | head -1)"
back_to_wait "$LW"
W_SENT=$(wc -l < "$T/$LW.sent")
W_ENTRY=$(entry "$LW" 1)
arrive_answer "$LW" 1 1 "wait for the release"
eq "levels: the same answer sent again changes nothing and sends nothing" "same $W_SENT" \
    "$([ "$(entry "$LW" 1)" = "$W_ENTRY" ] && echo same || echo changed) $(wc -l < "$T/$LW.sent")"
back_to_wait "$LW"

# R's coordinator relays W's reply as an answer, from the reply's own lines.
REPLY=$(last_sent "$LW" .text)
arrive_answer "$LR" 1 1 "$(printf '%s\n' "$REPLY" | sed -n 's/^Outcome: //p')" \
    "$(printf '%s\n' "$REPLY" | sed -n 's/^Reason: //p')" "$(printf '%s\n' "$REPLY" | sed -n 's/^Decided by: //p')"
eq "levels: R's entry settles naming the final decider" 'settled|coordinator ws (final: a person)' \
    "$(field "$LR" 1 state)|$(field "$LR" 1 decided_by)"
back_to_wait "$LR"

# A withdrawal from below.
arrive_raise "$LR" "Pin the plugin before the release?" "pin -- freezes a version with a known bug" "don't pin -- lets a breaking release through"
back_to_wait "$LR"
arrive_report "$LW" rr "$(last_sent "$LR" .text)"
back_to_wait "$LW"
eq "levels: W has R's second entry escalated to a person" 'escalated|coordinator rr #2 round 1' \
    "$(field "$LW" 2 state)|$(field "$LW" 2 source | sed 's/ \[.*//')"
R_BEFORE=$(wc -l < "$T/$LR.sent")
arrive_evidence "$LR" 2 dispatcher "the release moved a week"
back_to_wait "$LR"
eq "levels: evidence on R's sent escalation renders a withdrawal" "withdrawal|Withdrawn: decision 2 round 1." \
    "$(sed -n "$((R_BEFORE + 1))p" "$T/$LR.sent" | jq -r .kind)|$(sed -n "$((R_BEFORE + 1))p" "$T/$LR.sent" | jq -r .text | head -1)"
eq "levels: R settles it itself afterwards, owing nothing" 'settled|' "$(field "$LR" 2 state)|$(field "$LR" 2 owed)"
W_BEFORE=$(wc -l < "$T/$LW.sent")
arrive_report "$LW" rr "$(sed -n "$((R_BEFORE + 1))p" "$T/$LR.sent" | jq -r .text)"
case "$(field "$LW" 2 evidence)" in *"withdrawn: decision 2 round 1"*) ok "levels: the withdrawal is evidence on W's entry" ;;
    *) bad "levels: the withdrawal is evidence on W's entry" "$(field "$LW" 2 evidence)" ;; esac
eq "levels: W withdraws its own escalation from the person" "withdrawal" "$(sed -n "$((W_BEFORE + 1))p" "$T/$LW.sent" | jq -r .kind)"
eq "levels: W's entry settles on a new verdict and owes nothing" 'settled|' "$(field "$LW" 2 state)|$(field "$LW" 2 owed)"
eq "levels: nothing goes back down to R after the withdrawal" "withdrawal" \
    "$(tail -n +"$((W_BEFORE + 1))" "$T/$LW.sent" | jq -r .kind | tr '\n' ' ' | sed 's/ $//')"
[ ! -e "$T/$LW.bad-table" ] && ok "levels: no read of W's section showed a person an escalation without its reasons" ||
    bad "levels: no read of W's section showed a person an escalation without its reasons"

finish
