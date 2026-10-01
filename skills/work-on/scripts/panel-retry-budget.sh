#!/usr/bin/env bash
# panel-retry-budget.sh -- for /work-on: may this panel send the work back again?
#
# A review panel (scrutiny, review, qa_validation) that finds blocking defects
# either submits `blocking_retry`, which returns the run to `implementation`, or
# `blocking_escalate`, which ends it at `done_blocked`. This script makes that
# call, and on a grant records the retry, so the panel directives run it before
# the retry loop and submit what it says.
#
# The rule (docs/decisions/DECISION-work-on-panel-retry-progress-cap-2026-10-01.md):
#
#   - The first FLOOR retries in a run are granted whatever the counts.
#   - Past those, a retry is granted only when this panel's blocking count is
#     lower than its own count on its previous blocking round. A panel with no
#     earlier blocking round has nothing to show progress against and is
#     refused.
#   - No run gets more than CEILING retries.
#
# Counts are compared within one panel because the panels count different
# things: scrutiny and review count blocking findings, qa_validation counts
# failed scenarios.
#
# The record is the koto context key `panel_retries`: one line per granted
# retry, "<panel> <count>", oldest first. The retry loops in the phase files
# clear the panel result keys and summary.md, never this one, so it lasts the
# whole run. A refusal records nothing.
#
# Fails closed where it can tell. A record koto reports present but won't
# return, a record line this script didn't write, a write that fails, or a
# read-back that doesn't show the new line is a refusal (exit 64 or 66), never
# a grant: a retry nobody recorded would not count against the ceiling. An
# absent record is the first retry of the run.
#
# What it can't tell: koto gives no way to separate an absent key from a store
# it can't read. `get` fails the same way for both, and `exists` and `list`
# report both as absent. On koto's local store an unreadable directory also
# refuses the write, so the grant still fails closed; that is the case the
# suite drives. On a store whose reads can fail while its writes succeed, a
# failed read would look like an empty record and the write would replace the
# real one, giving the run up to 3 more retries. That is reasoned from koto's
# behaviour, not observed; if it happens, the run spends more panel rounds than
# the ceiling allows rather than stopping early.
#
# One call per round. A second call for the same round records a second retry,
# so a run that repeats a call counts against the ceiling early and may read a
# repeated count as no progress. Both mistakes stop the run sooner, never later.
#
# Usage: panel-retry-budget.sh <koto-session-name> <panel> <blocking-count>
#   <panel>           scrutiny | review | qa_validation
#   <blocking-count>  this round's blocking findings (failed scenarios for
#                     qa_validation), a whole number of at least 1
#
# Prints one line on stdout:
#   verdict=retry retry=<n> ceiling=<CEILING>
#   verdict=escalate reason=<why>
#
# Exit codes:
#   0  -- retry granted and recorded; submit blocking_retry through the retry loop
#   1  -- refused; submit blocking_escalate with the printed reason
#   64 -- no answer: the record could not be read, or holds a line this script
#         didn't write; escalate
#   66 -- the grant could not be recorded: the write failed, or the read-back
#         doesn't show it; escalate
#   67 -- bad arguments; nothing was read or written
#
# Bash 3.2: no associative arrays, no mapfile.
set -uo pipefail

# These two numbers are also stated in the three panel directives in
# koto-templates/work-on.md, which settled-policy_test.sh pins, in this
# script's tests, and in the decision record. Change them together.
FLOOR=2
CEILING=3
KEY=panel_retries

usage() {
    echo "verdict=escalate reason=panel-retry-budget.sh was called wrongly: $1"
    echo "panel-retry-budget: $1" >&2
    echo "usage: panel-retry-budget.sh <koto-session-name> <scrutiny|review|qa_validation> <blocking-count>" >&2
    exit 67
}

no_answer() {
    echo "verdict=escalate reason=$1"
    echo "panel-retry-budget: $1" >&2
    exit 64
}

not_recorded() {
    echo "verdict=escalate reason=$1"
    echo "panel-retry-budget: $1" >&2
    exit 66
}

refuse() {
    echo "verdict=escalate reason=$1"
    exit 1
}

[ "$#" -eq 3 ] || usage "expected 3 arguments, got $#"
SESSION=$1
PANEL=$2
COUNT=$3

