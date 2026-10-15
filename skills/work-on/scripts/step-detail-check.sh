#!/usr/bin/env bash
# step-detail-check.sh - may this plan step's work start?
#
# A plan/v2 step plan details its first steps and leaves the rest as one-line
# outlines. The plan's owner details step N+1 after step N's work reaches its
# terminal, so a step that is still an outline has nothing to build from yet.
# /work-on's plan_validation state runs this check before any implementation,
# against the plan as committed at that moment, and stops the step's child when
# the step is still an outline. Once the owner commits the detail, running the
# child again passes the check.
#
# The decision is `shirabe plan outlines`'s `detailed` field, which needs a
# goal, acceptance criteria and a check together. The same parser feeds the
# validator, so on a plan `shirabe validate` accepts, this script and the
# validator never disagree about which steps are detailed. A plan/v1 issue is
# always detailed.
#
# Usage:
#   step-detail-check.sh <plan> <step>
#   step-detail-check.sh --task <task-name> <plan>
#
#   <plan>   path to the PLAN, inside the git repository of the current
#            directory; a symlink is followed and must land inside it too.
#   <step>   the step number (the issue number on a plan/v1 PLAN), matching
#            ^[1-9][0-9]{0,2}$. Checked before the plan is read.
#   --task   the form the work-on template's gate uses: <task-name> is the
#            child's ARTIFACT_PREFIX. plan-to-tasks.sh names every plan/v2 task
#            step-<N>, and the number after `step-` is checked as <step>. Any
#            other name is a plan/v1 task (o-<slug>, m-<slug>, issue-<N>, pr-*, gate-*), whose
#            entries are always detailed, so the check passes at once without
#            reading anything.
#
# Environment:
#   SHIRABE_BIN   the shirabe binary to run (default: shirabe on PATH).
#
# Output: nothing from the plan itself. Step titles and text never reach the
# output, so hostile plan text cannot reach a terminal or a log through here.
# Caller-supplied values echoed in a refusal have control characters stripped
# and are cut to 80 characters. When shirabe cannot read the plan, the first
# line of its error is echoed the same way, stripped and cut to 240 characters.
#
# Exit codes:
#   0 - the step is detailed (stdout: `step <N> is detailed`), or --task named
#       a task that is not a step
#   1 - the step is an outline (stderr: `step <N> is an outline; the plan's
#       owner details it before its work starts`)
#   2 - refused: a malformed step, a plan path that is missing, not a regular
#       file or outside the repository, a PLAN that is not plan/v1 or plan/v2,
#       no such step, a missing jq or shirabe, or a shirabe that cannot read
#       the PLAN

set -uo pipefail

PROG="step-detail-check"
STEP_RE='^[1-9][0-9]{0,2}$'

refuse() {
    printf '%s: %s\n' "$PROG" "$1" >&2
    exit 2
}

usage() {
    refuse "usage: step-detail-check.sh <plan> <step> | step-detail-check.sh --task <task-name> <plan>"
}

# shown <value> [<max>]: a value made safe to print: control characters
# stripped, at most <max> characters (default 80).
shown() {
    local s
    s=$(printf '%s' "$1" | LC_ALL=C tr -d '\000-\037\177')
    printf '%s' "${s:0:${2:-80}}"
}

if [ "${1:-}" = "--task" ]; then
    [ $# -eq 3 ] || usage
    TASK="$2"
    PLAN="$3"
    case "$TASK" in
        step-*) STEP="${TASK#step-}" ;;
        *) exit 0 ;;
    esac
