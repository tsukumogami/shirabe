#!/usr/bin/env bash
# decide-first-gate.sh -- for /work-on: what koto holds for the run's arrival at
# decide_first, the state in front of every covered exit.
#
# A covered exit is one the run used to take straight to done_blocked or
# validation_exit when it could not settle something. The run now arrives at
# decide_first first, and it leaves only once koto holds an attempt for that
# arrival: a deciding one lets it go back to its work or take the exit, an
# undecided one with the question it raised ends it at done_waiting. The
# procedure the session follows there is references/question-procedure.md;
# this script only reads the record and names what it found.
#
# Usage:
#   decide-first-gate.sh <session>             the attempt_recorded gate
#   decide-first-gate.sh --arrive <session>    decide_first's default action
#   decide-first-gate.sh --from <session>      the decide_from gate
#   decide-first-gate.sh --approval <session>  deferral_approval's answer gate
#   decide-first-gate.sh --resume <session>    entry's decide_resume gate
#
# The arrival. Each edge into decide_first assigns decide_origin (the covered
# state the run left) and decide_fresh=yes. --arrive, the state's default
# action, sees decide_fresh and counts the arrival: decide_count goes up by
# one and decide_arrival becomes <origin>:<count>, the name the session passes
# as --state to `shirabe question attempt` and `raise`. decide_count is a
# context key, so a session continuing a waiting run carries it and goes on
# counting: no two arrivals in a run share a name. koto runs the action on
# every tick that enters the state without evidence, so it counts only when
# decide_fresh is yes, sets it to no, and otherwise prints the name it holds.
# It prints the name on stdout, which koto captures as DECIDE_ARRIVAL for the
# directive.
#
# attempt_recorded (no option) exits:
#   0  an attempt with result decided or provisional is recorded in the
#      session for this arrival. In a session rewound to the arrival it
#      waited from, whose question (decide_question, raised for this
#      arrival) has since been answered, the attempt must also cite that
#      answer in its basis, or the gate is at 1.
#   3  an undecided attempt is recorded for it and an open question whose
#      state is this arrival names it, or an open need carries this arrival's
#      state. The question's identity is written to decide_question, which
#      done_waiting's result reads.
#   1  neither: one ::koto-finding:: line says what is missing
#   2  the record cannot be read (koto or shirabe missing, below the minimum,
#      or failing); no edge is taken and the run holds
# An attempt counts only when it is in effect, was recorded in this session,
# and its state is this arrival's name. One with no state, one naming an
# earlier arrival, one in another session and one a predecessor recorded for
# the arrival it waited on all leave the gate at 1. A question answered or
# withdrawn since is not open and does not count.
#
# --from exits with the code of the covered state named by decide_origin, so
# decide_first's edges can pair it with the submitted outcome: 10 analysis,
# 11 implementation, 12 introspection, 13 task_validation,
# 14 post_research_validation, 15 plan_validation, 16 deferral_approval,
# and /execute's 20 worktree_discipline_check; 2 when decide_origin is
# missing or names no covered state.
#
# --approval exits 0 when the run's record holds, for the deferral_approval
# arrival in decide_arrival, a deciding attempt whose basis names an answer in
# effect, or, in a session continuing a waiting run, a deciding attempt citing
# the answer to the question in decide_question; 1 otherwise, with a finding;
# 2 when the record cannot be read. An approval then rests on an answer
# someone other than the run gave.
#
# --resume exits 0 when the session continues no waiting run (no
# decide_question in context): a fresh run is untouched. In a session that
# continues one it exits the origin code of the question's state (10 to 16, as
# --from) once a deciding attempt in this session cites the question's answer
# in its basis, and 1, with a finding, while the question is open, after it
# was withdrawn, or before the answer is cited; 2 when the record cannot be
# read.
#
# Nothing here writes a decision. stdout carries the finding or the arrival
# name; koto's and jq's own messages reach stderr unchanged.
set -u

SELF_DIR=$(cd "$(dirname "$0")" && pwd -P) || exit 2
ROOT_SELF=$(cd "$SELF_DIR/../../.." && pwd -P) || exit 2

MODE=check
case "${1:-}" in
    --arrive|--from|--approval|--resume) MODE="${1#--}"; shift ;;
esac
WF="${1:-}"
if [ -z "$WF" ] || [ "$#" -ne 1 ]; then
    echo "usage: decide-first-gate.sh [--arrive|--from|--approval|--resume] <session>" >&2
    exit 2
fi

unreadable() {
    echo "decide-first-gate: $*" >&2
    exit 2
}

finding() {
    local line
    line=$(jq -cn --arg m "$1" '{rule_id: "work-on/decide-first", level: "error", message: $m}') || exit 2
    printf '::koto-finding::%s\n' "$line"
    exit 1
}

