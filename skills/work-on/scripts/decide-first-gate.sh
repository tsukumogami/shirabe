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
#   decide-first-gate.sh <session>                    the attempt_recorded gate
#   decide-first-gate.sh --arrive <session>           decide_first's default action
#   decide-first-gate.sh --from <session>             the decide_from gate
#   decide-first-gate.sh --laps <session>             the decide_laps gate
#   decide-first-gate.sh --record-question <session>  waiting_record's default action
#   decide-first-gate.sh --approval <session>         deferral_approval's answer gate
#   decide-first-gate.sh --resume <session>           entry's decide_resume gate
#
# Only the two default actions, --arrive and --record-question, write to
# context. The gates read it and exit; a gate's output never reaches context.
#
# The arrival. Each edge into decide_first assigns decide_origin (the covered
# state the run left) and decide_fresh=yes. --arrive sees decide_fresh and
# counts the arrival: decide_count goes up by one, decide_arrival becomes
# <origin>:<count>, the name the session passes as --state to
# `shirabe question attempt` and `raise`, and decide_laps_<origin> counts the
# arrivals from that state. These are context keys, so a session continuing a
# waiting run carries them and goes on counting: no two arrivals in a run
# share a name. koto runs the action on every tick that enters the state
# without evidence, so it counts only when decide_fresh is yes, and sets it to
# no. It prints the arrival name.
#
# A question for the arrival is one whose state is decide_arrival and whose
# raiser is this session or a session it continues: one tied to an undecided
# attempt for the arrival, an open need raised from it, or decide_question
# when it names one.
#
# attempt_recorded (no option) exits:
#   0  an attempt with result decided or provisional is recorded in the
#      session for this arrival, and no question for the arrival is open
#   3  a question for the arrival is open, tied to an undecided attempt or
#      an open need; a deciding attempt beside it prints a finding too, since
#      the run can't carry on past its own open question
#   1  neither: one ::koto-finding:: line says what is missing
#   2  the record cannot be read (koto or shirabe missing, below the minimum,
#      or failing); no edge is taken and the run holds
# An attempt counts only when it is in effect, was recorded in this session,
# and its state is this arrival's name. A question answered or withdrawn since
# is not open and does not count.
#
# --record-question removes decide_question, then writes the identity of the
# open question for the arrival into it: exit 0 written, 1 none open (with a
# finding), 2 the record cannot be read.
#
# --from exits with the code of the covered state named by decide_origin, so
# decide_first's edges can pair it with the submitted outcome: 10 analysis,
# 11 implementation, 12 introspection, 13 task_validation,
# 14 post_research_validation, 15 plan_validation, 16 deferral_approval;
# 2 when decide_origin is missing or names no covered state.
#
# --laps exits 0 while decide_laps_<origin> is at most 3, and 1, with a
# finding, from the fourth arrival from one state: the resume edges need 0.
#
# --approval exits 0 when, for the deferral_approval arrival in
# decide_arrival, a question for the arrival has an answer in effect that is
# either a person's answer koto reads as verified, a settle resting on one, or
# a session's answer given by a session above this run (its dispatcher, the
# dispatcher's, and so on, by koto's recorded origin, never this session or
# one it continues), and a deciding attempt in this session cites that
# answer. 1 otherwise, with a finding; 2 when the record cannot be read.
#
# --resume exits 0 when the session continues no waiting run (no
# decide_question in context): a fresh run is untouched. In a session that
# continues one it exits the origin code of the question's state (10 to 16, as
# --from) once a deciding attempt in this session cites the question's answer
# in its basis, and 1, with a finding, while the question is open, after it
# was withdrawn, or before the answer is cited; 2 when the record cannot be
# read. koto runs it at entry on every run, so a gate PATH with no koto holds
# every run there, with a line saying so.
#
# Nothing here writes a decision. stdout carries the finding or the arrival
# name; koto's and jq's own messages reach stderr unchanged.
set -uo pipefail

LAP_CAP=3

SELF_DIR=$(cd "$(dirname "$0")" && pwd -P) || exit 2
ROOT_SELF=$(cd "$SELF_DIR/../../.." && pwd -P) || exit 2

