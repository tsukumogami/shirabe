#!/usr/bin/env bash
# settled-branch-record_test.sh — the settled-branch record, end to end
# Part of the execute skill
#
# orchestrator_setup records the branch the run settled on, and spawn_and_await
# reads it back to route every child. On the adopt path that record is the only
# thing that knows the branch: the run stays on a branch that already has an open
# PR and creates nothing, so nothing downstream can re-derive it. The record used
# to be written with `koto context set`, a subcommand koto does not have, and the
# failure was invisible because koto's migration noise makes `2>/dev/null` the
# routine operator reflex.
#
# This harness asserts the repair on both halves:
#
#   the write works and round-trips byte-exact  (cases 1, 2)
#   the state machine will not advance without it (cases 3, 4, 5)
#   a failure to record announces itself          (cases 6, 7)
#
# It runs the SHIPPED TEXT rather than a copy: both the recording block and the
# read-back idiom are extracted from skills/execute/koto-templates/execute.md at
# run time, so an edit to the directive that breaks either one fails here. A copy
# of the block pasted into this file would keep passing after the directive
# drifted, which is the failure this whole issue is about.
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
# to do with what that leg checks. The Linux leg's explicit install step is what
# guarantees a silent skip cannot hide a koto that vanished from CI -- the install
# fails first.

set -uo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
TEMPLATE="$SCRIPT_DIR/../koto-templates/execute.md"

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

WORKDIR=$(mktemp -d)
cleanup() {
    # Case 7 leaves a directory read-only; restore it so rm can finish.
    [ -n "${LOCKED_CTX:-}" ] && [ -d "${LOCKED_CTX:-}" ] && chmod u+w "$LOCKED_CTX" 2>/dev/null
    [ -n "${WORKDIR:-}" ] && rm -rf "$WORKDIR"
    return 0
}
trap cleanup EXIT

# koto resolves its session store through the home directory, so pointing HOME at
# the temp tree keeps every session this harness creates out of the developer's
# real ~/.koto. Without it a failing run leaves sessions behind that the next run
# then finds.
export HOME="$WORKDIR/home"
mkdir -p "$HOME"

ADOPT_BRANCH="docs/settled-branch-record"

# --- extract the shipped text -------------------------------------------------

# Print the first ```bash fenced block in $1 that contains the substring $2.
extract_block() {
    awk -v marker="$2" '
        /^```bash$/  { inblk = 1; buf = ""; next }
        /^```$/ && inblk {
            if (index(buf, marker) > 0) { printf "%s", buf; exit }
            inblk = 0; buf = ""; next
        }
        inblk { buf = buf $0 "\n" }
    ' "$1"
}

RECORD_BLOCK=$(extract_block "$TEMPLATE" "koto context add")
if [ -z "$RECORD_BLOCK" ]; then
    fail "could not extract the recording block from $TEMPLATE (no bash block contains 'koto context add')"
    echo; echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed"; exit 1
fi

# The read-back idiom as spawn_and_await runs it: the assignment plus the case
# guard on the three lines that follow it.
READ_IDIOM=$(grep -A3 -m1 'SETTLED_BRANCH=\$(koto context get' "$TEMPLATE")
if [ -z "$READ_IDIOM" ]; then
    fail "could not extract the read-back idiom from $TEMPLATE"
    echo; echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed"; exit 1
fi

# Render a block for execution: substitute koto's {{SESSION_NAME}} runtime
# variable with the session this case uses. The trailing newline matters --
# without it the next line appended to the block joins onto `esac`.
render() { printf '%s\n' "$1" | sed "s|{{SESSION_NAME}}|$2|g"; }

# A git repo standing on an adopt-path branch, so `git rev-parse --abbrev-ref
# HEAD` inside the recording block returns what it would on a real adopt run.
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

new_session() {
    koto init "$1" --template "$TEMPLATE" \
        --var PLAN_DOC=docs/plans/PLAN-settled-branch-record.md \
        --var PLAN_SLUG=settled-branch-record \
        --var PAUSE_BEFORE_FINALIZE=false >/dev/null 2>&1
}

