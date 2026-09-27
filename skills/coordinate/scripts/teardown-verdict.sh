#!/usr/bin/env bash
# teardown-verdict.sh -- read the teardown inventory's sealed verdict.
#
# teardown-inventory.sh --seal runs as the teardown state's default action and
# seals its verdict in the context key `teardown_verdict` through the record
# feature's coord-log.sh, which the state captures as TEARDOWN_SEAL. This
# script is the only reader of that verdict, and it reads it only through the
# seal check, so a verdict edited after sealing, or a seal from another state
# entry or another session, never reads as durable. The captured token is
# read from the session's own log, never taken as an argument.
#
# Modes:
#
#   gate --session <s>
#       The teardown state's gate (overridable: false). Exit 0 only when the
#       seal checks and the verdict is durable.
#
#   read --session <s>
#       Run by the destroy state's directive before any destroy command is
#       named. Prints the verdict when the seal checks, the verdict is
#       durable, and the session log shows no directed transition (`koto next
#       --to`, which skips gates; koto#251) since the sealed teardown entry.
#       Refuses otherwise.
#
# Exit codes:
#   0  durable, and (read) reached without a directed transition
#   1  the verdict says unique
#   2  the verdict says error, or a read failed
#   3  the seal doesn't check (the verdict was changed, or it isn't this
#      state entry's)
#   4  (read) a directed transition since the teardown entry: refuse to destroy
#
# Read-only. bash 3.2.
set -uo pipefail

PROG=teardown-verdict
HERE=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=dispatch-common.sh
. "$HERE/dispatch-common.sh"

usage() { printf 'usage: %s gate|read --session <s>\n' "$PROG" >&2; exit 2; }

MODE="${1:-}"
[ $# -gt 0 ] && shift
SESSION=""
while [ $# -gt 0 ]; do
    case "$1" in
        --session) [ $# -ge 2 ] || usage; SESSION="$2"; shift 2 ;;
        *) usage ;;
    esac
done
[ -n "$SESSION" ] || usage
case "$MODE" in gate | read) ;; *) usage ;; esac

CAPTURED=$(dc_capture "$SESSION" TEARDOWN_SEAL) || { printf '%s: cannot read the TEARDOWN_SEAL capture\n' "$PROG" >&2; exit 2; }
TOKEN=$(printf '%s' "$CAPTURED" | grep -Eo 'sealed:[0-9]+:[0-9a-f]{64}' | tail -1)
[ -n "$TOKEN" ] || { printf '%s: TEARDOWN_SEAL holds no seal\n' "$PROG" >&2; exit 3; }

VERDICT=$(dc_seal_check "$SESSION" teardown "$TOKEN" teardown_verdict)
case "$?" in
    0) ;;
    1) printf '%s: the teardown verdict does not match its seal\n' "$PROG" >&2; exit 3 ;;
    *) printf '%s: the teardown verdict could not be read\n' "$PROG" >&2; exit 2 ;;
esac

case "$VERDICT" in
    durable\ * | durable) ;;
    unique\ * | unique) printf '%s\n' "$VERDICT" >&2; exit 1 ;;
    *) printf '%s\n' "$VERDICT" >&2; exit 2 ;;
esac

if [ "$MODE" = read ]; then
    SEQ=$(printf '%s' "$TOKEN" | cut -d: -f2)
    dc_directed_since "$SESSION" "$SEQ"
    case "$?" in
        0) ;;
        1) printf '%s: a directed transition moved this run since the teardown inventory; refusing to destroy\n' "$PROG" >&2; exit 4 ;;
        *) printf '%s: the session log could not be read for directed transitions\n' "$PROG" >&2; exit 2 ;;
    esac
    printf '%s\n' "$VERDICT"
fi
exit 0
