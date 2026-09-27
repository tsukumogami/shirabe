#!/usr/bin/env bash
# quiet-check.sh -- the check action of state quiet_check: which workers have
# gone quiet, and is this their first or second silent check? Read-only: it
# never messages, redispatches or tears anything down.
#
# For every Holdings row (record-holding.sh --list) the last activity is the
# latest of: its pull request's head commit date (gh pr view --json
# headRefOid, then the commit), the latest `wait` evidence with event
# `report` naming it as unit, the latest `dispatch` evidence naming it as
# topic, and the run start (a restart resets the counts, erring toward one
# more status message).
#
# A topic's earlier silent checks are the QUIET captures in this run (each
# seal checked against a real entry into quiet_check) that named it silent
# after its last activity. The topic is silent in this sweep when 30 minutes
# have passed since the later of its last activity and its latest earlier
# silent check, so a worker is checked at most once per 30 minutes and a
# status message gets 30 minutes to be answered.
#
# Verdict tokens:
#   quiet-none                 no topic is silent
#   first-silence <t1> <t2>... silent topics, none checked silent before
#   second-silence <t1>...     the silent topics with an earlier silent check
#                              since their last activity (wins over first)
# Topics are space-separated: koto captures only letters, digits, spaces and
# `: / _ . - @`, and a dispatch topic never holds a space.
# The detail goes to context key coord/quiet.json as data: per holding its
# last activity, whether it is silent, and its earlier silent checks.
#
# Usage:
#   quiet-check.sh --session S [--now YYYY-MM-DDTHH:MM:SSZ]
#   quiet-check.sh --session S --scope roadmap|discipline --name N --repo O/R
#                  --ref N [--now T] [--no-seal]                     (tests)
#
# Exit codes: 0 a verdict was printed; 2 a read failed; 64 usage.
#
# GitHub reads: record-holding.sh --list (gh issue|pr view);
# gh pr view <n> --repo <repo> --json headRefOid;
# gh api --method GET repos/<repo>/commits/<sha> --jq .commit.committer.date
set -uo pipefail

PROG=quiet-check
HERE=$(cd "$(dirname "$0")" && pwd)
SESSION= SCOPE= NAME= REPO= REF= NOW=
NO_SEAL=0 SKIP_CHECKS=0
QUIET_SECONDS=1800

usage() { sed -n '/^# Usage:/,/^# Exit codes:/p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 64; }
while [ $# -gt 0 ]; do
    case "$1" in
        --session) [ $# -ge 2 ] || usage; SESSION=$2; shift 2 ;;
        --scope) [ $# -ge 2 ] || usage; SCOPE=$2; shift 2 ;;
        --name) [ $# -ge 2 ] || usage; NAME=$2; shift 2 ;;
        --repo) [ $# -ge 2 ] || usage; REPO=$2; shift 2 ;;
        --ref) [ $# -ge 2 ] || usage; REF=$2; shift 2 ;;
        --now) [ $# -ge 2 ] || usage; NOW=$2; shift 2 ;;
        --no-seal) NO_SEAL=1; shift ;;
        *) usage ;;
    esac
done
[ -n "$SESSION" ] || usage
. "$HERE/record-common.sh"
lib_facts
[ -n "$NOW" ] || NOW=$(lib_now)
NOW_S=$(lib_epoch "$NOW") || usage
lib_log || lib_die2 "no readable log for $SESSION"

T=$(mktemp -d "${TMPDIR:-/tmp}/quiet-check.XXXXXX")
trap 'rm -rf "$T"' EXIT

if [ "$OVERRIDE" = 1 ]; then
    [[ $REF =~ $RE_NUM ]] || { echo "$PROG: --ref goes with the override flags" >&2; exit 64; }
    bash "$HERE/record-holding.sh" --scope "$SCOPE" --name "$NAME" --repo "$REPO" --ref "$REF" --list > "$T/holdings.json" 2> "$T/h.err"
else
    [ -z "$REF" ] || usage
    bash "$HERE/record-holding.sh" --session "$SESSION" --list > "$T/holdings.json" 2> "$T/h.err"
fi
[ $? -eq 0 ] || lib_die2 "record-holding.sh --list failed: $(lib_scrub < "$T/h.err")"

START=$(bash "$HERE/coord-log.sh" run-start --session "$SESSION" 2>/dev/null) || lib_die2 "cannot read the run start"
START_S=$(lib_epoch "$START") || lib_die2 "the run start $START is not a time"

