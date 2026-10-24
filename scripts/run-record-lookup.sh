#!/usr/bin/env bash
# run-record-lookup.sh -- from a PR's repository and number to the koto
# session that ran its plan, and from there to every PR the run recorded.
#
# Usage: run-record-lookup.sh <owner/repo> <n> [--steps]
#
# It reads the PR's index session, `pr.<owner>.<repo>.<n>`, at the shared
# address scripts/lib/record-store.sh defines (both canonical forms of it),
# takes the entries latest first (by `written_at`, ties broken by `run_id`;
# the field is the writer's clock, so it orders entries and proves nothing),
# and reads the record root each one names at its recorded workspace. A root
# is returned only when its own `trail/pr/*` list holds this PR, so an index
# entry naming an unrelated session never leads anywhere. The first root that
# confirms the PR is the answer.
#
# The two forms of the shared address. A form koto answers "not found" for
# (record-store.sh's 68: with the workspace option, the form no writer on
# this host used) or that isn't a directory here (69) holds nothing, and the
# read goes on to the next form. A form whose read fails any other way is
# unreadable: the entries the other form holds are still used, and the
# unreadable form is named in `missing`. When no form gave an entry and one
# was unreadable, the answer is exit 2, not 3, since that form may hold it.
#
# With --steps, `steps` lists what the root recorded per step
# (scripts/run-trail.sh's `step` and `plan` verbs), in step order:
#   {step, session, workspace, superseded: [names],
#    plan: {sha, entry, recorded_at, text_key} | null}
# `session` is the step session, where that step's departures
# (`trail/departure/*`) and decisions (`trail/decision/*`) are kept, and
# `text_key` is the root's key holding the PLAN's text as the step began; read
# either with `koto context get`. A step with a plan snapshot and no step
# record has `session`, `workspace` and `superseded` null. Without --steps,
# `steps` is [] and the step records are not read.
#
# Every read goes through record-store.sh's rs_koto_read, which passes koto's
# read-only --workspace option when the installed koto has it and otherwise
# runs koto from the addressed directory, which reaches the record on the
# host that wrote it. The lookup writes nothing, imports nothing and reads
# nothing from GitHub. Every value it reads back is checked against the same
# closed patterns the writer used; one that fails is named in `missing` and
# never used. Reads are bounded: at most 20 index entries per form of the
# shared address, 200 PR keys and 200 step keys per root.
#
# Output, on exit 0, one JSON object built with jq:
#   {record_root: {workspace, session}, run_id, complete, unique,
#    missing: [...], prs: [{repo, number, state}], others: [run_id],
#    steps: [...]}
# `complete` is true when nothing was missing; `unique` is true when the
# index holds one entry for the PR. The workspace names a user and an
# instance: it's internal, not for pasting into PRs or issues.
#
# Exit codes:
#   0   found; the JSON is on stdout
#   2   a store read failed, or a record root's workspace can't be reached
#       from here
#   3   no index entry for the PR, or no entry's record root lists it
#   64  malformed input
# Every exit but 0 says on stderr which case it hit.
#
# Requires: bash 3.2+, jq, koto.
set -uo pipefail

PROG=run-record-lookup
SELF_DIR=$(CDPATH='' cd "$(dirname "${BASH_SOURCE[0]}")" && pwd) || exit 64
# shellcheck source=lib/record-store.sh
. "$SELF_DIR/lib/record-store.sh" || exit 64

MAX_ENTRIES=20
MAX_PRS=200
MAX_STEPS=200

usage() {
    echo "$PROG: $*" >&2
    echo "usage: run-record-lookup.sh <owner/repo> <n> [--steps]" >&2
    exit 64
}

STEPS=0
ARGS=()
for a in "$@"; do
    case "$a" in
        --steps)
            [ "$STEPS" -eq 0 ] || usage "--steps given more than once"
            STEPS=1
            ;;
        --*) usage "unknown flag [$a]" ;;
        *) ARGS+=("$a") ;;
    esac
done
[ "${#ARGS[@]}" -eq 2 ] || usage "expected <owner/repo> and a PR number"
REPO=${ARGS[0]}
N=${ARGS[1]}
case "$REPO" in
    */*/*) usage "[$REPO] is not owner/repo: more than one /" ;;
    */) usage "[$REPO] names an owner without a repository" ;;
    /*) usage "[$REPO] names a repository without an owner" ;;
    */*) ;;
    *) usage "[$REPO] names an owner without a repository" ;;
