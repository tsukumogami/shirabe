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
# with each answer of the is_root gate (stubbed to a fixed exit, beside the two
# CI gates), and the claim that a coordinated child reaches ci_monitor at
# all rests on /execute's own contract (a coordinated child works on its own
# branch and lands its own per-repo pull request), not on anything measured here.
# A single-pr child would prove nothing either way — it submits pr_status: shared
# and routes to done long before ci_monitor, for reasons that have nothing to do
# with the run's role.
#
# The discriminator itself — scripts/session-role.sh, which reads `root` and
# `child` from koto's parent_workflow, and the is_root gate command that tests
# its answer — is covered at the end of this file. Its
# cases describe BEHAVIOUR ("a child classifies as child"), never the mechanism
# session-role.sh uses to decide, so they survive a change in how koto records
# parentage.
#
# Usage: ci-monitor-role_test.sh
# Exit codes: 0 all pass, 1 any failed, 0 with a skip notice when koto is absent.

set -uo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
SKILL_DIR=$(cd "$SCRIPT_DIR/.." && pwd)
TEMPLATE="$SKILL_DIR/koto-templates/work-on.md"
ROLE_SH="$SCRIPT_DIR/session-role.sh"

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

# Engine-free, so it runs on the bash 3.2 floor too: the discriminator refuses a
# call it cannot answer, printing nothing a caller could mistake for a role.
ROLE_OUT=$(bash "$ROLE_SH" 2>/dev/null)
ROLE_RC=$?
if [[ "$ROLE_RC" -eq 2 && -z "$ROLE_OUT" ]]; then
    pass "the discriminator rejects a missing session name with exit 2 and prints nothing"
else
    fail "the discriminator did not exit 2 silently on a missing session name (rc=$ROLE_RC, out=[$ROLE_OUT])"
fi

