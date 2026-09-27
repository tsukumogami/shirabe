#!/usr/bin/env bash
# record-open_test.sh -- record-open.sh opens exactly one record, and refuses
# when a fresh read shows one, when the body isn't a canonical record for the
# scope, or when the session fails provenance or has a directed transition.
#
# Covers: a roadmap issue opened with the exact title and the given body, then
# refused on a second run; a closed record doesn't block; a -v2 title doesn't
# block; at discipline scope the empty commit on the default branch's head, the
# ref and the draft pull request with the rotation title; an open pull request
# and an existing branch refused, --recut deleting and cutting it again; an end
# before the start and a body for another scope refused (65); partial-write
# failures reporting their step (11); provenance and directed-transition
# refusals through a prepared session log (10).
#
# Usage: bash skills/coordinate/scripts/record-open_test.sh
set -uo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
command -v jq >/dev/null 2>&1 || { echo "SKIP: jq not on PATH"; exit 0; }
. "$HERE/testdata/test-lib.sh"
O="$HERE/record-open.sh"

RM=(--scope roadmap --name plugin-system --repo "$REPO" --skip-session-checks)
DS=(--scope discipline --name ci-health --repo "$REPO" --skip-session-checks --start 2026-09-26 --end 2026-10-03)
TITLE="Coordinator record: ROADMAP-plugin-system"
render "$(record_json roadmap plugin-system)" issue > "$T/rm.md"
render "$(record_json discipline ci-health)" pr > "$T/ds.md"
BR=coordinate/discipline-ci-health

echo "== roadmap =="
db_init
OUT=$(bash "$O" "${RM[@]}" --body-file "$T/rm.md" 2>"$T/err"); rc=$?
eq "a roadmap record opens" "0 record=https://github.com/acme/widgets/issues/1" "$rc $OUT"
eq "it carries the exact title and the body" "$TITLE|$(cat "$T/rm.md")" "$(jq -r '.issues[0] | "\(.title)|\(.body)"' "$GH_DB")"
OUT=$(bash "$O" "${RM[@]}" --body-file "$T/rm.md" 2>"$T/err"); rc=$?
eq "a second open is refused with 10" 10 "$rc"
eq "and opens nothing" 1 "$(jq '.issues | length' "$GH_DB")"
grep -q 'exists' "$T/err" && ok "the refusal names the existing record" || bad "the refusal names the existing record" "$(cat "$T/err")"
db '.issues[0].state = "closed"'
bash "$O" "${RM[@]}" --body-file "$T/rm.md" >/dev/null 2>&1; eq "a closed record doesn't block a new one" 0 $?
db_init
db '.issues += [{repo: "acme/widgets", number: 4, title: ($t + "-v2"), body: "x", state: "open", author: "alice", editor: null}]' --arg t "$TITLE"
bash "$O" "${RM[@]}" --body-file "$T/rm.md" >/dev/null 2>&1; eq "a -v2 title doesn't block" 0 $?
grep -qi search "$GH_DB.calls" && bad "no search form" "$(calls)" || ok "no search form"
db_init
bash "$O" "${RM[@]}" --body-file "$T/ds.md" >/dev/null 2>&1; eq "a discipline body is refused at roadmap scope" 65 $?
render "$(record_json roadmap other)" issue > "$T/other.md"
bash "$O" "${RM[@]}" --body-file "$T/other.md" >/dev/null 2>&1; eq "another roadmap's body is refused" 65 $?
eq "a refused body writes nothing" "" "$(grep -E 'issue create|POST|DELETE' "$GH_DB.calls")"
db '.fail = [{match: "issue create", rc: 1}]'
OUT=$(bash "$O" "${RM[@]}" --body-file "$T/rm.md" 2>/dev/null); rc=$?
eq "a failed create exits 11 naming its step" "11 step=issue-create" "$rc $OUT"
bash "$O" "${RM[@]}" --body-file "$T/rm.md" --start 2026-09-26 --end 2026-09-27 >/dev/null 2>&1; eq "dates at roadmap scope are a usage error" 64 $?

echo "== discipline =="
db_init
OUT=$(bash "$O" "${DS[@]}" --body-file "$T/ds.md" 2>"$T/err"); rc=$?
eq "a rotation record opens" "0 record=https://github.com/acme/widgets/pull/1" "$rc $OUT"
eq "the draft pull request has the rotation title, base and head" "docs(coordinate): ci-health rotation 2026-09-26 to 2026-10-03|main|$BR|true" \
    "$(jq -r '.prs[0] | "\(.title)|\(.baseRefName)|\(.headRefName)|\(.isDraft)"' "$GH_DB")"
NEW=$(jq -r --arg b "$BR" '.branches["acme/widgets"][$b]' "$GH_DB")
[ "$NEW" != "$SHA_MAIN" ] && [ "$(jq -r --arg s "$NEW" '.commits[$s].tree' "$GH_DB")" = 4444444444444444444444444444444444444444 ] \
    && ok "the branch points at a new commit with the default branch's tree" || bad "the branch points at a new commit with the default branch's tree" "$NEW"
grep -q "git/commits -f message=docs(coordinate): open ci-health rotation record -f tree=4444444444444444444444444444444444444444 -f parents\[\]=$SHA_MAIN" "$GH_DB.calls" \
    && ok "the empty commit sits on the default branch's head with its tree" || bad "the empty commit sits on the default branch's head with its tree" "$(calls)"
