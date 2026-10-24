#!/usr/bin/env bash
# state-write_test.sh -- state-write.sh replaces the whole record, in the
# coordinator's koto session, from the state file a writer hands it, and
# refuses a session that doesn't hold this scope's record, a state that breaks
# a rule, a private repository named from a public host, and a run with failed
# provenance or a directed transition.
#
# Covers: the whole-state write into the session's keys, with no GitHub write;
# --close and --body-file usage errors; --end refused at roadmap scope; a
# session holding no record or another scope's (10); a state that isn't a JSON
# object, breaks a rule of state-schema.jq or is another scope's (65); a
# private Holdings repo and a private pull request link from a public host (65)
# but not from a private host; filed and closed deferrals kept before the run's
# first dispatch and dropped after it, carried and open rows staying; every
# write carrying the script's own written time, never the state's (a future one
# included); a Side effects Target, or any other string, naming a private or
# unreadable repository (65); the session refused unless it is its scope's one
# live session (an older run of the same record, several live, a terminal run,
# another scope's name), with the slug derived as coordinate-open.sh derives
# it; the found record from run-facts; failed reads (2). The Decisions
# section: a write that adds, drops or edits it is refused (65) even with
# DECISIONS_WRITER=1 in the environment, one that carries the live section is
# written, and a Decisions text cell naming a private repository from a public
# host is refused. A state larger than 60,000 bytes is written: there is no
# size budget. Each refusal leaves the keys as they were; the section owners
# (Holds, Run) hold; a write left marked pending is record-changed; a worker
# shaped like a session id, a path or a job id, a status column and a private
# repository are refused, and a cell holding a pipe, a newline and backticks
# round-trips (PRD R6). An optional section left empty is stored as no key. A
# pushed head (PRD R17): set, kept by later writes and cleared, never in the
# state a reader is handed; and with no state file, set or cleared by
# rewriting record/holdings alone, no other key and no GitHub call touched.
#
# Usage: bash skills/coordinate/scripts/state-write_test.sh
set -uo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
command -v jq >/dev/null 2>&1 || { echo "SKIP: jq not on PATH"; exit 0; }
. "$HERE/testdata/test-lib.sh"
WR="$HERE/state-write.sh"

SR=coordinate-roadmap-plugin-system-20260926T070000Z
export RS_SESSION=$SR
RM=(--scope roadmap --name plugin-system --repo "$REPO" --skip-session-checks)
DS=(--scope discipline --name ci-health --repo "$REPO" --skip-session-checks)
OLDJ=$(record_json roadmap plugin-system)
DEFERRALS='[{"deferral":"a","reason":"r","raised":"2026-09-25T10:00Z","disposition":"filed #40"},
            {"deferral":"b","reason":"r","raised":"2026-09-25T10:00Z","disposition":"closed: done elsewhere"},
            {"deferral":"c","reason":"r","raised":"2026-09-25T10:00Z","disposition":"carried 2026-09-26T08:30Z: next week"},
            {"deferral":"d","reason":"r","raised":"2026-09-25T10:00Z","disposition":""}]'
NEWJ=$(record_json roadmap plugin-system | jq -c --argjson h "$(holding feature-2)" --argjson d "$DEFERRALS" '.holdings = [$h] | .deferrals = $d')
state_json "$NEWJ" > "$T/new.json"

# seed_rm: a fresh GitHub stand-in and the session holding the empty record,
# written at 09:00, the version every test state is edited from.
seed_rm() { db_init; seed_session "$SR" "$OLDJ"; }
# rebase: the session's record back at that version, the DB as it is.
rebase() { seed_session "$SR" "$OLDJ"; }
# reader_state [session]: the record as a reader is handed it (rs_record), in
# one compact line; nothing when it can't be read.
reader_state() {
    ( RS_SESSION=${1:-$RS_SESSION} PROG=reader SCOPE=${RSCOPE:-roadmap} NAME=${RNAME:-plugin-system}
      . "$HERE/state-common.sh"; . "$HERE/state-read.sh"; RS_RETRY_PAUSE=0
      rs_record "$T/reader" > /dev/null 2>&1 && jq -cS . "$T/reader" )
}
# cur7 [session]: the record's state without its written time.
cur7() { reader_state "$@" | jq -cS 'del(.written)'; }
written7() { reader_state "$@" | jq -r .written; }
# as_state <file>: a state file's own content in the same compact form.
as_state() { jq -cS 'del(.written)' "$1"; }
OLD=$(state_json "$OLDJ" | jq -cS 'del(.written)')
gh_writes() { grep -E 'issue (create|edit|close)|pr (create|edit|ready)|comment|--method (POST|PUT|PATCH|DELETE)' "$GH_DB.calls"; }
deferral_names() { cur7 "$@" | jq -r '[.deferrals[].deferral] | join(" ")'; }

