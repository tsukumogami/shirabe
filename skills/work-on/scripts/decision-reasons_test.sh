#!/usr/bin/env bash
# decision-reasons_test.sh -- the scrutiny_decider slice, from the session log
# Part of the work-on skill
#
# decision-reasons.sh prints the decisions a run recorded in `analysis` and
# `implementation` as `- choice:` / `  reason:` lines. These cases pin the
# exact bytes, since the slice is what Jev grades and what the contract's
# figures measure, and the exits a gate reads as a fallback.
#
# The last cases pin the text that tells an agent how to answer a pending
# batch, in the scrutiny directive and in phase-4a-scrutiny.md. They need no
# koto, so they run on the macOS bash 3.2 leg too.
#
# Usage: decision-reasons_test.sh
#
# Exit codes:
#   0 -- all cases pass
#   1 -- one or more cases failed

set -uo pipefail
. "$(dirname "$0")/../../../scripts/lib/koto-test-guard.sh" || exit 1

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
SCRIPT="$SCRIPT_DIR/decision-reasons.sh"
SKILL_DIR=$(cd "$SCRIPT_DIR/.." && pwd)
TEMPLATE="$SKILL_DIR/koto-templates/work-on.md"
PHASE="$SKILL_DIR/references/phases/phase-4a-scrutiny.md"

PASS_COUNT=0
FAIL_COUNT=0

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

pass() { echo -e "${GREEN}PASS${NC}: $*"; PASS_COUNT=$((PASS_COUNT + 1)); }
fail() { echo -e "${RED}FAIL${NC}: $*"; FAIL_COUNT=$((FAIL_COUNT + 1)); }

command -v jq >/dev/null 2>&1 || { echo "SKIP: jq not on PATH -- no case ran"; exit 0; }
[ -x "$SCRIPT" ] || { echo "FAIL: $SCRIPT is missing or not executable" >&2; exit 1; }

WORKDIR=$(mktemp -d) || exit 1
cleanup() { [ -n "${WORKDIR:-}" ] && chmod -R u+rwx "$WORKDIR" 2>/dev/null; [ -n "${WORKDIR:-}" ] && rm -rf "$WORKDIR"; return 0; }
ktg_on_exit cleanup

HEADER='{"schema_version":1,"workflow":"t","session_id":"s-1","template_name":"work-on"}'

# A run's log: decisions in analysis (two visits), implementation and
# verification, with alternatives, runs of whitespace, a missing rationale,
# an empty choice and multibyte text.
LOG="$WORKDIR/koto-t.state.jsonl"
{
    printf '%s\n' "$HEADER"
    printf '%s\n' '{"seq":1,"type":"transitioned","payload":{"from":"entry","to":"analysis"}}'
    printf '%s\n' '{"seq":2,"type":"decision_recorded","payload":{"state":"analysis","decision":{"choice":"Read the log path the gate passes","rationale":"koto decisions list sees only the current state","alternatives_considered":["koto decisions list","a context key"]}}}'
    printf '%s\n' '{"seq":3,"type":"decision_recorded","payload":{"state":"analysis","decision":{"choice":"  Keep   one\tjq program ","rationale":"one\nimplementation\n\nfor gate, fixtures   and measurement"}}}'
    printf '%s\n' '{"seq":4,"type":"decision_recorded","payload":{"state":"implementation","decision":{"choice":"Name the café test — naïve","rationale":"它保持不变"}}}'
    printf '%s\n' '{"seq":5,"type":"decision_recorded","payload":{"state":"implementation","decision":{"choice":"No rationale given"}}}'
    printf '%s\n' '{"seq":6,"type":"decision_recorded","payload":{"state":"implementation","decision":{"choice":"","rationale":"an empty choice"}}}'
    printf '%s\n' '{"seq":7,"type":"decision_recorded","payload":{"state":"verification","decision":{"choice":"Not in the slice","rationale":"verification is outside it"}}}'
    printf '%s\n' '{"seq":8,"type":"transitioned","payload":{"from":"implementation","to":"analysis"}}'
    printf '%s\n' '{"seq":9,"type":"decision_recorded","payload":{"state":"analysis","decision":{"choice":"A second visit","rationale":"later visits count too"}}}'
} > "$LOG"

WANT="$WORKDIR/want"
{
    printf '%s\n' '- choice: Read the log path the gate passes'
    printf '%s\n' '  reason: koto decisions list sees only the current state'
    printf '%s\n' '- choice: Keep one jq program'
    printf '%s\n' '  reason: one implementation for gate, fixtures and measurement'
    printf '%s\n' '- choice: Name the café test — naïve'
    printf '%s\n' '  reason: 它保持不变'
    printf '%s\n' '- choice: No rationale given'
    printf '%s\n' '  reason:'
    printf '%s\n' '- choice:'
    printf '%s\n' '  reason: an empty choice'
    printf '%s\n' '- choice: A second visit'
    printf '%s\n' '  reason: later visits count too'
} > "$WANT"

