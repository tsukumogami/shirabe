#!/usr/bin/env bash
# publish-scoping-pr.sh -- /scope's one push and one pull request, on intent runs.
#
# With --intent set, /scope pushes its branch and opens one PR at exit, once the
# PLAN's mode is known (R9). This script is that step. The publish states in
# skills/scope/koto-templates/scope.md (publish_full_run, publish_re_evaluation,
# publish_abandonment) and `republish` have the agent run it, because a push and
# `gh pr create` are externally visible events and never a default action
# (references/default-action-conversion.md). Each of those states then gates on
# this script's --verify mode, which makes no write, so a run cannot claim a PR
# it did not open.
#
# Publish, in order; any failure stops with its step and no later write:
#
#   1. validate --topic against the slug pattern; read the mode from the PLAN's
#      frontmatter (never from evidence) -- required on a full-run exit
#   2. refuse a detached HEAD, a branch failing `git check-ref-format --branch`,
#      a missing `origin`, and the remote's default branch (or main/master)
#                                                            -> scope:push
#   3. untrack the topic's own wip/ prefixes: `git rm --cached` of the tracked
#      wip/{scope,brief,prd,design,plan}_<topic>_* and
#      wip/research/{prd,design}_<topic>_* paths, committed as exactly that
#      removal (built from HEAD's tree through a private index, so nothing
#      else staged rides along). The files stay on disk for cleanup.
#   4. list every wip/ path in commits not yet on origin, run the
#      public-content visibility check over those files, and stop on a hit
#                                                            -> scope:push
#   5. push with `git push origin HEAD:refs/heads/<branch>` -- never a force
#      option, never a `+` refspec                           -> scope:push
#   6. look the PR up through skills/execute/scripts/owned-pr.sh, unchanged,
#      with --state open and --base <default>:
#        one survivor   reused; its body is rewritten with
#                       `gh pr edit --body-file` only when its intent= field
#                       differs from --intent
#        zero           one `gh pr create --head <branch> --base <default>
#                       --title <title> --body-file <file>` (a foreign-only
#                       branch counts as zero), then looked up again
#        several (3)    scope:pr-create, no write
#        read fails (2) scope:pr-create, no write
#
# Draft or ready (R9): a draft for a single-pr or coordinated full-run and for
# the re-evaluation and abandonment-forced exits; ready for a multi-pr
# full-run, which is meant to merge and land the Active PLAN.
#
# The body is a fixed template over validated fields only: the slug, exit,
# outcome, `intent=`, mode, the docs/ artifact paths that exist, and the PLAN's
# work-item IDs. No free-text state field reaches it. A coordinated body starts
# with the fixed coordination-PR declaration prefix and is checked with
# `shirabe validate --coordination-body` before it is posted.
#
# --verify exits 0 only when `git ls-remote origin refs/heads/<branch>` equals
# `git rev-parse HEAD`, exactly one owned open PR exists on the branch, and,
# with --expect-intent, that PR's body records `intent=<value>`. It makes no
# write call of any kind.
#
# The public-content visibility check. In a repository whose CLAUDE.md (or
# CLAUDE.local.md) declares `## Repo Visibility: Public`, a wip/ file in
# unpushed history is a hit when a line names a `private/` path component or
# declares `Repo Visibility: Private` -- the workspace's markers for content
# from a private repository. The paths are reported either way, as wip_paths=.
#
# Usage:
#   publish-scoping-pr.sh --topic <slug> --exit <full-run|re-evaluation|abandonment-forced>
#                         --intent <continue|stop> [--session <name>]
#   publish-scoping-pr.sh --topic <slug> --verify [--expect-intent <continue|stop>]
#
# With --session (publish mode only), the script clears the context keys
# publish_step and wip_paths when it starts, writes wip_paths when unpushed
# history holds any, and writes publish_step (scope:push or scope:pr-create)
# with `koto context add` when it fails. The publish states route on
# publish_step through non-overridable context-matches gates.
#
# Output (stdout, key=value lines):
#   publish:  mode=<mode>, wip_paths=<comma-joined> when any, pr=<url> on
#             success; step=<scope:push|scope:pr-create> on failure
#   verify:   pr=<url> on success
#
# Exit codes:
#   publish:  0 published; 10 scope:push; 11 scope:pr-create; 64 usage;
#             66 a koto context call failed
#   verify:   0 verified; 1 not verified; 2 could not read; 64 usage
#
# Requires: bash 3.2+, git, gh, jq; shirabe for a coordinated body; koto with
# --session.
set -uo pipefail

