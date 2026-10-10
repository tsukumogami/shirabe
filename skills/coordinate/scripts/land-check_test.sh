#!/usr/bin/env bash
# land-check_test.sh -- land-check.sh prints permit, deny, confirm, dirty,
# moved and unready for their fixtures, judging the live head against the
# unit's own verify capture, reading the worker's Review panel and the body,
# and narrowing the start's posture with a fresh read.
#
# The worker's round: no table (no-evidence), seats sharing a Run or a Seat,
# too few seats, a failing seat (each unready with its reason), and a ready
# one under deny with coord/land.json's message and files. The reviewed head:
# fresh one main merge-in behind; stale for a file main didn't touch, a
# non-merge commit, a second parent not on main, more than ten merge-ins, a
# comparison at the 300-file limit; a failed read (exit 2). The body: failing
# PR-body checks, and a Part 1 the message builder refuses.
#
# Covers: each token; a head that moved before or during the re-read; the
# posture's narrowing both ways (a start deny isn't widened by a permit now,
# a start permit is narrowed by a deny now); an unread posture that becomes
# permit only when posture_ask's latest evidence reads merge: permitted and a
# Reversals row from the human about the posture, dated at or after it, is on
# GitHub (Reversals prose alone never widens it); a missing,
# unverified or wrongly sealed verify capture (exit 2); a failed posture
# re-read; the repository found from the record's Holdings row. The
# milestone's Evidence for goal fit: on a roadmap/v2 roadmap read on the
# default branch, coord/land.json carries the holding's milestone tag and its
# numbered clauses (under permit and deny alike); a v1 roadmap and a pull
# request no holding names add nothing; a failed roadmap or default-branch
# read and a unit with no milestone leave the token as it was and say why in
# milestone_error.
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
PERMIT="readable merge:permit close:permit teardown:permit"
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
    bt_prview "${3:-CLEAN}"
    bt_record_body '[]'
}
token() { bash "$LC" --session "$S" --repo acme/widgets "$@" 2>"$T/err" | sed 's/ sealed:.*//'; }

echo "== the five tokens =="
scenario "$PERMIT" "$PERMIT"
OUT=$(bash "$LC" --session "$S" --repo acme/widgets 2>"$T/err")
eq "a permitted merge at the verified head is permit" "permit 12 $H" "${OUT% sealed:*}"
bash "$CL" check --session "$S" --state land --sealed "$OUT" && ok "the token is sealed to the latest entry into land" || bad "the token is sealed to the latest entry into land"
scenario "$PERMIT" "readable merge:deny close:permit teardown:permit"
eq "a denied merge is deny" "deny 12 $H" "$(token)"
scenario "$PERMIT" "readable merge:confirm close:permit teardown:permit"
eq "a merge behind a person's confirmation is confirm" "confirm 12 $H" "$(token)"
scenario "readable merge=permit close=permit teardown=permit" "readable merge=deny close=permit teardown=permit"
eq "the older = form between step and value is still read" "deny 12 $H" "$(token)"
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
scenario "readable merge:deny close:permit teardown:permit" "$PERMIT"
eq "a start deny isn't widened by a permit now" "deny 12 $H" "$(token)"
scenario "readable merge:confirm close:permit teardown:permit" "unread merge:unread close:permit teardown:permit"
eq "a start confirm stays confirm when the re-read is unread" "confirm 12 $H" "$(token)"
scenario "$PERMIT" "unread merge:unread close:unread teardown:unread"
eq "a start permit with an unreadable posture now is confirm" "confirm 12 $H" "$(token)"

