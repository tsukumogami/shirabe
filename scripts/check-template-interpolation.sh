#!/usr/bin/env bash
set -euo pipefail

# Fails the build if a koto template uses shell-style interpolation in a field
# koto executes itself.
#
# koto resolves template variables written as {{KEY}} and, at compile time,
# rejects any {{KEY}} not declared in the template's `variables:` block. It has
# no such check for shell-style $NAME or ${NAME}: those are passed to `sh -c`
# verbatim, where an unset variable expands to the empty string. A gate command
# written that way does not fail loudly -- it silently tests the wrong path.
# That is exactly how the worktree_discipline_check gate came to test
# `wip/work-on__impact.json` for every plan.
#
# Three forms are deliberately NOT flagged:
#   - {{KEY}}, which koto resolves and validates.
#   - ${evidence.<field>}, koto's own evidence-reference namespace. It appears
#     in `context_assignments`, which this check does not read.
#   - $(...) command substitution, which is the point: the gate's shell is
#     meant to run those, and several gates legitimately do
#     (`test "$(git rev-parse --abbrev-ref HEAD)" != "main"`). Only a bare
#     variable reference is a defect, because only a variable reference is
#     something an author could expect koto to have substituted.
#
# Directive prose is also not read: the agent runs those snippets in its own
# shell and legitimately sets and reads shell variables there. Only the fields
# koto hands to a shell are in scope -- gate `command:` values and
# `default_action` command values.
#
# Usage: scripts/check-template-interpolation.sh [template-glob-root]
# Exit code: 0 if clean, 1 if any offending field is found.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SEARCH_ROOT="${1:-$REPO_ROOT/skills}"

errors=0

# Emit "<line-number>:<state>:<field>:<value>" for every koto-executed command
# field in a template. State is tracked by the most recent top-level state key
# so a finding can name where it lives.
scan_template() {
  awk '
    # A state key: exactly two leading spaces, a name, a colon, nothing after.
    /^  [A-Za-z_][A-Za-z0-9_]*:[[:space:]]*$/ {
      line = $0
      sub(/^  /, "", line)
      sub(/:[[:space:]]*$/, "", line)
      state = line
      next
    }
    # A gate command or a default_action command, at any deeper indent.
    /^[[:space:]]+command:[[:space:]]*/ {
      value = $0
      sub(/^[[:space:]]+command:[[:space:]]*/, "", value)
      printf "%d:%s:command:%s\n", NR, state, value
      next
    }
    /^[[:space:]]+working_dir:[[:space:]]*/ {
      value = $0
      sub(/^[[:space:]]+working_dir:[[:space:]]*/, "", value)
      printf "%d:%s:working_dir:%s\n", NR, state, value
      next
    }
  ' "$1"
}

check_template() {
  local file="$1"
  local rel="${file#"$REPO_ROOT"/}"
  local entry lineno state field value

  while IFS= read -r entry; do
    [[ -n "$entry" ]] || continue
    lineno="${entry%%:*}"
    entry="${entry#*:}"
    state="${entry%%:*}"
    entry="${entry#*:}"
    field="${entry%%:*}"
    value="${entry#*:}"

    # Strip {{KEY}} references before looking for a `$`, so a template that
    # correctly uses {{PLAN_SLUG}} is not flagged for the braces.
    local stripped="$value"
    while [[ "$stripped" == *'{{'*'}}'* ]]; do
      stripped="${stripped%%\{\{*}${stripped#*\}\}}"
    done

    # A bare variable reference: $NAME or ${NAME}. `$(` is command
    # substitution and is legitimate, so it must not match.
    if [[ "$stripped" =~ \$\{?[A-Za-z_] ]]; then
      echo "FAIL: $rel:$lineno state '$state': $field uses shell-style interpolation"
      echo "  value: $value"
      echo "  koto passes this field to sh -c without resolving \$NAME or \${NAME},"
      echo "  so an unset variable expands to the empty string and the command"
      echo "  silently operates on the wrong value."
      echo "  Fix: declare the variable in the template's 'variables:' block and"
      echo "  reference it as {{NAME}}, passing it with --var at koto init."
      errors=$((errors + 1))
    fi
  done <<< "$(scan_template "$file")"
}

found_any=0
while IFS= read -r template; do
  [[ -n "$template" ]] || continue
  found_any=1
  check_template "$template"
done <<< "$(find "$SEARCH_ROOT" -path '*/koto-templates/*' -name '*.md' | sort)"

if [[ $found_any -eq 0 ]]; then
  echo "check-template-interpolation: no koto templates found under $SEARCH_ROOT"
  exit 0
fi

if [[ $errors -gt 0 ]]; then
  echo ""
  echo "check-template-interpolation: $errors offending field(s)"
  exit 1
fi

echo "check-template-interpolation: OK"
exit 0
