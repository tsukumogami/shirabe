#!/usr/bin/env bash
# check-recorded-intent.sh -- refuse an explicit --intent that differs from the
# intent an unfinished run already recorded.
#
# A live `scope-<topic>` session is protected by koto itself: INTENT_FLAG is
# not rebindable, so `koto init --attach-live` refuses a differing explicit
# value as var_mismatch. This script covers the case koto cannot see, a
# finished run whose session scope-open.sh replaced after a failed publish:
# key work/prior-run.md of the new session still records the intent that run
# was started with, and a new invocation naming a different one must not
# silently retry the publish under another intent. (key work/state.md of the
# same session is read the same way, through resolve-intent.sh.)
#
# A bare invocation (INTENT_FLAG empty) is never a mismatch; it resumes under
# the recorded value. An explicit value equal to the recorded one proceeds.
#
# Usage:
#   check-recorded-intent.sh --intent-flag <value> --session <name>
#
# Output and exit codes:
#   0  no mismatch; nothing on stdout
#   1  mismatch; stdout carries exactly two lines:
#        intent-mismatch
#        recorded=<continue|stop|none>
#   2  cannot tell: a usage error, or the keys cannot be read or record an
#      intent outside continue|stop|none (resolve-intent.sh's refusal).
#      Nothing on stdout.
#
# The recorded value is read through resolve-intent.sh with an empty flag, so
# the two scripts can never disagree about what the session says. A state
# with no `intent:` field (written before the field existed) records `none`.
# Read-only. bash 3.2.

set -uo pipefail

PROG=check-recorded-intent.sh
HERE=$(cd "$(dirname "$0")" && pwd)

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

[ "$FLAG_SEEN" -eq 1 ] || die "--intent-flag is required"
[ "$SESSION_SEEN" -eq 1 ] || die "--session is required"
[ -n "$SESSION" ] || die "--session must not be empty"

case "$FLAG" in
    "") exit 0 ;;
    continue|stop) ;;
    *) die "INTENT_FLAG must be empty, continue, or stop" ;;
esac

# Nothing recorded reads as `none` through resolve-intent.sh, and an explicit
# continue|stop differs from `none`, so a session that records nothing must be
# told apart first: work/state.md counts when it exists, work/prior-run.md only
# when it records a failed publish step (a clean finish leaves nothing to
# retry, so it binds no intent).
KOTO="${KOTO_BIN:-koto}"
HAVE=0
rc=0
"$KOTO" context exists "$SESSION" work/state.md >/dev/null 2>&1 || rc=$?
case "$rc" in
    0) HAVE=1 ;;
    1) ;;
    *) die "koto context exists $SESSION work/state.md exited $rc" ;;
esac
if [ "$HAVE" -eq 0 ]; then
    rc=0
    "$KOTO" context exists "$SESSION" work/prior-run.md >/dev/null 2>&1 || rc=$?
    case "$rc" in
        0)
            PRIOR=$("$KOTO" context get "$SESSION" work/prior-run.md 2>/dev/null) \
                || die "key work/prior-run.md of $SESSION cannot be read"
            if printf '%s\n' "$PRIOR" | grep -Eq '^step:[[:space:]]*["'"'"']?scope:(push|pr-create)'; then
                HAVE=1
            fi
            ;;
        1) ;;
        *) die "koto context exists $SESSION work/prior-run.md exited $rc" ;;
    esac
fi
[ "$HAVE" -eq 1 ] || exit 0

RECORDED=$(bash "$HERE/resolve-intent.sh" --intent-flag "" --session "$SESSION") \
    || die "the recorded intent could not be read from session $SESSION"

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
