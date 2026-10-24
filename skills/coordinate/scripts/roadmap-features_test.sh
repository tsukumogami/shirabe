#!/usr/bin/env bash
# roadmap-features_test.sh -- record-common.sh lib_roadmap_features, the
# picker's reading of a roadmap, and the blocked set pick-facts.sh builds on it.
#
# Covers: each item of the synthetic fixture roadmaps under
# testdata/roadmap-features, its finished, done and dependencies as the reader
# gives them and its blocked and blocked_by as pick-facts.sh's facts give
# them, against the hand-written expected.json. fixture.md is
# prefixed (AB1, AB10a, CD3): paragraphs ending at a blank line, the next
# field and a heading; nested and unbalanced parentheses; each soft marker; a
# sentence opening Soft; a self-mention; another roadmap's tag; a None
# paragraph with tags after it; the Done, Shipped, Dropped and near-miss
# statuses; a non-item `###` heading; a finished item and a Dropped one over
# an unfinished dependency; a dependency on a Dropped item; and `Feature 2`,
# `Features 1, 2 and 3` and `F2` resolving by position. numbered.md
# has its `Feature N` headings out of order, so those resolve by tag.
# fixture-v3.md and numbered-v3.md are the two as roadmap/v3 roadmaps (items
# under `## Milestones`, numbered.md's headings `### Milestone N:` with its
# prose still saying `Feature N`) and are held to the same expected entries,
# numbered-v3.md's ids read as `Milestone N`. On v3 a `## Features` section
# and a `### Feature N:` heading are no item, and on v2 neither are
# `## Milestones` and `### Milestone N:`. Dependency prose reads `milestone N`
# only on v3, where `Feature 2` and `Milestone 2` both name the item tagged
# `Milestone 2`; on v1 and v2 a passing `milestone 3` names nothing. The tag
# key (record-common.sh tag_key and lib_tag_key) makes `Feature 2` and
# `Milestone 2` one key and keeps `Feature 1` and `Milestone 14`, `AB1` and
# `Milestone 1`, `#3` and `Milestone 3`, `Feature 03` and `Milestone 3`, and
# `feature 2` and `Milestone 2` apart. Then a Dependencies paragraph of
# exactly 4096 bytes reads, and one byte more fails the reader and
# pick-facts.sh, naming the item.
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
    db '.files["acme/widgets"][$k] = $t' --arg k "main:docs/roadmaps/ROADMAP-$1.md" --rawfile t "$2"
    found_session "$S" "$(roadmap_vars "$1")"
    seed_session "$S" "$(record_json roadmap "$1")"
    log_to "$S" reconcile pick_facts
    bash "$PF" --session "$S" > /dev/null 2> "$T/pick.err"
    PICK_RC=$?
    cp "$KOTO_STORE/context/$S/coord/pick.json" "$T/pick.json" 2> /dev/null || echo '{}' > "$T/pick.json"
}

for fx in fixture.md numbered.md fixture-v3.md numbered-v3.md; do
    echo "== $fx =="
    name=${fx%.md}
    features "$D/$fx" > "$T/features.json" 2> "$T/features.err"
    eq "$fx: the reader succeeds" 0 $?
    picked "$name" "$D/$fx"
    eq "$fx: pick-facts.sh reads it" 0 "$PICK_RC"
    # Each item as the reader and the picker see it, beside its expected entry.
    jq -c --slurpfile p "$T/pick.json" 'map(. as $f | {id, finished, done, dependencies}
        + ([$p[0].units[]? | select(.unit == $f.id) | {blocked, blocked_by}][0] // {blocked: null, blocked_by: null}))' \
        "$T/features.json" > "$T/got.json"
    # A v3 twin is held to its original's entry, a `Feature N` id read as
    # `Milestone N`.
    case "$fx" in
        *-v3.md) jq -c --arg fx "${fx%-v3.md}.md" '.[$fx] | map(.id |= sub("^Feature "; "Milestone "))' "$D/expected.json" > "$T/want.json" ;;
        *) jq -c --arg fx "$fx" '.[$fx]' "$D/expected.json" > "$T/want.json" ;;
    esac
    eq "$fx: the items, in order" "$(jq -r '[.[].id] | join(",")' "$T/want.json")" "$(jq -r '[.[].id] | join(",")' "$T/got.json")"
    n=$(jq length "$T/want.json"); i=0
    while [ "$i" -lt "$n" ]; do
        want=$(jq -c --argjson i "$i" '.[$i]' "$T/want.json")
        got=$(jq -c --argjson i "$i" '.[$i] // null' "$T/got.json")
        eq "$fx: $(printf '%s' "$want" | jq -r .id)" "$want" "$got"
        i=$((i + 1))
    done
done

