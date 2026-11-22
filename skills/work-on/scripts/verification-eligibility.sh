#!/usr/bin/env bash
# verification-eligibility.sh -- may this verification result be run again at
# the same head?
# Part of the work-on skill
#
# Sourced, not run. run-verification.sh and check-verification.sh both load it
# by a path built from their own directory, so the launcher that archives an
# attempt and the gate that reports on it count re-runs the same way. It
# defines:
#
#   VE_CAP        the number of archived attempts allowed per head and
#                 merge-base: 2
#   VE_CLEAN_JQ   a jq program defining `clean`, the one cleaning for any text
#                 an earlier run wrote (a reason, a command id): ANSI escape
#                 sequences removed, control characters and newlines made
#                 spaces, Unicode format characters (bidirectional controls,
#                 zero-width characters, the byte-order mark) removed, then
#                 trimmed and capped at 500 characters
#   verification_clean <text>
#                 prints <text> cleaned by VE_CLEAN_JQ; empty when nothing is
#                 left
#   verification_attempts_at <ledger-file> <head> <merge-base>
#                 prints how many ledger lines name that head and merge-base,
#                 and returns 1, printing nothing, when the file is missing or
#                 any non-empty line isn't a JSON object with string `head` and
#                 `merge_base`
#   verification_eligibility <result-file> <ledger-file>
#                 prints exactly one line, below
#
# verification_eligibility's line:
#
#   eligible             the result's status is `done`, at least one command
#                        failed, every command that did not pass is a plain
#                        failure (a non-null, non-zero exit_status, with
#                        timed_out, runaway and not_started all false), and
#                        fewer than VE_CAP ledger lines are at the result's
#                        head and merge-base
#   over-cap             the same result, with VE_CAP or more ledger lines at
#                        its head and merge-base
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
#                          unreadable   the result is not one result object jq
#                                       can read, or the ledger is missing or
#                                       doesn't parse
#
# The result's own causes are decided first, and the ledger is read only for a
# result that would otherwise be eligible: over-cap applies to nothing else,
# and a passing result stays `ineligible passed` whatever the ledger holds. A
# missing ledger file (or no second argument) is `ineligible unreadable`, never
# an empty ledger: a caller that found no ledger key passes an empty file.
#
# A runaway, a command that never started and a timeout say something other
# than "this command failed once", so none of them is eligible here. Every input
# is read only through jq, and fetching the ledger from koto is the caller's
# job; a parse error reads as `unreadable`. verification_eligibility always
# returns 0: the answer is the line, not the status.
#
# Written for the bash 3.2 floor, without `set -e`. jq decodes its input to
# Unicode code points whatever the locale, so the cleaning matches U+202E or
# U+FEFF and counts 500 characters, not bytes, under LC_ALL=C on macOS too,
# where tr and sed work on bytes.

VE_CAP=2

# The order matters: escape sequences go first, since ESC is itself a control
# character the next step would turn into a space. \p{Cc} is C0, DEL and C1;
# U+2028 and U+2029, the line and paragraph separators, become spaces with
# them. The code points listed beside \p{Cf} keep the soft hyphen (U+00AD), the
# Arabic letter mark (U+061C), U+200B..U+200F, the bidirectional embeddings and
# overrides (U+202A..U+202E), U+2060..U+2064, the isolates and other format
# characters (U+2066..U+206F) and the byte-order mark (U+FEFF) removed even
# under a jq build whose Unicode tables are older. Those code points are built
# with implode, from their decimal values, so this file stays ASCII and no
# editor or copy can turn an escape into the invisible character itself (45 is
# the hyphen that makes a range). Backticks stay: whoever renders the text in a
# code span removes them there.
VE_CLEAN_JQ='
def clean: tostring
  | gsub("\u001b\\[[0-?]*[ -/]*[@-~]"; "")
  | gsub("\u001b\\][^\u0007\u001b]*(\u0007|\u001b\\\\)"; "")
  | gsub("\u001b[@-_]?"; "")
  | gsub("[\\p{Cc}" + ([8232, 8233] | implode) + "]"; " ")
  | gsub("[\\p{Cf}" + ([173, 1564, 8203, 45, 8207, 8234, 45, 8238, 8288, 45, 8292, 8294, 45, 8303, 65279]
                       | implode) + "]"; "")
  | sub("^\\s+"; "") | sub("\\s+$"; "") | .[0:500] | sub("\\s+$"; "");
'

verification_clean() {
    jq -rn --arg r "${1-}" "$VE_CLEAN_JQ"' $r | clean'
}

verification_attempts_at() {
    local file=${1-} out
    [ -n "$file" ] && [ -f "$file" ] || return 1
    # Line by line, so one line holding two JSON values is not two lines.
    out=$(jq -nR --arg head "${2-}" --arg mb "${3-}" '
        [inputs | select(length > 0) | fromjson
         | if type == "object" and (.head | type) == "string" and (.merge_base | type) == "string"
           then . else error("not a ledger line") end]
        | map(select(.head == $head and .merge_base == $mb)) | length
    ' "$file") || return 1
    case "$out" in ''|*[!0-9]*) return 1 ;; esac
    printf '%s\n' "$out"
}

verification_eligibility() {
    local file=${1-} ledger=${2-} out rh rmb at
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
    out=${out%%
*}
    if [ "$out" = eligible ]; then
        rh=$(jq -r 'if (.head | type) == "string" then .head else empty end' "$file")
        rmb=$(jq -r 'if (.merge_base | type) == "string" then .merge_base else empty end' "$file")
        if [ -z "$rh" ] || [ -z "$rmb" ]; then
            out="ineligible unreadable"
        elif ! at=$(verification_attempts_at "$ledger" "$rh" "$rmb"); then
            out="ineligible unreadable"
        elif [ "$at" -ge "$VE_CAP" ]; then
            out=over-cap
        fi
    fi
    printf '%s\n' "$out"
    return 0
}
