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
# entry naming an unrelated session never leads anywhere. A multi-pr entry
# names a plan root, `plan.<owner>.<repo>.<topic>.<sha12>` at the shared
# address, which lists every item's PR, and that root confirms the PR through
# its `trail/item/*` records instead: one of them must name this PR. A
# multi-pr entry naming any other session, or another mode's entry naming a
# plan root, fails its pattern. An entry qualifies
# when its root confirms the PR; the first qualifying entry is the answer,
# and every other qualifying entry's run_id is in `others`.
#
# The root an entry names is found by the koto session id the entry
# recorded, not by its name alone. A re-run of the same topic
# (`koto init --replace-terminal`) moves the finished root aside as
# `<name>_r<N>`, with every `<name>.<rest>` and `<name>~<rest>` session
# renamed under it, and the new run takes `<name>` (koto's rule, written
# down once in record-store.sh's rs_moved_candidates and rs_moved_name). So
# the root is the
# session in the entry's workspace whose id is the recorded one, named
# `<name>` or `<name>_r1` to `<name>_r10`; one `koto session list` per
# workspace answers that. A session under any other name, or no session with
# that id, is not the entry's root: the run's record was moved past `_r10`
# or removed, and the entry leads nowhere. When the root was moved, the step
# sessions and superseded names `--steps` reports are given under the moved
# name, the way the move renamed them.
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
# `steps` is [] and the step records are not read. A multi-pr plan root
# records items (`item`) rather than steps: each row is one item, its
# `session` and `workspace` the item's own /work-on session and where it ran,
# `superseded` [], an added `pr` ({repo, number} or null), and `plan` the
# PLAN as that item began.
#
# Every read goes through record-store.sh's rs_koto_read, which passes koto's
# read-only --workspace option when the installed koto has it and otherwise
# runs koto from the addressed directory, which reaches the record on the
# host that wrote it. The lookup writes nothing, imports nothing and reads
# nothing from GitHub. Every value it reads back is checked against the same
# closed patterns the writer used; one that fails is named in `missing` and
# never used. Reads are bounded: at most 20 index entries per form of the
# shared address, 200 PR keys and 200 step keys per root, and one session
# list per workspace.
#
# Output, on exit 0, one JSON object built with jq:
#   {record_root: {workspace, session}, run_id, complete, unique,
#    missing: [...], prs: [{repo, number, role, state}], others: [run_id],
#    steps: [...]}
# `prs` is every PR the root lists, this one included: a single-pr run's home
# PR, a coordinated run's node, follow-up and coordination PRs, or a
# multi-pr plan's item PRs, items run later included, each with the role and
# the state its writer last recorded (a removed follow-up stays, as closed).
# `complete` is true when nothing was missing; `unique` is true when exactly
# one entry qualifies and no other entry's root was unreadable or
# unreachable, and `others` lists the other qualifying entries' run_ids. An
# entry whose root doesn't list the PR is in neither. The workspace names a
# user and an instance: it's internal, not for pasting into PRs or issues.
#
# Exit codes:
#   0   found; the JSON is on stdout
#   2   a store read failed, or a record root's workspace can't be reached
#       from here
#   3   no index entry for the PR, or no entry's record root is found (under
#       its name or a moved-aside one) and lists it
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
TAB=$(printf '\t')

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
            # A multi-pr entry names a plan root, and only a multi-pr one may.
            IS_PLAN_ROOT=0
            rs_plan_root_owner "$SESS" >/dev/null && IS_PLAN_ROOT=1
            case "$MODE:$IS_PLAN_ROOT" in
                single-pr:0|coordinated:0|multi-pr:1)
                    printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$AT" "$RID" "$WS" "$SESS" "$SID" "$MODE" >> "$WORK/entries"
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

