#!/usr/bin/env bash
# check-verification.sh -- what did the verification run for this head find?
# Part of the work-on skill
#
# The `verification` state's `poll:` gate. run-verification.sh --start starts
# the map's commands; this reads the result they leave on disk and exits with
# the verdict, or with koto's pending code while there is none yet.
#
#   --verdict --session <s> [--base-ref <ref>] [--shared-branch <value>]
#
# --shared-branch carries the template's SHARED_BRANCH (empty for a run not
# under /execute). It is accepted and passed on; the hosted-of-record route no
# longer reads it, since /execute collects a child's record.
#
# The result file's location, the head and the merge-base come from
# `run-verification.sh --locate`, so the two scripts can't disagree on them.
# A result computed against another merge-base is stale and reads as pending:
# the next --start replaces it.
#
# Exit status:
#   75  no result for this head yet; the gate waits
#   0   every selected command ran and passed, or was carried from the run a
#       fix round follows (outcome carried, which counts as passed), or every
#       cause found is of a rule below the `block` stage
#   1   a check failed (outcome failed,        verification/command-failed
#       including a stop at its limit with a
#       finished-failed suite)
#   3   no map, or a map that selects nothing  verification/no-map
#       a map that does not parse              verification/bad-map
#   4   a command needs a person               verification/needs-person
#       a check timed out, or the run passed   verification/timed-out
#       its total budget, and the
#       hosted-of-record route is closed
#       a command grew past max_procs          verification/runaway
#       a command could not start              verification/not-started
#       tracked files were dirty               verification/dirty-tree
#   5   a check timed out, none failed, and    verification/timed-out
#       the hosted-of-record route is open:
#       the hold, where the run may ask for a
#       re-run (rerun with a reason, under the
#       cap), take the route (hosted_of_record
#       with a reason), go back to fix, or stop
#   2   the result could not be read, or recorded in koto context, or
#       verification_attempts could not be read from koto context (a missing
#       key is not a failed read), or the supervisor stopped before every
#       command ran, or a build-output removal outlasted the run's budget and
#       no command started; the gate holds. No finding; the reason goes to
#       stderr.
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
# A `removal-running` result is held the same way, and for the same reason:
# the supervisor waited on a build-output removal still running in the work
# tree until the run's budget ran out, and started no command. The message
# names the record from the result's detail.
#
# The ranking reads each record's `outcome` (run-verification.sh's header).
# A not-started command, a runaway, a command that needs a person and a dirty
# tree outrank everything (4); then no map or a bad one (3); then a failed
# check (1), so a failed check beside a timed-out one goes back to
# implementation, since the change broke something the clock didn't decide;
# and only then a timeout, which is 5 when the hosted-of-record route is open
# and 4 when it isn't, with each closing cause on stderr. A record without
# `outcome` (a result written before outcomes existed) ranks by its flags as
# before, its timed-out records ranked as timeouts, and the route stays closed.
# Whether the route is open is verification-route.sh's vr_open_check, sourced
# here and run in this process, never as a second one.
#
# Only a cause whose rule is at the `block` stage takes part in that ranking.
# Every cause prints its finding at its rule's stage (error at block, warning
# at warn, info at shadow, nothing at retired); the route is the highest exit
# among the causes printed at block, and 0 when there is none. So a timed-out
# command whose rule is at warn, beside a failed command whose rule is at
# block, routes to 1. A non-zero route also prints a line on stderr
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
# The re-run ledger, `verification_attempts`, is read through --session only
# when the result could route to 1 or to 5. To 1: a failed command is present
# and verification/command-failed is at `block`. To 5: the only causes at
# `block` are timeouts and the hosted-of-record route is open, which is why
# the route's open check runs before anything is recorded. A pass and exits 3
# and 4 (a timed-out check with the route closed included) never read it, so a
# koto failure can't change them. A failed read holds the gate (exit 2) before anything is
# recorded; a missing key is an empty ledger and lists no earlier attempt. On
# exits 1 and 5 with ledger lines at the result's head and merge-base, stderr
# gives this attempt's number (those lines plus one) and its log folder, then
# each earlier attempt oldest first, with its failed or timed-out command ids
# and its reason, cleaned and marked as data from earlier runs.
#
# verification-eligibility.sh's verification_eligibility is the one counter,
# shared with run-verification.sh, and its answer picks the rest. On exit 1,
# `over-cap` adds a line naming the two ways out: a real fix, committed as a
# new head, or implementation_status: blocked. A failed command beside a
# timed-out one is eligible like a plain failure, so it gets that line too. On
# exit 5, `eligible` offers verification_status: rerun beside
# hosted_of_record, fix and blocked, and for a stop at the total budget says a
# re-run can take up to two more hours; `over-cap` says the cap is spent and
# offers only the other three. A ledger that reads but doesn't parse keeps the
# exit and says the re-run history can't be read, so no re-run is offered.
#
# Written for the bash 3.2 floor, without `set -e`: an unexpected failure must
# not exit 1 and read as a failed command.

