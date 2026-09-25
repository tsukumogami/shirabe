#!/usr/bin/env bash
# record-merge-verdict.sh — for /execute: find the owned PR, compute the merge
# verdict, and record it in the koto session's context.
#
# This is the default action of `merge_readiness` (and, with --confirm, of
# `merge_confirm` and the coordinated envelope's confirm read). It exists
# because a koto command gate exposes only an exit code, and merge-verdict.sh
# exits 0 for every verdict: the decision is in what it prints. So the verdict
# reaches routing the one way koto allows, through `koto context add` in a
# default action, and the states route on non-overridable `context-matches`
# gates over the keys written here.
#
# It reads GitHub and writes koto context, and nothing else: it pushes nothing,
# merges nothing, and writes nothing to GitHub.
#
# Usage:
#   record-merge-verdict.sh --repo <owner/repo> --head-branch <branch>
#                           [--merge true|false] [--confirm]
#                           [--session <koto-session>]
#
#   --repo         a single ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$, neither half `.`
#                  or `..`. Never the comma-joined `repos` write set, and this
#                  script never reads the `repos` context key: the caller reads
#                  whatever it records and passes one repository here.
#   --head-branch  ^[A-Za-z0-9._/-]+$, no `..`, no leading `-` or `/`
#   --merge        this invocation's merge intent, the session's MERGE
#                  variable (`{{MERGE}}` in the template). Default false.
#   --confirm      confirm mode (below)
#   --session      the koto session to read and write; default
#                  $KOTO_TICK_SESSION, which koto sets for every command it
#                  runs. ^[A-Za-z0-9][A-Za-z0-9._-]*$
#
# koto substitutes declared variables into a default_action command but never
# context keys, so the template passes the repository and branch by reading
# them inside the command (`--repo "$(koto context get <session> repos)"`).
# Both are explicit arguments here in both modes.
#
# Verdict mode (no --confirm), in order:
#   1. clear merge_verdict, home_pr, reason, step, and waiting, so an action
#      that fails or times out part-way leaves no value from an earlier entry
#      for the gates to read as current;
#   2. read expected_head from context; anything but a 40-character sha is
#      passed on as `none`, which makes merge-verdict.sh's row 8 fire;
#   3. resolve the PR with `owned-pr.sh --state all` (so a PR that already
#      merged is still found) on --repo and --head-branch. Several owned PRs, or
#      none, record step `execute:pr-adopt`; a failed read records
#      `execute:status-read`; each with the matching `error:execute:<step>`
#      verdict;
#   4. run merge-verdict.sh on that PR with --merge and the expected head;
#   5. check the printed line against merge-verdict.sh's verdict grammar, and
#      derive `reason` (the condition after `awaiting:` or `not-merged:`,
#      checked against the decision table's closed condition set) or `step`
#      (the `execute:<step>` of an `error:` verdict, checked against
#      ^execute:(pr-closed|ready|ci|ci-timeout|status-read)$);
#   6. only when every check passed, write home_pr (the owned PR's URL),
#      waiting (`<url>:human` unless the verdict is `merged`), reason or step,
#      and merge_verdict last, with `koto context add`.
#   A verdict or derived value that fails its pattern writes nothing.
#
# Confirm mode (--confirm): clear confirm_verdict, re-resolve the PR the same
# way (never from agent evidence), run `merge-verdict.sh --confirm` on it, and
# write confirm_verdict only when the line matches
# ^(merged|not-merged:merge-not-observed)$. Nothing else is read or written.
#
# Exit codes:
#   0   recorded (in verdict mode this includes the lookup failures of step 3,
#       which are recorded as error verdicts)
#   1   merge-verdict.sh failed, printed something outside its grammar, or a
#       derived value failed its pattern; or, in confirm mode, the lookup
#       failed. Nothing was written after the clear.
#   64  usage error: a missing or invalid argument or session. Nothing was
#       read or written, and no gh or koto call was made.
#   70  a koto context read, clear, or write failed
#
# Environment: EXECUTE_CI_WAIT_LIMIT_SECS and MERGE_CONFIRM_WAIT_SECS reach
# merge-verdict.sh unchanged.
#
# Requires: bash 3.2+, jq (through owned-pr.sh), gh, koto.
set -uo pipefail

PROG=record-merge-verdict

RE_REPO='^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$'
RE_BRANCH='^[A-Za-z0-9._/-]+$'
RE_SESSION='^[A-Za-z0-9][A-Za-z0-9._-]*$'
RE_SHA='^[0-9a-f]{40}$'
RE_URL='^https://[A-Za-z0-9.-]+/[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+/pull/[1-9][0-9]*$'

