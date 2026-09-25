#!/usr/bin/env bash
# deliver-probe.sh -- /deliver's durable re-checks, run as default actions.
#
# A child's result never moves a /deliver run forward on its own. Before each
# next step the run re-reads durable state -- the PLAN, the owned pull
# request, GitHub -- through this script. It runs as a default action because
# a koto command gate exposes only an exit code, and each re-check has to
# carry the PR it verified into the run's result. So it clears its keys, runs
# the check, and writes a verdict and that PR with `koto context add`; the
# state routes on non-overridable context-matches gates over those keys.
#
# The PR is always found here, through the shared ownership filter
# skills/execute/scripts/owned-pr.sh (same repository, the authenticated
# author, the expected base, the head branch), and never taken from a leg: the
# PR it finds is written both as `checked_pr` and as the result key `pr`,
# replacing whatever a leg copied. A lookup that fails leaves both empty.
#
# The head branch is the checked-out branch: the topic branch /scope
# published. On a /deliver run /execute adopts that branch's PR for a
# single-pr PLAN (no impl/<slug> branch is cut), and a coordinated PLAN's
# coordination PR is the same branch's PR, so every mode finds its PR there.
#
# Modes and the context keys each owns (cleared first, the verdict written
# last):
#
#   scoped    scoped_verdict (pass|fail), checked_pr, pr
#             pass needs all of: docs/plans/PLAN-<topic>.md tracked by git and
#             unchanged against HEAD; skills/scope/scripts/publish-scoping-pr.sh
#             --verify --expect-intent continue (the branch pushed at HEAD, one
#             owned open PR recording intent=continue); and owned-pr.sh
#             --state open finding that same PR.
#   executed  executed_verdict (merged|open|fail), checked_pr, pr, pr_state
#             merged or open needs: no PLAN on disk or at HEAD,
#             docs/designs/current/DESIGN-<topic>.md present, and owned-pr.sh
#             --state all finding one PR whose state `gh pr view` reads as
#             MERGED or OPEN.
#   merged    merged_verdict (merged|not-merged), checked_pr, pr
#             owned-pr.sh --state all (a merged PR drops out of an open-only
#             lookup) finds the PR, then skills/execute/scripts/merge-verdict.sh
#             --confirm reads it live. The PR's URL is written whichever the
#             verdict; `merged` only when the confirm read printed `merged`.
#
# owned-pr.sh's codes map to a failing verdict (`fail`, or `not-merged` for
# `merged`) with no checked_pr or pr written: zero survivors (empty output,
# exit 0), several (exit 3), and a failed read (exit 2 or anything else).
#
# Usage:
#   deliver-probe.sh scoped|executed|merged --topic <slug> [--session <name>]
#
# The session is koto's $KOTO_TICK_SESSION when koto set it, else --session.
# The repository is `gh repo view --json nameWithOwner`.
#
# Output: `<mode>_verdict=<verdict>` and, when written, `pr=<url>` on stdout;
# the reason for a failing verdict on stderr.
#
# Exit codes:
#   0   a verdict was written (any verdict)
#   64  usage error; nothing read or written
#   66  a `koto context` call failed
#
# Environment:
#   MERGE_CONFIRM_WAIT_SECS  the confirm window merge-verdict.sh waits for a
#                            MERGED read; this script sets 5 when it is unset,
#                            because it re-reads a merge /execute already
#                            confirmed and a default action has 30 seconds.
#
# Read-only on GitHub and the working tree: its gh calls are `gh repo view`,
# owned-pr.sh's reads, `gh pr view`, and merge-verdict.sh --confirm's state
# read; its git calls read refs and the index. It writes only this run's own
# context keys. bash 3.2.
set -uo pipefail

PROG=deliver-probe
HERE=$(cd "$(dirname "$0")" && pwd)
PLUGIN=$(cd "$HERE/../../.." && pwd)
OWNED="$PLUGIN/skills/execute/scripts/owned-pr.sh"
VERDICT="$PLUGIN/skills/execute/scripts/merge-verdict.sh"
PUBLISH="$PLUGIN/skills/scope/scripts/publish-scoping-pr.sh"

