#!/usr/bin/env bash
# deliver-report.sh -- render /deliver's exit lines from its terminal result.
#
# The agent never composes /deliver's report. deliver.md's four terminals
# declare a `result:` map (outcome, step, reason, pr, pr_state, repos, resume,
# waiting, next, startable, execute_state), koto resolves it on the tick that lands
# in the terminal, and this script prints the human-facing lines from it.
#
# Much of that result came from a child's leg: /scope's and /execute's payload
# keys, copied into context. So every value is checked against a closed
# pattern first -- a PR URL, an `owner/repo` list, an enumerated outcome, step,
# and reason, a fixed command shape -- and anything that fails is dropped
# rather than printed. A leg cannot carry control characters or prose into the
# report.
#
# Usage:
#   deliver-report.sh [<file>]     read the JSON from <file>, or from stdin
#   deliver-report.sh --refused    deliver-open.sh's koto init refusal: no
#                                  session, no result
#
# The JSON may be `koto status` on the retained terminal, the terminal
# `koto next` response, or the bare result object; the payload is read from
# `.result.payload` or `.payload`.
#
# Output, one key=value per line, in this order:
#
#   outcome=<token>      always: merged, ready-awaiting-merge,
#                        paused-awaiting-merges, paused-for-review, scoped,
#                        handed-off-multi-pr, scope-ended-early, or error. A
#                        refusal (`refused` in the payload) prints error; an
#                        unreadable outcome prints error with
#                        step=deliver:child-outcome.
#   step=<step>          on error only (deliver:child-outcome when the result
#                        carries none that passes its pattern)
#   reason=<reason>      on error and scope-ended-early (which of
#                        re-evaluation, abandonment, cancelled); on a lost
#                        execute leg execute-leg-lost:<koto's code>, or
#                        execute-leg-lost:request_not_found when this host's
#                        request store doesn't hold the run's request
#   execute_state=<state>
#                        on error only, when the result names the execute
#                        session's state (a lost execute leg): its state, or
#                        absent, or unreadable
#   worktree_repo=<owner/repo>
#   other_repos=<owner/repo[,owner/repo...]>
#   message=<sentences>  on reason=worktree-isolated: the repository whose
#                        worktree the session is isolated in and the PLAN's
#                        other repositories, when the result names them
#                        (/deliver's own stop does; one /execute relayed
#                        doesn't), then a fixed message built from them that
#                        says what to do
#   repos=<owner/repo[,owner/repo...]>
#   pr=<url>             on merged, and on every outcome that names one PR
#   pr=<url> waiting=<human|predecessor> [reason=<condition>]
#                        on ready-awaiting-merge and paused-awaiting-merges,
#                        one line per unmerged PR; a result that names a PR
#                        but no waiting entry lists that PR as waiting on a
#                        human
#   pr_state=<merged|open>
#   resume=<command>     on paused-awaiting-merges and paused-for-review
#   next=<command>       on scoped and handed-off-multi-pr
#   #<N> <title>         on handed-off-multi-pr, each startable item
#
# What each outcome means:
#
#   merged                  every PR the PLAN needs reads MERGED on GitHub,
#                           coordination PR included, confirmed by /deliver's
#                           own live read
#   ready-awaiting-merge    the PRs are open and ready, and at least one is
#                           unmerged; each is listed with its waiting= value
#   paused-awaiting-merges  coordinated only: some PR can't start until a
#                           predecessor merges; resume= gives the command
#   paused-for-review       interactive only: /execute's review pause, with
#                           the home PR still draft
#   scoped                  the author declined the confirmation; next= is
#                           /deliver <topic>
#   handed-off-multi-pr     the PLAN is multi-pr, /execute was not started,
#                           and the startable items follow
#   scope-ended-early       /scope ended at re-evaluation, abandonment or a
#                           clean cancel; reason= names which
#   error                   a step failed; step= names it: /scope's and
#                           /execute's own steps, scope:refused (/scope's
#                           arguments or attach refused; a refused /execute is
#                           a lost leg, below), deliver:intent-mismatch,
#                           deliver:child-outcome (a result /deliver doesn't
#                           recognise, or a failed re-check),
#                           deliver:child-absent (a child returned without
#                           recording a result, or the execute leg was lost:
#                           refused, or its request missing from this host's
#                           store), deliver:request-abandoned
#                           (this run's request was abandoned under it),
#                           deliver:worktree-isolated (the session is
#                           isolated in one repository's worktree and the
#                           coordinated PLAN has nodes in others, so /execute
#                           was not started), or deliver:refused (koto
#                           refused this invocation's own arguments)
#
# Exit codes: 0 lines printed; 64 usage error; 65 the input is not JSON.
#
# Requires: bash 3.2+, jq.
set -uo pipefail

