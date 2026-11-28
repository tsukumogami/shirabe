#!/usr/bin/env bash
#
# skill-gate.sh - the pull request gate: run the deterministic checks on each
# skill a change touches, and every script case when a shared path changes
#
# The skill-gate and skill-gate-suites jobs of
# .github/workflows/check-skill-gate.yml run this on Linux with `bash` and on
# macOS as the `skill-gate` floor suite, so it takes no arguments and reads
# its base, and the part of the gate the job makes (SKILL_GATE_PART, below),
# from the environment. It takes the paths
# that changed between SKILL_GATE_BASE and HEAD
# (`git diff --name-only --no-renames`) and runs:
#
#   - `scripts/check-skill.sh <skill>`, in full or in the job's part, once for each skills/<skill>/
#     directory a changed path falls under and that still exists at HEAD, in
#     name order. A deleted skill selects nothing, since nothing is left to
#     check; a renamed one selects its new name only. A path under a skill's
#     own scripts/ selects that skill and is not a shared path;
#   - `python3 scripts/lib/script-cases.py --all` once, last, when a changed
#     path is under scripts/, references/ or koto-templates/ at the root,
#     since any skill's cases can depend on those. The suites part leaves
#     this out.
#
# Both are the checked tree's own copies. Every selected check runs even after
# one fails, and the run ends with the list of those that failed, each with
# its exit code when that code is not 1.
#
# With SKILL_GATE_BASE unset or empty (the daily macos-floor.yml run, which
# has no pull request to compare against) it runs `script-cases.py --all`
# only. Otherwise SKILL_GATE_BASE must be a 40-character lower-case hex id of
# a commit in this repository; anything else is refused before anything runs.
#
# Usage: scripts/skill-gate.sh [--list]
#   --list   print the checks the run would make, one per line in run order
#            (`check-skill <skill>` or `script-cases --all`), and run nothing
#
# Environment:
#   SKILL_GATE_BASE   the commit to compare HEAD against: on a pull request,
#                     the first parent of the merge commit the checkout is
#                     (the base-branch commit it merges into); on a push to
#                     main, the commit before the push
#   SKILL_GATE_PART   the half of the gate this job makes, for the workflow's
#                     two jobs: `suites` runs only each selected skill's
#                     script suites (check-skill.sh's step 4) and drops
#                     `script-cases --all`; `checks` runs everything else,
#                     `script-cases --all` included. Unset or empty runs both.
#                     It stays in the environment, so each check-skill.sh
#                     makes the same part. Any other value is refused (exit 2)
#                     before anything runs. SUITE_SLICE and SUITE_SLICE_COSTS
#                     reach check-skill.sh the same way, which slices its
#                     suites with them.
#
# Exit codes:
#   0 - every selected check passed, or nothing was selected
#   1 - one or more checks failed
#   2 - usage error, a refused SKILL_GATE_BASE or SKILL_GATE_PART, or git
#       could not list the changes, or the run's temporary directory was
#       lost mid-run ("is gone or unreadable"), so the selection is unknown
#
# bash 3.2 floor: no associative arrays, no mapfile.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

usage() {
    echo "usage: scripts/skill-gate.sh [--list]" >&2
}

LIST=0
case $# in
    0) ;;
    1)
        if [ "$1" = "--list" ]; then
            LIST=1
        else
            usage
            exit 2
        fi
        ;;
    *)
        usage
        exit 2
        ;;
esac

case "${SKILL_GATE_PART:-}" in
    ""|suites|checks) ;;
    *)
        echo "skill-gate: SKILL_GATE_PART must be suites or checks (or unset)" >&2
        exit 2
        ;;
esac
# Every script case is the checks part's, never the suites part's.
CASES_ALL=1
[ "${SKILL_GATE_PART:-}" = suites ] && CASES_ALL=0

cd "$REPO_ROOT" || exit 2

BASE="${SKILL_GATE_BASE:-}"

# The plan: one check per line, `check-skill <skill>` or `script-cases --all`.
PLAN=""

if [ -z "$BASE" ]; then
    echo "skill-gate: no base commit; running every skill's script cases" >&2
    [ "$CASES_ALL" -eq 1 ] && PLAN="script-cases --all"
