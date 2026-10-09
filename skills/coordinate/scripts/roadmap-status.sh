#!/usr/bin/env bash
# roadmap-status.sh -- write a landed feature's Status and Delivered line back
# to the roadmap as a pull request, and keep the record saying it is pending.
# Agent-run, at roadmap scope only
# (docs/designs/current/DESIGN-coordinate-record-container.md, Decision 4).
#
# Usage:
#   roadmap-status.sh --session S --unit TAG --outcome TEXT
#   roadmap-status.sh --session S --confirm TAG
#   roadmap-status.sh --session S --drop TAG --reason TEXT
#   roadmap-status.sh --session S --list
#   ... [--scope roadmap --name N --repo O/R --ref N [--roadmap PATH]
#        --skip-session-checks]                                   (tests)
#
# The session gives the name, host, roadmap and record number (coord-log.sh
# vars and run-facts); the override flags exist for tests only.
#
# --unit opens the roadmap pull request for the feature whose heading tag is
# TAG (`Feature 7`, `ED1`, `AB10b`), the coordinator having judged that its last pull
# request landed: it reads the roadmap at the default branch's head, refuses a
# TAG that isn't a feature there or already reads Done, Shipped or Dropped
# (annotated or not, as lib_roadmap_features reads them), refuses one
# with a follow-up Work row (its scoping alone landed, its execution not), and refuses
# while any roadmap pull request is pending in the record, since the generated
# sections of two such pull requests would conflict. It sets the feature's
# **Status:** to Done, writes **Delivered:** TEXT right after it (replacing one
# that is there), removes its **Needs:** line, each with its wrapped lines,
# runs `shirabe roadmap populate` so the generated sections agree, and changes
# nothing else: an **Outcome:** line is the promise and is never touched. One
# exception: on a roadmap/v1 roadmap whose Dependencies name prefixed tags, or
# whose headings carry a letter suffix (`AB10a`), the first populate with a
# shirabe that reads those tags also rewrites the generated sections well
# beyond this feature (rows go from None to real edges, and later F keys
# renumber);
# run one populate pass on such a roadmap on its own first, so this pull
# request stays this feature's change. --outcome's text is what lands on the
# Delivered line; the flag keeps its old name. It commits that
# on a new branch, coordinate/roadmap-status-<tag>-<minute>, through the git
# data and contents APIs, opens the pull request against the default branch,
# and writes a Side effects in flight row through the record's write core:
# Action `roadmap-status`, Target `<TAG> [#n](URL)`, How to confirm `the
# roadmap on <default> reads <TAG> Done`. It never merges the pull request;
# whoever merges roadmap changes does.
#
# --confirm removes TAG's row once the roadmap on the default branch reads
# Done, Shipped or Dropped for it, annotated or not (`Done -- shipped in #12`;
# exit 1, nothing written, while it doesn't). --drop
# removes it with a reason, for a pull request closed unmerged. --list prints
# the pending rows as a JSON array of {unit, pull_request, attempted}; it is
# the one reader of these rows, which pick-facts.sh marks as landed units.
#
# Each change to the record is told as an entry with record-append.sh, kind
# roadmap-status, after the body is written.
#
# A failed record write after the pull request opened (11, 12 or 13) leaves
# the pull request with no row: close it by hand before running --unit again,
# which would open a second one on a new branch.
#
# Exit codes: 0 done (prints the pull request's URL, or the record's) or
# printed; 1 --confirm: the roadmap doesn't read Done yet; 2 a read failed;
# 10 refused about the record (no found record, not a canonical one, or from
# the write core: not open, provenance, a directed transition); 11 a write
# failed; 12 the record changed between this script's read and its write; 13
# the record is full; 14 the record was written but its entry wasn't posted;
# 64 usage (and any scope but a roadmap); 65 refused about the request: the
# tag, the feature's state, a pending pull request (the reason on stderr).
#
# GitHub calls:
#   reads:  gh issue view N --repo R --json body
#           gh api --method GET repos/R --jq .default_branch
#           gh api --method GET repos/R/git/ref/heads/<default> --jq .object.sha
#           gh api --method GET repos/R/contents/<roadmap>?ref=<that sha>   (--unit)
#           gh api --method GET repos/R/contents/<roadmap>?ref=<default>    (--confirm)
#   writes: gh api --method POST repos/R/git/refs -f ref=... -f sha=...
#           gh api --method PUT repos/R/contents/<roadmap> (message, content, sha, branch)
#           gh pr create --repo R --head <branch> --base <default> --title T --body-file F
#           the record, through record-write-core.sh; the entry, through record-append.sh
set -uo pipefail

