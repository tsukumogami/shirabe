#!/usr/bin/env bash
# probe: docs-only commits on origin/main
cd "$(dirname "$0")/.."
for c in $(git rev-list origin/main); do
  files=$(git show --pretty=format: --name-only "$c" | sed '/^$/d')
  nondocs=$(printf '%s\n' "$files" | grep -v '^docs/' | head -1)
  if [ -z "$nondocs" ]; then
    printf 'DOCSONLY %s %s\n' "$c" "$(git log -1 --format='%s' "$c")"
  fi
done
