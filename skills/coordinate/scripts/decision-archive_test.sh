#!/usr/bin/env bash
# decision-archive_test.sh -- the settled decisions a record moved from GitHub
# still carries archived (shirabe#827): decision-next.sh routing past them and
# archiving nothing, state-decision.sh restoring one, and the section's
# archived and kept-stamps fields in state-schema.jq, against the gh and koto
# stand-ins.
#
# Covers: a record whose section holds a long run of archived settled entries,
# the rows of a `decisions` entry's markdown table (a record moved from GitHub
# keeps them so); its next owed write routed and succeeding, and nothing
# archived by it or by a restart (the state, the entries and the archived list
# as they were: nothing archives an entry any more); an entry owed a reply
# still routed; every archived row readable verbatim from the `decisions`
# entries, through the table's escaping (`@`, `&`, `|`, `<`, a backslash, a
# line break); --owed reading the owed rule, never an archive move, over the
# caller's --parsed record too; --archive a usage error (64); a restarted
# run's own stamps read from the kept-stamps field (and the evidence owed again
# without it); evidence, an answer and a citation on an archived entry
# restoring it in the same write, an archive entry gone from the session never
# restoring one, and a restored entry's kept stamps going back to its row; the
# archived and kept-stamps fields' grammar in state-schema.jq (sorted, no key
# when empty, no identifier at Next decision or still held, a kept stamp of an
# archived entry in a known kind with its sequence). The record is the run's
# session's: the archive a session entry and the archived list in
# record/decisions, nothing written on GitHub.
#
# Usage: bash skills/coordinate/scripts/decision-archive_test.sh
set -uo pipefail
. "$(dirname "$0")/../../../scripts/lib/koto-test-guard.sh" || exit 1
HERE=$(cd "$(dirname "$0")" && pwd)
command -v jq >/dev/null 2>&1 || { echo "SKIP: jq not on PATH"; exit 0; }
. "$HERE/testdata/test-lib.sh"
RD="$HERE/state-decision.sh"
DN="$HERE/decision-next.sh"
RA="$HERE/state-entry.sh"
CL="$HERE/coord-log.sh"
RUN=20260926T080000Z
OLD=20260925T080000Z

# --- fixtures ----------------------------------------------------------------------

