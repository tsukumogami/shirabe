#!/usr/bin/env bash
# question-ladder_engine_test.sh -- a question going up the coordinator ladder
# by its identity, against the real koto and the branch's shirabe: pass-up,
# the unseen owner answers, seen, settle on the owner's precedent, and a
# relayed claim recorded as the coordinator's own word.
#
# Five sessions of a two-state template: director, manager (dispatched by
# director), and w1, w2, w3 (dispatched by manager), so koto's origin gives
# each worker manager as its dispatcher and manager director.
#
# An owner's answer comes from a recorded harness session, never a live
# prompt, as scripts/question-commands_test.sh records one: a record built
# from scripts/fixtures/question-commands/accepted.jsonl with the rendered
# question in it, in a folder of its own under .claude/projects/ in the
# account's home as the user database gives it (koto reads it there), removed
# at exit.
#
# Cases:
#   pass-up: w1's decision question passed up by manager is refused with no
#     attempt and with w1's own attempt, nothing recorded; with manager's
#     undecided attempt tied to it, it goes to director; pending at director
#     lists it once, and pending at manager marks it passed_up
#   a need addressed to manager (recorded with koto decisions record) is
#     refused with an attempt and passes up to director with none
#   unseen: the owner's answer to w3's question, given in w1, is listed unseen
#     at manager; seen records one judgment, empties manager's listing while
#     director's still shows it, and leaves koto decisions show's bytes as
#     they were; a second seen adds nothing
#   precedent: w2's question with the same label, addressed to manager, has
#     the owner's answer as its precedent (koto decisions precedent --person
#     owner --chain manager --label cache); settle with that basis closes it
#     and it leaves koto decisions open --at manager
#   relayed: settle --owner-note on a question addressed to manager is
#     recorded as manager's, and precedent doesn't return it; on a question
#     waiting on person:owner it is refused and the question stays open
#
# Not here: a leg whose result payload names a question identity waiting
# until koto shows that question closed. wait-target_test.sh proves its
# disposition from fixtures (testdata/waiting-leg/); a leg through real koto
# needs a whole coordinate run, which this suite doesn't open.
#
# Usage: bash skills/coordinate/scripts/question-ladder_engine_test.sh
#   koto 0.42.0 or later and jq on PATH; shirabe from SHIRABE_BIN, else the
#   tree's target/release/shirabe, else PATH, and it must have `question
#   pass-up`. SKIPs (exit 0) without koto, which run-tests.sh --engine turns
#   into a failure; fails without such a shirabe.
#
# bash 3.2 floor: no associative arrays, no namerefs, no mapfile.

set -uo pipefail
. "$(dirname "$0")/../../../scripts/lib/koto-test-guard.sh" || exit 1

# The suite stands in for an attended harness session: a run mode inherited
# from the session running it would refuse every answer before koto checks it.
unset KOTO_RUN_MODE CLAUDE_CODE_SESSION_ATTENDED CLAUDE_CONFIG_DIR

HERE=$(cd "$(dirname "$0")" && pwd)
REPO=$(cd "$HERE/../../.." && pwd)
FIXTURE="$REPO/scripts/fixtures/question-commands/accepted.jsonl"

PASS=0
FAIL=0
pass() { printf 'PASS: %s\n' "$*"; PASS=$((PASS + 1)); }
fail() { printf 'FAIL: %s\n' "$*"; FAIL=$((FAIL + 1)); }
finish() {
    echo
    echo "question-ladder_engine_test.sh: $PASS passed, $FAIL failed"
    [ "$FAIL" -eq 0 ]
    exit $?
}

command -v koto > /dev/null 2>&1 || { echo "SKIP: koto not on PATH -- the engine cases did not run"; exit 0; }
command -v jq > /dev/null 2>&1 || { fail "jq is not on PATH"; finish; }

SHIRABE=""
if [ -n "${SHIRABE_BIN:-}" ] && [ -x "$SHIRABE_BIN" ]; then SHIRABE=$SHIRABE_BIN
elif [ -x "$REPO/target/release/shirabe" ]; then SHIRABE="$REPO/target/release/shirabe"
else SHIRABE=$(command -v shirabe); fi
T=$(mktemp -d "${TMPDIR:-/tmp}/question-ladder-test.XXXXXX") || { fail "mktemp failed"; finish; }
ACCOUNT_HOME=$(eval echo "~$(id -un)")
RECORDS=""
cleanup() {
    [ -n "${T:-}" ] && rm -rf "$T"
    [ -n "$RECORDS" ] && rm -rf "$RECORDS"
    return 0
}
ktg_on_exit cleanup

