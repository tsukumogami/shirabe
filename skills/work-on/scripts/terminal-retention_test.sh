#!/usr/bin/env bash
# terminal-retention_test.sh -- every tick keeps the record, root or child
# Part of the work-on skill
#
# koto disposes of a session that reaches a success terminal, and the disposal
# takes the session's `ctx/` with it. `koto next --no-cleanup` keeps it, which is
# how a /work-on run keeps its record past its terminal (#360). From koto 0.14.0,
# shirabe's koto minimum, a session that reaches a failure terminal such as
# `done_blocked` is kept with or without the flag, and on a child the flag only
# keeps the session: the child's result still reaches its parent. So the rule
# is one line with no root/child split -- every `koto next` carries the flag --
# and this harness pins both the rule's text and the koto behaviour it rests on.
#
# Groups, in execution order -- deliberately not numbered, because a numbered
# map goes stale the first time a case is inserted and then misdirects the
# reader it was written for:
#
#   engine-free, so they also run on the bash 3.2 floor where koto is absent:
#     SKILL.md states the rule once, over every tick, naming no state and no role
#     every `koto next` command line the skill shows carries the flag
#     the template frontmatter records where the rule lives
#
#   engine-backed:
#     a root run's record survives done_blocked with and without the flag, and
#       a success terminal keeps it only with the flag (the control)
#     a blocked edge's context_assignments write failure_reason
#     the flag on an earlier tick retains nothing
#     retention does not become a false "already done" on the next run
#     a flagged child is kept and still delivers its result, to either shape
#       of parent, with an unflagged child as the control
#     an unflagged child that reaches a failure terminal is kept, readable with
#       koto status and koto context get, and its parent's retry_failed acts on it
#
# The root-run cases drive the SHIPPED work-on.md to its real `done_blocked`
# terminal rather than a stand-in, so a template edit that moves that terminal
# fails here. The child cases use a minimal parent/child pair, because what they
# assert is koto's convergence behaviour rather than anything about work-on.md's
# own states.
#
# Usage: terminal-retention_test.sh
#
# Exit codes:
#   0 -- all cases pass, or koto is absent and the run skipped
#   1 -- one or more cases failed
#
# A missing koto exits 0 with a loud SKIP rather than failing, matching
# retry-clearing_test.sh. The suite runs on two legs and only one has koto: the
# Linux leg of check-work-on-scripts.yml installs it through the project tool
# manifest, so the assertions genuinely run there; the macOS leg is the bash 3.2
# floor check and exists to test portability of the shell itself. The Linux
# leg's explicit install step is what keeps a silent skip from hiding a koto
# that vanished from CI -- the install fails first -- and its
# assert-koto-floor.sh step fails a koto below the minimum these cases assume.
#
# bash 3.2 floor: no associative arrays, no namerefs, no mapfile.

set -uo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
SKILL_DIR=$(cd "$SCRIPT_DIR/.." && pwd)
TEMPLATE="$SKILL_DIR/koto-templates/work-on.md"
PHASES="$SKILL_DIR/references/phases"
SKILL_MD="$SKILL_DIR/SKILL.md"

PASS_COUNT=0
FAIL_COUNT=0

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

pass() { echo -e "${GREEN}PASS${NC}: $*"; PASS_COUNT=$((PASS_COUNT + 1)); }
fail() { echo -e "${RED}FAIL${NC}: $*"; FAIL_COUNT=$((FAIL_COUNT + 1)); }

[ -f "$TEMPLATE" ] || { echo "FAIL: template not found at $TEMPLATE" >&2; exit 1; }

