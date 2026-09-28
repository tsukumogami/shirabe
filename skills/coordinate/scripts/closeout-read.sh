#!/usr/bin/env bash
# closeout-read.sh -- the check action of states rotation_close,
# predecessor_close and roadmap_close: where does the close-out stand?
#
# Discipline scope. The pull request is the run's own record (coord-log.sh
# run-facts) or, with --predecessor, the one the run's HANDOFF capture names
# (`rendered <n>`, sealed at the latest entry into predecessor_handoff). It
# reads the pull request's state, draft flag, title and head, and
# docs/disciplines/<name>.md at that head and (own rotation) on the host's
# default branch. The stage, first that applies:
#   merged <pr>            the pull request merged
#   closed-unmerged <pr>   it closed without merging
#   handoff-missing <pr>   (open) the file at the head is absent, isn't a
#                          canonical handoff for this discipline, or its header
#                          date isn't the close date (own rotation: today UTC;
#                          predecessor: the title's end date). Own rotation
#                          also: it is a predecessor copy, or its reasoning is
#                          identical to the default branch's (not written
#                          fresh). --predecessor also: its tables, not-re-checked
#                          line and fixed sentence differ from the predecessor
#                          handoff re-rendered from the live body
#                          (predecessor-handoff.sh --out).
#   title-stale <pr>       (open, own rotation only) the title's end date isn't
#                          today UTC; a predecessor's title is never corrected
#   land <pr> <head>       (open) board-verdict.sh --repo R --pr <pr> reads
#                          verified at <head>
#   land-blocked <pr>      (open) the board reads unverified. coord-verdict.sh
#                          maps no code to it, so the state stays blocked
#                          until the coordinator fixes the record pull request
#                          and ticks again
# A board still pending, or a board read error, exits 2 so koto re-runs the
# read on the next tick. `handed-over` is never printed: a hand-over is the
# coordinator's step, and the read sees only its result (merged or closed).
#
# Roadmap scope. The record issue (run-facts) and the roadmap file on the
# host's default branch (the session's ROADMAP path, contents API, never a
# working tree). First that applies:
#   closed <n>         the record issue is closed
#   features-open <n>  a feature under `## Features` doesn't read Done or
#                      Dropped, the roadmap lists no feature, or it is missing
#   holdings <n>       Holdings isn't empty
#   side-effects <n>   Side effects in flight isn't empty
#   deferrals <n>      a Deferrals row isn't `filed #<n>` or `closed: <text>`
#   decisions <n>      a Decisions entry isn't settled
#   ready <n>          all clear
# <n> is the record's issue number in every roadmap token.
#
# The detail goes to context key coord/closeout.json as data, naming the first
# blocker: {verdict, scope, ref, state, draft, head, title, reason, blocker, board}.
#
# Usage:
#   closeout-read.sh --session S [--predecessor] [--today YYYY-MM-DD]
#   closeout-read.sh [--session S] --scope roadmap|discipline --name N --repo O/R
#                    --ref N [--predecessor] [--roadmap PATH] [--today YYYY-MM-DD]
#                    [--no-seal]                                     (tests)
#
# --today (tests; the template never passes it) stands in for today UTC.
#
# Exit codes: 0 a verdict was printed; 2 a read failed, the board is pending,
# or the run has no record; 64 usage.
#
# GitHub reads (all reads):
#   gh pr view <n> --repo R --json number,state,isDraft,title,headRefOid,url
#   gh issue view <n> --repo R --json state,body
#   gh api --method GET repos/R --jq .default_branch
#   gh api --method GET "repos/R/contents/<path>?ref=<ref>" --jq .content
#   board-verdict.sh --repo R --pr <n>; predecessor-handoff.sh (gh pr view)
set -uo pipefail

PROG=closeout-read
HERE=$(cd "$(dirname "$0")" && pwd)
SESSION= SCOPE= NAME= REPO= REF= TODAY= ARG_ROADMAP=
NO_SEAL=0 PRED=0

