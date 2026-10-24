#!/usr/bin/env bash
# run-trail_test.sh -- scripts/run-trail.sh, the one writer of a run's record
#
# Against the stand-in koto (scripts/testdata/record-koto/koto), which keys a
# session by workspace:
#
#   self   trail/self holds the checkout's canonical path, the session's koto
#          id from the session list and its run_id; no run_id refuses (65)
#   pr     trail/pr/<owner>.<repo>.<n> holds the repository (lowercased), the
#          number as a number, the role and the state; a role, state,
#          repository or number outside its pattern refuses (65) and writes
#          nothing
#   index  run/<run_id> in pr.<owner>.<repo>.<n>, opened and written from
#          the shared address, naming the root's workspace, session, session
#          id, mode and topic; trail/self written first when it's absent;
#          a second write attaches and rewrites; with the option present no
#          write carries --workspace
#   usage  an unknown verb or flag, a repeated flag, a missing one: 64, no
#          koto call
#   koto   a failed write is 70
#
# Usage: run-trail_test.sh
# Exit codes: 0 all pass, 1 a failure

set -uo pipefail

SCRIPT_DIR=$(CDPATH='' cd "$(dirname "$0")" && pwd)
TRAIL="$SCRIPT_DIR/run-trail.sh"
STUB_DIR="$SCRIPT_DIR/testdata/record-koto"

PASS_COUNT=0
FAIL_COUNT=0
pass() { echo "PASS: $*"; PASS_COUNT=$((PASS_COUNT + 1)); }
fail() { echo "FAIL: $*"; FAIL_COUNT=$((FAIL_COUNT + 1)); }

command -v jq >/dev/null 2>&1 || { echo "FAIL: jq is required" >&2; exit 1; }

WORK=$(mktemp -d "${TMPDIR:-/tmp}/run-trail-test.XXXXXX") || exit 1
OWNER="rttest-$$-$(od -An -tx1 -N4 /dev/urandom | tr -d ' \n')"
trap 'rm -rf "$WORK" "/tmp/shirabe-run-record/$OWNER"' EXIT
export PATH="$STUB_DIR:$PATH"
export RECORD_KOTO_STORE="$WORK/store"
A="$WORK/a"
mkdir -p "$A"
A=$(cd "$A" && pwd -P)
S=execute-topic
RID=00112233445566778899aabbccddeeff

new_store() {
    rm -rf "$RECORD_KOTO_STORE"
    mkdir -p "$RECORD_KOTO_STORE"
    (cd "$A" && koto init "$S" --template t >/dev/null && printf '%s' "$RID" | koto context add "$S" run_id)
    : > "$RECORD_KOTO_STORE/calls.log"
}
run_trail() { # run_trail <args>: from the root's checkout
    OUT=$(cd "$A" && bash "$TRAIL" "$@" </dev/null 2>"$WORK/stderr")
    RC=$?
}
get_in() { # get_in <dir> <session> <key>
    (cd "$1" && koto context get "$2" "$3" 2>/dev/null)
}
root_get() { get_in "$A" "$S" "$1"; }
keys() { (cd "$A" && koto context list "$S"); }
writes() { grep -cE "$(printf '\t')(init|context add|context remove) " "$RECORD_KOTO_STORE/calls.log"; }

# --- self ---------------------------------------------------------------------------

new_store
run_trail self --session "$S"
SELF=$(root_get trail/self)
SID=$(cd "$A" && koto session list | jq -r --arg s "$S" '.[] | select(.id == $s) | .session_id')
if [ "$RC" -eq 0 ] && [ "$(jq -r '.workspace' <<<"$SELF")" = "$A" ] && [ "$(jq -r '.session' <<<"$SELF")" = "$S" ] \
    && [ "$(jq -r '.session_id' <<<"$SELF")" = "$SID" ] && [ "$(jq -r '.run_id' <<<"$SELF")" = "$RID" ]; then
    pass "self: trail/self names the checkout, the session, its koto id and its run_id"
else
    fail "self: exit $RC, [$SELF], stderr [$(cat "$WORK/stderr")]"
fi

new_store
(cd "$A" && koto context remove "$S" run_id)
run_trail self --session "$S"
[ "$RC" -eq 65 ] && [ -z "$(root_get trail/self)" ] && pass "self: a session with no run_id refuses (65), nothing written" \
    || fail "self without run_id: exit $RC"

# --- pr -------------------------------------------------------------------------------

new_store
run_trail pr --session "$S" --repo Octo/Repo.X --number 12 --role home --state open
DOC=$(root_get trail/pr/octo.repo.x.12)
if [ "$RC" -eq 0 ] && [ "$(jq -c '{repo, number, role, state}' <<<"$DOC")" = '{"repo":"octo/repo.x","number":12,"role":"home","state":"open"}' ] \
    && [[ $(jq -r '.recorded_at' <<<"$DOC") =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:]{8}Z$ ]]; then
    pass "pr: trail/pr/<owner>.<repo>.<n> holds the lowercased repository, the number, role, state and time"
else
    fail "pr: exit $RC, [$DOC], stderr [$(cat "$WORK/stderr")]"
fi

for args in "--repo o/r --number 7 --role boss --state open" \
            "--repo o/r --number 7 --role home --state shipped" \
            "--repo o --number 7 --role home --state open" \
            "--repo o/r/x --number 7 --role home --state open" \
            "--repo -o/r --number 7 --role home --state open" \
            "--repo o/.. --number 7 --role home --state open" \
            "--repo o/r --number 0 --role home --state open" \
            "--repo o/r --number 7x --role home --state open"; do
    new_store
    # shellcheck disable=SC2086
    run_trail pr --session "$S" $args
    [ "$RC" -eq 65 ] && [ "$(writes)" -eq 0 ] && pass "pr refuses [$args] (65), nothing written" \
        || fail "pr [$args]: exit $RC, writes $(writes)"
