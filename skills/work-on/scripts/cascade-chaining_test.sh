#!/usr/bin/env bash
# cascade-chaining_test.sh — asserts what ONE koto tick does across the cascade
# states, not what each state would do in isolation.
#
# Why this test is shaped this way
# -------------------------------
# koto's advance loop chains through states within a single `koto next`: it
# keeps advancing while the next transition can be chosen without evidence
# (engine/advance.rs). The guard that stops it is having at least one
# CONDITIONAL transition — NOT having an `accepts:` block. execute.md's
# `escalate` is the worked counter-example: required evidence, one unconditional
# edge, chained straight through.
#
# So a state-by-state reading cannot tell you whether `cascade_run` is safe.
# Collapsing its three edges into one unconditional transition is a tempting
# simplification — two of them share a target — and it would let a tick run the
# cascade and land on a terminal in the same invocation, with the agent never
# seeing the directive. The `accepts:` block would still be there, and a
# reviewer asking "does this state still require evidence?" would see nothing
# wrong.
#
# Case 2 below is therefore the point of the file: it mutates the shipped
# template exactly that way and asserts the behaviour changes. If Case 2 ever
# passes, this test has stopped protecting anything.
#
# The state declarations are extracted from the SHIPPED template at run time
# rather than duplicated here, following retry-clearing_test.sh in this same
# directory. A test carrying its own copy would keep passing after the template
# drifted away from it.
#
# Usage: cascade-chaining_test.sh
#
# Exit codes:
#   0 — all cases pass, or koto is absent and the test skipped
#   1 — one or more cases failed
#   2 — preconditions unmet (states not found in the shipped template)

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
TEMPLATE="$SCRIPT_DIR/../koto-templates/work-on.md"

PASS_COUNT=0
FAIL_COUNT=0

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

pass() { echo -e "${GREEN}PASS${NC}: $*"; PASS_COUNT=$((PASS_COUNT+1)); }
fail() { echo -e "${RED}FAIL${NC}: $*"; FAIL_COUNT=$((FAIL_COUNT+1)); }
skip() { echo -e "${YELLOW}SKIP${NC}: $*"; }

TMPS=()
SESSIONS=()
# Ends with an explicit success. The last command in this trap is a test
# that is FALSE when the arrays are empty, and on bash 3.2 an EXIT trap's
# final status replaces the script's own -- so a clean `exit 0` on the skip
# path came back as 1, and the suite failed while every line printed said it
# had passed.
cleanup() {
    for s in "${SESSIONS[@]:-}"; do
        [[ -n "$s" ]] && koto workflow remove "$s" >/dev/null 2>&1 || true
    done
    for d in "${TMPS[@]:-}"; do [[ -n "$d" ]] && rm -rf "$d"; done
    return 0
}
trap cleanup EXIT

# Skip cleanly when koto is absent, matching retry-clearing_test.sh. The macOS
# bash-floor leg has no koto, and this test cannot run without the engine whose
# chaining it asserts. The Linux CI step is what stops that skip from hiding a
# koto that vanished: it installs koto first, so a missing engine fails there.
if ! command -v koto >/dev/null 2>&1; then
    skip "koto not on PATH; cascade chaining cannot be exercised without the engine"
    exit 0
fi
[[ -f "$TEMPLATE" ]] || { echo "template not found: $TEMPLATE"; exit 2; }

# Extract a state's YAML block from the shipped template's frontmatter.
extract_state() {
    local name="$1"
    awk -v want="  $name:" '
        $0 == want { found=1; print; next }
        found && /^  [a-zA-Z_][a-zA-Z0-9_]*:$/ { exit }
        found { print }
    ' "$TEMPLATE"
}

CASCADE_ENTRY=$(extract_state cascade_entry)
CASCADE_RUN=$(extract_state cascade_run)

[[ -n "$CASCADE_ENTRY" ]] || { echo "cascade_entry not found in $TEMPLATE"; exit 2; }
[[ -n "$CASCADE_RUN" ]] || { echo "cascade_run not found in $TEMPLATE"; exit 2; }