echo "== an unread posture and the human's answer =="
# The answer is posture_ask's evidence (merge: permitted), never Reversals prose;
# the row on GitHub is the proof it was recorded, dated at or after it.
UNREAD="unread merge:unread close:unread teardown:unread"
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
scenario "$UNREAD" "unread merge:deny close:unread teardown:unread"; answer permitted
bt_record_body "[$HUMAN]"
eq "a deny now beats the human's earlier answer" "deny 12 $H" "$(token)"
scenario "$PERMIT" "$UNREAD"; answer permitted
bt_record_body "[$HUMAN]"
eq "the answer counts only when the start read was unread" "confirm 12 $H" "$(token)"
scenario "$UNREAD" "$UNREAD"; answer permitted
bt_record_body "[$HUMAN]"
for k in 2 3; do echo 1 > "$GH_BOARD_DIR/issue-7.rc.$k"; done   # the posture's read and its retry; the first read is the holds read
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

echo "== the worker's review round =="
# reason: the unready reason land-check.sh gave on stderr.
reason() { sed -n 's/^land-check: unready: //p' "$T/err" | head -1; }
body() { bt_body "$@" > "$T/body"; bt_prview CLEAN "$T/body"; }
scenario "$PERMIT" "$PERMIT"
printf '%s\n\n---\n\nNo panel here.\n' "$BT_PART1" > "$T/body"; bt_prview CLEAN "$T/body"
eq "a body with no Review panel is unready" "unready 12 $H" "$(token)"
eq "  ... for no-evidence" no-evidence "$(reason)"
scenario "$PERMIT" "$PERMIT"
bt_body | sed 's/comment-102/comment-101/' > "$T/body"; bt_prview CLEAN "$T/body"
eq "two seats sharing a Run are unready" "unready 12 $H" "$(token)"
eq "  ... for malformed:run-repeated" malformed:run-repeated "$(reason)"
scenario "$PERMIT" "$PERMIT"
bt_body | sed 's/| maintainer |/| Architect |/' > "$T/body"; bt_prview CLEAN "$T/body"
eq "two rows naming one seat are unready (malformed:seat-repeated)" malformed:seat-repeated "$(token >/dev/null; reason)"
scenario "$PERMIT" "$PERMIT"
bt_body | grep -v pragmatic > "$T/body"; bt_prview CLEAN "$T/body"
eq "two seats are too few" too-few-seats "$(token >/dev/null; reason)"
scenario "$PERMIT" "$PERMIT"
body "$H" fail
eq "a failing seat is not unanimous" "unready 12 $H" "$(token)"
eq "  ... for not-unanimous" not-unanimous "$(reason)"
scenario "$PERMIT" "readable merge:deny close:permit teardown:permit"
eq "a ready pull request under a denied merge is deny" "deny 12 $H" "$(token)"
OUT=$(bash "$LC" --session "$S" --repo acme/widgets 2>/dev/null)
bash "$CL" check --session "$S" --state land --sealed "$OUT" >/dev/null 2>&1 \
    && eq "  ... and coord/land.json carries the message, equal to the title and Part 1" \
        "$(printf 'feat(land): read the round\n\nReads the worker'"'"'s review round in the land step.')" \
        "$("$KOTO_BIN" context get "$S" coord/land.json | jq -r .message)" \
    || bad "  ... the sealed deny token checks"
eq "  ... and the changed files" '["skills/x.sh"]' "$("$KOTO_BIN" context get "$S" coord/land.json | jq -c .files)"

