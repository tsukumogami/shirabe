#!/usr/bin/env bash
# the decider fixture: a question whose field declares a decider block
# with an escape value. On the floor the block is dropped, so the run routes
# exactly as the stripped copy does and never offers the escape value.
#
# Run by scripts/check-koto-floor.sh, once against the checkout and once
# against the copy with every decider block stripped. The environment it
# expects is described at the top of the scenarios section in ../lib.sh.
set -uo pipefail
# shellcheck source=../lib.sh
. "$(cd "$(dirname "$0")/.." && pwd)/lib.sh"

S="decider"
fixture_repo "impl/$S" || exit 1
koto_init "$S" "$TREE/scripts/koto-floor/fixtures/decider.md" || exit 1
tick "$S"
expect_state question "decider fixture" || exit 1
tick "$S" '{"verdict":"proceed"}'
expect_final "$S" done || exit 1
