#!/usr/bin/env bash
# decide-first-gate.sh -- for /work-on, and /execute's decide_first: what koto
# holds for the run's arrival at decide_first, the state in front of every
# covered exit.
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
#   decide-first-gate.sh --recorded <session>         waiting_record's gate
#   decide-first-gate.sh --approval <session>         deferral_approval's answer gate
#   decide-first-gate.sh --resume <session>           resume_waiting's decide_resume gate
#   decide-first-gate.sh --answer <session> <identity>
#                                                     the answer with authority,
#                                                     for /execute's park.sh
#
# Only the two default actions, --arrive and --record-question, write to
# context. The gates read it and exit; a gate's output never reaches context.
#
# The arrival. Each edge into decide_first assigns decide_origin, the covered
# state the run left, and koto records that write in the session's context
# history as the transition's. The arrivals are read from that record, never
# from a key the session can rewrite: the run's arrivals are the transition
# writes of decide_origin in this session and every session it continues, the
# newest names the origin, their number is the arrival count, and those with
# the newest's value are the arrivals from that state. --arrive writes
# decide_arrival, <origin>:<count>, the name the session passes as --state to
# `shirabe question attempt` and `raise`, and prints it. Run again on the
# same arrival, it writes the same name, so a tick that fails part-way counts
# nothing twice. A session writing decide_origin itself (writer agent), or a
# succession carrying it (writer koto), adds no arrival.
#
# The gates read the arrival from the same record, not from decide_arrival.
# finalization's deferral_requested edge clears decide_arrival to none; when
# that transition write is newer in this session than its newest arrival,
# there is no arrival, whatever decide_arrival holds now.
#
# A question for the arrival is one whose state is the arrival's name and whose
# raiser is this session or a session it continues: one tied to an undecided
# attempt for the arrival, an open need raised from it, or decide_question
# when it names one.
#
# attempt_recorded (no option) exits:
#   0  an attempt with result decided or provisional is recorded in the
#      session for this arrival, and no question for the arrival is open.
#      In a session rewound to the arrival it waited from (/execute's
#      continuation), whose decide_question was raised for this arrival and
#      has since been answered, the attempt must also cite that answer in
#      its basis, or the gate is at 1.
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
# open question for the arrival into it, and exits 0 whether or not one is
# open: koto judges no gate after a failed action, so a question answered or
# withdrawn since `raised` must not hold the run here. 2 when the record
# cannot be read.
#
# --recorded, waiting_record's gate, exits 0 when decide_question names an
# open question for the arrival (on to done_waiting), and 1, with a finding,
# when none is open (back to decide_first, which reads the answer or the
# withdrawal; the arrival is unchanged, since that edge writes no
# decide_origin); 2 when the record cannot be read.
#
# --from exits with the code of the arrival's origin, so decide_first's edges
# can pair it with the submitted outcome: 10 analysis, 11 implementation,
# 12 introspection, 13 task_validation, 14 post_research_validation,
# 15 plan_validation, 16 deferral_approval, and /execute's
# 20 worktree_discipline_check; 2 when there is no arrival or its origin is no
# covered state.
#
# --laps exits 0 while the arrivals from the origin number at most 3, and 1,
# with a finding, from the fourth: the resume edges need 0.
#
# --approval exits 0 when, for a deferral_approval arrival, a question for the
# arrival has an answer in effect that is one of:
#   - a person's answer in effect that koto reads as verified;
#   - a settle whose basis holds such a person's answer (whether that answer
#     speaks to this deferral is the settling session's judgment; the gate
#     checks only what the settle rests on);
#   - a session's answer from the dispatcher the raiser had when it raised the
#     question, or a session above that one. The raiser's dispatched-by link
#     must sit earlier in its log than the question's escalate entry, each
#     link above it must be older than the raise, and every session of the
#     lineage newer than the raiser names that dispatcher or none.
# and a deciding attempt in this session cites that answer. 1 otherwise, with
# a finding; 2 when the record cannot be read.
#
# The limit of that check: a dispatched-by link is a claim a session records
# (`koto session link`), not a proof, and its dispatcher need not exist. The
# gate refuses a link recorded after the question, and a lineage whose
# dispatcher changes; it does not prove the dispatcher is a coordinator with
# authority over the work, and a run that declares a dispatcher before it
# raises, and answers as that dispatcher, is not stopped.
#
# --resume runs at resume_waiting, which entry routes to only when
# decide_question is in context (a run continuing one that stopped to wait),
# so a fresh run never calls it. It exits the origin code of the question's
# state (10 to 16, as --from) once a deciding attempt in this session cites
# the question's answer in its basis, and 1, with a finding, while the
# question is open, after it was withdrawn, when its answer carries no
# authority over the run (as --answer reads it), or before the answer is
# cited; 2 when the record cannot be read. Run directly in a session with no
# decide_question, it exits 0 and calls nothing.
#
# --answer prints the question's answer in effect as <session>:<id> when it
# carries authority over <session>'s run, by the rules --approval applies (a
# verified person's answer, a session answer from the raiser's dispatcher
# linked before the raise, or a settle whose basis holds a verified person's
# answer), and nothing otherwise; it exits 0 either way, and 2 when the record
# cannot be read. An answer from <session>'s own lineage never counts.
# <session> is the run the answer has to carry authority over: the raiser, or
# for a step's question /execute's run, the step's batch parent. A batch
# child has no dispatcher of its own, so its question counts its parent's
# dispatcher, never the parent. /execute's park.sh calls it, so the rule has
# one copy.
#
# Nothing here writes a decision. stdout carries the finding or the arrival
# name; koto's and jq's own messages reach stderr unchanged.
set -uo pipefail

