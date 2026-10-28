#!/usr/bin/env bash
# resolve-coordinator.sh -- where a worker sends its report: the newest member
# of the run that dispatched it
# (docs/designs/DESIGN-coordinate-successor-continues.md, Decision 4).
#
# A worker's brief names `dispatcher_session`, the koto session of the run
# member that dispatched it. A coordinator taken over since (coordinate-open.sh,
# koto init --continues --supersede) is fenced, and its successor holds the
# run; the brief is never edited to say so. This follows the
# `session_superseded` events forward from the dispatcher's session to the
# newest member (dispatch-common.sh dc_newest_member) and prints that
# member's Run `coordinator` row, the Claude session name the worker messages.
# The brief's Reporting section has the worker run it before each report, and
# render-result.sh runs it for the result block.
#
# Usage: resolve-coordinator.sh <dispatcher_session>
#
# Prints, on success:
#   coordinator=<claude session name>   the newest member's coordinator row
#   member=<koto session>               the newest member
#
# Exit codes:
#   0  printed
#   1  the chain can't be read (a session or log that can't be read, a name
#      that isn't one, a cycle), the newest member's record/meta names
#      another run than the dispatcher's (its scope differs, or either holds
#      none), or the member names no coordinator address; the worker reports
#      to its brief's address
#   3  the walk passed its hop cap (DC_HOP_CAP, 1024 by default); the worker
#      reports to its brief's address
#   64 usage
#
# Reads only: koto session dir, the logs, and koto context get of record/meta
# and record/run, each run from the session's own execution directory (its
# log header's execution_dir) so a store that reads a session only from its
# own workspace still answers. It writes nothing to any session.
set -uo pipefail

PROG=resolve-coordinator
HERE=$(cd "$(dirname "$0")" && pwd)
KOTO=${KOTO_BIN:-koto}

[ $# -eq 1 ] || { echo "usage: $PROG <dispatcher_session>" >&2; exit 64; }
DISP=$1
# shellcheck source=dispatch-common.sh
. "$HERE/dispatch-common.sh" || exit 64
[[ $DISP =~ $DC_RE_SESSION ]] || { echo "$PROG: [$DISP] is not a koto session name" >&2; exit 64; }
fail() { echo "$PROG: $*; report to the address your brief names" >&2; exit 1; }

OUT=$(dc_newest_member "$DISP")
case $? in
    0) ;;
    3) echo "$PROG: the chain from $DISP runs past ${DC_HOP_CAP:-1024} takeovers; report to the address your brief names" >&2; exit 3 ;;
    *) fail "the chain of takeovers from $DISP can't be read" ;;
esac
MEMBER=${OUT%%	*}

# key <session> <key>: a context key of the session, read from its own
# execution directory when its log header names one that exists.
key() {
    local dir ed
    dir=$("$KOTO" session dir "$1" </dev/null 2>/dev/null) || return 1
    ed=$(head -n 1 "$dir/koto-$1.state.jsonl" 2>/dev/null | jq -r '.execution_dir // "" | strings' 2>/dev/null)
    if [ -n "$ed" ] && [ -d "$ed" ]; then
        (cd "$ed" && "$KOTO" context get "$1" "$2" </dev/null 2>/dev/null)
    else
        "$KOTO" context get "$1" "$2" </dev/null 2>/dev/null
    fi
}

DSCOPE=$(key "$DISP" record/meta | jq -c '.scope // empty' 2>/dev/null)
[ -n "$DSCOPE" ] || fail "$DISP holds no record/meta naming its run"
if [ "$MEMBER" != "$DISP" ]; then
    MSCOPE=$(key "$MEMBER" record/meta | jq -c '.scope // empty' 2>/dev/null)
    [ -n "$MSCOPE" ] || fail "$MEMBER, the newest member, holds no record/meta naming its run"
    [ "$MSCOPE" = "$DSCOPE" ] || fail "$MEMBER's record/meta names another run ($MSCOPE) than $DISP's ($DSCOPE)"
fi
ADDR=$(key "$MEMBER" record/run | jq -r '[(. // [])[] | select(.key == "coordinator") | .value][0] // "" | strings' 2>/dev/null)
[[ $ADDR =~ $DC_RE_SESSION ]] || fail "$MEMBER's record names no coordinator address"
printf 'coordinator=%s\nmember=%s\n' "$ADDR" "$MEMBER"
