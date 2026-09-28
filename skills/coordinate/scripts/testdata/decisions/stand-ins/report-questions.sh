#!/usr/bin/env bash
# report-questions.sh -- STAND-IN for decisions-replay_engine_test.sh.
#
# Extracts the admitted report's questions into
# "$DEC_ST/<session>.questions.json": a coordinator escalation's fixed first
# line (only from a coordinator holding, and nothing for one already opened),
# a withdrawal's first line as evidence, and otherwise every line ending in a
# question mark or matching the real phrasing list (phrasing-lib.sh), with
# fenced and quoted lines skipped. The holding is "$DEC_ST/<session>.holding"
# (`worker <topic>` or `coordinator <topic>`). It doesn't cap, cite, seal the
# list or check a digest as the real script does. Issue 10 of the
# coordinate-decisions plan replaces it with
# skills/coordinate/scripts/report-questions.sh.
#
# Usage: report-questions.sh --session S
set -uo pipefail
[ "${1-}" = --session ] || exit 64
SESSION=$2
. "$(cd "$(dirname "$0")" && pwd)/model-lib.sh"
. "$HERE/phrasing-lib.sh"

TEXT=$(koto context get "$SESSION" worker_report) || { seal report_questions unreadable; exit 0; }
HOLD=$(cat "$DEC_ST/$SESSION.holding" 2>/dev/null || true)
KIND=${HOLD%% *} TOPIC=${HOLD#* }
[ -n "$HOLD" ] || { KIND=unknown; TOPIC=$(koto context get "$SESSION" report_topic); }
FIRST=$(printf '%s\n' "$TEXT" | head -1)
OUT="$DEC_ST/$SESSION.questions.json"

if [ "$KIND" = coordinator ]; then
    case "$FIRST" in
        "Decision "*" round "*.)
            n=$(printf '%s' "$FIRST" | sed -n 's/^Decision \([0-9]*\) round \([0-9]*\)\.$/\1/p')
            r=$(printf '%s' "$FIRST" | sed -n 's/^Decision \([0-9]*\) round \([0-9]*\)\.$/\2/p')
            src="coordinator $TOPIC #$n round $r"
            if m -e --arg s "$src" 'any(.entries[]; .source == $s)' >/dev/null; then
                seal report_questions none; exit 0
            fi
            # The question is the line before the options; the options are
            # the numbered lines, without the recommendation note.
            printf '%s\n' "$TEXT" | awk '/^1\. /{print prev; exit} {prev=$0}' > "$DEC_ST/$SESSION.q"
            printf '%s\n' "$TEXT" | sed -n 's/^[0-9][0-9]*\. //p' | sed 's/ (recommended: .*)$//' > "$DEC_ST/$SESSION.o"
            jq -n --rawfile q "$DEC_ST/$SESSION.q" --rawfile o "$DEC_ST/$SESSION.o" --arg s "$src" --argjson n "$n" --argjson r "$r" \
                '[{kind: "escalation", text: ($q | rtrimstr("\n")), options: ($o | split("\n") | map(select(length > 0))), source: $s, n: $n, round: $r}]' > "$OUT"
            seal report_questions questions; exit 0 ;;
        "Withdrawn: decision "*)
            n=$(printf '%s' "$FIRST" | sed -n 's/^Withdrawn: decision \([0-9]*\) round \([0-9]*\)\..*$/\1/p')
            r=$(printf '%s' "$FIRST" | sed -n 's/^Withdrawn: decision \([0-9]*\) round \([0-9]*\)\..*$/\2/p')
            jq -n --arg s "coordinator $TOPIC #$n round $r" --argjson n "$n" --argjson r "$r" \
                '[{kind: "withdrawal", source: $s, n: $n, round: $r}]' > "$OUT"
            seal report_questions questions; exit 0 ;;
    esac
fi

printf '[]\n' > "$OUT"
fence=0
while IFS= read -r line; do
    case "$line" in '```'*) fence=$((1 - fence)); continue ;; '>'*) continue ;; esac
    [ "$fence" = 0 ] || continue
    q=0
    case "$line" in *'?') q=1 ;; esac
    phrase_match decision "$line"; [ $? -eq 0 ] && q=1
    [ "$q" = 1 ] || continue
    a=false
    phrase_match addressed "$line"; [ $? -eq 0 ] && a=true
    jq -c --arg t "$line" --arg s "worker $TOPIC" --argjson a "$a" '. + [{kind: "question", text: $t, source: $s, addressed: $a}]' "$OUT" > "$OUT.tmp" && mv "$OUT.tmp" "$OUT"
done <<EOF
$TEXT
EOF
if [ "$(jq length "$OUT")" -gt 0 ]; then seal report_questions questions; else seal report_questions none; fi
