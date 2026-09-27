#!/usr/bin/env bash
# land-check_test.sh -- land-check.sh prints permit, deny, confirm, dirty and
# moved for their fixtures, judging the live head against the unit's own
# verify capture, and narrowing the start's posture with a fresh read.
#
# Covers: each token; a head that moved before or during the re-read; the
# posture's narrowing both ways (a start deny isn't widened by a permit now,
# a start permit is narrowed by a deny now); an unread posture that becomes
# permit only when posture_ask's latest evidence reads merge: permitted and a
# Reversals row from the human about the posture, dated at or after it, is on
# GitHub (Reversals prose alone never widens it); a missing,
# unverified or wrongly sealed verify capture (exit 2); a failed posture
# re-read; the repository found from the record's Holdings row.
#
# Runs offline on the gh-board and koto stand-ins in a localized plugin tree.
# Usage: bash skills/coordinate/scripts/land-check_test.sh
set -uo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
command -v jq >/dev/null 2>&1 || { echo "SKIP: jq not on PATH"; exit 0; }
T=$(mktemp -d "${TMPDIR:-/tmp}/land-check-test.XXXXXX")
trap 'rm -rf "$T"' EXIT
. "$HERE/testdata/board/helpers.sh"
bt_setup
LC="$PS/land-check.sh"
CL="$PS/coord-log.sh"
PERMIT="readable merge=permit close=permit teardown=permit"
N=0

# scenario <start-posture> <posture-now> [prview-state]: a fresh run at land.
scenario() {
    N=$((N + 1))
    S="coordinate-demo-20260926T10000${N}Z"
    bt_run "$S" "$1"
    bt_verified "$S" 12 "$H"
    bt_enter "$S" land
    printf '%s\n' "$2" > "$BT_STATE/posture"
    rm -f "$BT_STATE/posture.rc"
    bt_board complete-board
    printf '{"mergeStateStatus":"%s"}\n' "${3:-CLEAN}" > "$GH_BOARD_DIR/prview-12.out"
    bt_record_body '[]'
}
token() { bash "$LC" --session "$S" --repo acme/widgets "$@" 2>"$T/err" | sed 's/ sealed:.*//'; }

echo "== the five tokens =="
scenario "$PERMIT" "$PERMIT"
OUT=$(bash "$LC" --session "$S" --repo acme/widgets 2>"$T/err")
eq "a permitted merge at the verified head is permit" "permit 12 $H" "${OUT% sealed:*}"
bash "$CL" check --session "$S" --state land --sealed "$OUT" && ok "the token is sealed to the latest entry into land" || bad "the token is sealed to the latest entry into land"
scenario "$PERMIT" "readable merge=deny close=permit teardown=permit"
eq "a denied merge is deny" "deny 12 $H" "$(token)"
scenario "$PERMIT" "readable merge=confirm close=permit teardown=permit"
eq "a merge behind a person's confirmation is confirm" "confirm 12 $H" "$(token)"
scenario "readable merge:permit close:permit teardown:permit" "readable merge:deny close:permit teardown:permit"
eq "a posture token with : between step and value reads the same" "deny 12 $H" "$(token)"
scenario "$PERMIT" "$PERMIT" DIRTY
eq "a DIRTY merge state is dirty" "dirty 12" "$(token)"
scenario "$PERMIT" "$PERMIT"
jq -c --arg m "$MOVED" '.data.repository.pullRequest.headRefOid = $m | .data.repository.pullRequest.commits.nodes[0].commit.oid = $m' "$GH_BOARD_DIR/snapshot.out" > "$T/s" && mv "$T/s" "$GH_BOARD_DIR/snapshot.out"
jq -c --arg m "$MOVED" '.object.sha = $m' "$GH_BOARD_DIR/ref.out" > "$T/r" && mv "$T/r" "$GH_BOARD_DIR/ref.out"
eq "a head pushed since verify is moved" "moved 12 $H $MOVED" "$(token)"
scenario "$PERMIT" "$PERMIT"
jq -c --arg m "$MOVED" '.object.sha = $m' "$GH_BOARD_DIR/ref.out" > "$T/r" && mv "$T/r" "$GH_BOARD_DIR/ref.out"
eq "a push landing during the re-read is moved" "moved 12 $H $MOVED" "$(token)"
grep -q 'pr view' "$GH_BOARD_DIR/calls" && bad "a moved head reads nothing after the head" || ok "a moved head reads nothing after the head"

