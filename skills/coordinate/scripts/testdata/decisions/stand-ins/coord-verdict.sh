#!/usr/bin/env bash
# coord-verdict.sh -- STAND-IN for decisions-replay_engine_test.sh.
#
# The shipped verdict gate (coord-verdict-shipped.sh beside it) plus the codes
# the DESIGN gives the decision words, until coord-verdict.sh carries them.
# The seal is checked by the shipped script's own reader first. Issue 10 of
# the coordinate-decisions plan removes this and runs the shipped script.
set -uo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
CAPTURE=
args=("$@")
while [ $# -gt 0 ]; do
    case "$1" in --capture) CAPTURE=$2; shift 2 ;; *) shift ;; esac
done
set -- "${args[@]}"
case "${CAPTURE%% *}" in
    carry) c=150 ;; unrecorded-open) c=151 ;; unrecorded-answer) c=152 ;; unrecorded-evidence) c=153 ;;
    unrecorded-raise) c=154 ;; withdraw) c=155 ;; reply) c=156 ;; redirect) c=157 ;; escalate) c=158 ;;
    take) c=159 ;; verdict) c=160 ;; clear) c=161 ;; clear-report) c=162 ;; record-full) c=163 ;;
    questions) c=170 ;; overflow) c=171 ;; unreadable) c=172 ;; message) c=180 ;; accepted) c=190 ;;
    *) exec bash "$HERE/coord-verdict-shipped.sh" "$@" ;;
esac
# The same seal check the shipped script makes, through its own reader.
S= ST=
while [ $# -gt 0 ]; do
    case "$1" in --session) S=$2; shift 2 ;; --state) ST=$2; shift 2 ;; *) shift ;; esac
done
bash "$HERE/coord-log.sh" check --session "$S" --state "$ST" --sealed "$CAPTURE" >/dev/null
rc=$?
[ $rc -eq 0 ] || exit $(( rc == 2 ? 2 : 1 ))
exit $c
