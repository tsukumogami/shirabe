#!/usr/bin/env bash
# bump-callers.sh - Open PRs bumping the pinned shirabe release.yml ref in known caller repos
# Part of the release skill
#
# Usage: ./bump-callers.sh <new-tag>
#
# Arguments:
#   new-tag  Required. The shirabe tag callers should pin to, e.g. v0.6.0
#
# Reads the caller registry from callers.json (same directory's parent).
# For each caller already pinned to a different ref, clones the repo,
# updates the uses: line, and opens a PR. Callers already on the target
# tag, or whose workflow file doesn't reference the reusable workflow,
# are skipped and reported, not treated as failures.
#
# Exit codes:
#   0 - Completed (individual callers may have been skipped; see output)
#   1 - Bad usage or registry unreadable

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REGISTRY="$SCRIPT_DIR/../callers.json"
REF_PATTERN='shirabe/\.github/workflows/release\.yml@[A-Za-z0-9._/-]+'

NEW_TAG="${1:-}"
if [[ -z "$NEW_TAG" ]]; then
    echo "Usage: $0 <new-tag>" >&2
    exit 1
fi
if [[ ! -f "$REGISTRY" ]]; then
    echo "Registry not found: $REGISTRY" >&2
    exit 1
fi

WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT

RESULTS=()

while IFS=$'\t' read -r REPO WORKFLOW; do
    NAME="${REPO##*/}"
    CLONE_DIR="$WORKDIR/$NAME"

    if ! gh repo clone "$REPO" "$CLONE_DIR" -- --depth 1 --quiet 2>/dev/null; then
        echo "SKIP $REPO: clone failed" >&2
        RESULTS+=("$REPO: clone failed")
        continue
    fi

    WORKFLOW_PATH="$CLONE_DIR/$WORKFLOW"
    if [[ ! -f "$WORKFLOW_PATH" ]]; then
        echo "SKIP $REPO: $WORKFLOW not found" >&2
        RESULTS+=("$REPO: $WORKFLOW not found")
        continue
    fi

    CURRENT_REF=$(grep -oE "$REF_PATTERN" "$WORKFLOW_PATH" | head -1 | sed 's#.*@##') || true
    if [[ -z "$CURRENT_REF" ]]; then
        echo "SKIP $REPO: $WORKFLOW does not reference the reusable release workflow" >&2
        RESULTS+=("$REPO: no reference to reusable workflow")
        continue
    fi
    if [[ "$CURRENT_REF" == "$NEW_TAG" ]]; then
        echo "SKIP $REPO: already pinned to $NEW_TAG" >&2
        RESULTS+=("$REPO: already up to date")
        continue
    fi

    BRANCH="chore/bump-shirabe-release-workflow-$NEW_TAG"

    EXISTING_PR=$(gh pr list --repo "$REPO" --head "$BRANCH" --json url --jq '.[0].url' 2>/dev/null || echo "")
    if [[ -n "$EXISTING_PR" ]]; then
        echo "SKIP $REPO: PR already open for $BRANCH: $EXISTING_PR" >&2
        RESULTS+=("$REPO: already has open PR: $EXISTING_PR")
        continue
    fi

    if ! (
        cd "$CLONE_DIR"
        git checkout -q -b "$BRANCH"
        sed -i -E "s#$REF_PATTERN#shirabe/.github/workflows/release.yml@$NEW_TAG#" "$WORKFLOW"
        git add "$WORKFLOW"
        git commit -q -m "chore: bump shirabe release workflow to $NEW_TAG"
        git push -q -u origin "$BRANCH"
    ); then
        echo "FAIL $REPO: git commit/push failed" >&2
        RESULTS+=("$REPO: git commit/push failed")
        continue
    fi

    if ! PR_URL=$(gh pr create --repo "$REPO" \
        --title "chore: bump shirabe release workflow to $NEW_TAG" \
        --body "Bumps the pinned \`tsukumogami/shirabe/.github/workflows/release.yml\` ref in \`$WORKFLOW\` from \`$CURRENT_REF\` to \`$NEW_TAG\`.

---

Automated follow-up to the shirabe $NEW_TAG release." \
        --head "$BRANCH" --base main); then
        echo "FAIL $REPO: pr create failed (branch $BRANCH was pushed)" >&2
        RESULTS+=("$REPO: pr create failed, branch $BRANCH pushed")
        continue
    fi

    echo "PR $REPO: $PR_URL"
    RESULTS+=("$REPO: $PR_URL")
done < <(jq -r '.callers[] | [.repo, .workflow] | @tsv' "$REGISTRY")

echo
echo "Summary:"
for line in "${RESULTS[@]}"; do
    echo "  - $line"
done
