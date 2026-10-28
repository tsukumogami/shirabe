#!/usr/bin/env bash
# state-carry_test.sh -- core_carry (state-write-core.sh), the opener's copy of
# a run's record/ and legs/ keys into a new run, on a record the size of a
# long discipline run's (shirabe#1337).
#
# Covers: a carry of several hundred record/ and legs/ keys copying every key
# byte for byte, record/meta last with the source's written time; its koto
# calls, one get and one add per key and a fixed number besides; and a
# refusal found at the last key (a malformed name, a value that isn't JSON, a
# record/posted value that isn't a comment URL) or a failed read writing
# nothing into the new run, since every key is checked before any is written.
# A write that fails part way leaves the new run with no record/meta.
#
# Usage: bash skills/coordinate/scripts/state-carry_test.sh
set -uo pipefail
. "$(dirname "$0")/../../../scripts/lib/koto-test-guard.sh" || exit 1

HERE=$(cd "$(dirname "$0")" && pwd)
command -v jq >/dev/null 2>&1 || { echo "SKIP: jq not on PATH"; exit 0; }
. "$HERE/testdata/test-lib.sh"

SRC=coordinate-roadmap-plugin-system-20260926T070000Z
DST=coordinate-roadmap-plugin-system-20260926T080000Z
ENTRIES=420 POSTED=12 LEGS=40

carry() { # carry <from> <to>
    ( PROG=carry SCOPE=roadmap NAME=plugin-system
      . "$HERE/state-common.sh"; . "$HERE/state-read.sh"; . "$HERE/state-write-core.sh"; RS_RETRY_PAUSE=0
      core_carry "$1" "$2" )
}
# big_record: the source run, a record with sections, ENTRIES entries (one
# naming s7), POSTED posted URLs and LEGS legs/ keys, written as the stand-in
# holds them; the new run holds nothing.
big_record() {
    local c="$KOTO_STORE/context" i
    rm -rf "$c"
    db_init
    seed_session "$SRC" "$(record_json roadmap plugin-system)"
    mkdir -p "$c/$SRC/record/entries" "$c/$SRC/record/posted"
    for ((i = 1; i <= ENTRIES; i++)); do
        printf '{"n":%d,"stamp":"2026-09-26T08:00:00Z","kind":"entry","text":"note %d: tab\\there, \\"quoted\\", \\u00fcn\\u00efcode"}\n' "$i" "$i" \
            > "$c/$SRC/record/entries/$(printf '%06d' "$i")"
    done
    printf '{"n":3,"stamp":"2026-09-26T08:00:00Z","kind":"entry","text":"s7 (answer): an old answer. Owner: the human."}' \
        > "$c/$SRC/record/entries/000003"
    for ((i = 1; i <= POSTED; i++)); do
        printf 'https://github.com/acme/widgets/issues/%d#issuecomment-%d' "$i" "$((1000 + i))" \
            > "$c/$SRC/record/posted/$(printf '%06d' "$i")"
    done
    for ((i = 1; i <= LEGS; i++)); do
        mkdir -p "$c/$SRC/legs/req-$i/work-on"
        printf '{"leg":"work-on","result":{"pr":"https://github.com/acme/widgets/pull/%d"}}' "$i" \
            > "$c/$SRC/legs/req-$i/work-on/result.json"
    done
}
# keys_of <session>: every key of the session but record/meta, one per line.
keys_of() { (cd "$KOTO_STORE/context/$1" 2>/dev/null && find record legs -type f ! -path record/meta 2>/dev/null | LC_ALL=C sort); }
# same_bytes: every source key is in the new run with the same bytes; prints the first that isn't.
same_bytes() {
    local k
    while IFS= read -r k; do
        cmp -s "$KOTO_STORE/context/$SRC/$k" "$KOTO_STORE/context/$DST/$k" || { echo "$k"; return; }
    done < <(keys_of "$SRC")
}
held() { keys_of "$DST" | wc -l | tr -d ' '; }

echo "== a carry of several hundred keys =="
big_record
N=$(keys_of "$SRC" | wc -l | tr -d ' ')
eq "the source holds several hundred keys" 1 "$([ "$N" -ge $((ENTRIES + POSTED + LEGS)) ] && echo 1)"
: > "$KOTO_STORE/calls"
carry "$SRC" "$DST" > /dev/null 2>"$T/err"
eq "the carry succeeds" 0 $?
eq "  ... the new run holds every key the source holds" "$(keys_of "$SRC")" "$(keys_of "$DST")"
eq "  ... each with the source's bytes" "" "$(same_bytes)"
eq "  ... and record/meta with the source's written time" "$(jq -r .written "$KOTO_STORE/context/$SRC/record/meta")" \
    "$(jq -r .written "$KOTO_STORE/context/$DST/record/meta")"
