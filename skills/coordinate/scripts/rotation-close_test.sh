#!/usr/bin/env bash
# rotation-close_test.sh -- rotation-close.sh, the rotation close-out's
# writes, each behind a fresh read.
#
# Covers: --step handoff committing a canonical handoff to the record branch
# through the contents API with the fixed message, and overwriting with the
# existing blob's sha; refusing a file that isn't a canonical handoff, another
# discipline's, an own handoff that is a predecessor copy, a --predecessor
# file that isn't the unedited render, a closed pull request, and a pull
# request from another branch or a fork; --step ready only on an open draft;
# --step delete-branch only after a merge, and a branch already gone; a failed
# write (11) and a failed read (2); refusals on failed provenance and on a
# directed transition in the run (10), and on a session that isn't the
# scope's live one; the own and predecessor pull requests found from the
# session log.
#
# Usage: bash skills/coordinate/scripts/rotation-close_test.sh
set -uo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
command -v jq >/dev/null 2>&1 || { echo "SKIP: jq not on PATH"; exit 0; }
. "$HERE/testdata/test-lib.sh"
RCS="$HERE/rotation-close.sh"
CL="$HERE/coord-log.sh"
BR=coordinate/discipline-ci-health
HP=docs/disciplines/ci-health.md
REC_JSON=$(record_json discipline ci-health | jq -c --argjson h "$(holding alpha)" '.holdings = [$h]')
seed() { # seed [state] [draft] [headRefName] [cross]
    db_init
    db '.branches["acme/widgets"][$br] = $s | .prs += [{repo: "acme/widgets", number: 22,
        title: "docs(coordinate): ci-health rotation 2026-09-15 to 2026-09-22", body: $b, state: $st, isDraft: ($d == "true"),
        isCrossRepository: ($x == "true"), baseRefName: "main", headRefName: $h, headRefOid: $s, author: "alice", editor: null}]' \
        --arg br "$BR" --arg s "$SHA_HEAD" --arg st "${1:-OPEN}" --arg d "${2:-true}" --arg h "${3:-$BR}" --arg x "${4:-false}" \
        --arg b "$(render "$REC_JSON" pr 2026-09-22T17:00:00Z)"
}
handoff() { # handoff <date> [reasoning]
    printf '%s' "$REC_JSON" | jq -c --arg d "$1" --arg r "${2:-What this rotation learned.}" \
        '. + {rotation: {start: "2026-09-15", end: "2026-09-22", date: $d, host_repo: "acme/widgets", record_url: "https://github.com/acme/widgets/pull/22"}, reasoning: $r}' \
        | bash "$HERE/record-render.sh" --format handoff
}
X=(--scope discipline --name ci-health --repo "$REPO" --ref 22 --skip-session-checks)
rc_() { bash "$RCS" "${X[@]}" "$@" > "$T/out" 2> "$T/err"; }
on_branch() { jq -r --arg k "$BR:$HP" '.files["acme/widgets"][$k] // empty' "$GH_DB"; }
handoff 2026-09-22 > "$T/own.md"

echo "== handoff =="
seed; reset_calls
rc_ --step handoff --file "$T/own.md"; eq "a canonical handoff is committed" "0 committed $HP to $BR" "$? $(cat "$T/out")"
eq "the file is on the record branch" "$(cat "$T/own.md")" "$(on_branch)"
grep -q "^api --method PUT repos/acme/widgets/contents/$HP -f message=docs(coordinate): ci-health rotation handoff 2026-09-22 .*-f branch=$BR$" "$GH_DB.calls" \
    && ok "through the contents API with the fixed message and no sha for a new file" || bad "through the contents API with the fixed message" "$(calls)"
[ "$(jq -r '.prs[0].headRefOid' "$GH_DB")" != "$SHA_HEAD" ] && ok "the pull request's head moves to the commit" || bad "the pull request's head moves to the commit"
handoff 2026-09-22 "A second thought." > "$T/own2.md"
reset_calls
rc_ --step handoff --file "$T/own2.md"; eq "an overwrite is committed" 0 $?
grep -q -- "-f sha=[0-9a-f]\{40\}" "$GH_DB.calls" && ok "an overwrite passes the existing blob's sha" || bad "an overwrite passes the existing blob's sha" "$(calls)"
eq "the overwrite replaced the file" "$(cat "$T/own2.md")" "$(on_branch)"
sed 's/^## Deferrals$/## Deferred/' "$T/own.md" > "$T/bad.md"
seed; rc_ --step handoff --file "$T/bad.md"; eq "a file that isn't a canonical handoff is refused" 10 $?
eq "and nothing is written" "" "$(on_branch)"
handoff 2026-09-22 | sed 's/^# ci-health handoff/# other handoff/; s/coordinate\/discipline-ci-health\./coordinate\/discipline-other./' > "$T/other.md"
rc_ --step handoff --file "$T/other.md"; eq "another discipline's handoff is refused" 10 $?
bash "$HERE/predecessor-handoff.sh" --scope discipline --name ci-health --repo "$REPO" --ref 22 --out "$T/pred.md" --no-seal >/dev/null
rc_ --step handoff --file "$T/pred.md"; eq "an own handoff that is a predecessor copy is refused" 10 $?
seed CLOSED false; rc_ --step handoff --file "$T/own.md"; eq "a closed pull request is refused" 10 $?
seed OPEN true feat/other; rc_ --step handoff --file "$T/own.md"; eq "a pull request from another branch is refused" 10 $?
seed OPEN true "$BR" true; rc_ --step handoff --file "$T/own.md"; eq "a fork's pull request is refused" 10 $?
seed; db '.fail = [{match: "--method PUT", rc: 1, stderr: "gh: Server Error (HTTP 502)"}]'
rc_ --step handoff --file "$T/own.md"; eq "a failed commit exits 11" 11 $?
seed; db '.fail = [{match: "pr view", rc: 1, stderr: "gh: Server Error (HTTP 502)"}]'
rc_ --step handoff --file "$T/own.md"; eq "a failed pre-read exits 2" 2 $?

