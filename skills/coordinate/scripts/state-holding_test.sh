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
# --strand only on a dispatched message-path holding, and --retire of a
# stranded one or of a merged one whose removed teardown teardown-pass.sh
# check confirms, never of a live leg-bound holding or a merged one the check
# doesn't confirm; and --retire of a holding torn down outside the run, merged
# or not, once the check's reason carries the removed marker, with an entry
# saying the teardown was not the run's own (shirabe#1196).
#
# Usage: bash skills/coordinate/scripts/state-holding_test.sh
set -uo pipefail
. "$(dirname "$0")/../../../scripts/lib/koto-test-guard.sh" || exit 1

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

echo "== a confirmed merge clears its Side effects merge row (shirabe#1824) =="
# The write that clears a holding's Pull request cell after a confirmed merge
# (the row reads merged: Verified head kept, cell blank) drops the Side
# effects merge row for that pull request at that head, one a takeover
# carried included. Every other row stays: a merge row at another head, for
# another pull request or repository, and a row of another action.
MERGE_ROW() { jq -nc --arg t "$1" --arg s "$2" --arg a "${3:-merge}" \
    '{action: $a, target: $t, verified_head: $s, attempted: "2026-09-26T09:58Z", how_to_confirm: "gh pr view 12 --repo acme/widgets --json mergeCommit"}'; }
LINKED=$(holding alpha "{\"verified_head\": \"$SHA_HEAD\"}")
SE_ALL=$(jq -nc --argjson a "$(MERGE_ROW acme/widgets#12 "$SHA_HEAD")" \
    --argjson u "$(MERGE_ROW 'merge of https://github.com/acme/widgets/pull/12' "$SHA_HEAD")" \
    --argjson o "$(MERGE_ROW acme/widgets#12 "$SHA_OTHER")" \
    --argjson p "$(MERGE_ROW acme/widgets#13 "$SHA_HEAD")" \
    --argjson g "$(MERGE_ROW acme/gadgets#12 "$SHA_HEAD")" \
    --argjson t "$(MERGE_ROW acme/widgets#12 "$SHA_HEAD" teardown)" '[$a, $u, $o, $p, $g, $t]')
seed "$(record_json roadmap plugin-system | jq -c --argjson h "$LINKED" --argjson se "$SE_ALL" '.holdings = [$h] | .side_effects = $se')"
holding alpha "{\"verified_head\": \"$SHA_HEAD\", \"pull_request\": \"\"}" > "$T/cleared.json"
hw --topic alpha --row-file "$T/cleared.json" >/dev/null 2>"$T/err"; eq "clearing the cell after a confirmed merge exits 0" 0 $?
eq "  ... the row is kept with its cell cleared" "alpha $SHA_HEAD " "$(live | jq -r '.holdings[0] | "\(.worker) \(.verified_head) \(.pull_request)"')"
eq "  ... and the merge rows for acme/widgets#12 at that head go, by o/r#n or URL" 0 \
    "$(live | jq --arg s "$SHA_HEAD" '[.side_effects[] | select(.action == "merge" and .verified_head == $s and (.target == "acme/widgets#12" or (.target | contains("widgets/pull/12"))))] | length')"
eq "  ... the rows at another head, for another pull request or repository, and of another action stay" \
    "merge acme/widgets#12 $SHA_OTHER|merge acme/widgets#13 $SHA_HEAD|merge acme/gadgets#12 $SHA_HEAD|teardown acme/widgets#12 $SHA_HEAD" \
    "$(live | jq -r '[.side_effects[] | "\(.action) \(.target) \(.verified_head)"] | join("|")')"
# Any other write leaves Side effects as it was: an update that keeps the
# link, and a merged row written again (no link to clear).
seed "$(record_json roadmap plugin-system | jq -c --argjson h "$LINKED" --argjson se "$SE_ALL" '.holdings = [$h] | .side_effects = $se')"
holding alpha "{\"verified_head\": \"$SHA_HEAD\", \"branch\": \"feat/y\"}" > "$T/kept.json"
hw --topic alpha --row-file "$T/kept.json" >/dev/null 2>"$T/err"; eq "an update that keeps the link exits 0" 0 $?
eq "  ... and drops no Side effects row" 6 "$(live | jq '.side_effects | length')"
seed "$(record_json roadmap plugin-system | jq -c --argjson h "$(cat "$T/cleared.json")" --argjson se "$SE_ALL" '.holdings = [$h] | .side_effects = $se')"
hw --topic alpha --row-file "$T/cleared.json" >/dev/null 2>"$T/err"; eq "a merged row written again exits 0" 0 $?
eq "  ... and drops no Side effects row" 6 "$(live | jq '.side_effects | length')"

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
: >"$KOTO_STORE/calls"
hw --topic alpha --retire >/dev/null 2>"$T/err"; eq "--retire removes a stranded row" 0 $?
eq "  ... and only it" "beta gamma" "$(live | jq -r '.holdings | map(.worker) | join(" ")')"
eq "  ... and abandons no request (shirabe#1833)" "" "$(grep 'request abandon-request' "$KOTO_STORE/calls")"
hw --strand >/dev/null 2>&1; eq "--strand without --topic is a usage error" 64 $?

