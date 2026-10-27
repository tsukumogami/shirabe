#!/usr/bin/env bash
# session-start_engine_test.sh -- a coordinator started after the GitHub
# record's removal, stopped, and started again, the shipped coordinate.md
# driven through real koto against the testdata/gh stand-in
# (docs/designs/current/DESIGN-coordinator-record-teardown.md, "The start").
# The setup and helpers are the coordinate engine suites'
# (testdata/coordinate-engine-lib.sh).
#
# Proves, one line per case:
#   1. a fresh start of a new roadmap scope, given no store, opens a session
#      that stops at record_open; state-open.sh writes the record into the
#      session's keys and opens nothing on GitHub; the next find reaches
#      reconcile and writes coord/source.json reading `session`;
#   2. on that fresh session, state-stored-set.sh writes each crash-set Run row
#      (rules, briefs, friction, reports-to), each accepted with no `store`
#      row in the record, and record/run then holds all four and still no
#      `store` row;
#   3. the coordinator stops, leaving its run live where it stood, and the
#      next start resumes it: resumed=1 and the same session, no session
#      opened or cancelled, the run at the state it stood at, every record/
#      key byte for byte as it was, and coord/source.json still reading
#      `session`.
#
# Needs koto, jq and git; SKIPs (exit 0) without koto, which
# run-tests.sh --engine turns into a failure.
# Usage: bash skills/coordinate/scripts/session-start_engine_test.sh
set -uo pipefail
. "$(dirname "$0")/../../../scripts/lib/koto-test-guard.sh" || exit 1

HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/testdata/coordinate-engine-lib.sh"

# keys: every record/ key of $S, its name and its content (run-tests.sh's PATH
# has no cksum, so no digest).
keys() {
    local k
    (cd "$WD" && koto context list "$S" --prefix record/) | jq -r '.[]' | LC_ALL=C sort | while IFS= read -r k; do
        printf '%s %s\n' "$k" "$(cd "$WD" && koto context get "$S" "$k")"
    done
}
source_of() { (cd "$WD" && koto context get "$S" coord/source.json 2>/dev/null) | jq -r '.source // empty'; }
# store_rows: the record's `store` Run rows, 0 when it has no Run section.
store_rows() {
    (cd "$WD" && koto context exists "$S" record/run > /dev/null 2>&1) || { echo 0; return; }
    (cd "$WD" && koto context get "$S" record/run) | jq -r '[.[] | select(.key == "store")] | length'
}
sessions() { koto session list 2>/dev/null | jq -r '[.[].id] | sort | join(" ")'; }

# ---- 1. a fresh start ------------------------------------------------------------
echo "== 1. a fresh start of a new roadmap scope =="
seed_roadmap fresh
reset_calls
open_run fresh || { bad "1: the fresh start opens a session" "$(cat "$T/open.err")"; done_tests session-start-engine; exit 1; }
ok "1: the fresh start opens a session"
grep -qx 'resumed=1' <<< "$OPEN_OUT" && bad "1:   ... resuming nothing" "$OPEN_OUT" || ok "1:   ... resuming nothing"
eq "1: with no record it stops at record_open" record_open "$(at)"
write_as_agent state-open.sh
eq "1: state-open.sh (agent-run) opens the record" 0 $?
(cd "$WD" && koto context exists "$S" record/meta) && ok "1:   ... in the session's record/meta" || bad "1:   ... in the session's record/meta" "$(cat "$T/w.err")"
grep -Eq '^(issue|pr) create|^api --method POST' "$GH_DB.calls" \
    && bad "1:   ... opening nothing on GitHub" "$(grep -E '^(issue|pr) create|^api --method POST' "$GH_DB.calls")" || ok "1:   ... opening nothing on GitHub"
eq "1: the next find reaches reconcile" reconcile "$(at --with-data '{"opened":"opened"}')"
eq "1:   ... and coord/source.json reads session" session "$(source_of)"

# ---- 2. the crash set on a fresh session --------------------------------------------
echo "== 2. each crash-set Run row, with no store row =="
# 64 hex characters each, written out: run-tests.sh's PATH has no seq.
RULES=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
BRIEFS=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
eq "2: the fresh record holds no store row" 0 "$(store_rows)"
write_as_agent state-stored-set.sh --run rules "coordinate sha256:$RULES" --by coord-test
eq "2: rules is accepted" 0 $?
write_as_agent state-stored-set.sh --run briefs "lane sha256:$BRIEFS" --by coord-test
eq "2: briefs is accepted" 0 $?
write_as_agent state-stored-set.sh --run friction lane-friction --by coord-test
eq "2: friction is accepted" 0 $?
write_as_agent state-stored-set.sh --run reports-to "the human" --by "the human"
eq "2: reports-to is accepted" 0 $?
eq "2: record/run holds the four rows" "briefs=lane sha256:$BRIEFS|friction=lane-friction|reports-to=the human|rules=coordinate sha256:$RULES" \
    "$( (cd "$WD" && koto context get "$S" record/run) | jq -r '[.[] | select(.key | IN("rules", "briefs", "friction", "reports-to")) | "\(.key)=\(.value)"] | sort | join("|")')"
eq "2:   ... and still no store row" 0 "$(store_rows)"

# ---- 3. a stop, then the next start ---------------------------------------------------
echo "== 3. the coordinator stops, and the next start resumes it =="
# The coordinator's process ends here: nothing is cancelled, and the run
# stays live at the state it stood at.
FIRST=$S
STOOD=$(now_at)
SNAP=$(keys)
[ -n "$SNAP" ] && ok "3: the record's keys are read before the stop" || bad "3: the record's keys are read before the stop" ""
BEFORE=$(sessions)
sleep 1
open_run fresh || bad "3: the next start opens" "$(cat "$T/open.err")"
grep -qx 'resumed=1' <<< "$OPEN_OUT" && ok "3: the next start prints resumed=1" || bad "3: the next start prints resumed=1" "$OPEN_OUT"
eq "3:   ... and the same session" "$FIRST" "$S"
grep -q '^cancelled=' <<< "$OPEN_OUT" && bad "3:   ... cancelling nothing" "$OPEN_OUT" || ok "3:   ... cancelling nothing"
eq "3:   ... opening no session" "$BEFORE" "$(sessions)"
eq "3: the run is where it stood" "$STOOD" "$(now_at)"
eq "3: every record/ key is as it was" "$SNAP" "$(keys)"
eq "3: coord/source.json still reads session" session "$(source_of)"

done_tests session-start-engine
