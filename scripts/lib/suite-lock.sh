#!/usr/bin/env bash
# suite-lock.sh -- the host suite lock: one heavy local test suite at a time
# on a host, taken by code.
#
# Two suites running at once on one host push its load and memory up until
# both fail on timing, and koto's fixed action limit starts cutting checks
# that pass when the host is idle. Everything that starts a heavy suite
# (work-on's verification supervisor, check-skill.sh, red-first.sh's runs)
# takes this lock first and holds it for the suite's length. A second suite
# waits its turn, saying who holds the lock, for a bounded time.
#
# Source it, then:
#   sl_acquire <label> [<wait secs>]
#       Take a slot. 0 held (SL_INHERITED=1 when a caller up the process tree
#       already holds it, see below), 1 the wait passed its bound (SL_HOLDER
#       says who held it), 2 the lock could not be set up (a reason on
#       stderr). While it waits it prints, on stderr, one
#       `suite-lock: waiting for the host suite lock held by ...` line each
#       time the holder changes, and keeps the same line in SL_QUEUE_FILE when
#       that is set.
#   sl_release
#       Give the slot back. Safe to call when nothing is held.
#   sl_holders
#       One line per held slot: what holds it.
#
# Or run it: `suite-lock.sh status` prints sl_holders; `suite-lock.sh run
# [--wait <secs>] [--label <text>] -- <command> [<arg>...]` runs the command
# under the lock and exits with its status (75 when the wait passed its bound,
# 2 when the lock could not be set up). A repository's release check or any
# hand-run suite can be wrapped this way.
#
# Where: ${SHIRABE_SUITE_LOCK_DIR:-$HOME/.local/state/shirabe/suite-lock}, mode
# 0700. HOME and not XDG_STATE_HOME, because koto runs actions and gates with
# a cleared environment that keeps HOME: a supervisor koto started and a suite
# run by hand in a shell must find the same lock. It sits outside every
# repository, so every niwa instance and worktree of the user on the host
# shares it.
#
# How: slot-<n>.lock files under flock(2), n from 0 to SHIRABE_SUITE_LOCK_SLOTS
# - 1 (default 1, at most 8). The lock is held by a small keeper process (this
# file run as `__keep`), not by the caller: the keeper opens the slot, takes
# the flock without blocking, reports, and then waits for the caller's pid to
# go. So the suite's own processes never inherit the lock's descriptor, and a
# daemon a test leaves behind can't keep the host locked. The kernel drops an
# flock when its last descriptor closes, so a caller that crashes, or is
# killed with KILL, releases the slot within a second (the keeper's poll);
# there is no lock file to go stale. The try uses flock(1) where it is on PATH
# (Linux, Alpine's busybox), else perl's flock, else python3's.
#
# The holder's description (label, pid, start time) is written beside the slot
# as slot-<n>.holder once it is taken. It is only a description: whether a
# slot is held is the flock's answer, never the file's.
#
# Inheritance: after a take, SHIRABE_SUITE_LOCK_HELD names the lock directory
# in the environment, so a suite run under the lock that runs check-skill.sh
# again doesn't wait for itself. A caller whose environment names this
# directory takes nothing and releases nothing.
#
# SHIRABE_SUITE_LOCK=off turns the lock off (every take succeeds at once); the
# suites that test the scripts which take it set it, so a test's own nested
# runs never queue behind the host's real suites.
#
# Written for the bash 3.2 floor, without `set -e`.

SL_SLOT=""
SL_KEEPER=""
SL_INHERITED=0
SL_HOLDER=""

sl_dir() {
    if [ -n "${SHIRABE_SUITE_LOCK_DIR:-}" ]; then
        printf '%s\n' "$SHIRABE_SUITE_LOCK_DIR"
    elif [ -n "${HOME:-}" ]; then
        printf '%s\n' "$HOME/.local/state/shirabe/suite-lock"
    else
        return 1
    fi
}

sl_slots() {
    local n=${SHIRABE_SUITE_LOCK_SLOTS:-1}
    case "$n" in [1-8]) printf '%s\n' "$n" ;; *) printf '1\n' ;; esac
}

