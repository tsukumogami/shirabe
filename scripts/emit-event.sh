#!/usr/bin/env bash
# emit-event.sh -- send one telemetry event through the host's shared event
# sender, or do nothing. The only file in this repository that names the
# sender's path or its off switch (scripts/check-event-sender-names.sh fails
# the build if any other code does). docs/designs/DESIGN-fleet-cost-emit.md
# is the design.
#
# Usage:
#   emit-event.sh event --scope <scope> --kind <kind> [--koto-dir <dir>]
#                 [<key>=<value> ...]
#
# Callers run it as a child and ignore everything it does:
#
#   bash "$root/scripts/emit-event.sh" event --scope unit-cost --kind landed \
#       unit.pr=github.com/o/r#5 </dev/null >/dev/null 2>&1 || :
#
# never by sourcing it, so a fault in it can't reach the caller's shell.
#
# It stops, exiting 0, at the first of these that fails, in this order:
#
#   1. The off switch: FLEET_EVENT_SINK set to exactly `off` stops it. No
#      other value of the variable is read.
#   2. The date gate: /bin/date -u +%s must print an integer at or after
#      EE_NOT_BEFORE (2026-11-09T02:00:00Z). A clock it can't read counts as
#      before. The date is a constant: no variable, argument or setting moves
#      it, so nothing can start sending early.
#   3. Discovery: $HOME/.local/libexec/fleet/event-sink is a regular file,
#      not a symbolic link, and executable; it and every directory above it
#      (the physical path, up to /) are owned by this user's uid or by 0,
#      and none is writable by group or others. Ownership and mode come from
#      /bin/ls -ldn, which reads the same on macOS and Linux.
#   4. With --koto-dir (an absolute path with no `..` and no leading `-`),
#      `koto session list --execution-dir <dir>` runs under its own
#      EE_BOUND-second deadline, and the row whose id is unit.koto_session
#      gives unit.koto_session_id (and unit.parent_session, its
#      parent_workflow, when the caller passed none). A failed or slow read
#      leaves both out. The read runs only here, after the gate and the
#      discovery checks, so before the cutoff nothing reads koto at all.
#   5. Fields: unit.topic, unit.leg, unit.roadmap and unit.milestone are
#      mapped to the name alphabet (each other character becomes `_`) and cut
#      at 128 characters. Then each key must be in the field table below and
#      each value must match its shape whole; a key or value that doesn't, or
#      a value that starts with `--`, is dropped and the rest are sent. A
#      scope or kind outside the table sends nothing.
#
# Then the sender runs once, under `timeout -s KILL` when `timeout` is on PATH
# and under this script's own deadline otherwise (a watcher that kills the
# sender's whole process group), with `env -i` and only the allow-list below,
# each value one argument, standard input closed, its output and status
# discarded. It is never retried, nothing is spooled or written, and nothing
# is left running when this returns. Exit status is always 0.
#
# The sender's environment, exactly: HOME, PATH=EE_PATH, LANG and LC_ALL when
# set to a locale name, and the stamps the sender reads itself,
# CLAUDE_CODE_SESSION_ID, NIWA_DISPATCH_ID and NIWA_WORKSPACE, when set. No
# token or other variable of the calling script reaches it.
#
# The test (scripts/emit-event_test.sh) sources this file and calls ee_run with
# the time as its first argument; the command line always passes /bin/date's.
#
# Requires: bash 3.2+; jq for --koto-dir.

EE_NOT_BEFORE=1794189600
EE_BOUND=3
EE_PATH=/usr/bin:/bin:/usr/sbin:/sbin

EE_RE_ID='^[A-Za-z0-9._:-]{1,128}$'
EE_RE_NAME='^[A-Za-z0-9._:/@-]{1,128}$'
EE_RE_PR='^github\.com/[A-Za-z0-9._-]{1,64}/[A-Za-z0-9._-]{1,100}#[1-9][0-9]{0,9}$'
EE_RE_INT='^(0|[1-9][0-9]{0,18})$'
EE_RE_LOCALE='^[A-Za-z0-9_.@-]{1,64}$'

# ee_shape <key>: print the field's shape, with `map` for the free-text fields
# mapped before their check. Mirrors the design's field table.
ee_shape() {
    case "$1" in
        unit.request | unit.koto_session | unit.koto_session_id | unit.parent_session \
            | unit.worker_session | unit.worker_dispatch) echo id ;;
        unit.leg | unit.topic | unit.roadmap | unit.milestone) echo map ;;
        unit.scope_slug | unit.entry_point | unit.repo | unit.template | unit.mode \
            | unit.outcome) echo name ;;
        unit.requested_at) echo int ;;
        unit.pr) echo pr ;;
        *) return 1 ;;
    esac
}

