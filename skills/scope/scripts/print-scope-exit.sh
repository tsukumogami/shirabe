#!/usr/bin/env bash
# print-scope-exit.sh -- /scope's printed exit block, rendered from the
# terminal result.
#
# Every /scope run ends at a terminal whose `result:` map koto resolved (see
# skills/scope/koto-templates/scope.md). This script reads that result and
# prints the block; the agent composes no exit line (R31). The block is the
# human-facing contract, asserted by evals; parents read the result itself.
#
#   /scope finished: exit=<exit>; artifact=<path>
#   intent=<continue|stop|none>                   always
#   outcome=<scoped|handed-off-multi-pr|executed|error>
#                                                 full-run, executed, or error
#   step=<step>                                   error only
#   next=<command>                                full-run (and a refusal that
#                                                 names where to go instead)
#   pr=<url>                                      intent runs only
#   pr_state=<merged|open>                        executed only
#   wip_paths=<comma-separated paths>             when set
#   #<N> <title>                                  multi-pr startable items,
#   <one closing line>                            then one closing line
#
# Re-evaluation, abandonment and cancel print today's exit record with no
# outcome= line. A refusal prints today's refusal text, then intent=,
# outcome=error and step=scope:refused. `refused` is a result-payload value and
# is never printed after outcome=.
#
# Every value is checked against a closed pattern and dropped when it fails, so
# a result can carry no control character or prose into the report. The pr=
# URL must match ^https://github\.com/<owner>/<repo>/pull/<n>$.
#
# Usage:
#   print-scope-exit.sh --topic <slug> (--session <name> | --result-file <file>)
#
#   --session      reads `koto status <name>`
#   --result-file  a `koto next` or `koto status` JSON response
#
# The artifact path of a re-evaluation (the Decision Record) and an
# abandonment (the file carrying the abandonment marker) is read from the tree
# in the working directory, composed from the validated slug.
#
# Exit codes: 0 printed; 1 the result could not be read, or the session is not
# at a /scope terminal; 64 usage. Requires: bash 3.2+, jq; koto with --session.
set -uo pipefail

PROG=print-scope-exit

RE_TOPIC='^[a-z0-9][a-z0-9-]*$'
RE_PR_URL='^https://github\.com/[A-Za-z0-9._-]+/[A-Za-z0-9._-]+/pull/[1-9][0-9]*$'

usage() {
    printf '%s: %s\n' "$PROG" "$1" >&2
    printf 'usage: print-scope-exit.sh --topic <slug> (--session <name> | --result-file <file>)\n' >&2
    exit 64
}

TOPIC=""; SESSION=""; FILE=""
SEEN=" "
while [ "$#" -gt 0 ]; do
    case "$1" in
        --topic|--session|--result-file)
            [ "$#" -ge 2 ] || usage "$1 needs a value"
            case "$SEEN" in *" $1 "*) usage "$1 given more than once" ;; esac
            SEEN="$SEEN$1 "
            case "$1" in
                --topic) TOPIC="$2" ;;
                --session) SESSION="$2" ;;
                --result-file) FILE="$2" ;;
            esac
            shift ;;
        *) usage "unknown argument: $1" ;;
    esac
    shift
done
[[ "$TOPIC" =~ $RE_TOPIC ]] || usage "--topic [$TOPIC] does not match $RE_TOPIC"
if [ -n "$SESSION" ] && [ -n "$FILE" ]; then usage "give --session or --result-file, not both"; fi
if [ -z "$SESSION" ] && [ -z "$FILE" ]; then usage "--session or --result-file is required"; fi

if [ -n "$SESSION" ]; then
    JSON=$(koto status "$SESSION") || { echo "$PROG: koto status $SESSION failed" >&2; exit 1; }
else
    [ -f "$FILE" ] && [ -r "$FILE" ] || { echo "$PROG: cannot read $FILE" >&2; exit 1; }
    JSON=$(cat "$FILE")
fi

STATE=$(printf '%s' "$JSON" | jq -r '(.current_state // .state // "") | strings') \
    || { echo "$PROG: the result is not JSON" >&2; exit 1; }
