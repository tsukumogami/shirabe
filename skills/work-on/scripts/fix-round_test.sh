#!/usr/bin/env bash
# fix-round_test.sh -- a fix round taken after a child reached done (#1322).
#
# A child of a stand-in parent is driven to done on a scratch git branch, as a
# coordinated child is once its pull request is open. Then:
#
#   - `koto rewind` from done lands on pr_creation and the next tick returns
#     to done: rewinding doesn't reopen a round, which is why the route exists;
#   - fix-round.sh refuses a child that isn't at done, and one whose shared
#     branch isn't the branch HEAD is on;
#   - from done it starts <child>-fix-1 from the shipped work-on.md, under the
#     same parent and with the child's variables (not its review level, and
#     with a declared partial delivery), and records the round in both
#     sessions;
#   - the round's impl_base is the head the child left, so its changed paths
#     cover the fix commit only;
#   - review-round.sh records a round at the fix head both in the child at done
#     and in the round;
#   - --fresh writes fresh: true into the round's fix_round.json;
#   - the route can't loop: a second round is refused while the first is open,
#     a round started from a round counts against the original, and a fourth
#     round is refused;
#   - a round inherits the verdict ledger of the run it follows (the last
#     round, else the child) when every commit the ledger recorded is an
#     ancestor of the round's base, and inherits nothing when one isn't or
#     with --fresh.
#
# The child is a stand-in template with the variables a coordinated child
# carries and a pr_creation that goes to done, not the shipped work-on.md
# walked from entry: that walk is a dozen states of evidence, and what this
# file pins is what happens after done. Each round starts from the shipped
# template, which koto compiles, so a variable the round carries that the
# template refuses fails here.
#
# Usage: fix-round_test.sh
# Exit codes: 0 all pass, 1 any failed, 0 with a skip notice when koto, jq or
# git is absent.

set -uo pipefail
. "$(dirname "$0")/../../../scripts/lib/koto-test-guard.sh" || exit 1

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIR/../../.." && pwd)
FIX_ROUND="$SCRIPT_DIR/fix-round.sh"
CHANGED_PATHS="$SCRIPT_DIR/record-changed-paths.sh"
REVIEW_ROUND="$REPO_ROOT/skills/coordinate/scripts/review-round.sh"

