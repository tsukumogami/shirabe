#!/usr/bin/env bash
# check-verification.sh -- what did the verification run for this head find?
# Part of the work-on skill
#
# The `verification` state's `poll:` gate. run-verification.sh --start starts
# the map's commands; this reads the result they leave on disk and exits with
# the verdict, or with koto's pending code while there is none yet.
#
#   --verdict --session <s> [--base-ref <ref>]
#   --record-deferral --session <s> [--base-ref <ref>]
#
# The result file's location, the head and the merge-base come from
# `run-verification.sh --locate`, so the two scripts can't disagree on them.
# A result computed against another merge-base is stale and reads as pending:
# the next --start replaces it.
#
# Exit status of --verdict:
#   75  no result for this head yet; the gate waits
#   0   every selected command ran and passed, or every cause found is of a
#       rule below the `block` stage
#   1   a command ran and failed, and either   verification/command-failed
#       passed at the merge-base while a clean
#       checkout of the head reproduced it, or
#       the result has no comparison
#   5   every failed command failed with the   verification/command-failed-
#       same exit status at the merge-base and preexisting
#       in a clean checkout of the head: the
#       failure predates the change
#   6   a failed command's comparison with the verification/baseline-
#       merge-base could not decide            undecidable
#   3   no map, or a map that selects nothing  verification/no-map
#       a map that does not parse              verification/bad-map
#   4   a command needs a person               verification/needs-person
#       a command timed out, or the run        verification/timed-out
#       passed its total budget
#       a command grew past max_procs          verification/runaway
#       a command could not start              verification/not-started
#       tracked files were dirty               verification/dirty-tree
#   2   the result could not be read, or recorded in koto context, or the
#       supervisor stopped before every command ran; the gate holds. No
#       finding; the reason goes to stderr.
#
# A supervisor that stopped early (a memory guard or a person killed it, or it
# could not run at all) writes a `supervisor-error` result. That result says
# nothing about the change, so it is not a verdict: reading it as a failure
# would end the run at a failure terminal over a killed process, with no moment
# to decide otherwise. The gate holds on it instead, records nothing, and says
# how to go on: move the result aside and tick to run the suite again, or
# submit `verification_status: blocked` to stop. The launcher keeps the result
# on disk until then, so a held tick never starts a new suite by itself.
#
# The ranking, highest first: 4, 3, 1, 6, 5, 0. Exit 4 outranks exit 1: when
# one result holds a failed command and one that timed out, the run stops for a
# person rather than going back to implementation, since the change was never
# fully verified. One failed command the change caused makes the verdict 1
# whatever the others showed at the merge-base; one undecidable command with
# no caused one makes it 6; only a result whose every failed command is
# pre-existing reads 5. The comparison itself is run-verification.sh's: the
# per-command `baseline` object it writes. A result without one, written
# before the comparison existed, reads a failed command as 1.
#
# Exit 5 is routed by koto on its own, with no evidence, into the
# `verification_preexisting` state. Exit 6 holds for the agent: the hold line
# on stderr names `verification_status: fix` (back to implementation),
# `verification_status: blocked` (stop), and the rerun path, moving the result
# aside and ticking, which runs the whole suite and its comparison again.
#
# --record-deferral is that state's action. It locates the result the same
# way, re-derives the verdict from it without printing findings or recording
# the result again, and refuses (exit 2) unless the verdict is 5. Then it
# writes the context key `verification_deferral`, one line naming the head,
# the merge-base and the pre-existing command ids, and exits 0. Any failure is
# 2, so the action stops the tick and the run doesn't move on without the
# record.
#
# Only a cause whose rule is at the `block` stage takes part in that ranking.
# Every cause prints its finding at its rule's stage (error at block, warning
# at warn, info at shadow, nothing at retired); the route is the highest exit
# among the causes printed at block, and 0 when there is none. So a timed-out
# command whose rule is at warn, beside a failed command whose rule is at
# block, routes to 1, not 4. A non-zero route also prints a line on stderr
# saying how to dispute a finding.
#
# Each violation prints one koto finding per cause:
#   ::koto-finding::{"rule_id":"verification/<rule>","level":"error",
#                    "message":"<summary>: ...","rule_ref":"<path>#L<a>-L<b>@<revision>"}
# the rules being entries of references/rule-registry.json, resolved through
# scripts/lib/rule-findings.sh before the result is read.
#
# A settled result (anything but 75 and 2) is also recorded in koto context
# under `verification_results.json`, for the audit trail. A gate command may
# write context; a failed write holds the gate (exit 2) rather than settling
# without the record.
#
# Written for the bash 3.2 floor, without `set -e`: an unexpected failure must
# not exit 1 and read as a failed command.