# A question holding every character a table row encodes.
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
# enc: the cell encoding a GitHub record's table row used, as dec reads it back.
ENC='def enc: gsub("&"; "&amp;") | gsub("<"; "&lt;") | gsub(">"; "&gt;") | gsub("\\\\"; "&#92;") | gsub("\\|"; "\\|") | gsub("\n"; "<br>") | gsub("@"; "&#64;");'
# table <rows-jsonl-file>: the Decisions table a GitHub record's body archived.
table() {
    jq -r -L "$HERE" "include \"state-schema\"; $ENC"'
        . as $r | decisions_cols as $c
        | "| " + ($c | map(.[1]) | join(" | ")) + " |", "|" + ($c | map("---") | join("|")) + "|",
          "| " + ($c | map($r[.[0]] // "" | enc) | join(" | ")) + " |"' "$1" \
        | awk 'NR == 1 { print; next } NR == 2 { print; next } NR % 3 == 0 { print }'
}

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
# moved <rows-jsonl-file> <entries-json-array> [jq edit]: the record a GitHub
# record moved onto its session: the rows archived (the file's entries) in a
# `decisions` entry, their identifiers in decisions.archived, the entries
# (and the edit) beside them.
moved() {
    local ids
    ids=$(jq -sc 'map(.decision | tonumber) | sort' "$1")
    setup "$2" 60 "$RUN" ".decisions.archived = $ids | ${3:-.}"
    table "$1" > "$T/table.txt"
    bash "$RA" --session "$S" --kind decisions --text-file "$T/table.txt" > /dev/null 2>"$T/err" || bad "the archive entry is written" "$(cat "$T/err")"
}
to() { log_to "$S" "$LAST" "$1"; LAST=$1; }
arrive() { to wait; log_evidence "$S" wait "$2"; to "$1"; }
# reader_state: the record as a reader is handed it (rs_record), in one compact line.
reader_state() {
    ( RS_SESSION=${1:-$S} PROG=reader SCOPE=roadmap NAME=feat
      . "$HERE/state-common.sh"; . "$HERE/state-read.sh"; RS_RETRY_PAUSE=0
      rs_record "$T/reader" > /dev/null 2>&1 && jq -cS . "$T/reader" )
}
sec() { bash "$RD" --session "$S" --list; }
ent() { sec | jq -c --arg n "$1" '.entries[] | select(.decision == $n)'; }
f() { ent "$1" | jq -r --arg f "$2" '.[$f] // ""'; }
ids() { sec | jq -r '[.entries[].decision] | join(" ")'; }
archived() { sec | jq -r '(.archived // []) | map(tostring) | join(" ")'; }
kept() { sec | jq -c '.kept // empty'; }
# comments: the archive entries the session holds.
comments() { bash "$RA" --session "$S" --list | jq '[.[] | select(.kind == "decisions")] | length'; }
rd() { OUT=$(bash "$RD" --session "$S" "$@" 2>"$T/err"); RC=$?; }
dn() { OUT=$(bash "$DN" --session "$S" "$@" 2>"$T/err"); RC=$?; }
word() { dn; printf '%s' "${OUT%% sealed:*}"; }
# The rows the record's `decisions` entries hold, parsed back, one per line,
# the columns a row leaves empty dropped.
archive_rows() {
    bash "$RA" --session "$S" --list | jq -c -L "$HERE" 'include "state-schema"; .[] | select(.kind == "decisions") | .text | d_archive_rows[] | with_entries(select(.value != ""))'
}
wrote() { if [ "$RC" = 0 ]; then ok "$1"; else bad "$1" "exit $RC: $(cat "$T/err")"; fi; }
# the rows of the settled entries 1..46, one JSON object per line, to archive
jq -c . <<< "[$FULL]" | jq -c '.[]' > "$T/old46.jsonl"
# the same rows plus two of this run's: 52 (a stamped source), 53 (a stamped evidence line)
DONE='outcome: "pin; reason: r", decided_by: "the coordinator"'
{ cat "$T/old46.jsonl"
  E 52 settled "{$DONE, source: \"self [$RUN raise 4]\"}"
  E 53 settled "{$DONE, evidence: \"2026-09-26T09:00Z the coordinator [$RUN hold 5]: holding: the cap\"}"; } > "$T/old48.jsonl"
KEPT52='{run: "'$RUN'", stamps: [{decision: 52, kind: "raise", seq: "4", addressed: false}, {decision: 53, kind: "hold", seq: "5", addressed: false}]}'

# --- the archived record --------------------------------------------------------------

echo "== a record carrying archived entries =="
moved "$T/old48.jsonl" "[$(E 50 proposed)]" ".decisions.kept = $KEPT52"
eq "the archived entries are not in the section" "50" "$(ids)"
eq "  ... the archived list names them" "$(span 1 46) 52 53" "$(archived)"
KEPT_A=$(jq -nc --arg r "$RUN" '{run: $r, stamps: [{decision: 52, kind: "raise", seq: "4", addressed: false}, {decision: 53, kind: "hold", seq: "5", addressed: false}]}')
eq "  ... the kept stamps are the run's" "$(printf %s "$KEPT_A" | jq -cS .)" "$(kept | jq -cS .)"
eq "  ... Next decision unchanged" 60 "$(sec | jq .next)"
archive_rows | jq -cS . > "$T/after.jsonl"
jq -cS 'with_entries(select(.value != ""))' "$T/old48.jsonl" > "$T/before.jsonl"
eq "every archived entry is readable from the record's decisions entries, verbatim" "$(cat "$T/before.jsonl")" "$(cat "$T/after.jsonl")"
eq "  ... a question kept to the byte through the table's escaping" \
    "Ship @alice's migration & the a|b <b>format</b> with C:\\path first? $PAD" "$(jq -r 'select(.decision == "7") | .question' "$T/after.jsonl")"
eq "  ... the options' line break kept" "$(printf 'ship now -- users get the format this week\nwait -- one upgrade carries both')" \
    "$(jq -r 'select(.decision == "7") | .options' "$T/after.jsonl")"
grep -q '&#64;' "$T/table.txt" && ! grep -q '@' "$T/table.txt" && ok "  ... the table itself holds no @ (written as &#64;)" || bad "  ... the table itself holds no @ (written as &#64;)" "$(grep -c '@' "$T/table.txt") lines hold one"

echo "== the owed write is routed past them, nothing archived =="
moved "$T/old46.jsonl" "[$(E 50 proposed)]"
reader_state > "$T/before.state"
SNAP=$(session_snapshot "$S")
to decision_next
eq "the owed take is routed" "take 50" "$(word)"
eq "  ... the state and the keys are as they were" "$SNAP" "$(session_snapshot "$S")"
eq "  ... the archived list is as it was" "$(span 1 46)" "$(archived)"
eq "  ... the entries are as they were" "50" "$(ids)"
eq "  ... and the archive holds the one entry it held" "1" "$(comments)"
log_capture "$S" DECISION_NEXT "$(bash "$CL" seal --session "$S" --state decision_next --token "take 50")"
to decision_take
WRITTEN_BEFORE=$(jq -r .written "$T/before.state")
rd --take
wrote "the owed decision write succeeds"
eq "  ... the archived list kept through the write" "$(span 1 46)" "$(archived)"
eq "  ... the entry taken" "coordinator-verdict" "$(f 50 state)"
[ "$(reader_state | jq -r .written)" != "$WRITTEN_BEFORE" ] && ok "  ... the write core stamped its own written time" || bad "  ... the write core stamped its own written time" "$WRITTEN_BEFORE"
eq "  ... and the archive still holds the rows, verbatim" "$(jq -cS 'with_entries(select(.value != ""))' "$T/old46.jsonl")" "$(archive_rows | jq -cS .)"

# A long section of settled entries in the section itself is routed too: no
# size moves anything.
setup "[$FULL, $(E 50 proposed)]"
SNAP=$(session_snapshot "$S")
to decision_next
eq "a section of 46 settled entries and an owed take: the take is routed" "take 50" "$(word)"
eq "  ... and not one entry moved" "$SNAP" "$(session_snapshot "$S")"
# An entry owed a message is routed first.
setup "[$FULL, $(SETTLED 51 '{owed: "reply"}')]"
to decision_next
eq "an entry owed a reply is routed" "reply 51" "$(word)"
# A section of entries that all owe a reply is routed like any other.
REPLY=; for i in $(span 1 46); do REPLY="$REPLY${REPLY:+, }$(SETTLED "$i" '{owed: "reply"}')"; done
setup "[$REPLY]"
to decision_next
eq "a section whose entries all owe a reply routes the lowest: not record-full" "reply 1" "$(word)"
eq "  ... nothing posted" "0" "$(comments)"

echo "== --owed and a restarted run =="
moved "$T/old46.jsonl" "[$(E 50 coordinator-verdict)]"
B=$(session_snapshot "$S")
eq "--owed pick on a record with archived entries: the rule, not archive" "verdict" "$(bash "$DN" --session "$S" --owed pick 2>/dev/null)"
eq "--owed dispatch: the rule too" "verdict" "$(bash "$DN" --session "$S" --owed dispatch 2>/dev/null)"
# pick-facts.sh passes the record it already read (--parsed).
reader_state > /dev/null
cp "$T/reader" "$T/p.json"
eq "--owed pick over the caller's --parsed record: the rule" "verdict" "$(bash "$DN" --session "$S" --owed pick --parsed "$T/p.json" 2>/dev/null)"
eq "  ... and --owed wrote nothing" "$B|1" "$(session_snapshot "$S")|$(comments)"
to decision_next
eq "the restarted run routes the verdict at decision_next" "verdict 50" "$(word)"
eq "  ... and archived nothing" "$(span 1 46)" "$(archived)"

echo "== a run whose own stamps are kept =="
# Every entry this run recorded left the section: the latest evidence arrival
# and the latest raise visit were recorded on two of them, and the rules read
# those stamps from the kept stamps.
own_log() { to wait; log_evidence "$S" wait '{"event":"evidence","decision":"45"}'; to decision_evidence; to decision_next; to decision_raise; }
setup "[]" 1
own_log
W=$(bash "$CL" evidence --session "$S" --state wait | jq -r .seq)
RSQ=$(bash "$CL" current --session "$S" | cut -d" " -f2)
OWN=$(jq -c --arg old "$OLD" --arg run "$RUN" --arg w "$W" --arg r "$RSQ" '
    if .decision == "45" then .evidence += "\n2026-09-26T09:10Z dispatcher [\($run) wait \($w)]: the format slipped"
    elif .decision == "46" then .source = "self [\($run) raise \($r)]" else . end' "$T/old46.jsonl")
printf '%s\n' "$OWN" > "$T/own.jsonl"
KEPT_OWN=$(jq -nc --arg run "$RUN" --arg w "$W" --arg r "$RSQ" '{run: $run, stamps: [{decision: 45, kind: "wait", seq: $w, addressed: false}, {decision: 46, kind: "raise", seq: $r, addressed: false}]}')
moved "$T/own.jsonl" "[]" ".decisions.kept = $KEPT_OWN"
own_log
to decision_next
eq "a section emptied into the archive: nothing owed, the kept stamps cover the run's writes" "clear" "$(word)"
eq "  ... every entry is in the archive" "" "$(ids)"
moved "$T/own.jsonl" "[]"
own_log
to decision_next
eq "  ... and without the kept stamps the evidence would be owed again: the rules read them" "unrecorded-evidence" "$(word)"

echo "== --archive is gone =="
setup "[$FULL]"
to decision_next
SNAP=$(session_snapshot "$S")
rd --archive
eq "--archive is a usage error, nothing written" "64|0|yes" "$RC|$(comments)|$([ "$(session_snapshot "$S")" = "$SNAP" ] && echo yes)"
grep -q '^Usage:' "$T/err" && ! grep -q -- '--archive ' "$T/err" && ok "  ... the usage no longer lists it" || bad "  ... the usage no longer lists it" "$(cat "$T/err")"

echo "== restoring an archived entry =="
moved "$T/old46.jsonl" "[$(E 50 proposed)]"
ORIG=$(jq -c 'select(.decision == "7")' "$T/old46.jsonl")
to decision_next; word > /dev/null
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
eq "  ... and it left the archived list" "$(span 1 6) $(span 8 46)" "$(archived)"
# A restored entry of this run takes its stamps back from the kept stamps.
moved "$T/old48.jsonl" "[$(E 50 proposed)]" ".decisions.kept = $KEPT52"
to decision_next; word > /dev/null
arrive decision_evidence '{"event":"evidence","decision":"52"}'
rd --evidence --source dispatcher --text "reopened"
wrote "--evidence on an archived entry of this run writes"
eq "  ... its row is back with its own stamp" "self [$RUN raise 4]" "$(f 52 source)"
eq "  ... and the kept stamps hold only the other entry's" \
    "$(jq -ncS --arg r "$RUN" '{run: $r, stamps: [{decision: 53, kind: "hold", seq: "5", addressed: false}]}')" "$(kept | jq -cS .)"
# An answer re-sent for an archived entry's round adds its stamped line.
moved "$T/old46.jsonl" "[$(E 50 proposed)]"
to decision_next; word > /dev/null
arrive decision_answer '{"event":"answer","decision":"9","round":"1"}'
rd --answer --outcome "wait" --reason "one upgrade @carol can review"
wrote "--answer on an archived entry writes"
eq "  ... restored, the answer recorded on it" "coordinator-verdict|answer for round 1: wait" "$(f 9 state)|$(f 9 evidence | tail -1 | sed 's/.*\]: //')"
# A citation in a report.
moved "$T/old46.jsonl" "[$(E 50 proposed)]"
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
moved "$T/old46.jsonl" "[$(E 50 proposed)]"
to decision_next; word > /dev/null
rm -rf "$KOTO_STORE/context/$S/record/entries"
arrive decision_evidence '{"event":"evidence","decision":"7"}'
SNAP=$(session_snapshot "$S")
rd --evidence --source dispatcher --text "late"
eq "an archive entry gone from the session restores nothing: refused, the keys untouched" "65|yes" "$RC|$([ "$(session_snapshot "$S")" = "$SNAP" ] && echo yes)"

echo "== the archived list and the kept stamps in the state =="
# nstate <json>: state-schema.jq's normal form of a record (failing with its reason on stderr)
nstate() { printf '%s' "$1" | jq -c -L "$HERE" 'include "state-schema"; normalize_state([])' 2>"$T/err"; }
J=$(record_json roadmap feat | jq -c --argjson e "[$(E 9 proposed)]" '.decisions = {next: 10, entries: $e, archived: [8, 1, 2, 3, 5]}')
eq "an archived list is kept ascending" "[1,2,3,5,8]" "$(nstate "$J" | jq -c .decisions.archived)"
eq "  ... a repeated identifier once" "[1,2]" "$(nstate "$(printf '%s' "$J" | jq -c '.decisions.archived = [2, 1, 2]')" | jq -c .decisions.archived)"
eq "no archive, no key" "false" "$(nstate "$(record_json roadmap feat | jq -c --argjson e "[$(E 9 proposed)]" '.decisions = {next: 10, entries: $e}')" | jq -c '.decisions | has("archived")')"
eq "an empty archived list is no key either" "false" "$(nstate "$(printf '%s' "$J" | jq -c '.decisions.archived = []')" | jq -c '.decisions | has("archived")')"
nstate "$(printf '%s' "$J" | jq -c '.decisions.archived = [10]')" > /dev/null
grep -q 'Next decision' "$T/err" && ok "an archived identifier at Next decision is refused" || bad "an archived identifier at Next decision is refused" "$(cat "$T/err")"
nstate "$(printf '%s' "$J" | jq -c '.decisions.archived = [9]')" > /dev/null
grep -q 'an identifier the section still holds' "$T/err" && ok "an archived identifier the section still holds is refused" || bad "an archived identifier the section still holds is refused" "$(cat "$T/err")"
nstate "$(printf '%s' "$J" | jq -c '.decisions.archived = ["8"]')" > /dev/null
grep -q 'not a list of identifiers' "$T/err" && ok "an archived identifier that is not a number is refused" || bad "an archived identifier that is not a number is refused" "$(cat "$T/err")"

K=$(printf '%s' "$J" | jq -c '.decisions.kept = {run: "20260926T080000Z", stamps: [{decision: 2, kind: "raise", seq: "4", addressed: false}, {decision: 5, kind: "report", seq: "7.1", addressed: true}]}')
eq "kept stamps are kept as given" "$(printf '%s' "$K" | jq -cS .decisions.kept)" "$(nstate "$K" | jq -cS .decisions.kept)"
nstate "$(printf '%s' "$K" | jq -c '.decisions.kept.stamps[0].decision = 9')" > /dev/null
grep -q "a stamp of an entry that isn't archived" "$T/err" && ok "a kept stamp of an entry that isn't archived is refused" || bad "a kept stamp of an entry that isn't archived is refused" "$(cat "$T/err")"
nstate "$(printf '%s' "$K" | jq -c '.decisions.kept.stamps[0].kind = "forged"')" > /dev/null
grep -q 'decisions.kept' "$T/err" && ok "a kept stamp of another kind is refused" || bad "a kept stamp of another kind is refused" "$(cat "$T/err")"
nstate "$(printf '%s' "$K" | jq -c '.decisions.kept.stamps[0].seq = ""')" > /dev/null
grep -q 'decisions.kept' "$T/err" && ok "a kept stamp missing its sequence is refused" || bad "a kept stamp missing its sequence is refused" "$(cat "$T/err")"
nstate "$(printf '%s' "$K" | jq -c '.decisions.kept.run = "yesterday"')" > /dev/null
grep -q 'decisions.kept' "$T/err" && ok "a kept run that isn't a run stamp is refused" || bad "a kept run that isn't a run stamp is refused" "$(cat "$T/err")"

echo "== the archive in the session =="
moved "$T/old46.jsonl" "[$(E 50 proposed)]"
reset_calls
to decision_next
eq "the owed take is routed" "take 50" "$(word)"
eq "  ... the archive is a session entry" "decisions" \
    "$(koto context list "$S" --prefix record/entries/ | jq -r '.[0]' | xargs -I{} koto context get "$S" {} | jq -r .kind)"
eq "  ... the archived list in record/decisions" "46" "$(koto context get "$S" record/decisions | jq '.archived | length')"
eq "  ... the rows read back verbatim" "$(jq -cS 'with_entries(select(.value != ""))' "$T/old46.jsonl")" "$(archive_rows | jq -cS .)"
eq "  ... and nothing written on GitHub" "" "$(grep -E 'comments|issue (edit|create)|--method (POST|PATCH|PUT)' "$GH_DB.calls")"

done_tests decision-archive
