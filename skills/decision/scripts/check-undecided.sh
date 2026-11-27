#!/usr/bin/env bash
# check-undecided.sh -- check a decision handed back undecided, before a
# caller raises its question.
#
# Usage: check-undecided.sh <session> <report_key>
#
# <report_key> is the decision's report key in <session>: `work/report.md`
# for a direct run (its key_dir is `work`) or `work/decision_<N>_report.md`
# under a parent (key_dir `work/decision-<N>`). The script reads, with
# `koto context get` and `koto context exists`, and never writes:
#
#   - the report: one block delimited by `<!-- decision:start ... -->` and
#     `<!-- decision:end -->` with status `undecided`, holding Context,
#     Question, a Recommendation with its reason, Alternatives Considered with
#     at least two entries each carrying a reason, and a non-empty What Would
#     Settle It, and no Chosen section
#     (references/decision-report-format.md, Undecided report);
#   - `<key_dir>/question.json`: the question in the form
#     `shirabe question raise` takes -- non-empty `context`, `problem`,
#     `question` and `label`, two to four `options` each with a non-empty
#     `label` and `reason`, a `ground` string and a `waiting` array;
#   - `<key_dir>/context.md`, `research.md` and `alternatives.md`: still
#     present, since an undecided decision removes no intermediate key.
#
# Exit codes:
#   0  the report and the question are whole: raise the question
#   1  a part is missing or wrong; the line printed names it
#   2  usage: wrong arguments, or a report key of neither shape
#   3  the report is settled (a confirmed or assumed block with a Chosen
#      section): the decision is complete and there is no question to raise
#   4  koto is missing or could not read the session
#
# Output is one line: `undecided: ok`, `missing: <part>: <why>`,
# `complete: <report_key> is a settled decision`, or `usage: ...`.
set -u

usage() { printf 'usage: %s\n' "$1"; exit 2; }
missing() { printf 'missing: %s: %s\n' "$1" "$2"; exit 1; }

[ "$#" -eq 2 ] || usage "check-undecided.sh <session> <report_key>"
session=$1
report_key=$2
case "$session" in
    ''|-*) usage "the session name is empty or starts with -" ;;
esac
case "$report_key" in
    work/report.md) key_dir=work ;;
    work/decision_*_report.md)
        n=${report_key#work/decision_}
        n=${n%_report.md}
        case "$n" in
            ''|*[!0-9]*) usage "report key $report_key is not work/report.md or work/decision_<N>_report.md" ;;
        esac
        key_dir="work/decision-$n"
        ;;
    *) usage "report key $report_key is not work/report.md or work/decision_<N>_report.md" ;;
esac

command -v koto >/dev/null 2>&1 || { printf 'koto: not found on PATH\n'; exit 4; }
command -v jq >/dev/null 2>&1 || { printf 'jq: not found on PATH\n'; exit 4; }

tmp=$(mktemp -d "${TMPDIR:-/tmp}/check-undecided.XXXXXX") || { printf 'koto: no scratch directory\n'; exit 4; }
trap 'rm -rf "$tmp"' EXIT

if ! koto context exists "$session" "$report_key" >/dev/null 2>&1; then
    # Tell a missing key from a session koto cannot read.
    if ! koto context list "$session" >/dev/null 2>"$tmp/err"; then
        printf 'koto: cannot read session %s\n' "$session"
        exit 4
    fi
    missing report "key $report_key is not in $session"
fi
koto context get "$session" "$report_key" > "$tmp/report.md" 2>/dev/null \
    || { printf 'koto: cannot read %s in %s\n' "$report_key" "$session"; exit 4; }

# The block: its opening line, status and body.
start=$(grep -n -m 1 '^<!-- decision:start id="[^"]*" status="[^"]*" -->$' "$tmp/report.md")
[ -n "$start" ] || missing block "no <!-- decision:start id=... status=... --> line"
start_line=${start%%:*}
status=${start#*status=\"}
status=${status%%\"*}
grep -q '^<!-- decision:end -->$' "$tmp/report.md" || missing block "no <!-- decision:end --> line"
sed -n "${start_line},\$p" "$tmp/report.md" | sed '/^<!-- decision:end -->$/q' > "$tmp/block.md"

has_chosen=0
grep -q '^\*\*Chosen' "$tmp/block.md" && has_chosen=1

case "$status" in
    undecided) ;;
    confirmed|assumed)
        if [ "$has_chosen" = 1 ]; then
            printf 'complete: %s is a settled decision (status %s)\n' "$report_key" "$status"
            exit 3
        fi
        missing status "block status is $status, not undecided"
        ;;
    *) missing status "block status is $status, not undecided" ;;
