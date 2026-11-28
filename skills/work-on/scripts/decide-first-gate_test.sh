#!/usr/bin/env bash
# decide-first-gate_test.sh -- decide-first-gate.sh against the real koto and
# the branch's shirabe, each record prepared with `shirabe question attempt`
# and `raise`.
#
# decide-first-routes_test.sh drives the gate through work-on.md. This suite
# runs the script on its own, in sessions from a one-state template whose
# self-loop edges stand for the edges into decide_first: submitting
# `arrive: <state>` assigns decide_origin, and `clear: yes` assigns
# decide_arrival: none, as finalization's deferral edge does, so each arrival
# is a transition koto records, and each code is reached by one prepared
# record and nothing else.
#
# Sessions: `manager`, and `worker...` sessions dispatched by it, whose
# questions go to session:manager and are answered there with `koto decisions
# answer --by session`; `solo...` sessions nothing dispatched, whose questions
# go to person:owner. An owner's answer comes from a recorded harness session
# built from scripts/fixtures/question-commands/accepted.jsonl, never a live
# prompt, as scripts/question-commands_test.sh records one.
#
# Cases:
#   --arrive  names the first arrival implementation:1 and writes it to
#     decide_arrival, prints the same name on a repeat run, names the next
#     arrival implementation:2; an agent's write of decide_origin or
#     decide_arrival changes neither the name nor the code; an arrival from a
#     state no covered exit names (2); koto failing `context history` (2)
#   --from    exits 10 to 16 for the seven covered states, 2 for none
#   --laps  3 arrivals from one state (0), a fourth (1), an agent's write of
#     decide_origin changing nothing, and a session continuing the run going
#     on counting (1, arrival implementation:5)
#   the gate  no attempt (1, with one finding); an undecided attempt and no
#     question (1); an undecided attempt and its open question (3, writing
#     nothing); decided (0); provisional (0); a deciding attempt beside the
#     arrival's open question (3, with a finding); an open need raised from
#     the arrival with no attempt (3); an attempt for an earlier arrival, one
#     with no state, one in another session and one a predecessor recorded
#     for the arrival it waited on (1 each); a question answered since, and
#     one withdrawn since (1 each); koto failing, koto failing only `context
#     exists`, and a shirabe with no `question precedent` (2 each)
#   --record-question and --recorded  with the question open, the action
#     writes its identity and the gate exits 0; with a stale decide_question
#     and nothing open, the action clears the key and exits 0 and the gate
#     exits 1; once the question is answered, the gate exits 1
#   presenting  an owner question raised, rendered and answered from a
#     recorded prompt: the gate exits 3 before the answer, 1 after it (so
#     `raised` holds), and 0 once an attempt citing the answer is recorded
#   --approval  no attempt, and a deciding attempt that cites no answer (1
#     each); a deciding attempt citing the dispatcher's answer to the question
#     raised for the arrival (0), and the owner's verified answer (0); the
#     arrival cleared by a `clear` transition (1), and still 1 after an
#     agent writes decide_arrival back; the answer to a question another
#     session raised for the same arrival name (1); koto refusing to pass a
#     question to a session that is not the dispatcher; a dispatcher linked
#     after the question was raised, then answering it (1); a successor
#     linked to a different dispatcher than the run it continues (1), and one
#     linked to the same (0); a settle whose basis is a session's answer (1),
#     and one whose basis is the owner's verified answer (0); and koto's own
#     refusals of an answer by the run itself and of a person's answer with
#     no prompt evidence
#   --resume  no decide_question: 0, with no shirabe call; the question open,
#     answered but not cited, and withdrawn (1 each); cited by a deciding
#     attempt (11, the code of the state the question names)
#
# Usage: bash skills/work-on/scripts/decide-first-gate_test.sh
#   shirabe from SHIRABE_BIN, else the tree's target/release/shirabe, else
#   PATH; it must have `question precedent`. koto 0.42.0 or later on PATH; jq.
#
# Exit codes:
#   0 -- all cases pass
#   0 -- also when koto or jq is absent, every case skipped
#   1 -- one or more cases failed, or shirabe has no `question precedent`
#
# bash 3.2 floor: no associative arrays, no namerefs, no mapfile.

set -uo pipefail
. "$(dirname "$0")/../../../scripts/lib/koto-test-guard.sh" || exit 1
unset KOTO_RUN_MODE CLAUDE_CODE_SESSION_ATTENDED CLAUDE_CONFIG_DIR CLAUDE_CODE_SESSION_ID
unset KOTO_DECIDER KOTO_DECIDER_API_KEY KOTO_DECIDER_ENDPOINT

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
REPO=$(cd "$SCRIPT_DIR/../../.." && pwd)
GATE="$SCRIPT_DIR/decide-first-gate.sh"
FIXTURE="$REPO/scripts/fixtures/question-commands/accepted.jsonl"

