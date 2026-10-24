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
#   plan   --session S --step ID --plan docs/plans/PLAN-<topic>.md
#          record root: `trail/plan/<step>.md`, the PLAN's text as committed
#          at HEAD (`git show HEAD:<plan>`), and `trail/plan/<step>.json`,
#          {sha, entry, recorded_at}: HEAD's commit, the step's heading line
#          in that text (`### Step <N>:` for a `step-<N>` id; null when the
#          id names no such heading) and the time. The path must match
#          ^docs/plans/PLAN-[a-z0-9-]+\.md$ and nothing else is read.
#   step   --session S --step ID --child NAME [--supersede]
#          record root: `trail/step/<step>`, {session, workspace, superseded}:
#          the step session's name, this checkout, and the names a new step
#          agent's session replaced. A record naming another session is
#          refused unless --supersede is given, which moves that name to
#          `superseded`; naming the same session again changes nothing.
#   departure --session S --step ID
#          --kind deviated|deferral|scope-change|entry-rewritten
#          stdin: {"what": ..., "why": ...}
#          the session where it happened: `trail/departure/<n>.json`,
#          {step, kind, what, why, at}, n one past the highest there.
#   decision --session S --step ID --actor agent:NAME|person|person:LOGIN
#          stdin: {"choice": ..., "rationale": ...,
#                  "alternatives_considered": [...]}  (the last optional)
#          the session where it happened: `trail/decision/<n>.json`,
#          {step, actor, choice, rationale, alternatives_considered, at}, and
#          the same choice, rationale and alternatives through
#          `koto decisions record`, which keeps no actor of its own. NAME is a
#          session name (the agent's own run), LOGIN a GitHub login. The
#          trail key is written first; a koto copy that then fails is 70, and
#          a retry records the decision again under the next n.
#   snapshot --session S
#          reads only: every `trail/` key of S but `trail/self`, as one JSON
#          object {key: value} on stdout, each value its exact bytes. A key
#          outside the layout above is left out, named on stderr.
#   carry  --session S
#          stdin: a snapshot. Writes each key S doesn't hold yet and prints
#          `carried=<n>`. /execute's opener carries a finished session's
#          trail into its replacement this way.
#
# Free text never arrives as an argument or a path: departure and decision
# take it only as one JSON document on stdin (64 KiB at most), each text field
# a non-empty string of 16 KiB at most, and plan reads only the one PLAN path.
# The PLAN is capped at 256 KiB. A text holding a private-key header, an
# `Authorization:` line or a common token shape (gh[pousr]_, github_pat_,
# AKIA, xox?-) is refused before anything is written, the copy decision sends
# through `koto decisions record` included.
#
# Run every verb from the session's checkout: its keys are written in the
# current directory's workspace. Every value is held to a closed pattern
# (scripts/lib/record-store.sh) before it reaches a koto command line, and
# every JSON value is built with jq. The owner and repository are lowercased
# in names and values. Timestamps are the writer's clock: they order entries
# and prove nothing.
#
# Exit codes:
#   0   written (snapshot: printed)
#   64  usage: an unknown verb or flag, a flag given twice or without a value,
#       an argument where none is taken
#   65  a value the verb refuses (outside its pattern, a stdin document that
#       is not one JSON object with the verb's fields, a credential shape, an
#       oversized text, a PLAN path outside docs/plans or not at HEAD, a step
#       record naming another session without --supersede, or a session
#       with no run_id or session id to record); nothing written
#   70  a koto, git or jq call failed
#
# Requires: bash 3.2+, git, jq, koto.
set -uo pipefail

PROG=run-trail
SELF_DIR=$(CDPATH='' cd "$(dirname "${BASH_SOURCE[0]}")" && pwd) || exit 64
PLUGIN_DIR=$(CDPATH='' cd "$SELF_DIR/.." && pwd) || exit 64
# shellcheck source=lib/record-store.sh
. "$SELF_DIR/lib/record-store.sh" || exit 64
TEMPLATE="$PLUGIN_DIR/koto-templates/skill-session.md"

