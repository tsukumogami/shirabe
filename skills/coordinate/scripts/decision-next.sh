#!/usr/bin/env bash
# decision-next.sh -- the one owed predicate of the decision flow. The
# decision_next state's default action, and, with --owed, the reading
# dispatch_check's deferral-check.sh and pick_facts' pick-facts.sh make of it.
#
# Usage:
#   decision-next.sh --session S                  route: print the sealed verdict
#   decision-next.sh --session S --owed dispatch|pick [--parsed FILE]
#
# --parsed, with --owed only, names the record this session's caller read in
# the same tick: rs_record's output FILE, readable (otherwise usage, 64).
# pick-facts.sh and deferral-check.sh pass their own, so the record is read
# once in the tick (shirabe#840, shirabe#1156). Nothing checks that FILE
# is this session's record; only a caller that just read it may pass it.
# Without --parsed the record is read here.
#
# It reads the Decisions section (state-decision.sh --list, or its projection
# over the --parsed record) and the session log (coord-log.sh). The rules, in
# routing order; the first that holds is the verdict:
#
#   1 carry             never printed now: a discipline rotation carries its
#                       predecessor's unsettled entries and Next decision when
#                       it opens (state-open.sh --carry), so nothing is left
#                       to carry by the time this runs; the rule keeps its
#                       place in the order
#   2 unrecorded-open   the latest report_questions visit sealed a list, the run
#                       went on to decision_open and not to wait since, and no
#                       Source or Evidence line carries this run's
#                       `report <seq>.` stamp for it
#     unrecorded-answer the latest answer (a `wait` answer event, or
#                       escalate_send's `answered`) reached decision_answer and
#                       no line carries this run's `wait <seq>` stamp for it (a
#                       re-sent identical answer writes its own stamped line
#                       too). An arrival state-decision.sh can't write (no
#                       decision, one that isn't a plain number, one the
#                       record has no entry for, or an answer with no plain
#                       round) is never owed: routing back to it would loop
#                       with no way out
#     unrecorded-evidence  likewise for the latest `wait` evidence event
#     unrecorded-raise  the latest visit to decision_raise left no entry with
#                       this run's `raise <seq>` stamp; when that visit is a
#                       park's (the pick before it chose await_decision, with
#                       no visit to wait between), instead, until the next
#                       pick: no `decision` Work row
#                       (state-stored-set.sh --list) parks the unit pick named,
#                       on a new entry or on one already open
#   3 withdraw <n>      an entry owes a withdrawal
#   4 reply <n>         an entry owes a reply
#   5 redirect <n> <seq>  a report of this run (its `report <seq>.` stamps) has
#                       an entry with the addressed mark and no entry with a
#                       `redirect <seq>` line; <n> is the first entry it wrote
#   6 escalate <n>      an entry owes its escalation
#   7 take <n>          a proposed entry, lowest identifier first
#   8 verdict <n>       an entry awaiting a verdict with none recorded, lowest
#                       first (a held or queued verdict is recorded); the entry
#                       goes to the detail key coord/decision.json
#   9 clear-report      nothing owed, and the latest report_questions visit
#                       sealed a list for a report with a holding, routed to
#                       decision_open, and neither classify_report nor wait has
#                       been entered since: the report is still to classify
#     clear             nothing owed
#
# A record moved from a GitHub record may keep archived entries (an Archived
# line, and this run's stamps on them as kept stamps), which the rules read as
# they read a row's. An arrival naming an archived entry is writable:
# state-decision.sh restores the entry first.
#
# --owed prints the rule that blocks the given step, or `none`, and seals and
# writes nothing. What each rule blocks (the DESIGN's table):
#   dispatch  before the run's first dispatch: every rule 1 to 8;
#             after it: rules 2 to 6
#   pick      every rule 1 to 8
# A held entry, and an escalated entry that owes nothing, block nothing.
#
# Exit codes: 0 a verdict (or with --owed, a rule or `none`) was printed; 2 a
# read failed; 64 usage.
set -uo pipefail

