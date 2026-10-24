#!/usr/bin/env bash
# run-id_test.sh — run-id.sh's modes, against a file-backed koto stub
# Part of the execute skill
#
# Asserts:
#   get    mints a 32-hex id once, stores it as run_id, and returns the same
#          id on every later call; two sessions get different ids
#   seed   stores a given id only when the session has none
#   adopt  stores a given id whether or not the session has one
#   stamp, restamp, carry and marker exit 64 as unknown verbs and write
#          nothing: a PR's text carries nothing of the run
#   usage errors exit 64; a failing koto exits 66
#
# Usage: run-id_test.sh
# Exit codes: 0 all pass, 1 a failure

set -uo pipefail

SCRIPT_DIR=$(CDPATH='' cd "$(dirname "$0")" && pwd)
RUNID="$SCRIPT_DIR/run-id.sh"

PASS_COUNT=0
FAIL_COUNT=0
pass() { echo "PASS: $*"; PASS_COUNT=$((PASS_COUNT + 1)); }
fail() { echo "FAIL: $*"; FAIL_COUNT=$((FAIL_COUNT + 1)); }

command -v jq >/dev/null 2>&1 || { echo "FAIL: jq is required" >&2; exit 1; }

WORK=$(mktemp -d "${TMPDIR:-/tmp}/run-id-test.XXXXXX") || exit 1
trap 'rm -rf "$WORK"' EXIT
BIN="$WORK/bin"
mkdir -p "$BIN" "$WORK/ctx"

# koto stub: `koto context exists|get|add <session> <key>`, one file per key.
cat > "$BIN/koto" <<'STUB'
#!/usr/bin/env bash
ctx="${KOTO_CTX:?}"
[ -f "$ctx/fail" ] && exit 1
[ "$1" = context ] || { echo "koto stub: only context" >&2; exit 2; }
f="$ctx/$3.$4"
case "$2" in
    exists)
        [ -f "$ctx/exists-rc" ] && exit "$(cat "$ctx/exists-rc")"
        [ -f "$f" ] ;;
    get) [ -f "$f" ] && cat "$f" ;;
    add) cat > "$f" ;;
    *) exit 2 ;;
esac
STUB
chmod +x "$BIN/koto"

rid() { KOTO_CTX="$WORK/ctx" PATH="$BIN:$PATH" bash "$RUNID" "$@"; }

# --- get ---------------------------------------------------------------------------

rid get execute-demo >/dev/null 2>&1; RC0=$?
if [ "$RC0" -eq 67 ] && [ ! -f "$WORK/ctx/execute-demo.run_id" ]; then
    pass "get on a session with no id exits 67 and mints nothing"
else
    fail "get on a session with no id: exit $RC0, stored [$(cat "$WORK/ctx/execute-demo.run_id" 2>/dev/null)]"
fi
A1=$(rid mint execute-demo); RC1=$?
A2=$(rid get execute-demo); RC2=$?
B1=$(rid mint execute-other)
A3=$(rid mint execute-demo)
if [ "$A3" = "$A1" ]; then pass "mint on a session that has an id returns it and mints no second one"; else fail "mint replaced an existing id: [$A1] then [$A3]"; fi
if [ "$RC1" -eq 0 ] && [[ $A1 =~ ^[0-9a-f]{32}$ ]]; then pass "mint mints a 32-hex id"; else fail "mint: [$A1] exit $RC1"; fi
if [ "$RC2" -eq 0 ] && [ "$A1" = "$A2" ]; then pass "get returns the minted id"; else fail "get after mint: [$A1] then [$A2]"; fi
if [ "$(cat "$WORK/ctx/execute-demo.run_id")" = "$A1" ]; then pass "mint stores the id as run_id"; else fail "run_id not stored"; fi
if [ "$A1" != "$B1" ]; then pass "two sessions get different ids"; else fail "two sessions share [$A1]"; fi

# --- seed --------------------------------------------------------------------------

