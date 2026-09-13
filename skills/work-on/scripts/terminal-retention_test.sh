#!/usr/bin/env bash
# terminal-retention_test.sh -- the terminal tick keeps its record, and only a root does it
# Part of the work-on skill
#
# koto deletes a session when it reaches a terminal state, and the deletion
# takes the session's `ctx/` with it. `koto next --no-cleanup` suppresses that,
# which is how a /work-on run that ends at `done_blocked` keeps the record of
# why (#360).
#
# The flag cannot simply be applied everywhere. On a CHILD session it also
# suppresses the `request_store.result` and `ChildCompleted` events that
# /execute's `children-complete` gate reads to learn the child finished, and the
# parent's converge then blocks permanently. So retention is root-only, and
# `session-role.sh` is the discriminator that decides.
#
# This harness asserts that contract on four fronts, in execution order:
#
#   nothing has tidied the flag into the child template   (cases 1-3)
#   the discriminator refuses a call it cannot answer     (case 4)
#   the discriminator answers correctly, and fails safe   (cases 5-8)
#   a root run's record survives its blocked terminal     (cases 9-11)
#   retention does not become a false "already done"      (cases 12-15)
#   a child's terminal tick must NOT carry the flag       (cases 16-17)
#
# Cases 1-4 need no engine and run BEFORE the koto check, so the macOS bash 3.2
# floor leg -- where koto is absent -- still exercises this file rather than
# skipping it whole. Cases 9-11 drive the SHIPPED work-on.md to its real
# `done_blocked` terminal rather than a stand-in, so a template edit that moves
# that terminal fails here. Cases 12-13 use a minimal parent/child pair, because
# what they assert is koto's convergence behaviour and not anything about
# work-on.md's own states.
#
# The discriminator cases describe BEHAVIOUR ("a child classifies as child"),
# never the mechanism session-role.sh currently uses to decide. koto's parentage
# signal may change; these cases should survive that without being rewritten.
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
# that vanished from CI -- the install fails first.
#
# bash 3.2 floor: no associative arrays, no namerefs, no mapfile.

set -uo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
SKILL_DIR=$(cd "$SCRIPT_DIR/.." && pwd)
TEMPLATE="$SKILL_DIR/koto-templates/work-on.md"
PHASES="$SKILL_DIR/references/phases"
SKILL_MD="$SKILL_DIR/SKILL.md"
ROLE_SH="$SCRIPT_DIR/session-role.sh"

PASS_COUNT=0
FAIL_COUNT=0

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

pass() { echo -e "${GREEN}PASS${NC}: $*"; PASS_COUNT=$((PASS_COUNT + 1)); }
fail() { echo -e "${RED}FAIL${NC}: $*"; FAIL_COUNT=$((FAIL_COUNT + 1)); }

[ -f "$TEMPLATE" ] || { echo "FAIL: template not found at $TEMPLATE" >&2; exit 1; }
[ -f "$ROLE_SH" ]  || { echo "FAIL: discriminator not found at $ROLE_SH" >&2; exit 1; }

# --- nothing has tidied the flag into the child template ---------------------
#
# These need no engine, so they run first and the floor leg gets real coverage.
#
# work-on.md and its phase files are read by BOTH a root run and a child. A
# `--no-cleanup` written into either would reach children, which is the wedge
# this whole contract exists to avoid. The rule therefore lives in SKILL.md,
# which is consumed per-run, and these cases keep a later edit from relocating
# it.

if grep -rn -- '--no-cleanup' "$TEMPLATE" >/dev/null 2>&1; then
    fail "work-on.md carries --no-cleanup; a child reads this template and would wedge its parent"
else
    pass "work-on.md carries no --no-cleanup, so a child cannot pick it up from the template"
fi

if grep -rn -- '--no-cleanup' "$PHASES" >/dev/null 2>&1; then
    fail "a references/phases file carries --no-cleanup; children read these too"
else
    pass "no references/phases file carries --no-cleanup"
fi

# The rule has to actually be stated somewhere a root run reads, and has to
# route through the discriminator rather than asserting rootness on its own.
if grep -q -- '--no-cleanup' "$SKILL_MD" && grep -q 'session-role.sh' "$SKILL_MD"; then
    pass "SKILL.md states the retention rule and routes it through session-role.sh"
else
    fail "SKILL.md must state the retention rule and decide it with session-role.sh"
fi

bash "$ROLE_SH" >/dev/null 2>&1
if [ "$?" -eq 2 ]; then
    pass "the discriminator rejects a missing session name with exit 2"
else
    fail "the discriminator did not exit 2 on a missing session name"
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

role_of() { bash "$ROLE_SH" "$1" 2>/dev/null; }

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
# These assert koto's behaviour when a child's terminal tick carries the flag.
# work-on.md is not used: reaching a work-on terminal as a materialized child
# would test the same koto code path through far more of work-on's own gates.

cat > "$WORKDIR/child.md" <<'CHILD_EOF'
---
name: retention-probe-child
version: "1.0"
description: Minimal child that ticks straight to a terminal.
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

Submit `status: ok`.

## done

Terminal.
CHILD_EOF

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

TASKS='{"tasks":[{"name":"leaf","description":"leaf task"}]}'

# --- the discriminator -------------------------------------------------------

koto init role_root --template "$WORKDIR/child.md" >/dev/null 2>&1
init_or_die role_root
if [ "$(role_of role_root)" = "root" ]; then
    pass "a directly-initialized session classifies as root"
