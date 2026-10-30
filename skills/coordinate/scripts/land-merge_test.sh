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
# the record stands on the pull request now, when a pause holds its unit (exit
# 12), or when its title and Part 1 don't build a message; and it must be
# called with the repository, the pull request and the verified sha
# otherwise. The record, its holds and its pauses, is re-read from the run's
# session, never from GitHub. --closeout is a usage error: there is no record
# pull request to merge. merge-exec's own refusal and failure pass through as
# exit 11. The script never names `gh pr merge`, and a MERGE_EXEC in the
# environment never replaces merge-exec.sh. A merge sends one `landed` event,
# whose arguments a stand-in for scripts/emit-event.sh in the localized tree
# records: the topic and request only from the holdings the repository lookup
# read; a refused merge sends none; and a helper that exits non-zero or is
# missing leaves the exit code, stdout and stderr as they were.
#
# Runs offline on the gh-board and koto stand-ins in a localized plugin tree.
# Usage: bash skills/coordinate/scripts/land-merge_test.sh
set -uo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
command -v jq >/dev/null 2>&1 || { echo "SKIP: jq not on PATH"; exit 0; }
T=$(mktemp -d "${TMPDIR:-/tmp}/land-merge-test.XXXXXX") || exit 1
trap 'rm -rf "$T"' EXIT
. "$HERE/testdata/board/helpers.sh"
bt_setup
BT_PRVIEW_BODY=$(bt_body)
LM="$PS/land-merge.sh"
PERMIT="readable merge:permit close:permit teardown:permit release:permit"
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
at_land; printf '%s\n' "readable merge:deny close:permit teardown:permit release:permit" > "$BT_STATE/posture"
never "the posture re-read denies" 10
at_land; printf '%s\n' "readable merge:confirm close:permit teardown:permit release:permit" > "$BT_STATE/posture"
never "the posture re-read asks for a person's confirmation" 10
at_land; echo 2 > "$BT_STATE/posture.rc"
never "the posture re-read fails" 10
at_land "readable merge:deny close:permit teardown:permit release:permit"
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
at_land; rm -f "$KOTO_BOARD_DIR/sessions/$S/ctx/record__meta"
never "a session that holds no record can't be re-read for its holds" 10

echo "== a pause written after the land check =="
at_land; bt_record_paused "[$(bt_pause s1 pause all lifted)]"
never "a pause on all stops the merge with its own code" 12
grep -q 'paused: pause s1 holds #12 now (on all, until lifted); submit merge: paused' "$T/err" && ok "  ... naming the pause and the value to submit" || bad "  ... naming the pause and the value to submit" "$(cat "$T/err")"
at_land; bt_record_paused "[$(bt_pause s2 pause "Feature 2" "time 2099-01-01T00:00Z")]"
never "a pause on the pull request's unit stops it too" 12
at_land; bt_record_paused "[$(bt_pause s2 pause "Feature 3" lifted)]"
bash "$LM" --session "$S" --repo acme/widgets >/dev/null 2>&1; eq "a pause on another unit doesn't" 0 $?
at_land; bt_record_paused "[$(bt_pause s1 pause all lifted), $(bt_pause s3 go-ahead "Feature 2" "")]"
bash "$LM" --session "$S" --repo acme/widgets >/dev/null 2>&1; eq "nor does an all pause the unit has a go-ahead through" 0 $?
at_land; bt_record_paused "[$(bt_pause s1 pause all "time 2000-01-01T00:00Z")]"
bash "$LM" --session "$S" --repo acme/widgets >/dev/null 2>&1; eq "nor a pause whose minute has passed" 0 $?

echo "== the record is the session's =="
# The hold and the pause are re-read from the run's session keys; GitHub
# serves no record.
at_land; bt_record_body '[]' "[$HOLD_GO]"; : > "$GH_BOARD_DIR/calls"
never "a hold in the session stops the merge" 10
at_land; bt_record_paused "[$(bt_pause s1 pause all lifted)]"; : > "$GH_BOARD_DIR/calls"
never "a pause in the session stops it with its own code" 12
grep -q 'issues/' "$GH_BOARD_DIR/calls" && bad "  ... and no record is read on GitHub" "$(cat "$GH_BOARD_DIR/calls")" || ok "  ... and no record is read on GitHub"

echo "== merge-exec's own answers =="
at_land; printf 'merge-refused:unmergeable:blocked\n' > "$BT_STATE/merge-exec.out"; echo 0 > "$BT_STATE/merge-exec.rc"
OUT=$(bash "$LM" --session "$S" --repo acme/widgets 2>/dev/null); rc=$?
eq "a merge-exec refusal is exit 11" 11 $rc
eq "and its line is printed" "merge-refused:unmergeable:blocked" "$OUT"
at_land; : > "$BT_STATE/merge-exec.out"; echo 2 > "$BT_STATE/merge-exec.rc"
bash "$LM" --session "$S" --repo acme/widgets >/dev/null 2>&1; eq "a merge-exec failure is exit 11" 11 $?

echo "== --closeout is gone =="
at_land
never "--closeout is a usage error" 64 --closeout

