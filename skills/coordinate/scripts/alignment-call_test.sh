#!/usr/bin/env bash
# alignment-call_test.sh -- alignment-call.sh: a director's `diverges` call
# holds the pull request, and the manager's land check reads the hold from
# its own record (docs/designs/DESIGN-director-alignment-review.md,
# Decision 1).
#
# Covers, on one planted pull request head and two scratch records, a
# director's and a manager's whose Run reports-to row names the director: the
# call written as an alignment entry; the `align-<repo>-<n>-<head>` hold,
# until lifted, set by the director at its address with the manager as
# receiver, in the director's record; the printed message naming the pull
# request, the hold row, the Sources and Reason, the receiver and the release;
# a malformed call refused by state-entry.sh (65) with nothing written in the
# director's record and no hold; a call whose hold has no receiver refused
# before anything is written. The manager's copy: a message from anyone but
# the address its reports-to row names, one whose hold name isn't of the
# align- form, one whose head isn't 40 hex, one that isn't the six lines, and
# one whose Set by doesn't name the sender, each refused (65) with the
# manager's record unchanged; the message passed with an event number and
# the director's address adding the identical row and a `hold` entry naming
# the event; the same message again changing nothing; and then land-check.sh
# on the manager's record, which passes every earlier check (verify capture,
# a three-seat round at the head, a fresh reviewed head, a body that passes
# and a message that builds), reporting `held <pr> <sha>` with coord/land.json
# listing the align- hold as unmet. A successor director: its hold message
# refused while the row names the old address; an address message naming
# another current address, and one sent to a row holding no address,
# changing nothing (65); one naming the row's address and the sender's
# rewriting the row through state-stored-set.sh, with a `hold` entry naming
# the event and both addresses, after which the successor's hold message is
# accepted. A second diverges call while the hold stands writes its entry and
# places no second hold; a diverges call on a merged pull request writes its
# entry and places none; a fits call writes its entry and touches no hold.
#
# Every script runs on the koto stand-in (testdata/koto) and one store; the
# writers read GitHub through testdata/gh and land-check.sh through gh-board
# in the localized plugin tree the board helpers build.
#
# Usage: bash skills/coordinate/scripts/alignment-call_test.sh
set -uo pipefail
. "$(dirname "$0")/../../../scripts/lib/koto-test-guard.sh" || exit 1

HERE=$(cd "$(dirname "$0")" && pwd)
command -v jq >/dev/null 2>&1 || { echo "SKIP: jq not on PATH"; exit 0; }
. "$HERE/testdata/test-lib.sh"
. "$HERE/testdata/board/helpers.sh"
W_PATH=$PATH
bt_setup
# The writers keep testdata/gh; land-check.sh gets gh-board and the shirabe
# stand-in. Both read the one koto store.
B_PATH=$PATH
PATH=$W_PATH
export KOTO_BIN="$HERE/testdata/koto"
AC="$HERE/alignment-call.sh"
PERMIT="readable merge:permit close:permit teardown:permit release:permit"

SD=coordinate-roadmap-direction-20260926T080000Z
SM=coordinate-roadmap-plugin-system-20260926T080000Z
run_row() { jq -nc --arg k "$1" --arg v "$2" '{key: $k, value: $v, set_by: "alice", set: "2026-09-26T08:00Z"}'; }
link() { printf '[#%s](https://github.com/acme/widgets/pull/%s)' "$1" "$1"; }
seal() { bash "$HERE/coord-log.sh" seal --session "$1" --state "$2" --token "$3"; }
gh_writes() { grep -E 'issue (create|edit|close)|pr (create|edit)|comment|--method (POST|PUT|PATCH|DELETE)' "$GH_DB.calls"; }
entries() { koto context list --prefix record/entries/ "$1" | jq length; }
last_entry() { koto context get "$1" "record/entries/$(printf '%06d' "$(entries "$1")")"; }
holds() { koto context get "$1" record/holds 2>/dev/null || echo '[]'; }
nalign() { holds "$1" | jq --arg on "$2" '[.[] | select((.hold | startswith("align-")) and .on == $on)] | length'; }

db_init
db '.prs += [{repo: "acme/widgets", number: 12, title: "x", body: "", state: "OPEN", isDraft: false, isCrossRepository: false,
        baseRefName: "main", headRefName: "feat/x", headRefOid: $h, author: "alice", editor: null},
    {repo: "acme/widgets", number: 13, title: "y", body: "", state: "OPEN", isDraft: false, isCrossRepository: false,
        baseRefName: "main", headRefName: "feat/y", headRefOid: $m, author: "alice", editor: null},
    {repo: "acme/widgets", number: 14, title: "z", body: "", state: "MERGED", isDraft: false, isCrossRepository: false,
        baseRefName: "main", headRefName: "feat/z", headRefOid: $m, author: "alice", editor: null}]' --arg h "$H" --arg m "$MOVED"

