# test-classify.sh -- the test files a unit's committed diff touched, each
# labelled by the shape of its change.
#
# Sourced, never run. Defines one function:
#
#   test_classify <base> <head> <rules-file>
#
# run from inside the repository. It diffs <base> to <head> (commits, so only
# committed changes count), keeps the paths the `test` class of <rules-file>
# matches, and prints one tab-separated row per path:
#
#   <label>\t<path>\t<digest>
#
# <label> is
#   added      the file is new, or its diff removes no line
#   edited     the file is deleted, its diff removes at least one line, it is
#              a binary file that changed, or its type changed
#   unchanged  a rename (or copy) that changes no line
# <path> is the path at <head> (the old path for a deleted file), and <digest>
# is its blob id at <head>, or `deleted`.
#
# A rename is judged on both of its paths: when either is in the class the row
# is printed, so a test moved out of the class with edits is still `edited`.
#
# <rules-file> is review-level-rules.tsv's format (class <name> <glob>); only
# its `test` class lines are read. Callers pass the copy `review-level.sh init`
# stored in the run's context (`review_level_rules.tsv`), so the class is the
# one at the run's base and a unit can't narrow it. Globs are bash `case`
# patterns on the repository-relative path, `*` matching `/` too, and a
# leading `**/` also matching no directory, as review-level.sh reads them.
#
# Returns 0 with the rows printed (none when no test file changed), or 2 when
# a commit doesn't resolve, the diff fails, or the rules file has no `test`
# class; a line on standard error says which and nothing is printed.
#
# And one more, for the readers that judge a unit's test changes:
#
#   test_classify_unit <base> <head> <rules-file> [<red-record-file>]
#
# test_classify's rows, with a fix's reproducing tests and harness files also
# labelled `edited` when their blob id at <head> differs from the one the red
# recorded (red-first.sh's `red_first.json`, `.red.tests` and `.red.harness`):
# a reproducing test changed after its red is an edit even when it only gained
# lines, and one outside the `test` class is added as a row of its own. With no
# record file, or an empty one, the rows are test_classify's. Returns what
# test_classify returns, or 2 when the record doesn't parse.
#
# Callers: skills/work-on/scripts/red-first.sh, for the tests a red copies onto
# the base; skills/work-on/scripts/test-change.sh (the hold),
# skills/work-on/scripts/review-level.sh (the `tests_edited` floor),
# scripts/review-packet.sh (the packet's test section) and
# skills/work-on/scripts/panel-scope.sh (the judgments a round needs) through
# test_classify_unit, so all four agree on which test was edited.
#
# Written for the bash 3.2 floor: no associative arrays, no mapfile.

_tc_glob_match() {
    # shellcheck disable=SC2254
    case "$1" in $2) return 0 ;; esac
    case "$2" in
        '**/'*)
            # shellcheck disable=SC2254
            case "$1" in ${2#\*\*/}) return 0 ;; esac
            ;;
    esac
    return 1
}

# _tc_is_test <path> <globs, newline-separated>
_tc_is_test() {
    local g
    while IFS= read -r g; do
        [ -n "$g" ] || continue
        _tc_glob_match "$1" "$g" && return 0
    done <<EOF
$2
EOF
    return 1
}

