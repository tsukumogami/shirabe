#!/usr/bin/env bash
# ci-fix-tests.sh -- has every test change on the shared branch been judged by
# a /work-on run's panels?
# Part of the execute skill
#
# A gate script: ci_monitor's ci_fix_tests_judged gate runs it, and koto
# holds the `failing_fixed` edge until it exits 0. A CI fix /execute makes on
# the shared PR is committed after every child reached `done`, so no panel of
# any child saw it. A fix that edits production files only is fine as it is.
# A fix that edits a test has to go through a fix round of the step's /work-on
# run (`fix-round.sh start --from <child>`), whose panels judge the test and
# whose counting gate then records the head it counted at. This script is how
# ci_monitor tells the two apart.
#
# Usage: ci-fix-tests.sh <execute session>
#
# It lists the session's children (`koto workflows --children`), which
# includes every fix round, since a round is started under the run's parent.
# For each child with a `counted_head` context key (test-change.sh status
# writes it when a counting gate passes) it reads the commit; for a step that
# ran in its own worktree and was rebased when it landed, the head its
# step_group.jsonl `landed` record names stands in for it, and a step recorded
# as stopped is skipped (see step-group.sh). The newest is
# the one with the fewest commits between it and HEAD, not the latest
# recorded: every head must be an ancestor of HEAD (else exit 2), and on the
# shared branch's linear history the closest one is the last counted. It then
# classifies the diff from that commit to HEAD with
# scripts/lib/test-classify.sh, using the `review_level_rules.tsv` copy stored
# in the same child's session, or the rules /work-on ships when that child has
# none.
#
# It only reads: no koto context write, no git write, nothing to GitHub.
#
# Exit codes:
#   0  the diff from the newest counted head to HEAD touches no test file
#   1  it touches one or more; each is printed as `untested: <path>`
#   2  could not decide: no child recorded a counted_head, a recorded head
#      isn't 40 hex, names no commit or isn't an ancestor of HEAD, a koto
#      read failed, or the classification failed
#   64 usage
#
# Requires: bash 3.2+, jq, koto, git. Written without `set -e`.

set -u

HERE=$(cd "$(dirname "$0")" && pwd)
PLUGIN_ROOT_SELF=$(cd "$HERE/../../.." && pwd)
RULES_SHIPPED="$PLUGIN_ROOT_SELF/skills/work-on/references/review-level-rules.tsv"
COUNTED_KEY=counted_head
RULES_KEY=review_level_rules.tsv
GROUP_KEY=step_group.jsonl

usage() { echo "usage: ci-fix-tests.sh <execute session>" >&2; exit 64; }
undecided() { echo "ci-fix-tests: $*" >&2; exit 2; }

[ $# -eq 1 ] || usage
SESSION=$1
case "$SESSION" in
    ''|-*|*..*|*[!A-Za-z0-9._-]*) usage ;;
esac

command -v jq >/dev/null 2>&1 || undecided "jq is not on PATH"
command -v koto >/dev/null 2>&1 || undecided "koto is not on PATH"

# shellcheck source=../../../scripts/lib/test-classify.sh
. "$PLUGIN_ROOT_SELF/scripts/lib/test-classify.sh" || undecided "cannot load scripts/lib/test-classify.sh"

WORK=$(mktemp -d "${TMPDIR:-/tmp}/ci-fix-tests.XXXXXX") || undecided "could not create a temporary directory"
trap 'rm -rf "$WORK"' EXIT

HEAD=$(git rev-parse -q --verify "HEAD^{commit}" 2>/dev/null) || undecided "HEAD names no commit"

koto workflows --children "$SESSION" > "$WORK/children.json" 2> "$WORK/koto.err" \
    || undecided "koto workflows --children $SESSION failed: $(tail -n 1 "$WORK/koto.err")"
jq -e 'type == "array" and all(.[]; (.name | type) == "string")' "$WORK/children.json" >/dev/null 2>&1 \
    || undecided "koto workflows --children $SESSION did not answer a list of sessions"
jq -r '.[].name' "$WORK/children.json" > "$WORK/children.txt"

# /execute's concurrent steps (scripts/step-group.sh): a step cut into its own
# worktree counts on its step branch, and `land` then rebases that branch onto
# the shared one, so the counted_head its child recorded is not on the shared
# branch. The step's `landed` record in the run's step_group.jsonl names the
# head the same commits reached the shared branch at, and that head stands in
# for it. A step recorded as stopped landed nothing, so its child is skipped.
koto context exists "$SESSION" "$GROUP_KEY" >/dev/null 2>"$WORK/koto.err" < /dev/null
rc=$?
case "$rc" in
    0) koto context get "$SESSION" "$GROUP_KEY" > "$WORK/group.jsonl" 2>"$WORK/koto.err" < /dev/null \
           || undecided "koto context get $SESSION $GROUP_KEY failed: $(tail -n 1 "$WORK/koto.err")" ;;
    1) : > "$WORK/group.jsonl" ;;
    *) undecided "koto context exists $SESSION $GROUP_KEY failed (exit $rc): $(tail -n 1 "$WORK/koto.err")" ;;