# session_rows <workspace>: the path of a file holding koto's session list for
# the workspace, read once per workspace and kept for the next entry naming
# it; 2 on a failed read, 69 when the workspace can't be reached from here. A
# workspace koto says it holds nothing in (68) lists no sessions.
session_rows() {
    local ws=$1 n=0 f w rows rc
    while IFS="$TAB" read -r w f; do
        if [ "$w" = "$ws" ]; then
            printf '%s\n' "$f"
            return 0
        fi
        n=$((n + 1))
    done < "$WORK/session-lists"
    f="$WORK/session-list.$n"
    rows=$(rs_koto_read "$ws" session list </dev/null)
    rc=$?
    case "$rc" in
        0) ;;
        68) rows='[]' ;;
        69) return 69 ;;
        *) return 2 ;;
    esac
    jq -e 'type == "array"' >/dev/null 2>&1 <<<"$rows" || return 2
    printf '%s\n' "$rows" > "$f" || return 2
    printf '%s\t%s\n' "$ws" "$f" >> "$WORK/session-lists"
    printf '%s\n' "$f"
}

# resolve_root <workspace> <session> <session_id>: prints the name the root
# holds now, <session> or <session>_r<N>, found by its id; returns 0 found, 3
# not found, 2 a failed read, 69 an unreachable workspace. Only the rows that
# bear on the answer are checked against their patterns, so the rest of a
# large store adds nothing to `missing`: a row holding the recorded id under
# a name outside the session pattern, and a row under a candidate name whose
# id is outside the id pattern, are named in `missing` and never used.
resolve_root() {
    local ws=$1 sess=$2 sid=$3 f rc rows kind name cand
    f=$(session_rows "$ws")
    rc=$?
    [ "$rc" -eq 0 ] || return "$rc"
    # A value that isn't a string, or holds a control character, reads as ""
    # and so fails its pattern below.
    rows=$(jq -r --arg sid "$sid" --arg s "$sess" '
        def clean: if type == "string" and (test("[[:cntrl:]]") | not) then . else "" end;
        .[] | select(type == "object")
        | (.id | clean) as $id
        | (.session_id | clean) as $i
        | if $i == $sid then "id\t" + $id
          elif $id == $s or ($id | startswith($s + "_r")) then "name\t" + $i
          else empty end' "$f") || return 2
    while IFS="$TAB" read -r kind name; do
        case "$kind" in
            id) rs_valid_session "$name" \
                    || missing "session list: a session holding the id recorded for $sess has a name that fails its pattern" ;;
            name) [[ $name =~ $RS_RE_SESSION_ID ]] \
                    || missing "session list: a session named as $sess or a moved-aside name has an id that fails its pattern" ;;
        esac
    done <<<"$rows"
    while IFS= read -r cand; do
        [ -n "$cand" ] || continue
        if grep -qxF -- "id$TAB$cand" <<<"$rows"; then
            printf '%s\n' "$cand"
            return 0
        fi
    done <<<"$(rs_moved_candidates "$sess")"
    return 3
}

# moved_name <name>: the name a session has after its root moved from
# $ENTRY_SESS to $ROOT_SESS, by koto's rule (record-store.sh's
# rs_moved_name); 1 when the result fails the session pattern, so a built
# name is never used unchecked.
moved_name() {
    rs_moved_name "$ENTRY_SESS" "$ROOT_SESS" "$1"
}

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
            | select(.role == "home" or .role == "node" or .role == "follow-up" or .role == "coordination" or .role == "item")
            | select(.number >= 1 and .number == (.number | floor))
            | {repo, number, role, state}' <<<"$val" 2>&1) || row=""
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

