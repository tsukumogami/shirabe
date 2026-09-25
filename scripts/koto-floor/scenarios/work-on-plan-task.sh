#!/usr/bin/env bash
# work-on: a plan-backed run. plan_validation answers `proceed`,
# implementation answers `complete`, changed_paths_record records, and
# issue_type_routing answers `task`, which goes to verification.
#
# Run by scripts/check-koto-floor.sh, once against the checkout and once
# against the copy with every decider block stripped. The environment it
# expects is described at the top of the scenarios section in ../lib.sh.
set -uo pipefail
# shellcheck source=../lib.sh
. "$(cd "$(dirname "$0")/.." && pwd)/lib.sh"

S="wo-task"
workon_plan_backed "$S" || exit 1
workon_to_routing "$S" no || exit 1
tick "$S" '{"issue_type":"task"}'
expect_state verification "task route" || exit 1
expect_final "$S" verification || exit 1
