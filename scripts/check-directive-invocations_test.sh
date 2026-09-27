#!/usr/bin/env bash
set -euo pipefail

# Tests for check-directive-invocations.sh.
#
# Each test builds a throwaway git repository shaped like shirabe (a skills/
# tree with a SKILL.md and a script) and points the check at it. The exec-bit
# rule reads the committed mode, so the fixture has to be a real repository
# rather than a directory of files.
#
# Every rule gets one fixture that passes and one that fails, so a rule that
# never fires cannot hide behind a green run.
#
# Usage:
#   scripts/check-directive-invocations_test.sh
#
# Exit codes:
#   0 - all tests passed
#   1 - one or more tests failed

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHECK_SCRIPT="$SCRIPT_DIR/check-directive-invocations.sh"

TEST_DIR=""
PASS_COUNT=0
FAIL_COUNT=0

setup() {
    TEST_DIR=$(mktemp -d)
    mkdir -p "$TEST_DIR/repo/skills/demo/scripts" "$TEST_DIR/repo/scripts"
    git -C "$TEST_DIR/repo" init -q
    : > "$TEST_DIR/allow"
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

# skill_md -- the fixture's directive file, from stdin.
skill_md() {
    cat > "$TEST_DIR/repo/skills/demo/SKILL.md"
}

# add_script <repo-relative-path> <mode: 755|644> [first-line]
add_script() {
    local path="$1" mode="$2" first="${3-#!/usr/bin/env bash}"
    printf '%s\necho ok\n' "$first" > "$TEST_DIR/repo/$path"
    chmod "$mode" "$TEST_DIR/repo/$path"
}

# commit -- stage everything. The check reads modes from the index, so staging
# is enough; core.fileMode is forced on so a host configured otherwise still
# records the mode the fixture chose.
commit() {
    git -C "$TEST_DIR/repo" -c core.fileMode=true add -A
}

run_check() {
    DIRECTIVE_INVOCATIONS_ROOT="$TEST_DIR/repo" \
        DIRECTIVE_INVOCATIONS_ALLOWLIST="$TEST_DIR/allow" \
        "$CHECK_SCRIPT" 2>&1
}

assert_fails() {
    local name="$1" needle="$2"
    local output status=0
    output=$(run_check) || status=$?

    if [ "$status" -eq 0 ]; then
        fail "$name" "expected a non-zero exit, got 0. Output: $output"
        return
    fi
    case "$output" in
        *"$needle"*) pass "$name" ;;
        *) fail "$name" "expected output containing '$needle'. Output: $output" ;;
    esac
}

assert_passes() {
    local name="$1"
    local output status=0
    output=$(run_check) || status=$?

    if [ "$status" -eq 0 ]; then
        pass "$name"
    else
        fail "$name" "expected exit 0, got $status. Output: $output"
    fi
}

# -- bash-invocation ----------------------------------------------------------

test_by_path_passes() {
    setup
    add_script skills/demo/scripts/run.sh 755
    skill_md <<'EOF'
---
allowed-tools: Bash(${CLAUDE_PLUGIN_ROOT}/skills/demo/scripts/run.sh *), Bash(true)
---

!`${CLAUDE_PLUGIN_ROOT}/skills/demo/scripts/run.sh demo 2>&1 || true`

Run `{{PLUGIN_ROOT}}/skills/demo/scripts/run.sh --flag`, then carry on.
EOF
    commit
    assert_passes "script run by path passes"
    teardown
}

test_bash_invocation_fails() {
    setup
    add_script skills/demo/scripts/run.sh 755
    skill_md <<'EOF'
Run `bash {{PLUGIN_ROOT}}/skills/demo/scripts/run.sh --flag`, then carry on.
EOF
    commit
    assert_fails "'bash <script>' in a directive fails" "[bash-invocation] {{PLUGIN_ROOT}}/skills/demo/scripts/run.sh"
    teardown
}

test_bash_in_permission_pattern_fails() {
    setup
    add_script scripts/preflight.sh 755
    skill_md <<'EOF'
---
allowed-tools: Bash(bash ${CLAUDE_PLUGIN_ROOT}/scripts/preflight.sh *), Bash(true)
---
EOF
    commit
    assert_fails "'Bash(bash <script> *)' permission pattern fails" "[bash-invocation]"
    teardown
}

test_sh_with_flag_fails() {
    setup
    add_script skills/demo/scripts/run.sh 755
    skill_md <<'EOF'
    X=$(sh -e "$CLAUDE_PLUGIN_ROOT/skills/demo/scripts/run.sh")
EOF
    commit
    assert_fails "'sh -e \"<script>\"' fails" "[bash-invocation]"
    teardown
}

test_quoted_root_fails() {
    setup
    add_script skills/demo/scripts/run.sh 755
    skill_md <<'EOF'
    bash "$CLAUDE_PLUGIN_ROOT"/skills/demo/scripts/run.sh
    bash -- "${CLAUDE_PLUGIN_ROOT}"/skills/demo/scripts/run.sh
EOF
    commit
    assert_fails "a root quoted apart from its path, after a long flag, fails" "[bash-invocation] \$CLAUDE_PLUGIN_ROOT/skills/demo/scripts/run.sh"
    teardown
}

test_quoted_root_exec_bit_fails() {
    setup
    add_script skills/demo/scripts/run.sh 644
    skill_md <<'EOF'
    "$CLAUDE_PLUGIN_ROOT"/skills/demo/scripts/run.sh
EOF
    commit
    assert_fails "a quoted root is followed for the exec bit" "committed as 100644"
    teardown
}