echo "== roadmap =="
seed_rm
OUT=$(bash "$WR" "${RM[@]}" --state-file "$T/new.json" 2>"$T/err"); rc=$?
eq "a write exits 0 and prints the session holding the record" "0 $SR" "$rc $OUT"
eq "the whole record is replaced" "$(as_state "$T/new.json")" "$(cur7)"
eq "  ... in its keys" "$(printf '%s' "$NEWJ" | jq -cS .holdings)" "$(koto context get "$SR" record/holdings | jq -cS .)"
eq "nothing is written on GitHub" "" "$(gh_writes)"
eq "filed and closed deferrals stay before any dispatch" "a b c d" "$(deferral_names)"
rebase
bash "$WR" "${RM[@]}" --close --state-file "$T/new.json" >/dev/null 2>&1; eq "--close is a usage error" 64 $?
bash "$WR" "${RM[@]}" --body-file "$T/new.json" >/dev/null 2>&1; eq "--body-file, a retired flag, is a usage error" 64 $?
rm -rf "$KOTO_STORE/context/$SR"
bash "$WR" "${RM[@]}" --state-file "$T/new.json" >/dev/null 2>&1; eq "a session holding no record is refused" 10 $?
# The state is checked before the live record is read, so a malformed state is
# refused as malformed (65) even where the live read would refuse it (10).
jq -c '. + {notes: "a field no record has"}' "$T/new.json" > "$T/bad.json"
bash "$WR" "${RM[@]}" --state-file "$T/bad.json" >/dev/null 2>&1; eq "  ... but a malformed state is refused before the live read" 65 $?
seed_session "$SR" "$(record_json roadmap other)"
bash "$WR" "${RM[@]}" --state-file "$T/new.json" >/dev/null 2>&1; eq "a session holding another scope's record is refused" 10 $?
seed_rm
printf 'not json\n' > "$T/bad.json"
bash "$WR" "${RM[@]}" --state-file "$T/bad.json" >/dev/null 2>&1; eq "a state file that isn't a JSON object is refused" 65 $?
jq -c '. + {notes: "a field no record has"}' "$T/new.json" > "$T/bad.json"
bash "$WR" "${RM[@]}" --state-file "$T/bad.json" >/dev/null 2>"$T/err"; eq "a state with a field no record has is refused" 65 $?
grep -q 'refused: ' "$T/err" && ok "  ... with state-schema.jq's reason" || bad "  ... with state-schema.jq's reason" "$(cat "$T/err")"
state_json "$(record_json roadmap other)" > "$T/other.json"
bash "$WR" "${RM[@]}" --state-file "$T/other.json" >/dev/null 2>&1; eq "a state for another roadmap is refused" 65 $?
eq "refused states write nothing" "$OLD" "$(cur7)"
bash "$WR" "${RM[@]}" --end 2026-10-01 --state-file "$T/new.json" >/dev/null 2>&1; eq "--end at roadmap scope is a usage error" 64 $?
bash "$WR" "${RM[@]}" --ref 7 --state-file "$T/new.json" >/dev/null 2>&1; eq "--ref is a usage error" 64 $?

echo "== the written time is the script's own, and a stale base is refused =="
seed_rm
BEFORE=$(date -u +%Y-%m-%dT%H:%M:%SZ)
bash "$WR" "${RM[@]}" --state-file "$T/new.json" >/dev/null 2>"$T/err"; eq "a state edited from the live version is written" 0 $?
AFTER=$(date -u +%Y-%m-%dT%H:%M:%SZ)
W=$(written7)
if [ "$W" != 2026-09-26T09:00:00Z ] && ! [ "$W" \< "$BEFORE" ] && ! [ "$AFTER" \< "$W" ]; then
    ok "the written record carries now, not the state's own time"
else
    bad "the written record carries now, not the state's own time" "$BEFORE <= $W <= $AFTER"
fi
eq "  ... record/meta's own written time" "$W" "$(koto context get "$SR" record/meta | jq -r .written)"
eq "only the written time differs from the state given" "$(as_state "$T/new.json")" "$(cur7)"
# The same state again: the live record now carries the first write's time, so
# a state still edited from 09:00 would lose that write.
SNAP=$(session_snapshot "$SR")
bash "$WR" "${RM[@]}" --state-file "$T/new.json" >/dev/null 2>"$T/err"; eq "a state edited from an older version is refused (record-changed)" 12 $?
grep -q "record-changed" "$T/err" && ok "the refusal names record-changed" || bad "the refusal names record-changed" "$(cat "$T/err")"
eq "a refused write changes no key" "$SNAP" "$(session_snapshot "$SR")"
seed_rm
state_json "$NEWJ" 2099-01-01T00:00:00Z > "$T/future.json"
bash "$WR" "${RM[@]}" --state-file "$T/future.json" >/dev/null 2>&1; eq "a state with a written time the live record never carried is refused" 12 $?
jq -c 'del(.written)' "$T/new.json" > "$T/nowritten.json"
bash "$WR" "${RM[@]}" --state-file "$T/nowritten.json" >/dev/null 2>&1; eq "a state carrying no written time is refused (record-changed)" 12 $?