# ee_kind_ok <scope> <kind>: the scopes and kinds this helper sends.
ee_kind_ok() {
    [ "$1" = unit-cost ] || return 1
    case "$2" in
        dispatched | session_opened | landed | retired) return 0 ;;
    esac
    return 1
}

# ee_value_ok <shape> <value>: the value matches its shape whole.
ee_value_ok() {
    case "$2" in --*) return 1 ;; esac
    case "$1" in
        id) [[ "$2" =~ $EE_RE_ID ]] ;;
        name | map) [[ "$2" =~ $EE_RE_NAME ]] ;;
        pr) [ "${#2}" -le 128 ] && [[ "$2" =~ $EE_RE_PR ]] ;;
        int)
            [[ "$2" =~ $EE_RE_INT ]] || return 1
            # 19 digits can pass 2^63-1; compare as text at that length.
            local max=9223372036854775807
            [ "${#2}" -lt 19 ] || [ "$2" = "$max" ] || [[ "n$2" < "n$max" ]]
            ;;
        *) return 1 ;;
    esac
}

# ee_map <value>: the value in the name alphabet, cut at 128 characters.
ee_map() {
    local v="$1"
    v=${v//[^A-Za-z0-9._:\/@-]/_}
    printf '%s' "${v:0:128}"
}

# ee_mode_ok <path> <file|dir>: the path's own entry is of that type, owned by
# this uid or by 0, and not writable by group or others.
ee_mode_ok() {
    local line mode uid
    line=$(/bin/ls -ldn -- "$1" 2>/dev/null) || return 1
    mode=${line%% *}
    line=${line#"$mode"}
    line=${line#"${line%%[! ]*}"}
    line=${line#*[ ]}
    line=${line#"${line%%[! ]*}"}
    uid=${line%% *}
    case "$2:${mode:0:1}" in
        file:-|dir:d) ;;
        *) return 1 ;;
    esac
    [ "${mode:5:1}" != w ] && [ "${mode:8:1}" != w ] || return 1
    [ "$uid" = "$EUID" ] || [ "$uid" = 0 ]
}

# ee_discover: print the sender's physical path when every check passes.
ee_discover() {
    local dir file
    [ -n "${HOME:-}" ] || return 1
    case "$HOME" in /*) ;; *) return 1 ;; esac
    file="$HOME/.local/libexec/fleet/event-sink"
    [ -f "$file" ] && [ ! -L "$file" ] && [ -x "$file" ] || return 1
    dir=$(cd -P -- "$HOME/.local/libexec/fleet" 2>/dev/null && pwd -P) || return 1
    file="$dir/event-sink"
    [ -f "$file" ] && [ ! -L "$file" ] && [ -x "$file" ] || return 1
    ee_mode_ok "$file" file || return 1
    while :; do
        ee_mode_ok "$dir" dir || return 1
        [ "$dir" = / ] && break
        dir=${dir%/*}
        [ -n "$dir" ] || dir=/
    done
    printf '%s' "$file"
}

# ee_bounded <secs> <command...>: run the command, a function or a program,
# for at most <secs> seconds. Job control puts it and the watcher each in a
# process group of their own, so the deadline kills everything the command
# started, and the watcher (with its sleep) is killed as soon as the command
# ends. Returns the command's status, 137 when the deadline killed it.
ee_bounded() {
    local secs="$1" pid w rc
    shift
    set -m
    "$@" &
    pid=$!
    (exec >/dev/null 2>&1 </dev/null; sleep "$secs"; kill -KILL -- "-$pid") &
    w=$!
    set +m
    wait "$pid"
    rc=$?
    kill -KILL -- "-$w" 2>/dev/null
    wait "$w" 2>/dev/null
    return "$rc"
}

# ee_lookup <dir> <session name>: print the session's id and parent, tab
# separated, from koto's listing of <dir>.
ee_lookup() {
    koto session list --execution-dir "$1" </dev/null 2>/dev/null \
        | jq -r --arg n "$2" 'first(.sessions[]? | select(.id == $n))
            | [(.session_id // "" | strings), (.parent_workflow // "" | strings)] | @tsv' 2>/dev/null
}

# ee_run <now> event --scope S --kind K [--koto-dir D] [key=value ...]
ee_run() {
    local now="$1" scope="" kind="" kdir="" sink key val shape got sid parent i
    local keys=() vals=() envs=()
    # The caller's locale goes to the sender; the checks here run in C, so a
    # character class means the same bytes in every locale.
    local lang="${LANG-}" lcall="${LC_ALL-}"
    local LC_ALL=C
    shift
    [ "${1:-}" = event ] || return 0
    shift
    while [ "$#" -gt 0 ]; do
        case "$1" in
            --scope) [ "$#" -ge 2 ] || return 0; scope="$2"; shift ;;
            --kind) [ "$#" -ge 2 ] || return 0; kind="$2"; shift ;;
            --koto-dir) [ "$#" -ge 2 ] || return 0; kdir="$2"; shift ;;
            --*) ;;
            *=*)
                key=${1%%=*}
                val=${1#*=}
                keys+=("$key")
                vals+=("$val")
                ;;
        esac
        shift
    done

    # 1. The off switch.
    [ "${FLEET_EVENT_SINK-}" != off ] || return 0
    # 2. The date gate.
    [[ "$now" =~ ^[0-9]{1,18}$ ]] || return 0
    [ "$now" -ge "$EE_NOT_BEFORE" ] || return 0
    # 3. Discovery.
    sink=$(ee_discover) || return 0
    [ -n "$sink" ] || return 0
    ee_kind_ok "$scope" "$kind" || return 0

    # 4. The koto session id, looked up only now.
    if [ -n "$kdir" ]; then
        case "$kdir" in
            /*) ;;
            *) kdir="" ;;
        esac
        case "/$kdir/" in */../*) kdir="" ;; esac
    fi
    sid=""
    parent=""
    if [ -n "$kdir" ]; then
        val=""
        for i in ${keys[@]+"${!keys[@]}"}; do
            [ "${keys[$i]}" = unit.koto_session ] && val="${vals[$i]}"
        done
        if ee_value_ok id "$val" && command -v koto >/dev/null 2>&1 && command -v jq >/dev/null 2>&1; then
            got=$(ee_bounded "$EE_BOUND" ee_lookup "$kdir" "$val" 2>/dev/null) || got=""
            got=${got%%$'\n'*}
            sid=${got%%$'\t'*}
            case "$got" in *$'\t'*) parent=${got#*$'\t'} ;; esac
        fi
    fi

    # 5. Fields. The looked-up id always wins over a passed one; a passed
    # parent wins over the looked-up one.
    set -- event --scope "$scope" --kind "$kind"
    for i in ${keys[@]+"${!keys[@]}"}; do
        key="${keys[$i]}"
        val="${vals[$i]}"
        [ "$key" != unit.koto_session_id ] || continue
        shape=$(ee_shape "$key") || continue
        [ "$shape" != map ] || val=$(ee_map "$val")
        ee_value_ok "$shape" "$val" || continue
        [ "$key" != unit.parent_session ] || parent=""
        set -- "$@" "$key=$val"
    done
    ! ee_value_ok id "$sid" || set -- "$@" "unit.koto_session_id=$sid"
    ! ee_value_ok id "$parent" || set -- "$@" "unit.parent_session=$parent"

    # The sender's environment: the allow-list and nothing else.
    envs=("HOME=$HOME" "PATH=$EE_PATH")
    [[ "$lang" =~ $EE_RE_LOCALE ]] && envs+=("LANG=$lang")
    [[ "$lcall" =~ $EE_RE_LOCALE ]] && envs+=("LC_ALL=$lcall")
    [ -z "${CLAUDE_CODE_SESSION_ID:-}" ] || envs+=("CLAUDE_CODE_SESSION_ID=$CLAUDE_CODE_SESSION_ID")
    [ -z "${NIWA_DISPATCH_ID:-}" ] || envs+=("NIWA_DISPATCH_ID=$NIWA_DISPATCH_ID")
    [ -z "${NIWA_WORKSPACE:-}" ] || envs+=("NIWA_WORKSPACE=$NIWA_WORKSPACE")

    if command -v timeout >/dev/null 2>&1; then
        timeout -s KILL "$EE_BOUND" /usr/bin/env -i "${envs[@]}" "$sink" "$@" </dev/null >/dev/null 2>&1
    else
        ee_bounded "$EE_BOUND" /usr/bin/env -i "${envs[@]}" "$sink" "$@" </dev/null >/dev/null 2>&1
    fi
    return 0
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    ee_now=$(/bin/date -u +%s 2>/dev/null) || ee_now=""
    ee_run "$ee_now" "$@" </dev/null >/dev/null 2>&1
    exit 0
fi
