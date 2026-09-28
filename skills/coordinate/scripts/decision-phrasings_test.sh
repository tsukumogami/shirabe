#!/usr/bin/env bash
# decision-phrasings_test.sh -- the decision-phrasing list and its reader,
# phrasing-lib.sh (phrase_match, phrasings_check).
#
# Covers: the shipped list passes the check; every line of decision.txt
# matches the decision kind; every line of addressed.txt matches the addressed
# kind; no line of no-match.txt matches either; every row of the shipped list
# is matched by at least one fixture line, so a row that stops matching fails
# here; matching ignores case; the two kinds answer separately (the niwa#330
# line "Please decide whether to ship ..." is both, a bare "decide whether to
# ship" only a decision). Refused lists (65 from the check, 2 from the
# matcher, never "no match"): a back-reference, each non-portable escape, an
# unknown kind, a row with no pattern, a carriage return. The matcher also
# returns 2 for an unknown kind asked of it, an unreadable list, and a kind
# with no patterns.
#
# Usage: bash skills/coordinate/scripts/decision-phrasings_test.sh
set -uo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/testdata/test-lib.sh"
. "$HERE/phrasing-lib.sh"
FIX="$HERE/testdata/decision-phrasings"

echo "== the shipped list =="
phrasings_check; eq "the shipped list passes the check" 0 "$?"

each() { # each <fixture> <kind> <want-status>: every line of the fixture
    local line st all=ok
    while IFS= read -r line; do
        [ -n "$line" ] || continue
        phrase_match "$2" "$line"; st=$?
        [ "$st" = "$3" ] || { all="[$line] gave $st"; break; }
    done < "$FIX/$1"
    eq "$1 against $2 gives $3" ok "$all"
}
for f in decision.txt addressed.txt no-match.txt; do
    [ "$(grep -c . "$FIX/$f")" -ge 3 ] && ok "at least three lines in $f" || bad "at least three lines in $f"
done
each decision.txt decision 0
each addressed.txt addressed 0
each no-match.txt decision 1
each no-match.txt addressed 1

# Every row is exercised: for each row, some fixture line of its kind matches
# that row alone.
uncovered=
while IFS=$'\t' read -r kind pat; do
    case "$kind" in ''|'#'*) continue ;; esac
    case "$kind" in
        decision) fx="$FIX/decision.txt" ;;
        addressed) fx="$FIX/addressed.txt" ;;
        both) fx="$FIX/decision.txt $FIX/addressed.txt" ;;
    esac
    # shellcheck disable=SC2086
    cat $fx | grep -Eiq -e "$pat" || uncovered="$uncovered [$pat]"
done < "$PHRASINGS_LIST"
eq "every row is matched by a fixture line of its kind" "" "$uncovered"

phrase_match decision "DECIDE WHETHER TO SHIP"; eq "matching ignores case" 0 "$?"
phrase_match decision "we decided to ship"; eq "a word that only contains a phrase doesn't match" 1 "$?"

echo "== the two kinds, separately =="
both() { # both <text> <want-decision> <want-addressed>
    local d a
    phrase_match decision "$1"; d=$?
    phrase_match addressed "$1"; a=$?
    eq "[$1] decision/addressed" "$2/$3" "$d/$a"
}
both "Please decide whether to ship with the mixed result." 0 0
both "decide whether to ship" 0 1
both "the human should look at the board" 1 0
both "the human-readable summary" 1 1
both "report at its next checkpoint" 1 1

