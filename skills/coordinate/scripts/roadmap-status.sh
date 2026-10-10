#!/usr/bin/env bash
# roadmap-status.sh -- write a landed feature's Status and Delivered line back
# to the roadmap as a pull request, and keep the record saying it is pending;
# on a milestone roadmap, mark the milestone's verdict owed and open the one
# roadmap edit a checked verdict calls for. Agent-run, at roadmap scope only
# (docs/designs/current/DESIGN-coordinate-record-container.md, Decision 4;
# docs/designs/DESIGN-milestone-verdicts.md, Decisions 1 and 3).
#
# Usage:
#   roadmap-status.sh --session S --unit TAG [--outcome TEXT]
#   roadmap-status.sh --session S --verdict TAG --entry-file F --entry-url URL
#   roadmap-status.sh --session S --confirm TAG
#   roadmap-status.sh --session S --drop TAG --reason TEXT
#   roadmap-status.sh --session S --list
#   ... [--scope roadmap --name N --repo O/R --ref N [--roadmap PATH]
#        --skip-session-checks]                                   (tests)
#
# The session gives the name, host, roadmap and record number (coord-log.sh
# vars and run-facts); the override flags exist for tests only.
#
# --unit first reads the roadmap at the default branch's head and its
# frontmatter `schema:`, before any refusal, and then does one of two things.
#
# On a roadmap/v2 (milestone) roadmap a milestone reads Done only on a
# recorded verdict, never because its work merged, so --unit opens no pull
# request. It refuses a TAG that isn't a milestone with Evidence there, one
# that already reads Done or Dropped, and one with a follow-up Work row (its
# scoping alone landed); otherwise it writes a Work row of kind verdict-owed
# (Item TAG, Who the dispatch topic of the holding whose Unit is TAG or
# `TAG: <title>`, or `none` when no holding names it, Next `verdict owed
# since <date>`), prints `verdict-owed TAG` and exits 0. Run again with the
# row there, it prints the same and writes nothing. The row keeps the
# milestone off the picker and away from dispatch until its verdict's edit
# is confirmed; --outcome is ignored.
#
# On any other roadmap --unit opens the roadmap pull request for the feature
# whose heading tag is TAG (`Feature 7`, `ED1`, `AB10b`), the coordinator
# having judged that its last pull request landed, and --outcome is required:
# it refuses a TAG that isn't a feature at the default branch's head or
# already reads Done, Shipped or Dropped (annotated or not, as
# lib_roadmap_features reads them), refuses one with a follow-up Work row
# (its scoping alone landed, its execution not), and refuses while any
# roadmap pull request is pending in the record, since the generated
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
# --verdict opens the roadmap edit a checked verdict entry calls for. F is the
# entry as posted with record-append.sh --kind milestone-verdict, at most 16
# KiB, and URL that comment's URL on this run's record issue. It requires
# TAG's verdict-owed row, reads the roadmap at the commit the entry's Source
# line names (whose path must be this run's roadmap) and runs milestone.sh
# check-verdict against it, with --worker the row's Who unless that is
# `none`. It refuses (exit 65, nothing opened) a TAG outside the heading-tag
# grammar, one with no verdict-owed row, an entry file over 16 KiB, an entry
# URL that isn't a comment on the record issue, an entry check-verdict
# refuses (a checker or Work checked value outside its closed shape among
# them), a verified-with-follow-ups verdict (its follow-up milestones aren't
# written yet, so Done is never set without them), a TAG already reading Done
# on the default branch, and any roadmap pull request already pending. For a
# verified verdict the edit sets TAG's Status to Done, removes its Needs line
# and appends the Work checked pull requests to its Delivered line (adding
# the line after Status when there is none); for changes needed it leaves
# Status and Delivered as they are. Either way it appends to `## Progress`
#
#   - <Checked on>: <TAG> -- <verdict>, checked by <checker> (<URL>, <hash8>)
#
# where hash8 is the first eight hex digits of the entry file's sha256, runs
# `shirabe roadmap populate`, commits on coordinate/roadmap-verdict-<tag>-
# <minute>, and opens one pull request whose body carries the whole entry, so
# whoever merges it reviews the judgment. It writes a Side effects row:
# Action `milestone-done` (How to confirm `the roadmap on <default> reads
# <TAG> Done`) for a verified verdict, `milestone-verdict` (How to confirm
# `the roadmap on <default> carries <URL> in Progress`) for changes needed.
# It never merges.
#
# --confirm removes TAG's row once the roadmap on the default branch shows
# it, by the row's Action: `roadmap-status` and `milestone-done` read Done,
# Shipped or Dropped for TAG, annotated or not (`Done -- shipped in #12`);
# `milestone-verdict` finds the entry's URL in `## Progress` (milestone.sh
# progress-has). Confirming a milestone row also removes TAG's verdict-owed
# Work row. While the default branch doesn't show it: exit 1, nothing
# written. --drop removes a row of any of the three Actions with a reason,
# for a pull request closed unmerged, and leaves a verdict-owed row standing.
# --list prints the pending rows as a JSON array of {unit, pull_request,
# attempted, action}; it is the one reader of these rows, which pick-facts.sh
# marks as landed units.
#
# Each change to the record is told as an entry with record-append.sh, kind
# roadmap-status, after the body is written.
#
# A failed record write after the pull request opened (11, 12 or 13) leaves
# the pull request with no row: close it by hand before running --unit or
# --verdict again, which would open a second one on a new branch.
#
# Exit codes: 0 done (prints the pull request's URL, `verdict-owed TAG`, or the
# record's URL) or printed; 1 --confirm: the roadmap doesn't show it yet; 2 a
# read failed; 10 refused about the record (no found record, not a canonical
# one, or from the write core: not open, provenance, a directed transition);
# 11 a write failed; 12 the record changed between this script's read and its
# write; 13 the record is full; 14 the record was written but its entry
# wasn't posted; 64 usage (and any scope but a roadmap); 65 refused about the
# request: the tag, the feature's state, the entry, a pending pull request
# (the reason on stderr).
#
# GitHub calls:
#   reads:  gh issue view N --repo R --json body
#           gh api --method GET repos/R --jq .default_branch
#           gh api --method GET repos/R/git/ref/heads/<default> --jq .object.sha
#           gh api --method GET repos/R/contents/<roadmap>?ref=<that sha>   (--unit, --verdict)
#           gh api --method GET repos/R/contents/<roadmap>?ref=<Source>     (--verdict)
#           gh api --method GET repos/R/contents/<roadmap>?ref=<default>    (--confirm)
#   writes: gh api --method POST repos/R/git/refs -f ref=... -f sha=...
#           gh api --method PUT repos/R/contents/<roadmap> (message, content, sha, branch)
#           gh pr create --repo R --head <branch> --base <default> --title T --body-file F
#           the record, through record-write-core.sh; the entry, through record-append.sh
set -uo pipefail

