#!/usr/bin/env bash
# holding-link.sh -- write the pull request a worker's report names, and its
# head branch, onto the worker's holding. Agent-run, at state report_link.
#
# report_facts reads a holding whose Pull request cell is empty against the
# pull request the report itself names, and when that one may be adopted it
# seals `link <pr> <topic>`. This script is how the holding comes to carry it,
# so nothing downstream (verify_board, reconcile, the progress table) finds an
# empty cell for a worker whose pull request is open. It takes no pull request
# or topic as an argument: it reads them the way report_facts did, from the
# session log and GitHub, and re-checks everything before the write:
#   - the session is at report_link, and report_facts' REPORT capture, sealed
#     at its latest visit, reads `link <pr> <topic>` (exit 10 otherwise);
#   - the run's latest report is still that topic's, and the pull request it
#     names (record-common.sh lib_report_pr: koto's record of the leg, or the
#     `pull_request` field of the message's `wait` evidence) is #<pr>;
#   - the pull request is in the scope's repositories, no other Holdings row
#     links it, its head is not from a fork, and its head branch agrees with a
#     Branch cell already set (exit 65 otherwise, naming why).
# The Branch written is the pull request's headRefName as GitHub reports it,
# never text from the report. The row is written with record-holding.sh, which
# re-reads the record and checks provenance and directed transitions before
# record-write.sh writes it. A holding that already links the pull request is
# left as it is (exit 0), so running it again is safe; one that links another
# is refused.
#
# Usage:
#   holding-link.sh --session S
#   holding-link.sh --session S --scope roadmap|discipline --name N --repo O/R
#                   --ref N --skip-session-checks                    (tests)
#
# Exit codes: 0 written, or already linked (prints the record's URL, or
# `already linked`); 10 refused, either because the session log doesn't show
# this report's link (not at report_link, no sealed `link`, a later report, or
# another number than the one sealed) or because record-holding.sh refused the
# write (no open record, provenance, a directed transition); 65 the pull
# request was refused (the reason on stderr); 11 the write failed and 12 the
# record changed since the read (run it again for either); 13 the record is
# full; 2 a read failed (run it again); 64 usage. Every refusal names its
# reason on stderr.
#
# GitHub reads: record-holding.sh --list;
# gh pr view <n> --repo <repo> --json headRefName,isCrossRepository,url (the link
# names the repository as that URL spells it).
# GitHub writes: only through record-holding.sh (record-write.sh).
set -uo pipefail

PROG=holding-link
HERE=$(cd "$(dirname "$0")" && pwd)
SESSION= SCOPE= NAME= REPO= REF=
SKIP_CHECKS=0

usage() { sed -n '/^# Usage:/,/^# Exit codes:/p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 64; }
while [ $# -gt 0 ]; do
    case "$1" in
        --session) [ $# -ge 2 ] || usage; SESSION=$2; shift 2 ;;
        --scope) [ $# -ge 2 ] || usage; SCOPE=$2; shift 2 ;;
        --name) [ $# -ge 2 ] || usage; NAME=$2; shift 2 ;;
        --repo) [ $# -ge 2 ] || usage; REPO=$2; shift 2 ;;
        --ref) [ $# -ge 2 ] || usage; REF=$2; shift 2 ;;
        --skip-session-checks) SKIP_CHECKS=1; shift ;;
        *) usage ;;
    esac
done
# The pull request and topic live in the session log, so a session is always needed.
[ -n "$SESSION" ] || usage
. "$HERE/record-common.sh"
lib_facts
if [ "$OVERRIDE" = 1 ]; then
    [[ $REF =~ $RE_NUM ]] || { echo "$PROG: --ref goes with the override flags" >&2; exit 64; }
else
    [ -z "$REF" ] && [ "$SKIP_CHECKS" = 0 ] || usage
fi
lib_log_readable || lib_die2 "no readable log for $SESSION"

T=$(mktemp -d "${TMPDIR:-/tmp}/holding-link.XXXXXX")
trap 'rm -rf "$T"' EXIT

refuse() { echo "$PROG: refused: $*" >&2; exit 65; }
hold() { # hold <mode args...>: record-holding.sh with this run's facts
    if [ "$OVERRIDE" = 1 ]; then
        set -- --scope "$SCOPE" --name "$NAME" --repo "$REPO" --ref "$REF" "$@"
        [ "$SKIP_CHECKS" = 1 ] && set -- "$@" --skip-session-checks
    fi
    bash "$HERE/record-holding.sh" --session "$SESSION" "$@"
}

