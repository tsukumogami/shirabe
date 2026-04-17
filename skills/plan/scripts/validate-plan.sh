#!/usr/bin/env bash
#
# validate-plan.sh - Pre-flight validation for PLAN.md documents
#
# Checks frontmatter fields and optional upstream chain before plan-to-tasks.sh
# or the cascade consume the document.
#
# Usage:
#   validate-plan.sh <PLAN.md-path>
#
# Exit codes:
#   0 - valid PLAN doc (upstream check passes or upstream is absent)
#   1 - malformed input (file not found, not readable)
#   2 - frontmatter validation failure (missing or wrong required fields)
#   3 - upstream validation failure (file missing, not tracked, or wrong status)

set -euo pipefail

usage() {
    cat >&2 <<'EOF'
Usage: validate-plan.sh <PLAN.md-path>

Validates a PLAN.md document's frontmatter and optional upstream chain.

Exit codes:
  0 - valid
  1 - malformed input (file not found, not readable)
  2 - frontmatter validation failure
  3 - upstream validation failure
EOF
    exit 1
}

log_error() {
    echo "validate-plan: error: $*" >&2
}

log_ok() {
    echo "validate-plan: ok: $*" >&2
}

# Extract the YAML frontmatter block (between the first two --- markers)
extract_frontmatter() {
    local file="$1"
    awk '
        /^---$/ {
            count++
            if (count == 1) { next }
            if (count == 2) { exit }
        }
        count == 1 { print }
    ' "$file"
}

# Get a single field value from frontmatter text on stdin.
# Strips surrounding quotes and trims trailing whitespace.
get_field() {
    local field="$1"
    awk -v field="$field" '
        $0 ~ "^" field ":" {
            sub("^" field ":[ \t]*", "")
            gsub(/^["'"'"']|["'"'"']$/, "")  # strip surrounding quotes
            sub(/[ \t]+$/, "")               # strip trailing whitespace
            print
            exit
        }
    '
}

# ── Argument parsing ──

if [[ $# -eq 0 || "$1" == "-h" || "$1" == "--help" ]]; then
    usage
fi

PLAN_PATH="$1"

if [[ $# -gt 1 ]]; then
    log_error "too many arguments"
    usage
fi

# ── File validation ──

if [[ ! -e "$PLAN_PATH" ]]; then
    log_error "file not found: $PLAN_PATH"
    exit 1
fi

if [[ ! -r "$PLAN_PATH" ]]; then
    log_error "file is not readable: $PLAN_PATH"
    exit 1
fi

# ── Frontmatter presence ──

first_line=$(head -1 "$PLAN_PATH")
if [[ "$first_line" != "---" ]]; then
    log_error "PLAN file does not start with YAML frontmatter (expected '---' on line 1): $PLAN_PATH"
    exit 2
fi

frontmatter=$(extract_frontmatter "$PLAN_PATH")

# ── Required field: schema ──

schema_val=$(echo "$frontmatter" | get_field "schema")
if [[ "$schema_val" != "plan/v1" ]]; then
    log_error "frontmatter 'schema' must be 'plan/v1', got: '${schema_val}' — ${PLAN_PATH}"
    exit 2
fi

# ── Required field: execution_mode ──

execution_mode=$(echo "$frontmatter" | get_field "execution_mode")
if [[ -z "$execution_mode" ]]; then
    log_error "frontmatter missing required field 'execution_mode' — ${PLAN_PATH}"
    exit 2
fi

# ── Required field: issue_count ──

issue_count=$(echo "$frontmatter" | get_field "issue_count")
if [[ -z "$issue_count" ]]; then
    log_error "frontmatter missing required field 'issue_count' — ${PLAN_PATH}"
    exit 2
fi

# ── Optional field: upstream ──

upstream_val=$(echo "$frontmatter" | get_field "upstream")

if [[ -z "$upstream_val" ]]; then
    log_ok "no upstream field — skipping upstream validation"
    log_ok "${PLAN_PATH} is valid"
    exit 0
fi

# Resolve repo root relative to the PLAN file's location
repo_root=$(git -C "$(dirname "$(realpath "$PLAN_PATH")")" rev-parse --show-toplevel 2>/dev/null) || {
    log_error "could not determine git repo root from ${PLAN_PATH} — is this file in a git repository?"
    exit 3
}

upstream_abs="${repo_root}/${upstream_val}"

# ── Upstream: file existence ──

if [[ ! -f "$upstream_abs" ]]; then
    log_error "upstream file does not exist: '${upstream_val}' (resolved to ${upstream_abs}) — ${PLAN_PATH}"
    exit 3
fi

# ── Upstream: git tracking ──

if ! git -C "$repo_root" ls-files --error-unmatch "$upstream_val" &>/dev/null; then
    log_error "upstream file exists but is not tracked by git: '${upstream_val}' — ${PLAN_PATH}"
    log_error "  run 'git add ${upstream_val}' or check the path"
    exit 3
fi

# ── Upstream: status field ──

upstream_frontmatter=$(extract_frontmatter "$upstream_abs")
upstream_status=$(echo "$upstream_frontmatter" | get_field "status")

# Accept both Accepted and Planned: /plan transitions the upstream design from
# Accepted → Planned when creating the PLAN doc, so both are valid states on PRs.
if [[ "$upstream_status" != "Accepted" && "$upstream_status" != "Planned" ]]; then
    log_error "upstream file '${upstream_val}' has status '${upstream_status}' — expected 'Accepted' or 'Planned' — ${PLAN_PATH}"
    log_error "  the upstream document must be Accepted (before planning) or Planned (after planning starts)"
    exit 3
fi

log_ok "upstream '${upstream_val}' is ${upstream_status}"
log_ok "${PLAN_PATH} is valid"
exit 0
