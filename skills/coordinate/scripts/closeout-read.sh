#!/usr/bin/env bash
# closeout-read.sh -- the check action of state roadmap_close: is the roadmap
# done, and the record clear to close?
#
# Roadmap scope only: a discipline rotation ends at rotation_end, by writing
# its reasoning for the next rotation, and has no close-out to read. It reads
# the record (state-read.sh) and the roadmap file on the host's default
# branch (the session's ROADMAP path, contents API, never a working tree).
# First that applies:
#   verdict-owed       a Work row of kind verdict-owed stands: a milestone
#                      whose verdict is owed or whose verdict's roadmap edit
#                      isn't confirmed (roadmap-status.sh); the reason names
#                      it, `verdict-owed <tag>`, and the detail's blocker is
#                      its row (docs/designs/DESIGN-milestone-verdicts.md)
#   features-open      an item under the roadmap's items section
#                      (`## Milestones` on roadmap/v3, `## Features`
#                      otherwise) doesn't read Done, Shipped or Dropped
#                      (annotated or not, as in `Done -- shipped in #12`, as
#                      lib_roadmap_features reads it), the roadmap lists no
#                      item, or it is missing; on v3 the reason names
#                      milestones
#   holdings           Holdings isn't empty
#   side-effects       Side effects in flight isn't empty; a milestone's
#                      pending reopen edit (roadmap-status.sh --reopen) is
#                      the blocker first, its reason `reopen-pending <tag>`
#   deferrals          a Deferrals row isn't `filed #<n>` or `closed: <text>`
#   decisions          a Decisions entry isn't settled
#   ready              all clear
#
# The detail goes to context key coord/closeout.json as data, naming the first
# blocker: {verdict, scope, session, reason, blocker}.
#
# Usage:
#   closeout-read.sh --session S
#   closeout-read.sh [--session S] --scope roadmap --name N --repo O/R
#                    [--roadmap PATH] [--no-seal]                     (tests)
#
# The override flags are for tests, with RS_SESSION naming the session that
# holds the record.
#
# Exit codes: 0 a verdict was printed; 2 a read failed, or the run has no
# record; 64 usage.
#
# GitHub reads (all reads):
#   gh api --method GET repos/R --jq .default_branch
#   gh api --method GET "repos/R/contents/<path>?ref=<ref>" --jq .content
set -uo pipefail

PROG=closeout-read
HERE=$(cd "$(dirname "$0")" && pwd)
SESSION= SCOPE= NAME= REPO= ARG_ROADMAP=
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
. "$HERE/state-common.sh"
ROADMAP=$ARG_ROADMAP
lib_facts
[ -z "$ARG_ROADMAP" ] || [ "$OVERRIDE" = 1 ] || usage
[ "$SCOPE" = roadmap ] || { echo "$PROG: a discipline rotation has no close-out to read; it ends at rotation_end" >&2; exit 64; }
lib_run_found || lib_die2 "the run has no found record"

T=$(mktemp -d "${TMPDIR:-/tmp}/closeout-read.XXXXXX") || lib_die2 "cannot make a temporary directory"
trap 'rm -rf "$T"' EXIT

REASON= BLOCKER=null
finish() { # finish <token>
    [ -z "$REASON" ] || echo "$PROG: $REASON" >&2
    jq -n --arg v "$1" --arg scope "$SCOPE" --arg s "${RS_SESSION:-$SESSION}" --arg r "$REASON" --argjson b "$BLOCKER" \
        '{verdict: $v, scope: $scope, session: $s, reason: $r, blocker: $b}' > "$T/detail.json"
    lib_emit roadmap_close "$1" coord/closeout.json "$T/detail.json"
}

lib_roadmap_path
rs_record "$T/parsed.json"; RS_RC=$?
case $RS_RC in
    0) ;;
    65) lib_die2 "$(lib_record_name) doesn't read back as a roadmap record for $NAME: $(lib_scrub < "$T/parsed.json.err" | head -1)" ;;
    *) lib_die2 "cannot read the record: $(lib_scrub < "$T/parsed.json.err" | head -1)" ;;
