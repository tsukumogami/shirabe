#!/usr/bin/env bash
# record-confirm.sh -- the check action of states record and verified_confirm:
# is the change the run's last step implies on GitHub yet?
#
# Every spoke that changes what the record must hold returns through `record`,
# whose gate holds until this script sees the change in the live body. What it
# expects comes from the session log, never from an argument: the source state
# is the `from` of the latest entry into `record`, and its last evidence (or,
# for a check state, its own sealed capture) says what should have changed.
# Every case also needs the record's Written: time to be later than a point in
# the log, so an older body that happens to match doesn't count. For a step
# whose directive writes the record before the evidence that closes it, the
# point is when the step became due (step_start, and the case pattern that
# calls it is the list): the latest entry, before the step's evidence, into
# `wait` (the hub) or `record_find` (the run's start or a re-read of its
# record, on the way to posture_ask), whichever is later. For dispatch it is
# the DISPATCH_CHECK capture; for any other evidence-closed step, the
# evidence's own time; for a check state, its capture.
#
#   dispatch        a Holdings row whose Worker is the evidence's topic, which
#                   must be the topic dispatch_check sealed (`ok <topic>`);
#                   another topic is a conflict. Written: is compared with
#                   the DISPATCH_CHECK capture, not the evidence, since the
#                   dispatch path writes the holding before `sent`. When the
#                   pick this dispatch came from chose send_execution, the
#                   row must also read Phase `executing`: a send that changed
#                   nothing never confirms (shirabe#553)
#   leg_spent       (`replaced`) the evidence's topic's row on a leg other
#                   than the spent one (the WAIT_REQ and WAIT_LEG captures),
#                   and no row on the spent leg (shirabe#506)
#   surface         (merge_table) the unit's row has a Verified head; the unit
#                   is the one the run's latest arrival before the source
#                   names (below).
#                   When surface was entered from land_merge on `merge: held`
#                   (the human directed a hold the workspace doesn't require),
#                   the row's Phase must also be `held`
#   merge_confirm,  from MERGE_CONFIRM / MERGED_FACTS: `merged <pr> <sha>` means
#   merged_facts    the unit's Holdings row is still there with its Pull
#                   request cell blank: a confirmed merge clears the cell
#                   and keeps the row until the teardown removes it;
#                   `unconfirmed <pr> <sha>` means a Side effects row whose
#                   Target names <owner/repo>#<pr> (or its github.com URL),
#                   the repository being the one the unit's row links, with
#                   Verified head <sha>
#   teardown        `kept`: only the newer Written: time (`done`, from before
#                   the dispatch path's destroy, still means no Holdings row)
#   destroy         (the dispatch path's teardown) `destroyed`: no Holdings row
#                   for the topic; `handed_over`: no Holdings row for it and a
#                   Side effects row whose Target names it. The topic comes from
#                   the sealed teardown inventory (TEARDOWN_SEAL, key
#                   teardown_verdict, its `topic <t>` line), never from a
#                   context key.
#   decision_apply  `reversal`: a Reversals row dated at or after that point;
#                   `deferral`: a Deferrals row raised at or after it
#   posture_ask     a Reversals row at or after that point, From `the human`,
#                   whose Reversed or Now mentions posture
#
# With --verified (state verified_confirm): the VERIFIED capture
# (`verified <pr> <sha>`, sealed at a real visit of verify_board) must equal
# the Verified head of the unit's Holdings row, which must link #<pr>; when
# the pull request's live head, read from the repository that row links, is
# no longer <sha> the verdict is `moved`.
#
# The unit is always found by its Worker (dispatch topic) from the log, as
# report-facts.sh finds it (record-common.sh lib_unit): the latest `wait`
# evidence naming a unit, or on the leg path (wait_leg, then take_report) the
# Holdings row whose Return path is the leg the engine captured, whichever
# arrived later; with neither, the latest `dispatch` evidence's `topic`. A
# pull request is never found by its bare number, since two units in
# different repositories can both hold #12: its row is the unit's row, and its
# repository is the one in that row's full Pull request URL.
#
# Verdict tokens: confirmed | waiting (no route: the state stays blocked until
# the coordinator writes the record and ticks) | conflict (the body is missing
# or not canonical, or the log gives nothing to confirm) | moved (--verified) |
# directed (the run has a `koto next --to`).
#
# Usage:
#   record-confirm.sh --session S [--verified]
#   record-confirm.sh --session S --scope roadmap|discipline --name N --repo O/R
#                     --ref N [--verified] [--no-seal]                  (tests)
#
# The detail goes to context key coord/record_confirm.json as data.
#
# Exit codes: 0 a verdict was printed; 2 a read failed; 64 usage.
#
# GitHub reads: gh issue view N --repo R --json state,body |
# gh pr view N --repo R --json state,body; with --verified,
# gh pr view <pr> --repo <the unit's row's repository> --json headRefOid.
#
# The session log is read only through coord-log.sh.
set -uo pipefail

