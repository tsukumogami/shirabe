#!/usr/bin/env bash
# roadmap-features_test.sh -- record-common.sh lib_roadmap_features, the
# picker's reading of a roadmap, and the blocked set pick-facts.sh builds on it.
#
# Covers: each item of the synthetic fixture roadmaps under
# testdata/roadmap-features, its finished, done and dependencies as the reader
# gives them and its blocked and blocked_by as pick-facts.sh's facts give
# them, against the hand-written expected.json. ROADMAP-fixture.md is
# prefixed (AB1, AB10a, CD3): paragraphs ending at a blank line, the next
# field and a heading; nested and unbalanced parentheses; each soft marker; a
# sentence opening Soft; a self-mention; another roadmap's tag; a None
# paragraph with tags after it; the Done, Shipped, Dropped and near-miss
# statuses; a non-item `###` heading; a finished item and a Dropped one over
# an unfinished dependency; a dependency on a Dropped item; and `Feature 2`,
# `Features 1, 2 and 3` and `F2` resolving by position. ROADMAP-numbered.md
# has its `Feature N` headings out of order, so those resolve by tag. Then a
# Dependencies paragraph of exactly 4096 bytes reads, and one byte more fails
# the reader and pick-facts.sh, naming the item.
#
# Usage: bash skills/coordinate/scripts/roadmap-features_test.sh
set -uo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
command -v jq >/dev/null 2>&1 || { echo "SKIP: jq not on PATH"; exit 0; }
. "$HERE/testdata/test-lib.sh"
D="$HERE/testdata/roadmap-features"
PF="$HERE/pick-facts.sh"

# features <roadmap.md>: lib_roadmap_features over it, in a subshell so the
# library's globals stay out of this test.
features() { (PROG=roadmap-features; . "$HERE/record-common.sh"; lib_roadmap_features "$1"); }
N=0
# picked <name> <roadmap.md>: pick-facts.sh's facts for a roadmap run whose
# roadmap on the default branch is that file; the facts land in $T/pick.json.
picked() {
    N=$((N + 1))
    S="coordinate-roadmap-$1-20260926T08$(printf %02d "$N")00Z"
    db_init
    db '.issues += [{repo: "acme/widgets", number: 7, title: $t, body: $b, state: "open", author: "alice", editor: null}]' \
        --arg t "Coordinator record: ROADMAP-$1" --arg b "$(render "$(record_json roadmap "$1")" issue)"
    db '.files["acme/widgets"][$k] = $t' --arg k "main:docs/roadmaps/ROADMAP-$1.md" --rawfile t "$2"
    found_session "$S" "$(roadmap_vars "$1")" 7
    log_to "$S" reconcile pick_facts
    bash "$PF" --session "$S" > /dev/null 2> "$T/pick.err"
    PICK_RC=$?
    cp "$KOTO_STORE/context/$S/coord/pick.json" "$T/pick.json" 2> /dev/null || echo '{}' > "$T/pick.json"
}

for fx in ROADMAP-fixture.md ROADMAP-numbered.md; do
    echo "== $fx =="
    name=${fx#ROADMAP-}; name=${name%.md}
    features "$D/$fx" > "$T/features.json" 2> "$T/features.err"
    eq "$fx: the reader succeeds" 0 $?
    picked "$name" "$D/$fx"
    eq "$fx: pick-facts.sh reads it" 0 "$PICK_RC"
    # Each item as the reader and the picker see it, beside its expected entry.
    jq -c --slurpfile p "$T/pick.json" 'map(. as $f | {id, finished, done, dependencies}
        + ([$p[0].units[]? | select(.unit == $f.id) | {blocked, blocked_by}][0] // {blocked: null, blocked_by: null}))' \
        "$T/features.json" > "$T/got.json"
    jq -c --arg fx "$fx" '.[$fx]' "$D/expected.json" > "$T/want.json"
    eq "$fx: the items, in order" "$(jq -r '[.[].id] | join(",")' "$T/want.json")" "$(jq -r '[.[].id] | join(",")' "$T/got.json")"
    n=$(jq length "$T/want.json"); i=0
    while [ "$i" -lt "$n" ]; do
        want=$(jq -c --argjson i "$i" '.[$i]' "$T/want.json")
        got=$(jq -c --argjson i "$i" '.[$i] // null' "$T/got.json")
        eq "$fx: $(printf '%s' "$want" | jq -r .id)" "$want" "$got"
        i=$((i + 1))
    done
done

echo "== a Dependencies paragraph over 4096 bytes =="
# big <bytes of x>: a roadmap whose AB2 paragraph is `AB1 ` and that many
# x, wrapped over lines of at most 100 bytes joined by single spaces.
big() {
    local left=$1 line
    printf '## Features\n\n### AB1: Base\n**Status:** Done\n\n### AB2: Long\n**Status:** Not started\n**Dependencies:** AB1'
    while [ "$left" -gt 0 ]; do
        if [ "$left" -gt 100 ]; then line=99; else line=$((left - 1)); fi
        printf '\n%s' "$(printf "%0${line}d" 0 | tr 0 x)"
        left=$((left - line - 1))
    done
    printf '\n\n### AB3: After\n**Dependencies:** AB2\n'
}
# `AB1` is 3 bytes; the rest is a separator and its line per pass.
big 4093 > "$T/limit.md"
features "$T/limit.md" > "$T/limit.json" 2> "$T/limit.err"
eq "a paragraph of exactly 4096 bytes reads" 0 $?
eq "  ... and names its dependency" "[1]" "$(jq -c '.[1].dependencies' "$T/limit.json")"
big 4094 > "$T/over.md"
features "$T/over.md" > /dev/null 2> "$T/over.err"
rc=$?
[ "$rc" -ne 0 ] && ok "one byte more fails the reader (exit $rc)" || bad "one byte more fails the reader"
grep -q 'AB2' "$T/over.err" && ok "  ... naming the item" || bad "  ... naming the item" "$(cat "$T/over.err")"
picked over "$T/over.md"
eq "pick-facts.sh exits 2 on it" 2 "$PICK_RC"
grep -q 'AB2' "$T/pick.err" && ok "  ... naming the item" || bad "  ... naming the item" "$(cat "$T/pick.err")"

done_tests roadmap-features
