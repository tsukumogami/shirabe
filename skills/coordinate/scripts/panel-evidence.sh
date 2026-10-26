#!/usr/bin/env bash
# panel-evidence.sh -- judge a worker's review round: the worker's own review
# round, which the land step reads instead of running a panel of its own
# (docs/designs/current/DESIGN-coordinate-merge-policy.md, Decision 1). The
# round is the JSON record review-round.sh stores in the worker's run session,
# read there or from the result block of the worker's report (board-lib.sh's
# bl_review_evidence). A pull request body's Review panel table is not a
# round, and nothing here reads one.
#
# Usage: panel-evidence.sh --round <file|->
#
# The input is one JSON object:
#
#   {"reviewed_head": "<40-hex sha>",
#    "seats": [{"seat": S, "model": M, "run": R, "verdict": V}, ...]}
#
# and each seat is read as a row of seat, model, run, verdict and the round's
# reviewed head, then judged by the rules below.
#
# Rules, each a `malformed` reason:
#   shape         the input isn't one object with a string reviewed_head and
#                 a seats array of objects whose four fields are strings
#   no-rows       seats is empty
#   control       a field holds a control character
#   cells         a seat has an empty field
#   run           a Run isn't ^[A-Za-z0-9][A-Za-z0-9._:/#-]{3,}$
#   verdict       a Verdict isn't pass or fail
#   head          the reviewed head isn't a full lowercase sha
#   seat-repeated two seats share a Seat, compared without case
#   run-repeated  two seats share a Run, compared exactly
#   heads-differ  the seats name different reviewed heads
# Seats are checked in order, each against the per-seat rules in the order
# above; the last three, which compare seats, run once every seat passes. A
# repeated Seat or Run is a panel claim whose seats can't be told apart.
#
# Output, one JSON object on stdout:
#   {"status":"malformed","reason":R,"row":N}   N is the 1-based seat, or 0
#   {"status":"ok","reviewed_head":S,"seats":[{seat,model,run,verdict}],
#    "count":N,"passes":P}
#
# Exit codes: 0 printed; 2 the input couldn't be read; 64 usage.
set -uo pipefail

usage() { sed -n '/^# Usage:/p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 64; }
[ $# -eq 2 ] && [ "$1" = --round ] || usage
shift
case "$1" in --*) usage ;; esac
if [ "$1" = - ]; then
    IN=/dev/stdin
else
    [ -r "$1" ] || { echo "panel-evidence: can't read $1" >&2; exit 2; }
    IN=$1
fi

# A file that isn't JSON at all is the round's shape, not a read failure: the
# record is there and says nothing the land step can use.
jq -Rsc '
  def bad($r; $n): {status: "malformed", reason: $r, row: $n};
  def judge($rows):
    if ($rows | length) == 0 then bad("no-rows"; 0)
    else
      ([range(0; $rows | length) as $i | $rows[$i] as $r
        | if ($r | map(explode | any(. < 32 or . == 127)) | any) then bad("control"; $i + 1)
          elif ($r | length) != 5 or ($r | map(. == "") | any) then bad("cells"; $i + 1)
          elif ($r[2] | test("^[A-Za-z0-9][A-Za-z0-9._:/#-]{3,}$") | not) then bad("run"; $i + 1)
          elif ($r[3] | IN("pass", "fail") | not) then bad("verdict"; $i + 1)
          elif ($r[4] | test("^[0-9a-f]{40}$") | not) then bad("head"; $i + 1)
          else empty end] | first) as $err
      | if $err != null then $err
        elif ($rows | map(.[0] | ascii_downcase) | unique | length) != ($rows | length) then bad("seat-repeated"; 0)
        elif ($rows | map(.[2]) | unique | length) != ($rows | length) then bad("run-repeated"; 0)
        elif ($rows | map(.[4]) | unique | length) != 1 then bad("heads-differ"; 0)
        else {status: "ok", reviewed_head: $rows[0][4],
              seats: [$rows[] | {seat: .[0], model: .[1], run: .[2], verdict: .[3]}],
              count: ($rows | length),
              passes: ([$rows[] | select(.[3] == "pass")] | length)}
        end
    end;
  (try fromjson catch null) as $o
  | if ($o | type) != "object"
       or ($o.reviewed_head | type) != "string"
       or ($o.seats | type) != "array"
       or ($o.seats | map(type == "object" and ([.seat, .model, .run, .verdict] | map(type == "string") | all)) | all | not)
    then bad("shape"; 0)
    else judge([$o.seats[] | [.seat, .model, .run, .verdict, $o.reviewed_head]])
    end' "$IN" || { echo "panel-evidence: the round couldn't be parsed" >&2; exit 2; }