RE_TOPIC='^[a-z0-9][a-z0-9-]*$'
RE_SESSION='^[A-Za-z0-9][A-Za-z0-9._-]*$'
RE_REPO='^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$'
RE_BRANCH='^[A-Za-z0-9._/-]+$'
RE_PR_URL='^https://github\.com/[A-Za-z0-9._-]+/[A-Za-z0-9._-]+/pull/[1-9][0-9]*$'

usage() {
    printf '%s: %s\n' "$PROG" "$1" >&2
    printf 'usage: deliver-probe.sh scoped|executed|merged --topic <slug> [--session <name>]\n' >&2
    exit 64
}

MODE="${1:-}"
case "$MODE" in
    scoped|executed|merged) shift ;;
    *) usage "the first argument must be scoped, executed, or merged" ;;
esac
TOPIC=""; SESSION_ARG=""; SEEN=" "
while [ "$#" -gt 0 ]; do
    case "$1" in
        --topic|--session)
            [ "$#" -ge 2 ] || usage "$1 needs a value"
            case "$SEEN" in *" $1 "*) usage "$1 given more than once" ;; esac
            SEEN="$SEEN$1 "
            case "$1" in
                --topic) TOPIC="$2" ;;
                --session) SESSION_ARG="$2" ;;
            esac
            shift ;;
        *) usage "unknown argument: $1" ;;
    esac
    shift
done
[[ "$TOPIC" =~ $RE_TOPIC ]] || usage "--topic [$TOPIC] does not match $RE_TOPIC"
SESSION="${KOTO_TICK_SESSION:-$SESSION_ARG}"
[[ "$SESSION" =~ $RE_SESSION ]] || usage "no usable session: --session is empty or invalid and KOTO_TICK_SESSION is unset"

ctx_remove() {
    koto context remove "$SESSION" "$1" >/dev/null && return 0
    printf '%s: koto context remove failed for %s\n' "$PROG" "$1" >&2
    exit 66
}
ctx_add() {
    printf '%s' "$2" | koto context add "$SESSION" "$1" >/dev/null && return 0
    printf '%s: koto context add failed for %s\n' "$PROG" "$1" >&2
    exit 66
}

# --- clear, so nothing an earlier tick or a leg wrote is read as current -----

case "$MODE" in
    scoped) KEYS="scoped_verdict checked_pr pr" ;;
    executed) KEYS="executed_verdict checked_pr pr pr_state" ;;
    merged) KEYS="merged_verdict checked_pr pr" ;;
esac
for k in $KEYS; do ctx_remove "$k"; done

# verdict <value> [<url>] [<state>] -- write the PR keys (when given), then the
# verdict last, and exit 0.
verdict() {
    if [ -n "${2:-}" ]; then
        ctx_add checked_pr "$2"
        ctx_add pr "$2"
    fi
    if [ -n "${3:-}" ]; then
        ctx_add pr_state "$3"
    fi
    ctx_add "${MODE}_verdict" "$1"
    printf '%s_verdict=%s\n' "$MODE" "$1"
    [ -n "${2:-}" ] && printf 'pr=%s\n' "$2"
    exit 0
}
FAILING=fail
[ "$MODE" = merged ] && FAILING=not-merged
failing() {
    printf '%s: %s\n' "$PROG" "$1" >&2
    verdict "$FAILING"
}

# --- shared reads -------------------------------------------------------------

BRANCH=$(git symbolic-ref --quiet --short HEAD) || BRANCH=""
[ -n "$BRANCH" ] || failing "HEAD is not on a named branch"
[[ "$BRANCH" =~ $RE_BRANCH ]] || failing "the branch name [$BRANCH] is outside the pattern"
TOP=$(git rev-parse --show-toplevel) || failing "not inside a git work tree"
cd "$TOP" || failing "cannot enter the work tree"

REPO=$(gh repo view --json nameWithOwner --jq .nameWithOwner </dev/null) || REPO=""
[[ "$REPO" =~ $RE_REPO ]] || failing "could not read the repository name"

