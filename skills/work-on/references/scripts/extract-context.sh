#!/usr/bin/env bash
# extract-context.sh - Extract and inject design context for a GitHub issue
# Part of /work-on Phase 0: Context Injection
#
# Usage: ./extract-context.sh <issue-number>
#
# This script performs the complete context injection:
# 1. Searches for design docs containing this issue
# 2. Parses the Implementation Issues table
# 3. Extracts relevant design sections
# 4. Displays context summary to stdout
# 5. Writes wip/IMPLEMENTATION_CONTEXT.md
# 6. Outputs final JSON summary for Claude
#
# Exit codes:
#   0 - Always (script never fails for expected issues)
#
# Output: Human-readable display followed by JSON summary
#   {
#     "status": "success|degraded|failed",
#     "context_available": true|false,
#     "context_file": "wip/IMPLEMENTATION_CONTEXT.md" (if written),
#     "tier": "simple|testable|critical",
#     "warnings": ["warning1", "warning2"]
#   }
#
# Functions:
#   display_context()       - Print section header to stdout
#   display_warnings()      - Print accumulated warnings
#   write_context_file()    - Write wip/IMPLEMENTATION_CONTEXT.md
#   json_success()          - Emit success JSON summary
#   json_failed()           - Emit failure JSON summary
#   check_prerequisites()   - Verify gh and jq are available
#   find_design_doc()       - Search docs/ for design doc referencing the issue
#   parse_table_agent()     - Parse implementation issues table via agent
#   parse_table_regex()     - Parse implementation issues table via regex fallback
#   extract_section()       - Extract a section from markdown by heading
#   summarize_with_agent()  - Summarize design context via agent
#   build_context_file()    - Assemble context from design doc sections
#   main()                  - Entry point

set -euo pipefail

# Initialize warning array
declare -a WARNINGS
STATUS="success"

# Display and file writing helpers
display_context() {
  local context="$1"
  local issue="$2"

  echo ""
  echo "---------------------------------------------------"
  echo "Design Context for Issue #${issue}"
  echo "---------------------------------------------------"
  echo ""
  echo "$context"
  echo ""
  echo "---------------------------------------------------"
  echo "Full context saved to wip/IMPLEMENTATION_CONTEXT.md"
  echo "---------------------------------------------------"
  echo ""
}