LAP_CAP=3

SELF_DIR=$(cd "$(dirname "$0")" && pwd -P) || exit 2
ROOT_SELF=$(cd "$SELF_DIR/../../.." && pwd -P) || exit 2

MODE=check
case "${1:-}" in
    --arrive|--from|--laps|--record-question|--recorded|--approval|--resume) MODE="${1#--}"; shift ;;
    --answer) MODE=answer; shift ;;
esac
WF="${1:-}"
IDENTITY=""
if [ "$MODE" = answer ]; then
    IDENTITY="${2:-}"
    if [ -z "$WF" ] || [ -z "$IDENTITY" ] || [ "$#" -ne 2 ]; then
        echo "usage: decide-first-gate.sh --answer <session> <identity>" >&2
        exit 2
    fi
elif [ -z "$WF" ] || [ "$#" -ne 1 ]; then
    echo "usage: decide-first-gate.sh [--arrive|--from|--laps|--record-question|--recorded|--approval|--resume] <session>" >&2
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

# The covered states of every template whose decide_first runs this script,
# with the code --from exits with: one table, so the arrival derive() reads and
# the code decide_first's edges pair it with can't name different sets.
# /work-on's seven, then /execute's covered exit.
COVERED_CODES="analysis:10 implementation:11 introspection:12 task_validation:13
post_research_validation:14 plan_validation:15 deferral_approval:16
worktree_discipline_check:20"
COVERED=$(printf '%s\n' $COVERED_CODES | sed 's/:.*//')

