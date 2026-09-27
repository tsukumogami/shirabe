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
#   - the body is always re-rendered with this script's own Written: time,
#     never the one in the body, since record-confirm.sh trusts that time;
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
# since the body was read; 11 a write failed; 2 a read failed; 64 usage; 65
# the body was refused.
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
if [ -z "$REF" ]; then
    FACTS=$(bash "$HERE/coord-log.sh" run-facts --session "$SESSION" 2>/dev/null)
    case $? in
        0) REF=$(printf '%s' "$FACTS" | jq -r '.ref') ;;
        1) echo "$PROG: refused: the run has no found record" >&2; exit 10 ;;
        *) lib_die2 "cannot read the run's facts" ;;
    esac
fi
[[ $REF =~ $RE_NUM ]] || usage

T=$(mktemp -d "${TMPDIR:-/tmp}/record-write.XXXXXX")
trap 'rm -rf "$T"' EXIT

lib_parse "$BODY" "$T/parsed.json"
case $? in
    0) ;;
    3|65) echo "$PROG: refused: the body is not a canonical $SCOPE record for $NAME:" >&2; lib_scrub < "$T/parsed.json.err" >&2; echo >&2; exit 65 ;;
    *) lib_die2 "record-parse.sh failed" ;;
esac

# The target, re-read now.
if [ "$SCOPE" = roadmap ]; then
    gh issue view "$REF" --repo "$REPO" --json state,body,url > "$T/target.json" 2> "$T/r.err" < /dev/null || lib_die2 "cannot read issue #$REF"
else
    gh pr view "$REF" --repo "$REPO" --json state,body,url,title,headRefName,isCrossRepository > "$T/target.json" 2> "$T/r.err" < /dev/null || lib_die2 "cannot read pull request #$REF"
fi
jq -r '.body // ""' "$T/target.json" | tr -d '\r' > "$T/live.md" || lib_die2 "the target read is not JSON"
STATE=$(jq -r '.state' "$T/target.json")
URL=$(jq -r '.url' "$T/target.json")
[ "$STATE" = OPEN ] || { echo "$PROG: refused: #$REF is $STATE, not an open record" >&2; exit 10; }
grep -qxF -- "$DECL" "$T/live.md" || { echo "$PROG: refused: #$REF does not carry this scope's declaration line" >&2; exit 10; }
# Compare and swap on the Written: line. The body carries the Written: time of
# the version it was edited from; the live body must still carry that time, or
# someone wrote the record since it was read and this write would lose their
# change. A live body that no longer parses as a canonical record has changed
# too.
BASE=$(jq -r '.written // ""' "$T/parsed.json")
if lib_parse "$T/live.md" "$T/live.json" 2> /dev/null; then
    LIVE_W=$(jq -r '.written // ""' "$T/live.json")
else
    LIVE_W="(not a canonical record)"
fi
if [ -z "$BASE" ] || [ "$BASE" != "$LIVE_W" ]; then
    echo "$PROG: refused: record-changed: #$REF was written at $LIVE_W, but this body was edited from ${BASE:-no version}; re-read it and redo the change" >&2
    exit 12
fi
if [ "$SCOPE" = discipline ]; then
    [ "$(jq -r '.headRefName' "$T/target.json")" = "$BRANCH" ] && [ "$(jq -r '.isCrossRepository' "$T/target.json")" = false ] \
        || { echo "$PROG: refused: #$REF is not on $BRANCH in $REPO" >&2; exit 10; }
fi

