#!/usr/bin/env bash
# run-trail.sh -- the one writer of a run's record: the `trail/` keys in the
# run's own sessions and the run's entries in the per-PR index sessions.
#
# A plan's run is its own record. The record root (`execute-<topic>`) holds a
# `trail/` area naming what the run did, and each PR the run records gets an
# entry in its index session, `pr.<owner>.<repo>.<n>`, at the shared address
# scripts/lib/record-store.sh defines, so a reader holding only the PR's
# repository and number reaches the root (scripts/run-record-lookup.sh).
# Every write goes through a verb here, and each verb owns fixed keys:
#
#   self   --session S
#          record root: `trail/self`, {workspace, session, session_id, run_id}.
#          The run's address as its opener saw it: `pwd -P` of the checkout,
#          the session's koto `session_id` from `koto session list`, and the
#          session's `run_id`. /execute's opener writes it on every open.
#   pr     --session S --repo owner/repo --number N
#          --role home|node|follow-up|coordination|item
#          --state open|ready|merged|closed
#          record root: `trail/pr/<owner>.<repo>.<n>`,
#          {repo, number, role, state, recorded_at}.
#   index  --repo owner/repo --number N --session S
#          --mode single-pr|coordinated|multi-pr --topic T
#          the PR's index session at the shared address: `run/<run_id>`,
#          {workspace, session, session_id, mode, topic, written_at}, taken
#          from the root's `trail/self` (written first when it is absent).
#          The index session is opened from koto-templates/skill-session.md
#          with --attach-live and never ticked.
#
# Run every verb from the record root's checkout: the root's keys are written
# in the current directory's workspace. Every value is held to a closed
# pattern before it reaches a koto command line, and every JSON value is built
# with jq. The owner is held to GitHub's owner grammar, the repository to
# ^[A-Za-z0-9._-]+$ without `.` or `..`, and both are lowercased in names and
# values. Timestamps are the writer's clock: they order entries and prove
# nothing.
#
# Exit codes:
#   0   written
#   64  usage: an unknown verb or flag, a flag given twice or without a value
#   65  a value the verb refuses (outside its pattern, or a session with no
#       run_id or session id to record); nothing written
#   70  a koto read or write failed
#
# Requires: bash 3.2+, jq, koto.
set -uo pipefail

PROG=run-trail
SELF_DIR=$(CDPATH='' cd "$(dirname "${BASH_SOURCE[0]}")" && pwd) || exit 64
PLUGIN_DIR=$(CDPATH='' cd "$SELF_DIR/.." && pwd) || exit 64
# shellcheck source=lib/record-store.sh
. "$SELF_DIR/lib/record-store.sh" || exit 64
TEMPLATE="$PLUGIN_DIR/koto-templates/skill-session.md"

RE_SESSION='^[A-Za-z0-9][A-Za-z0-9._-]{0,199}$'
RE_RUN_ID='^[0-9a-f]{32}$'
RE_SESSION_ID='^[A-Za-z0-9-]{1,64}$'
RE_TOPIC='^[a-z0-9-]{1,100}$'

usage() {
    echo "$PROG: $*" >&2
    echo "usage: run-trail.sh self --session S" >&2
    echo "       run-trail.sh pr --session S --repo owner/repo --number N --role home|node|follow-up|coordination|item --state open|ready|merged|closed" >&2
    echo "       run-trail.sh index --repo owner/repo --number N --session S --mode single-pr|coordinated|multi-pr --topic T" >&2
    exit 64
}
refuse() { echo "$PROG: $*" >&2; exit 65; }
failed() { echo "$PROG: $*" >&2; exit 70; }
now() { date -u +%Y-%m-%dT%H:%M:%SZ; }

[ $# -ge 1 ] || usage "no verb"
VERB=$1
shift
case "$VERB" in
    self) ALLOWED=" --session " ;;
    pr) ALLOWED=" --session --repo --number --role --state " ;;
    index) ALLOWED=" --session --repo --number --mode --topic " ;;
    *) usage "unknown verb [$VERB]" ;;
esac

SESSION=""; REPO=""; NUMBER=""; ROLE=""; STATE=""; MODE=""; TOPIC=""
SEEN=" "
while [ $# -gt 0 ]; do
    case "$ALLOWED" in *" $1 "*) ;; *) usage "$VERB takes no argument [$1]" ;; esac
    [ $# -ge 2 ] || usage "$1 needs a value"
    case "$SEEN" in *" $1 "*) usage "$1 given more than once" ;; esac
    SEEN="$SEEN$1 "
    case "$1" in
        --session) SESSION=$2 ;;
        --repo) REPO=$2 ;;
        --number) NUMBER=$2 ;;
        --role) ROLE=$2 ;;
        --state) STATE=$2 ;;
        --mode) MODE=$2 ;;
        --topic) TOPIC=$2 ;;
    esac
    shift 2
done
for flag in $ALLOWED; do
    case "$SEEN" in *" $flag "*) ;; *) usage "$VERB needs $flag" ;; esac
done

[[ $SESSION =~ $RE_SESSION ]] || refuse "--session [$SESSION] is not a koto session name"
if [ "$VERB" != self ]; then
    case "$REPO" in */*/*|/*|*/) refuse "--repo [$REPO] is not owner/repo" ;; */*) ;; *) refuse "--repo [$REPO] is not owner/repo" ;; esac
    rs_valid_owner "${REPO%%/*}" || refuse "--repo [$REPO]: the owner is not a GitHub owner name"
    rs_valid_repo "${REPO#*/}" || refuse "--repo [$REPO]: the repository name is not allowed"
    [[ $NUMBER =~ $RS_RE_NUMBER ]] || refuse "--number [$NUMBER] is not a PR number"
    REPO=$(rs_lower "$REPO")
