#!/usr/bin/env bash
# coordinate-takeover-load_engine_test.sh -- a takeover of a run holding a
# long record, on a heavily loaded host, against real koto (0.28.0 or later,
# with `koto init --supersede`) and the shipped coordinate.md
# (docs/designs/DESIGN-coordinate-successor-continues.md, Decision 1: the
# fence and the carry are single koto calls a slow host must still finish).
#
# Proves, on a run A opened by one Claude session (a synthetic
# CLAUDE_CODE_SESSION_ID) holding 70 record entries, six open legs,
# taken_legs and leg_children, with the host's one-minute load average raised
# to 25 or more by busy-loop processes:
#   1. the load average read 25 or more as the takeover started;
#   2. the opener run by another Claude session from another directory prints
#      outcome=continued, predecessor=A and session=B;
#   3. every key A held under record/ (but record/meta and record/run, which
#      the takeover rewrites), legs/, taken_legs and leg_children is in B with
#      the same value, all 70 entries among them;
#   4. no single koto call the takeover made took 30 seconds or more (the
#      slowest is printed), timed by a koto stand-in (KOTO_BIN) that runs the
#      real koto and logs each call's wall time.
#
# It costs minutes of every core, so it runs on CI only (CI set, as hosted
# CI sets it), where the engine job runs it on Linux through run-tests.sh
# --engine. The load is read from /proc/loadavg, or from `sysctl -n
# vm.loadavg` on macOS, so a macOS runner with CI set runs it the same way.
# Anywhere else it prints SKIP and runs no case: a local check-skill.sh gate
# passes it without loading the host, and run-tests.sh --engine counts the
# skip as a failure, since the suite didn't run. CI=1 runs it on a host that
# can take the load. The busy loops are stopped on exit, whatever ends the
# suite, and as soon as the takeover returns.
#
# Every koto call runs under koto-test-guard.sh: a scratch HOME, every
# KOTO_SESSION_* name, KOTO_SESSIONS_BASE and KOTO_HOME unset, and the store
# asserted under the scratch directory. The Claude job directory is a fixture
# (DC_CLAUDE_HOME). Needs koto, jq and git; SKIPs (exit 0) without one, or on
# a koto without --supersede, which run-tests.sh --engine turns into a
# failure.
set -uo pipefail
. "$(dirname "$0")/../../../scripts/lib/koto-test-guard.sh" || exit 1
if [ -z "${CI:-}" ]; then
    echo "SKIP: the load suite raises this host's load average to 25 and runs on CI only (CI is unset here) -- no case ran"
    exit 0
fi
HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/testdata/coordinate-engine-lib.sh"
case "$(koto init --help 2>/dev/null)" in
    *--supersede*) ;;
    *) echo "SKIP: this koto has no init --supersede -- the load case did not run"; exit 0 ;;
esac
case "$(koto session dir probe)" in "$T"/*|"$KOTO_TEST_GUARD_DIR"/*) ;; *) echo "FAIL: the koto store is outside the scratch directory"; exit 1 ;; esac
REAL_KOTO=$(command -v koto)
WANT_LOAD=25
BUSY_PROCS=40
LOAD_WAIT=300
CALL_LIMIT_MS=30000

BUSY=
stop_load() { local p; for p in $BUSY; do kill "$p" 2>/dev/null; done; for p in $BUSY; do wait "$p" 2>/dev/null; done; BUSY=; }
trap 'stop_load; case "$T" in */coordinate-test.*) rm -rf "$T" ;; esac; case "${KOTO_TEST_GUARD_DIR:-}" in */suite-scratch.*) rm -rf "$KOTO_TEST_GUARD_DIR" ;; esac' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

load1() { # load1: the one-minute load average
    if [ -r /proc/loadavg ]; then cut -d' ' -f1 /proc/loadavg
    else { sysctl -n vm.loadavg 2>/dev/null || /usr/sbin/sysctl -n vm.loadavg; } | tr -d '{}' | awk '{ print $1 }'; fi
}
at_least() { awk -v a="$1" -v b="$2" 'BEGIN { exit !(a + 0 >= b + 0) }'; } # at_least <a> <b>: a >= b

