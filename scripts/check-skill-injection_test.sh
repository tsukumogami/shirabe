#!/usr/bin/env bash
# check-skill-injection_test.sh -- Test harness for check-skill-injection.sh
#
# The two cases that matter most are the historical defects the check exists to
# stop: the guardless `!`shirabe work-summary render`` that killed the skill on
# any host without the binary, and the documentation line
# `!`shirabe work-summary track <pr-url> [<pr-url> ...]`` whose placeholder was
# a shell redirection. Both are reconstructed as fixtures here, and the check
# must fail on each. The tree as it stands must stay green.
#
# Usage: scripts/check-skill-injection_test.sh
#
# Exit codes:
#   0 -- all cases pass
#   1 -- one or more cases failed

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CHECK="$SCRIPT_DIR/check-skill-injection.sh"

PASS_COUNT=0
FAIL_COUNT=0

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

pass() { echo -e "${GREEN}PASS${NC}: $*"; PASS_COUNT=$((PASS_COUNT + 1)); }
fail() { echo -e "${RED}FAIL${NC}: $*"; FAIL_COUNT=$((FAIL_COUNT + 1)); }

TMPS=()
cleanup() { for d in "${TMPS[@]:-}"; do [ -n "$d" ] && rm -rf "$d"; done; }
trap cleanup EXIT

WORK=$(mktemp -d); TMPS+=("$WORK")

# Write a one-skill fixture tree. $1 is the case name, $2 the allowed-tools
# value (empty means the key is omitted entirely), $3 the body line.
make_fixture() {
  local name="$1" allowed="$2" body="$3"
  local dir="$WORK/$name/skills/$name"
  mkdir -p "$dir"
  {
    echo "---"
    echo "name: $name"
    echo "description: fixture"
    if [ -n "$allowed" ]; then
      echo "allowed-tools: $allowed"
    fi
    echo "---"
    echo
    echo "# Fixture"
    echo
    echo "$body"
    echo
    echo "Prose after the injected line."
  } > "$dir/SKILL.md"
  FIXTURE="$WORK/$name/skills"
}

# Assert the check accepts a fixture.
assert_accepts() {
  local label="$1" out
  out=$(bash "$CHECK" "$FIXTURE" 2>&1)
  if [ $? -eq 0 ]; then
    pass "$label"
  else
    fail "$label -- expected exit 0, got failure: $out"
  fi
}

# Assert the check rejects a fixture, and that its output names the reason.
assert_rejects() {
  local label="$1" needle="$2" out rc
  out=$(bash "$CHECK" "$FIXTURE" 2>&1); rc=$?
  if [ "$rc" -eq 0 ]; then
    fail "$label -- expected exit 1, but the check passed"
  elif [ "$rc" -ne 1 ]; then
    fail "$label -- expected exit 1, got $rc: $out"
  else
    case "$out" in
      *"$needle"*) pass "$label" ;;
      *) fail "$label -- exited 1 but did not say '$needle'; got: $out" ;;
    esac
  fi
}

# --- Case 1: the tree as it stands is green -------------------------------
# The check is only useful if it holds against the repo it guards. This is the
# acceptance criterion "green against the tree as it stands".
out=$(bash "$CHECK" 2>&1)
if [ $? -eq 0 ]; then
  pass "current tree passes ($out)"
else
  fail "current tree should pass; got: $out"
fi

# --- Case 2: the live inflight line ---------------------------------------
# skills/inflight/SKILL.md:40 as it stands after its fix: a guarded `|| echo`
# with both halves declared. It is the only injected line in the tree today, so
# it is also the check's only positive sample from real code.
make_fixture inflight-live \
  'Bash(shirabe:*), Bash(echo:*)' \
  "!\`shirabe work-summary render || echo 'shirabe work-summary render did not run: the shirabe binary is not on PATH. Do not list pull requests from memory.'\`"
assert_accepts "guarded '|| echo' with both halves declared is accepted"

# --- Case 3: the canonical rollout line ------------------------------------
# The shape twenty skills are about to carry. It must be accepted, including
# its `2>&1`, or the check blocks the rollout it was written to protect.
make_fixture rollout-canonical \
  'Bash(bash ${CLAUDE_PLUGIN_ROOT}/scripts/skill-preflight.sh *), Bash(true)' \
  '!`bash ${CLAUDE_PLUGIN_ROOT}/scripts/skill-preflight.sh rollout-canonical 2>&1 || true`'
assert_accepts "canonical rollout line with '2>&1 || true' is accepted"

# --- Case 4 (NEGATIVE FIXTURE 1): the guardless render line ----------------
# skills/inflight/SKILL.md:40 as it was. `shirabe work-summary render` exits 0
# once it runs, but on a host without the binary the shell returns 127 and the
# skill does not load at all.
make_fixture guardless-render \
  'Bash(shirabe:*)' \
  '!`shirabe work-summary render`'
assert_rejects "guardless '!\`shirabe work-summary render\`' is rejected" "no exit-0 guard"

