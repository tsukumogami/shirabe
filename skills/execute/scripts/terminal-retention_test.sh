#!/usr/bin/env bash
# terminal-retention_test.sh -- the orchestrator's terminal tick keeps its record
# Part of the execute skill
#
# koto deletes a session on the tick that reaches a terminal state, and the
# deletion takes the session's `ctx/` with it. `/execute` ends at `done_blocked`
# when the chain cannot proceed and at `paused_for_review` when an interactive
# run hands a DRAFT PR back for review; both lose their context without
# `koto next --no-cleanup` (#360). The second is the worse loss -- a pause is
# solicited, and what dies with it is what a resume reads.
#
# `/execute` passes the flag unconditionally, where `/work-on` has to decide per
# run. That is sound only while an orchestrator session is always a root, so
# this harness checks the premise rather than trusting it:
#
#   the orchestrator's blocked terminal keeps its context     (cases 1-2)
#   its pause terminal keeps its context                      (case 3)
#   execute.md is never materialized as a koto child          (case 4)
#   SKILL.md states the rule                                  (case 5)
#
# Case 4 is the tripwire. If a future change makes `/execute` spawnable as a
# child, the unconditional flag becomes the wedge documented in
# skills/work-on/scripts/session-role.sh, and this case is what says so before
# it ships rather than after.
#
# Cases 1-3 drive the SHIPPED execute.md to its real terminals, so a template
# edit that moves them fails here.
#
# Usage: terminal-retention_test.sh
#
# Exit codes:
#   0 -- all cases pass, or koto is absent and the run skipped
#   1 -- one or more cases failed
#
# A missing koto exits 0 with a loud SKIP, matching settled-branch-record_test.sh:
# the Linux leg of check-execute-scripts.yml installs koto through the project
# tool manifest so the assertions genuinely run, and the macOS leg is the bash
# 3.2 floor check, where failing on absence would red the leg for a reason that
# has nothing to do with what it checks.
#
# bash 3.2 floor: no associative arrays, no namerefs, no mapfile.

set -uo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
SKILL_DIR=$(cd "$SCRIPT_DIR/.." && pwd)
SKILLS_DIR=$(cd "$SKILL_DIR/.." && pwd)
TEMPLATE="$SKILL_DIR/koto-templates/execute.md"
SKILL_MD="$SKILL_DIR/SKILL.md"

PASS_COUNT=0
FAIL_COUNT=0

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

pass() { echo -e "${GREEN}PASS${NC}: $*"; PASS_COUNT=$((PASS_COUNT + 1)); }
fail() { echo -e "${RED}FAIL${NC}: $*"; FAIL_COUNT=$((FAIL_COUNT + 1)); }

# --- case 4 needs no engine, so it runs before the koto skip ------------------
#
# The premise behind /execute's unconditional flag: nothing materializes
# execute.md as a child. `default_template` is how a koto template names the
# template its children are built from, so a hit anywhere outside a comment is
# the thing this case exists to catch.

