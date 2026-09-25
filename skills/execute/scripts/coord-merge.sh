#!/usr/bin/env bash
# coord-merge.sh — for /execute: merge one coordinated PR (a node PR, or the
# coordination PR last) through merge-exec.sh, and record a merge that did not
# land.
#
# coordinated-next.sh prints `merge:<node>` or `merge-coordination`; this is
# the command that action runs. It takes nothing the merge depends on from the
# agent: it finds the coordination PR through the ownership filter, reads the
# node's index line for the PR number and the `head=` that node-push.sh
# recorded, checks that the indexed PR is the one owned PR on the node's
# branch, and hands exactly those values to merge-exec.sh, which recomputes the
# verdict and makes the one fixed `gh pr merge --match-head-commit` call.
#
# For the coordination PR it first runs the merge-last gate itself:
# `shirabe validate --merge-gate --mode=ready` over the index's refs, with the
# entry pointing at the coordination PR itself dropped (the coordination PR
# can't wait on its own merge). A gate that doesn't pass refuses the merge.
#
# After a `merge-called:` line it runs `merge-verdict.sh --confirm`. A merge is
# never read as merged on the call alone. When the confirm read doesn't see
# MERGED, or the merge call itself failed, it records `<node>:<result>` in the
# session's `merge_attempts` context key, so the loop doesn't call the same
# merge again in this invocation: coordinated-next.sh then reports that PR
# unmerged with reason merge-not-observed or merge-call-failed.
#
# Usage:
#   coord-merge.sh --session <koto-session> --slug <slug>
#                  --home-repo <owner/repo> --coord-branch <branch>
#                  --node <node-id|coordination>
#
# Output: merge-exec.sh's line (`merge-called:<method>:<sha>` or
# `merge-refused:<verdict>`), then, after a call, the confirm line (`merged` or
# `not-merged:merge-not-observed`). A merge refused before merge-exec.sh runs
# prints `merge-refused:awaiting:head-moved` (no head= record) or
# `merge-refused:merge-gate`.
#
# Exit codes:
#   0   a line was printed (a refusal included)
#   64  usage error
#   70  the merge_attempts write failed
#   72  a GitHub read failed (execute:status-read)
#   73  the indexed PR is not the one owned PR on its branch, or the index has
#       no line for the node (execute:pr-adopt)
#
# Requires: bash 3.2+, gh, jq, koto, shirabe.
set -uo pipefail

PROG=coord-merge

COORD_SELF_DIR=$(CDPATH='' cd "$(dirname "${BASH_SOURCE[0]}")" && pwd) || exit 64
# shellcheck source=coord-common.sh
. "$COORD_SELF_DIR/coord-common.sh"
REPO_ROOT=$(CDPATH='' cd "$COORD_SELF_DIR/../../.." && pwd) || exit 64

usage_error() {
    echo "$PROG: $*" >&2
    echo "usage: coord-merge.sh --session <koto-session> --slug <slug> --home-repo <owner/repo> --coord-branch <branch> --node <node-id|coordination>" >&2
    exit 64
}

SESSION=""; SLUG=""; HOME_REPO=""; CB=""; NODE=""
SEEN=" "
while [ $# -gt 0 ]; do
    case "$1" in
        --session|--slug|--home-repo|--coord-branch|--node)
            [ $# -ge 2 ] || usage_error "$1 needs a value"
            case "$SEEN" in *" $1 "*) usage_error "$1 given more than once" ;; esac
            SEEN="$SEEN$1 "
            case "$1" in
                --session) SESSION="$2" ;;
                --slug) SLUG="$2" ;;
                --home-repo) HOME_REPO="$2" ;;
                --coord-branch) CB="$2" ;;
                --node) NODE="$2" ;;
            esac
            shift 2
            ;;
        *) usage_error "unexpected argument [$1]" ;;
    esac
done
[[ $SESSION =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || usage_error "session [$SESSION] is not a koto session name"
[[ $SLUG =~ $RE_COORD_SLUG ]] || usage_error "--slug [$SLUG] is outside ^[a-z0-9-]+\$"
coord_valid_repo "$HOME_REPO" || usage_error "--home-repo [$HOME_REPO] is not a single owner/repo"
coord_valid_branch "$CB" || usage_error "--coord-branch [$CB] is not an allowed branch name"
[[ $NODE =~ $RE_COORD_NODE ]] || usage_error "--node [$NODE] is outside ^[a-z][a-z0-9-]*\$"
command -v jq >/dev/null || { echo "$PROG: jq is not on PATH" >&2; exit 72; }

coord_find_pr "$HOME_REPO" "$CB" open
case $? in
    0) ;;
    2) exit 72 ;;
    *) exit 73 ;;
