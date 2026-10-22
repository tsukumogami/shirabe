#!/usr/bin/env bash
#
# resolve-plan-version_test.sh - Tests for resolve-plan-version.sh
#
# Covers the version precedence (flag over header over default), the header
# rules (whole line, outside fenced code, one header only, v1 or v2 exactly),
# every refusal, the one-line default and what flipping it changes, and that
# the step plan example in references/quality/plan-doc-examples.md validates
# clean as a PLAN file.
#
# The CLAUDE.md variants live in testdata/plan-version/.
#
# The example check needs a shirabe that knows plan/v2: $SHIRABE_BIN when set,
# otherwise this suite builds one with `cargo build --release -p shirabe`, the
# way plan-to-tasks_test.sh does.
#
# Usage:
#   bash resolve-plan-version_test.sh
#
# Exit codes:
#   0 - All tests passed
#   1 - One or more tests failed

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RESOLVER="$SCRIPT_DIR/resolve-plan-version.sh"
DATA="$SCRIPT_DIR/testdata/plan-version"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
EXAMPLES="$REPO_ROOT/skills/plan/references/quality/plan-doc-examples.md"
TEST_DIR=$(mktemp -d)
trap 'rm -rf "$TEST_DIR"' EXIT
PASS_COUNT=0
FAIL_COUNT=0

# The setting's name, kept apart from its value so this file never spells the
# assignment out: `git grep -n "<name>=v2" skills/plan/scripts/` must match
# exactly once, the script's own line, to show the default lives in one place.
DEFAULT_NAME="DEFAULT_PLAN_VERSION"

pass() {
    PASS_COUNT=$((PASS_COUNT + 1))
    echo "PASS: $1" >&2
}

fail() {
    FAIL_COUNT=$((FAIL_COUNT + 1))
    echo "FAIL: $1 - $2" >&2
}

# expect <name> <version> <resolver> <args...>
expect() {
    local name="$1" want="$2" resolver="$3"
    shift 3
    local out rc=0
    out=$("$BASH" "$resolver" "$@" 2>"$TEST_DIR/stderr") || rc=$?
    if [ "$rc" -ne 0 ]; then
        fail "$name" "exit $rc, stderr: $(cat "$TEST_DIR/stderr")"
    elif [ "$out" != "$want" ]; then
        fail "$name" "got '$out', want '$want'"
    elif [ -s "$TEST_DIR/stderr" ]; then
        fail "$name" "unexpected stderr: $(cat "$TEST_DIR/stderr")"
    else
        pass "$name"
    fi
}

# reject <name> <text stderr must contain> <args...>
# A refusal exits non-zero, prints nothing on stdout and one line on stderr.
reject() {
    local name="$1" needle="$2"
    shift 2
    local out rc=0
    out=$("$BASH" "$RESOLVER" "$@" 2>"$TEST_DIR/stderr") || rc=$?
    if [ "$rc" -eq 0 ]; then
        fail "$name" "expected non-zero exit, got 0 with '$out'"
    elif [ -n "$out" ]; then
        fail "$name" "expected empty stdout, got '$out'"
    elif ! grep -qF -- "$needle" "$TEST_DIR/stderr"; then
        fail "$name" "stderr does not name '$needle': $(cat "$TEST_DIR/stderr")"
    elif [ "$(wc -l < "$TEST_DIR/stderr" | tr -d ' ')" -ne 1 ]; then
        fail "$name" "expected one stderr line, got: $(cat "$TEST_DIR/stderr")"
    else
        pass "$name"
    fi
}

# --- precedence -------------------------------------------------------------

expect "flag v2" v2 "$RESOLVER" --plan-version=v2
expect "flag v1" v1 "$RESOLVER" --plan-version=v1
expect "flag in two-token form" v2 "$RESOLVER" --plan-version v2
expect "flag v1 wins over a v2 header" v1 "$RESOLVER" \
    --plan-version=v1 --claude-md "$DATA/CLAUDE-header-only.md"
expect "flag v2 with a CLAUDE.md that has no header" v2 "$RESOLVER" \
    --plan-version=v2 --claude-md "$DATA/CLAUDE-flag-only.md"