PAYLOAD=$(printf '%s' "$JSON" | jq -c '.result.payload // {} | if type == "object" then . else {} end') || PAYLOAD='{}'

# get <key> <pattern> -- the payload's string value, or empty when it is
# absent, not a string, or outside the pattern.
get() {
    local v
    v=$(printf '%s' "$PAYLOAD" | jq -r --arg k "$1" '.[$k] // "" | strings') || v=""
    if [ -n "$v" ] && printf '%s' "$v" | LC_ALL=C grep -q '[[:cntrl:]]'; then v=""; fi
    if [ -n "$v" ] && [[ "$v" =~ $2 ]]; then printf '%s' "$v"; fi
}

OUTCOME=$(get outcome '^(scoped|handed-off-multi-pr|executed|re-evaluation|abandonment|cancelled|refused|error)$')
EXITV=$(get exit '^(full-run|re-evaluation|abandonment-forced)$')
INTENT=$(get intent '^(continue|stop|none)$')
STEP=$(get step '^scope:(push|pr-create|intake|resume-probe|refused)$')
NEXT=$(get next "^(/execute docs/plans/PLAN-${TOPIC}\\.md|/work-on( #[1-9][0-9]*)?|/release ${TOPIC})\$")
PR=$(get pr "$RE_PR_URL")
PR_STATE=$(get pr_state '^(merged|open)$')
PLAN_PATH=$(get plan_path "^docs/plans/PLAN-${TOPIC}\\.md\$")
MODE=$(get plan_execution_mode '^(single-pr|multi-pr|coordinated)$')
REASON=$(get reason '^(invalid-var:[A-Z_]+|duplicate-var:[A-Z_]+|var-mismatch:[A-Z_]+|template-mismatch|origin-mismatch|intent-mismatch|upstream-wip|upstream-untracked|upstream-outside|upstream-basename|plan-active|plan-done)$')
RECORDED=$(get recorded '^(continue|stop|none)$')
REQUESTED=$(get requested '^(continue|stop)$')
BOUNDARY=$(get boundary '^(prd|design)$')

# wip_paths: each comma-separated entry a plain wip/ path, else dropped whole.
WIP=$(printf '%s' "$PAYLOAD" | jq -r '.wip_paths // "" | strings') || WIP=""
if [ -n "$WIP" ]; then
    printf '%s\n' "$WIP" | tr ',' '\n' | grep -Evq '^wip/[A-Za-z0-9._/-]+$' && WIP=""
    case "$WIP" in *..*|*[[:cntrl:]]*) WIP="" ;; esac
fi

# startable: `#<N> <title>` lines, each dropped when it holds anything else.
STARTABLE=$(printf '%s' "$PAYLOAD" | jq -r '.startable // "" | strings' \
    | LC_ALL=C grep -E '^#[1-9][0-9]* [^[:cntrl:]]+$' || true)

case "$STATE" in
    done_full_run|done_republished|done_executed|done_re_evaluation|done_abandonment|done_cancelled|done_refused|done_error) ;;
    *) echo "$PROG: [$STATE] is not a /scope terminal" >&2; exit 1 ;;
esac

decision_record() {
    local b p last=""
    for b in ${BOUNDARY:-prd design}; do
        for p in docs/decisions/DECISION-"$b"-"$TOPIC"-*.md; do
            [ -f "$p" ] && last="$p"
        done
    done
    printf '%s' "$last"
}
forced_artifact() {
    local p
    for p in "docs/plans/PLAN-${TOPIC}.md" "docs/designs/current/DESIGN-${TOPIC}.md" \
             "docs/designs/DESIGN-${TOPIC}.md" "docs/prds/PRD-${TOPIC}.md" "docs/briefs/BRIEF-${TOPIC}.md"; do
        if [ -f "$p" ] && grep -qF -- "scope-status-block: abandonment-forced" "$p"; then
            printf '%s' "$p"; return
        fi
    done
}