PROG=record-confirm
HERE=$(cd "$(dirname "$0")" && pwd)
SESSION= SCOPE= NAME= REPO= REF=
VERIFIED=0 NO_SEAL=0

usage() { sed -n '/^# Usage:/,/^# Exit codes:/p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 64; }
while [ $# -gt 0 ]; do
    case "$1" in
        --session) [ $# -ge 2 ] || usage; SESSION=$2; shift 2 ;;
        --scope) [ $# -ge 2 ] || usage; SCOPE=$2; shift 2 ;;
        --name) [ $# -ge 2 ] || usage; NAME=$2; shift 2 ;;
        --repo) [ $# -ge 2 ] || usage; REPO=$2; shift 2 ;;
        --ref) [ $# -ge 2 ] || usage; REF=$2; shift 2 ;;
        --verified) VERIFIED=1; shift ;;
        --no-seal) NO_SEAL=1; shift ;;
        *) usage ;;
    esac
done
# The expectation lives in the session log, so a session is always needed.
[ -n "$SESSION" ] || usage
. "$HERE/record-common.sh"
lib_facts
STATE_NAME=record
[ "$VERIFIED" = 1 ] && STATE_NAME=verified_confirm

T=$(mktemp -d "${TMPDIR:-/tmp}/record-confirm.XXXXXX")
trap 'rm -rf "$T"' EXIT

VERDICT= REASON= SOURCE= EVT= WRITTEN= EXPECT=
finish() {
    # event_time is the point Written: was compared with: the step's start for
    # the steps step_start covers, else the event's own time.
    jq -n --arg v "$VERDICT" --arg r "$REASON" --arg s "$SOURCE" --arg e "$EVT" --arg w "$WRITTEN" --arg x "$EXPECT" \
        --arg ref "$REF" '{verdict: $v, reason: $r, source: $s, event_time: $e, written: $w, expectation: $x, ref: $ref}' > "$T/detail.json"
    lib_emit "$STATE_NAME" "$VERDICT" coord/record_confirm.json "$T/detail.json"
}

OUT=$(bash "$HERE/coord-log.sh" directed-since --session "$SESSION" --from 0 2>/dev/null)
case $? in
    0) ;;
    1) VERDICT=directed; REASON="directed transition $(printf '%s' "$OUT" | head -1)"; finish ;;
    *) lib_die2 "cannot read the session log" ;;
esac
lib_log_readable || lib_die2 "cannot read the session log"
if ! lib_run_ref; then VERDICT=conflict; REASON="the run has no found record"; finish; fi

# The live body.
if [ "$SCOPE" = roadmap ]; then
    gh issue view "$REF" --repo "$REPO" --json state,body --jq '.body // ""' > "$T/live.md" 2> /dev/null < /dev/null || lib_die2 "cannot read issue #$REF"
else
    gh pr view "$REF" --repo "$REPO" --json state,body --jq '.body // ""' > "$T/live.md" 2> /dev/null < /dev/null || lib_die2 "cannot read pull request #$REF"
fi
if ! [ -s "$T/live.md" ] || ! lib_parse "$T/live.md" "$T/rec.json"; then
    VERDICT=conflict; REASON="the record body is missing or not canonical"; finish
fi
WRITTEN=$(jq -r '.written' "$T/rec.json")

# later <written> <event-time>: Written: (whole seconds) is strictly after the
# event's second; a write in the same second can't be ordered, so it waits.
later() { [ "${1:0:19}" \> "${2:0:19}" ]; }

