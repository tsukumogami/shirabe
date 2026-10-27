#!/usr/bin/env bash
# worktree-isolation.sh — for /execute and /deliver: stop a coordinated PLAN
# before any node is cut when the session is isolated in one repository's
# worktree and the PLAN has nodes in other repositories.
#
# A session a harness isolated in a linked worktree may run git only in that
# worktree: a worktree guard refuses every git command aimed at another
# repository's checkout, for the session and for every step agent it starts.
# A coordinated PLAN whose PR nodes land in other repositories can't be built
# from such a session, and node-cut.sh would find that out only at the first
# node outside the session's repository, after the earlier nodes were built.
# This check says so before the first node instead, as soon as the PLAN's
# repositories are known: /deliver runs it right after its scoping re-check,
# and /execute's coordinated setup (record-coord-setup.sh) runs it before it
# reads or writes anything.
#
# What counts as isolated. No environment variable says a session is
# isolated, so the check reads the shape isolation leaves: the current
# directory is in a linked worktree (git's git-dir differs from its
# common-dir). A session in a repository's main checkout passes, whatever the
# PLAN names, and so does a linked worktree whose PLAN's PR nodes all land in
# the worktree's own repository.
#
# The PLAN's repositories are its PR nodes' REPO values as plan-to-tasks.sh
# emits them, the same list record-coord-setup.sh records as the write set.
# The worktree's repository is read from its origin remote the way
# record-write-set.sh --print reads it. Names compare without regard to case,
# as GitHub's do. A PLAN whose mode isn't coordinated (plan-mode.sh) passes
# without either read: a single-pr PLAN runs in the repository it sits in.
#
# Usage: worktree-isolation.sh --plan <path> [--session <koto-session>]
#
# Output (stdout), one key=value per line:
#   isolation=pass|isolated
#   why=not-coordinated|not-a-worktree|one-repository   on pass
#   worktree=<absolute path>                            on isolated
#   worktree_repo=<owner/repo>                          on isolated
#   other_repos=<owner/repo[,owner/repo...]>            on isolated
#   message=<one plain sentence group>                  on isolated
#
# With --session it also records the verdict in that koto session, for
# /deliver's isolation_check state to route on: it removes
# isolation_verdict, worktree_repo and other_repos first, then writes
# isolation_verdict (pass or isolated) and, on isolated, worktree_repo and
# other_repos. The message is not stored: deliver-report.sh rebuilds it from
# those two keys.
#
# Exit codes:
#   0   pass; with --session, any verdict recorded
#   1   isolated (without --session)
#   64  usage error
#   65  could not decide: not inside a git repository, the worktree's
#       owner/repo could not be read, or the PLAN could not be read into nodes
#   66  a koto context call failed (--session only)
#
# Read-only on git and GitHub (gh only through record-write-set.sh's
# fallback read). Requires: bash 3.2+, git, jq; koto with --session.
set -uo pipefail

PROG=worktree-isolation

SELF_DIR=$(CDPATH='' cd "$(dirname "${BASH_SOURCE[0]}")" && pwd) || exit 64
PLAN_MODE="$SELF_DIR/../../../scripts/plan-mode.sh"
PLAN_TO_TASKS="$SELF_DIR/../../plan/scripts/plan-to-tasks.sh"
WRITE_SET="$SELF_DIR/record-write-set.sh"

RE_SESSION='^[A-Za-z0-9][A-Za-z0-9._-]*$'
RE_REPO='^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$'

usage_error() {
    echo "$PROG: $*" >&2
    echo "usage: worktree-isolation.sh --plan <path> [--session <koto-session>]" >&2
    exit 64
}

PLAN=""; SESSION=""
SEEN=" "
while [ $# -gt 0 ]; do
    case "$1" in
        --plan|--session)
            [ $# -ge 2 ] || usage_error "$1 needs a value"
            case "$SEEN" in *" $1 "*) usage_error "$1 given more than once" ;; esac
            SEEN="$SEEN$1 "
            case "$1" in
                --plan) PLAN="$2" ;;
                --session) SESSION="$2" ;;
            esac
            shift 2
            ;;
        *) usage_error "unexpected argument [$1]" ;;
    esac
done
[ -n "$PLAN" ] || usage_error "--plan is required"
case "$SEEN" in
    *" --session "*) [[ $SESSION =~ $RE_SESSION ]] || usage_error "session [$SESSION] is not a koto session name" ;;
