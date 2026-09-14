#!/usr/bin/env bash
# find-anchor-plan.sh — does this issue have a PLAN behind it?
#
# The "anchor" is the PLAN that sequences an issue: the only document the
# completion cascade can be entered from, since run-cascade.sh takes a
# plan-shaped path as its sole argument. cascade_entry calls this to decide
# whether the run cascades at all.
#
# Usage: find-anchor-plan.sh <issue-number> [<plan-doc>]
#
# Exit codes, and why there are three rather than two:
#   0 — exactly one anchor found; its path is printed on stdout.
#   1 — confidently NO anchor. The run skips the cascade silently (PRD R3).
#   2 — could not decide. The run must stop and say so, never skip.
#
# The split between 1 and 2 is the whole point. Exit 1 routes past the cascade
# with no output, so it must only ever mean "there is genuinely nothing to
# cascade". If an unreadable tree or an ambiguous match returned 1, a cascade
# that was owed would be skipped without anyone being told — the exact silent
# omission this feature exists to remove. Uncertainty therefore returns 2.
#
# The search is anchored, and the anchoring is load-bearing. The canonical
# issues-table row is `| [#N: <title>](<url>) |` (references/issues-table.md),
# optionally struck through as `| ~~[#N: ...` once done. Matching on the colon
# that follows the number is what stops issue 12 matching a row for issue 123.
# An unanchored `#${issue}` — the form extract-context.sh's find_design_doc
# uses — would do exactly that, and here it would cascade the wrong document
# chain. Nothing mechanical enforces this anchoring; keep it when editing.

set -uo pipefail

ISSUE="${1:-}"
PLAN_DOC="${2:-}"

# No issue number means free-form mode: nothing can sequence the work, so there
# is confidently no anchor. The number must be all digits, because an empty or
# non-numeric value would otherwise turn the pattern below into one that matches
# an empty cell — and cascade whichever PLAN happens to have one.
if [[ -z "$ISSUE" ]]; then
    exit 1
fi
if [[ ! "$ISSUE" =~ ^[0-9]+$ ]]; then
    echo "find-anchor-plan: issue number is not numeric: $ISSUE" >&2
    exit 2
fi

# A caller who already knows the PLAN short-circuits the search. A named PLAN
# that does not exist is a caller error, not an absence, so it is exit 2.
if [[ -n "$PLAN_DOC" ]]; then
    if [[ -f "$PLAN_DOC" ]]; then
        echo "$PLAN_DOC"
        exit 0
    fi
    echo "find-anchor-plan: caller-supplied PLAN not found: $PLAN_DOC" >&2
    exit 2
fi

if [[ ! -d docs/plans ]]; then
    # A repository with no plans directory has no PLANs at all. That is a
    # confident absence, not an error.
    exit 1
fi
if [[ ! -r docs/plans ]]; then
    echo "find-anchor-plan: docs/plans exists but is not readable" >&2
    exit 2
fi

PATTERN="^\\|[[:space:]]*(~~)?\\[#${ISSUE}:"

MATCHES=()
while IFS= read -r f; do
    [[ -n "$f" ]] && MATCHES+=("$f")
done < <(grep -lE "$PATTERN" docs/plans/*.md 2>/dev/null)

case "${#MATCHES[@]}" in
    0)
        exit 1
        ;;
    1)
        echo "${MATCHES[0]}"
        exit 0
        ;;
    *)
        # Two PLANs claiming one issue is a corpus defect. Picking one would
        # cascade a chain chosen by file order; skipping would hide it.
        echo "find-anchor-plan: issue #${ISSUE} is named by more than one PLAN:" >&2
        printf '  %s\n' "${MATCHES[@]}" >&2
        exit 2
        ;;
esac
