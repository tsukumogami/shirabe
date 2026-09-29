#!/usr/bin/env bash
# merged-facts_test.sh -- merged-facts.sh finds a holding by its topic on
# GitHub, takes the head from the unit's own verify capture, and reports
# whether a person's merge landed it.
#
# Covers: merged, unconfirmed (a blob differs) and not-merged; the unit's
# capture from an earlier verify visit, found by its pull request among
# later ones; the unit from the latest wait evidence when --unit is absent
# (none, a malformed one, a title such as "Feature 16: example", one naming no
# holding or a holding without a pull request are each refused as
# unknown-topic, naming the field and the accepted topics); no verify capture
# for the pull request in this run, and an unverified capture, each exit 2; the token sealed to merged_facts; the topic as a locator only.
#
# Runs offline on the gh-board and koto stand-ins in a localized plugin tree.
# Usage: bash skills/coordinate/scripts/merged-facts_test.sh
set -uo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
command -v jq >/dev/null 2>&1 || { echo "SKIP: jq not on PATH"; exit 0; }
T=$(mktemp -d "${TMPDIR:-/tmp}/merged-facts-test.XXXXXX")
trap 'rm -rf "$T"' EXIT
. "$HERE/testdata/board/helpers.sh"
bt_setup
MF="$PS/merged-facts.sh"
CL="$PS/coord-log.sh"
PERMIT="readable merge:permit close:permit teardown:permit"
B1=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
B2=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
N=0
at_facts() { # #12 verified for plugin-registry, #13 verified later for sandbox; now at merged_facts
    N=$((N + 1))
    S="coordinate-demo-20260926T1400$(printf '%02d' "$N")Z"
    bt_run "$S" "$PERMIT"
    bt_verified "$S" 12 "$H"
    bt_enter "$S" verify; bt_evidence "$S" verify '{"prediction":"green"}'
    bt_verified "$S" 13 "$MOVED"
    bt_enter "$S" wait; bt_evidence "$S" wait '{"event":"merged","unit":"plugin-registry"}'
    bt_enter "$S" merged_facts
    jq -nc '[{worker: "plugin-registry", repo: "acme/widgets", pull_request: "[#12](https://github.com/acme/widgets/pull/12)"},
             {worker: "sandbox", repo: "acme/widgets", pull_request: "[#13](https://github.com/acme/widgets/pull/13)"},
             {worker: "unopened", repo: "acme/widgets", pull_request: ""}]' > "$BT_STATE/holdings"
    rm -rf "$GH_BOARD_DIR"; mkdir -p "$GH_BOARD_DIR"
    bt_merged MERGED '["src/main.go"]'
    bt_blob main src/main.go "$B1"; bt_blob "$H" src/main.go "$B1"
}
token() { bash "$MF" --session "$S" --unit "${1:-plugin-registry}" 2>"$T/err" | sed 's/ sealed:.*//'; }

echo "== merged, unconfirmed, not merged =="
at_facts
OUT=$(bash "$MF" --session "$S" --unit plugin-registry 2>"$T/err")
eq "a person's merge of the verified head: merged" "merged 12 $H" "${OUT% sealed:*}"
bash "$CL" check --session "$S" --state merged_facts --sealed "$OUT" && ok "sealed to the latest entry into merged_facts" || bad "sealed to the latest entry into merged_facts"
grep -q "contents/src/main.go?ref=$H" "$GH_BOARD_DIR/calls" && ok "the head is the unit's own verify capture, from an earlier visit" || bad "the head is the unit's own verify capture" "$(cat "$GH_BOARD_DIR/calls")"
grep -q -- '--topic plugin-registry --read' "$BT_STATE/holding.calls" && ok "the holding is found by topic on GitHub" || bad "the holding is found by topic on GitHub"
at_facts; bt_blob main src/main.go "$B2"
eq "a merge that doesn't hold the verified content: unconfirmed" "unconfirmed 12 $H" "$(token)"
at_facts; bt_merged OPEN '["src/main.go"]'
eq "still open: not-merged" "not-merged 12" "$(token)"
at_facts; bt_merged CLOSED '["src/main.go"]'
eq "closed without merging: not-merged" "not-merged 12" "$(token)"

