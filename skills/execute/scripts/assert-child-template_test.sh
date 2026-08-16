#!/usr/bin/env bash
# assert-child-template_test.sh — Test harness for assert-child-template.sh
# Part of the execute skill
#
# Asserts that the check resolves the plugin root without depending on
# $CLAUDE_PLUGIN_ROOT being exported, while keeping the cross-skill child
# template (work-on.md) existence check as the real assertion. Also asserts the
# success path is silent.
#
# Usage: assert-child-template_test.sh
#
# Exit codes:
#   0 — all cases pass
#   1 — one or more cases failed

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
ASSERT="$SCRIPT_DIR/assert-child-template.sh"

PASS_COUNT=0
FAIL_COUNT=0

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

pass() { echo -e "${GREEN}PASS${NC}: $*"; ((PASS_COUNT++)) || true; }
fail() { echo -e "${RED}FAIL${NC}: $*"; ((FAIL_COUNT++)) || true; }

TMPS=()
cleanup() { for d in "${TMPS[@]:-}"; do [[ -n "$d" ]] && rm -rf "$d"; done; }
trap cleanup EXIT

# Case 1 — unset CLAUDE_PLUGIN_ROOT: self-resolves from the script's own location
# (the real checkout, where work-on.md exists) and succeeds.
if env -u CLAUDE_PLUGIN_ROOT bash "$ASSERT" >/dev/null 2>&1; then
    pass "unset CLAUDE_PLUGIN_ROOT -> self-resolves and exits 0"
else
    fail "unset CLAUDE_PLUGIN_ROOT should self-resolve and exit 0, but it failed"
fi

# Case 2 — the success path is silent: a valid root prints nothing on stdout or
# stderr. A check that speaks only when it fails is the shape this repo expects.
ALT_ROOT=$(mktemp -d); TMPS+=("$ALT_ROOT")
mkdir -p "$ALT_ROOT/skills/work-on/koto-templates"
touch "$ALT_ROOT/skills/work-on/koto-templates/work-on.md"
out=$(CLAUDE_PLUGIN_ROOT="$ALT_ROOT" bash "$ASSERT" 2>&1) || true
if [[ -z "$out" ]]; then
    pass "success path prints nothing"
else
    fail "success path should print nothing; got: $out"
fi

# Case 3 — env-var precedence AND the existence assertion: point CLAUDE_PLUGIN_ROOT
# at an empty dir while self-resolution (the real checkout) would have succeeded.
# Exit 1 proves the env var won; the message naming the empty root proves which
# path was probed.
EMPTY_DIR=$(mktemp -d); TMPS+=("$EMPTY_DIR")
if err=$(CLAUDE_PLUGIN_ROOT="$EMPTY_DIR" bash "$ASSERT" 2>&1); then
    fail "missing child template (env-var root) should exit 1, but it passed"
elif [[ "$err" == *"$EMPTY_DIR/skills/work-on/koto-templates/work-on.md"* ]]; then
    pass "missing child template (env-var root) -> exits 1 naming the env-var root"
else
    fail "CLAUDE_PLUGIN_ROOT should take precedence; got: $err"
fi

# Case 4 — self-resolve path, missing child: copy the script into a fake plugin
# tree that lacks work-on.md and run with the env var unset; the assertion must fire.
FAKE_ROOT=$(mktemp -d); TMPS+=("$FAKE_ROOT")
mkdir -p "$FAKE_ROOT/skills/execute/scripts"
cp "$ASSERT" "$FAKE_ROOT/skills/execute/scripts/assert-child-template.sh"
if env -u CLAUDE_PLUGIN_ROOT bash "$FAKE_ROOT/skills/execute/scripts/assert-child-template.sh" >/dev/null 2>&1; then
    fail "missing child template (self-resolved root) should exit 1, but it passed"
else
    pass "missing child template (self-resolved root) -> exits 1 (assertion fires)"
fi

echo
echo "assert-child-template_test.sh: $PASS_COUNT passed, $FAIL_COUNT failed"
[[ "$FAIL_COUNT" -eq 0 ]]