echo "== handoff --predecessor =="
seed
rc_ --predecessor --step handoff --file "$T/pred.md"; eq "the predecessor's copy, unedited, is committed" 0 $?
eq "it is on the branch byte for byte" "$(cat "$T/pred.md")" "$(on_branch)"
seed; sed 's/| alpha |/| beta |/' "$T/pred.md" > "$T/pred-edited.md"
rc_ --predecessor --step handoff --file "$T/pred-edited.md"; eq "an edited predecessor copy is refused" 10 $?
rc_ --predecessor --step handoff --file "$T/own.md"; eq "reasoning written for the predecessor is refused" 10 $?

echo "== ready =="
seed
rc_ --step ready; eq "an open draft is marked ready" "0 ready #22" "$? $(cat "$T/out")"
eq "the pull request is no longer a draft" false "$(jq -r '.prs[0].isDraft' "$GH_DB")"
rc_ --step ready; eq "a pull request that isn't a draft is refused" 10 $?
seed MERGED false; rc_ --step ready; eq "a merged pull request is refused" 10 $?
seed; db '.fail = [{match: "pr ready", rc: 1, stderr: "gh: failed"}]'
rc_ --step ready; eq "a failed gh pr ready exits 11" 11 $?

echo "== delete-branch =="
seed; rc_ --step delete-branch; eq "an open pull request's branch is never deleted" 10 $?
eq "the branch stays" "$SHA_HEAD" "$(jq -r --arg b "$BR" '.branches["acme/widgets"][$b]' "$GH_DB")"
seed CLOSED false; rc_ --step delete-branch; eq "a closed, unmerged pull request's branch is never deleted" 10 $?
seed MERGED false; reset_calls
rc_ --step delete-branch; eq "a merged record's branch is deleted" "0 deleted $BR" "$? $(cat "$T/out")"
grep -q "^api --method DELETE repos/acme/widgets/git/refs/heads/$BR$" "$GH_DB.calls" && ok "through DELETE git/refs" || bad "through DELETE git/refs" "$(calls)"
rc_ --step delete-branch; eq "a branch already gone is done" "0 deleted $BR (already gone)" "$? $(cat "$T/out")"
seed MERGED false; db '.fail = [{match: "--method DELETE", rc: 1, stderr: "gh: failed"}]'
rc_ --step delete-branch; eq "a failed delete exits 11" 11 $?

echo "== usage =="
seed
rc_ --step ready --file "$T/own.md"; eq "--file with ready is a usage error" 64 $?
rc_ --step handoff; eq "handoff without --file is a usage error" 64 $?
rc_ --step merge; eq "an unknown step is a usage error" 64 $?
bash "$RCS" --scope roadmap --name x --repo "$REPO" --ref 7 --skip-session-checks --step ready >/dev/null 2>&1; eq "roadmap scope is a usage error" 64 $?
bash "$RCS" --scope discipline --name ci-health --repo "$REPO" --ref 22 --step ready >/dev/null 2>&1; eq "override flags without --skip-session-checks need a session" 64 $?

echo "== the session =="
seed
S=coordinate-discipline-ci-health-20260926T080000Z
found_session "$S" "$(discipline_vars ci-health)" 22
bash "$RCS" --session "$S" --step ready > "$T/out" 2>"$T/err"; eq "the own record comes from run-facts" "0 ready #22" "$? $(cat "$T/out")"
seed
log_end "$S"
S=coordinate-discipline-ci-health-20260926T080001Z
log_new "$S" "$(discipline_vars ci-health)"
log_to "$S" record_find predecessor_handoff
log_capture "$S" HANDOFF "$(bash "$CL" seal --session "$S" --state predecessor_handoff --token "rendered 22")"
log_to "$S" predecessor_handoff predecessor_close
log_to "$S" predecessor_close predecessor_step
bash "$RCS" --session "$S" --predecessor --step handoff --file "$T/pred.md" > "$T/out" 2>"$T/err"
eq "the predecessor comes from the HANDOFF capture" "0 committed $HP to $BR" "$? $(cat "$T/out")"
S_PRED=$S
seed
bash "$RCS" --session "$S" --step ready >/dev/null 2>&1; eq "without --predecessor a run with no found record is refused" 10 $?
log_end "$S"
S=coordinate-discipline-ci-health-20260926T080002Z
found_session "$S" "$(discipline_vars ci-health)" 22 deadbeef
bash "$RCS" --session "$S" --step ready >/dev/null 2>"$T/err"; eq "a session that fails provenance is refused" 10 $?
seed
bash "$RCS" --session "$S_PRED" --predecessor --step ready >/dev/null 2>"$T/err"; eq "an ended session is refused" 10 $?
eq "and nothing is written" true "$(jq -r '.prs[0].isDraft' "$GH_DB")"
log_end "$S"
S=coordinate-discipline-ci-health-20260926T080003Z
found_session "$S" "$(discipline_vars ci-health)" 22
log_ev "$S" directed_transition '{"from":"rotation_close","to":"rotation_step"}'
bash "$RCS" --session "$S" --step ready >/dev/null 2>"$T/err"; eq "a directed transition in the run is refused" 10 $?
eq "and nothing is written" true "$(jq -r '.prs[0].isDraft' "$GH_DB")"
grep -q 'directed transition' "$T/err" && ok "the refusal names the directed transition" || bad "the refusal names the directed transition" "$(cat "$T/err")"

done_tests rotation-close
