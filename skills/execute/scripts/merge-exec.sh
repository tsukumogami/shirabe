#!/usr/bin/env bash
# merge-exec.sh — for /execute: merge one PR, and only when a verdict this
# script computes itself, immediately before the call, says it may.
#
# This is the only place in the repository that calls `gh pr merge`, and a
# test holds it to that by grep. It never trusts a stored verdict, which the
# agent's shell could have written: it runs merge-verdict.sh from its own
# directory (never from PATH) with --merge true and the expected head it was
# given, and it merges only when that fresh verdict is exactly
# `mergeable:<method>:<expected-head>`. The call then carries
# --match-head-commit, so a push landing between the verdict and the merge
# makes GitHub refuse it.
#
# Usage: merge-exec.sh <owner/repo> <pr> <expected-head>
#
# Exactly three positional arguments, no flags, and nothing passed through.
# Closed patterns, checked before any gh call:
#   <owner/repo>     ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$  (neither half `.`/`..`)
#   <pr>             ^[1-9][0-9]*$
#   <expected-head>  ^[0-9a-f]{40}$  (`none` is refused: with no recorded head
#                    there is nothing to merge at)
#
# Output: exactly one line on stdout. Diagnostics, including gh's own output
# from the merge call, go to stderr. The grammar, as anchored extended regular
# expressions, where <verdict> is any line of merge-verdict.sh's grammar:
#
#   ^merge-called:(squash|merge|rebase):[0-9a-f]{40}$
#   ^merge-refused:<verdict>$
#
# `merge-called` means the merge call exited 0 and nothing more; it is never
# read as merged. The caller confirms with `merge-verdict.sh --confirm`, and
# only a live read of MERGED there reports `merged`. Refusals:
#   merge-refused:<fresh verdict>             the fresh verdict was not
#                                             mergeable at <expected-head>
#   merge-refused:not-merged:merge-call-failed  the merge call exited
#                                             non-zero, or merge-verdict.sh
#                                             itself failed or printed
#                                             something outside its grammar
#
# Exit codes:
#   0 — a line is on stdout (merge-called or merge-refused)
#   2 — usage error: wrong argument count or a value outside its pattern.
#       stdout is empty and no gh call was made.
#
# Exact gh invocations: those merge-verdict.sh makes with
# `--repo <repo> --pr <pr> --merge true --expected-head <expected-head>` (its
# header lists them), then at most one merge call, byte-for-byte:
#
#   gh pr merge <pr> --repo <repo> --<method> --match-head-commit <expected-head>
#
# with <method> taken from the fresh verdict and stdin from /dev/null. There is
# no --admin, no --auto, no --delete-branch, and no retry with another method
# or option when the call fails.
set -uo pipefail

PROG=merge-exec

RE_REPO='^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$'
RE_PR='^[1-9][0-9]*$'
RE_SHA='^[0-9a-f]{40}$'
RE_MERGEABLE='^mergeable:(squash|merge|rebase):[0-9a-f]{40}$'

usage_error() {
    echo "$PROG: $*" >&2
    echo "usage: merge-exec.sh <owner/repo> <pr> <expected-head>" >&2
    exit 2
}

[ $# -eq 3 ] || usage_error "expected exactly 3 arguments, got $#"

REPO="$1"
PR="$2"
EXPECTED="$3"

[[ $REPO =~ $RE_REPO ]] || usage_error "[$REPO] is not owner/repo"
case "/$REPO/" in
    */./*|*/../*) usage_error "[$REPO] names a dot path segment" ;;
esac
[[ $PR =~ $RE_PR ]] || usage_error "[$PR] is not a PR number"
[[ $EXPECTED =~ $RE_SHA ]] || usage_error "[$EXPECTED] is not a 40-character lowercase sha"

SELF_DIR=$(CDPATH='' cd "$(dirname "${BASH_SOURCE[0]}")" && pwd) || {
    echo "$PROG: cannot locate this script's directory" >&2
    echo "merge-refused:not-merged:merge-call-failed"
    exit 0
}
VERDICT_SCRIPT="$SELF_DIR/merge-verdict.sh"

refuse() {
    printf 'merge-refused:%s\n' "$1"
    exit 0
}

# Run by the interpreter already running this script, from this directory, so
# neither a merge-verdict.sh nor a bash planted earlier on PATH is ever run.
VERDICT=$("$BASH" "$VERDICT_SCRIPT" --repo "$REPO" --pr "$PR" --merge true --expected-head "$EXPECTED" </dev/null)
RC=$?
if [ "$RC" -ne 0 ]; then
    echo "$PROG: merge-verdict.sh exited $RC" >&2
    refuse "not-merged:merge-call-failed"
fi
case "$VERDICT" in
    *"
"*|"")
        echo "$PROG: merge-verdict.sh printed [$VERDICT], not one verdict line" >&2
        refuse "not-merged:merge-call-failed"
        ;;
esac

[[ $VERDICT =~ $RE_MERGEABLE ]] || refuse "$VERDICT"

METHOD=${VERDICT#mergeable:}
METHOD=${METHOD%%:*}
VERDICT_SHA=${VERDICT##*:}
[ "$VERDICT_SHA" = "$EXPECTED" ] || refuse "$VERDICT"
case "$METHOD" in
    squash|merge|rebase) ;;
    *) refuse "not-merged:merge-call-failed" ;;
esac

echo "$PROG: merging $REPO#$PR with --$METHOD at $EXPECTED" >&2
if gh pr merge "$PR" --repo "$REPO" "--$METHOD" --match-head-commit "$EXPECTED" </dev/null >&2; then
    printf 'merge-called:%s:%s\n' "$METHOD" "$EXPECTED"
    exit 0
fi
echo "$PROG: the merge call failed; not retrying with another method or option" >&2
refuse "not-merged:merge-call-failed"
