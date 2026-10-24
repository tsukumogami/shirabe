#!/usr/bin/env bash
# teardown-verdict.sh -- read the teardown inventory's sealed verdict.
#
# teardown-inventory.sh --seal runs as the teardown_inventory state's default action and
# seals its verdict in the context key `teardown_verdict` through the record
# feature's coord-log.sh, which the state captures as TEARDOWN_SEAL. This
# script and the record feature's state-confirm.sh (which takes the topic
# from it) read that verdict, each only through the seal check, so a verdict edited after sealing, or a seal from another state
# entry or another session, never reads as durable. The captured token is
# read from the session's own log, never taken as an argument.
#
# Modes:
#
#   gate --session <s> [--absent-route]
#       The teardown_inventory state's gate (overridable: false). Exit 0 only when the
#       seal checks and the verdict is durable. An `absent` verdict (niwa
#       lists no instance for the topic) answers 2, the error route, unless
#       --absent-route is given: then the latest `teardown` evidence of this
#       visit to teardown, read from the session's own log through
#       coord-log.sh, decides it: 5 after `teardown: removed` (the unit was
#       torn down outside the pass; on to the handoff's removed mode), 6
#       after `teardown: stopped` (nothing was there to stop; back to
#       teardown), 2 for anything else. Only a template that knows the two
#       routes passes the flag, so a coordinator still running a template
#       compiled before them keeps exit 2 for an absent instance.
#
#   read --session <s>
#       Run by teardown-handoff.sh before it seals the pass's verdict. Prints
#       the verdict, whose `instance <path>` line is the one instance the
#       pass may destroy, when the seal checks, the verdict is durable, and
#       the session log shows no directed transition (`koto next --to`,
#       which skips gates; koto#251) since the sealed teardown_inventory
#       entry. An `absent` verdict is printed only when the handoff's own
#       sealed verdict for this visit says `removed yes`; until then it is
#       exit 5, which is where the handoff's removed mode starts. Refuses
#       otherwise.
#
# Exit codes:
#   0  durable (or, read, an absent verdict a removed handoff admits), and
#      (read) reached without a directed transition
#   1  the verdict says unique
#   2  the verdict says error, a read failed, or (gate) absent with no
#      --absent-route or no removed or stopped evidence to route it by
#   3  the seal doesn't check (the verdict was changed, or it isn't this
#      state entry's), or it covers a topic other than teardown_topic
#   4  (read) a directed transition since the teardown entry: refuse to destroy
#   5  (gate --absent-route) absent after `teardown: removed`; (read) absent,
#      and no sealed handoff of this visit says `removed yes`
#   6  (gate --absent-route) absent after `teardown: stopped`
#
# Read-only. bash 3.2.
set -uo pipefail

PROG=teardown-verdict
HERE=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=dispatch-common.sh
. "$HERE/dispatch-common.sh"

KOTO="${KOTO:-koto}"

usage() { printf 'usage: %s gate|read --session <s> [--absent-route]\n' "$PROG" >&2; exit 2; }

MODE="${1:-}"
[ $# -gt 0 ] && shift
SESSION=""
ABSENT_ROUTE=0
while [ $# -gt 0 ]; do
    case "$1" in
        --session) [ $# -ge 2 ] || usage; SESSION="$2"; shift 2 ;;
        --absent-route) ABSENT_ROUTE=1; shift ;;
        *) usage ;;
    esac
done
[ -n "$SESSION" ] || usage
case "$MODE" in gate | read) ;; *) usage ;; esac
[ "$MODE" = read ] && [ "$ABSENT_ROUTE" = 1 ] && usage

CAPTURED=$(dc_capture "$SESSION" TEARDOWN_SEAL) || { printf '%s: cannot read the TEARDOWN_SEAL capture\n' "$PROG" >&2; exit 2; }
# The capture is the bare token `sealed:<seq>:<sha256>`; any text around it
# is ignored, and only the token is checked. The verdict is read from the
# sealed bytes, never from the capture.
TOKEN=$(printf '%s' "$CAPTURED" | grep -Eo 'sealed:[0-9]+:[0-9a-f]{64}' | tail -1)
[ -n "$TOKEN" ] || { printf '%s: TEARDOWN_SEAL holds no seal\n' "$PROG" >&2; exit 3; }