set -u

HERE=$(cd "$(dirname "$0")" && pwd)
RULE_IDS="verification/command-failed verification/command-failed-preexisting verification/baseline-undecidable verification/no-map verification/bad-map verification/needs-person verification/timed-out verification/runaway verification/not-started verification/dirty-tree"
RESULT_SCHEMA=shirabe-verification-result/v1

usage() {
    cat >&2 <<'EOF'
Usage: check-verification.sh --verdict --session <s> [--base-ref <ref>]
       check-verification.sh --record-deferral --session <s> [--base-ref <ref>]
EOF
}

undecided() {
    echo "check-verification: $*" >&2
    exit 2
}

# shellcheck source=../../../scripts/lib/rule-findings.sh
. "$HERE/../../../scripts/lib/rule-findings.sh" || undecided "cannot load scripts/lib/rule-findings.sh"

MODE=""
case "${1:-}" in
    --verdict) MODE=verdict ;;
    --record-deferral) MODE=record-deferral ;;
    *) usage; exit 2 ;;
esac
shift
SESSION=""
BASE_REF=""
while [ $# -gt 0 ]; do
    case "$1" in
        --session)
            [ $# -ge 2 ] && [ -z "$SESSION" ] || { usage; exit 2; }
            SESSION=$2; shift 2 ;;
        --base-ref)
            [ $# -ge 2 ] && [ -z "$BASE_REF" ] || { usage; exit 2; }
            BASE_REF=$2; shift 2 ;;
        *) usage; exit 2 ;;
    esac
done
[ -n "$SESSION" ] || { usage; exit 2; }

command -v jq >/dev/null || undecided "jq is not on PATH"
# Every cause the result can name, written out: rf_require checks each against
# RULE_IDS, and a cause the result names that isn't here holds at rf_finding.
rf_require verification/command-failed verification/command-failed-preexisting \
    verification/baseline-undecidable verification/no-map verification/bad-map \
    verification/needs-person verification/timed-out verification/runaway \
    verification/not-started verification/dirty-tree

if [ -n "$BASE_REF" ]; then
    LOC=$("$HERE/run-verification.sh" --locate --session "$SESSION" --base-ref "$BASE_REF") || exit 2
else
    LOC=$("$HERE/run-verification.sh" --locate --session "$SESSION") || exit 2
fi
HEAD_SHA=$(printf '%s\n' "$LOC" | sed -n 1p)
MB=$(printf '%s\n' "$LOC" | sed -n 2p)
RESULT=$(printf '%s\n' "$LOC" | sed -n 3p)

# pending: the gate waits; there is nothing for --record-deferral to record.
pending() {
    [ "$MODE" = verdict ] && exit 75
    undecided "there is no verification result for $HEAD_SHA at the merge-base $MB, so there is no deferral to record"
}

[ -e "$RESULT" ] || pending
[ -r "$RESULT" ] || undecided "the result $RESULT is not readable"
jq -e --arg schema "$RESULT_SCHEMA" '.schema == $schema and (.commands | type) == "array"' "$RESULT" >/dev/null \
    || undecided "the result $RESULT is not a $RESULT_SCHEMA object"
