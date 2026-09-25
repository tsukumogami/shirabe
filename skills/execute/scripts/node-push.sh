#!/usr/bin/env bash
# node-push.sh — for /execute: push a coordinated node (or the coordination
# branch) and record the pushed commit on the coordination PR's index.
#
# Two modes.
#
#   node-push.sh node --slug <slug> --node <node-id> --repo <owner/repo>
#                     --issues <ids> --home-repo <owner/repo>
#                     --coord-branch <branch> [--remote <name>]
#
#     Run inside the node's worktree (node-cut.sh), on impl/<slug>-<node-id>,
#     after the node's work items committed there. It sweeps wip/, pushes,
#     finds the node's owned PR or opens a draft one, and writes the node's
#     index line with `head=<sha>`.
#
#   node-push.sh coordination --slug <slug> --home-repo <owner/repo>
#                             --coord-branch <branch> [--remote <name>]
#
#     Run in the coordination checkout after the finalization cascade. It
#     sweeps wip/, pushes the coordination branch, and writes the coordination
#     PR's own index line (`- coordination | ... | head=<sha>`), the expected
#     head its merge is checked against.
#
# The expected head of every coordinated PR is recorded here and nowhere else:
# no other script, template, or directive writes a `head=` field. It is the
# commit this script just pushed, never a value read off the live PR.
#
# In order:
#   1. check every value against its closed pattern (slug ^[a-z0-9-]+$, node
#      id ^[a-z][a-z0-9-]*$, repositories owner/repo, issues a comma-joined
#      list of numbers);
#   2. refuse a detached HEAD, a checked-out branch other than the expected
#      one, and the remote's default branch;
#   3. sweep wip/: when `git ls-files wip/` lists anything, `git rm -r` it and
#      commit, so the pushed head carries no wip/ file (the sweep single-pr
#      finalization runs, since a node PR is finalized on its own);
#   4. push with exactly `git push <remote> HEAD:refs/heads/<branch>`, never a
#      force option;
#   5. find the coordination PR (owned-pr.sh on home repo and coordination
#      branch, carrying the `This is a **coordination PR**` marker);
#   6. node mode: find the node's owned PR on impl/<slug>-<node-id>. One
#      survivor is adopted. Zero survivors open a draft PR against the default
#      branch, titled `feat(<slug>): <node-id>`, with a body from a fixed
#      template of the node id, the work-item ids, and the coordination PR's
#      link, passed with --body-file -- unless the index already names a PR
#      for this node, which must then be adopted, and zero survivors refuse;
#   7. rewrite the body's `## PR Index` line for the node (replacing it, or
#      adding it), run `shirabe validate --coordination-body` on the new body,
#      and only when that passes, post it with `gh pr edit --body-file`. A
#      failing validation leaves the posted body untouched.
#
# Output: `pr=<url>` and `head=<sha>` on stdout. Diagnostics on stderr.
#
# Exit codes:
#   0   pushed and recorded
#   64  usage error
#   65  HEAD is detached
#   66  the checked-out branch is not the expected one, or its name is refused
#   67  the branch is the remote's default branch
#   68  the push failed
#   69  the wip/ sweep failed, or the pushed head still carries wip/
#   72  a GitHub read failed (the caller's execute:status-read)
#   73  no single owned PR where one must be adopted: the coordination PR, or
#       an indexed node PR (the caller's execute:pr-adopt)
#   74  shirabe validate --coordination-body refused the new body; nothing
#       was edited
#   75  gh pr create or gh pr edit failed
#
# Requires: bash 3.2+, git, gh, jq, shirabe.
set -uo pipefail

PROG=node-push

COORD_SELF_DIR=$(CDPATH='' cd "$(dirname "${BASH_SOURCE[0]}")" && pwd) || exit 64
# shellcheck source=coord-common.sh
. "$COORD_SELF_DIR/coord-common.sh"

usage_error() {
    echo "$PROG: $*" >&2
    echo "usage: node-push.sh node --slug <slug> --node <node-id> --repo <owner/repo> --issues <ids> --home-repo <owner/repo> --coord-branch <branch> [--remote <name>]" >&2
    echo "       node-push.sh coordination --slug <slug> --home-repo <owner/repo> --coord-branch <branch> [--remote <name>]" >&2
    exit 64
}

[ $# -ge 1 ] || usage_error "a mode is required"
MODE="$1"; shift
case "$MODE" in node|coordination) ;; *) usage_error "mode must be node or coordination, got [$MODE]" ;; esac