echo "== repository visibility =="
seed_rm
state_json "$(printf '%s' "$NEWJ" | jq -c '.holdings[0].repo = "acme/secret"')" > "$T/priv.json"
bash "$WR" "${RM[@]}" --state-file "$T/priv.json" >/dev/null 2>"$T/err"; rc=$?
eq "a private Holdings repo from a public host is refused" 65 "$rc"
grep -q 'acme/secret' "$T/err" && ok "the refusal names the repository" || bad "the refusal names the repository" "$(cat "$T/err")"
state_json "$(printf '%s' "$NEWJ" | jq -c '.holdings[0].pull_request = "[#3](https://github.com/acme/secret/pull/3)"')" > "$T/privpr.json"
bash "$WR" "${RM[@]}" --state-file "$T/privpr.json" >/dev/null 2>&1; eq "a private pull request link from a public host is refused" 65 $?
state_json "$(printf '%s' "$NEWJ" | jq -c '.holdings[0].repo = "acme/gadgets"')" > "$T/pub.json"
rebase
bash "$WR" "${RM[@]}" --state-file "$T/pub.json" >/dev/null 2>&1; eq "a public unit repository is fine" 0 $?
for tgt in 'acme/secret#3' 'https://github.com/acme/secret/issues/3' '[#3](https://github.com/acme/secret/pull/3)' \
           'merge of acme/secret#3.' 'https://github.com/acme/secret.git' 'acme/unknown#1'; do
    seed_rm
    state_json "$(printf '%s' "$NEWJ" | jq -c --arg t "$tgt" '.side_effects = [{action: "merge", target: $t,
        verified_head: "0123456789abcdef0123456789abcdef01234567", attempted: "2026-09-26T11:02Z", how_to_confirm: "read the pull request"}]')" > "$T/se.json"
    bash "$WR" "${RM[@]}" --state-file "$T/se.json" >/dev/null 2>"$T/err"; rc=$?
    eq "a Side effects Target [$tgt] naming a private or unreadable repository is refused" 65 "$rc"
    grep -qE 'acme/(secret|unknown)' "$T/err" && ok "the refusal names it" || bad "the refusal names it" "$(cat "$T/err")"
    eq "and nothing is written" "$OLD" "$(cur7)"
done
# Any other string of the state is scanned too: a How to confirm naming a
# private repository, which no column check reads.
seed_rm
state_json "$(printf '%s' "$NEWJ" | jq -c '.side_effects = [{action: "merge", target: "acme/widgets#12",
    verified_head: "0123456789abcdef0123456789abcdef01234567", attempted: "2026-09-26T11:02Z", how_to_confirm: "read acme/secret#3 first"}]')" > "$T/se.json"
bash "$WR" "${RM[@]}" --state-file "$T/se.json" >/dev/null 2>"$T/err"; rc=$?
eq "a How to confirm naming a private repository is refused" 65 "$rc"
grep -q 'side_effects\[0\].how_to_confirm' "$T/err" && ok "  ... naming the string's place" || bad "  ... naming the string's place" "$(cat "$T/err")"
for tgt in 'acme/gadgets#4' 'https://github.com/acme/gadgets/pull/4' '#12' 'worker feature-2'; do
    seed_rm
    state_json "$(printf '%s' "$NEWJ" | jq -c --arg t "$tgt" '.side_effects = [{action: "merge", target: $t,
        verified_head: "0123456789abcdef0123456789abcdef01234567", attempted: "2026-09-26T11:02Z", how_to_confirm: "read the pull request"}]')" > "$T/se.json"
    bash "$WR" "${RM[@]}" --state-file "$T/se.json" >/dev/null 2>"$T/err"; eq "a Side effects Target [$tgt] naming no private repository is written" 0 $?
done
seed_rm; db '.repos["acme/widgets"].private = true'
bash "$WR" "${RM[@]}" --state-file "$T/priv.json" >/dev/null 2>&1; eq "a private host may name a private repository" 0 $?
seed_rm; db '.fail = [{match: "repos/acme/widgets --jq .private", rc: 1}]'
bash "$WR" "${RM[@]}" --state-file "$T/new.json" >/dev/null 2>&1; eq "a failed visibility read exits 2" 2 $?

