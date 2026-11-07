#!/usr/bin/env bash
# alignment-call_test.sh -- alignment-call.sh: a director's `diverges` call
# holds the pull request, the manager's land check reads the hold from its
# own record, and the hold lifts only on a new head and a later fits call
# (docs/designs/DESIGN-director-alignment-review.md, Decision 1).
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
# The lift. A fits call, and --lift-releasable, while the live head is the
# placed-on head lift nothing and print nothing. Once the pull request moves,
# a diverges re-read adds a call and no hold; a fits with follow-ups call
# lifts the director's hold, its Lifted cell naming the director at its
# address, the call and the new head, and prints the lift message (the hold,
# the head, the call's entry number). In a manager's record verified at the
# new head, --copy --lift lifts the copy at once and land-check.sh reports
# permit instead of held, with a hold entry naming the hold, the call's entry
# number and the event; the same lift again changes nothing. On fresh held
# manager records, a lift at the placed-on head, a replayed lift naming an
# older head than the verified head and one from a non-dispatcher sender are
# each refused, the record unchanged and still held. When the live head can't
# be read a fits call is written and its lift blocked (13, the hold named and
# standing), as is --lift-releasable, which lifts the hold once the read is
# back, writing no alignment entry. A pull request no holding links lifts at
# its live head only (refused at another head, 2 when the head can't be
# read). The guard takes calls in entry order: a fits call made before the
# hold's diverges call releases nothing, and a fits call at another head
# lifts nothing while --lift-releasable lifts on the earlier one for the live
# head. A person's lift on an unchanged head goes through state-hold.sh --lift
# on both sides, and land-check.sh then reports permit at the placed-on head.
# Last, the rows and entries name the decider, the pull request, both heads
# and the call's entry number, and every row keeps the Holds grammar.
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

# ---- the lift ----------------------------------------------------------------
# callat <pr> <head> <call> [Sources] [Follow-ups] [Action]: an alignment text in $T/call.txt.
callat() {
    printf 'Alignment: %s at %s -- %s\nRead: full\nSources: %s\nReason: %s\nEvidence: none\nFollow-ups: %s\nAction: %s\n' \
        "$1" "$2" "$3" "${4:-standing s1}" "the loader keeps the cap the standing row sets" "${5:-none}" "${6:-merge}" > "$T/call.txt"
}
releasable() { bash "$AC" --session "$SD" --lift-releasable --on "$1"; }
copyto() { local s=$1; shift; bash "$AC" --session "$s" --copy "$@"; }
lifted() { holds "$1" | jq -r --arg h "$2" '.[] | select(.hold == $h) | .lifted'; }
# lifted_by <session> <hold>: the Lifted cell after its minute, or why it doesn't read as one.
lifted_by() {
    local l
    l=$(lifted "$1" "$2")
    [[ $l =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}Z\ by\ (.+)$ ]] && printf '%s' "${BASH_REMATCH[1]}" || printf 'not lifted: [%s]' "$l"
}
elist() { bash "$HERE/state-entry.sh" --session "$1" --list; }
nalignment() { elist "$1" | jq '[.[] | select(.kind == "alignment")] | length'; }
last_call() { elist "$1" | jq '[.[] | select(.kind == "alignment")] | last | .id'; }
# joined <file>: its lines joined by `|`. Plain bash: run-tests.sh's PATH has no paste.
joined() { local l j=; while IFS= read -r l; do j=${j:+$j|}$l; done < "$1"; printf '%s' "$j"; }
move() { db '(.prs[] | select(.repo == "acme/widgets" and .number == ($n | tonumber))).headRefOid = $h' --arg n "$1" --arg h "$2"; }
headfail() { db '.fail = [{match: $m, rc: 1, stderr: "gh: Server Error (HTTP 502)"}]' --arg m "pr view $1 --repo acme/widgets --json headRefOid"; }
headok() { db '.fail = []'; }
# board_at <head>: land-check's board for #12 with <head> as its head, and #12's view.
board_at() {
    bt_case complete-board | sed "s/$H/$1/g" > "$T/case.json" && bt_materialize "$T/case.json" "$GH_BOARD_DIR"
    bt_prview CLEAN
}
landcheck() {
    local o rc
    o=$(PATH="$B_PATH" bash "$PS/land-check.sh" --session "$1" --repo acme/widgets 2>"$T/lc.err"); rc=$?
    printf '%s %s' "$rc" "${o% sealed:*}"
}
# manager <session> <roadmap name> <head>: a manager's record reporting to
# director-a, its worker's holding on #12 verified at <head>, and its run at
# land with the verify capture and the worker's three-seat round at <head>, as
# land-check_test.sh's fixtures set them.
manager() {
    local s=$1 h=$3
    log_new "$s" "$(roadmap_vars "$2")"
    log_to "$s" start start_posture
    log_capture "$s" POSTURE "$(seal "$s" start_posture "$PERMIT")"
    log_to "$s" start_posture record_find
    log_capture "$s" RECORD_FIND "$(seal "$s" record_find found)"
    seed_session "$s" "$(record_json roadmap "$2" | jq -c \
        --argjson h "$(holding worker-f12 "$(jq -nc --arg l "$(link 12)" --arg v "$h" '{pull_request: $l, verified_head: $v}')")" \
        --argjson c "$(run_row coordinator mgr-widgets)" --argjson t "$(run_row reports-to "director at director-a")" \
        --argjson r "$(run_row role manager)" '.holdings = [$h] | .run = [$c, $t, $r]')"
    log_to "$s" record_find wait
    log_evidence "$s" wait "$(jq -nc --arg r "$(bt_result "$(bt_round "$h")")" '{event: "report", unit: "worker-f12", report: $r}')"
    log_to "$s" wait verify
    log_evidence "$s" verify '{"prediction":"every job green"}'
    log_to "$s" verify verify_board
    log_capture "$s" VERIFIED "$(seal "$s" verify_board "verified 12 $h")"
    log_to "$s" verify_board verified_confirm
    log_to "$s" verified_confirm land
}
H12="align-widgets-12-$H" H13="align-widgets-13-$H"

