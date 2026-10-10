#!/usr/bin/env bash
# roadmap-status.sh -- write a landed feature's Status and Delivered line back
# to the roadmap as a pull request, and keep the record saying it is pending;
# on a milestone roadmap, mark the milestone's verdict owed, open the one
# roadmap edit a checked verdict calls for, and open the edit that sends a
# Done milestone back to In progress on a checked failure. Agent-run, at
# roadmap scope only
# (docs/designs/current/DESIGN-coordinate-record-container.md, Decision 4;
# docs/designs/DESIGN-milestone-verdicts.md, Decisions 1 and 3).
#
# Usage:
#   roadmap-status.sh --session S --unit TAG [--outcome TEXT]
#   roadmap-status.sh --session S --verdict TAG --entry-file F --entry-url URL [--follow-ups FILE]
#   roadmap-status.sh --session S --reopen TAG --entry-file F --entry-url URL
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
# TAG's verdict-owed row, re-reads the comment at URL (GitHub's comment API),
# which must be on this run's record issue, carry the milestone-verdict entry
# marker and hold F's text exactly (both with CR and outer blank lines
# dropped), requires the default branch to contain the commit the entry's
# Source line names (the compare API: identical or ahead), reads the roadmap
# at that commit (whose path must be this run's roadmap) and runs
# milestone.sh check-verdict against it, with --worker the row's Who unless
# that is `none`. It refuses (exit 65, nothing opened) a TAG outside the
# heading-tag grammar, one with no verdict-owed row, an entry file over 16
# KiB, an entry URL that isn't a comment on the record issue, a comment whose
# text or kind isn't the entry's, a Source commit the default branch doesn't
# contain, an entry check-verdict refuses (a checker or Work checked value
# outside its closed shape among them), a changes-needed verdict whose rework
# text (below) the record couldn't hold, a TAG already reading Done on the
# default branch, TAG's Evidence on the default branch differing from its
# Evidence at Source (clauses are numbered by position, so a judgment is
# never applied to Evidence it wasn't made against), and any roadmap pull
# request already pending.
#
# A verified-with-follow-ups verdict needs --follow-ups FILE (and no other
# verdict takes it): at most 32 KiB, one `### <tag>: <title>` section per
# follow-up with non-empty Outcome, Evidence (`- ` clauses), Left open and
# Dependencies fields, and optionally Needs, nothing else. A `new: <title>`
# follow-up is the section with that title, under a tag the roadmap doesn't
# use; an `amend <tag>: <what>` follow-up is the section with that tag, a
# milestone the roadmap has (never TAG itself), with its title and
# Dependencies unchanged. FILE is refused for a section the verdict doesn't
# name, a follow-up with no section, a missing field, a control character or
# tab, a token, a home-directory path or a work-in-progress path.
#
# For either verified verdict the edit sets TAG's Status to Done, removes its
# Needs line and appends the Work checked pull requests to its Delivered line
# (adding the line after Status when there is none); for verified with
# follow-ups it also replaces each amended milestone's Outcome, Evidence and
# Left open with its section's and adds each new section, Status Not
# started, after the last milestone. For changes needed it leaves Status and
# Delivered as they are. Either way it appends to `## Progress`
#
#   - <Checked on>: <TAG> -- <verdict>, checked by <checker> (<URL>, <hash8>)
#
# where hash8 is the first eight hex digits of the posted entry's sha256, and
# for each amendment `- <Checked on>: <tag> amended -- a follow-up of the
# verified verdict on <TAG> (<URL>)`; runs `shirabe roadmap populate`,
# commits on coordinate/roadmap-verdict-<tag>-<second>, and opens one pull
# request whose body carries the whole entry, so whoever merges it reviews
# the judgment. It writes a Side effects row: Action `milestone-done` (How to
# confirm `the roadmap on <default> reads <TAG> Done`) for a verified verdict
# of either kind, `milestone-verdict` (How to confirm `the roadmap on
# <default> carries <URL> in Progress`) for changes needed. It never merges.
#
# --reopen opens the roadmap edit a failure reported against a Done milestone
# calls for. F is the failure entry as posted with record-append.sh --kind
# milestone-failure, at most 16 KiB, and URL that comment's URL on this run's
# record issue, bound to F as --verdict binds its entry (the comment must
# carry the milestone-failure marker). It refuses (exit 65, nothing opened)
# while any roadmap pull request is pending, so a second failure recorded
# while a reopen edit is pending opens nothing, and an entry milestone.sh
# check-failure refuses against the roadmap at the default branch's head
# (TAG not reading Done, a clause out of range, a reporter or What was seen
# outside its closed shape). The edit sets TAG's Status to In progress,
# leaves its Delivered, Outcome and Evidence as they are, and appends to
# `## Progress`
#
#   - <Seen on>: <TAG> -- reopened: clause <n> failed, reported by <reporter> (<URL>, <hash8>)
#
# then runs `shirabe roadmap populate`, commits on
# coordinate/roadmap-reopen-<tag>-<second> and opens one pull request whose
# body carries the entry, so whoever merges it reviews the report. It writes
# a Side effects row, Action `milestone-reopen`, How to confirm `the roadmap
# on <default> reads <TAG> In progress`, and never merges. It prints the pull
# request's URL and then `held-dependent <tag> <worker>` for each milestone
# whose Dependencies name TAG (as pick reads them, soft ones aside) and that
# a holding covers: that worker's milestone reads blocked again once the
# edit lands, and the coordinator tells its owner.
#
# --confirm removes TAG's row once the roadmap on the default branch shows
# it, by the row's Action: `roadmap-status` and `milestone-done` read Done,
# Shipped or Dropped for TAG, annotated or not (`Done -- shipped in #12`);
# `milestone-verdict` finds the entry's URL in `## Progress` (milestone.sh
# progress-has); `milestone-reopen` reads TAG In progress, and the last
# Progress line naming TAG must be a reopen line whose entry URL is on this
# run's record and whose hash8 the posted milestone-failure comment still
# hashes to. Confirming a milestone row also removes TAG's verdict-owed
# and rework Work rows. Confirming a `milestone-reopen` row writes a rework
# Work row for TAG (Who `failure <comment id>`) whose Next step is
# `Evidence clause <n> failed: <what was seen>`, cut to the codec's 600
# bytes (rework_cap). Confirming a `milestone-verdict` (changes needed)
# row re-reads its entry, which must still hash to its Progress line's
# hash8, and writes a rework Work row for TAG (Who `verdict <comment id>`)
# whose Next step is the rework text: `Evidence clauses not held: <n, n>.`,
# `The work does not fit the strategy.` when it doesn't, and `Changes
# needed: <the line>`, one paragraph the codec holds to 600 bytes with no URL
# or link. pick-facts.sh reports it, render-brief.sh quotes it into the
# milestone's next brief, and dispatch-worker.sh removes it once a worker is
# dispatched. While the default branch doesn't show it: exit 1, nothing
# written. --drop removes a row of any of the four Actions with a reason,
# for a pull request closed unmerged, and leaves a verdict-owed row
# standing; the entry is still on the record, so --verdict or --reopen can
# open the edit again from it.
# --list prints the pending rows as a JSON array of {unit, pull_request,
# attempted, action}; it is the one reader of these rows, which pick-facts.sh
# marks as landed units.
#
# Each change to the record is told as an entry with record-append.sh, kind
# roadmap-status, after the body is written.
#
# A failed record write after the pull request opened (11, 12 or 13) leaves
# the pull request with no row: close it by hand before running --unit,
# --verdict or --reopen again, which would open a second one on a new branch.
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
#           gh api --method GET repos/R/contents/<roadmap>?ref=<that sha>   (--unit, --verdict, --reopen)
#           gh api --method GET repos/R/contents/<roadmap>?ref=<Source>     (--verdict)
#           gh api --method GET repos/R/compare/<Source>...<head sha>       (--verdict)
#           gh api --method GET repos/R/issues/comments/<id>               (--verdict, --reopen, --confirm)
#           gh api --method GET repos/R/contents/<roadmap>?ref=<default>    (--confirm)
#   writes: gh api --method POST repos/R/git/refs -f ref=... -f sha=...
#           gh api --method PUT repos/R/contents/<roadmap> (message, content, sha, branch)
#           gh pr create --repo R --head <branch> --base <default> --title T --body-file F
#           the record, through record-write-core.sh; the entry, through record-append.sh
set -uo pipefail

