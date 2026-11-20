#!/usr/bin/env bash
# start-commit.sh — for /execute's orchestrator_setup: give the shared branch
# impl/<slug> a commit of its own when it has none, so its draft PR can be
# opened.
#
# GitHub refuses a pull request whose head has no commit the base lacks ("No
# commits between main and impl/<slug>"). In the usual flow the PLAN commit
# sits on impl/<slug>, so the branch is already ahead when the draft PR is
# created. When an earlier pull request merged the PLAN to the default branch,
# impl/<slug> is cut at the default branch's head and has nothing of its own,
# so the create fails and the run can't leave orchestrator_setup. This script
# runs in step 2 before push-and-record.sh: when the branch has no commit the
# remote's default branch lacks, it adds one empty commit, and otherwise it
# changes nothing. A re-run finds the branch already ahead and changes nothing.
#
# The commit carries HEAD's own tree, so it changes no file, and it is written
# with `git commit-tree` and moved onto the branch with `git update-ref`, which
# checks the branch still points where it was read. Nothing staged reaches the
# commit, the index and work tree are left as they are, and no commit hook
# runs. Its subject is a Conventional Commits one with no trailer, which
# pr_finalization's settled_commits check requires of every commit on the
# shared branch. The script never pushes: push-and-record.sh, run next, pushes
# the branch and records the start commit as expected_head. It is a script of
# its own rather than a flag on push-and-record.sh because every fix push from
# ci_monitor goes through that script, which stays exactly a push.
#
# Usage: start-commit.sh --plan-slug <slug> [--remote <remote>]
#
#   --plan-slug  ^[a-z0-9-]+$; the checked-out branch must be impl/<slug>
#   --remote     ^[A-Za-z0-9._-]+$, not starting with `-`; default origin
#
# Each flag appears at most once, as `--flag value`.
#
# The default branch is read as push-and-record.sh reads it: the remote's own
# answer (`git ls-remote --symref <remote> HEAD`) first, the local
# refs/remotes/<remote>/HEAD second. It is then fetched, so the count is taken
# against the remote's current head, not a local copy that may be stale.
#
# Output: one line on stdout, `created <sha>` when the start commit was made or
# `unchanged <sha>` when the branch already had a commit of its own, where
# <sha> is HEAD afterwards. Diagnostics go to stderr.
#
# Exit codes:
#   0   the branch has a commit the default branch lacks (made now, or already)
#   64  usage error; nothing read or changed
#   65  HEAD is detached
#   66  the checked-out branch is not impl/<slug>
#   67  the branch is the remote's default branch
#   68  the default branch could not be read or fetched; nothing changed
#   69  the commit could not be written, or the branch moved; nothing changed
#
# Requires: bash 3.2+, git.
set -uo pipefail

PROG=start-commit

RE_SLUG='^[a-z0-9-]+$'
RE_REMOTE='^[A-Za-z0-9._][A-Za-z0-9._-]*$'
RE_SHA='^[0-9a-f]{40}$'

usage_error() {
    echo "$PROG: $*" >&2
    echo "usage: start-commit.sh --plan-slug <slug> [--remote <remote>]" >&2
    exit 64
}

SLUG=""; REMOTE="origin"
SEEN=" "
while [ $# -gt 0 ]; do
    case "$1" in
        --plan-slug|--remote)
            [ $# -ge 2 ] || usage_error "$1 needs a value"
            case "$SEEN" in *" $1 "*) usage_error "$1 given more than once" ;; esac
            SEEN="$SEEN$1 "
            case "$1" in
                --plan-slug) SLUG="$2" ;;
                --remote) REMOTE="$2" ;;
            esac
            shift 2
            ;;
        *) usage_error "unexpected argument [$1]" ;;
    esac
done

[[ $SLUG =~ $RE_SLUG ]] || usage_error "--plan-slug [$SLUG] must match ^[a-z0-9-]+\$"
[[ $REMOTE =~ $RE_REMOTE ]] || usage_error "--remote [$REMOTE] is not a remote name"

