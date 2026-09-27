#!/usr/bin/env bash
# record-write_test.sh -- record-write.sh replaces the whole record body, never
# comments, and refuses a target that isn't this scope's open record, a body
# that isn't canonical, a private repository named from a public host, and a
# run with failed provenance or a directed transition.
#
# Covers: the whole-body edit (the calls log shows `issue edit`/`pr edit` and
# no comment); --close writing before closing; --end rewriting the title's end
# and refusing one before the start; closed, foreign and other-scope targets
# (10); non-canonical and wrong-scope bodies (65); a private Holdings repo and
# a private pull request link from a public host (65) but not from a private
# host; filed and closed deferrals kept before the run's first dispatch and
# dropped (with a new Written: time) after it, carried and open rows staying;
# the record number from run-facts; failed writes (11) and reads (2).
#
# Usage: bash skills/coordinate/scripts/record-write_test.sh
set -uo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
command -v jq >/dev/null 2>&1 || { echo "SKIP: jq not on PATH"; exit 0; }
. "$HERE/testdata/test-lib.sh"
WR="$HERE/record-write.sh"

TITLE="Coordinator record: ROADMAP-plugin-system"
RM=(--scope roadmap --name plugin-system --repo "$REPO" --ref 7 --skip-session-checks)
DS=(--scope discipline --name ci-health --repo "$REPO" --ref 22 --skip-session-checks)
BR=coordinate/discipline-ci-health
OLD=$(render "$(record_json roadmap plugin-system)" issue 2026-09-26T08:00:00Z)
DOLD=$(render "$(record_json discipline ci-health)" pr 2026-09-26T08:00:00Z)
DEFERRALS='[{"deferral":"a","reason":"r","raised":"2026-09-25T10:00Z","disposition":"filed #40"},
            {"deferral":"b","reason":"r","raised":"2026-09-25T10:00Z","disposition":"closed: done elsewhere"},
            {"deferral":"c","reason":"r","raised":"2026-09-25T10:00Z","disposition":"carried 2026-09-26T08:30Z: next week"},
            {"deferral":"d","reason":"r","raised":"2026-09-25T10:00Z","disposition":""}]'
NEWJ=$(record_json roadmap plugin-system | jq -c --argjson h "$(holding feature-2)" --argjson d "$DEFERRALS" '.holdings = [$h] | .deferrals = $d')
render "$NEWJ" issue 2026-09-26T11:00:00Z > "$T/new.md"

seed_rm() { db_init; db '.issues += [{repo: "acme/widgets", number: 7, title: $t, body: $b, state: "open", author: "alice", editor: null}]' --arg t "$TITLE" --arg b "$OLD"; }
seed_ds() {
    db_init
    db '.branches["acme/widgets"][$br] = $s | .prs += [{repo: "acme/widgets", number: 22, title: "docs(coordinate): ci-health rotation 2026-09-22 to 2026-09-29",
        body: $b, state: "OPEN", isDraft: true, isCrossRepository: false, baseRefName: "main", headRefName: $br, headRefOid: $s, author: "alice", editor: null}]' \
        --arg br "$BR" --arg s "$SHA_HEAD" --arg b "$DOLD"
}
body7() { jq -r '.issues[] | select(.number == 7) | .body' "$GH_DB"; }

