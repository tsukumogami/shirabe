#!/usr/bin/env bash
# work-on: a free-form run through research. research submits no
# context_gathered: it takes no evidence at all, and the tick passes through
# it to post_research_validation.
#
# Run by scripts/check-koto-floor.sh, once against the checkout and once
# against the copy with every decider block stripped. The environment it
# expects is described at the top of the scenarios section in ../lib.sh.
set -uo pipefail
# shellcheck source=../lib.sh
. "$(cd "$(dirname "$0")/.." && pwd)/lib.sh"

S="wo-free"
fixture_repo "impl/$S" || exit 1
koto_init "$S" "$TREE/$WORKON_TEMPLATE_REL" \
    --var ARTIFACT_PREFIX="task_$S" --var PLUGIN_ROOT="$TREE" || exit 1
tick "$S"
expect_state entry "free-form" || exit 1
tick "$S" '{"mode":"free_form","task_description":"change a"}'
expect_state task_validation "free-form" || exit 1
tick "$S" '{"verdict":"proceed"}'
expect_visited "$S" research || exit 1
expect_state post_research_validation "free-form" || exit 1
expect_final "$S" post_research_validation || exit 1