code_of() {
    local e
    for e in $COVERED_CODES; do
        [ "${e%%:*}" = "$1" ] && { echo "${e#*:}"; return 0; }
    done
    return 1
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

# sha <text>: the text's sha256, as `koto context history` hashes a value.
sha() {
    if command -v sha256sum > /dev/null; then
        printf '%s' "$1" | sha256sum | cut -d' ' -f1
    else
        printf '%s' "$1" | shasum -a 256 | cut -d' ' -f1
    fi
}

# writes <session> <key>: the writes an edge's context_assignments made to the
# key in the session (writer transition), as "<seq> <hash>" lines, oldest
# first.
writes() {
    local h
    h=$(koto context history "$1" "$2") || unreadable "koto context history $1 $2 failed"
    printf '%s\n' "$h" | jq -r '.[] | select(.writer == "transition") | "\(.seq) \(.hash)"' \
        || unreadable "could not read the history of $2 in $1"
}

# derive: the run's arrivals, from koto's record (see the header). Sets ORIGIN
# (the newest arrival's covered state, empty when its value names none), N
# (the run's arrivals), LAPS (those from ORIGIN) and ARRIVAL (<ORIGIN>:<N>,
# empty when there is none or this session cleared it since).
derive() {
    local lin l w all="" newest="" own=0 clear=0 o
    command -v jq > /dev/null || unreadable "jq is not on PATH"
    lin=$(lineage) || exit 2
    for l in $lin; do
        w=$(writes "$l" decide_origin) || exit 2
        [ -n "$w" ] || continue
        all="$all$w
"
        [ -n "$newest" ] || newest=$(printf '%s\n' "$w" | tail -n 1)
        [ "$l" = "$WF" ] && own=${newest%% *}
    done
    N=$(printf '%s' "$all" | awk 'NF { n++ } END { print n + 0 }')
    LAPS=$(printf '%s' "$all" | awk -v h="${newest#* }" 'NF && $2 == h { n++ } END { print n + 0 }')
    ORIGIN=""
    for o in $COVERED; do
        [ "$(sha "$o")" = "${newest#* }" ] && ORIGIN=$o
    done
    w=$(writes "$WF" decide_arrival) || exit 2
    clear=$(printf '%s\n' "$w" | awk -v h="$(sha none)" 'NF && $2 == h { s = $1 } END { print s + 0 }')
    ARRIVAL=""
    if [ -n "$ORIGIN" ] && [ "$clear" -le "$own" ]; then
        ARRIVAL="$ORIGIN:$N"
    fi
}

# dispatcher_of <session>: the session koto's recorded origin names as its
# dispatcher, or nothing (none recorded, or no such session).
dispatcher_of() {
    local out rc=0
    out=$(koto session origin "$1") || rc=$?
    case "$rc" in
        0) ;;
        2) return 0 ;;
        *) unreadable "koto session origin $1 failed with exit $rc" ;;
    esac
    printf '%s\n' "$out" | jq -r 'select(.origin.state == "dispatched" and .origin.dispatcher_kind == "workflow") | .origin.dispatcher // empty' \
        || unreadable "could not read the origin of $1"
}

# link_first <session> <dispatcher> <field>: the seq or timestamp of the
# first write of the session's dispatched-by link to the dispatcher.
link_first() {
    local h
    h=$(koto context history "$1" "koto/links/dispatched-by/$2") || unreadable "koto context history $1 for its link to $2 failed"
    printf '%s\n' "$h" | jq -r --arg f "$3" '.[0][$f] // empty | tostring' || unreadable "could not read $1's link to $2"
}

# parent_of <session>: the batch parent koto spawned the session under, or
# nothing.
parent_of() {
    local out
    out=$(koto session hierarchy --json "$1") || unreadable "koto session hierarchy $1 failed"
    printf '%s\n' "$out" | jq -r --arg s "$1" \
        '[.members[]? | select(.name == $s) | .joined_by[]? | select(.via == "parent_workflow" and .holder == $s and .named != $s) | .named][0] // empty' \
        || unreadable "could not read the hierarchy of $1"
}

# above_at_raise <identity>: the sessions above the run whose session answer to
# the question counts, one per line (see --approval in the header): the
# raiser's dispatcher, linked before the question was raised, then each
# dispatcher above it linked before the raise; nothing when the raiser had no
# dispatcher then, or a newer session of the lineage names another. A batch
# child (an /execute step) has no dispatcher of its own: its question is read
# against its parent run's dispatcher, linked before the raise by timestamp,
# since the two sessions' log positions don't compare. The parent run itself
# is never among them.
above_at_raise() {
    local h r t shown e d first lin l s i p
    h=$(history "$1") || exit 2
    r=$(printf '%s\n' "$h" | jq -r '.raiser.name // empty')
    t=$(printf '%s\n' "$h" | jq -r '[.entries[]? | select(.entry == "raise")][0].time // empty')
    [ -n "$r" ] && [ -n "$t" ] || unreadable "the history of $1 names no raiser or raise time"
    d=$(dispatcher_of "$r") || exit 2
    if [ -n "$d" ]; then
        shown=$(show "$r" "${1##*/}") || exit 2
        e=$(printf '%s\n' "$shown" | jq -r '.decision.log_seq // empty')
        case "$e" in ''|*[!0-9]*) unreadable "the escalate entry of $1 has no log position" ;; esac
        first=$(link_first "$r" "$d" seq) || exit 2
        case "$first" in ''|*[!0-9]*) return 0 ;; esac
        [ "$first" -lt "$e" ] || return 0
    else
        p=$(parent_of "$r") || exit 2
        [ -n "$p" ] || return 0
        d=$(dispatcher_of "$p") || exit 2
        [ -n "$d" ] || return 0
        first=$(link_first "$p" "$d" timestamp) || exit 2
        [ -n "$first" ] && [[ "$first" < "$t" ]] || return 0
    fi
    lin=$(lineage) || exit 2
    for l in $lin; do
        [ "$l" = "$r" ] && break
        s=$(dispatcher_of "$l") || exit 2
        [ -z "$s" ] || [ "$s" = "$d" ] || return 0
    done
    printf '%s\n' "$d"
    s=$d
    i=0
    while [ "$i" -lt 20 ]; do
        d=$(dispatcher_of "$s") || exit 2
        [ -n "$d" ] || break
        first=$(link_first "$s" "$d" timestamp) || exit 2
        [ -n "$first" ] && [[ "$first" < "$t" ]] || break
        printf '%s\n' "$d"
        s=$d
        i=$((i + 1))
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

