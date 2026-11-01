#!/usr/bin/env bash
# check-handoff.sh -- check one skill's hand-off to another, with no model.
#
# Usage: scripts/check-handoff.sh <from> <to>
#
# <from> is the skill that hands off and <to> the skill that receives it: in
# `check-handoff.sh deliver execute`, /deliver opens a koto request and runs
# /execute on its `execute` leg; in `check-handoff.sh execute work-on`,
# /execute's spawn_and_await materializes work-on.md children; in
# `check-handoff.sh coordinate work-on`, /coordinate's wait_leg reads a
# templated leg (`leg: "{{WAIT_LEG}}"`) that dispatch-worker.sh opened from
# work-on's row in skills/coordinate/references/entry-points.tsv. The
# script-graded eval cases name it in their `run` field
# (scripts/lib/script-cases.py runs them), and anyone can run it directly.
#
# Four checks, each printing one PASS line when it holds or a FAIL line per
# problem, every line naming its check:
#
#   receiving-side contract  the target template's file name, outcome words
#                            and result keys against what the caller's leg
#                            gate expects and copies, per outcome
#                            (scripts/check-handoff.results.tsv declares the
#                            keys a target carries for an outcome by design),
#                            and --koto-leg in the target's SKILL.md; for a
#                            child hand-off, the child template reference
#                            resolving to the target's template
#   rendered directive       the state waiting on the target renders a
#                            directive naming skill <to> and
#                            --koto-leg=<req>:<leg> (for a child, the child
#                            template's file; for a templated leg, the gate
#                            reads a request and leg a state captures)
#   attach                   the real target template attached with
#                            `koto init --koto-leg` to a fresh request the
#                            caller's own opener created (for a child, opened
#                            with `koto init --parent` under the real caller;
#                            for a templated leg, a request in the shape
#                            dispatch-worker.sh opens from the row)
#   routes                   the caller's suites for the edge, from
#                            scripts/check-handoff.routes.tsv, run with
#                            HANDOFF_ROUTE=<to> so a suite that takes the
#                            selector runs only the sections on the
#                            hand-off to <to>; the others run whole
#
# scripts/lib/check-handoff.py runs the first three; its header has the
# details. The routes check fails on a suite that exits non-zero, prints a
# SKIP line, or reports no passing case, so a suite that skipped for want of
# a tool never passes the case.
#
# Every koto call, the suites' included, runs against a scratch koto store:
# scripts/lib/koto-test-guard.sh clears koto's store variables and sets a
# scratch HOME before anything starts, and the scratch directories are removed
# on exit. The caller's own koto sessions are never read or written.
#
# Exit codes:
#   0  every check held
#   1  a check failed, or koto (with --koto-leg) or python3 is missing
#   2  usage error
#
# Needs koto with `koto init --koto-leg`, python3, and what the route suites
# need (jq, git).
#
# bash 3.2 floor: no associative arrays, no mapfile, no ${var,,}.

set -u

usage() {
    echo "usage: check-handoff.sh <from> <to>" >&2
    exit 2
}

[ "$#" -eq 2 ] || usage
FROM=$1
TO=$2
for arg in "$FROM" "$TO"; do
    case "$arg" in
        ''|[!A-Za-z0-9]*|*[!A-Za-z0-9._-]*)
            echo "check-handoff: skill name [$arg] does not match [A-Za-z0-9][A-Za-z0-9._-]*" >&2
            exit 2 ;;
    esac
done

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd -P) || exit 2
REPO_ROOT=$(cd "$SCRIPT_DIR/.." && pwd -P) || exit 2
for arg in "$FROM" "$TO"; do
    [ -d "$REPO_ROOT/skills/$arg" ] || {
        echo "check-handoff: skills/$arg is not a directory" >&2
        exit 2
    }
done

# koto first: every check needs it, and a koto without --koto-leg can neither
# attach nor run the engine suites, which would otherwise SKIP.
if ! command -v koto >/dev/null; then
    echo "FAIL: handoff $FROM -> $TO: koto is not on PATH; every check needs it"
    exit 1
