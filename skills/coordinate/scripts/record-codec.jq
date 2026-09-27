# record-codec.jq -- the coordinator record's one codec, both directions.
#
# The record is its visible markdown tables: there is no hidden copy. This file
# holds the section and column definitions, the cell encoding, the per-column
# grammars, and the render and parse functions for the record body and for the
# discipline handoff file. record-render.sh and record-parse.sh are thin bash
# wrappers that `include` it; a body is canonical only when rendering its parse
# reproduces it byte for byte, and record-parse.sh is where that is checked.
#
# Every refusal is a jq error() whose message starts with "refused: ", which
# the wrappers turn into exit 65.

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

def re_time_min: "^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}Z$";
def re_time_sec: "^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$";
def re_date: "^[0-9]{4}-[0-9]{2}-[0-9]{2}$";
def re_repo: "^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$";
def re_name: "^[A-Za-z0-9._-]+$";
def re_pr_url: "^https://github\\.com/[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+/pull/[0-9]+$";

# Columns a person may leave empty; every other column must hold a value.
def optional_cols: ["mode", "branch", "verified_head", "pull_request", "disposition"];

# Column names that would record what GitHub already knows.
def recomputable_names:
  ["status", "state", "ci", "checks", "checkstatus", "merge", "mergestate",
   "mergeable", "review", "reviewdecision"];

# Cell encoding, applied in this order so each step is reversible.
def enc:
  gsub("&"; "&amp;") | gsub("<"; "&lt;") | gsub(">"; "&gt;")
  | gsub("\\\\"; "&#92;") | gsub("\\|"; "\\|")
  | gsub("\r"; "&#13;") | gsub("\n"; "<br>")
  | sub("^ "; "&#32;") | sub("^\t"; "&#9;")
  | sub(" $"; "&#32;") | sub("\t$"; "&#9;");

def dec:
  gsub("&#9;"; "\t") | gsub("&#32;"; " ") | gsub("<br>"; "\n")
  | gsub("&#13;"; "\r") | gsub("\\\\\\|"; "|") | gsub("&#92;"; "\\")
  | gsub("&gt;"; ">") | gsub("&lt;"; "<") | gsub("&amp;"; "&");

def check_worker:
  if . == "" then refuse("worker: empty")
  elif test("/") then refuse("worker: contains '/', the shape of a path")
  elif test("[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}")
    or test("[0-9A-Fa-f]{32}") then refuse("worker: the shape of an instance or session id")
  elif test("^session_"; "i") then refuse("worker: the shape of a session id")
  elif test("\\+") then refuse("worker: the shape of an instance name")
  elif test("^[0-9]+$") then refuse("worker: the shape of a job id")
  elif (test("^[A-Za-z0-9][A-Za-z0-9._-]*$") | not) then refuse("worker: not a dispatch topic")
  else . end;

# names_repo($r): does this cell name repository $r (case-insensitive), as a
# whole owner/repo token rather than a substring of a longer name?
def names_repo($r):
  ascii_downcase as $v | ($r | ascii_downcase | gsub("\\."; "\\.")) as $l
  | $v | test("(^|[^A-Za-z0-9_.-])" + $l + "(\\.git)?\\.*($|[^A-Za-z0-9_.-])");

