#!/usr/bin/env bash
# land-merge_test.sh -- land-merge.sh calls merge-exec.sh with the verified
# sha only when every check before it holds, and never otherwise.
#
# A stand-in merge-exec.sh (MERGE_EXEC) logs its arguments. It must never be
# called when the posture re-read denies or asks for confirmation, when
# land's capture is stale (land entered again since it was sealed), absent,
# not permit, or unsealed, when provenance fails (another plugin root, an
# edited template), or when the run has a directed transition; and it must be
# called with the repository, the pull request and the verified sha
# otherwise. --closeout does the same for a rotation's or a predecessor's
# record pull request from its close-out capture. merge-exec's own refusal
# and failure pass through as exit 11. The script never names `gh pr merge`.
#
# Runs offline on the gh-board and koto stand-ins in a localized plugin tree.
# Usage: bash skills/coordinate/scripts/land-merge_test.sh
set -uo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
command -v jq >/dev/null 2>&1 || { echo "SKIP: jq not on PATH"; exit 0; }
T=$(mktemp -d "${TMPDIR:-/tmp}/land-merge-test.XXXXXX")
trap 'rm -rf "$T"' EXIT
. "$HERE/testdata/board/helpers.sh"
bt_setup
LM="$PS/land-merge.sh"
export MERGE_EXEC="$TD/board/stand-in-merge-exec.sh"
PERMIT="readable merge=permit close=permit teardown=permit"
CALLS="$BT_STATE/merge-exec.calls"
N=0

# at_land [start-posture]: a fresh run whose land check sealed permit 12 H,
# now at land_merge.
at_land() {
    N=$((N + 1))
    S="coordinate-demo-20260926T1100$(printf '%02d' "$N")Z"
    bt_run "$S" "${1:-$PERMIT}"
    bt_verified "$S" 12 "$H"
    bt_enter "$S" land
    bt_sealed "$S" land LAND "permit 12 $H"
    bt_enter "$S" land_merge
    printf '%s\n' "$PERMIT" > "$BT_STATE/posture"
    rm -f "$CALLS" "$BT_STATE/merge-exec.out" "$BT_STATE/merge-exec.rc" "$BT_STATE/posture.rc"
    bt_board complete-board
    bt_record_body '[]'
}
never() { # never <label> <want-rc> [args...]
    local label=$1 want=$2; shift 2
    bash "$LM" --session "$S" --repo acme/widgets "$@" > "$T/out" 2> "$T/err"
    local rc=$?
    if [ "$rc" = "$want" ] && [ ! -s "$CALLS" ]; then ok "$label"
    else bad "$label" "rc=$rc calls=$(cat "$CALLS" 2>/dev/null) err=$(cat "$T/err")"; fi
}

echo "== merges the verified head =="
at_land
OUT=$(bash "$LM" --session "$S" --repo acme/widgets 2>"$T/err"); rc=$?
eq "a permitted, fresh land capture merges: exit 0" 0 $rc
eq "merge-exec gets the repository, the pull request and the verified sha" "acme/widgets 12 $H" "$(cat "$CALLS")"
eq "merge-exec's line is printed" "merge-called:squash:$H" "$OUT"

echo "== never merges =="
at_land; printf '%s\n' "readable merge=deny close=permit teardown=permit" > "$BT_STATE/posture"
never "the posture re-read denies" 10
at_land; printf '%s\n' "readable merge=confirm close=permit teardown=permit" > "$BT_STATE/posture"
never "the posture re-read asks for a person's confirmation" 10
at_land; echo 2 > "$BT_STATE/posture.rc"
never "the posture re-read fails" 10
at_land "readable merge=deny close=permit teardown=permit"
never "the start's posture denied, whatever the re-read says" 10
at_land; bt_enter "$S" land
never "land's capture is stale (land entered again since)" 10
at_land; bt_enter "$S" land; bt_sealed "$S" land LAND "deny 12 $H"; bt_enter "$S" surface
never "land's capture is deny" 10
at_land; bt_enter "$S" land; bt_capture "$S" LAND "permit 12 $H"
never "land's capture is unsealed" 10
at_land; bt_enter "$S" land; bt_sealed "$S" land_merge LAND "permit 12 $H"
never "land's capture is sealed at another state" 10
at_land; bt_append "$S" directed_transition '{"from":"verify","to":"land"}'
never "the run has a directed transition" 10
at_land; jq -c '.template_hash = "0000"' "$(bt_logf "$S")" | head -1 > "$T/h"; { cat "$T/h"; tail -n +2 "$(bt_logf "$S")"; } > "$T/l"; mv "$T/l" "$(bt_logf "$S")"
never "provenance fails: the session came from another template" 10
N=$((N + 1)); S="coordinate-demo-20260926T1100$(printf '%02d' "$N")Z"
mkdir -p "$T/other"
bt_session "$S" "$T/other"; bt_enter "$S" start_posture; bt_sealed "$S" start_posture POSTURE "$PERMIT"
bt_enter "$S" land; bt_sealed "$S" land LAND "permit 12 $H"; bt_enter "$S" land_merge; rm -f "$CALLS"
never "provenance fails: PLUGIN_ROOT is another plugin" 10
at_land; S=coordinate-demo-nosuchsession
never "no session log" 10