bash "$O" "${DS[@]}" --body-file "$T/ds.md" >/dev/null 2>"$T/err"; eq "an open pull request on the branch is refused" 10 $?
db '.prs[0].state = "MERGED"'
bash "$O" "${DS[@]}" --body-file "$T/ds.md" >/dev/null 2>"$T/err"; eq "an existing branch without --recut is refused" 10 $?
reset_calls
OUT=$(bash "$O" "${DS[@]}" --recut --body-file "$T/ds.md" 2>"$T/err"); rc=$?
eq "--recut opens a new record" "0 record=https://github.com/acme/widgets/pull/2" "$rc $OUT"
eq "--recut deleted the ref before cutting it" "DELETE POST POST" "$(grep -oE -- '--method (DELETE|POST)' "$GH_DB.calls" | awk '{print $2}' | tr '\n' ' ' | sed 's/ $//')"
db_init
bash "$O" --scope discipline --name ci-health --repo "$REPO" --skip-session-checks --start 2026-09-26 --end 2026-09-20 --body-file "$T/ds.md" >/dev/null 2>&1
eq "an end before the start is refused" 65 $?
bash "$O" --scope discipline --name ci-health --repo "$REPO" --skip-session-checks --start 2026-02-30 --end 2026-03-02 --body-file "$T/ds.md" >/dev/null 2>&1
eq "an impossible date is a usage error" 64 $?
bash "$O" "${DS[@]}" --body-file "$T/rm.md" >/dev/null 2>&1; eq "an issue-container body is refused at discipline scope" 65 $?
db '.fail = [{match: "git/refs -f ref", rc: 1}]'
OUT=$(bash "$O" "${DS[@]}" --body-file "$T/ds.md" 2>/dev/null); rc=$?
eq "a failed ref create exits 11 naming its step" "11 step=ref-create" "$rc $OUT"
db_init; db '.fail = [{match: "pr create", rc: 1}]'
OUT=$(bash "$O" "${DS[@]}" --body-file "$T/ds.md" 2>/dev/null); rc=$?
eq "a failed pull request create exits 11 naming its step" "11 step=pr-create" "$rc $OUT"
db_init; db '.fail = [{match: "repos/acme/widgets --jq", rc: 1}]'
bash "$O" "${DS[@]}" --body-file "$T/ds.md" >/dev/null 2>&1; eq "a failed read exits 2" 2 $?

echo "== session checks =="
db_init
S=coordinate-roadmap-plugin-system-20260926T080000Z
log_new "$S" "$(roadmap_vars plugin-system)"
log_to "$S" record_find record_open
OUT=$(bash "$O" --session "$S" --body-file "$T/rm.md" 2>"$T/err"); rc=$?
eq "a session that passes provenance opens" "0 record=https://github.com/acme/widgets/issues/1" "$rc $OUT"
db_init
S2=coordinate-roadmap-plugin-system-20260926T090000Z
log_new "$S2" "$(roadmap_vars plugin-system)" 0badbeef
bash "$O" --session "$S2" --body-file "$T/rm.md" >/dev/null 2>"$T/err"; eq "a session from another template is refused" 10 $?
eq "and writes nothing" "" "$(calls)"
log_end "$S"; log_end "$S2"
S3=coordinate-roadmap-plugin-system-20260926T100000Z
log_new "$S3" "$(roadmap_vars plugin-system)"
log_ev "$S3" directed_transition '{"from":"record_find","to":"record_open"}'
bash "$O" --session "$S3" --body-file "$T/rm.md" >/dev/null 2>"$T/err"; eq "a directed transition in the run is refused" 10 $?
grep -q 'record_find->record_open' "$T/err" && ok "the refusal names the directed edge" || bad "the refusal names the directed edge" "$(cat "$T/err")"
log_end "$S3"
S4=coordinate-roadmap-plugin-system-20260926T110000Z
log_new "$S4" "$(jq -nc '{SCOPE: "roadmap", ROADMAP: "docs/roadmaps/ROADMAP-plugin-system.md", HOST_REPO: "acme/widgets", PLUGIN_ROOT: "/elsewhere"}')"
bash "$O" --session "$S4" --body-file "$T/rm.md" >/dev/null 2>"$T/err"; eq "a PLUGIN_ROOT that isn't this plugin is refused" 10 $?
bash "$O" --scope roadmap --name plugin-system --repo "$REPO" --body-file "$T/rm.md" >/dev/null 2>&1; eq "override flags without a session need --skip-session-checks" 64 $?
bash "$O" --session "$S" --skip-session-checks --body-file "$T/rm.md" >/dev/null 2>&1; eq "--skip-session-checks without the override flags is a usage error" 64 $?
S5=coordinate-roadmap-plugin-system-20260926T120000Z
log_new "$S5" "$(roadmap_vars plugin-system)"
log_to "$S5" record_find record_open
S6=coordinate-roadmap-plugin-system-20260926T130000Z
log_new "$S6" "$(roadmap_vars plugin-system)"
db_init
bash "$O" --session "$S5" --body-file "$T/rm.md" >/dev/null 2>"$T/err"; eq "a session that isn't its scope's one live session is refused" 10 $?
eq "and writes nothing" "" "$(calls)"

done_tests record-open
