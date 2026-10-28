#!/usr/bin/env bash
# board-record_test.sh -- board-record.sh turns board-verdict.sh's JSON into
# a sealed verified, unverified or pending token, keeps the JSON in
# coord/board.json, and refuses to read the board before the prediction.
#
# Covers: a verified board (the token carries the head, sealed to the latest
# entry into verify_board, and coord/board.json's verdict, head, reasons and
# skipped match the board read); one unverified, one pending and one not-run
# fixture each print their word with no head; a refused check rollup reads source
# `actions` and prints the same verified, unverified or pending, and
# check-unreadable for a required check only another app's check run reports
# (board-unreadable when a read also failed);
# a failed board read or the deadline prints
# board-unreadable, a merged pull request not-open, and a pull request no
# single holding links (none, two repositories, a bad link) unlinked with a
# reason for each (nothing read), each sealed with its reason in
# coord/board.json in board-verdict.sh's shape; an unreadable record prints
# board-unreadable; the review round its report carried (malformed:
# unevidenced; failing or absent: verified, land's to refuse), never the
# body (a malformed table, or a body that can't be read, changes nothing,
# and no body is read); the round the worker recorded in its session, read
# before the report's (malformed: unevidenced; a failed request read: exit
# 2); a failed context write exits 2; no
# prediction since the latest arrival at verify exits 2 with
# nothing read; the pull request from report_facts's REPORT capture (none,
# stale, unsealed or absent exits 2); --no-seal; the repository from the
# record's Holdings row.
#
# Runs offline on the gh-board and koto stand-ins in a localized plugin tree.
# Usage: bash skills/coordinate/scripts/board-record_test.sh
set -uo pipefail
. "$(dirname "$0")/../../../scripts/lib/koto-test-guard.sh" || exit 1

HERE=$(cd "$(dirname "$0")" && pwd)
command -v jq >/dev/null 2>&1 || { echo "SKIP: jq not on PATH"; exit 0; }
T=$(mktemp -d "${TMPDIR:-/tmp}/board-record-test.XXXXXX") || exit 1
ktg_on_exit 'rm -rf "$T"'
. "$HERE/testdata/board/helpers.sh"
bt_setup
# A body for pull request #12's view; verify_board never reads it for the round.
BT_PRVIEW_BODY=$(printf 'Part one.\n\n---\n\nNo panel.\n')
BR="$PS/board-record.sh"
CL="$PS/coord-log.sh"
PERMIT="readable merge:permit close:permit teardown:permit release:permit"
N=0
fresh() { # a run at verify_board with its prediction
    N=$((N + 1))
    S="coordinate-demo-20260926T1200$(printf '%02d' "$N")Z"
    bt_run "$S" "$PERMIT"
    bt_enter "$S" verify_board
}
ctx() { cat "$KOTO_BOARD_DIR/sessions/$S/ctx/coord__board.json" 2>/dev/null; }

echo "== verified =="
fresh
bt_board skipped-nonrequired-job
bash "$PS/board-verdict.sh" --repo acme/widgets --pr 12 > "$T/direct" 2>/dev/null
OUT=$(bash "$BR" --session "$S" --pr 12 --repo acme/widgets 2>"$T/err"); rc=$?
eq "a verified board exits 0" 0 $rc
eq "the token carries the verified head" "verified 12 $H" "${OUT% sealed:*}"
bash "$CL" check --session "$S" --state verify_board --sealed "$OUT" && ok "sealed to the latest entry into verify_board" || bad "sealed to the latest entry into verify_board"
eq "coord/board.json's verdict, head, reasons and skipped match the read" \
    "$(jq -c '{verdict, head, reasons, skipped}' "$T/direct")" "$(ctx | jq -c '{verdict, head, reasons, skipped}')"
eq "and it lists the skipped job" '[{"run":101,"job":1003,"name":"LLM Quality Gate"}]' "$(ctx | jq -c .skipped)"

