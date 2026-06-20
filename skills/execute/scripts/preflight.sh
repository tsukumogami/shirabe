#!/usr/bin/env bash
# Preflight for /execute: assert the cross-skill /work-on per-issue child template
# resolves before any child is spawned.
#
# /execute owns plan-level execution but delegates each single issue to /work-on's
# single-issue engine (work-on.md). The lifted execute koto template references
# that child template relatively (../../work-on/koto-templates/work-on.md); in a
# canonical plugin install that resolves to:
#   ${CLAUDE_PLUGIN_ROOT}/skills/work-on/koto-templates/work-on.md
# A missing or misresolved path is otherwise a silent failure at child-spawn time
# (the load-bearing cross-skill coupling). This preflight makes it loud and early.
set -euo pipefail

ROOT="${CLAUDE_PLUGIN_ROOT:?CLAUDE_PLUGIN_ROOT is not set; /execute cannot resolve the cross-skill child template}"
CHILD="$ROOT/skills/work-on/koto-templates/work-on.md"

if [[ ! -f "$CHILD" ]]; then
  echo "execute preflight FAILED: cross-skill child template not found at: $CHILD" >&2
  echo "  /execute delegates each issue to /work-on's work-on.md; this path must resolve before spawning children." >&2
  exit 1
fi

echo "execute preflight OK: cross-skill child template resolves at: $CHILD"
