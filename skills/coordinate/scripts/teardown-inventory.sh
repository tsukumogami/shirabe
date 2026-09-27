#!/usr/bin/env bash
# teardown-inventory.sh -- what does a worker's instance hold that exists
# nowhere else?
#
# A coordinator destroys a worker's instance only once nothing in it would be
# lost. This script inventories every git repository in the instance,
# worktrees included, and prints a verdict per repository. It never destroys,
# stops or deletes anything: the destroy is the coordinator's, one instance at
# a time, after this passes.
#
# Durability is proven by content, never by ancestry. A squash merge lands a
# branch's changes as a new commit, so every finished branch looks unmerged to
# `git branch --no-merged`. For a branch whose head is on no remote branch,
# the check diffs the branch head's tree, over the paths the branch changed,
# against the squash merge commit of the merged pull request whose head was
# that branch; only when no merged pull request exists does it compare
# against the default branch's head. Comparing against the merge commit keeps a
# later change to the same paths on the default branch from reading as unique
# work.
#
# Per repository (each is `unique` on the first finding):
#
#   1. `git fetch --prune origin`, under a short deadline, so a remote branch
#      deleted without merging doesn't still look pushed. A fetch that fails
#      or misses the deadline makes the repository an error.
#   2. Uncommitted or untracked changes (`git status --porcelain
#      --untracked-files=all`).
#   3. Stash entries.
#   4. Each local branch, and a detached HEAD, whose head is on no remote
#      branch, checked by content as above.
#
# Anything it can't classify (a submodule, a repository it can't read, a
# pull request lookup that fails) is an error, never `durable`.
#
# Usage:
#   teardown-inventory.sh --topic <topic> [--instance <dir>] [--seal --session <s>]
#
#   --instance  the instance directory; found by the topic's worker session
#               in `niwa list --json` when absent
#   --seal      run as the teardown state's default action: store the verdict
#               through the record feature's seal helper and print its
#               `sealed:<seq>:<sha256>` token, which the state captures. The
#               state's gate checks the stored verdict against the seal, so
#               the verdict can't be edited after the fact, and the destroy
#               directive reads it through the helper's reader, which refuses
#               a destroy entered by a directed transition (koto#251).
#
# Output: one line per repository, `durable <path> (vs <target>)` or
# `unique <path>: <why> (vs <target>)` or `error <path>: <why>`, each path
# relative to the instance and each target `merge <sha>`, `default <branch>`
# or `-`. With --seal, the verdict goes to the seal helper and stdout carries
# only the token.
#
# Exit codes: 0 every repository durable; 1 at least one unique; 2 an error,
# no instance found, or usage.
#
# Writes nothing but the remote-tracking refs its fetches update (and, with
# --seal, the sealed verdict). bash 3.2; needs git, jq, and gh for the pull
# request lookup.
set -uo pipefail

PROG=teardown-inventory
HERE=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=dispatch-common.sh
. "$HERE/dispatch-common.sh"

GH="${GH:-gh}"
FETCH_SECS="${TEARDOWN_FETCH_SECS:-6}"
# The whole scan's budget. As the teardown state's default action this has
# koto's 30 seconds, and an action killed there is a failure, not a verdict;
# a repository the budget doesn't reach is an error, never durable.
TOTAL_SECS="${TEARDOWN_TOTAL_SECS:-24}"
STARTED=$(date +%s)

usage() { printf 'usage: %s --topic <topic> [--instance <dir>] [--seal --session <s>]\n' "$PROG" >&2; exit 2; }

TOPIC=""
INSTANCE=""
SEAL=0
SESSION=""
while [ $# -gt 0 ]; do
    case "$1" in
        --topic) [ $# -ge 2 ] || usage; TOPIC="$2"; shift 2 ;;
        --instance) [ $# -ge 2 ] || usage; INSTANCE="$2"; shift 2 ;;
        --seal) SEAL=1; shift ;;
        --session) [ $# -ge 2 ] || usage; SESSION="$2"; shift 2 ;;
        *) usage ;;
    esac
done
dc_valid_topic "$TOPIC" || usage
[ "$SEAL" = 0 ] || [ -n "$SESSION" ] || usage