echo "== merge-exec's own answers =="
at_land; printf 'merge-refused:unmergeable:blocked\n' > "$BT_STATE/merge-exec.out"; echo 0 > "$BT_STATE/merge-exec.rc"
OUT=$(bash "$LM" --session "$S" --repo acme/widgets 2>/dev/null); rc=$?
eq "a merge-exec refusal is exit 11" 11 $rc
eq "and its line is printed" "merge-refused:unmergeable:blocked" "$OUT"
at_land; : > "$BT_STATE/merge-exec.out"; echo 2 > "$BT_STATE/merge-exec.rc"
bash "$LM" --session "$S" --repo acme/widgets >/dev/null 2>&1; eq "a merge-exec failure is exit 11" 11 $?

echo "== --closeout =="
closeout() { # closeout <NAME> <state>
    N=$((N + 1))
    S="coordinate-demo-20260926T1100$(printf '%02d' "$N")Z"
    bt_run "$S" "$PERMIT"
    bt_enter "$S" "$2"
    bt_sealed "$S" "$2" "$1" "land 30 $H"
    bt_enter "$S" "${2%_close}_step"
    rm -f "$CALLS" "$BT_STATE/merge-exec.out" "$BT_STATE/merge-exec.rc" "$BT_STATE/posture.rc"
    printf '%s\n' "$PERMIT" > "$BT_STATE/posture"
}
closeout ROTATION_CLOSE rotation_close
bash "$LM" --session "$S" --closeout >/dev/null 2>"$T/err"; rc=$?
eq "a rotation's record pull request merges: exit 0" 0 $rc
eq "at the host, with the close-out's verified sha" "acme/widgets 30 $H" "$(cat "$CALLS" 2>/dev/null)"
closeout PREDECESSOR_CLOSE predecessor_close
bash "$LM" --session "$S" --closeout >/dev/null 2>&1; eq "a predecessor's record pull request merges: exit 0" 0 $?
closeout ROTATION_CLOSE rotation_close; bt_enter "$S" rotation_close
never "a stale close-out capture" 10 --closeout
closeout ROTATION_CLOSE rotation_close; printf '%s\n' "readable merge=deny close=permit teardown=permit" > "$BT_STATE/posture"
never "a close-out the posture denies" 10 --closeout
closeout ROTATION_CLOSE rotation_close; bt_append "$S" directed_transition '{"from":"rotation_step","to":"rotation_close"}'
never "a close-out in a run with a directed transition" 10 --closeout
at_land
never "--closeout doesn't take land's capture" 10 --closeout

echo "== usage and the merge call =="
bash "$LM" --session "$S" --bogus >/dev/null 2>&1; eq "usage: exit 64" 64 $?
bash "$LM" >/dev/null 2>&1; eq "no session: exit 64" 64 $?
if grep -v '^ *#' "$HERE/land-merge.sh" | grep -q 'gh pr merge'; then bad "land-merge.sh never calls gh pr merge itself"; else ok "land-merge.sh never calls gh pr merge itself"; fi
grep -q 'skills/execute/scripts/merge-exec.sh\|execute/scripts/merge-exec.sh' "$HERE/land-merge.sh" && ok "it calls the unchanged merge-exec.sh" || bad "it calls the unchanged merge-exec.sh"

echo
echo "land-merge: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
