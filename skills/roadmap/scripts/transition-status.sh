#!/usr/bin/env bash
# transition-status.sh - Transition a roadmap document to a new status
# Part of the roadmap skill
#
# Usage: ./transition-status.sh <roadmap-doc-path> <target-status>
#
# Arguments:
#   roadmap-doc-path  Path to roadmap document (e.g., docs/roadmaps/ROADMAP-foo.md)
#   target-status     Target status: Draft, Active, Done
#
# Exit codes:
#   0 - Success (outputs JSON with result)
#   1 - Invalid arguments or file not found
#   2 - Invalid status transition
#   3 - File operation failed

set -euo pipefail

# Valid statuses
VALID_STATUSES="Draft Active Done"

# JSON output helpers
json_success() {
    local doc_path="$1"
    local old_status="$2"
    local new_status="$3"
    local new_path="$4"
    local moved="$5"

    jq -n \
        --arg doc_path "$doc_path" \
        --arg old_status "$old_status" \
        --arg new_status "$new_status" \
        --arg new_path "$new_path" \
        --argjson moved "$moved" \
        '{
            success: true,
            doc_path: $doc_path,
            old_status: $old_status,
            new_status: $new_status,
            new_path: $new_path,
            moved: $moved
        }'
}

json_error() {
    local message="$1"
    local code="${2:-1}"
    jq -n --arg message "$message" --argjson code "$code" \
        '{success: false, error: $message, code: $code}' >&2
    exit "$code"
}

# Print usage
usage() {
    cat <<EOF
Usage: $(basename "$0") <roadmap-doc-path> <target-status>

Transition a roadmap document to a new status. Roadmaps stay in
docs/roadmaps/ regardless of status (no directory movement).

Arguments:
  roadmap-doc-path  Path to roadmap document
  target-status     One of: $VALID_STATUSES

Allowed transitions:
  Draft -> Active (requires at least 2 ### Feature headings)
  Active -> Done

Examples:
  $(basename "$0") docs/roadmaps/ROADMAP-foo.md Active
  $(basename "$0") docs/roadmaps/ROADMAP-foo.md Done
EOF
}

# Check if doc has YAML frontmatter
has_frontmatter() {
    local doc_path="$1"
    head -1 "$doc_path" | grep -q '^---$'
}

# Extract status from YAML frontmatter
get_frontmatter_status() {
    local doc_path="$1"

    # Extract frontmatter (between first and second ---)
    # and get the status field
    sed -n '2,/^---$/p' "$doc_path" | \
        grep -E '^status:' | \
        sed 's/^status:[[:space:]]*//' | \
        head -1
}

# Extract status from legacy ## Status section
get_body_status() {
    local doc_path="$1"

    local status_line
    status_line=$(grep -A 3 '^## Status' "$doc_path" | \
        grep -E '^(Draft|Active|Done)' | \
        head -1) || status_line=""

    if [[ -z "$status_line" ]]; then
        return 1
    fi

    # Extract just the status keyword (first word)
    echo "$status_line" | sed 's/^[[:space:]]*//' | cut -d' ' -f1
}

# Extract current status from roadmap doc
# Handles both YAML frontmatter and legacy "## Status" section
get_current_status() {
    local doc_path="$1"

    if has_frontmatter "$doc_path"; then
        local status
        status=$(get_frontmatter_status "$doc_path")
        if [[ -n "$status" ]]; then
            echo "$status"
            return 0
        fi
    fi

    # Fall back to body status
    local body_status
    body_status=$(get_body_status "$doc_path") || {
        json_error "Could not extract status from roadmap doc" 1
    }
    echo "$body_status"
}

# Detect status format (frontmatter or body)
get_status_format() {
    local doc_path="$1"

    if has_frontmatter "$doc_path"; then
        local fm_status
        fm_status=$(get_frontmatter_status "$doc_path")
        if [[ -n "$fm_status" ]]; then
            echo "frontmatter"
            return 0
        fi
    fi
    echo "body"
}

# Get the full status line from body format
get_current_status_line() {
    local doc_path="$1"

    grep -A 3 '^## Status' "$doc_path" | \
        grep -E '^(Draft|Active|Done)' | \
        head -1 || echo ""
}

# Validate transition is allowed
validate_transition() {
    local current="$1"
    local target="$2"

    # Done is terminal
    if [[ "$current" == "Done" ]]; then
        json_error "Done is a terminal status; roadmaps are permanent records once completed" 2
    fi

    local transition="${current}__${target}"

    case "$transition" in
        Draft__Active)   return 0 ;;
        Active__Done)    return 0 ;;
        Draft__Done)     json_error "Draft cannot transition directly to Done; must go through Active first" 2 ;;
        Active__Draft)   json_error "Active cannot regress to Draft" 2 ;;
        *)               json_error "Invalid transition: ${current} -> ${target}" 2 ;;
    esac
}