PROG=decision-next
HERE=$(cd "$(dirname "$0")" && pwd)
SESSION= OWED= PARSED= NO_SEAL=0
usage() { sed -n '/^# Usage:/,/^# It reads/p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 64; }
while [ $# -gt 0 ]; do
    case "$1" in
        --session) [ $# -ge 2 ] || usage; SESSION=$2; shift 2 ;;
        --owed) [ $# -ge 2 ] || usage; OWED=$2; shift 2 ;;
        --parsed) [ $# -ge 2 ] || usage; PARSED=$2; shift 2 ;;
        *) usage ;;
    esac
done
[ -n "$SESSION" ] || usage
[ -z "$PARSED" ] || { [ -n "$OWED" ] && [ -r "$PARSED" ]; } || usage
case "$OWED" in ''|dispatch|pick) ;; *) usage ;; esac
SCOPE= NAME= REPO=
. "$HERE/state-common.sh"
lib_facts
lib_run_stamp
T=$(mktemp -d "${TMPDIR:-/tmp}/decision-next.XXXXXX") || lib_die2 "cannot make a temporary directory"
trap 'rm -rf "$T"' EXIT
# One record read for the step: the Decisions section, and the Work rows a
# park is judged on, come from one read of the sections they print
# (shirabe#1315).
rs_once_begin "$T/once" "decisions run standing work" || lib_die2 "cannot make a temporary directory"
CL() { bash "$HERE/coord-log.sh" "$@" --session "$SESSION"; }

# The section and the log facts the rules read.
if [ -n "$PARSED" ]; then
    jq -c -L "$HERE" 'include "state-schema"; decisions_list' "$PARSED" > "$T/section.json" || lib_die2 "cannot read the Decisions section"
else
    bash "$HERE/state-decision.sh" --session "$SESSION" --list > "$T/section.json" 2> "$T/rd.err" \
        || { cat "$T/rd.err" >&2; lib_die2 "cannot read the Decisions section"; }
fi
# The latest entry into each state the rules read, 0 when none, in one read
# of the log (coord-log.sh entries) rather than one coord-log.sh per state.
# READS is the one list of <state>:<variable>: the request is built from it,
# and each variable is set from its state's line only after the line was
# found and its seq is a number, so a state added here can't be left unread,
# and a short or garbled answer stops the run instead of reading as 0.
READS="dispatch:DISPATCH_SEQ report_questions:RQ_SEQ decision_open:OPEN_SEQ wait:WAIT_SEQ
classify_report:CLASSIFY_SEQ decision_answer:ANSWER_SEQ decision_evidence:EVID_SEQ decision_raise:RAISE_SEQ"
states=
for pair in $READS; do states="$states${states:+,}${pair%%:*}"; done
ENTRIES=$(CL entries --states "$states") || lib_die2 "cannot read the session log"
for pair in $READS; do
    rest=$'\n'"$ENTRIES"
    case "$rest" in *$'\n'"${pair%%:*} "*) ;; *) lib_die2 "cannot read the session log" ;; esac
    rest=${rest#*$'\n'"${pair%%:*} "}
    sq=${rest%%[ $'\n']*}
    case "$sq" in ''|*[!0-9]*) lib_die2 "cannot read the session log" ;; esac
    printf -v "${pair#*:}" '%s' "$sq"
