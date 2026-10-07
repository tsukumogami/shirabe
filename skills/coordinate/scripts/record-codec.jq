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
# A dispatch topic, the Worker cell's shape: record-common.sh's RE_TOPIC, the
# grammar every bash script holds a topic to.
def re_topic: "^[A-Za-z0-9][A-Za-z0-9._-]*$";

# pr_link_parts: a Pull request cell `[#a](https://github.com/o/r/pull/b)` as
# {a, r, b}, or nothing for any other value. The one jq parser of the cell
# (record-common.sh lib_pr_link is the bash one); scripts outside the codec
# reach it with `jq -L <scripts dir> 'include "record-codec"; ...'`.
def pr_link_parts:
  strings | capture("^\\[#(?<a>[0-9]+)\\]\\(https://github\\.com/(?<r>[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+)/pull/(?<b>[0-9]+)\\)$");
# pr_link: the cell as {repo, number} when its two numbers agree, else nothing.
def pr_link: pr_link_parts | select(.a == .b) | {repo: .r, number: .a};

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
  elif (test(re_topic) | not) then refuse("worker: not a dispatch topic")
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
    elif $key == "pull_request" then (if ([pr_link_parts] | length) > 0 then . else refuse("pull_request: not [#n](https://github.com/owner/repo/pull/n), or empty for none yet") end)
    elif $key == "disposition" then (if test("^(filed #[0-9]+|closed: [\\s\\S]+|carried [0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}Z( until [0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}Z)?: [\\s\\S]+)$") then . else refuse("disposition: not filed #<n>, closed: <reason> or carried <YYYY-MM-DDTHH:MMZ> [until <YYYY-MM-DDTHH:MMZ>]: <reason>") end)
    else . end
  | if ($v != "") and (($key == "repo") or ($key == "pull_request") or ($key == "target")) then
      ([$private[] as $p | select($v | names_repo($p)) | $p] | first) as $hit
      | if $hit != null then refuse("\($key): names \($hit), a repository that isn't public") else . end
    else . end;

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

# ---- the Holds section ------------------------------------------------------
#
# Holds on merges, each a condition the land step evaluates live
# (docs/designs/current/DESIGN-coordinate-merge-policy.md, Decision 6). Like
# Decisions, it sits after Reversals and renders only when it has a row, so a
# record written before the section existed parses with no `holds` key and
# renders back to the same bytes. Only record-hold.sh adds or lifts a hold.
#
#   Hold     a short name, unique in the section
#   On       the held pull request, owner/repo#n
#   Until    `merged owner/repo#m` (another pull request merges),
#            `tag owner/repo <tag>` (a release is tagged), or `lifted` (a
#            person lifts it)
#   Set by   who asked for the hold, in words
#   Set      when, YYYY-MM-DDTHH:MMZ
#   Lifted   blank while it stands; `<YYYY-MM-DDTHH:MMZ> by <who>` once a
#            person lifted it (only a `lifted` hold is lifted by hand)

def holds_title: "Holds";
def holds_cols: [
  ["hold", "Hold"], ["on", "On"], ["until", "Until"], ["set_by", "Set by"],
  ["set", "Set"], ["lifted", "Lifted"]];
def re_pr_ref: "^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+#[1-9][0-9]*$";
def re_tag: "^[A-Za-z0-9][A-Za-z0-9._+-]*$";

def check_hcell($key; $private):
  . as $v
  | if ($v | type) != "string" then refuse("holds.\($key): not a string")
    elif $v | test("[\\x00-\\x08\\x0b\\x0c\\x0e-\\x1f\\x7f]") then refuse("holds.\($key): a control character")
    elif ($v | test("[\r\n]")) then refuse("holds.\($key): a line break")
    elif $v == "" and $key != "lifted" then refuse("holds.\($key): empty")
    elif $v == "" then $v
    elif $key == "hold" then (if test(re_name) then . else refuse("holds.hold: not a short name") end)
    elif $key == "on" then (if test(re_pr_ref) then . else refuse("holds.on: not owner/repo#n") end)
    elif $key == "until" then
      (if . == "lifted" then .
       elif (split(" ") | length == 2 and .[0] == "merged" and (.[1] | test(re_pr_ref))) then .
       elif (split(" ") | length == 3 and .[0] == "tag" and (.[1] | test(re_repo)) and (.[2] | test(re_tag))) then .
       else refuse("holds.until: not `merged owner/repo#n`, `tag owner/repo <tag>` or `lifted`") end)
    elif $key == "set" then (if test(re_time_min) then . else refuse("holds.set: not YYYY-MM-DDTHH:MMZ") end)
    elif $key == "lifted" then (if test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}Z by .+$") then . else refuse("holds.lifted: not `<YYYY-MM-DDTHH:MMZ> by <who>`") end)
    else . end
  | if ($v != "") and ($key == "on" or $key == "until") then
      ([$private[] as $p | select($v | names_repo($p)) | $p] | first) as $hit
      | if $hit != null then refuse("holds.\($key): names \($hit), a repository that isn't public") else . end
    else . end;

