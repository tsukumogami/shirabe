#!/usr/bin/env bash
# state-hold_test.sh -- state-hold.sh, the one way the Holds section
# changes: add a hold, lift a `lifted` one, list them.
#
# Covers: --list on a record with no section ([]), and in record order; a hold
# added appends the section, in the run's session's record/holds; a second
# hold of the same name, a lifted new hold and a malformed Until refused (65);
# --lift stamping the minute and who, only for a `lifted` hold, and only once;
# a lift of an unknown hold refused; each add and lift told as a `hold` entry;
# usage errors; reads writing nothing; nothing written on GitHub. The
# section's one writer: state-write.sh dropping or changing a hold refused
# (65), carrying it unchanged fine; a hold naming a private repository on a
# public host refused.
#
# Usage: bash skills/coordinate/scripts/state-hold_test.sh
set -uo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
command -v jq >/dev/null 2>&1 || { echo "SKIP: jq not on PATH"; exit 0; }
. "$HERE/testdata/test-lib.sh"
RH="$HERE/state-hold.sh"

SR=coordinate-roadmap-plugin-system-20260926T070000Z
export RS_SESSION=$SR
RM=(--scope roadmap --name plugin-system --repo "$REPO")
W_RM=("${RM[@]}" --skip-session-checks)
seed() { db_init; seed_session "$SR" "$1"; } # seed <record-json>
live() { session_state "$SR"; }
gh_writes() { grep -E 'issue (create|edit|close)|pr (create|edit)|comment|--method (POST|PUT|PATCH|DELETE)' "$GH_DB.calls"; }
hold() { # hold <name> <on> <until>
    jq -nc --arg h "$1" --arg o "$2" --arg u "$3" \
        '{hold: $h, on: $o, until: $u, set_by: "the workspace coordinator", set: "2026-09-26T09:00Z"}'
}

echo "== list =="
seed "$(record_json roadmap plugin-system)"
eq "--list with no Holds section is []" "[]" "$(bash "$RH" "${RM[@]}" --list 2>&1)"
eq "a read writes nothing, and reads nothing on GitHub" "" "$(calls)"

echo "== add =="
hold after-346 acme/widgets#12 "merged acme/gadgets#346" > "$T/h1.json"
OUT=$(bash "$RH" "${W_RM[@]}" --add --row-file "$T/h1.json" 2>"$T/err"); rc=$?
eq "a hold is added" "0 $SR" "$rc $OUT"
eq "the section holds it, unlifted" "after-346 acme/widgets#12 merged acme/gadgets#346 []" \
    "$(live | jq -r '.holds[0] | "\(.hold) \(.on) \(.until) [\(.lifted)]"')"
eq "  ... in record/holds" after-346 "$(koto context get "$SR" record/holds | jq -r '.[0].hold')"
eq "  ... told as a hold entry" "hold|Hold after-346 added on acme/widgets#12, until merged acme/gadgets#346, set by the workspace coordinator." \
    "$(koto context get "$SR" record/entries/000001 | jq -r '"\(.kind)|\(.text)"')"
eq "  ... with nothing written on GitHub" "" "$(gh_writes)"
hold go-signal acme/widgets#13 lifted > "$T/h2.json"
bash "$RH" "${W_RM[@]}" --add --row-file "$T/h2.json" >/dev/null 2>"$T/err"; eq "a second hold is added" 0 $?
eq "--list keeps record order" "after-346 go-signal" "$(bash "$RH" "${RM[@]}" --list | jq -r 'map(.hold) | join(" ")')"
bash "$RH" "${W_RM[@]}" --add --row-file "$T/h1.json" >/dev/null 2>"$T/err"; eq "a hold of the same name is refused" 65 $?
jq -c '.hold = "pre-lifted" | .until = "lifted" | .lifted = "2026-09-26T09:30Z by the human"' "$T/h1.json" > "$T/h3.json"
bash "$RH" "${W_RM[@]}" --add --row-file "$T/h3.json" >/dev/null 2>"$T/err"; eq "a new hold that's already lifted is refused" 65 $?
hold bad acme/widgets#14 "until Monday" > "$T/h4.json"
bash "$RH" "${W_RM[@]}" --add --row-file "$T/h4.json" >/dev/null 2>"$T/err"; eq "an Until outside the three conditions is refused" 65 $?
grep -q 'holds.until' "$T/err" && ok "  ... naming the column" || bad "  ... naming the column" "$(cat "$T/err")"
hold tagged acme/widgets#15 "tag acme/gadgets v0.28.0" > "$T/h5.json"
bash "$RH" "${W_RM[@]}" --add --row-file "$T/h5.json" >/dev/null 2>"$T/err"; eq "a tag condition is accepted" 0 $?