esac
lib_default_branch || lib_die2 "cannot read $REPO's default branch"
lib_file_at "$ROADMAP" "$DEFAULT_BRANCH" "$T/roadmap.md"
case $? in
    0) ;;
    1) REASON="$ROADMAP is not on $DEFAULT_BRANCH"; finish features-open ;;
    *) lib_die2 "cannot read $ROADMAP: $(lib_scrub < "$T/roadmap.md.err")" ;;
esac
# A milestone whose verdict is owed blocks first, naming the milestone: it may
# already read Done on the default branch (its verdict's edit merged, not yet
# confirmed) or still In progress, and either way the roadmap isn't closed
# until its verdict-owed row is confirmed away.
BLOCKER=$(jq -c '[(.work // [])[] | select(.kind == "verdict-owed")][0] // null
    | if . == null then null else {item, who, next} end' "$T/parsed.json")
if [ "$BLOCKER" != null ]; then
    REASON="verdict-owed $(printf '%s' "$BLOCKER" | jq -r .item): its verdict is owed; give it, and confirm its roadmap edit, before the roadmap closes"
    finish verdict-owed
fi
lib_roadmap_features "$T/roadmap.md" > "$T/features.json" || lib_die2 "cannot parse the roadmap's features"
# RM_SECTION and RM_WORD, from the reader: the item is a milestone on v3.
ITEM=feature
[ "$RM_WORD" = Milestone ] && ITEM=milestone
if [ "$(jq length "$T/features.json")" -eq 0 ]; then
    REASON="the roadmap lists no $ITEM under ## $RM_SECTION"; finish features-open
fi
OPEN=$(jq -c '[.[] | select(.done | not)]' "$T/features.json")
if [ "$(printf '%s' "$OPEN" | jq length)" -gt 0 ]; then
    BLOCKER=$(printf '%s' "$OPEN" | jq -c '.[0] | {id, title, status}')
    REASON="$(printf '%s' "$OPEN" | jq length) $ITEM(s) not Done, Shipped or Dropped"
    finish features-open
fi
if [ "$(jq '.holdings | length' "$T/parsed.json")" -gt 0 ]; then
    BLOCKER=$(jq -c '.holdings[0] | {unit, worker, pull_request}' "$T/parsed.json")
    REASON="Holdings is not empty"; finish holdings
fi
if [ "$(jq '.side_effects | length' "$T/parsed.json")" -gt 0 ]; then
    # A milestone's pending reopen edit is named first, by its tag: the
    # milestone may still read Done on the default branch, so nothing above
    # caught it.
    BLOCKER=$(jq -c '([.side_effects[] | select(.action == "milestone-reopen")] + .side_effects)[0] | {action, target}' "$T/parsed.json")
    if [ "$(printf '%s' "$BLOCKER" | jq -r .action)" = milestone-reopen ]; then
        REASON="reopen-pending $(printf '%s' "$BLOCKER" | jq -r '.target | split(" [")[0]'): its reopen edit is pending; confirm it with roadmap-status.sh --confirm, or drop it, before the roadmap closes"
    else
        REASON="Side effects in flight is not empty"
    fi
    finish side-effects
fi
BLOCKER=$(jq -c '[.deferrals[] | select(.disposition | test("^(filed #[1-9][0-9]*|closed: [\\s\\S]+)$") | not)][0] // null
    | if . == null then null else {deferral, disposition} end' "$T/parsed.json")
if [ "$BLOCKER" != null ]; then
    REASON="a deferral is not filed or closed"; finish deferrals
fi
BLOCKER=$(jq -c '[(.decisions.entries // [])[] | select(.state != "settled")][0] // null
    | if . == null then null else {decision, state, question} end' "$T/parsed.json")
if [ "$BLOCKER" != null ]; then
    REASON="a decision is not settled"; finish decisions
fi
REASON="every feature Done, Shipped or Dropped and the record is clear"
finish ready
