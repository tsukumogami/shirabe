#!/usr/bin/env bash
#
# create-issue.sh - Create a single GitHub issue from a body file
#
# This script creates a GitHub issue, handling:
# - YAML frontmatter stripping
# - Placeholder substitution for issue references
# - Complexity label application
#
# Usage:
#   create-issue.sh --file <path> --title <string> [options]
#
# Required:
#   --file <path>       Path to issue body file (with optional YAML frontmatter)
#   --title <string>    Issue title
#
# Options:
#   --milestone <name>  Milestone name to assign
#   --labels <labels>   Comma-separated labels to apply
#   --map <file>        JSON file mapping internal IDs to GitHub numbers
#                       Format: {"1": 291, "2": 292}
#   --complexity <complexity>  Validation complexity (simple|testable|critical)
#   --dry-run           Print what would be created without creating
#   --skip-placeholder-check  Skip unresolved placeholder validation
#                             (used by batch script which validates post-update)
#
# Output:
#   On success: prints the created issue number to stdout
#   On dry-run: prints the substituted body to stderr
#
# Exit codes:
#   0 - Issue created successfully
#   1 - Failed to create issue
#   2 - Invalid arguments
#
# Example:
#   create-issue.sh --file wip/plan_issue_1_body.md --title "feat: add X" --complexity testable
#   create-issue.sh --file wip/plan_issue_2_body.md --title "feat: add Y" --map mapping.json

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

# Source shared retry utility
source "$REPO_ROOT/scripts/lib/retry.sh"

# Default values
FILE=""
TITLE=""
MILESTONE=""
LABELS=""
MAP_FILE=""
COMPLEXITY=""
DRY_RUN=false
SKIP_PLACEHOLDER_CHECK=false

usage() {
    cat >&2 <<'EOF'
Usage: create-issue.sh --file <path> --title <string> [options]

Required:
  --file <path>       Path to issue body file
  --title <string>    Issue title

Options:
  --milestone <name>  Milestone name to assign
  --labels <labels>   Comma-separated labels to apply
  --map <file>        JSON file mapping internal IDs to GitHub numbers
  --complexity <complexity>  Validation complexity (simple|testable|critical)
  --dry-run           Print what would be created without creating
  --skip-placeholder-check  Skip placeholder substitution and validation
EOF
    exit 2
}

log() {
    echo "[create-issue] $*" >&2
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --file)
            FILE="$2"
            shift 2
            ;;
        --title)
            TITLE="$2"
            shift 2
            ;;
        --milestone)
            MILESTONE="$2"
            shift 2
            ;;
        --labels)
            LABELS="$2"
            shift 2
            ;;
        --map)
            MAP_FILE="$2"
            shift 2
            ;;
        --complexity)
            COMPLEXITY="$2"
            shift 2
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --skip-placeholder-check)
            SKIP_PLACEHOLDER_CHECK=true
            shift
            ;;
        -h|--help)
            usage
            ;;
        *)
            log "Error: unknown option: $1"
            usage
            ;;
    esac
done

# Validate required arguments
if [[ -z "$FILE" ]]; then
    log "Error: --file is required"
    usage
fi

if [[ -z "$TITLE" ]]; then
    log "Error: --title is required"
    usage
fi

if [[ ! -f "$FILE" ]]; then
    log "Error: file not found: $FILE"
    exit 1
fi

# Validate complexity if provided
if [[ -n "$COMPLEXITY" ]] && [[ ! "$COMPLEXITY" =~ ^(simple|testable|critical)$ ]]; then
    log "Error: invalid complexity: $COMPLEXITY (must be simple, testable, or critical)"
    exit 2
fi

# Strip YAML frontmatter from file content
# Frontmatter is delimited by --- at start and --- after metadata
strip_frontmatter() {
    local content="$1"

    # Check if file starts with ---
    if echo "$content" | head -1 | grep -q '^---$'; then
        # Find the second --- and skip everything before it
        echo "$content" | awk '
            BEGIN { in_frontmatter=0; found_end=0 }
            /^---$/ {
                if (in_frontmatter == 0) {
                    in_frontmatter = 1
                    next
                } else if (found_end == 0) {
                    found_end = 1
                    next
                }
            }
            found_end == 1 { print }
        '
    else
        echo "$content"
    fi
}