echo "== unverified, pending and not-run record no head =="
# One fixture per verdict: board-verdict_test.sh judges every fixture, and
# board-record.sh only maps the verdict word to its token.
SEEN=" "
for cf in "$TD"/board/cases/*.jq; do
    name=$(basename "$cf" .jq)
    set -- $(sed -n 's/^# expect: //p' "$cf")
    [ "$1" = unverified ] || [ "$1" = pending ] || [ "$1" = not-run ] || continue
    case "$SEEN" in *" $1 "*) continue ;; esac
    sed -n 's/^# args: //p' "$cf" | grep -q . && continue
    sed -n 's/^# env: //p' "$cf" | grep -q . && continue
    SEEN="$SEEN$1 "
    want=$1; shift
    fresh
    bt_board "$name"
    OUT=$(bash "$BR" --session "$S" --pr 12 --repo acme/widgets 2>"$T/err"); rc=$?
    if [ $rc -eq 0 ] && [ "${OUT% sealed:*}" = "$want 12 none" ] \
        && [ "$(ctx | jq -r .verdict)" = "$want" ] && ctx | jq -e --arg c "$1" 'any(.reasons[]; .code == $c)' >/dev/null; then
        ok "$name: $want 12 none, $1 in coord/board.json"
    else
        bad "$name" "rc=$rc out=$OUT ctx=$(ctx) err=$(cat "$T/err")"
    fi
done

echo "== checks the token can't read =="
fresh; bt_board checks-refused
OUT=$(bash "$BR" --session "$S" --pr 12 --repo acme/widgets 2>"$T/err"); rc=$?
eq "a refused check rollup, green from the Actions jobs and statuses: verified at the head" "verified 12 $H" "${OUT% sealed:*}"
eq "and coord/board.json names the source it read" actions "$(ctx | jq -r .source)"
fresh; bt_board checks-refused-rollup-only-required
eq "a required check only another app's check run reports, unseen under the fallback: check-unreadable, never verified" "check-unreadable 12 none" "$(bash "$BR" --session "$S" --pr 12 --repo acme/widgets --no-seal 2>/dev/null)"
fresh; bt_board checks-refused-statuses-refused
eq "a required status the token can't read: check-unreadable too" "check-unreadable 12 none" "$(bash "$BR" --session "$S" --pr 12 --repo acme/widgets --no-seal 2>/dev/null)"
fresh; bt_board rules-unreadable
eq "a board that also failed a read is board-unreadable, never check-unreadable" "board-unreadable 12 none" "$(bash "$BR" --session "$S" --pr 12 --repo acme/widgets --no-seal 2>/dev/null)"
fresh; bt_board checks-refused-job-red
eq "a refused check rollup with a red job: unverified, as from the checks" "unverified 12 none" "$(bash "$BR" --session "$S" --pr 12 --repo acme/widgets --no-seal 2>/dev/null)"
fresh; bt_board checks-refused-run-pending
eq "a refused check rollup with a run going: pending, as from the checks" "pending 12 none" "$(bash "$BR" --session "$S" --pr 12 --repo acme/widgets --no-seal 2>/dev/null)"
fresh; bt_board complete-board
bash "$BR" --session "$S" --pr 12 --repo acme/widgets >/dev/null 2>&1
eq "a readable rollup is the checks source" checks "$(ctx | jq -r .source)"

echo "== the round the worker's report carried =="
fresh; bt_board complete-board
bt_reported_round "$S" worker-f12 "$(bt_round | jq -c '.seats[1].run = "agent-r1"')"
OUT=$(bash "$BR" --session "$S" --pr 12 --repo acme/widgets 2>"$T/err")
eq "a green board with seats sharing a Run: unevidenced, no head" "unevidenced 12 none" "${OUT% sealed:*}"
eq "and coord/board.json names the rule broken and the report" "run-repeated report" "$(ctx | jq -r '"\(.evidence.reason) \(.evidence.source)"')"
eq "  ... with a reason saying it was the round the report carried" "the review round the worker's report carried is malformed: run-repeated" "$(ctx | jq -r '.reasons[] | select(.code == "unevidenced") | .detail')"
fresh; bt_board complete-board; bt_reported_round "$S" worker-f12 "$(bt_round)"
eq "a green board with a well-formed round: verified" "verified 12 $H" "$(bash "$BR" --session "$S" --pr 12 --repo acme/widgets --no-seal 2>/dev/null)"
fresh; bt_board complete-board; bt_reported_round "$S" worker-f12 "$(bt_round "$H" fail)"
eq "a failing seat is land's to refuse, not verify's" "verified 12 $H" "$(bash "$BR" --session "$S" --pr 12 --repo acme/widgets --no-seal 2>/dev/null)"
fresh; bt_board complete-board; bt_reported_round "$S" worker-f12
eq "no round yet is land's to refuse, not verify's" "verified 12 $H" "$(bash "$BR" --session "$S" --pr 12 --repo acme/widgets --no-seal 2>/dev/null)"
fresh; bt_board complete-board; bt_reported_round "$S" worker-f12
bt_table_body | sed 's/comment-102/comment-101/' > "$T/body"; bt_prview CLEAN "$T/body"
eq "a malformed Review panel table in the body is never read: verified" "verified 12 $H" "$(bash "$BR" --session "$S" --pr 12 --repo acme/widgets --no-seal 2>/dev/null)"
fresh; bt_board complete-board; bt_reported_round "$S" worker-f12 "$(bt_round)"
rm -f "$GH_BOARD_DIR/prview-12.out"; echo 'gh: Server Error (HTTP 502)' > "$GH_BOARD_DIR/prview-12.err"; echo 1 > "$GH_BOARD_DIR/prview-12.rc"
: > "$GH_BOARD_DIR/calls"
eq "a body that can't be read doesn't matter: verified" "verified 12 $H" "$(bash "$BR" --session "$S" --pr 12 --repo acme/widgets --no-seal 2>/dev/null)"
grep -q 'pr view' "$GH_BOARD_DIR/calls" && bad "  ... and the body is never read" "$(cat "$GH_BOARD_DIR/calls")" || ok "  ... and the body is never read"
rm -f "$GH_BOARD_DIR/prview-12.err" "$GH_BOARD_DIR/prview-12.rc"

echo "== the round recorded in the worker's session =="
REQ=req-board-record-round
fresh; bt_board complete-board
bt_leg_round "$REQ" work-on issue_12 "$(bt_round | jq -c '.seats[1].run = "agent-r1"')"
OUT=$(bash "$BR" --session "$S" --pr 12 --repo acme/widgets 2>"$T/err")
eq "a malformed round in the session: unevidenced" "unevidenced 12 none" "${OUT% sealed:*}"
eq "  ... and coord/board.json names the rule and the session" "run-repeated session" "$(ctx | jq -r '"\(.evidence.reason) \(.evidence.source)"')"
eq "  ... with a reason saying it was the round recorded in the session" "the review round recorded in the worker's session is malformed: run-repeated" "$(ctx | jq -r '.reasons[] | select(.code == "unevidenced") | .detail')"
fresh; bt_board complete-board
bt_leg_round "$REQ" work-on issue_12 "$(bt_round)"
bt_report "$S" w "$(bt_round | jq -c '.seats[1].run = "agent-r1"')"
eq "a well-formed session round is read before a malformed reported one: verified" "verified 12 $H" "$(bash "$BR" --session "$S" --pr 12 --repo acme/widgets --no-seal 2>/dev/null)"
fresh; bt_board complete-board
bt_leg_round "$REQ" work-on issue_12
bt_report "$S" w "$(bt_round | jq -c '.seats[1].run = "agent-r1"')"
eq "a bound session with no round: the report's round is read" "unevidenced 12 none" "$(bash "$BR" --session "$S" --pr 12 --repo acme/widgets --no-seal 2>/dev/null)"
fresh; bt_board complete-board
bt_leg_round "$REQ" work-on issue_12 "$(bt_round)"
touch "$KOTO_BOARD_DIR/requests/$REQ.fail"
bash "$BR" --session "$S" --pr 12 --repo acme/widgets --no-seal >/dev/null 2>&1
eq "a request read that fails: exit 2" 2 $?
rm -f "$KOTO_BOARD_DIR/requests/$REQ.fail"
echo '[]' > "$BT_STATE/holdings"

echo "== a board that can't be judged still leaves verify_board =="
fresh; bt_board rules-unreadable
OUT=$(bash "$BR" --session "$S" --pr 12 --repo acme/widgets 2>"$T/err"); rc=$?
eq "a board read that fails exits 0" 0 $rc
eq "with unreadable" "board-unreadable 12 none" "${OUT% sealed:*}"
bash "$CL" check --session "$S" --state verify_board --sealed "$OUT" && ok "sealed to the latest entry into verify_board" || bad "sealed to the latest entry into verify_board"
eq "and coord/board.json keeps the reason" required-set-unreadable "$(ctx | jq -r '.reasons[0].code')"
grep -q 'required-set-unreadable' "$T/err" && ok "naming the reason on stderr" || bad "naming the reason on stderr" "$(cat "$T/err")"
fresh; bt_board deadline
eq "a read past the deadline: unreadable" "board-unreadable 12 none" "$(BOARD_DEADLINE_SECS=2 bash "$BR" --session "$S" --pr 12 --repo acme/widgets --no-seal 2>/dev/null)"
fresh; bt_board pr-merged
OUT=$(bash "$BR" --session "$S" --pr 12 --repo acme/widgets 2>"$T/err"); rc=$?
eq "a merged pull request: not-open" "0 not-open 12 none" "$rc ${OUT% sealed:*}"
eq "and coord/board.json says it merged" MERGED "$(ctx | jq -r .pr_state)"
fresh; bt_board complete-board; bt_holdings "[#9](https://github.com/acme/widgets/pull/9)"
rm -f "$GH_BOARD_DIR/calls"
OUT=$(bash "$BR" --session "$S" --pr 12 2>"$T/err"); rc=$?
eq "no holding links #12 (torn down after it merged): unlinked" "0 unlinked 12 none" "$rc ${OUT% sealed:*}"
eq "and coord/board.json says why" no-holding "$(ctx | jq -r '.reasons[0].code')"
[ ! -s "$GH_BOARD_DIR/calls" ] && ok "and no board was read without a repository" || bad "and no board was read without a repository" "$(cat "$GH_BOARD_DIR/calls")"
bash "$PS/board-verdict.sh" --repo acme/widgets --pr 12 > "$T/direct" 2>/dev/null
eq "in board-verdict.sh's shape" "$(jq -c 'keys' "$T/direct")" "$(ctx | jq -c 'keys')"
bt_holdings "[#12](https://github.com/acme/widgets/pull/12)" "[#12](https://github.com/acme/gadgets/pull/12)"
fresh
eq "#12 linked in two repositories: unlinked" "unlinked 12 none" "$(bash "$BR" --session "$S" --pr 12 2>/dev/null | sed 's/ sealed:.*//')"
eq "naming the two repositories as the reason" several-holdings "$(ctx | jq -r '.reasons[0].code')"
bt_holdings "[#12](https://github.com/acme/../pull/12)"
fresh
eq "#12 linked to a repository that isn't owner/repo: unlinked" "unlinked 12 none" "$(bash "$BR" --session "$S" --pr 12 2>/dev/null | sed 's/ sealed:.*//')"
eq "naming the bad link as the reason" bad-link "$(ctx | jq -r '.reasons[0].code')"
echo 2 > "$BT_STATE/holding.rc"
fresh
eq "the holdings can't be read: board-unreadable" "board-unreadable 12 none" "$(bash "$BR" --session "$S" --pr 12 2>/dev/null | sed 's/ sealed:.*//')"
eq "in board-verdict.sh's shape too" "$(jq -c 'keys' "$T/direct")" "$(ctx | jq -c 'keys')"
rm -f "$BT_STATE/holding.rc"