PASS_COUNT=0
FAIL_COUNT=0
pass() { printf 'PASS: %s\n' "$*"; PASS_COUNT=$((PASS_COUNT + 1)); }
fail() { printf 'FAIL: %s\n' "$*"; FAIL_COUNT=$((FAIL_COUNT + 1)); }
finish() {
    echo
    echo "decide-first-gate_test.sh: $PASS_COUNT passed, $FAIL_COUNT failed"
    [ "$FAIL_COUNT" -eq 0 ]
    exit $?
}

# The engine cases are all of it: without koto or jq nothing runs, as on the
# macOS floor runner, which has no koto.
for tool in koto jq; do
    command -v "$tool" > /dev/null || { echo "SKIP: $tool is not on PATH -- no case ran"; exit 0; }
done
SHIRABE=""
if [ -n "${SHIRABE_BIN:-}" ] && [ -x "$SHIRABE_BIN" ]; then
    SHIRABE=$SHIRABE_BIN
elif [ -x "$REPO/target/release/shirabe" ]; then
    SHIRABE="$REPO/target/release/shirabe"
else
    SHIRABE=$(command -v shirabe)
fi
case "$SHIRABE" in /*) ;; *) SHIRABE="" ;; esac
if [ -z "$SHIRABE" ] || ! "$SHIRABE" question precedent --help > /dev/null; then
    fail "no shirabe with \`question precedent\` (SHIRABE_BIN, target/release/shirabe or PATH); build the branch's (cargo build --release -p shirabe)"
    finish
fi

T=$(mktemp -d "${TMPDIR:-/tmp}/decide-first-gate-test.XXXXXX") || { fail "mktemp failed"; finish; }
ACCOUNT_HOME=$(eval echo "~$(id -un)")
RECORDS=""
cleanup() {
    [ -n "${T:-}" ] && rm -rf "$T"
    [ -n "$RECORDS" ] && rm -rf "$RECORDS"
    return 0
}
ktg_on_exit cleanup
cd "$T" || { fail "cd $T"; finish; }

# The gate finds shirabe on PATH, as koto's gate commands do.
mkdir -p "$T/bin"
ln -s "$SHIRABE" "$T/bin/shirabe"
export PATH="$T/bin:$PATH"

# One edge per covered state, plus `nowhere` for a state no covered exit
# names, each assigning decide_origin as work-on.md's edges into decide_first
# do; `clear` assigns decide_arrival: none as finalization's deferral edge
# does.
{
    cat <<'EOF'
---
name: two
version: "1.0"
initial_state: work
states:
  work:
    accepts:
      done:
        type: enum
        values: [yes]
      arrive:
        type: enum
        values: [analysis, implementation, introspection, task_validation, post_research_validation, plan_validation, deferral_approval, nowhere]
      clear:
        type: enum
        values: [yes]
    transitions:
      - target: end
        when:
          done: yes
      - target: work
        when:
          clear: yes
        context_assignments:
          decide_arrival: none
EOF
    for o in analysis implementation introspection task_validation post_research_validation plan_validation deferral_approval nowhere; do
        printf '      - target: work\n        when:\n          arrive: %s\n        context_assignments:\n          decide_origin: %s\n' "$o" "$o"
    done
    cat <<'EOF'
  end:
    terminal: true
---

## work

Do the work.

## end

Done.
EOF
} > "$T/two.md"

# open <session> [koto init args...]
open() {
    local s=$1
    shift
    koto init "$s" --template "$T/two.md" "$@" > /dev/null 2>"$T/init.err" \
        || { fail "koto init $s: $(cat "$T/init.err")"; finish; }
}
# put <session> <key> <value>: an agent's write, which no arrival is read from.
put() {
    printf '%s' "$3" | koto context add "$1" "$2" > /dev/null 2>"$T/put.err" \
        || { fail "koto context add $1 $2: $(cat "$T/put.err")"; finish; }
}
# tick <session> <evidence>
tick() {
    koto next "$1" --with-data "$2" --no-cleanup > "$T/tick.out" 2>"$T/tick.err" \
        || fail "koto next $1 $2: $(cat "$T/tick.out" "$T/tick.err")"
}
# arrive <session> <state>: one transition assigning decide_origin.
arrive() { tick "$1" "{\"arrive\":\"$2\"}"; }
# gate [<mode>] <session> -> stdout in $G, exit in $RC
gate() {
    G=$(bash "$GATE" "$@" 2>"$T/gate.err")
    RC=$?
}
# at <session> <origin> <origin>:<n>: n arrivals from <origin>, then the
# default action's --arrive, which must name the n-th.
at() {
    local i=0 n=${3##*:}
    while [ "$i" -lt "$n" ]; do
        arrive "$1" "$2"
        i=$((i + 1))
    done
    gate --arrive "$1"
    [ "$RC:$G" = "0:$3" ] || fail "at $1: --arrive printed [$G], exit $RC, want $3: $(cat "$T/gate.err")"
}
# expect <label> <code>
expect() {
    if [ "$RC" -eq "$2" ]; then
        pass "$1: exit $2"
    else
        fail "$1: exit $RC, want $2: [$G] [$(cat "$T/gate.err")]"
    fi
}
# finding_says <label> <text>: one finding line whose message holds <text>.
finding_says() {
    local n m
    n=$(printf '%s\n' "$G" | grep -c '^::koto-finding::')
    m=$(printf '%s\n' "$G" | sed -n 's/^::koto-finding:://p' | jq -r 'select(.rule_id == "work-on/decide-first") | .message')
    case "$n:$m" in
        1:*"$2"*) pass "$1: one finding saying $2" ;;
        *) fail "$1: finding [$G]" ;;
    esac
}

# attempt <session> <args...> -> the attempt's id in $A, exit in $RC
attempt() {
    local s=$1
    shift
    "$SHIRABE" question attempt --in "$s" --what "cache store" "$@" > "$T/att.out" 2>"$T/att.err"
    RC=$?
    A=$(jq -r '.id // empty' "$T/att.out")
    [ "$RC" -eq 0 ] && [ -n "$A" ] || fail "shirabe question attempt --in $s $*: exit $RC: $(cat "$T/att.out" "$T/att.err")"
}
content() {
    jq -n --arg label "${2:-build cache store}" '{
        context: "The build cache is lost on every runner restart.",
        problem: "Two stores fit, and they differ in what an operator has to run.",
        question: "Which store should the build cache use?",
        options: [
            {label: "SQLite", reason: "One file beside the runner, no server to run."},
            {label: "Postgres", reason: "Shared across runners, but a server to keep up."}
        ],
        ground: "Picking a server changes what the team operates.",
        waiting: ["issue-12"],
        label: $label
    }' > "$1"
}
content "$T/q.json"
jq -n '{
    context: "Publishing the package needs the registry token.",
    problem: "The token is not in the environment and only the owner holds it.",
    question: "Can you provide the registry token?",
    need: "credential",
    needed: "A registry token with publish rights, set as NPM_TOKEN.",
    ground: "Only the owner holds the token.",
    waiting: ["issue-12"],
    label: "registry token"
}' > "$T/need.json"
# raise <session> <args...> -> the question's identity in $Q
raise() {
    local s=$1
    shift
    "$SHIRABE" question raise --in "$s" "$@" > "$T/raise.out" 2>"$T/raise.err"
    RC=$?
    Q=$(jq -r '.identity // empty' "$T/raise.out")
    [ "$RC" -eq 0 ] && [ -n "$Q" ] || fail "shirabe question raise --in $s $*: exit $RC: $(cat "$T/raise.out" "$T/raise.err")"
}
# answers <answerer> <raiser> <identity> -> the answer's id in $ANS
answers() {
    ANS=$(koto decisions answer --in="$1" --text=SQLite --by=session -- "$2" "${3##*/}" 2>"$T/ans.err" \
        | jq -r '.decision.id // .id // empty')
    [ -n "$ANS" ] || fail "$1 could not answer $3: $(cat "$T/ans.err")"
}
manager_answers() { answers manager "$1" "$2"; }
# settle <raiser> <identity> <basis> -> the settle's id in $SET
settle() {
    SET=$(koto decisions answer --in="$1" --outcome settled --basis "$3" --text "settled on the earlier answer" -- "$1" "${2##*/}" 2>"$T/set.err" \
        | jq -r '.decision.id // .id // empty')
    [ -n "$SET" ] || fail "$1 could not settle $2 on $3: $(cat "$T/set.err")"
}