esac
BODY=$(printf '%s' "$C_JSON" | jq -r '.body // ""')
ENTRIES=$(coord_index_entries "$BODY")
LINE=$(coord_find_entry "$ENTRIES" "$NODE") || {
    echo "$PROG: the coordination PR's index has no single line for $NODE" >&2
    exit 73
}
coord_parse_entry "$LINE" || { echo "$PROG: the index line for $NODE is outside the grammar" >&2; exit 73; }
REPO="$E_REPO"; PR="$E_NUM"; HEAD="$E_HEAD"

if [ "$NODE" = coordination ]; then
    if [ "$PR" != "$C_NUM" ] || [ "$(coord_lower "$REPO")" != "$(coord_lower "$HOME_REPO")" ]; then
        echo "$PROG: the coordination line names $REPO#$PR, not the coordination PR $C_URL" >&2
        exit 73
    fi
else
    OUT=$("$BASH" "$COORD_SELF_DIR/owned-pr.sh" --repo "$REPO" --head "impl/$SLUG-$NODE" --state open </dev/null)
    case $? in
        0) ;;
        2) exit 72 ;;
        *) exit 73 ;;
    esac
    if [ -z "$OUT" ] || [ "${OUT##*/}" != "$PR" ]; then
        echo "$PROG: index entry $NODE names #$PR, which is not the owned open PR on $REPO impl/$SLUG-$NODE" >&2
        exit 73
    fi
fi

if [ -z "$HEAD" ]; then
    # No recorded push: merge-verdict.sh would say head-moved, and merge-exec.sh
    # takes no `none`.
    printf 'merge-refused:awaiting:head-moved\n'
    exit 0
fi

record_attempt() { # record_attempt <result>
    local old new rest e
    old=$(koto context get "$SESSION" merge_attempts) || old=""
    [[ $old =~ $RE_COORD_ATTEMPTS ]] || old=""
    new=""
    rest="$old"
    while [ -n "$rest" ]; do
        e="${rest%%,*}"
        if [ "$e" = "$rest" ]; then rest=""; else rest="${rest#*,}"; fi
        case "$e" in "$NODE":*) continue ;; esac
        if [ -z "$new" ]; then new="$e"; else new="$new,$e"; fi
    done
    if [ -z "$new" ]; then new="$NODE:$1"; else new="$new,$NODE:$1"; fi
    printf '%s' "$new" | koto context add "$SESSION" merge_attempts >/dev/null || {
        echo "$PROG: could not record merge_attempts in session $SESSION" >&2
        exit 70
    }
}

if [ "$NODE" = coordination ]; then
    # The merge-last gate, over every indexed PR but the coordination PR itself.
    REFS=$(printf '%s\n' "$BODY" | bash "$REPO_ROOT/scripts/coordination-gate-refs.sh" "$HOME_REPO" "$C_NUM") || REFS=""
    set --
    while IFS= read -r ref; do
        [ -n "$ref" ] && set -- "$@" --pr "$ref"
    done <<<"$REFS"
    if [ $# -eq 0 ]; then
        echo "$PROG: the coordination PR's index names no PR to gate on" >&2
        printf 'merge-refused:merge-gate\n'
        exit 0
    fi
    SHIRABE="${SHIRABE_BIN:-shirabe}"
    if ! "$SHIRABE" validate --merge-gate --mode=ready "$@" </dev/null >&2; then
        echo "$PROG: shirabe validate --merge-gate --mode=ready did not pass" >&2
        printf 'merge-refused:merge-gate\n'
        exit 0
    fi
fi

LINE1=$("$BASH" "$COORD_SELF_DIR/merge-exec.sh" "$REPO" "$PR" "$HEAD" </dev/null)
printf '%s\n' "$LINE1"
case "$LINE1" in
    merge-called:*)
        LINE2=$("$BASH" "$COORD_SELF_DIR/merge-verdict.sh" --repo "$REPO" --pr "$PR" --merge true \
            --expected-head "$HEAD" --confirm </dev/null) || LINE2="not-merged:merge-not-observed"
        [ "$LINE2" = merged ] || LINE2="not-merged:merge-not-observed"
        printf '%s\n' "$LINE2"
        [ "$LINE2" = merged ] || record_attempt merge-not-observed
        ;;
    merge-refused:not-merged:merge-call-failed)
        record_attempt merge-call-failed
        ;;
esac
exit 0
