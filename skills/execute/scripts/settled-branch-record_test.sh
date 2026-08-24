#!/usr/bin/env bash
# settled-branch-record_test.sh — the settled-branch record, end to end
# Part of the execute skill
#
# `settled_branch_record` records the branch the run settled on, and
# `spawn_and_await` reads it back to route every child. On the adopt path that
# record is the only thing that knows the branch: the run stays on a branch that
# already has an open PR and creates nothing, so nothing downstream can
# re-derive it.
#
# This harness asserts:
#
#   the script records and round-trips byte-exact       (cases 1, 2)
#   each refusal fires, with its own exit code          (cases 3, 4, 5, 6)
#   stdout stays clean on every failure                 (case 7)
#   the state machine will not advance without a record (cases 8, 9)
#   the gate's pattern is anchored                      (case 10)
#
# **It used to run shell extracted from the template at run time**, because the
# recording lived in a directive as a block of shell and a copy pasted into this
# file would keep passing after the directive drifted. The recording is now
# `record-settled-branch.sh`, a real file that koto invokes as the state's
# `default_action`, so this harness runs that file directly. The drift the
# extraction guarded against is gone with the thing it guarded: there is one
# copy, and it is the one that ships.
#
# Usage: settled-branch-record_test.sh
#
# Exit codes:
#   0 — all cases pass, or koto is absent and the run skipped
#   1 — one or more cases failed
#
# A missing koto exits 0 with a loud SKIP rather than failing. The harness runs
# on three legs and only one of them has koto: the Linux leg of
# check-execute-scripts.yml installs it through the project tool manifest, so the
# assertions genuinely run there; the macOS bash-3.2 floor leg has no koto and
# exists to check portability of the shell itself; and a developer's machine has
# koto. Failing on absence would red the floor leg for a reason that has nothing
# to do with what that leg checks.

set -uo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
TEMPLATE="$SCRIPT_DIR/../koto-templates/execute.md"
RECORDER="$SCRIPT_DIR/record-settled-branch.sh"
PLUGIN_ROOT=$(cd "$SCRIPT_DIR/../../.." && pwd)

PASS_COUNT=0
FAIL_COUNT=0

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

pass() { echo -e "${GREEN}PASS${NC}: $*"; PASS_COUNT=$((PASS_COUNT + 1)); }
fail() { echo -e "${RED}FAIL${NC}: $*"; FAIL_COUNT=$((FAIL_COUNT + 1)); }

command -v koto >/dev/null 2>&1 || { echo "SKIP: koto not on PATH -- no case ran"; exit 0; }
command -v git  >/dev/null 2>&1 || { echo "SKIP: git not on PATH -- no case ran"; exit 0; }
[ -f "$TEMPLATE" ] || { echo "FAIL: template not found at $TEMPLATE" >&2; exit 1; }
[ -x "$RECORDER" ] || { echo "FAIL: recorder not executable at $RECORDER" >&2; exit 1; }

WORKDIR=$(mktemp -d)
cleanup() {
    [ -n "${LOCKED_CTX:-}" ] && [ -d "${LOCKED_CTX:-}" ] && chmod u+w "$LOCKED_CTX" 2>/dev/null
    [ -n "${WORKDIR:-}" ] && rm -rf "$WORKDIR"
    return 0
}
trap cleanup EXIT

# koto resolves its session store through the home directory, so pointing HOME at
# the temp tree keeps every session this harness creates out of the developer's
# real ~/.koto.
export HOME="$WORKDIR/home"
mkdir -p "$HOME"

ADOPT_BRANCH="docs/settled-branch-record"

make_repo() {
    mkdir -p "$1"
    (
        cd "$1" || exit 1
        git init -q .
        git config user.email t@example.com
        git config user.name t
        git commit -q --allow-empty -m init
        git checkout -q -b "$2"
    ) >/dev/null 2>&1
}

REPO="$WORKDIR/repo"
make_repo "$REPO" "$ADOPT_BRANCH"

# koto validates every --var value against ^[a-zA-Z0-9._/:@ \-]*$ and refuses
# anything else at init. A checkout path is not guaranteed to be inside that
# set -- a `+` in a directory name is legal on disk and is not in the pattern --
# so the harness reaches the plugin root through an allowlist-clean symlink in
# its own temp tree rather than by its real path. A canonical install under
# ~/.claude/plugins/cache/ is already clean; this keeps the harness from
# depending on that being true of a developer's checkout.
case "$PLUGIN_ROOT" in
    *[!a-zA-Z0-9._/:@\ -]*)
        ln -s "$PLUGIN_ROOT" "$WORKDIR/plugin"
        PLUGIN_ROOT="$WORKDIR/plugin"
        echo "  note: plugin root reached through $PLUGIN_ROOT (real path is outside koto's --var allowlist)"
        ;;
