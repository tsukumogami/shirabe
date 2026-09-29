#!/usr/bin/env bash
# deferral-check.sh -- the check action of state dispatch_check: may this
# dispatch go ahead? Also a row mode other scripts call to judge one Deferrals
# row.
#
# Check mode, first that applies:
#   record-changed        the record the run found (coord-log.sh run-facts) is
#                         gone, closed, or no longer a canonical record of
#                         this scope, or the run has no found record
#   deferral-open <count> <count> deferrals are open: a row raised before the
#                         run start (coord-log.sh run-start) that isn't
#                         disposed (row mode below, with the chain start from
#                         coord-log.sh chain-start, so a carry made by a run
#                         this one restarted still counts), a `filed #<n>` naming no
#                         issue in the host repository, and, at discipline
#                         scope until a DISPATCH_CHECK capture in this run read
#                         `ok`, a deferral of the handoff file
#                         docs/disciplines/<name>.md on the host's default
#                         branch (absent: none) that the record doesn't carry,
#                         by its Deferral text, with a disposition
#   decision-owed <rule>  decision-next.sh --owed dispatch names a rule that
#                         blocks this dispatch (the DESIGN's blocking table):
#                         before the run's first dispatch any owed rule, after
#                         it an unrecorded write or an owed message
#   duplicate-topic <topic>
#                         the pick dispatches (dispatch or scope_ahead) a
#                         topic a Holdings row already names as its Worker:
#                         worker session names are machine-wide, so a second
#                         live worker on the topic would collide with the
#                         first (koto refuses the attach as origin_mismatch
#                         and nothing is recorded on a leg already bound)
#   at-cap <active>/<cap> <parked>/<bound>
#                         the pick being checked (the latest `pick` evidence)
#                         would pass the cap or the parked bound: dispatch and
#                         scope_ahead add an active worker, so they need
#                         active < CAP and parked < PARKED_BOUND;
#                         send_execution to a scoping-ahead holding, and a
#                         redispatch of a unit still held, move a worker
#                         already counted, so they are at the cap only when
#                         active > CAP
#   ok <topic>            clear; <topic> is the unit this visit checks, by the
#                         path into it (the pick after the latest entry into
#                         pick, or on a redispatch the unit that failed; `-`
#                         when there is none). record-confirm.sh holds the
#                         dispatch that follows to this topic
# A row is parked when it has a Verified head and its pull request is open and
# not a draft; every other Holdings row is active. CAP and PARKED_BOUND are the
# session's variables. The detail goes to context key coord/dispatch_check.json.
#
# Row mode judges one Deferrals row (a JSON object with deferral, reason,
# raised, disposition) against a run start, and prints one of:
#   disposed filed <n> | disposed closed | disposed carried <time>
#   undisposed empty | undisposed malformed | undisposed carried-before-chain-start
#   undisposed decide-by-passed   (a carry whose `until` time has passed)
#   undisposed raised-this-run    (undisposed, but raised at or after the run
#                                 start, so not a predecessor's; exit 0)
# A carry is `carried <time>: <reason>` or, with a decide-by,
# `carried <time> until <time>: <reason>`. Its time counts when it is at or
# after the chain start (--chain-start, default the run start): the start of
# the earliest run in the unbroken chain of restarts that led to this one, so
# a restart doesn't re-decide what the run it replaced carried, while a
# successor still does. A carry whose until time is before now is open again,
# chain or not: the until time is compared with the clock now, and a carry is
# still disposed through the until minute itself. An until at or before the
# carry time is allowed; it only makes a carry that is already open. Times
# compare to the minute (the Disposition's resolution).
# Row mode reads nothing from GitHub, so it can't tell whether a filed issue
# exists; check mode does.
#
# Usage:
#   deferral-check.sh --session S
#   deferral-check.sh --session S --scope roadmap|discipline --name N --repo O/R
#                     --ref N [--no-seal]                            (tests)
#   deferral-check.sh --row-file F --run-start YYYY-MM-DDTHH:MM[:SS[.fff]]Z
#                     [--chain-start YYYY-MM-DDTHH:MM[:SS[.fff]]Z]
#
# Exit codes, check mode: 0 a verdict was printed; 2 a read failed; 64 usage.
# Row mode: 0 disposed or raised-this-run; 1 undisposed; 64 usage.
#
# GitHub reads: gh issue view <n> --repo R --json state,body |
# gh pr view <n> --repo R --json state,body,headRefName,isCrossRepository;
# gh api --method GET repos/R/issues/<n>; gh api --method GET repos/R --jq
# .default_branch; gh api --method GET "repos/R/contents/<path>?ref=<default>";
# gh pr view <n> --repo <repo> --json state,isDraft for each verified holding.
set -uo pipefail