echo "== discipline =="
SDR=coordinate-discipline-ci-health-20260926T070000Z
db_init; seed_session "$SDR" "$(record_json discipline ci-health)"
state_json "$(printf '%s' "$NEWJ" | jq -c '.scope = {kind: "discipline", name: "ci-health"}')" > "$T/dnew.json"
OUT=$(RS_SESSION=$SDR bash "$WR" "${DS[@]}" --state-file "$T/dnew.json" 2>"$T/err"); rc=$?
eq "a discipline write exits 0" "0 $SDR" "$rc $OUT"
eq "  ... into the rotation's keys" "feature-2" "$(koto context get "$SDR" record/holdings | jq -r '.[0].worker')"
eq "  ... with nothing written on GitHub" "" "$(gh_writes)"
seed_session "$SDR" "$(record_json discipline ci-health)"
RS_SESSION=$SDR bash "$WR" "${DS[@]}" --end 2026-09-25 --state-file "$T/dnew.json" >/dev/null 2>"$T/err"; eq "--end is a date at discipline scope" 0 $?
RS_SESSION=$SDR bash "$WR" "${DS[@]}" --end 2026-02-30 --state-file "$T/dnew.json" >/dev/null 2>&1; eq "an impossible --end is a usage error" 64 $?

echo "== the session: the found record, dispatch, refusals =="
S=coordinate-roadmap-plugin-system-20260926T080000Z
seed_rm; seed_session "$S" "$OLDJ"
found_session "$S" "$(roadmap_vars plugin-system)"
OUT=$(env -u RS_SESSION bash "$WR" --session "$S" --state-file "$T/new.json" 2>"$T/err"); rc=$?
eq "the run's found record is written" "0 $S" "$rc $OUT"
eq "before the run's first dispatch every deferral stays" "a b c d" "$(deferral_names "$S")"
log_to "$S" reconcile pick_facts; log_to "$S" pick_facts pick; log_to "$S" pick dispatch_check; log_to "$S" dispatch_check dispatch
seed_session "$S" "$OLDJ"
env -u RS_SESSION bash "$WR" --session "$S" --state-file "$T/new.json" >/dev/null 2>"$T/err"; eq "a write after the first dispatch exits 0" 0 $?
eq "filed and closed deferrals are dropped after the first dispatch" "c d" "$(deferral_names "$S")"
log_end "$S"
S2=coordinate-roadmap-plugin-system-20260926T090000Z
log_new "$S2" "$(roadmap_vars plugin-system)"
seed_session "$S2" "$OLDJ"
env -u RS_SESSION bash "$WR" --session "$S2" --state-file "$T/new.json" >/dev/null 2>"$T/err"; eq "a run with no found record is refused" 10 $?
grep -q 'no found record' "$T/err" && ok "  ... saying so" || bad "  ... saying so" "$(cat "$T/err")"
log_end "$S2"
S3=coordinate-roadmap-plugin-system-20260926T100000Z
found_session "$S3" "$(roadmap_vars plugin-system)"
seed_session "$S3" "$OLDJ"
log_ev "$S3" directed_transition '{"from":"reconcile","to":"dispatch"}'
reset_calls
env -u RS_SESSION bash "$WR" --session "$S3" --state-file "$T/new.json" >/dev/null 2>&1; eq "a directed transition in the run is refused" 10 $?
eq "and nothing is read or written" "" "$(calls)"
S4=coordinate-roadmap-plugin-system-20260926T110000Z
found_session "$S4" "$(roadmap_vars plugin-system)" 0badbeef
env -u RS_SESSION bash "$WR" --session "$S4" --state-file "$T/new.json" >/dev/null 2>&1; eq "failed provenance is refused" 10 $?

