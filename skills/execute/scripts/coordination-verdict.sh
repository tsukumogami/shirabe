#!/usr/bin/env bash
# coordination-verdict.sh — for /execute: the verdict a coordinated run ends on.
#
# When the coordinated loop stops (coordinated-next.sh printed `done:`,
# `pause`, or `error:`), koto's `coord_verdict` state runs this script, through
# record-coordination-verdict.sh, to decide which terminal the run ends at. It
# recomputes the run's position from the same reads coordinated-next.sh makes
# (the one shared computation in coord-common.sh), so the verdict never rests
# on what the agent said the loop printed. It is read-only: it writes neither
# GitHub nor koto context.
#
# Usage:
#   coordination-verdict.sh --plan <path> --slug <slug> --repos <list>
#                           --home-repo <owner/repo> --coord-branch <branch>
#                           --merge true|false [--attempts <list>]
#                           [--loop-line <line>]
#
# The first six flags and --attempts are coordinated-next.sh's. --loop-line is
# the last line the loop reported. It is used for one thing only: when the
# recomputed action is not a stopping one (the loop stopped while there is
# still something to do, for example because a child failed), the verdict is
# `error`, and a --loop-line of `error:execute:<step>` with a step from the
# closed set below names the step; anything else names execute:coord-loop. It
# can only ever pick which error the run ends on, never move it forward.
#
# Output, one key=value per line, in this order:
#
#   coord_verdict=<merged|ready|paused|dirty|error>
#   pr=<the coordination PR's URL>
#   waiting=<url>:<human|predecessor>[,...]   one entry per unmerged PR
#   resume=/execute <plan> [--merge]          on paused only
#   reason=<condition>                        ready, paused, dirty
#   step=<execute:step>                       error only
#
# The routes:
#
#   merged  the coordination PR is MERGED, or this run called its merge and
#           did not see it land (the confirm read decides) -> coord_merge_confirm
#   dirty   an unmerged node PR's merge state is DIRTY: reason merge-state:DIRTY
#   paused  a node waits on an unmerged predecessor
#   ready   nothing is left to start, something is unmerged
#   error   the loop's error, or a loop that stopped early
#
# reason is drawn from the merge decision table's conditions
# (merge-not-requested, head-moved, no-checks, base-unprotected, review,
# workflow-change, merge-method-unresolved, merge-state:<S>[:review=<R>]),
# merge-call-failed and merge-not-observed, and the pause conditions
# predecessor-unmerged and gate-unverified. step is one of execute:pr-closed,
# ready, ci, ci-timeout, status-read, pr-adopt, write-set, dispatch, push,
# cascade, merge-gate, coord-loop.
#
# Exit codes: 0 the verdict is on stdout; 64 usage error.
#
# Requires: bash 3.2+, jq, gh (through the shared computation).
set -uo pipefail

PROG=coordination-verdict

COORD_SELF_DIR=$(CDPATH='' cd "$(dirname "${BASH_SOURCE[0]}")" && pwd) || exit 64
COORD_PLAN_TO_TASKS="$COORD_SELF_DIR/../../plan/scripts/plan-to-tasks.sh"
# shellcheck source=coord-common.sh
. "$COORD_SELF_DIR/coord-common.sh"

RE_STEP_SET='^execute:(pr-closed|ready|ci|ci-timeout|status-read|pr-adopt|write-set|dispatch|push|cascade|merge-gate|coord-loop)$'

usage_error() {
    echo "$PROG: $*" >&2
    echo "usage: coordination-verdict.sh --plan <path> --slug <slug> --repos <list> --home-repo <owner/repo> --coord-branch <branch> --merge true|false [--attempts <list>] [--loop-line <line>]" >&2
    exit 64
}

CC_PLAN=""; CC_SLUG=""; CC_REPOS=""; CC_HOME=""; CC_CB=""; CC_MERGE=""; CC_ATTEMPTS=""
LOOP_LINE=""
SEEN=" "
while [ $# -gt 0 ]; do
    case "$1" in
        --plan|--slug|--repos|--home-repo|--coord-branch|--merge|--attempts|--loop-line)
            [ $# -ge 2 ] || usage_error "$1 needs a value"
            case "$SEEN" in *" $1 "*) usage_error "$1 given more than once" ;; esac
            SEEN="$SEEN$1 "
            case "$1" in
                --plan) CC_PLAN="$2" ;;
                --slug) CC_SLUG="$2" ;;
                --repos) CC_REPOS="$2" ;;
                --home-repo) CC_HOME="$2" ;;
                --coord-branch) CC_CB="$2" ;;
                --merge) CC_MERGE="$2" ;;
                --attempts) CC_ATTEMPTS="$2" ;;
                --loop-line) LOOP_LINE="$2" ;;
            esac
            shift 2
            ;;
        *) usage_error "unexpected argument [$1]" ;;
    esac