PROG=publish-scoping-pr
HERE=$(cd "$(dirname "$0")" && pwd)
OWNED="$HERE/../../execute/scripts/owned-pr.sh"

RE_TOPIC='^[a-z0-9][a-z0-9-]*$'
RE_REPO='^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$'
RE_PR_URL='^https://github\.com/[A-Za-z0-9._-]+/[A-Za-z0-9._-]+/pull/[1-9][0-9]*$'
RE_SESSION='^[A-Za-z0-9][A-Za-z0-9._-]*$'
DECLARATION='> This is a **coordination PR** for a coordinated effort. It is docs-only and'

usage() {
    printf '%s: %s\n' "$PROG" "$1" >&2
    printf 'usage: publish-scoping-pr.sh --topic <slug> --exit <exit> --intent <continue|stop> [--session <name>]\n' >&2
    printf '       publish-scoping-pr.sh --topic <slug> --verify [--expect-intent <continue|stop>]\n' >&2
    exit 64
}

TOPIC=""; EXIT=""; INTENT=""; SESSION=""; VERIFY=0; EXPECT=""
SEEN=" "
while [ "$#" -gt 0 ]; do
    case "$1" in
        --topic|--exit|--intent|--session|--expect-intent)
            [ "$#" -ge 2 ] || usage "$1 needs a value"
            case "$SEEN" in *" $1 "*) usage "$1 given more than once" ;; esac
            SEEN="$SEEN$1 "
            case "$1" in
                --topic) TOPIC="$2" ;;
                --exit) EXIT="$2" ;;
                --intent) INTENT="$2" ;;
                --session) SESSION="$2" ;;
                --expect-intent) EXPECT="$2" ;;
            esac
            shift ;;
        --verify)
            case "$SEEN" in *" --verify "*) usage "--verify given more than once" ;; esac
            SEEN="$SEEN--verify "; VERIFY=1 ;;
        *) usage "unknown argument: $1" ;;
    esac
    shift
done

[[ "$TOPIC" =~ $RE_TOPIC ]] || usage "--topic [$TOPIC] does not match $RE_TOPIC"
if [ "$VERIFY" -eq 1 ]; then
    [ -z "$EXIT$INTENT$SESSION" ] || usage "--verify takes only --topic and --expect-intent"
    case "$SEEN" in
        *" --expect-intent "*) case "$EXPECT" in continue|stop) ;; *) usage "--expect-intent must be continue or stop" ;; esac ;;
    esac
else
    case "$SEEN" in *" --expect-intent "*) usage "--expect-intent goes with --verify" ;; esac
    case "$EXIT" in full-run|re-evaluation|abandonment-forced) ;; *) usage "--exit must be full-run, re-evaluation or abandonment-forced" ;; esac
    case "$INTENT" in continue|stop) ;; *) usage "--intent must be continue or stop" ;; esac
    if [ -n "$SESSION" ] && ! [[ "$SESSION" =~ $RE_SESSION ]]; then
        usage "--session [$SESSION] is not a koto session name"
    fi
fi

PLAN="docs/plans/PLAN-${TOPIC}.md"
SCRATCH=""
cleanup() { [ -n "$SCRATCH" ] && rm -rf -- "$SCRATCH"; return 0; }
trap cleanup EXIT

# --- shared reads -----------------------------------------------------------------

