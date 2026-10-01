#!/usr/bin/env bash
# quiet-check_test.sh -- quiet-check.sh counts each worker's silent checks
# from the session log and never tears anything down.
#
# Covers: no worker quiet inside 30 minutes of the run start; first silence
# for every holding quiet 30 minutes; a sweep within 30 minutes of the last
# silent check not counting again; second silence after it, winning over a
# first silence in the same sweep and naming only the topics with two; a
# report (a `wait` report event naming the unit), a push (the pull request's
# head commit date) and a dispatch each resetting a worker's count; a QUIET
# capture whose seal fails not counted; space-separated topic lists and every
# token in koto's capture alphabet; the sealed token and coord/quiet.json; a
# failed read (2); no GitHub write and no teardown.
#
# Usage: bash skills/coordinate/scripts/quiet-check_test.sh
set -uo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
command -v jq >/dev/null 2>&1 || { echo "SKIP: jq not on PATH"; exit 0; }
. "$HERE/testdata/test-lib.sh"
QC="$HERE/quiet-check.sh"
CL="$HERE/coord-log.sh"
tok_shape() {
    local re='^[A-Za-z0-9 :/_.@-]*$'
    if [[ ${2% sealed:*} =~ $re ]]; then ok "$1"; else bad "$1" "[$2]"; fi
}
ITITLE="Coordinator record: ROADMAP-plugin-system"
HOLDINGS=$(jq -nc --argjson a "$(holding alpha '{"pull_request": "[#12](https://github.com/acme/widgets/pull/12)"}')" \
    --argjson b "$(holding beta '{"pull_request": ""}')" '[$a, $b]')
seed() {
    db_init
    db '.issues += [{repo: "acme/widgets", number: 7, title: $t, body: $b, state: "open", author: "alice", editor: null}]
        | .prs += [{repo: "acme/widgets", number: 12, title: "w", body: "", state: "OPEN", isDraft: true, isCrossRepository: false,
                    baseRefName: "main", headRefName: "feat/x", headRefOid: $h, author: "alice", editor: null}]
        | .commits[$h] = {tree: "4444444444444444444444444444444444444444", date: "2026-09-26T07:00:00Z"}' \
        --arg t "$ITITLE" --arg b "$(render "$(record_json roadmap plugin-system | jq -c --argjson h "$HOLDINGS" '.holdings = $h')" issue)" \
        --arg h "$SHA_HEAD"
}
N=0
run() { # a fresh run at wait; the run starts 08:00
    N=$((N + 1))
    S="coordinate-roadmap-plugin-system-20260926T0800${N}Z"
    found_session "$S" "$(roadmap_vars plugin-system)" 7
    log_to "$S" reconcile wait 2026-09-26T08:02:00.000Z
}
sweep() { # sweep <HH:MM>: tick wait with quiet, run the check at that time, capture its token
    local ts="2026-09-26T$1:00.000Z"
    log_evidence "$S" wait '{"event":"quiet"}' "$ts"
    log_to "$S" wait quiet_check "$ts"
    OUT=$(bash "$QC" --session "$S" --now "2026-09-26T$1:00Z" 2>"$T/err")
    RC=$?
    TOK=${OUT% sealed:*}
    [ $RC -eq 0 ] && log_capture "$S" QUIET "$OUT" "$ts"
    log_to "$S" quiet_check wait "$ts"
}

echo "== silences =="
seed; run
sweep 08:20; eq "inside 30 minutes of the run start nobody is quiet" quiet-none "$TOK"
tok_shape "quiet-none is in koto's capture alphabet" "$OUT"
sweep 08:31; eq "30 minutes of silence is a first silence for each worker" "first-silence alpha beta" "$TOK"
tok_shape "first-silence, space-separated, is in koto's capture alphabet" "$OUT"
eq "the detail goes to coord/quiet.json" "alpha:true:0 beta:true:0" "$(jq -r '[.holdings[] | "\(.worker):\(.silent):\(.earlier_silent_checks)"] | join(" ")' "$KOTO_STORE/context/$S/coord/quiet.json")"
sweep 08:45; eq "a sweep within 30 minutes of the last silent check doesn't count again" quiet-none "$TOK"
sweep 09:02; eq "a second silent check is second-silence" "second-silence alpha beta" "$TOK"
tok_shape "second-silence is in koto's capture alphabet" "$OUT"

echo "== activity resets the count =="
seed; run
sweep 08:31; eq "first silence" "first-silence alpha beta" "$TOK"
log_evidence "$S" wait '{"event":"progress","unit":"beta","report":"checkpoint 1"}' 2026-09-26T08:40:00.000Z
log_to "$S" wait take_report 2026-09-26T08:40:00.000Z; log_to "$S" take_report wait 2026-09-26T08:40:00.000Z
sweep 09:02; eq "a progress report resets its worker too (shirabe#491)" "second-silence alpha" "$TOK"
seed; run
sweep 08:31; eq "first silence" "first-silence alpha beta" "$TOK"
log_evidence "$S" wait '{"event":"report","unit":"alpha"}' 2026-09-26T08:40:00.000Z
log_to "$S" wait report_facts 2026-09-26T08:40:00.000Z; log_to "$S" report_facts wait 2026-09-26T08:40:00.000Z
sweep 09:02; eq "a report resets its worker; the other is on its second" "second-silence beta" "$TOK"
sweep 09:11; eq "a reset worker is quiet again 30 minutes after its report" "first-silence alpha" "$TOK"
seed; run
sweep 08:31
db '.commits[$h].date = "2026-09-26T08:50:00Z"' --arg h "$SHA_HEAD"
sweep 09:05; eq "a push resets its worker" "second-silence beta" "$TOK"
seed; run
sweep 08:31
log_evidence "$S" dispatch '{"dispatched":"sent","topic":"beta"}' 2026-09-26T08:50:00.000Z
sweep 09:05; eq "a redispatch resets its worker" "second-silence alpha" "$TOK"
seed; run
log_capture "$S" QUIET "first-silence alpha beta sealed:3:0000000000000000000000000000000000000000000000000000000000000000" 2026-09-26T08:31:00.000Z
sweep 09:05; eq "a QUIET capture whose seal fails isn't a silent check" "first-silence alpha beta" "$TOK"

echo "== the sealed token, reads only =="
seed; run; reset_calls; : > "$KOTO_STORE/calls"
log_to "$S" wait quiet_check 2026-09-26T08:40:00.000Z
OUT=$(bash "$QC" --session "$S" --now 2026-09-26T08:40:00Z 2>"$T/err")
bash "$CL" check --session "$S" --state quiet_check --sealed "$OUT" && ok "the token is sealed to quiet_check" || bad "the token is sealed to quiet_check" "$OUT"
grep -q '^api --method GET repos/acme/widgets/commits/2222222222222222222222222222222222222222' "$GH_DB.calls" \
    && ok "the head commit's date is read" || bad "the head commit's date is read" "$(calls)"
grep -qE 'PUT|POST|DELETE|edit|close|ready|merge' "$GH_DB.calls" && bad "no GitHub write" "$(calls)" || ok "no GitHub write"
grep -qvE '^(session dir|context add .* coord/quiet.json|template compile)' "$KOTO_STORE/calls" \
    && bad "no koto call but reads and its own detail" "$(cat "$KOTO_STORE/calls")" || ok "no koto call but reads and its own detail"
db '.fail = [{match: "commits/", rc: 1, stderr: "gh: Server Error (HTTP 502)"}]'
bash "$QC" --session "$S" --now 2026-09-26T08:40:00Z >/dev/null 2>&1; eq "a failed read exits 2" 2 $?
bash "$QC" --session "$S" --now soon >/dev/null 2>&1; eq "a --now that isn't a time is a usage error" 64 $?
bash "$QC" --now 2026-09-26T08:40:00Z >/dev/null 2>&1; eq "no session is a usage error" 64 $?

done_tests quiet-check