BRANCH=$(git symbolic-ref --quiet --short HEAD) || {
    echo "$PROG: HEAD is detached, so there is no branch to start. Check out impl/$SLUG." >&2
    exit 65
}
if [ "$BRANCH" != "impl/$SLUG" ]; then
    echo "$PROG: refusing branch [$BRANCH]: the start commit goes only on this PLAN's branch impl/$SLUG" >&2
    exit 66
fi

DEFAULT=$(git ls-remote --symref "$REMOTE" HEAD </dev/null 2>/dev/null \
    | sed -n 's#^ref: refs/heads/\([^[:space:]]*\)[[:space:]]*HEAD$#\1#p')
DEFAULT=${DEFAULT%%$'\n'*}
if [ -z "$DEFAULT" ]; then
    DEFAULT=$(git symbolic-ref --quiet --short "refs/remotes/$REMOTE/HEAD" || true)
    DEFAULT=${DEFAULT#"$REMOTE"/}
fi
if [ -z "$DEFAULT" ]; then
    echo "$PROG: could not read $REMOTE's default branch, so there is nothing to count against; nothing changed" >&2
    exit 68
fi
if [ "$BRANCH" = "$DEFAULT" ]; then
    echo "$PROG: refusing [$BRANCH]: it is the default branch of $REMOTE" >&2
    exit 67
fi

if ! git fetch --quiet --no-tags "$REMOTE" "refs/heads/$DEFAULT" </dev/null >&2; then
    echo "$PROG: could not fetch $REMOTE's $DEFAULT; nothing changed" >&2
    exit 68
fi
BASE=$(git rev-parse --verify --quiet 'FETCH_HEAD^{commit}') || BASE=""
if ! [[ $BASE =~ $RE_SHA ]]; then
    echo "$PROG: fetched $REMOTE's $DEFAULT, but FETCH_HEAD read back as [$BASE]; nothing changed" >&2
    exit 68
fi

OLD=$(git rev-parse --verify --quiet HEAD) || OLD=""
[[ $OLD =~ $RE_SHA ]] || { echo "$PROG: HEAD read back as [$OLD]; nothing changed" >&2; exit 69; }

AHEAD=$(git rev-list --count "$BASE..$OLD") || {
    echo "$PROG: could not count $BRANCH's commits beyond $REMOTE's $DEFAULT; nothing changed" >&2
    exit 69
}
if [ "$AHEAD" -gt 0 ]; then
    echo "$PROG: $BRANCH already has $AHEAD commit(s) $REMOTE's $DEFAULT lacks; no start commit needed" >&2
    printf 'unchanged %s\n' "$OLD"
    exit 0
fi

SUBJECT="chore: start the $SLUG implementation"
BODY="Nothing on this branch differs from the default branch yet, and a pull request needs at least one commit of its own, so the branch starts with this empty one."
TREE=$(git rev-parse --verify --quiet "$OLD^{tree}") || TREE=""
NEW=""
[[ $TREE =~ $RE_SHA ]] && NEW=$(printf '%s\n\n%s\n' "$SUBJECT" "$BODY" | git commit-tree "$TREE" -p "$OLD")
if ! [[ $NEW =~ $RE_SHA ]]; then
    echo "$PROG: could not write the start commit; nothing changed" >&2
    exit 69
fi
# The old value makes the move conditional: if anything moved the branch since
# it was read, update-ref refuses and the branch stays where it is.
if ! git update-ref -m "$PROG: $SUBJECT" "refs/heads/$BRANCH" "$NEW" "$OLD" </dev/null; then
    echo "$PROG: could not move $BRANCH to the start commit $NEW; nothing changed" >&2
    exit 69
fi

echo "$PROG: $BRANCH had no commit beyond $REMOTE's $DEFAULT; added the empty start commit $NEW" >&2
printf 'created %s\n' "$NEW"
exit 0
