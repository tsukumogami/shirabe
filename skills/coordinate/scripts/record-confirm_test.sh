#!/usr/bin/env bash
# record-confirm_test.sh -- record-confirm.sh reads the source step from the
# session log and confirms the change it implies with a newer Written: time.
#
# Covers, with a passing and a failing fixture each: dispatch (the topic's
# row), surface (the unit's Verified head), merge_confirm and merged_facts
# (merged: no row linking the pull request; unconfirmed: a Side effects row at
# the sha), teardown (done and kept), decision_apply (reversal and deferral),
# posture_ask, and --verified (confirmed, waiting, moved). Also: an older
# Written: time waits even when the rows match; a missing or non-canonical
# body is a conflict; a directed transition is `directed`; a capture with a
# broken seal is a conflict; the sealed token and its context detail.
#
# Usage: bash skills/coordinate/scripts/record-confirm_test.sh
set -uo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
command -v jq >/dev/null 2>&1 || { echo "SKIP: jq not on PATH"; exit 0; }
. "$HERE/testdata/test-lib.sh"
C="$HERE/record-confirm.sh"
CL="$HERE/coord-log.sh"

TITLE="Coordinator record: ROADMAP-plugin-system"
EVT=2026-09-26T10:00:00.000Z
AFTER=2026-09-26T10:05:00Z
BEFORE=2026-09-26T09:55:00Z
N=0

# body <record-json> [written]: make issue #7's body this record.
body() {
    db_init
    db '.issues += [{repo: "acme/widgets", number: 7, title: $t, body: $b, state: "open", author: "alice", editor: null}]
        | .prs += [{repo: "acme/widgets", number: 12, title: "feat", body: "", state: "OPEN", isDraft: false, isCrossRepository: false,
                    baseRefName: "main", headRefName: "feat/x", headRefOid: $h, author: "alice", editor: null}]' \
        --arg t "$TITLE" --arg b "$(render "$1" issue "${2:-$AFTER}")" --arg h "$SHA_HEAD"
}
rec() { record_json roadmap plugin-system; }
# session: a fresh run with a found record #7; prints its name.
session() {
    N=$((N + 1))
    S=coordinate-plugin-system-20260926T0800$(printf '%02d' "$N")Z
    found_session "$S" "$(roadmap_vars plugin-system)" 7
}
confirm() { bash "$C" --session "$S" --no-seal "$@" 2>"$T/err"; }
sealed_capture() { # sealed_capture <state> <KEY> <token> [timestamp]
    log_to "$S" wait "$1"
    log_capture "$S" "$2" "$(bash "$CL" seal --session "$S" --state "$1" --token "$3")" "${4:-$EVT}"
}

echo "== dispatch =="
session
log_evidence "$S" dispatch '{"outcome":"sent","topic":"alpha"}' "$EVT"
log_to "$S" dispatch record "$EVT"
body "$(rec | jq -c --argjson h "$(holding alpha)" '.holdings = [$h]')"
eq "dispatch: the topic's row with a newer Written: confirms" confirmed "$(confirm)"
body "$(rec | jq -c --argjson h "$(holding beta)" '.holdings = [$h]')"
eq "dispatch: another topic's row waits" waiting "$(confirm)"
body "$(rec | jq -c --argjson h "$(holding alpha)" '.holdings = [$h]')" "$BEFORE"
eq "dispatch: an older Written: time waits even with the row" waiting "$(confirm)"
body "$(rec | jq -c --argjson h "$(holding alpha)" '.holdings = [$h]')" 2026-09-26T10:00:00Z
eq "dispatch: a Written: time in the event's own second waits" waiting "$(confirm)"

echo "== surface =="
session
log_evidence "$S" wait '{"event":"report","unit":"alpha"}' 2026-09-26T09:50:00.000Z
log_to "$S" wait report_facts; log_to "$S" report_facts classify_report
log_to "$S" classify_report surface
log_evidence "$S" surface '{"surfaced":"merge_table"}' "$EVT"
log_to "$S" surface record "$EVT"
body "$(rec | jq -c --argjson h "$(holding alpha "{\"verified_head\":\"$SHA_HEAD\"}")" '.holdings = [$h]')"
eq "surface: the unit's row with a Verified head confirms" confirmed "$(confirm)"
body "$(rec | jq -c --argjson h "$(holding alpha)" '.holdings = [$h]')"
eq "surface: the unit's row without a Verified head waits" waiting "$(confirm)"