A_ID=$(printf '%s-0000-4000-8000-%012d' aaaaaaaa 1)
B_ID=$(printf '%s-0000-4000-8000-%012d' bbbbbbbb 2)
export DC_CLAUDE_HOME="$T/claude"
mkdir -p "$DC_CLAUDE_HOME/jobs/job-b"
jq -n --arg s "$B_ID" '{sessionId: $s, name: "coord-b", state: "working"}' > "$DC_CLAUDE_HOME/jobs/job-b/state.json"
mkdir -p "$T/work2/.niwa" "$T/work2/.claude"
(cd "$T/work2" && git init -q && git remote add origin https://github.com/acme/widgets.git)
cp "$T/work/.niwa/instance.json" "$T/work2/.niwa/"; cp "$T/work/.claude/settings.json" "$T/work2/.claude/"

put() { printf '%s' "$3" > "$T/v.json"; (cd "$T/work" && koto context add "$1" "$2" --from-file "$T/v.json" >/dev/null); }
keyset() { # keyset <session>: every carried key but record/meta and record/run, and its value's digest
    local p k
    for p in record/ legs/ taken_legs leg_children; do
        (cd "$T/work" && koto context list "$1" --prefix "$p") | jq -r '.[]'
    done | grep -v '^record/meta$' | grep -v '^record/run$' | grep -v '^koto/' | sort -u | while read -r k; do
        printf '%s %s\n' "$k" "$( (cd "$T/work" && koto context get "$1" "$k") | $SHA256 | cut -d' ' -f1)"
    done
}

# The timing koto: the real one, each call's wall time in milliseconds and
# its arguments logged a line each.
mkdir -p "$T/kt"
cat > "$T/kt/koto" <<EOF
#!/usr/bin/env bash
REAL="$REAL_KOTO" LOG="$T/kt.log"
EOF
cat >> "$T/kt/koto" <<'EOF'
now_ms() {
    if [ -n "${EPOCHREALTIME-}" ]; then local t=${EPOCHREALTIME/[.,]/}; echo $((10#$t / 1000))
    elif command -v perl >/dev/null 2>&1; then perl -MTime::HiRes=time -e 'printf "%d\n", time() * 1000'
    else echo $(($(date +%s) * 1000)); fi
}
s=$(now_ms)
"$REAL" "$@"
rc=$?
e=$(now_ms)
printf '%s %s\n' "$((e - s))" "$*" >> "$LOG"
exit $rc
EOF
chmod +x "$T/kt/koto"

# ---- A: a run with a long record ------------------------------------------------------
export CLAUDE_CODE_SESSION_ID=$A_ID
three_features load; seed_record load
if open_run load && [ "$(at)" = reconcile ]; then
    A=$S
    ok "A: the run opens and reaches reconcile"
else
    bad "A: the run opens and reaches reconcile" "$(cat "$T/open.err" "$T/tick.err" 2>/dev/null)"
    echo; echo "coordinate-takeover-load engine: $PASS passed, $FAIL failed (no run to take over)"; exit 1
fi
# The entries as state-entry.sh writes them: record/entries/<n>, six digits,
# holding {n, stamp, kind, text}.
i=1
while [ $i -le 70 ]; do
    put "$A" "record/entries/$(printf '%06d' $i)" "$(jq -nc --argjson n $i --arg t "account line $i of a long run" '{n: $n, stamp: "2026-10-01T08:00:00Z", kind: "entry", text: $t}')"
    i=$((i + 1))
done
i=1
while [ $i -le 6 ]; do
    put "$A" "legs/req-a$i/work-on" "$(jq -nc --arg w "feat-$i" --arg r "req-a$i" '{worker: $w, request: $r}')"
    i=$((i + 1))
done
put "$A" taken_legs '["req-a1:work-on","req-a2:work-on","req-a3:work-on"]'
put "$A" leg_children '{"req-a1:work-on":"feat-1-session","req-a2:work-on":"feat-2-session","req-a3:work-on":"feat-3-session"}'
NE=$(cd "$T/work" && bash "$PS/state-entry.sh" --session "$A" --list 2>/dev/null | jq length)
[ "${NE:-0}" -ge 65 ] && ok "A: holds $NE record entries" || bad "A: holds at least 65 record entries" "${NE:-none}"
BASE=$(keyset "$A")
NB=$(grep -c . <<< "$BASE")
[ "$NB" -ge 80 ] && ok "A: holds $NB carried keys" || bad "A: holds at least 80 carried keys" "$NB"

# ---- the load ------------------------------------------------------------------------------
i=0
while [ $i -lt $BUSY_PROCS ]; do
    ( while :; do :; done ) &
    BUSY="$BUSY $!"
    i=$((i + 1))
done
SECONDS=0
L=$(load1)
while ! at_least "${L:-0}" "$WANT_LOAD" && [ $SECONDS -lt $LOAD_WAIT ]; do
    sleep 5
    L=$(load1)
done
echo "  note: the one-minute load average read ${L:-nothing} after ${SECONDS}s of $BUSY_PROCS busy loops"

# ---- 1-2. B takes A over on the loaded host -------------------------------------------------
export CLAUDE_CODE_SESSION_ID=$B_ID
: > "$T/kt.log"
START_LOAD=$(load1)
printf '["docs/roadmaps/ROADMAP-load.md"]' > "$T/args.json"
SECONDS=0
OUT=$(cd "$T/work2" && KOTO_BIN=$T/kt/koto bash "$PS/coordinate-open.sh" --plugin-root "$PR" "$T/args.json" 2>"$T/open.err"); ORC=$?
TOOK=$SECONDS
END_LOAD=$(load1)
stop_load
line() { sed -n "s/^$1=//p" <<< "$OUT"; }
if at_least "${START_LOAD:-0}" "$WANT_LOAD"; then ok "1: the load average was ${START_LOAD} (>= $WANT_LOAD) as the takeover started (${END_LOAD:-unread} as it ended)"
else bad "1: the load average was $WANT_LOAD or more as the takeover started" "${START_LOAD:-unread} after ${LOAD_WAIT}s of $BUSY_PROCS busy loops"; fi
eq "2: the takeover prints outcome=continued (in ${TOOK}s)" "0 continued" "$ORC $(line outcome)"
eq "2:   ... predecessor= naming A" "$A" "$(line predecessor)"
B=$(line session)
case "$B" in coordinate-roadmap-load-2*Z) [ "$B" != "$A" ] && ok "2:   ... session= naming a new run" || bad "2:   ... session= naming a new run" "$B" ;;
    *) bad "2:   ... session= naming a new run" "$OUT $(cat "$T/open.err")" ;; esac

# ---- 3. every carried key ------------------------------------------------------------------
if [ -n "$B" ]; then
    MISSING=$(grep -vxF -f <(keyset "$B") <<< "$BASE")
    eq "3: every key A held is in B with the same value" "" "$MISSING"
    eq "3:   ... all 70 entries among them" 70 "$(grep -c '^record/entries/' <<< "$BASE")"
fi

# ---- 4. no koto call took 30 seconds -------------------------------------------------------------
NCALLS=$(grep -c . "$T/kt.log")
SLOW=$(sort -k1,1n "$T/kt.log" | tail -n 1)
SLOW_MS=${SLOW%% *}
echo "  note: the takeover made $NCALLS koto calls; the slowest took ${SLOW_MS:-?} ms: ${SLOW#* }"
[ "$NCALLS" -gt 0 ] && ok "4: the takeover's koto calls were timed ($NCALLS)" || bad "4: the takeover's koto calls were timed" "none logged"
if [ -n "$SLOW_MS" ] && [ "$SLOW_MS" -lt "$CALL_LIMIT_MS" ]; then ok "4: no single koto call took 30 seconds or more (slowest ${SLOW_MS} ms)"
else bad "4: no single koto call took 30 seconds or more" "${SLOW_MS:-?} ms: ${SLOW#* }"; fi

echo; echo "coordinate-takeover-load engine: $PASS passed, $FAIL failed"; [ "$FAIL" -eq 0 ]