echo "== retired after a removed teardown (shirabe#1593) =="
# A stand-in for teardown-pass.sh: it logs each call and answers its check
# with the exit code in $T/check.rc (0 confirmed, 1 not), the reason on stderr.
# When $T/check.msg holds a line, it prints that line on stdout, the way the
# real check prints its confirmed reason.
CHECK="$T/teardown-pass-check.sh"
cat >"$CHECK" <<'EOF'
#!/usr/bin/env bash
echo "$*" >>"$CHECK_LOG"
rc=$(cat "$CHECK_RC")
[ -s "$CHECK_MSG" ] && cat "$CHECK_MSG"
[ "$rc" = 0 ] || echo "teardown-pass: teardown-incomplete: niwa still lists the instance" >&2
exit "$rc"
EOF
chmod +x "$CHECK"
export CHECK_LOG="$T/check.log" CHECK_RC="$T/check.rc" CHECK_MSG="$T/check.msg"
: >"$CHECK_MSG"
hr() { STATE_HOLDING_TEARDOWN_PASS=$CHECK hw "$@"; }
MERGED='{"return_path": "leg req_9:work-on", "entry_point": "/shirabe:work-on", "verified_head": "3333333333333333333333333333333333333333", "pull_request": ""}'
seed "$(record_json roadmap plugin-system | jq -c --argjson a "$(holding alpha)" \
    --argjson b "$(holding beta '{"return_path": "leg req_8:work-on", "entry_point": "/shirabe:work-on"}')" \
    --argjson c "$(holding gamma "$MERGED")" '.holdings = [$a, $b, $c]')"
: >"$CHECK_LOG"
echo 0 >"$CHECK_RC"
SNAP=$(session_snapshot "$SR")
hr --topic beta --retire >/dev/null 2>"$T/err"; eq "--retire refuses a live leg-bound holding" 65 $?
eq "  ... and nothing was written" "$SNAP" "$(session_snapshot "$SR")"
# Its check is asked (an unmerged row may be one torn down outside the run,
# shirabe#1196), and confirms no removed teardown.
grep -q 'confirms no removed teardown' "$T/err" && ok "  ... and names the missing removed teardown" \
    || bad "  ... and names the missing removed teardown" "$(cat "$T/err")"
: >"$CHECK_LOG"
echo 1 >"$CHECK_RC"
hr --topic gamma --retire >/dev/null 2>"$T/err"; eq "--retire refuses a merged leg-bound holding with no confirmed removed teardown" 65 $?
grep -q 'niwa still lists the instance' "$T/err" && ok "  ... and says why" || bad "  ... and says why" "$(cat "$T/err")"
eq "  ... and nothing was written" "$SNAP" "$(session_snapshot "$SR")"
eq "  ... the check asked of its topic in the run's session" "check --session $SR --topic gamma" "$(head -1 "$CHECK_LOG")"
echo 0 >"$CHECK_RC"
W0=$(live | jq -r .written)
hr --topic gamma --retire >/dev/null 2>"$T/err"; rc=$?
[ "$rc" = 0 ] && ok "--retire removes a merged leg-bound holding whose teardown is confirmed" \
    || bad "--retire removes a merged leg-bound holding whose teardown is confirmed" "exit $rc: $(cat "$T/err")"
eq "  ... and only it" "alpha beta" "$(live | jq -r '.holdings | map(.worker) | join(" ")')"
# The record step after destroy waits for a newer written time (shirabe#1148):
# the retire's own write must carry one.
[ "$(live | jq -r .written)" != "$W0" ] && ok "  ... and the retire carries a new written time" \
    || bad "  ... and the retire carries a new written time" "still $W0"
eq "  ... the write goes to the session, nothing to GitHub" "" "$(gh_writes)"

echo "== retired after a teardown outside the run (shirabe#1196) =="
# A unit whose pull request a person merged outside the run's land path keeps
# a dispatched row that never reads as merged. Once the check confirms its
# removed teardown, the reason starting with the marker, the row goes and an
# entry says the teardown was not the run's own; without the marker, or
# unconfirmed, it stays.
OUTSIDE_ENTRY="retired after a teardown that was not this run's own: its instance and job were removed outside the run's teardown pass, which archived only what survived and removed nothing."
seed "$(record_json roadmap plugin-system | jq -c --argjson a "$(holding alpha)" \
    --argjson d "$(holding delta '{"return_path": "leg req_7:work-on", "entry_point": "/shirabe:work-on", "pull_request": "[#768](https://github.com/acme/widgets/pull/768)"}')" \
    --argjson g "$(holding gamma "$MERGED")" '.holdings = [$a, $d, $g]')"
