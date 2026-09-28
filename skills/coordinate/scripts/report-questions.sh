#!/usr/bin/env bash
# report-questions.sh -- extract a worker report's questions. The
# report_questions state's default action: every admitted report crosses it,
# so no question in a report reaches the dispatcher except through an entry's
# verdict.
#
# Usage: report-questions.sh --session S
#
# Reads only engine-written or gated values: the report text (the context key
# worker_report, gated at take_report) and report_facts' sealed REPORT capture,
# which says whether the report has a holding (`holding <pr|none> <topic>`) or
# not (`unknown <topic>`, `refused <topic> <why>`) and names its topic. With a
# holding, the holding's row (record-holding.sh --read) gives its entry point,
# and the Decisions section (record-decision.sh --list) the entries a citation
# or a first line refers to.
#
# What it extracts, skipping lines inside fenced code (``` or ~~~) and quoted
# lines (`>`):
#   - every numbered item under a line reading exactly `Questions:`, up to the
#     first line that is neither a numbered item nor blank. An item's
#     `(decision <n>)` is its citation only when there is a holding and entry
#     <n>'s Source is `worker <topic>`; any other citation is dropped;
#   - every other line ending in `?`, and every other line the phrasing list
#     marks as a decision (phrasing-lib.sh);
#   - each marked `addressed` when the list's person-addressing patterns match.
# A coordinator's fixed first lines are honored only with a holding whose entry
# point is /shirabe:coordinate:
#   `Decision <n> round <r>.`  one escalation: the question is the line before
#       the options, each option a numbered line with its explanation on the
#       indented lines under it, kept as `<option> -- <explanation>` (the
#       recommendation's note dropped, its option kept as `recommended`). The
#       last line must be
#       `Digest: <sha256>` of every byte above it, or the report is unreadable.
#       An entry already opened from the same source gives `none`, so a re-sent
#       escalation opens nothing.
#   `Withdrawn: decision <n> round <r>.`  one withdrawal, when an entry was
#       opened from that source, settled or not: it becomes evidence there,
#       which reopens the entry; with no such entry, `none`.
#   `Answer: ...` is ordinary text.
# Without a holding every citation is dropped and no first line is honored;
# the source is the topic the report named.
#
# Each item: {index, kind: question|escalation|withdrawal, text, source,
# addressed, cite}, plus options and recommended for an escalation, and n and
# round for a coordinator's escalation or withdrawal. The source has no stamp;
# record-decision.sh --open-from-report adds it.
#
# Verdicts (sealed to this visit):
#   questions <count> keyseal:<seq>:<sha256>   the list is in coord/questions.json,
#       stored with coord-log.sh seal --file --key; keyseal is that key's seal,
#       carried in the engine-written capture so a reader can check the key
#   none        nothing to extract
#   overflow    more than 10 items, or a worker's question over 400
#               characters (a coordinator's escalation is worded by that
#               coordinator and isn't held to it); nothing stored
#   unreadable  the report can't be read, names no dispatch topic, or is a
#               coordinator's escalation that doesn't hash to its digest or
#               has no question or options. It goes to the human (surface):
#               an escalation altered in transit can be neither trusted nor
#               bounced back as a worker's rebrief
# Exit codes: 0 a verdict was printed; 2 a read failed; 64 usage.
set -uo pipefail