echo "== the session must be the scope's one live session =="
# Every earlier session above is ended; each case starts from none live.
for s in "$S3" "$S4"; do log_end "$s"; done
# The plugin rewritten in place mid-run: the shipped template now compiles to
# another hash, and the run koto opened from it still writes.
SW=coordinate-roadmap-plugin-system-20260926T120000Z
found_session "$SW" "$(roadmap_vars plugin-system)"
seed_session "$SW" "$OLDJ"
opened_from "$SW" "$PLUGIN_ROOT_REAL/skills/coordinate/koto-templates/coordinate.md" '{"compiled":"as opened"}' >/dev/null
KOTO_COMPILED_HASH=0ddba11 env -u RS_SESSION bash "$WR" --session "$SW" --state-file "$T/new.json" >/dev/null 2>"$T/err"; eq "a write after the plugin is rewritten in place succeeds" 0 $?
log_end "$SW"
SF=coordinate-roadmap-plugin-system-20260926T130000Z
found_session "$SF" "$(roadmap_vars plugin-system)"
seed_session "$SF" "$OLDJ"
mkdir -p "$T/elsewhere"; cp "$PLUGIN_ROOT_REAL/skills/coordinate/koto-templates/coordinate.md" "$T/elsewhere/coordinate.md"
opened_from "$SF" "$T/elsewhere/coordinate.md" '{"compiled":"foreign"}' >/dev/null
SNAP=$(session_snapshot "$SF")
KOTO_COMPILED_HASH=0ddba11 env -u RS_SESSION bash "$WR" --session "$SF" --state-file "$T/new.json" >/dev/null 2>&1; eq "a session opened from another template is still refused" 10 $?
eq "and nothing is written" "$SNAP" "$(session_snapshot "$SF")"
log_end "$SF"
OLDS=coordinate-roadmap-plugin-system-20260927T080000Z
found_session "$OLDS" "$(roadmap_vars plugin-system)"
seed_session "$OLDS" "$OLDJ"
NEWS=coordinate-roadmap-plugin-system-20260927T090000Z
found_session "$NEWS" "$(roadmap_vars plugin-system)"
seed_session "$NEWS" "$OLDJ"
reset_calls
env -u RS_SESSION bash "$WR" --session "$OLDS" --state-file "$T/new.json" >/dev/null 2>"$T/err"; eq "two live runs of the scope refuse the write" 10 $?
grep -q 'several live' "$T/err" && ok "the refusal says several are live" || bad "the refusal says several are live" "$(cat "$T/err")"
log_end "$OLDS"
env -u RS_SESSION bash "$WR" --session "$OLDS" --state-file "$T/new.json" >/dev/null 2>"$T/err"; eq "an older, still provenanced run of the same record is refused" 10 $?
grep -q "$NEWS is" "$T/err" && ok "the refusal names the live session" || bad "the refusal names the live session" "$(cat "$T/err")"
eq "and nothing is read or written" "" "$(calls)"
eq "the record is untouched" "$OLD" "$(cur7 "$OLDS")"
env -u RS_SESSION bash "$WR" --session "$NEWS" --state-file "$T/new.json" >/dev/null 2>"$T/err"; eq "the live run writes" 0 $?
touch "$KOTO_STORE/sessions/$NEWS/.terminal"
env -u RS_SESSION bash "$WR" --session "$NEWS" --state-file "$T/new.json" >/dev/null 2>"$T/err"; eq "a run that reached a terminal state is refused" 10 $?
grep -q 'no live' "$T/err" && ok "the refusal says no run is live" || bad "the refusal says no run is live" "$(cat "$T/err")"
OTHER=coordinate-roadmap-other-20260927T100000Z
found_session "$OTHER" "$(roadmap_vars plugin-system)"
env -u RS_SESSION bash "$WR" --session "$OTHER" --state-file "$T/new.json" >/dev/null 2>"$T/err"; eq "a session named for another scope is refused" 10 $?
log_end "$OTHER"
# The slug is <scope>-<name> lowercased, other characters made -, squeezed,
# a trailing - trimmed: discipline CI_Health.. is discipline-ci-health.
DSESS=coordinate-discipline-ci-health-20260927T110000Z
log_new "$DSESS" "$(discipline_vars CI_Health..)"
env -u RS_SESSION bash "$WR" --session "$DSESS" --state-file "$T/dnew.json" >/dev/null 2>"$T/err"; rc=$?
eq "a session named by the slug passes the guard (then has no found record)" "10 no found record" "$rc $(grep -o 'no found record' "$T/err")"
DBAD=coordinate-discipline-CI_Health..-20260927T120000Z
log_new "$DBAD" "$(discipline_vars CI_Health..)"
env -u RS_SESSION bash "$WR" --session "$DBAD" --state-file "$T/dnew.json" >/dev/null 2>"$T/err"; rc=$?
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
state_json "$(printf '%s' "$NEWJ" | jq -c --argjson d "$DEC" '.decisions = $d')" > "$T/adddec.json"
bash "$WR" "${RM[@]}" --state-file "$T/adddec.json" >/dev/null 2>"$T/err"; rc=$?
eq "a write that adds a Decisions section is refused" 65 "$rc"
grep -q 'state-decision.sh' "$T/err" && ok "the refusal names the decision writer" || bad "the refusal names the decision writer" "$(cat "$T/err")"
eq "and nothing is written" "$OLD" "$(cur7)"
DECENV=$(DECISIONS_WRITER=1 bash "$WR" "${RM[@]}" --state-file "$T/adddec.json" 2>&1 >/dev/null; echo "rc=$?")
eq "DECISIONS_WRITER in the environment doesn't open the section" 65 "${DECENV##*rc=}"
OLDDJ=$(record_json roadmap plugin-system | jq -c --argjson d "$DEC" '.decisions = $d')
seed_rm; seed_session "$SR" "$OLDDJ"
state_json "$(printf '%s' "$NEWJ" | jq -c --argjson d "$DEC" '.decisions = $d')" > "$T/keepdec.json"
bash "$WR" "${RM[@]}" --state-file "$T/keepdec.json" >/dev/null 2>"$T/err"; eq "a write carrying the live Decisions section is written" 0 $?
eq "the section is kept as it was" 3 "$(cur7 | jq -r '.decisions.next')"
seed_session "$SR" "$OLDDJ"
bash "$WR" "${RM[@]}" --state-file "$T/new.json" >/dev/null 2>"$T/err"; eq "a write that drops the live Decisions section is refused" 65 $?
state_json "$(printf '%s' "$NEWJ" | jq -c --argjson d "$DEC" '.decisions = $d | .decisions.entries[1].question = "Which cache backend?"')" > "$T/editdec.json"
bash "$WR" "${RM[@]}" --state-file "$T/editdec.json" >/dev/null 2>"$T/err"; eq "a write that edits an entry is refused" 65 $?
DECPROSE=$(printf '%s' "$DEC" | jq -c '.entries[1].question = "does the and/or rule hold for CI/CD, n/a elsewhere, and acme/secret?"')
seed_rm; seed_session "$SR" "$(record_json roadmap plugin-system | jq -c --argjson d "$DECPROSE" '.decisions = $d')"
state_json "$(printf '%s' "$NEWJ" | jq -c --argjson d "$DECPROSE" '.decisions = $d')" > "$T/prose.json"
reset_calls
bash "$WR" "${RM[@]}" --state-file "$T/prose.json" >/dev/null 2>"$T/err"
eq "a word/word in a Decisions question is prose, not a repository" 0 "$?"
calls | grep -Eq 'repos/(and/or|CI/CD|n/a|acme/secret)' && bad "prose makes no repository read" "$(calls | grep repos/)" || ok "prose makes no repository read"
DECPRIV=$(printf '%s' "$DEC" | jq -c '.entries[1].question = "does acme/secret#3 ship first?"')
seed_rm; seed_session "$SR" "$(record_json roadmap plugin-system | jq -c --argjson d "$DECPRIV" '.decisions = $d')"
state_json "$(printf '%s' "$NEWJ" | jq -c --argjson d "$DECPRIV" '.decisions = $d')" > "$T/privdec.json"
bash "$WR" "${RM[@]}" --state-file "$T/privdec.json" >/dev/null 2>"$T/err"; rc=$?
eq "a Decisions text cell naming a private repository from a public host is refused" 65 "$rc"
grep -q 'acme/secret' "$T/err" && ok "the refusal names it" || bad "the refusal names it" "$(cat "$T/err")"

