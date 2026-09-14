#!/usr/bin/env bash
# ci-monitor-role_test.sh — a child must not reach the cascade, and a root must.
#
# The cascade finalizes a chain once per plan. A child materialized by /execute
# lands its own pull request and must stop at done: a child that cascaded would
# delete the PLAN its siblings are still working from. That is the branch this
# file drives, against the SHIPPED ci_monitor block rather than a hand-written
# copy of it, so an edit to the template's routing reaches these cases.
#
# WHAT THIS FILE DOES NOT DO, stated so nobody reads more into a green run than
# is there. It does not construct a real coordinated child and walk it from entry
# to ci_monitor. That path runs through roughly a dozen states, each demanding
# evidence, and the harness would be a reimplementation of /execute. What stands
# in its place is narrower and honest: the routing table is exercised directly
# with each role, and the claim that a coordinated child reaches ci_monitor at
# all rests on /execute's own contract (a coordinated child works on its own
# branch and lands its own per-repo pull request), not on anything measured here.
# A single-pr child would prove nothing either way — it submits pr_status: shared
# and routes to done long before ci_monitor, for reasons that have nothing to do
# with session_role.
#
# The discriminator itself — that `root` and `child` are read from koto's
# parent_workflow — is covered by terminal-retention_test.sh, not here.
#
# Usage: ci-monitor-role_test.sh
# Exit codes: 0 all pass, 1 any failed, 0 with a skip notice when koto is absent.

set -uo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
SKILL_DIR=$(cd "$SCRIPT_DIR/.." && pwd)
TEMPLATE="$SKILL_DIR/koto-templates/work-on.md"