frontmatter_field() { # frontmatter_field <file> <key>
    awk -v k="$2" '
        NR == 1 { if ($0 !~ /^---[[:space:]]*$/) exit; inside = 1; next }
        inside && /^---[[:space:]]*$/ { exit }
        inside && index($0, k ":") == 1 {
            v = substr($0, length(k) + 2)
            sub(/[[:space:]]+#.*$/, "", v)
            sub(/^[[:space:]]+/, "", v); sub(/[[:space:]]+$/, "", v)
            if (v ~ /^".*"$/ || v ~ /^'"'"'.*'"'"'$/) v = substr(v, 2, length(v) - 2)
            print v; exit
        }
    ' "$1"
}

# default_branch -- the remote's default branch: origin's HEAD symref, else
# what GitHub reports. Empty when neither can be read.
default_branch() {
    local d
    d=$(git ls-remote --symref origin HEAD 2>/dev/null | awk '$1 == "ref:" && $3 == "HEAD" { sub(/^refs\/heads\//, "", $2); print $2; exit }')
    if [ -z "$d" ]; then
        d=$(gh repo view --json defaultBranchRef --jq .defaultBranchRef.name </dev/null 2>/dev/null) || d=""
    fi
    printf '%s' "$d"
}

repo_name() {
    local r
    r=$(gh repo view --json nameWithOwner --jq .nameWithOwner </dev/null 2>/dev/null) || r=""
    [[ "$r" =~ $RE_REPO ]] || return 1
    printf '%s' "$r"
}

# body_intent <url> -- the value of the PR body's `intent=` line.
body_intent() {
    local body
    body=$(gh pr view "$1" --json body --jq .body </dev/null 2>/dev/null) || return 1
    printf '%s\n' "$body" | tr -d '\r' | sed -nE 's/^intent=(continue|stop|none)$/\1/p' | sed -n '1p'
}

# --- verify ---------------------------------------------------------------------------

if [ "$VERIFY" -eq 1 ]; then
    not_verified() { printf '%s: not verified: %s\n' "$PROG" "$1" >&2; exit 1; }
    unreadable()   { printf '%s: cannot verify: %s\n' "$PROG" "$1" >&2; exit 2; }

    BRANCH=$(git symbolic-ref --quiet --short HEAD 2>/dev/null) || not_verified "HEAD is detached"
    git remote get-url origin >/dev/null 2>&1 || not_verified "no origin remote"
    HEAD_SHA=$(git rev-parse HEAD 2>/dev/null) || unreadable "git rev-parse HEAD failed"
    REMOTE=$(git ls-remote origin "refs/heads/$BRANCH" 2>/dev/null) || unreadable "git ls-remote origin failed"
    REMOTE_SHA=$(printf '%s\n' "$REMOTE" | awk 'NR == 1 { print $1 }')
    [ "$REMOTE_SHA" = "$HEAD_SHA" ] || not_verified "origin's $BRANCH is [$REMOTE_SHA], HEAD is $HEAD_SHA"

    DEFAULT=$(default_branch)
    [ -n "$DEFAULT" ] || unreadable "the default branch cannot be read"
    REPO=$(repo_name) || unreadable "the repository name cannot be read"
    URL=$(bash "$OWNED" --repo "$REPO" --head "$BRANCH" --state open --base "$DEFAULT" </dev/null)
    RC=$?
    case "$RC" in
        0) ;;
        3) not_verified "several owned open PRs on $BRANCH" ;;
        *) unreadable "owned-pr.sh exited $RC" ;;
    esac
    [ -n "$URL" ] || not_verified "no owned open PR on $BRANCH"
    [[ "$URL" =~ $RE_PR_URL ]] || unreadable "owned-pr.sh printed a URL outside the pattern"
    if [ -n "$EXPECT" ]; then
        GOT=$(body_intent "$URL") || unreadable "the PR body cannot be read"
        [ "$GOT" = "$EXPECT" ] || not_verified "the PR body records intent=[$GOT], expected $EXPECT"
    fi
    printf 'pr=%s\n' "$URL"
    exit 0
fi

# --- publish ----------------------------------------------------------------------------

