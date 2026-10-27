#!/usr/bin/env bash
# closeout-read_test.sh -- closeout-read.sh reads a roadmap's close-out stage:
# the record in the coordinator's session, the roadmap on the default branch.
#
# Covers: a discipline rotation has no close-out to read (64; it ends at
# rotation_end). Roadmap: a verdict-owed Work row (before a milestone not
# Done, and with every milestone Done; its reason naming the milestone, its row
# the detail's blocker), one feature not Done, Shipped or Dropped, a missing
# roadmap, no features, holdings, side effects (a pending reopen named first),
# one undisposed deferral (carried or empty), an unsettled decision, and ready
# with every feature Done, Shipped or Dropped (an annotated `Done -- shipped in
# #12` and `Shipped (#34)` included) and a clear record; each token a bare
# word, no record number; the roadmap read from the default branch; the
# sealed token and coord/closeout.json naming the first blocker and the
# session; every token in koto's capture alphabet; the read writes nothing. On
# a roadmap/v3 roadmap an open `### Milestone N:` blocks, named in the detail
# with a reason that counts milestones, all Done or Dropped is ready, and a
# `## Features` section there lists none.
#
# Usage: bash skills/coordinate/scripts/closeout-read_test.sh
set -uo pipefail
. "$(dirname "$0")/../../../scripts/lib/koto-test-guard.sh" || exit 1

HERE=$(cd "$(dirname "$0")" && pwd)
command -v jq >/dev/null 2>&1 || { echo "SKIP: jq not on PATH"; exit 0; }
. "$HERE/testdata/test-lib.sh"
CR="$HERE/closeout-read.sh"
CL="$HERE/coord-log.sh"
tok_shape() {
    local re='^[A-Za-z0-9 :/_.@-]*$'
    if [[ ${2% sealed:*} =~ $re ]]; then ok "$1"; else bad "$1" "[$2]"; fi
}
file_at() { # file_at <ref> <path> <text>
    db '.files["acme/widgets"][$k] = $t' --arg k "$1:$2" --arg t "$3"
}

echo "== discipline =="
SD=coordinate-discipline-ci-health-20260926T070000Z
db_init; seed_session "$SD" "$(record_json discipline ci-health)"
RS_SESSION=$SD bash "$CR" --scope discipline --name ci-health --repo "$REPO" --no-seal >/dev/null 2>"$T/err"
eq "a discipline rotation has no close-out to read" 64 $?
grep -q 'rotation_end' "$T/err" && ok "  ... it ends at rotation_end" || bad "  ... it ends at rotation_end" "$(cat "$T/err")"

