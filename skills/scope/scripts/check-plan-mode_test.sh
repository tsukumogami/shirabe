#!/usr/bin/env bash
# check-plan-mode_test.sh -- the plan_mode_consistent gate's script: a match,
# each way a hop can drop or invent a flag, the no-split case, and the
# no-intent short-circuit.
#
# Usage: bash skills/scope/scripts/check-plan-mode_test.sh
# Exit 0 when every case holds. Needs bash and git; runs on the 3.2 floor.
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
S="$HERE/check-plan-mode.sh"
T="$(mktemp -d "${TMPDIR:-/tmp}/check-plan-mode-test.XXXXXX")"
trap 'rm -rf "$T"' EXIT
export GIT_CEILING_DIRECTORIES="$T"

PASS=0
FAIL=0

R="$T/repo"
mkdir -p "$R/docs/plans"
git -C "$R" init -q 2>/dev/null

# plan <name> <execution_mode> <split_mode_source> -- a PLAN with that record.
# An empty mode or source leaves the field out.
plan() {
    local f="$R/docs/plans/PLAN-$1.md"
    {
        printf -- '---\nschema: plan/v1\nstatus: Active\n'
        [ -n "$2" ] && printf 'execution_mode: %s\n' "$2"
        [ -n "$3" ] && printf 'split_mode_source: %s   # from the decomposition artifact\n' "$3"
        printf 'split_rationale: |\n  Hard Constraint. execution_mode: single-pr is quoted here and is not the field.\n'
        printf 'upstream: docs/designs/DESIGN-x.md\n---\n\n# PLAN\n\nexecution_mode: coordinated\n'
    } >"$f"
    printf 'docs/plans/PLAN-%s.md' "$1"
}

expect() { # expect <label> <want-exit> <args...>
    local label="$1" want="$2" rc
    shift 2
    (cd "$R" && bash "$S" "$@" >/dev/null 2>"$T/err"); rc=$?
    if [ "$rc" = "$want" ]; then
        PASS=$((PASS + 1)); printf 'ok   %s\n' "$label"
    else
        FAIL=$((FAIL + 1)); printf 'FAIL %s\n     want exit=%s, got %s: %s\n' "$label" "$want" "$rc" "$(cat "$T/err")"
    fi
}

SINGLE=$(plan single single-pr none)
SINGLE_BAD=$(plan single-bad single-pr intent)
COORD_INTENT=$(plan coord-intent coordinated intent)
MULTI_INTENT=$(plan multi-intent multi-pr intent)
MULTI_DEFAULT=$(plan multi-default multi-pr default)
MULTI_FLAG=$(plan multi-flag multi-pr flag)
COORD_FLAG=$(plan coord-flag coordinated flag)
COORD_HEADER=$(plan coord-header coordinated header)
NO_SOURCE=$(plan no-source multi-pr "")
NO_MODE=$(plan no-mode "" intent)
ODD_MODE=$(plan odd-mode sequential intent)

echo "== the no-intent short-circuit =="
expect "intent none exits 0 without reading the PLAN"        0 --plan docs/plans/PLAN-absent.md --intent none --coordination none
expect "intent none exits 0 even when the PLAN disagrees"    0 --plan "$SINGLE_BAD" --intent none --coordination coordinated

echo "== the no-split case =="
expect "no split: single-pr / none under continue"           0 --plan "$SINGLE" --intent continue --coordination none
expect "no split: single-pr / none under stop with a flag"   0 --plan "$SINGLE" --intent stop --coordination coordinated
expect "no split recorded with a split source is a mismatch" 1 --plan "$SINGLE_BAD" --intent continue --coordination none

echo "== matches =="
expect "continue resolves a split to coordinated / intent"   0 --plan "$COORD_INTENT" --intent continue --coordination none
expect "stop resolves a split to multi-pr / intent"          0 --plan "$MULTI_INTENT" --intent stop --coordination none
expect "--no-coordinated outranks continue: multi-pr / flag" 0 --plan "$MULTI_FLAG" --intent continue --coordination no-coordinated
expect "--coordinated outranks stop: coordinated / flag"     0 --plan "$COORD_FLAG" --intent stop --coordination coordinated

echo "== each mismatch =="
expect "dropped --intent=continue (PLAN resolved by default)" 1 --plan "$MULTI_DEFAULT" --intent continue --coordination none
expect "dropped --intent=stop (PLAN resolved by default)"     1 --plan "$MULTI_DEFAULT" --intent stop --coordination none
expect "invented continue under stop"                         1 --plan "$COORD_INTENT" --intent stop --coordination none
expect "dropped --no-coordinated (intent decided instead)"    1 --plan "$COORD_INTENT" --intent continue --coordination no-coordinated
expect "dropped --coordinated (intent decided instead)"       1 --plan "$MULTI_INTENT" --intent stop --coordination coordinated
expect "invented --no-coordinated"                            1 --plan "$MULTI_FLAG" --intent stop --coordination none
expect "invented --coordinated"                               1 --plan "$COORD_FLAG" --intent continue --coordination none
expect "a header-derived mode where intent should decide"     1 --plan "$COORD_HEADER" --intent continue --coordination none
expect "a PLAN with no split_mode_source"                     1 --plan "$NO_SOURCE" --intent stop --coordination none
expect "a PLAN with no execution_mode"                        1 --plan "$NO_MODE" --intent stop --coordination none
expect "a PLAN with an unknown execution_mode"                1 --plan "$ODD_MODE" --intent stop --coordination none

echo "== the CLAUDE.md headers are read =="
printf '# repo\n\n## PR Grouping Policy: coordinated\n' >"$R/CLAUDE.md"
expect "a repository CLAUDE.md is picked up and intent still outranks it" 0 --plan "$MULTI_INTENT" --intent stop --coordination none
expect "an explicit --claude-md is passed through"                        0 --plan "$COORD_INTENT" --intent continue --coordination none --claude-md "$R/CLAUDE.md"
rm -f "$R/CLAUDE.md"

echo "== cannot tell (exit 2) =="
expect "a PLAN that does not exist"            2 --plan docs/plans/PLAN-absent.md --intent continue --coordination none
expect "an intent outside continue|stop|none"  2 --plan "$SINGLE" --intent maybe --coordination none
expect "a coordination value outside the set"  2 --plan "$SINGLE" --intent stop --coordination both
expect "a --claude-md that does not exist"     2 --plan "$COORD_INTENT" --intent continue --coordination none --claude-md "$T/nope.md"
expect "a missing --coordination"              2 --plan "$SINGLE" --intent stop
expect "an unknown argument"                   2 --plan "$SINGLE" --intent stop --coordination none --x y

if grep -v '^[[:space:]]*#' "$S" | grep -q 'wip/scope_'; then
    FAIL=$((FAIL + 1)); echo "FAIL the gate script reads the run's own state file"
else
    PASS=$((PASS + 1)); echo "ok   the gate script never reads the run's own state file"
fi

echo
echo "passed: $PASS   failed: $FAIL"
[ "$FAIL" -eq 0 ]