RT_RE_PLAN='^docs/plans/PLAN-[a-z0-9-]+\.md$'
RT_TEXT_MAX=16384
RT_DOC_MAX=65536
RT_PLAN_MAX=262144
RT_CARRY_MAX=16777216
RT_SNAPSHOT_MAX_KEYS=2000
# The credential shapes, one Oniguruma regex for jq's test().
RT_SECRET_RE='-----BEGIN ([A-Z0-9]+ )*PRIVATE KEY-----|(^|\n)[ \t]*[Aa][Uu][Tt][Hh][Oo][Rr][Ii][Zz][Aa][Tt][Ii][Oo][Nn][ \t]*:[ \t]*[^ \t\r\n]|gh[pousr]_[A-Za-z0-9]{36}|github_pat_[A-Za-z0-9_]{22,}|AKIA[0-9A-Z]{16}|xox[abprs]-[A-Za-z0-9-]{10,}'

usage() {
    echo "$PROG: $*" >&2
    echo "usage: run-trail.sh self --session S" >&2
    echo "       run-trail.sh pr --session S --repo owner/repo --number N --role home|node|follow-up|coordination|item --state open|ready|merged|closed" >&2
    echo "       run-trail.sh index --repo owner/repo --number N --session S --mode single-pr|coordinated|multi-pr --topic T" >&2
    echo "       run-trail.sh plan --session S --step ID --plan docs/plans/PLAN-<topic>.md" >&2
    echo "       run-trail.sh step --session S --step ID --child NAME [--supersede]" >&2
    echo "       run-trail.sh departure --session S --step ID --kind deviated|deferral|scope-change|entry-rewritten < {\"what\": ..., \"why\": ...}" >&2
    echo "       run-trail.sh decision --session S --step ID --actor agent:NAME|person[:LOGIN] < {\"choice\": ..., \"rationale\": ...}" >&2
    echo "       run-trail.sh snapshot --session S" >&2
    echo "       run-trail.sh carry --session S < <snapshot>" >&2
    exit 64
}
refuse() { echo "$PROG: $*" >&2; exit 65; }
failed() { echo "$PROG: $*" >&2; exit 70; }
now() { date -u +%Y-%m-%dT%H:%M:%SZ; }

[ $# -ge 1 ] || usage "no verb"
VERB=$1
shift
# ALLOWED: the flags the verb needs, each with a value. SWITCHES: the flags it
# may take without one.
SWITCHES=" "
case "$VERB" in
    self|snapshot|carry) ALLOWED=" --session " ;;
    pr) ALLOWED=" --session --repo --number --role --state " ;;
    index) ALLOWED=" --session --repo --number --mode --topic " ;;
    plan) ALLOWED=" --session --step --plan " ;;
    step) ALLOWED=" --session --step --child "; SWITCHES=" --supersede " ;;
    departure) ALLOWED=" --session --step --kind " ;;
    decision) ALLOWED=" --session --step --actor " ;;
    *) usage "unknown verb [$VERB]" ;;
esac

SESSION=""; REPO=""; NUMBER=""; ROLE=""; STATE=""; MODE=""; TOPIC=""
STEP=""; PLAN=""; CHILD=""; KIND=""; ACTOR=""; SUPERSEDE=0
SEEN=" "
while [ $# -gt 0 ]; do
    case "$SEEN" in *" $1 "*) usage "$1 given more than once" ;; esac
    case "$SWITCHES" in
        *" $1 "*)
            SEEN="$SEEN$1 "
            SUPERSEDE=1
            shift
            continue
            ;;
    esac
    case "$ALLOWED" in *" $1 "*) ;; *) usage "$VERB takes no argument [$1]" ;; esac
    [ $# -ge 2 ] || usage "$1 needs a value"
    SEEN="$SEEN$1 "
    case "$1" in
        --session) SESSION=$2 ;;
        --repo) REPO=$2 ;;
        --number) NUMBER=$2 ;;
        --role) ROLE=$2 ;;
        --state) STATE=$2 ;;
        --mode) MODE=$2 ;;
        --topic) TOPIC=$2 ;;
        --step) STEP=$2 ;;
        --plan) PLAN=$2 ;;
        --child) CHILD=$2 ;;
        --kind) KIND=$2 ;;
        --actor) ACTOR=$2 ;;
    esac
    shift 2
