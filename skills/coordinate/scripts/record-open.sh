#!/usr/bin/env bash
# record-open.sh -- open this scope's coordinator record, exactly once.
# Agent-run, from the directive of state record_open; never a default action.
#
# It re-reads GitHub first, because the find that routed here may be minutes
# old: a record that now exists (an open issue with the exact title, or an
# open pull request on the record branch) is refused with exit 10 rather than
# opened a second time. The body must be a canonical record for this scope in
# the right container before anything is written.
#
# Roadmap scope: one issue titled "Coordinator record: ROADMAP-<name>".
# Discipline scope: the branch coordinate/discipline-<name> cut from the
# default branch's head with one empty commit, made through GitHub's git-data
# API (the coordinator usually has no checkout of the host), then a draft pull
# request titled "docs(coordinate): <name> rotation <start> to <end>". An
# existing branch is refused unless --recut, which deletes the remote ref
# first (the find's stale-branch and unopened cases), so a squash-merged
# history never comes back.
#
# Usage:
#   record-open.sh --session S --body-file F [--start YYYY-MM-DD --end YYYY-MM-DD] [--recut]
#   record-open.sh --scope roadmap|discipline --name N --repo O/R
#                  --skip-session-checks --body-file F [...]         (tests)
#
# --start and --end are required at discipline scope and refused at roadmap
# scope. Before any read, the session must pass `coord-log.sh provenance` and
# show no directed transition in the run.
#
# Exit codes: 0 opened (prints record=<url>); 10 refused (a record exists, the
# branch exists without --recut, provenance, or a directed transition); 11 a
# write failed partway (prints step=<ref-delete|commit|ref-create|pr-create|
# issue-create>); 2 a read failed; 64 usage; 65 the body was refused.
#
# GitHub calls:
#   reads:  those record-common.sh's lib_open_issues and lib_discipline_read make;
#           gh api --method GET repos/R/git/ref/heads/<default> --jq .object.sha
#           gh api --method GET repos/R/git/commits/<sha> --jq .tree.sha
#   writes: gh issue create --repo R --title T --body-file F
#           gh api --method DELETE repos/R/git/refs/heads/coordinate/discipline-<name>
#           gh api --method POST repos/R/git/commits -f message=... -f tree=... -f parents[]=...
#           gh api --method POST repos/R/git/refs -f ref=refs/heads/... -f sha=...
#           gh pr create --repo R --draft --head ... --base <default> --title T --body-file F
set -uo pipefail

PROG=record-open
HERE=$(cd "$(dirname "$0")" && pwd)
SESSION= SCOPE= NAME= REPO= REF= BODY= START= END=
RECUT=0 SKIP_CHECKS=0

usage() { sed -n '/^# Usage:/,/^# Exit codes:/p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 64; }
while [ $# -gt 0 ]; do
    case "$1" in
        --session) [ $# -ge 2 ] || usage; SESSION=$2; shift 2 ;;
        --scope) [ $# -ge 2 ] || usage; SCOPE=$2; shift 2 ;;
        --name) [ $# -ge 2 ] || usage; NAME=$2; shift 2 ;;
        --repo) [ $# -ge 2 ] || usage; REPO=$2; shift 2 ;;
        --body-file) [ $# -ge 2 ] || usage; BODY=$2; shift 2 ;;
        --start) [ $# -ge 2 ] || usage; START=$2; shift 2 ;;
        --end) [ $# -ge 2 ] || usage; END=$2; shift 2 ;;
        --recut) RECUT=1; shift ;;
        --skip-session-checks) SKIP_CHECKS=1; shift ;;
        *) usage ;;
    esac
done
[ -n "$BODY" ] && [ -r "$BODY" ] || usage
. "$HERE/record-common.sh"
lib_facts
if [ "$SCOPE" = discipline ]; then
    lib_valid_date "$START" && lib_valid_date "$END" || usage
    if [ "$END" \< "$START" ]; then echo "$PROG: refused: the end date $END is before the start $START" >&2; exit 65; fi
    PR_TITLE="docs(coordinate): $NAME rotation $START to $END"
else
    [ -z "$START$END" ] && [ "$RECUT" = 0 ] || usage
