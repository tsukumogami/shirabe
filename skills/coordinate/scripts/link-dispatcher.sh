#!/usr/bin/env bash
# link-dispatcher.sh -- record, in a message-path worker's own session, the
# coordinator run that dispatched it.
#
# A worker dispatched on a request leg is joined to its coordinator by the
# leg. One on the message path has none, so its brief (render-brief.sh) shows
# the command that records the coordinator run as its dispatcher. For
# /coordinate, /explore, /decision and /release that command is the entry
# point's own opener with --dispatched-by (coordinate-open.sh, skill-session.sh
# open). The openers of /scope, /deliver, /execute and /work-on take a
# dispatcher only through a leg, so a worker of theirs on the message path (a
# /work-on given a PLAN, or any worker a re-brief moved off its leg) runs this
# once its entry point has opened its session.
#
# It runs `koto session link <session> --dispatched-by <name>` through
# scripts/lib/dispatch-link.sh, the openers' shared code: a failed link is
# run once more, and a second failure prints
#   warning=link-failed dispatched_by=<name>
# and records it in the session's own key session/link-warning, which
# render-result.sh carries into the worker's result. Either way it exits 0:
# the session goes on, only outside the dispatcher's hierarchy.
#
# Usage:
#   link-dispatcher.sh <session> --dispatched-by <name>
#
#   <session>        the worker's own koto session
#   --dispatched-by  the coordinator run, any koto session name
#                    (^[A-Za-z0-9][A-Za-z0-9._-]*$, at most 200 bytes) other
#                    than <session>
#
# Output: nothing when the link is written, the warning line when it isn't.
#
# Exit codes: 0 linked, or warned and recorded; 2 no such session here; 64
# usage; 127 koto missing.
#
# Requires: bash 3.2+, koto. KOTO_BIN overrides the binary.
set -uo pipefail

PROG=link-dispatcher
HERE=$(cd "$(dirname "$0")" && pwd)
KOTO="${KOTO_BIN:-koto}"
# shellcheck source=../../../scripts/lib/dispatch-link.sh
. "$HERE/../../../scripts/lib/dispatch-link.sh" || exit 64

usage() { printf '%s: %s\n' "$PROG" "$1" >&2; exit 64; }

SESSION=""
DISPATCHER=""
HAVE=0
while [ $# -gt 0 ]; do
    case "$1" in
        --dispatched-by) [ $# -ge 2 ] || usage "--dispatched-by needs the dispatcher's session name"
                         HAVE=$((HAVE + 1)); DISPATCHER=$2; shift 2 ;;
        -*) usage "unknown option $1" ;;
        *) [ -z "$SESSION" ] || usage "expected one <session>"; SESSION=$1; shift ;;
    esac
done
[ -n "$SESSION" ] || usage "usage: $PROG <session> --dispatched-by <name>"
[ "$HAVE" -eq 1 ] || usage "--dispatched-by is required, once"
dl_valid_dispatcher "$SESSION" || usage "<session> must name a koto session, got [$SESSION]"
dl_valid_dispatcher "$DISPATCHER" \
    || usage "--dispatched-by must name a koto session: ^[A-Za-z0-9][A-Za-z0-9._-]*\$, at most 200 bytes, got [$DISPATCHER]"
[ "$DISPATCHER" != "$SESSION" ] || usage "--dispatched-by names $SESSION itself; a session is not its own dispatcher"
command -v "$KOTO" >/dev/null 2>&1 || { printf 'failed=koto_missing\n'; exit 127; }
# koto's own diagnostic, when the session isn't here, goes to stderr as it is.
"$KOTO" status "$SESSION" </dev/null >/dev/null \
    || { printf '%s: no session %s here; run this from the directory your session was opened in\n' "$PROG" "$SESSION" >&2; exit 2; }

# A failed link has printed its warning and recorded it; the session stands.
dl_link "$KOTO" "$SESSION" "$DISPATCHER" || true
exit 0
