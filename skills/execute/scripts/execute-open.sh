#!/usr/bin/env bash
# execute-open.sh — /execute's koto entry: map this invocation's tokens to the
# session's variables and open `execute-<slug>` through the shared koto-open.sh.
#
# Every /execute invocation, fresh or resumed, enters the same way: the agent
# writes the invocation's tokens (the words of $ARGUMENTS) to a file outside the
# work tree, and this script builds the variable pairs with jq -- never eval --
# and makes the one `koto init` call:
#
#   koto init execute-<slug> --template <execute.md | execute-coordinated.md>
#             --vars-file <pairs> --attach-live --replace-terminal
#             [--koto-leg <request-id>:execute]
#
# The template follows the PLAN's `execution_mode:` frontmatter:
# `coordinated` enters execute-coordinated.md, `multi-pr` is refused (it runs
# through /work-on), anything else enters execute.md. A PLAN the cascade
# deleted takes the mode of its run instead: run/setup's in the session, else
# in the opener's snapshot, else the PLAN's last committed version before the
# commit that deleted it. Both share the session name, so a live session from
# the other template is koto's template_mismatch refusal, and a finished one
# is replaced.
#
# koto then decides everything a variable can express, so /execute refuses
# nothing of its own that koto could: a repeated --merge is koto's
# duplicate_var, `--merge=yes` is invalid_var, a slug outside ^[a-z0-9-]+$ is
# invalid_var on PLAN_SLUG, a live session from another template, worktree, or
# store is template_mismatch or origin_mismatch, and a coordinated flag on a
# single-pr PLAN is unknown_var. Under --koto-leg every one of those refusals
# is recorded on the leg by koto itself. This script's own refusals are only
# the ones where no koto call can be built at all, or would change a run it
# must not: a malformed --koto-leg value, a coordinated flag with no value or
# a --remove with no --follow-up, a --follow-up value with no `=`, a
# verification deferral koto would refuse in words nobody can act on or can't
# check at all (below), a tokens
# file it cannot read, a multi-pr PLAN, which /work-on runs rather than
# /execute (`error=multi-pr`), a setup-only flag on a live coordinated session past coord_setup
# (`error=flag-needs-setup`), a session another opener holds
# (`error=session-busy`), and a run record it could not read or carry
# (`failed=carry`). koto-open.sh adds the other two: an args file inside the
# work tree, and no koto binary.
#
# Usage: execute-open.sh <tokens-file>
#
#   <tokens-file>  a JSON array of strings, the invocation's tokens in order,
#                  written with jq into a directory from
#                  `koto-open.sh --alloc-dir`. This script removes it, and
#                  koto-open.sh removes the pairs file and the directory.
#
# The pairs, one per occurrence, so a repeat survives to be refused:
#
#   PLAN_DOC               the first token ending in .md that isn't a flag or
#                          a flag's separate value
#   PLAN_SLUG              its basename without PLAN- and .md
#   PLUGIN_ROOT            $CLAUDE_PLUGIN_ROOT, else this plugin's root
#   MERGE                  `--merge` -> true, `--merge=<v>` -> <v>, one pair per
#                          occurrence; none -> one pair, false. Passed
#                          explicitly on every invocation, so koto rebinds it on
#                          every accepted attach and a run is never merged on an
#                          earlier invocation's intent.
#   PAUSE_BEFORE_FINALIZE  one pair per mode flag (`--interactive` -> true,
#                          `--auto` -> false); with no mode flag, one pair from
#                          the repository's `## Execution Mode:` header in
#                          CLAUDE.md, else interactive (true). A resume of a
#                          session retained at paused_for_review passes false:
#                          re-invoking a paused run is the finalize invocation.
#   REVIEW_FLOOR           `--review-floor=<level>` -> <level>, one pair per
#                          occurrence (a bare --review-floor is the literal
#                          token, which the pattern refuses); none -> no pair.
#   REVIEW_CEILING         `--review-ceiling=<level>`, the same way.
#   VERIFICATION           `--verification=<local|hosted-ci>`, the same way.
#   VERIFICATION_DEFERRAL_REASON
#                          `--verification-reason=<text>`, the same way.
#   STORE                  `--store <v>` or `--store=<v>`
#   COORDINATION_PR        `--coordination-pr <url>`
#   FOLLOW_UP              `--follow-up <node>=<url>` -> `<node> <url>`: the
#                          first `=` becomes a space, since koto's own value
#                          allowlist has no `=`; a value with no `=` is
#                          refused here (error=usage) (the jq
#                          `sub("="; " ")` in the pairs builder below)
#   FOLLOW_UP_REMOVE       `--remove` -> true
#   ADOPT_RUN              `--adopt-run <id>`
#
# The two review-level bound variables are passed only when their flag is, so a
# run without the flags initialises exactly the variables it did before they
# existed. Both are rebind in the templates, like MERGE: an attach that doesn't
# pass one resets it to empty, so a resumed run bounds the children it spawns
# from then on by this invocation's flags, never an earlier one's. koto refuses
# a value outside light, standard and full (invalid_var) and a repeat
# (duplicate_var).
#
# The verification deferral's two variables are passed only when their flag is
# too, so a run without them initialises exactly what it did before. Both
# templates declare them, a single-pr run's children getting them through the
# spawn and a coordinated run's through the dispatch step. Unlike the bound
# they are not rebind, as in /work-on: an attach
# that passes none keeps what the run started with, and one that passes another
# value is koto's refusal. Before any koto call this script refuses, with
# /work-on's opener's checks (scripts/lib/verification-deferral.sh), a reason
# with a character outside koto's value allowlist and --verification=hosted-ci
# with no reason (error=usage, exit 64).
#
# The five coordinated variables (STORE through ADOPT_RUN) are passed on every
# coordinated invocation, one pair per occurrence, and `""` when the flag is
# absent: all five are rebind in execute-coordinated.md, so an attach without
# the flag resets it, and a value from an earlier invocation never persists.
# On a single-pr PLAN a pair is passed only when its flag was given, and koto
# refuses it (unknown_var). Each flag takes `--flag <value>` or
# `--flag=<value>`; the separate value is never read as the PLAN.
#
# `--koto-leg=<request-id>:<leg>` (or `--koto-leg <request-id>:<leg>`) is passed
# through once. The leg must be `execute`, the one leg /execute answers; the
# request id is checked by koto-open.sh against koto's pattern. The flag changes
# nothing but where the result goes.
#
# A coordinated PLAN, before `koto init`:
#
#   the lock      `<carry root>/<session>.lock`, a directory holding the
#                 holder's pid, taken with mkdir (retried every 0.2 s, 25
#                 times; a lock whose pid is gone is removed), released on
#                 exit. Still held: `error=session-busy`, exit 64. The carry
#                 root is $SHIRABE_STATE_DIR/execute-carry, else
#                 ${XDG_STATE_HOME:-$HOME/.local/state}/shirabe/execute-carry,
#                 mode 0700.
#   the status    one `koto status` read. A live session (not terminal, not
#                 removed) past coord_setup given --store, --coordination-pr,
#                 --follow-up or --adopt-run is refused `error=flag-needs-setup`
#                 (exit 64, no koto init): those flags take effect only at
#                 setup.
#   the snapshot  a finished session holding `run/` keys has its run record
#                 (and its run_id) written to `<carry root>/<session>/`
#                 before koto replaces it. A read that fails is
#                 `failed=carry`, exit 70, nothing replaced.
#
# And after the open (any `opened=`): the session's `run_id` is seeded from
# the snapshot, else from the finished session it replaced; a coordinated
# open never mints one (record-coord-setup.sh mints when it seals a new run
# record). A snapshot is carried into a session that has no run/setup yet
# (`run-record.sh carry`) and removed once the carry succeeds
# (`carried=<key-count>`); a carry that fails keeps it for the next open
# (`carry=pending`, `failed=carry`, exit 70; stderr names the snapshot). A
# session that already has run/setup makes the snapshot stale, and it is
# removed. `merge_attempts` and `recovered` are removed, so every invocation
# starts with no merge attempts and reports a recovery only when its own setup
# made one. On `opened=attached` the run's plan_abs is checked against this
# checkout with `record-coord-setup.sh --reroot-plan`, which re-roots it only
# when the recorded PLAN is gone and this checkout is on the recorded
# coord_branch with home_repo as its origin (one stderr line names both paths);
# its stdout is dropped and it changes no line or exit code here. A
# single-pr open seeds the prior run_id and mints one when the session still
# has none.
#
# The run identity. A session this script opens always has a `run_id`
# (`run-id.sh mint`) on a single-pr PLAN, the identity every owned-PR lookup of
# the run carries; a coordinated session has one once its setup ran. When
# koto replaces a finished session, the finished one's `run_id` is read first
# and seeded into the replacement, so a re-invocation of the same PLAN in the
# same place still owns the PR the earlier run opened.
#
# The replaced run's review round is carried too. Before the open, when the
# session holds review_round.json (review-round.sh writes it there, and
# coordinate's land step reads it there), the key is read into a file in a
# private directory from `koto-open.sh --alloc-dir`, outside the work tree;
# nothing is written to that session. After opened=replaced (with or without
# moved_to=), on either template, and never after opened=new or
# opened=attached, the file is written unchanged as the new session's
# review_round.json, when it is one JSON object. It keeps its reviewed_head,
# so the land step still refuses a round whose head has moved. A read or a
# write that fails, or a value that isn't one JSON object, prints one stderr
# warning naming the session and saying the round has to be recorded again
# with review-round.sh, and the run goes on: no stdout line or exit code
# changes. The file and its directory are removed on every exit path. Nothing
# else of the finished session is carried beyond the keys named here.
#
# Output: koto-open.sh's lines (opened=..., refused=..., failed=...), then
# `carried=<n>` after a carry and `session=execute-<slug>` when a session was
# opened, or, on a refusal, the exit lines print-exit.sh --refused prints
# (outcome=error, step=execute:refused). This script's own refusals print
# `error=usage`, `error=multi-pr`, `error=flag-needs-setup`,
# `error=session-busy`, or `failed=carry`, with the reason on stderr. No line
# names a local path; the snapshot's path goes to stderr only. koto's refusal
# wording goes to stderr, from execute-open-wording.tsv.
#
# A finished session koto keeps for its hierarchy is moved aside rather than
# replaced: koto-open.sh's moved_to= and moved_reason= lines follow
# opened=replaced, the old run stays readable under that name, and the
# snapshot and run identity above are carried as for any replace, so the moved
# run and the fresh one share a run_id: the fresh run still owns the PR the
# moved one opened, and the moved one is finished and looks nothing up. When it
# can't be moved, koto refuses (replace_held_live, with a live= line, or
# replace_failed) and nothing is replaced; a snapshot taken for it is kept,
# and the next open takes a fresh one.
#
# Exit codes: koto-open.sh's (0 opened, 2 refused, 74 replace_failed, 75
# replace_held_live, 127 no koto or jq, koto's
# own code otherwise), 64 for this script's own refusals (usage, multi-pr,
# flag-needs-setup, session-busy), or 70 for a run record it could not
# snapshot or carry.
#
# Requires: bash 3.2+, jq, koto.
set -uo pipefail

