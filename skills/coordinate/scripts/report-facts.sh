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
# back to the hub, never to classification, with no phase change. The one
# exception is a holding whose entry point is `coordinate`: a progress event
# there names a pull request of a worker the dispatched coordinator runs, not
# its own, so with the Pull request cell empty it gives `progress none`, never
# `link`, and the holding is left as it was. That coordinator's report still
# links the pull request it sends up.
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
# Exit codes: 0 a verdict was printed; 2 a read failed, or a read, the
# coord/report.json add or the seal ran past the deadline; 64 usage.
#
# Environment (tests only): REPORT_FACTS_DEADLINE=<seconds>, counted from the
# script's start, after which a backend call still running is stopped.
#
# The record through state-holding.sh --read and --list, which share one read
# of it (rs_once_begin), and state-holding.sh --pushed-head writes a changed
# head into the one session key that keeps it, reading and writing no body.
# Every call to the storage backend or GitHub (those reads, gh pr view, the
# coord/report.json add, the seal and the pushed-head write) runs in its own
# process group and is stopped once the action has run REPORT_FACTS_DEADLINE
# seconds (26 by default, under koto's 30 s action limit; the clock is whole
# seconds), so a slow backend never runs the action into koto's kill
# (shirabe#1123, #1531). A call whose script is killed first is stopped by a
# watcher in its own group. A read, the add or the seal the deadline stops
# exits 2 naming it on stderr, before any verdict is printed.
#
# The pushed-head write's time never decides the verdict or the exit code:
# the verdict is written and sealed first, and the write is skipped when about
# a second or less is left. A head that wasn't kept is named on stderr and
# tried again on the holding's next visit, which compares the pull request's
# head with the row's pushed_head again.
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
DEADLINE=${REPORT_FACTS_DEADLINE:-26}
[[ $DEADLINE =~ ^[0-9]+$ ]] || { echo "$PROG: REPORT_FACTS_DEADLINE is a whole number of seconds" >&2; exit 64; }
. "$HERE/state-common.sh"
lib_facts
lib_log_readable || lib_die2 "no readable log for $SESSION"

T=$(mktemp -d "${TMPDIR:-/tmp}/report-facts.XXXXXX") || lib_die2 "cannot make a temporary directory"
BOUNDED=
trap 'stop_bounded; rm -rf "$T"' EXIT
# A signal ends the script through the EXIT trap, so a backend call still
# running (the pushed-head write among them) is stopped rather than left to
# land after the action.
trap 'exit 2' TERM INT HUP
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
    # The facts go to coord/report.json as data and the verdict is sealed to
    # this visit, as lib_emit does, with each call bounded by the deadline.
    # Under --no-seal the token is printed bare and nothing is written.
    local sealed=$tok
    if [ "$NO_SEAL" != 1 ]; then
        bounded add "$KOTO" context add "$SESSION" coord/report.json --from-file "$T/report.json"
        case $? in
            0) ;;
            124) late "the coord/report.json add" ;;
            *) lib_die2 "koto context add coord/report.json failed: $(lib_scrub < "$T/add.err")" ;;
        esac
        bounded seal bash "$HERE/coord-log.sh" seal --session "$SESSION" --state report_facts --token "$tok"
        case $? in
            0) ;;
            124) late "the verdict's seal (coord-log.sh seal)" ;;
            *) lib_die2 "cannot seal the verdict: $(lib_scrub < "$T/seal.err")" ;;
        esac
        sealed=$(cat "$T/seal.out")
    fi
    # finish <token> <head>: the verdict is written and sealed before the
    # pushed-head write and printed after it, so the write, however it ends,
    # changes neither.
    [ -z "${2:-}" ] || keep_head "$2"
    printf '%s\n' "$sealed"
    exit 0
}

# bounded <name> <command...>: run the command with stdin from /dev/null,
# stdout in $T/<name>.out and stderr in $T/<name>.err, stopped once the
# action has run DEADLINE seconds. It runs in its own process group (job
# control on for this one job), so stopping it stops every koto or gh call
# under it. That takes it out of the group koto kills when the action runs
# out of time, so a guard in the group stops the group when this script is
# gone, whatever ended it, as well as at the deadline, where it marks
# $T/<name>.late first. Returns the command's status, or 124 when the
# deadline stopped it or had passed before it could start.
bounded() {
    local n=$1 rc
    shift
    rm -f "$T/$n.late"
    [ "$SECONDS" -lt "$DEADLINE" ] || return 124
    set -m
    (
        (
            # The guard outlives the TERM it sends its own group, to send
            # the KILL after the grace.
            trap '' TERM
            while kill -0 "$$" 2> /dev/null && [ "$SECONDS" -lt "$DEADLINE" ]; do sleep 0.2; done
            kill -0 "$$" 2> /dev/null && : > "$T/$n.late"
            kill -TERM 0
            sleep 0.5
            kill -KILL 0
        ) &
        w=$!
        "$@"
        rc=$?
        kill -KILL "$w" 2> /dev/null
        exit "$rc"
    ) < /dev/null > "$T/$n.out" 2> "$T/$n.err" &
    BOUNDED=$!
    set +m
    wait "$BOUNDED" 2> /dev/null
    rc=$?
    BOUNDED=
    [ -e "$T/$n.late" ] && return 124
    return "$rc"
}

