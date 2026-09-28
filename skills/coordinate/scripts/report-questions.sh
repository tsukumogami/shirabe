#!/usr/bin/env bash
# report-questions.sh -- extract a worker report's questions. The
# report_questions state's default action: every admitted report crosses it,
# so no question in a report reaches the dispatcher except through an entry's
# verdict.
#
# Usage: report-questions.sh --session S
#
# Reads only engine-written or gated values: the report text (the context key
# worker_report, gated at take_report), how it arrived (report_source, written
# on both edges into take_report), and report_facts' sealed REPORT capture,
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
#               has no question or options, or a report from a coordinator
#               holding that carries a digest line, the fixed answer line or
#               a withdrawal's fixed line anywhere (indented or quoted too)
#               but isn't that message exactly as rendered. It fails closed:
#               a coordinator's own report that happens to hold such a line
#               goes to the human too. It goes to the human (surface):
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
T=$(mktemp -d "${TMPDIR:-/tmp}/report-questions.XXXXXX")
trap 'rm -rf "$T"' EXIT
verdict() { bash "$HERE/coord-log.sh" seal --session "$SESSION" --state report_questions --token "$1" || lib_die2 "cannot seal the verdict"; exit 0; }
sha() { if command -v sha256sum >/dev/null 2>&1; then sha256sum | cut -d' ' -f1; else shasum -a 256 | cut -d' ' -f1; fi; }

# The report and its holding.
"$KOTO" context get "$SESSION" worker_report > "$T/report" 2> "$T/koto.err" || { cat "$T/koto.err" >&2; verdict unreadable; }
[ -s "$T/report" ] || verdict unreadable
VIA=$("$KOTO" context get "$SESSION" report_source) || lib_die2 "cannot read how the report arrived (report_source)"
# A leg report is the one line report-source.sh builds (its format is the
# contract with that script). Its reason field is where a worker's question
# goes, so that field alone is read: a reason ending in `?` is a question
# although the line ends with the pull request field. A line in any other
# shape is read whole.
if [ "$VIA" = leg ]; then
    LINE=$(cat "$T/report")
    case "$LINE" in
        "leg result: "*"; reason "*"; pull request "*)
            LINE=${LINE#*; reason }
            printf '%s\n' "${LINE%; pull request *}" > "$T/report" ;;
    esac
fi
REPORT=$(bash "$HERE/coord-log.sh" capture --session "$SESSION" --name REPORT --state report_facts)
case $? in 0) ;; 1) echo "$PROG: no sealed report_facts verdict from its latest visit" >&2; verdict unreadable ;; *) lib_die2 "cannot read the report_facts capture" ;; esac
set -f; set -- $REPORT; set +f
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
    ROW=$(bash "$HERE/record-holding.sh" --session "$SESSION" --topic "$TOPIC" --read) || lib_die2 "cannot read the holding for $TOPIC"
    EP=$(printf '%s' "$ROW" | jq -r '.entry_point // ""')
    SECTION=$(bash "$HERE/record-decision.sh" --session "$SESSION" --list) || lib_die2 "cannot read the Decisions section"
fi
# Whether an entry was opened from <source> (a source without its stamp), settled or not.
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