echo "== usage and the merge call =="
bash "$LM" --session "$S" --bogus >/dev/null 2>&1; eq "usage: exit 64" 64 $?
bash "$LM" >/dev/null 2>&1; eq "no session: exit 64" 64 $?
lm_code=$(grep -v '^ *#' "$HERE/land-merge.sh")
if grep -q 'gh pr merge' <<<"$lm_code"; then bad "land-merge.sh never calls gh pr merge itself"; else ok "land-merge.sh never calls gh pr merge itself"; fi
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
lm_code=$(grep -v '^ *#' "$HERE/land-merge.sh")
if grep -q 'MERGE_EXEC' <<<"$lm_code"; then bad "land-merge.sh reads no MERGE_EXEC"; else ok "land-merge.sh reads no MERGE_EXEC"; fi

echo "== the landed event =="
# A stand-in for scripts/emit-event.sh in the localized tree: each call's
# arguments, one per line and then `--`, appended to emit.calls; it prints on
# both streams and exits with emit.rc (0 without it), which the merge must
# ignore.
EMIT_CALLS="$BT_STATE/emit.calls"
cat > "$T/plugin/scripts/emit-event.sh" <<'EOF'
#!/usr/bin/env bash
{ printf '%s\n' "$@"; echo --; } >> "$BT_STATE/emit.calls"
echo "emit-event stand-in: stdout"
echo "emit-event stand-in: stderr" >&2
exit "$(cat "$BT_STATE/emit.rc" 2>/dev/null || echo 0)"
EOF
emits() { cat "$EMIT_CALLS" 2>/dev/null; }
at_emit() { at_land "$@"; rm -f "$EMIT_CALLS" "$BT_STATE/emit.rc" "$BT_STATE/holding.calls"; echo '[]' > "$BT_STATE/holdings"; }
at_emit
bash "$LM" --session "$S" --repo acme/widgets >/dev/null 2>&1; eq "a merge with --repo: exit 0" 0 $?
eq "  ... one landed event: the pull request, the scope slug and this session (no holdings read, so no topic or request)" \
    "$(printf '%s\n' event --scope unit-cost --kind landed unit.pr=github.com/acme/widgets#12 unit.scope_slug=demo "unit.koto_session=$S" --)" \
    "$(emits)"
at_emit
printf '%s\n' '[{"worker":"w12","pull_request":"[#12](https://github.com/acme/widgets/pull/12)","repo":"acme/widgets","return_path":"leg req_7:deliver"},
  {"worker":"w13","pull_request":"[#13](https://github.com/acme/widgets/pull/13)","repo":"acme/widgets","return_path":"leg req_8:deliver"}]' > "$BT_STATE/holdings"
OUT=$(bash "$LM" --session "$S" 2>"$T/err"); rc=$?
eq "a merge whose repository the record gives: exit 0" "0 merge-called:squash:$H" "$rc $OUT"
eq "  ... the landed event adds the holding's topic and its leg's request, from the same read" \
    "$(printf '%s\n' event --scope unit-cost --kind landed unit.pr=github.com/acme/widgets#12 unit.topic=w12 \
        unit.scope_slug=demo "unit.koto_session=$S" unit.request=req_7 --)" \
    "$(emits)"
eq "  ... the holdings were read once" 1 "$(grep -c -- '--list' "$BT_STATE/holding.calls" 2>/dev/null)"
at_emit
printf '%s\n' '[{"worker":"w12","pull_request":"[#12](https://github.com/acme/widgets/pull/12)","repo":"acme/widgets","return_path":"message"}]' > "$BT_STATE/holdings"
bash "$LM" --session "$S" >/dev/null 2>&1
eq "a holding on the message path: the topic, no request" \
    "$(printf '%s\n' event --scope unit-cost --kind landed unit.pr=github.com/acme/widgets#12 unit.topic=w12 \
        unit.scope_slug=demo "unit.koto_session=$S" --)" \
    "$(emits)"
at_emit; printf '%s\n' "readable merge:deny close:permit teardown:permit release:permit" > "$BT_STATE/posture"
never "a refused merge" 10
eq "  ... sends nothing" "" "$(emits)"
at_emit; printf 'merge-refused:unmergeable:blocked\n' > "$BT_STATE/merge-exec.out"; echo 0 > "$BT_STATE/merge-exec.rc"
bash "$LM" --session "$S" --repo acme/widgets >/dev/null 2>&1; eq "a merge-exec refusal: exit 11" 11 $?
eq "  ... sends nothing" "" "$(emits)"
# A helper that exits non-zero, and one that is missing, leave the merge's
# exit code, stdout and stderr as a helper that works leaves them.
at_emit
OUT=$(bash "$LM" --session "$S" --repo acme/widgets 2>"$T/err"); rc=$?
WANT="$rc|$OUT|$(cat "$T/err")"
at_emit; echo 3 > "$BT_STATE/emit.rc"
OUT=$(bash "$LM" --session "$S" --repo acme/widgets 2>"$T/err"); rc=$?
eq "a helper that exits 3: the same exit, output and stderr" "$WANT" "$rc|$OUT|$(cat "$T/err")"
eq "  ... and it was called" 1 "$(grep -c '^landed$' "$EMIT_CALLS" 2>/dev/null)"
at_emit; mv "$T/plugin/scripts/emit-event.sh" "$T/emit-event.aside"
OUT=$(bash "$LM" --session "$S" --repo acme/widgets 2>"$T/err"); rc=$?
mv "$T/emit-event.aside" "$T/plugin/scripts/emit-event.sh"
eq "a missing helper: the same exit, output and stderr" "$WANT" "$rc|$OUT|$(cat "$T/err")"

echo
echo "land-merge: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
