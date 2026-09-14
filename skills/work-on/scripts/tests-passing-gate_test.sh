#!/usr/bin/env bash
# tests-passing-gate_test.sh — the gate must leave something to read.
#
# The gate used to end in `2>/dev/null`. A run whose test suite fork bombed was
# recorded as `timed_out` with exit -1 and nothing else, while the command had
# been writing evidence the whole time.
#
# Removing the redirect would not have been enough, and that is the point of
# these cases. koto keeps a command gate's stderr only for a spawn or wait
# failure: a non-zero exit is reported as {"exit_code": N, "error": ""} and a
# timeout as {"error": "timed_out"} (koto/src/gate.rs:281-306). So the gate has
# to persist its own output, and Case 3 — a command KILLED mid-run, which is the
# shape that actually happened — is the one that decides whether this works.
#
# The cases run the expression EXTRACTED FROM THE TEMPLATE, with `go` replaced by
# a stub. A copy pasted here would keep passing after someone edited the real one.
#
# Usage: tests-passing-gate_test.sh
# Exit codes: 0 all pass, 1 any failed.

set -uo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
SKILL_DIR=$(cd "$SCRIPT_DIR/.." && pwd)
TEMPLATE="$SKILL_DIR/koto-templates/work-on.md"

PASS_COUNT=0
FAIL_COUNT=0
GREEN='\033[0;32m'; RED='\033[0;31m'; NC='\033[0m'
pass() { echo -e "${GREEN}PASS${NC}: $*"; PASS_COUNT=$((PASS_COUNT+1)); }
fail() { echo -e "${RED}FAIL${NC}: $*"; FAIL_COUNT=$((FAIL_COUNT+1)); }

TMPS=()
cleanup() { for d in "${TMPS[@]:-}"; do [[ -n "$d" ]] && rm -rf "$d"; done; return 0; }
trap cleanup EXIT

# The gate command, read out of the template. BOTH YAML quote styles are
# unquoted, and that is not tidiness: an extractor that only understood the
# single-quoted form mis-read the double-quoted one it replaced, passed the
# quotes through to `sh -c`, and produced a 127 "not found". The cases then
# failed against the old gate for a reason that had nothing to do with the
# defect — a red result that would have been mistaken for proof.
GATE=$(awk '
    /^      tests_passing:$/ { found=1 }
    found && /^        command:/ {
        sub(/^        command:[[:space:]]*/, "")
        if (substr($0, 1, 1) == "\"") {
            sub(/^"/, ""); sub(/"$/, "")
            gsub(/\\"/, "\"")
        } else if (substr($0, 1, 1) == "'"'"'") {
            sub(/^'"'"'/, ""); sub(/'"'"'$/, "")
        }
        print
        exit
    }
' "$TEMPLATE")

if [[ -z "$GATE" ]]; then
    echo "could not read the tests_passing gate command from $TEMPLATE" >&2
    exit 2
fi

# run_gate <dir> <go-stub-body> — substitute {{SESSION_DIR}} as koto would, put
# the stub ahead of any real go, and run the expression from <dir>.
run_gate() {
    local dir="$1" stub="$2"
    local session="$dir/session"
    mkdir -p "$session" "$dir/bin"
    printf '%s\n' "$stub" > "$dir/bin/go"
    chmod +x "$dir/bin/go"
    local cmd="${GATE//\{\{SESSION_DIR\}\}/$session}"
    ( cd "$dir" && PATH="$dir/bin:$PATH" sh -c "$cmd" )
}

new_repo() {
    local d; d=$(mktemp -d); TMPS+=("$d")
    printf 'module example.invalid/x\n' > "$d/go.mod"
    echo "$d"
}

# ---------------------------------------------------------------------------
# Case 1 — a failing suite: the verdict survives AND the output is readable.
# ---------------------------------------------------------------------------
D=$(new_repo)
run_gate "$D" '#!/usr/bin/env bash
echo "ok   example.invalid/x/good"
echo "--- FAIL: TestThing (0.00s)" >&2
echo "    thing_test.go:12: expected 3, got 4" >&2
exit 1'
status=$?

if [[ "$status" -ne 1 ]]; then
    fail "a failing suite must keep its own exit status, got $status"
elif ! grep -q "expected 3, got 4" "$D/session/tests_passing.log" 2>/dev/null; then
    fail "the failure detail did not reach the log: $(cat "$D/session/tests_passing.log" 2>/dev/null | head -c 200)"
else
    pass "a failing suite keeps its exit status and its stderr reaches the log"
fi

# Case 2 — a passing suite still passes, and stdout is captured too.
D=$(new_repo)
run_gate "$D" '#!/usr/bin/env bash
echo "ok   example.invalid/x	0.004s"
exit 0'
status=$?
if [[ "$status" -eq 0 ]] && grep -q "0.004s" "$D/session/tests_passing.log" 2>/dev/null; then
    pass "a passing suite passes, with its output captured"
else
    fail "passing case: status $status, log: $(cat "$D/session/tests_passing.log" 2>/dev/null | head -c 200)"
fi

# ---------------------------------------------------------------------------
# Case 3 — THE CASE THIS EXISTS FOR. A command killed mid-run, which is what a
# runaway suite looks like from outside, must still leave its partial output.
# koto reports a timeout as `timed_out` and nothing else, so the file is the
# only place an operator can learn what the command was doing.
# ---------------------------------------------------------------------------
D=$(new_repo)
(
    run_gate "$D" '#!/usr/bin/env bash
echo "spawning worker 1" >&2
echo "spawning worker 2" >&2
sleep 30'
) & gate_pid=$!
# Give it long enough to write, then kill it the way a timeout would.
sleep 1
kill -TERM "$gate_pid" 2>/dev/null
wait "$gate_pid" 2>/dev/null

if grep -q "spawning worker 2" "$D/session/tests_passing.log" 2>/dev/null; then
    pass "a command killed mid-run leaves its partial output in the log"
else
    fail "a killed command left nothing to read, which is the defect: $(cat "$D/session/tests_passing.log" 2>/dev/null | head -c 200)"
fi

# ---------------------------------------------------------------------------
# Case 4 — the control: the form this replaced. With `2>/dev/null` the same
# failing suite leaves nothing, which is what made the original unreadable.
# ---------------------------------------------------------------------------
D=$(new_repo)
mkdir -p "$D/session" "$D/bin"
printf '%s\n' '#!/usr/bin/env bash
echo "--- FAIL: TestThing" >&2
exit 1' > "$D/bin/go"
chmod +x "$D/bin/go"
old_out=$( cd "$D" && PATH="$D/bin:$PATH" sh -c '[ ! -f go.mod ] || go test ./... 2>/dev/null' 2>&1 )
if [[ -z "$old_out" ]]; then
    pass "the replaced form discarded the failure detail, so Case 1 is a real change"
else
    fail "the control produced output, so it does not demonstrate what was fixed: $old_out"
fi

# Case 5 — a repository with no go.mod is untouched: no command runs, no log.
D=$(mktemp -d); TMPS+=("$D")
run_gate "$D" '#!/usr/bin/env bash
echo "this must never run" >&2
exit 1'
status=$?
if [[ "$status" -eq 0 ]] && [[ ! -f "$D/session/tests_passing.log" ]]; then
    pass "a repository with no go.mod passes without running anything"
else
    fail "no-go.mod case: status $status, log present: $([[ -f "$D/session/tests_passing.log" ]] && echo yes || echo no)"
fi

echo
echo "tests-passing-gate_test.sh: $PASS_COUNT passed, $FAIL_COUNT failed"
[[ "$FAIL_COUNT" -eq 0 ]]
