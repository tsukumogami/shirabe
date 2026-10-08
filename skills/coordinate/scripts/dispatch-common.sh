#!/usr/bin/env bash
# dispatch-common.sh -- helpers the coordinate skill's dispatch scripts source.
#
# Sourced, never run. Every function returns a status and prints only its
# answer on stdout; a caller decides what a failure means. bash 3.2.
#
#   dc_valid_topic <topic>
#       0 when the topic matches ^[a-z0-9][a-z0-9-]*$ and is at most 64
#       characters. The topic names the brief file, the lock and the worker,
#       so nothing else ever reaches a path. The 64-character bound is a cap
#       rather than a limit anything downstream imposes: it keeps the brief
#       file, its lock and the request's `coordinate-<topic>` label short
#       (niwa cuts the session slug at 40 anyway).
#
#   dc_invocation <brief-input-file> [<return-path>]
#       Prints the worker's invocation: `/shirabe:<entry> <positional>
#       <run_mode flags> <entry_args flags>`, then `--review-floor=<x>` and
#       `--review-ceiling=<y>` from the input's `review_level` when it gives
#       them, then `--koto-leg=<return-path>` when a return path other than
#       `message` is given. The one place the invocation is built: the brief
#       shows it, the dispatch prompt carries it, and the holding's mode is
#       the run_mode and entry_args part of it, so the three can't disagree.
#
#   dc_mode <brief-input-file>
#       Prints the flags part of the invocation (run_mode, then entry_args
#       flags), the holding's `mode` cell. The review-level flags stay out of
#       it: a re-brief rebuilds run_mode from this cell and keeps the input's
#       review_level, so carrying them here would give them twice.
#
#   dc_unit_forms <pick-json-file>
#   dc_unit_matches <unit> <pick-json-file>
#       The Unit cell values pick_facts reads as covering a unit it listed
#       (coord/pick.json), and whether <unit> is one: a roadmap feature's tag
#       or `<tag>: <title>`, an issue's `#<n>` or `<host>#<n>`. A holding
#       written with any other value is invisible to pick.
#
#   dc_niwa_slug <topic>
#       Prints the slug niwa derives from `niwa dispatch --name <topic>`: the
#       name is lowercased, each run of characters outside [a-z0-9] becomes `_`, leading and trailing
#       `_` are trimmed, and the result is capped at 40 characters. The
#       worker's session name is this slug, `-`, and an 8-hex token. niwa
#       doesn't document the format yet (niwa#325), so it's pinned here and
#       in dispatch-common_test.sh.
#
#   dc_session_matches <topic> <session-name>
#       0 when the session name is exactly the topic's slug, `-`, and eight
#       lowercase hex digits. Never a prefix match: topic `api` doesn't match
#       `api_v2-` and its eight digits.
#
#   dc_find_session <workspace-root> <topic>
#       Prints `<session-name><TAB><instance-path>` for the topic's worker
#       from `niwa list --json` (run from the workspace root), matched with
#       dc_session_matches. Returns 0 found, 1 none, 2 when the listing can't
#       be read. NIWA overrides the binary.
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
#       Prints field n of the skill's row: 1 skill, 2 leg (or -), 3 admitted
#       templates, comma-joined (or -), 4 pinned inputs as VAR=source pairs
#       (or -), 5 allowed flags (or -), 6 the visibility its targets must have
#       (any, public or private), 7 the entry point to name instead (or -).
#       DC_F_LEG, DC_F_TEMPLATES, DC_F_PINNED, DC_F_FLAGS, DC_F_TARGET_VIS and
#       DC_F_INSTEAD name them.
#
#   dc_entry_target_visibility <skill>
#       Prints the visibility the skill's targets must have: `any`, `public`
#       or `private`. A row without the field reads as `any`; any other value
#       returns 2, so a malformed table never passes a dispatch.
#
#   dc_repo_visibility <owner/repo>
#       Prints `public` or `private`, read live from `gh api --method GET
#       repos/<r>`'s `visibility`, the read the merge gate's resolver makes;
#       `internal` and any other value print `private`. Returns 2, printing
#       nothing, when the read fails: a caller never guesses.
#
#   dc_flag_allowed <skill> <flag>
#       0 when the flag is in the skill's allowed set: an exact entry, or a
#       `<prefix>=*` entry and a flag of the form `<prefix>=<non-empty value>`.
#
#   dc_record_read <session> <topic>
#       Prints the topic's holding row as one JSON object. Returns 0 for a row,
#       1 for no row, 10 when the record refuses (no open record, or the run
#       log shows a directed transition), 2 for any other failure. It's the one
#       place a script reads a holding, so a change to the record's reader is
#       one edit here.
#
#   dc_rp_from_row <cell> / dc_rp_to_row <return-path>
#       A return path is `message` or `<request-id>:<leg>` inside these
#       scripts, and `message` or `leg <request-id>:<leg>` in the record's
#       Return path cell, the record codec's form. These convert between
#       the two; every read and write of a single cell goes through them
#       (wait-target.sh's jq filter over the whole list reads the same form).
#
#   dc_record_list <session>
#       Prints every holding row as one JSON array, in record order. Returns
#       0 (an empty array when there are none), 10 refused, 2 otherwise.
#
#   dc_record_write <session> <topic> <row-file>
#       Adds or replaces the topic's holding row whole. Returns the writer's
#       code: 0 written, 10 refused, 13 the record is full (record-full), 65
#       row refused, 2 otherwise. The
#       writer's 12 (the record changed under it) is retried up to
#       three times, then reads as a failed write.
#
#   The record's scripts belong to the record feature: record-holding.sh
#   ships with it, beside these scripts (it is not holding-recorded.sh, the
#   dispatch gate). It derives the record's scope, name, repository and reference from
#   the session's own log, so these pass the session and nothing else. When
#   it's absent, these return 2 and say so. DC_RECORD_HOLDING overrides its
#   path; tests use a stand-in.
#
#   dc_seal <session> <state> <verdict-file> <context-key>
#       Stores a check state's verdict in the context key through the record
#       feature's seal helper, coord-log.sh, and prints its
#       `sealed:<seq>:<sha256>` token, where seq is the state's latest entry
#       in the session log and the hash covers the session, state, seq and the
#       verdict's bytes. The helper ships with the record feature, like
#       record-holding.sh. DC_COORD_LOG overrides its path.
#
#   dc_seal_check <session> <state> <token> <context-key>
#       Prints the sealed verdict's bytes when the token still matches them and
#       the state's latest entry; returns 0 valid, 1 invalid, 2 read failure.
#
#   dc_capture <session> <name>
#       Prints a capture's latest value from the session's own log, so an
#       agent-run script never takes a sealed token as an argument.
#
#   dc_directed_since <session> <seq>
#       Returns 0 when the session log shows no directed transition (`koto
#       next --to`) since entry seq, 1 when it shows one, 2 on a read failure.
#
#   dc_with_deadline <seconds> <command...>
#       Runs the command and kills it once the deadline passes. Returns the
#       command's status, or 124 when the deadline killed it. `timeout` isn't
#       on macOS, whose /bin/bash is the floor these scripts target.

