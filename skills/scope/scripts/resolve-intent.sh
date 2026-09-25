#!/usr/bin/env bash
# resolve-intent.sh -- the effective intent of a /scope run.
#
# /scope carries the caller's `--intent` token on the koto variable
# INTENT_FLAG, which is empty when the flag was not given. The effective
# intent, RUN_INTENT, is what every later intent check keys on, and it is
# resolved here and nowhere else:
#
#   1. INTENT_FLAG, when it is non-empty;
#   2. otherwise the `intent:` field of the run's state file, when the file
#      exists and records one;
#   3. otherwise `none`.
#
# A state file written before `intent:` existed has no such field and reads as
# `none`. The empty value exists only on the variable: a state file whose
# `intent:` is empty, a placeholder, or outside continue|stop|none is a schema
# violation (see references/parent-skill-state-schema.md, Invocation intent),
# not a run with no intent.
#
# Usage:
#   resolve-intent.sh --intent-flag <value> --state-file <path>
#
#   --intent-flag   INTENT_FLAG as koto holds it: empty, continue, or stop.
#   --state-file    the run's state file, wip/scope_<topic>_state.md. It need
#                   not exist.
#
# Output: exactly one line on stdout, `continue`, `stop`, or `none`, then exit
# 0. With `--intent-flag ""` the line is the state file's recorded intent (or
# `none`), which is how check-recorded-intent.sh reads it.
#
# Exit codes:
#   0  resolved; the value is on stdout
#   2  cannot resolve: a usage error, an INTENT_FLAG outside continue|stop, a
#      state file that exists but cannot be read, or a recorded `intent:` that
#      is empty, repeated, or outside continue|stop|none. Nothing on stdout.
#
# Reads only its arguments and the named file. bash 3.2.

set -uo pipefail

PROG=resolve-intent.sh

die() {
    printf '%s: %s\n' "$PROG" "$1" >&2
    exit 2
}

FLAG=""
FLAG_SEEN=0
STATE_FILE=""
STATE_SEEN=0

while [ "$#" -gt 0 ]; do
    case "$1" in
        --intent-flag)
            [ "$#" -ge 2 ] || die "--intent-flag requires a value (it may be empty)"
            [ "$FLAG_SEEN" -eq 0 ] || die "--intent-flag given more than once"
            FLAG="$2"; FLAG_SEEN=1; shift ;;
        --intent-flag=*)
            [ "$FLAG_SEEN" -eq 0 ] || die "--intent-flag given more than once"
            FLAG="${1#--intent-flag=}"; FLAG_SEEN=1 ;;
        --state-file)
            [ "$#" -ge 2 ] || die "--state-file requires a path"
            [ "$STATE_SEEN" -eq 0 ] || die "--state-file given more than once"
            STATE_FILE="$2"; STATE_SEEN=1; shift ;;
        --state-file=*)
            [ "$STATE_SEEN" -eq 0 ] || die "--state-file given more than once"
            STATE_FILE="${1#--state-file=}"; STATE_SEEN=1 ;;
        *) die "unknown argument: $1" ;;
    esac
    shift
done

[ "$FLAG_SEEN" -eq 1 ] || die "--intent-flag is required (pass an empty value when the flag was not given)"
[ "$STATE_SEEN" -eq 1 ] || die "--state-file is required"
[ -n "$STATE_FILE" ] || die "--state-file must not be empty"

case "$FLAG" in
    continue|stop)
        printf '%s\n' "$FLAG"
        exit 0
        ;;
    "") ;;
    *) die "INTENT_FLAG must be empty, continue, or stop" ;;
esac

# No explicit intent: the recorded one, if any.
if [ ! -e "$STATE_FILE" ] && [ ! -L "$STATE_FILE" ]; then
    printf 'none\n'
    exit 0
fi
[ -f "$STATE_FILE" ] && [ -r "$STATE_FILE" ] || die "state file exists but cannot be read: $STATE_FILE"

# The field is a top-level YAML key: `intent:` at column 0. Indented keys of
# the same name belong to nested blocks and are not the run's intent.
COUNT=0
VALUE=""
while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in
        intent:*)
            COUNT=$((COUNT + 1))
            VALUE="${line#intent:}"
            ;;
    esac
done <"$STATE_FILE" || die "state file cannot be read: $STATE_FILE"

if [ "$COUNT" -eq 0 ]; then
    # Written before the field existed.
    printf 'none\n'
    exit 0
fi
[ "$COUNT" -eq 1 ] || die "state file records intent: more than once"

# Trim a trailing comment, surrounding whitespace and CR, and one pair of
# matching quotes.
case "$VALUE" in
    *' #'*) VALUE="${VALUE%% #*}" ;;
esac
VALUE="${VALUE#"${VALUE%%[![:space:]]*}"}"
VALUE="${VALUE%"${VALUE##*[![:space:]]}"}"
case "$VALUE" in
    \"*\") VALUE="${VALUE#\"}"; VALUE="${VALUE%\"}" ;;
    \'*\') VALUE="${VALUE#\'}"; VALUE="${VALUE%\'}" ;;
esac

case "$VALUE" in
    continue|stop|none)
        printf '%s\n' "$VALUE"
        exit 0
        ;;
    *) die "state file records intent outside continue|stop|none" ;;
esac
