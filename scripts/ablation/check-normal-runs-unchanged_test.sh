#!/usr/bin/env bash
set -euo pipefail

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
trap 'rm -rf "$TEST_DIR"' EXIT

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

echo "check-normal-runs-unchanged_test: $PASS_COUNT passed, $FAIL_COUNT failed" >&2
[ "$FAIL_COUNT" -eq 0 ]
