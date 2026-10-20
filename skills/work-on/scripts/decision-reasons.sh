#!/usr/bin/env bash
# decision-reasons.sh -- for /work-on: the decisions a run recorded, as a slice
#
# The `scrutiny_decider` gate on `scrutiny` runs this and sends what it prints
# to Jev with one shadow question: does every decision listed give, in its
# reason, why the choice was made? The slice is every `decision_recorded`
# event koto wrote for `analysis` or `implementation`, any visit, in log order:
#
#   - choice: <choice>
#     reason: <rationale>
#
# Each field's whitespace is collapsed to single spaces and trimmed, and an
# empty or missing field is printed as the bare label. A decision's
# `alternatives_considered` is left out: the question judges the reason, and
# with alternatives the slice was over budget on more of the measured runs
# (references/jev-criteria.md, work-on/scrutiny-decision-reasons).
#
# The gate passes the session log's path ({{SESSION_DIR}}/koto-<name>.state.jsonl),
# so this calls no koto and can't contend with the tick that runs it. The same
# call on a fixture or a stored session's log is how the fixtures and the
# measurement build their slices, so there is one implementation. It reads no
# other file and no context key.
#
# Usage: decision-reasons.sh slice <session-log>
#
# Exit codes:
#   0   -- the slice is on stdout, or nothing when no decision matches
#   64  -- usage
#   66  -- the log is missing or unreadable, or holds a line jq can't parse
#          (koto reads that as extraction_failed: a fallback, never a pass)
#   127 -- jq is missing
#
# Bash 3.2: no associative arrays, no mapfile.
set -uo pipefail

die() {
    # $1 exit code, $2 message
    echo "decision-reasons: $2" >&2
    exit "$1"
}

[ "$#" -eq 2 ] && [ "$1" = slice ] || die 64 "usage: decision-reasons.sh slice <session-log>"
LOG="$2"
command -v jq >/dev/null || die 127 "jq is not on PATH"
[ -f "$LOG" ] && [ -r "$LOG" ] || die 66 "cannot read session log [$LOG]"

# Every input is read before anything is printed, so a line jq can't parse
# prints nothing and fails the whole slice.
# shellcheck disable=SC2016
PROGRAM='
def one: if type == "string" then gsub("\\s+"; " ") | sub("^ "; "") | sub(" $"; "")
         elif . == null then "" else tostring | gsub("\\s+"; " ") | sub("^ "; "") | sub(" $"; "") end;
def field($label): if . == "" then $label else $label + " " + . end;
[inputs
 | select(type == "object" and .type == "decision_recorded")
 | select((.payload.state // "") as $s | $s == "analysis" or $s == "implementation")
 | (.payload.decision // {})]
| .[]
| ((.choice | one | field("- choice:")) + "\n" + (.rationale | one | field("  reason:")))
'
out=$(jq -rn "$PROGRAM" < "$LOG") || die 66 "cannot parse session log [$LOG]"
[ -n "$out" ] && printf '%s\n' "$out"
exit 0
