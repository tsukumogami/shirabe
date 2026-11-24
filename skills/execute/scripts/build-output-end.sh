#!/usr/bin/env bash
# build-output-end.sh — for /execute: at the run's successful end, clean the
# declared build output of each worktree the run recorded.
#
# Usage: build-output-end.sh --session <S> [--switch-root <dir>]
#
#   <S>            the run's koto session, execute-<plan-slug>
#   --switch-root  the work tree whose CLAUDE.local.md turns the cleanup on;
#                  by default the root of the work tree this runs in, which is
#                  the parent's own checkout (the coordination checkout on a
#                  coordinated run). Node worktrees node-cut.sh made carry no
#                  CLAUDE.local.md of their own, so they follow the parent's.
#
# The `merged` and `ready_awaiting_merge` directives of execute.md and
# execute-coordinated.md run this after print-exit.sh, as
# `test -x <this> && <this> --session <S>; true`. The run is already at its
# terminal then, so nothing found here can change its outcome, and nothing
# koto-timed runs it. No other state calls it: plan_completion runs before CI
# is watched, and done_blocked, done_error, paused_for_review and
# paused_awaiting_merges are not successful ends.
#
# The recorded worktrees are the run record's `run/cleanup/<id>` keys, each
# {path, pin}, written once by build-output-pin.sh: `single` on single-pr, one
# per node on coordinated. The record is read with run-record-lib.sh, and
# nothing in it is written here. For each, in id order:
#
#   1. On coordinated, a node with `run/node/<node>` and no
#      `run/cleanup/<node>` (a pin never written, a recovered run) prints
#      `build-output: <node> base unreadable, removed nothing`; so does a
#      single-pr session with no `run/cleanup/single`.
#   2. The path must still be a work tree root (`git rev-parse
#      --show-toplevel` prints it) whose checked-out branch is the one the run
#      recorded for it: `settled_branch` on single-pr, `impl/<plan-slug>-<node>`
#      on coordinated. Otherwise `build-output: <id> worktree unverified,
#      removed nothing`, so a stale path, or one naming someone's own clone,
#      is never cleaned.
#   3. The worktree's own pull request's hosted CI, read with the chain
#      execute.md's owned_ci_passing gate runs: the PR through owned-pr.sh
#      (--state open-else-merged, the run's --run-id, an empty selector read
#      as no PR), its checks through pr-checks.sh (at least one, every one in
#      the pass or skipping bucket), then ci-cancel-after-merge.sh --owned,
#      then ci-none-declared.sh --owned. Single-pr reads the run's PR on
#      `repos` and `settled_branch`; a node reads its own node PR on the
#      repository run/node/<node> records. The cancel-after-merge fallback
#      reads the floor list of the checkout this runs in, so it is asked only
#      for a PR in this checkout's own repository (single-pr's, or a node in
#      `home_repo`); a node elsewhere whose only non-green checks are cancelled
#      floor runs keeps its tree. The route that reached the terminal is not
#      trusted to mean green: ready_awaiting_merge can follow a DIRTY merge
#      state or a pending CI. Not green prints `build-output: <id> CI not
#      green, removed nothing`.
#   4. Otherwise `build-output: <id> cleaning <path>`, then
#      `clean-build-output.sh --base <pin> --root <path> --switch-root
#      <switch root>` with its default walk budget, its lines passed through
#      unchanged. The pin goes in as recorded and is never recomputed: after
#      the branch merged, a fresh merge base would be the branch head.
#
# Every block starts with a line beginning `build-output: <id>`. All the lines
# are printed and written once, as the session's `build_output_cleanup`
# context key. The script exits 0 whatever happened: a CI read that fails, a
# missing cleanup script or an unreadable record each print a line and change
# nothing else.
#
# Requires: bash 3.2+, git, jq, koto, gh (through the CI scripts).
set -uo pipefail

PROG=build-output-end

SELF_DIR=$(CDPATH='' cd "$(dirname "${BASH_SOURCE[0]}")" && pwd) || exit 0
WORKON_DIR="$SELF_DIR/../../work-on/scripts"
CLEAN="$WORKON_DIR/clean-build-output.sh"
PR_CHECKS="$WORKON_DIR/pr-checks.sh"
CANCEL="$WORKON_DIR/ci-cancel-after-merge.sh"
NONE_DECLARED="$WORKON_DIR/ci-none-declared.sh"
OWNED="$SELF_DIR/owned-pr.sh"
# shellcheck source=run-record-lib.sh
. "$SELF_DIR/run-record-lib.sh"

SESSION=""; SWITCH_ROOT=""
while [ $# -gt 0 ]; do
    case "$1" in
        --session|--switch-root)
            [ $# -ge 2 ] || { echo "$PROG: $1 needs a value" >&2; exit 0; }
            case "$1" in
                --session) SESSION="$2" ;;
                --switch-root) SWITCH_ROOT="$2" ;;
            esac
            shift 2
            ;;
        *) echo "$PROG: unexpected argument [$1]" >&2; exit 0 ;;
    esac
done
if ! [[ $SESSION =~ ^execute-[a-z0-9-]+$ ]]; then
    echo "$PROG: session [$SESSION] is not an /execute session; nothing was removed" >&2
    exit 0
