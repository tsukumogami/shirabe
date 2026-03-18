#!/usr/bin/env bash
#
# create-issues-batch.sh - Create multiple GitHub issues from a manifest
#
# This script reads a manifest file and creates issues in dependency order,
# building a placeholder mapping as issues are created so that later issues
# can reference earlier ones.
#
# Usage:
#   create-issues-batch.sh --manifest <path> [options]
#
# Required:
#   --manifest <path>   Path to manifest JSON file
#
# Options:
#   --milestone <name>        Milestone name to assign to all issues
#   --milestone-description   Milestone description (e.g., "Design: `path`")
#   --labels <labels>         Comma-separated labels to apply to all issues
#   --dry-run                 Print what would be created without creating
#   --output-map <file>       Write the final ID mapping to this file
#
# Manifest format (from /plan Phase 4):
#   [
#     {
#       "issue_id": "1",
#       "title": "feat: add X",
#       "complexity": "testable",
#       "file": "wip/plan_issue_1_body.md",
#       "status": "PASS",
#       "dependencies": [],
#       "needs_label": "needs-design"
#     },
#     ...
#   ]
#
# Per-issue fields:
#   needs_label (optional) - A label to apply alongside global --labels.
#     When present, it is merged with any global labels (additive).
#     When absent, only global --labels apply.
#
# Output:
#   Prints progress to stderr
#   Final mapping JSON to stdout (or to --output-map file)
#
# Exit codes:
#   0 - All issues created successfully
#   1 - Some issues failed to create
#   2 - Invalid arguments
#
# Example:
#   create-issues-batch.sh --manifest wip/plan_issue_manifest.json --milestone "v1.0"

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Default values
MANIFEST=""
MILESTONE=""
MILESTONE_DESCRIPTION=""
LABELS=""
DRY_RUN=false
OUTPUT_MAP=""

usage() {
    cat >&2 <<'EOF'
Usage: create-issues-batch.sh --manifest <path> [options]

Required:
  --manifest <path>         Path to manifest JSON file

Options:
  --milestone <name>        Milestone name to assign to all issues
  --milestone-description   Milestone description (e.g., "Design: `path`")
  --labels <labels>         Comma-separated labels to apply to all issues
  --dry-run                 Print what would be created without creating
  --output-map <file>       Write the final ID mapping to this file

Manifest per-issue fields:
  needs_label (optional)    Label merged with global --labels for that issue.
                            When present, added alongside global labels (additive).
                            When absent, only global --labels apply.
EOF
    exit 2
}

log() {
    echo "[create-issues-batch] $*" >&2
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --manifest)
            MANIFEST="$2"
            shift 2
            ;;
        --milestone)
            MILESTONE="$2"
            shift 2
            ;;
        --milestone-description)
            MILESTONE_DESCRIPTION="$2"
            shift 2
            ;;
        --labels)
            LABELS="$2"
            shift 2
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --output-map)
            OUTPUT_MAP="$2"
            shift 2
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
if [[ -z "$MANIFEST" ]]; then
    log "Error: --manifest is required"
    usage
fi

if [[ ! -f "$MANIFEST" ]]; then
    log "Error: manifest file not found: $MANIFEST"
    exit 1
fi

# Check prerequisites
if ! command -v jq &>/dev/null; then
    log "Error: jq is required but not found"
    exit 1
fi