if [ -z "$SHIRABE" ] || ! "$SHIRABE" question pass-up --help > /dev/null 2> "$T/probe.err"; then
    fail "no shirabe with \`question pass-up\` (SHIRABE_BIN, target/release/shirabe or PATH); build the branch's (cargo build --release): $(head -n 2 "$T/probe.err")"
    finish
fi

# koto's store under the scratch tree; the harness records stay where koto
# reads them, in the account's home.
export HOME="$T/home"
mkdir -p "$HOME" "$T/ws" || { fail "cannot make the scratch tree"; finish; }
cd "$T/ws" || { fail "cd $T/ws"; finish; }

cat > "$T/two.md" <<'EOF'
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
        required: true
    transitions:
      - target: end
        when:
          done: yes
  end:
    terminal: true
---

## work

Do the work.

## end

Done.
EOF
start() { # start <session> [koto init flags...]
    local s=$1
    shift
    koto init "$s" --template "$T/two.md" "$@" > /dev/null 2> "$T/init.err" || { fail "koto init $s: $(cat "$T/init.err")"; finish; }
}
start director
start manager --dispatched-by director
for w in w1 w2 w3; do start "$w" --dispatched-by manager; done

# --- helpers -----------------------------------------------------------------

# content <file> <label> <question>
content() {
    jq -n --arg label "$2" --arg q "$3" '{
        context: "The build cache is lost on every runner restart.",
        problem: "Two stores fit, and they differ in what an operator has to run.",
        question: $q,
        options: [
            {label: "SQLite", reason: "One file beside the runner, no server to run."},
            {label: "Postgres", reason: "Shared across runners, but a server to keep up."}
        ],
        ground: "Picking a server changes what the team operates.",
        waiting: [],
        label: $label
    }' > "$1"
}
# attempt <session> -> an undecided attempt's id, recorded with koto
attempt() {
    koto decisions record "$1" --kind judgment --outcome settled \
        --subject what="which store" --subject result=undecided --by session > "$T/att.json" 2> "$T/att.err" || return 1
    jq -r '.id // empty' "$T/att.json"
}
# raise <session> <label> <question> [more args...]: QID the identity, QN its
# decision id; RC the exit, output in $T/raise.out
raise() {
    local s=$1 l=$2 q=$3 a
    shift 3
    QID= QN=
    content "$T/c.json" "$l" "$q"
    a=$(attempt "$s") || { fail "an attempt in $s: $(cat "$T/att.err")"; return 1; }
    "$SHIRABE" question raise --in "$s" --content "$T/c.json" --attempt "$a" "$@" > "$T/raise.out" 2> "$T/raise.err"
    RC=$?
    [ "$RC" -eq 0 ] || { fail "raise in $s exited $RC: $(cat "$T/raise.out" "$T/raise.err")"; return 1; }
    QID=$(jq -r '.identity' "$T/raise.out")
    QN=$(jq -r '.id' "$T/raise.out")
}
# run <name> <args...>: shirabe, output in $T/<name>.out, exit in RC
run() {
    local n=$1
    shift
    "$SHIRABE" "$@" > "$T/$n.out" 2> "$T/$n.err"
    RC=$?
}
# history <identity>: koto's history of it in $T/history.json
history() { koto decisions history "$1" > "$T/history.json" 2> "$T/history.err" || { fail "koto decisions history $1: $(cat "$T/history.err")"; return 1; }; }
addressee() { history "$1" && jq -r '.addressee | "\(.kind):\(.name // .handle)"' "$T/history.json"; }
pending() { # pending <session>: shirabe question pending --in <session> into $T/pending-<session>.json
    "$SHIRABE" question pending --in "$1" > "$T/pending-$1.json" 2> "$T/pending.err" \
        || { fail "pending --in $1: $(cat "$T/pending.err")"; return 1; }
}