: >"$CHECK_LOG"
: >"$CHECK_MSG"
SNAP=$(session_snapshot "$SR")
echo 1 >"$CHECK_RC"
hr --topic delta --retire >/dev/null 2>"$T/err"; eq "--retire refuses a dispatched holding whose teardown check doesn't confirm" 65 $?
grep -q 'niwa still lists the instance' "$T/err" && ok "  ... and says why" || bad "  ... and says why" "$(cat "$T/err")"
eq "  ... and nothing was written" "$SNAP" "$(session_snapshot "$SR")"
eq "  ... the check asked of its topic in the run's session" "check --session $SR --topic delta" "$(head -1 "$CHECK_LOG")"
echo 0 >"$CHECK_RC"
echo "teardown-pass: teardown-confirmed: the instance and the job are gone and the archive is whole" >"$CHECK_MSG"
hr --topic delta --retire >/dev/null 2>"$T/err"; eq "--retire refuses a dispatched holding whose confirmed teardown isn't a removed one" 65 $?
grep -q 'confirms no removed teardown' "$T/err" && ok "  ... and says why" || bad "  ... and says why" "$(cat "$T/err")"
eq "  ... and nothing was written" "$SNAP" "$(session_snapshot "$SR")"
echo "teardown-pass: teardown-confirmed: removed outside the run: the instance and the job were already gone, and the run's removed pass archived what survived; the archive is whole" >"$CHECK_MSG"
: >"$KOTO_STORE/calls"
hr --topic delta --retire >/dev/null 2>"$T/err"; rc=$?
[ "$rc" = 0 ] && ok "--retire removes a dispatched holding whose worker was torn down outside its own teardown pass" \
    || bad "--retire removes a dispatched holding whose worker was torn down outside its own teardown pass" "exit $rc: $(cat "$T/err")"
eq "  ... and only it" "alpha gamma" "$(live | jq -r '.holdings | map(.worker) | join(" ")')"
# A leg-bound row's request is abandoned, and the entry says the leg was
# released (shirabe#1833). It says nothing about a merge: this check's reason
# doesn't say nothing merged, and a row never marked merged may have merged
# outside the land path.
grep -q '^request abandon-request req_7 ' "$KOTO_STORE/calls" && ok "  ... and abandons its leg's request req_7" \
    || bad "  ... and abandons its leg's request req_7" "$(grep request "$KOTO_STORE/calls")"
eq "  ... and leaves an entry saying the teardown was not the run's own" \
    "entry|Holding delta (unit $(holding delta | jq -r .unit)) $OUTSIDE_ENTRY The retirement released its leg req_7:work-on." \
    "$(koto context get "$SR" record/entries/000001 | jq -r '"\(.kind)|\(.text)"')"
hr --topic gamma --retire >/dev/null 2>"$T/err"; rc=$?
[ "$rc" = 0 ] && ok "--retire removes a merged holding whose removed teardown outside the run is confirmed" \
    || bad "--retire removes a merged holding whose removed teardown outside the run is confirmed" "exit $rc: $(cat "$T/err")"
eq "  ... and only it" "alpha" "$(live | jq -r '.holdings | map(.worker) | join(" ")')"
grep -q '^request abandon-request req_9 ' "$KOTO_STORE/calls" && ok "  ... and abandons its leg's request req_9" \
    || bad "  ... and abandons its leg's request req_9" "$(grep request "$KOTO_STORE/calls")"
eq "  ... and leaves the same entry, with the leg released and no unmerged clause" \
    "entry|Holding gamma (unit $(holding gamma | jq -r .unit)) $OUTSIDE_ENTRY The retirement released its leg req_9:work-on." \
    "$(koto context get "$SR" record/entries/000002 | jq -r '"\(.kind)|\(.text)"')"
eq "  ... the writes go to the session, nothing to GitHub" "" "$(gh_writes)"
# An abandon that fails doesn't undo the retirement: the row still goes, the
# exit is 0, and stderr and the entry say how to release the leg by hand.
seed "$(record_json roadmap plugin-system | jq -c --argjson a "$(holding alpha)" \
    --argjson e "$(holding epsilon '{"return_path": "leg req_5:work-on", "entry_point": "/shirabe:work-on"}')" '.holdings = [$a, $e]')"
: >"$KOTO_STORE/calls"
KOTO_ABANDON_FAIL=1 hr --topic epsilon --retire >/dev/null 2>"$T/err"; rc=$?
eq "--retire whose leg's abandon fails still exits 0" 0 "$rc"
eq "  ... and the row is gone" "alpha" "$(live | jq -r '.holdings | map(.worker) | join(" ")')"
grep -q '^request abandon-request req_5 ' "$KOTO_STORE/calls" && ok "  ... and the abandon was asked" \
    || bad "  ... and the abandon was asked" "$(grep request "$KOTO_STORE/calls")"
grep -q '^state-holding: .*req_5' "$T/err" && ok "  ... and stderr names the request" || bad "  ... and stderr names the request" "$(cat "$T/err")"
eq "  ... and the entry says the release failed and how to finish it" \
    "entry|Holding epsilon (unit $(holding epsilon | jq -r .unit)) $OUTSIDE_ENTRY The release of its leg req_5:work-on failed; abandon it with koto request abandon-request req_5." \
    "$(koto context get "$SR" record/entries/000001 | jq -r '"\(.kind)|\(.text)"')"
: >"$CHECK_MSG"