PROG=roadmap-status
HERE=$(cd "$(dirname "$0")" && pwd)
SESSION= SCOPE= NAME= REPO= REF= ROADMAP= MODE= TAG= OUTCOME= REASON= ENTRY_IN= ENTRY_URL=
SKIP_CHECKS=0
ARG_ROADMAP=
OUTCOME_SET=0
# An entry file is at most this many bytes (milestone.sh's own cap).
ENTRY_MAX=16384

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
        --verdict) [ $# -ge 2 ] || usage; setmode verdict; TAG=$2; shift 2 ;;
        --confirm) [ $# -ge 2 ] || usage; setmode confirm; TAG=$2; shift 2 ;;
        --drop) [ $# -ge 2 ] || usage; setmode drop; TAG=$2; shift 2 ;;
        --list) setmode list; shift ;;
        --outcome) [ $# -ge 2 ] || usage; OUTCOME=$2; OUTCOME_SET=1; shift 2 ;;
        --reason) [ $# -ge 2 ] || usage; REASON=$2; shift 2 ;;
        --entry-file) [ $# -ge 2 ] || usage; ENTRY_IN=$2; shift 2 ;;
        --entry-url) [ $# -ge 2 ] || usage; ENTRY_URL=$2; shift 2 ;;
        --skip-session-checks) SKIP_CHECKS=1; shift ;;
        *) usage ;;
    esac
done
case "$MODE" in
    open) [ -z "$REASON$ENTRY_IN$ENTRY_URL" ] || usage ;;
    verdict) [ -n "$ENTRY_IN" ] && [ -n "$ENTRY_URL" ] && [ "$OUTCOME_SET" = 0 ] && [ -z "$REASON" ] || usage ;;
    drop) [ -n "$REASON" ] && [ "$OUTCOME_SET" = 0 ] && [ -z "$ENTRY_IN$ENTRY_URL" ] || usage ;;
    confirm|list) [ "$OUTCOME_SET" = 0 ] && [ -z "$REASON$ENTRY_IN$ENTRY_URL" ] || usage ;;
    *) usage ;;