PROG=roadmap-status
HERE=$(cd "$(dirname "$0")" && pwd)
SESSION= SCOPE= NAME= REPO= REF= ROADMAP= MODE= TAG= OUTCOME= REASON=
SKIP_CHECKS=0
ARG_ROADMAP=

usage() { sed -n '/^# Usage:/,/^# The session gives/p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 64; }
setmode() { [ -z "$MODE" ] || usage; MODE=$1; }
while [ $# -gt 0 ]; do
    case "$1" in
        --session) [ $# -ge 2 ] || usage; SESSION=$2; shift 2 ;;
        --scope) [ $# -ge 2 ] || usage; SCOPE=$2; shift 2 ;;
        --name) [ $# -ge 2 ] || usage; NAME=$2; shift 2 ;;
        --repo) [ $# -ge 2 ] || usage; REPO=$2; shift 2 ;;
        --ref) [ $# -ge 2 ] || usage; REF=$2; shift 2 ;;
        --roadmap) [ $# -ge 2 ] || usage; ARG_ROADMAP=$2; shift 2 ;;
        --unit) [ $# -ge 2 ] || usage; setmode open; TAG=$2; shift 2 ;;
        --confirm) [ $# -ge 2 ] || usage; setmode confirm; TAG=$2; shift 2 ;;
        --drop) [ $# -ge 2 ] || usage; setmode drop; TAG=$2; shift 2 ;;
        --list) setmode list; shift ;;
        --outcome) [ $# -ge 2 ] || usage; OUTCOME=$2; shift 2 ;;
        --reason) [ $# -ge 2 ] || usage; REASON=$2; shift 2 ;;
        --skip-session-checks) SKIP_CHECKS=1; shift ;;
        *) usage ;;
    esac
done
case "$MODE" in
    open) [ -n "$OUTCOME" ] && [ -z "$REASON" ] || usage ;;
    drop) [ -n "$REASON" ] && [ -z "$OUTCOME" ] || usage ;;
    confirm|list) [ -z "$OUTCOME$REASON" ] || usage ;;
    *) usage ;;
esac
. "$HERE/record-common.sh"
lib_facts
[ -z "$ARG_ROADMAP" ] || { [ "$OVERRIDE" = 1 ] || usage; ROADMAP=$ARG_ROADMAP; }
[ "$SCOPE" = roadmap ] || { echo "$PROG: a feature's status is a roadmap's; this run's scope is $SCOPE" >&2; exit 64; }
lib_roadmap_path
lib_run_ref || { echo "$PROG: refused: the run has no found record" >&2; exit 10; }
case "$MODE" in
    list) ;;
    *) [[ $TAG =~ ^(Feature\ [0-9]+|[A-Za-z]+[0-9]+[a-z]?)$ ]] || { echo "$PROG: $TAG is not a feature's heading tag (Feature 7, ED1, AB10b)" >&2; exit 64; } ;;
esac
case "$OUTCOME$REASON" in *$'\n'*|*$'\r'*) echo "$PROG: --outcome and --reason are one line" >&2; exit 64 ;; esac

WD=$(mktemp -d "${TMPDIR:-/tmp}/roadmap-status.XXXXXX")
trap 'rm -rf "$WD"' EXIT

gh issue view "$REF" --repo "$REPO" --json body --jq .body > "$WD/live.raw" 2> "$WD/r.err" < /dev/null || lib_die2 "cannot read issue #$REF: $(lib_scrub < "$WD/r.err")"
tr -d '\r' < "$WD/live.raw" > "$WD/live.md"
lib_parse "$WD/live.md" "$WD/parsed.json"
case $? in
    0) ;;
    3|65) echo "$PROG: refused: #$REF is not a canonical roadmap record for $NAME" >&2; exit 10 ;;
    *) lib_die2 "record-parse.sh failed" ;;