open manager

# --- --arrive and --from ---------------------------------------------------------

open arr
arrive arr implementation
gate --arrive arr
[ "$RC:$G" = "0:implementation:1" ] && pass "--arrive names the first arrival: implementation:1" || fail "--arrive printed [$G], exit $RC: $(cat "$T/gate.err")"
[ "$(koto context get arr decide_arrival)" = implementation:1 ] && pass "--arrive writes the name to decide_arrival" \
    || fail "decide_arrival is [$(koto context get arr decide_arrival)]"
gate --arrive arr
[ "$RC:$G" = "0:implementation:1" ] && pass "--arrive run again with no new arrival prints the same name" || fail "--arrive repeat printed [$G], exit $RC"
arrive arr implementation
gate --arrive arr
[ "$RC:$G" = "0:implementation:2" ] && pass "the next arrival is implementation:2" || fail "--arrive second printed [$G], exit $RC"
put arr decide_origin analysis
put arr decide_arrival analysis:9
gate --arrive arr
[ "$RC:$G" = "0:implementation:2" ] && pass "an agent's writes of decide_origin and decide_arrival change no arrival" \
    || fail "--arrive after agent writes printed [$G], exit $RC"
gate --from arr
expect "--from after an agent's write of decide_origin reads the transition's (implementation)" 11
arrive arr nowhere
gate --arrive arr
expect "--arrive from a state no covered exit names" 2

