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
# /execute stays a child and never cascades). Its `analysis` records HEAD as
# its `impl_base`, so the fix is committed in the round's `implementation`, not
# before: the round's changed paths, review packet and panels then cover the
# fix commits only, and its verification runs at the fix head. A fix committed
# earlier falls before the base and out of the round's review.
#
# Why a new session rather than an edge out of `done`: an edge needs `done` to
# stop being terminal, and a terminal `done` is what /execute's
# children-complete gate counts as a finished child and what koto promotes to
# a caller's leg as the run's result. A round under the same parent counts in
# that gate too while it runs, so a round that ends at `done_blocked` is the
# parent's failure as well.
#
# Usage: fix-round.sh start --from <session> [--fresh] [--fix-report <text>]
#
#   --fix-report  the round's own report: the CI failure or review finding
#            that caused it. It becomes the round's FIX_REPORT in place of the
#            run's, so fix_determination records the round as a fix (source
#            `step`) and stores the text as its fix_report.txt, the passage a
#            red is found in. koto's variable allowlist applies: it starts
#            with a letter or digit and holds only letters, digits, spaces and
#            . _ / : @ + -; anything else is a usage error (exit 64) before
#            anything starts. Without it the round copies the run's
#            FIX_REPORT, empty or not.
#
#   --from   the run that reached `done`, or one of its fix rounds, which
#            resolves to the run it was started for. Rounds are counted
#            against that original run, never nested.
#   --fresh  carry nothing from the run the round follows: no verdicts are
#            inherited, so every panel of the round reviews in full, and
#            `fresh: true` is written into the round's fix_round.json, so its
#            verification runs every selected check rather than carrying the
#            ones that run passed (run-verification.sh's header).
#
# Refused (exit 1, a `refused=<reason>` line on stdout, nothing written):
#
#   not-done         the original isn't at `done`. A run at `done_blocked`
#                    walks back with `koto rewind`, as its directive says.
#   round-open       the last fix round hasn't reached a terminal state. One
#                    round at a time: finish it, or end it, first. Two open
#                    rounds on one branch would each take the other's commits
#                    as their own fix.
#   cap              three rounds already ran. A fourth is a person's call,
#                    the same three the repository's other retry caps allow.
#   wrong-branch     the run worked on /execute's shared branch (SHARED_BRANCH)
#                    and HEAD is on another, so the round would start from a
#                    head that isn't the one the run left.
#
# The round inherits the verdicts already given. The ledger of the run the
# round follows (the last earlier round, else the original run) is copied into
# the round as its `verdict_ledger.json`, with `inherited` set to {from, base,
# criteria_sha}, when every commit the ledger recorded is an ancestor of the
# round's base: the panels judged the head the round starts from, or an
# ancestor of it. panel-scope.sh then judges the round's fix as a fix diff
# from the panels' last judged commit, so a small fix gets the re-verifier and
# the fix-diff review rather than every seat, and a fix over its line
# threshold still gets every seat. A ledger that recorded a commit the base
# doesn't contain (a rebase or a reset since) is not inherited, nor is one
# that can't be read; nothing is inherited with --fresh. Either way the round
# reviews in full, as a round without a ledger always did.
# `inherited=<session>` or `inherited=none` says which.
#
# Started (exit 0): prints `session=<original>-fix-<n>`, `round=<n>` and the
# `inherited=` line. The
# new session's context has `fix_round.json` ({from, round, base}, and
# `fresh: true` under --fresh), and the
# original's context has `fix_rounds.jsonl`, one line per round started
# ({round, session, base, ts}), so the run that reached `done` names every
# round whose review and verification were recorded for it. `base` is HEAD as
# the round starts. The agent then drives the new session from `entry` with
# the entry evidence the original was given.
#
# The variables are the original's, read from the first initialization in its
# own state log, with three exceptions. REVIEW_LEVEL and UNIT_KIND are left
# out, since the round chooses and determines them again. PLUGIN_ROOT is this
# plugin's. PLAN_DOC is the parent's plan_abs when the parent records one that
# differs (see the block above the init below). Empty values
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

