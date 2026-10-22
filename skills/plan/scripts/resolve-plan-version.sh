#!/usr/bin/env bash
#
# resolve-plan-version.sh - Resolve which plan version /plan writes
#
# /plan writes either `plan/v1` (entries are issues) or `plan/v2` (entries are
# steps). The version is chosen on a three-level stack, first answer wins:
#
#   1. --plan-version=<v1|v2>                  (the flag)
#   2. a `## Plan Version: <v1|v2>` line in the CLAUDE.md named by --claude-md
#                                              (the header)
#   3. DEFAULT_PLAN_VERSION, below             (the default)
#
# The default is assigned on exactly one line of this script and nowhere else.
# Changing which version /plan writes by default is a one-line edit to that
# assignment; resolve-plan-version_test.sh flips it in a copy and checks that
# nothing else has to change.
#
# Header rules: only a whole line that starts `## Plan Version:` counts, read
# from the file --claude-md names (the repository root's CLAUDE.md), and a line
# inside a fenced code block (``` or ~~~) is ignored. The value is trimmed of
# surrounding whitespace and must then be `v1` or `v2` exactly. The header is
# read only when no flag is given: the flag wins, and a run given the flag is
# not stopped by a duplicated or malformed header it never reads.
#
# --needs-v1=<roadmap|coordinated> says the run needs something only plan/v1
# has: a roadmap input, or a split that resolved to `coordinated`. A step plan
# can hold neither. When the version came from the default, the default gives
# way: the script prints v1 and says why in one stderr line, still exit 0, and
# /plan repeats that line to the author. When a flag or header asked for v2,
# the run stops instead (exit 2), since the author chose a step plan. A v1 from
# any level is printed as usual.
#
# Usage:
#   resolve-plan-version.sh [--plan-version <v1|v2>] [--claude-md <path>]
#                           [--needs-v1 <roadmap|coordinated>]
#
#   Each option also accepts the `--opt=value` form. Without --claude-md no
#   header is consulted.
#
# Output: exactly one line on stdout, `v1` or `v2`, then exit 0. Only the
# default giving way to --needs-v1 also writes to stderr.
#
# Rejections (exit 2, nothing on stdout, one stderr line):
#   a --plan-version value other than v1 or v2, empty included; a header value
#   other than v1 or v2; two `## Plan Version:` headers outside fenced code
#   (naming both lines); a --needs-v1 value other than roadmap or coordinated;
#   a flag or header asking for v2 when --needs-v1 is given; an option given
#   twice; a --claude-md path that is not a file; an unknown argument; an
#   option missing its value. A value is never
#   echoed back raw: control characters are stripped and it is cut to 40
#   characters first
#   (200 for a path).
#
# The script reads only its arguments and the named CLAUDE.md, makes no network
# call, and runs under bash 3.2.

set -euo pipefail

DEFAULT_PLAN_VERSION=v2

die() {
    echo "resolve-plan-version.sh: $1" >&2
    exit 2
}

# quote <text> [<max>]: the text with control characters removed, cut to <max>
# characters (default 40), for use inside an error message.
quote() {
    local s max="${2:-40}"
    s=$(printf '%s' "$1" | LC_ALL=C tr -d '\000-\037\177')
    if [ "${#s}" -gt "$max" ]; then
        s="${s:0:$max}..."
    fi
    printf '%s' "$s"
}

check_version() {
    # check_version <where> <value>
    case "$2" in
        v1|v2) return 0 ;;
    esac
    die "$1 must be v1 or v2, got '$(quote "$2")'"
}

FLAG=""
FLAG_SEEN=false
CLAUDE_MD=""
CLAUDE_MD_SEEN=false
NEEDS_V1=""
NEEDS_V1_SEEN=false

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
        --plan-version|--claude-md|--needs-v1)
            if ! $has_inline; then
                if [ $# -lt 2 ]; then
                    [ "$opt" = "--plan-version" ] && die "--plan-version requires a value: v1 or v2"
                    [ "$opt" = "--needs-v1" ] && die "--needs-v1 requires a value: roadmap or coordinated"
                    die "$opt requires a value"
                fi
                val="$2"
                shift
            fi
            ;;
        *)
            die "unknown argument: $(quote "$arg")"
            ;;
    esac
    shift

    case "$opt" in
        --plan-version)
            $FLAG_SEEN && die "--plan-version given more than once"
            FLAG_SEEN=true
            check_version "--plan-version" "$val"
            FLAG="$val"
            ;;
        --claude-md)
            $CLAUDE_MD_SEEN && die "--claude-md given more than once"
            CLAUDE_MD_SEEN=true
            [ -n "$val" ] || die "--claude-md requires a value"
            [ -f "$val" ] || die "--claude-md is not a file: $(quote "$val" 200)"
            CLAUDE_MD="$val"
            ;;
        --needs-v1)
            $NEEDS_V1_SEEN && die "--needs-v1 given more than once"
            NEEDS_V1_SEEN=true
            case "$val" in
                roadmap|coordinated) ;;
                *) die "--needs-v1 must be roadmap or coordinated, got '$(quote "$val")'" ;;
            esac
            NEEDS_V1="$val"
            ;;
    esac