# The session log, through coord-log.sh. Each sets a variable rather than
# printing, so a failed read exits 2 from here instead of from a subshell.
# evidence <state> <before-seq>: EVJ, the last evidence event there, or empty.
evidence() {
    EVJ=$(bash "$HERE/coord-log.sh" evidence --session "$SESSION" --state "$1" --before "$2" 2> /dev/null)
    [ $? -eq 2 ] && lib_die2 "cannot read the session log"
    return 0
}
# entry <state> [<before-seq>]: ENT_SEQ and ENT_FROM of the latest entry into
# <state>, or both empty.
entry() {
    local e
    if [ -n "${2-}" ]; then
        e=$(bash "$HERE/coord-log.sh" entry --session "$SESSION" --state "$1" --before "$2" 2> /dev/null)
    else
        e=$(bash "$HERE/coord-log.sh" entry --session "$SESSION" --state "$1" 2> /dev/null)
    fi
    [ $? -eq 2 ] && lib_die2 "cannot read the session log"
    ENT_SEQ= ENT_FROM=
    [ -n "$e" ] || return 0
    ENT_SEQ=${e%% *} ENT_FROM=${e#* }
}
# step_start <source> <before-seq>: sets EVT to the moment the step became
# due: the latest entry, before <before-seq>, into one of the two states a
# step's chain starts from, `wait` (the hub) or `record_find` (where the run
# starts, and where it goes back to re-read its record, on the way to
# posture_ask), whichever came later; with neither, the entry into <source>.
# Not the evidence that leaves <source>: the directives write the record
# before they submit that evidence (a merge-order table's Verified head is
# written at verified_confirm, a decision is recorded before it's even ticked
# at the hub), so a gate on the evidence's time can only be passed by
# rewriting the record with no change. Anything written since the step became
# due belongs to it; a body from before that doesn't count.
step_start() {
    local st e best= bseq=-1
    for st in wait record_find "$1"; do
        # The source's own entry counts only when neither start is in the log.
        [ "$st" = "$1" ] && [ -n "$best" ] && break
        e=$(bash "$HERE/coord-log.sh" entry --session "$SESSION" --state "$st" --before "$2" --with-time 2> /dev/null)
        [ $? -eq 2 ] && lib_die2 "cannot read the session log"
        [ -n "$e" ] || continue
        if [ "${e%% *}" -gt "$bseq" ]; then bseq=${e%% *}; best=$e; fi
    done
    [ -n "$best" ] || { VERDICT=conflict; REASON="the log has no entry into wait, record_find or $1 before its evidence"; finish; }
    EVT=${best##* }
}
has_value() { # has_value <word>: some evidence field's value is exactly <word>
    printf '%s' "$EV" | jq -e --arg w "$1" '[.fields[] | strings] | index($w) != null' > /dev/null
}
holds() { # holds <jq test over the record> [jq args...]: the expectation
    local f=$1; shift
    jq -e "$@" "$f" "$T/rec.json" > /dev/null
}
rec_holdings() { jq -c '.holdings' "$T/rec.json"; }
# arrival_unit <before-seq>: UNIT, the unit the run's latest arrival names
# (lib_unit, resolving a leg against this record's rows), or empty. A leg no
# row carries is a unit with no row, as a topic with no row is on the message
# path (its row may be the one the step removed): UNIT is then the leg itself,
# which no Worker cell can equal.
arrival_unit() {
    lib_unit "$1" "" rec_holdings
    [ -n "$UNIT_LEG" ] && [ "$LEG_ROWS" = 0 ] && UNIT=$UNIT_LEG
    return 0
}
# unit_topic <before-seq>: UNIT, the unit the step is about, by its Worker: the
# latest arrival's unit, else, when the run has had no arrival, the latest
# `dispatch` evidence's topic.
unit_topic() {
    lib_unit "$1" "" rec_holdings
    [ $? -eq 1 ] || { [ -n "$UNIT_LEG" ] && [ "$LEG_ROWS" = 0 ] && UNIT=$UNIT_LEG; return 0; }
    evidence dispatch "$1"
    [ -n "$EVJ" ] && UNIT=$(printf '%s' "$EVJ" | jq -r '.fields.topic // empty')
    return 0
}
# unit_row <topic>: sets ROW (the Holdings row whose Worker is the topic, or
# empty) and, when its Pull request cell is a full link, ROW_REPO and ROW_PR.
unit_row() {
    ROW=$(jq -c --arg t "$1" '[.holdings[] | select(.worker == $t)][0] // empty' "$T/rec.json")
    ROW_REPO= ROW_PR=
    [ -n "$ROW" ] || return 0
    lib_pr_link "$(printf '%s' "$ROW" | jq -r '.pull_request // ""')" || return 0
    ROW_PR=$LINK_NUM ROW_REPO=$LINK_REPO
}

if [ "$VERIFIED" = 1 ]; then
    SOURCE=verify_board
    V=$(bash "$HERE/coord-log.sh" capture --session "$SESSION" --name VERIFIED 2>/dev/null)
    case $? in 0) ;; 1) VERDICT=conflict; REASON="no VERIFIED capture in the run"; finish ;; *) lib_die2 "cannot read the captures" ;; esac
    bash "$HERE/coord-log.sh" check --session "$SESSION" --state verify_board --sealed "$V" --any-visit > /dev/null 2>&1
    case $? in 0) ;; 1) VERDICT=conflict; REASON="the VERIFIED capture fails its seal"; finish ;; *) lib_die2 "cannot check the seal" ;; esac
    set -- $V
    PR=${2-} SHA=${3-}
    if [ "${1-}" != verified ] || ! [[ $PR =~ $RE_NUM ]] || ! [[ $SHA =~ $RE_SHA ]]; then
        VERDICT=conflict; REASON="the VERIFIED capture is not verified <pr> <sha>"; finish
    fi
    entry verified_confirm; VSEQ=$ENT_SEQ
    [ -n "$VSEQ" ] || { VERDICT=conflict; REASON="the log has no entry into verified_confirm"; finish; }
    unit_topic "$VSEQ"
    [ -n "$UNIT" ] || { VERDICT=conflict; REASON="the log names no unit for the verified pull request"; finish; }
    EXPECT="the Holdings row for $UNIT links #$PR and has Verified head $SHA"
    unit_row "$UNIT"
    if [ -z "$ROW" ]; then VERDICT=waiting; REASON="no Holdings row for $UNIT yet"; finish; fi
    if [ "$ROW_PR" != "$PR" ]; then
        VERDICT=conflict; REASON="the Holdings row for $UNIT links $(printf '%s' "$ROW" | jq -r '.pull_request'), not #$PR"; finish
    fi
    EXPECT="the Holdings row for $UNIT links $ROW_REPO#$PR and has Verified head $SHA"
    LIVE=$(gh pr view "$PR" --repo "$ROW_REPO" --json headRefOid --jq .headRefOid 2> /dev/null < /dev/null) || lib_die2 "cannot read $ROW_REPO#$PR's head"
    if [ "$LIVE" != "$SHA" ]; then VERDICT=moved; REASON="$ROW_REPO#$PR's head is now $LIVE"; finish; fi
    if [ "$(printf '%s' "$ROW" | jq -r .verified_head)" = "$SHA" ]; then
        VERDICT=confirmed; REASON="the verified head is recorded"
    else
        VERDICT=waiting; REASON="the verified head is not in the record yet"
    fi
    finish