LEDGER_KEY=verdict_ledger.json
CRITERIA_KEY=review_level_criteria.txt
FRESH=0
[ $# -ge 3 ] && [ "$1" = start ] && [ "$2" = --from ] || usage
FROM=$3
shift 3
OWN_REPORT=""
HAVE_REPORT=0
while [ $# -gt 0 ]; do
    case "$1" in
        --fresh) [ "$FRESH" = 0 ] || usage; FRESH=1; shift ;;
        --fix-report)
            [ $# -ge 2 ] && [ "$HAVE_REPORT" = 0 ] || usage
            OWN_REPORT=$2; HAVE_REPORT=1; shift 2 ;;
        *) usage ;;
    esac
done
[[ $FROM =~ $RE_SESSION ]] || usage
# koto takes a variable value only inside its allowlist, so a report outside
# it is refused here, before anything starts, rather than by koto init.
RE_REPORT='^[a-zA-Z0-9][a-zA-Z0-9._/:@+ -]*$'
if [ "$HAVE_REPORT" = 1 ] && ! [[ $OWN_REPORT =~ $RE_REPORT ]]; then
    echo "fix-round: --fix-report must start with a letter or digit and hold only letters, digits, spaces and . _ / : @ + -" >&2
    exit 64
fi

command -v koto >/dev/null || die 2 "the koto CLI is not on PATH"
command -v jq >/dev/null || die 2 "the jq CLI is not on PATH"
[ -r "$TEMPLATE" ] || die 2 "template not found: $TEMPLATE"

# A round names the run it was started for; a round started from a round
# counts against that run.
ORIG=$FROM
if koto context exists "$FROM" "$ROUND_KEY"; then
    ORIG=$(koto context get "$FROM" "$ROUND_KEY" | jq -r '.from // empty') \
        || die 2 "could not read $ROUND_KEY from $FROM"
    [[ $ORIG =~ $RE_SESSION ]] || die 2 "$ROUND_KEY in $FROM names no run"
fi

STATUS=$(koto status "$ORIG") || die 2 "could not read the status of $ORIG"
STATE=$(printf '%s' "$STATUS" | jq -r '.current_state // empty')
[ "$STATE" = done ] || refuse not-done "$ORIG is at ${STATE:-an unknown state}, not done"

ROUNDS=""
if koto context exists "$ORIG" "$ROUNDS_KEY"; then
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

SHARED=$(printf '%s' "$VARS" | jq -r '.SHARED_BRANCH // empty')
if [ -n "$SHARED" ]; then
    CURRENT=$(git rev-parse --abbrev-ref HEAD) || die 2 "could not read the current branch"
    [ "$CURRENT" = "$SHARED" ] || refuse wrong-branch "$ORIG worked on $SHARED, and HEAD is on $CURRENT"
fi

# A plan-backed child's PLAN_DOC is the parent's plan_abs as it was when the
# child was opened. When the parent's checkout has moved since, its plan_abs was
# re-rooted (record-coord-setup.sh --reroot-plan), and the round reads the PLAN
# there. The parent is read in the directory it is bound to, since a session
# answers only there; a unit with no plan never reads it. A parent bound to a
# directory that no longer exists is refused rather than read from here, where
# it could look like a parent with no plan_abs and leave the round on the old
# path.
CHILD_PLAN_DOC=$(printf '%s' "$VARS" | jq -r '.PLAN_DOC // empty')
if [ -n "$CHILD_PLAN_DOC" ] && [ -n "$PARENT" ]; then
    PARENT_DIR=$(koto session list | jq -r --arg s "$PARENT" 'map(select(.id == $s))[0].execution_dir // empty') \
        || die 2 "could not read the directory of $PARENT"
    if [ -z "$PARENT_DIR" ]; then
        PARENT_DIR=.
    elif [ ! -d "$PARENT_DIR" ]; then
        die 2 "$PARENT is bound to $PARENT_DIR, which no longer exists; rebind it to its checkout (koto session rebind) and start the round again"
    fi
    (cd "$PARENT_DIR" && koto context exists "$PARENT" plan_abs >/dev/null)
    case $? in
        0)
            PARENT_PLAN_ABS=$(cd "$PARENT_DIR" && koto context get "$PARENT" plan_abs) \
                || die 2 "could not read plan_abs from $PARENT"
            if [ -n "$PARENT_PLAN_ABS" ] && [ "$PARENT_PLAN_ABS" != "$CHILD_PLAN_DOC" ]; then
                VARS=$(printf '%s' "$VARS" | jq -c --arg p "$PARENT_PLAN_ABS" '.PLAN_DOC = $p') \
                    || die 2 "could not set the round's PLAN_DOC"
            fi
            ;;
        1) ;; # the parent records no plan_abs: the round keeps the child's PLAN_DOC
        *) die 2 "could not read whether $PARENT records plan_abs" ;;
    esac
