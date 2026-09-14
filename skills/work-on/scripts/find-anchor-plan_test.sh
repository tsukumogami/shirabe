#!/usr/bin/env bash
# find-anchor-plan_test.sh — each case targets a specific wrong implementation.
#
# The cases that matter most are the ones a plausible-looking implementation
# gets wrong: an unanchored match (12 finding 123), an empty issue number
# matching an empty cell, and uncertainty collapsing into "no anchor", which
# would skip an owed cascade silently.
#
# Usage: find-anchor-plan_test.sh
# Exit codes: 0 all pass, 1 any failed.

set -uo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
FIND="$SCRIPT_DIR/find-anchor-plan.sh"

PASS_COUNT=0
FAIL_COUNT=0
GREEN='\033[0;32m'; RED='\033[0;31m'; NC='\033[0m'
pass() { echo -e "${GREEN}PASS${NC}: $*"; PASS_COUNT=$((PASS_COUNT+1)); }
fail() { echo -e "${RED}FAIL${NC}: $*"; FAIL_COUNT=$((FAIL_COUNT+1)); }

TMPS=()
cleanup() { for d in "${TMPS[@]:-}"; do [[ -n "$d" ]] && rm -rf "$d"; done; }
trap cleanup EXIT

# expect <label> <expected-exit> <dir> <args...>
expect() {
    local label="$1" want="$2" dir="$3"; shift 3
    local got
    (cd "$dir" && bash "$FIND" "$@" >/dev/null 2>&1); got=$?
    if [[ "$got" == "$want" ]]; then pass "$label (exit $got)"
    else fail "$label: expected exit $want, got $got"; fi
}

row() { printf '| %s[#%s: %s](https://example.invalid/%s)%s | None | simple |\n' "$2" "$1" "t" "$1" "$3"; }

new_tree() {
    local d; d=$(mktemp -d); TMPS+=("$d"); mkdir -p "$d/docs/plans"; echo "$d"
}

# Case 1 — the basic hit.
T=$(new_tree); { echo "## Implementation Issues"; row 42 "" ""; } > "$T/docs/plans/PLAN-a.md"
expect "issue named in a PLAN's table is found" 0 "$T" 42

# Case 2 — THE ANCHORING CASE. A PLAN naming only #123 must not be found for #12.
# An unanchored `#${issue}` search passes Case 1 and fails this one.
T=$(new_tree); { echo "## Implementation Issues"; row 123 "" ""; } > "$T/docs/plans/PLAN-a.md"
expect "issue 12 does NOT match a row for issue 123" 1 "$T" 12

# Case 3 — the reverse: #1 must not match #12 either.
T=$(new_tree); { echo "## Implementation Issues"; row 12 "" ""; } > "$T/docs/plans/PLAN-a.md"
expect "issue 1 does NOT match a row for issue 12" 1 "$T" 1

# Case 4 — a done row, struck through, is still an anchor.
T=$(new_tree); { echo "## Implementation Issues"; row 7 "~~" "~~"; } > "$T/docs/plans/PLAN-a.md"
expect "struck-through row is still found" 0 "$T" 7

# Case 5 — a mention in prose is not a table row and must not anchor.
T=$(new_tree); printf '## Notes\nSee #42 for context.\n' > "$T/docs/plans/PLAN-a.md"
expect "prose mention of #42 is not an anchor" 1 "$T" 42

# Case 6 — EMPTY ISSUE NUMBER. Free-form mode has none. A naive pattern built
# from an empty value matches an empty cell and cascades whatever PLAN has one.
T=$(new_tree); printf '## Implementation Issues\n| [#: ](x) | None | simple |\n' > "$T/docs/plans/PLAN-a.md"
expect "empty issue number is confidently no anchor" 1 "$T" ""

# Case 7 — a non-numeric issue is an error, not an absence.
T=$(new_tree)
expect "non-numeric issue number cannot be decided" 2 "$T" "12;rm"

# Case 8 — AMBIGUITY. Two PLANs naming one issue must stop, not pick by file
# order and not skip. Collapsing this to exit 1 would hide a corpus defect and
# silently skip a cascade that was owed.
T=$(new_tree)
{ echo "## Implementation Issues"; row 9 "" ""; } > "$T/docs/plans/PLAN-a.md"
{ echo "## Implementation Issues"; row 9 "" ""; } > "$T/docs/plans/PLAN-b.md"
expect "two PLANs naming one issue cannot be decided" 2 "$T" 9

# Case 9 — a repository with no plans directory has confidently no anchor.
T=$(mktemp -d); TMPS+=("$T")
expect "no docs/plans directory is confidently no anchor" 1 "$T" 42

# Case 10 — a caller-supplied PLAN short-circuits the search.
T=$(new_tree); echo "# plan" > "$T/docs/plans/PLAN-given.md"
expect "caller-supplied PLAN that exists is used" 0 "$T" 99 "docs/plans/PLAN-given.md"

# Case 11 — a caller-supplied PLAN that does not exist is an error, not absence.
T=$(new_tree)
expect "caller-supplied PLAN that is missing cannot be decided" 2 "$T" 99 "docs/plans/PLAN-missing.md"

# Case 12 — the found path is what gets printed, so cascade_run can use it.
T=$(new_tree); { echo "## Implementation Issues"; row 5 "" ""; } > "$T/docs/plans/PLAN-x.md"
out=$(cd "$T" && bash "$FIND" 5 2>/dev/null)
if [[ "$out" == "docs/plans/PLAN-x.md" ]]; then pass "prints the anchor's path"
else fail "should print docs/plans/PLAN-x.md, got: $out"; fi

echo
echo "find-anchor-plan_test.sh: $PASS_COUNT passed, $FAIL_COUNT failed"
[[ "$FAIL_COUNT" -eq 0 ]]
