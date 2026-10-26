#!/usr/bin/env bash
# node-push.sh — for /execute: push a coordinated node (or the coordination
# branch), record the pushed commit in the run record, and bring the
# coordination PR's body up to date with it; or, in the order mode, only
# bring the body up to date.
#
# Three modes.
#
#   node-push.sh node --session <S> --slug <slug> --node <node-id>
#                     --repo <owner/repo> --issues <ids>
#                     --home-repo <owner/repo> --coord-branch <branch>
#                     --plan <path> [--remote <name>] [--run-id <id>]
#                     [--verification <local|hosted-ci|""> [--reason <text>]]
#
#     Run inside the node's worktree (node-cut.sh), on impl/<slug>-<node-id>,
#     after the node's work items committed there. It pushes, finds the
#     node's owned PR or opens a draft one, records the node's PR and pushed
#     head in the run record (`run/node/<node>` through `run-record.sh push`),
#     and renders the coordination PR's body from the record
#     (coord-render.sh). --plan is the PLAN in the coordination checkout (the
#     recorded plan_abs), since the node branch doesn't carry it: the node
#     must be one of its nodes, and each work item's goal comes from it.
#     --verification and --reason are the run's VERIFICATION and
#     VERIFICATION_DEFERRAL_REASON: see "The verification deferral" below.
#
#   node-push.sh coordination --session <S> --slug <slug>
#                             --home-repo <owner/repo> --coord-branch <branch>
#                             [--remote <name>] [--run-id <id>]
#
#     Run in the coordination checkout after the finalization cascade. It
#     pushes the coordination branch, records the cascade's pushed head in
#     the run record (`run/cascade` {verdict: pushed, head} through
#     `run-record.sh cascade`), the expected head its merge is checked
#     against, and renders the body. The coordination PR has no index line of
#     its own: the record holds its head, and the body never indexes it.
#
#   node-push.sh order --session <S> --slug <slug> --home-repo <owner/repo>
#                      --coord-branch <branch> [--run-id <id>]
#
#     Run in the coordination checkout just before the finalization cascade.
#     It pushes nothing and records nothing: it only renders the body, so the
#     index and the merge order are current when the cascade starts. The
#     merge-order block comes from the node list run/setup sealed, not from
#     the PLAN, so it takes no --plan and survives the PLAN's deletion.
#
# --session is the run's koto session, ^[A-Za-z0-9][A-Za-z0-9._-]*$: the
# coordination PR is the one its run record names (run/setup's
# coordination_pr), read by number with no lookup, and the node and
# coordination modes write the run record there.
#
# --run-id is this run's identity (`run-id.sh get <session>`, ^[0-9a-f]{32}$).
# The node branch's lookups carry it, so a PR another run recorded last in
# its index is never adopted; the node PR this script opens or adopts is
# indexed as this run's (step 5c). Omitted only on a hand run: the lookups
# then match by login and branch alone. Nothing of the run goes into a node
# PR's text but, under the run's recorded switch include, the one Part 2
# line `scripts/pr-workflow-content.sh --reference` prints.
#
# The expected head of every coordinated PR is recorded here and nowhere else:
# no other script, template, or directive writes a node's or the cascade's
# pushed head in the run record. It is the commit this script just pushed,
# never a value read off the live PR, and it is recorded only after the push
# succeeded: a rejected push records nothing. The run record is written before
# the body is rendered, so a body that can't be posted still leaves the head
# recorded, and the body's `head=` fields are only ever the codec's rendering
# of the record (scripts/lib/coordination-body.sh).
#
# The body. coord-render.sh renders the whole body from the run record and
# posts it only on a difference: the live Part 1 kept byte for byte (or a
# composed sentence when the body has none), the run lines, one PR Index line
# per recorded node and follow-up, and the `## Merge Order` block from
# run/setup's node list, every node, PR and gate alike, in the order setup
# sealed them (every node after its predecessors):
#
#   <node-id> | pr | after: <node-id>, <node-id>
#   <node-id> | gate | after: -
#
# The node id must stay the first field: testdata/merge-order-gated.txt pins
# the rendered section, and the validator's own tests read that file with the
# real parser. Nothing schedules or gates from the block. A body that can't
# be posted (`body=stale`, `body=full`) changes no exit code here; the next
# transition renders again.
#
# The verification deferral (node mode). A node's work items are /work-on
# children, `work-on-<slug>-<node-id>-<item>` for each --issues item and each
# work item the PLAN lists for the node, and a
# child that deferred verification to hosted CI holds its reason as
# `verification_deferral`. The node's reasons are the run's own (--reason,
# when --verification is hosted-ci) and each of those children's, collected
# by shared-deferral-record.sh --list before anything is pushed. With none,
# nothing below changes. With any, under the run's recorded switch include
# (scripts/pr-workflow-content.sh --session), a new node PR's body carries
# the `## Verification` section /work-on's phase-6-pr.md gives, in its second
# part: that local verification did not run, one `Reason: ` line per reason,
# verbatim, and that hosted CI is the build of record; under omit it carries
# none, and the work items' keys are the record. Under include an owned PR
# already on the node branch is adopted only when its body records every reason
# (shared-deferral-record.sh over it, the check /execute's single-pr gate
# makes): one that doesn't is refused with 80 before the push, so a node PR
# carrying a deferred work item never gets a push it doesn't record. It is
# refused rather than repaired: this script writes a body only when it opens
# the PR, and an adopted body may hold a person's edits, so fixing it is left
# to the caller, as pr_finalization's gate leaves the shared PR's body to the
# run that owns it. The section's three lines are phase-6-pr.md's; a change
# to that wording changes the text below, and node-push_test.sh runs work-on's
# own check over the body written here.
#
# In order:
#   1. check every value against its closed pattern (slug ^[a-z0-9-]+$, node
#      id ^[a-z][a-z0-9-]*$, repositories owner/repo, issues a comma-joined
#      list of numbers); in node mode, read the PLAN's nodes through
#      plan-to-tasks.sh, refuse a PLAN that has no node named --node, and read
#      each --issues work item's goal from the PLAN into the node's
#      description, all before anything is pushed or edited; then collect the
#      node's deferral reasons;
#   (the order mode skips steps 2, 4, 5, 5b, and the node-branch check in 3)
#   2. refuse a detached HEAD, a checked-out branch other than the expected
#      one, and the remote's default branch; in node mode, for a node whose
#      repository is not the coordination PR's, refuse a worktree that
#      shares the coordination checkout's git directory or origin URL;
#   3. before any push, read the coordination PR the run record names (open,
#      carrying the `This is a **coordination PR**` marker; a session with no
#      run record is 73) and, in node mode, check the node branch's PR: another run's
#      PR there, or several, stops with 73 and nothing pushed, and the
#      run's own PR there whose body doesn't record the node's deferral
#      stops with 80, nothing pushed. Before those
#      reads, in node mode, read the home repository's and the node
#      repository's visibility live (coord_node_visibility): a private node
#      under a public coordination PR is refused with 77, and a public node
#      under a private one has its commits since the default branch (added
#      lines and messages) and the node's description scanned for the
#      public-content markers, a hit or a failed scan refused with 78;
#      nothing pushed either way;
#   4. push with exactly `git push <remote> HEAD:refs/heads/<branch>`, never a
#      force option;
#   5. node mode: find the node's owned PR on impl/<slug>-<node-id>. One
#      survivor is adopted. Zero survivors open a draft PR against the default
#      branch, titled `<type>(<slug>): <node-id>`, with a two-part body passed
#      with --body-file: the node's description (each work item's goal from
#      the PLAN), one top-level `---`, then the fixed fields (the node id,
#      the work-item ids, the coordination PR's link, and, under include,
#      the `## Verification` section when the node carries a deferral and the
#      one `Run record:` line last). The type is `docs` when every file the node changes against
#      the default branch is under docs/ or a Markdown file at the repository
#      root, `feat` otherwise. The link is left out when the node's
#      repository is public and the coordination PR's is private, so a public
#      PR never points into a private one. `shirabe validate --pr-body` with
#      --pr-title checks the body and title first, and a refusal creates
#      nothing. Unless the run record already names a PR for this node
#      (`run/node/<node>`), which must then be the one adopted: zero
#      survivors, or a survivor other than the recorded PR, refuse;
#   5b. record the pushed commit in the run record: node mode
#      `run/node/<node>` {repo, pr, head} (`run-record.sh push`, which keeps a
#      recorded merged_head), coordination mode `run/cascade` {verdict:
#      pushed, head} (`run-record.sh cascade`). A refused or failed write is
#      exit 70, and nothing is rendered;
#   5c. node mode: record the node PR in the run's trail through
#      scripts/run-trail.sh: `pr` (role node, state open) in the root, then
#      `index` (mode coordinated, topic <slug>) at the PR's owner's shared
#      address, so a lookup from the node PR reaches the run. Either one
#      failing is exit 70, naming the PR, and nothing is rendered;
#   6. render the coordination PR's body from the record: coord-render.sh,
#      which observes merges, validates the body with
#      `shirabe validate --coordination-body`, and posts it with
#      `gh pr edit --body-file` only when it differs from the live one.
#
# Output: `pr=<url>` and `head=<sha>` on stdout (the order mode prints only
# `pr=<coordination PR url>`), then coord-render.sh's
# `body=<posted|unchanged|stale|full>` line (its `observed=` lines go to
# stderr). Diagnostics on stderr.
#
# Exit codes:
#   0   pushed and recorded (order mode: rendered), whatever the body= line
#   64  usage error
#   65  HEAD is detached
#   66  the checked-out branch is not the expected one, or its name is refused
#   67  the branch is the remote's default branch
#   68  the push failed; nothing was recorded
#   69  HEAD, read back after the push, is not a commit id
#   70  the run record write failed or was refused, or (node mode) the node
#       PR's trail or index write failed, stderr naming the PR; the push
#       happened, and the coordination PR's body was not rendered (the
#       caller's execute:push)
#   72  a GitHub read failed, or the run record could not be read (the
#       caller's execute:status-read)
#   73  no single owned PR where one must be adopted: the recorded
#       coordination PR is not open, has lost its marker, or the session has
#       no run record; or the node's recorded PR is not the one owned PR on
#       its branch; or the node branch's PR is another run's, or one of
#       several (checked before the push, so nothing is pushed then) (the
#       caller's execute:pr-adopt)
#   74  node mode: shirabe validate --pr-body refused a new node PR's body or
#       title, and no PR was created
#   75  node mode: gh pr create failed, or the new node PR's body could not
#       be stamped with the run's marker
#   76  node mode: plan-to-tasks.sh could not read the PLAN, the PLAN is not
#       coordinated (a node without NODE_KIND pr or gate), the PLAN has no
#       node named --node, or a work item's goal could not be read from it;
#       nothing was pushed or edited
#   77  node mode: the node's repository is private and the coordination
#       PR's is public, and nothing was pushed or edited; or, in any mode,
#       the render refused a record that would index a private repository in
#       a public coordination PR (body=refused:execute:visibility), after the
#       push and the record write, with nothing posted (the caller's
#       execute:visibility)
#   78  node mode: a public node under a private coordination PR whose
#       commits, description or deferral reasons carry private-repository
#       markers, or whose
#       commits the check couldn't read; nothing was pushed or edited
#       (execute:visibility)
#   79  node mode: the node names a repository other than the coordination
#       PR's, but this worktree shares the coordination checkout's git
#       directory (a node cut without node-cut.sh --repo-dir) or its push
#       URL names the same repository as the checkout's origin fetch or push
#       URL (a clone of the coordination PR's repository; network URLs
#       compared by host and path, local paths as written), or either git
#       directory could not be read; nothing was pushed or edited
#       (execute:dispatch)
#   80  node mode: the node carries a verification deferral, and the owned PR
#       on its branch doesn't record it in its body (stderr names each part
#       missing); nothing was pushed or edited (execute:deferral-record)
#
# A deferral that can't be read (a koto read that failed, hosted-ci with no
# reason) or checked (a GitHub read for the body) is a 72, like a failed
# GitHub read, and nothing is pushed.
#
# A failed visibility read is a 72, like any other GitHub read.
#
# Requires: bash 3.2+, git, gh, jq, koto, shirabe.
set -uo pipefail

