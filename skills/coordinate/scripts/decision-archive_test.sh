#!/usr/bin/env bash
# decision-archive_test.sh -- settled decisions leaving a full record body
# (shirabe#827): decision-next.sh archiving before it routes, and
# record-decision.sh --archive and the restore of an archived entry, against
# the gh and koto stand-ins.
#
# Covers: a record filled past the guard with an earlier run's settled entries,
# whose next owed write is routed and succeeds with the body under the guard;
# every archived row readable verbatim from the record's `decisions` entries,
# through record-append.sh's escaping (`@`, `&`, `|`, `<`, a backslash, a line
# break); what stays in the body (an unsettled entry, one owed a reply) and
# what leaves (a settled entry whose Source or Evidence carries this run's
# stamp, the stamp itself kept on the section's kept-stamps line); Next
# decision and the Written: line; a run whose own settled entries fill the
# record archiving them and staying under the guard, the rules still reading
# its stamps from the kept line (and owing the write again without it); a
# restarted run whose --owed reading is `archive` before anything else, which
# then archives and finds nothing owed, read over the caller's --parsed record
# as well as its own; --owed writing nothing; a record under
# the guard left alone; a record full of what can't move still record-full;
# --archive's refusals; evidence, an answer and a
# citation on an archived entry restoring it in the same write, and an archive
# entry gone from the session never restoring one, and a restored entry's
# kept stamps going back to its row; the Archived and kept-stamps lines'
# grammar in the codec. The record is the run's session's: its body is the
# render record-source.sh --show prints, the archive a session entry and the
# section's Archived line in record/decisions, nothing written on GitHub.
#
# Usage: bash skills/coordinate/scripts/decision-archive_test.sh
set -uo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
command -v jq >/dev/null 2>&1 || { echo "SKIP: jq not on PATH"; exit 0; }
. "$HERE/testdata/test-lib.sh"
RD="$HERE/record-decision.sh"
DN="$HERE/decision-next.sh"
RA="$HERE/record-append.sh"
CL="$HERE/coord-log.sh"
RUN=20260926T080000Z
OLD=20260925T080000Z
GUARD=$((60000 - 4096))

# --- fixtures ----------------------------------------------------------------------

# A question long enough that a few dozen settled rows fill the body, holding
# every character the body and an entry encode.
# span <from> <to>: the numbers between, space-separated (no seq on the suite's PATH).
span() { local i out=; for ((i = $1; i <= $2; i++)); do out="$out${out:+ }$i"; done; printf '%s' "$out"; }
PAD=; for i in $(span 1 18); do PAD="$PAD${PAD:+ }the migration and the format ship together"; done
SETTLED() { # SETTLED <n> [jq merge]: an earlier run's settled entry that owes nothing
    local merge=${2-}
    [ -n "$merge" ] || merge='{}'
    jq -nc --arg n "$1" --arg pad "$PAD" --arg old "$OLD" '{decision: $n, round: "1",
        question: "Ship @alice'"'"'s migration & the a|b <b>format</b> with C:\\path first? \($pad)",
        options: "ship now -- users get the format this week\nwait -- one upgrade carries both",
        state: "settled", source: "worker w\($n) [\($old) report \($n).1]", verdict: "settle",
        evidence: "2026-09-25T09:00Z worker w\($n) [\($old) wait \($n)]: the check came back & green",
        outcome: "wait; reason: one upgrade @carol can review", decided_by: "the coordinator",
        updated: "2026-09-25T10:00Z"}' | jq -c ". + ($merge)"
}
E() { # E <n> <state> [jq merge]: a short entry
    local merge=${3-}
    [ -n "$merge" ] || merge='{}'
    jq -nc --arg n "$1" --arg s "$2" '{decision: $n, round: "0", question: "Pin the plugin?",
        options: "pin -- freezes a version\nfloat -- takes fixes", state: $s,
        source: "self [20260925T080000Z raise \($n)]", updated: "2026-09-26T07:00Z"}' | jq -c ". + ($merge)"
}
# settled_run <from> <to>: SETTLED entries <from>..<to> as a JSON array body
settled_run() { local i out=""; for i in $(span "$1" "$2"); do out="$out${out:+, }$(SETTLED "$i")"; done; printf '%s' "$out"; }
FULL=$(settled_run 1 46)