echo "== roadmap =="
RP=docs/roadmaps/ROADMAP-plugin-system.md
SR=coordinate-roadmap-plugin-system-20260926T070000Z
export RS_SESSION=$SR
roadmap() { # roadmap <status1> <status2> <status3>
    printf -- '---\nstatus: Active\n---\n\n# ROADMAP: plugin system\n\n## Features\n\n### Feature 1: Loader\n**Dependencies:** None\n**Status:** %s\n\n### Feature 2: Registry\n**Dependencies:** Feature 1\n**Status:** %s\n\n### Feature 3: Sandbox\n**Dependencies:** Features 1 and 2\n**Status:** %s\n\n## Sequencing Rationale\n\n**Status:** Not started\n' "$1" "$2" "$3"
}
rm_seed() { db_init; seed_session "$SR" "$1"; } # rm_seed <record-json>
RM=(--scope roadmap --name plugin-system --repo "$REPO" --no-seal)
rm_read() { bash "$CR" "${RM[@]}" 2>"$T/err"; }
CLEAR=$(record_json roadmap plugin-system)
rm_seed "$CLEAR"; file_at main "$RP" "$(roadmap Done Dropped Done.)"
OUT=$(rm_read); eq "every feature Done or Dropped and a clear record is ready" ready "$OUT"
tok_shape "ready is in koto's capture alphabet" "$OUT"
grep -q "contents/$RP?ref=main" "$GH_DB.calls" && ok "the roadmap is read from the default branch" || bad "the roadmap is read from the default branch" "$(calls)"
grep -qE 'issue view|pr view|issues/7' "$GH_DB.calls" && bad "  ... and no record on GitHub" "$(calls)" || ok "  ... and no record on GitHub"
file_at main "$RP" "$(roadmap 'Done -- shipped in #12' 'Shipped (#34)' Dropped)"
eq "an annotated Done and Shipped close like Done" ready "$(rm_read)"
file_at main "$RP" "$(roadmap Done 'In progress' Done)"
OUT=$(rm_read); eq "one feature not Done or Dropped is features-open" features-open "$OUT"
tok_shape "features-open is in koto's capture alphabet" "$OUT"
file_at feat "$RP" "$(roadmap Done Done Done)"
eq "a Done copy on another branch doesn't count" features-open "$(rm_read)"
file_at main "$RP" "$(roadmap Done Doneness Done)"
eq "a word that only begins with Done is not Done" features-open "$(rm_read)"
file_at main "$RP" "$(roadmap Done done Done)"
eq "the status is case-sensitive" features-open "$(rm_read)"
db '.files["acme/widgets"] |= del(.["main:" + $p])' --arg p "$RP"
eq "a missing roadmap is features-open" features-open "$(rm_read)"
file_at main "$RP" "$(printf -- '# ROADMAP\n\n## Features\n\nNone yet.\n')"
eq "a roadmap with no features is features-open" features-open "$(rm_read)"
rm_seed "$(printf '%s' "$CLEAR" | jq -c --argjson h "$(holding alpha)" '.holdings = [$h]')"; file_at main "$RP" "$(roadmap Done Done Dropped)"
OUT=$(rm_read); eq "a holding left is holdings" holdings "$OUT"; tok_shape "holdings is in koto's capture alphabet" "$OUT"
rm_seed "$(printf '%s' "$CLEAR" | jq -c '.side_effects = [{action: "merge", target: "acme/widgets#12", verified_head: "2222222222222222222222222222222222222222", attempted: "2026-09-26T10:00Z", how_to_confirm: "gh pr view 12"}]')"
file_at main "$RP" "$(roadmap Done Done Dropped)"
OUT=$(rm_read); eq "a side effect in flight is side-effects" side-effects "$OUT"; tok_shape "side-effects is in koto's capture alphabet" "$OUT"
grep -q 'reopen-pending' "$T/err" && bad "  ... with no reopen named" "$(cat "$T/err")" || ok "  ... with no reopen named"
# A milestone's pending reopen edit, the milestone still reading Done: named
# first, by its tag, whatever row comes before it.
rm_seed "$(printf '%s' "$CLEAR" | jq -c '.side_effects = [{action: "merge", target: "acme/widgets#12", verified_head: "2222222222222222222222222222222222222222", attempted: "2026-09-26T10:00Z", how_to_confirm: "gh pr view 12"},
    {action: "milestone-reopen", target: "Feature 2 [#9](https://github.com/acme/widgets/pull/9)", verified_head: "", attempted: "2026-09-26T10:00Z", how_to_confirm: "the roadmap on main reads Feature 2 In progress"}]')"
file_at main "$RP" "$(roadmap Done Done Dropped)"
eq "a pending reopen edit is side-effects" side-effects "$(rm_read)"
grep -q 'reopen-pending Feature 2: its reopen edit is pending' "$T/err" && ok "  ... its reason naming the milestone" || bad "  ... its reason naming the milestone" "$(cat "$T/err")"
D_OK='{"deferral":"a","reason":"r","raised":"2026-09-25T10:00Z","disposition":"filed #40"}'
D_CL='{"deferral":"b","reason":"r","raised":"2026-09-25T10:00Z","disposition":"closed: moot"}'
D_CA='{"deferral":"c","reason":"r","raised":"2026-09-25T10:00Z","disposition":"carried 2026-09-26T08:30Z: later"}'
D_EM='{"deferral":"d","reason":"r","raised":"2026-09-25T10:00Z","disposition":""}'
rm_seed "$(printf '%s' "$CLEAR" | jq -c --argjson a "$D_OK" --argjson b "$D_CL" --argjson c "$D_CA" '.deferrals = [$a, $b, $c]')"
file_at main "$RP" "$(roadmap Done Done Dropped)"
OUT=$(rm_read); eq "one carried deferral is deferrals (nobody succeeds a roadmap)" deferrals "$OUT"; tok_shape "deferrals is in koto's capture alphabet" "$OUT"
rm_seed "$(printf '%s' "$CLEAR" | jq -c --argjson a "$D_OK" --argjson d "$D_EM" '.deferrals = [$a, $d]')"
file_at main "$RP" "$(roadmap Done Done Dropped)"
eq "one undisposed deferral is deferrals" deferrals "$(rm_read)"
rm_seed "$(printf '%s' "$CLEAR" | jq -c --argjson a "$D_OK" --argjson b "$D_CL" '.deferrals = [$a, $b]')"
file_at main "$RP" "$(roadmap Done Done Dropped)"
eq "filed and closed deferrals are ready" ready "$(rm_read)"
DENTRY() { jq -nc --arg s "$1" '{decision: "1", round: "1", question: "Ship?", options: "ship\nhold", state: $s,
    source: "self [20260927T233505Z raise 41]", verdict: "", recommendation: "ship", reason: "the check held",
    context: "c", problem: "p", grounds: "scope", target: "a person", owed: "", asked: "", evidence: "",
    outcome: (if $s == "settled" then "ship" else "" end), decided_by: (if $s == "settled" then "a person" else "" end),
    updated: "2026-09-27T23:40Z"}'; }
