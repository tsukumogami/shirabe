#!/usr/bin/env bash
# transition-status.sh - Transition a PRD document to a new status
# Part of the prd skill
#
# Usage: ./transition-status.sh <prd-doc-path> <target-status>
#
# Arguments:
#   prd-doc-path    Path to PRD document (e.g., docs/prds/PRD-foo.md)
#   target-status   Target status: Draft, Accepted, In Progress, Done
#
# PRDs do not move between directories on status transition.
# This script updates the frontmatter and body ## Status section only.
#
# Exit codes:
#   0 - Success (outputs JSON with result)
#   1 - Invalid arguments or file not found
#   2 - Invalid status transition
#   3 - File operation failed

set -euo pipefail

# Portable in-place sed: BSD sed (macOS) requires a backup extension; GNU does not.
_sed_i() { sed -i.bak "$1" "$2" && rm -f "${2}.bak"; }

# Valid statuses
VALID_STATUSES="Draft Accepted In Progress Done"

# JSON output helpers
json_success() {
    local doc_path="$1"
    local old_status="$2"
    local new_status="$3"

    jq -n \
        --arg doc_path "$doc_path" \
        --arg old_status "$old_status" \
        --arg new_status "$new_status" \
        '{
            success: true,
            doc_path: $doc_path,
            old_status: $old_status,
            new_status: $new_status
        }'
}

json_error() {
    local message="$1"
    local code="${2:-1}"
    jq -n --arg message "$message" --argjson code "$code" \
        '{success: false, error: $message, code: $code}' >&2
    exit "$code"
}

usage() {
    cat <<EOF
Usage: $(basename "$0") <prd-doc-path> <target-status>

Transition a PRD document to a new status. PRDs stay in docs/prds/ regardless
of status -- no directory movement occurs.

Arguments:
  prd-doc-path    Path to PRD document
  target-status   One of: $VALID_STATUSES

Examples:
  $(basename "$0") docs/prds/PRD-foo.md Done
  $(basename "$0") docs/prds/PRD-foo.md "In Progress"
EOF
}

has_frontmatter() {
    local doc_path="$1"
    head -1 "$doc_path" | grep -q '^---$'
}

get_frontmatter_status() {
    local doc_path="$1"
    sed -n '2,/^---$/p' "$doc_path" | \
        grep -E '^status:' | \
        sed 's/^status:[[:space:]]*//' | \
        head -1
}

get_body_status() {
    local doc_path="$1"

    local status_line
    status_line=$(grep -A 3 '^## Status' "$doc_path" | \
        grep -E '^(Draft|Accepted|In Progress|Done)' | \
        head -1) || status_line=""

    if [[ -z "$status_line" ]]; then
        return 1
    fi

    echo "$status_line" | sed 's/^[[:space:]]*//'
}

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

    local body_status
    body_status=$(get_body_status "$doc_path") || {
        json_error "Could not extract status from PRD doc" 1
    }
    echo "$body_status"
}

update_frontmatter_status() {
    local doc_path="$1"
    local new_status="$2"

    # "In Progress" contains a space — quote it properly for sed
    local escaped_status
    escaped_status=$(printf '%s' "$new_status" | sed 's/[[\.*^$()+?{|]/\\&/g')

    _sed_i "s/^status:.*$/status: ${escaped_status}/" "$doc_path" || {
        json_error "Failed to update status in frontmatter" 3
    }
}

update_body_status() {
    local doc_path="$1"
    local old_status="$2"
    local new_status="$3"

    local escaped_old escaped_new
    escaped_old=$(printf '%s\n' "$old_status" | sed 's/[[\.*^$()+?{|]/\\&/g')
    escaped_new=$(printf '%s\n' "$new_status" | sed 's/[&/\]/\\&/g')

    _sed_i "s/^${escaped_old}$/${escaped_new}/" "$doc_path" || {
        json_error "Failed to update status in file body" 3
    }
}

main() {
    if [[ "${1:-}" == "--help" ]] || [[ "${1:-}" == "-h" ]]; then
        usage
        exit 0
    fi

    if [[ $# -lt 2 ]]; then
        json_error "Usage: $(basename "$0") <prd-doc-path> <target-status>" 1
    fi

    local doc_path="$1"
    local target_status="$2"

    if [[ ! -f "$doc_path" ]]; then
        json_error "PRD doc not found: $doc_path" 1
    fi

    # Validate target status (check each word to handle "In Progress")
    local found=false
    # shellcheck disable=SC2043
    for s in "Draft" "Accepted" "In Progress" "Done"; do
        if [[ "$s" == "$target_status" ]]; then
            found=true
            break
        fi
    done
    if [[ "$found" == false ]]; then
        json_error "Invalid status: $target_status. Must be one of: $VALID_STATUSES" 2
    fi

    local current_status
    current_status=$(get_current_status "$doc_path")

    if [[ "$current_status" == "$target_status" ]]; then
        json_success "$doc_path" "$current_status" "$target_status"
        exit 0
    fi

    # Update frontmatter if present
    if has_frontmatter "$doc_path"; then
        update_frontmatter_status "$doc_path" "$target_status"
    fi

    # Update body ## Status section if present
    local body_status
    if body_status=$(get_body_status "$doc_path" 2>/dev/null); then
        update_body_status "$doc_path" "$body_status" "$target_status"
    fi

    json_success "$doc_path" "$current_status" "$target_status"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
