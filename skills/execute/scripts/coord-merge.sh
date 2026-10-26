#!/usr/bin/env bash
# coord-merge.sh — for /execute: merge one coordinated PR (a node PR, or the
# coordination PR last) through merge-exec.sh, and record a merge that did not
# land.
#
# coordinated-next.sh prints `merge:<node>` or `merge-coordination`; this is
# the command that action runs. It takes nothing the merge depends on from the
# agent or from the coordination PR's editable body: it reads the coordination
# PR the run record names (run/setup's coordination_pr), takes the node's
# repository, PR number, and pushed head from its run record
# (`run/node/<node>`, which node-push.sh wrote from the commit it pushed),
# checks that the recorded PR is the one owned PR on the node's branch, and
# hands exactly those values to merge-exec.sh, which recomputes the verdict at
# that head and makes the one fixed `gh pr merge --match-head-commit` call, or
# refuses with no call when the live head differs. For the coordination PR the
# head is the cascade's pushed head (`run/cascade`); with no pushed cascade
# the merge is refused.
#
# A follow-up, `--node <node>/follow-up-<n>` (coordinated-next.sh prints
# `merge:<node>/follow-up-<n>`), takes its repository, number and head from
# its own record (run/follow-up/<node>/<n>, which setup wrote from its live
# head); an absent or removed one, or one outside its node's repository or
# the write set, is exit 73. It merges only after its node: a node PR GitHub
# doesn't report MERGED refuses with `merge-refused:predecessor-unmerged`.
# Then the rule every follow-up is held to (coord_follow_up_check, read live:
# the default branch as base, not a fork, the authenticated author, not
# closed) refuses with `merge-refused:follow-up-<base|author|closed>`, and
# a follow-up already MERGED (a person merged it) prints `merged` and the
# render's lines with no merge call, as a merge it confirmed would. No
# owned-branch lookup and no merge-last gate apply to it; the merge itself is
# a node's.
#
# For the coordination PR it first brings the body up to date with the
# record (`coord-render.sh --before-coordination`): CI's merge-last gate reads
# the body, so a body the render couldn't post (body=stale, body=full) refuses
# the merge with no call, prints `merge-refused:body-stale` (or
# `merge-refused:body-full`), and the render has recorded
# `coordination:body-stale` (or `body-full`) in the session's merge_attempts.
# Then it re-reads the coordination PR for its state (it must still be open)
# and runs the merge-last gate itself: `shirabe validate --merge-gate
# --mode=ready` over the refs of the index in the body this run just rendered
# and posted (or found already equal), which the render hands back through
# `--rendered-out`, never over a re-read of the live body (under the run's
# recorded switch omit, whose body indexes nothing, over the same refs built
# from the run record's node and follow-up PRs), with
# any entry pointing at the coordination PR itself dropped (the coordination PR
# can't wait on its own merge), and with `--visibility private` when the home
# repository reads private live (repo-visibility.sh's read), so a private
# coordination PR can gate over public and private nodes alike. A gate that
# doesn't pass refuses the merge.
#
# Every merge passes a squash message: merge-message.sh builds it from the
# pull request's live title and Part 1 (scripts/lib/squash-message.sh), and
# merge-exec.sh hands it to `gh pr merge` as --subject and --body-file (a
# rebase takes none). A message the builder refuses (an empty Part 1, a title
# that spans lines, an attribution line) makes no merge call and prints
# `merge-refused:squash-message`.
#
# After a `merge-called:` line it runs `merge-verdict.sh --confirm`. A merge is
# never read as merged on the call alone. When the confirm read doesn't see
# MERGED, or the merge call itself failed, it records `<id>:<result>` in the
# session's `merge_attempts` context key, so the loop doesn't call the same
# merge again in this invocation: coordinated-next.sh then reports that PR
# unmerged with reason merge-not-observed or merge-call-failed. Every refusal
# (no recorded head, the merge-last gate, the squash message, or merge-exec.sh's
# own fresh verdict) records `<id>:merge-refused` the same way, and the run
# ends ready-awaiting-merge with that PR waiting on a human.
#
# A node or follow-up seen merged is a transition the body shows: after the
# confirm read reports `merged` for one, coord-render.sh records its merged
# head and posts the body. The coordination PR's body is final at its merge,
# so none is rendered after it.
#
# Usage:
#   coord-merge.sh --session <koto-session> --slug <slug>
#                  --home-repo <owner/repo> --coord-branch <branch>
#                  --node <node-id|<node>/follow-up-<n>|coordination>
#
# Output: merge-exec.sh's line (`merge-called:<method>:<sha>` or
# `merge-refused:<verdict>`), then, after a call, the confirm line (`merged` or
# `not-merged:merge-not-observed`), then, after a node's or a follow-up's
# `merged`, coord-render.sh's `observed=` and `body=` lines. A merge refused
# before merge-exec.sh runs prints `merge-refused:awaiting:head-moved` (no
# pushed head in the run record), `merge-refused:body-stale` or
# `merge-refused:body-full` (the coordination body couldn't be brought up to
# date), `merge-refused:merge-gate`, `merge-refused:squash-message`, or, for a
# follow-up, `merge-refused:predecessor-unmerged` or
# `merge-refused:follow-up-<base|author|closed>`; a follow-up already MERGED
# prints `merged` and the render's lines.
#
# Exit codes:
#   0   a line was printed (a refusal included)
#   64  usage error
#   70  the merge_attempts write failed, or the run's identity could not be
#       read (run-id.sh get)
#   72  a GitHub read failed, the run record could not be read, or there was
#       no temporary directory for the coordination PR's rendered body
#       (execute:status-read)
#   73  the recorded PR is not the one owned PR on its branch, the run record
#       has no PR for the node, holds no live follow-up of that number, or one
#       outside its node's repository or the write set, or the recorded
#       coordination PR is not open (execute:pr-adopt)
#   77  the render refused a record that would index a private repository in
#       a public coordination PR (execute:visibility); before the coordination
#       PR's merge no call was made
#
# Requires: bash 3.2+, gh, jq, koto, shirabe.
set -uo pipefail

