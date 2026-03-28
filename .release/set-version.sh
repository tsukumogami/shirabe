#!/usr/bin/env bash
set -euo pipefail

# Updates version in plugin.json and marketplace.json.
# Called by the reusable release workflow with:
#   .release/set-version.sh <version>
# where <version> has no v prefix (e.g., "0.3.0" or "0.3.1-dev").

VERSION="${1:?Usage: set-version.sh <version>}"

PLUGIN_JSON=".claude-plugin/plugin.json"
MARKETPLACE_JSON=".claude-plugin/marketplace.json"

for file in "$PLUGIN_JSON" "$MARKETPLACE_JSON"; do
  if [ ! -f "$file" ]; then
    echo "ERROR: $file not found" >&2
    exit 1
  fi
done

# Update plugin.json .version
jq --arg v "$VERSION" '.version = $v' "$PLUGIN_JSON" > "$PLUGIN_JSON.tmp" \
  && mv "$PLUGIN_JSON.tmp" "$PLUGIN_JSON"

# Update marketplace.json .plugins[0].version
jq --arg v "$VERSION" '.plugins[0].version = $v' "$MARKETPLACE_JSON" > "$MARKETPLACE_JSON.tmp" \
  && mv "$MARKETPLACE_JSON.tmp" "$MARKETPLACE_JSON"

echo "Version set to $VERSION in $PLUGIN_JSON and $MARKETPLACE_JSON"