if ! command -v koto >/dev/null 2>&1; then
    skip "koto not on PATH; the role branch cannot be driven without the engine"
    [[ "$FAIL_COUNT" -eq 0 ]]
    exit $?
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
# stub_gates <block> <ci_passing exit> <merge_state_clean exit> <is_root exit>
# Replaces each gate's command with a fixed exit, keyed on the gate name above
# it. A blanket substitution would give every gate the same exit and make the
# DIRTY and child cases untestable, since those are exactly the gates
# disagreeing: checks that look green because a conflicted pull request never
# ran any, and green CI on a run that is not the root.
stub_gates() {
    printf '%s\n' "$1" | awk -v ci="$2" -v merge="$3" -v root="$4" '
        /^      [a-z_]+:$/ { gate = $1; sub(/:$/, "", gate) }
        /^        command:/ {
            if (gate == "ci_passing") { print "        command: \"exit " ci "\""; next }
            if (gate == "merge_state_clean") { print "        command: \"exit " merge "\""; next }
            if (gate == "is_root") { print "        command: \"exit " root "\""; next }
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
  PLUGIN_ROOT:
    description: Plugin root the is_root gate reaches session-role.sh through
    required: false
states:
  start:
    transitions:
      - target: ci_monitor
$(stub_gates "$block" "${3:-0}" "${4:-0}" "${5:-0}")
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
Green CI routes on the gates; submit ci_outcome only while CI fails.

## cascade_entry
Stub terminal standing in for the cascade path.

## done
Done.

## done_blocked
Blocked.
FIXTURE
}

# land <dir> <session> <block> <evidence-json-or-empty> [ci] [merge] [is_root]
# Drives to ci_monitor and, with evidence, submits it; prints the response.
land() {
    local dir="$1" session="$2" block="$3" data="$4"
    local ci_exit="${5:-0}" merge_exit="${6:-0}" root_exit="${7:-0}"
    build_fixture "$dir" "$block" "$ci_exit" "$merge_exit" "$root_exit"
    koto init "$session" --template "$dir/fixture.md" >/dev/null 2>&1 || return 1
    SESSIONS+=("$session")
    if [[ -z "$data" ]]; then
        koto next "$session" 2>/dev/null
    else
        koto next "$session" >/dev/null 2>&1 || true
        koto next "$session" --with-data "$data" 2>/dev/null
    fi
}

# ---------------------------------------------------------------------------
# Case 1 — a root with green CI reaches the cascade, with no evidence.
# ---------------------------------------------------------------------------
D1=$(mktemp -d); TMPS+=("$D1")
OUT1=$(land "$D1" "ci-role-root-$$" "$CI_MONITOR" '' 0 0 0 || true)
if echo "$OUT1" | grep -q '"state":"cascade_entry"'; then
    pass "a root with passing CI routes to cascade_entry with no evidence"
else
    fail "root case: expected cascade_entry, got: $(echo "$OUT1" | head -c 200)"
fi

# ---------------------------------------------------------------------------
# Case 2 — THE POINT OF THIS FILE. A child with the same green CI stops at done
# and never reaches the cascade.
# ---------------------------------------------------------------------------
D2=$(mktemp -d); TMPS+=("$D2")
OUT2=$(land "$D2" "ci-role-child-$$" "$CI_MONITOR" '' 0 0 1 || true)
if echo "$OUT2" | grep -q '"state":"cascade_entry"'; then
    fail "a child reached cascade_entry — it would cascade a PLAN its siblings are still using"
elif echo "$OUT2" | grep -qE '"state":"done"|"action":"done"'; then
    pass "a child with passing CI stops at done, never reaching cascade_entry"
else
    fail "child case: expected done, got: $(echo "$OUT2" | head -c 200)"
fi

# ---------------------------------------------------------------------------
# Case 3 — the control: ci_monitor as it stood BEFORE the root-or-child split
# existed. A child submitting the same evidence reaches the cascade, which is
# the defect the split removes, and which is what makes Case 2 worth running.
#
# A literal rather than a mutation of the shipped block: a fixed historical
# artifact cannot drift.
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
    pass "the pre-split state sends a child to cascade_entry — the split is load-bearing"
else
    fail "control case: the pre-split state did not reach cascade_entry, so Case 2 proves nothing: $(echo "$OUT3" | head -c 200)"
fi

# ---------------------------------------------------------------------------
# Case 4 — a fix goes back to CI monitoring whatever its role. A pushed fix has
# not been checked yet, so failing_fixed must not end the run: it returns to
# ci_monitor, where the gates poll CI on the new push.
# ---------------------------------------------------------------------------
D4=$(mktemp -d); TMPS+=("$D4")
OUT4=$(land "$D4" "ci-role-fixed-$$" "$CI_MONITOR" '{"ci_outcome":"failing_fixed"}' 1 0 0 || true)
if echo "$OUT4" | grep -qE '"state":"done"|"action":"done"'; then
    fail "failing_fixed reached done — a fix nobody re-checked ended the run"
elif echo "$OUT4" | grep -q '"advanced":true' && echo "$OUT4" | grep -q '"state":"ci_monitor"'; then
    pass "failing_fixed on red CI returns to ci_monitor"
else
    fail "failing_fixed case: expected ci_monitor, got: $(echo "$OUT4" | head -c 200)"
fi

# ---------------------------------------------------------------------------
# Case 4b — red or unfinished CI never reaches done. With no evidence koto
# holds the state and names the failing gate, so the agent waits for the
# checks and ticks again; reporting success on red CI is the defect.
# ---------------------------------------------------------------------------
D4B=$(mktemp -d); TMPS+=("$D4B")
OUT4B=$(land "$D4B" "ci-role-red-$$" "$CI_MONITOR" '' 1 0 1 || true)
if echo "$OUT4B" | grep -qE '"state":"done"|"action":"done"'; then
    fail "red CI reached done — the run reported success on failing checks"
elif echo "$OUT4B" | grep -q '"state":"ci_monitor"' && echo "$OUT4B" | grep -q '"name":"ci_passing"'; then
    pass "red CI holds ci_monitor, naming the ci_passing gate"
else
    fail "red-CI case: expected a hold on ci_passing, got: $(echo "$OUT4B" | head -c 200)"
fi

# ---------------------------------------------------------------------------
# Case 4c — no edge out of ci_monitor is unconditional, and every one names
# ci_passing: green CI is the only way to done or the cascade, and the two
# evidence values apply only while it fails. Read from the shipped block.
# ---------------------------------------------------------------------------
EDGES=$(printf '%s\n' "$CI_MONITOR" | awk '/^      - target:/ { n++ } END { print n + 0 }')
NAMED=$(printf '%s\n' "$CI_MONITOR" | grep -c '^          gates\.ci_passing\.exit_code:')
if [[ "$EDGES" -gt 0 && "$EDGES" -eq "$NAMED" ]]; then
    pass "every ci_monitor edge names ci_passing ($EDGES of $EDGES)"
else
    fail "ci_monitor has $EDGES edges and $NAMED name ci_passing"
fi

# ---------------------------------------------------------------------------
# Case 5 — an unresolvable failure still blocks, and carries its reason.
# ---------------------------------------------------------------------------
D5=$(mktemp -d); TMPS+=("$D5")
OUT5=$(land "$D5" "ci-role-unresolvable-$$" "$CI_MONITOR" '{"ci_outcome":"failing_unresolvable","rationale":"upstream outage"}' 1 0 1 || true)
if echo "$OUT5" | grep -q '"state":"done_blocked"'; then
    pass "failing_unresolvable on red CI routes to done_blocked"
else
    fail "unresolvable case: expected done_blocked, got: $(echo "$OUT5" | head -c 200)"
fi

# ---------------------------------------------------------------------------
# Case 6 — the root-or-child answer is the gate's, never the agent's: the
# state accepts no field for it.
# ---------------------------------------------------------------------------
if printf '%s\n' "$CI_MONITOR" | grep -q 'session_role'; then
    fail "ci_monitor still accepts a role field; the is_root gate is the only source"
else
    pass "ci_monitor accepts no role field; is_root decides"
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
OUT7=$(land "$D7" "ci-role-dirty-$$" "$CI_MONITOR" '' 0 1 0 || true)
if echo "$OUT7" | grep -q '"state":"done_blocked"'; then
    pass "a DIRTY pull request blocks even with the CI gate passing"
elif echo "$OUT7" | grep -q '"state":"cascade_entry"'; then
    fail "a DIRTY pull request reached the cascade — it would finalize a chain on a conflicted PR"
else
    fail "dirty case: expected done_blocked, got: $(echo "$OUT7" | head -c 200)"
fi

# Case 7b — and a clean one still passes, so Case 7 is not blocking everything.
D7B=$(mktemp -d); TMPS+=("$D7B")
OUT7B=$(land "$D7B" "ci-role-clean-$$" "$CI_MONITOR" '' 0 0 0 || true)
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
PLAN_RUN_ROLES="0 1 1 1"
RUN_N=0
for root_exit in $PLAN_RUN_ROLES; do
    RUN_N=$((RUN_N + 1))
    D=$(mktemp -d); TMPS+=("$D")
    OUT=$(land "$D" "ci-role-plan-${RUN_N}-$$" "$CI_MONITOR" '' 0 0 "$root_exit" || true)
    if echo "$OUT" | grep -q '"state":"cascade_entry"'; then
        CASCADE_COUNT=$((CASCADE_COUNT + 1))
    fi
done

if [[ "$CASCADE_COUNT" -eq 1 ]]; then
    pass "a plan run of one root and three children reaches the cascade exactly once (count: $CASCADE_COUNT)"
else
    fail "R13: expected exactly 1 cascade across one root and three children, counted $CASCADE_COUNT"
fi

# ---------------------------------------------------------------------------
# The discriminator — the is_root answer every case above stubs.
#
# Sessions live in their own HOME, so nothing here reaches the developer's
# ~/.koto. An unresolvable session must answer `child`: a child that wrongly
# stops at done leaves the chain for the run that owns it, while a child that
# wrongly cascades deletes a PLAN its siblings are still working from.
# ---------------------------------------------------------------------------
if command -v jq >/dev/null 2>&1; then
    RD=$(mktemp -d); TMPS+=("$RD")
    mkdir -p "$RD/home"
    rk() { (cd "$RD" && HOME="$RD/home" koto "$@"); }
    role_of() { (cd "$RD" && HOME="$RD/home" bash "$ROLE_SH" "$1" 2>/dev/null); }
    cat > "$RD/child.md" <<'ROLE_CHILD'
---
name: role-probe-child
version: "1.0"
description: Minimal child.
initial_state: work
states:
  work:
    accepts:
      status:
        type: enum
        values: [ok]
        required: true
    transitions:
      - target: done
        when:
          status: ok
  done:
    terminal: true
---

## work

Submit status.

## done

Terminal.
ROLE_CHILD
    cat > "$RD/parent.md" <<'ROLE_PARENT'
---
name: role-probe-parent
version: "1.0"
description: Minimal parent that materializes one child.
initial_state: spawn
states:
  spawn:
    gates:
      batch_done:
        type: children-complete
    accepts:
      tasks:
        type: tasks
        required: true
    materialize_children:
      from_field: tasks
      failure_policy: skip_dependents
      default_template: ./child.md
    transitions:
      - target: finished
  finished:
    terminal: true
---

## spawn

Submit tasks.

## finished

Terminal.
ROLE_PARENT
    rk init role_root --template "$RD/child.md" >/dev/null 2>&1
    rk init role_parent --template "$RD/parent.md" >/dev/null 2>&1
    rk next role_parent --with-data '{"tasks":[{"name":"leaf","description":"leaf task"}]}' >/dev/null 2>&1
    if ! rk status role_root >/dev/null 2>&1 || ! rk status role_parent.leaf >/dev/null 2>&1; then
        fail "the discriminator fixture sessions were not created -- the role cases below cannot run"
    else
        got=$(role_of role_root)
        [[ "$got" == root ]] && pass "a directly-initialized session classifies as root" \
            || fail "a directly-initialized session classified as '$got', expected root"
        got=$(role_of role_parent.leaf)
        [[ "$got" == child ]] && pass "a materialized child classifies as child" \
            || fail "a materialized child classified as '$got', expected child"
        got=$(role_of role_parent)
        [[ "$got" == root ]] && pass "the parent of a materialized child still classifies as root" \
            || fail "the parent classified as '$got', expected root"
        # The shipped is_root gate's own command, rendered as koto would: it
        # passes for the root and fails for the child.
        IS_ROOT_CMD=$(printf '%s\n' "$CI_MONITOR" | awk '
            /^      is_root:$/ { f = 1; next }
            f && /^        command:/ { sub(/^        command: /, ""); print substr($0, 2, length($0) - 2); exit }')
        PLUGIN_ROOT_DIR=$(cd "$SKILL_DIR/../.." && pwd)
        for pair in role_root:0 role_parent.leaf:1; do
            cmd=${IS_ROOT_CMD//\{\{PLUGIN_ROOT\}\}/$PLUGIN_ROOT_DIR}
            cmd=${cmd//\{\{SESSION_NAME\}\}/${pair%%:*}}
            (cd "$RD" && HOME="$RD/home" sh -c "$cmd" >/dev/null 2>&1)
            rc=$?
            [[ "$rc" == "${pair#*:}" ]] && pass "the shipped is_root command exits $rc for ${pair%%:*}" \
                || fail "the shipped is_root command exited $rc for ${pair%%:*}, expected ${pair#*:}"
        done
    fi
    got=$(role_of no-such-session-anywhere)
    [[ "$got" == child ]] && pass "an unresolvable session classifies as child, which skips the cascade" \
        || fail "an unresolvable session classified as '$got', expected child"
else
    skip "jq not on PATH; the discriminator cases need it"
fi

echo
echo "ci-monitor-role_test.sh: $PASS_COUNT passed, $FAIL_COUNT failed"
[[ "$FAIL_COUNT" -eq 0 ]]