echo "== retired after a unit that ended with no pull request (shirabe#1075) =="
# The run's own teardown pass tore the unit down, and its check confirms it
# with a reason that ends saying nothing of it merged and naming the handoff
# (a `pr none` verdict). The row goes, merged or not; a leg-bound one's
# request is abandoned with the handoff link in its rationale, and the entry
# says the unit ended with no pull request. A confirmed reason without the
# ending still retires only a merged row.
HLINK="https://github.com/acme/widgets/issues/591#issuecomment-1005"
NOPR_ENTRY="retired after its teardown pass: the unit ended with no pull request merged, and its handoff comment is on its issue."
seed "$(record_json roadmap plugin-system | jq -c --argjson a "$(holding alpha)" \
    --argjson z "$(holding zeta '{"return_path": "leg req_6:work-on", "entry_point": "/shirabe:work-on", "branch": ""}')" \
    --argjson e "$(holding eta '{"branch": ""}')" '.holdings = [$a, $z, $e]')"
SNAP=$(session_snapshot "$SR")
echo 0 >"$CHECK_RC"
echo "teardown-pass: teardown-confirmed: the instance and the job are gone and the archive is whole" >"$CHECK_MSG"
hr --topic zeta --retire >/dev/null 2>"$T/err"; eq "--retire refuses an unmerged holding whose confirmed teardown doesn't say nothing merged" 65 $?
eq "  ... and nothing was written" "$SNAP" "$(session_snapshot "$SR")"
echo "teardown-pass: teardown-confirmed: the instance and the job are gone and the archive is whole; no pull request of it merged; handoff $HLINK" >"$CHECK_MSG"
echo 1 >"$CHECK_RC"
hr --topic zeta --retire >/dev/null 2>"$T/err"; eq "--retire refuses one whose teardown isn't confirmed" 65 $?
eq "  ... and nothing was written" "$SNAP" "$(session_snapshot "$SR")"
echo 0 >"$CHECK_RC"
: >"$KOTO_STORE/calls"
hr --topic zeta --retire >/dev/null 2>"$T/err"; rc=$?
[ "$rc" = 0 ] && ok "--retire removes a leg-bound holding that ended with no pull request" \
    || bad "--retire removes a leg-bound holding that ended with no pull request" "exit $rc: $(cat "$T/err")"
eq "  ... and only it" "alpha eta" "$(live | jq -r '.holdings | map(.worker) | join(" ")')"
eq "  ... and abandons its leg's request with the handoff link as the rationale" \
    "request abandon-request req_6 --rationale zeta was retired after its unit ended with no pull request; handoff $HLINK" \
    "$(grep '^request abandon-request' "$KOTO_STORE/calls")"
eq "  ... and its entry says the unit ended with no pull request" \
    "entry|Holding zeta (unit $(holding zeta | jq -r .unit)) $NOPR_ENTRY The retirement released its leg req_6:work-on." \
    "$(koto context get "$SR" record/entries/000001 | jq -r '"\(.kind)|\(.text)"')"
: >"$KOTO_STORE/calls"
hr --topic eta --retire >/dev/null 2>"$T/err"; rc=$?
[ "$rc" = 0 ] && ok "--retire removes a message-path holding that ended with no pull request" \
    || bad "--retire removes a message-path holding that ended with no pull request" "exit $rc: $(cat "$T/err")"
eq "  ... abandoning nothing" "" "$(grep 'request abandon-request' "$KOTO_STORE/calls")"
eq "  ... with the entry alone" "entry|Holding eta (unit $(holding eta | jq -r .unit)) $NOPR_ENTRY" \
    "$(koto context get "$SR" record/entries/000002 | jq -r '"\(.kind)|\(.text)"')"
: >"$CHECK_MSG"

echo "== a dispatch-failed holding retired (shirabe#1612) =="
# A failed launch's row goes through --retire only when no worker exists for
# its topic: niwa lists no session for it, and no unfinished Claude job carries
# its session name. Either one found refuses it, and a listing that can't be
# read writes nothing. The runs start in a stand-in workspace root, with
# stand-ins for niwa's listing and the Claude job directory.
WS="$T/ws"
mkdir -p "$WS/.niwa" "$T/claude/jobs"
: >"$WS/.niwa/workspace.toml"
NIWA_OUT="$T/niwa-list.json" NIWA_FAIL="$T/niwa-fail"
cat >"$T/niwa-stand-in.sh" <<'EOF'
#!/usr/bin/env bash
[ -e "$NIWA_FAIL" ] && { echo "niwa: cannot read the instances" >&2; exit 1; }
cat "$NIWA_OUT"
EOF
chmod +x "$T/niwa-stand-in.sh"
hf() { (cd "$WS" && export NIWA="$T/niwa-stand-in.sh" NIWA_OUT NIWA_FAIL DC_CLAUDE_HOME="$T/claude" && hw "$@"); }
job() { mkdir -p "$T/claude/jobs/$1" && jq -nc --arg n "$2" --arg s "$3" '{name: $n, state: $s}' >"$T/claude/jobs/$1/state.json"; }
rawjob() { mkdir -p "$T/claude/jobs/$1" && printf '%s' "$2" >"$T/claude/jobs/$1/state.json"; }
nojob() { rm -rf "$T/claude/jobs/$1"; }
seed "$(record_json roadmap plugin-system | jq -c --argjson a "$(holding alpha)" --argjson d "$(holding delta '{"dispatch_status": "dispatch-failed"}')" \
    --argjson g "$(holding gamma '{"dispatch_status": "stranded"}')" '.holdings = [$a, $d, $g]')"