if [ -z "$INSTANCE" ]; then
    ROOT=$(dc_workspace_root) || { printf '%s: no workspace root found\n' "$PROG" >&2; exit 2; }
    FOUND=$(dc_find_session "$ROOT" "$TOPIC")
    case "$?" in
        0) INSTANCE=${FOUND#*	} ;;
        1) printf '%s: no instance for %s\n' "$PROG" "$TOPIC" >&2; exit 2 ;;
        *) printf '%s: niwa list could not be read\n' "$PROG" >&2; exit 2 ;;
    esac
fi
INSTANCE=$(cd "$INSTANCE" 2>/dev/null && pwd -P) || { printf '%s: no instance directory for %s\n' "$PROG" "$TOPIC" >&2; exit 2; }

WORK=$(mktemp -d "${TMPDIR:-/tmp}/teardown-inventory.XXXXXX") || exit 2
trap 'rm -rf "$WORK"' EXIT
VERDICT="$WORK/verdict"
: >"$VERDICT"
WORST=0

note() {
    # note <level 0|1|2> <line>
    printf '%s\n' "$2" >>"$VERDICT"
    [ "$1" -gt "$WORST" ] && WORST="$1"
}

# owner/repo of a clone's origin as configured (before any insteadOf
# rewrite), or empty for a non-GitHub origin.
origin_repo() {
    git -C "$1" config --get remote.origin.url |
        sed -n -e 's#^https://github.com/\([^/]*/[^/]*\)$#\1#p' -e 's#^git@github.com:\([^/]*/[^/]*\)$#\1#p' |
        sed -e 's#\.git$##'
}

