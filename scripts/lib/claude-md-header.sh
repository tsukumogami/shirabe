# claude-md-header.sh -- one `## <Name>: <value>` declaration from a CLAUDE.md.
#
# Sourced, never run. Defines three functions:
#
#   claude_md_header <name> <file>
#                       reads <file> from the working tree
#   claude_md_header_named <name> <file>
#                       reads <file> from the working tree, like
#                       claude_md_header, and prints the heading's name as the
#                       file writes it, a tab, then the value, so a caller that
#                       needs the name in an exact case can check it
#   claude_md_header_at <commit> <name> [<path>]
#                       reads <path> (default CLAUDE.md) as it stands at
#                       <commit>, so a unit's own diff can't change what it
#                       reads; the caller is inside the repository
#
# Each prints the declaration's value, trimmed (claude_md_header_named puts
# the name and a tab before it), and returns:
#
#   0  the header is declared once; its value is printed (it may be empty)
#   1  the file has no such header, or the file doesn't exist (at <commit>)
#   2  the header is declared more than once, or the file can't be read; a
#      line on standard error says which, and nothing is printed
#
# The scan is fence-aware: a line inside a ``` or ~~~ fenced block is never a
# declaration, so a CLAUDE.md that shows an example header in a code block
# doesn't declare it. A fence closes on a line of the same character at least
# as long as the one that opened it, as CommonMark has it. The heading is
# matched case-insensitively on its name and may be indented up to three
# spaces; the value is everything after the first colon. Two declarations are
# refused rather than resolved, since either choice would let a later edit
# hide behind an earlier line.
#
# Callers: skills/work-on/scripts/fix-kind.sh reads `## Fix Labels:` with it,
# and skills/work-on/scripts/clean-build-output.sh `## Build Output Cleanup:`
# through claude_md_header_named.
#
# Written for the bash 3.2 floor.

# _claude_md_header_scan <name> [named]: reads the file on stdin. With a second
# argument it prints the name as written, a tab, then the value.
_claude_md_header_scan() {
    awk -v want="$1" -v named="${2-}" '
        BEGIN { want = tolower(want); n = 0; fence = "" }
        {
            line = $0
            sub(/\r$/, "", line)
            stripped = line
            for (k = 0; k < 3 && substr(stripped, 1, 1) == " "; k++) stripped = substr(stripped, 2)
            if (fence != "") {
                if (substr(stripped, 1, length(fence)) == fence) {
                    rest = substr(stripped, length(fence) + 1)
                    c = substr(fence, 1, 1)
                    while (substr(rest, 1, 1) == c) rest = substr(rest, 2)
                    if (rest ~ /^[ \t]*$/) fence = ""
                }
                next
            }
            if (stripped ~ /^(```|~~~)/) {
                c = substr(stripped, 1, 1)
                f = ""
                while (substr(stripped, length(f) + 1, 1) == c) f = f c
                fence = f
                next
            }
            if (substr(stripped, 1, 3) != "## ") next
            head = substr(stripped, 4)
            colon = index(head, ":")
            if (colon == 0) next
            name = substr(head, 1, colon - 1)
            sub(/[ \t]+$/, "", name)
            if (tolower(name) != want) next
            value = substr(head, colon + 1)
            sub(/^[ \t]+/, "", value)
            sub(/[ \t]+$/, "", value)
            n++
            found = (named != "") ? name "\t" value : value
        }
        END {
            if (n == 0) exit 1
            if (n > 1) exit 2
            print found
        }
    '
}

claude_md_header() {
    _claude_md_header_file "$1" "$2" ""
}

claude_md_header_named() {
    _claude_md_header_file "$1" "$2" named
}

# _claude_md_header_file <name> <file> <named>: the working-tree read behind
# claude_md_header and claude_md_header_named.
_claude_md_header_file() {
    local name="$1" file="$2" named="$3" out rc
    [ -e "$file" ] || return 1
    if [ ! -r "$file" ]; then
        echo "claude-md-header: $file can't be read" >&2
        return 2
    fi
    out=$(_claude_md_header_scan "$name" ${named:+"$named"} < "$file")
    rc=$?
    case "$rc" in
        0) printf '%s\n' "$out"; return 0 ;;
        1) return 1 ;;
        *) echo "claude-md-header: $file declares ## $name: more than once" >&2; return 2 ;;
    esac
}

claude_md_header_at() {
    local commit="$1" name="$2" path="${3:-CLAUDE.md}" out rc
    git cat-file -e "$commit^{commit}" 2>/dev/null || {
        echo "claude-md-header: [$commit] names no commit" >&2
        return 2
    }
    git cat-file -e "$commit:$path" 2>/dev/null || return 1
    out=$(git show "$commit:$path" 2>/dev/null | _claude_md_header_scan "$name")
    rc=$?
    case "$rc" in
        0) printf '%s\n' "$out"; return 0 ;;
        1) return 1 ;;
        *) echo "claude-md-header: $path at $commit declares ## $name: more than once" >&2; return 2 ;;
    esac
}
