#!/usr/bin/env bash
# koto-minimum-consistency_test.sh -- every place that states shirabe's koto
# minimum states the one value scripts/assert-koto-floor.sh defines.
#
# The minimum is defined once, as FLOOR in scripts/assert-koto-floor.sh, and
# read through `assert-koto-floor.sh --print-floor` by everything that needs the
# number: check-koto-entry-floor.yml, check-koto-release.sh and its test, and
# this file. The prose that tells a reader the minimum (README, the guides, the
# references, the skills, the requires.tsv comments, the templates' comments,
# the tool manifest's comment) restates it. A restatement that disagrees is the
# failure this exists for: it goes stale silently when the minimum moves, and a
# reader who trusts it installs a koto shirabe no longer supports.
#
# Cases:
#   the minimum reads through --print-floor
#   the matcher fires on each planted disagreement, passes a planted
#     agreement, and ignores another tool's version (the controls, so a green
#     run is not a matcher that matches nothing or everything)
#   no minimum statement in the scanned files names a different version. The
#     forms read as a minimum, each anchored to the word koto:
#       koto <v> or later              requires / needs koto <v>
#       koto minimum (is) <v>          <v> (and later), shirabe's koto minimum
#       exactly koto <v>               koto <v>, the floor
#       the koto <v> floor             <v>, which shirabe's (koto) minimum requires
#     A sentence saying what a release introduced -- "koto <v> and later",
#     "shipped in <v>", "<v> is the release that ..." -- is history and
#     deliberately not matched. That is also the way out of a false positive:
#     the failure names each file, line and phrase, and says so.
#   no workflow installs a literal koto release, the entry-floor job and
#     check-koto-release.sh read the minimum through --print-floor, and no
#     script or workflow reads the FLOOR line with a copy of its own
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
BASH_BIN=$(command -v "${BASH:-bash}")

PASS_COUNT=0
FAIL_COUNT=0
pass() { printf 'PASS: %s\n' "$*"; PASS_COUNT=$((PASS_COUNT + 1)); }
fail() { printf 'FAIL: %s\n' "$*"; FAIL_COUNT=$((FAIL_COUNT + 1)); }

T=$(mktemp -d "${TMPDIR:-/tmp}/koto-minimum-test.XXXXXX")
cleanup() { [ -n "${T:-}" ] && rm -rf "$T"; return 0; }
trap cleanup EXIT

MINIMUM=$("$BASH_BIN" "$ASSERT" --print-floor 2>/dev/null)
if printf '%s' "$MINIMUM" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$'; then
    pass "the koto minimum reads through assert-koto-floor.sh --print-floor ($MINIMUM)"
else
    fail "assert-koto-floor.sh --print-floor did not print a MAJOR.MINOR.PATCH: [$MINIMUM]"
    echo
    echo "koto-minimum-consistency_test.sh: $PASS_COUNT passed, $FAIL_COUNT failed"
    exit 1
fi

V='v?[0-9]+\.[0-9]+\.[0-9]+'
FORMS="koto( minimum( is)?)? $V or later"
FORMS="$FORMS|(requires?|needs?) koto $V"
FORMS="$FORMS|koto minimum( is)? $V"
FORMS="$FORMS|koto $V, the floor"
FORMS="$FORMS|the koto $V floor"
FORMS="$FORMS|$V( and later)?, shirabe's koto minimum"
FORMS="$FORMS|$V,? which shirabe's (koto )?minimum requires"
FORMS="$FORMS|exactly koto $V"

