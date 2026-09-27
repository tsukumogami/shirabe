#!/usr/bin/env bash
# merge-confirm_test.sh -- merge-confirm.sh reads the pull request and the
# head from land's own capture and compares the default branch's blobs with
# the verified head's.
#
# Covers: merged (every changed file's blob matches, a file the pull request
# deleted is absent on both); unconfirmed when a blob differs, when the
# pull request isn't merged yet, or when a deleted file is still on the
# default branch; a failed blob read, and an absent, stale or non-permit land
# capture, exit 2; the token sealed to merge_confirm; --pr that disagrees
# with the capture.
#
# Runs offline on the gh-board and koto stand-ins in a localized plugin tree.
# Usage: bash skills/coordinate/scripts/merge-confirm_test.sh
set -uo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
command -v jq >/dev/null 2>&1 || { echo "SKIP: jq not on PATH"; exit 0; }
T=$(mktemp -d "${TMPDIR:-/tmp}/merge-confirm-test.XXXXXX")
trap 'rm -rf "$T"' EXIT
. "$HERE/testdata/board/helpers.sh"
bt_setup
MC="$PS/merge-confirm.sh"
CL="$PS/coord-log.sh"
PERMIT="readable merge=permit close=permit teardown=permit"
B1=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
B2=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
N=0
at_confirm() { # a run whose land sealed permit 12 H and whose merge was attempted
    N=$((N + 1))
    S="coordinate-demo-20260926T1300$(printf '%02d' "$N")Z"
    bt_run "$S" "$PERMIT"
    bt_verified "$S" 12 "$H"
    bt_enter "$S" land
    bt_sealed "$S" land LAND "permit 12 $H"
    bt_enter "$S" land_merge
    bt_evidence "$S" land_merge '{"outcome":"attempted"}'
    bt_enter "$S" merge_confirm
    rm -rf "$GH_BOARD_DIR"; mkdir -p "$GH_BOARD_DIR"
    bt_merged MERGED '["src/main.go", "docs/old.md"]'
    bt_blob main src/main.go "$B1"; bt_blob "$H" src/main.go "$B1"
    bt_blob main docs/old.md absent; bt_blob "$H" docs/old.md absent
}
token() { bash "$MC" --session "$S" --repo acme/widgets "$@" 2>"$T/err" | sed 's/ sealed:.*//'; }

echo "== merged and unconfirmed =="
at_confirm
OUT=$(bash "$MC" --session "$S" --repo acme/widgets 2>"$T/err")
eq "every blob matches and the deleted file is gone: merged" "merged 12 $H" "${OUT% sealed:*}"
bash "$CL" check --session "$S" --state merge_confirm --sealed "$OUT" && ok "sealed to the latest entry into merge_confirm" || bad "sealed to the latest entry into merge_confirm"
grep -q "contents/src/main.go?ref=$H" "$GH_BOARD_DIR/calls" && grep -q 'contents/src/main.go?ref=main' "$GH_BOARD_DIR/calls" \
    && ok "each file is read at the default branch and at the verified head" || bad "each file is read at the default branch and at the verified head" "$(cat "$GH_BOARD_DIR/calls")"
at_confirm; bt_blob main src/main.go "$B2"
eq "a blob on the default branch that differs: unconfirmed" "unconfirmed 12 $H" "$(token)"
at_confirm; bt_blob main docs/old.md "$B2"
eq "a deleted file still on the default branch: unconfirmed" "unconfirmed 12 $H" "$(token)"
at_confirm; bt_merged OPEN '["src/main.go"]'
eq "not merged yet: unconfirmed" "unconfirmed 12 $H" "$(token)"
grep -q contents "$GH_BOARD_DIR/calls" && bad "an unmerged pull request reads no blobs" || ok "an unmerged pull request reads no blobs"
at_confirm; bt_merged MERGED '["a b/c.txt"]'; bt_blob main "a%20b/c.txt" "$B1"; bt_blob "$H" "a%20b/c.txt" "$B1"
eq "a path with a space is encoded per segment" "merged 12 $H" "$(token)"

echo "== failures exit 2 =="
at_confirm; bt_blob "$H" src/main.go fail
bash "$MC" --session "$S" --repo acme/widgets >/dev/null 2>&1; eq "a failed blob read" 2 $?
at_confirm; echo 1 > "$GH_BOARD_DIR/prview-12.rc"
bash "$MC" --session "$S" --repo acme/widgets >/dev/null 2>&1; eq "a failed pull request read" 2 $?
at_confirm; bt_enter "$S" land
bash "$MC" --session "$S" --repo acme/widgets >/dev/null 2>&1; eq "a stale land capture" 2 $?
at_confirm; bt_enter "$S" land; bt_sealed "$S" land LAND "deny 12 $H"
bash "$MC" --session "$S" --repo acme/widgets >/dev/null 2>&1; eq "a land capture that isn't permit" 2 $?
N=$((N + 1)); S="coordinate-demo-20260926T1300$(printf '%02d' "$N")Z"; bt_run "$S" "$PERMIT"; bt_enter "$S" merge_confirm
bash "$MC" --session "$S" --repo acme/widgets >/dev/null 2>&1; eq "no land capture" 2 $?
at_confirm
bash "$MC" --session "$S" --repo acme/widgets --pr 13 >/dev/null 2>&1; eq "--pr that disagrees with land's capture" 2 $?
eq "--no-seal prints the bare token" "merged 12 $H" "$(bash "$MC" --session "$S" --repo acme/widgets --no-seal 2>/dev/null)"
bash "$MC" --bogus >/dev/null 2>&1; eq "usage: exit 64" 64 $?

echo
echo "merge-confirm: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
