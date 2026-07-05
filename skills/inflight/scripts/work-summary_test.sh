#!/usr/bin/env bash
#
# work-summary_test.sh - Tests for work-summary.sh
#
# Standalone (bash work-summary_test.sh), no network. `gh` is stubbed via a
# PATH-independent GH override variable pointing at a fixture script. Timing is
# controlled via WS_NOW; the store is isolated via WS_STORE_DIR.
#
# Coverage:
#   - capture URL regex fixtures (valid accepted; /pull/new/ rejected; flag-
#     injection owner rejected; non-github rejected; URL-in-surrounding-text
#     extracted)
#   - the terminal-safety sanitizer (ANSI stripped, newline removed, `|`
#     removed, marker substring forbidden, truncation after strip)
#   - gate transitions (unchanged ledger -> suppress; ledger change -> emit;
#     terminal PR -> shown once then dropped)
#   - attention-first ordering
#
# Usage:
#   bash work-summary_test.sh
#
# Exit codes:
#   0 - All tests passed
#   1 - One or more tests failed

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMPONENT="$SCRIPT_DIR/work-summary.sh"
PASS_COUNT=0
FAIL_COUNT=0
WORKDIR=""
GH_STUB=""
GH_STATE_DIR=""

pass() { echo "PASS: $1"; PASS_COUNT=$((PASS_COUNT + 1)); }
fail() { echo "FAIL: $1 - $2" >&2; FAIL_COUNT=$((FAIL_COUNT + 1)); }

assert_eq() {
    local name="$1" expected="$2" actual="$3"
    if [[ "$expected" == "$actual" ]]; then
        pass "$name"
    else
        fail "$name" "expected [$expected], got [$actual]"
    fi
}

assert_contains() {
    local name="$1" haystack="$2" needle="$3"
    if [[ "$haystack" == *"$needle"* ]]; then
        pass "$name"
    else
        fail "$name" "expected to contain [$needle], got [$haystack]"
    fi
}

assert_not_contains() {
    local name="$1" haystack="$2" needle="$3"
    if [[ "$haystack" != *"$needle"* ]]; then
        pass "$name"
    else
        fail "$name" "expected NOT to contain [$needle], got [$haystack]"
    fi
}

# --- gh stub ---------------------------------------------------------------
# The stub answers `pr view <url> --json ...` by reading a per-PR-number JSON
# file from $GH_STATE_DIR (keyed by the trailing number of the URL). If the file
# is missing or GH_FAIL is set, it exits non-zero (simulating gh unreachable).
setup_gh_stub() {
    GH_STATE_DIR="$WORKDIR/ghstate"
    mkdir -p "$GH_STATE_DIR"
    GH_STUB="$WORKDIR/gh-stub.sh"
    cat > "$GH_STUB" <<'STUB'
#!/usr/bin/env bash
# gh stub: only supports `pr view <url> --json ...`
if [[ -n "${GH_FAIL:-}" ]]; then
    echo "could not connect" >&2
    exit 1
fi
url=""
for a in "$@"; do
    case "$a" in
        https://*) url="$a" ;;
    esac
done
num="${url##*/}"
f="${GH_STATE_DIR}/${num}.json"
if [[ -f "$f" ]]; then
    cat "$f"
    exit 0
fi
echo "no such PR" >&2
exit 1
STUB
    chmod +x "$GH_STUB"
}

set_pr_state() {
    # set_pr_state <number> <json>
    printf '%s' "$2" > "$GH_STATE_DIR/$1.json"
}

# Build a PostToolUse hook JSON payload for capture stdin.
hook_json() {
    # hook_json <command> <stdout>
    jq -n --arg c "$1" --arg o "$2" \
        '{tool_input: {command: $c}, tool_response: {stdout: $o}}'
}

run_capture() {
    # run_capture <sid> <command> <stdout> [extra env assignments...]
    local sid="$1" cmd="$2" out="$3"; shift 3
    hook_json "$cmd" "$out" | env GH="$GH_STUB" GH_STATE_DIR="$GH_STATE_DIR" WS_STORE_DIR="$WORKDIR/store" "$@" \
        bash "$COMPONENT" capture --session "$sid"
}

run_render() {
    local sid="$1"; shift
    env GH="$GH_STUB" GH_STATE_DIR="$GH_STATE_DIR" WS_STORE_DIR="$WORKDIR/store" "$@" \
        bash "$COMPONENT" render --session "$sid"
}

