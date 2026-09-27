#!/usr/bin/env bash
# koto-minimum-consistency_test.sh -- every place that states shirabe's koto
# minimum states the one value scripts/assert-koto-floor.sh defines.
#
# The minimum is defined once, as FLOOR in scripts/assert-koto-floor.sh. The
# workflows that install exactly the minimum, and scripts/check-koto-release.sh,
# read it from there; the prose that tells a reader the minimum (README, the
# guides, the references, the skills, the requires.tsv comments, the templates'
# comments, the tool manifest's comment) restates it. A restatement that
# disagrees is the failure this exists for: it goes stale silently when the
# minimum moves, and a reader who trusts it installs a koto shirabe no longer
# supports.
#
# Cases:
#   the minimum reads from its one definition
#   the matcher fires on a planted disagreement and passes a planted agreement
#     (the control, so a green run is not a matcher that matches nothing)
#   no statement of the form "koto <version> or later", "requires/needs koto
#     <version>", or "koto minimum <version>" in the scanned files names a
#     different version
#   no workflow installs a literal koto release; the one that installs the
#     minimum reads it from assert-koto-floor.sh with the same sed as
#     check-koto-release.sh
#
# Statements are matched across line breaks and comment markers, so a sentence
# wrapped in a YAML or shell comment is read as a sentence. docs/designs,
# docs/prds and docs/plans are not scanned: they record what was decided at the
# time, including earlier minimums.
#
# Usage: bash scripts/koto-minimum-consistency_test.sh
#
# Exit codes:
#   0 -- all cases pass
#   1 -- one or more cases failed
#
# bash 3.2 floor: no associative arrays, no namerefs, no mapfile.

set -uo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
REPO=$(cd "$SCRIPT_DIR/.." && pwd)
ASSERT="$REPO/scripts/assert-koto-floor.sh"

PASS_COUNT=0
FAIL_COUNT=0
pass() { printf 'PASS: %s\n' "$*"; PASS_COUNT=$((PASS_COUNT + 1)); }
fail() { printf 'FAIL: %s\n' "$*"; FAIL_COUNT=$((FAIL_COUNT + 1)); }

T=$(mktemp -d "${TMPDIR:-/tmp}/koto-minimum-test.XXXXXX")
cleanup() { [ -n "${T:-}" ] && rm -rf "$T"; return 0; }
trap cleanup EXIT

# The read the workflows and check-koto-release.sh make.
FLOOR_SED='s/^FLOOR="\${KOTO_FLOOR:-\([0-9.]*\)}"$/\1/p'
MINIMUM=$(sed -n "$FLOOR_SED" "$ASSERT" | head -1)
if printf '%s' "$MINIMUM" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$'; then
    pass "the koto minimum reads from scripts/assert-koto-floor.sh ($MINIMUM)"
else
    fail "cannot read the koto minimum from scripts/assert-koto-floor.sh: [$MINIMUM]"
    echo
    echo "koto-minimum-consistency_test.sh: $PASS_COUNT passed, $FAIL_COUNT failed"
    exit 1
fi