# statements <file>: prints each version a minimum statement in <file> names,
# one per line, as `<version>\t<the matched text>`. The file is flattened first:
# leading whitespace and comment markers (#, //, >) are dropped from each line
# and the lines are joined with a space, so a statement wrapped across lines
# reads as one.
statements() {
    # -E, because BSD sed has no \| in a basic expression: without it macOS
    # left the comment markers in and read a wrapped statement as two.
    sed -E 's/^[[:space:]]*(#+|\/\/|>)?[[:space:]]*//' "$1" \
        | tr '\n' ' ' \
        | tr -s ' ' \
        | grep -oiE "($FORMS)" \
        | while IFS= read -r m; do
            v=$(printf '%s' "$m" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
            printf '%s\t%s\n' "$v" "$m"
        done
}

# mismatches <file>: the statements in <file> naming anything but the minimum.
mismatches() {
    statements "$1" | awk -F '\t' -v want="$MINIMUM" '$1 != want { print }'
}

# line_of <file> <version> <phrase>: the first line holding the whole phrase,
# or, for a phrase wrapped across lines, the first line naming the version.
line_of() {
    local n
    n=$(grep -niF -- "$3" "$1" 2>/dev/null | head -1 | cut -d: -f1)
    [ -n "$n" ] || n=$(grep -nF -- "$2" "$1" 2>/dev/null | head -1 | cut -d: -f1)
    printf '%s' "$n"
}

# --- the controls ---------------------------------------------------------------

printf '# /work-on requires koto\n# 0.12.2 or later.\n' >"$T/bad.md"
printf '      koto 0.12.2, the floor for runs\n# keeps the koto v0.12.2 floor for every run\n' >"$T/bad-floor.md"
printf 'It describes koto 0.12.2 and later, shirabe%ss koto minimum.\nCI runs the suites on exactly koto 0.12.2.\n' "'" >"$T/bad-minimum.md"
printf '/deliver needs koto\nv0.12.2 to run at all.\n' >"$T/bad-needs.md"
printf 'koto 0.12.2, which shirabe%ss minimum requires, records a wake.\n' "'" >"$T/bad-requires.md"
printf 'Every skill needs koto v%s, and\nkoto %s or later is tested.\n' "$MINIMUM" "$MINIMUM" >"$T/good.md"
printf 'The floor image needs v4.44.1 of yq, and the leg runs\nexactly 3.2.57 as /bin/bash.\n' >"$T/other-tool.md"
if [ -n "$(mismatches "$T/bad.md")" ]; then
    pass "the matcher flags a wrapped, commented statement of another version (control)"
else
    fail "the matcher missed a planted disagreement -- a green run below would prove nothing"
fi
if [ "$(mismatches "$T/bad-floor.md" | wc -l | tr -d ' ')" = 2 ]; then
    pass "the matcher flags both 'the floor' phrasings of another version (control)"
else
    fail "the matcher missed a 'the floor' phrasing: $(statements "$T/bad-floor.md" | tr '\n' ';')"
fi
if [ "$(mismatches "$T/bad-minimum.md" | wc -l | tr -d ' ')" = 2 ]; then
    pass "the matcher flags 'shirabe's koto minimum' and 'exactly koto' phrasings of another version (control)"
else
    fail "the matcher missed a 'shirabe's koto minimum' or 'exactly koto' phrasing: $(statements "$T/bad-minimum.md" | tr '\n' ';')"
fi
if [ -n "$(mismatches "$T/bad-needs.md")" ]; then
    pass "the matcher flags a wrapped 'needs koto <version>' (control)"
else
    fail "the matcher missed a wrapped 'needs koto <version>'"
fi
if [ -n "$(mismatches "$T/bad-requires.md")" ]; then
    pass "the matcher flags '<version>, which shirabe's minimum requires' (control)"
else
    fail "the matcher missed '<version>, which shirabe's minimum requires'"
fi
if [ -z "$(statements "$T/other-tool.md")" ]; then
    pass "the matcher ignores another tool's version after 'needs' or 'exactly' (control)"
else
    fail "the matcher read another tool's version as a koto minimum: $(statements "$T/other-tool.md" | tr '\n' ';')"
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
    'skills/*/scripts/*.sh' '.github/workflows/*.yml' 'scripts/*.sh' 2>/dev/null | sort -u)
