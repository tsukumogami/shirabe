#!/usr/bin/env bash
# test-classify_test.sh -- test-classify.sh labels each test file a unit's
# committed diff touched by the shape of its change.
#
# Covers: one diff that adds a test file, appends lines to another, removes a
# line from a third, deletes a fourth and renames a fifth unchanged, labelled
# added, added, edited, edited and unchanged; the head's blob id as the digest
# and `deleted` for a deleted file; a non-test path left out; an uncommitted
# change left out; a test renamed out of the class with an edit still edited;
# a binary test file that changed is edited; the class read from the rules
# file given, so a narrower copy drops a path; a base that names no commit and
# a rules file with no test class (exit 2). test_classify_unit gives the same
# rows with no record, and with a red's record labels a reproducing test or
# harness file changed since the red edited, even one that only gained lines;
# a record that doesn't parse is exit 2.
#
# Usage: bash scripts/lib/test-classify_test.sh
set -uo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../.." && pwd)
command -v git >/dev/null 2>&1 || { echo "SKIP: git not on PATH"; exit 0; }
# shellcheck source=test-classify.sh
. "$HERE/test-classify.sh"
RULES="$ROOT/skills/work-on/references/review-level-rules.tsv"

PASS=0 FAIL=0
ok()  { PASS=$((PASS + 1)); printf 'ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); printf 'FAIL %s\n     %s\n' "$1" "${2-}"; }
eq() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "want [$2], got [$3]"; fi; }

W=$(mktemp -d) || { echo "FAIL: could not create a temporary directory"; exit 1; }
trap 'rm -rf "$W"' EXIT
R="$W/repo"
mkdir -p "$R"
cd "$R" || exit 1
git init -q -b main .
git config user.email t@example.com
git config user.name t
mkdir -p tests src
printf 'a1\na2\n' > tests/append_test.sh
printf 'r1\nr2\nr3\n' > tests/remove_test.sh
printf 'd1\n' > tests/delete_test.sh
printf 'm1\nm2\nm3\nm4\nm5\n' > tests/move_test.sh
printf 'o1\no2\no3\no4\no5\no6\n' > tests/out_test.sh
printf 'bin\000ary\n' > tests/fixture_test.bin
printf 'code\n' > src/main.sh
git add -A
git commit -q -m base
BASE=$(git rev-parse HEAD)

printf 'n1\n' > tests/new_test.sh
printf 'a3\n' >> tests/append_test.sh
printf 'r1\nr3\n' > tests/remove_test.sh
git rm -q tests/delete_test.sh
git mv tests/move_test.sh tests/moved_test.sh
mkdir -p docs
git mv tests/out_test.sh docs/out.txt
printf 'o1\no2\no3\no4\no5\n' > docs/out.txt
printf 'bin\000ary2\n' > tests/fixture_test.bin
printf 'more code\n' >> src/main.sh
git add -A
git commit -q -m change
HEAD_SHA=$(git rev-parse HEAD)
# Uncommitted: never part of the diff.
printf 'dirty\n' >> tests/new_test.sh
printf 'u\n' > tests/untracked_test.sh

OUT=$(test_classify "$BASE" "$HEAD_SHA" "$RULES")
eq "test_classify exits 0" 0 $?
label() { printf '%s\n' "$OUT" | awk -F '\t' -v p="$1" '$2 == p { print $1 }'; }
digest() { printf '%s\n' "$OUT" | awk -F '\t' -v p="$1" '$2 == p { print $3 }'; }