done
for flag in $ALLOWED; do
    case "$SEEN" in *" $flag "*) ;; *) usage "$VERB needs $flag" ;; esac
done

rs_valid_session "$SESSION" || refuse "--session [$SESSION] is not a koto session name"
case "$VERB" in
    pr|index)
        case "$REPO" in */*/*|/*|*/) refuse "--repo [$REPO] is not owner/repo" ;; */*) ;; *) refuse "--repo [$REPO] is not owner/repo" ;; esac
        rs_valid_owner "${REPO%%/*}" || refuse "--repo [$REPO]: the owner is not a GitHub owner name"
        rs_valid_repo "${REPO#*/}" || refuse "--repo [$REPO]: the repository name is not allowed"
        [[ $NUMBER =~ $RS_RE_NUMBER ]] || refuse "--number [$NUMBER] is not a PR number"
        REPO=$(rs_lower "$REPO")
        ;;
    plan|step|departure|decision)
        rs_valid_step "$STEP" || refuse "--step [$STEP] is not a step id"
        ;;
esac

TMP=""
trap '[ -n "$TMP" ] && rm -rf -- "$TMP"' EXIT
tmpdir() {
    [ -n "$TMP" ] && return 0
    TMP=$(mktemp -d "${TMPDIR:-/tmp}/run-trail.XXXXXX") || { TMP=""; failed "mktemp failed"; }
}

# has_secret <file>: 0 when the file's text holds a credential shape.
has_secret() {
    local hit
    hit=$(jq -Rs --arg re "$RT_SECRET_RE" 'test($re)' < "$1") || failed "jq could not read the text"
    [ "$hit" = true ]
}

