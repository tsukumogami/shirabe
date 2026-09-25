#!/usr/bin/env bash
# record-write-set.sh — for /execute: fix the run's write set at start.
#
# The write set is the set of repositories this run may write to. A single-pr
# run writes to one, the repository it runs in, and it is recorded once, before
# anything else happens, as the koto context key `repos`. Every PR lookup and
# both merge scripts then receive the repository from that record as an
# explicit argument, never from something the agent or a PR body says later.
# This is `write_set_record`'s default action, the template's initial state.
#
# The repository is read from the `origin` remote's configured URL (not the
# URL after `url.<base>.insteadOf` rewriting), in any of the forms
#
#   https://<host>/<owner>/<repo>[.git][/]
#   ssh://git@<host>/<owner>/<repo>[.git]
#   git@<host>:<owner>/<repo>[.git]
#
# and, when that URL names no owner/repo, from
# `gh repo view --json nameWithOwner --jq .nameWithOwner`.
#
# The value must match ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ with neither half `.`
# or `..`. Once recorded it is fixed: a re-run that computes the same value is a
# no-op, and one that computes a different value refuses rather than widening
# or moving the write set mid-run.
#
# Usage: record-write-set.sh <koto-session-name>
#        record-write-set.sh --print
#
# --print derives the same value and prints it without recording anything. It
# is what the Resume ladder's home-PR lookup uses before a session exists, so
# the lookup and the record read the repository one way.
#
# Output: the recorded owner/repo on stdout. Diagnostics go to stderr.
#
# Exit codes:
#   0   recorded (or already recorded with the same value)
#   64  usage error: the session name is missing or invalid
#   65  no owner/repo could be read for this repository
#   66  the value read is outside the pattern
#   67  a different write set is already recorded for this session
#   70  the koto context write failed
#
# Requires: bash 3.2+, git, koto; gh only for the fallback read.
set -uo pipefail

PROG=record-write-set

RE_SESSION='^[A-Za-z0-9][A-Za-z0-9._-]*$'
RE_REPO='^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$'

[ $# -eq 1 ] || { echo "usage: record-write-set.sh <koto-session-name> | --print" >&2; exit 64; }
SESSION="$1"
PRINT_ONLY=0
if [ "$SESSION" = "--print" ]; then
    PRINT_ONLY=1
elif ! [[ $SESSION =~ $RE_SESSION ]]; then
    echo "$PROG: [$SESSION] is not a koto session name" >&2
    exit 64
fi

URL=$(git config --get remote.origin.url || true)
REPO=""
case "$URL" in
    https://*/*/*|http://*/*/*|ssh://*/*/*)
        REPO=$(printf '%s' "$URL" | sed -E 's#/$##; s#\.git$##; s#^[a-z]+://([^/@]*@)?[^/]+/([^/]+)/([^/]+)$#\2/\3#')
        ;;
    *@*:*/*)
        REPO=$(printf '%s' "$URL" | sed -E 's#\.git$##; s#^[^@/]+@[^:/]+:([^/]+)/([^/]+)$#\1/\2#')
        ;;
esac
# A URL that did not reduce to exactly owner/repo is no answer.
[[ $REPO =~ $RE_REPO ]] || REPO=""
case "$REPO" in */*/*) REPO="" ;; esac

if [ -z "$REPO" ]; then
    REPO=$(gh repo view --json nameWithOwner --jq .nameWithOwner </dev/null || true)
fi
if [ -z "$REPO" ]; then
    echo "$PROG: could not read owner/repo from the origin remote [$URL] or from gh repo view" >&2
    exit 65
fi
if ! [[ $REPO =~ $RE_REPO ]]; then
    echo "$PROG: refusing write set [$REPO]: outside ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+\$" >&2
    exit 66
fi
case "/$REPO/" in
    */./*|*/../*)
        echo "$PROG: refusing write set [$REPO]: a dot path segment" >&2
        exit 66
        ;;
esac

if [ "$PRINT_ONLY" -eq 1 ]; then
    printf '%s\n' "$REPO"
    exit 0
fi

# koto reports a missing key with a non-zero exit (and its error on stdout), so
# the exit status, not the output, says whether a write set is recorded.
EXISTING=$(koto context get "$SESSION" repos) || EXISTING=""
if [ -n "$EXISTING" ]; then
    if [ "$EXISTING" = "$REPO" ]; then
        printf '%s\n' "$REPO"
        exit 0
    fi
    echo "$PROG: the write set is already fixed as [$EXISTING]; refusing to change it to [$REPO]" >&2
    exit 67
fi

if ! printf '%s' "$REPO" | koto context add "$SESSION" repos >/dev/null; then
    echo "$PROG: could not record the write set in session [$SESSION]" >&2
    exit 70
fi
printf '%s\n' "$REPO"
exit 0