PROG=coord-merge

COORD_SELF_DIR=$(CDPATH='' cd "$(dirname "${BASH_SOURCE[0]}")" && pwd) || exit 64
# shellcheck source=coord-common.sh
. "$COORD_SELF_DIR/coord-common.sh"
REPO_ROOT=$(CDPATH='' cd "$COORD_SELF_DIR/../../.." && pwd) || exit 64

usage_error() {
    echo "$PROG: $*" >&2
    echo "usage: coord-merge.sh --session <koto-session> --slug <slug> --home-repo <owner/repo> --coord-branch <branch> --node <node-id|<node>/follow-up-<n>|coordination>" >&2
    exit 64
}

SESSION=""; SLUG=""; HOME_REPO=""; CB=""; NODE=""
SEEN=" "
while [ $# -gt 0 ]; do
    case "$1" in
        --session|--slug|--home-repo|--coord-branch|--node)
            [ $# -ge 2 ] || usage_error "$1 needs a value"
            case "$SEEN" in *" $1 "*) usage_error "$1 given more than once" ;; esac
            SEEN="$SEEN$1 "
            case "$1" in
                --session) SESSION="$2" ;;
                --slug) SLUG="$2" ;;
                --home-repo) HOME_REPO="$2" ;;
                --coord-branch) CB="$2" ;;
                --node) NODE="$2" ;;
            esac
            shift 2
            ;;
        *) usage_error "unexpected argument [$1]" ;;
    esac
done
[[ $SESSION =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || usage_error "session [$SESSION] is not a koto session name"
[[ $SLUG =~ $RE_COORD_SLUG ]] || usage_error "--slug [$SLUG] is outside ^[a-z0-9-]+\$"
coord_valid_repo "$HOME_REPO" || usage_error "--home-repo [$HOME_REPO] is not a single owner/repo"
coord_valid_branch "$CB" || usage_error "--coord-branch [$CB] is not an allowed branch name"
[ "$NODE" = coordination ] || [[ $NODE =~ $RE_COORD_UNIT ]] \
    || usage_error "--node [$NODE] is not coordination, a node id, or <node>/follow-up-<n>"
FU_OF=""; FU_NUM=""
if [[ $NODE =~ $RE_COORD_FOLLOW_UP_ID ]]; then
    FU_OF="${BASH_REMATCH[1]}"; FU_NUM="${BASH_REMATCH[2]}"
fi
command -v jq >/dev/null || { echo "$PROG: jq is not on PATH" >&2; exit 72; }

# This run's identity, from its session: every lookup below carries it.
COORD_RUN_ID=$("$BASH" "$COORD_SELF_DIR/run-id.sh" get "$SESSION" </dev/null) || {
    echo "$PROG: could not read this run's identity in session $SESSION" >&2
    exit 70
}

coord_recorded_pr "$SESSION" "$HOME_REPO" open
case $? in
    0) ;;
    2) exit 72 ;;
    # A coordination body that lost its declaration marker (a /scope
    # republish) gets it back from the render below, and is read again after.
    3) [ "$NODE" = coordination ] && [ "$C_WHY" = marker ] || exit 73 ;;
    *) exit 73 ;;