done

# --- index ------------------------------------------------------------------------------

DIR="/tmp/shirabe-run-record/$OWNER"
new_store
run_trail index --repo "$OWNER/R" --number 7 --session "$S" --mode single-pr --topic topic
CANON=$(cd "$DIR" 2>/dev/null && pwd -P)
NAME="pr.$OWNER.r.7"
ENTRY=$(get_in "$DIR" "$NAME" "run/$RID")
SID=$(cd "$A" && koto session list | jq -r --arg s "$S" '.[] | select(.id == $s) | .session_id')
if [ "$RC" -eq 0 ] \
    && [ "$(jq -c '{workspace, session, session_id, mode, topic}' <<<"$ENTRY")" = "$(jq -nc --arg w "$A" --arg s "$S" --arg i "$SID" '{workspace: $w, session: $s, session_id: $i, mode: "single-pr", topic: "topic"}')" ] \
    && [[ $(jq -r '.written_at' <<<"$ENTRY") =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:]{8}Z$ ]]; then
    pass "index: run/<run_id> in pr.<owner>.<repo>.<n> names the root's workspace, session, id, mode and topic"
else
    fail "index: exit $RC, entry [$ENTRY], stderr [$(cat "$WORK/stderr")]"
fi
if grep -qF "$(printf '%s\tinit %s --template ' "$CANON" "$NAME")" "$RECORD_KOTO_STORE/calls.log" \
    && grep -qF "$(printf '%s\tcontext add %s run/%s' "$CANON" "$NAME" "$RID")" "$RECORD_KOTO_STORE/calls.log"; then
    pass "index: the session is opened and written from the shared address"
else
    fail "index calls: [$(cat "$RECORD_KOTO_STORE/calls.log")]"
fi
if [ -n "$(root_get trail/self)" ]; then
    pass "index: a root with no trail/self gets one first"
else
    fail "index: no trail/self written"
fi
if grep -q 'skill-session.md --attach-live' "$RECORD_KOTO_STORE/calls.log"; then
    pass "index: the index session is opened from the skill-session template, attaching when it exists"
else
    fail "index template: [$(grep init "$RECORD_KOTO_STORE/calls.log")]"
fi

run_trail index --repo "$OWNER/r" --number 7 --session "$S" --mode single-pr --topic topic
[ "$RC" -eq 0 ] && pass "index: a second write attaches to the index session and rewrites the entry" \
    || fail "index again: exit $RC, stderr [$(cat "$WORK/stderr")]"

# A trail/self naming another session is not this root's address.
new_store
(cd "$A" && jq -nc --arg w "$A" '{workspace: $w, session: "execute-other", session_id: "abc", run_id: "00112233445566778899aabbccddeeff"}' \
    | koto context add "$S" trail/self)
run_trail index --repo "$OWNER/r" --number 8 --session "$S" --mode single-pr --topic topic
[ "$RC" -eq 65 ] && [ -z "$(get_in "$DIR" "pr.$OWNER.r.8" "run/$RID")" ] \
    && pass "index: a trail/self naming another session refuses (65), no entry" \
    || fail "index with a foreign trail/self: exit $RC"

for args in "--mode serial --topic topic" "--mode single-pr --topic Topic" "--mode single-pr --topic a/b"; do
    new_store
    # shellcheck disable=SC2086
    run_trail index --repo "$OWNER/r" --number 7 --session "$S" $args
    [ "$RC" -eq 65 ] && [ "$(writes)" -eq 0 ] && pass "index refuses [$args] (65), nothing written" \
        || fail "index [$args]: exit $RC"
done

new_store
export RECORD_KOTO_WORKSPACE_OPTION=present
run_trail pr --session "$S" --repo "$OWNER/r" --number 9 --role home --state open
R1=$RC
run_trail index --repo "$OWNER/r" --number 9 --session "$S" --mode single-pr --topic topic
unset RECORD_KOTO_WORKSPACE_OPTION
if [ "$R1" -eq 0 ] && [ "$RC" -eq 0 ] && ! grep -q -- '--workspace' "$RECORD_KOTO_STORE/calls.log"; then
    pass "option present: every write still runs from its directory, none carries --workspace"
else
    fail "present-mode writes: pr $R1, index $RC, calls [$(cat "$RECORD_KOTO_STORE/calls.log")]"
fi

# --- usage and koto failures ------------------------------------------------------------------

for args in "" "nope --session $S" "pr --session $S" "self --session $S --session $S" \
            "self --session" "self --session $S --repo o/r" "pr --session $S --repo o/r --number 7 --role home --state open --extra x"; do
    new_store
    # shellcheck disable=SC2086
    run_trail $args
    [ "$RC" -eq 64 ] && [ ! -s "$RECORD_KOTO_STORE/calls.log" ] && pass "usage: [$args] is 64, no koto call" \
        || fail "usage [$args]: exit $RC, calls [$(cat "$RECORD_KOTO_STORE/calls.log")]"
done

new_store
export RECORD_KOTO_FAIL_WRITES=1
run_trail pr --session "$S" --repo o/r --number 7 --role home --state open
unset RECORD_KOTO_FAIL_WRITES
[ "$RC" -eq 70 ] && pass "a failed koto write is 70" || fail "failed write: exit $RC"

echo
echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed"
[ "$FAIL_COUNT" -eq 0 ] || exit 1
exit 0