echo "== the posture only narrows =="
scenario "readable merge=deny close=permit teardown=permit" "$PERMIT"
eq "a start deny isn't widened by a permit now" "deny 12 $H" "$(token)"
scenario "readable merge=confirm close=permit teardown=permit" "unread merge=unread close=permit teardown=permit"
eq "a start confirm stays confirm when the re-read is unread" "confirm 12 $H" "$(token)"
scenario "$PERMIT" "unread merge=unread close=unread teardown=unread"
eq "a start permit with an unreadable posture now is confirm" "confirm 12 $H" "$(token)"

echo "== an unread posture and the human's answer =="
# The answer is posture_ask's evidence (merge: permitted), never Reversals prose;
# the row on GitHub is the proof it was recorded, dated at or after it.
UNREAD="unread merge=unread close=unread teardown=unread"
ASKED=2026-09-26T12:20:07.000Z
HUMAN='{"date":"2026-09-26T12:30Z","reversed":"posture unreadable","now":"the coordinator holds merge","reason":"asked once at start","from":"the human"}'
answer() { # answer <merge> [timestamp]: posture_ask's evidence
    bt_evidence "$S" posture_ask "$(jq -nc --arg m "$1" '{merge: $m, close: "reserved", teardown: "reserved"}')" "${2:-$ASKED}"
}
row() { printf '%s' "$HUMAN" | jq -c "$1"; }
scenario "$UNREAD" "$UNREAD"; answer permitted
bt_record_body "[$HUMAN]"
eq "a permitted answer with the human's row on GitHub makes an unread merge permit" "permit 12 $H" "$(token)"
grep -q 'issues/7' "$GH_BOARD_DIR/calls" && ok "the row is read from the live record" || bad "the row is read from the live record" "$(cat "$GH_BOARD_DIR/calls")"
scenario "$UNREAD" "$UNREAD"; answer permitted
bt_record_body "[$(row '.date = "2026-09-26T12:20Z"')]"
eq "a row dated in the answer's minute counts" "permit 12 $H" "$(token)"
scenario "$UNREAD" "$UNREAD"; answer permitted
eq "a permitted answer without the row on GitHub is confirm" "confirm 12 $H" "$(token)"
scenario "$UNREAD" "$UNREAD"; answer permitted
bt_record_body "[$(row '.date = "2026-09-26T12:19Z"')]"
eq "a row dated before the answer doesn't count" "confirm 12 $H" "$(token)"
scenario "$UNREAD" "$UNREAD"; answer permitted
bt_record_body "[$(row '.from = "coordinator"')]"
eq "a row not from the human doesn't count" "confirm 12 $H" "$(token)"
scenario "$UNREAD" "$UNREAD"; answer permitted
bt_record_body "[$(row '.reversed = "merge step" | .now = "the coordinator holds merge"')]"
eq "a row that doesn't mention the posture doesn't count" "confirm 12 $H" "$(token)"
scenario "$UNREAD" "$UNREAD"; answer reserved
bt_record_body "[$HUMAN]"
eq "a reserved answer is confirm, whatever the row says" "confirm 12 $H" "$(token)"
scenario "$UNREAD" "$UNREAD"; answer permitted 2026-09-26T12:10:00.000Z; answer reserved
bt_record_body "[$HUMAN]"
eq "the latest answer is the one that counts" "confirm 12 $H" "$(token)"
scenario "$UNREAD" "$UNREAD"
bt_record_body "[$HUMAN]"
eq "a row with no answer in the log is confirm" "confirm 12 $H" "$(token)"
for NOWTEXT in "merge reserved; close held; teardown held" "the human holds the merge" \
    "the human holds merges, the coordinator holds close and teardown"; do
    scenario "$UNREAD" "$UNREAD"
    bt_record_body "[$(printf '%s' "$HUMAN" | jq -c --arg n "$NOWTEXT" '.now = $n')]"
    eq "no answer in the log, row [$NOWTEXT]: confirm" "confirm 12 $H" "$(token)"