esac
. "$HERE/record-common.sh"
lib_facts
[ -z "$ARG_ROADMAP" ] || { [ "$OVERRIDE" = 1 ] || usage; ROADMAP=$ARG_ROADMAP; }
[ "$SCOPE" = roadmap ] || { echo "$PROG: a feature's status is a roadmap's; this run's scope is $SCOPE" >&2; exit 64; }
lib_roadmap_path
lib_run_ref || { echo "$PROG: refused: the run has no found record" >&2; exit 10; }
RE_HEADING_TAG='^(Feature [0-9]+|[A-Za-z]+[0-9]+[a-z]?)$'
case "$MODE" in
    list) ;;
    verdict) [[ $TAG =~ $RE_HEADING_TAG ]] && [ "${#TAG}" -le 40 ] \
                 || { echo "$PROG: refused: $TAG is not a milestone's heading tag (Feature 7, ED1, AB10b)" >&2; exit 65; } ;;
    *) [[ $TAG =~ $RE_HEADING_TAG ]] || { echo "$PROG: $TAG is not a feature's heading tag (Feature 7, ED1, AB10b)" >&2; exit 64; } ;;
esac
case "$OUTCOME$REASON$ENTRY_URL" in *$'\n'*|*$'\r'*) echo "$PROG: --outcome, --reason and --entry-url are one line" >&2; exit 64 ;; esac

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
# The pending rows, {unit, pull_request, attempted, action, how_to_confirm}:
# the Target is `<TAG> [#n](URL)`. Three Actions are roadmap edits: a
# feature's Done (roadmap-status) and a milestone verdict's (milestone-done,
# milestone-verdict).
jq -c '[.side_effects[] | select(.action == "roadmap-status" or .action == "milestone-done" or .action == "milestone-verdict")
        | (.target | capture("^(?<unit>.+) (?<pr>\\[#[0-9]+\\]\\(https://github\\.com/[^)]+\\))$")) as $t
        | {unit: ($t.unit // .target), pull_request: ($t.pr // ""), attempted, action, how_to_confirm}]' "$WD/parsed.json" > "$WD/pending.json" \
    || lib_die2 "jq failed"
if [ "$MODE" = list ]; then
    jq -c 'map(del(.how_to_confirm))' "$WD/pending.json"
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
# text is kept outside $WD. Only this script changes a verdict-owed Work row
# (the write core holds every other writer to that).
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
    VERDICT_WRITER=1
    core_write > /dev/null
    if ! bash "$HERE/record-append.sh" "${ADDR[@]}" --kind roadmap-status --text-file "$ENTRY_FILE" > /dev/null; then
        echo "$PROG: the record was written, but its entry wasn't posted; post it with record-append.sh --kind roadmap-status: $(cat "$ENTRY_FILE")" >&2
        rm -f "$ENTRY_FILE"; exit 14
    fi
    rm -f "$ENTRY_FILE"
}
# without_row <out> [clear-owed]: the record without TAG's pending row, and
# with clear-owed also without TAG's verdict-owed Work row.
without_row() {
    jq --arg t "$TAG" --argjson owed "${2:-false}" 'del(.written)
        | .side_effects = [.side_effects[] | select(((.action == "roadmap-status" or .action == "milestone-done" or .action == "milestone-verdict")
                                                     and (.target | startswith($t + " ["))) | not)]
        | if $owed then .work = [(.work // [])[] | select((.kind == "verdict-owed" and .item == $t) | not)]
                        | (if (.work | length) == 0 then del(.work) else . end)
          else . end' \
        "$WD/parsed.json" > "$1" || lib_die2 "jq failed"
}
# head_read: BASE_SHA, the default branch's head, and the roadmap and its
# blob at that one commit, so the branch, the content edited and the sha the
# commit replaces all agree even if the default branch moves meanwhile.
head_read() {
    BASE_SHA=$(gh api --method GET "repos/$REPO/git/ref/heads/$DEFAULT_BRANCH" --jq .object.sha 2> /dev/null < /dev/null) || lib_die2 "cannot read the head of $DEFAULT_BRANCH"
    [[ $BASE_SHA =~ $RE_SHA ]] || lib_die2 "the head of $DEFAULT_BRANCH is not a sha"
    gh api --method GET "repos/$REPO/contents/$ROADMAP?ref=$BASE_SHA" > "$WD/contents.json" 2> "$WD/c.err" < /dev/null \
        || lib_die2 "cannot read $ROADMAP at $BASE_SHA: $(lib_scrub < "$WD/c.err")"
    BLOB=$(jq -r '.sha // empty' "$WD/contents.json")
    # The contents API leaves a file over one megabyte without its content.
    [ -n "$(jq -r '.content // empty' "$WD/contents.json")" ] || lib_die2 "the contents API gave no content for $ROADMAP (a file over 1 MB?)"
    [[ $BLOB =~ $RE_SHA ]] || lib_die2 "$ROADMAP's blob sha is not a sha"
    jq -r '.content // ""' "$WD/contents.json" > "$WD/roadmap.b64" && lib_b64d "$WD/roadmap.b64" "$WD/roadmap.md" || lib_die2 "cannot decode $ROADMAP"
}
# populate_and_commit <doc> <crlf> <branch-prefix> <message>: the generated
# sections regenerated, the CRLF endings restored, and the commit on a new
# branch from BASE_SHA. Sets BRANCH_NEW.
populate_and_commit() {
    (cd "$(dirname "$1")" && shirabe roadmap populate "$(basename "$1")" > /dev/null 2> "$WD/populate.err") \
        || lib_die2 "shirabe roadmap populate failed: $(lib_scrub < "$WD/populate.err")"
    if [ "$2" = 1 ]; then sed 's/$/\r/' "$1" > "$1.crlf" && mv "$1.crlf" "$1"; fi
    local slug
    slug=$(printf '%s' "$TAG" | tr 'A-Z' 'a-z' | tr -c 'a-z0-9\n' '-')
    BRANCH_NEW="$3-$slug-$(date -u +%Y%m%d%H%M)"
    gh api --method POST "repos/$REPO/git/refs" -f "ref=refs/heads/$BRANCH_NEW" -f "sha=$BASE_SHA" > /dev/null 2> "$WD/w.err" < /dev/null \
        || { echo "$PROG: creating $BRANCH_NEW failed: $(lib_scrub < "$WD/w.err")" >&2; exit 11; }
    base64 < "$1" | tr -d '\n\r ' > "$WD/content"
    gh api --method PUT "repos/$REPO/contents/$ROADMAP" -f "message=$4" \
        -f "content=$(cat "$WD/content")" -f "sha=$BLOB" -f "branch=$BRANCH_NEW" > /dev/null 2> "$WD/w.err" < /dev/null \
        || { echo "$PROG: the commit to $BRANCH_NEW failed: $(lib_scrub < "$WD/w.err")" >&2; exit 11; }
}
# open_pr <title>: the pull request from BRANCH_NEW, its body in $WD/prbody.md.
# Sets PR_URL and PR_NUM.
open_pr() {
    PR_URL=$(gh pr create --repo "$REPO" --head "$BRANCH_NEW" --base "$DEFAULT_BRANCH" --title "$1" \
        --body-file "$WD/prbody.md" 2> "$WD/w.err" < /dev/null) \
        || { echo "$PROG: opening the pull request failed: $(lib_scrub < "$WD/w.err")" >&2; exit 11; }
    PR_NUM=${PR_URL##*/}
    [[ $PR_NUM =~ $RE_NUM ]] || lib_die2 "gh pr create printed no pull request URL"
}
# pending_refuse: one roadmap pull request at a time, since two would
# conflict in the generated sections.
pending_refuse() {
    [ "$(jq length "$WD/pending.json")" = 0 ] \
        || refuse "a roadmap pull request is already pending ($(jq -r 'map("\(.unit) \(.pull_request)") | join(", ")' "$WD/pending.json")); confirm or drop it first, since two would conflict in the generated sections"
}
# follow_up_refuse: a unit whose scoping alone landed still has its
# execution to come: its follow-up Work row stands until a holding takes it.
follow_up_refuse() {
    local fu
    fu=$(jq -r --arg t "$TAG" '[(.work // [])[] | select(.kind == "follow-up" and .item == $t) | .who][0] // empty' "$WD/parsed.json")
    [ -z "$fu" ] || refuse "$TAG's scoping alone landed ($fu) and its execution is a follow-up still to dispatch; it isn't Done until that lands"
}
OWED_WHO=$(jq -r --arg t "$TAG" '[(.work // [])[] | select(.kind == "verdict-owed" and .item == $t) | .who][0] // empty' "$WD/parsed.json")

case "$MODE" in
confirm|drop)
    ROW=$(jq -c --arg t "$TAG" '[.[] | select(.unit == $t)][0] // empty' "$WD/pending.json")
    [ -n "$ROW" ] || refuse "no roadmap pull request is pending for $TAG"
    ACTION=$(printf '%s' "$ROW" | jq -r .action)
    PRL=$(printf '%s' "$ROW" | jq -r .pull_request)
    if [ "$MODE" = confirm ]; then
        lib_file_at "$ROADMAP" "$DEFAULT_BRANCH" "$WD/roadmap.md"
        case $? in 0) ;; 1) lib_die2 "$ROADMAP is not on $DEFAULT_BRANCH" ;; *) lib_die2 "cannot read $ROADMAP" ;; esac
        if [ "$ACTION" = milestone-verdict ]; then
            URL=$(printf '%s' "$ROW" | jq -r '.how_to_confirm | capture(" carries (?<u>[^ ]+) in Progress$").u // empty')
            [ -n "$URL" ] || lib_die2 "$TAG's milestone-verdict row names no entry URL in its How to confirm"
            bash "$HERE/milestone.sh" progress-has "$WD/roadmap.md" "$URL"
            case $? in
                0) ;;
                1) echo "$PROG: $ROADMAP on $DEFAULT_BRANCH carries no Progress line for $URL; its pull request, $PRL, hasn't landed" >&2; exit 1 ;;
                *) lib_die2 "cannot read $ROADMAP's Progress section" ;;
            esac
            ST="its verdict's Progress line"
        else
            feature_read "$WD/roadmap.md"
            ST=$(printf '%s' "$FEATURE" | jq -r '.status // empty')
            [ "$(printf '%s' "$FEATURE" | jq -r '.done // false')" = true ] \
                || { echo "$PROG: $TAG reads ${ST:-no status} on $DEFAULT_BRANCH; its pull request, $PRL, hasn't landed" >&2; exit 1; }
        fi
        case "$ACTION" in
            milestone-*)
                without_row "$WD/next.json" true
                write_record "$WD/next.json" "$TAG reads $ST on $DEFAULT_BRANCH; its verdict's roadmap pull request $PRL landed, and the record no longer holds it or $TAG's verdict owed." ;;
            *)
                without_row "$WD/next.json"
                write_record "$WD/next.json" "$TAG reads $ST on $DEFAULT_BRANCH; its roadmap pull request $PRL landed, and the record no longer holds it." ;;
        esac
    else
        without_row "$WD/next.json"
        write_record "$WD/next.json" "$TAG's roadmap pull request $PRL is dropped: $REASON"
    fi
    echo "https://github.com/$REPO/issues/$REF"
    exit 0
    ;;