open frm
codes=""
for o in analysis implementation introspection task_validation post_research_validation plan_validation deferral_approval; do
    arrive frm "$o"
    gate --from frm
    codes="$codes $RC"
done
[ "$codes" = " 10 11 12 13 14 15 16" ] && pass "--from exits 10 to 16 for the seven covered states" || fail "--from exits [$codes]"
open frm2
gate --from frm2
expect "--from with no arrival" 2

# --- the gate ----------------------------------------------------------------------

open solo1
at solo1 implementation implementation:1
gate solo1
expect "no attempt recorded" 1
finding_says "no attempt recorded" "no attempt is recorded for implementation:1"

open solo2
at solo2 implementation implementation:1
attempt solo2 --result undecided --state implementation:1
gate solo2
expect "an undecided attempt with no question" 1
finding_says "an undecided attempt with no question" "has no open question naming it"

raise solo2 --content "$T/q.json" --attempt "$A" --state implementation:1
Q_SOLO2=$Q
gate solo2
expect "an undecided attempt and its open question" 3
koto context exists solo2 decide_question > /dev/null && fail "the gate wrote decide_question" \
    || pass "the gate writes nothing to context"
gate --record-question solo2
expect "--record-question with the arrival's question open" 0
[ "$(koto context get solo2 decide_question)" = "$Q_SOLO2" ] && pass "--record-question writes the question's identity to decide_question" \
    || fail "decide_question is [$(koto context get solo2 decide_question)], want $Q_SOLO2"
gate --recorded solo2
expect "--recorded with the question open" 0
open solo2b
at solo2b implementation implementation:1
put solo2b decide_question stale
gate --record-question solo2b
expect "--record-question with no open question" 0
koto context exists solo2b decide_question > /dev/null && fail "--record-question left a stale decide_question" \
    || pass "--record-question clears decide_question before it looks"
gate --recorded solo2b
expect "--recorded with nothing open" 1
finding_says "--recorded with nothing open" "back to decide_first"

open solo3
at solo3 implementation implementation:1
attempt solo3 --result decided --chosen SQLite --state implementation:1
gate solo3
expect "a decided attempt" 0

open solo4
at solo4 implementation implementation:1
KOTO_RUN_MODE=unattended attempt solo4 --result provisional --chosen SQLite --undo cheap --undo-reason "the cache is local to this branch" --state implementation:1
gate solo4
expect "a provisional attempt" 0

open solo5
at solo5 implementation implementation:1
raise solo5 --content "$T/need.json" --state implementation:1
gate solo5
expect "an open need raised from the arrival, with no attempt" 3

open solo6
at solo6 implementation implementation:2
attempt solo6 --result decided --chosen SQLite --state implementation:1
gate solo6
expect "an attempt for an earlier arrival from the same origin" 1
attempt solo6 --result decided --chosen SQLite
gate solo6
expect "an attempt with no state" 1

open solo7
at solo7 implementation implementation:1
attempt solo3 --result decided --chosen SQLite --state implementation:1
gate solo7
expect "an attempt recorded in another session" 1

open pred
attempt pred --result decided --chosen SQLite --state implementation:1
open succ --continues pred
at succ implementation implementation:1
gate succ
expect "an attempt the predecessor recorded for the arrival it waited on" 1

