#!/usr/bin/env bash
# handover-classify_engine_test.sh -- the handover classifies each worker the
# current coordinator address hasn't reached, the shipped coordinate.md driven
# through real koto (docs/designs/DESIGN-coordinate-successor-continues.md,
# Decision 4; PRD R15).
#
# A run holds three dispatched workers and has told none of them its address.
# A niwa stand-in lists an instance for feat-1 and feat-2 and none for feat-3;
# feat-1's instance holds a running koto session driven by a working Claude
# job, and feat-2's holds no koto session and a Claude job that is done
# (DC_CLAUDE_HOME). Proves:
#   1. handover-classify.sh refuses a call with no session (64), and a record
#      with no coordinator row (2), recording nothing;
#   2. with the coordinator row set, the handover gate holds the run at
#      reconcile; the classification prints `live feat-1 <address>`,
#      `pending feat-2` and `missing feat-3`, records feat-2 pending and
#      nobody told;
#   3. the live worker told its address (the agent's --told), the gate's gap
#      is feat-3's alone; a second classification prints `missing feat-3`
#      only, and feat-2 stays pending while it hasn't reported;
#   4. with feat-3 recorded told by the fixture, the gate passes with feat-2
#      pending: the run reaches pick, and wait after a hold. feat-2's first
#      report at wait turns it told on the next classification, which prints
#      `told feat-2`; one more prints nothing.
#
# Every koto call runs under koto-test-guard.sh: a scratch HOME and KOTO_HOME,
# every KOTO_SESSION_* name and KOTO_SESSIONS_BASE unset, and the store
# asserted under the scratch directory. Needs koto, jq and git; SKIPs (exit 0)
# without one, which run-tests.sh --engine turns into a failure.
# Usage: bash skills/coordinate/scripts/handover-classify_engine_test.sh
set -uo pipefail
. "$(dirname "$0")/../../../scripts/lib/koto-test-guard.sh" || exit 1
HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/testdata/coordinate-engine-lib.sh"
case "$(koto session dir probe)" in "$T"/*|"$KOTO_TEST_GUARD_DIR"/*) ;; *) echo "FAIL: the koto store is outside the scratch directory"; exit 1 ;; esac

HC="$PS/handover-classify.sh"
classify() { # classify: handover-classify.sh from $WD, as the agent runs it at reconcile; HC_OUT, HC_ERR, HC_RC
    : > "$WD/.niwa/workspace.toml"
    HC_OUT=$(cd "$WD" && NIWA="$T/niwa-bin/niwa" bash "$HC" --session "$S" 2>"$T/hc.err"); HC_RC=$?
    HC_ERR=$(cat "$T/hc.err")
    rm -f "$WD/.niwa/workspace.toml"
}
run_rows() { live_body | jq -r '[(.run // [])[] | select(.key == "told" or .key == "pending") | "\(.key):\(.value)"] | sort | join(" ")'; }
gaps() { (cd "$WD" && bash "$PS/state-handover.sh" --session "$S") | jq -r '[.gaps[].gap] | join("|")'; }

# niwa: `list --json` names an instance for feat-1 and feat-2, each a directory
# under ws/, and none for feat-3.
# The session names and job ids are built here, so no id-shaped literal ships.
N1=$(printf 'feat_1-%s' 0a1a1a1a) N2=$(printf 'feat_2-%s' 0b2b2b2b)
J1=$(printf '%s%s' a1a1 a1a1) J2=$(printf '%s%s' b2b2 b2b2)
mkdir -p "$T/niwa-bin" "$T/ws/feat-1" "$T/ws/feat-2"
jq -n --arg a "$T/ws/feat-1" --arg b "$T/ws/feat-2" --arg n1 "$N1" --arg n2 "$N2" \
    '[{name: "feat-1", path: $a, session_name: $n1}, {name: "feat-2", path: $b, session_name: $n2}]' > "$T/niwa-list.json"
cat > "$T/niwa-bin/niwa" <<EOF
#!/usr/bin/env bash
case "\$*" in
    "list --json") cat "$T/niwa-list.json" ;;
    *) echo "niwa stand-in: unexpected call: \$*" >&2; exit 1 ;;
esac
EOF
chmod +x "$T/niwa-bin/niwa"

# The Claude jobs: feat-1's is working, feat-2's is done.
export DC_CLAUDE_HOME="$T/claude"
mkdir -p "$DC_CLAUDE_HOME/jobs/$J1" "$DC_CLAUDE_HOME/jobs/$J2"
jq -n --arg n "$N1" '{name: $n, state: "working"}' > "$DC_CLAUDE_HOME/jobs/$J1/state.json"
jq -n --arg n "$N2" '{name: $n, state: "done"}' > "$DC_CLAUDE_HOME/jobs/$J2/state.json"

# feat-1's instance holds its running koto session.
cat > "$T/worker.md" <<'TPL'
---
name: handover-classify-worker
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
(cd "$T/ws/feat-1" && koto init feat-1-work --template "$T/worker.md" >/dev/null) \
    && ok "fixture: feat-1's koto session runs in its instance" \
    || bad "fixture: feat-1's koto session runs in its instance" ""

# The run's record: three dispatched holdings with no pull request yet, a next
# step for each, and the Run rows the gate asks for but the coordinator's.
three_features hc
REC=$(record_json roadmap hc | jq -c \
    --argjson a "$(holding feat-1 '{"unit": "Feature 1", "branch": "", "pull_request": ""}')" \
    --argjson b "$(holding feat-2 '{"unit": "Feature 2", "branch": "", "pull_request": ""}')" \
    --argjson c "$(holding feat-3 '{"unit": "Feature 3", "branch": "", "pull_request": ""}')" '
    .holdings = [$a, $b, $c]
    | .run = [{key: "arguments", value: "--roadmap docs/roadmaps/ROADMAP-hc.md", set_by: "the human", set: "2026-09-26T08:00Z"},
              {key: "cap", value: "5", set_by: "the human", set: "2026-09-26T08:00Z"},
              {key: "reports-to", value: "the human", set_by: "the human", set: "2026-09-26T08:00Z"}]
    | .work = [.holdings[] | {item: .unit, kind: "holding", who: .worker, next: "waiting on the worker", updated: "2026-09-26T08:00Z"}]')
RAW_RECORD=1 seed_record hc "$REC"
if open_run hc && [ "$(at)" = reconcile ]; then
    ok "fixture: the run opens at reconcile"
else
    bad "fixture: the run opens at reconcile" "$(cat "$T/open.err" "$T/tick.err" 2>/dev/null)"
    echo; echo "handover-classify-engine: $PASS passed, $FAIL failed"; exit 1
fi

echo "== 1. refusals =="
(cd "$WD" && bash "$HC" >/dev/null 2>&1); rc=$?
eq "1: a call with no session exits 64" 64 "$rc"
classify
printf 'exit %s: %s\n' "$HC_RC" "$HC_ERR"
eq "1: a record with no coordinator row exits 2" 2 "$HC_RC"
case "$HC_ERR" in *"names no coordinator address"*) ok "1: ... saying the record names no coordinator address" ;;
    *) bad "1: ... saying the record names no coordinator address" "$HC_ERR" ;; esac
eq "1: ... printing nothing" "" "$HC_OUT"
eq "1: ... and recording nothing" "" "$(run_rows)"

echo "== 2. a live, a gone-with-instance and a gone worker =="
write_as_agent state-stored-set.sh --run coordinator coord-test --by coord-test
eq "2: the agent sets the coordinator row" 0 $?
eq "2: with nobody told, the handover gate holds the run at reconcile" reconcile "$(at --with-data '{"reconciled":"reported"}')"
classify
printf '%s\n' "$HC_OUT"
eq "2: handover-classify.sh exits 0" 0 "$HC_RC"
eq "2: feat-1 live (address coord-test), feat-2 pending, feat-3 missing" \
    "live feat-1 coord-test|pending feat-2|missing feat-3" "$(printf '%s' "$HC_OUT" | tr '\n' '|')"
eq "2: the record has feat-2 pending and nobody told" "pending:feat-2" "$(run_rows)"
eq "2: the gate's gaps: feat-1 and feat-3 not told" "not-told feat-1|not-told feat-3" "$(gaps)"

echo "== 3. the live worker told; the pending one hasn't reported =="
write_as_agent state-stored-set.sh --told feat-1 --by coord-test
eq "3: the agent records feat-1 told after its message" 0 $?
eq "3: the gate's one gap is feat-3's" "not-told feat-3" "$(gaps)"
classify
printf '%s\n' "$HC_OUT"
eq "3: a second classification prints only feat-3 missing" "missing feat-3" "$HC_OUT"
eq "3: feat-2 stays pending without a report" "pending:feat-2 told:feat-1" "$(run_rows)"

echo "== 4. the pending worker's first report turns it told =="
# A fixture shortcut, not how a missing worker is resolved: feat-3 is recorded
# told only so the gate passes and the run can reach wait for feat-2's report.
write_as_agent state-stored-set.sh --told feat-3 --by coord-test
eq "4: feat-3 recorded told by the fixture, to clear the gate" 0 $?
eq "4: the gate passes with feat-2 pending, and the run reaches pick" pick "$(at --with-data '{"reconciled":"reported"}')"
eq "4: hold reaches wait" wait "$(at --with-data '{"choice":"hold"}')"
AFTER=$(at --with-data '{"event":"report","unit":"feat-2","report":"Feature 2 is under way; no pull request yet."}')
[ -n "$AFTER" ] && ok "4: feat-2's report is taken at wait ($AFTER)" || bad "4: feat-2's report is taken at wait" "$(cat "$T/tick.err")"
classify
printf '%s\n' "$HC_OUT"
eq "4: the next classification prints feat-2 told" "told feat-2" "$HC_OUT"
eq "4: ... and records it told, its pending row gone" "told:feat-1 told:feat-2 told:feat-3" "$(run_rows)"
classify
eq "4: one more classification prints nothing" "0 " "$HC_RC $HC_OUT"

echo
echo "handover-classify-engine: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