PROG=deferral-check
HERE=$(cd "$(dirname "$0")" && pwd)
SESSION= SCOPE= NAME= REPO= REF= ROWFILE= RUNSTART= CHAINSTART=
NO_SEAL=0

usage() { sed -n '/^# Usage:/,/^# Exit codes,/p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 64; }
while [ $# -gt 0 ]; do
    case "$1" in
        --session) [ $# -ge 2 ] || usage; SESSION=$2; shift 2 ;;
        --scope) [ $# -ge 2 ] || usage; SCOPE=$2; shift 2 ;;
        --name) [ $# -ge 2 ] || usage; NAME=$2; shift 2 ;;
        --repo) [ $# -ge 2 ] || usage; REPO=$2; shift 2 ;;
        --ref) [ $# -ge 2 ] || usage; REF=$2; shift 2 ;;
        --row-file) [ $# -ge 2 ] || usage; ROWFILE=$2; shift 2 ;;
        --run-start) [ $# -ge 2 ] || usage; RUNSTART=$2; shift 2 ;;
        --chain-start) [ $# -ge 2 ] || usage; CHAINSTART=$2; shift 2 ;;
        --no-seal) NO_SEAL=1; shift ;;
        *) usage ;;
    esac
done
. "$HERE/record-common.sh"

# minute <time>: YYYY-MM-DDTHH:MM of a valid time, else empty.
minute() { lib_epoch "$1" > /dev/null 2>&1 && printf '%s' "${1:0:16}"; }

# judge_row <row-json> <chain-start-minute>: sets ROW_VERDICT; returns 0 when
# disposed, 1 when not. The raised-this-run exemption is the caller's.
judge_row() {
    local d re_filed='^filed #([1-9][0-9]*)$' t u why
    local re_carried='^carried ([0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}Z)( until ([0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}Z))?: (.+)$'
    d=$(printf '%s' "$1" | jq -r '.disposition // "" | tostring')
    ROW_FILED=
    if [ -z "$d" ]; then ROW_VERDICT="undisposed empty"; return 1; fi
    if [[ $d =~ $re_filed ]]; then ROW_FILED=${BASH_REMATCH[1]}; ROW_VERDICT="disposed filed $ROW_FILED"; return 0; fi
    case "$d" in "closed: "?*) ROW_VERDICT="disposed closed"; return 0 ;; esac
    if [[ $d =~ $re_carried ]]; then
        t=${BASH_REMATCH[1]} u=${BASH_REMATCH[3]} why=${BASH_REMATCH[4]}
        [ -n "$(minute "$t")" ] || { ROW_VERDICT="undisposed malformed"; return 1; }
        [ -z "$u" ] || [ -n "$(minute "$u")" ] || { ROW_VERDICT="undisposed malformed"; return 1; }
        case "$why" in *[![:space:]]*) ;; *) ROW_VERDICT="undisposed malformed"; return 1 ;; esac
        if [ "$(minute "$t")" \< "$2" ]; then ROW_VERDICT="undisposed carried-before-chain-start"; return 1; fi
        if [ -n "$u" ] && [ "$(minute "$u")" \< "$(date -u +%Y-%m-%dT%H:%M)" ]; then ROW_VERDICT="undisposed decide-by-passed"; return 1; fi
        ROW_VERDICT="disposed carried $t"; return 0
    fi
    ROW_VERDICT="undisposed malformed"
    return 1
}

# raised_this_run <row-json> <run-start-minute>: the row's Raised is a valid
# time at or after the run start.
raised_this_run() {
    local r
    r=$(printf '%s' "$1" | jq -r '.raised // "" | tostring')
    r=$(minute "$r")
    [ -n "$r" ] && [ ! "$r" \< "$2" ]
}

# ---- row mode ----------------------------------------------------------------
if [ -n "$ROWFILE$RUNSTART$CHAINSTART" ]; then
    [ -n "$ROWFILE" ] && [ -n "$RUNSTART" ] && [ -z "$SESSION$SCOPE$NAME$REPO$REF" ] && [ "$NO_SEAL" = 0 ] || usage
    [ -r "$ROWFILE" ] || usage
    RS=$(minute "$RUNSTART"); [ -n "$RS" ] || usage
    CS=$RS
    if [ -n "$CHAINSTART" ]; then CS=$(minute "$CHAINSTART"); [ -n "$CS" ] || usage; fi
    ROW=$(jq -c 'select(type == "object")' "$ROWFILE")
    [ -n "$ROW" ] || { echo "undisposed malformed"; exit 1; }
    if judge_row "$ROW" "$CS"; then echo "$ROW_VERDICT"; exit 0; fi
    if raised_this_run "$ROW" "$RS"; then echo "undisposed raised-this-run"; exit 0; fi
    echo "$ROW_VERDICT"
    exit 1