code_of() {
    case "$1" in
        analysis) echo 10 ;;
        implementation) echo 11 ;;
        introspection) echo 12 ;;
        task_validation) echo 13 ;;
        post_research_validation) echo 14 ;;
        plan_validation) echo 15 ;;
        deferral_approval) echo 16 ;;
        # /execute's covered exit.
        worktree_discipline_check) echo 20 ;;
        *) return 1 ;;
    esac
}

need_tools() {
    command -v koto > /dev/null || unreadable "koto is not on PATH"
    command -v jq > /dev/null || unreadable "jq is not on PATH"
    local out
    out=$(env -u KOTO_FLOOR bash "$ROOT_SELF/scripts/assert-koto-floor.sh" 2>&1) \
        || unreadable "koto is below shirabe's minimum: $(printf '%s\n' "$out" | tail -n 1)"
    command -v shirabe > /dev/null || unreadable "shirabe is not on PATH"
    shirabe question precedent --help > /dev/null \
        || unreadable "this shirabe has no 'question precedent'; the session needs the shirabe this plugin ships"
}

# ctx <key>: the context value, or empty when the key is absent.
ctx() {
    if koto context exists "$WF" "$1" > /dev/null; then
        koto context get "$WF" "$1" || unreadable "could not read context key $1"
    fi
}

put() {
    printf '%s' "$2" | koto context add "$WF" "$1" > /dev/null || unreadable "could not write context key $1"
}

# attempts: the session's own attempts in effect, as JSON lines.
attempts() {
    local raw
    raw=$(koto decisions attempts --in="$WF") || unreadable "koto decisions attempts --in=$WF failed"
    printf '%s\n' "$raw" | jq -c --arg s "$WF" '.attempts[]? | select(.session == $s and .status == "in-effect")' \
        || unreadable "could not read the attempts of $WF"
}

# open_question <identity> <state>: whether the question is open and was
# raised for that arrival.
open_question() {
    local h
    h=$(koto decisions history -- "$1") || unreadable "koto decisions history $1 failed"
    printf '%s\n' "$h" | jq -e --arg st "$2" '.open == true and .question.state == $st' > /dev/null
}

# answer_in_effect <session> <id>: whether that entry is an answer to a
# question that has not been withdrawn or replaced.
answer_in_effect() {
    local s
    s=$(koto decisions show "$1" "$2") || return 1
    printf '%s\n' "$s" | jq -e '.decision.kind == "answer" and .decision.outcome == "answered"
        and (.status == null or .status == "in-effect")' > /dev/null
}

# basis_of <attempt id>: the attempt's basis as <session>:<id> lines.
basis_of() {
    local s
    s=$(koto decisions show "$WF" "$1") || unreadable "koto decisions show $WF $1 failed"
    printf '%s\n' "$s" | jq -r '.decision.basis[]? | "\(.session):\(.id)"' || unreadable "could not read the basis of $1"
}

deciding() {
    jq -c 'select(.result == "decided" or .result == "provisional")'
}

command -v koto > /dev/null || unreadable "koto is not on PATH"

case "$MODE" in
arrive)
    origin=$(ctx decide_origin) || exit 2
    code_of "$origin" > /dev/null || unreadable "decide_origin names no covered state: '$origin'"
    fresh=$(ctx decide_fresh) || exit 2
    if [ "$fresh" = yes ]; then
        n=$(ctx decide_count) || exit 2
        case "$n" in ''|*[!0-9]*) n=0 ;; esac
        n=$((n + 1))
        put decide_count "$n"
        put decide_arrival "$origin:$n"
        put decide_fresh no
    fi
    arrival=$(ctx decide_arrival) || exit 2
    [ -n "$arrival" ] || unreadable "no arrival is recorded"
    printf '%s\n' "$arrival"
    exit 0
    ;;
from)
    origin=$(ctx decide_origin) || exit 2
    c=$(code_of "$origin") || unreadable "decide_origin names no covered state: '$origin'"
    exit "$c"
    ;;
resume)
    # A run that continues no waiting run is a fresh one: nothing else is
    # read, and no shirabe call is made.
    question=$(ctx decide_question) || exit 2
    [ -n "$question" ] || exit 0
    ;;
esac

need_tools
ALL=$(attempts) || exit 2