esac
# record_attempt <result> -- this node's merge result, in merge_attempts.
record_attempt() {
    coord_record_attempt "$SESSION" "$NODE" "$1" || exit 70
}

# render [--before-coordination [--rendered-out <file>]] -- coord-render.sh
# over the record. Sets
# RENDER_OUT (its stdout) and returns its exit code.
render() {
    RENDER_OUT=$("$BASH" "$COORD_SELF_DIR/coord-render.sh" --session "$SESSION" --slug "$SLUG" \
        --home-repo "$HOME_REPO" --coord-branch "$CB" "$@" </dev/null)
}

SCRATCH=""
cleanup() { [ -n "$SCRATCH" ] && rm -rf "$SCRATCH"; return 0; }
trap cleanup EXIT
if [ "$NODE" = coordination ]; then
    # The body CI's merge-last gate reads, brought up to date first; a render
    # that couldn't post it refuses the merge (and has recorded why). The
    # render hands back the bytes it posted or found equal, which are what the
    # gate below reads.
    SCRATCH=$(mktemp -d "${TMPDIR:-/tmp}/coord-merge.XXXXXX") || {
        SCRATCH=""
        echo "$PROG: no temporary directory for the rendered body; nothing was merged" >&2
        exit 72
    }
    render --before-coordination --rendered-out "$SCRATCH/body.md"
    rc=$?
    printf '%s\n' "$RENDER_OUT" | grep -v '^merge-refused:' >&2
    case "$rc" in
        0) ;;
        70) exit 70 ;;
        77) echo "$PROG: the coordination PR's body would index a private repository in a public coordination PR; nothing was merged" >&2
            exit 77 ;;
        *) echo "$PROG: coord-render.sh exited $rc; nothing was merged" >&2
           printf 'merge-refused:body-stale\n'
           record_attempt body-stale
           exit 0 ;;
    esac
    REFUSED=$(printf '%s\n' "$RENDER_OUT" | grep '^merge-refused:' | tail -1)
    if [ -n "$REFUSED" ]; then
        printf '%s\n' "$REFUSED"
        exit 0
    fi
    # The coordination PR again, for its state only: it must still be the
    # recorded open PR. Its body is not read here.
    coord_recorded_pr "$SESSION" "$HOME_REPO" open
    case $? in
        0) ;;
        2) exit 72 ;;
        *) exit 73 ;;
    esac
fi

if [ "$NODE" = coordination ]; then
    REPO="$HOME_REPO"; PR="$C_NUM"
    CASCADE=$(rr_cascade "$SESSION") || { echo "$PROG: could not read run/cascade in session $SESSION" >&2; exit 72; }
    HEAD=$(printf '%s' "$CASCADE" | jq -r 'if .verdict == "pushed" then (.head // "") else "" end')