#   Exit codes across the dispatch scripts. A condition keeps its meaning
#   everywhere; the number a gate script uses is the one its state routes on:
#
#     record refused (no open record, failed provenance, or a directed
#     transition in the run log): 8 from dispatch-worker.sh, 10 from
#     wait-target.sh, 2 from the gates that read the record
#     (holding-recorded.sh, report-source.sh), which fold every read failure
#     into 2. teardown-verdict.sh reads no record: its gate mode's 2 is an
#     error verdict or a read that failed, 3 a seal that doesn't hold, and
#     its read mode's 4 a directed transition since the seal
#     usage: 2, except wait-target.sh (64), whose 0/1/2 are taken

DC_HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
DC_F_LEG=2
DC_F_TEMPLATES=3
DC_F_PINNED=4
DC_F_FLAGS=5
DC_F_TARGET_VIS=6
DC_F_INSTEAD=7
# koto's request-id grammar, and its leg-name grammar.
DC_RE_REQ='^[a-z0-9_][a-z0-9_-]{0,63}$'
DC_RE_LEG='^[A-Za-z0-9_][A-Za-z0-9_-]{0,63}$'
DC_ENTRY_POINTS="${DC_ENTRY_POINTS:-$DC_HERE/../references/entry-points.tsv}"
DC_RECORD_HOLDING="${DC_RECORD_HOLDING:-$DC_HERE/record-holding.sh}"
# The stored set's reader, for the pauses (record-state.sh --list); tests use
# a stand-in.
DC_RECORD_STATE="${DC_RECORD_STATE:-$DC_HERE/record-state.sh}"
DC_COORD_LOG="${DC_COORD_LOG:-$DC_HERE/coord-log.sh}"

# The dispatch topic's grammar, which a refusal names as the accepted values.
DC_RE_TOPIC='^[a-z0-9][a-z0-9-]*$'
DC_TOPIC_GRAMMAR="$DC_RE_TOPIC (at most 64 characters)"

dc_valid_topic() {
    case "$1" in
        '' | -*) return 1 ;;
    esac
    [ "${#1}" -le 64 ] || return 1
    [[ $1 =~ $DC_RE_TOPIC ]]
}