# setup <entries-json-array> [next] [session-run] [jq edit]: a fresh session
# that found its record, the record holding them with the edit applied. Sets S.
setup() {
    rm -rf "$KOTO_STORE/sessions" "$KOTO_STORE/context"; mkdir -p "$KOTO_STORE/sessions"
    db_init
    S="coordinate-roadmap-feat-${3:-$RUN}"
    found_session "$S" "$(roadmap_vars feat)"
    seed_session "$S" "$(record_json roadmap feat | jq -c --argjson e "$1" --argjson n "${2:-60}" '.decisions = {next: $n, entries: $e}' | jq -c "${4:-.}")"
    LAST=reconcile
}
to() { log_to "$S" "$LAST" "$1"; LAST=$1; }
route() { # route <token> <state>: decision_next routes <token> to <state>
    to decision_next
    log_capture "$S" DECISION_NEXT "$(bash "$CL" seal --session "$S" --state decision_next --token "$1")"
    to "$2"
}
arrive() { to wait; log_evidence "$S" wait "$2"; to "$1"; }
body() { RS_SESSION="$S" bash "$HERE/record-source.sh" --scope roadmap --name feat --repo acme/widgets --show; }
size() { body | wc -c | tr -d ' '; }
sec() { bash "$RD" --session "$S" --list; }
ent() { sec | jq -c --arg n "$1" '.entries[] | select(.decision == $n)'; }
f() { ent "$1" | jq -r --arg f "$2" '.[$f] // ""'; }
ids() { sec | jq -r '[.entries[].decision] | join(" ")'; }
archived() { sec | jq -r '(.archived // []) | map(tostring) | join(" ")'; }
kept() { body | grep '^Stamps kept for run ' ; }
# comments: the archive entries the session holds.
comments() { bash "$RA" --session "$S" --list | jq '[.[] | select(.kind == "decisions")] | length'; }
rd() { OUT=$(bash "$RD" --session "$S" "$@" 2>"$T/err"); RC=$?; }
dn() { OUT=$(bash "$DN" --session "$S" "$@" 2>"$T/err"); RC=$?; }
word() { dn; printf '%s' "${OUT%% sealed:*}"; }
# The rows the record's `decisions` entries hold, parsed back, one per line.
archive_rows() {
    bash "$RA" --session "$S" --list | jq -c -L "$HERE" 'include "record-codec"; .[] | select(.kind == "decisions") | .text | d_archive_rows[]'
}
wrote() { if [ "$RC" = 0 ]; then ok "$1"; else bad "$1" "exit $RC: $(cat "$T/err")"; fi; }

# --- the full record -----------------------------------------------------------------

echo "== a record filled past the guard =="
DONE='outcome: "pin; reason: r", decided_by: "the coordinator"'
STAY="$(E 50 proposed), $(E 52 settled "{$DONE, source: \"self [$RUN raise 4]\"}"), \
$(E 53 settled "{$DONE, evidence: \"2026-09-26T09:00Z the coordinator [$RUN hold 5]: holding: the cap\"}")"
setup "[$FULL, $STAY]"
BEFORE_SIZE=$(size)
[ "$BEFORE_SIZE" -gt "$GUARD" ] && [ "$BEFORE_SIZE" -le 60000 ] && ok "the fixture is past the guard and under the budget ($BEFORE_SIZE bytes)" \
    || bad "the fixture is past the guard and under the budget" "$BEFORE_SIZE bytes"
sec | jq -c '.entries[] | select(.state == "settled" and (.owed // "") == "")' > "$T/before.jsonl"
WRITTEN_BEFORE=$(body | grep '^Written: ')
to decision_next
eq "the owed take is routed, not record-full" "take 50" "$(word)"
[ "$(size)" -le "$GUARD" ] && ok "  ... the body is under the guard after the archive ($(size) bytes)" || bad "  ... the body is under the guard after the archive" "$(size) bytes"
eq "  ... the settled entries left, this run's too; the unsettled one stays" "50" "$(ids)"
eq "  ... the Archived line names them" "$(span 1 46) 52 53" "$(archived)"
eq "  ... this run's stamps on them stay, and no other run's" "Stamps kept for run $RUN: 52 raise 4, 53 hold 5" "$(kept)"
body | grep -qx "Archived: 1-46, 52-53 (settled; each kept verbatim in a decisions entry on this record)" \
    && ok "  ... rendered as ranges in the body" || bad "  ... rendered as ranges in the body" "$(body | grep '^Archived' )"
