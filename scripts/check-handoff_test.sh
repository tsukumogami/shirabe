#!/usr/bin/env bash
# check-handoff_test.sh -- tests for scripts/check-handoff.sh, the hand-off
# check the script-graded eval cases run.
#
# Usage: bash scripts/check-handoff_test.sh
#
# Each case copies the parts of this tree the check reads (the script itself,
# the two skills' SKILL.md and koto-templates/, and work-on's koto-templates/,
# which execute.md names as its child template) into a temporary
# directory, applies one mutation there, runs that copy's
# scripts/check-handoff.sh, and removes the copy. The checkout is never
# changed. The mutations break the receiving-side contract of /deliver's
# hand-off to /execute in every way the check is meant to catch: an outcome
# word renamed on the edges into each terminal state of execute.md, a new
# terminal state with a new word, a word dropped from the exec_leg gate's
# expect list, each copied key dropped from a result map, an extra copied key,
# the template renamed, and the --koto-leg declaration removed.
#
# Needs koto (the check compiles the templates with it) and python3. With no
# koto on PATH every case that needs it fails rather than skips: a skip here
# would report green having checked nothing.
#
# Exit codes:
#   0 -- all cases pass
#   1 -- one or more cases failed
#
# bash 3.2 floor: no associative arrays, no mapfile.

set -uo pipefail
. "$(dirname "$0")/../scripts/lib/koto-test-guard.sh" || exit 1

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd -P)
REPO_ROOT=$(cd "$SCRIPT_DIR/.." && pwd -P)

PASS_COUNT=0
FAIL_COUNT=0
pass() { printf 'PASS: %s\n' "$*"; PASS_COUNT=$((PASS_COUNT + 1)); }
fail() { printf 'FAIL: %s\n' "$*"; FAIL_COUNT=$((FAIL_COUNT + 1)); }

T=$(mktemp -d "${TMPDIR:-/tmp}/check-handoff-test.XXXXXX") || { echo "FAIL: mktemp"; exit 1; }
cleanup() { [ -n "${T:-}" ] && rm -rf "$T"; return 0; }
ktg_on_exit cleanup

COPY="$T/tree"
EXEC_TPL="skills/execute/koto-templates/execute.md"
DELIVER_TPL="skills/deliver/koto-templates/deliver.md"

# fresh_copy: the files the check reads, in $COPY, replacing any earlier copy.
fresh_copy() {
    rm -rf "$COPY"
    mkdir -p "$COPY/scripts" "$COPY/skills/deliver" "$COPY/skills/execute" || return 1
    cp "$REPO_ROOT/scripts/check-handoff.sh" "$COPY/scripts/" || return 1
    for s in deliver execute; do
        cp "$REPO_ROOT/skills/$s/SKILL.md" "$COPY/skills/$s/" || return 1
        cp -R "$REPO_ROOT/skills/$s/koto-templates" "$COPY/skills/$s/" || return 1
    done
    # execute.md's spawn_and_await names work-on.md as its child template, and
    # koto compiles the child with the parent.
    mkdir -p "$COPY/skills/work-on" || return 1
    cp -R "$REPO_ROOT/skills/work-on/koto-templates" "$COPY/skills/work-on/" || return 1
}

RC=0
OUT=""
run_check() { # run_check -- the copy's check on deliver -> execute; sets RC and OUT
    RC=0
    OUT=$(bash "$COPY/scripts/check-handoff.sh" deliver execute 2>&1) || RC=$?
}

# apply <file> <awk program> [awk -v assignments...]: rewrite a file in the
# copy through awk, and fail when the rewrite changed nothing, so a mutation
# that no longer matches the template is reported instead of passing quietly.
MUTATED=0
apply() {
    local file="$COPY/$1" prog="$2"
    shift 2
    MUTATED=0
    awk "$@" "$prog" "$file" > "$file.new" || return 1
    if cmp -s "$file" "$file.new"; then
        rm -f "$file.new"
        return 1
    fi
    mv "$file.new" "$file" && MUTATED=1
}