echo "== the unit from the merged event =="
at_facts
OUT=$(bash "$MF" --session "$S" 2>"$T/err")
eq "without --unit, the latest wait evidence names the unit" "merged 12 $H" "${OUT% sealed:*}"
bt_evidence "$S" wait '{"event":"merged","unit":"sandbox"}'
bash "$MF" --session "$S" --no-seal >/dev/null 2>&1
eq "the latest wait evidence wins" "--session $S --topic sandbox --read" "$(tail -1 "$BT_STATE/holding.calls")"
echo "== a unit that names no holding is refused, back to the hub =="
# refused <label> <wait-evidence>: the event is refused as unknown-topic,
# sealed to merged_facts, naming the field, the value and the accepted topics,
# with no read past the holdings.
refused() {
    at_facts; bt_evidence "$S" wait "$2"
    : > "$GH_BOARD_DIR/calls"
    OUT=$(bash "$MF" --session "$S" 2>"$T/err"); rc=$?
    eq "$1: refused as unknown-topic, exit 0" "0 unknown-topic" "$rc ${OUT% sealed:*}"
    bash "$CL" check --session "$S" --state merged_facts --sealed "$OUT" && ok "$1: sealed to merged_facts" || bad "$1: sealed to merged_facts"
    D="$KOTO_BOARD_DIR/sessions/$S/ctx/coord__merged_facts.json"
    jq -e '.field == "unit" and .accepted == ["plugin-registry", "sandbox"] and (.reason | test("plugin-registry, sandbox$"))' "$D" >/dev/null \
        && ok "$1: the reason names the field and the accepted topics" || bad "$1: the reason names the field and the accepted topics" "$(cat "$D" 2>/dev/null)"
    grep -q 'unit takes the dispatch topic of a holding' "$T/err" && ok "$1: and says so on stderr" || bad "$1: and says so on stderr" "$(cat "$T/err")"
    [ -s "$GH_BOARD_DIR/calls" ] && bad "$1: nothing on GitHub is read" "$(cat "$GH_BOARD_DIR/calls")" || ok "$1: nothing on GitHub is read"
}
refused "a unit's title in place of its topic (shirabe#547)" '{"event":"merged","unit":"Feature 16: example"}'
refused "a merged event without a unit" '{"event":"merged"}'
refused "a unit outside the topic pattern" '{"event":"merged","unit":"../x"}'
refused "a topic no holding names" '{"event":"merged","unit":"nobody"}'
refused "a holding with no pull request" '{"event":"merged","unit":"unopened"}'
at_facts; bt_evidence "$S" wait '{"event":"merged","unit":"Feature 16"}'; echo 2 > "$BT_STATE/holding.rc"
bash "$MF" --session "$S" >/dev/null 2>&1; eq "holdings that can't be listed for the refusal: exit 2, retried rather than refused" 2 $?
rm -f "$BT_STATE/holding.rc"
at_facts; bt_evidence "$S" report_facts '{"unit":"sandbox"}'
eq "evidence in another state isn't the event" "merged 12 $H" "$(bash "$MF" --session "$S" --no-seal 2>/dev/null)"

echo "== failures exit 2 =="
at_facts
eq "--unit naming no holding is refused too" "unknown-topic" "$(bash "$MF" --session "$S" --unit nobody --no-seal 2>/dev/null)"
jq -c '. + [{worker: "later", repo: "acme/widgets", pull_request: "[#14](https://github.com/acme/widgets/pull/14)"}]' "$BT_STATE/holdings" > "$T/h" && mv "$T/h" "$BT_STATE/holdings"
bash "$MF" --session "$S" --unit later >/dev/null 2>&1; eq "no verify capture for its pull request in this run" 2 $?
at_facts; bt_enter "$S" verify_board; bt_sealed "$S" verify_board VERIFIED "unverified 12 none"
bash "$MF" --session "$S" --unit plugin-registry >/dev/null 2>&1; eq "the latest capture for its pull request is unverified" 2 $?
at_facts; echo 2 > "$BT_STATE/holding.rc"
bash "$MF" --session "$S" --unit plugin-registry >/dev/null 2>&1; eq "a failed holding read" 2 $?
rm -f "$BT_STATE/holding.rc"
at_facts; bt_blob main src/main.go fail
bash "$MF" --session "$S" --unit plugin-registry >/dev/null 2>&1; eq "a failed blob read" 2 $?

echo "== overrides and usage =="
at_facts
eq "--pr --repo skip the holding read" "merged 12 $H" "$(bash "$MF" --session "$S" --unit x --pr 12 --repo acme/widgets --no-seal 2>/dev/null)"
bash "$MF" --session "$S" --unit 'a b' >/dev/null 2>&1; eq "a malformed topic: exit 64" 64 $?
bash "$MF" --session "$S" --unit x --pr 12 >/dev/null 2>&1; eq "--pr without --repo: exit 64" 64 $?
bash "$MF" --unit x >/dev/null 2>&1; eq "no --session: exit 64" 64 $?

echo
echo "merged-facts: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