# A tree git can't read (the bash-floor container mounts a worktree whose .git
# points outside it) is walked with find over the same set instead. A git
# pathspec `*` crosses `/`, so both walks descend.
if [ -z "$FILES" ]; then
    FILES=$(cd "$REPO" && {
        for f in README.md CLAUDE.md .tsuku.toml; do [ -f "$f" ] && echo "$f"; done
        find docs/guides references -name '*.md' 2>/dev/null
        find skills \( -name SKILL.md -o -name requires.tsv \) 2>/dev/null
        find skills -path '*/koto-templates/*.md' 2>/dev/null
        find skills -path '*/references/*.md' 2>/dev/null
        find .github/workflows -name '*.yml' 2>/dev/null
        find scripts -name '*.sh' 2>/dev/null
        find skills -path '*/scripts/*.sh' 2>/dev/null
    } | sort -u)
fi
if [ -z "$FILES" ]; then
    fail "found nothing to scan under $REPO"
fi

SCANNED=0
BAD=""
for f in $FILES; do
    [ -f "$REPO/$f" ] || continue
    # This file plants other versions as its controls.
    [ "$f" = scripts/koto-minimum-consistency_test.sh ] && continue
    SCANNED=$((SCANNED + 1))
    m=$(mismatches "$REPO/$f")
    [ -n "$m" ] || continue
    while IFS="	" read -r v phrase; do
        BAD="$BAD
  $f:$(line_of "$REPO/$f" "$v" "$phrase"): \"$phrase\""
    done <<<"$m"
done
if [ -n "$BAD" ]; then
    fail "these statements name a koto minimum other than $MINIMUM:$BAD
  For each: if it states shirabe's minimum, change the version to $MINIMUM.
  If it records what a release introduced, reword it as history (\"koto <v>
  and later\", \"shipped in <v>\", \"<v> is the release that ...\"); the header
  of this file lists the forms read as a minimum."
else
    pass "no minimum statement in $SCANNED scanned files names anything but $MINIMUM"
fi

# --- the readers ----------------------------------------------------------------

LITERAL=$(cd "$REPO" && grep -nE 'koto@v?[0-9]+\.[0-9]' .github/workflows/*.yml 2>/dev/null)
if [ -n "$LITERAL" ]; then
    fail "a workflow installs a literal koto release instead of the minimum read from assert-koto-floor.sh:
$LITERAL"
else
    pass "no workflow installs a literal koto release"
fi

ENTRY="$REPO/.github/workflows/check-koto-entry-floor.yml"
if grep -qF 'assert-koto-floor.sh --print-floor' "$ENTRY" && grep -q 'koto@\$KOTO_FLOOR_RELEASE' "$ENTRY"; then
    pass "check-koto-entry-floor.yml installs the release assert-koto-floor.sh --print-floor names"
else
    fail "check-koto-entry-floor.yml no longer reads the minimum through --print-floor, or no longer installs it"
fi
if grep -qF 'assert-koto-floor.sh" --print-floor' "$REPO/scripts/check-koto-release.sh"; then
    pass "check-koto-release.sh reads the minimum through --print-floor"
else
    fail "check-koto-release.sh no longer reads the minimum through --print-floor"
fi
COPIES=$(cd "$REPO" && grep -lF 'KOTO_FLOOR:-\(' .github/workflows/*.yml scripts/*.sh scripts/lib/*.sh skills/*/scripts/*.sh 2>/dev/null | grep -v '^scripts/koto-minimum-consistency_test.sh$')
if [ -z "$COPIES" ]; then
    pass "no script or workflow reads the FLOOR line with a sed copy of its own"
else
    fail "these read the FLOOR line with their own sed; call assert-koto-floor.sh --print-floor instead:
$COPIES"
fi

echo
echo "koto-minimum-consistency_test.sh: $PASS_COUNT passed, $FAIL_COUNT failed"
[ "$FAIL_COUNT" -eq 0 ]