esac

ctx_remove() {
    koto context remove "$SESSION" "$1" </dev/null >/dev/null && return 0
    echo "$PROG: koto context remove failed for $1" >&2
    exit 66
}
ctx_add() {
    printf '%s' "$2" | koto context add "$SESSION" "$1" >/dev/null && return 0
    echo "$PROG: koto context add failed for $1" >&2
    exit 66
}

if [ -n "$SESSION" ]; then
    ctx_remove isolation_verdict
    ctx_remove worktree_repo
    ctx_remove other_repos
fi

# pass <why> -- the session can build every node the PLAN names.
pass() {
    [ -n "$SESSION" ] && ctx_add isolation_verdict pass
    printf 'isolation=pass\nwhy=%s\n' "$1"
    exit 0
}

# undecided <why> -- no verdict: the caller fixes the cause and runs it again.
undecided() {
    echo "$PROG: could not decide: $*" >&2
    exit 65
}

bash "$PLAN_MODE" "$PLAN" </dev/null >/dev/null 2>&1
[ $? -eq 10 ] || pass not-coordinated

# abs_dir <dir> -- <dir> resolved from the current directory, symlinks too.
abs_dir() { (CDPATH='' cd -- "$1" 2>/dev/null && pwd -P); }

GIT_DIR_REL=$(git rev-parse --git-dir) || undecided "not inside a git repository"
COMMON_REL=$(git rev-parse --git-common-dir) || undecided "not inside a git repository"
GIT_DIR_ABS=$(abs_dir "$GIT_DIR_REL") || undecided "cannot resolve the git directory [$GIT_DIR_REL]"
COMMON_ABS=$(abs_dir "$COMMON_REL") || undecided "cannot resolve the git common directory [$COMMON_REL]"
[ "$GIT_DIR_ABS" != "$COMMON_ABS" ] || pass not-a-worktree

WORKTREE=$(git rev-parse --show-toplevel) || undecided "cannot read the worktree's top level"
WORKTREE=$(abs_dir "$WORKTREE") || undecided "cannot resolve the worktree [$WORKTREE]"
WT_REPO=$(bash "$WRITE_SET" --print </dev/null) || undecided "cannot read this worktree's owner/repo"
[[ $WT_REPO =~ $RE_REPO ]] || undecided "this worktree's owner/repo read as [$WT_REPO]"

TASKS=$(bash "$PLAN_TO_TASKS" "$PLAN" </dev/null) || undecided "plan-to-tasks.sh could not read $PLAN into nodes"
REPOS=$(printf '%s' "$TASKS" | jq -r '
    if type != "array" then error("not an array") else . end
    | [.[] | select((.vars.NODE_KIND // "pr") == "pr") | .vars.REPO // ""] | unique | .[]') \
    || undecided "plan-to-tasks.sh did not emit a node list for $PLAN"

lower() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]'; }
WT_LOWER=$(lower "$WT_REPO")
OTHERS=""
while IFS= read -r r; do
    [ -n "$r" ] || continue
    [[ $r =~ $RE_REPO ]] || undecided "the PLAN names a node repository [$r] that is not owner/repo"
    [ "$(lower "$r")" = "$WT_LOWER" ] && continue
    OTHERS="${OTHERS:+$OTHERS,}$r"
done <<EOF
$REPOS
EOF
[ -n "$OTHERS" ] || pass one-repository

if [ -n "$SESSION" ]; then
    ctx_add worktree_repo "$WT_REPO"
    ctx_add other_repos "$OTHERS"
    ctx_add isolation_verdict isolated
fi
MESSAGE="Stopped before any node was cut: this session is isolated in a worktree of $WT_REPO ($WORKTREE), and the PLAN also has nodes in ${OTHERS//,/, }. A session isolated in one repository's worktree can't run git in another repository's checkout, so those nodes can't be built from here. Run this again from a session that isn't isolated in one repository's worktree."
printf 'isolation=isolated\n'
printf 'worktree=%s\n' "$WORKTREE"
printf 'worktree_repo=%s\n' "$WT_REPO"
printf 'other_repos=%s\n' "$OTHERS"
printf 'message=%s\n' "$MESSAGE"
[ -n "$SESSION" ] && exit 0
exit 1