open worker1 --dispatched-by manager
at worker1 implementation implementation:1
attempt worker1 --result undecided --state implementation:1
raise worker1 --content "$T/q.json" --attempt "$A" --state implementation:1
gate worker1
expect "a worker's open question to its dispatcher" 3
attempt worker1 --result decided --chosen SQLite --state implementation:1
gate worker1
expect "a deciding attempt beside the arrival's open question" 3
finding_says "a deciding attempt beside the arrival's open question" "is still open, so a deciding attempt can't take the run on"
manager_answers worker1 "$Q"
gate worker1
expect "once the question is answered, the deciding attempt counts" 0
open worker1b --dispatched-by manager
at worker1b implementation implementation:1
attempt worker1b --result undecided --state implementation:1
raise worker1b --content "$T/q.json" --attempt "$A" --state implementation:1
gate --record-question worker1b
gate --recorded worker1b
expect "--recorded while the worker's question is open" 0
manager_answers worker1b "$Q"
gate worker1b
expect "a question answered since" 1
gate --recorded worker1b
expect "--recorded once the question was answered since it was raised" 1
finding_says "--recorded once the question was answered since it was raised" "back to decide_first"

open worker2 --dispatched-by manager
at worker2 implementation implementation:1
attempt worker2 --result undecided --state implementation:1
raise worker2 --content "$T/q.json" --attempt "$A" --state implementation:1
"$SHIRABE" question withdraw "$Q" --in worker2 --reason "the dependency landed" > "$T/wd.out" 2>"$T/wd.err" \
    || fail "withdraw: $(cat "$T/wd.out" "$T/wd.err")"
gate worker2
expect "a question withdrawn since" 1

# koto failing, and a shirabe with no `question precedent`.
mkdir -p "$T/badkoto" "$T/oldshirabe"
printf '#!/bin/sh\necho "koto stand-in: unavailable" >&2\nexit 1\n' > "$T/badkoto/koto"
printf '#!/bin/sh\necho "error: unrecognized subcommand" >&2\nexit 2\n' > "$T/oldshirabe/shirabe"
chmod +x "$T/badkoto/koto" "$T/oldshirabe/shirabe"
G=$(PATH="$T/badkoto:$PATH" bash "$GATE" solo3 2>"$T/gate.err")
RC=$?
expect "koto failing" 2
G=$(PATH="$T/oldshirabe:$PATH" bash "$GATE" solo3 2>"$T/gate.err")
RC=$?
expect "a shirabe with no question precedent" 2
# koto failing only `context exists`: read as trouble, never as an absent key,
# so a continued run never routes as a fresh one; and failing only `context
# history`, which the arrivals are read from.
mkdir -p "$T/flakykoto" "$T/nohistory"
{
    echo '#!/bin/sh'
    echo 'if [ "$1 $2" = "context exists" ]; then echo "koto stand-in: store unreadable" >&2; exit 3; fi'
    printf 'exec "%s" "$@"\n' "$(command -v koto)"
} > "$T/flakykoto/koto"
{
    echo '#!/bin/sh'
    echo 'if [ "$1 $2" = "context history" ]; then echo "koto stand-in: log unreadable" >&2; exit 3; fi'
    printf 'exec "%s" "$@"\n' "$(command -v koto)"
} > "$T/nohistory/koto"
chmod +x "$T/flakykoto/koto" "$T/nohistory/koto"
G=$(PATH="$T/flakykoto:$PATH" bash "$GATE" --resume solo3 2>"$T/gate.err")
RC=$?
expect "--resume with koto context exists failing" 2
G=$(PATH="$T/nohistory:$PATH" bash "$GATE" --arrive solo3 2>"$T/gate.err")
RC=$?
expect "--arrive with koto context history failing" 2

# --- --laps -------------------------------------------------------------------------

open lap
arrive lap analysis
arrive lap implementation
arrive lap implementation
arrive lap implementation
gate --laps lap
expect "--laps at the third arrival from implementation" 0
arrive lap implementation
gate --laps lap
expect "--laps at the fourth" 1
finding_says "--laps at the fourth" "resume is refused"
put lap decide_origin analysis
gate --laps lap
expect "--laps after an agent's write of decide_origin" 1
koto next lap --with-data '{"done":"yes"}' --no-cleanup > "$T/tick.out" 2>"$T/tick.err" || fail "lap to end: $(cat "$T/tick.out" "$T/tick.err")"
open lap2 --continues lap
arrive lap2 implementation
gate --arrive lap2
[ "$RC:$G" = "0:implementation:6" ] && pass "a session continuing the run goes on counting: implementation:6" \
    || fail "--arrive in the successor printed [$G], exit $RC: $(cat "$T/gate.err")"