# statements <file>: prints each version a minimum statement in <file> names,
# one per line, as `<version>\t<the matched text>`. The file is flattened first:
# leading whitespace and comment markers (#, //, >) are dropped from each line
# and the lines are joined with a space, so a statement wrapped across lines
# reads as one.
statements() {
    sed -e 's/^[[:space:]]*\(#\{1,\}\|\/\/\|>\)\{0,1\}[[:space:]]*//' "$1" \
        | tr '\n' ' ' \
        | tr -s ' ' \
        | grep -oiE "(koto( minimum( is)?)? v?[0-9]+\.[0-9]+\.[0-9]+ or later|(requires?|needs?) koto v?[0-9]+\.[0-9]+\.[0-9]+|koto minimum( is)? v?[0-9]+\.[0-9]+\.[0-9]+)" \
        | while IFS= read -r m; do
            v=$(printf '%s' "$m" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
            printf '%s\t%s\n' "$v" "$m"
        done
}

# mismatches <file>: the statements in <file> naming anything but the minimum.
mismatches() {
    statements "$1" | awk -F '\t' -v want="$MINIMUM" '$1 != want { print }'
}

# --- the control ----------------------------------------------------------------

printf '# /work-on requires koto\n# 0.12.2 or later.\n' >"$T/bad.md"
printf 'Every skill needs koto v%s, and\nkoto %s or later is tested.\n' "$MINIMUM" "$MINIMUM" >"$T/good.md"
if [ -n "$(mismatches "$T/bad.md")" ]; then
    pass "the matcher flags a wrapped, commented statement of another version (control)"
else
    fail "the matcher missed a planted disagreement -- a green run below would prove nothing"
fi
if [ "$(statements "$T/good.md" | wc -l | tr -d ' ')" = 2 ] && [ -z "$(mismatches "$T/good.md")" ]; then
    pass "the matcher reads both planted statements of the minimum and accepts them (control)"
else
    fail "the matcher misread a planted agreement: $(statements "$T/good.md" | tr '\n' ';')"
fi

# --- the scan -------------------------------------------------------------------

FILES=$(cd "$REPO" && git ls-files -- \
    README.md CLAUDE.md .tsuku.toml \
    'docs/guides/*.md' 'references/*.md' 'references/**/*.md' \
    'skills/*/SKILL.md' 'skills/*/requires.tsv' 'skills/*/koto-templates/*.md' \
    'skills/*/references/*.md' 'skills/*/references/**/*.md' \
    '.github/workflows/*.yml' 'scripts/*.sh' 2>/dev/null | sort -u)
# A tree git can't read (the bash-floor container mounts a worktree whose .git
# points outside it) is walked with find over the same set instead.
if [ -z "$FILES" ]; then
    FILES=$(cd "$REPO" && {
        for f in README.md CLAUDE.md .tsuku.toml; do [ -f "$f" ] && echo "$f"; done
        find docs/guides references -name '*.md' 2>/dev/null
        find skills \( -name SKILL.md -o -name requires.tsv \) 2>/dev/null
        find skills -path '*/koto-templates/*.md' 2>/dev/null
        find skills -path '*/references/*.md' 2>/dev/null
        find .github/workflows -name '*.yml' 2>/dev/null
        find scripts -maxdepth 1 -name '*.sh' 2>/dev/null
    } | sort -u)
fi
if [ -z "$FILES" ]; then
    fail "found nothing to scan under $REPO"
fi

SCANNED=0
BAD=""
for f in $FILES; do
    [ -f "$REPO/$f" ] || continue
    SCANNED=$((SCANNED + 1))
    m=$(mismatches "$REPO/$f")
    [ -n "$m" ] && BAD="$BAD
$f: $(printf '%s' "$m" | cut -f2 | tr '\n' ';')"
done
if [ -n "$BAD" ]; then
    fail "these files state a koto minimum other than $MINIMUM:$BAD"
else
    pass "no minimum statement in $SCANNED scanned files names anything but $MINIMUM"
fi

# --- the workflows --------------------------------------------------------------

LITERAL=$(cd "$REPO" && grep -nE 'koto@v?[0-9]+\.[0-9]' .github/workflows/*.yml 2>/dev/null)
if [ -n "$LITERAL" ]; then
    fail "a workflow installs a literal koto release instead of the minimum read from assert-koto-floor.sh:
$LITERAL"
else
    pass "no workflow installs a literal koto release"
fi

ENTRY="$REPO/.github/workflows/check-koto-entry-floor.yml"
if grep -qF "$FLOOR_SED" "$ENTRY" && grep -q 'koto@\$KOTO_FLOOR_RELEASE' "$ENTRY"; then
    pass "check-koto-entry-floor.yml installs the release it reads from assert-koto-floor.sh"
else
    fail "check-koto-entry-floor.yml no longer reads the minimum from assert-koto-floor.sh, or no longer installs it"
fi
if grep -qF "$FLOOR_SED" "$REPO/scripts/check-koto-release.sh"; then
    pass "check-koto-release.sh reads the minimum from assert-koto-floor.sh"
else
    fail "check-koto-release.sh no longer reads the minimum from assert-koto-floor.sh"
fi

echo
echo "koto-minimum-consistency_test.sh: $PASS_COUNT passed, $FAIL_COUNT failed"
[ "$FAIL_COUNT" -eq 0 ]
