#!/usr/bin/env bash
# render-result.sh -- render a message-path worker's result, the block its
# final report ends with.
#
# A worker on the message path has no request leg to carry its result, so the
# coordinator reads the result from the worker's report. The brief's Reporting
# section (render-brief.sh) names this script as the report step, and the
# worker runs it from its own session's directory when it reports its result.
# It reads the worker's own session, never the coordinator's, and the
# coordinator never reads the worker's keys: what this prints is how the
# coordinator learns of anything below, so no read is recorded into the
# worker's session from the coordinator's side.
#
# What it carries: the worker's review round, when its session holds one
# (review-round.sh stores it as review_round.json), as one
# `review_round=<the round as compact JSON>` line. The land step reads the
# round from that line in the report the coordinator submitted (board-lib.sh's
# bl_review_evidence), so a worker with no leg, or whose session the
# coordinator's host can't read, lands with no table in its pull request body.
# A round that isn't JSON is refused here (exit 2) rather than carried.
#
# And when the worker's opener could not record which coordinator
# run dispatched it (scripts/lib/dispatch-link.sh, after two attempts), the
# opener left the key session/link-warning in the worker's session, one
# dispatched_by=<name> line per dispatcher under a warning=link-failed line.
# The result carries one `warning=link-failed dispatched_by=<name>` line for
# each, so the coordinator knows the worker sits outside its hierarchy (koto
# may reclaim it on its own schedule). With no such key the result has no
# warning line. Nothing in a skill's text asks the worker to pass the warning
# on: this script does.
#
# And, given the brief's dispatcher_session, where the report goes: the
# script runs resolve-coordinator.sh on it, and the result carries the newest
# run member's address as `coordinator=<name>`, so a worker started again
# after takeovers sends its result to the run's newest member. When the
# resolver can't say (exit 1 or 3), the result carries no such line and the
# worker sends it to its brief's address; the block is printed either way.
#
# Usage:
#   render-result.sh --session <session> [--dispatcher <session>] [--pr <url>]...
#
#   --session     the worker's own koto session, the one its opener opened
#   --dispatcher  the brief's dispatcher_session, the run member that
#                 dispatched the worker
#   --pr          a pull request the worker opened, an https URL; repeatable
#
# Output, on stdout:
#   === RESULT ===
#   session=<session>
#   coordinator=<name>                           (with --dispatcher, resolved)
#   pr=<url>                                     (one per --pr)
#   review_round=<json>                          (when the session holds one)
#   warning=link-failed dispatched_by=<name>     (one per recorded dispatcher)
#   === END RESULT ===
#
# Exit codes: 0 rendered; 2 the session doesn't exist, or its round or warning
# key couldn't be read, or its round isn't JSON (nothing printed); 64 usage;
# 127 koto or jq missing.
#
# Requires: bash 3.2+, koto, jq. KOTO_BIN overrides the koto binary.
set -uo pipefail

PROG=render-result
KOTO="${KOTO_BIN:-koto}"
KEY="session/link-warning"
RE_NAME='^[A-Za-z0-9][A-Za-z0-9._-]*$'
RE_URL='^https://[^[:space:]]+$'

usage() { printf '%s: %s\n' "$PROG" "$1" >&2; exit 64; }

SESSION=""
DISPATCHER=""
PRS=()
while [ $# -gt 0 ]; do
    case "$1" in
        --session) [ $# -ge 2 ] || usage "--session needs the worker's session name"
                   [ -z "$SESSION" ] || usage "--session given more than once"
                   SESSION=$2; shift 2 ;;
        --dispatcher) [ $# -ge 2 ] || usage "--dispatcher needs the brief's dispatcher_session"
                      [ -z "$DISPATCHER" ] || usage "--dispatcher given more than once"
                      [[ $2 =~ $RE_NAME ]] || usage "--dispatcher must name a koto session, got [$2]"
                      DISPATCHER=$2; shift 2 ;;
        --pr) [ $# -ge 2 ] || usage "--pr needs a pull request URL"
              [[ $2 =~ $RE_URL ]] || usage "--pr takes an https URL, got [$2]"
              PRS+=("$2"); shift 2 ;;
        *) usage "unknown argument $1; usage: $PROG --session <session> [--dispatcher <session>] [--pr <url>]..." ;;
    esac
done
[ -n "$SESSION" ] || usage "--session is required"
[[ $SESSION =~ $RE_NAME ]] || usage "--session must name a koto session, got [$SESSION]"
command -v "$KOTO" >/dev/null 2>&1 || { printf 'failed=koto_missing\n'; exit 127; }
command -v jq >/dev/null 2>&1 || { printf 'failed=jq_missing\n'; exit 127; }

# koto's own diagnostics go to stderr as they are, beside this script's.
"$KOTO" status "$SESSION" </dev/null >/dev/null \
    || { printf '%s: no session %s here; run this from the directory your session was opened in\n' "$PROG" "$SESSION" >&2; exit 2; }
ROUND=""
"$KOTO" context exists "$SESSION" review_round.json </dev/null >/dev/null
case $? in
    0) VALUE=$("$KOTO" context get "$SESSION" review_round.json </dev/null) \
           || { printf '%s: could not read review_round.json from %s\n' "$PROG" "$SESSION" >&2; exit 2; }
       # jq's own parse error, if any, goes to stderr beside this script's.
       ROUND=$(printf '%s' "$VALUE" | jq -c .) && [ -n "$ROUND" ] && [ "$(printf '%s\n' "$ROUND" | wc -l | tr -d ' ')" = 1 ] \
           || { printf '%s: review_round.json in %s is not one JSON value\n' "$PROG" "$SESSION" >&2; exit 2; } ;;
    1) ;;
    *) printf '%s: could not read review_round.json from %s\n' "$PROG" "$SESSION" >&2; exit 2 ;;
esac
WARNINGS=""
"$KOTO" context exists "$SESSION" "$KEY" </dev/null >/dev/null
case $? in
    0) VALUE=$("$KOTO" context get "$SESSION" "$KEY" </dev/null) \
           || { printf '%s: could not read %s from %s\n' "$PROG" "$KEY" "$SESSION" >&2; exit 2; }
       WARNINGS=$(printf '%s\n' "$VALUE" | sed -n 's/^dispatched_by=\(.*\)$/warning=link-failed dispatched_by=\1/p') ;;
    1) ;;
    *) printf '%s: could not read %s from %s\n' "$PROG" "$KEY" "$SESSION" >&2; exit 2 ;;
esac

ADDR=""
if [ -n "$DISPATCHER" ]; then
    # The resolver's own reason, when it can't say, goes to stderr as it is.
    ADDR=$(bash "$(dirname "$0")/resolve-coordinator.sh" "$DISPATCHER" </dev/null | sed -n 's/^coordinator=//p')
fi

printf '=== RESULT ===\n'
printf 'session=%s\n' "$SESSION"
[ -z "$ADDR" ] || printf 'coordinator=%s\n' "$ADDR"
for pr in ${PRS[@]+"${PRS[@]}"}; do printf 'pr=%s\n' "$pr"; done
[ -z "$ROUND" ] || printf 'review_round=%s\n' "$ROUND"
[ -z "$WARNINGS" ] || printf '%s\n' "$WARNINGS"
printf '=== END RESULT ===\n'
exit 0