else
    fail "a directly-initialized session classified as '$(role_of role_root)', expected root"
fi

koto init role_parent --template "$WORKDIR/parent.md" >/dev/null 2>&1
init_or_die role_parent
koto next role_parent --with-data "$TASKS" >/dev/null 2>&1
if [ "$(role_of role_parent.leaf)" = "child" ]; then
    pass "a materialized child classifies as child"
else
    fail "a materialized child classified as '$(role_of role_parent.leaf)', expected child"
fi

if [ "$(role_of role_parent)" = "root" ]; then
    pass "the parent of a materialized child still classifies as root"
else
    fail "the parent classified as '$(role_of role_parent)', expected root"
fi

# Unknown must fail toward withholding the flag: losing one run's record is
# recoverable, wedging a parent's converge is not.
if [ "$(role_of no-such-session-anywhere)" = "child" ]; then
    pass "an unresolvable session classifies as child, withholding retention"
else
    fail "an unresolvable session classified as '$(role_of no-such-session-anywhere)', expected child"
fi

# --- a root run's record survives its blocked terminal -----------------------
#
# Driven through the SHIPPED work-on.md: entry -> context_injection ->
# done_blocked, which is the real terminal #360 is about.

drive_work_on_to_blocked() {
    # $1 session name, $2 extra flag for the terminal tick ("" or --no-cleanup)
    koto init "$1" --template "$TEMPLATE" \
        --var ISSUE_NUMBER=360 --var ARTIFACT_PREFIX="$1" >/dev/null 2>&1
    init_or_die "$1"
    printf 'the running record\n' | koto context add "$1" plan.md >/dev/null 2>&1
    koto next "$1" --with-data '{"mode":"issue_backed","issue_number":"360"}' >/dev/null 2>&1
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

# The negative control matters: without it this suite would pass on a koto that
# had stopped cleaning up at all, and the flag would look load-bearing when it
# was doing nothing.
drive_work_on_to_blocked retain_no ""
if koto context get retain_no plan.md >/dev/null 2>&1; then
    fail "a root run reaching done_blocked without the flag kept plan.md -- the control did not fire"
else
    pass "a root run reaching done_blocked without the flag loses plan.md (control)"
fi

# The flag is read only on the tick that lands on a terminal, so carrying it
# earlier retains nothing. This is why the rule cannot be "pass it once".
koto init retain_early --template "$TEMPLATE" \
    --var ISSUE_NUMBER=360 --var ARTIFACT_PREFIX=retain_early >/dev/null 2>&1
init_or_die retain_early
printf 'the running record\n' | koto context add retain_early plan.md >/dev/null 2>&1
koto next retain_early --with-data '{"mode":"issue_backed","issue_number":"360"}' --no-cleanup >/dev/null 2>&1
koto next retain_early --with-data '{"status":"blocked"}' >/dev/null 2>&1
if koto context get retain_early plan.md >/dev/null 2>&1; then
    fail "the flag on an earlier tick retained the record -- it is meant to act only on the terminal tick"
else
    pass "the flag on an earlier tick retains nothing; only the terminal tick counts"
fi

# --- retention must not turn into a false "already done" ---------------------
#
# Retention creates an ambiguity that did not exist before it: a finished session
# is still on disk, so the Resume step finds it where it used to find nothing and
# fall through to a fresh `koto init`. Ticking it answers `action: "done"`, which
# the Execution Loop says to report as the outcome -- a run claiming the issue is
# complete having done none of it -- and that same tick disposes of the session.
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

# Reading the signal must not advance or dispose of anything: the whole point of
# using koto status rather than a tick is that discovering the session is
# finished cannot itself destroy the record.
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

# --- a child's terminal tick must not carry the flag -------------------------
#
# The tripwire. If koto#240 or a later koto makes the flag safe for children,
# this case goes red and tells the next author the exception can be dropped,
# rather than leaving it as folklore in a comment.

converge_state() {
    # Prints the parent's converge_blocked verdict after its children settled.
    koto next "$1" --with-data "$TASKS" 2>/dev/null \
        | jq -r '[.blocking_conditions[]? | select(.name=="batch_done")][0].output.converge_blocked // "absent"'
}

koto init wedge --template "$WORKDIR/parent.md" >/dev/null 2>&1
init_or_die wedge
koto next wedge --with-data "$TASKS" >/dev/null 2>&1
koto next wedge.leaf --with-data '{"status":"ok"}' --no-cleanup >/dev/null 2>&1
if [ "$(converge_state wedge)" = "true" ]; then
    pass "a child whose terminal tick carries the flag blocks its parent's converge"
else
    fail "a child's flagged terminal tick did not block the converge -- the child exception may no longer be needed; re-check koto#240 before dropping it"
fi

koto init nowedge --template "$WORKDIR/parent.md" >/dev/null 2>&1
init_or_die nowedge
koto next nowedge --with-data "$TASKS" >/dev/null 2>&1
koto next nowedge.leaf --with-data '{"status":"ok"}' >/dev/null 2>&1
if [ "$(converge_state nowedge)" = "absent" ]; then
    pass "a child whose terminal tick omits the flag lets its parent converge (control)"
else
    fail "a child's unflagged terminal tick still blocked the converge"
fi

echo
echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed"
[ "$FAIL_COUNT" -eq 0 ] || exit 1
exit 0