echo "== refused lists and failed checks =="
list() { printf '%s\n' "$@" > "$T/list.tsv"; }
refused() { # refused <label> <row>
    list "$2"
    phrasings_check "$T/list.tsv" 2>/dev/null; eq "$1: the check refuses it" 65 "$?"
    phrase_match decision "please decide" "$T/list.tsv" 2>/dev/null; eq "$1: the matcher can't check" 2 "$?"
}
refused "a back-reference" 'decision	(a)\1'
refused "a \\b word edge" 'decision	\bdecide\b'
refused "a \\< word edge" 'decision	\<decide\>'
refused "a \\w class" 'decision	decide\w+'
refused "a \\s class" 'decision	please\sdecide'
refused "a \\d class" 'decision	option \d'
list 'decision	please decide\.'
phrasings_check "$T/list.tsv"; eq "an escaped punctuation mark is fine" 0 "$?"
long=
i=0
while [ "$i" -lt 3000 ]; do long="$long please decide whether to ship"; i=$((i + 1)); done
( set -o pipefail; phrase_match decision "$long" ); eq "a long matching text under pipefail still matches" 0 "$?"
refused "an unknown kind" 'question	decide'
refused "a row with no pattern" 'decision'
refused "a carriage return" $'decision\tplease decide\r'
refused "a pattern grep -E can't compile" 'decision	(please decide'
list '# a comment' '' 'both	please decide'
phrasings_check "$T/list.tsv"; eq "comments and blank lines are skipped" 0 "$?"
phrase_match addressed "please decide" "$T/list.tsv"; eq "a both row counts for addressed" 0 "$?"
list 'decision	please decide'
phrase_match addressed "please decide" "$T/list.tsv" 2>/dev/null; eq "a kind with no patterns can't be checked" 2 "$?"
phrase_match decision "please decide" "$T/missing.tsv" 2>/dev/null; eq "an unreadable list can't be checked" 2 "$?"
phrase_match question "please decide" 2>/dev/null; eq "an unknown kind asked of the matcher can't be checked" 2 "$?"

# phrase_lines: the same list, every line of a file in one pass.
printf 'Nothing here.\nPlease decide whether to ship.\nwaiting on the release decision from the vendor\nyour call on the pin\n' > "$T/lines.txt"
eq "phrase_lines numbers the decision lines, a both row among them" "2 4" "$(phrase_lines decision "$T/lines.txt" | tr '\n' ' ' | sed 's/ $//')"
eq "phrase_lines numbers the addressed lines" "2 4" "$(phrase_lines addressed "$T/lines.txt" | tr '\n' ' ' | sed 's/ $//')"
while IFS= read -r l; do phrase_match decision "$l" && printf '+' || printf '.'; done < "$T/lines.txt" > "$T/one"
awk 'NR == FNR { h[$1] = 1; next } { printf (h[FNR] ? "+" : ".") }' <(phrase_lines decision "$T/lines.txt") "$T/lines.txt" > "$T/batch"
eq "phrase_lines agrees with phrase_match line by line" "$(cat "$T/one")" "$(cat "$T/batch")"
# The readers match bytes (LC_ALL=C) so an invalid byte never hides a line;
# that holds only while every pattern is ASCII.
eq "every phrasing pattern is ASCII" "0" "$(LC_ALL=C awk '/[^\t -~]/' "$HERE/../references/decision-phrasings.tsv" | wc -l | tr -d ' ')"
printf 'a stray \377 byte, then please decide whether to ship\n' > "$T/binary.txt"
eq "phrase_lines reads a line holding an invalid byte as text" "1" "$(phrase_lines decision "$T/binary.txt")"
printf 'nothing\n' > "$T/none.txt"
phrase_lines decision "$T/none.txt" > "$T/out"; eq "no match prints nothing and exits 0" "0 0" "$? $(wc -c < "$T/out" | tr -d ' ')"
phrase_lines decision "$T/lines.txt" "$T/missing.tsv" >/dev/null 2>&1; eq "phrase_lines on an unreadable list can't check" 2 "$?"
phrase_lines decision "$T/absent.txt" >/dev/null 2>&1; eq "phrase_lines on an unreadable file can't check" 2 "$?"
phrase_lines question "$T/lines.txt" >/dev/null 2>&1; eq "phrase_lines on an unknown kind can't check" 2 "$?"

done_tests decision-phrasings