PROG=deliver-report

RE_OUTCOME='^(merged|ready-awaiting-merge|paused-awaiting-merges|paused-for-review|scoped|handed-off-multi-pr|scope-ended-early|error)$'
RE_STEP='^(scope:(push|pr-create|intake|resume-probe|refused)|execute:[a-z][a-z0-9_-]*|deliver:(intent-mismatch|child-outcome|child-absent|request-abandoned|refused|worktree-isolated))$'
RE_REASON='^(re-evaluation|abandonment|cancelled|intent-mismatch|upstream-(wip|untracked|outside|basename)|plan-active|plan-done|(invalid-var|duplicate-var|unknown-var|var-mismatch):[A-Z][A-Z0-9_]*|template-mismatch|origin-mismatch|input-mismatch|session-terminal|session-live|leg-[a-z]+(-[a-z]+)*|merge-not-requested|head-moved|no-checks|base-unprotected|review|workflow-change|merge-method-unresolved|merge-state:[A-Z_]+(:review=(REVIEW_REQUIRED|CHANGES_REQUESTED))?|merge-call-failed|merge-not-observed|predecessor-unmerged|gate-unverified|worktree-isolated|execute-leg-lost:[a-z][a-z0-9_-]*(:[A-Z][A-Z0-9_]*)?)$'
RE_REPO='^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$'
RE_REPO_LIST='^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+(,[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+)*$'
RE_URL='^https://github\.com/[A-Za-z0-9._-]+/[A-Za-z0-9._-]+/pull/[1-9][0-9]*$'
RE_ROLE='^(human|predecessor)$'
RE_PR_STATE='^(merged|open)$'
RE_RESUME='^/execute [A-Za-z0-9._/-]+\.md( --[a-z][a-z-]*)*$'
RE_EXECUTE_STATE='^[a-z][a-z0-9_]*$'
RE_NEXT='^(/deliver [a-z0-9][a-z0-9-]*|/execute docs/plans/PLAN-[a-z0-9][a-z0-9-]*\.md|/work-on( #[1-9][0-9]*)?|/release [a-z0-9][a-z0-9-]*)$'

