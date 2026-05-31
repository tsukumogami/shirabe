#!/usr/bin/env bash
# transition-status.sh - Transition a COMP document to a new status
# Part of the comp skill
#
# Usage: ./transition-status.sh <comp-doc-path> <target-status>
#
# Arguments:
#   comp-doc-path   Path to COMP document (e.g., docs/competitive/COMP-foo.md)
#   target-status   Target status: Accepted or Done
#
# Lifecycle (comp-format.md):
#   Draft -> Accepted
#   Accepted -> Done
#   Draft -> Done       (shortcut; a Draft analysis may close directly)
#   No downgrade transitions. No directory movement (COMP docs never move).
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
VALID_STATUSES="Draft Accepted Done"

# JSON output helpers. moved is always false: COMP docs never change directory.
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
            new_status: $new_status,
            moved: false
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
Usage: $(basename "$0") <comp-doc-path> <target-status>

Transition a COMP document to a new status in place. COMP docs never
move directories.

Arguments:
  comp-doc-path   Path to COMP document
  target-status   One of: Accepted, Done

Allowed transitions:
  Draft -> Accepted
  Accepted -> Done
  Draft -> Done

Examples:
  $(basename "$0") docs/competitive/COMP-foo.md Accepted
  $(basename "$0") docs/competitive/COMP-foo.md Done
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
    sed -n '2,/^---$/p' "$doc_path" | \
        grep -E '^status:' | \
        sed 's/^status:[[:space:]]*//' | \
        head -1
}

# Extract status from body ## Status section
get_body_status() {
    local doc_path="$1"
    local status_line
    status_line=$(grep -A 3 '^## Status' "$doc_path" | \
        grep -E '^(Draft|Accepted|Done)' | \
        head -1) || status_line=""

    if [[ -z "$status_line" ]]; then
        return 1
    fi

    echo "$status_line" | sed 's/^[[:space:]]*//' | cut -d' ' -f1
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
        json_error "Could not extract status from comp doc" 1
    }
    echo "$body_status"
}

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

get_current_status_line() {
    local doc_path="$1"
    grep -A 3 '^## Status' "$doc_path" | \
        grep -E '^(Draft|Accepted|Done)' | \
        head -1 || echo ""
}

# Allowed transitions per comp-format.md. Forward-only: Draft -> Accepted,
# Accepted -> Done, and the Draft -> Done shortcut. No downgrades, no
# regressions, Done is terminal.
validate_transition() {
    local current="$1"
    local target="$2"

    if [[ "$current" == "Done" ]]; then
        json_error "Done is a terminal status; no further transitions allowed" 2
    fi

    local transition="${current}__${target}"

    case "$transition" in
        Draft__Accepted)    return 0 ;;
        Accepted__Done)     return 0 ;;
        Draft__Done)        return 0 ;;
        Accepted__Draft)    json_error "Accepted cannot regress to Draft" 2 ;;
        *)                  json_error "Invalid transition: ${current} -> ${target}" 2 ;;
    esac
}

# Update status in YAML frontmatter.
update_frontmatter_status() {
    local doc_path="$1"
    local new_status="$2"

    _sed_i "s/^status:.*$/status: ${new_status}/" "$doc_path" || {
        json_error "Failed to update status in frontmatter" 3
    }
}

# Update status in body ## Status section. The new status line is the bare
# target status word on its own line, keeping the doc FC03-valid.
update_body_status() {
    local doc_path="$1"
    local old_status_line="$2"
    local new_status_line="$3"

    local escaped_old escaped_new
    escaped_old=$(printf '%s\n' "$old_status_line" | sed 's/[[\.*^$()+?{|]/\\&/g')
    escaped_new=$(printf '%s\n' "$new_status_line" | sed 's/[&/\]/\\&/g')

    _sed_i "s/^${escaped_old}$/${escaped_new}/" "$doc_path" || {
        json_error "Failed to update status in file" 3
    }
}

main() {
    if [[ "${1:-}" == "--help" ]] || [[ "${1:-}" == "-h" ]]; then
        usage
        exit 0
    fi

    if [[ $# -lt 2 ]]; then
        json_error "Usage: $(basename "$0") <comp-doc-path> <target-status>" 1
    fi

    local doc_path="$1"
    local target_status="$2"

    if [[ ! -f "$doc_path" ]]; then
        json_error "Comp doc not found: $doc_path" 1
    fi

    if ! echo "$VALID_STATUSES" | grep -qw "$target_status"; then
        json_error "Invalid status: $target_status. Must be one of: Accepted Done" 2
    fi

    local current_status status_format
    current_status=$(get_current_status "$doc_path")
    status_format=$(get_status_format "$doc_path")

    if [[ "$current_status" == "$target_status" ]]; then
        json_success "$doc_path" "$current_status" "$target_status"
        exit 0
    fi

    validate_transition "$current_status" "$target_status"

    if [[ "$status_format" == "frontmatter" ]]; then
        update_frontmatter_status "$doc_path" "$target_status"
    fi

    local body_status
    if body_status=$(get_body_status "$doc_path" 2>/dev/null); then
        local current_status_line new_status_line
        current_status_line=$(get_current_status_line "$doc_path")
        if [[ -n "$current_status_line" ]]; then
            new_status_line="$target_status"
            update_body_status "$doc_path" "$current_status_line" "$new_status_line"
        fi
    fi

    json_success "$doc_path" "$current_status" "$target_status"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