def check_cell($key; $private):
  . as $v
  | if ($v | type) != "string" then refuse("\($key): not a string")
    elif $v | test("[\\x00-\\x08\\x0b\\x0c\\x0e-\\x1f\\x7f]") then refuse("\($key): a control character")
    elif ($v == "") and (any(optional_cols[]; . == $key) | not) then refuse("\($key): empty")
    elif $v == "" then $v
    elif $key == "worker" then check_worker
    elif $key == "phase" then (if test("^(scoping-ahead|executing|held)$") then . else refuse("phase: not scoping-ahead, executing or held") end)
    elif $key == "dispatch_status" then (if test("^(dispatching|dispatched|dispatch-failed)$") then . else refuse("dispatch_status: not dispatching, dispatched or dispatch-failed") end)
    elif $key == "return_path" then (if test("^(message|leg [a-z0-9_][a-z0-9_-]{0,63}:[a-z0-9_-]+)$") then . else refuse("return_path: not `message` or `leg <request-id>:<leg>` (the word leg, a space, then the request and leg)") end)
    elif $key == "repo" then (if test(re_repo) then . else refuse("repo: not owner/repo") end)
    elif $key == "branch" then (if test("^[A-Za-z0-9._/-]+$") then . else refuse("branch: not a branch name") end)
    elif $key == "verified_head" then (if test("^[0-9a-f]{40}$") then . else refuse("verified_head: not a full sha") end)
    elif $key == "dispatched" then (if test(re_date) then . else refuse("dispatched: not YYYY-MM-DD") end)
    elif ($key == "raised" or $key == "attempted" or $key == "date") then (if test(re_time_min) then . else refuse("\($key): not YYYY-MM-DDTHH:MMZ") end)
    elif $key == "pull_request" then (if test("^\\[#[0-9]+\\]\\(https://github\\.com/[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+/pull/[0-9]+\\)$") then . else refuse("pull_request: not [#n](https://github.com/owner/repo/pull/n), or empty for none yet") end)
    elif $key == "disposition" then (if test("^(filed #[0-9]+|closed: [\\s\\S]+|carried [0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}Z: [\\s\\S]+)$") then . else refuse("disposition: not filed #<n>, closed: <reason> or carried <YYYY-MM-DDTHH:MMZ>: <reason>") end)
    else . end
  | if ($v != "") and (($key == "repo") or ($key == "pull_request") or ($key == "target"))
      and ([$private[] as $p | select($v | names_repo($p))] | length) > 0
    then refuse("\($key): names a repository that isn't public") else . end;