# sl_holders: what holds each held slot, one line each.
sl_holders() {
    local dir n i desc pid
    dir=$(sl_dir) || return 0
    n=$(sl_slots)
    i=0
    while [ "$i" -lt "$n" ]; do
        if [ -f "$dir/slot-$i.lock" ] && ! sl_free "$dir/slot-$i.lock"; then
            desc=$(head -n 1 "$dir/slot-$i.holder" 2>/dev/null)
            [ -n "$desc" ] || desc="an unknown holder"
            pid=$(sed -n 's/.*(pid \([0-9][0-9]*\),.*/\1/p' <<<"$desc")
            if [ -n "$pid" ] && ! kill -0 "$pid" 2>/dev/null; then
                desc="$desc; that process is gone, its keeper is releasing the slot"
            fi
            printf '%s\n' "$desc"
        fi
        i=$((i + 1))
    done
}

# sl_try_fd9: take the flock on descriptor 9 without blocking. 0 taken, 1
# held elsewhere, 2 no tool can take one.
sl_try_fd9() {
    if command -v flock >/dev/null 2>&1; then
        flock -n 9 && return 0
        return 1
    fi
    if command -v perl >/dev/null 2>&1; then
        perl -MFcntl=:flock -e 'open(my $f, ">&=", 9) or exit 2; exit(flock($f, LOCK_EX | LOCK_NB) ? 0 : 1)'
        return $?
    fi
    if command -v python3 >/dev/null 2>&1; then
        python3 -c 'import fcntl, sys
try:
    fcntl.flock(9, fcntl.LOCK_EX | fcntl.LOCK_NB)
except BlockingIOError:
    sys.exit(1)
except OSError:
    sys.exit(2)'
        return $?
    fi
    return 2
}

# sl_free <slot file>: true when nobody holds the slot (probed in a subshell,
# whose descriptor closes, and so releases, as it exits).
sl_free() {
    ( exec 9>>"$1" && sl_try_fd9 ) 2>/dev/null
}

# sl_keep <slot file> <watch pid>: the keeper. Prints `ok`, `busy` or `error`
# on its first line; on `ok` it holds the slot until <watch pid> is gone or it
# is killed.
sl_keep() {
    exec 9>>"$1" || { echo error; exit 2; }
    sl_try_fd9
    case $? in
        0) echo "ok $$" ;;
        1) echo busy; exit 1 ;;
        *) echo error; exit 2 ;;
    esac
    exec >/dev/null 2>&1 </dev/null
    trap 'exit 0' TERM HUP INT
    while kill -0 "$2" 2>/dev/null; do
        sleep 1
    done
    exit 0
}

# sl_take_slot <dir> <i> <label>: one non-blocking try at slot i. 0 taken
# (SL_SLOT and SL_KEEPER set), 1 busy, 2 setup failure.
sl_take_slot() {
    local file="$1/slot-$2.lock" line pid
    # The keeper is this file run as a program, so its pid is its own $$. It
    # is started in the background of the process substitution, which exits
    # at once, so the keeper is nobody's child here: a caller's bare `wait`
    # (check-skill.sh waits for its suites that way) never waits for it, and
    # it never waits for the caller, which would hold both forever.
    exec 8< <(bash "$SL_SELF" __keep "$file" "$$" 2>/dev/null </dev/null &)
    IFS=' ' read -r line pid <&8
    exec 8<&-
    case "$line" in
        ok)
            SL_SLOT=$2 SL_KEEPER=$pid
            return 0 ;;
        busy) return 1 ;;
    esac
    return 2
}