esac
# The pending rows, {unit, pull_request, attempted}: the Target is
# `<TAG> [#n](URL)`.
jq -c '[.side_effects[] | select(.action == "roadmap-status")
        | (.target | capture("^(?<unit>.+) (?<pr>\\[#[0-9]+\\]\\(https://github\\.com/[^)]+\\))$")) as $t
        | {unit: ($t.unit // .target), pull_request: ($t.pr // ""), attempted}]' "$WD/parsed.json" > "$WD/pending.json" \
    || lib_die2 "jq failed"
if [ "$MODE" = list ]; then
    cat "$WD/pending.json"
    exit 0
fi

refuse() { echo "$PROG: refused: $*" >&2; exit 65; }
lib_default_branch || lib_die2 "cannot read $REPO's default branch"
# feature_read <file>: FEATURE, TAG's entry as lib_roadmap_features reads the
# roadmap, or empty when no item carries TAG. A roadmap the reader can't read
# is a read failure, never a feature that isn't there.
feature_read() {
    lib_roadmap_features "$1" > "$WD/features.json" 2> "$WD/f.err" || lib_die2 "cannot read the features of $ROADMAP: $(lib_scrub < "$WD/f.err")"
    FEATURE=$(jq -c --arg t "$TAG" '[.[] | select(.id == $t)][0] // empty' "$WD/features.json") || lib_die2 "jq failed"
}

# write_record <next-json> <entry-text>: the record through the write core,
# then the entry. The write core takes over the EXIT trap, so the entry's
# text is kept outside $WD.
write_record() {
    bash "$HERE/record-render.sh" --container issue --written "$(jq -r '.written' "$WD/parsed.json")" "$1" > "$WD/body.md" 2> "$WD/render.err" \
        || { echo "$PROG: refused:" >&2; lib_scrub < "$WD/render.err" >&2; echo >&2; exit 65; }
    ENTRY_FILE=$(mktemp "${TMPDIR:-/tmp}/roadmap-status-entry.XXXXXX")
    printf '%s\n' "$2" > "$ENTRY_FILE"
    if [ "$OVERRIDE" = 1 ]; then ADDR=(--scope "$SCOPE" --name "$NAME" --repo "$REPO" --ref "$REF")
    else ADDR=(--session "$SESSION"); fi
    BODY="$WD/body.md" END= CLOSE=0 CORE_CLEANUP=$WD
    lib_write_guard
    . "$HERE/record-write-core.sh"
    core_write > /dev/null
    if ! bash "$HERE/record-append.sh" "${ADDR[@]}" --kind roadmap-status --text-file "$ENTRY_FILE" > /dev/null; then
        echo "$PROG: the record was written, but its entry wasn't posted; post it with record-append.sh --kind roadmap-status: $(cat "$ENTRY_FILE")" >&2
        rm -f "$ENTRY_FILE"; exit 14
    fi
    rm -f "$ENTRY_FILE"
}
# without_row <out>: the record without TAG's row.
without_row() {
    jq --arg t "$TAG" 'del(.written) | .side_effects = [.side_effects[] | select((.action == "roadmap-status" and (.target | startswith($t + " ["))) | not)]' \
        "$WD/parsed.json" > "$1" || lib_die2 "jq failed"
}

case "$MODE" in
confirm|drop)
    ROW=$(jq -c --arg t "$TAG" '[.[] | select(.unit == $t)][0] // empty' "$WD/pending.json")
    [ -n "$ROW" ] || refuse "no roadmap pull request is pending for $TAG"
    if [ "$MODE" = confirm ]; then
        lib_file_at "$ROADMAP" "$DEFAULT_BRANCH" "$WD/roadmap.md"
        case $? in 0) ;; 1) lib_die2 "$ROADMAP is not on $DEFAULT_BRANCH" ;; *) lib_die2 "cannot read $ROADMAP" ;; esac
        feature_read "$WD/roadmap.md"
        ST=$(printf '%s' "$FEATURE" | jq -r '.status // empty')
        [ "$(printf '%s' "$FEATURE" | jq -r '.done // false')" = true ] \
            || { echo "$PROG: $TAG reads ${ST:-no status} on $DEFAULT_BRANCH; its pull request, $(printf '%s' "$ROW" | jq -r .pull_request), hasn't landed" >&2; exit 1; }
        without_row "$WD/next.json"
        write_record "$WD/next.json" "$TAG reads $ST on $DEFAULT_BRANCH; its roadmap pull request $(printf '%s' "$ROW" | jq -r .pull_request) landed, and the record no longer holds it."
    else
        without_row "$WD/next.json"
        write_record "$WD/next.json" "$TAG's roadmap pull request $(printf '%s' "$ROW" | jq -r .pull_request) is dropped: $REASON"
    fi
    echo "https://github.com/$REPO/issues/$REF"
    exit 0
    ;;