esac
OWNER=${REPO%%/*}
NAME_PART=${REPO#*/}
rs_valid_owner "$OWNER" || usage "[$OWNER] is not a GitHub owner name"
rs_valid_repo "$NAME_PART" || usage "[$NAME_PART] is not an allowed repository name"
[[ $N =~ $RS_RE_NUMBER ]] || usage "PR number [$N] is not a positive integer"
REPO=$(rs_lower "$REPO")
INDEX=$(rs_index_name "$REPO" "$N") || usage "no index name for $REPO#$N"

WORK=$(mktemp -d "${TMPDIR:-/tmp}/run-record-lookup.XXXXXX") || { echo "$PROG: mktemp failed" >&2; exit 2; }
trap 'rm -rf "$WORK"' EXIT
: > "$WORK/missing"
: > "$WORK/entries"
: > "$WORK/steps"

missing() { printf '%s\n' "$1" >> "$WORK/missing"; }

# json_keys <json>: the array's string elements, one per line, at most $2.
json_keys() {
    jq -r --argjson max "$2" 'if type == "array" then .[:$max][] | select(type == "string")
        | select(test("[[:cntrl:]]") | not) else empty end' <<<"$1"
}

# --- the index -----------------------------------------------------------------

# Both forms of the shared address. With the workspace option each form is
# its own workspace id; without it a form is read from its directory, and two
# forms that are one directory here (/tmp on macOS) are read once.
FORMS=$(rs_shared_forms "$OWNER") || usage "no shared address for $OWNER"
SEEN_DIRS=" "
UNREADABLE_FORM=0
while IFS= read -r FORM; do
    [ -n "$FORM" ] || continue
    if ! rs_has_workspace_option; then
        [ -d "$FORM" ] || continue
        CANON=$(cd -- "$FORM" && pwd -P) || continue
        case "$SEEN_DIRS" in *" $CANON "*) continue ;; esac
        SEEN_DIRS="$SEEN_DIRS$CANON "
    fi
    LIST=$(rs_koto_read "$FORM" context list "$INDEX" --prefix run/ </dev/null)
    RC=$?
    case "$RC" in
        0) ;;
        68|69) continue ;;
        *)
            echo "$PROG: could not read the index session $INDEX at $FORM (koto exit $RC)" >&2
            UNREADABLE_FORM=1
            missing "index: a form of the shared address could not be read"
            continue
            ;;
    esac
    KEYS=$(json_keys "$LIST" "$MAX_ENTRIES") || { echo "$PROG: the index session $INDEX listed something that is not JSON" >&2; exit 2; }
    while IFS= read -r KEY; do
        [ -n "$KEY" ] || continue
        RID=${KEY#run/}
        if ! [[ $RID =~ $RS_RE_RUN_ID ]]; then
            missing "index: a key that is not run/<run_id>"
            continue
        fi
        VAL=$(rs_koto_read "$FORM" context get "$INDEX" "$KEY" </dev/null)
        RC=$?
        if [ "$RC" -ne 0 ]; then
            echo "$PROG: could not read $KEY in $INDEX (koto exit $RC)" >&2
            exit 2
        fi
        FIELDS=$(jq -r 'if type == "object" then
                [.written_at, .workspace, .session, .session_id, .mode, .topic]
                | map(if type == "string" and (test("[[:cntrl:]]") | not) then . else "" end)
            else ["", "", "", "", "", ""] end | .[]' <<<"$VAL") || FIELDS=""
        AT=""; WS=""; SESS=""; SID=""; MODE=""; TOPIC=""
        { IFS= read -r AT; IFS= read -r WS; IFS= read -r SESS; IFS= read -r SID; IFS= read -r MODE; IFS= read -r TOPIC; } <<<"$FIELDS"
        if [[ $AT =~ $RS_RE_AT ]] && rs_valid_workspace "$WS" && rs_valid_session "$SESS" \
            && [[ $SID =~ $RS_RE_SESSION_ID ]] && [[ $TOPIC =~ $RS_RE_TOPIC ]]; then
            case "$MODE" in
                single-pr|coordinated|multi-pr)
                    printf '%s\t%s\t%s\t%s\n' "$AT" "$RID" "$WS" "$SESS" >> "$WORK/entries"
                    continue
                    ;;
            esac
        fi
        missing "index: run/$RID fails its pattern"
    done <<<"$KEYS"
done <<<"$FORMS"

# One run's entry can sit at both forms; it counts once.
LC_ALL=C sort -t "$(printf '\t')" -k1,1r -k2,2r -u "$WORK/entries" > "$WORK/sorted" || exit 2
RUN_IDS=$(cut -f2 "$WORK/sorted" | LC_ALL=C sort -u)
ENTRY_COUNT=0
[ -n "$RUN_IDS" ] && ENTRY_COUNT=$(printf '%s\n' "$RUN_IDS" | wc -l | tr -d ' ')
if [ "$ENTRY_COUNT" -eq 0 ]; then
    if [ "$UNREADABLE_FORM" -eq 1 ]; then
        echo "$PROG: could not read the index for $REPO#$N under every form of the shared address" >&2
        exit 2
    fi
    echo "$PROG: no index entry for $REPO#$N" >&2
    exit 3
fi

# --- the record root ---------------------------------------------------------------

# read_root <workspace> <session>: the root's PRs as JSON lines in
# $WORK/prs; returns 0 when it lists this PR, 1 when it doesn't, 2 on a read
# failure, 69 when the workspace can't be reached from here.
read_root() {
    local ws=$1 sess=$2 list keys key val rc found=1 row
    : > "$WORK/prs"
    list=$(rs_koto_read "$ws" context list "$sess" --prefix trail/pr/ </dev/null)
    rc=$?
    [ "$rc" -eq 69 ] && return 69
    [ "$rc" -eq 0 ] || return 2
    keys=$(json_keys "$list" "$MAX_PRS") || return 2
    while IFS= read -r key; do
        [ -n "$key" ] || continue
        val=$(rs_koto_read "$ws" context get "$sess" "$key" </dev/null) || return 2
        row=$(jq -c 'select(type == "object")
            | select((.repo | type) == "string" and (.number | type) == "number" and (.state | type) == "string")
            | select(.state == "open" or .state == "ready" or .state == "merged" or .state == "closed")
            | select(.number >= 1 and .number == (.number | floor))
            | {repo, number, state}' <<<"$val" 2>&1) || row=""
        case "$row" in
            '{'*)
                local r
                r=$(jq -r '.repo' <<<"$row")
                if [[ $r == */* ]] && rs_valid_owner "${r%%/*}" && rs_valid_repo "${r#*/}"; then
                    printf '%s\n' "$row" >> "$WORK/prs"
                    if [ "$(rs_lower "$r")" = "$REPO" ] && [ "$(jq -r '.number' <<<"$row")" = "$N" ]; then
                        found=0
                    fi
                    continue
                fi
                ;;
        esac
        missing "root $sess: a trail/pr entry fails its pattern"
    done <<<"$keys"
    return "$found"
}

# read_steps <workspace> <session>: the root's step records and plan
# snapshots as JSON lines in $WORK/steps; returns 2 on a read failure.
read_steps() {
    local ws=$1 sess=$2 list keys key id val row
    : > "$WORK/step-ids"
    : > "$WORK/step-keys"
    list=$(rs_koto_read "$ws" context list "$sess" --prefix trail/step/ </dev/null) || return 2
    keys=$(json_keys "$list" "$MAX_STEPS") || return 2
    list=$(rs_koto_read "$ws" context list "$sess" --prefix trail/plan/ </dev/null) || return 2
    keys="$keys
$(json_keys "$list" "$((MAX_STEPS * 2))")" || return 2
    while IFS= read -r key; do
        case "$key" in
            trail/step/*) id=${key#trail/step/} ;;
            trail/plan/*.json) id=${key#trail/plan/}; id=${id%.json} ;;
            *) continue ;;
        esac
        if ! rs_valid_step "$id"; then
            missing "root $sess: a ${key%/*}/ key is not a step id"
            continue
        fi
        printf '%s\n' "$id" >> "$WORK/step-ids"
        printf '%s\n' "$key" >> "$WORK/step-keys"
    done <<<"$keys"
    while IFS= read -r id; do
        [ -n "$id" ] || continue
        row=$(jq -nc --arg step "$id" '{step: $step, session: null, workspace: null, superseded: null, plan: null}')
        if grep -qxF "trail/step/$id" "$WORK/step-keys"; then
            val=$(rs_koto_read "$ws" context get "$sess" "trail/step/$id" </dev/null) || return 2
            if step_ok "$val"; then
                row=$(jq -c --argjson v "$val" '. + ($v | {session, workspace, superseded})' <<<"$row")
            else
                missing "root $sess: trail/step/$id fails its pattern"
            fi
        fi
        if grep -qxF "trail/plan/$id.json" "$WORK/step-keys"; then
            val=$(rs_koto_read "$ws" context get "$sess" "trail/plan/$id.json" </dev/null) || return 2
            if plan_ok "$val"; then
                row=$(jq -c --argjson v "$val" --arg k "trail/plan/$id.md" \
                    '.plan = ($v | {sha, entry, recorded_at, text_key: $k})' <<<"$row")
            else
                missing "root $sess: trail/plan/$id.json fails its pattern"
            fi
        fi
        printf '%s\n' "$row" >> "$WORK/steps"
    done <<<"$(LC_ALL=C sort -u "$WORK/step-ids")"
    return 0
}

# step_ok <json>: a step record, every name and the workspace in its pattern.
step_ok() {
    local fields s w n
    fields=$(jq -r 'if type == "object" and (.session | type) == "string" and (.workspace | type) == "string"
            and (.superseded | type) == "array" and (.superseded | all(type == "string"))
            and ([.session, .workspace, .superseded[]] | all(test("[[:cntrl:]]") | not))
        then .session, .workspace, .superseded[] else empty end' <<<"$1" 2>&1) || return 1
    [ -n "$fields" ] || return 1
    { IFS= read -r s; IFS= read -r w; } <<<"$fields"
    rs_valid_session "$s" && rs_valid_workspace "$w" || return 1
    while IFS= read -r n; do
        [ -n "$n" ] || continue
        rs_valid_session "$n" || return 1
    done <<<"$(printf '%s\n' "$fields" | tail -n +3)"
    return 0
}

# plan_ok <json>: a plan snapshot record, its sha and time in their patterns.
plan_ok() {
    local fields sha at
    fields=$(jq -r 'if type == "object" and (.sha | type) == "string" and (.recorded_at | type) == "string"
            and ((.entry | type) == "null" or ((.entry | type) == "string" and (.entry | test("[[:cntrl:]]") | not)))
        then .sha, .recorded_at else empty end' <<<"$1" 2>&1) || return 1
    { IFS= read -r sha; IFS= read -r at; } <<<"$fields"
    [[ $sha =~ $RS_RE_SHA ]] && [[ $at =~ $RS_RE_AT ]]
}

ROOT_WS=""; ROOT_SESS=""; ROOT_RUN=""; UNREACHABLE=0; FAILED=0
while IFS="$(printf '\t')" read -r AT RID WS SESS; do
    [ -n "$RID" ] || continue
    read_root "$WS" "$SESS"
    case $? in
        0) ROOT_WS=$WS; ROOT_SESS=$SESS; ROOT_RUN=$RID; break ;;
        1) ;;
        69) UNREACHABLE=1 ;;
        *) FAILED=1 ;;
    esac
done < "$WORK/sorted"

if [ -z "$ROOT_SESS" ]; then
    if [ "$FAILED" -eq 1 ]; then
        echo "$PROG: could not read a record root the index names for $REPO#$N" >&2
        exit 2
    fi
    if [ "$UNREACHABLE" -eq 1 ]; then
        echo "$PROG: a record root for $REPO#$N is in a workspace this host can't reach without koto's --workspace option" >&2
        exit 2
    fi
    echo "$PROG: no record root the index names for $REPO#$N lists the PR" >&2
    exit 3
fi

if [ "$STEPS" -eq 1 ] && ! read_steps "$ROOT_WS" "$ROOT_SESS"; then
    echo "$PROG: could not read the step records of $ROOT_SESS" >&2
    exit 2
fi

OTHERS=$(printf '%s\n' "$RUN_IDS" | grep -vxF -- "$ROOT_RUN")
jq -n --arg ws "$ROOT_WS" --arg sess "$ROOT_SESS" --arg run "$ROOT_RUN" \
    --argjson unique "$([ "$ENTRY_COUNT" -eq 1 ] && echo true || echo false)" \
    --rawfile missing "$WORK/missing" --rawfile prs "$WORK/prs" --arg others "$OTHERS" \
    --rawfile steps "$WORK/steps" '
    ($missing | split("\n") | map(select(. != ""))) as $m
    | {record_root: {workspace: $ws, session: $sess},
       run_id: $run,
       complete: ($m | length == 0),
       unique: $unique,
       missing: $m,
       prs: ($prs | split("\n") | map(select(. != "") | fromjson) | unique_by([.repo, .number]) | sort_by(.repo, .number)),
       others: ($others | split("\n") | map(select(. != ""))),
       steps: ($steps | split("\n") | map(select(. != "") | fromjson)
               | sort_by((.step | capture("(?<n>[0-9]+)$").n // "0" | tonumber), .step))}'
