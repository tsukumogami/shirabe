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
# the pass sealed it fails one of those. On the session store the report must
# also have been read under the run's current import facts (record/host): one
# sealed before the run was imported here, on another host, is refused with 3,
# in every mode. The reconcile gate sends the run back to reconcile_pass on
# that code, and the hub's directive runs --check on every visit and ticks
# `moved` on it, so a run imported in any state reconciles on this host.
#
# Usage:
#   reconcile-report-get.sh --session S --check   exit status only (the reconcile
#                                                  gate, and the hub's directive)
#   reconcile-report-get.sh --session S           {report, directed_transitions}
#   reconcile-report-get.sh --session S --md      the report rendered as text
#
# directed_transitions lists every `koto next --to` in the run, as
# "<seq> <from>-><to>": a directed transition passes any gate, so a reader is
# told rather than trusting the route.
#
# Exit codes: 0 read and checked; 1 refused (no sealed report, a mismatch);
# 2 the log or a context key can't be read; 3 the report was sealed before the
# run was imported to this host; 64 usage.
#
# Requires: bash 3.2+, jq, koto, and a sha256 tool (sha256sum or shasum).
set -uo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)

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

CAP=$("$BASH" "$RD_COORD_LOG" capture --session "$SESSION" --name RECONCILE_SEAL --state "$STATE")
case $? in
    0) ;;
    1) fail 1 "no sealed reconcile capture from the latest visit to $STATE" ;;
    *) fail 2 "the session log can't be read" ;;
esac
[[ $CAP =~ ^reconciled\ ([0-9a-f]{64})\ sealed:[0-9]+:[0-9a-f]{64}$ ]] \
    || fail 1 "the latest capture is not a sealed reconcile report"
WANT=${BASH_REMATCH[1]}

T=$(mktemp -d "${TMPDIR:-/tmp}/reconcile-report-get.XXXXXX") || fail 2 "cannot make a temporary directory"
trap 'rm -rf "$T"' EXIT
koto context get "$SESSION" "$KEY" > "$T/report.json" 2>/dev/null || fail 2 "context key $KEY can't be read"
[ "$(rd_sha256 < "$T/report.json")" = "$WANT" ] || fail 1 "$KEY does not match the sealed report"
jq -e '.schema == "coordinate-reconcile-report/v1"' "$T/report.json" >/dev/null 2>&1 \
    || fail 1 "$KEY is not a coordinate-reconcile-report/v1 document"

# A report sealed before the run was imported here was read on another host:
# its workers, inventory and legs are that host's. record/host's import facts
# change with each import, and the report carries the ones it was read under,
# so a difference sends the run back to reconcile_pass for a new visit here.
if [ -n "$SESSION" ]; then
    rs_host "$SESSION" "$T/host" || fail 2 "record/host can't be read"
    # jq -e exits 1 only for a false comparison; any other code is a jq
    # failure, which must not read as an import and loop the run to the pass.
    jq -e --slurpfile r "$T/report.json" '
        (if (.source_session // "") == "" then null
         else {source_session, source_workspace: (.source_workspace // ""), template_hash: (.template_hash // "")} end)
        == ($r[0].header.import // null)' "$T/host" >/dev/null 2>&1
    case $? in
        0) ;;
        1) fail 3 "the sealed report was read before this run was imported here; it is reconciled again on this host" ;;
        *) fail 2 "record/host or the report couldn't be compared" ;;
    esac
fi

case "$MODE" in
    check) exit 0 ;;
    md) "$BASH" "$HERE/reconcile-report.sh" md < "$T/report.json" || fail 2 "the report could not be rendered" ;;
    json)
        DIRECTED=$("$BASH" "$RD_COORD_LOG" directed-since --session "$SESSION" --from 0)
        case $? in 0|1) ;; *) fail 2 "the session log can't be read" ;; esac
        jq -c --arg d "$DIRECTED" '{report: ., directed_transitions: ($d | split("\n") | map(select(length > 0)))}' "$T/report.json" \
            || fail 2 "the report could not be read"
        ;;
esac
