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
# On a koto with `session flush` (a wrapper in front of the stand-in, which
# has none) every add into the new run carries KOTO_WRITE_WINDOW set to it and
# no other call does, one flush of the new run follows the last add, and
# record/meta is written after it without the variable; the calls are
# otherwise the ones a koto without it gets, which are main's plus the one
# --help probe. A write that fails part way, an add or the flush, exits 11
# and leaves the new run with no record/meta.
#
# Usage: bash skills/coordinate/scripts/state-carry_test.sh
set -uo pipefail
. "$(dirname "$0")/../../../scripts/lib/koto-test-guard.sh" || exit 1
# The window's variable is what the window cases look for; none may come in
# from the caller.
unset KOTO_WRITE_WINDOW

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
# A koto with the write window, in front of the stand-in: each call is logged
# to $KOTO_STORE/wcalls as `W=<KOTO_WRITE_WINDOW, - when unset> <args>`. With
# WK_FLUSH=1 it answers `session flush --help` and `session flush S` itself
# (logging them to calls as the stand-in logs its own), the flush failing
# with a koto-like message when WK_FAIL_FLUSH is set; without it they go to
# the stand-in, which has no such command.
mkdir -p "$T/wkoto"
cat > "$T/wkoto/koto" <<EOF
#!/usr/bin/env bash
printf 'W=%s %s\n' "\${KOTO_WRITE_WINDOW:--}" "\$*" >> "\$KOTO_STORE/wcalls"
if [ -n "\${WK_FLUSH:-}" ] && [ "\${1:-} \${2:-}" = "session flush" ]; then
    printf '%s\n' "\$*" >> "\$KOTO_STORE/calls"
    [ "\${3:-}" = --help ] && { echo "Usage: koto session flush <NAME>"; exit 0; }
    [ -z "\${WK_FAIL_FLUSH:-}" ] || { printf '{"error": "flush of session %s failed: the bucket could not be reached"}\n' "\$3"; exit 1; }
    printf '{"name": "%s", "flushed": true}\n' "\$3"; exit 0
