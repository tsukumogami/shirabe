#!/usr/bin/env bash
# execute: main changed a path the PLAN references, so the run stops at
# worktree_discipline_check; `informational` goes on to spawn_and_await.
#
# Run by scripts/check-koto-floor.sh, once against the checkout and once
# against the copy with every decider block stripped. The environment it
# expects is described at the top of the scenarios section in ../lib.sh.
set -uo pipefail
# shellcheck source=../lib.sh
. "$(cd "$(dirname "$0")/.." && pwd)/lib.sh"

S="$EXECUTE_SESSION"
execute_start 'printf a3 >> src/a.go' 'feat: touch a' || exit 1
expect_state worktree_discipline_check "overlap" || exit 1
tick "$S" '{"impact":"informational"}'
expect_state spawn_and_await "overlap" || exit 1
expect_final "$S" spawn_and_await || exit 1
