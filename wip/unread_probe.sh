#!/usr/bin/env bash
# Probe: VAR=$(<declared-tool> ...) where VAR is never referenced again.
# Heuristic, for sizing the fourth shape only.
set -uo pipefail
TOOLS='shirabe|koto|gh|jq|git|python3'

find skills -type f \( -name '*.sh' -o -name '*.md' \) \
  | grep -vE '_test\.sh|/evals/|/fixtures/' \
  | while IFS= read -r f; do
      grep -nE "^[[:space:]]*(local[[:space:]]+)?[A-Za-z_][A-Za-z0-9_]*=\\\$\(" "$f" 2>/dev/null \
      | grep -E "($TOOLS)[[:space:]]" \
      | while IFS= read -r hit; do
          ln="${hit%%:*}"
          text="${hit#*:}"
          var=$(printf '%s' "$text" | sed -E 's/^[[:space:]]*(local[[:space:]]+)?([A-Za-z_][A-Za-z0-9_]*)=.*/\2/')
          [ -n "$var" ] || continue
          uses=$(grep -cE "\\\$\{?$var\b" "$f" 2>/dev/null)
          if [ "${uses:-0}" -eq 0 ]; then
            printf 'UNREAD %s:%s:%s\n' "$f" "$ln" "$var"
          fi
        done
    done