# --- Case 5 (NEGATIVE FIXTURE 2): the documentation line -------------------
# skills/inflight/SKILL.md:77 as it was. Written to show a verb the agent
# should run later; `<pr-url>` is an input redirection from a file that does
# not exist, so the command failed and the skill never loaded.
make_fixture doc-placeholder \
  'Bash(shirabe:*), Bash(true)' \
  '!`shirabe work-summary track <pr-url> [<pr-url> ...] || true`'
assert_rejects "'<pr-url>' placeholder line is rejected" "unquoted redirection"

# --- Case 6: an undeclared subcommand across '||' --------------------------
# The failure the inflight frontmatter comment documents: `Bash(shirabe:*)`
# alone leaves the `echo` half undeclared, and an undeclared subcommand deletes
# the skill silently rather than degrading it.
make_fixture undeclared-half \
  'Bash(shirabe:*)' \
  "!\`shirabe work-summary render || echo 'fallback text'\`"
assert_rejects "undeclared '||' half is rejected" "not covered by allowed-tools"

# --- Case 7: an injected line with no allowed-tools at all -----------------
make_fixture no-declaration \
  '' \
  '!`shirabe work-summary render || true`'
assert_rejects "injected line with no allowed-tools is rejected" "no Bash(...) allowed-tools entry"

# --- Case 8: the guard behind '&&' -----------------------------------------
# `&&` skips the guard on exactly the failure it was meant to absorb.
make_fixture guard-behind-and \
  'Bash(shirabe:*), Bash(true)' \
  '!`shirabe work-summary render && true`'
assert_rejects "guard behind '&&' is rejected" "unreachable on failure"

# --- Case 9: an unterminated injection -------------------------------------
make_fixture unterminated \
  'Bash(shirabe:*), Bash(true)' \
  '!`shirabe work-summary render || true'
assert_rejects "unterminated backtick is rejected" "never closes the backtick"

# --- Case 10: quoting is honored, both ways --------------------------------
# A '>' inside a quoted string is text, not a redirection, and a '||' inside
# one is not a subcommand boundary. Both would be false positives.
make_fixture quoted-metachars \
  'Bash(shirabe:*), Bash(echo:*)' \
  "!\`shirabe work-summary render || echo 'run: shirabe work-summary track <url> || retry'\`"
assert_accepts "'<', '>' and '||' inside quotes are not read as shell syntax"

# --- Case 11: a fenced example is still an injection -----------------------
# The harness resolves injections before anything parses markdown, so a
# '!'-prefixed line inside a code fence loads exactly like one in prose. The
# defect this check exists for was written as documentation too.
name=fenced-example
dir="$WORK/$name/skills/$name"
mkdir -p "$dir"
{
  echo "---"
  echo "name: $name"
  echo "description: fixture"
  echo "allowed-tools: Bash(shirabe:*)"
  echo "---"
  echo
  echo 'Example of what to run:'
  echo
  echo '```'
  echo '!`shirabe work-summary track <pr-url>`'
  echo '```'
} > "$dir/SKILL.md"
FIXTURE="$WORK/$name/skills"
assert_rejects "an injected line inside a code fence is still checked" "unquoted redirection"

# --- Case 12: a skill with no injected line is silently fine ---------------
name=no-injection
dir="$WORK/$name/skills/$name"
mkdir -p "$dir"
{
  echo "---"
  echo "name: $name"
  echo "description: fixture"
  echo "---"
  echo
  echo 'Prose that mentions `!` and even shows a > redirection in text.'
} > "$dir/SKILL.md"
FIXTURE="$WORK/$name/skills"
assert_accepts "a skill with no injected line is accepted"

# --- Case 13: the command ends at the closing backtick ---------------------
# Prose after the injection is prose. Reading past the closing backtick would
# make an ordinary sentence look like a redirection.
make_fixture trailing-prose \
  'Bash(shirabe:*), Bash(true)' \
  '!`shirabe work-summary render || true` -- relay the output, and see `docs > guides` for why.'
assert_accepts "prose after the closing backtick is not read as part of the command"

# --- Case 14: every injected line is checked, and named by line number ------
name=two-injections
dir="$WORK/$name/skills/$name"
mkdir -p "$dir"
{
  echo "---"
  echo "name: $name"
  echo "description: fixture"
  echo "allowed-tools: Bash(shirabe:*), Bash(true)"
  echo "---"
  echo
  echo '!`shirabe work-summary render || true`'
  echo
  echo '!`shirabe work-summary track <pr-url> || true`'
} > "$dir/SKILL.md"
FIXTURE="$WORK/$name/skills"
assert_rejects "the second injected line is checked too" "SKILL.md:9:"

# --- Case 15: a bad path is a usage error, not a finding -------------------
out=$(bash "$CHECK" "$WORK/does-not-exist" 2>&1); rc=$?
if [ "$rc" -eq 2 ]; then
  pass "a nonexistent path exits 2 (usage), not 1 (finding)"
else
  fail "a nonexistent path should exit 2; got $rc: $out"
fi

echo
echo "check-skill-injection_test.sh: $PASS_COUNT passed, $FAIL_COUNT failed"
[ "$FAIL_COUNT" -eq 0 ]
