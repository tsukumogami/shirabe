#!/usr/bin/env bash
# archive-common_test.sh -- archive-common.sh's post lock (ac_lock and
# ac_unlock), driven directly by processes that each source the file, as
# unit-cost.sh and unit-removed.sh do.
#
# Covers: a free lock taken and released; a lock whose holder is gone taken
# over; a lock a live process holds waited out, left in place, and named in
# AC_WHY; ac_unlock leaving another process's lock alone; and a holder that
# stalls inside ac_lock while a second process arrives, which must not leave
# both holding the lock.
#
# The stall case is stepped, not timed. The stalled holder runs with a `date`
# stand-in first on PATH that marks the call and then blocks until the suite
# lets it go; every taker runs with a `sleep` stand-in that returns at once,
# so a waiter's one-second steps cost nothing and its decisions don't depend
# on how fast the machine is. The suite starts the second process only once
# the holder is blocked, lets the holder go only once the second process has
# decided, and then counts the processes that came out of ac_lock holding it.
#
# Usage: bash skills/coordinate/scripts/archive-common_test.sh
set -uo pipefail
. "$(dirname "$0")/../../../scripts/lib/koto-test-guard.sh" || exit 1

HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/testdata/test-lib.sh"
AC="$HERE/archive-common.sh"
REAL_DATE=$(command -v date)
REAL_SLEEP=$(command -v sleep)

# The `sleep` every taker sees: no wait at all.
mkdir -p "$T/fast" "$T/gated"
printf '#!/bin/sh\nexit 0\n' >"$T/fast/sleep"
# The stalled holder's `date`: marks the call, then waits for $T/go.
cat >"$T/gated/date" <<EOF
#!/bin/sh
: >'$T/dated'
while [ ! -e '$T/go' ]; do '$REAL_SLEEP' 0.05; done
exec '$REAL_DATE' "\$@"
EOF
chmod +x "$T/fast/sleep" "$T/gated/date"

# taker <lock> <name> <wait secs>: a process that sources archive-common.sh and
# runs ac_lock on <lock> with a 60-second max age. It writes `<rc> <AC_WHY>` to
# $T/<name>.rc; holding the lock, it keeps it until $T/<name>.release exists,
# then runs ac_unlock.
cat >"$T/taker" <<EOF
#!/usr/bin/env bash
. '$AC' || exit 1
ac_lock "\$1" 60 "\$3"
rc=\$?
printf '%s %s\n' "\$rc" "\$AC_WHY" >'$T/'"\$2.rc.new"
mv '$T/'"\$2.rc.new" '$T/'"\$2.rc"
[ "\$rc" -eq 0 ] || exit 0
i=0
while [ ! -e '$T/'"\$2.release" ] && [ "\$i" -lt 600 ]; do '$REAL_SLEEP' 0.05; i=\$((i + 1)); done
ac_unlock "\$1"
EOF

# wait_for <path>: up to 30 seconds for <path> to exist. Only a bound: no case
# depends on it running out.
wait_for() {
    local i=0
    until [ -e "$1" ] || [ "$i" -ge 300 ]; do sleep 0.1; i=$((i + 1)); done
    [ -e "$1" ]
}
there() { if [ -e "$1" ] || [ -L "$1" ]; then echo yes; else echo no; fi; }
rc_of() { cut -d' ' -f1 "$T/$1.rc" 2>/dev/null; }
why_of() { cut -d' ' -f2- "$T/$1.rc" 2>/dev/null; }
fresh() { rm -rf "$T/l" "$T"/*.rc "$T"/*.release "$T/dated" "$T/go"; mkdir -p "$T/l"; L="$T/l/.post-lock"; }

echo "== a free lock =="
fresh
PATH="$T/fast:$PATH" bash "$T/taker" "$L" a 0 &
P=$!
wait_for "$T/a.rc"
eq "a free lock is taken" 0 "$(rc_of a)"
PATH="$T/fast:$PATH" bash "$T/taker" "$L" b 0
eq "  ... and a second process, not waiting, is held out of it" 1 "$(rc_of b)"
case "$(why_of b)" in *"held by process $P"*) ok "  ... naming the holder" ;; *) bad "  ... naming the holder" "$(why_of b)" ;; esac
touch "$T/a.release"; wait "$P"
eq "  ... released, no lock is left" no "$(there "$L")"

echo "== a holder that is gone =="
fresh
# The holder takes the lock and exits without releasing it.
PATH="$T/fast:$PATH" bash -c '. "$1" && ac_lock "$2" 60 0' _ "$AC" "$L"
eq "a process that took the lock and exited leaves it" yes "$(there "$L")"
PATH="$T/fast:$PATH" bash "$T/taker" "$L" a 0 &
P=$!
wait_for "$T/a.rc"
eq "  ... and the next process takes it over" 0 "$(rc_of a)"
touch "$T/a.release"; wait "$P"
eq "  ... released, no lock is left" no "$(there "$L")"

echo "== a live holder =="
fresh
PATH="$T/fast:$PATH" bash "$T/taker" "$L" a 0 &
P=$!
wait_for "$T/a.rc"
PATH="$T/fast:$PATH" bash "$T/taker" "$L" b 3
eq "a lock a live process holds is waited out, then refused" 1 "$(rc_of b)"
eq "  ... and left in place" yes "$(there "$L")"
# ac_unlock from a process that doesn't hold it changes nothing.
PATH="$T/fast:$PATH" bash -c '. "$1" && ac_unlock "$2"' _ "$AC" "$L"
eq "ac_unlock by another process leaves the holder's lock" yes "$(there "$L")"
touch "$T/a.release"; wait "$P"
eq "  ... and the holder's own release removes it" no "$(there "$L")"

echo "== a holder that stalls inside ac_lock =="
# The issue: "the lock can admit two holders when they arrive close together".
# The first process stalls at its first `date` call inside ac_lock; the second
# arrives while it is stalled and decides; then the first goes on. At most one
# of them may come out of ac_lock holding the lock.
fresh
PATH="$T/gated:$T/fast:$PATH" bash "$T/taker" "$L" first 3 &
P1=$!
wait_for "$T/dated" || bad "the first process reached date" "it never did"
PATH="$T/fast:$PATH" bash "$T/taker" "$L" second 3 &
P2=$!
wait_for "$T/second.rc" || bad "the second process decided" "it never did"
touch "$T/go"
wait_for "$T/first.rc" || bad "the first process decided" "it never did"
eq "a stalled holder and a second arrival: the lock does not admit two holders" 1 \
    "$(cat "$T/first.rc" "$T/second.rc" | cut -d' ' -f1 | grep -c '^0$')"
touch "$T/first.release" "$T/second.release"
wait "$P1"; wait "$P2"
eq "  ... released, no lock is left" no "$(there "$L")"

done_tests archive-common