ctx() { # ctx add|remove <key> [value]
    [ -n "$SESSION" ] || return 0
    local sess="${KOTO_TICK_SESSION:-$SESSION}"
    if [ "$1" = remove ]; then
        koto context remove "$sess" "$2" >/dev/null && return 0
    else
        printf '%s' "$3" | koto context add "$sess" "$2" >/dev/null && return 0
    fi
    printf '%s: koto context %s failed for %s\n' "$PROG" "$1" "$2" >&2
    exit 66
}

fail() { # fail <step> <message>
    printf '%s: %s\n' "$PROG" "$2" >&2
    ctx add publish_step "$1"
    printf 'step=%s\n' "$1"
    case "$1" in
        scope:push) exit 10 ;;
        *) exit 11 ;;
    esac
}

ctx remove publish_step
ctx remove wip_paths

SCRATCH=$(mktemp -d "${TMPDIR:-/tmp}/publish-scoping-pr.XXXXXX") || fail scope:push "could not make a scratch directory"

git rev-parse --is-inside-work-tree >/dev/null 2>&1 || fail scope:push "not inside a git work tree"
TOP=$(git rev-parse --show-toplevel) || fail scope:push "the work tree root cannot be read"
cd "$TOP" || fail scope:push "cannot enter $TOP"

# 1. the mode, from the PLAN
MODE=""
if [ -f "$PLAN" ]; then
    MODE=$(frontmatter_field "$PLAN" execution_mode)
    case "$MODE" in single-pr|multi-pr|coordinated) ;; *) MODE="" ;; esac
fi
if [ "$EXIT" = full-run ] && [ -z "$MODE" ]; then
    fail scope:push "a full-run exit needs $PLAN with an execution_mode in {single-pr, multi-pr, coordinated}"
fi
printf 'mode=%s\n' "${MODE:-none}"

# 2. the branch
BRANCH=$(git symbolic-ref --quiet --short HEAD 2>/dev/null) || fail scope:push "HEAD is detached; nothing is pushed from a detached HEAD"
git check-ref-format --branch "$BRANCH" >/dev/null 2>&1 || fail scope:push "[$BRANCH] fails git check-ref-format --branch"
case "$BRANCH" in -*) fail scope:push "[$BRANCH] starts with -" ;; esac
git remote get-url origin >/dev/null 2>&1 || fail scope:push "there is no origin remote"
DEFAULT=$(default_branch)
[ -n "$DEFAULT" ] || fail scope:push "origin's default branch cannot be read"
case "$BRANCH" in
    "$DEFAULT"|main|master) fail scope:push "[$BRANCH] is the default branch; /scope never pushes to it" ;;
esac

# 3. untrack the topic's own wip/
UNTRACK=$(git ls-files -- \
    "wip/scope_${TOPIC}_*" "wip/brief_${TOPIC}_*" "wip/prd_${TOPIC}_*" \
    "wip/design_${TOPIC}_*" "wip/plan_${TOPIC}_*" \
    "wip/research/prd_${TOPIC}_*" "wip/research/design_${TOPIC}_*" 2>/dev/null)
if [ -n "$UNTRACK" ]; then
    IDX="$SCRATCH/index"
    OLD=$(git rev-parse HEAD) || fail scope:push "git rev-parse HEAD failed"
    GIT_INDEX_FILE="$IDX" git read-tree HEAD || fail scope:push "could not read HEAD's tree"
    printf '%s\n' "$UNTRACK" | while IFS= read -r p; do
        GIT_INDEX_FILE="$IDX" git rm --cached -q -- "$p" || exit 1
    done || fail scope:push "could not untrack the topic's wip/ paths"
    TREE=$(GIT_INDEX_FILE="$IDX" git write-tree) || fail scope:push "could not write the untrack tree"
    MSG="chore(scope): untrack ${TOPIC} wip/ artifacts"
    NEW=$(git commit-tree "$TREE" -p "$OLD" -m "$MSG") || fail scope:push "could not commit the untrack"
    git update-ref -m "$MSG" "refs/heads/$BRANCH" "$NEW" "$OLD" || fail scope:push "could not move $BRANCH"
    printf '%s\n' "$UNTRACK" | while IFS= read -r p; do
        git rm --cached -q -- "$p" >/dev/null 2>&1 || true
    done
