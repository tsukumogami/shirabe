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
# dropped after it, carried and open rows staying; every write carrying the
# script's own Written: time, never the body's (a future one included); a
# Side effects Target naming a private or unreadable repository (65); the
# session refused unless it is its scope's one live session (an older run of
# the same record, several live, a terminal run, another scope's name), with
# the slug derived as coordinate-open.sh derives it; the record number from
# run-facts; failed writes (11) and reads (2). The Decisions section: a write
# that adds, drops or edits it is refused (65) even with DECISIONS_WRITER=1 in
# the environment, one that carries the live section is written, and a
# Decisions text cell naming a private repository from a public host is
# refused; a render over the 60,000-byte budget is refused as record-full (13).
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
OLD=$(render "$(record_json roadmap plugin-system)" issue)
DOLD=$(render "$(record_json discipline ci-health)" pr)
DEFERRALS='[{"deferral":"a","reason":"r","raised":"2026-09-25T10:00Z","disposition":"filed #40"},
            {"deferral":"b","reason":"r","raised":"2026-09-25T10:00Z","disposition":"closed: done elsewhere"},
            {"deferral":"c","reason":"r","raised":"2026-09-25T10:00Z","disposition":"carried 2026-09-26T08:30Z: next week"},
            {"deferral":"d","reason":"r","raised":"2026-09-25T10:00Z","disposition":""}]'
NEWJ=$(record_json roadmap plugin-system | jq -c --argjson h "$(holding feature-2)" --argjson d "$DEFERRALS" '.holdings = [$h] | .deferrals = $d')
render "$NEWJ" issue > "$T/new.md"

seed_rm() { db_init; db '.issues += [{repo: "acme/widgets", number: 7, title: $t, body: $b, state: "open", author: "alice", editor: null}]' --arg t "$TITLE" --arg b "$OLD"; }
seed_ds() {
    db_init
    db '.branches["acme/widgets"][$br] = $s | .prs += [{repo: "acme/widgets", number: 22, title: "docs(coordinate): ci-health rotation 2026-09-22 to 2026-09-29",
        body: $b, state: "OPEN", isDraft: true, isCrossRepository: false, baseRefName: "main", headRefName: $br, headRefOid: $s, author: "alice", editor: null}]' \
        --arg br "$BR" --arg s "$SHA_HEAD" --arg b "$DOLD"
}
# rebase: put the live record back at the version the test bodies were edited
# from (Written 09:00), leaving everything else as it is, so a second write in
# a row isn't refused as record-changed.
rebase() {
    db '(.issues[] | select(.number == 7) | .body) |= $o | (.prs[] | select(.number == 22) | .body) |= $d' --arg o "$OLD" --arg d "$DOLD"
}
body7() { jq -r '.issues[] | select(.number == 7) | .body' "$GH_DB"; }

echo "== roadmap =="
seed_rm
OUT=$(bash "$WR" "${RM[@]}" --body-file "$T/new.md" 2>"$T/err"); rc=$?
eq "a write exits 0 and prints the URL" "0 https://github.com/acme/widgets/issues/7" "$rc $OUT"
eq "the whole body is replaced" "$(grep -v '^Written: ' "$T/new.md")" "$(body7 | grep -v '^Written: ')"
grep -q '^issue edit 7 --repo acme/widgets --body-file' "$GH_DB.calls" && ok "the write is an issue edit" || bad "the write is an issue edit" "$(calls)"
grep -q comment "$GH_DB.calls" && bad "no comment is posted" "$(calls)" || ok "no comment is posted"
eq "filed and closed deferrals stay before any dispatch" 4 "$(body7 | grep -c '^| [abcd] |')"
reset_calls
rebase
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

echo "== the Written: time is the script's own, and a stale base is refused =="
seed_rm
BEFORE=$(date -u +%Y-%m-%dT%H:%M:%SZ)
bash "$WR" "${RM[@]}" --body-file "$T/new.md" >/dev/null 2>"$T/err"; eq "a body edited from the live version is written" 0 $?
AFTER=$(date -u +%Y-%m-%dT%H:%M:%SZ)
W=$(body7 | sed -n 's/^Written: //p')
if [ "$W" != 2026-09-26T09:00:00Z ] && ! [ "$W" \< "$BEFORE" ] && ! [ "$AFTER" \< "$W" ]; then
    ok "the written body carries now, not the body's own time"
else
    bad "the written body carries now, not the body's own time" "$BEFORE <= $W <= $AFTER"
