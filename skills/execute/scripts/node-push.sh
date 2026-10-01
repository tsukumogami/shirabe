#!/usr/bin/env bash
# node-push.sh — for /execute: push a coordinated node (or the coordination
# branch) and record the pushed commit on the coordination PR's index; or,
# in the order mode, only render the PLAN's merge order into that PR's body.
#
# Three modes.
#
#   node-push.sh node --slug <slug> --node <node-id> --repo <owner/repo>
#                     --issues <ids> --home-repo <owner/repo>
#                     --coord-branch <branch> --plan <path> [--remote <name>]
#                     [--run-id <id>]
#
#     Run inside the node's worktree (node-cut.sh), on impl/<slug>-<node-id>,
#     after the node's work items committed there. It sweeps wip/, pushes,
#     finds the node's owned PR or opens a draft one, writes the node's index
#     line with `head=<sha>`, and renders the merge order into the body's
#     `## Merge Order` section. --plan is the PLAN in the coordination
#     checkout (the recorded plan_abs), since the node branch doesn't carry it.
#
#   node-push.sh coordination --slug <slug> --home-repo <owner/repo>
#                             --coord-branch <branch> [--remote <name>]
#                             [--run-id <id>]
#
#     Run in the coordination checkout after the finalization cascade. It
#     sweeps wip/, pushes the coordination branch, and writes the coordination
#     PR's own index line (`- coordination | ... | head=<sha>`), the expected
#     head its merge is checked against. The cascade has deleted the PLAN by
#     then, so this mode leaves the merge-order block as it was.
#
#   node-push.sh order --slug <slug> --home-repo <owner/repo>
#                      --coord-branch <branch> --plan <path> [--run-id <id>]
#
#     Run in the coordination checkout just before the finalization cascade
#     deletes the PLAN. It pushes nothing and records no index line: it only
#     renders the PLAN's merge order into the coordination PR's body, so the
#     block matches the PLAN the effort finished with even when the PLAN
#     changed after the last node push.
#
# --run-id is this run's identity (`run-id.sh get <session>`, ^[0-9a-f]{32}$).
# Both lookups carry it, so a PR another run opened is never adopted, and a
# node PR this script opens carries the run's marker line (`run-id.sh stamp`).
# Omitted only on a hand run: the lookups then match by login and branch
# alone, and a new node PR carries no marker.
#
# The expected head of every coordinated PR is recorded here and nowhere else:
# no other script, template, or directive writes a `head=` field. It is the
# commit this script just pushed, never a value read off the live PR.
#
# The merge-order block. The node and order modes replace the body's whole
# `## Merge Order` section with one fenced ```merge-order block listing every
# node of the PLAN, PR and gate alike, one per line, in the order
# plan-to-tasks.sh emits them (every node after its predecessors):
#
#   <node-id> | pr | after: <node-id>, <node-id>
#   <node-id> | gate | after: -
#
# Each line carries a node id (the same ids the PR index already carries), its
# kind, and its predecessors' ids: no repository field, and no merge state,
# which is live and belongs to the merge gate. The same PLAN renders the same
# block, so a second render leaves it as it was, and a PLAN whose waits_on
# changed replaces it whole (a run marker line that sat in the old section is
# kept, moved to the end of the body). The block is the durable, human-readable order
# that outlives the PLAN. Nothing schedules or gates from it:
# coordinated-next.sh reads the PLAN, and `shirabe validate --merge-gate`
# recomputes merge state from live gh. The node id must stay the first field:
# testdata/merge-order-gated.txt pins the rendered section, and the
# validator's own tests read that file with the real parser.
#
# In order:
#   1. check every value against its closed pattern (slug ^[a-z0-9-]+$, node
#      id ^[a-z][a-z0-9-]*$, repositories owner/repo, issues a comma-joined
#      list of numbers); in the node and order modes, read the PLAN's nodes
#      through plan-to-tasks.sh and render the merge-order block (node mode
#      also refuses a PLAN that has no node named --node), all before
#      anything is pushed or edited;
#   (the order mode skips steps 2, 3, 5, 6, the node-branch check in 4, and
#   the index half of 7)
#   2. refuse a detached HEAD, a checked-out branch other than the expected
#      one, and the remote's default branch; in node mode, for a node whose
#      repository is not the coordination PR's, refuse a worktree that
#      shares the coordination checkout's git directory or origin URL;
#   3. sweep wip/: when `git ls-files wip/` lists anything, `git rm -r` it and
#      commit, so the pushed head carries no wip/ file (a node PR is
#      finalized on its own; the single-pr path has no such sweep);
#   4. before any push, find the coordination PR (owned-pr.sh on home repo
#      and coordination branch, carrying the `This is a **coordination PR**`
#      marker) and, in node mode, check the node branch's PR: another run's
#      PR there, or several, stops with 73 and nothing pushed. Before those
#      reads, in node mode, read the home repository's and the node
#      repository's visibility live (coord_node_visibility): a private node
#      under a public coordination PR is refused with 77, and a public node
#      under a private one has its commits since the default branch (added
#      lines and messages) scanned for the public-content markers, a hit or a
#      failed scan refused with 78; nothing pushed either way;
#   5. push with exactly `git push <remote> HEAD:refs/heads/<branch>`, never a
#      force option;
#   6. node mode: find the node's owned PR on impl/<slug>-<node-id>. One
#      survivor is adopted. Zero survivors open a draft PR against the default
#      branch, titled `feat(<slug>): <node-id>`, with a body from a fixed
#      template of the node id, the work-item ids, and the coordination PR's
#      link (and the run's marker line), passed with --body-file; the link is
#      left out when the node's repository is public and the coordination
#      PR's is private, so a public PR never points into a private one -- unless
#      the index already names a PR for this node, which must then be adopted,
#      and zero survivors refuse;
#   7. rewrite the body's `## PR Index` line for the node (replacing it, or
#      adding it) and keep every other line, the run marker included; in the
#      node and order modes replace the `## Merge Order` section with the
#      rendered block (adding the section when absent); run
#      `shirabe validate --coordination-body` on the new body, and only when
#      that passes, post it with `gh pr edit --body-file`. A failing
#      validation leaves the posted body untouched.
#
# Output: `pr=<url>` and `head=<sha>` on stdout (the order mode prints only
# `pr=<coordination PR url>`). Diagnostics on stderr.
#
# Exit codes:
#   0   pushed and recorded (order mode: rendered and posted)
#   64  usage error
#   65  HEAD is detached
#   66  the checked-out branch is not the expected one, or its name is refused
#   67  the branch is the remote's default branch
#   68  the push failed
#   69  the wip/ sweep failed, or the pushed head still carries wip/
#   72  a GitHub read failed (the caller's execute:status-read)
#   73  no single owned PR where one must be adopted: the coordination PR, or
#       an indexed node PR; or the node branch's PR is another run's, or one of
#       several (checked before the push, so nothing is pushed then) (the
#       caller's execute:pr-adopt)
#   74  shirabe validate --coordination-body refused the new body; nothing
#       was edited
#   75  gh pr create or gh pr edit failed
#   76  node or order mode: plan-to-tasks.sh could not read the PLAN, the
#       PLAN is not coordinated (a node without NODE_KIND pr or gate), or
#       (node mode) the PLAN has no node named --node; nothing was pushed or
#       edited
#   77  node mode: the node's repository is private and the coordination
#       PR's is public; nothing was pushed or edited (the caller's
#       execute:visibility)
#   78  node mode: a public node under a private coordination PR whose
#       commits carry private-repository markers, or whose commits the check
#       couldn't read; nothing was pushed or edited (execute:visibility)
#   79  node mode: the node names a repository other than the coordination
#       PR's, but this worktree shares the coordination checkout's git
#       directory (a node cut without node-cut.sh --repo-dir) or its push
#       URL names the same repository as the checkout's origin fetch or push
#       URL (a clone of the coordination PR's repository; network URLs
#       compared by host and path, local paths as written), or either git
#       directory could not be read; nothing was pushed or edited
#       (execute:dispatch)
#
# A failed visibility read is a 72, like any other GitHub read.
#
# Requires: bash 3.2+, git, gh, jq, shirabe.
set -uo pipefail

