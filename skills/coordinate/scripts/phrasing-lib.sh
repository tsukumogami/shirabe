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
#   phrase_lines <kind> <file> [list]
#       Prints the 1-based number of every line of <file> that matches a
#       pattern of that kind, one per line, in one grep pass. Exit 0 (none
#       printed is no match); 2 cannot check, as phrase_match.
#   phrasings_check [list]
#       Exit 0 when every row is well formed and its pattern compiles under
#       grep -E; 65 a refused row (stderr names it); 2 the list is unreadable.
#
# [list] is for tests only; every caller in the skill passes none and reads the
# shipped list beside this file.
#
# A row is `<kind><TAB><pattern>`, kind `decision`, `addressed` or `both`, the
# pattern a non-empty extended regular expression. Refused: a carriage return
# (a CRLF file would never match), a back-reference (\1..\9), and a backslash
# before a letter, <, >, ` or ' (\b \w \s \d and the like), which GNU grep
# takes and BSD grep doesn't; escape punctuation such as \. is fine. Comment
# (#) and blank lines are skipped.
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
            if (pat ~ /\\[A-Za-z<>`'"'"']/) { printf "decision phrasings: line %d: an escape BSD grep does not take; spell it out\n", NR > "/dev/stderr"; bad = 1; exit }
            if (want != "" && ($1 == want || $1 == "both")) { print pat; n++ }
        }
        END { if (bad) exit 65; if (want != "" && n == 0) exit 3 }
    ' "$2"
}

phrasings_check() {
    local f="${1:-$PHRASINGS_LIST}" pat rc
    [ -r "$f" ] || { echo "decision phrasings: cannot read $f" >&2; return 2; }
    _phrasings_read "" "$f" >/dev/null || return $?
    # Each pattern must also compile: grep exits 2 on a malformed expression.
    # It is given one line to read, since some greps compile only then.
    while IFS= read -r pat; do
        printf 'x\n' | grep -Eq -e "$pat"
        rc=${PIPESTATUS[1]}
        [ "$rc" -le 1 ] || { echo "decision phrasings: a pattern grep -E can't compile: $pat" >&2; return 65; }
    done < <(awk -F'\t' '!/^#/ && NF >= 2 { sub(/^[^\t]*\t/, ""); print }' "$f")
    return 0
}

# _ascii: stdin to stdout with every byte but tab, newline and printable ASCII
# turned into a space. The patterns are ASCII, so nothing they match is lost,
# line numbers are kept, and no grep's handling of an invalid or non-ASCII
# byte (BSD grep skips such a line) decides what matches.
_ascii() { LC_ALL=C tr -c '\11\12\40-\176' ' '; }

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
    # pattern list: a line matches when any pattern does. The status is grep's
    # own, read from PIPESTATUS: printf may take SIGPIPE when grep quits early
    # on a match, which must not count, and a here-string is no better, since a
    # redirection that can't write its temporary file skips grep and reads as
    # no match.
    printf '%s\n' "$text" | _ascii | LC_ALL=C grep -Eiq -e "$pats"
    rc=${PIPESTATUS[2]}
    [ "$rc" -le 1 ] || return 2
    return "$rc"
}

phrase_lines() {
    local kind="$1" file="$2" f="${3:-$PHRASINGS_LIST}" pats rc
    case "$kind" in
        decision|addressed) ;;
        *) echo "decision phrasings: unknown kind '$kind'" >&2; return 2 ;;
    esac
    [ -r "$f" ] || { echo "decision phrasings: cannot read $f" >&2; return 2; }
    [ -r "$file" ] || { echo "decision phrasings: cannot read $file" >&2; return 2; }
    pats=$(_phrasings_read "$kind" "$f"); rc=$?
    [ "$rc" -eq 0 ] || { [ "$rc" -eq 3 ] && echo "decision phrasings: no $kind patterns" >&2; return 2; }
    # One grep over the whole file, so a report's lines are matched in one
    # pass, never one process per line. grep's own status is the one read.
    # Only printable ASCII reaches grep (see _ascii): the patterns are ASCII,
    # and BSD grep skips a line holding an invalid byte, -a and LC_ALL=C or not.
    _ascii < "$file" | LC_ALL=C grep -aEin -e "$pats" | cut -d: -f1
    rc=${PIPESTATUS[1]}
    [ "$rc" -le 1 ] || return 2
    return 0
}