fi
eq "only the Written: line differs from the body given" "$(grep -v '^Written: ' "$T/new.md")" "$(body7 | grep -v '^Written: ')"
# The same body again: the live record now carries the first write's time, so
# a body still edited from 09:00 would lose that write.
reset_calls
bash "$WR" "${RM[@]}" --body-file "$T/new.md" >/dev/null 2>"$T/err"; eq "a body edited from an older version is refused (record-changed)" 12 $?
grep -q "record-changed" "$T/err" && ok "the refusal names record-changed" || bad "the refusal names record-changed" "$(cat "$T/err")"
grep -q '^issue edit' "$GH_DB.calls" && bad "a refused write edits nothing" "$(calls)" || ok "a refused write edits nothing"
seed_rm
render "$NEWJ" issue 2099-01-01T00:00:00Z > "$T/future.md"
bash "$WR" "${RM[@]}" --body-file "$T/future.md" >/dev/null 2>&1; eq "a body with a Written: the live record never carried is refused" 12 $?
seed_rm; db '.issues[0].body = $b' --arg b "$(printf '%s\n\nA line a person added.\n' "$OLD")"
bash "$WR" "${RM[@]}" --body-file "$T/new.md" >/dev/null 2>&1; eq "a live body a person edited out of canonical form is refused as changed" 12 $?

echo "== repository visibility =="
seed_rm
render "$(printf '%s' "$NEWJ" | jq -c '.holdings[0].repo = "acme/secret"')" issue > "$T/priv.md"
bash "$WR" "${RM[@]}" --body-file "$T/priv.md" >/dev/null 2>"$T/err"; rc=$?
eq "a private Holdings repo from a public host is refused" 65 "$rc"
grep -q 'acme/secret' "$T/err" && ok "the refusal names the repository" || bad "the refusal names the repository" "$(cat "$T/err")"
render "$(printf '%s' "$NEWJ" | jq -c '.holdings[0].pull_request = "[#3](https://github.com/acme/secret/pull/3)"')" issue > "$T/privpr.md"
bash "$WR" "${RM[@]}" --body-file "$T/privpr.md" >/dev/null 2>&1; eq "a private pull request link from a public host is refused" 65 $?
render "$(printf '%s' "$NEWJ" | jq -c '.holdings[0].repo = "acme/gadgets"')" issue > "$T/pub.md"
rebase
bash "$WR" "${RM[@]}" --body-file "$T/pub.md" >/dev/null 2>&1; eq "a public unit repository is fine" 0 $?
for tgt in 'acme/secret#3' 'https://github.com/acme/secret/issues/3' '[#3](https://github.com/acme/secret/pull/3)' \
           'merge of acme/secret#3.' 'https://github.com/acme/secret.git' 'acme/unknown#1'; do
    seed_rm
    render "$(printf '%s' "$NEWJ" | jq -c --arg t "$tgt" '.side_effects = [{action: "merge", target: $t,
        verified_head: "0123456789abcdef0123456789abcdef01234567", attempted: "2026-09-26T11:02Z", how_to_confirm: "read the pull request"}]')" issue > "$T/se.md"
    rebase
    bash "$WR" "${RM[@]}" --body-file "$T/se.md" >/dev/null 2>"$T/err"; rc=$?
    eq "a Side effects Target [$tgt] naming a private or unreadable repository is refused" 65 "$rc"
    grep -qE 'acme/(secret|unknown)' "$T/err" && ok "the refusal names it" || bad "the refusal names it" "$(cat "$T/err")"
    eq "and nothing is written" "$OLD" "$(body7)"
done
for tgt in 'acme/gadgets#4' 'https://github.com/acme/gadgets/pull/4' '#12' 'worker feature-2'; do
    seed_rm
    render "$(printf '%s' "$NEWJ" | jq -c --arg t "$tgt" '.side_effects = [{action: "merge", target: $t,
        verified_head: "0123456789abcdef0123456789abcdef01234567", attempted: "2026-09-26T11:02Z", how_to_confirm: "read the pull request"}]')" issue > "$T/se.md"
    rebase
    bash "$WR" "${RM[@]}" --body-file "$T/se.md" >/dev/null 2>"$T/err"; eq "a Side effects Target [$tgt] naming no private repository is written" 0 $?
done
seed_rm; db '.repos["acme/widgets"].private = true'
rebase
bash "$WR" "${RM[@]}" --body-file "$T/priv.md" >/dev/null 2>&1; eq "a private host may name a private repository" 0 $?
seed_rm; db '.fail = [{match: "repos/acme/widgets --jq .private", rc: 1}]'
bash "$WR" "${RM[@]}" --body-file "$T/new.md" >/dev/null 2>&1; eq "a failed visibility read exits 2" 2 $?