rm_seed "$(printf '%s' "$CLEAR" | jq -c --argjson e "$(DENTRY escalated)" '.decisions = {next: 2, entries: [$e]}')"
file_at main "$RP" "$(roadmap Done Done Dropped)"
OUT=$(rm_read); eq "an unsettled decision is decisions" decisions "$OUT"; tok_shape "decisions is in koto's capture alphabet" "$OUT"
rm_seed "$(printf '%s' "$CLEAR" | jq -c --argjson e "$(DENTRY settled)" '.decisions = {next: 2, entries: [$e]}')"
file_at main "$RP" "$(roadmap Done Done Dropped)"
eq "settled decisions are ready" ready "$(rm_read)"
# A milestone whose verdict is owed (docs/designs/DESIGN-milestone-verdicts.md):
# its verdict-owed row blocks the close, naming it, whether the milestone
# still reads In progress or already reads Done (the edit merged, the row
# not yet confirmed); with the row gone the roadmap is ready.
OWED_ROW='{"item":"Feature 2","kind":"verdict-owed","who":"none","next":"verdict owed since 2026-09-26","wakes":"0","updated":"2026-09-26T07:00Z"}'
rm_seed "$(printf '%s' "$CLEAR" | jq -c --argjson w "[$OWED_ROW]" '.work = $w')"; file_at main "$RP" "$(roadmap Done 'In progress' Done)"
OUT=$(rm_read); eq "a verdict-owed row is verdict-owed, before the feature that isn't Done" verdict-owed "$OUT"
tok_shape "verdict-owed is in koto's capture alphabet" "$OUT"
grep -q '^closeout-read: verdict-owed Feature 2: its verdict is owed' "$T/err" && ok "  ... its reason names the milestone" || bad "  ... its reason names the milestone" "$(cat "$T/err")"
file_at main "$RP" "$(roadmap Done Done Done)"
OUT=$(rm_read); eq "  ... and still blocks once every milestone reads Done" verdict-owed "$OUT"
rm_seed "$CLEAR"; file_at main "$RP" "$(roadmap Done Done Done)"
OUT=$(rm_read); eq "with the row confirmed away the same roadmap is ready" ready "$OUT"
reset_calls; rm_read > /dev/null
grep -qE 'PUT|POST|DELETE|pr ready|pr edit|pr merge|issue (edit|close)' "$GH_DB.calls" && bad "the read writes nothing" "$(calls)" || ok "the read writes nothing"
rm_seed "$CLEAR"; file_at main "$RP" "$(roadmap Done Done Done)"; db '.fail = [{match: "contents/", rc: 1, stderr: "gh: Server Error (HTTP 502)"}]'
rm_read >/dev/null; eq "a failed roadmap read exits 2" 2 $?
rm -rf "$KOTO_STORE/context/$SR"
rm_read >/dev/null; eq "a session holding no record exits 2" 2 $?
bash "$CR" "${RM[@]}" --predecessor >/dev/null 2>&1; eq "--predecessor is a usage error" 64 $?
bash "$CR" "${RM[@]}" --ref 7 >/dev/null 2>&1; eq "--ref is a usage error" 64 $?
bash "$CR" "${RM[@]}" --today 2026-09-26 >/dev/null 2>&1; eq "--today is a usage error" 64 $?

