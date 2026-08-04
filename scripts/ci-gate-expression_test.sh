#!/usr/bin/env bash
# Tests for the ci_passing gate expression carried by the koto templates.
#
# The gate decides whether a pull request's checks are green. It's a shell
# pipeline embedded in a YAML string, so nothing else in the repo exercises it.
# This test pulls the live command out of each template and drives its jq filter
# against synthetic `gh pr checks` payloads, so it can't drift from what ships.
#
# The payloads carry only the fields the command actually asks gh for. That's
# what catches a command that requests one field and filters on another.
#
# The bucket values below come from gh's own aggregation, which folds the check
# states into five buckets (cli/cli v2.97.0, pkg/cmd/pr/checks/aggregate.go:73-87):
#
#   pass      SUCCESS
#   skipping  SKIPPED, NEUTRAL
#   fail      ERROR, FAILURE, TIMED_OUT, ACTION_REQUIRED
#   cancel    CANCELLED
#   pending   everything else, including EXPECTED, REQUESTED, WAITING, QUEUED,
#             PENDING, IN_PROGRESS and STALE
#
# The gate asks for `bucket` rather than `state` precisely so that the last row
# holds: a state gh has never heard of arrives as `pending` and gates, instead of
# slipping through. That means the states above are documentation of gh's
# behavior, not inputs to these assertions -- the assertions run per bucket.
#
# Usage: bash scripts/ci-gate-expression_test.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# shellcheck source=lib/koto-gates.sh
. "$SCRIPT_DIR/lib/koto-gates.sh"

PASS=0
FAIL=0

# Every koto template carrying a ci_passing gate belongs here. The validator's
# check 4 holds them all to the same command, so a template added there and
# forgotten here would be gated but never exercised.
TEMPLATES=(
    "skills/work-on/koto-templates/work-on.md"
    "skills/execute/koto-templates/execute.md"
)

# ---------------------------------------------------------------------------
# Pulling the pieces out of the gate command
# ---------------------------------------------------------------------------

# Prints the comma-separated field list passed to `gh pr checks --json`.
# The command also runs `gh pr list --json number`, so take the last --json:
# that's the one belonging to the checks call.
extract_json_fields() {
    printf '%s' "$1" | grep -oE '\-\-json [a-zA-Z,]+' | tail -1 | sed 's/^--json //'
}

# Prints the jq filter that classifies the checks. The command carries two --jq
# flags and the classifying one is the last, for the same reason.
extract_jq_filter() {
    local rest="$1" last="" head
    while [[ "$rest" == *"--jq '"* ]]; do
        rest="${rest#*--jq \'}"
        head="${rest%%\'*}"
        [[ "$head" == "$rest" ]] && break
        last="$head"
        rest="${rest#*\'}"
    done
    printf '%s' "$last"
}

# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------

# Builds a `gh pr checks --json <fields>` payload from a list of bucket values,
# emitting only the fields the command asked for.
# Usage: build_payload "<fields>" pass skipping
build_payload() {
    local fields="$1"
    shift
    local out="[" first=1
    local bucket obj f value
    for bucket in "$@"; do
        obj=""
        while IFS= read -r f; do
            case "$f" in
                bucket) value="$bucket" ;;
                state)  value="UNCHECKED_STATE" ;;
                name)   value="some check" ;;
                *)      value="" ;;
            esac
            [[ -n "$obj" ]] && obj="${obj},"
            obj="${obj}\"${f}\":\"${value}\""
        done < <(printf '%s\n' "$fields" | tr ',' '\n')
        [[ $first -eq 0 ]] && out="${out},"
        first=0
        out="${out}{${obj}}"
    done
    printf '%s]' "$out"
}

# ---------------------------------------------------------------------------
# Assertions
# ---------------------------------------------------------------------------

