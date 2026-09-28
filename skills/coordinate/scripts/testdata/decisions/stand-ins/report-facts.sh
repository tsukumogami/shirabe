#!/usr/bin/env bash
# report-facts.sh -- STAND-IN for decisions-replay_engine_test.sh.
#
# Prints `holding` when the harness has named the reporting holding in
# "$DEC_ST/<session>.holding", else `unknown`. The real script reads the
# record. Issue 10 of the coordinate-decisions plan keeps a stand-in here only
# if the harness still can't give the real one a record.
#
# Usage: report-facts.sh --session S
set -uo pipefail
[ "${1-}" = --session ] || exit 64
SESSION=$2
. "$(cd "$(dirname "$0")" && pwd)/model-lib.sh"
if [ -s "$DEC_ST/$SESSION.holding" ]; then seal report_facts holding; else seal report_facts unknown; fi