echo "== no size budget =="
seed_rm
BIG=$(head -c 61000 /dev/zero | tr '\0' 'x')
state_json "$(printf '%s' "$NEWJ" | jq -c --arg r "$BIG" '.deferrals[3].reason = $r')" > "$T/big.json"
[ "$(wc -c < "$T/big.json" | tr -d ' ')" -gt 60000 ] && ok "the state is over 60,000 bytes" || bad "the state is over 60,000 bytes" ""
bash "$WR" "${RM[@]}" --state-file "$T/big.json" >/dev/null 2>"$T/err"; rc=$?
eq "a state over 60,000 bytes is written" 0 "$rc"
eq "  ... whole" 61000 "$(koto context get "$SR" record/deferrals | jq -r '.[3].reason | length')"

echo "== an empty optional section is no key =="
seed_rm
jq -c '.holds = [] | .run = [] | .work = [] | .decisions = {next: 1, entries: []}' "$T/new.json" > "$T/empties.json"
bash "$WR" "${RM[@]}" --state-file "$T/empties.json" >/dev/null 2>"$T/err"; eq "a state with empty optional sections is written" 0 $?
eq "  ... and the session holds no key for them" "" \
    "$(ls "$KOTO_STORE/context/$SR/record" | grep -xE 'holds|run|work|decisions' | tr '\n' ' ')"

echo "== the section owners =="
seed_rm
bash "$WR" "${RM[@]}" --state-file "$T/new.json" >/dev/null 2>"$T/err"
SNAP=$(session_snapshot "$SR")
reader_state > "$T/cur.json"
jq -c '.holds = [{hold: "after-release", on: "acme/widgets#12", until: "lifted", set_by: "the human", set: "2026-09-29T20:30Z", lifted: ""}]' "$T/cur.json" > "$T/hold.json"
bash "$WR" "${RM[@]}" --state-file "$T/hold.json" >/dev/null 2>"$T/err"; rc=$?
eq "state-write.sh changing record/holds is refused (not its key)" 65 "$rc"
grep -q 'Holds section changes only through state-hold.sh' "$T/err" && ok "  ... by the Holds owner check" || bad "  ... by the Holds owner check" "$(cat "$T/err")"
eq "  ... and changes no key" "$SNAP" "$(session_snapshot "$SR")"
# The hold writer's own flags (HOLDS_WRITER, as state-hold.sh sets them), on a
# state that also changes the Run section: record/run isn't the hold writer's key.
sed -e 's|^\. "\$HERE/state-write-core.sh"$|. "$HERE/state-write-core.sh"; HOLDS_WRITER=1|' -e "s|^HERE=.*|HERE=$HERE|" "$WR" > "$T/hold-writer.sh"
grep -q 'HOLDS_WRITER=1' "$T/hold-writer.sh" && ok "the hold-writer harness opens only the Holds section" || bad "the hold-writer harness opens only the Holds section" ""
jq -c '.run = [{key: "arguments", value: "docs/roadmaps/ROADMAP-plugin-system.md", set_by: "the human", set: "2026-09-28T11:27Z"}]' "$T/cur.json" > "$T/run.json"
bash "$T/hold-writer.sh" "${RM[@]}" --state-file "$T/run.json" >/dev/null 2>"$T/err"; rc=$?
eq "the hold writer changing record/run is refused (R5)" 65 "$rc"
grep -q 'Run, Standing and Work sections change only through state-stored-set.sh' "$T/err" && ok "  ... by the Run owner check" || bad "  ... by the Run owner check" "$(cat "$T/err")"
eq "  ... and changes no key" "$SNAP" "$(session_snapshot "$SR")"
# Reversals and Side effects have no writer of their own: state-write.sh writes
# them with the state, and each lands in its key and reads back through the seam.
jq -c '.reversals = [{date: "2026-09-26T10:00Z", reversed: "merge on green", now: "hold", reason: "freeze", from: "the human"}]
    | .side_effects = [{action: "merge", target: "acme/widgets#12", verified_head: "0123456789abcdef0123456789abcdef01234567",
                        attempted: "2026-09-26T11:02Z", how_to_confirm: "read the pull request"}]' "$T/cur.json" > "$T/revse.json"
