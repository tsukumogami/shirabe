#!/usr/bin/env bash
# park.sh -- /execute's record of the PLAN steps held on a question.
#
# A step is parked when its work waits on the answer to an open question: the
# run's own, raised at decide_first in front of worktree_discipline_check, or
# a child /work-on run's, raised at that child's decide_first and left at its
# done_waiting terminal. The run records each as parked/<step> in its context,
# the value being the question's identity (`<session id>/<decision id>`), and
# goes on with the steps that do not depend on it. parked-state.sh reads the
# same keys as the spawn_and_await gate.
#
# Usage:
#   park.sh mark <run> --own --plan <PLAN>
#       park_own's default action. Parks every step the run's own question
#       (decide_question) names in its `waiting` list, and every PLAN step when
#       it names none. Writes parked_ever. Exits 0 once the keys are written,
#       and 0 with nothing written and `none` printed when the run holds no
#       decide_question (--record-question found no open question and cleared
#       it: park_own's question_recorded gate then takes the way out); 2 when
#       koto or the PLAN can't be read.
#   park.sh mark <run> --child <child>
#       Parks the child's step on the question in the child's result. Prints
#       the identity. Refuses, writing nothing (exit 1), a child that is not at
#       done_waiting, one whose result names no question, and one whose
#       question is closed.
#   park.sh clear <run> <step>
#       Removes parked/<step> once its question is closed with an answer that
#       carries authority (pk_answer in park-lib.sh, which calls /work-on's
#       decide-first-gate.sh --answer) and a decision in the run, or in the
#       step's child run, names that answer in its basis. Exit 1, with the key
#       kept, before that, and when the answer carries no authority: the
#       run's own, or a session's that is not the run's dispatcher linked
#       before the raise. A question withdrawn with no answer clears at once
#       and prints `withdrawn`: the withdrawal and its reason are the
#       decision, and the step runs as the PLAN states it.
#   park.sh list <run>
#       One line per parked step: `<step> <identity> open`,
#       `<step> <identity> answered <session>:<id>` for an answer with
#       authority, `<step> <identity> unauthorized <session>:<id>` for one
#       without, or `<step> <identity> closed` for a question withdrawn with
#       no answer.
#   park.sh questions <run>
#       waiting_record's default action. Writes waiting_questions: every open
#       question the run's steps are parked on, once each, separated by a
#       space, for done_waiting's result, or `none` when no step is parked on
#       an open question (a run rewound from done_waiting once its questions
#       closed, which waiting_record sends back to spawn_and_await). Clears
#       the key first, so a read that fails leaves it absent and no edge out.
#   park.sh reason <run>
#       escalate_parked's default action. Appends "; open questions: <ids>"
#       to the failure_reason spawn_and_await's edge wrote, once, so a run
#       that ends at done_blocked with a step parked names the question.
#   park.sh cited <run>
#       spawn_and_await's parked_stop gate. Exits 0 when a parked step's
#       question is closed with an answer that carries authority (as clear
#       reads it) and a decision recorded in the run names that answer in its
#       basis, 1 when none is, 2 when unreadable.
#   park.sh check <run> --plan <PLAN>
#       decide_first's waiting_steps gate. Exits 1 with a finding when the open
#       question raised for this arrival names in `waiting` a step the PLAN
#       does not hold; 0 otherwise, including when no question is raised yet
#       (attempt_recorded says what is missing then); 2 when unreadable.
#
# A question's `waiting` list is read from the content `shirabe question
# raise` stored with it (`koto decisions content read`); this script trusts
# that content as koto returns it and does not re-check its packet hash.
#
# Exit codes: 0 done, 1 refused (a finding or a message says why), 2 koto,
# jq or the PLAN could not be read, 64 usage.
set -u

SELF_DIR=$(cd "$(dirname "$0")" && pwd -P) || exit 2
. "$SELF_DIR/park-lib.sh"

usage() {
    echo "usage: park.sh mark <run> (--own --plan <PLAN> | --child <child>) | clear <run> <step> | list <run> | questions <run> | reason <run> | cited <run> | check <run> --plan <PLAN>" >&2
    exit 64
}
unreadable() {
    echo "park.sh: $*" >&2
    exit 2
}
refuse() {
    echo "park.sh: $*" >&2
    exit 1
}
finding() {
    local line
    line=$(jq -cn --arg m "$1" '{rule_id: "execute/park", level: "error", message: $m}') || exit 2
    printf '::koto-finding::%s\n' "$line"
    exit 1
}

command -v koto > /dev/null || unreadable "koto is not on PATH"
command -v jq > /dev/null || unreadable "jq is not on PATH"

CMD="${1:-}"
RUN="${2:-}"
[ -n "$CMD" ] && [ -n "$RUN" ] || usage
shift 2

