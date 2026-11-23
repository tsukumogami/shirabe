#!/usr/bin/env bash
# check-suite-slices_test.sh -- tests for scripts/check-suite-slices.sh, the
# check that every sliced CI job runs all of its slices.
#
# Each case writes a throwaway workflow and expects the check to pass it or to
# fail it naming the job; the last cases run the check over this repository's
# own workflows and over a tree missing a required sliced job.
#
# Usage: bash scripts/check-suite-slices_test.sh
# Needs mikefarah yq v4.
#
# bash 3.2 floor: no associative arrays, no namerefs, no mapfile.

set -uo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
CHECK="$HERE/check-suite-slices.sh"

PASS_COUNT=0
FAIL_COUNT=0
pass() { printf 'PASS: %s\n' "$*"; PASS_COUNT=$((PASS_COUNT + 1)); }
fail() { printf 'FAIL: %s\n' "$*"; FAIL_COUNT=$((FAIL_COUNT + 1)); }

command -v yq >/dev/null 2>&1 || { echo "check-suite-slices_test: yq (mikefarah v4) is required" >&2; exit 1; }

T=$(mktemp -d "${TMPDIR:-/tmp}/check-suite-slices-test.XXXXXX") || { echo "check-suite-slices_test: no temporary directory" >&2; exit 1; }
trap 'rm -rf "$T"' EXIT

# workflow <file> <strategy lines> <env lines> <run line>: a one-job workflow
# whose job `sliced` has the given strategy, job env and step run.
workflow() {
    {
        printf 'name: fixture\non: pull_request\njobs:\n  plain:\n    runs-on: ubuntu-latest\n    steps:\n      - run: echo plain\n'
        printf '  sliced:\n'
        [ -z "$2" ] || printf '    strategy:\n%s\n' "$2"
        printf '    runs-on: ubuntu-latest\n'
        [ -z "$3" ] || printf '    env:\n%s\n' "$3"
        printf '    steps:\n      - run: %s\n' "$4"
    } > "$1"
}

GOOD_STRATEGY='      fail-fast: false
      matrix:
        slice: [1, 2, 3, 4]'
GOOD_ENV='      SUITE_SLICE: ${{ matrix.slice }}/4'

# expect <label> <want exit> <file> [<text the output must name>]
expect() {
    local label=$1 want=$2 file=$3 text=${4-} out st
    out=$(bash "$CHECK" "$file" 2>&1)
    st=$?
    if [ "$st" -ne "$want" ]; then
        fail "$label: exit $st, want $want; output: $out"
    elif [ -n "$text" ] && ! grep -qF -- "$text" <<< "$out"; then
        fail "$label: output does not name '$text': $out"
    else
        pass "$label"
    fi
}

workflow "$T/good.yml" "$GOOD_STRATEGY" "$GOOD_ENV" 'bash run-tests.sh'
expect "a well-formed sliced job passes" 0 "$T/good.yml"

workflow "$T/gap.yml" '      fail-fast: false
      matrix:
        slice: [1, 2, 4]' "$GOOD_ENV" 'bash run-tests.sh'
expect "matrix.slice [1, 2, 4] under /4 fails and names the job" 1 "$T/gap.yml" "job sliced: matrix.slice is [1,2,4]"

workflow "$T/extra.yml" '      fail-fast: false
      matrix:
        slice: [1, 2, 3, 4, 5]' "$GOOD_ENV" 'bash run-tests.sh'
expect "matrix.slice [1..5] under /4 fails" 1 "$T/extra.yml" "job sliced: matrix.slice"

workflow "$T/strings.yml" '      fail-fast: false
      matrix:
        slice: ["1", "2", "3", "4"]' "$GOOD_ENV" 'bash run-tests.sh'
expect "string slice values fail" 1 "$T/strings.yml" "job sliced: matrix.slice"

workflow "$T/noslice.yml" '      fail-fast: false
      matrix:
        os: [ubuntu-latest]' "$GOOD_ENV" 'bash run-tests.sh'
expect "a job with SUITE_SLICE and no matrix.slice fails" 1 "$T/noslice.yml" "job sliced: matrix.slice is null"

workflow "$T/ff-missing.yml" '      matrix:
        slice: [1, 2, 3, 4]' "$GOOD_ENV" 'bash run-tests.sh'
expect "fail-fast left at its default fails" 1 "$T/ff-missing.yml" "job sliced: strategy.fail-fast"

workflow "$T/ff-true.yml" '      fail-fast: true
      matrix:
        slice: [1, 2, 3, 4]' "$GOOD_ENV" 'bash run-tests.sh'