# --- SKILL.md states the rule ---------------------------------------------------
#
# These need no engine, so they run first and the floor leg gets real coverage.
#
# The rule's value is that it covers ticks nobody had thought of when it was
# written: a state added later reaches a terminal through a tick the author never
# saw. An enumeration cannot do that, and the difference is invisible to a grep
# for the flag.
#
# Measured, before this case existed: narrowing the rule to "the koto next calls
# that reach context_injection, analysis and implementation carry --no-cleanup"
# -- an enumeration omitting the cascade terminals entirely -- left this suite
# 20/20 green. Coverage of any tick not named in that list was an assumption.
#
# So the rule has to quantify over every tick and name no state, because the
# moment it names one it has become a list. And it names no role: a rule gated
# on root versus child is the pre-0.14 exception, which leaves a child's
# success terminal bare.
RETENTION_RULE=$(awk '
    /^\*\*Retention:/ { inrule = 1 }
    inrule { print }
    inrule && /^$/ { exit }
' "$SKILL_MD")

if [ -z "$RETENTION_RULE" ]; then
    fail "the retention rule paragraph could not be found in SKILL.md -- it was reworded, and this case no longer reads it"
elif ! printf '%s' "$RETENTION_RULE" | grep -q -- '--no-cleanup'; then
    fail "the retention rule paragraph no longer names --no-cleanup"
elif ! printf '%s' "$RETENTION_RULE" | grep -qE 'every (`?koto next`?|tick)'; then
    fail "the retention rule no longer quantifies over every tick, so a tick added later is not covered by it"
else
    # State names come from the template rather than a hardcoded list, so a state
    # added later is checked without anyone remembering to add it here.
    NAMED=""
    for st in $(awk '/^states:/ { s=1; next } s && /^  [a-z_]+:$/ { n=$1; sub(/:$/, "", n); print n }' "$TEMPLATE"); do
        # Bounded on both sides, so "the entry-evidence tick" is not read as
        # naming the `entry` state. A bare substring match reports that, and a
        # check that cries wolf is a check people switch off.
        if printf '%s' "$RETENTION_RULE" | grep -qE "(^|[^-_[:alnum:]])${st}([^-_[:alnum:]]|$)"; then
            NAMED="$NAMED $st"
        fi
    done
    if [ -n "$NAMED" ]; then
        fail "the retention rule names states ($NAMED) -- it has become an enumeration, and ticks outside it are uncovered"
    else
        pass "the retention rule quantifies over every tick and names no state, so a tick added later is covered by it"
    fi
fi

# No role gate anywhere in the skill's ticks: the ROLE variable the pre-0.14
# rule resolved before the first tick is gone, and nothing tells a run to leave
# the flag off because it is a child.
if grep -n -E '\bROLE\b' "$SKILL_MD" >/dev/null 2>&1; then
    fail "SKILL.md still resolves or reads ROLE -- the retention rule must not depend on a session's role:
$(grep -n -E '\bROLE\b' "$SKILL_MD")"
else
    pass "SKILL.md resolves no ROLE, so no tick's flag depends on whether the run is a child"
fi

# --- every koto next command line carries the flag ------------------------------
#
# A child run reads work-on.md's directives and the phase files they send it
# to, and copies their command lines. Each one that submits a tick has to carry
# the flag, or the rule in SKILL.md is contradicted where the agent actually
# reads. Lines are matched as commands: `koto next` at the start of a line, or
# inside backticks.
bare_ticks() {
    grep -n -E '(^|`)koto next (<WF>|\{\{SESSION_NAME\}\}|<[A-Za-z_]+>)' "$@" 2>/dev/null \
        | grep -v -- '--no-cleanup'
}
BARE=$(bare_ticks "$SKILL_MD" "$TEMPLATE" "$PHASES"/*.md)
if [ -n "$BARE" ]; then
    fail "a koto next command line the skill shows is missing --no-cleanup:
$BARE"
else
    pass "every koto next command line in SKILL.md, work-on.md and its phase files carries --no-cleanup"
fi

# The check above is only as good as its matcher, so it is shown to fire.
printf 'Run:\n\nkoto next <WF> --with-data %s\n' "'{\"x\": 1}'" >"${TMPDIR:-/tmp}/tr-bare.$$.md"
if [ -n "$(bare_ticks "${TMPDIR:-/tmp}/tr-bare.$$.md")" ]; then
    pass "the bare-tick matcher fires on a command line without the flag (control)"
else
    fail "the bare-tick matcher missed a planted bare tick -- the case above proves nothing"
fi
rm -f "${TMPDIR:-/tmp}/tr-bare.$$.md"

# The frontmatter note tells a template editor where the rule lives, so nobody
# re-derives it in the template.
if grep -q '^# *Terminal-tick retention' "$TEMPLATE"; then
    pass "work-on.md's frontmatter records where the retention rule lives"
else
    fail "work-on.md has no frontmatter note pointing at the retention rule"
fi

command -v koto >/dev/null 2>&1 || {
    echo
    echo "SKIP: koto not on PATH -- the engine-backed cases did not run"
    echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed"
    [ "$FAIL_COUNT" -eq 0 ] || exit 1
    exit 0
}
command -v jq >/dev/null 2>&1 || {
    echo
    echo "SKIP: jq not on PATH -- the engine-backed cases did not run"
    echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed"
    [ "$FAIL_COUNT" -eq 0 ] || exit 1
    exit 0
}

WORKDIR=$(mktemp -d)
cleanup() { [ -n "${WORKDIR:-}" ] && rm -rf "$WORKDIR"; return 0; }
trap cleanup EXIT

# koto resolves its session store through the home directory, so pointing HOME
# at the temp tree keeps every session this harness creates out of the
# developer's real ~/.koto. Without it a failing run leaves sessions behind that
# the next run then finds -- and this suite retains sessions on purpose, so it
# would leave more than most.
export HOME="$WORKDIR/home"
mkdir -p "$HOME"

echo "koto: $(koto version 2>/dev/null | head -1)"

# A `koto init` that fails leaves every later call reporting the session missing,
# and assertions written against a session that never existed pass or fail for
# reasons unrelated to what they claim to test. Every init in this suite is
# checked. (The failure is not hypothetical: koto validates template variables
# against `^[a-zA-Z0-9._/:@ \-]*$`, so a checkout under a path containing a `+`
# fails init on any template that takes a path variable.)
init_or_die() {
    if ! koto status "$1" >/dev/null 2>&1; then
        echo "FAIL: koto init did not produce session '$1' -- no case below can be trusted" >&2
        exit 1
    fi
}

# --- a minimal parent/child pair, for the convergence cases -------------------
#
# These assert koto's behaviour at a child's terminal. work-on.md is not used:
# reaching a work-on terminal as a materialized child would test the same koto
# code path through far more of work-on's own gates. `blocked` stands in for
# work-on's done_blocked: a failure terminal whose edge writes failure_reason.

cat > "$WORKDIR/child.md" <<'CHILD_EOF'
---
name: retention-probe-child
version: "1.0"
description: Minimal child that ticks straight to a success or a failure terminal.
initial_state: work
states:
  work:
    accepts:
      status:
        type: enum
        values: [ok, blocked]
        required: true
    transitions:
      - target: done
        when:
          status: ok
      - target: blocked
        when:
          status: blocked
        context_assignments:
          failure_reason: "work blocked: probe"
  done:
    terminal: true
  blocked:
    terminal: true
    failure: true
---

## work

Submit `status: ok` or `status: blocked`.

## done

Terminal.

## blocked

Failure terminal.
CHILD_EOF

# Two transitions to a non-failure terminal, so a flag can ride a real earlier
# transition and be left off the one that lands (retain_early).
cat > "$WORKDIR/two_step.md" <<'TWO_STEP_EOF'
---
name: retention-probe-two-step
version: "1.0"
description: Two evidence-driven transitions to a non-failure terminal.
initial_state: work
states:
  work:
    accepts:
      status:
        type: enum
        values: [ok]
        required: true
    transitions:
      - target: mid
        when:
          status: ok
  mid:
    accepts:
      go:
        type: enum
        values: ["yes"]
        required: true
    transitions:
      - target: done
        when:
          go: "yes"
  done:
    terminal: true
---

## work

Submit `status: ok`.

## mid

Submit `go: yes`.

## done

Terminal.
TWO_STEP_EOF

# parent.md: a parent that waits for the gate to pass, behind a single
# unconditional exit.
cat > "$WORKDIR/parent.md" <<'PARENT_EOF'
---
name: retention-probe-parent
version: "1.0"
description: Minimal parent with a children-complete gate.
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
PARENT_EOF

# parent_hold.md: a parent that stays put whatever the gate says, so the gate
# can be read, and retry_failed submitted, without the parent advancing.
cat > "$WORKDIR/parent_hold.md" <<'HOLD_EOF'
---
name: retention-probe-parent-hold
version: "1.0"
description: A parent that only advances on explicit evidence, so the gate can be read.
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
      go:
        type: enum
        values: ["yes"]
        required: false
    materialize_children:
      from_field: tasks
      failure_policy: continue
      default_template: ./child.md
    transitions:
      - target: finished
        when:
          go: "yes"
  finished:
    terminal: true
---

## spawn

Submit tasks.

## finished

Terminal.
HOLD_EOF

TASKS='{"tasks":[{"name":"leaf","description":"leaf task"}]}'

# --- a root run's record survives its terminal ---------------------------------
#
# Driven through the SHIPPED work-on.md: entry -> context_injection ->
# done_blocked, which is the real terminal #360 is about.

drive_work_on_to_blocked() {
    # $1 session name, $2 extra flag for the terminal tick ("" or --no-cleanup)
    # PLUGIN_ROOT is required by the template (cascade_entry's gate resolves the
    # anchor finder against it) and koto resolves every required variable at
    # init, so a session cannot be created without it even though no case here
    # reaches that state. A literal rather than this checkout's path: koto
    # validates a value against ^[a-zA-Z0-9._/:@ \-]*$ and rejects the init if it
    # does not match, which a checkout under a directory containing "+" would.
    koto init "$1" --template "$TEMPLATE" \
        --var ISSUE_NUMBER=360 --var ARTIFACT_PREFIX="$1" \
        --var PLUGIN_ROOT=/nonexistent/plugin-root >/dev/null 2>&1
    init_or_die "$1"
    printf 'the running record\n' | koto context add "$1" plan.md >/dev/null 2>&1
    koto next "$1" --with-data '{"mode":"issue_backed","issue_number":"360"}' --no-cleanup >/dev/null 2>&1
    if [ -n "$2" ]; then
        koto next "$1" --with-data '{"status":"blocked"}' "$2" >/dev/null 2>&1
    else
        koto next "$1" --with-data '{"status":"blocked"}' >/dev/null 2>&1
    fi
}

drive_work_on_to_blocked retain_yes --no-cleanup
if [ "$(koto context get retain_yes plan.md 2>/dev/null)" = "the running record" ]; then
    pass "a root run reaching done_blocked with the flag keeps plan.md readable"
else
    fail "a root run reaching done_blocked with the flag lost plan.md"
fi

# done_blocked is a failure terminal, which koto keeps without the flag.
drive_work_on_to_blocked retain_no ""
if [ "$(koto context get retain_no plan.md 2>/dev/null)" = "the running record" ]; then
    pass "a root run reaching done_blocked without the flag keeps plan.md (a failure terminal is kept)"
else
    fail "a root run reaching done_blocked without the flag lost plan.md; koto $(koto version | head -1) should keep a failure terminal"
fi

# The control: without it this suite would pass on a koto that had stopped
# cleaning up at all, and the flag would look load-bearing when it was doing
# nothing. A success terminal is disposed of without the flag and kept with it.
koto init retain_no_ok --template "$WORKDIR/child.md" >/dev/null 2>&1
init_or_die retain_no_ok
printf 'the running record\n' | koto context add retain_no_ok plan.md >/dev/null 2>&1
koto next retain_no_ok --with-data '{"status":"ok"}' >/dev/null 2>&1
if koto context get retain_no_ok plan.md >/dev/null 2>&1; then
    fail "a root run reaching a success terminal without the flag kept plan.md -- the control did not fire"
else
    pass "a root run reaching a success terminal without the flag loses plan.md (control)"
fi
koto init retain_yes_ok --template "$WORKDIR/child.md" >/dev/null 2>&1
init_or_die retain_yes_ok
printf 'the running record\n' | koto context add retain_yes_ok plan.md >/dev/null 2>&1
RESP=$(koto next retain_yes_ok --with-data '{"status":"ok"}' --no-cleanup 2>/dev/null)
if [ "$(koto context get retain_yes_ok plan.md 2>/dev/null)" = "the running record" ] \
    && printf '%s' "$RESP" | jq -e '.retention.retained == true and .retention.reason == "no_cleanup"' >/dev/null 2>&1; then
    pass "a root run reaching a success terminal with the flag keeps plan.md, and the response says retention.reason no_cleanup"
else
    fail "a root run reaching a success terminal with the flag lost plan.md or did not report no_cleanup: $(printf '%s' "$RESP" | head -c 300)"
fi

# --- a blocked edge's context_assignments execute --------------------------------
#
# The blocked edge out of context_injection writes `failure_reason` into the
# session's context with the submitted evidence interpolated, where `koto
# context get` reads it for a failed run. Compiling proves only that the blocks
# are well-formed; this drives one edge and reads the key back, so it proves
# they run. The kept failure terminal is what makes the key readable afterwards.
koto init assign_probe --template "$TEMPLATE" \
    --var ISSUE_NUMBER=360 --var ARTIFACT_PREFIX=assign_probe \
    --var PLUGIN_ROOT=/nonexistent/plugin-root >/dev/null 2>&1
init_or_die assign_probe
koto next assign_probe --with-data '{"mode":"issue_backed","issue_number":"360"}' --no-cleanup >/dev/null 2>&1
koto next assign_probe --with-data '{"status":"blocked","detail":"issue body could not be read"}' --no-cleanup >/dev/null 2>&1
ASSIGNED=$(koto context get assign_probe failure_reason 2>/dev/null)
if [ "$ASSIGNED" = "context_injection blocked: issue body could not be read" ]; then
    pass "the blocked edge's context_assignments wrote failure_reason with the evidence interpolated"
else
    fail "failure_reason after the blocked edge was [$ASSIGNED], expected the interpolated context_injection wording -- the assignments did not execute"
fi
if [ "$(koto status assign_probe 2>/dev/null | jq -r '.current_state')" = "done_blocked" ]; then
    pass "the edge that wrote failure_reason is the one that reached done_blocked"
else
    fail "the assignment probe did not reach done_blocked"
fi

# The flag is read only on the tick that lands on a terminal, so carrying it
# earlier retains nothing. This is why the rule cannot be "pass it once". The
# case runs against two_step.md's success terminal, since a failure terminal is
# kept anyway: the flag rides the real work -> mid transition, and the tick that
# lands on the terminal doesn't carry it.
koto init retain_early --template "$WORKDIR/two_step.md" >/dev/null 2>&1
init_or_die retain_early
printf 'the running record\n' | koto context add retain_early plan.md >/dev/null 2>&1
koto next retain_early --with-data '{"status":"ok"}' --no-cleanup >/dev/null 2>&1
if [ "$(koto status retain_early 2>/dev/null | jq -r '.current_state')" != mid ]; then
    fail "retain_early's flagged tick did not take the work -> mid transition -- the case below would prove nothing"
fi
koto next retain_early --with-data '{"go":"yes"}' >/dev/null 2>&1
if koto context get retain_early plan.md >/dev/null 2>&1; then
    fail "the flag on an earlier tick retained the record -- it is meant to act only on the terminal tick"
else
    pass "the flag on an earlier tick retains nothing; only the terminal tick counts"
fi

# --- retention must not turn into a false "already done" ---------------------
#
# Retention creates an ambiguity: a finished session is still on disk, so the
# Resume step finds it where it used to find nothing and fall through to a
# fresh `koto init`. Ticking it answers `action: "done"`, which the Execution
# Loop says to report as the outcome -- a run claiming the issue is complete
# having done none of it.
#
# Two halves, and they are not equally strong. The first is EXECUTED: the signal
# the Resume step reads exists, says what the guard needs, and the ambiguity it
# resolves is real. The second is a GREP: whether an agent actually follows the
# written step cannot be executed here, so what is pinned is that the instruction
# still reads the signal before ticking. A later edit that drops the guard fails
# the grep; an agent that ignores the guard is beyond this harness.

drive_work_on_to_blocked resume_probe --no-cleanup

if [ "$(koto status resume_probe 2>/dev/null | jq -r '.is_terminal')" = "true" ]; then
    pass "a retained finished session reports is_terminal: true, the signal the Resume guard reads"
else
    fail "koto status no longer reports is_terminal: true for a retained finished session -- the Resume guard's signal is gone and the guard cannot work"
fi

# The ambiguity the guard exists for: koto workflows still lists it, unmarked.
if koto workflows 2>/dev/null | jq -e --arg s resume_probe 'map(select(.name == $s)) | length == 1' >/dev/null 2>&1; then
    pass "koto workflows still lists the finished session, so the Resume step does find it and must disambiguate"
else
    fail "koto workflows no longer lists a retained finished session -- re-check whether the Resume guard is still needed"
fi

# Reading the signal must not advance or dispose of anything.
if [ "$(koto context get resume_probe plan.md 2>/dev/null)" = "the running record" ]; then
    pass "koto status left the record intact, so the guard cannot destroy what it inspects"
else
    fail "reading koto status destroyed or altered the retained record"
fi

if grep -q 'is_terminal' "$SKILL_MD"; then
    pass "SKILL.md's Resume step reads is_terminal (grep, not an executed agent run)"
else
    fail "SKILL.md no longer reads is_terminal before ticking a found session -- the Resume guard has been dropped"
fi

# --- a flagged child is kept and still delivers its result ---------------------
#
# The pre-0.14 exception existed because the flag on a child withheld its
# result: the parent's gate reported all_complete true with results_in false,
# and a parent that waits on the gate never advanced. These cases pin the
# opposite, which is what lets a child carry the flag like any other run.

parent_tick() { # $1 parent session: resubmits the tasks and prints the response, whose blocking_conditions carry the gate
    koto next "$1" --with-data "$TASKS" 2>/dev/null
}

koto init flagged --template "$WORKDIR/parent_hold.md" >/dev/null 2>&1
init_or_die flagged
koto next flagged --with-data "$TASKS" >/dev/null 2>&1
koto next flagged.leaf --with-data '{"status":"ok"}' --no-cleanup >/dev/null 2>&1
if [ "$(koto status flagged.leaf 2>/dev/null | jq -r '.is_terminal')" = "true" ]; then
    pass "a child whose terminal tick carries the flag is kept at its success terminal"
else
    fail "a flagged child was not kept at its success terminal"
fi
# The tick's own response is read rather than a missing field, which an error
# response would also produce: the tick must be accepted, leave the parent at
# spawn (parent_hold advances only on `go`), and carry no batch_done blocker.
RESP=$(parent_tick flagged)
if printf '%s' "$RESP" | jq -e '.error == null and .state == "spawn"
        and ([.blocking_conditions[]? | select(.name == "batch_done")] | length == 0)' >/dev/null 2>&1; then
    pass "a flagged child's result reaches its parent: the gate passes with nothing blocking"
else
    fail "a flagged child's result did not reach its parent: $(printf '%s' "$RESP" | head -c 300)"
fi

# The control: an unflagged child delivers too, and is not kept.
koto init unflagged --template "$WORKDIR/parent_hold.md" >/dev/null 2>&1
init_or_die unflagged
koto next unflagged --with-data "$TASKS" >/dev/null 2>&1
koto next unflagged.leaf --with-data '{"status":"ok"}' >/dev/null 2>&1
RESP=$(parent_tick unflagged)
if printf '%s' "$RESP" | jq -e '.error == null and ([.blocking_conditions[]? | select(.name == "batch_done")] | length == 0)' >/dev/null 2>&1 \
    && ! koto status unflagged.leaf >/dev/null 2>&1; then
    pass "an unflagged child delivers its result and is not kept at a success terminal (control)"
else
    fail "the unflagged control did not deliver, or was kept: $(printf '%s' "$RESP" | head -c 300)"
fi

# parent.md waits for the gate to pass, the shape a flagged child used to wedge.
koto init waits --template "$WORKDIR/parent.md" >/dev/null 2>&1
init_or_die waits
koto next waits --with-data "$TASKS" >/dev/null 2>&1
koto next waits.leaf --with-data '{"status":"ok"}' --no-cleanup >/dev/null 2>&1
RESP=$(koto next waits --with-data "$TASKS" 2>/dev/null)
if printf '%s' "$RESP" | jq -e '.error == null and .state == "finished"' >/dev/null 2>&1; then
    pass "against a parent that waits for the gate to pass, a flagged child lets it reach finished"
else
    fail "a parent that waits on the gate did not advance past a flagged child: $(printf '%s' "$RESP" | head -c 300)"
fi

# --- a failed child is kept and readable ----------------------------------------
#
# The record a needs_attention batch most wants is the failed child's. It is
# kept without the flag, readable with koto's own commands, and still the
# parent's to retry.
koto init failed_child --template "$WORKDIR/parent_hold.md" >/dev/null 2>&1
init_or_die failed_child
koto next failed_child --with-data "$TASKS" >/dev/null 2>&1
RESP=$(koto next failed_child.leaf --with-data '{"status":"blocked"}' 2>/dev/null)
if printf '%s' "$RESP" | jq -e '.retention.retained == true and .retention.reason == "failure_terminal"' >/dev/null 2>&1 \
    && [ "$(koto status failed_child.leaf 2>/dev/null | jq -r '.current_state')" = "blocked" ]; then
    pass "an unflagged child reaching a failure terminal is kept (retention.reason failure_terminal), and koto status reports where it stopped"
else
    fail "an unflagged failed child was not kept: $(printf '%s' "$RESP" | head -c 300)"
fi
if [ "$(koto context get failed_child.leaf failure_reason 2>/dev/null)" = "work blocked: probe" ]; then
    pass "the kept failed child's failure_reason is readable with koto context get"
else
    fail "koto context get could not read the kept failed child's failure_reason"
fi
koto next failed_child --with-data '{"retry_failed":{"children":["leaf"]}}' >/dev/null 2>&1
if [ "$(koto status failed_child.leaf 2>/dev/null | jq -r '.current_state')" = "work" ]; then
    pass "the parent's retry_failed acts on the kept failed child, rewinding it to work"
else
    fail "retry_failed did not rewind the kept failed child: state $(koto status failed_child.leaf 2>/dev/null | jq -r '.current_state')"
fi

echo
echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed"
[ "$FAIL_COUNT" -eq 0 ] || exit 1
exit 0