gate --laps lap2
expect "--laps in a session continuing the run counts the predecessor's laps" 1

# --- presenting: an owner question answered from a recorded prompt ---------------

mkdir -p "$ACCOUNT_HOME/.claude/projects" || { fail "cannot make $ACCOUNT_HOME/.claude/projects"; finish; }
RECORDS=$(mktemp -d "$ACCOUNT_HOME/.claude/projects/shirabe-decide-first-gate-test.XXXXXX") \
    || { fail "mktemp under the account's .claude/projects failed"; finish; }
harness_id() {
    od -An -N16 -tx1 /dev/urandom | tr -d ' \n' \
        | sed 's/^\(........\)\(....\)\(....\)\(....\)\(............\)$/\1-\2-\3-\4-\5/'
}
# record <render file> <harness id> <label picked>: the harness record of a
# question-tool call showing the rendered question and the owner's pick.
record() {
    jq -c --slurpfile r "$1" --arg h "$2" --arg pick "$3" \
        --arg now "$(date -u +%Y-%m-%dT%H:%M:%S.000Z)" '
        ($r[0].prompts[0].questions) as $qs
        | if .type == "assistant" then
              .message.content[0].input.questions = $qs
              | .wireToolInputs["toolu_ZQXMARKERcall000000000001"].questions = $qs
          else
              .toolUseResult.questions = $qs
              | .toolUseResult.answers = {($qs[0].question): $pick}
          end
        | .timestamp = $now | .session_id = $h | .sessionId = $h' "$FIXTURE" > "$RECORDS/$2.jsonl"
}

open solo8
at solo8 analysis analysis:1
attempt solo8 --result undecided --state analysis:1
raise solo8 --content "$T/q.json" --attempt "$A" --state analysis:1
Q_SOLO8=$Q
gate solo8
expect "presenting: before the answer" 3
"$SHIRABE" question render "$Q_SOLO8" > "$T/render.out" 2>"$T/render.err" || fail "render: $(cat "$T/render.err")"
sleep 1
H=$(harness_id)
record "$T/render.out" "$H" SQLite
CLAUDE_CODE_SESSION_ID="$H" "$SHIRABE" question answer "$Q_SOLO8" --in manager > "$T/answer.out" 2>"$T/answer.err"
RC=$?
OWNER_ANS="$(jq -r '.session // empty' "$T/answer.out"):$(jq -r '.id // empty' "$T/answer.out")"
if [ "$RC" -eq 0 ] && [ "$(jq -r '.reading' "$T/answer.out")" = verified ]; then
    pass "presenting: the recorded prompt's answer reads verified"
else
    fail "presenting: answer exited $RC: $(cat "$T/answer.out" "$T/answer.err")"
fi
gate solo8
expect "presenting: after the answer, raised holds" 1
attempt solo8 --result decided --chosen SQLite --basis "$OWNER_ANS" --state analysis:1
gate solo8
expect "presenting: once an attempt cites the answer" 0

open solo9
at solo9 deferral_approval deferral_approval:1
attempt solo9 --result undecided --state deferral_approval:1
raise solo9 --content "$T/q.json" --attempt "$A" --state deferral_approval:1
Q_SOLO9=$Q
"$SHIRABE" question render "$Q_SOLO9" > "$T/render.out" 2>"$T/render.err" || fail "render: $(cat "$T/render.err")"
sleep 1
H=$(harness_id)
record "$T/render.out" "$H" SQLite
CLAUDE_CODE_SESSION_ID="$H" "$SHIRABE" question answer "$Q_SOLO9" --in manager > "$T/answer.out" 2>"$T/answer.err" \
    || fail "the owner's answer to $Q_SOLO9: $(cat "$T/answer.out" "$T/answer.err")"
OWNER9="$(jq -r '.session // empty' "$T/answer.out"):$(jq -r '.id // empty' "$T/answer.out")"
attempt solo9 --result decided --chosen "defer it" --basis "$OWNER9" --state deferral_approval:1
gate --approval solo9
expect "--approval citing the owner's verified answer to the question raised for the arrival" 0

# --- --approval ---------------------------------------------------------------------

