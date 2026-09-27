#!/usr/bin/env bash
# record-find.sh -- the check action of state record_find: find this scope's
# coordinator record on GitHub and say whether the run may adopt it.
#
# Roadmap scope: every open issue in the host, read through the paginated REST
# listing (never a search, whose index lags a new issue and whose phrase match
# takes a -v2 title), matched on the exact title
# "Coordinator record: ROADMAP-<name>". Discipline scope: the record branch
# coordinate/discipline-<name> and its same-repository pull requests into the
# default branch; a fork's or another branch's pull request is never looked at.
#
# One candidate is judged in this order: the declaration line (else
# `foreign`), then authority (its author and last editor each have admin,
# maintain or write access to the host, else `unauthorized`; a failed
# permission read exits 2 so nothing is adopted), then a canonical body for
# this scope (else `malformed`), then, at discipline scope, the rotation
# title's dates (unparseable: `ambiguous`; ended before today UTC:
# `predecessor`).
#
# On `found`, the record's URL also goes to context key record_url, which the
# terminal results name as `record`.
#
# Verdict tokens (the first word is what coord-verdict.sh routes on):
#   roadmap:    found <n> | none | ambiguous <n> <m> [...] | foreign <n>
#               | malformed <n> | unauthorized <n>
#   discipline: found <n> | predecessor <n> | foreign <n> | ambiguous <n> [...]
#               | malformed <n> | unauthorized <n> | stale-branch | unopened | none
#
# Usage:
#   record-find.sh --session S
#   record-find.sh [--session S] --scope roadmap|discipline --name N --repo O/R
#                  [--today YYYY-MM-DD] [--no-seal]          (tests)
#
# The detail goes to context key coord/record_find.json as data:
#   {verdict, ref, url, reason, candidates, default_branch, rotation:{start,end}}
# The token, sealed to this visit of record_find, is the only stdout line;
# under --no-seal it is printed bare and no context is written.
#
# Exit codes: 0 a verdict was printed; 2 a read failed (koto re-runs the
# action); 64 usage.
#
# GitHub reads (all reads; no search form anywhere):
#   gh api --method GET "repos/R/issues?state=open&per_page=100" --paginate
#   gh api --method GET repos/R  --jq .default_branch
#   gh api --method GET repos/R/branches/coordinate%2Fdiscipline-<name>
#   gh pr list --repo R --head coordinate/discipline-<name> --state all --limit 100 --json ...
#   gh api graphql (a query: the candidate's author and editor logins)
#   gh api --method GET repos/R/collaborators/<login>/permission --jq .permission
set -uo pipefail

PROG=record-find
HERE=$(cd "$(dirname "$0")" && pwd)
SESSION= SCOPE= NAME= REPO= REF= TODAY=
NO_SEAL=0 SKIP_CHECKS=0

usage() { sed -n '/^# Usage:/,/^# Exit codes:/p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 64; }
while [ $# -gt 0 ]; do
    case "$1" in
        --session) [ $# -ge 2 ] || usage; SESSION=$2; shift 2 ;;
        --scope) [ $# -ge 2 ] || usage; SCOPE=$2; shift 2 ;;
        --name) [ $# -ge 2 ] || usage; NAME=$2; shift 2 ;;
        --repo) [ $# -ge 2 ] || usage; REPO=$2; shift 2 ;;
        --today) [ $# -ge 2 ] || usage; TODAY=$2; shift 2 ;;
        --no-seal) NO_SEAL=1; shift ;;
        *) usage ;;
    esac
done
. "$HERE/record-common.sh"
lib_facts
if [ -n "$TODAY" ]; then lib_valid_date "$TODAY" || usage; else TODAY=$(date -u +%Y-%m-%d); fi

T=$(mktemp -d "${TMPDIR:-/tmp}/record-find.XXXXXX")
trap 'rm -rf "$T"' EXIT

VERDICT= NUM= URL= REASON= CANDS='[]' DEFAULT_BRANCH= ROT_START= ROT_END=