harness_id() {
    od -An -N16 -tx1 /dev/urandom | tr -d ' \n' \
        | sed 's/^\(........\)\(....\)\(....\)\(....\)\(............\)$/\1-\2-\3-\4-\5/'
}
# answer <identity> <label picked> <session>: the owner's answer from a
# recorded harness session, given in <session>; output in $T/answer.out
answer() {
    local h now
    if [ -z "$RECORDS" ]; then
        mkdir -p "$ACCOUNT_HOME/.claude/projects" || { fail "cannot make $ACCOUNT_HOME/.claude/projects"; return 1; }
        RECORDS=$(mktemp -d "$ACCOUNT_HOME/.claude/projects/shirabe-question-ladder-test.XXXXXX") \
            || { RECORDS=; fail "mktemp under the account's .claude/projects failed"; return 1; }
    fi
    "$SHIRABE" question render "$1" > "$T/render.out" 2> "$T/render.err" || { fail "render $1: $(cat "$T/render.err")"; return 1; }
    # The call must come no earlier than the question was raised.
    sleep 1
    h=$(harness_id)
    now=$(date -u +%Y-%m-%dT%H:%M:%S.000Z)
    jq -c --slurpfile r "$T/render.out" --arg h "$h" --arg pick "$2" --arg now "$now" '
        ($r[0].prompts[0].questions) as $qs
        | if .type == "assistant" then
              .message.content[0].input.questions = $qs
              | .wireToolInputs["toolu_ZQXMARKERcall000000000001"].questions = $qs
          else
              .toolUseResult.questions = $qs
              | .toolUseResult.answers = {($qs[0].question): $pick}
          end
        | .timestamp = $now | .session_id = $h | .sessionId = $h' "$FIXTURE" > "$RECORDS/$h.jsonl" \
        || { fail "cannot write the harness record"; return 1; }
    CLAUDE_CODE_SESSION_ID="$h" "$SHIRABE" question answer "$1" --in "$3" > "$T/answer.out" 2> "$T/answer.err"
    RC=$?
    [ "$RC" -eq 0 ] || { fail "answer $1 in $3 exited $RC: $(cat "$T/answer.out" "$T/answer.err")"; return 1; }
}

# --- pass-up -----------------------------------------------------------------

raise w1 store "Which store should the build cache use?" || finish
Q1=$QID Q1N=$QN
[ "$(addressee "$Q1")" = session:manager ] && pass "w1's question waits on manager, its dispatcher" \
    || fail "w1's question waits on $(addressee "$Q1")"

run passup question pass-up "$Q1" --in manager --ground changes-scope
history "$Q1"
if [ "$RC" -eq 1 ] && [ "$(jq '[(.entries // [])[] | select(.entry == "pass-up")] | length' "$T/history.json")" = 0 ] \
    && [ "$(addressee "$Q1")" = session:manager ]; then
    pass "a pass-up with no attempt is refused (exit 1) and koto records nothing"
else
    fail "pass-up with no attempt exited $RC: $(cat "$T/passup.out" "$T/passup.err")"
fi

# The raiser's own attempt is not the passing session's.
koto decisions attempts --in=w1 --question "$Q1" > "$T/w1att.json" 2> "$T/att.err" || fail "koto decisions attempts --in=w1: $(cat "$T/att.err")"
W1ATT=$(jq -r '.attempts[0].id // empty' "$T/w1att.json")
run passup question pass-up "$Q1" --in manager --ground changes-scope --attempt "w1:$W1ATT"
if [ -n "$W1ATT" ] && [ "$RC" -eq 1 ] && [ "$(addressee "$Q1")" = session:manager ]; then
    pass "a pass-up resting on the raiser's attempt is refused (exit 1), the question where it was"
else
    fail "pass-up with w1's attempt exited $RC: $(cat "$T/passup.out" "$T/passup.err")"
fi

run attempt question attempt --in manager --what "which store the build cache uses" --result undecided --basis "w1:$Q1N"
MA=$(jq -r '.id // empty' "$T/attempt.out")
[ "$RC" -eq 0 ] && [ -n "$MA" ] || { fail "manager's attempt exited $RC: $(cat "$T/attempt.out" "$T/attempt.err")"; finish; }
run passup question pass-up "$Q1" --in manager --ground changes-scope --attempt "$MA"
if [ "$RC" -eq 0 ] && [ "$(jq -r '.to' "$T/passup.out")" = session:director ] && [ "$(addressee "$Q1")" = session:director ]; then
    pass "with manager's own undecided attempt the question passes up to director, keeping its identity"
