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
EOF
    commit
    assert_fails "a root quoted apart from its path fails" "[bash-invocation] \$CLAUDE_PLUGIN_ROOT/skills/demo/scripts/run.sh"
    teardown
}

test_long_flag_fails() {
    setup
    add_script skills/demo/scripts/run.sh 755
    skill_md <<'EOF'
    bash -- "${CLAUDE_PLUGIN_ROOT}"/skills/demo/scripts/run.sh
EOF
    commit
    assert_fails "'bash -- <script>' fails" "[bash-invocation] \${CLAUDE_PLUGIN_ROOT}/skills/demo/scripts/run.sh"
    teardown
}

test_absolute_interpreter_fails() {
    setup
    add_script skills/demo/scripts/run.sh 755
    skill_md <<'EOF'
    /bin/bash "$CLAUDE_PLUGIN_ROOT"/skills/demo/scripts/run.sh
EOF
    commit
    assert_fails "'/bin/bash <script>' fails" "[bash-invocation] \$CLAUDE_PLUGIN_ROOT/skills/demo/scripts/run.sh"
    teardown
}

test_subject_is_the_final_sh() {
    setup
    mkdir -p "$TEST_DIR/repo/skills/demo/x.shared"
    add_script skills/demo/x.shared/run.sh 755
    skill_md <<'EOF'
Run `bash {{PLUGIN_ROOT}}/skills/demo/x.shared/run.sh --flag`.
EOF
    commit
    assert_fails "the subject runs to the operand's final .sh" "[bash-invocation] {{PLUGIN_ROOT}}/skills/demo/x.shared/run.sh"
    teardown
}

test_quoted_root_exec_bit_fails() {
    setup
    add_script skills/demo/scripts/run.sh 644
    skill_md <<'EOF'
    "$CLAUDE_PLUGIN_ROOT"/skills/demo/scripts/run.sh
EOF
    commit
    assert_fails "a double-quoted root is followed for the exec bit" "committed as 100644"
    teardown
}

test_single_quoted_root_exec_bit_fails() {
    setup
    add_script skills/demo/scripts/run.sh 644
    skill_md <<'EOF'
    '{{PLUGIN_ROOT}}/skills/demo/scripts/run.sh' --flag
EOF
    commit
    assert_fails "a single-quoted root is followed for the exec bit" "committed as 100644"
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

# A CRLF script run by path asks for an interpreter named `bash\r` and exits
# 127, which a preflight line's `|| true` swallows. The rule reads the working
# tree, so the fixture's CR survives whatever the host does to line endings on
# `git add`.
test_shebang_crlf_fails() {
    setup
    add_script skills/demo/scripts/run.sh 755 "$(printf '#!/usr/bin/env bash\r')"
    skill_md <<'EOF'
!`${CLAUDE_PLUGIN_ROOT}/skills/demo/scripts/run.sh demo 2>&1 || true`
EOF
    commit
    assert_fails "script with a CRLF #! line fails" "has a carriage return on its #! line"
    teardown
}

# The same script with LF endings, named the same way, passes. Every other
# passing fixture above is an LF script too.
test_shebang_lf_passes() {
    setup
    add_script skills/demo/scripts/run.sh 755 '#!/usr/bin/env bash'
    skill_md <<'EOF'
!`${CLAUDE_PLUGIN_ROOT}/skills/demo/scripts/run.sh demo 2>&1 || true`
EOF
    commit
    assert_passes "script with an LF #! line passes"
    teardown
}

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
    assert_fails "\${CLAUDE_SKILL_DIR} outside a skill cannot resolve" "and this file is not"
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
    assert_fails "an allowlist record naming an unknown rule fails" \
        "known rules: bash-invocation, exec-bit, shebang, unresolved"
    teardown
}

# The loader is shared with check-template-directives.sh (scripts/lib/
# allowlist.sh); this check's records still name a file in field 2, and the
# error says so.
test_allowlist_untabbed_record_fails() {
    setup
    skill_md <<'EOF'
Nothing to run.
EOF
    commit
    printf 'unresolved skills/demo/SKILL.md x.sh owner/repo#1 spaces, not tabs\n' > "$TEST_DIR/allow"
    assert_fails "an allowlist record that is not tab-separated fails, naming the file field" \
        "expected: <rule><TAB><file><TAB><subject>"
    teardown
}

# A record missing its subject would otherwise have its issue field reused as
# the subject and be accepted, deferring nothing anyone meant to defer.
test_allowlist_truncated_record_fails() {
    setup
    skill_md <<'EOF'
Nothing to run.
EOF
    commit
    printf 'exec-bit\tskills/demo/SKILL.md\towner/repo#1\n' > "$TEST_DIR/allow"
    assert_fails "an allowlist record with fewer than four fields fails" \
        "is not a tab-separated record"
    teardown
}

# -- scan coverage --------------------------------------------------------------

# scan_fails <repo-relative-path> -- a `bash x.sh` line in that file is found.
scan_fails() {
    local path="$1"
    setup
    add_script scripts/run.sh 755
    mkdir -p "$TEST_DIR/repo/$(dirname "$path")"
    printf 'Run `bash ${CLAUDE_PLUGIN_ROOT}/scripts/run.sh`.\n' > "$TEST_DIR/repo/$path"
    commit
    assert_fails "$path is scanned as a directive" "FAIL: $path:1 [bash-invocation]"
    teardown
}

# Every SKILL.md pulls in its extension file with `@`, so each line there is a
# directive, as is every line of the root CLAUDE.md and AGENTS.md.
test_extension_file_is_scanned() {
    scan_fails .claude/shirabe-extensions/demo.md
}

test_claude_md_is_scanned() {
    scan_fails CLAUDE.md
}

test_agents_md_is_scanned() {
    scan_fails AGENTS.md
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
test_long_flag_fails
test_absolute_interpreter_fails
test_subject_is_the_final_sh
test_quoted_root_exec_bit_fails
test_single_quoted_root_exec_bit_fails
test_bash_word_in_prose_passes
test_evals_are_not_scanned

test_exec_bit_set_passes
test_exec_bit_missing_fails
test_untracked_script_fails

test_shebang_missing_fails
test_shebang_crlf_fails
test_shebang_lf_passes

test_unresolved_fails
test_skill_dir_outside_skills_fails

test_allowlist_defers_finding
test_allowlist_record_without_issue_fails
test_allowlist_unknown_rule_fails
test_allowlist_untabbed_record_fails
test_allowlist_truncated_record_fails

test_extension_file_is_scanned
test_claude_md_is_scanned
test_agents_md_is_scanned

test_shipped_tree_passes

echo ""
echo "check-directive-invocations_test: $PASS_COUNT passed, $FAIL_COUNT failed"
[ "$FAIL_COUNT" -eq 0 ] || exit 1
exit 0
