#!/usr/bin/env bash
# Tests for the ci_passing gate expression carried by the koto templates.
#
# The gate decides whether a pull request's checks are green. It is a shell
# pipeline embedded in a YAML string, so nothing else in the repo exercises it.
# This test pulls the live command out of each template and drives its jq filter
# against synthetic `gh pr checks` payloads.
#
# The fixtures carry only the fields the command actually asks `gh` for, so a
# command that requests one field and filters on another fails here rather than
# in production.
#
# Usage: bash scripts/ci-gate-expression_test.sh

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PASS=0
FAIL=0

TEMPLATES=(
    "skills/work-on/koto-templates/work-on.md"
    "skills/execute/koto-templates/execute.md"
)

# ---------------------------------------------------------------------------
# Extraction: pull the ci_passing gate command out of a template
# ---------------------------------------------------------------------------

# Prints the raw YAML scalar for the ci_passing gate's `command:` field.
extract_gate_command() {
    local template="$1"
    awk '
        /^    gates:[[:space:]]*$/ { in_gates = 1; gate = ""; next }
        in_gates && /^      [a-z_][a-z_0-9]*:[[:space:]]*$/ {
            gate = $0
            sub(/:.*/, "", gate)
            sub(/^[[:space:]]+/, "", gate)
            next
        }
        in_gates && gate == "ci_passing" && /^        command:/ {
            line = $0
            sub(/^        command:[[:space:]]*/, "", line)
            print line
            exit
        }
        /^  [a-z_]/ { in_gates = 0 }
    ' "$template"
}

# Strips the surrounding double quotes and unescapes the YAML string, so the
# result is the command as the shell would receive it.
unquote_yaml_scalar() {
    local raw="$1"
    raw="${raw#\"}"
    raw="${raw%\"}"
    printf '%s' "${raw//\\\"/\"}"
}

# Prints the comma-separated field list passed to `gh pr checks --json`.
# The command also runs `gh pr list --json number`, so take the last --json:
# that is the one belonging to the checks call.
extract_json_fields() {
    local cmd="$1"
    printf '%s' "$cmd" | grep -oE '\-\-json [a-zA-Z,]+' | tail -1 | sed 's/^--json //'
}

# Prints the jq filter that classifies the checks. The command carries two --jq
# flags; the classifying one is the last.
extract_jq_filter() {
    local cmd="$1"
    local rest="$cmd" last="" head
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
# Fixtures: build a `gh pr checks --json <fields>` payload
# ---------------------------------------------------------------------------

# Builds a JSON array from "STATE:BUCKET" pairs, emitting only the fields the
# command asked for. Usage: build_payload "<fields>" SUCCESS:pass SKIPPED:skipping
build_payload() {
    local fields="$1"
    shift
    local out="[" first=1
    local pair state bucket obj f value
    for pair in "$@"; do
        state="${pair%%:*}"
        bucket="${pair##*:}"
        obj=""
        while IFS= read -r f; do
            case "$f" in
                state)  value="$state" ;;
                bucket) value="$bucket" ;;
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

# assert_gate <label> <expected true|false> <name> <fields> <filter> <pairs...>
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

# 42 SUCCESS and 5 SKIPPED: the shape measured on a real pull request whose
# checks were all green but which the pre-fix gate rejected.
real_world_pairs() {
    local i
    for i in $(seq 1 42); do printf 'SUCCESS:pass\n'; done
    for i in $(seq 1 5); do printf 'SKIPPED:skipping\n'; done
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

    raw=$(extract_gate_command "$path")
    if [[ -z "$raw" ]]; then
        echo "FAIL: [$label] no ci_passing gate command found"
        FAIL=$((FAIL + 1))
        continue
    fi

    cmd=$(unquote_yaml_scalar "$raw")
    fields=$(extract_json_fields "$cmd")
    filter=$(extract_jq_filter "$cmd")

    if [[ -z "$fields" || -z "$filter" ]]; then
        echo "FAIL: [$label] could not extract --json fields or jq filter from: $cmd"
        FAIL=$((FAIL + 1))
        continue
    fi

    # Green: nothing failed and nothing is still running.
    assert_gate "$label" true "all checks succeed" \
        "$fields" "$filter" SUCCESS:pass SUCCESS:pass SUCCESS:pass
    assert_gate "$label" true "success plus skipped passes" \
        "$fields" "$filter" SUCCESS:pass SKIPPED:skipping
    assert_gate "$label" true "success plus neutral passes" \
        "$fields" "$filter" SUCCESS:pass NEUTRAL:skipping
    assert_gate "$label" true "every check skipped passes" \
        "$fields" "$filter" SKIPPED:skipping SKIPPED:skipping
    # shellcheck disable=SC2046
    assert_gate "$label" true "42 success and 5 skipped passes" \
        "$fields" "$filter" $(real_world_pairs)

    # Red: a real failure must still gate.
    assert_gate "$label" false "a failure gates" \
        "$fields" "$filter" SUCCESS:pass FAILURE:fail
    assert_gate "$label" false "an error gates" \
        "$fields" "$filter" SUCCESS:pass ERROR:fail
    assert_gate "$label" false "a timeout gates" \
        "$fields" "$filter" SUCCESS:pass TIMED_OUT:fail
    assert_gate "$label" false "action_required gates" \
        "$fields" "$filter" SUCCESS:pass ACTION_REQUIRED:fail
    assert_gate "$label" false "a failure alongside a skip still gates" \
        "$fields" "$filter" SKIPPED:skipping FAILURE:fail

    # Cancelled produced no verdict, so it is not green.
    assert_gate "$label" false "cancelled gates" \
        "$fields" "$filter" SUCCESS:pass CANCELLED:cancel

    # Still-running checks are not green either. Loosening the gate to "nothing
    # has failed" would break these four.
    assert_gate "$label" false "pending gates" \
        "$fields" "$filter" SUCCESS:pass PENDING:pending
    assert_gate "$label" false "in_progress gates" \
        "$fields" "$filter" SUCCESS:pass IN_PROGRESS:pending
    assert_gate "$label" false "queued gates" \
        "$fields" "$filter" SUCCESS:pass QUEUED:pending
    assert_gate "$label" false "stale gates" \
        "$fields" "$filter" SUCCESS:pass STALE:pending
done

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------

echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