echo "== a fits call at the placed-on head lifts nothing =="
N0=$(entries "$SD")
callat acme/widgets#12 "$H" fits
direct --on acme/widgets#12 > "$T/out" 2>"$T/err"; rc=$?
eq "a fits call while the live head is the placed-on head is written" "0 $((N0 + 1))" "$rc $(entries "$SD")"
eq "  ... and the hold stands" "" "$(lifted "$SD" "$H12")"
eq "  ... with no lift message" "" "$(cat "$T/out")"
grep -q "$H12 stands: acme/widgets#12's live head is still $H" "$T/err" && ok "  ... saying why" || bad "  ... saying why" "$(cat "$T/err")"
releasable acme/widgets#12 > "$T/out" 2>"$T/err"; rc=$?
eq "--lift-releasable on a hold that isn't releasable lifts nothing and prints nothing" "0 $((N0 + 1)) |" \
    "$rc $(entries "$SD") $(lifted "$SD" "$H12")|$(cat "$T/out")"

echo "== the director's lift at a new head =="
move 12 "$MOVED"
callat acme/widgets#12 "$MOVED" diverges "standing s1" none hold
direct --on acme/widgets#12 > "$T/out" 2>"$T/err"; rc=$?
eq "a re-read that calls diverges on the new head writes a call" "0 $((N0 + 2))" "$rc $(entries "$SD")"
eq "  ... leaving the one hold standing, with no message" "1||" "$(nalign "$SD" acme/widgets#12)|$(lifted "$SD" "$H12")|$(cat "$T/out")"
callat acme/widgets#12 "$MOVED" "fits with follow-ups" "standing s1" "new: name the cap in the loader's guide"
direct --on acme/widgets#12 > "$T/lift12" 2>"$T/err"; rc=$?
FIT12=$(last_call "$SD")
eq "a fits with follow-ups call at the new head lifts the hold" 0 "$rc"
eq "  ... its Lifted cell naming the director, the call and the head" "director at director-a, fits with follow-ups at $MOVED" "$(lifted_by "$SD" "$H12")"
eq "  ... and printing the lift message: the hold, the head and the call's entry" \
    "Alignment lift: acme/widgets#12 at $MOVED|Hold: $H12|Call: fits with follow-ups, entry $FIT12" "$(joined "$T/lift12")"
eq "  ... and the director's account naming the hold, the head and the call's entry" "hold" \
    "$(last_entry "$SD" | jq -r --arg h "$H12" --arg m "$MOVED" --arg e "entry $FIT12" 'select(.text | contains($h) and contains($m) and contains($e)) | .kind')"