PROG=node-push

COORD_SELF_DIR=$(CDPATH='' cd "$(dirname "${BASH_SOURCE[0]}")" && pwd) || exit 64
# shellcheck source=coord-common.sh
. "$COORD_SELF_DIR/coord-common.sh"

usage_error() {
    echo "$PROG: $*" >&2
    echo "usage: node-push.sh node --session <koto-session> --slug <slug> --node <node-id> --repo <owner/repo> --issues <ids> --home-repo <owner/repo> --coord-branch <branch> --plan <path> [--remote <name>] [--run-id <id>] [--verification <local|hosted-ci|\"\"> [--reason <text>]]" >&2
    echo "       node-push.sh coordination --session <koto-session> --slug <slug> --home-repo <owner/repo> --coord-branch <branch> [--remote <name>] [--run-id <id>]" >&2
    echo "       node-push.sh order --session <koto-session> --slug <slug> --home-repo <owner/repo> --coord-branch <branch> [--run-id <id>]" >&2
    exit 64
}

[ $# -ge 1 ] || usage_error "a mode is required"
MODE="$1"; shift
case "$MODE" in node|coordination|order) ;; *) usage_error "mode must be node, coordination, or order, got [$MODE]" ;; esac

SESSION=""; SLUG=""; NODE=""; REPO=""; ISSUES=""; HOME_REPO=""; CB=""; PLAN=""; REMOTE="origin"
VERIFICATION=""; RUN_REASON=""
SEEN=" "
while [ $# -gt 0 ]; do
    case "$1" in
        --session|--slug|--node|--repo|--issues|--home-repo|--coord-branch|--plan|--remote|--run-id|--verification|--reason)
            [ $# -ge 2 ] || usage_error "$1 needs a value"
            case "$SEEN" in *" $1 "*) usage_error "$1 given more than once" ;; esac
            SEEN="$SEEN$1 "
            case "$1" in
                --run-id) COORD_RUN_ID="$2" ;;
                --session) SESSION="$2" ;;
                --slug) SLUG="$2" ;;
                --node) NODE="$2" ;;
                --repo) REPO="$2" ;;
                --issues) ISSUES="$2" ;;
                --home-repo) HOME_REPO="$2" ;;
                --coord-branch) CB="$2" ;;
                --plan) PLAN="$2" ;;
                --remote) REMOTE="$2" ;;
                --verification) VERIFICATION="$2" ;;
                --reason) RUN_REASON="$2" ;;
            esac
            shift 2
            ;;
        *) usage_error "unexpected argument [$1]" ;;
    esac
