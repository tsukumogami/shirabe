#!/usr/bin/env bash
# step-group_test.sh -- step-group.sh against real git and a real koto store.
# Part of the execute skill
#
# Each case builds a repository on a shared branch and a parent session whose
# children koto materializes from a task list, as /execute's spawn_and_await
# does, with a two-state stand-in for work-on.md. The three work-on scripts the
# re-checks call (review-level.sh, run-verification.sh, check-verification.sh)
# are stubs that log each call with the directory it ran in and answer from
# files, so a case sets the floor, a level and a verdict.
#
# It asserts:
#
#   limit      an empty value is 2, 1 to 6 are themselves, anything else is
#              refused;
#   next       steps 2 and 3, which wait only on step 1, form one group once
#              step 1 is terminal and before either has finished, and step 4,
#              which waits on step 2, is not in it; with three ready steps and
#              a limit of 2 the group has two, and with a limit of 1 it is one
#              step in the checkout with nothing recorded; a group with a step
#              still to land comes back as open, so step 4 does not start
#              while step 2 has finished but not landed, and does once it has;
#   cut        makes the worktree and step branch at the shared head, binds
#              the child there (a tick from the checkout is refused, one from
#              the worktree runs), finds both again on a second call, and
#              refuses a step outside the group and a bad step id or branch
#              before anything is written;
#   land       refuses a step whose earlier sibling has not been rebased
#              (wait), rebases in PLAN order with the shared branch untouched
#              until check, and with no shared file runs no re-check;
#   check      fast-forwards the shared branch to the rebased tip in PLAN
#              order after one facts call, removes the worktrees, and binds
#              the children back; a combined floor above every step's level
#              answers round and moves nothing;
#   conflict   a conflicting rebase is aborted and the step held while the
#              other step lands; the held step keeps the gate closed and a
#              step that waits on it out of the next group, which the step
#              that waits on the landed one does join; a held step is still
#              landed, alone, after a later worktrees group was picked, and
#              keeps its group open while its fix round runs; the owner's own rebase
#              then answers round, and the step lands only once a fix round
#              at done brought its head in after the round's base;
#   re-check   a rebase that brought in a change to one of the step's files
#              runs facts and check --ledger and starts verification, all in
#              the step's worktree against the step's child; a pending verdict
#              is verifying, a pass is staged, a held level or a failed
#              verdict is round, and a child that deferred verification runs
#              the level check alone;
#   stopped    a child at another terminal than done is recorded as stopped
#              and lands nothing;
#   landed     passes with no record and once every cut step has landed, and
#              fails naming the steps that have not;
#   the gate   spawn_and_await as execute.md ships it, its block taken from
#              the template at run time with only the child template swapped:
#              with every child at done it goes to pr_finalization when no
#              step was cut, holds on steps_landed while a cut step has not
#              landed and goes on once it has, and a failed child still
#              routes to escalate whatever the record says.
#
# Usage: step-group_test.sh
# Exit codes: 0 all pass, 1 a failure

set -u
. "$(dirname "$0")/../../../scripts/lib/koto-test-guard.sh" || exit 1

SCRIPT_DIR=$(CDPATH='' cd "$(dirname "$0")" && pwd)
SG="$SCRIPT_DIR/step-group.sh"

PASS_COUNT=0
FAIL_COUNT=0
pass() { echo "PASS: $*"; PASS_COUNT=$((PASS_COUNT + 1)); }
fail() { echo "FAIL: $*"; FAIL_COUNT=$((FAIL_COUNT + 1)); }

for tool in koto git jq; do
    command -v "$tool" >/dev/null || { echo "FAIL: $tool is not on PATH"; exit 1; }
done

WORK=$(mktemp -d "${TMPDIR:-/tmp}/step-group-test.XXXXXX") || exit 1
WORK=$(CDPATH='' cd "$WORK" && pwd -P)
ktg_on_exit 'rm -rf "$WORK"'

export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.invalid
export GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.invalid
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null

# --- the stand-in work-on scripts ------------------------------------------------

STUB="$WORK/stub"
mkdir -p "$STUB"
export STEP_GROUP_WORK_ON_SCRIPTS="$STUB" STUB
cat > "$STUB/review-level.sh" <<'EOF'
#!/usr/bin/env bash
echo "review-level $* cwd=$(pwd -P)" >> "$STUB/log"
case "$1" in
    facts) jq -nc --arg f "$(cat "$STUB/floor")" '{floor: $f}' | koto context add "$2" review_facts.json >/dev/null ;;
    check) exit "$(cat "$STUB/check_rc")" ;;
    level) if [ -f "$STUB/level-$2" ]; then cat "$STUB/level-$2"; else echo standard; fi ;;
