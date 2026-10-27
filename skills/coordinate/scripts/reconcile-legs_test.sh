#!/usr/bin/env bash
# reconcile-legs_test.sh -- reconcile-legs.sh, the reconcile pass's write that
# gives a leg an end on a host whose request store doesn't hold it (PRD R15),
# through the real state-holding.sh and state-write.sh against the gh and
# koto stand-ins. dispatch-worker.sh --releg-imported is a stand-in here
# (dispatch-worker_test.sh covers it); the scripts run from a copy of the
# skills tree so it can stand beside them.
#
# Covers: a request this host holds is watched and nothing is written; a
# re-leg that succeeds is relegged with the new return path; one the re-leg
# refuses moves the holding to the message path and marks its leg key
# unwatchable (and makes no key for a holding without one); a re-leg that
# fails, or a request that can't be read, is not verified with nothing
# written; a holding no longer on that leg, or no longer dispatched, is left
# alone; every answer is one JSON fact, exit 0. The record is the run's
# session's.
#
# Usage: bash skills/coordinate/scripts/reconcile-legs_test.sh
set -uo pipefail
. "$(dirname "$0")/../../../scripts/lib/koto-test-guard.sh" || exit 1

HERE=$(cd "$(dirname "$0")" && pwd)
command -v jq >/dev/null 2>&1 || { echo "SKIP: jq not on PATH"; exit 0; }
. "$HERE/testdata/test-lib.sh"

# The skills tree, copied, with dispatch-worker.sh as a stand-in: RELEG_RC is
# its exit code, and on 0 it prints the new leg as the real one does.
cp -R "$(cd "$HERE/../.." && pwd -P)" "$T/skills"
SC="$T/skills/coordinate/scripts"
cat > "$SC/dispatch-worker.sh" <<'STUB'
#!/usr/bin/env bash
echo "dispatch-worker $*" >> "$KOTO_STORE/releg.calls"
case "${RELEG_RC:-0}" in
    0) printf 'leg=req_new:deliver\nchild=deliver-plugin-api\n' ;;
    9) echo "dispatch-worker: the child deliver-plugin-api of req_1:deliver isn't on this host: plugin-api can't be re-legged" >&2 ;;
    *) echo "dispatch-worker: koto request create failed for plugin-api" >&2 ;;
esac
exit "${RELEG_RC:-0}"
STUB
L="$SC/reconcile-legs.sh"

seed() { # seed <holdings-json-array>: the record, in the run's session
    db_init
    seed_session "$S" "$(record_json roadmap plugin-system | jq -c --argjson h "$1" '.holdings = $h')" 2026-09-26T08:00:00Z
}
live() { session_state "$S"; }
snap() { session_snapshot "$S"; }
legged() { holding plugin-api '{"return_path": "leg req_1:deliver", "entry_point": "deliver"}'; }
classify() { bash "$L" --session "$S" --topic "${1:-plugin-api}" --return-path "${2:-leg req_1:deliver}" 2>/dev/null; }
KEYDIR() { printf '%s/context/%s/legs/req_1' "$KOTO_STORE" "$S"; }
mkkey() {
    mkdir -p "$(KEYDIR)"
    jq -nc '{request: "req_1", leg: "deliver", topic: "plugin-api", state: "open", templates: ["deliver.md"], inputs: {TOPIC: "plugin-api"}}' > "$(KEYDIR)/deliver"
}
gone() { mkdir -p "$KOTO_STORE/requests"; : > "$KOTO_STORE/requests/req_1.gone"; }
held() { mkdir -p "$KOTO_STORE/requests"; rm -f "$KOTO_STORE/requests/req_1.gone"; echo '{"request_id":"req_1","legs":{"deliver":{"disposition":"open"}}}' > "$KOTO_STORE/requests/req_1.json"; }

# The run's plugin root is the copy, which the record writer's provenance
# check compares the scripts it runs from against.
S=coordinate-roadmap-plugin-system-20260926T080000Z
found_session "$S" "$(roadmap_vars plugin-system | jq -c --arg p "$T" '.PLUGIN_ROOT = $p')"

echo "== watched =="
seed "[$(legged)]"; mkkey; held
SNAP=$(snap)
OUT=$(classify); rc=$?
eq "a request this host holds is watched" "0 watched" "$rc $(printf '%s' "$OUT" | jq -r .outcome)"
eq "  ... and nothing is written" "$SNAP" "$(snap)"
[ -e "$KOTO_STORE/releg.calls" ] && bad "  ... and nothing is re-legged" "$(cat "$KOTO_STORE/releg.calls")" || ok "  ... and nothing is re-legged"