esac

# --unit: open the roadmap pull request.
# A unit whose scoping alone landed still has its execution to come: its
# follow-up Work row stands until a holding takes it.
FU=$(jq -r --arg t "$TAG" '[(.work // [])[] | select(.kind == "follow-up" and .item == $t) | .who][0] // empty' "$WD/parsed.json")
[ -z "$FU" ] || refuse "$TAG's scoping alone landed ($FU) and its execution is a follow-up still to dispatch; it isn't Done until that lands"
[ "$(jq length "$WD/pending.json")" = 0 ] \
    || refuse "a roadmap pull request is already pending ($(jq -r 'map("\(.unit) \(.pull_request)") | join(", ")' "$WD/pending.json")); confirm or drop it first, since two would conflict in the generated sections"
# The default branch's head, then the roadmap and its blob at that one
# commit, so the branch, the content edited and the sha the commit replaces
# all agree even if the default branch moves meanwhile.
BASE_SHA=$(gh api --method GET "repos/$REPO/git/ref/heads/$DEFAULT_BRANCH" --jq .object.sha 2> /dev/null < /dev/null) || lib_die2 "cannot read the head of $DEFAULT_BRANCH"
[[ $BASE_SHA =~ $RE_SHA ]] || lib_die2 "the head of $DEFAULT_BRANCH is not a sha"
gh api --method GET "repos/$REPO/contents/$ROADMAP?ref=$BASE_SHA" > "$WD/contents.json" 2> "$WD/c.err" < /dev/null \
    || lib_die2 "cannot read $ROADMAP at $BASE_SHA: $(lib_scrub < "$WD/c.err")"
BLOB=$(jq -r '.sha // empty' "$WD/contents.json")
# The contents API leaves a file over one megabyte without its content.
[ -n "$(jq -r '.content // empty' "$WD/contents.json")" ] || lib_die2 "the contents API gave no content for $ROADMAP (a file over 1 MB?)"
[[ $BLOB =~ $RE_SHA ]] || lib_die2 "$ROADMAP's blob sha is not a sha"
jq -r '.content // ""' "$WD/contents.json" > "$WD/roadmap.b64" && lib_b64d "$WD/roadmap.b64" "$WD/roadmap.md" || lib_die2 "cannot decode $ROADMAP"
feature_read "$WD/roadmap.md"
[ -n "$FEATURE" ] || refuse "$TAG is not a feature of $ROADMAP"
[ "$(printf '%s' "$FEATURE" | jq -r .done)" = false ] || refuse "$TAG already reads $(printf '%s' "$FEATURE" | jq -r .status)"
TITLE=$(printf '%s' "$FEATURE" | jq -r .title)