# The director's record: its address, its role, and the lane holding whose
# Worker, the manager, holds pull request #12.
found_session "$SD" "$(roadmap_vars direction)"
seed_session "$SD" "$(record_json roadmap direction | jq -c --argjson h "$(holding mgr-widgets "{\"pull_request\": \"$(link 12)\"}")" \
    --argjson c "$(run_row coordinator director-a)" --argjson r "$(run_row role director)" '.holdings = [$h] | .run = [$c, $r]')"
log_to "$SD" reconcile wait

# The manager's record, reporting to the director, its worker's holding on
# #12; its run at land with the verify capture, the worker's three-seat round
# at the head, a body that passes and a message that builds, as
# land-check_test.sh's fixtures set them.
MREC=$(record_json roadmap plugin-system | jq -c --argjson h "$(holding worker-f12 "{\"pull_request\": \"$(link 12)\"}")" \
    --argjson c "$(run_row coordinator mgr-widgets)" --argjson t "$(run_row reports-to "director at director-a")" \
    --argjson r "$(run_row role manager)" '.holdings = [$h] | .run = [$c, $t, $r]')
log_new "$SM" "$(roadmap_vars plugin-system)"
log_to "$SM" start start_posture
log_capture "$SM" POSTURE "$(seal "$SM" start_posture "$PERMIT")"
log_to "$SM" start_posture record_find
log_capture "$SM" RECORD_FIND "$(seal "$SM" record_find found)"
seed_session "$SM" "$MREC"
log_to "$SM" record_find wait
log_evidence "$SM" wait "$(jq -nc --arg r "$(bt_result "$(bt_round)")" '{event: "report", unit: "worker-f12", report: $r}')"
log_to "$SM" wait verify
log_evidence "$SM" verify '{"prediction":"every job green"}'
log_to "$SM" verify verify_board
log_capture "$SM" VERIFIED "$(seal "$SM" verify_board "verified 12 $H")"
log_to "$SM" verify_board verified_confirm
log_to "$SM" verified_confirm land
jq -nc --arg l "$(link 12)" '[{worker: "worker-f12", pull_request: $l, repo: "acme/widgets", return_path: "message"}]' > "$BT_STATE/holdings"
printf '%s\n' "$PERMIT" > "$BT_STATE/posture"
bt_board complete-board
bt_prview CLEAN

# call <pr> <call> [Sources] [Action]: an alignment text on <pr> at $H, in $T/call.txt.
call() {
    printf 'Alignment: %s at %s -- %s\nRead: full\nSources: %s\nReason: %s\nEvidence: none\nFollow-ups: none\nAction: %s\n' \
        "$1" "$H" "$2" "${3:-standing s1}" "the loader drops the cap the standing row sets" "${4:-hold}" > "$T/call.txt"
}
direct() { bash "$AC" --session "$SD" --text-file "$T/call.txt" "$@"; }
copy() { bash "$AC" --session "$SM" --copy "$@"; }

echo "== a malformed call writes nothing =="
call acme/widgets#12 diverges none
N0=$(entries "$SD")
direct --on acme/widgets#12 > "$T/out" 2>"$T/err"; rc=$?
eq "a diverges call with Sources none is refused by state-entry.sh" "65 $N0 0" "$rc $(entries "$SD") $(nalign "$SD" acme/widgets#12)"
eq "  ... printing no message" "" "$(cat "$T/out")"
call acme/widgets#13 diverges
direct --on acme/widgets#13 > "$T/out" 2>"$T/err"; rc=$?
eq "a diverges call whose pull request no holding links, with no --receiver, is refused" "65 $N0 0" "$rc $(entries "$SD") $(nalign "$SD" acme/widgets#13)"
grep -q -- '--receiver' "$T/err" && ok "  ... naming --receiver" || bad "  ... naming --receiver" "$(cat "$T/err")"

echo "== the director's diverges call places the hold =="
call acme/widgets#12 diverges
direct --on acme/widgets#12 > "$T/msg" 2>"$T/err"; rc=$?
eq "the call is written" "0 $((N0 + 2))" "$rc $(entries "$SD")"
CALLN=$(koto context list --prefix record/entries/ "$SD" | jq -r '.[]' | while read -r k; do koto context get "$SD" "$k" | jq -r 'select(.kind == "alignment") | .n'; done | tail -1)
eq "  ... as an alignment entry holding the call's text" "$(cat "$T/call.txt")" "$(koto context get "$SD" "record/entries/$(printf '%06d' "$CALLN")" | jq -r .text)"
HOLD="align-widgets-12-$H"
eq "the director's record holds the align- hold named after the head" \
    "$HOLD|acme/widgets#12|lifted|director at director-a, receiver manager at mgr-widgets|" \
    "$(holds "$SD" | jq -r '.[] | "\(.hold)|\(.on)|\(.until)|\(.set_by)|\(.lifted)"')"
eq "  ... and only that one" 1 "$(holds "$SD" | jq length)"
eq "the message names the pull request and head" "Alignment hold: acme/widgets#12 at $H" "$(sed -n 1p "$T/msg")"
eq "  ... the hold row as the record holds it" "$(holds "$SD" | jq -cS '.[0]')" "$(sed -n 2p "$T/msg" | sed 's/^Row: //' | jq -cS .)"
eq "  ... the reason" "Sources: standing s1|Reason: the loader drops the cap the standing row sets" "$(sed -n 3p "$T/msg")|$(sed -n 4p "$T/msg")"
eq "  ... the receiver and the release" "Receiver: manager at mgr-widgets|Release: a new head that the director re-reads and calls fits or fits with follow-ups" \
    "$(sed -n 5p "$T/msg")|$(sed -n 6p "$T/msg")"
eq "  ... and nothing else" 6 "$(wc -l < "$T/msg" | tr -d ' ')"
eq "nothing is written on GitHub" "" "$(gh_writes)"

echo "== the manager's copy refuses what isn't its director's hold =="
SNAP=$(session_snapshot "$SM")
copy --add --message-file "$T/msg" --event 7 --from director-x >/dev/null 2>"$T/err"; rc=$?
eq "a message from another address is refused" 65 "$rc"
grep -q 'reports to director at director-a' "$T/err" && ok "  ... saying so" || bad "  ... saying so" "$(cat "$T/err")"
sed '2s/"hold":"align-/"hold":"hold-/' "$T/msg" > "$T/bad1"
copy --add --message-file "$T/bad1" --event 7 --from director-a >/dev/null 2>"$T/err"; eq "a hold name not of the align- form is refused" 65 $?
grep -q 'form align-widgets-12-' "$T/err" && ok "  ... saying so" || bad "  ... saying so" "$(cat "$T/err")"
sed "1s/$H/0123456789abcdef/" "$T/msg" > "$T/bad2"
copy --add --message-file "$T/bad2" --event 7 --from director-a >/dev/null 2>"$T/err"; eq "a head that isn't 40 hex is refused" 65 $?
grep -q "isn't 40 lower-case hex" "$T/err" && ok "  ... saying so" || bad "  ... saying so" "$(cat "$T/err")"
sed '5d' "$T/msg" > "$T/bad3"
copy --add --message-file "$T/bad3" --event 7 --from director-a >/dev/null 2>"$T/err"; eq "a message missing a line is refused" 65 $?
sed '2s/director at director-a/director at director-z/' "$T/msg" > "$T/bad4"
copy --add --message-file "$T/bad4" --event 7 --from director-a >/dev/null 2>"$T/err"; eq "a hold whose Set by doesn't name the sender is refused" 65 $?
eq "  ... each leaving the manager's record as it was" "$SNAP" "$(session_snapshot "$SM")"

echo "== the copy, and the manager's land check =="
copy --add --message-file "$T/msg" --event 7 --from director-a >/dev/null 2>"$T/err"; rc=$?
eq "the director's message is copied" 0 "$rc"
eq "  ... the manager's record holding the identical row" "$(holds "$SD" | jq -cS '.[0]')" "$(holds "$SM" | jq -cS '.[0]')"
eq "  ... with a hold entry naming event 7" "hold" "$(last_entry "$SM" | jq -r 'select(.text | test("event 7")) | .kind')"
N1=$(entries "$SM")
copy --add --message-file "$T/msg" --event 9 --from director-a >/dev/null 2>"$T/err"; rc=$?
eq "the same message again changes nothing" "0 $N1 1" "$rc $(entries "$SM") $(holds "$SM" | jq length)"
OUT=$(PATH="$B_PATH" bash "$PS/land-check.sh" --session "$SM" --repo acme/widgets 2>"$T/lc.err"); rc=$?
eq "the manager's land check reports the pull request held" "0 held 12 $H" "$rc ${OUT% sealed:*}"
eq "  ... coord/land.json listing the align- hold unmet" "$HOLD unmet" \
    "$(koto context get "$SM" coord/land.json | jq -r '.holds[] | "\(.hold) \(.state)"')"
eq "  ... having passed the round, the freshness and the body" "ok fresh" \
    "$(koto context get "$SM" coord/land.json | jq -r '"\(.evidence.status) \(.freshness)"')"

echo "== a successor director's address =="
# The successor's hold message on #13, as it would send it.
call acme/widgets#13 diverges
direct --on acme/widgets#13 --receiver mgr-widgets > "$T/msg13" 2>"$T/err"; rc=$?
eq "a diverges call names its receiver with --receiver when no holding links the pull request" "0 1" "$rc $(nalign "$SD" acme/widgets#13)"
sed 's/director at director-a/director at director-b/' "$T/msg13" > "$T/succ"
SNAP=$(session_snapshot "$SM")
copy --add --message-file "$T/succ" --event 11 --from director-b >/dev/null 2>"$T/err"
eq "the successor's hold message is refused while the row names the old address" "65" "$?"
printf 'Director address: director-x is now director-b\n' > "$T/addr-x"
copy --reports-to --message-file "$T/addr-x" --event 12 --from director-b >/dev/null 2>"$T/err"
eq "an address message naming another current address is refused" 65 "$?"
grep -q 'names director-x as the current address' "$T/err" && ok "  ... saying so" || bad "  ... saying so" "$(cat "$T/err")"
eq "  ... changing nothing" "$SNAP" "$(session_snapshot "$SM")"
# A row holding no address, for one case, then the row as it was.
koto context get "$SM" record/run > "$T/run.json"
jq -c 'map(if .key == "reports-to" then .value = "the owner" else . end)' "$T/run.json" | koto context add "$SM" record/run
SNAP0=$(session_snapshot "$SM")
printf 'Director address: director-a is now director-b\n' > "$T/addr"
copy --reports-to --message-file "$T/addr" --event 12 --from director-b >/dev/null 2>"$T/err"
eq "an address message to a row holding no address is refused" 65 "$?"
grep -q 'holds no address' "$T/err" && ok "  ... saying so" || bad "  ... saying so" "$(cat "$T/err")"
eq "  ... changing nothing" "$SNAP0" "$(session_snapshot "$SM")"
koto context add "$SM" record/run --from-file "$T/run.json"
copy --reports-to --message-file "$T/addr" --event 12 --from director-b >/dev/null 2>"$T/err"; rc=$?
eq "an address message naming the row's address and the sender's rewrites the row" "0 director at director-b|director at director-b" \
    "$rc $(koto context get "$SM" record/run | jq -r '.[] | select(.key == "reports-to") | "\(.value)|\(.set_by)"')"
eq "  ... with a hold entry naming the event and both addresses" "hold" \
    "$(last_entry "$SM" | jq -r 'select(.text | test("director-a") and test("director-b") and test("event 12")) | .kind')"
copy --add --message-file "$T/succ" --event 13 --from director-b >/dev/null 2>"$T/err"; rc=$?
eq "the successor's hold message is then accepted" "0 1" "$rc $(nalign "$SM" acme/widgets#13)"
copy --add --message-file "$T/msg" --event 14 --from director-a >/dev/null 2>"$T/err"
eq "  ... and the old director's refused" 65 "$?"

echo "== a call that places no hold =="
N0=$(entries "$SD")
call acme/widgets#12 diverges
direct --on acme/widgets#12 > "$T/out" 2>"$T/err"; rc=$?
eq "a second diverges call while the hold stands writes its entry" "0 $((N0 + 1))" "$rc $(entries "$SD")"
eq "  ... and places no second hold" 1 "$(nalign "$SD" acme/widgets#12)"
eq "  ... printing no message" "" "$(cat "$T/out")"
call acme/widgets#14 diverges
direct --on acme/widgets#14 > "$T/out" 2>"$T/err"; rc=$?
eq "a diverges call on a merged pull request writes its entry" "0 $((N0 + 2)) alignment" "$rc $(entries "$SD") $(last_entry "$SD" | jq -r .kind)"
eq "  ... and places no hold" 0 "$(nalign "$SD" acme/widgets#14)"
call acme/widgets#12 fits none merge
direct --on acme/widgets#12 > "$T/out" 2>"$T/err"; rc=$?
eq "a fits call writes its entry and leaves the hold as it stands" "0 $((N0 + 3)) 1 " \
    "$rc $(entries "$SD") $(nalign "$SD" acme/widgets#12) $(holds "$SD" | jq -r '.[0].lifted')"
eq "nothing in this suite was written on GitHub" "" "$(gh_writes)"

echo
echo "alignment-call: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
