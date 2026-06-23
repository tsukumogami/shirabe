#!/usr/bin/env bash
# preflight_test.sh — Test harness for preflight.sh
# Part of the execute skill
#
# Asserts that the /execute preflight resolves the plugin root without depending
# on $CLAUDE_PLUGIN_ROOT being exported, while keeping the cross-skill child
# template (work-on.md) existence check as the real assertion.
#
# Usage: preflight_test.sh
#
# Exit codes:
#   0 — all cases pass
#   1 — one or more cases failed

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
PREFLIGHT="$SCRIPT_DIR/preflight.sh"

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
if env -u CLAUDE_PLUGIN_ROOT bash "$PREFLIGHT" >/dev/null 2>&1; then
    pass "unset CLAUDE_PLUGIN_ROOT -> self-resolves and exits 0"
else
    fail "unset CLAUDE_PLUGIN_ROOT should self-resolve and exit 0, but it failed"
fi

# Case 2 — env-var precedence: point CLAUDE_PLUGIN_ROOT at a DISTINCT valid root
# (a temp tree with its own work-on.md) and confirm the preflight resolves
# against THAT root, not the self-resolved checkout.
ALT_ROOT=$(mktemp -d); TMPS+=("$ALT_ROOT")
mkdir -p "$ALT_ROOT/skills/work-on/koto-templates"
touch "$ALT_ROOT/skills/work-on/koto-templates/work-on.md"
out=$(CLAUDE_PLUGIN_ROOT="$ALT_ROOT" bash "$PREFLIGHT" 2>&1) || true
if [[ "$out" == *"$ALT_ROOT/skills/work-on/koto-templates/work-on.md"* ]]; then
    pass "CLAUDE_PLUGIN_ROOT takes precedence over self-resolution"
else
    fail "CLAUDE_PLUGIN_ROOT should take precedence; got: $out"
fi

# Case 3 — env-var path, missing child: the existence assertion must fire (exit 1).
EMPTY_DIR=$(mktemp -d); TMPS+=("$EMPTY_DIR")
if CLAUDE_PLUGIN_ROOT="$EMPTY_DIR" bash "$PREFLIGHT" >/dev/null 2>&1; then
    fail "missing child template (env-var root) should exit 1, but it passed"
else
    pass "missing child template (env-var root) -> exits 1 (assertion fires)"
fi

# Case 4 — self-resolve path, missing child: copy the script into a fake plugin
# tree that lacks work-on.md and run with the env var unset; the assertion must fire.
FAKE_ROOT=$(mktemp -d); TMPS+=("$FAKE_ROOT")
mkdir -p "$FAKE_ROOT/skills/execute/scripts"
cp "$PREFLIGHT" "$FAKE_ROOT/skills/execute/scripts/preflight.sh"
if env -u CLAUDE_PLUGIN_ROOT bash "$FAKE_ROOT/skills/execute/scripts/preflight.sh" >/dev/null 2>&1; then
    fail "missing child template (self-resolved root) should exit 1, but it passed"
else
    pass "missing child template (self-resolved root) -> exits 1 (assertion fires)"
fi

echo
echo "preflight_test.sh: $PASS_COUNT passed, $FAIL_COUNT failed"
[[ "$FAIL_COUNT" -eq 0 ]]