expect "fail-fast true fails" 1 "$T/ff-true.yml" "job sliced: strategy.fail-fast is true"

workflow "$T/ff-string.yml" '      fail-fast: "false"
      matrix:
        slice: [1, 2, 3, 4]' "$GOOD_ENV" 'bash run-tests.sh'
expect "fail-fast as the string \"false\" fails" 1 "$T/ff-string.yml" "job sliced: strategy.fail-fast"

workflow "$T/run-matrix.yml" "$GOOD_STRATEGY" "$GOOD_ENV" 'SUITE_SLICE=${{ matrix.slice }}/4 bash run-tests.sh'
expect "a run: body holding \${{ matrix fails" 1 "$T/run-matrix.yml" "job sliced: a run: body holds"

workflow "$T/literal.yml" "$GOOD_STRATEGY" '      SUITE_SLICE: 2/4' 'bash run-tests.sh'
expect "a literal SUITE_SLICE fails" 1 "$T/literal.yml" "job sliced: SUITE_SLICE is '2/4'"

workflow "$T/n17.yml" "$GOOD_STRATEGY" '      SUITE_SLICE: ${{ matrix.slice }}/17' 'bash run-tests.sh'
expect "n over 16 fails" 1 "$T/n17.yml" "job sliced: SUITE_SLICE is"

workflow "$T/exclude.yml" '      fail-fast: false
      matrix:
        slice: [1, 2, 3, 4]
        exclude:
          - slice: 3' "$GOOD_ENV" 'bash run-tests.sh'
expect "a matrix exclude: on a sliced job fails" 1 "$T/exclude.yml" "job sliced: the matrix has an exclude:"

workflow "$T/include.yml" '      fail-fast: false
      matrix:
        slice: [1, 2, 3, 4]
        include:
          - slice: 5' "$GOOD_ENV" 'bash run-tests.sh'
expect "a matrix include: naming slice fails" 1 "$T/include.yml" "job sliced: a matrix include: entry names slice"

for key in "if: false" "continue-on-error: true"; do
    {
        printf 'name: fixture\non: pull_request\njobs:\n  sliced:\n    %s\n    strategy:\n%s\n    runs-on: ubuntu-latest\n' "$key" "$GOOD_STRATEGY"
        printf '    env:\n%s\n    steps:\n      - run: bash run-tests.sh\n' "$GOOD_ENV"
    } > "$T/joblevel.yml"
    expect "a job-level ${key%%:*}: on a sliced job fails" 1 "$T/joblevel.yml" "job sliced: the job has a job-level ${key%%:*}:"
done

{
    printf 'name: fixture\non: pull_request\njobs:\n  sliced:\n    strategy:\n%s\n    runs-on: ubuntu-latest\n' "$GOOD_STRATEGY"
    printf '    steps:\n      - run: bash run-tests.sh\n        env:\n          SUITE_SLICE: ${{ matrix.slice }}/4\n'
} > "$T/step-env.yml"
expect "SUITE_SLICE set in a step's env fails" 1 "$T/step-env.yml" "job sliced:"

workflow "$T/nslice-ok.yml" '      fail-fast: false
      matrix:
        slice: [1, 2]
        os: [ubuntu-latest, macos-latest]' '      SUITE_SLICE: ${{ matrix.slice }}/2' 'bash run-tests.sh'
expect "a slice matrix crossed with os passes" 0 "$T/nslice-ok.yml"

printf 'not: [valid\n' > "$T/broken.yml"
expect "an unreadable workflow exits 2" 2 "$T/broken.yml"

# --- the default run: this repository, and a tree missing a required job ----

out=$(bash "$CHECK" 2>&1)
st=$?
if [ "$st" -eq 0 ]; then pass "this repository's workflows pass"; else fail "this repository's workflows: exit $st: $out"; fi

mkdir -p "$T/tree/.github/workflows"
workflow "$T/tree/.github/workflows/check-coordinate-scripts.yml" "" "" 'bash run-tests.sh --engine'
out=$(CHECK_SUITE_SLICES_ROOT="$T/tree" bash "$CHECK" 2>&1)
st=$?
if [ "$st" -eq 1 ] && grep -qF "check-coordinate-scripts.yml: job test-coordinate-engine: missing or not sliced" <<< "$out"; then
    pass "a required sliced job that is gone fails and is named"
else
    fail "missing required job: exit $st: $out"
fi

echo
echo "check-suite-slices_test: $PASS_COUNT passed, $FAIL_COUNT failed"
[ "$FAIL_COUNT" -eq 0 ]
