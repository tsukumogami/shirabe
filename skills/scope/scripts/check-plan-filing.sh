#!/usr/bin/env bash
# check-plan-filing.sh -- did the /plan hop file GitHub issues, and was it
# allowed to?
#
# Filing issues and a milestone creates remote artifacts, so every path that
# files needs an approval: interactively the author's, and under --auto the
# repository's own standing instruction, a `## Tracking Level:` header in its
# CLAUDE.md that names a filing level. koto cannot see the Skill call that
# filed, so the hop_plan state gates its `landed` edge on what the call left
# behind: this script reads the PLAN's recorded tracking level and the run's
# execution mode, and a context-matches gate beside it reads the approval the
# hop recorded under the `plan_filing_approval` key.
#
# A PLAN files when its `tracking_level` is `issues` or `issues-and-milestone`,
# or, with no `tracking_level`, when its `execution_mode` is `multi-pr` or
# `coordinated` (plan-format.md reads such a PLAN as issue-carrying). A
# `single-pr` PLAN with no level files nothing.
#
# Usage:
#   check-plan-filing.sh --plan <path> --exec-mode <auto|interactive|default>
#                        [--claude-md <path>]
#
#   --exec-mode  EXEC_MODE, this invocation's execution mode
#   --claude-md  the CLAUDE.md whose `## Tracking Level:` header is read;
#                defaults to CLAUDE.md at the repository root when it exists
#
# Exit codes:
#   0  the PLAN files nothing: no approval is needed
#   3  the PLAN files, and filing was permitted (an interactive run, or an
#      --auto run whose CLAUDE.md declares a filing level that covers the
#      PLAN's: `issues-and-milestone` covers both, `issues` only `issues`):
#      the hop must also have recorded the approval
#   1  the PLAN files under --auto and CLAUDE.md declares no filing level that
#      covers it: nobody approved the filing; a line on stderr says so
#   2  cannot tell: a usage error, or a PLAN that cannot be read
#
# Read-only. bash 3.2.

set -uo pipefail

PROG=check-plan-filing.sh

die() {
    printf '%s: %s\n' "$PROG" "$1" >&2
    exit 2
}

PLAN=""
EXEC=""
CLAUDE_MD=""
SEEN_PLAN=0
SEEN_EXEC=0
SEEN_CLAUDE=0

while [ "$#" -gt 0 ]; do
    case "$1" in
        --plan)      [ "$#" -ge 2 ] || die "--plan requires a value"; PLAN="$2"; SEEN_PLAN=$((SEEN_PLAN + 1)); shift ;;
        --exec-mode) [ "$#" -ge 2 ] || die "--exec-mode requires a value"; EXEC="$2"; SEEN_EXEC=$((SEEN_EXEC + 1)); shift ;;
        --claude-md) [ "$#" -ge 2 ] || die "--claude-md requires a value"; CLAUDE_MD="$2"; SEEN_CLAUDE=$((SEEN_CLAUDE + 1)); shift ;;
        *) die "unknown argument: $1" ;;
    esac
    shift
done

[ "$SEEN_PLAN" -eq 1 ] || die "--plan is required once"
[ "$SEEN_EXEC" -eq 1 ] || die "--exec-mode is required once"
[ "$SEEN_CLAUDE" -le 1 ] || die "--claude-md given more than once"

case "$EXEC" in
    auto) ;;
    interactive|default) EXEC=interactive ;;
    *) die "--exec-mode must be auto, interactive, or default" ;;
esac

[ -n "$PLAN" ] || die "--plan must not be empty"
[ -f "$PLAN" ] && [ -r "$PLAN" ] || die "the PLAN cannot be read: $PLAN"

if [ "$SEEN_CLAUDE" -eq 0 ]; then
    TOP=$(git rev-parse --show-toplevel 2>/dev/null) || TOP=""
    if [ -n "$TOP" ] && [ -f "$TOP/CLAUDE.md" ]; then
        CLAUDE_MD="$TOP/CLAUDE.md"
    fi
fi

# frontmatter_field <key> -- the value of a top-level key in the PLAN's YAML
# frontmatter, trimmed, one pair of quotes and a trailing comment removed.
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
LEVEL=$(frontmatter_field tracking_level)

case "$LEVEL" in
    issues|issues-and-milestone) FILES=yes ;;
    none) FILES=no ;;
    "")
        case "$MODE" in
            multi-pr|coordinated) FILES=yes ;;
            single-pr) FILES=no ;;
            *) die "the PLAN records no tracking_level and an execution_mode of '$MODE'" ;;
        esac
        ;;
    *) die "the PLAN records tracking_level '$LEVEL', which is not none, issues, or issues-and-milestone" ;;
esac

[ "$FILES" = yes ] || exit 0
[ "$EXEC" = interactive ] && exit 3

# --auto: the repository's CLAUDE.md must declare a filing level.
HEADER=""
if [ -n "$CLAUDE_MD" ] && [ -f "$CLAUDE_MD" ]; then
    HEADER=$(sed -n 's/^## Tracking Level:[[:space:]]*//p' "$CLAUDE_MD" | head -n 1 | sed 's/[[:space:]]*$//')
fi
# The header must cover what the PLAN filed: `issues` does not cover a
# milestone. A PLAN with no level is read as issue-carrying at the default,
# which files a milestone too.
case "$HEADER:${LEVEL:-issues-and-milestone}" in
    issues-and-milestone:*|issues:issues) exit 3 ;;
esac
printf '%s: the PLAN files issues (tracking level %s) under --auto, but CLAUDE.md declares no filing tracking level that covers it%s\n' \
    "$PROG" "${LEVEL:-unset, read as issue-carrying}" "${HEADER:+ (it declares $HEADER)}" >&2
exit 1
