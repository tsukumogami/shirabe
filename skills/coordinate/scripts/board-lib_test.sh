#!/usr/bin/env bash
# board-lib_test.sh -- bl_gh's deadline: a quick read leaves nothing of its
# deadline running, a TERM dropped as the deadline's watcher installs its
# trap doesn't hold the read until the deadline, and a read past the deadline
# fails as `deadline`. bl_posture_merge reads the merge step of a token that
# ends with a release step.
#
# gh is a shell function here, so nothing leaves the host.
#
# Usage: bash skills/coordinate/scripts/board-lib_test.sh
# Exit codes: 0 all pass; 1 a failure. bash 3.2.
set -uo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
PROG=board-lib-test
# shellcheck source=board-lib.sh
. "$HERE/board-lib.sh"

T=$(mktemp -d "${TMPDIR:-/tmp}/board-lib-test.XXXXXX") || exit 1
trap 'case "$T" in */board-lib-test.*) rm -rf "$T" ;; esac' EXIT

PASS=0
FAIL=0
ok()  { PASS=$((PASS + 1)); printf 'ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); printf 'FAIL %s\n     %s\n' "$1" "${2-}"; }
eq()  { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "want [$2], got [$3]"; fi; }

# --- a quick read leaves no sleep behind ----------------------------------------------

# Every sleep the deadline starts for a read runs for the seconds left of 23
# here: 23, or less when SECONDS ticks over between BL_START and the read, or
# the host is slow. This stand-in records that sleep's pid before it execs
# sleep (keeping that pid), so the check needs no ps: each recorded pid must
# be gone the moment bl_gh returns. The deadline runs the sleep in the
# background, where the exec replaces only that background process. A sleep
# stopped before it records anything is gone too, so a read may record none.
export BOARD_DEADLINE_SECS=23
BL_DEADLINE=23
# is_deadline_sleep <arg>: a whole number of seconds from 10 to 23, which no
# other sleep here uses (the deadline's own checks sleep 0.05, a retry 1).
is_deadline_sleep() { case "$1" in 1[0-9] | 2[0-3]) return 0 ;; esac; return 1; }
# sleeps_left <case>: fails the case for each recorded sleep still running,
# and kills it, since one that ignores TERM would outlive the suite.
sleeps_left() {
    local p left=""
    while read -r p; do
        kill -0 "$p" 2>/dev/null && left="$left $p"
    done <"$T/sleeps"
    if [ -n "$left" ]; then
        bad "$1" "still running:$left"
        for p in $left; do kill -KILL "$p" 2>/dev/null; done
    else
        ok "$1"
    fi
}
# bash drops a TERM that reaches the sleep before it execs (the forked child
# still runs its parent's trap). A sleep that ignores TERM stands in for that
# one, and gh ends only once the sleep is running, so the deadline has to stop
# it after the read; gh fails the case if the sleep never starts.
sleep() {
    if is_deadline_sleep "$1"; then exec sh -c 'trap "" TERM; echo $$ >>"$0"; exec sleep "$1"' "$T/sleeps" "$1"; fi
    command sleep "$@"
}
gh() { local i=0; until [ -s "$T/sleeps" ]; do [ "$i" -ge 50 ] && return 1; command sleep 0.1; i=$((i + 1)); done; }
: >"$T/sleeps"
BL_START=$SECONDS
bl_gh "$T/out" api x
eq "a read whose deadline sleep ignores TERM returns 0" 0 "$?"
sleeps_left "no deadline sleep left running when it ignores TERM"
# A gh that returns at once is the case that left the old watchdog's sleep
# running most often: its TERM landed before the watchdog had the sleep's pid.
sleep() {
    if is_deadline_sleep "$1"; then exec sh -c 'echo $$ >>"$0"; exec sleep "$1"' "$T/sleeps" "$1"; fi
    command sleep "$@"
}
gh() { :; }
: >"$T/sleeps"
RCS=""
i=0
while [ "$i" -lt 30 ]; do
    BL_START=$SECONDS
    bl_gh "$T/out" api x || RCS="$RCS $i"
    i=$((i + 1))
done
unset -f sleep gh
eq "30 quick reads return 0" "" "$RCS"
sleeps_left "30 quick reads leave no deadline sleep running"

# --- a TERM dropped as the watcher's trap goes in -------------------------------------

# bash ignores a TERM that reaches a shell while `trap` installs its handler.
# A watcher that ignores TERM for a second before its trap goes in stands in
# for that, and the read ends once the watcher is inside that second, so the
# first TERM to the watcher is the one dropped. The read still returns well
# before its 20-second deadline. gh fails the case if the watcher never gets
# there.
export BOARD_DEADLINE_SECS=20
BL_DEADLINE=20
trap() { builtin trap '' TERM; : >"$T/ignoring"; command sleep 1; builtin trap "$@"; }
gh() { local i=0; until [ -e "$T/ignoring" ]; do [ "$i" -ge 50 ] && return 1; command sleep 0.1; i=$((i + 1)); done; }
BL_START=$SECONDS
START=$(date +%s)
bl_gh "$T/out" api x
RC=$?
unset -f trap gh
if [ "$RC" -eq 0 ] && [ $(( $(date +%s) - START )) -lt 10 ]; then
    ok "a TERM the watcher drops as its trap goes in doesn't hold the read"
else
    bad "a TERM the watcher drops as its trap goes in doesn't hold the read" "status $RC after $(( $(date +%s) - START ))s"
fi

# --- a read past the deadline ---------------------------------------------------------

export BOARD_DEADLINE_SECS=2
BL_DEADLINE=2
# The read runs in the background, so exec leaves nothing behind it.
gh() { exec sleep 30; }
BL_START=$SECONDS
START=$(date +%s)
bl_gh "$T/out" api x
RC=$?
unset -f gh
eq "a read past the deadline fails" 1 "$RC"
eq "a read past the deadline is named deadline" deadline "$(cat "$T/out.fail" 2>/dev/null)"
if [ $(( $(date +%s) - START )) -lt 10 ]; then ok "a read past the deadline stops at the deadline"; else bad "a read past the deadline stops at the deadline" ""; fi

# --- the posture token's merge step ---------------------------------------------------

# posture-read.sh's token ends with a release step; the merge step reads the same.
eq "the merge step of a four-step token" deny "$(bl_posture_merge 'readable merge:deny close:permit teardown:permit release:permit')"
eq "the merge step beside an unread release" permit "$(bl_posture_merge 'unread merge:permit close:unread teardown:unread release:unread')"
eq "the merge step with = as the separator" confirm "$(bl_posture_merge 'readable merge=confirm close=permit teardown=permit release=confirm')"

printf '\nboard-lib: %d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