MODE=check
case "${1:-}" in
    --arrive|--from|--laps|--record-question|--approval|--resume) MODE="${1#--}"; shift ;;
esac
WF="${1:-}"
if [ -z "$WF" ] || [ "$#" -ne 1 ]; then
    echo "usage: decide-first-gate.sh [--arrive|--from|--laps|--record-question|--approval|--resume] <session>" >&2
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
        *) return 1 ;;
    esac
}

need_tools() {
    command -v jq > /dev/null || unreadable "jq is not on PATH"
    local out
    out=$(env -u KOTO_FLOOR bash "$ROOT_SELF/scripts/assert-koto-floor.sh" 2>&1) \
        || unreadable "koto is below shirabe's minimum: $(printf '%s\n' "$out" | tail -n 1)"
    command -v shirabe > /dev/null || unreadable "shirabe is not on PATH"
    shirabe question precedent --help > /dev/null \
        || unreadable "this shirabe has no 'question precedent'; the session needs the shirabe this plugin ships"
}

# ctx <key>: the context value, or empty when the key is absent or holds the
# literal none an edge clears it with. `koto context exists` exits 1 for an
# absent key; any other failure is koto trouble, and the gate fails closed.
ctx() {
    local rc=0 v
    koto context exists "$WF" "$1" > /dev/null || rc=$?
    case "$rc" in
        0)
            v=$(koto context get "$WF" "$1") || unreadable "could not read context key $1"
            [ "$v" = none ] && v=""
            printf '%s' "$v"
            ;;
        1) ;;
        *) unreadable "koto context exists $WF $1 failed with exit $rc; read koto's message above" ;;
    esac
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

# history <identity>: the question's history, or the gate fails closed.
history() {
    koto decisions history -- "$1" || unreadable "koto decisions history $1 failed"
}

# show <session> <id>: one decision, or the gate fails closed.
show() {
    koto decisions show -- "$1" "$2" || unreadable "koto decisions show $1 $2 failed"
}

# lineage: this session and every session it continues, one per line.
lineage() {
    local s=$WF p i=0
    while [ -n "$s" ] && [ "$i" -lt 20 ]; do
        printf '%s\n' "$s"
        p=$(koto session hierarchy --json "$s" | jq -r '.predecessor // empty') \
            || unreadable "koto session hierarchy $s failed"
        s=$p
        i=$((i + 1))
    done
}

# above: every session koto's recorded origin names above this run's lineage,
# one per line: each dispatcher, its dispatcher, and so on.
above() {
    local l s d i
    for l in $(lineage); do
        s=$l
        i=0
        while [ "$i" -lt 20 ]; do
            d=$(koto session origin "$s" | jq -r 'select(.origin.state == "dispatched" and .origin.dispatcher_kind == "workflow") | .origin.dispatcher // empty') \
                || unreadable "koto session origin $s failed"
            [ -n "$d" ] || break
            printf '%s\n' "$d"
            s=$d
            i=$((i + 1))
        done
    done
}

in_lines() {
    grep -Fx -- "$1" > /dev/null <<< "$2"
}

# questions <arrival>: the identities of the questions for the arrival, one
# per line, whatever their standing.
questions() {
    local arrival=$1 rows q h lin
    lin=$(lineage) || exit 2
    {
        printf '%s\n' "$ALL" | jq -r --arg a "$arrival" 'select(.state == $a and .result == "undecided") | .questions[]?' \
            || unreadable "could not read the attempts"
        rows=$(koto decisions list "$WF" --format v1 --kind escalate) || unreadable "koto decisions list $WF failed"
        printf '%s\n' "$rows" | jq -r --arg a "$arrival" \
            '.decisions[]? | select(.decision.subject.state == $a) | "\(.decision.session.id)/\(.id)"' \
            || unreadable "could not read the questions of $WF"
        q=$(ctx decide_question) || exit 2
        [ -z "$q" ] || printf '%s\n' "$q"
    } | sort -u | while read -r q; do
        [ -n "$q" ] || continue
        h=$(history "$q") || exit 2
        if printf '%s\n' "$h" | jq -e --arg a "$arrival" '.question.state == $a' > /dev/null \
            && in_lines "$(printf '%s\n' "$h" | jq -r '.raiser.name // empty')" "$lin"; then
            printf '%s\n' "$q"
        fi
    done
}