display_warnings() {
  if [ ${#WARNINGS[@]} -gt 0 ]; then
    echo "Context Extraction Warnings:"
    for warning in "${WARNINGS[@]}"; do
      echo "  - $warning"
    done
    echo ""
  fi
}

write_context_file() {
  local context="$1"
  mkdir -p wip
  echo "$context" > wip/IMPLEMENTATION_CONTEXT.md
}

# JSON output helpers (printed at end for Claude to parse)
json_success() {
  local tier="${1:-simple}"
  local warnings_json
  warnings_json=$(printf '%s\n' "${WARNINGS[@]}" | jq -R . | jq -s .)
  jq -n \
    --arg status "$STATUS" \
    --arg tier "$tier" \
    --arg context_file "wip/IMPLEMENTATION_CONTEXT.md" \
    --argjson warnings "$warnings_json" \
    '{status: $status, context_available: true, context_file: $context_file, tier: $tier, warnings: $warnings}'
}

json_failed() {
  local error="$1"
  jq -n --arg error "$error" \
    '{status: "failed", context_available: false, error: $error, warnings: []}'
}

# Check prerequisites
check_prerequisites() {
  if ! command -v gh &>/dev/null; then
    json_failed "gh CLI not found"
    exit 0
  fi
  if ! command -v jq &>/dev/null; then
    json_failed "jq not found"
    exit 0
  fi
  if ! gh auth status &>/dev/null; then
    json_failed "gh CLI not authenticated"
    exit 0
  fi
}

# Find design doc containing issue reference
# Returns: design doc path or empty string
find_design_doc() {
  local issue="$1"
  local candidates=()

  # Search all DESIGN-*.md files for issue reference
  while IFS= read -r doc; do
    if grep -q "#${issue}" "$doc" 2>/dev/null; then
      candidates+=("$doc")
    fi
  done < <(find docs -name "DESIGN-*.md" 2>/dev/null || true)

  if [ ${#candidates[@]} -eq 0 ]; then
    return 1
  elif [ ${#candidates[@]} -eq 1 ]; then
    echo "${candidates[0]}"
    return 0
  else
    # Multiple matches - prefer the one with Implementation Issues table
    local best_match=""
    for doc in "${candidates[@]}"; do
      # Check if this doc has an Implementation Issues table with this issue
      if grep -q "^| \[#${issue}\]" "$doc" 2>/dev/null; then
        best_match="$doc"
        break
      fi
    done

    if [ -n "$best_match" ]; then
      WARNINGS+=("Multiple design docs found, using one with Implementation Issues table")
      STATUS="degraded"
      echo "$best_match"
      return 0
    else
      # No doc has the issue in Implementation Issues table
      WARNINGS+=("Found multiple design docs: ${candidates[*]}, none with Implementation Issues table")
      STATUS="failed"
      return 1
    fi
  fi
}

# Parse Implementation Issues table using agent
# Args: $1 = design doc path, $2 = issue number
# Returns: JSON with tier and section
parse_table_agent() {
  local design_doc="$1"
  local issue="$2"

  # For now, return empty to trigger regex fallback
  # TODO: Implement agent-based parsing in future iteration
  return 1
}

# Parse Implementation Issues table using regex
# Args: $1 = design doc path, $2 = issue number
# Returns: JSON with tier and section
parse_table_regex() {
  local design_doc="$1"
  local issue="$2"

  # Find the table row for this issue
  local row
  row=$(grep "| \[#${issue}\]" "$design_doc" 2>/dev/null | head -1) || return 1

  if [ -z "$row" ]; then
    return 1
  fi

  # Parse columns - supports multiple formats:
  # Current:  | Issue | Dependencies | Tier |           (3-col, title in issue link)
  # Legacy 1: | Issue | Title | Dependencies | Tier |   (4-col)
  # Legacy 2: | Issue | Title | Dependencies | Tier | Section |  (5-col)
  # Detect format by checking if the table header has a Title column
  local header tier section
  header=$(grep -E "^\| *Issue" "$design_doc" 2>/dev/null | head -1) || true
  if echo "$header" | grep -qiE "\| *Title *\|"; then
    # Legacy format: Tier at col 5, Section at col 6
    tier=$(echo "$row" | awk -F'|' '{gsub(/^[ \t]+|[ \t]+$/, "", $5); print $5}')
    section=$(echo "$row" | awk -F'|' '{gsub(/^[ \t]+|[ \t]+$/, "", $6); print $6}')
  else
    # New format: Tier at col 4, no Section column
    tier=$(echo "$row" | awk -F'|' '{gsub(/^[ \t]+|[ \t]+$/, "", $4); print $4}')
    section=""
  fi

  # Default to critical tier if missing (conservative for legacy designs)
  [ -z "$tier" ] && tier="critical"
  [ -z "$section" ] && section="None"

  jq -n --arg tier "$tier" --arg section "$section" \
    '{tier: $tier, section: $section}'
}

# Extract section content from design doc
# Args: $1 = design doc path, $2 = section anchor (e.g., "§4.2")
# Returns: section content or empty
extract_section() {
  local design_doc="$1"
  local section="$2"

  if [ "$section" = "None" ] || [ -z "$section" ]; then
    cat "$design_doc"
    return 0
  fi

  # Convert §4.2 to heading pattern
  # Matches: "## 4.2", "### 4.2", etc.
  local heading_pattern
  heading_pattern=$(echo "$section" | sed 's/§//')

  # Extract from heading to next same-level heading
  awk "/^##+ ${heading_pattern} /,/^##+ [0-9]/" "$design_doc" || {
    # Section not found
    return 1
  }
}

# Summarize with agent (for critical tier)
# Args: $1 = design doc path, $2 = issue number
# Returns: agent-generated summary
summarize_with_agent() {
  local design_doc="$1"
  local issue="$2"

  # For now, return empty to trigger fallback
  # TODO: Implement agent-based summarization in future iteration
  return 1
}

# Build IMPLEMENTATION_CONTEXT.md content
# Args: $1 = context excerpt, $2 = issue number, $3 = design doc path, $4 = section
build_context_file() {
  local excerpt="$1"
  local issue="$2"
  local design_doc="$3"
  local section="$4"

  cat <<EOF
---
# TODO: Fill in this summary after reading the design excerpt below
summary:
  constraints:
    - # TODO: Key design constraints that affect implementation
  integration_points:
    - # TODO: Components/files that must integrate with this work
  risks:
    - # TODO: Potential issues to watch for during implementation
  approach_notes: |
    # TODO: Brief notes on implementation approach based on design context
---

# Implementation Context: Issue #${issue}

**Source**: ${design_doc}${section:+ (${section})}

## Design Excerpt

${excerpt}
EOF
}

# Main function
main() {
  local issue="$1"

  check_prerequisites

  # 1. Find design doc
  local design_doc
  if ! design_doc=$(find_design_doc "$issue"); then
    WARNINGS+=("Design doc not found - using issue body only")
    STATUS="degraded"

    # Use issue body as context
    local issue_body
    issue_body=$(gh issue view "$issue" --json body --jq '.body' 2>/dev/null) || {
      json_failed "Failed to fetch issue"
      exit 0
    }

    # Display, write file, show warnings, output JSON
    display_context "$issue_body" "$issue"
    write_context_file "$issue_body"
    display_warnings
    json_success "simple"
    exit 0
  fi

  # 2. Parse table
  local table_data tier section
  if ! table_data=$(parse_table_agent "$design_doc" "$issue"); then
    WARNINGS+=("Agent table parsing not implemented - using regex fallback")
    STATUS="degraded"

    if ! table_data=$(parse_table_regex "$design_doc" "$issue"); then
      WARNINGS+=("Regex parsing failed - using full design doc")
      tier="testable"
      section="None"
    else
      tier=$(echo "$table_data" | jq -r '.tier')
      section=$(echo "$table_data" | jq -r '.section')
    fi
  else
    tier=$(echo "$table_data" | jq -r '.tier')
    section=$(echo "$table_data" | jq -r '.section')
  fi

  # 3. Extract context (tier-dependent)
  local context
  if [ "$tier" = "critical" ]; then
    # Agent-based summarization for critical tier
    if ! context=$(summarize_with_agent "$design_doc" "$issue"); then
      WARNINGS+=("Agent summarization not implemented - using section extraction")
      STATUS="degraded"

      if ! context=$(extract_section "$design_doc" "$section"); then
        WARNINGS+=("Section extraction failed - using full doc")
        context=$(cat "$design_doc")
      fi
    fi
  else
    # Table-indexed extraction for simple/testable
    if ! context=$(extract_section "$design_doc" "$section"); then
      WARNINGS+=("Section $section not found - using full doc")
      STATUS="degraded"
      context=$(cat "$design_doc")
    fi
  fi

  # 4. Build context file content
  local context_md
  context_md=$(build_context_file "$context" "$issue" "$design_doc" "$section")

  # 5. Display context, write file, show warnings
  display_context "$context_md" "$issue"
  write_context_file "$context_md"
  display_warnings

  # 6. Output JSON summary for Claude
  json_success "$tier"
}

# Validate argument
if [ $# -lt 1 ]; then
  json_failed "Issue number required"
  exit 0
fi

main "$1"
