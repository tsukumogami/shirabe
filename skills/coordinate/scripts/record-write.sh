#!/usr/bin/env bash
# record-write.sh -- replace the coordinator record's whole body. Agent-run;
# every record update, record-holding.sh's included, goes through here so all
# of them share the same checks.
#
# The record is rewritten, never appended to: the body is one canonical render,
# edited in place with `gh issue edit` or `gh pr edit`, and no comment is ever
# posted. Before writing it:
#   - the session must pass `coord-log.sh provenance` and show no directed
#     transition in the run (exit 10);
#   - the body must parse as a canonical record for this scope and container
#     (exit 65);
#   - a fresh read must show the target open and carrying this scope's
#     declaration line (exit 10), so a record closed or replaced since the
#     find is never written over;
#   - the live body's Written: time must equal the body's own, the time of the
#     version it was edited from (exit 12, record-changed), so a write that
#     landed since the read, by another coordinator or a person, is never
#     silently overwritten;
#   - when the host is public, no Holdings Repo, no repository in a Pull
#     request link and no repository named in a Side effects Target (owner/repo,
#     owner/repo#n or a github.com URL) may be private or unreadable (exit 65,
#     naming it): this script reads each named repository's visibility and
#     passes the private and unreadable ones to record-render.sh
#     --private-repos, whose codec decides whether a cell names one;
#   - the Decisions section must be as the live record has it (exit 65): only
#     record-decision.sh changes it, through the same write core;
#   - the body is always re-rendered with this script's own Written: time,
#     never the one in the body, since record-confirm.sh trusts that time,
#     and a render over 60,000 bytes is refused (exit 13, record-full);
#   - once the run has entered `dispatch`, Deferrals rows disposed as
#     `filed ...` or `closed: ...` are dropped before that render. Carried rows
#     stay. Before the first dispatch they stay too, because the deferral check
#     compares them with a predecessor's handoff until then.
#
# Usage:
#   record-write.sh --session S --body-file F [--end YYYY-MM-DD] [--close]
#   record-write.sh [--session S] --scope roadmap|discipline --name N --repo O/R
#                   --ref N --skip-session-checks --body-file F [...]   (tests)
#
# --end (discipline only) rewrites the pull request title's end date, keeping
# the live title's start; an end before that start is refused (exit 65).
# --close (roadmap only) writes the body, then closes the issue.
# The record number comes from `coord-log.sh run-facts` (the run's found
# record); --ref replaces it only with the test override flags.
#
# Exit codes: 0 written (prints the record's URL); 10 not an open record of
# this scope, or provenance, or a directed transition; 12 the record changed
# since the body was read; 13 the body is over the size budget; 11 a write
# failed; 2 a read failed; 64 usage; 65 the body was refused.
#
# The write itself (every check from the parse on, and the GitHub edit) is
# core_write in record-write-core.sh, which only write scripts source.
#
# GitHub calls:
#   reads:  gh issue view N --repo R --json state,body,url
#           gh pr view N --repo R --json state,body,url,title,headRefName,isCrossRepository
#           gh api --method GET repos/<repo> --jq .private   (the host, then each named repo)
#   writes: gh issue edit N --repo R --body-file F; gh issue close N --repo R
#           gh pr edit N --repo R --body-file F [--title T]
set -uo pipefail

PROG=record-write
HERE=$(cd "$(dirname "$0")" && pwd)
SESSION= SCOPE= NAME= REPO= REF= BODY= END=
CLOSE=0 SKIP_CHECKS=0

usage() { sed -n '/^# Usage:/,/^# Exit codes:/p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 64; }
while [ $# -gt 0 ]; do
    case "$1" in
        --session) [ $# -ge 2 ] || usage; SESSION=$2; shift 2 ;;
        --scope) [ $# -ge 2 ] || usage; SCOPE=$2; shift 2 ;;
        --name) [ $# -ge 2 ] || usage; NAME=$2; shift 2 ;;
        --repo) [ $# -ge 2 ] || usage; REPO=$2; shift 2 ;;
        --ref) [ $# -ge 2 ] || usage; REF=$2; shift 2 ;;
        --body-file) [ $# -ge 2 ] || usage; BODY=$2; shift 2 ;;
        --end) [ $# -ge 2 ] || usage; END=$2; shift 2 ;;
        --close) CLOSE=1; shift ;;
        --skip-session-checks) SKIP_CHECKS=1; shift ;;
        *) usage ;;
    esac
done
[ -n "$BODY" ] && [ -r "$BODY" ] || usage
. "$HERE/record-common.sh"
lib_facts
if [ -n "$END" ]; then
    [ "$SCOPE" = discipline ] || { echo "$PROG: --end is for a discipline rotation" >&2; exit 64; }
    lib_valid_date "$END" || usage
fi
[ "$CLOSE" = 0 ] || [ "$SCOPE" = roadmap ] || { echo "$PROG: --close is for a roadmap record" >&2; exit 64; }
if [ "$OVERRIDE" = 1 ]; then
    [ -n "$REF" ] || { echo "$PROG: --ref goes with the override flags" >&2; exit 64; }
else
    [ -z "$REF" ] || usage
fi
lib_write_guard

# Sourcing the core closes the Decisions section (DECISIONS_WRITER=0), and this
# script never opens it: only record-decision.sh does.
. "$HERE/record-write-core.sh"
core_write