# waiting_of <identity>: the question's `waiting` list, one step a line.
waiting_of() {
    local c
    c=$(koto decisions content read -- "$1") || return 2
    printf '%s\n' "$c" | jq -r '.waiting[]?'
}

# own_question: the open question the run raised for the arrival it stands
# at, or empty. Read from the record, not from decide_question, which
# park_own's action writes only after decide_first's gates have run.
own_question() {
    local arrival all qs q h
    arrival=$(pk_ctx "$RUN" decide_arrival) || return 2
    [ -n "$arrival" ] || return 0
    all=$(koto decisions attempts --in="$RUN") || return 2
    qs=$(printf '%s\n' "$all" | jq -r --arg s "$RUN" --arg a "$arrival" \
        '.attempts[]? | select(.session == $s and .status == "in-effect" and .state == $a and .result == "undecided") | .questions[]?') || return 2
    for q in $qs; do
        h=$(pk_history "$q") || return 2
        if printf '%s\n' "$h" | jq -e --arg a "$arrival" '.open == true and .question.state == $a' > /dev/null; then
            printf '%s\n' "$q"
            return 0
        fi
    done
}

plan_arg() {
    [ "${1:-}" = --plan ] && [ -n "${2:-}" ] || usage
    PLAN="$2"
    [ -f "$PLAN" ] || unreadable "no PLAN at $PLAN"
    TASKS=$(pk_tasks "$PLAN") || unreadable "plan-to-tasks.sh could not read $PLAN"
}

case "$CMD" in
mark)
    case "${1:-}" in
    --own)
        shift
        plan_arg "$@"
        q=$(pk_ctx "$RUN" decide_question) || unreadable "could not read decide_question"
        if [ -z "$q" ]; then
            echo none
            exit 0
        fi
        steps=$(waiting_of "$q") || unreadable "could not read the content of $q"
        [ -n "$steps" ] || steps=$(printf '%s\n' "$TASKS" | jq -r '.name')
        for s in $steps; do
            printf '%s\n' "$TASKS" | jq -e --arg s "$s" 'select(.name == $s)' > /dev/null \
                || unreadable "the question names $s, which the PLAN does not hold"
        done
        for s in $steps; do
            printf '%s' "$q" | koto context add "$RUN" "parked/$s" > /dev/null || unreadable "could not write parked/$s"
        done
        printf 'yes' | koto context add "$RUN" parked_ever > /dev/null || unreadable "could not write parked_ever"
        exit 0
        ;;
    --child)
        child="${2:-}"
        [ -n "$child" ] || usage
        case "$child" in
            "$RUN".*) step="${child#"$RUN".}" ;;
            *) refuse "$child is not a child of $RUN" ;;
        esac
        st=$(koto status "$child") || unreadable "koto status $child failed"
        state=$(printf '%s\n' "$st" | jq -r '.current_state') || unreadable "could not read the status of $child"
        [ "$state" = done_waiting ] || refuse "$child stands at $state, not done_waiting: only a child waiting on a question is parked"
        q=$(pk_child_question "$child") || unreadable "could not read the result of $child"
        [ -n "$q" ] || refuse "$child's result names no question"
        h=$(pk_history "$q") || unreadable "koto decisions history $q failed"
        printf '%s\n' "$h" | jq -e '.open == true' > /dev/null || refuse "the question $q is closed: take $child up again instead of parking it"
        printf '%s' "$q" | koto context add "$RUN" "parked/$step" > /dev/null || unreadable "could not write parked/$step"
        printf 'yes' | koto context add "$RUN" parked_ever > /dev/null || unreadable "could not write parked_ever"
        printf '%s\n' "$q"
        exit 0
        ;;
    *) usage ;;
    esac
    ;;