fi
lib_write_guard

T=$(mktemp -d "${TMPDIR:-/tmp}/record-open.XXXXXX")
trap 'rm -rf "$T"' EXIT

lib_parse "$BODY" "$T/parsed.json"
case $? in
    0) ;;
    3|65) echo "$PROG: refused: the body is not a canonical $SCOPE record for $NAME:" >&2; lib_scrub < "$T/parsed.json.err" >&2; echo >&2; exit 65 ;;
    *) lib_die2 "record-parse.sh failed" ;;
esac
# A new record opens with no Decisions section: entries are written, and a
# predecessor's are carried in, only by record-decision.sh, which checks each
# one.
if jq -e 'has("decisions")' "$T/parsed.json" > /dev/null; then
    echo "$PROG: refused: a new record opens without a Decisions section; record-decision.sh writes and carries decisions" >&2
    exit 65
fi

step_failed() { echo "step=$1"; echo "$PROG: the $1 write failed: $(lib_scrub < "$T/w.err")" >&2; exit 11; }

if [ "$SCOPE" = roadmap ]; then
    lib_open_issues "$T/issues.json" || lib_die2 "the open-issue listing failed"
    N=$(jq length "$T/issues.json")
    if [ "$N" -gt 0 ]; then
        echo "$PROG: refused: an open issue titled \"$ISSUE_TITLE\" exists (#$(jq -r 'map(.number | tostring) | join(", #")' "$T/issues.json"))" >&2
        exit 10
    fi
    URL=$(gh issue create --repo "$REPO" --title "$ISSUE_TITLE" --body-file "$BODY" 2> "$T/w.err" < /dev/null) || step_failed issue-create
    echo "record=$(printf '%s' "$URL" | tail -1)"
    exit 0
fi

lib_discipline_read "$T" || lib_die2 "a discipline read failed"
OPEN=$(jq -r '[.[] | select(.state == "OPEN") | .number | tostring] | join(", #")' "$T/prs.json")
if [ -n "$OPEN" ]; then
    echo "$PROG: refused: $BRANCH has an open pull request (#$OPEN)" >&2
    exit 10
fi
if [ "$BRANCH_EXISTS" = 1 ]; then
    if [ "$RECUT" = 0 ]; then
        echo "$PROG: refused: $BRANCH exists; re-run with --recut to delete and cut it again" >&2
        exit 10
    fi
    gh api --method DELETE "repos/$REPO/git/refs/heads/$BRANCH" > /dev/null 2> "$T/w.err" < /dev/null || step_failed ref-delete
fi
BASE_SHA=$(gh api --method GET "repos/$REPO/git/ref/heads/$DEFAULT_BRANCH" --jq .object.sha 2> /dev/null < /dev/null) || lib_die2 "cannot read the head of $DEFAULT_BRANCH"
[[ $BASE_SHA =~ $RE_SHA ]] || lib_die2 "the head of $DEFAULT_BRANCH is not a sha"
TREE=$(gh api --method GET "repos/$REPO/git/commits/$BASE_SHA" --jq .tree.sha 2> /dev/null < /dev/null) || lib_die2 "cannot read the tree of $BASE_SHA"
[[ $TREE =~ $RE_SHA ]] || lib_die2 "the tree of $BASE_SHA is not a sha"
NEW=$(gh api --method POST "repos/$REPO/git/commits" -f message="docs(coordinate): open $NAME rotation record" \
    -f tree="$TREE" -f "parents[]=$BASE_SHA" --jq .sha 2> "$T/w.err" < /dev/null) || step_failed commit
[[ $NEW =~ $RE_SHA ]] || step_failed commit
gh api --method POST "repos/$REPO/git/refs" -f ref="refs/heads/$BRANCH" -f sha="$NEW" > /dev/null 2> "$T/w.err" < /dev/null || step_failed ref-create
URL=$(gh pr create --repo "$REPO" --draft --head "$BRANCH" --base "$DEFAULT_BRANCH" --title "$PR_TITLE" \
    --body-file "$BODY" 2> "$T/w.err" < /dev/null) || step_failed pr-create
echo "record=$(printf '%s' "$URL" | tail -1)"