esac

if [ "$MODE" = verdict ]; then
    # ---- --verdict: the roadmap edit a checked verdict calls for ----------
    [ -r "$ENTRY_IN" ] && [ -f "$ENTRY_IN" ] || refuse "cannot read the entry file $ENTRY_IN"
    SIZE=$(wc -c < "$ENTRY_IN" | tr -d ' ')
    [ "$SIZE" -le "$ENTRY_MAX" ] || refuse "the entry file is $SIZE bytes, over $ENTRY_MAX"
    case "$ENTRY_URL" in
        "https://github.com/$REPO/issues/$REF#issuecomment-"*) ;;
        *) refuse "--entry-url is not a comment on this run's record, https://github.com/$REPO/issues/$REF#issuecomment-<id>" ;;
    esac
    [[ ${ENTRY_URL##*#issuecomment-} =~ ^[1-9][0-9]*$ ]] || refuse "--entry-url's comment id is not a number"
    [ -n "$OWED_WHO" ] || refuse "$TAG has no verdict-owed row: tick landed for it first, which writes one"
    pending_refuse
    # The roadmap at the entry's Source commit, the copy its clauses were
    # judged against.
    SRC_LINE=$(sed -n 4p "$ENTRY_IN")
    RE_SRC='^Source: ([^ ]+) at ([0-9a-f]{40})$'
    [[ $SRC_LINE =~ $RE_SRC ]] || refuse "the entry's line 4 is not \`Source: <roadmap path> at <40-character commit>\`"
    SRC_PATH=${BASH_REMATCH[1]} SRC_COMMIT=${BASH_REMATCH[2]}
    [ "$SRC_PATH" = "$ROADMAP" ] || refuse "the entry's Source is $SRC_PATH, not this run's roadmap, $ROADMAP"
    lib_file_at "$ROADMAP" "$SRC_COMMIT" "$WD/source.md"
    case $? in
        0) ;;
        1) refuse "$ROADMAP is not at the entry's Source commit, $SRC_COMMIT" ;;
        *) lib_die2 "cannot read $ROADMAP at $SRC_COMMIT" ;;
    esac
    set -- check-verdict "$WD/source.md" "$TAG" "$ENTRY_IN"
    [ "$OWED_WHO" = none ] || set -- "$@" --worker "$OWED_WHO"
    bash "$HERE/milestone.sh" "$@" > "$WD/verdict.json" 2> "$WD/check.err"
    case $? in
        0) ;;
        1|2) refuse "the entry doesn't pass milestone.sh check-verdict: $(lib_scrub < "$WD/check.err")" ;;
        *) lib_die2 "milestone.sh check-verdict failed: $(lib_scrub < "$WD/check.err")" ;;
    esac
    VERDICT=$(jq -r .verdict "$WD/verdict.json")
    CHECKER=$(jq -r .checked_by "$WD/verdict.json")
    CHECKED_ON=$(jq -r .checked_on "$WD/verdict.json")
    [ "$VERDICT" != "verified with follow-ups" ] \
        || refuse "a verified-with-follow-ups verdict adds its follow-up milestones in the same edit, which this writer doesn't do yet; record verified or changes needed, or defer the verdict"
    head_read
    bash "$HERE/milestone.sh" evidence "$WD/roadmap.md" "$TAG" > "$WD/milestone.json" 2> "$WD/m.err" \
        || refuse "$TAG is not a milestone with Evidence on $DEFAULT_BRANCH: $(lib_scrub < "$WD/m.err")"
    TITLE=$(jq -r .title "$WD/milestone.json")
    case "$(jq -r .status "$WD/milestone.json")" in Done*) refuse "$TAG already reads Done on $DEFAULT_BRANCH" ;; esac
    grep -qE $'^## Progress[ \t\r]*$' "$WD/roadmap.md" || refuse "$ROADMAP has no ## Progress section for the verdict's line"
    if command -v sha256sum > /dev/null 2>&1; then HASH=$(sha256sum < "$ENTRY_IN" | cut -c1-8)
    else HASH=$(shasum -a 256 < "$ENTRY_IN" | cut -c1-8); fi
    PROGRESS="- $CHECKED_ON: $TAG -- $VERDICT, checked by $CHECKER ($ENTRY_URL, $HASH)"
    DONE=0 DELIVER=
    if [ "$VERDICT" = verified ]; then
        DONE=1
        # The Work checked pull requests the Delivered line doesn't name yet.
        DELIVER=$(jq -r '.work_checked | join("\n")' "$WD/verdict.json" | while IFS= read -r item; do
            [ -n "$item" ] || continue
            tr -d '\r' < "$WD/roadmap.md" | RS_TAG="$TAG" RS_ITEM="$item" awk '
                BEGIN { tag = ENVIRON["RS_TAG"]; item = ENVIRON["RS_ITEM"] }
                # names(s): s names item as a whole reference (#1 is not #12).
                function names(s,   p) {
                    while ((p = index(s, item)) > 0) {
                        if (substr(s, p + length(item), 1) !~ /[0-9]/) return 1
                        s = substr(s, p + 1)
                    }
                    return 0
                }
                /^## / { infeat = ($0 ~ /^## Features[ \t]*$/); inblock = 0; next }
                infeat && /^### / { inblock = (index($0, "### " tag ": ") == 1); indel = 0; next }
                inblock && /^\*\*Delivered:\*\*/ { indel = 1 }
                inblock && indel && (/^[ \t]*$/ || (/^\*\*[A-Z][A-Za-z ]*:\*\*/ && !/^\*\*Delivered:\*\*/)) { indel = 0 }
                indel && names($0) { found = 1 }
                END { exit(found ? 1 : 0) }' && printf '%s, ' "$item"
        done)
        DELIVER=${DELIVER%, }
    fi
    mkdir -p "$WD/doc"
    DOC="$WD/doc/$(basename "$ROADMAP")"
    CRLF=0
    grep -q $'\r$' "$WD/roadmap.md" && CRLF=1
    # TAG's Status, Needs and Delivered lines and the Progress section, and
    # nothing else before the populate. Values reach awk through the
    # environment, which takes them as written.
    tr -d '\r' < "$WD/roadmap.md" | RS_TAG="$TAG" RS_DONE="$DONE" RS_DELIVER="$DELIVER" RS_PROGRESS="$PROGRESS" awk '
        BEGIN { tag = ENVIRON["RS_TAG"]; done = ENVIRON["RS_DONE"] == "1"; deliver = ENVIRON["RS_DELIVER"]; progress = ENVIRON["RS_PROGRESS"] }
        function field_end() { return ($0 ~ /^[ \t]*$/ || $0 ~ /^\*\*[A-Z][A-Za-z ]*:\*\*/ || $0 ~ /^#+([ \t]|$)/) }
        # The Delivered field held back, so the last of its lines takes the new items.
        function flush_delivered() { if (nd) { dl[nd] = dl[nd] ", " deliver; for (i = 1; i <= nd; i++) print dl[i]; nd = 0 } }
        # The Progress section held back, so the new line goes after its last non-blank line.
        function flush_progress(   i, last) {
            last = 0; for (i = 1; i <= np; i++) if (pl[i] !~ /^[ \t]*$/) last = i
            if (last == 0) { print ""; print progress; for (i = 1; i <= np; i++) print pl[i]; if (np == 0 && more) print "" }
            else { for (i = 1; i <= last; i++) print pl[i]; print progress; for (i = last + 1; i <= np; i++) print pl[i]; if (last == np && more) print "" }
            np = 0; inprog = 0; wrote = 1
        }
        dropping && field_end() { dropping = 0 }
        dropping { next }
        nd && field_end() { flush_delivered() }
        nd { dl[++nd] = $0; next }
        /^## / {
            if (inprog) { more = 1; flush_progress() }
            infeat = ($0 ~ /^## Features[ \t]*$/); inblock = 0
            print
            if ($0 ~ /^## Progress[ \t]*$/ && !wrote) { inprog = 1; np = 0; more = 0 }
            next
        }
        inprog { pl[++np] = $0; next }
        infeat && /^### / { inblock = (index($0, "### " tag ": ") == 1); print; next }
        inblock && done && /^\*\*Needs:\*\*/ { dropping = 1; next }
        inblock && done && deliver != "" && /^\*\*Delivered:\*\*/ { nd = 1; dl[1] = $0; hasdel = 1; next }
        inblock && done && /^\*\*Status:\*\*/ { print "**Status:** Done"; statusdone = 1; next }
        { print }
        END {
            flush_delivered()
            if (inprog) { more = 0; flush_progress() }
        }' > "$DOC.1" || lib_die2 "awk failed"
    # A verified milestone with no Delivered line gets one after its Status.
    if [ "$DONE" = 1 ] && [ -n "$DELIVER" ] && ! awk -v t="### $TAG: " '
            /^## / { infeat = ($0 ~ /^## Features[ \t]*$/); inb = 0; next }
            infeat && /^### / { inb = (index($0, t) == 1); next }
            inb && /^\*\*Delivered:\*\*/ { f = 1 }
            END { exit(f ? 0 : 1) }' "$DOC.1"; then
        RS_TAG="$TAG" RS_DELIVER="$DELIVER" awk '
            BEGIN { tag = ENVIRON["RS_TAG"]; deliver = ENVIRON["RS_DELIVER"] }
            /^## / { infeat = ($0 ~ /^## Features[ \t]*$/); inb = 0; print; next }
            infeat && /^### / { inb = (index($0, "### " tag ": ") == 1); print; next }
            inb && /^\*\*Status:\*\*/ { print; print "**Delivered:** " deliver; next }
            { print }' "$DOC.1" > "$DOC" || lib_die2 "awk failed"
    else
        mv "$DOC.1" "$DOC"
    fi
    bash "$HERE/milestone.sh" progress-has "$DOC" "$PROGRESS" || refuse "the Progress line could not be written into $ROADMAP"
    if [ "$DONE" = 1 ]; then
        bash "$HERE/milestone.sh" evidence "$DOC" "$TAG" 2> /dev/null | jq -e '.status == "Done"' > /dev/null \
            || refuse "$TAG's Status could not be set to Done (its block has no **Status:** line?)"
    fi
    if [ "$DONE" = 1 ]; then
        MSG="docs(roadmap): record $TAG, $TITLE, as done on its verdict"
    else
        MSG="docs(roadmap): record the changes-needed verdict on $TAG, $TITLE"
    fi
    populate_and_commit "$DOC" "$CRLF" coordinate/roadmap-verdict "$MSG"
    {
        if [ "$DONE" = 1 ]; then
            printf 'Records the verified verdict on %s of the roadmap, %s: its Status is Done, its Needs line goes and its Delivered line names the work checked; a Progress line names the verdict, who checked it and the entry. Its Outcome and Evidence are unchanged, and the generated sections are regenerated.\n' "$TAG" "$TITLE"
        else
            printf 'Records the changes-needed verdict on %s of the roadmap, %s: a Progress line names the verdict, who checked it and the entry. Its Status and Delivered line are unchanged; the milestone stays open for the changes the verdict names.\n' "$TAG" "$TITLE"
        fi
        printf '\nThe verdict entry, as posted on the record (%s):\n\n' "$ENTRY_URL"
        sed -e 's/&/\&amp;/g' -e 's/@/\&#64;/g' -e 's/^/> /' "$ENTRY_IN"
        printf '\n---\n\n'
        printf 'Opened by the coordinator for %s from its record, issue #%s. Review the verdict against the milestone'"'"'s Evidence before merging: on a milestone roadmap this pull request is what sets the Status, and the coordinator never merges it.\n' "$NAME" "$REF"
    } > "$WD/prbody.md"
    if [ "$DONE" = 1 ]; then open_pr "docs(roadmap): record $TAG, $TITLE, as done on its verdict"
    else open_pr "docs(roadmap): record the changes-needed verdict on $TAG, $TITLE"; fi
    if [ "$DONE" = 1 ]; then ACTION=milestone-done HOW="the roadmap on $DEFAULT_BRANCH reads $TAG Done"
    else ACTION=milestone-verdict HOW="the roadmap on $DEFAULT_BRANCH carries $ENTRY_URL in Progress"; fi
    jq --arg t "$TAG [#$PR_NUM]($PR_URL)" --arg at "$(date -u +%Y-%m-%dT%H:%MZ)" --arg a "$ACTION" --arg h "$HOW" '
        del(.written) | .side_effects += [{action: $a, target: $t, verified_head: "", attempted: $at, how_to_confirm: $h}]' \
        "$WD/parsed.json" > "$WD/next.json" || lib_die2 "jq failed"
    URL_OUT=$PR_URL
    write_record "$WD/next.json" "$TAG's verdict, $VERDICT, checked by $CHECKER ($ENTRY_URL), is on its roadmap pull request $PR_URL. Its verdict stays owed, and pick passes over $TAG, until that merges and is confirmed."
    printf '%s\n' "$URL_OUT"
    exit 0
fi

# ---- --unit ------------------------------------------------------------------
head_read
SCHEMA=$(bash "$HERE/milestone.sh" schema "$WD/roadmap.md") || lib_die2 "cannot read $ROADMAP's schema"

if [ "$SCHEMA" = roadmap/v2 ]; then
    # A milestone roadmap: the verdict, not the merge, sets Done.
    bash "$HERE/milestone.sh" evidence "$WD/roadmap.md" "$TAG" > "$WD/milestone.json" 2> "$WD/m.err" \
        || refuse "$TAG is not a milestone with Evidence on $ROADMAP: $(lib_scrub < "$WD/m.err")"
    case "$(jq -r .status "$WD/milestone.json")" in
        Done*|Dropped*) refuse "$TAG already reads $(jq -r .status "$WD/milestone.json")" ;;
    esac
    follow_up_refuse
    if [ -n "$OWED_WHO" ]; then
        echo "verdict-owed $TAG"
        exit 0
    fi
    WHO=$(jq -r --arg t "$TAG" '[.holdings[] | select(.unit == $t or (.unit | startswith($t + ": "))) | .worker][0] // "none"' "$WD/parsed.json")
    TODAY=$(date -u +%Y-%m-%d)
    jq --arg t "$TAG" --arg w "$WHO" --arg n "verdict owed since $TODAY" --arg u "$(date -u +%Y-%m-%dT%H:%MZ)" '
        del(.written) | .work = ((.work // []) + [{item: $t, kind: "verdict-owed", who: $w, next: $n, wakes: "0", updated: $u}])' \
        "$WD/parsed.json" > "$WD/next.json" || lib_die2 "jq failed"
    if [ "$WHO" = none ]; then BYWHO="no holding names it"; else BYWHO="$WHO held it"; fi
    write_record "$WD/next.json" "$TAG's work is finished ($BYWHO); its verdict is owed. On a milestone roadmap no pull request sets it Done: its verdict, checked against its Evidence, does. Pick passes over $TAG until that verdict's roadmap edit is confirmed."
    echo "verdict-owed $TAG"
    exit 0
fi

# A feature roadmap: the Done pull request, as before.
[ "$OUTCOME_SET" = 1 ] && [ -n "$OUTCOME" ] || usage
follow_up_refuse
pending_refuse
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
populate_and_commit "$DOC" "$CRLF" coordinate/roadmap-status "docs(roadmap): record $TAG, $TITLE, as done"
{
    printf 'Records %s of the roadmap, %s, as done: its Status is Done and its Delivered line reads "%s"; its Outcome, the promise, is unchanged. Its Needs line goes, as the roadmap'"'"'s rule for done features asks, and the generated sections are regenerated. Nothing else in the roadmap changes.\n\n---\n\n' "$TAG" "$TITLE" "$OUTCOME"
    printf 'Opened by the coordinator for %s from its record, issue #%s, after it judged the feature'"'"'s last pull request landed. Review it against the roadmap'"'"'s own rules for an Active document before merging; the coordinator never merges it.\n' "$NAME" "$REF"
} > "$WD/prbody.md"
open_pr "docs(roadmap): record $TAG, $TITLE, as done"

jq --arg t "$TAG [#$PR_NUM]($PR_URL)" --arg at "$(date -u +%Y-%m-%dT%H:%MZ)" --arg d "$DEFAULT_BRANCH" --arg tag "$TAG" '
    del(.written) | .side_effects += [{action: "roadmap-status", target: $t, verified_head: "", attempted: $at,
        how_to_confirm: "the roadmap on \($d) reads \($tag) Done"}]' "$WD/parsed.json" > "$WD/next.json" || lib_die2 "jq failed"
printf '%s\n' "$PR_URL" > "$WD/url"
URL_OUT=$(cat "$WD/url")
write_record "$WD/next.json" "$TAG landed; its roadmap pull request $PR_URL sets its Status to Done with the Delivered line \"$OUTCOME\". Pick passes over $TAG until it merges."
printf '%s\n' "$URL_OUT"
