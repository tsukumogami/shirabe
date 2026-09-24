#!/usr/bin/env bash
#
# resolve-split-mode.sh - Resolve a PLAN's execution mode from its split verdict
#
# /plan settles a PLAN's mode in two questions. The first -- does the work
# split, and on which branch -- is a judgment made in phase 3 step 3.6 and
# recorded in `split_branch` / `split_rationale`. This script answers the
# second question deterministically, so the one decision the scope-then-execute
# chain turns on is table-tested rather than left to model judgment:
#
#   --split no   -> single-pr, recorded with split_mode_source none, regardless
#                   of intent, flags, or headers.
#   --split yes  -> the first level that answers wins:
#                     1. an explicit flag: --coordinated gives coordinated,
#                        --no-coordinated gives multi-pr        (source: flag)
#                     2. intent: continue gives coordinated, stop gives
#                        multi-pr; none gives no answer here    (source: intent)
#                     3. a coordinated-by-default CLAUDE.md header
#                        gives coordinated                      (source: header)
#                     4. multi-pr                               (source: default)
#
# The precedence and the header values are defined in
# references/coordination-strategy.md ("Mode Resolution" and
# "Coordinated-by-default header values"). The header values are mirrored in
# the constants below; the two must change together, and
# resolve-split-mode_test.sh fails when they differ.
#
# Usage:
#   resolve-split-mode.sh --split <yes|no>
#                         [--intent <continue|stop|none>]
#                         [--coordinated | --no-coordinated]
#                         [--claude-md <path>]
#
#   Each option also accepts the `--opt=value` form. Without --claude-md no
#   header is consulted, so level 3 gives no answer.
#
# Output (stable interface; /scope's check-plan-mode.sh re-runs this script
# over a PLAN's split record and compares):
#   Exactly two lines on stdout, then exit 0:
#     execution_mode=<single-pr|multi-pr|coordinated>
#     split_mode_source=<none|flag|intent|header|default>
#   `--split no` always prints single-pr / none; `--split yes` never prints
#   source none.
#
# Rejections (exit 2, nothing on stdout, one stderr line naming the argument):
#   a missing or invalid --split; an --intent outside continue|stop|none; any
#   option given twice; --coordinated together with --no-coordinated; a
#   --claude-md path that does not exist; an unknown argument; an option
#   missing its value.
#
# The script reads only its arguments and the named CLAUDE.md. It makes no
# network or gh call, and runs under bash 3.2.

set -euo pipefail

# Coordinated-by-default header values. Mirror of the table in
# references/coordination-strategy.md; space-separated, matched exactly and
# case-sensitively after trimming. An empty list means no value of that header
# turns coordinated mode on.
COORDINATED_VALUES_PR_GROUPING_POLICY="coordinated"
COORDINATED_VALUES_REVIEWABILITY_CEILING=""

die() {
    echo "resolve-split-mode.sh: $1" >&2
    exit 2
}

SPLIT=""
SPLIT_SEEN=false
INTENT="none"
INTENT_SEEN=false
COORD_FLAG=""
COORDINATED_SEEN=false
NO_COORDINATED_SEEN=false
CLAUDE_MD=""
CLAUDE_MD_SEEN=false

# require_value <option> <remaining-arg-count>
# Refuses an option given as the last argument, with no value after it.
require_value() {
    if [ "$2" -lt 2 ]; then
        die "$1 requires a value"
    fi
}

while [ $# -gt 0 ]; do
    arg="$1"
    opt="$arg"
    val=""
    has_inline=false
    case "$arg" in
        --*=*)
            opt="${arg%%=*}"
            val="${arg#*=}"
            has_inline=true
            ;;
    esac

    case "$opt" in
        --split|--intent|--claude-md)
            if ! $has_inline; then
                require_value "$opt" $#
                val="$2"
                shift
            fi
            ;;
        --coordinated|--no-coordinated)
            if $has_inline; then
                die "$opt takes no value"
            fi
            ;;
        *)
            die "unknown argument: $arg"
            ;;
    esac
    shift

    case "$opt" in
        --split)
            $SPLIT_SEEN && die "--split given more than once"
            SPLIT_SEEN=true
            case "$val" in
                yes|no) SPLIT="$val" ;;
                *) die "--split must be yes or no, got '$val'" ;;
            esac
            ;;
        --intent)
            $INTENT_SEEN && die "--intent given more than once"
            INTENT_SEEN=true
            case "$val" in
                continue|stop|none) INTENT="$val" ;;
                *) die "--intent must be continue, stop, or none, got '$val'" ;;
            esac
            ;;
        --coordinated)
            $COORDINATED_SEEN && die "--coordinated given more than once"
            COORDINATED_SEEN=true
            ;;
        --no-coordinated)
            $NO_COORDINATED_SEEN && die "--no-coordinated given more than once"
            NO_COORDINATED_SEEN=true
            ;;
        --claude-md)
            $CLAUDE_MD_SEEN && die "--claude-md given more than once"
            CLAUDE_MD_SEEN=true
            [ -n "$val" ] || die "--claude-md requires a value"
            CLAUDE_MD="$val"
            ;;
    esac
done

$SPLIT_SEEN || die "--split is required (yes or no)"

if $COORDINATED_SEEN && $NO_COORDINATED_SEEN; then
    die "--coordinated and --no-coordinated are mutually exclusive"
fi
$COORDINATED_SEEN && COORD_FLAG="coordinated"
$NO_COORDINATED_SEEN && COORD_FLAG="no-coordinated"

if $CLAUDE_MD_SEEN && [ ! -f "$CLAUDE_MD" ]; then
    die "--claude-md path does not exist: $CLAUDE_MD"
fi

# header_value <file> <header-name>
# Prints the trimmed value of the first `## <header-name>:` line, or nothing.
header_value() {
    local file="$1" name="$2" line value
    while IFS= read -r line || [ -n "$line" ]; do
        case "$line" in
            "## $name:"*)
                value="${line#"## $name:"}"
                # Trim leading and trailing whitespace (spaces, tabs, CR).
                value="${value#"${value%%[![:space:]]*}"}"
                value="${value%"${value##*[![:space:]]}"}"
                printf '%s' "$value"
                return 0
                ;;
        esac
    done < "$file"
    return 0
}

# in_list <value> <space-separated list>
in_list() {
    local needle="$1" item
    [ -n "$needle" ] || return 1
    for item in $2; do
        [ "$item" = "$needle" ] && return 0
    done
    return 1
}

header_says_coordinated() {
    [ -n "$CLAUDE_MD" ] || return 1
    local v
    v=$(header_value "$CLAUDE_MD" "PR Grouping Policy")
    in_list "$v" "$COORDINATED_VALUES_PR_GROUPING_POLICY" && return 0
    v=$(header_value "$CLAUDE_MD" "Reviewability Ceiling")
    in_list "$v" "$COORDINATED_VALUES_REVIEWABILITY_CEILING" && return 0
    return 1
}

emit() {
    printf 'execution_mode=%s\nsplit_mode_source=%s\n' "$1" "$2"
    exit 0
}

if [ "$SPLIT" = "no" ]; then
    emit single-pr none
fi

case "$COORD_FLAG" in
    coordinated) emit coordinated flag ;;
    no-coordinated) emit multi-pr flag ;;
esac

case "$INTENT" in
    continue) emit coordinated intent ;;
    stop) emit multi-pr intent ;;
esac

if header_says_coordinated; then
    emit coordinated header
fi

emit multi-pr default
