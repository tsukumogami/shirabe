#!/usr/bin/env bash
# reconcile-owe.sh -- owe the verdict of every milestone a roadmap/v4
# roadmap reads Completed that the record doesn't owe yet.
#
# On a roadmap/v4 roadmap a milestone reads Completed once its work is
# finished and Verified once its verdict is given. The record says which
# verdicts are owed with a verdict-owed Work row, which roadmap-status.sh
# --unit writes at the landed tick. A coordinator that takes up a roadmap
# whose milestones were Completed before this record knew of them (a new
# record, a restart over a migrated roadmap) finds no row for them, so pick
# would never offer their verdicts. reconcile-pass.sh launches this once per
# visit at roadmap scope, as it launches reconcile-settle.sh, and only when
# its whole budget fits in the pass; it runs roadmap-status.sh
# --owe-completed, the only writer of verdict-owed rows, which writes a row
# for each such milestone and nothing on v1 to v3
# (docs/designs/DESIGN-completed-verified-states.md, Decision 3).
#
# Usage:
#   reconcile-owe.sh --session S
#
# Output: one JSON fact on stdout, exit 0, like every re-check:
#   {kind: "owe", status: "ok", owed: [<tag>...], reason: "", read_at}
#   {kind: "owe", status: "not_verified", reason, read_at}
# owed names the milestones this call wrote a row for, empty when there was
# none to write (every Completed milestone owed already, no Completed
# milestone, or a roadmap that isn't roadmap/v4). Exit 64 on usage.
#
# Requires: bash 3.2+, jq, gh, koto.
set -uo pipefail

PROG=reconcile-owe
HERE=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=reconcile-deps.sh
. "$HERE/reconcile-deps.sh"

usage() { echo "$PROG: usage: $PROG --session S" >&2; exit 64; }
SESSION=""
while [ $# -gt 0 ]; do
    [ $# -ge 2 ] || usage
    case "$1" in
        --session) SESSION=$2 ;;
        *) usage ;;
    esac
    shift 2
done
[ -n "$SESSION" ] || usage

T=$(mktemp -d "${TMPDIR:-/tmp}/reconcile-owe.XXXXXX") || { rd_not_verified owe "no temp directory"; exit 0; }
trap 'rm -rf "$T"' EXIT

bash "$HERE/roadmap-status.sh" --session "$SESSION" --owe-completed > "$T/out" 2> "$T/err" < /dev/null
rc=$?
# roadmap-status.sh's last stderr line says why; it scrubs token-shaped text.
why=$(tail -n 1 "$T/err" | tr -d '\000-\037' | cut -c1-200)
case $rc in
    0) ;;
    12) rd_not_verified owe "the record changed under the write; the next pass reads it again"; exit 0 ;;
    10) rd_not_verified owe "the record refused the write: $why"; exit 0 ;;
    *) rd_not_verified owe "owing the Completed milestones' verdicts failed (exit $rc): $why"; exit 0 ;;
esac
sed -n 's/^verdict-owed //p' "$T/out" | jq -R . | jq -sc --arg t "$(rd_now)" '{kind: "owe", status: "ok", owed: ., reason: "", read_at: $t}' \
    || rd_not_verified owe "the rows written could not be read"
exit 0
