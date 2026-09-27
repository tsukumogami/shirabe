#!/usr/bin/env bash
# coordinate-open.sh -- /coordinate's entry: the invocation's tokens to the
# session's variables, and a fresh per-run session.
#
# Every invocation is a new run. A restart after a crash gets its own session,
# its own start time (the session header's created_at), and a full start,
# find and reconcile; continuity lives on GitHub, where the new run's find
# adopts the record the previous run opened. So this script cancels (never
# cleans up) any live coordinate session for the same scope, keeping its log
# readable, and opens `coordinate-<scope-slug>-<UTC stamp>`.
#
# Tokens, in order, from a JSON array of strings in <args-file>:
#   <roadmap-path>               roadmap scope (docs/roadmaps/.../ROADMAP-<name>.md)
#   --discipline <name>          discipline scope
#   --host <owner/repo>          the record's host (discipline scope; at roadmap
#                                scope it is the repository this runs in)
#   --cap <n>, --parked-bound <n>, --rotation-days <n>
#   --                           everything after it is the human's decisions:
#                                shown to the coordinator, never a setting
# Values reach koto only through a vars file, mapped with jq; koto checks each
# against its variable's pattern and refuses a bad or repeated one at init,
# with no session left behind.
#
# Usage: coordinate-open.sh [--plugin-root <path>] <args-file>
# Prints koto-open.sh's result line, then `session=<name>` on success. At
# discipline scope with no --host it opens nothing and prints
# `ask=host`: ask the human once, with a recommendation, and re-invoke with
# --host. It never defaults to the repository it runs in there.
#
# Exit codes: 0 opened; 10 the human must name the host first; koto-open.sh's
# own codes otherwise (2 refused, 64 usage, 127 koto or jq missing).
set -uo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
KOTO_OPEN="$HERE/../../../scripts/koto-open.sh"
WORDING="$HERE/coordinate-open.wording.tsv"
KOTO="${KOTO_BIN:-koto}"

usage() { echo "coordinate-open: $1" >&2; exit 64; }

PLUGIN_ROOT=
ARGS_FILE=
while [ $# -gt 0 ]; do
    case "$1" in
        --plugin-root) [ $# -ge 2 ] || usage "--plugin-root needs a path"; PLUGIN_ROOT=$2; shift 2 ;;
        --*) usage "unknown option $1" ;;
        *) [ -z "$ARGS_FILE" ] || usage "expected one <args-file>"; ARGS_FILE=$1; shift ;;
    esac
done
[ -n "$ARGS_FILE" ] && [ -r "$ARGS_FILE" ] || usage "expected a readable <args-file>"
[ -n "$PLUGIN_ROOT" ] || PLUGIN_ROOT=$(cd "$HERE/../../.." && pwd)
command -v jq >/dev/null 2>&1 || { echo "failed=jq_missing"; exit 127; }