PROG=roadmap-status
HERE=$(cd "$(dirname "$0")" && pwd)
SESSION= SCOPE= NAME= REPO= REF= ROADMAP= MODE= TAG= OUTCOME= REASON= ENTRY_IN= ENTRY_URL= FOLLOW_UPS=
SKIP_CHECKS=0
ARG_ROADMAP=
OUTCOME_SET=0
# An entry file is at most this many bytes (milestone.sh's own cap), and a
# follow-ups file at most this many.
ENTRY_MAX=16384
FOLLOW_UPS_MAX=32768
# A verdict's branch carries the second, so an edit opened again after --drop
# (its pull request closed unmerged, its branch left) gets a branch of its own.
BRANCH_STAMP=%Y%m%d%H%M

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
        --reopen) [ $# -ge 2 ] || usage; setmode reopen; TAG=$2; shift 2 ;;
        --confirm) [ $# -ge 2 ] || usage; setmode confirm; TAG=$2; shift 2 ;;
        --drop) [ $# -ge 2 ] || usage; setmode drop; TAG=$2; shift 2 ;;
        --list) setmode list; shift ;;
        --outcome) [ $# -ge 2 ] || usage; OUTCOME=$2; OUTCOME_SET=1; shift 2 ;;
        --reason) [ $# -ge 2 ] || usage; REASON=$2; shift 2 ;;
        --entry-file) [ $# -ge 2 ] || usage; ENTRY_IN=$2; shift 2 ;;
        --entry-url) [ $# -ge 2 ] || usage; ENTRY_URL=$2; shift 2 ;;
        --follow-ups) [ $# -ge 2 ] || usage; FOLLOW_UPS=$2; shift 2 ;;
        --skip-session-checks) SKIP_CHECKS=1; shift ;;
        *) usage ;;
    esac
