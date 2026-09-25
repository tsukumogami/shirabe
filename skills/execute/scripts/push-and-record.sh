#!/usr/bin/env bash
# push-and-record.sh — for /execute: push the current branch, then record the
# commit that was pushed as the session's expected head.
#
# The merge decision compares the PR's live head with the commit this run
# pushed (merge-verdict.sh row 8), so that a push the run didn't make can't be
# merged on the strength of checks the run saw. That comparison is only as good
# as the record behind it, and the record is written here, by the push itself,
# never by the agent: only after `git push` exits 0 does this script write
# `git rev-parse HEAD` into the koto session's `expected_head` context key. A
# failed push writes nothing, so the previous record (or none) stands, and a
# run with no record ends `ready-awaiting-merge` naming `head-moved` rather
# than merging.
#
# Every push /execute's single-pr directives make goes through this script: the
# initial push of the shared branch at orchestrator_setup and each follow-up fix
# pushed from ci_monitor. The finalization cascade's push records the same key
# through `run-cascade.sh --push --session <name>`.
#
# Usage: push-and-record.sh <koto-session-name> [<remote>]
#
#   <koto-session-name>  ^[A-Za-z0-9][A-Za-z0-9._-]*$
#   <remote>             ^[A-Za-z0-9._-]+$, not starting with `-`; default origin
#
# The push is exactly
#
#   git push --set-upstream <remote> HEAD:refs/heads/<branch>
#
# with the explicit refspec, so it can only ever update the branch of the same
# name, and never with a force option. --set-upstream keeps what the old
# `git push -u` gave a later bare `git push`.
#
# Refused before any push:
#   a detached HEAD (there is no branch to push);
#   a branch name outside ^[A-Za-z0-9._/-]+$, or holding `..`, or starting
#     with `-` or `/`;
#   the remote's default branch (from `git ls-remote --symref <remote> HEAD`,
#     else the local refs/remotes/<remote>/HEAD), and `main` and `master`
#     whenever neither source answers.
#
# Output: the recorded sha on stdout, and nothing else. git's output and every
# diagnostic go to stderr.
#
# Exit codes:
#   0   pushed, and expected_head recorded
#   64  usage error (missing or invalid session name or remote)
#   65  HEAD is detached
#   66  the branch name is refused
#   67  the branch is the remote's default branch
#   68  the push failed; nothing was recorded
#   69  pushed, but HEAD did not read back as a 40-character sha; nothing
#       was recorded
#   70  pushed, but the koto context write failed
#
# Requires: bash 3.2+, git, koto.
set -uo pipefail

PROG=push-and-record

RE_SESSION='^[A-Za-z0-9][A-Za-z0-9._-]*$'
RE_REMOTE='^[A-Za-z0-9._][A-Za-z0-9._-]*$'
RE_BRANCH='^[A-Za-z0-9._/-]+$'
RE_SHA='^[0-9a-f]{40}$'

usage_error() {
    echo "$PROG: $*" >&2
    echo "usage: push-and-record.sh <koto-session-name> [<remote>]" >&2
    exit 64
}

[ $# -ge 1 ] && [ $# -le 2 ] || usage_error "expected 1 or 2 arguments, got $#"
SESSION="$1"
REMOTE="${2:-origin}"
[[ $SESSION =~ $RE_SESSION ]] || usage_error "[$SESSION] is not a koto session name"
[[ $REMOTE =~ $RE_REMOTE ]] || usage_error "[$REMOTE] is not a remote name"

BRANCH=$(git symbolic-ref --quiet --short HEAD) || {
    echo "$PROG: HEAD is detached, so there is no branch to push. Check out the run's branch." >&2
    exit 65
}
if ! [[ $BRANCH =~ $RE_BRANCH ]]; then
    echo "$PROG: refusing branch name [$BRANCH]: it is outside ^[A-Za-z0-9._/-]+\$" >&2
    exit 66
fi
case "$BRANCH" in
    -*|/*|*..*|*/)
        echo "$PROG: refusing branch name [$BRANCH]" >&2
        exit 66
        ;;
esac

# The remote's own answer first; a local symref second; and when neither
# answers, the two conventional names, so an unanswerable question never lets
# every branch through.
DEFAULT=$(git ls-remote --symref "$REMOTE" HEAD </dev/null \
    | sed -n 's#^ref: refs/heads/\([^[:space:]]*\)[[:space:]]*HEAD$#\1#p' | head -1)
if [ -z "$DEFAULT" ]; then
    DEFAULT=$(git symbolic-ref --quiet --short "refs/remotes/$REMOTE/HEAD" || true)
    DEFAULT=${DEFAULT#"$REMOTE"/}
fi
refuse_default() {
    echo "$PROG: refusing to push [$BRANCH]: it is the default branch of $REMOTE." >&2
    echo "/execute pushes only its own branch." >&2
    exit 67
}
if [ -n "$DEFAULT" ]; then
    [ "$BRANCH" = "$DEFAULT" ] && refuse_default
else
    case "$BRANCH" in main|master) refuse_default ;; esac
fi

if ! git push --set-upstream "$REMOTE" "HEAD:refs/heads/$BRANCH" </dev/null >&2; then
    echo "$PROG: the push failed; expected_head was not recorded" >&2
    exit 68
fi

SHA=$(git rev-parse HEAD)
if ! [[ $SHA =~ $RE_SHA ]]; then
    echo "$PROG: HEAD read back as [$SHA], not a 40-character sha; nothing recorded" >&2
    exit 69
fi

# printf, not echo: koto stores the bytes it receives, and a trailing newline
# would make the record fail its own pattern.
if ! printf '%s' "$SHA" | koto context add "$SESSION" expected_head >/dev/null; then
    echo "$PROG: pushed $SHA, but recording expected_head in session [$SESSION] failed" >&2
    exit 70
fi

printf '%s\n' "$SHA"
exit 0