echo "== discipline =="
seed_ds
render "$(printf '%s' "$NEWJ" | jq -c '.scope = {kind: "discipline", name: "ci-health"}')" pr > "$T/dnew.md"
bash "$WR" "${DS[@]}" --body-file "$T/dnew.md" >/dev/null 2>"$T/err"; eq "a discipline write exits 0" 0 $?
eq "the pull request body is replaced" "$(grep -v '^Written: ' "$T/dnew.md")" "$(jq -r '.prs[0].body' "$GH_DB" | grep -v '^Written: ')"
grep -q '^pr edit 22 --repo acme/widgets --body-file' "$GH_DB.calls" && ok "the write is a pr edit" || bad "the write is a pr edit" "$(calls)"
grep -q comment "$GH_DB.calls" && bad "no comment on the pull request" "$(calls)" || ok "no comment on the pull request"
eq "the title is untouched without --end" "docs(coordinate): ci-health rotation 2026-09-22 to 2026-09-29" "$(jq -r '.prs[0].title' "$GH_DB")"
rebase
bash "$WR" "${DS[@]}" --end 2026-09-25 --body-file "$T/dnew.md" >/dev/null 2>"$T/err"; eq "--end exits 0" 0 $?
eq "--end rewrites the title's end and keeps its start" "docs(coordinate): ci-health rotation 2026-09-22 to 2026-09-25" "$(jq -r '.prs[0].title' "$GH_DB")"
reset_calls
rebase
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
S=coordinate-roadmap-plugin-system-20260926T080000Z
found_session "$S" "$(roadmap_vars plugin-system)" 7
OUT=$(bash "$WR" --session "$S" --body-file "$T/new.md" 2>"$T/err"); rc=$?
eq "the record number comes from run-facts" "0 https://github.com/acme/widgets/issues/7" "$rc $OUT"
eq "before the run's first dispatch every deferral stays" 4 "$(body7 | grep -c '^| [abcd] |')"
log_to "$S" reconcile pick_facts; log_to "$S" pick_facts pick; log_to "$S" pick dispatch_check; log_to "$S" dispatch_check dispatch
rebase
bash "$WR" --session "$S" --body-file "$T/new.md" >/dev/null 2>"$T/err"; eq "a write after the first dispatch exits 0" 0 $?
eq "filed and closed deferrals are dropped after the first dispatch" "c d" "$(body7 | sed -n 's/^| \([abcd]\) |.*/\1/p' | tr '\n' ' ' | sed 's/ $//')"
W=$(body7 | sed -n 's/^Written: //p')
[ "$W" != 2026-09-26T11:00:00Z ] && ok "the dropped render carries a new Written: time" || bad "the dropped render carries a new Written: time" "$W"
log_end "$S"
S2=coordinate-roadmap-plugin-system-20260926T090000Z
log_new "$S2" "$(roadmap_vars plugin-system)"
bash "$WR" --session "$S2" --body-file "$T/new.md" >/dev/null 2>&1; eq "a run with no found record is refused" 10 $?
log_end "$S2"
S3=coordinate-roadmap-plugin-system-20260926T100000Z
found_session "$S3" "$(roadmap_vars plugin-system)" 7
log_ev "$S3" directed_transition '{"from":"reconcile","to":"dispatch"}'
seed_rm; reset_calls
bash "$WR" --session "$S3" --body-file "$T/new.md" >/dev/null 2>&1; eq "a directed transition in the run is refused" 10 $?
eq "and nothing is read or written" "" "$(calls)"
S4=coordinate-roadmap-plugin-system-20260926T110000Z
found_session "$S4" "$(roadmap_vars plugin-system)" 7 0badbeef
bash "$WR" --session "$S4" --body-file "$T/new.md" >/dev/null 2>&1; eq "failed provenance is refused" 10 $?
bash "$WR" --session "$S" --ref 7 --body-file "$T/new.md" >/dev/null 2>&1; eq "--ref without the override flags is a usage error" 64 $?