echo "== merge_confirm and merged_facts =="
for src in merge_confirm merged_facts; do
    KEY=MERGE_CONFIRM; [ "$src" = merged_facts ] && KEY=MERGED_FACTS
    session
    sealed_capture "$src" "$KEY" "merged 12 $SHA_HEAD"
    log_to "$S" "$src" record "$EVT"
    body "$(rec | jq -c --argjson h "$(holding beta '{"pull_request":"[#13](https://github.com/acme/widgets/pull/13)"}')" '.holdings = [$h]')"
    eq "$src merged: no row linking the pull request confirms" confirmed "$(confirm)"
    body "$(rec | jq -c --argjson h "$(holding alpha)" '.holdings = [$h]')"
    eq "$src merged: a row still linking #12 waits" waiting "$(confirm)"
    session
    sealed_capture "$src" "$KEY" "unconfirmed 12 $SHA_HEAD"
    log_to "$S" "$src" record "$EVT"
    SE=$(jq -nc --arg s "$SHA_HEAD" '[{action: "merge", target: "acme/widgets#12", verified_head: $s, attempted: "2026-09-26T09:58Z", how_to_confirm: "compare blobs"}]')
    body "$(rec | jq -c --argjson se "$SE" '.side_effects = $se')"
    eq "$src unconfirmed: a Side effects row at the sha confirms" confirmed "$(confirm)"
    body "$(rec | jq -c --argjson se "$SE" --arg o "$SHA_OTHER" '.side_effects = $se | .side_effects[0].verified_head = $o')"
    eq "$src unconfirmed: a Side effects row at another sha waits" waiting "$(confirm)"
    body "$(rec | jq -c --argjson se "$SE" '.side_effects = $se | .side_effects[0].target = "#123"')"
    eq "$src unconfirmed: #123 does not name #12" waiting "$(confirm)"
done
session
log_to "$S" wait merge_confirm
log_capture "$S" MERGE_CONFIRM "merged 12 $SHA_HEAD sealed:99:abc" "$EVT"
log_to "$S" merge_confirm record "$EVT"
body "$(rec)"
eq "a capture with a broken seal is a conflict" conflict "$(confirm)"

echo "== teardown =="
session
log_evidence "$S" wait '{"event":"retire","unit":"alpha"}' 2026-09-26T09:50:00.000Z
log_to "$S" wait teardown
log_evidence "$S" teardown '{"outcome":"done"}' "$EVT"
log_to "$S" teardown record "$EVT"
body "$(rec | jq -c --argjson h "$(holding beta)" '.holdings = [$h]')"
eq "teardown done: no row for the unit confirms" confirmed "$(confirm)"
body "$(rec | jq -c --argjson h "$(holding alpha)" '.holdings = [$h]')"
eq "teardown done: the unit's row still there waits" waiting "$(confirm)"
session
log_evidence "$S" wait '{"event":"retire","unit":"alpha"}' 2026-09-26T09:50:00.000Z
log_to "$S" wait teardown
log_evidence "$S" teardown '{"outcome":"kept"}' "$EVT"
log_to "$S" teardown record "$EVT"
body "$(rec | jq -c --argjson h "$(holding alpha)" '.holdings = [$h]')"
eq "teardown kept: a newer Written: confirms with the row kept" confirmed "$(confirm)"
body "$(rec | jq -c --argjson h "$(holding alpha)" '.holdings = [$h]')" "$BEFORE"
eq "teardown kept: an older Written: waits" waiting "$(confirm)"

echo "== decision_apply =="
REV='{"date":"2026-09-26T10:00Z","reversed":"merge on green","now":"hold","reason":"freeze","from":"the human"}'
session
log_evidence "$S" decision_apply '{"applied":"reversal"}' "$EVT"
log_to "$S" decision_apply record "$EVT"
body "$(rec | jq -c --argjson r "$REV" '.reversals = [$r]')"
eq "decision_apply reversal: a row dated at the event confirms" confirmed "$(confirm)"
body "$(rec | jq -c --argjson r "$REV" '.reversals = [$r | .date = "2026-09-26T09:59Z"]')"
eq "decision_apply reversal: only an earlier row waits" waiting "$(confirm)"
session
log_evidence "$S" decision_apply '{"applied":"deferral"}' "$EVT"
log_to "$S" decision_apply record "$EVT"
DEF='{"deferral":"flaky","reason":"later","raised":"2026-09-26T10:01Z","disposition":""}'
body "$(rec | jq -c --argjson d "$DEF" '.deferrals = [$d]')"
eq "decision_apply deferral: a row raised after the event confirms" confirmed "$(confirm)"
body "$(rec | jq -c --argjson d "$DEF" '.deferrals = [$d | .raised = "2026-09-25T10:01Z"]')"
eq "decision_apply deferral: only an older deferral waits" waiting "$(confirm)"