PASS_COUNT=0
FAIL_COUNT=0
GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[0;33m'; NC='\033[0m'
pass() { echo -e "${GREEN}PASS${NC}: $*"; PASS_COUNT=$((PASS_COUNT+1)); }
fail() { echo -e "${RED}FAIL${NC}: $*"; FAIL_COUNT=$((FAIL_COUNT+1)); }
skip() { echo -e "${YELLOW}SKIP${NC}: $*"; }

TMPS=()
SESSIONS=()
# Ends with an explicit success. The last command in this trap is a test that is
# FALSE when the arrays are empty, which under `set -e` would replace this
# script's own exit status -- a clean `exit 0` on the skip path coming back as 1,
# with every line printed saying it had passed.
#
# It never did so HERE. This file runs `set -uo pipefail` with no -e, and
# measured against the pre-fix version with koto absent it exits 0. The shape was
# present and could not fire; adding -e is what would make it fire, which is the
# useful thing for the next author to know. cascade-chaining_test.sh, which sets
# -euo pipefail, is where it actually bit.
#
# The trigger is `set -e` and not any shell version: bash 5.2 and 3.2 behave
# identically.
cleanup() {
    for w in "${SESSIONS[@]:-}"; do [[ -n "$w" ]] && koto cancel "$w" >/dev/null 2>&1; done
    for d in "${TMPS[@]:-}"; do [[ -n "$d" ]] && rm -rf "$d"; done
    return 0
}
trap cleanup EXIT

if ! command -v koto >/dev/null 2>&1; then
    skip "koto not on PATH; the role branch cannot be driven without the engine"
    exit 0
fi
[[ -f "$TEMPLATE" ]] || { echo "template not found: $TEMPLATE"; exit 2; }

# Pull the shipped ci_monitor block out of the template's frontmatter.
extract_state() {
    local name="$1"
    awk -v want="  $name:" '
        $0 == want { found=1; print; next }
        found && /^  [a-zA-Z_][a-zA-Z0-9_]*:$/ { exit }
        found { print }
    ' "$TEMPLATE"
}

CI_MONITOR=$(extract_state ci_monitor)
[[ -n "$CI_MONITOR" ]] || { echo "ci_monitor not found in $TEMPLATE"; exit 2; }

# build_fixture <dir> <ci_monitor block>
# `start` stands in for pr_creation: it routes into ci_monitor with no evidence
# of its own. cascade_entry and the terminals are stubs — this file is about
# which one the run lands on, not what happens after.
# stub_gates <block> <ci_passing exit> <merge_state_clean exit>
# Replaces each gate's command with a fixed exit, keyed on the gate name above
# it. A blanket substitution would give both gates the same exit and make the
# DIRTY case untestable, since that case is exactly the two disagreeing: checks
# that look green because a conflicted pull request never ran any.
stub_gates() {
    printf '%s\n' "$1" | awk -v ci="$2" -v merge="$3" '
        /^      [a-z_]+:$/ { gate = $1; sub(/:$/, "", gate) }
        /^        command:/ {
            if (gate == "ci_passing") { print "        command: \"exit " ci "\""; next }
            if (gate == "merge_state_clean") { print "        command: \"exit " merge "\""; next }
        }
        { print }
    '
}

build_fixture() {
    local dir="$1" block="$2"
    cat > "$dir/fixture.md" <<FIXTURE
---
name: ci-monitor-role-fixture
version: "1.0"
description: Fixture exercising ci_monitor's root-versus-child branch.
initial_state: start
variables:
  ISSUE_NUMBER:
    description: Issue under test
    required: false
states:
  start:
    transitions:
      - target: ci_monitor
$(stub_gates "$block" "${3:-0}" "${4:-0}")
  cascade_entry:
    terminal: true
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
Stand-in for pr_creation.

## ci_monitor
Submit ci_outcome and session_role.

## cascade_entry
Stub terminal standing in for the cascade path.

## done
Done.

## done_blocked
Blocked.
FIXTURE
}

# land <dir> <session> <block> <evidence-json> — drive to ci_monitor, submit, print the state.
land() {
    local dir="$1" session="$2" block="$3" data="$4"
    local ci_exit="${5:-0}" merge_exit="${6:-0}"
    build_fixture "$dir" "$block" "$ci_exit" "$merge_exit"
    koto init "$session" --template "$dir/fixture.md" >/dev/null 2>&1 || return 1
    SESSIONS+=("$session")
    koto next "$session" >/dev/null 2>&1 || true
    koto next "$session" --with-data "$data" 2>/dev/null
}

# ---------------------------------------------------------------------------
# Case 1 — a root with green CI reaches the cascade.
# ---------------------------------------------------------------------------
D1=$(mktemp -d); TMPS+=("$D1")
OUT1=$(land "$D1" "ci-role-root-$$" "$CI_MONITOR" '{"ci_outcome":"passing","session_role":"root"}' || true)
if echo "$OUT1" | grep -q '"state":"cascade_entry"'; then
    pass "a root with passing CI routes to cascade_entry"
else
    fail "root case: expected cascade_entry, got: $(echo "$OUT1" | head -c 200)"
fi

# ---------------------------------------------------------------------------
# Case 2 — THE POINT OF THIS FILE. A child with the same green CI stops at done
# and never reaches the cascade.
# ---------------------------------------------------------------------------
D2=$(mktemp -d); TMPS+=("$D2")
OUT2=$(land "$D2" "ci-role-child-$$" "$CI_MONITOR" '{"ci_outcome":"passing","session_role":"child"}' || true)
if echo "$OUT2" | grep -q '"state":"cascade_entry"'; then
    fail "a child reached cascade_entry — it would cascade a PLAN its siblings are still using"
elif echo "$OUT2" | grep -qE '"state":"done"|"action":"done"'; then
    pass "a child with passing CI stops at done, never reaching cascade_entry"
else
    fail "child case: expected done, got: $(echo "$OUT2" | head -c 200)"
fi

# ---------------------------------------------------------------------------
# Case 3 — the control: ci_monitor as it stood BEFORE this branch existed. A
# child submitting the same evidence reaches the cascade, which is the defect
# the branch removes, and which is what makes Case 2 worth running.
#
# A literal rather than a mutation of the shipped block, because the obvious
# mutation does not compile. Stripping `session_role: root` from the cascade edge
# leaves it as {passing, gate 0} beside a child edge of {passing, gate 0, child},
# and koto refuses that template: the first could match anything the second
# matches, so it cannot prove them exclusive. The engine will not let the
# half-changed shape exist, so the control has to be the whole earlier shape.
# Being a fixed historical artifact, it cannot drift.
# ---------------------------------------------------------------------------
LEGACY_CI_MONITOR='  ci_monitor:
    gates:
      ci_passing:
        type: command
        command: "exit 0"
    accepts:
      ci_outcome:
        type: enum
        values: [passing, failing_fixed, failing_unresolvable]
        required: true
      rationale:
        type: string
        description: What was fixed or why CI failures are unresolvable
    transitions:
      - target: cascade_entry
        when:
          ci_outcome: passing
          gates.ci_passing.exit_code: 0
      - target: done
        when:
          ci_outcome: failing_fixed
      - target: done_blocked
        when:
          ci_outcome: failing_unresolvable
      - target: done'
D3=$(mktemp -d); TMPS+=("$D3")
OUT3=$(land "$D3" "ci-role-legacy-$$" "$LEGACY_CI_MONITOR" '{"ci_outcome":"passing"}' || true)
if echo "$OUT3" | grep -q '"state":"cascade_entry"'; then
    pass "the pre-branch state sends a child to cascade_entry — the branch is load-bearing"
else
    fail "control case: the pre-branch state did not reach cascade_entry, so Case 2 proves nothing: $(echo "$OUT3" | head -c 200)"
fi

# ---------------------------------------------------------------------------
# Case 4 — a failing-then-fixed run ends at done whatever its role. The role
# branch must not have captured the other outcomes on its way past.
# ---------------------------------------------------------------------------
D4=$(mktemp -d); TMPS+=("$D4")
OUT4=$(land "$D4" "ci-role-fixed-$$" "$CI_MONITOR" '{"ci_outcome":"failing_fixed","session_role":"root"}' || true)
if echo "$OUT4" | grep -qE '"state":"done"|"action":"done"'; then
    pass "failing_fixed still routes to done for a root"
else
    fail "failing_fixed case: expected done, got: $(echo "$OUT4" | head -c 200)"
fi

# ---------------------------------------------------------------------------
# Case 5 — an unresolvable failure still blocks, and carries its reason.
# ---------------------------------------------------------------------------
D5=$(mktemp -d); TMPS+=("$D5")
OUT5=$(land "$D5" "ci-role-unresolvable-$$" "$CI_MONITOR" '{"ci_outcome":"failing_unresolvable","session_role":"child","rationale":"upstream outage"}' || true)
if echo "$OUT5" | grep -q '"state":"done_blocked"'; then
    pass "failing_unresolvable still routes to done_blocked for a child"
else
    fail "unresolvable case: expected done_blocked, got: $(echo "$OUT5" | head -c 200)"
fi

# ---------------------------------------------------------------------------
# Case 6 — session_role is required. A submission without it must not advance,
# because the state's last edge is unconditional: an unrecognised submission
# would otherwise take the silent route to done and skip an owed cascade.
# ---------------------------------------------------------------------------
D6=$(mktemp -d); TMPS+=("$D6")
OUT6=$(land "$D6" "ci-role-missing-$$" "$CI_MONITOR" '{"ci_outcome":"passing"}' || true)
if echo "$OUT6" | grep -qE '"state":"done"|"state":"cascade_entry"'; then
    fail "a submission with no session_role advanced — the fallback edge swallowed it"
else
    pass "a submission with no session_role does not advance"
fi

# ---------------------------------------------------------------------------
# Case 7 — a DIRTY pull request blocks, even though CI looks green.
#
# This is the pairing that makes the second gate necessary rather than
# decorative. A conflicted pull request gets no new check-runs, and the CI gate
# asks whether nothing is failing — which zero check-runs satisfies. So the CI
# gate passes on a conflicted PR exactly as it does on a genuinely green one,
# and the merge-state gate is the only thing that can tell them apart.
# ---------------------------------------------------------------------------
D7=$(mktemp -d); TMPS+=("$D7")
OUT7=$(land "$D7" "ci-role-dirty-$$" "$CI_MONITOR" '{"ci_outcome":"passing","session_role":"root"}' 0 1 || true)
if echo "$OUT7" | grep -q '"state":"done_blocked"'; then
    pass "a DIRTY pull request blocks even with the CI gate passing"
elif echo "$OUT7" | grep -q '"state":"cascade_entry"'; then
    fail "a DIRTY pull request reached the cascade — it would finalize a chain on a conflicted PR"
else
    fail "dirty case: expected done_blocked, got: $(echo "$OUT7" | head -c 200)"
fi

# Case 7b — and a clean one still passes, so Case 7 is not blocking everything.
D7B=$(mktemp -d); TMPS+=("$D7B")
OUT7B=$(land "$D7B" "ci-role-clean-$$" "$CI_MONITOR" '{"ci_outcome":"passing","session_role":"root"}' 0 0 || true)
if echo "$OUT7B" | grep -q '"state":"cascade_entry"'; then
    pass "a clean merge state still reaches the cascade"
else
    fail "clean case: expected cascade_entry, got: $(echo "$OUT7B" | head -c 200)"
fi

# ---------------------------------------------------------------------------
# Case 8 — R13, as a count. A plan run is one root and its children; the chain is
# finalized ONCE for the plan, not once per issue in it. So drive a whole plan's
# worth of runs and count how many reach the cascade. The assertion is `-eq 1`
# deliberately: "at least one cascaded" passes at any number, including the
# once-per-issue behaviour this exists to rule out, and a race to delete the same
# PLAN four times would satisfy it.
#
# Scope, stated so the number is not read as more than it is: this counts
# ROUTING decisions across four runs of the shipped ci_monitor block, not four
# real sessions walking the whole workflow.
# ---------------------------------------------------------------------------
CASCADE_COUNT=0
PLAN_RUN_ROLES="root child child child"
RUN_N=0
for role in $PLAN_RUN_ROLES; do
    RUN_N=$((RUN_N + 1))
    D=$(mktemp -d); TMPS+=("$D")
    OUT=$(land "$D" "ci-role-plan-${RUN_N}-$$" "$CI_MONITOR" "{\"ci_outcome\":\"passing\",\"session_role\":\"$role\"}" || true)
    if echo "$OUT" | grep -q '"state":"cascade_entry"'; then
        CASCADE_COUNT=$((CASCADE_COUNT + 1))
    fi
done

if [[ "$CASCADE_COUNT" -eq 1 ]]; then
    pass "a plan run of one root and three children reaches the cascade exactly once (count: $CASCADE_COUNT)"
else
    fail "R13: expected exactly 1 cascade across one root and three children, counted $CASCADE_COUNT"
fi

echo
echo "ci-monitor-role_test.sh: $PASS_COUNT passed, $FAIL_COUNT failed"
[[ "$FAIL_COUNT" -eq 0 ]]
