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
#   dc_opener <brief-input-file>
#       Prints, tab-separated, how a message-path worker records the
#       coordinator run that dispatched it, and the exact command, with
#       `--dispatched-by <dispatcher_session>` filled in from the input:
#         open   the entry point's own opener with the flag, run in place of
#                the open its skill shows: coordinate-open.sh for
#                /coordinate (`"$ARGS_DIR/args.json"` as its step writes
#                it), `skill-session.sh open <entry> <topic>` for /explore,
#                /decision and /release (`<topic>` the one the entry point
#                derives)
#         link   link-dispatcher.sh `<session>`, run once the entry point has
#                opened its session (`<session>` that session), for /scope,
#                /deliver, /execute and /work-on, whose openers take a
#                dispatcher only through a request leg
#       The commands start from "${CLAUDE_PLUGIN_ROOT}", as the skills' own
#       commands do. Returns 1 when dispatcher_session isn't a koto session
#       name, which render-brief.sh refuses first.
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
#   dc_find_session <workspace-root> <topic> [<row-file>]
#       Prints `<session-name><TAB><instance-path>` for the topic's worker
#       from `niwa list --json` (run from the workspace root), matched with
#       dc_session_matches. Returns 0 found, 1 none, 2 when the listing can't
#       be read. NIWA overrides the binary. With <row-file>, a match also
#       writes its listing row there as one JSON object (its dispatch_id is
#       the worker's niwa dispatch id), from the same read; a row that can't
#       be written leaves no file and changes nothing else.
#
#   dc_scope_slug <session>
#       Prints the scope slug a coordinator run's session name carries
#       (`coordinate-<scope slug>-<UTC stamp>`), or nothing, returning 1,
#       when the name isn't one. Reads nothing.
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
#       Return path cell, state-schema.jq's form. These convert between
#       the two; every read and write of a single cell goes through them
#       (wait-target.sh's jq filter over the whole list reads the same form).
#
#   dc_leg_key <request> <leg>
#       Prints the context key that holds one worker leg in the coordinator's
#       own koto session: legs/<request>/<leg> (PRD R13). The session holds it
#       whichever store the record is on, so an import or a carry moves a
#       run's legs with its session.
#
#   dc_leg_get <session> <request> <leg>
#       Prints the leg key's JSON object. Returns 0 read, 1 no such key, 2 a
#       failed read or a value that isn't a JSON object. Presence comes from
#       a listing, so an absent key and a failed read stay apart: `context
#       get` fails the same way for both, and `context exists` on koto's
#       cloud backend retries an absent key's 404 for about a second
#       (state-read.sh rs_list).
#
#   dc_leg_put <session> <request> <leg> <json>
#       Writes the leg key whole. Returns 0, or 2 when the value isn't a JSON
#       object naming that request and leg, or the write fails.
#
#   A leg key is {request, leg, topic, state, templates, inputs}, and as they
#   become known child (the bound session's name as koto reported it), result
#   (koto's result for the leg, once read), new_request (a re-leg's new
#   request) and from (the request a re-legged key replaced). templates and
#   inputs are the leg's declaration at dispatch. state is one of:
#     open           dispatched on this leg; no result read yet
#     taken          wait-target.sh read its result, kept beside it
#     spent          it ended with no result its worker promoted
#     replaced       a new leg replaced it on this host (--releg, an
#                    execution sent)
#     releg-pending  an import's re-leg opened new_request and hasn't finished
#     relegged       the re-leg finished: the holding names new_request
#     unwatchable    after an import its worker can't be watched from this
#                    host, and the holding reports by message
#
#   dc_record_list <session>
#       Prints every holding row as one JSON array, in record order. Returns
#       0 (an empty array when there are none), 10 refused, 2 otherwise.
#
#   dc_record_write <session> <topic> <row-file>
#       Adds or replaces the topic's holding row whole. Returns the writer's
#       code: 0 written, 10 refused, 65 row refused, 2 otherwise. The
#       writer's 12 (the record changed under it) is retried up to
#       three times, then reads as a failed write.
#
#   The record's scripts belong to the record feature: state-holding.sh
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
#       state-holding.sh. DC_COORD_LOG overrides its path.
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
#       command's status, or 124 once the deadline has passed and the command
#       didn't exit 0: a command that exits 0 as the deadline's TERM lands, or
#       from its own TERM trap, keeps its 0, and one that fails just as the
#       deadline passes reads as 124. No process it starts to keep the
#       deadline is still running once it returns, unless its watcher won't
#       stop within about five seconds: the watcher is then killed and the
#       call returns, leaving the watcher's sleep to run out. `timeout` isn't
#       on macOS, whose /bin/bash is the floor these scripts target.
#       The deadline's TERM reaches only the command's own pid; a command
#       whose children must stop with it runs through dc_tree.
#       The watcher is sent no TERM until it is ready, so a caller's EXIT and
#       TERM traps don't run in it (bash 5 would otherwise run them there).
#
#   dc_tree <command...>
#       Runs the command in a process group of its own and waits for it. A
#       TERM to dc_tree (dc_with_deadline's) is passed to the whole group, so
#       `dc_with_deadline <secs> dc_tree <command...>` stops the command's
#       children too, such as the remote helper `git ls-remote` starts.
#       It sets a TERM trap and toggles `set -m` in the shell that runs it,
#       so it runs in a subshell of its own, as dc_with_deadline's command
#       does, never in a caller's shell.
#
#   dc_job_finished <claude-home> <job-id> <listing-row-json>
#       0 when the Claude Code background job is finished, by evidence that
#       still means it: its own <claude-home>/jobs/<id>/state.json reads
#       `state` done, stopped or failed, and its `claude agents --json --all`
#       row shows no pid, or a pid no process holds (`kill -0` and `ps -p`
#       both find none). The row's `state` is activity, not lifecycle, and
#       isn't read: Claude Code 2.1.309 lists every job as `working`, a
#       stopped one included. Otherwise 1, printing why: a job id that isn't
#       one (it never reaches a path), a row that isn't a JSON object, a pid
#       that isn't one, a live pid, or a state file that is missing, isn't
#       JSON, reads `working` or reads anything else. A caller about to
#       remove a job refuses on 1; a wrong answer here only refuses.
#
#   dc_claude_job <claude-home> <claude-session-id> [<session-name>]
#       Prints the id of the Claude Code job on this host whose
#       <claude-home>/jobs/<id>/state.json names the Claude session by its
#       `sessionId`, or, when no job does and a name is given, by its `name`.
#       Returns 0 found, 1 none (no jobs directory, an id or a name that
#       isn't one, or no state file names it).
#
#   dc_claude_name <claude-home> <claude-session-id>
#       Prints the `name` the session's job state file gives it: its
#       messaging address. Returns 0; 1 when no job names the session or its
#       name isn't a session name.
#
#   dc_session_live <koto-session> <claude-session-id> <session-name>
#       The liveness probe: 0 when the koto session is live by the
#       coordinator's definition, 1 when it isn't, printing why either way; 2
#       when its log can't be read. Live is: not finished or cancelled in
#       koto, and either a running Claude job on this host for the Claude
#       session that drives it (its job found by dc_claude_job, by id or by
#       name, and dc_job_finished saying it isn't finished), or, when no job
#       for it can be seen from here, a koto event in its log within the last
#       10 minutes (600 seconds). Either argument after the koto session may
#       be empty. The koto session may be empty too, for a worker whose koto
#       session can't be found: then only its Claude job decides, and with no
#       job seen from here there is no event to read, so it isn't live.
#       DC_CLAUDE_HOME (default $HOME/.claude) and DC_NOW (epoch seconds,
#       default the host clock) move the job directory and the clock, for
#       tests.
#
#   dc_newest_member <koto-session>
#       Follows `session_superseded` events forward from the session (each
#       names the run that continued it, koto init --continues --supersede)
#       and prints the newest member of its chain, the session itself when
#       nothing superseded it, then a tab and the hops taken. Each name is
#       checked against a koto session name's grammar before it is read, and
#       a name met twice ends the walk. Returns 0 found; 1 the chain can't be
#       read (a log that can't be read, a name that isn't one, a cycle); 3 the
#       walk passed its hop cap, DC_HOP_CAP (default 1024, about six months of
#       recycles), printing nothing.

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
# A koto session name, as a leg's bound child is recorded.
DC_RE_SESSION='^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$'
# A coordinator run's session name, its scope slug captured.
DC_RE_COORD_SLUG='^coordinate-([a-z0-9-]+)-[0-9]{8}T[0-9]{6}Z$'
DC_ENTRY_POINTS="${DC_ENTRY_POINTS:-$DC_HERE/../references/entry-points.tsv}"
DC_RECORD_HOLDING="${DC_RECORD_HOLDING:-$DC_HERE/state-holding.sh}"
# The stored set's reader, for the pauses (state-stored-set.sh --list); tests use
# a stand-in.
DC_RECORD_STATE="${DC_RECORD_STATE:-$DC_HERE/state-stored-set.sh}"
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
# pull request pending, `landed` set) has no form, so no brief for it renders,
# and neither has a milestone whose verdict is owed (`verdict_owed` true).
# Returns 2 when the file isn't pick_facts' JSON. pick-facts_test.sh holds the
# two rules together.
dc_unit_forms() {
    jq -r '
        if (.units | type) != "array" then error("no units") else . end
        | .scope as $s | (.host // "") as $h | .units[] | select((.landed // null) == null and (.verdict_owed // false) != true)
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
    grep -Fxq -- "$1" <<<"$forms"
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
    grep -Eq '^[0-9a-f]{8}$' <<<"${2#"$slug"-}"
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

dc_opener() {
    local entry d root='${CLAUDE_PLUGIN_ROOT}'
    entry=$(jq -r '.entry_point // "" | strings' "$1") || return 2
    d=$(jq -r '.dispatcher_session // "" | strings' "$1") || return 2
    { [ "${#d}" -le 200 ] && [[ $d =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]]; } || return 1
    case "$entry" in
        coordinate)
            printf 'open\t"%s/skills/coordinate/scripts/coordinate-open.sh" --plugin-root "%s" --dispatched-by %s "$ARGS_DIR/args.json"\n' "$root" "$root" "$d" ;;
        explore | decision | release)
            printf 'open\t"%s/scripts/skill-session.sh" open %s <topic> --dispatched-by %s\n' "$root" "$entry" "$d" ;;
        *)
            printf 'link\t"%s/skills/coordinate/scripts/link-dispatcher.sh" <session> --dispatched-by %s\n' "$root" "$d" ;;
    esac
}

