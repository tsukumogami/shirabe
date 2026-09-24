#!/usr/bin/env bash
# execute: a batch with one failing child. The spawn_and_await gate
# routes it to escalate, which ends at done_blocked.
#
# Run by scripts/check-koto-floor.sh, once against the checkout and once
# against the copy with every decider block stripped. The environment it
# expects is described at the top of the scenarios section in ../lib.sh.
set -uo pipefail
# shellcheck source=../lib.sh
. "$(cd "$(dirname "$0")/.." && pwd)/lib.sh"

S="$EXECUTE_SESSION"
execute_start 'printf more >> README.md' 'docs: touch the readme' || exit 1
expect_state spawn_and_await "batch failure" || exit 1
tick "$S" "{\"tasks\":[$(child_task issue-1 child-success.md),$(child_task issue-2 child-failure.md)]}"
expect_state spawn_and_await "batch failure: tasks submitted" || exit 1
tick "$S.issue-1"
expect_state done "batch failure: issue-1" || exit 1
tick "$S.issue-2"
expect_state failed "batch failure: issue-2" || exit 1
# One tick ends the run. escalate declares evidence but exits unconditionally,
# so the tick that routes the batch there chains on to done_blocked; the
# session log is what shows it went through escalate.
tick "$S"
expect_state done_blocked "batch failure" || exit 1
expect_visited "$S" escalate || exit 1
expect_final "$S" done_blocked || exit 1