done

# finish <version> <from>: print the version, or let --needs-v1 overrule a
# v2 that came from the default, or stop on a v2 a flag or header asked for.
# <from> is `flag`, `header` or `default`.
finish() {
    local version="$1" from="$2" why stop
    if [ -n "$NEEDS_V1" ] && [ "$version" = "v2" ]; then
        case "$NEEDS_V1" in
            roadmap)
                why="a roadmap input is planned under v1"
                stop="a roadmap is planned with --plan-version=v1; step plans are for designs, PRDs and topics"
                ;;
            coordinated)
                why="a coordinated split is planned under v1"
                stop="coordinated plans use --plan-version=v1; a step plan lands as single-pr or multi-pr"
                ;;
        esac
        if [ "$from" != "default" ]; then
            die "$stop"
        fi
        echo "resolve-plan-version.sh: no plan version was asked for, so the default v2 gives way to v1: $why" >&2
        version=v1
    fi
    printf '%s\n' "$version"
    exit 0
}

if [ -n "$FLAG" ]; then
    finish "$FLAG" flag
fi

# header_scan <file>
# Prints "<line-number> <trimmed value>" for every `## Plan Version:` line
# outside a fenced code block.
header_scan() {
    local file="$1" line n=0 in_fence=false fence_char="" fence_len=0
    local re_fence='^ {0,3}(`{3,}|~{3,})(.*)$'
    local run rest value
    while IFS= read -r line || [ -n "$line" ]; do
        n=$((n + 1))
        line="${line%$'\r'}"
        if [[ "$line" =~ $re_fence ]]; then
            run="${BASH_REMATCH[1]}"
            rest="${BASH_REMATCH[2]}"
            if $in_fence; then
                # A closing fence: the same character, at least as long, and
                # nothing after it but whitespace.
                if [ "${run:0:1}" = "$fence_char" ] && [ "${#run}" -ge "$fence_len" ] \
                    && [ -z "${rest//[[:space:]]/}" ]; then
                    in_fence=false
                fi
                continue
            fi
            # A backtick fence's info string may not contain a backtick.
            case "$run" in
                '`'*)
                    case "$rest" in
                        *'`'*) ;;
                        *)
                            in_fence=true
                            fence_char='`'
                            fence_len=${#run}
                            continue
                            ;;
                    esac
                    ;;
                *)
                    in_fence=true
                    fence_char='~'
                    fence_len=${#run}
                    continue
                    ;;
            esac
        fi
        $in_fence && continue
        case "$line" in
            '## Plan Version:'*)
                value="${line#'## Plan Version:'}"
                value="${value#"${value%%[![:space:]]*}"}"
                value="${value%"${value##*[![:space:]]}"}"
                printf '%s %s\n' "$n" "$value"
                ;;
        esac
    done < "$file"
}

if [ -n "$CLAUDE_MD" ]; then
    headers=$(header_scan "$CLAUDE_MD")
    if [ -n "$headers" ]; then
        count=$(printf '%s\n' "$headers" | wc -l | tr -d ' ')
        if [ "$count" -gt 1 ]; then
            lines=$(printf '%s\n' "$headers" | cut -d' ' -f1 | tr '\n' ',' | sed 's/,$//; s/,/, /g')
            die "'## Plan Version:' appears more than once in $(quote "$CLAUDE_MD" 200) (lines $lines); keep one"
        fi
        value="${headers#* }"
        check_version "the '## Plan Version:' header in $(quote "$CLAUDE_MD" 200)" "$value"
        finish "$value" header
    fi
fi

finish "$DEFAULT_PLAN_VERSION" default