finished() { # finished <exit> <artifact>
    printf '/scope finished: exit=%s; artifact=%s\n' "$1" "${2:-none}"
}
line() { [ -n "$2" ] && printf '%s=%s\n' "$1" "$2"; return 0; }

intent_line() { printf 'intent=%s\n' "${INTENT:-none}"; }
pr_line() { [ "${INTENT:-none}" != none ] && line pr "$PR"; return 0; }

refusal_text() {
    case "$REASON" in
        plan-active)
            printf '/scope cannot resume against a PLAN already under implementation; redirect to %s\n' "${NEXT:-/work-on}" ;;
        plan-done)
            printf '/scope cannot resume against a completed PLAN; redirect to /release %s\n' "$TOPIC" ;;
        intent-mismatch)
            printf '/scope refused: this topic'"'"'s unfinished run recorded intent=%s, and this invocation asked for --intent=%s. Re-invoke with --intent=%s, or with no --intent to resume under the recorded intent.\n' \
                "${RECORDED:-?}" "${REQUESTED:-?}" "${RECORDED:-?}" ;;
        upstream-wip)
            printf '/scope refused: --upstream resolves under wip/; an upstream must be a durable ROADMAP under docs/roadmaps/.\n' ;;
        upstream-untracked)
            printf '/scope refused: --upstream names a file git does not track; commit the ROADMAP or name one that is tracked.\n' ;;
        upstream-outside)
            printf '/scope refused: --upstream resolves outside docs/roadmaps/ once symlinks are followed.\n' ;;
        upstream-basename)
            printf '/scope refused: --upstream must name a file whose basename starts with ROADMAP-.\n' ;;
        *)
            printf '/scope refused the invocation%s.\n' "${REASON:+ ($REASON)}" ;;
    esac
}

closing_line() {
    if [ "${INTENT:-none}" != none ] && [ -n "$PR" ]; then
        printf 'These items can start once the scoping PR %s merges.\n' "$PR"
    else
        printf 'These items can start once the PLAN is on the default branch.\n'
    fi
}

case "$STATE" in
    done_full_run|done_republished)
        finished "${EXITV:-full-run}" "${PLAN_PATH:-docs/plans/PLAN-${TOPIC}.md}"
        intent_line
        line outcome "$OUTCOME"
        line next "$NEXT"
        pr_line
        line wip_paths "$WIP"
        if [ "$OUTCOME" = handed-off-multi-pr ] || [ "$MODE" = multi-pr ]; then
            if [ -n "$STARTABLE" ]; then
                printf '%s\n' "$STARTABLE"
                closing_line
            fi
        fi
        ;;
    done_executed)
        finished executed "docs/designs/current/DESIGN-${TOPIC}.md"
        intent_line
        line outcome "$OUTCOME"
        pr_line
        line pr_state "$PR_STATE"
        ;;
    done_re_evaluation)
        finished re-evaluation "$(decision_record)"
        intent_line
        pr_line
        line wip_paths "$WIP"
        ;;
    done_abandonment)
        finished abandonment-forced "$(forced_artifact)"
        intent_line
        pr_line
        line wip_paths "$WIP"
        ;;
    done_cancelled)
        printf '/scope cancelled: no exit was recorded and nothing was force-materialized\n'
        intent_line
        ;;
    done_refused)
        refusal_text
        intent_line
        printf 'outcome=error\n'
        printf 'step=scope:refused\n'
        line next "$NEXT"
        ;;
    done_error)
        if [ -n "$EXITV" ]; then
            case "$EXITV" in
                full-run) finished full-run "${PLAN_PATH:-docs/plans/PLAN-${TOPIC}.md}" ;;
                re-evaluation) finished re-evaluation "$(decision_record)" ;;
                abandonment-forced) finished abandonment-forced "$(forced_artifact)" ;;
            esac
        else
            printf '/scope stopped before recording an exit\n'
        fi
        intent_line
        printf 'outcome=error\n'
        line step "$STEP"
        line wip_paths "$WIP"
        ;;
esac
exit 0
