#!/usr/bin/env bash
# run-record-pin.sh -- pin the koto sessions that hold a finished run's
# evidence, so no removal by rule takes them, and record any pin koto
# refuses so the next invocation can retry it.
#
# A run that leaves its plan's PRs ready or merged is its own record (see
# scripts/run-trail.sh). koto keeps a finished session only until its
# retention passes; a pin (`koto session pin`, koto 0.24.0) keeps that one
# session past every removal by rule. This script makes one
# `koto session pin --reason <reason> <name>` call per session the run's
# evidence lives in:
#
#   the record root      always (a multi-pr plan root from the shared
#                        address, through record-store.sh's write path)
#   each step session    the root's `trail/step/<id>` names (never a name
#                        listed as superseded), pinned only when it is the
#                        root's own koto child (`koto workflows --children
#                        <root>`, read in the root's workspace), or its
#                        dispatched-by link names the root (the key
#                        `koto/links/dispatched-by/<root>` in its context,
#                        read in its own recorded workspace), as a
#                        coordinated work item's does
#   each index session   `pr.<owner>.<repo>.<n>` for each PR in the root's
#                        `trail/pr/*`, only when its `run/<run_id>` entry
#                        names the root and the root's session id, as the
#                        root's `trail/self` records them
#   a multi-pr item      on a plan root: the item's own /work-on session as
#                        `trail/item/<step>` names it (--item <step>, or every
#                        item when no --item is given), and the index session
#                        of that item's PR, held to the same entry check
#
# What belongs to the run is decided from these local facts and the run's own
# records, never from a name read back from another store alone. A name that
# fails a check is not pinned and is reported `skipped=<name>:<why>`. A
# session whose recorded workspace is not a directory on this host is not
# pinned either: it is recorded as unpinned with the code `other-workspace`.
# Its provenance can't be read from here, so that record comes before any
# check; a retry on a host that has the workspace checks it then, and one on
# this host records it unpinned again.
#
# The reason is `record of plan <topic>: <owner>/<repo>#<n>`: the plan's topic
# (from the root's name) and the run's own PR (the home PR, else the
# coordination PR, else the item's PR); an index session's reason names its
# own PR. It holds no plan prose and no control character, and is at most 500
# characters, the topic cut to fit.
#
# The floor. RECORD_PIN_FLOOR is koto 0.24.0, the release that adds the pin.
# It is checked from `koto version`, because 0.24.0 hides `session pin` from
# its help (and so no requires.tsv declares it). Below it no pin call is made
# and every name that would have been pinned is unpinned with the code
# `below-floor`.
#
# Unpinned. A pin koto refuses (exit 2, as koto 0.24.0 does under the cloud
# backend), can't confirm (exit 3), or fails any other way is recorded with
# koto's exit code. The run's unpinned names go to the root's
# `trail/unpinned`, {names: [{session, workspace, code}], at}, and the key is
# removed once none is left. A pin never holds the run: each template's
# `record_keep` state runs this as a default action whose command ends with
# `|| true`.
#
# --retry. The next invocation's opener (skills/execute/scripts/
# execute-open.sh before it replaces a finished root, and a multi-pr item's
# start, skills/work-on/scripts/multi-pr-item-record.sh) reruns this with
# --retry: only the names `trail/unpinned` lists are tried again, each put
# through the same checks first; a listed name that no longer passes is
# dropped as skipped. With no `trail/unpinned` it does nothing and prints
# `retry=none`.
#
# --result S writes the outcome into session S (in the directory this runs
# from), where the terminals' `result:` maps read it: `record` is `pinned`
# (every name pinned), `unpinned` (one or more recorded unpinned) or `skipped`
# (nothing to pin), and `record_unpinned` the unpinned names, space-joined,
# empty when there are none.
#
# shirabe never unpins: this script has no unpin path, and
# scripts/check-run-record-rules.sh fails on any unpin call in shirabe's
# skills and scripts. A pin comes off by hand (references/
# koto-session-retention.md).
#
# Usage:
#   run-record-pin.sh --root <session> [--item <step>] [--result <session>]
#                     [--retry]
#
# Run it from the root's checkout (a plan root's from the item's checkout; the
# script moves to the shared address for the root's own calls).
#
# Output: one line per name, `pinned=<name>`, `unpinned=<name>:<code>` or
# `skipped=<name>:<why>`, then `record=<pinned|unpinned|skipped>` (or
# `retry=none`).
#
# Exit codes:
#   0   done, whatever was pinned (the output says what)
#   64  usage: an unknown flag, a flag given twice or without a value, a
#       missing --root, a value outside its pattern
#   70  the outcome could not be recorded (trail/unpinned or the result keys)
#
# Requires: bash 3.2+, jq, koto.
set -uo pipefail