PASS_COUNT=0
FAIL_COUNT=0
GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[0;33m'; NC='\033[0m'
pass() { echo -e "${GREEN}PASS${NC}: $*"; PASS_COUNT=$((PASS_COUNT+1)); }
fail() { echo -e "${RED}FAIL${NC}: $*"; FAIL_COUNT=$((FAIL_COUNT+1)); }
skip() { echo -e "${YELLOW}SKIP${NC}: $*"; }

OUT=$(bash "$FIX_ROUND" start 2>/dev/null); RC=$?
if [[ $RC -eq 64 && -z "$OUT" ]]; then
    pass "a call without --from is a usage error"
else
    fail "a call without --from was not refused as usage (rc=$RC, out=[$OUT])"
fi
OUT=$(bash "$FIX_ROUND" start --from x --stale 2>/dev/null); RC=$?
if [[ $RC -eq 64 && -z "$OUT" ]]; then
    pass "a fourth argument other than --fresh is a usage error"
else
    fail "start --from x --stale was not refused as usage (rc=$RC, out=[$OUT])"
fi

for tool in koto jq git; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        skip "$tool not on PATH; a fix round can't be driven without it"
        [[ $FAIL_COUNT -eq 0 ]]; exit $?
    fi
done

W="$KOTO_TEST_GUARD_DIR/work"
REPO="$W/repo"
mkdir -p "$REPO"
git -C "$REPO" init -q -b main
git -C "$REPO" config user.email t@example.com
git -C "$REPO" config user.name t
echo base > "$REPO/a.txt"
git -C "$REPO" add a.txt
git -C "$REPO" commit -q -m "chore: base"
git -C "$REPO" checkout -q -b feature
echo work > "$REPO/b.txt"
git -C "$REPO" add b.txt
git -C "$REPO" commit -q -m "feat: the child's work"
DONE_HEAD=$(git -C "$REPO" rev-parse HEAD)

cat > "$W/parent.md" <<'EOF'
---
name: parent
version: "1.0"
initial_state: wait
states:
  wait:
    accepts:
      go:
        type: enum
        values: [yes]
        required: true
    transitions:
      - target: fin
        when:
          go: yes
  fin:
    terminal: true
---
## wait

Wait.

## fin

Done.
EOF

cat > "$W/child.md" <<'EOF'
---
name: child
version: "1.0"
initial_state: pr_creation
variables:
  ISSUE_NUMBER:
    required: false
  ARTIFACT_PREFIX:
    required: true
  SHARED_BRANCH:
    required: false
  PLUGIN_ROOT:
    required: true
  REVIEW_LEVEL:
    required: false
  DELIVERY:
    required: false
  DELIVERY_REASON:
    required: false
  PLAN_DOC:
    required: false
states:
  pr_creation:
    accepts:
      pr_status:
        type: enum
        values: [shared]
        required: true
    transitions:
      - target: done
        when:
          pr_status: shared
  done:
    terminal: true
---
## pr_creation

Submit shared.

## done

Done.
EOF

# Every koto and git call below runs in the scratch repository, the way an
# agent runs fix-round.sh from the branch it is fixing.
in_repo() { (cd "$REPO" && "$@"); }
state_of() { koto status "$1" | jq -r .current_state; }
tick() { printf '%s\n' "$2" > "$W/ev.json"; koto next "$1" --with-data @"$W/ev.json" --no-cleanup >/dev/null; }

koto init par --template "$W/parent.md" >/dev/null || { fail "could not init the parent"; exit 1; }
koto init par.kid --parent par --template "$W/child.md" \
    --var ISSUE_NUMBER=1322 --var ARTIFACT_PREFIX=issue_1322 --var SHARED_BRANCH=feature \
    --var PLUGIN_ROOT=/nowhere --var REVIEW_LEVEL=full \
    --var DELIVERY=partial --var "DELIVERY_REASON=step 1 of 2" >/dev/null \
    || { fail "could not init the child"; exit 1; }

# --- not at done ---------------------------------------------------------------
OUT=$(in_repo bash "$FIX_ROUND" start --from par.kid 2>/dev/null); RC=$?
if [[ $RC -eq 1 && "$OUT" == "refused=not-done" ]] && ! koto context exists par.kid fix_rounds.jsonl; then
    pass "a child that hasn't reached done gets no fix round"
else
    fail "a child at pr_creation was not refused as not-done (rc=$RC, out=[$OUT])"
fi

tick par.kid '{"pr_status":"shared"}'
[[ $(state_of par.kid) == done ]] || { fail "the child did not reach done"; exit 1; }

# --- rewind doesn't reopen a round ----------------------------------------------
koto rewind par.kid >/dev/null
AFTER_REWIND=$(state_of par.kid)
tick par.kid '{"pr_status":"shared"}'
if [[ $AFTER_REWIND == pr_creation && $(state_of par.kid) == done ]]; then
    pass "rewind from done reaches pr_creation only, and the next tick is back at done"
else
    fail "rewind from done went to [$AFTER_REWIND], then [$(state_of par.kid)]"
fi

# --- not on the shared branch ----------------------------------------------------
git -C "$REPO" checkout -q -b elsewhere
OUT=$(in_repo bash "$FIX_ROUND" start --from par.kid 2>/dev/null); RC=$?
git -C "$REPO" checkout -q feature
if [[ $RC -eq 1 && "$OUT" == "refused=wrong-branch" ]] && ! koto context exists par.kid fix_rounds.jsonl; then
    pass "a round isn't started from a branch other than the child's shared branch"
else
    fail "a round from another branch was not refused as wrong-branch (rc=$RC, out=[$OUT])"
fi

# --- the first round -------------------------------------------------------------
# The child's panels judged the head it left, as panel-scope.sh records them.
# ledger_at <commit>: a ledger whose one seat judged <commit>.
ledger_at() {
    jq -nc --arg h "$1" '{rev: 1,
        seats: {"review/architect": {verdict: "pass", judged_at: $h, ac_sha: "a"}},
        findings: {}, history: [{panel: "review", round: 1, head: $h, rev: 1}]}'
}
ledger_at "$DONE_HEAD" | koto context add par.kid verdict_ledger.json >/dev/null
# The criteria review-level.sh stored from the child's context.md.
printf 'criteria\n' | koto context add par.kid review_level_criteria.txt >/dev/null
OFF_BRANCH=$(git -C "$REPO" commit-tree "HEAD^{tree}" -m "not on the branch")

OUT=$(in_repo bash "$FIX_ROUND" start --from par.kid); RC=$?
if [[ $RC -eq 0 && "$OUT" == $'session=par.kid-fix-1\nround=1\ninherited=par.kid' ]]; then
    pass "a child at done starts fix round 1, inheriting its ledger"
else
    fail "fix round 1 did not start (rc=$RC, out=[$OUT])"
fi
CRIT_SHA=$(printf 'criteria\n' | git hash-object --stdin)
if koto context get par.kid-fix-1 verdict_ledger.json 2>/dev/null | jq -e --arg h "$DONE_HEAD" --arg c "$CRIT_SHA" '
        .seats["review/architect"].judged_at == $h and .rev == 1
        and .inherited == {from: "par.kid", base: $h, criteria_sha: $c}' >/dev/null; then
    pass "the inherited ledger keeps the child's verdicts and names the child, the base and the criteria"
else
    fail "the round's ledger is $(koto context get par.kid-fix-1 verdict_ledger.json 2>&1)"
fi

R1=par.kid-fix-1
PARENT=$(koto session list | jq -r --arg s "$R1" 'map(select(.id == $s))[0].parent_workflow // empty')
if [[ $PARENT == par && $(bash "$SCRIPT_DIR/session-role.sh" "$R1" 2>/dev/null) == child ]]; then
    pass "the round is a child of the same parent, so it never cascades"
else
    fail "the round's parent is [$PARENT]"
fi

LOG="$(koto session dir "$R1")/koto-$R1.state.jsonl"
VARS=$(jq -sc '[.[] | select(.type == "workflow_initialized")][0].payload.variables' "$LOG")
if jq -e --arg root "$REPO_ROOT" '.ISSUE_NUMBER == "1322" and .ARTIFACT_PREFIX == "issue_1322"
        and .SHARED_BRANCH == "feature" and .PLUGIN_ROOT == $root
        and ((.REVIEW_LEVEL // "") == "")' <<<"$VARS" >/dev/null; then
    pass "the round carries the child's variables, this plugin's root, and no review level"
else
    fail "the round's variables are $VARS"
fi

# A partial delivery (#1736) is the child's to declare at init, and a round
# keeps it: the shipped template takes both variables.
if jq -e '.DELIVERY == "partial" and .DELIVERY_REASON == "step 1 of 2"' <<<"$VARS" >/dev/null; then
    pass "the round carries the child's DELIVERY and DELIVERY_REASON"
else
    fail "the round's delivery variables are $VARS"
fi

# The log keeps the template's file name; the stand-in child has no entry state.
SRC=$(jq -rs '.[0].template_source_file // empty' "$LOG")
if [[ $SRC == work-on.md && $(state_of "$R1") == entry ]]; then
    pass "the round starts at entry of the shipped work-on template"
else
    fail "the round is at [$(state_of "$R1")] of [$SRC]"
fi

ROUND=$(koto context get "$R1" fix_round.json 2>/dev/null)
ROUNDS=$(koto context get par.kid fix_rounds.jsonl 2>/dev/null)
if jq -e --arg h "$DONE_HEAD" '.from == "par.kid" and .round == 1 and .base == $h and (has("fresh") | not)' <<<"$ROUND" >/dev/null \
   && jq -se --arg h "$DONE_HEAD" 'length == 1 and .[0].session == "par.kid-fix-1" and .[0].base == $h' <<<"$ROUNDS" >/dev/null; then
    pass "the round names the child it fixes, and the child names the round"
else
    fail "the round's record is [$ROUND], the child's [$ROUNDS]"
fi

# --- the round covers the fix commit only -----------------------------------------
# analysis's action, record-changed-paths.sh --base, run here by hand as the
# round reaches analysis; the fix is committed after it, in implementation, as
# the done directive says.
in_repo bash "$CHANGED_PATHS" --base "$R1"
echo fix > "$REPO/c.txt"
git -C "$REPO" add c.txt
git -C "$REPO" commit -q -m "fix: what review asked for"
FIX_HEAD=$(git -C "$REPO" rev-parse HEAD)
in_repo bash "$CHANGED_PATHS" --write "$R1"
CP=$(koto context get "$R1" changed_paths.txt 2>/dev/null)
if [[ "$CP" == "base: $DONE_HEAD"$'\n'"commits: 1"$'\n'"A	c.txt" ]]; then
    pass "the round's changed paths start at the head the child left: the fix commit alone"
else
    fail "the round's changed paths are [$CP]"
fi

# --- review-round.sh at the fix head ---------------------------------------------
jq -n --arg h "$FIX_HEAD" '{reviewed_head: $h, seats: [
    {seat: "architect", model: "m", run: "run-a1", verdict: "pass"},
    {seat: "maintainer", model: "m", run: "run-m1", verdict: "pass"},
    {seat: "pragmatic", model: "m", run: "run-p1", verdict: "pass"}]}' > "$W/round.json"
for s in par.kid "$R1"; do
    OUT=$(bash "$REVIEW_ROUND" record --session "$s" "$W/round.json" 2>&1); RC=$?
    if [[ $RC -eq 0 && "$OUT" == "recorded 3 seats at $FIX_HEAD" ]] \
       && [[ $(koto context get "$s" review_round.json | jq -r .reviewed_head) == "$FIX_HEAD" ]]; then
        pass "review-round.sh records the round at the fix head in $s ($(state_of "$s"))"
    else
        fail "review-round.sh in $s: rc=$RC out=[$OUT]"
    fi
done

# --- it can't loop ----------------------------------------------------------------
OUT=$(in_repo bash "$FIX_ROUND" start --from par.kid 2>/dev/null); RC=$?
if [[ $RC -eq 1 && "$OUT" == "refused=round-open" ]]; then
    pass "a second round is refused while the first is open"
else
    fail "a second round was not refused while the first was open (rc=$RC, out=[$OUT])"
fi

# entry's `skipped` mode is the shortest way to a terminal state in the shipped
# template, which is all the open-round rule asks of a finished round.
tick "$R1" '{"mode":"skipped"}'
# Round 2 follows round 1, so it reads round 1's ledger, not the child's: one
# that recorded a commit the branch doesn't hold (a rebase since) is not
# inherited, though the child's still would be.
ledger_at "$OFF_BRANCH" | koto context add "$R1" verdict_ledger.json >/dev/null
OUT=$(in_repo bash "$FIX_ROUND" start --from "$R1"); RC=$?
if [[ $RC -eq 0 && "$OUT" == $'session=par.kid-fix-2\nround=2\ninherited=none' ]]; then
    pass "a round started from a round counts against the original child"
else
    fail "a round from a round did not start par.kid-fix-2 (rc=$RC, out=[$OUT])"
fi
if ! koto context exists par.kid-fix-2 verdict_ledger.json; then
    pass "a ledger recording a commit the round's base doesn't hold is not inherited"
else
    fail "par.kid-fix-2 inherited a ledger that judged a commit off the branch"
fi
# The round's record names the run it continues: the original, never the
# round it was started from.
if koto context get par.kid-fix-2 fix_round.json 2>/dev/null | jq -e '.from == "par.kid" and .round == 2' >/dev/null; then
    pass "a round started from a round records the original run it continues"
else
    fail "par.kid-fix-2's fix_round.json does not name par.kid: $(koto context get par.kid-fix-2 fix_round.json 2>&1)"
fi

tick par.kid-fix-2 '{"mode":"skipped"}'
# --fresh inherits no ledger, even one the round could have inherited, and
# marks the round, so its verification carries nothing from the run it
# follows (run-verification.sh).
ledger_at "$FIX_HEAD" | koto context add par.kid-fix-2 verdict_ledger.json >/dev/null
OUT=$(in_repo bash "$FIX_ROUND" start --from par.kid --fresh); RC=$?
if [[ $RC -eq 0 && "$OUT" == $'session=par.kid-fix-3\nround=3\ninherited=none' ]] \
   && ! koto context exists par.kid-fix-3 verdict_ledger.json \
   && koto context get par.kid-fix-3 fix_round.json 2>/dev/null | jq -e '.fresh == true and .round == 3 and .from == "par.kid"' >/dev/null; then
    pass "--fresh inherits no ledger and writes fresh: true into the round's fix_round.json"
else
    fail "--fresh round 3: rc=$RC out=[$OUT], fix_round.json $(koto context get par.kid-fix-3 fix_round.json 2>&1)"
fi
tick par.kid-fix-3 '{"mode":"skipped"}'
OUT=$(in_repo bash "$FIX_ROUND" start --from par.kid 2>/dev/null); RC=$?
N=$(koto context get par.kid fix_rounds.jsonl | jq -s length)
if [[ $RC -eq 1 && "$OUT" == "refused=cap" && $N -eq 3 ]] \
   && ! koto status par.kid-fix-4 >/dev/null 2>&1; then
    pass "a fourth round is refused and nothing is started"
else
    fail "a fourth round was not refused (rc=$RC, out=[$OUT], rounds=$N)"
fi

# --- the PLAN's checkout moved (#2104) -------------------------------------------
# A plan-backed child of a coordinated run records PLAN_DOC as the run's plan_abs
# when the child was opened. When the coordination checkout moves, the parent's
# plan_abs is re-rooted (record-coord-setup.sh --reroot-plan), and a round started
# after that reads the PLAN where the run reads it now. The parent is opened in a
# directory of its own, as a coordinated run is, so the round reads it there.
round_var() {
    local log
    log="$(koto session dir "$1")/koto-$1.state.jsonl"
    jq -rs --arg k "$2" '[.[] | select(.type == "workflow_initialized")][0].payload.variables[$k] // ""' "$log"
}
OLD_PLAN="$W/old/docs/plans/PLAN-moved.md"
NEW_PLAN="$W/new/docs/plans/PLAN-moved.md"
mkdir -p "$W/coord" "$(dirname "$OLD_PLAN")" "$(dirname "$NEW_PLAN")"
printf -- '---\nschema: plan/v2\n---\n' > "$OLD_PLAN"
cp "$OLD_PLAN" "$NEW_PLAN"

# The child is opened under the parent, so it is bound to the parent's directory,
# then rebound to the node repository and driven to done there, as a step agent
# drives a coordinated child in the node's worktree.
open_plan_child() { # <parent> <plan_abs or empty> <child PLAN_DOC>
    local c="$W/coord"
    (cd "$c" && koto init "$1" --template "$W/parent.md" >/dev/null) \
        || { echo "could not init the parent $1" >&2; return 1; }
    if [ -n "$2" ]; then
        printf '%s' "$2" | (cd "$c" && koto context add "$1" plan_abs >/dev/null) \
            || { echo "could not record plan_abs in $1" >&2; return 1; }
    fi
    (cd "$c" && koto init "$1.kid" --parent "$1" --template "$W/child.md" \
        --var ARTIFACT_PREFIX=step-1 --var PLUGIN_ROOT=/nowhere \
        --var "PLAN_DOC=$3" >/dev/null) || { echo "could not init $1.kid" >&2; return 1; }
    (cd "$c" && koto session rebind "$1.kid" --to "$REPO" >/dev/null) \
        || { echo "could not rebind $1.kid to the node repository" >&2; return 1; }
    in_repo tick "$1.kid" '{"pr_status":"shared"}'
    [[ $(in_repo state_of "$1.kid") == done ]] || { echo "$1.kid did not reach done" >&2; return 1; }
}

# The checkout moved: the parent's plan_abs is the PLAN in the new checkout, and
# the old checkout still exists, so a round on the old path would read a PLAN the
# run has moved off.
if open_plan_child mov "$NEW_PLAN" "$OLD_PLAN"; then
    OUT=$(in_repo bash "$FIX_ROUND" start --from mov.kid 2>/dev/null); RC=$?
    GOT=$(round_var mov.kid-fix-1 PLAN_DOC 2>/dev/null)
    MOVED=$(round_var mov.kid-fix-1 PLAN_DOC_MOVED 2>/dev/null)
    if [[ $RC -eq 0 && "$GOT" == "$NEW_PLAN" && -z "$MOVED" ]]; then
        pass "after the PLAN's checkout moved, the round's PLAN_DOC is the parent's re-rooted plan_abs"
    elif [[ "$GOT" == "$OLD_PLAN" ]]; then
        fail "the new session's PLAN_DOC variable is the old path: [$GOT], plan_abs [$NEW_PLAN] (rc=$RC, out=[$OUT])"
    else
        fail "the moved round's PLAN_DOC is [$GOT] and PLAN_DOC_MOVED [$MOVED] (rc=$RC, out=[$OUT])"
    fi
else
    fail "could not open the moved plan-backed child"
fi

# The checkout never moved: plan_abs is the path the child recorded, and the round
# carries it as it does today.
if open_plan_child stay "$OLD_PLAN" "$OLD_PLAN"; then
    OUT=$(in_repo bash "$FIX_ROUND" start --from stay.kid 2>/dev/null); RC=$?
    GOT=$(round_var stay.kid-fix-1 PLAN_DOC 2>/dev/null)
    MOVED=$(round_var stay.kid-fix-1 PLAN_DOC_MOVED 2>/dev/null)
    if [[ $RC -eq 0 && "$GOT" == "$OLD_PLAN" && -z "$MOVED" ]]; then
        pass "a round for a child whose checkout never moved keeps the PLAN_DOC it recorded"
    else
        fail "the unmoved round's PLAN_DOC is [$GOT] and PLAN_DOC_MOVED [$MOVED] (rc=$RC, out=[$OUT])"
    fi
else
    fail "could not open the unmoved plan-backed child"
fi

# A parent with no plan_abs (a run that never recorded one) leaves PLAN_DOC as the
# child recorded it.
if open_plan_child noabs "" "$OLD_PLAN"; then
    OUT=$(in_repo bash "$FIX_ROUND" start --from noabs.kid 2>/dev/null); RC=$?
    GOT=$(round_var noabs.kid-fix-1 PLAN_DOC 2>/dev/null)
    if [[ $RC -eq 0 && "$GOT" == "$OLD_PLAN" ]]; then
        pass "a round under a parent with no plan_abs keeps the PLAN_DOC the child recorded"
    else
        fail "the round under a parent with no plan_abs has PLAN_DOC [$GOT] (rc=$RC, out=[$OUT])"
    fi
else
    fail "could not open the plan-backed child under a parent with no plan_abs"
fi

# A unit with no plan carries no PLAN_DOC, and its round has none either.
if [[ -z "$(round_var par.kid-fix-1 PLAN_DOC 2>/dev/null)" ]]; then
    pass "a round for a unit with no plan has no PLAN_DOC"
else
    fail "the no-plan round has PLAN_DOC [$(round_var par.kid-fix-1 PLAN_DOC)]"
fi

echo
echo "fix-round_test: $PASS_COUNT passed, $FAIL_COUNT failed"
[[ $FAIL_COUNT -eq 0 ]]
