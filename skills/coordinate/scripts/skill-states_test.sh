#!/usr/bin/env bash
# skill-states_test.sh -- SKILL.md's Decisions section names only states the
# template has.
#
# The template is the source of truth for the decision flow; the skill text
# only names its states and checks. Every inline-code word in the section
# that is shaped like a state name (lowercase letters and underscores) must be
# a state of coordinate.md, except the entry states, which are words of the
# record, not of the template. The check is proved against a copy of the
# section naming a state the template doesn't have.
#
# Usage: bash skills/coordinate/scripts/skill-states_test.sh
set -uo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
SKILL="$HERE/../SKILL.md"
TPL="$HERE/../koto-templates/coordinate.md"
PASS=0 FAIL=0
ok()  { PASS=$((PASS + 1)); printf 'ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); printf 'FAIL %s\n     %s\n' "$1" "${2-}"; }
T=$(mktemp -d "${TMPDIR:-/tmp}/skill-states.XXXXXX")
trap 'rm -rf "$T"' EXIT

# The template's states: the `  <state>:` lines of its front matter.
awk 'NR > 1 && /^---$/ { exit } /^  [a-z_]+:$/ { s = $1; sub(/:$/, "", s); print s }' "$TPL" | sort -u > "$T/states"
# Words of the record's Decisions section, not template states: the entry
# states, and the one ground with no hyphen (`scope`).
ENTRY_STATES='proposed escalated settled scope'

# unknown <file>: every state-shaped inline-code word in its Decisions
# section that the template doesn't have.
unknown() {
    awk '/^## Decisions$/ { on = 1; next } /^## / { on = 0 } on' "$1" \
        | grep -oE '`[a-z][a-z_]*`' | tr -d '`' | sort -u \
        | while IFS= read -r w; do
            case " $ENTRY_STATES " in *" $w "*) continue ;; esac
            grep -qx -- "$w" "$T/states" || echo "$w"
        done
}

N=$(awk '/^## Decisions$/ { on = 1; next } /^## / { on = 0 } on' "$SKILL" | grep -oE '`[a-z][a-z_]*`' | sort -u | wc -l | tr -d ' ')
[ "$N" -ge 10 ] && ok "SKILL.md has a Decisions section naming states ($N)" || bad "SKILL.md has a Decisions section naming states" "found $N"
U=$(unknown "$SKILL")
[ -z "$U" ] && ok "every state the Decisions section names is in the template" || bad "every state the Decisions section names is in the template" "$U"

# The failing fixture: the same section naming one state the template lacks.
sed 's/`decision_take`/`decision_ponder`/' "$SKILL" > "$T/SKILL.md"
[ "$(unknown "$T/SKILL.md")" = decision_ponder ] && ok "the check names a state the template doesn't have" \
    || bad "the check names a state the template doesn't have" "$(unknown "$T/SKILL.md")"

echo
echo "skill-states: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
