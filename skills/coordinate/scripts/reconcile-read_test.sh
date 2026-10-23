#!/usr/bin/env bash
# reconcile-read_test.sh -- reconcile-read.sh reads the run's record from its
# koto session, and at discipline scope the previous rotation's reasoning from
# the predecessor's session, through the record feature's parser, and refuses
# with a distinct exit for no found record and a failed read.
#
# Covers: a roadmap record read with each row sourced to the record, its
# Written: time, no import and no reasoning, nothing read on GitHub; the
# escalated Decisions entries carried with question, recommendation, reason
# and target, a proposed one not; an imported record's host facts as its
# import, and none without a source session; refusals: a run that found no
# record (3), a session whose record is gone, another scope's record, a key
# that isn't a record, host facts that aren't an object, and a read past the
# deadline (5, the reason saying it timed out); at discipline scope the
# predecessor's reasoning present (and written to --reasoning-out), not
# recorded (empty, or never written), absent with no predecessor or no
# record/rotation, a stale --reasoning-out removed, and a record/rotation that
# isn't a window failed; the override flags with RS_SESSION, and without it;
# usage errors.
#
# Usage: bash skills/coordinate/scripts/reconcile-read_test.sh
set -uo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
command -v jq >/dev/null 2>&1 || { echo "SKIP: jq not on PATH"; exit 0; }
. "$HERE/testdata/test-lib.sh"
RR="$HERE/reconcile-read.sh"

R=acme/widgets
SHA=0123456789abcdef0123456789abcdef01234567
HOLD=$(holding plugin-registry "{\"verified_head\": \"$SHA\"}")
DEF='{"deferral":"flaky test","reason":"not now","raised":"2026-09-25T10:00Z","disposition":""}'
SIDE="{\"action\":\"merge\",\"target\":\"#12\",\"verified_head\":\"$SHA\",\"attempted\":\"2026-09-26T11:02Z\",\"how_to_confirm\":\"compare blobs on main\"}"
ROADMAP=$(record_json roadmap plugin-system | jq -c --argjson h "$HOLD" --argjson d "$DEF" --argjson s "$SIDE" \
    '.holdings = [$h] | .deferrals = [$d] | .side_effects = [$s]')
DISC=$(printf '%s' "$ROADMAP" | jq -c '.scope = {kind: "discipline", name: "ci-health"}')

N=0
# run_at <vars-json> [record-json]: a fresh run that found its record, the
# record (when given) in its session, written 2026-09-26T12:00:00Z. Sets S.
run_at() {
    N=$((N + 1))
    S="coordinate-$(printf '%s' "$1" | jq -r 'if .SCOPE == "roadmap" then "roadmap-plugin-system" else "discipline-ci-health" end')-20260926T12$(printf %02d "$N")00Z"
    found_session "$S" "$1"
    [ -z "${2-}" ] || seed_session "$S" "$2" 2026-09-26T12:00:00Z
}
OUT= RC=0
read_rec() { OUT=$(bash "$RR" "$@" 2>"$T/err"); RC=$?; }
expect() { # expect <label> <jq predicate> [exit]
    if [ "$RC" = "${3:-0}" ] && printf '%s' "$OUT" | jq -e "$2" >/dev/null 2>&1; then ok "$1"
    else bad "$1" "exit $RC: $OUT $(cat "$T/err")"; fi
}

echo "== the run's record =="
db_init
run_at "$(roadmap_vars plugin-system)" "$ROADMAP"
reset_calls
read_rec --session "$S"
expect "a roadmap record is read from the run's session, each row sourced to the record" \
    '.status == "found" and .scope == {kind: "roadmap", name: "plugin-system", repo: "acme/widgets"} and .record.written == "2026-09-26T12:00:00Z" and .record.source == "record" and .record.handoff_date == null and .record.import == null and .holdings[0].source == "record" and .deferrals[0].row.deferral == "flaky test" and .side_effects[0].row.action == "merge" and .unparseable == [] and .reasoning == null and .decisions == []'