# Build a runnable fixture around the extracted states. `start` stands in for
# ci_monitor: it accepts evidence and routes into cascade_entry, so a tick that
# submits that evidence is the same shape as the real one.
build_fixture() {
    local dir="$1" run_block="$2" anchor_exit="$3"
    cat > "$dir/fixture.md" <<FIXTURE
---
name: cascade-chaining-fixture
version: "1.0"
description: Fixture exercising one tick across the cascade states.
initial_state: start
variables:
  ISSUE_NUMBER:
    description: Issue under test
    required: false
  PLAN_DOC:
    description: Caller-supplied PLAN, empty in every case here
    required: false
  PLUGIN_ROOT:
    description: >-
      Declared optional here, unlike the shipped template, so Case 5 can init
      without it and exercise what the gate does with an unresolved root.
    required: false
states:
  start:
    accepts:
      ci_outcome:
        type: enum
        values: [passing]
        required: true
    transitions:
      - target: cascade_entry
        when:
          ci_outcome: passing
$(if [[ "$anchor_exit" == "real" ]]; then echo "$CASCADE_ENTRY"; else echo "$CASCADE_ENTRY" | sed "s|command: .*|command: \"exit $anchor_exit\"|"; fi)
$run_block
  done:
    terminal: true
  done_blocked:
    terminal: true
    failure: true
    accepts:
      failure_reason:
        type: string
---

## start
Stand-in for ci_monitor.

## cascade_entry
No action.

## cascade_run
Run the cascade and report.

## done
Done.

## done_blocked
Blocked.
FIXTURE
}

tick_from_start() {
    local dir="$1" session="$2" anchor_exit="$3" run_block="$4"
    build_fixture "$dir" "$run_block" "$anchor_exit"
    koto init "$session" --template "$dir/fixture.md" >/dev/null 2>&1 || return 1
    SESSIONS+=("$session")
    koto next "$session" >/dev/null 2>&1 || true
    koto next "$session" --with-data '{"ci_outcome":"passing"}' 2>/dev/null
}

# ---------------------------------------------------------------------------
# Case 1 — the shipped shape: one tick from start must STOP at cascade_run.
#
# With an anchor present, the tick advances start -> cascade_entry -> cascade_run
# and must stop there, because cascade_run's conditional transitions cannot be
# chosen without evidence. If it reaches a terminal in this one invocation, the
# agent never saw the cascade directive and never ran the cascade.
# ---------------------------------------------------------------------------
D1=$(mktemp -d); TMPS+=("$D1")
OUT1=$(tick_from_start "$D1" "cascade-chain-shipped-$$" 0 "$CASCADE_RUN" || true)

if echo "$OUT1" | grep -q '"state":"cascade_run"'; then
    pass "shipped shape: one tick stops at cascade_run (agent sees the directive)"
elif echo "$OUT1" | grep -qE '"state":"done(_blocked)?"'; then
    fail "shipped shape: one tick chained past cascade_run to a terminal — the cascade would never run"
else
    fail "shipped shape: unexpected tick result: $(echo "$OUT1" | head -c 300)"
fi

