#!/usr/bin/env bash
# transition-status.sh - Transition a design document to a new status
# Part of the design skill
#
# Usage: ./transition-status.sh <design-doc-path> <target-status> [superseding-doc]
#
# Arguments:
#   design-doc-path   Path to design document (e.g., docs/designs/DESIGN-foo.md)
#   target-status     Target status: Proposed, Accepted, Planned, Current, Superseded
#   superseding-doc   Required when target is Superseded: path to the superseding doc
#
# Exit codes:
#   0 - Success (outputs JSON with result)
#   1 - Invalid arguments or file not found
#   2 - Invalid status transition
#   3 - File operation failed

set -euo pipefail

# Status to directory mapping (function instead of associative array for Bash 3.2 compatibility)
status_dir() {
    case "$1" in
        Proposed|Accepted|Planned) echo "docs/designs" ;;
        Current)     echo "docs/designs/current" ;;
        Superseded)  echo "docs/designs/archive" ;;
    esac
}

# Valid statuses
VALID_STATUSES="Proposed Accepted Planned Current Superseded"

# JSON output helpers
json_success() {
    local doc_path="$1"
    local old_status="$2"
    local new_status="$3"
    local new_path="$4"
    local moved="$5"
    local superseded_by="${6:-}"

    if [[ -n "$superseded_by" ]]; then
        jq -n \
            --arg doc_path "$doc_path" \
            --arg old_status "$old_status" \
            --arg new_status "$new_status" \
            --arg new_path "$new_path" \
            --argjson moved "$moved" \
            --arg superseded_by "$superseded_by" \
            '{
                success: true,
                doc_path: $doc_path,
                old_status: $old_status,
                new_status: $new_status,
                new_path: $new_path,
                moved: $moved,
                superseded_by: $superseded_by
            }'
    else
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
    fi
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
Usage: $(basename "$0") <design-doc-path> <target-status> [superseding-doc]

Transition a design document to a new status, moving it to the
appropriate directory if needed.

Arguments:
  design-doc-path   Path to design document
  target-status     One of: $VALID_STATUSES
  superseding-doc   Required for Superseded: path to the new design doc

Directory mapping:
  Proposed/Accepted/Planned -> docs/designs/
  Current                   -> docs/designs/current/
  Superseded                -> docs/designs/archive/

Examples:
  $(basename "$0") docs/designs/DESIGN-foo.md Current
  $(basename "$0") docs/designs/DESIGN-old.md Superseded docs/designs/DESIGN-new.md
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
        grep -E '^(Proposed|Accepted|Planned|Current|Superseded)' | \
        head -1) || status_line=""

    if [[ -z "$status_line" ]]; then
        return 1
    fi

    # Extract just the status keyword (first word)
    echo "$status_line" | sed 's/^[[:space:]]*//' | cut -d' ' -f1
}

# Extract current status from design doc
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
        json_error "Could not extract status from design doc" 1
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

# Get the full status line (for detecting existing "Superseded by" links)
# Only used for body format
get_current_status_line() {
    local doc_path="$1"

    grep -A 3 '^## Status' "$doc_path" | \
        grep -E '^(Proposed|Accepted|Planned|Current|Superseded)' | \
        head -1 || echo ""
}

