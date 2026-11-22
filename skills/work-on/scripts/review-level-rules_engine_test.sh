#!/usr/bin/env bash
# review-level-rules_engine_test.sh -- every file a template's gate digest
# covers is in the review-level rules' engine class
# Part of the work-on skill
#
# A template's compatibility file (`<template>.compat.json`) records a digest
# of the scripts its gates and actions reach (check-template-compat.sh). A
# change to one of those scripts can change what a run does, so it belongs in
# the `engine` class of skills/work-on/references/review-level-rules.tsv and
# floors a review at `full` on its own, whether or not the compatibility file
# is in the same diff. This suite checks that, for every template that ships a
# compatibility file:
#
#   - the files `check-template-compat.sh --list` prints (the set the digest
#     hashes, relative to the skill's scripts directory), plus the
#     repository-root files those reach through `$HERE/../../../<path>`, which
#     the digest's own closure doesn't follow, are each matched by an `engine`
#     row;
#   - a rules copy with one covered row removed fails the same check, naming
#     that path, so the check can't pass by matching nothing.
#
# Limit: the scan is static. A path built at run time, or a data file a gate
# reads without naming it through `$HERE`, is outside what it can follow; a
# gate script that reads one keeps that file listed in the engine class by
# hand.
#
# It needs koto (to compile each template) and jq, and is skipped with a note
# when koto is absent.
#
# Usage: review-level-rules_engine_test.sh
#
# Exit codes: 0 every check passed (or skipped), 1 a check failed.
set -uo pipefail
. "$(dirname "$0")/../../../scripts/lib/koto-test-guard.sh" || exit 1

HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../../.." && pwd)
REVIEW_LEVEL="$HERE/review-level.sh"
COMPAT="$ROOT/scripts/check-template-compat.sh"
RULES="$HERE/../references/review-level-rules.tsv"

PASS=0
FAIL=0
pass() { PASS=$((PASS + 1)); echo "PASS: $1"; }
fail() { FAIL=$((FAIL + 1)); echo "FAIL: $1"; }

command -v jq >/dev/null 2>&1 || { echo "review-level-rules_engine_test: jq is required" >&2; exit 1; }
if ! command -v "${KOTO_BIN:-koto}" >/dev/null 2>&1; then
    echo "review-level-rules_engine_test: koto is not installed; skipped"
    exit 0
fi

WORK=$(mktemp -d) || exit 1
cleanup() { [ -n "${WORK:-}" ] && rm -rf "$WORK"; return 0; }
ktg_on_exit cleanup

# covered <template>: the repository-relative paths the template's gate digest
# covers, plus the repository-root files they reach through $HERE/../../../.
covered() {
    local template=$1 skill_scripts rel
    skill_scripts=$(cd "$(dirname "$template")/../scripts" && pwd) || return 1
    bash "$COMPAT" --template "$template" --list > "$WORK/list" || return 1
    while IFS= read -r rel; do
        [ -n "$rel" ] || continue
        printf '%s\n' "${skill_scripts#"$ROOT"/}/$rel"
        # Most files reach nothing outside their skill; grep's exit 1 for
        # "no match" is not a failure here.
        { grep -oE '\$HERE/\.\./\.\./\.\./[A-Za-z0-9_][A-Za-z0-9_./-]*\.(sh|jq|tsv)' "$skill_scripts/$rel" || true; } \
            | sed 's|^\$HERE/\.\./\.\./\.\./||'
    done < "$WORK/list" | LC_ALL=C sort -u
}

# missing <rules-file> <paths-file>: the paths no engine row of the rules
# file matches, one per line.
missing() {
    # shellcheck disable=SC2046
    REVIEW_LEVEL_RULES="$1" bash "$REVIEW_LEVEL" classify $(cat "$2") \
        | awk -F'\t' '{ n = split($2, c, ","); e = 0; for (i = 1; i <= n; i++) if (c[i] == "engine") e = 1; if (!e) print $1 }'
}

TEMPLATES=$(cd "$ROOT" && ls skills/*/koto-templates/*.compat.json 2>/dev/null | sed 's|\.compat\.json$|.md|')
[ -n "$TEMPLATES" ] && pass "found templates with a compatibility file" \
    || fail "no skills/*/koto-templates/*.compat.json found under $ROOT"

for t in $TEMPLATES; do
    name=$(basename "$t" .md)
    if ! covered "$ROOT/$t" > "$WORK/$name.paths" || [ ! -s "$WORK/$name.paths" ]; then
        fail "$name: could not list the files its gate digest covers"
        continue
    fi
    n=$(wc -l < "$WORK/$name.paths" | tr -d ' ')
    out=$(cd "$ROOT" && missing "$RULES" "$WORK/$name.paths")
    if [ -z "$out" ]; then
        pass "$name: all $n files its gate digest covers are in the engine class"
    else
        fail "$name: not in the engine class of review-level-rules.tsv: $(printf '%s' "$out" | paste -sd' ' -)"
    fi

    # The check fails when a covered row goes away. The first covered path
    # with its own exact engine row is dropped from a copy of the rules.
    drop=
    while IFS= read -r p; do
        if grep -qxF "class	engine	$p" "$RULES"; then drop=$p; break; fi
    done < "$WORK/$name.paths"
    if [ -z "$drop" ]; then
        fail "$name: no covered path has its own engine row to remove for the negative case"
        continue
    fi
    grep -vxF "class	engine	$drop" "$RULES" > "$WORK/rules-minus.tsv"
    base=$(cd "$ROOT" && missing "$RULES" "$WORK/$name.paths")
    out=$(cd "$ROOT" && missing "$WORK/rules-minus.tsv" "$WORK/$name.paths")
    added=$(comm -13 <(printf '%s\n' "$base" | LC_ALL=C sort) <(printf '%s\n' "$out" | LC_ALL=C sort) | grep -v '^$')
    [ "$added" = "$drop" ] \
        && pass "$name: removing the engine row for $drop makes the check name it" \
        || fail "$name: with $drop's row removed the check reported [$out]"
done

echo
echo "review-level-rules_engine_test: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