done

for f in --plan --slug --repos --home-repo --coord-branch --merge; do
    case "$SEEN" in *" $f "*) ;; *) usage_error "$f is required" ;; esac
done
case "$CC_MERGE" in true|false) ;; *) usage_error "--merge must be true or false, got [$CC_MERGE]" ;; esac
[[ $CC_SLUG =~ $RE_COORD_SLUG ]] || usage_error "--slug [$CC_SLUG] is outside ^[a-z0-9-]+\$"
coord_valid_repo_list "$CC_REPOS" || usage_error "--repos [$CC_REPOS] is not a comma-joined owner/repo list"
coord_valid_repo "$CC_HOME" || usage_error "--home-repo [$CC_HOME] is not a single owner/repo"
coord_in_list "$CC_HOME" "$CC_REPOS" || usage_error "--home-repo [$CC_HOME] is not in --repos"
coord_valid_branch "$CC_CB" || usage_error "--coord-branch [$CC_CB] is not an allowed branch name"
[ -n "$CC_PLAN" ] || usage_error "--plan is empty"
case "/$CC_PLAN/" in */../*) usage_error "--plan [$CC_PLAN] has a .. segment" ;; esac
case "$CC_PLAN" in *[!A-Za-z0-9._/-]*) usage_error "--plan [$CC_PLAN] holds a character outside [A-Za-z0-9._/-]" ;; esac
if [ -n "$CC_ATTEMPTS" ] && ! [[ $CC_ATTEMPTS =~ $RE_COORD_ATTEMPTS ]]; then
    usage_error "--attempts [$CC_ATTEMPTS] is outside <node>:<merge-not-observed|merge-call-failed>,..."
fi

emit() { # emit <verdict> <waiting> <resume> <reason> <step>
    printf 'coord_verdict=%s\n' "$1"
    printf 'pr=%s\n' "$CC_COORD_URL"
    printf 'waiting=%s\n' "$2"
    printf 'resume=%s\n' "$3"
    printf 'reason=%s\n' "$4"
    printf 'step=%s\n' "$5"
    exit 0
}

if ! command -v jq >/dev/null; then
    CC_COORD_URL=""
    emit error "" "" "" "execute:status-read"
fi

coord_compute

# The waiting list and the first human-waiting condition, from the unmerged
# PRs in merge order.
WAITING=""
FIRST_HUMAN_REASON=""
DIRTY=0
while IFS= read -r line; do
    [ -n "$line" ] || continue
    url="${line%% *}"
    rest="${line#* }"
    role="${rest%% *}"
    reason="${rest#* }"
    [[ $url =~ $RE_COORD_URL ]] || continue
    case ",$WAITING," in *",$url:"*) continue ;; esac
    if [ -z "$WAITING" ]; then WAITING="$url:$role"; else WAITING="$WAITING,$url:$role"; fi
    if [ "$role" = human ] && [ -z "$FIRST_HUMAN_REASON" ]; then
        FIRST_HUMAN_REASON="$reason"
    fi
    case "$reason" in merge-state:DIRTY|merge-state:DIRTY:*) DIRTY=1 ;; esac
done <<<"$CC_UNMERGED"

RESUME="/execute $CC_PLAN"
[ "$CC_MERGE" = true ] && RESUME="$RESUME --merge"

case "$CC_ACTION" in
    done:merged)
        emit merged "" "" "" ""
        ;;
    error:*)
        step="${CC_ACTION#error:}"
        [[ $step =~ $RE_STEP_SET ]] || step="execute:status-read"
        emit error "" "" "" "$step"
        ;;
    done:ready-awaiting-merge|pause)
        if [ "$CC_ACTION" = "done:ready-awaiting-merge" ] && [ "$CC_COORD_ATTEMPT" = "merge-not-observed" ]; then
            # This run called the coordination PR's merge and did not see it
            # land. Only the confirm read decides whether it has since.
            emit merged "$CC_COORD_URL:human" "" "" ""
        fi
        if [ "$DIRTY" -eq 1 ]; then
            emit dirty "$WAITING" "" "merge-state:DIRTY" ""
        fi
        if [ "$CC_ACTION" = pause ]; then
            emit paused "$WAITING" "$RESUME" "${FIRST_HUMAN_REASON:-${CC_BLOCK_REASON:-predecessor-unmerged}}" ""
        fi
        emit ready "$WAITING" "" "${FIRST_HUMAN_REASON:-predecessor-unmerged}" ""
        ;;
    *)
        # The loop stopped while there is still something to do.
        step="execute:coord-loop"
        case "$LOOP_LINE" in
            error:*)
                cand="${LOOP_LINE#error:}"
                [[ $cand =~ $RE_STEP_SET ]] && step="$cand"
                ;;
        esac
        emit error "" "" "" "$step"
        ;;
esac
