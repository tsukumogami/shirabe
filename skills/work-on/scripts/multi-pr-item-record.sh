#!/usr/bin/env bash
# multi-pr-item-record.sh -- a multi-pr plan's item records itself in the
# plan's record root.
#
# A multi-pr PLAN runs through /work-on one item at a time, each item its own
# top-level run with its own pull request and no /execute session above it.
# The plan's record is one plan-level root at the shared address,
# `plan.<owner>.<repo>.<topic>.<sha12>` (scripts/run-trail.sh plan-root),
# which every item's run opens with the same attach-or-create call and
# records itself into, so scripts/run-record-lookup.sh leads from any item's
# PR to that root and the root lists every item's PR, items run later
# included.
#
#   start  at the item's start: opens the plan root, then records the PLAN
#          as committed now (`plan`, keyed by the item's step id) and the
#          item (`item`: this run's session and the directory it runs in,
#          no PR yet).
#   pr     once the item's PR exists: records the item again with its PR,
#          the PR in the root's trail (`pr`, role item, state open) and the
#          PR's index entry (`index --mode multi-pr`), in that order.
#
# A plan-backed child of /execute does none of this: its parent records it.
# The work-on template passes the run's own SHARED_BRANCH and ISSUE_SOURCE,
# which koto renders from the session's variables, and a run with either set
# is a plan-backed child: the script prints `skipped=plan-backed-child` and
# makes no koto call. A run given no PLAN (`--plan ""`), or a PLAN whose
# frontmatter doesn't say `execution_mode: multi-pr`, is not an item of a
# multi-pr plan and is skipped the same way (`skipped=no-plan`,
# `skipped=not-multi-pr`).
#
# Usage:
#   multi-pr-item-record.sh start --session WF --plan PATH --step ID
#       --repo owner/repo --shared-branch VALUE --issue-source VALUE
#   multi-pr-item-record.sh pr --session WF --plan PATH --step ID
#       --repo owner/repo --number N --shared-branch VALUE --issue-source VALUE
#
# PATH is docs/plans/PLAN-<topic>.md in the checkout that holds it, absolute
# or relative to the directory this runs from; ID is the item's step id, the
# run's ARTIFACT_PREFIX as the template passes it (`issue_<N>` for an issue,
# `task_<slug>` for free-form work). Run it
# from the item's own checkout: that directory is the item's recorded
# workspace. --shared-branch and --issue-source are required and may be
# empty.
#
# On success it prints `plan_root=<name>` and `recorded=start` or
# `recorded=pr`.
#
# Exit codes:
#   0   recorded, or skipped (the reason on stdout)
#   64  usage: an unknown subcommand or flag, a flag given twice or without
#       a value, a missing one
#   65  a value refused (here or by run-trail.sh); nothing more written
#   70  a koto, git or jq call failed (run-trail.sh's 70)
#
# Requires: bash 3.2+, git, jq, koto.
set -uo pipefail

PROG=multi-pr-item-record
SELF_DIR=$(CDPATH='' cd "$(dirname "${BASH_SOURCE[0]}")" && pwd) || exit 64
TRAIL=$(CDPATH='' cd "$SELF_DIR/../../../scripts" && pwd)/run-trail.sh || exit 64

usage() {
    echo "$PROG: $*" >&2
    echo "usage: multi-pr-item-record.sh start --session WF --plan PATH --step ID --repo owner/repo --shared-branch VALUE --issue-source VALUE" >&2
    echo "       multi-pr-item-record.sh pr --session WF --plan PATH --step ID --repo owner/repo --number N --shared-branch VALUE --issue-source VALUE" >&2
    exit 64
}

[ $# -ge 1 ] || usage "no subcommand"
SUB=$1
shift
case "$SUB" in
    start) ALLOWED=" --session --plan --step --repo --shared-branch --issue-source " ;;
    pr) ALLOWED=" --session --plan --step --repo --number --shared-branch --issue-source " ;;
    *) usage "unknown subcommand [$SUB]" ;;
esac

SESSION=""; PLAN=""; STEP=""; REPO=""; NUMBER=""; SHARED=""; SOURCE=""
SEEN=" "
while [ $# -gt 0 ]; do
    case "$SEEN" in *" $1 "*) usage "$1 given more than once" ;; esac
    case "$ALLOWED" in *" $1 "*) ;; *) usage "$SUB takes no argument [$1]" ;; esac
    [ $# -ge 2 ] || usage "$1 needs a value"
    SEEN="$SEEN$1 "
    case "$1" in
        --session) SESSION=$2 ;;
        --plan) PLAN=$2 ;;
        --step) STEP=$2 ;;
        --repo) REPO=$2 ;;
        --number) NUMBER=$2 ;;
        --shared-branch) SHARED=$2 ;;
        --issue-source) SOURCE=$2 ;;
    esac
    shift 2
done
for flag in $ALLOWED; do
    case "$SEEN" in *" $flag "*) ;; *) usage "$SUB needs $flag" ;; esac
done

if [ -n "$SHARED" ] || [ -n "$SOURCE" ]; then
    echo "skipped=plan-backed-child"
    exit 0
fi
if [ -z "$PLAN" ]; then
    echo "skipped=no-plan"
    exit 0
fi
[ -f "$PLAN" ] || { echo "$PROG: --plan [$PLAN] is not a file" >&2; exit 65; }
# The frontmatter is the block between the first two `---` lines. Only
# execution_mode is read, and only to skip a PLAN that isn't multi-pr; the
# PLAN's validity is shirabe validate's job, and the record verbs below hold
# every value they write to its own pattern.
MODE=$(awk 'NR == 1 && $0 != "---" { exit } NR > 1 && $0 == "---" { exit }
    NR > 1 && /^execution_mode:[ \t]*/ { sub(/^execution_mode:[ \t]*/, ""); sub(/[ \t]+$/, ""); print; exit }' "$PLAN") \
    || { echo "$PROG: could not read $PLAN" >&2; exit 70; }
MODE=${MODE#[\"\']}
MODE=${MODE%[\"\']}
if [ "$MODE" != multi-pr ]; then
    echo "skipped=not-multi-pr"
    exit 0
fi
case "$PLAN" in
    */PLAN-*.md) TOPIC=${PLAN##*/PLAN-} ;;
    PLAN-*.md) TOPIC=${PLAN#PLAN-} ;;
    *) echo "$PROG: --plan [$PLAN] is not docs/plans/PLAN-<topic>.md" >&2; exit 65 ;;
esac
TOPIC=${TOPIC%.md}

ROOT=$(bash "$TRAIL" plan-root --repo "$REPO" --plan "$PLAN") || exit $?
case "$SUB" in
    start)
        bash "$TRAIL" plan --session "$ROOT" --step "$STEP" --plan "$PLAN" || exit $?
        bash "$TRAIL" item --session "$ROOT" --step "$STEP" --child "$SESSION" || exit $?
        ;;
    pr)
        bash "$TRAIL" item --session "$ROOT" --step "$STEP" --child "$SESSION" \
            --repo "$REPO" --number "$NUMBER" || exit $?
        bash "$TRAIL" pr --session "$ROOT" --repo "$REPO" --number "$NUMBER" \
            --role item --state open || exit $?
        bash "$TRAIL" index --repo "$REPO" --number "$NUMBER" --session "$ROOT" \
            --mode multi-pr --topic "$TOPIC" || exit $?
        ;;
esac
printf 'plan_root=%s\nrecorded=%s\n' "$ROOT" "$SUB"
exit 0