S=0123456789abcdef0123456789abcdef
rid seed execute-fresh "$S"
if [ "$(rid get execute-fresh)" = "$S" ]; then pass "seed stores the id on a session with none"; else fail "seed did not store"; fi
rid seed execute-demo "$S"
if [ "$(rid get execute-demo)" = "$A1" ]; then pass "seed leaves an existing id alone"; else fail "seed overwrote an existing id"; fi

# --- adopt -------------------------------------------------------------------------

rid seed execute-adopt "$A1"
rid adopt execute-adopt "$S"; RC=$?
if [ "$RC" -eq 0 ] && [ "$(rid get execute-adopt)" = "$S" ]; then pass "adopt overwrites a session's existing id"; else fail "adopt: exit $RC, id [$(rid get execute-adopt)]"; fi
rid adopt execute-adopt-fresh "$S"; RC=$?
if [ "$RC" -eq 0 ] && [ "$(rid get execute-adopt-fresh)" = "$S" ]; then pass "adopt stores the id on a session with none"; else fail "adopt on a fresh session: exit $RC"; fi

# --- the marker verbs are gone -------------------------------------------------------

# A PR's text carries nothing of the run: the verbs that once wrote or read a
# marker line in a body are unknown verbs now, and they touch no file.
printf 'Body.\n' > "$WORK/body.md"
cp "$WORK/body.md" "$WORK/body.orig"
for verb in stamp restamp carry marker; do
    case "$verb" in
        stamp|restamp) args=("$S" "$WORK/body.md") ;;
        carry) args=("$WORK/body.md" "$WORK/body.md") ;;
        marker) args=("$WORK/body.md") ;;
    esac
    ERR=$(rid "$verb" "${args[@]}" 2>&1 >/dev/null); RC=$?
    if [ "$RC" -eq 64 ] && cmp -s "$WORK/body.md" "$WORK/body.orig"; then
        case "$ERR" in
            *"unknown mode [$verb]"*) pass "$verb exits 64 as an unknown verb and writes nothing" ;;
            *) fail "$verb: exit 64 but not as an unknown verb: [$ERR]" ;;
        esac
    else
        fail "$verb: exit $RC, body [$(cat "$WORK/body.md")]"
    fi
done
case "$(rid 2>&1)" in
    *stamp*|*carry*|*marker*) fail "the usage line still names a marker verb" ;;
    *) pass "the usage line names only mint, get, seed and adopt" ;;
esac

# --- usage and failures ------------------------------------------------------------

expect_rc() { # expect_rc <label> <rc> <args...>
    local label="$1" want="$2"; shift 2
    rid "$@" >/dev/null 2>&1
    local rc=$?
    if [ "$rc" -eq "$want" ]; then pass "$label (exit $want)"; else fail "$label: want exit $want, got $rc"; fi
}
expect_rc "no mode" 64
expect_rc "unknown mode" 64 forge execute-demo
expect_rc "mint without a session" 64 mint
expect_rc "get without a session" 64 get
expect_rc "get with a bad session name" 64 get '-x'
expect_rc "seed with a bad id" 64 seed execute-demo ABC
expect_rc "adopt with a bad id" 64 adopt execute-demo ABC
expect_rc "adopt without an id" 64 adopt execute-demo
touch "$WORK/ctx/fail"
expect_rc "mint when every koto call fails (the add of a fresh id fails)" 66 mint execute-brand-new
rm -f "$WORK/ctx/fail"
echo 2 > "$WORK/ctx/exists-rc"
expect_rc "get when koto context exists errors (not 'absent'): an error, not a new id" 66 get execute-demo
expect_rc "mint when koto context exists errors: an error, not a second id" 66 mint execute-demo
rm -f "$WORK/ctx/exists-rc"
if [ "$(cat "$WORK/ctx/execute-demo.run_id")" = "$A1" ]; then
    pass "an exists error left the stored id untouched"
else
    fail "an exists error changed the stored id"
fi

echo
echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed"
[ "$FAIL_COUNT" -eq 0 ] || exit 1
exit 0
