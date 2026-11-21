#!/usr/bin/env bash
# draft-probe.sh -- does the shirabe on PATH accept a design at status Draft?
#
# /design writes its Phase 0 skeleton at status Draft and commits it, so a
# validator that refuses Draft (any release before v0.47.0) would refuse that
# commit under a validating pre-commit hook. SKILL.md runs this script once,
# right after the session opens and before any branch setup, resume row or
# Phase 0 step writes or commits anything, so such a run stops with nothing
# to clean up.
#
# The probe document is a minimal Draft design: schema, status and problem,
# no upstream (an upstream that isn't on disk would draw R6), the body
# Status, and the nine required sections, the six a Phase 0 skeleton leaves
# unreached holding the stub marker that
# skills/design/references/design-format.md defines. It's written to a
# private temporary directory that's removed on exit, so nothing lands in the
# caller's work tree.
#
# Usage: draft-probe.sh
# Exit codes:
#   0  the validator accepts a Draft design; prints "draft-probe: ok"
#   1  no shirabe on PATH, or it refuses a Draft design; names the release
#      /design needs on stderr
#   2  the probe couldn't run (no temporary directory, or the validator
#      exited with something other than a verdict)

set -u

NEED=v0.47.0

if ! command -v shirabe >/dev/null 2>&1; then
    echo "design: no shirabe on PATH. /design needs shirabe $NEED or later; install it and run /design again." >&2
    exit 1
fi

d=$(mktemp -d "${TMPDIR:-/tmp}/design-draft-probe.XXXXXX") || exit 2
trap 'rm -rf "$d"' EXIT

doc="$d/DESIGN-draft-probe.md"
cat > "$doc" <<'EOF' || exit 2
---
schema: design/v1
status: Draft
problem: |
  The probe checks that the validator accepts a design at status Draft.
---

# DESIGN: Draft probe

## Status

Draft

## Context and Problem Statement

The probe checks that the validator accepts a design at status Draft.

## Decision Drivers

The validator on PATH must accept the skeleton /design commits at Phase 0.

## Considered Options

Not written yet: a later /design phase replaces this line.

## Decision Outcome

Not written yet: a later /design phase replaces this line.

## Solution Architecture

Not written yet: a later /design phase replaces this line.

## Implementation Approach

Not written yet: a later /design phase replaces this line.

## Security Considerations

Not written yet: a later /design phase replaces this line.

## Consequences

Not written yet: a later /design phase replaces this line.
EOF

out=$(shirabe validate "$doc" 2>&1)
rc=$?
case "$rc" in
    0)
        echo "draft-probe: ok"
        exit 0
        ;;
    2)
        echo "design: the shirabe on PATH refuses a design at status Draft. /design needs shirabe $NEED or later; install it and run /design again." >&2
        printf '%s\n' "$out" >&2
        exit 1
        ;;
    *)
        echo "design: could not run the probe: shirabe validate exited $rc on a minimal Draft design" >&2
        printf '%s\n' "$out" >&2
        exit 2
        ;;
esac
