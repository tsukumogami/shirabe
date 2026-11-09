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
# The Run `role` row on a carry (docs/designs/DESIGN-coordinator-named-roles.md,
# Decision 1; PRD R5): right after core_carry lands a run's record in a new
# run, before that run's find, state-stored-set.sh --run role --intervention
# writes the change there (its row, set_by, set and entry) while a plain --run
# role is refused for want of a found record. state-open.sh --carry --role adds
# the row to a role-less copy, set by `start --role`, and leaves a copy
# holding a role as it is; with --role-change-by and --role-change-source it
# replaces a carried role through the intervention write. A carry run again
# after it landed settles the role first: a change its first run didn't write
# is written then, and a role-less landed copy given --role gets the row.
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

echo "== a role change written before the find, right after a carry lands =="
# The opener's carry: core_carry copies the record into a new run whose find
# hasn't run, and the change goes in through the before-find path.
RSRC=coordinate-roadmap-lanes-20260926T070000Z
RDST=coordinate-roadmap-lanes-20260926T080000Z
db_init
rm -rf "$KOTO_STORE/context/$RSRC" "$KOTO_STORE/context/$RDST"
seed_session "$RSRC" "$(record_json roadmap lanes | jq -c '.run = [{key: "role", value: "director", set_by: "the human", set: "2026-09-26T07:00Z"},
    {key: "reports-to", value: "the human", set_by: "the human", set: "2026-09-26T07:00Z"}]')"
log_new "$RDST" "$(roadmap_vars lanes)"
( PROG=carry SCOPE=roadmap NAME=lanes
  . "$HERE/state-common.sh"; . "$HERE/state-read.sh"; . "$HERE/state-write-core.sh"; RS_RETRY_PAUSE=0
  core_carry "$RSRC" "$RDST" ) > /dev/null 2>"$T/err"
eq "the carry lands in the new run" 0 $?
bash "$HERE/coord-log.sh" run-facts --session "$RDST" > /dev/null 2>&1
eq "  ... whose find hasn't run: no found record" 1 $?
rrole() { koto context get "$RDST" record/run | jq -r '[.[] | select(.key == "role")] | if length == 0 then "none" else (.[0] | "\(.value)|\(.set_by)") end'; }
RSNAP=$(session_snapshot "$RDST")
bash "$HERE/state-stored-set.sh" --session "$RDST" --run role manager --by lane-lead >/dev/null 2>"$T/err"
eq "a plain --run role there is refused: it keeps the found-record rule (10)" 10 $?
eq "  ... writing nothing" "$RSNAP" "$(session_snapshot "$RDST")"
BEFORE=$(date -u +%Y-%m-%dT%H:%MZ)
bash "$HERE/state-stored-set.sh" --session "$RDST" --run role manager --by lane-lead --intervention dispatcher >/dev/null 2>"$T/err"
eq "--run role --intervention writes there before the find" "0 manager|lane-lead" "$? $(rrole)"
AFTER=$(date -u +%Y-%m-%dT%H:%MZ)
RSET=$(koto context get "$RDST" record/run | jq -r '.[] | select(.key == "role") | .set')
[[ ! $RSET < $BEFORE ]] && [[ ! $RSET > $AFTER ]] && ok "  ... its Set the write's time" || bad "  ... its Set the write's time" "$BEFORE <= $RSET <= $AFTER"
eq "  ... the other Run rows as the carry brought them" "reports-to:the human" \
    "$(koto context get "$RDST" record/run | jq -r '[.[] | select(.key != "role") | "\(.key):\(.value)"] | join(" ")')"
eq "  ... and its entry names the old role, the new one and the source" \
    "run|Run role changed from director to manager by lane-lead, an intervention from above; source: dispatcher." \
    "$(RS_SESSION=$RDST bash "$HERE/state-entry.sh" --scope roadmap --name lanes --repo "$REPO" --list | jq -r '.[-1] | "\(.kind)|\(.text)"')"
eq "  ... the source run left as it was" "director" "$(koto context get "$RSRC" record/run | jq -r '.[] | select(.key == "role") | .value')"

echo "== state-open.sh --carry --role =="
# A discipline rotation that carries its predecessor: P, an ended rotation
# holding the given Run rows, and S, the next rotation, its find sealed
# `predecessor P`. Each case is its own discipline, so S is its scope's one
# live run.
TODAY=$(date -u +%Y-%m-%d)
dsealed() {
    log_to "$1" start_posture record_find 2026-09-26T08:01:00.000Z
    log_capture "$1" RECORD_FIND "$(bash "$HERE/coord-log.sh" seal --session "$1" --state record_find --token "$2")" 2026-09-26T08:01:00.000Z
}
# pred_rotation <discipline> <run-rows-json>: P for <discipline>, ended, its
# record holding <run-rows-json> as its Run section ([] for none). Sets P and S.
pred_rotation() {
    P=coordinate-discipline-$1-20261001T100000Z S=coordinate-discipline-$1-20261008T100000Z
    log_new "$P" "$(discipline_vars "$1")"; dsealed "$P" found
    record_json discipline "$1" | jq -c --argjson r "$2" '. + {written: "2026-10-01T10:00:00Z"} | if $r == [] then . else .run = $r end' > "$T/pred.json"
    session_keys "$P" "$T/pred.json"
    jq -nc '{start: "2026-10-01", end: "2026-10-07", host_repo: "acme/widgets", predecessor: null}' | koto context add "$P" record/rotation
    touch "$KOTO_STORE/sessions/$P/.terminal"
    log_new "$S" "$(discipline_vars "$1")"; dsealed "$S" "predecessor $P"
}
srole() { koto context get "$S" record/run | jq -r '[.[] | select(.key == "role")] | if length == 0 then "none" else (.[0] | "\(.value)|\(.set_by)") end'; }
sentries() { bash "$HERE/state-entry.sh" --session "$S" --list; }
MGR='[{"key": "role", "value": "manager", "set_by": "the human", "set": "2026-10-01T10:00Z"}]'
db_init