usage() { sed -n '/^# Usage:/,/^# Exit codes:/p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 64; }
while [ $# -gt 0 ]; do
    case "$1" in
        --session) [ $# -ge 2 ] || usage; SESSION=$2; shift 2 ;;
        --scope) [ $# -ge 2 ] || usage; SCOPE=$2; shift 2 ;;
        --name) [ $# -ge 2 ] || usage; NAME=$2; shift 2 ;;
        --repo) [ $# -ge 2 ] || usage; REPO=$2; shift 2 ;;
        --ref) [ $# -ge 2 ] || usage; REF=$2; shift 2 ;;
        --roadmap) [ $# -ge 2 ] || usage; ARG_ROADMAP=$2; shift 2 ;;
        --today) [ $# -ge 2 ] || usage; TODAY=$2; shift 2 ;;
        --predecessor) PRED=1; shift ;;
        --no-seal) NO_SEAL=1; shift ;;
        *) usage ;;
    esac
done
. "$HERE/record-common.sh"
ROADMAP=$ARG_ROADMAP
lib_facts
[ -z "$ARG_ROADMAP" ] || [ "$OVERRIDE" = 1 ] || usage
if [ -n "$TODAY" ]; then lib_valid_date "$TODAY" || usage; else TODAY=$(date -u +%Y-%m-%d); fi
[ "$PRED" = 0 ] || [ "$SCOPE" = discipline ] || usage

if [ "$SCOPE" = roadmap ]; then STATE_NAME=roadmap_close
elif [ "$PRED" = 1 ]; then STATE_NAME=predecessor_close
else STATE_NAME=rotation_close; fi

# The pull request or issue: the override --ref, the HANDOFF capture, or run-facts.
if [ "$PRED" = 1 ] && [ "$OVERRIDE" = 0 ]; then
    [ -z "$REF" ] || usage
    HC=$(bash "$HERE/coord-log.sh" capture --session "$SESSION" --name HANDOFF --state predecessor_handoff 2>/dev/null)
    case $? in
        0) ;;
        1) lib_die2 "the run has no sealed predecessor_handoff capture" ;;
        *) lib_die2 "cannot read the session log" ;;
    esac
    set -f; set -- $HC; set +f
    [ "${1-}" = rendered ] || lib_die2 "the predecessor's handoff was not rendered"
    REF=${2-}
    [[ $REF =~ $RE_NUM ]] || lib_die2 "the HANDOFF capture names no pull request"
else
    lib_run_ref || lib_die2 "the run has no found record"
fi

T=$(mktemp -d "${TMPDIR:-/tmp}/closeout-read.XXXXXX")
trap 'rm -rf "$T"' EXIT

V= REASON= BLOCKER=null PRSTATE= DRAFT= HEAD= TITLE= BOARD=null
finish() { # finish <token>
    [ -z "$REASON" ] || echo "$PROG: $REASON" >&2
    jq -n --arg v "${1%% *}" --arg scope "$SCOPE" --arg ref "$REF" --arg st "$PRSTATE" --arg d "$DRAFT" \
        --arg h "$HEAD" --arg t "$TITLE" --arg r "$REASON" --argjson b "$BLOCKER" --argjson board "$BOARD" \
        '{verdict: $v, scope: $scope, ref: $ref, state: $st, draft: $d, head: $h, title: $t, reason: $r,
          blocker: $b, board: $board}' > "$T/detail.json"
    lib_emit "$STATE_NAME" "$1" coord/closeout.json "$T/detail.json"
}