open worker3 --dispatched-by manager
at worker3 deferral_approval deferral_approval:1
gate --approval worker3
expect "--approval with no attempt" 1
attempt worker3 --result decided --chosen "defer it" --state deferral_approval:1
gate --approval worker3
expect "--approval with a deciding attempt that cites no answer" 1
at worker3 deferral_approval deferral_approval:2
attempt worker3 --result undecided --state deferral_approval:2
raise worker3 --content "$T/q.json" --attempt "$A" --state deferral_approval:2
manager_answers worker3 "$Q"
WORKER3_ANS="manager:$ANS"
attempt worker3 --result decided --chosen "defer it" --basis "$WORKER3_ANS" --state deferral_approval:2
gate --approval worker3
expect "--approval citing the dispatcher's answer to the question raised for the arrival" 0
tick worker3 '{"clear":"yes"}'
gate --approval worker3
expect "--approval once a new deferral cleared the arrival" 1
finding_says "--approval once a new deferral cleared the arrival" "needs_answer"
put worker3 decide_arrival deferral_approval:2
gate --approval worker3
expect "--approval after an agent writes the cleared arrival back" 1

# Another session's question under the same arrival name, answered by its
# dispatcher, approves nothing here.
open aux --dispatched-by manager
at aux deferral_approval deferral_approval:1
attempt aux --result undecided --state deferral_approval:1
raise aux --content "$T/q.json" --attempt "$A" --state deferral_approval:1
manager_answers aux "$Q"
open worker6 --dispatched-by manager
at worker6 deferral_approval deferral_approval:1
attempt worker6 --result decided --chosen "defer it" --state deferral_approval:1 --basis "manager:$ANS"
gate --approval worker6
expect "--approval citing the answer to another session's question" 1
finding_says "--approval citing the answer to another session's question" "no question is raised for deferral_approval:1"

# koto passes a question up only to a person or the recording session's
# dispatcher: a session outside the dispatch chain cannot be made to answer it.
open scratch
open worker7 --dispatched-by manager
at worker7 deferral_approval deferral_approval:1
attempt worker7 --result undecided --state deferral_approval:1
raise worker7 --content "$T/q.json" --attempt "$A" --state deferral_approval:1
koto decisions readdress --in=worker7 --to=session:scratch --by=session --reason "a scratch session" -- worker7 "${Q##*/}" > "$T/readdress.out" 2>"$T/readdress.err"
RC=$?
[ "$RC" -ne 0 ] && grep -q 'invalid_decision' "$T/readdress.out" "$T/readdress.err" \
    && pass "koto refuses to pass a question to a session that is not the dispatcher" \
    || fail "readdress to scratch exited $RC: $(cat "$T/readdress.out" "$T/readdress.err")"

# A dispatcher named only after the question was raised: koto then lets the
# question pass to it and lets it answer, and the gate counts nothing.
open late
at late deferral_approval deferral_approval:1
attempt late --result undecided --state deferral_approval:1
raise late --content "$T/q.json" --attempt "$A" --state deferral_approval:1
Q_LATE=$Q
koto session link late --dispatched-by manager > "$T/link.out" 2>"$T/link.err" || fail "link late: $(cat "$T/link.out" "$T/link.err")"
koto decisions readdress --in=late --to=session:manager --by=session --reason "the manager decides" -- late "${Q_LATE##*/}" > "$T/readdress.out" 2>"$T/readdress.err" \
    || fail "readdress late to manager: $(cat "$T/readdress.out" "$T/readdress.err")"
manager_answers late "$Q_LATE"
attempt late --result decided --chosen "defer it" --basis "manager:$ANS" --state deferral_approval:1
gate --approval late
expect "--approval citing a dispatcher linked after the question was raised" 1
finding_says "--approval citing a dispatcher linked after the question was raised" "approves nothing"

# A run continued under a different dispatcher than the one it raised under:
# the raiser's dispatcher's answer counts only across a lineage that names it.
open wa --dispatched-by manager
at wa deferral_approval deferral_approval:1
attempt wa --result undecided --state deferral_approval:1
raise wa --content "$T/q.json" --attempt "$A" --state deferral_approval:1
Q_WA=$Q
manager_answers wa "$Q_WA"
ANS_WA="manager:$ANS"
open wb --continues wa --dispatched-by scratch
put wb decide_question "$Q_WA"
attempt wb --result decided --chosen "defer it" --basis "$ANS_WA" --state deferral_approval:1
gate --approval wb
expect "--approval in a successor linked to a different dispatcher" 1
finding_says "--approval in a successor linked to a different dispatcher" "approves nothing"
open wd --dispatched-by manager
at wd deferral_approval deferral_approval:1
attempt wd --result undecided --state deferral_approval:1
raise wd --content "$T/q.json" --attempt "$A" --state deferral_approval:1
Q_WD=$Q
manager_answers wd "$Q_WD"
open we --continues wd --dispatched-by manager
put we decide_question "$Q_WD"
attempt we --result decided --chosen "defer it" --basis "manager:$ANS" --state deferral_approval:1
gate --approval we
expect "--approval in a successor linked to the same dispatcher" 0