# Check that Features section has at least 2 ### Feature headings (for Draft -> Active)
validate_features_count() {
    local doc_path="$1"

    local count
    count=$(grep -c '^### Feature' "$doc_path" 2>/dev/null) || count=0

    if [[ "$count" -lt 2 ]]; then
        json_error "Draft -> Active requires at least 2 ### Feature headings in the Features section. Found ${count}." 2
    fi
}

# Update status in YAML frontmatter
update_frontmatter_status() {
    local doc_path="$1"
    local new_status="$2"

    sed -i "s/^status:.*$/status: ${new_status}/" "$doc_path" || {
        json_error "Failed to update status in frontmatter" 3
    }
}

# Update status in legacy body format
update_body_status() {
    local doc_path="$1"
    local old_status_line="$2"
    local new_status_line="$3"

    # Escape special characters for sed
    local escaped_old escaped_new
    escaped_old=$(printf '%s\n' "$old_status_line" | sed 's/[[\.*^$()+?{|]/\\&/g')
    escaped_new=$(printf '%s\n' "$new_status_line" | sed 's/[&/\]/\\&/g')

    # Replace the old status line with new status line
    sed -i "s/^${escaped_old}$/${escaped_new}/" "$doc_path" || {
        json_error "Failed to update status in file" 3
    }
}

# Main
main() {
    if [[ "${1:-}" == "--help" ]] || [[ "${1:-}" == "-h" ]]; then
        usage
        exit 0
    fi

    if [[ $# -lt 2 ]]; then
        json_error "Usage: $(basename "$0") <roadmap-doc-path> <target-status>" 1
    fi

    local doc_path="$1"
    local target_status="$2"

    # Validate file exists
    if [[ ! -f "$doc_path" ]]; then
        json_error "Roadmap doc not found: $doc_path" 1
    fi

    # Validate target status
    if ! echo "$VALID_STATUSES" | grep -qw "$target_status"; then
        json_error "Invalid status: $target_status. Must be one of: $VALID_STATUSES" 2
    fi

    # Get current status and format
    local current_status status_format
    current_status=$(get_current_status "$doc_path")
    status_format=$(get_status_format "$doc_path")

    # Check if already at target status
    if [[ "$current_status" == "$target_status" ]]; then
        json_success "$doc_path" "$current_status" "$target_status" "$doc_path" false
        exit 0
    fi

    # Validate the transition is allowed
    validate_transition "$current_status" "$target_status"

    # Precondition: Draft -> Active requires at least 2 Feature headings
    if [[ "$current_status" == "Draft" ]] && [[ "$target_status" == "Active" ]]; then
        validate_features_count "$doc_path"
    fi

    # Update status in frontmatter if present
    if [[ "$status_format" == "frontmatter" ]]; then
        update_frontmatter_status "$doc_path" "$target_status"
    fi

    # Also update body status section if it exists (keep frontmatter and body in sync)
    local body_status
    if body_status=$(get_body_status "$doc_path" 2>/dev/null); then
        local current_status_line new_status_line
        current_status_line=$(get_current_status_line "$doc_path")
        if [[ -n "$current_status_line" ]]; then
            new_status_line="$target_status"
            update_body_status "$doc_path" "$current_status_line" "$new_status_line"
        fi
    fi

    # No directory movement for roadmaps - all statuses stay in docs/roadmaps/
    json_success "$doc_path" "$current_status" "$target_status" "$doc_path" false
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