# `koto next` reports the resulting state in its JSON response, and keeps
# reporting it after a terminal transition -- `koto status` does not (it answers
# "workflow not found" once a workflow is terminal), so the submission response is
# the surface to read.
NEXT_RESPONSE=""
NEXT_STATE=""
submit() {
    # Sets the globals rather than printing them. A `state=$(submit ...)` would
    # run this in a subshell, so NEXT_RESPONSE would not survive the call and the
    # gate-name assertion below would read an empty string.
    NEXT_RESPONSE=$(koto next "$1" --with-data "$2" 2>/dev/null)
    NEXT_STATE=$(printf '%s' "$NEXT_RESPONSE" | sed -n 's/.*"state":"\([^"]*\)".*/\1/p')
}

# --- Case 1 — the round trip, on an adopt-path branch -------------------------
#
# The branch is deliberately docs/<topic> and not impl/<slug>: an implementation
# that silently fell through to the `|| impl/$PLAN_SLUG` fallback would produce
# impl/settled-branch-record here and fail the comparison. A fixture named
# impl/<slug> would pass against the very defect this tests.

new_session round-trip
out=$(cd "$REPO" && render "$RECORD_BLOCK" round-trip | bash 2>/dev/null)
rc=$?
readback=$(cd "$REPO" && { render "$READ_IDIOM" round-trip; echo 'printf "%s" "$SETTLED_BRANCH"'; } \
    | PLAN_SLUG=settled-branch-record bash 2>/dev/null)

echo "  recorded:                   [$ADOPT_BRANCH]"
echo "  read back as SHARED_BRANCH: [$readback]"
if [ "$rc" -eq 0 ] && [ "$readback" = "$ADOPT_BRANCH" ]; then
    pass "adopt-path round trip: the branch recorded is the branch children are dispatched to"
else
    fail "adopt-path round trip: recorded [$ADOPT_BRANCH], read back [$readback] (block exit $rc)"
fi

# The stored bytes must be exactly the branch name. A trailing newline -- what
# `echo` instead of `printf '%s'` would leave -- makes the value a different
# branch and also fails the gate's anchored pattern.
stored_len=$(koto context get round-trip settled_branch 2>/dev/null | wc -c | tr -d ' ')
if [ "$stored_len" = "${#ADOPT_BRANCH}" ]; then
    pass "stored value is exactly ${#ADOPT_BRANCH} bytes: no trailing newline"
else
    fail "stored value is $stored_len bytes, expected ${#ADOPT_BRANCH} (a trailing newline would add one)"
fi

# --- Case 2 — idempotence -----------------------------------------------------
#
# orchestrator_setup is documented as safe to re-run after a crash, so the
# recording step must not fail on a key that is already there.

(cd "$REPO" && render "$RECORD_BLOCK" round-trip | bash >/dev/null 2>&1)
rc=$?
again=$(koto context get round-trip settled_branch 2>/dev/null)
keys=$(koto context list round-trip 2>/dev/null)
if [ "$rc" -eq 0 ] && [ "$again" = "$ADOPT_BRANCH" ]; then
    pass "re-running the recording block is idempotent (exit 0, same value)"
else
    fail "re-run should be idempotent; exit $rc, value [$again]"
fi
if [ "$(printf '%s' "$keys" | grep -c 'settled_branch')" -eq 1 ]; then
    pass "one settled_branch key after two writes"
else
    fail "expected exactly one settled_branch key, got: $keys"
fi

# --- Case 3 — the gate holds the state when the record is missing -------------
#
# This is the case the whole design turns on. With no recorded branch, an agent
# submitting `override` must NOT reach spawn_and_await, because spawn_and_await's
# fallback would hand every child impl/<slug> -- a branch the adopt path never
# created.

new_session gate-absent
submit gate-absent '{"status":"override"}'; state="$NEXT_STATE"
if [ "$state" = "orchestrator_setup" ]; then
    pass "key absent + status override: state holds at orchestrator_setup (did not advance)"
else
    fail "key absent + status override: expected to hold at orchestrator_setup, got [$state]"
fi
# koto names the failed gate in the submission response, so an operator is not
# left guessing which condition held the state.
if printf '%s' "$NEXT_RESPONSE" | grep -q '"name":"settled_branch_recorded"'; then
    pass "the blocked submission names settled_branch_recorded as the failing condition"
else
    fail "the blocked submission should name the failing gate; got: $(printf '%s' "$NEXT_RESPONSE" | cut -c1-200)"
fi

# The failure exit must stay reachable when the store is what is broken.
submit gate-absent '{"status":"blocked","detail":"probe"}'; state="$NEXT_STATE"
if [ "$state" = "done_blocked" ]; then
    pass "key absent + status blocked: done_blocked stays reachable (no gate on that edge)"