PROG=node-push

COORD_SELF_DIR=$(CDPATH='' cd "$(dirname "${BASH_SOURCE[0]}")" && pwd) || exit 64
# shellcheck source=coord-common.sh
. "$COORD_SELF_DIR/coord-common.sh"

usage_error() {
    echo "$PROG: $*" >&2
    echo "usage: node-push.sh node --slug <slug> --node <node-id> --repo <owner/repo> --issues <ids> --home-repo <owner/repo> --coord-branch <branch> --plan <path> [--remote <name>] [--run-id <id>]" >&2
    echo "       node-push.sh coordination --slug <slug> --home-repo <owner/repo> --coord-branch <branch> [--remote <name>] [--run-id <id>]" >&2
    echo "       node-push.sh order --slug <slug> --home-repo <owner/repo> --coord-branch <branch> --plan <path> [--run-id <id>]" >&2
    exit 64
}

[ $# -ge 1 ] || usage_error "a mode is required"
MODE="$1"; shift
case "$MODE" in node|coordination|order) ;; *) usage_error "mode must be node, coordination, or order, got [$MODE]" ;; esac

SLUG=""; NODE=""; REPO=""; ISSUES=""; HOME_REPO=""; CB=""; PLAN=""; REMOTE="origin"
SEEN=" "
while [ $# -gt 0 ]; do
    case "$1" in
        --slug|--node|--repo|--issues|--home-repo|--coord-branch|--plan|--remote|--run-id)
            [ $# -ge 2 ] || usage_error "$1 needs a value"
            case "$SEEN" in *" $1 "*) usage_error "$1 given more than once" ;; esac
            SEEN="$SEEN$1 "
            case "$1" in
                --run-id) COORD_RUN_ID="$2" ;;
                --slug) SLUG="$2" ;;
                --node) NODE="$2" ;;
                --repo) REPO="$2" ;;
                --issues) ISSUES="$2" ;;
                --home-repo) HOME_REPO="$2" ;;
                --coord-branch) CB="$2" ;;
                --plan) PLAN="$2" ;;
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
case "$SEEN" in
    *" --run-id "*) [[ $COORD_RUN_ID =~ $RE_COORD_RUN_ID ]] || usage_error "--run-id [$COORD_RUN_ID] is not a run id" ;;
