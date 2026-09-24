#!/usr/bin/env bash
# execute: no drift. main moved only where the PLAN does not look, so
# the run reaches spawn_and_await from settled_branch_record in one tick,
# without stopping at worktree_discipline_check.
#
# Run by scripts/check-koto-floor.sh, once against the checkout and once
# against the copy with every decider block stripped. The environment it
# expects is described at the top of the scenarios section in ../lib.sh.
set -uo pipefail
# shellcheck source=../lib.sh
. "$(cd "$(dirname "$0")/.." && pwd)/lib.sh"

S="$EXECUTE_SESSION"
execute_start 'printf more >> README.md' 'docs: touch the readme' || exit 1
expect_state spawn_and_await "no drift" || exit 1
expect_final "$S" spawn_and_await || exit 1