dc_find_session() {
    local list name path
    list=$(cd "$1" && "${NIWA:-niwa}" list --json) || return 2
    printf '%s' "$list" | jq -e 'type == "array"' >/dev/null || return 2
    while IFS='	' read -r name path; do
        [ -n "$name" ] || continue
        if dc_session_matches "$2" "$name"; then
            if [ -n "${3-}" ]; then
                printf '%s' "$list" | jq -c --arg n "$name" '[.[] | select(.session_name == $n)][0] // empty' >"$3" 2>/dev/null ||
                    rm -f "$3"
            fi
            printf '%s\t%s\n' "$name" "$path"
            return 0
        fi
    done <<EOF
$(printf '%s' "$list" | jq -r '.[] | select((.session_name | type) == "string") | [.session_name, (.path // "")] | @tsv')
EOF
    return 1
}

dc_scope_slug() {
    [[ $1 =~ $DC_RE_COORD_SLUG ]] || return 1
    printf '%s\n' "${BASH_REMATCH[1]}"
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

DC_RE_LEG_STATE='^(open|taken|spent|replaced|releg-pending|relegged|unwatchable)$'

dc_leg_key() { printf 'legs/%s/%s\n' "$1" "$2"; }

dc_leg_get() {
    local key out
    key=$(dc_leg_key "$2" "$3")
    out=$("${KOTO:-koto}" context list "$1" --prefix "$key" </dev/null) || return 2
    jq -e --arg k "$key" 'type == "array" and index($k) != null' <<<"$out" >/dev/null
    case "$?" in
        0) ;;
        1) return 1 ;;
        *) return 2 ;;
    esac
    out=$("${KOTO:-koto}" context get "$1" "$key" </dev/null) || return 2
    jq -e 'type == "object"' <<<"$out" >/dev/null || return 2
    printf '%s\n' "$out"
}

