#!/usr/bin/env bash
# execute: main deleted a path the PLAN references, so the run stops at
# worktree_discipline_check; `intent-changing` ends at done_blocked through
# escalate_upstream_drift.
#
# Run by scripts/check-koto-floor.sh, once against the checkout and once
# against the copy with every decider block stripped. The environment it
# expects is described at the top of the scenarios section in ../lib.sh.
set -uo pipefail
# shellcheck source=../lib.sh
. "$(cd "$(dirname "$0")/.." && pwd)/lib.sh"

S="$EXECUTE_SESSION"
execute_start 'git rm -q src/a.go' 'refactor: drop a' || exit 1
expect_state worktree_discipline_check "deletion" || exit 1
# escalate_upstream_drift takes the rationale this tick carries and exits
# unconditionally, so the tick ends the run; the session log shows the path.
tick "$S" '{"impact":"intent-changing","rationale":"src/a.go is gone"}'
expect_state done_blocked "deletion" || exit 1
expect_visited "$S" escalate_upstream_drift || exit 1
expect_final "$S" done_blocked || exit 1