# Update status in YAML frontmatter
update_frontmatter_status() {
    local doc_path="$1"
    local new_status="$2"
    local superseding_doc="${3:-}"

    # Update the status: line in frontmatter
    sed -i "s/^status:.*$/status: ${new_status}/" "$doc_path" || {
        json_error "Failed to update status in frontmatter" 3
    }

    # For Superseded, add or update superseded_by field
    if [[ "$new_status" == "Superseded" ]] && [[ -n "$superseding_doc" ]]; then
        # Check if superseded_by already exists
        if grep -q '^superseded_by:' "$doc_path"; then
            sed -i "s|^superseded_by:.*$|superseded_by: ${superseding_doc}|" "$doc_path"
        else
            # Insert superseded_by after status line
            sed -i "/^status:/a superseded_by: ${superseding_doc}" "$doc_path"
        fi
    fi
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

# Get the repository root directory
get_repo_root() {
    git rev-parse --show-toplevel 2>/dev/null || pwd
}

# Normalize a path relative to repo root for comparison
# Returns path relative to repo root, or absolute path if not in repo
normalize_path() {
    local path="$1"
    local repo_root
    repo_root=$(get_repo_root)

    # Get absolute path
    local abs_path
    if [[ "$path" = /* ]]; then
        abs_path="$path"
    else
        abs_path="$(cd "$(dirname "$path")" && pwd)/$(basename "$path")"
    fi

    # Strip repo root to get relative path
    if [[ "$abs_path" == "$repo_root"/* ]]; then
        echo "${abs_path#$repo_root/}"
    else
        echo "$abs_path"
    fi
}

# Get directory portion of normalized path
get_normalized_dir() {
    local path="$1"
    local normalized
    normalized=$(normalize_path "$path")
    dirname "$normalized"
}

# Move design doc to target directory
move_to_directory() {
    local doc_path="$1"
    local target_dir="$2"
    local filename

    filename=$(basename "$doc_path")
    local target_path="${target_dir}/${filename}"

    # Create target directory if needed
    mkdir -p "$target_dir"

    # Use git mv if in a git repo, otherwise regular mv
    if git rev-parse --git-dir > /dev/null 2>&1; then
        git mv "$doc_path" "$target_path" || {
            json_error "git mv failed" 3
        }
    else
        mv "$doc_path" "$target_path" || {
            json_error "mv failed" 3
        }
    fi

    echo "$target_path"
}

# Note: Issue description rows are no longer stripped during status transitions.
# When individual issues are marked as done, both the issue row and its description
# row are struck through (~~text~~). This preserves the narrative context while
# visually indicating completion. See the implementation-diagram skill for details.

# Main
main() {
    if [[ "${1:-}" == "--help" ]] || [[ "${1:-}" == "-h" ]]; then
        usage
        exit 0
    fi

    if [[ $# -lt 2 ]]; then
        json_error "Usage: $(basename "$0") <design-doc-path> <target-status> [superseding-doc]" 1
    fi

    local doc_path="$1"
    local target_status="$2"
    local superseding_doc="${3:-}"

    # Validate file exists
    if [[ ! -f "$doc_path" ]]; then
        json_error "Design doc not found: $doc_path" 1
    fi

    # Validate target status
    if ! echo "$VALID_STATUSES" | grep -qw "$target_status"; then
        json_error "Invalid status: $target_status. Must be one of: $VALID_STATUSES" 2
    fi

    # Superseded requires the superseding doc argument
    if [[ "$target_status" == "Superseded" ]] && [[ -z "$superseding_doc" ]]; then
        json_error "Superseded status requires path to superseding document as third argument" 1
    fi

    # Get current status and format
    local current_status status_format
    current_status=$(get_current_status "$doc_path")
    status_format=$(get_status_format "$doc_path")

    # Check if already at target status
    if [[ "$current_status" == "$target_status" ]]; then
        json_success "$doc_path" "$current_status" "$target_status" "$doc_path" false "$superseding_doc"
        exit 0
    fi

    # Update status in frontmatter if present
    if [[ "$status_format" == "frontmatter" ]]; then
        update_frontmatter_status "$doc_path" "$target_status" "$superseding_doc"
    fi

    # Also update body status section if it exists (keep frontmatter and body in sync)
    local body_status
    if body_status=$(get_body_status "$doc_path" 2>/dev/null); then
        local current_status_line new_status_line
        current_status_line=$(get_current_status_line "$doc_path")
        if [[ -n "$current_status_line" ]]; then
            if [[ "$target_status" == "Superseded" ]]; then
                local superseding_name
                superseding_name=$(basename "$superseding_doc")
                new_status_line="Superseded by [${superseding_name}](${superseding_doc})"
            else
                new_status_line="$target_status"
            fi
            update_body_status "$doc_path" "$current_status_line" "$new_status_line"
        fi
    fi

    # Note: Issue descriptions are no longer stripped during transitions.
    # They remain in the document with strikethrough formatting applied
    # when individual issues were marked as done.

    # Determine if move is needed
    # Normalize paths to handle both absolute and relative inputs
    local current_dir target_dir
    current_dir=$(get_normalized_dir "$doc_path")
    target_dir="$(status_dir "$target_status")"

    local new_path="$doc_path"
    local moved=false

    # Move if target directory is different from current (comparing normalized paths)
    if [[ "$current_dir" != "$target_dir" ]]; then
        new_path=$(move_to_directory "$doc_path" "$target_dir")
        moved=true
    fi

    json_success "$doc_path" "$current_status" "$target_status" "$new_path" "$moved" "$superseding_doc"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