dc_leg_put() {
    local key
    key=$(dc_leg_key "$2" "$3")
    jq -e --arg r "$2" --arg l "$3" --arg re "$DC_RE_LEG_STATE" \
        'type == "object" and .request == $r and .leg == $l and ((.state // "") | test($re))' <<<"$4" >/dev/null || return 2
    jq -c . <<<"$4" | "${KOTO:-koto}" context add "$1" "$key" >/dev/null || return 2
}

dc_record_present() {
    [ -f "$DC_RECORD_HOLDING" ] && return 0
    printf 'dispatch-common: the record feature'"'"'s state-holding.sh is not installed at %s\n' "$DC_RECORD_HOLDING" >&2
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
    grep -Eq '^sealed:[0-9]+:[0-9a-f]{64}$' <<<"$token" || return 2
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
    local secs="$1" pid watcher rc mark tries=0
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
    # The ready mark goes down right after the trap, never before it: the
    # caller sends no TERM until it sees the mark (see the wait below).
    # A TERM that lands before `sp` is set (the sleep may already be running)
    # only records the stop, and the line after the assignment acts on it, so
    # no sleep is left behind in that window either.
    # The sleep is stopped with KILL, not TERM: until the forked child execs
    # sleep it still runs the watcher's TERM trap, so a TERM landing in that
    # window is caught and dropped and the sleep runs its full length. The
    # watcher then waits on the sleep, so it is gone before the watcher exits
    # and so before the caller's wait on the watcher returns. The trap's first
    # act is to ignore further TERMs: the caller repeats its TERM, and one
    # landing during that wait would cut the wait short.
    (
        sp=""
        stop=""
        trap 'trap "" TERM; stop=1; if [ -n "$sp" ]; then kill -KILL "$sp" >/dev/null 2>&1; wait "$sp"; exit 0; fi' TERM
        : >"$mark.ready"
        sleep "$secs" &
        sp=$!
        if [ -n "$stop" ]; then kill -KILL "$sp" >/dev/null 2>&1; wait "$sp"; exit 0; fi
        # The mark goes down before the kill: the caller stops this watcher
        # with TERM as soon as the command ends, and a mark written after the
        # kill could be cut off by that TERM, so a deadline that passed would
        # read as the killed command's 143.
        if wait "$sp"; then
            : >"$mark"
            kill -TERM "$pid" >/dev/null 2>&1
        fi
    ) </dev/null >/dev/null 2>&1 &
    watcher=$!
    wait "$pid"
    rc=$?
    # No TERM goes to the watcher until it has marked itself ready. bash 5
    # runs a parent's traps in a subshell it has just forked when a signal
    # lands before the subshell has run its first command, so a TERM sent the
    # moment a quick command ended could run the caller's EXIT or TERM trap
    # in the watcher (an EXIT trap that removes a temporary directory then
    # removes it mid-run). The mark also means the TERM can't arrive while the
    # watcher's own trap is going in. The wait spins on builtins for the
    # millisecond or two a fork takes, then polls 0.01s apart, and gives up
    # after about a second or as soon as the watcher is gone, so it can't hold
    # the call; the TERM then goes out as before.
    while [ ! -e "$mark.ready" ] && [ "$tries" -lt 1000 ] && kill -0 "$watcher" >/dev/null 2>&1; do
        tries=$((tries + 1))
    done
    tries=0
    while [ ! -e "$mark.ready" ] && [ "$tries" -lt 100 ] && kill -0 "$watcher" >/dev/null 2>&1; do
        sleep 0.01
        tries=$((tries + 1))
    done
    tries=0
    # The loops below are for a watcher the wait gave up on: bash ignores a
    # signal while `trap` installs its handler, so a TERM that lands as the
    # watcher sets its trap is lost, and the watcher would run to the
    # deadline. A watcher that got the TERM is gone within a millisecond or
    # two, so the first loop only checks for it, with the builtin kill -0,
    # and spawns nothing. One still there after that gets the TERM again
    # until it is gone: 100 tries 0.05s apart, about five seconds. A watcher
    # still there after that is killed outright, so the call always returns;
    # a sleep it had started is then left to run out on its own, and nothing
    # is reported. bash prints a job's "Terminated" notice when it reaps the
    # watcher between the loops' commands, so their stderr goes nowhere, as
    # the wait's does.
    kill -TERM "$watcher" >/dev/null 2>&1
    {
        while [ "$tries" -lt 500 ] && kill -0 "$watcher" >/dev/null 2>&1; do
            tries=$((tries + 1))
        done
        tries=0
        while [ "$tries" -lt 100 ] && kill -0 "$watcher" >/dev/null 2>&1; do
            sleep 0.05
            kill -TERM "$watcher" >/dev/null 2>&1
            tries=$((tries + 1))
        done
    } 2>/dev/null
    if kill -0 "$watcher" >/dev/null 2>&1; then
        kill -KILL "$watcher" >/dev/null 2>&1
    fi
    wait "$watcher" >/dev/null 2>&1
    # The watcher is gone, so nothing writes the ready mark after this.
    rm -f "$mark.ready"
    # Past the deadline, a command that still exited 0 (as the TERM landed, or
    # from its own TERM trap) keeps its 0; any other status is the deadline's.
    if [ -e "$mark" ]; then
        rm -f "$mark"
        [ "$rc" -eq 0 ] || return 124
    fi
    return "$rc"
}