echo "== the reviewed head =="
OLD=2222222222222222222222222222222222222222
MAINC=3333333333333333333333333333333333333333
# fresh_case <files-merged-in> <files-main-changed> [parents-count]: the head
# $H is a merge of $OLD (the reviewed head) and $MAINC (on main).
fresh_case() {
    scenario "$PERMIT" "$PERMIT"
    body "$OLD"
    if [ "${3:-2}" = 2 ]; then
        jq -nc --arg a "$OLD" --arg b "$MAINC" '{parents: [{sha: $a}, {sha: $b}]}' > "$GH_BOARD_DIR/commit-$H.out"
    else
        jq -nc --arg a "$OLD" '{parents: [{sha: $a}]}' > "$GH_BOARD_DIR/commit-$H.out"
    fi
    echo '{"status":"behind","files":[]}' > "$GH_BOARD_DIR/compare-main...$MAINC.out"
    jq -nc --argjson f "$2" '{status: "ahead", files: [$f[] | {filename: .}]}' > "$GH_BOARD_DIR/compare-$OLD...$MAINC.out"
    jq -nc --argjson f "$1" '{status: "ahead", files: [$f[] | {filename: .}]}' > "$GH_BOARD_DIR/compare-$OLD...$H.out"
}
fresh_case '["a.md"]' '["a.md","b.md"]'
eq "a reviewed head one main merge-in behind is fresh" "permit 12 $H" "$(token)"
fresh_case '["a.md","mine.sh"]' '["a.md"]'
eq "a merge-in that touches a file main didn't is unready" "unready 12 $H" "$(token)"
eq "  ... for stale:files" stale:files "$(reason)"
fresh_case '["a.md"]' '["a.md"]' 1
eq "a commit after the round that isn't a merge is stale:not-a-merge" stale:not-a-merge "$(token >/dev/null; reason)"
fresh_case '["a.md"]' '["a.md"]'
echo '{"status":"ahead","files":[]}' > "$GH_BOARD_DIR/compare-main...$MAINC.out"
eq "a second parent not on main is stale:not-on-base" stale:not-on-base "$(token >/dev/null; reason)"
fresh_case '["a.md"]' "$(jq -nc '[range(300) | "f\(.).md"]')"
eq "a comparison at the 300-file limit is stale:too-many-files" stale:too-many-files "$(token >/dev/null; reason)"
# A chain of eleven main merge-ins, each fresh on its own: past the cap of ten.
fresh_case '["a.md"]' '["a.md"]'
prev=$H
for i in 1 2 3 4 5 6 7 8 9 10 11; do
    p=$(printf '%040d' "$i")
    jq -nc --arg a "$p" --arg b "$MAINC" '{parents: [{sha: $a}, {sha: $b}]}' > "$GH_BOARD_DIR/commit-$prev.out"
    echo '{"status":"ahead","files":[{"filename":"a.md"}]}' > "$GH_BOARD_DIR/compare-$p...$MAINC.out"
    echo '{"status":"ahead","files":[{"filename":"a.md"}]}' > "$GH_BOARD_DIR/compare-$p...$prev.out"
    prev=$p
done
eq "more than ten merge-ins is stale:too-many-merges" stale:too-many-merges "$(token >/dev/null; reason)"
fresh_case '["a.md"]' '["a.md"]'
echo 1 > "$GH_BOARD_DIR/commit-$H.rc"; echo 'gh: Server Error (HTTP 502)' > "$GH_BOARD_DIR/commit-$H.err"; rm -f "$GH_BOARD_DIR/commit-$H.out"
bash "$LC" --session "$S" --repo acme/widgets >/dev/null 2>&1; eq "a failed commit read: exit 2" 2 $?

echo "== the body checks and the message =="
scenario "$PERMIT" "$PERMIT"
echo '{"schema":"shirabe-pr-body/v1","outcome":"violations","findings":[{"line":1,"message":"bad title"}]}' > "$BT_STATE/shirabe.out"
eq "a body failing the PR-body checks is unready" "unready 12 $H" "$(token)"
eq "  ... for body-checks" body-checks "$(reason)"
rm -f "$BT_STATE/shirabe.out"
scenario "$PERMIT" "$PERMIT"
bt_body | sed '1s/.*/Co-Authored-By: someone/' > "$T/body"; bt_prview CLEAN "$T/body"
eq "a Part 1 with an attribution line is unready for message" message "$(token >/dev/null; reason)"

echo "== holds =="
# hold <name> <on> <until> [lifted]: one Holds row.
hold() { jq -nc --arg h "$1" --arg o "$2" --arg u "$3" --arg l "${4-}" \
    '{hold: $h, on: $o, until: $u, set_by: "the workspace coordinator", set: "2026-09-26T09:00Z", lifted: $l}'; }