fi

# ---- check mode --------------------------------------------------------------
[ -n "$SESSION" ] || usage
lib_facts
lib_bounds
lib_log_readable || lib_die2 "no readable log for $SESSION"

T=$(mktemp -d "${TMPDIR:-/tmp}/deferral-check.XXXXXX")
trap 'rm -rf "$T"' EXIT

REASON= OPEN='[]' ACTIVE=0 PARKED=0 CHOICE= TOPIC=- COMPARED=false
finish() {
    jq -n --arg v "${1%% *}" --arg ref "$REF" --arg reason "$REASON" --argjson open "$OPEN" \
        --argjson a "$ACTIVE" --argjson p "$PARKED" --argjson cap "$CAP" --argjson pb "$PARKED_BOUND" \
        --arg choice "$CHOICE" --arg topic "$TOPIC" --argjson cmp "$COMPARED" \
        '{verdict: $v, ref: $ref, reason: $reason, open_deferrals: $open, active: $a, parked: $p, cap: $cap,
          parked_bound: $pb, choice: $choice, topic: $topic, handoff_compared: $cmp}' > "$T/detail.json"
    lib_emit dispatch_check "$1" coord/dispatch_check.json "$T/detail.json"
}

# The unit being checked, by the path into this visit, never the latest pick
# anywhere in the log. From pick (or deferral_dispose, which pick led to): the
# pick evidence submitted after the latest entry into pick. From failure (a
# redispatch): the unit that failed, which is the topic this state sealed on its
# previous visit when the failure came from dispatch, else the latest `wait`
# evidence's unit. record-confirm.sh then holds the dispatch to this topic.
CL="$HERE/coord-log.sh"
# rd <var> <args...>: a coord-log.sh read into <var>, in this shell (not a
# command substitution, so a failure exits the script). Exit 1 means "none"
# and leaves <var> empty; any other failure is a read failure (exit 2), never
# "no path".
rd() {
    local var=$1 out rc; shift
    out=$(bash "$CL" "$@"); rc=$?
    case $rc in 0) ;; 1) out= ;; *) lib_die2 "cannot read the session log ($1)" ;; esac
    printf -v "$var" '%s' "$out"
}
UNIT_FROM_LOG=0
rd ENT entry --session "$SESSION" --state dispatch_check
FROMST=${ENT#* }
U=
case "$FROMST" in
    pick|deferral_dispose)
        rd PE entry --session "$SESSION" --state pick
        if [ -n "$PE" ]; then
            rd PICK evidence --session "$SESSION" --state pick --after "${PE%% *}"
            if [ -n "$PICK" ]; then
                CHOICE=$(printf '%s' "$PICK" | jq -r '.fields.choice // "" | tostring')
                U=$(printf '%s' "$PICK" | jq -r '.fields.unit // "" | tostring')
            fi
        fi ;;
    failure)
        CHOICE=redispatch
        rd FE entry --session "$SESSION" --state failure
        if [ "${FE#* }" = dispatch ]; then
            PREV=$(bash "$CL" capture --session "$SESSION" --name DISPATCH_CHECK --state dispatch_check --any-visit 2> /dev/null) || PREV=
            case "$PREV" in "ok "*) U=${PREV#ok }; U=${U%% *} ;; esac
        else
            # The unit the failure is about, resolved like report-facts.sh's
            # (lib_unit): a leg arrival names no unit in its evidence, so it
            # needs the record's rows, read below.
            UNIT_FROM_LOG=1
        fi ;;
esac
[[ $U =~ $RE_TOPIC ]] && TOPIC=$U
case "$CHOICE" in ''|dispatch|scope_ahead|send_execution|redispatch) ;; *) CHOICE=other ;; esac

# The record, by the run's ref.
lib_run_ref || { REASON="the run has no found record"; finish record-changed; }
changed_or_die() { # changed_or_die <err-file> <what>
    if grep -qE 'Could not resolve|Not Found|HTTP 404|no pull requests found' "$1"; then
        REASON="$2 is gone"; finish record-changed
    fi
    lib_die2 "cannot read $2: $(lib_scrub < "$1")"
}
if [ "$SCOPE" = roadmap ]; then
    gh issue view "$REF" --repo "$REPO" --json state,body > "$T/rec.json" 2> "$T/rec.err" < /dev/null || changed_or_die "$T/rec.err" "issue #$REF"
    [ "$(jq -r .state "$T/rec.json")" = OPEN ] || { REASON="issue #$REF is closed"; finish record-changed; }