is_open() {
    local h
    h=$(history "$1") || exit 2
    printf '%s\n' "$h" | jq -e '.open == true' > /dev/null
}

# verified <session> <id>: koto reads the entry as a person's verified answer.
verified() {
    local s
    s=$(show "$1" "$2") || exit 2
    printf '%s\n' "$s" | jq -e '(.reading // .decision.reading) == "verified"' > /dev/null
}

# authoritative_answer <identity>: the question's answer in effect as
# <session>:<id>, when it carries authority over this run; nothing otherwise.
authoritative_answer() {
    local h s id kind outcome shown b up lin
    h=$(history "$1") || exit 2
    s=$(printf '%s\n' "$h" | jq -r '.answer.session // empty')
    id=$(printf '%s\n' "$h" | jq -r '.answer.id // empty')
    outcome=$(printf '%s\n' "$h" | jq -r '.answer.outcome // empty')
    [ -n "$s" ] && [ -n "$id" ] || return 0
    shown=$(show "$s" "$id") || exit 2
    printf '%s\n' "$shown" | jq -e '.status == null or .status == "in-effect"' > /dev/null || return 0
    case "$outcome" in
        answered)
            if verified "$s" "$id"; then
                printf '%s:%s\n' "$s" "$id"
                return 0
            fi
            kind=$(printf '%s\n' "$shown" | jq -r '.decision.decider.kind // empty')
            [ "$kind" = session ] || return 0
            lin=$(lineage) || exit 2
            in_lines "$s" "$lin" && return 0
            up=$(above) || exit 2
            in_lines "$s" "$up" && printf '%s:%s\n' "$s" "$id"
            ;;
        settled)
            for b in $(printf '%s\n' "$shown" | jq -r '.decision.basis[]? | "\(.session):\(.id)"'); do
                if verified "${b%%:*}" "${b#*:}"; then
                    printf '%s:%s\n' "$s" "$id"
                    return 0
                fi
            done
            ;;
    esac
    return 0
}

# basis_of <attempt id>: the attempt's basis as <session>:<id> lines.
basis_of() {
    local s
    s=$(show "$WF" "$1") || exit 2
    printf '%s\n' "$s" | jq -r '.decision.basis[]? | "\(.session):\(.id)"' || unreadable "could not read the basis of $1"
}

deciding() {
    jq -c 'select(.result == "decided" or .result == "provisional")'
}

# cited <entry>: a deciding attempt in this session cites the entry.
cited() {
    local a b bs
    for a in $(printf '%s\n' "$ALL" | deciding | jq -r '.id'); do
        bs=$(basis_of "$a") || exit 2
        for b in $bs; do
            [ "$b" = "$1" ] && return 0
        done
    done
    return 1
}

if ! command -v koto > /dev/null; then
    unreadable "koto is not on the PATH koto runs this gate with; every /work-on run holds here until it is"
fi