esac
EOF
cat > "$STUB/run-verification.sh" <<'EOF'
#!/usr/bin/env bash
echo "run-verification $* cwd=$(pwd -P)" >> "$STUB/log"
EOF
cat > "$STUB/check-verification.sh" <<'EOF'
#!/usr/bin/env bash
echo "check-verification $* cwd=$(pwd -P)" >> "$STUB/log"
exit "$(cat "$STUB/verdict_rc")"
EOF
chmod +x "$STUB"/*.sh
stub_reset() {
    : > "$STUB/log"
    echo standard > "$STUB/floor"
    echo 0 > "$STUB/check_rc"
    echo 0 > "$STUB/verdict_rc"
    rm -f "$STUB"/level-*
}

# --- the stand-in templates ------------------------------------------------------

TPL="$WORK/tpl"
mkdir -p "$TPL"
cat > "$TPL/child.md" <<'EOF'
---
name: step-group-probe-child
version: "1.0"
description: A child that ticks to done or to a failure terminal.
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
  done:
    terminal: true
  blocked:
    terminal: true
    failure: true
---

## work

Submit `status`.

## done

Terminal.

## blocked

Failure terminal.
EOF
cat > "$TPL/parent.md" <<'EOF'
---
name: step-group-probe-parent
version: "1.0"
description: A parent that materializes one child per task and holds.
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
EOF

# --- helpers ---------------------------------------------------------------------

SHARED=impl/probe
REPO=""
SESSION=""
TASKS=""

# setup <name> <tasks json>: a repository on $SHARED with one commit, and a
# parent session named <name> whose first tick submitted the tasks.
setup() {
    REPO="$WORK/$1/repo"
    SESSION="$1"
    TASKS="$WORK/$1/tasks.json"
    mkdir -p "$REPO"
    cd "$REPO" || exit 1
    git init -q -b "$SHARED" .
    printf 'one\ntwo\nthree\nfour\nfive\n' > shared.txt
    git add shared.txt
    git commit -q -m base
    printf '%s\n' "$2" > "$TASKS"
    jq -c '{tasks: .}' "$TASKS" > "$WORK/$1/evidence.json"
    koto init "$SESSION" --template "$TPL/parent.md" >/dev/null 2>&1
    koto next "$SESSION" --with-data @"$WORK/$1/evidence.json" --no-cleanup >/dev/null 2>&1
    koto status "$SESSION" >/dev/null 2>&1 \
        || { echo "FAIL: could not open session $SESSION -- no case below can be trusted" >&2; exit 1; }
    stub_reset
}

# finish <step> [<dir>] [<status>]: tick the step's child to a terminal from
# <dir> (the checkout by default), then tick the parent so koto lists the
# children that waited on it.
finish() {
    (cd "${2:-$REPO}" && printf '{"status": "%s"}\n' "${3:-ok}" > "$WORK/ev.json" \
        && koto next "$SESSION.$1" --with-data @"$WORK/ev.json" --no-cleanup >/dev/null 2>&1)
    (cd "$REPO" && koto next "$SESSION" --no-cleanup >/dev/null 2>&1)
}

# commit_in <dir> <file> <content> <message>
commit_in() {
    printf '%s\n' "$3" > "$1/$2"
    git -C "$1" add -- "$2"
    git -C "$1" commit -q -m "$4"
}

OUT=""
RC=0
ERR="$WORK/err.txt"
# sg <args>: run step-group.sh in the checkout; OUT is stdout, RC its exit.
sg() {
    RC=0
    OUT=$(cd "$REPO" && bash "$SG" "$@" 2>"$ERR") || RC=$?
}

# expect <label> <rc> <stdout line>...: the last sg exited <rc> and printed
# each line.
expect() {
    local label=$1 rc=$2 line ok=1
    shift 2
    [ "$RC" -eq "$rc" ] || ok=0
    for line in "$@"; do
        grep -qxF -- "$line" <<<"$OUT" || ok=0
    done
    if [ "$ok" -eq 1 ]; then
        pass "$label"
    else
        fail "$label: exit $RC, stdout [$(printf '%s' "$OUT" | tr '\n' '|')], stderr [$(head -c 400 "$ERR" | tr '\n' '|')]"
    fi
}

lacks() {
    if grep -qF -- "$2" <<<"$OUT"; then
        fail "$1: stdout has [$2]: [$(printf '%s' "$OUT" | tr '\n' '|')]"
    else
        pass "$1"
    fi
}

check() {
    if eval "$2"; then pass "$1"; else fail "$1"; fi
}

wt_of() { printf '%s-step-worktrees/%s.%s\n' "$REPO" "$SESSION" "$1"; }
head_of() { git -C "$REPO" rev-parse "$1"; }
ledger() { (cd "$REPO" && koto context get "$SESSION" step_group.jsonl); }
has_ledger() { (cd "$REPO" && koto context exists "$SESSION" step_group.jsonl); }

FOUR='[{"name":"step-1","waits_on":[]},{"name":"step-2","waits_on":["step-1"]},{"name":"step-3","waits_on":["step-1"]},{"name":"step-4","waits_on":["step-2"]},{"name":"step-5","waits_on":["step-3"]}]'
THREE='[{"name":"step-1","waits_on":[]},{"name":"step-2","waits_on":["step-1"]},{"name":"step-3","waits_on":["step-1"]},{"name":"step-4","waits_on":["step-1"]}]'

# open_group <name>: FOUR's plan with step 1 finished in the checkout and
# steps 2 and 3 cut as a group of two.
open_group() {
    setup "$1" "$FOUR"
    finish step-1
    sg next "$SESSION" 2 "$TASKS"
    sg cut "$SESSION" step-2 "$SHARED"
    sg cut "$SESSION" step-3 "$SHARED"
}

# --- limit -----------------------------------------------------------------------

REPO="$WORK"
sg limit ""
expect "limit: an empty value is the default, 2" 0 2
for n in 1 2 6; do
    sg limit "$n"
    expect "limit: $n is itself" 0 "$n"
done
for bad in 0 7 12 two -1; do
    sg limit "$bad"
    expect "limit: [$bad] is refused" 1
done

# --- next ------------------------------------------------------------------------

setup next-a "$FOUR"
sg next "$SESSION" 2 "$TASKS"
expect "next: only step 1 is ready at the start, in the checkout" 0 "group=1 mode=checkout" "step=step-1 child=next-a.step-1"
lacks "next: step 2 is not in the first group" "step=step-2"
check "next: a group of one records nothing" '! has_ledger'
sg landed "$SESSION"
expect "landed: passes with no record" 0 "landed=all"

finish step-1
sg next "$SESSION" 2 "$TASKS"
expect "next: steps 2 and 3 start together once step 1 is terminal, before either finishes" 0 \
    "group=1 mode=worktrees" "step=step-2 child=next-a.step-2" "step=step-3 child=next-a.step-3"
lacks "next: step 4, which waits on step 2, is not in the group" "step=step-4"
check "next: both children are still running when the group is picked" \
    '[ "$(cd "$REPO" && koto status next-a.step-2 | jq -r .is_terminal)$(cd "$REPO" && koto status next-a.step-3 | jq -r .is_terminal)" = falsefalse ]'
check "next: the group is recorded with the checkout's head" \
    '[ "$(ledger | jq -rs ".[0] | \"\(.event) \(.steps | join(\",\")) \(.base)\"")" = "group step-2,step-3 $(head_of HEAD)" ]'

sg next "$SESSION" 2 "$TASKS"
expect "next: a group with steps still to land comes back as open" 0 "group=1 mode=open"

setup next-b "$THREE"
finish step-1
sg next "$SESSION" 2 "$TASKS"
expect "next: three ready steps and a limit of 2 start two" 0 "group=1 mode=worktrees" "step=step-2 child=next-b.step-2" "step=step-3 child=next-b.step-3"
lacks "next: the third ready step waits for the next group" "step=step-4"

setup next-c "$THREE"
finish step-1
sg next "$SESSION" 3 "$TASKS"
expect "next: a limit of 3 starts all three" 0 "group=1 mode=worktrees" "step=step-2 child=next-c.step-2" "step=step-3 child=next-c.step-3" "step=step-4 child=next-c.step-4"

setup next-d "$THREE"
finish step-1
sg next "$SESSION" 1 "$TASKS"
expect "next: a limit of 1 is one step in the checkout, in PLAN order" 0 "group=1 mode=checkout" "step=step-2 child=next-d.step-2"
lacks "next: a limit of 1 starts no second step" "step=step-3"
check "next: a limit of 1 records nothing" '! has_ledger'
sg next "$SESSION" 9 "$TASKS"
expect "next: a limit outside 1 to 6 is refused" 1

# --- cut -------------------------------------------------------------------------

setup cut-a "$FOUR"
finish step-1
sg next "$SESSION" 2 "$TASKS"
BASE=$(head_of HEAD)
sg cut "$SESSION" step-4 "$SHARED"
expect "cut: a step outside the group is refused" 1
for bad in ../x A_b -x "$(printf 'a%.0s' $(seq 1 64))"; do
    sg cut "$SESSION" "$bad" "$SHARED"
    expect "cut: the step id [${bad:0:12}] is refused" 1
done
sg cut "$SESSION" step-2 "-evil"
expect "cut: a branch with a leading dash is refused" 1
check "cut: a refusal wrote no worktree, branch or record line" \
    '[ ! -d "$REPO-step-worktrees" ] && [ -z "$(git -C "$REPO" branch --list "*--*")" ] && [ "$(ledger | jq -s length)" = 1 ]'

sg cut "$SESSION" step-2 "$SHARED"
expect "cut: makes the step's worktree and branch" 0 "worktree=$(wt_of step-2)" "branch=$SHARED--step-2" "cut=new"
check "cut: the step branch starts at the shared branch's head, in its own worktree" \
    '[ "$(git -C "$(wt_of step-2)" rev-parse HEAD)" = "$BASE" ] && [ "$(git -C "$(wt_of step-2)" rev-parse --abbrev-ref HEAD)" = "$SHARED--step-2" ]'
check "cut: the checkout stays on the shared branch" '[ "$(git -C "$REPO" rev-parse --abbrev-ref HEAD)" = "$SHARED" ]'
printf '{"status": "ok"}\n' > "$WORK/ev.json"
check "cut: a tick of the child from the checkout is refused" \
    '(cd "$REPO" && koto next cut-a.step-2 --with-data @"$WORK/ev.json" --no-cleanup 2>/dev/null) | jq -e ".error.code == \"execution_anchor_mismatch\"" >/dev/null'
check "cut: a tick of the child from its worktree runs" \
    '(cd "$(wt_of step-2)" && koto next cut-a.step-2 --with-data @"$WORK/ev.json" --no-cleanup 2>/dev/null) | jq -e ".state == \"done\"" >/dev/null'
sg cut "$SESSION" step-2 "$SHARED"
expect "cut: a second call finds the same worktree" 0 "worktree=$(wt_of step-2)" "cut=reused"
check "cut: the second call adds no record line" '[ "$(ledger | jq -s "map(select(.event == \"cut\")) | length")" = 1 ]'

# --- land and check: two steps that share no file --------------------------------

open_group land-a
BASE=$(head_of "$SHARED")
commit_in "$(wt_of step-2)" a.txt alpha "step 2"
commit_in "$(wt_of step-3)" b.txt beta "step 3"
sg land "$SESSION" step-2 "$SHARED"
expect "land: a step whose child is still running is refused" 1
finish step-2 "$(wt_of step-2)"
finish step-3 "$(wt_of step-3)"
sg land "$SESSION" step-3 "$SHARED"
expect "land: step 3 waits while step 2 has not been rebased" 6 "outcome=wait" "step=step-2"
sg land "$SESSION" step-2 "$SHARED"
expect "land: step 2 is staged" 0 "outcome=staged"
sg land "$SESSION" step-3 "$SHARED"
expect "land: step 3 is rebased onto step 2 and staged" 0 "outcome=staged"
check "land: step 3's branch now holds step 2's commit" \
    'git -C "$REPO" merge-base --is-ancestor "$SHARED--step-2" "$SHARED--step-3"'
check "land: the shared branch has not moved before check" '[ "$(head_of "$SHARED")" = "$BASE" ]'
check "land: with no shared file no re-check ran" '[ ! -s "$STUB/log" ]'
sg landed "$SESSION"
expect "landed: fails while the steps are staged" 1
check "landed: names both steps" 'grep -q "step-2 step-3" "$ERR"'
sg next "$SESSION" 2 "$TASKS"
expect "next: step 4 does not start while step 2 has finished but not landed" 0 "group=1 mode=open"

sg check "$SESSION" "$SHARED"
expect "check: lands the group" 0 "outcome=landed" "step=step-2" "step=step-3"
check "check: the shared branch is at step 3's rebased head" '[ "$(head_of "$SHARED")" = "$(head_of "$SHARED--step-3")" ]'
check "check: the commits are in PLAN order" \
    '[ "$(git -C "$REPO" log --format=%s "$BASE..$SHARED" | tr "\n" ",")" = "step 3,step 2," ]'
check "check: one level check ran over the combined diff, in the last step's worktree" \
    '[ "$(grep -c "^review-level facts" "$STUB/log")" = 1 ] && grep -q "^review-level facts land-a.step-3 --shared-branch $SHARED --no-check-line cwd=$(wt_of step-3)\$" "$STUB/log"'
check "check: the worktrees are removed" '[ ! -d "$(wt_of step-2)" ] && [ ! -d "$(wt_of step-3)" ]'
check "check: the children are bound to the checkout again" \
    '(cd "$REPO" && koto next land-a.step-2 --no-cleanup 2>/dev/null) | jq -e ".error == null" >/dev/null'
sg landed "$SESSION"
expect "landed: passes once every cut step has landed" 0 "landed=all"
sg next "$SESSION" 2 "$TASKS"
expect "next: steps 4 and 5 start once the steps they wait on have landed" 0 "group=2 mode=worktrees" "step=step-4 child=land-a.step-4" "step=step-5 child=land-a.step-5"

# --- check: a combined floor above every step's level ----------------------------

open_group floor-a
BASE=$(head_of "$SHARED")
commit_in "$(wt_of step-2)" a.txt alpha "step 2"
commit_in "$(wt_of step-3)" b.txt beta "step 3"
finish step-2 "$(wt_of step-2)"
finish step-3 "$(wt_of step-3)"
sg land "$SESSION" step-2 "$SHARED"
sg land "$SESSION" step-3 "$SHARED"
echo full > "$STUB/floor"
sg check "$SESSION" "$SHARED"
expect "check: a combined floor above every step's level answers round" 5 "outcome=round" "reason=group-floor:full"
check "check: the shared branch has not moved" '[ "$(head_of "$SHARED")" = "$BASE" ]'
check "check: the stderr line names the fix round and the branch to fast-forward to" \
    'grep -q "fix-round.sh start --from floor-a.step-3 --fresh" "$ERR" && grep -q "merge --ff-only $SHARED--step-3" "$ERR"'
sg check "$SESSION" "$SHARED"
expect "check: it stays round until the fix round is done" 5 "outcome=round"

open_group floor-b
commit_in "$(wt_of step-2)" a.txt alpha "step 2"
commit_in "$(wt_of step-3)" b.txt beta "step 3"
finish step-2 "$(wt_of step-2)"
finish step-3 "$(wt_of step-3)"
sg land "$SESSION" step-2 "$SHARED"
sg land "$SESSION" step-3 "$SHARED"
echo full > "$STUB/floor"
echo full > "$STUB/level-floor-b.step-2"
sg check "$SESSION" "$SHARED"
expect "check: a floor one step already got lands the group" 0 "outcome=landed"

# --- conflict --------------------------------------------------------------------

open_group conflict-a
BASE=$(head_of "$SHARED")
commit_in "$(wt_of step-2)" shared.txt "step two's line" "step 2"
commit_in "$(wt_of step-3)" shared.txt "step three's line" "step 3"
finish step-2 "$(wt_of step-2)"
finish step-3 "$(wt_of step-3)"
OLD3=$(head_of "$SHARED--step-3")
sg land "$SESSION" step-2 "$SHARED"
sg land "$SESSION" step-3 "$SHARED"
expect "conflict: a conflicting rebase stops the step" 3 "outcome=conflict"
check "conflict: the rebase was aborted and the step branch is as it was" \
    '[ "$(head_of "$SHARED--step-3")" = "$OLD3" ] && [ -z "$(git -C "$(wt_of step-3)" status --porcelain)" ]'
sg check "$SESSION" "$SHARED"
expect "conflict: the other step lands" 0 "outcome=landed" "step=step-2"
check "conflict: the shared branch holds step 2 and not step 3" \
    '[ "$(head_of "$SHARED")" = "$(head_of "$SHARED--step-2")" ] && ! git -C "$REPO" merge-base --is-ancestor "$OLD3" "$SHARED"'
sg landed "$SESSION"
expect "conflict: the held step keeps the gate closed" 1
check "conflict: the gate names the held step alone" 'grep -q "shared branch: step-3\$" "$ERR"'
sg next "$SESSION" 2 "$TASKS"
expect "conflict: the step that waits on the landed step goes on, and the held one is named" 0 \
    "group=2 mode=checkout" "step=step-4 child=conflict-a.step-4" "held=step-3"
lacks "conflict: the step that waits on the held step does not start" "step=step-5"

# The owner resolves by rebasing the step branch itself, in the step's worktree.
git -C "$(wt_of step-3)" rebase -q "$SHARED" >/dev/null 2>&1
printf 'resolved\n' > "$(wt_of step-3)/shared.txt"
git -C "$(wt_of step-3)" add shared.txt
GIT_EDITOR=true git -C "$(wt_of step-3)" rebase --continue >/dev/null 2>&1
NEW3=$(head_of "$SHARED--step-3")
sg land "$SESSION" step-3 "$SHARED"
expect "conflict: the owner's resolution answers round" 5 "outcome=round" "reason=conflict-resolved"
check "conflict: the resolution is not on the shared branch" '! git -C "$REPO" merge-base --is-ancestor "$NEW3" "$SHARED"'

# A fix round at done whose base is the shared head before the fast-forward.
ROUND_BASE=$(head_of "$SHARED")
(cd "$REPO" && koto init conflict-a.step-3-fix-1 --template "$TPL/child.md" >/dev/null 2>&1 \
    && jq -nc --arg b "$ROUND_BASE" '{round: 1, session: "conflict-a.step-3-fix-1", base: $b}' \
        | koto context add conflict-a.step-3 fix_rounds.jsonl >/dev/null 2>&1)
sg land "$SESSION" step-3 "$SHARED"
expect "conflict: a round that is still open lands nothing" 5 "outcome=round"
(cd "$REPO" && printf '{"status": "ok"}\n' > "$WORK/ev.json" \
    && koto next conflict-a.step-3-fix-1 --with-data @"$WORK/ev.json" --no-cleanup >/dev/null 2>&1)
sg land "$SESSION" step-3 "$SHARED"
expect "conflict: a round at done that brought nothing in lands nothing" 5 "outcome=round"
git -C "$REPO" merge -q --ff-only "$SHARED--step-3"
sg land "$SESSION" step-3 "$SHARED"
expect "conflict: the step lands once its round brought its head in" 0 "outcome=landed" "step=step-3"
sg landed "$SESSION"
expect "conflict: the gate opens once the held step has landed" 0 "landed=all"

# A step whose head was already under the round's base did not come in by it.
open_group conflict-b
commit_in "$(wt_of step-2)" shared.txt "step two's line" "step 2"
commit_in "$(wt_of step-3)" shared.txt "step three's line" "step 3"
finish step-2 "$(wt_of step-2)"
finish step-3 "$(wt_of step-3)"
sg land "$SESSION" step-2 "$SHARED"
sg land "$SESSION" step-3 "$SHARED"
sg check "$SESSION" "$SHARED"
git -C "$(wt_of step-3)" rebase -q "$SHARED" >/dev/null 2>&1
printf 'resolved\n' > "$(wt_of step-3)/shared.txt"
git -C "$(wt_of step-3)" add shared.txt
GIT_EDITOR=true git -C "$(wt_of step-3)" rebase --continue >/dev/null 2>&1
sg land "$SESSION" step-3 "$SHARED"
git -C "$REPO" merge -q --ff-only "$SHARED--step-3"
(cd "$REPO" && koto init conflict-b.step-3-fix-1 --template "$TPL/child.md" >/dev/null 2>&1 \
    && printf '{"status": "ok"}\n' > "$WORK/ev.json" \
    && koto next conflict-b.step-3-fix-1 --with-data @"$WORK/ev.json" --no-cleanup >/dev/null 2>&1 \
    && jq -nc --arg b "$(head_of "$SHARED")" '{round: 1, session: "conflict-b.step-3-fix-1", base: $b}' \
        | koto context add conflict-b.step-3 fix_rounds.jsonl >/dev/null 2>&1)
sg land "$SESSION" step-3 "$SHARED"
expect "conflict: a resolution fast-forwarded before the round's base is not landed by it" 5 "outcome=round"

# A held step is still landed after a later worktrees group was picked.
LATER='[{"name":"step-1","waits_on":[]},{"name":"step-2","waits_on":["step-1"]},{"name":"step-3","waits_on":["step-1"]},{"name":"step-4","waits_on":["step-2"]},{"name":"step-5","waits_on":["step-2"]}]'
setup conflict-c "$LATER"
finish step-1
sg next "$SESSION" 2 "$TASKS"
sg cut "$SESSION" step-2 "$SHARED"
sg cut "$SESSION" step-3 "$SHARED"
commit_in "$(wt_of step-2)" shared.txt "step two's line" "step 2"
commit_in "$(wt_of step-3)" shared.txt "step three's line" "step 3"
finish step-2 "$(wt_of step-2)"
finish step-3 "$(wt_of step-3)"
sg land "$SESSION" step-2 "$SHARED"
sg land "$SESSION" step-3 "$SHARED"
sg check "$SESSION" "$SHARED"
sg next "$SESSION" 2 "$TASKS"
expect "conflict: the next group is picked past the held step" 0 "group=2 mode=worktrees" "step=step-4 child=conflict-c.step-4" "step=step-5 child=conflict-c.step-5" "held=step-3"
git -C "$(wt_of step-3)" rebase -q "$SHARED" >/dev/null 2>&1
printf 'resolved\n' > "$(wt_of step-3)/shared.txt"
git -C "$(wt_of step-3)" add shared.txt
GIT_EDITOR=true git -C "$(wt_of step-3)" rebase --continue >/dev/null 2>&1
sg land "$SESSION" step-3 "$SHARED"
expect "conflict: a held step of an earlier group is still landed after a later group was picked" 5 "outcome=round" "reason=conflict-resolved"
ROUND_BASE=$(head_of "$SHARED")
git -C "$REPO" merge -q --ff-only "$SHARED--step-3"
(cd "$REPO" && koto init conflict-c.step-3-fix-1 --template "$TPL/child.md" >/dev/null 2>&1 \
    && printf '{"status": "ok"}\n' > "$WORK/ev.json" \
    && koto next conflict-c.step-3-fix-1 --with-data @"$WORK/ev.json" --no-cleanup >/dev/null 2>&1 \
    && jq -nc --arg b "$ROUND_BASE" '{round: 1, session: "conflict-c.step-3-fix-1", base: $b}' \
        | koto context add conflict-c.step-3 fix_rounds.jsonl >/dev/null 2>&1)
sg land "$SESSION" step-3 "$SHARED"
expect "conflict: it lands through its round, alone" 0 "outcome=landed" "step=step-3"
lacks "conflict: landing it records no step of the later group" "step=step-4"
sg cut "$SESSION" step-4 "$SHARED"
expect "conflict: the later group is still the one cut and landed" 0 "branch=$SHARED--step-4"

# A held step whose round is under way holds the next group back.
open_group conflict-d
commit_in "$(wt_of step-2)" shared.txt "step two's line" "step 2"
commit_in "$(wt_of step-3)" shared.txt "step three's line" "step 3"
finish step-2 "$(wt_of step-2)"
finish step-3 "$(wt_of step-3)"
sg land "$SESSION" step-2 "$SHARED"
sg land "$SESSION" step-3 "$SHARED"
sg check "$SESSION" "$SHARED"
git -C "$(wt_of step-3)" rebase -q "$SHARED" >/dev/null 2>&1
printf 'resolved\n' > "$(wt_of step-3)/shared.txt"
git -C "$(wt_of step-3)" add shared.txt
GIT_EDITOR=true git -C "$(wt_of step-3)" rebase --continue >/dev/null 2>&1
sg land "$SESSION" step-3 "$SHARED"
sg next "$SESSION" 2 "$TASKS"
expect "conflict: a held step in its fix round keeps its group open" 0 "group=1 mode=open" "step=step-3 child=conflict-d.step-3 state=round"

# --- re-check: the rebase brought in a change to one of the step's files ----------

# overlap <name>: steps 2 and 3 change different lines of shared.txt, so step 3
# rebases cleanly onto step 2 and one of its files changed under it.
overlap() {
    open_group "$1"
    printf 'ONE\ntwo\nthree\nfour\nfive\n' > "$(wt_of step-2)/shared.txt"
    git -C "$(wt_of step-2)" commit -q -am "step 2"
    printf 'one\ntwo\nthree\nfour\nFIVE\n' > "$(wt_of step-3)/shared.txt"
    git -C "$(wt_of step-3)" commit -q -am "step 3"
    finish step-2 "$(wt_of step-2)"
    finish step-3 "$(wt_of step-3)"
    sg land "$SESSION" step-2 "$SHARED"
    : > "$STUB/log"
}

overlap recheck-a
echo 75 > "$STUB/verdict_rc"
sg land "$SESSION" step-3 "$SHARED"
expect "re-check: a pending verdict is verifying" 4 "outcome=verifying"
W3=$(wt_of step-3)
check "re-check: the level check ran at the rebased head, in the step's worktree, against its child" \
    'grep -q "^review-level facts recheck-a.step-3 --shared-branch $SHARED --no-check-line cwd=$W3\$" "$STUB/log" && grep -q "^review-level check recheck-a.step-3 --ledger cwd=$W3\$" "$STUB/log"'
check "re-check: verification was started there too" \
    'grep -q "^run-verification --start --session recheck-a.step-3 cwd=$W3\$" "$STUB/log" && grep -q "^check-verification --verdict --session recheck-a.step-3 --shared-branch $SHARED cwd=$W3\$" "$STUB/log"'
check "re-check: the rebased head holds both changes" \
    '[ "$(tr "\n" "," < "$W3/shared.txt")" = "ONE,two,three,four,FIVE," ]'
sg land "$SESSION" step-3 "$SHARED"
expect "re-check: it stays verifying while the verdict is pending" 4 "outcome=verifying"
check "re-check: verification is started once" '[ "$(grep -c "^run-verification" "$STUB/log")" = 1 ]'
sg check "$SESSION" "$SHARED"
expect "re-check: check waits on a step that is still verifying" 6 "outcome=wait" "step=step-3"
echo 0 > "$STUB/verdict_rc"
sg land "$SESSION" step-3 "$SHARED"
expect "re-check: a passing verdict stages the step" 0 "outcome=staged"

overlap recheck-b
echo 1 > "$STUB/check_rc"
sg land "$SESSION" step-3 "$SHARED"
expect "re-check: a level below the floor at the rebased head answers round" 5 "outcome=round" "reason=level"
check "re-check: no verification starts for a step that needs a round" '! grep -q "^run-verification" "$STUB/log"'

overlap recheck-c
echo 1 > "$STUB/verdict_rc"
sg land "$SESSION" step-3 "$SHARED"
expect "re-check: a failed verification at the rebased head answers round" 5 "outcome=round" "reason=verification:1"

overlap recheck-d
(cd "$REPO" && printf 'deferred\n' | koto context add recheck-d.step-3 verification_deferral >/dev/null 2>&1)
sg land "$SESSION" step-3 "$SHARED"
expect "re-check: a child that deferred verification is staged on the level check alone" 0 "outcome=staged"
check "re-check: the deferred child ran the level check and no verification" \
    'grep -q "^review-level check recheck-d.step-3 --ledger" "$STUB/log" && ! grep -q "verification" "$STUB/log"'

# --- stopped ---------------------------------------------------------------------

open_group stopped-a
commit_in "$(wt_of step-2)" a.txt alpha "step 2"
finish step-2 "$(wt_of step-2)" blocked
finish step-3 "$(wt_of step-3)"
sg land "$SESSION" step-2 "$SHARED"
expect "stopped: a child at another terminal than done lands nothing" 7 "outcome=stopped" "state=blocked"
sg land "$SESSION" step-3 "$SHARED"
expect "stopped: the step after it goes on" 0 "outcome=staged"
sg check "$SESSION" "$SHARED"
expect "stopped: the group lands without it" 0 "outcome=landed" "step=step-3"
check "stopped: its commit is not on the shared branch" '! git -C "$REPO" merge-base --is-ancestor "$SHARED--step-2" "$SHARED"'
sg landed "$SESSION"
expect "stopped: a stopped step does not hold the gate; the batch's own gate routes it" 0 "landed=all"

# --- the gate, as execute.md ships it -----------------------------------------------

TEMPLATE="$SCRIPT_DIR/../koto-templates/execute.md"
PLUGIN=$(CDPATH='' cd "$SCRIPT_DIR/../../.." && pwd)
GATE="$WORK/gate"
mkdir -p "$GATE"
cp "$TPL/child.md" "$GATE/child.md"
{
    printf '%s\n' '---' 'name: step-group-gate-fixture' 'version: "1.0"' \
        'description: spawn_and_await as shipped, between two stub terminals.' \
        'initial_state: spawn_and_await' 'variables:' \
        '  PLUGIN_ROOT:' '    description: plugin root' '    required: true' 'states:'
    awk '
        $0 == "  spawn_and_await:" { found = 1; print; next }
        found && /^  [a-zA-Z_][a-zA-Z0-9_]*:$/ { exit }
        found && /^---$/ { exit }
        found { print }
    ' "$TEMPLATE" | sed 's|default_template: .*|default_template: ./child.md|'
    printf '%s\n' '  pr_finalization:' '    terminal: true' '  escalate:' '    terminal: true' \
        '---' '' '## spawn_and_await' '' 'The state under test.' '' \
        '## pr_finalization' '' 'Stub.' '' '## escalate' '' 'Stub.'
} > "$GATE/fixture.md"
mkdir -p "$GATE/repo"
git -C "$GATE/repo" init -q -b "$SHARED" .

# gate_run <session> <status of b> [<record line>...]: two children, a at done
# and b at <status>, the record seeded, then one bare tick. STATE is where the
# parent stands and BLOCK the gates that hold it.
STATE=""
BLOCK=""
gate_tick() {
    local resp
    resp=$(cd "$GATE/repo" && koto next "$1" --no-cleanup 2>/dev/null)
    STATE=$(printf '%s' "$resp" | jq -r '.state // "none"')
    BLOCK=$(printf '%s' "$resp" | jq -r '[.blocking_conditions[]? | .name] | join(",")')
}
gate_run() {
    local s=$1 status=$2
    shift 2
    printf '{"tasks": [{"name": "a"}, {"name": "b"}]}\n' > "$WORK/gate-tasks.json"
    (cd "$GATE/repo" && koto init "$s" --template "$GATE/fixture.md" --var PLUGIN_ROOT="$PLUGIN" >/dev/null 2>&1 \
        && koto next "$s" --with-data @"$WORK/gate-tasks.json" --no-cleanup >/dev/null 2>&1)
    printf '{"status": "ok"}\n' > "$WORK/ev.json"
    (cd "$GATE/repo" && koto next "$s.a" --with-data @"$WORK/ev.json" --no-cleanup >/dev/null 2>&1)
    printf '{"status": "%s"}\n' "$status" > "$WORK/ev.json"
    (cd "$GATE/repo" && koto next "$s.b" --with-data @"$WORK/ev.json" --no-cleanup >/dev/null 2>&1)
    [ $# -eq 0 ] || printf '%s\n' "$@" | (cd "$GATE/repo" && koto context add "$s" step_group.jsonl >/dev/null 2>&1)
    gate_tick "$s"
}
CUT_A='{"event":"cut","step":"a","worktree":"/nowhere","branch":"x--a","base":"0"}'
LANDED_A='{"event":"landed","step":"a","head":"0"}'

if grep -q '^      steps_landed:$' "$GATE/fixture.md"; then
    pass "the gate: the shipped spawn_and_await block has a steps_landed gate"
else
    fail "the gate: the shipped spawn_and_await block has no steps_landed gate"
fi
gate_run gate-none ok
check "the gate: every child done and no step ever cut goes to pr_finalization" '[ "$STATE" = pr_finalization ]'
gate_run gate-held ok "$CUT_A"
check "the gate: every child done with a cut step not landed holds at spawn_and_await on steps_landed" \
    '[ "$STATE" = spawn_and_await ] && [ "$BLOCK" = steps_landed ]'
printf '%s\n' "$CUT_A" "$LANDED_A" | (cd "$GATE/repo" && koto context add gate-held step_group.jsonl >/dev/null 2>&1)
gate_tick gate-held
check "the gate: the same run goes to pr_finalization once the step is recorded as landed" '[ "$STATE" = pr_finalization ]'
gate_run gate-failed blocked "$CUT_A"
check "the gate: a failed child routes to escalate whatever the record says" '[ "$STATE" = escalate ]'

# --- usage -----------------------------------------------------------------------

sg bogus
expect "usage: an unknown subcommand exits 64" 64
sg land "bad session" step-2 "$SHARED"
expect "usage: a session name with a space exits 64" 64

echo
echo "step-group_test.sh: $PASS_COUNT passed, $FAIL_COUNT failed"
[ "$FAIL_COUNT" -eq 0 ]
