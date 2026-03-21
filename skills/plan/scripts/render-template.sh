#!/usr/bin/env bash
# render-template.sh - Render complexity-specific AC templates with JSON content
# Part of the complexity-based validation system (docs/DESIGN-tiered-validation.md)
#
# Usage: ./render-template.sh < input.json
#
# Input JSON (via stdin):
#   {
#     "complexity": "simple|testable|critical",
#     "goal": "Issue goal statement",
#     "context": "Context paragraph",
#     "prose_ac": ["AC item 1", "AC item 2"],
#     "validation_commands": "# Test 1\ncommand1\n# Test 2\ncommand2",
#     "security_checklist": ["Check 1", "Check 2"],
#     "dependencies": "Blocked by #123",
#     "downstream_deps": "This issue blocks #456"
#   }
#
# Output: Rendered markdown template to stdout
#
# Exit codes:
#   0 - Success
#   1 - Invalid input or missing required fields
#   2 - Template not found

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE_DIR="$SCRIPT_DIR/../references/templates"

# Output error and exit
json_error() {
    local message="$1"
    local code="${2:-1}"
    echo "{\"error\": \"$message\"}" >&2
    exit "$code"
}

# Check prerequisites
check_prerequisites() {
    if ! command -v jq &>/dev/null; then
        json_error "jq not found. Please install jq." 2
    fi
}

# Read and validate input JSON
read_input() {
    local input
    input=$(cat)

    if [[ -z "$input" ]]; then
        json_error "Empty input. Expected JSON via stdin."
    fi

    if ! echo "$input" | jq -e '.' >/dev/null 2>&1; then
        json_error "Invalid JSON input."
    fi

    # Validate required fields
    if ! echo "$input" | jq -e '.complexity' >/dev/null 2>&1; then
        json_error "Missing required field: complexity"
    fi

    if ! echo "$input" | jq -e '.goal' >/dev/null 2>&1; then
        json_error "Missing required field: goal"
    fi

    echo "$input"
}

# Get template path for complexity
get_template_path() {
    local complexity="$1"
    local template_path="$TEMPLATE_DIR/ac-${complexity}.md"

    if [[ ! -f "$template_path" ]]; then
        json_error "Template not found for complexity: $complexity" 2
    fi

    echo "$template_path"
}

# Format prose_ac array as markdown checkboxes
format_prose_ac() {
    local items_json="$1"

    if [[ -z "$items_json" ]] || [[ "$items_json" == "null" ]] || [[ "$items_json" == "[]" ]]; then
        echo ""
        return
    fi

    echo "$items_json" | jq -r '.[] | "- [ ] " + .'
}

# Format security_checklist array as markdown checkboxes
format_security_checklist() {
    local items_json="$1"

    if [[ -z "$items_json" ]] || [[ "$items_json" == "null" ]] || [[ "$items_json" == "[]" ]]; then
        echo ""
        return
    fi

    echo "$items_json" | jq -r '.[] | "- [ ] " + .'
}

# Replace a placeholder in a file using awk (handles special characters safely)
# Args: $1=placeholder, $2=replacement content, $3=input file
replace_placeholder() {
    local placeholder="$1"
    local replacement="$2"
    local input_file="$3"
    local output_file

    output_file=$(mktemp)

    # Use awk for safe replacement - handles special characters in replacement
    awk -v placeholder="{{$placeholder}}" -v replacement="$replacement" '
    {
        idx = index($0, placeholder)
        if (idx > 0) {
            before = substr($0, 1, idx - 1)
            after = substr($0, idx + length(placeholder))
            print before replacement after
        } else {
            print $0
        }
    }
    ' "$input_file" > "$output_file"

    cat "$output_file"
    rm -f "$output_file"
}

# Render template with content
render_template() {
    local input="$1"

    # Extract fields
    local complexity goal context prose_ac_json validation_commands security_checklist_json dependencies downstream_deps
    complexity=$(echo "$input" | jq -r '.complexity')
    goal=$(echo "$input" | jq -r '.goal // ""')
    context=$(echo "$input" | jq -r '.context // ""')
    prose_ac_json=$(echo "$input" | jq -c '.prose_ac // []')
    validation_commands=$(echo "$input" | jq -r '.validation_commands // ""')
    security_checklist_json=$(echo "$input" | jq -c '.security_checklist // []')
    dependencies=$(echo "$input" | jq -r '.dependencies // "None"')
    downstream_deps=$(echo "$input" | jq -r '.downstream_deps // "None"')

    # Format arrays
    local prose_ac security_checklist
    prose_ac=$(format_prose_ac "$prose_ac_json")
    security_checklist=$(format_security_checklist "$security_checklist_json")

    # Default empty validation commands
    if [[ -z "$validation_commands" ]]; then
        validation_commands="# No validation commands specified"
    fi

    # Get template
    local template_path
    template_path=$(get_template_path "$complexity")

    # Use temp files for safe multi-line replacements
    local tmp1 tmp2 tmp3 tmp4 tmp5 tmp6 tmp7 tmp8
    tmp1=$(mktemp)
    tmp2=$(mktemp)
    tmp3=$(mktemp)
    tmp4=$(mktemp)
    tmp5=$(mktemp)
    tmp6=$(mktemp)
    tmp7=$(mktemp)
    tmp8=$(mktemp)

    # Chain replacements using temp files
    replace_placeholder "GOAL" "$goal" "$template_path" > "$tmp1"
    replace_placeholder "CONTEXT" "$context" "$tmp1" > "$tmp2"
    replace_placeholder "PROSE_AC" "$prose_ac" "$tmp2" > "$tmp3"
    replace_placeholder "VALIDATION_COMMANDS" "$validation_commands" "$tmp3" > "$tmp4"
    replace_placeholder "SECURITY_CHECKLIST" "$security_checklist" "$tmp4" > "$tmp5"
    replace_placeholder "DEPENDENCIES" "$dependencies" "$tmp5" > "$tmp6"
    replace_placeholder "DOWNSTREAM_DEPS" "$downstream_deps" "$tmp6" > "$tmp7"

    # Final output
    local output
    output=$(cat "$tmp7")

    # Cleanup temp files
    rm -f "$tmp1" "$tmp2" "$tmp3" "$tmp4" "$tmp5" "$tmp6" "$tmp7" "$tmp8"

    # Validate no remaining placeholders
    if echo "$output" | grep -qE '\{\{[A-Z_]+\}\}'; then
        local remaining
        remaining=$(echo "$output" | grep -oE '\{\{[A-Z_]+\}\}' | sort -u | tr '\n' ', ')
        json_error "Unsubstituted placeholders remaining: $remaining"
    fi

    echo "$output"
}

# Main function
main() {
    check_prerequisites

    local input
    input=$(read_input)

    render_template "$input"
}

# Run main if script is executed (not sourced)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
