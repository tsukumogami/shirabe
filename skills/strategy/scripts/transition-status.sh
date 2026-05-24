#!/usr/bin/env bash
# transition-status.sh - Transition a STRATEGY document to a new status
# Part of the strategy skill
#
# Usage: ./transition-status.sh <strategy-doc-path> <target-status> [reason]
#
# Arguments:
#   strategy-doc-path  Path to STRATEGY document (e.g., docs/strategies/STRATEGY-foo.md)
#   target-status      Target status: Draft, Accepted, Active, Sunset
#   reason             Required for Sunset: short text describing why the bet
#                      was invalidated, pivoted, or abandoned (sed/awk metachars
#                      and frontmatter delimiters rejected; see Security
#                      Considerations in DESIGN-shirabe-strategy-skill.md).
#
# Lifecycle (DESIGN-shirabe-strategy-skill.md Decision 3):
#   Draft -> Accepted (requires Open Questions empty or removed)
#   Accepted -> Active
#   Accepted -> Sunset (lifecycle refinement; bet invalidated before downstream
#                       consumption began)
#   Active -> Sunset
#   No downgrade transitions.
#
# Directory mapping:
#   Draft / Accepted / Active -> docs/strategies/
#   Sunset                    -> docs/strategies/sunset/
#
# Exit codes:
#   0 - Success (outputs JSON with result)
#   1 - Invalid arguments or file not found
#   2 - Invalid status transition or sanitization failure
#   3 - File operation failed

set -euo pipefail

# Portable in-place sed: BSD sed (macOS) requires a backup extension; GNU does not.
_sed_i() { sed -i.bak "$1" "$2" && rm -f "${2}.bak"; }

# Status to directory mapping (function for Bash 3.2 compatibility).
status_dir() {
    case "$1" in
        Draft|Accepted|Active) echo "docs/strategies" ;;
        Sunset)                echo "docs/strategies/sunset" ;;
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
    local reason="${6:-}"

    if [[ -n "$reason" ]]; then
        jq -n \
            --arg doc_path "$doc_path" \
            --arg old_status "$old_status" \
            --arg new_status "$new_status" \
            --arg new_path "$new_path" \
            --argjson moved "$moved" \
            --arg reason "$reason" \
            '{
                success: true,
                doc_path: $doc_path,
                old_status: $old_status,
                new_status: $new_status,
                new_path: $new_path,
                moved: $moved,
                reason: $reason
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

usage() {
    cat <<EOF
Usage: $(basename "$0") <strategy-doc-path> <target-status> [reason]

Transition a STRATEGY document to a new status, moving it to the
appropriate directory if needed.

Arguments:
  strategy-doc-path  Path to STRATEGY document
  target-status      One of: $VALID_STATUSES
  reason             Required for Sunset: short text describing the
                     invalidation. Special characters rejected for safety.

Directory mapping:
  Draft / Accepted / Active -> docs/strategies/
  Sunset                    -> docs/strategies/sunset/

Allowed transitions:
  Draft -> Accepted     (Open Questions must be empty or removed)
  Accepted -> Active
  Accepted -> Sunset    (bet invalidated before downstream consumption)
  Active -> Sunset

Examples:
  $(basename "$0") docs/strategies/STRATEGY-foo.md Accepted
  $(basename "$0") docs/strategies/STRATEGY-foo.md Active
  $(basename "$0") docs/strategies/STRATEGY-foo.md Sunset "Upstream VISION pivoted"
EOF
}