FIRST=$(head -1 "$T/report" | tr -d '\r')
if [ "$HOLDING" = 1 ] && [ "$EP" = /shirabe:coordinate ]; then
    # A report holding a digest line or the fixed answer line anywhere, after
    # any run of spaces, tabs and quote marks (indented, quoted, both), is an
    # escalation whatever else it says, and one holding a withdrawal's fixed
    # line anywhere is a withdrawal. One that isn't exactly as rendered (a
    # line put before or after it, CRLF line ends, a quoted or indented relay)
    # is unreadable, never read on as a worker's question with its digest
    # unchecked or its withdrawal lost. LAST is also the line the escalation
    # branch checks the digest against, so it is read here, once.
    LAST=$(awk 'NF { l = $0 } END { print l }' "$T/report")
    PFX='^[[:space:]>]*'
    if grep -qaE "$PFX(Digest: [0-9a-f]{64}|Answer naming decision [1-9][0-9]* round [1-9][0-9]* )" "$T/report"; then
        [[ $FIRST =~ $RE_ESC ]] && case "$LAST" in Digest:\ *) true ;; *) false ;; esac \
            || { echo "$PROG: the report carries an escalation that isn't as rendered" >&2; verdict unreadable; }
    elif grep -qaE "${PFX}Withdrawn: decision [1-9][0-9]* round [1-9][0-9]*\\." "$T/report"; then
        [[ $FIRST =~ $RE_WDR ]] \
            || { echo "$PROG: the report carries a withdrawal that isn't as rendered" >&2; verdict unreadable; }
    fi
    if [[ $FIRST =~ $RE_ESC ]]; then
        N=${BASH_REMATCH[1]} R=${BASH_REMATCH[2]}
        SRC="coordinator $TOPIC #$N round $R"
        # The digest covers every byte above the last line, which must be it.
        case "$LAST" in Digest:\ *) ;; *) echo "$PROG: the escalation has no digest line" >&2; verdict unreadable ;; esac
        awk -v last="$LAST" '{ lines[NR] = $0 } END { for (i = NR; i > 0 && lines[i] != last; i--); for (j = 1; j < i; j++) print lines[j] }' \
            "$T/report" > "$T/above"
        [ "$(sha < "$T/above")" = "${LAST#Digest: }" ] || { echo "$PROG: the escalation doesn't hash to its digest" >&2; verdict unreadable; }
        opened_from "$SRC" && verdict none
        # The options are read upward from the fixed answer line: the block
        # of numbered lines and their indented explanations just above it,
        # and the question the line above that block. Reading from the anchor
        # means a context or problem line that happens to start with `1. `
        # is never taken for an option. Each option is written back as
        # `<option> -- <explanation>`, the form the record keeps; the
        # recommended option's note is dropped and its option noted apart.
        : > "$T/recommended"
        awk -v n="$N" -v r="$R" -v qf="$T/question" -v recf="$T/recommended" '
            { L[NR] = $0 }
            END {
                for (a = NR; a > 0; a--) if (index(L[a], "Answer naming decision " n " round " r " ") == 1) break
                if (a == 0) exit 3
                for (i = a - 1; i > 0 && L[i] == ""; i--);
                for (s = i; s > 0 && (L[s] ~ /^[1-9][0-9]*\. / || L[s] ~ /^   [^ ]/); s--);
                s++
                if (s > i || L[s] !~ /^1\. / || s < 2 || L[s - 1] == "") exit 3
                print L[s - 1] > qf
                cur = ""; why = ""
                for (j = s; j <= i; j++) {
                    if (L[j] ~ /^[1-9][0-9]*\. /) { flush(); cur = L[j]; sub(/^[1-9][0-9]*\. /, "", cur) }
                    else { w = L[j]; sub(/^   /, "", w); why = (why == "" ? w : why " " w) }
                }
                flush()
            }
            function flush() {
                if (cur == "") return
                if (match(cur, / \(recommended: .*\)$/)) { cur = substr(cur, 1, RSTART - 1); print cur > recf }
                print cur (why != "" ? " -- " why : "")
                cur = ""; why = ""
            }' "$T/above" > "$T/options" \
            || { echo "$PROG: the escalation has no question and options above its answer line" >&2; verdict unreadable; }
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