else
    fail "pass-up with manager's attempt exited $RC: $(cat "$T/passup.out" "$T/passup.err")"
fi

pending director && N=$(jq --arg q "$Q1" '[.questions[], .held[] | select(.identity == $q)] | length' "$T/pending-director.json")
[ "${N:-}" = 1 ] && pass "pending at director lists the question once" || fail "pending at director lists it ${N:-?} times"
pending manager && PU=$(jq -r --arg q "$Q1" '[.questions[], .held[] | select(.identity == $q) | .passed_up] | first // "unlisted"' "$T/pending-manager.json")
[ "${PU:-}" = true ] && pass "pending at manager marks it passed_up" || fail "pending at manager: passed_up ${PU:-?}"

# --- a need ------------------------------------------------------------------

koto decisions record w2 --kind escalate --outcome escalated --subject question=q --subject "text=A deploy token for the staging cluster" \
    --subject recipient=session:manager --subject label=staging-token --subject need=credential --by session > "$T/need.json" 2> "$T/need.err" \
    || { fail "koto records w2's need: $(cat "$T/need.err")"; finish; }
# Its identity: the raiser's session id, then the decision id.
NEED="$(jq -r '.decision.session.id // empty' "$T/need.json")/$(jq -r '.id // empty' "$T/need.json")"
case "$NEED" in /*|*/) fail "koto printed no identity for w2's need: $(cat "$T/need.json")"; finish ;; esac
run passup question pass-up "$NEED" --in manager --ground outward-facing --attempt "$MA"
if [ "$RC" -eq 1 ] && [ "$(addressee "$NEED")" = session:manager ]; then
    pass "a need passed up with an attempt is refused (exit 1)"
else
    fail "a need's pass-up with an attempt exited $RC: $(cat "$T/passup.out" "$T/passup.err")"
fi
run passup question pass-up "$NEED" --in manager --ground outward-facing
if [ "$RC" -eq 0 ] && [ "$(jq -r '.attempt' "$T/passup.out")" = null ] && [ "$(addressee "$NEED")" = session:director ]; then
    pass "a need passes up to director with no attempt"
else
    fail "a need's pass-up exited $RC: $(cat "$T/passup.out" "$T/passup.err")"
fi

# --- unseen and seen ---------------------------------------------------------

