#!/usr/bin/env bash
# skill-states_test.sh -- the decision states' guidance names only decision
# states the template has.
#
# The decision flow's rules live in the template's `## decision_*` sections,
# the guidance a tick shows when it stops at one
# (docs/designs/DESIGN-coordinate-entry-budget.md). The frontmatter is the
# source of truth for the flow, and the guidance only names its states, so
# every inline-code word in those sections shaped like a decision state
# (`decision_` and lowercase letters and underscores) must be a state of
# coordinate.md. The check is proved against a copy of the template whose
# guidance names a decision state it doesn't have.
#
# Usage: bash skills/coordinate/scripts/skill-states_test.sh
set -uo pipefail
. "$(dirname "$0")/../../../scripts/lib/koto-test-guard.sh" || exit 1
HERE=$(cd "$(dirname "$0")" && pwd)
TPL="$HERE/../koto-templates/coordinate.md"
PASS=0 FAIL=0
ok()  { PASS=$((PASS + 1)); printf 'ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); printf 'FAIL %s\n     %s\n' "$1" "${2-}"; }
T=$(mktemp -d "${TMPDIR:-/tmp}/skill-states.XXXXXX") || exit 1
ktg_on_exit 'rm -rf "$T"'

# states <template>: the `  <state>:` lines of its front matter.
states() { awk 'NR > 1 && /^---$/ { exit } /^  [a-z_]+:$/ { s = $1; sub(/:$/, "", s); print s }' "$1" | sort -u; }

# named <template>: every decision-state-shaped inline-code word in the
# guidance of its decision states.
named() {
    awk '/^## decision_/ { on = 1; next } /^## / { on = 0 } on' "$1" \
        | grep -oE '`decision_[a-z_]+`' | tr -d '`' | sort -u
}

# unknown <template>: the named words that aren't states of it.
unknown() {
    states "$1" > "$T/states"
    named "$1" | while IFS= read -r w; do grep -qx -- "$w" "$T/states" || echo "$w"; done
}

N=$(named "$TPL" | wc -l | tr -d ' ')
[ "$N" -ge 3 ] && ok "the decision states' guidance names decision states ($N)" || bad "the decision states' guidance names decision states" "found $N"
U=$(unknown "$TPL")
[ -z "$U" ] && ok "every decision state the guidance names is in the template" || bad "every decision state the guidance names is in the template" "$U"

# The failing fixture: the same template whose guidance names one decision
# state it lacks. Only the guidance changes; the frontmatter keeps its states.
awk 'NR > 1 && /^---$/ { body = 1 } body && /^## decision_/ { on = 1 } body && /^## / && !/^## decision_/ { on = 0 }
     on { gsub(/`decision_next`/, "`decision_ponder`") } { print }' "$TPL" > "$T/coordinate.md"
[ "$(unknown "$T/coordinate.md")" = decision_ponder ] && ok "the check names a state the template doesn't have" \
    || bad "the check names a state the template doesn't have" "$(unknown "$T/coordinate.md")"

echo
echo "skill-states: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