# The state a line belongs to (a two-space-indented key in the frontmatter)
# and the target of the transition it sits under.
TRACK='
/^  [A-Za-z_][A-Za-z0-9_]*:[ ]*$/ { state = $1; sub(/:$/, "", state); target = "" }
/^ *- target: / { target = $0; sub(/^ *- target: */, "", target); sub(/[ ]*$/, "", target) }
'

# expect_fail <label> <needle>...: the check exited non-zero and its output
# names every needle.
expect_fail() {
    local label="$1" needle missing=""
    shift
    for needle in "$@"; do
        case "$OUT" in *"$needle"*) ;; *) missing="$missing [$needle]" ;; esac
    done
    if [ "$RC" -ne 0 ] && [ -z "$missing" ]; then
        pass "$label: exit $RC, output names $*"
    else
        fail "$label (rc=$RC, missing:$missing): $OUT"
    fi
}

if ! command -v koto >/dev/null; then
    fail "koto is not on PATH; check-handoff.sh compiles the templates with it, so no case can run"
    echo ""
    echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed"
    exit 1
fi

# -- unchanged tree --------------------------------------------------------

fresh_copy || { fail "could not copy the tree"; exit 1; }
run_check
if [ "$RC" -eq 0 ] && [ "$OUT" = "PASS: handoff deliver -> execute: receiving-side contract" ]; then
    pass "unchanged tree: deliver -> execute exits 0 with one PASS line"
else
    fail "unchanged tree (rc=$RC): $OUT"
fi
rm -rf "$COPY"

# -- outcome words on the edges into each terminal state -------------------