fi

ARGS=(init "$NAME" --template "$TEMPLATE")
[ -n "$PARENT" ] && ARGS+=(--parent "$PARENT")
while IFS= read -r kv; do
    [ -n "$kv" ] && ARGS+=(--var "$kv")
done < <(printf '%s' "$VARS" | jq -r --argjson own "$HAVE_REPORT" '
    to_entries[]
    | select(.key != "REVIEW_LEVEL" and .key != "UNIT_KIND" and .key != "PLUGIN_ROOT")
    | select($own == 0 or .key != "FIX_REPORT")
    | select((.value | tostring) != "")
    | "\(.key)=\(.value)"')
ARGS+=(--var "PLUGIN_ROOT=$PLUGIN_ROOT_SELF")
[ "$HAVE_REPORT" = 0 ] || ARGS+=(--var "FIX_REPORT=$OWN_REPORT")

koto "${ARGS[@]}" >/dev/null || die 2 "koto init $NAME failed"

TS=$(date -u +%Y-%m-%dT%H:%M:%SZ)
jq -nc --arg from "$ORIG" --argjson round "$N" --arg base "$BASE" --argjson fresh "$FRESH" \
    '{from: $from, round: $round, base: $base} + (if $fresh == 1 then {fresh: true} else {} end)' | koto context add "$NAME" "$ROUND_KEY" >/dev/null \
    || die 2 "the round $NAME started, but $ROUND_KEY could not be stored in it"
{ [ -n "$ROUNDS" ] && printf '%s\n' "$ROUNDS"
  jq -nc --argjson round "$N" --arg session "$NAME" --arg base "$BASE" --arg ts "$TS" \
      '{round: $round, session: $session, base: $base, ts: $ts}'
} | koto context add "$ORIG" "$ROUNDS_KEY" >/dev/null \
    || die 2 "the round $NAME started, but $ROUNDS_KEY could not be stored in $ORIG"

# The ledger the round inherits: the last earlier round's, else the original's.
SRC=$ORIG
[ "$COUNT" -gt 0 ] && SRC=$LAST
INHERITED=none
if [ "$FRESH" -eq 0 ] && koto context exists "$SRC" "$LEDGER_KEY"; then
    LEDGER_JSON=$(koto context get "$SRC" "$LEDGER_KEY") || LEDGER_JSON=""
    # Every commit the panels recorded: seats' judged_at, the re-verifiers'
    # heads and the finding records' commits. One the base doesn't contain
    # means what they judged is gone from the branch.
    if COMMITS=$(printf '%s' "$LEDGER_JSON" | jq -r 'select(type == "object") | [
            ((.seats // {})[] | .judged_at?),
            ((.reverified // {})[] | .head?),
            ((.findings // {})[] | objects | (.records // [])[] | .commit?) ]
            | map(select(type == "string")) | unique | .[]') && [ -n "$COMMITS" ]; then
        OK=1
        while IFS= read -r c; do
            case "$c" in *[!0-9a-f]*|"") OK=0; break ;; esac
            git merge-base --is-ancestor "$c" "$BASE" || { OK=0; break; }
        done <<EOF
$COMMITS
EOF
        if [ "$OK" -eq 1 ]; then
            # The acceptance criteria the seats judged against, as
            # review-level.sh stored them from context.md: the round writes
            # its own context.md at entry, and only the criteria have to
            # match, not the rest of the issue text.
            CRIT_SHA=""
            if koto context exists "$SRC" "$CRITERIA_KEY"; then
                CRIT_SHA=$(koto context get "$SRC" "$CRITERIA_KEY" | git hash-object --stdin) \
                    || die 2 "the round $NAME started, but $CRITERIA_KEY in $SRC could not be read"
            fi
            printf '%s' "$LEDGER_JSON" | jq -c --arg from "$SRC" --arg base "$BASE" --arg crit "$CRIT_SHA" \
                '.inherited = {from: $from, base: $base, criteria_sha: $crit}' \
                | koto context add "$NAME" "$LEDGER_KEY" >/dev/null \
                || die 2 "the round $NAME started, but $LEDGER_KEY could not be copied into it"
            INHERITED=$SRC
        fi
    fi
fi

echo "session=$NAME"
echo "round=$N"
echo "inherited=$INHERITED"
