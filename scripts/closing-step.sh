#!/usr/bin/env bash
# closing-step.sh -- the checks a session runs on its worktree at a run's end,
# before it writes its handoff brief: nothing left untracked, nothing left
# unpushed.
#
# Usage:
#   scripts/closing-step.sh <worktree> [--instance <root>]
#
# It blocks, with one line per cause, when:
#   - `git status --porcelain --untracked-files=all` lists an untracked file
#     that `git check-ignore` doesn't match (stray: <path>);
#   - HEAD is not on a branch (detached: HEAD);
#   - the branch has no upstream (no-upstream: <branch>);
#   - `git rev-list @{u}..HEAD` lists a commit (unpushed: <sha> <subject>).
# The upstream is read from the local remote-tracking ref; nothing is fetched.
#
# On a pass it prints the instance root for the caller to move to: the
# --instance it was given, or else the directory that holds the worktree's
# repository (the parent of the main checkout). It never deletes the worktree.
# It reports done only when the caller's working directory is outside the
# worktree; inside it, it says to move to the instance root first.
#
# Output, on stdout:
#   closing=blocked            then one cause line each, exit 1
#   closing=pass
#   instance=<root>
#   done=yes | done=no         (done=no: the working directory is inside the
#                               worktree), exit 0
#
# Exit codes:
#   0  pass
#   1  blocked, with the causes named
#   2  an environment fault: git is not on PATH, the worktree is not a
#      directory inside a git work tree, or --instance is not a directory
#
# Every git call runs with core.fsmonitor and core.hooksPath turned off, so a
# repository's own configuration runs nothing here.
#
# bash 3.2.

set -uo pipefail

PROG=closing-step.sh

fault() {
    printf '%s: %s\n' "$PROG" "$1" >&2
    exit 2
}

usage() {
    sed -n '5,6p' "$0" | sed 's/^# \{0,1\}//' >&2
}

# Control characters in a path or subject become `?`, so a name can't move
# the cursor or forge a line of its own.
clean() {
    printf '%s' "$1" | LC_ALL=C tr '[:cntrl:]' '?'
}

wt=""
instance=""
while [ "$#" -gt 0 ]; do
    case "$1" in
        --instance) [ "$#" -ge 2 ] || { usage; fault "--instance needs a directory"; }; instance="$2"; shift ;;
        -h|--help)  usage; exit 0 ;;
        -*)         usage; fault "unknown argument: $1" ;;
        *)
            [ -z "$wt" ] || { usage; fault "one worktree only"; }
            wt="$1"
            ;;
    esac
    shift
done
[ -n "$wt" ] || { usage; fault "name the worktree"; }

command -v git >/dev/null 2>&1 || fault "git is not on PATH"
[ -d "$wt" ] || fault "[$wt] is not a directory"

g() {
    git -c core.fsmonitor=false -c core.hooksPath=/dev/null -C "$wt" "$@"
}

top=$(g rev-parse --show-toplevel) || fault "[$wt] is not inside a git work tree"
[ -n "$top" ] || fault "[$wt] is not inside a git work tree"
top=$(cd "$top" && pwd -P) || fault "cannot resolve [$top]"

causes=()

# Untracked files. -z keeps names with spaces or newlines whole; a rename or
# copy entry carries its source as one more field, which is skipped.
status_file=$(umask 077 && mktemp "${TMPDIR:-/tmp}/closing-step.XXXXXX") || fault "cannot create a temporary file"
trap 'rm -f "$status_file"' EXIT
g status --porcelain=v1 -z --untracked-files=all >"$status_file" || fault "git status failed in [$wt]"
skip_next=0
while IFS= read -r -d '' rec; do
    if [ "$skip_next" -eq 1 ]; then
        skip_next=0
        continue
    fi
    xy="${rec:0:2}"
    path="${rec:3}"
    case "$xy" in
        R*|C*) skip_next=1 ;;
    esac
    [ "$xy" = "??" ] || continue
    if g check-ignore -q -- "$path"; then
        continue
    fi
    causes+=("stray: $(clean "$path")")
done <"$status_file"

# The upstream and what is not on it.
branch=$(g symbolic-ref --quiet --short HEAD) || branch=""
if [ -z "$branch" ]; then
    causes+=("detached: HEAD is not on a branch, so nothing can be pushed")
elif ! upstream=$(g rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null) || [ -z "$upstream" ]; then
    causes+=("no-upstream: $(clean "$branch") has no upstream; push it with -u first")
else
    log=$(g log --format='%H %s' "@{u}..HEAD") || fault "git log @{u}..HEAD failed in [$wt]"
    if [ -n "$log" ]; then
        while IFS= read -r line; do
            causes+=("unpushed: $(clean "$line")")
        done <<EOF
$log
EOF
    fi
fi

if [ "${#causes[@]}" -gt 0 ]; then
    printf 'closing=blocked\n'
    for c in "${causes[@]}"; do
        printf '%s\n' "$c"
    done
    exit 1
fi

# The instance root.
if [ -n "$instance" ]; then
    [ -d "$instance" ] || fault "--instance [$instance] is not a directory"
    root=$(cd "$instance" && pwd -P) || fault "cannot resolve --instance [$instance]"
else
    common=$(g rev-parse --git-common-dir) || fault "git rev-parse --git-common-dir failed in [$wt]"
    case "$common" in
        /*) ;;
        *) common="$top/$common" ;;
    esac
    common=$(cd "$common" && pwd -P) || fault "cannot resolve the repository's git directory"
    case "$common" in
        */.git) repo="${common%/.git}" ;;
        *) repo="$common" ;;
    esac
    root=$(cd "$repo/.." && pwd -P) || fault "cannot resolve the directory above [$repo]"
fi

printf 'closing=pass\n'
printf 'instance=%s\n' "$root"

here=$(pwd -P) || fault "cannot resolve the working directory"
case "$here/" in
    "$top"/*)
        printf 'done=no\n'
        printf '%s: the working directory is inside the worktree; cd %s, then run this again\n' "$PROG" "$root" >&2
        ;;
    *)
        printf 'done=yes\n'
        ;;
esac
exit 0
