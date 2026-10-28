#!/usr/bin/env bash
# report-facts.sh -- the check action of state report_facts: find the
# reporting worker's holding and check that its pull request may be verified.
#
# The unit is the `unit` of the latest `wait` evidence whose event is
# `report` or `progress`. Its holding is read with state-holding.sh --read (the row whose
# Worker is that topic). When the row links a pull request, it is refused when:
#   out-of-scope-repo  the link's repository is neither the host nor the Repo
#                      of any Holdings row
#   bad-link           the Pull request cell's two numbers differ
#   fork-head          the pull request's head is in another repository
#   branch-mismatch    its head branch differs from a non-empty Branch cell
# With Branch empty there is nothing to compare.
#
# With Pull request empty, the pull request the report itself names is read
# instead (state-common.sh lib_report_pr: the `pr` of the leg's result in
# koto's record of the leg, or the `pull_request` field of the message's
# `wait` evidence). A report naming none gives `holding none`. One naming a
# pull request gives `link`: the holding should carry it, and report_link has
# holding-link.sh write it and its head branch onto the holding before
# report_facts reads again. It is refused as a linked one is
# (out-of-scope-repo, fork-head, branch-mismatch), and also as:
#   bad-report-pr      the report names it in neither the URL nor the o/r#n
#                      form (several named is neither)
#   pr-held            another Holdings row links it, so whose it is is
#                      ambiguous: it is reported, never adopted
#
# A progress report (the hub's `progress` event: a checkpoint message, never
# a result; shirabe#491) is read the same way, and a pull request it names
# that its holding lacks still gives `link`, so report_link writes it onto
# the holding through holding-link.sh, and a refusal is `refused` as for any
# report. Where a report reads `holding`, progress reads `progress <pr|none>
# <topic>`: report_questions still reads its questions, and it then goes
# back to the hub, never to classification, with no phase change.
#
# Verdict tokens: holding <pr|none> <topic> | link <pr> <topic> | progress
# <pr|none> <topic> | unknown <topic> (no row, or `-` when the evidence names
# no dispatch topic) | refused <topic> <why> (one of the codes above).
# The facts go to context key coord/report.json as data (classify_report's
# decider input): {unit, pull_request: {repo, number, url} or null, state,
# draft, head, merge_state, holding}. No worker message text: the dispatch
# path adds worker_report separately.
#
# Usage:
#   report-facts.sh --session S
#   report-facts.sh --session S --scope roadmap|discipline --name N --repo O/R
#                   [--no-seal]                                      (tests)
#
# Exit codes: 0 a verdict was printed; 2 a read failed; 64 usage.
#
# The record through state-holding.sh --read and --list, which share one read
# of it (rs_once_begin), and state-holding.sh --pushed-head writes a changed
# head into the one session key that keeps it, reading and writing no body.
# GitHub reads:
# gh pr view <n> --repo <repo> --json number,state,isDraft,headRefOid,headRefName,isCrossRepository,mergeStateStatus,url
# koto reads: on the leg path with Pull request empty, koto request get <request>.
set -uo pipefail

PROG=report-facts
HERE=$(cd "$(dirname "$0")" && pwd)
SESSION= SCOPE= NAME= REPO=
NO_SEAL=0

usage() { sed -n '/^# Usage:/,/^# Exit codes:/p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 64; }
while [ $# -gt 0 ]; do
    case "$1" in
        --session) [ $# -ge 2 ] || usage; SESSION=$2; shift 2 ;;
        --scope) [ $# -ge 2 ] || usage; SCOPE=$2; shift 2 ;;
        --name) [ $# -ge 2 ] || usage; NAME=$2; shift 2 ;;
        --repo) [ $# -ge 2 ] || usage; REPO=$2; shift 2 ;;
        --no-seal) NO_SEAL=1; shift ;;
        *) usage ;;
    esac
done
[ -n "$SESSION" ] || usage
. "$HERE/state-common.sh"
lib_facts
lib_log_readable || lib_die2 "no readable log for $SESSION"

T=$(mktemp -d "${TMPDIR:-/tmp}/report-facts.XXXXXX") || lib_die2 "cannot make a temporary directory"
trap 'rm -rf "$T"' EXIT
# One record read for the whole step: every state-holding.sh call below (the
# leg's holding list, the holding's row, the list again) takes it from here
# rather than reading the record again (shirabe#1094).
rs_once_begin "$T/once" holdings || lib_die2 "cannot make a temporary directory"

