#!/usr/bin/env bash
# report-pr_test.sh -- report-pr.sh, classify_report's gate: a `done` goes
# on to verify only when report_facts' sealed verdict has a pull request.
#
# Covers: `holding <pr>` 0; `holding none` 1; another verdict, a capture
# sealed before report_facts' latest visit, an unsealed one and none at all 2.
#
# Usage: bash skills/coordinate/scripts/report-pr_test.sh
set -uo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
command -v jq >/dev/null 2>&1 || { echo "SKIP: jq not on PATH"; exit 0; }
. "$HERE/testdata/test-lib.sh"
RP="$HERE/report-pr.sh"
N=0
at() { # at <REPORT token>: a run whose report_facts sealed the token, now at classify_report
    N=$((N + 1))
    S="coordinate-roadmap-plugin-system-20260926T0800$(printf '%02d' "$N")Z"
    log_new "$S" "$(roadmap_vars plugin-system)"
    log_to "$S" wait report_facts
    [ -z "$1" ] || log_capture "$S" REPORT "$(bash "$HERE/coord-log.sh" seal --session "$S" --state report_facts --token "$1")"
    log_to "$S" report_facts report_questions
    log_to "$S" report_questions classify_report
}
rc() { bash "$RP" --session "$S" >/dev/null 2>&1; echo $?; }

at "holding 12 alpha"; eq "a holding with a pull request: 0" 0 "$(rc)"
at "holding none alpha"; eq "a holding with none: 1" 1 "$(rc)"
at "unknown alpha"; eq "another verdict: 2" 2 "$(rc)"
at "refused alpha fork-head"; eq "a refusal: 2" 2 "$(rc)"
at "holding 12 alpha"; log_to "$S" classify_report report_facts
eq "a capture from before report_facts' latest visit: 2" 2 "$(rc)"
at ""; log_capture "$S" REPORT "holding 12 alpha"
eq "an unsealed capture: 2" 2 "$(rc)"
at ""; eq "no capture at all: 2" 2 "$(rc)"
bash "$RP" >/dev/null 2>&1; eq "no session: 2" 2 $?

done_tests report-pr