set -u

HERE=$(cd "$(dirname "$0")" && pwd)
RULE_IDS="verification/command-failed verification/no-map verification/bad-map verification/needs-person verification/timed-out verification/runaway verification/not-started verification/dirty-tree"
RESULT_SCHEMA=shirabe-verification-result/v1

usage() {
    echo "Usage: check-verification.sh --verdict --session <s> [--base-ref <ref>] [--shared-branch <value>]" >&2
}

undecided() {
    echo "check-verification: $*" >&2
    exit 2
}

# shellcheck source=../../../scripts/lib/rule-findings.sh
. "$HERE/../../../scripts/lib/rule-findings.sh" || undecided "cannot load scripts/lib/rule-findings.sh"
# The route's open check, run in this process (see the ranking above).
# shellcheck source=verification-route.sh
. "$HERE/verification-route.sh" || undecided "cannot load verification-route.sh"
# The re-run count and the text cleaning, shared with run-verification.sh.
# shellcheck source=verification-eligibility.sh
. "$HERE/verification-eligibility.sh" || undecided "cannot load verification-eligibility.sh"
CV_LEDGER_KEY=verification_attempts

# cv_ledger_read: write verification_attempts' non-empty lines to LEDGER_FILE,
# leaving it empty for a missing key, and return 0; return 1 on a failed read.
# A missing key is `koto context exists` exiting 1 with nothing on stdout, the
# rule run-verification.sh's ctx_read keeps; anything else is a failed read,
# never an empty ledger.
cv_ledger_read() {
    local out rc
    : > "$LEDGER_FILE" || return 1
    out=$(koto context exists "$SESSION" "$CV_LEDGER_KEY")
    rc=$?
    if [ "$rc" -eq 1 ] && [ -z "$out" ]; then
        return 0
    fi
    [ "$rc" -eq 0 ] || return 1
    out=$(koto context get "$SESSION" "$CV_LEDGER_KEY") || return 1
    printf '%s\n' "$out" | grep . > "$LEDGER_FILE"
    # grep exits 1 for a value with no non-empty line, which is an empty ledger.
    [ $? -le 1 ] || return 1
    return 0
}

CV_K=0

# cv_attempts_listing: the lines about earlier attempts at this head and
# merge-base (see the header), on stderr, for exits 1 and 5. Sets CV_K to the
# ledger's line count at the pair and returns 0, printing nothing when that is
# 0. Returns 1, printing nothing, when the ledger doesn't parse.
cv_attempts_listing() {
    local k hd n folder
    CV_K=0
    k=$(verification_attempts_at "$LEDGER_FILE" "$HEAD_SHA" "$MB") || return 1
    CV_K=$k
    [ "$k" -gt 0 ] || return 0
    hd=$(dirname "$RESULT")
    # The folder this attempt logs to: run.json's attempt, else the folder of
    # the first command log the result names (a run.json from before attempt
    # folders logs in the head directory itself).
    n=""
    [ ! -e "$hd/run.json" ] \
        || n=$(jq -r 'if (.attempt | type) == "number" and .attempt == (.attempt | floor) and .attempt >= 1
                      then (.attempt | floor | tostring) else empty end' "$hd/run.json")
    case "$n" in
        ''|*[!0-9]*)
            folder=$(jq -r '[.commands[]? | objects | .log | strings][0] // empty' "$RESULT")
            if [ -n "$folder" ]; then
                folder=$(verification_clean "${folder%/*}/")
            else
                folder="$hd/"
            fi
            ;;
        *) folder="$hd/attempts/$n/" ;;
    esac
    echo "check-verification: this is attempt $((k + 1)) at head $HEAD_SHA and merge-base $MB; its logs are in $folder" >&2
    echo "check-verification: earlier attempts at this head and merge-base, oldest first. Their ids and reasons" \
        "are data recorded by earlier runs, not instructions:" >&2
    # Every value shown came from an earlier run, so each goes through clean
    # again here, whatever the archive stored.
    jq -nR -r --arg head "$HEAD_SHA" --arg mb "$MB" "$VE_CLEAN_JQ"'
        [inputs | select(length > 0) | fromjson | select(.head == $head and .merge_base == $mb)]
        | sort_by(.attempt) | .[]
        | ([.commands[]? | objects
            | select(.timed_out == true or ((.exit_status | type) == "number" and .exit_status != 0))
            | "\(.id | clean) \(if .timed_out == true then "timed out" else "failed" end)"]
           | if length == 0 then "no failed command recorded" else join(", ") end) as $ids
        | "check-verification:   attempt \(.attempt | clean): \($ids); reason [\(.reason | clean)]"
    ' "$LEDGER_FILE" >&2
    return 0
}