# ---------------------------------------------------------------------------
# Case 2 — THE POINT OF THIS FILE.
#
# Collapse cascade_run's three conditional edges into one unconditional
# transition, leaving its `accepts:` block untouched. A state-by-state review
# sees a state that still requires evidence. A tick does not: it chains through.
#
# This case asserts the mutation IS detectable. If it ever reports PASS, the
# guard has gone and Case 1 is no longer evidence of anything.
# ---------------------------------------------------------------------------
MUTATED=$(echo "$CASCADE_RUN" | awk '
    /^    transitions:/ { print; print "      - target: done"; skipping=1; next }
    skipping && /^    [a-zA-Z_]/ { skipping=0 }
    skipping { next }
    { print }
')

D2=$(mktemp -d); TMPS+=("$D2")
OUT2=$(tick_from_start "$D2" "cascade-chain-mutated-$$" 0 "$MUTATED" || true)

if echo "$OUT2" | grep -qE '"state":"done"|"action":"done"'; then
    pass "all-unconditional mutation chains through to a terminal — the defect is detectable"
elif echo "$OUT2" | grep -q '"state":"cascade_run"'; then
    fail "all-unconditional mutation still stopped at cascade_run — this test no longer detects the defect it exists for"
else
    fail "mutation case: unexpected tick result: $(echo "$OUT2" | head -c 300)"
fi

# ---------------------------------------------------------------------------
# Case 3 — the silent no-anchor path.
#
# With no anchor, the tick must reach a terminal WITHOUT stopping at
# cascade_run. PRD R3: a maintainer fixing an ordinary bug must never learn a
# cascade step exists.
# ---------------------------------------------------------------------------
D3=$(mktemp -d); TMPS+=("$D3")
OUT3=$(tick_from_start "$D3" "cascade-chain-noanchor-$$" 1 "$CASCADE_RUN" || true)

if echo "$OUT3" | grep -q '"state":"cascade_run"'; then
    fail "no-anchor path stopped at cascade_run — R3 violated, the agent learns a cascade exists"
elif echo "$OUT3" | grep -qE '"state":"done"|"action":"done"'; then
    pass "no-anchor path reaches a terminal without stopping at cascade_run (R3 holds)"
else
    fail "no-anchor case: unexpected tick result: $(echo "$OUT3" | head -c 300)"
fi

# ---------------------------------------------------------------------------
# Case 4 — uncertainty is not absence.
#
# The finder exits 2 when it cannot decide: a non-numeric issue number, an
# unreadable docs/plans, or two PLANs naming the same issue. That must stop at
# done_blocked. Routing it to done would skip a cascade that may be owed, and
# the no-anchor edge is silent, so nobody would ever hear about it.
# ---------------------------------------------------------------------------
D4=$(mktemp -d); TMPS+=("$D4")
OUT4=$(tick_from_start "$D4" "cascade-chain-undecided-$$" 2 "$CASCADE_RUN" || true)

if echo "$OUT4" | grep -q '"state":"done_blocked"'; then
    pass "could-not-decide stops at done_blocked (uncertainty is not treated as absence)"
elif echo "$OUT4" | grep -qE '"state":"done"|"action":"done"'; then
    fail "could-not-decide routed to done — an owed cascade would be skipped in silence"
else
    fail "undecided case: unexpected tick result: $(echo "$OUT4" | head -c 300)"
fi

# ---------------------------------------------------------------------------
# Case 5 — the SHIPPED gate command, with no plugin root to resolve.
#
# Every case above stubs the gate's exit code. This one runs the real command
# text with PLUGIN_ROOT unset, which is what an init in a shell with no
# CLAUDE_PLUGIN_ROOT produces: koto accepts an empty value for a required
# variable, so the empty root reaches the gate rather than being caught at init
# (koto#245). Without the `test -x` guard the finder is simply not found, the
# gate exits 127, koto discards its output, and the run holds with no
# diagnostic. The guard is what turns that into a loud stop.
# ---------------------------------------------------------------------------
D5=$(mktemp -d); TMPS+=("$D5")
OUT5=$(tick_from_start "$D5" "cascade-chain-noroot-$$" real "$CASCADE_RUN" || true)

if echo "$OUT5" | grep -q '"state":"done_blocked"'; then
    pass "shipped gate with an unresolved plugin root fails closed to done_blocked"
elif echo "$OUT5" | grep -qE '"state":"done"|"action":"done"'; then
    fail "shipped gate with an unresolved plugin root routed to done — a cascade would be skipped because a path was wrong"
elif echo "$OUT5" | grep -q '"state":"cascade_entry"'; then
    fail "shipped gate with an unresolved plugin root held at cascade_entry with no route — the fail-closed guard is gone"
else
    fail "no-root case: unexpected tick result: $(echo "$OUT5" | head -c 300)"
fi

echo
echo "passed: $PASS_COUNT  failed: $FAIL_COUNT"
[[ "$FAIL_COUNT" -eq 0 ]]
