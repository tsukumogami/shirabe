#!/usr/bin/env bash
# state-handover_test.sh -- the handover gate's told rule with pending rows
# (state-handover.sh --check), read from records seeded straight into the
# session store; state-stored-set_test.sh covers the writes that make them.
#
# Covers, with each gate result printed: a record written before pending rows
# existed reads and checks exactly as it did (no pending field anywhere, the
# same gaps); a pending worker passes the gate while a live worker neither told
# nor pending holds it with not-told; told passes; a cleared address holds on
# every live worker again; a merged holding needs neither; a missing worker
# (niwa listed no instance for it) passes the gate too, the read naming it
# missing, and a record with no missing row printing no missing field; and
# state-schema.jq refusing a record that holds one worker as both told and
# pending, or as pending twice, or as missing and told or pending, so a
# reader stops on it (10); the Run `role` row printed as
# role, manager, director or null, --check listing the gap no-role with its
# fix when the record holds none and no such gap when it holds either; a
# record with no reports-to row listing no-reports-to alone, and the gap
# reports-to-unsourced: none for a reports-to naming a person, listed for one
# naming a session with its fix, cleared by a dispatched-by link to that
# session (not one to another) and by a rule row's What or an event row's
# Relayed by naming it as a whole word (not a longer name holding it).
# And the gap brief-unread <label>: listed, its fix exactly the intake, when
# record/host names a readable brief no Run briefs row carries the digest of,
# and for a stale digest; not listed for a matching row, nor when record/host
# names no brief (the read's fields as before) or a file that can't be read;
# one gap of two briefs when one is taken; the brief never edited.
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
# rows given beside the arguments, cap, reports-to, coordinator and role rows.
record() {
    record_json roadmap plugin-system | jq -c --argjson a "$(holding worker-f2)" \
        --argjson b "$(holding worker-f3 '{"unit": "Feature 3", "pull_request": ""}')" \
        --argjson base "[$(row arguments "--roadmap x"),$(row cap 2),$(row reports-to "the human"),$(row coordinator lane-v1),$(row role manager)]" \
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
    "arguments briefs cap coordinator friction gaps holds host reports_to role rules standing told work workers" \
    "$(printf '%s' "$H" | jq -r 'keys | join(" ")')"
eq "  ... each worker with the same fields" "next phase told unit worker|next phase told unit worker" \
    "$(printf '%s' "$H" | jq -r '[.workers[] | keys | join(" ")] | join("|")')"
gate; eq "  ... and the gate holds on the untold live worker, as before" "1 not-told worker-f3" "$G"
grep -q 'state-stored-set.sh --told worker-f3' "$T/gate" && ok "  ... its fix naming --told" || bad "  ... its fix naming --told" "$(cat "$T/gate")"
grep -q 'state-stored-set.sh --pending worker-f3' "$T/gate" && ok "  ... and --pending" || bad "  ... and --pending" "$(cat "$T/gate")"
grep -q 'state-stored-set.sh --missing worker-f3' "$T/gate" && ok "  ... and --missing" || bad "  ... and --missing" "$(cat "$T/gate")"

echo "== pending =="
seed "$(record "[$(row told worker-f2),$(row pending worker-f3)]")"
gate; eq "a pending worker doesn't hold the gate" "0 " "$G"
eq "  ... and the read names it pending" '["worker-f2"]|["worker-f3"]|worker-f2:false worker-f3:true' \
    "$(bash "$RH" "${RM[@]}" | jq -r '"\(.told | tojson)|\(.pending | tojson)|" + ([.workers[] | "\(.worker):\(.pending // false)"] | join(" "))')"
seed "$(record "[$(row pending worker-f3)]")"
gate; eq "a live worker neither told nor pending still holds it" "1 not-told worker-f2" "$G"

echo "== missing =="
seed "$(record "[$(row told worker-f2),$(row missing worker-f3)]")"
gate; eq "a missing worker doesn't hold the gate" "0 " "$G"
eq "  ... and the read names it missing, with no pending field" '["worker-f3"]|null|worker-f2:false worker-f3:true' \
    "$(bash "$RH" "${RM[@]}" | jq -r '"\(.missing | tojson)|\(.pending | tojson)|" + ([.workers[] | "\(.worker):\(.missing // false)"] | join(" "))')"
seed "$(record "[$(row pending worker-f2),$(row missing worker-f3)]")"
gate; eq "a pending and a missing worker: the gate passes" "0 " "$G"
seed "$(record "[$(row missing worker-f3)]")"
gate; eq "a live worker neither told, pending nor missing still holds it" "1 not-told worker-f2" "$G"

echo "== told =="
seed "$(record "[$(row told worker-f2),$(row told worker-f3)]")"
gate; eq "every live worker told: the gate passes" "0 " "$G"

echo "== clear =="
seed "$(record '[]')"
gate; eq "a new address with no told or pending row holds on every live worker" "1 not-told worker-f2,not-told worker-f3" "$G"
seed "$(record '[]' | jq -c --arg s "$SHA_HEAD" '.holdings[1].verified_head = $s | .holdings[1].pull_request = ""')"
gate; eq "a merged holding needs neither told nor pending" "1 not-told worker-f2" "$G"

echo "== rule rows =="
EVENTS='[{"standing":"s1","kind":"pause","on":"Feature 3","until":"lifted","what":"hold the third lane","owner":"the human","relayed_by":"","set":"2026-09-26T08:00Z"},
 {"standing":"s2","kind":"approval","on":"","until":"","what":"ship the docs first","owner":"the human","relayed_by":"","set":"2026-09-26T08:01Z"}]'
RULE='{"standing":"s3","kind":"rule","on":"","until":"","what":"Read a CI run'"'"'s status at most once a minute.","owner":"","relayed_by":"","set":"2026-09-26T08:02Z","source":"inferred"}'
seed "$(record "[$(row told worker-f2),$(row told worker-f3)]" | jq -c --argjson s "$EVENTS" '.standing = $s')"
H=$(bash "$RH" "${RM[@]}" 2>"$T/err"); eq "a record whose Standing holds no rule row reads" 0 $?
eq "  ... with no rule_lists key: the same top-level fields as before" \
    "arguments briefs cap coordinator friction gaps holds host reports_to role rules standing told work workers" \
    "$(printf '%s' "$H" | jq -r 'keys | join(" ")')"
seed "$(record "[$(row told worker-f2),$(row told worker-f3)]" | jq -c --argjson s "$EVENTS" --argjson r "$RULE" '.standing = $s + [$r]')"
H2=$(bash "$RH" "${RM[@]}" 2>"$T/err"); eq "the same record with a rule row reads" 0 $?
eq "  ... with rule_lists, its inferred row awaiting confirmation" "awaiting-confirmation:s3 superseded: asserted-reversal: authorized-by:" \
    "$(printf '%s' "$H2" | jq -r '[.rule_lists[] | "\(.list):\([.rows[].standing] | join(","))"] | join(" ")')"
eq "  ... and everything else as the record without it reads" "$(printf '%s' "$H" | jq -cS .)" "$(printf '%s' "$H2" | jq -cS 'del(.rule_lists)')"

echo "== the role =="
# docs/designs/DESIGN-coordinator-named-roles.md, Decision 1: the role is
# printed, and a record without it holds the gate on no-role.
seed "$(record "[$(row told worker-f2),$(row told worker-f3)]" | jq -c '.run = [.run[] | select(.key != "role")]')"
eq "a record with no role row prints role null" null "$(bash "$RH" "${RM[@]}" 2>"$T/err" | jq -c .role)"
gate; eq "  ... and the gate holds on no-role" "1 no-role" "$G"
grep -qxF '  no-role: state-stored-set.sh --run role <manager|director> --by <who named it>' "$T/gate" \
    && ok "  ... its fix the set-once writer's --run role" || bad "  ... its fix the set-once writer's --run role" "$(cat "$T/gate")"
for r in manager director; do
    seed "$(record "[$(row told worker-f2),$(row told worker-f3)]" | jq -c --arg r "$r" '.run |= map(if .key == "role" then .value = $r else . end)')"
    eq "a record whose role row reads $r prints it" "\"$r\"" "$(bash "$RH" "${RM[@]}" 2>"$T/err" | jq -c .role)"
    gate; eq "  ... and the gate lists no no-role" "0 " "$G"
done
seed "$(record "[$(row told worker-f2),$(row told worker-f3)]" | jq -c '.run = [.run[] | select(.key != "reports-to")]')"
bash "$RH" "${RM[@]}" --check >/dev/null 2>"$T/gate"
grep -qF 'no-reports-to: state-stored-set.sh --run reports-to "<name>[ at <address>]" --by <who>' "$T/gate" \
    && ok "the no-reports-to fix names <name>[ at <address>]" || bad "the no-reports-to fix names <name>[ at <address>]" "$(cat "$T/gate")"
gate; eq "  ... and a record with no reports-to row lists no-reports-to alone" "1 no-reports-to" "$G"

echo "== reports-to-unsourced =="
# The design's Decision 5: a reports-to row naming a session, `<name> at
# <address>`, holds the gate unless the run's session holds a dispatched-by
# link to the address or a Standing row names it; a person's name names no
# session.
told_both="[$(row told worker-f2),$(row told worker-f3)]"
with_rt() { record "$told_both" | jq -c --arg v "$1" '.run |= map(if .key == "reports-to" then .value = $v else . end)'; }
seed "$(record "$told_both")"
gate; eq "a reports-to naming a person, the human, lists neither reports-to gap" "0 " "$G"
seed "$(with_rt "director at coord-lead")"
gate; eq "a reports-to naming a session with no link and no Standing row lists reports-to-unsourced" "1 reports-to-unsourced" "$G"
grep -qF 'reports-to-unsourced: state-stored-set.sh --run reports-to "director at coord-lead" --inferred "Report to coord-lead: ' "$T/gate" \
    && grep -qF 'koto session link <this run> --dispatched-by coord-lead' "$T/gate" \
    && ok "  ... its fix the --inferred write, or the dispatched-by link" || bad "  ... its fix the --inferred write, or the dispatched-by link" "$(cat "$T/gate")"
printf '{}' | koto context add "$SR" koto/links/dispatched-by/coord-lead
gate; eq "  ... a dispatched-by link to the address clears it" "0 " "$G"
koto context remove "$SR" koto/links/dispatched-by/coord-lead
printf '{}' | koto context add "$SR" koto/links/dispatched-by/coord-other
gate; eq "  ... a link to another session doesn't" "1 reports-to-unsourced" "$G"
koto context remove "$SR" koto/links/dispatched-by/coord-other
for c in "a rule row's What|{\"standing\":\"s1\",\"kind\":\"rule\",\"on\":\"\",\"until\":\"\",\"what\":\"Report to coord-lead.\",\"owner\":\"\",\"relayed_by\":\"\",\"set\":\"2026-09-26T08:00Z\",\"source\":\"inferred\"}" \
    "an event row's Relayed by|{\"standing\":\"s1\",\"kind\":\"approval\",\"on\":\"\",\"until\":\"\",\"what\":\"ship the docs first\",\"owner\":\"the human\",\"relayed_by\":\"coord-lead\",\"set\":\"2026-09-26T08:00Z\"}"; do
    seed "$(with_rt "director at coord-lead" | jq -c --argjson r "${c#*|}" '.standing = [$r]')"
    gate; eq "  ... $(printf '%s' "${c%%|*}") naming the address clears it" "0 " "$G"
done
seed "$(with_rt "director at coord-lead" | jq -c '.standing = [{standing: "s1", kind: "rule", on: "", until: "", what: "Report to coord-leader.", owner: "", relayed_by: "", set: "2026-09-26T08:00Z", source: "inferred"}]')"
gate; eq "  ... a row naming a longer name holding it doesn't" "1 reports-to-unsourced" "$G"

echo "== brief-unread =="
# The design's Decision 10: a brief record/host names, whose digest no Run
# briefs row carries, holds the gate until the intake takes it.
BRIEF="$T/briefs/worker.md"
mkdir -p "$T/briefs"
printf '# Brief: lane\n\n## Decisions already made\n\n- Keep one lane per feature.\n' > "$BRIEF"
if command -v sha256sum > /dev/null 2>&1; then BD=$(sha256sum < "$BRIEF" | cut -d' ' -f1); else BD=$(shasum -a 256 < "$BRIEF" | cut -d' ' -f1); fi
# host_names <json>: record/host as the --host writes leave it.
host_names() { printf '%s' "$1" | koto context add "$SR" record/host; }
seed "$(record "$told_both")"
host_names "$(jq -nc --arg p "$BRIEF" '{"briefs:worker": $p}')"
gate; eq "brief-unread: listed when no briefs row carries the file's digest" "1 brief-unread worker" "$G"
grep -qxF '  brief-unread worker: state-stored-set.sh --intake worker --by <you>' "$T/gate" \
    && ok "  ... its fix exactly the intake" || bad "  ... its fix exactly the intake" "$(cat "$T/gate")"
seed "$(record "[$(row told worker-f2),$(row told worker-f3),$(row briefs "worker sha256:$BD")]")"
host_names "$(jq -nc --arg p "$BRIEF" '{"briefs:worker": $p}')"
gate; eq "brief-unread: not listed for a matching row" "0 " "$G"
seed "$(record "[$(row told worker-f2),$(row told worker-f3),$(row briefs "worker sha256:$(printf '%064d' 0)")]")"
host_names "$(jq -nc --arg p "$BRIEF" '{"briefs:worker": $p}')"
gate; eq "brief-unread: listed for a stale digest" "1 brief-unread worker" "$G"
seed "$(record "$told_both")"
H=$(bash "$RH" "${RM[@]}" 2>"$T/err")
gate; eq "brief-unread: not listed when record/host names no brief" "0 " "$G"
eq "  ... and the read's top-level fields are as before" \
    "arguments briefs cap coordinator friction gaps holds host reports_to role rules standing told work workers" \
    "$(printf '%s' "$H" | jq -r 'keys | join(" ")')"
printf '# Brief: other\n\n## Out of scope\n\n- Leave the docs alone.\n' > "$T/briefs/other.md"
seed "$(record "[$(row told worker-f2),$(row told worker-f3),$(row briefs "worker sha256:$BD")]")"
host_names "$(jq -nc --arg p "$BRIEF" --arg o "$T/briefs/other.md" '{"briefs:worker": $p, "briefs:other": $o}')"
gate; eq "  ... with two briefs named, one taken, the other is listed" "1 brief-unread other" "$G"
seed "$(record "$told_both")"
host_names "$(jq -nc --arg p "$T/briefs/missing.md" '{"briefs:gone": $p}')"
gate; eq "  ... and a brief whose file can't be read raises no gap" "0 " "$G"
cmp -s <(printf '# Brief: lane\n\n## Decisions already made\n\n- Keep one lane per feature.\n') "$BRIEF" \
    && ok "  ... no read edited the brief" || bad "  ... no read edited the brief" "$(cat "$BRIEF")"

echo "== the schema =="
state_json "$(record "[$(row told worker-f2),$(row pending worker-f2)]")" >/dev/null 2>"$T/err"
[ $? -ne 0 ] && grep -q 'both told and pending' "$T/err" && ok "state-schema.jq refuses a worker both told and pending" \
    || bad "state-schema.jq refuses a worker both told and pending" "$(cat "$T/err")"
state_json "$(record "[$(row pending worker-f2),$(row pending worker-f2)]")" >/dev/null 2>"$T/err"
[ $? -ne 0 ] && grep -q 'pending twice' "$T/err" && ok "  ... and a worker pending twice" || bad "  ... and a worker pending twice" "$(cat "$T/err")"
state_json "$(record "[$(row pending plugin/worker)]")" >/dev/null 2>"$T/err"
[ $? -ne 0 ] && grep -q "shape of a path" "$T/err" && ok "  ... and a pending value that isn't a messaging address" || bad "  ... and a pending value that isn't a messaging address" "$(cat "$T/err")"
state_json "$(record "[$(row told worker-f2),$(row missing worker-f2)]")" >/dev/null 2>"$T/err"
[ $? -ne 0 ] && grep -q 'both told and missing' "$T/err" && ok "  ... and a worker both told and missing" || bad "  ... and a worker both told and missing" "$(cat "$T/err")"
state_json "$(record "[$(row pending worker-f2),$(row missing worker-f2)]")" >/dev/null 2>"$T/err"
[ $? -ne 0 ] && grep -q 'both pending and missing' "$T/err" && ok "  ... and a worker both pending and missing" || bad "  ... and a worker both pending and missing" "$(cat "$T/err")"
# A record whose Run key was written around the write core: the reader stops.
seed "$(record "[$(row told worker-f2)]")"
jq -c '. + [{key: "pending", value: "worker-f2", set_by: "lane-v1", set: "2026-09-26T08:00Z"}]' "$KOTO_STORE/context/$SR/record/run" > "$T/run.json" \
    && cp "$T/run.json" "$KOTO_STORE/context/$SR/record/run"
gate; eq "a stored record holding a worker both told and pending doesn't read back: the gate stops (10)" "10 " "$G"
eq "nothing in this suite reached GitHub" "" "$(calls)"

done_tests state-handover_test