esac
[ "$has_chosen" = 0 ] || missing chosen "an undecided report holds no Chosen section"

# The text under a bold heading line, up to the next bold heading or the end
# of the block, with blank lines dropped.
section() {
    awk -v h="$1" '
        /^<!-- decision:end -->$/ { exit }
        /^\*\*[^*]+\*\*/ {
            if (inside) exit
            line = $0
            sub(/^\*\*/, "", line)
            if (index(line, h) == 1) { inside = 1; next }
        }
        inside && NF { print }
    ' "$tmp/block.md"
}
has_heading() { grep -q "^\*\*$1" "$tmp/block.md"; }

for part in Context Question; do
    has_heading "$part\*\*" || missing "$part" "no **$part** section"
    [ -n "$(section "$part**")" ] || missing "$part" "the **$part** section is empty"
done

has_heading 'Recommendation: [^*][^*]*\*\*' || missing Recommendation "no **Recommendation: <Name>** section"
[ -n "$(section "Recommendation:")" ] || missing Recommendation "the recommendation gives no reason"

has_heading 'Alternatives Considered\*\*' || missing "Alternatives Considered" "no **Alternatives Considered** section"
section "Alternatives Considered**" > "$tmp/alts"
alts=$(grep -c '^- \*\*[^*][^*]*\*\*' "$tmp/alts")
[ "$alts" -ge 2 ] || missing "Alternatives Considered" "fewer than two alternatives"
grep '^- \*\*[^*][^*]*\*\*' "$tmp/alts" > "$tmp/altlines"
if grep -qv '^- \*\*[^*][^*]*\*\*:* *[^ ]' "$tmp/altlines"; then
    missing "Alternatives Considered" "an alternative has no reason"
fi

has_heading 'What Would Settle It\*\*' || missing "What Would Settle It" "no **What Would Settle It** section"
[ -n "$(section "What Would Settle It**")" ] || missing "What Would Settle It" "the **What Would Settle It** section is empty"

# The question.
qkey="$key_dir/question.json"
koto context exists "$session" "$qkey" >/dev/null 2>&1 || missing question "key $qkey is not in $session"
koto context get "$session" "$qkey" > "$tmp/question.json" 2>/dev/null \
    || { printf 'koto: cannot read %s in %s\n' "$qkey" "$session"; exit 4; }
jq -e . "$tmp/question.json" >/dev/null 2>&1 || missing question "$qkey is not JSON"
qcheck() {
    jq -e "$1" "$tmp/question.json" >/dev/null 2>&1 || missing question "$2"
}
for f in context problem question label; do
    qcheck "(.$f | type) == \"string\" and (.$f | test(\"\\\\S\"))" "$qkey has no $f"
done
qcheck '(.options | type) == "array"' "$qkey has no options"
qcheck '(.options | length) >= 2' "$qkey has fewer than two options"
qcheck '(.options | length) <= 4' "$qkey has more than four options"
qcheck 'all(.options[]; (.label | type) == "string" and (.label | test("\\S")))' "an option in $qkey has no label"
qcheck 'all(.options[]; (.reason | type) == "string" and (.reason | test("\\S")))' "an option in $qkey has no reason"
qcheck '(.ground | type) == "string"' "$qkey has no ground"
qcheck '(.waiting | type) == "array"' "$qkey has no waiting list"

# The research, kept.
for k in context.md research.md alternatives.md; do
    koto context exists "$session" "$key_dir/$k" >/dev/null 2>&1 \
        || missing research "key $key_dir/$k is not in $session; an undecided decision removes no intermediate key"
done

printf 'undecided: ok\n'
exit 0