eq "a new test file is added" added "$(label tests/new_test.sh)"
eq "a test file that only gained lines is added" added "$(label tests/append_test.sh)"
eq "a test file that lost a line is edited" edited "$(label tests/remove_test.sh)"
eq "a deleted test file is edited" edited "$(label tests/delete_test.sh)"
eq "a rename that changes no line is unchanged" unchanged "$(label tests/moved_test.sh)"
eq "a test renamed out of the class with an edit is still edited" edited "$(label docs/out.txt)"
eq "a binary test file that changed is edited" edited "$(label tests/fixture_test.bin)"
eq "a non-test path is left out" "" "$(label src/main.sh)"
eq "an untracked test file is left out" "" "$(label tests/untracked_test.sh)"
eq "the digest is the blob id at the head" "$(git rev-parse "$HEAD_SHA:tests/new_test.sh")" "$(digest tests/new_test.sh)"
eq "an uncommitted change doesn't move the digest" "$(git rev-parse "$HEAD_SHA:tests/new_test.sh")" "$(git rev-parse HEAD:tests/new_test.sh)"
eq "a deleted file's digest is the word deleted" deleted "$(digest tests/delete_test.sh)"
eq "seven rows, one per test path" 7 "$(printf '%s\n' "$OUT" | grep -c .)"

# The class comes from the rules file passed, not the shipped one.
printf 'class\ttest\t**/new_test.*\n' > "$W/narrow.tsv"
eq "a rules copy with one glob keeps one path" "added	tests/new_test.sh" \
    "$(test_classify "$BASE" "$HEAD_SHA" "$W/narrow.tsv" | cut -f 1,2)"

test_classify 0123456789abcdef0123456789abcdef01234567 "$HEAD_SHA" "$RULES" >/dev/null 2>&1
eq "a base that names no commit: exit 2" 2 $?
printf 'class\tdocs\t*.md\n' > "$W/notest.tsv"
test_classify "$BASE" "$HEAD_SHA" "$W/notest.tsv" >/dev/null 2>&1
eq "a rules file with no test class: exit 2" 2 $?
eq "no rows when nothing changed" "" "$(test_classify "$HEAD_SHA" "$HEAD_SHA" "$RULES")"

# test_classify_unit: the same rows, plus a fix's reproducing tests changed
# since the red.
eq "test_classify_unit with no record: test_classify's rows" "$OUT" "$(test_classify_unit "$BASE" "$HEAD_SHA" "$RULES")"
: > "$W/empty.json"
eq "test_classify_unit with an empty record: the same rows" "$OUT" "$(test_classify_unit "$BASE" "$HEAD_SHA" "$RULES" "$W/empty.json")"
command -v jq >/dev/null 2>&1 && {
    printf '{"red":{"tests":[{"path":"tests/new_test.sh","blob":"%s"}],"harness":[{"path":"src/main.sh","blob":"%s"}]}}\n' \
        "$(git rev-parse "$HEAD_SHA:tests/new_test.sh")" "$(git rev-parse "$BASE:src/main.sh")" > "$W/red.json"
    U=$(test_classify_unit "$BASE" "$HEAD_SHA" "$RULES" "$W/red.json")
    eq "a reproducing test unchanged since the red keeps its label" added \
        "$(printf '%s\n' "$U" | awk -F '\t' '$2 == "tests/new_test.sh" { print $1 }')"
    eq "a harness file changed since the red is added as edited" "edited	src/main.sh	$(git rev-parse "$HEAD_SHA:src/main.sh")" \
        "$(printf '%s\n' "$U" | awk -F '\t' '$2 == "src/main.sh"')"
    printf '{"red":{"tests":[{"path":"tests/append_test.sh","blob":"%s"}]}}\n' "$(git rev-parse "$BASE:tests/append_test.sh")" > "$W/red2.json"
    eq "a reproducing test that only gained lines after the red is edited" edited \
        "$(test_classify_unit "$BASE" "$HEAD_SHA" "$RULES" "$W/red2.json" | awk -F '\t' '$2 == "tests/append_test.sh" { print $1 }')"
    printf 'not json\n' > "$W/bad.json"
    test_classify_unit "$BASE" "$HEAD_SHA" "$RULES" "$W/bad.json" >/dev/null 2>&1
    eq "a record that doesn't parse: exit 2" 2 $?
}
test_classify_unit 0123456789abcdef0123456789abcdef01234567 "$HEAD_SHA" "$RULES" >/dev/null 2>&1
eq "test_classify_unit passes test_classify's exit 2 on" 2 $?

echo
echo "test-classify: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
