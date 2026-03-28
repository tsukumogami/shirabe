#!/usr/bin/env bash
set -euo pipefail

# Validates that plugin manifest versions contain the sentinel value.
# Used by CI to prevent accidental version bumps on PRs.

SENTINEL="0.0.0-dev"
PLUGIN_JSON=".claude-plugin/plugin.json"
MARKETPLACE_JSON=".claude-plugin/marketplace.json"

errors=0

check_version() {
  local file="$1"
  local filter="$2"
  local version

  if [[ ! -f "$file" ]]; then
    echo "FAIL: $file not found"
    errors=$((errors + 1))
    return
  fi

  version=$(jq -r "$filter" "$file")

  if [[ "$version" != "$SENTINEL" ]]; then
    echo "FAIL: $file has version \"$version\", expected \"$SENTINEL\""
    echo "  Versions are set automatically at release time."
    echo "  Do not change the version in manifest files."
    errors=$((errors + 1))
  fi
}

check_version "$PLUGIN_JSON" '.version'
check_version "$MARKETPLACE_JSON" '.plugins[0].version'

if [[ $errors -gt 0 ]]; then
  exit 1
fi

echo "PASS: all manifest versions are $SENTINEL"
