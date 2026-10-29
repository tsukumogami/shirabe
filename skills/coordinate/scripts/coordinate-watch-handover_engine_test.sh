#!/usr/bin/env bash
# coordinate-watch-handover_engine_test.sh -- a takeover moves the run's
# watch: the predecessor's `koto request watch` exits and the successor's,
# armed on the printed session=, hears the legs, against real koto (0.28.0 or
# later, with `koto init --supersede`) and the shipped coordinate.md.
#
# Each case opens a run A of its own scope as one Claude session and takes it
# over with coordinate-open.sh as another, from another directory:
#   1. a watch armed on A exits woke:true on the takeover, the opener prints
#      watcher=stopped, and A's next tick is refused session_superseded;
#   2. with no watch on A, watcher=absent;
#   3. with A's session naming another machine as its last writer (koto's
#      version.json, planted), watcher=unobserved;
#   4. leg_wake=supported on a koto 0.31.0 or later, unsupported on an older
#      one; and with KOTO_BIN a koto reporting 0.30.0, the takeover still
#      prints outcome=continued and leg_wake=unsupported;
#   5. a leg A opened before the takeover wakes a watch armed on the printed
#      session= within 10 seconds of its result (koto 0.31.0 and later).
#
# Every koto call runs under koto-test-guard.sh: a scratch HOME, every
# KOTO_SESSION_* name, KOTO_SESSIONS_BASE and KOTO_HOME unset, and the store
# asserted under the scratch directory. Every watch is armed on a session
# this suite opened in that store, and each is waited for or killed before
# the suite ends. Needs koto, jq and git; SKIPs (exit 0) without one, which
# run-tests.sh --engine turns into a failure. On a koto without --supersede
# every case is left out.
set -uo pipefail
. "$(dirname "$0")/../../../scripts/lib/koto-test-guard.sh" || exit 1
HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/testdata/coordinate-engine-lib.sh"
. "$HERE/testdata/takeover-flags.sh"
case "$(koto session dir probe)" in "$T"/*|"$KOTO_TEST_GUARD_DIR"/*) ;; *) echo "FAIL: the koto store is outside the scratch directory"; exit 1 ;; esac
needs_takeover "1-5: the takeover's watcher= and leg_wake=" || {
    echo; echo "coordinate-watch-handover engine: $PASS passed, $FAIL failed (this koto has no init --supersede)"
    [ "$FAIL" -eq 0 ]; exit
}

# Synthetic Claude session ids, built here so no id-shaped literal ships.
A_ID=$(printf '%s-0000-4000-8000-%012d' aaaaaaaa 1)
B_ID=$(printf '%s-0000-4000-8000-%012d' bbbbbbbb 2)
export DC_CLAUDE_HOME="$T/claude"
mkdir -p "$DC_CLAUDE_HOME/jobs/job-b"
jq -n --arg s "$B_ID" '{sessionId: $s, name: "coord-b", state: "working"}' > "$DC_CLAUDE_HOME/jobs/job-b/state.json"
mkdir -p "$T/work2/.niwa" "$T/work2/.claude"
(cd "$T/work2" && git init -q && git remote add origin https://github.com/acme/widgets.git)
cp "$T/work/.niwa/instance.json" "$T/work2/.niwa/"; cp "$T/work/.claude/settings.json" "$T/work2/.claude/"

opener() { # opener <name> <workdir>: coordinate-open.sh as the agent runs it; OUT its stdout, ORC its exit
    printf '["docs/roadmaps/ROADMAP-%s.md"]' "$1" > "$T/args.json"
    OUT=$(cd "$2" && bash "$PS/coordinate-open.sh" --plugin-root "$PR" "$T/args.json" 2>"$T/open.err"); ORC=$?
}
line() { printf '%s\n' "$OUT" | sed -n "s/^$1=//p"; }
run_a() { # run_a <name>: a run of its own scope, opened and at reconcile as A's Claude session; sets A
    export CLAUDE_CODE_SESSION_ID=$A_ID
    three_features "$1"; seed_record "$1"
    A=
    if open_run "$1" && [ "$(at)" = reconcile ]; then A=$S; return 0; fi
    bad "$1: A opens and reaches reconcile" "$(cat "$T/open.err" "$T/tick.err" 2>/dev/null)"
    return 1
}
take_over() { export CLAUDE_CODE_SESSION_ID=$B_ID; opener "$1" "$T/work2"; } # take_over <name>: B's opener
watching() { # watching <session>: a watch on it shows in ps within 2 seconds
    local i=0 procs
    while [ $i -lt 20 ]; do
        procs=$(ps -A -o args=)
        case "$procs" in *"request watch --session $1 "*) return 0 ;; esac
        sleep 0.1; i=$((i + 1))
    done
    return 1
}
# What leg_wake= should read on this koto: koto 0.31.0 follows supersede
# events when it rings (koto#510).
KV=$(koto version | sed -n '1s/^koto \([0-9][0-9]*\)\.\([0-9][0-9]*\)\..*/\1 \2/p')
read -r KMA KMI <<EOF
$KV
EOF
if [ "${KMA:-0}" -gt 0 ] || [ "${KMI:-0}" -ge 31 ]; then WANT_WAKE=supported; else WANT_WAKE=unsupported; fi