setup() {
    WORKDIR=$(mktemp -d)
    mkdir -p "$WORKDIR/store"
    setup_gh_stub
}

teardown() {
    [[ -n "$WORKDIR" ]] && rm -rf "$WORKDIR"
}

# ===========================================================================
# 1. URL regex / extraction (functions sourced directly)
# ===========================================================================
# shellcheck source=/dev/null
source "$COMPONENT"

test_url_regex() {
    local u
    # valid bare PR URL accepted
    if u=$(extract_pr_url "https://github.com/owner/repo/pull/42"); then
        assert_eq "valid PR URL accepted" "https://github.com/owner/repo/pull/42" "$u"
    else
        fail "valid PR URL accepted" "extract returned non-zero"
    fi

    # /pull/new/ hint rejected
    if extract_pr_url "https://github.com/owner/repo/pull/new/my-branch" >/dev/null; then
        fail "/pull/new/ rejected" "extractor accepted a /pull/new/ hint"
    else
        pass "/pull/new/ rejected"
    fi

    # flag-injection-shaped owner rejected
    if extract_pr_url "https://github.com/-x/repo/pull/1" >/dev/null; then
        fail "flag-injection owner (-x) rejected" "extractor accepted -x owner"
    else
        pass "flag-injection owner (-x) rejected"
    fi
    if extract_pr_url "https://github.com/--foo/repo/pull/1" >/dev/null; then
        fail "flag-injection owner (--foo) rejected" "extractor accepted --foo owner"
    else
        pass "flag-injection owner (--foo) rejected"
    fi

    # non-github URL rejected
    if extract_pr_url "https://gitlab.com/owner/repo/pull/1" >/dev/null; then
        fail "non-github URL rejected" "extractor accepted gitlab URL"
    else
        pass "non-github URL rejected"
    fi

    # URL embedded in surrounding text extracted correctly
    if u=$(extract_pr_url "Created PR: https://github.com/acme/tool/pull/7 (done)"); then
        assert_eq "URL in surrounding text extracted" "https://github.com/acme/tool/pull/7" "$u"
    else
        fail "URL in surrounding text extracted" "extract returned non-zero"
    fi

    # validate_pr_url anchoring: trailing path is not a bare match
    if validate_pr_url "https://github.com/o/r/pull/7/files"; then
        fail "validate_pr_url rejects trailing path" "accepted /pull/7/files"
    else
        pass "validate_pr_url rejects trailing path"
    fi
}

# ===========================================================================
# 2. Sanitizer
# ===========================================================================
test_sanitizer() {
    local out
    # ANSI stripped
    out=$(sanitize "$(printf 'hel\x1b[31mlo')")
    assert_eq "sanitizer strips ANSI" "hello" "$out"

    # newline removed
    out=$(sanitize "$(printf 'a\nb')")
    assert_eq "sanitizer removes newline" "ab" "$out"

    # pipe removed
    out=$(sanitize "a|b|c")
    assert_eq "sanitizer removes pipe" "abc" "$out"

    # marker substring forbidden
    out=$(sanitize "before === WORK IN FLIGHT === after")
    assert_not_contains "sanitizer forbids marker substring" "$out" "=== WORK IN FLIGHT ==="

    # truncation after strip: 60 'a' chars with an ANSI prefix -> 50 chars, no ESC
    out=$(sanitize "$(printf '\x1b[1m%s' "$(printf 'a%.0s' {1..60})")")
    assert_eq "sanitizer truncates to 50 after strip" "50" "${#out}"
    assert_not_contains "sanitizer truncation leaves no ESC" "$out" "$(printf '\x1b')"
}