else
    gh pr view "$REF" --repo "$REPO" --json state,body,headRefName,isCrossRepository > "$T/rec.json" 2> "$T/rec.err" < /dev/null \
        || changed_or_die "$T/rec.err" "pull request #$REF"
    [ "$(jq -r .state "$T/rec.json")" = OPEN ] || { REASON="pull request #$REF is not open"; finish record-changed; }
    [ "$(jq -r .headRefName "$T/rec.json")" = "$BRANCH" ] && [ "$(jq -r .isCrossRepository "$T/rec.json")" = false ] \
        || { REASON="pull request #$REF is not from $BRANCH"; finish record-changed; }
fi
jq -r '.body // ""' "$T/rec.json" > "$T/body.md"
lib_parse "$T/body.md" "$T/parsed.json"
case $? in
    0) ;;
    3|65) REASON="#$REF is no longer a canonical $SCOPE record for $NAME: $(lib_scrub < "$T/parsed.json.err" | head -1)"; finish record-changed ;;
    *) lib_die2 "record-parse.sh failed" ;;
esac

# Deferrals raised before the run start.
START=$(bash "$HERE/coord-log.sh" run-start --session "$SESSION" 2>/dev/null) || lib_die2 "cannot read the run start"
RS=$(minute "$START"); [ -n "$RS" ] || lib_die2 "the run start $START is not a time"
CHAIN=$(bash "$HERE/coord-log.sh" chain-start --session "$SESSION" 2>/dev/null) || lib_die2 "cannot read the chain start"
CS=$(minute "$CHAIN"); [ -n "$CS" ] || lib_die2 "the chain start $CHAIN is not a time"
: > "$T/open.jsonl"
open_row() { # open_row <deferral-text> <why>
    jq -nc --arg d "$1" --arg w "$2" '{deferral: ($d | .[0:200]), why: $w}' >> "$T/open.jsonl"
}
N=$(jq '.deferrals | length' "$T/parsed.json")
i=0
while [ "$i" -lt "$N" ]; do
    ROW=$(jq -c --argjson i "$i" '.deferrals[$i]' "$T/parsed.json")
    TEXT=$(printf '%s' "$ROW" | jq -r .deferral)
    i=$((i + 1))
    if judge_row "$ROW" "$CS"; then
        if [ -n "$ROW_FILED" ]; then
            if gh api --method GET "repos/$REPO/issues/$ROW_FILED" > "$T/filed.json" 2> "$T/filed.err" < /dev/null; then
                jq -e 'has("pull_request") | not' "$T/filed.json" > /dev/null || open_row "$TEXT" "filed #$ROW_FILED is a pull request, not an issue"
            else
                grep -q 'HTTP 404' "$T/filed.err" || lib_die2 "cannot read issue #$ROW_FILED: $(lib_scrub < "$T/filed.err")"
                open_row "$TEXT" "filed #$ROW_FILED names no issue in $REPO"
            fi
        fi
        continue
    fi
    raised_this_run "$ROW" "$RS" && continue
    open_row "$TEXT" "${ROW_VERDICT#undisposed }"
done