esac
if [ "$MODE" = node ]; then
    [[ $NODE =~ $RE_COORD_NODE ]] || usage_error "--node [$NODE] is outside ^[a-z][a-z0-9-]*\$"
    [ "$NODE" != coordination ] || usage_error "--node coordination is the coordination PR's own record; use the coordination mode"
    coord_valid_repo "$REPO" || usage_error "--repo [$REPO] is not a single owner/repo"
    [[ $ISSUES =~ ^[1-9][0-9]*(,[1-9][0-9]*)*$ ]] || usage_error "--issues [$ISSUES] is not a comma-joined list of work-item numbers"
    case "$SEEN" in *" --plan "*) ;; *) usage_error "--plan is required in the node mode" ;; esac
    [ -f "$PLAN" ] || usage_error "--plan [$PLAN] is not a file"
    BRANCH="impl/$SLUG-$NODE"
    ENTRY_NODE="$NODE"
    ENTRY_REPO="$REPO"
elif [ "$MODE" = order ]; then
    for f in --node --repo --issues --remote; do
        case "$SEEN" in *" $f "*) usage_error "$f does not belong to the order mode" ;; esac
    done
    case "$SEEN" in *" --plan "*) ;; *) usage_error "--plan is required in the order mode" ;; esac
    [ -f "$PLAN" ] || usage_error "--plan [$PLAN] is not a file"
else
    for f in --node --repo --issues --plan; do
        case "$SEEN" in *" $f "*) usage_error "$f belongs to the node mode" ;; esac
    done
    BRANCH="$CB"
    ENTRY_NODE="coordination"
    ENTRY_REPO="$HOME_REPO"
fi
command -v jq >/dev/null || { echo "$PROG: jq is not on PATH" >&2; exit 72; }