echo "== posture_ask =="
session
log_evidence "$S" posture_ask '{"merge":"held","close":"reserved","teardown":"reserved"}' "$EVT"
log_to "$S" posture_ask record "$EVT"
PREV='{"date":"2026-09-26T10:02Z","reversed":"posture unread","now":"coordinator holds merge","reason":"asked once","from":"the human"}'
body "$(rec | jq -c --argjson r "$PREV" '.reversals = [$r]')"
eq "posture_ask: the human's posture answer confirms" confirmed "$(confirm)"
body "$(rec | jq -c --argjson r "$PREV" '.reversals = [$r | .from = "the coordinator"]')"
eq "posture_ask: a row not from the human waits" waiting "$(confirm)"
body "$(rec | jq -c --argjson r "$PREV" '.reversals = [$r | .reversed = "merge order" | .now = "hold"]')"
eq "posture_ask: a row not about the posture waits" waiting "$(confirm)"

echo "== --verified =="
session
log_to "$S" verify verify_board
log_capture "$S" VERIFIED "$(bash "$CL" seal --session "$S" --state verify_board --token "verified 12 $SHA_HEAD")" "$EVT"
log_to "$S" verify_board verified_confirm "$EVT"
body "$(rec | jq -c --argjson h "$(holding alpha "{\"verified_head\":\"$SHA_HEAD\"}")" '.holdings = [$h]')"
eq "--verified: the row's Verified head equal to the capture confirms" confirmed "$(confirm --verified)"
grep -q "pr view 12 --repo acme/widgets --json headRefOid" "$GH_DB.calls" && ok "--verified re-reads the live head" || bad "--verified re-reads the live head" "$(calls)"
body "$(rec | jq -c --argjson h "$(holding alpha)" '.holdings = [$h]')"
eq "--verified: no head written yet waits" waiting "$(confirm --verified)"
body "$(rec | jq -c --argjson h "$(holding alpha "{\"verified_head\":\"$SHA_OTHER\"}")" '.holdings = [$h]')"
eq "--verified: another head in the row waits" waiting "$(confirm --verified)"
body "$(rec | jq -c --argjson h "$(holding alpha "{\"verified_head\":\"$SHA_HEAD\"}")" '.holdings = [$h]')"
db '.prs[0].headRefOid = $o' --arg o "$SHA_OTHER"
eq "--verified: a moved live head is moved" moved "$(confirm --verified)"
db '.fail = [{match: "headRefOid", rc: 1}]'
confirm --verified >/dev/null; eq "--verified: a failed head read exits 2" 2 $?

echo "== conflicts and refusals =="
session
log_evidence "$S" dispatch '{"outcome":"sent","topic":"alpha"}' "$EVT"
log_to "$S" dispatch record "$EVT"
body "$(rec)"; db '.issues[0].body = "gone"'
eq "a body that isn't a record is a conflict" conflict "$(confirm)"
db '.issues[0].body = ""'
eq "an empty body is a conflict" conflict "$(confirm)"
body "$(rec)"; db '.fail = [{match: "issue view", rc: 1}]'
confirm >/dev/null; eq "a failed body read exits 2" 2 $?
log_ev "$S" directed_transition '{"from":"record","to":"pick_facts"}'
body "$(rec)"
eq "a directed transition in the run is directed" directed "$(confirm)"
session
log_to "$S" reconcile record "$EVT"
body "$(rec)"
eq "an entry from a state with nothing to confirm is a conflict" conflict "$(confirm)"

echo "== sealing =="
session
log_evidence "$S" dispatch '{"outcome":"sent","topic":"alpha"}' "$EVT"
log_to "$S" dispatch record "$EVT"
body "$(rec | jq -c --argjson h "$(holding alpha)" '.holdings = [$h]')"
OUT=$(bash "$C" --session "$S" 2>"$T/err")
case "$OUT" in "confirmed sealed:"*) ok "the verdict is sealed to the record visit" ;; *) bad "the verdict is sealed to the record visit" "$OUT $(cat "$T/err")" ;; esac
bash "$CL" check --session "$S" --state record --sealed "$OUT" && ok "the seal checks" || bad "the seal checks"
eq "the detail names the source" dispatch "$(jq -r .source "$KOTO_STORE/context/$S/coord/record_confirm.json")"
bash "$C" --no-seal >/dev/null 2>&1; eq "no session is a usage error" 64 $?

done_tests record-confirm
