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
#   roadmap-status.sh --session S --verdict TAG --entry N [--follow-ups FILE]
#   roadmap-status.sh --session S --reopen TAG --entry N
#   roadmap-status.sh --session S --confirm TAG
#   roadmap-status.sh --session S --drop TAG --reason TEXT
#   roadmap-status.sh --session S --list
#   ... [--scope roadmap --name N --repo O/R [--roadmap PATH]
#        --skip-session-checks]                                   (tests)
#
# The session gives the name, host and roadmap (coord-log.sh vars), and must
# have a found record (coord-log.sh run-facts); the override flags exist for
# tests only, with RS_SESSION naming the session that holds the record.
#
# --unit first reads the roadmap at the default branch's head and its
# frontmatter `schema:`, before any refusal, and then does one of two things.
#
# A milestone roadmap is a roadmap/v2 or roadmap/v3 one (milestone.sh
# is-milestone). The two read alike: v3 lists its milestones under
# `## Milestones` with `### Milestone N:` headings where v2 has `## Features`
# and `### Feature N:`. TAG and every record row and entry this script
# matches to a heading (a holding, a pending row, a Work row, a verdict or
# failure entry, a follow-up, an amendment, a Progress reopen line) compare
# by state-common.sh's tag key, so a record that names `Feature 2` still
# finds a v3 roadmap's `### Milestone 2:`. Rows keep TAG as given; what the
# edit writes into the roadmap (a Progress line, the commit and pull request
# titles) names the milestone as the roadmap spells its heading.
#
# On a milestone roadmap a milestone reads Done only on a
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
# --verdict opens the roadmap edit a checked verdict entry calls for. The entry
# is record/entries/N, written with state-entry.sh --kind milestone-verdict
# --on none, at most 16 KiB. It requires TAG's verdict-owed row, requires the
# default branch to contain the commit the entry's
# Source line names (the compare API: identical or ahead), reads the roadmap
# at that commit (whose path must be this run's roadmap) and runs
# milestone.sh check-verdict against it, with --worker the row's Who unless
# that is `none`. It refuses (exit 65, nothing opened) a TAG outside the
# heading-tag grammar, one with no verdict-owed row, an entry over 16 KiB or
# of another kind, an entry already posted elsewhere, a Source commit the default branch doesn't
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
# confirm `the roadmap on <default> reads <TAG> Done (entry N)`) for a
# verified verdict of either kind, `milestone-verdict` (How to confirm `the
# roadmap on <default> carries its entry's comment in Progress (entry N)`) for
# changes needed. It never merges.
#
# --reopen opens the roadmap edit a failure reported against a Done milestone
# calls for. The entry is record/entries/N, written with state-entry.sh
# --kind milestone-failure --on none, at most 16 KiB, taken as --verdict takes
# its own. It refuses (exit 65, nothing opened)
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
# on <default> reads <TAG> In progress (entry N)`, and never merges. It prints the pull
# request's URL and then `held-dependent <tag> <worker>` for each milestone
# whose Dependencies name TAG (as pick reads them, soft ones aside) and that
# a holding covers: that worker's milestone reads blocked again once the
# edit lands, and the coordinator tells its owner.
#
# --verdict and --reopen post their entry on the roadmap pull request they open
# (docs/designs/current/DESIGN-coordinator-record-teardown.md, Decision 2), in
# an order that lets the Progress line name that comment: the edit without its
# Progress lines is committed on the new branch, the pull request opens with
# the entry in its body, the Side effects row is written (its How to confirm
# ends `(entry N)`), the entry is posted on the pull request with
# state-entry.sh --repost N --on <host>#<pull request> (so the content
# checks and the `@` escaping apply), and a second commit adds the Progress
# lines with the comment's URL and hash. When the post or that commit fails,
# it exits 14 naming the pull request; run with the same entry again it finds
# its row, posts once (state-entry.sh's retry finds a post that landed) and
# pushes only the missing commit, so no second pull request opens. An entry
# already posted anywhere else is refused, so after --drop the edit opens
# again from the same verdict or failure written as a new entry.
#
# --confirm removes TAG's row once the roadmap on the default branch shows
# it, by the row's Action: `roadmap-status` and `milestone-done` read Done,
# Shipped or Dropped for TAG, annotated or not (`Done -- shipped in #12`);
# `milestone-verdict` finds the entry's URL in `## Progress` (milestone.sh
# progress-has); `milestone-reopen` reads TAG In progress, and the last
# Progress line naming TAG must be a reopen line whose entry URL is on the
# row's pull request and whose hash8 the posted milestone-failure comment still
# hashes to; a reopen line written before the record moved to the session may
# cite a comment on an issue of the host, which is still accepted. Confirming
# a milestone row also removes TAG's verdict-owed
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
# A comment --confirm reads is found by id in the host repository, and the
# issue or pull request it sits on is read from the API's `issue_url`. For a
# row that names its entry (`(entry N)`) the comment must be on the roadmap
# pull request the row names, by the login `gh api user` answers, compared
# without case; such a milestone-verdict row finds its entry's URL in
# record/posted/N, and a reopen line cites a comment on the row's pull
# request. A row that names its comment's URL instead, written while the
# record was on GitHub, is checked against that comment in the host
# repository, bounded by its marker, kind, text and hash.
# --list prints the pending rows as a JSON array of {unit, pull_request,
# attempted, action}, state-schema.jq pending_list, the projection pick-facts.sh
# also takes from its own parse to mark landed units.
#
# Each change to the record is told as an entry with state-entry.sh, kind
# roadmap-status, after the state is written.
#
# A failed record write after the pull request opened (11 or 12) leaves
# the pull request with no row: close it by hand before running --unit,
# --verdict or --reopen again, which would open a second one on a new branch.
#
# Exit codes: 0 done (prints the pull request's URL, `verdict-owed TAG`, or the
# session holding the record) or printed; 1 --confirm: the roadmap doesn't show it yet; 2 a
# read failed; 10 refused about the record (no found record, one that doesn't
# read back as this roadmap's, or from the write core: not open, provenance, a
# directed transition); 11 a write failed; 12 the record changed between this
# script's read and its write; 14 the record was written but its entry
# wasn't posted; 64 usage (and any scope but a roadmap); 65 refused about the
# request: the tag, the feature's state, the entry, a pending pull request
# (the reason on stderr).
#
# The record is read through state-read.sh.
# GitHub calls:
#   reads:  gh api --method GET repos/R --jq .default_branch
#           gh api --method GET repos/R/git/ref/heads/<default> --jq .object.sha
#           gh api --method GET repos/R/contents/<roadmap>?ref=<that sha>   (--unit, --verdict, --reopen)
#           gh api --method GET repos/R/contents/<roadmap>?ref=<Source>     (--verdict)
#           gh api --method GET repos/R/compare/<Source>...<head sha>       (--verdict)
#           gh api --method GET repos/R/issues/comments/<id>               (--confirm)
#           gh api --method GET repos/R/contents/<roadmap>?ref=<default>    (--confirm)
#           gh api user --jq .login                                        (--confirm, a pull request's comment)
#           gh pr view N --repo R --json state,headRefName                 (--verdict, --reopen, run again)
#           gh api --method GET repos/R/contents/<roadmap>?ref=<branch>    (the Progress commit)
#   writes: gh api --method POST repos/R/git/refs -f ref=... -f sha=...
#           gh api --method PUT repos/R/contents/<roadmap> (message, content, sha, branch)
#           gh pr create --repo R --head <branch> --base <default> --title T --body-file F
#           the record, through state-write-core.sh; the entry, through state-entry.sh
#           (the posted entry too, through state-entry.sh --repost --on)
set -uo pipefail

