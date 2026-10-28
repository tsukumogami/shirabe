#!/usr/bin/env bash
# child-read_test.sh -- child-read.sh runs its one koto read in the node
# worktree, so a work item's session bound there answers it.
# Part of the execute skill
#
# koto is a stub that answers `status` and `context get` for one session,
# bound to the node worktree as koto's cloud backend binds a session to the
# directory it was opened in: from any other directory it exits 2 with
# session_bound_elsewhere. Every call logs its directory and arguments.
#
# Cases:
#   status from the coordination checkout, through the script: answered, the
#     call made in the worktree; the same call made directly is refused (the
#     stub's control)
#   context get of summary.md: answered
#   koto's own failure passes through with its exit status
#   usage (64, no koto call): a missing or absent worktree, a verb other than
#     the two, a session or key outside its pattern, extra arguments
#
# Usage: child-read_test.sh
# Exit codes: 0 all pass, 1 a failure

set -uo pipefail
. "$(dirname "$0")/../../../scripts/lib/koto-test-guard.sh" || exit 1

SCRIPT_DIR=$(CDPATH='' cd "$(dirname "$0")" && pwd)
READ="$SCRIPT_DIR/child-read.sh"

PASS_COUNT=0
FAIL_COUNT=0
pass() { echo "PASS: $*"; PASS_COUNT=$((PASS_COUNT + 1)); }
fail() { echo "FAIL: $*"; FAIL_COUNT=$((FAIL_COUNT + 1)); }

WORK=$(mktemp -d "${TMPDIR:-/tmp}/child-read-test.XXXXXX") || exit 1
# This trap replaces koto-test-guard.sh's, so it removes the guard's directory too.
trap 'rm -rf "$WORK"; case "${KOTO_TEST_GUARD_DIR:-}" in */suite-scratch.*) rm -rf "$KOTO_TEST_GUARD_DIR" ;; esac' EXIT
mkdir -p "$WORK/bin" "$WORK/coord" "$WORK/node-wt"
NODE_WT=$(cd "$WORK/node-wt" && pwd -P)
CHILD=work-on-t-core-2
export CR_LOG="$WORK/calls.log" CR_BOUND="$NODE_WT" CR_CHILD="$CHILD"
cat > "$WORK/bin/koto" <<'STUB'
#!/usr/bin/env bash
printf '%s|%s\n' "$(pwd -P)" "$*" >> "$CR_LOG"
[ -z "${CR_FAIL:-}" ] || { echo "koto: failed" >&2; exit "$CR_FAIL"; }
case "$1 ${2:-}" in
    "status $CR_CHILD") s=$2 ;;
    "context get") s=$3 ;;
    *) exit 9 ;;
esac
if [ "$s" = "$CR_CHILD" ] && [ "$(pwd -P)" != "$CR_BOUND" ]; then
    echo "session_bound_elsewhere: session '$s' is bound to $CR_BOUND, not to the directory this command ran in" >&2
    exit 2
fi
case "$1" in
    status) printf '{"name":"%s","current_state":"done","is_terminal":true}\n' "$s" ;;
    context) printf '## Changes Made\n\nThe parser.\n' ;;
esac
STUB
chmod +x "$WORK/bin/koto"
export PATH="$WORK/bin:$PATH"

# --- the reads ----------------------------------------------------------------------

: > "$CR_LOG"
OUT=$(cd "$WORK/coord" && bash "$READ" "$NODE_WT" status "$CHILD" 2>"$WORK/err"); RC=$?
if [ "$RC" -eq 0 ] && [ "$(printf '%s' "$OUT" | jq -r .is_terminal)" = true ]; then
    pass "status from the coordination checkout: the bound child answers"
else
    fail "status: rc=$RC out=[$OUT] err=[$(cat "$WORK/err")]"
fi
[ "$(cut -d'|' -f1 "$CR_LOG")" = "$NODE_WT" ] && pass "the koto call ran in the node worktree" \
    || fail "the koto call ran in [$(cut -d'|' -f1 "$CR_LOG")]"
(cd "$WORK/coord" && koto status "$CHILD" >/dev/null 2>"$WORK/err"); RC=$?
[ "$RC" -eq 2 ] && grep -q session_bound_elsewhere "$WORK/err" \
    && pass "control: the same read made directly from the coordination checkout is refused" \
    || fail "control: rc=$RC err=[$(cat "$WORK/err")]"

OUT=$(cd "$WORK/coord" && bash "$READ" "$NODE_WT" context get "$CHILD" summary.md 2>"$WORK/err"); RC=$?
[ "$RC" -eq 0 ] && grep -q '^## Changes Made' <<<"$OUT" && pass "context get summary.md: answered" \
    || fail "context get: rc=$RC out=[$OUT] err=[$(cat "$WORK/err")]"

OUT=$(cd "$WORK/coord" && CR_FAIL=3 bash "$READ" "$NODE_WT" status "$CHILD" 2>"$WORK/err"); RC=$?
[ "$RC" -eq 3 ] && grep -q 'koto: failed' "$WORK/err" && pass "koto's own failure passes through (3)" \
    || fail "koto failure: rc=$RC err=[$(cat "$WORK/err")]"

# --- usage ----------------------------------------------------------------------------

: > "$CR_LOG"
for args in "" "$WORK/no-such-dir status $CHILD" "$NODE_WT" "$NODE_WT next $CHILD" \
            "$NODE_WT context add $CHILD summary.md" "$NODE_WT status" "$NODE_WT status $CHILD extra" \
            "$NODE_WT status -x" "$NODE_WT context get $CHILD" "$NODE_WT context get $CHILD ../x" \
            "$NODE_WT context get $CHILD summary.md extra"; do
    # shellcheck disable=SC2086 # args is a word list
    (cd "$WORK/coord" && bash "$READ" $args >/dev/null 2>&1); RC=$?
    [ "$RC" -eq 64 ] && pass "usage [${args#"$NODE_WT"}] exits 64" || fail "usage [$args]: rc=$RC"
done
[ -s "$CR_LOG" ] && fail "a usage error ran koto: $(head -1 "$CR_LOG")" || pass "no usage error ran koto"

echo
echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed"
[ "$FAIL_COUNT" -eq 0 ] || exit 1
exit 0