echo "== the manager's copy lifts at its own verified head =="
board_at "$MOVED"
SM1=coordinate-roadmap-lift-a-20260926T080000Z
manager "$SM1" lift-a "$MOVED"
copyto "$SM1" --add --message-file "$T/msg" --event 21 --from director-a >/dev/null 2>"$T/err"
eq "a manager's record verified at the new head, holding the copy, is held" "0 held 12 $MOVED" "$(landcheck "$SM1")"
copyto "$SM1" --lift --message-file "$T/lift12" --event 22 --from director-a >/dev/null 2>"$T/err"; rc=$?
eq "the lift message lifts the copy at once" "0 director at director-a, fits with follow-ups at $MOVED" "$rc $(lifted_by "$SM1" "$H12")"
eq "  ... and land-check then reports the posture, not held" "0 permit 12 $MOVED" "$(landcheck "$SM1")"
eq "  ... the hold entry naming the hold, the call's entry and the event" "hold" \
    "$(last_entry "$SM1" | jq -r --arg h "$H12" --arg e "entry $FIT12" 'select(.text | contains($h) and contains($e) and contains("event 22")) | .kind')"
N1=$(entries "$SM1")
copyto "$SM1" --lift --message-file "$T/lift12" --event 23 --from director-a >/dev/null 2>"$T/err"; rc=$?
eq "the same lift again changes nothing" "0 $N1" "$rc $(entries "$SM1")"

echo "== the manager refuses a lift it can't verify =="
board_at "$H"
SM2=coordinate-roadmap-lift-b-20260926T080000Z
manager "$SM2" lift-b "$H"
copyto "$SM2" --add --message-file "$T/msg" --event 31 --from director-a >/dev/null 2>"$T/err"
sed "1s/$MOVED/$H/" "$T/lift12" > "$T/lift-placed"
SNAP=$(session_snapshot "$SM2")
copyto "$SM2" --lift --message-file "$T/lift-placed" --event 32 --from director-a >/dev/null 2>"$T/err"; rc=$?
eq "a lift at the placed-on head is refused" 65 "$rc"
grep -q "the head $H12 was placed on" "$T/err" && ok "  ... saying so" || bad "  ... saying so" "$(cat "$T/err")"
eq "  ... the record unchanged, and still held" "same 0 held 12 $H" \
    "$([ "$SNAP" = "$(session_snapshot "$SM2")" ] && echo same) $(landcheck "$SM2")"
board_at "$MOVED"
SM3=coordinate-roadmap-lift-c-20260926T080000Z
manager "$SM3" lift-c "$MOVED"
copyto "$SM3" --add --message-file "$T/msg" --event 41 --from director-a >/dev/null 2>"$T/err"
sed "1s/$MOVED/$SHA_HEAD/" "$T/lift12" > "$T/lift-old"
SNAP=$(session_snapshot "$SM3")
copyto "$SM3" --lift --message-file "$T/lift-old" --event 42 --from director-a >/dev/null 2>"$T/err"; rc=$?
eq "a replayed lift naming an older head than the verified head is refused" 65 "$rc"
grep -q "has verified head $MOVED" "$T/err" && ok "  ... saying so" || bad "  ... saying so" "$(cat "$T/err")"
copyto "$SM3" --lift --message-file "$T/lift12" --event 43 --from director-x >/dev/null 2>"$T/err"; rc=$?
eq "a lift from anyone but the address reports-to names is refused" 65 "$rc"
grep -q 'reports to director at director-a' "$T/err" && ok "  ... saying so" || bad "  ... saying so" "$(cat "$T/err")"
eq "  ... each leaving the record unchanged, and still held" "same 0 held 12 $MOVED" \
    "$([ "$SNAP" = "$(session_snapshot "$SM3")" ] && echo same) $(landcheck "$SM3")"

