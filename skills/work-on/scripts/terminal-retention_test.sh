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
# This harness asserts that contract in these groups, in execution order --
# deliberately not numbered, because a numbered map goes stale the first time a
# case is inserted and then misdirects the reader it was written for:
#
#   engine-free, so they also run on the bash 3.2 floor where koto is absent:
#     nothing has tidied the flag into the child template or its phase files
#     SKILL.md states the rule and routes it through the discriminator
#     the template frontmatter records why the flag must not be added there
#     the discriminator refuses a call it cannot answer
#
#   engine-backed:
#     the discriminator answers correctly for a root, a child, and a parent,
#       and fails safe on a session it cannot resolve
#     a root run's record survives its blocked terminal, with a control, and
#       the flag on an earlier tick is shown to retain nothing
#     retention does not become a false "already done" on the next run
#     a child's terminal tick must NOT carry the flag, with a control
#
# The root-run cases drive the SHIPPED work-on.md to its real `done_blocked`
# terminal rather than a stand-in, so a template edit that moves that terminal
# fails here. The child cases use a minimal parent/child pair, because what they
# assert is koto's convergence behaviour rather than anything about work-on.md's
# own states.
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
# `--no-cleanup` written into either would reach children, and a child carrying
# it withholds its result from its parent -- the outcome this contract exists to
# avoid. The rule therefore lives in SKILL.md,
# which is consumed per-run, and these cases keep a later edit from relocating
# it.