# 1. The merge order, rendered from the PLAN before anything is pushed.
ORDER_BLOCK=""
if [ "$MODE" != coordination ]; then
    # jq given no input runs nothing and exits 0, so an empty result is
    # checked as well as each command's status. Only a coordinated PLAN's
    # nodes carry NODE_KIND (pr or gate); any other PLAN's tasks don't, and
    # are refused rather than rendered as PR nodes.
    TASKS=$("$BASH" "$COORD_PLAN_TO_TASKS" "$PLAN" </dev/null) \
    && ORDER_LINES=$(printf '%s' "$TASKS" | jq -r --arg re "$RE_COORD_NODE" '
        if type == "array" and length > 0
            and all(.[]; (.name | type) == "string" and (.name | test($re))
                         and (.vars.NODE_KIND == "pr" or .vars.NODE_KIND == "gate"))
        then .[] | "\(.name) | \(.vars.NODE_KIND) | after: \(if (.waits_on | length) == 0 then "-" else (.waits_on | join(", ")) end)"
        else error("no usable node list") end' 2>/dev/null) \
    && [ -n "$ORDER_LINES" ] || {
        echo "$PROG: plan-to-tasks.sh could not read [$PLAN] into a coordinated merge order; nothing was pushed or edited" >&2
        exit 76
    }
    if [ "$MODE" = node ] && ! printf '%s\n' "$ORDER_LINES" | grep -q "^$NODE |"; then
        echo "$PROG: the PLAN [$PLAN] has no node $NODE; nothing was pushed" >&2
        exit 76
    fi
    ORDER_BLOCK=$(
        printf '```merge-order\n'
        printf "# Rendered by /execute from the PLAN's waits_on graph; not read by the merge gate.\n"
        printf '# One node per line, after its predecessors: <node-id> | pr|gate | after: <node-ids>\n'
        printf '%s\n' "$ORDER_LINES"
        printf '```'
    )
fi

# Steps 2 and 3 prepare a branch to push; the order mode pushes nothing.
if [ "$MODE" != order ]; then
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

    # 2b. A node in a repository other than the coordination PR's is pushed
    # from a clone of that repository (node-cut.sh --repo-dir), never from
    # the coordination checkout the PLAN sits in. A worktree sharing that
    # checkout's git directory, or pushing to the repository its origin
    # names, would put the node branch in the home repository, which the run
    # writes only through the coordination PR's own paths.
    if [ "$MODE" = node ] && [ "$(coord_lower "$REPO")" != "$(coord_lower "$HOME_REPO")" ]; then
        PLAN_DIR=$(dirname -- "$PLAN")
        HOME_GIT=$(coord_git_common_dir "$PLAN_DIR") || HOME_GIT=""
        NODE_GIT=$(coord_git_common_dir .) || NODE_GIT=""
        # The node side is where its push goes (insteadOf, pushInsteadOf and
        # pushurl applied). The home side is both of origin's URLs, insteadOf
        # applied: the fetch URL (the remote.origin.url home_repo was read
        # from) and the push URL, which differ when origin has a pushurl.
        HOME_FETCH=$(cd "$PLAN_DIR" && git remote get-url origin 2>/dev/null) || HOME_FETCH=""
        HOME_URL=$(cd "$PLAN_DIR" && git remote get-url --push origin 2>/dev/null) || HOME_URL=""
        NODE_URL=$(git remote get-url --push "$REMOTE" 2>/dev/null) || NODE_URL=""
        if [ -z "$HOME_GIT" ] || [ -z "$NODE_GIT" ]; then
            echo "$PROG: could not read the git directories of this worktree and of the coordination checkout the PLAN is in; nothing was pushed" >&2
            exit 79
        fi
        HOME_FETCH=$(coord_url_key "$HOME_FETCH")
        HOME_URL=$(coord_url_key "$HOME_URL")
        NODE_URL=$(coord_url_key "$NODE_URL")
        if [ "$HOME_GIT" = "$NODE_GIT" ] \
            || { [ -n "$NODE_URL" ] && { [ "$NODE_URL" = "$HOME_FETCH" ] || [ "$NODE_URL" = "$HOME_URL" ]; }; }; then
            # Names no repository, either of which may be private: only the
            # node id and this worktree's local path and branch.
            echo "$PROG: node $NODE lands in another repository than the coordination PR's, but this worktree pushes to the coordination checkout's; cut it with node-cut.sh --repo-dir <a clone of the node's repository>. Nothing was pushed. Re-cut the node in its own repository's clone and run its work items there; then remove this worktree ($(git rev-parse --show-toplevel 2>/dev/null)) with git worktree remove and its branch $BRANCH with git branch -D, both in the repository this worktree belongs to" >&2
            exit 79
        fi
    fi

    # 3. The wip/ sweep.
    if [ -n "$(git ls-files -- wip/)" ]; then
        git rm -r -q -- wip/ >&2 || { echo "$PROG: git rm of wip/ failed" >&2; exit 69; }
        git commit -q -m "chore($SLUG): remove wip/ artifacts before push" >&2 \
            || { echo "$PROG: committing the wip/ sweep failed" >&2; exit 69; }
    fi
