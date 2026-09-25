#!/usr/bin/env bash
set -euo pipefail

# Tests for check-merged-wording.sh.
#
# Each case builds a throwaway repository root holding the two scanned SKILL.md
# files and an allowlist, points the check at it through MERGED_WORDING_ROOT,
# and asserts the exit code (and, for failures, that the output names what
# failed). The last case runs the check on this repository as it stands.
#
# Usage:
#   bash scripts/check-merged-wording_test.sh
#
# Exit codes:
#   0 - all tests passed
#   1 - one or more tests failed

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHECK_SCRIPT="$SCRIPT_DIR/check-merged-wording.sh"

TEST_DIR=""
PASS_COUNT=0
FAIL_COUNT=0

setup() {
    # macOS mktemp ignores TMPDIR without an explicit template.
    TEST_DIR=$(mktemp -d "${TMPDIR:-/tmp}/check-merged-wording.XXXXXX")
    mkdir -p "$TEST_DIR/skills/execute" "$TEST_DIR/skills/work-on" "$TEST_DIR/scripts"
    printf '%s\n' '# Execute' '' 'Drives a plan to ready pull requests.' \
        > "$TEST_DIR/skills/execute/SKILL.md"
    printf '%s\n' '# Work on' '' 'Leaves a ready PR with passing CI.' \
        > "$TEST_DIR/skills/work-on/SKILL.md"
    printf '%s\n' '# allowlist' '' > "$TEST_DIR/scripts/check-merged-wording.allow"
}

teardown() {
    [ -n "$TEST_DIR" ] && rm -rf "$TEST_DIR"
    TEST_DIR=""
}

fail() {
    echo "FAIL: $1 - $2" >&2
    FAIL_COUNT=$((FAIL_COUNT + 1))
}

pass() {
    echo "PASS: $1" >&2
    PASS_COUNT=$((PASS_COUNT + 1))
}

# add_line <repo-relative file> <text>
add_line() {
    printf '%s\n' "$2" >> "$TEST_DIR/$1"
}

# add_record <file> <match> <reason>
add_record() {
    printf '%s\t%s\t%s\n' "$1" "$2" "$3" >> "$TEST_DIR/scripts/check-merged-wording.allow"
}

OUT=""
RC=0
run_check() {
    RC=0
    OUT=$(MERGED_WORDING_ROOT="$TEST_DIR" bash "$CHECK_SCRIPT" 2>&1) || RC=$?
}

# expect <name> <rc> [<substring the output must contain>]
expect() {
    local name="$1" want="$2" needle="${3:-}"
    if [ "$RC" -ne "$want" ]; then
        fail "$name" "expected exit $want, got $RC: $OUT"
        return
    fi
    if [ -n "$needle" ]; then
        case "$OUT" in
            *"$needle"*) ;;
            *) fail "$name" "output does not name '$needle': $OUT"; return ;;
        esac
    fi
    pass "$name"
}

test_clean_file_passes() {
    setup
    run_check
    expect "a file with no \"merged\" passes" 0
    teardown
}

test_unallowlisted_line_fails() {
    setup
    add_line skills/execute/SKILL.md 'Drives the plan all the way to merged code.'
    run_check
    expect "an unallowlisted \"merged\" line fails naming file:line" 1 "skills/execute/SKILL.md:4"
    teardown
}

test_work_on_is_scanned() {
    setup
    add_line skills/work-on/SKILL.md 'A merged PR with passing CI.'
    run_check
    expect "the work-on SKILL.md is scanned too" 1 "skills/work-on/SKILL.md:4"
    teardown
}

# accepted <case name> <line>
accepted() {
    setup
    add_line skills/execute/SKILL.md "$2"
    run_check
    expect "$1 passes with no record" 0
    teardown
}

test_accepted_tokens() {
    accepted "the \`merged\` final state" 'The run ends at the `merged` terminal.'
    accepted "outcome=merged" 'print-exit.sh prints outcome=merged on success.'
    accepted "pr_state=merged" 'The record carries pr_state=merged.'
    accepted "GitHub's MERGED state" 'A node is satisfied once its PR reports MERGED.'
    accepted "unmerged" 'A node waits while its predecessor is unmerged.'
    accepted "not-merged" 'An unresolvable PR is treated as not-merged.'
}

test_accepted_token_does_not_hide_a_second_occurrence() {
    setup
    add_line skills/execute/SKILL.md 'It reaches `merged` once the PR is merged.'
    run_check
    expect "an accepted token on the line does not excuse another \"merged\"" 1 "skills/execute/SKILL.md:4"
    teardown
}

test_record_covers_line() {
    setup
    add_line skills/execute/SKILL.md 'Merged by a human on GitHub, the PR unblocks its successor.'
    add_record skills/execute/SKILL.md 'Merged by a human on GitHub' 'Describes the PR state GitHub reports, not a run outcome.'
    run_check
    expect "a record covers its flagged line" 0
    teardown
}

test_record_matching_zero_lines_fails() {
    setup
    add_record skills/execute/SKILL.md 'no such line merged' 'A reason.'
    run_check
    expect "a record matching zero lines fails" 1 "matches 0 lines"
    teardown
}

test_record_matching_two_lines_fails() {
    setup
    add_line skills/execute/SKILL.md 'The PR merged on GitHub (first).'
    add_line skills/execute/SKILL.md 'The PR merged on GitHub (second).'
    add_record skills/execute/SKILL.md 'The PR merged on GitHub' 'Describes GitHub PR state.'
    run_check
    expect "a record matching two lines fails" 1 "matches 2 lines"
    teardown
}

test_stale_record_fails() {
    setup
    add_line skills/execute/SKILL.md 'The PR reports MERGED on a live read.'
    add_record skills/execute/SKILL.md 'reports MERGED on a live read' 'Describes GitHub PR state.'
    run_check
    expect "a stale record fails" 1 "stale"
    teardown
}

test_empty_reason_fails() {
    setup
    add_line skills/execute/SKILL.md 'The PR merged on GitHub.'
    add_record skills/execute/SKILL.md 'The PR merged on GitHub' ''
    run_check
    expect "a record with an empty reason fails" 1 "empty reason"
    teardown
}

test_file_outside_scanned_list_fails() {
    setup
    mkdir -p "$TEST_DIR/skills/other"
    add_line skills/other/SKILL.md 'The PR merged on GitHub.'
    add_record skills/other/SKILL.md 'The PR merged on GitHub' 'Describes GitHub PR state.'
    run_check
    expect "a record naming a file outside the scanned list fails" 1 "outside the scanned list"
    teardown
}

test_malformed_record_fails() {
    setup
    printf '%s\n' 'skills/execute/SKILL.md only-two-fields' >> "$TEST_DIR/scripts/check-merged-wording.allow"
    run_check
    expect "a record that is not tab-separated fails" 1 "not a tab-separated"
    teardown
}

test_real_repository_passes() {
    RC=0
    OUT=$(bash "$CHECK_SCRIPT" 2>&1) || RC=$?
    expect "the repository as it stands passes" 0
}

echo "Running check-merged-wording.sh tests..."
echo ""

test_clean_file_passes
test_unallowlisted_line_fails
test_work_on_is_scanned
test_accepted_tokens
test_accepted_token_does_not_hide_a_second_occurrence
test_record_covers_line
test_record_matching_zero_lines_fails
test_record_matching_two_lines_fails
test_stale_record_fails
test_empty_reason_fails
test_file_outside_scanned_list_fails
test_malformed_record_fails
test_real_repository_passes

echo ""
echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed"
[ "$FAIL_COUNT" -eq 0 ]