def check_row($sec; $private):
  . as $row
  | if type != "object" then refuse("\($sec.key): a row that isn't an object") else . end
  | ($sec.cols | map(.[0])) as $keys
  | ([keys[] | . as $k | select(any($keys[]; . == $k) | not)]) as $extra
  | if ($extra | length) > 0 then
      ($extra[0] | ascii_downcase | gsub("[-_ ]"; "")) as $n
      | if any(recomputable_names[]; . == $n)
        then refuse("\($sec.key).\($extra[0]): status, CI and merge-state columns are read from GitHub, never recorded")
        else refuse("\($sec.key).\($extra[0]): not a column of this section") end
    else . end
  | reduce $sec.cols[] as $c ({}; .[$c[0]] = (($row[$c[0]] // "") | check_cell($c[0]; $private)));

def scope_text($s):
  if ($s | type) != "object" then refuse("scope: missing")
  elif ($s.name // "" | test(re_name) | not) then refuse("scope.name: not a name")
  elif $s.kind == "roadmap" then "ROADMAP-\($s.name)"
  elif $s.kind == "discipline" then "the \($s.name) discipline"
  else refuse("scope.kind: not roadmap or discipline") end;

def declaration($s): "> This is a **coordinator record** for \(scope_text($s)).";

def pr_prefix($s):
  if $s.kind != "discipline" then refuse("container pr: only a discipline record is a pull request")
  else "Coordinator record for the \($s.name) discipline, kept on coordinate/discipline-\($s.name).\n\n---\n\n" end;

def render_table($sec; $rows):
  "## \($sec.title)\n\n"
  + if ($rows | length) == 0 then "None."
    else
      ("| " + ($sec.cols | map(.[1]) | join(" | ")) + " |") + "\n"
      + ("|" + ($sec.cols | map("---") | join("|")) + "|")
      + ($rows | map(. as $r | "\n| " + ($sec.cols | map($r[.[0]] | enc) | join(" | ")) + " |") | join(""))
    end;

def checked_sections($in; $private):
  sections | map(. as $sec
    | ($in[$sec.key] // []) as $rows
    | if ($rows | type) != "array" then refuse("\($sec.key): not a list") else . end
    | {sec: $sec, rows: ($rows | map(check_row($sec; $private)))});

def check_top($in; $allowed):
  ([$in | keys[] | . as $k | select(any($allowed[]; . == $k) | not)]) as $extra
  | if ($extra | length) > 0 then refuse("\($extra[0]): not a field of this format") else . end;

def render_record($container; $written; $private):
  . as $in
  | check_top($in; ["scope", "written", "holdings", "deferrals", "side_effects", "reversals"])
  | if ($written | test(re_time_sec) | not) then refuse("written: not YYYY-MM-DDTHH:MM:SSZ") else . end
  | (if $container == "pr" then pr_prefix($in.scope) elif $container == "issue" then "" else refuse("container: not issue or pr") end) as $prefix
  | $prefix + declaration($in.scope) + "\n\nWritten: \($written)\n\n"
    + (checked_sections($in; $private) | map(render_table(.sec; .rows)) | join("\n\n")) + "\n";

def predecessor_sentence: "The outgoing rotation's reasoning was not recorded.";

def render_handoff($private):
  . as $in
  | check_top($in; ["scope", "rotation", "holdings", "deferrals", "side_effects", "reversals", "reasoning", "predecessor_copy"])
  | if ($in.scope.kind // "") != "discipline" then refuse("handoff: only a discipline has a handoff") else . end
  | scope_text($in.scope) as $_
  | ($in.rotation // refuse("rotation: missing")) as $r
  | if ($r | keys) != ["date", "end", "host_repo", "record_url", "start"] then refuse("rotation: needs exactly start, end, date, host_repo, record_url") else . end
  | if ([$r.start, $r.end, $r.date] | all(test(re_date)) | not) then refuse("rotation: dates are not YYYY-MM-DD") else . end
  | if ($r.host_repo | test(re_repo) | not) then refuse("rotation.host_repo: not owner/repo") else . end
  | if ($r.record_url | test(re_pr_url) | not) then refuse("rotation.record_url: not a pull request URL") else . end
  | (if $in.predecessor_copy != null then
       if $in.reasoning != null then refuse("reasoning: a predecessor's reasoning is never written on its behalf")
       elif ($in.predecessor_copy | keys) != ["written"] or ($in.predecessor_copy.written | test(re_time_sec) | not)
         then refuse("predecessor_copy.written: not YYYY-MM-DDTHH:MM:SSZ")
       else {line: "As written by the previous rotation at \($in.predecessor_copy.written); not re-checked.\n\n", text: predecessor_sentence} end
     else
       (($in.reasoning // "") | sub("\\s+$"; "")) as $t
       | if $t == "" then refuse("reasoning: empty") elif $t == predecessor_sentence then refuse("reasoning: the fixed predecessor sentence is only written for a predecessor copy") else {line: "", text: $t} end
     end) as $reason
  | "# \($in.scope.name) handoff, \($r.date)\n\n"
    + "Rotation from \($r.start) to \($r.end). Host repository: \($r.host_repo). Record: \($r.record_url), kept on coordinate/discipline-\($in.scope.name).\n\n"
    + $reason.line
    + (checked_sections($in; $private) | map(render_table(.sec; .rows)) | join("\n\n"))
    + "\n\n## Reasoning for the next rotation\n\n" + $reason.text + "\n";

# ---- parsing ---------------------------------------------------------------

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

def parse_record:
  normalized | split("\n\n## ") as $parts
  | if ($parts | length) != 5 then refuse("expected four sections, found \(($parts | length) - 1)") else . end
  | ($parts[0] | split("\n")) as $head
  | ([$head | to_entries[] | select(.value | startswith("> This is a **coordinator record** for ")) | .key]) as $at
  | if ($at | length) != 1 then refuse("expected one declaration line") else . end
  | ($head[$at[0] + 2] // "") as $wline
  | ($wline | capture("^Written: (?<w>.*)$") // refuse("no Written: line")).w as $written
  | {scope: parse_scope($head[$at[0]]), written: $written} + parse_sections($parts[1:]);

def parse_handoff:
  normalized | split("\n\n## ") as $parts
  | if ($parts | length) < 6 then refuse("expected four sections and the reasoning") else . end
  | ($parts[5:] | join("\n\n## ")) as $rp
  | if ($rp | startswith("Reasoning for the next rotation\n\n") | not) then refuse("expected ## Reasoning for the next rotation last") else . end
  | ($rp[("Reasoning for the next rotation\n\n" | length):]) as $text
  | ($parts[0] | split("\n\n")) as $head
  | ($head[0] | capture("^# (?<n>[A-Za-z0-9._-]+) handoff, (?<d>.*)$") // refuse("no handoff heading")) as $h
  | (($head[1] // "") | capture("^Rotation from (?<s>[^ ]*) to (?<e>[^ ]*)\\. Host repository: (?<r>[^ ]*)\\. Record: (?<u>[^ ,]*), kept on coordinate/discipline-(?<n>[A-Za-z0-9._-]+)\\.$") // refuse("no rotation line")) as $i
  | ([($head[2] // "") | capture("^As written by the previous rotation at (?<w>.*); not re-checked\\.$")] | first) as $p
  | {scope: {kind: "discipline", name: $h.n},
     rotation: {start: $i.s, end: $i.e, date: $h.d, host_repo: $i.r, record_url: $i.u}}
    + (if $p != null and $text == predecessor_sentence then {predecessor_copy: {written: $p.w}} else {reasoning: $text} end)
    + parse_sections($parts[1:5]);