echo "== lift =="
bash "$RH" "${W_RM[@]}" --lift --hold go-signal --by "the human" >/dev/null 2>"$T/err"; eq "a lifted hold is lifted" 0 $?
lifted=$(live | jq -r '.holds[] | select(.hold == "go-signal") | .lifted')
grep -Eq '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}Z by the human$' <<<"$lifted" \
    && ok "  ... stamped with the minute and who" || bad "  ... stamped with the minute and who" "$(live | jq -c .holds)"
bash "$RH" "${W_RM[@]}" --lift --hold go-signal --by "the human" >/dev/null 2>"$T/err"; eq "lifting it twice is refused" 65 $?
bash "$RH" "${W_RM[@]}" --lift --hold after-346 --by "the human" >/dev/null 2>"$T/err"; eq "a merged condition isn't lifted by hand" 65 $?
bash "$RH" "${W_RM[@]}" --lift --hold nosuch --by "the human" >/dev/null 2>"$T/err"; eq "an unknown hold is refused" 65 $?
eq "no hold is ever removed" 3 "$(live | jq '.holds | length')"
eq "the lift is told too" "hold|Hold go-signal lifted by the human." \
    "$(koto context get "$SR" record/entries/000004 | jq -r '"\(.kind)|\(.text)"')"

echo "== the section has one writer =="
W=(--scope roadmap --name plugin-system --repo "$REPO" --skip-session-checks)
# A whole-state write through state-write.sh that drops a hold, or lifts one.
live > "$T/now.json"
jq -c 'del(.written) | .holds |= map(select(.hold != "after-346"))' "$T/now.json" > "$T/drop.json"
state_json "$(cat "$T/drop.json")" "$(jq -r .written "$T/now.json")" > "$T/drop.state"
bash "$HERE/state-write.sh" "${W[@]}" --state-file "$T/drop.state" >/dev/null 2>"$T/err"; eq "another writer dropping a hold is refused" 65 $?
grep -q 'only through state-hold.sh' "$T/err" && ok "  ... naming the one writer" || bad "  ... naming the one writer" "$(cat "$T/err")"
jq -c 'del(.written) | .holds |= map(if .hold == "tagged" then .set_by = "someone else" else . end)' "$T/now.json" > "$T/edit.json"
state_json "$(cat "$T/edit.json")" "$(jq -r .written "$T/now.json")" > "$T/edit.state"
bash "$HERE/state-write.sh" "${W[@]}" --state-file "$T/edit.state" >/dev/null 2>"$T/err"; eq "another writer changing a hold is refused" 65 $?
jq -c 'del(.written)' "$T/now.json" > "$T/same.json"
state_json "$(cat "$T/same.json")" "$(jq -r .written "$T/now.json")" > "$T/same.state"
bash "$HERE/state-write.sh" "${W[@]}" --state-file "$T/same.state" >/dev/null 2>"$T/err"; eq "another writer carrying the holds as they are is fine" 0 $?
eq "  ... and every hold is still there" 3 "$(live | jq '.holds | length')"

echo "== a public host and a private repository =="
db '.repos["acme/secret"] = {private: true}'
hold leak acme/widgets#16 "merged acme/secret#5" > "$T/h6.json"
bash "$RH" "${W_RM[@]}" --add --row-file "$T/h6.json" >/dev/null 2>"$T/err"; eq "a hold naming a private repository on a public host is refused" 65 $?

echo "== usage =="
bash "$RH" "${RM[@]}" >/dev/null 2>&1; eq "no mode" 64 $?
bash "$RH" "${RM[@]}" --lift --hold go-signal >/dev/null 2>&1; eq "--lift without --by" 64 $?
bash "$RH" "${RM[@]}" --add >/dev/null 2>&1; eq "--add without a row file" 64 $?
bash "$RH" "${RM[@]}" --list --add >/dev/null 2>&1; eq "two modes" 64 $?

eq "nothing in this suite was written on GitHub" "" "$(gh_writes)"
echo
echo "state-hold: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
