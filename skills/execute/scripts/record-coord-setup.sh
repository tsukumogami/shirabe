#!/usr/bin/env bash
# record-coord-setup.sh — for /execute: fix a coordinated run's write set and
# coordination home at start.
#
# execute-coordinated.md's `coord_setup` state is agent-run: the agent runs
# this script in the coordination checkout (the checkout holding the
# coordination branch and the PLAN), then ticks. The state's non-overridable
# context-matches gates read back what it wrote, so a run that could not
# record its write set never reaches the loop.
#
# It records four context keys:
#
#   repos         the write set: every PR node's REPO as plan-to-tasks.sh
#                 emits it, sorted, de-duplicated, comma-joined. Every PR the
#                 run opens, edits, readies, or merges must be in one of these
#                 repositories, and an index entry naming any other is refused.
#   home_repo     the one repository holding the coordination branch, read
#                 from the origin remote the way record-write-set.sh reads it.
#                 It must match ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ and be one
#                 of the repos entries.
#   coord_branch  the checked-out branch: the coordination branch. A detached
#                 HEAD and the remote's default branch are refused.
#   plan_abs      the PLAN's absolute path in this checkout, which outline
#                 children receive as PLAN_DOC (node branches don't carry it).
#
# All four are fixed for the run: a re-run that computes the same values is a
# no-op, and one that computes a different value refuses rather than moving
# the write set mid-run.
#
# Usage: record-coord-setup.sh --session <koto-session> --plan <path>
#
# Output: `repos=`, `home_repo=`, `coord_branch=`, `plan_abs=` lines on stdout.
#
# Exit codes:
#   0   recorded (or already recorded with the same values)
#   64  usage error
#   65  HEAD is detached
#   66  a value is outside its pattern, or home_repo is not in repos
#   67  the checked-out branch is the remote's default branch
#   68  a different value is already recorded for this session
#   69  the PLAN could not be read into nodes
#   70  a koto context write failed
#
# Requires: bash 3.2+, git, jq, koto.
set -uo pipefail

PROG=record-coord-setup

COORD_SELF_DIR=$(CDPATH='' cd "$(dirname "${BASH_SOURCE[0]}")" && pwd) || exit 64
# shellcheck source=coord-common.sh
. "$COORD_SELF_DIR/coord-common.sh"
PLAN_TO_TASKS="$COORD_SELF_DIR/../../plan/scripts/plan-to-tasks.sh"

RE_SESSION='^[A-Za-z0-9][A-Za-z0-9._-]*$'

usage_error() {
    echo "$PROG: $*" >&2
    echo "usage: record-coord-setup.sh --session <koto-session> --plan <path>" >&2
    exit 64
}

SESSION=""; PLAN=""
SEEN=" "
while [ $# -gt 0 ]; do
    case "$1" in
        --session|--plan)
            [ $# -ge 2 ] || usage_error "$1 needs a value"
            case "$SEEN" in *" $1 "*) usage_error "$1 given more than once" ;; esac
            SEEN="$SEEN$1 "
            case "$1" in
                --session) SESSION="$2" ;;
                --plan) PLAN="$2" ;;
            esac
            shift 2
            ;;
        *) usage_error "unexpected argument [$1]" ;;
    esac
done
[[ $SESSION =~ $RE_SESSION ]] || usage_error "session [$SESSION] is not a koto session name"
[ -f "$PLAN" ] || usage_error "no PLAN at [$PLAN]"