# ===========================================================================
# 3. Capture + gate transitions (subprocess)
# ===========================================================================
test_capture_and_gate() {
    setup
    local sid="sess-1"
    set_pr_state 42 '{"state":"OPEN","isDraft":false,"statusCheckRollup":[{"status":"COMPLETED","conclusion":"SUCCESS"}],"reviewDecision":"","title":"add feature"}'

    # Ledger change -> emit
    local out
    out=$(run_capture "$sid" "gh pr create --fill" "https://github.com/owner/repo/pull/42" WS_NOW=1000)
    assert_contains "capture emits block on new PR" "$out" "=== WORK IN FLIGHT ==="
    assert_contains "capture block has PR line" "$out" "owner/repo#42 | open ci:passing | add feature | https://github.com/owner/repo/pull/42"
    assert_contains "capture block has freshness line" "$out" "updated "

    # Unchanged ledger, within render interval -> suppress
    out=$(run_capture "$sid" "echo hello" "" WS_NOW=1010)
    assert_eq "unchanged ledger suppresses (empty output)" "" "$out"

    # Non-PR gh push with /pull/new/ hint -> not captured, still suppressed
    out=$(run_capture "$sid" "git push origin HEAD" "remote: https://github.com/owner/repo/pull/new/feature-branch" WS_NOW=1020)
    assert_eq "git push /pull/new/ not captured" "" "$out"
    # ledger should still have exactly one row
    local rows
    rows=$(wc -l < "$WORKDIR/store/$sid.ledger")
    assert_eq "ledger still has one row after push" "1" "$rows"

    # Second PR -> ledger change -> emit with both
    set_pr_state 43 '{"state":"OPEN","isDraft":true,"statusCheckRollup":[{"status":"IN_PROGRESS","conclusion":null}],"reviewDecision":"","title":"second"}'
    out=$(run_capture "$sid" "gh pr create --fill" "https://github.com/owner/repo/pull/43" WS_NOW=1030)
    assert_contains "second PR emits" "$out" "owner/repo#43 | draft ci:pending | second |"
    assert_contains "second PR block still lists first" "$out" "owner/repo#42"

    # Duplicate capture of same URL -> no new row, suppressed
    out=$(run_capture "$sid" "gh pr create --fill" "https://github.com/owner/repo/pull/43" WS_NOW=1040)
    rows=$(wc -l < "$WORKDIR/store/$sid.ledger")
    assert_eq "duplicate URL not appended" "2" "$rows"
    assert_eq "duplicate capture suppressed" "" "$out"

    teardown
}

# ===========================================================================
# 4. Expensive-level gate: status flip after interval
# ===========================================================================
test_expensive_gate() {
    setup
    local sid="sess-exp"
    set_pr_state 5 '{"state":"OPEN","isDraft":false,"statusCheckRollup":[{"status":"IN_PROGRESS","conclusion":null}],"reviewDecision":"","title":"t"}'
    local out
    out=$(run_capture "$sid" "gh pr create --fill" "https://github.com/o/r/pull/5" WS_NOW=1000 WS_RENDER_INTERVAL=300)
    assert_contains "initial emit pending" "$out" "open ci:pending"

    # within interval, no change -> suppress even though we call again
    out=$(run_capture "$sid" "echo x" "" WS_NOW=1100 WS_RENDER_INTERVAL=300)
    assert_eq "within interval suppressed" "" "$out"

    # flip CI to passing; still within interval -> suppressed (ledger unchanged)
    set_pr_state 5 '{"state":"OPEN","isDraft":false,"statusCheckRollup":[{"status":"COMPLETED","conclusion":"SUCCESS"}],"reviewDecision":"","title":"t"}'
    out=$(run_capture "$sid" "echo x" "" WS_NOW=1200 WS_RENDER_INTERVAL=300)
    assert_eq "status flip within interval suppressed" "" "$out"

    # now past interval -> expensive level re-renders, block changed -> emit
    out=$(run_capture "$sid" "echo x" "" WS_NOW=1400 WS_RENDER_INTERVAL=300)
    assert_contains "status flip past interval emits" "$out" "open ci:passing"

    teardown
}

# ===========================================================================
# 5. Terminal-drop: shown once then dropped
# ===========================================================================
test_terminal_drop() {
    setup
    local sid="sess-term"
    set_pr_state 9 '{"state":"OPEN","isDraft":false,"statusCheckRollup":[],"reviewDecision":"","title":"tt"}'
    run_capture "$sid" "gh pr create --fill" "https://github.com/o/r/pull/9" WS_NOW=1000 >/dev/null

    # Mark merged; render once -> shows merged
    set_pr_state 9 '{"state":"MERGED","isDraft":false,"statusCheckRollup":[],"reviewDecision":"","title":"tt"}'
    local out
    out=$(run_render "$sid" WS_NOW=1100)
    assert_contains "terminal PR shown once" "$out" "o/r#9 | merged |"

    # Render again -> dropped (ledger empty of visible items => no output)
    out=$(run_render "$sid" WS_NOW=1200)
    assert_not_contains "terminal PR dropped on next render" "$out" "o/r#9"

    teardown
}

