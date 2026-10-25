#!/usr/bin/env bash
# coord-log.sh -- read a /coordinate session's koto log: seal a check's verdict
# to the visit that produced it, check a seal, read an engine-written capture,
# find directed transitions, and derive the run's facts.
#
# Every check state in coordinate.md runs a script that prints one verdict
# token, sealed with `seal`, which the engine captures. A capture is written
# only by the engine, so a gate that reads it in the same advance reads the
# check's own answer. The seal ties that answer to one visit (the sequence
# number of the log's entry into the state), which is what lets a later reader
# refuse a capture left over from an earlier visit. The seal's hash has no key
# and covers only what the coordinator can read, so it is a consistency check,
# not a secret: what makes a seal trustworthy is that readers take it from the
# log themselves, never from an argument the coordinator passes.
#
# `koto next --to` could move a session past a gate before koto 0.14.0 (koto#251); `directed-since`
# is how every write script detects that and refuses.
#
# Usage:
#   coord-log.sh seal --session S --state ST (--token T | --file F --key K)
#       --token: prints "T sealed:<seq>:<sha256>".
#       --file/--key: stores F's bytes in context key K, prints "sealed:<seq>:<sha256>".
#       Exit 0 sealed; 2 no readable log or no entry into ST; 66 koto context failed.
#   coord-log.sh check --session S --state ST --sealed V [--key K] [--any-visit]
#       Exit 0 valid (with --key, prints the verified context bytes); 1 invalid
#       (hash mismatch, another session's or state's seal, a visit that isn't
#       the latest entry into ST unless --any-visit, unsealed input); 2 read failure.
#   coord-log.sh capture --session S --name N [--for KEY] [--state ST [--any-visit]]
#       Prints the latest engine-written value of capture N (with --for, the
#       latest whose second word is KEY). With --state, the value is printed only
#       when its seal checks against ST: sealed at the latest entry into ST, or
#       with --any-visit at any real entry (a per-unit read, where later visits
#       concern other units). Exit 0 found; 1 absent or its seal fails; 2 read
#       failure.
#   coord-log.sh directed-since --session S --from SEQ
#       Prints "seq from->to" per directed transition after SEQ. Exit 0 none;
#       1 some; 2 read failure.
#   coord-log.sh run-facts --session S
#       Prints {"scope","name","repo"}. Exit 0; 1 no found record in the run
#       (the find's sealed token is `found`, the run's own session holding the
#       record, or at discipline scope `first` or `predecessor
#       coordinate-<slug>-<stamp>`, the rotation record_open or
#       predecessor_carry puts there); 2 read failure.
#   coord-log.sh run-start --session S       Prints the header's created_at.
#   coord-log.sh chain-start --session S
#       Prints the created_at of the earliest run in the unbroken chain of
#       cancelled runs of S's scope just before S, or S's own created_at when
#       the run just before it wasn't cancelled. coordinate-open.sh cancels
#       the live run it replaces, so the chain is the restarts that led to S
#       (a run a person cancelled by hand counts the same way). A run that
#       ended at a terminal state (a handover, a finish), is no longer
#       listed, or whose log can't be read ends it, which only makes the
#       chain shorter; so does a name that isn't
#       coordinate-<slug>-<UTC stamp>. Exit 0; 2 S's own log can't be read.
#   coord-log.sh provenance --session S [--template PATH]
#       Exit 0 when the session's template is one this plugin can drive and
#       its PLUGIN_ROOT, as koto applies it now (the value it opened with,
#       folded with every rebind), is this script's plugin root; 1 otherwise;
#       2 read failure. A template this plugin can drive is one whose
#       structure (template-fingerprint.jq over the compiled copy koto runs
#       the session from) the compat table beside the shipped template
#       (coordinate.compat.json) lists at the table's compat number, or the
#       shipped template itself: one that
#       compiles today to the header's template_hash, or (the plugin rewritten
#       in place since the run opened) the template koto compiled the run from
#       by its own path, when the compiled copy koto runs it from still hashes
#       to template_hash. --template is for tests that run a localized copy;
#       its table is the .compat.json beside it.
#   coord-log.sh compat --session S [--template PATH]
#       Prints "<run's compat> <shipped compat> <run's fingerprint>" from the
#       compat table, the run's compat `-` when the table doesn't list its
#       template's structure (the fingerprint `unreadable` when the compiled
#       copy the run runs from can't be read).
#       Exit 0 when the run's compat is the shipped one; 1 otherwise; 2 the log
#       or the table can't be read.
#   coord-log.sh plugin-root --session S
#       Prints {"root","rebind"}: the run's PLUGIN_ROOT as koto applies it now,
#       and whether the compiled template the run runs from declares it
#       rebindable (so `koto init --attach-live` can move it). Exit 0; 2 read
#       failure.
#   coord-log.sh template-hash --session S
#       Prints the template_hash in S's header, the hash of the template koto
#       compiled the run from, which a resume compares with the shipped
#       template's (provenance passes a run whose plugin was rewritten in place
#       since, so it can't tell). Exit 0; 1 the header has none; 2 S's log can't
#       be read.
#   coord-log.sh live-session --scope-slug SLUG [--all]
#       Prints the one live coordinate-SLUG-* session. Exit 0; 1 none; 3 several.
#       With --all, prints every live one, one per line. Exit 0; 1 none.
#   coord-log.sh slug --scope SCOPE --name NAME
#       Prints the scope slug sessions are named by: `<scope>-<name>` lowercased,
#       every character outside [a-z0-9-] made `-`, runs of `-` squeezed, one
#       trailing `-` trimmed. Reads no session. Exit 0.
#   coord-log.sh vars --session S
#       Prints the workflow_initialized variables object as compact JSON, the
#       run's scope, roadmap or discipline, and host. Exit 0; 2 read failure.
#   coord-log.sh entered --session S --state ST
#       Exit 0 when the log shows any entry into ST in this run; 1 none; 2 read
#       failure. Write scripts ask it whether the run has dispatched yet.
#   coord-log.sh current --session S
#       Prints "<state> <seq>": the state the session is in now, the target of
#       the log's latest transition (transitioned, directed or rewound), and
#       that entry's sequence. Exit 0; 1 no transition; 2 read failure.
#       state-decision.sh binds each write mode to its state with it.
#   coord-log.sh entry --session S --state ST [--before SEQ] [--with-time]
#       Prints "<seq> <from>" for the latest entry into ST (transitioned,
#       directed or rewound), before SEQ when given; --with-time adds the
#       entry's timestamp as a third word. Exit 0; 1 none; 2 read failure.
#   coord-log.sh entries --session S --states ST[,ST...]
#       What `entry` would print for each state, in one read of the log: one
#       line per state, in the order given, "<state> <seq> <from>" for its
#       latest entry or "<state> 0" when the log has none (koto numbers a
#       log's events from 1; the header carries no seq, so 0 is never one).
#       A state name is [a-z0-9_]+. Exit 0; 2 read failure.
#   coord-log.sh evidence --session S --state ST [--after SEQ] [--before SEQ]
#                         [--where FIELD=VALUE]... [--has FIELD]
#       Prints {"seq","timestamp","fields"} for the latest evidence submitted at
#       ST in that window. --where keeps evidence whose FIELD, as a string (""
#       when absent), is VALUE, or one of the values VALUE lists separated by
#       `|` (`event=report|progress`); --has keeps evidence whose FIELD is set
#       (not null or false). Exit 0; 1 none; 2 read failure.
#   coord-log.sh captures --session S --name N [--after SEQ] [--before SEQ]
#       Prints {"seq","timestamp","value"} for every engine-written capture of N
#       in that window, oldest first, one per line; no seal is checked. Exit 0;
#       1 none; 2 read failure.
#   coord-log.sh unit --session S [--before SEQ] [--event E]
#       The unit the run's latest arrival names, before SEQ when given. An
#       arrival is a `wait` evidence naming a unit (with --event, any `wait`
#       evidence whose event is E, or one of the events E lists separated by
#       `|`, naming a unit or not), or the leg path: the
#       latest entry into take_report, when it came from wait_leg. Prints
#       `topic <unit>` (the evidence's unit, unchecked, possibly empty) or
#       `leg <request>:<leg>` (the first words of the latest WAIT_REQ and
#       WAIT_LEG captures before that entry), whichever arrival is later.
#       Exit 0; 1 no arrival; 3 a leg whose captures are not a request id and a
#       leg; 2 read failure.
#   coord-log.sh count --session S
#       Prints how many events the log holds. Exit 0; 2 read failure.
#   coord-log.sh wakes --session S [--after-time T]
#       The run's wakes, attributed (docs/designs/current/DESIGN-coordinate-paused-state.md,
#       Decision 4): a wake is `wait` evidence whose event is report, progress,
#       leg, quiet, merged or resume, after T (an ISO-8601 time; every wake
#       when absent). report, progress and merged count for their evidence's
#       unit; leg for `leg <request>`, the request of the first WAIT_REQ
#       capture after it and before the next `wait` evidence, when it read
#       one; quiet for each topic the first QUIET capture after it named
#       silent; anything else, resume included, for the run. Prints one JSON
#       object, {"<topic>" | "leg <request>" | "": count}. Exit 0; 2 read
#       failure.
#
# Exit 64 on usage errors, everywhere.
set -uo pipefail