if [ $# -gt 1 ]; then
    echo "usage: deliver-report.sh [--refused | <file>]" >&2
    exit 64
fi
if [ "${1:-}" = "--refused" ]; then
    printf 'outcome=error\n'
    printf 'step=deliver:refused\n'
    exit 0
fi
if [ $# -eq 1 ]; then
    [ -f "$1" ] || { echo "$PROG: no such file: $1" >&2; exit 64; }
    INPUT=$(cat -- "$1")
else
    INPUT=$(cat)
fi

command -v jq >/dev/null || { echo "$PROG: jq is not on PATH" >&2; exit 65; }
printf '%s' "$INPUT" | jq -e 'type == "object"' >/dev/null || {
    echo "$PROG: the input is not a JSON object" >&2
    exit 65
}

# field <name> -- a payload value as one line, or empty: a non-string, or a
# value holding a newline or any other control character, reads as empty, so
# it can never pass a pattern.
field() {
    printf '%s' "$INPUT" | jq -r --arg k "$1" '
        ((.result.payload // .payload // {}) | if type == "object" then .[$k] else null end) as $v
        | if ($v | type) == "string" and ($v | test("[[:cntrl:]]") | not) then $v else "" end'
}
# pattern <value> <regex> -- the value when it matches, else empty.
pattern() {
    if [[ $1 =~ $2 ]]; then printf '%s' "$1"; fi
}

OUTCOME=$(field outcome)
STEP=$(pattern "$(field step)" "$RE_STEP")
REASON=$(pattern "$(field reason)" "$RE_REASON")
PR=$(pattern "$(field pr)" "$RE_URL")
PR_STATE=$(pattern "$(field pr_state)" "$RE_PR_STATE")
REPOS=$(pattern "$(field repos)" "$RE_REPO_LIST")
RESUME=$(pattern "$(field resume)" "$RE_RESUME")
NEXT=$(pattern "$(field next)" "$RE_NEXT")
WAITING=$(field waiting)
EXECUTE_STATE=$(pattern "$(field execute_state)" "$RE_EXECUTE_STATE")
WORKTREE_REPO=$(pattern "$(field worktree_repo)" "$RE_REPO")
OTHER_REPOS=$(pattern "$(field other_repos)" "$RE_REPO_LIST")

# startable is several lines by design; each `#<N> <title>` line is kept on its
# own, and a line holding anything else is dropped.
STARTABLE=$(printf '%s' "$INPUT" | jq -r '(.result.payload // .payload // {}) | .startable // "" | strings' \
    | LC_ALL=C grep -E '^#[1-9][0-9]* [^[:cntrl:]]+$' || true)

if [ "$OUTCOME" = "refused" ]; then
    OUTCOME=error
    [ -n "$STEP" ] || STEP=deliver:refused
fi
if ! [[ $OUTCOME =~ $RE_OUTCOME ]]; then
    # A terminal whose result carries no readable outcome is reported as an
    # error the run could not read, never as a success.
    OUTCOME=error
    STEP=deliver:child-outcome
fi

printf 'outcome=%s\n' "$OUTCOME"
case "$OUTCOME" in
    error)
        printf 'step=%s\n' "${STEP:-deliver:child-outcome}"
        [ -n "$REASON" ] && printf 'reason=%s\n' "$REASON"
        [ -n "$EXECUTE_STATE" ] && printf 'execute_state=%s\n' "$EXECUTE_STATE"
        if [ "$REASON" = worktree-isolated ]; then
            # The message is fixed text around values that passed their
            # patterns, never prose read from the result.
            if [ -n "$WORKTREE_REPO" ] && [ -n "$OTHER_REPOS" ]; then
                printf 'worktree_repo=%s\n' "$WORKTREE_REPO"
                printf 'other_repos=%s\n' "$OTHER_REPOS"
                printf "message=Stopped before any node was cut: this session is isolated in a worktree of %s, and the PLAN also has nodes in %s. A session isolated in one repository's worktree can't run git in another repository's checkout, so run this again from a session that isn't isolated in one repository's worktree.\n" \
                    "$WORKTREE_REPO" "${OTHER_REPOS//,/, }"
            else
                printf "message=Stopped before any node was cut: this session is isolated in one repository's worktree, and the PLAN has nodes in other repositories. Run this again from a session that isn't isolated in one repository's worktree.\n"
            fi
        fi
        ;;
    scope-ended-early)
        case "$REASON" in
            re-evaluation|abandonment|cancelled) printf 'reason=%s\n' "$REASON" ;;
        esac
        ;;
esac

[ -n "$REPOS" ] && printf 'repos=%s\n' "$REPOS"

case "$OUTCOME" in
    ready-awaiting-merge|paused-awaiting-merges)
        # One entry per unmerged PR, `<url>:<role>` comma-joined. A URL carries
        # a colon, so each entry splits on its last one.
        printed=0
        rest="$WAITING"
        while [ -n "$rest" ]; do
            entry="${rest%%,*}"
            if [ "$entry" = "$rest" ]; then rest=""; else rest="${rest#*,}"; fi
            url="${entry%:*}"
            role="${entry##*:}"
            if [[ $url =~ $RE_URL ]] && [[ $role =~ $RE_ROLE ]]; then
                line="pr=$url waiting=$role"
                [ -n "$REASON" ] && line="$line reason=$REASON"
                printf '%s\n' "$line"
                printed=1
            fi
        done
        if [ "$printed" -eq 0 ] && [ -n "$PR" ]; then
            line="pr=$PR waiting=human"
            [ -n "$REASON" ] && line="$line reason=$REASON"
            printf '%s\n' "$line"
        fi
        ;;
    *)
        [ -n "$PR" ] && printf 'pr=%s\n' "$PR"
        ;;
esac

[ -n "$PR_STATE" ] && printf 'pr_state=%s\n' "$PR_STATE"

case "$OUTCOME" in
    paused-awaiting-merges|paused-for-review)
        [ -n "$RESUME" ] && printf 'resume=%s\n' "$RESUME"
        ;;
    scoped|handed-off-multi-pr)
        [ -n "$NEXT" ] && printf 'next=%s\n' "$NEXT"
        ;;
esac

if [ "$OUTCOME" = "handed-off-multi-pr" ] && [ -n "$STARTABLE" ]; then
    printf '%s\n' "$STARTABLE"
fi

exit 0
