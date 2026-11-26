#!/usr/bin/env bash
# resolve-coordinator_engine_test.sh -- a worker never gets an earlier
# member's coordinator while the newest member's takeover is still finishing,
# against real koto (with `koto init --supersede`).
#
# A run taken over twice is a chain A -> B -> C, each fenced by
# `koto init --continues --supersede`. B finished its takeover: its
# record/meta names {takeover: {predecessor: A}, takeover_done: true} and its
# Run coordinator row is its own. C is in its takeover window, the state
# coordinate-open.sh's finish_takeover leaves between its first record/meta
# write and its last: record/meta names {takeover: {predecessor: B},
# takeover_done: false}, and record/run is still the verbatim copy of B's,
# which `--carry record/` made. Proves:
#   1. a worker dispatched by A, before both takeovers: resolve-coordinator.sh A
#      exits 4 and prints no coordinator= line, so the worker uses its brief's
#      address instead of B's coordinator;
#   2. a worker dispatched by B, the middle member: in C's window
#      resolve-coordinator.sh B exits 4 with no coordinator= line, and still
#      does once C's own row is written while takeover_done is false; once C's
#      takeover_done is true it prints C's row (member=C), and so does A;
#   3. render-result.sh --dispatcher A in C's window carries no coordinator=
#      line.
#
# Every koto call runs under koto-test-guard.sh: a scratch HOME and KOTO_HOME,
# every KOTO_SESSION_* name and KOTO_SESSIONS_BASE unset, and the store
# asserted under the scratch directory. Needs koto and jq; SKIPs (exit 0)
# without one, which run-tests.sh --engine turns into a failure where it
# requires the suite. On a koto without --supersede (the entry floor) no run
# can be taken over, so every case needs one: it prints a line for each case it
# leaves out.
set -uo pipefail
. "$(dirname "$0")/../../../scripts/lib/koto-test-guard.sh" || exit 1
HERE=$(cd "$(dirname "$0")" && pwd)
command -v koto >/dev/null 2>&1 || { echo "SKIP: koto not on PATH"; exit 0; }
command -v jq >/dev/null 2>&1 || { echo "SKIP: jq not on PATH"; exit 0; }
. "$HERE/testdata/takeover-flags.sh"