echo "== roadmap =="
seed_rm
OUT=$(bash "$WR" "${RM[@]}" --body-file "$T/new.md" 2>"$T/err"); rc=$?
eq "a write exits 0 and prints the URL" "0 https://github.com/acme/widgets/issues/7" "$rc $OUT"
eq "the whole body is replaced" "$(cat "$T/new.md")" "$(body7)"
grep -q '^issue edit 7 --repo acme/widgets --body-file' "$GH_DB.calls" && ok "the write is an issue edit" || bad "the write is an issue edit" "$(calls)"
grep -q comment "$GH_DB.calls" && bad "no comment is posted" "$(calls)" || ok "no comment is posted"
eq "filed and closed deferrals stay before any dispatch" 4 "$(body7 | grep -c '^| [abcd] |')"
reset_calls
bash "$WR" "${RM[@]}" --close --body-file "$T/new.md" >/dev/null 2>"$T/err"; rc=$?
eq "--close exits 0" 0 "$rc"
eq "--close writes the body, then closes" "issue edit|issue close" "$(grep -oE '^issue (edit|close)' "$GH_DB.calls" | tr '\n' '|' | sed 's/|$//')"
eq "the issue is closed" closed "$(jq -r '.issues[0].state' "$GH_DB")"
bash "$WR" "${RM[@]}" --body-file "$T/new.md" >/dev/null 2>&1; eq "a closed record is refused" 10 $?
seed_rm; db '.issues[0].body = "not a record"'
bash "$WR" "${RM[@]}" --body-file "$T/new.md" >/dev/null 2>&1; eq "a target without the declaration line is refused" 10 $?
seed_rm; db '.issues[0].body = $b' --arg b "$(render "$(record_json roadmap other)" issue)"
bash "$WR" "${RM[@]}" --body-file "$T/new.md" >/dev/null 2>&1; eq "a target declared for another scope is refused" 10 $?
seed_rm
printf '%s\n\nA note.\n' "$(cat "$T/new.md")" > "$T/bad.md"
bash "$WR" "${RM[@]}" --body-file "$T/bad.md" >/dev/null 2>&1; eq "a non-canonical body is refused" 65 $?
render "$(record_json roadmap other)" issue > "$T/other.md"
bash "$WR" "${RM[@]}" --body-file "$T/other.md" >/dev/null 2>&1; eq "a body for another roadmap is refused" 65 $?
eq "refused bodies write nothing" "$OLD" "$(body7)"
bash "$WR" "${RM[@]}" --end 2026-10-01 --body-file "$T/new.md" >/dev/null 2>&1; eq "--end at roadmap scope is a usage error" 64 $?

