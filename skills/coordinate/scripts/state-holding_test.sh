#!/usr/bin/env bash
# state-holding_test.sh -- state-holding.sh, the one way a Holdings row
# changes: upsert by topic, read by topic, list in record order.
#
# Covers: a new topic appended; the same topic replaced rather than added
# twice; --read printing the row and exiting 1 when absent; --list in record
# order and [] for None.; a row whose worker isn't the topic, a row with a
# status column and a malformed row refused (65); a session holding another
# scope's record refused (10); filed and closed deferrals dropped only once the
# run has dispatched; the write going through state-write.sh into the run's
# session, with nothing written on GitHub, and its refusals (a directed
# transition in the run, 10); both scopes; a pushed head kept beside its row;
# --strand only on a dispatched message-path holding, and --retire only of a
# stranded one.
#
# Usage: bash skills/coordinate/scripts/state-holding_test.sh
set -uo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
command -v jq >/dev/null 2>&1 || { echo "SKIP: jq not on PATH"; exit 0; }
. "$HERE/testdata/test-lib.sh"
H="$HERE/state-holding.sh"

SR=coordinate-roadmap-plugin-system-20260926T070000Z
RM=(--scope roadmap --name plugin-system --repo "$REPO")
W_RM=("${RM[@]}" --skip-session-checks)
h() { RS_SESSION=$SR bash "$H" "${RM[@]}" "$@"; }      # a read, on the test record
hw() { RS_SESSION=$SR bash "$H" "${W_RM[@]}" "$@"; }   # a write, on the test record
seed() { db_init; seed_session "$SR" "$1"; } # seed <record-json>
live() { session_state "$SR"; }
gh_writes() { grep -E 'issue (create|edit|close)|pr (create|edit)|comment|--method (POST|PUT|PATCH|DELETE)' "$GH_DB.calls"; }

echo "== read and list =="
seed "$(record_json roadmap plugin-system)"
eq "--list on None. is []" "[]" "$(h --list 2>&1)"
h --topic alpha --read >/dev/null 2>&1; eq "--read with no row exits 1" 1 $?
seed "$(record_json roadmap plugin-system | jq -c --argjson a "$(holding zeta)" --argjson b "$(holding alpha)" --argjson c "$(holding mid)" '.holdings = [$a, $b, $c]')"
eq "--list keeps record order" "zeta alpha mid" "$(h --list | jq -r 'map(.worker) | join(" ")')"
eq "--read prints the topic's row as compact JSON" "$(holding alpha)" "$(h --topic alpha --read)"
h --topic beta --read >/dev/null 2>&1; eq "--read for an absent topic exits 1" 1 $?
eq "reads write nothing, and read nothing on GitHub" "" "$(calls)"
h --topic 'a/b' --read >/dev/null 2>&1; eq "a topic outside the worker grammar is a usage error" 64 $?
h --read >/dev/null 2>&1; eq "--read without --topic is a usage error" 64 $?
h --ref 7 --list >/dev/null 2>&1; eq "--ref is a usage error" 64 $?
seed_session "$SR" "$(record_json roadmap other)"
h --list >/dev/null 2>&1; eq "a session holding another scope's record is refused" 10 $?

