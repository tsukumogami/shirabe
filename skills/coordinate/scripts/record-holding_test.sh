#!/usr/bin/env bash
# record-holding_test.sh -- record-holding.sh, the one way a Holdings row
# changes: upsert by topic, read by topic, list in record order.
#
# Covers: a new topic appended; the same topic replaced rather than added
# twice; --read printing the row and exiting 1 when absent; --list in record
# order and [] for None.; a row whose worker isn't the topic, a row with a
# status column and a malformed row refused (65); a non-canonical live body
# refused (10); filed and closed deferrals dropped only once the run has
# dispatched; the write going through record-write.sh (a whole-body edit, no
# comment) and its refusals (a directed transition in the run, 10); both
# containers.
#
# Usage: bash skills/coordinate/scripts/record-holding_test.sh
set -uo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
command -v jq >/dev/null 2>&1 || { echo "SKIP: jq not on PATH"; exit 0; }
. "$HERE/testdata/test-lib.sh"
H="$HERE/record-holding.sh"

TITLE="Coordinator record: ROADMAP-plugin-system"
RM=(--scope roadmap --name plugin-system --repo "$REPO" --ref 7)
W_RM=("${RM[@]}" --skip-session-checks)
seed() { # seed <record-json>
    db_init
    db '.issues += [{repo: "acme/widgets", number: 7, title: $t, body: $b, state: "open", author: "alice", editor: null}]' \
        --arg t "$TITLE" --arg b "$(render "$1" issue 2026-09-26T08:00:00Z)"
}
live() { jq -r '.issues[] | select(.number == 7) | .body' "$GH_DB" | bash "$HERE/record-parse.sh"; }

echo "== read and list =="
seed "$(record_json roadmap plugin-system)"
eq "--list on None. is []" "[]" "$(bash "$H" "${RM[@]}" --list 2>&1)"
bash "$H" "${RM[@]}" --topic alpha --read >/dev/null 2>&1; eq "--read with no row exits 1" 1 $?
seed "$(record_json roadmap plugin-system | jq -c --argjson a "$(holding zeta)" --argjson b "$(holding alpha)" --argjson c "$(holding mid)" '.holdings = [$a, $b, $c]')"
eq "--list keeps record order" "zeta alpha mid" "$(bash "$H" "${RM[@]}" --list | jq -r 'map(.worker) | join(" ")')"
eq "--read prints the topic's row as compact JSON" "$(holding alpha)" "$(bash "$H" "${RM[@]}" --topic alpha --read)"
bash "$H" "${RM[@]}" --topic beta --read >/dev/null 2>&1; eq "--read for an absent topic exits 1" 1 $?
grep -qE 'edit|create|close' "$GH_DB.calls" && bad "reads write nothing" "$(calls)" || ok "reads write nothing"
bash "$H" "${RM[@]}" --topic 'a/b' --read >/dev/null 2>&1; eq "a topic outside the worker grammar is a usage error" 64 $?
bash "$H" "${RM[@]}" --read >/dev/null 2>&1; eq "--read without --topic is a usage error" 64 $?
db '.issues[0].body = (.issues[0].body + "\nstray")'
bash "$H" "${RM[@]}" --list >/dev/null 2>&1; eq "a non-canonical live body is refused" 10 $?

