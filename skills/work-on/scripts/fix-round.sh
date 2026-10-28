#!/usr/bin/env bash
# fix-round.sh -- for /work-on: start a fix round for a run that already
# reached `done`, as a fresh work-on session on the same branch.
#
# `done` is terminal, and koto gives a terminal state no transitions, so a run
# there can't go back to implementation. `koto rewind` doesn't reopen it
# either: from `done` it steps back to `pr_creation`, and the next tick returns
# to `done` (#1322). A fix that review or CI asks for after `done` is taken by
# a new session instead, started here. It is the same template with the same
# variables and the same parent, so it routes as the original did (a child of
# /execute stays a child and never cascades), and it starts from the head the
# original left: `analysis` records that head as its `impl_base`, so the
# round's changed paths, review packet and panels cover the fix commits only,
# and its verification runs at the fix head.
#
# Usage: fix-round.sh start --from <session>
#
#   --from   the run that reached `done`, or one of its fix rounds, which
#            resolves to the run it was started for. Rounds are counted
#            against that original run, never nested.
#
# Refused (exit 1, a `refused=<reason>` line on stdout, nothing written):
#
#   not-done         the original isn't at `done`. A run at `done_blocked`
#                    walks back with `koto rewind`, as its directive says.
#   round-open       the last fix round hasn't reached a terminal state. One
#                    round at a time: finish it, or end it, first.
#   cap              three rounds already ran. A fourth is a person's call.
#
# Started (exit 0): prints `session=<original>-fix-<n>` and `round=<n>`. The
# new session's context has `fix_round.json` ({from, round, base}), and the
# original's context has `fix_rounds.jsonl`, one line per round started
# ({round, session, base, ts}), so the run that reached `done` names every
# round whose review and verification were recorded for it. `base` is HEAD as
# the round starts. The agent then drives the new session from `entry` with
# the entry evidence the original was given.
#
# The variables are the original's, read from the first initialization in its
# own state log, except REVIEW_LEVEL and UNIT_KIND, which the round chooses
# and determines again, and PLUGIN_ROOT, which is this plugin's. Empty values
# are left out, so each takes the template's default. The template is this
# plugin's work-on.md, not the path the original recorded, which a plugin
# update may have removed.
#
# Environment (tests only):
#   FIX_ROUND_TEMPLATE  the template the round is started from; default
#                       ../koto-templates/work-on.md beside this script.
#
# Exit codes:
#   0  -- the round was started and recorded
#   1  -- refused (see above)
#   2  -- a koto call or a read of the original's log failed; nothing was
#         started, unless the message says the round started and only its
#         record failed
#   64 -- usage
#
# Bash 3.2: no associative arrays, no mapfile.
set -uo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
SKILL_DIR=$(cd "$SCRIPT_DIR/.." && pwd)
PLUGIN_ROOT_SELF=$(cd "$SKILL_DIR/../.." && pwd)
TEMPLATE="${FIX_ROUND_TEMPLATE:-$SKILL_DIR/koto-templates/work-on.md}"

ROUND_KEY=fix_round.json
ROUNDS_KEY=fix_rounds.jsonl
CAP=3
RE_SESSION='^[A-Za-z0-9._-]+$'

