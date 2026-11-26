#!/usr/bin/env bash
# state-write-race_test.sh -- two record writers on one run never lose each
# other's rows (shirabe#2059): the record's write lock (state-read.sh
# rs_write_lock_path, state-write-core.sh core_lock) is held from a writer's
# compare on the written time to its last key.
#
# Covers:
#   1. a --told row written while the handover's --missing write
#      (handover-classify.sh writes through state-stored-set.sh, as here) has
#      passed its compare and not yet written its keys: the --told write is
#      refused record-changed (12), saying so, and lands when tried again on
#      the fresh record, as handover-classify.sh's set_row tries again; both
#      rows are then in the record and state-handover.sh reads the worker as
#      told. A koto wrapper first on PATH holds the handover's write at its
#      pending mark until the --told write has marked its own, or for
#      RACE_WAIT seconds when it can't: without the lock the --told write
#      passes its compare in that window and the handover's write then
#      replaces the Run section without it;
#   2. a record/meta left marked pending by a writer that stopped part way
#      (no live writer holding the lock): a reader reads past the mark, and
#      the next write lands, clears the mark and replaces the keys the
#      stopped writer had changed;
#   3. a lock whose holder is gone is taken over; one a live writer holds
#      past CORE_LOCK_WAIT refuses the write record-changed (12), leaving the
#      record and the lock as they were;
#   4. a write landing in the same second as the version it was edited from
#      gets a later written time, so a writer that read that version is still
#      refused.
#
# Usage: bash skills/coordinate/scripts/state-write-race_test.sh
set -uo pipefail
. "$(dirname "$0")/../../../scripts/lib/koto-test-guard.sh" || exit 1

HERE=$(cd "$(dirname "$0")" && pwd)
command -v jq >/dev/null 2>&1 || { echo "SKIP: jq not on PATH"; exit 0; }
. "$HERE/testdata/test-lib.sh"
RS="$HERE/state-stored-set.sh"
RH="$HERE/state-handover.sh"
WR="$HERE/state-write.sh"
unset CLAUDE_CODE_SESSION_ID NIWA_BIN

SR=coordinate-roadmap-plugin-system-20260926T070000Z
export RS_SESSION=$SR RS_RETRY_PAUSE=0
RM=(--scope roadmap --name plugin-system --repo "$REPO")
W=("${RM[@]}" --skip-session-checks)
mkdir -p "$KOTO_STORE/sessions/$SR"
LOCK="$(koto session dir "$SR")/record-write.lock"
TWO=$(record_json roadmap plugin-system | jq -c --argjson a "$(holding worker-f2)" \
    --argjson b "$(holding worker-f3 '{"unit": "Feature 3", "pull_request": ""}')" '.holdings = [$a, $b]')
run_rows() { session_state "$SR" | jq -r '[.run[] | select(.key == "told" or .key == "missing") | "\(.key)=\(.value)"] | sort | join(",")'; }

# The wrapper: on a write of record/meta marked pending, the writer whose
# RACE_ROLE is `first` says it is there and waits for the `second` writer's
# mark, up to RACE_WAIT seconds; the second says it has marked.
REAL_KOTO=$(command -v koto)
mkdir -p "$T/race-bin" "$T/race"
cat > "$T/race-bin/koto" <<EOF
#!/usr/bin/env bash
if [ "\${1:-} \${2:-}" = "context add" ] && [ "\${4:-}" = record/meta ] && [ -n "\${RACE_ROLE:-}" ] \\
    && [ "\${5:-}" = --from-file ] && jq -e '.pending == true' "\${6:-}" > /dev/null 2>&1; then
    case "\$RACE_ROLE" in
        first)
            touch "$T/race/first-at-mark"
            n=0
            while [ ! -e "$T/race/second-marked" ] && [ "\$n" -lt "\$((RACE_WAIT * 10))" ]; do sleep 0.1; n=\$((n + 1)); done ;;
        second) touch "$T/race/second-marked" ;;
    esac
fi
exec "$REAL_KOTO" "\$@"
EOF
chmod +x "$T/race-bin/koto"

echo "== a --told write while the handover's write is under way =="
db_init; seed_session "$SR" "$TWO"
bash "$RS" "${W[@]}" --run coordinator lane-v2 --by lane-v2 >/dev/null 2>"$T/err"; eq "a coordinator address is set" 0 $?
rm -f "$T/race/"*
( PATH="$T/race-bin:$PATH" RACE_ROLE=first RACE_WAIT=3 bash "$RS" "${W[@]}" --missing worker-f3 --by "the handover" \
    >/dev/null 2>"$T/first.err"; echo $? > "$T/first.rc" ) &
