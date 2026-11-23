#!/usr/bin/env bash
#
# check-suite-slices.sh - fail a sliced CI job whose slices don't all run
#
# A long suite list runs as a matrix of slices: the job sets SUITE_SLICE from
# its matrix, and the list's runner keeps only that slice through
# scripts/lib/suite-slice.sh. The selector partitions any list exactly, so
# every suite runs as long as every slice runs. This check holds the workflow
# side of that. For every job that sets SUITE_SLICE, in any workflow:
#
#   - SUITE_SLICE is set in the job's own `env:`, to exactly
#     `${{ matrix.slice }}/<n>` with 1 <= n <= 16, and in no step's `env:`;
#   - the job's `strategy.matrix.slice` is exactly the integers [1, ..., n],
#     so no slice is missing, repeated or out of range, and its matrix has no
#     `exclude:` and no `include:` entry naming `slice`, either of which can
#     drop or add a slice the list doesn't show;
#   - its `strategy.fail-fast` is the boolean false, so one failing slice
#     doesn't cancel the others before they report;
#   - the job has no job-level `if:` and no `continue-on-error`, so no slice
#     is skipped or passes having failed;
#   - no `run:` body in the job holds `${{ matrix`: matrix values reach a
#     step through `env:` only.
#
# And every job in REQUIRED below exists and is sliced, so deleting a sliced
# job, or dropping its SUITE_SLICE, fails here rather than quietly shrinking
# what CI runs.
#
# Usage:
#   scripts/check-suite-slices.sh              every workflow, plus REQUIRED
#   scripts/check-suite-slices.sh FILE...      these workflows only
#
# CHECK_SUITE_SLICES_ROOT points the default run at another tree; it is for
# tests.
#
# Requires mikefarah yq v4.
#
# Exit codes:
#   0  every sliced job is well formed and every required job is there
#   1  a violation, each printed with its workflow and job
#   2  a workflow could not be read, or yq is missing
#
# bash 3.2 floor: no associative arrays, no namerefs, no mapfile.

set -uo pipefail

# The sliced jobs that must exist: one `<workflow file name> <job>` pair per
# line, one line per job.
REQUIRED='
check-coordinate-scripts.yml test-coordinate-engine
check-coordinate-scripts.yml test-coordinate-scripts
check-koto-entry-floor.yml entry-floor-coordinate
'

ROOT=${CHECK_SUITE_SLICES_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}

command -v yq >/dev/null 2>&1 || { echo "check-suite-slices: yq (mikefarah v4) is required" >&2; exit 2; }

DEFAULT=0
if [ "$#" -eq 0 ]; then
    DEFAULT=1
    for f in "$ROOT"/.github/workflows/*.yml "$ROOT"/.github/workflows/*.yaml; do
        [ -e "$f" ] && set -- "$@" "$f"
    done
fi

rc=0
violation() {
    echo "check-suite-slices: $1: job $2: $3"
    rc=1
}

# check_job <file> <name> <job>
check_job() {
    local f=$1 name=$2 j=$3 val n want got tag runs
    val=$(J=$j yq -r '.jobs[strenv(J)].env.SUITE_SLICE // ""' "$f")
    case "$val" in
        '${{ matrix.slice }}/'[1-9]|'${{ matrix.slice }}/'1[0-6]) n=${val##*/} ;;
        *) violation "$name" "$j" "SUITE_SLICE is '$val', not \${{ matrix.slice }}/<n> with 1 <= n <= 16"; return ;;
    esac
    want=$(awk -v n="$n" 'BEGIN { s = "["; for (i = 1; i <= n; i++) s = s (i > 1 ? "," : "") i; print s "]" }')
    got=$(J=$j yq -o=json -I=0 '.jobs[strenv(J)].strategy.matrix.slice // null' "$f")
    if [ "$got" != "$want" ]; then
        violation "$name" "$j" "matrix.slice is $got, not $want for SUITE_SLICE .../$n"
    fi
    if [ "$(J=$j yq -r '.jobs[strenv(J)].strategy.matrix | has("exclude")' "$f")" = true ]; then
        violation "$name" "$j" "the matrix has an exclude:, which can drop a slice"
    fi
    if [ "$(J=$j yq -r '[.jobs[strenv(J)].strategy.matrix.include[]? | select(has("slice"))] | length' "$f")" != 0 ]; then
        violation "$name" "$j" "a matrix include: entry names slice"
    fi
    for key in if continue-on-error; do
        if [ "$(J=$j K=$key yq -r '.jobs[strenv(J)] | has(strenv(K))' "$f")" = true ]; then
            violation "$name" "$j" "the job has a job-level $key:, which can skip a slice or pass a failed one"
        fi
    done
    tag=$(J=$j yq -r '.jobs[strenv(J)].strategy."fail-fast" | tag' "$f")
    got=$(J=$j yq -r '.jobs[strenv(J)].strategy."fail-fast"' "$f")
    if [ "$tag" != '!!bool' ] || [ "$got" != false ]; then
        violation "$name" "$j" "strategy.fail-fast is $got, not false"
    fi
    if [ "$(J=$j yq -r '[.jobs[strenv(J)].steps[]? | select((.env // {}) | has("SUITE_SLICE"))] | length' "$f")" != 0 ]; then
        violation "$name" "$j" "a step sets SUITE_SLICE; set it in the job's env only"
    fi
    runs=$(J=$j yq -r '.jobs[strenv(J)].steps[]?.run // ""' "$f")
    if grep -q '\${{ *matrix' <<< "$runs"; then
        violation "$name" "$j" "a run: body holds \${{ matrix ...}}; pass matrix values through env:"
    fi
}

SLICED=""
for f in "$@"; do
    name=$(basename "$f")
    if ! jobs=$(yq -r '.jobs // {} | keys | .[]' "$f" 2>/dev/null); then
        echo "check-suite-slices: cannot read $f" >&2
        exit 2
    fi
    for j in $jobs; do
        sets=$(J=$j yq -r '(.jobs[strenv(J)].env // {} | has("SUITE_SLICE")) or ([.jobs[strenv(J)].steps[]? | select((.env // {}) | has("SUITE_SLICE"))] | length > 0)' "$f")
        [ "$sets" = true ] || continue
        SLICED="$SLICED$name $j
"
        check_job "$f" "$name" "$j"
    done
done

if [ "$DEFAULT" = 1 ]; then
    missing=$(printf '%s\n' "$REQUIRED" | while read -r wf job; do
        [ -n "$wf" ] || continue
        grep -qxF "$wf $job" <<< "$SLICED" \
            || echo "check-suite-slices: $wf: job $job: missing or not sliced (no SUITE_SLICE)"
    done)
    if [ -n "$missing" ]; then
        printf '%s\n' "$missing"
        rc=1
    fi
fi

exit "$rc"