echo "== write =="
seed "$(record_json roadmap plugin-system | jq -c --argjson a "$(holding alpha)" '.holdings = [$a]')"
holding beta > "$T/beta.json"
OUT=$(bash "$H" "${W_RM[@]}" --topic beta --row-file "$T/beta.json" 2>"$T/err"); rc=$?
eq "a new topic's row is written" "0 https://github.com/acme/widgets/issues/7" "$rc $OUT"
eq "it is appended after the existing rows" "alpha beta" "$(live | jq -r '.holdings | map(.worker) | join(" ")')"
holding beta '{"verified_head": "2222222222222222222222222222222222222222", "branch": "feat/beta"}' > "$T/beta2.json"
bash "$H" "${W_RM[@]}" --topic beta --row-file "$T/beta2.json" >/dev/null 2>"$T/err"; eq "an update exits 0" 0 $?
eq "the topic's row is replaced, not added twice" "alpha beta" "$(live | jq -r '.holdings | map(.worker) | join(" ")')"
eq "the replacement carries the new cells" "feat/beta $SHA_HEAD" "$(live | jq -r '.holdings[1] | "\(.branch) \(.verified_head)"')"
grep -q '^issue edit 7' "$GH_DB.calls" && ! grep -q comment "$GH_DB.calls" && ok "the write is a whole-body edit, no comment" || bad "the write is a whole-body edit, no comment" "$(calls)"
[ "$(live | jq -r .written)" != 2026-09-26T08:00:00Z ] && ok "the write carries a new Written: time" || bad "the write carries a new Written: time"
bash "$H" "${W_RM[@]}" --topic gamma --row-file "$T/beta.json" >/dev/null 2>"$T/err"; eq "a row whose worker isn't the topic is refused" 65 $?
holding beta '{"status": "open"}' > "$T/status.json"
bash "$H" "${W_RM[@]}" --topic beta --row-file "$T/status.json" >/dev/null 2>"$T/err"; eq "a status column is refused" 65 $?
grep -q 'never recorded' "$T/err" && ok "the renderer's reason reaches stderr" || bad "the renderer's reason reaches stderr" "$(cat "$T/err")"
holding beta '{"phase": "planning"}' > "$T/phase.json"
bash "$H" "${W_RM[@]}" --topic beta --row-file "$T/phase.json" >/dev/null 2>&1; eq "a malformed cell is refused" 65 $?
holding beta '{"repo": "acme/secret"}' > "$T/secret.json"
bash "$H" "${W_RM[@]}" --topic beta --row-file "$T/secret.json" >/dev/null 2>&1; eq "a private repository from a public host is refused by record-write.sh" 65 $?
printf 'not json' > "$T/junk.json"
bash "$H" "${W_RM[@]}" --topic beta --row-file "$T/junk.json" >/dev/null 2>&1; eq "a row file that isn't JSON is refused" 65 $?

echo "== deferrals and the session =="
DEFERRALS='[{"deferral":"a","reason":"r","raised":"2026-09-25T10:00Z","disposition":"filed #40"},
            {"deferral":"b","reason":"r","raised":"2026-09-25T10:00Z","disposition":"closed: moot"},
            {"deferral":"c","reason":"r","raised":"2026-09-25T10:00Z","disposition":"carried 2026-09-26T08:30Z: later"}]'
seed "$(record_json roadmap plugin-system | jq -c --argjson d "$DEFERRALS" '.deferrals = $d')"
S=coordinate-plugin-system-20260926T080000Z
found_session "$S" "$(roadmap_vars plugin-system)" 7
bash "$H" --session "$S" --topic beta --row-file "$T/beta.json" >/dev/null 2>"$T/err"; eq "a session write exits 0" 0 $?
eq "before the first dispatch every deferral stays" "a b c" "$(live | jq -r '.deferrals | map(.deferral) | join(" ")')"
log_to "$S" reconcile pick_facts; log_to "$S" pick_facts pick; log_to "$S" pick dispatch_check; log_to "$S" dispatch_check dispatch
bash "$H" --session "$S" --topic beta --row-file "$T/beta2.json" >/dev/null 2>"$T/err"; eq "a write after the first dispatch exits 0" 0 $?
eq "after it, filed and closed deferrals drop and carried stay" "c" "$(live | jq -r '.deferrals | map(.deferral) | join(" ")')"
eq "the row still upserts" "beta" "$(live | jq -r '.holdings | map(.worker) | join(" ")')"
eq "--read through the session" "feat/beta" "$(bash "$H" --session "$S" --topic beta --read | jq -r .branch)"
log_ev "$S" directed_transition '{"from":"dispatch","to":"wait"}'
bash "$H" --session "$S" --topic beta --row-file "$T/beta.json" >/dev/null 2>&1; eq "a directed transition in the run refuses the write" 10 $?

echo "== discipline container =="
BR=coordinate/discipline-ci-health
db_init
db '.branches["acme/widgets"][$br] = $s | .prs += [{repo: "acme/widgets", number: 22, title: "docs(coordinate): ci-health rotation 2026-09-22 to 2026-09-29",
    body: $b, state: "OPEN", isDraft: true, isCrossRepository: false, baseRefName: "main", headRefName: $br, headRefOid: $s, author: "alice", editor: null}]' \
    --arg br "$BR" --arg s "$SHA_HEAD" --arg b "$(render "$(record_json discipline ci-health)" pr)"
DH=(--scope discipline --name ci-health --repo "$REPO" --ref 22)
bash "$H" "${DH[@]}" --skip-session-checks --topic beta --row-file "$T/beta.json" >/dev/null 2>"$T/err"; eq "a discipline write exits 0" 0 $?
eq "the pull request's body holds the row" "beta" "$(bash "$H" "${DH[@]}" --list | jq -r 'map(.worker) | join(" ")')"
grep -q '^pr edit 22' "$GH_DB.calls" && ok "the discipline write is a pr edit" || bad "the discipline write is a pr edit" "$(calls)"

done_tests record-holding
