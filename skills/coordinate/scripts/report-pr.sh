#!/usr/bin/env bash
# report-pr.sh -- classify_report's gate: does the report being classified
# have a pull request to verify?
#
# `done` sends a report on to verify, and verify_board reads the pull request
# report_facts found for it. A holding with no pull request, whose report
# named none either, has nothing to verify, so `done` for it goes back to the
# hub instead of to a board read that can only stop. The answer is
# report_facts' REPORT capture, sealed at its latest visit, read from the
# session log: never a value the coordinator submits.
#
# Usage: report-pr.sh --session <koto-session>
#
# Exit codes (the gate routes on them; it's declared overridable: false):
#   0  the capture reads `holding <pr> <topic>`: there is a pull request
#   1  it reads `holding none <topic>`: there is none
#   2  no sealed capture from report_facts' latest visit, another verdict, or
#      the log can't be read
#
# Read-only. bash 3.2.
set -uo pipefail

PROG=report-pr
HERE=$(cd "$(dirname "$0")" && pwd)
SESSION=
while [ $# -gt 0 ]; do
    case "$1" in
        --session) [ $# -ge 2 ] || { printf 'usage: %s --session <s>\n' "$PROG" >&2; exit 2; }; SESSION=$2; shift 2 ;;
        *) printf 'usage: %s --session <s>\n' "$PROG" >&2; exit 2 ;;
    esac
done
[ -n "$SESSION" ] || { printf 'usage: %s --session <s>\n' "$PROG" >&2; exit 2; }

CAP=$(bash "$HERE/coord-log.sh" capture --session "$SESSION" --name REPORT --state report_facts 2> /dev/null) || {
    printf '%s: no sealed report_facts verdict from its latest visit\n' "$PROG" >&2; exit 2; }
set -f; set -- ${CAP% sealed:*}; set +f
if [ $# -eq 3 ] && [ "$1" = holding ]; then
    case "$2" in
        none) printf '%s: the holding for %s has no pull request, and the report named none\n' "$PROG" "$3" >&2; exit 1 ;;
        [1-9]*) case "$2" in *[!0-9]*) ;; *) exit 0 ;; esac ;;
    esac
fi
printf '%s: report_facts'"'"' verdict is [%s], not a holding\n' "$PROG" "${CAP% sealed:*}" >&2
exit 2