SLUG=""; NODE=""; REPO=""; ISSUES=""; HOME_REPO=""; CB=""; REMOTE="origin"
SEEN=" "
while [ $# -gt 0 ]; do
    case "$1" in
        --slug|--node|--repo|--issues|--home-repo|--coord-branch|--remote)
            [ $# -ge 2 ] || usage_error "$1 needs a value"
            case "$SEEN" in *" $1 "*) usage_error "$1 given more than once" ;; esac
            SEEN="$SEEN$1 "
            case "$1" in
                --slug) SLUG="$2" ;;
                --node) NODE="$2" ;;
                --repo) REPO="$2" ;;
                --issues) ISSUES="$2" ;;
                --home-repo) HOME_REPO="$2" ;;
                --coord-branch) CB="$2" ;;
                --remote) REMOTE="$2" ;;
            esac
            shift 2
            ;;
        *) usage_error "unexpected argument [$1]" ;;
    esac
done

[[ $SLUG =~ $RE_COORD_SLUG ]] || usage_error "--slug [$SLUG] is outside ^[a-z0-9-]+\$"
coord_valid_repo "$HOME_REPO" || usage_error "--home-repo [$HOME_REPO] is not a single owner/repo"
coord_valid_branch "$CB" || usage_error "--coord-branch [$CB] is not an allowed branch name"
[[ $REMOTE =~ ^[A-Za-z0-9._][A-Za-z0-9._-]*$ ]] || usage_error "--remote [$REMOTE] is not a remote name"
if [ "$MODE" = node ]; then
    [[ $NODE =~ $RE_COORD_NODE ]] || usage_error "--node [$NODE] is outside ^[a-z][a-z0-9-]*\$"
    [ "$NODE" != coordination ] || usage_error "--node coordination is the coordination PR's own record; use the coordination mode"
    coord_valid_repo "$REPO" || usage_error "--repo [$REPO] is not a single owner/repo"
    [[ $ISSUES =~ ^[1-9][0-9]*(,[1-9][0-9]*)*$ ]] || usage_error "--issues [$ISSUES] is not a comma-joined list of work-item numbers"
    BRANCH="impl/$SLUG-$NODE"
    ENTRY_NODE="$NODE"
    ENTRY_REPO="$REPO"
else
    for f in --node --repo --issues; do
        case "$SEEN" in *" $f "*) usage_error "$f belongs to the node mode" ;; esac
    done
    BRANCH="$CB"
    ENTRY_NODE="coordination"
    ENTRY_REPO="$HOME_REPO"
fi
command -v jq >/dev/null || { echo "$PROG: jq is not on PATH" >&2; exit 72; }

# 2. The branch.
CUR=$(git symbolic-ref --quiet --short HEAD) || {
    echo "$PROG: HEAD is detached, so there is no branch to push" >&2
    exit 65
}
if [ "$CUR" != "$BRANCH" ]; then
    echo "$PROG: the checked-out branch is [$CUR], not [$BRANCH]" >&2
    exit 66
fi
coord_valid_branch "$BRANCH" || { echo "$PROG: refusing branch name [$BRANCH]" >&2; exit 66; }
DEFAULT=$(git ls-remote --symref "$REMOTE" HEAD </dev/null \
    | sed -n 's#^ref: refs/heads/\([^[:space:]]*\)[[:space:]]*HEAD$#\1#p' | head -1)
if [ -z "$DEFAULT" ]; then
    DEFAULT=$(git symbolic-ref --quiet --short "refs/remotes/$REMOTE/HEAD" || true)
    DEFAULT=${DEFAULT#"$REMOTE"/}
fi
if [ -n "$DEFAULT" ]; then
    [ "$BRANCH" = "$DEFAULT" ] && { echo "$PROG: refusing to push [$BRANCH]: it is the default branch of $REMOTE" >&2; exit 67; }
else
    case "$BRANCH" in main|master) echo "$PROG: refusing to push [$BRANCH]: a default branch name" >&2; exit 67 ;; esac
fi

# 3. The wip/ sweep.
if [ -n "$(git ls-files -- wip/)" ]; then
    git rm -r -q -- wip/ >&2 || { echo "$PROG: git rm of wip/ failed" >&2; exit 69; }
    git commit -q -m "chore($SLUG): remove wip/ artifacts before push" >&2 \
        || { echo "$PROG: committing the wip/ sweep failed" >&2; exit 69; }
fi

# 4. The push: the explicit refspec, never a force option.
if ! git push "$REMOTE" "HEAD:refs/heads/$BRANCH" </dev/null >&2; then
    echo "$PROG: the push failed; nothing was recorded" >&2
    exit 68
fi
SHA=$(git rev-parse HEAD)
[[ $SHA =~ $RE_COORD_SHA ]] || { echo "$PROG: HEAD read back as [$SHA]" >&2; exit 69; }
if [ -n "$(git ls-tree -r --name-only "$SHA" -- wip/)" ]; then
    echo "$PROG: the pushed head $SHA still carries wip/ files" >&2
    exit 69
fi

# 5. The coordination PR.
coord_find_pr "$HOME_REPO" "$CB" open
case $? in
    0) ;;
    2) exit 72 ;;
    *) exit 73 ;;
