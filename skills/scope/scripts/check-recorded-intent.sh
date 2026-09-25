#!/usr/bin/env bash
# check-recorded-intent.sh -- refuse an explicit --intent that differs from the
# intent an unfinished run already recorded.
#
# A live `scope-<topic>` session is protected by koto itself: INTENT_FLAG is
# not rebindable, so `koto init --attach-live` refuses a differing explicit
# value as var_mismatch. This script covers the case koto cannot see, an
# unfinished run whose session is gone: its state file still records the
# intent it was started with, and a new invocation naming a different one must
# not silently continue it under another intent.
#
# A bare invocation (INTENT_FLAG empty) is never a mismatch; it resumes under
# the recorded value. An explicit value equal to the recorded one proceeds.
#
# Usage:
#   check-recorded-intent.sh --intent-flag <value> --state-file <path>
#
# Output and exit codes:
#   0  no mismatch; nothing on stdout
#   1  mismatch; stdout carries exactly two lines:
#        intent-mismatch
#        recorded=<continue|stop|none>
#   2  cannot tell: a usage error, or the state file cannot be read or records
#      an intent outside continue|stop|none (resolve-intent.sh's refusal).
#      Nothing on stdout.
#
# The recorded value is read through resolve-intent.sh with an empty flag, so
# the two scripts can never disagree about what a state file says. A state
# file with no `intent:` field (written before the field existed) records
# `none`. Read-only. bash 3.2.

set -uo pipefail

PROG=check-recorded-intent.sh
HERE=$(cd "$(dirname "$0")" && pwd)

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

[ "$FLAG_SEEN" -eq 1 ] || die "--intent-flag is required"
[ "$STATE_SEEN" -eq 1 ] || die "--state-file is required"
[ -n "$STATE_FILE" ] || die "--state-file must not be empty"

case "$FLAG" in
    "") exit 0 ;;
    continue|stop) ;;
    *) die "INTENT_FLAG must be empty, continue, or stop" ;;
esac

# No state file: nothing was recorded, so nothing can differ.
if [ ! -e "$STATE_FILE" ] && [ ! -L "$STATE_FILE" ]; then
    exit 0
fi

RECORDED=$(bash "$HERE/resolve-intent.sh" --intent-flag "" --state-file "$STATE_FILE") \
    || die "the recorded intent could not be read from $STATE_FILE"

case "$RECORDED" in
    continue|stop|none) ;;
    *) die "resolve-intent.sh printed an unexpected value" ;;
esac

if [ "$RECORDED" = "$FLAG" ]; then
    exit 0
fi

printf 'intent-mismatch\n'
printf 'recorded=%s\n' "$RECORDED"
exit 1