echo '[{"name": "tsuku+delta", "session_name": "delta-0123abcd", "path": "/ws/tsuku+delta"}]' >"$NIWA_OUT"
SNAP=$(session_snapshot "$SR")
hf --topic delta --strand >/dev/null 2>"$T/err"; eq "--strand still refuses a dispatch-failed holding" 65 $?
hf --topic delta --retire >/dev/null 2>"$T/err"; eq "--retire refuses a dispatch-failed holding while niwa lists its session" 65 $?
grep -q "niwa lists delta's session delta-0123abcd" "$T/err" && ok "  ... and says why" || bad "  ... and says why" "$(cat "$T/err")"
eq "  ... and nothing was written" "$SNAP" "$(session_snapshot "$SR")"
: >"$NIWA_FAIL"
hf --topic delta --retire >/dev/null 2>"$T/err"; eq "--retire of a dispatch-failed holding exits 2 when niwa's listing can't be read" 2 $?
eq "  ... and nothing was written" "$SNAP" "$(session_snapshot "$SR")"
rm -f "$NIWA_FAIL"
echo '[{"name": "tsuku+deltav2", "session_name": "deltav2-0123abcd", "path": "/ws/tsuku+deltav2"}]' >"$NIWA_OUT"
job 0a1b2c3d delta-89abcdef working
hf --topic delta --retire >/dev/null 2>"$T/err"; eq "--retire refuses a dispatch-failed holding while an unfinished job carries its session" 65 $?
grep -q 'Claude job 0a1b2c3d carries delta' "$T/err" && ok "  ... and says why" || bad "  ... and says why" "$(cat "$T/err")"
eq "  ... and nothing was written" "$SNAP" "$(session_snapshot "$SR")"
job 0a1b2c3d delta-89abcdef done
job 4e5f6a7b deltav2-0123abcd working
hf --topic delta --retire >/dev/null 2>"$T/err"; rc=$?
[ "$rc" = 0 ] && ok "--retire removes a dispatch-failed holding once no worker exists for it (a finished job, another topic's session)" \
    || bad "--retire removes a dispatch-failed holding once no worker exists for it (a finished job, another topic's session)" "exit $rc: $(cat "$T/err")"
eq "  ... and only it" "alpha gamma" "$(live | jq -r '.holdings | map(.worker) | join(" ")')"
eq "  ... and leaves an entry naming the topic" \
    "entry|Holding delta (unit $(holding delta | jq -r .unit)) retired: its dispatch failed, and no niwa session or unfinished Claude job exists for it." \
    "$(koto context get "$SR" record/entries/000001 | jq -r '"\(.kind)|\(.text)"')"
hw --topic gamma --retire >/dev/null 2>"$T/err"; eq "--retire of a stranded holding still writes no entry" 0 $?
koto context get "$SR" record/entries/000002 >/dev/null 2>&1; eq "  ... (no second entry)" 1 $?

echo "== a dispatch-failed holding's job check fails closed (shirabe#1612) =="
# Only done, stopped and failed count as finished, and a job state file whose
# name can't be read could be the topic's worker, so each one refuses.
seed "$(record_json roadmap plugin-system | jq -c --argjson d "$(holding delta '{"dispatch_status": "dispatch-failed"}')" '.holdings = [$d]')"
SNAP=$(session_snapshot "$SR")
job 0a1b2c3d delta-89abcdef idle
hf --topic delta --retire >/dev/null 2>"$T/err"; eq "--retire refuses a dispatch-failed holding while a job carrying its session is idle" 65 $?
eq "  ... and nothing was written" "$SNAP" "$(session_snapshot "$SR")"
job 0a1b2c3d delta-89abcdef done
rawjob 5c6d7e8f 'not json'
hf --topic delta --retire >/dev/null 2>"$T/err"; eq "--retire refuses a dispatch-failed holding while a job's state file isn't JSON" 65 $?
grep -q 'Claude job 5c6d7e8f has no readable name' "$T/err" && ok "  ... and says why" || bad "  ... and says why" "$(cat "$T/err")"
eq "  ... and nothing was written" "$SNAP" "$(session_snapshot "$SR")"
rawjob 5c6d7e8f '{"state": "working"}'
hf --topic delta --retire >/dev/null 2>"$T/err"; eq "--retire refuses a dispatch-failed holding while a job's state file has no name" 65 $?
eq "  ... and nothing was written" "$SNAP" "$(session_snapshot "$SR")"
nojob 5c6d7e8f

