#!/usr/bin/env bash
# question-commands_test.sh -- `shirabe question raise`, `pending`, `render`
# and `answer` against the real koto.
#
# The Rust suites (crates/shirabe/tests/question_*.rs) drive the commands
# against a koto stand-in. This one runs them against the koto on PATH, so
# what koto itself decides is exercised: the recipient a session's origin
# gives, the attempt basis, the twenty-question limit, and the checks koto
# makes of a question prompt before it records the owner's answer.
#
# An owner's answer here comes from a recorded harness session, never a live
# prompt: each case writes a record built from
# scripts/fixtures/question-commands/accepted.jsonl (a copy of koto's own
# fixture) with the rendered question put in it, the way the harness records
# a question-tool call and its reply. koto reads that record from
# .claude/projects/ in the account's home as the system's user database gives
# it, so the records go in a folder of their own there,
# shirabe-question-commands-test.*, removed at exit.
#
# Cases:
#   every `shirabe question` subcommand the procedure and the guide name
#     answers --help, and the procedure says "escalat" only in code
#   a decision question without an attempt is refused; with one, it is
#     raised to person:owner from a session nothing dispatched and to the
#     dispatcher from a dispatched one, and its packet is koto's
#   pending lists the dispatched session's question at the dispatcher and the
#     owner's questions, each once, and writes nothing
#   render prints the same bytes from another directory under env -i, and its
#     header is koto's prompt_header
#   an answered prompt is recorded as the owner's, reads verified and is
#     listed under answered until a decision cites it
#   a prompt whose question text, option label or reply differs is refused
#     with koto's check named, and the question stays open
#   a twenty-first question for the owner is refused by koto
#
# Usage: bash scripts/question-commands_test.sh
#   shirabe from PATH, or SHIRABE_BIN; koto 0.42.0 or later on PATH; jq.
#
# Exit codes:
#   0 -- all cases pass
#   1 -- one or more cases failed, or a tool is missing
#
# bash 3.2 floor: no associative arrays, no namerefs, no mapfile.

set -uo pipefail
. "$(dirname "$0")/../scripts/lib/koto-test-guard.sh" || exit 1

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
REPO=$(cd "$SCRIPT_DIR/.." && pwd)
FIXTURE="$REPO/scripts/fixtures/question-commands/accepted.jsonl"

PASS_COUNT=0
FAIL_COUNT=0
pass() { printf 'PASS: %s\n' "$*"; PASS_COUNT=$((PASS_COUNT + 1)); }
fail() { printf 'FAIL: %s\n' "$*"; FAIL_COUNT=$((FAIL_COUNT + 1)); }
finish() {
    echo
    echo "question-commands_test.sh: $PASS_COUNT passed, $FAIL_COUNT failed"
    [ "$FAIL_COUNT" -eq 0 ]
    exit $?
}

