#!/usr/bin/env bash
# Probe harness for Decision 5a. Not the shipped scan; reproduces the
# in-scope count so the design can cite real numbers.
set -uo pipefail

ROOT="${1:-skills}"
TOOLS='shirabe|koto|gh|jq|git|python3'

# Shapes that route a fd to /dev/null. The first three are the shapes the
# PRD acceptance criteria name; the fourth is the one they omit.
SHAPES='2>/dev/null|&>/dev/null|2>&1[[:space:]]*>/dev/null|>/dev/null[[:space:]]*2>&1'

# Word-boundary match for a declared tool appearing as a COMMAND, i.e. not
# merely somewhere in the file path. Callers must strip "path:lineno:" first.
tool_in_command() {
  printf '%s' "$1" | grep -qE "(^|[^A-Za-z0-9_./-])($TOOLS)([^A-Za-z0-9_-]|$)"
}

emit() {
  local mode="$1"
  grep -rnE "$SHAPES" "$ROOT" 2>/dev/null \
  | grep -vE '_test\.sh|/evals/|/fixtures/' \
  | while IFS= read -r hit; do
      local path lineno text
      path="${hit%%:*}"
      local rest="${hit#*:}"
      lineno="${rest%%:*}"
      text="${rest#*:}"
      case "$mode" in
        prd3)  printf '%s' "$text" | grep -qE '2>/dev/null|&>/dev/null|2>&1[[:space:]]*>/dev/null' || continue ;;
        omitted) printf '%s' "$text" | grep -qE '>/dev/null[[:space:]]*2>&1' || continue
                 printf '%s' "$text" | grep -qE '2>/dev/null|&>/dev/null|2>&1[[:space:]]*>/dev/null' && continue ;;
        all) : ;;
      esac
      tool_in_command "$text" || continue
      printf '%s:%s:%s\n' "$path" "$lineno" "$text"
    done
}

case "${2:-prd3}" in
  prd3)    emit prd3 ;;
  omitted) emit omitted ;;
  all)     emit all ;;
esac