# merge-verdict.sh's grammar (its header is the source; its tests hold every
# verdict it prints to this list).
RE_V_MERGED='^merged$'
RE_V_PENDING='^pending:(checks|merge-state)$'
RE_V_MERGEABLE='^mergeable:(squash|merge|rebase):[0-9a-f]{40}$'
RE_V_AWAITING='^awaiting:(merge-not-requested|head-moved|no-checks|base-unprotected|review|workflow-change|merge-method-unresolved)$'
RE_V_AWAITING_STATE='^awaiting:merge-state:[A-Z_]+(:review=(REVIEW_REQUIRED|CHANGES_REQUESTED))?$'
RE_V_ERROR='^error:execute:(pr-closed|ready|ci|ci-timeout|status-read)$'
RE_V_NOT_MERGED='^not-merged:(merge-call-failed|merge-not-observed)$'

# The decision table's closed condition set, and the verdict steps.
RE_REASON='^(merge-not-requested|head-moved|no-checks|base-unprotected|review|workflow-change|merge-method-unresolved|merge-state:[A-Z_]+(:review=(REVIEW_REQUIRED|CHANGES_REQUESTED))?|merge-call-failed|merge-not-observed)$'
RE_STEP='^execute:(pr-closed|ready|ci|ci-timeout|status-read)$'
RE_CONFIRM='^(merged|not-merged:merge-not-observed)$'

usage_error() {
    echo "$PROG: $*" >&2
    echo "usage: record-merge-verdict.sh --repo <owner/repo> --head-branch <branch> [--merge true|false] [--confirm] [--session <koto-session>]" >&2
    exit 64
}

valid_branch() {
    [[ $1 =~ $RE_BRANCH ]] || return 1
    case "$1" in -*|/*|*..*|*/) return 1 ;; esac
    return 0
}

REPO=""; BRANCH=""; MERGE="false"; CONFIRM=0; SESSION=""
SEEN=" "
while [ $# -gt 0 ]; do
    case "$1" in
        --repo|--head-branch|--merge|--session)
            [ $# -ge 2 ] || usage_error "$1 needs a value"
            case "$SEEN" in *" $1 "*) usage_error "$1 given more than once" ;; esac
            SEEN="$SEEN$1 "
            case "$1" in
                --repo) REPO="$2" ;;
                --head-branch) BRANCH="$2" ;;
                --merge) MERGE="$2" ;;
                --session) SESSION="$2" ;;
            esac
            shift 2
            ;;
        --confirm)
            case "$SEEN" in *" --confirm "*) usage_error "--confirm given more than once" ;; esac
            SEEN="$SEEN--confirm "
            CONFIRM=1
            shift
            ;;
        *) usage_error "unexpected argument [$1]" ;;
    esac
done

