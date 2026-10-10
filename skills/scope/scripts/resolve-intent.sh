#!/usr/bin/env bash
# resolve-intent.sh -- the effective intent of a /scope run.
#
# /scope carries the caller's `--intent` token on the koto variable
# INTENT_FLAG, which is empty when the flag was not given. The effective
# intent, RUN_INTENT, is what every later intent check keys on, and it is
# resolved here and nowhere else:
#
#   1. INTENT_FLAG, when it is non-empty;
#   2. otherwise the `intent:` field of key work/state.md in the run's
#      session, when the key exists and records one;
#   3. otherwise the `intent:` field of key work/prior-run.md, when that key
#      records a failed publish step (`step:` scope:push or scope:pr-create).
#      scope-open.sh writes the key from the result of a finished run it
#      replaced, and only a run that failed to publish has anything left to
#      retry; a finished run's intent after a clean exit is not carried;
#   4. otherwise `none`.
#
# A state written before `intent:` existed has no such field and reads as
# `none`. The empty value exists only on the variable: a state whose
# `intent:` is empty, a placeholder, or outside continue|stop|none is a schema
# violation (see references/parent-skill-state-schema.md, Invocation intent),
# not a run with no intent.
#
# Usage:
#   resolve-intent.sh --intent-flag <value> --session <name>
#
#   --intent-flag   INTENT_FLAG as koto holds it: empty, continue, or stop.
#   --session       the run's koto session, scope-<topic>. It need not exist,
#                   and neither key need exist in it.
#
# Output: exactly one line on stdout, `continue`, `stop`, or `none`, then exit
# 0. With `--intent-flag ""` the line is the recorded intent (or `none`),
# which is how check-recorded-intent.sh reads it.
#
# Exit codes:
#   0  resolved; the value is on stdout
#   2  cannot resolve: a usage error, an INTENT_FLAG outside continue|stop, a
#      session name outside ^[a-z][a-z-]*-[a-z0-9][a-z0-9-]*$, a key koto
#      cannot report on or read, or a recorded `intent:` that is empty,
#      repeated, or outside continue|stop|none (in work/prior-run.md, only
#      when it records a failed publish step). Nothing on stdout.
#
# Reads only its arguments and the two keys, through `koto context` (KOTO_BIN
# names the binary). bash 3.2.

set -uo pipefail

PROG=resolve-intent.sh

die() {
    printf '%s: %s\n' "$PROG" "$1" >&2
    exit 2
}

FLAG=""
FLAG_SEEN=0
SESSION=""
SESSION_SEEN=0

while [ "$#" -gt 0 ]; do
    case "$1" in
        --intent-flag)
            [ "$#" -ge 2 ] || die "--intent-flag requires a value (it may be empty)"
            [ "$FLAG_SEEN" -eq 0 ] || die "--intent-flag given more than once"
            FLAG="$2"; FLAG_SEEN=1; shift ;;
        --intent-flag=*)
            [ "$FLAG_SEEN" -eq 0 ] || die "--intent-flag given more than once"
            FLAG="${1#--intent-flag=}"; FLAG_SEEN=1 ;;
        --session)
            [ "$#" -ge 2 ] || die "--session requires a name"
            [ "$SESSION_SEEN" -eq 0 ] || die "--session given more than once"
            SESSION="$2"; SESSION_SEEN=1; shift ;;
        --session=*)
            [ "$SESSION_SEEN" -eq 0 ] || die "--session given more than once"
            SESSION="${1#--session=}"; SESSION_SEEN=1 ;;
        *) die "unknown argument: $1" ;;
    esac
    shift
done

[ "$FLAG_SEEN" -eq 1 ] || die "--intent-flag is required (pass an empty value when the flag was not given)"
[ "$SESSION_SEEN" -eq 1 ] || die "--session is required"
[[ "$SESSION" =~ ^[a-z][a-z-]*-[a-z0-9][a-z0-9-]*$ ]] || die "--session must match ^[a-z][a-z-]*-[a-z0-9][a-z0-9-]*\$"

case "$FLAG" in
    continue|stop)
        printf '%s\n' "$FLAG"
        exit 0
        ;;
    "") ;;
    *) die "INTENT_FLAG must be empty, continue, or stop" ;;
esac

KOTO="${KOTO_BIN:-koto}"

# read_key <key> -- set DOC to the key's bytes and return 0; return 1 when the
# key (or the session) does not exist; die when koto cannot say or cannot
# return the bytes.
DOC=""
read_key() {
    local rc=0 out
    "$KOTO" context exists "$SESSION" "$1" >/dev/null 2>&1 || rc=$?
    case "$rc" in
        0) ;;
        1) return 1 ;;
        *) die "koto context exists $SESSION $1 exited $rc" ;;
    esac
    out=$("$KOTO" context get "$SESSION" "$1" 2>/dev/null && printf '.') \
        || die "key $1 of $SESSION cannot be read"
    DOC="${out%.}"
}

# field <name> -- sets COUNT and VALUE for the top-level YAML key `<name>:`
# (column 0) in DOC. Indented keys of the same name belong to nested blocks.
# The value is trimmed of a trailing comment, surrounding whitespace and CR,
# and one pair of matching quotes.
COUNT=0
VALUE=""
field() {
    COUNT=0
    VALUE=""
    local line
    while IFS= read -r line || [ -n "$line" ]; do
        case "$line" in
            "$1":*)
                COUNT=$((COUNT + 1))
                VALUE="${line#"$1":}"
                ;;
        esac
    done <<EOF_DOC
$DOC
EOF_DOC
    case "$VALUE" in
        *' #'*) VALUE="${VALUE%% #*}" ;;
    esac
    VALUE="${VALUE#"${VALUE%%[![:space:]]*}"}"
    VALUE="${VALUE%"${VALUE##*[![:space:]]}"}"
    case "$VALUE" in
        \"*\") VALUE="${VALUE#\"}"; VALUE="${VALUE%\"}" ;;
        \'*\') VALUE="${VALUE#\'}"; VALUE="${VALUE%\'}" ;;
    esac
}

# No explicit intent: the recorded one, if any.
if read_key work/state.md; then
    field intent
    if [ "$COUNT" -eq 0 ]; then
        # Written before the field existed.
        printf 'none\n'
        exit 0
    fi
    [ "$COUNT" -eq 1 ] || die "work/state.md records intent: more than once"
    case "$VALUE" in
        continue|stop|none)
            printf '%s\n' "$VALUE"
            exit 0
            ;;
        *) die "work/state.md records intent outside continue|stop|none" ;;
    esac
fi

# No state: a finished run's failed publish may still be waiting for a retry.
if read_key work/prior-run.md; then
    field step
    if [ "$COUNT" -eq 1 ]; then
        case "$VALUE" in
            scope:push|scope:pr-create)
                field intent
                [ "$COUNT" -eq 1 ] || die "work/prior-run.md records intent: $COUNT times"
                case "$VALUE" in
                    continue|stop|none)
                        printf '%s\n' "$VALUE"
                        exit 0
                        ;;
                    *) die "work/prior-run.md records intent outside continue|stop|none" ;;
                esac
                ;;
        esac
    fi
fi

printf 'none\n'
exit 0