# TAG's Status, Needs and Delivered fields, and nothing else before the
# populate. A Needs or Delivered field goes with its wrapped lines, the lines
# below it up to a blank line, the next field line or a heading, as the
# reader bounds a field. The text reaches awk through the environment, which
# takes it as written (`-v` would read its backslashes as escapes). A roadmap
# with CRLF line endings keeps them.
mkdir -p "$WD/doc"
DOC="$WD/doc/$(basename "$ROADMAP")"
CRLF=0
grep -q $'\r$' "$WD/roadmap.md" && CRLF=1
tr -d '\r' < "$WD/roadmap.md" | RS_TAG="$TAG" RS_DELIVERED="$OUTCOME" awk '
    BEGIN { tag = ENVIRON["RS_TAG"]; delivered = ENVIRON["RS_DELIVERED"] }
    dropping && (/^[ \t]*$/ || /^\*\*[A-Z][A-Za-z ]*:\*\*/ || /^#+([ \t]|$)/) { dropping = 0 }
    dropping { next }
    /^## / { infeat = ($0 ~ /^## Features[ \t]*$/); inblock = 0; print; next }
    infeat && /^### / { inblock = (index($0, "### " tag ": ") == 1); print; next }
    inblock && /^\*\*Needs:\*\*/ { dropping = 1; next }
    inblock && /^\*\*Delivered:\*\*/ { dropping = 1; next }
    inblock && /^\*\*Status:\*\*/ { print "**Status:** Done"; print "**Delivered:** " delivered; next }
    { print }' > "$DOC" || lib_die2 "awk failed"
grep -qxF "**Delivered:** $OUTCOME" "$DOC" || refuse "the Delivered line could not be written into $TAG's block (it has no **Status:** line, or the text didn't survive as written)"
(cd "$WD/doc" && shirabe roadmap populate "$(basename "$DOC")" > /dev/null 2> "$WD/populate.err") \
    || lib_die2 "shirabe roadmap populate failed: $(lib_scrub < "$WD/populate.err")"
if [ "$CRLF" = 1 ]; then sed 's/$/\r/' "$DOC" > "$DOC.crlf" && mv "$DOC.crlf" "$DOC"; fi

# The branch, from the commit the roadmap was read at, and the commit on it.
SLUG=$(printf '%s' "$TAG" | tr 'A-Z' 'a-z' | tr -c 'a-z0-9\n' '-')
BRANCH_NEW="coordinate/roadmap-status-$SLUG-$(date -u +%Y%m%d%H%M)"
gh api --method POST "repos/$REPO/git/refs" -f "ref=refs/heads/$BRANCH_NEW" -f "sha=$BASE_SHA" > /dev/null 2> "$WD/w.err" < /dev/null \
    || { echo "$PROG: creating $BRANCH_NEW failed: $(lib_scrub < "$WD/w.err")" >&2; exit 11; }
base64 < "$DOC" | tr -d '\n\r ' > "$WD/content"
gh api --method PUT "repos/$REPO/contents/$ROADMAP" -f "message=docs(roadmap): record $TAG, $TITLE, as done" \
    -f "content=$(cat "$WD/content")" -f "sha=$BLOB" -f "branch=$BRANCH_NEW" > /dev/null 2> "$WD/w.err" < /dev/null \
    || { echo "$PROG: the commit to $BRANCH_NEW failed: $(lib_scrub < "$WD/w.err")" >&2; exit 11; }
{
    printf 'Records %s of the roadmap, %s, as done: its Status is Done and its Delivered line reads "%s"; its Outcome, the promise, is unchanged. Its Needs line goes, as the roadmap'"'"'s rule for done features asks, and the generated sections are regenerated. Nothing else in the roadmap changes.\n\n---\n\n' "$TAG" "$TITLE" "$OUTCOME"
    printf 'Opened by the coordinator for %s from its record, issue #%s, after it judged the feature'"'"'s last pull request landed. Review it against the roadmap'"'"'s own rules for an Active document before merging; the coordinator never merges it.\n' "$NAME" "$REF"
} > "$WD/prbody.md"
PR_URL=$(gh pr create --repo "$REPO" --head "$BRANCH_NEW" --base "$DEFAULT_BRANCH" --title "docs(roadmap): record $TAG, $TITLE, as done" \
    --body-file "$WD/prbody.md" 2> "$WD/w.err" < /dev/null) \
    || { echo "$PROG: opening the pull request failed: $(lib_scrub < "$WD/w.err")" >&2; exit 11; }
PR_NUM=${PR_URL##*/}
[[ $PR_NUM =~ $RE_NUM ]] || lib_die2 "gh pr create printed no pull request URL"

jq --arg t "$TAG [#$PR_NUM]($PR_URL)" --arg at "$(date -u +%Y-%m-%dT%H:%MZ)" --arg d "$DEFAULT_BRANCH" --arg tag "$TAG" '
    del(.written) | .side_effects += [{action: "roadmap-status", target: $t, verified_head: "", attempted: $at,
        how_to_confirm: "the roadmap on \($d) reads \($tag) Done"}]' "$WD/parsed.json" > "$WD/next.json" || lib_die2 "jq failed"
printf '%s\n' "$PR_URL" > "$WD/url"
URL_OUT=$(cat "$WD/url")
write_record "$WD/next.json" "$TAG landed; its roadmap pull request $PR_URL sets its Status to Done with the Delivered line \"$OUTCOME\". Pick passes over $TAG until it merges."
printf '%s\n' "$URL_OUT"