case "$SEEN" in *" --repo "*) ;; *) usage_error "--repo is required" ;; esac
case "$SEEN" in *" --head-branch "*) ;; *) usage_error "--head-branch is required" ;; esac
[[ $REPO =~ $RE_REPO ]] || usage_error "--repo [$REPO] is not a single owner/repo"
case "/$REPO/" in */./*|*/../*) usage_error "--repo [$REPO] names a dot path segment" ;; esac
valid_branch "$BRANCH" || usage_error "--head-branch [$BRANCH] is not an allowed branch name"
case "$MERGE" in true|false) ;; *) usage_error "--merge must be true or false, got [$MERGE]" ;; esac
case "$SEEN" in *" --session "*) ;; *) SESSION="${KOTO_TICK_SESSION:-}" ;; esac
[ -n "$SESSION" ] || usage_error "no --session and KOTO_TICK_SESSION is not set"
[[ $SESSION =~ $RE_SESSION ]] || usage_error "session [$SESSION] is not a koto session name"

SELF_DIR=$(CDPATH='' cd "$(dirname "${BASH_SOURCE[0]}")" && pwd) || {
    echo "$PROG: cannot locate this script's directory" >&2
    exit 1
}
OWNED="$SELF_DIR/owned-pr.sh"
VERDICT_SCRIPT="$SELF_DIR/merge-verdict.sh"

ctx_clear() {
    local k
    for k in "$@"; do
        koto context remove "$SESSION" "$k" >/dev/null || {
            echo "$PROG: could not clear context key $k in session $SESSION" >&2
            exit 70
        }
    done
}

ctx_write() { # ctx_write <key> <value>
    printf '%s' "$2" | koto context add "$SESSION" "$1" >/dev/null || {
        echo "$PROG: could not write context key $1 in session $SESSION" >&2
        exit 70
    }
}

# The recorded expected head, or `none`. A missing key is the ordinary "no
# record" case, not a failure.
EXPECTED=$(koto context get "$SESSION" expected_head) || EXPECTED=""
[[ $EXPECTED =~ $RE_SHA ]] || EXPECTED="none"

if [ "$CONFIRM" -eq 1 ]; then
    ctx_clear confirm_verdict
else
    ctx_clear merge_verdict home_pr reason step waiting
fi

# Resolve the owned PR. Run by this interpreter from this directory, never from
# PATH.
URL=$("$BASH" "$OWNED" --repo "$REPO" --head "$BRANCH" --state all </dev/null)
LOOKUP_RC=$?

lookup_failed() { # lookup_failed <step>
    if [ "$CONFIRM" -eq 1 ]; then
        echo "$PROG: no single owned PR on $REPO head $BRANCH to confirm ($1); confirm_verdict not written" >&2
        exit 1
    fi
    ctx_write step "execute:$1"
    ctx_write merge_verdict "error:execute:$1"
    echo "$PROG: recorded error:execute:$1 for $REPO head $BRANCH" >&2
    exit 0
}

case "$LOOKUP_RC" in
    0) [ -n "$URL" ] || lookup_failed pr-adopt ;;
    2) lookup_failed status-read ;;
    3) lookup_failed pr-adopt ;;
    *)
        echo "$PROG: owned-pr.sh exited $LOOKUP_RC" >&2
        exit 1
        ;;
esac
if ! [[ $URL =~ $RE_URL ]]; then
    echo "$PROG: owned-pr.sh printed [$URL], not one pull request URL" >&2
    exit 1
fi
PR_NUMBER=${URL##*/}

if [ "$CONFIRM" -eq 1 ]; then
    LINE=$("$BASH" "$VERDICT_SCRIPT" --repo "$REPO" --pr "$PR_NUMBER" --merge "$MERGE" \
        --expected-head "$EXPECTED" --confirm </dev/null)
    RC=$?
    if [ "$RC" -ne 0 ]; then
        echo "$PROG: merge-verdict.sh --confirm exited $RC; confirm_verdict not written" >&2
        exit 1
    fi
    if ! [[ $LINE =~ $RE_CONFIRM ]]; then
        echo "$PROG: merge-verdict.sh --confirm printed [$LINE], outside ^(merged|not-merged:merge-not-observed)\$" >&2
        exit 1
    fi
    ctx_write confirm_verdict "$LINE"
    exit 0
fi

LINE=$("$BASH" "$VERDICT_SCRIPT" --repo "$REPO" --pr "$PR_NUMBER" --merge "$MERGE" \
    --expected-head "$EXPECTED" </dev/null)
RC=$?
if [ "$RC" -ne 0 ]; then
    echo "$PROG: merge-verdict.sh exited $RC; nothing recorded" >&2
    exit 1
fi

REASON=""
STEP=""
if [[ $LINE =~ $RE_V_MERGED ]] || [[ $LINE =~ $RE_V_PENDING ]] || [[ $LINE =~ $RE_V_MERGEABLE ]]; then
    :
elif [[ $LINE =~ $RE_V_AWAITING ]] || [[ $LINE =~ $RE_V_AWAITING_STATE ]]; then
    REASON=${LINE#awaiting:}
elif [[ $LINE =~ $RE_V_NOT_MERGED ]]; then
    REASON=${LINE#not-merged:}
elif [[ $LINE =~ $RE_V_ERROR ]]; then
    STEP=${LINE#error:}
else
    echo "$PROG: merge-verdict.sh printed [$LINE], outside its verdict grammar; nothing recorded" >&2
    exit 1
fi
if [ -n "$REASON" ] && ! [[ $REASON =~ $RE_REASON ]]; then
    echo "$PROG: condition [$REASON] is outside the closed condition set; nothing recorded" >&2
    exit 1
fi
if [ -n "$STEP" ] && ! [[ $STEP =~ $RE_STEP ]]; then
    echo "$PROG: step [$STEP] is outside the verdict steps; nothing recorded" >&2
    exit 1
fi

ctx_write home_pr "$URL"
if [ "$LINE" != "merged" ]; then
    ctx_write waiting "$URL:human"
fi
[ -n "$REASON" ] && ctx_write reason "$REASON"
[ -n "$STEP" ] && ctx_write step "$STEP"
# Last, so a gate never sees a verdict whose companion keys are missing.
ctx_write merge_verdict "$LINE"
exit 0
