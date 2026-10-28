#!/usr/bin/env bash
# newest-member_engine_test.sh -- a worker reaches its run's newest member
# after takeovers, and the cost sweep charges it, against real koto (with
# `koto init --supersede`).
#
# A run taken over twice is a chain A -> B -> C of koto sessions, each fenced
# by `koto init --continues --supersede`, holding record/meta and a Run
# coordinator row. The names and the fences disagree on purpose: C carries
# another scope slug than A and B, and a decoy run D carries A's slug and is
# live, so a lookup by name finds D, never C. Proves:
#   1. resolve-coordinator.sh A prints C's coordinator row and member=C;
#   2. a chain that can't be read (a dispatcher with no session) and a newest
#      member whose record/meta names another run each exit 1, printing
#      nothing, so the worker uses its brief's address;
#   3. past the hop cap (DC_HOP_CAP=1, two takeovers) it exits 3, printing
#      nothing;
#   4. render-result.sh --dispatcher A carries coordinator=<C's row>, and with
#      a dispatcher whose chain can't be read the block carries no such line;
#   5. unit-removed.sh's sweep, for a unit whose koto request A made, charges
#      C: the record's last outcome names C, not the decoy D.
#
# Every koto call runs under koto-test-guard.sh: a scratch HOME and KOTO_HOME,
# every KOTO_SESSION_* name and KOTO_SESSIONS_BASE unset, and the store
# asserted under the scratch directory. Needs koto and jq; SKIPs (exit 0)
# without one, or on a koto without --supersede, which run-tests.sh --engine
# turns into a failure where it requires the suite.
set -uo pipefail
. "$(dirname "$0")/../../../scripts/lib/koto-test-guard.sh" || exit 1
HERE=$(cd "$(dirname "$0")" && pwd)
command -v koto >/dev/null 2>&1 || { echo "SKIP: koto not on PATH"; exit 0; }
command -v jq >/dev/null 2>&1 || { echo "SKIP: jq not on PATH"; exit 0; }
case "$(koto init --help 2>/dev/null)" in *--supersede*) ;; *) echo "SKIP: koto lacks init --supersede"; exit 0 ;; esac

