# record-parse.jq -- the legacy importer's parser for a coordinator record body
# on GitHub: every definition skills/coordinate/scripts/record-codec.jq's
# parse_record reaches, copied unchanged and in the codec's order from the codec
# as of 098a3c9, the last commit that changed it. It holds no renderer. Its only
# checks are the ones parsing needs (the table grammars and check_scope on the
# declaration line); the importer checks the parsed state through the write
# core (state-schema.jq) before it writes a key.
#
# A copy rather than an include, so the importer still reads the old body
# format once the codec's markdown half is removed; whoever changes the codec's
# parse half before then refreshes this copy. Every refusal is a jq error()
# whose message starts with "refused: ".

# ---- from the codec's copy of state-schema.jq's section tables ------------
# The four sections every record has, in order, with their columns.
def sections: [
  {key: "holdings", title: "Holdings", cols: [
    ["unit", "Unit"], ["entry_point", "Entry point"], ["mode", "Mode"],
    ["phase", "Phase"], ["dispatch_status", "Dispatch status"],
    ["return_path", "Return path"], ["worker", "Worker"], ["repo", "Repo"],
    ["branch", "Branch"], ["verified_head", "Verified head"],
    ["dispatched", "Dispatched"], ["pull_request", "Pull request"]]},
  {key: "deferrals", title: "Deferrals", cols: [
    ["deferral", "Deferral"], ["reason", "Reason"], ["raised", "Raised"],
    ["disposition", "Disposition"]]},
  {key: "side_effects", title: "Side effects in flight", cols: [
    ["action", "Action"], ["target", "Target"], ["verified_head", "Verified head"],
    ["attempted", "Attempted"], ["how_to_confirm", "How to confirm"]]},
  {key: "reversals", title: "Reversals", cols: [
    ["date", "Date"], ["reversed", "Reversed"], ["now", "Now"],
    ["reason", "Reason"], ["from", "From"]]}
];

def refuse($m): error("refused: " + $m);

def re_name: "^[A-Za-z0-9._-]+$";

def holds_cols: [
  ["hold", "Hold"], ["on", "On"], ["until", "Until"], ["set_by", "Set by"],
  ["set", "Set"], ["lifted", "Lifted"]];

def state_secs: [
  {key: "run", title: "Run", cols: [["key", "Key"], ["value", "Value"], ["set_by", "Set by"], ["set", "Set"]]},
  {key: "standing", title: "Standing", cols: [["standing", "Standing"], ["kind", "Kind"], ["on", "On"],
    ["until", "Until"], ["what", "What"], ["owner", "Owner"], ["relayed_by", "Relayed by"], ["set", "Set"]]},
  {key: "work", title: "Work", cols: [["item", "Item"], ["kind", "Kind"], ["who", "Who"], ["next", "Next step"],
    ["wakes", "Wakes"], ["updated", "Updated"]]}];

def decisions_cols: [
  ["decision", "Decision"], ["round", "Round"], ["question", "Question"],
  ["options", "Options"], ["state", "State"], ["source", "Source"],
  ["verdict", "Verdict"], ["recommendation", "Recommendation"], ["reason", "Reason"],
  ["context", "Context"], ["problem", "Problem"], ["grounds", "Grounds"],
  ["target", "Target"], ["owed", "Owed"], ["asked", "Asked"],
  ["evidence", "Evidence"], ["outcome", "Outcome"], ["decided_by", "Decided by"],
  ["updated", "Updated"]];

def re_kept_stamp: "^[1-9][0-9]* (report|wait|raise|hold|redirect|ask) [1-9][0-9]*(\\.[1-9][0-9]*)?( addressed)?$";

