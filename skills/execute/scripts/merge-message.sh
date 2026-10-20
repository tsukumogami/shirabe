#!/usr/bin/env bash
# merge-message.sh — for /execute: build the squash message a merge passes to
# merge-exec.sh, from the pull request's live title and Part 1.
#
# Every /execute merge (a coordinated node or follow-up, the coordination PR,
# and a single-pr run's home PR) lands its title and its Part 1 in the
# default branch's commit, never the reviewer context below the body's first
# top-level `---`, nor a coordination PR's index and run lines. The builder is
# scripts/lib/squash-message.sh, the one /coordinate's land step uses, so the
# two merge paths can't disagree about what a squash commit carries.
#
# Usage: merge-message.sh <owner/repo> <pr>
#
#   <owner/repo>  ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ (neither half `.`/`..`)
#   <pr>          ^[1-9][0-9]*$
#
# It reads `gh pr view <pr> --repo <owner/repo> --json title,body`, runs
# `squash-message.sh --title <title> <body-file>`, and writes the message to a
# new temporary file (mktemp) whose path it prints. The caller passes that
# path as merge-exec.sh's fourth argument and removes the file afterwards; it
# is the only file this script leaves behind.
#
# Output: the message file's path on stdout (exit 0), or
# `merge-refused:squash-message` (exit 1) when the builder refuses: an empty
# Part 1, a title that is empty or spans lines, or an AI attribution line or
# session link in the message. The builder's reason goes to stderr.
#
# Exit codes:
#   0   the message file's path printed
#   1   merge-refused:squash-message printed; no file left behind
#   64  usage error
#   72  the pull request's title and body could not be read, or no temporary
#       file could be made
#
# Requires: bash 3.2+, gh, jq.
set -uo pipefail

PROG=merge-message

SELF_DIR=$(CDPATH='' cd "$(dirname "${BASH_SOURCE[0]}")" && pwd) || exit 64
BUILDER="$SELF_DIR/../../../scripts/lib/squash-message.sh"

usage_error() {
    echo "$PROG: $*" >&2
    echo "usage: merge-message.sh <owner/repo> <pr>" >&2
    exit 64
}

[ $# -eq 2 ] || usage_error "expected 2 arguments, got $#"
REPO="$1"; PR="$2"
[[ $REPO =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || usage_error "<owner/repo> [$REPO] is outside its pattern"
case "/$REPO/" in */./*|*/../*) usage_error "<owner/repo> [$REPO] has a . or .. half" ;; esac
[[ $PR =~ ^[1-9][0-9]*$ ]] || usage_error "<pr> [$PR] is not a pull request number"
command -v jq >/dev/null || { echo "$PROG: jq is not on PATH" >&2; exit 72; }
[ -f "$BUILDER" ] || { echo "$PROG: the squash-message builder is missing at $BUILDER" >&2; exit 72; }

JSON=""
attempt=1
while :; do
    if JSON=$(gh pr view "$PR" --repo "$REPO" --json title,body </dev/null); then break; fi
    if [ "$attempt" -ge 2 ]; then
        echo "$PROG: could not read $REPO#$PR's title and body" >&2
        exit 72
    fi
    attempt=2
    sleep 1
done
TITLE=$(printf '%s' "$JSON" | jq -r 'if type == "object" then (.title // "") else error("not a PR object") end') || {
    echo "$PROG: $REPO#$PR's read is not a pull request object" >&2
    exit 72
}

BODY_FILE=$(mktemp "${TMPDIR:-/tmp}/merge-message-body.XXXXXX") || { echo "$PROG: no temporary file" >&2; exit 72; }
MSG_FILE=$(mktemp "${TMPDIR:-/tmp}/merge-message.XXXXXX") || { rm -f "$BODY_FILE"; echo "$PROG: no temporary file" >&2; exit 72; }
printf '%s' "$JSON" | jq -j '.body // ""' > "$BODY_FILE" || {
    rm -f "$BODY_FILE" "$MSG_FILE"
    echo "$PROG: $REPO#$PR's body could not be staged" >&2
    exit 72
}

"$BASH" "$BUILDER" --title "$TITLE" "$BODY_FILE" > "$MSG_FILE" </dev/null
rc=$?
rm -f "$BODY_FILE"
case "$rc" in
    0)
        printf '%s\n' "$MSG_FILE"
        exit 0
        ;;
    1|64)
        # A refusal (exit 1) or a title the builder takes as missing (64):
        # either way there is no message this merge may carry.
        rm -f "$MSG_FILE"
        printf 'merge-refused:squash-message\n'
        exit 1
        ;;
    *)
        rm -f "$MSG_FILE"
        echo "$PROG: the squash-message builder could not read $REPO#$PR's body (exit $rc)" >&2
        exit 72
        ;;
esac