# dc_unit_forms <pick-json-file>: print, one per line, every Unit cell value
# that covers a unit pick_facts listed, by pick-facts.sh's own rule: a roadmap
# feature's heading tag or `<tag>: <title>`, an issue's `#<n>` or
# `<host>#<n>`, with the host pick_facts recorded; a unit a person assigned
# (its `assigned` set) by its id as the record names it, and `<host><id>` for
# an id that is `#<n>`. A landed unit (its roadmap
# pull request pending, `landed` set) has no form, so no brief for it renders.
# Returns 2 when the file isn't pick_facts' JSON. pick-facts_test.sh holds the
# two rules together.
dc_unit_forms() {
    jq -r '
        if (.units | type) != "array" then error("no units") else . end
        | .scope as $s | (.host // "") as $h | .units[] | select((.landed // null) == null)
        | if (.assigned // null) != null then .unit, (if $h != "" and (.unit | startswith("#")) then $h + .unit else empty end)
          elif $s == "roadmap" then .unit, (if (.title // "") == "" then empty else "\(.unit): \(.title)" end)
          else .unit, (if $h != "" then $h + .unit else empty end) end' "$1" 2>/dev/null || return 2
}

# dc_unit_matches <unit> <pick-json-file>: 0 when <unit> is a Unit cell value
# pick would read as covering one of the units it listed (dc_unit_forms), so
# a holding written with it is never invisible to pick; 1 when it isn't (an
# empty or multi-line unit never is); 2 when the file can't be read as
# pick_facts' JSON.
dc_unit_matches() {
    local forms
    forms=$(dc_unit_forms "$2") || return 2
    case "$1" in '' | *'
'*) return 1 ;; esac
    printf '%s\n' "$forms" | grep -Fxq -- "$1"
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

DC_JQ_TOKENS='
    ([.entry_args[0]] + ((.run_mode // "") | split(" ") | map(select(. != ""))) + (.entry_args[1:]))'

dc_mode() {
    jq -r "$DC_JQ_TOKENS"' | .[1:] | join(" ")' "$1"
}

dc_invocation() {
    local inv
    inv=$(jq -r "$DC_JQ_TOKENS"' as $t
        | ($t[0] | if test("\\s") then "\"" + . + "\"" else . end) as $pos
        | (if (.review_level | type) == "object" then
             ([ (.review_level.floor // empty | strings | "--review-floor=" + .),
                (.review_level.ceiling // empty | strings | "--review-ceiling=" + .) ])
           else [] end) as $bound
        | "/shirabe:" + .entry_point + " " + ([$pos] + $t[1:] + $bound | join(" "))' "$1") || return 2
    case "${2:-message}" in
        message) ;;
        *) inv="$inv --koto-leg=$2" ;;
    esac
    printf '%s\n' "$inv"
}

dc_find_session() {
    local list name path
    list=$(cd "$1" && "${NIWA:-niwa}" list --json) || return 2
    printf '%s' "$list" | jq -e 'type == "array"' >/dev/null || return 2
    while IFS='	' read -r name path; do
        [ -n "$name" ] || continue
        if dc_session_matches "$2" "$name"; then
            printf '%s\t%s\n' "$name" "$path"
            return 0
        fi
    done <<EOF
$(printf '%s' "$list" | jq -r '.[] | select((.session_name | type) == "string") | [.session_name, (.path // "")] | @tsv')
EOF
    return 1
}

dc_workspace_root() {
    local d
    d=$(cd "${1:-.}" 2>/dev/null && pwd -P) || return 2
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

dc_entry_target_visibility() {
    local v
    v=$(dc_entry_field "$1" "$DC_F_TARGET_VIS") || return $?
    case "$v" in
        '' | any) printf 'any\n' ;;
        public | private) printf '%s\n' "$v" ;;
        *) return 2 ;;
    esac
}

dc_repo_visibility() {
    local json v
    json=$(gh api --method GET "repos/$1" </dev/null) || return 2
    v=$(printf '%s' "$json" | jq -r 'if type == "object" then (.visibility // "") else "" end') || return 2
    case "$v" in
        public) printf 'public\n' ;;
        '') return 2 ;;
        *) printf 'private\n' ;;
    esac
}

dc_flag_allowed() {
    local flags f
    flags=$(dc_entry_field "$1" "$DC_F_FLAGS") || return 1
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

dc_rp_from_row() {
    case "$1" in
        'leg '*) printf '%s\n' "${1#leg }" ;;
        *) printf '%s\n' "$1" ;;
    esac
}

dc_rp_to_row() {
    case "$1" in
        message | '') printf '%s\n' "${1:-message}" ;;
        *) printf 'leg %s\n' "$1" ;;
    esac
}

dc_record_present() {
    [ -f "$DC_RECORD_HOLDING" ] && return 0
    printf 'dispatch-common: the record feature'"'"'s record-holding.sh is not installed at %s\n' "$DC_RECORD_HOLDING" >&2
    return 2
}

dc_record_read() {
    dc_record_present || return 2
    local out rc
    out=$(bash "$DC_RECORD_HOLDING" --read --topic "$2" --session "$1")
    rc=$?
    case "$rc" in
        0)
            printf '%s' "$out" | jq -e 'type == "object"' >/dev/null || return 2
            printf '%s\n' "$out"
            return 0
            ;;
        1 | 10) return "$rc" ;;
        *) return 2 ;;
    esac
}