test_classify() {
    local base="$1" head="$2" rules="$3" globs tab
    tab=$(printf '\t')
    git cat-file -e "$base^{commit}" 2>/dev/null || { echo "test-classify: base [$base] names no commit" >&2; return 2; }
    git cat-file -e "$head^{commit}" 2>/dev/null || { echo "test-classify: head [$head] names no commit" >&2; return 2; }
    [ -f "$rules" ] || { echo "test-classify: rules file [$rules] is not a file" >&2; return 2; }
    globs=$(awk -F '\t' '$1 == "class" && $2 == "test" && $3 != "" { print $3 }' "$rules")
    [ -n "$globs" ] || { echo "test-classify: the rules file has no test class" >&2; return 2; }

    # Both diffs are read with -z, which keeps any byte a path can hold, into
    # indexed arrays; bash's read -d '' splits on the NULs.
    local w st p1 p2 rec a r p i n
    w=$(mktemp -d "${TMPDIR:-/tmp}/test-classify.XXXXXX") || { echo "test-classify: could not create a temporary directory" >&2; return 2; }
    git diff --name-status -z -M "$base" "$head" > "$w/status" 2>/dev/null \
        || { rm -rf "$w"; echo "test-classify: git diff --name-status failed" >&2; return 2; }
    git diff --numstat -z -M "$base" "$head" > "$w/numstat" 2>/dev/null \
        || { rm -rf "$w"; echo "test-classify: git diff --numstat failed" >&2; return 2; }

    # numstat: "<added>\t<removed>\t<path>\0", or for a rename or copy
    # "<added>\t<removed>\t\0<old>\0<new>\0". Kept by the new path.
    local -a ns_path=() ns_added=() ns_removed=()
    n=0
    while IFS= read -r -d '' rec; do
        a=${rec%%"$tab"*}
        rec=${rec#*"$tab"}
        r=${rec%%"$tab"*}
        p=${rec#*"$tab"}
        if [ -z "$p" ]; then
            IFS= read -r -d '' p || break
            IFS= read -r -d '' p || break
        fi
        ns_path[$n]=$p
        ns_added[$n]=$a
        ns_removed[$n]=$r
        n=$((n + 1))
    done < "$w/numstat"

    # name-status: "<status>\0<path>\0", or for a rename or copy
    # "<status>\0<old>\0<new>\0".
    local -a st_status=() st_old=() st_new=()
    local m=0
    while IFS= read -r -d '' st; do
        IFS= read -r -d '' p1 || break
        p2=""
        case "$st" in
            R*|C*) IFS= read -r -d '' p2 || break ;;
        esac
        st_status[$m]=$st
        st_old[$m]=$p1
        st_new[$m]=$p2
        m=$((m + 1))
    done < "$w/status"
    rm -rf "$w"

    local path added removed label digest j
    i=0
    while [ "$i" -lt "$m" ]; do
        st=${st_status[$i]}
        p1=${st_old[$i]}
        p2=${st_new[$i]}
        i=$((i + 1))
        path="$p1"
        [ -z "$p2" ] || path="$p2"
        if ! _tc_is_test "$path" "$globs"; then
            [ -n "$p2" ] && _tc_is_test "$p1" "$globs" || continue
        fi
        added=0
        removed=0
        j=0
        while [ "$j" -lt "$n" ]; do
            if [ "${ns_path[$j]}" = "$path" ]; then
                added=${ns_added[$j]}
                removed=${ns_removed[$j]}
                break
            fi
            j=$((j + 1))
        done
        case "$st" in
            D*) label=edited ;;
            A*) label=added ;;
            T*) label=edited ;;
            *)
                if [ "$added" = "-" ] || [ "$removed" = "-" ]; then
                    label=edited
                elif [ "$removed" -gt 0 ] 2>/dev/null; then
                    label=edited
                elif [ "$added" -gt 0 ] 2>/dev/null; then
                    label=added
                else
                    label=unchanged
                fi
                ;;
        esac
        case "$st" in
            D*) digest=deleted ;;
            *) digest=$(git rev-parse -q --verify "$head:$path" 2>/dev/null) || digest=deleted ;;
        esac
        printf '%s\t%s\t%s\n' "$label" "$path" "$digest"
    done
    return 0
}

test_classify_unit() {
    local base="$1" head="$2" rules="$3" record="${4:-}" w tab p b cur rc
    tab=$(printf '\t')
    w=$(mktemp -d "${TMPDIR:-/tmp}/test-classify.XXXXXX") || { echo "test-classify: could not create a temporary directory" >&2; return 2; }
    test_classify "$base" "$head" "$rules" > "$w/rows"
    rc=$?
    if [ "$rc" -ne 0 ]; then
        rm -rf "$w"
        return "$rc"
    fi
    if [ -n "$record" ] && [ -s "$record" ]; then
        if ! jq -r 'if type != "object" then error("not an object") else . end
                    | (.red // {}) | ((.tests // []) + (.harness // []))[] | "\(.path)\t\(.blob)"' \
                "$record" > "$w/red" 2>/dev/null; then
            rm -rf "$w"
            echo "test-classify: the red record does not parse" >&2
            return 2
        fi
        while IFS="$tab" read -r p b; do
            [ -n "$p" ] || continue
            cur=$(git rev-parse -q --verify "$head:$p" 2>/dev/null) || cur=deleted
            [ "$cur" != "$b" ] || continue
            if awk -F '\t' -v p="$p" '$2 == p { f = 1 } END { exit !f }' "$w/rows"; then
                awk -F '\t' -v OFS='\t' -v p="$p" '$2 == p { $1 = "edited" } { print }' "$w/rows" > "$w/rows.next"
                mv "$w/rows.next" "$w/rows"
            else
                printf 'edited\t%s\t%s\n' "$p" "$cur" >> "$w/rows"
            fi
        done < "$w/red"
    fi
    cat "$w/rows"
    rm -rf "$w"
    return 0
}