# assert_gate <label> <expected true|false> <name> <fields> <filter> <buckets...>
assert_gate() {
    local label="$1" expected="$2" name="$3" fields="$4" filter="$5"
    shift 5

    local payload actual
    payload=$(build_payload "$fields" "$@")

    if ! actual=$(printf '%s' "$payload" | jq -r "$filter" 2>&1); then
        echo "FAIL: [$label] $name (jq error: $actual)"
        FAIL=$((FAIL + 1))
        return
    fi

    if [[ "$actual" == "$expected" ]]; then
        echo "PASS: [$label] $name"
        PASS=$((PASS + 1))
    else
        echo "FAIL: [$label] $name (expected $expected, got $actual)"
        echo "       payload: $payload"
        FAIL=$((FAIL + 1))
    fi
}

# ---------------------------------------------------------------------------
# Run the fixture set against every template's live expression
# ---------------------------------------------------------------------------

for template in "${TEMPLATES[@]}"; do
    label="$(basename "$template")"
    path="$REPO_ROOT/$template"

    if [[ ! -f "$path" ]]; then
        echo "FAIL: [$label] template not found at $path"
        FAIL=$((FAIL + 1))
        continue
    fi

    raw=$(koto_gate_command "$path" ci_passing)
    if [[ -z "$raw" ]]; then
        echo "FAIL: [$label] no readable ci_passing gate command found."
        echo "       Either the gate was renamed or scripts/lib/koto-gates.sh no"
        echo "       longer matches koto's template layout."
        FAIL=$((FAIL + 1))
        continue
    fi

    cmd=$(koto_unquote_scalar "$raw")
    fields=$(extract_json_fields "$cmd")
    filter=$(extract_jq_filter "$cmd")

    if [[ -z "$fields" || -z "$filter" ]]; then
        echo "FAIL: [$label] extract_json_fields or extract_jq_filter came back empty."
        echo "       Command was: $cmd"
        FAIL=$((FAIL + 1))
        continue
    fi

    # Both extractors assume the classifying --json and --jq are the last of
    # their kind on the line. If a future edit reorders them, they would silently
    # return the pull-request-number filter instead and every assertion below
    # would fail for a reason that has nothing to do with the gate's semantics.
    if [[ "$filter" != *"$fields"* ]]; then
        echo "FAIL: [$label] the extracted filter does not mention the requested field."
        echo "       Requested: $fields"
        echo "       Filter:    $filter"
        echo "       Look at extract_json_fields and extract_jq_filter in this file:"
        echo "       they take the last --json and --jq on the line."
        FAIL=$((FAIL + 1))
        continue
    fi

    # Green: nothing failed and nothing is still running.
    assert_gate "$label" true "all checks pass" \
        "$fields" "$filter" pass pass pass
    assert_gate "$label" true "pass plus skipping passes (#244)" \
        "$fields" "$filter" pass skipping
    assert_gate "$label" true "every check skipping passes" \
        "$fields" "$filter" skipping skipping

    # Red: a real failure must still gate.
    assert_gate "$label" false "fail gates" \
        "$fields" "$filter" pass fail
    assert_gate "$label" false "fail alongside skipping still gates" \
        "$fields" "$filter" skipping fail

    # Cancelled produced no verdict, so it isn't green.
    assert_gate "$label" false "cancel gates" \
        "$fields" "$filter" pass cancel

    # A check that's still running isn't green either. Loosening the gate to
    # "nothing is in the fail bucket" would break this one case and nothing else,
    # which is why it's called out here and in the template comment.
    assert_gate "$label" false "pending gates" \
        "$fields" "$filter" pass pending

    # An unrecognized bucket must gate rather than slip through, which is what
    # makes the filter safe against gh growing a sixth bucket.
    assert_gate "$label" false "an unknown bucket gates" \
        "$fields" "$filter" pass something_new

    # A pull request with no checks reported at all satisfies `length == 0` and
    # so reads as green. This is long-standing behavior, not something #244
    # introduced, and it's the silent-success surface that execute.md's
    # merge_state_clean gate exists to cover. Asserted so the next person sees
    # it stated rather than discovering it.
    assert_gate "$label" true "no checks at all reads as green (pre-existing surface)" \
        "$fields" "$filter"
done

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------

echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