# One awk pass classifies every line, so the cost is linear in the report and
# a long fenced log costs no more than reading it. Each line comes out as
# <line number><TAB><class><TAB><text, trimmed>:
#   item  a numbered item of the Questions part (its number dropped)
#   q     any other line ending in `?`
#   line  any other non-blank line, a candidate for the phrasing list
# Lines inside a fence (``` or ~~~, closed by the same mark) and quoted lines
# are left out. A fence that never closes hides nothing: its opener is read as
# text and so is everything after it.
awk '
    function trim(s) { sub(/^[ \t]+/, "", s); sub(/[ \t]+$/, "", s); return s }
    { sub(/\r$/, ""); L[NR] = $0 }
    END {
        open = 0
        for (i = 1; i <= NR; i++) {
            t = trim(L[i])
            if (t !~ /^(```|~~~)/) continue
            m = substr(t, 1, 3)
            if (!open) { open = i; mark = m }
            else if (m == mark) { for (j = open; j <= i; j++) F[j] = 1; open = 0 }
        }
        inpart = 0
        for (i = 1; i <= NR; i++) {
            if (F[i]) { inpart = 0; continue }
            t = trim(L[i])
            if (t ~ /^>/) { inpart = 0; continue }
            if (t == "Questions:") { inpart = 1; continue }
            if (inpart) {
                if (t ~ /^[1-9][0-9]*[.)] +[^ ]/) { sub(/^[1-9][0-9]*[.)] +/, "", t); print i "\titem\t" t; continue }
                if (t == "") continue
                inpart = 0
            }
            if (t == "") continue
            if (t ~ /\?$/) print i "\tq\t" t
            else print i "\tline\t" t
        }
    }' "$T/report" > "$T/classified" || lib_die2 "cannot read the report's lines"

# The candidates for the phrasing list, matched in one grep pass.
awk -F'\t' '$2 == "line"' "$T/classified" > "$T/cand"
cut -f3- "$T/cand" > "$T/cand.txt"
phrase_lines decision "$T/cand.txt" > "$T/cand.hit" || lib_die2 "the phrasing list can't be read"
{ awk -F'\t' '$2 != "line"' "$T/classified"
  awk 'NR == FNR { hit[$1] = 1; next } hit[FNR]' "$T/cand.hit" "$T/cand"
} | sort -n > "$T/all"

# Over the cap is decided before anything else is read. A leg report can't be
# rebriefed by message (its worker answers only through the leg), so one over
# the cap goes to the human instead.
N_ITEMS=$(wc -l < "$T/all" | tr -d ' ')
# Length is counted by jq, in characters and over the whole text after the
# class field, the same count write_list's check makes; awk would count bytes
# on some systems and stop at a tab.
if [ "$N_ITEMS" -gt "$MAX_ITEMS" ] || jq -R -s -e --argjson m "$MAX_LEN" \
        'split("\n") | map(select(length > 0) | split("\t")[2:] | join("\t")) | any(length > $m)' "$T/all" > /dev/null; then
    [ "$VIA" = leg ] && { echo "$PROG: a leg report over the cap can't be rebriefed" >&2; verdict unreadable; }
    verdict overflow
fi
[ "$N_ITEMS" -gt 0 ] || verdict none

cut -f3- "$T/all" > "$T/all.txt"
phrase_lines addressed "$T/all.txt" > "$T/addressed" || lib_die2 "the phrasing list can't be read"
# A citation is honored only on an item of the Questions part, and only for
# the reporting worker's own entry.
jq -R -s -c --rawfile addr "$T/addressed" --argjson sec "$SECTION" --arg topic "$TOPIC" --argjson holding "$HOLDING" '
    ($addr | split("\n") | map(select(length > 0) | tonumber)) as $a
    | split("\n") | map(select(length > 0)) | to_entries
    | map(.key as $k | (.value | split("\t")) as $f | ($f[2:] | join("\t")) as $text
        | ([$text | capture("\\(decision (?<n>[1-9][0-9]*)\\)") | .n] | first) as $c
        | {kind: "question", text: $text, source: "worker \($topic)",
           addressed: ($a | index($k + 1) != null),
           cite: (if $f[1] == "item" and $holding == 1 and $c != null
                     and any($sec.entries[]; .decision == $c and (.source | startswith("worker \($topic) [")))
                  then ($c | tonumber) else null end)})
    | .[]' "$T/all" > "$T/items" || lib_die2 "cannot build the list"
write_list "$T/items"
