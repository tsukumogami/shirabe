#!/usr/bin/env bash
#
# apply-complexity-label.sh - Apply validation complexity label to a GitHub issue
#
# This script implements the hybrid label application approach (Decision 4C):
# 1. Fast path: Try to apply the label (works if label exists)
# 2. Fallback: Create the label if missing, then retry application
# 3. Race handling: Catch 422 errors from concurrent creation, retry application
#
# Usage:
#   apply-complexity-label.sh <issue_number> <complexity>
#
# Arguments:
#   issue_number  GitHub issue number
#   complexity    One of: simple, testable, critical
#
# Exit codes:
#   0 - Label applied successfully
#   1 - Failed to apply label (after retries)
#   2 - Invalid arguments
#
# Example:
#   apply-complexity-label.sh 294 testable

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

# Source shared retry utility
source "$REPO_ROOT/scripts/lib/retry.sh"

# Complexity-to-color mapping (from DESIGN-tiered-validation.md Key Interfaces section 4)
# Uses functions instead of associative arrays for Bash 3.2 (macOS) compatibility
complexity_color() {
    case "$1" in
        simple)   echo "d4c5f9" ;;   # Light purple
        testable) echo "0366d6" ;;    # Blue
        critical) echo "d93f0b" ;;    # Red
    esac
}

complexity_description() {
    case "$1" in
        simple)   echo "Simple validation: tests pass, CI green" ;;
        testable) echo "Testable validation: includes validation script" ;;
        critical) echo "Critical validation: security review required" ;;
    esac
}

usage() {
    echo "Usage: $0 <issue_number> <complexity>" >&2
    echo "  complexity: simple | testable | critical" >&2
    exit 2
}

log() {
    echo "[apply-complexity-label] $*" >&2
}

# Validate arguments
if [[ $# -ne 2 ]]; then
    usage
fi

ISSUE_NUMBER="$1"
COMPLEXITY="$2"

# Validate issue number is numeric
if ! [[ "$ISSUE_NUMBER" =~ ^[0-9]+$ ]]; then
    log "Error: issue_number must be numeric, got: $ISSUE_NUMBER"
    exit 2
fi

# Validate complexity is known
LABEL_COLOR="$(complexity_color "$COMPLEXITY")"
if [[ -z "$LABEL_COLOR" ]]; then
    log "Error: unknown complexity: $COMPLEXITY"
    log "Valid complexity levels: simple, testable, critical"
    exit 2
fi

LABEL_NAME="validation:$COMPLEXITY"
LABEL_DESC="$(complexity_description "$COMPLEXITY")"

# Try to apply label (fast path - label already exists)
apply_label() {
    retry gh issue edit "$ISSUE_NUMBER" --add-label "$LABEL_NAME" 2>&1
}

# Create the label
create_label() {
    retry gh label create "$LABEL_NAME" \
        --description "$LABEL_DESC" \
        --color "$LABEL_COLOR" 2>&1
}

# Main logic with fallback
main() {
    local output
    local exit_code

    # Fast path: try to apply label directly
    log "Attempting to apply label '$LABEL_NAME' to issue #$ISSUE_NUMBER..."

    set +e
    output=$(apply_label)
    exit_code=$?
    set -e

    if [[ $exit_code -eq 0 ]]; then
        log "Label applied successfully"
        return 0
    fi

    # Check if failure is due to missing label
    if echo "$output" | grep -qi "label.*not found\|no such label"; then
        log "Label not found, creating it..."

        set +e
        output=$(create_label)
        exit_code=$?
        set -e

        if [[ $exit_code -eq 0 ]]; then
            log "Label created, retrying application..."
        elif echo "$output" | grep -q "already exists\|422"; then
            # Race condition: another process created the label
            log "Label already exists (race condition), retrying application..."
        else
            log "Warning: failed to create label: $output"
            return 1
        fi

        # Retry label application
        set +e
        output=$(apply_label)
        exit_code=$?
        set -e

        if [[ $exit_code -eq 0 ]]; then
            log "Label applied successfully after creation"
            return 0
        else
            log "Warning: failed to apply label after creation: $output"
            return 1
        fi
    fi

    # Some other error occurred
    log "Warning: failed to apply label: $output"
    return 1
}

main