TOPIC=- ROW=null PRJ=null PRVIEW='{}' PROGRESS=0
finish() {
    local tok=$1
    # A checkpoint report is never classified: where a report reads holding,
    # it reads progress.
    [ "$PROGRESS" = 1 ] && case "$tok" in "holding "*) tok="progress ${tok#holding }" ;; esac
    jq -n --arg u "$TOPIC" --argjson row "$ROW" --argjson pr "$PRJ" --argjson v "$PRVIEW" '
        {unit: $u, pull_request: $pr, state: ($v.state // null), draft: (if ($v | has("isDraft")) then $v.isDraft else null end),
         head: ($v.headRefOid // null), merge_state: ($v.mergeStateStatus // null), holding: $row}' > "$T/report.json"
    lib_emit report_facts "$tok" coord/report.json "$T/report.json"
}

hold() { # hold <mode args...>: state-holding.sh with this run's facts
    if [ "$OVERRIDE" = 1 ]; then
        bash "$HERE/state-holding.sh" --scope "$SCOPE" --name "$NAME" --repo "$REPO" "$@"
    else
        bash "$HERE/state-holding.sh" --session "$SESSION" "$@"
    fi
}

# The unit, from the log alone (state-common.sh lib_unit, which
# state-confirm.sh uses too). On the message path it is the latest `wait`
# evidence with event report. On the leg path (the dispatch path's wait_leg,
# then take_report, then here) the hub's evidence carries no unit, so the
# unit is the holding whose Return path is the leg the engine captured:
# `leg <WAIT_REQ>:<WAIT_LEG>`. Which path applies is read from the log (the
# later of the two arrivals), never from a context key.
leg_holdings() {
    hold --list 2> "$T/list.err" || lib_die2 "state-holding.sh --list failed: $(lib_scrub < "$T/list.err")"
}
lib_unit "" 'report|progress' leg_holdings || finish "unknown -"
TOPIC=$UNIT
# Progress: the arrival is a `wait` evidence (never a leg's result) whose
# event is progress, read from the log, never from a context key.
if [ -z "$UNIT_LEG" ]; then
    EVP=$(bash "$HERE/coord-log.sh" evidence --session "$SESSION" --state wait --where 'event=report|progress' 2> /dev/null)
    case $? in 0|1) ;; *) lib_die2 "cannot read the session log" ;; esac
    [ "$(printf '%s' "$EVP" | jq -r '.fields.event // ""')" = progress ] && PROGRESS=1
fi
ROW=$(hold --topic "$TOPIC" --read 2> "$T/read.err")
case $? in
    0) ;;
    1) ROW=null; finish "unknown $TOPIC" ;;
    *) lib_die2 "state-holding.sh --read failed: $(lib_scrub < "$T/read.err")" ;;
esac
hold --list > "$T/all.json" 2> "$T/list.err" || lib_die2 "state-holding.sh --list failed: $(lib_scrub < "$T/list.err")"

CELL=$(printf '%s' "$ROW" | jq -r '.pull_request // ""')
BR=$(printf '%s' "$ROW" | jq -r '.branch // ""')
WORD=holding
if [ -n "$CELL" ]; then
    lib_pr_link "$CELL" || finish "refused $TOPIC bad-link"
else
    lib_report_pr
    [ -n "$REPORT_PR" ] || finish "holding none $TOPIC"
    lib_pr_ref "$REPORT_PR" || finish "refused $TOPIC bad-report-pr"
    WORD=link
fi
PRJ=$(jq -nc --arg r "$LINK_REPO" --argjson n "$LINK_NUM" '{repo: $r, number: $n, url: "https://github.com/\($r)/pull/\($n)"}')
lib_in_scope "$LINK_REPO" "$T/all.json" || finish "refused $TOPIC out-of-scope-repo"
if [ "$WORD" = link ] && lib_pr_held "$LINK_REPO" "$LINK_NUM" "$TOPIC" "$T/all.json"; then
    finish "refused $TOPIC pr-held"
fi
gh pr view "$LINK_NUM" --repo "$LINK_REPO" --json number,state,isDraft,headRefOid,headRefName,isCrossRepository,mergeStateStatus,url \
    > "$T/pr.json" 2> "$T/pr.err" < /dev/null || lib_die2 "cannot read $LINK_REPO#$LINK_NUM: $(lib_scrub < "$T/pr.err")"
PRVIEW=$(jq -c '{state, isDraft, headRefOid, mergeStateStatus, isCrossRepository, headRefName}' "$T/pr.json") || lib_die2 "jq failed"
[ "$(printf '%s' "$PRVIEW" | jq -r '.isCrossRepository')" = false ] || finish "refused $TOPIC fork-head"
if [ -n "$BR" ] && [ "$(printf '%s' "$PRVIEW" | jq -r '.headRefName // ""')" != "$BR" ]; then
    finish "refused $TOPIC branch-mismatch"
fi
# A holding keeps the head this read saw (PRD R17). This
# script is a check and writes nothing itself: state-holding.sh writes it in
# its own process, its output kept off the verdict line, and a write that fails
# or is refused is named on stderr and changes no verdict. A link's head is
# written by holding-link.sh with the link.
if [ "$WORD" = holding ]; then
    NEWH=$(printf '%s' "$PRVIEW" | jq -r '.headRefOid // ""')
    if [[ $NEWH =~ ^[0-9a-f]{40}$ ]] && [ "$NEWH" != "$(printf '%s' "$ROW" | jq -r '.pushed_head // ""')" ]; then
        hold --topic "$TOPIC" --pushed-head "$NEWH" > "$T/push.out" 2> "$T/push.err" \
            || echo "$PROG: $TOPIC's pushed head $NEWH wasn't kept: $(lib_scrub < "$T/push.err" | head -1)" >&2
    fi
fi
finish "$WORD $LINK_NUM $TOPIC"
