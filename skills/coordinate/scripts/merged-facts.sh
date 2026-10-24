#!/usr/bin/env bash
# merged-facts.sh -- the check action of merged_facts: a person merged a
# parked pull request after a hand-over; did it land the head this run
# verified? Read-only.
#
# Usage: merged-facts.sh --session S [--unit <topic>] [--pr N --repo R] [--no-seal]
#
# The unit is the one the `merged` event named: the `unit` field of the latest
# evidence_submitted in state `wait` in the session log. --unit overrides it
# (for tests and hand runs; one outside the Worker cell's grammar, RE_TOPIC,
# is a usage error there). A logged unit outside that grammar, or one that
# names no holding with a pull request
# link (a unit's title or tag submitted in place of its topic, say), is
# refused: the token `unknown-topic`, which sends the run back to `wait` to
# submit the event again, with the reason and the accepted topics on stderr
# and in context key coord/merged_facts.json.
#
# The unit's topic only locates the holding: state-holding.sh --read finds
# its row on GitHub, whose Pull request cell gives the number and the
# repository. The head comes from the unit's own verify capture in this run
# (VERIFIED naming #<pr>, sealed at verify_board at any visit, reading
# `verified <pr> <sha>`), never from the record or the coordinator. Then the
# same check as merge-confirm.sh, from GitHub's record of the merge: the pull
# request's state and, when MERGED, that the head it merged is <sha> and its
# merge commit is on the default branch (board-lib.sh's bl_merge_compare).
# With no verified head in this run (no VERIFIED capture for the pull request,
# or the latest one isn't `verified <pr> <sha>`: verified by an earlier run,
# or accepted by a decision), there is nothing to compare with, and one read
# of the pull request decides instead (shirabe#560): merged is
# `unconfirmed <pr> <the head GitHub merged>`, open or closed is
# `not-merged <pr>`, each with the reason in coord/merged_facts.json.
#
# Token: `merged <pr> <sha>`, `unconfirmed <pr> <sha>` (merged, but from
# another head, or its merge commit isn't on the default branch, or from a
# head this run never verified), `not-merged <pr>`, or `unknown-topic`;
# sealed to the latest entry into merged_facts (captured as MERGED_FACTS).
# --pr with --repo skip the holding read, for tests; --no-seal (tests) prints
# the bare token.
#
# Exit codes: 0 a token printed; 2 a read failed (the log, the record or
# GitHub), which the next tick may get past; 64 usage.
set -uo pipefail

PROG=merged-facts
HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/board-lib.sh"

usage() { sed -n '/^# Usage:/p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 64; }
SESSION= UNIT= PR= REPO= NO_SEAL=0
while [ $# -gt 0 ]; do
    case "$1" in
        --session) [ $# -ge 2 ] || usage; SESSION=$2; shift 2 ;;
        --unit) [ $# -ge 2 ] || usage; UNIT=$2; shift 2 ;;
        --pr) [ $# -ge 2 ] || usage; PR=$2; shift 2 ;;
        --repo) [ $# -ge 2 ] || usage; REPO=$2; shift 2 ;;
        --no-seal) NO_SEAL=1; shift ;;
        *) usage ;;
    esac
done
bl_session_ok "$SESSION" || usage
[ -z "$UNIT" ] || bl_topic_ok "$UNIT" || usage

# refuse_unit <why>: the unit names no holding a merge can be about. Nothing
# is read further and nothing is written but this state's own verdict:
# `unknown-topic`, sealed, which sends the run back to the hub to submit the
# event again, with the reason and the accepted values on stderr and in
# context key coord/merged_facts.json. Exits 2 when the holdings can't be
# listed, so the tick is retried rather than refused on a guess.
refuse_unit() {
    local known
    known=$(bash "$HERE/state-holding.sh" --session "$SESSION" --list 2>/dev/null \
        | jq -c -L "$HERE" 'include "state-schema"; [.[]? | select([(.pull_request // "") | pr_link] | length > 0) | .worker]') || {
        echo "$PROG: the record's holdings could not be read" >&2; exit 2; }
    DETAIL=$(mktemp "${TMPDIR:-/tmp}/merged-facts.XXXXXX") || exit 2
    # lib_emit exits through this trap. no_verified_head sets the only other
    # one; both functions end the script, so one invocation reaches at most
    # one of the two and neither trap replaces the other's file.
    trap 'rm -f "$DETAIL"' EXIT
    jq -n --arg u "${UNIT:0:80}" --arg why "$1" --argjson known "$known" \
        --arg lead "the merged event's unit" --arg want "unit takes the dispatch topic of a holding with a pull request (its Worker), one of" \
        '{verdict: "unknown-topic", field: "unit", value: $u, accepted: $known,
          reason: ($lead + " [" + $u + "] " + $why + "; " + $want + ": "
                   + (if ($known | length) == 0 then "none (no holding has a pull request yet)" else ($known | join(", ")) end))}' > "$DETAIL"
    echo "$PROG: refused: $(jq -r .reason "$DETAIL")" >&2
    lib_emit merged_facts unknown-topic coord/merged_facts.json "$DETAIL"
}