echo "== repository visibility =="
seed_rm
render "$(printf '%s' "$NEWJ" | jq -c '.holdings[0].repo = "acme/secret"')" issue > "$T/priv.md"
bash "$WR" "${RM[@]}" --body-file "$T/priv.md" >/dev/null 2>"$T/err"; rc=$?
eq "a private Holdings repo from a public host is refused" 65 "$rc"
grep -q 'acme/secret' "$T/err" && ok "the refusal names the repository" || bad "the refusal names the repository" "$(cat "$T/err")"
render "$(printf '%s' "$NEWJ" | jq -c '.holdings[0].pull_request = "[#3](https://github.com/acme/secret/pull/3)"')" issue > "$T/privpr.md"
bash "$WR" "${RM[@]}" --body-file "$T/privpr.md" >/dev/null 2>&1; eq "a private pull request link from a public host is refused" 65 $?
render "$(printf '%s' "$NEWJ" | jq -c '.holdings[0].repo = "acme/gadgets"')" issue > "$T/pub.md"
bash "$WR" "${RM[@]}" --body-file "$T/pub.md" >/dev/null 2>&1; eq "a public unit repository is fine" 0 $?
seed_rm; db '.repos["acme/widgets"].private = true'
bash "$WR" "${RM[@]}" --body-file "$T/priv.md" >/dev/null 2>&1; eq "a private host may name a private repository" 0 $?
seed_rm; db '.fail = [{match: "repos/acme/widgets --jq .private", rc: 1}]'
bash "$WR" "${RM[@]}" --body-file "$T/new.md" >/dev/null 2>&1; eq "a failed visibility read exits 2" 2 $?

echo "== discipline =="
seed_ds
render "$(printf '%s' "$NEWJ" | jq -c '.scope = {kind: "discipline", name: "ci-health"}')" pr 2026-09-26T11:00:00Z > "$T/dnew.md"
bash "$WR" "${DS[@]}" --body-file "$T/dnew.md" >/dev/null 2>"$T/err"; eq "a discipline write exits 0" 0 $?
eq "the pull request body is replaced" "$(cat "$T/dnew.md")" "$(jq -r '.prs[0].body' "$GH_DB")"
grep -q '^pr edit 22 --repo acme/widgets --body-file' "$GH_DB.calls" && ok "the write is a pr edit" || bad "the write is a pr edit" "$(calls)"
grep -q comment "$GH_DB.calls" && bad "no comment on the pull request" "$(calls)" || ok "no comment on the pull request"
eq "the title is untouched without --end" "docs(coordinate): ci-health rotation 2026-09-22 to 2026-09-29" "$(jq -r '.prs[0].title' "$GH_DB")"
bash "$WR" "${DS[@]}" --end 2026-09-25 --body-file "$T/dnew.md" >/dev/null 2>"$T/err"; eq "--end exits 0" 0 $?
eq "--end rewrites the title's end and keeps its start" "docs(coordinate): ci-health rotation 2026-09-22 to 2026-09-25" "$(jq -r '.prs[0].title' "$GH_DB")"
reset_calls
bash "$WR" "${DS[@]}" --end 2026-09-21 --body-file "$T/dnew.md" >/dev/null 2>&1; eq "an end before the start is refused" 65 $?
grep -q 'pr edit' "$GH_DB.calls" && bad "a refused end writes nothing" "$(calls)" || ok "a refused end writes nothing"
bash "$WR" "${DS[@]}" --close --body-file "$T/dnew.md" >/dev/null 2>&1; eq "--close at discipline scope is a usage error" 64 $?
seed_ds; db '.prs[0].headRefName = "feat/other"'
bash "$WR" "${DS[@]}" --body-file "$T/dnew.md" >/dev/null 2>&1; eq "a pull request off the record branch is refused" 10 $?
seed_ds; db '.prs[0].state = "MERGED"'
bash "$WR" "${DS[@]}" --body-file "$T/dnew.md" >/dev/null 2>&1; eq "a merged record is refused" 10 $?
seed_ds; db '.fail = [{match: "pr edit", rc: 1}]'
bash "$WR" "${DS[@]}" --body-file "$T/dnew.md" >/dev/null 2>&1; eq "a failed edit exits 11" 11 $?
seed_ds; db '.fail = [{match: "pr view", rc: 1}]'
bash "$WR" "${DS[@]}" --body-file "$T/dnew.md" >/dev/null 2>&1; eq "a failed target read exits 2" 2 $?

echo "== the session: record number, dispatch, refusals =="
seed_rm
S=coordinate-plugin-system-20260926T080000Z
found_session "$S" "$(roadmap_vars plugin-system)" 7
OUT=$(bash "$WR" --session "$S" --body-file "$T/new.md" 2>"$T/err"); rc=$?
eq "the record number comes from run-facts" "0 https://github.com/acme/widgets/issues/7" "$rc $OUT"
eq "before the run's first dispatch every deferral stays" 4 "$(body7 | grep -c '^| [abcd] |')"
log_to "$S" reconcile pick_facts; log_to "$S" pick_facts pick; log_to "$S" pick dispatch_check; log_to "$S" dispatch_check dispatch
bash "$WR" --session "$S" --body-file "$T/new.md" >/dev/null 2>"$T/err"; eq "a write after the first dispatch exits 0" 0 $?
eq "filed and closed deferrals are dropped after the first dispatch" "c d" "$(body7 | sed -n 's/^| \([abcd]\) |.*/\1/p' | tr '\n' ' ' | sed 's/ $//')"
W=$(body7 | sed -n 's/^Written: //p')
[ "$W" != 2026-09-26T11:00:00Z ] && ok "the dropped render carries a new Written: time" || bad "the dropped render carries a new Written: time" "$W"
S2=coordinate-plugin-system-20260926T090000Z
log_new "$S2" "$(roadmap_vars plugin-system)"
bash "$WR" --session "$S2" --body-file "$T/new.md" >/dev/null 2>&1; eq "a run with no found record is refused" 10 $?
S3=coordinate-plugin-system-20260926T100000Z
found_session "$S3" "$(roadmap_vars plugin-system)" 7
log_ev "$S3" directed_transition '{"from":"reconcile","to":"dispatch"}'
seed_rm; reset_calls
bash "$WR" --session "$S3" --body-file "$T/new.md" >/dev/null 2>&1; eq "a directed transition in the run is refused" 10 $?
eq "and nothing is read or written" "" "$(calls)"
S4=coordinate-plugin-system-20260926T110000Z
found_session "$S4" "$(roadmap_vars plugin-system)" 7 0badbeef
bash "$WR" --session "$S4" --body-file "$T/new.md" >/dev/null 2>&1; eq "failed provenance is refused" 10 $?
bash "$WR" --session "$S" --ref 7 --body-file "$T/new.md" >/dev/null 2>&1; eq "--ref without the override flags is a usage error" 64 $?

done_tests record-write