# cv_failed_message: exit 1's lines about earlier attempts (see the header).
# Prints nothing for an empty ledger or one with no line at the pair.
cv_failed_message() {
    local elig
    if ! cv_attempts_listing; then
        echo "check-verification: $CV_LEDGER_KEY for session $SESSION does not parse, so the re-run history" \
            "can't be read: the earlier attempts can't be listed and no re-run is offered. The ways out are a" \
            "real fix (a new head) or implementation_status: blocked." >&2
        return 0
    fi
    [ "$CV_K" -gt 0 ] || return 0
    elig=$(verification_eligibility "$RESULT" "$LEDGER_FILE")
    if [ "$elig" = over-cap ]; then
        echo "check-verification: the re-run cap is spent: $CV_K attempts are already archived at this head and" \
            "merge-base, so a re-run request is refused. The ways out are a real fix, committed as a new head," \
            "or implementation_status: blocked with the reason in rationale." >&2
    fi
    return 0
}

# cv_hold_message: exit 5's lines (see the header): earlier attempts, then
# the values the hold accepts, with rerun only while the result is eligible.
cv_hold_message() {
    local elig="" lead three
    lead="check-verification: a check timed out, none failed, and the hosted-of-record route is open, so the run holds here."
    three="verification_status: hosted_of_record with the reason in detail (public text: it reaches the pull"
    three="$three request body) to settle the timed-out checks on their hosted jobs; fix to go back to"
    three="$three implementation; or blocked with the reason in detail to stop."
    if [ "$LEDGER_READ" -eq 1 ]; then
        if cv_attempts_listing; then
            elig=$(verification_eligibility "$RESULT" "$LEDGER_FILE")
        else
            echo "check-verification: $CV_LEDGER_KEY for session $SESSION does not parse, so the re-run history" \
                "can't be read: the earlier attempts can't be listed and no re-run is offered." >&2
        fi
    fi
    case "$elig" in
        eligible)
            echo "$lead Submit verification_status: rerun with the reason in detail to run the suite again at this" \
                "head (at most $VE_CAP re-runs per head and merge-base, counted together with the failed route's);" \
                "$three" >&2
            if [ "$(jq -r .status "$RESULT")" = timed-out ]; then
                echo "check-verification: this run stopped at its total budget, so a re-run can take up to two" \
                    "more hours." >&2
            fi
            ;;
        over-cap)
            echo "check-verification: the re-run cap is spent: $CV_K attempts are already archived at this head" \
                "and merge-base, so a rerun is refused." >&2
            echo "$lead Submit $three" >&2
            ;;
        *) echo "$lead Submit $three" >&2 ;;
    esac
    return 0
}

