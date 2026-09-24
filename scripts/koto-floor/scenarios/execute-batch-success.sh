#!/usr/bin/env bash
# execute: a batch whose children all succeed. The spawn_and_await gate
# routes it to pr_finalization with no evidence beyond the task list.
#
# Run by scripts/check-koto-floor.sh, once against the checkout and once
# against the copy with every decider block stripped. The environment it
# expects is described at the top of the scenarios section in ../lib.sh.
set -uo pipefail
# shellcheck source=../lib.sh
. "$(cd "$(dirname "$0")/.." && pwd)/lib.sh"

S="$EXECUTE_SESSION"
execute_start 'printf more >> README.md' 'docs: touch the readme' || exit 1
expect_state spawn_and_await "batch success" || exit 1
tick "$S" "{\"tasks\":[$(child_task issue-1 child-success.md),$(child_task issue-2 child-success.md)]}"
expect_state spawn_and_await "batch success: tasks submitted" || exit 1
tick "$S.issue-1"
expect_state done "batch success: issue-1" || exit 1
tick "$S.issue-2"
expect_state done "batch success: issue-2" || exit 1
tick "$S"
expect_state pr_finalization "batch success" || exit 1
expect_final "$S" pr_finalization || exit 1