eq "  ... the rows as the record holds them" "$(jq -nc --argjson h "$HOLD" --argjson d "$DEF" --argjson s "$SIDE" '[$h, $d, $s]')" \
    "$(printf '%s' "$OUT" | jq -c '[.holdings[0].row, .deferrals[0].row, .side_effects[0].row]')"
eq "  ... and nothing read on GitHub" "" "$(calls)"
FOUND=$S

S="coordinate-roadmap-plugin-system-20260926T130000Z"
log_new "$S" "$(roadmap_vars plugin-system)"
read_rec --session "$S"
expect "a run that found no record is refused as none" '.status == "none"' 3

run_at "$(roadmap_vars plugin-system)"
read_rec --session "$S"
expect "a session whose record is gone is a failed read" '.status == "failed" and (.reason | test("could not be read"))' 5

run_at "$(roadmap_vars plugin-system)" "$(record_json roadmap other-system)"
read_rec --session "$S"
if [ "$RC" -ne 0 ] && printf '%s' "$OUT" | jq -e '.status == "failed" or .status == "unreadable"' >/dev/null 2>&1; then
    ok "another scope's record is refused"; else bad "another scope's record is refused" "exit $RC: $OUT"; fi

run_at "$(roadmap_vars plugin-system)" "$ROADMAP"
printf '"not a record"' | koto context add "$S" record/holdings
read_rec --session "$S"
if [ "$RC" -ne 0 ] && printf '%s' "$OUT" | jq -e '.status != "found"' >/dev/null 2>&1; then
    ok "a key that isn't a record is refused"; else bad "a key that isn't a record is refused" "exit $RC: $OUT"; fi

# A koto whose reads take three seconds, against a one-second deadline.
mkdir -p "$T/slow"
printf '#!/bin/sh\ncase "$1 $2" in "context get"|"context list") sleep 3 ;; esac\nexec "%s/testdata/koto" "$@"\n' "$HERE" > "$T/slow/koto"
chmod +x "$T/slow/koto"
OUT=$(PATH="$T/slow:$PATH" RECONCILE_READ_DEADLINE=1 bash "$RR" --session "$FOUND" 2>"$T/err"); RC=$?
expect "a read past the deadline is a failed read, saying it timed out" '.status == "failed" and (.reason | test("timed out"))' 5

echo "== decisions and imports =="
ESC='{"decision":"3","round":"1","question":"Ship before the release?","options":"ship -- now\nwait -- later","state":"escalated","source":"self [20260926T080000Z raise 2]","verdict":"escalate","recommendation":"wait","reason":"the release is Friday","context":"c","problem":"p","grounds":"scope","target":"a person","owed":"","asked":"2026-09-26T09:00Z","updated":"2026-09-26T09:00Z"}'
PROP='{"decision":"4","round":"0","question":"Pin it?","options":"pin -- a\nfloat -- b","state":"proposed","source":"self [20260926T080000Z raise 3]","updated":"2026-09-26T09:00Z"}'
run_at "$(roadmap_vars plugin-system)" "$(printf '%s' "$ROADMAP" | jq -c --argjson e "$ESC" --argjson p "$PROP" '.decisions = {next: 5, entries: [$e, $p]}')"
read_rec --session "$S"
expect "an escalated entry is carried with its question, recommendation, reason and target; a proposed one isn't" \
    '.status == "found" and .decisions == [{decision: "3", question: "Ship before the release?", recommendation: "wait", reason: "the release is Friday", target: "a person"}]'
jq -nc '{source_workspace: "ws-old", source_session: "coordinate-roadmap-plugin-system-20260901T000000Z", template_hash: "abc123"}' \
    | koto context add "$S" record/host
read_rec --session "$S"
expect "an imported record carries its host facts as its import" \
    '.record.import == {source_workspace: "ws-old", source_session: "coordinate-roadmap-plugin-system-20260901T000000Z", template_hash: "abc123"}'