bash "$WR" "${RM[@]}" --state-file "$T/revse.json" >/dev/null 2>"$T/err"; rc=$?
eq "state-write.sh writes Reversals and Side effects" 0 "$rc"
eq "  ... into record/reversals and record/side-effects" "freeze|acme/widgets#12" \
    "$(koto context get "$SR" record/reversals | jq -r '.[0].reason')|$(koto context get "$SR" record/side-effects | jq -r '.[0].target')"
eq "  ... and read back through the seam" "merge on green|merge" \
    "$(reader_state | jq -r '"\(.reversals[0].reversed)|\(.side_effects[0].action)"')"
reader_state > "$T/cur.json"
jq -c '.holds = [{hold: "after-release", on: "acme/widgets#12", until: "lifted", set_by: "the human", set: "2026-09-29T20:30Z", lifted: ""}]' "$T/cur.json" > "$T/hold.json"
# A write part way through, left by a crash: the reader re-reads, then refuses.
# The mark is read into a file before it is written back: in one pipeline the
# write could truncate the key before the read had it.
koto context get "$SR" record/meta > "$T/meta.json"
jq -c '.pending = true' "$T/meta.json" | koto context add "$SR" record/meta
RS_RETRY_PAUSE=0 bash "$WR" "${RM[@]}" --state-file "$T/hold.json" >/dev/null 2>"$T/err"; rc=$?
eq "a record left marked pending is record-changed to a writer" 12 "$rc"
jq -c '.pending = false' "$T/meta.json" | koto context add "$SR" record/meta
# The legacy store session row an existing session holds stays through a write.
seed_session "$SR" "$(printf '%s' "$OLDJ" | jq -c '.run = [{key: "store", value: "session", set_by: "the invocation (--store session)", set: "2026-09-26T08:00Z"}]')"
state_json "$(printf '%s' "$NEWJ" | jq -c '.run = [{key: "store", value: "session", set_by: "the invocation (--store session)", set: "2026-09-26T08:00Z"}]')" > "$T/legacy.json"
bash "$WR" "${RM[@]}" --state-file "$T/legacy.json" >/dev/null 2>"$T/err"; eq "a write keeping the legacy store session row is written" 0 $?
eq "  ... and the row stays" "store=session" "$(koto context get "$SR" record/run | jq -r '.[] | "\(.key)=\(.value)"')"

echo "== the record's checks (PRD R6) =="
R6N=0
one() { # one <state-file>: the state written to a fresh session; RC its exit code
    R6N=$((R6N + 1)); R6S=coordinate-roadmap-plugin-system-20260926T15$(printf '%02d' "$R6N")00Z
    db_init; seed_session "$R6S" "$OLDJ"
    RS_SESSION=$R6S bash "$WR" "${RM[@]}" --state-file "$1" >/dev/null 2>&1
    RC=$?
}
for w in coordinate-roadmap-x-0123456789abcdef0123456789abcdef session_feature-2 workers/feature-2 48213; do
    jq -c --arg w "$w" '.holdings[0].worker = $w' "$T/new.json" > "$T/r6.json"
    one "$T/r6.json"; eq "a worker named $w is refused" 65 "$RC"