# Earlier sweeps: "<epoch>\t<word>\t<topics>" per QUIET capture whose seal checks.
: > "$T/sweeps.tsv"
for E in $(jq -r 'select(.type == "variable_captured" and .payload.key == "QUIET") | [.timestamp, .payload.value] | @base64' "$LOG"); do
    E=$(printf '%s' "$E" | base64 -d 2>/dev/null || printf '%s' "$E" | base64 -D 2>/dev/null)
    TS=$(printf '%s' "$E" | jq -r '.[0]')
    V=$(printf '%s' "$E" | jq -r '.[1]')
    bash "$HERE/coord-log.sh" check --session "$SESSION" --state quiet_check --sealed "$V" --any-visit > /dev/null 2>&1 || continue
    S=$(lib_epoch "$TS") || continue
    B=${V% sealed:*}
    W=${B%% *}
    case "$W" in first-silence|second-silence) printf '%s\t%s\t%s\n' "$S" "$W" "${B#* }" >> "$T/sweeps.tsv" ;; esac
done

# latest_evidence <state> <field> <value>: epoch of the latest such evidence, or empty.
latest_evidence() {
    local ts
    ts=$(jq -r --arg s "$1" --arg f "$2" --arg v "$3" 'select(.type == "evidence_submitted" and .payload.state == $s
        and ((.payload.fields[$f] // "") | tostring) == $v
        and ($s != "wait" or (.payload.fields.event // "") == "report")) | .timestamp' "$LOG" | tail -1)
    [ -n "$ts" ] && lib_epoch "$ts"
}

FIRST= SECOND=
: > "$T/detail.jsonl"
N=$(jq length "$T/holdings.json")
i=0
while [ "$i" -lt "$N" ]; do
    ROW=$(jq -c --argjson i "$i" '.[$i]' "$T/holdings.json")
    i=$((i + 1))
    W=$(printf '%s' "$ROW" | jq -r .worker)
    [[ $W =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || continue
    LAST=$START_S
    for S in "$(latest_evidence wait unit "$W")" "$(latest_evidence dispatch topic "$W")"; do
        [ -n "$S" ] && [ "$S" -gt "$LAST" ] && LAST=$S
    done
    if lib_pr_link "$(printf '%s' "$ROW" | jq -r '.pull_request // ""')"; then
        H=$(gh pr view "$LINK_NUM" --repo "$LINK_REPO" --json headRefOid --jq .headRefOid 2> "$T/pr.err" < /dev/null) \
            || lib_die2 "cannot read $LINK_REPO#$LINK_NUM: $(lib_scrub < "$T/pr.err")"
        [[ $H =~ $RE_SHA ]] || lib_die2 "$LINK_REPO#$LINK_NUM has no usable head"
        D=$(gh api --method GET "repos/$LINK_REPO/commits/$H" --jq .commit.committer.date 2> "$T/c.err" < /dev/null) \
            || lib_die2 "cannot read commit $H: $(lib_scrub < "$T/c.err")"
        S=$(lib_epoch "$D") || lib_die2 "commit $H has no usable date"
        [ "$S" -gt "$LAST" ] && LAST=$S
    fi
    # Earlier silent checks since the last activity, and the latest of them.
    EARLIER=0 LATEST_CHECK=$LAST
    while IFS='	' read -r S WORD TOPICS; do
        [ -n "$S" ] || continue
        [ "$S" -gt "$LAST" ] || continue
        case " $TOPICS " in *" $W "*) ;; *) continue ;; esac
        EARLIER=$((EARLIER + 1))
        [ "$S" -gt "$LATEST_CHECK" ] && LATEST_CHECK=$S
    done < "$T/sweeps.tsv"
    SILENT=false
    if [ $((NOW_S - LATEST_CHECK)) -ge "$QUIET_SECONDS" ]; then
        SILENT=true
        if [ "$EARLIER" -gt 0 ]; then SECOND="$SECOND $W"; else FIRST="$FIRST $W"; fi
    fi
    jq -nc --arg w "$W" --argjson l "$LAST" --argjson s "$SILENT" --argjson e "$EARLIER" \
        '{worker: $w, last_activity: ($l | todate), silent: $s, earlier_silent_checks: $e}' >> "$T/detail.jsonl"
done
jq -s -c --arg now "$NOW" '{now: $now, holdings: .}' "$T/detail.jsonl" > "$T/quiet.json" || lib_die2 "jq failed"

if [ -n "$SECOND" ]; then lib_emit quiet_check "second-silence${SECOND}" coord/quiet.json "$T/quiet.json"; fi
if [ -n "$FIRST" ]; then lib_emit quiet_check "first-silence${FIRST}" coord/quiet.json "$T/quiet.json"; fi
lib_emit quiet_check quiet-none coord/quiet.json "$T/quiet.json"