fi

# 4a. The node against its own target, before any other read can name its
# repository in a diagnostic: a public coordination PR never indexes a
# private node, so that pair is refused here, before the push and before the
# index line that would name the repository in a public body. The call sets
# COORD_HOME_VIS and COORD_NODE_VIS, which also decide the scan below and the
# node PR's body. A resumed run can reach this push without passing through
# the dispatch step's own check, so the check is repeated here.
if [ "$MODE" = node ]; then
    coord_node_visibility "$HOME_REPO" "$REPO" "$NODE"
    case $? in
        0) ;;
        3) exit 77 ;;   # a private node under a public coordination PR
        *) exit 72 ;;   # a visibility read failed
    esac
    # A public node driven from a private home: its commits were written from
    # a private PLAN, so the public-content markers /scope's publish step
    # scans for (a `private/` path component, a `Repo Visibility: Private`
    # declaration) are checked on what this push would publish, the added
    # lines and the commit messages since the default branch. A hit, or a
    # scan that can't run, stops the push.
    if [ "$COORD_HOME_VIS" = private ] && [ "$COORD_NODE_VIS" = public ]; then
        SCAN_DIR=$(mktemp -d "${TMPDIR:-/tmp}/node-push-scan.XXXXXX") || exit 78
        BASE=""
        [ -n "$DEFAULT" ] && BASE=$(git merge-base HEAD "refs/remotes/$REMOTE/$DEFAULT")
        if [ -z "$BASE" ] \
            || ! git log --format=%B "$BASE..HEAD" >"$SCAN_DIR/text" \
            || ! git diff "$BASE" HEAD >"$SCAN_DIR/diff"; then
            rm -rf "$SCAN_DIR"
            echo "$PROG: the public-content check could not read node $NODE's commits since the default branch; nothing was pushed" >&2
            exit 78
        fi
        grep '^+' "$SCAN_DIR/diff" | grep -v '^+++ ' >>"$SCAN_DIR/text"
        SCAN=0
        grep -Eq '(^|[^A-Za-z0-9_.-])private/[A-Za-z0-9._-]|Repo Visibility:[[:space:]]*Private' "$SCAN_DIR/text" || SCAN=$?
        rm -rf "$SCAN_DIR"
        case "$SCAN" in
            0) echo "$PROG: node $NODE lands in a public repository from a private PLAN, and its commits carry private-repository content (a private/ path or a Repo Visibility: Private line); remove it and push again. Nothing was pushed." >&2
               exit 78 ;;
            1) ;;
            *) echo "$PROG: the public-content check could not scan node $NODE's commits (grep exit $SCAN); nothing was pushed" >&2
               exit 78 ;;
        esac
    fi
fi

# 4b. Ownership, before anything is pushed: the coordination PR, and in node
# mode whose PR (if any) is already on the node branch. A branch whose PR
# another run opened is never pushed to, so a run can't move another run's
# PR head.
coord_find_pr "$HOME_REPO" "$CB" open
case $? in
    0) ;;
    2) exit 72 ;;
    *) exit 73 ;;
esac
BODY=$(printf '%s' "$C_JSON" | jq -r '.body // ""')
WORK=$(mktemp -d "${TMPDIR:-/tmp}/node-push.XXXXXX") || exit 72
trap 'rm -rf "$WORK"' EXIT
if [ "$MODE" = node ]; then
    coord_owned "$REPO" "$BRANCH" open >/dev/null
    case $? in
        0) ;;
        2) exit 72 ;;
        *) echo "$PROG: no single PR this run owns on $REPO $BRANCH; nothing pushed" >&2; exit 73 ;;
    esac
