#!/usr/bin/env bash
# plan-mode.sh -- map a PLAN's `execution_mode:` to an exit code.
#
# A koto command gate sees only an exit code, so a template that routes on the
# PLAN's mode needs the mode as one. /deliver's `mode_route` state is the
# first caller: single-pr and coordinated PLANs go on to /execute, a multi-pr
# PLAN is handed off, and a PLAN whose mode can't be read stops the run.
#
# The mode is read from the PLAN's YAML frontmatter only: the first line must
# be `---`, the block ends at the next `---`, and the first `execution_mode:`
# key inside it is the value (surrounding quotes and a trailing `# comment`
# are stripped). A key in the body, a second frontmatter block, or a value
# outside the enum is not a mode.
#
# Usage:
#   plan-mode.sh <plan-path>
#
# Output: the mode on stdout (`single-pr`, `coordinated`, or `multi-pr`) when
# it is valid, nothing otherwise, so a directive can show it to a person. The
# exit code carries the decision:
#
#   0   single-pr
#   10  coordinated
#   20  multi-pr
#   4   missing or invalid: no such file, no frontmatter, no execution_mode
#       key, or a value outside the three
#   64  usage error
#
# Read-only. bash 3.2, awk.
set -uo pipefail

PROG=plan-mode

if [ "$#" -ne 1 ] || [ -z "${1:-}" ]; then
    echo "usage: plan-mode.sh <plan-path>" >&2
    exit 64
fi
PLAN="$1"
case "$PLAN" in
    -*) PLAN="./$PLAN" ;;
esac

if [ ! -f "$PLAN" ] || [ ! -r "$PLAN" ]; then
    echo "$PROG: no readable PLAN at $1" >&2
    exit 4
fi

MODE=$(awk '
    NR == 1 { if ($0 !~ /^---[[:space:]]*$/) exit; inside = 1; next }
    inside && /^---[[:space:]]*$/ { exit }
    inside && /^execution_mode:/ {
        v = $0
        sub(/^execution_mode:[[:space:]]*/, "", v)
        sub(/[[:space:]]+#.*$/, "", v)
        sub(/[[:space:]]+$/, "", v)
        if (v ~ /^".*"$/ || v ~ /^'"'"'.*'"'"'$/) v = substr(v, 2, length(v) - 2)
        print v
        exit
    }' "$PLAN" 2>/dev/null)

case "$MODE" in
    single-pr) printf 'single-pr\n'; exit 0 ;;
    coordinated) printf 'coordinated\n'; exit 10 ;;
    multi-pr) printf 'multi-pr\n'; exit 20 ;;
esac
echo "$PROG: $1 records no valid execution_mode (single-pr, coordinated, multi-pr)" >&2
exit 4