fi
SLUG=${SESSION#execute-}

LINES=""
say() { LINES="$LINES$*"$'\n'; }

# finish -- print every line and write them once as build_output_cleanup.
finish() {
    printf '%s' "$LINES"
    printf '%s' "$LINES" | koto context add "$SESSION" build_output_cleanup >/dev/null \
        || echo "$PROG: could not write build_output_cleanup in $SESSION" >&2
    exit 0
}

command -v jq >/dev/null || { say "build-output: jq is not on PATH, removed nothing"; finish; }

if [ -z "$SWITCH_ROOT" ]; then
    SWITCH_ROOT=$(git rev-parse --show-toplevel) || SWITCH_ROOT=""
fi
if [ -n "$SWITCH_ROOT" ]; then
    SWITCH_ROOT=$(CDPATH='' cd -- "$SWITCH_ROOT" 2>/dev/null && pwd -P) || SWITCH_ROOT=""
fi

REC=$(rr_record "$SESSION" 2>/dev/null) || {
    say "build-output: run record unreadable, removed nothing"
    finish
}

# ctx <key> -- a koto context value, empty when absent or unreadable. The
# exists check keeps an absent key quiet, so get's stderr is kept for a real
# read failure.
ctx() {
    koto context exists "$SESSION" "$1" </dev/null >/dev/null || return 0
    koto context get "$SESSION" "$1" </dev/null || true
}

RUN_ID=$("$BASH" "$SELF_DIR/run-id.sh" get "$SESSION" </dev/null 2>/dev/null) || RUN_ID=""
[[ $RUN_ID =~ ^[0-9a-f]{32}$ ]] || RUN_ID=""

# ci_green <repo> <branch> <cancel_ok> -- the owned_ci_passing chain for the
# PR the run owns on <branch> in <repo>. An empty selector, or no PR, is not
# green; the fallbacks still run, as the gate runs them, and each refuses an
# empty lookup itself.
ci_green() {
    local repo="$1" branch="$2" cancel_ok="$3" pr=""
    [ -n "$repo" ] && [ -n "$branch" ] && [ -n "$RUN_ID" ] || return 1
    pr=$("$BASH" "$OWNED" --repo "$repo" --head "$branch" --state open-else-merged --run-id "$RUN_ID" </dev/null 2>/dev/null) || pr=""
    if [ -n "$pr" ] && "$BASH" "$PR_CHECKS" "$pr" --json bucket \
        --jq 'length > 0 and ([.[] | select(.bucket != "pass" and .bucket != "skipping")] | length == 0)' \
        </dev/null 2>/dev/null | grep -q true; then
        return 0
    fi
    if [ "$cancel_ok" = 1 ] && "$BASH" "$CANCEL" "$SESSION" --owned --repo "$repo" --head "$branch" \
        --state open-else-merged --run-id "$RUN_ID" </dev/null >/dev/null 2>&1; then
        return 0
    fi
    "$BASH" "$NONE_DECLARED" "$SESSION" --owned --repo "$repo" --head "$branch" \
        --state open-else-merged --run-id "$RUN_ID" </dev/null >/dev/null 2>&1
}

# clean_one <id> <repo> <branch> <cancel_ok> -- steps 2 to 4 for one recorded
# worktree.
clean_one() {
    local id="$1" repo="$2" branch="$3" cancel_ok="$4" obj path pin top cur out
    obj=$(printf '%s' "$REC" | jq -c --arg k "run/cleanup/$id" '.[$k] // empty') || obj=""
    if [ -z "$obj" ]; then
        say "build-output: $id base unreadable, removed nothing"
        return
    fi
    path=$(printf '%s' "$obj" | jq -r '.path // ""')
    pin=$(printf '%s' "$obj" | jq -r '.pin // ""')
    if ! [[ $pin =~ ^[0-9a-f]{40}$ ]]; then
        say "build-output: $id base unreadable, removed nothing"
        return
    fi
    top=""; cur=""
    if [ -n "$path" ] && [ -d "$path" ]; then
        top=$(git -C "$path" rev-parse --show-toplevel) || top=""
        [ -n "$top" ] && top=$(CDPATH='' cd -- "$top" 2>/dev/null && pwd -P)
        cur=$(git -C "$path" symbolic-ref --quiet --short HEAD) || cur=""
        path=$(CDPATH='' cd -- "$path" 2>/dev/null && pwd -P) || path=""
    fi
    if [ -z "$path" ] || [ "$top" != "$path" ] || [ -z "$branch" ] || [ "$cur" != "$branch" ]; then
        say "build-output: $id worktree unverified, removed nothing"
        return
    fi
    if ! ci_green "$repo" "$branch" "$cancel_ok"; then
        say "build-output: $id CI not green, removed nothing"
        return
    fi
    if [ ! -x "$CLEAN" ] || [ -z "$SWITCH_ROOT" ]; then
        say "build-output: $id cleanup unavailable, removed nothing"
        return
    fi
    say "build-output: $id cleaning $path"
    out=$("$CLEAN" --base "$pin" --root "$path" --switch-root "$SWITCH_ROOT" </dev/null 2>/dev/null) || true
    if [ -n "$out" ]; then say "$out"; fi
}

if rr_q "$REC" 'has("run/setup")' | grep -qx true; then
    # Coordinated: every node the record knows, pinned or not.
    HOME_REPO=$(ctx home_repo)
    IDS=$(rr_q "$REC" '[keys[] | select(startswith("run/node/") or startswith("run/cleanup/")) | split("/")[2]] | unique | .[]')
    while IFS= read -r id; do
        [ -n "$id" ] || continue
        repo=$(printf '%s' "$REC" | jq -r --arg k "run/node/$id" '.[$k].repo // ""') || repo=""
        cancel_ok=0
        [ -n "$repo" ] && [ "$repo" = "$HOME_REPO" ] && cancel_ok=1
        clean_one "$id" "$repo" "impl/$SLUG-$id" "$cancel_ok"
    done <<<"$IDS"
else
    # Single-pr: the run's one worktree, on its settled branch.
    clean_one single "$(ctx repos)" "$(ctx settled_branch)" 1
fi
finish
