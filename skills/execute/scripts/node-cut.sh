#!/usr/bin/env bash
# node-cut.sh — for /execute: cut a coordinated PR node's branch in its own
# worktree.
#
# The PR node, not the repository, is the unit of branching in a coordinated
# run: each node gets `impl/<slug>-<node-id>`, cut from the tip of the
# repository's default branch, in a dedicated `git worktree`. Never from the
# coordination branch, a predecessor's branch, or HEAD: a node branch must not
# carry the PLAN or the planning chain to the default branch ahead of the
# coordination PR, and a predecessor's work reaches it only by merging first.
#
# Re-running it for a node whose worktree already exists reuses that worktree
# and never re-cuts or rebases the branch. A branch that exists without a
# worktree (locally, or only on the remote after a resume elsewhere) gets a
# worktree on the branch as it stands.
#
# Usage: node-cut.sh <slug> <node-id> [--repo-dir <dir>] [--worktree-root <dir>]
#
#   <slug>           ^[a-z0-9-]+$
#   <node-id>        plan-to-tasks.sh's node-name pattern ^[a-z][a-z0-9-]*$
#   --repo-dir       a local clone of the node's repository; default the
#                    repository of the current directory. A node in another
#                    repository is cut in that repository's clone.
#   --worktree-root  where node worktrees live; default
#                    <git-common-dir>/shirabe-node-worktrees, outside every
#                    work tree. The worktree is <root>/<slug>-<node-id>.
#
# Output (stdout), one key=value per line:
#   worktree=<absolute path>
#   branch=impl/<slug>-<node-id>
#   base=<sha>        the default-branch tip the branch was cut from (on a
#                     fresh cut only)
#   cut=new|reused|attached
#
# Exit codes:
#   0   the worktree is ready
#   64  usage error: a slug or node id outside its pattern, a bad directory
#   65  the default branch could not be fetched
#   66  git worktree add failed
#
# Requires: bash 3.2+, git.
set -uo pipefail

PROG=node-cut

usage_error() {
    echo "$PROG: $*" >&2
    echo "usage: node-cut.sh <slug> <node-id> [--repo-dir <dir>] [--worktree-root <dir>]" >&2
    exit 64
}

[ $# -ge 2 ] || usage_error "expected <slug> <node-id>"
SLUG="$1"; NODE="$2"; shift 2
[[ $SLUG =~ ^[a-z0-9-]+$ ]] || usage_error "slug [$SLUG] is outside ^[a-z0-9-]+\$"
[[ $NODE =~ ^[a-z][a-z0-9-]*$ ]] || usage_error "node id [$NODE] is outside ^[a-z][a-z0-9-]*\$"

REPO_DIR=""; WT_ROOT=""
SEEN=" "
while [ $# -gt 0 ]; do
    case "$1" in
        --repo-dir|--worktree-root)
            [ $# -ge 2 ] || usage_error "$1 needs a value"
            case "$SEEN" in *" $1 "*) usage_error "$1 given more than once" ;; esac
            SEEN="$SEEN$1 "
            case "$1" in
                --repo-dir) REPO_DIR="$2" ;;
                --worktree-root) WT_ROOT="$2" ;;
            esac
            shift 2
            ;;
        *) usage_error "unexpected argument [$1]" ;;
    esac
done

if [ -n "$REPO_DIR" ]; then
    cd -- "$REPO_DIR" || usage_error "no directory [$REPO_DIR]"
fi
TOP=$(git rev-parse --show-toplevel) || usage_error "not inside a git repository"
cd -- "$TOP" || exit 64
COMMON=$(CDPATH='' cd "$(git rev-parse --git-common-dir)" && pwd -P) || usage_error "no git common dir"
[ -n "$WT_ROOT" ] || WT_ROOT="$COMMON/shirabe-node-worktrees"
mkdir -p -- "$WT_ROOT" || usage_error "cannot create [$WT_ROOT]"
WT_ROOT=$(CDPATH='' cd "$WT_ROOT" && pwd -P) || usage_error "cannot resolve [$WT_ROOT]"

BRANCH="impl/$SLUG-$NODE"
WT="$WT_ROOT/$SLUG-$NODE"

# A worktree already holding the branch is reused as it stands.
EXISTING=$(git worktree list --porcelain | awk -v ref="refs/heads/$BRANCH" '
    /^worktree / { wt = substr($0, 10) }
    /^branch / && substr($0, 8) == ref { print wt; exit }')
if [ -n "$EXISTING" ]; then
    printf 'worktree=%s\nbranch=%s\ncut=reused\n' "$EXISTING" "$BRANCH"
    exit 0
fi

# The remote's default branch: its own answer first, then the local symref.
DEFAULT=$(git ls-remote --symref origin HEAD </dev/null \
    | sed -n 's#^ref: refs/heads/\([^[:space:]]*\)[[:space:]]*HEAD$#\1#p' | head -1)
if [ -z "$DEFAULT" ]; then
    DEFAULT=$(git symbolic-ref --quiet --short refs/remotes/origin/HEAD || true)
    DEFAULT=${DEFAULT#origin/}
fi
[ -n "$DEFAULT" ] || { echo "$PROG: cannot tell origin's default branch" >&2; exit 65; }
[[ $DEFAULT =~ ^[A-Za-z0-9._/-]+$ ]] || { echo "$PROG: unusable default branch [$DEFAULT]" >&2; exit 65; }

if git show-ref --verify --quiet "refs/heads/$BRANCH"; then
    # The branch exists without a worktree: attach one, never re-cut it.
    git worktree add -q -- "$WT" "$BRANCH" >&2 || { echo "$PROG: git worktree add failed" >&2; exit 66; }
    printf 'worktree=%s\nbranch=%s\ncut=attached\n' "$WT" "$BRANCH"
    exit 0
fi

git fetch -q origin "+refs/heads/$DEFAULT:refs/remotes/origin/$DEFAULT" </dev/null >&2 || {
    echo "$PROG: could not fetch origin's $DEFAULT" >&2
    exit 65
}
if git ls-remote --exit-code --heads origin "refs/heads/$BRANCH" </dev/null >/dev/null; then
    git fetch -q origin "+refs/heads/$BRANCH:refs/remotes/origin/$BRANCH" </dev/null >&2 || {
        echo "$PROG: could not fetch origin's $BRANCH" >&2
        exit 65
    }
    # Pushed from another checkout: continue that branch, never re-cut it.
    git worktree add -q -b "$BRANCH" -- "$WT" "refs/remotes/origin/$BRANCH" >&2 \
        || { echo "$PROG: git worktree add failed" >&2; exit 66; }
    printf 'worktree=%s\nbranch=%s\ncut=attached\n' "$WT" "$BRANCH"
    exit 0
fi

TIP=$(git rev-parse --verify "refs/remotes/origin/$DEFAULT^{commit}") || {
    echo "$PROG: origin/$DEFAULT does not resolve" >&2
    exit 65
}
git worktree add -q --no-track -b "$BRANCH" -- "$WT" "$TIP" >&2 || {
    echo "$PROG: git worktree add failed" >&2
    exit 66
}
printf 'worktree=%s\nbranch=%s\nbase=%s\ncut=new\n' "$WT" "$BRANCH" "$TIP"
exit 0
