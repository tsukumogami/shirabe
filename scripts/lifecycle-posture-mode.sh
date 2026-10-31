#!/usr/bin/env bash
#
# lifecycle-posture-mode.sh - resolve lifecycle.yml's posture input to a mode flag
#
# Reads two values from the environment and prints the mode flag the lifecycle
# step passes to `shirabe validate --lifecycle .`:
#
#   POSTURE   the workflow's `posture` input: `auto` or `draft`
#   PR_DRAFT  the pull request's draft state: `true` or `false`
#
#   POSTURE=auto,  PR_DRAFT=false  ->  --mode=ready
#   POSTURE=auto,  anything else   ->  (empty: the binary's draft posture)
#   POSTURE=draft, any PR_DRAFT    ->  (empty: draft posture, never ready)
#
# `auto` keeps the workflow's long-standing behavior: ready posture on a ready
# pull request, draft posture otherwise (a non-PR trigger has no draft state and
# lands on draft, as before). `draft` holds the check at draft posture on every
# pull request, for a repository whose default branch holds open plans that no
# single pull request can finish.
#
# A workflow_call string input has no choice type, so the `case` below is the
# input's only allowlist. Any other value fails with an error naming the two
# accepted values; the rejected value is never echoed, since it comes from the
# caller's workflow file.
#
# Both values arrive through `env:`, never interpolated into a `run:` script.
#
# Usage:
#   POSTURE=<auto|draft> PR_DRAFT=<true|false> lifecycle-posture-mode.sh
#
# Exit codes:
#   0 - the mode flag printed on stdout (possibly empty)
#   1 - POSTURE is not an accepted value

set -euo pipefail

case "${POSTURE-}" in
    auto)
        if [ "${PR_DRAFT-}" = "false" ]; then
            printf '%s\n' "--mode=ready"
        else
            printf '\n'
        fi
        ;;
    draft)
        printf '\n'
        ;;
    *)
        echo "::error::lifecycle.yml: the posture input must be 'auto' or 'draft'"
        exit 1
        ;;
esac
