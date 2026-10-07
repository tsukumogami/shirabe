#!/usr/bin/env bash
# record-hold_test.sh -- record-hold.sh, the one way the Holds section
# changes: add a hold, lift a `lifted` one, list them.
#
# Covers: --list on a record with no section ([]), and in record order; a hold
# added appends the section, and the body round-trips through the codec; a
# second hold of the same name, a lifted new hold and a malformed Until
# refused (65); --lift stamping the minute and who, only for a `lifted` hold,
# and only once; a lift of an unknown hold refused; usage errors; reads
# writing nothing; the write as a whole-body edit. The section's one writer:
# record-write.sh dropping or changing a hold refused (65), carrying it
# unchanged fine; a hold naming a private repository on a public host
# refused.
#
# Usage: bash skills/coordinate/scripts/record-hold_test.sh
set -uo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
command -v jq >/dev/null 2>&1 || { echo "SKIP: jq not on PATH"; exit 0; }
. "$HERE/testdata/test-lib.sh"
RH="$HERE/record-hold.sh"

TITLE="Coordinator record: ROADMAP-plugin-system"
RM=(--scope roadmap --name plugin-system --repo "$REPO" --ref 7)
W_RM=("${RM[@]}" --skip-session-checks)
seed() { # seed <record-json>
    db_init
    db '.issues += [{repo: "acme/widgets", number: 7, title: $t, body: $b, state: "open", author: "alice", editor: null}]' \
        --arg t "$TITLE" --arg b "$(render "$1" issue 2026-09-26T08:00:00Z)"
}
live() { jq -r '.issues[] | select(.number == 7) | .body' "$GH_DB" | bash "$HERE/record-parse.sh"; }
hold() { # hold <name> <on> <until>
    jq -nc --arg h "$1" --arg o "$2" --arg u "$3" \
        '{hold: $h, on: $o, until: $u, set_by: "the workspace coordinator", set: "2026-09-26T09:00Z"}'
}

echo "== list =="
seed "$(record_json roadmap plugin-system)"
eq "--list with no Holds section is []" "[]" "$(bash "$RH" "${RM[@]}" --list 2>&1)"
grep -qE 'edit|create|close' "$GH_DB.calls" && bad "a read writes nothing" "$(calls)" || ok "a read writes nothing"

echo "== add =="
hold after-346 acme/widgets#12 "merged acme/gadgets#346" > "$T/h1.json"
OUT=$(bash "$RH" "${W_RM[@]}" --add --row-file "$T/h1.json" 2>"$T/err"); rc=$?
eq "a hold is added" "0 https://github.com/acme/widgets/issues/7" "$rc $OUT"
eq "the section holds it, unlifted" "after-346 acme/widgets#12 merged acme/gadgets#346 []" \
    "$(live | jq -r '.holds[0] | "\(.hold) \(.on) \(.until) [\(.lifted)]"')"
grep -q '^issue edit 7' "$GH_DB.calls" && ! grep -q comment "$GH_DB.calls" && ok "the write is a whole-body edit, no comment" || bad "the write is a whole-body edit, no comment" "$(calls)"
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
live | jq -r '.holds[] | select(.hold == "go-signal") | .lifted' | grep -Eq '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}Z by the human$' \
    && ok "  ... stamped with the minute and who" || bad "  ... stamped with the minute and who" "$(live | jq -c .holds)"
bash "$RH" "${W_RM[@]}" --lift --hold go-signal --by "the human" >/dev/null 2>"$T/err"; eq "lifting it twice is refused" 65 $?
bash "$RH" "${W_RM[@]}" --lift --hold after-346 --by "the human" >/dev/null 2>"$T/err"; eq "a merged condition isn't lifted by hand" 65 $?
bash "$RH" "${W_RM[@]}" --lift --hold nosuch --by "the human" >/dev/null 2>"$T/err"; eq "an unknown hold is refused" 65 $?
eq "no hold is ever removed" 3 "$(live | jq '.holds | length')"

echo "== the section has one writer =="
W=(--scope roadmap --name plugin-system --repo "$REPO" --ref 7 --skip-session-checks)
# A whole-body write through record-write.sh that drops a hold, or lifts one.
live > "$T/now.json"
jq -c 'del(.written) | .holds |= map(select(.hold != "after-346"))' "$T/now.json" > "$T/drop.json"
bash "$HERE/record-render.sh" --written "$(jq -r .written "$T/now.json")" "$T/drop.json" > "$T/drop.md"
bash "$HERE/record-write.sh" "${W[@]}" --body-file "$T/drop.md" >/dev/null 2>"$T/err"; eq "another writer dropping a hold is refused" 65 $?
grep -q 'only through record-hold.sh' "$T/err" && ok "  ... naming the one writer" || bad "  ... naming the one writer" "$(cat "$T/err")"
jq -c 'del(.written) | .holds |= map(if .hold == "tagged" then .set_by = "someone else" else . end)' "$T/now.json" > "$T/edit.json"
bash "$HERE/record-render.sh" --written "$(jq -r .written "$T/now.json")" "$T/edit.json" > "$T/edit.md"
bash "$HERE/record-write.sh" "${W[@]}" --body-file "$T/edit.md" >/dev/null 2>"$T/err"; eq "another writer changing a hold is refused" 65 $?
jq -c 'del(.written)' "$T/now.json" > "$T/same.json"
bash "$HERE/record-render.sh" --written "$(jq -r .written "$T/now.json")" "$T/same.json" > "$T/same.md"
bash "$HERE/record-write.sh" "${W[@]}" --body-file "$T/same.md" >/dev/null 2>"$T/err"; eq "another writer carrying the holds as they are is fine" 0 $?
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

echo
echo "record-hold: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