echo "== relegged =="
rm -f "$KOTO_STORE/requests/req_1.json"; gone
OUT=$(RELEG_RC=0 classify); rc=$?
eq "a worker whose session came along is re-legged" "0 relegged" "$rc $(printf '%s' "$OUT" | jq -r .outcome)"
eq "  ... naming the new return path" "leg req_new:deliver" "$(printf '%s' "$OUT" | jq -r .now)"
eq "  ... through dispatch-worker.sh --releg-imported" "dispatch-worker --session $S --releg-imported plugin-api" "$(cat "$KOTO_STORE/releg.calls")"

echo "== unwatchable =="
seed "[$(legged), $(holding other)]"; mkkey; gone
OUT=$(RELEG_RC=9 classify); rc=$?
eq "a worker the re-leg refuses is unwatchable" "0 unwatchable message" "$rc $(printf '%s' "$OUT" | jq -r '"\(.outcome) \(.now)"')"
eq "  ... and says why" "the child deliver-plugin-api of req_1:deliver isn't on this host: plugin-api can't be re-legged" "$(printf '%s' "$OUT" | jq -r .reason)"
eq "  ... the holding reports by message" message "$(live | jq -r '.holdings[] | select(.worker == "plugin-api") | .return_path')"
eq "  ... nothing else in it changed" "$(legged | jq -c '.return_path = "message"')" "$(live | jq -c '.holdings[] | select(.worker == "plugin-api")')"
eq "  ... the other holding is untouched" "$(holding other)" "$(live | jq -c '.holdings[] | select(.worker == "other")')"
eq "  ... and the leg key reads unwatchable" unwatchable "$(jq -r .state "$(KEYDIR)/deliver")"
seed "[$(legged)]"; mkkey; gone
jq -c '.state = "releg-pending" | .new_request = "req_8"' "$(KEYDIR)/deliver" > "$T/k" && mv "$T/k" "$(KEYDIR)/deliver"
OUT=$(RELEG_RC=9 classify); rc=$?
eq "a leg left pending by an earlier re-leg, refused now, is unwatchable" "0 unwatchable" "$rc $(printf '%s' "$OUT" | jq -r .outcome)"
grep -q '^request abandon-request req_8 ' "$KOTO_STORE/calls" && ok "  ... and its pending request is abandoned" || bad "  ... and its pending request is abandoned" "$(grep request "$KOTO_STORE/calls")"
eq "  ... and the key names no pending request" "unwatchable null" "$(jq -r '"\(.state) \(.new_request)"' "$(KEYDIR)/deliver")"
seed "[$(legged)]"; rm -rf "$(KEYDIR)"; gone
OUT=$(RELEG_RC=9 classify); rc=$?
eq "a holding dispatched before leg keys is unwatchable" "0 unwatchable" "$rc $(printf '%s' "$OUT" | jq -r .outcome)"
[ -e "$(KEYDIR)/deliver" ] && bad "  ... and no key is made for it" "" || ok "  ... and no key is made for it"

echo "== left alone =="
seed "[$(legged | jq -c '.return_path = "leg req_7:deliver"')]"; gone
SNAP=$(snap)
OUT=$(classify); rc=$?
eq "a holding no longer on the leg the pass read is left alone" "0 none" "$rc $(printf '%s' "$OUT" | jq -r .outcome)"
eq "  ... with nothing written" "$SNAP" "$(snap)"
seed "[$(legged | jq -c '.dispatch_status = "dispatching"')]"
SNAP=$(snap)
OUT=$(classify); rc=$?
eq "a holding no longer dispatched is left alone" "0 none" "$rc $(printf '%s' "$OUT" | jq -r .outcome)"
OUT=$(classify nobody); rc=$?
eq "a topic with no holding is left alone" "0 none" "$rc $(printf '%s' "$OUT" | jq -r .outcome)"
eq "  ... with nothing written" "$SNAP" "$(snap)"

echo "== not verified =="
seed "[$(legged)]"; mkkey; gone
SNAP=$(snap)
OUT=$(RELEG_RC=2 classify); rc=$?
eq "a re-leg that fails is not verified" "0 not_verified" "$rc $(printf '%s' "$OUT" | jq -r .status)"
eq "  ... with nothing written" "$SNAP" "$(snap)"
eq "  ... and the leg key as it was" open "$(jq -r .state "$(KEYDIR)/deliver")"
rm -f "$KOTO_STORE/requests/req_1.gone" "$KOTO_STORE/requests/req_1.json"
OUT=$(classify); rc=$?
eq "a request that can't be read is not verified" "0 not_verified" "$rc $(printf '%s' "$OUT" | jq -r .status)"
[ "$(printf '%s\n' "$OUT" | wc -l | tr -d ' ')" = 1 ] && printf '%s' "$OUT" | jq -e '.kind == "legs"' >/dev/null
eq "every answer is one legs fact" 0 $?
bash "$L" --session "$S" --topic plugin-api --return-path message >/dev/null 2>&1; eq "a message return path is a usage error" 64 $?

done_tests reconcile-legs