dc_record_list() {
    dc_record_present || return 2
    local out rc
    out=$(bash "$DC_RECORD_HOLDING" --list --session "$1")
    rc=$?
    case "$rc" in
        0)
            printf '%s' "$out" | jq -e 'type == "array"' >/dev/null || return 2
            printf '%s\n' "$out"
            return 0
            ;;
        10) return 10 ;;
        *) return 2 ;;
    esac
}

dc_record_write() {
    dc_record_present || return 2
    # A write prints the record's URL; it goes to stderr so a caller's stdout
    # stays its own answer.
    # Exit 12 is the record changing between the writer's read and its write
    # (another writer got there first): the write is retried, a bounded number
    # of times, and a record that keeps changing is a failed write.
    local rc tries=0
    while :; do
        bash "$DC_RECORD_HOLDING" --topic "$2" --row-file "$3" --session "$1" >&2
        rc=$?
        [ "$rc" = 12 ] || break
        tries=$((tries + 1))
        [ "$tries" -lt 3 ] || break
    done
    case "$rc" in
        0 | 10 | 13 | 65) return "$rc" ;;
        *) return 2 ;;
    esac
}

dc_coord_log_present() {
    [ -f "$DC_COORD_LOG" ] && return 0
    printf 'dispatch-common: the record feature'"'"'s coord-log.sh is not installed at %s\n' "$DC_COORD_LOG" >&2
    return 2
}

dc_seal() {
    dc_coord_log_present || return 2
    local token
    token=$(bash "$DC_COORD_LOG" seal --session "$1" --state "$2" --file "$3" --key "$4") || return 2
    printf '%s' "$token" | grep -Eq '^sealed:[0-9]+:[0-9a-f]{64}$' || return 2
    printf '%s\n' "$token"
}

dc_seal_check() {
    dc_coord_log_present || return 2
    bash "$DC_COORD_LOG" check --session "$1" --state "$2" --sealed "$3" --key "$4"
    case "$?" in
        0) return 0 ;;
        1) return 1 ;;
        *) return 2 ;;
    esac
}

dc_capture() {
    dc_coord_log_present || return 2
    bash "$DC_COORD_LOG" capture --session "$1" --name "$2"
}

dc_directed_since() {
    dc_coord_log_present || return 2
    bash "$DC_COORD_LOG" directed-since --session "$1" --from "$2" >/dev/null
    case "$?" in
        0) return 0 ;;
        1) return 1 ;;
        *) return 2 ;;
    esac
}

dc_with_deadline() {
    local secs="$1" pid watcher rc mark
    shift
    mark=$(mktemp "${TMPDIR:-/tmp}/dc-deadline.XXXXXX") || return 2
    rm -f "$mark"
    "$@" &
    pid=$!
    # The watcher runs its sleep in the background and waits on it, so the
    # TERM that stops the watcher also stops the sleep (a foreground sleep
    # would outlive it). Its streams go nowhere, so nothing it leaves holds a
    # caller's $(...) pipe open.
    # The trap goes in before the sleep starts: a command that finishes at
    # once can stop the watcher before it would otherwise have installed one.
    # A TERM that lands before `sp` is set (the sleep may already be running)
    # only records the stop, and the line after the assignment acts on it, so
    # no sleep is left behind in that window either.
    (
        sp=""
        stop=""
        trap 'stop=1; if [ -n "$sp" ]; then kill -TERM "$sp" >/dev/null 2>&1; exit 0; fi' TERM
        sleep "$secs" &
        sp=$!
        if [ -n "$stop" ]; then kill -TERM "$sp" >/dev/null 2>&1; exit 0; fi
        if wait "$sp" && kill -TERM "$pid" >/dev/null 2>&1; then
            : >"$mark"
        fi
    ) </dev/null >/dev/null 2>&1 &
    watcher=$!
    wait "$pid"
    rc=$?
    kill -TERM "$watcher" >/dev/null 2>&1
    wait "$watcher" >/dev/null 2>&1
    if [ -e "$mark" ]; then
        rm -f "$mark"
        return 124
    fi
    return "$rc"
}
