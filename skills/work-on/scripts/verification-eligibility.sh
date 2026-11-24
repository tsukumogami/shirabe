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
#   verification_gate_exit <result-file>
#                 prints the gate exit an eligible result came through: 1 when
#                 any command failed, 5 when every command that did not pass
#                 timed out (the timed-out hold). Returns 1, printing nothing,
#                 when jq can't read the file
#
# A command record is one of three kinds, read the way check-verification.sh
# ranks it. A record with `outcome` timed out when the outcome is
# timed-out-limit or timed-out-inside; one without timed out when timed_out
# is true. A failure is any other record that did not pass, did not grow past
# max_procs, did start, and has a numeric exit_status (a stop at the limit
# whose suite summary lists a finished-failed suite is `outcome: failed`, so a
# failure). A pass exits 0 with every flag false.
#
# verification_eligibility's line:
#
#   eligible             the result's status is `done` or `timed-out` (a stop at
#                        the run's total budget), at least one command did not
#                        pass (or the status is `timed-out`), every command
#                        that did not pass is a failure or a timeout, no
#                        command grew past max_procs or failed to start, a
#                        budget stop left no command unstarted, and fewer than
#                        VE_CAP ledger lines are at the result's head and
#                        merge-base. A failed command beside a timed-out one is
#                        eligible too
#   over-cap             the same result, with VE_CAP or more ledger lines at
#                        its head and merge-base
#   ineligible <cause>   anything else. <cause> is:
#                          no-result    there is no result file (a suite still
#                                       running, or none started)
#                          passed       every command passed
#                          <status>     the status of a result that is neither
#                                       `done` nor `timed-out`: attended,
#                                       dirty-tree, no-map, bad-map,
#                                       supervisor-error, removal-running
#                          runaway      a command grew past its max_procs
#                          not-started  a command could not start, or a budget
#                                       stop left commands unstarted: fewer
#                                       records than the invocations in the
#                                       run.json beside the result
#                          unreadable   the result is not one result object jq
#                                       can read, the run.json beside a budget
#                                       stop doesn't parse, or the ledger is
#                                       missing or doesn't parse
#
# The result's own causes are decided first, and the ledger is read only for a
# result that would otherwise be eligible: over-cap applies to nothing else,
# and a passing result stays `ineligible passed` whatever the ledger holds. A
# missing ledger file (or no second argument) is `ineligible unreadable`, never
# an empty ledger: a caller that found no ledger key passes an empty file. A
# missing run.json is no unstarted command, as verification-route.sh's open
# check reads it.
#
# A runaway and a command that never started say something other than "this
# command failed once" or "this command ran out of time", so neither is
# eligible here. Every input is read only through jq, and fetching the ledger
# from koto is the caller's job; a parse error reads as `unreadable`.
# verification_eligibility always returns 0: the answer is the line, not the
# status.
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

# The record kinds (see the header), shared by verification_eligibility and
# verification_gate_exit.
VE_RECORD_JQ='
def flag($k): .[$k] == true;
def passed: (.exit_status == 0) and (flag("timed_out") | not)
            and (flag("runaway") | not) and (flag("not_started") | not);
def timed_out_rec: if has("outcome")
                   then (.outcome == "timed-out-limit" or .outcome == "timed-out-inside")
                   else flag("timed_out") end;
def failed_rec: (passed | not) and (flag("runaway") | not) and (flag("not_started") | not)
                and (timed_out_rec | not) and ((.exit_status | type) == "number");
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
    local file=${1-} ledger=${2-} out rh rmb at runf inv=""
    if [ ! -e "$file" ]; then
        echo "ineligible no-result"
        return 0
    fi
    # The invocations a budget stop was given, from the run.json beside the
    # result: empty when there is none, `bad` when it doesn't parse.
    runf="$(dirname "$file")/run.json"
    if [ -e "$runf" ]; then
        inv=$(jq -r 'if type == "object" and (.invocations | type) == "array"
                     then (.invocations | length) else "bad" end' "$runf") || inv=bad
        case "$inv" in ''|*[!0-9]*) inv=bad ;; esac
    fi
    out=$(jq -rs --arg inv "$inv" "$VE_RECORD_JQ"'
        if length != 1 or (.[0] | type) != "object" then "ineligible unreadable"
        else .[0]
        | if (.status | type) != "string" then "ineligible unreadable"
          elif (.status | test("^[a-z][a-z-]*$") | not) then "ineligible unreadable"
          elif .status != "done" and .status != "timed-out" then "ineligible \(.status)"
          elif (.commands | type) != "array" then "ineligible unreadable"
          elif (.commands | all(type == "object") | not) then "ineligible unreadable"
          else [.commands[] | select(passed | not)] as $bad
          | if any($bad[]; flag("runaway")) then "ineligible runaway"
            elif any($bad[]; flag("not_started")) then "ineligible not-started"
            elif .status == "timed-out" and $inv == "bad" then "ineligible unreadable"
            elif .status == "timed-out" and $inv != "" and (.commands | length) < ($inv | tonumber)
            then "ineligible not-started"
            elif ($bad | length) == 0 and .status == "done" then "ineligible passed"
            elif all($bad[]; failed_rec or timed_out_rec) then "eligible"
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

verification_gate_exit() {
    local out
    out=$(jq -r "$VE_RECORD_JQ"'
        if any((.commands // [])[]; type == "object" and failed_rec) then 1 else 5 end' "${1-}") || return 1
    case "$out" in
        1|5) printf '%s\n' "$out" ;;
        *) return 1 ;;
    esac
}