echo "== the session must be the scope's one live session =="
# Every earlier session above is ended; each case starts from none live.
for s in "$S3" "$S4"; do log_end "$s"; done
# The plugin rewritten in place mid-run: the shipped template now compiles to
# another hash, and the run koto opened from it still writes.
SW=coordinate-roadmap-plugin-system-20260926T120000Z
found_session "$SW" "$(roadmap_vars plugin-system)" 7
opened_from "$SW" "$PLUGIN_ROOT_REAL/skills/coordinate/koto-templates/coordinate.md" '{"compiled":"as opened"}' >/dev/null
seed_rm
KOTO_COMPILED_HASH=0ddba11 bash "$WR" --session "$SW" --body-file "$T/new.md" >/dev/null 2>"$T/err"; eq "a write after the plugin is rewritten in place succeeds" 0 $?
log_end "$SW"
SF=coordinate-roadmap-plugin-system-20260926T130000Z
found_session "$SF" "$(roadmap_vars plugin-system)" 7
mkdir -p "$T/elsewhere"; cp "$PLUGIN_ROOT_REAL/skills/coordinate/koto-templates/coordinate.md" "$T/elsewhere/coordinate.md"
opened_from "$SF" "$T/elsewhere/coordinate.md" '{"compiled":"foreign"}' >/dev/null
seed_rm; reset_calls
KOTO_COMPILED_HASH=0ddba11 bash "$WR" --session "$SF" --body-file "$T/new.md" >/dev/null 2>&1; eq "a session opened from another template is still refused" 10 $?
eq "and nothing is written" "" "$(calls | grep 'edit' || true)"
log_end "$SF"
OLDS=coordinate-roadmap-plugin-system-20260927T080000Z
found_session "$OLDS" "$(roadmap_vars plugin-system)" 7
NEWS=coordinate-roadmap-plugin-system-20260927T090000Z
found_session "$NEWS" "$(roadmap_vars plugin-system)" 7
seed_rm; reset_calls
bash "$WR" --session "$OLDS" --body-file "$T/new.md" >/dev/null 2>"$T/err"; eq "two live runs of the scope refuse the write" 10 $?
grep -q 'several live' "$T/err" && ok "the refusal says several are live" || bad "the refusal says several are live" "$(cat "$T/err")"
log_end "$OLDS"
bash "$WR" --session "$OLDS" --body-file "$T/new.md" >/dev/null 2>"$T/err"; eq "an older, still provenanced run of the same record is refused" 10 $?
grep -q "$NEWS is" "$T/err" && ok "the refusal names the live session" || bad "the refusal names the live session" "$(cat "$T/err")"
eq "and nothing is read or written" "" "$(calls)"
eq "the body is untouched" "$OLD" "$(body7)"
rebase
bash "$WR" --session "$NEWS" --body-file "$T/new.md" >/dev/null 2>"$T/err"; eq "the live run writes" 0 $?
touch "$KOTO_STORE/sessions/$NEWS/.terminal"
bash "$WR" --session "$NEWS" --body-file "$T/new.md" >/dev/null 2>"$T/err"; eq "a run that reached a terminal state is refused" 10 $?
grep -q 'no live' "$T/err" && ok "the refusal says no run is live" || bad "the refusal says no run is live" "$(cat "$T/err")"
OTHER=coordinate-roadmap-other-20260927T100000Z
found_session "$OTHER" "$(roadmap_vars plugin-system)" 7
bash "$WR" --session "$OTHER" --body-file "$T/new.md" >/dev/null 2>"$T/err"; eq "a session named for another scope is refused" 10 $?
log_end "$OTHER"
# The slug is <scope>-<name> lowercased, other characters made -, squeezed,
# a trailing - trimmed: discipline CI_Health.. is discipline-ci-health.
DSESS=coordinate-discipline-ci-health-20260927T110000Z
log_new "$DSESS" "$(discipline_vars CI_Health..)"
bash "$WR" --session "$DSESS" --body-file "$T/dnew.md" >/dev/null 2>"$T/err"; rc=$?
eq "a session named by the slug passes the guard (then has no found record)" "10 no found record" "$rc $(grep -o 'no found record' "$T/err")"
DBAD=coordinate-discipline-CI_Health..-20260927T120000Z
log_new "$DBAD" "$(discipline_vars CI_Health..)"
bash "$WR" --session "$DBAD" --body-file "$T/dnew.md" >/dev/null 2>"$T/err"; rc=$?
eq "a session not named by the slug is refused by the guard" "10 not the live" "$rc $(grep -o 'not the live' "$T/err" | head -1)"
log_end "$DSESS"