# sl_acquire <label> [<wait secs>]: see the header.
sl_acquire() {
    local label="$1" wait="${2:-${SHIRABE_SUITE_LOCK_WAIT_SECS:-3600}}" dir n i rc start since now said="" holders
    SL_INHERITED=0 SL_HOLDER=""
    [ -n "$SL_SLOT" ] && return 0
    if [ "${SHIRABE_SUITE_LOCK:-}" = off ]; then
        SL_INHERITED=1
        return 0
    fi
    dir=$(sl_dir) || { echo "suite-lock: neither SHIRABE_SUITE_LOCK_DIR nor HOME is set" >&2; return 2; }
    if [ "${SHIRABE_SUITE_LOCK_HELD:-}" = "$dir" ]; then
        SL_INHERITED=1
        return 0
    fi
    case "$wait" in ''|*[!0-9]*) wait=3600 ;; esac
    (umask 077 && mkdir -p "$dir") || { echo "suite-lock: cannot create $dir" >&2; return 2; }
    n=$(sl_slots)
    start=$(date +%s)
    since=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    while :; do
        i=0
        while [ "$i" -lt "$n" ]; do
            sl_take_slot "$dir" "$i" "$label"
            rc=$?
            if [ "$rc" -eq 0 ]; then
                printf '%s (pid %s, since %s)\n' "$label" "$$" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
                    > "$dir/slot-$i.holder" 2>/dev/null
                export SHIRABE_SUITE_LOCK_HELD="$dir"
                [ -n "$said" ] && echo "suite-lock: took the host suite lock after $(( $(date +%s) - start )) s" >&2
                [ -n "${SL_QUEUE_FILE:-}" ] && rm -f "$SL_QUEUE_FILE"
                return 0
            fi
            if [ "$rc" -eq 2 ]; then
                echo "suite-lock: cannot take a lock on $dir/slot-$i.lock (no flock, perl or python3 that can)" >&2
                return 2
            fi
            i=$((i + 1))
        done
        holders=$(sl_holders | paste -s -d ';' -)
        [ -n "$holders" ] || holders="a holder that just released it"
        SL_HOLDER=$holders
        now=$(date +%s)
        if [ $((now - start)) -ge "$wait" ]; then
            echo "suite-lock: gave up after waiting $((now - start)) s (bound $wait s) for the host suite lock held by $holders" >&2
            [ -n "${SL_QUEUE_FILE:-}" ] && rm -f "$SL_QUEUE_FILE"
            return 1
        fi
        if [ "$holders" != "$said" ]; then
            echo "suite-lock: waiting for the host suite lock held by $holders" >&2
            if [ -n "${SL_QUEUE_FILE:-}" ]; then
                printf 'waiting since %s for the host suite lock held by %s\n' "$since" "$holders" \
                    > "$SL_QUEUE_FILE.tmp" 2>/dev/null && mv -f "$SL_QUEUE_FILE.tmp" "$SL_QUEUE_FILE"
            fi
            said=$holders
        fi
        sleep "${SL_POLL_SECS:-2}"
    done
}

sl_release() {
    local dir
    [ -n "$SL_SLOT" ] || return 0
    [ -n "$SL_KEEPER" ] && kill "$SL_KEEPER" 2>/dev/null
    # The keeper exits at once on TERM; wait for the slot so a caller that
    # releases and exits never leaves it held behind it.
    local k=0
    while [ -n "$SL_KEEPER" ] && kill -0 "$SL_KEEPER" 2>/dev/null && [ "$k" -lt 50 ]; do
        sleep 0.1; k=$((k + 1))
    done
    # The description goes once the slot is free, so a waiter never reads a
    # held slot with no holder named.
    dir=$(sl_dir) && rm -f "$dir/slot-$SL_SLOT.holder"
    SL_SLOT="" SL_KEEPER=""
    unset SHIRABE_SUITE_LOCK_HELD
}

SL_SELF="${BASH_SOURCE[0]}"
case "$SL_SELF" in /*) ;; *) SL_SELF="$(cd "$(dirname "$SL_SELF")" && pwd)/$(basename "$SL_SELF")" ;; esac

# Run as a program.
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    case "${1:-}" in
        __keep)
            [ $# -eq 3 ] || exit 2
            sl_keep "$2" "$3" ;;
        status)
            sl_holders
            exit 0 ;;
        run)
            shift
            SL_RUN_WAIT="" SL_RUN_LABEL="suite-lock run"
            while [ $# -gt 0 ]; do
                case "$1" in
                    --wait) [ $# -ge 2 ] || exit 2; SL_RUN_WAIT=$2; shift 2 ;;
                    --label) [ $# -ge 2 ] || exit 2; SL_RUN_LABEL=$2; shift 2 ;;
                    --) shift; break ;;
                    *) echo "usage: suite-lock.sh run [--wait <secs>] [--label <text>] -- <command> [<arg>...]" >&2; exit 2 ;;
                esac
            done
            [ $# -ge 1 ] || { echo "suite-lock: run needs a command" >&2; exit 2; }
            sl_acquire "$SL_RUN_LABEL: $*" $SL_RUN_WAIT
            case $? in 0) ;; 1) exit 75 ;; *) exit 2 ;; esac
            "$@"
            SL_RC=$?
            sl_release
            exit "$SL_RC" ;;
        *)
            echo "usage: suite-lock.sh status | run [--wait <secs>] [--label <text>] -- <command> [<arg>...]" >&2
            exit 2 ;;
    esac
fi
