#!/usr/bin/env bash
# reconcile-report-get.sh -- read the reconcile report, checked against the
# seal the engine captured when the pass wrote it.
#
# It takes no sealed token as an argument. It reads the reconcile_pass
# state's capture (RECONCILE_SEAL) from the session log itself, through the
# record feature's coord-log.sh, and requires:
#   - the capture has the form "reconciled <64 hex> sealed:<seq>:<64 hex>";
#   - its seal checks, and <seq> is the latest entry into reconcile_pass;
#   - the sha256 of context key reconcile/report.json equals the first hex;
#   - the report parses with schema coordinate-reconcile-report/v1.
# A report written by the agent, left from an earlier visit, or altered after
# the pass sealed it fails one of those.
#
# Usage:
#   reconcile-report-get.sh --session S --check   exit status only (the gate)
#   reconcile-report-get.sh --session S           {report, directed_transitions}
#   reconcile-report-get.sh --session S --md      the report rendered as text
#
# directed_transitions lists every `koto next --to` in the run, as
# "<seq> <from>-><to>" (koto#251: a directed transition passes any gate, so a
# reader is told rather than trusting the route).
#
# Exit codes: 0 read and checked; 1 refused (no sealed report, a mismatch);
# 2 the log or a context key can't be read; 64 usage; 70 environment refused.
#
# Requires: bash 3.2+, jq, koto, and a sha256 tool (sha256sum or shasum).
set -uo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=reconcile-env.sh
. "$HERE/reconcile-env.sh"
if [ "${1-}" = --scrubbed ]; then shift; else rd_scrub "$0" "$@"; fi

PROG=reconcile-report-get
# shellcheck source=reconcile-deps.sh
. "$HERE/reconcile-deps.sh"

STATE=reconcile_pass
KEY=reconcile/report.json
SESSION="" MODE=json
while [ $# -gt 0 ]; do
    case "$1" in
        --session) [ $# -ge 2 ] || exit 64; SESSION=$2; shift 2 ;;
        --check) MODE=check; shift ;;
        --md) MODE=md; shift ;;
        *) exit 64 ;;
    esac
done
[[ $SESSION =~ ^[A-Za-z][A-Za-z0-9._-]*$ ]] || exit 64

fail() { echo "reconcile-report-get: $2" >&2; exit "$1"; }

CAP=$(bash "$RD_COORD_LOG" capture --session "$SESSION" --name RECONCILE_SEAL --state "$STATE")
case $? in
    0) ;;
    1) fail 1 "no sealed reconcile capture from the latest visit to $STATE" ;;
    *) fail 2 "the session log can't be read" ;;
esac
[[ $CAP =~ ^reconciled\ ([0-9a-f]{64})\ sealed:[0-9]+:[0-9a-f]{64}$ ]] \
    || fail 1 "the latest capture is not a sealed reconcile report"
WANT=${BASH_REMATCH[1]}

T=$(mktemp -d "${TMPDIR:-/tmp}/reconcile-report-get.XXXXXX")
trap 'rm -rf "$T"' EXIT
koto context get "$SESSION" "$KEY" > "$T/report.json" 2>/dev/null || fail 2 "context key $KEY can't be read"
[ "$(rd_sha256 < "$T/report.json")" = "$WANT" ] || fail 1 "$KEY does not match the sealed report"
jq -e '.schema == "coordinate-reconcile-report/v1"' "$T/report.json" >/dev/null 2>&1 \
    || fail 1 "$KEY is not a coordinate-reconcile-report/v1 document"

case "$MODE" in
    check) exit 0 ;;
    md) bash "$HERE/reconcile-report.sh" md < "$T/report.json" || fail 2 "the report could not be rendered" ;;
    json)
        DIRECTED=$(bash "$RD_COORD_LOG" directed-since --session "$SESSION" --from 0)
        case $? in 0|1) ;; *) fail 2 "the session log can't be read" ;; esac
        jq -c --arg d "$DIRECTED" '{report: ., directed_transitions: ($d | split("\n") | map(select(length > 0)))}' "$T/report.json" \
            || fail 2 "the report could not be read"
        ;;
esac
