#!/usr/bin/env bash
# panel-evidence_test.sh -- panel-evidence.sh reads a body's Review panel
# table: ok with its seats, absent with none, and malformed naming the first
# rule a table breaks.
#
# Covers: a well-formed table (backticked cells, header case, a failing seat
# still ok); no separator, no heading, a heading only in Part 1 or inside a
# fence (absent); each malformed reason in its order; the first table only;
# stdin; an unreadable file and usage.
#
# Usage: bash skills/coordinate/scripts/panel-evidence_test.sh
set -uo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
command -v jq >/dev/null 2>&1 || { echo "SKIP: jq not on PATH"; exit 0; }
T=$(mktemp -d "${TMPDIR:-/tmp}/panel-evidence-test.XXXXXX")
trap 'rm -rf "$T"' EXIT
PE="$HERE/panel-evidence.sh"
H=0123456789abcdef0123456789abcdef01234567
G=89abcdef0123456789abcdef0123456789abcdef
PASS=0 FAIL=0
ok()  { PASS=$((PASS + 1)); printf 'ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); printf 'FAIL %s\n     %s\n' "$1" "${2-}"; }
eq() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "want [$2], got [$3]"; fi; }

# body [rows...]: Part 1, the separator, the heading and a table of the rows.
body() {
    printf 'Part one.\n\n---\n\n## Review panel\n\n| Seat | Model | Run | Verdict | Reviewed head |\n|---|---|---|---|---|\n'
    local r
    for r in "$@"; do printf '%s\n' "$r"; done
    printf '\nAfter the table.\n'
}
ROW1="| architect | sonnet | comment-1 | pass | $H |"
ROW2="| maintainer | sonnet | comment-2 | pass | $H |"
ROW3="| pragmatic | sonnet | comment-3 | pass | $H |"
parse() { printf '%s' "$1" | bash "$PE" -; }
field() { printf '%s' "$1" | jq -r "$2"; }

