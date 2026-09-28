#!/usr/bin/env bash
# decision-phrasings_test.sh -- the decision-phrasing list and its matcher in
# record-common.sh (lib_phrasings_check, lib_phrase_match).
#
# Covers: the shipped list passes the check; every refused fixture matches the
# `decision` kind; no accepted fixture matches either kind; every addressed
# fixture matches the `addressed` kind; matching ignores case; a list with a
# back-reference, an unknown kind, or a row with no pattern is refused (65),
# and a refused or missing list makes the matcher return 2, never "no match".
#
# Usage: bash skills/coordinate/scripts/decision-phrasings_test.sh
set -uo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/testdata/test-lib.sh"
PROG=decision-phrasings_test
SESSION=
. "$HERE/record-common.sh"
FIX="$HERE/testdata/decision-phrasings"

echo "== the shipped list =="
lib_phrasings_check; eq "the shipped list passes the check" 0 "$?"

each() { # each <fixture> <kind> <want-status>: every line of the fixture
    local line st all=ok
    while IFS= read -r line; do
        [ -n "$line" ] || continue
        lib_phrase_match "$2" "$line"; st=$?
        [ "$st" = "$3" ] || { all="[$line] gave $st"; break; }
    done < "$FIX/$1"
    eq "$1 against $2 gives $3" ok "$all"
}
[ "$(grep -c . "$FIX/refused.txt")" -ge 3 ] && ok "at least three refused fixtures" || bad "at least three refused fixtures"
[ "$(grep -c . "$FIX/accepted.txt")" -ge 3 ] && ok "at least three accepted fixtures" || bad "at least three accepted fixtures"
[ "$(grep -c . "$FIX/addressed.txt")" -ge 3 ] && ok "at least three addressed fixtures" || bad "at least three addressed fixtures"
each refused.txt decision 0
each accepted.txt decision 1
each accepted.txt addressed 1
each addressed.txt addressed 0
lib_phrase_match decision "DECIDE WHETHER TO SHIP"; eq "matching ignores case" 0 "$?"
lib_phrase_match decision "we decided to ship"; eq "a word that only contains a phrase doesn't match" 1 "$?"

echo "== refused lists =="
list() { printf '%s\n' "$@" > "$T/list.tsv"; }
list 'decision	(a)\1'
lib_phrasings_check "$T/list.tsv" 2>/dev/null; eq "a back-reference is refused" 65 "$?"
list 'question	decide'
lib_phrasings_check "$T/list.tsv" 2>/dev/null; eq "an unknown kind is refused" 65 "$?"
list 'decision'
lib_phrasings_check "$T/list.tsv" 2>/dev/null; eq "a row with no pattern is refused" 65 "$?"
list '# a comment' '' 'decision	please decide'
lib_phrasings_check "$T/list.tsv"; eq "comments and blank lines are skipped" 0 "$?"

list 'decision	(a)\1'
PHRASINGS_FILE="$T/list.tsv" lib_phrase_match decision "aa" 2>/dev/null
eq "a refused list makes the matcher fail, not miss" 2 "$?"
PHRASINGS_FILE="$T/missing.tsv" lib_phrase_match decision "please decide" 2>/dev/null
eq "a missing list makes the matcher fail, not miss" 2 "$?"

done_tests decision-phrasings