# read_steps <workspace> <session> <prefix>: the root's step records (prefix
# trail/step/) or a plan root's item records (trail/item/), with the plan
# snapshots, as JSON lines in $WORK/steps; returns 2 on a read failure.
read_steps() {
    local ws=$1 sess=$2 pfx=$3 list keys key id val row
    : > "$WORK/step-ids"
    : > "$WORK/step-keys"
    list=$(rs_koto_read "$ws" context list "$sess" --prefix "$pfx" </dev/null) || return 2
    keys=$(json_keys "$list" "$MAX_STEPS") || return 2
    # Each plan snapshot is two keys, the .md text and the .json record.
    list=$(rs_koto_read "$ws" context list "$sess" --prefix trail/plan/ </dev/null) || return 2
    keys="$keys
$(json_keys "$list" "$((MAX_STEPS * 2))")" || return 2
    while IFS= read -r key; do
        case "$key" in
            "$pfx"*) id=${key#"$pfx"} ;;
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
        if [ "$pfx" = trail/item/ ]; then
            row=$(jq -c '. + {pr: null}' <<<"$row")
            if grep -qxF "trail/item/$id" "$WORK/step-keys"; then
                val=$(rs_koto_read "$ws" context get "$sess" "trail/item/$id" </dev/null) || return 2
                if val=$(item_ok "$val"); then
                    row=$(jq -c --argjson v "$val" '. + $v + {superseded: []}' <<<"$row")
                else
                    missing "root $sess: trail/item/$id fails its pattern"
                fi
            fi
        elif grep -qxF "trail/step/$id" "$WORK/step-keys"; then
            val=$(rs_koto_read "$ws" context get "$sess" "trail/step/$id" </dev/null) || return 2
            if step_ok "$val" && val=$(moved_step "$val"); then
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

# item_ok <json>: a multi-pr item record ({session, workspace, pr}), its
# session and workspace in their patterns and its pr null or {repo, number}
# with the repository in owner/repo form; prints it as {session, workspace,
# pr} with the repository lowercased, or returns 1.
item_ok() {
    local fields s w r n
    fields=$(jq -r 'if type == "object" and (.session | type) == "string" and (.workspace | type) == "string"
            and ([.session, .workspace] | all(test("[[:cntrl:]]") | not))
            and ((.pr | type) == "null" or ((.pr | type) == "object" and (.pr.repo | type) == "string"
                and (.pr.repo | test("[[:cntrl:]]") | not) and (.pr.number | type) == "number"))
        then .session, .workspace, (.pr.repo // ""), (.pr.number // "" | tostring) else empty end' <<<"$1" 2>&1) || return 1
    [ -n "$fields" ] || return 1
    { IFS= read -r s; IFS= read -r w; IFS= read -r r; IFS= read -r n; } <<<"$fields"
    rs_valid_session "$s" && rs_valid_workspace "$w" || return 1
    if [ -z "$r" ]; then
        jq -nc --arg s "$s" --arg w "$w" '{session: $s, workspace: $w, pr: null}'
        return
    fi
    [[ $r == */* ]] && rs_valid_owner "${r%%/*}" && rs_valid_repo "${r#*/}" && [[ $n =~ $RS_RE_NUMBER ]] || return 1
    jq -nc --arg s "$s" --arg w "$w" --arg r "$(rs_lower "$r")" --argjson n "$n" \
        '{session: $s, workspace: $w, pr: {repo: $r, number: $n}}'
}

# read_items <workspace> <session>: 0 when one of the plan root's
# trail/item/* records names this PR, 1 when none does, 2 on a read
# failure, 69 when the workspace can't be reached from here.
read_items() {
    local ws=$1 sess=$2 list keys key val rc item found=1
    list=$(rs_koto_read "$ws" context list "$sess" --prefix trail/item/ </dev/null)
    rc=$?
    [ "$rc" -eq 69 ] && return 69
    [ "$rc" -eq 0 ] || return 2
    keys=$(json_keys "$list" "$MAX_STEPS") || return 2
    while IFS= read -r key; do
        [ -n "$key" ] || continue
        val=$(rs_koto_read "$ws" context get "$sess" "$key" </dev/null) || return 2
        if ! item=$(item_ok "$val"); then
            missing "root $sess: a trail/item entry fails its pattern"
            continue
        fi
        if [ "$(jq -r '.pr.repo // ""' <<<"$item")" = "$REPO" ] && [ "$(jq -r '.pr.number // ""' <<<"$item")" = "$N" ]; then
            found=0
        fi
    done <<<"$keys"
    return "$found"
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

# moved_step <json>: a checked step record with its session and superseded
# names as they are after the root's move (moved_name); 1 when one of them
# then fails its pattern.
moved_step() {
    local names n out=""
    names=$(jq -r '.session, .superseded[]' <<<"$1") || return 1
    while IFS= read -r n; do
        n=$(moved_name "$n") || return 1
        out="$out$n
"
    done <<<"$names"
    jq -c --arg names "$out" '($names | split("\n") | map(select(. != ""))) as $n
        | .session = $n[0] | .superseded = $n[1:]' <<<"$1"
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

# Every entry is weighed, latest first: the first whose root confirms the PR
# is the answer, and the rest decide only `unique` and `others`. Once there is
# an answer, an entry whose root can't be found, read or reached is named in
# `missing`, since that run may have carried the PR too.
: > "$WORK/session-lists"
: > "$WORK/qualifying"
: > "$WORK/unresolved"
ROOT_WS=""; ROOT_SESS=""; ROOT_RUN=""; ENTRY_SESS=""; ROOT_MODE=""
UNREACHABLE=0; FAILED=0; NOT_FOUND=0; UNLISTED=0; UNKNOWN=0
while IFS="$TAB" read -r AT RID WS SESS SID MODE; do
    [ -n "$RID" ] || continue
    FOUND=$(resolve_root "$WS" "$SESS" "$SID")
    RC=$?
    if [ "$RC" -eq 0 ]; then
        read_root "$WS" "$FOUND"
        RC=$?
        # A multi-pr plan root confirms the PR through its items, not its
        # trail/pr list.
        if [ "$MODE" = multi-pr ] && { [ "$RC" -eq 0 ] || [ "$RC" -eq 1 ]; }; then
            read_items "$WS" "$FOUND"
            RC=$?
        fi
    fi
    case "$RC" in
        0)
            printf '%s\n' "$RID" >> "$WORK/qualifying"
            if [ -z "$ROOT_SESS" ]; then
                ROOT_WS=$WS; ROOT_SESS=$FOUND; ROOT_RUN=$RID; ENTRY_SESS=$SESS; ROOT_MODE=$MODE
                cp -- "$WORK/prs" "$WORK/root-prs" || exit 2
            fi
            continue
            ;;
        1) UNLISTED=1; continue ;;
        3) NOT_FOUND=1; NOTE="was not found under its name or any moved-aside name" ;;
        69) UNREACHABLE=1; UNKNOWN=1; NOTE="is in a workspace this host can't reach" ;;
        *) FAILED=1; UNKNOWN=1; NOTE="could not be read" ;;
    esac
    printf 'index: the record root of run/%s %s\n' "$RID" "$NOTE" >> "$WORK/unresolved"
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
    if [ "$NOT_FOUND" -eq 1 ]; then
        echo "$PROG: the recorded root for $REPO#$N wasn't found under its name or any moved-aside name (_r1 to _r$RS_MAX_MOVED)" >&2
    fi
    if [ "$UNLISTED" -eq 1 ]; then
        echo "$PROG: no record root the index names for $REPO#$N lists the PR" >&2
    fi
    exit 3
fi
cat -- "$WORK/unresolved" >> "$WORK/missing" || exit 2

STEP_PREFIX=trail/step/
[ "$ROOT_MODE" = multi-pr ] && STEP_PREFIX=trail/item/
if [ "$STEPS" -eq 1 ] && ! read_steps "$ROOT_WS" "$ROOT_SESS" "$STEP_PREFIX"; then
    echo "$PROG: could not read the step records of $ROOT_SESS" >&2
    exit 2
fi

OTHERS=$(LC_ALL=C sort -u "$WORK/qualifying" | grep -vxF -- "$ROOT_RUN")
UNIQUE=false
[ -z "$OTHERS" ] && [ "$UNKNOWN" -eq 0 ] && UNIQUE=true
jq -n --arg ws "$ROOT_WS" --arg sess "$ROOT_SESS" --arg run "$ROOT_RUN" \
    --argjson unique "$UNIQUE" \
    --rawfile missing "$WORK/missing" --rawfile prs "$WORK/root-prs" --arg others "$OTHERS" \
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