expect "header v2 with no flag" v2 "$RESOLVER" --claude-md "$DATA/CLAUDE-header-only.md"
printf '# Repo\n\n## Plan Version: v1\n' > "$TEST_DIR/header-v1.md"
expect "header v1 with no flag wins over the default" v1 "$RESOLVER" \
    --claude-md "$TEST_DIR/header-v1.md"
expect "header inside a fenced block is ignored" v2 "$RESOLVER" \
    --claude-md "$DATA/CLAUDE-fenced-header.md"
expect "no header falls through to the default" v2 "$RESOLVER" \
    --claude-md "$DATA/CLAUDE-flag-only.md"
expect "no flag and no CLAUDE.md gives the default" v2 "$RESOLVER"

# --- header matching ----------------------------------------------------------

printf '## Plan Version: \t v1  \r\n' > "$TEST_DIR/padded.md"
expect "header value is trimmed, CRLF included" v1 "$RESOLVER" --claude-md "$TEST_DIR/padded.md"

printf '### Plan Version: v1\n' > "$TEST_DIR/h3.md"
expect "an h3 line is not the header" v2 "$RESOLVER" --claude-md "$TEST_DIR/h3.md"

printf 'Set ## Plan Version: v1 to opt out.\n' > "$TEST_DIR/inline.md"
expect "the header text inside a sentence is not the header" v2 "$RESOLVER" \
    --claude-md "$TEST_DIR/inline.md"

printf '~~~~\n```\n## Plan Version: v2\n~~~\n~~~~~\n\n## Plan Version: v1\n' > "$TEST_DIR/tilde.md"
expect "a tilde fence closes only on a run at least as long" v1 "$RESOLVER" \
    --claude-md "$TEST_DIR/tilde.md"

printf '```\n## Plan Version: v2\n```\n\n## Plan Version: v1\n' > "$TEST_DIR/fence-then-header.md"
expect "a header after a closed fence counts, the fenced one does not" v1 "$RESOLVER" \
    --claude-md "$TEST_DIR/fence-then-header.md"

printf '```\n## Plan Version: v1\n' > "$TEST_DIR/unclosed.md"
expect "an unclosed fence runs to the end of the file" v2 "$RESOLVER" \
    --claude-md "$TEST_DIR/unclosed.md"

printf '## Plan Version: v1' > "$TEST_DIR/no-newline.md"
expect "a header on a last line with no newline counts" v1 "$RESOLVER" \
    --claude-md "$TEST_DIR/no-newline.md"

# --- refusals -----------------------------------------------------------------

reject "flag v3 names v1 and v2" "must be v1 or v2" --plan-version=v3
reject "empty flag value names v1 and v2" "must be v1 or v2" --plan-version=
reject "flag with no value names v1 and v2" "v1 or v2" --plan-version
reject "flag value is case-sensitive" "must be v1 or v2" --plan-version=V2
reject "flag given twice" "more than once" --plan-version=v2 --plan-version=v2
reject "bad header value names v1 and v2" "must be v1 or v2" \
    --claude-md "$DATA/CLAUDE-bad-value.md"
reject "duplicate header names both lines" "lines 3, 7" \
    --claude-md "$DATA/CLAUDE-duplicate-header.md"
reject "missing CLAUDE.md path" "not a file" --claude-md "$TEST_DIR/absent.md"
reject "--claude-md given twice" "more than once" \
    --claude-md "$DATA/CLAUDE-flag-only.md" --claude-md "$DATA/CLAUDE-flag-only.md"
reject "unknown argument" "unknown argument" --plan-versions=v2

printf '## Plan Version: v2\x1b[31m%s\n' "$(printf 'x%.0s' $(seq 1 80))" > "$TEST_DIR/hostile.md"
reject "a quoted header value has control characters stripped" "must be v1 or v2" \
    --claude-md "$TEST_DIR/hostile.md"
# The checks below read the stderr the reject call above left in place.
# 45 = the 40 kept characters, the "..." marker and the newline, plus one.
if LC_ALL=C grep -q "$(printf '\033')" "$TEST_DIR/stderr"; then
    fail "a quoted header value carries no escape" "stderr holds an ESC byte"