fi

# write_self: the root's address as this checkout sees it, as `trail/self`.
# SELF_DOC holds what was written.
write_self() {
    local run_id rows sid ws
    run_id=$(koto context get "$SESSION" run_id </dev/null) \
        || refuse "$SESSION has no readable run_id; nothing written"
    [[ $run_id =~ $RE_RUN_ID ]] || refuse "$SESSION's run_id is not a run identity; nothing written"
    rows=$(koto session list </dev/null) || failed "koto session list failed"
    sid=$(jq -r --arg s "$SESSION" \
        'if type == "array" then ([.[] | select(.id == $s)][0].session_id // "") else "" end
         | if type == "string" then . else "" end' <<<"$rows") \
        || failed "koto session list printed something that is not JSON"
    [[ $sid =~ $RE_SESSION_ID ]] || refuse "koto lists no session id for $SESSION; nothing written"
    ws=$(pwd -P) || failed "could not read the working directory"
    rs_valid_workspace "$ws" || refuse "the working directory is not a recordable workspace"
    SELF_DOC=$(jq -nc --arg w "$ws" --arg s "$SESSION" --arg i "$sid" --arg r "$run_id" \
        '{workspace: $w, session: $s, session_id: $i, run_id: $r}') || failed "jq failed"
    printf '%s' "$SELF_DOC" | koto context add "$SESSION" trail/self \
        || failed "could not write trail/self in $SESSION"
}

# read_self: the root's `trail/self`, written first when it is absent, with
# every field checked again. Sets SELF_WS, SELF_SID and SELF_RUN.
read_self() {
    local rc fields
    koto context exists "$SESSION" trail/self </dev/null
    rc=$?
    case "$rc" in
        0) SELF_DOC=$(koto context get "$SESSION" trail/self </dev/null) \
               || failed "could not read trail/self in $SESSION" ;;
        1) write_self ;;
        *) failed "could not check trail/self in $SESSION (koto exit $rc)" ;;
    esac
    # One field per line: a field holding a control character (a newline
    # included) is emptied first, so the lines can't shift.
    fields=$(jq -r 'if type == "object" then
            [.workspace, .session, .session_id, .run_id]
            | map(if type == "string" and (test("[[:cntrl:]]") | not) then . else "" end)
        else ["", "", "", ""] end | .[]' <<<"$SELF_DOC") || refuse "$SESSION's trail/self is not JSON"
    local s=""
    SELF_WS=""; SELF_SID=""; SELF_RUN=""
    { IFS= read -r SELF_WS; IFS= read -r s; IFS= read -r SELF_SID; IFS= read -r SELF_RUN; } <<<"$fields"
    rs_valid_workspace "$SELF_WS" || refuse "$SESSION's trail/self names no valid workspace"
    [ "$s" = "$SESSION" ] || refuse "$SESSION's trail/self names another session"
    [[ $SELF_SID =~ $RE_SESSION_ID ]] || refuse "$SESSION's trail/self names no valid session id"
    [[ $SELF_RUN =~ $RE_RUN_ID ]] || refuse "$SESSION's trail/self names no valid run id"
}

case "$VERB" in
    self)
        write_self
        ;;
    pr)
        case "$ROLE" in home|node|follow-up|coordination|item) ;; *) refuse "--role [$ROLE] is not a PR role" ;; esac
        case "$STATE" in open|ready|merged|closed) ;; *) refuse "--state [$STATE] is not a PR state" ;; esac
        KEY="trail/pr/${REPO%%/*}.${REPO#*/}.$NUMBER"
        DOC=$(jq -nc --arg repo "$REPO" --argjson n "$NUMBER" --arg role "$ROLE" --arg state "$STATE" --arg at "$(now)" \
            '{repo: $repo, number: $n, role: $role, state: $state, recorded_at: $at}') || failed "jq failed"
        printf '%s' "$DOC" | koto context add "$SESSION" "$KEY" \
            || failed "could not write $KEY in $SESSION"
        ;;
    index)
        case "$MODE" in single-pr|coordinated|multi-pr) ;; *) refuse "--mode [$MODE] is not a plan mode" ;; esac
        [[ $TOPIC =~ $RE_TOPIC ]] || refuse "--topic [$TOPIC] must match ^[a-z0-9-]+\$"
        read_self
        NAME=$(rs_index_name "$REPO" "$NUMBER") || refuse "no index name for $REPO#$NUMBER"
        DIR=$(rs_shared_dir "${REPO%%/*}") || refuse "no shared address for $REPO"
        ENTRY=$(jq -nc --arg w "$SELF_WS" --arg s "$SESSION" --arg i "$SELF_SID" --arg m "$MODE" \
            --arg t "$TOPIC" --arg at "$(now)" \
            '{workspace: $w, session: $s, session_id: $i, mode: $m, topic: $t, written_at: $at}') \
            || failed "jq failed"
        rs_koto_write "$DIR" init "$NAME" --template "$TEMPLATE" --attach-live </dev/null >/dev/null \
            || failed "could not open the index session $NAME"
        printf '%s' "$ENTRY" | rs_koto_write "$DIR" context add "$NAME" "run/$SELF_RUN" \
            || failed "could not write run/$SELF_RUN in $NAME"
        ;;
esac
exit 0
