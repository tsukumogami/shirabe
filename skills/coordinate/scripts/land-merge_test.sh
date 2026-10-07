#!/usr/bin/env bash
# land-merge_test.sh -- land-merge.sh calls merge-exec.sh with the verified
# sha only when every check before it holds, and never otherwise.
#
# A stand-in merge-exec.sh, at the localized plugin tree's
# skills/execute/scripts/merge-exec.sh, logs its arguments. It must never be
# called when the posture re-read denies or asks for confirmation, when
# land's capture is stale (land entered again since it was sealed), absent,
# not permit, or unsealed, when provenance fails (another plugin root, an
# edited template), when the run has a directed transition, when a hold in
# the record stands on the pull request now, or when its title and Part 1
# don't build a message; and it must be
# called with the repository, the pull request and the verified sha
# otherwise. --closeout does the same for a rotation's or a predecessor's
# record pull request from its close-out capture. merge-exec's own refusal
# and failure pass through as exit 11. The script never names `gh pr merge`,
# and a MERGE_EXEC in the environment never replaces merge-exec.sh.
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
BT_PRVIEW_BODY=$(bt_body)
LM="$PS/land-merge.sh"
PERMIT="readable merge:permit close:permit teardown:permit"
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
eq "and a message file built from the title and Part 1" \
    "$(printf 'feat(land): read the round\n\nReads the worker'"'"'s review round in the land step.')" \
    "$(cat "$BT_STATE/merge-exec.msg" 2>/dev/null)"
at_land; jq -c '.body = "\n\n---\n\nonly part two"' "$GH_BOARD_DIR/prview-12.out" > "$T/p" && mv "$T/p" "$GH_BOARD_DIR/prview-12.out"
never "an empty Part 1: no message, no merge" 10
at_land; rm -f "$GH_BOARD_DIR/prview-12.out"; echo 1 > "$GH_BOARD_DIR/prview-12.rc"; echo "gh: Server Error (HTTP 502)" > "$GH_BOARD_DIR/prview-12.err"
never "a body that can't be read: no merge" 10

echo "== never merges =="
at_land; printf '%s\n' "readable merge:deny close:permit teardown:permit" > "$BT_STATE/posture"
never "the posture re-read denies" 10
at_land; printf '%s\n' "readable merge:confirm close:permit teardown:permit" > "$BT_STATE/posture"
never "the posture re-read asks for a person's confirmation" 10
at_land; echo 2 > "$BT_STATE/posture.rc"
never "the posture re-read fails" 10
at_land "readable merge:deny close:permit teardown:permit"
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

echo "== a hold recorded after the land check =="
HOLD_GO='{"hold":"go","on":"acme/widgets#12","until":"lifted","set_by":"the human","set":"2026-09-26T11:30Z","lifted":""}'
at_land; bt_record_body '[]' "[$HOLD_GO]"
never "a standing hold on the pull request stops the merge" 10
grep -q 'a hold stands on #12 now: go (lifted, unmet)' "$T/err" && ok "  ... naming the hold" || bad "  ... naming the hold" "$(cat "$T/err")"
at_land; bt_record_body '[]' "[$(printf '%s' "$HOLD_GO" | jq -c '.lifted = "2026-09-26T11:40Z by the human"')]"
bash "$LM" --session "$S" --repo acme/widgets >/dev/null 2>&1; eq "a lifted hold doesn't" 0 $?
at_land; bt_record_body '[]' "[$(printf '%s' "$HOLD_GO" | jq -c '.on = "acme/widgets#13"')]"
bash "$LM" --session "$S" --repo acme/widgets >/dev/null 2>&1; eq "nor does one on another pull request" 0 $?
at_land; echo 1 > "$GH_BOARD_DIR/issue-7.rc"
never "a record that can't be re-read for its holds" 10

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
    # The record pull request: the renderer's fixed Part 1, then the record.
    jq -nc '{title: "docs(coordination): close the demo rotation",
             body: "The coordination record for the demo rotation.\n\n---\n\n> This is a **coordinator record**"}' \
        > "$GH_BOARD_DIR/prview-30.out"
}
closeout ROTATION_CLOSE rotation_close
bash "$LM" --session "$S" --closeout >/dev/null 2>"$T/err"; rc=$?
eq "a rotation's record pull request merges: exit 0" 0 $rc
eq "at the host, with the close-out's verified sha" "acme/widgets 30 $H" "$(cat "$CALLS" 2>/dev/null)"
eq "and the record pull request's title and fixed Part 1 as the message" \
    "$(printf 'docs(coordination): close the demo rotation\n\nThe coordination record for the demo rotation.')" \
    "$(cat "$BT_STATE/merge-exec.msg" 2>/dev/null)"
closeout PREDECESSOR_CLOSE predecessor_close
bash "$LM" --session "$S" --closeout >/dev/null 2>&1; eq "a predecessor's record pull request merges: exit 0" 0 $?
closeout ROTATION_CLOSE rotation_close; bt_enter "$S" rotation_close
never "a stale close-out capture" 10 --closeout
closeout ROTATION_CLOSE rotation_close; printf '%s\n' "readable merge:deny close:permit teardown:permit" > "$BT_STATE/posture"
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

echo "== the environment can't name another merge-exec.sh =="
at_land
cat > "$T/rogue-merge-exec.sh" <<'ROGUE'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$BT_STATE/rogue.calls"
echo "merge-called:squash:rogue"
ROGUE
rm -f "$BT_STATE/rogue.calls"
OUT=$(MERGE_EXEC="$T/rogue-merge-exec.sh" bash "$LM" --session "$S" --repo acme/widgets 2>"$T/err"); rc=$?
eq "with MERGE_EXEC exported, the merge still exits 0" 0 $rc
[ ! -e "$BT_STATE/rogue.calls" ] && ok "an exported MERGE_EXEC is never called" || bad "an exported MERGE_EXEC is never called" "$(cat "$BT_STATE/rogue.calls")"
eq "the sibling merge-exec.sh is called instead" "acme/widgets 12 $H" "$(cat "$CALLS" 2>/dev/null)"
eq "and its line is the one printed" "merge-called:squash:$H" "$OUT"
if grep -v '^ *#' "$HERE/land-merge.sh" | grep -q 'MERGE_EXEC'; then bad "land-merge.sh reads no MERGE_EXEC"; else ok "land-merge.sh reads no MERGE_EXEC"; fi

echo
echo "land-merge: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
