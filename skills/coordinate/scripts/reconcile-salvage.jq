# reconcile-salvage.jq -- read a coordinator record body, or a discipline
# handoff, that the record feature's parser refused, row by row.
#
# record-parse.sh refuses a whole body for one bad row; reconcile must still
# re-check every other claim and report the bad row as unparseable. This reads
# the same structure with the record feature's own codec (record-codec.jq:
# its sections, cell splitting, row grammar and scope line), so what is a
# valid row is still that feature's definition. Only the handling of a bad
# row differs: it is set aside with its raw line and the codec's reason. A
# body whose structure is wrong (sections, headers, declaration) is still
# refused, since there is no row to salvage from.
#
# Input: the body as one raw string (jq -R -s). Output: the parser's JSON
# shape plus `unparseable: [{raw, reason}]`. For a handoff whose reasoning
# section is missing or empty, `reasoning` is "" (the caller reads that as
# not recorded).

# A handoff with a Reasoning heading and no tables is refused too: there is no
# row to salvage.
#
# reconcile-read.sh runs this as one program with the codec prepended (jq 1.8
# aborts on a function reached through two levels of include); the include
# line below is for reading the file on its own.

include "record-codec";

def reason_of: sub("^refused: "; "");

# salvage_table($sec; $body) -> {rows: [...], bad: [{raw, reason}]}
def salvage_table($sec; $body):
  if $body == "None." then {rows: [], bad: []}
  else
    ($body | split("\n")) as $lines
    | ("| " + ($sec.cols | map(.[1]) | join(" | ")) + " |") as $header
    | if ($lines | length) < 3 then refuse("\($sec.title): a table needs a header, a separator and a row, or None.")
      elif $lines[0] != $header then refuse("\($sec.title): header row differs from the fixed columns")
      else reduce $lines[2:][] as $line ({rows: [], bad: []};
        (try ($line | split_cells as $cells
              | if ($cells | length) != ($sec.cols | length)
                then refuse("\($sec.title): a row with \($cells | length) cells, not \($sec.cols | length)")
                else [range(0; $sec.cols | length) as $i | {($sec.cols[$i][0]): $cells[$i]}] | add
                     | check_row($sec; []) end
              | {ok: .})
         catch {err: (. | tostring | reason_of)}) as $r
        | if $r.ok != null then .rows += [$r.ok]
          else .bad += [{raw: ($line | gsub("[\u0000-\u001f\u007f]"; "")), reason: $r.err}] end)
      end
  end;

def salvage_sections($parts):
  [range(0; 4) as $i | sections[$i] as $sec | $parts[$i] as $p
   | if ($p | startswith($sec.title + "\n\n") | not) then refuse("section \($i + 1): expected ## \($sec.title)") else . end
   | salvage_table($sec; $p[($sec.title | length) + 2:]) | {key: $sec.key, value: .}]
  | {tables: (map({key, value: .value.rows}) | from_entries), unparseable: (map(.value.bad[]))};

def salvage_record:
  normalized | split("\n\n## ") as $parts
  | if ($parts | length) != 5 then refuse("expected four sections, found \(($parts | length) - 1)") else . end
  | ($parts[0] | split("\n")) as $head
  | ([$head | to_entries[] | select(.value | startswith("> This is a **coordinator record** for ")) | .key]) as $at
  | if ($at | length) != 1 then refuse("expected one declaration line") else . end
  | ($head[$at[0] + 2] // "") as $wline
  | ($wline | capture("^Written: (?<w>.*)$") // refuse("no Written: line")).w as $written
  | salvage_sections($parts[1:5]) as $s
  | {scope: parse_scope($head[$at[0]]), written: $written} + $s.tables + {unparseable: $s.unparseable};

# A handoff whose reasoning section is missing, or present and empty, still
# has its four tables read; its reasoning is "".
def salvage_handoff:
  normalized | split("\n\n## ") as $parts
  | if ($parts | length) < 5 then refuse("expected four sections") else . end
  | ($parts[5:] | join("\n\n## ")) as $rp
  | (if $rp == "" or $rp == "Reasoning for the next rotation" then ""
     elif ($rp | startswith("Reasoning for the next rotation\n\n")) then $rp[("Reasoning for the next rotation\n\n" | length):]
     else refuse("expected ## Reasoning for the next rotation last") end) as $text
  | ($parts[0] | split("\n\n")) as $head
  | ($head[0] | capture("^# (?<n>[A-Za-z0-9._-]+) handoff, (?<d>.*)$") // refuse("no handoff heading")) as $h
  | (($head[1] // "") | capture("^Rotation from (?<s>[^ ]*) to (?<e>[^ ]*)\\. Host repository: (?<r>[^ ]*)\\. Record: (?<u>[^ ,]*), kept on coordinate/discipline-(?<n>[A-Za-z0-9._-]+)\\.$") // refuse("no rotation line")) as $i
  | ([($head[2] // "") | capture("^As written by the previous rotation at (?<w>.*); not re-checked\\.$")] | first) as $p
  | salvage_sections($parts[1:5]) as $s
  | {scope: {kind: "discipline", name: $h.n},
     rotation: {start: $i.s, end: $i.e, date: $h.d, host_repo: $i.r, record_url: $i.u}}
    + (if $p != null and $text == predecessor_sentence then {predecessor_copy: {written: $p.w}} else {reasoning: $text} end)
    + $s.tables + {unparseable: $s.unparseable};