# A settle approves only on a person's answer in its basis.
open solo10
at solo10 deferral_approval deferral_approval:1
attempt solo10 --result undecided --state deferral_approval:1
raise solo10 --content "$T/q.json" --attempt "$A" --state deferral_approval:1
settle solo10 "$Q" "$WORKER3_ANS"
attempt solo10 --result decided --chosen "defer it" --basis "solo10:$SET" --state deferral_approval:1
gate --approval solo10
expect "--approval citing a settle whose basis is a session's answer" 1
open solo11
at solo11 deferral_approval deferral_approval:1
attempt solo11 --result undecided --state deferral_approval:1
raise solo11 --content "$T/q.json" --attempt "$A" --state deferral_approval:1
settle solo11 "$Q" "$OWNER9"
attempt solo11 --result decided --chosen "defer it" --basis "solo11:$SET" --state deferral_approval:1
gate --approval solo11
expect "--approval citing a settle whose basis is the owner's verified answer" 0

# koto's own refusals: the run answering itself, and a person's answer with
# no prompt evidence.
open worker8 --dispatched-by manager
at worker8 deferral_approval deferral_approval:1
attempt worker8 --result undecided --state deferral_approval:1
raise worker8 --content "$T/q.json" --attempt "$A" --state deferral_approval:1
koto decisions answer --in=worker8 --text=Defer --by=session -- worker8 "${Q##*/}" > "$T/self.out" 2>"$T/self.err"
RC=$?
[ "$RC" -ne 0 ] && grep -q '"field":"in"' "$T/self.out" "$T/self.err" && pass "koto refuses an answer the run records for its own question" \
    || fail "a self-answer exited $RC: $(cat "$T/self.out" "$T/self.err")"
koto decisions answer --in=manager --text=Defer --by=person:owner -- worker8 "${Q##*/}" > "$T/person.out" 2>"$T/person.err"
RC=$?
[ "$RC" -ne 0 ] && grep -q '"field":"prompt"' "$T/person.out" "$T/person.err" && pass "koto refuses a person's answer with no prompt evidence" \
    || fail "an unproven person answer exited $RC: $(cat "$T/person.out" "$T/person.err")"

# --- --resume -----------------------------------------------------------------------

mkdir -p "$T/logbin"
printf '#!/bin/sh\necho "$*" >> "%s/shirabe.log"\nexec "%s" "$@"\n' "$T" "$SHIRABE" > "$T/logbin/shirabe"
chmod +x "$T/logbin/shirabe"
open fresh
: > "$T/shirabe.log"
G=$(PATH="$T/logbin:$PATH" bash "$GATE" --resume fresh 2>"$T/gate.err")
RC=$?
expect "--resume in a run that continues none" 0
[ -s "$T/shirabe.log" ] && fail "--resume in a fresh run called shirabe: $(cat "$T/shirabe.log")" || pass "--resume in a fresh run makes no shirabe call"

open worker4 --dispatched-by manager
at worker4 implementation implementation:1
attempt worker4 --result undecided --state implementation:1
raise worker4 --content "$T/q.json" --attempt "$A" --state implementation:1
Q4=$Q
open worker4b --continues worker4 --dispatched-by manager
put worker4b decide_question "$Q4"
gate --resume worker4b
expect "--resume while the question is open" 1
finding_says "--resume while the question is open" "still open"
manager_answers worker4 "$Q4"
gate --resume worker4b
expect "--resume with the answer not cited" 1
finding_says "--resume with the answer not cited" "is not cited yet"
attempt worker4b --result decided --chosen SQLite --basis "manager:$ANS"
gate --resume worker4b
expect "--resume once a deciding attempt cites the answer (implementation)" 11

open worker5 --dispatched-by manager
at worker5 analysis analysis:1
attempt worker5 --result undecided --state analysis:1
raise worker5 --content "$T/q.json" --attempt "$A" --state analysis:1
Q5=$Q
"$SHIRABE" question withdraw "$Q5" --in worker5 --reason "the dependency landed" > "$T/wd.out" 2>"$T/wd.err" \
    || fail "withdraw: $(cat "$T/wd.out" "$T/wd.err")"
open worker5b --continues worker5
put worker5b decide_question "$Q5"
gate --resume worker5b
expect "--resume after the question was withdrawn" 1

finish