echo "== an unnamed job is ruled out by its own state, pid and cwd (shirabe#1937) =="
# niwa lists only deltav2's instance, at /ws/tsuku+deltav2. An unnamed job
# goes once its state file says it finished and its pid is gone, or once its
# cwd lies in an instance niwa lists for another session; any other refuses.
retire_seed() { seed "$(record_json roadmap plugin-system | jq -c --argjson d "$(holding delta '{"dispatch_status": "dispatch-failed"}')" '.holdings = [$d]')"; }
retire_seed
SNAP=$(session_snapshot "$SR")
rawjob 5c6d7e8f "{\"name\": null, \"state\": \"stopped\", \"pid\": $$}"
hf --topic delta --retire >/dev/null 2>"$T/err"; eq "--retire refuses while an unnamed job reads stopped but its pid is still running" 65 $?
grep -q 'Claude job 5c6d7e8f has no readable name' "$T/err" && ok "  ... and says why" || bad "  ... and says why" "$(cat "$T/err")"
eq "  ... and nothing was written" "$SNAP" "$(session_snapshot "$SR")"
rawjob 5c6d7e8f '{"name": null, "state": "working", "pid": null, "cwd": "/srv/elsewhere"}'
hf --topic delta --retire >/dev/null 2>"$T/err"; eq "--retire refuses while an unnamed working job's cwd is in no instance niwa lists" 65 $?
eq "  ... and nothing was written" "$SNAP" "$(session_snapshot "$SR")"
rawjob 5c6d7e8f '{"name": null, "state": "working", "pid": null, "cwd": "/ws/tsuku+deltav2x/public/shirabe"}'
hf --topic delta --retire >/dev/null 2>"$T/err"; eq "--retire refuses while an unnamed working job's cwd only shares a prefix with a listed instance" 65 $?
eq "  ... and nothing was written" "$SNAP" "$(session_snapshot "$SR")"
rawjob 5c6d7e8f '{"name": null, "state": "working", "pid": null, "cwd": "/ws/tsuku+deltav2/../tsuku+deltaother"}'
hf --topic delta --retire >/dev/null 2>"$T/err"; eq "--retire refuses while an unnamed working job's cwd climbs out of a listed instance" 65 $?
eq "  ... and nothing was written" "$SNAP" "$(session_snapshot "$SR")"
rawjob 5c6d7e8f '{"name": null, "state": "working", "pid": null, "cwd": 7}'
hf --topic delta --retire >/dev/null 2>"$T/err"; eq "--retire refuses while an unnamed working job's cwd isn't a path" 65 $?
eq "  ... and nothing was written" "$SNAP" "$(session_snapshot "$SR")"
nojob 5c6d7e8f
rawjob 31e9216f '{"name": null, "state": "stopped", "pid": null, "cwd": "/ws/tsuku+epsilon"}'
hf --topic delta --retire >/dev/null 2>"$T/err"; rc=$?
[ "$rc" = 0 ] && ok "--retire rules out an unnamed job that is stopped with no pid (the issue's job)" \
    || bad "--retire rules out an unnamed job that is stopped with no pid (the issue's job)" "exit $rc: $(cat "$T/err")"
eq "  ... and the holding is gone" "" "$(live | jq -r '.holdings | map(.worker) | join(" ")')"
nojob 31e9216f
retire_seed
rawjob 5c6d7e8f '{"state": "working", "cwd": "/ws/tsuku+deltav2/public/shirabe"}'
hf --topic delta --retire >/dev/null 2>"$T/err"; rc=$?
[ "$rc" = 0 ] && ok "--retire rules out an unnamed working job whose cwd is in another session's listed instance" \
    || bad "--retire rules out an unnamed working job whose cwd is in another session's listed instance" "exit $rc: $(cat "$T/err")"
retire_seed
rawjob 5c6d7e8f '{"state": "working", "cwd": "/ws/tsuku+deltav2"}'
hf --topic delta --retire >/dev/null 2>"$T/err"; rc=$?
[ "$rc" = 0 ] && ok "  ... and one whose cwd is that instance's root" \
    || bad "  ... and one whose cwd is that instance's root" "exit $rc: $(cat "$T/err")"
nojob 5c6d7e8f

echo "== a dispatch-failed holding retired through the session (shirabe#1612) =="
# Its own roadmap, so no other live run of the same record is in the way.
SF=coordinate-roadmap-retire-path-20260927T070000Z
seed_session "$SF" "$(record_json roadmap retire-path | jq -c --argjson d "$(holding delta '{"dispatch_status": "dispatch-failed"}')" '.holdings = [$d]')"
found_session "$SF" "$(roadmap_vars retire-path)"
(cd "$WS" && export NIWA="$T/niwa-stand-in.sh" NIWA_OUT NIWA_FAIL DC_CLAUDE_HOME="$T/claude" && bash "$H" --session "$SF" --topic delta --retire) >/dev/null 2>"$T/err"
eq "--retire through --session removes a dispatch-failed holding with no worker" 0 $?
eq "  ... and the row is gone" "" "$(session_state "$SF" | jq -r '.holdings | map(.worker) | join(" ")')"
eq "  ... and the session holds the entry" \
    "entry|Holding delta (unit $(holding delta | jq -r .unit)) retired: its dispatch failed, and no niwa session or unfinished Claude job exists for it." \
    "$(koto context get "$SF" record/entries/000001 | jq -r '"\(.kind)|\(.text)"')"