# ---- roadmap ----------------------------------------------------------------
if [ "$SCOPE" = roadmap ]; then
    lib_roadmap_path
    gh issue view "$REF" --repo "$REPO" --json state,body > "$T/issue.json" 2> "$T/issue.err" < /dev/null \
        || lib_die2 "cannot read issue #$REF: $(lib_scrub < "$T/issue.err")"
    PRSTATE=$(jq -r '.state // ""' "$T/issue.json")
    if [ "$PRSTATE" = CLOSED ]; then REASON="the record issue is closed"; finish "closed $REF"; fi
    lib_default_branch || lib_die2 "cannot read $REPO's default branch"
    lib_file_at "$ROADMAP" "$DEFAULT_BRANCH" "$T/roadmap.md"
    case $? in
        0) ;;
        1) REASON="$ROADMAP is not on $DEFAULT_BRANCH"; finish "features-open $REF" ;;
        *) lib_die2 "cannot read $ROADMAP: $(lib_scrub < "$T/roadmap.md.err")" ;;
    esac
    lib_roadmap_features "$T/roadmap.md" > "$T/features.json" || lib_die2 "cannot parse the roadmap's features"
    if [ "$(jq length "$T/features.json")" -eq 0 ]; then
        REASON="the roadmap lists no feature under ## Features"; finish "features-open $REF"
    fi
    OPEN=$(jq -c '[.[] | select(.done | not)]' "$T/features.json")
    if [ "$(printf '%s' "$OPEN" | jq length)" -gt 0 ]; then
        BLOCKER=$(printf '%s' "$OPEN" | jq -c '.[0] | {id, title, status}')
        REASON="$(printf '%s' "$OPEN" | jq length) feature(s) not Done or Dropped"
        finish "features-open $REF"
    fi
    jq -r '.body // ""' "$T/issue.json" > "$T/body.md"
    lib_parse "$T/body.md" "$T/parsed.json"
    case $? in
        0) ;;
        3|65) lib_die2 "#$REF is not a canonical roadmap record for $NAME: $(lib_scrub < "$T/parsed.json.err" | head -1)" ;;
        *) lib_die2 "record-parse.sh failed" ;;
    esac
    if [ "$(jq '.holdings | length' "$T/parsed.json")" -gt 0 ]; then
        BLOCKER=$(jq -c '.holdings[0] | {unit, worker, pull_request}' "$T/parsed.json")
        REASON="Holdings is not empty"; finish "holdings $REF"
    fi
    if [ "$(jq '.side_effects | length' "$T/parsed.json")" -gt 0 ]; then
        BLOCKER=$(jq -c '.side_effects[0] | {action, target}' "$T/parsed.json")
        REASON="Side effects in flight is not empty"; finish "side-effects $REF"
    fi
    BLOCKER=$(jq -c '[.deferrals[] | select(.disposition | test("^(filed #[1-9][0-9]*|closed: [\\s\\S]+)$") | not)][0] // null
        | if . == null then null else {deferral, disposition} end' "$T/parsed.json")
    if [ "$BLOCKER" != null ]; then
        REASON="a deferral is not filed or closed"; finish "deferrals $REF"
    fi
    BLOCKER=$(jq -c '[(.decisions.entries // [])[] | select(.state != "settled")][0] // null
        | if . == null then null else {decision, state, question} end' "$T/parsed.json")
    if [ "$BLOCKER" != null ]; then
        REASON="a decision is not settled"; finish "decisions $REF"
    fi
    REASON="every feature Done or Dropped and the record is clear"
    finish "ready $REF"
fi

# ---- discipline -------------------------------------------------------------
gh pr view "$REF" --repo "$REPO" --json number,state,isDraft,title,headRefOid,url > "$T/pr.json" 2> "$T/pr.err" < /dev/null \
    || lib_die2 "cannot read pull request #$REF: $(lib_scrub < "$T/pr.err")"
PRSTATE=$(jq -r '.state // ""' "$T/pr.json")
DRAFT=$(jq -r '.isDraft // false' "$T/pr.json")
HEAD=$(jq -r '.headRefOid // ""' "$T/pr.json")
TITLE=$(jq -r '.title // ""' "$T/pr.json" | lib_scrub)
case "$PRSTATE" in
    MERGED) REASON="the record pull request merged"; finish "merged $REF" ;;
    CLOSED) REASON="the record pull request closed without merging"; finish "closed-unmerged $REF" ;;
    OPEN) ;;
    *) lib_die2 "pull request #$REF has an unknown state" ;;
esac
[[ $HEAD =~ $RE_SHA ]] || lib_die2 "pull request #$REF has no usable head"

HANDOFF_PATH="docs/disciplines/$NAME.md"
missing() { REASON=$1; finish "handoff-missing $REF"; }

TITLE_OK=1
lib_rotation_dates "$(jq -r '.title // ""' "$T/pr.json")" || TITLE_OK=0
if [ "$PRED" = 1 ]; then
    [ "$TITLE_OK" = 1 ] || missing "the predecessor's title is not a rotation title, so its close date is unknown"
    CLOSE_DATE=$ROT_END
else
    CLOSE_DATE=$TODAY
fi

lib_file_at "$HANDOFF_PATH" "$HEAD" "$T/handoff.md"
case $? in
    0) ;;
    1) missing "$HANDOFF_PATH is not at the head" ;;
    *) lib_die2 "cannot read $HANDOFF_PATH at the head: $(lib_scrub < "$T/handoff.md.err")" ;;