echo "== roadmap: the session and the detail =="
S=coordinate-roadmap-plugin-system-20260926T080000Z
rm_seed "$CLEAR"; seed_session "$S" "$CLEAR"; file_at main "$RP" "$(roadmap Done 'In progress' Done)"
found_session "$S" "$(roadmap_vars plugin-system)"
log_to "$S" pick_facts roadmap_close
OUT=$(env -u RS_SESSION bash "$CR" --session "$S" 2>"$T/err")
eq "the session's record is read and the token sealed" features-open "${OUT% sealed:*}"
bash "$CL" check --session "$S" --state roadmap_close --sealed "$OUT" && ok "the token is sealed to roadmap_close" || bad "the token is sealed to roadmap_close"
eq "coord/closeout.json names the first blocking feature and the session" "Feature 2 In progress $S" \
    "$(jq -r '"\(.blocker.id) \(.blocker.status) \(.session)"' "$KOTO_STORE/context/$S/coord/closeout.json")"
seed_session "$S" "$(printf '%s' "$CLEAR" | jq -c --argjson w "[$OWED_ROW]" '.work = $w')"; file_at main "$RP" "$(roadmap Done Done Done)"
log_to "$S" roadmap_blocked roadmap_close
OUT=$(env -u RS_SESSION bash "$CR" --session "$S" 2>"$T/err")
eq "a verdict owed reads through the session too" verdict-owed "${OUT% sealed:*}"
eq "  ... and coord/closeout.json's blocker is its row" "Feature 2 verdict owed since 2026-09-26" "$(jq -r '"\(.blocker.item) \(.blocker.next)"' "$KOTO_STORE/context/$S/coord/closeout.json")"
S0=coordinate-roadmap-plugin-system-20260926T090000Z
log_new "$S0" "$(roadmap_vars plugin-system)"
log_to "$S0" pick_facts roadmap_close
env -u RS_SESSION bash "$CR" --session "$S0" >/dev/null 2>&1; eq "a run with no found record exits 2" 2 $?
log_end "$S0"

echo "== roadmap/v3: open milestones =="
# roadmap3 <status1> <status2> <status3>: the roadmap as roadmap/v3, its items
# under `## Milestones` headed `### Milestone N:`.
roadmap3() {
    roadmap "$@" | awk 'NR == 1 { print; print "schema: roadmap/v3"; next } { print }' \
        | sed -e 's/^## Features$/## Milestones/' -e 's/^### Feature \([0-9]\)/### Milestone \1/'
}
cr_detail() { jq -r "$1" "$KOTO_STORE/context/$S/coord/closeout.json"; }
seed_session "$S" "$CLEAR"; file_at main "$RP" "$(roadmap3 Done 'In progress' Done)"
log_to "$S" roadmap_blocked roadmap_close
OUT=$(env -u RS_SESSION bash "$CR" --session "$S" 2>"$T/err")
eq "v3: a milestone not Done is features-open" features-open "${OUT% sealed:*}"
eq "  ... coord/closeout.json names the open milestone and counts milestones" "Milestone 2 In progress|1 milestone(s) not Done, Shipped or Dropped" \
    "$(cr_detail '"\(.blocker.id) \(.blocker.status)|\(.reason)"')"
seed_session "$SR" "$CLEAR"
file_at main "$RP" "$(roadmap3 Done 'Done -- shipped in #12' Dropped)"
eq "v3: every milestone Done or Dropped and a clear record is ready" ready "$(rm_read)"
file_at main "$RP" "$(printf -- '---\nschema: roadmap/v3\n---\n\n## Features\n\n### Feature 1: Loader\n**Status:** In progress\n\n## Milestones\n\nNone yet.\n')"
log_to "$S" roadmap_blocked roadmap_close
OUT=$(env -u RS_SESSION bash "$CR" --session "$S" 2>"$T/err")
eq "v3: a ## Features section is no milestone, so none is listed" "features-open|the roadmap lists no milestone under ## Milestones" "${OUT% sealed:*}|$(cr_detail .reason)"
file_at main "$RP" "$(roadmap Done Done 'Not started')"
log_to "$S" roadmap_blocked roadmap_close
env -u RS_SESSION bash "$CR" --session "$S" >/dev/null 2>"$T/err"
eq "v1: the reason still counts features" "1 feature(s) not Done, Shipped or Dropped" "$(cr_detail .reason)"

done_tests closeout-read