eq "  ... Next decision unchanged" 60 "$(sec | jq .next)"
[ "$(body | grep '^Written: ')" != "$WRITTEN_BEFORE" ] && ok "  ... the write core stamped its own Written: time" || bad "  ... the write core stamped its own Written: time" "$WRITTEN_BEFORE"
archive_rows > "$T/after.jsonl"
eq "every archived entry is readable from the record's decisions entries, verbatim" \
    "$(jq -cS . "$T/before.jsonl")" "$(jq -cS . "$T/after.jsonl")"
eq "  ... a question kept to the byte through the entry's escaping" \
    "Ship @alice's migration & the a|b <b>format</b> with C:\\path first? $PAD" "$(jq -r 'select(.decision == "7") | .question' "$T/after.jsonl")"
eq "  ... the options' line break kept" "$(printf 'ship now -- users get the format this week\nwait -- one upgrade carries both')" \
    "$(jq -r 'select(.decision == "7") | .options' "$T/after.jsonl")"
route "take 50" decision_take
rd --take
wrote "the next owed decision write succeeds"
[ "$(size)" -le "$GUARD" ] && ok "  ... and leaves the body under the guard" || bad "  ... and leaves the body under the guard" "$(size) bytes"
eq "  ... the Archived line kept through the write" "$(span 1 46) 52 53" "$(archived)"
eq "  ... and the kept stamps" "Stamps kept for run $RUN: 52 raise 4, 53 hold 5" "$(kept)"

# An entry owed a message stays, and its message is routed first.
setup "[$FULL, $(SETTLED 51 '{owed: "reply"}')]"
to decision_next
eq "an entry owed a reply stays in the body and is routed" "reply 51|51" "$(word)|$(ids)"

# A settled entry a unit is parked on stays: pick-facts.sh hands the unit its
# outcome, and an archived entry would read as gone, with no outcome.
PARK7='.work = [{item: "Feature 2", kind: "decision", who: "decision 7", next: "dispatch once decided", wakes: "0", updated: "2026-09-26T07:00Z"}]'
setup "[$FULL, $(E 50 proposed)]" 60 "$RUN" "$PARK7"
to decision_next
eq "a settled entry a unit is parked on stays in the body" "take 50|7 50" "$(word)|$(ids)"
eq "  ... with its outcome" "wait; reason: one upgrade @carol can review" "$(f 7 outcome)"
eq "  ... and every other settled entry is archived" "$(span 1 6) $(span 8 46)" "$(archived)"
[ "$(size)" -le "$GUARD" ] && ok "  ... under the guard ($(size) bytes)" || bad "  ... under the guard" "$(size) bytes"
# Every settled entry parked: nothing can move, so the owed write is record-full.
PARKALL=$(jq -nc --arg s "$(span 1 46)" '[$s | split(" ")[] | {item: "#\(.)", kind: "decision", who: "decision \(.)", next: "dispatch once decided", wakes: "0", updated: "2026-09-26T07:00Z"}]')
setup "[$FULL, $(E 50 proposed)]" 60 "$RUN" ".work = $PARKALL"
to decision_next
eq "a full record whose settled entries all hold a parked unit is record-full" "record-full|0" "$(word)|$(comments)"

echo "== --owed and a restarted run =="
setup "[$FULL, $(E 50 coordinator-verdict '{verdict: "hold", reason: "the cap"}')]" 60 20260927T080000Z
B=$(body)
eq "--owed pick on a full record with settled entries to move: archive" "archive" "$(bash "$DN" --session "$S" --owed pick 2>/dev/null)"
eq "--owed dispatch: archive too" "archive" "$(bash "$DN" --session "$S" --owed dispatch 2>/dev/null)"
# pick-facts.sh passes the record it already read and parsed (--parsed).
body > "$T/p.json.md"; body | bash "$HERE/record-parse.sh" > "$T/p.json"
eq "--owed pick over the caller's --parsed record: archive" "archive" "$(bash "$DN" --session "$S" --owed pick --parsed "$T/p.json" 2>/dev/null)"
eq "  ... and --owed wrote nothing" "$B|0" "$(body)|$(comments)"
to decision_next
eq "the restarted run archives at decision_next and then owes nothing" "clear" "$(word)"
[ "$(size)" -le "$GUARD" ] && ok "  ... under the guard" || bad "  ... under the guard" "$(size) bytes"
eq "  ... and --owed is none after" "none" "$(bash "$DN" --session "$S" --owed pick 2>/dev/null)"

