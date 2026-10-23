#!/usr/bin/env bash
# repo-pr-content.sh -- whether a repository the coordinator has no checkout
# of opts in to workflow content on its pull requests and issues: the
# `## PR Workflow Content: include` switch scripts/pr-workflow-content.sh
# reads. The coordinator's outward entries (goal-fit, milestone-verdict,
# milestone-failure) are posted on a repository's items only when it answers
# include; otherwise they stay in the coordinator's session.
#
# Usage: repo-pr-content.sh <owner/repo>
#
# Prints include or omit. The repository's CLAUDE.md on its default branch,
# read through the contents API, is handed to scripts/pr-workflow-content.sh
# in a directory of its own, so the switch has one reader. A workspace's
# opt-in that arrives as CLAUDE.local.md isn't committed, so it isn't seen
# here: such a repository reads omit, the side that posts nothing. A missing
# CLAUDE.md, a failed read or decode, or a reader that fails also reads omit,
# so nothing lands on a repository's items by accident; the reason goes to
# stderr.
#
# Exit codes: 0 printed; 64 usage.
#
# GitHub calls:
#   reads: gh api --method GET repos/<owner/repo>/contents/CLAUDE.md --jq .content
#
# Written for the bash 3.2 floor.
set -u

PROG=repo-pr-content
HERE=$(cd "$(dirname "$0")" && pwd)
READER="$HERE/../../../scripts/pr-workflow-content.sh"

[ $# -eq 1 ] && [[ $1 =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] \
    || { echo "usage: repo-pr-content.sh <owner/repo>" >&2; exit 64; }
REPO=$1

omit() { echo "$PROG: $REPO reads omit: $1" >&2; echo omit; exit 0; }

WD=$(mktemp -d "${TMPDIR:-/tmp}/repo-pr-content.XXXXXX") || omit "no temporary directory"
trap 'rm -rf "$WD"' EXIT
mkdir "$WD/repo" || omit "no temporary directory"

gh api --method GET "repos/$REPO/contents/CLAUDE.md" --jq .content > "$WD/b64" 2> "$WD/err" < /dev/null \
    || omit "its CLAUDE.md couldn't be read ($(head -1 "$WD/err"))"
tr -d '\n\r ' < "$WD/b64" > "$WD/flat"
base64 -d < "$WD/flat" > "$WD/repo/CLAUDE.md" 2> /dev/null || base64 -D < "$WD/flat" > "$WD/repo/CLAUDE.md" 2> /dev/null \
    || omit "its CLAUDE.md couldn't be decoded"
[ -f "$READER" ] || omit "no reader at $READER"
v=$(bash "$READER" "$WD/repo" 2> "$WD/err") || omit "the reader failed ($(head -1 "$WD/err"))"
[ "$v" = include ] && echo include || echo omit