[ -n "$SESSION" ] || usage "missing session name"
case "$PANEL" in
    scrutiny|review|qa_validation) ;;
    *) usage "unknown panel [$PANEL]" ;;
esac
case "$COUNT" in
    ''|*[!0-9]*) usage "blocking count [$COUNT] is not a whole number" ;;
esac
# Six digits is far past any real round, and keeps the comparison below inside
# what `[ -lt ]` can compare: a number it can't parse makes the test error,
# which would read as "not refused" and grant.
[ "${#COUNT}" -le 6 ] || usage "blocking count [$COUNT] is longer than 6 digits"
# Strip leading zeros so the arithmetic below never reads the count as octal.
COUNT=$(printf '%s' "$COUNT" | sed 's/^0*//')
[ -n "$COUNT" ] || usage "blocking count is 0; a round with no blocking findings passes, it doesn't retry"

# --- read the record ---------------------------------------------------------

# `exists` is used only to find a record that is there; its "absent" is taken
# as absent because koto offers nothing better (see the header).
RECORD=""
if koto context exists "$SESSION" "$KEY" >/dev/null; then
    RECORD=$(koto context get "$SESSION" "$KEY") \
        || no_answer "could not read the retry record ($KEY) for session $SESSION"
fi

USED=0
LAST_SAME=""
while IFS=' ' read -r rec_panel rec_count rest; do
    [ -n "$rec_panel" ] || continue
    case "$rec_panel" in
        scrutiny|review|qa_validation) ;;
        *) no_answer "the retry record ($KEY) has a line this script did not write: [$rec_panel $rec_count]" ;;
    esac
    case "$rec_count" in
        ''|*[!0-9]*) no_answer "the retry record ($KEY) has a malformed count: [$rec_panel $rec_count]" ;;
    esac
    [ "${#rec_count}" -le 6 ] && [ -z "$rest" ] \
        || no_answer "the retry record ($KEY) has a line this script did not write: [$rec_panel $rec_count $rest]"
    USED=$((USED + 1))
    [ "$rec_panel" = "$PANEL" ] && LAST_SAME=$rec_count
done <<EOF
$RECORD
EOF

# --- decide ------------------------------------------------------------------

if [ "$USED" -ge "$CEILING" ]; then
    refuse "this run has used all $CEILING blocking retries"
fi
if [ "$USED" -ge "$FLOOR" ]; then
    if [ -z "$LAST_SAME" ]; then
        refuse "$USED blocking retries used and $PANEL has no earlier blocking round to show progress against"
    fi
    LAST_SAME=$(printf '%s' "$LAST_SAME" | sed 's/^0*//')
    LAST_SAME=${LAST_SAME:-0}
    # Written as "not fewer" rather than `-ge`: if `[` can't compare the two, it
    # fails, and the negation turns that failure into a refusal, not a grant.
    if ! [ "$COUNT" -lt "$LAST_SAME" ]; then
        refuse "$USED blocking retries used and $PANEL found $COUNT, not fewer than its previous $LAST_SAME"
    fi
fi

# --- record the grant, then confirm it landed ----------------------------------

LINE="$PANEL $COUNT"
if [ -n "$RECORD" ]; then
    NEW=$(printf '%s\n%s\n' "$RECORD" "$LINE")
else
    NEW=$(printf '%s\n' "$LINE")
fi
printf '%s\n' "$NEW" | koto context add "$SESSION" "$KEY" >/dev/null \
    || not_recorded "could not write the retry record ($KEY) for session $SESSION"

BACK=$(koto context get "$SESSION" "$KEY") \
    || not_recorded "could not read back the retry record ($KEY) for session $SESSION"
BACK_LINES=$(printf '%s\n' "$BACK" | grep -c .)
BACK_LAST=$(printf '%s\n' "$BACK" | grep . | tail -n 1)
if [ "$BACK_LINES" -ne $((USED + 1)) ] || [ "$BACK_LAST" != "$LINE" ]; then
    not_recorded "the retry record ($KEY) did not take this round's line"
fi

echo "verdict=retry retry=$((USED + 1)) ceiling=$CEILING"
exit 0
