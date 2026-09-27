#!/usr/bin/env bash
# run-id_test.sh — run-id.sh's four modes, against a file-backed koto stub
# Part of the execute skill
#
# Asserts:
#   get    mints a 32-hex id once, stores it as run_id, and returns the same
#          id on every later call; two sessions get different ids
#   seed   stores a given id only when the session has none
#   stamp  appends the marker line; is idempotent for the same id; refuses a
#          body naming another run (exit 65)
#   carry  keeps the live body's marker and drops any the new body invented;
#          an unmarked live body leaves the new body unmarked
#   a body run-id.sh stamped is one owned-pr.sh --run-id matches
#   usage errors exit 64; a failing koto exits 66
#
# Usage: run-id_test.sh
# Exit codes: 0 all pass, 1 a failure

set -uo pipefail

SCRIPT_DIR=$(CDPATH='' cd "$(dirname "$0")" && pwd)
RUNID="$SCRIPT_DIR/run-id.sh"
OWNED="$SCRIPT_DIR/owned-pr.sh"

PASS_COUNT=0
FAIL_COUNT=0
pass() { echo "PASS: $*"; PASS_COUNT=$((PASS_COUNT + 1)); }
fail() { echo "FAIL: $*"; FAIL_COUNT=$((FAIL_COUNT + 1)); }

command -v jq >/dev/null 2>&1 || { echo "FAIL: jq is required" >&2; exit 1; }

WORK=$(mktemp -d "${TMPDIR:-/tmp}/run-id-test.XXXXXX")
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

A1=$(rid get execute-demo); RC1=$?
A2=$(rid get execute-demo); RC2=$?
B1=$(rid get execute-other)
if [ "$RC1" -eq 0 ] && [[ $A1 =~ ^[0-9a-f]{32}$ ]]; then pass "get mints a 32-hex id"; else fail "get: [$A1] exit $RC1"; fi
if [ "$RC2" -eq 0 ] && [ "$A1" = "$A2" ]; then pass "get returns the stored id on a later call"; else fail "get is not stable: [$A1] then [$A2]"; fi
if [ "$(cat "$WORK/ctx/execute-demo.run_id")" = "$A1" ]; then pass "get stores the id as run_id"; else fail "run_id not stored"; fi
if [ "$A1" != "$B1" ]; then pass "two sessions get different ids"; else fail "two sessions share [$A1]"; fi

# --- seed --------------------------------------------------------------------------

S=0123456789abcdef0123456789abcdef
rid seed execute-fresh "$S"
if [ "$(rid get execute-fresh)" = "$S" ]; then pass "seed stores the id on a session with none"; else fail "seed did not store"; fi
rid seed execute-demo "$S"
if [ "$(rid get execute-demo)" = "$A1" ]; then pass "seed leaves an existing id alone"; else fail "seed overwrote an existing id"; fi

# --- stamp -------------------------------------------------------------------------

printf 'Implements docs/plans/PLAN-x.md.' > "$WORK/body.md"
rid stamp "$S" "$WORK/body.md"; RC=$?
if [ "$RC" -eq 0 ] && [ "$(tail -1 "$WORK/body.md")" = "<!-- shirabe-run: $S -->" ] \
    && [ "$(head -1 "$WORK/body.md")" = "Implements docs/plans/PLAN-x.md." ]; then
    pass "stamp appends the marker line after the body"
else
    fail "stamp: exit $RC, body [$(cat "$WORK/body.md")]"
fi
rid stamp "$S" "$WORK/body.md"
if [ "$(grep -c 'shirabe-run' "$WORK/body.md")" -eq 1 ]; then pass "stamp is idempotent"; else fail "stamp added a second marker"; fi
rid stamp "$A1" "$WORK/body.md" 2>/dev/null; RC=$?
if [ "$RC" -eq 65 ]; then pass "stamp refuses a body naming another run (exit 65)"; else fail "stamp over another run: exit $RC"; fi
if grep -q "$S" "$WORK/body.md" && ! grep -q "$A1" "$WORK/body.md"; then pass "a refused stamp leaves the body alone"; else fail "refused stamp changed the body"; fi

# --- carry -------------------------------------------------------------------------

printf 'Old part 1.\n\n---\n\nOld part 2.\n\n<!-- shirabe-run: %s -->\n' "$S" > "$WORK/live.md"
printf 'New part 1.\n\n---\n\nNew part 2.\n<!-- shirabe-run: %s -->\n' "$A1" > "$WORK/new.md"
rid carry "$WORK/live.md" "$WORK/new.md"; RC=$?
if [ "$RC" -eq 0 ] && grep -qxF "<!-- shirabe-run: $S -->" "$WORK/new.md" \
    && ! grep -qF "$A1" "$WORK/new.md" && grep -qxF "New part 2." "$WORK/new.md" \
    && [ "$(grep -c '^---$' "$WORK/new.md")" -eq 1 ]; then
    pass "carry keeps the live marker and drops an invented one"
else
    fail "carry: exit $RC, body [$(cat "$WORK/new.md")]"