PROG=run-record-pin
SELF_DIR=$(CDPATH='' cd "$(dirname "${BASH_SOURCE[0]}")" && pwd) || exit 64
# shellcheck source=lib/record-store.sh
. "$SELF_DIR/lib/record-store.sh" || exit 64

RECORD_PIN_FLOOR=0.24.0
RP_REASON_MAX=500

usage() {
    echo "$PROG: $*" >&2
    echo "usage: run-record-pin.sh --root <session> [--item <step>] [--result <session>] [--retry]" >&2
    exit 64
}
failed() { echo "$PROG: $*" >&2; exit 70; }

ROOT=""; ITEM=""; RESULT=""; RETRY=0
SEEN=" "
while [ $# -gt 0 ]; do
    case "$SEEN" in *" $1 "*) usage "$1 given more than once" ;; esac
    case "$1" in
        --retry) SEEN="$SEEN$1 "; RETRY=1; shift; continue ;;
        --root|--item|--result) ;;
        *) usage "unexpected argument [$1]" ;;
    esac
    [ $# -ge 2 ] || usage "$1 needs a value"
    SEEN="$SEEN$1 "
    case "$1" in
        --root) ROOT=$2 ;;
        --item) ITEM=$2 ;;
        --result) RESULT=$2 ;;
    esac
    shift 2
done
[ -n "$ROOT" ] || usage "--root is required"
rs_valid_session "$ROOT" || usage "--root [$ROOT] is not a koto session name"
[ -z "$ITEM" ] || rs_valid_step "$ITEM" || usage "--item [$ITEM] is not a step id"
[ -z "$RESULT" ] || rs_valid_session "$RESULT" || usage "--result [$RESULT] is not a koto session name"

CALLER_DIR=$(pwd -P) || failed "could not read the working directory"

# The root's directory: a plan root lives at the shared address of the owner
# its name encodes, every other root here.
PLAN_ROOT=0
ROOT_DIR=$CALLER_DIR
if ROOT_OWNER=$(rs_plan_root_owner "$ROOT"); then
    PLAN_ROOT=1
    ROOT_DIR=$(rs_shared_dir "$ROOT_OWNER") || usage "no shared address for $ROOT"
fi
[ -z "$ITEM" ] || [ "$PLAN_ROOT" -eq 1 ] || usage "--item applies to a multi-pr plan root, plan.<owner>.<repo>.<topic>.<sha12>"

# root_koto <args>: a koto call on the root, from the root's directory. A
# plan root's writes go through record-store.sh's write path.
root_read() {
    if [ "$PLAN_ROOT" -eq 1 ]; then
        rs_koto_read "$ROOT_DIR" "$@" </dev/null
    else
        koto "$@" </dev/null
    fi
}
root_write() {
    if [ "$PLAN_ROOT" -eq 1 ]; then
        rs_koto_write "$ROOT_DIR" "$@"
    else
        koto "$@"
    fi
}
# root_get <key>: the key's value, or nothing (1) when the root lacks it.
root_get() {
    root_read context exists "$ROOT" "$1" >/dev/null 2>&1 || return 1
    root_read context get "$ROOT" "$1"
}

TMP=$(mktemp -d "${TMPDIR:-/tmp}/run-record-pin.XXXXXX") || failed "mktemp failed"
trap 'rm -rf -- "$TMP"' EXIT