else
    # A fixed shape before git sees it, so the value can never reach git as an
    # option or a revision expression.
    case "$BASE" in
        *[!0123456789abcdef]*) BASE_OK=0 ;;
        *) BASE_OK=1 ;;
    esac
    if [ "$BASE_OK" -ne 1 ] || [ "${#BASE}" -ne 40 ]; then
        echo "skill-gate: SKILL_GATE_BASE must be a 40-character lower-case hex commit id" >&2
        exit 2
    fi
    if ! git cat-file -e "$BASE^{commit}" 2>/dev/null; then
        echo "skill-gate: SKILL_GATE_BASE $BASE is not a commit in this repository" >&2
        exit 2
    fi

    T=$(mktemp -d "${TMPDIR:-/tmp}/skill-gate.XXXXXX") || exit 2
    trap 'rm -rf "$T"' EXIT

    scratch_lost() {
        echo "skill-gate: temporary directory $T is gone or unreadable: cannot $1" >&2
        exit 2
    }
    need_scratch() {
        [ -r "$T/$1" ] || scratch_lost "read back $1"
    }

    if ! git diff --name-only --no-renames -z "$BASE" HEAD >"$T/changed" 2>"$T/diff.err"; then
        echo "skill-gate: git diff $BASE HEAD failed: $(cat "$T/diff.err")" >&2
        exit 2
    fi

    # The working files live under $T, so a directory lost mid-run must end
    # the run: an unreadable change list would otherwise read as no changes
    # and print "nothing to check" (shirabe#2229).
    need_scratch changed
    : >"$T/skills" || scratch_lost "write skills"
    SHARED=0
    while IFS= read -r -d '' path; do
        case "$path" in
            skills/*/*)
                name=${path#skills/}
                name=${name%%/*}
                # Only a directory that HEAD still has is a skill to check.
                if [ "$(git cat-file -t "HEAD:skills/$name" 2>/dev/null)" = "tree" ]; then
                    printf '%s\n' "$name" >>"$T/skills" || scratch_lost "write skills"
                fi
                ;;
            scripts/*|references/*|koto-templates/*)
                SHARED=1
                ;;
        esac
    done <"$T/changed"

    need_scratch skills
    LC_ALL=C sort -u "$T/skills" >"$T/selected" || scratch_lost "write selected"
    need_scratch selected
    while IFS= read -r name; do
        PLAN="${PLAN}check-skill $name
"
    done <"$T/selected"
    if [ "$SHARED" -eq 1 ] && [ "$CASES_ALL" -eq 1 ]; then
        PLAN="${PLAN}script-cases --all"
    fi
fi

# Drop a trailing newline so the plan is one check per line and nothing else.
PLAN=$(printf '%s' "$PLAN")

if [ "$LIST" -eq 1 ]; then
    [ -n "$PLAN" ] && printf '%s\n' "$PLAN"
    exit 0
fi

if [ -z "$PLAN" ]; then
    echo "skill-gate: nothing to check"
    exit 0
fi

TOTAL=0
PASSED=0
FAILED=""
# The plan is read on fd 3, so a check that reads stdin can't swallow the rest.
while IFS= read -r check <&3; do
    [ -n "$check" ] || continue
    TOTAL=$((TOTAL + 1))
    echo "== $check"
    case "$check" in
        "check-skill "*)
            bash scripts/check-skill.sh "${check#check-skill }" </dev/null
            rc=$?
            ;;
        *)
            python3 scripts/lib/script-cases.py --all </dev/null
            rc=$?
            ;;
    esac
    if [ "$rc" -eq 0 ]; then
        PASSED=$((PASSED + 1))
    else
        if [ "$rc" -eq 1 ]; then
            entry="$check"
        else
            entry="$check (exit $rc)"
        fi
        if [ -n "$FAILED" ]; then
            FAILED="$FAILED, $entry"
        else
            FAILED="$entry"
        fi
    fi
done 3<<EOF
$PLAN
EOF

if [ -n "$FAILED" ]; then
    echo "skill-gate: failed: $FAILED"
    exit 1
fi
echo "skill-gate: $PASSED of $TOTAL checks passed"
exit 0
