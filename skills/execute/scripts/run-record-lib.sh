# run-record-lib.sh — the reader of a coordinated run's record.
#
# Sourced, never run. A coordinated /execute run keeps its control-plane facts
# (the node list, each node's PR and pushed head, the cascade's verdict, the
# coordination PR's number, the store) as `run/` keys in its own koto session,
# `execute-<topic>`, beside the session's `run_id`. run-record.sh is the one
# writer of those keys; this file is the one reader. Every read is a local
# koto call: nothing here reads GitHub.
#
# The layout, one JSON object per key:
#
#   run/setup                  store, coordination_pr, repos, mode, nodes,
#                              run_lines
#   run/node/<node>            repo, pr, head, deferrals, merged_head
#   run/follow-up/<node>/<n>   repo, pr, head, merged_head, removed
#   run/cascade                verdict, head, step
#   run/recovered              pr, source
#   run/adopted                id, login, at
#
# A key under `run/` outside that layout (RR_KEY_RE, with the node id
# `coordination` refused) is reported on stderr and ignored, never read as part
# of the record.
#
# Functions (each takes the koto session name first):
#
#   rr_keys <S>             the record's keys, one per line, sorted; rc 2 when
#                           the list failed
#   rr_record <S>           one JSON object {key: value} of every key; `{}`
#                           when there are none; rc 2 when a read failed or a
#                           value is not one JSON object
#   rr_setup <S>            the run/setup object; rc 1 when absent, rc 2 when
#                           the read failed (absence and failure differ: the
#                           key's existence is checked first)
#   rr_nodes <S>            run/setup's node list; rc 1 when there is no record
#   rr_node <S> <node>      the run/node/<node> object; rc 1 when absent
#   rr_follow_ups <S> <node>  that node's follow-up objects, sorted by pr (`[]`
#                           when none)
#   rr_cascade <S>          the run/cascade object, `{"verdict":"not-run"}`
#                           when absent
#   rr_q <record> <filter>  jq <filter> over an already-loaded record (raw
#                           strings, compact objects), so a caller that read
#                           the record once with rr_record projects it without
#                           another koto call
#
# Callers set PROG and `set -uo pipefail` themselves. Every object printed is
# canonical JSON (`jq -cS`).
#
# Requires: bash 3.2+, jq, koto.

RR_KEY_RE='^run/(setup|cascade|recovered|adopted|node/[a-z][a-z0-9-]*|follow-up/[a-z][a-z0-9-]*/[1-9][0-9]*)$'

# rr_valid_key <key> -- the key is in the record's fixed layout.
rr_valid_key() {
    [[ $1 =~ $RR_KEY_RE ]] || return 1
    case "$1" in run/node/coordination|run/follow-up/coordination/*) return 1 ;; esac
    return 0
}

rr_keys() {
    local out keys k
    out=$(koto context list "$1" --prefix run/ </dev/null) || {
        echo "${PROG:-run-record-lib}: could not list the run record's keys in session $1" >&2
        return 2
    }
    keys=$(printf '%s' "$out" | jq -r 'if type == "array" and all(.[]; type == "string") then .[] else error("not a key list") end') || {
        echo "${PROG:-run-record-lib}: koto context list for session $1 is not a JSON list of keys" >&2
        return 2
    }
    while IFS= read -r k; do
        [ -n "$k" ] || continue
        if rr_valid_key "$k"; then
            printf '%s\n' "$k"
        else
            echo "${PROG:-run-record-lib}: ignoring context key [$k] in session $1: it is outside the run record's layout" >&2
        fi
    done <<<"$keys" | LC_ALL=C sort
    return 0
}

# rr__object <S> <key> -- the key's value as one canonical JSON object; rc 2
# when the read fails or the value is anything else.
rr__object() {
    local v
    v=$(koto context get "$1" "$2" </dev/null) || {
        echo "${PROG:-run-record-lib}: could not read $2 in session $1" >&2
        return 2
    }
    printf '%s' "$v" | jq -cS -s 'if length == 1 and (.[0] | type) == "object" then .[0] else error("not one object") end' || {
        echo "${PROG:-run-record-lib}: $2 in session $1 is not one JSON object" >&2
        return 2
    }
}

# rr__present <S> <key> -- rc 0 present, 1 absent, 2 the check failed.
rr__present() {
    local rc
    koto context exists "$1" "$2" </dev/null >/dev/null
    rc=$?
    case "$rc" in
        0) return 0 ;;
        1) return 1 ;;
        *) echo "${PROG:-run-record-lib}: could not check $2 in session $1 (koto exit $rc)" >&2; return 2 ;;
    esac
}

rr_record() {
    local keys k v doc='{}'
    keys=$(rr_keys "$1") || return 2
    while IFS= read -r k; do
        [ -n "$k" ] || continue
        v=$(rr__object "$1" "$k") || return 2
        doc=$(jq -cnS --argjson d "$doc" --arg k "$k" --argjson v "$v" '$d + {($k): $v}') || return 2
    done <<<"$keys"
    printf '%s\n' "$doc"
}

rr_setup() {
    rr__present "$1" run/setup || return $?
    rr__object "$1" run/setup
}

rr_nodes() {
    local s
    s=$(rr_setup "$1") || return $?
    printf '%s' "$s" | jq -c '.nodes // []'
}

rr_node() {
    rr__present "$1" "run/node/$2" || return $?
    rr__object "$1" "run/node/$2"
}

rr_follow_ups() {
    local rec
    rec=$(rr_record "$1") || return 2
    printf '%s' "$rec" | jq -c --arg p "run/follow-up/$2/" '[to_entries[] | select(.key | startswith($p)) | .value] | sort_by(.pr)'
}

rr_cascade() {
    local rc
    rr__present "$1" run/cascade
    rc=$?
    case "$rc" in
        0) rr__object "$1" run/cascade ;;
        1) printf '{"verdict":"not-run"}\n' ;;
        *) return 2 ;;
    esac
}

rr_q() {
    printf '%s' "$1" | jq -rc "$2"
}
