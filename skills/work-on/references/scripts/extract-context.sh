#!/usr/bin/env bash
# extract-context.sh - Extract and inject design context for a GitHub issue
# Part of /work-on Phase 0: Context Injection
#
# Usage: ./extract-context.sh <issue-number> --session <name> --issue-repo <owner/repo>
#
# This script performs the complete context injection:
# 1. Searches for design docs containing this issue
# 2. Parses the Implementation Issues table
# 3. Extracts relevant design sections
# 4. Stores content via koto context add under key "context.md"
# 5. Displays context summary to stdout
# 6. Outputs final JSON summary for Claude
#
# Options:
#   --session <name>  The koto session to store the content in, under key
#                     "context.md". Required: the script writes no file. Without
#                     it (or with the flag and no value), or with it and no koto
#                     on PATH, the script prints a failed JSON summary
#                     (context_available false) whose warning names koto, and
#                     stores nothing.
#   --issue-repo <owner/repo>
#                     The repository the issue lives in: the run's ISSUE_REPO,
#                     which the context_injection directive passes as written.
#                     Required, and empty for an issue in this repository.
#                     Missing, or not owner/repo, is a failed JSON summary
#                     that stores nothing, never a guess at this repository:
#                     reading the wrong repository's issue N would put another
#                     issue's acceptance criteria in front of the run.
#
# An issue in another repository (a non-empty --issue-repo) is read with
# `gh issue view <N> --repo <owner/repo>`, and this repository's design docs
# are not searched, since a `#N` in them names this repository's issue N.
#
# Environment:
#   KOTO_BIN          The koto binary to run (default: koto on PATH).
#
# Exit codes:
#   0 - Every outcome the JSON summary reports: success, degraded, and failed,
#       including a missing issue number, session or issue repository, no
#       koto, and a failed koto context add
#   non-zero - an unexpected error under set -e, with no JSON summary
#
# Output: Human-readable display followed by JSON summary
#   {
#     "status": "success|degraded|failed",
#     "context_available": true|false,
#     "context_key": "context.md" (on success),
#     "session": "<name>" (on success),
#     "tier": "simple|testable|critical",
#     "warnings": ["warning1", "warning2"]
#   }
#
# Functions:
#   display_context()       - Print section header to stdout
#   display_warnings()      - Print accumulated warnings
#   store_context()         - Store content via koto context
#   json_success()          - Emit success JSON summary
#   json_failed()           - Emit failure JSON summary
#   check_prerequisites()   - Verify gh and jq are available
#   find_design_doc()       - Search docs/ for design doc referencing the issue
#   parse_table_agent()     - Parse implementation issues table via agent
#   parse_table_regex()     - Parse implementation issues table via regex fallback
#   extract_section()       - Extract a section from markdown by heading
#   summarize_with_agent()  - Summarize design context via agent
#   build_context()         - Assemble the context.md content from design doc sections
#   main()                  - Entry point

set -euo pipefail

# Initialize warning array
declare -a WARNINGS
STATUS="success"
SESSION=""
# The issue's repository, from --issue-repo; empty for a same-repository run.
ISSUE_REPO=""
ISSUE_REPO_GIVEN=0
# The koto binary, overridable for tests the way the sibling state scripts allow.
KOTO="${KOTO_BIN:-koto}"

