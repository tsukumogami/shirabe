#!/usr/bin/env bash
# coord-verdict-table_test.sh -- coord-verdict.sh's word-to-code table and the
# template's arms agree.
#
# Proves: every check-state arm's code is in the table, and the word in the
# arm's comment is the table's word for that code; no word is in the table
# twice; every code in the table has
# an arm, except the two the table documents as having none here; and, for each
# group of states the table lists together, every state has an arm for every
# word of its group, except the pairs listed below. That last check is what
# catches a state whose script emits a verdict the template never routes, which
# would block it silently.
#
# Needs only awk; no koto.
# Usage: bash skills/coordinate/scripts/coord-verdict-table_test.sh
set -uo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
V="$HERE/coord-verdict.sh"
TPL="$HERE/../koto-templates/coordinate.md"
PASS=0 FAIL=0
ok()  { PASS=$((PASS + 1)); printf 'ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); printf 'FAIL %s\n%s\n' "$1" "${2-}"; }
T=$(mktemp -d "${TMPDIR:-/tmp}/verdict-table.XXXXXX")
trap 'rm -rf "$T"' EXIT

# state<TAB>word pairs with no arm on purpose. start and start_posture share a
# comment line but are two states with two word sets. record: moved is
# --verified only (verified_confirm). merge_confirm follows a merge the
# coordinator attempted, which is merged or unconfirmed, never not-merged.
# closeout-read.sh checks the title's date for the run's own rotation only.
EXCEPT='start	readable
start	unread
start_posture	active
start_posture	discipline
start_posture	not-active
record	moved
merge_confirm	not-merged
predecessor_close	title-stale'

# The table: word<TAB>code<TAB>group (the comment line above it, its state list).
table() {
awk '
    /^    # [a-z_]/ { g = $0; sub(/^    # /, "", g); sub(/ [(].*$/, "", g); sub(/, the .*$/, "", g); gsub(/ /, "", g); next }
    /waiting\|land-blocked/ { g = "" }
    {
        s = $0
        while (match(s, /[a-z][a-z-]*\) exit [0-9]+ ;;/)) {
            m = substr(s, RSTART, RLENGTH); s = substr(s, RSTART + RLENGTH)
            w = m; sub(/\).*/, "", w); c = m; sub(/^[^ ]* exit /, "", c); sub(/ ;;$/, "", c)
            print w "\t" c "\t" g
        }
    }' "$1"
}
table "$V" > "$T/table"
# The arms: state<TAB>code<TAB>comment word, from the front matter only.
awk '
    NR > 1 && /^---$/ { exit }
    /^  [a-z_]+:[ ]*$/ { st = $1; sub(/:$/, "", st) }
    /gates\.[a-z_]+_verdict\.exit_code: [0-9]+/ {
        c = $0; sub(/.*exit_code: /, "", c); w = c; sub(/[ ].*$/, "", c)
        if (w ~ /#/) { sub(/.*# /, "", w) } else { w = "" }
        print st "\t" c "\t" w
    }' "$TPL" > "$T/arms"

NW=$(wc -l < "$T/table" | tr -d ' '); NA=$(wc -l < "$T/arms" | tr -d ' ')
if [ "$NW" -ge 50 ] && [ "$NA" -ge 50 ]; then ok "the table and the arms parse ($NW words, $NA arms)"
else bad "the table and the arms parse" "$NW words, $NA arms"; fi

: > "$T/bad"
while IFS='	' read -r st c w; do
    tw=$(awk -F'\t' -v c="$c" '$2 == c { print $1 }' "$T/table")
    if [ -z "$tw" ]; then echo "arm $st exit $c is not in the table" >> "$T/bad"
    elif [ "$w" != "$tw" ]; then echo "arm $st exit $c says [$w] but the table's word is $tw" >> "$T/bad"; fi
done < "$T/arms"
while IFS='	' read -r w c g; do
    case "$w" in handed-over|reconciled) continue ;; esac
    cut -f2 "$T/arms" | grep -qx "$c" || echo "code $c ($w) has no arm in any state" >> "$T/bad"
    [ -n "$g" ] || continue
    for st in $(printf '%s' "$g" | tr ',' ' '); do
        cut -f1 "$T/arms" | grep -qx "$st" || continue
        printf '%s\n' "$EXCEPT" | grep -qx "$st	$w" && continue
        awk -F'\t' -v s="$st" -v c="$c" '$1 == s && $2 == c { f = 1 } END { exit !f }' "$T/arms" \
            || echo "$st has no arm for $w ($c)" >> "$T/bad"
    done
done < "$T/table"
if [ -s "$T/bad" ]; then bad "every arm, word and state group agrees with coord-verdict.sh" "$(cat "$T/bad")"
else ok "every arm, word and state group agrees with coord-verdict.sh"; fi
# A word listed twice: coord-verdict.sh's `case` runs the first label only, so
# the second code could never be reached. Proved against a copy with one word
# added again, so the check can't pass by reading nothing.
dups() { cut -f1 "$1" | sort | uniq -d; }
D=$(dups "$T/table")
[ -z "$D" ] && ok "no verdict word appears twice in the table" || bad "no verdict word appears twice in the table" "$D"
sed 's/^    reconciled) exit 140 ;;$/    reconciled) exit 140 ;; pick) exit 141 ;;/' "$V" > "$T/dup.sh"
table "$T/dup.sh" > "$T/dup.table"
[ "$(dups "$T/dup.table")" = pick ] && ok "the duplicate check catches a word listed twice" \
    || bad "the duplicate check catches a word listed twice" "$(dups "$T/dup.table")"
grep -q 'waiting|land-blocked)' "$V" && grep -q 'exit 4 ;;' "$V" && ok "a verdict that holds the state by design exits 4" || bad "a verdict that holds the state by design exits 4"
grep -q 'unknown verdict word' "$V" && ok "an unknown word exits 3 and names itself" || bad "an unknown word exits 3 and names itself"

echo
echo "coord-verdict-table: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