fi

# 4. wip/ in unpushed history, and the visibility check
COMMITS=$(git rev-list HEAD --not --remotes=origin 2>/dev/null) || fail scope:push "cannot list unpushed commits"
WIP_PATHS=""
if [ -n "$COMMITS" ]; then
    WIP_PATHS=$(git log --format= --name-only HEAD --not --remotes=origin -- wip/ 2>/dev/null | sed '/^$/d' | sort -u)
fi

PUBLIC=0
for f in CLAUDE.md CLAUDE.local.md; do
    [ -f "$f" ] && grep -Eqi '^##[[:space:]]+Repo Visibility:[[:space:]]*Public' "$f" && PUBLIC=1
done

if [ -n "$WIP_PATHS" ]; then
    JOINED=$(printf '%s\n' "$WIP_PATHS" | paste -sd, -)
    printf 'wip_paths=%s\n' "$JOINED"
    ctx add wip_paths "$JOINED"
    if [ "$PUBLIC" -eq 1 ]; then
        HIT=""
        # Every version of every listed path that an unpushed commit holds.
        for c in $COMMITS; do
            while IFS= read -r p; do
                [ -n "$p" ] || continue
                if git cat-file -p "$c:$p" 2>/dev/null \
                    | grep -Eq '(^|[^A-Za-z0-9_.-])private/[A-Za-z0-9._-]|Repo Visibility:[[:space:]]*Private'; then
                    HIT="$p"; break
                fi
            done <<EOF
$WIP_PATHS
EOF
            [ -z "$HIT" ] || break
        done
        [ -z "$HIT" ] || fail scope:push "the public-content visibility check found private-repository content in $HIT; nothing was pushed"
    fi
fi

# 5. the push, skipped when origin already holds HEAD (a re-run after success)
HEAD_SHA=$(git rev-parse HEAD) || fail scope:push "git rev-parse HEAD failed"
REMOTE_SHA=$(git ls-remote origin "refs/heads/$BRANCH" 2>/dev/null | awk 'NR == 1 { print $1 }')
if [ "$REMOTE_SHA" != "$HEAD_SHA" ]; then
    git push -q origin "HEAD:refs/heads/$BRANCH" </dev/null >&2 \
        || fail scope:push "the push of HEAD to origin's $BRANCH failed"
fi

# 6. the PR
REPO=$(repo_name) || fail scope:pr-create "the repository name cannot be read"

OUTCOME=""
case "$EXIT" in
    full-run) if [ "$MODE" = multi-pr ]; then OUTCOME=handed-off-multi-pr; else OUTCOME=scoped; fi ;;
    re-evaluation) OUTCOME=re-evaluation ;;
    abandonment-forced) OUTCOME=abandonment ;;
esac

DRAFT=1
[ "$EXIT" = full-run ] && [ "$MODE" = multi-pr ] && DRAFT=0

TITLE="docs(scope): ${TOPIC} (${EXIT})"

