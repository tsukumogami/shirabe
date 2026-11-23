#!/usr/bin/env bash
# issue-type-route.sh -- for /work-on: is this run's type already decided as
# code, from facts the run holds?
#
# The `code_route` gate on `issue_type_routing` runs this. The state asks the
# agent for the issue's type after implementation, and on almost every run the
# answer is `code`. When the facts already say so, the run takes the code route
# on entry with no agent turn: the type hint is `code` (ISSUE_TYPE, from the
# plan entry's Type field or the default) and the changed paths the run
# recorded (`changed_paths.txt`, written at `changed_paths_record`) name at
# least one path that isn't plain documentation. A path is plain
# documentation when review-level.sh classifies it as `docs` and nothing else;
# a SKILL.md, a reference an agent loads, a script, a template, or a path in
# no class at all is not. Code is the route that reviews the most, so taking
# it from the facts can only add review, never skip it.
#
# Everything else asks the agent, as before: a `docs` or `task` hint, a diff of
# documentation only, no changed paths, or a changed_paths.txt that can't be
# read. Those are the cases where the answer can differ from `code`.
#
# Usage: issue-type-route.sh <koto-session-name> <issue-type-hint>
#
# Exit codes:
#   0  -- code, decided from the facts
#   1  -- not decided: the state asks the agent
#   64 -- usage
#
# Nothing on stdout but one `route:` line saying which and why. Bash 3.2.
set -uo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
RL="$SCRIPT_DIR/review-level.sh"

[ $# -eq 2 ] || { echo "usage: issue-type-route.sh <session> <issue-type-hint>" >&2; exit 64; }
SESSION=$1
HINT=$2
case "$SESSION" in ""|-*|*[!A-Za-z0-9._-]*) echo "issue-type-route: bad session name [$SESSION]" >&2; exit 64 ;; esac

ask() { echo "route: ask ($1)"; exit 1; }

[ "$HINT" = code ] || ask "the type hint is ${HINT:-empty}, not code"

WORK=$(mktemp -d) || ask "no temporary directory"
trap 'rm -rf "$WORK"' EXIT

koto context exists "$SESSION" changed_paths.txt || ask "no changed_paths.txt recorded"
koto context get "$SESSION" changed_paths.txt > "$WORK/cp" || ask "changed_paths.txt could not be read"

# The path lines are `<status>\t<path>[\t<path>]`, after the `base:` and
# `commits:` header lines; a rename names both sides and both count.
awk -F '\t' 'NF >= 2 { for (i = 2; i <= NF; i++) if ($i != "") print $i }' "$WORK/cp" > "$WORK/paths"
[ -s "$WORK/paths" ] || ask "no changed paths"

# One classify call for every path: `<path>\t<classes>`, `-` for none.
tr '\n' '\0' < "$WORK/paths" | xargs -0 "$RL" classify > "$WORK/classes" \
    || ask "review-level.sh classify failed"
first=$(awk -F '\t' '$2 != "docs" { print $1; exit }' "$WORK/classes")
[ -n "$first" ] || ask "every changed path is documentation"
echo "route: code ($first is not documentation)"
exit 0