[ "$(jq -r .head "$RESULT")" = "$HEAD_SHA" ] || undecided "the result $RESULT is for another head"
[ "$(jq -r .merge_base "$RESULT")" = "$MB" ] || pending

# A stopped supervisor is no verdict (see the header): hold, record nothing.
if [ "$(jq -r .status "$RESULT")" = supervisor-error ]; then
    undecided "the verification run for $HEAD_SHA stopped before every command ran" \
        "($(jq -r '.commands | length' "$RESULT") finished), so there is no verdict to route on." \
        "The result is $RESULT. To run the suite again, move that file aside and tick;" \
        "to stop the run, submit verification_status: blocked with the reason in detail."
fi

JQ_ERR=$(mktemp "${TMPDIR:-/tmp}/check-verification.XXXXXX") || undecided "could not create a temporary file"
trap 'rm -f "$JQ_ERR"' EXIT

# The findings and the verdict, both from the result, in one jq program. Each
# line is `<exit>\t<rule>\t<message>`; the verdict is the highest-ranked exit
# among the lines whose finding printed at block.
LINES=$(jq -r '
    def argv: (.argv // []) | join(" ");
    def logpart: if .log then " (log: \(.log))" else "" end;
    if .status == "done" or .status == "timed-out" then
        (.commands[]
         | if .not_started then "4\tnot-started\tcommand \(.id) did not start: [\(.argv[0])] is not an executable program\(logpart)"
           elif .runaway then "4\trunaway\tcommand \(.id) [\(argv)] grew past its max_procs and was killed\(logpart)"
           elif .timed_out then "4\ttimed-out\tcommand \(.id) [\(argv)] ran past its timeout_secs or the total run budget and was killed\(logpart)"
           elif .exit_status != 0 then
               (.baseline // null) as $bl
               | ($bl.verdict // null) as $v
               | "command \(.id) [\(argv)] exited \(.exit_status)" as $failed
               | if $bl == null then "1\tcommand-failed\t\($failed)\(logpart)"
                 elif $v == "caused" then "1\tcommand-failed\t\($failed); compared with the merge-base \($bl.merge_base.commit // ""): \($bl.reason)\(logpart)"
                 elif $v == "preexisting" then "5\tcommand-failed-preexisting\t\($failed), and fails the same way at the merge-base \($bl.merge_base.commit // ""): \($bl.reason)\(logpart)"
                 elif $v == "undecidable" then "6\tbaseline-undecidable\t\($failed), and the comparison with the merge-base could not decide whether the change caused it: \($bl.reason)\(logpart)"
                 else "2\t\tcommand \(.id) has a baseline verdict this script does not know: \($v)" end
           else empty end),
        (if .status == "timed-out" then "4\ttimed-out\t\(.detail)" else empty end)
    elif .status == "no-map" then "3\tno-map\t\(.detail)"
    elif .status == "bad-map" then "3\tbad-map\tthe verification map does not parse: \(.detail)"
    elif .status == "attended" then "4\tneeds-person\t\(.detail)"
    elif .status == "dirty-tree" then "4\tdirty-tree\t\(.detail)"
    else "2\t\t" + "unknown result status \(.status)" end
' "$RESULT" 2>"$JQ_ERR") || undecided "could not read the result $RESULT: $(tail -n 3 "$JQ_ERR")"

TAB=$(printf '\t')
# A result this script can't read holds the gate before anything is recorded
# or printed.
while IFS= read -r line; do
    [ -n "$line" ] || continue
    [ "${line%%"$TAB"*}" != 2 ] || undecided "${line##*"$TAB"}"
done <<EOF
$LINES
EOF

# rank <exit>: the route's explicit order (see the header), 4 over 3 over 1
# over 6 over 5 over 0. Not the exit numbers themselves: 5 and 6 rank below 1.
rank() {
    case "$1" in
        4) echo 5 ;;
        3) echo 4 ;;
        1) echo 3 ;;
        6) echo 2 ;;
        5) echo 1 ;;
        *) echo 0 ;;
    esac
}