fi
if ! koto init --help 2>/dev/null | grep -q -- '--koto-leg'; then
    echo "FAIL: handoff $FROM -> $TO: this koto's init has no --koto-leg; the attach and the engine suites need a koto that has it"
    exit 1
fi
if ! command -v python3 >/dev/null; then
    echo "FAIL: handoff $FROM -> $TO: python3 is not on PATH"
    exit 1
fi

# shellcheck source=lib/koto-test-guard.sh
. "$REPO_ROOT/scripts/lib/koto-test-guard.sh" || exit 1

WORK=$(mktemp -d "${TMPDIR:-/tmp}/check-handoff.XXXXXX") || {
    echo "FAIL: handoff $FROM -> $TO: could not make a temporary directory"
    exit 1
}
ktg_on_exit 'rm -rf "$WORK"'

rc=0
python3 "$REPO_ROOT/scripts/lib/check-handoff.py" "$FROM" "$TO" "$WORK" || rc=1

# --- routes -----------------------------------------------------------------

# The caller's suites that walk its hand-off to <to>, from
# scripts/check-handoff.routes.tsv (from, to, suite; the suite relative to
# the repository). The engine and structure suites that take HANDOFF_ROUTE
# run only that route's sections under it; the others run whole.
ROUTES="$REPO_ROOT/scripts/check-handoff.routes.tsv"
ESC=$(printf '\033')
TAB=$(printf '\t')
routes_ok=1
SUITES=""
if [ -f "$ROUTES" ]; then
    SUITES=$(awk -F "$TAB" -v f="$FROM" -v t="$TO" \
        '$0 !~ /^#/ && NF == 3 && $1 == f && $2 == t { print $3 }' "$ROUTES")
fi
if [ ! -f "$ROUTES" ]; then
    echo "FAIL: handoff $FROM -> $TO: routes: scripts/check-handoff.routes.tsv does not exist"
    routes_ok=0
elif [ -z "$SUITES" ]; then
    echo "FAIL: handoff $FROM -> $TO: routes: no route suites are declared for this hand-off in scripts/check-handoff.routes.tsv (a row is three tab-separated fields: from, to, suite)"
    routes_ok=0
fi
for suite in $SUITES; do
    out="$WORK/suite.out"
    if [ ! -f "$REPO_ROOT/$suite" ]; then
        echo "FAIL: handoff $FROM -> $TO: routes: $suite does not exist"
        routes_ok=0
        continue
    fi
    src=0
    (cd "$REPO_ROOT" && HANDOFF_ROUTE="$TO" bash "$suite") >"$out" 2>&1 || src=$?
    # Colour codes off, so FAIL and SKIP lines read the same from every suite.
    sed "s/$ESC\[[0-9;]*m//g" "$out" >"$out.plain"
    counts=$(grep -E '[0-9]+ passed, [0-9]+ failed' "$out.plain" | tail -n 1 \
        | sed -E 's/^/ /; s/.*[^0-9]([0-9]+) passed, ([0-9]+) failed.*/\1 \2/')
    passed=${counts% *}
    failed=${counts#* }
    reason=""
    if [ "$src" -ne 0 ]; then
        reason="exited $src"
    elif grep -q '^SKIP' "$out.plain"; then
        reason="skipped: $(grep -m 1 '^SKIP' "$out.plain")"
    elif [ -z "$counts" ] || [ "${passed:-0}" -eq 0 ]; then
        reason="reported no passing case"
    elif [ "${failed:-0}" -ne 0 ]; then
        reason="reported $failed failed"
    fi
    if [ -n "$reason" ]; then
        echo "FAIL: handoff $FROM -> $TO: routes: $suite (HANDOFF_ROUTE=$TO) $reason:"
        # The suite's own failing lines, each with the detail line after it,
        # the first 40 only. sed reads to the end rather than stopping at
        # line 40, so no stage before it is cut off.
        grep -E -A 1 '^(FAIL|SKIP)' "$out.plain" | grep -v '^--$' | sed -n '1,40s/^/    /p'
        tail -n 1 "$out.plain" | sed 's/^/    /'
        routes_ok=0
    fi
done
if [ "$routes_ok" -eq 1 ]; then
    echo "PASS: handoff $FROM -> $TO: routes"
else
    rc=1
fi
exit "$rc"
