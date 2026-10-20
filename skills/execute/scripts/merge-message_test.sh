#!/usr/bin/env bash
# merge-message_test.sh — merge-message.sh builds a merge's squash message
# from the pull request's live title and Part 1
# Part of the execute skill
#
# Each case runs merge-message.sh against the eval gh shim's repository model
# (coord-test-helpers.sh), with TMPDIR pointed at the case's own directory so
# the files it leaves are countable. Cases:
#
#   a two-part body                   exit 0, the path of the one file left:
#                                     the title, a blank line, Part 1 as plain
#                                     text, nothing below the ---
#   a body with no top-level ---      the whole body is Part 1
#   an empty Part 1, a title spanning lines, an empty title, an AI
#   attribution line                  exit 1, merge-refused:squash-message,
#                                     no file left
#   a read that fails                 exit 72, no file left
#   usage                             exit 64, no gh call
#
# Usage: merge-message_test.sh
# Exit codes: 0 all pass, 1 a failure

set -uo pipefail

SCRIPT_DIR=$(CDPATH='' cd "$(dirname "$0")" && pwd)
MSG="$SCRIPT_DIR/merge-message.sh"

PASS_COUNT=0
FAIL_COUNT=0
pass() { echo "PASS: $*"; PASS_COUNT=$((PASS_COUNT + 1)); }
fail() { echo "FAIL: $*"; FAIL_COUNT=$((FAIL_COUNT + 1)); }

command -v jq >/dev/null 2>&1 || { echo "FAIL: jq is required" >&2; exit 1; }
command -v git >/dev/null 2>&1 || { echo "FAIL: git is required" >&2; exit 1; }

# shellcheck source=coord-test-helpers.sh
. "$SCRIPT_DIR/coord-test-helpers.sh"

run_msg() { # run_msg <repo> <pr>
    mkdir -p "$CASE/tmp"
    OUT=$(cd "$CASE" && TMPDIR="$CASE/tmp" bash "$MSG" "$@" 2>"$CASE/stderr")
    RC=$?
}
left() { find "$CASE/tmp" -type f -print | LC_ALL=C sort; }

msg_case() { # msg_case <name> [pr key=json ...]
    local name="$1"
    shift
    ct_case "$name"
    ct_pr "$CT_REPO" 11 "impl/t-$CT_CORE" "$@"
    ct_write_db
}

# --- a two-part body ----------------------------------------------------------

msg_case two-part 'title="feat(t): the parser"' \
    'body="Adds the **parser** and its `cli`.\n\n- one\n- two\n\n---\n\nReviewer context.\nCoordinated node.\n"'
run_msg "$CT_REPO" 11
WANT="feat(t): the parser

Adds the parser and its cli.

one
two"
if [ "$RC" -eq 0 ] && [ -f "$OUT" ] && [ "$(cat "$OUT")" = "$WANT" ]; then
    pass "the message is the title, a blank line, and Part 1 as plain text"
else
    fail "two-part: rc=$RC out=[$OUT] message=[$(cat "$OUT" 2>/dev/null)]"
fi
if [ "$(left)" = "$OUT" ]; then
    pass "the message file is the only file left behind"
else
    fail "files left: [$(left)]"
fi
case "$OUT" in "$CASE/tmp/"*) pass "the message file is a temporary file" ;; *) fail "the path [$OUT]" ;; esac
rm -f "$OUT"
[ -z "$(left)" ] && pass "the caller's removal leaves nothing" || fail "after the removal: [$(left)]"
if [ "$(ct_calls)" = "pr view 11 --repo $CT_REPO --json title,body" ]; then
    pass "one read: gh pr view --json title,body"
else
    fail "the gh calls: [$(ct_calls)]"
fi

msg_case no-separator 'body="The whole body.\n"'
run_msg "$CT_REPO" 11
[ "$RC" -eq 0 ] && [ "$(tail -1 "$OUT")" = "The whole body." ] \
    && pass "a body with no top-level --- is all Part 1" || fail "no separator: rc=$RC [$(cat "$OUT" 2>/dev/null)]"

# --- refusals -----------------------------------------------------------------

refused() { # refused <label> <pr key=json ...>
    local label="$1"
    shift
    msg_case "refused-$(printf '%s' "$label" | tr -c 'a-z0-9' '-')" "$@"
    run_msg "$CT_REPO" 11
    if [ "$RC" -eq 1 ] && [ "$OUT" = "merge-refused:squash-message" ] && [ -z "$(left)" ]; then
        pass "$label: exit 1, merge-refused:squash-message, no file left"
    else
        fail "$label: rc=$RC out=[$OUT] left=[$(left)]"
    fi
}
refused "an empty Part 1" 'body="\n\n---\n\nonly reviewer context\n"'
refused "a title spanning lines" 'title="feat(t): a\nb"'
refused "an empty title" 'title=""'
refused "an AI attribution line" 'body="Fix.\n\nCo-Authored-By: someone <x@example.com>\n\n---\n\nfields\n"'
refused "a session link" 'body="See https://claude.ai/chat/x for it.\n\n---\n"'

# --- a read that fails --------------------------------------------------------

msg_case read-fails
GH_SHIM_FAIL='^pr view 11 ' run_msg "$CT_REPO" 11
if [ "$RC" -eq 72 ] && [ -z "$OUT" ] && [ -z "$(left)" ]; then
    pass "a read that fails exits 72, prints nothing, and leaves no file"
else
    fail "read-fails: rc=$RC out=[$OUT] left=[$(left)]"
fi

# --- usage --------------------------------------------------------------------

ct_case usage
ct_write_db
for args in "" "$CT_REPO" "$CT_REPO 0" "a/b/c 11" "$CT_REPO 11 extra" "../x 11"; do
    # shellcheck disable=SC2086
    bash "$MSG" $args >/dev/null 2>&1; rc=$?
    [ "$rc" -eq 64 ] && pass "usage [$args] exits 64" || fail "usage [$args]: rc=$rc"
done
[ -s "$GH_CALL_LOG" ] && fail "a usage error made a gh call" || pass "no usage error made a gh call"

echo
echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed"
[ "$FAIL_COUNT" -eq 0 ] || exit 1
exit 0
