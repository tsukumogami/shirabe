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

run_compact() {
    local sid="$1"; shift
    env GH="$GH_STUB" GH_STATE_DIR="$GH_STATE_DIR" WS_STORE_DIR="$WORKDIR/store" "$@" \
        bash "$COMPONENT" compact --session "$sid"
}

run_absence() {
    local sid="$1"; shift
    env GH="$GH_STUB" GH_STATE_DIR="$GH_STATE_DIR" WS_STORE_DIR="$WORKDIR/store" "$@" \
        bash "$COMPONENT" absence --session "$sid"
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
# 5. Terminal-drop (AMBIENT path): shown once then dropped.
# On-demand render is pure (see test_render_pure); the show-once-then-drop R3
# behavior lives on the ambient paths (capture/absence/compact). We drive it
# here with compact, which renders-and-consumes when the ledger is non-empty.
# ===========================================================================
test_terminal_drop() {
    setup
    local sid="sess-term"
    set_pr_state 9 '{"state":"OPEN","isDraft":false,"statusCheckRollup":[],"reviewDecision":"","title":"tt"}'
    run_capture "$sid" "gh pr create --fill" "https://github.com/o/r/pull/9" WS_NOW=1000 >/dev/null

    # Mark merged; ambient compact once -> shows merged and consumes the showing.
    set_pr_state 9 '{"state":"MERGED","isDraft":false,"statusCheckRollup":[],"reviewDecision":"","title":"tt"}'
    local out
    out=$(run_compact "$sid" WS_NOW=1100)
    assert_contains "terminal PR shown once (ambient)" "$out" "o/r#9 | merged |"

    # Ambient compact again -> dropped (already-shown terminal excluded).
    out=$(run_compact "$sid" WS_NOW=1200)
    assert_not_contains "terminal PR dropped on next ambient fire" "$out" "o/r#9"

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

# ===========================================================================
# 10. C1 control strip (FIX 1): UTF-8 two-byte C1 (0xC2 0x9x) and raw C1 bytes
#     do not survive the sanitizer / the block.
# ===========================================================================
test_c1_strip() {
    # 0x9D=OSC, 0x9C=ST, 0x9B=CSI in their valid-UTF-8 two-byte form.
    local title out
    title=$(printf 'a\xc2\x9db\xc2\x9cc\xc2\x9bd')
    out=$(sanitize "$title")
    assert_eq "sanitizer strips UTF-8 C1 (0xC2 0x9x)" "abcd" "$out"
    # No byte in the C1 UTF-8 range remains.
    if printf '%s' "$out" | LC_ALL=C grep -q $'\xc2[\x80-\x9f]'; then
        fail "sanitizer leaves no UTF-8 C1 sequence" "found a 0xC2 0x8x/0x9x byte pair"
    else
        pass "sanitizer leaves no UTF-8 C1 sequence"
    fi

    # Raw C1 bytes (0x80-0x9F, not part of a UTF-8 sequence) are also stripped.
    title=$(printf 'x\x9dy\x9bz')
    out=$(sanitize "$title")
    assert_eq "sanitizer strips raw C1 bytes" "xyz" "$out"

    # End-to-end: a C1-laden PR title never reaches the rendered block.
    setup
    local sid="sess-c1"
    local t
    t=$(printf 'evil\xc2\x9d]8;;http://x\xc2\x9c\\\\link\xc2\x9b31m')
    set_pr_state 1 "$(jq -n --arg t "$t" '{state:"OPEN",isDraft:false,statusCheckRollup:[],reviewDecision:"",title:$t}')"
    run_capture "$sid" "gh pr create" "https://github.com/o/r/pull/1" WS_NOW=1000 >/dev/null
    local block
    block=$(run_render "$sid" WS_NOW=1100)
    if printf '%s' "$block" | LC_ALL=C grep -q $'\xc2[\x80-\x9f]'; then
        fail "block carries no UTF-8 C1 sequence" "block contains a C1 byte pair"
    else
        pass "block carries no UTF-8 C1 sequence"
    fi
    if printf '%s' "$block" | LC_ALL=C grep -q $'[\x80-\x9f]'; then
        fail "block carries no raw C1 byte" "block contains a raw C1 byte"
    else
        pass "block carries no raw C1 byte"
    fi
    teardown
}

# ===========================================================================
# 11. Expensive-gate SUPPRESS-on-no-change past the interval (FIX 2 regression).
#     A stable PR with no state change must NOT be re-emitted every interval
#     just because the freshness timestamp advanced.
# ===========================================================================
test_gate_suppress_no_change() {
    setup
    local sid="sess-nochange"
    set_pr_state 7 '{"state":"OPEN","isDraft":false,"statusCheckRollup":[{"status":"COMPLETED","conclusion":"SUCCESS"}],"reviewDecision":"","title":"stable"}'
    local out
    out=$(run_capture "$sid" "gh pr create" "https://github.com/o/r/pull/7" WS_NOW=1000 WS_RENDER_INTERVAL=300)
    assert_contains "stable PR initial emit" "$out" "open ci:passing"

    # Past the interval, no state change -> must SUPPRESS (only the timestamp
    # would differ; that is excluded from the dedup hash).
    out=$(run_capture "$sid" "echo x" "" WS_NOW=1400 WS_RENDER_INTERVAL=300)
    assert_eq "no-change past interval suppressed (1st)" "" "$out"

    # And again a full interval later -> still SUPPRESS.
    out=$(run_capture "$sid" "echo x" "" WS_NOW=1800 WS_RENDER_INTERVAL=300)
    assert_eq "no-change past interval suppressed (2nd)" "" "$out"

    teardown
}

# ===========================================================================
# 12. is_pr_create false positives (FIX 3): a command that merely CONTAINS the
#     text "gh pr create" (as data) must not capture a PR.
# ===========================================================================
test_is_pr_create_false_positive() {
    setup
    local sid="sess-fp"
    set_pr_state 1 '{"state":"OPEN","isDraft":false,"statusCheckRollup":[],"reviewDecision":"","title":"x"}'
    local out
    # grep whose quoted pattern is `gh pr create` and whose stdout is a PR URL.
    out=$(run_capture "$sid" "grep 'gh pr create' notes.txt" "match: https://github.com/o/r/pull/1" WS_NOW=1000)
    assert_eq "grep 'gh pr create' emits nothing" "" "$out"
    if [[ -f "$WORKDIR/store/$sid.ledger" ]]; then
        fail "grep false-positive does not create a ledger row" "ledger file was created"
    else
        pass "grep false-positive does not create a ledger row"
    fi

    # echo / cat with the text as an argument, also carrying a PR URL in stdout.
    out=$(run_capture "$sid" "echo gh pr create" "https://github.com/o/r/pull/1" WS_NOW=1001)
    assert_eq "echo gh pr create emits nothing" "" "$out"

    # Positive control: a real invocation with a leading env-assignment DOES
    # capture (anchored gh command + bare pr/create argv tokens).
    out=$(run_capture "$sid" "GH_TOKEN=xxx gh pr create --fill" "https://github.com/o/r/pull/1" WS_NOW=1002)
    assert_contains "env-prefixed real gh pr create captures" "$out" "o/r#1"

    teardown
}

# ===========================================================================
# 13. On-demand render is PURE (FIX 4): repeated renders of a merged PR both
#     show it (no consumption), while the ambient path still drops after one.
# ===========================================================================
test_render_pure() {
    setup
    local sid="sess-pure"
    set_pr_state 4 '{"state":"OPEN","isDraft":false,"statusCheckRollup":[],"reviewDecision":"","title":"pp"}'
    run_capture "$sid" "gh pr create" "https://github.com/o/r/pull/4" WS_NOW=1000 >/dev/null
    set_pr_state 4 '{"state":"MERGED","isDraft":false,"statusCheckRollup":[],"reviewDecision":"","title":"pp"}'

    local out
    out=$(run_render "$sid" WS_NOW=1100)
    assert_contains "pure render shows merged (1st)" "$out" "o/r#4 | merged |"
    out=$(run_render "$sid" WS_NOW=1200)
    assert_contains "pure render still shows merged (2nd)" "$out" "o/r#4 | merged |"

    # Gate state untouched: a subsequent ambient compact still gets its single
    # post-transition showing, then drops.
    out=$(run_compact "$sid" WS_NOW=1300)
    assert_contains "ambient still shows once after pure renders" "$out" "o/r#4 | merged |"
    out=$(run_compact "$sid" WS_NOW=1400)
    assert_not_contains "ambient drops after its one showing" "$out" "o/r#4"

    teardown
}

# ===========================================================================
# 14. Symlinked per-session file refused (FIX 5): a pre-planted symlinked
#     .ledger is refused; the symlink target is not written.
# ===========================================================================
test_symlink_refused() {
    setup
    local sid="sess-sym"
    local target="$WORKDIR/outside.txt"
    : > "$target"
    ln -s "$target" "$WORKDIR/store/$sid.ledger"
    set_pr_state 1 '{"state":"OPEN","isDraft":false,"statusCheckRollup":[],"reviewDecision":"","title":"x"}'
    local out
    out=$(run_capture "$sid" "gh pr create" "https://github.com/o/r/pull/1" WS_NOW=1000)
    assert_eq "symlinked ledger refused (no output)" "" "$out"
    local tsize
    tsize=$(wc -c < "$target")
    assert_eq "symlink target not written" "0" "$tsize"
    teardown
}

# ===========================================================================
# 15. Concurrency (flock contract): N simultaneous captures produce N distinct
#     rows with no corruption.
# ===========================================================================
test_concurrency() {
    setup
    local sid="sess-conc"
    local i
    for i in 1 2 3 4 5 6 7 8; do
        set_pr_state "$i" "{\"state\":\"OPEN\",\"isDraft\":false,\"statusCheckRollup\":[],\"reviewDecision\":\"\",\"title\":\"c$i\"}"
    done
    for i in 1 2 3 4 5 6 7 8; do
        run_capture "$sid" "gh pr create" "https://github.com/o/r/pull/$i" WS_NOW=$((2000 + i)) >/dev/null 2>&1 &
    done
    wait
    local rows distinct fields
    rows=$(wc -l < "$WORKDIR/store/$sid.ledger")
    assert_eq "concurrent captures produce N rows" "8" "$rows"
    distinct=$(cut -f3 "$WORKDIR/store/$sid.ledger" | sort -u | wc -l)
    assert_eq "concurrent captures are all distinct" "8" "$distinct"
    # No corruption: every row has exactly 5 tab-separated fields.
    fields=$(awk -F'\t' 'NF!=5{print "bad"}' "$WORKDIR/store/$sid.ledger" | grep -c bad || true)
    assert_eq "no corrupted (short/long) rows" "0" "$fields"
    teardown
}

# ===========================================================================
# 16. absence + compact ambient subcommands.
# ===========================================================================
test_absence_and_compact() {
    setup
    local sid="sess-ac"
    set_pr_state 1 '{"state":"OPEN","isDraft":false,"statusCheckRollup":[{"status":"COMPLETED","conclusion":"SUCCESS"}],"reviewDecision":"","title":"a"}'
    run_capture "$sid" "gh pr create" "https://github.com/o/r/pull/1" WS_NOW=1000 >/dev/null

    # Idle beyond the absence threshold -> absence emits.
    local out
    out=$(run_absence "$sid" WS_NOW=5000 WS_ABSENCE_THRESHOLD=1800)
    assert_contains "absence emits after idle" "$out" "o/r#1 | open ci:passing"

    # compact emits whenever the ledger is non-empty.
    out=$(run_compact "$sid" WS_NOW=5100)
    assert_contains "compact emits when ledger non-empty" "$out" "o/r#1 | open ci:passing"

    # absence within threshold -> suppressed.
    out=$(run_absence "$sid" WS_NOW=5200 WS_ABSENCE_THRESHOLD=1800)
    assert_eq "absence suppressed within threshold" "" "$out"

    teardown
}

# ===========================================================================
# 17. Empty rollup carries an explicit ci:none (FIX 6 / R2).
# ===========================================================================
test_ci_none() {
    setup
    local sid="sess-cinone"
    set_pr_state 1 '{"state":"OPEN","isDraft":false,"statusCheckRollup":[],"reviewDecision":"","title":"nostatus"}'
    run_capture "$sid" "gh pr create" "https://github.com/o/r/pull/1" WS_NOW=1000 >/dev/null
    local out
    out=$(run_render "$sid" WS_NOW=1100)
    assert_contains "empty rollup shows ci:none" "$out" "o/r#1 | open ci:none |"
    teardown
}

# ===========================================================================
# 18. inflight.sh repo-scoped fallback: fail-closed when repo cannot be
#     confirmed; non-current-repo URLs dropped when it can.
# ===========================================================================
test_inflight_fallback() {
    setup
    local sid_env="" # force fallback: no session id
    local IF_STUB="$WORKDIR/if-gh.sh"
    cat > "$IF_STUB" <<'STUB'
#!/usr/bin/env bash
case "$1" in
    repo)
        # gh repo view --json nameWithOwner --jq '.nameWithOwner'
        [[ -n "${IF_REPO:-}" ]] || { echo "no repo" >&2; exit 1; }
        printf '%s\n' "$IF_REPO"
        exit 0 ;;
    pr)
        # gh pr list ... --json ...
        if [[ -n "${IF_LIST:-}" && -f "$IF_LIST" ]]; then cat "$IF_LIST"; exit 0; fi
        echo "[]"; exit 0 ;;
esac
echo "unsupported" >&2; exit 1
STUB
    chmod +x "$IF_STUB"

    local listfile="$WORKDIR/if-list.json"
    printf '%s' '[
      {"number":10,"title":"good one","state":"OPEN","url":"https://github.com/o/r/pull/10","isDraft":false,"statusCheckRollup":[{"status":"COMPLETED","conclusion":"SUCCESS"}],"reviewDecision":""},
      {"number":99,"title":"cross repo","state":"OPEN","url":"https://github.com/other/repo/pull/99","isDraft":false,"statusCheckRollup":[],"reviewDecision":""}
    ]' > "$listfile"

    local out
    # Fail-closed: repo cannot be confirmed -> no output.
    out=$(env GH="$IF_STUB" WS_STORE_DIR="$WORKDIR/store" CLAUDE_CODE_SESSION_ID="" CLAUDE_SESSION_ID="" \
        bash "$SCRIPT_DIR/inflight.sh" 2>/dev/null)
    assert_eq "inflight fail-closed when repo unknown" "" "$out"

    # Confirmed repo -> lists the current-repo PR, drops the cross-repo one.
    out=$(env GH="$IF_STUB" IF_REPO="o/r" IF_LIST="$listfile" WS_STORE_DIR="$WORKDIR/store" \
        CLAUDE_CODE_SESSION_ID="" CLAUDE_SESSION_ID="" \
        bash "$SCRIPT_DIR/inflight.sh" 2>/dev/null)
    assert_contains "fallback lists current-repo PR" "$out" "o/r#10 | open ci:passing"
    assert_contains "fallback labeled repo-scoped" "$out" "repo-scoped fallback: o/r"
    assert_not_contains "fallback drops cross-repo PR (repo)" "$out" "other/repo"
    assert_not_contains "fallback drops cross-repo PR (num)" "$out" "#99"

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
test_c1_strip
test_gate_suppress_no_change
test_is_pr_create_false_positive
test_render_pure
test_symlink_refused
test_concurrency
test_absence_and_compact
test_ci_none
test_inflight_fallback

echo ""
echo "================================"
echo "PASS: $PASS_COUNT  FAIL: $FAIL_COUNT"
echo "================================"
[[ $FAIL_COUNT -eq 0 ]]
