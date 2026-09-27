#!/usr/bin/env bash
# record-confirm.sh -- the check action of states record and verified_confirm:
# is the change the run's last step implies on GitHub yet?
#
# Every spoke that changes what the record must hold returns through `record`,
# whose gate holds until this script sees the change in the live body. What it
# expects comes from the session log, never from an argument: the source state
# is the `from` of the latest entry into `record`, and its last evidence (or,
# for a check state, its own sealed capture) says what should have changed.
# Every case also needs the record's Written: time to be later than that
# event's time, so an older body that happens to match doesn't count.
#
#   dispatch        a Holdings row whose Worker is the evidence's topic, which
#                   must be the topic dispatch_check sealed (`ok <topic>`);
#                   another topic is a conflict
#   surface         (merge_table) the unit's row has a Verified head; the unit
#                   is the latest `wait` evidence's `unit` before the source.
#                   When surface was entered from land_merge on `merge: held`
#                   (the human directed a hold the workspace doesn't require),
#                   the row's Phase must also be `held`
#   merge_confirm,  from MERGE_CONFIRM / MERGED_FACTS: `merged <pr> <sha>` means
#   merged_facts    the unit's Holdings row no longer links #<pr>;
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
#   decision_apply  `reversal`: a Reversals row dated at or after the event;
#                   `deferral`: a Deferrals row raised at or after it
#   posture_ask     a Reversals row at or after the event, From `the human`,
#                   whose Reversed or Now mentions posture
#
# With --verified (state verified_confirm): the VERIFIED capture
# (`verified <pr> <sha>`, sealed at a real visit of verify_board) must equal
# the Verified head of the unit's Holdings row, which must link #<pr>; when
# the pull request's live head, read from the repository that row links, is
# no longer <sha> the verdict is `moved`.
#
# The unit is always found by its Worker (dispatch topic) from the log: the
# latest `wait` evidence's `unit`, else the latest `dispatch` evidence's
# `topic`. A pull request is never found by its bare number, since two units
# in different repositories can both hold #12: its row is the unit's row, and
# its repository is the one in that row's full Pull request URL.
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
set -uo pipefail

PROG=record-confirm
HERE=$(cd "$(dirname "$0")" && pwd)
SESSION= SCOPE= NAME= REPO= REF=
VERIFIED=0 NO_SEAL=0 SKIP_CHECKS=0

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
lib_log || lib_die2 "cannot read the session log"
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