printf '{"host":"this one"}' | koto context add "$S" record/host
read_rec --session "$S"
expect "host facts with no source session are no import" '.status == "found" and .record.import == null'
printf '"a string"' | koto context add "$S" record/host
read_rec --session "$S"
expect "host facts that aren't an object are a failed read" '.status == "failed"' 5

echo "== discipline scope: the predecessor's reasoning =="
PRED=coordinate-discipline-ci-health-20260919T080000Z
seed_session "$PRED" "$DISC"
rotation() { # rotation [predecessor]: this rotation's window
    jq -nc --arg p "${1-}" '{start: "2026-09-26", end: "2026-10-03", host_repo: "acme/widgets"} + (if $p == "" then {} else {predecessor: $p} end)' \
        | koto context add "$S" record/rotation
}
run_at "$(discipline_vars ci-health)" "$DISC"
rotation "$PRED"
printf '"The flaky job is timing."' | koto context add "$PRED" record/reasoning
read_rec --session "$S" --reasoning-out "$T/reasoning.txt"
expect "a discipline record is read with the predecessor's reasoning present" \
    '.status == "found" and .scope.kind == "discipline" and .reasoning == "present" and (.holdings | length) == 1'
eq "  ... written verbatim to --reasoning-out" "The flaky job is timing." "$(cat "$T/reasoning.txt" 2>/dev/null)"
printf '"  "' | koto context add "$PRED" record/reasoning
read_rec --session "$S" --reasoning-out "$T/reasoning.txt"
expect "an empty reasoning is not recorded" '.reasoning == "not_recorded"'
[ -e "$T/reasoning.txt" ] && bad "  ... and the stale --reasoning-out is removed" "$(cat "$T/reasoning.txt")" || ok "  ... and the stale --reasoning-out is removed"
rm -f "$KOTO_STORE/context/$PRED/record/reasoning"
read_rec --session "$S"
expect "a predecessor that never wrote its reasoning is not recorded" '.reasoning == "not_recorded"'
rotation
read_rec --session "$S"
expect "a rotation that names no predecessor: reasoning absent" '.status == "found" and .reasoning == "absent"'
rm -f "$KOTO_STORE/context/$S/record/rotation"
read_rec --session "$S"
expect "a record with no record/rotation: reasoning absent" '.status == "found" and .reasoning == "absent"'
printf '"soon"' | koto context add "$S" record/rotation
read_rec --session "$S"
expect "a record/rotation that isn't a window is a failed read" '.status == "failed" and (.reason | test("record/rotation"))' 5
eq "no discipline read touched GitHub" "" "$(calls)"

echo "== the override flags and usage =="
OUT=$(RS_SESSION="$FOUND" bash "$RR" --scope roadmap --name plugin-system --repo "$R" 2>"$T/err"); RC=$?
expect "the override flags read the record from RS_SESSION" '.status == "found" and (.holdings | length) == 1 and .record.import == null'
OUT=$(env -u RS_SESSION bash "$RR" --scope roadmap --name plugin-system --repo "$R" 2>"$T/err"); RC=$?
expect "the override flags with no RS_SESSION are a failed read" '.status == "failed" and (.reason | test("no session"))' 5
bash "$RR" >/dev/null 2>&1; eq "no arguments is a usage error" 64 $?
bash "$RR" --session "$FOUND" --scope roadmap --name plugin-system --repo "$R" >/dev/null 2>&1; eq "--session with the override flags is a usage error" 64 $?
bash "$RR" --scope roadmap --name plugin-system >/dev/null 2>&1; eq "part of the override flags is a usage error" 64 $?
bash "$RR" --session "$FOUND" --ref 40 >/dev/null 2>&1; eq "--ref is a usage error" 64 $?
bash "$RR" --session >/dev/null 2>&1; eq "a flag without its value is a usage error" 64 $?

done_tests reconcile-read