done
DISPATCHED=false
[ "$DISPATCH_SEQ" = 0 ] || DISPATCHED=true
# ev_json <state> [where]: the latest evidence at it, {} when none.
ev_json() {
    local e st=$1; shift
    e=$(CL evidence --state "$st" "$@")
    case $? in 0) printf '%s' "$e" ;; 1) printf '{}' ;; *) lib_die2 "cannot read the session log" ;; esac
}
QCAP=$(CL capture --name QUESTIONS --state report_questions 2>/dev/null) || QCAP=
WAIT_ANS=$(ev_json wait --where event=answer)
TOOL_ANS=$(ev_json escalate_send --where sent=answered)
WAIT_EVI=$(ev_json wait --where event=evidence)
RCAP=$(CL capture --name REPORT --state report_facts 2>/dev/null) || RCAP=
# The latest visit to decision_raise belongs to a park when the pick before it
# chose await_decision and the run wasn't back at wait in between: the visit
# from pick, or one the run came back for. A park is judged by the unit pick
# named having its decision row, not by a stamp, since a visit it came back for
# opens nothing; it is judged until the next pick, and the chain can't reach a
# pick before the row is there. The Work section (state-stored-set.sh, its one
# reader) is read only while it is judged.
PARK=false CHAIN=false PARK_UNIT= PARK_SINCE=
if [ "$RAISE_SEQ" -gt 0 ]; then
    PICK_EV=$(ev_json pick --before "$RAISE_SEQ")
    PICK_SEQ=$(printf '%s' "$PICK_EV" | jq -r '.seq // 0')
    WAIT_BEFORE=$(CL entry --state wait --before "$RAISE_SEQ")
    case $? in 0|1) ;; *) lib_die2 "cannot read the session log" ;; esac
    WAIT_BEFORE=${WAIT_BEFORE%% *}
    if [ "$(printf '%s' "$PICK_EV" | jq -r '.fields.choice // ""')" = await_decision ] && [ "${WAIT_BEFORE:-0}" -lt "$PICK_SEQ" ]; then
        CHAIN=true
        [ "$(ev_json pick | jq -r '.seq // 0')" -gt "$RAISE_SEQ" ] || PARK=true
    fi
fi
if [ "$PARK" = true ]; then
    PARK_UNIT=$(printf '%s' "$PICK_EV" | jq -r '.fields.unit // "" | tostring')
    # The pick's minute: a park row older than the pick is an earlier park.
    PARK_SINCE=$(printf '%s' "$PICK_EV" | jq -r '(.timestamp // "")[0:16]')
    if [ -n "$PARSED" ]; then
        jq -c -L "$HERE" 'include "state-schema"; state_list' "$PARSED" > "$T/state.json" || lib_die2 "cannot read the Work section"
    else
        bash "$HERE/state-stored-set.sh" --session "$SESSION" --list > "$T/state.json" 2> "$T/rs.err" \
            || { cat "$T/rs.err" >&2; lib_die2 "cannot read the Work section"; }
    fi
else
    echo '{"work":[]}' > "$T/state.json"
fi

# Rule 1: the carry. A rotation carried its predecessor's unsettled entries
# when it opened (state-open.sh --carry), so there is nothing left to carry.
CARRY=false