PROG=roadmap-status
HERE=$(cd "$(dirname "$0")" && pwd)
SESSION= SCOPE= NAME= REPO= ROADMAP= MODE= TAG= OUTCOME= REASON= ENTRY_URL= FOLLOW_UPS= ENTRY_N=
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
        --roadmap) [ $# -ge 2 ] || usage; ARG_ROADMAP=$2; shift 2 ;;
        --unit) [ $# -ge 2 ] || usage; setmode open; TAG=$2; shift 2 ;;
        --verdict) [ $# -ge 2 ] || usage; setmode verdict; TAG=$2; shift 2 ;;
        --reopen) [ $# -ge 2 ] || usage; setmode reopen; TAG=$2; shift 2 ;;
        --confirm) [ $# -ge 2 ] || usage; setmode confirm; TAG=$2; shift 2 ;;
        --drop) [ $# -ge 2 ] || usage; setmode drop; TAG=$2; shift 2 ;;
        --list) setmode list; shift ;;
        --outcome) [ $# -ge 2 ] || usage; OUTCOME=$2; OUTCOME_SET=1; shift 2 ;;
        --reason) [ $# -ge 2 ] || usage; REASON=$2; shift 2 ;;
        --entry) [ $# -ge 2 ] || usage; ENTRY_N=$2; shift 2 ;;
        --follow-ups) [ $# -ge 2 ] || usage; FOLLOW_UPS=$2; shift 2 ;;
        --skip-session-checks) SKIP_CHECKS=1; shift ;;
        *) usage ;;
    esac
done
# entry_given: the session entry, by number.
entry_given() {
    [[ $ENTRY_N =~ ^[0-9]{1,6}$ ]] && [ "$((10#$ENTRY_N))" -gt 0 ]
}
case "$MODE" in
    open) [ -z "$REASON$FOLLOW_UPS$ENTRY_N" ] || usage ;;
    verdict) entry_given && [ "$OUTCOME_SET" = 0 ] && [ -z "$REASON" ] || usage ;;
    reopen) entry_given && [ "$OUTCOME_SET" = 0 ] && [ -z "$REASON$FOLLOW_UPS" ] || usage ;;
    drop) [ -n "$REASON" ] && [ "$OUTCOME_SET" = 0 ] && [ -z "$FOLLOW_UPS$ENTRY_N" ] || usage ;;
    confirm|list) [ "$OUTCOME_SET" = 0 ] && [ -z "$REASON$FOLLOW_UPS$ENTRY_N" ] || usage ;;
    *) usage ;;
esac
. "$HERE/state-common.sh"
lib_facts
[ -z "$ARG_ROADMAP" ] || { [ "$OVERRIDE" = 1 ] || usage; ROADMAP=$ARG_ROADMAP; }
[ "$SCOPE" = roadmap ] || { echo "$PROG: a feature's status is a roadmap's; this run's scope is $SCOPE" >&2; exit 64; }
lib_roadmap_path
lib_run_found || { echo "$PROG: refused: the run has no found record" >&2; exit 10; }
# The record's address, for state-entry.sh.
if [ "$OVERRIDE" = 1 ]; then ADDR=(--scope "$SCOPE" --name "$NAME" --repo "$REPO")
else ADDR=(--session "$SESSION"); fi
# --entry N reads the session's entry N (EN its key's six digits, ENUM the
# number).
ES=${RS_SESSION:-$SESSION} EN= ENUM=
if [ -n "$ENTRY_N" ]; then
    [ -n "$ES" ] || { echo "$PROG: --entry needs the run's session" >&2; exit 64; }
    ENUM=$((10#$ENTRY_N))
    EN=$(printf '%06d' "$ENUM")
fi
RE_HEADING_TAG='^(Feature [0-9]+|Milestone [0-9]+|[A-Za-z]+[0-9]+[a-z]?)$'
case "$MODE" in
    list) ;;
    verdict|reopen) [[ $TAG =~ $RE_HEADING_TAG ]] && [ "${#TAG}" -le 40 ] \
                 || { echo "$PROG: refused: $TAG is not a milestone's heading tag (Feature 7, Milestone 7, ED1, AB10b)" >&2; exit 65; } ;;
    *) [[ $TAG =~ $RE_HEADING_TAG ]] || { echo "$PROG: $TAG is not a feature's heading tag (Feature 7, Milestone 7, ED1, AB10b)" >&2; exit 64; } ;;
esac
case "$OUTCOME$REASON" in *$'\n'*|*$'\r'*) echo "$PROG: --outcome and --reason are one line" >&2; exit 64 ;; esac

WD=$(mktemp -d "${TMPDIR:-/tmp}/roadmap-status.XXXXXX") || lib_die2 "cannot make a temporary directory"
trap 'rm -rf "$WD"' EXIT

rs_record "$WD/parsed.json"
case $? in
    0) ;;
    65) echo "$PROG: refused: $(lib_record_name) doesn't read back as a roadmap record for $NAME" >&2; exit 10 ;;
    4) lib_scrub < "$WD/parsed.json.err" >&2; exit 10 ;;
    12) lib_scrub < "$WD/parsed.json.err" >&2; exit 12 ;;
    *) lib_die2 "cannot read the record: $(lib_scrub < "$WD/parsed.json.err")" ;;
esac

# The pending rows, {unit, pull_request, attempted, action, how_to_confirm}
# (state-schema.jq pending_rows, which pick-facts.sh reads the same way).
jq -c -L "$HERE" 'include "state-schema"; pending_rows' "$WD/parsed.json" > "$WD/pending.json" \
    || lib_die2 "jq failed"
if [ "$MODE" = list ]; then
    jq -c -L "$HERE" 'include "state-schema"; pending_list' "$WD/parsed.json"
    exit 0
fi

refuse() { echo "$PROG: refused: $*" >&2; exit 65; }
lib_default_branch || lib_die2 "cannot read $REPO's default branch"
# feature_read <file>: FEATURE, TAG's entry as lib_roadmap_features reads the
# roadmap (its tag compared by key), or empty when no item carries TAG. A
# roadmap the reader can't read is a read failure, never a feature that isn't
# there. Sets RM_SECTION and RM_WORD, as the reader does.
feature_read() {
    lib_roadmap_features "$1" > "$WD/features.json" 2> "$WD/f.err" || lib_die2 "cannot read the features of $ROADMAP: $(lib_scrub < "$WD/f.err")"
    FEATURE=$(jq -c --arg t "$TAG" "$JQ_TAG_KEY"'[.[] | select((.id | tag_key) == ($t | tag_key))][0] // empty' "$WD/features.json") || lib_die2 "jq failed"
}
# words_read <file>: RM_SECTION and RM_WORD for the roadmap at FILE, and
# HEAD_TAG, TAG as that roadmap spells its heading (`Milestone 2` on v3 for a
# TAG of `Feature 2`).
words_read() {
    lib_roadmap_words "$1"
    HEAD_TAG=$(lib_heading_tag "$TAG")
}

