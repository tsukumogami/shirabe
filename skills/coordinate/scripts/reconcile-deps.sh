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
#   board-lib.sh's bl_merge_compare <repo> <pr> <sha>
#     Prints merged, unconfirmed or not-merged; returns 2 when a read failed.
#     The one merge-confirmation rule, shared with merge-confirm.sh and stated
#     in references/verification-checklist.md, "Confirming a Merge". Reached
#     through rd_merge_compare below.
#
# The checks are always the ones beside this file. There is no environment
# override: the environment of a tick is the agent's, and a variable that
# chose which board check runs would let it choose the verdict.
#
# A script that calls rd_deadline first calls rd_idle with a private
# directory of its own (see rd_idle below); without it every read returns 125.
# This file takes file descriptor 7 for that; inventory-common.sh's pool takes 9.
#
# Requires: bash 3.2+, jq, mkfifo, and pkill (procps on Linux, base system on
# macOS).

RD_HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

# The validators. coord-common.sh is sourced for its patterns and functions
# only; it defines, it doesn't run.
# coord-common.sh finds its own directory through COORD_SELF_DIR, which its
# callers set before sourcing it.
COORD_SELF_DIR=$(cd "$RD_HERE/../../execute/scripts" && pwd)
# shellcheck source=/dev/null
. "$COORD_SELF_DIR/coord-common.sh"

RD_BOARD_CHECK=$RD_HERE/board-verdict.sh
RD_DEFERRAL_CHECK=$RD_HERE/deferral-check.sh
# The one read of a repository's live refs, shared with teardown-inventory.sh.
RD_GITHUB_REFS=$RD_HERE/github-refs.sh
# The run's facts (scope, name, host): coord-log.sh.
RD_COORD_LOG=$RD_HERE/coord-log.sh
# The one reader of the record (record-source.sh): reconcile-read.sh reads
# the record through its rs_record.
# shellcheck source=/dev/null
. "$RD_HERE/record-source.sh"

rd_valid_repo()   { coord_valid_repo "$1" && [[ $1 != -* ]]; }
rd_valid_branch() { coord_valid_branch "$1"; }
rd_valid_sha()    { [[ $1 =~ $RE_COORD_SHA ]]; }
rd_valid_topic()  { [[ $1 =~ $RE_COORD_SLUG ]]; }
rd_valid_number() { [[ $1 =~ ^[1-9][0-9]{0,9}$ ]]; }
rd_valid_secs()   { [[ $1 =~ ^[1-9][0-9]{0,3}$ ]]; }

# rd_merge_compare SECS REPO PR SHA -- the record feature's merge check,
# bl_merge_compare, with its reads stopped by SECS (clipped to 1..24). It runs
# in a subshell, so board-lib.sh's names stay out of the caller's.
rd_merge_compare() {
    local secs=$1
    shift
    rd_valid_secs "$secs" || secs=8
    [ "$secs" -gt 24 ] && secs=24
    (
        HERE=$RD_HERE
        BOARD_DEADLINE_SECS=$secs
        # shellcheck source=/dev/null
        . "$RD_HERE/board-lib.sh" || exit 2
        bl_merge_compare "$@"
    )
}

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
#
# A read is most of what the reconcile pass does, so this costs as few
# processes as it can (shirabe#750): the watcher waits with `read -t` on a
# FIFO nobody writes to rather than a sleep(1), the markers are made by
# redirection, and the file's name is a tag for the shell and a counter in the
# caller's private directory rather than a mktemp per call. Only `cat` and
# `rm` run on every call, and pkill only when a deadline ends a command.
#
# The names are simple, so they rest on two rules. The directory is the
# caller's own, made by mktemp -d for this run (see rd_idle), so nothing
# outside the run can plant a file or a symlink at a name, and nothing left by
# an earlier run is found there. And no two calls running at once share a
# name: a counter bumped inside `$(...)` is lost when it returns, so calls
# from one shell reuse a name, which is safe only because each call removes its
# files before it returns and the next one starts. Any subshell that calls this
# while another shell can too (a background job, either side of a pipeline, a
# process substitution) must first set RD_SHELL to a tag of its own and RD_N to
# 0: reconcile-check.sh's inventory pool jobs (rc_job) do, and no other caller
# runs reads side by side.
#
# A read that can't be started because rd_idle failed (no mkfifo, no
# directory) returns 125 without running CMD: a failed read, which every
# caller treats as not verified. 125 is no reader's own code, so a caller
# that gives one of CMD's codes a meaning (koto's 2, "not found") never
# mistakes this for it.
RD_SHELL=m
RD_N=0
RD_IDLE=""
RD_DIR=""
# rd_idle DIR -- open the idle FIFO on fd 7 in DIR, once, so every subshell
# inherits it, and keep DIR for rd_deadline's files. DIR is the calling
# script's own private directory, which it removes on exit. A script that
# calls rd_deadline calls this in its main shell before its first read: a
# FIFO opened first inside a `$(...)` would be opened again by every call.
rd_idle() {
    [ -n "$RD_IDLE" ] && return 0
    [ -n "${1:-}" ] && [ -d "$1" ] || return 1
    mkfifo "$1/idle" && exec 7<>"$1/idle" || return 1
    RD_DIR=$1
    RD_IDLE=1
}
rd_deadline() {
    local secs=$1 pid watcher rc out
    shift
    rd_valid_secs "$secs" || secs=8
    [ -n "$RD_IDLE" ] || return 125
    RD_N=$((RD_N + 1))
    out="$RD_DIR/read.$RD_SHELL.$RD_N"
    # A name an interrupted call left files under is passed over, by builtin
    # tests so it costs no process: a stale .done would disable the deadline,
    # and a stale .late would force 124.
    while [ -e "$out" ] || [ -e "$out.done" ] || [ -e "$out.late" ]; do
        RD_N=$((RD_N + 1))
        out="$RD_DIR/read.$RD_SHELL.$RD_N"
    done
    "$@" > "$out" &
    pid=$!
    (
        read -r -t "$secs" _ <&7
        # CMD ended and the caller is stopping this watcher: nothing is late.
        [ -e "$out.done" ] && exit 0
        : > "$out.late"
        pkill -TERM -P "$pid" 2>/dev/null; kill -TERM "$pid" 2>/dev/null
        read -r -t 1 _ <&7
        pkill -KILL -P "$pid" 2>/dev/null; kill -KILL "$pid" 2>/dev/null
    ) >/dev/null 2>&1 &
    watcher=$!
    wait "$pid"
    rc=$?
    : > "$out.done"
    # The watcher waits in a builtin, so there's no sleep of its own to stop:
    # killing it is enough. If the deadline fired, a pkill it started may
    # outlive it by a moment; CMD has ended by then either way.
    kill "$watcher" 2>/dev/null
    wait "$watcher" 2>/dev/null
    [ -e "$out.late" ] && rc=124
    cat "$out"
    rm -f "$out" "$out.done" "$out.late"
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
# no hooks, no transport. GIT_ALLOW_PROTOCOL holds where `-c protocol.allow`
# alone doesn't, since a clone's own `protocol.<name>.allow` can widen that,
# and GIT_NO_LAZY_FETCH stops a partial clone fetching a missing object. The
# remote's refs are read by github-refs.sh (RD_GITHUB_REFS), never through here.
rd_git() {
    GIT_ALLOW_PROTOCOL=none GIT_NO_LAZY_FETCH=1 \
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