# Reason argument sanitization. Sunset reasons get spliced into the body
# Status section via sed; we reject inputs that would break the substitution
# or escape the section. See Security Considerations in
# DESIGN-shirabe-strategy-skill.md.
sanitize_reason() {
    local reason="$1"

    # Reject empty
    if [[ -z "$reason" ]]; then
        json_error "Sunset requires a non-empty reason argument" 2
    fi

    # Reject newlines
    if [[ "$reason" == *$'\n'* ]]; then
        json_error "Sunset reason must be a single line (no newlines)" 2
    fi

    # Reject sed/awk metacharacters that would break the substitution.
    # Specifically: backslash, forward slash, and ampersand are all used by
    # sed's s/// replacement syntax.
    case "$reason" in
        *\\*|*/*|*\&*)
            json_error "Sunset reason contains forbidden character (\\\\, /, or &); use plain prose" 2
            ;;
    esac

    # Reject the frontmatter delimiter literally.
    if [[ "$reason" == *---* ]]; then
        json_error "Sunset reason must not contain the frontmatter delimiter '---'" 2
    fi
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
        grep -E '^(Draft|Accepted|Active|Sunset)' | \
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
        json_error "Could not extract status from strategy doc" 1
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
        grep -E '^(Draft|Accepted|Active|Sunset)' | \
        head -1 || echo ""
}

# Allowed transitions per Decision 3. Accepted -> Sunset is the lifecycle
# refinement noted in the design (bet may be invalidated before downstream
# consumption begins).
validate_transition() {
    local current="$1"
    local target="$2"

    if [[ "$current" == "Sunset" ]]; then
        json_error "Sunset is a terminal status; no further transitions allowed" 2
    fi

    local transition="${current}__${target}"

    case "$transition" in
        Draft__Accepted)    return 0 ;;
        Accepted__Active)   return 0 ;;
        Accepted__Sunset)   return 0 ;;
        Active__Sunset)     return 0 ;;
        Draft__Active)      json_error "Draft cannot transition directly to Active; must be Accepted first" 2 ;;
        Draft__Sunset)      json_error "Draft cannot transition to Sunset; delete the document instead" 2 ;;
        Active__Accepted)   json_error "Active cannot regress to Accepted" 2 ;;
        Active__Draft)      json_error "Active cannot regress to Draft" 2 ;;
        Accepted__Draft)    json_error "Accepted cannot regress to Draft" 2 ;;
        *)                  json_error "Invalid transition: ${current} -> ${target}" 2 ;;
    esac
}

# Draft -> Accepted requires Open Questions section to be empty or removed.
validate_open_questions_resolved() {
    local doc_path="$1"

    if ! grep -q '^## Open Questions' "$doc_path"; then
        return 0
    fi

    local content
    content=$(sed -n '/^## Open Questions$/,/^## /{ /^## /d; p; }' "$doc_path" | \
        sed '/^[[:space:]]*$/d')

    if [[ -n "$content" ]]; then
        json_error "Draft -> Accepted requires Open Questions section to be empty or removed. Found unresolved content." 2
    fi
}

# Update status in YAML frontmatter, optionally adding sunset_reason for Sunset.
update_frontmatter_status() {
    local doc_path="$1"
    local new_status="$2"
    local reason="${3:-}"

    _sed_i "s/^status:.*$/status: ${new_status}/" "$doc_path" || {
        json_error "Failed to update status in frontmatter" 3
    }

    if [[ "$new_status" == "Sunset" ]] && [[ -n "$reason" ]]; then
        if grep -q '^sunset_reason:' "$doc_path"; then
            _sed_i "s|^sunset_reason:.*$|sunset_reason: ${reason}|" "$doc_path"
        else
            awk -v line="sunset_reason: ${reason}" \
                '/^status:/ { print; print line; next } 1' \
                "$doc_path" > "${doc_path}.tmp" && mv "${doc_path}.tmp" "$doc_path"
        fi
    fi
}

# Update status in body ## Status section.
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

get_repo_root() {
    git rev-parse --show-toplevel 2>/dev/null || pwd
}

normalize_path() {
    local path="$1"
    local repo_root
    repo_root=$(get_repo_root)

    local abs_path
    if [[ "$path" = /* ]]; then
        abs_path="$path"
    else
        abs_path="$(cd "$(dirname "$path")" && pwd)/$(basename "$path")"
    fi

    if [[ "$abs_path" == "$repo_root"/* ]]; then
        echo "${abs_path#$repo_root/}"
    else
        echo "$abs_path"
    fi
}

get_normalized_dir() {
    local path="$1"
    local normalized
    normalized=$(normalize_path "$path")
    dirname "$normalized"
}

# Move strategy doc to target directory (creates docs/strategies/sunset/ as needed).
move_to_directory() {
    local doc_path="$1"
    local target_dir="$2"
    local filename

    filename=$(basename "$doc_path")
    local target_path="${target_dir}/${filename}"

    mkdir -p "$target_dir"

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

main() {
    if [[ "${1:-}" == "--help" ]] || [[ "${1:-}" == "-h" ]]; then
        usage
        exit 0
    fi

    if [[ $# -lt 2 ]]; then
        json_error "Usage: $(basename "$0") <strategy-doc-path> <target-status> [reason]" 1
    fi

    local doc_path="$1"
    local target_status="$2"
    local reason="${3:-}"

    if [[ ! -f "$doc_path" ]]; then
        json_error "Strategy doc not found: $doc_path" 1
    fi

    if ! echo "$VALID_STATUSES" | grep -qw "$target_status"; then
        json_error "Invalid status: $target_status. Must be one of: $VALID_STATUSES" 2
    fi

    # Sunset requires a sanitized reason; non-Sunset transitions ignore the arg
    # rather than erroring (mirrors vision's optional superseded_by behavior).
    if [[ "$target_status" == "Sunset" ]]; then
        sanitize_reason "$reason"
    fi

    local current_status status_format
    current_status=$(get_current_status "$doc_path")
    status_format=$(get_status_format "$doc_path")

    if [[ "$current_status" == "$target_status" ]]; then
        json_success "$doc_path" "$current_status" "$target_status" "$doc_path" false "$reason"
        exit 0
    fi

    validate_transition "$current_status" "$target_status"

    if [[ "$current_status" == "Draft" ]] && [[ "$target_status" == "Accepted" ]]; then
        validate_open_questions_resolved "$doc_path"
    fi

    if [[ "$status_format" == "frontmatter" ]]; then
        update_frontmatter_status "$doc_path" "$target_status" "$reason"
    fi

    local body_status
    if body_status=$(get_body_status "$doc_path" 2>/dev/null); then
        local current_status_line new_status_line
        current_status_line=$(get_current_status_line "$doc_path")
        if [[ -n "$current_status_line" ]]; then
            if [[ "$target_status" == "Sunset" ]] && [[ -n "$reason" ]]; then
                new_status_line="Sunset: ${reason}"
            else
                new_status_line="$target_status"
            fi
            update_body_status "$doc_path" "$current_status_line" "$new_status_line"
        fi
    fi

    local current_dir target_dir
    current_dir=$(get_normalized_dir "$doc_path")
    target_dir="$(status_dir "$target_status")"

    local new_path="$doc_path"
    local moved=false

    if [[ "$current_dir" != "$target_dir" ]]; then
        new_path=$(move_to_directory "$doc_path" "$target_dir")
        moved=true
    fi

    json_success "$doc_path" "$current_status" "$target_status" "$new_path" "$moved" "$reason"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
