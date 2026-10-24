#!/usr/bin/env bash
#
# check-no-fixture-design-leak_test.sh - the fixture-design leak check, on the
# tree and on fixtures
#
# The first case runs the check against this repository, so one CI step
# covers both the scan and its own regressions. The rest copy the check into a
# throwaway tree under a mktemp directory (the check finds the repository root
# from its own location), plant fixtures there, and assert what it flags and
# what it lets through.
#
# Usage: scripts/check-no-fixture-design-leak_test.sh
#
# Exit 0 when every case passes, 1 otherwise.
#
# Runs on bash 3.2, and on macOS's BSD userland as on Linux's GNU one.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHECK="$SCRIPT_DIR/check-no-fixture-design-leak.sh"

PASS_COUNT=0
FAIL_COUNT=0
pass() { echo "PASS: $*"; PASS_COUNT=$((PASS_COUNT + 1)); }
fail() { echo "FAIL: $*"; FAIL_COUNT=$((FAIL_COUNT + 1)); }

WORKDIR=$(mktemp -d "${TMPDIR:-/tmp}/fixture-design-leak.XXXXXX") || { echo "mktemp failed" >&2; exit 1; }
trap 'rm -rf "$WORKDIR"' EXIT

echo "bash $BASH_VERSION"

# --- the tree -----------------------------------------------------------------

out=$(bash "$CHECK" 2>&1)
rc=$?
if [ "$rc" -eq 0 ]; then
  pass "the repository has no eval-fixture DESIGN in docs/designs/current/"
else
  fail "the check fails on the repository (exit $rc):
$out"
fi

# --- fixtures -----------------------------------------------------------------

# new_tree <name>: a fresh tree holding a copy of the check and one fixture
# DESIGN, skills/a/evals/fixtures/designs/DESIGN-fixture.md; sets ROOT.
ROOT=""
new_tree() {
  ROOT="$WORKDIR/$1"
  mkdir -p "$ROOT/scripts" "$ROOT/skills/a/evals/fixtures/designs"
  cp "$CHECK" "$ROOT/scripts/"
  printf -- '---\nstatus: Proposed\n---\n\n# DESIGN: fixture\n' \
    > "$ROOT/skills/a/evals/fixtures/designs/DESIGN-fixture.md"
}

# put <relative path> <content>: write a file under ROOT.
put() {
  mkdir -p "$ROOT/$(dirname "$1")"
  printf -- '%s' "$2" > "$ROOT/$1"
}

# run_check: run the copied check over ROOT; sets OUT and RC.
OUT=""
RC=0
run_check() {
  OUT=$(bash "$ROOT/scripts/check-no-fixture-design-leak.sh" 2>&1)
  RC=$?
}

passes() { # <name> <expected line>
  run_check
  if [ "$RC" -eq 0 ] && grep -q -F -- "$2" <<<"$OUT"; then
    pass "$1: passes"
  else
    fail "$1: expected exit 0 printing [$2], got exit $RC: [$OUT]"
  fi
}

flagged() { # <name> <basename> <reason text>
  run_check
  if [ "$RC" -eq 1 ] \
    && grep -q -F -- "FAIL: docs/designs/current/$2 is an eval-fixture leak" <<<"$OUT" \
    && grep -q -F -- "$3" <<<"$OUT"; then
    pass "$1: flags $2"
  else
    fail "$1: expected exit 1 flagging $2 with [$3], got exit $RC: [$OUT]"
  fi
}

new_tree clean
put docs/designs/current/DESIGN-real.md $'---\nstatus: Current\nupstream: docs/prds/PRD-real.md\n---\n\n# DESIGN: real\n'
passes "a clean tree" "PASS: no eval-fixture DESIGN leaked into docs/designs/current/"

new_tree no-current
passes "a tree without docs/designs/current/" "PASS: docs/designs/current/ absent"

new_tree basename
put docs/designs/current/DESIGN-fixture.md $'---\nstatus: Current\n---\n\n# DESIGN: fixture\n'
flagged "a fixture DESIGN's basename" DESIGN-fixture.md "basename matches an eval-fixture DESIGN"

new_tree nested
put skills/b/evals/fixtures/designs/sub/DESIGN-nested.md $'# DESIGN: nested\n'
put docs/designs/current/DESIGN-nested.md $'# DESIGN: nested\n'
flagged "a basename from a nested fixture folder" DESIGN-nested.md "basename matches an eval-fixture DESIGN"

new_tree other-fixture-folder
put skills/b/evals/fixtures/plans/DESIGN-elsewhere.md $'# not a DESIGN fixture\n'
put docs/designs/current/DESIGN-elsewhere.md $'---\nstatus: Current\n---\n\n# DESIGN: elsewhere\n'
passes "a basename found only outside fixtures/designs/" "PASS: no eval-fixture DESIGN leaked"

new_tree upstream
put docs/designs/current/DESIGN-moved.md $'---\nstatus: Current\nupstream: skills/a/evals/fixtures/prds/PRD-fixture.md\n---\n\n# DESIGN: moved\n'
flagged "a frontmatter upstream into evals/fixtures/" DESIGN-moved.md "frontmatter upstream points at an eval-fixture path (skills/a/evals/fixtures/prds/PRD-fixture.md)"

new_tree upstream-in-body
put docs/designs/current/DESIGN-body.md $'---\nstatus: Current\n---\n\n# DESIGN: body\n\nupstream: skills/a/evals/fixtures/prds/PRD-fixture.md\n'
passes "an upstream line outside the frontmatter" "PASS: no eval-fixture DESIGN leaked"

new_tree two-leaks
put docs/designs/current/DESIGN-fixture.md $'# DESIGN: fixture\n'
put docs/designs/current/DESIGN-moved.md $'---\nupstream: skills/a/evals/fixtures/prds/PRD-fixture.md\n---\n'
run_check
leaks=$(grep -c -- '^FAIL: ' <<<"$OUT")
if [ "$RC" -eq 1 ] && [ "$leaks" -eq 2 ]; then
  pass "two leaks: both flagged"
else
  fail "two leaks: expected exit 1 with 2 FAIL lines, got exit $RC with $leaks: [$OUT]"
fi

echo ""
echo "$PASS_COUNT passed, $FAIL_COUNT failed"
[ "$FAIL_COUNT" -eq 0 ]
