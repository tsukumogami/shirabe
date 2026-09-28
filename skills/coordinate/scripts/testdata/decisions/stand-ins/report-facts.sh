#!/usr/bin/env bash
# report-facts.sh -- STAND-IN for decisions-replay_engine_test.sh. The shipped
# report-facts.sh also reads the holding's pull request and board, which this
# harness has no stand-in for; the decision flow needs only its verdict and
# the coord/report.json the holding arm's gate requires. This prints
# `holding <topic>` when the record has a Holdings row for the report's topic
# (read through record-holding.sh), and writes that row as coord/report.json,
# else `unknown <topic>`.
#
# Usage: report-facts.sh --session S
set -uo pipefail
[ "${1-}" = --session ] || exit 64
SESSION=$2
HERE=$(cd "$(dirname "$0")" && pwd)
seal() { bash "$HERE/coord-log.sh" seal --session "$SESSION" --state report_facts --token "$1"; }
TOPIC=$(koto context get "$SESSION" report_topic)
F=$(mktemp "${TMPDIR:-/tmp}/rf-standin.XXXXXX")
if bash "$HERE/record-holding.sh" --session "$SESSION" --topic "$TOPIC" --read > "$F"; then
    koto context add "$SESSION" coord/report.json --from-file "$F" >/dev/null || { rm -f "$F"; exit 2; }
    rm -f "$F"
    seal "holding $TOPIC"
else
    rm -f "$F"
    seal "unknown $TOPIC"
fi
