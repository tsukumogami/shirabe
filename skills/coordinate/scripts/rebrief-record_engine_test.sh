#!/usr/bin/env bash
# rebrief-record_engine_test.sh -- the re-brief step's three outcomes, driven
# through the shipped coordinate.md on real koto, from a run coordinate-open.sh
# opens (testdata/coordinate-engine-lib.sh), with the told and pending set
# printed after each (tsukumogami/shirabe#1245).
#
# From a run at wait whose one live holding's worker (feat-1) is told nothing
# at the current address, a report classified needs_fix reaches rebrief, and:
#   sent         goes through rebrief_record, which records feat-1 told with no
#                --told run by hand, and on to wait; the handover gate passes;
#   refused      goes straight to wait and records nothing; the gate keeps its
#                not-told gap;
#   worker_gone  goes through rebrief_record and back through pick: with niwa
#                still listing an instance for feat-1 it is recorded pending
#                and the gate passes; with none, nothing is recorded.
#
# The koto store is asserted under the suite's scratch directory before any
# case runs: koto-test-guard.sh clears every KOTO_SESSION_* variable,
# KOTO_SESSIONS_BASE and KOTO_HOME and makes HOME scratch, the lib moves HOME
# under its own $T, and KOTO_HOME is set to the store under it.
#
# Needs koto, jq and git; SKIPs (exit 0) without koto, which
# run-tests.sh --engine turns into a failure.
# Usage: bash skills/coordinate/scripts/rebrief-record_engine_test.sh
set -uo pipefail
. "$(dirname "$0")/../../../scripts/lib/koto-test-guard.sh" || exit 1

HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/testdata/coordinate-engine-lib.sh"
export KOTO_HOME="$HOME/.koto"

# A niwa stand-in whose listing is NIWA_LIST (an empty list unless set).
mkdir -p "$T/niwa-rb"
cat > "$T/niwa-rb/niwa" <<'EOF'
#!/usr/bin/env bash
[ "$1 ${2-}" = "list --json" ] || exit 2
printf '%s\n' "${NIWA_LIST:-[]}"
EOF
chmod +x "$T/niwa-rb/niwa"
export NIWA="$T/niwa-rb/niwa"

# told_set: the record's told and pending rows, printed and kept in TS.
told_set() {
    TS=$(live_body | jq -r '[(.run // [])[] | select(.key == "told" or .key == "pending") | "\(.key) \(.value)"] | join(", ")')
    echo "     told set: [${TS}]"
}
# gate: the handover gate's result, as the reconcile step runs it.
gate() {
    (cd "$WD" && bash "$PS/state-handover.sh" --session "$S" --check) >/dev/null 2>"$T/gate"
    G="$? $(sed -n 's/^  \([^:]*\): .*/\1/p' "$T/gate" | paste -sd, -)"
    echo "     gate: $G"
}
# to_rebrief: from the saved run at wait, a report classified needs_fix.
to_rebrief() {
    snap_load rb-wait || return 1
    at --with-data '{"event":"report","unit":"feat-1","report":"the tests fail"}' > /dev/null
    [ "$(at --with-data '{"classification":"needs_fix"}')" = rebrief ]
}

echo "== the re-brief's outcomes record told, pending or nothing =="
if empty_run rebrief; then
    case "$(cd "$WD" && koto session dir "$S")" in
        "$T"/*) ok "the koto store is under the suite's scratch directory" ;;
        *) bad "the koto store is under the suite's scratch directory" "$(cd "$WD" && koto session dir "$S")"; done_tests rebrief-record_engine; exit 1 ;;
    esac
    eq "every KOTO_SESSION_* variable and KOTO_SESSIONS_BASE are unset" "" \
        "$(env | sed -n 's/^\(KOTO_SESSION_[A-Za-z0-9_]*\|KOTO_SESSIONS_BASE\)=.*/\1/p')"
    # The holding is live (dispatched); a new address leaves its worker told
    # nothing.
    write_as_agent state-stored-set.sh --run coordinator coord-rebrief --by coord-rebrief
    told_set; gate
    eq "at the start: no told or pending row, and the gate holds on feat-1" "|1 not-told feat-1" "$TS|$G"
    snap_save rb-wait
else
    bad "reach wait with a live holding" "$(cat "$T/open.err" "$T/tick.err" 2>/dev/null)"
fi

echo "== sent =="
if to_rebrief; then
    eq "sent: rebrief_record records the worker and goes on to wait" wait "$(at --with-data '{"sent":"sent"}')"
    eq "  ... through rebrief_record" 1 "$(entered rebrief_record)"
    told_set; gate
    eq "  ... feat-1 told with no --told by hand, and the gate passes" "told feat-1|0 " "$TS|$G"
else
    bad "sent: reach rebrief" "$(cat "$T/tick.err" 2>/dev/null)"
fi

echo "== refused =="
if to_rebrief; then
    eq "refused: straight to wait" wait "$(at --with-data '{"sent":"refused"}')"
    eq "  ... never through rebrief_record" 0 "$(entered rebrief_record)"
    told_set; gate
    eq "  ... nothing recorded, and the gate keeps its not-told gap" "|1 not-told feat-1" "$TS|$G"
else
    bad "refused: reach rebrief" "$(cat "$T/tick.err" 2>/dev/null)"
fi

echo "== worker_gone, its instance still there =="
if to_rebrief; then
    : > "$T/work/.niwa/workspace.toml"
    export NIWA_LIST="[{\"session_name\":\"feat_1-0123abcd\",\"path\":\"$T/inst\"}]"
    ST=$(at --with-data '{"sent":"worker_gone"}')
    unset NIWA_LIST
    rm -f "$T/work/.niwa/workspace.toml"
    eq "worker_gone: through rebrief_record and back through pick" 1 "$(entered rebrief_record)"
    from_to rebrief_record pick_facts && ok "  ... rebrief_record goes on to pick_facts" || bad "  ... rebrief_record goes on to pick_facts" "$ST $(cat "$T/tick.err")"
    told_set; gate
    eq "  ... feat-1 recorded pending, and the gate passes" "pending feat-1|0 " "$TS|$G"
else
    bad "worker_gone: reach rebrief" "$(cat "$T/tick.err" 2>/dev/null)"
fi

echo "== worker_gone, no instance left =="
if to_rebrief; then
    : > "$T/work/.niwa/workspace.toml"
    ST=$(at --with-data '{"sent":"worker_gone"}')
    rm -f "$T/work/.niwa/workspace.toml"
    from_to rebrief_record pick_facts && ok "worker_gone with no instance: rebrief_record goes on to pick_facts" \
        || bad "worker_gone with no instance: rebrief_record goes on to pick_facts" "$ST $(cat "$T/tick.err")"
    told_set; gate
    eq "  ... nothing recorded, and the gate keeps its not-told gap" "|1 not-told feat-1" "$TS|$G"
else
    bad "worker_gone with no instance: reach rebrief" "$(cat "$T/tick.err" 2>/dev/null)"
fi

echo
echo "rebrief-record_engine: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
