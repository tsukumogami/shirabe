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
#   0   every selected command ran and passed, or every cause found is of a
#       rule below the `block` stage
#   1   a command ran and failed               verification/command-failed
#   3   no map, or a map that selects nothing  verification/no-map
#       a map that does not parse              verification/bad-map
#   4   a command needs a person               verification/needs-person
#       a command timed out, or the run        verification/timed-out
#       passed its total budget
#       a command grew past max_procs          verification/runaway
#       a command could not start              verification/not-started
#       tracked files were dirty               verification/dirty-tree
#   5   every cause above that counted is a    verification/command-failed
#       failed or timed-out command whose log  verification/timed-out
#       names failures only in files the
#       change doesn't touch (or, timed out,
#       names no failure)
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
# Exit 4 outranks exit 1: when one result holds a failed command and one that
# timed out, the run stops for a person rather than going back to
# implementation, since the change was never fully verified.
#
# Only a cause whose rule is at the `block` stage takes part in that ranking.
# Every cause prints its finding at its rule's stage (error at block, warning
# at warn, info at shadow, nothing at retired); the route is the highest exit
# among the causes printed at block, and 0 when there is none. So a timed-out
# command whose rule is at warn, beside a failed command whose rule is at
# block, routes to 1, not 4. A non-zero route also prints a line on stderr
# saying how to dispute a finding.
#
# Exit 5 comes after that ranking, never inside it: when the ranked exit is 1
# or 4 and every cause counted at block is eligible (see "attribution" below),
# the exit is 5 instead. Its findings keep their rule ids; an eligible cause's
# message ends with `; outside the change: <files>` or `; its log names no
# failure`. The template has no automatic route on 5: the run goes on only on
# the agent's evidence, and hosted CI stays the build of record.
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
RULE_IDS="verification/command-failed verification/no-map verification/bad-map verification/needs-person verification/timed-out verification/runaway verification/not-started verification/dirty-tree"
RESULT_SCHEMA=shirabe-verification-result/v1

usage() {
    echo "Usage: check-verification.sh --verdict --session <s> [--base-ref <ref>]" >&2
}

undecided() {
    echo "check-verification: $*" >&2
    exit 2
}

# shellcheck source=../../../scripts/lib/rule-findings.sh
. "$HERE/../../../scripts/lib/rule-findings.sh" || undecided "cannot load scripts/lib/rule-findings.sh"

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

JQ_ERR=$(mktemp "${TMPDIR:-/tmp}/check-verification.XXXXXX") || undecided "could not create a temporary file"
trap 'rm -f "$JQ_ERR"' EXIT

# --- attribution: which failures lie only outside the change -------------------
#
# A failed or timed-out command is eligible for exit 5 when its log attributes
# its failures only to files the change doesn't touch. Every test below fails
# closed: anything the result can't show leaves the command ineligible, and an
# ineligible cause keeps today's exit.
#
#   - The result is a `done` one and carries changed_paths, the merge-base diff
#     run-verification.sh --start selected on. A `timed-out` result (the run's
#     budget) never qualifies: the commands after the budget never started.
#   - The command failed (not runaway, not not-started) or timed out, and
#     carries failure_lines, read from the map at the merge-base, so a branch
#     can't widen its own attribution.
#   - Its log is readable. A failure line starts with `prefix` at column 0;
#     indented lines never count. A failed command needs at least one; a
#     timed-out one may have none, which is "its log names no failure".
#   - Every failure line starts with `path_prefix`, and the file it names (the
#     text after it, up to the first space) is a plain repo-relative path, no
#     leading `/`, no `.` or `..` component, that names a file (a blob) at the
#     result's head. A path printed in any other form can't then slip past the
#     comparison below.
#   - No named file is in changed_paths.
#
# The log is read with jq -R, and every prefix is a literal string compared
# with startswith, so no regex dialect decides what a line means.

# path_plain <path>: true when <path> is a plain repo-relative path.
path_plain() {
    case "$1" in
        ''|/*|.|..|./*|../*|*/./*|*/../*|*/.|*/..|*//*|*/) return 1 ;;
    esac
    return 0
}