def check_holds($h; $private):
  if $h == null then null
  elif ($h | type) != "array" then refuse("holds: not a list")
  else
    ($h | map(. as $row
      | if type != "object" then refuse("holds: a row that isn't an object") else . end
      | ([keys[] | . as $k | select(any(holds_cols[]; .[0] == $k) | not)]) as $extra
      | if ($extra | length) > 0 then refuse("holds.\($extra[0]): not a column of this section") else . end
      | reduce holds_cols[] as $c ({}; .[$c[0]] = (($row[$c[0]] // "") | check_hcell($c[0]; $private)))
      | if .lifted != "" and .until != "lifted" then refuse("holds: \(.hold): only a `lifted` hold is lifted by hand") else . end)) as $rows
    | if ($rows | map(.hold) | unique | length) != ($rows | length) then refuse("holds: a hold name is used twice") else $rows end
  end;

def render_holds($h):
  if $h == null or ($h | length) == 0 then ""
  else
    "\n\n## \(holds_title)\n\n"
    + ("| " + (holds_cols | map(.[1]) | join(" | ")) + " |") + "\n"
    + ("|" + (holds_cols | map("---") | join("|")) + "|")
    + ($h | map(. as $r | "\n| " + (holds_cols | map($r[.[0]] | enc) | join(" | ")) + " |") | join(""))
  end;

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

# ---- the Decisions section --------------------------------------------------
#
# A fifth section, after Reversals, rendered only when it has something to
# hold: an entry, or a `Next decision` above 1. A record written before the
# section existed has none, parses to no `decisions` key, and renders back to
# the same bytes. `Next decision` never goes down, so a record changes shape
# once, at its first entry, and never toggles back: a section holding
# `Next decision: 1` and no entry renders to nothing, and the canonical check
# refuses it.
#
# Its cells are looked up by this section's own grammars (check_dcell), so its
# `reason`, `target` and `state` columns neither take nor disturb the grammars
# of the other sections' columns of the same names. Only record-decision.sh
# changes the section; record-write.sh and record-open.sh refuse any change.

def decisions_title: "Decisions";
def decisions_cols: [
  ["decision", "Decision"], ["round", "Round"], ["question", "Question"],
  ["options", "Options"], ["state", "State"], ["source", "Source"],
  ["verdict", "Verdict"], ["recommendation", "Recommendation"], ["reason", "Reason"],
  ["context", "Context"], ["problem", "Problem"], ["grounds", "Grounds"],
  ["target", "Target"], ["owed", "Owed"], ["asked", "Asked"],
  ["evidence", "Evidence"], ["outcome", "Outcome"], ["decided_by", "Decided by"],
  ["updated", "Updated"]];

def d_states: ["proposed", "coordinator-verdict", "escalated", "settled"];
def d_grounds: ["scope", "supplied-decision", "reserved-step", "outside-scope"];
# The columns a person or the coordinator writes in words: a public host's
# check reads them, and `@` is encoded in them so a record never mentions
# anyone.
def d_text_cols: ["question", "options", "recommendation", "reason", "context",
  "problem", "evidence", "outcome", "decided_by"];
# A stamp names the run (the UTC stamp in the session's name) and the visit
# that caused a write, so no run's write is mistaken for another's.
def re_stamp: "\\[[0-9]{8}T[0-9]{6}Z (report|wait|raise|hold|redirect|ask) [1-9][0-9]*(\\.[1-9][0-9]*)?\\]";

def enc_d: enc | gsub("@"; "&#64;");
def dec_d: gsub("&#64;"; "@") | dec;

# Free text a person reads on a public host: a Decisions text column, or a
# record entry (record-append.sh). text_named_repos lists the repositories the
# text names unambiguously, a github.com/<owner>/<repo> link or
# <owner>/<repo>#<n>, since in prose "and/or" or "CI/CD" is not a repository;
# the caller reads each one's visibility. text_problem($private) is null, or
# what makes the text unfit: a repository on the $private list, a
# home-directory path or a token-shaped string.
def text_named_repos:
  def clean: sub("\\.git$"; "") | sub("\\.+$"; "");
  [ (scan("github\\.com/([A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+)") | .[0] | clean),
    (gsub("[A-Za-z][A-Za-z0-9+.-]*://[^\\s)\\]>]*"; " ")
     | scan("(?:^|[\\s(\\[<,;:])([A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+)#[0-9]") | .[0] | clean) ]
  | map(select(. != "")) | unique;
def text_problem($private):
  . as $v
  | ([$private[] as $p | select($v | names_repo($p)) | $p] | first) as $hit
  | if $hit != null then "names \($hit), a repository that isn't public"
    elif ($v | test("(^|[\\s(\"'`])(/home/|/Users/)[^/[:space:]]")) then "a home-directory path"
    elif ($v | test("(^|[^A-Za-z0-9_-])(gh[pousr]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}|sk-[A-Za-z0-9_-]{20,}|xox[abprs]-[A-Za-z0-9-]{10,})")) then "a token-shaped string"
    else null end;

# check_dcell($key; $private): one Decisions cell, by this section's grammars.
def check_dcell($key; $private):
  . as $v
  | if ($v | type) != "string" then refuse("decisions.\($key): not a string")
    elif $v | test("[\\x00-\\x08\\x0b\\x0c\\x0e-\\x1f\\x7f]") then refuse("decisions.\($key): a control character")
    elif ($v | test("\r")) then refuse("decisions.\($key): a carriage return")
    elif ($v != "") and (($key != "options") and ($key != "evidence")) and ($v | test("\n")) then refuse("decisions.\($key): a line break inside a single item")
    elif $v == "" then $v
    elif $key == "decision" then (if test("^[1-9][0-9]*$") then . else refuse("decisions.decision: not a positive integer") end)
    elif $key == "round" then (if test("^(0|[1-9][0-9]*)$") then . else refuse("decisions.round: not a count") end)
    elif $key == "state" then (if any(d_states[]; . == $v) then . else refuse("decisions.state: not proposed, coordinator-verdict, escalated or settled") end)
    elif $key == "source" then (if test("^(worker [A-Za-z0-9][A-Za-z0-9._-]*|coordinator [A-Za-z0-9][A-Za-z0-9._-]* #[1-9][0-9]* round [1-9][0-9]*|dispatcher|self) " + re_stamp + "$") then . else refuse("decisions.source: not `worker <topic>`, `coordinator <topic> #<n> round <r>`, `dispatcher` or `self`, then a stamp") end)
    elif $key == "verdict" then (if test("^(settle|escalate|hold)$") then . else refuse("decisions.verdict: not settle, escalate or hold") end)
    elif $key == "grounds" then (if (split(", ") | all(. as $g | any(d_grounds[]; . == $g))) then . else refuse("decisions.grounds: not a comma list of \(d_grounds | join(", "))") end)
    elif $key == "target" then (if test("^(a person|coordinator [A-Za-z0-9][A-Za-z0-9._-]*)$") then . else refuse("decisions.target: not `a person` or `coordinator <topic>`") end)
    elif $key == "owed" then (if test("^(escalation|withdrawal|reply)$") then . else refuse("decisions.owed: not escalation, withdrawal or reply") end)
    elif ($key == "asked" or $key == "updated") then (if test(re_time_min) then . else refuse("decisions.\($key): not YYYY-MM-DDTHH:MMZ") end)
    elif $key == "options" then (if (split("\n") | all(length > 0)) then . else refuse("decisions.options: an empty option") end)
    elif $key == "evidence" then (if (split("\n") | all(test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}Z [^\\[]+ " + re_stamp + ": .+$"))) then . else refuse("decisions.evidence: a line that isn't `<time> <source> <stamp>: <text>`") end)
    else . end
  | if ($v != "") and any(d_text_cols[]; . == $key) then
      ($v | text_problem($private)) as $why
      | if $why != null then refuse("decisions.\($key): \($why)") else . end
    else . end;

# escalation_problems($target): what keeps a recorded escalate verdict from
# being escalated to $target, as a list (empty when it may be). The one
# validator record-decision.sh and decision-render.sh share.
#
# An escalated entry's Options lines each carry an explanation, written
# `<option> -- <explanation>` so the column's grammar is unchanged; the
# recommendation names the option part. d_options gives them as
# {label, explanation}, in the record's order.
def d_options:
  (.options // "") | split("\n") | map(select(length > 0)
    | split(" -- ") as $p | {label: $p[0], explanation: ($p[1:] | join(" -- "))});
def escalation_problems($target):
  def blank: (. // "") | gsub("^\\s+|\\s+$"; "") | . == "";
  . as $e
  | [ (if ([$e | d_options[].label] | index($e.recommendation // "")) == null then "the recommendation is not one of the options" else empty end),
      (if any($e | d_options[]; .explanation | blank) then "an option has no explanation" else empty end),
      (if ($e.reason | blank) then "the reason is empty" else empty end),
      (if ($e.context | blank) then "the context is empty" else empty end),
      (if ($e.problem | blank) then "the problem is empty" else empty end),
      (if ($e.grounds | blank) then "no ground" else empty end),
      (if ($e.target // "") != $target then "the target is not the run's (\($target))" else empty end) ];

# The stamps an entry carries, by position: the one ending its Source, and the
# one after each Evidence line's source. A stamp-like string inside a line's
# text is not a stamp. Each is {run, kind, seq, text}; text is the Evidence
# line's text, "" for the Source's.
def d_stamps:
  [ ((.source // "") | capture(" \\[(?<run>[0-9]{8}T[0-9]{6}Z) (?<kind>[a-z]+) (?<seq>[0-9.]+)\\]$") | . + {text: ""}),
    ((.evidence // "") | split("\n")[] | select(length > 0)
      | capture("^[^ ]+ [^\\[]+ \\[(?<run>[0-9]{8}T[0-9]{6}Z) (?<kind>[a-z]+) (?<seq>[0-9.]+)\\]: (?<text>.*)$")) ];
# The text of the Evidence line that marks an extracted question as addressed
# to a person, stamped with the report that carried it. A report with one owes
# its worker a redirect; decision-next.sh routes it, decision-render.sh renders
# it, and record-decision.sh --open-from-report writes the mark.
def d_addressed_mark: "addressed to a person";

# compact_settled: a settled entry that owes nothing keeps its identity, round,
# question, options, source, outcome, who decided, when, and its redirect
# lines; every other cell is blanked. `Next decision` keeps its identifier from
# being reused.
def compact_settled:
  if .state == "settled" and (.owed // "") == "" then
    . as $e | reduce (decisions_cols[] | .[0]) as $k ({}; .[$k] = "")
    | .decision = $e.decision | .round = $e.round | .question = $e.question
    | .options = $e.options
    | .state = "settled" | .source = $e.source | .outcome = $e.outcome
    | .decided_by = $e.decided_by | .updated = $e.updated
    # Options stay because evidence can reopen a settled entry, which then
    # needs them to be escalated again; a redirect line stays because losing it
    # would owe the report's redirect a second time.
    | .evidence = ([($e.evidence // "") | split("\n")[]
        | select(test("^[^ ]+ [^\\[]+ \\[[0-9]{8}T[0-9]{6}Z redirect [0-9]+\\]: "))] | join("\n"))
  else . end;

def check_drow($private):
  . as $row
  | if type != "object" then refuse("decisions: a row that isn't an object") else . end
  | (decisions_cols | map(.[0])) as $keys
  | ([keys[] | . as $k | select(any($keys[]; . == $k) | not)]) as $extra
  | if ($extra | length) > 0 then refuse("decisions.\($extra[0]): not a column of this section") else . end
  | (reduce decisions_cols[] as $c ({}; .[$c[0]] = (($row[$c[0]] // "") | check_dcell($c[0]; $private)))) as $r
  | def need($ks; $why): ($ks | map(select(($r[.] // "") == "")) | first) as $m
      | if $m != null then refuse("decisions: entry \($r.decision): \($m) is empty, and \($why)") else . end;
    ($r | need(["decision", "round", "question", "state", "source", "updated"]; "every entry needs it"))
  | if $r.state == "escalated" then need(["options", "recommendation", "reason", "context", "problem", "grounds", "target"]; "an escalated entry needs it")
    elif $r.state == "settled" then need(["outcome", "decided_by"]; "a settled entry needs it")
    elif $r.state == "proposed" then need(["options"]; "a proposed entry needs it")
    elif $r.verdict == "hold" then need(["reason"]; "a held verdict needs what it waits on")
    else . end
  | if $r.state == "proposed" and $r.verdict != ""
    then refuse("decisions: entry \($r.decision): a proposed entry has no verdict yet") else . end
  | if $r.verdict == "hold" and $r.state != "coordinator-verdict"
    then refuse("decisions: entry \($r.decision): only an entry awaiting a verdict can be held") else . end
  | $r;

# check_decisions($d; $private): the section's JSON, checked; null when absent.
def check_decisions($d; $private):
  if $d == null then null
  elif ($d | type) != "object" then refuse("decisions: not an object")
  elif (($d | keys) - ["entries", "next"]) != [] then refuse("decisions.\((($d | keys) - ["entries", "next"])[0]): not a field of this section")
  elif ($d.next | type) != "number" or $d.next < 1 or $d.next > 999999 or ($d.next | floor) != $d.next then refuse("decisions.next: not a positive integer below a million")
  elif (($d.entries // []) | type) != "array" then refuse("decisions.entries: not a list")
  else
    ($d.entries // [] | map(check_drow($private))) as $rows
    | ($rows | map(.decision | tonumber)) as $ids
    | if ($ids | unique | length) != ($ids | length) then refuse("decisions: an identifier is used twice")
      elif any($ids[]; . >= $d.next) then refuse("decisions: an identifier at or above Next decision (\($d.next))")
      # floor: a number written 7.0 or 7e0 renders as 7, the one form the
      # parser reads back.
      else {next: ($d.next | floor), entries: $rows} end
  end;

def render_decisions($d):
  if $d == null or (($d.entries | length) == 0 and $d.next == 1) then ""
  else
    "\n\n## \(decisions_title)\n\nNext decision: \($d.next)\n\n"
    + if ($d.entries | length) == 0 then "None."
      else
        ("| " + (decisions_cols | map(.[1]) | join(" | ")) + " |") + "\n"
        + ("|" + (decisions_cols | map("---") | join("|")) + "|")
        + ($d.entries | map(. as $r | "\n| " + (decisions_cols | map(.[0] as $k | $r[$k] | if any(d_text_cols[]; . == $k) then enc_d else enc end) | join(" | ")) + " |") | join(""))
      end
  end;

def parse_decisions($p):
  if ($p | startswith(decisions_title + "\n\n") | not) then refuse("expected ## \(decisions_title) after Reversals") else . end
  | ($p[(decisions_title | length) + 2:]) as $body
  | ($body | capture("^Next decision: (?<n>[1-9][0-9]*)\n\n(?<rest>[\\s\\S]*)$") // refuse("Decisions: no `Next decision: <n>` line")) as $m
  | {next: ($m.n | tonumber), entries:
      (if $m.rest == "None." then []
       else ($m.rest | split("\n")) as $lines
       | ("| " + (decisions_cols | map(.[1]) | join(" | ")) + " |") as $header
       | if ($lines | length) < 3 then refuse("Decisions: a table needs a header, a separator and a row, or None.")
         elif $lines[0] != $header then refuse("Decisions: header row differs from the fixed columns")
         else $lines[2:] | map(
           (if (startswith("| ") and endswith(" |")) | not then refuse("table row: not | cell | ... |") else . end
            | .[2:-2] | gsub("\\\\\\|"; "\u001f") | split(" | ") | map(gsub("\u001f"; "\\|") | dec_d)) as $cells
           | if ($cells | length) != (decisions_cols | length) then refuse("Decisions: a row with \($cells | length) cells, not \(decisions_cols | length)")
             else [range(0; decisions_cols | length) as $i | {(decisions_cols[$i][0]): $cells[$i]}] | add end)
         end
       end)};

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
  | check_top($in; ["scope", "written", "holdings", "deferrals", "side_effects", "reversals", "holds", "decisions"])
  | if ($written | test(re_time_sec) | not) then refuse("written: not YYYY-MM-DDTHH:MM:SSZ") else . end
  | (if $container == "pr" then pr_prefix($in.scope) elif $container == "issue" then "" else refuse("container: not issue or pr") end) as $prefix
  | $prefix + declaration($in.scope) + "\n\nWritten: \($written)\n\n"
    + (checked_sections($in; $private) | map(render_table(.sec; .rows)) | join("\n\n"))
    + render_holds(check_holds($in.holds; $private))
    + render_decisions(check_decisions($in.decisions; $private)) + "\n";

def predecessor_sentence: "The outgoing rotation's reasoning was not recorded.";

def render_handoff($private):
  . as $in
  | check_top($in; ["scope", "rotation", "holdings", "deferrals", "side_effects", "reversals", "holds", "decisions", "reasoning", "predecessor_copy"])
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
    # Holds carry over as they stand: a hold outlives the rotation that set it.
    + render_holds(check_holds($in.holds; $private))
    # The handoff carries only the unsettled entries, with the same Next
    # decision, so the next rotation's record continues the numbering; a
    # predecessor copy is copied as it stands.
    + render_decisions(check_decisions($in.decisions; $private)
        | if . == null or $in.predecessor_copy != null then . else .entries |= map(select(.state != "settled")) end)
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

# optional_tail($rest): the parts after the four sections, each an optional
# Holds then an optional Decisions, in that order, as {holds?, decisions?}.
def optional_tail($rest):
  ($rest | map(select(startswith(holds_title + "\n\n")))) as $h
  | ($rest | map(select(startswith(decisions_title + "\n\n")))) as $d
  | if ($h | length) + ($d | length) != ($rest | length) or ($h | length) > 1 or ($d | length) > 1
    then refuse("after Reversals, only ## \(holds_title) and then ## \(decisions_title) may follow")
    elif ($h | length) == 1 and ($d | length) == 1 and ($rest[0] | startswith(holds_title + "\n\n") | not)
    then refuse("## \(holds_title) comes before ## \(decisions_title)")
    else (if ($h | length) == 1 then {holds: parse_holds($h[0])} else {} end)
         + (if ($d | length) == 1 then {decisions: parse_decisions($d[0])} else {} end) end;

def parse_record:
  normalized | split("\n\n## ") as $parts
  | if ($parts | length) < 5 or ($parts | length) > 7 then refuse("expected four sections, then an optional Holds and an optional Decisions, found \(($parts | length) - 1)") else . end
  | ($parts[0] | split("\n")) as $head
  | ([$head | to_entries[] | select(.value | startswith("> This is a **coordinator record** for ")) | .key]) as $at
  | if ($at | length) != 1 then refuse("expected one declaration line") else . end
  | ($head[$at[0] + 2] // "") as $wline
  | ($wline | capture("^Written: (?<w>.*)$") // refuse("no Written: line")).w as $written
  | {scope: parse_scope($head[$at[0]]), written: $written} + parse_sections($parts[1:5])
    + optional_tail($parts[5:]);

def parse_handoff:
  normalized | split("\n\n## ") as $parts
  | if ($parts | length) < 6 then refuse("expected four sections and the reasoning") else . end
  | ([$parts[5:] | to_entries[] | select((.value | startswith(holds_title + "\n\n") or startswith(decisions_title + "\n\n")) | not) | .key] | first // ($parts[5:] | length)) as $n_opt
  | ($parts[5:5 + $n_opt]) as $opt
  | if ($parts | length) < 6 + $n_opt then refuse("expected the reasoning after the record's sections") else . end
  | ($parts[5 + $n_opt:] | join("\n\n## ")) as $rp
  | if ($rp | startswith("Reasoning for the next rotation\n\n") | not) then refuse("expected ## Reasoning for the next rotation last") else . end
  | ($rp[("Reasoning for the next rotation\n\n" | length):]) as $text
  | ($parts[0] | split("\n\n")) as $head
  | ($head[0] | capture("^# (?<n>[A-Za-z0-9._-]+) handoff, (?<d>.*)$") // refuse("no handoff heading")) as $h
  | (($head[1] // "") | capture("^Rotation from (?<s>[^ ]*) to (?<e>[^ ]*)\\. Host repository: (?<r>[^ ]*)\\. Record: (?<u>[^ ,]*), kept on coordinate/discipline-(?<n>[A-Za-z0-9._-]+)\\.$") // refuse("no rotation line")) as $i
  | ([($head[2] // "") | capture("^As written by the previous rotation at (?<w>.*); not re-checked\\.$")] | first) as $p
  | {scope: {kind: "discipline", name: $h.n},
     rotation: {start: $i.s, end: $i.e, date: $h.d, host_repo: $i.r, record_url: $i.u}}
    + (if $p != null and $text == predecessor_sentence then {predecessor_copy: {written: $p.w}} else {reasoning: $text} end)
    + parse_sections($parts[1:5])
    + optional_tail($opt);