case "$MODE" in
check)
    arrival=$(ctx decide_arrival) || exit 2
    [ -n "$arrival" ] || unreadable "no arrival is recorded at decide_first"
    mine=$(printf '%s\n' "$ALL" | jq -c --arg a "$arrival" 'select(.state == $a)') || unreadable "could not read the attempts"
    if [ -n "$(printf '%s\n' "$mine" | deciding)" ]; then
        # A session rewound to the arrival it waited from still holds that
        # arrival's question. Once the question is closed with an answer, the
        # deciding attempt must cite it: the run resumes on the answer to the
        # question it raised for this stop, not on a decision of its own
        # made around it. A question withdrawn without an answer leaves the
        # session's own deciding attempt standing.
        question=$(ctx decide_question) || exit 2
        if [ -n "$question" ]; then
            h=$(koto decisions history -- "$question") || unreadable "koto decisions history $question failed"
            answer=$(printf '%s\n' "$h" | jq -r --arg a "$arrival" 'select(.question.state == $a and .open != true)
                | .answer | select(. != null and .outcome == "answered") | "\(.session):\(.id)"') \
                || unreadable "could not read the history of $question"
            if [ -n "$answer" ]; then
                for a in $(printf '%s\n' "$mine" | deciding | jq -r '.id'); do
                    bases=$(basis_of "$a") || exit 2
                    for b in $bases; do
                        [ "$b" = "$answer" ] && exit 0
                    done
                done
                finding "the question $question raised for $arrival was answered ($answer): record shirabe question attempt --in $WF --state $arrival --result decided --basis $answer before leaving decide_first"
            fi
        fi
        exit 0
    fi
    # An undecided attempt and the open question that names it.
    for q in $(printf '%s\n' "$mine" | jq -r 'select(.result == "undecided") | .questions[]?'); do
        if open_question "$q" "$arrival"; then
            put decide_question "$q"
            exit 3
        fi
    done
    # An open need raised from the arrival stands without an attempt.
    raised=$(koto decisions list "$WF" --format v1 --kind escalate) || unreadable "koto decisions list $WF failed"
    for row in $(printf '%s\n' "$raised" | jq -r --arg a "$arrival" \
        '.decisions[]? | select(.decision.subject.state == $a and (.decision.subject.need // "decision") != "decision")
         | "\(.decision.session.id)/\(.id)"'); do
        if open_question "$row" "$arrival"; then
            put decide_question "$row"
            exit 3
        fi
    done
    if [ -n "$(printf '%s\n' "$mine" | jq -c 'select(.result == "undecided")')" ]; then
        finding "the undecided attempt for $arrival has no open question naming it: raise one with shirabe question raise --attempt <id> --state $arrival, or record a deciding attempt"
    fi
    finding "no attempt is recorded for $arrival: record one with shirabe question attempt --in $WF --state $arrival before leaving decide_first"
    ;;
approval)
    arrival=$(ctx decide_arrival) || exit 2
    question=$(ctx decide_question) || exit 2
    cited=""
    case "$arrival" in
        deferral_approval:*) ;;
        *) arrival="" ;;
    esac
    if [ -n "$question" ]; then
        h=$(koto decisions history -- "$question") || unreadable "koto decisions history $question failed"
        cited=$(printf '%s\n' "$h" | jq -r 'select(.question.state | startswith("deferral_approval:"))
            | .answer | select(. != null and .outcome == "answered") | "\(.session):\(.id)"') \
            || unreadable "could not read the history of $question"
    fi
    if [ -z "$arrival" ] && [ -z "$cited" ]; then
        finding "deferral_approval needs an answer first: submit approval_decision: needs_answer and settle the deferral at decide_first"
    fi
    for a in $(printf '%s\n' "$ALL" | deciding | jq -r --arg a "$arrival" --argjson any "$([ -n "$cited" ] && echo true || echo false)" \
        'select((($a != "") and .state == $a) or $any) | .id'); do
        bases=$(basis_of "$a") || exit 2
        for b in $bases; do
            if [ -n "$cited" ] && [ "$b" = "$cited" ]; then exit 0; fi
            if [ -n "$arrival" ] && answer_in_effect "${b%%:*}" "${b#*:}"; then exit 0; fi
        done
    done
    finding "no deciding attempt for the deferral cites an answer in effect: an approval rests on an answer someone other than the run gave"
    ;;
resume)
    h=$(koto decisions history -- "$question") || unreadable "koto decisions history $question failed"
    state=$(printf '%s\n' "$h" | jq -r '.question.state // ""') || unreadable "could not read the history of $question"
    c=$(code_of "${state%%:*}") || unreadable "the question's state '$state' names no covered state"
    if printf '%s\n' "$h" | jq -e '.open == true' > /dev/null; then
        finding "the question $question is still open: this run continues once it is answered"
    fi
    answer=$(printf '%s\n' "$h" | jq -r '.answer | select(. != null and .outcome == "answered") | "\(.session):\(.id)"')
    [ -n "$answer" ] || finding "the question $question was closed without an answer: withdraw the run's work or start it fresh"
    for a in $(printf '%s\n' "$ALL" | deciding | jq -r '.id'); do
        bases=$(basis_of "$a") || exit 2
        for b in $bases; do
            [ "$b" = "$answer" ] && exit "$c"
        done
    done
    finding "the answer $answer is not cited yet: record shirabe question attempt --in $WF --result decided --basis $answer before going back to ${state%%:*}"
    ;;
esac