# attribute <index>: true when command <index> is eligible. Sets ATTR_FILES to
# the JSON list of files its failure lines name (empty for a timed-out command
# whose log names no failure).
attribute() {
    local kind log fl scan unattr count f
    ATTR_FILES='[]'
    kind=$(jq -r --argjson i "$1" '.commands[$i]
        | if .not_started == true or .runaway == true then "none"
          elif .timed_out == true then "timed"
          elif .exit_status != 0 then "failed"
          else "none" end' "$RESULT" 2>/dev/null) || return 1
    [ "$kind" = failed ] || [ "$kind" = timed ] || return 1
    fl=$(jq -c --argjson i "$1" '.commands[$i].failure_lines
        | if type == "object" and (.prefix | type) == "string" and .prefix != ""
             and (.path_prefix | type) == "string"
             and (.prefix as $p | .path_prefix | startswith($p))
          then {prefix, path_prefix} else null end' "$RESULT" 2>/dev/null) || return 1
    [ -n "$fl" ] && [ "$fl" != null ] || return 1
    log=$(jq -r --argjson i "$1" '.commands[$i].log | if type == "string" then . else "" end' "$RESULT" 2>/dev/null) || return 1
    [ -n "$log" ] && [ -f "$log" ] && [ -r "$log" ] || return 1
    # One pass over the log: how many failure lines, how many of them name no
    # file, and the distinct files named.
    scan=$(jq -Rnc --argjson fl "$fl" '
        [inputs | select(startswith($fl.prefix))] as $lines
        | ($fl.path_prefix | length) as $n
        | [$lines[] | select(startswith($fl.path_prefix)) | .[$n:] | split(" ")[0]] as $named
        | {count: ($lines | length), unattributed: (($lines | length) - ($named | length)),
           files: ($named | unique)}' "$log" 2>/dev/null) || return 1
    count=$(printf '%s' "$scan" | jq -r .count) || return 1
    unattr=$(printf '%s' "$scan" | jq -r .unattributed) || return 1
    [ "$unattr" = 0 ] || return 1
    [ "$kind" = timed ] || [ "$count" -gt 0 ] || return 1
    ATTR_FILES=$(printf '%s' "$scan" | jq -c .files) || return 1
    while IFS= read -r f; do
        [ -n "$f" ] || continue
        path_plain "$f" || return 1
        [ "$(git -C "$ROOT" cat-file -t "$HEAD_SHA:$f" 2>/dev/null)" = blob ] || return 1
    done <<EOF
$(printf '%s' "$ATTR_FILES" | jq -r '.[]')
EOF
    # The loop skips blank lines (an empty list prints one), so an empty name,
    # a path_prefix line with nothing after it, is refused here.
    printf '%s' "$ATTR_FILES" | jq -e 'all(. != "")' >/dev/null || return 1
    jq -e --argjson f "$ATTR_FILES" '(.changed_paths) as $ch | all($f[]; . as $p | $ch | index([$p]) | not)' \
        "$RESULT" >/dev/null 2>&1 || return 1
    return 0
}

# ELIG: [{i, files}] for each eligible command, read by the jq program below.
ELIG='[]'
if jq -e '.status == "done" and (.changed_paths | type) == "array" and all(.changed_paths[]; type == "string")' \
    "$RESULT" >/dev/null 2>&1; then
    ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || ROOT=""
    NCMD=$(jq '.commands | length' "$RESULT" 2>/dev/null) || NCMD=0
    if [ -n "$ROOT" ]; then
        i=0
        while [ "$i" -lt "$NCMD" ]; do
            if attribute "$i"; then
                ELIG=$(jq -cn --argjson e "$ELIG" --argjson i "$i" --argjson f "$ATTR_FILES" '$e + [{i: $i, files: $f}]') \
                    || undecided "could not record the attribution of command $i"
            fi
            i=$((i + 1))
        done
    fi
fi

# The findings and the verdict, both from the result, in one jq program. Each
# line is `<exit>\t<rule>\t<eligible>\t<message>`, where <eligible> is 1 for a
# cause whose failures lie only outside the change (above) and 0 otherwise;
# the verdict is the highest-ranked exit among the lines whose finding printed
# at block, or 5 when every one of those is eligible.
LINES=$(jq -r --argjson elig "$ELIG" '
    def argv: (.argv // []) | join(" ");
    def logpart: if .log then " (log: \(.log))" else "" end;
    def outside($e): if ($e.files | length) == 0 then "; its log names no failure"
                     else "; outside the change: \($e.files | join(", "))" end;
    if .status == "done" or .status == "timed-out" then
        (.commands | to_entries[] | .key as $k | .value
         | ([$elig[] | select(.i == $k)] | first) as $e
         | if .not_started then "4\tnot-started\t0\tcommand \(.id) did not start: [\(.argv[0])] is not an executable program\(logpart)"
           elif .runaway then "4\trunaway\t0\tcommand \(.id) [\(argv)] grew past its max_procs and was killed\(logpart)"
           elif .timed_out then
               if $e then "4\ttimed-out\t1\tcommand \(.id) [\(argv)] ran past its timeout_secs or the total run budget and was killed\(logpart)\(outside($e))"
               else "4\ttimed-out\t0\tcommand \(.id) [\(argv)] ran past its timeout_secs or the total run budget and was killed\(logpart)" end
           elif .exit_status != 0 then
               if $e then "1\tcommand-failed\t1\tcommand \(.id) [\(argv)] exited \(.exit_status)\(logpart)\(outside($e))"
               else "1\tcommand-failed\t0\tcommand \(.id) [\(argv)] exited \(.exit_status)\(logpart)" end
           else empty end),
        (if .status == "timed-out" then "4\ttimed-out\t0\t\(.detail)" else empty end)
    elif .status == "no-map" then "3\tno-map\t0\t\(.detail)"
    elif .status == "bad-map" then "3\tbad-map\t0\tthe verification map does not parse: \(.detail)"
    elif .status == "attended" then "4\tneeds-person\t0\t\(.detail)"
    elif .status == "dirty-tree" then "4\tdirty-tree\t0\t\(.detail)"
    else "2\t\t0\t" + "unknown result status \(.status)" end
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
koto context add "$SESSION" verification_results.json --from-file "$RESULT" >/dev/null \
    || undecided "could not record verification_results.json in koto context"

# Print every finding, and rank the route over the ones that printed at block:
# rf_finding sets RF_COUNTED to 1 for exactly those, so a cause whose rule is
# below block reports without choosing the route.
VERDICT=0
COUNTED=0
ALL_ELIGIBLE=1
while IFS= read -r line; do
    [ -n "$line" ] || continue
    code=${line%%"$TAB"*}
    rest=${line#*"$TAB"}
    rule=verification/${rest%%"$TAB"*}
    rest=${rest#*"$TAB"}
    eligible=${rest%%"$TAB"*}
    msg=${rest#*"$TAB"}
    rf_finding "$rule" "$msg"
    [ "$RF_COUNTED" -eq 1 ] || continue
    COUNTED=$((COUNTED + 1))
    [ "$eligible" = 1 ] || ALL_ELIGIBLE=0
    case "$code" in
        4) VERDICT=4 ;;
        3) [ "$VERDICT" -eq 4 ] || VERDICT=3 ;;
        1) [ "$VERDICT" -ge 3 ] || VERDICT=1 ;;
    esac
done <<EOF
$LINES
EOF

# Exit 5: the ranking above settled on 1 or 4, and every cause counted at
# block is a failed or timed-out command outside the change. One cause that isn't --
# a touched or unattributable failure, a runaway, a command that never
# started, the run's budget -- keeps the ranked exit, so 5 never hides one.
if [ "$COUNTED" -gt 0 ] && [ "$ALL_ELIGIBLE" -eq 1 ] && { [ "$VERDICT" -eq 1 ] || [ "$VERDICT" -eq 4 ]; }; then
    VERDICT=5
    echo "check-verification: every failure above lies outside the change. Submit verification_status: deferred with the files and your reading in detail to go on with hosted CI as the build of record, fix to go back to implementation (pick it when a failing suite exercises code this change edits), or blocked to stop." >&2
fi

[ "$VERDICT" -eq 0 ] || rf_dispute_hint
# The escalation ladder (scripts/lib/rule-findings.sh): nothing without the
# template's context, or when no block-stage finding was printed. A passing
# verdict prints none at block, so rf_deliver does nothing before an exit 0 and
# always returns 0, which is why it can sit before every exit here.
rf_deliver
exit "$VERDICT"