done
scenario "$UNREAD" "unread merge=deny close=unread teardown=unread"; answer permitted
bt_record_body "[$HUMAN]"
eq "a deny now beats the human's earlier answer" "deny 12 $H" "$(token)"
scenario "$PERMIT" "$UNREAD"; answer permitted
bt_record_body "[$HUMAN]"
eq "the answer counts only when the start read was unread" "confirm 12 $H" "$(token)"
scenario "$UNREAD" "$UNREAD"; answer permitted
bt_record_body "[$HUMAN]"
echo 1 > "$GH_BOARD_DIR/issue-7.rc"
eq "a failed record read is confirm" "confirm 12 $H" "$(token)"

echo "== the verify capture =="
N=$((N + 1)); S="coordinate-demo-20260926T10010${N}Z"
bt_run "$S" "$PERMIT"; bt_enter "$S" land
bash "$LC" --session "$S" --repo acme/widgets >/dev/null 2>&1; eq "no verify capture: exit 2" 2 $?
N=$((N + 1)); S="coordinate-demo-20260926T10010${N}Z"
bt_run "$S" "$PERMIT"; bt_enter "$S" verify_board; bt_sealed "$S" verify_board VERIFIED "unverified 12 none"; bt_enter "$S" land
bash "$LC" --session "$S" --repo acme/widgets >/dev/null 2>&1; eq "an unverified capture: exit 2" 2 $?
N=$((N + 1)); S="coordinate-demo-20260926T10010${N}Z"
bt_run "$S" "$PERMIT"; bt_enter "$S" verify_board; bt_sealed "$S" verify "VERIFIED" "verified 12 $H"; bt_enter "$S" land
bash "$LC" --session "$S" --repo acme/widgets >/dev/null 2>&1; eq "a capture sealed at another state: exit 2" 2 $?
N=$((N + 1)); S="coordinate-demo-20260926T10010${N}Z"
bt_run "$S" "$PERMIT"; bt_enter "$S" verify_board; bt_capture "$S" VERIFIED "verified 12 $H"; bt_enter "$S" land
bash "$LC" --session "$S" --repo acme/widgets >/dev/null 2>&1; eq "an unsealed capture: exit 2" 2 $?
scenario "$PERMIT" "$PERMIT"
bt_enter "$S" verify_board
bt_sealed "$S" verify_board VERIFIED "verified 13 $MOVED"
bt_enter "$S" land
eq "--pr picks the unit's own capture from an earlier visit" "permit 12 $H" "$(token --pr 12)"

echo "== reads and repository =="
scenario "$PERMIT" "$PERMIT"
echo 1 > "$BT_STATE/posture.rc"
bash "$LC" --session "$S" --repo acme/widgets >/dev/null 2>&1; eq "a failed posture re-read: exit 2" 2 $?
scenario "$PERMIT" "$PERMIT"
echo 1 > "$GH_BOARD_DIR/ref.rc"
bash "$LC" --session "$S" --repo acme/widgets >/dev/null 2>&1; eq "a failed head re-read: exit 2" 2 $?
scenario "$PERMIT" "$PERMIT"
bt_holdings "[#12](https://github.com/acme/widgets/pull/12)" "[#9](https://github.com/acme/gadgets/pull/9)"
eq "the repository comes from the Holdings row linking the pull request" "permit 12 $H" "$(bash "$LC" --session "$S" --no-seal 2>"$T/err")"
bt_holdings "[#12](https://github.com/acme/widgets/pull/12)" "[#12](https://github.com/acme/gadgets/pull/12)"
bash "$LC" --session "$S" --no-seal >/dev/null 2>&1; eq "two holdings linking #12 in two repositories: exit 2" 2 $?
bash "$LC" --session "$S" --bogus >/dev/null 2>&1; eq "usage: exit 64" 64 $?
bash "$LC" >/dev/null 2>&1; eq "no session: exit 64" 64 $?

echo
echo "land-check: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