echo "== ok =="
OUT=$(parse "$(body "$ROW1" "$ROW2" "$ROW3")")
eq "three seats parse ok" ok "$(field "$OUT" .status)"
eq "  ... with the reviewed head" "$H" "$(field "$OUT" .reviewed_head)"
eq "  ... three seats, three passes" "3 3" "$(field "$OUT" '"\(.count) \(.passes)"')"
eq "  ... seats in order" "architect maintainer pragmatic" "$(field "$OUT" '[.seats[].seat] | join(" ")')"
OUT=$(parse "$(body "| architect | sonnet | \`agent-a1\` | pass | \`$H\` |" "$ROW2")")
eq "backticked cells are read without them" "agent-a1 $H" "$(field "$OUT" '"\(.seats[0].run) \(.reviewed_head)"')"
OUT=$(parse "$(body "$ROW1" "$ROW2" "${ROW3/pass/fail}")")
eq "a failing seat is still a well-formed table" "ok 2" "$(field "$OUT" '"\(.status) \(.passes)"')"
OUT=$(parse "$(body "$ROW1" | sed 's/| Seat | Model | Run | Verdict | Reviewed head |/| SEAT | model | RUN | Verdict | Reviewed Head |/')")
eq "header cells are compared without case" ok "$(field "$OUT" .status)"
OUT=$(parse "$(body "$ROW1"; printf '\n## Review panel\n\n| Seat | Model | Run | Verdict | Reviewed head |\n|---|---|---|---|---|\n| x | y | comment-9 | bogus | %s |\n' "$H")")
eq "only the first table is read" ok "$(field "$OUT" .status)"

echo "== absent =="
eq "no separator: absent" absent "$(field "$(parse "Just a body.")" .status)"
eq "no heading in Part 2: absent" absent "$(field "$(parse "$(printf 'Part one.\n\n---\n\nNothing.\n')")" .status)"
eq "a heading only in Part 1: absent" absent "$(field "$(parse "$(printf '## Review panel\n\n| Seat | Model | Run | Verdict | Reviewed head |\n|---|---|---|---|---|\n%s\n\n---\n\nPart two.\n' "$ROW1")")" .status)"
eq "a heading inside a fence: absent" absent "$(field "$(parse "$(printf 'Part one.\n\n---\n\n```\n## Review panel\n```\n')")" .status)"
eq "a separator inside a fence doesn't count" absent "$(field "$(parse "$(printf 'Part one.\n```\n---\n```\n## Review panel\n\n| Seat | Model | Run | Verdict | Reviewed head |\n|---|---|---|---|---|\n%s\n' "$ROW1")")" .status)"
eq "a deeper heading isn't the evidence" absent "$(field "$(parse "$(printf 'Part one.\n\n---\n\n### Review panel\n')")" .status)"

echo "== malformed, by rule =="
reason() { field "$(parse "$1")" '"\(.status) \(.reason) \(.row)"'; }
eq "prose under the heading: no-table" "malformed no-table 0" "$(reason "$(printf 'Part one.\n\n---\n\n## Review panel\n\nThree seats passed.\n')")"
eq "a heading and nothing else: no-table" "malformed no-table 0" "$(reason "$(printf 'Part one.\n\n---\n\n## Review panel\n')")"
eq "other columns: header" "malformed header 0" "$(reason "$(body "$ROW1" | sed 's/| Reviewed head |/| Head |/')")"
eq "no separator row: header" "malformed header 0" "$(reason "$(body "$ROW1" | grep -v '^|---')")"
eq "no seat rows: no-rows" "malformed no-rows 0" "$(reason "$(body)")"
eq "a control character: control, row 2" "malformed control 2" "$(reason "$(body "$ROW1" "$(printf '| maintainer | sonnet | comment-2 | pass\001 | %s |' "$H")")")"
eq "a missing cell: cells" "malformed cells 1" "$(reason "$(body "| architect | sonnet | comment-1 | pass |")")"
eq "an empty Run: cells" "malformed cells 1" "$(reason "$(body "| architect | sonnet |  | pass | $H |")")"
eq "a Run too short: run" "malformed run 1" "$(reason "$(body "| architect | sonnet | a1 | pass | $H |")")"
eq "a Run with a space: run" "malformed run 1" "$(reason "$(body "| architect | sonnet | the same agent | pass | $H |")")"
eq "a verdict word outside pass and fail: verdict" "malformed verdict 1" "$(reason "$(body "| architect | sonnet | comment-1 | approve | $H |")")"
eq "a short sha: head" "malformed head 1" "$(reason "$(body "| architect | sonnet | comment-1 | pass | ${H%0*} |")")"
eq "an uppercase sha: head" "malformed head 1" "$(reason "$(body "| architect | sonnet | comment-1 | pass | ABCDEF0123456789ABCDEF0123456789ABCDEF01 |")")"
eq "row rules run before table rules" "malformed verdict 2" "$(reason "$(body "$ROW1" "| architect | sonnet | comment-1 | ok | $H |")")"
eq "one Seat twice, without case: seat-repeated" "malformed seat-repeated 0" "$(reason "$(body "$ROW1" "| Architect | sonnet | comment-2 | pass | $H |" "$ROW3")")"
eq "one Run twice: run-repeated (the niwa#346 case)" "malformed run-repeated 0" "$(reason "$(body "$ROW1" "| maintainer | sonnet | comment-1 | pass | $H |" "$ROW3")")"
eq "two reviewed heads: heads-differ" "malformed heads-differ 0" "$(reason "$(body "$ROW1" "$ROW2" "| pragmatic | sonnet | comment-3 | pass | $G |")")"

echo "== input =="
body "$ROW1" > "$T/body"
eq "a file argument is read" ok "$(field "$(bash "$PE" "$T/body")" .status)"
bash "$PE" "$T/missing" >/dev/null 2>&1; eq "an unreadable file: exit 2" 2 $?
bash "$PE" >/dev/null 2>&1; eq "no argument: exit 64" 64 $?

echo
echo "panel-evidence: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
