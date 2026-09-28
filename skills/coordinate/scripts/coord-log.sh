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
#       Prints {"scope","name","repo","ref"}. Exit 0; 1 no found record in the
#       run; 2 read failure.
#   coord-log.sh run-start --session S       Prints the header's created_at.
#   coord-log.sh provenance --session S [--template PATH]
#       Exit 0 when the session was created from coordinate.md as shipped beside
#       this script (its compiled hash equals the header's template_hash) and its
#       PLUGIN_ROOT variable is this script's plugin root; 1 otherwise; 2 read failure.
#       --template is for tests that run a localized copy.
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
#       record-decision.sh binds each write mode to its state with it.
#   coord-log.sh entry --session S --state ST [--before SEQ]
#       Prints "<seq> <from>" for the latest entry into ST (transitioned,
#       directed or rewound), before SEQ when given. Exit 0; 1 none; 2 read failure.
#   coord-log.sh evidence --session S --state ST [--after SEQ] [--before SEQ]
#                         [--where FIELD=VALUE]... [--has FIELD]
#       Prints {"seq","timestamp","fields"} for the latest evidence submitted at
#       ST in that window. --where keeps evidence whose FIELD, as a string (""
#       when absent), is VALUE; --has keeps evidence whose FIELD is set (not
#       null or false). Exit 0; 1 none; 2 read failure.
#   coord-log.sh captures --session S --name N [--after SEQ] [--before SEQ]
#       Prints {"seq","timestamp","value"} for every engine-written capture of N
#       in that window, oldest first, one per line; no seal is checked. Exit 0;
#       1 none; 2 read failure.
#   coord-log.sh unit --session S [--before SEQ] [--event E]
#       The unit the run's latest arrival names, before SEQ when given. An
#       arrival is a `wait` evidence naming a unit (with --event, any `wait`
#       evidence whose event is E, naming a unit or not), or the leg path: the
#       latest entry into take_report, when it came from wait_leg. Prints
#       `topic <unit>` (the evidence's unit, unchecked, possibly empty) or
#       `leg <request>:<leg>` (the first words of the latest WAIT_REQ and
#       WAIT_LEG captures before that entry), whichever arrival is later.
#       Exit 0; 1 no arrival; 3 a leg whose captures are not a request id and a
#       leg; 2 read failure.
#   coord-log.sh count --session S
#       Prints how many events the log holds. Exit 0; 2 read failure.
#
# Exit 64 on usage errors, everywhere.
set -uo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
KOTO=${KOTO_BIN:-koto}

usage() { sed -n '/^# Usage:/,/^# Exit 64/p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 64; }
die() { echo "coord-log: $*" >&2; exit 2; }

sha256() {
    if command -v sha256sum >/dev/null 2>&1; then sha256sum | cut -d' ' -f1
    else shasum -a 256 | cut -d' ' -f1; fi
}

# session_log <session> -> path of the state log. The one place any script
# finds a session's log: every other script reads it through the subcommands
# below. A header whose schema_version isn't 1 is a format this reader doesn't
# know, so the log is refused rather than misread.
session_log() {
    local dir f v
    dir=$("$KOTO" session dir "$1") || return 1
    f="$dir/koto-$1.state.jsonl"
    [ -r "$f" ] || return 1
    v=$(head -1 "$f" | jq -c '.schema_version') || v=unreadable
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

SESSION= STATE= TOKEN= FILE= KEY= SEALED= NAME= FOR= FROM= TEMPLATE= SLUG= AFTER= BEFORE=
SCOPE= EVENT= HAS=
WHERE='[]'
ANY=0 ALL=0
CMD=${1-}
[ -n "$CMD" ] || usage
shift
while [ $# -gt 0 ]; do
    case "$1" in
        --session) [ $# -ge 2 ] || usage; SESSION=$2; shift 2 ;;
        --state) [ $# -ge 2 ] || usage; STATE=$2; shift 2 ;;
        --token) [ $# -ge 2 ] || usage; TOKEN=$2; shift 2 ;;
        --file) [ $# -ge 2 ] || usage; FILE=$2; shift 2 ;;
        --key) [ $# -ge 2 ] || usage; KEY=$2; shift 2 ;;
        --sealed) [ $# -ge 2 ] || usage; SEALED=$2; shift 2 ;;
        --name) [ $# -ge 2 ] || usage; NAME=$2; shift 2 ;;
        --for) [ $# -ge 2 ] || usage; FOR=$2; shift 2 ;;
        --from) [ $# -ge 2 ] || usage; FROM=$2; shift 2 ;;
        --after) [ $# -ge 2 ] || usage; AFTER=$2; shift 2 ;;
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
        *) usage ;;
    esac
done

need() { for v in "$@"; do eval "[ -n \"\${$v}\" ]" || usage; done; }

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
check)
    need SESSION STATE SEALED
    LOG=$(session_log "$SESSION") || die "no readable log for $SESSION"
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
    ;;
capture)
    need SESSION NAME
    LOG=$(session_log "$SESSION") || die "no readable log for $SESSION"
    V=$(jq -r --arg n "$NAME" --arg f "$FOR" 'select(.type == "variable_captured" and .payload.key == $n) | .payload.value
        | select($f == "" or ((split(" ") | .[1]) == $f))' "$LOG" | tail -1)
    [ -n "$V" ] || exit 1
    if [ -n "$STATE" ]; then
        if [ "$ANY" = 1 ]; then
            bash "$0" check --session "$SESSION" --state "$STATE" --sealed "$V" --any-visit >/dev/null || exit 1
        else
            bash "$0" check --session "$SESSION" --state "$STATE" --sealed "$V" >/dev/null || exit 1
        fi
    fi
    printf '%s\n' "$V"
    ;;
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
run-facts)
    need SESSION
    LOG=$(session_log "$SESSION") || die "no readable log for $SESSION"
    VARS=$(jq -c 'select(.type == "workflow_initialized") | .payload.variables' "$LOG" | head -1)
    [ -n "$VARS" ] || die "no workflow_initialized event"
    FOUND=$(bash "$0" capture --session "$SESSION" --name RECORD_FIND) || exit 1
    case "$FOUND" in found\ *) ;; *) exit 1 ;; esac
    bash "$0" check --session "$SESSION" --state record_find --sealed "$FOUND" --any-visit >/dev/null 2>&1 || exit 1
    REF=$(printf '%s' "$FOUND" | cut -d' ' -f2)
    case "$REF" in ''|*[!0-9]*) exit 1 ;; esac
    printf '%s' "$VARS" | jq -c --arg ref "$REF" '{
        scope: .SCOPE,
        name: (if .SCOPE == "roadmap" then (.ROADMAP | split("/") | last | sub("^ROADMAP-"; "") | sub("\\.md$"; "")) else .DISCIPLINE end),
        repo: .HOST_REPO, ref: $ref}'
    ;;