CUR=$(bash "$HERE/coord-log.sh" current --session "$SESSION" 2> /dev/null)
case $? in 0|1) ;; *) lib_die2 "cannot read the session log" ;; esac
[ "${CUR%% *}" = report_link ] || { echo "$PROG: refused: the run is at ${CUR%% *}, not report_link" >&2; exit 10; }

CAP=$(bash "$HERE/coord-log.sh" capture --session "$SESSION" --name REPORT --state report_facts 2> /dev/null)
case $? in 0) ;; 1) CAP= ;; *) lib_die2 "cannot read the report_facts capture" ;; esac
set -f; set -- ${CAP% sealed:*}; set +f
if [ $# -ne 3 ] || [ "$1" != link ] || ! [[ $2 =~ $RE_NUM ]] || ! [[ $3 =~ $RE_TOPIC ]]; then
    echo "$PROG: refused: report_facts' latest verdict is [${CAP% sealed:*}], not a pull request to link" >&2
    exit 10
fi
NUM=$2 TOPIC=$3

# The same derivation report_facts made, from the log, so the capture is
# checked against what the report said rather than trusted alone.
hold --list > "$T/all.json" 2> "$T/list.err" || lib_die2 "record-holding.sh --list failed: $(lib_scrub < "$T/list.err")"
all_rows() { cat "$T/all.json"; }
lib_unit "" 'report|progress' all_rows
[ "$UNIT" = "$TOPIC" ] || { echo "$PROG: refused: the latest report is ${UNIT:-no worker}'s, not $TOPIC's" >&2; exit 10; }
lib_report_pr
lib_pr_ref "$REPORT_PR" || refuse "the report names [$REPORT_PR], not a pull request"
[ "$LINK_NUM" = "$NUM" ] || { echo "$PROG: refused: the report names #$LINK_NUM, report_facts sealed #$NUM" >&2; exit 10; }
PR_REPO=$LINK_REPO

jq -c --arg t "$TOPIC" '[.[] | select(.worker == $t)][0] // empty' "$T/all.json" > "$T/row.json" || lib_die2 "jq failed"
[ -s "$T/row.json" ] || refuse "no holding for $TOPIC"
CELL=$(jq -r '.pull_request // ""' "$T/row.json")
BR=$(jq -r '.branch // ""' "$T/row.json")
# Linked already (a second run after a write report_facts hasn't re-read yet):
# nothing to do. A Branch cell is neither checked nor filled here: report_facts'
# next read compares it with the head branch, as for any linked holding.
if [ -n "$CELL" ]; then
    if lib_pr_link "$CELL" && [ "$LINK_NUM" = "$NUM" ] \
        && [ "$(printf '%s' "$LINK_REPO" | tr '[:upper:]' '[:lower:]')" = "$(printf '%s' "$PR_REPO" | tr '[:upper:]' '[:lower:]')" ]; then
        echo "already linked"
        exit 0
    fi
    refuse "the holding for $TOPIC already links $CELL"
fi
lib_in_scope "$PR_REPO" "$T/all.json" || refuse "$PR_REPO is neither the host nor the repository of any holding"
! lib_pr_held "$PR_REPO" "$NUM" "$TOPIC" "$T/all.json" || refuse "another holding links $PR_REPO#$NUM"

gh pr view "$NUM" --repo "$PR_REPO" --json headRefName,isCrossRepository,url > "$T/pr.json" 2> "$T/pr.err" < /dev/null \
    || lib_die2 "cannot read $PR_REPO#$NUM: $(lib_scrub < "$T/pr.err")"
[ "$(jq -r '.isCrossRepository' "$T/pr.json")" = false ] || refuse "$PR_REPO#$NUM's head is in another repository"
# The link names the repository as GitHub spells it, whatever case the report used.
lib_pr_ref "$(jq -r '.url // ""' "$T/pr.json")" && [ "$LINK_NUM" = "$NUM" ] \
    || lib_die2 "$PR_REPO#$NUM's URL as GitHub reports it is not a pull request URL"
PR_REPO=$LINK_REPO
HEAD_BR=$(jq -r '.headRefName // ""' "$T/pr.json")
[ -n "$HEAD_BR" ] || lib_die2 "$PR_REPO#$NUM has no head branch"
[ -z "$BR" ] || [ "$BR" = "$HEAD_BR" ] || refuse "$PR_REPO#$NUM's head branch is $HEAD_BR, the holding's Branch is $BR"

jq --arg b "$HEAD_BR" --arg p "[#$NUM](https://github.com/$PR_REPO/pull/$NUM)" '.branch = $b | .pull_request = $p' \
    "$T/row.json" > "$T/next.json" || lib_die2 "jq failed"
hold --topic "$TOPIC" --row-file "$T/next.json"
