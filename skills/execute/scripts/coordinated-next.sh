#!/usr/bin/env bash
# coordinated-next.sh — for /execute: print the one next action of a
# coordinated run.
#
# The coordinated loop's decisions live here, not in prose. The script is
# stateless and read-only: it reads the PLAN's nodes (through
# plan-to-tasks.sh), the coordination PR's PR index (through the ownership
# filter), and live `gh`, writes nothing anywhere, and prints exactly one line.
# The agent performs that action and runs the script again, until it prints
# `done:<outcome>`, `pause`, or `error:<step>`.
#
# Usage:
#   coordinated-next.sh --plan <path> --slug <slug> --repos <owner/repo,...>
#                       --home-repo <owner/repo> --coord-branch <branch>
#                       --merge true|false [--attempts <node:result,...>]
#
#   --plan          the PLAN in the coordination checkout. While it exists its
#                   nodes come from plan-to-tasks.sh; once the finalization
#                   cascade has deleted it, from the PR index.
#   --slug          the topic slug, ^[a-z0-9-]+$; node branches are
#                   impl/<slug>-<node-id>
#   --repos         the write set recorded at coord_setup, comma-joined
#   --home-repo     the repository holding the coordination branch
#   --coord-branch  the coordination branch
#   --merge         this invocation's merge intent: exactly `true` or `false`,
#                   passed explicitly by the caller from the session's MERGE
#                   variable. The script reads no koto variable or environment
#                   for it; a missing or other value is a usage error.
#   --attempts      the session's `merge_attempts` record, written by
#                   coord-merge.sh: `<node>:merge-not-observed` or
#                   `<node>:merge-call-failed` for a merge this run already
#                   called and did not see land (node `coordination` for the
#                   coordination PR). Such a PR is not merged again in this
#                   invocation; it is reported unmerged with that reason.
#
# Output: exactly one line, from the closed set (first match wins):
#
#   error:<step>              a read failed (execute:status-read), a PR the
#                             run must adopt is not the one owned PR on its
#                             branch (execute:pr-adopt), a repository outside
#                             the write set (execute:write-set), a failing
#                             check (execute:ci), a closed PR
#                             (execute:pr-closed), or a verdict error
#   done:merged               the coordination PR is MERGED
#   merge:<node>              a node PR whose verdict is mergeable (only with
#                             --merge true); run coord-merge.sh on it
#   dispatch:<node>           a node with no indexed PR whose predecessors are
#                             all satisfied: cut it, run its work items, push
#   evaluate:<node>           a node PR that is still a draft (mark it ready
#                             once its checks pass) or whose checks are pending
#   cascade                   every node PR MERGED, and the finalization
#                             cascade has not run and been recorded
#   evaluate-coordination     the coordination PR is a draft after the cascade,
#                             or its checks are pending
#   merge-coordination        the coordination PR is mergeable (only with
#                             --merge true)
#   pause                     something is unmerged and a node cannot start
#                             because a predecessor is not satisfied
#   done:ready-awaiting-merge nothing is left to start and something is
#                             unmerged
#
# A PR node is satisfied only when a live read reports its PR MERGED: a merge
# call that returned `merge-called` is never read as merged. A gate node is
# never satisfied by this script, whose reads cannot verify a prose condition:
# it fails closed, and the nodes after it wait.
#
# Exit codes: 0 a line was printed (an error: line included); 64 usage error
# (nothing printed, no gh call made).
#
# Requires: bash 3.2+, jq, gh (through owned-pr.sh and merge-verdict.sh).
set -uo pipefail

PROG=coordinated-next

COORD_SELF_DIR=$(CDPATH='' cd "$(dirname "${BASH_SOURCE[0]}")" && pwd) || exit 64
COORD_PLAN_TO_TASKS="$COORD_SELF_DIR/../../plan/scripts/plan-to-tasks.sh"
# shellcheck source=coord-common.sh
. "$COORD_SELF_DIR/coord-common.sh"

usage_error() {
    echo "$PROG: $*" >&2
    echo "usage: coordinated-next.sh --plan <path> --slug <slug> --repos <list> --home-repo <owner/repo> --coord-branch <branch> --merge true|false [--attempts <list>]" >&2
    exit 64
}

CC_PLAN=""; CC_SLUG=""; CC_REPOS=""; CC_HOME=""; CC_CB=""; CC_MERGE=""; CC_ATTEMPTS=""
SEEN=" "
while [ $# -gt 0 ]; do
    case "$1" in
        --plan|--slug|--repos|--home-repo|--coord-branch|--merge|--attempts)
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
command -v jq >/dev/null || { printf 'error:execute:status-read\n'; echo "$PROG: jq is not on PATH" >&2; exit 0; }

coord_compute
printf '%s\n' "$CC_ACTION"
exit 0