elif [ -n "$FU_OF" ]; then
    # A follow-up: its repository, number and head from its own record, in
    # its node's repository and the write set; no owned-branch lookup (it is
    # a person's PR, on a branch of their own), and the rule every follow-up
    # is held to, read live.
    N_REC=$(rr_node "$SESSION" "$FU_OF")
    case $? in
        0) ;;
        1) echo "$PROG: the run record has no PR for $FU_OF, so $NODE has no node to merge after" >&2; exit 73 ;;
        *) echo "$PROG: could not read $FU_OF's run record" >&2; exit 72 ;;
    esac
    N_REPO=$(printf '%s' "$N_REC" | jq -r '.repo // ""')
    N_PR=$(printf '%s' "$N_REC" | jq -r '.pr // ""')
    FUS=$(rr_follow_ups "$SESSION" "$FU_OF") || { echo "$PROG: could not read $FU_OF's follow-ups" >&2; exit 72; }
    REC=$(printf '%s' "$FUS" | jq -c --argjson p "$FU_NUM" '[.[] | select(.pr == $p)][0] // empty')
    if [ -z "$REC" ] || [ "$(printf '%s' "$REC" | jq -r '.removed // false')" = true ]; then
        echo "$PROG: the run record holds no live follow-up #$FU_NUM for $FU_OF (absent or removed)" >&2
        exit 73
    fi
    REPO=$(printf '%s' "$REC" | jq -r '.repo // ""')
    PR=$(printf '%s' "$REC" | jq -r '.pr // ""')
    HEAD=$(printf '%s' "$REC" | jq -r '.head // ""')
    SETUP_REPOS=$(rr_setup "$SESSION" | jq -r '(.repos // []) | join(",")') \
        || { echo "$PROG: could not read run/setup in session $SESSION" >&2; exit 72; }
    if ! coord_valid_repo "$REPO" || ! [[ $PR =~ ^[1-9][0-9]*$ ]] || [ "$REPO" != "$N_REPO" ] \
        || ! coord_in_list "$REPO" "$SETUP_REPOS"; then
        echo "$PROG: the run record's $NODE names [$REPO] #$PR, not a PR in $FU_OF's repository within the write set" >&2
        exit 73
    fi
    # Only after its node: GitHub must report the node's PR MERGED.
    N_VIEW=""
    coord_gh_read N_VIEW pr view "$N_PR" --repo "$N_REPO" --json state \
        || { echo "$PROG: could not read $FU_OF's PR #$N_PR" >&2; exit 72; }
    if [ "$(printf '%s' "$N_VIEW" | jq -r '.state // ""')" != MERGED ]; then
        echo "$PROG: $FU_OF's PR is not MERGED; its follow-up $NODE merges only after it" >&2
        printf 'merge-refused:predecessor-unmerged\n'
        record_attempt merge-refused
        exit 0
    fi
    coord_gh_read LOGIN api user --jq .login || { echo "$PROG: could not read the authenticated login" >&2; exit 72; }
    coord_follow_up_check "$REPO" "$PR" "$LOGIN" || exit 72
    if [ -n "$FU_FAULT" ]; then
        echo "$PROG: $FU_URL fails the follow-up rule ($FU_FAULT); nothing was merged" >&2
        printf 'merge-refused:follow-up-%s\n' "$FU_FAULT"
        record_attempt merge-refused
        exit 0
    fi
    if [ "$FU_STATE" = MERGED ]; then
        # Already merged (a person merged it): nothing to call, and the body
        # records its merged head as after a merge this run confirmed.
        printf 'merged\n'
        render
        rc=$?
        printf '%s\n' "$RENDER_OUT"
        [ "$rc" -eq 77 ] && exit 77
        exit 0
    fi
else
    REC=$(rr_node "$SESSION" "$NODE")
    case $? in
        0) ;;
        1) echo "$PROG: the run record has no PR for $NODE" >&2; exit 73 ;;
        *) echo "$PROG: could not read $NODE's run record" >&2; exit 72 ;;
    esac
    REPO=$(printf '%s' "$REC" | jq -r '.repo // ""')
    PR=$(printf '%s' "$REC" | jq -r '.pr // ""')
    HEAD=$(printf '%s' "$REC" | jq -r '.head // ""')
    coord_valid_repo "$REPO" && [[ $PR =~ ^[1-9][0-9]*$ ]] || {
        echo "$PROG: the run record for $NODE names no usable repository and PR" >&2
        exit 73
    }
    OUT=$(coord_owned "$REPO" "impl/$SLUG-$NODE" open)
    case $? in
        0) ;;
        2) exit 72 ;;
        *) exit 73 ;;
    esac
    if [ -z "$OUT" ] || [ "${OUT##*/}" != "$PR" ]; then
        echo "$PROG: the run record names #$PR for $NODE, which is not the owned open PR on $REPO impl/$SLUG-$NODE" >&2
        exit 73
    fi
fi

if ! [[ $HEAD =~ $RE_COORD_SHA ]]; then
    # No recorded push: merge-verdict.sh would say head-moved, and merge-exec.sh
    # takes no `none`.
    printf 'merge-refused:awaiting:head-moved\n'
    record_attempt merge-refused
    exit 0
fi

