#!/usr/bin/env bash
set -euo pipefail
. "$(dirname "$0")/../../scripts/lib/koto-test-guard.sh" || exit 1

# Tests for check-normal-runs-unchanged.sh, against a throwaway repository.
#
# Usage:
#   bash scripts/ablation/check-normal-runs-unchanged_test.sh
#
# Exit codes:
#   0 - all tests passed
#   1 - one or more tests failed

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUT="$SCRIPT_DIR/check-normal-runs-unchanged.sh"

PASS_COUNT=0
FAIL_COUNT=0
TEST_DIR=$(mktemp -d)
ktg_on_exit 'rm -rf "$TEST_DIR"'

fail() { echo "FAIL: $1 - $2" >&2; FAIL_COUNT=$((FAIL_COUNT + 1)); }
pass() { echo "PASS: $1" >&2; PASS_COUNT=$((PASS_COUNT + 1)); }

FIX="$TEST_DIR/repo"
mkdir -p "$FIX/docs/measurement/offload-baseline" "$FIX/skills/work-on/koto-templates" \
    "$FIX/skills/work-on/references" "$FIX/scripts"
g() { git -C "$FIX" -c user.email=t@example.invalid -c user.name=t "$@"; }
g init -q -b main
printf '# manifest\nprofile\tpath\tselector\tweight\tnote\nwork-on\tskills/work-on/SKILL.md\tfile\t1\tresident\nwork-on\tskills/work-on/references/phase.md\tfile\t0.1\tconditional\n' \
    > "$FIX/docs/measurement/offload-baseline/load-manifest.tsv"
printf 'skill\n' > "$FIX/skills/work-on/SKILL.md"
printf 'phase\n' > "$FIX/skills/work-on/references/phase.md"
printf 'not loaded\n' > "$FIX/skills/work-on/references/unlisted.md"
printf 'template\n' > "$FIX/skills/work-on/koto-templates/work-on.md"
printf 'harness\n' > "$FIX/scripts/tool.sh"
g add -A
g commit -q -m base
BASE=$(g rev-parse HEAD)

run() {
    STATUS=0
    ERR=$(cd "$FIX" && "$SUT" "$@" 2>&1 >/dev/null) || STATUS=$?
}

reset_to_base() { g reset -q --hard "$BASE"; }

commit_change() {
    printf 'changed\n' >> "$FIX/$1"
    g commit -q -am "change $1"
}

printf 'more harness\n' >> "$FIX/scripts/tool.sh"
printf 'edit\n' >> "$FIX/skills/work-on/references/unlisted.md"
g commit -q -am "outside the load"
run "$BASE"
if [ "$STATUS" -eq 0 ]; then
    pass "files no run loads may change"
else
    fail "files no run loads may change" "status $STATUS: $ERR"
fi
reset_to_base

commit_change skills/work-on/SKILL.md
run "$BASE"
case "$STATUS:$ERR" in
    1:*"skills/work-on/SKILL.md differs"*) pass "a manifest path that changed fails, named" ;;
    *) fail "a manifest path that changed fails, named" "status $STATUS: $ERR" ;;
esac
reset_to_base

commit_change skills/work-on/koto-templates/work-on.md
run "$BASE"
case "$STATUS:$ERR" in
    1:*"koto-templates/work-on.md differs"*) pass "a changed koto template fails, named" ;;
    *) fail "a changed koto template fails, named" "status $STATUS: $ERR" ;;
esac
reset_to_base

printf 'new\n' > "$FIX/skills/work-on/koto-templates/extra.md"
g add -A
g commit -q -m "new template"
run "$BASE"
case "$STATUS:$ERR" in
    1:*"koto-templates/extra.md differs"*) pass "an added koto template fails, named" ;;
    *) fail "an added koto template fails, named" "status $STATUS: $ERR" ;;
esac
reset_to_base

# The base branch moves on after the change forked: its commits are not the
# change's own.
g checkout -q -b change "$BASE"
printf 'harness only\n' >> "$FIX/scripts/tool.sh"
g commit -q -am "the change"
HEAD_SHA=$(g rev-parse HEAD)
g checkout -q main
commit_change skills/work-on/SKILL.md
MOVED=$(g rev-parse HEAD)
run "$MOVED" "$HEAD_SHA"
if [ "$STATUS" -eq 0 ]; then
    pass "a manifest change that landed on the base after the fork is not the change's"