elif [ "$(sed -n "s/.*got '\\(.*\\)'.*/\\1/p" "$TEST_DIR/stderr" | wc -c | tr -d ' ')" -gt 45 ]; then
    fail "a quoted header value is cut to 40 characters" "$(cat "$TEST_DIR/stderr")"
else
    pass "a quoted header value is stripped and cut"
fi

# --- the default --------------------------------------------------------------

count=$(grep -c "^${DEFAULT_NAME}=" "$RESOLVER" || true)
if [ "$count" = "1" ] && grep -qx "${DEFAULT_NAME}=v2" "$RESOLVER"; then
    pass "the default is assigned on exactly one line, to v2"
else
    fail "the default is assigned on exactly one line, to v2" "found $count assignment lines"
fi

# Flip the default in a copy with a one-line substitution and nothing else.
FLIPPED="$TEST_DIR/flipped/resolve-plan-version.sh"
mkdir -p "$(dirname "$FLIPPED")"
sed "s/^${DEFAULT_NAME}=v2\$/${DEFAULT_NAME}=v1/" "$RESOLVER" > "$FLIPPED"
changed=$(diff "$RESOLVER" "$FLIPPED" | grep -c '^[<>]' || true)
if [ "$changed" = "2" ]; then
    pass "the flip changes one line"
else
    fail "the flip changes one line" "diff shows $changed changed lines"
fi
expect "flipped default: no flag, no header resolves to v1" v1 "$FLIPPED"
expect "flipped default: no header in CLAUDE.md resolves to v1" v1 "$FLIPPED" \
    --claude-md "$DATA/CLAUDE-flag-only.md"
expect "flipped default: an explicit v2 flag still wins" v2 "$FLIPPED" --plan-version=v2
expect "flipped default: a v2 header still wins" v2 "$FLIPPED" \
    --claude-md "$DATA/CLAUDE-header-only.md"

# --- the step plan example validates -------------------------------------------

resolve_shirabe() {
    if [ -n "${SHIRABE_BIN:-}" ] && [ -x "${SHIRABE_BIN:-}" ]; then
        return 0
    fi
    echo "Building shirabe release binary (cargo build --release -p shirabe)..." >&2
    if ! ( cd "$REPO_ROOT" && cargo build --release -p shirabe ) >&2; then
        echo "Error: failed to build the shirabe release binary" >&2
        exit 1
    fi
    SHIRABE_BIN="$REPO_ROOT/target/release/shirabe"
}

test_step_example_validates() {
    local name="the step plan example in plan-doc-examples.md validates clean"
    local repo="$TEST_DIR/example-repo" plan upstream out rc=0
    mkdir -p "$repo/docs/plans" "$repo/docs/designs"
    plan="$repo/docs/plans/PLAN-step-example.md"
    # The first ```markdown block after the example's heading, up to its fence.
    awk '/^## Step Plan Example \(plan\/v2\)/ { f = 1 }
         f && !g && /^```markdown$/ { g = 1; next }
         g && /^```$/ { exit }
         g' "$EXAMPLES" > "$plan"
    if ! grep -q '^schema: plan/v2$' "$plan"; then
        fail "$name" "no plan/v2 example found under its heading in $EXAMPLES"
        return
    fi
    # The example's upstream has to resolve and be tracked, so give it a stub
    # design in a throwaway repository.
    upstream=$(sed -n 's/^upstream: //p' "$plan")
    if [ -n "$upstream" ]; then
        mkdir -p "$repo/$(dirname "$upstream")"
        printf -- '---\nschema: design/v1\nstatus: Planned\n---\n' > "$repo/$upstream"
    fi
    git -C "$repo" init -q
    git -C "$repo" add docs
    git -C "$repo" -c user.name=test -c user.email=test@example.com commit -qm fixture
    out=$(cd "$repo" && "$SHIRABE_BIN" validate docs/plans/PLAN-step-example.md 2>&1) || rc=$?
    if [ "$rc" -ne 0 ] || [ -n "$out" ]; then
        fail "$name" "exit $rc: $out"
    else
        pass "$name"
    fi
}

resolve_shirabe
test_step_example_validates

echo "" >&2
echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed" >&2
[ "$FAIL_COUNT" -eq 0 ]
