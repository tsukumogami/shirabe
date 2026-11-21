#!/usr/bin/env bash
# verification-eligibility.sh -- may this verification result be run again at
# the same head?
# Part of the work-on skill
#
# Sourced, not run: it defines one function. run-verification.sh loads it by a
# path built from its own directory, and decides from its answer whether a
# re-run request may archive the result it has.
#
#   verification_eligibility <result-file>
#
# Prints exactly one line:
#
#   eligible             the result's status is `done`, at least one command
#                        failed, and every command that did not pass is a plain
#                        failure: a non-null, non-zero exit_status, with
#                        timed_out, runaway and not_started all false
#   ineligible <cause>   anything else. <cause> is:
#                          no-result    there is no result file (a suite still
#                                       running, or none started)
#                          passed       every command passed
#                          <status>     the status of a result that is not
#                                       `done`: timed-out, attended,
#                                       dirty-tree, no-map, bad-map,
#                                       supervisor-error
#                          runaway      a command grew past its max_procs
#                          not-started  a command could not start
#                          timed-out    a command ran past its deadline
#                          unreadable   the file is not one result object jq
#                                       can read
#
# A runaway, a command that never started and a timeout say something other
# than "this command failed once", so none of them is eligible here. The
# result is read only through jq; a parse error reads as `unreadable`. The
# function always returns 0: the answer is the line, not the status.
#
# Written for the bash 3.2 floor, without `set -e`.

verification_eligibility() {
    local file=$1 out
    if [ ! -e "$file" ]; then
        echo "ineligible no-result"
        return 0
    fi
    out=$(jq -rs '
        def flag($k): .[$k] == true;
        def passed: (.exit_status == 0) and (flag("timed_out") | not)
                    and (flag("runaway") | not) and (flag("not_started") | not);
        def plain_failure: (.exit_status | type) == "number" and .exit_status != 0
                           and (flag("timed_out") | not) and (flag("runaway") | not)
                           and (flag("not_started") | not);
        if length != 1 or (.[0] | type) != "object" then "ineligible unreadable"
        else .[0]
        | if (.status | type) != "string" then "ineligible unreadable"
          elif (.status | test("^[a-z][a-z-]*$") | not) then "ineligible unreadable"
          elif .status != "done" then "ineligible \(.status)"
          elif (.commands | type) != "array" then "ineligible unreadable"
          elif (.commands | all(type == "object") | not) then "ineligible unreadable"
          else [.commands[] | select(passed | not)] as $bad
          | if ($bad | length) == 0 then "ineligible passed"
            elif any($bad[]; flag("runaway")) then "ineligible runaway"
            elif any($bad[]; flag("not_started")) then "ineligible not-started"
            elif any($bad[]; flag("timed_out")) then "ineligible timed-out"
            elif all($bad[]; plain_failure) then "eligible"
            else "ineligible unreadable" end
          end
        end
    ' "$file" 2>/dev/null) || out=""
    case "$out" in
        eligible|"ineligible "*) ;;
        *) out="ineligible unreadable" ;;
    esac
    # One line, whatever jq printed.
    printf '%s\n' "${out%%
*}"
    return 0
}