echo "== only the version's own section and heading word are items =="
# ids <roadmap.md>: the item ids the reader gives, joined by commas.
ids() { features "$1" | jq -r '[.[].id] | join(",")'; }
printf -- '---\nschema: roadmap/v3\n---\n\n## Features\n\n### Milestone 7: Under the v2 section\n**Status:** Not started\n\n## Milestones\n\n### Milestone 1: One\n**Status:** Done\n\n### Feature 3: A v2 heading on v3\n**Status:** Not started\n\n### Milestone 2: Two\n**Dependencies:** Feature 3\n**Status:** Not started\n' > "$T/stray3.md"
eq "v3: ## Features and ### Feature 3: are no item" "Milestone 1,Milestone 2" "$(ids "$T/stray3.md")"
eq "  ... and Feature 3 in prose names the 3rd item, of which there is none" "[]" "$(features "$T/stray3.md" | jq -c '.[1].dependencies')"
printf -- '---\nschema: roadmap/v2\n---\n\n## Milestones\n\n### Feature 7: Under the v3 section\n**Status:** Not started\n\n## Features\n\n### Feature 1: One\n**Status:** Done\n\n### Milestone 3: A v3 heading on v2\n**Status:** Not started\n\n### Feature 2: Two\n**Status:** Not started\n' > "$T/stray2.md"
eq "v2: ## Milestones and ### Milestone 3: are no item" "Feature 1,Feature 2" "$(ids "$T/stray2.md")"

echo "== the milestone word in dependency prose is v3's =="
# prose <schema> <word>: a roadmap of that version, its classic heading word
# WORD, its 3rd item listed before its 2nd, and two Dependencies lines: a
# passing mention of another project's milestone, and `Feature 2` and
# `Milestone 2` naming items.
prose() {
    printf -- '---\nschema: %s\n---\n\n## %ss\n\n' "$1" "$2"
    printf '### %s 1: Base\n**Dependencies:** None\n**Status:** Done\n\n' "$2"
    printf '### %s 3: Third, listed second\n**Dependencies:** Lands after the upstream project'"'"'s milestone 3.\n**Status:** Not started\n\n' "$2"
    printf '### %s 2: Second, listed third\n**Dependencies:** Feature 1\n**Status:** Not started\n\n' "$2"
    printf '### %s 4: Fourth\n**Dependencies:** Milestone 2\n**Status:** Not started\n\n' "$2"
    printf '### %s 5: Fifth\n**Dependencies:** Feature 2\n**Status:** Not started\n' "$2"
}
prose roadmap/v1 Feature > "$T/p1.md"; prose roadmap/v2 Feature > "$T/p2.md"; prose roadmap/v3 Milestone > "$T/p3.md"
deps() { features "$1" | jq -c '[.[] | .dependencies]'; }
eq "v1: a passing milestone 3 and Milestone 2 name nothing; Feature 2 names the item tagged Feature 2" '[[],[],[1],[],[3]]' "$(deps "$T/p1.md")"
eq "v2: the same" '[[],[],[1],[],[3]]' "$(deps "$T/p2.md")"
eq "v3: milestone 3 names the item tagged Milestone 3, and Feature 2 and Milestone 2 the item tagged Milestone 2" '[[],[],[1],[3],[3]]' "$(deps "$T/p3.md")"
# The upstream project's milestone 3 is the 3rd item's own tag on v3, so it
# names itself, which is no dependency; written `milestone 4` it would block.
printf '%s\n' "$(sed 's/milestone 3\./milestone 4./' "$T/p3.md")" > "$T/p3b.md"
eq "  ... and a passing milestone 4 on v3 names Milestone 4" "[4]" "$(features "$T/p3b.md" | jq -c '.[1].dependencies')"

echo "== the tag key =="
key() { (PROG=roadmap-features; . "$HERE/record-common.sh"; printf '%s' "$1" | jq -R -r "$JQ_TAG_KEY"'tag_key'); }
bkey() { (PROG=roadmap-features; . "$HERE/record-common.sh"; lib_tag_key "$1"); }
same() { if [ "$(key "$2")" = "$(key "$3")" ] && [ "$(bkey "$2")" = "$(bkey "$3")" ]; then ok "$1"; else bad "$1" "[$(key "$2")|$(bkey "$2")] [$(key "$3")|$(bkey "$3")]"; fi; }
apart() { if [ "$(key "$2")" != "$(key "$3")" ] && [ "$(bkey "$2")" != "$(bkey "$3")" ]; then ok "$1"; else bad "$1" "[$(key "$2")] [$(key "$3")]"; fi; }
same "Feature 2 and Milestone 2 are one key" "Feature 2" "Milestone 2"
eq "  ... ms:2, in jq and in bash" "ms:2 ms:2" "$(key "Feature 2") $(bkey "Milestone 2")"
apart "Feature 1 is not Milestone 14" "Feature 1" "Milestone 14"
apart "AB1 is not Milestone 1" "AB1" "Milestone 1"
apart "an issue #3 is not Milestone 3" "#3" "Milestone 3"
apart "Feature 03 is not Milestone 3" "Feature 03" "Milestone 3"
apart "feature 2 is not Milestone 2" "feature 2" "Milestone 2"
apart "Milestone 2a is not Milestone 2" "Milestone 2a" "Milestone 2"
eq "a prefix tag and an issue key as themselves" "AB1 #3" "$(key AB1) $(bkey '#3')"

echo "== a Dependencies paragraph over 4096 bytes =="
# big <bytes of x>: a roadmap whose AB2 paragraph is `AB1` followed by that
# many bytes: lines of at most 99 x, each joined by one space.
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