echo "== the lift fails closed, and --lift-releasable lifts it later =="
# #13's live head is $MOVED, and its hold was placed on $H.
N0=$(entries "$SD") C0=$(nalignment "$SD")
headfail 13
callat acme/widgets#13 "$MOVED" fits
direct --on acme/widgets#13 > "$T/out" 2>"$T/err"; rc=$?
eq "a fits call when the live head can't be read is written, and exits 13" "13 $((C0 + 1))" "$rc $(nalignment "$SD")"
grep -q "lift blocked: .*$H13 stands" "$T/err" && ok "  ... naming the hold" || bad "  ... naming the hold" "$(cat "$T/err")"
eq "  ... which stands, with no lift message" "|" "$(lifted "$SD" "$H13")|$(cat "$T/out")"
FIT13=$(last_call "$SD")
releasable acme/widgets#13 > "$T/out" 2>"$T/err"; rc=$?
eq "--lift-releasable while the live head can't be read exits 13, the hold standing" "13 |" "$rc $(lifted "$SD" "$H13")|$(cat "$T/out")"
grep -q "lift blocked: .*$H13 stands" "$T/err" && ok "  ... naming the hold" || bad "  ... naming the hold" "$(cat "$T/err")"
headok
releasable acme/widgets#13 > "$T/lift13" 2>"$T/err"; rc=$?
eq "--lift-releasable lifts the releasable hold" "0 director at director-a, fits at $MOVED" "$rc $(lifted_by "$SD" "$H13")"
eq "  ... writing no alignment entry" "$((C0 + 1))" "$(nalignment "$SD")"
eq "  ... and printing the lift message" "Alignment lift: acme/widgets#13 at $MOVED|Hold: $H13|Call: fits, entry $FIT13" "$(joined "$T/lift13")"
N1=$(entries "$SD")
releasable acme/widgets#13 > "$T/out" 2>"$T/err"; rc=$?
eq "--lift-releasable with no hold standing lifts and prints nothing" "0 $N1 " "$rc $(entries "$SD") $(cat "$T/out")"

echo "== a pull request the manager wrote: the lift checks the live head =="
# $SM3's only holding is on #12, so #13 is one no holding links.
copyto "$SM3" --add --message-file "$T/msg13" --event 51 --from director-a >/dev/null 2>"$T/err"
eq "the copy of #13's hold is in the manager's record" "1" "$(nalign "$SM3" acme/widgets#13)"
sed "1s/$MOVED/$SHA_HEAD/" "$T/lift13" > "$T/lift13-other"
SNAP=$(session_snapshot "$SM3")
copyto "$SM3" --lift --message-file "$T/lift13-other" --event 52 --from director-a >/dev/null 2>"$T/err"; rc=$?
eq "a lift at a head other than the live head is refused" 65 "$rc"
grep -q "its live head is $MOVED" "$T/err" && ok "  ... saying so" || bad "  ... saying so" "$(cat "$T/err")"
headfail 13
copyto "$SM3" --lift --message-file "$T/lift13" --event 53 --from director-a >/dev/null 2>"$T/err"; rc=$?
headok
eq "a lift when the live head can't be read exits 2" 2 "$rc"
grep -q "can't be read.*$H13 stands" "$T/err" && ok "  ... saying the hold stands" || bad "  ... saying the hold stands" "$(cat "$T/err")"
eq "  ... each leaving the record unchanged" "same" "$([ "$SNAP" = "$(session_snapshot "$SM3")" ] && echo same)"
copyto "$SM3" --lift --message-file "$T/lift13" --event 54 --from director-a >/dev/null 2>"$T/err"; rc=$?
eq "a lift at the live head lifts the copy" "0 director at director-a, fits at $MOVED" "$rc $(lifted_by "$SM3" "$H13")"

echo "== the guard reads the calls in entry order =="
# #13's live head is still $MOVED, whose fits call came before this hold.
callat acme/widgets#13 "$SHA_HEAD" diverges "standing s1" none hold
direct --on acme/widgets#13 --receiver mgr-widgets > "$T/out" 2>"$T/err"; rc=$?
H13B="align-widgets-13-$SHA_HEAD"
eq "a diverges call on another head places a hold named after that head" "0 $H13B" \
    "$rc $(holds "$SD" | jq -r '[.[] | select(.on == "acme/widgets#13" and .lifted == "") | .hold] | join(" ")')"