usage() { sed -n '/^# Usage:/p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 64; }
die() { echo "fix-round: $2" >&2; exit "$1"; }
refuse() { echo "refused=$1"; echo "fix-round: $2" >&2; exit 1; }

[ $# -eq 3 ] && [ "$1" = start ] && [ "$2" = --from ] || usage
FROM=$3
[[ $FROM =~ $RE_SESSION ]] || usage

command -v koto >/dev/null 2>&1 || die 2 "koto is not on PATH"
command -v jq >/dev/null 2>&1 || die 2 "jq is not on PATH"
[ -r "$TEMPLATE" ] || die 2 "template not found: $TEMPLATE"

# A round names the run it was started for; a round started from a round
# counts against that run.
ORIG=$FROM
if koto context exists "$FROM" "$ROUND_KEY" 2>/dev/null; then
    ORIG=$(koto context get "$FROM" "$ROUND_KEY" | jq -r '.from // empty') \
        || die 2 "could not read $ROUND_KEY from $FROM"
    [[ $ORIG =~ $RE_SESSION ]] || die 2 "$ROUND_KEY in $FROM names no run"
fi

STATUS=$(koto status "$ORIG") || die 2 "could not read the status of $ORIG"
STATE=$(printf '%s' "$STATUS" | jq -r '.current_state // empty')
[ "$STATE" = done ] || refuse not-done "$ORIG is at ${STATE:-an unknown state}, not done"

ROUNDS=""
if koto context exists "$ORIG" "$ROUNDS_KEY" 2>/dev/null; then
    ROUNDS=$(koto context get "$ORIG" "$ROUNDS_KEY") || die 2 "could not read $ROUNDS_KEY from $ORIG"
fi
COUNT=$(printf '%s' "$ROUNDS" | jq -s 'length') || die 2 "$ROUNDS_KEY in $ORIG is not JSON lines"
if [ "$COUNT" -gt 0 ]; then
    LAST=$(printf '%s' "$ROUNDS" | jq -rs '.[-1].session // empty')
    [[ $LAST =~ $RE_SESSION ]] || die 2 "the last line of $ROUNDS_KEY in $ORIG names no session"
    TERMINAL=$(koto status "$LAST" | jq -r '.is_terminal') || die 2 "could not read the status of $LAST"
    [ "$TERMINAL" = true ] || refuse round-open "fix round $LAST is still open; finish or end it before starting another"
fi
[ "$COUNT" -lt "$CAP" ] || refuse cap "$ORIG has had $COUNT fix rounds; a fourth is a person's call"

N=$((COUNT + 1))
NAME="$ORIG-fix-$N"
BASE=$(git rev-parse --verify -q "HEAD^{commit}") || die 2 "HEAD does not name a commit"

DIR=$(koto session dir "$ORIG") || die 2 "could not locate the session directory of $ORIG"
LOG="$DIR/koto-$ORIG.state.jsonl"
[ -r "$LOG" ] || die 2 "could not read the state log of $ORIG"
VARS=$(jq -sc '[.[] | select(.type == "workflow_initialized")][0].payload.variables // {}' "$LOG") \
    || die 2 "could not read the variables of $ORIG from its state log"
PARENT=$(koto session list | jq -r --arg s "$ORIG" 'map(select(.id == $s))[0].parent_workflow // empty') \
    || die 2 "could not read the parent of $ORIG"

ARGS=(init "$NAME" --template "$TEMPLATE")
[ -n "$PARENT" ] && ARGS+=(--parent "$PARENT")
while IFS= read -r kv; do
    [ -n "$kv" ] && ARGS+=(--var "$kv")
done < <(printf '%s' "$VARS" | jq -r '
    to_entries[]
    | select(.key != "REVIEW_LEVEL" and .key != "UNIT_KIND" and .key != "PLUGIN_ROOT")
    | select((.value | tostring) != "")
    | "\(.key)=\(.value)"')
ARGS+=(--var "PLUGIN_ROOT=$PLUGIN_ROOT_SELF")

# koto's compile warnings about the template are the template's, not the
# round's; its stderr is shown only when the init fails.
if ! ERR=$(koto "${ARGS[@]}" 2>&1 >/dev/null); then
    printf '%s\n' "$ERR" >&2
    die 2 "koto init $NAME failed"
fi

TS=$(date -u +%Y-%m-%dT%H:%M:%SZ)
jq -nc --arg from "$ORIG" --argjson round "$N" --arg base "$BASE" \
    '{from: $from, round: $round, base: $base}' | koto context add "$NAME" "$ROUND_KEY" >/dev/null \
    || die 2 "the round $NAME started, but $ROUND_KEY could not be stored in it"
{ [ -n "$ROUNDS" ] && printf '%s\n' "$ROUNDS"
  jq -nc --argjson round "$N" --arg session "$NAME" --arg base "$BASE" --arg ts "$TS" \
      '{round: $round, session: $session, base: $base, ts: $ts}'
} | koto context add "$ORIG" "$ROUNDS_KEY" >/dev/null \
    || die 2 "the round $NAME started, but $ROUNDS_KEY could not be stored in $ORIG"

echo "session=$NAME"
echo "round=$N"