provenance)
    need SESSION
    LOG=$(session_log "$SESSION") || die "no readable log for $SESSION"
    HASH=$(head -1 "$LOG" | jq -r '.template_hash // empty')
    ROOT=$(jq -r 'select(.type == "workflow_initialized") | .payload.variables.PLUGIN_ROOT // empty' "$LOG" | head -1)
    MINE=$(cd "$HERE/../../.." && pwd -P)
    [ -n "$ROOT" ] && [ "$(cd "$ROOT" 2>/dev/null && pwd -P)" = "$MINE" ] || { echo "coord-log: PLUGIN_ROOT is not this plugin" >&2; exit 1; }
    [ -n "$TEMPLATE" ] || TEMPLATE="$MINE/skills/coordinate/koto-templates/coordinate.md"
    COMPILED=$("$KOTO" template compile "$TEMPLATE") || die "cannot compile $TEMPLATE"
    WANT=$(basename "$COMPILED" .json)
    [ -n "$HASH" ] && [ "$HASH" = "$WANT" ] || { echo "coord-log: the session was not created from $TEMPLATE" >&2; exit 1; }
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
entry|evidence|captures)
    if [ "$CMD" = captures ]; then need SESSION NAME; else need SESSION STATE; fi
    for n in "$AFTER" "$BEFORE"; do case "$n" in *[!0-9]*) usage ;; esac; done
    LOG=$(session_log "$SESSION") || die "no readable log for $SESSION"
    A=${AFTER:-0} B=${BEFORE:-}
    case "$CMD" in
    entry)
        OUT=$(jq -r --arg s "$STATE" --arg b "$B" 'select((.type == "transitioned" or .type == "directed_transition" or .type == "rewound")
            and .payload.to == $s and ($b == "" or .seq < ($b | tonumber))) | "\(.seq) \(.payload.from // "")"' "$LOG" | tail -1) || die "cannot read $LOG"
        ;;
    evidence)
        OUT=$(jq -c --arg s "$STATE" --argjson a "$A" --arg b "$B" --argjson w "$WHERE" --arg h "$HAS" '
            select(.type == "evidence_submitted" and .payload.state == $s
                and .seq > $a and ($b == "" or .seq < ($b | tonumber)))
            | (.payload.fields // {}) as $f
            | select(all($w[]; ($f[.[0]] // "" | tostring) == .[1]) and ($h == "" or ($f[$h] // null) != null))
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
                 else (.payload.fields.event // "") == $ev end))] | last) as $w
        | if $leg != null and ($leg.payload.from // "") == "wait_leg" and ($w == null or $leg.seq > $w.seq) then
            cap("WAIT_REQ"; $leg.seq) as $r | cap("WAIT_LEG"; $leg.seq) as $l
            | if ($r | test("^[a-z0-9_][a-z0-9_-]{0,63}$")) and ($l | test("^[a-z0-9_-]+$")) then "leg \($r):\($l)" else "unusable" end
          elif $w != null then "topic \(($w.payload.fields.unit // "") | tostring)"
          else empty end' "$LOG") || die "cannot read $LOG"
    [ -n "$OUT" ] || exit 1
    [ "$OUT" = unusable ] && { echo "coord-log: the leg captures are not a request id and a leg" >&2; exit 3; }
    printf '%s\n' "$OUT"
    ;;
*) usage ;;
esac