done

case "$SEEN" in *" --session "*) ;; *) usage_error "--session is required" ;; esac
[[ $SESSION =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || usage_error "--session [$SESSION] is not a koto session name"
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
    case "$VERIFICATION" in ""|local|hosted-ci) ;; *) usage_error "--verification must be local or hosted-ci, got [$VERIFICATION]" ;; esac
    BRANCH="impl/$SLUG-$NODE"
elif [ "$MODE" = order ]; then
    # The merge order renders from run/setup's node list, so the order mode
    # reads no PLAN.
    for f in --node --repo --issues --remote --plan --verification --reason; do
        case "$SEEN" in *" $f "*) usage_error "$f does not belong to the order mode" ;; esac
    done
else
    for f in --node --repo --issues --plan --verification --reason; do
        case "$SEEN" in *" $f "*) usage_error "$f belongs to the node mode" ;; esac
    done
    BRANCH="$CB"
fi
command -v jq >/dev/null || { echo "$PROG: jq is not on PATH" >&2; exit 72; }
SHIRABE="${SHIRABE_BIN:-shirabe}"

# 1. The node, in the PLAN, before anything is pushed.
if [ "$MODE" = node ]; then
    # jq given no input runs nothing and exits 0, so an empty result is
    # checked as well as each command's status. Only a coordinated PLAN's
    # nodes carry NODE_KIND (pr or gate); any other PLAN's tasks don't, and
    # are refused rather than pushed as a node.
    TASKS=$("$BASH" "$COORD_PLAN_TO_TASKS" "$PLAN" </dev/null) \
    && ORDER_LINES=$(printf '%s' "$TASKS" | jq -r --arg re "$RE_COORD_NODE" '
        if type == "array" and length > 0
            and all(.[]; (.name | type) == "string" and (.name | test($re))
                         and (.vars.NODE_KIND == "pr" or .vars.NODE_KIND == "gate"))
        then .[] | "\(.name) | \(.vars.NODE_KIND) | after: \(if (.waits_on | length) == 0 then "-" else (.waits_on | join(", ")) end)"
        else error("no usable node list") end' 2>/dev/null) \
    && [ -n "$ORDER_LINES" ] || {
        echo "$PROG: plan-to-tasks.sh could not read [$PLAN] into a coordinated node list; nothing was pushed or edited" >&2
        exit 76
    }
    if ! grep -q "^$NODE |" <<<"$ORDER_LINES"; then
        echo "$PROG: the PLAN [$PLAN] has no node $NODE; nothing was pushed" >&2
        exit 76
    fi