# read_doc <jq filter>: the one JSON document on stdin, normalized by the
# filter (which raises an error naming what is wrong) into DOC. The document
# is held to RT_DOC_MAX bytes, and every string in it is checked for a
# credential shape.
read_doc() {
    local size out
    tmpdir
    head -c "$((RT_DOC_MAX + 1))" > "$TMP/doc.json" || failed "could not read stdin"
    size=$(wc -c < "$TMP/doc.json" | tr -d ' ')
    [ "$size" -gt 0 ] || refuse "$VERB takes its text as one JSON document on stdin; nothing was given"
    [ "$size" -le "$RT_DOC_MAX" ] || refuse "the stdin document is over $RT_DOC_MAX bytes"
    jq -e 'type == "object"' "$TMP/doc.json" >/dev/null \
        || refuse "stdin is not one JSON object"
    if jq -e --arg re "$RT_SECRET_RE" '[.. | strings | test($re)] | any' "$TMP/doc.json" >/dev/null; then
        refuse "the document holds a credential shape (a private key, an Authorization: line or a token); nothing written"
    fi
    out=$(jq -c --argjson cap "$RT_TEXT_MAX" "
        def text(\$k): if (.[\$k] | type) == \"string\" and (.[\$k] | length) > 0 then
                (if (.[\$k] | utf8bytelength) <= \$cap then .[\$k] else error(\"\(\$k) is over \(\$cap) bytes\") end)
            else error(\"needs a non-empty string \(\$k)\") end;
        $1" "$TMP/doc.json" 2>&1) || refuse "the stdin document: $(sed -n '1s/^jq: error[^:]*: //p' <<<"$out")"
    DOC=$out
}

# next_n <prefix>: one past the highest <n> of the session's <prefix><n>.json.
next_n() {
    local list n
    list=$(koto context list "$SESSION" --prefix "$1" </dev/null) || failed "could not list $1 in $SESSION"
    n=$(jq -r --arg p "$1" '[(if type == "array" then .[] else empty end) | strings | ltrimstr($p)
            | select(test("^[1-9][0-9]{0,5}\\.json$")) | rtrimstr(".json") | tonumber]
        | (max // 0) + 1' <<<"$list") || failed "koto context list printed something that is not a key list"
    printf '%s\n' "$n"
}

# trail_key_ok <key>: 0 when the key is in the trail layout above, trail/self
# included.
trail_key_ok() {
    local k=${1#trail/} rest
    [ "$k" != "$1" ] || return 1
    case "$k" in
        self) return 0 ;;
        pr/*)
            rest=${k#pr/}
            [[ $rest =~ ^[a-z0-9-]+\.[a-z0-9._-]+\.[1-9][0-9]{0,9}$ ]]
            return
            ;;
        plan/*.md) rest=${k#plan/}; rs_valid_step "${rest%.md}"; return ;;
        plan/*.json) rest=${k#plan/}; rs_valid_step "${rest%.json}"; return ;;
        step/*) rs_valid_step "${k#step/}"; return ;;
        departure/*|decision/*)
            rest=${k#*/}
            [[ $rest =~ ^[1-9][0-9]{0,5}\.json$ ]]
            return
            ;;
    esac
    return 1
}

# write_self: the root's address as this checkout sees it, as `trail/self`.
# SELF_DOC holds what was written.
write_self() {
    local run_id rows sid ws
    run_id=$(koto context get "$SESSION" run_id </dev/null) \
        || refuse "$SESSION has no readable run_id; nothing written"
    [[ $run_id =~ $RS_RE_RUN_ID ]] || refuse "$SESSION's run_id is not a run identity; nothing written"
    rows=$(koto session list </dev/null) || failed "koto session list failed"
    sid=$(jq -r --arg s "$SESSION" \
        'if type == "array" then ([.[] | select(.id == $s)][0].session_id // "") else "" end
         | if type == "string" then . else "" end' <<<"$rows") \
        || failed "koto session list printed something that is not JSON"
    [[ $sid =~ $RS_RE_SESSION_ID ]] || refuse "koto lists no session id for $SESSION; nothing written"
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
    [[ $SELF_SID =~ $RS_RE_SESSION_ID ]] || refuse "$SESSION's trail/self names no valid session id"
    [[ $SELF_RUN =~ $RS_RE_RUN_ID ]] || refuse "$SESSION's trail/self names no valid run id"
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
        [[ $TOPIC =~ $RS_RE_TOPIC ]] || refuse "--topic [$TOPIC] must match ^[a-z0-9-]+\$"
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
    plan)
        [[ $PLAN =~ $RT_RE_PLAN ]] || refuse "--plan [$PLAN] is not docs/plans/PLAN-<topic>.md; nothing written"
        tmpdir
        git show "HEAD:$PLAN" > "$TMP/plan.md" </dev/null || refuse "no $PLAN at HEAD; nothing written"
        SHA=$(git rev-parse --verify HEAD </dev/null) || failed "could not read HEAD"
        [[ $SHA =~ $RS_RE_SHA ]] || failed "HEAD [$SHA] is not a commit id"
        SIZE=$(wc -c < "$TMP/plan.md" | tr -d ' ')
        [ "$SIZE" -le "$RT_PLAN_MAX" ] || refuse "$PLAN is over $RT_PLAN_MAX bytes; nothing written"
        has_secret "$TMP/plan.md" && refuse "$PLAN holds a credential shape (a private key, an Authorization: line or a token); nothing written"
        HEADING=""
        case "$STEP" in
            step-[1-9]*)
                N=${STEP#step-}
                if [[ $N =~ ^[1-9][0-9]{0,2}$ ]]; then
                    HEADING=$(grep -m1 -E "^### Step $N:" "$TMP/plan.md" | head -c 1024 | tr -d '[:cntrl:]')
                fi
                ;;
        esac
        DOC=$(jq -nc --arg sha "$SHA" --arg entry "$HEADING" --arg at "$(now)" \
            '{sha: $sha, entry: (if $entry == "" then null else $entry end), recorded_at: $at}') || failed "jq failed"
        koto context add "$SESSION" "trail/plan/$STEP.md" --from-file "$TMP/plan.md" </dev/null \
            || failed "could not write trail/plan/$STEP.md in $SESSION"
        printf '%s' "$DOC" | koto context add "$SESSION" "trail/plan/$STEP.json" \
            || failed "could not write trail/plan/$STEP.json in $SESSION"
        ;;
    step)
        rs_valid_session "$CHILD" || refuse "--child [$CHILD] is not a koto session name"
        WS=$(pwd -P) || failed "could not read the working directory"
        rs_valid_workspace "$WS" || refuse "the working directory is not a recordable workspace"
        KEY="trail/step/$STEP"
        SUPERSEDED='[]'
        koto context exists "$SESSION" "$KEY" </dev/null
        RC=$?
        case "$RC" in
            0)
                CUR=$(koto context get "$SESSION" "$KEY" </dev/null) || failed "could not read $KEY in $SESSION"
                FIELDS=$(jq -r 'if type == "object" and (.session | type) == "string"
                        and ((.superseded // []) | type) == "array" and ((.superseded // []) | all(type == "string"))
                    then ([.session] + (.superseded // [])) | map(select(test("[[:cntrl:]]") | not)) | .[]
                    else empty end' <<<"$CUR") || FIELDS=""
                CUR_SESSION=$(sed -n 1p <<<"$FIELDS")
                rs_valid_session "$CUR_SESSION" || refuse "$KEY in $SESSION is not a step record; nothing written"
                while IFS= read -r n; do
                    [ -n "$n" ] || continue
                    rs_valid_session "$n" || refuse "$KEY in $SESSION names a superseded session outside the pattern"
                done <<<"$(printf '%s\n' "$FIELDS" | tail -n +2)"
                SUPERSEDED=$(jq -c '(.superseded // [])' <<<"$CUR") || failed "jq failed"
                if [ "$CUR_SESSION" != "$CHILD" ]; then
                    [ "$SUPERSEDE" -eq 1 ] \
                        || refuse "$KEY already names $CUR_SESSION; a new step agent's session is recorded with --supersede"
                    SUPERSEDED=$(jq -c --arg s "$CUR_SESSION" '(. + [$s]) | unique' <<<"$SUPERSEDED") || failed "jq failed"
                fi
                ;;
            1) ;;
            *) failed "could not check $KEY in $SESSION (koto exit $RC)" ;;
        esac
        DOC=$(jq -nc --arg s "$CHILD" --arg w "$WS" --argjson sup "$SUPERSEDED" \
            '{session: $s, workspace: $w, superseded: ($sup - [$s])}') || failed "jq failed"
        printf '%s' "$DOC" | koto context add "$SESSION" "$KEY" \
            || failed "could not write $KEY in $SESSION"
        ;;
    departure)
        case "$KIND" in deviated|deferral|scope-change|entry-rewritten) ;; *) refuse "--kind [$KIND] is not a departure kind" ;; esac
        read_doc '{what: text("what"), why: text("why")}'
        N=$(next_n trail/departure/) || exit $?
        DOC=$(jq -c --arg step "$STEP" --arg kind "$KIND" --arg at "$(now)" \
            '{step: $step, kind: $kind, what, why, at: $at}' <<<"$DOC") || failed "jq failed"
        printf '%s' "$DOC" | koto context add "$SESSION" "trail/departure/$N.json" \
            || failed "could not write trail/departure/$N.json in $SESSION"
        ;;
    decision)
        case "$ACTOR" in
            person) ;;
            person:*) rs_valid_owner "${ACTOR#person:}" || refuse "--actor [$ACTOR]: the login is not a GitHub login" ;;
            agent:*) rs_valid_session "${ACTOR#agent:}" || refuse "--actor [$ACTOR]: the agent is not a session name" ;;
            *) refuse "--actor [$ACTOR] is not agent:<name>, person or person:<login>" ;;
        esac
        read_doc '{choice: text("choice"), rationale: text("rationale")}
            + (if has("alternatives_considered") then
                  (.alternatives_considered | if type == "array" and length <= 20
                      and all(type == "string" and length > 0 and utf8bytelength <= $cap)
                   then {alternatives_considered: .}
                   else error("alternatives_considered must be at most 20 non-empty strings of \($cap) bytes at most") end)
               else {} end)'
        N=$(next_n trail/decision/) || exit $?
        # The trail key first: it is the record that names the actor, which
        # koto's copy can't. A failure of the koto copy after it is 70, and
        # running the call again records the decision a second time.
        KOTO_DOC=$DOC
        DOC=$(jq -c --arg step "$STEP" --arg actor "$ACTOR" --arg at "$(now)" \
            '{step: $step, actor: $actor} + . + {at: $at}' <<<"$DOC") || failed "jq failed"
        printf '%s' "$DOC" | koto context add "$SESSION" "trail/decision/$N.json" \
            || failed "could not write trail/decision/$N.json in $SESSION"
        koto decisions record "$SESSION" --with-data "$KOTO_DOC" </dev/null >&2 \
            || failed "koto decisions record failed in $SESSION, after trail/decision/$N.json was written"
        ;;
    snapshot)
        tmpdir
        LIST=$(koto context list "$SESSION" --prefix trail/ </dev/null) || failed "could not list trail/ in $SESSION"
        KEYS=$(jq -r --argjson max "$RT_SNAPSHOT_MAX_KEYS" 'if type == "array" then .[:$max][] | strings
            | select(test("[[:cntrl:]]") | not) else error("not a key list") end' <<<"$LIST") \
            || failed "koto context list printed something that is not a key list"
        printf '{}' > "$TMP/snap.json"
        while IFS= read -r K; do
            [ -n "$K" ] || continue
            [ "$K" = trail/self ] && continue
            if ! trail_key_ok "$K"; then
                echo "$PROG: leaving out [$K] in $SESSION: it is outside the trail layout" >&2
                continue
            fi
            koto context get "$SESSION" "$K" --to-file "$TMP/value" </dev/null \
                || failed "could not read $K in $SESSION"
            jq -c --arg k "$K" --rawfile v "$TMP/value" '. + {($k): $v}' "$TMP/snap.json" > "$TMP/next.json" \
                && mv -- "$TMP/next.json" "$TMP/snap.json" || failed "jq failed"
        done <<<"$KEYS"
        cat -- "$TMP/snap.json"
        ;;
    carry)
        tmpdir
        head -c "$((RT_CARRY_MAX + 1))" > "$TMP/snap.json" || failed "could not read stdin"
        SIZE=$(wc -c < "$TMP/snap.json" | tr -d ' ')
        [ "$SIZE" -le "$RT_CARRY_MAX" ] || refuse "the snapshot is over $RT_CARRY_MAX bytes; nothing written"
        jq -e --argjson cap "$RT_PLAN_MAX" 'type == "object" and all(.[]; type == "string" and utf8bytelength <= $cap)' \
            "$TMP/snap.json" >/dev/null \
            || refuse "the snapshot is not one JSON object of text values; nothing written"
        KEYS=$(jq -r 'keys[] | select(test("[[:cntrl:]]") | not)' "$TMP/snap.json") || failed "jq failed"
        [ "$(jq 'length' "$TMP/snap.json")" -eq "$(printf '%s' "$KEYS" | grep -c '^')" ] \
            || refuse "the snapshot names a key holding a control character; nothing written"
        while IFS= read -r K; do
            [ -n "$K" ] || continue
            [ "$K" != trail/self ] && trail_key_ok "$K" \
                || refuse "the snapshot names [$K], outside the trail layout; nothing written"
        done <<<"$KEYS"
        CARRIED=0
        while IFS= read -r K; do
            [ -n "$K" ] || continue
            koto context exists "$SESSION" "$K" </dev/null
            RC=$?
            case "$RC" in
                0) continue ;;
                1) ;;
                *) failed "could not check $K in $SESSION (koto exit $RC); carried $CARRIED" ;;
            esac
            jq -j --arg k "$K" '.[$k]' "$TMP/snap.json" > "$TMP/value" || failed "jq failed"
            koto context add "$SESSION" "$K" --from-file "$TMP/value" </dev/null \
                || failed "could not write $K in $SESSION; carried $CARRIED"
            CARRIED=$((CARRIED + 1))
        done <<<"$KEYS"
        printf 'carried=%s\n' "$CARRIED"
        ;;
esac
exit 0
