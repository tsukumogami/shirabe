#!/usr/bin/env bash
# panel-evidence.sh -- parse a pull request body's Review panel table: the
# worker's own review round, which the land step reads instead of running a
# panel of its own (docs/designs/current/DESIGN-coordinate-merge-policy.md,
# Decision 1).
#
# Usage: panel-evidence.sh <body-file|->
#
# Part 1 is the body above its first top-level `---` line outside a code
# fence; it becomes the squash message, so it is never searched. In Part 2 the
# first line reading exactly `## Review panel` outside a fence starts the
# evidence; after blank lines comes one table:
#
#   | Seat | Model | Run | Verdict | Reviewed head |
#   |---|---|---|---|---|
#   | architect | sonnet | <run id> | pass | <40-hex sha> |
#
# Headers are matched case-insensitively. A cell may be wrapped in backticks.
# Rules, each a `malformed` reason:
#   no-table      the heading is followed by no header row
#   header        the header names other columns, or no separator row follows
#   no-rows       no seat row follows the separator row
#   control       a cell holds a control character
#   cells         a row hasn't five non-empty cells
#   run           a Run isn't ^[A-Za-z0-9][A-Za-z0-9._:/#-]{3,}$
#   verdict       a Verdict isn't pass or fail
#   head          a Reviewed head isn't a full lowercase sha
#   seat-repeated two rows name the same Seat, compared without case
#   run-repeated  two rows share a Run, compared exactly
#   heads-differ  the rows name different reviewed heads
# Rows are checked in order, each against the per-row rules in the order
# above; the last three, which compare rows, run once every row passes. A
# repeated Seat or Run is a panel claim whose seats can't be told apart.
#
# Output, one JSON object on stdout:
#   {"status":"absent"}                         no heading in Part 2
#   {"status":"malformed","reason":R,"row":N}   N is the 1-based seat row, or 0
#   {"status":"ok","reviewed_head":S,"seats":[{seat,model,run,verdict}],
#    "count":N,"passes":P}
#
# Exit codes: 0 printed; 2 the body couldn't be read; 64 usage.
set -uo pipefail

[ $# -eq 1 ] || { sed -n '/^# Usage:/p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 64; }
if [ "$1" = - ]; then
    IN=/dev/stdin
else
    [ -r "$1" ] || { echo "panel-evidence: can't read $1" >&2; exit 2; }
    IN=$1
fi

jq -Rsc '
  def trim: sub("^[ \t]+"; "") | sub("[ \t]+$"; "");
  def unticked: if test("^`[^`]*`$") then .[1:-1] else . end;
  def cells: trim | sub("^\\|"; "") | sub("\\|$"; "") | split("|") | map(trim | unticked);
  def bad($r; $n): {status: "malformed", reason: $r, row: $n};

  (gsub("\r\n"; "\n") | split("\n")) as $lines
  # Whether each line sits inside a code fence; a fence line counts as inside.
  | (reduce range(0; $lines | length) as $i ({fence: false, out: []};
      if ($lines[$i] | test("^[ \t]*```")) then .fence = (.fence | not) | .out += [true]
      else .out += [.fence] end) | .out) as $infence
  | ([range(0; $lines | length) | select(($infence[.] | not) and ($lines[.] | trim) == "---")] | first) as $sep
  | if $sep == null then {status: "absent"}
    else
      ([range($sep + 1; $lines | length)
        | select(($infence[.] | not) and ($lines[.] | sub("[ \t]+$"; "")) == "## Review panel")] | first) as $h
      | if $h == null then {status: "absent"}
        else
          ([range($h + 1; $lines | length) | select(($lines[.] | trim) != "")] | first) as $t
          | if $t == null or ($lines[$t] | trim | startswith("|") | not) then bad("no-table"; 0)
            elif ($lines[$t] | cells | map(ascii_downcase)) != ["seat", "model", "run", "verdict", "reviewed head"] then bad("header"; 0)
            elif ($t + 1 >= ($lines | length)) or ($lines[$t + 1] | trim | test("^\\|?[ \t:|-]+\\|?$") | not) then bad("header"; 0)
            else
              $lines[$t + 2:] as $rest
              | ([range(0; $rest | length) | select($rest[.] | trim | startswith("|") | not)] | first // ($rest | length)) as $end
              | [ $rest[0:$end][] | cells ] as $rows
              | if ($rows | length) == 0 then bad("no-rows"; 0)
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
                end
            end
        end
    end' "$IN" || { echo "panel-evidence: the body couldn't be parsed" >&2; exit 2; }