finish() {
    local token=$VERDICT
    [ -n "$NUM" ] && token="$VERDICT $NUM"
    jq -n --arg v "$VERDICT" --arg ref "$NUM" --arg url "$URL" --arg reason "$REASON" \
        --argjson c "$CANDS" --arg db "$DEFAULT_BRANCH" --arg s "$ROT_START" --arg e "$ROT_END" \
        '{verdict: $v, ref: $ref, url: $url, reason: $reason, candidates: $c, default_branch: $db,
          rotation: {start: $s, end: $e}}' > "$T/detail.json"
    # The found record's URL, for the terminal results' `record` field
    # (${context.record_url}): written here, by the engine's own read, so the
    # closing report names the record the run actually found.
    if [ "$NO_SEAL" != 1 ] && [ "$VERDICT" = found ] \
        && [[ $URL =~ ^https://github\.com/[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+/(issues|pull)/[0-9]+$ ]]; then
        printf '%s' "$URL" > "$T/record_url"
        "$KOTO" context add "$SESSION" record_url --from-file "$T/record_url" >/dev/null || lib_die2 "koto context add record_url failed"
    fi
    lib_emit record_find "$token" coord/record_find.json "$T/detail.json"
}

# judge <kind> <number> <body-file>: declaration, authority, canonical body.
# Sets VERDICT and REASON when the candidate fails one; returns 1 then.
judge() {
    if ! lib_has_declaration "$3"; then
        VERDICT=foreign; REASON="the candidate has no declaration line"; return 1
    fi
    lib_authority "$1" "$2"
    case $? in
        0) ;;
        1) VERDICT=unauthorized; REASON=$AUTH_REASON; return 1 ;;
        *) lib_die2 "the author-authority read failed for #$2; nothing adopted" ;;
    esac
    lib_parse "$3" "$T/parsed.json"
    case $? in
        0) ;;
        3|65) VERDICT=malformed; REASON=$(lib_scrub < "$T/parsed.json.err" | head -1); return 1 ;;
        *) lib_die2 "record-parse.sh failed" ;;
    esac
    return 0
}

if [ "$SCOPE" = roadmap ]; then
    lib_open_issues "$T/issues.json" || lib_die2 "the open-issue listing failed: $(lib_scrub < "$T/issues.json.raw.err")"
    CANDS=$(jq -c 'map({number, url, title})' "$T/issues.json")
    COUNT=$(jq length "$T/issues.json")
    if [ "$COUNT" -eq 0 ]; then
        VERDICT=none; REASON="no open issue titled $ISSUE_TITLE"; finish
    fi
    if [ "$COUNT" -gt 1 ]; then
        VERDICT=ambiguous; NUM=$(jq -r 'map(.number | tostring) | join(" ")' "$T/issues.json")
        REASON="$COUNT open issues carry the record's title"; finish
    fi
    NUM=$(jq -r '.[0].number' "$T/issues.json")
    URL=$(jq -r '.[0].url' "$T/issues.json")
    [[ $NUM =~ $RE_NUM ]] || lib_die2 "the listing returned an unusable issue number"
    jq -r '.[0].body' "$T/issues.json" > "$T/body.md"
    judge issue "$NUM" "$T/body.md" || finish
    VERDICT=found; REASON="one open record"; finish
fi

# Discipline scope.
lib_discipline_read "$T" || lib_die2 "a discipline read failed: $(cat "$T"/*.err 2>/dev/null | lib_scrub)"
CANDS=$(jq -c 'map({number, url, title, state})' "$T/prs.json")
if [ "$BRANCH_EXISTS" = 0 ]; then
    VERDICT=none; REASON="no branch $BRANCH"; finish
fi
jq '[.[] | select(.state == "OPEN")]' "$T/prs.json" > "$T/open.json"
OPEN=$(jq length "$T/open.json")
if [ "$OPEN" -eq 0 ]; then
    if [ "$(jq length "$T/prs.json")" -gt 0 ]; then
        VERDICT=stale-branch; REASON="the branch's last pull request was merged or closed"
    else
        VERDICT=unopened; REASON="the branch never had a pull request"
    fi
    finish
fi
if [ "$OPEN" -gt 1 ]; then
    VERDICT=ambiguous; NUM=$(jq -r 'map(.number | tostring) | join(" ")' "$T/open.json")
    REASON="$OPEN open pull requests on $BRANCH"; finish
fi
NUM=$(jq -r '.[0].number' "$T/open.json")
URL=$(jq -r '.[0].url' "$T/open.json")
[[ $NUM =~ $RE_NUM ]] || lib_die2 "the listing returned an unusable pull request number"
jq -r '.[0].body // ""' "$T/open.json" > "$T/body.md"
judge pullRequest "$NUM" "$T/body.md" || finish
TITLE=$(jq -r '.[0].title' "$T/open.json")
if ! lib_rotation_dates "$TITLE"; then
    VERDICT=ambiguous; REASON="the record's title is not a rotation title with real dates"; finish
fi
if [ "$ROT_END" \< "$TODAY" ]; then
    VERDICT=predecessor; REASON="the rotation ended $ROT_END"; finish
fi
VERDICT=found; REASON="the rotation runs to $ROT_END"; finish