prstate() { jq -nc --arg s "$2" '{state: $s}' > "$GH_BOARD_DIR/prview-$1.out"; }
scenario "$PERMIT" "$PERMIT"
bt_record_body '[]' "[$(hold after-346 acme/widgets#12 'merged acme/gadgets#346')]"
prstate 346 OPEN
eq "a hold until another pull request merges, still open: held" "held 12 $H" "$(token)"
OUT=$(bash "$LC" --session "$S" --repo acme/widgets 2>/dev/null)
eq "  ... and coord/land.json names it unmet" "after-346 unmet" "$("$KOTO_BIN" context get "$S" coord/land.json | jq -r '.holds[] | "\(.hold) \(.state)"')"
scenario "$PERMIT" "$PERMIT"
bt_record_body '[]' "[$(hold after-346 acme/widgets#12 'merged acme/gadgets#346')]"
prstate 346 MERGED
eq "once that pull request merged, the hold is met: permit" "permit 12 $H" "$(token)"
scenario "$PERMIT" "readable merge:deny close:permit teardown:permit"
bt_record_body '[]' "[$(hold after-346 acme/widgets#12 'merged acme/gadgets#346')]"
prstate 346 CLOSED
eq "a hold beats the posture: held, not deny" "held 12 $H" "$(token)"
scenario "$PERMIT" "$PERMIT"
bt_record_body '[]' "[$(hold v028 acme/widgets#12 'tag acme/gadgets v0.28.0')]"
echo '{"ref":"refs/tags/v0.28.0","object":{"sha":"abc"}}' > "$GH_BOARD_DIR/tag-v0.28.0.out"
eq "a hold until a tag, tagged: permit" "permit 12 $H" "$(token)"
scenario "$PERMIT" "$PERMIT"
bt_record_body '[]' "[$(hold v028 acme/widgets#12 'tag acme/gadgets v0.28.0')]"
echo 'gh: Not Found (HTTP 404)' > "$GH_BOARD_DIR/tag-v0.28.0.err"; echo 1 > "$GH_BOARD_DIR/tag-v0.28.0.rc"
eq "a hold until a tag, not yet tagged: held" "held 12 $H" "$(token)"
scenario "$PERMIT" "$PERMIT"
bt_record_body '[]' "[$(hold v028 acme/widgets#12 'tag acme/gadgets v0.28.0')]"
echo 'gh: Server Error (HTTP 502)' > "$GH_BOARD_DIR/tag-v0.28.0.err"; echo 1 > "$GH_BOARD_DIR/tag-v0.28.0.rc"
eq "a condition that can't be read: held" "held 12 $H" "$(token)"
grep -q 'unreadable' "$T/err" && ok "  ... naming it unreadable" || bad "  ... naming it unreadable" "$(cat "$T/err")"
scenario "$PERMIT" "$PERMIT"
bt_record_body '[]' "[$(hold go acme/widgets#12 lifted)]"
eq "a hold a person lifts, standing: held" "held 12 $H" "$(token)"
scenario "$PERMIT" "$PERMIT"
bt_record_body '[]' "[$(hold go acme/widgets#12 lifted '2026-09-26T10:00Z by the human')]"
eq "once lifted, with who and when: permit" "permit 12 $H" "$(token)"
scenario "$PERMIT" "$PERMIT"
bt_record_body '[]' "[$(hold other acme/widgets#13 lifted), $(hold elsewhere acme/gadgets#12 lifted)]"
eq "holds on another pull request, or the same number elsewhere, don't apply" "permit 12 $H" "$(token)"
scenario "$PERMIT" "$PERMIT"
bt_record_body '[]'
echo 1 > "$GH_BOARD_DIR/issue-7.rc"
bash "$LC" --session "$S" --repo acme/widgets >/dev/null 2>&1; eq "a record that can't be read for its holds: exit 2" 2 $?

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