echo "== six leg-bound holdings whose workers were removed outside the run, nothing merged (shirabe#1833) =="
# A takeover carries six dispatched, leg-bound holdings whose workers were
# torn down outside the run before any pull request of theirs merged: no niwa
# instance, no Claude job, and the worker's koto session long idle. Two are
# scope legs, three work-on legs and one a review-fix worker whose unit was
# reassigned. Each goes through the route the run has: the teardown hand-off
# seals its verdict (the real teardown-handoff.sh --seal, removed mode, no
# handoff link), then --retire asks the real teardown-pass.sh check. Each
# holding retires, its leg's request is abandoned, and its entry says the
# pull request had not merged and the leg was released. --strand of such a
# row still refuses. The plugin tree holds the real hand-off, pass and
# libraries; the hand-off's `read`, which needs the engine's capture and
# seals, is a stand-in that prints the verdict the seal stored, as read does
# for a ready one, and refuses as read does for a refused one.
TT="$(cd -P "$T" && pwd -P)/gone-workers"
TS="$TT/plugin/skills/coordinate/scripts"
TB="$TT/bin"
TW="$TT/ws"
mkdir -p "$TS" "$TB" "$TW/.niwa" "$TT/home" "$TT/claude" "$TT/koto-sessions"
: >"$TW/.niwa/workspace.toml"
: >"$TW/.niwa/instance.json"
cp "$HERE/teardown-pass.sh" "$HERE/dispatch-common.sh" "$HERE/archive-common.sh" "$TS/"
cp "$HERE/teardown-handoff.sh" "$TS/teardown-handoff.real.sh"
cat >"$TS/teardown-handoff.sh" <<'EOF'
#!/usr/bin/env bash
if [ "${1-}" = read ]; then
    [ "$(sed -n 1p "$TH_ST/ctx/teardown_handoff" 2>/dev/null)" = ready ] \
        || { echo "teardown-handoff: the teardown verdict is a refusal" >&2; exit 1; }
    sed 1d "$TH_ST/ctx/teardown_handoff"
    printf 'keyseal keyseal:7:%064d\n' 0
    exit 0
fi
exec bash "$(dirname "$0")/teardown-handoff.real.sh" "$@"
EOF
# The inventory answers absent (5): niwa lists no instance for the topic.
cat >"$TS/teardown-verdict.sh" <<'EOF'
#!/usr/bin/env bash
[ "$1" = read ] || exit 64
printf 'absent\ntopic %s\n' "$(cat "$TH_ST/topic")"
exit 5
EOF
# coord-log.sh: a file seal stores the file under ctx/<key>; a token seal is
# printed back sealed; the latest entry into teardown and its evidence,
# `teardown: removed` with no handoff link.
cat >"$TS/coord-log.sh" <<'EOF'
#!/usr/bin/env bash
cmd="$1"; shift
A_file="" A_key="" A_token=""
while [ $# -gt 0 ]; do
    case "$1" in
        --session|--name|--where|--state|--after) shift 2 ;;
        --key) A_key=$2; shift 2 ;;
        --file) A_file=$2; shift 2 ;;
        --token) A_token=$2; shift 2 ;;
        *) exit 64 ;;
    esac
done
case "$cmd" in
    seal)
        if [ -n "$A_file" ]; then
            cp "$A_file" "$TH_ST/ctx/$A_key"
            printf 'sealed:7:%064d\n' 0
        else
            printf '%s sealed:8:%064d\n' "$A_token" 0
        fi ;;
    capture) printf 'sealed:6:%064d\n' 0 ;;
    entry) echo "4 wait" ;;
    evidence) printf '{"seq":5,"timestamp":"t","fields":{"teardown":"removed"}}\n' ;;
    *) exit 64 ;;
