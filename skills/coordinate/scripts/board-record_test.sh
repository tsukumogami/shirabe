#!/usr/bin/env bash
# board-record_test.sh -- board-record.sh turns board-verdict.sh's JSON into
# a sealed verified, unverified or pending token, keeps the JSON in
# coord/board.json, and refuses to read the board before the prediction.
#
# Covers: a verified board (the token carries the head, sealed to the latest
# entry into verify_board, and coord/board.json's verdict, head, reasons and
# skipped match the board read); every unverified fixture prints unverified
# with no head; a pending board; a refused check rollup reads source
# `actions` and prints actions-green (never verified, even with a check only
# isRequired names unseen); a failed board read or the deadline prints
# board-unreadable, a merged pull request not-open, and a pull request no
# single holding links (none, two repositories, a bad link) unlinked with a
# reason for each (nothing read), each sealed with its reason in
# coord/board.json in board-verdict.sh's shape; an unreadable record prints
# board-unreadable; a failed context write exits 2; no
# prediction since the latest arrival at verify exits 2 with
# nothing read; the pull request from report_facts's REPORT capture (none,
# stale, unsealed or absent exits 2); --no-seal; the repository from the
# record's Holdings row.
#
# Runs offline on the gh-board and koto stand-ins in a localized plugin tree.
# Usage: bash skills/coordinate/scripts/board-record_test.sh
set -uo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
command -v jq >/dev/null 2>&1 || { echo "SKIP: jq not on PATH"; exit 0; }
T=$(mktemp -d "${TMPDIR:-/tmp}/board-record-test.XXXXXX")
trap 'rm -rf "$T"' EXIT
. "$HERE/testdata/board/helpers.sh"
bt_setup
BR="$PS/board-record.sh"
CL="$PS/coord-log.sh"
PERMIT="readable merge:permit close:permit teardown:permit"
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
for cf in "$TD"/board/cases/*.jq; do
    name=$(basename "$cf" .jq)
    set -- $(sed -n 's/^# expect: //p' "$cf")
    [ "$1" = unverified ] || [ "$1" = pending ] || [ "$1" = not-run ] || continue
    sed -n 's/^# args: //p' "$cf" | grep -q . && continue
    sed -n 's/^# env: //p' "$cf" | grep -q . && continue
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
eq "a refused check rollup, green from the Actions jobs: actions-green, no head" "actions-green 12 none" "${OUT% sealed:*}"
eq "and coord/board.json names the source it read" actions "$(ctx | jq -r .source)"
fresh; bt_board checks-refused-rollup-only-required
eq "a check only isRequired names, unseen under the fallback: still actions-green, never verified" "actions-green 12 none" "$(bash "$BR" --session "$S" --pr 12 --repo acme/widgets --no-seal 2>/dev/null)"
fresh; bt_board complete-board
bash "$BR" --session "$S" --pr 12 --repo acme/widgets >/dev/null 2>&1
eq "a readable rollup is the checks source" checks "$(ctx | jq -r .source)"

echo "== the body's Review panel =="
fresh; bt_board complete-board; bt_body | sed 's/comment-102/comment-101/' > "$T/body"; bt_prview CLEAN "$T/body"
OUT=$(bash "$BR" --session "$S" --pr 12 --repo acme/widgets 2>"$T/err")
eq "a green board with seats sharing a Run: unevidenced, no head" "unevidenced 12 none" "${OUT% sealed:*}"
eq "and coord/board.json names the rule broken" run-repeated "$(ctx | jq -r .evidence.reason)"
fresh; bt_board complete-board; bt_prview CLEAN
eq "a green board with a well-formed table: verified" "verified 12 $H" "$(bash "$BR" --session "$S" --pr 12 --repo acme/widgets --no-seal 2>/dev/null)"
fresh; bt_board complete-board; bt_body "$H" fail > "$T/body"; bt_prview CLEAN "$T/body"
eq "a failing seat is land's to refuse, not verify's" "verified 12 $H" "$(bash "$BR" --session "$S" --pr 12 --repo acme/widgets --no-seal 2>/dev/null)"
fresh; bt_board complete-board; rm -f "$GH_BOARD_DIR/prview-12.out"; echo 'gh: Server Error (HTTP 502)' > "$GH_BOARD_DIR/prview-12.err"; echo 1 > "$GH_BOARD_DIR/prview-12.rc"
eq "a body that can't be read: board-unreadable" "board-unreadable 12 none" "$(bash "$BR" --session "$S" --pr 12 --repo acme/widgets --no-seal 2>/dev/null)"

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

echo
echo "board-record: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