# Topological sort of issues based on dependencies
# Returns issue IDs in creation order (dependencies first)
topological_sort() {
    local manifest="$1"

    # Get all issue IDs and their dependencies
    # Build adjacency list and compute in-degrees
    local issues
    issues=$(jq -c '[.[] | select(.status == "PASS")]' "$manifest")

    # Use jq to perform topological sort
    # This outputs IDs in order where dependencies come before dependents
    echo "$issues" | jq -r '
        # Build a map of id -> dependencies
        (reduce .[] as $item ({}; . + {($item.issue_id): ($item.dependencies // [])})) as $deps |

        # Get all IDs
        [.[] | .issue_id] as $all |

        # Topological sort: repeatedly pick items whose deps are all done
        reduce range($all | length) as $_ (
            {done: [], todo: $all};

            .done as $done |
            [.todo[] | . as $id | select(
                [$deps[$id][] | select(. as $d | $done | index($d) | not)] | length == 0
            )][0] as $pick |

            if $pick then
                {done: ($done + [$pick]), todo: (.todo - [$pick])}
            else
                .
            end
        ) |
        .done[]
    '
}

# Strip YAML frontmatter from content
strip_frontmatter() {
    local content="$1"

    if echo "$content" | head -1 | grep -q '^---$'; then
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

# Check for unresolved placeholders in text. Returns 0 if clean, 1 if found.
check_placeholders() {
    local text="$1"
    if echo "$text" | grep -qE '<<ISSUE:[^>]+>>'; then
        return 1
    fi
    return 0
}

# Resolve file path relative to manifest directory
resolve_file_path() {
    local file="$1"
    local manifest_dir="$2"

    if [[ ! "$file" = /* ]]; then
        if [[ "$manifest_dir" != "." && ! "$file" =~ ^"$manifest_dir"/ ]]; then
            file="$manifest_dir/$file"
        fi
    fi
    echo "$file"
}

# Main
main() {
    log "Reading manifest: $MANIFEST"

    local manifest_dir
    manifest_dir=$(dirname "$MANIFEST")

    local total_issues
    total_issues=$(jq '[.[] | select(.status == "PASS")] | length' "$MANIFEST")
    log "Found $total_issues issues to create"

    if [[ "$total_issues" -eq 0 ]]; then
        log "No issues with status PASS found"
        echo "{}"
        return 0
    fi

    # If a milestone was specified, ensure it exists (create if needed)
    # Resolve manage-milestone.sh relative to the skill directory
    local skill_scripts_dir
    skill_scripts_dir="$SCRIPT_DIR/../../github-milestone/scripts"

    if [[ -n "$MILESTONE" && "$DRY_RUN" != "true" ]]; then
        # Check if the milestone already exists
        if "$skill_scripts_dir/manage-milestone.sh" get --title "$MILESTONE" >/dev/null 2>&1; then
            log "Using existing milestone: $MILESTONE"
        else
            log "Creating milestone: $MILESTONE"
            "$skill_scripts_dir/manage-milestone.sh" create \
                --title "$MILESTONE" \
                --description "${MILESTONE_DESCRIPTION:-(No description provided)}" >/dev/null 2>&1
        fi
    fi

    # Topological sort isn't needed for pass 1 (no substitution), but
    # preserving order keeps issue numbers roughly sequential
    log "Computing creation order..."
    local sorted_ids
    sorted_ids=$(topological_sort "$MANIFEST")

    # Initialize mapping
    local map_file
    map_file=$(mktemp)
    echo "{}" > "$map_file"
    trap "rm -f '$map_file'" EXIT

    local created_count=0
    local failed_count=0
    local failed_ids=()

    # ── Pass 1: Create all issues with placeholders intact ──
    log ""
    log "=== Pass 1: Creating issues ==="
    while IFS= read -r issue_id; do
        [[ -z "$issue_id" ]] && continue

        local issue_data
        issue_data=$(jq -c --arg id "$issue_id" '.[] | select(.issue_id == $id)' "$MANIFEST")

        local title complexity file needs_label
        title=$(echo "$issue_data" | jq -r '.title')
        complexity=$(echo "$issue_data" | jq -r '.complexity // "simple"')
        file=$(echo "$issue_data" | jq -r '.file')
        file=$(resolve_file_path "$file" "$manifest_dir")
        needs_label=$(echo "$issue_data" | jq -r '.needs_label // empty')

        log "[$((created_count + failed_count + 1))/$total_issues] Creating issue $issue_id: $title"

        # Merge global labels with per-issue needs_label (additive)
        local merged_labels="$LABELS"
        if [[ -n "$needs_label" ]]; then
            if [[ -n "$merged_labels" ]]; then
                merged_labels="${merged_labels},${needs_label}"
            else
                merged_labels="$needs_label"
            fi
            log "  Per-issue label: $needs_label"
        fi

        # Skip placeholder substitution -- batch handles it in pass 2
        local create_args=(
            "--file" "$file"
            "--title" "$title"
            "--complexity" "$complexity"
            "--skip-placeholder-check"
        )

        if [[ -n "$MILESTONE" ]]; then
            create_args+=("--milestone" "$MILESTONE")
        fi

        if [[ -n "$merged_labels" ]]; then
            create_args+=("--labels" "$merged_labels")
        fi

        if [[ "$DRY_RUN" == "true" ]]; then
            create_args+=("--dry-run")
        fi

        local github_number
        if github_number=$("$SCRIPT_DIR/create-issue.sh" "${create_args[@]}"); then
            if [[ "$DRY_RUN" != "true" ]]; then
                jq --arg id "$issue_id" --arg num "$github_number" \
                    '. + {($id): ($num | tonumber)}' "$map_file" > "$map_file.tmp"
                mv "$map_file.tmp" "$map_file"

                log "  -> Created #$github_number"
                ((created_count++)) || true
            else
                ((created_count++)) || true
            fi
        else
            log "  -> FAILED"
            ((failed_count++)) || true
            failed_ids+=("$issue_id")
        fi
    done <<< "$sorted_ids"

    # ── Pass 2: Update all issue bodies with resolved placeholders ──
    if [[ "$DRY_RUN" != "true" && "$created_count" -gt 0 ]]; then
        log ""
        log "=== Pass 2: Updating issue bodies with resolved references ==="
        local update_count=0
        local update_failed=0

        while IFS= read -r issue_id; do
            [[ -z "$issue_id" ]] && continue

            # Skip issues that failed to create
            local github_number
            github_number=$(jq -r --arg id "$issue_id" '.[$id] // empty' "$map_file")
            [[ -z "$github_number" ]] && continue

            local issue_data
            issue_data=$(jq -c --arg id "$issue_id" '.[] | select(.issue_id == $id)' "$MANIFEST")

            local file
            file=$(echo "$issue_data" | jq -r '.file')
            file=$(resolve_file_path "$file" "$manifest_dir")

            # Read body, strip frontmatter, substitute placeholders
            local raw_content body
            raw_content=$(cat "$file")
            body=$(strip_frontmatter "$raw_content")
            body=$(substitute_placeholders "$body" "$map_file")
            body=$(echo "$body" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')

            log "  Updating #$github_number (issue $issue_id)..."
            if gh issue edit "$github_number" --body "$body" >/dev/null 2>&1; then
                ((update_count++)) || true
            else
                log "  -> FAILED to update #$github_number"
                ((update_failed++)) || true
            fi
        done <<< "$sorted_ids"

        log "  Updated: $update_count, Failed: $update_failed"
    fi

    # ── Pass 3: Validate no unresolved placeholders remain ──
    if [[ "$DRY_RUN" != "true" && "$created_count" -gt 0 ]]; then
        log ""
        log "=== Pass 3: Validating placeholder resolution ==="
        local placeholder_issues=()

        while IFS= read -r issue_id; do
            [[ -z "$issue_id" ]] && continue

            local github_number
            github_number=$(jq -r --arg id "$issue_id" '.[$id] // empty' "$map_file")
            [[ -z "$github_number" ]] && continue

            # Fetch the issue body from GitHub and check for placeholders
            local current_body
            current_body=$(gh issue view "$github_number" --json body --jq '.body' 2>/dev/null || true)

            if ! check_placeholders "$current_body"; then
                local unresolved
                unresolved=$(echo "$current_body" | grep -oE '<<ISSUE:[^>]+>>' | sort -u | paste -sd ', ')
                log "  WARNING: #$github_number still has unresolved placeholders: $unresolved"
                placeholder_issues+=("#$github_number")
            fi
        done <<< "$sorted_ids"

        if [[ ${#placeholder_issues[@]} -gt 0 ]]; then
            log ""
            log "WARNING: ${#placeholder_issues[@]} issue(s) have unresolved placeholders: ${placeholder_issues[*]}"
            log "These issues need manual placeholder resolution."
        else
            log "  All issues have resolved placeholders."
        fi
    fi

    # Report summary
    log ""
    log "=== Summary ==="
    log "Created: $created_count"
    log "Failed: $failed_count"

    if [[ ${#failed_ids[@]} -gt 0 ]]; then
        log "Failed issue IDs: ${failed_ids[*]}"
    fi

    # Output the final mapping
    local final_map
    final_map=$(cat "$map_file")

    if [[ -n "$OUTPUT_MAP" ]]; then
        echo "$final_map" > "$OUTPUT_MAP"
        log "Mapping written to: $OUTPUT_MAP"
    else
        echo "$final_map"
    fi

    # Return error if any issues failed to create
    if [[ $failed_count -gt 0 ]]; then
        return 1
    fi

    return 0
}

main
