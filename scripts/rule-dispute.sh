#!/usr/bin/env bash
# rule-dispute.sh -- record a dispute of a rule's finding at a koto gate.
#
# A gate script that fails on a block-stage finding prints one standard-error
# line (rf_dispute_hint in scripts/lib/rule-findings.sh) naming this script,
# with the same argument names as below. An agent that believes the finding is
# wrong runs it with the session and gate from the koto response it holds. The
# dispute is recorded, not obeyed: it changes no gate outcome, route or state,
# so it can't be used to get past a check. references/check-lifecycle.md says
# how disputes count toward a rule's stage.
#
# Usage:
#   rule-dispute.sh --session <name> --gate <gate> --rule <rule-id>
#                   --reason <text> [--state <state>] [--by agent|person]
#                   [--step <step-id>]
#
# The rule id must resolve through `scripts/rule-registry.sh ref` as an active
# registry entry, which keeps arbitrary strings out of the session's dispute
# records. Every argument is checked before koto runs, so a refusal records
# nothing.
#
# Where the dispute goes:
#   - When `koto disputes --help` succeeds, `koto disputes record` journals it
#     (a finding_disputed session event and a check_disputed journal record),
#     and the script prints `dispute=journaled`. --state and --by are passed
#     only when given; koto defaults them to the current state and agent.
#   - On an older koto, it is recorded as a decision in the run's record,
#     through scripts/run-trail.sh decision: its choice is `dispute:<rule-id>`,
#     its rationale `gate=<gate> state=<state, or current>: <reason>`, and who
#     disputed it is the record's actor, `agent:<session>` for --by agent (the
#     default) and `person` for --by person. run-trail.sh writes it as the
#     session's next `trail/decision/<n>.json`, against --step (the session
#     name, cut to a step id's 100 characters, when it isn't given), and sends the same choice and rationale
#     through `koto decisions record`. The script prints
#     `dispute=session-only`. It stays in the session and reaches no journal
#     figure.
#
# Each value reaches koto as its own argument word, never through a shell
# string, and the decision's JSON is built with `jq --arg`, so a reason holding
# quotes, `$()` or JSON reaches the record as typed. The flags go to
# `koto disputes record` in `--name=value` form so a reason that starts with
# `-` is still read as the value.
#
# Exit codes:
#   0    recorded; stdout is the one `dispute=` line
#   2    refused: a missing or empty required argument, an unknown argument,
#        --by other than agent or person, a session that starts with `-`, or a
#        rule id that isn't an active registry entry (or a registry that can't
#        be read)
#   127  jq is needed for the fallback and isn't installed
#   any other non-zero: on a koto with `koto disputes`, koto's own exit; on
#        the fallback, run-trail.sh's (65 a value it refuses, such as a step
#        id outside its pattern or a reason holding a token, 70 a koto call
#        that failed). Either is passed through, and nothing is printed on
#        stdout
#
# koto's own output goes to standard error, so stdout carries only the result.
#
# bash 3.2 floor: no associative arrays, no namerefs, no mapfile.

set -u

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
REGISTRY="$SCRIPT_DIR/rule-registry.sh"
# The fallback runs run-trail.sh under the bash running this script.
BASH_CMD=${BASH:-bash}
ME=rule-dispute.sh

usage_line='usage: rule-dispute.sh --session <name> --gate <gate> --rule <rule-id> --reason <text> [--state <state>] [--by agent|person] [--step <step-id>]'

refuse() {
    printf '%s: %s\n' "$ME" "$1" >&2
    printf '%s\n' "$usage_line" >&2
    exit 2
}

SESSION=""
GATE=""
RULE=""
REASON=""
STATE=""
BY=""
STEP=""
HAVE_STATE=0
HAVE_BY=0
HAVE_STEP=0

while [ $# -gt 0 ]; do
    case "$1" in
        --session|--gate|--rule|--reason|--state|--by|--step)
            [ $# -ge 2 ] || refuse "$1 needs a value"
            case "$1" in
                --session) SESSION=$2 ;;
                --gate) GATE=$2 ;;
                --rule) RULE=$2 ;;
                --reason) REASON=$2 ;;
                --state) STATE=$2; HAVE_STATE=1 ;;
                --by) BY=$2; HAVE_BY=1 ;;
                --step) STEP=$2; HAVE_STEP=1 ;;
            esac
            shift 2
            ;;
        *)
            refuse "unknown argument: $1"
            ;;
    esac
done

[ -n "$SESSION" ] || refuse "--session is required"
[ -n "$GATE" ] || refuse "--gate is required"
[ -n "$RULE" ] || refuse "--rule is required"
[ -n "$REASON" ] || refuse "--reason is required"
if [ "$HAVE_STATE" -eq 1 ] && [ -z "$STATE" ]; then
    refuse "--state, when given, can't be empty"
fi
if [ "$HAVE_STEP" -eq 1 ] && [ -z "$STEP" ]; then
    refuse "--step, when given, can't be empty"
fi
case "$SESSION" in
    -*) refuse "a session name can't start with '-': $SESSION" ;;
esac
if [ "$HAVE_BY" -eq 1 ]; then
    case "$BY" in
        agent|person) ;;
        *) refuse "--by must be agent or person, not: $BY" ;;
    esac
fi

# An active entry is one `ref` prints: it exits 1 for no entry and for a
# retired one, and 2 when it can't decide. Either way the id is refused.
if ! "$REGISTRY" ref "$RULE" >/dev/null 2>&1; then
    refuse "rule $RULE is not an active entry in references/rule-registry.json"
fi

if koto disputes --help >/dev/null 2>&1; then
    set -- disputes record "$SESSION" "--gate=$GATE" "--rule=$RULE" "--reason=$REASON"
    [ "$HAVE_STATE" -eq 1 ] && set -- "$@" "--state=$STATE"
    [ "$HAVE_BY" -eq 1 ] && set -- "$@" "--by=$BY"
    koto "$@" >&2
    RC=$?
    [ "$RC" -eq 0 ] || exit "$RC"
    printf 'dispute=journaled\n'
    exit 0
fi

command -v jq >/dev/null 2>&1 || {
    printf '%s: jq is required to record a dispute on a koto without `koto disputes`\n' "$ME" >&2
    exit 127
}

DATA=$(jq -cn \
    --arg choice "dispute:$RULE" \
    --arg rationale "gate=$GATE state=${STATE:-current}: $REASON" \
    '{choice: $choice, rationale: $rationale}') || {
    printf '%s: could not build the decision record\n' "$ME" >&2
    exit 2
}

case "${BY:-agent}" in
    person) ACTOR=person ;;
    *) ACTOR="agent:$SESSION" ;;
esac
# The document reaches run-trail.sh on stdin only, never as an argument.
# Without --step the session name stands in, cut to the step id's 100
# characters.
printf '%s' "$DATA" | "$BASH_CMD" "$SCRIPT_DIR/run-trail.sh" decision --session "$SESSION" \
    --step "${STEP:-${SESSION:0:100}}" --actor "$ACTOR" >&2
RC=$?
[ "$RC" -eq 0 ] || exit "$RC"
printf 'dispute=session-only\n'
exit 0