fi

# The latest entry into `record`, and where it came from.
entry record
[ -n "$ENT_SEQ" ] || { VERDICT=conflict; REASON="the log has no entry into record"; finish; }
ESEQ=$ENT_SEQ
SOURCE=$ENT_FROM

case "$SOURCE" in
dispatch|surface|teardown|destroy|decision_apply|posture_ask|leg_spent)
    evidence "$SOURCE" "$ESEQ"; EV=$EVJ
    [ -n "$EV" ] || { VERDICT=conflict; REASON="no evidence from $SOURCE before record"; finish; }
    EVT=$(printf '%s' "$EV" | jq -r .timestamp)
    EVSEQ=$(printf '%s' "$EV" | jq -r .seq)
    # The steps whose directives write the record before the closing
    # evidence are compared with the moment they became due (step_start);
    # this case pattern is the list. dispatch keeps its DISPATCH_CHECK
    # capture (below), and teardown and destroy, which write after it, keep
    # the evidence's own time.
    case "$SOURCE" in surface|decision_apply|posture_ask|leg_spent) step_start "$SOURCE" "$EVSEQ" ;; esac
    MIN=${EVT:0:16}
    ;;
merge_confirm|merged_facts)
    CAPNAME=MERGE_CONFIRM
    [ "$SOURCE" = merged_facts ] && CAPNAME=MERGED_FACTS
    CAP=$(bash "$HERE/coord-log.sh" captures --session "$SESSION" --name "$CAPNAME" --before "$ESEQ" 2> /dev/null)
    [ $? -eq 2 ] && lib_die2 "cannot read the session log"
    CAP=$(printf '%s' "$CAP" | tail -1)
    [ -n "$CAP" ] || { VERDICT=conflict; REASON="no $CAPNAME capture before record"; finish; }
    V=$(printf '%s' "$CAP" | jq -r .value)
    EVT=$(printf '%s' "$CAP" | jq -r .timestamp)
    bash "$HERE/coord-log.sh" check --session "$SESSION" --state "$SOURCE" --sealed "$V" --any-visit > /dev/null 2>&1
    case $? in 0) ;; 1) VERDICT=conflict; REASON="the $CAPNAME capture fails its seal"; finish ;; *) lib_die2 "cannot check the seal" ;; esac
    set -- $V
    KIND=${1-} PR=${2-} SHA=${3-}
    case "$KIND" in merged|unconfirmed) ;; *) VERDICT=conflict; REASON="$CAPNAME is $KIND, not merged or unconfirmed"; finish ;; esac
    if ! [[ $PR =~ $RE_NUM ]] || ! [[ $SHA =~ $RE_SHA ]]; then VERDICT=conflict; REASON="$CAPNAME is not <verdict> <pr> <sha>"; finish; fi
    ;;
