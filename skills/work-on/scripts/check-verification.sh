#!/usr/bin/env bash
# check-verification.sh -- what did the verification run for this head find?
# Part of the work-on skill
#
# The `verification` state's `poll:` gate. run-verification.sh --start starts
# the map's commands; this reads the result they leave on disk and exits with
# the verdict, or with koto's pending code while there is none yet.
#
#   --verdict --session <s> [--base-ref <ref>]
#
# The result file's location, the head and the merge-base come from
# `run-verification.sh --locate`, so the two scripts can't disagree on them.
# A result computed against another merge-base is stale and reads as pending:
# the next --start replaces it.
#
# Exit status:
#   75  no result for this head yet; the gate waits
#   0   every selected command ran and passed
#   1   a command ran and failed               verification/command-failed
#   3   no map, or a map that selects nothing  verification/no-map
#       a map that does not parse              verification/bad-map
#   4   a command needs a person               verification/needs-person
#       a command timed out                    verification/timed-out
#       a command grew past max_procs          verification/runaway
#       a command could not start, or the      verification/not-started
#       supervisor stopped before it finished
#       tracked files were dirty               verification/dirty-tree
#   2   the result could not be read, or recorded in koto context; the gate
#       holds. No finding; the reason goes to stderr.
#
# Exit 4 outranks exit 1: when one result holds a failed command and one that
# timed out, the run stops for a person rather than going back to
# implementation, since the change was never fully verified.
#
# Each violation prints one koto finding per cause:
#   ::koto-finding::{"rule_id":"verification/<rule>","level":"error",
#                    "message":"...","rule_ref":"<path>#L<a>-L<b>@<commit>"}
# with the rule_ref from gate-rules.tsv beside this script.
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
RULES="$HERE/gate-rules.tsv"
RESULT_SCHEMA=shirabe-verification-result/v1

usage() {
    echo "Usage: check-verification.sh --verdict --session <s> [--base-ref <ref>]" >&2
}

undecided() {
    echo "check-verification: $*" >&2
    exit 2
}

rule_ref() {
    awk -F'\t' -v id="$1" '$0 !~ /^#/ && $1 == id { print $2 "@" $3; exit }' "$RULES" 2>/dev/null
}

[ $# -ge 1 ] && [ "$1" = --verdict ] || { usage; exit 2; }
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
[ -r "$RULES" ] || undecided "the rule table $RULES is not readable"
for id in command-failed no-map bad-map needs-person timed-out runaway not-started dirty-tree; do
    [ -n "$(rule_ref "verification/$id")" ] || undecided "the rule table has no row for verification/$id"
done

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

# The findings and the verdict, both from the result, in one jq program. Each
# line is `<exit>\t<rule>\t<message>`; the verdict is the highest-ranked exit.
LINES=$(jq -r '
    def argv: (.argv // []) | join(" ");
    def logpart: if .log then " (log: \(.log))" else "" end;
    if .status == "done" then
        (.commands[]
         | if .not_started then "4\tnot-started\tcommand \(.id) did not start: [\(.argv[0])] is not an executable program\(logpart)"
           elif .runaway then "4\trunaway\tcommand \(.id) [\(argv)] grew past its max_procs and was killed\(logpart)"
           elif .timed_out then "4\ttimed-out\tcommand \(.id) [\(argv)] ran past its timeout_secs and was killed\(logpart)"
           elif .exit_status != 0 then "1\tcommand-failed\tcommand \(.id) [\(argv)] exited \(.exit_status)\(logpart)"
           else empty end)
    elif .status == "no-map" then "3\tno-map\t\(.detail)"
    elif .status == "bad-map" then "3\tbad-map\tthe verification map does not parse: \(.detail)"
    elif .status == "attended" then "4\tneeds-person\t\(.detail)"
    elif .status == "dirty-tree" then "4\tdirty-tree\t\(.detail)"
    elif .status == "supervisor-error" then "4\tnot-started\t\(.detail)"
    else "2\t\t" + "unknown result status \(.status)" end
' "$RESULT" 2>/dev/null) || undecided "could not read the result $RESULT"

VERDICT=0
TAB=$(printf '\t')
while IFS= read -r line; do
    [ -n "$line" ] || continue
    code=${line%%"$TAB"*}
    case "$code" in
        2) undecided "${line##*"$TAB"}" ;;
        4) VERDICT=4 ;;
        3) [ "$VERDICT" -eq 4 ] || VERDICT=3 ;;
        1) [ "$VERDICT" -ge 3 ] || VERDICT=1 ;;
    esac
done <<EOF
$LINES
EOF

# Record the settled result before reporting it.
command -v koto >/dev/null || undecided "koto is not on PATH; the result was not recorded"
koto context add "$SESSION" verification_results.json --from-file "$RESULT" >/dev/null \
    || undecided "could not record verification_results.json in koto context"

while IFS= read -r line; do
    [ -n "$line" ] || continue
    rest=${line#*"$TAB"}
    rule=verification/${rest%%"$TAB"*}
    msg=${rest#*"$TAB"}
    jq -cn --arg id "$rule" --arg msg "$msg" --arg ref "$(rule_ref "$rule")" \
        '{rule_id: $id, level: "error", message: $msg, rule_ref: $ref}' | sed 's/^/::koto-finding::/'
done <<EOF
$LINES
EOF

exit "$VERDICT"
