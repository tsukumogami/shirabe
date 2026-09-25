#!/usr/bin/env bash
# check-plan-mode.sh -- did the /plan hop resolve the split mode from what
# /scope forwarded?
#
# koto cannot see a Skill call, so it cannot check that the hop passed /plan
# the flags the directive names. It can check what the call produced. This
# script re-runs /plan's own resolver, skills/plan/scripts/resolve-split-mode.sh,
# over the PLAN's split verdict and the flags /scope forwarded, and compares
# the answer with the PLAN's recorded `execution_mode` and `split_mode_source`.
# A hop that dropped `--intent`, dropped a coordination flag, or invented one
# resolves to a different mode or a different source, and the gate on
# hop_plan's `landed` edge routes the run to `bail` instead of on.
#
# The split verdict itself is /plan's judgment and is not re-made here. The
# PLAN records no `split_branch` field; it records the verdict through its
# mode: `single-pr` is the no-split outcome and `multi-pr` or `coordinated` a
# split. That is the one input taken from the PLAN; the other inputs are the
# forwarded intent and coordination flag and the repository's CLAUDE.md
# headers, exactly the inputs /plan's step 5a hands the resolver.
#
# A run with no intent short-circuits: its /plan hop sends today's argument
# string, and there is nothing forwarded to check.
#
# Usage:
#   check-plan-mode.sh --plan <path> --intent <continue|stop|none>
#                      --coordination <none|coordinated|no-coordinated>
#                      [--claude-md <path>]
#
#   --intent        RUN_INTENT, the effective intent intake resolved
#   --coordination  COORDINATION, the coordination flag the caller passed
#   --claude-md     the CLAUDE.md whose headers the resolver reads; defaults to
#                   CLAUDE.md at the repository root when that file exists
#
# Exit codes:
#   0  consistent, or --intent none
#   1  inconsistent: the PLAN's mode or source differs from the resolver's,
#      or the PLAN records no mode or source; a line on stderr names both
#   2  cannot tell: a usage error, a PLAN that cannot be read, or a resolver
#      that refused its arguments
#
# Read-only. It reads the PLAN and CLAUDE.md, and never the run's own state
# file. bash 3.2.

set -uo pipefail

PROG=check-plan-mode.sh
HERE=$(cd "$(dirname "$0")" && pwd)
RESOLVER="$HERE/../../plan/scripts/resolve-split-mode.sh"

die() {
    printf '%s: %s\n' "$PROG" "$1" >&2
    exit 2
}

mismatch() {
    printf '%s: %s\n' "$PROG" "$1" >&2
    exit 1
}

PLAN=""
INTENT=""
COORD=""
CLAUDE_MD=""
SEEN_PLAN=0
SEEN_INTENT=0
SEEN_COORD=0
SEEN_CLAUDE=0

while [ "$#" -gt 0 ]; do
    case "$1" in
        --plan)         [ "$#" -ge 2 ] || die "--plan requires a value"; PLAN="$2"; SEEN_PLAN=$((SEEN_PLAN + 1)); shift ;;
        --intent)       [ "$#" -ge 2 ] || die "--intent requires a value"; INTENT="$2"; SEEN_INTENT=$((SEEN_INTENT + 1)); shift ;;
        --coordination) [ "$#" -ge 2 ] || die "--coordination requires a value"; COORD="$2"; SEEN_COORD=$((SEEN_COORD + 1)); shift ;;
        --claude-md)    [ "$#" -ge 2 ] || die "--claude-md requires a value"; CLAUDE_MD="$2"; SEEN_CLAUDE=$((SEEN_CLAUDE + 1)); shift ;;
        *) die "unknown argument: $1" ;;
    esac
    shift
done

[ "$SEEN_PLAN" -eq 1 ] || die "--plan is required once"
[ "$SEEN_INTENT" -eq 1 ] || die "--intent is required once"
[ "$SEEN_COORD" -eq 1 ] || die "--coordination is required once"
[ "$SEEN_CLAUDE" -le 1 ] || die "--claude-md given more than once"

case "$INTENT" in
    none) exit 0 ;;
    continue|stop) ;;
    *) die "--intent must be continue, stop, or none" ;;
esac

case "$COORD" in
    none) COORD_ARG="" ;;
    coordinated) COORD_ARG="--coordinated" ;;
    no-coordinated) COORD_ARG="--no-coordinated" ;;
    *) die "--coordination must be none, coordinated, or no-coordinated" ;;
esac

[ -n "$PLAN" ] || die "--plan must not be empty"
[ -f "$PLAN" ] && [ -r "$PLAN" ] || die "the PLAN cannot be read: $PLAN"
[ -f "$RESOLVER" ] || die "resolve-split-mode.sh not found at $RESOLVER"

if [ "$SEEN_CLAUDE" -eq 0 ]; then
    TOP=$(git rev-parse --show-toplevel) || TOP=""
    if [ -n "$TOP" ] && [ -f "$TOP/CLAUDE.md" ]; then
        CLAUDE_MD="$TOP/CLAUDE.md"
    fi
fi

# frontmatter_field <key> -- the value of a top-level key in the PLAN's YAML
# frontmatter (between the first two `---` lines), trimmed, one pair of quotes
# and a trailing comment removed. Empty when absent.
frontmatter_field() {
    awk -v key="$1" '
        NR == 1 && $0 != "---" { exit }
        NR == 1 { inside = 1; next }
        inside && $0 == "---" { exit }
        inside && index($0, key ":") == 1 {
            v = substr($0, length(key) + 2)
            sub(/[[:space:]]+#.*$/, "", v)
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", v)
            gsub(/\r$/, "", v)
            if (v ~ /^".*"$/ || v ~ /^'"'"'.*'"'"'$/) v = substr(v, 2, length(v) - 2)
            print v
            exit
        }
    ' "$PLAN"
}

MODE=$(frontmatter_field execution_mode)
SOURCE=$(frontmatter_field split_mode_source)

[ -n "$MODE" ] || mismatch "the PLAN records no execution_mode"
[ -n "$SOURCE" ] || mismatch "the PLAN records no split_mode_source, so the hop's mode resolution cannot be checked"

case "$MODE" in
    single-pr) SPLIT=no ;;
    multi-pr|coordinated) SPLIT=yes ;;
    *) mismatch "the PLAN records execution_mode '$MODE', which is not single-pr, multi-pr, or coordinated" ;;
esac

set -- --split "$SPLIT" --intent "$INTENT"
[ -n "$COORD_ARG" ] && set -- "$@" "$COORD_ARG"
[ -n "$CLAUDE_MD" ] && set -- "$@" --claude-md "$CLAUDE_MD"

EXPECTED=$(bash "$RESOLVER" "$@") || die "resolve-split-mode.sh refused the forwarded arguments"
EXPECTED_MODE=$(printf '%s\n' "$EXPECTED" | sed -n 's/^execution_mode=//p')
EXPECTED_SOURCE=$(printf '%s\n' "$EXPECTED" | sed -n 's/^split_mode_source=//p')
[ -n "$EXPECTED_MODE" ] && [ -n "$EXPECTED_SOURCE" ] || die "resolve-split-mode.sh printed no mode"

if [ "$MODE" != "$EXPECTED_MODE" ] || [ "$SOURCE" != "$EXPECTED_SOURCE" ]; then
    mismatch "the PLAN records execution_mode=$MODE split_mode_source=$SOURCE, but the forwarded flags (intent=$INTENT coordination=$COORD) resolve to execution_mode=$EXPECTED_MODE split_mode_source=$EXPECTED_SOURCE"
fi

exit 0
