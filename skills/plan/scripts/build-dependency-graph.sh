#!/usr/bin/env bash
# build-dependency-graph.sh - Compute downstream dependents from issue outlines
# Part of the complexity-based validation system (docs/DESIGN-tiered-validation.md)
#
# Usage: ./build-dependency-graph.sh < issue_outlines.json
#
# Input JSON (via stdin):
#   [
#     {"id": "1", "section": "Section 1", "dependencies": []},
#     {"id": "2", "section": "Section 2", "dependencies": ["1"]},
#     {"id": "3", "section": "Section 3", "dependencies": ["1", "2"]}
#   ]
#
# Output JSON:
#   {
#     "downstream": {
#       "1": ["2", "3"],
#       "2": ["3"],
#       "3": []
#     },
#     "roots": ["1"],
#     "leaves": ["3"]
#   }
#
# Exit codes:
#   0 - Success
#   1 - Invalid input

set -euo pipefail

# Output error and exit
json_error() {
    local message="$1"
    echo "{\"error\": \"$message\"}" >&2
    exit 1
}

# Check prerequisites
check_prerequisites() {
    if ! command -v jq &>/dev/null; then
        json_error "jq not found. Please install jq."
    fi
}

# Read and validate input JSON
read_input() {
    local input
    input=$(cat)

    if [[ -z "$input" ]]; then
        json_error "Empty input. Expected JSON array via stdin."
    fi

    # Validate it's valid JSON array
    if ! echo "$input" | jq -e 'type == "array"' >/dev/null 2>&1; then
        json_error "Invalid input. Expected JSON array."
    fi

    echo "$input"
}

# Build downstream mapping by inverting dependencies
# For each issue, find all other issues that depend on it
build_downstream() {
    local input="$1"

    # Get all issue IDs
    local all_ids
    all_ids=$(echo "$input" | jq -r '.[].id')

    # Build the downstream map
    local downstream_map="{}"

    for id in $all_ids; do
        # Find all issues that list this ID in their dependencies
        local dependents
        dependents=$(echo "$input" | jq -c --arg id "$id" \
            '[.[] | select(.dependencies != null and (.dependencies | contains([$id]))) | .id]')

        downstream_map=$(echo "$downstream_map" | jq --arg id "$id" --argjson deps "$dependents" \
            '. + {($id): $deps}')
    done

    echo "$downstream_map"
}

# Find root nodes (issues with no dependencies)
find_roots() {
    local input="$1"
    echo "$input" | jq -c '[.[] | select(.dependencies == null or .dependencies == []) | .id]'
}

# Find leaf nodes (issues with no downstream dependents)
find_leaves() {
    local downstream_map="$1"
    echo "$downstream_map" | jq -c '[to_entries[] | select(.value == []) | .key]'
}

# Main function
main() {
    check_prerequisites

    local input
    input=$(read_input)

    # Build downstream mapping
    local downstream
    downstream=$(build_downstream "$input")

    # Find roots and leaves
    local roots leaves
    roots=$(find_roots "$input")
    leaves=$(find_leaves "$downstream")

    # Output combined result
    jq -n \
        --argjson downstream "$downstream" \
        --argjson roots "$roots" \
        --argjson leaves "$leaves" \
        '{
            downstream: $downstream,
            roots: $roots,
            leaves: $leaves
        }'
}

# Run main if script is executed (not sourced)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
