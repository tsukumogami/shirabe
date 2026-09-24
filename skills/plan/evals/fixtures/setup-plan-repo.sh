#!/usr/bin/env bash
#
# setup-plan-repo.sh - Build a throwaway git repository for a /plan eval.
#
# Usage:
#   setup-plan-repo.sh <target-dir> <design> <claude-md>
#
#   <design>     basename under fixtures/designs/ (e.g. DESIGN-release-pipeline.md),
#                copied to docs/designs/<design>
#   <claude-md>  basename under fixtures/claude-md/ (e.g. CLAUDE-plain.md),
#                copied to CLAUDE.md
#
# The target must not exist. The repository gets one commit holding both
# files, so /plan's tracked-by-git checks and `shirabe validate` see a normal
# checkout. Scenarios then cd into it, put fixtures/bin first on PATH (the gh
# shim, which reports the repository as acme/widgets), and run /plan.
#
# Prints the target directory on success.

set -euo pipefail

if [ $# -ne 3 ]; then
    echo "usage: setup-plan-repo.sh <target-dir> <design> <claude-md>" >&2
    exit 2
fi

FIXTURES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET="$1"
DESIGN="$FIXTURES_DIR/designs/$2"
CLAUDE_MD="$FIXTURES_DIR/claude-md/$3"

[ -e "$TARGET" ] && { echo "setup-plan-repo.sh: target exists: $TARGET" >&2; exit 2; }
[ -f "$DESIGN" ] || { echo "setup-plan-repo.sh: no design fixture: $2" >&2; exit 2; }
[ -f "$CLAUDE_MD" ] || { echo "setup-plan-repo.sh: no CLAUDE.md fixture: $3" >&2; exit 2; }

mkdir -p "$TARGET/docs/designs"
cp "$DESIGN" "$TARGET/docs/designs/$2"
cp "$CLAUDE_MD" "$TARGET/CLAUDE.md"

git -C "$TARGET" init -q
git -C "$TARGET" add CLAUDE.md docs
git -C "$TARGET" -c user.name=eval -c user.email=eval@example.com \
    commit -q -m "chore: eval fixture"

printf '%s\n' "$(cd "$TARGET" && pwd)"