evidence() { # evidence <state> <before-seq>: the last evidence event there
    jq -c --arg s "$1" --argjson q "$2" 'select(.type == "evidence_submitted" and .payload.state == $s and .seq < $q)
        | {seq, timestamp, fields: (.payload.fields // {})}' "$LOG" | tail -1
}
has_value() { # has_value <word>: some evidence field's value is exactly <word>
    printf '%s' "$EV" | jq -e --arg w "$1" '[.fields[] | strings] | index($w) != null' > /dev/null
}
wait_unit() { # the latest `wait` evidence's unit before <seq>
    jq -r --argjson q "$1" 'select(.type == "evidence_submitted" and .payload.state == "wait" and .seq < $q)
        | .payload.fields.unit // empty' "$LOG" | tail -1
}
holds() { # holds <jq test over the record> [jq args...]: the expectation
    local f=$1; shift
    jq -e "$@" "$f" "$T/rec.json" > /dev/null
}
# unit_topic <before-seq>: the unit the step is about, by its Worker: the
# latest `wait` evidence's unit, else the latest `dispatch` evidence's topic.
unit_topic() {
    local u
    u=$(wait_unit "$1")
    [ -n "$u" ] || u=$(jq -r --argjson q "$1" 'select(.type == "evidence_submitted" and .payload.state == "dispatch" and .seq < $q)
        | .payload.fields.topic // empty' "$LOG" | tail -1)
    printf '%s' "$u"
}
# unit_row <topic>: sets ROW (the Holdings row whose Worker is the topic, or
# empty) and, when its Pull request cell is a full link, ROW_REPO and ROW_PR.
unit_row() {
    ROW=$(jq -c --arg t "$1" '[.holdings[] | select(.worker == $t)][0] // empty' "$T/rec.json")
    ROW_REPO= ROW_PR=
    [ -n "$ROW" ] || return 0
    local parts
    parts=$(printf '%s' "$ROW" | jq -r '.pull_request // ""
        | capture("^\\[#(?<a>[0-9]+)\\]\\(https://github\\.com/(?<r>[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+)/pull/(?<b>[0-9]+)\\)$")?
        | select(.a == .b) | "\(.a) \(.r)"' 2> /dev/null)
    set -f; set -- $parts; set +f
    [ $# -eq 2 ] || return 0
    ROW_PR=$1 ROW_REPO=$2
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
    VSEQ=$(jq -r 'select((.type == "transitioned" or .type == "directed_transition" or .type == "rewound") and .payload.to == "verified_confirm") | .seq' "$LOG" | tail -1)
    [ -n "$VSEQ" ] || { VERDICT=conflict; REASON="the log has no entry into verified_confirm"; finish; }
    UNIT=$(unit_topic "$VSEQ")
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
ENTRY=$(jq -c 'select((.type == "transitioned" or .type == "directed_transition" or .type == "rewound") and .payload.to == "record")
    | {seq, from: (.payload.from // "")}' "$LOG" | tail -1)
[ -n "$ENTRY" ] || { VERDICT=conflict; REASON="the log has no entry into record"; finish; }
ESEQ=$(printf '%s' "$ENTRY" | jq -r .seq)
SOURCE=$(printf '%s' "$ENTRY" | jq -r .from)


case "$SOURCE" in
dispatch|surface|teardown|destroy|decision_apply|posture_ask)
    EV=$(evidence "$SOURCE" "$ESEQ")
    [ -n "$EV" ] || { VERDICT=conflict; REASON="no evidence from $SOURCE before record"; finish; }
    EVT=$(printf '%s' "$EV" | jq -r .timestamp)
    EVSEQ=$(printf '%s' "$EV" | jq -r .seq)
    MIN=${EVT:0:16}
    ;;
merge_confirm|merged_facts)
    CAPNAME=MERGE_CONFIRM
    [ "$SOURCE" = merged_facts ] && CAPNAME=MERGED_FACTS
    CAP=$(jq -c --arg k "$CAPNAME" --argjson q "$ESEQ" 'select(.type == "variable_captured" and .payload.key == $k and .seq < $q)
        | {timestamp, value: .payload.value}' "$LOG" | tail -1)
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
    ;;
surface)
    has_value merge_table || { VERDICT=conflict; REASON="surface reached record without merge_table"; finish; }
    UNIT=$(wait_unit "$EVSEQ")
    # Held by direction: the latest entry into surface came from land_merge,
    # whose last evidence there says held. Read from the log, never a key.
    SFROM=$(jq -r --argjson q "$ESEQ" 'select((.type == "transitioned" or .type == "directed_transition" or .type == "rewound")
        and .payload.to == "surface" and .seq < $q) | .payload.from // ""' "$LOG" | tail -1)
    HELD=0
    if [ "$SFROM" = land_merge ]; then
        LM=$(evidence land_merge "$ESEQ")
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
    [ -n "$UNIT" ] || UNIT=$(wait_unit "$EVSEQ")
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
    UNIT=$(unit_topic "$ESEQ")
    [ -n "$UNIT" ] || { VERDICT=conflict; REASON="the log names no unit for #$PR"; finish; }
    unit_row "$UNIT"
    if [ "$KIND" = merged ]; then
        # The unit's own row: another unit's #$PR in another repository is
        # not this one.
        EXPECT="the Holdings row for $UNIT no longer links #$PR"
        [ -n "$ROW" ] && [ "$ROW_PR" = "$PR" ] && OKX=0
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