fi
printf 'Adopted scoping PR body.\n' > "$WORK/live.md"
printf 'New part 1.\n\n---\n\nNew part 2.\n' > "$WORK/new.md"
rid carry "$WORK/live.md" "$WORK/new.md"
if ! grep -q 'shirabe-run' "$WORK/new.md" && grep -qxF "New part 2." "$WORK/new.md"; then
    pass "carry leaves an unmarked PR unmarked"
else
    fail "carry marked an unmarked PR: [$(cat "$WORK/new.md")]"
fi

# --- restamp ----------------------------------------------------------------------

printf 'Body line.\n  <!-- shirabe-run: %s -->\nmore words\n' "$A1" > "$WORK/re.md"
rid restamp "$S" "$WORK/re.md"; RC=$?
if [ "$RC" -eq 0 ] && grep -qxF "<!-- shirabe-run: $S -->" "$WORK/re.md" \
    && ! grep -qF "$A1" "$WORK/re.md" && grep -qxF "more words" "$WORK/re.md" \
    && [ "$(grep -c 'shirabe-run' "$WORK/re.md")" -eq 1 ]; then
    pass "restamp replaces every marker line (an indented one included) with this run's"
else
    fail "restamp: exit $RC, body [$(cat "$WORK/re.md")]"
fi

printf 'x\n   <!-- shirabe-run: %s -->   \n' "$S" > "$WORK/indent.md"
rid stamp "$S" "$WORK/indent.md"; RC=$?
if [ "$RC" -eq 0 ] && [ "$(grep -c 'shirabe-run' "$WORK/indent.md")" -eq 1 ]; then
    pass "stamp reads an indented copy of this run's own marker as this run's, as owned-pr.sh does"
else
    fail "stamp on an indented own marker: exit $RC, body [$(cat "$WORK/indent.md")]"
fi

# --- a stamped body is one owned-pr.sh matches -----------------------------------

cat > "$BIN/gh" <<'STUB'
#!/usr/bin/env bash
case "$1 ${2:-}" in
    "api user") echo '{"login":"octo"}' ;;
    "pr list") cat "${GH_LIST:?}" ;;
    *) exit 1 ;;
esac
STUB
chmod +x "$BIN/gh"
printf 'Implements docs/plans/PLAN-x.md.' > "$WORK/body.md"
rid stamp "$S" "$WORK/body.md"
jq -n --rawfile b "$WORK/body.md" '[{url: "https://github.com/o/r/pull/7", state: "OPEN",
    isCrossRepository: false, author: {login: "octo"}, baseRefName: "main",
    headRefName: "impl/x", body: $b}]' > "$WORK/list.json"
OUT=$(GH_LIST="$WORK/list.json" PATH="$BIN:$PATH" bash "$OWNED" --repo o/r --head impl/x \
    --state open --base main --run-id "$S" </dev/null 2>/dev/null)
if [ "$OUT" = "https://github.com/o/r/pull/7" ]; then pass "owned-pr.sh matches a body run-id.sh stamped"; else fail "owned-pr.sh on a stamped body: [$OUT]"; fi
GH_LIST="$WORK/list.json" PATH="$BIN:$PATH" bash "$OWNED" --repo o/r --head impl/x \
    --state open --base main --run-id "$A1" </dev/null >/dev/null 2>&1
RC=$?
if [ "$RC" -eq 5 ]; then pass "owned-pr.sh refuses the same body to another run (exit 5)"; else fail "another run on a stamped body: exit $RC"; fi

# --- the marker says nothing about where the run happened -------------------------

if [ "$(tail -1 "$WORK/body.md")" = "<!-- shirabe-run: $S -->" ] && ! grep -q '/' <<<"$(tail -1 "$WORK/body.md" | sed 's/<!--//; s/-->//')"; then
    pass "the marker line carries only the id"
else
    fail "the marker line: [$(tail -1 "$WORK/body.md")]"
fi

# --- usage and failures ------------------------------------------------------------

expect_rc() { # expect_rc <label> <rc> <args...>
    local label="$1" want="$2"; shift 2
    rid "$@" >/dev/null 2>&1
    local rc=$?
    if [ "$rc" -eq "$want" ]; then pass "$label (exit $want)"; else fail "$label: want exit $want, got $rc"; fi
}
expect_rc "no mode" 64
expect_rc "unknown mode" 64 mint execute-demo
expect_rc "get without a session" 64 get
expect_rc "get with a bad session name" 64 get '-x'
expect_rc "seed with a bad id" 64 seed execute-demo ABC
expect_rc "stamp with a bad id" 64 stamp xyz "$WORK/body.md"
expect_rc "stamp on a missing file" 74 stamp "$S" "$WORK/nope.md"
expect_rc "carry on a missing live file" 74 carry "$WORK/nope.md" "$WORK/body.md"
touch "$WORK/ctx/fail"
expect_rc "get when every koto call fails (the add of a fresh id fails)" 66 get execute-brand-new
rm -f "$WORK/ctx/fail"
echo 2 > "$WORK/ctx/exists-rc"
expect_rc "get when koto context exists errors (not 'absent'): no id is minted" 66 get execute-demo
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