echo "== pauses =="
paused_record() { bt_record_paused "$@"; }
prow() { bt_pause "$@"; }
scenario "$PERMIT" "$PERMIT"
paused_record "[$(prow s1 pause "Feature 2" lifted)]"
OUT=$(bash "$LC" --session "$S" --repo acme/widgets 2>"$T/err")
eq "a pause on the pull request's unit: paused" "paused 12 $H" "${OUT% sealed:*}"
bash "$CL" check --session "$S" --state land --sealed "$OUT" && ok "  ... sealed to the latest entry into land" || bad "  ... sealed to the latest entry into land"
eq "  ... and coord/land.json names the unit and the pause" "Feature 2 s1 paused" \
    "$("$KOTO_BIN" context get "$S" coord/land.json | jq -r '"\(.pauses.unit) \(.pauses.paused) \(.verdict)"')"
scenario "$PERMIT" "$PERMIT"
paused_record "[$(prow s1 pause all "time 2099-01-01T00:00Z")]" "[$(hold after-346 acme/widgets#12 'merged acme/gadgets#346')]"
prstate 346 OPEN
eq "a pause on all beats a hold: paused, not held" "paused 12 $H" "$(token)"
scenario "$PERMIT" "$PERMIT"
paused_record "[$(prow s1 pause all lifted)]"
bt_prview CLEAN /dev/null
eq "a pause comes before the worker's evidence: paused, not unready" "paused 12 $H" "$(token)"
scenario "$PERMIT" "$PERMIT"
paused_record "[$(prow s1 pause "Feature 3" lifted)]"
eq "a pause on another unit holds nothing here: permit" "permit 12 $H" "$(token)"
scenario "$PERMIT" "$PERMIT"
paused_record "[$(prow s1 pause all lifted), $(prow s2 go-ahead "Feature 2" "")]"
eq "a go-ahead on the unit lets it through an all pause: permit" "permit 12 $H" "$(token)"
scenario "$PERMIT" "$PERMIT"
paused_record "[$(prow s1 pause all "time 2000-01-01T00:00Z")]"
eq "a pause whose minute has passed: permit" "permit 12 $H" "$(token)"


echo "== the milestone's Evidence for goal fit =="
# milestone_record <unit>: record #7 with pull request #12's holding on <unit>.
milestone_record() {
    jq -nc --arg u "$1" '{scope: {kind: "roadmap", name: "demo"},
        holdings: [{unit: $u, entry_point: "/shirabe:deliver", mode: "--auto", phase: "executing",
            dispatch_status: "dispatched", return_path: "message", worker: "worker-mv1", repo: "acme/widgets",
            branch: "feat/x", verified_head: "", dispatched: "2026-09-26",
            pull_request: "[#12](https://github.com/acme/widgets/pull/12)"}],
        deferrals: [], side_effects: [], reversals: [], holds: []}' > "$T/rec.json"
    bash "$PS/record-render.sh" --written 2026-09-26T11:00:00Z "$T/rec.json" > "$T/rec.md" || return 1
    jq -Rsc '{number: 7, body: .}' "$T/rec.md" > "$GH_BOARD_DIR/issue-7.out"
}
# main_roadmap <file>: the host's default branch, main, with <file> as the
# run's roadmap on it.
main_roadmap() {
    echo '{"full_name":"acme/widgets","default_branch":"main"}' > "$GH_BOARD_DIR/repo.out"
    jq -nc --arg c "$(base64 < "$1")" '{content: $c, encoding: "base64"}' > "$GH_BOARD_DIR/contents-main-docs__roadmaps__ROADMAP-demo.md.out"
}
landjson() { "$KOTO_BIN" context get "$S" coord/land.json; }
cat > "$T/v2.md" <<'EOF'
---
schema: roadmap/v2
status: Active
---