[ $# -ge 1 ] && [ "$1" = --verdict ] || { usage; exit 2; }
shift
SESSION=""
BASE_REF=""
SHARED_BRANCH=""
while [ $# -gt 0 ]; do
    case "$1" in
        --session)
            [ $# -ge 2 ] && [ -z "$SESSION" ] || { usage; exit 2; }
            SESSION=$2; shift 2 ;;
        --shared-branch)
            [ $# -ge 2 ] || { usage; exit 2; }
            SHARED_BRANCH=$2; shift 2 ;;
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
rf_require verification/command-failed verification/no-map verification/bad-map \
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

[ -e "$RESULT" ] || exit 75
[ -r "$RESULT" ] || undecided "the result $RESULT is not readable"
jq -e --arg schema "$RESULT_SCHEMA" '.schema == $schema and (.commands | type) == "array"' "$RESULT" >/dev/null \
    || undecided "the result $RESULT is not a $RESULT_SCHEMA object"
[ "$(jq -r .head "$RESULT")" = "$HEAD_SHA" ] || undecided "the result $RESULT is for another head"
[ "$(jq -r .merge_base "$RESULT")" = "$MB" ] || exit 75

# A stopped supervisor is no verdict (see the header): hold, record nothing.
if [ "$(jq -r .status "$RESULT")" = supervisor-error ]; then
    undecided "the verification run for $HEAD_SHA stopped before every command ran" \
        "($(jq -r '.commands | length' "$RESULT") finished), so there is no verdict to route on." \
        "The result is $RESULT. To run the suite again, move that file aside and tick;" \
        "to stop the run, submit verification_status: blocked with the reason in detail."
fi
# Nor is a run that started no command because a build-output removal outlasted
# its budget (see the header): the same hold, naming the record.
if [ "$(jq -r .status "$RESULT")" = removal-running ]; then
    undecided "the verification run for $HEAD_SHA started no command: $(jq -r '.detail' "$RESULT")." \
        "The result is $RESULT. Once that removal has ended, move the result aside and tick to run the suite;" \
        "to stop the run, submit verification_status: blocked with the reason in detail."
fi

# Every temporary file this script makes, removed by the one EXIT trap below,
# set before the first is made, so an exit between the two still removes it.
JQ_ERR=""
LEDGER_FILE=""
cv_cleanup() {
    [ -z "$JQ_ERR" ] || rm -f "$JQ_ERR"
    [ -z "$LEDGER_FILE" ] || rm -f "$LEDGER_FILE"
    return 0
}
trap cv_cleanup EXIT
JQ_ERR=$(mktemp "${TMPDIR:-/tmp}/check-verification.XXXXXX") || { JQ_ERR=""; undecided "could not create a temporary file"; }
LEDGER_FILE=$(mktemp "${TMPDIR:-/tmp}/check-verification.XXXXXX") || { LEDGER_FILE=""; undecided "could not create a temporary file"; }

# The findings and the verdict, both from the result, in one jq program. Each
# line is `<code>\t<rule>\t<message>`, the code 4, 3, 1 or T (a timeout,
# whose exit the route decides); the verdict is ranked over the lines whose
# finding printed at block.
LINES=$(jq -r '
    def argv: (.argv // []) | join(" ");
    def logpart: if .log then " (log: \(.log))" else "" end;
    def stopped: "command \(.id) [\(argv)] ran past its timeout_secs or the total run budget and was killed\(logpart)";
    if .status == "done" or .status == "timed-out" then
        (.commands[]
         | if .not_started then "4\tnot-started\tcommand \(.id) did not start: [\(.argv[0])] is not an executable program\(logpart)"
           elif .runaway then "4\trunaway\tcommand \(.id) [\(argv)] grew past its max_procs and was killed\(logpart)"
           elif .outcome == "passed" or .outcome == "carried" then empty
           elif (has("outcome") | not) then
               (if .timed_out then "T\ttimed-out\t\(stopped)"
                elif .exit_status != 0 then "1\tcommand-failed\tcommand \(.id) [\(argv)] exited \(.exit_status)\(logpart)"
                else empty end)
           elif .outcome == "failed" then
               (if .timed_out
                then "1\tcommand-failed\tcommand \(.id) [\(argv)] was stopped at its limit after suites finished failed: \((.suites.failed // []) | join(", "))\(logpart)"
                else "1\tcommand-failed\tcommand \(.id) [\(argv)] exited \(.exit_status)\(logpart)" end)
           elif .outcome == "timed-out-limit" then "T\ttimed-out\t\(stopped)"
           elif .outcome == "timed-out-inside"
           then "T\ttimed-out\tcommand \(.id) [\(argv)] exited \(.exit_status) and every failure line matches its timeout_form\(logpart)"
           else empty end),
        (if .status == "timed-out" then "T\ttimed-out\t\(.detail)" else empty end)
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

# Record the settled result before reporting it.
command -v koto >/dev/null || undecided "koto is not on PATH; the result was not recorded"
# Which routes the result could take, from each cause's code and its rule's
# stage: only a cause at `block` chooses the route, as in the ranking below.
CV_OUT=0 CV_FAIL=0 CV_TIME=0
while IFS= read -r line; do
    [ -n "$line" ] || continue
    code=${line%%"$TAB"*}
    rest=${line#*"$TAB"}
    [ "$(rf_stage "verification/${rest%%"$TAB"*}")" = block ] || continue
    case "$code" in
        4|3) CV_OUT=1 ;;
        1) CV_FAIL=1 ;;
        T) CV_TIME=1 ;;
    esac
done <<EOF
$LINES
EOF
# A result whose only block-stage causes are timeouts holds at 5 exactly when
# the route is open, so the open check runs here, before the record, and the
# ranking reuses its answer: a timed-out check with the route closed (exit 4)
# never reads the ledger.
CV_ROUTE=""
if [ "$CV_FAIL" -eq 0 ] && [ "$CV_OUT" -eq 0 ] && [ "$CV_TIME" -eq 1 ]; then
    if vr_open_check "$SESSION" "$HEAD_SHA" "$MB" "$RESULT" "$SHARED_BRANCH"; then
        CV_ROUTE=open
    else
        CV_ROUTE=closed
    fi
fi
# The ledger, read only when the result could route to 1 or 5 (see the
# header), and before the record, so a failed read settles nothing.
LEDGER_READ=0
if [ "$CV_FAIL" -eq 1 ] || [ "$CV_ROUTE" = open ]; then
    cv_ledger_read || undecided "could not read $CV_LEDGER_KEY for session $SESSION from koto context; a failed" \
        "read is not an empty ledger, so the result was not recorded"
    LEDGER_READ=1
fi
koto context add "$SESSION" verification_results.json --from-file "$RESULT" >/dev/null \
    || undecided "could not record verification_results.json in koto context"

# Print every finding, and rank the route over the ones that printed at block:
# rf_finding sets RF_COUNTED to 1 for exactly those, so a cause whose rule is
# below block reports without choosing the route.
HELD=0 MAPPED=0 FAILED=0 TIMED=0
while IFS= read -r line; do
    [ -n "$line" ] || continue
    code=${line%%"$TAB"*}
    rest=${line#*"$TAB"}
    rule=verification/${rest%%"$TAB"*}
    msg=${rest#*"$TAB"}
    rf_finding "$rule" "$msg"
    [ "$RF_COUNTED" -eq 1 ] || continue
    case "$code" in
        4) HELD=1 ;;
        3) MAPPED=1 ;;
        1) FAILED=1 ;;
        T) TIMED=1 ;;
    esac