# Substitute <<ISSUE:N>> placeholders with #<github-number>
substitute_placeholders() {
    local content="$1"
    local map_file="$2"

    if [[ -z "$map_file" ]] || [[ ! -f "$map_file" ]]; then
        echo "$content"
        return
    fi

    # Read the mapping and build sed substitutions
    local sed_script=""
    while IFS= read -r line; do
        local internal_id github_num
        internal_id=$(echo "$line" | jq -r '.key')
        github_num=$(echo "$line" | jq -r '.value')
        sed_script="${sed_script}s/<<ISSUE:${internal_id}>>/#${github_num}/g;"
    done < <(jq -c 'to_entries[]' "$map_file")

    if [[ -n "$sed_script" ]]; then
        echo "$content" | sed -E "$sed_script"
    else
        echo "$content"
    fi
}

# Main
main() {
    # Read and process file content
    local raw_content
    raw_content=$(cat "$FILE")

    # Strip frontmatter
    local body
    body=$(strip_frontmatter "$raw_content")

    # In default mode, substitute placeholders and validate.
    # In --skip-placeholder-check mode (batch), skip both: the batch
    # script handles substitution and validation after all issues exist.
    if [[ "$SKIP_PLACEHOLDER_CHECK" != "true" ]]; then
        # Substitute placeholders if map provided
        if [[ -n "$MAP_FILE" ]]; then
            body=$(substitute_placeholders "$body" "$MAP_FILE")
        fi

        # Fail if unresolved placeholders remain
        if echo "$body" | grep -qE '<<ISSUE:[^>]+>>'; then
            local unresolved
            unresolved=$(echo "$body" | grep -oE '<<ISSUE:[^>]+>>' | sort -u | paste -sd ', ')
            log "Error: unresolved placeholders in body: $unresolved"
            log "Ensure dependencies are created first and the mapping file is correct"
            exit 1
        fi
    fi

    # Trim leading/trailing whitespace
    body=$(echo "$body" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')

    if [[ "$DRY_RUN" == "true" ]]; then
        log "=== DRY RUN ==="
        log "Title: $TITLE"
        log "Milestone: ${MILESTONE:-<none>}"
        log "Labels: ${LABELS:-<none>}"
        log "Complexity: ${COMPLEXITY:-<none>}"
        log "=== Body ==="
        echo "$body" >&2
        log "=== End Body ==="
        return 0
    fi

    # Build gh issue create command
    local gh_args=("issue" "create" "--title" "$TITLE")

    # Use heredoc for body to handle special characters
    gh_args+=("--body" "$body")

    if [[ -n "$MILESTONE" ]]; then
        gh_args+=("--milestone" "$MILESTONE")
    fi

    if [[ -n "$LABELS" ]]; then
        gh_args+=("--label" "$LABELS")
    fi

    # Create the issue (with retry for transient API failures)
    log "Creating issue: $TITLE"
    local output
    output=$(retry gh "${gh_args[@]}" 2>&1)

    # Extract issue number from URL
    # gh issue create returns URL like: https://github.com/owner/repo/issues/123
    local issue_number
    issue_number=$(echo "$output" | grep -oE '/issues/[0-9]+' | grep -oE '[0-9]+' | tail -1)

    if [[ -z "$issue_number" ]]; then
        log "Error: failed to create issue or extract issue number"
        log "Output: $output"
        exit 1
    fi

    log "Created issue #$issue_number"

    # Apply complexity label if specified
    if [[ -n "$COMPLEXITY" ]]; then
        log "Applying complexity label: validation:$COMPLEXITY"
        "$SCRIPT_DIR/apply-complexity-label.sh" "$issue_number" "$COMPLEXITY" || {
            log "Warning: failed to apply complexity label (issue still created)"
        }
    fi

    # Output the issue number
    echo "$issue_number"
}

main