# A public host never names a private repository: not in a Holdings Repo, not
# in a Pull request link, not in a Side effects Target (an owner/repo token,
# owner/repo#n, or a github.com URL). A named repository the host can't read
# (404) can't be shown public, so it is refused too. This finds the
# repositories the body names and reads each one's visibility; the render
# below refuses a cell naming any on the list (the codec's names_repo, the one
# test of whether a cell names a repository).
PRIVATE=
HOST_PRIVATE=$(gh api --method GET "repos/$REPO" --jq .private 2> /dev/null < /dev/null) || lib_die2 "cannot read $REPO's visibility"
if [ "$HOST_PRIVATE" = false ]; then
    jq -r -L "$HERE" 'include "record-codec";
        def clean: sub("\\.git$"; "") | sub("\\.+$"; "");
        [ (.holdings[] | .repo, (.pull_request | pr_link_parts | .r)),
          (.side_effects[] | (.target // "") | tostring
            | ( (scan("github\\.com/([A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+)") | .[0] | clean),
                (gsub("[A-Za-z][A-Za-z0-9+.-]*://[^\\s)\\]>]*"; " ")
                 | scan("(?:^|[\\s(\\[<,;:])([A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+)(?=#[0-9]|[\\s)\\]>,;:]|$)") | .[0] | clean) )) ]
        | map(select(. != "")) | unique | .[]' "$T/parsed.json" > "$T/named" || lib_die2 "jq failed"
    while IFS= read -r r; do
        [[ $r =~ $RE_REPO ]] || { echo "$PROG: refused: $r is not owner/repo" >&2; exit 65; }
        [ "$r" = "$REPO" ] && continue
        if ! P=$(gh api --method GET "repos/$r" --jq .private 2> "$T/v.err" < /dev/null); then
            grep -q 'HTTP 404' "$T/v.err" || lib_die2 "cannot read $r's visibility"
            P=unreadable
        fi
        [ "$P" = false ] || PRIVATE="$PRIVATE${PRIVATE:+,}$r"
    done < "$T/named"
fi

# The body is always re-rendered with this script's own Written: time: the
# time in the coordinator's body is never trusted, because record-confirm.sh
# reads it as proof a write came after an event. Once the run has entered
# dispatch, deferrals already filed or closed are dropped first.
cp "$T/parsed.json" "$T/next.json"
if lib_dispatched && lib_drop_disposed "$T/parsed.json" "$T/dropped.json"; then
    mv "$T/dropped.json" "$T/next.json"
fi
jq 'del(.written)' "$T/next.json" | bash "$HERE/record-render.sh" --container "$CONTAINER" --written "$(lib_now)" --private-repos "$PRIVATE" \
    > "$T/body.md" 2> "$T/render.err" || {
    echo "$PROG: refused:" >&2; lib_scrub < "$T/render.err" >&2; echo >&2
    [ -z "$PRIVATE" ] || echo "$PROG: private, or unreadable from the public host $REPO: $PRIVATE" >&2
    exit 65; }
OUT="$T/body.md"

if [ "$SCOPE" = roadmap ]; then
    gh issue edit "$REF" --repo "$REPO" --body-file "$OUT" > /dev/null 2> "$T/w.err" < /dev/null \
        || { echo "$PROG: the issue edit failed: $(lib_scrub < "$T/w.err")" >&2; exit 11; }
    if [ "$CLOSE" = 1 ]; then
        gh issue close "$REF" --repo "$REPO" > /dev/null 2> "$T/w.err" < /dev/null \
            || { echo "$PROG: the body was written but the close failed: $(lib_scrub < "$T/w.err")" >&2; exit 11; }
    fi
else
    set -- --body-file "$OUT"
    if [ -n "$END" ]; then
        lib_rotation_dates "$(jq -r '.title' "$T/target.json")" || { echo "$PROG: refused: #$REF's title is not this rotation's title" >&2; exit 10; }
        if [ "$END" \< "$ROT_START" ]; then echo "$PROG: refused: the end $END is before the rotation's start $ROT_START" >&2; exit 65; fi
        set -- "$@" --title "docs(coordinate): $NAME rotation $ROT_START to $END"
    fi
    gh pr edit "$REF" --repo "$REPO" "$@" > /dev/null 2> "$T/w.err" < /dev/null \
        || { echo "$PROG: the pull request edit failed: $(lib_scrub < "$T/w.err")" >&2; exit 11; }
fi
printf '%s\n' "$URL"