PROG=report-questions
HERE=$(cd "$(dirname "$0")" && pwd)
SESSION=
usage() { sed -n '/^# Usage:/,/^# Reads only/p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 64; }
while [ $# -gt 0 ]; do
    case "$1" in
        --session) [ $# -ge 2 ] || usage; SESSION=$2; shift 2 ;;
        *) usage ;;
    esac
done
[ -n "$SESSION" ] || usage
SCOPE= NAME= REPO=
. "$HERE/record-common.sh"
. "$HERE/phrasing-lib.sh"
MAX_ITEMS=10 MAX_LEN=400
# The patterns live in variables: bash 3.2 and later read an escaped pattern
# written inline in [[ =~ ]] differently.
RE_ESC='^Decision ([1-9][0-9]*) round ([1-9][0-9]*)\.$'
RE_WDR='^Withdrawn: decision ([1-9][0-9]*) round ([1-9][0-9]*)\.'
RE_CITE='\(decision ([1-9][0-9]*)\)'
RE_ITEM='^[1-9][0-9]*[.)] +(.+)$'
T=$(mktemp -d "${TMPDIR:-/tmp}/report-questions.XXXXXX")
trap 'rm -rf "$T"' EXIT
verdict() { bash "$HERE/coord-log.sh" seal --session "$SESSION" --state report_questions --token "$1" || lib_die2 "cannot seal the verdict"; exit 0; }
sha() { if command -v sha256sum >/dev/null 2>&1; then sha256sum | cut -d' ' -f1; else shasum -a 256 | cut -d' ' -f1; fi; }

# The report and its holding.
"$KOTO" context get "$SESSION" worker_report > "$T/report" 2> "$T/koto.err" || { cat "$T/koto.err" >&2; verdict unreadable; }
[ -s "$T/report" ] || verdict unreadable
REPORT=$(bash "$HERE/coord-log.sh" capture --session "$SESSION" --name REPORT --state report_facts)
case $? in 0) ;; 1) echo "$PROG: no sealed report_facts verdict from its latest visit" >&2; verdict unreadable ;; *) lib_die2 "cannot read the report_facts capture" ;; esac
set -- $REPORT
HOLDING=0
case "${1-}" in
    holding) HOLDING=1 TOPIC=${3-} ;;
    unknown|refused) TOPIC=${2-} ;;
    *) echo "$PROG: report_facts' verdict is not one this reads: ${1-}" >&2; verdict unreadable ;;
esac
# Every entry this list opens names the topic in its source, so a report that
# names none (report_facts' `unknown -`) can't be recorded.
[[ $TOPIC =~ $RE_TOPIC ]] || { echo "$PROG: the report names no dispatch topic" >&2; verdict unreadable; }
EP= SECTION='{"next":1,"entries":[]}'
if [ "$HOLDING" = 1 ]; then
    [[ $TOPIC =~ $RE_TOPIC ]] || { echo "$PROG: the holding's topic isn't a topic" >&2; verdict unreadable; }
    ROW=$(bash "$HERE/record-holding.sh" --session "$SESSION" --topic "$TOPIC" --read) || lib_die2 "cannot read the holding for $TOPIC"
    EP=$(printf '%s' "$ROW" | jq -r '.entry_point // ""')
    SECTION=$(bash "$HERE/record-decision.sh" --session "$SESSION" --list) || lib_die2 "cannot read the Decisions section"
fi
# An open entry opened from <source> (a source without its stamp).
opened_from() { printf '%s' "$SECTION" | jq -e --arg p "$1 [" 'any(.entries[]; .source | startswith($p))' >/dev/null; }

# write_list <file of JSON items, one per line>: cap, store, seal.
write_list() {
    local n
    n=$(jq -s 'length' "$1")
    [ "$n" -gt 0 ] || verdict none
    if [ "$n" -gt "$MAX_ITEMS" ] || jq -s -e --argjson m "$MAX_LEN" 'any(.[]; .kind == "question" and (.text | length) > $m)' "$1" >/dev/null; then
        verdict overflow
    fi
    jq -s 'to_entries | map(.value + {index: (.key + 1)})' "$1" > "$T/questions.json" || lib_die2 "cannot build the list"
    local keyseal
    keyseal=$(bash "$HERE/coord-log.sh" seal --session "$SESSION" --state report_questions --file "$T/questions.json" --key coord/questions.json) \
        || lib_die2 "cannot store the question list"
    [[ $keyseal =~ ^sealed:[0-9]+:[0-9a-f]{64}$ ]] || lib_die2 "the list's seal is malformed"
    verdict "questions $n keyseal:${keyseal#sealed:}"
}

# --- a coordinator's fixed first line ---------------------------------------------------

