#!/usr/bin/env bash
# record-move_test.sh -- record-move.sh, the move of a roadmap record from GitHub
# onto the session store (docs/designs/DESIGN-coordinator-session-record.md,
# Decision 11; PRD R3).
#
# Covers:
#   1. a move: the GitHub state lands in the run's session, one `moved` entry is
#      posted naming the run's stamp, and the GitHub body becomes the moved shape;
#      a re-run finds every step done and changes nothing;
#   2. a move killed after its first step, or inside it, finishes on the next run with one
#      `moved` entry;
#   3. afterwards a GitHub write to the record is store-moved, and so is
#      `record-state.sh --run store github`, on either store;
#   4. a move whose scope's state another session here holds is refused, and so
#      is a record whose Run section doesn't read store session.
#
# Usage: bash skills/coordinate/scripts/record-move_test.sh
set -uo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
command -v jq >/dev/null 2>&1 || { echo "SKIP: jq not on PATH"; exit 0; }
. "$HERE/testdata/test-lib.sh"
MV="$HERE/record-move.sh"
TITLE="Coordinator record: ROADMAP-plugin-system"
RM=(--scope roadmap --name plugin-system --repo "$REPO" --ref 7)
W_RM=("${RM[@]}" --skip-session-checks)

# The record before its move: a holding, a hold, the owner's store row, and the
# run entry record-state.sh posts with the row.
STATE=$(record_json roadmap plugin-system | jq -c --argjson h "$(holding feature-2)" '
    .holdings = [$h]
    | .holds = [{hold: "after-release", on: "acme/widgets#12", until: "lifted", set_by: "the human", set: "2026-09-29T20:30Z", lifted: ""}]
    | .run = [{key: "store", value: "session", set_by: "alice", set: "2026-10-11T10:00Z"}]')
render "$STATE" issue 2026-10-11T10:00:00Z > "$T/before.md"
bash "$HERE/record-parse.sh" --container issue "$T/before.md" > "$T/before.json"
seed() {
    db_init
    db '.issues += [{repo: "acme/widgets", number: 7, title: $t, body: $b, state: "open", author: "alice", editor: null}]
        | .comments = [{repo: "acme/widgets", number: 7, id: 900, user: "coord", created_at: "2026-10-11T10:00:05Z", updated_at: "2026-10-11T10:00:05Z",
            body: "<!-- coordinator-record-entry v1 kind=run -->\n**2026-10-11T10:00:05Z** (host clock) run\n\nRun store set to session by alice."}]' \
        --arg t "$TITLE" --arg b "$(cat "$T/before.md")"
}
body7() { jq -r '.issues[] | select(.number == 7) | .body' "$GH_DB"; }
moved_entries() { jq '[.comments[] | select(.body | startswith("<!-- coordinator-record-entry v1 kind=moved -->"))] | length' "$GH_DB"; }

echo "== 1. a move =="
SM=coordinate-roadmap-plugin-system-20261012T090000Z
seed
OUT=$(env RS_SESSION="$SM" bash "$MV" "${W_RM[@]}" 2>"$T/err"); rc=$?
eq "the move is done" "0 move=done" "$rc $(printf '%s' "$OUT" | tail -1)"
eq "  ... the GitHub state is in the session, key by key" "$(jq -cS 'del(.written)' "$T/before.json")" \
    "$(env RS_SOURCE=session RS_SESSION="$SM" bash "$HERE/record-source.sh" "${RM[@]}" --show | bash "$HERE/record-parse.sh" | jq -cS 'del(.written)')"
eq "  ... one moved entry, naming the run's stamp" "1 yes" \
    "$(moved_entries) $(jq -r '[.comments[] | select(.body | contains("run 20261012T090000Z"))] | if length == 1 then "yes" else "no" end' "$GH_DB")"
body7 | bash "$HERE/record-parse.sh" > "$T/after.json"
eq "  ... and the GitHub body is the moved shape" '{"deferrals":[],"holdings":[],"reversals":[],"run":["store=session"],"side_effects":[]}' \
    "$(jq -cS '{holdings, deferrals, side_effects, reversals, run: [.run[] | "\(.key)=\(.value)"]}' "$T/after.json")"
eq "  ... keeping no other section" "false false" "$(jq -r '[has("holds"), has("decisions")] | map(tostring) | join(" ")' "$T/after.json")"
SNAP=$(session_snapshot "$SM"); BODY=$(body7)
OUT=$(env RS_SESSION="$SM" bash "$MV" "${W_RM[@]}" 2>"$T/err"); rc=$?
eq "a re-run finds every step done" "0 move=done" "$rc $(printf '%s' "$OUT" | tail -1)"
eq "  ... and changes nothing" "$SNAP|$BODY|1" "$(session_snapshot "$SM")|$(body7)|$(moved_entries)"

echo "== 2. a move killed after its first step =="
SK=coordinate-roadmap-plugin-system-20261012T100000Z
seed
db '.fail = [{match: "POST repos/acme/widgets/issues/7/comments", rc: 1, stderr: "HTTP 502"}]'
env RS_SESSION="$SK" bash "$MV" "${W_RM[@]}" >/dev/null 2>"$T/err"; rc=$?
eq "a failed second step exits 11" 11 "$rc"
koto context exists "$SK" record/meta && ok "  ... the first step stands" || bad "  ... the first step stands" "$(cat "$T/err")"
eq "  ... with no moved entry and the body unmoved" "0 $(cat "$T/before.md")" "$(moved_entries) $(body7)"
db '.fail = []'
OUT=$(env RS_SESSION="$SK" bash "$MV" "${W_RM[@]}" 2>"$T/err"); rc=$?
eq "restarted, it finishes" "0 move=done" "$rc $(printf '%s' "$OUT" | tail -1)"
eq "  ... with one moved entry" 1 "$(moved_entries)"

# Killed inside the copy: record/meta is pending and a section key never came.
SC=coordinate-roadmap-plugin-system-20261012T103000Z
seed
env KOTO_FAIL_ADD=record/holds RS_SESSION="$SC" bash "$MV" "${W_RM[@]}" >/dev/null 2>"$T/err"; rc=$?
eq "a copy that fails part way exits 11" 11 "$rc"
eq "  ... leaving record/meta pending, record/holds missing, nothing posted and the body unmoved" "true false 0 yes" \
    "$(koto context get "$SC" record/meta | jq -r .pending) $(koto context exists "$SC" record/holds && echo true || echo false) $(moved_entries) $([ "$(body7)" = "$(cat "$T/before.md")" ] && echo yes || echo no)"
koto context add "$SC" record/standing --from-file <(printf '[]') # a key the GitHub state doesn't hold
OUT=$(env RS_SESSION="$SC" bash "$MV" "${W_RM[@]}" 2>"$T/err"); rc=$?
eq "restarted, the copy runs again and the move finishes" "0 step=copy written move=done" \
    "$rc $(printf '%s' "$OUT" | grep '^step=copy') $(printf '%s' "$OUT" | tail -1)"
eq "  ... with every section of the GitHub state in the session" "$(jq -cS 'del(.written)' "$T/before.json")" \
    "$(env RS_SOURCE=session RS_SESSION="$SC" bash "$HERE/record-source.sh" "${RM[@]}" --show | bash "$HERE/record-parse.sh" | jq -cS 'del(.written)')"
koto context exists "$SC" record/standing && bad "  ... and no key it doesn't hold" "" || ok "  ... and no key it doesn't hold"
eq "  ... and one moved entry" 1 "$(moved_entries)"

echo "== 3. after the move =="
render "$(record_json roadmap plugin-system | jq -c '.run = [{key: "store", value: "session", set_by: "alice", set: "2026-10-11T10:00Z"}]')" issue \
    "$(body7 | bash "$HERE/record-parse.sh" | jq -r .written)" > "$T/write.md"
bash "$HERE/record-write.sh" "${W_RM[@]}" --body-file "$T/write.md" >/dev/null 2>"$T/err"; rc=$?
eq "a GitHub write to the moved record is refused" 65 "$rc"
grep -q 'store-moved' "$T/err" && ok "  ... as store-moved" || bad "  ... as store-moved" "$(cat "$T/err")"
bash "$HERE/record-state.sh" "${W_RM[@]}" --run store github --by alice >/dev/null 2>"$T/err"; rc=$?
eq "record-state.sh --run store github on the moved record is refused" 65 "$rc"
grep -q 'store-moved' "$T/err" && ok "  ... as store-moved" || bad "  ... as store-moved" "$(cat "$T/err")"
env RS_SOURCE=session RS_SESSION="$SK" bash "$HERE/record-state.sh" "${W_RM[@]}" --run store github --by alice >/dev/null 2>"$T/err"; rc=$?
eq "  ... and on the session store too" 65 "$rc"

# Before the move's last step the state is still the GitHub body's: the run that
# set the row keeps writing it.
seed
jq -c 'del(.written) | .deferrals = [{deferral: "a", reason: "r", raised: "2026-09-25T10:00Z", disposition: ""}]' "$T/before.json" \
    | bash "$HERE/record-render.sh" --container issue --written "$(jq -r .written "$T/before.json")" > "$T/premove.md"
bash "$HERE/record-write.sh" "${W_RM[@]}" --body-file "$T/premove.md" >/dev/null 2>"$T/err"; rc=$?
eq "before the move, a GitHub write to a record with the row and its tables goes through" 0 "$rc"

echo "== 4. refusals =="
SO=coordinate-roadmap-plugin-system-20261012T110000Z
seed
log_new "$SK" "$(roadmap_vars plugin-system)"
OUT=$(env RS_SESSION="$SO" bash "$MV" "${W_RM[@]}" 2>"$T/err"); rc=$?
eq "another session here holding the scope's state refuses the move" "65 move=refused" "$rc $(printf '%s' "$OUT" | tail -1)"
koto context exists "$SO" record/meta && bad "  ... and nothing is copied" "" || ok "  ... and nothing is copied"
db_init
db '.issues += [{repo: "acme/widgets", number: 7, title: $t, body: $b, state: "open", author: "alice", editor: null}]' \
    --arg t "$TITLE" --arg b "$(render "$(record_json roadmap plugin-system)" issue 2026-10-11T10:00:00Z)"
OUT=$(env RS_SESSION=coordinate-roadmap-plugin-system-20261012T120000Z bash "$MV" "${W_RM[@]}" 2>"$T/err"); rc=$?
eq "a record whose Run doesn't read store session isn't moved" "65 move=refused" "$rc $(printf '%s' "$OUT" | tail -1)"

done_tests record-move_test