fi

# work_item_goal <number> -- one work item's goal from the PLAN, on one line:
# an outline's `**Goal**:` text (`### Issue <n>:` under `## Issue Outlines`),
# else the italic summary row under its `[#<n>: <title>](...)` row in
# `## Implementation Issues` (annotation rows, `^_..._`, are not summaries),
# else that row's title. Prints nothing when the PLAN names no such item.
# Fenced blocks are skipped, so an example in the PLAN is never read as one.
#
# It reads plan/v1 forms only, on purpose. This script serves coordinated
# plans, and a plan/v2 step plan cannot be one: `shirabe validate` refuses a
# coordinated plan/v2 (FC22) and plan-to-tasks.sh refuses it too, naming
# plan/v1. So a `### Step <N>:` heading never reaches this function, and it
# has no step form to read.
work_item_goal() {
    awk -v n="$1" '
        function flat(s) { gsub(/[[:space:]]+/, " ", s); sub(/^ /, "", s); sub(/ $/, "", s); return s }
        /^[[:space:]]*(```|~~~)/ { fence = !fence; next }
        fence { next }
        /^## / { sec = flat($0); inblk = 0; ingoal = 0; inrow = 0; next }
        sec == "## Issue Outlines" && /^### / {
            ingoal = 0
            inblk = (index($0, "### Issue " n ":") == 1)
            next
        }
        inblk {
            line = $0
            if (ingoal && (line ~ /^[[:space:]]*$/ || line ~ /^[[:space:]]*(\*\*|#|---)/)) ingoal = 0
            if (ingoal) { goal = goal " " line; next }
            if (line ~ /^[[:space:]]*\*\*Goal\*\*:/ && goal == "") {
                sub(/^[[:space:]]*\*\*Goal\*\*:/, "", line)
                goal = line; ingoal = 1
            }
            next
        }
        sec == "## Implementation Issues" && /^[[:space:]]*\|/ {
            cell = $0
            sub(/^[[:space:]]*\|[[:space:]]*/, "", cell)
            if (substr(cell, 1, 1) == "[") {
                inrow = (index(cell, "[#" n ":") == 1)
                if (inrow && title == "") {
                    t = substr(cell, length("[#" n ":") + 1)
                    p = index(t, "](")
                    if (p > 0) title = substr(t, 1, p - 1)
                }
                next
            }
            if (inrow && summary == "" && cell ~ /^_/) {
                sub(/[[:space:]]*\|.*$/, "", cell)
                if (cell ~ /^_.*_$/ && length(cell) > 2) summary = substr(cell, 2, length(cell) - 2)
            }
        }
        END {
            goal = flat(goal); summary = flat(summary); title = flat(title)
            if (goal != "") print goal
            else if (summary != "") print summary
            else if (title != "") print "Work item " n ": " title "."
        }
    ' "$PLAN"
}

# The node PR's description, rendered in node mode before anything is pushed
# so the public-content check below can read it: one paragraph per work item,
# its goal from the PLAN, in --issues order. It becomes the first part of a
# new node PR's body, the part a squash merge keeps; a PLAN that names none
# of the items gets a sentence naming the node instead.
NODE_DESC=""
if [ "$MODE" = node ]; then
    OLDIFS=$IFS; IFS=,
    for item in $ISSUES; do
        IFS=$OLDIFS
        g=$(work_item_goal "$item") || {
            echo "$PROG: could not read work item $item's goal from [$PLAN]; nothing was pushed or edited" >&2
            exit 76
        }
        [ -n "$g" ] && NODE_DESC="${NODE_DESC:+$NODE_DESC

}$g"
    done
    IFS=$OLDIFS
    [ -n "$NODE_DESC" ] || NODE_DESC="Implements node $NODE of the $SLUG coordinated effort, work items $ISSUES."
fi

# The node's verification deferral (see the header), read before anything is
# pushed: the run's reason and each work item's child's, one per line. The
# work items are --issues and the node's own ISSUES in the PLAN, so an
# --issues that leaves an item out can't hide that item's deferral.
DEFERRAL_ARGS=()
DEFERRAL=""
if [ "$MODE" = node ]; then
    DEFERRAL_ARGS=(--session "$SESSION" --verification "$VERIFICATION" --reason "$RUN_REASON")
    PLAN_ISSUES=$(printf '%s' "$TASKS" | jq -r --arg n "$NODE" \
        '[.[] | select(.name == $n) | .vars.ISSUES // empty] | first // ""')
    OLDIFS=$IFS; IFS=,
    SEEN_ITEMS=,
    for item in $ISSUES $PLAN_ISSUES; do
        case "$item" in ''|*[!0-9]*) continue ;; esac
        case "$SEEN_ITEMS" in *",$item,"*) continue ;; esac
        SEEN_ITEMS="$SEEN_ITEMS$item,"
        DEFERRAL_ARGS+=(--child "work-on-$SLUG-$NODE-$item")
    done
    IFS=$OLDIFS
    DEFERRAL=$("$BASH" "$COORD_SELF_DIR/shared-deferral-record.sh" "${DEFERRAL_ARGS[@]}" --list </dev/null) || {
        echo "$PROG: could not read node $NODE's verification deferral; nothing was pushed" >&2
        exit 72
    }
fi

# Step 2 prepares a branch to push; the order mode pushes nothing.
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
        | sed -n 's#^ref: refs/heads/\([^[:space:]]*\)[[:space:]]*HEAD$#\1#p')
    DEFAULT=${DEFAULT%%$'\n'*}
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
        HOME_FETCH=$(CDPATH='' cd "$PLAN_DIR" && git remote get-url origin) || HOME_FETCH=""
        HOME_URL=$(CDPATH='' cd "$PLAN_DIR" && git remote get-url --push origin) || HOME_URL=""
        NODE_URL=$(git remote get-url --push "$REMOTE") || NODE_URL=""
        if [ -z "$HOME_GIT" ] || [ -z "$NODE_GIT" ]; then
            echo "$PROG: could not read the git directories of this worktree and of the coordination checkout the PLAN is in; nothing was pushed. Pass --plan as the PLAN inside the coordination checkout (the recorded plan_abs), and run this from a node worktree node-cut.sh made" >&2
            exit 79
        fi
        HOME_FETCH=$(coord_url_key "$HOME_FETCH")
        HOME_URL=$(coord_url_key "$HOME_URL")
        NODE_URL=$(coord_url_key "$NODE_URL")
        if [ "$HOME_GIT" = "$NODE_GIT" ] \
            || { [ -n "$NODE_URL" ] && { [ "$NODE_URL" = "$HOME_FETCH" ] || [ "$NODE_URL" = "$HOME_URL" ]; }; }; then
            # Names no repository, either of which may be private: only the
            # node id and this worktree's local path and branch.
            echo "$PROG: node $NODE lands in another repository than the coordination PR's, but this worktree belongs to, or pushes to, the coordination checkout's; cut it with node-cut.sh --repo-dir <a clone of the node's repository>. Nothing was pushed. Re-cut the node in its own repository's clone and run its work items there; then remove this worktree ($(git rev-parse --show-toplevel)) with git worktree remove and its branch $BRANCH with git branch -D, both in the repository this worktree belongs to" >&2
            exit 79
        fi
    fi
fi

# 3a. The node against its own target, before any other read can name its
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
        # The node PR's description comes from the same private PLAN, and a
        # new node PR publishes it, with any deferral reason it records.
        printf '%s\n' "$NODE_DESC" >>"$SCAN_DIR/text"
        [ -z "$DEFERRAL" ] || printf '%s\n' "$DEFERRAL" >>"$SCAN_DIR/text"
        SCAN=0
        grep -Eq '(^|[^A-Za-z0-9_.-])private/[A-Za-z0-9._-]|Repo Visibility:[[:space:]]*Private' "$SCAN_DIR/text" || SCAN=$?
        rm -rf "$SCAN_DIR"
        case "$SCAN" in
            0) echo "$PROG: node $NODE lands in a public repository from a private PLAN, and its commits or its work items' goals in the PLAN carry private-repository content (a private/ path or a Repo Visibility: Private line); remove it and push again. Nothing was pushed." >&2
               exit 78 ;;
            1) ;;
            *) echo "$PROG: the public-content check could not scan node $NODE's commits (grep exit $SCAN); nothing was pushed" >&2
               exit 78 ;;
        esac
    fi
fi

# 3b. Ownership, before anything is pushed: the coordination PR the run
# record names, and in node mode whose PR (if any) is already on the node
# branch. A branch whose PR another run opened is never pushed to, so a run
# can't move another run's PR head.
coord_recorded_pr "$SESSION" "$HOME_REPO" open
case $? in
    0) ;;
    2) exit 72 ;;
    *) exit 73 ;;
esac
WORK=$(mktemp -d "${TMPDIR:-/tmp}/node-push.XXXXXX") || exit 72
trap 'rm -rf "$WORK"' EXIT
REC_PR=""
if [ "$MODE" = node ]; then
    # owned-pr-callers_test.sh matches this line to check the lookup comes
    # before the push.
    OWNED_NOW=$(coord_owned "$REPO" "$BRANCH" open)
    case $? in
        0) ;;
        2) exit 72 ;;
        *) echo "$PROG: no single PR this run owns on $REPO $BRANCH; nothing pushed" >&2; exit 73 ;;
    esac
    # A node PR already open that carries a deferred work item gets no push
    # until its body records the deferral, under include: the check
    # /execute's single-pr gate makes, over the same owned PR. Under omit the
    # work items' verification_deferral keys are the record, and it passes.
    if [ -n "$DEFERRAL" ] && [ -n "$OWNED_NOW" ]; then
        OWNED_ARGS=(--repo "$REPO" --head "$BRANCH" --state open)
        [ -n "$COORD_RUN_ID" ] && OWNED_ARGS+=(--run-id "$COORD_RUN_ID")
        "$BASH" "$COORD_SELF_DIR/shared-deferral-record.sh" "${DEFERRAL_ARGS[@]}" -- "${OWNED_ARGS[@]}" </dev/null
        case $? in
            0) ;;
            1) echo "$PROG: node $NODE carries a verification deferral that $OWNED_NOW's body doesn't record; nothing was pushed. Add the ## Verification section to its body and push again" >&2
               exit 80 ;;
            *) echo "$PROG: could not check $OWNED_NOW's body for node $NODE's verification deferral; nothing was pushed" >&2
               exit 72 ;;
        esac
    fi
    # The PR the run record already names for this node, if any.
    REC_NODE=$(rr_node "$SESSION" "$NODE")
    case $? in
        0) REC_PR=$(printf '%s' "$REC_NODE" | jq -r '.pr // ""') ;;
        1) ;;
        *) echo "$PROG: could not read node $NODE's run record; nothing pushed" >&2; exit 72 ;;
    esac
fi

# 4. The push: the explicit refspec, never a force option. The order mode
# pushes nothing.
if [ "$MODE" != order ]; then
    if ! git push "$REMOTE" "HEAD:refs/heads/$BRANCH" </dev/null >&2; then
        echo "$PROG: the push failed; nothing was recorded" >&2
        exit 68
    fi
    SHA=$(git rev-parse HEAD)
    [[ $SHA =~ $RE_COORD_SHA ]] || { echo "$PROG: HEAD read back as [$SHA]" >&2; exit 69; }
fi

# node_type <base-branch> -- the Conventional Commits type of a new node PR:
# `docs` when every file the node changes against <base-branch> on the remote
# sits under docs/ or is a Markdown file at the repository root, `feat`
# otherwise, and `feat` when the files can't be read. Markdown elsewhere is
# not taken as docs: a skill or a koto template is Markdown, and changing one
# changes behaviour.
node_type() {
    local mb files
    mb=$(git merge-base HEAD "refs/remotes/$REMOTE/$1") || { echo feat; return 0; }
    files=$(git diff --name-only "$mb" HEAD) || { echo feat; return 0; }
    if [ -n "$files" ] && ! grep -Ev '^docs/|^[^/]+\.md$' <<<"$files" | grep . >/dev/null; then
        echo docs
    else
        echo feat
    fi
}

# render_body -- coord-render.sh over the record just written: print its
# body= line, its observed= lines to stderr, and stop with 77 on a
# visibility refusal. A stale or full body is reported, never an exit code:
# the push and the record stand, and the next transition renders again.
render_body() {
    local out rc
    out=$("$BASH" "$COORD_SELF_DIR/coord-render.sh" --session "$SESSION" --slug "$SLUG" \
        --home-repo "$HOME_REPO" --coord-branch "$CB" </dev/null)
    rc=$?
    printf '%s\n' "$out" | grep '^observed=' >&2
    printf '%s\n' "$out" | grep '^body=' | tail -1
    case "$rc" in
        0) ;;
        77) echo "$PROG: the coordination PR's body was not posted: the record would index a private repository in a public coordination PR${1:+; $1}" >&2
            exit 77 ;;
        *) echo "$PROG: coord-render.sh exited $rc; the body was not posted" >&2
           printf 'body=stale\n' ;;
    esac
}

# The order mode pushes and records nothing: it only renders.
if [ "$MODE" = order ]; then
    printf 'pr=%s\n' "$C_URL"
    render_body
    exit 0
fi

# 5. The node's PR. The run record (REC_PR, read before the push), not the
# body, says whether one was already recorded for this node, which must then
# be the one adopted.
if [ "$MODE" = node ]; then
    OUT=$(coord_owned "$REPO" "$BRANCH" open)
    case $? in
        0) ;;
        2) exit 72 ;;
        *) exit 73 ;;
    esac
    if [ -z "$OUT" ]; then
        if [ -n "$REC_PR" ]; then
            echo "$PROG: the run record names #$REC_PR for $NODE, and no owned open PR is on $REPO $BRANCH to adopt" >&2
            exit 73
        fi
        REPO_JSON=""
        coord_gh_read REPO_JSON api "repos/$REPO" || exit 72
        BASE=$(printf '%s' "$REPO_JSON" | jq -r 'if type == "object" then (.default_branch // "") else "" end')
        coord_valid_branch "$BASE" || { echo "$PROG: the default branch of $REPO is unusable [$BASE]" >&2; exit 72; }
        # The body is the two-part shape a squash merge expects: the node's
        # description, one top-level `---`, then the fixed fields. The run's
        # recorded switch decides the rest: under include, the deferral's
        # record and the one line naming the run's record; under omit,
        # nothing of the run (the work items' keys hold the deferral).
        # A public node PR links its coordination PR only when that PR is
        # public too: a link from a public PR into a private repository is a
        # public-to-private reference.
        CONTENT=$("$BASH" "$COORD_SELF_DIR/../../../scripts/pr-workflow-content.sh" --session "$SESSION" </dev/null) \
            || { echo "$PROG: the run's PR content switch could not be read; nothing created" >&2; exit 75; }
        REF=""
        if [ "$CONTENT" = include ]; then
            REF=$("$BASH" "$COORD_SELF_DIR/../../../scripts/pr-workflow-content.sh" --reference "$SESSION" </dev/null) \
                || { echo "$PROG: the run's record reference could not be read; nothing created" >&2; exit 75; }
        fi
        {
            printf '%s\n\n---\n\n' "$NODE_DESC"
            printf 'Coordinated node `%s` of `%s`.\n\n' "$NODE" "$SLUG"
            printf 'Work items: %s\n' "$ISSUES"
            # Omitted exactly when the home is private and the node public
            # (step 3a has already refused a public home over a private node).
            if ! { [ "$COORD_HOME_VIS" = private ] && [ "$COORD_NODE_VIS" = public ]; }; then
                printf '\nCoordination PR: %s\n' "$C_URL"
            fi
            # The deferral's record, in phase-6-pr.md's words, one Reason:
            # line per reason, under include only.
            if [ -n "$DEFERRAL" ] && [ "$CONTENT" = include ]; then
                printf '\n## Verification\n\nLocal verification did not run: it was deferred to hosted CI.\n'
                while IFS= read -r r; do
                    printf 'Reason: %s\n' "$r"
                done <<<"$DEFERRAL"
                printf 'Hosted CI is the build of record for this change.\n'
            fi
            [ -z "$REF" ] || printf '\n%s\n' "$REF"
        } > "$WORK/node-body.md"
        TYPE=$(node_type "$BASE")
        TITLE="$TYPE($SLUG): $NODE"
        # A slug shaped like an issue number is no Conventional Commits scope.
        RE_ISSUE_SCOPE='^(issue[-_]?)?[0-9]+$'
        [[ $SLUG =~ $RE_ISSUE_SCOPE ]] && TITLE="$TYPE: $SLUG $NODE"
        if ! "$SHIRABE" validate --pr-body "$WORK/node-body.md" --pr-title "$TITLE" >&2; then
            echo "$PROG: shirabe validate --pr-body refused the node PR's title or body; no PR was created" >&2
            exit 74
        fi
        OUT=$(gh pr create --repo "$REPO" --draft --base "$BASE" --head "$BRANCH" \
            --title "$TITLE" --body-file "$WORK/node-body.md" </dev/null) || {
            echo "$PROG: gh pr create failed" >&2
            exit 75
        }
        OUT=$(printf '%s\n' "$OUT" | grep -E "$RE_COORD_URL" | tail -1)
    elif [ -n "$REC_PR" ] && [ "$REC_PR" != "${OUT##*/}" ]; then
        echo "$PROG: the run record names #$REC_PR for $NODE, not the owned PR $OUT" >&2
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

# 5b. The pushed commit, in the run record, before the body is rendered: a
# post that fails after this leaves the head recorded, and a write that fails
# here renders nothing.
if [ "$MODE" = node ]; then
    jq -cn --arg k "run/node/$NODE" --arg r "$REPO" --argjson p "$PR_NUM" --arg h "$SHA" \
        '{($k): {repo: $r, pr: $p, head: $h}}' > "$WORK/record.json"
    RR_VERB=push
else
    jq -cn --arg h "$SHA" '{"run/cascade": {verdict: "pushed", head: $h}}' > "$WORK/record.json"
    RR_VERB=cascade
fi
if ! "$BASH" "$COORD_SELF_DIR/run-record.sh" "$RR_VERB" --session "$SESSION" --json "$WORK/record.json" </dev/null >&2; then
    echo "$PROG: the run record write failed; the push happened, and the coordination PR's body was not rendered" >&2
    exit 70
fi

# 5c. Node mode: the node PR in the run's trail, in the same call that
# recorded it: the root lists it (`trail/pr/*`, role node) and its index
# session, at its owner's shared address, names the root, so a lookup from
# the node PR (scripts/run-record-lookup.sh) reaches the run. Both go through
# scripts/run-trail.sh, whose index entry takes the root's address from the
# `trail/self` record-coord-setup.sh wrote in the coordination checkout.
if [ "$MODE" = node ]; then
    TRAIL="$COORD_SELF_DIR/../../../scripts/run-trail.sh"
    "$BASH" "$TRAIL" pr --session "$SESSION" --repo "$REPO" --number "$PR_NUM" --role node --state open </dev/null >&2 \
        || { echo "$PROG: could not record the node PR $PR_URL in $SESSION's run record; the push happened, and the body was not rendered" >&2; exit 70; }
    "$BASH" "$TRAIL" index --repo "$REPO" --number "$PR_NUM" --session "$SESSION" --mode coordinated --topic "$SLUG" </dev/null >&2 \
        || { echo "$PROG: could not write the index entry of the node PR $PR_URL; the push happened, and the body was not rendered" >&2; exit 70; }
fi

# 6. The body, rendered from the record just written.
printf 'pr=%s\nhead=%s\n' "$PR_URL" "$SHA"
render_body "the push happened and the record holds it"
exit 0