esac
EOF
# The hand-off's record read: the holding's row.
cat >"$TS/state-holding.sh" <<'EOF'
#!/usr/bin/env bash
cat "$TH_ST/row.json"
EOF
# niwa and Claude Code list nothing, and GitHub lists no merged pull request
# from any of the branches.
printf '#!/usr/bin/env bash\n[ "$1" = list ] && { echo "[]"; exit 0; }\nexit 64\n' >"$TB/niwa"
printf '#!/usr/bin/env bash\n[ "$1" = agents ] && { echo "[]"; exit 0; }\nexit 64\n' >"$TB/claude"
printf '#!/usr/bin/env bash\n[ "$1 $2" = "pr list" ] && { echo "[]"; exit 0; }\nexit 64\n' >"$TB/gh"
chmod +x "$TS"/*.sh "$TB"/*
export TH_ST="$TT/state"
mkdir -p "$TH_ST/ctx"
gone_env() { export NIWA="$TB/niwa" CLAUDE_CLI="$TB/claude" GH="$TB/gh" HOME="$TT/home" \
    TEARDOWN_CLAUDE_HOME="$TT/claude" TEARDOWN_KOTO_SESSIONS="$TT/koto-sessions" TH_ST; }
# gone <topic> <request> <leg> <entry point> <unit> <pull request cell>: one
# dispatched leg-bound holding, its worker's instance path recorded by its
# koto session, which last moved long ago.
GONE_ROWS="[]"
gone() {
    local inst="$TW/tsuku+$1-1a2b3c4d" row
    row=$(holding "$1" "$(jq -nc --arg rp "leg $2:$3" --arg ep "$4" --arg u "$5" --arg pr "$6" --arg b "feat/$1" \
        '{return_path: $rp, entry_point: $ep, unit: $u, pull_request: $pr, branch: $b}')")
    GONE_ROWS=$(jq -c --argjson r "$row" '. + [$r]' <<<"$GONE_ROWS")
    mkdir -p "$TT/koto-sessions/wk-$1"
    printf '{"schema_version":1,"workflow":"wk-%s","execution_dir":"%s/public/shirabe"}\n{"seq":1}\n{"seq":2,"timestamp":"2026-09-20T09:00:00.000Z","type":"transitioned"}\n' \
        "$1" "$inst" >"$TT/koto-sessions/wk-$1/koto-wk-$1.state.jsonl"
}
gone scopeauth req_21 scope /shirabe:scope "Feature 4" ""
gone scopecache req_22 scope /shirabe:scope "Feature 5" ""
gone workdocs req_23 work-on /shirabe:work-on "Feature 6" "[#801](https://github.com/acme/widgets/pull/801)"
gone workindex req_24 work-on /shirabe:work-on "Feature 7" "[#802](https://github.com/acme/widgets/pull/802)"
gone worksearch req_25 work-on /shirabe:work-on "Feature 8" ""
gone reviewfix req_26 work-on /shirabe:work-on "Feature 9" "[#803](https://github.com/acme/widgets/pull/803)"
seed "$(record_json roadmap plugin-system | jq -c --argjson g "$GONE_ROWS" '.holdings = $g')"
: >"$KOTO_STORE/calls"
(cd "$TW" && gone_env && hw --topic scopeauth --strand) >/dev/null 2>"$T/err"
eq "--strand still refuses a leg-bound holding whose worker is gone" 65 $?
N=0
for topic in scopeauth scopecache workdocs workindex worksearch reviewfix; do
    N=$((N + 1))
    REQ=$(jq -r --arg t "$topic" '.[] | select(.worker == $t) | .return_path' <<<"$GONE_ROWS")
    REQ=${REQ#leg }
    printf '%s' "$topic" >"$TH_ST/topic"
    jq -c --arg t "$topic" '.[] | select(.worker == $t)' <<<"$GONE_ROWS" >"$TH_ST/row.json"
    rm -f "$TH_ST/ctx/teardown_handoff"
    printf '%s' "$topic" | koto context add "$SR" teardown_topic
    SEAL=$(cd "$TW" && gone_env && bash "$TS/teardown-handoff.sh" --seal --session "$SR" 2>"$T/seal.err")
    case "$SEAL" in "handoff-ready keyseal:"*) ok "$topic: the hand-off seals a ready verdict" ;;
        *) bad "$topic: the hand-off seals a ready verdict" "$SEAL $(sed -n 2p "$TH_ST/ctx/teardown_handoff" 2>/dev/null) $(cat "$T/seal.err")" ;; esac
    (cd "$TW" && gone_env && STATE_HOLDING_TEARDOWN_PASS="$TS/teardown-pass.sh" hw --topic "$topic" --retire) >/dev/null 2>"$T/err"
    rc=$?
    [ "$rc" = 0 ] && ok "$topic: --retire ends the holding of a worker removed outside the run, nothing merged" \
        || bad "$topic: --retire ends the holding of a worker removed outside the run, nothing merged" "exit $rc: $(cat "$T/err")"
    live | jq -e --arg t "$topic" '.holdings | any(.worker == $t) | not' >/dev/null \
        && ok "  ... and its row is gone" || bad "  ... and its row is gone" "$(live | jq -c '.holdings | map(.worker)')"
    grep -q "^request abandon-request ${REQ%%:*} " "$KOTO_STORE/calls" && ok "  ... and its leg's request ${REQ%%:*} is abandoned" \
        || bad "  ... and its leg's request ${REQ%%:*} is abandoned" "$(grep request "$KOTO_STORE/calls")"
    ENTRY=$(koto context get "$SR" "record/entries/$(printf '%06d' "$N")" 2>/dev/null | jq -r '.text // ""')
    case "$ENTRY" in *"Holding $topic "*"had not merged"*"released its leg $REQ"*) ok "  ... and its entry says what was found and that the leg was released" ;;
        *) bad "  ... and its entry says what was found and that the leg was released" "[$ENTRY]" ;; esac
done
eq "  ... every one of the six is gone" "" "$(live | jq -r '.holdings | map(.worker) | join(" ")')"
eq "  ... and nothing is written on GitHub" "" "$(gh_writes)"

done_tests state-holding