esac

# koto binds a session to the directory `koto init` ran in and refuses to tick
# from anywhere else, so every session here is opened from inside its fixture
# repo. That is also what makes the state's action see the right branch.
#
# The session is named `execute-<slug>` and PLAN_SLUG is that same slug, because
# the state's action rebuilds the session name as `execute-{{PLAN_SLUG}}` --
# koto does not substitute {{SESSION_NAME}} inside a default_action command. A
# harness that named its sessions freely would test a session the action never
# writes to, which is exactly the failure that finding produced.
new_session() {
    (cd "${2:-$REPO}" && koto init "execute-$1" --template "$TEMPLATE" \
        --var PLAN_DOC="docs/plans/PLAN-$1.md" \
        --var PLAN_SLUG="$1" \
        --var PLUGIN_ROOT="$PLUGIN_ROOT" \
        --var PAUSE_BEFORE_FINALIZE=false >/dev/null 2>&1)
}

NEXT_RESPONSE=""
NEXT_STATE=""
submit() {
    NEXT_RESPONSE=$(cd "${3:-$REPO}" && koto next "$1" --with-data "$2" 2>/dev/null)
    NEXT_STATE=$(printf '%s' "$NEXT_RESPONSE" | sed -n 's/.*"state":"\([^"]*\)".*/\1/p')
}

# --- Case 1 — the round trip, on an adopt-path branch -------------------------
#
# The branch is deliberately docs/<topic> and not impl/<slug>: an implementation
# that fell through to the old `|| impl/$PLAN_SLUG` fallback would produce
# impl/settled-branch-record here and fail the comparison. A fixture named
# impl/<slug> would pass against the very defect this tests.

new_session round-trip
out=$(cd "$REPO" && "$RECORDER" round-trip 2>/dev/null)
rc=$?
stored=$(koto context get round-trip settled_branch 2>/dev/null)

echo "  recorded:  [$ADOPT_BRANCH]"
echo "  stored:    [$stored]"
echo "  on stdout: [$out]"
if [ "$rc" -eq 0 ] && [ "$stored" = "$ADOPT_BRANCH" ] && [ "$out" = "$ADOPT_BRANCH" ]; then
    pass "adopt-path round trip: recorded, stored, and printed for capture"
else
    fail "adopt-path round trip: stored [$stored], printed [$out] (exit $rc)"
fi

# The stored bytes must be exactly the branch name. A trailing newline -- what
# `echo` instead of `printf '%s'` would leave -- makes the value a different
# branch and also fails the gate's anchored pattern. The same holds for stdout,
# which koto trims but whose allowlist forbids the newline outright.
stored_len=$(koto context get round-trip settled_branch 2>/dev/null | wc -c | tr -d ' ')
if [ "$stored_len" = "${#ADOPT_BRANCH}" ]; then
    pass "stored value is exactly ${#ADOPT_BRANCH} bytes: no trailing newline"
else
    fail "stored value is $stored_len bytes, expected ${#ADOPT_BRANCH}"
fi

# --- Case 2 — idempotence -----------------------------------------------------
#
# The action re-runs on every entry to the state without evidence, including
# each gate-blocked retry, so a second run must be harmless.

(cd "$REPO" && "$RECORDER" round-trip >/dev/null 2>&1)
rc=$?
again=$(koto context get round-trip settled_branch 2>/dev/null)
keys=$(koto context list round-trip 2>/dev/null)
if [ "$rc" -eq 0 ] && [ "$again" = "$ADOPT_BRANCH" ]; then
    pass "re-running the recorder is idempotent (exit 0, same value)"
else
    fail "re-run should be idempotent; exit $rc, value [$again]"
fi
if [ "$(printf '%s' "$keys" | grep -c 'settled_branch')" -eq 1 ]; then
    pass "one settled_branch key after two writes"
else
    fail "expected exactly one settled_branch key, got: $keys"
fi

# --- Case 3 — a detached HEAD is refused (64) ---------------------------------

DETACHED="$WORKDIR/detached"
make_repo "$DETACHED" 'some/branch'
(cd "$DETACHED" && git checkout -q --detach) >/dev/null 2>&1
new_session detached-probe "$DETACHED"
err=$(cd "$DETACHED" && "$RECORDER" detached-probe 2>&1 >/dev/null)
rc=$?
if [ "$rc" -eq 64 ] && printf '%s' "$err" | grep -q 'HEAD is detached'; then
    pass "detached HEAD refused with exit 64 and a diagnostic naming it"