*)
    VERDICT=conflict; REASON="nothing to confirm after ${SOURCE:-no state}"; finish ;;
esac

OKX=1
case "$SOURCE" in
dispatch)
    TOPIC=$(printf '%s' "$EV" | jq -r '.fields.topic // ""')
    # The dispatch records only the topic dispatch_check passed: its sealed
    # `ok <topic>`. A topic named only in the dispatch evidence is refused.
    DC=$(bash "$HERE/coord-log.sh" capture --session "$SESSION" --name DISPATCH_CHECK --state dispatch_check --any-visit 2> /dev/null) || DC=
    case "$DC" in "ok "*) CHECKED=${DC#ok }; CHECKED=${CHECKED%% *} ;; *) CHECKED= ;; esac
    if [ -z "$CHECKED" ] || [ "$CHECKED" = - ] || [ "$TOPIC" != "$CHECKED" ]; then
        VERDICT=conflict; REASON="the dispatch names topic ${TOPIC:-none}, but dispatch_check passed ${CHECKED:-no topic}"; finish
    fi
    EXPECT="a Holdings row for topic $TOPIC"
    [ -n "$TOPIC" ] && holds "any(.holdings[]; .worker == $(jq -n --arg t "$TOPIC" '$t'))" || OKX=0
    # A send_execution moves the holding from scoping-ahead to executing; one
    # that left it scoping ahead sent nothing, and never confirms.
    entry pick "$ESEQ"; PSEQ=$ENT_SEQ
    if [ -n "$PSEQ" ]; then
        evidence pick "$ESEQ"
        if [ -n "$EVJ" ] && [ "$(printf '%s' "$EVJ" | jq -r '.seq')" -gt "$PSEQ" ] \
            && [ "$(printf '%s' "$EVJ" | jq -r '.fields.choice // ""')" = send_execution ] \
            && [ "$(printf '%s' "$EVJ" | jq -r '.fields.unit // ""')" = "$TOPIC" ]; then
            EXPECT="the Holdings row for topic $TOPIC at Phase executing: send_execution moves it from scoping-ahead, and a row still scoping ahead means no execution was sent"
            holds "any(.holdings[]; .worker == $(jq -n --arg t "$TOPIC" '$t') and .phase == \"executing\")" || OKX=0
        fi
    fi
    # The dispatch path writes the holding before `sent` (dispatch's
    # holding_recorded gate requires it), so the row is fresh for this
    # dispatch when it was written after dispatch_check passed the topic, not
    # after the evidence: that capture is the point the Written: time is
    # compared against.
    CAP=$(bash "$HERE/coord-log.sh" captures --session "$SESSION" --name DISPATCH_CHECK --before "$ESEQ" 2> /dev/null)
    [ $? -eq 2 ] && lib_die2 "cannot read the session log"
    CAP=$(printf '%s' "$CAP" | tail -1)
    [ -n "$CAP" ] && EVT=$(printf '%s' "$CAP" | jq -r .timestamp)
    ;;
leg_spent)
    has_value replaced || { VERDICT=conflict; REASON="leg_spent reached record without replaced"; finish; }
    TOPIC=$(printf '%s' "$EV" | jq -r '.fields.topic // ""')
    [[ $TOPIC =~ $RE_TOPIC ]] || { VERDICT=conflict; REASON="leg_spent's evidence names no topic"; finish; }
    # The spent leg is the one the wait read: the latest WAIT_REQ and
    # WAIT_LEG captures, which only the engine writes.
    SREQ=$(bash "$HERE/coord-log.sh" captures --session "$SESSION" --name WAIT_REQ --before "$ESEQ" 2> /dev/null | tail -1 | jq -r '.value // ""')
    SLEG=$(bash "$HERE/coord-log.sh" captures --session "$SESSION" --name WAIT_LEG --before "$ESEQ" 2> /dev/null | tail -1 | jq -r '.value // ""')
    [ -n "$SREQ" ] && [ -n "$SLEG" ] || { VERDICT=conflict; REASON="the log names no spent leg before leg_spent"; finish; }
    SPENT="leg $SREQ:$SLEG"
    EXPECT="the Holdings row for $TOPIC on a new leg in place of the spent $SPENT, and no row on $SPENT"
    holds "any(.holdings[]; .worker == \$t and (.return_path | startswith(\"leg \")) and .return_path != \$s)
        and (any(.holdings[]; .return_path == \$s) | not)" --arg t "$TOPIC" --arg s "$SPENT" || OKX=0
    ;;