esac
bash "$HERE/record-parse.sh" --format handoff "$T/handoff.md" > "$T/handoff.json" 2> "$T/handoff.err"
case $? in
    0) ;;
    3|65) missing "the file is not a canonical handoff: $(lib_scrub < "$T/handoff.err" | head -1)" ;;
    *) lib_die2 "record-parse.sh failed" ;;
esac
[ "$(jq -r '.scope.name' "$T/handoff.json")" = "$NAME" ] || missing "the file is the handoff of another discipline"
HDATE=$(jq -r '.rotation.date' "$T/handoff.json")
[ "$HDATE" = "$CLOSE_DATE" ] || missing "the header date is $HDATE, not the close date $CLOSE_DATE"

# reasoning <file>: the text under the reasoning heading, CR and trailing blank
# lines dropped, for comparing two files whether or not either parses.
reasoning() {
    tr -d '\r' < "$1" | awk 'found { print; next } $0 == "## Reasoning for the next rotation" { found = 1 }' \
        | awk '{ l[NR] = $0 } END { n = NR; while (n > 0 && l[n] ~ /^[ \t]*$/) n--; for (i = 1; i <= n; i++) print l[i] }'
}

if [ "$PRED" = 1 ]; then
    bash "$HERE/predecessor-handoff.sh" --scope discipline --name "$NAME" --repo "$REPO" --ref "$REF" \
        --out "$T/expected.md" --no-seal > "$T/expected.tok" 2> "$T/expected.err"
    rc=$?
    [ $rc -eq 0 ] || lib_die2 "cannot re-render the predecessor's handoff: $(lib_scrub < "$T/expected.err")"
    case "$(cat "$T/expected.tok")" in
        rendered\ *) ;;
        *) missing "the predecessor's live body no longer renders a handoff" ;;
    esac
    bash "$HERE/record-parse.sh" --format handoff "$T/expected.md" > "$T/expected.json" 2>/dev/null || lib_die2 "the re-rendered handoff does not parse"
    [ "$(jq -S -c . "$T/handoff.json")" = "$(jq -S -c . "$T/expected.json")" ] \
        || missing "the committed file differs from the predecessor's tables, not-re-checked line or fixed sentence"
else
    jq -e '.predecessor_copy == null' "$T/handoff.json" > /dev/null \
        || missing "the rotation's own handoff is a predecessor copy; write its reasoning fresh"
    lib_default_branch || lib_die2 "cannot read $REPO's default branch"
    lib_file_at "$HANDOFF_PATH" "$DEFAULT_BRANCH" "$T/previous.md"
    case $? in
        0) if [ "$(reasoning "$T/handoff.md")" = "$(reasoning "$T/previous.md")" ]; then
               missing "the reasoning is the one already on $DEFAULT_BRANCH, not written fresh"
           fi ;;
        1) ;;
        *) lib_die2 "cannot read $HANDOFF_PATH on $DEFAULT_BRANCH: $(lib_scrub < "$T/previous.md.err")" ;;
    esac
    if [ "$TITLE_OK" = 0 ]; then REASON="the title is not a rotation title"; finish "title-stale $REF"; fi
    if [ "$ROT_END" != "$TODAY" ]; then REASON="the title ends $ROT_END, not today ($TODAY)"; finish "title-stale $REF"; fi
fi

bash "$HERE/board-verdict.sh" --repo "$REPO" --pr "$REF" > "$T/board.json" 2> "$T/board.err" < /dev/null \
    || lib_die2 "the board read failed: $(lib_scrub < "$T/board.err")"
BOARD=$(jq -c '{verdict, head, reasons: [(.reasons // [])[] | .code]}' "$T/board.json") || lib_die2 "the board read printed no JSON"
BV=$(printf '%s' "$BOARD" | jq -r '.verdict')
BH=$(printf '%s' "$BOARD" | jq -r '.head // ""')
case "$BV" in
    verified)
        [ "$BH" = "$HEAD" ] || lib_die2 "the board verified $BH but the head read $HEAD; tick again"
        REASON="the handoff is committed and the board verified the head"
        finish "land $REF $HEAD" ;;
    unverified)
        REASON="the record pull request's board is unverified; fix it and tick again"
        finish "land-blocked $REF" ;;
    pending) lib_die2 "the record pull request's board is still pending; tick again" ;;
    *) lib_die2 "the board read reported $BV" ;;
esac