# Rules 2 to 9, over the section and the log facts.
NEXT=$(jq -r -L "$HERE" --arg run "$RUN" --argjson carry "$CARRY" --arg qcap "$QCAP" --arg rcap "$RCAP" \
    --argjson rq "$RQ_SEQ" --argjson op "$OPEN_SEQ" --argjson wt "$WAIT_SEQ" --argjson cls "$CLASSIFY_SEQ" \
    --argjson an "$ANSWER_SEQ" --argjson evs "$EVID_SEQ" --argjson rs "$RAISE_SEQ" \
    --argjson wans "$WAIT_ANS" --argjson tans "$TOOL_ANS" --argjson wevi "$WAIT_EVI" \
    --argjson park "$PARK" --argjson chain "$CHAIN" --arg pu "$PARK_UNIT" --arg since "$PARK_SINCE" --arg host "$REPO" --slurpfile st "$T/state.json" '
  include "state-schema";
  .entries as $es
  | (.archived // []) as $archived
  | [d_section_stamps[] | select(.run == $run)] as $mine
  # A raise from pick is done when the unit it named has its decision row,
  # on a new entry or on one already open, written since that pick.
  | ($park and (any(($st[0].work // [])[]; .kind == "decision" and (.updated // "")[0:16] >= $since
        and (.item == $pu or .item == ($host + $pu) or ($host + .item) == $pu)) | not)) as $unparked
  | def stamped($k; $s): any($mine[]; .kind == $k and .seq == $s);
    def report_stamped($s): any($mine[]; .kind == "report" and (.seq | split(".")[0]) == $s);
    def lowest(f): [$es[] | select(f) | .decision | tonumber] | min;
    ($qcap | split(" ")) as $q
  | ($q[0] == "questions" and $rq > 0) as $listed
  | ([$q[] | select(startswith("keyseal:")) | split(":")[1]] | first // "") as $qseq
  | ($listed and $op > $rq and $wt < $rq) as $to_open
  # The latest answer, by either route, and whether it reached decision_answer.
  | ([$wans, $tans] | map(select(.seq != null)) | max_by(.seq)) as $ans
  # An arrival state-decision.sh can write: a decision that is a plain
  # number with an entry in the record, and for an answer a plain-number
  # round. Anything else it refuses, so owing it would loop back forever.
  | def writable($a; $round):
      (($a.fields.decision // "") | tostring) as $d
      | ($d | test("^[1-9][0-9]*$")) and (any($es[]; .decision == $d) or (($archived | index($d | tonumber)) != null))
        and ((($round | not)) or ((($a.fields.round // "") | tostring) | test("^[1-9][0-9]*$")));
  (if $ans == null or (writable($ans; true) | not) then false else $an > $ans.seq end) as $ans_taken
  # Every answer state-decision.sh takes, a re-sent identical one included,
  # writes a line with its arrival stamp, so the stamp alone says it landed; an
  # answer line without it may be another answer for the same round.
  | ($ans_taken and stamped("wait"; ($ans.seq | tostring))) as $ans_recorded
  | (if $wevi.seq == null or (writable($wevi; false) | not) then false else $evs > $wevi.seq end) as $evi_taken
  # Rule 5: the reports of this run that addressed someone and have no redirect.
  | ([$mine[] | select(.kind == "report") | .seq | split(".")[0]] | unique) as $reports
  | ([ $reports[] as $r
       | select(any($mine[]; .kind == "report" and (.seq | split(".")[0]) == $r and (.text | startswith(d_addressed_mark))))
       | select(any($mine[]; .kind == "redirect" and .seq == $r) | not)
       | {r: $r, n: ([$mine[] | select(.kind == "report" and (.seq | split(".")[0]) == $r) | .decision | tonumber] | min)} ]
     | sort_by(.n) | first) as $redir
  | if $carry then "carry"
    elif $to_open and ($qseq != "") and (report_stamped($qseq) | not) then "unrecorded-open"
    elif $ans_taken and ($ans_recorded | not) then "unrecorded-answer"
    elif $evi_taken and (stamped("wait"; ($wevi.seq | tostring)) | not) then "unrecorded-evidence"
    elif $unparked then "unrecorded-raise"
    elif ($chain | not) and $rs > 0 and (stamped("raise"; ($rs | tostring)) | not) then "unrecorded-raise"
    elif lowest(.owed == "withdrawal") != null then "withdraw \(lowest(.owed == "withdrawal"))"
    elif lowest(.owed == "reply") != null then "reply \(lowest(.owed == "reply"))"
    elif $redir != null then "redirect \($redir.n) \($redir.r)"
    elif lowest(.owed == "escalation") != null then "escalate \(lowest(.owed == "escalation"))"
    elif lowest(.state == "proposed") != null then "take \(lowest(.state == "proposed"))"
    elif lowest(.state == "coordinator-verdict" and (.verdict // "") == "") != null
      then "verdict \(lowest(.state == "coordinator-verdict" and (.verdict // "") == ""))"
    elif $to_open and $cls < $rq and (($rcap | split(" "))[0] == "holding") then "clear-report"
    else "clear" end' "$T/section.json") || lib_die2 "cannot read the owed rules"
WORD=${NEXT%% *}

# --owed: what blocks the step, without sealing or writing anything.
if [ -n "$OWED" ]; then
    case "$WORD" in
        clear|clear-report) printf 'none\n' ;;
        carry|take|verdict)
            if [ "$OWED" = pick ] || [ "$DISPATCHED" = false ]; then printf '%s\n' "$WORD"; else printf 'none\n'; fi ;;
        *) printf '%s\n' "$WORD" ;;
    esac
    exit 0
fi

if [ "$WORD" = verdict ]; then
    jq -c --arg n "${NEXT#* }" '.entries[] | select(.decision == $n)' "$T/section.json" > "$T/decision.json" || lib_die2 "cannot write the entry"
    lib_emit decision_next "$NEXT" coord/decision.json "$T/decision.json"
fi
lib_emit decision_next "$NEXT" "" ""
