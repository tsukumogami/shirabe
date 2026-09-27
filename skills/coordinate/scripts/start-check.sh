#!/usr/bin/env bash
# start-check.sh -- the check action of state start: may this run begin?
#
# Roadmap scope: the roadmap file as it stands on the host's default branch
# (not in any local checkout, which may be stale or on another branch) must
# carry `status: Active` in its YAML frontmatter, compared case-sensitively.
# Discipline scope has nothing to read and always answers `discipline`.
#
# Verdict tokens:
#   active                 the roadmap reads Active
#   not-active <status>    any other status; <status> is the frontmatter value
#                          when it is a plain word, `unset` when there is no
#                          status line, `other` for anything else (a value from
#                          GitHub never reaches the capture unless it is a word)
#   not-active missing     the roadmap isn't on the default branch (404)
#   discipline             discipline scope
#
# Usage:
#   start-check.sh --session S
#   start-check.sh [--session S] --scope roadmap|discipline --name N --repo O/R
#                  [--roadmap PATH] [--no-seal]                          (tests)
#
# The roadmap path is the session's ROADMAP variable (with the override flags,
# --roadmap or docs/roadmaps/ROADMAP-<name>.md).
#
# Exit codes: 0 a verdict was printed; 2 a read failed; 64 usage.
#
# GitHub reads:
#   gh api --method GET repos/R --jq .default_branch
#   gh api --method GET "repos/R/contents/<path>?ref=<default>" --jq .content
set -uo pipefail

PROG=start-check
HERE=$(cd "$(dirname "$0")" && pwd)
SESSION= SCOPE= NAME= REPO= REF= ARG_ROADMAP=
NO_SEAL=0

usage() { sed -n '/^# Usage:/,/^# Exit codes:/p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 64; }
while [ $# -gt 0 ]; do
    case "$1" in
        --session) [ $# -ge 2 ] || usage; SESSION=$2; shift 2 ;;
        --scope) [ $# -ge 2 ] || usage; SCOPE=$2; shift 2 ;;
        --name) [ $# -ge 2 ] || usage; NAME=$2; shift 2 ;;
        --repo) [ $# -ge 2 ] || usage; REPO=$2; shift 2 ;;
        --roadmap) [ $# -ge 2 ] || usage; ARG_ROADMAP=$2; shift 2 ;;
        --no-seal) NO_SEAL=1; shift ;;
        *) usage ;;
    esac
done
. "$HERE/record-common.sh"
ROADMAP=$ARG_ROADMAP
lib_facts
[ -z "$ARG_ROADMAP" ] || [ "$OVERRIDE" = 1 ] || usage

[ "$SCOPE" = discipline ] && lib_emit start discipline "" ""

# A closed shape for the path: under docs/roadmaps/, a ROADMAP-*.md file, no
# `..`, nothing that would change the API path or its query.
lib_roadmap_path

T=$(mktemp -d "${TMPDIR:-/tmp}/start-check.XXXXXX")
trap 'rm -rf "$T"' EXIT

lib_default_branch || lib_die2 "cannot read $REPO's default branch, or it is not a branch name"
lib_file_at "$ROADMAP" "$DEFAULT_BRANCH" "$T/roadmap.md"
case $? in
    0) ;;
    1) lib_emit start "not-active missing" "" "" ;;
    *) if [ -s "$T/roadmap.md.err" ]; then lib_die2 "cannot read $ROADMAP: $(lib_scrub < "$T/roadmap.md.err")"
       else lib_die2 "cannot decode $ROADMAP"; fi ;;
esac

# The frontmatter: from a first line of `---` to the next `---`.
STATUS=$(tr -d '\r' < "$T/roadmap.md" | awk 'NR == 1 { if ($0 != "---") exit; next } $0 == "---" { exit }
    /^status:/ { sub(/^status:[ \t]*/, ""); sub(/[ \t]+$/, ""); print; exit }')
case "$STATUS" in \"*\") STATUS=${STATUS#\"}; STATUS=${STATUS%\"} ;; \'*\') STATUS=${STATUS#\'}; STATUS=${STATUS%\'} ;; esac
if [ "$STATUS" = Active ]; then lib_emit start active "" ""; fi
if [ -z "$STATUS" ]; then STATUS=unset
elif ! [[ $STATUS =~ ^[A-Za-z][A-Za-z-]{0,31}$ ]]; then STATUS=other; fi
lib_emit start "not-active $STATUS" "" ""