T=$(mktemp -d "${TMPDIR:-/tmp}/newest-member.XXXXXX") || exit 1
T=$(cd "$T" && pwd -P)
trap 'case "$T" in */newest-member.*) rm -rf "$T" ;; esac' EXIT
export HOME="$T/home" KOTO_HOME="$T/koto-home" XDG_STATE_HOME="$T/state" XDG_DATA_HOME="$T/data"
unset GH_TOKEN GITHUB_TOKEN
mkdir -p "$HOME" "$T/w"
cd "$T/w" || exit 1
case "$(koto session dir probe)" in "$T"/*) ;; *) echo "FAIL: the koto store is outside the scratch directory"; exit 1 ;; esac

PASS=0 FAIL=0
ok()  { PASS=$((PASS + 1)); printf 'ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); printf 'FAIL %s\n     %s\n' "$1" "${2-}"; }
eq()  { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "want [$2], got [$3]"; fi; }

cat > "$T/w/run.md" <<'TPL'
---
name: newest-member-fixture
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
C=coordinate-other-20261003T080000Z
D=coordinate-roadmap-x-20261004T080000Z
E=coordinate-roadmap-y-20261005T080000Z
F=coordinate-roadmap-y-20261006T080000Z
put() { printf '%s' "$3" > "$T/v.json"; koto context add "$1" "$2" --from-file "$T/v.json" >/dev/null; }
member() { # member <session> <roadmap name> <coordinator> [--continues <pred>]
    local s=$1 n=$2 c=$3
    shift 3
    if [ $# -gt 0 ]; then koto init "$s" --template run.md "$@" --supersede >/dev/null
    else koto init "$s" --template run.md >/dev/null; fi || return 1
    put "$s" record/meta "$(jq -nc --arg n "$n" '{scope: {kind: "roadmap", name: $n}, store: "session"}')"
    put "$s" record/run "$(jq -nc --arg c "$c" '[{key: "coordinator", value: $c, set_by: $c, set: "2026-10-01T08:00Z"}]')"
}
# A writes the leg key of the unit it dispatches before anyone takes it over:
# a fenced run takes no write.
if member "$A" x coord-a \
    && put "$A" legs/r_dispatch_x/deliver '{"request":"r_dispatch_x","leg":"deliver","topic":"feat-x","state":"taken"}' \
    && member "$B" x coord-b --continues "$A" && member "$C" x coord-c --continues "$B" \
    && member "$D" x coord-decoy && member "$E" y coord-e && member "$F" z coord-f --continues "$E"; then
    ok "fixture: A -> B -> C fenced, a decoy D on A's slug, and E -> F across two runs"
else
    bad "fixture: the chains open" ""
    echo; echo "newest-member-engine: $PASS passed, $FAIL failed"; exit 1
fi

RC="$HERE/resolve-coordinator.sh"
echo "== 1. a worker dispatched by A, after A -> B -> C =="
OUT=$(bash "$RC" "$A" 2>"$T/rc.err"); rc=$?
printf '%s\n' "$OUT"
eq "1: resolve-coordinator.sh A exits 0" 0 "$rc"
eq "1: ... printing C's coordinator row and C" "coordinator=coord-c member=$C" "$(printf '%s' "$OUT" | tr '\n' ' ' | sed 's/ $//')"

echo "== 2. a chain that can't be read, and a member of another run =="
OUT=$(bash "$RC" coordinate-roadmap-x-20261009T080000Z 2>"$T/rc.err"); rc=$?
printf 'exit %s: %s\n' "$rc" "$(cat "$T/rc.err")"
eq "2: an unreadable chain exits 1" 1 "$rc"
eq "2: ... printing nothing, so the brief's address is used" "" "$OUT"
OUT=$(bash "$RC" "$E" 2>"$T/rc.err"); rc=$?
printf 'exit %s: %s\n' "$rc" "$(cat "$T/rc.err")"
eq "2: a newest member whose record/meta names another run exits 1" 1 "$rc"
eq "2: ... printing nothing" "" "$OUT"

echo "== 3. past the hop cap =="
OUT=$(DC_HOP_CAP=1 bash "$RC" "$A" 2>"$T/rc.err"); rc=$?
printf 'exit %s: %s\n' "$rc" "$(cat "$T/rc.err")"
eq "3: two takeovers past a cap of one exit 3" 3 "$rc"
eq "3: ... printing nothing, so the brief's address is used" "" "$OUT"

echo "== 4. render-result.sh carries the resolved address =="
koto init worker-1 --template run.md >/dev/null
OUT=$(bash "$HERE/render-result.sh" --session worker-1 --dispatcher "$A" 2>/dev/null); rc=$?
printf '%s\n' "$OUT"
eq "4: render-result.sh exits 0" 0 "$rc"
eq "4: ... its block names C's coordinator" "coordinator=coord-c" "$(printf '%s\n' "$OUT" | grep '^coordinator=')"
OUT=$(bash "$HERE/render-result.sh" --session worker-1 --dispatcher coordinate-roadmap-x-20261009T080000Z 2>/dev/null); rc=$?
eq "4: with a chain that can't be read it still exits 0" 0 "$rc"
eq "4: ... and carries no coordinator line" "" "$(printf '%s\n' "$OUT" | grep '^coordinator=')"

echo "== 5. the cost sweep charges the newest member =="
FX="$HERE/testdata/unit-cost"
KEY=2026-10-01-feat-x-0a1b2c3d
IP="$T/ws/inst-feat-x"
mkdir -p "$IP" "$T/ksessions" "$T/requests"
export TEARDOWN_KOTO_SESSIONS="$T/ksessions" KOTO_REQUESTS="$T/requests"
for d in "$FX/archive/$KEY/koto"/*/; do
    n=$(basename "$d")
    cp -R "$d" "$T/ksessions/$n"
    f="$T/ksessions/$n/koto-$n.state.jsonl"
    { head -n 1 "$f" | jq -c --arg e "$IP" '.execution_dir = $e'; tail -n +2 "$f"; } >"$f.new" && mv "$f.new" "$f"
done
cp -R "$FX/requests/." "$T/requests/"
jq -c --arg s "$A" '.requested_by = $s' "$FX/requests/r_dispatch_x/request.jsonl" >"$T/requests/r_dispatch_x/request.jsonl"
R="$XDG_STATE_HOME/shirabe/removals"
mkdir -p "$R" && chmod 700 "$R"
jq -nc --arg p "$IP" '{schema: "unit-removal/1", dispatch_id: "dsp-feat-x.7", session_id: "0a1b2c3d-77aa",
    instance_path: $p, removed_at: "2026-10-01T10:00:00Z", attempts: 0, last: null}' >"$R/dsp-feat-x.7.json"
LIVE=$(bash "$HERE/coord-log.sh" live-session --scope-slug roadmap-x --all)
eq "5: a lookup by A's slug finds only the decoy" "$D" "$LIVE"
bash "$HERE/unit-removed.sh" sweep >"$T/sweep.out" 2>&1
cat "$T/sweep.out"
eq "5: the sweep charges C for the unit A dispatched" "$C" "$(jq -r '.last.coordinator // ""' "$R/dsp-feat-x.7.json" 2>/dev/null)"

echo
echo "newest-member-engine: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