echo "== errors exit 2 =="
fresh; bt_board complete-board; touch "$KOTO_BOARD_DIR/fail-context"
bash "$BR" --session "$S" --pr 12 --repo acme/widgets >"$T/out" 2>/dev/null; eq "a failed context write exits 2" 2 $?
rm -f "$KOTO_BOARD_DIR/fail-context"

echo "== the prediction comes first =="
N=$((N + 1)); S="coordinate-demo-20260926T1200$(printf '%02d' "$N")Z"
bt_run "$S" "$PERMIT"; bt_enter "$S" verify_board; bt_enter "$S" verify; bt_enter "$S" verify_board
bt_board complete-board
bash "$BR" --session "$S" --pr 12 --repo acme/widgets >"$T/out" 2>"$T/err"; rc=$?
eq "no prediction since the latest arrival at verify: exit 2" 2 $rc
[ ! -s "$GH_BOARD_DIR/calls" ] && ok "and nothing was read" || bad "and nothing was read" "$(cat "$GH_BOARD_DIR/calls")"
N=$((N + 1)); S="coordinate-demo-20260926T1200$(printf '%02d' "$N")Z"
bt_session "$S"; bt_enter "$S" verify_board
bash "$BR" --session "$S" --pr 12 --repo acme/widgets >/dev/null 2>&1; eq "never at verify: exit 2" 2 $?
N=$((N + 1)); S="coordinate-demo-20260926T1200$(printf '%02d' "$N")Z"
bt_session "$S"; bt_enter "$S" verify; bt_evidence "$S" wait '{"event":"report"}'; bt_enter "$S" verify_board
bash "$BR" --session "$S" --pr 12 --repo acme/widgets >/dev/null 2>&1; eq "evidence in another state isn't the prediction: exit 2" 2 $?