eq "  ... and a standing_used from the entry naming s7" 7 "$(jq -r .standing_used "$KOTO_STORE/context/$DST/record/meta")"
eq "  ... written last" "context add $DST record/meta --from-file" \
    "$(grep '^context add ' "$KOTO_STORE/calls" | tail -1 | sed 's/--from-file .*/--from-file/')"

# The calls: each key is read once from the source and written once into the
# new run; everything else the carry asks koto is the same at any size.
GETS=$(grep -c "^context get $SRC \(record/entries/\|record/posted/\|legs/\)" "$KOTO_STORE/calls")
ADDS=$(grep -c "^context add $DST " "$KOTO_STORE/calls")
OTHER=$(grep -vc "^context get $SRC \(record/entries/\|record/posted/\|legs/\)\|^context add $DST " "$KOTO_STORE/calls")
eq "  ... one get per entry, posted and legs/ key" $((ENTRIES + POSTED + LEGS)) "$GETS"
eq "  ... one add per key and one for record/meta" $((N + 1)) "$ADDS"
ENTRIES=20 POSTED=2 LEGS=3 big_record
: > "$KOTO_STORE/calls"
carry "$SRC" "$DST" > /dev/null 2>"$T/err"
eq "  ... and the same other calls as a carry of a small record" "$OTHER" \
    "$(grep -vc "^context get $SRC \(record/entries/\|record/posted/\|legs/\)\|^context add $DST " "$KOTO_STORE/calls")"

echo "== every key is checked before any is written =="
refused() { # refused <what> <want-exit> <stderr-pattern>
    carry "$SRC" "$DST" > /dev/null 2>"$T/err"
    eq "$1 ($2)" "$2" $?
    grep -q "$3" "$T/err" && ok "  ... saying so" || bad "  ... saying so" "$(cat "$T/err")"
    eq "  ... writing nothing into the new run" 0 "$(held)"
    eq "  ... not even record/meta" 1 "$([ ! -e "$KOTO_STORE/context/$DST/record/meta" ] && echo 1)"
}
big_record
mkdir -p "$KOTO_STORE/context/$SRC/legs/zz"
printf '{"leg": ' > "$KOTO_STORE/context/$SRC/legs/zz/last"
refused "a last legs/ key that isn't JSON is refused" 65 "legs/zz/last isn't JSON"
big_record
printf 'https://example.com/acme/widgets/issues/1#issuecomment-1' > "$KOTO_STORE/context/$SRC/record/posted/000999"
refused "a last record/posted value that isn't a comment URL is refused" 65 "record/posted/000999 isn't a comment URL"
big_record
mkdir -p "$KOTO_STORE/context/$SRC/legs/zz"
printf '{}' > "$KOTO_STORE/context/$SRC/legs/zz/bad name"
refused "a last key with a malformed name is refused" 65 "holds a key named legs/zz/bad name"
big_record
printf '{}' > "$KOTO_STORE/context/$SRC/record/notes"
refused "a record/ key that isn't one of the store's is refused" 65 "record/notes, not one of the session store's"
big_record
chmod 000 "$KOTO_STORE/context/$SRC/legs/req-$LEGS/work-on/result.json"
refused "a key that can't be read fails the carry" 2 "cannot read legs/req-$LEGS/work-on/result.json"
chmod 600 "$KOTO_STORE/context/$SRC/legs/req-$LEGS/work-on/result.json"

echo "== a write that fails part way =="
big_record
KOTO_FAIL_ADD=legs/req-1/work-on/result.json carry "$SRC" "$DST" > /dev/null 2>"$T/err"
eq "a failed add stops the carry (11)" 11 $?
grep -q "failed at legs/req-1/work-on/result.json" "$T/err" && ok "  ... naming the key" || bad "  ... naming the key" "$(cat "$T/err")"
eq "  ... leaving the new run without record/meta, so the next start carries again" 1 \
    "$([ ! -e "$KOTO_STORE/context/$DST/record/meta" ] && echo 1)"

done_tests state-carry_test
