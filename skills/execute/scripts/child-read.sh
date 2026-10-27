#!/usr/bin/env bash
# child-read.sh -- for /execute: one koto read of a coordinated work item's
# session, run in the node worktree its step agent opened it in.
# Part of the execute skill
#
# Usage: child-read.sh <node worktree> status <session>
#        child-read.sh <node worktree> context get <session> <key>
#
# The owning session of a coordinated run works in the coordination checkout,
# but a node's work items, `work-on-<slug>-<node>-<item>`, are opened by step
# agents in the node's worktree (node-cut.sh's `worktree=`). Under koto's
# cloud backend a session answers only in the directory it was opened in and
# refuses a read from any other with session_bound_elsewhere, so the owning
# session's `koto status <child>` after a step agent returns, and its read of
# the child's `summary.md` when it details the next work item, run through
# this script, which runs koto from the worktree. On the local backend the
# read answers the same from either directory.
#
# Only these two reads are served: nothing here writes, and every other verb
# is a usage error. The session name is ^[A-Za-z0-9][A-Za-z0-9._-]*$ and the
# key ^[A-Za-z0-9][A-Za-z0-9._/-]*$. koto is the one on PATH; its stdout,
# stderr and exit status pass through unchanged.
#
# Exit codes:
#   64  usage: a verb other than the two, a name or key outside its pattern,
#       or a worktree that is no directory; koto was not run
#   otherwise koto's own
#
# Requires: bash 3.2+, koto.
set -u

usage() {
    echo "child-read: $*" >&2
    echo "usage: child-read.sh <node worktree> status <session> | <node worktree> context get <session> <key>" >&2
    exit 64
}

RE_SESSION='^[A-Za-z0-9][A-Za-z0-9._-]*$'
RE_KEY='^[A-Za-z0-9][A-Za-z0-9._/-]*$'

[ $# -ge 1 ] || usage "a node worktree is required"
WT=$1
shift
[ -n "$WT" ] && [ -d "$WT" ] || usage "[$WT] is not a directory"
case "${1:-} ${2:-}" in
    "status "*)
        [ $# -eq 2 ] || usage "status takes one session"
        [[ $2 =~ $RE_SESSION ]] || usage "[$2] is not a koto session name"
        ;;
    "context get")
        [ $# -eq 4 ] || usage "context get takes a session and a key"
        [[ $3 =~ $RE_SESSION ]] || usage "[$3] is not a koto session name"
        [[ $4 =~ $RE_KEY ]] && [[ $4 != *..* ]] || usage "[$4] is not a context key"
        ;;
    *) usage "only status and context get are served" ;;
esac

CDPATH='' cd -- "$WT" || usage "cannot enter [$WT]"
exec koto "$@" </dev/null
