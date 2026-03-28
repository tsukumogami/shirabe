#!/usr/bin/env bash
# retry.sh - Shared retry utility for transient failures
#
# Usage:
#   source "$(dirname "$0")/../scripts/lib/retry.sh"  # adjust path as needed
#   retry gh issue create --title "foo" --body "bar"
#   retry --max-attempts 5 --backoff-base 2 gh api repos/owner/repo/milestones
#
# Options (must come before the command):
#   --max-attempts N    Maximum number of attempts (default: 3)
#   --backoff-base S    Base delay in seconds for exponential backoff (default: 1)
#
# Behavior:
#   - Retries the command up to max-attempts times on failure
#   - Uses exponential backoff with jitter between retries
#   - Logs retry attempts to stderr
#   - Returns the exit code of the last attempt on exhaustion

# Guard against double-sourcing
if [[ -n "${_RETRY_SH_LOADED:-}" ]]; then
    return 0 2>/dev/null || true
fi
_RETRY_SH_LOADED=1

retry() {
    local max_attempts=3
    local backoff_base=1

    # Parse options
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --max-attempts)
                max_attempts="$2"
                shift 2
                ;;
            --backoff-base)
                backoff_base="$2"
                shift 2
                ;;
            --)
                shift
                break
                ;;
            -*)
                echo "retry: unknown option: $1" >&2
                return 1
                ;;
            *)
                break
                ;;
        esac
    done

    if [[ $# -eq 0 ]]; then
        echo "retry: no command specified" >&2
        return 1
    fi

    local attempt=1
    local exit_code

    while true; do
        # Run the command, capturing exit code
        # Use || true to prevent set -e from killing the caller
        "$@" && exit_code=0 || exit_code=$?

        if [[ $exit_code -eq 0 ]]; then
            return 0
        fi

        if [[ $attempt -ge $max_attempts ]]; then
            echo "retry: command failed after $max_attempts attempts: $*" >&2
            return $exit_code
        fi

        # Calculate delay with exponential backoff and jitter
        local delay
        delay=$(( backoff_base * (2 ** (attempt - 1)) ))
        # Add jitter: random value between 0 and delay
        local jitter
        jitter=$(( RANDOM % (delay + 1) ))
        local total_delay=$(( delay + jitter ))

        echo "retry: attempt $attempt/$max_attempts failed (exit $exit_code), retrying in ${total_delay}s..." >&2
        sleep "$total_delay"

        attempt=$(( attempt + 1 ))
    done
}