PROG=execute-open

SELF_DIR=$(CDPATH='' cd "$(dirname "${BASH_SOURCE[0]}")" && pwd) || exit 64
SKILL_DIR=$(CDPATH='' cd "$SELF_DIR/.." && pwd) || exit 64
PLUGIN_DIR=$(CDPATH='' cd "$SKILL_DIR/../.." && pwd) || exit 64
TEMPLATE="$SKILL_DIR/koto-templates/execute.md"
KOTO_OPEN="$PLUGIN_DIR/scripts/koto-open.sh"
WORDING="$SELF_DIR/execute-open-wording.tsv"
PRINT_EXIT="$SELF_DIR/print-exit.sh"
# shellcheck source=run-record-lib.sh
. "$SELF_DIR/run-record-lib.sh"
# shellcheck source=../../../scripts/lib/verification-deferral.sh
. "$PLUGIN_DIR/scripts/lib/verification-deferral.sh" || exit 64

TOKENS_FILE="${1:-}"
own_refusal() {
    [ -n "$TOKENS_FILE" ] && rm -f -- "$TOKENS_FILE"
    printf 'error=usage\n'
    echo "$PROG: $*" >&2
    exit 64
}

[ $# -eq 1 ] || own_refusal "usage: execute-open.sh <tokens-file>"
[ -f "$TOKENS_FILE" ] || own_refusal "no tokens file at [$TOKENS_FILE]"
command -v jq >/dev/null || { printf 'failed=jq_missing\n'; echo "$PROG: jq is not on PATH" >&2; exit 127; }
jq -e 'type == "array" and all(.[]; type == "string")' "$TOKENS_FILE" >/dev/null \
    || own_refusal "the tokens file is not a JSON array of strings"

TOKENS=$(cat -- "$TOKENS_FILE")
DIR=$(dirname -- "$TOKENS_FILE")
rm -f -- "$TOKENS_FILE"

# The verification deferral's two refusals, /work-on's own (see VERIFICATION in
# the header): a reason koto would refuse, and hosted-ci with no reason.
REFUSAL=$(vd_reason_chars_refusal "$TOKENS")
[ -z "$REFUSAL" ] || own_refusal "$REFUSAL"
REFUSAL=$(vd_missing_reason_refusal "$TOKENS")
[ -z "$REFUSAL" ] || own_refusal "$REFUSAL"

# --koto-leg: the one flag this script checks itself, because without a
# well-formed value there is no leg for koto to record a refusal on.
LEGS=$(printf '%s' "$TOKENS" | jq -c '. as $t | [range(0; length) as $i
    | if $t[$i] == "--koto-leg" then ($t[$i + 1] // "")
      elif ($t[$i] | startswith("--koto-leg=")) then ($t[$i] | ltrimstr("--koto-leg="))
      else empty end]')
LEG_COUNT=$(printf '%s' "$LEGS" | jq 'length')
LEG=""
if [ "$LEG_COUNT" -gt 1 ]; then
    own_refusal "--koto-leg given more than once"
elif [ "$LEG_COUNT" -eq 1 ]; then
    LEG=$(printf '%s' "$LEGS" | jq -r '.[0]')
    case "$LEG" in
        *:execute) ;;
        *) own_refusal "--koto-leg must be <request-id>:execute, got [$LEG]" ;;
    esac
    case "${LEG%:execute}" in
        ""|*:*) own_refusal "--koto-leg must be <request-id>:execute, got [$LEG]" ;;
    esac