test_bash_word_in_prose_passes() {
    setup
    add_script skills/demo/scripts/run.sh 755
    skill_md <<'EOF'
The script needs bash 3.2 or later; run.sh and push.sh share a helper.
EOF
    commit
    assert_passes "'bash' in prose without a script operand passes"
    teardown
}

test_evals_are_not_scanned() {
    setup
    add_script skills/demo/scripts/run.sh 755
    skill_md <<'EOF'
Run `{{PLUGIN_ROOT}}/skills/demo/scripts/run.sh`.
EOF
    mkdir -p "$TEST_DIR/repo/skills/demo/evals/fixtures"
    printf 'bash {{PLUGIN_ROOT}}/skills/demo/scripts/run.sh\n' \
        > "$TEST_DIR/repo/skills/demo/evals/fixtures/old.md"
    commit
    assert_passes "eval fixtures are test data, not directives"
    teardown
}

# -- exec-bit -----------------------------------------------------------------

test_exec_bit_set_passes() {
    setup
    add_script skills/demo/scripts/run.sh 755
    skill_md <<'EOF'
Run `${CLAUDE_SKILL_DIR}/scripts/run.sh`.
EOF
    commit
    assert_passes "script committed 100755 passes"
    teardown
}

test_exec_bit_missing_fails() {
    setup
    add_script skills/demo/scripts/run.sh 644
    skill_md <<'EOF'
Run `${CLAUDE_SKILL_DIR}/scripts/run.sh`.
EOF
    commit
    assert_fails "script committed 100644 fails" "committed as 100644"
    teardown
}

test_untracked_script_fails() {
    setup
    skill_md <<'EOF'
Run `{{PLUGIN_ROOT}}/scripts/late.sh`.
EOF
    commit
    add_script scripts/late.sh 755
    assert_fails "script present but never committed fails" "is not committed"
    teardown
}

# -- shebang ------------------------------------------------------------------

test_shebang_missing_fails() {
    setup
    add_script skills/demo/scripts/run.sh 755 'echo start'
    skill_md <<'EOF'
Run `{{PLUGIN_ROOT}}/skills/demo/scripts/run.sh`.
EOF
    commit
    assert_fails "script with no #! line fails" "[shebang]"
    teardown
}

# The passing half of the shebang rule is every passing fixture above: each
# script starts with #!/usr/bin/env bash and the check stays green.

# -- unresolved ---------------------------------------------------------------

test_unresolved_fails() {
    setup
    skill_md <<'EOF'
Run `{{PLUGIN_ROOT}}/skills/demo/scripts/missing.sh`.
EOF
    commit
    assert_fails "root-anchored path naming no file fails" "[unresolved]"
    teardown
}

test_skill_dir_outside_skills_fails() {
    setup
    mkdir -p "$TEST_DIR/repo/references"
    printf 'Run `${CLAUDE_SKILL_DIR}/scripts/run.sh`.\n' > "$TEST_DIR/repo/references/guide.md"
    commit
    assert_fails "\${CLAUDE_SKILL_DIR} outside a skill cannot resolve" "[unresolved]"
    teardown
}

# -- allowlist ----------------------------------------------------------------

test_allowlist_defers_finding() {
    setup
    skill_md <<'EOF'
Run `{{PLUGIN_ROOT}}/scripts/private-only.sh`.
EOF
    commit
    printf 'unresolved\tskills/demo/SKILL.md\t{{PLUGIN_ROOT}}/scripts/private-only.sh\towner/repo#80\tlives in another plugin\n' \
        > "$TEST_DIR/allow"
    assert_passes "an allowlisted finding with an issue reference is deferred"
    teardown
}

test_allowlist_record_without_issue_fails() {
    setup
    skill_md <<'EOF'
Run `{{PLUGIN_ROOT}}/scripts/private-only.sh`.
EOF
    commit
    printf 'unresolved\tskills/demo/SKILL.md\t{{PLUGIN_ROOT}}/scripts/private-only.sh\tsoon\tno ticket\n' \
        > "$TEST_DIR/allow"
    assert_fails "an allowlist record without an issue reference fails" "has no issue reference"
    teardown
}

test_allowlist_unknown_rule_fails() {
    setup
    skill_md <<'EOF'
Nothing to run.
EOF
    commit
    printf 'no-such-rule\tskills/demo/SKILL.md\tx.sh\towner/repo#1\treason\n' > "$TEST_DIR/allow"
    assert_fails "an allowlist record naming an unknown rule fails" "unknown rule"
    teardown
}

# -- the shipped tree -----------------------------------------------------------

test_shipped_tree_passes() {
    local output status=0
    output=$("$CHECK_SCRIPT" 2>&1) || status=$?
    if [ "$status" -eq 0 ]; then
        pass "the shipped directives pass ($output)"
    else
        fail "the shipped directives pass" "exit $status. Output: $output"
    fi
}

test_by_path_passes
test_bash_invocation_fails
test_bash_in_permission_pattern_fails
test_sh_with_flag_fails
test_quoted_root_fails
test_quoted_root_exec_bit_fails
test_bash_word_in_prose_passes
test_evals_are_not_scanned

test_exec_bit_set_passes
test_exec_bit_missing_fails
test_untracked_script_fails

test_shebang_missing_fails

test_unresolved_fails
test_skill_dir_outside_skills_fails

test_allowlist_defers_finding
test_allowlist_record_without_issue_fails
test_allowlist_unknown_rule_fails

test_shipped_tree_passes

echo ""
echo "check-directive-invocations_test: $PASS_COUNT passed, $FAIL_COUNT failed"
[ "$FAIL_COUNT" -eq 0 ] || exit 1
exit 0
