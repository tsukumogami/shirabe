#!/usr/bin/env bash
# squash-message_test.sh -- squash-message.sh builds the commit message from
# a title and the body's Part 1 as plain text, and refuses an empty Part 1 or
# an attribution line.
#
# Covers: markdown removed (headings, emphasis, code ticks, list markers, task
# boxes, blockquotes, table rules and pipes, images, HTML comments), links as
# `text (url)`, blank runs collapsed; Part 1 ending at the first `---` outside
# a fence; refusals; usage.
#
# Usage: bash skills/coordinate/scripts/squash-message_test.sh
set -uo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
command -v jq >/dev/null 2>&1 || { echo "SKIP: jq not on PATH"; exit 0; }
SM="$HERE/squash-message.sh"
PASS=0 FAIL=0
ok()  { PASS=$((PASS + 1)); printf 'ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); printf 'FAIL %s\n     %s\n' "$1" "${2-}"; }
eq() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "want [$2], got [$3]"; fi; }
msg() { printf '%s' "$2" | bash "$SM" --title "$1" - 2>/dev/null; }

eq "the title, a blank line, then Part 1" "$(printf 'feat(x): y\n\nThe change.')" "$(msg 'feat(x): y' "$(printf 'The change.\n\n---\n\nReviewer context.\n')")"
eq "emphasis, ticks and links" "Adds panel reading to the land step, see the design (https://x.y/z)." \
    "$(msg t "$(printf 'Adds **panel** reading to the `land` step, see [the design](https://x.y/z).\n---\n')" | tail -1)"
eq "italic, underscores and images" "an item and bold alt" "$(msg t "$(printf 'an *item* and __bold__ ![alt](i.png)\n---\n')" | tail -1)"
eq "list markers, task boxes and blockquotes" "$(printf 'one\ntwo\nthree\nquoted')" \
    "$(msg t "$(printf -- '- one\n2. two\n[x] three\n> quoted\n---\n')" | tail -n +3)"
eq "a table keeps its cells, joined" "$(printf 'a, b\nc, d')" "$(msg t "$(printf '| a | b |\n|---|---|\n| c | d |\n---\n')" | tail -n +3)"
eq "a heading marker and an HTML comment go" "Root cause found." "$(msg t "$(printf '## Root cause found.<!-- x -->\n---\n')" | tail -1)"
eq "blank runs collapse and the ends are trimmed" "$(printf 'one\n\ntwo')" "$(msg t "$(printf '\n\none\n\n\n\ntwo\n\n---\n')" | tail -n +3)"
eq "a --- inside a fence doesn't end Part 1" "$(printf -- '---\ninside\nafter')" "$(msg t "$(printf '```\n---\ninside\n```\nafter\n---\nnot this\n')" | tail -n +3)"
eq "a body with no separator is all Part 1" "whole body" "$(msg t "whole body" | tail -1)"

printf '\n\n---\nonly part two\n' | bash "$SM" --title t - >/dev/null 2>&1; eq "an empty Part 1 is refused (exit 1)" 1 $?
printf 'Fix.\nCo-Authored-By: someone\n---\n' | bash "$SM" --title t - >/dev/null 2>&1; eq "a co-author trailer is refused" 1 $?
printf 'See https://claude.ai/x\n---\n' | bash "$SM" --title t - >/dev/null 2>&1; eq "a claude.ai link is refused" 1 $?
printf 'Fix.\n' | bash "$SM" --title "$(printf 'two\nlines')" - >/dev/null 2>&1; eq "a title spanning lines is refused" 1 $?
bash "$SM" --title t /nonexistent/body >/dev/null 2>&1; eq "an unreadable body: exit 2" 2 $?
bash "$SM" - >/dev/null 2>&1 </dev/null; eq "no title: exit 64" 64 $?

echo
echo "squash-message: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