surface)
    has_value merge_table || { VERDICT=conflict; REASON="surface reached record without merge_table"; finish; }
    arrival_unit "$EVSEQ"
    # Held by direction: the latest entry into surface came from land_merge,
    # whose last evidence there says held. Read from the log, never a key.
    entry surface "$ESEQ"; SFROM=$ENT_FROM
    HELD=0
    if [ "$SFROM" = land_merge ]; then
        evidence land_merge "$ESEQ"; LM=$EVJ
        [ "$(printf '%s' "$LM" | jq -r '.fields.merge // ""')" = held ] && HELD=1
    fi
    if [ "$HELD" = 1 ]; then
        EXPECT="the row for $UNIT has a Verified head and Phase held"
        [ -n "$UNIT" ] && holds "any(.holdings[]; .worker == $(jq -n --arg t "$UNIT" '$t') and .verified_head != \"\" and .phase == \"held\")" || OKX=0
    else
        EXPECT="the row for $UNIT has a Verified head"
        [ -n "$UNIT" ] && holds "any(.holdings[]; .worker == $(jq -n --arg t "$UNIT" '$t') and .verified_head != \"\")" || OKX=0
    fi
    ;;
teardown)
    UNIT=$(printf '%s' "$EV" | jq -r '.fields.unit // .fields.topic // ""')
    [ -n "$UNIT" ] || arrival_unit "$EVSEQ"
    if has_value done; then
        EXPECT="no Holdings row for $UNIT"
        [ -n "$UNIT" ] && holds "any(.holdings[]; .worker == $(jq -n --arg t "$UNIT" '$t')) | not" || OKX=0
    elif has_value kept; then
        EXPECT="a newer Written: time"
    else
        VERDICT=conflict; REASON="teardown evidence is neither done nor kept"; finish
    fi
    ;;
