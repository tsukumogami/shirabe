#!/usr/bin/env bash
# work-on: a plan-backed run whose plan_validation answers `exit`,
# ending at validation_exit. Together with the three routing scenarios, every
# plan_validation value is submitted.
#
# Run by scripts/check-koto-floor.sh, once against the checkout and once
# against the copy with every decider block stripped. The environment it
# expects is described at the top of the scenarios section in ../lib.sh.
set -uo pipefail
# shellcheck source=../lib.sh
. "$(cd "$(dirname "$0")/.." && pwd)/lib.sh"

S="wo-exit"
workon_plan_backed "$S" || exit 1
tick "$S" '{"verdict":"exit","rationale":"the outline item is too vague"}'
expect_final "$S" validation_exit || exit 1
