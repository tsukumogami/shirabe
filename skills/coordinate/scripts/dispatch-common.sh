#!/usr/bin/env bash
# dispatch-common.sh -- helpers the coordinate skill's dispatch scripts source.
#
# Sourced, never run. Every function returns a status and prints only its
# answer on stdout; a caller decides what a failure means. bash 3.2.
#
#   dc_valid_topic <topic>
#       0 when the topic matches ^[a-z0-9][a-z0-9-]*$ and is at most 64
#       characters. The topic names the brief file, the lock and the worker,
#       so nothing else ever reaches a path.
#
#   dc_niwa_slug <topic>
#       Prints the slug niwa derives from `niwa dispatch --name <topic>`: each
#       run of characters outside [a-z0-9] becomes `_`, leading and trailing
#       `_` are trimmed, and the result is capped at 40 characters. The
#       worker's session name is this slug, `-`, and an 8-hex token. niwa
#       doesn't document the format yet (niwa#325), so it's pinned here and
#       in dispatch-common_test.sh.
#
#   dc_session_matches <topic> <session-name>
#       0 when the session name is exactly the topic's slug, `-`, and eight
#       lowercase hex digits. Never a prefix match: topic `api` doesn't match
#       `api_v2-1a2b3c4d`.
#
#   dc_workspace_root [<start-dir>]
#       Prints the workspace root for the start directory (default: the
#       working directory), or returns 2. niwa exposes no workspace root to a
#       process (niwa#326), so this walks up, guarded against being shadowed:
#       a clone can carry its own .niwa/workspace.toml, and a workspace root
#       also carries .niwa/instance.json. The walk takes the nearest ancestor
#       holding .niwa/instance.json. When that directory also holds
#       .niwa/workspace.toml it is the root; otherwise it's an instance, and
#       its parent must hold .niwa/workspace.toml. With no instance marker
#       above the start, the start directory itself must hold
#       .niwa/workspace.toml. Any other layout returns 2 rather than guess,
#       and a .niwa/workspace.toml met on the way up is never taken on its own.
#
#   dc_entry_row <skill>
#       Prints the entry point's row of references/entry-points.tsv, fields
#       tab-separated, or returns 1 when the skill has no row.
#
#   dc_entry_field <skill> <n>
#       Prints field n (1-5) of the skill's row.
#
#   dc_flag_allowed <skill> <flag>
#       0 when the flag is in the skill's allowed set: an exact entry, or a
#       `<prefix>=*` entry and a flag of the form `<prefix>=<non-empty value>`.

DC_HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
DC_ENTRY_POINTS="${DC_ENTRY_POINTS:-$DC_HERE/../references/entry-points.tsv}"

dc_valid_topic() {
    case "$1" in
        '' | -*) return 1 ;;
    esac
    [ "${#1}" -le 64 ] || return 1
    printf '%s' "$1" | grep -Eq '^[a-z0-9][a-z0-9-]*$'
}

dc_niwa_slug() {
    local s
    s=$(printf '%s' "$1" | tr 'A-Z' 'a-z' | sed -e 's/[^a-z0-9][^a-z0-9]*/_/g' -e 's/^_*//' -e 's/_*$//')
    s=$(printf '%s' "$s" | cut -c1-40 | sed -e 's/_*$//')
    printf '%s\n' "$s"
}

dc_session_matches() {
    local slug
    slug=$(dc_niwa_slug "$1")
    [ -n "$slug" ] || return 1
    case "$2" in
        "$slug"-*) ;;
        *) return 1 ;;
    esac
    printf '%s' "${2#"$slug"-}" | grep -Eq '^[0-9a-f]{8}$'
}

dc_workspace_root() {
    local d
    d=$(cd "${1:-.}" 2>&1 && pwd -P) || return 2
    local start="$d"
    while :; do
        if [ -f "$d/.niwa/instance.json" ]; then
            if [ -f "$d/.niwa/workspace.toml" ]; then
                printf '%s\n' "$d"
                return 0
            fi
            local p
            p=$(dirname "$d")
            if [ -f "$p/.niwa/workspace.toml" ]; then
                printf '%s\n' "$p"
                return 0
            fi
            return 2
        fi
        [ "$d" = / ] && break
        d=$(dirname "$d")
    done
    if [ -f "$start/.niwa/workspace.toml" ]; then
        printf '%s\n' "$start"
        return 0
    fi
    return 2
}

dc_entry_row() {
    [ -n "$1" ] || return 1
    [ -r "$DC_ENTRY_POINTS" ] || return 2
    local row
    row=$(awk -F'\t' -v s="$1" '!/^#/ && NF >= 5 && $1 == s { print; exit }' "$DC_ENTRY_POINTS")
    [ -n "$row" ] || return 1
    printf '%s\n' "$row"
}

dc_entry_field() {
    local row
    row=$(dc_entry_row "$1") || return $?
    printf '%s\n' "$row" | cut -f"$2"
}

dc_flag_allowed() {
    local flags f
    flags=$(dc_entry_field "$1" 5) || return 1
    [ "$flags" = - ] && return 1
    case "$2" in
        '' | *[[:space:]]*) return 1 ;;
    esac
    local IFS=,
    for f in $flags; do
        case "$f" in
            *'=*')
                case "$2" in
                    "${f%\*}"?*) return 0 ;;
                esac
                ;;
            *)
                [ "$2" = "$f" ] && return 0
                ;;
        esac
    done
    return 1
}