# The frontmatter note that tells a template editor WHY the flag must not be
# here has to be able to name it, so YAML comments are excluded -- but ONLY
# inside the frontmatter. A `#`-leading line in the markdown body is not a
# comment at all: koto renders body prose into the state's directive verbatim,
# so a child would read it. Scoping the exclusion by position rather than by the
# `#` alone is what keeps that distinction; an earlier file-wide version of this
# grep would have let a body line through.
template_flag_sites() {
    awk '
        NR == 1 && $0 == "---" { in_fm = 1; next }
        in_fm && $0 == "---"   { in_fm = 0; next }
        /--no-cleanup/ {
            if (in_fm && $0 ~ /^[[:space:]]*#/) next
            printf "%d: %s\n", NR, $0
        }
    ' "$1" 2>/dev/null
}

if [ -n "$(template_flag_sites "$TEMPLATE")" ]; then
    fail "work-on.md carries --no-cleanup outside a YAML comment; a child reads this template and would withhold its result from its parent:
$(template_flag_sites "$TEMPLATE")"
else
    pass "work-on.md carries no --no-cleanup call site, so a child cannot pick it up from the template"
fi

# Phase files a work-on.md state sends a child to must not carry the flag. The
# ban is scoped to those files, not to the directory: phase-2.5 lives here but is
# read only by /execute's worktree_discipline_check, on the orchestrator -- always
# a root -- and it MUST carry the flag, because its intent-changing tick chains
# into done_blocked. An earlier directory-wide ban here actively forbade that fix.
#
# The exemption is only as good as its premise, so the premise is checked:
# work-on.md must never route to phase-2.5. If it ever does, that file becomes
# child-readable and the exemption would hand the flag to children.
ORCH_ONLY="phase-2.5-worktree-discipline.md"
PHASE_HITS=$(grep -rln -- '--no-cleanup' "$PHASES" 2>/dev/null | grep -v "/$ORCH_ONLY\$")
if [ -n "$PHASE_HITS" ]; then
    fail "a child-readable references/phases file carries --no-cleanup:
$PHASE_HITS"
else
    pass "no child-readable phase file carries --no-cleanup ($ORCH_ONLY excepted: orchestrator-only)"
fi

if grep -q "$ORCH_ONLY" "$TEMPLATE"; then
    fail "work-on.md now references $ORCH_ONLY, so a child can be sent there -- its --no-cleanup would reach children. Drop the exemption above or move the file."
else
    pass "work-on.md never routes to $ORCH_ONLY, so its flag cannot reach a child"
fi

# The frontmatter note is itself required: without it a future editor has no
# reason recorded for the flag's absence and re-adds it. This is the template
# half of the issue's "say why the flag is there" criterion.
if grep -q '^# *Terminal-tick retention' "$TEMPLATE"; then
    pass "work-on.md's frontmatter records why the flag is absent here and where the rule lives"
else
    fail "work-on.md has no frontmatter note explaining why --no-cleanup must not be added to it"
fi

# The rule has to actually be stated somewhere a root run reads, and has to
# route through the discriminator rather than asserting rootness on its own.
if grep -q -- '--no-cleanup' "$SKILL_MD" && grep -q 'session-role.sh' "$SKILL_MD"; then
    pass "SKILL.md states the retention rule and routes it through session-role.sh"
else
    fail "SKILL.md must state the retention rule and decide it with session-role.sh"
fi

# ...and it has to be UNIVERSAL, which the check above does not establish. The
# rule's value is that it covers ticks nobody had thought of when it was written:
# a state added later reaches a terminal through a tick the author never saw. An
# enumeration cannot do that, and the difference is invisible to a grep for the
# flag.
#
# Measured, before this case existed: narrowing the rule to "the koto next calls
# that reach context_injection, analysis and implementation carry --no-cleanup"
# -- an enumeration omitting the cascade terminals entirely -- left this suite
# 20/20 green. Coverage of any tick not named in that list was an assumption.
#
# Two things are asserted. The rule quantifies over every tick, and it names no
# state, because the moment it names one it has become a list.
RETENTION_RULE=$(awk '
    /^\*\*Retention:/ { inrule = 1 }
    inrule { print }
    inrule && /^$/ { exit }
' "$SKILL_MD")

if [ -z "$RETENTION_RULE" ]; then
    fail "the retention rule paragraph could not be found in SKILL.md -- it was reworded, and this case no longer reads it"
elif ! printf '%s' "$RETENTION_RULE" | grep -qE 'every (\`?koto next\`?|tick)'; then
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
    --var ISSUE_NUMBER=360 --var ARTIFACT_PREFIX=retain_early \
    --var PLUGIN_ROOT=/nonexistent/plugin-root >/dev/null 2>&1
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
# What the flag does to a child, pinned as the shape-independent fact: the
# child's result never reaches its parent. The gate reports all_complete true
# with results_in false.
#
# An earlier version of this block asserted that a flagged child blocks its
# parent's converge. That holds only for a parent that waits for the gate to
# pass, like parent.md's single unconditional exit -- NOT for /execute, whose
# spawn_and_await keys on gates.batch_done.all_complete and so advances anyway,
# without the child's result. So the assertion is the result, and the two parent
# shapes are shown separately rather than one being generalised to the other.
#
# This is also the tripwire: if koto#240 or a later koto makes the flag safe for
# children, results_in goes true under the flag, this case goes red, and the
# exception can be dropped rather than surviving as folklore.

gate_field() { # $1 parent session, $2 field of the batch_done gate output
    # Not `.output[$f] // "absent"`: jq's `//` treats false as empty as well as
    # null, so a results_in of false would read back as "absent" and this suite
    # would report the opposite of what koto said. Null is tested explicitly.
    koto next "$1" --with-data "$TASKS" 2>/dev/null \
        | jq -r --arg f "$2" '
            ([.blocking_conditions[]? | select(.name=="batch_done")][0].output) as $o
            | if $o == null or $o[$f] == null then "absent" else ($o[$f] | tostring) end'
}

# parent_hold.md: a parent that stays put whatever the gate says, so the gate
# can be read without the parent advancing and cleaning itself up.
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
      failure_policy: skip_dependents
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

koto init withheld --template "$WORKDIR/parent_hold.md" >/dev/null 2>&1
init_or_die withheld
koto next withheld --with-data "$TASKS" >/dev/null 2>&1
koto next withheld.leaf --with-data '{"status":"ok"}' --no-cleanup >/dev/null 2>&1
if [ "$(gate_field withheld all_complete)" = "true" ] && [ "$(gate_field withheld results_in)" = "false" ]; then
    pass "a child whose terminal tick carries the flag withholds its result: all_complete true, results_in false"
else
    fail "a flagged child's result reached its parent (results_in is not false) -- the child exception may no longer be needed; re-check koto#240 before dropping it"
fi

koto init delivered --template "$WORKDIR/parent_hold.md" >/dev/null 2>&1
init_or_die delivered
koto next delivered --with-data "$TASKS" >/dev/null 2>&1
koto next delivered.leaf --with-data '{"status":"ok"}' >/dev/null 2>&1
# An unflagged child delivers its result, so the gate passes and is not reported
# as a blocking condition at all.
if [ "$(gate_field delivered results_in)" = "absent" ]; then
    pass "a child whose terminal tick omits the flag delivers its result (control)"
else
    fail "an unflagged child's result did not reach its parent"
fi

# The two consequences, which depend on the parent and not the child. parent.md
# waits for the gate to pass, so it never advances; this is why the exception
# matters for any parent shaped like it, even though /execute is not.
koto init waits --template "$WORKDIR/parent.md" >/dev/null 2>&1
init_or_die waits
koto next waits --with-data "$TASKS" >/dev/null 2>&1
koto next waits.leaf --with-data '{"status":"ok"}' --no-cleanup >/dev/null 2>&1
if [ "$(gate_field waits converge_blocked)" = "true" ]; then
    pass "against a parent that waits for the gate to pass, a flagged child leaves it blocked"
else
    fail "a parent that waits on the gate advanced despite a flagged child"
fi

echo
echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed"
[ "$FAIL_COUNT" -eq 0 ] || exit 1
exit 0