echo "== a run whose own settled entries fill the record =="
# Every entry is this run's, and the latest evidence arrival and the latest
# raise visit were recorded on two of them: the rules read those stamps.
setup "[]" 1
to wait; log_evidence "$S" wait '{"event":"evidence","decision":"45"}'
W=$(bash "$CL" evidence --session "$S" --state wait | jq -r .seq)
to decision_evidence; to decision_next; to decision_raise
RSQ=$(bash "$CL" current --session "$S" | cut -d" " -f2)
OWN="${FULL//$OLD/$RUN}"
OWN=$(printf '[%s]' "$OWN" | jq -c --arg run "$RUN" --arg w "$W" --arg r "$RSQ" 'map(
    if .decision == "45" then .evidence += "\n2026-09-26T09:10Z dispatcher [\($run) wait \($w)]: the format slipped"
    elif .decision == "46" then .source = "self [\($run) raise \($r)]" else . end)')
seed_session "$S" "$(record_json roadmap feat | jq -c --argjson e "$OWN" '.decisions = {next: 60, entries: $e}')"
to decision_next
eq "a full record of this run's own settled entries: nothing owed after the archive" "clear" "$(word)"
[ "$(size)" -le "$GUARD" ] && ok "  ... under the guard ($(size) bytes)" || bad "  ... under the guard" "$(size) bytes"
eq "  ... every entry left the body" "" "$(ids)"
case "$(kept)" in *"45 wait $W"*"46 raise $RSQ"*) ok "  ... the stamps the rules read are kept" ;; *) bad "  ... the stamps the rules read are kept" "$(kept)" ;; esac
NOKEPT=$(body | bash "$HERE/record-parse.sh" | jq -c 'del(.decisions.kept)')
rm -rf "$T/entries.keep"; cp -R "$KOTO_STORE/context/$S/record/entries" "$T/entries.keep"
seed_session "$S" "$(printf '%s' "$NOKEPT" | jq -c 'del(.written)')" "$(printf '%s' "$NOKEPT" | jq -r .written)"
# seed_session clears record/; the archive entries go back as they were.
cp -R "$T/entries.keep" "$KOTO_STORE/context/$S/record/entries"
eq "  ... and without the kept line the evidence would be owed again: the rules read it" "unrecorded-evidence" "$(word)"
# A record full of what can't move is still record-full.
REPLY=; for i in $(span 1 46); do REPLY="$REPLY${REPLY:+, }$(SETTLED "$i" '{owed: "reply"}')"; done
setup "[$REPLY]"
to decision_next
eq "a full record whose entries all owe a reply is still record-full" "record-full" "$(word)"
eq "  ... nothing moved, nothing posted" "0" "$(comments)"

echo "== a record under the guard =="
setup "[$(settled_run 1 5), $(E 50 proposed)]"
B=$(body)
to decision_next
eq "a small record's owed write is routed" "take 50" "$(word)"
eq "  ... with nothing archived" "$B|0" "$(body)|$(comments)"
eq "--owed on a small record: the rule, not archive" "take" "$(bash "$DN" --session "$S" --owed pick 2>/dev/null)"
body > "$T/p.json.md"; body | bash "$HERE/record-parse.sh" > "$T/p.json"
eq "  ... and over a --parsed record too" "take" "$(bash "$DN" --session "$S" --owed pick --parsed "$T/p.json" 2>/dev/null)"

echo "== --archive refusals =="
setup "[$(settled_run 1 5)]"
to decision_next
rd --archive
eq "--archive under the guard is refused, the body untouched" "65|0" "$RC|$(comments)"
setup "[$REPLY]"
to decision_next
rd --archive
eq "--archive with nothing that can move is refused" "65|0" "$RC|$(comments)"
setup "[$FULL]"
to decision_take
rd --archive
eq "--archive outside decision_next is refused" "65|0" "$RC|$(comments)"