if [ "$MODE" = record-deferral ]; then
    # The same verdict --verdict reached, from the same lines and stages, with
    # nothing printed or recorded: a cause counts when its rule is at block,
    # which is exactly when rf_finding would set RF_COUNTED.
    VERDICT=0
    while IFS= read -r line; do
        [ -n "$line" ] || continue
        code=${line%%"$TAB"*}
        rest=${line#*"$TAB"}
        rule=verification/${rest%%"$TAB"*}
        [ "$(rf_stage "$rule")" = block ] || continue
        [ "$(rank "$code")" -le "$(rank "$VERDICT")" ] || VERDICT=$code
    done <<EOF
$LINES
EOF
    [ "$VERDICT" -eq 5 ] \
        || undecided "the verification result for $HEAD_SHA reads $VERDICT, not 5 (every failed command failing the same way at the merge-base), so there is no deferral to record"
    IDS=$(jq -r '[.commands[] | select(.exit_status != 0 and .baseline.verdict == "preexisting") | .id] | join(", ")' "$RESULT" 2>"$JQ_ERR") \
        || undecided "could not read the command ids from $RESULT: $(tail -n 3 "$JQ_ERR")"
    [ -n "$IDS" ] || undecided "the result $RESULT names no pre-existing failed command"
    command -v koto >/dev/null || undecided "koto is not on PATH; the deferral was not recorded"
    REASON=$(mktemp "${TMPDIR:-/tmp}/check-verification-deferral.XXXXXX") || undecided "could not create a temporary file"
    trap 'rm -f "$JQ_ERR" "$REASON"' EXIT
    printf 'local verification failed at head %s and at the merge-base %s with the same exit status for %s, so the failure predates this change\n' \
        "$HEAD_SHA" "$MB" "$IDS" > "$REASON" || undecided "could not write the deferral reason"
    koto context add "$SESSION" verification_deferral --from-file "$REASON" >/dev/null \
        || undecided "could not record verification_deferral in koto context"
    echo "check-verification: recorded verification_deferral: $(cat "$REASON")" >&2
    exit 0
fi

# Record the settled result before reporting it.
command -v koto >/dev/null || undecided "koto is not on PATH; the result was not recorded"
koto context add "$SESSION" verification_results.json --from-file "$RESULT" >/dev/null \
    || undecided "could not record verification_results.json in koto context"

# Print every finding, and rank the route over the ones that printed at block:
# rf_finding sets RF_COUNTED to 1 for exactly those, so a cause whose rule is
# below block reports without choosing the route.
VERDICT=0
while IFS= read -r line; do
    [ -n "$line" ] || continue
    code=${line%%"$TAB"*}
    rest=${line#*"$TAB"}
    rule=verification/${rest%%"$TAB"*}
    msg=${rest#*"$TAB"}
    rf_finding "$rule" "$msg"
    [ "$RF_COUNTED" -eq 1 ] || continue
    [ "$(rank "$code")" -le "$(rank "$VERDICT")" ] || VERDICT=$code
done <<EOF
$LINES
EOF

# Exit 6 holds for the agent (see the header): say what each answer does.
if [ "$VERDICT" -eq 6 ]; then
    echo "check-verification: the comparison with the merge-base could not decide whether this change caused" \
        "the failure, so there is no deferral. Submit verification_status: fix to change the code (back to" \
        "implementation), or verification_status: blocked with the reason in detail to stop. To run the suite" \
        "and the comparison again, move the result $RESULT aside and tick." >&2
fi

[ "$VERDICT" -eq 0 ] || rf_dispute_hint
# The escalation ladder (scripts/lib/rule-findings.sh): nothing without the
# template's context, or when no block-stage finding was printed. A passing
# verdict prints none at block, so rf_deliver does nothing before an exit 0 and
# always returns 0, which is why it can sit before every exit here.
rf_deliver
exit "$VERDICT"