releasable acme/widgets#13 > "$T/out" 2>"$T/err"; rc=$?
eq "a fits call for the live head made before the hold's diverges call releases nothing" "0 |" "$rc $(lifted "$SD" "$H13B")|$(cat "$T/out")"
grep -q "doesn't come after the diverges call" "$T/err" && ok "  ... saying why" || bad "  ... saying why" "$(cat "$T/err")"
headfail 13
callat acme/widgets#13 "$MOVED" fits
direct --on acme/widgets#13 > "$T/out" 2>"$T/err"; rc=$?
headok
FIT13B=$(last_call "$SD")
eq "a later fits call for the live head, its lift blocked, leaves the hold releasable" "13 " "$rc $(lifted "$SD" "$H13B")"
callat acme/widgets#13 "$SHA_OTHER" fits
direct --on acme/widgets#13 > "$T/out" 2>"$T/err"; rc=$?
eq "a fits call at a head that isn't the live head lifts nothing" "0 |" "$rc $(lifted "$SD" "$H13B")|$(cat "$T/out")"
grep -q "the call just written isn't for the live head" "$T/err" && ok "  ... saying why" || bad "  ... saying why" "$(cat "$T/err")"
releasable acme/widgets#13 > "$T/out" 2>"$T/err"; rc=$?
eq "--lift-releasable then lifts it on the fits call for the live head" "0 director at director-a, fits at $MOVED|Call: fits, entry $FIT13B" \
    "$rc $(lifted_by "$SD" "$H13B")|$(sed -n 3p "$T/out")"

echo "== a person's lift on an unchanged head =="
callat acme/widgets#12 "$MOVED" diverges "standing s1" none hold
direct --on acme/widgets#12 > "$T/out" 2>"$T/err"; rc=$?
eq "a diverges call after the lift places a new hold, on the live head" "0 align-widgets-12-$MOVED" \
    "$rc $(holds "$SD" | jq -r '[.[] | select(.on == "acme/widgets#12" and .lifted == "") | .hold] | join(" ")')"
bash "$HERE/state-hold.sh" --session "$SD" --lift --hold "align-widgets-12-$MOVED" --by alice >/dev/null 2>"$T/err"; rc=$?
eq "the director records the owner's lift with state-hold.sh, naming the person" "0 alice" "$rc $(lifted_by "$SD" "align-widgets-12-$MOVED")"
board_at "$H"
bash "$HERE/state-hold.sh" --session "$SM2" --lift --hold "$H12" --by "alice, relayed by director" >/dev/null 2>"$T/err"; rc=$?
eq "the manager records the relayed word on its copy" "0 alice, relayed by director" "$rc $(lifted_by "$SM2" "$H12")"
eq "  ... and land-check reports the posture at the placed-on head" "0 permit 12 $H" "$(landcheck "$SM2")"

echo "== the records name who decided each hold and lift, and on what =="
eq "the director's row: the decider, the pull request and the placed-on head" \
    "director at director-a, receiver manager at mgr-widgets|acme/widgets#12|$H12" \
    "$(holds "$SD" | jq -r --arg h "$H12" '.[] | select(.hold == $h) | "\(.set_by)|\(.on)|\(.hold)"')"
eq "  ... its Lifted cell the decider, the call and the head it was released on" \
    "director at director-a, fits with follow-ups at $MOVED" "$(lifted_by "$SD" "$H12")"
eq "  ... its account the call's entry number" 1 \
    "$(elist "$SD" | jq --arg h "$H12" --arg e "released at $MOVED, on the fits with follow-ups call at entry $FIT12" '[.[] | select(.kind == "hold" and (.text | contains($h) and contains($e)))] | length')"
eq "the manager's row: the same decider, pull request, placed-on head and Lifted text" \
    "director at director-a, receiver manager at mgr-widgets|acme/widgets#12|$H12|director at director-a, fits with follow-ups at $MOVED" \
    "$(holds "$SM1" | jq -r --arg h "$H12" '.[] | select(.hold == $h) | "\(.set_by)|\(.on)|\(.hold)"')|$(lifted_by "$SM1" "$H12")"
eq "  ... its account the hold, the head, the call's entry and the event" 1 \
    "$(elist "$SM1" | jq --arg h "$H12" --arg m "$MOVED" --arg e "entry $FIT12" '[.[] | select(.kind == "hold" and (.text | contains($h) and contains($m) and contains($e) and contains("event 22")))] | length')"
for s in "$SD" "$SM1" "$SM2" "$SM3"; do holds "$s"; done | jq -s 'add' > "$T/allholds.json"
eq "every hold row keeps the Holds grammar's six keys, and no other" "true" \
    "$(jq 'all(.[]; (keys | sort) == ["hold", "lifted", "on", "set", "set_by", "until"])' "$T/allholds.json")"
eq "  ... and every Lifted cell reads empty or <minute> by <who>" "true" \
    "$(jq 'all(.[]; .lifted == "" or (.lifted | test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}Z by .+$")))' "$T/allholds.json")"
eq "nothing in this suite was written on GitHub" "" "$(gh_writes)"

echo
echo "alignment-call: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