VERDICT=$(dc_seal_check "$SESSION" teardown_inventory "$TOKEN" teardown_verdict)
case "$?" in
    0) ;;
    1) printf '%s: the teardown verdict does not match its seal\n' "$PROG" >&2; exit 3 ;;
    *) printf '%s: the teardown verdict could not be read\n' "$PROG" >&2; exit 2 ;;
esac

# The sealed verdict opens with the word, `instance <path>` and `topic <t>`.
WORD=$(printf '%s\n' "$VERDICT" | sed -n 1p)
SEALED_TOPIC=$(sed -n '/^topic /{s///p;q;}' <<<"$VERDICT")
# The verdict covers the topic it was taken for: teardown_topic rewritten
# after the seal can't point the destroy at another worker.
NOW_TOPIC=$("$KOTO" context get "$SESSION" teardown_topic) || { printf '%s: cannot read teardown_topic\n' "$PROG" >&2; exit 2; }
if [ -z "$SEALED_TOPIC" ] || [ "$SEALED_TOPIC" != "$NOW_TOPIC" ]; then
    printf '%s: the sealed verdict covers [%s], but teardown_topic is [%s]\n' "$PROG" "$SEALED_TOPIC" "$NOW_TOPIC" >&2
    exit 3
fi
case "$WORD" in
    durable) ;;
    unique) printf '%s\n' "$VERDICT" >&2; exit 1 ;;
    absent) ;;
    *) printf '%s\n' "$VERDICT" >&2; exit 2 ;;
esac

# gate on absent: route it by the coordinator's own latest teardown evidence,
# read from the log, never from an argument.
if [ "$MODE" = gate ] && [ "$WORD" = absent ]; then
    [ "$ABSENT_ROUTE" = 1 ] || { printf '%s\n' "$VERDICT" >&2; exit 2; }
    ENT=$(bash "$DC_COORD_LOG" entry --session "$SESSION" --state teardown) \
        || { printf '%s: absent, and the session log has no readable entry into teardown\n' "$PROG" >&2; exit 2; }
    EV=$(bash "$DC_COORD_LOG" evidence --session "$SESSION" --state teardown --after "${ENT%% *}") \
        || { printf '%s: absent, and no teardown evidence at the latest visit to teardown\n' "$PROG" >&2; exit 2; }
    case "$(printf '%s' "$EV" | jq -r '.fields.teardown // ""')" in
        removed) printf '%s: absent after teardown: removed\n' "$PROG" >&2; exit 5 ;;
        stopped) printf '%s: absent after teardown: stopped; niwa lists no instance for the topic\n' "$PROG" >&2; exit 6 ;;
        *) printf '%s: absent, and the latest teardown evidence is neither removed nor stopped\n' "$PROG" >&2; exit 2 ;;
    esac
fi

if [ "$MODE" = read ]; then
    SEQ=$(printf '%s' "$TOKEN" | cut -d: -f2)
    dc_directed_since "$SESSION" "$SEQ"
    case "$?" in
        0) ;;
        1) printf '%s: a directed transition moved this run since the teardown inventory; refusing to destroy\n' "$PROG" >&2; exit 4 ;;
        *) printf '%s: the session log could not be read for directed transitions\n' "$PROG" >&2; exit 2 ;;
    esac
    if [ "$WORD" = absent ]; then
        # An absent verdict names no instance, so on its own it admits
        # nothing. It stands only beside the handoff's sealed verdict for
        # this visit saying the unit was removed outside the pass; that
        # reader checks its own seal, topic and directed transitions.
        if ! HV=$(bash "$HERE/teardown-handoff.sh" read --session "$SESSION" 2>/dev/null) \
            || ! grep -qx 'removed yes' <<<"$HV"; then
            printf '%s: the instance is absent, and no sealed handoff of this visit says it was removed\n' "$PROG" >&2
            exit 5
        fi
    fi
    printf '%s\n' "$VERDICT"
fi
exit 0