# rename_edge <terminal> <old word> <new word>
rename_edge() {
    apply "$EXEC_TPL" "$TRACK"'
{ if (target == t && $0 ~ ("^ +outcome: " old "$")) sub("outcome: " old "$", "outcome: " new); print }' \
        -v t="$1" -v old="$2" -v new="$3"
}
for spec in paused_for_review:paused-for-review merged:merged \
    ready_awaiting_merge:ready-awaiting-merge done_blocked:error; do
    terminal=${spec%%:*}
    word=${spec#*:}
    renamed="$word-renamed"
    fresh_copy || { fail "could not copy the tree"; continue; }
    if ! rename_edge "$terminal" "$word" "$renamed"; then
        fail "rename '$word' on the edges into $terminal: the mutation matched nothing in $EXEC_TPL"
        rm -rf "$COPY"
        continue
    fi
    run_check
    expect_fail "'$word' renamed to '$renamed' on the edges into $terminal" \
        "outcome word '$renamed'" "doesn't expect it" "exec_leg"
    rm -rf "$COPY"
done

# -- a new terminal state with a new word ----------------------------------

fresh_copy || fail "could not copy the tree"
# escalate's one unconditional edge goes to a new terminal, parked, assigning
# the word parked; parked's result map is the others'.
if apply "$EXEC_TPL" "$TRACK"'
$0 == "  done_blocked:" {
    print "  parked:"; print "    terminal: true"; print "    result:"
    print "      outcome: \"${context.outcome}\""; print "      step: \"${context.step}\""
    print "      reason: \"${context.reason}\""; print "      pr: \"${context.home_pr}\""
    print "      repos: \"${context.repos}\""; print "      resume: \"${context.resume}\""
    print "      waiting: \"${context.waiting}\""; print ""
}
{
    if (state == "escalate" && $0 ~ /^ *- target: done_blocked$/) sub(/done_blocked$/, "parked")
    else if (state == "escalate" && $0 ~ /^ +outcome: error$/) sub(/error$/, "parked")
    print
}
END { print ""; print "## parked"; print ""; print "Parked." }'; then
    run_check
    expect_fail "a new terminal state reached by an edge assigning 'parked'" \
        "outcome word 'parked'" "terminal state parked" "doesn't expect it"
else
    fail "parked: the mutation matched nothing in $EXEC_TPL"
fi
rm -rf "$COPY"

# -- the expect list loses a word ------------------------------------------

fresh_copy || fail "could not copy the tree"
if apply "$DELIVER_TPL" '
{ if ($0 ~ /^ +outcome: \[.*paused-for-review, /) sub(/paused-for-review, /, ""); print }'; then
    run_check
    expect_fail "exec_leg's expect list without paused-for-review" \
        "outcome word 'paused-for-review'" "doesn't expect it"
else
    fail "expect list: the mutation matched nothing in $DELIVER_TPL"
fi
rm -rf "$COPY"

# -- result maps lose a copied key -----------------------------------------

for key in pr repos resume waiting reason step; do
    fresh_copy || { fail "could not copy the tree"; continue; }
    if apply "$EXEC_TPL" "$TRACK"'
{ if (state == "merged" && $0 ~ ("^      " k ": ")) next; print }' -v k="$key"; then
        run_check
        expect_fail "'$key' dropped from the result map of terminal state merged" \
            "key '$key'" "terminal state merged" "execute_run"
    else
        fail "drop $key: the mutation matched nothing in $EXEC_TPL"
    fi
    rm -rf "$COPY"
done

# -- an extra copied key ---------------------------------------------------

fresh_copy || fail "could not copy the tree"
if apply "$DELIVER_TPL" "$TRACK"'
{
    print
    if (state == "execute_run" && !done && $0 ~ /^ +pr: "\$\{gates\.exec_leg\.payload\.pr\}"$/) {
        line = $0; sub(/pr: .*/, "", line)
        print line "extra: \"${gates.exec_leg.payload.extra}\""
        done = 1
    }
}'; then
    run_check
    expect_fail "execute_run also copying 'extra'" "key 'extra'" "missing from the result map"
else
    fail "extra key: the mutation matched nothing in $DELIVER_TPL"
fi
rm -rf "$COPY"

# -- the template renamed --------------------------------------------------

fresh_copy || fail "could not copy the tree"
mv "$COPY/$EXEC_TPL" "$COPY/skills/execute/koto-templates/execute-v2.md"
run_check
expect_fail "execute.md renamed to execute-v2.md" "execute.md" "does not exist"
rm -rf "$COPY"

# -- --koto-leg removed from SKILL.md --------------------------------------

fresh_copy || fail "could not copy the tree"
if apply "skills/execute/SKILL.md" 'index($0, "--koto-leg") == 0 { print }'; then
    run_check
    expect_fail "--koto-leg removed from skills/execute/SKILL.md" "--koto-leg" "skills/execute/SKILL.md"
else
    fail "--koto-leg: the mutation matched nothing in skills/execute/SKILL.md"
fi
rm -rf "$COPY"

# -- usage and koto ----------------------------------------------------------

fresh_copy || fail "could not copy the tree"
RC=0
OUT=$(bash "$COPY/scripts/check-handoff.sh" deliver nosuchskill 2>&1) || RC=$?
if [ "$RC" -eq 2 ] && case "$OUT" in *"skills/nosuchskill"*) true ;; *) false ;; esac; then
    pass "a skill with no directory under skills/ is a usage error, exit 2"
else
    fail "missing skill (rc=$RC): $OUT"
fi
# PATH without koto: python3 and the basic tools only.
NOKOTO="$T/nokoto-bin"
mkdir -p "$NOKOTO"
ln -s "$(command -v python3)" "$NOKOTO/python3"
if PATH="$NOKOTO:/usr/bin:/bin" command -v koto >/dev/null; then
    echo "SKIP: a koto in /usr/bin or /bin -- the no-koto case was not checked"
else
    RC=0
    OUT=$(PATH="$NOKOTO:/usr/bin:/bin" /bin/bash "$COPY/scripts/check-handoff.sh" deliver execute 2>&1) || RC=$?
    expect_fail "with no koto on PATH" "koto is not on PATH"
fi
rm -rf "$COPY"

echo ""
echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed"
[ "$FAIL_COUNT" -eq 0 ]