FIRST=$!
n=0
while [ ! -e "$T/race/first-at-mark" ] && [ "$n" -lt 300 ]; do sleep 0.1; n=$((n + 1)); done
[ -e "$T/race/first-at-mark" ] && ok "the handover's write reaches its pending mark" || bad "the handover's write reaches its pending mark" "$(cat "$T/first.err")"
# The coordinator's --told, tried again on record-changed as set_row does.
TRIES=
for try in 1 2 3; do
    PATH="$T/race-bin:$PATH" RACE_ROLE=second bash "$RS" "${W[@]}" --told worker-f2 --by lane-v2 >/dev/null 2>"$T/second.$try.err"
    rc=$?
    TRIES="$TRIES$rc "
    [ "$rc" = 12 ] || break
done
wait "$FIRST"
eq "the handover's --missing write lands" 0 "$(cat "$T/first.rc")"
eq "the --told write is refused record-changed once, then lands" "12 0 " "$TRIES"
grep -q 'record-changed' "$T/second.1.err" && ok "  ... the refusal saying record-changed" \
    || bad "  ... the refusal saying record-changed" "$(cat "$T/second.1.err")"
eq "both rows are in the record" "missing=worker-f3,told=worker-f2" "$(run_rows)"
bash "$RH" "${RM[@]}" | jq -e '[.gaps[].gap] | index("not-told worker-f2") == null' >/dev/null \
    && ok "  ... and the handover reads worker-f2 as told" || bad "  ... and the handover reads worker-f2 as told" "$(bash "$RH" "${RM[@]}")"
eq "  ... and no lock is left" no "$([ -e "$LOCK" ] && echo yes || echo no)"
eq "  ... and record/meta isn't left pending" false "$(koto context get "$SR" record/meta | jq -r '.pending')"

echo "== a pending mark a stopped writer left =="
db_init; seed_session "$SR" "$TWO"
# A state edited from the record before the writer that stopped began.
state_json "$TWO" > "$T/before.json"
koto context get "$SR" record/meta > "$T/meta.json"
jq -c '.pending = true' "$T/meta.json" | koto context add "$SR" record/meta
# The stopped writer had changed record/holdings already.
koto context get "$SR" record/holdings | jq -c '.[0:1]' > "$T/half.json"
koto context add "$SR" record/holdings --from-file "$T/half.json"
bash "$RS" "${RM[@]}" --list >/dev/null 2>"$T/err"; rc=$?
eq "a reader reads past a pending mark no writer holds the lock for" 0 "$rc"
bash "$WR" "${RM[@]}" --skip-session-checks --state-file "$T/before.json" >/dev/null 2>"$T/err"; rc=$?
eq "the next write lands" 0 "$rc"
eq "  ... clearing the mark" false "$(koto context get "$SR" record/meta | jq -r '.pending')"
eq "  ... and replacing the stopped writer's keys with its state's" 2 "$(koto context get "$SR" record/holdings | jq length)"

echo "== a lock a gone writer left, and one a live writer holds =="
db_init; seed_session "$SR" "$TWO"
bash "$RS" "${W[@]}" --run coordinator lane-v2 --by lane-v2 >/dev/null 2>"$T/err"
sh -c 'exit 0' & GONE=$!; wait "$GONE"
printf '%s %s\n' "$GONE" "$(date +%s)" > "$LOCK"
bash "$RS" "${W[@]}" --told worker-f2 --by lane-v2 >/dev/null 2>"$T/err"; rc=$?
eq "a lock whose holder is gone is taken over" 0 "$rc"
eq "  ... and let go" no "$([ -e "$LOCK" ] && echo yes || echo no)"
SNAP=$(session_snapshot "$SR")
printf '%s %s\n' "$$" "$(date +%s)" > "$LOCK"
CORE_LOCK_WAIT=1 bash "$RS" "${W[@]}" --told worker-f3 --by lane-v2 >/dev/null 2>"$T/err"; rc=$?
eq "a lock a live writer holds past the wait is record-changed" 12 "$rc"
grep -q 'record-changed' "$T/err" && ok "  ... saying so" || bad "  ... saying so" "$(cat "$T/err")"
eq "  ... writing nothing" "$SNAP" "$(session_snapshot "$SR")"
eq "  ... and leaving the other writer's lock" "$$" "$(cut -d' ' -f1 "$LOCK")"
rm -f "$LOCK"

echo "== a write in the same second as its version =="
db_init
NOW=$(date -u +%Y-%m-%dT%H:%M:%SZ)
seed_session "$SR" "$TWO" "$NOW"
state_json "$TWO" "$NOW" > "$T/same.json"
bash "$WR" "${RM[@]}" --skip-session-checks --state-file "$T/same.json" >/dev/null 2>"$T/err"; rc=$?
eq "the write lands" 0 "$rc"
W2=$(koto context get "$SR" record/meta | jq -r .written)
[ "$W2" != "$NOW" ] && ok "  ... with a written time after its version's" || bad "  ... with a written time after its version's" "$W2"
bash "$WR" "${RM[@]}" --skip-session-checks --state-file "$T/same.json" >/dev/null 2>"$T/err"; rc=$?
eq "a second writer edited from that version is refused record-changed" 12 "$rc"

done_tests state-write-race