# The previous rotation's handoff, until this run's first pass.
if [ "$SCOPE" = discipline ]; then
    PASSED=0
    bash "$CL" captures --session "$SESSION" --name DISPATCH_CHECK > "$T/passes.jsonl" 2> /dev/null
    [ $? -eq 2 ] && lib_die2 "cannot read the session log"
    while IFS= read -r C; do
        V=$(printf '%s' "$C" | jq -r '.value | strings | select(startswith("ok "))')
        [ -n "$V" ] || continue
        if bash "$CL" check --session "$SESSION" --state dispatch_check --sealed "$V" --any-visit > /dev/null 2>&1; then
            PASSED=1; break
        fi
    done < "$T/passes.jsonl"
    if [ "$PASSED" = 0 ]; then
        COMPARED=true
        lib_default_branch || lib_die2 "cannot read $REPO's default branch"
        lib_file_at "docs/disciplines/$NAME.md" "$DEFAULT_BRANCH" "$T/handoff.md"
        case $? in
            0)
                if bash "$HERE/record-parse.sh" --format handoff --no-canonical "$T/handoff.md" > "$T/handoff.json" 2> /dev/null; then
                    M=$(jq '.deferrals | length' "$T/handoff.json")
                    j=0
                    while [ "$j" -lt "$M" ]; do
                        TEXT=$(jq -r --argjson j "$j" '.deferrals[$j].deferral' "$T/handoff.json")
                        j=$((j + 1))
                        MINE=$(jq -c --arg d "$TEXT" '[.deferrals[] | select(.deferral == $d)][0] // empty' "$T/parsed.json")
                        if [ -z "$MINE" ]; then open_row "$TEXT" "in the previous rotation's handoff, missing from the record"; continue; fi
                        # The record's copy needs a disposition however recently it was raised.
                        judge_row "$MINE" "$CS" || open_row "$TEXT" "the previous rotation's deferral is ${ROW_VERDICT#undisposed }"
                    done
                else
                    open_row "docs/disciplines/$NAME.md" "the handoff file on $DEFAULT_BRANCH does not parse"
                fi ;;
            1) ;;
            *) lib_die2 "cannot read the handoff file: $(lib_scrub < "$T/handoff.md.err")" ;;
        esac
    fi
fi
OPEN=$(jq -s -c 'unique_by(.deferral + "\u0000" + .why)' "$T/open.jsonl")
COUNT=$(printf '%s' "$OPEN" | jq 'map(.deferral) | unique | length')
if [ "$COUNT" -gt 0 ]; then
    REASON="$COUNT deferral(s) open"; finish "deferral-open $COUNT"
fi

# Owed decision work, by the one owed predicate: before the run's first
# dispatch every owed rule blocks it, after it only an unrecorded write and an
# owed message do. A held entry, and an escalation that owes nothing, never do.
OWED_RULE=$(bash "$HERE/decision-next.sh" --session "$SESSION" --owed dispatch) || lib_die2 "cannot read what the decisions are owed"
if [ "$OWED_RULE" != none ]; then
    REASON="decision work is owed first: $OWED_RULE"; finish "decision-owed $OWED_RULE"
fi

jq '.holdings' "$T/parsed.json" > "$T/holdings.json"
if [ "$UNIT_FROM_LOG" = 1 ]; then
    parsed_holdings() { cat "$T/holdings.json"; }
    lib_unit "" "" parsed_holdings; rc=$?
    case $rc in 0) TOPIC=$UNIT ;; *) TOPIC=- ;; esac
fi
# A topic already held. send_execution is judged below, as it targets a holding.
if { [ "$CHOICE" = dispatch ] || [ "$CHOICE" = scope_ahead ]; } && [ "$TOPIC" != - ] \
    && jq -e --arg t "$TOPIC" 'any(.[]; .worker == $t)' "$T/holdings.json" > /dev/null; then
    REASON="a Holdings row already names $TOPIC as its worker"
    finish "duplicate-topic $TOPIC"
fi

# The cap and the parked bound.
lib_parked "$T/holdings.json" "$T/counted.json" || lib_die2 "a holding's pull request read failed"
PARKED=$(jq '[.[] | select(.parked)] | length' "$T/counted.json")
ACTIVE=$(jq '[.[] | select(.parked | not)] | length' "$T/counted.json")
ATCAP=0
# send_execution moves a worker already counted only when the unit really is
# a scoping-ahead holding; otherwise it would start a worker, and is judged as
# a dispatch. The choice is the coordinator's word; the holding is GitHub's.
SCOPING=$(jq -r --arg t "$TOPIC" '[.[] | select(.worker == $t and .phase == "scoping-ahead")] | length' "$T/holdings.json")
HELD=$(jq -r --arg t "$TOPIC" '[.[] | select(.worker == $t)] | length' "$T/holdings.json")
if { [ "$CHOICE" = send_execution ] && [ -n "$TOPIC" ] && [ "$SCOPING" -gt 0 ]; } \
    || { [ "$CHOICE" = redispatch ] && [ "$HELD" -gt 0 ]; }; then
    [ "$ACTIVE" -gt "$CAP" ] && ATCAP=1
else
    { [ "$ACTIVE" -ge "$CAP" ] || [ "$PARKED" -ge "$PARKED_BOUND" ]; } && ATCAP=1
fi
if [ "$ATCAP" = 1 ]; then
    REASON="active $ACTIVE of $CAP, parked $PARKED of $PARKED_BOUND"
    finish "at-cap $ACTIVE/$CAP $PARKED/$PARKED_BOUND"
fi
REASON="clear to dispatch"
finish "ok $TOPIC"