# --- the slice --------------------------------------------------------------

"$SCRIPT" slice "$LOG" > "$WORKDIR/got" 2> "$WORKDIR/err"
rc=$?
if [ "$rc" -eq 0 ] && cmp -s "$WANT" "$WORKDIR/got"; then
    pass "prints analysis and implementation decisions in log order, alternatives left out"
else
    fail "slice: exit $rc, diff: $(diff "$WANT" "$WORKDIR/got" | head -20)"
fi

if grep -q 'koto decisions list"\|a context key' "$WORKDIR/got"; then
    fail "an alternative was printed"
else
    pass "alternatives are never printed"
fi

if grep -q 'Not in the slice' "$WORKDIR/got"; then
    fail "a verification decision was printed"
else
    pass "a decision in another state is left out"
fi

# --- nothing to print --------------------------------------------------------

EMPTY="$WORKDIR/koto-empty.state.jsonl"
{
    printf '%s\n' "$HEADER"
    printf '%s\n' '{"seq":1,"type":"decision_recorded","payload":{"state":"verification","decision":{"choice":"x","rationale":"y"}}}'
} > "$EMPTY"
out=$("$SCRIPT" slice "$EMPTY" 2>/dev/null)
rc=$?
if [ "$rc" -eq 0 ] && [ -z "$out" ]; then
    pass "no matching decision prints nothing and exits 0"
else
    fail "no matching decision: exit $rc, stdout [$out]"
fi

# --- exits -------------------------------------------------------------------

"$SCRIPT" slice "$WORKDIR/absent.jsonl" >/dev/null 2>&1
rc=$?
[ "$rc" -eq 66 ] && pass "a missing log exits 66" || fail "a missing log exited $rc, want 66"

if [ "$(id -u)" -ne 0 ]; then
    UNREAD="$WORKDIR/koto-unread.state.jsonl"
    cp "$LOG" "$UNREAD"
    chmod 000 "$UNREAD"
    "$SCRIPT" slice "$UNREAD" >/dev/null 2>&1
    rc=$?
    [ "$rc" -eq 66 ] && pass "an unreadable log exits 66" || fail "an unreadable log exited $rc, want 66"
else
    echo "SKIP: running as root, an unreadable file is readable"
fi

BROKEN="$WORKDIR/koto-broken.state.jsonl"
{
    cat "$LOG"
    printf '%s\n' '{"seq":10,"type":"decision_recorded",'
} > "$BROKEN"
out=$("$SCRIPT" slice "$BROKEN" 2>/dev/null)
rc=$?
if [ "$rc" -eq 66 ] && [ -z "$out" ]; then
    pass "a line jq can't parse exits 66 with nothing printed"
else
    fail "a broken line: exit $rc, stdout [$out]"
fi

"$SCRIPT" >/dev/null 2>&1
rc=$?
[ "$rc" -eq 64 ] && pass "no arguments exits 64" || fail "no arguments exited $rc, want 64"

"$SCRIPT" project "$LOG" >/dev/null 2>&1
rc=$?
[ "$rc" -eq 64 ] && pass "an unknown mode exits 64" || fail "an unknown mode exited $rc, want 64"

NOJQ="$WORKDIR/nojq"
mkdir -p "$NOJQ"
PATH="$NOJQ" /bin/bash "$SCRIPT" slice "$LOG" >/dev/null 2>&1
rc=$?
[ "$rc" -eq 127 ] && pass "a missing jq exits 127" || fail "a missing jq exited $rc, want 127"

# --- how the agent answers a pending batch -----------------------------------

# The scrutiny directive: from the `## scrutiny` heading to the next `## `.
DIRECTIVE=$(awk '/^## scrutiny$/{on=1; next} on && /^## /{exit} on' "$TEMPLATE")
ANSWER='koto decider answer {{SESSION_NAME}} --gate scrutiny_decider --criterion work-on/scrutiny-decision-reasons --answer <pass|fail|unclear>'
for where in directive phase; do
    if [ "$where" = directive ]; then text="$DIRECTIVE"; else text=$(cat "$PHASE"); fi
    for phrase in "beside the seats" "decider is on" "advisory while" "awaiting" "carried round" "$ANSWER"; do
        flat=$(printf '%s' "$text" | tr '\n' ' ')
        if grep -qF -- "$phrase" <<<"$flat"; then
            pass "the $where says [$phrase]"
        else
            fail "the $where lost [$phrase]"
        fi
    done
done

echo ""
echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed"
[ "$FAIL_COUNT" -eq 0 ]
