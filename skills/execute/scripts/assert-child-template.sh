#!/usr/bin/env bash
# assert-child-template.sh — for /execute: assert the cross-skill /work-on
# per-issue child template resolves before any child is spawned.
#
# /execute owns plan-level execution but delegates each single issue to /work-on's
# single-issue engine (work-on.md). The lifted execute koto template references
# that child template relatively (../../work-on/koto-templates/work-on.md); in a
# canonical plugin install that resolves to:
#   ${CLAUDE_PLUGIN_ROOT}/skills/work-on/koto-templates/work-on.md
# A missing or misresolved path is otherwise a silent failure at child-spawn time
# (the load-bearing cross-skill coupling). This assertion makes it loud and early.
#
# Fail-closed by design: a missing child template exits 1 and halts the run. The
# success path is silent — nothing is printed when the template resolves.
set -euo pipefail

# Resolve the plugin root. Prefer $CLAUDE_PLUGIN_ROOT when the loader exported it,
# but fall back to the script's own location so the check works from a plain
# shell (e.g. an agent running it directly) where the env var may be unset. This
# script lives at skills/execute/scripts/, so ../../.. is the plugin root. The
# real assertion remains the child-template existence check below.
ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)}"
CHILD="$ROOT/skills/work-on/koto-templates/work-on.md"

if [[ ! -f "$CHILD" ]]; then
  echo "execute assert-child-template FAILED: cross-skill child template not found at: $CHILD" >&2
  echo "  /execute delegates each issue to /work-on's work-on.md; this path must resolve before spawning children." >&2
  exit 1
fi

# The completion cascade is the second cross-skill path /execute depends on.
# It lives under /work-on because the single-issue skill runs the same cascade
# for a standalone issue, and /work-on is the component /execute already depends
# on. Checked here, at the same early point, for the same reason as the child
# template: without it a misresolved path surfaces deep inside plan_completion,
# after the cascade has begun transitioning documents, instead of before any
# child is spawned.
CASCADE="$ROOT/skills/work-on/scripts/run-cascade.sh"

if [[ ! -f "$CASCADE" ]]; then
  echo "execute assert-child-template FAILED: cross-skill cascade script not found at: $CASCADE" >&2
  echo "  plan_completion runs /work-on's run-cascade.sh; this path must resolve before any document is transitioned." >&2
  exit 1
fi