case "$MODE" in
arrive)
    origin=$(ctx decide_origin) || exit 2
    code_of "$origin" > /dev/null || unreadable "decide_origin names no covered state: '$origin'"
    fresh=$(ctx decide_fresh) || exit 2
    if [ "$fresh" = yes ]; then
        n=$(ctx decide_count) || exit 2
        case "$n" in ''|*[!0-9]*) n=0 ;; esac
        laps=$(ctx "decide_laps_$origin") || exit 2
        case "$laps" in ''|*[!0-9]*) laps=0 ;; esac
        n=$((n + 1))
        put decide_count "$n"
        put "decide_laps_$origin" "$((laps + 1))"
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
laps)
    origin=$(ctx decide_origin) || exit 2
    code_of "$origin" > /dev/null || unreadable "decide_origin names no covered state: '$origin'"
    laps=$(ctx "decide_laps_$origin") || exit 2
    case "$laps" in ''|*[!0-9]*) laps=0 ;; esac
    [ "$laps" -le "$LAP_CAP" ] && exit 0
    command -v jq > /dev/null || unreadable "jq is not on PATH"
    finding "this is arrival $laps from $origin, past the cap of $LAP_CAP: resume is refused; stop with decided_next: stop, or raise the question"
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
check|record-question)
    arrival=$(ctx decide_arrival) || exit 2
    [ -n "$arrival" ] || unreadable "no arrival is recorded at decide_first"
    mine=$(printf '%s\n' "$ALL" | jq -c --arg a "$arrival" 'select(.state == $a)') || unreadable "could not read the attempts"
    qs=$(questions "$arrival") || exit 2
    open=""
    for q in $qs; do
        if is_open "$q"; then open=$q; break; fi
    done
    if [ "$MODE" = record-question ]; then
        koto context remove "$WF" decide_question > /dev/null || unreadable "could not clear context key decide_question"
        [ -n "$open" ] || finding "no open question names $arrival: raise one with shirabe question raise --attempt <id> --state $arrival"
        put decide_question "$open"
        exit 0
    fi
    if [ -n "$open" ]; then
        if [ -n "$(printf '%s\n' "$mine" | deciding)" ]; then
            line=$(jq -cn --arg m "the question $open raised for $arrival is still open, so a deciding attempt can't take the run on: wait for its answer and cite it, or withdraw it with shirabe question withdraw $open --in $WF --reason <why>" \
                '{rule_id: "work-on/decide-first", level: "error", message: $m}') || exit 2
            printf '::koto-finding::%s\n' "$line"
        fi
        exit 3
    fi
    if [ -n "$(printf '%s\n' "$mine" | deciding)" ]; then
        exit 0
    fi
    if [ -n "$(printf '%s\n' "$mine" | jq -c 'select(.result == "undecided")')" ]; then
        finding "the undecided attempt for $arrival has no open question naming it: raise one with shirabe question raise --attempt <id> --state $arrival, or record a deciding attempt"
    fi
    finding "no attempt is recorded for $arrival: record one with shirabe question attempt --in $WF --state $arrival before leaving decide_first"
    ;;
approval)
    arrival=$(ctx decide_arrival) || exit 2
    case "$arrival" in
        deferral_approval:*) ;;
        *) finding "deferral_approval needs an answer first: submit approval_decision: needs_answer and settle the deferral at decide_first" ;;
    esac
    qs=$(questions "$arrival") || exit 2
    [ -n "$qs" ] || finding "no question is raised for $arrival: a deferral is approved or rejected only on the answer to the question raised for it"
    for q in $qs; do
        ans=$(authoritative_answer "$q") || exit 2
        [ -n "$ans" ] || continue
        cited "$ans" && exit 0
        finding "the answer $ans to $q is not cited yet: record shirabe question attempt --in $WF --state $arrival --result decided --basis $ans"
    done
    finding "no question raised for $arrival has an answer from a verified person or from a session above this run: an answer given by this run, a session it continues, or a session outside its dispatch chain approves nothing"
    ;;
resume)
    h=$(history "$question") || exit 2
    state=$(printf '%s\n' "$h" | jq -r '.question.state // ""') || unreadable "could not read the history of $question"
    c=$(code_of "${state%%:*}") || unreadable "the question's state '$state' names no covered state"
    if printf '%s\n' "$h" | jq -e '.open == true' > /dev/null; then
        finding "the question $question is still open: this run continues once it is answered"
    fi
    answer=$(printf '%s\n' "$h" | jq -r '.answer | select(. != null and (.outcome == "answered" or .outcome == "settled")) | "\(.session):\(.id)"')
    [ -n "$answer" ] || finding "the question $question was closed without an answer: there is nothing to continue from; start the work fresh"
    cited "$answer" && exit "$c"
    finding "the answer $answer is not cited yet: record shirabe question attempt --in $WF --result decided --basis $answer before going back to ${state%%:*}"
    ;;
esac