else
    fail "detached HEAD should exit 64; got $rc, stderr [$err]"
fi

# --- Case 4 — an unsafe branch name is refused (65) ---------------------------
#
# `br@nch` is a legal git ref and outside the safe charset, so it exercises the
# guard rather than git's own ref validation.

BADREPO="$WORKDIR/badrepo"
make_repo "$BADREPO" 'br@nch'
new_session guard-probe "$BADREPO"
err=$(cd "$BADREPO" && "$RECORDER" guard-probe 2>&1 >/dev/null)
rc=$?
if [ "$rc" -eq 65 ] && printf '%s' "$err" | grep -q 'refusing branch name'; then
    pass "unsafe branch name refused with exit 65, before it is stored"
else
    fail "unsafe branch name should exit 65; got $rc, stderr [$err]"
fi
if koto context exists guard-probe settled_branch >/dev/null 2>&1; then
    fail "unsafe branch name reached the store"
else
    pass "unsafe branch name never reached the store"
fi

# --- Case 5 — the default branch is refused (66) ------------------------------
#
# This is the case the old recording block could not catch. `main` is a
# perfectly well-formed branch name: the anchored pattern accepts it and a
# read-back confirms it, and every child then commits to main. The directive
# handled it by telling the agent to run the block LAST. A script can refuse it.

MAINREPO="$WORKDIR/mainrepo"
make_repo "$MAINREPO" 'main'
new_session default-probe "$MAINREPO"
err=$(cd "$MAINREPO" && "$RECORDER" default-probe 2>&1 >/dev/null)
rc=$?
if [ "$rc" -eq 66 ] && printf '%s' "$err" | grep -q 'refusing to record the default branch'; then
    pass "the default branch is refused with exit 66 -- the case a pattern cannot catch"
else
    fail "default branch should exit 66; got $rc, stderr [$err]"
fi
if koto context exists default-probe settled_branch >/dev/null 2>&1; then
    fail "the default branch reached the store"
else
    pass "the default branch never reached the store"
fi

# --- Case 6 — a missing session argument is refused (67) ----------------------

err=$(cd "$REPO" && "$RECORDER" 2>&1 >/dev/null)
rc=$?
if [ "$rc" -eq 67 ] && printf '%s' "$err" | grep -q 'no koto session name given'; then
    pass "missing session argument refused with exit 67"
else
    fail "missing session argument should exit 67; got $rc, stderr [$err]"
fi

# --- Case 7 — stdout stays clean on every failure -----------------------------
#
# stdout is the capture stream: koto delivers it under SETTLED_BRANCH and
# rejects a value outside its allowlist. A diagnostic printed there would either
# be captured as a branch name or fail the capture with a confusing error, so
# every refusal writes to stderr and prints nothing. koto delivers both streams
# to the agent on an action failure, so nothing is lost by that choice.