# Display and storage helpers
display_context() {
  local context="$1"
  local issue="$2"

  echo ""
  echo "---------------------------------------------------"
  echo "Design Context for Issue ${ISSUE_REPO}#${issue}"
  echo "---------------------------------------------------"
  echo ""
  echo "$context"
  echo ""
  echo "---------------------------------------------------"
  echo "Context stored in koto session: ${SESSION} (key: context.md)"
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

# Store context content via koto context. The script writes no file. A failed
# add is reported in the JSON summary rather than as a non-zero exit, so the
# header's exit contract holds on the one storage path there is.
store_context() {
  local context="$1"
  if ! printf '%s\n' "$context" | "$KOTO" context add "$SESSION" context.md; then
    json_failed "koto context add failed" "could not store context.md in koto session ${SESSION}; nothing was stored"
    exit 0
  fi
}

# JSON output helpers (printed at end for Claude to parse)
json_success() {
  local tier="${1:-simple}"
  local warnings_json
  warnings_json=$(printf '%s\n' "${WARNINGS[@]}" | jq -R . | jq -s .)
  jq -n \
    --arg status "$STATUS" \
    --arg tier "$tier" \
    --arg session "$SESSION" \
    --argjson warnings "$warnings_json" \
    '{status: $status, context_available: true, context_key: "context.md", session: $session, tier: $tier, warnings: $warnings}'
}

json_failed() {
  local error="$1"
  local warning="${2:-}"
  if [ -n "$warning" ]; then
    jq -n --arg error "$error" --arg warning "$warning" \
      '{status: "failed", context_available: false, error: $error, warnings: [$warning]}'
  else
    jq -n --arg error "$error" \
      '{status: "failed", context_available: false, error: $error, warnings: []}'
  fi
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
  if grep -qiE "\| *Title *\|" <<<"$header"; then
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

# Build the content stored under key context.md
# Args: $1 = context excerpt, $2 = issue number, $3 = design doc path, $4 = section
build_context() {
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

  # 1. Find design doc. An issue in another repository skips the search: this
  # repository's design docs number its own issues, so a `#N` there is not it.
  local design_doc found=1
  if [ -n "$ISSUE_REPO" ]; then
    WARNINGS+=("Issue is in ${ISSUE_REPO}: design doc search skipped - using issue body only")
    found=0
  elif ! design_doc=$(find_design_doc "$issue"); then
    WARNINGS+=("Design doc not found - using issue body only")
    found=0
  fi
  if [ "$found" -eq 0 ]; then
    STATUS="degraded"

    # Use issue body as context, read from the issue's own repository.
    local issue_body
    local -a repo_args=()
    [ -z "$ISSUE_REPO" ] || repo_args=(--repo "$ISSUE_REPO")
    issue_body=$(gh issue view "$issue" ${repo_args[@]+"${repo_args[@]}"} --json body --jq '.body' 2>/dev/null) || {
      json_failed "Failed to fetch issue${ISSUE_REPO:+ from $ISSUE_REPO}"
      exit 0
    }

    # Store in koto, then display, show warnings, output JSON
    store_context "$issue_body"
    display_context "$issue_body" "$issue"
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

  # 4. Build the context.md content
  local context_md
  context_md=$(build_context "$context" "$issue" "$design_doc" "$section")

  # 5. Store it in koto, then display it and the warnings
  store_context "$context_md"
  display_context "$context_md" "$issue"
  display_warnings

  # 6. Output JSON summary for Claude
  json_success "$tier"
}

# Parse arguments
ISSUE=""
while [ $# -gt 0 ]; do
  case "$1" in
    --session)
      # A trailing --session has no value; shift past the flag alone so set -e
      # doesn't end the script on a failed `shift 2`, and let the empty
      # SESSION check below report it.
      SESSION="${2:-}"
      shift
      [ $# -gt 0 ] && shift
      ;;
    --issue-repo)
      # An empty value is a real answer (this repository), so whether a value
      # came at all is kept apart from the value. A trailing flag with no
      # argument after it gave none.
      if [ $# -ge 2 ]; then
        ISSUE_REPO_GIVEN=1
        ISSUE_REPO="$2"
        shift
      fi
      shift
      ;;
    *)
      ISSUE="$1"
      shift
      ;;
  esac
done

if [ -z "$ISSUE" ]; then
  json_failed "Issue number required"
  exit 0
fi

# The context is stored in a koto session and nowhere else. No session, or no
# koto to reach it with, is a failure the caller reads from the JSON.
if [ -z "$SESSION" ]; then
  json_failed "No session given (--session <name>)" "koto session required: this script stores context in koto and writes no file, and no session name was given"
  exit 0
fi
# No guess at the issue's repository: the template knows it, so a caller that
# leaves it out, or passes something that isn't owner/repo, stops here. koto
# checks ISSUE_REPO's pattern at init; it is checked again because the value
# reaches a gh argument.
if [ "$ISSUE_REPO_GIVEN" -eq 0 ]; then
  json_failed "No issue repository given (--issue-repo <owner/repo>, empty for this repository)" "the issue's repository is required: pass the run's ISSUE_REPO as the context_injection directive gives it"
  exit 0
fi
RE_REPO='^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$'
if [ -n "$ISSUE_REPO" ] && ! [[ $ISSUE_REPO =~ $RE_REPO ]]; then
  json_failed "--issue-repo [$ISSUE_REPO] is not owner/repo"
  exit 0
fi
if ! command -v "$KOTO" &>/dev/null; then
  json_failed "koto not found" "koto not found on PATH; install it with 'tsuku install koto'. This script stores context in koto and writes no file"
  exit 0
fi

main "$ISSUE"