# Every check script calls this one many times per run, so it spends no process
# it doesn't need: its directory comes from $0 without `dirname`, and a
# subcommand that needs another one's answer calls it in-process.
case "$0" in */*) HERE=${0%/*}; HERE=$(cd "${HERE:-/}" && pwd) ;; *) HERE=$(pwd) ;; esac
KOTO=${KOTO_BIN:-koto}

usage() { sed -n '/^# Usage:/,/^# Exit 64/p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 64; }
die() { echo "coord-log: $*" >&2; exit 2; }

# sha256: the hex digest of stdin, the first word of the tool's output, taken
# in the shell; every seal and check hashes, so a `cut` here would start one
# more process per call.
sha256() {
    local h
    if command -v sha256sum >/dev/null 2>&1; then h=$(sha256sum) || return 1
    else h=$(shasum -a 256) || return 1; fi
    printf '%s\n' "${h%% *}"
}

# session_log <session> -> path of the state log. The one place any script
# finds a session's log: every other script reads it through the subcommands
# below. A header whose schema_version isn't 1 is a format this reader doesn't
# know, so the log is refused rather than misread.
# FLAT_HEADER: `{"schema_version":1` then any number of `,"key":value`, where a
# key is a string with no quote, backslash or control character and a value is
# such a string, an integer without leading zeros, true, false or null; then
# `}`. Every line it matches is valid JSON with no nesting.
FLAT_HEADER='^\{"schema_version":1(,"[^"\\[:cntrl:]]*":("[^"\\[:cntrl:]]*"|-?(0|[1-9][0-9]*)|true|false|null))*\}$'
session_log() {
    local dir f v line=
    dir=$("$KOTO" session dir "$1") || return 1
    f="$dir/koto-$1.state.jsonl"
    [ -r "$f" ] || return 1
    # A header that is a flat JSON object of plain values (no escapes, no
    # nesting), schema_version 1 first and only once, is read without starting
    # jq: the pattern admits only valid JSON, so jq would say 1 for it too.
    # Anything else, koto's own nested header included, goes to jq as before,
    # so a header jq refuses is still refused here.
    # The case refuses a second "schema_version" after the first, since jq
    # reads the last of duplicate keys.
    IFS= read -r line < "$f" || true
    if [[ $line =~ $FLAT_HEADER ]] && case "${line#*'"schema_version"'}" in *'"schema_version"'*) false ;; esac; then
        v=1
    else
        v=$(printf '%s\n' "$line" | jq -c '.schema_version') || v=unreadable
    fi
    if [ "$v" != 1 ]; then
        echo "coord-log: $1's log header has schema_version ${v:-none}; this reader knows 1" >&2
        return 1
    fi
    printf '%s\n' "$f"
}

# events <log>: every event line (the header has no "type").
events() { jq -c 'select(.type != null)' "$1"; }

latest_entry() { # latest_entry <log> <state> -> seq of the latest entry, or empty
    jq -r --arg s "$2" 'select((.type == "transitioned" or .type == "directed_transition" or .type == "rewound") and .payload.to == $s) | .seq' "$1" | tail -1
}

is_entry() { # is_entry <log> <state> <seq>
    jq -e --arg s "$2" --argjson q "$3" 'select(.seq == $q and (.type == "transitioned" or .type == "directed_transition" or .type == "rewound") and .payload.to == $s)' "$1" >/dev/null
}

seal_hash() { printf '%s|%s|%s|%s' "$1" "$2" "$3" "$4" | sha256; }

# effective_root <log>: the run's PLUGIN_ROOT as koto applies it now, the
# value it opened with folded with every variables_rebound event in log order
# (a later rebind wins, as koto folds them).
effective_root() {
    jq -rn '[inputs | select(.type == "workflow_initialized" or .type == "variables_rebound")
             | .payload.variables.PLUGIN_ROOT // empty] | last // empty' "$1"
}

# run_copy <log>: the compiled template koto runs the session from (the
# template_path its workflow_initialized event records), when readable.
run_copy() {
    local p
    p=$(jq -r 'select(.type == "workflow_initialized") | .payload.template_path // empty' "$1" | head -1)
    [ -n "$p" ] && [ -r "$p" ] && printf '%s\n' "$p"
}

# run_fingerprint <log>: the sha256 of the structure of the compiled template
# the session runs from (template-fingerprint.jq), or nothing when that copy
# can't be read.
run_fingerprint() {
    local p
    p=$(run_copy "$1") || return 1
    jq -S -c -f "$HERE/template-fingerprint.jq" "$p" 2>/dev/null | sha256
}

# compat_verdict <fingerprint> <table>: 0 when the compat table lists the
# template structure <fingerprint> at the table's own (shipped) compat number;
# 1 when it lists it at another number or not at all; 2 when the table can't
# be read.
compat_verdict() {
    [ -r "$2" ] || return 2
    jq -e 'type == "object" and (.compat | type == "number") and (.fingerprints | type == "object")' "$2" >/dev/null 2>&1 || return 2
    [ -n "$1" ] || return 1
    jq -e --arg f "$1" '.fingerprints[$f] == .compat' "$2" >/dev/null 2>&1 && return 0
    return 1
}

# default_template: coordinate.md as shipped beside this script.
default_template() { printf '%s/skills/coordinate/koto-templates/coordinate.md' "$(cd "$HERE/../../.." && pwd -P)"; }

SESSION= STATE= TOKEN= FILE= KEY= SEALED= NAME= FOR= FROM= TEMPLATE= SLUG= AFTER= BEFORE=
SCOPE= EVENT= HAS= AFTER_TIME= STATES=
WHERE='[]'
ANY=0 ALL=0 WITH_TIME=0
CMD=${1-}
[ -n "$CMD" ] || usage
shift
while [ $# -gt 0 ]; do
    case "$1" in
        --session) [ $# -ge 2 ] || usage; SESSION=$2; shift 2 ;;
        --state) [ $# -ge 2 ] || usage; STATE=$2; shift 2 ;;
        --states) [ $# -ge 2 ] || usage; STATES=$2; shift 2 ;;
        --token) [ $# -ge 2 ] || usage; TOKEN=$2; shift 2 ;;
        --file) [ $# -ge 2 ] || usage; FILE=$2; shift 2 ;;
        --key) [ $# -ge 2 ] || usage; KEY=$2; shift 2 ;;
        --sealed) [ $# -ge 2 ] || usage; SEALED=$2; shift 2 ;;
        --name) [ $# -ge 2 ] || usage; NAME=$2; shift 2 ;;
        --for) [ $# -ge 2 ] || usage; FOR=$2; shift 2 ;;
        --from) [ $# -ge 2 ] || usage; FROM=$2; shift 2 ;;
        --after) [ $# -ge 2 ] || usage; AFTER=$2; shift 2 ;;
        --after-time) [ $# -ge 2 ] || usage; AFTER_TIME=$2; shift 2 ;;
        --before) [ $# -ge 2 ] || usage; BEFORE=$2; shift 2 ;;
        --template) [ $# -ge 2 ] || usage; TEMPLATE=$2; shift 2 ;;
        --scope-slug) [ $# -ge 2 ] || usage; SLUG=$2; shift 2 ;;
        --scope) [ $# -ge 2 ] || usage; SCOPE=$2; shift 2 ;;
        --event) [ $# -ge 2 ] || usage; EVENT=$2; shift 2 ;;
        --has) [ $# -ge 2 ] || usage; HAS=$2; shift 2 ;;
        --where) [ $# -ge 2 ] || usage
            case "$2" in ?*=*) ;; *) usage ;; esac
            WHERE=$(jq -nc --argjson w "$WHERE" --arg f "${2%%=*}" --arg v "${2#*=}" '$w + [[$f, $v]]') || usage
            shift 2 ;;
        --any-visit) ANY=1; shift ;;
        --all) ALL=1; shift ;;
        --with-time) WITH_TIME=1; shift ;;
        *) usage ;;
    esac
done

need() { for v in "$@"; do eval "[ -n \"\${$v}\" ]" || usage; done; }

# The log this run has already read. It starts empty whatever the environment
# holds: a reader only ever takes the log from koto, never from its caller.
LOG=

# cmd_check: the `check` subcommand, on SESSION, STATE, SEALED, KEY and ANY,
# reading LOG when this process has read it already. It ends the process with
# its exit status, so a caller that goes on afterwards runs it in a subshell,
# setting the variables it reads (SESSION, STATE, SEALED, KEY, ANY) to what the
# subcommand would have been given.
cmd_check() {
    need SESSION STATE SEALED
    [ -n "$LOG" ] || LOG=$(session_log "$SESSION") || die "no readable log for $SESSION"
    case "$SEALED" in
        *' sealed:'*) BODY=${SEALED% sealed:*}; SEAL=${SEALED##* sealed:} ;;
        sealed:*) BODY=; SEAL=${SEALED#sealed:} ;;
        *) echo "coord-log: unsealed" >&2; exit 1 ;;
    esac
    SEQ=${SEAL%%:*}
    HASH=${SEAL#*:}
    case "$SEQ" in ''|*[!0-9]*) echo "coord-log: malformed seal" >&2; exit 1 ;; esac
    case "$HASH" in *[!0-9a-f]*|'') echo "coord-log: malformed seal" >&2; exit 1 ;; esac
    if [ "$ANY" = 1 ]; then
        is_entry "$LOG" "$STATE" "$SEQ" || { echo "coord-log: seq $SEQ is not an entry into $STATE" >&2; exit 1; }
    else
        [ "$(latest_entry "$LOG" "$STATE")" = "$SEQ" ] || { echo "coord-log: seq $SEQ is not the latest entry into $STATE" >&2; exit 1; }
    fi
    if [ -n "$KEY" ]; then
        [ -z "$BODY" ] || usage
        T=$(mktemp "${TMPDIR:-/tmp}/coord-log.XXXXXX")
        trap 'rm -f "$T"' EXIT
        "$KOTO" context get "$SESSION" "$KEY" > "$T" || die "cannot read context key $KEY"
        DIGEST=$(sha256 < "$T")
        [ "$(seal_hash "$SESSION" "$STATE" "$SEQ" "$DIGEST")" = "$HASH" ] || { echo "coord-log: $KEY does not match its seal" >&2; exit 1; }
        cat "$T"
    else
        [ -n "$BODY" ] || { echo "coord-log: a file seal needs --key" >&2; exit 1; }
        [ "$(seal_hash "$SESSION" "$STATE" "$SEQ" "$BODY")" = "$HASH" ] || { echo "coord-log: the token does not match its seal" >&2; exit 1; }
    fi
}

# found_token <token> <scope>: 0 when the find's token, its seal stripped,
# names a record this run holds or is putting in its own session: `found` (the
# run's session holds it), and at discipline scope `first` (the rotation
# record_open opens there) or `predecessor coordinate-<slug>-<stamp>` (the
# predecessor the run carries in).
found_token() {
    case "$1" in
        found) return 0 ;;
        first) [ "$2" = discipline ] ;;
        "predecessor "*)
            [ "$2" = discipline ] && [[ ${1#predecessor } =~ ^coordinate-[a-z0-9-]+-[0-9]{8}T[0-9]{6}Z$ ]] ;;
        *) return 1 ;;
    esac
}

# cmd_capture: the `capture` subcommand, on SESSION, NAME, FOR, STATE and ANY,
# as cmd_check is for `check`.
cmd_capture() {
    need SESSION NAME
    [ -n "$LOG" ] || LOG=$(session_log "$SESSION") || die "no readable log for $SESSION"
    V=$(jq -r --arg n "$NAME" --arg f "$FOR" 'select(.type == "variable_captured" and .payload.key == $n) | .payload.value
        | select($f == "" or ((split(" ") | .[1]) == $f))' "$LOG" | tail -1)
    [ -n "$V" ] || exit 1
    if [ -n "$STATE" ]; then
        (SEALED=$V KEY=; cmd_check) >/dev/null || exit 1
    fi
    printf '%s\n' "$V"
}

case "$CMD" in
seal)
    need SESSION STATE
    { [ -n "$TOKEN" ] && [ -z "$FILE$KEY" ]; } || { [ -z "$TOKEN" ] && [ -n "$FILE" ] && [ -n "$KEY" ]; } || usage
    case "$TOKEN" in *'
'*) usage ;; esac
    LOG=$(session_log "$SESSION") || die "no readable log for $SESSION"
    SEQ=$(latest_entry "$LOG" "$STATE")
    [ -n "$SEQ" ] || die "the log has no entry into $STATE"
    if [ -n "$TOKEN" ]; then
        printf '%s sealed:%s:%s\n' "$TOKEN" "$SEQ" "$(seal_hash "$SESSION" "$STATE" "$SEQ" "$TOKEN")"
    else
        [ -r "$FILE" ] || usage
        "$KOTO" context add "$SESSION" "$KEY" --from-file "$FILE" >/dev/null || { echo "coord-log: koto context add failed" >&2; exit 66; }
        DIGEST=$(sha256 < "$FILE")
        printf 'sealed:%s:%s\n' "$SEQ" "$(seal_hash "$SESSION" "$STATE" "$SEQ" "$DIGEST")"
    fi
    ;;
check) cmd_check ;;
capture) cmd_capture ;;
directed-since)
    need SESSION FROM
    case "$FROM" in *[!0-9]*) usage ;; esac
    LOG=$(session_log "$SESSION") || die "no readable log for $SESSION"
    OUT=$(jq -r --argjson q "$FROM" 'select(.type == "directed_transition" and .seq > $q) | "\(.seq) \(.payload.from)->\(.payload.to)"' "$LOG")
    [ -z "$OUT" ] && exit 0
    printf '%s\n' "$OUT"
    exit 1
    ;;
run-start)
    need SESSION
    LOG=$(session_log "$SESSION") || die "no readable log for $SESSION"
    head -1 "$LOG" | jq -er '.created_at' || die "no created_at in the header"
    ;;
chain-start)
    need SESSION
    LOG=$(session_log "$SESSION") || die "no readable log for $SESSION"
    START=$(head -1 "$LOG" | jq -er '.created_at') || die "no created_at in the header"
    # A name coordinate-open.sh didn't give has no scope to find a chain in.
    [[ $SESSION =~ ^coordinate-([a-z0-9-]+)-[0-9]{8}T[0-9]{6}Z$ ]] || { printf '%s\n' "$START"; exit 0; }
    P="coordinate-${BASH_REMATCH[1]}-"
    # Every earlier run of this scope, newest first. The stamp sorts as time,
    # and matching it whole keeps a longer slug from reading as this scope's.
    LIST=$("$KOTO" session list) || die "koto session list failed"
    for id in $(printf '%s' "$LIST" | jq -r --arg p "$P" --arg me "$SESSION" '[.[] | select(.parent_workflow == null) | .id
            | select(startswith($p) and (.[($p | length):] | test("^[0-9]{8}T[0-9]{6}Z$")) and . < $me)] | sort | reverse | .[]'); do
        L=$(session_log "$id") || break
        jq -e 'select(.type == "workflow_cancelled")' "$L" >/dev/null || break
        START=$(head -1 "$L" | jq -er '.created_at') || die "no created_at in $id's header"
    done
    printf '%s\n' "$START"
    ;;
run-facts)
    need SESSION
    LOG=$(session_log "$SESSION") || die "no readable log for $SESSION"
    VARS=$(jq -c 'select(.type == "workflow_initialized") | .payload.variables' "$LOG" | head -1)
    [ -n "$VARS" ] || die "no workflow_initialized event"
    FOUND=$(NAME=RECORD_FIND FOR= STATE= ANY=0; cmd_capture) || exit 1
    found_token "${FOUND% sealed:*}" "$(printf '%s' "$VARS" | jq -r '.SCOPE // ""')" || exit 1
    (STATE=record_find SEALED=$FOUND KEY= ANY=1; cmd_check) >/dev/null 2>&1 || exit 1
    printf '%s' "$VARS" | jq -c '{
        scope: .SCOPE,
        name: (if .SCOPE == "roadmap" then (.ROADMAP | split("/") | last | sub("^ROADMAP-"; "") | sub("\\.md$"; "")) else .DISCIPLINE end),
        repo: .HOST_REPO}'
    ;;
provenance)
    need SESSION
    LOG=$(session_log "$SESSION") || die "no readable log for $SESSION"
    HASH=$(head -1 "$LOG" | jq -r '.template_hash // empty')
    ROOT=$(effective_root "$LOG")
    MINE=$(cd "$HERE/../../.." && pwd -P)
    [ -n "$ROOT" ] && [ "$(cd "$ROOT" 2>/dev/null && pwd -P)" = "$MINE" ] || { echo "coord-log: PLUGIN_ROOT is not this plugin" >&2; exit 1; }
    [ -n "$TEMPLATE" ] || TEMPLATE=$(default_template)
    [ -n "$HASH" ] || { echo "coord-log: the session's header has no template_hash" >&2; exit 1; }
    # A run compiled from a template whose structure the shipped compat table
    # lists at the shipped compat number is one this plugin's scripts can
    # drive, whatever its directive text (coordinate.compat.json; CI's
    # check-template-compat.sh keeps the table honest).
    compat_verdict "$(run_fingerprint "$LOG")" "${TEMPLATE%.md}.compat.json" && exit 0
    # A template that doesn't compile (a reinstall left half-written, say)
    # proves nothing either way, so it falls through to the check below.
    COMPILED=$("$KOTO" template compile "$TEMPLATE") || COMPILED=
    [ -n "$COMPILED" ] && [ "$HASH" = "$(basename "$COMPILED" .json)" ] && exit 0
    # The template no longer compiles to the hash the session opened under:
    # a foreign session, or the plugin rewritten in place since the run
    # opened. koto runs a session from the compiled copy it cached at init,
    # whose content hashes to template_hash (coord-log_engine_test.sh pins
    # this against real koto), so a rewrite leaves the run's own contract
    # unchanged. What tells the two apart is where koto recorded compiling it
    # from: the session passes when that is this template's own path, given
    # absolute, and its compiled copy is still there, whole.
    { IFS= read -r SRC_DIR; IFS= read -r SRC_FILE; } <<EOF
$(head -1 "$LOG" | jq -r '(.template_source_dir // ""), (.template_source_file // "")')
EOF
    RUN_COPY=$(jq -r 'select(.type == "workflow_initialized") | .payload.template_path // empty' "$LOG" | head -1)
    TEMPLATE_DIR=$(cd "$(dirname "$TEMPLATE")" 2>/dev/null && pwd -P) || TEMPLATE_DIR=
    case "$SRC_DIR" in /*) ;; *) SRC_DIR= ;; esac
    if [ -n "$SRC_DIR" ] && [ -n "$TEMPLATE_DIR" ] && [ "$(cd "$SRC_DIR" 2>/dev/null && pwd -P)" = "$TEMPLATE_DIR" ] \
        && [ "$(basename "$SRC_FILE")" = "$(basename "$TEMPLATE")" ] \
        && [ -n "$RUN_COPY" ] && [ -r "$RUN_COPY" ] && [ "$(sha256 < "$RUN_COPY")" = "$HASH" ]; then
        exit 0
    fi
    echo "coord-log: the session was not created from $TEMPLATE" >&2
    exit 1
    ;;
compat)
    need SESSION
    LOG=$(session_log "$SESSION") || die "no readable log for $SESSION"
    FP=$(run_fingerprint "$LOG") || FP=
    [ -n "$TEMPLATE" ] || TEMPLATE=$(default_template)
    TABLE=${TEMPLATE%.md}.compat.json
    compat_verdict "$FP" "$TABLE"
    RC=$?
    [ $RC -eq 2 ] && die "the compat table $TABLE can't be read"
    jq -r --arg f "$FP" '"\(if $f == "" then "-" else (.fingerprints[$f] // "-") end) \(.compat) \(if $f == "" then "unreadable" else $f end)"' "$TABLE"
    exit $RC
    ;;
plugin-root)
    need SESSION
    LOG=$(session_log "$SESSION") || die "no readable log for $SESSION"
    ROOT=$(effective_root "$LOG")
    REBIND=false
    if RUN_COPY=$(run_copy "$LOG") && jq -e '.variables.PLUGIN_ROOT.rebind == true' "$RUN_COPY" >/dev/null 2>&1; then
        REBIND=true
    fi
    jq -nc --arg r "$ROOT" --argjson b "$REBIND" '{root: $r, rebind: $b}'
    ;;
template-hash)
    need SESSION
    LOG=$(session_log "$SESSION") || die "no readable log for $SESSION"
    HASH=$(head -1 "$LOG" | jq -r '.template_hash // empty')
    [ -n "$HASH" ] || { echo "coord-log: the session's header has no template_hash" >&2; exit 1; }
    printf '%s\n' "$HASH"
    ;;
live-session)
    need SLUG
    case "$SLUG" in *[!a-z0-9-]*) usage ;; esac
    LIVE=
    n=0
    # A run's name is coordinate-<slug>-<UTC stamp>; matching the stamp keeps a
    # longer slug (a -v2 roadmap) from reading as this scope's run.
    for id in $("$KOTO" session list | jq -r --arg p "coordinate-$SLUG-" '.[] | select(.parent_workflow == null) | .id | select(startswith($p) and (.[($p | length):] | test("^[0-9]{8}T[0-9]{6}Z$")))'); do
        st=$("$KOTO" status "$id") || continue
        [ "$(printf '%s' "$st" | jq -r '.is_terminal')" = false ] || continue
        LOG=$(session_log "$id") || continue
        jq -e 'select(.type == "workflow_cancelled")' "$LOG" >/dev/null && continue
        [ "$ALL" = 1 ] && printf '%s\n' "$id"
        LIVE=$id
        n=$((n + 1))
    done
    [ $n -eq 0 ] && exit 1
    [ "$ALL" = 1 ] && exit 0
    [ $n -gt 1 ] && { echo "coord-log: several live sessions for $SLUG" >&2; exit 3; }
    printf '%s\n' "$LIVE"
    ;;
slug)
    need SCOPE NAME
    SLUG=$(printf '%s-%s' "$SCOPE" "$NAME" | tr '[:upper:]' '[:lower:]' | tr -c 'a-z0-9-\n' '-' | tr -s '-')
    printf '%s\n' "${SLUG%-}"
    ;;
count)
    need SESSION
    LOG=$(session_log "$SESSION") || die "no readable log for $SESSION"
    N=$(wc -l < "$LOG") || die "cannot read $LOG"
    echo $((N - 1))
    ;;
vars)
    need SESSION
    LOG=$(session_log "$SESSION") || die "no readable log for $SESSION"
    VARS=$(jq -c 'select(.type == "workflow_initialized") | .payload.variables' "$LOG" | head -1)
    [ -n "$VARS" ] || die "no workflow_initialized event"
    printf '%s\n' "$VARS"
    ;;
entered)
    need SESSION STATE
    LOG=$(session_log "$SESSION") || die "no readable log for $SESSION"
    [ -n "$(latest_entry "$LOG" "$STATE")" ] || exit 1
    ;;
current)
    need SESSION
    LOG=$(session_log "$SESSION") || die "no readable log for $SESSION"
    CUR=$(jq -r 'select(.type == "transitioned" or .type == "directed_transition" or .type == "rewound") | "\(.payload.to) \(.seq)"' "$LOG" | tail -1)
    [ -n "$CUR" ] || exit 1
    printf '%s\n' "$CUR"
    ;;
entries)
    # `entry` for several states in one pass, for a check script that would
    # otherwise start this script once per state. A log jq can't read ends
    # in a read failure (jq prints only after reading the whole log), as
    # `entry` does under pipefail, never in a "0" that reads as no entry.
    need SESSION STATES
    re='^[a-z0-9_]+(,[a-z0-9_]+)*$'
    [[ $STATES =~ $re ]] || usage
    LOG=$(session_log "$SESSION") || die "no readable log for $SESSION"
    jq -nr --arg ss "$STATES" '($ss | split(",")) as $want
        | reduce (inputs | select((.type == "transitioned" or .type == "directed_transition" or .type == "rewound")
                and (.payload.to as $t | $want | index([$t]) != null))) as $e
            ({}; .[$e.payload.to] = "\($e.seq) \($e.payload.from // "")")
        | . as $m | $want[] | if $m[.] then "\(.) \($m[.])" else "\(.) 0" end' "$LOG" || die "cannot read $LOG"
    ;;
entry|evidence|captures)
    if [ "$CMD" = captures ]; then need SESSION NAME; else need SESSION STATE; fi
    for n in "$AFTER" "$BEFORE"; do case "$n" in *[!0-9]*) usage ;; esac; done
    LOG=$(session_log "$SESSION") || die "no readable log for $SESSION"
    A=${AFTER:-0} B=${BEFORE:-}
    case "$CMD" in
    entry)
        OUT=$(jq -r --arg s "$STATE" --arg b "$B" 'select((.type == "transitioned" or .type == "directed_transition" or .type == "rewound")
            and .payload.to == $s and ($b == "" or .seq < ($b | tonumber)))
            | "\(.seq) \(.payload.from // "")" + (if $t == 1 then " \(.timestamp)" else "" end)' --argjson t "$WITH_TIME" "$LOG" | tail -1) || die "cannot read $LOG"
        ;;
    evidence)
        OUT=$(jq -c --arg s "$STATE" --argjson a "$A" --arg b "$B" --argjson w "$WHERE" --arg h "$HAS" '
            select(.type == "evidence_submitted" and .payload.state == $s
                and .seq > $a and ($b == "" or .seq < ($b | tonumber)))
            | (.payload.fields // {}) as $f
            | select(all($w[]; ($f[.[0]] // "" | tostring) as $v
                    | (.[1] | if . == "" then [""] else split("|") end) | index([$v]) != null)
                and ($h == "" or ($f[$h] // null) != null))
            | {seq, timestamp, fields: $f}' "$LOG" | tail -1) || die "cannot read $LOG"
        ;;
    captures)
        OUT=$(jq -c --arg n "$NAME" --argjson a "$A" --arg b "$B" 'select(.type == "variable_captured" and .payload.key == $n
            and .seq > $a and ($b == "" or .seq < ($b | tonumber))) | {seq, timestamp, value: .payload.value}' "$LOG") || die "cannot read $LOG"
        ;;
    esac
    [ -n "$OUT" ] || exit 1
    printf '%s\n' "$OUT"
    ;;
unit)
    need SESSION
    case "$BEFORE" in *[!0-9]*) usage ;; esac
    LOG=$(session_log "$SESSION") || die "no readable log for $SESSION"
    OUT=$(jq -rs --arg b "$BEFORE" --arg ev "$EVENT" '
        [.[] | select(.type != null and ($b == "" or .seq < ($b | tonumber)))] as $e
        | def cap($k; $q): [$e[] | select(.type == "variable_captured" and .payload.key == $k and .seq < $q)] | last
            | (.payload.value // "") | tostring | split(" ") | .[0] // "";
          ([$e[] | select((.type == "transitioned" or .type == "directed_transition" or .type == "rewound")
            and .payload.to == "take_report")] | last) as $leg
        | ([$e[] | select(.type == "evidence_submitted" and .payload.state == "wait"
            and (if $ev == "" then (.payload.fields.unit // null) != null
                 else ((.payload.fields.event // "") | tostring) as $got | ($ev | split("|") | index([$got]) != null) end))] | last) as $w
        | if $leg != null and ($leg.payload.from // "") == "wait_leg" and ($w == null or $leg.seq > $w.seq) then
            cap("WAIT_REQ"; $leg.seq) as $r | cap("WAIT_LEG"; $leg.seq) as $l
            | if ($r | test("^[a-z0-9_][a-z0-9_-]{0,63}$")) and ($l | test("^[a-z0-9_-]+$")) then "leg \($r):\($l)" else "unusable" end
          elif $w != null then "topic \(($w.payload.fields.unit // "") | tostring)"
          else empty end' "$LOG") || die "cannot read $LOG"
    [ -n "$OUT" ] || exit 1
    [ "$OUT" = unusable ] && { echo "coord-log: the leg captures are not a request id and a leg" >&2; exit 3; }
    printf '%s\n' "$OUT"
    ;;
wakes)
    need SESSION
    LOG=$(session_log "$SESSION") || die "no readable log for $SESSION"
    # One pass over the log: a wake stays open until the next `wait` evidence,
    # and the first WAIT_REQ or QUIET capture inside it says what it was for.
    jq -cn --arg t "$AFTER_TIME" '
        def secs: (. // "") | tostring | sub("\\.[0-9]+Z$"; "Z") | try fromdateiso8601 catch 0;
        def close: if .open == null then . else .keys += (.open.k // [""]) | .open = null end;
        ($t | if . == "" then null else secs end) as $cut
        | reduce (inputs | select(.type != null)) as $x ({open: null, keys: []};
            if $x.type == "evidence_submitted" and $x.payload.state == "wait" then
              close
              | (($x.payload.fields // {}) | (.event // "") | tostring) as $ev
              | (($x.payload.fields // {}) | (.unit // "") | tostring) as $u
              | if ($cut != null and ($x.timestamp | secs) <= $cut) then .
                elif ($ev == "report" or $ev == "progress" or $ev == "merged") then .open = {ev: $ev, k: [$u]}
                elif ($ev == "leg" or $ev == "quiet") then .open = {ev: $ev, k: null}
                elif $ev == "resume" then .open = {ev: $ev, k: [""]}
                else . end
            elif $x.type == "variable_captured" and .open != null and .open.k == null then
              (($x.payload.value // "") | tostring | sub(" sealed:.*$"; "") | split(" ")) as $w
              | if .open.ev == "leg" and $x.payload.key == "WAIT_REQ" then
                  .open.k = [if ($w[0] // "") == "" or $w[0] == "none" then "" else "leg " + $w[0] end]
                elif .open.ev == "quiet" and $x.payload.key == "QUIET" then
                  .open.k = ((if ($w[0] == "first-silence" or $w[0] == "second-silence") then $w[1:] else [] end)
                             | if length == 0 then [""] else . end)
                else . end
            else . end)
        | close
        | reduce .keys[] as $k ({}; .[$k] += 1)' "$LOG" || die "cannot read $LOG"
    ;;
*) usage ;;
esac