done
case "$MODE" in
    open) [ -z "$REASON$ENTRY_IN$ENTRY_URL$FOLLOW_UPS" ] || usage ;;
    verdict) [ -n "$ENTRY_IN" ] && [ -n "$ENTRY_URL" ] && [ "$OUTCOME_SET" = 0 ] && [ -z "$REASON" ] || usage ;;
    reopen) [ -n "$ENTRY_IN" ] && [ -n "$ENTRY_URL" ] && [ "$OUTCOME_SET" = 0 ] && [ -z "$REASON$FOLLOW_UPS" ] || usage ;;
    drop) [ -n "$REASON" ] && [ "$OUTCOME_SET" = 0 ] && [ -z "$ENTRY_IN$ENTRY_URL$FOLLOW_UPS" ] || usage ;;
    confirm|list) [ "$OUTCOME_SET" = 0 ] && [ -z "$REASON$ENTRY_IN$ENTRY_URL$FOLLOW_UPS" ] || usage ;;
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
    verdict|reopen) [[ $TAG =~ $RE_HEADING_TAG ]] && [ "${#TAG}" -le 40 ] \
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
# the Target is `<TAG> [#n](URL)`. Four Actions are roadmap edits: a
# feature's Done (roadmap-status), a milestone verdict's (milestone-done,
# milestone-verdict) and a milestone's reopen (milestone-reopen).
EDIT_ACTIONS='["roadmap-status", "milestone-done", "milestone-verdict", "milestone-reopen"]'
jq -c --argjson acts "$EDIT_ACTIONS" '[.side_effects[] | select(.action as $a | any($acts[]; . == $a))
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
# with clear-owed also without TAG's verdict-owed and rework Work rows (a
# confirmed verdict or reopen supersedes the rework an earlier one left).
without_row() {
    jq --arg t "$TAG" --argjson owed "${2:-false}" --argjson acts "$EDIT_ACTIONS" 'del(.written)
        | .side_effects = [.side_effects[] | select(((.action as $a | any($acts[]; . == $a))
                                                     and (.target | startswith($t + " ["))) | not)]
        | if $owed then .work = [(.work // [])[] | select(((.kind == "verdict-owed" or .kind == "rework") and .item == $t) | not)]
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
    BRANCH_NEW="$3-$slug-$(date -u +"$BRANCH_STAMP")"
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

# norm_entry <in> <out>: an entry's text as record-append.sh posts it: CR
# dropped, leading and trailing blank lines dropped, one final line break.
norm_entry() {
    tr -d '\r' < "$1" | awk '{ l[NR] = $0 } END { s = 1; while (s <= NR && l[s] ~ /^[ \t]*$/) s++
        e = NR; while (e >= s && l[e] ~ /^[ \t]*$/) e--; for (i = s; i <= e; i++) print l[i] }' > "$2"
}
# sha8 <file>: the first eight hex digits of its sha256.
sha8() {
    if command -v sha256sum > /dev/null 2>&1; then sha256sum < "$1" | cut -c1-8
    else shasum -a 256 < "$1" | cut -c1-8; fi
}
# posted_entry <comment-id> <out> <kind>: the text of record comment ID, as
# record-append.sh --list reads it back, normalised as norm_entry does. The
# comment must be on this run's record issue and carry KIND's entry marker
# (milestone-verdict or milestone-failure); anything else is refused (65),
# and a failed read exits 2.
posted_entry() {
    local c
    if ! c=$(gh api --method GET "repos/$REPO/issues/comments/$1" 2> "$WD/pc.err" < /dev/null); then
        grep -q 'HTTP 404' "$WD/pc.err" && refuse "no comment $1 on $REPO: the entry URL names no posted entry"
        lib_die2 "cannot read comment $1: $(lib_scrub < "$WD/pc.err")"
    fi
    printf '%s' "$c" | jq -e --arg u "https://github.com/$REPO/issues/$REF#issuecomment-$1" \
        '(.html_url // "" | ascii_downcase) == ($u | ascii_downcase)' > /dev/null \
        || refuse "comment $1 is not on this run's record, issue #$REF"
    printf '%s' "$c" | jq -r '.body // ""' | tr -d '\r' > "$WD/pc.body" || lib_die2 "comment $1 is not JSON"
    [ "$(head -1 "$WD/pc.body")" = "${ENTRY_MARKER_PREFIX}$3 -->" ] \
        || refuse "comment $1 is not a $3 entry (one record-append.sh --kind $3 posted)"
    # record-append.sh writes `&` as `&amp;` and `@` as `&#64;`; decoded in
    # its reader's order, the text comes back as written.
    tail -n +4 "$WD/pc.body" | sed -e 's/&#64;/@/g' -e 's/&amp;/\&/g' > "$WD/pc.raw"
    norm_entry "$WD/pc.raw" "$2"
}
# rework_of <entry>: the rework text a changes-needed verdict leaves for the
# milestone's next brief: the not-held clause numbers, a strategy that
# doesn't fit, and the Changes needed line, one paragraph.
rework_of() {
    awk '
        /^[0-9]+\. not held -- / { n = $0; sub(/\..*$/, "", n); nh = nh (nh == "" ? "" : ", ") n }
        /^Strategy fit: does not fit -- / { nofit = 1 }
        /^Changes needed: / { ch = substr($0, 17) }
        END {
            s = ""
            if (nh != "") s = "Evidence clauses not held: " nh "."
            if (nofit) s = s (s == "" ? "" : " ") "The work does not fit the strategy."
            printf "%s%sChanges needed: %s\n", s, (s == "" ? "" : " "), ch
        }' "$1"
}
# field_of <section-file> <name>: the field's lines in a follow-up section,
# from its `**<name>:**` line to the first blank line, field line or heading.
field_of() {
    RS_F="**$2:**" awk '
        BEGIN { f = ENVIRON["RS_F"] }
        on && (/^[ \t]*$/ || /^\*\*[A-Z][A-Za-z ]*:\*\*/ || /^#/) { exit }
        index($0, f) == 1 { on = 1 }
        on { print }' "$1"
}
# follow_ups_read: the --follow-ups FILE checked against the verdict's
# Follow-ups line and the roadmap at the default branch's head, and split
# into $WD/fu/<n>.md, one per `### <tag>: <title>` section. Writes
# $WD/fu-plan.tsv, one line per follow-up in the verdict's order: `new <n>`
# or `amend <n> <tag>`. Every refusal exits 65.
follow_ups_read() {
    local size n i head tag title fields why k t ftitle used
    [ -r "$FOLLOW_UPS" ] && [ -f "$FOLLOW_UPS" ] || refuse "cannot read the follow-ups file $FOLLOW_UPS"
    size=$(wc -c < "$FOLLOW_UPS" | tr -d ' ')
    [ "$size" -le "$FOLLOW_UPS_MAX" ] || refuse "the follow-ups file is $size bytes, over $FOLLOW_UPS_MAX"
    # Text that lands in a committed roadmap: no control character or tab
    # (the Evidence reader refuses a tab), no token or home-directory path,
    # and no path into a work-in-progress directory.
    LC_ALL=C grep -q $'[\001-\010\011\013-\037\177]' "$FOLLOW_UPS" && refuse "the follow-ups file holds a control character or a tab"
    why=$(jq -R -s -r -L "$HERE" 'include "record-codec"; text_problem([]) // empty' < "$FOLLOW_UPS")
    [ -z "$why" ] || refuse "the follow-ups file holds $why"
    # (The bracket keeps the directory's name out of this file, which the
    # skill's hygiene suite holds to naming no staging path.)
    grep -qE '(^|[^A-Za-z0-9_.-])wi[p]/' "$FOLLOW_UPS" && refuse "the follow-ups file names a path into a work-in-progress directory"
    mkdir -p "$WD/fu"
    tr -d '\r' < "$FOLLOW_UPS" | awk -v d="$WD/fu" '
        /^### / { n++; f = d "/" n ".md" }
        n == 0 && /[^ \t]/ { bad = 1; exit }
        n > 0 { print > f }
        END { exit(bad ? 1 : 0) }' || refuse "the follow-ups file holds text before its first \`### <tag>: <title>\` section"
    n=$(ls "$WD/fu" | grep -c '\.md$')
    [ "$n" -gt 0 ] || refuse "the follow-ups file holds no \`### <tag>: <title>\` section"
    RE_FU_HEAD='^### (Feature [0-9]+|[A-Za-z]+[0-9]+[a-z]?): (.+)$'
    : > "$WD/fu/index.tsv"
    i=1
    while [ "$i" -le "$n" ]; do
        head=$(head -1 "$WD/fu/$i.md")
        [[ $head =~ $RE_FU_HEAD ]] || refuse "follow-up section $i's heading is not \`### <tag>: <title>\`: [${head:0:80}]"
        tag=${BASH_REMATCH[1]} title=${BASH_REMATCH[2]}
        # Field lines only, each once, from the closed set; the four a
        # milestone needs present and not empty.
        fields=$(awk '
            NR == 1 { next }
            /^\*\*[A-Z][A-Za-z ]*:\*\*/ {
                name = $0; sub(/^\*\*/, "", name); sub(/:\*\*.*$/, "", name)
                if (name != "Outcome" && name != "Evidence" && name != "Left open" && name != "Needs" && name != "Dependencies") { print "a " name " field, which a follow-up section doesn'"'"'t take"; exit }
                if (seen[name]++) { print "two " name " fields"; exit }
                val = $0; sub(/^\*\*[^*]*:\*\*[ \t]*/, "", val); v[name] = val; cur = name; next
            }
            /^[ \t]*$/ { cur = ""; next }
            /^#/ { print "a heading inside it"; exit }
            cur != "" { v[cur] = v[cur] $0; next }
            { print "text outside its fields: " substr($0, 1, 60); exit }
            END {
                split("Outcome|Evidence|Left open|Dependencies", req, "|")
                for (j = 1; j <= 4; j++) if (!(req[j] in v) || v[req[j]] !~ /[^ \t]/) { print "no " req[j]; exit }
            }' "$WD/fu/$i.md")
        [ -z "$fields" ] || refuse "follow-up section $tag: $fields"
        # The Evidence as the roadmap's reader takes it: one `- ` clause or
        # more, nothing it can't classify.
        { printf -- '---\nschema: roadmap/v2\n---\n\n## Features\n\n'; cat "$WD/fu/$i.md"; printf '**Status:** Not started\n'; } > "$WD/fu/$i.check"
        bash "$HERE/milestone.sh" evidence "$WD/fu/$i.check" "$tag" > "$WD/fu/$i.json" 2> /dev/null \
            || refuse "follow-up section $tag: its Evidence is not one \`- \` clause or more"
        printf '%s\t%s\t%s\n' "$i" "$tag" "$title" >> "$WD/fu/index.tsv"
        i=$((i + 1))
    done
    [ "$(cut -f2 "$WD/fu/index.tsv" | sort | uniq -d | head -1)" = "" ] || refuse "two follow-up sections share a tag"
    # Each follow-up the verdict names has its section, and each section is
    # one the verdict names.
    : > "$WD/fu-plan.tsv"
    used=
    while IFS='	' read -r k t; do
        if [ "$k" = new ]; then
            i=$(awk -F'\t' -v t="$t" '$3 == t { print $1; exit }' "$WD/fu/index.tsv")
            [ -n "$i" ] || refuse "the follow-up \`new: $t\` has no section in the follow-ups file (a \`### <tag>: $t\` heading)"
            tag=$(awk -F'\t' -v i="$i" '$1 == i { print $2 }' "$WD/fu/index.tsv")
            grep -qE "^### $tag:( |$)" "$WD/roadmap.md" && refuse "the follow-up \`new: $t\` takes the tag $tag, which the roadmap already uses"
            printf 'new\t%s\t%s\n' "$i" "$tag" >> "$WD/fu-plan.tsv"
        else
            [ "$t" != "$TAG" ] || refuse "a follow-up amends $TAG itself; the milestone this verdict verifies keeps the Evidence it was judged against"
            bash "$HERE/milestone.sh" evidence "$WD/roadmap.md" "$t" > "$WD/fu/target.json" 2> /dev/null \
                || refuse "the follow-up \`amend $t\` names a tag the roadmap has no milestone for"
            i=$(awk -F'\t' -v t="$t" '$2 == t { print $1; exit }' "$WD/fu/index.tsv")
            [ -n "$i" ] || refuse "the follow-up \`amend $t\` has no section in the follow-ups file (a \`### $t: <title>\` heading)"
            ftitle=$(awk -F'\t' -v i="$i" '$1 == i { print $3 }' "$WD/fu/index.tsv")
            [ "$ftitle" = "$(jq -r .title "$WD/fu/target.json")" ] \
                || refuse "the amend section for $t retitles it; an amendment changes Outcome, Evidence or Left open, never the title"
            # Dependencies don't change in place (roadmap format): the
            # section's must be the milestone's.
            [ "$(field_of "$WD/fu/$i.md" Dependencies)" = "$(tr -d '\r' < "$WD/roadmap.md" | awk -v h="### $t: " '
                    /^## / { inf = ($0 ~ /^## Features[ \t]*$/); inb = 0; next }
                    inf && /^### / { inb = (index($0, h) == 1); next }
                    inb && /^\*\*Dependencies:\*\*/ { print; exit }')" ] \
                || refuse "the amend section for $t changes its Dependencies, which a milestone roadmap never changes in place"
            printf 'amend\t%s\t%s\n' "$i" "$t" >> "$WD/fu-plan.tsv"
        fi
        used="$used $i "
    done <<EOF
$(jq -r '.follow_ups[] | if .kind == "new" then "new\t\(.title)" else "amend\t\(.tag)" end' "$WD/verdict.json")
EOF
    while IFS='	' read -r i tag title; do
        case "$used" in *" $i "*) ;; *) refuse "the follow-ups file's section $tag is no follow-up the verdict names" ;; esac
    done < "$WD/fu/index.tsv"
}
# follow_ups_apply <doc>: each follow-up of $WD/fu-plan.tsv written into DOC:
# an amend replaces its milestone's Outcome, Evidence and Left open fields
# with the section's, and the new milestones go after the last one, each
# Not started. Checked after: every new tag reads as a milestone, and every
# amended milestone carries its section's Evidence.
follow_ups_apply() {
    local k i at new=
    while IFS='	' read -r k i at; do
        if [ "$k" = amend ]; then
            RS_TAG="$at" RS_OUT="$(field_of "$WD/fu/$i.md" Outcome)" RS_EVI="$(field_of "$WD/fu/$i.md" Evidence)" \
            RS_LEFT="$(field_of "$WD/fu/$i.md" "Left open")" awk '
                BEGIN { h = "### " ENVIRON["RS_TAG"] ": "; r["Outcome"] = ENVIRON["RS_OUT"]; r["Evidence"] = ENVIRON["RS_EVI"]; r["Left open"] = ENVIRON["RS_LEFT"] }
                dropping && (/^[ \t]*$/ || /^\*\*[A-Z][A-Za-z ]*:\*\*/ || /^#/) { dropping = 0 }
                dropping { next }
                /^## / { inf = ($0 ~ /^## Features[ \t]*$/); inb = 0; print; next }
                inf && /^### / { inb = (index($0, h) == 1); print; next }
                inb && /^\*\*(Outcome|Evidence|Left open):\*\*/ {
                    name = $0; sub(/^\*\*/, "", name); sub(/:\*\*.*$/, "", name)
                    print r[name]; dropping = 1; next
                }
                { print }' "$1" > "$1.fu" && mv "$1.fu" "$1" || lib_die2 "awk failed"
            [ "$(bash "$HERE/milestone.sh" evidence "$1" "$at" 2> /dev/null | jq -c .evidence)" = "$(jq -c .evidence "$WD/fu/$i.json")" ] \
                || refuse "the amendment of $at could not be written into $ROADMAP"
        else
            new="$new$(awk '{ l[NR] = $0 } END { e = NR; while (e > 0 && l[e] ~ /^[ \t]*$/) e--; for (j = 1; j <= e; j++) print l[j] }' "$WD/fu/$i.md")"$'\n'"**Status:** Not started"$'\n\n'
        fi
    done < "$WD/fu-plan.tsv"
    if [ -n "$new" ]; then
        # After the last milestone: where the Features section ends, at the
        # next `## ` heading or the end of the file.
        RS_NEW="$new" awk '
            BEGIN { s = ENVIRON["RS_NEW"]; sub(/\n+$/, "", s) }
            function put() { if (pb) print ""; print s; print ""; done = 1 }
            /^## / && inf && !done { put() }
            /^## / { inf = ($0 ~ /^## Features[ \t]*$/) }
            { print; pb = ($0 !~ /^[ \t]*$/) }
            END { if (inf && !done) { if (pb) print ""; print s } }' "$1" > "$1.fu" && mv "$1.fu" "$1" || lib_die2 "awk failed"
        while IFS='	' read -r k i at; do
            [ "$k" = new ] || continue
            bash "$HERE/milestone.sh" evidence "$1" "$at" 2> /dev/null | jq -e '.status == "Not started"' > /dev/null \
                || refuse "the follow-up milestone $at could not be written into $ROADMAP"
        done < "$WD/fu-plan.tsv"
    fi
}
# rework_problem_of <text>: why the codec would refuse TEXT as a rework row's
# Next step (its closed shape, or text a public record never carries), or
# nothing.
rework_problem_of() {
    printf '%s' "$1" | jq -R -s -r -L "$HERE" 'include "record-codec"; (rework_problem // text_problem([])) // empty'
}
# failure_rework_of <entry>: the rework text a confirmed reopen leaves for the
# milestone's next brief, `Evidence clause <n> failed: <what was seen>`, cut
# to the codec's 600 bytes (rework_cap): What was seen may be 600 bytes
# itself, and the prefix would put the whole over. render-brief.sh picks its
# failure wording on that prefix, so the two change together.
failure_rework_of() {
    awk '/^Clause: / { c = substr($0, 9) } /^What was seen: / { w = substr($0, 16) }
         END { printf "Evidence clause %s failed: %s", c, w }' "$1" \
        | jq -R -s -j -L "$HERE" 'include "record-codec"; rework_cap'
}
# reopen_line <roadmap>: the last `## Progress` line naming TAG, when it is a
# reopen line --reopen writes for a failure posted on this run's record. Sets
# RL_CLAUSE, RL_URL, RL_ID and RL_HASH; returns 1 otherwise. TAG and the
# record's URL are compared as text, never as patterns.
reopen_line() {
    local last pre rest re
    last=$(tr -d '\r' < "$1" | RS_TAG="$TAG" awk '
        BEGIN { t = ": " ENVIRON["RS_TAG"] " -- " }
        /^## / { inprog = ($0 ~ /^## Progress[ \t]*$/); next }
        inprog && /^- [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]: / && index($0, t) == 13 { last = $0 }
        END { print last }')
    pre="${last:0:12}: $TAG -- reopened: clause "
    [ -n "$last" ] && [ "${last:0:${#pre}}" = "$pre" ] || return 1
    rest=${last:${#pre}}
    re='^([1-9][0-9]*) failed, reported by .+ \((https://github\.com/[^ ]+#issuecomment-([1-9][0-9]*)), ([0-9a-f]{8})\)$'
    [[ $rest =~ $re ]] || return 1
    RL_CLAUSE=${BASH_REMATCH[1]} RL_URL=${BASH_REMATCH[2]} RL_ID=${BASH_REMATCH[3]} RL_HASH=${BASH_REMATCH[4]}
    [ "$RL_URL" = "https://github.com/$REPO/issues/$REF#issuecomment-$RL_ID" ]
}

# block_edit <out> <status> <done> <deliver> <progress>: the roadmap at
# $WD/roadmap.md with TAG's block and the Progress section edited, and
# nothing else before the populate: STATUS, when not empty, replaces TAG's
# Status; DONE 1 also drops its Needs field and adds DELIVER to its Delivered
# field; PROGRESS (one line or more) goes after the last line of `## Progress`.
# Values reach awk through the environment, which takes them as written.
block_edit() {
    tr -d '\r' < "$WD/roadmap.md" | RS_TAG="$TAG" RS_STATUS="$2" RS_DONE="$3" RS_DELIVER="$4" RS_PROGRESS="$5" awk '
        BEGIN { tag = ENVIRON["RS_TAG"]; status = ENVIRON["RS_STATUS"]; done = ENVIRON["RS_DONE"] == "1"; deliver = ENVIRON["RS_DELIVER"]; progress = ENVIRON["RS_PROGRESS"] }
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
        inblock && status != "" && /^\*\*Status:\*\*/ { print "**Status:** " status; next }
        { print }
        END {
            flush_delivered()
            if (inprog) { more = 0; flush_progress() }
        }' > "$1" || lib_die2 "awk failed"
}

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
            # The rework the changes-needed verdict leaves, read from the
            # entry itself, which must still be the text its Progress line
            # hashed: a comment edited since is not the judgment the person
            # who merged the edit reviewed.
            [[ ${URL##*#issuecomment-} =~ $RE_NUM ]] || lib_die2 "$TAG's milestone-verdict row names no comment"
            posted_entry "${URL##*#issuecomment-}" "$WD/posted.txt" milestone-verdict
            PH=$(tr -d '\r' < "$WD/roadmap.md" | RS_URL="$URL" awk '
                BEGIN { u = "(" ENVIRON["RS_URL"] ", " }
                /^## / { inprog = ($0 ~ /^## Progress[ \t]*$/); next }
                inprog && (p = index($0, u)) > 0 { print substr($0, p + length(u), 8); exit }')
            [ -n "$PH" ] && [ "$PH" = "$(sha8 "$WD/posted.txt")" ] \
                || refuse "the entry at $URL is not the text its Progress line hashed (${PH:-no hash}); it changed since its verdict's edit, so nothing is confirmed: check the comment's history"
            REWORK=$(rework_of "$WD/posted.txt")
            WHY=$(rework_problem_of "$REWORK")
            [ -z "$WHY" ] || refuse "the entry's rework text can't go in the record ($WHY)"
        elif [ "$ACTION" = milestone-reopen ]; then
            ST=$(bash "$HERE/milestone.sh" evidence "$WD/roadmap.md" "$TAG" 2> /dev/null | jq -r '.status // empty')
            [ "$ST" = "In progress" ] \
                || { echo "$PROG: $TAG reads ${ST:-no status} on $DEFAULT_BRANCH; its reopen pull request, $PRL, hasn't landed" >&2; exit 1; }
            # The row's How to confirm names no entry, so the failure is the
            # one the merged edit wrote: the last Progress line naming TAG.
            # A later line about TAG (a verdict's) or none at all means the
            # default branch doesn't show this edit, whatever its Status
            # says, and nothing is confirmed.
            reopen_line "$WD/roadmap.md" \
                || { echo "$PROG: $ROADMAP on $DEFAULT_BRANCH reads $TAG In progress, but its last Progress line about $TAG is no reopen on this run's record; its reopen pull request, $PRL, hasn't landed" >&2; exit 1; }
            # The failure as reported, which must still be the text the
            # Progress line hashed, name TAG and name the line's clause.
            posted_entry "$RL_ID" "$WD/posted.txt" milestone-failure
            [ "$RL_HASH" = "$(sha8 "$WD/posted.txt")" ] \
                || refuse "the entry at $RL_URL is not the text its Progress line hashed ($RL_HASH); it changed since its reopen edit, so nothing is confirmed: check the comment's history"
            [ "$(sed -n 1p "$WD/posted.txt")" = "Failure: $TAG" ] && [ "$(sed -n 4p "$WD/posted.txt")" = "Clause: $RL_CLAUSE" ] \
                || refuse "the entry at $RL_URL doesn't name $TAG and clause $RL_CLAUSE as its Progress line does"
            URL=$RL_URL
            REWORK=$(failure_rework_of "$WD/posted.txt") || lib_die2 "jq failed"
            WHY=$(rework_problem_of "$REWORK")
            [ -z "$WHY" ] || refuse "the failure's rework text can't go in the record ($WHY)"
        else
            feature_read "$WD/roadmap.md"
            ST=$(printf '%s' "$FEATURE" | jq -r '.status // empty')
            [ "$(printf '%s' "$FEATURE" | jq -r '.done // false')" = true ] \
                || { echo "$PROG: $TAG reads ${ST:-no status} on $DEFAULT_BRANCH; its pull request, $PRL, hasn't landed" >&2; exit 1; }
        fi
        case "$ACTION" in
            milestone-verdict)
                # Changes needed: the milestone goes back to pick, In
                # progress, with a rework row its next brief quotes.
                without_row "$WD/next.json" true
                jq --arg t "$TAG" --arg w "verdict ${URL##*#issuecomment-}" --arg n "$REWORK" --arg u "$(date -u +%Y-%m-%dT%H:%MZ)" '
                    .work = ((.work // []) + [{item: $t, kind: "rework", who: $w, next: $n, wakes: "0", updated: $u}])' \
                    "$WD/next.json" > "$WD/next2.json" && mv "$WD/next2.json" "$WD/next.json" || lib_die2 "jq failed"
                write_record "$WD/next.json" "$TAG reads $ST on $DEFAULT_BRANCH; its verdict's roadmap pull request $PRL landed, and the record no longer holds it or $TAG's verdict owed. The verdict asked for changes, so $TAG goes back to pick with a rework row its next brief quotes: $REWORK" ;;
            milestone-reopen)
                # A failure after Done: the milestone goes back to pick, In
                # progress, with a rework row its next brief quotes.
                without_row "$WD/next.json" true
                jq --arg t "$TAG" --arg w "failure $RL_ID" --arg n "$REWORK" --arg u "$(date -u +%Y-%m-%dT%H:%MZ)" '
                    .work = ((.work // []) + [{item: $t, kind: "rework", who: $w, next: $n, wakes: "0", updated: $u}])' \
                    "$WD/next.json" > "$WD/next2.json" && mv "$WD/next2.json" "$WD/next.json" || lib_die2 "jq failed"
                write_record "$WD/next.json" "$TAG reads In progress on $DEFAULT_BRANCH; its reopen pull request $PRL landed, and the record no longer holds it. Evidence clause $RL_CLAUSE failed after $TAG read Done ($URL), so $TAG goes back to pick with a rework row its next brief quotes: $REWORK" ;;
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
    # The entry is the comment at URL, as posted: on this run's record, with
    # the milestone-verdict marker, and the entry file's text exactly, so the
    # judgment the edit carries is the one the record shows. ENTRY is the
    # text from here on.
    ENTRY="$WD/entry.txt"
    norm_entry "$ENTRY_IN" "$ENTRY"
    posted_entry "${ENTRY_URL##*#issuecomment-}" "$WD/posted.txt" milestone-verdict
    cmp -s "$ENTRY" "$WD/posted.txt" \
        || refuse "the entry file differs from the comment at $ENTRY_URL; give the file that was posted, or post this one and use its URL"
    # The roadmap at the entry's Source commit, the copy its clauses were
    # judged against: a commit the default branch contains, so the judgment
    # was made on Evidence that was on the roadmap, not on a branch.
    SRC_LINE=$(sed -n 4p "$ENTRY")
    RE_SRC='^Source: ([^ ]+) at ([0-9a-f]{40})$'
    [[ $SRC_LINE =~ $RE_SRC ]] || refuse "the entry's line 4 is not \`Source: <roadmap path> at <40-character commit>\`"
    SRC_PATH=${BASH_REMATCH[1]} SRC_COMMIT=${BASH_REMATCH[2]}
    [ "$SRC_PATH" = "$ROADMAP" ] || refuse "the entry's Source is $SRC_PATH, not this run's roadmap, $ROADMAP"
    head_read
    if ! CMP=$(gh api --method GET "repos/$REPO/compare/$SRC_COMMIT...$BASE_SHA" --jq .status 2> "$WD/cmp.err" < /dev/null); then
        grep -q 'HTTP 404' "$WD/cmp.err" && refuse "the entry's Source commit, $SRC_COMMIT, is not a commit of $REPO"
        lib_die2 "cannot compare $SRC_COMMIT with $DEFAULT_BRANCH: $(lib_scrub < "$WD/cmp.err")"
    fi
    case "$CMP" in
        identical|ahead) ;;
        *) refuse "$DEFAULT_BRANCH doesn't contain the entry's Source commit, $SRC_COMMIT ($CMP); judge the clauses against the roadmap on $DEFAULT_BRANCH" ;;
    esac
    lib_file_at "$ROADMAP" "$SRC_COMMIT" "$WD/source.md"
    case $? in
        0) ;;
        1) refuse "$ROADMAP is not at the entry's Source commit, $SRC_COMMIT" ;;
        *) lib_die2 "cannot read $ROADMAP at $SRC_COMMIT" ;;
    esac
    set -- check-verdict "$WD/source.md" "$TAG" "$ENTRY"
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
    if [ "$VERDICT" = "changes needed" ]; then
        # Its confirmation leaves a rework row for the next brief: text the
        # record can't hold is refused now, before any edit is opened.
        WHY=$(rework_problem_of "$(rework_of "$ENTRY")")
        [ -z "$WHY" ] || refuse "the Changes needed line becomes the milestone's rework text, which the next brief quotes, and it can't ($WHY): keep it one paragraph of at most 600 bytes with no URL or link"
    fi
    if [ "$VERDICT" = "verified with follow-ups" ]; then
        [ -n "$FOLLOW_UPS" ] || refuse "a verified-with-follow-ups verdict adds its follow-up milestones in the same edit: give each one's section with --follow-ups FILE"
    else
        [ -z "$FOLLOW_UPS" ] || refuse "--follow-ups goes with a verified-with-follow-ups verdict; this one is $VERDICT"
    fi
    bash "$HERE/milestone.sh" evidence "$WD/roadmap.md" "$TAG" > "$WD/milestone.json" 2> "$WD/m.err" \
        || refuse "$TAG is not a milestone with Evidence on $DEFAULT_BRANCH: $(lib_scrub < "$WD/m.err")"
    TITLE=$(jq -r .title "$WD/milestone.json")
    case "$(jq -r .status "$WD/milestone.json")" in Done*) refuse "$TAG already reads Done on $DEFAULT_BRANCH" ;; esac
    # Clauses are identified by position in the Evidence at Source; a
    # judgment is only good for the Evidence the default branch carries now,
    # so a sharpened or renumbered Evidence list is re-checked, never edited
    # against (Decision 3).
    bash "$HERE/milestone.sh" evidence "$WD/source.md" "$TAG" > "$WD/source-milestone.json" 2> /dev/null \
        || refuse "$TAG is not a milestone with Evidence at the entry's Source"
    [ "$(jq -c .evidence "$WD/source-milestone.json")" = "$(jq -c .evidence "$WD/milestone.json")" ] \
        || refuse "$TAG's Evidence on $DEFAULT_BRANCH differs from its Evidence at the entry's Source, $SRC_COMMIT; check the clauses again against the current Evidence and write a new entry"
    grep -qE $'^## Progress[ \t\r]*$' "$WD/roadmap.md" || refuse "$ROADMAP has no ## Progress section for the verdict's line"
    : > "$WD/fu-plan.tsv"
    [ -z "$FOLLOW_UPS" ] || follow_ups_read
    # The hash of the entry as posted (the text --confirm re-reads), so a
    # later edit of the comment shows.
    HASH=$(sha8 "$ENTRY")
    PROGRESS="- $CHECKED_ON: $TAG -- $VERDICT, checked by $CHECKER ($ENTRY_URL, $HASH)"
    # Each amendment a follow-up makes is named in Progress, as the format
    # asks of an Outcome, Evidence or Left open changed in place.
    while IFS='	' read -r k i at; do
        [ "$k" = amend ] || continue
        PROGRESS="$PROGRESS"$'\n'"- $CHECKED_ON: $at amended -- a follow-up of the verified verdict on $TAG ($ENTRY_URL)"
    done < "$WD/fu-plan.tsv"
    DONE=0 DELIVER=
    if [ "$VERDICT" != "changes needed" ]; then
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
    # TAG's Status, Needs and Delivered lines and the Progress section.
    if [ "$DONE" = 1 ]; then block_edit "$DOC.1" Done 1 "$DELIVER" "$PROGRESS"
    else block_edit "$DOC.1" "" 0 "" "$PROGRESS"; fi
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
    [ ! -s "$WD/fu-plan.tsv" ] || follow_ups_apply "$DOC"
    while IFS= read -r pl; do
        bash "$HERE/milestone.sh" progress-has "$DOC" "$pl" || refuse "the Progress line could not be written into $ROADMAP"
    done <<EOF
$PROGRESS
EOF
    if [ "$DONE" = 1 ]; then
        bash "$HERE/milestone.sh" evidence "$DOC" "$TAG" 2> /dev/null | jq -e '.status == "Done"' > /dev/null \
            || refuse "$TAG's Status could not be set to Done (its block has no **Status:** line?)"
    fi
    if [ "$DONE" = 1 ]; then
        MSG="docs(roadmap): record $TAG, $TITLE, as done on its verdict"
    else
        MSG="docs(roadmap): record the changes-needed verdict on $TAG, $TITLE"
    fi
    BRANCH_STAMP=%Y%m%d%H%M%S
    populate_and_commit "$DOC" "$CRLF" coordinate/roadmap-verdict "$MSG"
    {
        if [ "$DONE" = 1 ]; then
            printf 'Records the %s verdict on %s of the roadmap, %s: its Status is Done, its Needs line goes and its Delivered line names the work checked; a Progress line names the verdict, who checked it and the entry. Its Outcome and Evidence are unchanged, and the generated sections are regenerated.\n' "$VERDICT" "$TAG" "$TITLE"
        else
            printf 'Records the changes-needed verdict on %s of the roadmap, %s: a Progress line names the verdict, who checked it and the entry. Its Status and Delivered line are unchanged; the milestone stays open for the changes the verdict names.\n' "$TAG" "$TITLE"
        fi
        if [ -s "$WD/fu-plan.tsv" ]; then
            printf '\nIts follow-ups, in the same edit:\n\n'
            while IFS='	' read -r k i at; do
                if [ "$k" = new ]; then printf -- '- adds %s, Not started, after the last milestone\n' "$(head -1 "$WD/fu/$i.md" | sed -e 's/^### //' -e 's/&/\&amp;/g' -e 's/@/\&#64;/g')"
                else printf -- '- amends %s: its Outcome, Evidence and Left open are the follow-up'"'"'s, with a Progress line naming the amendment\n' "$at"; fi
            done < "$WD/fu-plan.tsv"
        fi
        printf '\nThe verdict entry, as posted on the record (%s):\n\n' "$ENTRY_URL"
        sed -e 's/&/\&amp;/g' -e 's/@/\&#64;/g' -e 's/^/> /' "$ENTRY"
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

if [ "$MODE" = reopen ]; then
    # ---- --reopen: the roadmap edit a failure after Done calls for ----------
    [ -r "$ENTRY_IN" ] && [ -f "$ENTRY_IN" ] || refuse "cannot read the entry file $ENTRY_IN"
    SIZE=$(wc -c < "$ENTRY_IN" | tr -d ' ')
    [ "$SIZE" -le "$ENTRY_MAX" ] || refuse "the entry file is $SIZE bytes, over $ENTRY_MAX"
    case "$ENTRY_URL" in
        "https://github.com/$REPO/issues/$REF#issuecomment-"*) ;;
        *) refuse "--entry-url is not a comment on this run's record, https://github.com/$REPO/issues/$REF#issuecomment-<id>" ;;
    esac
    [[ ${ENTRY_URL##*#issuecomment-} =~ ^[1-9][0-9]*$ ]] || refuse "--entry-url's comment id is not a number"
    # One roadmap edit at a time: a second failure recorded while this
    # milestone's reopen edit (or any other) is pending opens nothing.
    pending_refuse
    # The entry is the comment at URL, as posted, as --verdict binds its own.
    ENTRY="$WD/entry.txt"
    norm_entry "$ENTRY_IN" "$ENTRY"
    posted_entry "${ENTRY_URL##*#issuecomment-}" "$WD/posted.txt" milestone-failure
    cmp -s "$ENTRY" "$WD/posted.txt" \
        || refuse "the entry file differs from the comment at $ENTRY_URL; give the file that was posted, or post this one and use its URL"
    # Checked against the roadmap the edit changes, at the default branch's
    # head: TAG reads Done there, and the clause is one of its Evidence's.
    head_read
    bash "$HERE/milestone.sh" check-failure "$WD/roadmap.md" "$TAG" "$ENTRY" > "$WD/failure.json" 2> "$WD/check.err"
    case $? in
        0) ;;
        1|2) refuse "the entry doesn't pass milestone.sh check-failure against $ROADMAP on $DEFAULT_BRANCH: $(lib_scrub < "$WD/check.err")" ;;
        *) lib_die2 "milestone.sh check-failure failed: $(lib_scrub < "$WD/check.err")" ;;
    esac
    REPORTER=$(jq -r .reported_by "$WD/failure.json")
    SEEN_ON=$(jq -r .seen_on "$WD/failure.json")
    CLAUSE=$(jq -r .clause "$WD/failure.json")
    TITLE=$(bash "$HERE/milestone.sh" evidence "$WD/roadmap.md" "$TAG" | jq -r .title) || lib_die2 "cannot read $TAG's title"
    grep -qE $'^## Progress[ \t\r]*$' "$WD/roadmap.md" || refuse "$ROADMAP has no ## Progress section for the reopen's line"
    # Its confirmation leaves a rework row for the next brief: text the record
    # can't hold is refused now, before any edit is opened.
    WHY=$(rework_problem_of "$(failure_rework_of "$ENTRY")")
    [ -z "$WHY" ] || refuse "What was seen becomes the milestone's rework text, which the next brief quotes, and it can't ($WHY)"
    # The milestones a holding covers whose Dependencies name TAG, as pick
    # reads them: they read blocked again once this edit lands.
    lib_roadmap_features "$WD/roadmap.md" > "$WD/features.json" 2> "$WD/f.err" || lib_die2 "cannot read the features of $ROADMAP: $(lib_scrub < "$WD/f.err")"
    HELD=$(jq -r --arg t "$TAG" --slurpfile p "$WD/parsed.json" '
        ([.[] | select(.id == $t) | .number][0]) as $n
        | .[] | select(.id != $t and any(.dependencies[]; . == $n)) | . as $f
        | $p[0].holdings[] | select(.unit == $f.id or .unit == ($f.id + ": " + $f.title))
        | "held-dependent \($f.id) \(.worker)"' "$WD/features.json") || lib_die2 "jq failed"
    HASH=$(sha8 "$ENTRY")
    PROGRESS="- $SEEN_ON: $TAG -- reopened: clause $CLAUSE failed, reported by $REPORTER ($ENTRY_URL, $HASH)"
    mkdir -p "$WD/doc"
    DOC="$WD/doc/$(basename "$ROADMAP")"
    CRLF=0
    grep -q $'\r$' "$WD/roadmap.md" && CRLF=1
    # TAG's Status and the Progress section: Delivered, Outcome and Evidence
    # stay, so the milestone is judged again against the Evidence it failed.
    block_edit "$DOC" "In progress" 0 "" "$PROGRESS"
    bash "$HERE/milestone.sh" evidence "$DOC" "$TAG" 2> /dev/null | jq -e '.status == "In progress"' > /dev/null \
        || refuse "$TAG's Status could not be set to In progress (its block has no **Status:** line?)"
    bash "$HERE/milestone.sh" progress-has "$DOC" "$PROGRESS" || refuse "the Progress line could not be written into $ROADMAP"
    MSG="docs(roadmap): reopen $TAG, $TITLE, on a reported failure"
    BRANCH_STAMP=%Y%m%d%H%M%S
    populate_and_commit "$DOC" "$CRLF" coordinate/roadmap-reopen "$MSG"
    {
        printf 'Reopens %s of the roadmap, %s, on a failure reported after it read Done: its Status goes back to In progress and a Progress line names the failed clause, who reported it and the entry. Its Delivered line, Outcome and Evidence are unchanged, and the generated sections are regenerated.\n' "$TAG" "$TITLE"
        printf '\nThe failure entry, as posted on the record (%s):\n\n' "$ENTRY_URL"
        sed -e 's/&/\&amp;/g' -e 's/@/\&#64;/g' -e 's/^/> /' "$ENTRY"
        printf '\n---\n\n'
        printf 'Opened by the coordinator for %s from its record, issue #%s. Check the report against the milestone'"'"'s Evidence before merging: on a milestone roadmap this pull request is what sends a Done milestone back to work, and the coordinator never merges it.\n' "$NAME" "$REF"
    } > "$WD/prbody.md"
    open_pr "$MSG"
    jq --arg t "$TAG [#$PR_NUM]($PR_URL)" --arg at "$(date -u +%Y-%m-%dT%H:%MZ)" --arg h "the roadmap on $DEFAULT_BRANCH reads $TAG In progress" '
        del(.written) | .side_effects += [{action: "milestone-reopen", target: $t, verified_head: "", attempted: $at, how_to_confirm: $h}]' \
        "$WD/parsed.json" > "$WD/next.json" || lib_die2 "jq failed"
    URL_OUT=$PR_URL
    write_record "$WD/next.json" "A failure of Evidence clause $CLAUSE of $TAG, reported by $REPORTER ($ENTRY_URL), is on its reopen pull request $PR_URL. Until that merges and is confirmed, $TAG reads Done and pick passes over it."
    printf '%s\n' "$URL_OUT"
    [ -z "$HELD" ] || printf '%s\n' "$HELD"
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