if [ -n "$PR$REPO" ]; then
    bl_pr_ok "$PR" && bl_repo_ok "$REPO" || usage
else
    if [ -z "$UNIT" ]; then
        EV=$(bash "$HERE/coord-log.sh" evidence --session "$SESSION" --state wait 2>/dev/null)
        [ $? -eq 2 ] && { echo "$PROG: no readable log for $SESSION" >&2; exit 2; }
        UNIT=$(printf '%s' "$EV" | jq -r '.fields.unit // ""')
        bl_topic_ok "$UNIT" || refuse_unit "is not a topic"
    fi
    ROW=$(bash "$HERE/state-holding.sh" --session "$SESSION" --topic "$UNIT" --read)
    case $? in
        0) ;;
        1) refuse_unit "names no holding in the record" ;;
        *) echo "$PROG: the holding read failed" >&2; exit 2 ;;
    esac
    if ! lib_pr_link "$(printf '%s' "$ROW" | jq -r '.pull_request // ""')" \
        || ! bl_pr_ok "$LINK_NUM" || ! bl_repo_ok "$LINK_REPO"; then
        refuse_unit "names a holding with no pull request link"
    fi
    REPO=$LINK_REPO
    PR=$LINK_NUM
fi

# no_verified_head <why>: this run holds no verified head for #$PR (it was
# verified by an earlier run, or accepted by a decision, or the latest verify
# read it unverified; shirabe#560), so there is nothing to compare a merge
# with. Re-ticking would read the same log, so the run is not left here: one
# read of GitHub's record of the pull request decides where it goes, sealed
# like any verdict, with the reason in context key coord/merged_facts.json.
# MERGED is `unconfirmed <pr> <the head GitHub merged>`: a merge this run
# can't confirm, written down as the Side effects row any unconfirmed merge
# gets, at the head GitHub merged so a later reconcile's merge check can
# confirm that row. A head an earlier run verified isn't compared: the head
# comes from this run's capture, never from the record. Open or closed is
# `not-merged <pr>`, back to wait: an open one is verified before the merged
# event is submitted again, a closed one has no merge to record. A failed
# read exits 2, since it may succeed on the next tick. It never returns: every
# path ends the script, through lib_emit or an exit, like refuse_unit.
no_verified_head() {
    local d state head token next
    d=$(mktemp -d "${TMPDIR:-/tmp}/merged-facts.XXXXXX") || exit 2
    trap 'rm -rf "$d"' EXIT
    bl_gh "$d/pr" pr view "$PR" --repo "$REPO" --json state,headRefOid || { echo "$PROG: a read failed" >&2; exit 2; }
    state=$(jq -r '.state // "" | tostring' "$d/pr")
    head=$(jq -r '.headRefOid // "" | tostring' "$d/pr")
    case "$state" in
        MERGED)
            bl_sha_ok "$head" || { echo "$PROG: #$PR merged head [$head] is not a sha" >&2; exit 2; }
            token="unconfirmed $PR $head"
            next="GitHub merged #$PR at $head, which this run never verified: record it as a Side effects row for $REPO#$PR at $head" ;;
        OPEN)
            bl_sha_ok "$head" || head=
            token="not-merged $PR"
            next="#$PR is still open on GitHub: drive it through verify (a report event for its unit, classified done) before submitting the merged event again" ;;
        CLOSED)
            bl_sha_ok "$head" || head=
            token="not-merged $PR"
            next="#$PR was closed on GitHub without merging: there is no merge to record" ;;
        *) echo "$PROG: pull request state [$state]" >&2; exit 2 ;;
    esac
    jq -n --arg v "${token%% *}" --argjson pr "$PR" --arg repo "$REPO" --arg head "$head" --arg why "$1" --arg next "$next" \
        '{verdict: $v, pr: $pr, repo: $repo, head: (if $head == "" then null else $head end),
          reason: ($why + "; " + $next)}' > "$d/detail" || exit 2
    echo "$PROG: $(jq -r .reason "$d/detail")" >&2
    lib_emit merged_facts "$token" coord/merged_facts.json "$d/detail"
}

CAP=$(bl_capture "$SESSION" VERIFIED verify_board --any-visit --for "$PR")
case $? in
    0) ;;
    1) no_verified_head "no verify capture for #$PR in this run" ;;
    *) echo "$PROG: the verify capture for #$PR could not be read" >&2; exit 2 ;;
esac
set -f; set -- $CAP; set +f
if [ $# -ne 3 ] || [ "$1" != verified ] || [ "$2" != "$PR" ] || ! bl_sha_ok "$3"; then
    no_verified_head "the verify capture for #$PR reads [$CAP], not a verified head"
fi
SHA=$3

R=$(bl_merge_compare "$REPO" "$PR" "$SHA") || { echo "$PROG: a read failed" >&2; exit 2; }
case "$R" in
    merged) TOKEN="merged $PR $SHA" ;;
    unconfirmed) TOKEN="unconfirmed $PR $SHA" ;;
    not-merged) TOKEN="not-merged $PR" ;;
    *) exit 2 ;;
esac
bl_seal "$SESSION" merged_facts "$TOKEN" "$NO_SEAL" || exit 2