# check_scope($s): the record's scope, {kind: roadmap|discipline, name}.
def check_scope($s):
  if ($s | type) != "object" then refuse("scope: missing")
  elif ($s.name // "" | test(re_name) | not) then refuse("scope.name: not a name")
  elif $s.kind != "roadmap" and $s.kind != "discipline" then refuse("scope.kind: not roadmap or discipline")
  else $s end;

def dec:
  gsub("&#9;"; "\t") | gsub("&#32;"; " ") | gsub("<br>"; "\n")
  | gsub("&#13;"; "\r") | gsub("\\\\\\|"; "|") | gsub("&#92;"; "\\")
  | gsub("&gt;"; ">") | gsub("&lt;"; "<") | gsub("&amp;"; "&");

def holds_title: "Holds";

def parse_holds($p):
  ($p[(holds_title | length) + 2:]) as $body
  | ($body | split("\n")) as $lines
  | ("| " + (holds_cols | map(.[1]) | join(" | ")) + " |") as $header
  | if ($lines | length) < 3 then refuse("Holds: a table needs a header, a separator and a row")
    elif $lines[0] != $header then refuse("Holds: header row differs from the fixed columns")
    else $lines[2:] | map(
      (if (startswith("| ") and endswith(" |")) | not then refuse("table row: not | cell | ... |") else . end
       | .[2:-2] | gsub("\\\\\\|"; "\u001f") | split(" | ") | map(gsub("\u001f"; "\\|") | dec)) as $cells
      | if ($cells | length) != (holds_cols | length) then refuse("Holds: a row with \($cells | length) cells, not \(holds_cols | length)")
        else [range(0; holds_cols | length) as $i | {(holds_cols[$i][0]): $cells[$i]}] | add end)
    end;

def parse_opt($sec; $p):
  ($p[($sec.title | length) + 2:]) as $body
  | ($body | split("\n")) as $lines
  | ("| " + ($sec.cols | map(.[1]) | join(" | ")) + " |") as $header
  | if ($lines | length) < 3 then refuse("\($sec.title): a table needs a header, a separator and a row")
    elif $lines[0] != $header then refuse("\($sec.title): header row differs from the fixed columns")
    else $lines[2:] | map(
      (if (startswith("| ") and endswith(" |")) | not then refuse("table row: not | cell | ... |") else . end
       | .[2:-2] | gsub("\\\\\\|"; "\u001f") | split(" | ") | map(gsub("\u001f"; "\\|") | dec)) as $cells
      | if ($cells | length) != ($sec.cols | length) then refuse("\($sec.title): a row with \($cells | length) cells, not \($sec.cols | length)")
        else [range(0; $sec.cols | length) as $i | {($sec.cols[$i][0]): $cells[$i]}] | add end)
    end;

def decisions_title: "Decisions";

def dec_d: gsub("&#64;"; "@") | dec;

def d_archived_line: " (settled; each kept verbatim in a decisions entry on this record)";

def d_kept_title: "Stamps kept for run ";

def d_unranges:
  [split(", ")[] | split("-") | map(tonumber) | if length == 1 then .[0] else range(.[0]; .[1] + 1) end];

def d_header:
  ("| " + (decisions_cols | map(.[1]) | join(" | ")) + " |") + "\n"
  + ("|" + (decisions_cols | map("---") | join("|")) + "|");

# parse_drow: a table row back to its entry.
def parse_drow:
  (if (startswith("| ") and endswith(" |")) | not then refuse("table row: not | cell | ... |") else . end
   | .[2:-2] | gsub("\\\\\\|"; "\u001f") | split(" | ") | map(gsub("\u001f"; "\\|") | dec_d)) as $cells
  | if ($cells | length) != (decisions_cols | length) then refuse("Decisions: a row with \($cells | length) cells, not \(decisions_cols | length)")
    else [range(0; decisions_cols | length) as $i | {(decisions_cols[$i][0]): $cells[$i]}] | add end;

def parse_decisions($p):
  if ($p | startswith(decisions_title + "\n\n") | not) then refuse("expected ## \(decisions_title) after Reversals") else . end
  | ($p[(decisions_title | length) + 2:]) as $body
  | ($body | capture("^Next decision: (?<n>[1-9][0-9]*)\n\n(?<rest>[\\s\\S]*)$") // refuse("Decisions: no `Next decision: <n>` line")) as $m
  | (if $m.rest | startswith("Archived: ") then
      ($m.rest | capture("^Archived: (?<ids>[^\n]*)\n\n(?<rest>[\\s\\S]*)$") // refuse("Decisions: an `Archived:` line with nothing after it")) as $c
      | if ($c.ids | endswith(d_archived_line) | not) then refuse("Decisions: an `Archived:` line that doesn't end \"\(d_archived_line)\"")
        elif ($c.ids | rtrimstr(d_archived_line) | test("^[1-9][0-9]*(-[1-9][0-9]*)?(, [1-9][0-9]*(-[1-9][0-9]*)?)*$") | not)
        then refuse("Decisions: `Archived:` names identifiers as ascending ranges, `1-12, 14`")
        else {ids: ($c.ids | rtrimstr(d_archived_line)), rest: $c.rest} end
    else null end) as $a
  | ($a.rest // $m.rest) as $r1
  | (if $r1 | startswith(d_kept_title) then
      ($r1 | capture("^" + d_kept_title + "(?<run>[0-9]{8}T[0-9]{6}Z): (?<st>[^\n]*)\n\n(?<rest>[\\s\\S]*)$")
        // refuse("Decisions: a `\(d_kept_title)<run>: ...` line that doesn't read")) as $c
      | {run: $c.run, rest: $c.rest, stamps: ($c.st | split(", ") | map(
          if test(re_kept_stamp) then split(" ") as $w
            | {decision: ($w[0] | tonumber), kind: $w[1], seq: $w[2], addressed: (($w | length) == 4)}
          else refuse("Decisions: a kept stamp that isn't `<entry> <kind> <seq>[ addressed]`") end))}
    else null end) as $k
  | ($k.rest // $r1) as $rest
  | {next: ($m.n | tonumber), entries:
      (if $rest == "None." then []
       else ($rest | split("\n")) as $lines
       | if ($lines | length) < 3 then refuse("Decisions: a table needs a header, a separator and a row, or None.")
         elif $lines[0] != (d_header | split("\n")[0]) then refuse("Decisions: header row differs from the fixed columns")
         else $lines[2:] | map(parse_drow)
         end
       end)}
  + (if $a == null then {} else {archived: ($a.ids | d_unranges)} end)
  + (if $k == null then {} else {kept: {run: $k.run, stamps: $k.stamps}} end);

def scope_text($s):
  check_scope($s) as $_
  | if $s.kind == "roadmap" then "ROADMAP-\($s.name)" else "the \($s.name) discipline" end;

def declaration($s): "> This is a **coordinator record** for \(scope_text($s)).";

def normalized: gsub("\r\n"; "\n") | sub("\n+$"; "");

def split_cells:
  if (startswith("| ") and endswith(" |")) | not then refuse("table row: not | cell | ... |") else . end
  | .[2:-2] | gsub("\\\\\\|"; "\u001f") | split(" | ")
  | map(gsub("\u001f"; "\\|") | dec);

def parse_table($sec; $body):
  if $body == "None." then []
  else
    ($body | split("\n")) as $lines
    | ("| " + ($sec.cols | map(.[1]) | join(" | ")) + " |") as $header
    | if ($lines | length) < 3 then refuse("\($sec.title): a table needs a header, a separator and a row, or None.")
      elif $lines[0] != $header then refuse("\($sec.title): header row differs from the fixed columns")
      else $lines[2:] | map(split_cells as $cells
        | if ($cells | length) != ($sec.cols | length) then refuse("\($sec.title): a row with \($cells | length) cells, not \($sec.cols | length)")
          else [range(0; $sec.cols | length) as $i | {($sec.cols[$i][0]): $cells[$i]}] | add end)
      end
  end;

# parse_sections($parts): $parts[i] is "Title\n\nbody" for the four sections.
def parse_sections($parts):
  [range(0; 4) as $i | sections[$i] as $sec | $parts[$i] as $p
   | if ($p | startswith($sec.title + "\n\n") | not) then refuse("section \($i + 1): expected ## \($sec.title)") else . end
   | {($sec.key): parse_table($sec; $p[($sec.title | length) + 2:])}] | add;

def parse_scope($line):
  ($line | capture("^> This is a \\*\\*coordinator record\\*\\* for (?<s>.*)\\.$") // refuse("no declaration line")).s as $s
  | if ($s | test("^ROADMAP-[A-Za-z0-9._-]+$")) then {kind: "roadmap", name: $s[8:]}
    elif ($s | test("^the [A-Za-z0-9._-]+ discipline$")) then {kind: "discipline", name: ($s | capture("^the (?<n>.*) discipline$").n)}
    else refuse("declaration line: unknown scope") end;

# optional_titles: the optional sections after the four, in their one order.
def optional_titles: [holds_title] + (state_secs | map(.title)) + [decisions_title];

def optional_index: . as $p | [optional_titles | to_entries[] | select(. as $e | $p | startswith($e.value + "\n\n")) | .key] | first;

# optional_tail($rest): the parts after the four sections, each one of the
# optional sections at most once, in optional_titles' order, as
# {holds?, run?, standing?, work?, decisions?}.
def optional_tail($rest):
  ($rest | map(optional_index)) as $ix
  | if any($ix[]; . == null)
    then refuse("after Reversals, only \(optional_titles | map("## " + .) | join(", ")) may follow, in that order")
    elif ($ix | . != (sort | unique))
    then refuse("the sections after Reversals come at most once each, in the order \(optional_titles | join(", "))")
    else [$rest[] | . as $p | optional_index as $i
      | if $i == 0 then {holds: parse_holds($p)}
        elif $i == (optional_titles | length) - 1 then {decisions: parse_decisions($p)}
        else state_secs[$i - 1] as $sec | {($sec.key): parse_opt($sec; $p)} end] | add // {} end;

def parse_record:
  normalized | split("\n\n## ") as $parts
  | if ($parts | length) < 5 or ($parts | length) > 5 + (optional_titles | length) then refuse("expected four sections, then the optional \(optional_titles | join(", ")), found \(($parts | length) - 1)") else . end
  | ($parts[0] | split("\n")) as $head
  | ([$head | to_entries[] | select(.value | startswith("> This is a **coordinator record** for ")) | .key]) as $at
  | if ($at | length) != 1 then refuse("expected one declaration line") else . end
  | ($head[$at[0] + 2] // "") as $wline
  | ($wline | capture("^Written: (?<w>.*)$") // refuse("no Written: line")).w as $written
  | {scope: parse_scope($head[$at[0]]), written: $written} + parse_sections($parts[1:5])
    + optional_tail($parts[5:]);