destroy)
    # The topic the inventory sealed: read through the seal check, so a key
    # the coordinator wrote can't name another worker.
    TSEAL=$(bash "$HERE/coord-log.sh" capture --session "$SESSION" --name TEARDOWN_SEAL 2> /dev/null) \
        || { VERDICT=conflict; REASON="no valid sealed teardown inventory"; finish; }
    INV=$(bash "$HERE/coord-log.sh" check --session "$SESSION" --state teardown_inventory --sealed "$TSEAL" --key teardown_verdict --any-visit 2> /dev/null) \
        || { VERDICT=conflict; REASON="the teardown inventory fails its seal"; finish; }
    UNIT=$(printf '%s\n' "$INV" | sed -n 's/^topic //p' | head -1)
    [ -n "$UNIT" ] || { VERDICT=conflict; REASON="the sealed inventory names no topic"; finish; }
    TJ=$(jq -n --arg t "$UNIT" '$t')
    if has_value destroyed; then
        EXPECT="no Holdings row for $UNIT"
        holds "any(.holdings[]; .worker == $TJ) | not" || OKX=0
    elif has_value handed_over; then
        EXPECT="no Holdings row for $UNIT and a Side effects row whose Target names it"
        holds '(any(.holdings[]; .worker == $t) | not) and any(.side_effects[]; .target | test("(^|[^A-Za-z0-9._-])" + ($t | gsub("\\."; "\\.")) + "($|[^A-Za-z0-9._-])"))' --arg t "$UNIT" || OKX=0
    else
        VERDICT=conflict; REASON="destroy evidence is neither destroyed nor handed_over"; finish
    fi
    ;;
decision_apply)
    if has_value reversal; then
        EXPECT="a Reversals row dated at or after $MIN"
        holds "any(.reversals[]; .date[0:16] >= \"$MIN\")" || OKX=0
    elif has_value deferral; then
        EXPECT="a Deferrals row raised at or after $MIN"
        holds "any(.deferrals[]; .raised[0:16] >= \"$MIN\")" || OKX=0
    else
        VERDICT=conflict; REASON="decision_apply evidence is neither reversal nor deferral"; finish
    fi
    ;;
posture_ask)
    EXPECT="a Reversals row from the human about the posture, at or after $MIN"
    holds "any(.reversals[]; .date[0:16] >= \"$MIN\" and .from == \"the human\"
        and ((.reversed + \" \" + .now) | ascii_downcase | contains(\"posture\")))" || OKX=0
    ;;
merge_confirm|merged_facts)
    unit_topic "$ESEQ"
    [ -n "$UNIT" ] || { VERDICT=conflict; REASON="the log names no unit for #$PR"; finish; }
    unit_row "$UNIT"
    if [ "$KIND" = merged ]; then
        # The unit's own row: another unit's #$PR in another repository is
        # not this one.
        # The row stays until teardown (destroy removes it), so a row
        # already gone is not what this step writes.
        EXPECT="the Holdings row for $UNIT kept, with its Pull request cell cleared of #$PR"
        if [ -z "$ROW" ]; then OKX=0
        elif [ -n "$(printf '%s' "$ROW" | jq -r '.pull_request // ""')" ]; then OKX=0
        fi
    elif [ -z "$ROW" ] || [ "$ROW_PR" != "$PR" ]; then
        # Without the unit's row linking it, #$PR's repository can't be told,
        # and a bare #$PR could be another unit's.
        OKX=0
        EXPECT="the Holdings row for $UNIT to link #$PR (its repository), beside a Side effects row for it at $SHA"
    else
        EXPECT="a Side effects row for $ROW_REPO#$PR at $SHA"
        holds "any(.side_effects[]; .verified_head == \$sha and (.target | tostring
            | test(\"(^|[^A-Za-z0-9_./-])\" + \$re + \"#\" + \$pr + \"([^0-9]|\$)\"; \"i\")
              or test(\"github\\\\.com/\" + \$re + \"/(pull|issues)/\" + \$pr + \"([^0-9]|\$)\"; \"i\")))" \
            --arg sha "$SHA" --arg pr "$PR" --arg re "$(printf '%s' "$ROW_REPO" | sed 's/\./\\./g')" || OKX=0
    fi
    ;;
esac

if [ "$OKX" = 1 ] && later "$WRITTEN" "$EVT"; then
    VERDICT=confirmed; REASON="$EXPECT, written $WRITTEN"
else
    VERDICT=waiting
    if [ "$OKX" = 1 ]; then REASON="Written: $WRITTEN is not after $EVT"; else REASON="not yet: $EXPECT"; fi
fi
finish