echo "== write =="
seed "$(record_json roadmap plugin-system | jq -c --argjson a "$(holding alpha)" '.holdings = [$a]')"
holding beta > "$T/beta.json"
OUT=$(hw --topic beta --row-file "$T/beta.json" 2>"$T/err"); rc=$?
eq "a new topic's row is written" "0 $SR" "$rc $OUT"
eq "it is appended after the existing rows" "alpha beta" "$(live | jq -r '.holdings | map(.worker) | join(" ")')"
holding beta '{"verified_head": "2222222222222222222222222222222222222222", "branch": "feat/beta"}' > "$T/beta2.json"
hw --topic beta --row-file "$T/beta2.json" >/dev/null 2>"$T/err"; eq "an update exits 0" 0 $?
eq "the topic's row is replaced, not added twice" "alpha beta" "$(live | jq -r '.holdings | map(.worker) | join(" ")')"
eq "the replacement carries the new cells" "feat/beta $SHA_HEAD" "$(live | jq -r '.holdings[1] | "\(.branch) \(.verified_head)"')"
eq "the write goes to the session, nothing to GitHub" "" "$(gh_writes)"
[ "$(live | jq -r .written)" != 2026-09-26T09:00:00Z ] && ok "the write carries a new written time" || bad "the write carries a new written time"
hw --topic gamma --row-file "$T/beta.json" >/dev/null 2>"$T/err"; eq "a row whose worker isn't the topic is refused" 65 $?
holding beta '{"status": "open"}' > "$T/status.json"
hw --topic beta --row-file "$T/status.json" >/dev/null 2>"$T/err"; eq "a status column is refused" 65 $?
grep -q 'never recorded' "$T/err" && ok "the schema's reason reaches stderr" || bad "the schema's reason reaches stderr" "$(cat "$T/err")"
holding beta '{"phase": "planning"}' > "$T/phase.json"
hw --topic beta --row-file "$T/phase.json" >/dev/null 2>&1; eq "a malformed cell is refused" 65 $?
holding beta '{"repo": "acme/secret"}' > "$T/secret.json"
hw --topic beta --row-file "$T/secret.json" >/dev/null 2>&1; eq "a private repository from a public host is refused by state-write.sh" 65 $?
printf 'not json' > "$T/junk.json"
hw --topic beta --row-file "$T/junk.json" >/dev/null 2>&1; eq "a row file that isn't JSON is refused" 65 $?

echo "== deferrals and the session =="
DEFERRALS='[{"deferral":"a","reason":"r","raised":"2026-09-25T10:00Z","disposition":"filed #40"},
            {"deferral":"b","reason":"r","raised":"2026-09-25T10:00Z","disposition":"closed: moot"},
            {"deferral":"c","reason":"r","raised":"2026-09-25T10:00Z","disposition":"carried 2026-09-26T08:30Z: later"}]'
S=coordinate-roadmap-plugin-system-20260926T080000Z
db_init; seed_session "$S" "$(record_json roadmap plugin-system | jq -c --argjson d "$DEFERRALS" '.deferrals = $d')"
found_session "$S" "$(roadmap_vars plugin-system)"
slive() { session_state "$1"; }
bash "$H" --session "$S" --topic beta --row-file "$T/beta.json" >/dev/null 2>"$T/err"; eq "a session write exits 0" 0 $?
eq "before the first dispatch every deferral stays" "a b c" "$(slive "$S" | jq -r '.deferrals | map(.deferral) | join(" ")')"
log_to "$S" reconcile pick_facts; log_to "$S" pick_facts pick; log_to "$S" pick dispatch_check; log_to "$S" dispatch_check dispatch
bash "$H" --session "$S" --topic beta --row-file "$T/beta2.json" >/dev/null 2>"$T/err"; eq "a write after the first dispatch exits 0" 0 $?
eq "after it, filed and closed deferrals drop and carried stay" "c" "$(slive "$S" | jq -r '.deferrals | map(.deferral) | join(" ")')"
eq "the row still upserts" "beta" "$(slive "$S" | jq -r '.holdings | map(.worker) | join(" ")')"
eq "--read through the session" "feat/beta" "$(bash "$H" --session "$S" --topic beta --read | jq -r .branch)"
S2=coordinate-roadmap-plugin-system-20260926T090000Z
found_session "$S2" "$(roadmap_vars plugin-system)"
seed_session "$S2" "$(record_json roadmap plugin-system)"
log_end "$S"
bash "$H" --session "$S" --topic beta --row-file "$T/beta.json" >/dev/null 2>"$T/err"; eq "an ended run's session refuses the write" 10 $?
bash "$H" --session "$S2" --topic beta --row-file "$T/beta.json" >/dev/null 2>"$T/err"; eq "the live run's session writes" 0 $?
S=$S2
log_ev "$S" directed_transition '{"from":"dispatch","to":"wait"}'
bash "$H" --session "$S" --topic beta --row-file "$T/beta.json" >/dev/null 2>&1; eq "a directed transition in the run refuses the write" 10 $?
S3=coordinate-roadmap-plugin-system-20260926T100000Z
log_new "$S3" "$(roadmap_vars plugin-system)"
log_end "$S2"
seed_session "$S3" "$(record_json roadmap plugin-system)"
bash "$H" --session "$S3" --list >/dev/null 2>"$T/err"; eq "a run with no found record is refused" 10 $?