# person_answer <session> <id>: the entry is a person's answer in effect that
# koto reads as verified.
person_answer() {
    local s
    s=$(show "$1" "$2") || exit 2
    printf '%s\n' "$s" | jq -e '((.reading // .decision.reading) == "verified")
        and (.decision.decider.kind == "person")
        and (.status == null or .status == "in-effect")' > /dev/null
}

# authoritative_answer <identity>: the question's answer in effect as
# <session>:<id>, when it carries authority over this run; nothing otherwise.
authoritative_answer() {
    local h s id kind outcome shown b bs up lin
    h=$(history "$1") || exit 2
    s=$(printf '%s\n' "$h" | jq -r '.answer.session // empty')
    id=$(printf '%s\n' "$h" | jq -r '.answer.id // empty')
    outcome=$(printf '%s\n' "$h" | jq -r '.answer.outcome // empty')
    [ -n "$s" ] && [ -n "$id" ] || return 0
    shown=$(show "$s" "$id") || exit 2
    printf '%s\n' "$shown" | jq -e '.status == null or .status == "in-effect"' > /dev/null || return 0
    case "$outcome" in
        answered)
            if person_answer "$s" "$id"; then
                printf '%s:%s\n' "$s" "$id"
                return 0
            fi
            kind=$(printf '%s\n' "$shown" | jq -r '.decision.decider.kind // empty')
            [ "$kind" = session ] || return 0
            lin=$(lineage) || exit 2
            in_lines "$s" "$lin" && return 0
            up=$(above_at_raise "$1") || exit 2
            in_lines "$s" "$up" && printf '%s:%s\n' "$s" "$id"
            ;;
        settled)
            bs=$(printf '%s\n' "$shown" | jq -r '.decision.basis[]? | "\(.session):\(.id)"') \
                || unreadable "could not read the basis of $s:$id"
            for b in $bs; do
                if person_answer "${b%%:*}" "${b#*:}"; then
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
    local a as b bs
    as=$(printf '%s\n' "$ALL" | deciding | jq -r '.id') || unreadable "could not read the attempts"
    for a in $as; do
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
    derive
    [ -n "$ORIGIN" ] || unreadable "no edge into decide_first recorded a covered state as decide_origin"
    put decide_arrival "$ORIGIN:$N"
    printf '%s\n' "$ORIGIN:$N"
    exit 0
    ;;
from)
    derive
    c=$(code_of "$ORIGIN") || unreadable "no edge into decide_first recorded a covered state as decide_origin"
    exit "$c"
    ;;
laps)
    derive
    [ -n "$ORIGIN" ] || unreadable "no edge into decide_first recorded a covered state as decide_origin"
    [ "$LAPS" -le "$LAP_CAP" ] && exit 0
    finding "this is arrival $LAPS from $ORIGIN, past the cap of $LAP_CAP: resume is refused; stop with decided_next: stop, or raise the question"
    ;;