done
jq -c '.holdings[0].status = "merged"' "$T/new.json" > "$T/r6.json"
one "$T/r6.json"; eq "a status column is refused" 65 "$RC"
state_json "$(printf '%s' "$NEWJ" | jq -c '.holdings[0].repo = "acme/secret"')" > "$T/r6.json"
one "$T/r6.json"; eq "a private repository from a public host is refused" 65 "$RC"
state_json "$(printf '%s' "$NEWJ" | jq -c '.deferrals[3].reason = "x `code | pipe` y\nline two ``` z"')" > "$T/r6.json"
one "$T/r6.json"; eq "a cell with a pipe, a newline and backticks is written" 0 "$RC"
eq "  ... the cell unchanged" "x \`code | pipe\` y
line two \`\`\` z" "$(koto context get "$R6S" record/deferrals | jq -r '.[3].reason')"

echo "== a pushed head (PRD R17) =="
# A holding's last pushed head lives beside its row, never in the state a
# reader is handed: set by --pushed-head, kept by every later write.
SP=coordinate-roadmap-plugin-system-20260926T160000Z
db_init; seed_session "$SP" "$NEWJ"
spcur() { reader_state "$SP" > "$T/sp.json"; }
HEAD1=1111111111111111111111111111111111111111
spcur; RS_SESSION=$SP bash "$WR" "${RM[@]}" --state-file "$T/sp.json" --pushed-head feature-2 "$HEAD1" >/dev/null 2>"$T/err"
eq "--pushed-head sets the holding's head" "0 $HEAD1" "$? $(koto context get "$SP" record/holdings | jq -r '.[0].pushed_head')"
spcur
grep -q "$HEAD1" "$T/sp.json" && bad "  ... and the reader's state never carries it" "" || ok "  ... and the reader's state never carries it"
jq -c '.deferrals[3].reason = "r, said again"' "$T/sp.json" > "$T/sp2.json"
RS_SESSION=$SP bash "$WR" "${RM[@]}" --state-file "$T/sp2.json" >/dev/null 2>"$T/err"
eq "  ... a later write without it keeps it" "0 $HEAD1" "$? $(koto context get "$SP" record/holdings | jq -r '.[0].pushed_head')"
spcur; jq -c '.holdings[0].branch = "feat/y"' "$T/sp.json" > "$T/sp3.json"
RS_SESSION=$SP bash "$WR" "${RM[@]}" --state-file "$T/sp3.json" >/dev/null 2>"$T/err"
eq "  ... and so does a write that changes the holding's row" "0 feat/y $HEAD1" \
    "$? $(koto context get "$SP" record/holdings | jq -r '.[0] | "\(.branch) \(.pushed_head)"')"
spcur; RS_SESSION=$SP bash "$WR" "${RM[@]}" --state-file "$T/sp.json" --pushed-head feature-2 "" >/dev/null 2>"$T/err"
eq "  ... and an empty one clears it" "0 null" "$? $(koto context get "$SP" record/holdings | jq -r '.[0].pushed_head')"
spcur; RS_SESSION=$SP bash "$WR" "${RM[@]}" --state-file "$T/sp.json" --pushed-head feature-2 abc >/dev/null 2>"$T/err"
eq "a head that isn't 40 hex is refused" 65 $?
RS_SESSION=$SP bash "$WR" "${RM[@]}" --state-file "$T/sp.json" --pushed-head nobody "$HEAD1" >/dev/null 2>"$T/err"
eq "a topic no holding has is refused" 65 $?
# With no state file, --pushed-head rewrites record/holdings alone (shirabe#1094).
session_snapshot "$SP" | grep -v '^./holdings ' > "$T/sp.keys"
reset_calls
RS_SESSION=$SP bash "$WR" "${RM[@]}" --pushed-head feature-2 "$HEAD1" >/dev/null 2>"$T/err"
eq "with no state file, --pushed-head sets the head" "0 $HEAD1" "$? $(koto context get "$SP" record/holdings | jq -r '.[0].pushed_head')"
eq "  ... changing no other key, record/meta's written time included" "$(cat "$T/sp.keys")" "$(session_snapshot "$SP" | grep -v '^./holdings ')"
eq "  ... and asking GitHub for nothing" "" "$(calls)"
RS_SESSION=$SP bash "$WR" "${RM[@]}" --pushed-head feature-2 "" >/dev/null 2>"$T/err"
eq "  ... an empty one clears it" "0 null" "$? $(koto context get "$SP" record/holdings | jq -r '.[0].pushed_head')"
RS_SESSION=$SP bash "$WR" "${RM[@]}" --pushed-head feature-2 abc >/dev/null 2>"$T/err"
eq "  ... a head that isn't 40 hex is refused" 65 $?
RS_SESSION=$SP bash "$WR" "${RM[@]}" --pushed-head nobody "$HEAD1" >/dev/null 2>"$T/err"
eq "  ... and a topic no holding has" 65 $?
RS_SESSION=$SP bash "$WR" "${RM[@]}" --pushed-head feature-2 "$HEAD1" --close >/dev/null 2>"$T/err"
eq "  ... --close is usage" 64 $?
eq "no write in this suite reached GitHub" "" "$(gh_writes)"

done_tests state-write