echo "== the Decisions section =="
DEC='{"next": 3, "entries": [{"decision": "1", "round": "0", "question": "Ship with the mixed result?", "options": "ship\nhold", "state": "proposed",
      "source": "worker ci-pin [20260927T233505Z report 40.1]", "verdict": "", "recommendation": "", "reason": "", "context": "", "problem": "",
      "grounds": "", "target": "", "owed": "", "asked": "", "evidence": "", "outcome": "", "decided_by": "", "updated": "2026-09-27T23:40Z"},
     {"decision": "2", "round": "0", "question": "Which cache?", "options": "a\nb", "state": "proposed",
      "source": "self [20260927T233505Z raise 41]", "verdict": "", "recommendation": "", "reason": "", "context": "", "problem": "",
      "grounds": "", "target": "", "owed": "", "asked": "", "evidence": "", "outcome": "", "decided_by": "", "updated": "2026-09-27T23:40Z"}]}'
seed_rm
render "$(printf '%s' "$NEWJ" | jq -c --argjson d "$DEC" '.decisions = $d')" issue > "$T/adddec.md"
bash "$WR" "${RM[@]}" --body-file "$T/adddec.md" >/dev/null 2>"$T/err"; rc=$?
eq "a write that adds a Decisions section is refused" 65 "$rc"
grep -q 'record-decision.sh' "$T/err" && ok "the refusal names the decision writer" || bad "the refusal names the decision writer" "$(cat "$T/err")"
eq "and nothing is written" "$OLD" "$(body7)"
DECENV=$(DECISIONS_WRITER=1 bash "$WR" "${RM[@]}" --body-file "$T/adddec.md" 2>&1 >/dev/null; echo "rc=$?")
eq "DECISIONS_WRITER in the environment doesn't open the section" 65 "${DECENV##*rc=}"
OLDD=$(render "$(record_json roadmap plugin-system | jq -c --argjson d "$DEC" '.decisions = $d')" issue)
seed_rm; db '.issues[0].body = $b' --arg b "$OLDD"
render "$(printf '%s' "$NEWJ" | jq -c --argjson d "$DEC" '.decisions = $d')" issue > "$T/keepdec.md"
bash "$WR" "${RM[@]}" --body-file "$T/keepdec.md" >/dev/null 2>"$T/err"; eq "a write carrying the live Decisions section is written" 0 $?
body7 | grep -qx 'Next decision: 3' && ok "the section is kept as it was" || bad "the section is kept as it was" "$(body7 | tail -5)"
seed_rm; db '.issues[0].body = $b' --arg b "$OLDD"
bash "$WR" "${RM[@]}" --body-file "$T/new.md" >/dev/null 2>"$T/err"; eq "a write that drops the live Decisions section is refused" 65 $?
seed_rm; db '.issues[0].body = $b' --arg b "$OLDD"
render "$(printf '%s' "$NEWJ" | jq -c --argjson d "$DEC" '.decisions = $d | .decisions.entries[1].question = "Which cache backend?"')" issue > "$T/editdec.md"
bash "$WR" "${RM[@]}" --body-file "$T/editdec.md" >/dev/null 2>"$T/err"; eq "a write that edits an entry is refused" 65 $?
DECPRIV=$(printf '%s' "$DEC" | jq -c '.entries[1].question = "does acme/secret ship first?"')
seed_rm; db '.issues[0].body = $b' --arg b "$(render "$(record_json roadmap plugin-system | jq -c --argjson d "$DECPRIV" '.decisions = $d')" issue)"
render "$(printf '%s' "$NEWJ" | jq -c --argjson d "$DECPRIV" '.decisions = $d')" issue > "$T/privdec.md"
bash "$WR" "${RM[@]}" --body-file "$T/privdec.md" >/dev/null 2>"$T/err"; rc=$?
eq "a Decisions text cell naming a private repository from a public host is refused" 65 "$rc"
grep -q 'acme/secret' "$T/err" && ok "the refusal names it" || bad "the refusal names it" "$(cat "$T/err")"

echo "== the size budget =="
seed_rm
BIG=$(head -c 61000 /dev/zero | tr '\0' 'x')
render "$(printf '%s' "$NEWJ" | jq -c --arg r "$BIG" '.deferrals[3].reason = $r')" issue > "$T/big.md"
bash "$WR" "${RM[@]}" --body-file "$T/big.md" >/dev/null 2>"$T/err"; rc=$?
eq "a body over the 60,000-byte budget is refused as record-full" 13 "$rc"
grep -q 'record-full' "$T/err" && ok "the refusal says record-full" || bad "the refusal says record-full" "$(cat "$T/err")"
eq "and nothing is written" "$OLD" "$(body7)"

done_tests record-write