T=$(mktemp -d "${TMPDIR:-/tmp}/resolve-coordinator.XXXXXX") || exit 1
T=$(cd "$T" && pwd -P)
ktg_on_exit 'case "$T" in */resolve-coordinator.*) rm -rf "$T" ;; esac'
export HOME="$T/home" KOTO_HOME="$T/koto-home" XDG_STATE_HOME="$T/state" XDG_DATA_HOME="$T/data"
unset GH_TOKEN GITHUB_TOKEN
mkdir -p "$HOME" "$T/w"
cd "$T/w" || exit 1
case "$(koto session dir probe)" in "$T"/*) ;; *) echo "FAIL: the koto store is outside the scratch directory"; exit 1 ;; esac

PASS=0 FAIL=0
ok()  { PASS=$((PASS + 1)); printf 'ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); printf 'FAIL %s\n     %s\n' "$1" "${2-}"; }
eq()  { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "want [$2], got [$3]"; fi; }
# no_line <case> <output>: the output carries no coordinator= line; one that
# does names an earlier member's coordinator.
no_line() {
    local got
    got=$(printf '%s\n' "$2" | grep '^coordinator=')
    if [ -z "$got" ]; then ok "$1"; else bad "$1" "printed an earlier member's coordinator: [$got]"; fi
}

cat > "$T/w/run.md" <<'TPL'
---
name: resolve-coordinator-fixture
version: "1.0"
initial_state: work
states:
  work:
    transitions:
      - target: end
  end:
    terminal: true
---
## work
Work.
## end
Done.
TPL
A=coordinate-roadmap-x-20261001T080000Z
B=coordinate-roadmap-x-20261002T080000Z
C=coordinate-roadmap-x-20261003T080000Z
put() { printf '%s' "$3" > "$T/v.json"; koto context add "$1" "$2" --from-file "$T/v.json" >/dev/null; }
meta() { # meta <predecessor|""> <takeover_done>
    if [ -z "$1" ]; then jq -nc '{scope: {kind: "roadmap", name: "x"}, store: "session"}'
    else jq -nc --arg p "$1" --argjson d "$2" '{scope: {kind: "roadmap", name: "x"}, store: "session", driver: "drv", takeover_done: $d, takeover: {predecessor: $p, predecessor_stopped: "yes"}}'; fi
}
row() { jq -nc --arg c "$1" '[{key: "coordinator", value: $c, set_by: $c, set: "2026-10-01T08:00Z"}]'; }

RC="$HERE/resolve-coordinator.sh"
koto init worker-1 --template run.md >/dev/null
if needs_takeover "1-3: a worker resolving its coordinator while C's takeover finishes"; then
    if koto init "$A" --template run.md >/dev/null \
        && put "$A" record/meta "$(meta "" false)" && put "$A" record/run "$(row coord-a)" \
        && koto init "$B" --template run.md --continues "$A" --supersede >/dev/null \
        && put "$B" record/meta "$(meta "$A" true)" && put "$B" record/run "$(row coord-b)" \
        && koto init "$C" --template run.md --continues "$B" --supersede >/dev/null \
        && put "$C" record/meta "$(meta "$B" false)" && put "$C" record/run "$(koto context get "$B" record/run)"; then
        ok "fixture: A -> B -> C fenced, C in its takeover window with B's row carried"
    else
        bad "fixture: the chain opens" ""
        echo; echo "resolve-coordinator-engine: $PASS passed, $FAIL failed"; exit 1
    fi

    echo "== 1. a worker dispatched by A, before both takeovers =="
    OUT=$(bash "$RC" "$A" 2>/dev/null); rc=$?
    eq "1: resolve-coordinator.sh A exits 4 in C's window" 4 "$rc"
    no_line "1: ... and prints no coordinator= line" "$OUT"

    echo "== 2. a worker dispatched by B, the middle member =="
    OUT=$(bash "$RC" "$B" 2>/dev/null); rc=$?
    eq "2: resolve-coordinator.sh B exits 4 in C's window" 4 "$rc"
    no_line "2: ... and prints no coordinator= line" "$OUT"
    put "$C" record/run "$(row coord-c)"
    OUT=$(bash "$RC" "$B" 2>/dev/null); rc=$?
    eq "2: with C's own row written and takeover_done false it still exits 4" 4 "$rc"
    eq "2: ... printing nothing" "" "$OUT"
    put "$C" record/meta "$(meta "$B" true)"
    OUT=$(bash "$RC" "$B" 2>/dev/null); rc=$?
    eq "2: once C's takeover_done is true, resolve-coordinator.sh B exits 0" 0 "$rc"
    eq "2: ... and prints C's row" "$(printf 'coordinator=coord-c\nmember=%s' "$C")" "$OUT"
    OUT=$(bash "$RC" "$A" 2>/dev/null); rc=$?
    eq "2: ... and resolve-coordinator.sh A prints C's row too" "0 coordinator=coord-c" "$rc $(printf '%s\n' "$OUT" | grep '^coordinator=')"

    echo "== 3. render-result.sh in C's window =="
    put "$C" record/meta "$(meta "$B" false)"
    put "$C" record/run "$(koto context get "$B" record/run)"
    OUT=$(bash "$HERE/render-result.sh" --session worker-1 --dispatcher "$A" 2>/dev/null); rc=$?
    eq "3: render-result.sh --dispatcher A exits 0" 0 "$rc"
    no_line "3: ... and its block carries no coordinator= line" "$OUT"
fi

echo
echo "resolve-coordinator-engine: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
