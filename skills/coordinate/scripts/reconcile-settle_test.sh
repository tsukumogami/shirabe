#!/usr/bin/env bash
# reconcile-settle_test.sh -- reconcile-settle.sh, the one record write the
# reconcile pass makes, through the real record-holding.sh and record-write.sh
# against the gh and koto stand-ins.
#
# Covers: a row still dispatching is rewritten dispatched and nothing else in
# it changes; a row already dispatched, a row whose return path changed since
# the pass read it, and a topic with no row are left alone (settled false); a
# run that fails provenance is refused and reported not verified; a failed
# read is not verified; every fact is one JSON object on stdout, exit 0.
#
# Usage: bash skills/coordinate/scripts/reconcile-settle_test.sh
set -uo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
command -v jq >/dev/null 2>&1 || { echo "SKIP: jq not on PATH"; exit 0; }
. "$HERE/testdata/test-lib.sh"
ST="$HERE/reconcile-settle.sh"

TITLE="Coordinator record: ROADMAP-plugin-system"
seed() { # seed <holdings-json-array>
    db_init
    db '.issues += [{repo: "acme/widgets", number: 7, title: $t, body: $b, state: "open", author: "alice", editor: null}]' \
        --arg t "$TITLE" --arg b "$(render "$(record_json roadmap plugin-system | jq -c --argjson h "$1" '.holdings = $h')" issue 2026-09-26T08:00:00Z)"
}
live() { jq -r '.issues[] | select(.number == 7) | .body' "$GH_DB" | bash "$HERE/record-parse.sh"; }
stuck() { holding stuck '{"dispatch_status": "dispatching", "branch": "", "verified_head": "", "pull_request": ""}'; }
settle() { bash "$ST" --session "$S" --topic "${1:-stuck}" --return-path "${2:-message}" 2>/dev/null; }

S=coordinate-roadmap-plugin-system-20260926T080000Z
found_session "$S" "$(roadmap_vars plugin-system)" 7

echo "== settled =="
seed "[$(stuck), $(holding other)]"
OUT=$(settle); rc=$?
eq "a dispatching row is settled" "0 true" "$rc $(printf '%s' "$OUT" | jq -r '.settled')"
eq "the record now says dispatched" dispatched "$(live | jq -r '.holdings[] | select(.worker == "stuck") | .dispatch_status')"
eq "and nothing else in the row changed" "$(stuck | jq -c '.dispatch_status = "dispatched"')" "$(live | jq -c '.holdings[] | select(.worker == "stuck")')"
eq "the other holding is untouched" "$(holding other)" "$(live | jq -c '.holdings[] | select(.worker == "other")')"
grep -q '^issue edit 7' "$GH_DB.calls"; eq "the write is the record's own whole-body edit" 0 $?

echo "== left alone =="
reset_calls
OUT=$(settle); rc=$?
eq "a row already dispatched is not written again" "0 false" "$rc $(printf '%s' "$OUT" | jq -r '.settled')"
grep -q 'edit' "$GH_DB.calls" && bad "and nothing is edited" "$(calls)" || ok "and nothing is edited"
seed "[$(stuck)]"
OUT=$(settle stuck "leg req1:work-on"); rc=$?
eq "a row whose return path changed since the pass read it is left alone" "0 false" "$rc $(printf '%s' "$OUT" | jq -r '.settled')"
eq "it stays dispatching" dispatching "$(live | jq -r '.holdings[0].dispatch_status')"
OUT=$(settle nobody); rc=$?
eq "a topic with no row is left alone" "0 false" "$rc $(printf '%s' "$OUT" | jq -r '.settled')"

echo "== not verified =="
S2=coordinate-roadmap-plugin-system-20260926T090000Z
log_end "$S"
found_session "$S2" "$(roadmap_vars plugin-system)" 7 0badbeef
OUT=$(bash "$ST" --session "$S2" --topic stuck --return-path message 2>/dev/null); rc=$?
eq "a run that fails provenance is not verified, exit 0" "0 not_verified" "$rc $(printf '%s' "$OUT" | jq -r '.status')"
eq "it stays dispatching" dispatching "$(live | jq -r '.holdings[0].dispatch_status')"
log_end "$S2"
S=coordinate-roadmap-plugin-system-20260926T100000Z
found_session "$S" "$(roadmap_vars plugin-system)" 7
db '.fail = [{match: "issue view", rc: 1}]'
OUT=$(settle); rc=$?
eq "a failed read is not verified, exit 0" "0 not_verified" "$rc $(printf '%s' "$OUT" | jq -r '.status')"
[ "$(printf '%s\n' "$OUT" | wc -l | tr -d ' ')" = 1 ] && printf '%s' "$OUT" | jq -e '.kind == "settle"' >/dev/null
eq "every answer is one settle fact" 0 $?
bash "$ST" --session "$S" --topic stuck >/dev/null 2>&1; eq "a missing return path is a usage error" 64 $?

done_tests reconcile-settle