# The names to pin. One line each in $TMP/cands:
#   <name> TAB <workspace> TAB <how> TAB <repo#n for the reason, or empty>
# where <how> is root (the root's own call), shared (an index session, at the
# shared address) or local (a session in its recorded workspace).
: > "$TMP/cands"
: > "$TMP/report"
add_cand() { printf '%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "$4" >> "$TMP/cands"; }
skip() { printf 'skipped=%s:%s\n' "$1" "$2" >> "$TMP/report"; }

# --retry with nothing listed has nothing to do.
UNP=""
if [ "$RETRY" -eq 1 ] && ! UNP=$(root_get trail/unpinned 2>/dev/null); then
    echo "retry=none"
    exit 0
fi

# The run's address and identity, for the index entry check.
SELF_RUN=""; SELF_SID=""
if SELF_DOC=$(root_get trail/self 2>/dev/null); then
    SELF_RUN=$(jq -r 'if type == "object" and (.run_id | type) == "string" then .run_id else "" end' <<<"$SELF_DOC" 2>/dev/null) || SELF_RUN=""
    SELF_SID=$(jq -r 'if type == "object" and (.session_id | type) == "string" then .session_id else "" end' <<<"$SELF_DOC" 2>/dev/null) || SELF_SID=""
    [[ $SELF_RUN =~ $RS_RE_RUN_ID ]] || SELF_RUN=""
    [[ $SELF_SID =~ $RS_RE_SESSION_ID ]] || SELF_SID=""
fi

# The topic, from the root's name.
if [ "$PLAN_ROOT" -eq 1 ]; then
    TOPIC=$(rs_plan_root_topic "$ROOT") || TOPIC=""
else
    TOPIC=${ROOT#execute-}
fi
TOPIC=$(printf '%s' "$TOPIC" | tr -d '[:cntrl:]')

# The PRs the root records: <repo> TAB <n> TAB <role>.
: > "$TMP/prs"
if PR_KEYS=$(root_read context list "$ROOT" --prefix trail/pr/ 2>/dev/null); then
    while IFS= read -r K; do
        [ -n "$K" ] || continue
        V=$(root_read context get "$ROOT" "$K" 2>/dev/null) || continue
        jq -r 'if type == "object" and (.repo | type) == "string" and (.number | type) == "number"
                and (.role | type) == "string" then [.repo, (.number | tostring), .role] | @tsv else empty end' \
            <<<"$V" 2>/dev/null >> "$TMP/prs"
    done <<<"$(jq -r 'if type == "array" then .[] | strings else empty end' <<<"$PR_KEYS" 2>/dev/null)"
fi
pr_valid() { # pr_valid <repo> <n>
    case "$1" in */*/*|/*|*/) return 1 ;; */*) ;; *) return 1 ;; esac
    rs_valid_owner "${1%%/*}" && rs_valid_repo "${1#*/}" && [[ $2 =~ $RS_RE_NUMBER ]]
}

# The run's own PR, for the reason: home, else coordination, else the first.
PRIMARY=""
for role in home coordination; do
    [ -n "$PRIMARY" ] && break
    while IFS=$'\t' read -r r n ro; do
        [ "$ro" = "$role" ] && pr_valid "$r" "$n" && { PRIMARY="$r#$n"; break; }
    done < "$TMP/prs"
done

# index_cand <repo> <n> <holder>: the PR's index session, when its entry for
# this run names <holder> (the root) and the root's session id.
index_cand() {
    local repo=$1 n=$2 name dir entry rc es ei
    name=$(rs_index_name "$repo" "$n") || return 0
    if [ -z "$SELF_RUN" ] || [ -z "$SELF_SID" ]; then
        skip "$name" no-self
        return 0
    fi
    dir=$(rs_shared_dir "${repo%%/*}") || { skip "$name" no-address; return 0; }
    rs_koto_read "$dir" context exists "$name" "run/$SELF_RUN" </dev/null >/dev/null 2>&1
    rc=$?
    case "$rc" in
        0)
            entry=$(rs_koto_read "$dir" context get "$name" "run/$SELF_RUN" </dev/null 2>/dev/null)
            rc=$?
            ;;
        1|68|69) skip "$name" no-entry; return 0 ;;
    esac
    if [ "$rc" -ne 0 ]; then
        # A read that failed is not a "no": the entry may be there, so the
        # name is recorded unpinned and tried again.
        add_cand "$name" "$dir" unreadable "$repo#$n"
        return 0
    fi
    es=$(jq -r 'if type == "object" and (.session | type) == "string" then .session else "" end' <<<"$entry" 2>/dev/null) || es=""
    ei=$(jq -r 'if type == "object" and (.session_id | type) == "string" then .session_id else "" end' <<<"$entry" 2>/dev/null) || ei=""
    if [ "$es" != "$ROOT" ] || [ "$ei" != "$SELF_SID" ]; then
        skip "$name" not-this-run
        return 0
    fi
    add_cand "$name" "$dir" shared "$repo#$n"
}

# The root itself.
add_cand "$ROOT" "$ROOT_DIR" root ""