# ---- 1. a watch armed on A exits, A's next tick is refused ------------------------
if run_a watch-stopped; then
    koto request watch --session "$A" --timeout-secs 60 > "$T/wa.out" 2>&1 &
    WA=$!
    watching "$A" && ok "1: the watch on A is armed" || bad "1: the watch on A is armed" "$(cat "$T/wa.out")"
    take_over watch-stopped
    eq "1: the takeover continues A" "0 continued $A" "$ORC $(line outcome) $(line predecessor)"
    B1=$(line session)
    eq "1: watcher=stopped" stopped "$(line watcher)"
    eq "1: leg_wake= reads the koto version" "$WANT_WAKE" "$(line leg_wake)"
    wait "$WA"
    eq "1: A's watch exited on a wake, not its bound" true "$(jq -r .woke "$T/wa.out" 2>/dev/null)"
    NEXT=$( (cd "$WD" && koto next "$A" --no-cleanup) 2>&1); NRC=$?
    case "$NRC:$NEXT" in
        0:*) bad "1: A's next tick is refused" "$NEXT" ;;
        *session_superseded*) ok "1: A's next tick is refused session_superseded" ;;
        *) bad "1: A's next tick is refused session_superseded" "$NEXT" ;;
    esac
    case "$NEXT" in *"$B1"*) ok "1:   ... naming B" ;; *) bad "1:   ... naming B" "$NEXT" ;; esac
fi

# ---- 2. no watch on A -------------------------------------------------------------
if run_a watch-absent; then
    take_over watch-absent
    eq "2: the takeover continues A" "0 continued" "$ORC $(line outcome)"
    eq "2: watcher=absent" absent "$(line watcher)"
fi

# ---- 3. A's last writer is another host ------------------------------------------
if run_a watch-elsewhere; then
    jq -n '{version: 3, last_sync_base: 3, machine_id: "0f0f0f0f"}' > "$(koto session dir "$A")/version.json"
    take_over watch-elsewhere
    eq "3: the takeover continues A" "0 continued" "$ORC $(line outcome)"
    eq "3: watcher=unobserved" unobserved "$(line watcher)"
fi

# ---- 4. a koto without ring forwarding still takes over ---------------------------
if run_a watch-oldkoto; then
    REAL=$(command -v koto)
    mkdir -p "$T/oldkoto"
    printf '#!/usr/bin/env bash\n[ "${1:-}" = version ] && { echo "koto 0.30.0 (stub)"; exit 0; }\nexec %q "$@"\n' "$REAL" > "$T/oldkoto/koto"
    chmod +x "$T/oldkoto/koto"
    KOTO_BIN="$T/oldkoto/koto" take_over watch-oldkoto
    eq "4: a koto reporting 0.30.0 still takes A over" "0 continued $A" "$ORC $(line outcome) $(line predecessor)"
    eq "4: leg_wake=unsupported" unsupported "$(line leg_wake)"
    eq "4: watcher=absent" absent "$(line watcher)"
fi

# ---- 5. a leg A opened wakes the watch armed on session= --------------------------
if [ "$WANT_WAKE" = unsupported ]; then
    echo "left out 5: this koto ($KMA.$KMI) doesn't follow supersede events when it rings"
elif run_a watch-leg; then
    REQ=$(koto request create --role deliver --template deliver.md --inputs '{"TOPIC":"leg"}' \
        --requested-by "$A" --coordinator-of-record coordinate-watch-leg | jq -r .request_id)
    [ -n "$REQ" ] && ok "5: A opens a leg" || bad "5: A opens a leg" "$REQ"
    take_over watch-leg
    B5=$(line session)
    eq "5: the takeover continues A" "0 continued" "$ORC $(line outcome)"
    koto request watch --session "$B5" --timeout-secs 30 > "$T/wb.out" 2>&1 &
    WB=$!
    watching "$B5" && ok "5: the watch on session= is armed" || bad "5: the watch on session= is armed" "$(cat "$T/wb.out")"
    T0=$(date +%s)
    koto request resolve "$REQ" deliver --with-data '{"status":"success","summary":"done","payload":{}}' > /dev/null 2>"$T/res.err" \
        || bad "5: the leg resolves" "$(cat "$T/res.err")"
    wait "$WB"
    T1=$(date +%s)
    eq "5: B's watch wakes on the leg A opened" true "$(jq -r .woke "$T/wb.out" 2>/dev/null)"
    [ $((T1 - T0)) -le 10 ] && ok "5:   ... within 10 seconds of its result ($((T1 - T0))s)" \
        || bad "5:   ... within 10 seconds of its result" "$((T1 - T0))s"
fi

for p in $(jobs -p); do kill "$p" 2>/dev/null; done
echo
echo "coordinate-watch-handover engine: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