echo "== discipline scope =="
SD=coordinate-discipline-ci-health-20260926T070000Z
db_init; seed_session "$SD" "$(record_json discipline ci-health)"
DH=(--scope discipline --name ci-health --repo "$REPO")
RS_SESSION=$SD bash "$H" "${DH[@]}" --skip-session-checks --topic beta --row-file "$T/beta.json" >/dev/null 2>"$T/err"; eq "a discipline write exits 0" 0 $?
eq "the rotation's record holds the row" "beta" "$(RS_SESSION=$SD bash "$H" "${DH[@]}" --list | jq -r 'map(.worker) | join(" ")')"
eq "  ... and nothing is written on GitHub" "" "$(gh_writes)"

echo "== a pushed head (PRD R17) =="
SH=coordinate-roadmap-plugin-system-20260926T180000Z
HEAD1=1111111111111111111111111111111111111111
HEAD2=2222222222222222222222222222222222222222
REC=$(record_json roadmap plugin-system | jq -c --argjson a "$(holding alpha)" --argjson b "$(holding beta '{"unit": "Feature 3"}')" '.holdings = [$a, $b]')
db_init; seed_session "$SH" "$REC"
reset_calls
shw() { RS_SESSION=$SH bash "$H" "${W_RM[@]}" "$@"; }
shr() { RS_SESSION=$SH bash "$H" "${RM[@]}" "$@"; }
shw --topic alpha --pushed-head "$HEAD1" >/dev/null 2>"$T/err"; eq "--pushed-head sets alpha's head" 0 $?
eq "  ... --read prints it" "$HEAD1" "$(shr --topic alpha --read | jq -r .pushed_head)"
eq "  ... --list prints it beside its row only" "$HEAD1|null" "$(shr --list | jq -r 'map(.pushed_head) | map(tostring) | join("|")')"
eq "  ... and GitHub is never edited" "" "$(gh_writes)"
shr --topic beta --read | jq -c 'del(.pushed_head) | .pushed_head = $h' --arg h "$HEAD2" > "$T/beta-row.json"
shw --topic beta --row-file "$T/beta-row.json" >/dev/null 2>"$T/err"; eq "a row file may carry pushed_head" 0 $?
eq "  ... which lands beside the row, alpha's kept" "$HEAD1|$HEAD2" "$(koto context get "$SH" record/holdings | jq -r 'map(.pushed_head) | join("|")')"
shw --topic alpha --pushed-head nothex >/dev/null 2>"$T/err"; eq "a malformed head is refused" 65 $?
shw --topic gamma --pushed-head "$HEAD1" >/dev/null 2>"$T/err"; eq "a topic with no holding is refused" 65 $?

echo "== stranded (PRD R15; shirabe#732) =="
seed "$(record_json roadmap plugin-system | jq -c --argjson a "$(holding alpha)" --argjson b "$(holding beta '{"return_path": "leg req_1:deliver"}')" \
    --argjson c "$(holding gamma '{"dispatch_status": "dispatching"}')" '.holdings = [$a, $b, $c]')"
hw --topic beta --strand >/dev/null 2>"$T/err"; eq "--strand refuses a holding off the message path" 65 $?
grep -q 'only a holding on the message path is stranded' "$T/err" && ok "  ... and says why" || bad "  ... and says why" "$(cat "$T/err")"
hw --topic gamma --strand >/dev/null 2>"$T/err"; eq "--strand refuses a holding that isn't dispatched" 65 $?
hw --topic nobody --strand >/dev/null 2>"$T/err"; eq "--strand refuses a topic with no holding" 65 $?
SNAP=$(session_snapshot "$SR")
hw --topic alpha --retire >/dev/null 2>"$T/err"; eq "--retire refuses a holding that isn't stranded" 65 $?
eq "  ... and nothing was written" "$SNAP" "$(session_snapshot "$SR")"
hw --topic alpha --strand >/dev/null 2>"$T/err"; eq "--strand marks a message-path holding" 0 $?
eq "  ... stranded, the rest of the row as it was" "stranded message feat/x" "$(live | jq -r '.holdings[0] | "\(.dispatch_status) \(.return_path) \(.branch)"')"
hw --topic alpha --retire >/dev/null 2>"$T/err"; eq "--retire removes a stranded row" 0 $?
eq "  ... and only it" "beta gamma" "$(live | jq -r '.holdings | map(.worker) | join(" ")')"
hw --strand >/dev/null 2>&1; eq "--strand without --topic is a usage error" 64 $?

done_tests state-holding