clean=1
for probe in "$DETACHED:detached-probe" "$BADREPO:guard-probe" "$MAINREPO:default-probe"; do
    dir=${probe%%:*}; sess=${probe##*:}
    o=$(cd "$dir" && "$RECORDER" "$sess" 2>/dev/null)
    [ -z "$o" ] || { clean=0; fail "refusal in $dir printed to stdout: [$o]"; }
done
[ "$clean" -eq 1 ] && pass "every refusal keeps stdout empty, so the capture stream stays clean"

# --- Case 8 — one tick records and advances, with no evidence -----------------
#
# The happy path the conversion exists for: entering the state runs the action,
# the gate reads the value back through koto's own evaluator, and the run
# advances without the agent submitting anything for the record.

new_session happy-path
submit execute-happy-path '{"status":"override"}'
if [ "$NEXT_STATE" = "worktree_discipline_check" ]; then
    pass "one submission at orchestrator_setup lands at worktree_discipline_check"
else
    fail "expected worktree_discipline_check, got [$NEXT_STATE]"
fi
recorded=$(koto context get execute-happy-path settled_branch 2>/dev/null)
if [ "$recorded" = "$ADOPT_BRANCH" ]; then
    pass "the branch was recorded by the action, with no evidence submitted for it"
else
    fail "expected [$ADOPT_BRANCH] recorded by the action, got [$recorded]"
fi

# --- Case 9 — the state holds when the record cannot be made ------------------
#
# This is the case the whole design turns on. With no recorded branch the run
# must NOT reach spawn_and_await, which would otherwise dispatch every child
# against a branch the adopt path never created.

new_session held-probe "$BADREPO"
submit execute-held-probe '{"status":"override"}' "$BADREPO"
if [ "$NEXT_STATE" = "settled_branch_record" ]; then
    pass "an unrecordable branch holds the run at settled_branch_record"
else
    fail "expected to hold at settled_branch_record, got [$NEXT_STATE]"
fi
if printf '%s' "$NEXT_RESPONSE" | grep -q '"__action__"'; then
    pass "the blocked response names the action as the failing condition"
else
    fail "the blocked response should carry the __action__ condition; got: $(printf '%s' "$NEXT_RESPONSE" | cut -c1-200)"
fi
if printf '%s' "$NEXT_RESPONSE" | grep -q 'refusing branch name'; then
    pass "the script's own diagnostic reaches the agent on the failure path"
else
    fail "the action's stderr should reach the agent; got: $(printf '%s' "$NEXT_RESPONSE" | cut -c1-300)"
fi

# The failure exit must stay reachable when the record is what is broken.
submit execute-held-probe '{"status":"blocked","detail":"probe"}' "$BADREPO"
if [ "$NEXT_STATE" = "done_blocked" ]; then
    pass "status blocked reaches done_blocked even with the record missing"
else
    fail "expected done_blocked, got [$NEXT_STATE]"
fi

# --- Case 10 — the gate's pattern is anchored ---------------------------------
#
# context-matches evaluates Regex::is_match, a substring test. Unanchored, the
# pattern would accept "main; rm -rf /" because "main" matches. The value is
# written directly, bypassing the script's own guard, because the point is what
# the gate does with what comes OUT of the store -- a separate trust boundary.
#
# The submission carries `blocked`, which is the state's only evidence value.
# With the gate false, the blocked edge is the one that can fire; a passing gate
# would send it to worktree_discipline_check instead, which is the failure this
# case detects.

new_session gate-metachar
printf '%s' 'main; rm -rf /' | koto context add execute-gate-metachar settled_branch >/dev/null 2>&1
submit execute-gate-metachar '{"status":"blocked","detail":"probe"}'
if [ "$NEXT_STATE" = "done_blocked" ]; then
    pass "a value with a shell metacharacter fails the gate (pattern is anchored)"
else
    fail "a metacharacter value should fail the gate and route to done_blocked; got [$NEXT_STATE]"
fi

# --- Case 11 — the recorded branch is what children are dispatched to ---------
#
# The coverage `scripts/settled-branch-read_test.sh` used to provide. That
# harness extracted spawn_and_await's read block and ran it against a koto shim,
# because the read was twenty-five lines of exit-status branching over
# `koto context get` with an `|| impl/<slug>` fallback. There is no read any
# more: the value arrives as a capture the gate has already verified, so what is
# left to check is that the injection uses it.
#
# The block is extracted from the shipped template rather than copied, for the
# same reason the old harness extracted its read: a copy keeps passing after the
# directive drifts.

TICK1=$(awk '
    /^TMP=\$\(mktemp\)$/ { inb = 1 }
    inb { print }
    inb && /^rm -f "\$TMP"$/ { exit }
' "$TEMPLATE")

if [ -z "$TICK1" ]; then
    fail "could not extract spawn_and_await's tick-1 block from $TEMPLATE"
else
    INJECTED=$(printf '%s\n' "$TICK1" \
        | sed -e "s|{{SETTLED_BRANCH}}|$ADOPT_BRANCH|g" \
              -e 's|^TASKS=.*|TASKS=$(printf "%s" "[{\\"name\\":\\"i1\\",\\"vars\\":{}}]")|' \
              -e 's|^koto next .*|cat "$TMP"|' \
        | bash 2>/dev/null | jq -r '.tasks[0].vars.SHARED_BRANCH' 2>/dev/null)
    if [ "$INJECTED" = "$ADOPT_BRANCH" ]; then
        pass "tick 1 injects the captured branch into each child's SHARED_BRANCH"
    else
        fail "tick 1 should inject [$ADOPT_BRANCH] as SHARED_BRANCH, got [$INJECTED]"
    fi
    # An assignment, not the string: the block's own comment explains why the
    # fallback is gone, and a bare `grep impl/` matches that explanation.
    if printf '%s' "$TICK1" | grep -qE '^[^#]*SETTLED_BRANCH=.*impl/'; then
        fail "tick 1 still assigns an impl/<slug> fallback; the gate is what makes the value present"
    else
        pass "tick 1 assigns no impl/<slug> fallback -- the gate guarantees the value"
    fi
fi

# --- summary ------------------------------------------------------------------

echo
echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed"
[ "$FAIL_COUNT" -eq 0 ] || exit 1
exit 0