echo "== the pull request from report_facts's capture =="
reported() { # reported <REPORT token> : a run whose report_facts sealed the token, now at verify_board
    N=$((N + 1)); S="coordinate-demo-20260926T1200$(printf '%02d' "$N")Z"
    bt_session "$S"; bt_enter "$S" start_posture; bt_sealed "$S" start_posture POSTURE "$PERMIT"
    bt_enter "$S" report_facts; bt_sealed "$S" report_facts REPORT "$1"
    bt_enter "$S" classify_report; bt_enter "$S" verify; bt_evidence "$S" verify '{"prediction":"green"}'
    bt_enter "$S" verify_board
    bt_board complete-board
}
reported "holding 12 plugin-registry"
OUT=$(bash "$BR" --session "$S" --repo acme/widgets 2>"$T/err"); rc=$?
eq "without --pr, the latest REPORT capture names the pull request" "verified 12 $H" "${OUT% sealed:*}"
grep -q 'pulls/12/files' "$GH_BOARD_DIR/calls" && ok "and the board read is of #12" || bad "and the board read is of #12"
bt_holdings "[#12](https://github.com/acme/widgets/pull/12)"
eq "with neither --pr nor --repo, the session alone is enough" "verified 12 $H" "$(bash "$BR" --session "$S" --no-seal 2>"$T/err")"
# Nothing to verify leaves verify_board on a sealed no-pr, never an action that
# fails on every tick: what it read is sealed in report_facts' capture.
no_pr() { # no_pr <label> <reason code>: the run at verify_board reads no-pr, sealed
    : > "$GH_BOARD_DIR/calls"
    OUT=$(bash "$BR" --session "$S" 2>"$T/err"); rc=$?
    eq "$1: exit 0" 0 $rc
    eq "$1: no-pr" "no-pr none none" "${OUT% sealed:*}"
    bash "$CL" check --session "$S" --state verify_board --sealed "$OUT" >/dev/null 2>&1 \
        && ok "$1: sealed to verify_board" || bad "$1: sealed to verify_board" "$OUT"
    eq "$1: coord/board.json names why" "no-pr $2" "$(ctx | jq -r '"\(.verdict) \(.reasons[0].code)"')"
    [ -s "$GH_BOARD_DIR/calls" ] && bad "$1: no board read" "$(cat "$GH_BOARD_DIR/calls")" || ok "$1: no board read"
}
reported "holding none plugin-registry"
no_pr "a holding with no pull request yet" no-pull-request
reported "unknown plugin-registry"
no_pr "a report capture that isn't a holding" not-a-holding
reported "holding 12 plugin-registry"; bt_enter "$S" report_facts
no_pr "a stale report capture (report_facts entered since)" no-report
N=$((N + 1)); S="coordinate-demo-20260926T1200$(printf '%02d' "$N")Z"
bt_run "$S" "$PERMIT"; bt_enter "$S" report_facts; bt_capture "$S" REPORT "holding 12 plugin-registry"
bt_enter "$S" verify; bt_evidence "$S" verify '{"prediction":"green"}'; bt_enter "$S" verify_board
no_pr "an unsealed report capture" no-report
fresh
no_pr "no report capture at all" no-report
reported "holding 12 plugin-registry"
eq "--pr still overrides the report" "verified 12 $H" "$(bash "$BR" --session "$S" --pr 12 --repo acme/widgets --no-seal 2>/dev/null)"