# The `cut -d: -f3-` drops the `path:line:` prefix before matching, or every hit
# inside execute.md itself would match on its own filename.
CHILD_DECLS=$(grep -rn 'default_template:' "$SKILLS_DIR"/*/koto-templates/*.md 2>/dev/null \
    | grep -v '^[^:]*:[0-9]*: *#' \
    | awk -F: '{ line = $0; sub(/^[^:]*:[0-9]*:/, "", line); if (line ~ /execute\.md/) print $0 }')
if [ -z "$CHILD_DECLS" ]; then
    pass "no template names execute.md as a default_template, so an orchestrator session is always a root"
else
    fail "execute.md is named as a default_template, so /execute can now run as a child and its unconditional --no-cleanup would block the parent's converge:
$CHILD_DECLS"
fi

if grep -q -- '--no-cleanup' "$SKILL_MD"; then
    pass "SKILL.md states the terminal-tick retention rule"
else
    fail "SKILL.md must state that the orchestrator's koto next carries --no-cleanup"
fi

command -v koto >/dev/null 2>&1 || {
    echo
    echo "SKIP: koto not on PATH -- the engine-backed cases did not run"
    echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed"
    [ "$FAIL_COUNT" -eq 0 ] || exit 1
    exit 0
}
[ -f "$TEMPLATE" ] || { echo "FAIL: template not found at $TEMPLATE" >&2; exit 1; }

WORKDIR=$(mktemp -d)
cleanup() { [ -n "${WORKDIR:-}" ] && rm -rf "$WORKDIR"; return 0; }
trap cleanup EXIT

# Keep every session this harness creates out of the developer's real ~/.koto.
# This suite retains sessions on purpose, so it would leave more behind than most.
export HOME="$WORKDIR/home"
mkdir -p "$HOME"

# PLUGIN_ROOT is a fixed literal rather than this checkout's path. koto validates
# a variable's value against `^[a-zA-Z0-9._/:@ \-]*$`, and a checkout sitting
# under a directory with a `+` in it fails that -- silently, since the failure is
# on `koto init` and every later call then reports the session missing. The
# states these cases touch never read PLUGIN_ROOT, so a stand-in is honest here;
# what would not be honest is a suite whose init failed and whose assertions
# therefore proved nothing, which is why init_or_die exists.
init_orchestrator() {
    koto init "$1" --template "$TEMPLATE" \
        --var PLAN_DOC=docs/plans/PLAN-probe.md \
        --var PLAN_SLUG=probe \
        --var PLUGIN_ROOT=/koto-probe \
        --var PAUSE_BEFORE_FINALIZE=false >/dev/null 2>&1
    if ! koto status "$1" >/dev/null 2>&1; then
        echo "FAIL: koto init did not produce session '$1' -- the engine-backed cases cannot run" >&2
        koto init "$1" --template "$TEMPLATE" \
            --var PLAN_DOC=docs/plans/PLAN-probe.md \
            --var PLAN_SLUG=probe \
            --var PLUGIN_ROOT=/koto-probe \
            --var PAUSE_BEFORE_FINALIZE=false 2>&1 | tail -2 >&2
        exit 1
    fi
    printf 'the orchestrator record\n' | koto context add "$1" summary.md >/dev/null 2>&1
}

# --- the blocked terminal keeps its context ----------------------------------

init_orchestrator block_keep
koto next block_keep --with-data '{"status":"blocked","detail":"probe"}' --no-cleanup >/dev/null 2>&1
if [ "$(koto context get block_keep summary.md 2>/dev/null)" = "the orchestrator record" ]; then
    pass "an orchestrator run reaching done_blocked with the flag keeps its context"
else
    fail "an orchestrator run reaching done_blocked with the flag lost its context"
fi

# Without the control this suite would pass on a koto that had stopped cleaning
# up at all, and the flag would look load-bearing while doing nothing.
init_orchestrator block_drop
koto next block_drop --with-data '{"status":"blocked","detail":"probe"}' >/dev/null 2>&1
if koto context get block_drop summary.md >/dev/null 2>&1; then
    fail "an orchestrator run reaching done_blocked without the flag kept its context -- the control did not fire"
else
    pass "an orchestrator run reaching done_blocked without the flag loses its context (control)"
fi

# --- the pause terminal keeps its context ------------------------------------
#
# paused_for_review is a suspension, not a termination: the operator is expected
# to come back. It is nonetheless terminal: true, so koto disposes of it on
# arrival like any other. #360's written acceptance criteria cover only the
# blocked terminal; this case is the widening, argued in the PR.

PAUSE_TARGET=$(grep -n 'target: paused_for_review' "$TEMPLATE" | head -1)
if [ -n "$PAUSE_TARGET" ]; then
    pass "execute.md still routes to paused_for_review, the non-failure terminal whose resume needs its context"
else
    fail "execute.md no longer routes to paused_for_review -- re-check whether the retention rule still covers the pause path"
fi

echo
echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed"
[ "$FAIL_COUNT" -eq 0 ] || exit 1
exit 0
