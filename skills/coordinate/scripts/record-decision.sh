#!/usr/bin/env bash
# record-decision.sh -- the one reader and writer of the record's Decisions
# section. Every script that reads the section reads it through --list and
# --read; the write modes are the only way anything changes it.
#
# Usage:
#   record-decision.sh --session S --list        print the section
#   record-decision.sh --session S --read N      print entry N
#   ... [--scope roadmap|discipline --name N --repo O/R --ref N]   (tests)
#
# The session gives the scope, name, host and record number (coord-log.sh
# vars and run-facts); the override flags exist for tests only.
#
# Every mode reads the live body (gh issue view / gh pr view) and parses it
# canonically. --list prints the section as one compact JSON object,
# {"next": <n>, "entries": [...]}, entries in record order, and
# {"next": 1, "entries": []} for a record with no section. --read prints entry
# N as one compact JSON object: every cell a string, as the codec parses it,
# `@` decoded.
#
# Exit codes: 0 printed; 1 no entry N (--read only); 2 a read failed; 10
# refused (the target isn't a canonical record of this scope); 64 usage.
#
# GitHub reads: gh issue view N --repo R --json body | gh pr view N --repo R
# --json body.
set -uo pipefail

PROG=record-decision
HERE=$(cd "$(dirname "$0")" && pwd)
SESSION= SCOPE= NAME= REPO= REF= MODE= ENTRY=

usage() { sed -n '/^# Usage:/,/^# The session gives/p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 64; }
while [ $# -gt 0 ]; do
    case "$1" in
        --session) [ $# -ge 2 ] || usage; SESSION=$2; shift 2 ;;
        --scope) [ $# -ge 2 ] || usage; SCOPE=$2; shift 2 ;;
        --name) [ $# -ge 2 ] || usage; NAME=$2; shift 2 ;;
        --repo) [ $# -ge 2 ] || usage; REPO=$2; shift 2 ;;
        --ref) [ $# -ge 2 ] || usage; REF=$2; shift 2 ;;
        --list) [ -z "$MODE" ] || usage; MODE=list; shift ;;
        --read) [ $# -ge 2 ] && [ -z "$MODE" ] || usage; MODE=read; ENTRY=$2; shift 2 ;;
        *) usage ;;
    esac
done
case "$MODE" in
    list) ;;
    read) [[ $ENTRY =~ ^[1-9][0-9]*$ ]] || usage ;;
    *) usage ;;
esac
. "$HERE/record-common.sh"
lib_facts
if [ "$OVERRIDE" = 1 ]; then
    [ -n "$REF" ] || { echo "$PROG: --ref goes with the override flags" >&2; exit 64; }
else
    [ -z "$REF" ] || usage
    FACTS=$(bash "$HERE/coord-log.sh" run-facts --session "$SESSION")
    case $? in
        0) REF=$(printf '%s' "$FACTS" | jq -r '.ref') ;;
        1) echo "$PROG: refused: the run has no found record" >&2; exit 10 ;;
        *) lib_die2 "cannot read the run's facts" ;;
    esac
fi
[[ $REF =~ $RE_NUM ]] || usage

T=$(mktemp -d "${TMPDIR:-/tmp}/record-decision.XXXXXX")
trap 'rm -rf "$T"' EXIT

# read_live: the live body, parsed canonically into $T/parsed.json.
read_live() {
    if [ "$SCOPE" = roadmap ]; then
        gh issue view "$REF" --repo "$REPO" --json body --jq .body > "$T/live.md" 2> "$T/gh.err" < /dev/null \
            || { lib_scrub < "$T/gh.err" >&2; echo >&2; lib_die2 "cannot read issue #$REF"; }
    else
        gh pr view "$REF" --repo "$REPO" --json body --jq .body > "$T/live.md" 2> "$T/gh.err" < /dev/null \
            || { lib_scrub < "$T/gh.err" >&2; echo >&2; lib_die2 "cannot read pull request #$REF"; }
    fi
    lib_parse "$T/live.md" "$T/parsed.json"
    case $? in
        0) ;;
        3|65) echo "$PROG: refused: #$REF is not a canonical $SCOPE record for $NAME:" >&2; lib_scrub < "$T/parsed.json.err" >&2; echo >&2; exit 10 ;;
        *) lib_die2 "record-parse.sh failed" ;;
    esac
}

read_live
case "$MODE" in
list)
    jq -c '.decisions // {next: 1, entries: []}' "$T/parsed.json"
    exit 0
    ;;
read)
    E=$(jq -c --arg n "$ENTRY" '[(.decisions.entries // [])[] | select(.decision == $n)][0] // empty' "$T/parsed.json")
    [ -n "$E" ] || exit 1
    printf '%s\n' "$E"
    exit 0
    ;;
esac
