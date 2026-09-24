#!/usr/bin/env bash
#
# coordination-gate-refs.sh - extract the merge-gate refs from a coordination PR body
#
# Reads a coordination PR body on stdin and prints, one per line, every
# `owner/repo:path#number` ref the merge-last gate should wait on. The
# lifecycle.yml merge-last step turns each printed line into a
# `shirabe validate --merge-gate --pr <ref>` argument.
#
# The one ref it drops is the coordination PR itself. In a single-repo effort
# the PR index can list the coordination PR's own number in its own repository;
# gating on that ref would make the coordination PR wait for itself to merge, so
# the gate could never pass. A ref is a self-reference only when BOTH its
# `owner/repo` equals SELF_REPO (compared case-insensitively, as GitHub does)
# AND its number equals SELF_NUMBER. Another PR in the same repository, or the
# same number in a different repository, is kept.
#
# Printing nothing means the index is empty (or held only the self-reference);
# the caller treats that as an empty index and fails closed.
#
# Usage:
#   coordination-gate-refs.sh <self-repo> <self-number> < body.md
#
# Exit codes:
#   0 - refs printed (possibly none)
#   2 - usage error

set -euo pipefail

if [ "$#" -ne 2 ]; then
    echo "usage: coordination-gate-refs.sh <owner/repo> <pr-number> < body" >&2
    exit 2
fi

SELF_REPO="$1"
SELF_NUMBER="$2"

case "$SELF_NUMBER" in
    ''|*[!0-9]*)
        echo "coordination-gate-refs: pr-number must be a non-negative integer, got '$SELF_NUMBER'" >&2
        exit 2
        ;;
esac

lower() {
    printf '%s' "$1" | tr '[:upper:]' '[:lower:]'
}

SELF_REPO_LC="$(lower "$SELF_REPO")"
# Force base 10 so a leading zero is not read as octal.
SELF_NUMBER=$((10#$SELF_NUMBER))

# The token shape matches what the Rust coordination-body check extracts.
# `grep` exits 1 on no match; that is an empty index, not an error.
REFS="$(grep -oE '[A-Za-z0-9][A-Za-z0-9._-]*/[A-Za-z0-9._-]+:[^ |]+#[0-9]+' | sort -u || true)"

[ -z "$REFS" ] && exit 0

printf '%s\n' "$REFS" | while IFS= read -r ref; do
    [ -z "$ref" ] && continue
    slug="${ref%%:*}"
    number="${ref##*#}"
    if [ "$(lower "$slug")" = "$SELF_REPO_LC" ] && [ "$((10#$number))" -eq "$SELF_NUMBER" ]; then
        continue
    fi
    printf '%s\n' "$ref"
done