echo "== restoring an archived entry =="
setup "[$FULL, $(E 50 proposed)]"
to decision_next; word > /dev/null
ORIG=$(jq -c 'select(.decision == "7")' "$T/before.jsonl")
arrive decision_evidence '{"event":"evidence","decision":"7"}'
to decision_next
eq "evidence naming an archived entry is owed" "unrecorded-evidence" "$(word)"
to decision_evidence
rd --evidence --source dispatcher --text "the format slipped a week"
wrote "--evidence on an archived entry writes"
eq "  ... the entry is back, awaiting a verdict" "coordinator-verdict" "$(f 7 state)"
eq "  ... its question and options as they were" "$(printf '%s' "$ORIG" | jq -c '{question, options, source, round}')" "$(ent 7 | jq -c '{question, options, source, round}')"
eq "  ... its old outcome kept as evidence, the new evidence last" "previous outcome|dispatcher" \
    "$(f 7 evidence | sed -n 2p | cut -d' ' -f2-3)|$(f 7 evidence | tail -1 | cut -d' ' -f2)"
eq "  ... and it left the Archived line" "$(span 1 6) $(span 8 46)" "$(archived)"
# A restored entry of this run takes its stamps back from the kept line.
setup "[$FULL, $STAY]"
to decision_next; word > /dev/null
arrive decision_evidence '{"event":"evidence","decision":"52"}'
rd --evidence --source dispatcher --text "reopened"
wrote "--evidence on an archived entry of this run writes"
eq "  ... its row is back with its own stamp" "self [$RUN raise 4]" "$(f 52 source)"
eq "  ... and the kept line holds only the other entry's" "Stamps kept for run $RUN: 53 hold 5" "$(kept)"
# An answer re-sent for an archived entry's round adds its stamped line.
setup "[$FULL, $(E 50 proposed)]"
to decision_next; word > /dev/null
arrive decision_answer '{"event":"answer","decision":"9","round":"1"}'
rd --answer --outcome "wait" --reason "one upgrade @carol can review"
wrote "--answer on an archived entry writes"
eq "  ... restored, the answer recorded on it" "coordinator-verdict|answer for round 1: wait" "$(f 9 state)|$(f 9 evidence | tail -1 | sed 's/.*\]: //')"
# A citation in a report.
setup "[$FULL, $(E 50 proposed)]"
to decision_next; word > /dev/null
to report_questions
printf '%s' '[{"index":1,"kind":"question","text":"and the format (decision 12)?","source":"worker w1","addressed":false,"cite":12}]' > "$T/q.json"
KS=$(bash "$CL" seal --session "$S" --state report_questions --file "$T/q.json" --key coord/questions.json)
log_capture "$S" QUESTIONS "$(bash "$CL" seal --session "$S" --state report_questions --token "questions 1 keyseal:${KS#sealed:}")"
to decision_open
printf '%s' '{"1":{"question":"the format waits on the upgrade"}}' > "$T/w.json"
rd --open-from-report --text-file "$T/w.json"
wrote "--open-from-report citing an archived entry writes"
eq "  ... the cited entry is back with the citation as evidence" "coordinator-verdict|the format waits on the upgrade" \
    "$(f 12 state)|$(f 12 evidence | tail -1 | sed 's/.*\]: //')"
# An archive entry gone from the session never restores an entry.
setup "[$FULL, $(E 50 proposed)]"
to decision_next; word > /dev/null
rm -rf "$KOTO_STORE/context/$S/record/entries"
arrive decision_evidence '{"event":"evidence","decision":"7"}'
B=$(body)
rd --evidence --source dispatcher --text "late"
eq "an archive entry gone from the session restores nothing: refused, the body untouched" "65|yes" "$RC|$([ "$(body)" = "$B" ] && echo yes)"

echo "== the Archived line in the codec =="
rt() { printf '%s' "$1" | bash "$HERE/record-render.sh" --container issue --written 2026-09-26T09:00:00Z 2>"$T/err"; }
J=$(record_json roadmap feat | jq -c --argjson e "[$(E 9 proposed)]" '.decisions = {next: 10, entries: $e, archived: [8, 1, 2, 3, 5]}')
rt "$J" > "$T/r.md"
eq "an Archived line renders ascending, as ranges" "Archived: 1-3, 5, 8 (settled; each kept verbatim in a decisions entry on this record)" "$(grep '^Archived' "$T/r.md")"
eq "  ... and parses back" "[1,2,3,5,8]" "$(bash "$HERE/record-parse.sh" "$T/r.md" | jq -c .decisions.archived)"
rt "$(record_json roadmap feat | jq -c --argjson e "[$(E 9 proposed)]" '.decisions = {next: 10, entries: $e}')" > "$T/r0.md"
grep -q '^Archived' "$T/r0.md" && bad "no archive, no line" "$(cat "$T/r0.md")" || ok "no archive, no line"
eq "  ... and no key" "false" "$(bash "$HERE/record-parse.sh" "$T/r0.md" | jq -c '.decisions | has("archived")')"
rt "$(printf '%s' "$J" | jq -c '.decisions.archived = [10]')" > /dev/null
eq "an archived identifier at Next decision is refused" "1" "$([ -s "$T/err" ] && echo 1)"
rt "$(printf '%s' "$J" | jq -c '.decisions.archived = [9]')" > /dev/null
eq "an archived identifier the body still holds is refused" "1" "$([ -s "$T/err" ] && echo 1)"
sed 's/^Archived: 1-3, 5, 8/Archived: 5, 1-3, 8/' "$T/r.md" > "$T/bad.md"
bash "$HERE/record-parse.sh" "$T/bad.md" > /dev/null 2>&1
[ $? -ne 0 ] && ok "an Archived line out of order isn't canonical" || bad "an Archived line out of order isn't canonical" ""
sed 's/ (settled; each kept/ (kept/' "$T/r.md" > "$T/bad2.md"
bash "$HERE/record-parse.sh" "$T/bad2.md" > /dev/null 2>&1
[ $? -ne 0 ] && ok "an Archived line with other words is refused" || bad "an Archived line with other words is refused" ""

K=$(printf '%s' "$J" | jq -c '.decisions.kept = {run: "20260926T080000Z", stamps: [{decision: 2, kind: "raise", seq: "4", addressed: false}, {decision: 5, kind: "report", seq: "7.1", addressed: true}]}')
rt "$K" > "$T/k.md"
eq "kept stamps render on one line after Archived" "Stamps kept for run 20260926T080000Z: 2 raise 4, 5 report 7.1 addressed" "$(grep '^Stamps kept' "$T/k.md")"
eq "  ... and parse back" "$(printf '%s' "$K" | jq -cS .decisions.kept)" "$(bash "$HERE/record-parse.sh" "$T/k.md" | jq -cS .decisions.kept)"
rt "$(printf '%s' "$K" | jq -c '.decisions.kept.stamps[0].decision = 9')" > /dev/null
eq "a kept stamp of an entry that isn't archived is refused" "1" "$([ -s "$T/err" ] && echo 1)"
rt "$(printf '%s' "$K" | jq -c '.decisions.kept.stamps[0].kind = "forged"')" > /dev/null
eq "a kept stamp of another kind is refused" "1" "$([ -s "$T/err" ] && echo 1)"
sed 's/^Stamps kept for run 20260926T080000Z: 2 raise 4/Stamps kept for run 20260926T080000Z: 2 raise/' "$T/k.md" > "$T/bad3.md"
bash "$HERE/record-parse.sh" "$T/bad3.md" > /dev/null 2>&1
[ $? -ne 0 ] && ok "a kept stamp missing its sequence is refused" || bad "a kept stamp missing its sequence is refused" ""

echo "== the archive in the session =="
setup "[$FULL, $(E 50 proposed)]"
reset_calls
to decision_next
eq "the owed take is routed" "take 50" "$(word)"
eq "  ... the archive is a session entry" "decisions" \
    "$(koto context list "$S" --prefix record/entries/ | jq -r '.[0]' | xargs -I{} koto context get "$S" {} | jq -r .kind)"
eq "  ... the section's Archived line in record/decisions" "46" "$(koto context get "$S" record/decisions | jq '.archived | length')"
eq "  ... the rows read back verbatim" "$(jq -cS 'select((.decision | tonumber) <= 46)' "$T/before.jsonl")" "$(archive_rows | jq -cS .)"
eq "  ... and nothing written on GitHub" "" "$(grep -E 'comments|issue (edit|create)|--method (POST|PATCH|PUT)' "$GH_DB.calls")"

done_tests decision-archive
