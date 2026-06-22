#!/usr/bin/env bash
set -euo pipefail

# Fails the build if an eval-fixture DESIGN leaks into docs/designs/current/.
#
# The execute/work-on cascade evals run finalize-chain against the live tree,
# which `git mv`s a fixture DESIGN into docs/designs/current/. If that moved
# artifact is accidentally `git add`-ed and committed, it collides with the
# next eval run's `git mv` ("destination exists"), halting the cascade
# partial. This guard prevents that recurrence.
#
# A docs/designs/current/ file is flagged as a leak when either:
#   1. its basename matches a DESIGN fixture under skills/*/evals/fixtures/designs/, OR
#   2. its frontmatter `upstream:` points at an evals/fixtures/ path.
#
# Usage: scripts/check-no-fixture-design-leak.sh
# Exit code: 0 if clean, 1 if any leak is found.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CURRENT_DIR="$REPO_ROOT/docs/designs/current"

errors=0

# Collect the set of DESIGN fixture basenames (sorted, unique).
fixture_basenames=$(find "$REPO_ROOT/skills" -path '*/evals/fixtures/designs/*' \
  -name 'DESIGN-*.md' -printf '%f\n' 2>/dev/null | sort -u)

# Read the frontmatter `upstream:` value of a file (first match inside the
# leading `---` block). Prints empty string if absent.
read_upstream() {
  local file="$1"
  awk '
    /^---[[:space:]]*$/ { c++; if (c == 2) exit; next }
    c == 1 && /^upstream:[[:space:]]*/ {
      sub(/^upstream:[[:space:]]*/, "")
      print
      exit
    }
  ' "$file"
}

if [[ ! -d "$CURRENT_DIR" ]]; then
  echo "PASS: docs/designs/current/ absent, no fixture-design leak possible"
  exit 0
fi

shopt -s nullglob
for file in "$CURRENT_DIR"/DESIGN-*.md; do
  base=$(basename "$file")
  reason=""

  if grep -qx -- "$base" <<<"$fixture_basenames"; then
    reason="basename matches an eval-fixture DESIGN under skills/*/evals/fixtures/designs/"
  else
    upstream=$(read_upstream "$file")
    if [[ "$upstream" == *evals/fixtures/* ]]; then
      reason="frontmatter upstream points at an eval-fixture path ($upstream)"
    fi
  fi

  if [[ -n "$reason" ]]; then
    echo "FAIL: docs/designs/current/$base is an eval-fixture leak"
    echo "  Reason: $reason"
    echo "  Eval cascades git-mv fixtures into docs/designs/current/ at runtime;"
    echo "  a committed copy collides with the next run. Remove it (git rm)."
    errors=$((errors + 1))
  fi
done

if [[ $errors -gt 0 ]]; then
  exit 1
fi

echo "PASS: no eval-fixture DESIGN leaked into docs/designs/current/"