raise w3 cache "Which store should the shared cache use?" --to person:owner || finish
Q3=$QID
answer "$Q3" SQLite w1 || finish
ANS="$(jq -r '.session' "$T/answer.out"):$(jq -r '.id' "$T/answer.out")"
ANS_ID=${ANS#*:}
pending manager
if jq -e --arg a "$ANS" --arg q "$Q3" 'any(.unseen[]; .answer == $a and .identity == $q)' "$T/pending-manager.json" > /dev/null; then
    pass "the owner's answer given in w1 is listed unseen at manager"
else
    fail "manager's unseen: $(jq -c .unseen "$T/pending-manager.json")"
fi
koto decisions show w1 "$ANS_ID" > "$T/show-before.json" 2> "$T/show.err" || fail "koto decisions show w1 $ANS_ID: $(cat "$T/show.err")"
koto decisions list manager --format v1 > "$T/list-before.json" 2> "$T/list.err" || fail "koto decisions list manager: $(cat "$T/list.err")"
run seen question seen "$ANS" --in manager
koto decisions list manager --format v1 > "$T/list-after.json" 2> "$T/list.err" || fail "koto decisions list manager: $(cat "$T/list.err")"
ADDED=$(( $(jq '.decisions | length' "$T/list-after.json") - $(jq '.decisions | length' "$T/list-before.json") ))
if [ "$RC" -eq 0 ] && [ "$(jq -r '.recorded' "$T/seen.out")" = true ] && [ "$(jq -r '.id' "$T/seen.out")" != null ] && [ "$ADDED" = 1 ]; then
    pass "seen records one judgment in manager"
else
    fail "seen exited $RC, $ADDED decisions added: $(cat "$T/seen.out" "$T/seen.err")"
fi
pending manager && pending director
if jq -e --arg a "$ANS" 'any(.unseen[]; .answer == $a) | not' "$T/pending-manager.json" > /dev/null \
    && jq -e --arg a "$ANS" 'any(.unseen[]; .answer == $a)' "$T/pending-director.json" > /dev/null; then
    pass "the answer leaves manager's unseen listing and stays in director's"
else
    fail "unseen at manager $(jq -c .unseen "$T/pending-manager.json"), at director $(jq -c .unseen "$T/pending-director.json")"
fi
koto decisions show w1 "$ANS_ID" > "$T/show-after.json" 2> "$T/show.err" || fail "koto decisions show w1 $ANS_ID: $(cat "$T/show.err")"
cmp -s "$T/show-before.json" "$T/show-after.json" && pass "koto decisions show prints the answer's bytes unchanged" \
    || fail "the answer changed: $(diff "$T/show-before.json" "$T/show-after.json" | head -5)"
cp "$T/list-after.json" "$T/list-before.json"
run seen question seen "$ANS" --in manager
koto decisions list manager --format v1 > "$T/list-after.json" 2> "$T/list.err" || fail "koto decisions list manager: $(cat "$T/list.err")"
if [ "$RC" -eq 0 ] && [ "$(jq -r '.id' "$T/seen.out")" = null ] && [ "$(jq -r '.recorded' "$T/seen.out")" = false ] \
    && cmp -s "$T/list-before.json" "$T/list-after.json"; then
    pass "a second seen adds nothing and exits 0"
else
    fail "second seen exited $RC: $(cat "$T/seen.out" "$T/seen.err")"
fi

# --- precedent and settle ----------------------------------------------------

raise w2 cache "Which store should the build cache use, now for w2?" || finish
Q2=$QID
koto decisions precedent --person owner --chain manager --label cache > "$T/precedent.json" 2> "$T/precedent.err" \
    || fail "koto decisions precedent: $(cat "$T/precedent.err")"
if jq -e --arg id "$ANS_ID" 'any(.answers[]; .id == $id and .session == "w1" and .text == "SQLite")' "$T/precedent.json" > /dev/null; then
    pass "precedent at manager for label cache prints the owner's answer"
else
    fail "precedent: $(cat "$T/precedent.json")"
fi
run settle question settle "$Q2" --in manager --chosen SQLite --reason "the owner chose SQLite for the cache" --basis "$ANS"
koto decisions open --at manager > "$T/open.json" 2> "$T/open.err" || fail "koto decisions open --at manager: $(cat "$T/open.err")"
if [ "$RC" -eq 0 ] && jq -e --arg q "$Q2" 'any(.questions[]; .identity == $q) | not' "$T/open.json" > /dev/null; then
    pass "settle on the owner's answer closes w2's question, which leaves manager's open list"
else
    fail "settle exited $RC: $(cat "$T/settle.out" "$T/settle.err")"
fi

# --- a relayed claim ---------------------------------------------------------

raise w2 runner "Which runner image should the deploy use?" || finish
QR=$QID
run settle question settle "$QR" --in manager --chosen SQLite --reason "relayed in chat" --owner-note "the owner said so in chat"
koto decisions precedent --person owner --chain manager --label runner > "$T/precedent.json" 2> "$T/precedent.err" \
    || fail "koto decisions precedent: $(cat "$T/precedent.err")"
if [ "$RC" -eq 0 ] && [ "$(jq '.answers | length' "$T/precedent.json")" = 0 ]; then
    pass "settle --owner-note is manager's own word: precedent doesn't return it"
else
    fail "settle --owner-note exited $RC, precedent $(cat "$T/precedent.json"): $(cat "$T/settle.out" "$T/settle.err")"
fi

raise w3 deploy "Which deploy window should the release use?" --to person:owner || finish
QO=$QID
run settle question settle "$QO" --in manager --chosen "Friday" --reason "relayed in chat" --owner-note "the owner said Friday"
history "$QO"
if [ "$RC" -eq 1 ] && [ "$(jq -r '.open' "$T/history.json")" = true ]; then
    pass "settle --owner-note on a question waiting on person:owner is refused (exit 1), the question still open"
else
    fail "settle --owner-note to the owner's question exited $RC: $(cat "$T/settle.out" "$T/settle.err")"
fi

finish