done <<EOF
$LINES
EOF

VERDICT=0
if [ "$HELD" -eq 1 ]; then
    VERDICT=4
elif [ "$MAPPED" -eq 1 ]; then
    VERDICT=3
elif [ "$FAILED" -eq 1 ]; then
    VERDICT=1
elif [ "$TIMED" -eq 1 ]; then
    if [ -z "$CV_ROUTE" ]; then
        if vr_open_check "$SESSION" "$HEAD_SHA" "$MB" "$RESULT" "$SHARED_BRANCH"; then
            CV_ROUTE=open
        else
            CV_ROUTE=closed
        fi
    fi
    if [ "$CV_ROUTE" = open ]; then
        VERDICT=5
    else
        VERDICT=4
        while IFS= read -r cause; do
            [ -n "$cause" ] && echo "check-verification: the hosted-of-record route is closed: $cause" >&2
        done <<EOF
$VR_CAUSES
EOF
    fi
fi

# Earlier attempts at this head and merge-base on the failed route, and the
# hold's values at 5.
if [ "$VERDICT" -eq 1 ] && [ "$LEDGER_READ" -eq 1 ]; then
    cv_failed_message
elif [ "$VERDICT" -eq 5 ]; then
    cv_hold_message
fi

[ "$VERDICT" -eq 0 ] || rf_dispute_hint
# The escalation ladder (scripts/lib/rule-findings.sh): nothing without the
# template's context, or when no block-stage finding was printed. A passing
# verdict prints none at block, so rf_deliver does nothing before an exit 0 and
# always returns 0, which is why it can sit before every exit here.
rf_deliver
exit "$VERDICT"