SHIRABE=$(command -v shirabe 2>/dev/null)
case "$SHIRABE" in /*) ;; *) SHIRABE="${SHIRABE_BIN:-}" ;; esac
if [ -z "$SHIRABE" ] || [ ! -x "$SHIRABE" ]; then
    fail "no shirabe on PATH (or in SHIRABE_BIN); put target/release first (cargo build --release)"
    finish
fi
for tool in koto jq; do
    command -v "$tool" >/dev/null 2>&1 || { fail "$tool is not on PATH"; finish; }
done

T=$(mktemp -d "${TMPDIR:-/tmp}/question-commands-test.XXXXXX") || { fail "mktemp failed"; finish; }
ACCOUNT_HOME=$(eval echo "~$(id -un)")
RECORDS=""
cleanup() {
    [ -n "${T:-}" ] && rm -rf "$T"
    [ -n "$RECORDS" ] && rm -rf "$RECORDS"
    return 0
}
ktg_on_exit cleanup

# --- documents name only subcommands that exist -----------------------------

docs_ok=1
for doc in references/question-procedure.md docs/guides/question-commands.md; do
    for sub in $(grep -o 'shirabe question [a-z-]*' "$REPO/$doc" | awk '{print $3}' | sort -u); do
        if ! "$SHIRABE" question "$sub" --help >/dev/null 2>&1; then
            fail "$doc names \`shirabe question $sub\`, which answers --help with an error"
            docs_ok=0
        fi
    done
done
[ "$docs_ok" -eq 1 ] && pass "every shirabe question subcommand the procedure and the guide name answers --help"

if sed 's/`[^`]*`//g' "$REPO/references/question-procedure.md" | grep -qi 'escalat'; then
    fail "references/question-procedure.md says escalat outside a code span"
else
    pass "the procedure says escalat only inside code"
fi

# --- sessions ----------------------------------------------------------------

cd "$T" || { fail "cd $T"; finish; }
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
for s in manager solo many; do
    koto init "$s" --template "$T/two.md" >/dev/null 2>"$T/init.err" || { fail "koto init $s: $(cat "$T/init.err")"; finish; }
done
koto init worker --template "$T/two.md" --dispatched-by manager >/dev/null 2>"$T/init.err" \
    || { fail "koto init worker: $(cat "$T/init.err")"; finish; }

# content <file> <label> [question]
content() {
    jq -n --arg label "$2" --arg q "${3:-Which store should the build cache use?}" '{
        context: "The build cache is lost on every runner restart.",
        problem: "Two stores fit, and they differ in what an operator has to run.",
        question: $q,
        options: [
            {label: "SQLite", reason: "One file beside the runner, no server to run."},
            {label: "Postgres", reason: "Shared across runners, but a server to keep up."}
        ],
        ground: "Picking a server changes what the team operates.",
        waiting: ["issue-12"],
        label: $label
    }' > "$1"
}

# attempt <session> -> the undecided attempt's id
attempt() {
    koto decisions record "$1" --kind judgment --outcome settled \
        --subject what="which store" --subject result=undecided --by session 2>"$T/att.err" \
        | jq -r '.id // .decision.id // empty'
}

# raise <session> <content file> [more args...] -> output in $T/raise.out, exit in $RC
raise() {
    local s=$1 c=$2
    shift 2
    "$SHIRABE" question raise --in "$s" --content "$c" "$@" >"$T/raise.out" 2>"$T/raise.err"
    RC=$?
}

# --- raise -------------------------------------------------------------------

content "$T/c1.json" "build cache store"
raise solo "$T/c1.json"
if [ "$RC" -eq 1 ] && jq -e '.error.code' "$T/raise.out" >/dev/null 2>&1; then
    pass "a decision question without an attempt is refused before koto records it (exit 1)"
else
    fail "raise without --attempt exited $RC: $(cat "$T/raise.out" "$T/raise.err")"
fi

A_SOLO=$(attempt solo)
[ -n "$A_SOLO" ] || { fail "koto decisions record printed no id: $(cat "$T/att.err")"; finish; }
raise solo "$T/c1.json" --attempt "$A_SOLO"
Q_SOLO=$(jq -r '.identity // empty' "$T/raise.out" 2>/dev/null)
if [ "$RC" -eq 0 ] && [ "$(jq -r '.recipient' "$T/raise.out")" = "person:owner" ]; then
    pass "a session nothing dispatched raises to person:owner ($Q_SOLO)"
else
    fail "raise in solo exited $RC: $(cat "$T/raise.out" "$T/raise.err")"
    finish
fi
SOLO_ID=$(jq -r '.id' "$T/raise.out")
SOLO_HEADER=$(jq -r '.prompt_header' "$T/raise.out")
SHOW_PACKET=$(koto decisions show solo "$SOLO_ID" 2>/dev/null | jq -r '.decision.subject.packet // .packet // empty')
if [ -n "$SHOW_PACKET" ] && [ "$SHOW_PACKET" = "$(jq -r '.packet' "$T/raise.out")" ]; then
    pass "the packet raise prints is the one koto holds"
else
    fail "raise printed packet $(jq -r '.packet' "$T/raise.out"), koto shows [$SHOW_PACKET]"
fi

content "$T/c2.json" "worker store"
A_WORKER=$(attempt worker)
raise worker "$T/c2.json" --attempt "$A_WORKER"
Q_WORKER=$(jq -r '.identity // empty' "$T/raise.out" 2>/dev/null)
if [ "$RC" -eq 0 ] && [ "$(jq -r '.recipient' "$T/raise.out")" = "session:manager" ]; then
    pass "a dispatched session raises to its dispatcher (session:manager)"
else
    fail "raise in worker exited $RC: $(cat "$T/raise.out" "$T/raise.err")"
fi

# --- pending -----------------------------------------------------------------

before=$(koto decisions list manager 2>/dev/null | cksum)
"$SHIRABE" question pending --in manager >"$T/pending.out" 2>"$T/pending.err"
RC=$?
after=$(koto decisions list manager 2>/dev/null | cksum)
n_worker=$(jq --arg q "$Q_WORKER" '[.questions[], .held[] | select(.identity == $q)] | length' "$T/pending.out" 2>/dev/null)
n_solo=$(jq --arg q "$Q_SOLO" '[.questions[], .held[] | select(.identity == $q)] | length' "$T/pending.out" 2>/dev/null)
if [ "$RC" -eq 0 ] && [ "$n_worker" = 1 ] && [ "$n_solo" = 1 ]; then
    pass "pending at the dispatcher lists the worker's question and the owner's, each once"
else
    fail "pending exited $RC, worker $n_worker, solo $n_solo: $(cat "$T/pending.out" "$T/pending.err")"
fi
if [ "$before" = "$after" ]; then
    pass "pending recorded nothing in the session it read from"
else
    fail "pending left a decision in manager"
fi

# --- render ------------------------------------------------------------------

"$SHIRABE" question render "$Q_SOLO" >"$T/render1.out" 2>"$T/render.err"
RC=$?
(cd / && env -i PATH="$PATH" HOME="$HOME" "$SHIRABE" question render "$Q_SOLO" >"$T/render2.out" 2>/dev/null)
if [ "$RC" -eq 0 ] && cmp -s "$T/render1.out" "$T/render2.out"; then
    pass "render prints the same bytes from another directory under env -i"
else
    fail "render exited $RC or differed: $(cat "$T/render.err"; diff "$T/render1.out" "$T/render2.out" | head -5)"
fi
if [ "$(jq -r '.prompts[0].questions[0].header' "$T/render1.out")" = "$SOLO_HEADER" ]; then
    pass "the rendered header is koto's prompt_header ($SOLO_HEADER)"
else
    fail "rendered header $(jq -r '.prompts[0].questions[0].header' "$T/render1.out"), koto's $SOLO_HEADER"
fi

# --- answer ------------------------------------------------------------------

mkdir -p "$ACCOUNT_HOME/.claude/projects" || { fail "cannot make $ACCOUNT_HOME/.claude/projects"; finish; }
RECORDS=$(mktemp -d "$ACCOUNT_HOME/.claude/projects/shirabe-question-commands-test.XXXXXX") \
    || { fail "mktemp under the account's .claude/projects failed"; finish; }

harness_id() {
    od -An -N16 -tx1 /dev/urandom | tr -d ' \n' \
        | sed 's/^\(........\)\(....\)\(....\)\(....\)\(............\)$/\1-\2-\3-\4-\5/'
}

# record <render file> <harness id> <label picked> <mutation: none|text|label|reply>
record() {
    local now
    now=$(date -u +%Y-%m-%dT%H:%M:%S.000Z)
    jq -c --slurpfile r "$1" --arg h "$2" --arg pick "$3" --arg mut "$4" --arg now "$now" '
        ($r[0].prompts[0].questions) as $qs
        | (if $mut == "text" then ($qs | .[0].question += " Edited.")
           elif $mut == "label" then ($qs | .[0].options[0].label += " (Recommended)")
           else $qs end) as $shown
        | if .type == "assistant" then
              .message.content[0].input.questions = $shown
              | .wireToolInputs["toolu_ZQXMARKERcall000000000001"].questions = $shown
          else
              .toolUseResult.questions = $shown
              | .toolUseResult.answers = {($shown[0].question): $pick}
              | (if $mut == "reply" then .permissionDecision.source = "rule" else . end)
          end
        | .timestamp = $now | .session_id = $h | .sessionId = $h' "$FIXTURE" > "$RECORDS/$2.jsonl"
}

# The call must come no earlier than the question was raised.
sleep 1
H=$(harness_id)
record "$T/render1.out" "$H" "SQLite" none
CLAUDE_CODE_SESSION_ID="$H" "$SHIRABE" question answer "$Q_SOLO" --in solo >"$T/answer.out" 2>"$T/answer.err"
RC=$?
if [ "$RC" -eq 0 ] && [ "$(jq -r '.reading' "$T/answer.out")" = "verified" ] && [ "$(jq -r '.text' "$T/answer.out")" = "SQLite" ]; then
    pass "an answered prompt is recorded as the owner's and reads verified"
else
    fail "answer exited $RC: $(cat "$T/answer.out" "$T/answer.err")"
fi
ANSWER_ID=$(jq -r '.id // empty' "$T/answer.out")

"$SHIRABE" question pending --in solo >"$T/pending2.out" 2>/dev/null
if jq -e --arg q "$Q_SOLO" '[.answered[] | select((.identity // .question.identity // "") == $q or (.question // "") == $q)] | length >= 1' "$T/pending2.out" >/dev/null 2>&1; then
    pass "the raiser's pending lists the answer under answered"
else
    fail "pending --in solo does not list the answer: $(jq -c '.answered' "$T/pending2.out")"
fi
if [ -n "$ANSWER_ID" ] && koto decisions record solo --kind judgment --outcome settled \
        --subject what="used the cache answer" --basis "solo:$ANSWER_ID" --by session >/dev/null 2>"$T/cite.err"; then
    "$SHIRABE" question pending --in solo >"$T/pending3.out" 2>/dev/null
    if [ "$(jq '.answered | length' "$T/pending3.out")" = 0 ]; then
        pass "an answer a decision cites leaves answered"
    else
        fail "the cited answer is still under answered: $(jq -c '.answered' "$T/pending3.out")"
    fi
else
    fail "citing the answer failed: $(cat "$T/cite.err")"
fi

# Each refusal on a question of its own, so no other check is reached first.
refused() {
    local mut=$1 check=$2 label=$3 s q h
    content "$T/r-$mut.json" "$label" "Which store, case $mut?"
    s=solo
    raise "$s" "$T/r-$mut.json" --attempt "$(attempt "$s")"
    q=$(jq -r '.identity' "$T/raise.out")
    "$SHIRABE" question render "$q" >"$T/r-$mut.render" 2>/dev/null
    sleep 1
    h=$(harness_id)
    record "$T/r-$mut.render" "$h" "SQLite" "$mut"
    CLAUDE_CODE_SESSION_ID="$h" "$SHIRABE" question answer "$q" --in "$s" >"$T/r.out" 2>"$T/r.err"
    RC=$?
    if [ "$RC" -eq 4 ] && [ "$(jq -r '.error.check' "$T/r.out")" = "$check" ] \
        && "$SHIRABE" question pending --in "$s" | jq -e --arg q "$q" '[.questions[] | select(.identity == $q)] | length == 1' >/dev/null; then
        pass "a prompt with a changed $mut is refused with koto's '$check' check and the question stays open"
    else
        fail "changed $mut: exit $RC, check $(jq -r '.error.check' "$T/r.out" 2>/dev/null): $(cat "$T/r.err")"
    fi
}
refused text question-text "case text"
refused label options "case label"
refused reply result "case reply"

# --- the twenty-question limit ---------------------------------------------

A_MANY=$(attempt many)
i=1
limit_ok=1
while [ "$i" -le 20 ]; do
    content "$T/m.json" "many $i" "Which store for runner $i?"
    raise many "$T/m.json" --attempt "$A_MANY"
    if [ "$RC" -ne 0 ]; then
        fail "question $i of 20 was refused: $(cat "$T/raise.out")"
        limit_ok=0
        break
    fi
    i=$((i + 1))
done
if [ "$limit_ok" -eq 1 ]; then
    content "$T/m.json" "many 21" "Which store for runner 21?"
    raise many "$T/m.json" --attempt "$A_MANY"
    if [ "$RC" -eq 4 ] && [ "$(jq -r '.error.field' "$T/raise.out")" = "subject.recipient" ]; then
        pass "a twenty-first open question for the owner is refused by koto (exit 4, subject.recipient)"
    else
        fail "the twenty-first question exited $RC: $(cat "$T/raise.out")"
    fi
fi

finish