else
    [ $# -eq 2 ] || usage
    PLAN="$1"
    STEP="$2"
fi

# The step first, before anything is read.
if [[ ! "$STEP" =~ $STEP_RE ]]; then
    refuse "step must match ^[1-9][0-9]{0,2}\$ (1 to 999, no leading zero), got [$(shown "$STEP")]"
fi

# The plan path: present, a regular file, inside this repository.
[ -n "$PLAN" ] || refuse "no plan path given"
if [ ! -e "$PLAN" ] && [ ! -L "$PLAN" ]; then
    refuse "plan not found: $(shown "$PLAN")"
fi
ROOT=$(git rev-parse --show-toplevel) \
    || refuse "not inside a git repository; run from the repository that holds the plan"
ROOT=$(cd "$ROOT" 2>/dev/null && pwd -P) || refuse "cannot enter the repository root"

# Follow the plan's own symlinks by hand (readlink -f is not on every macOS
# this runs on), then resolve the directory physically, which settles `..`
# and any symlinked directory on the way.
p="$PLAN"
hops=0
while [ -L "$p" ]; do
    hops=$((hops + 1))
    [ "$hops" -le 40 ] || refuse "plan path has too many levels of symlinks: $(shown "$PLAN")"
    t=$(readlink "$p") || refuse "cannot read the symlink: $(shown "$PLAN")"
    case "$t" in
        /*) p="$t" ;;
        *) p="$(dirname "$p")/$t" ;;
    esac
done
[ -e "$p" ] || refuse "plan not found: $(shown "$PLAN") (a symlink to nothing)"
[ -f "$p" ] || refuse "plan is not a regular file: $(shown "$PLAN")"
d=$(cd "$(dirname "$p")" 2>/dev/null && pwd -P) || refuse "cannot resolve the plan's directory: $(shown "$PLAN")"
REAL="$d/$(basename "$p")"
case "$REAL" in
    "$ROOT"/*) ;;
    *) refuse "plan resolves outside the repository: $(shown "$PLAN")" ;;
esac
[ -r "$REAL" ] || refuse "plan is not readable: $(shown "$PLAN")"

# The version, from the frontmatter only.
SCHEMA=$(awk 'NR == 1 { if ($0 !~ /^---[[:space:]]*$/) exit; next }
              /^---[[:space:]]*$/ { exit }
              /^schema:/ { sub(/^schema:[[:space:]]*/, ""); sub(/[[:space:]]+$/, ""); print; exit }' "$REAL")
case "$SCHEMA" in
    plan/v1) NOUN="issue" ;;
    plan/v2) NOUN="step" ;;
    *) refuse "not a plan/v1 or plan/v2 PLAN (frontmatter schema [$(shown "$SCHEMA")]): $(shown "$PLAN")" ;;
esac

command -v jq >/dev/null || refuse "jq not found on PATH; it reads the outline envelope"

if [ -n "${SHIRABE_BIN:-}" ]; then
    [ -x "$SHIRABE_BIN" ] || refuse "SHIRABE_BIN is set but is not an executable file: $(shown "$SHIRABE_BIN")"
    BIN="$SHIRABE_BIN"
elif command -v shirabe >/dev/null 2>&1; then
    BIN="shirabe"
else
    refuse "shirabe binary not found: install shirabe so it is on PATH, or set SHIRABE_BIN. The plan is read through 'shirabe plan outlines'."
fi

# The plan goes to shirabe as an absolute path, so it can never be taken for
# an option.
if ! ENVELOPE=$("$BIN" plan outlines "$REAL" 2>/dev/null); then
    # Its first stderr line, with the absolute path put back as the caller
    # wrote it, so what shirabe objected to fits in the message.
    why=$("$BIN" plan outlines "$REAL" 2>&1 >/dev/null | sed -n 1p)
    why="${why//"$REAL"/$PLAN}"
    refuse "'shirabe plan outlines' could not read the plan: $(shown "$why" 240). A shirabe older than plan/v2 support cannot read a step plan; update it."
fi

VERDICT=$(printf '%s' "$ENVELOPE" | jq -r --argjson n "$STEP" '
    if .schema != "shirabe-plan-outlines/v1" then "envelope"
    else [.outlines[] | select(.number == $n)]
        | if length == 0 then "none"
          elif length > 1 then "many"
          elif (.[0] | has("detailed") | not) then "unknown"
          elif .[0].detailed == true then "detailed"
          else "outline" end
    end' 2>/dev/null) || VERDICT="envelope"

case "$VERDICT" in
    detailed)
        printf '%s %s is detailed\n' "$NOUN" "$STEP"
        exit 0
        ;;
    outline)
        printf "%s %s is an outline; the plan's owner details it before its work starts\n" "$NOUN" "$STEP" >&2
        exit 1
        ;;
    none) refuse "the plan has no $NOUN $STEP: $(shown "$PLAN")" ;;
    many) refuse "the plan declares $NOUN $STEP more than once: $(shown "$PLAN")" ;;
    unknown) refuse "this shirabe reports no 'detailed' field, so it predates plan/v2 support; update it" ;;
    *) refuse "unrecognized output from 'shirabe plan outlines'; the shirabe binary and this script are out of step" ;;
esac
