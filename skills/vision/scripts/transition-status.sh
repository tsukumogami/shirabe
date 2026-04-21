#!/usr/bin/env bash
# transition-status.sh - Transition a vision document to a new status
# Part of the vision skill
#
# Usage: ./transition-status.sh <vision-doc-path> <target-status> [superseding-doc]
#
# Arguments:
#   vision-doc-path   Path to vision document (e.g., docs/visions/VISION-foo.md)
#   target-status     Target status: Draft, Accepted, Active, Sunset
#   superseding-doc   Optional when target is Sunset: path to the superseding doc
#
# Exit codes:
#   0 - Success (outputs JSON with result)
#   1 - Invalid arguments or file not found
#   2 - Invalid status transition
#   3 - File operation failed

set -euo pipefail

# Portable in-place sed: BSD sed (macOS) requires a backup extension; GNU does not.
_sed_i() { sed -i.bak "$1" "$2" && rm -f "${2}.bak"; }

# Status to directory mapping (function instead of associative array for Bash 3.2 compatibility)
status_dir() {
    case "$1" in
        Draft|Accepted|Active) echo "docs/visions" ;;
        Sunset)                echo "docs/visions/sunset" ;;
    esac
}

# Valid statuses
VALID_STATUSES="Draft Accepted Active Sunset"

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
Usage: $(basename "$0") <vision-doc-path> <target-status> [superseding-doc]

Transition a vision document to a new status, moving it to the
appropriate directory if needed.

Arguments:
  vision-doc-path   Path to vision document
  target-status     One of: $VALID_STATUSES
  superseding-doc   Optional for Sunset: path to the superseding vision doc

Directory mapping:
  Draft/Accepted/Active -> docs/visions/
  Sunset                -> docs/visions/sunset/

Allowed transitions:
  Draft -> Accepted (Open Questions must be empty/removed)
  Accepted -> Active
  Active -> Sunset

Examples:
  $(basename "$0") docs/visions/VISION-foo.md Accepted
  $(basename "$0") docs/visions/VISION-old.md Sunset docs/visions/VISION-new.md
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
        grep -E '^(Draft|Accepted|Active|Sunset)' | \
        head -1) || status_line=""

    if [[ -z "$status_line" ]]; then
        return 1
    fi

    # Extract just the status keyword (first word)
    echo "$status_line" | sed 's/^[[:space:]]*//' | cut -d' ' -f1
}

# Extract current status from vision doc
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
        json_error "Could not extract status from vision doc" 1
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

# Get the full status line (for detecting existing "Sunset" links)
# Only used for body format
get_current_status_line() {
    local doc_path="$1"

    grep -A 3 '^## Status' "$doc_path" | \
        grep -E '^(Draft|Accepted|Active|Sunset)' | \
        head -1 || echo ""
}

# Validate transition is allowed
validate_transition() {
    local current="$1"
    local target="$2"

    # Sunset is terminal
    if [[ "$current" == "Sunset" ]]; then
        json_error "Sunset is a terminal status; no further transitions allowed" 2
    fi

    local transition="${current}__${target}"

    case "$transition" in
        Draft__Accepted)   return 0 ;;
        Accepted__Active)  return 0 ;;
        Active__Sunset)    return 0 ;;
        Draft__Active)     json_error "Draft cannot transition directly to Active; must be Accepted first" 2 ;;
        Draft__Sunset)     json_error "Draft cannot transition to Sunset; delete the document instead" 2 ;;
        Active__Accepted)  json_error "Active cannot regress to Accepted" 2 ;;
        Active__Draft)     json_error "Active cannot regress to Draft" 2 ;;
        Accepted__Draft)   json_error "Accepted cannot regress to Draft" 2 ;;
        *)                 json_error "Invalid transition: ${current} -> ${target}" 2 ;;
    esac
}

# Check that Open Questions section is empty or removed (for Draft -> Accepted)
validate_open_questions_resolved() {
    local doc_path="$1"

    # Check if "## Open Questions" section exists
    if ! grep -q '^## Open Questions' "$doc_path"; then
        # Section doesn't exist, that's fine
        return 0
    fi

    # Extract content between "## Open Questions" and the next "##" heading (or EOF)
    local content
    content=$(sed -n '/^## Open Questions$/,/^## /{ /^## /d; p; }' "$doc_path" | \
        sed '/^[[:space:]]*$/d')

    if [[ -n "$content" ]]; then
        json_error "Draft -> Accepted requires Open Questions section to be empty or removed. Found unresolved content." 2
    fi
}

# Update status in YAML frontmatter
update_frontmatter_status() {
    local doc_path="$1"
    local new_status="$2"
    local superseding_doc="${3:-}"

    # Update the status: line in frontmatter
    _sed_i "s/^status:.*$/status: ${new_status}/" "$doc_path" || {
        json_error "Failed to update status in frontmatter" 3
    }

    # For Sunset, add or update superseded_by field
    if [[ "$new_status" == "Sunset" ]] && [[ -n "$superseding_doc" ]]; then
        # Check if superseded_by already exists
        if grep -q '^superseded_by:' "$doc_path"; then
            _sed_i "s|^superseded_by:.*$|superseded_by: ${superseding_doc}|" "$doc_path"
        else
            # Insert superseded_by after status line (awk is portable; sed /a is not)
            awk -v sup="superseded_by: ${superseding_doc}" \
                '/^status:/ { print; print sup; next } 1' \
                "$doc_path" > "${doc_path}.tmp" && mv "${doc_path}.tmp" "$doc_path"
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
    _sed_i "s/^${escaped_old}$/${escaped_new}/" "$doc_path" || {
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

# Move vision doc to target directory
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

# Main
main() {
    if [[ "${1:-}" == "--help" ]] || [[ "${1:-}" == "-h" ]]; then
        usage
        exit 0
    fi

    if [[ $# -lt 2 ]]; then
        json_error "Usage: $(basename "$0") <vision-doc-path> <target-status> [superseding-doc]" 1
    fi

    local doc_path="$1"
    local target_status="$2"
    local superseding_doc="${3:-}"

    # Validate file exists
    if [[ ! -f "$doc_path" ]]; then
        json_error "Vision doc not found: $doc_path" 1
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
        json_success "$doc_path" "$current_status" "$target_status" "$doc_path" false "$superseding_doc"
        exit 0
    fi

    # Validate the transition is allowed
    validate_transition "$current_status" "$target_status"

    # Precondition: Draft -> Accepted requires Open Questions resolved
    if [[ "$current_status" == "Draft" ]] && [[ "$target_status" == "Accepted" ]]; then
        validate_open_questions_resolved "$doc_path"
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
            if [[ "$target_status" == "Sunset" ]] && [[ -n "$superseding_doc" ]]; then
                local superseding_name
                superseding_name=$(basename "$superseding_doc")
                new_status_line="Sunset: superseded by [${superseding_name}](${superseding_doc})"
            else
                new_status_line="$target_status"
            fi
            update_body_status "$doc_path" "$current_status_line" "$new_status_line"
        fi
    fi

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