fi
exec "$HERE/testdata/koto" "\$@"
EOF
chmod +x "$T/wkoto/koto"
wcarry() { ( export KOTO_BIN="$T/wkoto/koto"; carry "$@" ); }
# shape <file>: a call log with each add's file and each W= prefix dropped,
# and each run of record-section gets, and of their listings, sorted, so two
# carries' calls compare. state-read.sh starts those reads together, so they
# reach koto in any order (shirabe#1406); every other call keeps its place.
SECTION_KEYS='record/(holdings|deferrals|side-effects|reversals|decisions|holds|run|standing|work)$'
shape() {
    sed -e 's/^W=[^ ]* //' -e 's/--from-file .*/--from-file/' "$1" | awk -v get="^context get [^ ]+ $SECTION_KEYS" \
        -v list="^context list [^ ]+ --prefix $SECTION_KEYS" '
        function flush(   i, j, t) {
            for (i = 2; i <= n; i++)
                for (j = i; j > 1 && b[j - 1] > b[j]; j--) { t = b[j]; b[j] = b[j - 1]; b[j - 1] = t }
            for (i = 1; i <= n; i++) print b[i]
            n = 0; k = ""
        }
        { m = ""; if ($0 ~ get) m = "get"; else if ($0 ~ list) m = "list" }
        m != k { flush() }
        m == "" { print; next }
        { k = m; b[++n] = $0 }
        END { flush() }'
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

echo "== on a koto without session flush =="
big_record
: > "$KOTO_STORE/calls"; : > "$KOTO_STORE/wcalls"
wcarry "$SRC" "$DST" > /dev/null 2>"$T/err"
eq "the carry succeeds" 0 $?
eq "  ... asking koto once whether it has session flush, and never flushing" "session flush --help" \
    "$(grep '^session flush' "$KOTO_STORE/calls")"
eq "  ... with no call carrying KOTO_WRITE_WINDOW" 0 "$(grep -vc '^W=- ' "$KOTO_STORE/wcalls")"
eq "  ... and every key copied" "" "$(same_bytes)"
grep -v '^session flush --help$' "$KOTO_STORE/calls" | shape /dev/stdin > "$T/plain.calls"

echo "== on a koto with session flush, the writes in one window =="
big_record
: > "$KOTO_STORE/calls"; : > "$KOTO_STORE/wcalls"
WK_FLUSH=1 wcarry "$SRC" "$DST" > /dev/null 2>"$T/err"
eq "the carry succeeds" 0 $?
eq "  ... the new run holds every key the source holds" "$(keys_of "$SRC")" "$(keys_of "$DST")"
eq "  ... each with the source's bytes" "" "$(same_bytes)"
eq "  ... and record/meta with the source's written time" "$(jq -r .written "$KOTO_STORE/context/$SRC/record/meta")" \
    "$(jq -r .written "$KOTO_STORE/context/$DST/record/meta")"
eq "  ... and a standing_used from the entry naming s7" 7 "$(jq -r .standing_used "$KOTO_STORE/context/$DST/record/meta")"
W="$KOTO_STORE/wcalls"
eq "  ... every add of a key into the new run carries KOTO_WRITE_WINDOW set to it" "$N" \
    "$(grep -c "^W=$DST context add $DST " "$W")"
eq "  ... and no other call carries it" 0 "$(grep -v '^W=- ' "$W" | grep -vc "^W=$DST context add $DST ")"
eq "  ... record/meta's add carries none" 1 "$(grep -c "^W=- context add $DST record/meta " "$W")"
eq "  ... one flush of the new run" 1 "$(grep -c "^W=- session flush $DST\$" "$W")"
eq "  ... and no other flush but the one --help probe" 2 "$(grep -c '^W=- session flush' "$W")"
# The order: the probe, then only the window's adds, then the flush, then
# record/meta. A call on the new run between them would push the window early.
FIRST=$(grep -n "^W=$DST " "$W" | head -1 | cut -d: -f1)
LAST=$(grep -n "^W=$DST " "$W" | tail -1 | cut -d: -f1)
FLUSH=$(grep -n "^W=- session flush $DST\$" "$W" | cut -d: -f1)
META=$(grep -n "^W=- context add $DST record/meta " "$W" | cut -d: -f1)
eq "  ... the adds one run of calls, nothing else between them" "$N" "$((LAST - FIRST + 1))"
eq "  ... the flush right after the last add" "$((LAST + 1))" "$FLUSH"
eq "  ... and record/meta after the flush" 1 "$([ "$META" -gt "$FLUSH" ] && echo 1)"
grep -n '^W=- session flush --help$' "$W" | cut -d: -f1 > "$T/probe"
eq "  ... the probe before the first add" 1 "$([ "$(cat "$T/probe")" -lt "$FIRST" ] && echo 1)"
grep -v '^session flush' "$KOTO_STORE/calls" | shape /dev/stdin > "$T/window.calls"
eq "  ... and otherwise the calls a koto without session flush gets" "" "$(diff "$T/plain.calls" "$T/window.calls")"

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
big_record
: > "$KOTO_STORE/wcalls"
WK_FLUSH=1 KOTO_FAIL_ADD=legs/req-1/work-on/result.json wcarry "$SRC" "$DST" > /dev/null 2>"$T/err"
eq "a failed add inside the window stops the carry (11)" 11 $?
grep -q "failed at legs/req-1/work-on/result.json" "$T/err" && ok "  ... naming the key" || bad "  ... naming the key" "$(cat "$T/err")"
eq "  ... flushing nothing" 0 "$(grep -c "^W=- session flush $DST\$" "$KOTO_STORE/wcalls")"
eq "  ... and leaving the new run without record/meta" 1 "$([ ! -e "$KOTO_STORE/context/$DST/record/meta" ] && echo 1)"
big_record
: > "$KOTO_STORE/wcalls"
WK_FLUSH=1 WK_FAIL_FLUSH=1 wcarry "$SRC" "$DST" > /dev/null 2>"$T/err"
eq "a failed flush stops the carry (11)" 11 $?
grep -q "failed closing its write window: .*flush of session $DST failed: the bucket could not be reached" "$T/err" \
    && ok "  ... with koto's message" || bad "  ... with koto's message" "$(cat "$T/err")"
eq "  ... writing no record/meta after it" 0 "$(grep -c "context add $DST record/meta " "$KOTO_STORE/wcalls")"
eq "  ... so the new run holds no record and the next start carries again" 1 \
    "$([ ! -e "$KOTO_STORE/context/$DST/record/meta" ] && echo 1)"

done_tests state-carry_test
