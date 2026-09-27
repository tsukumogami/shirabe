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
#     "disposed carried <time>", or "undisposed <why>", where a row raised at
#     or after the run start prints "undisposed raised-this-run" and exits 0
#     (it isn't the predecessor's to dispose of). Exit 0 disposed or raised
#     this run, 1 undisposed, 64 usage. It checks the row's form only;
#     whether a filed issue exists is read by reconcile, from GitHub.
#
# The checks are always the ones beside this file. There is no environment
# override: the environment of a tick is the agent's, and a variable that
# chose which board check runs would let it choose the verdict.
#
# Requires: bash 3.2+, jq, and pkill (procps on Linux, base system on macOS).

RD_HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

# The validators. coord-common.sh is sourced for its patterns and functions
# only; it defines, it doesn't run.
# shellcheck source=/dev/null
. "$RD_HERE/../../execute/scripts/coord-common.sh"

RD_BOARD_CHECK=$RD_HERE/board-verdict.sh
RD_DEFERRAL_CHECK=$RD_HERE/deferral-check.sh
# The record's reader: record-parse.sh (the one codec, also for the discipline
# handoff) and coord-log.sh (the run's facts: scope, name, host, record).
RD_RECORD_PARSE=$RD_HERE/record-parse.sh
RD_COORD_LOG=$RD_HERE/coord-log.sh

rd_valid_repo()   { coord_valid_repo "$1" && [[ $1 != -* ]]; }
rd_valid_branch() { coord_valid_branch "$1"; }
rd_valid_sha()    { [[ $1 =~ $RE_COORD_SHA ]]; }
rd_valid_topic()  { [[ $1 =~ $RE_COORD_SLUG ]]; }
rd_valid_number() { [[ $1 =~ ^[1-9][0-9]{0,9}$ ]]; }
rd_valid_secs()   { [[ $1 =~ ^[1-9][0-9]{0,3}$ ]]; }

# rd_sha256 -- the sha256 of stdin, as 64 lowercase hex.
rd_sha256() {
    if command -v sha256sum >/dev/null 2>&1; then sha256sum | cut -d' ' -f1
    else shasum -a 256 | cut -d' ' -f1; fi
}

# rd_now -- the time a read finished, ISO 8601 UTC.
rd_now() { date -u +%Y-%m-%dT%H:%M:%SZ; }

# rd_deadline SECS CMD... -- run CMD with a deadline, in pure bash because
# macOS has no timeout(1). CMD's stdout goes to a file, not a pipe, so a
# grandchild left running can't hold the caller's $(...) open past the
# deadline; the file is printed once CMD has ended. At the deadline CMD and
# its children get TERM, and KILL a second later. Exit status is CMD's, or
# 124 when the deadline ended it. CMD's stderr passes through.
rd_deadline() {
    local secs=$1 pid watcher rc out mark
    shift
    rd_valid_secs "$secs" || secs=8
    out=$(mktemp "${TMPDIR:-/tmp}/reconcile-read.XXXXXX")
    mark="$out.late"
    "$@" > "$out" &
    pid=$!
    (
        sleep "$secs"
        : > "$mark"
        pkill -TERM -P "$pid" 2>/dev/null; kill -TERM "$pid" 2>/dev/null
        sleep 1
        pkill -KILL -P "$pid" 2>/dev/null; kill -KILL "$pid" 2>/dev/null
    ) >/dev/null 2>&1 &
    watcher=$!
    wait "$pid"
    rc=$?
    kill "$watcher" 2>/dev/null
    wait "$watcher" 2>/dev/null
    [ -e "$mark" ] && rc=124
    cat "$out"
    rm -f "$out" "$mark"
    return "$rc"
}

# rd_slug TOPIC -- the workspace manager's slug for a dispatch topic, by its
# own rule: lowercase, every run of characters outside [a-z0-9] collapsed to
# one "_", leading and trailing "_" trimmed, capped at 40 characters (and
# re-trimmed). Instance names end "+<slug>-<8 hex>" and session names are
# "<slug>-<8 hex>", so a worker is found by its topic without ever using a
# session id or an instance path from the record.
rd_slug() {
    printf '%s' "$1" | tr 'A-Z' 'a-z' | sed -E 's/[^a-z0-9]+/_/g; s/^_+//; s/_+$//' \
        | cut -c1-40 | sed -E 's/_+$//'
}

# rd_git ARGS... -- git that reads a worker's clone without running anything
# the clone's config names and without taking its index lock: no fsmonitor,
# no hooks, no transport. A caller that needs https (ls-remote) re-allows it.
rd_git() {
    git --no-optional-locks -c core.fsmonitor= -c core.hooksPath=/dev/null \
        -c protocol.allow=never "$@"
}

# rd_github_repo URL -- owner/repo for a github.com remote URL, https or ssh,
# or nothing for any other remote.
rd_github_repo() {
    local r
    case "$1" in
        https://github.com/*) r=${1#https://github.com/} ;;
        git@github.com:*) r=${1#git@github.com:} ;;
        ssh://git@github.com/*) r=${1#ssh://git@github.com/} ;;
        *) return 1 ;;
    esac
    r=${r%.git}
    rd_valid_repo "$r" || return 1
    printf '%s' "$r"
}

# rd_not_verified KIND REASON -- print a not_verified fact.
rd_not_verified() {
    jq -nc --arg k "$1" --arg r "$2" --arg t "$(rd_now)" \
        '{kind: $k, status: "not_verified", reason: $r, read_at: $t}'
}

# rd_urlencode_path PATH -- percent-encode each segment of a repository path
# for the contents API. Refuses (returns 1) a path that is empty, starts with
# "/", has an empty, "." or ".." segment, or holds any control character,
# newline and tab included.
rd_urlencode_path() {
    local p=$1
    case "$p" in ""|/*|*//*) return 1 ;; esac
    case "$p" in *[[:cntrl:]]*) return 1 ;; esac
    printf '%s' "$p" | jq -Rsr 'split("/")
        | if any(. == "" or . == "." or . == "..") then error("bad") else . end
        | map(@uri) | join("/")' 2>/dev/null
}