fi

# The coordinated flags, each `--flag <value>` or `--flag=<value>`. A separate
# value that is missing, or is itself a flag, is a usage error: there is no
# value to hand koto. FLAGS is {"<flag>": [values in order], ...}, plus
# "--remove": [one "true" per occurrence].
FLAGS=$(printf '%s' "$TOKENS" | jq -c '. as $t
    | def vals($f): [range(0; $t | length) as $i
        | if $t[$i] == $f then
            (if ($t[$i + 1] // null) == null or ($t[$i + 1] | startswith("-")) then {bad: $f}
             else {v: $t[$i + 1]} end)
          elif ($t[$i] | startswith($f + "=")) then {v: ($t[$i] | ltrimstr($f + "="))}
          else empty end];
    {"--store": vals("--store"), "--coordination-pr": vals("--coordination-pr"),
     "--follow-up": vals("--follow-up"), "--adopt-run": vals("--adopt-run"),
     "--remove": [$t[] | select(. == "--remove") | {v: "true"}]}')
BAD_FLAG=$(printf '%s' "$FLAGS" | jq -r '[.[][] | .bad // empty][0] // ""')
[ -z "$BAD_FLAG" ] || own_refusal "$BAD_FLAG needs a value (--flag <value> or --flag=<value>)"
# --follow-up's value is <node>=<url>, and koto carries it as `<node> <url>`
# (its own value allowlist has no `=`). A value with no `=` has no node to
# split off, so there is no FOLLOW_UP to build.
FU_NO_SEP=$(printf '%s' "$FLAGS" | jq -r 'first(."--follow-up"[] | .v | select(contains("=") | not)) | "[\(.)]"')
[ -z "$FU_NO_SEP" ] || own_refusal "--follow-up takes <node>=<url>, got $FU_NO_SEP"
if [ "$(printf '%s' "$FLAGS" | jq '(."--remove" | length) > 0 and (."--follow-up" | length) == 0')" = true ]; then
    own_refusal "--remove applies only with --follow-up <node>=<url>"
fi
# setup_flags_given -- the flags that take effect only at coord_setup, as one
# space-separated list (empty when none was given).
SETUP_FLAGS_GIVEN=$(printf '%s' "$FLAGS" | jq -r '[to_entries[] | select(.key != "--remove" and (.value | length) > 0) | .key] | join(" ")')

# The PLAN: the first non-flag token ending in .md that is not a flag's
# separate value.
PLAN=$(printf '%s' "$TOKENS" | jq -r '. as $t | [range(0; length) as $i
    | select(($t[$i] | startswith("-") | not) and ($t[$i] | endswith(".md"))
             and ($i == 0 or (["--koto-leg", "--store", "--coordination-pr", "--follow-up", "--adopt-run"]
                              | index($t[$i - 1])) == null))
    | $t[$i]][0] // ""')
SLUG=$(basename -- "$PLAN" .md)
SLUG=${SLUG#PLAN-}

# A slug outside the pattern is koto's to refuse (invalid_var on PLAN_SLUG), and
# koto validates variables before it looks at the session name, so the call is
# made under a placeholder name that koto never reaches.
case "$SLUG" in
    ""|*[!a-z0-9-]*) SESSION="execute-unnamed" ;;
    *) SESSION="execute-$SLUG" ;;
esac
HAVE_KOTO=0
command -v koto >/dev/null && HAVE_KOTO=1
NAMED=0
[ "$SESSION" != "execute-unnamed" ] && [ "$HAVE_KOTO" -eq 1 ] && NAMED=1
CR="${SHIRABE_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/shirabe}/execute-carry"

# mode_of -- the execution_mode of the PLAN text on stdin (its frontmatter).
mode_of() {
    awk '
        NR == 1 { if ($0 !~ /^---[[:space:]]*$/) exit; next }
        /^---[[:space:]]*$/ { exit }
        /^execution_mode:/ {
            sub(/^execution_mode:[[:space:]]*/, "")
            gsub(/["\047[:space:]]/, "")
            print
            exit
        }'
}

# The template, from the PLAN's execution_mode, re-validated against the enum:
# exactly `coordinated` selects execute-coordinated.md, `multi-pr` is refused
# here, before any koto call; anything else stays on execute.md, as before.
# Both templates share the execute-<slug> session name, so koto's
# --attach-live refuses a live session built from the other one
# (template_mismatch) and --replace-terminal replaces a finished one.
#
# A PLAN that is gone (the finalization cascade deletes it) takes its mode
# from the run it belonged to, read-only and before the lock: the session's
# run/setup (a live or finished session holding the record), else the
# snapshot an earlier open kept, else the PLAN's last committed version
# before the commit that deleted it. A run holding its record re-invokes on
# the coordinated template that way, and a lost record with its PLAN gone
# reaches setup's recovery-plan-gone stop. Nothing found stays on execute.md.
MODE=""
if [ -n "$PLAN" ] && [ -f "$PLAN" ]; then
    MODE=$(mode_of < "$PLAN")
elif [ -n "$PLAN" ] && [ "$NAMED" -eq 1 ]; then
    if GONE_SETUP=$(rr_setup "$SESSION") && [ "$(jq -r '.mode // ""' <<<"$GONE_SETUP")" = coordinated ]; then
        MODE=coordinated
    elif [ -f "$CR/$SESSION/record.json" ] \
        && [ "$(jq -r '(.["run/setup"] // {}).mode // ""' "$CR/$SESSION/record.json")" = coordinated ]; then
        MODE=coordinated
    else
        # The fallback's limits: it finds only the latest commit reachable
        # from HEAD that deleted exactly this path, and follows no rename. A
        # shallow clone, or a checkout without that commit, finds nothing and
        # stays on execute.md. A relative PLAN path is resolved against the
        # current directory. Only the frontmatter of the version just before
        # that deletion is read.
        GONE_AT=$(git log -1 --diff-filter=D --format=%H -- "$PLAN") || GONE_AT=""
        if [[ $GONE_AT =~ ^[0-9a-f]{40}$ ]]; then
            case "$PLAN" in
                /*) GONE_TOP=$(git rev-parse --show-toplevel) || GONE_TOP=""
                    GONE_PATH="${PLAN#"$GONE_TOP"/}" ;;
                *) GONE_PATH="./$PLAN" ;;
            esac
            if GONE_TEXT=$(git show "$GONE_AT^:$GONE_PATH"); then
                [ "$(mode_of <<<"$GONE_TEXT")" = coordinated ] && MODE=coordinated
            fi
        fi
    fi
fi
COORDINATED=0
case "$MODE" in
    coordinated)
        TEMPLATE="$SKILL_DIR/koto-templates/execute-coordinated.md"
        COORDINATED=1
        ;;
    multi-pr)
        # A multi-pr PLAN lands one pull request per issue, through /work-on.
        # Refused before any koto call, so nothing is recorded on a --koto-leg.
        printf 'error=multi-pr\n'
        echo "$PROG: $PLAN is a multi-pr PLAN; /execute doesn't run it. Run it with /work-on $PLAN, one issue at a time." >&2
        exit 64
        ;;
esac

# The coordinated run's lock, before the session is read: one opener at a time
# reads, replaces, and carries a session's record. (The mode fallback above
# only reads.)
LOCK=""
release_lock() { [ -n "$LOCK" ] && rm -rf -- "$LOCK"; return 0; }
if [ "$COORDINATED" -eq 1 ] && [ "$NAMED" -eq 1 ]; then
    mkdir -p "$CR" && chmod 700 "$CR" || {
        printf 'failed=carry\n'
        echo "$PROG: could not make the carry directory for $SESSION" >&2
        exit 70
    }
    tries=0
    while :; do
        if mkdir "$CR/$SESSION.lock" 2>/dev/null; then
            printf '%s\n' "$$" > "$CR/$SESSION.lock/pid"
            LOCK="$CR/$SESSION.lock"
            trap release_lock EXIT
            break
        fi
        holder=$(cat -- "$CR/$SESSION.lock/pid" 2>/dev/null) || holder=""
        # A holder that is gone left its lock behind: take it over. A lock
        # with no pid yet is a holder that just took it, unless it stays so
        # for the whole wait.
        if [ -n "$holder" ] && ! kill -0 "$holder" 2>/dev/null; then
            rm -rf -- "$CR/$SESSION.lock"
            continue
        fi
        tries=$((tries + 1))
        if [ "$tries" -ge 25 ]; then
            if [ -z "$holder" ]; then
                rm -rf -- "$CR/$SESSION.lock"
                tries=0
                continue
            fi
            printf 'error=session-busy\n'
            echo "$PROG: another /execute holds $SESSION (pid $holder); try again once it finishes" >&2
            exit 64
        fi
        sleep 0.2
    done
fi

# One status read for the session the invocation names. A retained
# paused_for_review session means this invocation resumes a paused run: the
# finalize invocation. From koto 0.17.0 (koto#355) `koto status` also answers
# for a session koto removed at its terminal, with "removed": true and the same
# state, so a removed pause has nothing to resume and is read as none.
STATUS=""
if [ "$NAMED" -eq 1 ]; then
    # koto answers a session it doesn't have with a nonzero exit and a
    # `not found` error object on stdout: that is no session. Any other
    # failure is reported here and read as no session too; the init below
    # then decides from koto's own state.
    STATUS=$(koto status "$SESSION")
    rc=$?
    if [ "$rc" -ne 0 ]; then
        case "$STATUS" in
            *"not found"*) ;;
            *) echo "$PROG: koto status $SESSION failed (exit $rc): $STATUS" >&2 ;;
        esac
        STATUS=""
    fi
    if [ -n "$STATUS" ] && ! jq -e 'type == "object" and has("current_state")' <<<"$STATUS" >/dev/null; then
        echo "$PROG: koto status $SESSION answered something other than a session's status: $STATUS" >&2
        STATUS=""
    fi
fi
RESUMING_PAUSE=0
if [ -n "$STATUS" ] && printf '%s' "$STATUS" \
    | jq -e '.removed != true and .is_terminal == true and .current_state == "paused_for_review"' >/dev/null; then
    RESUMING_PAUSE=1
fi
FINISHED=0
if [ -n "$STATUS" ] && printf '%s' "$STATUS" | jq -e '.removed != true and .is_terminal == true' >/dev/null; then
    FINISHED=1
fi

if [ "$COORDINATED" -eq 1 ] && [ "$NAMED" -eq 1 ]; then
    # The setup-only flags on a live session past coord_setup: setup has run,
    # so the flag would be accepted and then never applied.
    if [ -n "$SETUP_FLAGS_GIVEN" ] && [ -n "$STATUS" ] \
        && printf '%s' "$STATUS" | jq -e '.removed != true and .is_terminal != true and .current_state != "coord_setup"' >/dev/null; then
        printf 'error=flag-needs-setup\n'
        echo "$PROG: $SESSION is a live run at $(printf '%s' "$STATUS" | jq -r .current_state), past coord_setup; $SETUP_FLAGS_GIVEN take effect only at coord_setup. Run without them, or finish this run first." >&2
        exit 64
    fi
    # The snapshot: a finished session's run record, kept before koto
    # replaces it.
    if [ "$FINISHED" -eq 1 ]; then
        KEYS=$(rr_keys "$SESSION") || {
            printf 'failed=carry\n'
            echo "$PROG: could not list $SESSION's run record; nothing was replaced" >&2
            exit 70
        }
        if [ -n "$KEYS" ]; then
            SNAP_TMP=$(mktemp -d "$CR/.$SESSION.XXXXXX") || SNAP_TMP=""
            if [ -z "$SNAP_TMP" ] || ! rr_record "$SESSION" > "$SNAP_TMP/record.json"; then
                [ -n "$SNAP_TMP" ] && rm -rf -- "$SNAP_TMP"
                printf 'failed=carry\n'
                echo "$PROG: could not read $SESSION's run record into a snapshot; nothing was replaced" >&2
                exit 70
            fi
            # The run identity, when the session has one: `exists` answering
            # 1 is none; any other failure is reported, and the replacement
            # falls back to the identity read below.
            SNAP_ID=""
            koto context exists "$SESSION" run_id >/dev/null
            rc=$?
            case "$rc" in
                0) SNAP_ID=$(koto context get "$SESSION" run_id) || SNAP_ID="" ;;
                1) ;;
                *) echo "$PROG: could not check run_id in $SESSION (koto exit $rc)" >&2 ;;
            esac
            [[ $SNAP_ID =~ ^[0-9a-f]{32}$ ]] && printf '%s' "$SNAP_ID" > "$SNAP_TMP/run_id"
            # The finished session is newer than any snapshot an earlier open
            # left behind.
            rm -rf -- "$CR/$SESSION"
            mv "$SNAP_TMP" "$CR/$SESSION" || {
                rm -rf -- "$SNAP_TMP"
                printf 'failed=carry\n'
                echo "$PROG: could not keep $SESSION's run record snapshot; nothing was replaced" >&2
                exit 70
            }
        fi
    fi
fi

# The run identity a finished session carried (its `run_id`), read before koto
# replaces the session: a replacement starts with empty context, and without
# the id it would find the PR the earlier run opened carrying a foreign marker.
# Seeded into the new session below, so a re-invocation in the same place is
# the same run to the ownership filter. This read is deliberately loose (any
# failure just skips the carry, and a live session attached below keeps its
# own id anyway); the strict read is `run-id.sh get`, which runs after the open.
PRIOR_RUN_ID=""
if [ "$NAMED" -eq 1 ] && koto context exists "$SESSION" run_id >/dev/null; then
    PRIOR_RUN_ID=$(koto context get "$SESSION" run_id) || PRIOR_RUN_ID=""
    [[ $PRIOR_RUN_ID =~ ^[0-9a-f]{32}$ ]] || PRIOR_RUN_ID=""
fi

# The finished run's review round, read here beside its identity and written
# into the replacement after the open (see the header). ROUND_DIR is the
# private directory the round file sits in; on_exit removes both, and
# releases the lock, on every exit path from here on.
ROUND_FILE=""
ROUND_DIR=""
remove_round() {
    [ -n "$ROUND_FILE" ] && rm -f -- "$ROUND_FILE"
    ROUND_FILE=""
    if [ -n "$ROUND_DIR" ]; then
        rm -f -- "$ROUND_DIR/.koto-open-alloc"
        rmdir -- "$ROUND_DIR" 2>/dev/null
        ROUND_DIR=""
    fi
    return 0
}
on_exit() { remove_round; release_lock; }

# read_prior_round <session> -- copy <session>'s review_round.json, when it
# has one, into ROUND_FILE. A read only: nothing is written to <session>.
# ROUND_READ says what came of it: `none` (no such session or key), `read`,
# or `failed` (an `exists` that answered neither yes nor no, or a `get` that
# failed). Only a replace acts on it, so a failure here is reported by
# write_prior_round or not at all.
ROUND_READ=none
read_prior_round() {
    local session="$1" rc=0
    koto context exists "$session" review_round.json </dev/null >/dev/null 2>&1 || rc=$?
    case "$rc" in
        0) ;;
        1) return 0 ;;
        *) ROUND_READ=failed; return 0 ;;
    esac
    if ! ROUND_DIR=$(bash "$KOTO_OPEN" --alloc-dir 2>/dev/null) || [ ! -d "$ROUND_DIR" ]; then
        ROUND_DIR=""; ROUND_READ=failed; return 0
    fi
    ROUND_FILE="$ROUND_DIR/review_round.json"
    if koto context get "$session" review_round.json </dev/null >"$ROUND_FILE" 2>/dev/null; then
        ROUND_READ=read
    else
        ROUND_READ=failed
    fi
    return 0
}

# write_prior_round <session> -- after a replace, write the round
# read_prior_round kept, byte for byte, as the new session's
# review_round.json. Only one JSON object is written. A failed read, anything
# else, or a failed write is one warning: the land step then finds no round
# in this run until the worker records it again.
write_prior_round() {
    local session="$1" why=""
    case "$ROUND_READ" in
        none) return 0 ;;
        failed) why="could not be read" ;;
        read)
            if ! jq -s -e 'length == 1 and (.[0] | type) == "object"' <"$ROUND_FILE" >/dev/null 2>&1; then
                why="is not one JSON object"
            elif ! koto context add "$session" review_round.json <"$ROUND_FILE" >/dev/null 2>&1; then
                why="could not be written"
            fi
            ;;
    esac
    remove_round
    [ -n "$why" ] || return 0
    printf '%s: the review round recorded in the finished run of %s %s, so the new run has none; record it again with review-round.sh\n' \
        "$PROG" "$session" "$why" >&2
    return 0
}

if [ "$NAMED" -eq 1 ]; then
    trap on_exit EXIT
    trap 'on_exit; trap - EXIT; exit 130' INT
    trap 'on_exit; trap - EXIT; exit 143' TERM
    read_prior_round "$SESSION"
fi

HEADER_MODE=""
TOP=$(git rev-parse --show-toplevel) || TOP=""
if [ -n "$TOP" ] && [ -f "$TOP/CLAUDE.md" ]; then
    HEADER_MODE=$(sed -n 's/^## Execution Mode:[[:space:]]*\([A-Za-z-]*\).*/\1/p' "$TOP/CLAUDE.md" | head -1)
fi

ROOT="${CLAUDE_PLUGIN_ROOT:-$PLUGIN_DIR}"

# FOLLOW_UP's first `=` becomes a space: see FOLLOW_UP in the header.
PAIRS_FILE="$DIR/execute-vars.json"
printf '%s' "$TOKENS" | jq -c \
    --arg plan "$PLAN" --arg slug "$SLUG" --arg root "$ROOT" \
    --arg header "$HEADER_MODE" --argjson resuming "$RESUMING_PAUSE" \
    --argjson coordinated "$COORDINATED" --argjson flags "$FLAGS" '
    def pause_of($m): if $resuming == 1 then "false" elif $m == "auto" then "false" else "true" end;
    def bound($flag; $var):
        [ .[] | select(. == $flag or startswith($flag + "="))
          | [$var, (if . == $flag then . else ltrimstr($flag + "=") end)] ];
    # coord($flag; $var): one pair per occurrence; on a coordinated PLAN one
    # empty pair when the flag is absent.
    def coord($flag; $var):
        ($flags[$flag] | map([$var, .v])) as $p
        | if ($p | length) == 0 and $coordinated == 1 then [[$var, ""]] else $p end;
    bound("--review-floor"; "REVIEW_FLOOR") as $floors
    | bound("--review-ceiling"; "REVIEW_CEILING") as $ceilings
    | bound("--verification"; "VERIFICATION") as $verifications
    | bound("--verification-reason"; "VERIFICATION_DEFERRAL_REASON") as $reasons
    | [ .[] | select(. == "--merge" or startswith("--merge=")) ] as $merges
    | [ .[] | select(. == "--auto" or . == "--interactive") ] as $modes
    | (if $plan == "" then [] else [["PLAN_DOC", $plan], ["PLAN_SLUG", $slug]] end)
      + [["PLUGIN_ROOT", $root]]
      + (if ($merges | length) == 0 then [["MERGE", "false"]]
         else [ $merges[] | ["MERGE", (if . == "--merge" then "true" else ltrimstr("--merge=") end)] ] end)
      + (if ($modes | length) == 0 then [["PAUSE_BEFORE_FINALIZE", pause_of($header)]]
         else [ $modes[] | ["PAUSE_BEFORE_FINALIZE", pause_of(ltrimstr("--"))] ] end)
      + $floors + $ceilings + $verifications + $reasons
      + coord("--store"; "STORE") + coord("--coordination-pr"; "COORDINATION_PR")
      + (coord("--follow-up"; "FOLLOW_UP") | map(.[1] |= sub("="; " ")))
      + coord("--remove"; "FOLLOW_UP_REMOVE")
      + coord("--adopt-run"; "ADOPT_RUN")
    ' > "$PAIRS_FILE" || own_refusal "could not write the variables file"

set -- "$SESSION" "$TEMPLATE" "$PAIRS_FILE" --attach-live --replace-terminal --wording "$WORDING"
[ -n "$LEG" ] && set -- "$@" --koto-leg "$LEG"

OUT=$(bash "$KOTO_OPEN" "$@")
RC=$?
[ -n "$OUT" ] && printf '%s\n' "$OUT"

case "$OUT" in
    opened=*)
        # A replaced finished run hands its review round on, under either
        # template, before anything below can stop the run; an attached or
        # new session is left as it is.
        if [ "${OUT%%$'\n'*}" = opened=replaced ]; then
            write_prior_round "$SESSION"
        fi
        if [ "$COORDINATED" -eq 1 ]; then
            # The identity: the snapshot's, else the replaced session's. seed
            # writes only when the session has none, so an attached live
            # session keeps its own. No mint here: record-coord-setup.sh mints
            # when it seals a new run record.
            SEED_ID=""
            [ -f "$CR/$SESSION/run_id" ] && SEED_ID=$(cat -- "$CR/$SESSION/run_id" 2>/dev/null)
            [[ $SEED_ID =~ ^[0-9a-f]{32}$ ]] || SEED_ID="$PRIOR_RUN_ID"
            if [ -n "$SEED_ID" ]; then
                bash "$SELF_DIR/run-id.sh" seed "$SESSION" "$SEED_ID" </dev/null \
                    || echo "$PROG: could not carry the prior run's identity into $SESSION" >&2
            fi
            # The record: carried into a session that has none yet.
            if [ -f "$CR/$SESSION/record.json" ]; then
                rr_setup "$SESSION" >/dev/null
                case $? in
                    0)
                        # The session already holds its record: the snapshot
                        # is stale.
                        rm -rf -- "$CR/$SESSION"
                        ;;
                    1)
                        N=$(jq 'length' "$CR/$SESSION/record.json") || N=""
                        if CARRY_OUT=$(bash "$SELF_DIR/run-record.sh" carry --session "$SESSION" \
                            --json "$CR/$SESSION/record.json" </dev/null); then
                            rm -rf -- "$CR/$SESSION"
                            printf 'carried=%s\n' "$N"
                        else
                            printf 'carry=pending\nfailed=carry\n'
                            echo "$PROG: could not carry the run record into $SESSION ($(printf '%s' "$CARRY_OUT" | tail -1)); the snapshot is kept at $CR/$SESSION, and invoking /execute again retries the carry" >&2
                            exit 70
                        fi
                        ;;
                    *)
                        printf 'carry=pending\nfailed=carry\n'
                        echo "$PROG: could not read $SESSION's run record; the snapshot is kept at $CR/$SESSION, and invoking /execute again retries the carry" >&2
                        exit 70
                        ;;
                esac
            fi
            # Every invocation starts with no merge attempts (an earlier
            # invocation's are not carried), and with no `recovered`: only
            # the invocation whose setup recovered the record reports it.
            koto context remove "$SESSION" merge_attempts >/dev/null \
                || echo "$PROG: could not clear merge_attempts in $SESSION" >&2
            koto context remove "$SESSION" recovered >/dev/null \
                || echo "$PROG: could not clear recovered in $SESSION" >&2
            # A live run attached from a checkout it moved to: plan_abs is
            # re-rooted to the PLAN here when the recorded one is gone and
            # this is the same coordination branch of the same repository.
            # record-coord-setup.sh decides and writes, keeping the key's one
            # writer; its stdout is dropped so this script's lines don't
            # change, and its one stderr line names the move.
            if [ "${OUT%%$'\n'*}" = opened=attached ] && [ -n "$PLAN" ]; then
                bash "$SELF_DIR/record-coord-setup.sh" --reroot-plan --session "$SESSION" --plan "$PLAN" \
                    </dev/null >/dev/null \
                    || echo "$PROG: could not check plan_abs in $SESSION against this checkout" >&2
            fi
        else
            # Carry the prior run's identity into a replacement (seed writes
            # only when the session has none, so an attached live session
            # keeps its own), then mint one if the session still has none.
            # This is one of the places a run identity is minted; every later
            # caller only reads it. A failure here is not a refusal, but the
            # run's later lookups then fail on the missing run_id rather than
            # adopt anything.
            if [ -n "$PRIOR_RUN_ID" ]; then
                bash "$SELF_DIR/run-id.sh" seed "$SESSION" "$PRIOR_RUN_ID" </dev/null \
                    || echo "$PROG: could not carry the prior run's identity into $SESSION" >&2
            fi
            bash "$SELF_DIR/run-id.sh" mint "$SESSION" </dev/null >/dev/null \
                || echo "$PROG: could not record a run identity in $SESSION; its PR lookups will fail until it has one" >&2
        fi
        printf 'session=%s\n' "$SESSION"
        ;;
    refused=*) bash "$PRINT_EXIT" --refused ;;
esac
exit "$RC"