esac
BODY=$(printf '%s' "$C_JSON" | jq -r '.body // ""')
ENTRIES=$(coord_index_entries "$BODY")
OLD_LINE=$(coord_find_entry "$ENTRIES" "$ENTRY_NODE")
case $? in
    0|1) ;;
    *) echo "$PROG: the index lists $ENTRY_NODE more than once" >&2; exit 73 ;;
esac

WORK=$(mktemp -d "${TMPDIR:-/tmp}/node-push.XXXXXX") || exit 72
trap 'rm -rf "$WORK"' EXIT

# 6. The PR this line indexes.
if [ "$MODE" = node ]; then
    OUT=$("$BASH" "$COORD_SELF_DIR/owned-pr.sh" --repo "$REPO" --head "$BRANCH" --state open </dev/null)
    case $? in
        0) ;;
        2) exit 72 ;;
        *) exit 73 ;;
    esac
    if [ -z "$OUT" ]; then
        if [ -n "$OLD_LINE" ]; then
            echo "$PROG: the index names a PR for $NODE, and no owned open PR is on $REPO $BRANCH to adopt" >&2
            exit 73
        fi
        REPO_JSON=""
        coord_gh_read REPO_JSON api "repos/$REPO" || exit 72
        BASE=$(printf '%s' "$REPO_JSON" | jq -r 'if type == "object" then (.default_branch // "") else "" end')
        coord_valid_branch "$BASE" || { echo "$PROG: the default branch of $REPO is unusable [$BASE]" >&2; exit 72; }
        {
            printf 'Coordinated node `%s` of `%s`.\n\n' "$NODE" "$SLUG"
            printf 'Work items: %s\n\n' "$ISSUES"
            printf 'Coordination PR: %s\n' "$C_URL"
        } > "$WORK/node-body.md"
        OUT=$(gh pr create --repo "$REPO" --draft --base "$BASE" --head "$BRANCH" \
            --title "feat($SLUG): $NODE" --body-file "$WORK/node-body.md" </dev/null) || {
            echo "$PROG: gh pr create failed" >&2
            exit 75
        }
        OUT=$(printf '%s\n' "$OUT" | grep -E "$RE_COORD_URL" | tail -1)
    elif [ -n "$OLD_LINE" ] && coord_parse_entry "$OLD_LINE" && [ "$E_NUM" != "${OUT##*/}" ]; then
        echo "$PROG: the index names #$E_NUM for $NODE, not the owned PR $OUT" >&2
        exit 73
    fi
    [[ $OUT =~ $RE_COORD_URL ]] || { echo "$PROG: no usable PR URL for $NODE [$OUT]" >&2; exit 72; }
    URL_REPO=$(printf '%s' "$OUT" | sed -E 's#^https://[^/]+/([^/]+/[^/]+)/pull/[0-9]+$#\1#')
    [ "$(coord_lower "$URL_REPO")" = "$(coord_lower "$REPO")" ] || {
        echo "$PROG: the PR URL names $URL_REPO, not $REPO" >&2
        exit 72
    }
    PR_URL="$OUT"
else
    PR_URL="$C_URL"
fi
PR_NUM="${PR_URL##*/}"

# 7. The new index line, validated before it is posted.
NEW_LINE="- $ENTRY_NODE | $ENTRY_REPO:docs/plans/PLAN-$SLUG.md#$PR_NUM | open | head=$SHA"
coord_parse_entry "$NEW_LINE" || { echo "$PROG: built an index line outside the grammar" >&2; exit 64; }
printf '%s\n' "$BODY" | awk -v node="$ENTRY_NODE" -v line="$NEW_LINE" '
    function flush() { if (insec && !done) { print line; done = 1 } }
    /^## / {
        if (insec) flush()
        insec = ($0 ~ /^## PR Index[[:space:]]*$/)
        if (insec) sawsec = 1
        print
        next
    }
    insec && index($0, "- " node " |") == 1 { if (!done) { print line; done = 1 }; next }
    { print }
    END {
        if (insec) flush()
        if (!sawsec) { print ""; print "## PR Index"; print ""; print line }
    }
' > "$WORK/body.md"

SHIRABE="${SHIRABE_BIN:-shirabe}"
if ! "$SHIRABE" validate --coordination-body "$WORK/body.md" >&2; then
    echo "$PROG: shirabe validate --coordination-body refused the new body; the coordination PR was not edited" >&2
    exit 74
fi
if ! gh pr edit "$C_NUM" --repo "$HOME_REPO" --body-file "$WORK/body.md" </dev/null >&2; then
    echo "$PROG: gh pr edit failed" >&2
    exit 75
fi

printf 'pr=%s\nhead=%s\n' "$PR_URL" "$SHA"
exit 0
