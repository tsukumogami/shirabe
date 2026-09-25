#!/usr/bin/env bash
# deliver-open-request.sh -- the default action of /deliver's `open_request`:
# supersede this topic's earlier requests, open this run's, print its id.
#
# Each /deliver invocation opens one koto request with two legs, `scope` and
# `execute`, and reads its children's results only from those legs. The
# request id is the stale-run fence: before the new request is created, every
# request still open under this run's coordinator (`deliver-<topic>`) is
# abandoned with `koto request abandon-request`, which abandons its open legs
# and closes it. A child still bound to one of them is released for
# re-attachment, and a late result from it is refused at promotion. Requests
# under any other coordinator -- another topic's /deliver, or any other
# workflow -- are never read or touched.
#
# The legs:
#
#   scope    role scope,   template scope.md,
#            inputs {TOPIC: <topic>, INTENT_FLAG: continue}
#   execute  role execute, template [execute.md, execute-coordinated.md],
#            inputs {PLAN_SLUG: <topic>}
#
# The request is created before the PLAN's mode is known, so the execute leg
# names both of /execute's templates; the single-pr versus coordinated
# mismatch is caught by --attach-live's template check on the execute-<topic>
# session itself.
#
# It touches only koto's local request store: no git, no gh. Safe to re-run:
# a second run abandons the request the first created and opens another.
#
# Usage:
#   deliver-open-request.sh --topic <slug>
#
# Output: the new request id, alone on stdout (the template captures it as
# REQ). Diagnostics on stderr.
#
# Exit codes:
#   0   created; the id is on stdout
#   1   a koto request call failed, or printed no usable id
#   64  usage error; nothing read or written
#
# Environment: KOTO_BIN, the koto binary (default `koto`).
#
# Requires: bash 3.2+, jq, koto.
set -uo pipefail

PROG=deliver-open-request
RE_TOPIC='^[a-z0-9][a-z0-9-]*$'
RE_REQ='^[a-z0-9_][a-z0-9_-]{0,63}$'
KOTO="${KOTO_BIN:-koto}"

usage() {
    printf '%s: %s\n' "$PROG" "$1" >&2
    printf 'usage: deliver-open-request.sh --topic <slug>\n' >&2
    exit 64
}

TOPIC=""; SEEN=0
while [ "$#" -gt 0 ]; do
    case "$1" in
        --topic) [ "$#" -ge 2 ] || usage "--topic needs a value"; TOPIC="$2"; SEEN=$((SEEN + 1)); shift ;;
        *) usage "unknown argument: $1" ;;
    esac
    shift
done
[ "$SEEN" -eq 1 ] || usage "--topic is required once"
[[ "$TOPIC" =~ $RE_TOPIC ]] || usage "--topic [$TOPIC] does not match $RE_TOPIC"
command -v jq >/dev/null || { printf '%s: jq is not on PATH\n' "$PROG" >&2; exit 1; }
command -v "$KOTO" >/dev/null || { printf '%s: koto is not on PATH\n' "$PROG" >&2; exit 1; }

COORD="deliver-$TOPIC"

# --- supersede ---------------------------------------------------------------

LIST=$("$KOTO" request list --coordinator-of-record "$COORD" --state open </dev/null) || {
    printf '%s: koto request list failed\n' "$PROG" >&2
    exit 1
}
# Filter by coordinator again here rather than trusting the flag alone: a
# request under any other coordinator is never abandoned.
OLD=$(printf '%s' "$LIST" | jq -r --arg c "$COORD" '
    (.requests // [])[] | select(.coordinator_of_record == $c and .request_state == "open") | .request_id') || {
    printf '%s: koto request list printed something unreadable\n' "$PROG" >&2
    exit 1
}
while IFS= read -r id; do
    [ -n "$id" ] || continue
    if ! [[ "$id" =~ $RE_REQ ]]; then
        printf '%s: skipping a request id outside the pattern\n' "$PROG" >&2
        continue
    fi
    "$KOTO" request abandon-request "$id" \
        --rationale "superseded by a newer /deliver run on $TOPIC" </dev/null >/dev/null || {
        printf '%s: could not abandon the earlier request %s\n' "$PROG" "$id" >&2
        exit 1
    }
done <<EOF
$OLD
EOF

# --- create ------------------------------------------------------------------

DATA=$(jq -nc --arg t "$TOPIC" '{legs: [
    {name: "scope", role: "scope", template: "scope.md",
     inputs: {TOPIC: $t, INTENT_FLAG: "continue"}},
    {name: "execute", role: "execute", template: ["execute.md", "execute-coordinated.md"],
     inputs: {PLAN_SLUG: $t}}]}')

OUT=$("$KOTO" request create --with-data "$DATA" \
    --requested-by "$COORD" --coordinator-of-record "$COORD" </dev/null) || {
    printf '%s: koto request create failed\n' "$PROG" >&2
    exit 1
}
ID=$(printf '%s' "$OUT" | jq -r '.request_id // "" | strings')
if ! [[ "$ID" =~ $RE_REQ ]]; then
    printf '%s: koto request create printed no usable request id\n' "$PROG" >&2
    exit 1
fi
printf '%s\n' "$ID"
exit 0