if [ "$PLAN_ROOT" -eq 1 ]; then
    # A multi-pr plan root: the item (or every item) and its PR's index.
    if [ -n "$ITEM" ]; then
        ITEM_KEYS="trail/item/$ITEM"
    else
        ITEM_KEYS=$(root_read context list "$ROOT" --prefix trail/item/ 2>/dev/null \
            | jq -r 'if type == "array" then .[] | strings else empty end' 2>/dev/null)
    fi
    while IFS= read -r K; do
        [ -n "$K" ] || continue
        V=$(root_get "$K" 2>/dev/null) || { skip "${K#trail/item/}" no-item-record; continue; }
        IS=$(jq -r 'if type == "object" and (.session | type) == "string" then .session else "" end' <<<"$V" 2>/dev/null) || IS=""
        IW=$(jq -r 'if type == "object" and (.workspace | type) == "string" then .workspace else "" end' <<<"$V" 2>/dev/null) || IW=""
        IR=$(jq -r 'if type == "object" and (.pr | type) == "object" and (.pr.repo | type) == "string" then .pr.repo else "" end' <<<"$V" 2>/dev/null) || IR=""
        IN=$(jq -r 'if type == "object" and (.pr | type) == "object" and (.pr.number | type) == "number" then (.pr.number | tostring) else "" end' <<<"$V" 2>/dev/null) || IN=""
        rs_valid_session "$IS" || { skip "${K#trail/item/}" no-item-session; continue; }
        rs_valid_workspace "$IW" || { skip "$IS" no-workspace; continue; }
        REASON_PR=""
        if pr_valid "$IR" "$IN"; then
            REASON_PR="$IR#$IN"
            [ -n "$ITEM" ] && PRIMARY="$IR#$IN"
        fi
        add_cand "$IS" "$IW" local "$REASON_PR"
        [ -n "$REASON_PR" ] && index_cand "$IR" "$IN"
    done <<<"$ITEM_KEYS"
else
    # The root's koto children, read once in the root's workspace.
    CHILDREN=$(koto workflows --children "$ROOT" </dev/null 2>/dev/null \
        | jq -r 'if type == "array" then .[] | (.name // empty) | strings else empty end' 2>/dev/null) || CHILDREN=""
    STEP_KEYS=$(root_read context list "$ROOT" --prefix trail/step/ 2>/dev/null \
        | jq -r 'if type == "array" then .[] | strings else empty end' 2>/dev/null)
    while IFS= read -r K; do
        [ -n "$K" ] || continue
        V=$(root_get "$K" 2>/dev/null) || continue
        SS=$(jq -r 'if type == "object" and (.session | type) == "string" then .session else "" end' <<<"$V" 2>/dev/null) || SS=""
        SW=$(jq -r 'if type == "object" and (.workspace | type) == "string" then .workspace else "" end' <<<"$V" 2>/dev/null) || SW=""
        rs_valid_session "$SS" || { skip "${K#trail/step/}" no-step-session; continue; }
        rs_valid_workspace "$SW" || { skip "$SS" no-workspace; continue; }
        if [ ! -d "$SW" ]; then
            add_cand "$SS" "$SW" local ""
            continue
        fi
        if grep -qxF -- "$SS" <<<"$CHILDREN"; then
            add_cand "$SS" "$SW" local ""
        elif (cd -- "$SW" && koto context exists "$SS" "koto/links/dispatched-by/$ROOT" </dev/null >/dev/null 2>&1); then
            add_cand "$SS" "$SW" local ""
        else
            skip "$SS" not-dispatched-by-root
        fi
    done <<<"$STEP_KEYS"
    while IFS=$'\t' read -r r n ro; do
        [ -n "$r" ] || continue
        pr_valid "$r" "$n" || continue
        index_cand "$r" "$n"
    done < "$TMP/prs"
fi

# --retry: only the names trail/unpinned lists.
if [ "$RETRY" -eq 1 ]; then
    jq -r 'if type == "object" and (.names | type) == "array" then .names[] | (.session // empty) | strings else empty end' \
        <<<"$UNP" 2>/dev/null > "$TMP/listed" || : > "$TMP/listed"
    awk -F'\t' 'NR == FNR { want[$0] = 1; next } ($1 in want)' "$TMP/listed" "$TMP/cands" > "$TMP/cands.retry"
    while IFS= read -r L; do
        [ -n "$L" ] || continue
        cut -f1 "$TMP/cands" | grep -qxF -- "$L" || skip "$L" no-longer-this-run
    done < "$TMP/listed"
    mv -- "$TMP/cands.retry" "$TMP/cands"
fi