# dc_with_deadline TERMs only its direct child, which would leave the
# command's own children running; `set -m` is here only to give the command
# its own process group, so `kill -- -<pid>` reaches all of it. The trap kills
# and returns; it never waits on a child.
# shellcheck disable=SC2329 # run through dc_with_deadline's "$@"
dc_tree() {
    local p
    set -m 2>/dev/null
    "$@" &
    p=$!
    set +m 2>/dev/null
    trap 'kill -TERM -- "-$p" >/dev/null 2>&1; kill -TERM "$p" >/dev/null 2>&1; exit 143' TERM
    wait "$p"
}

dc_job_finished() {
    local home="$1" job="$2" row="$3" pid f st
    if ! grep -Eq '^[0-9a-f]{6,64}$' <<<"$job"; then
        printf 'the job id [%s] is not a job id\n' "$job"
        return 1
    fi
    pid=$(printf '%s' "$row" | jq -r 'if type != "object" then error("not an object")
        elif .pid == null then "" else .pid | tostring end' 2>/dev/null) || {
        printf 'the listing row for job %s is not a JSON object\n' "$job"
        return 1
    }
    if [ -n "$pid" ]; then
        if ! grep -Eq '^[1-9][0-9]{0,9}$' <<<"$pid"; then
            printf 'job %s lists pid [%s], which is not a pid\n' "$job" "$pid"
            return 1
        fi
        # kill -0 fails on a live process another user owns, so ps has the
        # last word: the pid is dead only when neither finds it.
        if kill -0 "$pid" 2>/dev/null || ps -p "$pid" >/dev/null 2>&1; then
            printf 'job %s is still running (pid %s)\n' "$job" "$pid"
            return 1
        fi
    fi
    f="$home/jobs/$job/state.json"
    if [ ! -f "$f" ]; then
        printf 'job %s has no state file at %s\n' "$job" "$f"
        return 1
    fi
    st=$(jq -r '.state // "" | strings' "$f") || {
        printf 'the state file of job %s is not readable JSON\n' "$job"
        return 1
    }
    case "$st" in
        done | stopped | failed) return 0 ;;
        working) printf 'the state file of job %s reads working\n' "$job" ;;
        *) printf "the state file of job %s reads [%s], which isn't known to be finished\n" "$job" "$st" ;;
    esac
    return 1
}