FIRST=$(head -1 "$T/report")
if [ "$HOLDING" = 1 ] && [ "$EP" = /shirabe:coordinate ]; then
    if [[ $FIRST =~ $RE_ESC ]]; then
        N=${BASH_REMATCH[1]} R=${BASH_REMATCH[2]}
        SRC="coordinator $TOPIC #$N round $R"
        # The digest covers every byte above the last line, which must be it.
        LAST=$(awk 'NF { l = $0 } END { print l }' "$T/report")
        case "$LAST" in Digest:\ *) ;; *) echo "$PROG: the escalation has no digest line" >&2; verdict unreadable ;; esac
        awk -v last="$LAST" '{ lines[NR] = $0 } END { for (i = NR; i > 0 && lines[i] != last; i--); for (j = 1; j < i; j++) print lines[j] }' \
            "$T/report" > "$T/above"
        [ "$(sha < "$T/above")" = "${LAST#Digest: }" ] || { echo "$PROG: the escalation doesn't hash to its digest" >&2; verdict unreadable; }
        opened_from "$SRC" && verdict none
        awk '/^1\. /{ print prev; exit } { prev = $0 }' "$T/above" > "$T/question"
        # Each numbered line is an option, the indented lines under it its
        # explanation; written back as `<option> -- <explanation>`, the form
        # the record keeps. The recommended option's note is dropped from it
        # and its option noted apart.
        : > "$T/recommended"
        awk -v recf="$T/recommended" '
            function flush() {
                if (cur == "") return
                if (match(cur, / \(recommended: .*\)$/)) { cur = substr(cur, 1, RSTART - 1); print cur > recf }
                print cur (why != "" ? " -- " why : "")
                cur = ""; why = ""
            }
            /^[1-9][0-9]*\. / { flush(); sub(/^[1-9][0-9]*\. /, ""); cur = $0; next }
            cur != "" && /^   [^ ]/ { w = $0; sub(/^   /, "", w); why = (why == "" ? w : why " " w); next }
            { flush() }
            END { flush() }' "$T/above" > "$T/options"
        [ -s "$T/question" ] && [ -s "$T/options" ] || { echo "$PROG: the escalation has no question or options" >&2; verdict unreadable; }
        jq -nc --rawfile q "$T/question" --rawfile o "$T/options" --rawfile rec "$T/recommended" --arg s "$SRC" --argjson n "$N" --argjson r "$R" '
            {kind: "escalation", text: ($q | rtrimstr("\n")), source: $s, addressed: false, cite: null, n: $n, round: $r,
             options: ($o | split("\n") | map(select(length > 0))),
             recommended: ($rec | split("\n") | map(select(length > 0)) | first // null)}' \
            > "$T/items"
        write_list "$T/items"
    elif [[ $FIRST =~ $RE_WDR ]]; then
        N=${BASH_REMATCH[1]} R=${BASH_REMATCH[2]}
        SRC="coordinator $TOPIC #$N round $R"
        opened_from "$SRC" || verdict none
        jq -nc --arg t "$FIRST" --arg s "$SRC" --argjson n "$N" --argjson r "$R" \
            '{kind: "withdrawal", text: $t, source: $s, addressed: false, cite: null, n: $n, round: $r}' > "$T/items"
        write_list "$T/items"
    fi
fi

# --- a worker's questions ---------------------------------------------------------------

: > "$T/items"
item() { # item <text>: one question, its citation checked, `addressed` marked
    local text=$1 cite=null a=false
    if [[ $text =~ $RE_CITE ]]; then
        if [ "$HOLDING" = 1 ] && printf '%s' "$SECTION" | jq -e --arg n "${BASH_REMATCH[1]}" --arg p "worker $TOPIC [" \
                'any(.entries[]; .decision == $n and (.source | startswith($p)))' >/dev/null; then
            cite=${BASH_REMATCH[1]}
        fi
    fi
    phrase_match addressed "$text"
    case $? in 0) a=true ;; 1) ;; *) lib_die2 "the phrasing list can't be read" ;; esac
    jq -nc --arg t "$text" --arg s "worker $TOPIC" --argjson a "$a" --argjson c "$cite" \
        '{kind: "question", text: $t, source: $s, addressed: $a, cite: $c}' >> "$T/items"
}
fence= inpart=0
while IFS= read -r line || [ -n "$line" ]; do
    line=${line%$'\r'}
    trimmed=$(printf '%s' "$line" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
    case "$trimmed" in
        '```'*|'~~~'*)
            mark=${trimmed:0:3}
            if [ -z "$fence" ]; then fence=$mark; elif [ "$fence" = "$mark" ]; then fence=; fi
            inpart=0; continue ;;
    esac
    [ -z "$fence" ] || continue
    case "$trimmed" in '>'*) inpart=0; continue ;; esac
    if [ "$trimmed" = "Questions:" ]; then inpart=1; continue; fi
    if [ "$inpart" = 1 ]; then
        if [[ $trimmed =~ $RE_ITEM ]]; then item "${BASH_REMATCH[1]}"; continue; fi
        [ -z "$trimmed" ] && continue
        inpart=0
    fi
    [ -n "$trimmed" ] || continue
    case "$trimmed" in *'?') item "$trimmed"; continue ;; esac
    phrase_match decision "$trimmed"
    case $? in 0) item "$trimmed" ;; 1) ;; *) lib_die2 "the phrasing list can't be read" ;; esac
done < "$T/report"
write_list "$T/items"