check_repo() {
    local dir="$1" rel="$2" g=(git -C "$1")
    if [ -n "$("${g[@]}" rev-parse --show-superproject-working-tree)" ]; then
        note 2 "error $rel: a submodule, which this inventory doesn't classify"
        return
    fi
    if ! dc_with_deadline "$FETCH_SECS" "${g[@]}" fetch --prune --quiet origin >"$WORK/fetch.out" 2>&1; then
        note 2 "error $rel: git fetch origin failed or timed out ($(tail -1 "$WORK/fetch.out"))"
        return
    fi
    local default
    default=$("${g[@]}" symbolic-ref --quiet --short refs/remotes/origin/HEAD) || default=""
    if [ -z "$default" ]; then
        for b in origin/main origin/master; do
            "${g[@]}" rev-parse --verify --quiet "$b" >/dev/null && { default="$b"; break; }
        done
    fi
    [ -n "$default" ] || { note 2 "error $rel: no default branch on origin"; return; }

    local why="" targets=""
    local porcelain
    porcelain=$("${g[@]}" status --porcelain --untracked-files=all) || { note 2 "error $rel: git status failed"; return; }
    [ -n "$porcelain" ] && why="${why}uncommitted or untracked changes; "
    [ -n "$("${g[@]}" stash list)" ] && why="${why}stash entries; "

    local repo
    repo=$(origin_repo "$dir")
    # Branches, and a detached HEAD, as "<name><TAB><sha>".
    {
        "${g[@]}" for-each-ref --format='%(refname:short)	%(objectname)' refs/heads/
        if ! "${g[@]}" symbolic-ref --quiet HEAD >/dev/null; then
            printf 'HEAD\t%s\n' "$("${g[@]}" rev-parse HEAD)"
        fi
    } >"$WORK/branches"
    local name sha paths target merge
    while IFS='	' read -r name sha; do
        [ -n "$sha" ] || continue
        # On a remote branch: its commits survive this instance.
        # Only origin was fetched and pruned, so only its refs can vouch.
        [ -n "$("${g[@]}" branch -r --contains "$sha" --list 'origin/*')" ] && continue
        paths=$("${g[@]}" diff --no-renames --name-only "$("${g[@]}" merge-base "$default" "$sha")" "$sha") || {
            note 2 "error $rel: cannot diff $name against $default"
            return
        }
        target="$default"
        if [ "$name" != HEAD ] && [ -n "$repo" ]; then
            if ! dc_with_deadline "$FETCH_SECS" "$GH" pr list --repo "$repo" --head "$name" --state merged \
                --json mergeCommit --jq '.[0].mergeCommit.oid // ""' >"$WORK/gh.out" 2>"$WORK/gh.err"; then
                note 2 "error $rel: the merged pull request for $name could not be looked up ($(tail -1 "$WORK/gh.err"))"
                return
            fi
            merge=$(cat "$WORK/gh.out")
            if [ -n "$merge" ]; then
                "${g[@]}" cat-file -e "$merge^{commit}" || dc_with_deadline "$FETCH_SECS" "${g[@]}" fetch --quiet origin "$merge" >"$WORK/fetch.out" 2>&1 || {
                    note 2 "error $rel: merge commit $merge for $name could not be fetched ($(tail -1 "$WORK/fetch.out"))"
                    return
                }
                target="$merge"
            fi
        fi
        targets="$targets $([ "$target" = "$default" ] && echo "default ${default#origin/}" || echo "merge $target")"
        [ -z "$paths" ] && continue
        local differ
        differ=$(printf '%s\n' "$paths" | while IFS= read -r p; do
            "${g[@]}" diff --no-renames --quiet "$target" "$sha" -- "$p" || printf '%s ' "$p"
        done)
        [ -n "$differ" ] && why="${why}${name} changed ${differ% } unlike its target; "
    done <"$WORK/branches"

    local shown="${targets# }"
    [ -n "$shown" ] || shown=-
    if [ -n "$why" ]; then
        note 1 "unique $rel: ${why%; } (vs $shown)"
    else
        note 0 "durable $rel (vs $shown)"
    fi
}

# Every repository and worktree: each has a .git directory or file.
find "$INSTANCE" -name .git -prune -print >"$WORK/gits"

# A bare repository has no .git, so the search above can't see it: look for a
# HEAD file beside objects/ and refs/ outside any .git directory. This
# inventory doesn't classify one, and an unclassified repository is never
# durable.
find "$INSTANCE" -name .git -prune -o -type f -name HEAD -print >"$WORK/heads"
while IFS= read -r head; do
    dir=$(dirname "$head")
    [ -d "$dir/objects" ] && [ -d "$dir/refs" ] || continue
    if [ "$(git -C "$dir" rev-parse --is-bare-repository)" = true ]; then
        rel=${dir#"$INSTANCE"}
        rel=${rel#/}
        note 2 "error ${rel:-.}: a bare repository, which this inventory doesn't classify"
    fi
done <"$WORK/heads"

if [ ! -s "$WORK/gits" ] && [ "$WORST" -eq 0 ]; then
    note 0 "durable . (vs -): no git repositories"
fi
while IFS= read -r gitpath; do
    dir=$(dirname "$gitpath")
    rel=${dir#"$INSTANCE"}
    rel=${rel#/}
    [ -n "$rel" ] || rel=.
    if [ $(( $(date +%s) - STARTED )) -ge "$TOTAL_SECS" ]; then
        note 2 "error $rel: not inventoried; the scan ran out of its ${TOTAL_SECS}s budget"
        continue
    fi
    if ! git -C "$dir" rev-parse --git-dir >/dev/null; then
        note 2 "error $rel: not a readable git repository"
        continue
    fi
    check_repo "$dir" "$rel"
done <"$WORK/gits"

if [ "$SEAL" = 1 ]; then
    # As a default action this exits 0 whatever the verdict: a non-zero exit
    # is an action failure, and a failed action's gates never run. The gate
    # reads the sealed verdict and routes on it.
    case "$WORST" in
        0) WORD=durable ;;
        1) WORD=unique ;;
        *) WORD=error ;;
    esac
    printf '%s %s\n' "$WORD" "$(cat "$VERDICT")" | tr '\n' ' ' >"$WORK/sealed"
    TOKEN=$(dc_seal "$SESSION" teardown "$WORK/sealed" teardown_verdict) || { printf '%s: sealing the verdict failed\n' "$PROG" >&2; exit 2; }
    cat "$VERDICT" >&2
    printf '%s %s\n' "$WORD" "$TOKEN"
    exit 0
fi
cat "$VERDICT"
exit "$WORST"