echo "== --no-seal and the repository =="
fresh; bt_board complete-board
eq "--no-seal prints the bare token" "verified 12 $H" "$(bash "$BR" --session "$S" --pr 12 --repo acme/widgets --no-seal 2>/dev/null)"
[ -z "$(ctx)" ] && ok "--no-seal writes no context key" || bad "--no-seal writes no context key"
bt_holdings "[#12](https://github.com/acme/widgets/pull/12)"
eq "without --repo, the Holdings row linking #12 names the repository" "verified 12 $H" "$(bash "$BR" --session "$S" --pr 12 --no-seal 2>/dev/null)"
bt_holdings "[#9](https://github.com/acme/widgets/pull/9)"
eq "no holding links #12: unlinked" "unlinked 12 none" "$(bash "$BR" --session "$S" --pr 12 --no-seal 2>/dev/null)"
bash "$BR" --session "$S" --bogus >/dev/null 2>&1; eq "usage: exit 64" 64 $?
bash "$BR" --pr 12 >/dev/null 2>&1; eq "no session: exit 64" 64 $?
bash "$BR" --session "$S" --pr x12 >/dev/null 2>&1; eq "a malformed number: exit 64" 64 $?

echo "== verify_board: the koto calls don't grow with the entries (shirabe#1315) =="
# The step reads the record's Holdings section alone and never lists record/,
# which names every entry: the same verified board on a record with a few
# entries and with 300 makes the same koto calls. The real state-holding.sh
# stands in the tree here, so the Holdings read reaches the session's keys.
# filler <session> <count>: plain entries numbered from 1, as the stand-in
# keeps keys.
filler() {
    local d="$KOTO_BOARD_DIR/sessions/$1/ctx" i
    mkdir -p "$d"
    for ((i = 1; i <= $2; i++)); do
        printf '{"n":%d,"stamp":"2026-09-26T08:00:00Z","kind":"entry","text":"note %d"}' "$i" "$i" > "$d/record__entries__$(printf '%06d' "$i")"
    done
}
# koto_calls <entries>: a run at verify_board on a green board, report_facts
# having sealed worker-f2's holding of #12, its record holding that row and
# <entries> entries, run as the template runs it (the pull request from the
# capture, the repository from the row); prints the token and the step's koto
# calls, the calls kept in $T/kc.calls.
koto_calls() {
    N=$((N + 1)); S="coordinate-demo-20260926T1200$(printf '%02d' "$N")Z"
    bt_run "$S" "$PERMIT"
    bt_enter "$S" report_facts; bt_sealed "$S" report_facts REPORT "holding 12 worker-f2"
    bt_enter "$S" classify_report; bt_enter "$S" verify; bt_evidence "$S" verify '{"prediction":"green"}'
    bt_enter "$S" verify_board
    bt_board complete-board
    bt_record_paused '[]'
    filler "$S" "$1"
    : > "$KOTO_BOARD_DIR/koto.calls"
    OUT=$(bash "$BR" --session "$S" 2>"$T/err")
    printf '%s %s' "${OUT% sealed:*}" "$(wc -l < "$KOTO_BOARD_DIR/koto.calls" | tr -d ' ')"
    cp "$KOTO_BOARD_DIR/koto.calls" "$T/kc.calls"
}
cp "$HERE/state-holding.sh" "$PS/state-holding.sh"
FEW=$(koto_calls 3)
MANY=$(koto_calls 300)
cp "$TD/board/stand-in-state-holding.sh" "$PS/state-holding.sh"
eq "the same token and koto calls with 3 entries and with 300 (${FEW##* } calls)" "$FEW" "$MANY"
eq "  ... verified at the head" "verified 12 $H" "${FEW% *}"
eq "  ... reading the Holdings section" 1 "$(grep -c '^context get [^ ]* record/holdings$' "$T/kc.calls")"
eq "  ... never listing record/" 0 "$(grep -cE '^context list (.* )?--prefix record/( |$)' "$T/kc.calls")"

echo
echo "board-record: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
