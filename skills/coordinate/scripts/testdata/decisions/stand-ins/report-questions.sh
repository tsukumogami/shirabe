#!/usr/bin/env bash
# report-questions.sh -- STAND-IN for decisions-replay_engine_test.sh, until
# the coordinate-decisions plan's Issue 6 ships the real script; Issue 6
# removes it from the harness's STAND_INS.
#
# Extracts the admitted report's questions (worker_report) into the context
# key coord/questions.json, a JSON list of
#   {index, kind: "question", text, addressed}
#   {index, kind: "escalation", text, options, n, round}   a coordinator's escalation
#   {index, kind: "withdrawal", n, round}                  a coordinator's withdrawal
# The fixed first lines are honored only from a holding whose entry point is
# /shirabe:coordinate (read through record-holding.sh), and an escalation
# already opened for that holding, entry and round opens nothing. Otherwise
# every line ending in a question mark or matching the real phrasing list is
# a question, fenced and quoted lines skipped, `addressed` from the list's
# person-addressing patterns. What it doesn't do that the real script will:
# the caps, citations, the digest check, sealing the list. Those are Issue 6's.
#
# Usage: report-questions.sh --session S
set -uo pipefail
[ "${1-}" = --session ] || exit 64
SESSION=$2
HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/phrasing-lib.sh"
seal() { bash "$HERE/coord-log.sh" seal --session "$SESSION" --state report_questions --token "$1"; }
T=$(mktemp -d "${TMPDIR:-/tmp}/rq-standin.XXXXXX")
trap 'rm -rf "$T"' EXIT

koto context get "$SESSION" worker_report > "$T/report" || { seal unreadable; exit 0; }
TOPIC=$(koto context get "$SESSION" report_topic)
EP=$(bash "$HERE/record-holding.sh" --session "$SESSION" --topic "$TOPIC" --read | jq -r '.entry_point // ""')
FIRST=$(head -1 "$T/report")
store() { koto context add "$SESSION" coord/questions.json --from-file "$T/q.json" >/dev/null || exit 2; seal "$1"; exit 0; }

if [ "$EP" = /shirabe:coordinate ]; then
    case "$FIRST" in
        "Decision "*" round "*.)
            n=$(printf '%s' "$FIRST" | sed -n 's/^Decision \([0-9]*\) round \([0-9]*\)\.$/\1/p')
            r=$(printf '%s' "$FIRST" | sed -n 's/^Decision \([0-9]*\) round \([0-9]*\)\.$/\2/p')
            if bash "$HERE/record-decision.sh" --session "$SESSION" --list |
                jq -e --arg p "coordinator $TOPIC #$n round $r " 'any(.entries[]; .source | startswith($p))' >/dev/null; then
                seal none; exit 0
            fi
            # The question is the line before the options; the options are the
            # numbered lines, the recommendation's note dropped.
            awk '/^1\. /{print prev; exit} {prev=$0}' "$T/report" > "$T/question"
            sed -n 's/^[0-9][0-9]*\. //p' "$T/report" | sed 's/ (recommended: .*)$//' > "$T/options"
            jq -n --rawfile q "$T/question" --rawfile o "$T/options" --argjson n "$n" --argjson r "$r" \
                '[{index: 1, kind: "escalation", text: ($q | rtrimstr("\n")), options: ($o | split("\n") | map(select(length > 0))), n: $n, round: $r}]' > "$T/q.json"
            store questions ;;
        "Withdrawn: decision "*)
            n=$(printf '%s' "$FIRST" | sed -n 's/^Withdrawn: decision \([0-9]*\) round \([0-9]*\)\..*$/\1/p')
            r=$(printf '%s' "$FIRST" | sed -n 's/^Withdrawn: decision \([0-9]*\) round \([0-9]*\)\..*$/\2/p')
            jq -n --argjson n "$n" --argjson r "$r" '[{index: 1, kind: "withdrawal", n: $n, round: $r}]' > "$T/q.json"
            store questions ;;
    esac
fi

printf '[]\n' > "$T/q.json"
fence=0 i=0
while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in '```'*) fence=$((1 - fence)); continue ;; '>'*) continue ;; esac
    [ "$fence" = 0 ] || continue
    q=0
    case "$line" in *'?') q=1 ;; esac
    phrase_match decision "$line"; [ $? -eq 0 ] && q=1
    [ "$q" = 1 ] || continue
    a=false
    phrase_match addressed "$line"; [ $? -eq 0 ] && a=true
    i=$((i + 1))
    jq -c --arg t "$line" --argjson a "$a" --argjson i "$i" '. + [{index: $i, kind: "question", text: $t, addressed: $a}]' \
        "$T/q.json" > "$T/q2" && mv "$T/q2" "$T/q.json"
done < "$T/report"
if [ "$i" -gt 0 ]; then store questions; else seal none; fi