pred_rotation roleless '[]'
OUT=$(bash "$HERE/state-open.sh" --session "$S" --carry --role director 2>"$T/err"); rc=$?
eq "--carry --role director on a role-less copy carries" "0 carried=$P" "$rc $(printf '%s\n' "$OUT" | grep '^carried=')"
eq "  ... adding the row, set by the start's --role" "director|start --role" "$(srole)"
eq "  ... in the seed: no role entry" 0 "$(sentries | jq '[.[] | select(.text | startswith("Run role"))] | length')"

pred_rotation keeps "$MGR"
OUT=$(bash "$HERE/state-open.sh" --session "$S" --carry --role director 2>"$T/err"); rc=$?
eq "--carry --role director on a copy holding manager carries" "0 carried=$P" "$rc $(printf '%s\n' "$OUT" | grep '^carried=')"
eq "  ... and the copy keeps manager" "manager|the human" "$(srole)"
SNAP=$(session_snapshot "$S")
OUT=$(bash "$HERE/state-open.sh" --session "$S" --carry --role director 2>"$T/err"); rc=$?
eq "  ... run again it reads as carried, changing no key" "0 carried=$P $SNAP" "$rc $(printf '%s\n' "$OUT" | grep '^carried=') $(session_snapshot "$S")"

pred_rotation change "$MGR"
BEFORE=$(date -u +%Y-%m-%dT%H:%MZ)
OUT=$(bash "$HERE/state-open.sh" --session "$S" --carry --role director --role-change-by "the human" --role-change-source person 2>"$T/err"); rc=$?
AFTER=$(date -u +%Y-%m-%dT%H:%MZ)
eq "--carry --role director with the change flags on a copy holding manager carries" "0 carried=$P" "$rc $(printf '%s\n' "$OUT" | grep '^carried=')"
eq "  ... replacing the row, set by who intervened" "director|the human" "$(srole)"
CSET=$(koto context get "$S" record/run | jq -r '.[] | select(.key == "role") | .set')
[[ ! $CSET < $BEFORE ]] && [[ ! $CSET > $AFTER ]] && ok "  ... at the write's time" || bad "  ... at the write's time" "$BEFORE <= $CSET <= $AFTER"
eq "  ... with the intervention write's entry" \
    "Run role changed from manager to director by the human, an intervention from above; source: person." \
    "$(sentries | jq -r '[.[] | select(.text | startswith("Run role"))] | last | .text')"
eq "  ... and the predecessor still holding manager" manager "$(koto context get "$P" record/run | jq -r '.[0].value')"

pred_rotation oneflag "$MGR"
bash "$HERE/state-open.sh" --session "$S" --carry --role director --role-change-by "the human" >/dev/null 2>"$T/err"
eq "--carry with --role-change-by alone is a usage error" 64 $?
bash "$HERE/state-open.sh" --session "$S" --carry --role director --role-change-source person >/dev/null 2>"$T/err"
eq "  ... and with --role-change-source alone" 64 $?
eq "  ... neither carrying anything" none "$(session_snapshot "$S")"

# A carry that landed without the change, then run again with it (a run cut
# short before the change was written): the re-run writes the change before it
# reads as carried.
pred_rotation landed "$MGR"
bash "$HERE/state-open.sh" --session "$S" --carry --role manager >/dev/null 2>"$T/err"
eq "a carry lands holding manager" "0 manager|the human" "$? $(srole)"
OUT=$(bash "$HERE/state-open.sh" --session "$S" --carry --role director --role-change-by lane-lead --role-change-source dispatcher 2>"$T/err"); rc=$?
eq "  ... run again with the change flags it reads as carried" "0 carried=$P" "$rc $(printf '%s\n' "$OUT" | grep '^carried=')"
eq "  ... having written the change" "director|lane-lead" "$(srole)"
eq "  ... through the intervention write" \
    "Run role changed from manager to director by lane-lead, an intervention from above; source: dispatcher." \
    "$(sentries | jq -r '[.[] | select(.text | startswith("Run role"))] | last | .text')"
N=$(sentries | jq length); SNAP=$(session_snapshot "$S")
OUT=$(bash "$HERE/state-open.sh" --session "$S" --carry --role director --role-change-by lane-lead --role-change-source dispatcher 2>"$T/err"); rc=$?
eq "  ... and a third run writes nothing more" "0 carried=$P $SNAP $N" \
    "$rc $(printf '%s\n' "$OUT" | grep '^carried=') $(session_snapshot "$S") $(sentries | jq length)"

pred_rotation lateroll '[]'
bash "$HERE/state-open.sh" --session "$S" --carry >/dev/null 2>"$T/err"
eq "a role-less carry lands with no --role and no row" "0 none" "$? $(srole)"
OUT=$(bash "$HERE/state-open.sh" --session "$S" --carry --role manager 2>"$T/err"); rc=$?
eq "  ... run again with --role it reads as carried" "0 carried=$P" "$rc $(printf '%s\n' "$OUT" | grep '^carried=')"
eq "  ... having written the row, set by the start's --role" "manager|start --role" "$(srole)"
grep -Eq '^(pr create|pr ready|api --method (POST|DELETE|PUT))' "$GH_DB.calls" && bad "no role write reached GitHub" "$(cat "$GH_DB.calls")" || ok "no role write reached GitHub"

done_tests state-carry_test
