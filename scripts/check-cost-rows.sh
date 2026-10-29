#!/usr/bin/env bash
#
# check-cost-rows.sh - refuse a skill whose check-skill.tsv cost rows and
# suites differ
#
# scripts/check-skill.sh launches a skill's suites costliest first by the
# `cost` rows of its check-skill.tsv, and a suite with no row launches last.
# A skill that keeps cost rows keeps exactly one per suite (scripts/*_test.sh),
# so a new suite can't quietly launch last and a removed one leaves no row
# behind.
#
# This used to be a case inside scripts/check-skill_test.sh, which pull
# request CI runs only when the check-skill scripts change, so a pull request
# that added a suite without a row stayed green and the daily macOS floor
# caught it on main (shirabe#1116). It compares two lists and runs no suite,
# so .github/workflows/check-cost-rows.yml runs it on every pull request that
# adds or removes a suite or edits a check-skill.tsv. check-skill_test.sh
# still calls it, so the macOS floor checks the same thing.
#
# A skill with no check-skill.tsv, or with one that holds no cost row, has
# opted out of the ordering and is not checked.
#
# Usage:
#   scripts/check-cost-rows.sh            every skill under skills/
#   scripts/check-cost-rows.sh SKILL...   these skills
#
# Prints one line per difference: a suite with no row, a row naming no
# suite, a suite with more than one row. Exit 0 when every checked skill's
# rows and suites agree, 1 when any differ, 2 on a usage error (a skill name
# outside [a-z0-9-], or no such skill).
#
# CHECK_COST_ROWS_ROOT points the check at another tree; it is for tests.
#
# bash 3.2 floor: no associative arrays, no namerefs, no mapfile.

set -uo pipefail

case "${1:-}" in
  -h|--help) sed -n '2,/^$/{s/^# \{0,1\}//;p;}' "$0"; exit 0 ;;
esac

ROOT=${CHECK_COST_ROWS_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}
# sort and comm must collate alike.
export LC_ALL=C

if [ "$#" -eq 0 ]; then
    for d in "$ROOT"/skills/*/; do
        [ -d "$d" ] && set -- "$@" "$(basename "$d")"
    done
fi

for skill in "$@"; do
    case "$skill" in
        ''|*[!a-z0-9-]*) echo "check-cost-rows: not a skill name: $skill" >&2; exit 2 ;;
    esac
    [ -d "$ROOT/skills/$skill" ] || { echo "check-cost-rows: no such skill: $skill" >&2; exit 2; }
done

DIFFER=0
CHECKED=0
for skill in "$@"; do
    tsv="$ROOT/skills/$skill/check-skill.tsv"
    [ -f "$tsv" ] || continue
    rows=$(awk -F'\t' '$1 == "cost" { print $2 }' "$tsv" | sort)
    [ -n "$rows" ] || continue
    CHECKED=$((CHECKED + 1))
    suites=$(for s in "$ROOT/skills/$skill"/scripts/*_test.sh; do
        [ -f "$s" ] && basename "$s"
    done | sort)

    missing=$(comm -13 <(printf '%s\n' "$rows" | sort -u) <(printf '%s\n' "$suites"))
    stale=$(comm -23 <(printf '%s\n' "$rows" | sort -u) <(printf '%s\n' "$suites"))
    twice=$(printf '%s\n' "$rows" | uniq -d)
    for s in $missing; do
        echo "$skill: no cost row for suite scripts/$s"
        DIFFER=1
    done
    for s in $stale; do
        echo "$skill: cost row names no suite: $s"
        DIFFER=1
    done
    for s in $twice; do
        echo "$skill: more than one cost row for suite $s"
        DIFFER=1
    done
done

if [ "$DIFFER" -ne 0 ]; then
    echo "check-cost-rows: add or remove the rows above in the skill's check-skill.tsv; its header says how a cost is measured" >&2
    exit 1
fi
echo "check-cost-rows: $CHECKED skill(s) with cost rows, one row per suite"