# version_ok: 0 when the installed koto is at or above RECORD_PIN_FLOOR.
version_ok() {
    local v have want i a b
    v=$(koto version </dev/null 2>/dev/null | sed -n '1s/^koto \([0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*\).*/\1/p')
    [ -n "$v" ] || return 1
    IFS=. read -r -a have <<<"$v"
    IFS=. read -r -a want <<<"$RECORD_PIN_FLOOR"
    for i in 0 1 2; do
        a=${have[$i]:-0}; b=${want[$i]:-0}
        [ "$a" -gt "$b" ] && return 0
        [ "$a" -lt "$b" ] && return 1
    done
    return 0
}

# reason_for <repo#n>: the pin reason, the topic cut so the whole fits.
reason_for() {
    local pr=$1 tail head room t=$TOPIC
    if [ -n "$pr" ]; then
        tail=": ${pr%%#*}#${pr#*#}"
    else
        tail=""
    fi
    head="record of plan "
    room=$((RP_REASON_MAX - ${#head} - ${#tail}))
    [ "$room" -ge 1 ] || room=1
    [ "${#t}" -le "$room" ] || t=${t:0:$room}
    [ -n "$t" ] || t=unknown
    printf '%s%s%s' "$head" "$t" "$tail"
}

ABOVE_FLOOR=0
version_ok && ABOVE_FLOOR=1

: > "$TMP/unpinned"
PINNED=0
SEEN_NAMES=" "
while IFS=$'\t' read -r NAME WS HOW PR; do
    [ -n "$NAME" ] || continue
    case "$SEEN_NAMES" in *" $NAME "*) continue ;; esac
    SEEN_NAMES="$SEEN_NAMES$NAME "
    [ -n "$PR" ] || PR=$PRIMARY
    CODE=""
    if [ "$HOW" = local ] && [ ! -d "$WS" ]; then
        CODE=other-workspace
    elif [ "$HOW" = unreadable ]; then
        CODE=unreadable
    elif [ "$ABOVE_FLOOR" -ne 1 ]; then
        CODE=below-floor
    else
        REASON=$(reason_for "$PR")
        case "$HOW" in
            root) root_write session pin --reason "$REASON" "$NAME" </dev/null >/dev/null ;;
            shared) rs_koto_write "$WS" session pin --reason "$REASON" "$NAME" </dev/null >/dev/null ;;
            *) (cd -- "$WS" && koto session pin --reason "$REASON" "$NAME" </dev/null >/dev/null) ;;
        esac
        RC=$?
        [ "$RC" -eq 0 ] || CODE=$RC
    fi
    if [ -z "$CODE" ]; then
        printf 'pinned=%s\n' "$NAME" >> "$TMP/report"
        PINNED=$((PINNED + 1))
    else
        printf 'unpinned=%s:%s\n' "$NAME" "$CODE" >> "$TMP/report"
        jq -nc --arg s "$NAME" --arg w "$WS" --arg c "$CODE" '{session: $s, workspace: $w, code: $c}' >> "$TMP/unpinned" \
            || failed "jq failed"
    fi
done < "$TMP/cands"

cat -- "$TMP/report"

# trail/unpinned: what is left, or removed once nothing is.
RECORD_FAILED=0
if [ -s "$TMP/unpinned" ]; then
    DOC=$(jq -sc --arg at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" '{names: ., at: $at}' "$TMP/unpinned") || failed "jq failed"
    printf '%s' "$DOC" | root_write context add "$ROOT" trail/unpinned >/dev/null || RECORD_FAILED=1
else
    if root_read context exists "$ROOT" trail/unpinned >/dev/null 2>&1; then
        root_write context remove "$ROOT" trail/unpinned </dev/null >/dev/null || RECORD_FAILED=1
    fi
fi

if [ -s "$TMP/unpinned" ]; then
    OUTCOME=unpinned
elif [ "$PINNED" -gt 0 ]; then
    OUTCOME=pinned
else
    OUTCOME=skipped
fi
NAMES=$(jq -rs 'map(.session) | join(" ")' "$TMP/unpinned" 2>/dev/null) || NAMES=""
printf 'record=%s\n' "$OUTCOME"

if [ -n "$RESULT" ]; then
    (cd -- "$CALLER_DIR" && printf '%s' "$OUTCOME" | koto context add "$RESULT" record >/dev/null) || RECORD_FAILED=1
    (cd -- "$CALLER_DIR" && printf '%s' "$NAMES" | koto context add "$RESULT" record_unpinned >/dev/null) || RECORD_FAILED=1
fi
[ "$RECORD_FAILED" -eq 0 ] || failed "could not record the outcome in $ROOT${RESULT:+ or $RESULT}"
exit 0
