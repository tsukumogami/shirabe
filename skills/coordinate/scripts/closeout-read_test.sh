#!/usr/bin/env bash
# closeout-read_test.sh -- closeout-read.sh reads each close-out stage from
# GitHub: a rotation's own close-out, a predecessor's, and a roadmap's.
#
# Covers, own rotation: handoff-missing for a file absent at the head, not
# canonical, dated other than today, a predecessor copy, or reasoning copied
# from the default branch; title-stale and the early end-date correction
# (record-write.sh --end) that clears it; land only when the board verifies
# the head (pending and a board error exit 2, unverified prints the unmapped
# land-blocked, a board at another head exits 2); merged; closed-unmerged; a
# hand-over, after which the read reports what the person did (merged), never
# `handed-over`. Predecessor: the copied tables, the not-re-checked line and the
# fixed sentence checked against a fresh render; an edited copy and a copy with
# reasoning refused; its title never stale; a whole predecessor close through
# rotation-close.sh. Roadmap: closed, one feature not Done, Shipped or
# Dropped, a missing roadmap, no features, holdings, side effects, one
# undisposed deferral (carried or empty), and ready with every feature Done,
# Shipped or Dropped (an annotated `Done -- shipped in #12` and
# `Shipped (#34)` included) and a clear record; the roadmap read from the default branch; the sealed
# token and coord/closeout.json naming the first blocker; every token in
# koto's capture alphabet.
#
# Runs in a localized plugin tree whose board-verdict.sh is a stand-in that
# prints $BOARD_OUT.
# Usage: bash skills/coordinate/scripts/closeout-read_test.sh
set -uo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
command -v jq >/dev/null 2>&1 || { echo "SKIP: jq not on PATH"; exit 0; }
. "$HERE/testdata/test-lib.sh"
PS="$T/plugin/skills/coordinate/scripts"
mkdir -p "$PS"
cp "$HERE"/*.sh "$HERE"/record-codec.jq "$PS/"
cat > "$PS/board-verdict.sh" <<'STUB'
#!/usr/bin/env bash
# Stand-in: prints the board the test staged.
printf '%s\n' "$*" >> "$BOARD_OUT.calls"
[ -f "$BOARD_OUT" ] || exit 1
cat "$BOARD_OUT"
STUB
export BOARD_OUT="$T/board.json"
CR="$PS/closeout-read.sh"
CL="$PS/coord-log.sh"
BR=coordinate/discipline-ci-health
HP=docs/disciplines/ci-health.md
tok_shape() {
    local re='^[A-Za-z0-9 :/_.@-]*$'
    if [[ ${2% sealed:*} =~ $re ]]; then ok "$1"; else bad "$1" "[$2]"; fi
}
board() { # board <verdict> [head]
    jq -nc --arg v "$1" --arg h "${2:-$SHA_HEAD}" '{verdict: $v, head: $h, reasons: (if $v == "unverified" then [{code: "run-conclusion"}] else [] end)}' > "$BOARD_OUT"
}
file_at() { # file_at <ref> <path> <text>
    db '.files["acme/widgets"][$k] = $t' --arg k "$1:$2" --arg t "$3"
}
pr_seed() { # pr_seed <title> [state] [draft]
    db_init
    db '.branches["acme/widgets"][$br] = $s | .prs += [{repo: "acme/widgets", number: 22, title: $t, body: $b, state: $st,
        isDraft: ($d == "true"), isCrossRepository: false, baseRefName: "main", headRefName: $br, headRefOid: $s, author: "alice", editor: null}]' \
        --arg br "$BR" --arg s "$SHA_HEAD" --arg t "$1" --arg st "${2:-OPEN}" --arg d "${3:-true}" \
        --arg b "$(render "$REC_JSON" pr 2026-09-26T09:00:00Z)"
}
handoff() { # handoff <date> [reasoning] [start end]: an own-rotation handoff
    printf '%s' "$REC_JSON" | jq -c --arg d "$1" --arg r "${2:-Flaky lint belongs to infra now.}" --arg s "${3:-2026-09-22}" --arg e "${4:-2026-09-29}" \
        '. + {rotation: {start: $s, end: $e, date: $d, host_repo: "acme/widgets", record_url: "https://github.com/acme/widgets/pull/22"}, reasoning: $r}' \
        | bash "$HERE/record-render.sh" --format handoff
}
REC_JSON=$(record_json discipline ci-health | jq -c --argjson h "$(holding alpha)" '.holdings = [$h]')
OWN=(--scope discipline --name ci-health --repo "$REPO" --ref 22 --no-seal)
own() { bash "$CR" "${OWN[@]}" --today "${1:-2026-09-29}" 2>"$T/err"; }
TITLE="docs(coordinate): ci-health rotation 2026-09-22 to 2026-09-29"

echo "== own rotation: the handoff =="
pr_seed "$TITLE"; board verified
eq "no file at the head is handoff-missing" "handoff-missing 22" "$(own)"
tok_shape "handoff-missing is in koto's capture alphabet" "$(own)"
file_at "$SHA_HEAD" "$HP" "$(handoff 2026-09-29 | sed 's/^## Deferrals$/## Deferred/')"
eq "a file that isn't a canonical handoff is handoff-missing" "handoff-missing 22" "$(own)"
file_at "$SHA_HEAD" "$HP" "$(handoff 2026-09-28)"
eq "a header date other than today is handoff-missing" "handoff-missing 22" "$(own)"
file_at "$SHA_HEAD" "$HP" "$(handoff 2026-09-29)"
file_at main "$HP" "$(handoff 2026-09-22 'Flaky lint belongs to infra now.' 2026-09-15 2026-09-22)"
eq "reasoning identical to the default branch's is handoff-missing" "handoff-missing 22" "$(own)"
grep -q 'not written fresh' "$T/err" && ok "the reason says why" || bad "the reason says why" "$(cat "$T/err")"
file_at main "$HP" "$(handoff 2026-09-22 'The old rotation learned something else.' 2026-09-15 2026-09-22)"
eq "fresh reasoning passes to the board" "land 22 $SHA_HEAD" "$(own)"
grep -q "contents/$HP?ref=$SHA_HEAD" "$GH_DB.calls" && grep -q "contents/$HP?ref=main" "$GH_DB.calls" \
    && ok "the file is read at the head and on the default branch" || bad "the file is read at the head and on the default branch" "$(calls)"
printf '%s' "$REC_JSON" | jq -c '. + {rotation: {start: "2026-09-22", end: "2026-09-29", date: "2026-09-29", host_repo: "acme/widgets",
    record_url: "https://github.com/acme/widgets/pull/22"}, predecessor_copy: {written: "2026-09-26T09:00:00Z"}}' \
    | bash "$HERE/record-render.sh" --format handoff > "$T/copy.md"
file_at "$SHA_HEAD" "$HP" "$(cat "$T/copy.md")"
eq "a predecessor copy as the own handoff is handoff-missing" "handoff-missing 22" "$(own)"
db '.files["acme/widgets"] |= del(.["main:" + $p])' --arg p "$HP"
file_at "$SHA_HEAD" "$HP" "$(handoff 2026-09-29)"
eq "no file on the default branch (a first rotation) passes" "land 22 $SHA_HEAD" "$(own)"

echo "== own rotation: the title and the early end-date correction =="
file_at "$SHA_HEAD" "$HP" "$(handoff 2026-09-26)"
eq "ending early: a handoff dated today and a title ending later is title-stale" "title-stale 22" "$(own 2026-09-26)"
tok_shape "title-stale is in koto's capture alphabet" "$(own 2026-09-26)"
render "$REC_JSON" pr > "$T/body.md"
bash "$PS/record-write.sh" --scope discipline --name ci-health --repo "$REPO" --ref 22 --skip-session-checks \
    --body-file "$T/body.md" --end 2026-09-26 >/dev/null 2>"$T/werr"
eq "record-write.sh --end corrects the title" "docs(coordinate): ci-health rotation 2026-09-22 to 2026-09-26" "$(jq -r '.prs[0].title' "$GH_DB")"
eq "after the correction the stage is land" "land 22 $SHA_HEAD" "$(own 2026-09-26)"

echo "== own rotation: the board =="
pr_seed "$TITLE"; file_at "$SHA_HEAD" "$HP" "$(handoff 2026-09-29)"
board verified
OUT=$(own); eq "a verified board is land at the head" "land 22 $SHA_HEAD" "$OUT"
tok_shape "land is in koto's capture alphabet" "$OUT"
grep -q -- "--repo acme/widgets --pr 22" "$BOARD_OUT.calls" && ok "the board is read for the record pull request" || bad "the board is read for the record pull request" "$(cat "$BOARD_OUT.calls")"
board pending; own >/dev/null; eq "a pending board exits 2 so koto re-reads" 2 $?
board unverified; OUT=$(own); eq "an unverified board is land-blocked, which no arm routes" "land-blocked 22" "$OUT"
tok_shape "land-blocked is in koto's capture alphabet" "$OUT"
board error:board-read; own >/dev/null; eq "a board read error exits 2" 2 $?
board verified "$SHA_OTHER"; own >/dev/null; eq "a board verified at another head exits 2" 2 $?
rm -f "$BOARD_OUT"; own >/dev/null; eq "a failed board read exits 2" 2 $?

echo "== own rotation: merged, closed, handed over =="
pr_seed "$TITLE" MERGED false
eq "a merged record is merged" "merged 22" "$(own 2026-10-02)"
pr_seed "$TITLE" CLOSED false
eq "a record closed without merging is closed-unmerged" "closed-unmerged 22" "$(own)"
tok_shape "closed-unmerged is in koto's capture alphabet" "$(own)"
pr_seed "$TITLE" OPEN false; file_at "$SHA_HEAD" "$HP" "$(handoff 2026-09-29)"; board verified
eq "a hand-over: the stage is still land while the person hasn't merged" "land 22 $SHA_HEAD" "$(own)"
db '.prs[0].state = "MERGED"'
eq "once the person merges, the read reports merged, never handed-over" "merged 22" "$(own 2026-09-30)"
reset_calls; own >/dev/null
grep -qE 'PUT|POST|DELETE|pr ready|pr edit|pr merge' "$GH_DB.calls" && bad "the read writes nothing" "$(calls)" || ok "the read writes nothing"

echo "== predecessor =="
PTITLE="docs(coordinate): ci-health rotation 2026-09-15 to 2026-09-22"
PRED=(--scope discipline --name ci-health --repo "$REPO" --ref 22 --predecessor --no-seal --today 2026-09-26)
pred() { bash "$CR" "${PRED[@]}" 2>"$T/err"; }
pr_seed "$PTITLE"; board verified
eq "a predecessor with no file at the head is handoff-missing" "handoff-missing 22" "$(pred)"
bash "$PS/predecessor-handoff.sh" --scope discipline --name ci-health --repo "$REPO" --ref 22 --out "$T/pred.md" --no-seal >/dev/null
file_at "$SHA_HEAD" "$HP" "$(cat "$T/pred.md")"
eq "the predecessor's copy as rendered lands; its title is never stale" "land 22 $SHA_HEAD" "$(pred)"
sed 's/| alpha |/| beta |/' "$T/pred.md" > "$T/edited.md"
file_at "$SHA_HEAD" "$HP" "$(cat "$T/edited.md")"
eq "a copy whose tables were edited is handoff-missing" "handoff-missing 22" "$(pred)"
printf '%s' "$REC_JSON" | jq -c '. + {rotation: {start: "2026-09-15", end: "2026-09-22", date: "2026-09-22", host_repo: "acme/widgets",
    record_url: "https://github.com/acme/widgets/pull/22"}, reasoning: "Written for the predecessor."}' | bash "$HERE/record-render.sh" --format handoff > "$T/reasoned.md"
file_at "$SHA_HEAD" "$HP" "$(cat "$T/reasoned.md")"
eq "a copy with reasoning written on the predecessor's behalf is handoff-missing" "handoff-missing 22" "$(pred)"
sed 's/^# ci-health handoff, 2026-09-22$/# ci-health handoff, 2026-09-26/' "$T/pred.md" > "$T/today.md"
file_at "$SHA_HEAD" "$HP" "$(cat "$T/today.md")"
eq "a copy dated today rather than the title's end date is handoff-missing" "handoff-missing 22" "$(pred)"

echo "== a predecessor close, step by step =="
pr_seed "$PTITLE"; board verified
RC=(--scope discipline --name ci-health --repo "$REPO" --ref 22 --skip-session-checks --predecessor)
eq "1. the stage starts at handoff-missing" "handoff-missing 22" "$(pred)"
bash "$PS/rotation-close.sh" "${RC[@]}" --step handoff --file "$T/pred.md" >/dev/null 2>"$T/rerr"; eq "2. the rendered copy is committed" 0 $?
H2=$(jq -r '.prs[0].headRefOid' "$GH_DB")
board verified "$H2"
eq "3. the stage is land at the new head" "land 22 $H2" "$(pred)"
bash "$PS/rotation-close.sh" "${RC[@]}" --step ready >/dev/null 2>&1; eq "4. the pull request is marked ready" 0 $?
db '.prs[0].state = "MERGED"'
eq "5. after the merge the stage is merged" "merged 22" "$(pred)"
bash "$PS/rotation-close.sh" "${RC[@]}" --step delete-branch >/dev/null 2>&1; eq "6. the branch is deleted" 0 $?
eq "7. the record branch is gone" "" "$(jq -r --arg b "$BR" '.branches["acme/widgets"][$b] // empty' "$GH_DB")"

echo "== the session =="
pr_seed "$PTITLE"; board verified
file_at "$SHA_HEAD" "$HP" "$(cat "$T/pred.md")"
S=coordinate-ci-health-20260926T080000Z
log_new "$S" "$(discipline_vars ci-health)"
log_to "$S" record_find predecessor_handoff
log_capture "$S" HANDOFF "$(bash "$CL" seal --session "$S" --state predecessor_handoff --token "rendered 22")"
log_to "$S" predecessor_handoff predecessor_close
OUT=$(bash "$CR" --session "$S" --predecessor --today 2026-09-26 2>"$T/err")
eq "the predecessor comes from the HANDOFF capture" "land 22 $SHA_HEAD" "${OUT% sealed:*}"
bash "$CL" check --session "$S" --state predecessor_close --sealed "$OUT" && ok "the token is sealed to predecessor_close" || bad "the token is sealed to predecessor_close" "$OUT $(cat "$T/err")"
eq "the detail goes to coord/closeout.json" "land verified" "$(jq -r '"\(.verdict) \(.board.verdict)"' "$KOTO_STORE/context/$S/coord/closeout.json")"
S2=coordinate-ci-health-20260926T080001Z
log_new "$S2" "$(discipline_vars ci-health)"
log_to "$S2" predecessor_handoff predecessor_close
bash "$CR" --session "$S2" --predecessor >/dev/null 2>&1; eq "no sealed HANDOFF capture exits 2" 2 $?

echo "== roadmap =="
RP=docs/roadmaps/ROADMAP-plugin-system.md
ITITLE="Coordinator record: ROADMAP-plugin-system"
roadmap() { # roadmap <status1> <status2> <status3>
    printf -- '---\nstatus: Active\n---\n\n# ROADMAP: plugin system\n\n## Features\n\n### Feature 1: Loader\n**Dependencies:** None\n**Status:** %s\n\n### Feature 2: Registry\n**Dependencies:** Feature 1\n**Status:** %s\n\n### Feature 3: Sandbox\n**Dependencies:** Features 1 and 2\n**Status:** %s\n\n## Sequencing Rationale\n\n**Status:** Not started\n' "$1" "$2" "$3"
}
rm_seed() { # rm_seed <record-json> [state]
    db_init
    db '.issues += [{repo: "acme/widgets", number: 7, title: $t, body: $b, state: $s, author: "alice", editor: null}]' \
        --arg t "$ITITLE" --arg b "$(render "$1" issue)" --arg s "${2:-open}"
}
RM=(--scope roadmap --name plugin-system --repo "$REPO" --ref 7 --no-seal)
rm_read() { bash "$CR" "${RM[@]}" 2>"$T/err"; }
CLEAR=$(record_json roadmap plugin-system)
rm_seed "$CLEAR"; file_at main "$RP" "$(roadmap Done Dropped Done.)"
OUT=$(rm_read); eq "every feature Done or Dropped and a clear record is ready" "ready 7" "$OUT"
tok_shape "ready is in koto's capture alphabet" "$OUT"
grep -q "contents/$RP?ref=main" "$GH_DB.calls" && ok "the roadmap is read from the default branch" || bad "the roadmap is read from the default branch" "$(calls)"
file_at main "$RP" "$(roadmap 'Done -- shipped in #12' 'Shipped (#34)' Dropped)"
eq "an annotated Done and Shipped close like Done" "ready 7" "$(rm_read)"
file_at main "$RP" "$(roadmap Done 'In progress' Done)"
OUT=$(rm_read); eq "one feature not Done or Dropped is features-open" "features-open 7" "$OUT"
tok_shape "features-open is in koto's capture alphabet" "$OUT"
file_at feat "$RP" "$(roadmap Done Done Done)"
eq "a Done copy on another branch doesn't count" "features-open 7" "$(rm_read)"
file_at main "$RP" "$(roadmap Done Doneness Done)"
eq "a word that only begins with Done is not Done" "features-open 7" "$(rm_read)"
file_at main "$RP" "$(roadmap Done done Done)"
eq "the status is case-sensitive" "features-open 7" "$(rm_read)"
db '.files["acme/widgets"] |= del(.["main:" + $p])' --arg p "$RP"
eq "a missing roadmap is features-open" "features-open 7" "$(rm_read)"
file_at main "$RP" "$(printf -- '# ROADMAP\n\n## Features\n\nNone yet.\n')"
eq "a roadmap with no features is features-open" "features-open 7" "$(rm_read)"
file_at main "$RP" "$(roadmap Done Done Dropped)"
rm_seed "$(printf '%s' "$CLEAR" | jq -c --argjson h "$(holding alpha)" '.holdings = [$h]')"; file_at main "$RP" "$(roadmap Done Done Dropped)"
OUT=$(rm_read); eq "a holding left is holdings" "holdings 7" "$OUT"; tok_shape "holdings is in koto's capture alphabet" "$OUT"
rm_seed "$(printf '%s' "$CLEAR" | jq -c '.side_effects = [{action: "merge", target: "acme/widgets#12", verified_head: "2222222222222222222222222222222222222222", attempted: "2026-09-26T10:00Z", how_to_confirm: "gh pr view 12"}]')"
file_at main "$RP" "$(roadmap Done Done Dropped)"
OUT=$(rm_read); eq "a side effect in flight is side-effects" "side-effects 7" "$OUT"; tok_shape "side-effects is in koto's capture alphabet" "$OUT"
D_OK='{"deferral":"a","reason":"r","raised":"2026-09-25T10:00Z","disposition":"filed #40"}'
D_CL='{"deferral":"b","reason":"r","raised":"2026-09-25T10:00Z","disposition":"closed: moot"}'
D_CA='{"deferral":"c","reason":"r","raised":"2026-09-25T10:00Z","disposition":"carried 2026-09-26T08:30Z: later"}'
D_EM='{"deferral":"d","reason":"r","raised":"2026-09-25T10:00Z","disposition":""}'
rm_seed "$(printf '%s' "$CLEAR" | jq -c --argjson a "$D_OK" --argjson b "$D_CL" --argjson c "$D_CA" '.deferrals = [$a, $b, $c]')"
file_at main "$RP" "$(roadmap Done Done Dropped)"
OUT=$(rm_read); eq "one carried deferral is deferrals (nobody succeeds a roadmap)" "deferrals 7" "$OUT"; tok_shape "deferrals is in koto's capture alphabet" "$OUT"
rm_seed "$(printf '%s' "$CLEAR" | jq -c --argjson a "$D_OK" --argjson d "$D_EM" '.deferrals = [$a, $d]')"
file_at main "$RP" "$(roadmap Done Done Dropped)"
eq "one undisposed deferral is deferrals" "deferrals 7" "$(rm_read)"
rm_seed "$(printf '%s' "$CLEAR" | jq -c --argjson a "$D_OK" --argjson b "$D_CL" '.deferrals = [$a, $b]')"
file_at main "$RP" "$(roadmap Done Done Dropped)"
eq "filed and closed deferrals are ready" "ready 7" "$(rm_read)"
DENTRY() { jq -nc --arg s "$1" '{decision: "1", round: "1", question: "Ship?", options: "ship\nhold", state: $s,
    source: "self [20260927T233505Z raise 41]", verdict: "", recommendation: "ship", reason: "the check held",
    context: "c", problem: "p", grounds: "scope", target: "a person", owed: "", asked: "", evidence: "",
    outcome: (if $s == "settled" then "ship" else "" end), decided_by: (if $s == "settled" then "a person" else "" end),
    updated: "2026-09-27T23:40Z"}'; }
rm_seed "$(printf '%s' "$CLEAR" | jq -c --argjson e "$(DENTRY escalated)" '.decisions = {next: 2, entries: [$e]}')"
file_at main "$RP" "$(roadmap Done Done Dropped)"
OUT=$(rm_read); eq "an unsettled decision is decisions" "decisions 7" "$OUT"; tok_shape "decisions is in koto's capture alphabet" "$OUT"
rm_seed "$(printf '%s' "$CLEAR" | jq -c --argjson e "$(DENTRY settled)" '.decisions = {next: 2, entries: [$e]}')"
file_at main "$RP" "$(roadmap Done Done Dropped)"
eq "settled decisions are ready" "ready 7" "$(rm_read)"
rm_seed "$CLEAR" closed; file_at main "$RP" "$(roadmap Done 'Not started' Done)"
OUT=$(rm_read); eq "a closed record issue is closed" "closed 7" "$OUT"; tok_shape "closed is in koto's capture alphabet" "$OUT"
rm_seed "$CLEAR"; file_at main "$RP" "$(roadmap Done Done Done)"; db '.fail = [{match: "contents/", rc: 1, stderr: "gh: Server Error (HTTP 502)"}]'
rm_read >/dev/null; eq "a failed roadmap read exits 2" 2 $?
bash "$CR" "${RM[@]}" --predecessor >/dev/null 2>&1; eq "--predecessor at roadmap scope is a usage error" 64 $?

echo "== roadmap: the session and the detail =="
rm_seed "$CLEAR"; file_at main "$RP" "$(roadmap Done 'In progress' Done)"
S=coordinate-plugin-system-20260926T080000Z
found_session "$S" "$(roadmap_vars plugin-system)" 7
log_to "$S" pick_facts roadmap_close
OUT=$(bash "$CR" --session "$S" 2>"$T/err")
eq "the session's record is read and the token sealed" "features-open 7" "${OUT% sealed:*}"
bash "$CL" check --session "$S" --state roadmap_close --sealed "$OUT" && ok "the token is sealed to roadmap_close" || bad "the token is sealed to roadmap_close"
eq "coord/closeout.json names the first blocking feature" "Feature 2 In progress" "$(jq -r '"\(.blocker.id) \(.blocker.status)"' "$KOTO_STORE/context/$S/coord/closeout.json")"

done_tests closeout-read