fi

# 5. The push: the explicit refspec, never a force option. The order mode
# pushes nothing.
if [ "$MODE" != order ]; then
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
fi

# post_body -- finish $WORK/body.md and post it: when a merge order was
# rendered, replace the whole `## Merge Order` section with it (up to the next
# heading; a body without the section gains it), then validate the body and,
# only when that passes, edit the coordination PR.
post_body() {
    if [ -n "$ORDER_BLOCK" ]; then
        printf '%s\n' "$ORDER_BLOCK" > "$WORK/order.md"
        awk -v blockfile="$WORK/order.md" '
            function emit(  l) { while ((getline l < blockfile) > 0) print l; close(blockfile) }
            /^## / {
                if (insec) print ""
                insec = ($0 ~ /^## Merge Order[[:space:]]*$/)
                print
                if (insec) { sawsec = 1; print ""; emit() }
                next
            }
            # A run marker line inside the replaced section is kept (and
            # re-emitted at the end of the body): the section is rewritten
            # whole, and the marker is what tells a later lookup which run
            # opened the PR.
            insec && /^[[:space:]]*<!--[[:space:]]*shirabe-run:/ { kept[++nk] = $0; next }
            insec { next }
            { print }
            END {
                if (!sawsec) { print ""; print "## Merge Order"; print ""; emit() }
                if (nk) { print ""; for (i = 1; i <= nk; i++) print kept[i] }
            }
        ' "$WORK/body.md" > "$WORK/body-order.md" \
            && mv "$WORK/body-order.md" "$WORK/body.md" \
            || { echo "$PROG: rendering the merge-order section failed" >&2; exit 64; }
    fi
    SHIRABE="${SHIRABE_BIN:-shirabe}"
    if ! "$SHIRABE" validate --coordination-body "$WORK/body.md" >&2; then
        echo "$PROG: shirabe validate --coordination-body refused the new body; the coordination PR was not edited" >&2
        exit 74
    fi
    if ! gh pr edit "$C_NUM" --repo "$HOME_REPO" --body-file "$WORK/body.md" </dev/null >&2; then
        echo "$PROG: gh pr edit failed" >&2
        exit 75
    fi
}

# The order mode records no index line: it skips step 6 and the index half of
# step 7, and post_body does the rest.
if [ "$MODE" = order ]; then
    printf '%s\n' "$BODY" > "$WORK/body.md"
    post_body
    printf 'pr=%s\n' "$C_URL"
    exit 0
fi

ENTRIES=$(coord_index_entries "$BODY")
OLD_LINE=$(coord_find_entry "$ENTRIES" "$ENTRY_NODE")
case $? in
    0|1) ;;
    *) echo "$PROG: the index lists $ENTRY_NODE more than once" >&2; exit 73 ;;
esac

# 6. The PR this line indexes.
if [ "$MODE" = node ]; then
    OUT=$(coord_owned "$REPO" "$BRANCH" open)
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
        # A public node PR links its coordination PR only when that PR is
        # public too: a link from a public PR into a private repository is a
        # public-to-private reference.
        {
            printf 'Coordinated node `%s` of `%s`.\n\n' "$NODE" "$SLUG"
            printf 'Work items: %s\n' "$ISSUES"
            # Omitted exactly when the home is private and the node public
            # (step 4a has already refused a public home over a private node).
            if ! { [ "$COORD_HOME_VIS" = private ] && [ "$COORD_NODE_VIS" = public ]; }; then
                printf '\nCoordination PR: %s\n' "$C_URL"
            fi
        } > "$WORK/node-body.md"
        if [ -n "$COORD_RUN_ID" ]; then
            "$BASH" "$COORD_SELF_DIR/run-id.sh" stamp "$COORD_RUN_ID" "$WORK/node-body.md" </dev/null || {
                echo "$PROG: could not stamp the node PR's body; nothing created" >&2
                exit 75
            }
        fi
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

post_body

printf 'pr=%s\nhead=%s\n' "$PR_URL" "$SHA"
exit 0