# repos, from the nodes.
TASKS=$("$BASH" "$PLAN_TO_TASKS" "$PLAN" </dev/null) || {
    echo "$PROG: plan-to-tasks.sh could not read $PLAN into nodes" >&2
    exit 69
}
REPOS=$(printf '%s' "$TASKS" | jq -r '
    if type != "array" then error("not an array") else . end
    | [.[] | select((.vars.NODE_KIND // "pr") == "pr") | .vars.REPO // ""] | unique | join(",")') || {
    echo "$PROG: plan-to-tasks.sh did not emit a node list" >&2
    exit 69
}
coord_valid_repo_list "$REPOS" || {
    echo "$PROG: the PLAN's node repositories [$REPOS] are not a list of owner/repo" >&2
    exit 66
}

# home_repo, read exactly as record-write-set.sh reads it.
HOME_REPO=$("$BASH" "$COORD_SELF_DIR/record-write-set.sh" --print) || {
    echo "$PROG: could not read this checkout's owner/repo" >&2
    exit 66
}
coord_valid_repo "$HOME_REPO" || { echo "$PROG: home_repo [$HOME_REPO] is not a single owner/repo" >&2; exit 66; }
if ! coord_in_list "$HOME_REPO" "$REPOS"; then
    echo "$PROG: this checkout's repository $HOME_REPO holds the coordination branch but is not in the write set [$REPOS]" >&2
    exit 66
fi

# coord_branch.
CB=$(git symbolic-ref --quiet --short HEAD) || {
    echo "$PROG: HEAD is detached; check out the coordination branch" >&2
    exit 65
}
coord_valid_branch "$CB" || { echo "$PROG: branch [$CB] is not an allowed branch name" >&2; exit 66; }
DEFAULT=$(git ls-remote --symref origin HEAD </dev/null \
    | sed -n 's#^ref: refs/heads/\([^[:space:]]*\)[[:space:]]*HEAD$#\1#p' | head -1)
if [ -z "$DEFAULT" ]; then
    DEFAULT=$(git symbolic-ref --quiet --short refs/remotes/origin/HEAD || true)
    DEFAULT=${DEFAULT#origin/}
fi
if [ -n "$DEFAULT" ]; then
    [ "$CB" = "$DEFAULT" ] && { echo "$PROG: [$CB] is the default branch, not a coordination branch" >&2; exit 67; }
else
    case "$CB" in main|master) echo "$PROG: [$CB] is a default branch name, not a coordination branch" >&2; exit 67 ;; esac
fi

# plan_abs.
PLAN_DIR=$(CDPATH='' cd "$(dirname -- "$PLAN")" && pwd -P) || exit 69
PLAN_ABS="$PLAN_DIR/$(basename -- "$PLAN")"
case "$PLAN_ABS" in /*) ;; *) echo "$PROG: [$PLAN_ABS] is not absolute" >&2; exit 66 ;; esac
case "$PLAN_ABS" in *"
"*) echo "$PROG: the PLAN path holds a newline" >&2; exit 66 ;; esac

record() { # record <key> <value>
    local old
    old=$(koto context get "$SESSION" "$1") || old=""
    if [ -n "$old" ]; then
        if [ "$old" != "$2" ]; then
            echo "$PROG: $1 is already recorded as [$old] for this run; refusing to change it to [$2]" >&2
            exit 68
        fi
        return 0
    fi
    printf '%s' "$2" | koto context add "$SESSION" "$1" >/dev/null || {
        echo "$PROG: could not write context key $1 in session $SESSION" >&2
        exit 70
    }
}

# Check every recorded value before writing any, so a refusal leaves the
# earlier record whole.
for pair in "repos=$REPOS" "home_repo=$HOME_REPO" "coord_branch=$CB" "plan_abs=$PLAN_ABS"; do
    k="${pair%%=*}"; v="${pair#*=}"
    old=$(koto context get "$SESSION" "$k") || old=""
    if [ -n "$old" ] && [ "$old" != "$v" ]; then
        echo "$PROG: $k is already recorded as [$old] for this run; refusing to change it to [$v]" >&2
        exit 68
    fi
done
record plan_abs "$PLAN_ABS"
record coord_branch "$CB"
record home_repo "$HOME_REPO"
# Last: coord_setup's gates read repos, so a partial write never passes.
record repos "$REPOS"

printf 'repos=%s\nhome_repo=%s\ncoord_branch=%s\nplan_abs=%s\n' "$REPOS" "$HOME_REPO" "$CB" "$PLAN_ABS"
exit 0