else
    fail "key absent + status blocked: expected done_blocked, got [$state]"
fi

# --- Case 4 — the gate releases when the record is present --------------------

new_session gate-present
printf '%s' "$ADOPT_BRANCH" | koto context add gate-present settled_branch >/dev/null 2>&1
submit gate-present '{"status":"override"}'; state="$NEXT_STATE"
if [ "$state" = "worktree_discipline_check" ]; then
    pass "key present + status override: advances to worktree_discipline_check"
else
    fail "key present + status override: expected worktree_discipline_check, got [$state]"
fi

# --- Case 5 — the pattern is anchored -----------------------------------------
#
# context-matches evaluates Regex::is_match, a substring test. Unanchored, the
# pattern would accept "main; rm -rf /" because "main" matches. This case fails
# if a later edit drops either anchor, which is the only thing standing between
# the gate and a formality. The value is written directly, bypassing the
# recording block's own guard, because the point is what the gate does with what
# comes OUT of the store -- the store is a separate trust boundary.

new_session gate-metachar
printf '%s' 'main; rm -rf /' | koto context add gate-metachar settled_branch >/dev/null 2>&1
submit gate-metachar '{"status":"override"}'; state="$NEXT_STATE"
if [ "$state" = "orchestrator_setup" ]; then
    pass "value with a shell metacharacter: gate rejects it, state holds (pattern is anchored)"
else
    fail "value with a shell metacharacter should hold the state; got [$state]"
fi

# --- Case 6 — the write-side guard rejects an unsafe branch name --------------
#
# `br@nch` is a legal git ref and outside the safe charset, so it exercises the
# guard rather than git's own ref validation.

BADREPO="$WORKDIR/badrepo"
make_repo "$BADREPO" 'br@nch'
new_session guard-probe
out=$(cd "$BADREPO" && render "$RECORD_BLOCK" guard-probe | bash 2>/dev/null)
rc=$?
if [ "$rc" -ne 0 ] && printf '%s' "$out" | grep -q 'refusing unsafe settled branch'; then
    pass "unsafe branch name is refused before it is stored, and the refusal is on stdout"
else
    fail "unsafe branch name should be refused on stdout with a non-zero exit; exit $rc, output [$out]"
fi
if koto context exists guard-probe settled_branch >/dev/null 2>&1; then
    fail "unsafe branch name reached the store"
else
    pass "unsafe branch name never reached the store"
fi

# --- Case 7 — a failed record announces itself through 2>/dev/null ------------
#
# Redirecting koto's stderr is the routine operator response to its migration
# noise, and it is what hid the original defect. The diagnostic must survive it,
# which is why it goes to stdout.
#
# The failure is injected by making the session's context directory unwritable,
# which is the closest cheap analogue of the real cause (an unwritable store).
# Pointing the block at a nonexistent session does NOT work: `koto context add`
# creates the session directory on demand and succeeds.

if [ "$(id -u)" = "0" ]; then
    echo "SKIP: case 7 needs a non-root user (root ignores the write bit)"
else
    new_session fail-probe
    printf 'seed' | koto context add fail-probe otherkey >/dev/null 2>&1
    LOCKED_CTX="$HOME/.koto/sessions/fail-probe/ctx"
    chmod a-w "$LOCKED_CTX"
    out=$(cd "$REPO" && render "$RECORD_BLOCK" fail-probe | bash 2>/dev/null)
    rc=$?
    chmod u+w "$LOCKED_CTX"
    if [ "$rc" -ne 0 ] && printf '%s' "$out" | grep -q 'settled_branch NOT recorded'; then
        pass "a failed record is visible on stdout with stderr redirected, and exits non-zero"
        echo "  diagnostic: $(printf '%s' "$out" | grep 'settled_branch NOT recorded' | cut -c1-110)"
    else
        fail "a failed record must announce itself on stdout and exit non-zero; exit $rc, output [$out]"
    fi
    if printf '%s' "$out" | grep -q 'do NOT submit completed or override'; then
        pass "the diagnostic tells the agent which status to submit"
    else
        fail "the diagnostic should name the status to submit; got [$out]"
    fi
fi

# --- summary ------------------------------------------------------------------

echo
echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed"
[ "$FAIL_COUNT" -eq 0 ] || exit 1
exit 0