clear)
    step="${1:-}"
    [ -n "$step" ] || usage
    q=$(pk_ctx "$RUN" "parked/$step") || unreadable "could not read parked/$step"
    [ -n "$q" ] || refuse "$step is not parked"
    h=$(pk_history "$q") || unreadable "koto decisions history $q failed"
    # Only a history that reads closed takes a step up: one that reads neither
    # way could pass for a withdrawal below.
    o=$(printf '%s\n' "$h" | jq -r '.open') || unreadable "could not read the history of $q"
    case "$o" in
        true) refuse "the question $q is still open; $step stays parked" ;;
        false) ;;
        *) unreadable "the history of $q reads neither open nor closed; $step stays parked" ;;
    esac
    answer=$(pk_answer "$RUN" "$q") || unreadable "could not read the answer to $q"
    raw=$(pk_raw_answer "$h") || unreadable "could not read the history of $q"
    if [ -z "$answer" ] && [ -n "$raw" ]; then
        refuse "the answer $raw to $q carries no authority over this run (the run's own, or a session's that is not its dispatcher linked before the raise); $step stays parked"
    fi
    if [ -z "$answer" ]; then
        # Withdrawn with no answer: the withdrawal, recorded with its reason,
        # is the decision. The step runs as the PLAN states it.
        koto context remove "$RUN" "parked/$step" > /dev/null || unreadable "could not remove parked/$step"
        echo "withdrawn"
        exit 0
    fi
    cited=1
    pk_cites "$RUN" "$answer"; rc=$?
    case "$rc" in
        0) cited=0 ;;
        1) ;;
        *) unreadable "could not read the decisions of $RUN" ;;
    esac
    if [ "$cited" -ne 0 ]; then
        ex=0
        koto status "$RUN.$step" > /dev/null || ex=$?
        if [ "$ex" -eq 0 ]; then
            pk_cites "$RUN.$step" "$answer"; rc=$?
            case "$rc" in
                0) cited=0 ;;
                1) ;;
                *) unreadable "could not read the decisions of $RUN.$step" ;;
            esac
        fi
    fi
    [ "$cited" -eq 0 ] || refuse "no decision in $RUN or $RUN.$step cites the answer $answer yet; record one with --basis $answer first"
    koto context remove "$RUN" "parked/$step" > /dev/null || unreadable "could not remove parked/$step"
    exit 0
    ;;
list)
    parked=$(pk_parked "$RUN") || unreadable "could not read the parked steps of $RUN"
    printf '%s\n' "$parked" | while read -r step q; do
        [ -n "$step" ] || continue
        h=$(pk_history "$q") || unreadable "koto decisions history $q failed"
        if printf '%s\n' "$h" | jq -e '.open == true' > /dev/null; then
            printf '%s %s open\n' "$step" "$q"
        else
            answer=$(pk_answer "$RUN" "$q") || unreadable "could not read the answer to $q"
            raw=$(pk_raw_answer "$h") || unreadable "could not read the history of $q"
            if [ -n "$answer" ]; then
                printf '%s %s answered %s\n' "$step" "$q" "$answer"
            elif [ -n "$raw" ]; then
                printf '%s %s unauthorized %s\n' "$step" "$q" "$raw"
            else
                printf '%s %s closed\n' "$step" "$q"
            fi
        fi
    done
    exit "${PIPESTATUS[1]}"
    ;;
questions)
    koto context remove "$RUN" waiting_questions > /dev/null || unreadable "could not clear waiting_questions"
    qs=$(pk_open_questions "$RUN") || unreadable "could not read the open questions of $RUN"
    [ -n "$qs" ] || qs=none
    printf '%s' "$qs" | koto context add "$RUN" waiting_questions > /dev/null || unreadable "could not write waiting_questions"
    exit 0
    ;;
reason)
    qs=$(pk_open_questions "$RUN") || unreadable "could not read the open questions of $RUN"
    r=$(pk_ctx "$RUN" failure_reason) || unreadable "could not read failure_reason"
    case "$r" in
        *"; open questions: "*) exit 0 ;;
    esac
    [ -n "$qs" ] || qs="none"
    printf '%s; open questions: %s' "$r" "$qs" | koto context add "$RUN" failure_reason > /dev/null \
        || unreadable "could not write failure_reason"
    exit 0
    ;;
cited)
    parked=$(pk_parked "$RUN") || unreadable "could not read the parked steps of $RUN"
    for q in $(printf '%s\n' "$parked" | awk 'NF == 2 { print $2 }'); do
        h=$(pk_history "$q") || unreadable "koto decisions history $q failed"
        answer=$(pk_answer "$RUN" "$q") || unreadable "could not read the answer to $q"
        [ -n "$answer" ] || continue
        pk_cites "$RUN" "$answer"; rc=$?
        case "$rc" in
            0) exit 0 ;;
            1) ;;
            *) unreadable "could not read the decisions of $RUN" ;;
        esac
    done
    exit 1
    ;;
check)
    plan_arg "$@"
    q=$(own_question) || unreadable "could not read the run's question for this arrival"
    [ -n "$q" ] || exit 0
    steps=$(waiting_of "$q") || unreadable "could not read the content of $q"
    for s in $steps; do
        printf '%s\n' "$TASKS" | jq -e --arg s "$s" 'select(.name == $s)' > /dev/null \
            || finding "the question $q names $s in waiting, which is not a step of the PLAN ($(printf '%s\n' "$TASKS" | jq -r '.name' | tr '\n' ' ')): withdraw it and raise it again naming the steps it holds"
    done
    exit 0
    ;;
*) usage ;;
esac