# The fixed template. Every value is an enum, the validated slug, or a path
# composed from it; work-item IDs are digits read from the PLAN.
render_body() {
    local f="$1" p ids
    {
        if [ "$MODE" = coordinated ] && [ "$EXIT" = full-run ]; then
            printf '# Coordination PR: %s\n\n' "$TOPIC"
            printf '%s\n' "$DECLARATION"
            printf '> merges **last**, once every indexed PR has merged and finalization is\n'
            printf '> complete. See `references/coordination-strategy.md`.\n\n'
        else
            printf '# /scope: %s\n\n' "$TOPIC"
        fi
        printf 'topic=%s\n' "$TOPIC"
        printf 'exit=%s\n' "$EXIT"
        printf 'outcome=%s\n' "$OUTCOME"
        printf 'intent=%s\n' "$INTENT"
        printf 'mode=%s\n\n' "${MODE:-none}"
        printf '## Artifact Chain\n\n'
        for p in "docs/briefs/BRIEF-${TOPIC}.md" "docs/prds/PRD-${TOPIC}.md" \
                 "docs/designs/DESIGN-${TOPIC}.md" "docs/designs/current/DESIGN-${TOPIC}.md" \
                 "docs/plans/PLAN-${TOPIC}.md"; do
            [ -f "$p" ] && printf -- '- %s\n' "$p"
        done
        for p in docs/decisions/DECISION-*-"${TOPIC}"-*.md; do
            [ -f "$p" ] && printf -- '- %s\n' "$p"
        done
        if [ -f "$PLAN" ]; then
            # Issue numbers from the Implementation Issues table (the first
            # cell of each row), else the outline IDs.
            ids=$(awk '
                /^##[[:space:]]+Implementation[[:space:]]+Issues/ { t = 1; next }
                t && /^##[[:space:]]/ { t = 0 }
                t && /^\|/ {
                    split($0, cells, "|")
                    if (match(cells[2], /#[0-9]+/)) print substr(cells[2], RSTART, RLENGTH)
                }
            ' "$PLAN" | awk '!seen[$0]++')
            if [ -z "$ids" ]; then
                ids=$(awk '/^###[[:space:]]+Issue[[:space:]]+[0-9]+/ { o = $0; sub(/^###[[:space:]]+Issue[[:space:]]+/, "", o); sub(/[^0-9].*$/, "", o); print "Issue " o }' "$PLAN")
            fi
            if [ -n "$ids" ]; then
                printf '\n## Work Items\n\n'
                printf '%s\n' "$ids" | sed 's/^/- /'
            fi
        fi
        if [ "$MODE" = coordinated ] && [ "$EXIT" = full-run ]; then
            printf '\n## PR Index\n\nNo node PR is open yet; /execute opens one per PR node.\n\n'
            printf '## Merge Order\n\n```merge-order\n'
            printf '# Two-node merge-order DAG (PR nodes + non-PR gate nodes), one node per line.\n'
            printf '```\n'
        fi
    } >"$f"
    if [ "$MODE" = coordinated ] && [ "$EXIT" = full-run ]; then
        shirabe validate --coordination-body "$f" >&2 \
            || fail scope:pr-create "the coordination body fails shirabe validate --coordination-body"
    fi
}

BODY="$SCRATCH/body.md"
render_body "$BODY"

lookup() {
    URL=$(bash "$OWNED" --repo "$REPO" --head "$BRANCH" --state open --base "$DEFAULT" </dev/null)
    LRC=$?
}

lookup
case "$LRC" in
    0) ;;
    3) fail scope:pr-create "several owned open PRs on $BRANCH; refusing to pick one" ;;
    *) fail scope:pr-create "the owned-PR lookup failed (owned-pr.sh exit $LRC)" ;;
esac

if [ -n "$URL" ]; then
    [[ "$URL" =~ $RE_PR_URL ]] || fail scope:pr-create "owned-pr.sh printed a URL outside the pattern"
    GOT=$(body_intent "$URL") || fail scope:pr-create "the owned PR's body cannot be read"
    if [ "$GOT" != "$INTENT" ]; then
        gh pr edit "$URL" --body-file "$BODY" </dev/null >&2 \
            || fail scope:pr-create "gh pr edit --body-file failed"
    fi
else
    if [ "$DRAFT" -eq 1 ]; then
        gh pr create --repo "$REPO" --draft --head "$BRANCH" --base "$DEFAULT" \
            --title "$TITLE" --body-file "$BODY" </dev/null >&2 \
            || fail scope:pr-create "gh pr create failed"
    else
        gh pr create --repo "$REPO" --head "$BRANCH" --base "$DEFAULT" \
            --title "$TITLE" --body-file "$BODY" </dev/null >&2 \
            || fail scope:pr-create "gh pr create failed"
    fi
    lookup
    [ "$LRC" -eq 0 ] && [ -n "$URL" ] \
        || fail scope:pr-create "the created PR is not found as the one owned open PR on $BRANCH"
    [[ "$URL" =~ $RE_PR_URL ]] || fail scope:pr-create "owned-pr.sh printed a URL outside the pattern"
fi

printf 'pr=%s\n' "$URL"
exit 0