if [ "$NODE" = coordination ]; then
    # The merge-last gate, over every indexed PR but the coordination PR
    # itself, read from the body the render just posted or found equal. Under
    # the run's recorded switch omit the body is Part 1 alone and indexes
    # nothing, so the refs come from the run record instead, in the index's
    # own shape: each recorded node PR and each live follow-up.
    REFS=""
    if [ "$COORD_CONTENT" = omit ]; then
        REFS=$(rr_record "$SESSION" | jq -r --arg slug "$SLUG" '
            .["run/setup"].nodes as $nodes | . as $r
            | $nodes[] | select(.kind == "pr") | .name as $n
            | select($r | has("run/node/\($n)"))
            | ($r["run/node/\($n)"] | "\(.repo):docs/plans/PLAN-\($slug).md#\(.pr)"),
              ($r | to_entries[] | select(.key | startswith("run/follow-up/\($n)/"))
               | select((.value.removed // false) | not)
               | "\(.value.repo):docs/plans/PLAN-\($slug).md#\(.value.pr)")') || REFS=""
    elif [ -f "$SCRATCH/body.md" ]; then
        REFS=$(bash "$REPO_ROOT/scripts/coordination-gate-refs.sh" "$HOME_REPO" "$C_NUM" < "$SCRATCH/body.md") || REFS=""
    else
        echo "$PROG: the render handed back no body for the merge-last gate" >&2
    fi
    set --
    while IFS= read -r ref; do
        [ -n "$ref" ] && set -- "$@" --pr "$ref"
    done <<<"$REFS"
    if [ $# -eq 0 ]; then
        echo "$PROG: the coordination PR's index names no PR to gate on" >&2
        printf 'merge-refused:merge-gate\n'
        record_attempt merge-refused
        exit 0
    fi
    # The gate takes the coordination PR's own visibility: a private one may
    # index private nodes, and without the flag the gate treats it as public
    # and refuses any. Read live; a failed read stops here, never guessed.
    HOME_VIS=$(coord_repo_visibility "$HOME_REPO") || {
        echo "$PROG: could not read the visibility of $HOME_REPO for the merge-last gate" >&2
        exit 72
    }
    [ "$HOME_VIS" = private ] && set -- --visibility private "$@"
    SHIRABE="${SHIRABE_BIN:-shirabe}"
    if ! "$SHIRABE" validate --merge-gate --mode=ready "$@" </dev/null >&2; then
        echo "$PROG: shirabe validate --merge-gate --mode=ready did not pass" >&2
        printf 'merge-refused:merge-gate\n'
        record_attempt merge-refused
        exit 0
    fi
fi

# The squash message: the title and Part 1, never the reviewer context or a
# coordination PR's index.
MSG=$("$BASH" "$COORD_SELF_DIR/merge-message.sh" "$REPO" "$PR" </dev/null)
case $? in
    0) ;;
    1) printf 'merge-refused:squash-message\n'
       record_attempt merge-refused
       exit 0 ;;
    72) exit 72 ;;
    *) echo "$PROG: merge-message.sh failed; nothing was merged" >&2; exit 72 ;;
esac
[ -f "$MSG" ] || { echo "$PROG: merge-message.sh named no message file" >&2; exit 72; }

LINE1=$("$BASH" "$COORD_SELF_DIR/merge-exec.sh" "$REPO" "$PR" "$HEAD" "$MSG" </dev/null)
rm -f "$MSG"
printf '%s\n' "$LINE1"
case "$LINE1" in
    merge-called:*)
        LINE2=$("$BASH" "$COORD_SELF_DIR/merge-verdict.sh" --repo "$REPO" --pr "$PR" --merge true \
            --expected-head "$HEAD" --confirm </dev/null) || LINE2="not-merged:merge-not-observed"
        [ "$LINE2" = merged ] || LINE2="not-merged:merge-not-observed"
        printf '%s\n' "$LINE2"
        if [ "$LINE2" != merged ]; then
            record_attempt merge-not-observed
        elif [ "$NODE" != coordination ]; then
            # A node or follow-up seen merged: the body records its merged head.
            render
            rc=$?
            printf '%s\n' "$RENDER_OUT"
            [ "$rc" -eq 77 ] && exit 77
        fi
        ;;
    merge-refused:not-merged:merge-call-failed)
        record_attempt merge-call-failed
        ;;
    merge-refused:*)
        record_attempt merge-refused
        ;;
esac
exit 0