# ===========================================================================
# 6. Attention-first ordering
# ===========================================================================
test_ordering() {
    setup
    local sid="sess-order"
    # #1 open passing (in progress), #2 failing (attention), #3 will merge later.
    # Capture #3 while OPEN so its one terminal showing is not consumed at capture
    # time; the render below is the first render to observe it as merged.
    set_pr_state 1 '{"state":"OPEN","isDraft":false,"statusCheckRollup":[{"status":"COMPLETED","conclusion":"SUCCESS"}],"reviewDecision":"","title":"one"}'
    set_pr_state 2 '{"state":"OPEN","isDraft":false,"statusCheckRollup":[{"status":"COMPLETED","conclusion":"FAILURE"}],"reviewDecision":"","title":"two"}'
    set_pr_state 3 '{"state":"OPEN","isDraft":false,"statusCheckRollup":[],"reviewDecision":"","title":"three"}'
    run_capture "$sid" "gh pr create" "https://github.com/o/r/pull/1" WS_NOW=1000 >/dev/null
    run_capture "$sid" "gh pr create" "https://github.com/o/r/pull/2" WS_NOW=1001 >/dev/null
    run_capture "$sid" "gh pr create" "https://github.com/o/r/pull/3" WS_NOW=1002 >/dev/null
    set_pr_state 3 '{"state":"MERGED","isDraft":false,"statusCheckRollup":[],"reviewDecision":"","title":"three"}'

    local out
    out=$(run_render "$sid" WS_NOW=1100)
    # order: attention (#2), in progress (#1), settled (#3)
    local order
    order=$(printf '%s\n' "$out" | grep -oE 'o/r#[0-9]+' | tr '\n' ' ')
    assert_eq "attention-first ordering" "o/r#2 o/r#1 o/r#3 " "$order"

    teardown
}

# ===========================================================================
# 7. Offline degradation
# ===========================================================================
test_offline() {
    setup
    local sid="sess-off"
    set_pr_state 1 '{"state":"OPEN","isDraft":false,"statusCheckRollup":[],"reviewDecision":"","title":"x"}'
    run_capture "$sid" "gh pr create" "https://github.com/o/r/pull/1" WS_NOW=1000 >/dev/null

    local out
    out=$(run_render "$sid" WS_NOW=1100 GH_FAIL=1)
    assert_contains "offline block has marker" "$out" "=== WORK IN FLIGHT ==="
    assert_contains "offline block marked best-effort" "$out" "(best-effort: live state unavailable)"
    assert_contains "offline block keeps URL" "$out" "https://github.com/o/r/pull/1"

    teardown
}

# ===========================================================================
# 8. Empty ledger render -> no output; help spec present
# ===========================================================================
test_empty_and_help() {
    setup
    local sid="sess-empty"
    local out
    out=$(run_render "$sid" WS_NOW=1000)
    assert_eq "empty ledger render is silent" "" "$out"

    out=$(env WS_STORE_DIR="$WORKDIR/store" bash "$COMPONENT" help)
    assert_contains "help prints marker spec" "$out" "=== WORK IN FLIGHT ==="
    assert_contains "help documents subcommands" "$out" "capture | render | absence | compact | help"

    # invalid session id rejected (fail-safe, exit 0, no output)
    out=$(env WS_STORE_DIR="$WORKDIR/store" bash "$COMPONENT" render --session "bad;rm -rf" 2>/dev/null)
    assert_eq "invalid sid rejected silently" "" "$out"

    teardown
}

# ===========================================================================
# 9. Section headers above 6 items
# ===========================================================================
test_sections() {
    setup
    local sid="sess-sections"
    local i
    for i in 1 2 3 4 5 6 7; do
        set_pr_state "$i" "{\"state\":\"OPEN\",\"isDraft\":false,\"statusCheckRollup\":[{\"status\":\"COMPLETED\",\"conclusion\":\"SUCCESS\"}],\"reviewDecision\":\"\",\"title\":\"t$i\"}"
        run_capture "$sid" "gh pr create" "https://github.com/o/r/pull/$i" WS_NOW=$((1000 + i)) >/dev/null
    done
    local out
    out=$(run_render "$sid" WS_NOW=1100)
    assert_contains "sections appear above 6 items" "$out" "## In progress"

    teardown
}

# --- run all ---------------------------------------------------------------
test_url_regex
test_sanitizer
test_capture_and_gate
test_expensive_gate
test_terminal_drop
test_ordering
test_offline
test_empty_and_help
test_sections

echo ""
echo "================================"
echo "PASS: $PASS_COUNT  FAIL: $FAIL_COUNT"
echo "================================"
[[ $FAIL_COUNT -eq 0 ]]