# stop_bounded: stop a bounded call still running when the script ends, TERM
# and then KILL after a short grace, and reap it.
stop_bounded() {
    [ -n "$BOUNDED" ] || return 0
    local i
    kill -TERM -- "-$BOUNDED" 2> /dev/null
    for i in 1 2 3 4 5; do
        kill -0 -- "-$BOUNDED" 2> /dev/null || break
        sleep 0.1
    done
    kill -KILL -- "-$BOUNDED" 2> /dev/null
    wait "$BOUNDED" 2> /dev/null
    BOUNDED=
}

# late <what>: a call the deadline stopped, or had no time left to start, is
# a failed read (exit 2), never a verdict.
late() { lib_die2 "$1 didn't finish within the action's $DEADLINE s deadline"; }

# keep_head <sha>: write the holding's pushed head, bounded by the deadline.
# A write that fails, is refused or is stopped is named on stderr; none
# changes the verdict or the exit code.
keep_head() {
    local newh=$1 rc
    if [ $((DEADLINE - SECONDS)) -le 1 ]; then
        echo "$PROG: $TOPIC's pushed head $newh wasn't kept: no time was left for the write" >&2
        return 0
    fi
    bounded push hold --topic "$TOPIC" --pushed-head "$newh"
    rc=$?
    case $rc in
        0) ;;
        124) echo "$PROG: $TOPIC's pushed head $newh wasn't kept: the write was stopped at the action's $DEADLINE s deadline (a store that keeps writes until the tick ends may still land it)" >&2 ;;
        *) echo "$PROG: $TOPIC's pushed head $newh wasn't kept: $(lib_scrub < "$T/push.err" | head -1)" >&2 ;;
    esac
    return 0
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
    holdings_list
    cat "$T/list.out"
}
# holdings_list: the Holdings rows in $T/list.out, or exit 2.
holdings_list() {
    bounded list hold --list
    case $? in
        0) ;;
        124) late "the holdings read (state-holding.sh --list)" ;;
        *) lib_die2 "state-holding.sh --list failed: $(lib_scrub < "$T/list.err")" ;;
    esac
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
bounded read hold --topic "$TOPIC" --read
case $? in
    0) ROW=$(cat "$T/read.out") ;;
    1) ROW=null; finish "unknown $TOPIC" ;;
    124) late "the holding's read (state-holding.sh --read)" ;;
    *) lib_die2 "state-holding.sh --read failed: $(lib_scrub < "$T/read.err")" ;;
esac
holdings_list
mv "$T/list.out" "$T/all.json" || lib_die2 "cannot keep the Holdings rows"

CELL=$(printf '%s' "$ROW" | jq -r '.pull_request // ""')
BR=$(printf '%s' "$ROW" | jq -r '.branch // ""')
WORD=holding
if [ -n "$CELL" ]; then
    lib_pr_link "$CELL" || finish "refused $TOPIC bad-link"
else
    # A coordinate holding's progress event links nothing: the pull request
    # it names belongs to a worker under that coordinator, not to the
    # holding, and linking it would count the holding as one with a pull
    # request in flight. Its report still links what it sends up.
    if [ "$PROGRESS" = 1 ] && printf '%s' "$ROW" | jq -e '(.entry_point // "") | ltrimstr("/shirabe:") == "coordinate"' > /dev/null; then
        finish "holding none $TOPIC"
    fi
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
bounded pr gh pr view "$LINK_NUM" --repo "$LINK_REPO" --json number,state,isDraft,headRefOid,headRefName,isCrossRepository,mergeStateStatus,url
case $? in
    0) ;;
    124) late "the pull request read (gh pr view $LINK_NUM --repo $LINK_REPO)" ;;
    *) lib_die2 "cannot read $LINK_REPO#$LINK_NUM: $(lib_scrub < "$T/pr.err")" ;;
esac
PRVIEW=$(jq -c '{state, isDraft, headRefOid, mergeStateStatus, isCrossRepository, headRefName}' "$T/pr.out") || lib_die2 "jq failed"
[ "$(printf '%s' "$PRVIEW" | jq -r '.isCrossRepository')" = false ] || finish "refused $TOPIC fork-head"
if [ -n "$BR" ] && [ "$(printf '%s' "$PRVIEW" | jq -r '.headRefName // ""')" != "$BR" ]; then
    finish "refused $TOPIC branch-mismatch"
fi
# A holding keeps the head this read saw (PRD R17). This
# script is a check and writes nothing itself: state-holding.sh writes it in
# its own process, its output kept off the verdict line, after the verdict is
# sealed and bounded by the deadline (keep_head), and a write that fails, is
# refused or is stopped is named on stderr and changes no verdict. A link's
# head is written by holding-link.sh with the link.
if [ "$WORD" = holding ]; then
    NEWH=$(printf '%s' "$PRVIEW" | jq -r '.headRefOid // ""')
    if [[ $NEWH =~ ^[0-9a-f]{40}$ ]] && [ "$NEWH" != "$(printf '%s' "$ROW" | jq -r '.pushed_head // ""')" ]; then
        finish "$WORD $LINK_NUM $TOPIC" "$NEWH"
    fi
fi
finish "$WORD $LINK_NUM $TOPIC"