esac
jq -es 'all(type == "object")' "$WORK/group.jsonl" > "$WORK/group.ok" 2>&1 \
    || undecided "$GROUP_KEY in $SESSION is not JSON lines"

# hex40 <child> <sha>: exits 2 unless <sha> is 40 lowercase hex.
hex40() {
    case "$2" in
        *[!0-9a-f]*|'') undecided "$1 recorded a $COUNTED_KEY that isn't 40 hex" ;;
    esac
    [ "${#2}" -eq 40 ] || undecided "$1 recorded a $COUNTED_KEY that isn't 40 hex"
}

NEWEST="" NEWEST_CHILD="" NEWEST_DIST=""
while IFS= read -r child; do
    [ -n "$child" ] || continue
    koto context exists "$child" "$COUNTED_KEY" >/dev/null 2>"$WORK/koto.err" < /dev/null
    rc=$?
    case "$rc" in
        0) ;;
        1) continue ;;
        *) undecided "koto context exists $child $COUNTED_KEY failed (exit $rc): $(tail -n 1 "$WORK/koto.err")" ;;
    esac
    sha=$(koto context get "$child" "$COUNTED_KEY" 2>"$WORK/koto.err" < /dev/null) \
        || undecided "koto context get $child $COUNTED_KEY failed: $(tail -n 1 "$WORK/koto.err")"
    sha=$(printf '%s' "$sha" | tr -d '[:space:]')
    hex40 "$child" "$sha"
    step=${child#"$SESSION".}
    if [ "$step" != "$child" ] && [ -s "$WORK/group.jsonl" ]; then
        last=$(jq -rs --arg s "$step" '[.[] | select(.step == $s and (.event == "landed" or .event == "stopped"))]
            | (.[-1] // {}) | "\(.event // "")=\(.head // "")"' "$WORK/group.jsonl") \
            || undecided "could not read step $step's record in $GROUP_KEY"
        case "$last" in
            stopped=*) continue ;;
            landed=*) sha=${last#landed=}; hex40 "$child (landed)" "$sha" ;;
        esac
    fi
    git cat-file -e "$sha^{commit}" 2>/dev/null || undecided "$child's $COUNTED_KEY $sha names no commit here"
    git merge-base --is-ancestor "$sha" "$HEAD" 2>/dev/null \
        || undecided "$child's $COUNTED_KEY $sha is not an ancestor of HEAD"
    dist=$(git rev-list --count "$sha..$HEAD" 2>/dev/null) || undecided "could not count the commits from $sha to HEAD"
    if [ -z "$NEWEST_DIST" ] || [ "$dist" -lt "$NEWEST_DIST" ]; then
        NEWEST=$sha NEWEST_CHILD=$child NEWEST_DIST=$dist
    fi
done < "$WORK/children.txt"

[ -n "$NEWEST" ] || undecided "no child of $SESSION recorded a $COUNTED_KEY; nothing says which commits the panels' record covers"

koto context exists "$NEWEST_CHILD" "$RULES_KEY" >/dev/null 2>"$WORK/koto.err" < /dev/null
rc=$?
case "$rc" in
    0) koto context get "$NEWEST_CHILD" "$RULES_KEY" > "$WORK/rules" 2>"$WORK/koto.err" < /dev/null \
           || undecided "koto context get $NEWEST_CHILD $RULES_KEY failed: $(tail -n 1 "$WORK/koto.err")" ;;
    1) cp "$RULES_SHIPPED" "$WORK/rules" 2>/dev/null || undecided "cannot read the shipped rules $RULES_SHIPPED" ;;
    *) undecided "koto context exists $NEWEST_CHILD $RULES_KEY failed (exit $rc): $(tail -n 1 "$WORK/koto.err")" ;;
esac

test_classify "$NEWEST" "$HEAD" "$WORK/rules" > "$WORK/rows" 2> "$WORK/classify.err" \
    || undecided "could not classify the test files from $NEWEST to HEAD: $(head -c 300 "$WORK/classify.err")"

if [ ! -s "$WORK/rows" ]; then
    echo "judged: no test file changed since $NEWEST, the counted head $NEWEST_CHILD recorded"
    exit 0
fi
cut -f 2 "$WORK/rows" | LC_ALL=C sed 's/[[:cntrl:]]/?/g; s/^/untested: /'
echo "ci-fix-tests: these test files changed after $NEWEST, the newest counted head ($NEWEST_CHILD); start a fix round so a panel judges them" >&2
exit 1