# Tokens before `--` are settings, each one variable pair (so a repeated flag
# reaches koto as a duplicate it refuses); tokens after it are decisions.
MAP='
if (type != "array") or (map(type == "string") | all | not) then error("not a JSON array of strings") else . end
| (index("--") // length) as $cut
| .[:$cut] as $s
| reduce range(0; $s | length) as $i ({pairs: [], skip: false, positional: [], bad: null};
    if .skip then .skip = false
    elif ($s[$i] | IN("--discipline", "--host", "--cap", "--parked-bound", "--rotation-days")) then
      if $i + 1 >= ($s | length) then .bad = "\($s[$i]) needs a value"
      else .skip = true
        | .pairs += [[({"--discipline": "DISCIPLINE", "--host": "HOST_REPO", "--cap": "CAP",
                        "--parked-bound": "PARKED_BOUND", "--rotation-days": "ROTATION_DAYS"})[$s[$i]], $s[$i + 1]]]
      end
    elif ($s[$i] | startswith("--")) then .bad = "unknown option \($s[$i])"
    else .positional += [$s[$i]] end)
'
MAPPED=$(jq -c "$MAP" < "$ARGS_FILE") || usage "the args file is not a JSON array of strings"
rm -f -- "$ARGS_FILE"
BAD=$(printf '%s' "$MAPPED" | jq -r '.bad // empty')
[ -z "$BAD" ] || usage "$BAD"

NPOS=$(printf '%s' "$MAPPED" | jq '.positional | length')
DISC=$(printf '%s' "$MAPPED" | jq -r '[.pairs[] | select(.[0] == "DISCIPLINE")] | length')
if [ "$DISC" -gt 0 ]; then
    [ "$NPOS" -eq 0 ] || usage "give a roadmap path or --discipline, not both"
    SCOPE=discipline
    NAME=$(printf '%s' "$MAPPED" | jq -r '[.pairs[] | select(.[0] == "DISCIPLINE")][0][1]')
    if [ "$(printf '%s' "$MAPPED" | jq '[.pairs[] | select(.[0] == "HOST_REPO")] | length')" -eq 0 ]; then
        echo "ask=host"
        echo "coordinate-open: a discipline's host repository is the human's decision; ask once, with a recommendation, then re-invoke with --host <owner/repo>" >&2
        exit 10
    fi
    EXTRA='[]'
else
    [ "$NPOS" -eq 1 ] || usage "expected one roadmap path, or --discipline <name>"
    SCOPE=roadmap
    ROADMAP=$(printf '%s' "$MAPPED" | jq -r '.positional[0]')
    NAME=$(basename -- "$ROADMAP" .md); NAME=${NAME#ROADMAP-}
    # The roadmap's record lives in the roadmap's own repository.
    HOST=$(bash "$HERE/../../execute/scripts/record-write-set.sh" --print 2>/dev/null) || HOST=
    [ -n "$HOST" ] || usage "could not read this repository's owner/repo from its origin remote"
    EXTRA=$(jq -nc --arg r "$ROADMAP" --arg h "$HOST" '[["ROADMAP", $r], ["HOST_REPO", $h]]')
fi

SLUG=$(printf '%s-%s' "$SCOPE" "$NAME" | tr '[:upper:]' '[:lower:]' | tr -c 'a-z0-9-\n' '-' | tr -s '-')
SLUG=${SLUG%-}
SESSION="coordinate-$SLUG-$(date -u +%Y%m%dT%H%M%SZ)"
TEMPLATE="$PLUGIN_ROOT/skills/coordinate/koto-templates/coordinate.md"

DIR=$(bash "$KOTO_OPEN" --alloc-dir) || usage "could not allocate a vars directory"
printf '%s' "$MAPPED" | jq -c --arg scope "$SCOPE" --arg root "$PLUGIN_ROOT" --argjson extra "$EXTRA" \
    '[["SCOPE", $scope]] + .pairs + $extra + [["PLUGIN_ROOT", $root]]' > "$DIR/coordinate-vars.json"
OUT=$(bash "$KOTO_OPEN" "$SESSION" "$TEMPLATE" "$DIR/coordinate-vars.json" --wording "$WORDING")
RC=$?
[ -n "$OUT" ] && printf '%s\n' "$OUT"
[ $RC -eq 0 ] || exit $RC

# Only once the new run is open (so a refused invocation leaves the live run
# alone): cancel, never clean up, every other live run of this scope, so its
# log stays readable.
for id in $("$KOTO" session list | jq -r --arg p "coordinate-$SLUG-" '.[] | select(.parent_workflow == null) | .id | select(startswith($p) and (.[($p | length):] | test("^[0-9]{8}T[0-9]{6}Z$")))'); do
    [ "$id" = "$SESSION" ] && continue
    [ "$("$KOTO" status "$id" | jq -r '.is_terminal')" = false ] || continue
    LOG="$("$KOTO" session dir "$id" 2>/dev/null)/koto-$id.state.jsonl"
    jq -e 'select(.type == "workflow_cancelled")' "$LOG" >/dev/null && continue
    "$KOTO" cancel "$id" </dev/null >/dev/null 2>&1 || { echo "failed=cancel"; echo "coordinate-open: could not cancel the live run $id" >&2; exit 1; }
    echo "cancelled=$id"
done
printf 'session=%s\n' "$SESSION"
exit 0