# write_record <next-json> <entry-text>: the record through the write core,
# then the entry. The write core takes over the EXIT trap, so the entry's
# text is kept outside $WD. Only this script changes a verdict-owed Work row
# (the write core holds every other writer to that).
write_record() {
    # The state carries the written time of the version read, which the write
    # core compares with the live record's; its file stays in $WD, readable by
    # its owner only, and goes with it.
    jq --arg w "$(jq -r '.written' "$WD/parsed.json")" '.written = $w' "$1" > "$WD/state.json" || lib_die2 "jq failed"
    chmod 600 "$WD/state.json" || lib_die2 "cannot make the state file private"
    ENTRY_FILE=$(mktemp "${TMPDIR:-/tmp}/roadmap-status-entry.XXXXXX") || lib_die2 "cannot make a temporary file"
    printf '%s\n' "$2" > "$ENTRY_FILE"
    if [ "$OVERRIDE" = 1 ]; then ADDR=(--scope "$SCOPE" --name "$NAME" --repo "$REPO")
    else ADDR=(--session "$SESSION"); fi
    STATE_FILE="$WD/state.json" CORE_CLEANUP=$WD
    lib_write_guard
    . "$HERE/state-write-core.sh"
    VERDICT_WRITER=1
    core_write > /dev/null
    if ! bash "$HERE/state-entry.sh" "${ADDR[@]}" --kind roadmap-status --text-file "$ENTRY_FILE" > /dev/null; then
        echo "$PROG: the record was written, but its entry wasn't posted; post it with state-entry.sh --kind roadmap-status: $(cat "$ENTRY_FILE")" >&2
        rm -f "$ENTRY_FILE"; exit 14
    fi
    rm -f "$ENTRY_FILE"
}
# without_row <out> [clear-owed]: the record without TAG's pending row, and
# with clear-owed also without TAG's verdict-owed and rework Work rows (a
# confirmed verdict or reopen supersedes the rework an earlier one left).
without_row() {
    jq -L "$HERE" --arg t "$TAG" --argjson owed "${2:-false}" 'include "state-schema"; '"$JQ_TAG_KEY"' roadmap_edit_actions as $acts | del(.written)
        | .side_effects = [.side_effects[] | select(((.action as $a | any($acts[]; . == $a))
                                                     and (.target | index(" [") as $i | $i != null and (.[0:$i] | tag_key) == ($t | tag_key))) | not)]
        | if $owed then .work = [(.work // [])[] | select(((.kind == "verdict-owed" or .kind == "rework") and (.item | tag_key) == ($t | tag_key)) | not)]
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
    fu=$(jq -r --arg t "$TAG" "$JQ_TAG_KEY"'[(.work // [])[] | select(.kind == "follow-up" and (.item | tag_key) == ($t | tag_key)) | .who][0] // empty' "$WD/parsed.json")
    [ -z "$fu" ] || refuse "$TAG's scoping alone landed ($fu) and its execution is a follow-up still to dispatch; it isn't Done until that lands"
}
OWED_WHO=$(jq -r --arg t "$TAG" "$JQ_TAG_KEY"'[(.work // [])[] | select(.kind == "verdict-owed" and (.item | tag_key) == ($t | tag_key)) | .who][0] // empty' "$WD/parsed.json")

# norm_entry <in> <out>: an entry's text as state-entry.sh posts it: CR
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
# lc <text>: lower case, for the comparisons GitHub makes without case.
lc() { printf '%s' "$1" | tr 'A-Z' 'a-z'; }
# coordinator_login: LOGIN, the login this run posts as (gh api user), read
# once; a failed read exits 2.
coordinator_login() {
    [ -n "${LOGIN:-}" ] && return 0
    LOGIN=$(gh api user --jq .login 2> "$WD/u.err" < /dev/null) && [[ $LOGIN =~ $RE_LOGIN ]] \
        || lib_die2 "cannot read the login this run posts as: $(lib_scrub < "$WD/u.err")"
}
# posted_entry <comment-id> <out> <kind> [<pull request>]: the text of comment
# ID, as state-entry.sh posted it, normalised as norm_entry does. The issue
# or pull request it sits on is the API's issue_url, never the URL's path, and
# must be in the host repository. Given a pull request, the comment must be on
# it and its author the coordinator's login (anyone can comment on a pull
# request); without one (a row written while the record was on GitHub, whose
# comment is on that record's issue) any issue of the host is accepted, the
# marker, kind, text and hash checks bounding it. It must carry KIND's entry
# marker (milestone-verdict or milestone-failure); anything else is refused
# (65), and a failed read exits 2.
posted_entry() {
    local c on
    if ! c=$(gh api --method GET "repos/$REPO/issues/comments/$1" 2> "$WD/pc.err" < /dev/null); then
        grep -q 'HTTP 404' "$WD/pc.err" && refuse "no comment $1 on $REPO: the entry URL names no posted entry"
        lib_die2 "cannot read comment $1: $(lib_scrub < "$WD/pc.err")"
    fi
    on=$(printf '%s' "$c" | jq -r '.issue_url // ""') || lib_die2 "comment $1 is not JSON"
    if [[ $(lc "$on") =~ ^https://api\.github\.com/repos/([a-z0-9_.-]+/[a-z0-9_.-]+)/issues/([1-9][0-9]*)$ ]] \
        && [ "${BASH_REMATCH[1]}" = "$(lc "$REPO")" ]; then
        on=${BASH_REMATCH[2]}
    else
        on=
    fi
    [ -n "$on" ] || refuse "comment $1 is not on an issue or pull request of $REPO"
    if [ -n "${4:-}" ]; then
        [ "$on" = "$4" ] || refuse "comment $1 is not on the roadmap pull request #$4"
        coordinator_login
        [ "$(lc "$(printf '%s' "$c" | jq -r '.user.login // ""')")" = "$(lc "$LOGIN")" ] \
            || refuse "comment $1 on the roadmap pull request #$4 is not by the coordinator's login, $LOGIN"
    fi
    printf '%s' "$c" | jq -r '.body // ""' | tr -d '\r' > "$WD/pc.body" || lib_die2 "comment $1 is not JSON"
    [ "$(head -1 "$WD/pc.body")" = "${ENTRY_MARKER_PREFIX}$3 -->" ] \
        || refuse "comment $1 is not a $3 entry (one state-entry.sh --kind $3 posted)"
    # state-entry.sh writes `&` as `&amp;` and `@` as `&#64;`; decoded in
    # its reader's order, the text comes back as written.
    tail -n +4 "$WD/pc.body" | sed -e 's/&#64;/@/g' -e 's/&amp;/\&/g' > "$WD/pc.raw"
    norm_entry "$WD/pc.raw" "$2"
}

# ---- --entry N: the session's entry, posted on the roadmap pull request ------
# session_entry <kind>: ENTRY, session entry N's text normalised as
# norm_entry does, after checking its kind and size; refused (65) otherwise.
session_entry() {
    rs_key "$ES" "record/entries/$EN" "$WD/sentry.json"
    case $? in
        0) ;;
        1) refuse "the session holds no entry $ENUM" ;;
        *) lib_die2 "cannot read record/entries/$EN: $(lib_scrub < "$WD/sentry.json.err")" ;;
    esac
    local k
    k=$(jq -r '.kind // ""' "$WD/sentry.json") || lib_die2 "record/entries/$EN is not JSON"
    [ "$k" = "$1" ] || refuse "entry $ENUM is a ${k:-kindless} entry, not a $1 entry (state-entry.sh --kind $1 --on none writes one)"
    jq -r '.text // ""' "$WD/sentry.json" > "$WD/sentry.txt" || lib_die2 "record/entries/$EN is not JSON"
    local size
    size=$(wc -c < "$WD/sentry.txt" | tr -d ' ')
    [ "$size" -le "$ENTRY_MAX" ] || refuse "entry $ENUM is $size bytes, over $ENTRY_MAX"
    norm_entry "$WD/sentry.txt" "$ENTRY"
}
# own_row <action>...: RESUME 1, with PRL, PR_NUM and PR_URL, when a pending
# row of one of these Actions for TAG ends its How to confirm `(entry N)`:
# this entry's edit, opened by an earlier run that stopped before its post or
# its Progress commit. Otherwise RESUME 0, and an entry already posted
# anywhere is refused: its comment isn't on a pull request this run opens.
own_row() {
    local row
    RESUME=0
    row=$(jq -c --arg t "$TAG" --arg a "$*" --arg h "(entry $ENUM)" "$JQ_TAG_KEY"'
        [.[] | select((.unit | tag_key) == ($t | tag_key) and (.action as $x | $a | split(" ") | index($x)) != null
                      and (.how_to_confirm | endswith($h)))][0] // empty' "$WD/pending.json") || lib_die2 "jq failed"
    if [ -n "$row" ]; then
        RESUME=1
        PRL=$(printf '%s' "$row" | jq -r .pull_request)
        PR_NUM=$(printf '%s' "$PRL" | sed -n 's/^\[#\([1-9][0-9]*\)\](.*$/\1/p')
        PR_URL=$(printf '%s' "$PRL" | sed -n 's/^\[#[0-9]*\](\(https:[^)]*\))$/\1/p')
        [ -n "$PR_NUM" ] && [ -n "$PR_URL" ] || lib_die2 "$TAG's row names no pull request: $PRL"
        return 0
    fi
    rs_key "$ES" "record/posted/$EN" "$WD/already"
    case $? in
        0) refuse "entry $ENUM is already posted, at $(head -n 1 "$WD/already"); a roadmap edit posts its entry on the pull request it opens, so write the entry again with --on none" ;;
        1) ;;
        *) lib_die2 "cannot read record/posted/$EN: $(lib_scrub < "$WD/already.err")" ;;
    esac
}
# post_session_entry: ENTRY_URL, the comment entry N becomes on PR_NUM,
# posted through state-entry.sh so its content checks, its `@` escaping and
# its retry (a post that landed before a crash stands) apply. A failure exits
# 14 naming the pull request, which a run with the same entry finishes.
post_session_entry() {
    if ! ENTRY_URL=$(bash "$HERE/state-entry.sh" "${ADDR[@]}" --repost "$ENUM" --on "$REPO#$PR_NUM" 2> "$WD/pe.err" < /dev/null); then
        echo "$PROG: the roadmap pull request $PR_URL is open and its row written, but entry $ENUM wasn't posted on it: $(lib_scrub < "$WD/pe.err"); run this again with --entry $ENUM, which posts it once and pushes its Progress line" >&2
        exit 14
    fi
    ENTRY_URL=${ENTRY_URL%%$'\n'*}
    [[ $(lc "$ENTRY_URL") =~ ^https://github\.com/([a-z0-9_.-]+/[a-z0-9_.-]+)/pull/([1-9][0-9]*)#issuecomment-[1-9][0-9]*$ ]] \
        && [ "${BASH_REMATCH[1]}" = "$(lc "$REPO")" ] && [ "${BASH_REMATCH[2]}" = "$PR_NUM" ] \
        || { echo "$PROG: entry $ENUM's comment, $ENTRY_URL, is not on the roadmap pull request $PR_URL" >&2; exit 14; }
}
# progress_commit <message>: PROGRESS's lines added to `## Progress` on the
# pull request's branch, as a second commit; nothing when the branch already
# carries them all (a run that stopped after pushing it). The branch is
# BRANCH_NEW on a first run, else the pull request's, which must still be
# open. A failure exits 14 naming the pull request.
progress_commit() {
    local branch st pl missing=0 crlf=0 blob
    if [ "$RESUME" = 1 ]; then
        gh pr view "$PR_NUM" --repo "$REPO" --json state,headRefName > "$WD/pr.json" 2> "$WD/pv.err" < /dev/null \
            || lib_die2 "cannot read pull request #$PR_NUM: $(lib_scrub < "$WD/pv.err")"
        st=$(jq -r '.state // ""' "$WD/pr.json") branch=$(jq -r '.headRefName // ""' "$WD/pr.json")
        [ "$st" = OPEN ] || refuse "the roadmap pull request $PR_URL is $st without its Progress line; drop its row with --drop $TAG, then run this again"
    else
        branch=$BRANCH_NEW
    fi
    [[ $branch =~ ^coordinate/roadmap-(verdict|reopen)-[a-z0-9-]+-[0-9]{12,14}$ ]] \
        || lib_die2 "pull request #$PR_NUM's branch, $branch, is not one this script opens"
    gh api --method GET "repos/$REPO/contents/$ROADMAP?ref=$branch" > "$WD/bcontents.json" 2> "$WD/bc.err" < /dev/null \
        || { echo "$PROG: the roadmap pull request $PR_URL is open and entry $ENUM posted ($ENTRY_URL), but $ROADMAP on $branch can't be read: $(lib_scrub < "$WD/bc.err"); run this again with --entry $ENUM" >&2; exit 14; }
    blob=$(jq -r '.sha // empty' "$WD/bcontents.json")
    [[ $blob =~ $RE_SHA ]] || lib_die2 "$ROADMAP's blob sha on $branch is not a sha"
    jq -r '.content // ""' "$WD/bcontents.json" > "$WD/branch.b64" && lib_b64d "$WD/branch.b64" "$WD/branch.md" || lib_die2 "cannot decode $ROADMAP on $branch"
    while IFS= read -r pl; do
        bash "$HERE/milestone.sh" progress-has "$WD/branch.md" "$pl" || missing=1
    done <<EOF
$PROGRESS
EOF
    [ "$missing" = 1 ] || return 0
    grep -q $'\r$' "$WD/branch.md" && crlf=1
    BE_SRC="$WD/branch.md" block_edit "$WD/branch.new" "" 0 "" "$PROGRESS"
    while IFS= read -r pl; do
        bash "$HERE/milestone.sh" progress-has "$WD/branch.new" "$pl" || refuse "the Progress line could not be written into $ROADMAP"
    done <<EOF
$PROGRESS
EOF
    if [ "$crlf" = 1 ]; then sed 's/$/\r/' "$WD/branch.new" > "$WD/branch.crlf" && mv "$WD/branch.crlf" "$WD/branch.new"; fi
    base64 < "$WD/branch.new" | tr -d '\n\r ' > "$WD/bcontent"
    gh api --method PUT "repos/$REPO/contents/$ROADMAP" -f "message=$1" \
        -f "content=$(cat "$WD/bcontent")" -f "sha=$blob" -f "branch=$branch" > /dev/null 2> "$WD/w.err" < /dev/null \
        || { echo "$PROG: the roadmap pull request $PR_URL is open and entry $ENUM posted ($ENTRY_URL), but the commit of its Progress line to $branch failed: $(lib_scrub < "$WD/w.err"); run this again with --entry $ENUM" >&2; exit 14; }
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
    why=$(jq -R -s -r -L "$HERE" 'include "state-schema"; text_problem([]) // empty' < "$FOLLOW_UPS")
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
    RE_FU_HEAD='^### (Feature [0-9]+|Milestone [0-9]+|[A-Za-z]+[0-9]+[a-z]?): (.+)$'
    : > "$WD/fu/index.tsv"
    i=1
    while [ "$i" -le "$n" ]; do
        head=$(head -1 "$WD/fu/$i.md")
        [[ $head =~ $RE_FU_HEAD ]] || refuse "follow-up section $i's heading is not \`### <tag>: <title>\`: [${head:0:80}]"
        tag=${BASH_REMATCH[1]} title=${BASH_REMATCH[2]}
        # A section is headed as the roadmap heads its milestones: `Milestone
        # N` on v3, `Feature N` on v2.
        [ "$(lib_heading_tag "$tag")" = "$tag" ] \
            || refuse "follow-up section $tag: this roadmap heads its milestones $RM_WORD N, so write \`### $(lib_heading_tag "$tag"): $title\`"
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
        # Checked in a document of the roadmap's own version and section.
        { printf -- '---\nschema: %s\n---\n\n## %s\n\n' "$(if [ "$RM_WORD" = Milestone ]; then echo roadmap/v3; else echo roadmap/v2; fi)" "$RM_SECTION"
          cat "$WD/fu/$i.md"; printf '**Status:** Not started\n'; } > "$WD/fu/$i.check"
        bash "$HERE/milestone.sh" evidence "$WD/fu/$i.check" "$tag" > "$WD/fu/$i.json" 2> /dev/null \
            || refuse "follow-up section $tag: its Evidence is not one \`- \` clause or more"
        printf '%s\t%s\t%s\t%s\n' "$i" "$tag" "$title" "$(lib_tag_key "$tag")" >> "$WD/fu/index.tsv"
        i=$((i + 1))
    done
    DUPTAGS=$(cut -f4 "$WD/fu/index.tsv" | sort | uniq -d)
    [ "${DUPTAGS%%$'\n'*}" = "" ] || refuse "two follow-up sections share a tag"
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
            [ "$(lib_tag_key "$t")" != "$(lib_tag_key "$TAG")" ] || refuse "a follow-up amends $TAG itself; the milestone this verdict verifies keeps the Evidence it was judged against"
            bash "$HERE/milestone.sh" evidence "$WD/roadmap.md" "$t" > "$WD/fu/target.json" 2> /dev/null \
                || refuse "the follow-up \`amend $t\` names a tag the roadmap has no milestone for"
            i=$(RS_KEY="$(lib_tag_key "$t")" awk -F'\t' '$4 == ENVIRON["RS_KEY"] { print $1; exit }' "$WD/fu/index.tsv")
            [ -n "$i" ] || refuse "the follow-up \`amend $t\` has no section in the follow-ups file (a \`### $(lib_heading_tag "$t"): <title>\` heading)"
            ftitle=$(awk -F'\t' -v i="$i" '$1 == i { print $3 }' "$WD/fu/index.tsv")
            [ "$ftitle" = "$(jq -r .title "$WD/fu/target.json")" ] \
                || refuse "the amend section for $t retitles it; an amendment changes Outcome, Evidence or Left open, never the title"
            # Dependencies don't change in place (roadmap format): the
            # section's must be the milestone's.
            [ "$(field_of "$WD/fu/$i.md" Dependencies)" = "$(tr -d '\r' < "$WD/roadmap.md" | RS_H="### $(lib_heading_tag "$t"): " RS_SECTION="## $RM_SECTION" awk '
                    BEGIN { h = ENVIRON["RS_H"]; sect = ENVIRON["RS_SECTION"] }
                    /^## / { s = $0; sub(/[ \t]+$/, "", s); inf = (s == sect); inb = 0; next }
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
            RS_TAG="$(lib_heading_tag "$at")" RS_SECTION="## $RM_SECTION" RS_OUT="$(field_of "$WD/fu/$i.md" Outcome)" RS_EVI="$(field_of "$WD/fu/$i.md" Evidence)" \
            RS_LEFT="$(field_of "$WD/fu/$i.md" "Left open")" awk '
                BEGIN { h = "### " ENVIRON["RS_TAG"] ": "; sect = ENVIRON["RS_SECTION"]; r["Outcome"] = ENVIRON["RS_OUT"]; r["Evidence"] = ENVIRON["RS_EVI"]; r["Left open"] = ENVIRON["RS_LEFT"] }
                dropping && (/^[ \t]*$/ || /^\*\*[A-Z][A-Za-z ]*:\*\*/ || /^#/) { dropping = 0 }
                dropping { next }
                /^## / { s = $0; sub(/[ \t]+$/, "", s); inf = (s == sect); inb = 0; print; next }
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
        # After the last milestone: where the items section ends, at the
        # next `## ` heading or the end of the file.
        RS_NEW="$new" RS_SECTION="## $RM_SECTION" awk '
            BEGIN { s = ENVIRON["RS_NEW"]; sub(/\n+$/, "", s); sect = ENVIRON["RS_SECTION"] }
            function put() { if (pb) print ""; print s; print ""; done = 1 }
            /^## / && inf && !done { put() }
            /^## / { h = $0; sub(/[ \t]+$/, "", h); inf = (h == sect) }
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
    printf '%s' "$1" | jq -R -s -r -L "$HERE" 'include "state-schema"; (rework_problem // text_problem([])) // empty'
}
# failure_rework_of <entry>: the rework text a confirmed reopen leaves for the
# milestone's next brief, `Evidence clause <n> failed: <what was seen>`, cut
# to the codec's 600 bytes (rework_cap): What was seen may be 600 bytes
# itself, and the prefix would put the whole over. render-brief.sh picks its
# failure wording on that prefix, so the two change together.
failure_rework_of() {
    awk '/^Clause: / { c = substr($0, 9) } /^What was seen: / { w = substr($0, 16) }
         END { printf "Evidence clause %s failed: %s", c, w }' "$1" \
        | jq -R -s -j -L "$HERE" 'include "state-schema"; rework_cap'
}
# reopen_line <roadmap>: the last `## Progress` line naming TAG (its tag
# compared by key, so `Feature 2` and `Milestone 2` are one), when it is a
# reopen line --reopen writes for a failure posted on the row's own pull
# request (ROW_PR), or, written while the record was on GitHub, on an issue of
# the host. Sets RL_CLAUSE, RL_URL, RL_ID, RL_HASH and RL_PR (ROW_PR, or empty
# for an issue); returns 1 otherwise. The key and the URLs are compared as
# text, never as patterns.
reopen_line() {
    local last pre rest re ltag
    last=$(tr -d '\r' < "$1" | RS_KEY="$(lib_tag_key "$TAG")" awk '
        BEGIN { k = ENVIRON["RS_KEY"] }
        /^## / { inprog = ($0 ~ /^## Progress[ \t]*$/); next }
        inprog && /^- [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]: / {
            rest = substr($0, 15); p = index(rest, " -- ")
            if (p == 0) next
            tg = substr(rest, 1, p - 1)
            if (tg ~ /^(Feature|Milestone) [0-9]+$/) tg = "ms:" substr(tg, index(tg, " ") + 1)
            if (tg == k) last = $0
        }
        END { print last }')
    ltag=${last:14}; ltag=${ltag%% -- *}
    pre="${last:0:12}: $ltag -- reopened: clause "
    [ -n "$last" ] && [ "${last:0:${#pre}}" = "$pre" ] || return 1
    rest=${last:${#pre}}
    re='^([1-9][0-9]*) failed, reported by .+ \((https://github\.com/[^ ]+#issuecomment-([1-9][0-9]*)), ([0-9a-f]{8})\)$'
    [[ $rest =~ $re ]] || return 1
    RL_CLAUSE=${BASH_REMATCH[1]} RL_URL=${BASH_REMATCH[2]} RL_ID=${BASH_REMATCH[3]} RL_HASH=${BASH_REMATCH[4]}
    # A comment on the reopen's own pull request, ROW_PR, or on an issue of the
    # host (the record's, while it was on GitHub).
    RL_PR=
    if [ -n "${ROW_PR:-}" ] && [ "$(lc "$RL_URL")" = "$(lc "https://github.com/$REPO/pull/$ROW_PR#issuecomment-$RL_ID")" ]; then
        RL_PR=$ROW_PR
        return 0
    fi
    [[ $(lc "$RL_URL") =~ ^https://github\.com/([a-z0-9_.-]+/[a-z0-9_.-]+)/issues/[1-9][0-9]*#issuecomment-[1-9][0-9]*$ ]] \
        && [ "${BASH_REMATCH[1]}" = "$(lc "$REPO")" ]
}

# block_edit <out> <status> <done> <deliver> <progress>: the roadmap at
# $WD/roadmap.md with TAG's block and the Progress section edited, and
# nothing else before the populate: STATUS, when not empty, replaces TAG's
# Status; DONE 1 also drops its Needs field and adds DELIVER to its Delivered
# field; PROGRESS (one line or more) goes after the last line of `## Progress`,
# and an empty PROGRESS adds nothing there (--entry's first commit, whose
# Progress lines wait for the comment they name).
# Values reach awk through the environment, which takes them as written.
# TAG's block is its heading as the roadmap spells it (HEAD_TAG) under the
# roadmap's items section; call words_read on $WD/roadmap.md first. BE_SRC
# names another copy of the roadmap to edit (the pull request's branch).
block_edit() {
    tr -d '\r' < "${BE_SRC:-$WD/roadmap.md}" | RS_TAG="$HEAD_TAG" RS_SECTION="## $RM_SECTION" RS_STATUS="$2" RS_DONE="$3" RS_DELIVER="$4" RS_PROGRESS="$5" awk '
        BEGIN { tag = ENVIRON["RS_TAG"]; sect = ENVIRON["RS_SECTION"]; status = ENVIRON["RS_STATUS"]; done = ENVIRON["RS_DONE"] == "1"; deliver = ENVIRON["RS_DELIVER"]; progress = ENVIRON["RS_PROGRESS"] }
        function field_end() { return ($0 ~ /^[ \t]*$/ || $0 ~ /^\*\*[A-Z][A-Za-z ]*:\*\*/ || $0 ~ /^#+([ \t]|$)/) }
        # The Delivered field held back, so the last of its lines takes the new items.
        function flush_delivered() { if (nd) { dl[nd] = dl[nd] ", " deliver; for (i = 1; i <= nd; i++) print dl[i]; nd = 0 } }
        # The Progress section held back, so the new line goes after its last non-blank line.
        function flush_progress(   i, last) {
            if (progress == "") { for (i = 1; i <= np; i++) print pl[i]; np = 0; inprog = 0; wrote = 1; return }
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
            h = $0; sub(/[ \t]+$/, "", h); infeat = (h == sect); inblock = 0
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
    ROW=$(jq -c --arg t "$TAG" "$JQ_TAG_KEY"'[.[] | select((.unit | tag_key) == ($t | tag_key))][0] // empty' "$WD/pending.json")
    [ -n "$ROW" ] || refuse "no roadmap pull request is pending for $TAG"
    ACTION=$(printf '%s' "$ROW" | jq -r .action)
    PRL=$(printf '%s' "$ROW" | jq -r .pull_request)
    # The roadmap pull request's number, where an --entry edit posted its entry.
    ROW_PR=$(printf '%s' "$PRL" | sed -n 's/^\[#\([1-9][0-9]*\)\](.*$/\1/p')
    if [ "$MODE" = confirm ]; then
        lib_file_at "$ROADMAP" "$DEFAULT_BRANCH" "$WD/roadmap.md"
        case $? in 0) ;; 1) lib_die2 "$ROADMAP is not on $DEFAULT_BRANCH" ;; *) lib_die2 "cannot read $ROADMAP" ;; esac
        if [ "$ACTION" = milestone-verdict ]; then
            URL=$(printf '%s' "$ROW" | jq -r '.how_to_confirm | capture(" carries (?<u>[^ ]+) in Progress$").u // empty')
            # An --entry edit's row names its entry, whose comment URL the
            # session keeps in record/posted/<n>.
            RN=$(printf '%s' "$ROW" | jq -r '.how_to_confirm | capture(" \\(entry (?<n>[1-9][0-9]{0,5})\\)$").n // empty')
            if [ -z "$URL" ] && [ -n "$RN" ]; then
                rs_key "${RS_SESSION:-$SESSION}" "record/posted/$(printf '%06d' "$RN")" "$WD/rowposted"
                case $? in
                    0) URL=$(head -n 1 "$WD/rowposted") ;;
                    1) echo "$PROG: entry $RN, $TAG's verdict, isn't posted on $PRL yet; run --verdict $TAG --entry $RN again, which posts it and pushes its Progress line" >&2; exit 1 ;;
                    *) lib_die2 "cannot read record/posted/$RN: $(lib_scrub < "$WD/rowposted.err")" ;;
                esac
            fi
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
            # A row naming its entry posted it on its own pull request; one
            # naming the comment's URL is from the record's time on GitHub.
            if [ -n "$RN" ]; then
                posted_entry "${URL##*#issuecomment-}" "$WD/posted.txt" milestone-verdict "$ROW_PR"
            else
                posted_entry "${URL##*#issuecomment-}" "$WD/posted.txt" milestone-verdict
            fi
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
                || { echo "$PROG: $ROADMAP on $DEFAULT_BRANCH reads $TAG In progress, but its last Progress line about $TAG is no reopen this run wrote; its reopen pull request, $PRL, hasn't landed" >&2; exit 1; }
            # The failure as reported, which must still be the text the
            # Progress line hashed, name TAG and name the line's clause.
            posted_entry "$RL_ID" "$WD/posted.txt" milestone-failure "$RL_PR"
            [ "$RL_HASH" = "$(sha8 "$WD/posted.txt")" ] \
                || refuse "the entry at $RL_URL is not the text its Progress line hashed ($RL_HASH); it changed since its reopen edit, so nothing is confirmed: check the comment's history"
            FL=$(sed -n 1p "$WD/posted.txt")
            [ "${FL:0:9}" = "Failure: " ] && [ "$(lib_tag_key "${FL:9}")" = "$(lib_tag_key "$TAG")" ] && [ "$(sed -n 4p "$WD/posted.txt")" = "Clause: $RL_CLAUSE" ] \
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
    printf '%s\n' "$ES"
    exit 0
    ;;
esac

if [ "$MODE" = verdict ]; then
    # ---- --verdict: the roadmap edit a checked verdict calls for ----------
    ENTRY="$WD/entry.txt"
    RESUME=0
    # The session's entry, which this run posts on the pull request it opens;
    # or, when its row is already pending, the edit an earlier run opened,
    # which this run finishes.
    session_entry milestone-verdict
    own_row milestone-done milestone-verdict
    [ -n "$OWED_WHO" ] || refuse "$TAG has no verdict-owed row: tick landed for it first, which writes one"
    [ "$RESUME" = 1 ] || pending_refuse
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
    words_read "$WD/roadmap.md"
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
    # verdict_progress: PROGRESS, the verdict's line and each amendment's,
    # naming the entry's comment at ENTRY_URL.
    verdict_progress() {
        local k i at
        PROGRESS="- $CHECKED_ON: $HEAD_TAG -- $VERDICT, checked by $CHECKER ($ENTRY_URL, $HASH)"
        # Each amendment a follow-up makes is named in Progress, as the format
        # asks of an Outcome, Evidence or Left open changed in place.
        while IFS='	' read -r k i at; do
            [ "$k" = amend ] || continue
            PROGRESS="$PROGRESS"$'\n'"- $CHECKED_ON: $(lib_heading_tag "$at") amended -- a follow-up of the verified verdict on $HEAD_TAG ($ENTRY_URL)"
        done < "$WD/fu-plan.tsv"
    }
    # The comment doesn't exist yet: the first commit carries no Progress line,
    # and the second adds them once the entry is posted.
    PROGRESS=
    DONE=0 DELIVER=
    if [ "$VERDICT" != "changes needed" ]; then
        DONE=1
        # The Work checked pull requests the Delivered line doesn't name yet.
        DELIVER=$(jq -r '.work_checked | join("\n")' "$WD/verdict.json" | while IFS= read -r item; do
            [ -n "$item" ] || continue
            tr -d '\r' < "$WD/roadmap.md" | RS_TAG="$HEAD_TAG" RS_SECTION="## $RM_SECTION" RS_ITEM="$item" awk '
                BEGIN { tag = ENVIRON["RS_TAG"]; sect = ENVIRON["RS_SECTION"]; item = ENVIRON["RS_ITEM"] }
                # names(s): s names item as a whole reference (#1 is not #12).
                function names(s,   p) {
                    while ((p = index(s, item)) > 0) {
                        if (substr(s, p + length(item), 1) !~ /[0-9]/) return 1
                        s = substr(s, p + 1)
                    }
                    return 0
                }
                /^## / { h = $0; sub(/[ \t]+$/, "", h); infeat = (h == sect); inblock = 0; next }
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
    if [ "$DONE" = 1 ] && [ -n "$DELIVER" ] && ! RS_H="### $HEAD_TAG: " RS_SECTION="## $RM_SECTION" awk '
            BEGIN { t = ENVIRON["RS_H"]; sect = ENVIRON["RS_SECTION"] }
            /^## / { h = $0; sub(/[ \t]+$/, "", h); infeat = (h == sect); inb = 0; next }
            infeat && /^### / { inb = (index($0, t) == 1); next }
            inb && /^\*\*Delivered:\*\*/ { f = 1 }
            END { exit(f ? 0 : 1) }' "$DOC.1"; then
        RS_TAG="$HEAD_TAG" RS_SECTION="## $RM_SECTION" RS_DELIVER="$DELIVER" awk '
            BEGIN { tag = ENVIRON["RS_TAG"]; sect = ENVIRON["RS_SECTION"]; deliver = ENVIRON["RS_DELIVER"] }
            /^## / { h = $0; sub(/[ \t]+$/, "", h); infeat = (h == sect); inb = 0; print; next }
            infeat && /^### / { inb = (index($0, "### " tag ": ") == 1); print; next }
            inb && /^\*\*Status:\*\*/ { print; print "**Delivered:** " deliver; next }
            { print }' "$DOC.1" > "$DOC" || lib_die2 "awk failed"
    else
        mv "$DOC.1" "$DOC"
    fi
    [ ! -s "$WD/fu-plan.tsv" ] || follow_ups_apply "$DOC"
    if [ -n "$PROGRESS" ]; then
        while IFS= read -r pl; do
            bash "$HERE/milestone.sh" progress-has "$DOC" "$pl" || refuse "the Progress line could not be written into $ROADMAP"
        done <<EOF
$PROGRESS
EOF
    fi
    if [ "$DONE" = 1 ]; then
        bash "$HERE/milestone.sh" evidence "$DOC" "$TAG" 2> /dev/null | jq -e '.status == "Done"' > /dev/null \
            || refuse "$TAG's Status could not be set to Done (its block has no **Status:** line?)"
    fi
    if [ "$DONE" = 1 ]; then
        MSG="docs(roadmap): record $HEAD_TAG, $TITLE, as done on its verdict"
    else
        MSG="docs(roadmap): record the changes-needed verdict on $HEAD_TAG, $TITLE"
    fi
    BRANCH_STAMP=%Y%m%d%H%M%S
    if [ "$RESUME" = 0 ]; then
        populate_and_commit "$DOC" "$CRLF" coordinate/roadmap-verdict "$MSG"
        {
            if [ "$DONE" = 1 ]; then
                printf 'Records the %s verdict on %s of the roadmap, %s: its Status is Done, its Needs line goes and its Delivered line names the work checked; a Progress line names the verdict, who checked it and the entry. Its Outcome and Evidence are unchanged, and the generated sections are regenerated.\n' "$VERDICT" "$HEAD_TAG" "$TITLE"
            else
                printf 'Records the changes-needed verdict on %s of the roadmap, %s: a Progress line names the verdict, who checked it and the entry. Its Status and Delivered line are unchanged; the milestone stays open for the changes the verdict names.\n' "$HEAD_TAG" "$TITLE"
            fi
            if [ -s "$WD/fu-plan.tsv" ]; then
                printf '\nIts follow-ups, in the same edit:\n\n'
                while IFS='	' read -r k i at; do
                    if [ "$k" = new ]; then printf -- '- adds %s, Not started, after the last milestone\n' "$(head -1 "$WD/fu/$i.md" | sed -e 's/^### //' -e 's/&/\&amp;/g' -e 's/@/\&#64;/g')"
                    else printf -- '- amends %s: its Outcome, Evidence and Left open are the follow-up'"'"'s, with a Progress line naming the amendment\n' "$at"; fi
                done < "$WD/fu-plan.tsv"
            fi
            printf '\nThe verdict entry, as the coordinator recorded it; it is posted as a comment on this pull request, and a Progress line names that comment:\n\n'
            sed -e 's/&/\&amp;/g' -e 's/@/\&#64;/g' -e 's/^/> /' "$ENTRY"
            printf '\n---\n\n'
            printf 'Opened by the coordinator for %s. Review the verdict against the milestone'"'"'s Evidence before merging: on a milestone roadmap this pull request is what sets the Status, and the coordinator never merges it.\n' "$NAME"
        } > "$WD/prbody.md"
        open_pr "$MSG"
        # The row names its entry, which a run that stopped short finds it by,
        # and whose comment --confirm reads from record/posted.
        if [ "$DONE" = 1 ]; then ACTION=milestone-done HOW="the roadmap on $DEFAULT_BRANCH reads $TAG Done (entry $ENUM)"
        else ACTION=milestone-verdict HOW="the roadmap on $DEFAULT_BRANCH carries its entry's comment in Progress (entry $ENUM)"; fi
        CITED="entry $ENUM"
        jq --arg t "$TAG [#$PR_NUM]($PR_URL)" --arg at "$(date -u +%Y-%m-%dT%H:%MZ)" --arg a "$ACTION" --arg h "$HOW" '
            del(.written) | .side_effects += [{action: $a, target: $t, verified_head: "", attempted: $at, how_to_confirm: $h}]' \
            "$WD/parsed.json" > "$WD/next.json" || lib_die2 "jq failed"
        write_record "$WD/next.json" "$TAG's verdict, $VERDICT, checked by $CHECKER ($CITED), is on its roadmap pull request $PR_URL. Its verdict stays owed, and pick passes over $TAG, until that merges and is confirmed."
    fi
    post_session_entry
    verdict_progress
    progress_commit "docs(roadmap): name the verdict entry on $HEAD_TAG in Progress"
    printf '%s\n' "$PR_URL"
    exit 0
fi

if [ "$MODE" = reopen ]; then
    # ---- --reopen: the roadmap edit a failure after Done calls for ----------
    ENTRY="$WD/entry.txt"
    RESUME=0
    # The session's entry, as --verdict takes its own.
    session_entry milestone-failure
    own_row milestone-reopen
    [ "$RESUME" = 1 ] || pending_refuse
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
    words_read "$WD/roadmap.md"
    grep -qE $'^## Progress[ \t\r]*$' "$WD/roadmap.md" || refuse "$ROADMAP has no ## Progress section for the reopen's line"
    # Its confirmation leaves a rework row for the next brief: text the record
    # can't hold is refused now, before any edit is opened.
    WHY=$(rework_problem_of "$(failure_rework_of "$ENTRY")")
    [ -z "$WHY" ] || refuse "What was seen becomes the milestone's rework text, which the next brief quotes, and it can't ($WHY)"
    # The milestones a holding covers whose Dependencies name TAG, as pick
    # reads them: they read blocked again once this edit lands.
    lib_roadmap_features "$WD/roadmap.md" > "$WD/features.json" 2> "$WD/f.err" || lib_die2 "cannot read the features of $ROADMAP: $(lib_scrub < "$WD/f.err")"
    HELD=$(jq -r --arg t "$TAG" --slurpfile p "$WD/parsed.json" "$JQ_TAG_KEY"'
        def covers($id; $title): (tag_key == ($id | tag_key))
            or (index(": ") as $i | $i != null and (.[0:$i] | tag_key) == ($id | tag_key) and .[$i + 2:] == $title);
        ([.[] | select((.id | tag_key) == ($t | tag_key)) | .number][0]) as $n
        | .[] | select((.id | tag_key) != ($t | tag_key) and any(.dependencies[]; . == $n)) | . as $f
        | $p[0].holdings[] | select(.unit | covers($f.id; $f.title))
        | "held-dependent \($f.id) \(.worker)"' "$WD/features.json") || lib_die2 "jq failed"
    HASH=$(sha8 "$ENTRY")
    # The Progress line waits for the comment it names, as --verdict's does.
    PROGRESS=
    mkdir -p "$WD/doc"
    DOC="$WD/doc/$(basename "$ROADMAP")"
    CRLF=0
    grep -q $'\r$' "$WD/roadmap.md" && CRLF=1
    # TAG's Status and the Progress section: Delivered, Outcome and Evidence
    # stay, so the milestone is judged again against the Evidence it failed.
    block_edit "$DOC" "In progress" 0 "" "$PROGRESS"
    bash "$HERE/milestone.sh" evidence "$DOC" "$TAG" 2> /dev/null | jq -e '.status == "In progress"' > /dev/null \
        || refuse "$TAG's Status could not be set to In progress (its block has no **Status:** line?)"
    [ -z "$PROGRESS" ] || bash "$HERE/milestone.sh" progress-has "$DOC" "$PROGRESS" || refuse "the Progress line could not be written into $ROADMAP"
    MSG="docs(roadmap): reopen $HEAD_TAG, $TITLE, on a reported failure"
    BRANCH_STAMP=%Y%m%d%H%M%S
    if [ "$RESUME" = 0 ]; then
        populate_and_commit "$DOC" "$CRLF" coordinate/roadmap-reopen "$MSG"
        {
            printf 'Reopens %s of the roadmap, %s, on a failure reported after it read Done: its Status goes back to In progress and a Progress line names the failed clause, who reported it and the entry. Its Delivered line, Outcome and Evidence are unchanged, and the generated sections are regenerated.\n' "$HEAD_TAG" "$TITLE"
            printf '\nThe failure entry, as the coordinator recorded it; it is posted as a comment on this pull request, and the Progress line names that comment:\n\n'
            sed -e 's/&/\&amp;/g' -e 's/@/\&#64;/g' -e 's/^/> /' "$ENTRY"
            printf '\n---\n\n'
            printf 'Opened by the coordinator for %s. Check the report against the milestone'"'"'s Evidence before merging: on a milestone roadmap this pull request is what sends a Done milestone back to work, and the coordinator never merges it.\n' "$NAME"
        } > "$WD/prbody.md"
        open_pr "$MSG"
        HOW="the roadmap on $DEFAULT_BRANCH reads $TAG In progress (entry $ENUM)" CITED="entry $ENUM"
        jq --arg t "$TAG [#$PR_NUM]($PR_URL)" --arg at "$(date -u +%Y-%m-%dT%H:%MZ)" --arg h "$HOW" '
            del(.written) | .side_effects += [{action: "milestone-reopen", target: $t, verified_head: "", attempted: $at, how_to_confirm: $h}]' \
            "$WD/parsed.json" > "$WD/next.json" || lib_die2 "jq failed"
        write_record "$WD/next.json" "A failure of Evidence clause $CLAUSE of $TAG, reported by $REPORTER ($CITED), is on its reopen pull request $PR_URL. Until that merges and is confirmed, $TAG reads Done and pick passes over it."
    fi
    post_session_entry
    PROGRESS="- $SEEN_ON: $HEAD_TAG -- reopened: clause $CLAUSE failed, reported by $REPORTER ($ENTRY_URL, $HASH)"
    progress_commit "docs(roadmap): name the failure entry on $HEAD_TAG in Progress"
    printf '%s\n' "$PR_URL"
    [ -z "$HELD" ] || printf '%s\n' "$HELD"
    exit 0
fi

# ---- --unit ------------------------------------------------------------------
head_read
bash "$HERE/milestone.sh" is-milestone "$WD/roadmap.md"
case $? in
    0) MILESTONES=1 ;;
    1) MILESTONES=0 ;;
    *) lib_die2 "cannot read $ROADMAP's schema" ;;
esac

if [ "$MILESTONES" = 1 ]; then
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
    WHO=$(jq -r --arg t "$TAG" "$JQ_TAG_KEY"'[.holdings[] | select((.unit | tag_key) == ($t | tag_key)
        or (.unit | index(": ") as $i | $i != null and (.[0:$i] | tag_key) == ($t | tag_key))) | .worker][0] // "none"' "$WD/parsed.json")
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
words_read "$WD/roadmap.md"

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
tr -d '\r' < "$WD/roadmap.md" | RS_TAG="$HEAD_TAG" RS_SECTION="## $RM_SECTION" RS_DELIVERED="$OUTCOME" awk '
    BEGIN { tag = ENVIRON["RS_TAG"]; sect = ENVIRON["RS_SECTION"]; delivered = ENVIRON["RS_DELIVERED"] }
    dropping && (/^[ \t]*$/ || /^\*\*[A-Z][A-Za-z ]*:\*\*/ || /^#+([ \t]|$)/) { dropping = 0 }
    dropping { next }
    /^## / { h = $0; sub(/[ \t]+$/, "", h); infeat = (h == sect); inblock = 0; print; next }
    infeat && /^### / { inblock = (index($0, "### " tag ": ") == 1); print; next }
    inblock && /^\*\*Needs:\*\*/ { dropping = 1; next }
    inblock && /^\*\*Delivered:\*\*/ { dropping = 1; next }
    inblock && /^\*\*Status:\*\*/ { print "**Status:** Done"; print "**Delivered:** " delivered; next }
    { print }' > "$DOC" || lib_die2 "awk failed"
grep -qxF "**Delivered:** $OUTCOME" "$DOC" || refuse "the Delivered line could not be written into $TAG's block (it has no **Status:** line, or the text didn't survive as written)"
populate_and_commit "$DOC" "$CRLF" coordinate/roadmap-status "docs(roadmap): record $TAG, $TITLE, as done"
{
    printf 'Records %s of the roadmap, %s, as done: its Status is Done and its Delivered line reads "%s"; its Outcome, the promise, is unchanged. Its Needs line goes, as the roadmap'"'"'s rule for done features asks, and the generated sections are regenerated. Nothing else in the roadmap changes.\n\n---\n\n' "$TAG" "$TITLE" "$OUTCOME"
    printf 'Opened by the coordinator for %s, after it judged the feature'"'"'s last pull request landed. Review it against the roadmap'"'"'s own rules for an Active document before merging; the coordinator never merges it.\n' "$NAME"
} > "$WD/prbody.md"
open_pr "docs(roadmap): record $TAG, $TITLE, as done"

jq --arg t "$TAG [#$PR_NUM]($PR_URL)" --arg at "$(date -u +%Y-%m-%dT%H:%MZ)" --arg d "$DEFAULT_BRANCH" --arg tag "$TAG" '
    del(.written) | .side_effects += [{action: "roadmap-status", target: $t, verified_head: "", attempted: $at,
        how_to_confirm: "the roadmap on \($d) reads \($tag) Done"}]' "$WD/parsed.json" > "$WD/next.json" || lib_die2 "jq failed"
printf '%s\n' "$PR_URL" > "$WD/url"
URL_OUT=$(cat "$WD/url")
write_record "$WD/next.json" "$TAG landed; its roadmap pull request $PR_URL sets its Status to Done with the Delivered line \"$OUTCOME\". Pick passes over $TAG until it merges."
printf '%s\n' "$URL_OUT"
