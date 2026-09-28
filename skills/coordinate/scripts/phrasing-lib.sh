# phrasing-lib.sh -- the reader of /coordinate's decision-phrasing list,
# skills/coordinate/references/decision-phrasings.tsv. Sourced, never run:
# `. "$HERE/phrasing-lib.sh"`. It reads one file and makes no other read or
# write, so any script that shows text to a person can use it without pulling
# in the record library.
#
# The list is a backstop behind a structural rule (a decision shown to a person
# comes only from an escalated decision entry), so every failure to read it is
# a failed check, never a quiet "no match".
#
#   phrase_match <kind> <text> [list]
#       Exit 0 when the text matches a pattern of that kind, case-insensitively
#       with grep -E; 1 no match; 2 cannot check: an unknown kind, a list that
#       is unreadable or has a refused row, or a kind with no patterns. <kind>
#       is `decision` or `addressed`; a row of kind `both` counts for each.
#   phrasings_check [list]
#       Exit 0 when every row is well formed; 65 a refused row (stderr names the
#       line); 2 the list is unreadable.
#
# [list] is for tests only; every caller in the skill passes none and reads the
# shipped list beside this file.
#
# A row is `<kind><TAB><pattern>`, kind `decision`, `addressed` or `both`, the
# pattern a non-empty extended regular expression. Refused: a carriage return
# (a CRLF file would never match), a back-reference (\1..\9), and \b \B \< \>
# \w \W \s \S, which GNU grep takes and BSD grep doesn't. Comment (#) and blank
# lines are skipped.
#
# Requires: bash 3.2+, awk, grep.

PHRASINGS_LIST="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../references/decision-phrasings.tsv"

# _phrasings_read <want> <list>: one pass over the list. Checks every row and,
# when <want> is a kind, prints that kind's patterns (its own rows and `both`
# rows). Exit 0 fine; 65 a refused row; 3 <want> is a kind with no patterns.
_phrasings_read() {
    awk -F'\t' -v want="$1" '
        /^#/ || /^[[:space:]]*$/ { next }
        {
            if (index($0, "\r") > 0) { printf "decision phrasings: line %d: a carriage return\n", NR > "/dev/stderr"; bad = 1; exit }
            if (NF < 2 || $2 == "") { printf "decision phrasings: line %d: not <kind><TAB><pattern>\n", NR > "/dev/stderr"; bad = 1; exit }
            if ($1 != "decision" && $1 != "addressed" && $1 != "both") { printf "decision phrasings: line %d: unknown kind %s\n", NR, $1 > "/dev/stderr"; bad = 1; exit }
            pat = $0; sub(/^[^\t]*\t/, "", pat)
            if (pat ~ /\\[1-9]/) { printf "decision phrasings: line %d: a back-reference\n", NR > "/dev/stderr"; bad = 1; exit }
            if (pat ~ /\\[bB<>wWsS]/) { printf "decision phrasings: line %d: an escape BSD grep does not take; spell it out\n", NR > "/dev/stderr"; bad = 1; exit }
            if (want != "" && ($1 == want || $1 == "both")) { print pat; n++ }
        }
        END { if (bad) exit 65; if (want != "" && n == 0) exit 3 }
    ' "$2"
}

phrasings_check() {
    local f="${1:-$PHRASINGS_LIST}"
    [ -r "$f" ] || { echo "decision phrasings: cannot read $f" >&2; return 2; }
    _phrasings_read "" "$f" >/dev/null
}

phrase_match() {
    local kind="$1" text="$2" f="${3:-$PHRASINGS_LIST}" pats rc
    case "$kind" in
        decision|addressed) ;;
        *) echo "decision phrasings: unknown kind '$kind'" >&2; return 2 ;;
    esac
    [ -r "$f" ] || { echo "decision phrasings: cannot read $f" >&2; return 2; }
    pats=$(_phrasings_read "$kind" "$f"); rc=$?
    [ "$rc" -eq 0 ] || { [ "$rc" -eq 3 ] && echo "decision phrasings: no $kind patterns" >&2; return 2; }
    # One -e argument holding newline-separated patterns is a POSIX grep
    # pattern list: a line matches when any pattern does.
    printf '%s\n' "$text" | grep -Eiq -e "$pats"
    rc=$?
    [ "$rc" -le 1 ] || return 2
    return "$rc"
}