# default_branch -- origin's HEAD symref, else what GitHub reports.
default_branch() {
    local d
    d=$(git ls-remote --symref origin HEAD | awk '$1 == "ref:" && $3 == "HEAD" { sub(/^refs\/heads\//, "", $2); print $2; exit }')
    if [ -z "$d" ]; then
        d=$(gh repo view --json defaultBranchRef --jq .defaultBranchRef.name </dev/null) || d=""
    fi
    printf '%s' "$d"
}

# lookup <open|all> [<base>] -- the one owned PR on BRANCH, or a failing
# verdict for zero, several, or a failed read. Sets URL.
URL=""
lookup() {
    local rc
    if [ -n "${2:-}" ]; then
        URL=$(bash "$OWNED" --repo "$REPO" --head "$BRANCH" --state "$1" --base "$2" </dev/null)
    else
        URL=$(bash "$OWNED" --repo "$REPO" --head "$BRANCH" --state "$1" </dev/null)
    fi
    rc=$?
    case "$rc" in
        0) ;;
        3) failing "several owned PRs on $BRANCH (owned-pr.sh exit 3)" ;;
        *) failing "the owned-PR lookup on $BRANCH failed (owned-pr.sh exit $rc)" ;;
    esac
    [ -n "$URL" ] || failing "no owned PR on $BRANCH"
    [[ "$URL" =~ $RE_PR_URL ]] || failing "owned-pr.sh printed a URL outside the pattern"
}

PLAN="docs/plans/PLAN-$TOPIC.md"
DESIGN_CURRENT="docs/designs/current/DESIGN-$TOPIC.md"

# --- the three re-checks --------------------------------------------------------

case "$MODE" in
scoped)
    git ls-files --error-unmatch -- "$PLAN" >/dev/null || failing "$PLAN is not tracked by git"
    git cat-file -e "HEAD:$PLAN" || failing "$PLAN is not in HEAD's tree"
    git diff --quiet HEAD -- "$PLAN" || failing "$PLAN differs from HEAD"
    VERIFIED=$(bash "$PUBLISH" --topic "$TOPIC" --verify --expect-intent continue </dev/null) \
        || failing "the scoping PR did not verify (publish-scoping-pr.sh --verify --expect-intent continue)"
    VERIFIED=$(printf '%s\n' "$VERIFIED" | sed -n 's/^pr=//p' | sed -n 1p)
    DEFAULT=$(default_branch)
    [[ "$DEFAULT" =~ $RE_BRANCH ]] || failing "the default branch cannot be read"
    lookup open "$DEFAULT"
    [ "$URL" = "$VERIFIED" ] || failing "the verified PR [$VERIFIED] is not the owned PR [$URL]"
    verdict pass "$URL"
    ;;
executed)
    [ ! -e "$PLAN" ] || failing "$PLAN still exists on disk"
    if git cat-file -e "HEAD:$PLAN"; then
        failing "$PLAN is still in HEAD's tree"
    fi
    [ -f "$DESIGN_CURRENT" ] || failing "$DESIGN_CURRENT does not exist"
    lookup all
    STATE=$(gh pr view "$URL" --json state --jq .state </dev/null) || STATE=""
    case "$STATE" in
        MERGED) verdict merged "$URL" merged ;;
        OPEN) verdict open "$URL" open ;;
        *) failing "the owned PR's state reads [$STATE], not MERGED or OPEN" ;;
    esac
    ;;
merged)
    lookup all
    NUMBER="${URL##*/}"
    LINE=$(MERGE_CONFIRM_WAIT_SECS="${MERGE_CONFIRM_WAIT_SECS:-5}" bash "$VERDICT" --repo "$REPO" --pr "$NUMBER" \
        --merge false --expected-head none --confirm </dev/null) || LINE=""
    case "$LINE" in
        merged) verdict merged "$URL" ;;
        *)
            printf '%s: the confirm read of %s printed [%s], not merged\n' "$PROG" "$URL" "$LINE" >&2
            verdict not-merged "$URL"
            ;;
    esac
    ;;
esac