dc_claude_job() {
    local home="$1" sid="$2" name="${3-}" f
    [ -d "$home/jobs" ] || return 1
    if grep -Eq '^[0-9a-f][0-9a-f-]{7,63}$' <<<"$sid"; then
        for f in "$home"/jobs/*/state.json; do
            [ -f "$f" ] || continue
            [ "$(jq -r '.sessionId // "" | strings' "$f" 2>/dev/null)" = "$sid" ] || continue
            f=${f%/state.json}; printf '%s\n' "${f##*/}"; return 0
        done
    fi
    [[ $name =~ $DC_RE_SESSION ]] || return 1
    for f in "$home"/jobs/*/state.json; do
        [ -f "$f" ] || continue
        [ "$(jq -r '.name // "" | strings' "$f" 2>/dev/null)" = "$name" ] || continue
        f=${f%/state.json}; printf '%s\n' "${f##*/}"; return 0
    done
    return 1
}

dc_claude_name() {
    local home="$1" job name
    job=$(dc_claude_job "$home" "$2") || return 1
    name=$(jq -r '.name // "" | strings' "$home/jobs/$job/state.json" 2>/dev/null) || return 1
    [[ $name =~ $DC_RE_SESSION ]] || return 1
    printf '%s\n' "$name"
}

dc_session_live() {
    local s="$1" sid="$2" name="$3" home="${DC_CLAUDE_HOME:-$HOME/.claude}" now="${DC_NOW:-$(date +%s)}" st log job why last at
    if [ -z "$s" ]; then
        job=$(dc_claude_job "$home" "$sid" "$name") \
            || { printf 'no koto session and no Claude job for %s is seen here\n' "${name:-$sid}"; return 1; }
        if why=$(dc_job_finished "$home" "$job" '{}'); then
            printf "%s's Claude job %s has finished\n" "${name:-$sid}" "$job"; return 1
        fi
        printf '%s is a running Claude job: %s\n' "${name:-$sid}" "$why"; return 0
    fi
    st=$("${KOTO_BIN:-koto}" status "$s" </dev/null 2>/dev/null) || { printf '%s has no readable status\n' "$s"; return 2; }
    if [ "$(printf '%s' "$st" | jq -r '.is_terminal')" != false ]; then
        printf '%s is finished\n' "$s"; return 1
    fi
    log="$("${KOTO_BIN:-koto}" session dir "$s" </dev/null 2>/dev/null)/koto-$s.state.jsonl"
    [ -r "$log" ] || { printf "%s's log can't be read\n" "$s"; return 2; }
    if jq -e 'select(.type == "workflow_cancelled")' "$log" >/dev/null 2>&1; then
        printf '%s is cancelled\n' "$s"; return 1
    fi
    if job=$(dc_claude_job "$home" "$sid" "$name"); then
        # A job seen from here decides: only its own state file and pid say
        # whether it is still running.
        if why=$(dc_job_finished "$home" "$job" '{}'); then
            printf "%s's Claude job %s has finished\n" "$s" "$job"; return 1
        fi
        printf '%s is driven by a running Claude job: %s\n' "$s" "$why"; return 0
    fi
    last=$(tail -n 1 "$log" | jq -r '.timestamp // empty' 2>/dev/null)
    [ -n "$last" ] || { printf "%s's log has no timed event\n" "$s"; return 2; }
    at=$(jq -rn --arg t "$last" '$t | sub("\\.[0-9]+Z$"; "Z") | fromdateiso8601' 2>/dev/null) \
        || { printf "%s's last event time [%s] can't be read\n" "$s" "$last"; return 2; }
    if [ $((now - at)) -le 600 ]; then
        printf "no Claude job for %s is seen here, and its last koto event is %ss old\n" "$s" "$((now - at))"; return 0
    fi
    printf "no Claude job for %s is seen here, and its last koto event is %ss old, past 10 minutes\n" "$s" "$((now - at))"
    return 1
}

dc_newest_member() {
    local s="$1" cap="${DC_HOP_CAP:-1024}" hops=0 seen=" " dir log next
    [[ $s =~ $DC_RE_SESSION ]] || return 1
    while :; do
        case "$seen" in *" $s "*) return 1 ;; esac
        seen="$seen$s "
        dir=$("${KOTO_BIN:-koto}" session dir "$s" </dev/null 2>/dev/null) || return 1
        log="$dir/koto-$s.state.jsonl"
        [ -r "$log" ] || return 1
        # The last supersede event, should a run carry more than one.
        next=$(jq -r 'select(.type == "session_superseded") | .payload.by // "" | strings' "$log" 2>/dev/null | tail -n 1) || return 1
        if [ -z "$next" ]; then
            printf '%s\t%s\n' "$s" "$hops"
            return 0
        fi
        [[ $next =~ $DC_RE_SESSION ]] || return 1
        [ "$hops" -lt "$cap" ] || return 3
        hops=$((hops + 1))
        s=$next
    done
}
