#!/usr/bin/env bash
# check-cost-rows_test.sh -- scripts/check-cost-rows.sh (shirabe#1116).
#
# Each case builds a throwaway skills/ tree and points the check at it through
# CHECK_COST_ROWS_ROOT. Covers: a skill whose rows and suites agree passes; a
# suite added with no cost row fails naming it, which is the pull request
# #1116 says CI let through; a row naming a removed suite fails; a duplicated
# row fails; a skill with no check-skill.tsv, or one with only shared rows, is
# not checked; only top-level scripts/*_test.sh count as suites; with no
# argument every skill is checked, and a difference in any one fails; a skill
# name outside the pattern, or one that isn't there, is a usage error.
#
# The repository's own tree is not a case here: the workflow runs the check
# on it as its own step, so a missing row in the tree reads as that step
# failing rather than as this harness failing.
#
# Usage: bash scripts/check-cost-rows_test.sh
#
# bash 3.2 floor: no associative arrays, no namerefs, no mapfile.

set -uo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
CHECK="$HERE/check-cost-rows.sh"
# The check runs under the bash running this harness, so a /bin/bash run
# exercises it on 3.2.
BASH_BIN=$(command -v "${BASH:-bash}")
T=$(mktemp -d "${TMPDIR:-/tmp}/check-cost-rows-test.XXXXXX") || exit 1
trap 'rm -rf "$T"' EXIT
PASS=0 FAIL=0
ok() { PASS=$((PASS + 1)); printf 'ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); printf 'FAIL %s\n     %s\n' "$1" "${2-}"; }

# tree: a fresh tree; skill <name> <suite>...: a skill with these suites and a
# helper script that is not a suite; rows <name> <row>...: its check-skill.tsv,
# each row a "kind<TAB>value" pair given as "kind:value".
tree() { rm -rf "$T/root"; mkdir -p "$T/root/skills"; }
skill() {
    local name=$1 s
    shift
    mkdir -p "$T/root/skills/$name/scripts"
    : > "$T/root/skills/$name/scripts/helper.sh"
    for s in "$@"; do : > "$T/root/skills/$name/scripts/$s"; done
}
rows() {
    local name=$1 r
    shift
    printf '# check-skill.tsv\n' > "$T/root/skills/$name/check-skill.tsv"
    for r in "$@"; do
        printf '%s\t%s\t10\n' "${r%%:*}" "${r#*:}" >> "$T/root/skills/$name/check-skill.tsv"
    done
}
# expect <label> <want rc> <want text> [<skill>...]
expect() {
    local label=$1 want=$2 text=$3 out rc
    shift 3
    out=$(CHECK_COST_ROWS_ROOT="$T/root" "$BASH_BIN" "$CHECK" "$@" 2>&1)
    rc=$?
    case "$rc:$out" in
        "$want":*"$text"*) ok "$label" ;;
        *) bad "$label" "rc=$rc out=$out" ;;
    esac
}

tree
skill demo a_test.sh b_test.sh
rows demo cost:a_test.sh cost:b_test.sh shared:helper.sh
expect "rows and suites that agree pass" 0 "1 skill(s) with cost rows" demo

skill demo c_test.sh
expect "a suite added with no cost row fails, naming it" 1 \
    "demo: no cost row for suite scripts/c_test.sh" demo

rm "$T/root/skills/demo/scripts/c_test.sh" "$T/root/skills/demo/scripts/b_test.sh"
expect "a row naming a removed suite fails, naming it" 1 \
    "demo: cost row names no suite: b_test.sh" demo

rows demo cost:a_test.sh cost:a_test.sh
expect "a suite with two cost rows fails, naming it" 1 \
    "demo: more than one cost row for suite a_test.sh" demo

rows demo cost:a_test.sh
mkdir -p "$T/root/skills/demo/scripts/testdata"
: > "$T/root/skills/demo/scripts/testdata/nested_test.sh"
expect "a *_test.sh below scripts/ is not a suite" 0 "1 skill(s)" demo

tree
skill bare x_test.sh
expect "a skill with no check-skill.tsv is not checked" 0 "0 skill(s)" bare
rows bare shared:helper.sh
expect "a skill with only shared rows is not checked" 0 "0 skill(s)" bare

tree
skill one a_test.sh
rows one cost:a_test.sh
skill two a_test.sh b_test.sh
rows two cost:a_test.sh
skill three z_test.sh
expect "with no argument every skill is checked and one difference fails" 1 \
    "two: no cost row for suite scripts/b_test.sh"
rows two cost:a_test.sh cost:b_test.sh
expect "  ... and passes once every skill agrees" 0 "2 skill(s)"

expect "a skill name outside the pattern is a usage error" 2 "not a skill name" ../one
expect "a skill that isn't there is a usage error" 2 "no such skill: nope" nope

echo ""
echo "check-cost-rows_test: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