# ROADMAP: demo

## Features

### MV1: the plugin list

**Outcome:** A maintainer lists the plugins they installed.

**Evidence:**
- A reviewer runs `widgets list` and sees exactly the three sample plugins.
- The same reviewer removes one manifest and sees it named as skipped.

**Left open:** the output layout.

**Dependencies:** None
**Status:** In progress

## Progress

- 2026-10-01: MV1 started
EOF
printf -- '---\nstatus: Active\n---\n\n# Roadmap\n\n## Features\n\n### Feature 2: second\n\n**Dependencies:** None\n**Status:** In progress\n' > "$T/v1.md"

scenario "$PERMIT" "$PERMIT"
milestone_record MV1; main_roadmap "$T/v2.md"
eq "a pull request for a milestone on a v2 roadmap: the token is unchanged" "permit 12 $H" "$(token)"
eq "  ... and coord/land.json carries the milestone's tag and numbered Evidence" \
    '{"tag":"MV1","evidence":["A reviewer runs `widgets list` and sees exactly the three sample plugins.","The same reviewer removes one manifest and sees it named as skipped."]}' \
    "$(landjson | jq -c .milestone)"
grep -q 'contents/docs/roadmaps/ROADMAP-demo.md?ref=main' "$GH_BOARD_DIR/calls" && ok "  ... read on the default branch" || bad "  ... read on the default branch" "$(cat "$GH_BOARD_DIR/calls")"
scenario "$PERMIT" "readable merge:deny close:permit teardown:permit"
milestone_record MV1; main_roadmap "$T/v2.md"
eq "under a denied merge too, which goal fit also reads" "deny 12 $H MV1" "$(token) $(landjson | jq -r .milestone.tag)"
scenario "$PERMIT" "$PERMIT"
milestone_record "Feature 2"; main_roadmap "$T/v1.md"
eq "a v1 roadmap adds nothing" "permit 12 $H null null" "$(token) $(landjson | jq -c '.milestone, .milestone_error' | tr '\n' ' ' | sed 's/ $//')"
scenario "$PERMIT" "$PERMIT"
main_roadmap "$T/v2.md"
eq "no holding naming the pull request adds nothing" "permit 12 $H null null" "$(token) $(landjson | jq -c '.milestone, .milestone_error' | tr '\n' ' ' | sed 's/ $//')"
grep -q 'contents/' "$GH_BOARD_DIR/calls" && bad "  ... and reads no roadmap" "$(cat "$GH_BOARD_DIR/calls")" || ok "  ... and reads no roadmap"
scenario "$PERMIT" "$PERMIT"
milestone_record MV1; main_roadmap "$T/v2.md"
K="$GH_BOARD_DIR/contents-main-docs__roadmaps__ROADMAP-demo.md"
rm -f "$K.out"; echo 'gh: Server Error (HTTP 502)' > "$K.err"; echo 1 > "$K.rc"
eq "a failed roadmap read doesn't change the token" "permit 12 $H" "$(token)"
eq "  ... coord/land.json says why, with no milestone" "null true" "$(landjson | jq -c '.milestone, (.milestone_error | test("couldn.t be read"))' | tr '\n' ' ' | sed 's/ $//')"
scenario "$PERMIT" "$PERMIT"
milestone_record MV1
eq "neither does a failed default-branch read" "permit 12 $H" "$(token)"
scenario "$PERMIT" "$PERMIT"
milestone_record MV7; main_roadmap "$T/v2.md"
eq "a unit with no milestone on a v2 roadmap: the token stands" "permit 12 $H" "$(token)"
case "$(landjson | jq -r '.milestone_error // ""')" in
    "MV7 has no Evidence on main"*) ok "  ... and coord/land.json says so" ;;
    *) bad "  ... and coord/land.json says so" "$(landjson | jq -c .)" ;;
esac
echo
echo "land-check: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