answer)
    command -v jq > /dev/null || unreadable "jq is not on PATH"
    authoritative_answer "$IDENTITY" || exit 2
    exit 0
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
check|record-question|recorded)
    derive
    arrival=$ARRIVAL
    [ -n "$arrival" ] || unreadable "no arrival is recorded at decide_first"
    mine=$(printf '%s\n' "$ALL" | jq -c --arg a "$arrival" 'select(.state == $a)') || unreadable "could not read the attempts"
    # The key is cleared before the questions are read, so an earlier value,
    # whatever it holds, is never read as one of them.
    if [ "$MODE" = record-question ]; then
        rc=0
        koto context exists "$WF" decide_question > /dev/null || rc=$?
        case "$rc" in
            0) koto context remove "$WF" decide_question > /dev/null || unreadable "could not clear context key decide_question" ;;
            1) ;;
            *) unreadable "koto context exists $WF decide_question failed with exit $rc; read koto's message above" ;;
        esac
    fi
    qs=$(questions "$arrival") || exit 2
    open=""
    for q in $qs; do
        if is_open "$q"; then open=$q; break; fi
    done
    if [ "$MODE" = record-question ]; then
        if [ -z "$open" ]; then
            echo "decide-first-gate: no open question names $arrival now; waiting_record's gate sends the run back to decide_first"
            exit 0
        fi
        put decide_question "$open"
        exit 0
    fi
    if [ "$MODE" = recorded ]; then
        recorded=$(ctx decide_question) || exit 2
        [ -n "$recorded" ] && in_lines "$recorded" "$qs" && is_open "$recorded" && exit 0
        finding "no question for $arrival is open now (answered or withdrawn since it was raised): back to decide_first, where the answer is cited or a new attempt recorded"
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
        # A session rewound to the arrival it waited from still holds that
        # arrival's question. Once the question is closed with an answer, the
        # deciding attempt must cite it: the run resumes on the answer to the
        # question it raised for this stop, not on a decision of its own
        # made around it. A question withdrawn without an answer leaves the
        # session's own deciding attempt standing. An answer without authority
        # over the run (its own, or a session's that is not its dispatcher
        # linked before the raise) is no answer to resume on, and does not
        # leave the run free to decide around it either.
        question=$(ctx decide_question) || exit 2
        if [ -n "$question" ]; then
            h=$(history "$question") || exit 2
            answer=""
            if printf '%s\n' "$h" | jq -e --arg a "$arrival" '.question.state == $a and .open != true' > /dev/null; then
                answer=$(authoritative_answer "$question") || exit 2
                raw=$(printf '%s\n' "$h" | jq -r '.answer | select(. != null) | "\(.session):\(.id)"') \
                    || unreadable "could not read the history of $question"
                if [ -z "$answer" ] && [ -n "$raw" ]; then
                    finding "the answer $raw to $question carries no authority over this run (its own, or from a session that is not its dispatcher linked before the raise): raise the question again for $arrival"
                fi
            fi
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
    if [ -n "$(printf '%s\n' "$mine" | jq -c 'select(.result == "undecided")')" ]; then
        finding "the undecided attempt for $arrival has no open question naming it: raise one with shirabe question raise --attempt <id> --state $arrival, or record a deciding attempt"
    fi
    finding "no attempt is recorded for $arrival: record one with shirabe question attempt --in $WF --state $arrival before leaving decide_first"
    ;;
approval)
    derive
    arrival=$ARRIVAL
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
    finding "no question raised for $arrival has an answer from a verified person, or from the dispatcher the run had when it raised the question: an answer given by this run, a session it continues, a session it did not name as its dispatcher before raising, or a lineage whose dispatcher changed approves nothing"
    ;;
resume)
    h=$(history "$question") || exit 2
    state=$(printf '%s\n' "$h" | jq -r '.question.state // ""') || unreadable "could not read the history of $question"
    c=$(code_of "${state%%:*}") || unreadable "the question's state '$state' names no covered state"
    if printf '%s\n' "$h" | jq -e '.open == true' > /dev/null; then
        finding "the question $question is still open: this run continues once it is answered"
    fi
    raw=$(printf '%s\n' "$h" | jq -r '.answer | select(. != null) | "\(.session):\(.id)"') \
        || unreadable "could not read the history of $question"
    [ -n "$raw" ] || finding "the question $question was closed without an answer: there is nothing to continue from; start the work fresh"
    answer=$(authoritative_answer "$question") || exit 2
    [ -n "$answer" ] || finding "the answer $raw to $question carries no authority over this run (its own, or from a session that is not its dispatcher linked before the raise): raise the question again"
    cited "$answer" && exit "$c"
    finding "the answer $answer is not cited yet: record shirabe question attempt --in $WF --result decided --basis $answer before going back to ${state%%:*}"
    ;;
esac