else
    fail "a manifest change that landed on the base after the fork is not the change's" "status $STATUS: $ERR"
fi
reset_to_base

run -rf
case "$STATUS:$ERR" in
    2:*"starts with '-'"*) pass "a base starting with - is refused" ;;
    *) fail "a base starting with - is refused" "status $STATUS: $ERR" ;;
esac
run nosuchref
case "$STATUS:$ERR" in
    2:*"not a commit"*) pass "an unknown base is refused" ;;
    *) fail "an unknown base is refused" "status $STATUS: $ERR" ;;
esac

# shirabe#2229. The path list removed before it is read back: a list that
# can't be read is not an empty one, so a changed manifest path is never
# waved through as unchanged. The sort stub fires on the call that sorts the
# list (sort -u and one file), removes that file and then runs the real sort;
# every other call is the real sort.
REAL_SORT=$(command -v sort)
VANISH_BIN="$TEST_DIR/vanish-bin"
mkdir -p "$VANISH_BIN"
printf '%s\n' '#!/bin/sh' 'if [ "$#" -eq 2 ] && [ "$1" = -u ]; then' '    rm -f "$2"' 'fi' \
    "exec \"$REAL_SORT\" \"\$@\"" > "$VANISH_BIN/sort"
chmod +x "$VANISH_BIN/sort"
commit_change skills/work-on/SKILL.md
rc=0
out=$(cd "$FIX" && PATH="$VANISH_BIN:$PATH" "$SUT" "$BASE" 2>&1) || rc=$?
if [ "$rc" -eq 2 ]; then
    pass "a temporary directory or file lost mid-run is an environment error (2)"
else
    fail "a temporary directory or file lost mid-run exited $rc, expected 2" "$out"
fi
case "$out" in
    *"is gone or unreadable"*) pass "  ... that names the cause" ;;
    *) fail "  ... that names the cause" "$out" ;;
esac
case "$out" in
    *"nothing a normal run loads differs"*) fail "  ... and never prints that nothing a normal run loads differs" "$out" ;;
    *) pass "  ... and never prints that nothing a normal run loads differs" ;;
esac
reset_to_base

# A git ls-tree that fails is an error, not an empty listing. Here the listing
# at HEAD fails and the one at the base works, so a template added at HEAD
# would be missing from the list and never compared. The git stub fails only
# the ls-tree of HEAD; every other call is the real git.
REAL_GIT=$(command -v git)
LSTREE_BIN="$TEST_DIR/lstree-bin"
mkdir -p "$LSTREE_BIN"
printf '%s\n' '#!/bin/sh' 'if [ "$1" = ls-tree ] && [ "$4" = HEAD ]; then' \
    '    echo "fatal: stub ls-tree failure" >&2' '    exit 128' 'fi' \
    "exec \"$REAL_GIT\" \"\$@\"" > "$LSTREE_BIN/git"
chmod +x "$LSTREE_BIN/git"
printf 'new template\n' > "$FIX/skills/work-on/koto-templates/added.md"
g add -A
g commit -q -m "add a template"
rc=0
out=$(cd "$FIX" && PATH="$LSTREE_BIN:$PATH" "$SUT" "$BASE" 2>&1) || rc=$?
if [ "$rc" -eq 2 ]; then
    pass "a failed git ls-tree is an environment error (2)"
else
    fail "a failed git ls-tree exited $rc, expected 2" "$out"
fi
case "$out" in
    *"could not list the files under skills/ at HEAD"*) pass "  ... that names the listing" ;;
    *) fail "  ... that names the listing" "$out" ;;
esac
case "$out" in
    *"nothing a normal run loads differs"*) fail "  ... and never prints that nothing a normal run loads differs" "$out" ;;
    *) pass "  ... and never prints that nothing a normal run loads differs" ;;
esac
reset_to_base

echo "check-normal-runs-unchanged_test: $PASS_COUNT passed, $FAIL_COUNT failed" >&2
[ "$FAIL_COUNT" -eq 0 ]
