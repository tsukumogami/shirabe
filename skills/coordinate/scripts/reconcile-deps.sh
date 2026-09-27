# reconcile-deps.sh -- the one place reconcile names what it borrows.
#
# Sourced, never run. Callers set PROG and `set -uo pipefail` first.
#
# Reconcile reuses rather than duplicates: the input validators from
# /execute's coord-common.sh, and two checks the coordination-record feature
# ships beside this file. Every reconcile script reaches those through the
# names below, so a rename on either side is a change here only.
#
# The two record-feature checks, and the interface this file assumes for
# them (stated by that feature; each lands on the default branch with its own
# outline of that feature's plan):
#
#   board-verdict.sh --repo <owner/repo> --sha <40-hex> --base <branch>
#     One JSON object on stdout: {verdict: verified|pending|unverified|
#     error:board-read|error:pr-state|error:deadline, head, reasons[{code,
#     run, job, name, detail}], ...}. Exit 0 with the object printed; 2
#     usage; 1 nothing printed. It stops itself at 24 s.
#
#   deferral-check.sh --row-file <json> --run-start <ISO time>
#     One line on stdout: "disposed filed <n>", "disposed closed",
#     "disposed carried <time>", or "undisposed <why>". Exit 0 disposed (or
#     raised this run), 1 undisposed, 64 usage. It checks the row's form
#     only; whether a filed issue exists is read here, from GitHub.
#
# Requires: bash 3.2+, jq.

RD_HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

# The validators. coord-common.sh is sourced for its patterns and functions
# only; it defines, it doesn't run.
# shellcheck source=/dev/null
. "$RD_HERE/../../execute/scripts/coord-common.sh"

# The record feature's checks. Overridable for tests only, by path.
RD_BOARD_CHECK=${RECONCILE_BOARD_CHECK:-$RD_HERE/board-verdict.sh}
RD_DEFERRAL_CHECK=${RECONCILE_DEFERRAL_CHECK:-$RD_HERE/deferral-check.sh}

rd_valid_repo()   { coord_valid_repo "$1"; }
rd_valid_branch() { coord_valid_branch "$1"; }
rd_valid_sha()    { [[ $1 =~ $RE_COORD_SHA ]]; }
rd_valid_topic()  { [[ $1 =~ $RE_COORD_SLUG ]]; }
rd_valid_number() { [[ $1 =~ ^[1-9][0-9]{0,9}$ ]]; }

# rd_now -- the time a read finished, ISO 8601 UTC.
rd_now() { date -u +%Y-%m-%dT%H:%M:%SZ; }

# rd_deadline SECS CMD... -- run CMD with a deadline, in pure bash because
# macOS has no timeout(1). Exit status is CMD's, or 124 when the deadline
# killed it. CMD's stdout and stderr pass through.
rd_deadline() {
    local secs=$1 pid watcher rc
    shift
    "$@" &
    pid=$!
    ( sleep "$secs" && kill -TERM "$pid" 2>/dev/null && touch "${RD_TIMED_OUT_MARK:-/dev/null}" ) >/dev/null 2>&1 &
    watcher=$!
    wait "$pid"
    rc=$?
    kill "$watcher" 2>/dev/null
    wait "$watcher" 2>/dev/null
    # A command killed by the watchdog dies of SIGTERM: 128 + 15.
    [ "$rc" -eq 143 ] && rc=124
    return "$rc"
}

# rd_not_verified KIND REASON -- print a not_verified fact.
rd_not_verified() {
    jq -nc --arg k "$1" --arg r "$2" --arg t "$(rd_now)" \
        '{kind: $k, status: "not_verified", reason: $r, read_at: $t}'
}

# rd_urlencode_path PATH -- percent-encode each segment of a repository path
# for the contents API. Refuses (returns 1) a path with an empty segment,
# a "." or ".." segment, a leading "/", or any control character.
rd_urlencode_path() {
    local p=$1
    case "$p" in ""|/*|*//*) return 1 ;; esac
    if printf '%s' "$p" | LC_ALL=C grep -q '[[:cntrl:]]'; then return 1; fi
    printf '%s' "$p" | jq -Rr 'split("/")
        | if any(. == "" or . == "." or . == "..") then error("bad") else . end
        | map(@uri) | join("/")' 2>/dev/null
}
