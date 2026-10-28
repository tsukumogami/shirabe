#!/usr/bin/env bash
# state-handover_test.sh -- the handover gate's told rule with pending rows
# (state-handover.sh --check), read from records seeded straight into the
# session store; state-stored-set_test.sh covers the writes that make them.
#
# Covers, with each gate result printed: a record written before pending rows
# existed reads and checks exactly as it did (no pending field anywhere, the
# same gaps); a pending worker passes the gate while a live worker neither told
# nor pending holds it with not-told; told passes; a cleared address holds on
# every live worker again; a merged holding needs neither; and state-schema.jq
# refusing a record that holds one worker as both told and pending, or as
# pending twice, so a reader stops on it (10).
#
# Usage: bash skills/coordinate/scripts/state-handover_test.sh
set -uo pipefail
. "$(dirname "$0")/../../../scripts/lib/koto-test-guard.sh" || exit 1

HERE=$(cd "$(dirname "$0")" && pwd)
command -v jq >/dev/null 2>&1 || { echo "SKIP: jq not on PATH"; exit 0; }
. "$HERE/testdata/test-lib.sh"
RH="$HERE/state-handover.sh"

SR=coordinate-roadmap-plugin-system-20260926T070000Z
export RS_SESSION=$SR
RM=(--scope roadmap --name plugin-system --repo "$REPO")

# row <key> <value>: a Run row.
row() { jq -nc --arg k "$1" --arg v "$2" '{key: $k, value: $v, set_by: "lane-v1", set: "2026-09-26T08:00Z"}'; }
# record <run-rows-json>: two live holdings, each with a next step, and the Run
# rows given beside the arguments, cap, reports-to and coordinator rows.
record() {
    record_json roadmap plugin-system | jq -c --argjson a "$(holding worker-f2)" \
        --argjson b "$(holding worker-f3 '{"unit": "Feature 3", "pull_request": ""}')" \
        --argjson base "[$(row arguments "--roadmap x"),$(row cap 2),$(row reports-to "the human"),$(row coordinator lane-v1)]" \
        --argjson extra "$1" '.holdings = [$a, $b] | .run = ($base + $extra)
        | .work = [{item: "Feature 2", kind: "holding", who: "worker-f2", next: "x", wakes: "0", updated: "2026-09-26T08:00Z"},
                   {item: "Feature 3", kind: "holding", who: "worker-f3", next: "y", wakes: "0", updated: "2026-09-26T08:00Z"}]'
}
seed() { db_init; seed_session "$SR" "$1"; }
# gate: the handover gate's result, printed and kept in G as "<exit> <gaps>".
gate() {
    bash "$RH" "${RM[@]}" --check >/dev/null 2>"$T/gate"
    G="$? $(awk '/^  [^:]*: / { sub(/^  /, ""); sub(/: .*/, ""); printf "%s%s", s, $0; s = "," }' "$T/gate")"
    echo "     gate: $G"
}

echo "== a record with no pending rows =="
seed "$(record "[$(row told worker-f2)]")"
H=$(bash "$RH" "${RM[@]}" 2>"$T/err"); eq "the read prints" 0 $?
eq "it reads as before pending rows existed: the same top-level fields" \
    "arguments briefs cap coordinator friction gaps holds host reports_to rules standing told work workers" \
    "$(printf '%s' "$H" | jq -r 'keys | join(" ")')"
eq "  ... each worker with the same fields" "next phase told unit worker|next phase told unit worker" \
    "$(printf '%s' "$H" | jq -r '[.workers[] | keys | join(" ")] | join("|")')"
gate; eq "  ... and the gate holds on the untold live worker, as before" "1 not-told worker-f3" "$G"
grep -q 'state-stored-set.sh --told worker-f3' "$T/gate" && ok "  ... its fix naming --told" || bad "  ... its fix naming --told" "$(cat "$T/gate")"
grep -q 'state-stored-set.sh --pending worker-f3' "$T/gate" && ok "  ... and --pending" || bad "  ... and --pending" "$(cat "$T/gate")"

echo "== pending =="
seed "$(record "[$(row told worker-f2),$(row pending worker-f3)]")"
gate; eq "a pending worker doesn't hold the gate" "0 " "$G"
eq "  ... and the read names it pending" '["worker-f2"]|["worker-f3"]|worker-f2:false worker-f3:true' \
    "$(bash "$RH" "${RM[@]}" | jq -r '"\(.told | tojson)|\(.pending | tojson)|" + ([.workers[] | "\(.worker):\(.pending // false)"] | join(" "))')"
seed "$(record "[$(row pending worker-f3)]")"
gate; eq "a live worker neither told nor pending still holds it" "1 not-told worker-f2" "$G"

echo "== told =="
seed "$(record "[$(row told worker-f2),$(row told worker-f3)]")"
gate; eq "every live worker told: the gate passes" "0 " "$G"

echo "== clear =="
seed "$(record '[]')"
gate; eq "a new address with no told or pending row holds on every live worker" "1 not-told worker-f2,not-told worker-f3" "$G"
seed "$(record '[]' | jq -c --arg s "$SHA_HEAD" '.holdings[1].verified_head = $s | .holdings[1].pull_request = ""')"
gate; eq "a merged holding needs neither told nor pending" "1 not-told worker-f2" "$G"

echo "== the schema =="
state_json "$(record "[$(row told worker-f2),$(row pending worker-f2)]")" >/dev/null 2>"$T/err"
[ $? -ne 0 ] && grep -q 'both told and pending' "$T/err" && ok "state-schema.jq refuses a worker both told and pending" \
    || bad "state-schema.jq refuses a worker both told and pending" "$(cat "$T/err")"
state_json "$(record "[$(row pending worker-f2),$(row pending worker-f2)]")" >/dev/null 2>"$T/err"
[ $? -ne 0 ] && grep -q 'pending twice' "$T/err" && ok "  ... and a worker pending twice" || bad "  ... and a worker pending twice" "$(cat "$T/err")"
state_json "$(record "[$(row pending plugin/worker)]")" >/dev/null 2>"$T/err"
[ $? -ne 0 ] && grep -q "shape of a path" "$T/err" && ok "  ... and a pending value that isn't a messaging address" || bad "  ... and a pending value that isn't a messaging address" "$(cat "$T/err")"
# A record whose Run key was written around the write core: the reader stops.
seed "$(record "[$(row told worker-f2)]")"
jq -c '. + [{key: "pending", value: "worker-f2", set_by: "lane-v1", set: "2026-09-26T08:00Z"}]' "$KOTO_STORE/context/$SR/record/run" > "$T/run.json" \
    && cp "$T/run.json" "$KOTO_STORE/context/$SR/record/run"
gate; eq "a stored record holding a worker both told and pending doesn't read back: the gate stops (10)" "10 " "$G"
eq "nothing in this suite reached GitHub" "" "$(calls)"

done_tests state-handover_test
